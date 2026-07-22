enable_language(OBJCXX)

if(NOT DEFINED RPCS3_IOS_PORT_ROOT)
    message(FATAL_ERROR "RPCS3_IOS_PORT_ROOT must point to the iOS port repository")
endif()

add_library(rpcs3_ios_core STATIC
    "${RPCS3_IOS_PORT_ROOT}/Port/IOSPlatform.mm"
    "${RPCS3_IOS_PORT_ROOT}/Port/IOSFilesystem.mm"
    "${RPCS3_IOS_PORT_ROOT}/CoreBridge/RPCS3CoreBridgeStub.mm"
)

target_compile_features(rpcs3_ios_core PUBLIC cxx_std_20)
target_compile_definitions(rpcs3_ios_core PUBLIC
    RPCS3_IOS=1
    RPCS3_PLATFORM_MOBILE=1
    RPCS3_PLATFORM_DESKTOP=0
)
target_include_directories(rpcs3_ios_core PUBLIC
    "${RPCS3_IOS_PORT_ROOT}/Port"
    "${RPCS3_IOS_PORT_ROOT}/CoreBridge"
    "${CMAKE_SOURCE_DIR}"
    "${CMAKE_SOURCE_DIR}/Utilities"
    "${CMAKE_SOURCE_DIR}/rpcs3"
)

set_target_properties(rpcs3_ios_core PROPERTIES
    OUTPUT_NAME "rpcs3-ios-core"
    POSITION_INDEPENDENT_CODE ON
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO
    XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED NO
)
