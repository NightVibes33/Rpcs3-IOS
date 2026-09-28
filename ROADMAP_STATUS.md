# RPCS3 iOS Roadmap Status

This document tracks the canonical XITRIX-based iOS port on `main`.

## Current product classification

```text
Native SwiftUI/UIKit RPCS3 iOS host
+ XITRIX/rpcs3 ios-port RPCS3Core
+ complete public iOS ABI v30 bridge
```

The old Qt/v0.0.40 architecture is retired from the product path.

## Verified build baseline

Current canonical main build:

```text
main: fc89a3887e7c14325d846c053501c13ea50df00a
workflow: Build Real RPCS3 iOS #27
result: PASS
```

Pinned XITRIX source revision:

```text
559987e966db0f8ac983502a160b419968e2474d
```

Verified by CI:

- source-built XITRIX `libRPCS3Core.dylib`;
- RPCS3 iOS ABI v30;
- 74/74 public ABI functions present in the bridge;
- 74/74 required public ABI symbols validated in the compiled dylib;
- native arm64 iPhoneOS SwiftUI host;
- delayed `dlopen` of RPCS3Core after JIT policy selection;
- LLVM/JIT execution self-test wired as a startup gate;
- no Qt, Flutter or legacy `RPCS3UpstreamRuntime` dependency in the app executable;
- valid unsigned IPA artifact.

## Phase 1 — Core bootstrap

**Status: build-complete; physical-device execution still to prove**

Implemented:

- current XITRIX iOS RPCS3 core;
- LLVM enabled;
- ARM64/JIT infrastructure;
- iOS JIT arena policy;
- emulator initialize/shutdown/pause/resume/stop;
- build-info/state/error APIs;
- boot progress and performance metrics.

Remaining proof:

- successful JIT self-test on the user's physical device;
- clean `Emu.Init()` and shutdown on device;
- stable repeated launch/stop cycles.

## Phase 2 — iOS platform integration

**Status: implemented in product build; device-runtime validation pending**

Implemented:

- native SwiftUI/UIKit frontend;
- `CAMetalLayer` display surface;
- Vulkan/MoltenVK path owned by RPCS3Core;
- iOS audio backend consumed through the XITRIX core;
- GameController input for multiple RPCS3 pad ports;
- touch-controller fallback;
- pad feedback bridge;
- background/foreground pause/resume;
- file importer and security-scoped file flow;
- device diagnostics/log sharing.

Remaining proof:

- real-device render presentation;
- route/interruption audio tests;
- controller/touch validation in a guest workload;
- memory-pressure/lifecycle soak testing.

## Phase 3 — Firmware and content

**Status: complete at ABI/host level; device validation pending**

Implemented through RPCS3Core:

- firmware installation and version query;
- PKG installation;
- ISO installation;
- ZIP installation;
- extracted folder installation;
- RAP installation;
- installed-game enumeration;
- per-title boot;
- VSH/XMB boot;
- Big Picture Mode.

Remaining proof:

- install official user-provided firmware on device;
- boot XMB;
- install and boot a small legal homebrew title;
- validate a real disc/ISO workflow where legally available.

## Phase 4 — RSX / rendering

**Status: full source/build path present; physical frame proof pending**

Implemented:

- XITRIX Vulkan path;
- MoltenVK;
- native `CAMetalLayer`;
- display-surface ABI;
- boot progress and performance telemetry.

Exit gate:

- first real guest RSX frame on physical iPhone/iPad;
- repeated presentation without drawable/swapchain failure;
- stable orientation/lifecycle handling.

## Phase 5 — Audio and input

**Status: integrated; guest validation pending**

Implemented:

- iOS audio path from XITRIX core;
- AVAudioSession host configuration;
- physical GameController mapping;
- up to seven RPCS3 pad slots;
- on-screen controller fallback;
- pad feedback API.

Exit gate:

- audible guest output;
- no sustained underrun/crackle in a test title;
- physical and touch input confirmed in guest;
- feedback/rumble confirmed where supported.

## Phase 6 — User-facing RPCS3 functionality

**Status: broad ABI parity implemented**

Current native host integrates:

- game library;
- Big Picture Mode;
- XMB;
- firmware/content import;
- Sony PS3 title updates;
- global settings;
- per-game settings;
- settings presets;
- compatibility/config database;
- Patch Engine repository/runtime patches;
- trophies;
- savestates, including import/export/duplicate/delete;
- game cache inspection/clearing;
- installed-title deletion;
- RPCN servers and credentials;
- RPCN account lifecycle;
- RPCN social actions;
- diagnostics and logs.

CI validates the full public ABI-v30 symbol surface used by these features.

## Phase 7 — First playable title

**Status: not yet proven on a physical device**

Required sequence:

1. Sign and sideload the canonical IPA.
2. Launch through StikDebug using the Universal JIT path.
3. Pass the LLVM/JIT self-test.
4. Install official user-provided firmware.
5. Confirm XMB or Big Picture presentation.
6. Install a small legal homebrew PKG.
7. Boot it through RPCS3Core.
8. Confirm frames, audio, input and stable execution.
9. Stop and relaunch successfully.
10. Progress to heavier titles only after the small workload is stable.

## Completion rules

The following remain separate claims:

- **Build-complete:** CI compiles and packages the app.
- **ABI-complete:** the native host exposes the complete current public core contract.
- **Device-bootable:** RPCS3 initializes and presents UI on physical iOS hardware.
- **Playable:** a guest title renders, accepts input, produces usable audio and remains stable.

The project has reached the first two. Physical-device testing is required for the last two.
