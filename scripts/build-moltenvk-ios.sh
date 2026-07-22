#!/bin/bash
set -euo pipefail

VERSION="${MOLTENVK_VERSION:-1.4.1}"
PORT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${MOLTENVK_IOS_ROOT:-$PORT_ROOT/BuildSupport/moltenvk-ios}"
CACHE_DIR="${MOLTENVK_CACHE_DIR:-$PORT_ROOT/BuildSupport/downloads/moltenvk-$VERSION}"
ARCHIVE="$CACHE_DIR/moltenvk-release"
EXTRACTED="$CACHE_DIR/extracted"
RELEASE_JSON="$CACHE_DIR/release.json"
SLICE_INFO_FILE="$CACHE_DIR/ios-device-slice.txt"

mkdir -p "$CACHE_DIR" "$PORT_ROOT/BuildSupport"

if [[ -f "$OUTPUT/version.txt" ]] && \
   [[ "$(tr -d '[:space:]' < "$OUTPUT/version.txt")" == "$VERSION" ]] && \
   [[ -f "$OUTPUT/lib/libMoltenVK.a" ]] && \
   [[ -f "$OUTPUT/include/vulkan/vulkan.h" ]] && \
   [[ -f "$OUTPUT/include/MoltenVK/mvk_vulkan.h" ]]; then
    echo "Using cached MoltenVK $VERSION iOS package at $OUTPUT"
    exit 0
fi

command -v curl >/dev/null
command -v python3 >/dev/null
command -v shasum >/dev/null

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl --fail --location --silent --show-error \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/KhronosGroup/MoltenVK/releases/tags/v$VERSION" \
        -o "$RELEASE_JSON"
else
    curl --fail --location --silent --show-error \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/KhronosGroup/MoltenVK/releases/tags/v$VERSION" \
        -o "$RELEASE_JSON"
fi

ASSET_URL="$(python3 - "$RELEASE_JSON" <<'PY'
import json
import sys

release = json.load(open(sys.argv[1], encoding="utf-8"))
assets = release.get("assets", [])
preferred = []
for asset in assets:
    name = asset.get("name", "")
    lower = name.lower()
    if "moltenvk" not in lower:
        continue
    score = 0
    if "all" in lower:
        score += 20
    if lower.endswith((".tar", ".tar.gz", ".tgz", ".zip")):
        score += 10
    if "ios" in lower:
        score += 5
    preferred.append((score, name, asset.get("browser_download_url", "")))
if not preferred:
    raise SystemExit("The pinned MoltenVK release contains no downloadable runtime package")
preferred.sort(reverse=True)
url = preferred[0][2]
if not url:
    raise SystemExit("The selected MoltenVK release asset has no download URL")
print(url)
PY
)"

rm -rf "$EXTRACTED" "$OUTPUT"
mkdir -p "$EXTRACTED" "$OUTPUT/include" "$OUTPUT/lib"

curl --fail --location --silent --show-error \
    "$ASSET_URL" \
    -o "$ARCHIVE"

if unzip -t "$ARCHIVE" >/dev/null 2>&1; then
    unzip -q "$ARCHIVE" -d "$EXTRACTED"
else
    tar -xf "$ARCHIVE" -C "$EXTRACTED"
fi

XCFRAMEWORK_INFO="$(find "$EXTRACTED" -type f -path '*/MoltenVK/static/MoltenVK.xcframework/Info.plist' -print | head -n 1)"
if [[ -z "$XCFRAMEWORK_INFO" ]]; then
    XCFRAMEWORK_INFO="$(find "$EXTRACTED" -type f -path '*/MoltenVK.xcframework/Info.plist' -print | grep '/static/' | head -n 1 || true)"
fi
if [[ -z "$XCFRAMEWORK_INFO" ]]; then
    echo "Unable to find the static MoltenVK XCFramework in the release package" >&2
    find "$EXTRACTED" -maxdepth 8 -name 'Info.plist' -print >&2
    exit 1
fi

python3 - "$XCFRAMEWORK_INFO" > "$SLICE_INFO_FILE" <<'PY'
import plistlib
import sys
from pathlib import Path

info_path = Path(sys.argv[1])
root = info_path.parent
with info_path.open("rb") as stream:
    info = plistlib.load(stream)

for library in info.get("AvailableLibraries", []):
    if library.get("SupportedPlatform") != "ios":
        continue
    if library.get("SupportedPlatformVariant"):
        continue
    identifier = library["LibraryIdentifier"]
    library_path = root / identifier / library["LibraryPath"]
    if library_path.suffix == ".framework":
        binary_path = library_path / library_path.stem
        headers_path = library_path / "Headers"
    else:
        binary_path = library_path
        headers_path = root / identifier / library.get("HeadersPath", "Headers")
    print(binary_path)
    print(headers_path)
    break
else:
    raise SystemExit("The MoltenVK XCFramework has no physical iOS device slice")
PY

MOLTENVK_BINARY="$(sed -n '1p' "$SLICE_INFO_FILE")"
MOLTENVK_HEADERS="$(sed -n '2p' "$SLICE_INFO_FILE")"

test -n "$MOLTENVK_BINARY"
test -n "$MOLTENVK_HEADERS"
test -f "$MOLTENVK_BINARY"
test -d "$MOLTENVK_HEADERS"

/usr/bin/ditto "$MOLTENVK_HEADERS" "$OUTPUT/include"
cp "$MOLTENVK_BINARY" "$OUTPUT/lib/libMoltenVK.a"

# Some packages nest headers beneath the framework name. Normalize the include
# tree expected by RPCS3 and CMake's FindVulkan module.
if [[ ! -f "$OUTPUT/include/vulkan/vulkan.h" ]]; then
    VULKAN_HEADER="$(find "$MOLTENVK_HEADERS" -type f -path '*/vulkan/vulkan.h' -print | head -n 1)"
    test -n "$VULKAN_HEADER"
    VULKAN_DIR="$(dirname "$VULKAN_HEADER")"
    mkdir -p "$OUTPUT/include/vulkan"
    /usr/bin/ditto "$VULKAN_DIR" "$OUTPUT/include/vulkan"
fi
if [[ ! -f "$OUTPUT/include/MoltenVK/mvk_vulkan.h" ]]; then
    MVK_HEADER="$(find "$MOLTENVK_HEADERS" -type f -name 'mvk_vulkan.h' -print | head -n 1)"
    test -n "$MVK_HEADER"
    MVK_DIR="$(dirname "$MVK_HEADER")"
    mkdir -p "$OUTPUT/include/MoltenVK"
    /usr/bin/ditto "$MVK_DIR" "$OUTPUT/include/MoltenVK"
fi

test -f "$OUTPUT/include/vulkan/vulkan.h"
test -f "$OUTPUT/include/MoltenVK/mvk_vulkan.h"
test -f "$OUTPUT/include/MoltenVK/mvk_private_api.h"
test -f "$OUTPUT/lib/libMoltenVK.a"

printf '%s\n' "$VERSION" > "$OUTPUT/version.txt"
printf '%s\n' "$ASSET_URL" > "$OUTPUT/source-url.txt"
shasum -a 256 "$OUTPUT/lib/libMoltenVK.a" > "$OUTPUT/lib/libMoltenVK.a.sha256"

file "$OUTPUT/lib/libMoltenVK.a"
echo "Prepared MoltenVK $VERSION physical-device iOS headers and static library at $OUTPUT"
