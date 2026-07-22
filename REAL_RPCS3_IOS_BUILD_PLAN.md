# Real RPCS3 iOS Port Build Plan

## Goal

Build an iOS application that uses upstream RPCS3 source files directly and exposes the same emulator concepts as desktop RPCS3:

- Shared host game list and installed-title database.
- Direct boot of folders, ELF/SELF content, installed PKG titles, and disc images.
- Firmware installation into RPCS3's virtual PS3 filesystem.
- A host-side **Boot VSH/XMB** action that starts the real PS3 dashboard through RPCS3's VSH boot path.
- Titles installed through the host UI and titles visible inside XMB must share the same `dev_hdd0`, `dev_flash`, licenses, caches, and configuration.
- Real upstream PPU, SPU, LV2, VFS, module, audio, and RSX execution paths.
- iOS-native presentation, input, audio, storage, and Metal backends without reimplementing the emulator core as a separate stub.

The project is not considered a real RPCS3 port until an upstream `Emu.System` instance can boot user-installed firmware, reach rendered VSH/XMB output on a physical iOS device, and launch at least one title through the shared RPCS3 environment.

## Non-goals

- Recreating XMB with UIKit.
- Shipping Sony firmware, keys, licenses, games, or dashboard assets.
- Calling an ELF probe or custom instruction loop "RPCS3 execution."
- Maintaining a parallel emulator core that only references RPCS3 headers.
- Claiming game compatibility before upstream execution paths are active.

## Required architecture

### Host frontend

UIKit remains the host interface for:

- Game list.
- Search and metadata.
- Firmware installation.
- PKG installation.
- ISO/folder import.
- Per-title configuration.
- Global RPCS3 configuration.
- Pads and touch controls.
- Logs and diagnostics.
- Boot Game.
- Boot VSH/XMB.

The host frontend must not implement PS3 behavior itself. It calls a narrow Objective-C/C bridge into the upstream RPCS3 core.

### Upstream RPCS3 core

The core must compile upstream implementation files directly from a pinned RPCS3 revision. The final binary should use upstream systems for:

- Emulator lifecycle.
- PPU execution.
- SPU execution.
- LV2 kernel and syscalls.
- SELF/PRX loading.
- Firmware module loading.
- VFS and virtual devices.
- PKG installation.
- Disc mounting.
- Audio modules.
- RSX command processing.
- Shader translation and rendering.
- VSH boot.
- Savedata, trophies, cache, and title configuration.

Custom iOS code is limited to platform backends, bridge code, build glue, and UI.

## Repository layout target

```text
App/                         UIKit frontend
CoreBridge/                  Stable C/Objective-C bridge
Port/iOS/                    iOS platform implementations
Port/Metal/                  RSX Metal backend
Port/AudioUnit/              AudioUnit backend
Port/GameController/         Controller backend
Port/Touch/                  Touch overlay backend
Port/Filesystem/             Sandbox and security-scoped URL support
Port/Threading/              iOS thread/TLS/priority compatibility
Port/Memory/                 VM reservation and executable-memory policy
cmake/                       iOS toolchain and upstream integration
scripts/                     Pinned upstream checkout and patch application
patches/upstream/            Minimal reviewable patches against RPCS3
upstream-rpcs3/              CI checkout only; not vendored unless licensing strategy changes
```

## Source-integration rule

Every emulator subsystem must come from upstream RPCS3 source files or a clearly documented upstream-derived patch.

Allowed:

- Compiling `rpcs3/Emu/...` source files directly.
- Small iOS conditionals submitted as patch files.
- New backend implementations conforming to existing RPCS3 interfaces.
- Temporary compatibility shims when an upstream interface requires a desktop implementation.

Not allowed as the final implementation:

- A replacement PPU interpreter unrelated to upstream RPCS3.
- A replacement SPU scheduler unrelated to upstream RPCS3.
- Custom syscall tables presented as LV2.
- A fake renderer that only creates a Metal command queue.
- A fake XMB built with UIKit.

## Phase 0: establish an honest baseline

### Tasks

- Mark existing custom runtime code as experimental.
- Remove capability flags that report PPU/SPU availability without upstream execution.
- Add a build manifest recording the pinned upstream RPCS3 commit.
- Save a generated list of all upstream source files included in the iOS core.
- Make CI fail if the core archive contains only bridge or port objects.
- Keep the current green unsigned-device IPA pipeline.

### Exit criteria

- CI artifact includes upstream commit, source manifest, archive members, and symbols.
- Diagnostics distinguish probe-only, partial-upstream, and execution-capable states.

## Phase 1: upstream core bootstrap

### Direct upstream source groups

Start with the minimal dependency closure around:

