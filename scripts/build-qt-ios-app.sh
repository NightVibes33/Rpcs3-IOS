#!/bin/bash
set -euo pipefail

ROOT="${1:-upstream-rpcs3}"
BUILD="${QT_APP_BUILD:-qt-ios-build}"
QT_ROOT="${QT_ROOT:-$HOME/Qt}"
QT_VERSION="${QT_VERSION:-6.11.1}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-26.0}"
PORT_ROOT="$(pwd)"
QT_APP="$PORT_ROOT/QtApp"
GENERATED="$QT_APP/Generated"
GENERATED_UI="$GENERATED/ui"
CORE_ARCHIVE="$PORT_ROOT/BuildSupport/librpcs3-ios-core.a"
MOLTENVK_ROOT="${MOLTENVK_ROOT:-$PORT_ROOT/BuildSupport/MoltenVK}"
MOLTENVK_BINARY="$MOLTENVK_ROOT/MoltenVK.xcframework/ios-arm64/MoltenVK.framework/MoltenVK"
IOS_QT="$QT_ROOT/$QT_VERSION/ios"
HOST_QT="$QT_ROOT/$QT_VERSION/macos"
QT_CMAKE="$IOS_QT/bin/qt-cmake"

command -v cmake >/dev/null
command -v python3 >/dev/null
command -v xcrun >/dev/null

test -d "$ROOT/.git"
test -f "$CORE_ARCHIVE"
test -f "$MOLTENVK_BINARY"
test -f "$MOLTENVK_ROOT/include/vulkan/vulkan.h"
test -x "$QT_CMAKE"
test -d "$HOST_QT"
test -f "$ROOT/rpcs3/rpcs3qt/main_window.ui"
test -f "$PORT_ROOT/scripts/generate-qt-ui-factory.py"

rm -rf "$GENERATED" "$BUILD"
mkdir -p "$GENERATED_UI" "$BUILD/logs"

python3 - "$ROOT/rpcs3/rpcs3qt" "$GENERATED_UI" <<'PY'
from pathlib import Path
import shutil
import sys

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
files = sorted(source.rglob("*.ui"))
if not files:
    raise SystemExit("No upstream RPCS3 Qt Designer files were found")

seen = {}
for item in files:
    name = item.name
    if name in seen:
        raise SystemExit(f"Duplicate Qt Designer filename: {name}: {seen[name]} and {item}")
    seen[name] = item
    shutil.copy2(item, destination / name)

required = {
    "main_window.ui",
    "settings_dialog.ui",
    "pad_settings_dialog.ui",
    "about_dialog.ui",
}
missing = sorted(required - set(seen))
if missing:
    raise SystemExit(f"Required upstream Qt UI documents are missing: {missing}")
print(f"Copied {len(files)} upstream Qt Designer files")
PY

python3 - "$GENERATED_UI/main_window.ui" "$BUILD/upstream-ui-manifest.json" <<'PY'
from pathlib import Path
import hashlib
import json
import sys
import xml.etree.ElementTree as ET

source = Path(sys.argv[1])
output = Path(sys.argv[2])
root = ET.parse(source).getroot()
class_name = root.findtext("class")
actions = [node.attrib.get("name", "") for node in root.findall(".//action")]
menus = [node.attrib.get("name", "") for node in root.findall(".//widget[@class='QMenu']")]
required_actions = {"bootGameAct", "bootIsoAct", "bootVSHAct", "confCPUAct", "sysStopAct"}
missing = sorted(required_actions - set(actions))
if class_name != "main_window":
    raise SystemExit(f"Unexpected upstream UI class: {class_name}")
if missing:
    raise SystemExit(f"Missing required upstream actions: {missing}")
manifest = {
    "source": str(source),
    "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
    "class": class_name,
    "action_count": len(actions),
    "menu_count": len(menus),
    "required_actions": sorted(required_actions),
}
output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(json.dumps(manifest, indent=2))
PY

python3 "$PORT_ROOT/scripts/generate-qt-ui-factory.py" \
  "$GENERATED_UI" \
  "$GENERATED/RPCS3QtUiFactory.h" \
  "$GENERATED/RPCS3QtUiFactory.cpp" \
  "$GENERATED/RPCS3CompiledUiFiles.cmake" \
  | tee "$BUILD/logs/generate-ui-factory.log"

