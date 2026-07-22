#!/bin/bash
set -euo pipefail

PORT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${UNIFIED_UPSTREAM_ROOT:-$PORT_ROOT/upstream-rpcs3-unified}"
BUILD="${UNIFIED_BUILD_ROOT:-$PORT_ROOT/unified-ios-build}"
OUTPUT="${UNIFIED_OUTPUT_ROOT:-$PORT_ROOT/unified-output}"
REVISION="$(tr -d '[:space:]' < "$PORT_ROOT/UPSTREAM_RPCS3_REVISION")"
QT_ROOT="${QT_ROOT:-$HOME/Qt}"
QT_VERSION="${QT_VERSION:-6.11.1}"
QT_IOS="$QT_ROOT/$QT_VERSION/ios"
QT_HOST="$QT_ROOT/$QT_VERSION/macos"
QT_CMAKE="$QT_IOS/bin/qt-cmake"
FFMPEG_ROOT="${RPCS3_IOS_FFMPEG_ROOT:-$PORT_ROOT/BuildSupport/ffmpeg-ios}"
MOLTENVK_ROOT="${RPCS3_IOS_MOLTENVK_ROOT:-$PORT_ROOT/BuildSupport/MoltenVK}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-26.0}"
LOG_DIR="${CI_LOGS:-$BUILD/logs}"

export RPCS3_IOS_FFMPEG_ROOT="$FFMPEG_ROOT"
export FFMPEG_IOS_ROOT="$FFMPEG_ROOT"
export RPCS3_IOS_MOLTENVK_ROOT="$MOLTENVK_ROOT"
export MOLTENVK_ROOT

command -v git >/dev/null
command -v cmake >/dev/null
command -v python3 >/dev/null
command -v xcrun >/dev/null
test -n "$REVISION"
test -x "$QT_CMAKE"
test -d "$QT_HOST"

rm -rf "$ROOT" "$BUILD" "$OUTPUT"
mkdir -p "$BUILD" "$OUTPUT" "$LOG_DIR"

run_logged() {
    local name="$1"
    shift
    echo "=== $name ==="
    "$@" 2>&1 | tee "$LOG_DIR/$name.log"
}

run_logged clone git clone \
    --filter=blob:none \
    --depth 1 \
    --branch "$REVISION" \
    --single-branch \
    https://github.com/RPCS3/rpcs3.git "$ROOT"
run_logged submodule-sync git -C "$ROOT" submodule sync --recursive
run_logged submodule-update git -C "$ROOT" submodule update --init --recursive --depth 1 --jobs 4

run_logged ffmpeg bash "$PORT_ROOT/scripts/build-ffmpeg-ios.sh"
run_logged moltenvk bash "$PORT_ROOT/scripts/build-moltenvk-ios.sh"

test -f "$FFMPEG_ROOT/lib/libavcodec.a"
test -f "$FFMPEG_ROOT/include/libavutil/pixfmt.h"
test -f "$MOLTENVK_ROOT/device-binary-path.txt"
MOLTENVK_BINARY="$MOLTENVK_ROOT/$(tr -d '\r\n' < "$MOLTENVK_ROOT/device-binary-path.txt")"
test -f "$MOLTENVK_BINARY"
test -f "$MOLTENVK_ROOT/include/vulkan/vulkan.h"

run_logged prepare-ui bash "$PORT_ROOT/scripts/prepare-qt-ios-ui.sh" "$ROOT" "$BUILD/upstream-ui-manifest.json"
run_logged overlay python3 "$PORT_ROOT/scripts/apply-upstream-ios-overlay.py" "$ROOT" --mode upstream
run_logged libusb python3 "$PORT_ROOT/scripts/patch-upstream-ios-libusb-api.py" "$ROOT"
run_logged cubeb python3 "$PORT_ROOT/scripts/patch-upstream-ios-cubeb.py" "$ROOT"
run_logged emu-graph python3 "$PORT_ROOT/scripts/patch-upstream-ios-emu-graph.py" "$ROOT"

