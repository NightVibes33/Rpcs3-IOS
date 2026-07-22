#!/bin/bash
set -euo pipefail

PORT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REVISION_FILE="$PORT_ROOT/SPIRV_CROSS_REVISION"
SOURCE_ROOT="${SPIRV_CROSS_SOURCE_ROOT:-$PORT_ROOT/.deps/SPIRV-Cross}"
BUILD_ROOT="${SPIRV_CROSS_BUILD_ROOT:-$PORT_ROOT/.cache/SPIRV-Cross-ios}"
OUTPUT_ROOT="${RPCS3_IOS_SPIRV_CROSS_ROOT:-$PORT_ROOT/BuildSupport/SPIRV-Cross}"
TOOLCHAIN="$PORT_ROOT/cmake/toolchains/ios-arm64.cmake"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-26.0}"
LOG_DIR="${CI_LOGS:-$PORT_ROOT/ci-logs}"
REVISION="$(tr -d '[:space:]' < "$REVISION_FILE")"

mkdir -p "$LOG_DIR" "$PORT_ROOT/.deps" "$PORT_ROOT/.cache" "$PORT_ROOT/BuildSupport"
test -n "$REVISION"
test -f "$TOOLCHAIN"

required_outputs=(
    include/spirv_cross/spirv_cross.hpp
    include/spirv_cross/spirv_glsl.hpp
    include/spirv_cross/spirv_msl.hpp
    lib/libspirv-cross-core.a
    lib/libspirv-cross-glsl.a
    lib/libspirv-cross-msl.a
)

cache_valid=true
if [[ ! -f "$OUTPUT_ROOT/revision.txt" ]] ||
   [[ "$(tr -d '[:space:]' < "$OUTPUT_ROOT/revision.txt" 2>/dev/null || true)" != "$REVISION" ]]; then
    cache_valid=false
fi
for relative in "${required_outputs[@]}"; do
    if [[ ! -f "$OUTPUT_ROOT/$relative" ]]; then
        cache_valid=false
    fi
done
if [[ "$cache_valid" == true ]]; then
    echo "Using cached SPIRV-Cross $REVISION from $OUTPUT_ROOT"
    exit 0
fi

rm -rf "$SOURCE_ROOT" "$BUILD_ROOT" "$OUTPUT_ROOT"
git clone --filter=blob:none --no-checkout https://github.com/KhronosGroup/SPIRV-Cross.git "$SOURCE_ROOT"
git -C "$SOURCE_ROOT" fetch --depth 1 origin "$REVISION"
git -C "$SOURCE_ROOT" checkout --detach FETCH_HEAD

echo "Building SPIRV-Cross revision $REVISION for arm64 iOS"
cmake \
    -S "$SOURCE_ROOT" \
    -B "$BUILD_ROOT" \
    -G Xcode \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$OUTPUT_ROOT" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    -DSPIRV_CROSS_STATIC=ON \
    -DSPIRV_CROSS_SHARED=OFF \
    -DSPIRV_CROSS_CLI=OFF \
    -DSPIRV_CROSS_ENABLE_TESTS=OFF \
    -DSPIRV_CROSS_ENABLE_GLSL=ON \
    -DSPIRV_CROSS_ENABLE_MSL=ON \
    -DSPIRV_CROSS_ENABLE_HLSL=OFF \
    -DSPIRV_CROSS_ENABLE_CPP=OFF \
    -DSPIRV_CROSS_ENABLE_REFLECT=OFF \
    -DSPIRV_CROSS_ENABLE_C_API=OFF \
    -DSPIRV_CROSS_ENABLE_UTIL=OFF \
    -DSPIRV_CROSS_FORCE_PIC=ON \
    2>&1 | tee "$LOG_DIR/spirv-cross-configure.log"

cmake --build "$BUILD_ROOT" --config Release --target install --parallel 3 \
    2>&1 | tee "$LOG_DIR/spirv-cross-build.log"

printf '%s\n' "$REVISION" > "$OUTPUT_ROOT/revision.txt"
for relative in "${required_outputs[@]}"; do
    test -f "$OUTPUT_ROOT/$relative"
done

for library in "$OUTPUT_ROOT"/lib/libspirv-cross-{core,glsl,msl}.a; do
    file "$library"
    lipo -info "$library"
    lipo -info "$library" | grep -q 'arm64'
done | tee "$LOG_DIR/spirv-cross-architectures.txt"

echo "SPIRV-Cross MSL libraries are ready at $OUTPUT_ROOT"
