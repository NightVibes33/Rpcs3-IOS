#!/bin/bash
set -euo pipefail

PORT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$PORT_ROOT/scripts/build-unified-qt-ios.sh"
DEDUP="$PORT_ROOT/scripts/patch-upstream-ios-bridge-dedup.py"
QT_PATCH="$PORT_ROOT/scripts/patch-unified-qt-host.py"
TEMP="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/build-unified-qt-ios-final-$$.sh"

trap 'rm -f "$TEMP"' EXIT

test -f "$SOURCE"
test -f "$DEDUP"
test -f "$QT_PATCH"

# Patch the checked-out port sources before CMake reads the external QtApp tree.
python3 "$QT_PATCH"

python3 - "$SOURCE" "$TEMP" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
text = source.read_text(encoding="utf-8")
needle = 'run_logged emu-graph python3 "$PORT_ROOT/scripts/patch-upstream-ios-emu-graph.py" "$ROOT"\n'
replacement = needle + 'run_logged bridge-dedup python3 "$PORT_ROOT/scripts/patch-upstream-ios-bridge-dedup.py" "$ROOT"\n'
if needle not in text:
    raise SystemExit("Unable to locate unified graph patch phase")
destination.write_text(text.replace(needle, replacement, 1), encoding="utf-8")
PY

bash "$TEMP"
