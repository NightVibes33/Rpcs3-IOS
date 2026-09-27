#!/usr/bin/env bash
set -euo pipefail

ROOT="$PWD"
BUILD="${NATIVE_APP_BUILD:-$ROOT/native-ios-build}"
CORE_DIR="$ROOT/BuildSupport/RPCS3Core"
DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-17.4}"

test -s "$CORE_DIR/libRPCS3Core.dylib"
test -s "$CORE_DIR/RPCS3IOS.h"

rm -rf "$BUILD"
cmake -S "$ROOT/NativeApp" -B "$BUILD" -G Xcode   -DCMAKE_SYSTEM_NAME=iOS   -DCMAKE_OSX_SYSROOT=iphoneos   -DCMAKE_OSX_ARCHITECTURES=arm64   -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"   -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO   -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO   -DRPCS3_CORE_DIR="$CORE_DIR"

cmake --build "$BUILD" --config Release --target RPCS3IOSNative --parallel 3

APP="$(find "$BUILD" -type d -name 'RPCS3.app' -path '*Release*' -print | head -n1)"
[[ -n "$APP" && -d "$APP" ]] || { find "$BUILD" -type d -name '*.app' -print; exit 1; }

mkdir -p "$APP/Frameworks"
cp -f "$CORE_DIR/libRPCS3Core.dylib" "$APP/Frameworks/libRPCS3Core.dylib"
chmod 0755 "$APP/Frameworks/libRPCS3Core.dylib"

# SideStore/SideSign uses the entitlements already present in the incoming
# application's code signature to decide which provisioning-profile
# entitlements it is allowed to keep. Do not ship a totally unsigned app:
# ad-hoc sign nested code first, then sign the app with RPCS3's required
# memory/address-space entitlements so SideStore can preserve them when it
# replaces this signature with the user's Apple Development identity.
codesign --force --sign - "$APP/Frameworks/libRPCS3Core.dylib"
codesign --force --sign - --entitlements "$ROOT/NativeApp/RPCS3.entitlements" "$APP"

BIN="$APP/RPCS3"
test -s "$BIN"
codesign --verify --deep --strict "$APP"
codesign -d --entitlements :- "$APP" > "$BUILD/app-signed-entitlements.plist" 2>/dev/null
grep -q 'com.apple.developer.kernel.increased-memory-limit' "$BUILD/app-signed-entitlements.plist"
grep -q 'com.apple.developer.kernel.extended-virtual-addressing' "$BUILD/app-signed-entitlements.plist"
grep -q 'com.apple.developer.kernel.increased-debugging-memory-limit' "$BUILD/app-signed-entitlements.plist"

otool -L "$BIN" | tee "$BUILD/app-linked-libraries.txt"

# XITRIX v0.9 selects the arena policy before RPCS3Core is loaded. A load-time
# dependency here would make that ordering impossible.
! grep -q 'libRPCS3Core.dylib' "$BUILD/app-linked-libraries.txt"
! grep -Eiq 'Qt(Core|Gui|Widgets)|RPCS3UpstreamRuntime|Flutter' "$BUILD/app-linked-libraries.txt"
grep -q 'SwiftUI.framework/SwiftUI' "$BUILD/app-linked-libraries.txt"
grep -q 'UIKit.framework/UIKit' "$BUILD/app-linked-libraries.txt"

nm -gU "$APP/Frameworks/libRPCS3Core.dylib" > "$BUILD/core-exports.txt"
grep -q '_rpcs3_ios_boot_big_picture_mode' "$BUILD/core-exports.txt"
grep -q '_rpcs3_ios_run_llvm_self_test' "$BUILD/core-exports.txt"
grep -q '_rpcs3_ios_set_display_surface' "$BUILD/core-exports.txt"

strings "$BIN" > "$BUILD/app-strings.txt"
grep -q 'RPCS3_IOS_EXPANDED_JIT_ARENA' "$BUILD/app-strings.txt"
grep -q 'libRPCS3Core.dylib' "$BUILD/app-strings.txt"
grep -q 'Big Picture Mode' "$BUILD/app-strings.txt"

file "$BIN" | tee "$BUILD/app-file.txt"
lipo -archs "$BIN" | tee "$BUILD/app-archs.txt"
printf '%s\n' "$APP" > "$BUILD/app-path.txt"
echo "PASS: SwiftUI host delays RPCS3Core loading until after JIT policy selection and carries SideStore-discoverable memory entitlements"
