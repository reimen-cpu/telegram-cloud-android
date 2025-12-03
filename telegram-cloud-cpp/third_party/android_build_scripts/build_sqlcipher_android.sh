#!/usr/bin/env bash
set -e
set -u
# Try to enable pipefail, but don't fail if it's not supported
(set -o pipefail) 2>/dev/null || true

# SQLCipher build script for Android using CMake
# This script cross-compiles SQLCipher for Android using the NDK

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
      echo "Usage: $0 -ndk <ndk-path> -abi <abi> -api <api-level> -opensslDir <openssl-dir> -srcPath <sqlcipher-src> -outDir <output-dir>"
      exit 1
      ;;
  esac
done

# Validate required parameters
if [ -z "$NDK" ] || [ -z "$SRC_PATH" ] || [ -z "$OUT_DIR" ]; then
  echo "Error: Missing required parameters"
  echo "Usage: $0 -ndk <ndk-path> -abi <abi> -api <api-level> -opensslDir <openssl-dir> -srcPath <sqlcipher-src> -outDir <output-dir>"
  echo ""
  echo "Example:"
  echo "  $0 -ndk /path/to/ndk -abi arm64-v8a -api 28 -opensslDir /path/to/openssl -srcPath /path/to/sqlcipher -outDir /path/to/output"
  exit 1
fi

# Verify paths exist
if [ ! -d "$NDK" ]; then
  echo "Error: NDK path not found: $NDK"
  exit 1
fi

if [ -n "$OPENSSL_DIR" ] && [ ! -d "$OPENSSL_DIR" ]; then
  echo "Error: OpenSSL directory not found: $OPENSSL_DIR"
  exit 1
fi

if [ ! -d "$SRC_PATH" ]; then
  echo "Error: SQLCipher source path not found: $SRC_PATH"
  exit 1
fi

# Normalize ABI for directory names
ABI_NORMALIZED="${ABI//-/_}"
BUILD_DIR="$OUT_DIR/build_$ABI_NORMALIZED"
INSTALL_DIR="$BUILD_DIR/installed"

