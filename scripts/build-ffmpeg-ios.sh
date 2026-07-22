#!/bin/bash
set -euo pipefail

PORT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FFMPEG_TAG="${FFMPEG_TAG:-n7.1}"
SOURCE_ROOT="${FFMPEG_SOURCE_ROOT:-$PORT_ROOT/.cache/ffmpeg-$FFMPEG_TAG}"
BUILD_ROOT="${FFMPEG_BUILD_ROOT:-$PORT_ROOT/.cache/ffmpeg-ios-build-$FFMPEG_TAG}"
PREFIX="${FFMPEG_IOS_ROOT:-$PORT_ROOT/BuildSupport/ffmpeg-ios}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-26.0}"
JOBS="${FFMPEG_JOBS:-3}"
STAMP="$PREFIX/.rpcs3-ios-ffmpeg-$FFMPEG_TAG"

required_libraries=(
  libavcodec.a
  libavformat.a
  libavutil.a
  libswscale.a
  libswresample.a
)

valid_install=1
[[ -f "$STAMP" ]] || valid_install=0
[[ -f "$PREFIX/include/libavutil/version.h" ]] || valid_install=0
for library in "${required_libraries[@]}"; do
  [[ -f "$PREFIX/lib/$library" ]] || valid_install=0
done

if [[ "$valid_install" == 1 ]]; then
  echo "Using cached FFmpeg $FFMPEG_TAG arm64-iOS install at $PREFIX"
  exit 0
fi

command -v git >/dev/null
command -v make >/dev/null
command -v xcrun >/dev/null

mkdir -p "$(dirname "$SOURCE_ROOT")" "$(dirname "$BUILD_ROOT")" "$(dirname "$PREFIX")"

if [[ ! -d "$SOURCE_ROOT/.git" ]]; then
  rm -rf "$SOURCE_ROOT"
  git clone --filter=blob:none --depth 1 --branch "$FFMPEG_TAG" --single-branch \
    https://github.com/FFmpeg/FFmpeg.git "$SOURCE_ROOT"
else
  git -C "$SOURCE_ROOT" fetch --depth 1 origin "refs/tags/$FFMPEG_TAG:refs/tags/$FFMPEG_TAG"
  git -C "$SOURCE_ROOT" checkout --detach --force "$FFMPEG_TAG"
  git -C "$SOURCE_ROOT" clean -ffdqx
fi

SDK_ROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
CC="$(xcrun --sdk iphoneos --find clang)"
CXX="$(xcrun --sdk iphoneos --find clang++)"
AR="$(xcrun --sdk iphoneos --find ar)"
RANLIB="$(xcrun --sdk iphoneos --find ranlib)"
STRIP="$(xcrun --sdk iphoneos --find strip)"
NM="$(xcrun --sdk iphoneos --find nm)"

rm -rf "$BUILD_ROOT" "$PREFIX"
mkdir -p "$BUILD_ROOT" "$PREFIX"

pushd "$BUILD_ROOT" >/dev/null
"$SOURCE_ROOT/configure" \
  --prefix="$PREFIX" \
  --target-os=darwin \
  --arch=arm64 \
  --cc="$CC" \
  --cxx="$CXX" \
  --ar="$AR" \
  --ranlib="$RANLIB" \
  --strip="$STRIP" \
  --nm="$NM" \
  --sysroot="$SDK_ROOT" \
  --enable-cross-compile \
  --enable-static \
  --disable-shared \
  --enable-pic \
  --disable-programs \
  --disable-doc \
  --disable-debug \
  --disable-avdevice \
  --disable-postproc \
  --disable-network \
  --disable-autodetect \
  --disable-iconv \
  --disable-bzlib \
  --disable-lzma \
  --disable-zlib \
  --extra-cflags="-arch arm64 -miphoneos-version-min=$DEPLOYMENT_TARGET -fPIC" \
  --extra-cxxflags="-arch arm64 -miphoneos-version-min=$DEPLOYMENT_TARGET -fPIC" \
  --extra-ldflags="-arch arm64 -miphoneos-version-min=$DEPLOYMENT_TARGET" \
  --extra-libs="-lc++"

make -j"$JOBS"
make install
popd >/dev/null

for library in "${required_libraries[@]}"; do
  test -f "$PREFIX/lib/$library"
  file "$PREFIX/lib/$library"
  lipo -info "$PREFIX/lib/$library" || true
done

grep -q '#define LIBAVUTIL_VERSION_MAJOR  *59' "$PREFIX/include/libavutil/version.h"
grep -q '#define LIBAVUTIL_VERSION_MINOR  *39' "$PREFIX/include/libavutil/version.h"
printf '%s\n' "$FFMPEG_TAG" > "$STAMP"

cat > "$PREFIX/rpcs3-ios-build.txt" <<EOF
FFmpeg tag: $FFMPEG_TAG
Target: arm64-apple-ios$DEPLOYMENT_TARGET
SDK: $SDK_ROOT
Source: $SOURCE_ROOT
Build: $BUILD_ROOT
EOF

cat "$PREFIX/rpcs3-ios-build.txt"
