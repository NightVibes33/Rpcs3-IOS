cmake_minimum_required(VERSION 3.28)

project(RPCS3QtIOS VERSION 0.1.0 LANGUAGES C CXX OBJC OBJCXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTOUIC ON)
set(CMAKE_AUTORCC ON)

option(RPCS3_IOS_UNIFIED_UPSTREAM "Link the Qt iOS host directly to the upstream rpcs3_emu graph" OFF)

# RPCS3's cross-compile graph can restrict package lookup to the iOS SDK.
# Qt's target CMake packages live beside Qt6Config.cmake outside that SDK, so
# pin each requested target component and temporarily allow both rooted and
# non-rooted package lookup while Qt resolves its target and host dependencies.
if(CMAKE_SYSTEM_NAME STREQUAL "iOS" AND DEFINED Qt6_DIR)
    get_filename_component(RPCS3_IOS_QT_CMAKE_ROOT "${Qt6_DIR}/.." ABSOLUTE)
    foreach(component IN ITEMS Core Gui Widgets)
        set(component_dir "${RPCS3_IOS_QT_CMAKE_ROOT}/Qt6${component}")
        if(NOT EXISTS "${component_dir}/Qt6${component}Config.cmake")
            message(FATAL_ERROR "Missing Qt iOS component package: ${component_dir}/Qt6${component}Config.cmake")
        endif()
        set(Qt6${component}_DIR "${component_dir}" CACHE PATH "Pinned Qt iOS ${component} package" FORCE)
    endforeach()
endif()

set(RPCS3_IOS_HAD_PACKAGE_ROOT_MODE FALSE)
if(DEFINED CMAKE_FIND_ROOT_PATH_MODE_PACKAGE)
    set(RPCS3_IOS_HAD_PACKAGE_ROOT_MODE TRUE)
    set(RPCS3_IOS_SAVED_PACKAGE_ROOT_MODE "${CMAKE_FIND_ROOT_PATH_MODE_PACKAGE}")
endif()
if(CMAKE_CROSSCOMPILING)
    set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
endif()
find_package(Qt6 6.8 REQUIRED COMPONENTS Core Gui Widgets)
if(CMAKE_CROSSCOMPILING)
    if(RPCS3_IOS_HAD_PACKAGE_ROOT_MODE)
        set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE "${RPCS3_IOS_SAVED_PACKAGE_ROOT_MODE}")
    else()
        unset(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE)
    endif()
endif()
qt_standard_project_setup()

