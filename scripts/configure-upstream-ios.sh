#!/bin/bash
set -euo pipefail

ROOT="${1:-upstream-rpcs3}"
BUILD="${BUILD:-cmake-ios-build}"
PORT_ROOT="$(pwd)"
TOOLCHAIN="$PORT_ROOT/cmake/toolchains/ios-arm64.cmake"

if [[ ! -d "$ROOT/.git" ]]; then
  git clone --filter=blob:none --recurse-submodules --shallow-submodules --depth 1 \
    https://github.com/RPCS3/rpcs3.git "$ROOT"
fi

python3 scripts/apply-upstream-ios-overlay.py "$ROOT"
rm -rf "$BUILD"
mkdir -p "$BUILD/logs"

UPSTREAM_SHA="$(git -C "$ROOT" rev-parse HEAD)"
SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"

set +e
cmake \
  -S "$ROOT" \
  -B "$BUILD/tree" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DCMAKE_BUILD_TYPE=Release \
  -DRPCS3_IOS_CORE_ONLY=ON \
  -DRPCS3_IOS_PORT_ROOT="$PORT_ROOT" \
  >"$BUILD/logs/configure.log" 2>&1
configure_status=$?
set -e

if [[ $configure_status -ne 0 ]]; then
  cat "$BUILD/logs/configure.log"
  exit "$configure_status"
fi

set +e
cmake --build "$BUILD/tree" --target rpcs3_ios_core --config Release --parallel 3 \
  >"$BUILD/logs/build.log" 2>&1
build_status=$?
set -e

if [[ $build_status -ne 0 ]]; then
  cat "$BUILD/logs/build.log"
  exit "$build_status"
fi

ARCHIVE="$(find "$BUILD/tree" -type f -name 'librpcs3-ios-core.a' -print | head -n 1)"
test -n "$ARCHIVE"
test -f "$ARCHIVE"

cp "$ARCHIVE" "$BUILD/librpcs3-ios-core.a"
file "$BUILD/librpcs3-ios-core.a" | tee "$BUILD/archive-file.txt"
lipo -info "$BUILD/librpcs3-ios-core.a" | tee "$BUILD/archive-architectures.txt"
xcrun ar -t "$BUILD/librpcs3-ios-core.a" | tee "$BUILD/archive-members.txt"
nm -gU "$BUILD/librpcs3-ios-core.a" | tee "$BUILD/archive-symbols.txt"
grep -q '_rpcs3_ios_core_initialize' "$BUILD/archive-symbols.txt"
grep -q '_rpcs3_ios_core_boot_elf' "$BUILD/archive-symbols.txt"

cat > "$BUILD/summary.md" <<EOF
# RPCS3 iOS upstream CMake core build

- Upstream commit: \`$UPSTREAM_SHA\`
- iPhoneOS SDK: \`$SDK_VERSION\`
- Target: \`arm64-apple-ios26.0\`
- Product: \`librpcs3-ios-core.a\`
- Upstream top-level build entered through the reproducible core-only overlay.
- The archive currently contains the iOS platform, filesystem, and replaceable core bridge. Portable upstream translation units are promoted into this target only after the compile probe passes them.
EOF

tar -czf "$BUILD.tar.gz" "$BUILD"
cat "$BUILD/summary.md"
