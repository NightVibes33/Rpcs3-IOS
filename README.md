# RPCS3 iOS

Experimental iOS 26 real-device bring-up project for researching an RPCS3 port.

This repository starts with a native diagnostic shell and reproducible GitHub Actions packaging. It does **not** yet contain a functioning RPCS3 core or claim PS3 game compatibility.

## Current milestone

- iOS 26.0 deployment target
- GitHub-hosted macOS 26 runner
- Xcode 26 toolchain discovery
- Native Objective-C++ UIKit shell
- Unsigned real-device IPA packaging
- Runtime diagnostics for device, memory, graphics, and JIT capability

## Planned progression

1. Build and install the diagnostic shell.
2. Add an iOS portability audit for isolated RPCS3 subsystems.
3. Link a static interpreter-only RPCS3 core.
4. Bring up a null renderer, then MoltenVK.
5. Add optional JIT only after runtime capability tests pass.

No PlayStation firmware, games, keys, or copyrighted Sony files are included.
