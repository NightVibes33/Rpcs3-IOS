#!/bin/bash
set -euo pipefail

ROOT="${1:-upstream-rpcs3}"
BUILD="${BUILD:-cmake-ios-build}"
PRODUCT_DIR="${PRODUCT_DIR:-BuildSupport}"
PORT_ROOT="$(pwd)"
TOOLCHAIN="$PORT_ROOT/cmake/toolchains/ios-arm64.cmake"

command -v cmake >/dev/null
command -v xcrun >/dev/null

if [[ ! -d "$ROOT/.git" ]]; then
  git clone --filter=blob:none --depth 1 https://github.com/RPCS3/rpcs3.git "$ROOT"
fi

python3 scripts/apply-upstream-ios-overlay.py "$ROOT"
rm -rf "$BUILD"
mkdir -p "$BUILD/logs" "$PRODUCT_DIR"

UPSTREAM_SHA="$(git -C "$ROOT" rev-parse HEAD)"
SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"

cmake \
  -S "$ROOT" \
  -B "$BUILD/tree" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DCMAKE_BUILD_TYPE=Release \
  -DRPCS3_IOS_CORE_ONLY=ON \
  -DRPCS3_IOS_PORT_ROOT="$PORT_ROOT" \
  >"$BUILD/logs/configure.log" 2>&1

cmake --build "$BUILD/tree" --target rpcs3_ios_core --config Release --parallel 3 \
  >"$BUILD/logs/build.log" 2>&1

ARCHIVE="$(find "$BUILD/tree" -type f -name 'librpcs3-ios-core.a' -print | head -n 1)"
test -n "$ARCHIVE"
test -f "$ARCHIVE"

OUTPUT="$PRODUCT_DIR/librpcs3-ios-core.a"
cp "$ARCHIVE" "$OUTPUT"
file "$OUTPUT" | tee "$BUILD/archive-file.txt"
lipo -info "$OUTPUT" | tee "$BUILD/archive-architectures.txt"
xcrun ar -t "$OUTPUT" | tee "$BUILD/archive-members.txt"
nm -gU "$OUTPUT" | tee "$BUILD/archive-symbols.txt"

grep -q '_rpcs3_ios_core_initialize' "$BUILD/archive-symbols.txt"
grep -q '_rpcs3_ios_core_boot_elf' "$BUILD/archive-symbols.txt"
grep -q '_mbedtls_sha256_ret' "$BUILD/archive-symbols.txt"
grep -q 'probe_ps3_elf' "$BUILD/archive-symbols.txt"
grep -q 'probe_ps3_self' "$BUILD/archive-symbols.txt"
grep -q 'sha256' "$BUILD/archive-members.txt"

cat > "$BUILD/summary.md" <<EOF
# RPCS3 iOS upstream core archive

- Upstream commit: \`$UPSTREAM_SHA\`
- iPhoneOS SDK: \`$SDK_VERSION\`
- Target: \`arm64-apple-ios26.0\`
- Product: \`$OUTPUT\`
- Included upstream unit: \`rpcs3/Crypto/sha256.cpp\`
- Upstream loader types consumed: \`rpcs3/Loader/ELF.h\`
- SELF layout mirrored from upstream: \`SceHeader\`, \`ext_hdr\`, and \`segment_ext_header\` in \`rpcs3/Crypto/unself.h\`
- Device bridge validates sandbox paths, SHA-256, PS3 ELF identity, SELF header ranges, embedded ELF metadata, and segment encryption/compression flags.
- PPU/SPU execution and encrypted SELF key handling remain intentionally disabled.
EOF

tar -czf "$BUILD.tar.gz" "$BUILD"
cat "$BUILD/summary.md"