set(RPCS3_PORT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/..")
set(RPCS3_UI_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/Generated/ui")
set(RPCS3_UI_FACTORY_HEADER "${CMAKE_CURRENT_SOURCE_DIR}/Generated/RPCS3QtUiFactory.h")
set(RPCS3_UI_FACTORY_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/Generated/RPCS3QtUiFactory.cpp")
set(RPCS3_UI_LIST "${CMAKE_CURRENT_SOURCE_DIR}/Generated/RPCS3CompiledUiFiles.cmake")
set(RPCS3_RENDERER_ROOT "${RPCS3_PORT_ROOT}/Renderers")
set(RPCS3_IOS_MOLTENVK_ROOT "${RPCS3_PORT_ROOT}/BuildSupport/MoltenVK" CACHE PATH "Pinned MoltenVK package root")

foreach(required_file IN ITEMS
    "${RPCS3_UI_ROOT}/main_window.ui"
    "${RPCS3_UI_FACTORY_HEADER}"
    "${RPCS3_UI_FACTORY_SOURCE}"
    "${RPCS3_UI_LIST}")
    if(NOT EXISTS "${required_file}")
        message(FATAL_ERROR "Missing ${required_file}. Generate the pinned RPCS3 Qt forms before configuring the iOS host.")
    endif()
endforeach()

include("${RPCS3_UI_LIST}")
include("${RPCS3_PORT_ROOT}/cmake/MoltenVKIOS.cmake")
file(GLOB_RECURSE RPCS3_UPSTREAM_UI_RESOURCE_FILES CONFIGURE_DEPENDS "${RPCS3_UI_ROOT}/*.ui")

if(RPCS3_IOS_UNIFIED_UPSTREAM)
    if(NOT TARGET rpcs3_ios_upstream_bridge OR NOT TARGET rpcs3_emu)
        message(FATAL_ERROR "Unified Qt mode must be configured inside RPCS3's upstream CMake graph after rpcs3_ios_upstream_bridge is defined")
    endif()
    set(RPCS3_IOS_CORE_TARGET rpcs3_ios_upstream_bridge)
    set(RPCS3_IOS_CORE_SOURCES
        "${RPCS3_PORT_ROOT}/CoreBridge/RPCS3CoreBridgeUpstream.cpp"
        "${RPCS3_PORT_ROOT}/CoreBridge/RPCS3UpstreamRuntimeHost.cpp"
        "${RPCS3_PORT_ROOT}/Port/IOSPlatform.mm"
        "${RPCS3_PORT_ROOT}/Port/IOSFilesystem.mm"
    )
    # Native Apple/Metal objects are compiled directly into rpcs3_emu. The Qt
    # self-test adds only its own renderer factory and Vulkan context/swapchain.
    set(RPCS3_RENDERER_SOURCES
        "${RPCS3_RENDERER_ROOT}/RPCS3RendererBackend.h"
        "${RPCS3_RENDERER_ROOT}/RPCS3RendererFactory.cpp"
        "${RPCS3_RENDERER_ROOT}/Vulkan/RPCS3VulkanContext.h"
        "${RPCS3_RENDERER_ROOT}/Vulkan/RPCS3VulkanContext.mm"
        "${RPCS3_RENDERER_ROOT}/Vulkan/RPCS3VulkanRenderer.h"
        "${RPCS3_RENDERER_ROOT}/Vulkan/RPCS3VulkanRenderer.mm"
    )
else()
    add_library(rpcs3_ios_core STATIC IMPORTED GLOBAL)
    set_target_properties(rpcs3_ios_core PROPERTIES
        IMPORTED_LOCATION "${RPCS3_PORT_ROOT}/BuildSupport/librpcs3-ios-core.a"
    )
    set(RPCS3_IOS_CORE_TARGET rpcs3_ios_core)
    set(RPCS3_IOS_CORE_SOURCES)
    set(RPCS3_RENDERER_SOURCES
        "${RPCS3_RENDERER_ROOT}/RPCS3RendererBackend.h"
        "${RPCS3_RENDERER_ROOT}/RPCS3RendererFactory.cpp"
        "${RPCS3_RENDERER_ROOT}/Apple/RPCS3AppleSurface.h"
        "${RPCS3_RENDERER_ROOT}/Apple/RPCS3AppleSurface.mm"
        "${RPCS3_RENDERER_ROOT}/Metal/RPCS3MetalRenderer.h"
        "${RPCS3_RENDERER_ROOT}/Metal/RPCS3MetalRenderer.mm"
        "${RPCS3_RENDERER_ROOT}/Vulkan/RPCS3VulkanContext.h"
        "${RPCS3_RENDERER_ROOT}/Vulkan/RPCS3VulkanContext.mm"
        "${RPCS3_RENDERER_ROOT}/Vulkan/RPCS3VulkanRenderer.h"
        "${RPCS3_RENDERER_ROOT}/Vulkan/RPCS3VulkanRenderer.mm"
    )
endif()

qt_add_executable(RPCS3QtIOS MANUAL_FINALIZATION
    main.cpp
    RPCS3QtMainWindow.cpp
    RPCS3QtMainWindow.h
    RPCS3RenderWidget.cpp
    RPCS3RenderWidget.h
    RPCS3RendererIntegration.cpp
    RPCS3RendererIntegration.h
    RPCS3RuntimeActionOverrides.cpp
    RPCS3RuntimeActionOverrides.h
    QtCompat.h
    QUiLoader
    ${RPCS3_IOS_CORE_SOURCES}
    ${RPCS3_RENDERER_SOURCES}
    ${RPCS3_UI_FACTORY_HEADER}
    ${RPCS3_UI_FACTORY_SOURCE}
    ${RPCS3_COMPILED_UI_FILES}
)

set(RPCS3_ARC_SOURCES
    "${RPCS3_RENDERER_ROOT}/Vulkan/RPCS3VulkanContext.mm"
    "${RPCS3_RENDERER_ROOT}/Vulkan/RPCS3VulkanRenderer.mm"
)
if(RPCS3_IOS_UNIFIED_UPSTREAM)
    list(APPEND RPCS3_ARC_SOURCES
        "${RPCS3_PORT_ROOT}/Port/IOSPlatform.mm"
        "${RPCS3_PORT_ROOT}/Port/IOSFilesystem.mm"
    )
else()
    list(APPEND RPCS3_ARC_SOURCES
        "${RPCS3_RENDERER_ROOT}/Apple/RPCS3AppleSurface.mm"
        "${RPCS3_RENDERER_ROOT}/Metal/RPCS3MetalRenderer.mm"
    )
endif()
set_source_files_properties(${RPCS3_ARC_SOURCES} PROPERTIES COMPILE_OPTIONS "-fobjc-arc")

set_target_properties(RPCS3QtIOS PROPERTIES
    AUTOUIC_SEARCH_PATHS "${RPCS3_UI_ROOT}"
)

target_precompile_headers(RPCS3QtIOS PRIVATE QtCompat.h)

qt_add_resources(RPCS3QtIOS "rpcs3_upstream_ui"
    PREFIX "/rpcs3/ui"
    BASE "${RPCS3_UI_ROOT}"
    FILES ${RPCS3_UPSTREAM_UI_RESOURCE_FILES}
)

target_include_directories(RPCS3QtIOS PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/Generated"
    "${RPCS3_PORT_ROOT}/CoreBridge"
    "${RPCS3_PORT_ROOT}/Port"
    "${RPCS3_RENDERER_ROOT}"
    "${RPCS3_RENDERER_ROOT}/Apple"
    "${RPCS3_RENDERER_ROOT}/Metal"
    "${RPCS3_RENDERER_ROOT}/Vulkan"
)
if(RPCS3_IOS_UNIFIED_UPSTREAM)
    target_include_directories(RPCS3QtIOS PRIVATE
        "${CMAKE_SOURCE_DIR}"
        "${CMAKE_SOURCE_DIR}/rpcs3"
        "${CMAKE_SOURCE_DIR}/Utilities"
    )
endif()

target_compile_definitions(RPCS3QtIOS PRIVATE
    RPCS3_QT_IOS_BUILD=1
    RPCS3_QT_BUILD_MARKER="RPCS3 Qt iOS upstream main_window.ui"
    $<$<BOOL:${RPCS3_IOS_UNIFIED_UPSTREAM}>:RPCS3_IOS_UNIFIED_UPSTREAM=1>
)

find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
find_library(SECURITY_FRAMEWORK Security REQUIRED)
find_library(METAL_FRAMEWORK Metal REQUIRED)
find_library(QUARTZCORE_FRAMEWORK QuartzCore REQUIRED)
find_library(COREGRAPHICS_FRAMEWORK CoreGraphics REQUIRED)
find_library(IOSURFACE_FRAMEWORK IOSurface REQUIRED)
find_library(UIKIT_FRAMEWORK UIKit REQUIRED)
find_library(AVFOUNDATION_FRAMEWORK AVFoundation REQUIRED)
find_library(AUDIOTOOLBOX_FRAMEWORK AudioToolbox REQUIRED)
find_library(UNIFORMTYPEIDENTIFIERS_FRAMEWORK UniformTypeIdentifiers REQUIRED)

target_link_libraries(RPCS3QtIOS PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Widgets
    ${RPCS3_IOS_CORE_TARGET}
    ${FOUNDATION_FRAMEWORK}
    ${SECURITY_FRAMEWORK}
    ${METAL_FRAMEWORK}
    ${QUARTZCORE_FRAMEWORK}
    ${COREGRAPHICS_FRAMEWORK}
    ${IOSURFACE_FRAMEWORK}
    ${UIKIT_FRAMEWORK}
    ${AVFOUNDATION_FRAMEWORK}
    ${AUDIOTOOLBOX_FRAMEWORK}
    ${UNIFORMTYPEIDENTIFIERS_FRAMEWORK}
)

if(RPCS3_IOS_UNIFIED_UPSTREAM)
    message(STATUS "RPCS3 iOS Qt host: inheriting MoltenVK from rpcs3_emu/3rdparty::vulkan")
else()
    rpcs3_link_moltenvk(RPCS3QtIOS "${RPCS3_IOS_MOLTENVK_ROOT}")
endif()

set_target_properties(RPCS3QtIOS PROPERTIES
    OUTPUT_NAME "RPCS3-iOS"
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_BUNDLE_NAME "RPCS3"
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.nightvibes33.rpcs3ios"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1.0"
    MACOSX_BUNDLE_BUNDLE_VERSION "1"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.nightvibes33.rpcs3ios"
    XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "26.0"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
    XCODE_ATTRIBUTE_SUPPORTS_MACCATALYST "NO"
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
    XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO"
    XCODE_ATTRIBUTE_ENABLE_BITCODE "NO"
)

qt_finalize_executable(RPCS3QtIOS)
