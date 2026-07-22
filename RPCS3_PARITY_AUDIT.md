# RPCS3 iOS — Upstream Feature Parity Audit

## Verdict

The current project is **not a full RPCS3 application port**.

It has two very different levels of progress:

1. **Emulator source integration:** the build now links a pinned upstream `rpcs3_emu` graph into `RPCS3UpstreamRuntime.framework` and exposes a narrow lifecycle bridge.
2. **Usable RPCS3 product parity:** the iOS application exposes only a small custom shell. Most desktop RPCS3 frontend behavior, platform backends, device validation, management tools, and end-to-end title execution remain missing or unproven.

A copied Qt Designer `.ui` file is not an implemented RPCS3 feature. A linked function is not a working feature until it is exercised on a physical iOS device with real output and lifecycle evidence.

## Classification vocabulary

| Classification | Meaning |
| --- | --- |
| **Linked upstream** | The pinned upstream implementation is part of the framework link graph. |
| **Bridged** | A narrow C API calls the upstream implementation. |
| **Host placeholder** | The iOS app displays a form, stages a file, scans a directory, or reports pending without the real upstream behavior. |
| **Null backend** | RPCS3 receives an intentionally non-functional backend. |
| **Device-unproven** | Source exists and may compile, but no physical-device result proves it works. |
| **Playable** | A physical device completes the workflow with rendering, input, stable execution, and usable output. |

## What is genuinely present

- A pinned upstream RPCS3 checkout and the real upstream `rpcs3_emu` target.
- A framework target that links the upstream emulator graph into the IPA.
- Calls into upstream `Emu.Init()`, `Emu.BootGame()`, pause, resume, stop, and state queries.
- Upstream static PPU and SPU interpreter selection.
- Upstream PKG extraction through `package_reader::extract_data()`.
- A native iOS `UIView`/`CAMetalLayer` surface and an attempted upstream `VKGSRender` path through MoltenVK.
- A shared sandbox data root intended to contain `dev_hdd0`, `dev_flash`, configuration, caches, and imports.

These are important foundations, but they do not equal a usable RPCS3 port.

## Frontend parity audit

### Upstream desktop RPCS3

Upstream builds a real `rpcs3_ui` target containing the C++ implementations for the main window, settings, game list, compatibility data, input setup, package installation, firmware installation, save data, trophies, patches, debugger, logs, VFS tools, users, screenshots, dialogs, render frame, and many other tools.

### Current iOS Qt target

The current `RPCS3QtIOS` target compiles the custom files:

- `QtApp/main.cpp`
- `QtApp/RPCS3QtMainWindow.cpp`
- `QtApp/RPCS3QtMainWindow.h`
- generated `.ui` wrappers/resources

It does **not** compile upstream `rpcs3_ui`, upstream `main_window.cpp`, upstream `gui_application.cpp`, upstream `game_list_frame.cpp`, upstream `settings_dialog.cpp`, or the other desktop frontend implementation classes.

### Consequence

The app visually resembles RPCS3 because it loads upstream `.ui` documents, but most widgets have no real RPCS3 controller/model behind them.

Current behavior includes:

- loading raw `.ui` forms with `QUiLoader`;
- routing unsupported actions to `showPending()`;
- copying selected files into sandbox folders;
- scanning directories into a basic `QListWidget`;
- directly searching for `EBOOT.BIN` or `vsh.self`;
- showing bridge diagnostic message boxes.

That is a custom launcher shell, not the desktop RPCS3 frontend ported to iOS.

## Core and runtime parity matrix

| RPCS3 area | Upstream code linked? | iOS host/backend status | Physical-device proof | Honest status |
| --- | --- | --- | --- | --- |
| Emulator lifecycle | Yes | Narrow bridge | No complete lifecycle evidence | Device-unproven |
| PPU interpreter | Yes | Static interpreter selected | No executed title proof | Device-unproven |
| SPU interpreter | Yes | Static interpreter selected | No SPU workload proof | Device-unproven |
| LV2 kernel/syscalls | Present in upstream graph | No complete iOS validation | None | Device-unproven |
| SELF/PRX/module loading | Present in upstream graph | Boot path bridge only | None | Device-unproven |
| Virtual memory | Present upstream | iOS mapping assumptions not validated | None | Major blocker |
| Threading/TLS/atomics | Present upstream | iOS behavior not validated | None | Major blocker |
| VFS | Present upstream | Shared root patch exists | No full mount proof | Partial |
| PKG install | Upstream installer called | Auto-boot wrapper exists | No real device install result | Device-unproven |
| Firmware PUP install | Header declarations added | No complete bridge/host workflow proven | None | Missing/incomplete |
| VSH/XMB boot | Upstream core contains support | Host searches for `vsh.self` directly | None | Placeholder |
| ISO/disc mount | Upstream core contains support | Current host stages/copies ISO/disc files | None | Placeholder |
| RAP/RIF/licenses | Upstream paths exist | Current host stages files into `keys` | None | Placeholder |
| Game list/database | Upstream frontend has full implementation | Basic directory scan into `QListWidget` | N/A | Replacement placeholder |
| Per-title config | Upstream implementation exists | Raw settings `.ui` only | N/A | Missing |
| Global config UI | Upstream implementation exists | Raw settings `.ui` only | N/A | Missing |
| Vulkan RSX | Upstream code linked with MoltenVK attempt | `CAMetalLayer` host exists | No rendered frame proof | Device-unproven |
| Native Metal RSX | No | No backend | None | Missing |
| Audio | Upstream mixer/modules linked | `NullAudioBackend` | None | Missing |
| Game controller | Upstream pad thread linked | Null/default pad path; no GameController backend | None | Missing |
| Touch controls | No guest input bridge | No touch overlay | None | Missing |
| Keyboard/mouse | Upstream interfaces linked | Null handlers | None | Missing |
| Camera/music | Upstream interfaces linked | Null handlers | None | Missing |
| Message dialogs | Upstream interfaces linked | callbacks return empty objects | None | Missing |
| OSK | Upstream interfaces linked | callback returns empty | None | Missing |
| Save data dialogs | Upstream interfaces linked | callback returns empty | None | Missing |
| Trophy notifications | Upstream interfaces linked | callback returns empty | None | Missing |
| Images/fonts/localization | Upstream interfaces linked | callbacks empty or false | None | Missing |
| Networking | LV2 networking source linked | no iOS/PKGi device validation | None | Device-unproven |
| RPCN | Upstream frontend/service exists | no functional host integration | None | Missing |
| Firmware/version readiness | Upstream can inspect firmware state | no completed one-time onboarding gate | None | Missing |
| User accounts | Upstream implementation exists | hard-coded user `00000001` | None | Partial placeholder |
| Savedata manager | Upstream frontend exists | raw form or pending | N/A | Missing |
| Trophy manager | Upstream frontend exists | pending | N/A | Missing |
| Patch manager | Upstream frontend exists | raw form without implementation | N/A | Missing |
| Cheat manager | Upstream frontend exists | pending | N/A | Missing |
| Shader/cache management | Upstream implementation exists | no functional host UI/device proof | None | Missing |
| Debugger | Upstream frontend exists | not compiled into iOS target | N/A | Missing |
| Log viewer | Upstream frontend exists | custom diagnostics message only | N/A | Replacement placeholder |
| Savestates | Upstream core/frontend exist | files are staged only | None | Placeholder |
| Background/foreground recovery | Platform-specific requirement | not implemented/proven | None | Missing |
| Memory pressure handling | Platform-specific requirement | not implemented/proven | None | Missing |
| Crash reporting/guest logs | Upstream logging exists | no complete export/support flow | None | Partial |

