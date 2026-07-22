#!/bin/bash
set -euo pipefail

ROOT="${1:-upstream-rpcs3-graph}"
BUILD="${BUILD:-cmake-ios-upstream-graph}"
PORT_ROOT="$(pwd)"
TOOLCHAIN="$PORT_ROOT/cmake/toolchains/ios-arm64.cmake"
REVISION_FILE="$PORT_ROOT/UPSTREAM_RPCS3_REVISION"
LOG_DIR="$BUILD/logs"
PHASE_LOG="$LOG_DIR/phases.log"
TIMEOUT_RUNNER="$PORT_ROOT/scripts/run-with-timeout.py"

UPSTREAM_REVISION="$(tr -d '[:space:]' < "$REVISION_FILE")"
test -n "$UPSTREAM_REVISION"
test -f "$TIMEOUT_RUNNER"

rm -rf "$ROOT" "$BUILD"
mkdir -p "$LOG_DIR"

phase() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$PHASE_LOG"
}

run_timed() {
  local seconds="$1"
  shift
  phase "RUN timeout=${seconds}s: $*"
  set +e
  python3 "$TIMEOUT_RUNNER" "$seconds" "$@" 2>&1 | tee -a "$PHASE_LOG"
  local status=${PIPESTATUS[0]}
  set -e
  if [[ $status -ne 0 ]]; then
    phase "FAILED status=$status: $*"
  fi
  return "$status"
}

phase "Clone pinned upstream tag $UPSTREAM_REVISION"
run_timed 900 git clone --filter=blob:none --depth 1 --branch "$UPSTREAM_REVISION" --single-branch https://github.com/RPCS3/rpcs3.git "$ROOT"

phase "Initialize upstream submodules"
run_timed 1800 git -C "$ROOT" submodule sync --recursive
run_timed 3600 git -C "$ROOT" submodule update --init --recursive --depth 1 --jobs 4

phase "Export the complete upstream Qt UI hierarchy"
run_timed 180 python3 scripts/export-upstream-qt-ui-model.py "$ROOT" "$BUILD/rpcs3-qt-ui-model.json"

phase "Apply iOS upstream-graph overlay"
run_timed 120 python3 scripts/apply-upstream-ios-overlay.py "$ROOT" --mode upstream
run_timed 120 python3 scripts/patch-upstream-ios-emu-graph.py "$ROOT"

git -C "$ROOT" rev-parse HEAD | tee "$BUILD/upstream-revision.txt"
git -C "$ROOT" submodule status --recursive > "$BUILD/upstream-submodules.txt"

phase "Configure RPCS3 real top-level graph for arm64 iOS"
set +e
python3 "$TIMEOUT_RUNNER" 3600 cmake \
  -S "$ROOT" \
  -B "$BUILD/tree" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DCMAKE_BUILD_TYPE=Release \
  -DRPCS3_IOS_UPSTREAM_GRAPH=ON \
  -DRPCS3_IOS_PORT_ROOT="$PORT_ROOT" \
  -DWITH_LLVM=OFF \
  -DBUILD_LLVM=OFF \
  -DBUILD_LLVM_SUBMODULE=OFF \
  -DUSE_SYSTEM_CURL=OFF \
  -DUSE_FAUDIO=OFF \
  -DUSE_PRECOMPILED_HEADERS=OFF \
  2>&1 | tee "$LOG_DIR/configure.log"
configure_status=${PIPESTATUS[0]}
set -e
phase "CMake configure exit status=$configure_status"

build_status=125
if [[ $configure_status -eq 0 ]]; then
  phase "Compile the real upstream rpcs3_emu target for arm64 iOS"
  set +e
  python3 "$TIMEOUT_RUNNER" 7200 cmake --build "$BUILD/tree" \
    --target rpcs3_emu \
    --config Release \
    --parallel 3 \
    2>&1 | tee "$LOG_DIR/build-rpcs3-emu.log"
  build_status=${PIPESTATUS[0]}
  set -e
  phase "rpcs3_emu build exit status=$build_status"
else
  phase "Skipping rpcs3_emu compile because configure failed"
fi

status=$configure_status
if [[ $configure_status -eq 0 ]]; then
  status=$build_status
fi

ui_file_count="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["ui_file_count"])' "$BUILD/rpcs3-qt-ui-model.json")"

{
  echo "# RPCS3 iOS real upstream graph probe"
  echo
  echo "- Requested revision: \`$UPSTREAM_REVISION\`"
  echo "- Resolved commit: \`$(cat "$BUILD/upstream-revision.txt")\`"
  echo "- Qt Designer UI files exported: \`$ui_file_count\`"
  echo "- Complete UI model: \`$BUILD/rpcs3-qt-ui-model.json\`"
  echo "- Configure exit status: \`$configure_status\`"
  echo "- rpcs3_emu build exit status: \`$build_status\`"
  echo "- LLVM is intentionally disabled for this graph stage so the interpreter-based PPU/SPU path can compile before an iOS-safe JIT backend is introduced."
  echo "- Desktop Qt is excluded from the binary, but every upstream .ui document is exported as the UIKit conversion source, including nested menus, tabs, stacked pages, toolboxes, docks, and QAction identifiers."
  echo "- Curl is built from RPCS3's pinned submodule for arm64 iOS instead of locating incompatible host libraries."
  echo "- This probe now compiles the real upstream rpcs3_emu target instead of treating successful CMake generation as completion."
  if [[ $configure_status -ne 0 ]]; then
    echo "- Configure tail:"
    echo
    echo '```text'
    tail -n 100 "$LOG_DIR/configure.log"
    echo '```'
  elif [[ $build_status -ne 0 ]]; then
    echo "- The build tail below is the next concrete runtime porting blocker:"
    echo
    echo '```text'
    tail -n 140 "$LOG_DIR/build-rpcs3-emu.log"
    echo '```'
  fi
} > "$BUILD/summary.md"

cat "$BUILD/summary.md"
exit "$status"
