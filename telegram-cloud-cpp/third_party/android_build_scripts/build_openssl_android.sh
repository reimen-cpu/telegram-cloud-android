#!/usr/bin/env bash
set -euo pipefail

NDK="$1" # path to ndk
ABI="${2:-arm64-v8a}"
API="${3:-24}"
SRC="$4" # openssl source dir
OUTDIR="${5:-$(pwd)/out}"

if [ -z "$NDK" ] || [ -z "$SRC" ]; then
  echo "Usage: $0 <ndk-path> [ABI] [API] <openssl-src> [outdir]"
  exit 1
fi

mkdir -p "$OUTDIR"
BUILD_DIR="$OUTDIR/build_$ABI"
mkdir -p "$BUILD_DIR"

TOOLCHAIN="$NDK/build/cmake/android.toolchain.cmake"
if [ ! -f "$TOOLCHAIN" ]; then
  echo "CMake toolchain not found at $TOOLCHAIN"
  exit 1
fi

pushd "$BUILD_DIR"
echo "Configuring OpenSSL build for ABI=$ABI API=$API"
cmake -G "Ninja" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DANDROID_ABI="$ABI" \
  -DANDROID_PLATFORM="android-$API" \
  -DCMAKE_BUILD_TYPE=Release \
  -DOPENSSL_USE_STATIC_LIBS=ON \
  -S "$SRC" -B .

cmake --build . --config Release -- -j
echo "OpenSSL build finished. Artifacts in $BUILD_DIR"
popd
