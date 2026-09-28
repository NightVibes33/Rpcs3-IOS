include_guard(GLOBAL)

function(rpcs3_enable_apple_mobile target)
    if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
        return()
    endif()
    if(NOT TARGET "${target}")
        message(FATAL_ERROR "rpcs3_enable_apple_mobile: target '${target}' does not exist")
    endif()
    if(NOT DEFINED RPCS3_IOS_PORT_ROOT OR RPCS3_IOS_PORT_ROOT STREQUAL "")
        message(FATAL_ERROR "RPCS3_IOS_PORT_ROOT must point at the Rpcs3-IOS checkout")
    endif()

    get_property(already_enabled TARGET "${target}" PROPERTY RPCS3_APPLE_MOBILE_ENABLED)
    if(already_enabled)
        return()
    endif()

    set(apple_mobile_platform "${RPCS3_IOS_PORT_ROOT}/CoreBridge/RPCS3AppleMobilePlatform.mm")
    set(upstream_runtime_bridge "${CMAKE_SOURCE_DIR}/rpcs3/Emu/RPCS3IOSUpstreamRuntimeBridge.cpp")
    set(upstream_pad_bridge "${RPCS3_IOS_PORT_ROOT}/CoreBridge/RPCS3IOSPadBridge.cpp")
    set(upstream_gs_frame "${RPCS3_IOS_PORT_ROOT}/Port/iOS/RPCS3IOSGSFrame.mm")
    foreach(required_source IN ITEMS
        "${apple_mobile_platform}"
        "${upstream_runtime_bridge}"
        "${upstream_pad_bridge}"
        "${upstream_gs_frame}")
        if(NOT EXISTS "${required_source}")
            message(FATAL_ERROR "RPCS3 Apple mobile source is missing: ${required_source}")
        endif()
    endforeach()

    enable_language(OBJCXX)
    target_sources("${target}" PRIVATE
        "${apple_mobile_platform}"
        "${upstream_runtime_bridge}"
        "${upstream_pad_bridge}"
        "${upstream_gs_frame}")
    target_include_directories("${target}" PRIVATE
        "${RPCS3_IOS_PORT_ROOT}/CoreBridge"
        "${RPCS3_IOS_PORT_ROOT}/Port/iOS"
        "${CMAKE_SOURCE_DIR}"
        "${CMAKE_SOURCE_DIR}/rpcs3")
    target_compile_definitions("${target}" PRIVATE
        RPCS3_IOS=1
        RPCS3_APPLE_MOBILE=1)
    target_compile_options("${target}" PRIVATE
        "$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>")
    target_link_libraries("${target}" PRIVATE
        "-framework Foundation"
        "-framework UIKit"
        "-framework QuartzCore"
        "-framework Metal"
        "-framework CoreGraphics"
        "-framework IOSurface"
        "-framework AVFoundation"
        "-framework VideoToolbox"
        "-framework CoreMedia"
        "-framework CoreVideo"
        "-framework AudioToolbox"
        "-framework CoreAudio"
        "-framework GameController")

    set_target_properties("${target}" PROPERTIES
        RPCS3_APPLE_MOBILE_ENABLED TRUE
        XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
        XCODE_ATTRIBUTE_SUPPORTS_MACCATALYST "NO"
        XCODE_ATTRIBUTE_ENABLE_BITCODE "NO"
        XCODE_ATTRIBUTE_INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents "YES"
        XCODE_ATTRIBUTE_INFOPLIST_KEY_UIFileSharingEnabled "YES"
        XCODE_ATTRIBUTE_INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace "YES")
endfunction()
