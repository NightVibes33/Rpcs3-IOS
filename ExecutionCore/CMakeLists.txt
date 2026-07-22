if(NOT TARGET rpcs3_emu)
    message(FATAL_ERROR "rpcs3_ios_execution_core requires the real upstream rpcs3_emu target")
endif()
if(NOT DEFINED RPCS3_IOS_PORT_ROOT)
    message(FATAL_ERROR "RPCS3_IOS_PORT_ROOT must point to the iOS port repository")
endif()

find_package(Qt6 6.8 REQUIRED COMPONENTS Core Gui Widgets)

set(RPCS3_IOS_EXECUTION_OBJCXX_SOURCES
    "${RPCS3_IOS_PORT_ROOT}/Port/IOSPlatform.mm"
    "${RPCS3_IOS_PORT_ROOT}/Port/IOSFilesystem.mm"
)

add_library(rpcs3_ios_execution_core STATIC
    ${RPCS3_IOS_EXECUTION_OBJCXX_SOURCES}
    "${RPCS3_IOS_PORT_ROOT}/CoreBridge/RPCS3CoreBridgeUpstream.cpp"
    "${RPCS3_IOS_PORT_ROOT}/CoreBridge/RPCS3UpstreamRuntimeHost.cpp"
)

set_source_files_properties(${RPCS3_IOS_EXECUTION_OBJCXX_SOURCES} PROPERTIES
    COMPILE_OPTIONS "-fobjc-arc"
)

target_compile_features(rpcs3_ios_execution_core PUBLIC cxx_std_23)
target_compile_definitions(rpcs3_ios_execution_core PUBLIC
    RPCS3_IOS=1
    RPCS3_PLATFORM_MOBILE=1
    RPCS3_PLATFORM_DESKTOP=0
    RPCS3_IOS_EXECUTION_CORE=1
    RPCS3_IOS_WITH_UPSTREAM_RUNTIME=1
)
target_include_directories(rpcs3_ios_execution_core PUBLIC
    "${RPCS3_IOS_PORT_ROOT}/Port"
    "${RPCS3_IOS_PORT_ROOT}/CoreBridge"
    "${RPCS3_IOS_PORT_ROOT}/Renderers"
    "${RPCS3_IOS_PORT_ROOT}/Renderers/Apple"
    "${RPCS3_IOS_PORT_ROOT}/Renderers/Metal"
    "${CMAKE_SOURCE_DIR}"
    "${CMAKE_SOURCE_DIR}/Utilities"
    "${CMAKE_SOURCE_DIR}/rpcs3"
)

target_link_libraries(rpcs3_ios_execution_core PUBLIC
    rpcs3_emu
    Qt6::Core
    Qt6::Gui
    Qt6::Widgets
    "-framework UIKit"
    "-framework Foundation"
    "-framework AVFoundation"
    "-framework AudioToolbox"
    "-framework Metal"
    "-framework QuartzCore"
    "-framework CoreGraphics"
    "-framework Security"
)

set_target_properties(rpcs3_ios_execution_core PROPERTIES
    OUTPUT_NAME "rpcs3-ios-execution-core"
    POSITION_INDEPENDENT_CODE ON
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO
    XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED NO
)
