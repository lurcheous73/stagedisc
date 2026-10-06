#!/bin/bash
# GPL-2.0-or-later FFmpeg/x264 helpers. Sources and notices accompany the app.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="${STAGEDISC_MEDIA_BUILD_DIR:-$root/.build-media}"
prefix="$scratch/static"
mkdir -p "$scratch" "$prefix" "$root/Resources/bin"
for name in x264 ffmpeg; do
    [[ ! -d "$scratch/$name" ]] || { echo "Choose an empty STAGEDISC_MEDIA_BUILD_DIR." >&2; exit 1; }
    mkdir "$scratch/$name"
    tar -xzf "$root/ThirdParty/sources/$name.tar.gz" -C "$scratch/$name"
done
export MACOSX_DEPLOYMENT_TARGET=14.0
cd "$scratch/x264"
./configure --prefix="$prefix" --enable-static --disable-cli --disable-opencl \
  --extra-cflags="-mmacosx-version-min=14.0 -g" --extra-asflags="-mmacosx-version-min=14.0 -g"
make -j"$(sysctl -n hw.logicalcpu)"
make install
cd "$scratch/ffmpeg"
PKG_CONFIG_PATH="$prefix/lib/pkgconfig" ./configure --prefix="$prefix" \
  --enable-gpl --enable-libx264 --enable-zlib --pkg-config-flags=--static \
  --disable-autodetect --disable-shared --enable-static --disable-network \
  --disable-doc --enable-debug=2 --disable-avdevice --disable-encoders \
  --enable-encoder=libx264,pcm_s16le,pcm_s24le,ac3 \
  --disable-muxers --enable-muxer=h264,hevc,w64,wav,ac3,eac3,dts,truehd,null \
  --extra-cflags=-mmacosx-version-min=14.0 --extra-ldflags=-mmacosx-version-min=14.0
make -j"$(sysctl -n hw.logicalcpu)"
symbols="${STAGEDISC_SYMBOLS_DIR:-$scratch/symbols}"
mkdir -p "$symbols" "$scratch/unstripped"
for name in ffmpeg ffprobe; do
    cp "${name}_g" "$scratch/unstripped/$name"
    xcrun dsymutil "$scratch/unstripped/$name" -o "$symbols/$name.dSYM"
done
cp ffmpeg ffprobe "$root/Resources/bin/"
cp COPYING.GPLv2 "$root/Resources/LICENSE-FFmpeg.txt"
cp "$scratch/x264/COPYING" "$root/Resources/LICENSE-x264.txt"
echo 'Built Apple Silicon media tools with macOS 14 minimum deployment target.'
