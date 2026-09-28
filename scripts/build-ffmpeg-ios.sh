#!/bin/bash
set -euo pipefail

PORT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FFMPEG_TAG="${FFMPEG_TAG:-n7.1}"
SOURCE_ROOT="${FFMPEG_SOURCE_ROOT:-$PORT_ROOT/.cache/ffmpeg-$FFMPEG_TAG}"
BUILD_ROOT="${FFMPEG_BUILD_ROOT:-$PORT_ROOT/.cache/ffmpeg-ios-build-$FFMPEG_TAG}"
PREFIX="${FFMPEG_IOS_ROOT:-$PORT_ROOT/BuildSupport/ffmpeg-ios}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-26.0}"
IOS_SDK="${IOS_SDK:-iphoneos}"
IOS_ARCH="${IOS_ARCH:-arm64}"
JOBS="${FFMPEG_JOBS:-3}"
STAMP="$PREFIX/.rpcs3-ios-ffmpeg-$FFMPEG_TAG-$IOS_SDK-videotoolbox-v2"
LEGACY_STAMP="$PREFIX/.rpcs3-ios-ffmpeg-$FFMPEG_TAG"

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
  cache_symbols="$PREFIX/.libavutil-symbols.txt"
  if ! /usr/bin/nm -gU "$PREFIX/lib/libavutil.a" >"$cache_symbols" 2>/dev/null \
      || ! grep -q '_av_map_videotoolbox_format_to_pixfmt' "$cache_symbols"; then
    valid_install=0
  fi
  rm -f "$cache_symbols"
fi

if [[ "$valid_install" == 1 ]]; then
  # Older graph/cache contracts still look for this stamp. Only create it after
  # the stricter VideoToolbox symbol validation above has succeeded.
  printf '%s\n' "$FFMPEG_TAG" > "$LEGACY_STAMP"
  echo "Using cached FFmpeg $FFMPEG_TAG $IOS_ARCH-$IOS_SDK VideoToolbox install at $PREFIX"
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

SDK_ROOT="$(xcrun --sdk "$IOS_SDK" --show-sdk-path)"
CC="$(xcrun --sdk "$IOS_SDK" --find clang)"
CXX="$(xcrun --sdk "$IOS_SDK" --find clang++)"
AR="$(xcrun --sdk "$IOS_SDK" --find ar)"
RANLIB="$(xcrun --sdk "$IOS_SDK" --find ranlib)"
STRIP="$(xcrun --sdk "$IOS_SDK" --find strip)"
NM="$(xcrun --sdk "$IOS_SDK" --find nm)"
if [[ "$IOS_SDK" == "iphonesimulator" ]]; then
  TARGET_FLAGS="-target $IOS_ARCH-apple-ios$DEPLOYMENT_TARGET-simulator"
else
  TARGET_FLAGS="-arch $IOS_ARCH -miphoneos-version-min=$DEPLOYMENT_TARGET"
fi

rm -rf "$BUILD_ROOT" "$PREFIX"
mkdir -p "$BUILD_ROOT" "$PREFIX"

pushd "$BUILD_ROOT" >/dev/null
"$SOURCE_ROOT/configure" \
  --prefix="$PREFIX" \
  --target-os=darwin \
  --arch="$IOS_ARCH" \
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
  --enable-videotoolbox \
  --disable-iconv \
  --disable-bzlib \
  --disable-lzma \
  --disable-zlib \
  --extra-cflags="$TARGET_FLAGS -fPIC" \
  --extra-cxxflags="$TARGET_FLAGS -fPIC" \
  --extra-ldflags="$TARGET_FLAGS" \
  --extra-libs="-lc++"

make -j"$JOBS"
make install
popd >/dev/null

for library in "${required_libraries[@]}"; do
  test -f "$PREFIX/lib/$library"
  file "$PREFIX/lib/$library"
  lipo -info "$PREFIX/lib/$library" || true
done

SYMBOLS_FILE="$PREFIX/libavutil-symbols.txt"
"$NM" -gU "$PREFIX/lib/libavutil.a" > "$SYMBOLS_FILE"
grep -q '_av_map_videotoolbox_format_to_pixfmt' "$SYMBOLS_FILE"
grep -q '#define LIBAVUTIL_VERSION_MAJOR  *59' "$PREFIX/include/libavutil/version.h"
grep -q '#define LIBAVUTIL_VERSION_MINOR  *39' "$PREFIX/include/libavutil/version.h"
printf '%s\n' "$FFMPEG_TAG" > "$STAMP"
printf '%s\n' "$FFMPEG_TAG" > "$LEGACY_STAMP"

cat > "$PREFIX/rpcs3-ios-build.txt" <<EOF
FFmpeg tag: $FFMPEG_TAG
Target: $IOS_ARCH-apple-ios$DEPLOYMENT_TARGET ($IOS_SDK)
SDK: $SDK_ROOT
Source: $SOURCE_ROOT
Build: $BUILD_ROOT
VideoToolbox: enabled
EOF

cat "$PREFIX/rpcs3-ios-build.txt"
