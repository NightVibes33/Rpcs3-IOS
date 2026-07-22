# RPCS3 iOS Roadmap Status

This file tracks evidence-based implementation progress against [`REAL_RPCS3_IOS_BUILD_PLAN.md`](REAL_RPCS3_IOS_BUILD_PLAN.md).

The detailed feature-by-feature truth table is in [`RPCS3_PARITY_AUDIT.md`](RPCS3_PARITY_AUDIT.md).

A phase is complete only when its exit criteria are supported by build artifacts and physical-device evidence. Bundled `.ui` files, API declarations, linked object files and successful IPA packaging are not sufficient by themselves.

## Current product classification

```text
RPCS3 iOS upstream-core integration prototype with a custom Qt launcher shell
```

The project is **not yet a playable PS3 emulator** and is **not yet a complete port of the RPCS3 application**.

## Phase 0 — Honest baseline

**Status: complete**

- Diagnostics distinguish probe-only, partial-upstream and execution-capable states.
- The pinned upstream revision is recorded.
- CI records upstream sources, symbols and build products.
- The project no longer treats a synthetic instruction loop or copied UI file as RPCS3 execution.
- The README and parity audit distinguish linked source from working/device-tested behavior.

## Phase 1 — Upstream core bootstrap

**Status: implemented in source; device-unproven**

Present in source:

- Pinned upstream `rpcs3_emu` graph configured for arm64 iOS.
- Desktop `rpcs3_ui` excluded from the runtime graph.
- LLVM/JIT disabled for the interpreter-first lane.
- Upstream static PPU and SPU interpreter modes selected.
- Narrow bridge for `Emu.Init()`, `Emu.BootGame()`, pause, resume, stop, state and diagnostics.
- `RPCS3UpstreamRuntime.framework` embedded in the Qt IPA.
- Shared sandbox data root through `RPCS3_CONFIG_DIR`.

Required evidence:

- Green framework and IPA build for the current head.
- Physical-device proof that `Emu.Init()` completes.
- Physical-device proof that workers, VM and VFS initialize correctly.
- Physical-device proof of clean stop and relaunch without deadlock.

## Frontend parity

**Status: custom launcher shell; upstream desktop frontend not ported**

The current Qt app bundles upstream `.ui` documents, but it does not compile the upstream `rpcs3_ui` target or most of its implementation classes.

Current host behavior is limited to:

- custom action routing;
- raw `.ui` loading through `QUiLoader`;
- sandbox file staging/import;
- basic directory-scanned game list;
- narrow bridge diagnostics and lifecycle calls;
- dedicated PKG install/auto-boot flow.

Most settings, managers, tools and dialogs are visual forms without their upstream C++ behavior, or actions routed to `showPending()`.

## Phase 2 — Platform foundations

**Status: partial; major device blockers unproven**

Present:

- sandbox storage layout;
- physical-device and Metal capability checks;
- import-to-container flow;
- initial libusb, FFmpeg, Cubeb, JIT-restriction and config-path overlays.

Still required:

- VM reservation, mapping, protection, guard-page and shared-memory tests;
- thread/TLS/priority/semaphore/atomic wait-wake tests;
- memory-pressure behavior;
- background/foreground suspension and recovery;
- complete runtime log export from a physical device.

## Phase 3 — PPU execution

**Status: upstream implementation linked; guest execution unproven**

- Static PPU interpreter selected.
- Upstream loaders and `BootGame()` are linked.
- No physical-device evidence yet proves a PPU guest reaches its main loop.

Exit requires a controlled legal homebrew workload executing through upstream PPU code with logs and stable shutdown.

## Phase 4 — LV2/HLE runtime

**Status: upstream source linked; behavior unproven**

The graph contains upstream LV2 and module implementations, but there is no device evidence that process, memory, thread, event, filesystem, sysutil, input, audio and networking services work correctly on iOS.

Exit requires a homebrew application reaching and remaining in its main loop through real upstream LV2/HLE paths.

## Phase 5 — SPU execution

**Status: upstream implementation linked; guest workload unproven**

- Static SPU interpreter selected.
- No device evidence proves SPU threads, MFC/DMA, reservations or PPU/SPU synchronization.

## Phase 6 — Firmware and VSH/XMB

**Status: incomplete**

