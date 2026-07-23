#!/bin/bash
set -euo pipefail

VERSION="${MOLTENVK_VERSION:-1.4.1}"
PORT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${MOLTENVK_IOS_ROOT:-$PORT_ROOT/BuildSupport/moltenvk-ios}"
CACHE_DIR="${MOLTENVK_CACHE_DIR:-$PORT_ROOT/BuildSupport/downloads/moltenvk-$VERSION}"
ARCHIVE="$CACHE_DIR/MoltenVK-ios.tar"
ARCHIVE_PART="$ARCHIVE.part"
EXTRACTED="$CACHE_DIR/extracted"
RELEASE_JSON="$CACHE_DIR/release.json"
SOURCE_ROOT="$CACHE_DIR/source"
SLICE_INFO_FILE="$CACHE_DIR/ios-device-slice.txt"
ASSET_NAME="MoltenVK-ios.tar"
ASSET_URL="${MOLTENVK_ASSET_URL:-https://github.com/KhronosGroup/MoltenVK/releases/download/v$VERSION/$ASSET_NAME}"
SOURCE_URL="https://github.com/KhronosGroup/MoltenVK.git"
SOURCE_ORIGIN="$ASSET_URL"
PACKAGE_ROOT=""

mkdir -p "$CACHE_DIR" "$PORT_ROOT/BuildSupport"

if [[ -f "$OUTPUT/version.txt" ]] && \
   [[ "$(tr -d '[:space:]' < "$OUTPUT/version.txt")" == "$VERSION" ]] && \
   [[ -f "$OUTPUT/lib/libMoltenVK.a" ]] && \
   [[ -f "$OUTPUT/include/vulkan/vulkan.h" ]] && \
   [[ -f "$OUTPUT/include/MoltenVK/mvk_vulkan.h" ]]; then
    echo "Using cached MoltenVK $VERSION iOS package at $OUTPUT"
    exit 0
fi

for tool in curl python3 shasum git make xcodebuild; do
    command -v "$tool" >/dev/null
 done

validate_archive() {
    local archive="$1"
    [[ -f "$archive" ]] || return 1

    local size
    size="$(stat -f '%z' "$archive" 2>/dev/null || stat -c '%s' "$archive")"
    if [[ "$size" -lt 1048576 ]]; then
        echo "MoltenVK archive is unexpectedly small: $size bytes" >&2
        file "$archive" >&2 || true
        return 1
    fi

    if unzip -t "$archive" >/dev/null 2>&1; then
        return 0
    fi
    tar -tf "$archive" >/dev/null 2>&1
}

download_direct() {
    echo "Downloading official MoltenVK $VERSION iOS asset: $ASSET_URL"
    rm -f "$ARCHIVE_PART"
    curl \
        --fail \
        --location \
        --silent \
        --show-error \
        --retry 6 \
        --retry-delay 3 \
        --retry-all-errors \
        --connect-timeout 30 \
        --max-time 1200 \
        --user-agent "RPCS3-iOS-CI/1.0" \
        "$ASSET_URL" \
        -o "$ARCHIVE_PART" || return 1
    mv "$ARCHIVE_PART" "$ARCHIVE"
    validate_archive "$ARCHIVE"
}

download_via_api() {
    [[ -n "${GITHUB_TOKEN:-}" ]] || return 1

    echo "Direct release download failed; retrying through GitHub's authenticated release API"
    curl \
        --fail \
        --location \
        --silent \
        --show-error \
        --retry 4 \
        --retry-delay 3 \
        --retry-all-errors \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/KhronosGroup/MoltenVK/releases/tags/v$VERSION" \
        -o "$RELEASE_JSON" || return 1

    local asset_api_url
    asset_api_url="$(python3 - "$RELEASE_JSON" "$ASSET_NAME" <<'PY'
import json
import sys

release = json.load(open(sys.argv[1], encoding="utf-8"))
asset_name = sys.argv[2]
for asset in release.get("assets", []):
    if asset.get("name") == asset_name:
        print(asset.get("url", ""))
        break
PY
)"
    [[ -n "$asset_api_url" ]] || return 1

    rm -f "$ARCHIVE_PART"
    curl \
        --fail \
        --location \
        --silent \
        --show-error \
        --retry 6 \
        --retry-delay 3 \
        --retry-all-errors \
        --connect-timeout 30 \
        --max-time 1200 \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/octet-stream" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$asset_api_url" \
        -o "$ARCHIVE_PART" || return 1
    mv "$ARCHIVE_PART" "$ARCHIVE"
    validate_archive "$ARCHIVE"
}

build_from_source() {
    echo "Release asset acquisition failed; building MoltenVK $VERSION for iOS from the official tag"
    rm -rf "$SOURCE_ROOT"
    git clone --filter=blob:none --depth 1 --branch "v$VERSION" --single-branch \
        "$SOURCE_URL" "$SOURCE_ROOT"

    (
        cd "$SOURCE_ROOT"
        ./fetchDependencies -v --ios
        make ios
    )

    PACKAGE_ROOT="$SOURCE_ROOT/Package/Release"
    [[ -d "$PACKAGE_ROOT/MoltenVK/static/MoltenVK.xcframework" ]]
    SOURCE_ORIGIN="$SOURCE_URL#v$VERSION (built from source)"
}

rm -f "$ARCHIVE" "$ARCHIVE_PART"
if download_direct || download_via_api; then
    echo "Validated MoltenVK release archive"
    rm -rf "$EXTRACTED"
    mkdir -p "$EXTRACTED"
    if unzip -t "$ARCHIVE" >/dev/null 2>&1; then
        unzip -q "$ARCHIVE" -d "$EXTRACTED"
    else
        tar -xf "$ARCHIVE" -C "$EXTRACTED"
    fi
    PACKAGE_ROOT="$EXTRACTED"
else
    rm -f "$ARCHIVE" "$ARCHIVE_PART"
    build_from_source
fi

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/include" "$OUTPUT/lib"

XCFRAMEWORK_INFO="$(find "$PACKAGE_ROOT" -type f -path '*/MoltenVK/static/MoltenVK.xcframework/Info.plist' -print | head -n 1)"
if [[ -z "$XCFRAMEWORK_INFO" ]]; then
    XCFRAMEWORK_INFO="$(find "$PACKAGE_ROOT" -type f -path '*/MoltenVK.xcframework/Info.plist' -print | grep '/static/' | head -n 1 || true)"
fi
if [[ -z "$XCFRAMEWORK_INFO" ]]; then
    echo "Unable to find the static MoltenVK XCFramework" >&2
    find "$PACKAGE_ROOT" -maxdepth 10 -name 'Info.plist' -print >&2
    exit 1
fi

echo "Using MoltenVK XCFramework metadata: $XCFRAMEWORK_INFO"
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

# Normalize the include tree expected by RPCS3 and CMake's FindVulkan module.
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
printf '%s\n' "$SOURCE_ORIGIN" > "$OUTPUT/source-url.txt"
if [[ -f "$ARCHIVE" ]]; then
    shasum -a 256 "$ARCHIVE" > "$OUTPUT/MoltenVK-ios.tar.sha256"
fi
shasum -a 256 "$OUTPUT/lib/libMoltenVK.a" > "$OUTPUT/lib/libMoltenVK.a.sha256"

file "$OUTPUT/lib/libMoltenVK.a"
echo "Prepared MoltenVK $VERSION physical-device iOS headers and static library at $OUTPUT"