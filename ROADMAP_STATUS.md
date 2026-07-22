# RPCS3 iOS Roadmap Status

This file tracks implementation progress against [`REAL_RPCS3_IOS_BUILD_PLAN.md`](REAL_RPCS3_IOS_BUILD_PLAN.md). A phase is only marked complete when its stated exit criteria are supported by build or physical-device evidence.

## Phase 0 — Honest baseline

**Status: complete in source; current CI verification pending**

Completed:

- Runtime diagnostics distinguish probe-only, partial-upstream, and execution-capable states.
- The pinned RPCS3 revision and direct upstream source count are compiled into diagnostics.
- CI generates upstream source, archive member, symbol, and resolved-revision evidence.
- The synthetic PPU/SPU runtime scaffold is excluded from the shipping archive.
- JIT and renderer availability remain false until actual linked and device-tested backends exist.

Current classification remains:

```text
partial-upstream
```

Compilation and linking alone do not grant execution-capable status.

## Phase 1 — Upstream core bootstrap

**Status: active; real runtime integration implemented in source, CI/device evidence pending**

Implemented in source:

- The real upstream `rpcs3_emu` target configures for arm64 iOS without the desktop Qt host.
- LLVM/JIT is disabled for the interpreter-first path.
- PPU and SPU use RPCS3's upstream static interpreter modes.
- The non-Qt bridge initializes the real global `Emu` lifecycle.
- Required Null keyboard, mouse, pad-thread, audio, camera, music, and `NullGSRender` objects are initialized through upstream fixed-object storage.
- The bridge exposes initialize, `Emulator::BootGame`, pause, resume, stop, state, and diagnostic entry points.
- `RPCS3UpstreamRuntime.framework` packages the real emulator graph as one embeddable iOS runtime.
- The Qt IPA build links and embeds that framework under `Frameworks/`.
- The host and upstream runtime share one authoritative sandbox root through `RPCS3_CONFIG_DIR`.

Still required before Phase 1 completion:

- Green framework and IPA CI evidence for the current bridge.
- Physical-device evidence that `Emu.Init()` completes.
- Physical-device evidence that an installed title enters the real PPU/LV2 boot path.
- Clean shutdown evidence without deadlocks.

## First playable PKG vertical slice

**Target application: a user-provided legal PS3 PKG such as PKGi or a smaller homebrew test package.**

Implemented in source:

1. The Qt **Install Packages** action copies the selected PKG into the app sandbox.
2. The runtime calls upstream `package_reader::extract_data()` directly.
3. RPCS3 installs the package into the shared `dev_hdd0/game` tree.
4. The bridge stores RPCS3's returned installed `USRDIR/EBOOT.BIN` path.
5. The Qt host refreshes the game list and automatically calls upstream `Emulator::BootGame()` on that path.
6. Build validation requires the installer and lifecycle symbols in the embedded runtime and final app.

Not yet complete:

- Current output uses upstream `NullGSRender`, so there is no visible gameplay.
- GameController/touch input is not yet connected to the upstream pad thread.
- Audio remains the upstream Null backend.
- PKGi networking has not been validated on device.
- A successful package install and boot has not yet been recorded from a physical iPhone.

Exit criteria for this vertical slice:

- A legal PKG installs without partial files.
- RPCS3 returns and accepts the installed boot path.
- The title reaches its main loop through real PPU/SPU/LV2 execution.
- RSX frames are presented through the iOS renderer.
- At least one controller or touch input path works.
- The title remains responsive long enough to navigate and perform its core function.

## Phase 2 — Platform foundations

**Status: partially prepared, not complete**

Available groundwork:

- Sandbox data-root creation and shared RPCS3 virtual-storage paths.
- Physical-device and Metal capability queries.
- Security-conscious imports copied into the app container.
- Initial iOS compatibility work for USB, FFmpeg, Cubeb, executable-memory restrictions, and configuration paths.

Still required:

- Upstream VM reservation/mapping/protection tests on device.
- Thread/TLS/priority and atomic wait/wake validation.
- Runtime memory-pressure and background/foreground recovery.

## Renderer milestone

**Status: Null RSX boot lane active; visible renderer not implemented**

The first visible renderer must preserve upstream RSX command processing and replace only the platform renderer/presentation layer. The planned order is:

1. Prove the PKG reaches RSX initialization with `NullGSRender`.
2. Add an iOS frame/surface object backed by `CAMetalLayer`.
3. Add the RPCS3 renderer enum/factory path for the iOS backend.
4. Implement RSX resources, shaders, render targets, synchronization, and presentation in Metal.
5. Evaluate RPCS3 Vulkan over MoltenVK as an additional compatibility path without treating it as the native Metal backend.

## Remaining phases

The following are not exit-criteria complete:

- Complete LV2/HLE validation.
- Complete SPU execution validation.
- Firmware installation and VSH/XMB boot.
- ISO/disc mounting.
- RSX-to-Metal rendering.
- AudioUnit output.
- GameController/touch guest input.
- Networking validation.
- Compatibility and performance optimization.

## Classification rules

- **Probe-only:** no direct upstream implementation object is present in the shipping core.
- **Partial-upstream:** direct upstream runtime code is present, but physical-device initialization and guest execution are not proven.
- **Execution-capable:** reserved for a build with physical-device `Emu.Init()`, guest execution, and clean lifecycle evidence.
