#!/bin/bash
set -euo pipefail

PORT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REVISION_FILE="$PORT_ROOT/MOLTENVK_REVISION"
SOURCE_ROOT="${MOLTENVK_SOURCE_ROOT:-$PORT_ROOT/.deps/MoltenVK}"
OUTPUT_ROOT="${MOLTENVK_ROOT:-$PORT_ROOT/BuildSupport/MoltenVK}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-26.0}"
LOG_DIR="${CI_LOGS:-$PORT_ROOT/ci-logs}"
REVISION="$(tr -d '[:space:]' < "$REVISION_FILE")"

mkdir -p "$LOG_DIR" "$PORT_ROOT/.deps" "$PORT_ROOT/BuildSupport"
test -n "$REVISION"

FRAMEWORK="$OUTPUT_ROOT/MoltenVK.xcframework"
DEVICE_BINARY="$FRAMEWORK/ios-arm64/MoltenVK.framework/MoltenVK"
if [[ -f "$DEVICE_BINARY" && -f "$OUTPUT_ROOT/revision.txt" ]] &&
   [[ "$(tr -d '[:space:]' < "$OUTPUT_ROOT/revision.txt")" == "$REVISION" ]]; then
    echo "Using cached MoltenVK $REVISION from $OUTPUT_ROOT"
    exit 0
fi

rm -rf "$SOURCE_ROOT" "$OUTPUT_ROOT"
git clone --filter=blob:none --no-checkout https://github.com/KhronosGroup/MoltenVK.git "$SOURCE_ROOT"
git -C "$SOURCE_ROOT" fetch --depth 1 origin "$REVISION"
git -C "$SOURCE_ROOT" checkout --detach FETCH_HEAD

echo "Building MoltenVK revision $REVISION for arm64 iOS"
(
    cd "$SOURCE_ROOT"
    ./fetchDependencies --ios
    xcodebuild \
        -project MoltenVKPackaging.xcodeproj \
        -scheme "MoltenVK Package (iOS only)" \
        -configuration Release \
        -destination "generic/platform=iOS" \
        ONLY_ACTIVE_ARCH=YES \
        ARCHS=arm64 \
        SDKROOT=iphoneos \
        IPHONEOS_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        build
) 2>&1 | tee "$LOG_DIR/moltenvk-build.log"

PACKAGE="$SOURCE_ROOT/Package/Latest/MoltenVK/static/MoltenVK.xcframework"
if [[ ! -d "$PACKAGE" ]]; then
    PACKAGE="$SOURCE_ROOT/Package/Release/MoltenVK/static/MoltenVK.xcframework"
fi
test -d "$PACKAGE"

mkdir -p "$OUTPUT_ROOT"
cp -R "$PACKAGE" "$FRAMEWORK"
cp -R "$SOURCE_ROOT/MoltenVK/include" "$OUTPUT_ROOT/include"
printf '%s\n' "$REVISION" > "$OUTPUT_ROOT/revision.txt"

DEVICE_BINARY="$FRAMEWORK/ios-arm64/MoltenVK.framework/MoltenVK"
test -f "$DEVICE_BINARY"
test -f "$OUTPUT_ROOT/include/vulkan/vulkan.h"
test -f "$OUTPUT_ROOT/include/MoltenVK/vk_mvk_moltenvk.h"
file "$DEVICE_BINARY" | tee "$LOG_DIR/moltenvk-binary.txt"
lipo -info "$DEVICE_BINARY" | tee "$LOG_DIR/moltenvk-architectures.txt"

grep -q 'arm64' "$LOG_DIR/moltenvk-architectures.txt"
echo "MoltenVK is ready at $OUTPUT_ROOT"
