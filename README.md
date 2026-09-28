# RPCS3 iOS

[![Build Real RPCS3 iOS](https://github.com/NightVibes33/Rpcs3-IOS/actions/workflows/build-real-rpcs3-ios.yml/badge.svg?branch=main)](https://github.com/NightVibes33/Rpcs3-IOS/actions/workflows/build-real-rpcs3-ios.yml)

Experimental iPhone/iPad RPCS3 project built around the XITRIX iOS core.

> [!IMPORTANT]
> The official XITRIX app and this repository's experimental SwiftUI/UIKit host are different frontends. Use the official release below when you want the actual XITRIX app. The source project and its build files remain in this repository.

## Install the actual XITRIX app

[Download the official XITRIX v0.10 IPA](https://github.com/XITRIX/RPCS3-iOS-Releases/releases/download/v0.10/RPCS3.ipa) · [Release notes](https://github.com/XITRIX/RPCS3-iOS-Releases/releases/tag/v0.10)

Import the `.ipa` in SideStore or AltStore. Follow the [official XITRIX instructions](https://github.com/XITRIX/RPCS3-iOS-Releases) for launch/JIT setup, then supply your own PS3 firmware and legally dumped games.

This is the actual upstream XITRIX frontend. The native `NativeApp/` source below is this repo's separate experimental host.

### The NeoStation file that caused the import error

The artifact from [NeoStation run 36343065903](https://github.com/TarbleFR/neostation-ios/actions/runs/36343065903) is named `RPCS3Core-7ecc36bdb9f1206aedff02cb15aa23341c242f91.zip`. It contains `libRPCS3Core.dylib` and build metadata, with no `Payload/*.app/Info.plist`. It's a core for another frontend, not an IPA, so SideStore correctly rejects it. NeoStation is optional; you don't need it to install XITRIX's app.

### Get the exact official IPA through this repo

Run **Actions → Verify official XITRIX RPCS3 iOS IPA → Run workflow**. The workflow checks the official v0.10 GitHub release SHA-256 and IPA structure, then uploads the unmodified app as `RPCS3-XITRIX-v0.10-official-IPA`.

```text
SHA-256: ba80e48ca9ee947a6b0ccbda05bc9af4cf190e1552e4aa550eb9d6ef143e1a91
```
## Current verified build

Latest verified source-build commit:

```text
c7614f4e7a9025b1452be757d1b739f7a7d56bc2
```

Canonical workflow:

```text
.github/workflows/build-real-rpcs3-ios.yml
```

Latest canonical run:

```text
Build Real RPCS3 iOS #29
PASS
```

That run successfully:

- consumed the verified source-built XITRIX RPCS3Core;
- compiled the SwiftUI/UIKit arm64 iPhoneOS application with Xcode 16.4;
- validated the complete RPCS3 iOS ABI v30 surface;
- verified the app does **not** load `libRPCS3Core.dylib` at process launch;
- verified Qt, Flutter and `RPCS3UpstreamRuntime` are absent from the product;
- embedded `Frameworks/libRPCS3Core.dylib`;
- packaged a valid unsigned IPA.

Produced artifact:

```text
RPCS3-XITRIX-iOS-c7614f4-unsigned.ipa
```

## Architecture

```text
SwiftUI / UIKit native frontend
          |
          | Objective-C++ dynamic ABI bridge
          |
          | sets JIT policy before core load
          v
dlopen(Frameworks/libRPCS3Core.dylib)
          |
          | RPCS3 iOS ABI v30
          v
XITRIX/rpcs3 ios-port
          |
          +-- ARM64 PPU/SPU + LLVM/JIT
          +-- iOS JIT arena / Universal JIT path
          +-- LV2 / HLE / loaders / VFS
          +-- firmware / PKG / ISO / ZIP / folder / RAP
          +-- Vulkan -> MoltenVK -> CAMetalLayer
          +-- iOS audio backend
          +-- iOS pad backend / feedback
          +-- RPCN
          +-- trophies / savestates / settings / patches / caches
```

Pinned XITRIX source revision:

```text
559987e966db0f8ac983502a160b419968e2474d
```

The application deliberately does **not** link RPCS3Core at process startup. It selects `RPCS3_IOS_EXPANDED_JIT_ARENA`, then loads the core dynamically and runs the ABI/LLVM self-test. This matches the startup model discovered from the official XITRIX iOS application.

## Public ABI coverage

The current bridge references **74/74** public functions exported by XITRIX's current `RPCS3IOS.h`.

CI also validates all 74 required symbols against the compiled `libRPCS3Core.dylib`.

That includes:

- initialize / shutdown / pause / resume / stop;
- LLVM JIT execution self-test;
- display-surface attachment;
- physical and touch pad state plus pad feedback;
- game enumeration and boot;
- Big Picture Mode;
- VSH/XMB boot;
- firmware install;
- PKG, ISO, ZIP, folder and RAP import;
- Sony game-update manifest/download/install flow;
- trophies;
- savestates including import/export/duplicate/delete;
- global and per-game settings;
- game-setting presets including import/export;
- Patch Engine repository/runtime patch management;
- compatibility/config database updates;
- game cache inspection/clearing;
- installed-title deletion;
- RPCN servers, credentials, account lifecycle and social actions;
- boot progress and performance telemetry.

## Native iOS frontend

The current app is a native SwiftUI/UIKit application. It includes iOS-native screens and controls for the RPCS3 core rather than attempting to ship the desktop Qt UI.

Current host capabilities include:

- native installed-game library;
- direct title boot;
- Big Picture Mode;
- PlayStation 3 XMB boot;
- firmware/content import;
- game updates;
- global RPCS3 settings;
- per-game settings and presets;
- game patches;
- trophies;
- save-state management;
- RPCN account/server/social management;
- game cache/storage management;
- physical controllers for RPCS3 pad ports;
- touch-controller fallback;
- boot-progress UI;
- FPS/CPU/RSX/RAM telemetry;
- device-log sharing/diagnostics.

## JIT startup

The app uses XITRIX's iOS JIT model.

On supported iOS versions the intended flow is:

1. Sign and install the IPA.
2. Open StikDebug.
3. Assign/use its Universal JIT script for RPCS3.
4. Launch RPCS3 from StikDebug.
5. Press **Start** inside RPCS3.
6. The app selects the JIT arena policy before loading RPCS3Core.
7. RPCS3Core initializes and the LLVM execution self-test must pass before emulator controls are enabled.

The host supports the expanded JIT-arena policy used by the current XITRIX port, including the 1 GiB option.

## Build the unsigned IPA

Open **Actions -> Build Real RPCS3 iOS -> Run workflow**.

The successful artifact is named:

```text
RPCS3-XITRIX-iOS-unsigned
```

The IPA itself follows:

```text
RPCS3-XITRIX-iOS-<commit>-unsigned.ipa
```

The retired Qt build workflows have been removed from active Actions. `QtApp/` remains only as legacy source material.

## Device-support metadata

The current target is:

- arm64 iPhone/iPad;
- iOS 17.4 or newer;
- native SwiftUI/UIKit;
- Game Mode capable;
- file sharing / Files integration enabled;
- local-network usage declared for RPCN;
- background audio enabled.

The entitlement template contains:

- `com.apple.developer.kernel.extended-virtual-addressing`;
- `com.apple.developer.kernel.increased-debugging-memory-limit`;
- `com.apple.developer.kernel.increased-memory-limit`;
- `get-task-allow`.

The final signing method/provisioning profile determines which entitlements are actually granted on device.

## What the green CI result proves

The current green build proves:

- the current XITRIX iOS core can be consumed by this project;
- the complete ABI v30 contract is present;
- the native iOS host compiles;
- the delayed-load/JIT startup boundary is preserved;
- the expected iOS frameworks are linked;
- the legacy Qt/Flutter/runtime bridge is absent from the app executable;
- the IPA can be packaged correctly as an unsigned arm64 iPhoneOS application.

It does **not** by itself prove that a commercial PS3 title is playable on a physical iPhone.

## Next physical-device gates

The remaining proof has to come from a signed installation on a real device:

1. JIT self-test passes after launching through StikDebug.
2. RPCS3 `Emu.Init()` completes without crash.
3. Official user-provided PS3 firmware installs and is detected.
4. Big Picture and/or XMB presents frames through MoltenVK/CAMetalLayer.
5. A small legal homebrew title boots.
6. Physical/touch controller input reaches the guest.
7. Audio is audible and stable.
8. Stop/relaunch and background/foreground lifecycle remain stable.
9. Then move to progressively heavier PS3 titles.

A green IPA build is a major build/integration gate; physical-device guest execution remains a separate acceptance gate.

## Repository map

| Path | Purpose |
| --- | --- |
| `NativeApp/` | Canonical SwiftUI/UIKit frontend and dynamic RPCS3Core bridge. |
| `scripts/build-real-xitrix-core.sh` | Builds the pinned XITRIX iOS core. |
| `scripts/build-real-ios-app.sh` | Builds the native iOS host and validates delayed loading. |
| `.github/workflows/build-real-rpcs3-ios.yml` | Canonical source/core/app/IPA workflow. |
| `QtApp/` | Retired legacy Qt experiment; not the canonical product. |
| `CoreBridge/` | Retired/legacy bridge material and historical experiments. |

## Legal

This is an experimental, unofficial project. It is not affiliated with Sony Interactive Entertainment, RPCS3, or XITRIX.

No PlayStation firmware, games, keys, licenses, copyrighted Sony files or commercial content are included. Users must supply and legally use their own content. Upstream projects and dependencies remain subject to their respective licenses.