- `rpcs3/Emu/System.cpp`
- `rpcs3/Emu/System.h`
- Core configuration files.
- Logging infrastructure.
- Serialization utilities.
- Virtual memory framework.
- CPU thread base classes.
- Loader infrastructure.
- VFS core.
- Module registration infrastructure.

### Tasks

- Stop returning from upstream top-level CMake before RPCS3 targets are configured.
- Introduce an iOS core target inside the upstream build graph.
- Disable Qt GUI targets, updater, desktop dialogs, Vulkan, OpenGL, and unsupported desktop services.
- Preserve upstream compile definitions and generated headers.
- Build a static or framework-style `rpcs3_core_ios` library.
- Expose a narrow bridge for initialize, boot, stop, pause, resume, diagnostics, and callbacks.

### Exit criteria

- An upstream `Emulator`/`Emu.System` object initializes on a physical arm64 iOS runner.
- No custom execution loop is needed for initialization.
- The core can create its virtual filesystem and config directories.

## Phase 2: platform foundations

### Memory

RPCS3 depends heavily on virtual address-space management.

Tasks:

- Port VM reservation, mapping, protection, guard pages, and shared mappings to Mach APIs.
- Determine the maximum reliable guest address-space layout on arm64 iOS.
- Implement non-JIT interpreter mode first.
- Treat executable-memory/JIT support as optional and entitlement-dependent.
- Add runtime checks that reject unsupported memory layouts cleanly.

Exit criteria:

- Upstream VM tests pass on device.
- Guest memory can be reserved and mapped consistently across launches.

### Threading

Tasks:

- Map thread creation, TLS, affinity hints, priorities, semaphores, condition variables, and naming to Darwin APIs.
- Replace unsupported desktop assumptions.
- Validate atomic wait/wake behavior.

Exit criteria:

- RPCS3 worker, PPU, SPU, RSX, and audio threads can start and stop without deadlock.

### Filesystem

Tasks:

- Map RPCS3 data root into the app sandbox.
- Implement security-scoped imports.
- Maintain RPCS3-compatible paths for `dev_hdd0`, `dev_flash`, `dev_flash2`, `dev_flash3`, `dev_bdvd`, `app_home`, cache, config, and logs.
- Preserve case sensitivity expectations and safe path normalization.

Exit criteria:

- Host UI and upstream VFS observe the same files and metadata.

## Phase 3: real PPU execution

### Tasks

- Compile upstream PPU decoder, interpreter, thread state, executable loader, module manager, and related utilities.
- Begin with upstream PPU interpreter modes only.
- Disable LLVM/JIT until interpreter boot is stable.
- Load ELF/SELF program segments through upstream loaders into upstream VM.
- Implement callback delivery to the UIKit host without blocking emulator threads.

### Exit criteria

- An upstream PPU thread executes a controlled homebrew ELF.
- Instruction count advances through upstream PPU code.
- Exceptions and unsupported instructions are reported through upstream logging.

## Phase 4: real LV2 and module runtime

### Direct upstream areas

- `rpcs3/Emu/Cell/lv2/...`
- `rpcs3/Emu/Cell/Modules/...`
- PRX/module loading.
- Process, memory, thread, event, synchronization, timer, filesystem, input, audio, and networking syscalls.

### Tasks

- Compile the actual LV2 syscall implementations.
- Link module registration and HLE libraries.
- Bring up process/thread/memory/event primitives first.
- Then filesystem, sysutil, input, audio, savedata, trophy, and network modules.
- Keep unsupported modules explicit rather than silently succeeding.

### Exit criteria

- A homebrew application reaches its main loop using upstream LV2/HLE paths.
- Upstream logs show real process and module initialization.

## Phase 5: real SPU execution

### Tasks

- Compile upstream SPU thread, interpreter, channels, MFC/DMA, reservations, events, and thread-group scheduling.
- Start with interpreter mode.
- Validate synchronization with upstream PPU and VM systems.
- Add device-focused scheduling limits if needed without altering guest-visible behavior.

### Exit criteria

- SPU test programs run through upstream SPU code.
- PPU/SPU synchronization tests complete.
- A real title reaches SPU workloads without immediate fatal errors.

## Phase 6: firmware and VSH/XMB

### Firmware installation

Tasks:

- Use upstream firmware/PUP installation code.
- Install user-provided firmware into the shared RPCS3 data root.
- Validate required `dev_flash` contents and firmware version.
- Surface installation progress and errors in UIKit.

### VSH boot

Tasks:

- Expose upstream VSH/XMB boot as a host action.
- Use the same upstream emulator lifecycle as game boot.
- Mount the installed firmware and virtual devices using upstream paths.
- Start the VSH executable selected by RPCS3's existing VSH boot logic.
- Route controller input, audio, and RSX output through iOS backends.

### Shared game environment

The host game list and XMB must use the same virtual PS3 installation:

