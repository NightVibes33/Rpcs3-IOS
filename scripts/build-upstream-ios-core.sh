#!/bin/bash
set -euo pipefail

ROOT="${1:-upstream-rpcs3}"
BUILD="${BUILD:-cmake-ios-build}"
PRODUCT_DIR="${PRODUCT_DIR:-BuildSupport}"
PORT_ROOT="$(pwd)"
TOOLCHAIN="$PORT_ROOT/cmake/toolchains/ios-arm64.cmake"
REVISION_FILE="$PORT_ROOT/UPSTREAM_RPCS3_REVISION"
UI_MODEL="$PORT_ROOT/App/Generated/RPCS3QtUIModel.json"

command -v cmake >/dev/null
command -v xcrun >/dev/null
command -v git >/dev/null

test -f "$REVISION_FILE"
UPSTREAM_REVISION="$(tr -d '[:space:]' < "$REVISION_FILE")"
test -n "$UPSTREAM_REVISION"

if [[ ! -d "$ROOT/.git" ]]; then
  git clone --filter=blob:none --no-checkout https://github.com/RPCS3/rpcs3.git "$ROOT"
fi

git -C "$ROOT" fetch --depth 1 origin "refs/tags/$UPSTREAM_REVISION:refs/tags/$UPSTREAM_REVISION"
git -C "$ROOT" checkout --detach --force "$UPSTREAM_REVISION"
git -C "$ROOT" submodule sync --recursive
git -C "$ROOT" submodule update --init --recursive --depth 1

python3 scripts/apply-upstream-ios-overlay.py "$ROOT" --mode bootstrap
rm -rf "$BUILD"
mkdir -p "$BUILD/logs" "$PRODUCT_DIR" "$(dirname "$UI_MODEL")"

# Export the real Qt Designer hierarchy before XcodeGen runs. Because this file
# lives under App/, XcodeGen copies it into the IPA as a resource consumed by
# the UIKit menu/tab renderer. It includes nested layouts, tab pages, stacked
# pages, docks, controls, QAction identifiers, labels, states, and shortcuts
# from the pinned RPCS3 tag.
python3 scripts/export-upstream-qt-ui-model.py "$ROOT" "$UI_MODEL" \
  >"$BUILD/logs/export-qt-ui-model.log" 2>&1
cp "$UI_MODEL" "$BUILD/rpcs3-qt-ui-model.json"

UPSTREAM_SHA="$(git -C "$ROOT" rev-parse HEAD)"
SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
printf '%s\n' "$UPSTREAM_SHA" > "$BUILD/upstream-revision.txt"
git -C "$ROOT" submodule status --recursive > "$BUILD/upstream-submodules.txt"

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
grep -q 'build_plain_self_load_plan' "$BUILD/archive-symbols.txt"
grep -q 'extract_plain_self_to_elf' "$BUILD/archive-symbols.txt"
grep -q 'sha256' "$BUILD/archive-members.txt"
python3 - "$UI_MODEL" <<'PY'
import json, sys
model = json.load(open(sys.argv[1], encoding="utf-8"))
assert model["schema"] >= 3
assert model["ui_file_count"] > 0
assert model["widget_count"] > 0
assert model["action_count"] > 0
main = next(d for d in model["documents"] if d["file"] == "main_window.ui")
settings = next(d for d in model["documents"] if d["file"] == "settings_dialog.ui")
actions = {item["name"]: item for item in main["actions"]}
assert actions["bootGameAct"]["title"]
assert actions["confCPUAct"]["title"]
assert actions["sysStopAct"]["title"]
assert settings["root"]
PY

UI_ACTION_COUNT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["action_count"])' "$UI_MODEL")"
cat > "$BUILD/summary.md" <<EOF
# RPCS3 iOS pinned upstream core archive

- Requested upstream revision: \`$UPSTREAM_REVISION\`
- Resolved upstream commit: \`$UPSTREAM_SHA\`
- iPhoneOS SDK: \`$SDK_VERSION\`
- Target: \`arm64-apple-ios26.0\`
- Product: \`$OUTPUT\`
- Bundled Qt UI model: \`$UI_MODEL\`
- Exported QAction definitions: \`$UI_ACTION_COUNT\`
- Checkout includes initialized upstream submodules.
- The bootstrap archive remains the shipping lane while the separate upstream-graph probe identifies blockers in RPCS3's real build graph.
EOF

tar -czf "$BUILD.tar.gz" "$BUILD"
cat "$BUILD/summary.md"
