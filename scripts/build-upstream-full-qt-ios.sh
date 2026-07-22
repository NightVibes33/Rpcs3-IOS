#!/bin/bash
set -euo pipefail

ROOT="${FULL_QT_ROOT:-upstream-rpcs3-full-qt}"
BUILD="${FULL_QT_BUILD:-full-rpcs3-qt-ios-build}"
PORT_ROOT="$(pwd)"
REVISION_FILE="$PORT_ROOT/UPSTREAM_RPCS3_REVISION"
TOOLCHAIN="$PORT_ROOT/cmake/toolchains/ios-arm64.cmake"
QT_ROOT="${QT_ROOT:-$HOME/Qt}"
QT_VERSION="${QT_VERSION:-6.11.1}"
IOS_QT="$QT_ROOT/$QT_VERSION/ios"
HOST_QT="$QT_ROOT/$QT_VERSION/macos"
QT_CMAKE="$IOS_QT/bin/qt-cmake"
FFMPEG_ROOT="${RPCS3_IOS_FFMPEG_ROOT:-$PORT_ROOT/BuildSupport/ffmpeg-ios}"
MOLTENVK_ROOT="${MOLTENVK_IOS_ROOT:-$PORT_ROOT/BuildSupport/moltenvk-ios}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-26.0}"

export RPCS3_IOS_FFMPEG_ROOT="$FFMPEG_ROOT"
export FFMPEG_IOS_ROOT="$FFMPEG_ROOT"
export MOLTENVK_IOS_ROOT="$MOLTENVK_ROOT"

print_failure_logs() {
  local status=$?
  if [[ $status -ne 0 ]]; then
    echo "Full upstream RPCS3 Qt iOS build failed (status=$status)."
    if [[ -d "$BUILD/logs" ]]; then
      while IFS= read -r log; do
        echo
        echo "===== tail: $log ====="
        tail -n 180 "$log" || true
      done < <(find "$BUILD/logs" -maxdepth 1 -type f -name '*.log' -print | sort)
    fi
  fi
  exit "$status"
}
trap print_failure_logs EXIT

for required in \
  "$REVISION_FILE" \
  "$TOOLCHAIN" \
  "$QT_CMAKE" \
  "$HOST_QT" \
  "$PORT_ROOT/scripts/build-ffmpeg-ios.sh" \
  "$PORT_ROOT/scripts/build-moltenvk-ios.sh" \
  "$PORT_ROOT/scripts/patch-upstream-ios-emu-graph.py" \
  "$PORT_ROOT/scripts/patch-upstream-ios-full-qt-blockers.py"; do
  test -e "$required"
done

UPSTREAM_REVISION="$(tr -d '[:space:]' < "$REVISION_FILE")"
test -n "$UPSTREAM_REVISION"

rm -rf "$ROOT" "$BUILD"
mkdir -p "$BUILD/logs"

git clone --filter=blob:none --depth 1 --branch "$UPSTREAM_REVISION" --single-branch \
  https://github.com/RPCS3/rpcs3.git "$ROOT" \
  >"$BUILD/logs/clone.log" 2>&1
git -C "$ROOT" submodule sync --recursive \
  >"$BUILD/logs/submodule-sync.log" 2>&1
git -C "$ROOT" submodule update --init --recursive --depth 1 --jobs 4 \
  >"$BUILD/logs/submodules.log" 2>&1

bash scripts/build-ffmpeg-ios.sh >"$BUILD/logs/ffmpeg.log" 2>&1
bash scripts/build-moltenvk-ios.sh >"$BUILD/logs/moltenvk.log" 2>&1

python3 scripts/apply-upstream-ios-overlay.py "$ROOT" --mode upstream \
  >"$BUILD/logs/overlay.log" 2>&1
python3 scripts/patch-upstream-ios-libusb-api.py "$ROOT" \
  >"$BUILD/logs/libusb.log" 2>&1
python3 scripts/patch-upstream-ios-cubeb.py "$ROOT" \
  >"$BUILD/logs/cubeb.log" 2>&1
