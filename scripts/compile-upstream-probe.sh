#!/bin/bash
set -euo pipefail

ROOT="${1:-upstream-rpcs3}"
OUT="${OUT:-compile-probe}"
MANIFEST="${MANIFEST:-Port/portable-sources.txt}"

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
manifest=$MANIFEST
EOF

COMMON=(
  -target "$TARGET"
  -isysroot "$SDKROOT"
  -std=c++20
  -DRPCS3_IOS=1
  -DRPCS3_PLATFORM_MOBILE=1
  -DRPCS3_PLATFORM_DESKTOP=0
  -include "$PWD/Port/IOSPlatform.h"
  -I"$PWD/Port"
  -I"$ROOT"
  -I"$ROOT/Utilities"
  -I"$ROOT/rpcs3"
  -I"$ROOT/3rdparty"
)

cat > "$OUT/probe.cpp" <<'EOF'
#include "IOSPlatform.h"
#include <cstdint>
#include <vector>

int rpcs3_ios_toolchain_probe()
{
    std::vector<std::uint32_t> words{0x505055u, 0x535055u};
    return static_cast<int>(words.size());
}
EOF

"$CLANGXX" "${COMMON[@]}" -c "$OUT/probe.cpp" \
  -o "$OUT/objects/toolchain-probe.o" \
  >"$OUT/logs/toolchain-probe.log" 2>&1

"$CLANGXX" "${COMMON[@]}" -fobjc-arc -c Port/IOSPlatform.mm \
  -o "$OUT/objects/ios-platform.o" \
  >"$OUT/logs/ios-platform.log" 2>&1

mapfile_compat() {
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    printf '%s\0' "$line"
  done < "$MANIFEST"
}

: > "$OUT/results.tsv"
while IFS= read -r -d '' relative; do
  source="$ROOT/$relative"
  name="$(echo "$relative" | tr '/.' '__')"
  log="$OUT/logs/$name.log"
  object="$OUT/objects/$name.o"

  if [[ ! -f "$source" ]]; then
    printf 'missing\t%s\n' "$relative" >> "$OUT/results.tsv"
    continue
  fi

  set +e
  "$CLANGXX" "${COMMON[@]}" -c "$source" -o "$object" >"$log" 2>&1
  status=$?
  set -e

  if [[ $status -eq 0 ]]; then
    printf 'pass\t%s\n' "$relative" >> "$OUT/results.tsv"
  else
    printf 'fail\t%s\n' "$relative" >> "$OUT/results.tsv"
  fi
done < <(mapfile_compat)

python3 - "$OUT" <<'PY'
from pathlib import Path
import re
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
    "- Platform adapter: compiled",
    "",
    "| Status | Translation unit | First diagnostic |",
    "|---|---|---|",
]
for status, path in rows:
    log = out / "logs" / path.replace('/', '__').replace('.', '__')
    log = log.with_suffix('.log')
    diagnostic = ""
    if log.exists():
        for text in log.read_text(errors="replace").splitlines():
            if " error:" in text or "fatal error:" in text:
                diagnostic = re.sub(r"\|", "\\|", text.strip())[:180]
                break
    summary.append(f"| {status} | `{path}` | {diagnostic} |")
(out / "summary.md").write_text("\n".join(summary) + "\n")
PY

test -f "$OUT/objects/toolchain-probe.o"
test -f "$OUT/objects/ios-platform.o"
tar -czf "$OUT.tar.gz" "$OUT"
cat "$OUT/summary.md"
