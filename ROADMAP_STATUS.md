# RPCS3 iOS Roadmap Status

This file tracks implementation progress against [`REAL_RPCS3_IOS_BUILD_PLAN.md`](REAL_RPCS3_IOS_BUILD_PLAN.md). A phase is only marked complete when its stated exit criteria are supported by build or physical-device evidence.

## Phase 0 — Honest baseline

**Status: complete in source; current CI verification pending**

Completed:

- The shipping archive identifies itself as `partial-upstream`, not execution-capable.
- Runtime diagnostics distinguish probe-only, partial-upstream, and execution-capable states.
- The pinned RPCS3 revision and direct upstream source count are compiled into the bridge diagnostics.
- CI generates `build-manifest.json`, `upstream-source-manifest.txt`, archive member listings, symbols, and the resolved upstream commit.
- CI fails when a declared direct upstream source does not produce a matching archive object.
- The synthetic PPU/SPU runtime scaffold is excluded from `rpcs3_ios_core` and explicitly marked non-shipping.
- JIT and renderer availability remain false until actual linked upstream/platform backends exist.

Current shipping classification:

```text
partial-upstream
```

This means the archive contains direct upstream implementation code and loader-related port code, but it does not contain a functioning upstream `Emu.System` guest runtime.

## Phase 1 — Upstream core bootstrap

**Status: active**

Implemented so far:

- The separate upstream graph configures the real `rpcs3_emu` static target for arm64 iOS.
- Desktop Qt is excluded from the emulator target while UIKit remains the host frontend.
- LLVM/JIT is disabled for the interpreter-first bring-up.
- The graph applies explicit iOS portability work for libusb, AsmJit, Cubeb, and dependency selection.
- CI generates `phase1-emusystem-evidence.json` from `compile_commands.json`.
- The Phase 1 evidence gate verifies that upstream `rpcs3/Emu/System.cpp` is configured in the real target and records whether its object was produced.

Not complete:

- The shipping IPA does not yet link the real `rpcs3_emu` archive.
- An upstream `Emulator`/`Emu.System` instance has not yet initialized on a physical iOS device.
- Pause, resume, reboot, real boot, callbacks, and lifecycle operations are not exposed by a real upstream bridge.
- Guest PPU or SPU instructions are not executed.

Next Phase 1 gate:

1. Get the real `rpcs3_emu` target through its next iOS compiler blocker.
2. Produce a complete arm64 iOS `rpcs3_emu` archive.
3. Add a narrow non-Qt bridge that references the real global `Emu` lifecycle.
4. Link that bridge into a device test target.
5. Record physical-device initialization and shutdown evidence before changing the core classification.

## Phase 2 — Platform foundations

**Status: partially prepared, not complete**

Available groundwork:

- Sandbox data-root creation and shared host storage paths.
- Physical-device and Metal capability queries.
- Security-conscious import flow that copies selected content into the app container.
- Initial iOS compatibility work for USB and AudioUnit dependencies.

Still required:

- Upstream VM reservation/mapping/protection tests on device.
- Thread/TLS/priority and atomic wait/wake validation.
- Proof that upstream VFS and the UIKit host observe the same complete virtual PS3 filesystem.

## Phases 3–12

**Status: not started or not exit-criteria complete**

The repository contains UI routes and preliminary platform scaffolding for later systems, but none of the following are considered complete:

- Real PPU execution.
- LV2/HLE runtime.
- Real SPU execution.
- Firmware installation and VSH/XMB boot.
- Upstream PKG/folder/ISO boot pipelines.
- RSX-to-Metal rendering.
- Complete audio runtime.
- GameController/touch guest input.
- Compatibility validation or performance optimization.

## Classification rules

- **Probe-only:** no direct upstream implementation object is present in the shipping core.
- **Partial-upstream:** direct upstream objects are present, but physical-device `Emu.System` initialization and guest execution are not proven.
- **Execution-capable:** reserved for a build with real upstream lifecycle initialization and guest execution evidence. Compilation alone cannot grant this classification.
