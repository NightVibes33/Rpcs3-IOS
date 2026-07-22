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
PHASE1_COLLECTOR="$PORT_ROOT/scripts/collect-emusystem-phase1-evidence.py"

UPSTREAM_REVISION="$(tr -d '[:space:]' < "$REVISION_FILE")"
test -n "$UPSTREAM_REVISION"
test -f "$TIMEOUT_RUNNER"
test -f "$PHASE1_COLLECTOR"

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
run_timed 120 python3 scripts/patch-upstream-ios-libusb-api.py "$ROOT"
run_timed 120 python3 scripts/patch-upstream-ios-cubeb.py "$ROOT"
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
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
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

phase1_status=125
if [[ $configure_status -eq 0 ]]; then
  phase "Collect Phase 1 Emu.System evidence"
  set +e
  python3 "$PHASE1_COLLECTOR" \
    --compile-commands "$BUILD/tree/compile_commands.json" \
    --build-root "$BUILD/tree" \
    --build-status "$build_status" \
    --output "$BUILD/phase1-emusystem-evidence.json" \
    2>&1 | tee "$LOG_DIR/phase1-emusystem-evidence.log"
  phase1_status=${PIPESTATUS[0]}
  set -e
  phase "Phase 1 evidence exit status=$phase1_status"
fi

status=$configure_status
if [[ $configure_status -eq 0 ]]; then
  status=$build_status
  if [[ $phase1_status -ne 0 && $status -eq 0 ]]; then
    status=$phase1_status
  fi
fi

ui_file_count="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["ui_file_count"])' "$BUILD/rpcs3-qt-ui-model.json")"
widget_count="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("widget_count", 0))' "$BUILD/rpcs3-qt-ui-model.json")"
system_cpp_configured="unknown"
system_cpp_object_built="unknown"
configured_emu_source_count="unknown"
if [[ -f "$BUILD/phase1-emusystem-evidence.json" ]]; then
  system_cpp_configured="$(python3 -c 'import json,sys; print(str(json.load(open(sys.argv[1]))["system_cpp_configured"]).lower())' "$BUILD/phase1-emusystem-evidence.json")"
  system_cpp_object_built="$(python3 -c 'import json,sys; print(str(json.load(open(sys.argv[1]))["system_cpp_object_built"]).lower())' "$BUILD/phase1-emusystem-evidence.json")"
  configured_emu_source_count="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["configured_emu_source_count"])' "$BUILD/phase1-emusystem-evidence.json")"
fi

{
  echo "# RPCS3 iOS real upstream graph probe"
  echo
  echo "- Requested revision: \`$UPSTREAM_REVISION\`"
  echo "- Resolved commit: \`$(cat "$BUILD/upstream-revision.txt")\`"
  echo "- Qt Designer UI files exported: \`$ui_file_count\`"
  echo "- Nested Qt widgets exported: \`$widget_count\`"
  echo "- Complete UI model: \`$BUILD/rpcs3-qt-ui-model.json\`"
  echo "- Configure exit status: \`$configure_status\`"
  echo "- rpcs3_emu build exit status: \`$build_status\`"
  echo "- Phase 1 evidence exit status: \`$phase1_status\`"
  echo "- Upstream Emu/System.cpp configured: \`$system_cpp_configured\`"
  echo "- Upstream Emu/System.cpp object built: \`$system_cpp_object_built\`"
  echo "- Configured upstream Emu source files: \`$configured_emu_source_count\`"
  echo "- Phase 1 evidence: \`$BUILD/phase1-emusystem-evidence.json\`"
  echo "- LLVM is intentionally disabled so interpreter-based PPU/SPU paths compile before any entitlement-dependent JIT work."
  echo "- Desktop Qt is excluded from the binary while upstream Qt UI documents remain the source for UIKit conversion."
  echo "- This probe compiles the real upstream rpcs3_emu target and separately proves whether System.cpp entered the build."
  echo "- Compilation is not treated as physical-device Emu.System initialization or guest execution."
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
  elif [[ $phase1_status -ne 0 ]]; then
    echo "- The target compiled, but Phase 1 source evidence validation failed:"
    echo
    echo '```text'
    tail -n 100 "$LOG_DIR/phase1-emusystem-evidence.log"
    echo '```'
  fi
} > "$BUILD/summary.md"

cat "$BUILD/summary.md"
exit "$status"
