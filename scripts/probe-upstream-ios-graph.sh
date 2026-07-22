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
FFMPEG_ROOT="${RPCS3_IOS_FFMPEG_ROOT:-$PORT_ROOT/BuildSupport/ffmpeg-ios}"
export RPCS3_IOS_FFMPEG_ROOT="$FFMPEG_ROOT"
export FFMPEG_IOS_ROOT="$FFMPEG_ROOT"

UPSTREAM_REVISION="$(tr -d '[:space:]' < "$REVISION_FILE")"
test -n "$UPSTREAM_REVISION"
test -f "$TIMEOUT_RUNNER"
test -f "$PHASE1_COLLECTOR"
test -f "$PORT_ROOT/scripts/build-ffmpeg-ios.sh"

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

phase "Build pinned FFmpeg 7.1 static libraries for arm64 iOS"
run_timed 3600 bash scripts/build-ffmpeg-ios.sh

test -f "$FFMPEG_ROOT/.rpcs3-ios-ffmpeg-n7.1"
test -f "$FFMPEG_ROOT/include/libavutil/pixfmt.h"
test -f "$FFMPEG_ROOT/lib/libavcodec.a"
test -f "$FFMPEG_ROOT/lib/libavformat.a"
test -f "$FFMPEG_ROOT/lib/libavutil.a"
test -f "$FFMPEG_ROOT/lib/libswscale.a"
test -f "$FFMPEG_ROOT/lib/libswresample.a"

phase "Apply iOS upstream-graph overlays"
run_timed 120 python3 scripts/apply-upstream-ios-overlay.py "$ROOT" --mode upstream
run_timed 120 python3 scripts/patch-upstream-ios-libusb-api.py "$ROOT"
run_timed 120 python3 scripts/patch-upstream-ios-cubeb.py "$ROOT"
run_timed 180 python3 scripts/patch-upstream-ios-emu-graph.py "$ROOT"

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
  -DRPCS3_IOS_FFMPEG_ROOT="$FFMPEG_ROOT" \
  -DWITH_LLVM=OFF \
  -DBUILD_LLVM=OFF \
  -DBUILD_LLVM_SUBMODULE=OFF \
  -DUSE_VULKAN=OFF \
  -DUSE_OPENGL=OFF \
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

bridge_status=125
if [[ $configure_status -eq 0 && $build_status -eq 0 ]]; then
  phase "Compile the non-Qt upstream Emu.Init bridge target"
  set +e
  python3 "$TIMEOUT_RUNNER" 1800 cmake --build "$BUILD/tree" \
    --target rpcs3_ios_upstream_bridge \
    --config Release \
    --parallel 3 \
    2>&1 | tee "$LOG_DIR/build-upstream-runtime-bridge.log"
  bridge_status=${PIPESTATUS[0]}
  set -e
  phase "rpcs3_ios_upstream_bridge build exit status=$bridge_status"
else
  phase "Skipping upstream runtime bridge because rpcs3_emu did not compile"
fi

link_probe_status=125
probe_binary=""
probe_symbol_present=false
if [[ $configure_status -eq 0 && $build_status -eq 0 && $bridge_status -eq 0 ]]; then
  phase "Link the arm64 iOS executable that calls the real Emu.Init bridge"
  set +e
  python3 "$TIMEOUT_RUNNER" 3600 cmake --build "$BUILD/tree" \
    --target rpcs3_ios_runtime_link_probe \
    --config Release \
    --parallel 3 \
    2>&1 | tee "$LOG_DIR/build-runtime-link-probe.log"
  link_probe_status=${PIPESTATUS[0]}
  set -e
  phase "rpcs3_ios_runtime_link_probe build exit status=$link_probe_status"

  if [[ $link_probe_status -eq 0 ]]; then
    probe_binary="$(find "$BUILD/tree" -type f -name 'rpcs3-ios-runtime-link-probe' -print | head -n 1)"
    if [[ -z "$probe_binary" || ! -f "$probe_binary" ]]; then
      phase "Runtime link target reported success but produced no probe executable"
      link_probe_status=126
    else
      file "$probe_binary" | tee "$BUILD/runtime-link-probe-file.txt"
      lipo -info "$probe_binary" | tee "$BUILD/runtime-link-probe-architectures.txt"
      nm -gU "$probe_binary" > "$BUILD/runtime-link-probe-symbols.txt"
      if grep -q '_rpcs3_ios_upstream_runtime_link_probe' "$BUILD/runtime-link-probe-symbols.txt"; then
        probe_symbol_present=true
      else
        phase "Runtime link probe is missing the exported bridge symbol"
        link_probe_status=127
      fi
    fi
  fi
