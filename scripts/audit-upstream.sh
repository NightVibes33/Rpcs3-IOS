#!/bin/bash
set -euo pipefail

ROOT="${1:-upstream-rpcs3}"
REPORT_DIR="${REPORT_DIR:-portability-report}"
mkdir -p "$REPORT_DIR"

if [[ ! -d "$ROOT/.git" ]]; then
  git clone --filter=blob:none --recurse-submodules --shallow-submodules --depth 1 \
    https://github.com/RPCS3/rpcs3.git "$ROOT"
fi

pushd "$ROOT" >/dev/null
UPSTREAM_SHA="$(git rev-parse HEAD)"
popd >/dev/null

{
  echo "RPCS3 iOS portability audit"
  echo "Upstream commit: $UPSTREAM_SHA"
  echo "Generated: $(date -u +%FT%TZ)"
  echo
  echo "Desktop/platform references"
  grep -RInE --exclude-dir=.git --exclude='*.ts' \
    'QApplication|QMainWindow|QWidget|fork\(|execve\(|dlopen\(|pthread_jit_write_protect_np|MAP_JIT|VK_KHR_(xlib|win32|wayland|xcb)_surface|NSWindow|AppKit' \
    "$ROOT/rpcs3" "$ROOT/Utilities" 2>/dev/null | head -n 2000 || true
} > "$REPORT_DIR/platform-references.txt"

{
  echo "Candidate portable source inventory"
  find "$ROOT/Utilities" "$ROOT/rpcs3/Emu" -type f \
    \( -name '*.cpp' -o -name '*.cc' -o -name '*.c' -o -name '*.h' -o -name '*.hpp' \) \
    | sort
} > "$REPORT_DIR/source-inventory.txt"

cat > "$REPORT_DIR/summary.md" <<EOF
# RPCS3 iOS portability audit

- Upstream commit: \`$UPSTREAM_SHA\`
- Target: \`arm64-apple-ios26.0\`
- This workflow inventories blockers; it does not claim upstream RPCS3 compiles for iOS.

## Required next work

1. Introduce an upstream-owned iOS platform definition without impersonating macOS.
2. Separate the emulator core from Qt and desktop process/window code.
3. Build Utilities and loader subsets against the iPhoneOS SDK.
4. Add interpreter-only PPU/SPU targets before JIT or rendering.
5. Replace unsupported desktop services with explicit iOS adapters.
EOF

tar -czf "$REPORT_DIR.tar.gz" "$REPORT_DIR"
echo "Audit complete for $UPSTREAM_SHA"
