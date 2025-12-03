#!/usr/bin/env bash
set -e
set -u
# Try to enable pipefail, but don't fail if it's not supported
(set -o pipefail) 2>/dev/null || true

# libcurl build script for Android using CMake
# This script cross-compiles libcurl for Android using the NDK

# Default values
NDK=""
ABI="arm64-v8a"
API=28
OPENSSL_DIR=""
SRC_PATH=""
OUT_DIR=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -ndk)
      NDK="$2"
      shift 2
      ;;
    -abi)
      ABI="$2"
      shift 2
      ;;
    -api)
      API="$2"
      shift 2
      ;;
    -opensslDir)
      OPENSSL_DIR="$2"
      shift 2
      ;;
    -srcPath)
      SRC_PATH="$2"
      shift 2
      ;;
    -outDir)
      OUT_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 -ndk <ndk-path> -abi <abi> -api <api-level> -opensslDir <openssl-dir> -srcPath <curl-src> -outDir <output-dir>"
      exit 1
      ;;
  esac
done

# Validate required parameters
if [ -z "$NDK" ] || [ -z "$OPENSSL_DIR" ] || [ -z "$SRC_PATH" ] || [ -z "$OUT_DIR" ]; then
  echo "Error: Missing required parameters"
  echo "Usage: $0 -ndk <ndk-path> -abi <abi> -api <api-level> -opensslDir <openssl-dir> -srcPath <curl-src> -outDir <output-dir>"
  echo ""
  echo "Example:"
  echo "  $0 -ndk /path/to/ndk -abi arm64-v8a -api 28 -opensslDir /path/to/openssl -srcPath /path/to/curl-8.7.1 -outDir /path/to/output"
  exit 1
fi

# Verify paths exist
if [ ! -d "$NDK" ]; then
  echo "Error: NDK path not found: $NDK"
  exit 1
fi

if [ ! -d "$OPENSSL_DIR" ]; then
  echo "Error: OpenSSL directory not found: $OPENSSL_DIR"
  exit 1
fi

if [ ! -d "$SRC_PATH" ]; then
  echo "Error: libcurl source path not found: $SRC_PATH"
  exit 1
fi

# Normalize ABI for directory names
ABI_NORMALIZED="${ABI//-/_}"
BUILD_DIR="$OUT_DIR/build_$ABI_NORMALIZED"
INSTALL_DIR="$BUILD_DIR/installed"

# Cache check: skip build if already compiled successfully
if [ -f "$INSTALL_DIR/lib/libcurl.a" ] && [ -d "$INSTALL_DIR/include/curl" ]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "✓ libcurl already built (cache hit)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Install location: $INSTALL_DIR"
  echo "Library: $INSTALL_DIR/lib/libcurl.a"
  echo "Headers: $INSTALL_DIR/include/curl"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 0
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "libcurl Build Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "NDK:         $NDK"
echo "ABI:         $ABI"
echo "API Level:   $API"
echo "OpenSSL:     $OPENSSL_DIR"
echo "Source:      $SRC_PATH"
echo "Build Dir:   $BUILD_DIR"
echo "Install Dir: $INSTALL_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Clean and create build directory
if [ -d "$BUILD_DIR" ]; then
  echo "Cleaning previous build..."
  rm -rf "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"

# Set up NDK toolchain paths
NDK_TOOLCHAIN_BASE="$NDK/toolchains/llvm/prebuilt"

# Detect host OS for NDK toolchain (Linux or macOS only)
if [ -d "$NDK_TOOLCHAIN_BASE/linux-x86_64" ]; then
  NDK_TOOLCHAIN="$NDK_TOOLCHAIN_BASE/linux-x86_64"
elif [ -d "$NDK_TOOLCHAIN_BASE/darwin-x86_64" ]; then
  NDK_TOOLCHAIN="$NDK_TOOLCHAIN_BASE/darwin-x86_64"
else
  echo "Error: Could not find NDK toolchain in $NDK_TOOLCHAIN_BASE"
  echo "  Expected linux-x86_64 or darwin-x86_64"
  exit 1
fi

# Set up compiler target prefix
case "$ABI" in
  arm64-v8a)
    TARGET_PREFIX="aarch64-linux-android"
    ;;
  armeabi-v7a)
    TARGET_PREFIX="armv7a-linux-androideabi"
    ;;
  x86)
    TARGET_PREFIX="i686-linux-android"
    ;;
  x86_64)
    TARGET_PREFIX="x86_64-linux-android"
    ;;
esac

# Verify NDK toolchain file exists
TOOLCHAIN="$NDK/build/cmake/android.toolchain.cmake"
if [ ! -f "$TOOLCHAIN" ]; then
  echo "Error: CMake toolchain not found at $TOOLCHAIN"
  exit 1
fi

cd "$BUILD_DIR"

echo ""
echo "[1/3] Configuring libcurl with CMake..."

echo "Using NDK toolchain: $NDK_TOOLCHAIN"

# Verify OpenSSL installation structure
if [ ! -d "$OPENSSL_DIR/lib" ] || [ ! -d "$OPENSSL_DIR/include" ]; then
  echo "Error: OpenSSL directory structure invalid: $OPENSSL_DIR"
  echo "  Expected: $OPENSSL_DIR/lib and $OPENSSL_DIR/include"
  exit 1
fi

# Build CMake command
CMAKE_ARGS=(
  -G "Ninja"
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN"
  -DANDROID_ABI="$ABI"
  -DANDROID_PLATFORM="android-$API"
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_SHARED_LIBS=OFF
  -DCURL_USE_OPENSSL=ON
  -DOPENSSL_ROOT_DIR="$OPENSSL_DIR"
  -DOPENSSL_INCLUDE_DIR="$OPENSSL_DIR/include"
  -DOPENSSL_CRYPTO_LIBRARY="$OPENSSL_DIR/lib/libcrypto.a"
  -DOPENSSL_SSL_LIBRARY="$OPENSSL_DIR/lib/libssl.a"
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR"
  -S "$SRC_PATH"
  -B .
)

cmake "${CMAKE_ARGS[@]}"

if [ $? -ne 0 ]; then
  echo "Error: CMake configuration failed"
  exit 1
fi

echo ""
echo "[2/3] Building libcurl..."
cmake --build . -j$(nproc)

if [ $? -ne 0 ]; then
  echo "Error: Build failed"
  exit 1
fi

echo ""
echo "[3/3] Installing libcurl..."
cmake --install .

if [ $? -ne 0 ]; then
  echo "Error: Install failed"
  exit 1
fi

# Verify installation
echo ""
echo "Verifying installation..."
if [ ! -f "$INSTALL_DIR/lib/libcurl.a" ]; then
  echo "Error: libcurl static library not found in $INSTALL_DIR/lib"
  if [ -f "$INSTALL_DIR/lib/libcurl.so" ]; then
    echo "  Found shared library instead. BUILD_SHARED_LIBS should be OFF."
  fi
  echo "  Contents of lib directory:"
  ls -la "$INSTALL_DIR/lib/" 2>/dev/null || echo "    (directory not found)"
  exit 1
fi

if [ ! -d "$INSTALL_DIR/include/curl" ]; then
  echo "Error: libcurl headers not found in $INSTALL_DIR/include"
  exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ libcurl build completed successfully"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Install location: $INSTALL_DIR"
echo "Library: $INSTALL_DIR/lib/libcurl.a"
echo "Headers: $INSTALL_DIR/include/curl"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
