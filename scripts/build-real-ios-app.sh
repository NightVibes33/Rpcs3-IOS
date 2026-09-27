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

BIN="$APP/RPCS3"
test -s "$BIN"
otool -L "$BIN" | tee "$BUILD/app-linked-libraries.txt"
grep -q '@rpath/libRPCS3Core.dylib' "$BUILD/app-linked-libraries.txt"
! grep -qi 'Qt.*framework' "$BUILD/app-linked-libraries.txt"

nm -gU "$APP/Frameworks/libRPCS3Core.dylib" > "$BUILD/core-exports.txt"
grep -q '_rpcs3_ios_boot_big_picture_mode' "$BUILD/core-exports.txt"
grep -q '_rpcs3_ios_run_llvm_self_test' "$BUILD/core-exports.txt"
grep -q '_rpcs3_ios_set_display_surface' "$BUILD/core-exports.txt"

file "$BIN" | tee "$BUILD/app-file.txt"
lipo -archs "$BIN" | tee "$BUILD/app-archs.txt"
printf '%s\n' "$APP" > "$BUILD/app-path.txt"
echo "PASS: native host links directly to XITRIX RPCS3Core; Qt is absent"
