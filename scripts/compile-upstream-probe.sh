#!/bin/bash
set -euo pipefail

ROOT="${1:-upstream-rpcs3}"
OUT="${OUT:-compile-probe}"
TOOLCHAIN="${TOOLCHAIN:-$PWD/cmake/toolchains/ios-arm64.cmake}"

rm -rf "$OUT"
mkdir -p "$OUT/logs" "$OUT/objects"

if [[ ! -d "$ROOT/.git" ]]; then
  git clone --filter=blob:none --recurse-submodules --shallow-submodules --depth 1 \
    https://github.com/RPCS3/rpcs3.git "$ROOT"
fi

SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos --find clang)"
CLANGXX="$(xcrun --sdk iphoneos --find clang++)"
TARGET="arm64-apple-ios26.0"
UPSTREAM_SHA="$(git -C "$ROOT" rev-parse HEAD)"

cat > "$OUT/metadata.txt" <<EOF
upstream_sha=$UPSTREAM_SHA
sdkroot=$SDKROOT
clang=$CLANG
target=$TARGET
EOF

cat > "$OUT/probe.cpp" <<'EOF'
#include <TargetConditionals.h>
#include <cstdint>
#include <string>
#include <vector>

#if !TARGET_OS_IPHONE
#error This probe must target physical iOS.
#endif

int rpcs3_ios_toolchain_probe()
{
    std::vector<std::uint32_t> words{0x505055u, 0x535055u};
    return static_cast<int>(words.size());
}
EOF

"$CLANGXX" \
  -target "$TARGET" \
  -isysroot "$SDKROOT" \
  -std=c++20 \
  -fvisibility=hidden \
  -fno-exceptions \
  -fno-rtti \
  -c "$OUT/probe.cpp" \
  -o "$OUT/objects/toolchain-probe.o" \
  >"$OUT/logs/toolchain-probe.log" 2>&1

# Compile selected upstream translation units individually. Failures are retained as
# actionable logs while successful objects prove which pieces already cross-compile.
candidates=(
  "Utilities/StrFmt.cpp"
  "Utilities/File.cpp"
  "Utilities/Thread.cpp"
  "Utilities/Log.cpp"
  "rpcs3/Loader/PSF.cpp"
  "rpcs3/Loader/TROPUSR.cpp"
)

: > "$OUT/results.tsv"
for relative in "${candidates[@]}"; do
  source="$ROOT/$relative"
  name="$(echo "$relative" | tr '/.' '__')"
  log="$OUT/logs/$name.log"
  object="$OUT/objects/$name.o"

  if [[ ! -f "$source" ]]; then
    printf 'missing\t%s\n' "$relative" >> "$OUT/results.tsv"
    continue
  fi

  set +e
  "$CLANGXX" \
    -target "$TARGET" \
    -isysroot "$SDKROOT" \
    -std=c++20 \
    -DRPCS3_IOS=1 \
    -I"$ROOT" \
    -I"$ROOT/Utilities" \
    -I"$ROOT/rpcs3" \
    -I"$ROOT/3rdparty" \
    -c "$source" \
    -o "$object" \
    >"$log" 2>&1
  status=$?
  set -e

  if [[ $status -eq 0 ]]; then
    printf 'pass\t%s\n' "$relative" >> "$OUT/results.tsv"
  else
    printf 'fail\t%s\n' "$relative" >> "$OUT/results.tsv"
  fi
done

python3 - "$OUT" <<'PY'
from pathlib import Path
import sys
out = Path(sys.argv[1])
rows = []
for line in (out / "results.tsv").read_text().splitlines():
    status, path = line.split("\t", 1)
    rows.append((status, path))
passed = sum(s == "pass" for s, _ in rows)
failed = sum(s == "fail" for s, _ in rows)
missing = sum(s == "missing" for s, _ in rows)
summary = [
    "# RPCS3 upstream iOS compile probe",
    "",
    f"- Passed: {passed}",
    f"- Failed: {failed}",
    f"- Missing: {missing}",
    "",
    "| Status | Translation unit |",
    "|---|---|",
]
summary += [f"| {s} | `{p}` |" for s, p in rows]
(out / "summary.md").write_text("\n".join(summary) + "\n")
PY

# The toolchain probe must pass. Upstream source failures are expected and become
# the next concrete patch list.
test -f "$OUT/objects/toolchain-probe.o"
tar -czf "$OUT.tar.gz" "$OUT"
cat "$OUT/summary.md"