"$QT_CMAKE" \
    -S "$ROOT" \
    -B "$BUILD/tree" \
    -G Xcode \
    -DQT_HOST_PATH="$QT_HOST" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    -DCMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH=YES \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY='' \
    -DRPCS3_IOS_UPSTREAM_GRAPH=ON \
    -DRPCS3_IOS_BUILD_QT_HOST=ON \
    -DRPCS3_IOS_UNIFIED_UPSTREAM=ON \
    -DRPCS3_IOS_PORT_ROOT="$PORT_ROOT" \
    -DRPCS3_IOS_FFMPEG_ROOT="$FFMPEG_ROOT" \
    -DRPCS3_IOS_MOLTENVK_ROOT="$MOLTENVK_ROOT" \
    -DWITH_LLVM=OFF \
    -DBUILD_LLVM=OFF \
    -DBUILD_LLVM_SUBMODULE=OFF \
    -DUSE_VULKAN=ON \
    -DUSE_SYSTEM_MVK=ON \
    -DUSE_SYSTEM_CURL=OFF \
    -DUSE_FAUDIO=OFF \
    -DUSE_PRECOMPILED_HEADERS=OFF \
    2>&1 | tee "$LOG_DIR/configure.log"

cmake --build "$BUILD/tree" \
    --target RPCS3QtIOS \
    --config Release \
    --parallel 3 \
    2>&1 | tee "$LOG_DIR/build.log"

APP="$(find "$BUILD/tree" -type d -name 'RPCS3-iOS.app' -path '*Release*' -print | head -n 1)"
if [[ -z "$APP" ]]; then
    APP="$(find "$BUILD/tree" -type d -name 'RPCS3-iOS.app' -print | head -n 1)"
fi
test -n "$APP"
test -d "$APP"
BIN="$APP/RPCS3-iOS"
test -f "$BIN"

file "$BIN" | tee "$BUILD/binary-file.txt"
lipo -info "$BIN" | tee "$BUILD/binary-architectures.txt"
xcrun vtool -show-build "$BIN" | tee "$BUILD/binary-build-version.txt" || true
strings "$BIN" > "$BUILD/binary-strings.txt"
nm -gU "$BIN" > "$BUILD/binary-symbols.txt"

for marker in \
    'RPCS3 Qt iOS upstream main_window.ui' \
    'Vulkan (MoltenVK)' \
    'Native Metal submitted and presented a frame' \
    'MoltenVK submitted and presented a Vulkan frame through Metal' \
    'RPCS3 Emu.System initialized'; do
    grep -q "$marker" "$BUILD/binary-strings.txt"
done

for symbol in \
    '_rpcs3_ios_core_initialize' \
    '_rpcs3_ios_core_boot_path' \
    '_rpcs3_ios_core_set_renderer' \
    '_vkCreateInstance' \
    '_MTLCreateSystemDefaultDevice'; do
    grep -q "$symbol" "$BUILD/binary-symbols.txt"
done

grep -q 'arm64' "$BUILD/binary-file.txt"

rm -rf "$BUILD/Payload"
mkdir -p "$BUILD/Payload"
cp -R "$APP" "$BUILD/Payload/RPCS3-iOS.app"
rm -rf "$BUILD/Payload/RPCS3-iOS.app/_CodeSignature"
rm -f "$BUILD/Payload/RPCS3-iOS.app/embedded.mobileprovision"
SHORT_REVISION="$(git -C "$PORT_ROOT" rev-parse --short HEAD 2>/dev/null || printf 'local')"
IPA="$OUTPUT/RPCS3-Qt-Emu-Vulkan-Metal-iOS26-${SHORT_REVISION}-unsigned.ipa"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$BUILD/Payload" "$IPA"
shasum -a 256 "$IPA" > "$IPA.sha256"
unzip -l "$IPA" > "$BUILD/ipa-contents.txt"
printf '%s\n' "$APP" > "$BUILD/app-path.txt"
printf '%s\n' "$IPA" > "$BUILD/ipa-path.txt"

cat > "$BUILD/summary.md" <<EOF
# Unified RPCS3 Qt iOS build

- Upstream revision: \`$REVISION\`
- App target: \`RPCS3QtIOS\`
- Architecture: \`arm64-apple-ios$DEPLOYMENT_TARGET\`
- Qt root window: upstream \`main_window.ui\`
- Execution core: upstream \`Emu.System\`, PPU interpreter, SPU interpreter
- Vulkan: upstream \`VKGSRender\` linked to \`$MOLTENVK_BINARY\`
- Metal: native \`metal_gs_render\` and \`CAMetalLayer\` host
- IPA: \`$IPA\`
- JIT: intentionally disabled in this interpreter-first lane
- Native Metal currently has real device, queue, surface, command submission, and presentation; full RSX draw/shader/texture/synchronization translation remains under development.
EOF

cat "$BUILD/summary.md"
ls -lh "$OUTPUT"
