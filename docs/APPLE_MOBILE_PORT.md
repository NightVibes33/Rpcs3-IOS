# RPCS3 Apple Mobile Port Layer

This bundle replaces remaining macOS/desktop assumptions with one shared implementation for **iOS and iPadOS**.

Implemented:

- UIKit idle-timer control instead of macOS IOPM assertions.
- AVAudioSession playback setup at 48 kHz.
- Native GameController polling wired into `rpcs3_ios_upstream_set_pad_state`.
- Correct iOS touch-controller button masks, plus L3/R3 support.
- Background pause, foreground resume, controller disconnect neutralization, memory-warning and thermal checkpoints.
- iPhone/iPad device profiling and target family `1,2`.
- App-sandbox Application Support and Documents locations.
- HIDAPI's existing C pthread-barrier fallback enabled exactly once for iOS and iPadOS.
- Exclusion of ApplicationServices/Carbon event injection and Finder/QProcess launching.
- A Vulkan presentation checkpoint written to `Library/Application Support/RPCS3/runtime/apple-mobile-runtime.jsonl`.

## Apply

From the Rpcs3-IOS repository root:

```bash
python3 /path/to/RPCS3-Apple-Mobile-Port/scripts/install-apple-mobile-port.py .
```

The installer copies the files and inserts the upstream patcher after the existing full-Qt blocker patch. If no build-script anchor is found, add this immediately after the upstream clone/overlay steps:

```bash
python3 scripts/patch-upstream-apple-mobile-platform.py "$ROOT"
```

Audit a patched checkout:

```bash
python3 scripts/audit-apple-mobile-port.py . --upstream-root upstream-rpcs3-full-qt
```

This layer does not claim gameplay success until a physical-device run records PKG installation, an installed `EBOOT.BIN` boot, Vulkan/MoltenVK initialization and `graphics.first-frame` in the runtime JSONL log.
