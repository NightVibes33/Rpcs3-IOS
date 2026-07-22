#include "RPCS3IOSGSFrame.h"

#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>

#include <atomic>
#include <mutex>

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

void update_metrics_locked(RPCS3IOSMetalView* view)
{
    if (!view)
    {
        return;
    }

    const CGFloat scale = view.window.screen.scale > 0.0 ? view.window.screen.scale : UIScreen.mainScreen.scale;
    const CGSize points = view.bounds.size;
    const int pixel_width = static_cast<int>(points.width * scale);
    const int pixel_height = static_cast<int>(points.height * scale);
    const double refresh = view.window.screen.maximumFramesPerSecond > 0
        ? static_cast<double>(view.window.screen.maximumFramesPerSecond)
        : 60.0;

    g_pixel_width.store(pixel_width > 0 ? pixel_width : 1280, std::memory_order_release);
    g_pixel_height.store(pixel_height > 0 ? pixel_height : 720, std::memory_order_release);
    g_refresh_rate.store(refresh, std::memory_order_release);

    CAMetalLayer* layer = (CAMetalLayer*)view.layer;
    layer.contentsScale = scale;
    layer.drawableSize = CGSizeMake(
        static_cast<CGFloat>(g_pixel_width.load(std::memory_order_relaxed)),
        static_cast<CGFloat>(g_pixel_height.load(std::memory_order_relaxed)));
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
            metal_view.frame = metal_view.superview.bounds;
            update_metrics_locked(metal_view);
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
        // RPCS3's Vulkan backend presents directly through VK_EXT_metal_surface.
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

namespace rpcs3::ios
{
bool attach_render_view(void* native_view)
{
    if (!native_view)
    {
        return false;
    }

    __block bool attached = false;
    run_on_main_sync(^{
        UIView* host = (__bridge UIView*)native_view;
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

        update_metrics_locked(g_metal_view);
        attached = true;
    });
    return attached;
}

void detach_render_view()
{
    run_on_main_sync(^{
        std::lock_guard lock(g_surface_mutex);
        [g_metal_view removeFromSuperview];
        g_metal_view = nil;
    });
}

bool render_view_ready()
{
    std::lock_guard lock(g_surface_mutex);
    return g_metal_view != nil;
}

std::unique_ptr<GSFrameBase> make_gs_frame()
{
    std::lock_guard lock(g_surface_mutex);
    if (!g_metal_view)
    {
        return {};
    }

    return std::make_unique<RPCS3IOSGSFrame>((__bridge void*)g_metal_view);
}
} // namespace rpcs3::ios
