# RPCS3 iOS — XITRIX ABI v30 Parity Audit

## Current result

The canonical application on `main` is no longer the old Qt/v0.0.40 prototype.

It is a native SwiftUI/UIKit frontend built around the current XITRIX RPCS3 iOS core.

### Verified baseline

```text
XITRIX source: 559987e966db0f8ac983502a160b419968e2474d
RPCS3 iOS ABI: 30
Public ABI functions: 74
Bridge coverage: 74/74
Compiled symbol gate: 74/74
Canonical main build: PASS
Unsigned IPA packaging: PASS
```

## Architecture parity

| Area | Current state |
| --- | --- |
| Product frontend | Native SwiftUI/UIKit |
| RPCS3 core | XITRIX/rpcs3 `ios-port` |
| Core loading | Delayed `dlopen` after JIT policy selection |
| LLVM/JIT | Enabled; self-test required before controls unlock |
| JIT arena | XITRIX iOS arena policy, including expanded configuration |
| Rendering | RPCS3 Vulkan through MoltenVK to `CAMetalLayer` |
| Audio | XITRIX iOS audio backend + host AVAudioSession |
| Physical input | GameController -> RPCS3 pad ABI |
| Touch input | Native on-screen PS3 controller fallback |
| Lifecycle | initialize, pause, resume, stop, shutdown wired |
| Qt | Not linked into canonical product |
| Flutter | Not linked |
| Legacy runtime framework | Not linked |

## Public ABI coverage

The current Objective-C++ bridge references every public function in XITRIX's current `RPCS3IOS.h`.

CI validates those symbols in the compiled dylib as well.

Covered groups include:

### Core lifecycle and diagnostics

- ABI/build info;
- initialization and shutdown;
- pause/resume/stop;
- emulation state;
- last-error reporting;
- LLVM JIT self-test;
- boot progress;
- performance metrics.

### Display and input

- display-surface attach/detach;
- pad-state injection;
- pad feedback.

### Content and boot

- firmware install/version;
- PKG;
- ISO;
- ZIP;
- extracted folder;
- RAP;
- installed-game enumeration;
- game boot;
- Big Picture Mode;
- VSH/XMB.

### Game updates

- Sony update manifest fetch;
- update-package download;
- title-checked game patch installation.

### Settings

- global setting enumeration/set/reset;
- per-game setting enumeration/set/reset/remove;
- settings presets;
- preset save/apply/duplicate/rename/delete;
- preset import/export;
- configuration database update.

### Patch Engine

- patch-repository URL;
- patch-repository install;
- game patch enumeration;
- runtime patch enumeration;
- runtime patch enable/disable.

### Saves and trophies

- trophy enumeration;
- savestate enumeration;
- savestate boot;
- duplicate/delete;
- savestate import/export.

### Game storage

- cache usage;
- cache clearing;
- installed-game deletion.

### RPCN

- config/profile state;
- server enumeration/add/remove/select;
- credentials;
- account creation;
- token resend;
- password-reset request/reset;
- account deletion;
- account test;
- social enumeration/actions.

## Native host functionality

The SwiftUI host provides native iOS equivalents for the core-facing desktop workflows rather than attempting to compile RPCS3's desktop Qt frontend.

Implemented host surfaces include:

- library/game details;
- direct boot;
- XMB and Big Picture;
- content/firmware import;
- updates;
- settings and presets;
- patches;
- trophies;
- savestates;
- RPCN;
- cache/storage;
- controller/touch input;
- performance HUD;
- diagnostics/log export.

## What CI proves

The green canonical build proves:

- current XITRIX core compatibility;
- complete ABI-v30 symbol availability;
- native iOS host compilation;
- correct delayed-core-loading boundary;
- absence of legacy Qt/Flutter product dependencies;
- correct arm64 iPhoneOS packaging;
- successful unsigned IPA artifact generation.

## What CI does not prove

CI cannot establish physical-device guest playability.

Still requiring real-device evidence:

| Device gate | Status |
| --- | --- |
| StikDebug/Universal JIT launch | Not yet captured from physical device |
| LLVM execution self-test on device | Not yet captured |
| `Emu.Init()` on device | Not yet captured |
| Firmware installation | Not yet captured |
| XMB/Big Picture rendered frame | Not yet captured |
| Homebrew title boot | Not yet captured |
| Sustained RSX presentation | Not yet captured |
| Guest audio | Not yet captured |
| Guest physical/touch input | Not yet captured |
| Background/foreground recovery | Not yet captured |
| Sustained gameplay stability | Not yet captured |

## Current honest classification

**Build-complete, ABI-complete native RPCS3 iOS integration using XITRIX RPCS3Core. Physical-device playability remains the next acceptance gate.**
