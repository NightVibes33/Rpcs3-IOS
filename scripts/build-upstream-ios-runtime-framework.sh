#!/bin/bash
set -euo pipefail

ROOT="${1:-upstream-rpcs3-runtime}"
BUILD="${RUNTIME_BUILD:-cmake-ios-runtime-framework}"
PRODUCT_DIR="${PRODUCT_DIR:-BuildSupport}"
PORT_ROOT="$(pwd)"
TOOLCHAIN="$PORT_ROOT/cmake/toolchains/ios-arm64.cmake"
REVISION_FILE="$PORT_ROOT/UPSTREAM_RPCS3_REVISION"
FFMPEG_ROOT="${RPCS3_IOS_FFMPEG_ROOT:-$PORT_ROOT/BuildSupport/ffmpeg-ios}"
MOLTENVK_ROOT="${MOLTENVK_IOS_ROOT:-$PORT_ROOT/BuildSupport/moltenvk-ios}"
OUTPUT="$PORT_ROOT/$PRODUCT_DIR/RPCS3UpstreamRuntime.framework"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-26.0}"

export RPCS3_IOS_FFMPEG_ROOT="$FFMPEG_ROOT"
export FFMPEG_IOS_ROOT="$FFMPEG_ROOT"
export MOLTENVK_IOS_ROOT="$MOLTENVK_ROOT"

print_failure_logs() {
  local status=$?
  if [[ $status -ne 0 && -d "$BUILD/logs" ]]; then
    echo "RPCS3 upstream runtime framework build failed (status=$status)."
    while IFS= read -r log; do
      echo
      echo "===== tail: $log ====="
      tail -n 160 "$log" || true
    done < <(find "$BUILD/logs" -maxdepth 1 -type f -name '*.log' -print | sort)
  fi
  exit "$status"
}
trap print_failure_logs EXIT

command -v cmake >/dev/null
command -v git >/dev/null
command -v python3 >/dev/null
command -v xcrun >/dev/null

for required in \
  "$REVISION_FILE" \
  "$PORT_ROOT/scripts/build-moltenvk-ios.sh" \
  "$PORT_ROOT/scripts/patch-upstream-ios-cubeb.py" \
  "$PORT_ROOT/CoreBridge/RPCS3UpstreamFirmwareInstaller.cpp" \
  "$PORT_ROOT/CoreBridge/RPCS3IOSPadBridge.cpp"; do
  test -f "$required"
done
UPSTREAM_REVISION="$(tr -d '[:space:]' < "$REVISION_FILE")"
test -n "$UPSTREAM_REVISION"

rm -rf "$ROOT" "$BUILD" "$OUTPUT"
mkdir -p "$BUILD/logs" "$PRODUCT_DIR"

git clone --filter=blob:none --depth 1 --branch "$UPSTREAM_REVISION" --single-branch \
  https://github.com/RPCS3/rpcs3.git "$ROOT" \
  >"$BUILD/logs/clone.log" 2>&1
git -C "$ROOT" submodule sync --recursive \
  >"$BUILD/logs/submodule-sync.log" 2>&1
git -C "$ROOT" submodule update --init --recursive --depth 1 --jobs 4 \
  >"$BUILD/logs/submodules.log" 2>&1

bash scripts/build-ffmpeg-ios.sh \
  >"$BUILD/logs/ffmpeg.log" 2>&1
bash scripts/build-moltenvk-ios.sh \
  >"$BUILD/logs/moltenvk.log" 2>&1

test -f "$MOLTENVK_ROOT/include/vulkan/vulkan.h"
test -f "$MOLTENVK_ROOT/lib/libMoltenVK.a"

python3 scripts/apply-upstream-ios-overlay.py "$ROOT" --mode upstream \
  >"$BUILD/logs/overlay.log" 2>&1
python3 scripts/patch-upstream-ios-libusb-api.py "$ROOT" \
  >"$BUILD/logs/libusb.log" 2>&1
python3 scripts/patch-upstream-ios-cubeb.py "$ROOT" \
  >"$BUILD/logs/cubeb.log" 2>&1
python3 scripts/patch-upstream-ios-emu-graph.py "$ROOT" \
  >"$BUILD/logs/runtime-graph.log" 2>&1

GENERATED_RUNTIME_BRIDGE="$ROOT/rpcs3/Emu/RPCS3IOSUpstreamRuntimeBridge.cpp"
test -f "$GENERATED_RUNTIME_BRIDGE"
grep -q 'Emu/Audio/Cubeb/CubebBackend.h' "$GENERATED_RUNTIME_BRIDGE"
grep -q 'audio_renderer::cubeb' "$GENERATED_RUNTIME_BRIDGE"
grep -q 'std::make_shared<CubebBackend>()' "$GENERATED_RUNTIME_BRIDGE"
grep -q 'std::make_shared<cubeb_enumerator>()' "$GENERATED_RUNTIME_BRIDGE"

UPSTREAM_SHA="$(git -C "$ROOT" rev-parse HEAD)"
printf '%s\n' "$UPSTREAM_SHA" > "$BUILD/upstream-revision.txt"
git -C "$ROOT" submodule status --recursive > "$BUILD/upstream-submodules.txt"

