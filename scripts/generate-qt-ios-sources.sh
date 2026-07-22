#!/bin/bash
set -euo pipefail

ROOT="${1:-upstream-rpcs3}"
PORT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
QT_APP="$PORT_ROOT/QtApp"
GENERATED="$QT_APP/Generated"
GENERATED_UI="$GENERATED/ui"
MANIFEST_OUTPUT="${2:-$PORT_ROOT/qt-ios-generated-manifest.json}"

command -v python3 >/dev/null
test -d "$ROOT/.git"
test -f "$ROOT/rpcs3/rpcs3qt/main_window.ui"
test -f "$PORT_ROOT/scripts/generate-qt-ui-factory.py"

rm -rf "$GENERATED"
mkdir -p "$GENERATED_UI" "$(dirname "$MANIFEST_OUTPUT")"

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

required = {"main_window.ui", "settings_dialog.ui", "pad_settings_dialog.ui", "about_dialog.ui"}
missing = sorted(required - set(seen))
if missing:
    raise SystemExit(f"Required upstream Qt UI documents are missing: {missing}")
print(f"Copied {len(files)} upstream Qt Designer files")
PY

python3 - "$GENERATED_UI/main_window.ui" "$MANIFEST_OUTPUT" <<'PY'
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
  "$GENERATED/RPCS3CompiledUiFiles.cmake"

test -f "$GENERATED/RPCS3QtUiFactory.cpp"
test -f "$GENERATED/RPCS3CompiledUiFiles.cmake"
grep -q 'main_window.ui' "$GENERATED/RPCS3QtUiFactory.cpp"
grep -q '<class>main_window</class>' "$GENERATED_UI/main_window.ui"

echo "Generated RPCS3 Qt iOS sources at $GENERATED"