Current source declares firmware bridge APIs, but a complete verified PUP installation workflow is not yet present end to end.

Required:

1. User selects an official unmodified `PS3UPDAT.PUP`.
2. File is copied into the app sandbox.
3. Upstream PUP/SCE/TAR implementation validates and extracts it.
4. Required `dev_flash` files and firmware version are verified.
5. PKG/title boot is blocked when firmware is missing.
6. VSH starts through RPCS3's proper VSH boot path, not merely by finding and directly submitting `vsh.self`.
7. XMB renders, accepts input and uses the same `dev_hdd0` as the host game list.

## Phase 7 — PKG, folders and ISO

### PKG

**Status: upstream install call exists; device-unproven**

- Host copies a selected PKG into the sandbox.
- Runtime calls upstream `package_reader::extract_data()`.
- Host attempts to auto-boot the returned path.
- No physical-device package install/boot result has been captured.

### Folder/SELF/ELF

**Status: bridge exists; device-unproven**

The host performs its own simple executable discovery. Upstream boot acceptance and guest execution are not proven.

### ISO/disc

**Status: placeholder**

The current host stages ISO/disc files. Proper upstream ISO parsing, decryption, `dev_bdvd` mount, disc insertion/ejection and boot are not connected end to end.

### RAP/RIF/licenses

**Status: placeholder**

The current host stages files into a keys directory. Upstream license import, account association and content activation are not implemented end to end.

## Phase 8 — Rendering

### Vulkan through MoltenVK

**Status: source path implemented; physical-device frame unproven**

Present:

- pinned MoltenVK dependency builder;
- upstream Vulkan source included in the runtime graph;
- custom iOS `UIView`/`CAMetalLayer` frame host;
- bridge selects upstream `VKGSRender` when the surface exists.

Required:

- framework and final IPA link proof for current head;
- physical-device Vulkan instance/device creation;
- successful Metal-surface and swapchain creation;
- first real RSX frame;
- resize/orientation/drawable-loss recovery;
- stable frame presentation during a guest workload.

### Native Metal backend

**Status: missing**

No native RPCS3 Metal renderer exists in the repository yet. MoltenVK is the first compatibility path, not proof of a native Metal backend.

## Phase 9 — Audio

**Status: missing**

The runtime currently returns `NullAudioBackend` and a null enumerator. AudioUnit/AVAudioSession output, buffering, route changes and interruption recovery are not implemented.

## Phase 10 — Input

**Status: missing**

The upstream pad thread is linked, but no usable GameController or touch guest-input backend is connected. Keyboard and mouse handlers are Null.

## Host services and dialogs

**Status: mostly missing**

The runtime currently returns empty or no-op implementations for major host contracts, including:

- message and OSK dialogs;
- save-data dialogs;
- send/receive message dialogs;
- trophy notifications;
- localization and fonts;
- image decoding/scaling;
- microphone/video source;
- breakpoints and several host-control callbacks.

These services can block real applications even after PPU/LV2 execution begins.

## First playable PKG vertical slice

**Target:** one legal user-provided homebrew PKG first, then PKGi.

Required gates:

1. Real firmware install and readiness validation.
2. Physical-device VM/thread/VFS/`Emu.Init()` proof.
3. Real PKG extraction and PPU/LV2 main-loop proof.
4. One real RSX frame through Vulkan/MoltenVK.
5. At least one usable controller or touch input path.
6. For PKGi: validated sockets, DNS, TLS, storage and any required OSK/dialog behavior.

The vertical slice is complete only when the title is visible, controllable, responsive and able to perform its core function.

## Full RPCS3 application parity after first playability

Still required:

- functional game list, metadata and compatibility integration;
- global and per-title configuration;
- users, licenses, savedata and trophies;
- patch, cheat, screenshot, cache and shader management;
- VSH/XMB and shared content environment;
- ISO/disc lifecycle;
- savestates;
- debugger and developer tools;
- audio, input, networking and lifecycle recovery;
- performance and compatibility work.

## Completion rules

- `.ui` present ≠ feature implemented.
- API declared ≠ API implemented.
- object linked ≠ runtime working.
- IPA built ≠ guest executable running.
- renderer linked ≠ frame presented.
- `BootGame()` returned success ≠ title playable.
- PKG extracted ≠ application usable.
- Playable requires rendering, input, stable execution and the title's core function.