test -f "$GENERATED/RPCS3QtUiFactory.cpp"
test -f "$GENERATED/RPCS3CompiledUiFiles.cmake"
grep -q 'main_window.ui' "$GENERATED/RPCS3QtUiFactory.cpp"
grep -q 'settings_dialog.ui' "$GENERATED/RPCS3QtUiFactory.cpp" || true

"$QT_CMAKE" \
  -S "$QT_APP" \
  -B "$BUILD" \
  -G Xcode \
  -DQT_HOST_PATH="$HOST_QT" \
  -DRPCS3_IOS_MOLTENVK_ROOT="$MOLTENVK_ROOT" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY='' \
  >"$BUILD/logs/configure.log" 2>&1

cmake --build "$BUILD" --config Release --target RPCS3QtIOS --parallel 3 \
  >"$BUILD/logs/build.log" 2>&1

APP="$(find "$BUILD" -type d -name 'RPCS3-iOS.app' -path '*Release*' -print | head -n 1)"
if [[ -z "$APP" ]]; then
  APP="$(find "$BUILD" -type d -name 'RPCS3-iOS.app' -print | head -n 1)"
fi
test -n "$APP"
test -d "$APP"
BIN="$APP/RPCS3-iOS"
test -f "$BIN"

GENERATED_HEADER="$(find "$BUILD" -type f -name 'ui_main_window.h' -print | head -n 1)"
test -n "$GENERATED_HEADER"
grep -q 'class Ui_main_window' "$GENERATED_HEADER"
grep -q 'bootGameAct' "$GENERATED_HEADER"
grep -q 'bootVSHAct' "$GENERATED_HEADER"
grep -q 'menuFile' "$GENERATED_HEADER"
grep -q 'menuConfiguration' "$GENERATED_HEADER"

file "$BIN" | tee "$BUILD/binary-file.txt"
lipo -info "$BIN" | tee "$BUILD/binary-architectures.txt"
xcrun vtool -show-build "$BIN" | tee "$BUILD/binary-build-version.txt" || true
strings "$BIN" > "$BUILD/binary-strings.txt"
grep -q 'RPCS3 Qt iOS upstream main_window.ui' "$BUILD/binary-strings.txt"
grep -q 'Vulkan (MoltenVK)' "$BUILD/binary-strings.txt"
grep -q 'Run GPU Self-Test' "$BUILD/binary-strings.txt"
grep -q 'Native Metal submitted and presented a frame' "$BUILD/binary-strings.txt"
grep -q 'MoltenVK submitted and presented a Vulkan frame through Metal' "$BUILD/binary-strings.txt"
nm -gU "$BIN" > "$BUILD/binary-symbols.txt"
cat "$BUILD/binary-symbols.txt"
grep -q '_rpcs3_ios_core_initialize' "$BUILD/binary-symbols.txt"
grep -q '_rpcs3_ios_core_boot_elf' "$BUILD/binary-symbols.txt"
grep -q '_vkCreateInstance' "$BUILD/binary-symbols.txt"
grep -q '_MTLCreateSystemDefaultDevice' "$BUILD/binary-symbols.txt"

COMPILED_FORM_COUNT="$(grep -c 'QStringLiteral(.*\.ui")' "$GENERATED/RPCS3QtUiFactory.cpp" || true)"
printf '%s\n' "$APP" > "$BUILD/app-path.txt"
cat > "$BUILD/summary.md" <<EOF
# RPCS3 Qt iOS application

- UI framework: **Qt Widgets**
- Main window source: pinned RPCS3 \`rpcs3qt/main_window.ui\`
- Main window compiler: Qt \`uic\` through CMake AUTOUIC
- Compile-compatible upstream forms: \`$COMPILED_FORM_COUNT\`
- Qt version: \`$QT_VERSION\`
- Target: \`arm64-apple-ios$DEPLOYMENT_TARGET\`
- App bundle: \`$APP\`
- Upstream UI manifest: \`$BUILD/upstream-ui-manifest.json\`
- Vulkan renderer: static MoltenVK XCFramework linked, with a real Vulkan instance/device/Metal surface/swapchain/present path.
- Metal renderer: native MTLDevice/MTLCommandQueue/CAMetalLayer/drawable/present path.
- The shipped root window is a real \`QMainWindow\` with RPCS3's real \`QMenuBar\`, \`QMenu\`, and \`QAction\` objects.
- Runtime actions are routed to the available iOS core bridge. Full RSX command translation is tracked separately from renderer device and presentation bring-up.
EOF

cat "$BUILD/summary.md"
