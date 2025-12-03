#!/usr/bin/env bash
set -euo pipefail

NDK="$1"
ABI="${2:-arm64-v8a}"
API="${3:-24}"
OPENSSL_DIR="$4"
SRC="$5"
OUTDIR="${6:-$(pwd)/out}"

if [ -z "$NDK" ] || [ -z "$OPENSSL_DIR" ] || [ -z "$SRC" ]; then
  echo "Usage: $0 <ndk-path> [ABI] [API] <openssl-dir> <curl-src> [outdir]"
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
echo "Configuring libcurl build for ABI=$ABI API=$API, OPENSSL_ROOT=$OPENSSL_DIR"

cmake -G "Ninja" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DANDROID_ABI="$ABI" \
  -DANDROID_PLATFORM="android-$API" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCURL_USE_OPENSSL=ON \
  -DOPENSSL_ROOT_DIR="$OPENSSL_DIR" \
  -DCMAKE_INSTALL_PREFIX="$BUILD_DIR/install" \
  -S "$SRC" -B .

cmake --build . --config Release -- -j
cmake --install . --config Release

echo "libcurl build finished. Installed to $BUILD_DIR/install"
popd