else
  phase "Skipping runtime link probe because its upstream target or bridge failed"
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
if [[ $status -eq 0 ]]; then status=$build_status; fi
if [[ $status -eq 0 ]]; then status=$bridge_status; fi
if [[ $status -eq 0 ]]; then status=$link_probe_status; fi
if [[ $status -eq 0 && $phase1_status -ne 0 ]]; then status=$phase1_status; fi

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
  echo "- FFmpeg target: \`arm64-apple-ios${DEPLOYMENT_TARGET:-26.0}\`"
  echo "- FFmpeg install: \`$FFMPEG_ROOT\`"
  echo "- Renderer lane: \`Null RSX (Vulkan/OpenGL disabled for interpreter execution proof)\`"
  echo "- Configure exit status: \`$configure_status\`"
  echo "- rpcs3_emu build exit status: \`$build_status\`"
  echo "- Upstream runtime bridge build exit status: \`$bridge_status\`"
  echo "- Emu.Init runtime link probe exit status: \`$link_probe_status\`"
  echo "- Runtime link probe binary: \`${probe_binary:-not-produced}\`"
  echo "- Runtime bridge symbol present in linked executable: \`$probe_symbol_present\`"
  echo "- Phase 1 evidence exit status: \`$phase1_status\`"
  echo "- Upstream Emu/System.cpp configured: \`$system_cpp_configured\`"
  echo "- Upstream Emu/System.cpp object built: \`$system_cpp_object_built\`"
  echo "- Configured upstream Emu source files: \`$configured_emu_source_count\`"
  echo "- Phase 1 evidence: \`$BUILD/phase1-emusystem-evidence.json\`"
  echo "- LLVM is intentionally disabled so interpreter-based PPU/SPU paths compile before entitlement-dependent JIT work."
  echo "- The desktop executable is excluded from this core graph; the shipped host is the separate Qt Widgets iOS application generated from RPCS3's upstream Qt UI."
  echo "- Pinned FFmpeg is built as real arm64-iOS static libraries and linked into the upstream graph."
  echo "- Vulkan and OpenGL are intentionally disabled in this phase; rendering is added after interpreter guest execution is proven."
  echo "- Success now requires a fully linked arm64 iOS executable that calls the real non-Qt Emu.Init bridge; configuring an unused bridge target is not accepted."
  echo "- The probe executable is cross-linked only. Physical-device execution evidence is still required before the project is classified as execution-capable."
  if [[ $configure_status -ne 0 ]]; then
    echo "- Configure tail:"
    echo
    echo '```text'
    tail -n 100 "$LOG_DIR/configure.log"
    echo '```'
  elif [[ $build_status -ne 0 ]]; then
    echo "- The rpcs3_emu build tail below is the next concrete runtime porting blocker:"
    echo
    echo '```text'
    tail -n 140 "$LOG_DIR/build-rpcs3-emu.log"
    echo '```'
  elif [[ $bridge_status -ne 0 ]]; then
    echo "- The bridge compile tail below is the next concrete Phase 1 blocker:"
    echo
    echo '```text'
    tail -n 140 "$LOG_DIR/build-upstream-runtime-bridge.log"
    echo '```'
  elif [[ $link_probe_status -ne 0 ]]; then
    echo "- The full Emu.Init link tail below is the next concrete Phase 1 blocker:"
    echo
    echo '```text'
    tail -n 180 "$LOG_DIR/build-runtime-link-probe.log"
    echo '```'
  elif [[ $phase1_status -ne 0 ]]; then
    echo "- The targets compiled and linked, but Phase 1 source evidence validation failed:"
    echo
    echo '```text'
    tail -n 100 "$LOG_DIR/phase1-emusystem-evidence.log"
    echo '```'
  fi
} > "$BUILD/summary.md"

cat "$BUILD/summary.md"
exit "$status"
