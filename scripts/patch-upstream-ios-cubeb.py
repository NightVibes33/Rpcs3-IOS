#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import subprocess
import tempfile
import urllib.request
from pathlib import Path

# Mozilla vendors the same Cubeb revision used by pinned RPCS3 and applies this
# complete iOS AudioUnit compile/runtime patch. Download the public raw file,
# then verify its immutable Git blob SHA before applying it. This avoids the
# unauthenticated GitHub REST API rate limit that previously stopped CI.
PATCH_BLOB_SHA = "465ae0f98a159751136c62c6d5ba49c5f983bd65"
PATCH_RAW_URL = (
    "https://raw.githubusercontent.com/mozilla/gecko-dev/master/"
    "media/libcubeb/0003-audiounit-ios-compile-fixes.patch"
)


def git_blob_sha(content: bytes) -> str:
    header = f"blob {len(content)}\0".encode("ascii")
    return hashlib.sha1(header + content).hexdigest()


def download_patch() -> bytes:
    request = urllib.request.Request(
        PATCH_RAW_URL,
        headers={"User-Agent": "RPCS3-iOS-upstream-graph"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        content = response.read()

    actual_sha = git_blob_sha(content)
    if actual_sha != PATCH_BLOB_SHA:
        raise SystemExit(
            "Mozilla Cubeb patch blob verification failed: "
            f"expected {PATCH_BLOB_SHA}, received {actual_sha}"
        )

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


def patch_cmake_for_ios(cubeb_root: Path) -> None:
    cmake = cubeb_root / "CMakeLists.txt"
    text = cmake.read_text(encoding="utf-8")
    needle = '''check_include_files(AudioUnit/AudioUnit.h USE_AUDIOUNIT)
if(USE_AUDIOUNIT)
  target_sources(cubeb PRIVATE
    src/cubeb_audiounit.cpp
    src/cubeb_osx_run_loop.cpp)
  target_compile_definitions(cubeb PRIVATE USE_AUDIOUNIT)
  target_link_libraries(cubeb PRIVATE "-framework AudioUnit" "-framework CoreAudio" "-framework CoreServices")
  list(APPEND private_libs_flags "-framework AudioUnit" "-framework CoreAudio" "-framework CoreServices")
endif()
'''
    replacement = '''check_include_files(AudioUnit/AudioUnit.h USE_AUDIOUNIT)
if(USE_AUDIOUNIT)
  target_sources(cubeb PRIVATE
    src/cubeb_audiounit.cpp)
  target_compile_definitions(cubeb PRIVATE USE_AUDIOUNIT)

  if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    # iOS uses Cubeb's AudioUnit backend but does not expose the desktop
    # CoreAudio notification run loop or CoreServices framework.
    target_link_libraries(cubeb PRIVATE
      "-framework AudioUnit"
      "-framework CoreAudio"
      "-framework AudioToolbox")
    list(APPEND private_libs_flags
      "-framework AudioUnit"
      "-framework CoreAudio"
      "-framework AudioToolbox")
  else()
    target_sources(cubeb PRIVATE
      src/cubeb_osx_run_loop.cpp)
    target_link_libraries(cubeb PRIVATE
      "-framework AudioUnit"
      "-framework CoreAudio"
      "-framework CoreServices")
    list(APPEND private_libs_flags
      "-framework AudioUnit"
      "-framework CoreAudio"
      "-framework CoreServices")
  endif()
endif()
'''
    if needle not in text:
        raise SystemExit("Unable to locate Cubeb AudioUnit CMake source block")
    updated = text.replace(needle, replacement, 1)
    if 'if(CMAKE_SYSTEM_NAME STREQUAL "iOS")' not in updated:
        raise SystemExit("Cubeb iOS CMake branch was not installed")
    cmake.write_text(updated, encoding="utf-8")


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

    patch_cmake_for_ios(cubeb_root)

    print(
        "Applied Mozilla Cubeb iOS AudioUnit backport "
        f"blob {PATCH_BLOB_SHA} and removed the macOS run loop from the iOS target"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
