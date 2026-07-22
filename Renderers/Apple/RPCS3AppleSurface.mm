#include "RPCS3AppleSurface.h"

#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>

#include <algorithm>
#include <mutex>

namespace rpcs3::ios::render
{
namespace
{
@interface RPCS3MetalSurfaceView : UIView
@end

@implementation RPCS3MetalSurfaceView
+ (Class)layerClass
{
    return CAMetalLayer.class;
}
@end

std::mutex g_parent_mutex;
__weak UIView* g_preferred_parent = nil;

UIView* active_root_view()
{
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes)
    {
        if (![scene isKindOfClass:UIWindowScene.class])
            continue;
        UIWindowScene* window_scene = static_cast<UIWindowScene*>(scene);
        if (window_scene.activationState != UISceneActivationStateForegroundActive &&
            window_scene.activationState != UISceneActivationStateForegroundInactive)
            continue;
        for (UIWindow* window in window_scene.windows)
        {
            if (window.isKeyWindow && window.rootViewController.view)
                return window.rootViewController.view;
        }
        for (UIWindow* window in window_scene.windows)
        {
            if (window.rootViewController.view)
                return window.rootViewController.view;
        }
    }
    return nullptr;
}

UIView* view_from_native_handle(void* native_view)
{
    if (!native_view)
        return nil;
    id candidate = (__bridge id)native_view;
    if ([candidate isKindOfClass:UIView.class])
        return static_cast<UIView*>(candidate);
    if ([candidate respondsToSelector:@selector(view)])
    {
        id view = [candidate valueForKey:@"view"];
        if ([view isKindOfClass:UIView.class])
            return static_cast<UIView*>(view);
    }
    return nil;
}

UIView* resolve_parent_view(void* native_parent_view)
{
    if (UIView* explicit_parent = view_from_native_handle(native_parent_view))
        return explicit_parent;

    {
        std::lock_guard lock(g_parent_mutex);
        if (g_preferred_parent)
            return g_preferred_parent;
    }

    return active_root_view();
}

CGSize point_size(std::uint32_t pixel_width, std::uint32_t pixel_height, float scale)
{
    const CGFloat safe_scale = std::max<CGFloat>(scale, 1.0);
    return CGSizeMake(std::max<CGFloat>(pixel_width, 1) / safe_scale,
                      std::max<CGFloat>(pixel_height, 1) / safe_scale);
}
} // namespace

struct apple_surface
{
    __strong UIView* parent = nullptr;
    __strong RPCS3MetalSurfaceView* view = nullptr;
    __strong CAMetalLayer* layer = nullptr;
};

void set_preferred_apple_surface_parent(void* native_view) noexcept
{
    @autoreleasepool
    {
        std::lock_guard lock(g_parent_mutex);
        g_preferred_parent = view_from_native_handle(native_view);
    }
}

void* preferred_apple_surface_parent() noexcept
{
    @autoreleasepool
    {
        std::lock_guard lock(g_parent_mutex);
        return g_preferred_parent ? (__bridge void*)g_preferred_parent : nullptr;
    }
}

apple_surface* create_apple_metal_surface(void* native_parent_view,
                                          std::uint32_t pixel_width,
                                          std::uint32_t pixel_height,
                                          float content_scale,
                                          std::string& error)
{
    @autoreleasepool
    {
        UIView* parent = resolve_parent_view(native_parent_view);
        if (!parent)
        {
            error = "Qt did not expose a usable iOS UIView for the renderer surface.";
            return nullptr;
        }

        const CGSize size = point_size(pixel_width, pixel_height, content_scale);
        auto* result = new apple_surface();
        result->parent = parent;
        result->view = [[RPCS3MetalSurfaceView alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height)];
        result->view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        result->view.userInteractionEnabled = NO;
        result->view.opaque = YES;
        result->view.backgroundColor = UIColor.blackColor;
        result->layer = static_cast<CAMetalLayer*>(result->view.layer);
        result->layer.contentsScale = std::max<CGFloat>(content_scale, 1.0);
        result->layer.drawableSize = CGSizeMake(std::max<std::uint32_t>(pixel_width, 1),
                                                std::max<std::uint32_t>(pixel_height, 1));
        result->layer.framebufferOnly = YES;
        result->layer.opaque = YES;

        [parent addSubview:result->view];
        error.clear();
        return result;
    }
}

void resize_apple_surface(apple_surface* surface,
                          std::uint32_t pixel_width,
                          std::uint32_t pixel_height,
                          float content_scale) noexcept
{
    if (!surface)
        return;
    @autoreleasepool
    {
        const CGSize size = point_size(pixel_width, pixel_height, content_scale);
        surface->view.frame = CGRectMake(0, 0, size.width, size.height);
        surface->layer.contentsScale = std::max<CGFloat>(content_scale, 1.0);
        surface->layer.drawableSize = CGSizeMake(std::max<std::uint32_t>(pixel_width, 1),
                                                 std::max<std::uint32_t>(pixel_height, 1));
    }
}

void* apple_surface_layer(apple_surface* surface) noexcept
{
    return surface ? (__bridge void*)surface->layer : nullptr;
}

void* apple_surface_view(apple_surface* surface) noexcept
{
    return surface ? (__bridge void*)surface->view : nullptr;
}

void destroy_apple_surface(apple_surface* surface) noexcept
{
    if (!surface)
        return;
    @autoreleasepool
    {
        [surface->view removeFromSuperview];
        surface->layer = nullptr;
        surface->view = nullptr;
        surface->parent = nullptr;
    }
    delete surface;
}
} // namespace rpcs3::ios::render