# Cache check: skip build if already compiled successfully
if [ -f "$INSTALL_DIR/lib/libsqlcipher.a" ] || [ -f "$INSTALL_DIR/lib/libsqlite3.a" ]; then
  if [ -d "$INSTALL_DIR/include" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✓ SQLCipher already built (cache hit)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Install location: $INSTALL_DIR"
    if [ -f "$INSTALL_DIR/lib/libsqlcipher.a" ]; then
      echo "Library: $INSTALL_DIR/lib/libsqlcipher.a"
    else
      echo "Library: $INSTALL_DIR/lib/libsqlite3.a"
    fi
    echo "Headers: $INSTALL_DIR/include"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
  fi
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SQLCipher Build Configuration"
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

# Verify SQLCipher source has configure script
if [ ! -f "$SRC_PATH/configure" ] && [ ! -f "$SRC_PATH/configure.ac" ]; then
  echo "Error: SQLCipher source does not contain configure script"
  echo "  Expected: $SRC_PATH/configure or $SRC_PATH/configure.ac"
  echo "  SQLCipher uses autotools, not CMake"
  exit 1
fi

# Copy source to build directory (configure modifies files in-place)
if [ ! -d "$BUILD_DIR" ] || [ ! -f "$BUILD_DIR/configure" ]; then
  echo "Copying SQLCipher source to build directory..."
  rm -rf "$BUILD_DIR"
  cp -r "$SRC_PATH" "$BUILD_DIR"
fi

cd "$BUILD_DIR"

# Set up compiler environment
export CC="$NDK_TOOLCHAIN/bin/${TARGET_PREFIX}${API}-clang"
export CXX="$NDK_TOOLCHAIN/bin/${TARGET_PREFIX}${API}-clang++"
export AR="$NDK_TOOLCHAIN/bin/llvm-ar"
export RANLIB="$NDK_TOOLCHAIN/bin/llvm-ranlib"
export STRIP="$NDK_TOOLCHAIN/bin/llvm-strip"
export PATH="$NDK_TOOLCHAIN/bin:$PATH"

# Set Android-specific flags
# Note: Don't set -D__ANDROID_API__ here as it's already set by the NDK compiler
export CFLAGS="-fPIC -O2"
export LDFLAGS="-L$NDK_TOOLCHAIN/sysroot/usr/lib/${TARGET_PREFIX}/$API -llog"

# Add OpenSSL and SQLCipher flags if provided
# These flags are required for SQLCipher compatibility with previous builds
if [ -n "$OPENSSL_DIR" ]; then
  export CFLAGS="$CFLAGS -I$OPENSSL_DIR/include -DSQLITE_HAS_CODEC -DSQLITE_TEMP_STORE=2 -DSQLITE_EXTRA_INIT=sqlcipher_extra_init -DSQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown"
  export LDFLAGS="$LDFLAGS -L$OPENSSL_DIR/lib -lcrypto -lssl"
  export LIBS="-lcrypto -lssl -llog"
else
  export CFLAGS="$CFLAGS -DSQLITE_HAS_CODEC -DSQLITE_TEMP_STORE=2 -DSQLITE_EXTRA_INIT=sqlcipher_extra_init -DSQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown"
  export LIBS="-llog"
fi

echo ""
echo "[1/3] Configuring SQLCipher with autotools..."

echo "Using NDK toolchain: $NDK_TOOLCHAIN"
echo "CC: $CC"
echo "CXX: $CXX"

# Run configure with correct options for SQLCipher
./configure \
  --host="$TARGET_PREFIX" \
  --prefix="$INSTALL_DIR" \
  --disable-tcl \
  --disable-shared \
  --enable-static

if [ $? -ne 0 ]; then
  echo "Error: SQLCipher configure failed"
  exit 1
fi

# Modify Makefile to ensure OpenSSL libraries are linked
if [ -n "$OPENSSL_DIR" ]; then
  echo "Modifying Makefile to link OpenSSL libraries..."
  # Fix permissions if needed (WSL/Windows file system issue)
  chmod +w Makefile 2>/dev/null || true
  
  # Find the sqlite3 target and add OpenSSL libraries to the linking command
  # The sqlite3 target typically uses $(TCC) or similar, we need to add libs at the end
  if grep -q "^sqlite3:" Makefile; then
    # Find the line with sqlite3 target and modify it to include OpenSSL libs
    # SQLCipher's Makefile typically has: sqlite3: shell.c sqlite3.c
    # We need to add the libraries to the actual link command, not the target line
    # Look for the actual compilation/linking line
    sed -i "s|\$(TCC) -o sqlite3|\$(TCC) -o sqlite3 -L$OPENSSL_DIR/lib -lcrypto -lssl -llog|g" Makefile
    sed -i "s|shell.c sqlite3.c|shell.c sqlite3.c -L$OPENSSL_DIR/lib -lcrypto -lssl -llog|g" Makefile
  fi
  # Also ensure LIBS variable includes OpenSSL
  if grep -q "^LIBS = " Makefile; then
    sed -i "s|^LIBS = |LIBS = -L$OPENSSL_DIR/lib -lcrypto -lssl -llog |" Makefile
  fi
  # Modify TARGET_LIBS if it exists
  if grep -q "^TARGET_LIBS = " Makefile; then
    sed -i "s|^TARGET_LIBS = |TARGET_LIBS = -L$OPENSSL_DIR/lib -lcrypto -lssl -llog |" Makefile
  else
    # Add TARGET_LIBS if it doesn't exist (before first target)
    sed -i "/^all:/i TARGET_LIBS = -L$OPENSSL_DIR/lib -lcrypto -lssl -llog" Makefile
  fi
  # Also add to libsqlite3.a if it exists as a target
  if grep -q "^libsqlite3.a:" Makefile; then
    # The library itself doesn't need linking, but ensure it's available
    echo "# OpenSSL libraries added for linking" >> Makefile
  fi
fi

echo ""
echo "[2/3] Building SQLCipher..."
make -j$(nproc)

if [ $? -ne 0 ]; then
  echo "Error: Build failed"
  exit 1
fi

echo ""
echo "[3/3] Installing SQLCipher..."
make install

if [ $? -ne 0 ]; then
  echo "Error: Install failed"
  exit 1
fi

# Verify installation
echo ""
echo "Verifying installation..."
if [ ! -f "$INSTALL_DIR/lib/libsqlcipher.a" ] && [ ! -f "$INSTALL_DIR/lib/libsqlite3.a" ]; then
  echo "Error: SQLCipher library not found in $INSTALL_DIR/lib"
  exit 1
fi

if [ ! -f "$INSTALL_DIR/include/sqlite3.h" ]; then
  echo "Error: SQLCipher headers not found in $INSTALL_DIR/include"
  exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ SQLCipher build completed successfully"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Install location: $INSTALL_DIR"
echo "Library: $INSTALL_DIR/lib/"
echo "Headers: $INSTALL_DIR/include/sqlite3.h"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
