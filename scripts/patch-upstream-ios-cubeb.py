#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import json
import subprocess
import tempfile
import urllib.request
from pathlib import Path

# Mozilla vendors the same Cubeb revision used by pinned RPCS3 and applies this
# complete iOS AudioUnit compile/runtime patch. Address the immutable Git blob
# directly so later gecko-dev branch changes cannot alter the graph build.
PATCH_BLOB_SHA = "465ae0f98a159751136c62c6d5ba49c5f983bd65"
PATCH_API_URL = (
    "https://api.github.com/repos/mozilla/gecko-dev/git/blobs/" + PATCH_BLOB_SHA
)


def download_patch() -> bytes:
    request = urllib.request.Request(
        PATCH_API_URL,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "RPCS3-iOS-upstream-graph",
        },
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        payload = json.load(response)

    if payload.get("sha") != PATCH_BLOB_SHA or payload.get("encoding") != "base64":
        raise SystemExit("Mozilla Cubeb patch blob response failed verification")

    content = base64.b64decode(payload["content"], validate=False)
    required = (
        b"diff --git a/src/cubeb_audiounit.cpp",
        b"#if TARGET_OS_IPHONE",
        b"audiounit_get_preferred_sample_rate",
        b"audiounit_register_device_collection_changed",
    )
    for marker in required:
        if marker not in content:
            raise SystemExit(f"Mozilla Cubeb patch is missing marker: {marker!r}")
    return content


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Apply Mozilla's complete AudioUnit iOS backport to RPCS3's pinned Cubeb submodule"
    )
    parser.add_argument("upstream_root", type=Path)
    args = parser.parse_args()

    cubeb_root = args.upstream_root / "3rdparty/cubeb/cubeb"
    source = cubeb_root / "src/cubeb_audiounit.cpp"
    if not source.is_file():
        raise SystemExit(f"Pinned Cubeb AudioUnit source was not found: {source}")

    patch = download_patch()
    with tempfile.NamedTemporaryFile(prefix="cubeb-ios-", suffix=".patch") as handle:
        handle.write(patch)
        handle.flush()
        subprocess.run(
            ["git", "-C", str(cubeb_root), "apply", "--check", handle.name],
            check=True,
        )
        subprocess.run(
            ["git", "-C", str(cubeb_root), "apply", handle.name],
            check=True,
        )

    updated = source.read_text(encoding="utf-8")
    verification_markers = (
        "const UInt32 kAudioObjectUnknown = 0;",
        "#if TARGET_OS_IPHONE\n  *rate = 44100;",
        "audiounit_register_device_collection_changed",
    )
    for marker in verification_markers:
        if marker not in updated:
            raise SystemExit(f"Applied Cubeb iOS backport failed verification: {marker}")

    print(
        "Applied Mozilla Cubeb iOS AudioUnit backport "
        f"blob {PATCH_BLOB_SHA} to {source}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
