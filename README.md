# RPCS3 iOS

[![Build iOS 26 Unsigned IPA](https://github.com/NightVibes33/Rpcs3-IOS/actions/workflows/build-ios.yml/badge.svg?branch=main)](https://github.com/NightVibes33/Rpcs3-IOS/actions/workflows/build-ios.yml)
[![Probe real upstream RPCS3 graph](https://github.com/NightVibes33/Rpcs3-IOS/actions/workflows/upstream-graph-probe.yml/badge.svg?branch=main)](https://github.com/NightVibes33/Rpcs3-IOS/actions/workflows/upstream-graph-probe.yml)

Experimental native iOS 26 porting project for RPCS3. The repository converts RPCS3's desktop Qt interface into UIKit, builds an arm64 iPhone/iPad application, and continuously probes the real upstream RPCS3 emulator graph for iOS portability blockers.

> [!WARNING]
> This is **not yet a playable PS3 emulator**. The current IPA builds and launches, but full PPU/SPU execution, PS3 syscalls, RSX rendering, game boot, firmware installation, and VSH/XMB execution are not complete. No game compatibility is claimed.

Implementation progress is tracked in [`ROADMAP_STATUS.md`](ROADMAP_STATUS.md) against the exit criteria in [`REAL_RPCS3_IOS_BUILD_PLAN.md`](REAL_RPCS3_IOS_BUILD_PLAN.md).

## Current status

| Area | Status | What that means |
| --- | --- | --- |
| iOS application | Building | GitHub Actions produces an unsigned arm64 IPA for physical devices with an iOS 26.0 deployment target. |
| RPCS3 interface conversion | In progress | RPCS3's Qt `.ui` hierarchy is exported into JSON and rendered with UIKit, including menus, submenus, tabs, nested tabs, stacked pages, toolboxes, and dock-style panels. |
| Menu actions | Partially connected | File pickers and routes exist for games, ISO, SELF/ELF, PKG, PUP, RAP/EDAT, savestates, firmware paths, configuration pages, logs, and utility screens. Unsupported actions remain visible but do not pretend to work. |
| iOS core bridge | Early bring-up | The linked archive initializes, detects and validates PS3 ELF/SELF containers, builds load plans, extracts supported plain SELF content, and exposes stop/diagnostic entry points. It does not execute guest PPU or SPU instructions yet. |
| Real upstream RPCS3 graph | Active compile probe | CI clones pinned RPCS3 `v0.0.40`, applies narrow iOS portability patches, and attempts to compile the real `rpcs3_emu` target so each genuine platform blocker can be fixed in order. |
| Game compatibility | None | A successful IPA build does not mean commercial games, homebrew, firmware, or XMB currently run. |

## What is already implemented

- Native Objective-C++ UIKit application for iPhone and iPad, including tab-bar and split-view layouts.
- Runtime-generated RPCS3 menu structure based on upstream `main_window.ui`, preserving upstream QAction identifiers and ordering.
- A renderer for extracted RPCS3 settings dialogs, nested tab widgets, stacked pages, toolboxes, common controls, tables, trees, lists, and dock panels.
- Separate storage routes for imported games, ISO images, firmware, packages, licenses, savestates, discs, and `dev_flash` data.
- Reproducible GitHub Actions workflows for unsigned IPA packaging, symbol validation, UI-model validation, and the real upstream `rpcs3_emu` compile probe.

## Important limitations

### Boot Game and Boot ISO

The UIKit menu and file-selection flow are present, but ISO mounting, disc decryption, executable discovery, and the complete RPCS3 boot pipeline are not connected to a functioning guest runtime.

### Boot SELF/ELF

Selected SELF/ELF files are submitted to the iOS core bridge. The bridge can inspect and prepare supported files, but it does not yet execute their PPU/SPU code.

### Boot VSH/XMB

The app exposes RPCS3's upstream **Boot VSH/XMB** action and searches the application data tree for `dev_flash/vsh/module/vsh.self`. Finding that file is not enough: VSH cannot run until firmware installation, SELF loading, PPU/SPU execution, syscalls, graphics, audio, input, and supporting services are implemented.

### PKG, PUP, RAP, and EDAT

The current interface imports these files into distinct RPCS3 data locations. Full RPCS3 package installation, firmware installation, license handling, and content registration are still pending.

### Graphics, audio, input, and JIT

The real upstream graph is being ported dependency by dependency. UIKit replaces Qt in the shipping application, but an iOS-safe RSX renderer, complete AudioUnit integration, controller input runtime, and an allowed executable-memory strategy are not finished.

## Architecture

```text
RPCS3 upstream v0.0.40
        |
        +-- Qt .ui exporter -----------------> RPCS3QtUIModel.json
        |                                           |
        |                                           +--> UIKit menus and dialogs
        |
        +-- iOS portability overlays --------> real rpcs3_emu compile probe
        |
        +-- upstream-derived loader pieces --> librpcs3-ios-core.a
                                                    |
                                                    +--> RPCS3CoreBridge
                                                            |
                                                            +--> iOS application
```

Desktop Qt is not shipped in the IPA. The upstream interface structure is treated as the source of truth and converted to UIKit. RPCS3 tools that are constructed entirely in C++ rather than `.ui` files require separate native ports and are clearly marked when unavailable.

## Build the unsigned IPA

1. Open the repository's **Actions** tab.
2. Run **Build iOS 26 Unsigned IPA**, or use an artifact from a successful `main` build.
3. Download the `RPCS3-iOS-iOS26-unsigned` artifact.
4. Sign the IPA with your own valid Apple development credentials and provisioning profile.
5. Install it on a compatible arm64 iPhone or iPad running the supported iOS version.

The workflow uses a GitHub-hosted macOS 26 runner, selects an Xcode installation with the iOS 26 SDK, builds the upstream-derived static archive, generates the Xcode project with XcodeGen, validates required symbols, and packages the unsigned IPA.

## Real upstream graph probe

The `upstream-graph-probe.yml` workflow is intentionally separate from the shipping IPA workflow. It:

1. Clones the pinned upstream RPCS3 revision and its submodules.
2. Exports every upstream `rpcs3qt/*.ui` document used by the UIKit conversion.
3. Applies explicit iOS portability patches for dependencies such as libusb, AsmJit, Cubeb, and FFmpeg graph configuration.
4. Configures RPCS3 for arm64 iOS with desktop Qt and LLVM JIT disabled for the interpreter-first bring-up stage.
5. Attempts to compile the real `rpcs3_emu` target and uploads the next concrete compiler failure as evidence.

A green configuration step alone is not treated as completion. The workflow records the actual `rpcs3_emu` build exit status and separate Phase 1 evidence for upstream `Emu/System.cpp`.

## Next engineering milestones

1. Replace loader-only boot handling with the real RPCS3 `Emu.System` lifecycle.
2. Bring up interpreter-based PPU and SPU execution with the required memory and syscall layers.
3. Implement an iOS RSX presentation path using Metal-compatible rendering infrastructure.
4. Connect AudioUnit output, controller input, firmware/package installation, and persistent configuration.
5. Complete VSH/XMB startup and then validate homebrew before making any game-compatibility claims.

## Repository map

| Path | Purpose |
| --- | --- |
| `App/` | UIKit application, converted upstream menus, dialogs, action routing, library, and management UI. |
| `CoreBridge/` | C/Objective-C++ boundary between the iOS application and the upstream-derived core archive. |
| `Port/` | iOS-specific core sources and portability shims used by the shipping archive. |
| `scripts/` | Upstream cloning, UI export, overlays, validation, packaging, and graph-probe automation. |
| `ROADMAP_STATUS.md` | Live phase-by-phase implementation status and evidence gates. |
| `REAL_RPCS3_IOS_BUILD_PLAN.md` | Detailed engineering plan and subsystem bring-up order. |

## Legal and project notice

This is an experimental, unofficial porting project. It is not affiliated with Sony Interactive Entertainment or the official RPCS3 project.

No PlayStation firmware, games, keys, licenses, copyrighted Sony files, or commercial content are included. Users are responsible for supplying and legally using their own content. Upstream RPCS3 code and third-party dependencies remain subject to their respective licenses.
