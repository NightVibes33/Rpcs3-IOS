# RPCS3 iOS — official XITRIX build

This repository now points to the **real iOS app published by XITRIX**. It does not create a replacement frontend or pretend a core library is an app.

## Install the app

[Download the official XITRIX v0.10 IPA](https://github.com/XITRIX/RPCS3-iOS-Releases/releases/download/v0.10/RPCS3.ipa) · [Release notes](https://github.com/XITRIX/RPCS3-iOS-Releases/releases/tag/v0.10)

Import `RPCS3.ipa` with SideStore or AltStore. Follow the official [XITRIX installation instructions](https://github.com/XITRIX/RPCS3-iOS-Releases) for launch/JIT setup. Supply your own legally obtained PS3 firmware and games.

XITRIX v0.10 is a preview release. The upstream release currently targets iOS 17.4 or newer and recommends at least 6 GB RAM.

## Why the NeoStation artifact failed to import

The artifact from [NeoStation workflow run 36343065903](https://github.com/TarbleFR/neostation-ios/actions/runs/36343065903) was `RPCS3Core-7ecc36bdb9f1206aedff02cb15aa23341c242f91.zip`. Its contents are the RPCS3 core dylib plus build metadata. It has no `Payload/*.app/Info.plist`, so it is not an IPA and SideStore correctly rejects it.

NeoStation is a separate frontend that embeds RPCS3 as one of its runtimes. It is optional; you do not need NeoStation to use the official XITRIX RPCS3 app.

## Verify and retrieve the exact upstream IPA from this repo

Run **Actions → Verify official XITRIX RPCS3 iOS IPA → Run workflow**. The workflow downloads XITRIX v0.10, checks the SHA-256 published by GitHub, validates the `Payload/*.app/Info.plist`, executable and embedded RPCS3 core, then uploads the original IPA unchanged as `RPCS3-XITRIX-v0.10-official-IPA`.

Official asset SHA-256:

```text
ba80e48ca9ee947a6b0ccbda05bc9af4cf190e1552e4aa550eb9d6ef143e1a91
```

The v0.10 release is published by [XITRIX](https://github.com/XITRIX/RPCS3-iOS-Releases). This repository does not claim authorship of the app or core.