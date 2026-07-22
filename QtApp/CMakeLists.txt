cmake_minimum_required(VERSION 3.28)

project(RPCS3QtIOS VERSION 0.1.0 LANGUAGES C CXX OBJC OBJCXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTOUIC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Core Gui Widgets)
qt_standard_project_setup()

set(RPCS3_UI_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/Generated/ui")
set(RPCS3_UI_FACTORY_HEADER "${CMAKE_CURRENT_SOURCE_DIR}/Generated/RPCS3QtUiFactory.h")
set(RPCS3_UI_FACTORY_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/Generated/RPCS3QtUiFactory.cpp")
set(RPCS3_UI_LIST "${CMAKE_CURRENT_SOURCE_DIR}/Generated/RPCS3CompiledUiFiles.cmake")
set(RPCS3_RENDERER_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../Renderers")
set(RPCS3_IOS_MOLTENVK_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../BuildSupport/MoltenVK" CACHE PATH "Pinned MoltenVK package root")

foreach(required_file IN ITEMS
    "${RPCS3_UI_ROOT}/main_window.ui"
    "${RPCS3_UI_FACTORY_HEADER}"
    "${RPCS3_UI_FACTORY_SOURCE}"
    "${RPCS3_UI_LIST}")
    if(NOT EXISTS "${required_file}")
        message(FATAL_ERROR "Missing ${required_file}. Run scripts/build-qt-ios-app.sh after cloning the pinned RPCS3 source.")
    endif()
endforeach()

include("${RPCS3_UI_LIST}")
include("${CMAKE_CURRENT_SOURCE_DIR}/../cmake/MoltenVKIOS.cmake")
file(GLOB_RECURSE RPCS3_UPSTREAM_UI_RESOURCE_FILES CONFIGURE_DEPENDS "${RPCS3_UI_ROOT}/*.ui")

add_library(rpcs3_ios_core STATIC IMPORTED GLOBAL)
set_target_properties(rpcs3_ios_core PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/../BuildSupport/librpcs3-ios-core.a"
)

set(RPCS3_RENDERER_SOURCES
    "${RPCS3_RENDERER_ROOT}/RPCS3RendererBackend.h"
    "${RPCS3_RENDERER_ROOT}/RPCS3RendererFactory.cpp"
    "${RPCS3_RENDERER_ROOT}/Apple/RPCS3AppleSurface.h"
    "${RPCS3_RENDERER_ROOT}/Apple/RPCS3AppleSurface.mm"
    "${RPCS3_RENDERER_ROOT}/Metal/RPCS3MetalRenderer.h"
    "${RPCS3_RENDERER_ROOT}/Metal/RPCS3MetalRenderer.mm"
    "${RPCS3_RENDERER_ROOT}/Vulkan/RPCS3VulkanRenderer.h"
    "${RPCS3_RENDERER_ROOT}/Vulkan/RPCS3VulkanRenderer.mm"
)

qt_add_executable(RPCS3QtIOS MANUAL_FINALIZATION
    main.cpp
    RPCS3QtMainWindow.cpp
    RPCS3QtMainWindow.h
    RPCS3RenderWidget.cpp
    RPCS3RenderWidget.h
    RPCS3RendererIntegration.cpp
    RPCS3RendererIntegration.h
    QtCompat.h
    QUiLoader
    ${RPCS3_RENDERER_SOURCES}
    ${RPCS3_UI_FACTORY_HEADER}
    ${RPCS3_UI_FACTORY_SOURCE}
    ${RPCS3_COMPILED_UI_FILES}
)

set_source_files_properties(
    "${RPCS3_RENDERER_ROOT}/Apple/RPCS3AppleSurface.mm"
    "${RPCS3_RENDERER_ROOT}/Metal/RPCS3MetalRenderer.mm"
    "${RPCS3_RENDERER_ROOT}/Vulkan/RPCS3VulkanRenderer.mm"
    PROPERTIES COMPILE_OPTIONS "-fobjc-arc"
)

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
    "${CMAKE_CURRENT_SOURCE_DIR}/../CoreBridge"
    "${RPCS3_RENDERER_ROOT}"
)

target_compile_definitions(RPCS3QtIOS PRIVATE
    RPCS3_QT_IOS_BUILD=1
    RPCS3_QT_BUILD_MARKER="RPCS3 Qt iOS upstream main_window.ui"
)

find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
find_library(SECURITY_FRAMEWORK Security REQUIRED)
find_library(METAL_FRAMEWORK Metal REQUIRED)
find_library(AVFOUNDATION_FRAMEWORK AVFoundation REQUIRED)
find_library(AUDIOTOOLBOX_FRAMEWORK AudioToolbox REQUIRED)
find_library(UNIFORMTYPEIDENTIFIERS_FRAMEWORK UniformTypeIdentifiers REQUIRED)

target_link_libraries(RPCS3QtIOS PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Widgets
    rpcs3_ios_core
    ${FOUNDATION_FRAMEWORK}
    ${SECURITY_FRAMEWORK}
    ${METAL_FRAMEWORK}
    ${AVFOUNDATION_FRAMEWORK}
    ${AUDIOTOOLBOX_FRAMEWORK}
    ${UNIFORMTYPEIDENTIFIERS_FRAMEWORK}
)

rpcs3_link_moltenvk(RPCS3QtIOS "${RPCS3_IOS_MOLTENVK_ROOT}")

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