cmake \
  -S "$ROOT" \
  -B "$BUILD/tree" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  -DRPCS3_IOS_UPSTREAM_GRAPH=ON \
  -DRPCS3_IOS_PORT_ROOT="$PORT_ROOT" \
  -DRPCS3_IOS_FFMPEG_ROOT="$FFMPEG_ROOT" \
  -DWITH_LLVM=OFF \
  -DBUILD_LLVM=OFF \
  -DBUILD_LLVM_SUBMODULE=OFF \
  -DUSE_VULKAN=ON \
  -DUSE_SYSTEM_MVK=ON \
  -DVulkan_INCLUDE_DIR="$MOLTENVK_ROOT/include" \
  -DVulkan_LIBRARY="$MOLTENVK_ROOT/lib/libMoltenVK.a" \
  -DUSE_OPENGL=OFF \
  -DUSE_SYSTEM_CURL=OFF \
  -DUSE_FAUDIO=OFF \
  -DUSE_PRECOMPILED_HEADERS=OFF \
  >"$BUILD/logs/configure.log" 2>&1

cmake --build "$BUILD/tree" \
  --target rpcs3_ios_upstream_runtime \
  --config Release \
  --parallel 3 \
  >"$BUILD/logs/build-runtime-framework.log" 2>&1

FRAMEWORK="$(find "$BUILD/tree" -type d -name 'RPCS3UpstreamRuntime.framework' -print | head -n 1)"
test -n "$FRAMEWORK"
test -d "$FRAMEWORK"
test -f "$FRAMEWORK/RPCS3UpstreamRuntime"
test -f "$FRAMEWORK/Headers/RPCS3UpstreamRuntimeBridge.h"

/usr/bin/ditto "$FRAMEWORK" "$OUTPUT"

file "$OUTPUT/RPCS3UpstreamRuntime" | tee "$BUILD/framework-file.txt"
lipo -info "$OUTPUT/RPCS3UpstreamRuntime" | tee "$BUILD/framework-architectures.txt"
otool -L "$OUTPUT/RPCS3UpstreamRuntime" | tee "$BUILD/framework-linked-libraries.txt"
nm -gU "$OUTPUT/RPCS3UpstreamRuntime" > "$BUILD/framework-symbols.txt"
strings "$OUTPUT/RPCS3UpstreamRuntime" > "$BUILD/framework-strings.txt"

for symbol in \
  _rpcs3_ios_upstream_set_render_view \
  _rpcs3_ios_upstream_render_view_ready \
  _rpcs3_ios_upstream_initialize \
  _rpcs3_ios_upstream_install_firmware \
  _rpcs3_ios_upstream_firmware_ready \
  _rpcs3_ios_upstream_firmware_version \
  _rpcs3_ios_upstream_firmware_last_message \
  _rpcs3_ios_upstream_install_pkg \
  _rpcs3_ios_upstream_last_installed_boot_path \
  _rpcs3_ios_upstream_boot_game \
  _rpcs3_ios_upstream_set_pad_state \
  _rpcs3_ios_upstream_pause \
  _rpcs3_ios_upstream_resume \
  _rpcs3_ios_upstream_stop; do
  grep -q "$symbol" "$BUILD/framework-symbols.txt"
done
grep -q '_vkCreateInstance' "$BUILD/framework-symbols.txt"
grep -q '_vkCreateMetalSurfaceEXT' "$BUILD/framework-symbols.txt"
grep -q 'Cubeb' "$BUILD/framework-strings.txt"
grep -q 'AudioToolbox.framework' "$BUILD/framework-linked-libraries.txt"

cat > "$BUILD/summary.md" <<EOF
# RPCS3 upstream iOS runtime framework

- Requested revision: \`$UPSTREAM_REVISION\`
- Resolved commit: \`$UPSTREAM_SHA\`
- Product: \`$OUTPUT\`
- Target: \`arm64-apple-ios$DEPLOYMENT_TARGET\`
- PPU lane: upstream static interpreter
- SPU lane: upstream static interpreter
- Renderer lane: upstream Vulkan through pinned MoltenVK, with Null fallback
- Native surface: Qt iOS \`UIView\` hosting a runtime-owned \`CAMetalLayer\`
- MoltenVK: \`$(cat "$MOLTENVK_ROOT/version.txt")\`
- Audio: upstream Cubeb through iOS AudioUnit/AudioToolbox, with Null fallback only when initialization fails
- Firmware installer: upstream PUP validation, SCE decryption, and nested TAR extraction into \`dev_flash\`
- Package installer: upstream \`package_reader::extract_data\`
- Input: touch overlay feeds a connected RPCS3 LDD/cellPad controller
- Exported lifecycle: render surface, initialize, install firmware, install PKG, BootGame, pad state, pause, resume, stop, state
- Data root: host-selected RPCS3 sandbox through RPCS3_CONFIG_DIR
EOF

cat "$BUILD/summary.md"
trap - EXIT