python3 scripts/patch-upstream-ios-emu-graph.py "$ROOT" \
  >"$BUILD/logs/full-qt-graph.log" 2>&1
python3 scripts/patch-upstream-ios-full-qt-blockers.py "$ROOT" \
  >"$BUILD/logs/full-qt-platform-blockers.log" 2>&1

UPSTREAM_SHA="$(git -C "$ROOT" rev-parse HEAD)"
printf '%s\n' "$UPSTREAM_SHA" > "$BUILD/upstream-revision.txt"

"$QT_CMAKE" \
  -S "$ROOT" \
  -B "$BUILD/tree" \
  -G Xcode \
  -DQT_HOST_PATH="$HOST_QT" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY='' \
  -DRPCS3_IOS_UPSTREAM_GRAPH=ON \
  -DRPCS3_IOS_FULL_QT_FRONTEND=ON \
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

# These files prove that the target is the actual RPCS3 application graph rather
# than the local Qt shell that only consumes upstream Designer documents.
for required_source in \
  'rpcs3/rpcs3.cpp' \
  'rpcs3/rpcs3qt/main_window.cpp' \
  'rpcs3/rpcs3qt/game_list_frame.cpp' \
  'rpcs3/rpcs3qt/settings_dialog.cpp' \
  'rpcs3/rpcs3qt/pkg_install_dialog.cpp' \
  'rpcs3/rpcs3qt/save_manager_dialog.cpp' \
  'rpcs3/rpcs3qt/trophy_manager_dialog.cpp'; do
  grep -q "$required_source" "$BUILD/tree/compile_commands.json" || {
    echo "The full frontend graph omitted $required_source" >&2
    exit 1
  }
done

cmake --build "$BUILD/tree" --config Release --target rpcs3 --parallel 3 \
  >"$BUILD/logs/build-full-rpcs3.log" 2>&1

APP="$(find "$BUILD/tree" -type d \( -name 'RPCS3-iOS.app' -o -name 'rpcs3.app' \) -path '*Release*' -print | head -n 1)"
test -n "$APP"
test -d "$APP"
BIN="$(find "$APP" -maxdepth 1 -type f \( -name 'RPCS3-iOS' -o -name 'rpcs3' \) -print | head -n 1)"
test -n "$BIN"
test -f "$BIN"

file "$BIN" | tee "$BUILD/binary-file.txt"
lipo -info "$BIN" | tee "$BUILD/binary-architectures.txt"
otool -L "$BIN" | tee "$BUILD/binary-linked-libraries.txt"
nm -gU "$BIN" > "$BUILD/binary-symbols.txt"
strings "$BIN" > "$BUILD/binary-strings.txt"

# Validate real frontend implementation, not copied .ui files.
for symbol_fragment in \
  'main_window' \
  'game_list_frame' \
  'settings_dialog' \
  'pkg_install_dialog'; do
  grep -qi "$symbol_fragment" "$BUILD/binary-symbols.txt" "$BUILD/binary-strings.txt"
done

printf '%s\n' "$APP" > "$BUILD/app-path.txt"
cat > "$BUILD/summary.md" <<EOF
# Full upstream RPCS3 Qt frontend for iOS

- Requested revision: \`$UPSTREAM_REVISION\`
- Resolved commit: \`$UPSTREAM_SHA\`
- Product: \`$APP\`
- Target: \`arm64-apple-ios$DEPLOYMENT_TARGET\`
- Frontend target: upstream \`rpcs3_ui\` + \`rpcs3_lib\` + \`rpcs3\`
- Main implementation: upstream \`rpcs3qt/main_window.cpp\`
- Game list: upstream \`game_list_frame.cpp\`
- Settings: upstream \`settings_dialog.cpp\`
- Package UI: upstream \`pkg_install_dialog.cpp\`
- This target does not use the local copied-form shell under \`QtApp/\`.
EOF
cat "$BUILD/summary.md"
trap - EXIT