- PKG installs go into upstream-compatible `dev_hdd0/game` locations.
- Licenses go into the same user/profile data used by upstream RPCS3.
- Host scanning reads metadata from the upstream data root.
- XMB sees those installed titles through the emulated firmware.
- Booting from the host list and selecting from XMB both use the same core and storage.

### Exit criteria

- The host menu exposes **Boot VSH/XMB**.
- User-installed firmware boots through upstream RPCS3 code.
- The real firmware XMB produces frames and accepts input.
- At least one host-installed PKG title appears inside XMB.

## Phase 7: PKG, folders, and ISO

### PKG

Tasks:

- Use upstream package reader and installer directly.
- Validate package headers and content IDs.
- Support user-provided RAP/RIF/license material through upstream paths.
- Install atomically with progress and rollback.
- Refresh the shared host game list after installation.

Exit criteria:

- A legal test PKG installs through upstream RPCS3 code.
- The installed title appears in both the host list and XMB.

### Folder games/apps

Tasks:

- Use upstream SFO and boot-path discovery.
- Mount folder content using upstream VFS rules.
- Resolve `EBOOT.BIN` through upstream loaders.

Exit criteria:

- A homebrew folder title boots through upstream `Emu.System`.

### ISO/disc images

Tasks:

- Use upstream disc/decryption/mount code.
- Mount images as `dev_bdvd`.
- Support required user-provided disc keys where applicable.
- Expose disc metadata in the host list without extracting the full image.

Exit criteria:

- A valid disc image mounts as `dev_bdvd`.
- Upstream boot logic resolves the disc executable.
- The same mounted title can be launched through the host list.

## Phase 8: RSX to Metal

This is the largest iOS-specific subsystem.

### Strategy

Keep upstream RSX command processing, memory, resources, synchronization, and guest behavior. Add a Metal implementation behind RPCS3's renderer interfaces.

### Tasks

- Compile upstream RSX thread, FIFO, methods, textures, surfaces, caches, and synchronization.
- Add a Metal renderer backend rather than replacing RSX.
- Translate RSX/NV shader programs into an intermediate form compatible with Metal shader generation.
- Implement vertex/index buffers, textures, samplers, render targets, depth/stencil, blending, clears, queries, and presentation.
- Implement resource lifetime and cache invalidation.
- Connect presentation to `CAMetalLayer` owned by UIKit.
- Handle app backgrounding, drawable loss, resize, rotation, and memory pressure.

### Exit criteria

- RSX test content renders known output.
- VSH/XMB renders through the real firmware pipeline.
- Frame pacing is stable enough for interactive navigation.

## Phase 9: audio

### Tasks

- Compile upstream Cell audio modules and mixer.
- Implement an RPCS3 audio backend using AudioUnit/AVAudioSession.
- Support sample-rate conversion, channel layouts, buffering, pause/resume, route changes, interruptions, and Bluetooth latency.
- Keep guest timing controlled by upstream audio behavior.

### Exit criteria

- Homebrew audio tests produce correct output.
- XMB sounds play without repeated underruns.
- Foreground/background transitions recover cleanly.

## Phase 10: input

### Tasks

- Implement an RPCS3 pad backend using GameController.
- Map DualShock buttons, sticks, triggers, motion, touchpad substitutes, and controller connection changes.
- Provide a UIKit touch overlay feeding the same upstream pad state.
- Keep host navigation input separate from guest input when appropriate.

### Exit criteria

- XMB navigation works with a physical controller and touch overlay.
- Per-title pad configuration persists through upstream config.

## Phase 11: host game list parity

### Tasks

- Replace the custom scanner as the authority with upstream game-list/cache data where practical.
- Mirror desktop RPCS3 categories and status fields that make sense on iOS.
- Use upstream metadata, compatibility data, patches, custom configuration, icons, and boot history.
- Add host actions for Boot, Boot with custom config, Manage Game Data, Remove HDD Game, Install Package, Add Game, Mount Disc, and Boot VSH/XMB.

### Exit criteria

- The host list and emulator core agree on title paths, serials, categories, and configuration.
- A title installed while the app is running appears without rebuilding the app database manually.

## Phase 12: performance and optional JIT

### Interpreter baseline

The first complete port must work without dynamic code generation, even if slowly.

### JIT path

Tasks:

- Audit iOS executable-memory restrictions.
- Support JIT only where platform policy and entitlements permit it.
- Evaluate upstream LLVM PPU and SPU recompilers on arm64.
- Fall back to interpreters automatically.

### Exit criteria

- Correctness does not depend on JIT.
- JIT availability is reported honestly per device/build.

## Phase 13: lifecycle, reliability, and mobile constraints

Tasks:

