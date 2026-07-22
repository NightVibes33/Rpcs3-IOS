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

find_device_binary() {
    local candidate
    while IFS= read -r candidate; do
        case "$candidate" in
            *simulator*|*maccatalyst*) continue ;;
        esac
        if lipo -info "$candidate" 2>/dev/null | grep -q 'arm64'; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done < <(find "$FRAMEWORK" \( -type f -o -type l \) \( -path '*/MoltenVK.framework/MoltenVK' -o -name 'libMoltenVK.a' \) -print 2>/dev/null | sort)
    return 1
}

DEVICE_BINARY="$(find_device_binary || true)"
if [[ -n "$DEVICE_BINARY" && -f "$OUTPUT_ROOT/revision.txt" ]] &&
   [[ "$(tr -d '[:space:]' < "$OUTPUT_ROOT/revision.txt")" == "$REVISION" ]] &&
   [[ -f "$OUTPUT_ROOT/include/vulkan/vulkan.h" ]] &&
   [[ -f "$OUTPUT_ROOT/include/vk_video/vulkan_video_codec_h264std.h" ]] &&
   [[ -f "$OUTPUT_ROOT/include/vk_video/vulkan_video_codec_h265std.h" ]] &&
   [[ -f "$OUTPUT_ROOT/include/MoltenVK/vk_mvk_moltenvk.h" ]]; then
    printf '%s\n' "${DEVICE_BINARY#"$OUTPUT_ROOT/"}" > "$OUTPUT_ROOT/device-binary-path.txt"
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

VULKAN_INCLUDE_ROOT="$SOURCE_ROOT/External/Vulkan-Headers/include"
VULKAN_HEADERS="$VULKAN_INCLUDE_ROOT/vulkan"
VULKAN_VIDEO_HEADERS="$VULKAN_INCLUDE_ROOT/vk_video"
MOLTENVK_API="$SOURCE_ROOT/MoltenVK/MoltenVK/API"
test -f "$VULKAN_HEADERS/vulkan.h"
test -f "$VULKAN_VIDEO_HEADERS/vulkan_video_codec_h264std.h"
test -f "$VULKAN_VIDEO_HEADERS/vulkan_video_codec_h265std.h"
test -f "$MOLTENVK_API/vk_mvk_moltenvk.h"

mkdir -p "$OUTPUT_ROOT/include/MoltenVK"
cp -R "$PACKAGE" "$FRAMEWORK"
cp -R "$VULKAN_HEADERS" "$OUTPUT_ROOT/include/vulkan"
cp -R "$VULKAN_VIDEO_HEADERS" "$OUTPUT_ROOT/include/vk_video"
find "$MOLTENVK_API" -maxdepth 1 -type f -name '*.h' -exec cp {} "$OUTPUT_ROOT/include/MoltenVK/" \;
printf '%s\n' "$REVISION" > "$OUTPUT_ROOT/revision.txt"

DEVICE_BINARY="$(find_device_binary)"
test -f "$DEVICE_BINARY"
printf '%s\n' "${DEVICE_BINARY#"$OUTPUT_ROOT/"}" > "$OUTPUT_ROOT/device-binary-path.txt"
test -f "$OUTPUT_ROOT/include/vulkan/vulkan.h"
test -f "$OUTPUT_ROOT/include/vk_video/vulkan_video_codec_h264std.h"
test -f "$OUTPUT_ROOT/include/vk_video/vulkan_video_codec_h265std.h"
test -f "$OUTPUT_ROOT/include/MoltenVK/vk_mvk_moltenvk.h"

find "$FRAMEWORK" -maxdepth 4 -print | sort > "$LOG_DIR/moltenvk-package-layout.txt"
find "$OUTPUT_ROOT/include/vk_video" -maxdepth 1 -type f -print | sort > "$LOG_DIR/moltenvk-vulkan-video-headers.txt"
file "$DEVICE_BINARY" | tee "$LOG_DIR/moltenvk-binary.txt"
lipo -info "$DEVICE_BINARY" | tee "$LOG_DIR/moltenvk-architectures.txt"
grep -q 'arm64' "$LOG_DIR/moltenvk-architectures.txt"
echo "MoltenVK is ready at $OUTPUT_ROOT ($DEVICE_BINARY)"
