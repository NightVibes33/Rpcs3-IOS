set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_SYSTEM_VERSION 26.0)
set(CMAKE_SYSTEM_PROCESSOR arm64 CACHE STRING "Target processor")
set(CMAKE_OSX_SYSROOT iphoneos CACHE STRING "iPhoneOS SDK")
set(CMAKE_OSX_DEPLOYMENT_TARGET 26.0 CACHE STRING "Minimum iOS version")
set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "Target architecture")
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

set(CMAKE_C_STANDARD 17)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_OBJCXX_STANDARD 20)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# qt-cmake can lose its device prefix when RPCS3 performs nested package
# discovery while cross-compiling. Pin the verified iOS Qt package directory
# from the workflow environment so find_package(Qt6) always resolves the
# physical-device libraries while QT_HOST_PATH continues to supply host tools.
if(DEFINED ENV{QT_ROOT} AND DEFINED ENV{QT_VERSION})
  set(RPCS3_IOS_QT_PREFIX "$ENV{QT_ROOT}/$ENV{QT_VERSION}/ios")
  list(PREPEND CMAKE_PREFIX_PATH "${RPCS3_IOS_QT_PREFIX}")
  set(Qt6_DIR "${RPCS3_IOS_QT_PREFIX}/lib/cmake/Qt6" CACHE PATH "Qt 6 iOS package directory" FORCE)
endif()

set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO)
set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED NO)
set(CMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH YES)
set(CMAKE_XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS iphoneos)
set(CMAKE_XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2")

add_compile_definitions(
  RPCS3_IOS=1
  RPCS3_PLATFORM_MOBILE=1
  RPCS3_PLATFORM_DESKTOP=0
)