- Suspend or pause safely when backgrounded.
- Save state only if upstream support is safe for the active mode.
- Handle thermal pressure and memory warnings.
- Add crash-safe logs and session recovery.
- Prevent partial PKG/firmware installs.
- Add watchdog-safe long operations and progress reporting.

Exit criteria:

- Repeated boot/stop cycles do not leak emulator threads or VM mappings.
- Interrupted installs recover safely.

## Build-system plan

### Upstream pinning

- Pin a specific upstream commit in a machine-readable file.
- Update intentionally through a dedicated script and reviewable patch set.
- Record the commit in every IPA artifact.

### CMake

- Build inside upstream's dependency and generated-header graph.
- Add an `RPCS3_IOS` platform option rather than bypassing the project.
- Disable unsupported targets individually.
- Compile direct upstream sources into `rpcs3_core_ios`.
- Compile iOS backend sources into the same dependency graph.

### Dependencies

Each upstream dependency must be classified:

- Reuse unchanged.
- Build for arm64 iOS.
- Replace with Apple framework backend.
- Disable because it is GUI-only or desktop-only.
- Patch minimally for iOS.

Expected work includes LLVM, zlib, zstd, libpng, libjpeg, ffmpeg-related media paths, crypto, audio, networking, and shader/compiler dependencies. Dependency choices must remain license-compatible and reproducible.

## Bridge API target

The host bridge should expose concepts, not emulator internals:

```c
initialize(data_root)
install_firmware(pup_path, progress_callback)
install_package(pkg_path, progress_callback)
add_game(path)
mount_disc(path, optional_key)
refresh_game_list()
list_games()
boot_game(title_or_path)
boot_vsh()
pause()
resume()
stop()
set_pad_state(port, state)
attach_metal_surface(surface_descriptor)
set_audio_session_state(state)
read_diagnostics()
read_logs()
```

No bridge function should bypass upstream loaders or invent success.

## CI stages

1. Build upstream dependency graph for arm64 iOS.
2. Compile direct upstream core source manifest.
3. Verify required upstream symbols in the archive.
4. Generate and build the UIKit app.
5. Run host-side parser and installer tests.
6. Run device-compatible core self-tests.
7. Package unsigned IPA.
8. Upload source manifest, pinned commit, patches, symbols, logs, and IPA.
9. Publish pending/success/failure commit status with the exact run URL.

## Required test ladder

### Tier 1: build and platform

- Core initializes.
- VM, threads, VFS, Metal device, and audio session initialize.

### Tier 2: loaders

- ELF, SELF, PRX, SFO, PKG, PUP, and disc metadata tests.

### Tier 3: execution

- PPU homebrew tests.
- SPU tests.
- LV2 syscall tests.
- Module tests.

### Tier 4: graphics/audio/input

- RSX render tests.
- Audio tests.
- Pad tests.

### Tier 5: system software

- Firmware installation.
- VSH boot.
- XMB frame output.
- XMB input and audio.

### Tier 6: shared title environment

- Install PKG from host UI.
- Verify host game-list entry.
- Boot XMB.
- Verify the same title appears in XMB.
- Launch from host list and from XMB through the same data root.

## Definition of done

The project may call itself a real RPCS3 iOS port only when all of the following are true:

- Most emulator behavior is provided by directly compiled upstream RPCS3 implementation files.
- Upstream `Emu.System` owns boot, pause, resume, and stop.
- Upstream PPU and SPU execution paths are active.
- Upstream LV2 and module implementations are active.
- Upstream VFS owns PS3 virtual devices.
- Firmware installs through upstream-compatible logic.
- **Boot VSH/XMB** reaches the real PS3 firmware dashboard.
- XMB is rendered through upstream RSX plus the iOS Metal backend.
- XMB audio uses upstream Cell audio plus the iOS audio backend.
- Host game list and XMB share the same installed-title environment.
- PKG, folder, and ISO content use upstream install/mount/boot paths.
- CI proves the upstream source manifest and successful physical-device IPA build.

Until those conditions are met, releases must be labeled as an experimental frontend or partial port, not full RPCS3.

## Immediate next implementation sequence

1. Add the pinned upstream revision manifest.
2. Replace the early-return core-only overlay with an iOS platform option inside the upstream graph.
3. Build upstream utility, logging, configuration, VM, VFS, loader, and `Emu.System` dependency closures.
4. Remove hard-coded PPU/SPU availability from custom scaffolds.
5. Initialize an actual upstream emulator object from the bridge.
6. Add upstream firmware installation.
7. Add the host **Boot VSH/XMB** command even while it reports missing runtime dependencies honestly.
8. Bring up PPU interpreter and LV2 foundations.
9. Bring up SPU interpreter.
10. Bring up RSX core and Metal presentation.
11. Bring up audio and input.
12. Validate real firmware-backed XMB on a physical device.
