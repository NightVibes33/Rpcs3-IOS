enable_language(OBJCXX)

if(NOT DEFINED RPCS3_IOS_PORT_ROOT)
    message(FATAL_ERROR "RPCS3_IOS_PORT_ROOT must point to the iOS port repository")
endif()

set(RPCS3_IOS_PORT_ROOT "${RPCS3_IOS_PORT_ROOT}")

set(RPCS3_IOS_OBJCXX_SOURCES
    "${RPCS3_IOS_PORT_ROOT}/Port/IOSPlatform.mm"
    "${RPCS3_IOS_PORT_ROOT}/Port/IOSFilesystem.mm"
    "${RPCS3_IOS_PORT_ROOT}/CoreBridge/RPCS3CoreBridgeStub.mm"
)

# Every entry in this list is compiled directly from the pinned upstream RPCS3
# checkout. Keep this list explicit so CI can prove which upstream implementation
# files are actually present in the shipping archive.
set(RPCS3_IOS_UPSTREAM_SOURCES
    "${CMAKE_SOURCE_DIR}/rpcs3/Crypto/sha256.cpp"
)

list(LENGTH RPCS3_IOS_UPSTREAM_SOURCES RPCS3_IOS_UPSTREAM_SOURCE_COUNT)
if(RPCS3_IOS_UPSTREAM_SOURCE_COUNT LESS 1)
    message(FATAL_ERROR "The iOS core must contain at least one direct upstream RPCS3 source")
endif()

file(STRINGS
    "${RPCS3_IOS_PORT_ROOT}/UPSTREAM_RPCS3_REVISION"
    RPCS3_IOS_UPSTREAM_REVISION
    LIMIT_COUNT 1
)
string(STRIP "${RPCS3_IOS_UPSTREAM_REVISION}" RPCS3_IOS_UPSTREAM_REVISION)
if(RPCS3_IOS_UPSTREAM_REVISION STREQUAL "")
    message(FATAL_ERROR "UPSTREAM_RPCS3_REVISION is empty")
endif()

# The shipping archive currently contains real upstream implementation code, but
# not Emu.System or guest execution. This is deliberately classified as
# partial-upstream rather than execution-capable.
set(RPCS3_IOS_BUILD_CAPABILITY_LEVEL 1)
set(RPCS3_IOS_BUILD_CLASSIFICATION "partial-upstream")
set(RPCS3_IOS_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${RPCS3_IOS_GENERATED_DIR}")
configure_file(
    "${RPCS3_IOS_PORT_ROOT}/Port/RPCS3IOSBuildManifest.h.in"
    "${RPCS3_IOS_GENERATED_DIR}/RPCS3IOSBuildManifest.h"
    @ONLY
)

set(RPCS3_IOS_UPSTREAM_SOURCE_MANIFEST
    "${CMAKE_BINARY_DIR}/rpcs3-ios-upstream-sources.txt"
)
file(WRITE "${RPCS3_IOS_UPSTREAM_SOURCE_MANIFEST}" "")
foreach(source IN LISTS RPCS3_IOS_UPSTREAM_SOURCES)
    file(RELATIVE_PATH relative_source "${CMAKE_SOURCE_DIR}" "${source}")
    file(APPEND "${RPCS3_IOS_UPSTREAM_SOURCE_MANIFEST}" "${relative_source}\n")
endforeach()

add_library(rpcs3_ios_core STATIC
    ${RPCS3_IOS_OBJCXX_SOURCES}
    ${RPCS3_IOS_UPSTREAM_SOURCES}
    "${RPCS3_IOS_PORT_ROOT}/Port/RPCS3CryptoCompat.cpp"
    "${RPCS3_IOS_PORT_ROOT}/Port/RPCS3ELFProbe.cpp"
    "${RPCS3_IOS_PORT_ROOT}/Port/RPCS3SELFProbe.cpp"
    "${RPCS3_IOS_PORT_ROOT}/Port/RPCS3SELFLoadPlan.cpp"
    "${RPCS3_IOS_PORT_ROOT}/Port/RPCS3SELFExtractor.cpp"
    "${RPCS3_IOS_PORT_ROOT}/Port/RPCS3SFO.cpp"
)

set_source_files_properties(${RPCS3_IOS_OBJCXX_SOURCES} PROPERTIES
    COMPILE_OPTIONS "-fobjc-arc"
)

target_compile_features(rpcs3_ios_core PUBLIC cxx_std_20)
target_compile_definitions(rpcs3_ios_core PUBLIC
    RPCS3_IOS=1
    RPCS3_PLATFORM_MOBILE=1
    RPCS3_PLATFORM_DESKTOP=0
    RPCS3_IOS_WITH_UPSTREAM_CRYPTO=1
    RPCS3_IOS_WITH_UPSTREAM_ELF_TYPES=1
    RPCS3_IOS_WITH_SELF_PROBE=1
    RPCS3_IOS_WITH_SELF_LOAD_PLAN=1
    RPCS3_IOS_WITH_SELF_EXTRACTOR=1
    RPCS3_IOS_WITH_SFO_METADATA=1
)
target_include_directories(rpcs3_ios_core PUBLIC
    "${RPCS3_IOS_PORT_ROOT}/Port"
    "${RPCS3_IOS_PORT_ROOT}/CoreBridge"
    "${RPCS3_IOS_GENERATED_DIR}"
    "${CMAKE_SOURCE_DIR}"
    "${CMAKE_SOURCE_DIR}/Utilities"
    "${CMAKE_SOURCE_DIR}/rpcs3"
    "${CMAKE_SOURCE_DIR}/rpcs3/Crypto"
    "${CMAKE_SOURCE_DIR}/rpcs3/Loader"
)

target_link_libraries(rpcs3_ios_core PUBLIC
    "-framework AVFoundation"
    "-framework Metal"
)

set_target_properties(rpcs3_ios_core PROPERTIES
    OUTPUT_NAME "rpcs3-ios-core"
    POSITION_INDEPENDENT_CODE ON
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO
    XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED NO
)
