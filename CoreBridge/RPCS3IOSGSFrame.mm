#include "RPCS3IOSGSFrame.h"

#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>

#include <atomic>
#include <mutex>
#include <utility>

@interface RPCS3IOSMetalView : UIView
@end

@implementation RPCS3IOSMetalView
+ (Class)layerClass
{
    return CAMetalLayer.class;
}
@end

namespace
{
std::mutex g_surface_mutex;
RPCS3IOSMetalView* g_metal_view = nil;
std::atomic<int> g_pixel_width{1280};
std::atomic<int> g_pixel_height{720};
std::atomic<double> g_refresh_rate{60.0};

void run_on_main_sync(void (^operation)(void))
{
    if (NSThread.isMainThread)
    {
        operation();
    }
    else
    {
        dispatch_sync(dispatch_get_main_queue(), operation);
    }
}

void run_on_main_async(void (^operation)(void))
{
    if (NSThread.isMainThread)
    {
        operation();
    }
    else
    {
        dispatch_async(dispatch_get_main_queue(), operation);
    }
}

void update_layer_metrics(RPCS3IOSMetalView* view, int pixel_width, int pixel_height)
{
    if (!view)
    {
        return;
    }

    CAMetalLayer* layer = static_cast<CAMetalLayer*>(view.layer);
    layer.contentsScale = UIScreen.mainScreen.scale;
    layer.drawableSize = CGSizeMake(static_cast<CGFloat>(pixel_width), static_cast<CGFloat>(pixel_height));
    layer.framebufferOnly = NO;
    layer.opaque = YES;
    layer.presentsWithTransaction = NO;
    if (@available(iOS 11.2, *))
    {
        layer.maximumDrawableCount = 3;
    }
}

class RPCS3IOSGSFrame final : public GSFrameBase
{
public:
    explicit RPCS3IOSGSFrame(void* view) noexcept
        : m_view(view)
    {
    }

    void close() override
    {
        hide();
    }

    void reset() override
    {
    }

    bool shown() override
    {
        return m_shown.load(std::memory_order_acquire);
    }

    void hide() override
    {
        m_shown.store(false, std::memory_order_release);
        void* view = m_view;
        run_on_main_async(^{
            RPCS3IOSMetalView* metal_view = (__bridge RPCS3IOSMetalView*)view;
            metal_view.hidden = YES;
        });
    }

    void show() override
    {
        m_shown.store(true, std::memory_order_release);
        void* view = m_view;
        run_on_main_async(^{
            RPCS3IOSMetalView* metal_view = (__bridge RPCS3IOSMetalView*)view;
            metal_view.hidden = NO;
            [metal_view.superview bringSubviewToFront:metal_view];
        });
    }

    void toggle_fullscreen() override
    {
        show();
    }

    void delete_context(draw_context_t) override
    {
    }

    draw_context_t make_context() override
    {
        return m_view;
    }

    void set_current(draw_context_t) override
    {
    }

    void flip(draw_context_t, bool) override
    {
        // VKGSRender presents directly through the CAMetalLayer-backed Vulkan swapchain.
    }

    int client_width() override
    {
        return g_pixel_width.load(std::memory_order_acquire);
    }

    int client_height() override
    {
        return g_pixel_height.load(std::memory_order_acquire);
    }

    f64 client_display_rate() override
    {
        return g_refresh_rate.load(std::memory_order_acquire);
    }

    bool has_alpha() override
    {
        return false;
    }

    display_handle_t handle() const override
    {
        return m_view;
    }

    bool can_consume_frame() const override
    {
        return false;
    }

    void present_frame(std::vector<u8>&&, u32, u32, u32, bool) const override
    {
    }

    void take_screenshot(std::vector<u8>&&, u32, u32, bool) override
    {
    }

    void update_title(double) override
    {
    }

private:
    void* m_view = nullptr;
    std::atomic<bool> m_shown{false};
};
} // namespace

int rpcs3_ios_attach_metal_view(void* host_view, int pixel_width, int pixel_height, double refresh_rate)
{
    if (!host_view || pixel_width <= 0 || pixel_height <= 0)
    {
        return 0;
    }

    __block int attached = 0;
    run_on_main_sync(^{
        UIView* host = (__bridge UIView*)host_view;
        if (!host)
        {
            return;
        }

        std::lock_guard lock(g_surface_mutex);
        if (!g_metal_view || g_metal_view.superview != host)
        {
            [g_metal_view removeFromSuperview];
            g_metal_view = [[RPCS3IOSMetalView alloc] initWithFrame:host.bounds];
            g_metal_view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            g_metal_view.backgroundColor = UIColor.blackColor;
            g_metal_view.opaque = YES;
            g_metal_view.hidden = YES;
            [host addSubview:g_metal_view];
        }
        else
        {
            g_metal_view.frame = host.bounds;
        }

        g_pixel_width.store(pixel_width, std::memory_order_release);
        g_pixel_height.store(pixel_height, std::memory_order_release);
        g_refresh_rate.store(refresh_rate > 0.0 ? refresh_rate : 60.0, std::memory_order_release);
        update_layer_metrics(g_metal_view, pixel_width, pixel_height);
        attached = 1;
    });
    return attached;
}

void rpcs3_ios_update_metal_view_metrics(int pixel_width, int pixel_height, double refresh_rate)
{
    if (pixel_width <= 0 || pixel_height <= 0)
    {
        return;
    }

    g_pixel_width.store(pixel_width, std::memory_order_release);
    g_pixel_height.store(pixel_height, std::memory_order_release);
    if (refresh_rate > 0.0)
    {
        g_refresh_rate.store(refresh_rate, std::memory_order_release);
    }

    run_on_main_async(^{
        std::lock_guard lock(g_surface_mutex);
        if (g_metal_view)
        {
            g_metal_view.frame = g_metal_view.superview.bounds;
            update_layer_metrics(g_metal_view, pixel_width, pixel_height);
        }
    });
}

bool rpcs3_ios_has_metal_view()
{
    std::lock_guard lock(g_surface_mutex);
    return g_metal_view != nil;
}

std::unique_ptr<GSFrameBase> rpcs3_ios_make_gs_frame()
{
    std::lock_guard lock(g_surface_mutex);
    if (!g_metal_view)
    {
        return {};
    }

    return std::make_unique<RPCS3IOSGSFrame>((__bridge void*)g_metal_view);
}
