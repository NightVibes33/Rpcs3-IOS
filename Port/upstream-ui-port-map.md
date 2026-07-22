# RPCS3 UI port map for iOS

The iOS target is the real RPCS3 application workflow adapted for touch. The upstream `rpcs3/rpcs3qt` implementation remains the behavioral and visual source of truth. UIKit is the platform view layer; this is not a separate simplified launcher.

## Upstream-to-iOS mapping

| Upstream RPCS3 UI | iOS surface | Port requirement |
| --- | --- | --- |
| `main_window` | root split/navigation controller | Preserve File, Emulation, Configuration, Manage, Utilities and Help actions as touch menus/toolbars. |
| `game_list_frame` / game grid | primary game library | Preserve list/grid modes, icons, title, serial, firmware, category, compatibility, play time and contextual boot/configure actions. |
| `settings_dialog` + `emu_settings` | settings navigation stack | Preserve CPU, GPU, Audio, Input/Output, System, Network and Advanced pages using native controls bound to the same config keys. |
| firmware install action | firmware importer/progress screen | Import official PS3UPDAT.PUP into the sandbox and call the upstream installer path. |
| package install action | PKG/RAP importer/progress screen | Support package queues, progress, cancellation and user-supplied license files. |
| pad settings | controller settings screen | Map GameController devices and touch overlays to RPCS3 pad handlers. |
| trophy manager | trophy browser | Preserve title grouping, unlock state, icons and details. |
| log frame | log viewer/share sheet | Stream RPCS3 log channels and export logs from the sandbox. |
| debugger/tools | advanced tools screens | Port only after the execution core is functional; keep data and command semantics compatible. |

## Rules

1. Do not invent a parallel app model when an upstream RPCS3 model or configuration key exists.
2. Reuse upstream parsers, game metadata, compatibility data structures, config serialization and core commands wherever they can compile on iOS.
3. Replace Qt widgets and desktop-only window management with UIKit views while preserving labels, grouping, defaults and action semantics.
4. The IPA must open directly into the RPCS3 game list. Diagnostics belong under Utilities, not on the launch screen.
5. Firmware, keys, RAP/RIF files and games are imported by the user and stored only in the app container.
6. Encrypted SELF support is an implementation task, not a permanent block. Integrate upstream key-vault and decryption code once its dependency slice compiles for arm64 iPhoneOS.

## Port order

1. Main window structure and game list.
2. Game discovery and metadata using upstream loaders.
3. Settings pages backed by RPCS3 config keys.
4. Firmware and PKG/RAP installation flows.
5. Boot lifecycle and renderer surface.
6. Controller, audio and touch input.
7. Trophy, logs and utilities.
8. Remaining desktop tools where they make sense on iOS.
