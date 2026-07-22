# RPCS3 iOS

[![Build iOS 26 Unsigned IPA](https://github.com/NightVibes33/Rpcs3-IOS/actions/workflows/build-ios.yml/badge.svg?branch=main)](https://github.com/NightVibes33/Rpcs3-IOS/actions/workflows/build-ios.yml)
[![Probe real upstream RPCS3 graph](https://github.com/NightVibes33/Rpcs3-IOS/actions/workflows/upstream-graph-probe.yml/badge.svg?branch=main)](https://github.com/NightVibes33/Rpcs3-IOS/actions/workflows/upstream-graph-probe.yml)

Experimental arm64 iPhone/iPad porting project for RPCS3.

> [!WARNING]
> This is **not yet a playable PS3 emulator or a complete RPCS3 application port**. The current project links a real pinned upstream emulator graph, but the iOS host, platform backends and physical-device execution path are incomplete. No game or application compatibility is claimed.

Read the detailed [RPCS3 feature parity audit](RPCS3_PARITY_AUDIT.md) before treating any menu, symbol or build result as a working feature.

## Current architecture

```text
Pinned upstream RPCS3 v0.0.40
        |
        +-- rpcs3_emu and dependencies
        |          |
        |          +--> RPCS3UpstreamRuntime.framework
        |                       |
        |                       +--> narrow lifecycle/install/render C bridge
        |
        +-- upstream Qt Designer .ui files
                                   |
                                   +--> custom Qt iOS launcher shell
```

The shipping iOS target is a **custom Qt Widgets shell**. It bundles upstream `.ui` documents for visual structure, but it does not compile the upstream desktop `rpcs3_ui` target or most of the C++ classes that make those windows and tools functional.

## What is genuinely integrated in source

- A pinned upstream RPCS3 checkout and real `rpcs3_emu` build graph.
- `RPCS3UpstreamRuntime.framework` embedded in the IPA.
- Narrow bridge calls for upstream `Emu.Init()`, `Emu.BootGame()`, pause, resume, stop and state.
- Upstream static PPU and SPU interpreter selection.
- Upstream PKG extraction through `package_reader::extract_data()`.
- A shared sandbox data root for RPCS3 virtual storage.
- An iOS `UIView`/`CAMetalLayer` host and attempted upstream Vulkan renderer path through MoltenVK.

These items are **source integration**, not proof that a PS3 title runs on an iPhone.

## What the current app actually does

- Loads RPCS3's upstream `main_window.ui` into a custom `QMainWindow`.
- Displays a simple directory-scanned game list.
- Copies imported content into sandbox folders.
- Calls the narrow upstream bridge for the dedicated PKG install/boot path.
- Shows diagnostics and explicit pending messages for unavailable actions.

Most other actions either load an unconnected `.ui` form, stage a file, open a website, or report that the upstream C++ implementation is not linked into the host.

## Major missing or unproven systems

| Area | Honest status |
| --- | --- |
| Physical-device `Emu.Init()` and clean shutdown | Unproven |
| Guest PPU/SPU/LV2 execution | Unproven |
| Real firmware PUP installation and readiness gate | Incomplete |
| VSH/XMB boot | Placeholder/unproven |
| Vulkan/MoltenVK RSX frame presentation | Source path exists; no device frame proof |
| Native Metal RSX backend | Missing |
| Audio output | Null backend |
| GameController and touch guest input | Missing |
| ISO/disc mounting | Staging placeholder |
| RAP/RIF/license handling | Staging placeholder |
| Upstream game list, metadata and compatibility | Not compiled into host |
| Functional settings and per-title configuration | Raw `.ui` forms only |
| Saves, trophies, users, patches, cheats and management tools | Missing |
| OSK, message and save dialogs | Empty callbacks |
| PKGi networking | Unproven |
| Backgrounding, memory pressure and lifecycle recovery | Missing |

## First playable PKG target

The immediate milestone is one legal, user-provided PKG that can be installed, booted, rendered and controlled on a physical iPhone.

Required gates:

1. Install and validate the user's official `PS3UPDAT.PUP` into the shared `dev_flash` tree.
2. Prove RPCS3 virtual memory, worker threads and `Emu.Init()` on device.
3. Install a small legal homebrew PKG and prove the upstream PPU/LV2 main loop runs.
4. Present a real RSX frame through Vulkan/MoltenVK and the iOS `CAMetalLayer`.
5. Add GameController or touch input, then validate PKGi sockets/TLS/DNS behavior.

PKGi is a strong later test because it exercises firmware modules, LV2, RSX, input, virtual storage and networking. A smaller homebrew PKG should be used first to isolate core boot and rendering failures.

## Important truth rules

- A bundled `.ui` file is not a functional RPCS3 feature.
- A header declaration is not an implemented feature.
- A linked upstream object is not a device-tested feature.
- A green IPA build is not proof of guest execution.
- Rendering is not complete until a physical device presents a real RSX frame.
- A PKG is not playable until it renders, accepts input and remains responsive.

## Build the unsigned IPA

1. Open the repository's **Actions** tab.
2. Run **Build RPCS3 Qt iOS Unsigned IPA**.
3. Download the `RPCS3-Qt-iOS26-unsigned` artifact from a successful run.
4. Sign the IPA with your own valid Apple development credentials and provisioning profile.
5. Install it on a supported physical arm64 iPhone or iPad.

The build workflow must validate the embedded upstream runtime, bridge symbols, architecture, Qt app bundle and MoltenVK linkage. Build success still does not establish playability.

## Engineering documents

- [`RPCS3_PARITY_AUDIT.md`](RPCS3_PARITY_AUDIT.md) — current upstream/product parity truth table.
- [`ROADMAP_STATUS.md`](ROADMAP_STATUS.md) — evidence-based phase status.
- [`REAL_RPCS3_IOS_BUILD_PLAN.md`](REAL_RPCS3_IOS_BUILD_PLAN.md) — complete subsystem bring-up plan.

## Repository map

| Path | Purpose |
| --- | --- |
| `QtApp/` | Current custom Qt iOS launcher shell and native render host. |
| `App/` | Earlier UIKit frontend experiments; not the current Qt product target. |
| `CoreBridge/` | Stable host/runtime boundary and diagnostics. |
| `Port/iOS/` | iOS platform implementations such as the `CAMetalLayer` frame host. |
| `Port/` | Platform and core-support code used by the shipping archive. |
| `scripts/` | Upstream checkout, overlays, dependencies, validation and IPA packaging. |

## Legal and project notice

This is an experimental, unofficial porting project. It is not affiliated with Sony Interactive Entertainment or the official RPCS3 project.

No PlayStation firmware, games, keys, licenses, copyrighted Sony files or commercial content are included. Users are responsible for supplying and legally using their own content. Upstream RPCS3 code and third-party dependencies remain subject to their respective licenses.
