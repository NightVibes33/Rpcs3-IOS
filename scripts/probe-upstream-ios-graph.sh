#!/bin/bash
set -euo pipefail

ROOT="${1:-upstream-rpcs3-graph}"
BUILD="${BUILD:-cmake-ios-upstream-graph}"
PORT_ROOT="$(pwd)"
TOOLCHAIN="$PORT_ROOT/cmake/toolchains/ios-arm64.cmake"
REVISION_FILE="$PORT_ROOT/UPSTREAM_RPCS3_REVISION"
LOG_DIR="$BUILD/logs"

UPSTREAM_REVISION="$(tr -d '[:space:]' < "$REVISION_FILE")"
test -n "$UPSTREAM_REVISION"

rm -rf "$ROOT" "$BUILD"
git clone --filter=blob:none --no-checkout https://github.com/RPCS3/rpcs3.git "$ROOT"
git -C "$ROOT" fetch --depth 1 origin "refs/tags/$UPSTREAM_REVISION:refs/tags/$UPSTREAM_REVISION"
git -C "$ROOT" checkout --detach --force "$UPSTREAM_REVISION"
git -C "$ROOT" submodule sync --recursive
git -C "$ROOT" submodule update --init --recursive --depth 1

python3 scripts/apply-upstream-ios-overlay.py "$ROOT" --mode upstream
mkdir -p "$LOG_DIR"

git -C "$ROOT" rev-parse HEAD | tee "$BUILD/upstream-revision.txt"
git -C "$ROOT" submodule status --recursive > "$BUILD/upstream-submodules.txt"

set +e
cmake \
  -S "$ROOT" \
  -B "$BUILD/tree" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DCMAKE_BUILD_TYPE=Release \
  -DRPCS3_IOS_UPSTREAM_GRAPH=ON \
  -DRPCS3_IOS_PORT_ROOT="$PORT_ROOT" \
  -DBUILD_LLVM_SUBMODULE=OFF \
  -DUSE_FAUDIO=OFF \
  -DUSE_PRECOMPILED_HEADERS=OFF \
  2>&1 | tee "$LOG_DIR/configure.log"
status=${PIPESTATUS[0]}
set -e

{
  echo "# RPCS3 iOS real upstream graph probe"
  echo
  echo "- Requested revision: \`$UPSTREAM_REVISION\`"
  echo "- Resolved commit: \`$(cat "$BUILD/upstream-revision.txt")\`"
  echo "- Configure exit status: \`$status\`"
  echo "- This probe intentionally enters RPCS3's real dependency/emulator graph without the bootstrap early return."
  if [[ $status -ne 0 ]]; then
    echo "- The tail below is the next concrete porting blocker:"
    echo
    echo '```text'
    tail -n 80 "$LOG_DIR/configure.log"
    echo '```'
  fi
} > "$BUILD/summary.md"

cat "$BUILD/summary.md"
exit "$status"