## Empty and Null host callbacks currently blocking real applications

The bridge currently supplies Null or empty implementations for major host services, including:

- audio output and audio device enumeration;
- keyboard, mouse, camera, and music handlers;
- message, OSK, save, send-message, receive-message, and trophy dialogs;
- localized strings/settings;
- image decoding/scaling and font directories;
- package-install callbacks invoked from guest/UI paths;
- breakpoints, display sleep control, microphone permission handling, video source, and game mode.

A title can fail even when PPU/LV2 execution begins because these host contracts are part of RPCS3’s runtime environment.

## Current firmware problem

The newest source declares:

- `rpcs3_ios_upstream_install_firmware()`
- `rpcs3_ios_upstream_firmware_ready()`
- `rpcs3_ios_upstream_firmware_version()`

The current runtime bridge and Qt host do not yet provide a complete, verified implementation of that API. The generic **Install Firmware** action still routes through staging behavior in `RPCS3QtMainWindow.cpp` unless a dedicated real handler overrides it.

This is not firmware installation until the user-provided `PS3UPDAT.PUP` is validated and extracted through upstream PUP/SCE/TAR code into the shared `dev_flash`, firmware readiness is checked, and boot is blocked when required files are missing.

## First playable PKG critical path

The first milestone is not “port every desktop tool.” It is the smallest honest path that can make one legal PKG usable:

1. **Firmware gate**
   - real upstream PUP extraction;
   - progress/error reporting;
   - verify `dev_flash`, version, modules and `vsh.self`;
   - persist one-time installed state.

2. **Device runtime gate**
   - prove VM reservation/mapping;
   - prove thread/TLS/atomic wait behavior;
   - prove `Emu.Init()` and clean shutdown on a physical iPhone;
   - capture complete RPCS3 logs.

3. **PKG execution gate**
   - install a small legal homebrew PKG first;
   - prove `Emu.BootGame()` reaches PPU/LV2 main loop;
   - then test PKGi.

4. **Visible interaction gate**
   - prove `VKGSRender` creates a MoltenVK swapchain on the iOS `CAMetalLayer`;
   - produce a real frame;
   - implement at least one GameController or touch input path.

5. **PKGi service gate**
   - validate DNS/TLS/socket behavior;
   - provide working OSK/dialog behavior where needed;
   - provide audio output or explicitly document it as the next blocker.

## Full product parity after the first playable PKG

After the vertical slice works, parity work must continue in this order:

1. Real game list, metadata, compatibility, per-title config and caches.
2. AudioUnit/AVAudioSession, GameController and touch input.
3. VSH/XMB, users, licenses, saves, trophies and content management.
4. ISO/disc mounting, savestates, patches, cheats and management utilities.
5. Debugger/developer tools, performance tuning, lifecycle recovery and native Metal evaluation.

## Rules preventing false completion

- Do not mark a feature implemented because its upstream `.ui` file is bundled.
- Do not mark a feature implemented because an API is declared in a header.
- Do not mark a feature implemented because a static library contains its object files.
- Do not mark rendering implemented until a physical device presents a real RSX frame.
- Do not mark PPU/SPU/LV2 execution implemented until a guest workload advances and logs prove the upstream paths.
- Do not mark firmware installed until required `dev_flash` files and a firmware version are validated.
- Do not mark PKG playable until the title renders, accepts input, remains responsive and completes its core function.
- Do not call the app full RPCS3 until the upstream product behaviors used by ordinary users are functional or explicitly replaced by equivalent iOS implementations.

## Current honest label

**RPCS3 iOS upstream-core integration prototype with a custom Qt launcher shell.**

It is not yet a playable PS3 emulator and is not yet a port of the complete RPCS3 application.
