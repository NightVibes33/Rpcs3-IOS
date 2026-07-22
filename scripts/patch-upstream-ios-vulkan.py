#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


def replace_once(path: Path, needle: str, replacement: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    if needle not in text:
        raise SystemExit(f"Unable to locate upstream {label} block in {path}")
    path.write_text(text.replace(needle, replacement, 1), encoding="utf-8")


def patch_dependency_graph(upstream_root: Path, moltenvk_root: Path) -> None:
    binary = moltenvk_root / "MoltenVK.xcframework/ios-arm64/MoltenVK.framework/MoltenVK"
    include = moltenvk_root / "include"
    for required in (binary, include / "vulkan/vulkan.h", include / "MoltenVK/vk_mvk_moltenvk.h"):
        if not required.exists():
            raise SystemExit(f"Missing MoltenVK input: {required}")

    cmake = upstream_root / "3rdparty/CMakeLists.txt"
    needle = '''# Vulkan
set(VULKAN_TARGET 3rdparty_dummy_lib)
if(USE_VULKAN)
'''
    replacement = f'''# Vulkan
set(VULKAN_TARGET 3rdparty_dummy_lib)
if(RPCS3_IOS_UPSTREAM_GRAPH AND USE_VULKAN)
\tmessage(STATUS "RPCS3 iOS: using pinned static MoltenVK XCFramework")
\tadd_library(3rdparty_vulkan INTERFACE)
\ttarget_compile_definitions(3rdparty_vulkan INTERFACE HAVE_VULKAN=1 VK_USE_PLATFORM_METAL_EXT=1)
\ttarget_include_directories(3rdparty_vulkan SYSTEM INTERFACE "{include.as_posix()}")
\ttarget_link_libraries(3rdparty_vulkan INTERFACE
\t\t"{binary.as_posix()}"
\t\t"-framework Metal"
\t\t"-framework Foundation"
\t\t"-framework QuartzCore"
\t\t"-framework CoreGraphics"
\t\t"-framework IOSurface"
\t)
\tset(VULKAN_TARGET 3rdparty_vulkan)
elseif(USE_VULKAN)
'''
    replace_once(cmake, needle, replacement, "Vulkan dependency")


def patch_metal_layer(upstream_root: Path) -> None:
    source = upstream_root / "rpcs3/Emu/RSX/VK/vkutils/metal_layer.mm"
    source.write_text('''#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wold-style-cast"
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
#pragma GCC diagnostic ignored "-Wmissing-declarations"
#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>
#import <TargetConditionals.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>

void* GetCAMetalLayerFromMetalView(void* view)
{
    UIView* ui_view = (__bridge UIView*)view;
    if (!ui_view)
        return nullptr;
    CALayer* layer = ui_view.layer;
    if ([layer isKindOfClass:CAMetalLayer.class])
        return (__bridge void*)layer;
    for (CALayer* child in layer.sublayers)
        if ([child isKindOfClass:CAMetalLayer.class])
            return (__bridge void*)child;
    return nullptr;
}
#else
#import <AppKit/AppKit.h>
void* GetCAMetalLayerFromMetalView(void* view) { return ((NSView*)view).layer; }
#endif
#pragma GCC diagnostic pop
''', encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("upstream_root", type=Path)
    parser.add_argument("moltenvk_root", type=Path)
    args = parser.parse_args()

    upstream_root = args.upstream_root.resolve()
    moltenvk_root = args.moltenvk_root.resolve()
    patch_dependency_graph(upstream_root, moltenvk_root)
    patch_metal_layer(upstream_root)
    print(f"Patched upstream Vulkan for iOS using MoltenVK at {moltenvk_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
