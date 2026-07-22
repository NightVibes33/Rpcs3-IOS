#include "RPCS3IOSGSFrame.h"

#include "Emu/RSX/GSFrameBase.h"

#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>

#include <atomic>
#include <utility>

namespace
{
__strong UIView* g_host_view = nil;
__strong CAMetalLayer* g_metal_layer = nil;
std::atomic<void*> g_layer_handle{nullptr};
std::atomic<int> g_drawable_width{1};
std::atomic<int> g_drawable_height{1};
std::atomic<int> g_display_rate{60};
std::atomic<bool> g_layer_visible{false};

void run_on_main_sync(dispatch_block_t block)
{
    if ([NSThread isMainThread])
    {
        block();
    }
    else
    {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

void run_on_main_async(dispatch_block_t block)
{
    if ([NSThread isMainThread])
    {
        block();
    }
    else
    {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

void update_geometry_on_main()
{
    if (!g_host_view || !g_metal_layer)
    {
        return;
    }

    const CGFloat scale = g_host_view.window.screen.scale > 0.0
        ? g_host_view.window.screen.scale
        : UIScreen.mainScreen.scale;
    const CGRect bounds = g_host_view.bounds;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    g_metal_layer.frame = bounds;
    g_metal_layer.contentsScale = scale;
    g_metal_layer.drawableSize = CGSizeMake(
        MAX(bounds.size.width * scale, 1.0),
        MAX(bounds.size.height * scale, 1.0));
    [CATransaction commit];

    g_drawable_width.store(static_cast<int>(g_metal_layer.drawableSize.width), std::memory_order_release);
    g_drawable_height.store(static_cast<int>(g_metal_layer.drawableSize.height), std::memory_order_release);
    g_display_rate.store(static_cast<int>(g_host_view.window.screen.maximumFramesPerSecond ?: 60), std::memory_order_release);
}

class ios_gs_frame final : public GSFrameBase
{
public:
    void close() override
    {
        hide();
    }

    void reset() override
    {
        run_on_main_async(^{ update_geometry_on_main(); });
    }

    bool shown() override
    {
        return g_layer_visible.load(std::memory_order_acquire);
    }

    void hide() override
    {
        run_on_main_async(^{
            g_metal_layer.hidden = YES;
            g_layer_visible.store(false, std::memory_order_release);
        });
    }

    void show() override
    {
        run_on_main_async(^{
            update_geometry_on_main();
            g_metal_layer.hidden = NO;
            g_layer_visible.store(true, std::memory_order_release);
        });
    }

    void toggle_fullscreen() override
    {
        // The Qt host owns iOS full-screen layout and orientation.
    }

    void delete_context(draw_context_t) override {}
    draw_context_t make_context() override { return nullptr; }
    void set_current(draw_context_t) override {}
    void flip(draw_context_t, bool) override {}

    int client_width() override
    {
        run_on_main_async(^{ update_geometry_on_main(); });
        return g_drawable_width.load(std::memory_order_acquire);
    }

    int client_height() override
    {
        run_on_main_async(^{ update_geometry_on_main(); });
        return g_drawable_height.load(std::memory_order_acquire);
    }

    f64 client_display_rate() override
    {
        return static_cast<f64>(g_display_rate.load(std::memory_order_acquire));
    }

    bool has_alpha() override { return false; }

    display_handle_t handle() const override
    {
        // RPCS3's Apple Vulkan WSI path consumes a CAMetalLayer through this
        // opaque handle. The iOS overlay patches the macOS helper accordingly.
        return g_layer_handle.load(std::memory_order_acquire);
    }

    bool can_consume_frame() const override { return true; }

    void present_frame(std::vector<u8>&&, u32, u32, u32, bool) const override
    {
        // Vulkan/Metal presents directly to CAMetalLayer. This hook remains for
        // software-present fallbacks and intentionally does not fake a frame.
    }

    void take_screenshot(std::vector<u8>&&, u32, u32, bool) override {}
    void update_title(double) override {}
};
} // namespace

namespace rpcs3::ios
{
int attach_render_view(void* native_view)
{
    if (!native_view)
    {
        return 0;
    }

    __block int attached = 0;
    run_on_main_sync(^{
        UIView* view = (__bridge UIView*)native_view;
        if (![view isKindOfClass:UIView.class])
        {
            return;
        }

        [g_metal_layer removeFromSuperlayer];
        g_host_view = view;
        g_metal_layer = [CAMetalLayer layer];
        g_metal_layer.device = MTLCreateSystemDefaultDevice();
        g_metal_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        g_metal_layer.framebufferOnly = NO;
        g_metal_layer.opaque = YES;
        g_metal_layer.hidden = YES;
        [g_host_view.layer addSublayer:g_metal_layer];

        update_geometry_on_main();
        g_layer_handle.store((__bridge void*)g_metal_layer, std::memory_order_release);
        g_layer_visible.store(false, std::memory_order_release);
        attached = g_metal_layer.device ? 1 : 0;
    });
    return attached;
}

void detach_render_view()
{
    run_on_main_sync(^{
        g_layer_handle.store(nullptr, std::memory_order_release);
        g_layer_visible.store(false, std::memory_order_release);
        [g_metal_layer removeFromSuperlayer];
        g_metal_layer = nil;
        g_host_view = nil;
        g_drawable_width.store(1, std::memory_order_release);
        g_drawable_height.store(1, std::memory_order_release);
    });
}

bool render_view_ready()
{
    return g_layer_handle.load(std::memory_order_acquire) != nullptr;
}

std::unique_ptr<GSFrameBase> make_gs_frame()
{
    if (!render_view_ready())
    {
        return {};
    }
    return std::make_unique<ios_gs_frame>();
}
} // namespace rpcs3::ios
