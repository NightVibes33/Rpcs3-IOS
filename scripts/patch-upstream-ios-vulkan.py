#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
from pathlib import Path


def replace_once(path: Path, needle: str, replacement: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    if needle not in text:
        raise SystemExit(f"Unable to locate upstream {label} block in {path}")
    path.write_text(text.replace(needle, replacement, 1), encoding="utf-8")


def resolve_device_binary(moltenvk_root: Path) -> Path:
    path_file = moltenvk_root / "device-binary-path.txt"
    if path_file.is_file():
        relative = path_file.read_text(encoding="utf-8").strip()
        candidate = moltenvk_root / relative
        if candidate.is_file():
            return candidate.resolve()

    xcframework = moltenvk_root / "MoltenVK.xcframework"
    candidates = [
        *xcframework.rglob("MoltenVK.framework/MoltenVK"),
        *xcframework.rglob("libMoltenVK.a"),
    ]
    for candidate in sorted(set(candidates)):
        lowered = candidate.as_posix().lower()
        if "simulator" in lowered or "maccatalyst" in lowered:
            continue
        if any(part.startswith("ios-") for part in candidate.parts) and candidate.is_file():
            return candidate.resolve()
    raise SystemExit(f"No iOS device MoltenVK framework or static archive was found under {xcframework}")


def patch_dependency_graph(upstream_root: Path, moltenvk_root: Path) -> None:
    binary = resolve_device_binary(moltenvk_root)
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
\tmessage(STATUS "RPCS3 iOS: using pinned static MoltenVK XCFramework: {binary.as_posix()}")
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


def validate_spirv_cross(spirv_cross_root: Path) -> tuple[Path, list[Path]]:
    include = spirv_cross_root / "include/spirv_cross"
    libraries = [
        spirv_cross_root / "lib/libspirv-cross-msl.a",
        spirv_cross_root / "lib/libspirv-cross-glsl.a",
        spirv_cross_root / "lib/libspirv-cross-core.a",
    ]
    required = [
        include / "spirv_cross.hpp",
        include / "spirv_glsl.hpp",
        include / "spirv_msl.hpp",
        *libraries,
    ]
    for path in required:
        if not path.is_file():
            raise SystemExit(f"Missing SPIRV-Cross iOS input: {path}")
    return include, libraries


def add_port_renderer_sources(upstream_root: Path, port_root: Path, spirv_cross_root: Path) -> None:
    cmake = upstream_root / "rpcs3/Emu/CMakeLists.txt"
    text = cmake.read_text(encoding="utf-8")
    marker = "# RPCS3 iOS native renderer sources"
    if marker in text:
        return

    spirv_include, spirv_libraries = validate_spirv_cross(spirv_cross_root)
    renderers = port_root / "Renderers"
    objcxx_sources = [
        renderers / "Apple/RPCS3AppleSurface.mm",
        renderers / "Apple/RPCS3IOSGSFrame.mm",
        renderers / "Metal/RPCS3MetalRenderer.mm",
        renderers / "Metal/RPCS3MetalResourceBinder.mm",
        renderers / "Metal/RPCS3MetalRSXFormats.mm",
        renderers / "Metal/RPCS3MetalPipelineState.mm",
        renderers / "Metal/RPCS3MetalRenderPipelineCache.mm",
        renderers / "Metal/RPCS3MetalShaderLibrary.mm",
        renderers / "Metal/RPCS3MetalGSRender.mm",
    ]
    cpp_sources = [
        renderers / "Metal/RPCS3MetalDrawSubmission.cpp",
        renderers / "Metal/RPCS3MetalPrimitiveExpander.cpp",
        renderers / "Metal/RPCS3MetalProgramCompiler.cpp",
        renderers / "Metal/RPCS3MetalShaderTranslator.cpp",
    ]
    headers = [
        renderers / "RPCS3RendererBackend.h",
        renderers / "Apple/RPCS3AppleSurface.h",
        renderers / "Apple/RPCS3IOSGSFrame.h",
        renderers / "Metal/RPCS3MetalDrawSubmission.h",
        renderers / "Metal/RPCS3MetalRenderer.h",
        renderers / "Metal/RPCS3MetalResourceBinder.h",
        renderers / "Metal/RPCS3MetalRSXFormats.h",
        renderers / "Metal/RPCS3MetalPipelineState.h",
        renderers / "Metal/RPCS3MetalRenderPipelineCache.h",
        renderers / "Metal/RPCS3MetalPrimitiveExpander.h",
        renderers / "Metal/RPCS3MetalProgramCompiler.h",
        renderers / "Metal/RPCS3MetalShaderTranslator.h",
        renderers / "Metal/RPCS3MetalShaderLibrary.h",
        renderers / "Metal/RPCS3MetalGSRender.h",
    ]
    for required in [*objcxx_sources, *cpp_sources, *headers]:
        if not required.exists():
            raise SystemExit(f"Missing renderer source: {required}")

    objcxx_lines = "\n".join(f'        "{path.as_posix()}"' for path in objcxx_sources)
    cpp_lines = "\n".join(f'        "{path.as_posix()}"' for path in cpp_sources)
    spirv_library_lines = "\n".join(f'        "{path.as_posix()}"' for path in spirv_libraries)
    block = f'''

{marker}
if(RPCS3_IOS_UPSTREAM_GRAPH)
    set(RPCS3_IOS_NATIVE_RENDERER_OBJCXX_SOURCES
{objcxx_lines}
    )
    set(RPCS3_IOS_NATIVE_RENDERER_CPP_SOURCES
{cpp_lines}
    )
    target_sources(rpcs3_emu PRIVATE
        ${{RPCS3_IOS_NATIVE_RENDERER_OBJCXX_SOURCES}}
        ${{RPCS3_IOS_NATIVE_RENDERER_CPP_SOURCES}}
    )
    set_source_files_properties(${{RPCS3_IOS_NATIVE_RENDERER_OBJCXX_SOURCES}} PROPERTIES
        COMPILE_OPTIONS "-fobjc-arc"
    )
    target_include_directories(rpcs3_emu PUBLIC
        "{renderers.as_posix()}"
        "{(renderers / 'Apple').as_posix()}"
        "{(renderers / 'Metal').as_posix()}"
    )
    target_include_directories(rpcs3_emu SYSTEM PRIVATE
        "{spirv_include.as_posix()}"
    )
    target_compile_definitions(rpcs3_emu PUBLIC
        RPCS3_IOS_HAS_MOLTENVK=1
        RPCS3_IOS_HAS_NATIVE_METAL=1
        RPCS3_IOS_METAL_RSX_FORMAT_TRANSLATION=1
        RPCS3_IOS_METAL_RSX_PIPELINE_TRANSLATION=1
        RPCS3_IOS_METAL_RSX_DRAW_SUBMISSION=1
        RPCS3_IOS_METAL_SPIRV_TO_MSL=1
        RPCS3_IOS_METAL_SHADER_LIBRARY_CACHE=1
        RPCS3_IOS_METAL_RENDER_PIPELINE_CACHE=1
        RPCS3_IOS_METAL_LIVE_PROGRAM_COMPILER=1
        RPCS3_IOS_METAL_REFLECTED_RESOURCE_BINDING=1
    )
    target_link_libraries(rpcs3_emu PUBLIC
{spirv_library_lines}
        "-framework UIKit"
        "-framework Metal"
        "-framework QuartzCore"
        "-framework CoreGraphics"
        "-framework Foundation"
    )
endif()
'''
    cmake.write_text(text + block, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("upstream_root", type=Path)
    parser.add_argument("moltenvk_root", type=Path)
    parser.add_argument("--spirv-cross-root", type=Path)
    args = parser.parse_args()

    upstream_root = args.upstream_root.resolve()
    moltenvk_root = args.moltenvk_root.resolve()
    port_root = Path(__file__).resolve().parent.parent
    configured_spirv_root = args.spirv_cross_root or Path(
        os.environ.get("RPCS3_IOS_SPIRV_CROSS_ROOT", port_root / "BuildSupport/SPIRV-Cross")
    )
    spirv_cross_root = configured_spirv_root.resolve()

    patch_dependency_graph(upstream_root, moltenvk_root)
    patch_metal_layer(upstream_root)
    add_port_renderer_sources(upstream_root, port_root, spirv_cross_root)
    print(
        "Patched upstream Vulkan and native Metal renderers for iOS using "
        f"MoltenVK at {moltenvk_root} and SPIRV-Cross at {spirv_cross_root}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
