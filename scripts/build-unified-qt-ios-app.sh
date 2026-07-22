#!/bin/bash
set -euo pipefail

PORT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${1:-$PORT_ROOT/upstream-rpcs3-unified}"
BUILD="${UNIFIED_BUILD:-$PORT_ROOT/cmake-ios-unified}"
TOOLCHAIN="$PORT_ROOT/cmake/toolchains/ios-arm64.cmake"
REVISION="$(tr -d '[:space:]' < "$PORT_ROOT/UPSTREAM_RPCS3_REVISION")"
QT_ROOT="${QT_ROOT:-$HOME/Qt}"
QT_VERSION="${QT_VERSION:-6.11.1}"
IOS_QT="$QT_ROOT/$QT_VERSION/ios"
HOST_QT="$QT_ROOT/$QT_VERSION/macos"
FFMPEG_ROOT="${RPCS3_IOS_FFMPEG_ROOT:-$PORT_ROOT/BuildSupport/ffmpeg-ios}"
MOLTENVK_ROOT="${RPCS3_IOS_MOLTENVK_ROOT:-$PORT_ROOT/BuildSupport/MoltenVK}"
SPIRV_CROSS_ROOT="${RPCS3_IOS_SPIRV_CROSS_ROOT:-$PORT_ROOT/BuildSupport/SPIRV-Cross}"
LOG_DIR="$BUILD/logs"

export RPCS3_IOS_FFMPEG_ROOT="$FFMPEG_ROOT"
export FFMPEG_IOS_ROOT="$FFMPEG_ROOT"
export RPCS3_IOS_MOLTENVK_ROOT="$MOLTENVK_ROOT"
export MOLTENVK_ROOT
export RPCS3_IOS_SPIRV_CROSS_ROOT="$SPIRV_CROSS_ROOT"

command -v cmake >/dev/null
command -v git >/dev/null
command -v python3 >/dev/null
command -v xcrun >/dev/null
test -n "$REVISION"
test -f "$TOOLCHAIN"
test -d "$IOS_QT"
test -d "$HOST_QT"
test -f "$IOS_QT/lib/cmake/Qt6/Qt6Config.cmake"

rm -rf "$ROOT" "$BUILD"
mkdir -p "$BUILD" "$LOG_DIR"

echo "Cloning pinned RPCS3 $REVISION"
git clone --filter=blob:none --depth 1 --branch "$REVISION" --single-branch https://github.com/RPCS3/rpcs3.git "$ROOT"
git -C "$ROOT" submodule sync --recursive
git -C "$ROOT" submodule update --init --recursive --depth 1 --jobs 4

bash "$PORT_ROOT/scripts/generate-qt-ios-sources.sh" "$ROOT" "$BUILD/qt-ui-manifest.json" \
  2>&1 | tee "$LOG_DIR/generate-qt.log"
bash "$PORT_ROOT/scripts/build-ffmpeg-ios.sh" 2>&1 | tee "$LOG_DIR/ffmpeg.log"
bash "$PORT_ROOT/scripts/build-moltenvk-ios.sh" 2>&1 | tee "$LOG_DIR/moltenvk.log"
bash "$PORT_ROOT/scripts/build-spirv-cross-ios.sh" 2>&1 | tee "$LOG_DIR/spirv-cross.log"

python3 "$PORT_ROOT/scripts/apply-upstream-ios-overlay.py" "$ROOT" --mode upstream
python3 "$PORT_ROOT/scripts/patch-upstream-ios-libusb-api.py" "$ROOT"
python3 "$PORT_ROOT/scripts/patch-upstream-ios-cubeb.py" "$ROOT"
python3 "$PORT_ROOT/scripts/patch-upstream-ios-emu-graph.py" "$ROOT"

cmake \
  -S "$ROOT" \
  -B "$BUILD/tree" \
  -G Xcode \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$IOS_QT" \
  -DQt6_DIR="$IOS_QT/lib/cmake/Qt6" \
  -DQT_HOST_PATH="$HOST_QT" \
  -DRPCS3_IOS_UPSTREAM_GRAPH=ON \
  -DRPCS3_IOS_BUILD_QT_HOST=ON \
  -DRPCS3_IOS_PORT_ROOT="$PORT_ROOT" \
  -DRPCS3_IOS_FFMPEG_ROOT="$FFMPEG_ROOT" \
  -DRPCS3_IOS_MOLTENVK_ROOT="$MOLTENVK_ROOT" \
  -DRPCS3_IOS_SPIRV_CROSS_ROOT="$SPIRV_CROSS_ROOT" \
  -DWITH_LLVM=OFF \
  -DBUILD_LLVM=OFF \
  -DBUILD_LLVM_SUBMODULE=OFF \
  -DUSE_VULKAN=ON \
  -DUSE_SYSTEM_MVK=ON \
  -DUSE_SYSTEM_CURL=OFF \
  -DUSE_FAUDIO=OFF \
  -DUSE_PRECOMPILED_HEADERS=OFF \
  2>&1 | tee "$LOG_DIR/configure.log"

cmake --build "$BUILD/tree" --config Release --target RPCS3QtIOS --parallel 3 \
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
nm -gU "$BIN" > "$BUILD/binary-symbols.txt"
c++filt < "$BUILD/binary-symbols.txt" > "$BUILD/binary-symbols-demangled.txt"
strings "$BIN" > "$BUILD/binary-strings.txt"

grep -q 'arm64' "$BUILD/binary-architectures.txt"
grep -q '_rpcs3_ios_core_initialize' "$BUILD/binary-symbols.txt"
grep -q '_rpcs3_ios_core_boot_path' "$BUILD/binary-symbols.txt"
grep -q 'VKGSRender' "$BUILD/binary-symbols-demangled.txt"
grep -q 'metal_gs_render' "$BUILD/binary-symbols-demangled.txt"
grep -q 'RPCS3 Qt iOS upstream main_window.ui' "$BUILD/binary-strings.txt"
grep -q 'Vulkan (MoltenVK)' "$BUILD/binary-strings.txt"
grep -q 'Metal' "$BUILD/binary-strings.txt"

printf '%s\n' "$APP" > "$BUILD/app-path.txt"
cat > "$BUILD/summary.md" <<EOF
# Unified RPCS3 Qt iOS app

- App: \`$APP\`
- Upstream RPCS3: \`$REVISION\`
- CPU lane: PPU/SPU interpreters
- Vulkan lane: RPCS3 \`VKGSRender\` -> MoltenVK -> \`CAMetalLayer\`
- Metal lane: native \`metal_gs_render\`, validated draw encoder, SPIR-V -> MSL translation, and cached Metal shader functions; live RSX vertex/texture binding remains in progress
- UI: real Qt Widgets \`main_window.ui\`
- Core: real \`rpcs3_emu\`, \`Emu.System\`, boot/pause/resume/stop/VSH/PKG/PUP bridge
EOF
cat "$BUILD/summary.md"
