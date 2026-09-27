cmake_minimum_required(VERSION 3.28)
project(RPCS3IOSNative LANGUAGES C CXX OBJC OBJCXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(RPCS3_CORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../BuildSupport/RPCS3Core" CACHE PATH "Built XITRIX RPCS3 iOS core")
if(NOT EXISTS "${RPCS3_CORE_DIR}/libRPCS3Core.dylib")
    message(FATAL_ERROR "Missing ${RPCS3_CORE_DIR}/libRPCS3Core.dylib. Build the XITRIX iOS core first.")
endif()
if(NOT EXISTS "${RPCS3_CORE_DIR}/RPCS3IOS.h")
    message(FATAL_ERROR "Missing ${RPCS3_CORE_DIR}/RPCS3IOS.h")
endif()

add_library(RPCS3Core SHARED IMPORTED GLOBAL)
set_target_properties(RPCS3Core PROPERTIES
    IMPORTED_LOCATION "${RPCS3_CORE_DIR}/libRPCS3Core.dylib"
    INTERFACE_INCLUDE_DIRECTORIES "${RPCS3_CORE_DIR}"
)

add_executable(RPCS3IOSNative MACOSX_BUNDLE
    main.mm
)

target_compile_options(RPCS3IOSNative PRIVATE
    "$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>"
)

target_link_libraries(RPCS3IOSNative PRIVATE
    RPCS3Core
    "-framework UIKit"
    "-framework Foundation"
    "-framework QuartzCore"
    "-framework Metal"
    "-framework GameController"
    "-framework AVFoundation"
    "-framework AudioToolbox"
    "-framework UniformTypeIdentifiers"
)

set_target_properties(RPCS3IOSNative PROPERTIES
    OUTPUT_NAME "RPCS3"
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
    MACOSX_BUNDLE_BUNDLE_NAME "RPCS3"
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.nightvibes33.rpcs3ios"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "0.9.0"
    MACOSX_BUNDLE_BUNDLE_VERSION "1"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.nightvibes33.rpcs3ios"
    XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "17.4"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
    XCODE_ATTRIBUTE_SUPPORTS_MACCATALYST "NO"
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
    XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO"
    XCODE_ATTRIBUTE_ENABLE_BITCODE "NO"
    XCODE_ATTRIBUTE_LD_RUNPATH_SEARCH_PATHS "@executable_path/Frameworks"
)
