#!/usr/bin/env bash
set -e
set -u
# Try to enable pipefail, but don't fail if it's not supported
(set -o pipefail) 2>/dev/null || true

# OpenSSL build script for Android using Configure + make (native method)
# This script cross-compiles OpenSSL for Android using the NDK

# Default values
NDK=""
ABI="arm64-v8a"
API=28
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
      echo "Usage: $0 -ndk <ndk-path> -abi <abi> -api <api-level> -srcPath <openssl-src> -outDir <output-dir>"
      exit 1
      ;;
  esac
done

# Validate required parameters
if [ -z "$NDK" ] || [ -z "$SRC_PATH" ] || [ -z "$OUT_DIR" ]; then
  echo "Error: Missing required parameters"
  echo "Usage: $0 -ndk <ndk-path> -abi <abi> -api <api-level> -srcPath <openssl-src> -outDir <output-dir>"
  echo ""
  echo "Example:"
  echo "  $0 -ndk /path/to/ndk -abi arm64-v8a -api 28 -srcPath /path/to/openssl-3.2.0 -outDir /path/to/output"
  exit 1
fi

# Verify paths exist
if [ ! -d "$NDK" ]; then
  echo "Error: NDK path not found: $NDK"
  exit 1
fi

if [ ! -d "$SRC_PATH" ]; then
  echo "Error: OpenSSL source path not found: $SRC_PATH"
  exit 1
fi

# Map Android ABI to OpenSSL target architecture
case "$ABI" in
  arm64-v8a)
    OPENSSL_TARGET="android-arm64"
    ARCH="aarch64"
    ;;
  armeabi-v7a)
    OPENSSL_TARGET="android-arm"
    ARCH="armv7a"
    ;;
  x86)
    OPENSSL_TARGET="android-x86"
    ARCH="i686"
    ;;
  x86_64)
    OPENSSL_TARGET="android-x86_64"
    ARCH="x86_64"
    ;;
  *)
    echo "Error: Unsupported ABI: $ABI"
    echo "Supported ABIs: arm64-v8a, armeabi-v7a, x86, x86_64"
    exit 1
    ;;
esac

# Normalize ABI for directory names (replace - with _)
ABI_NORMALIZED="${ABI//-/_}"
BUILD_DIR="$OUT_DIR/build_$ABI_NORMALIZED"
INSTALL_DIR="$BUILD_DIR/installed"

# Cache check: skip build if already compiled successfully
if [ -f "$INSTALL_DIR/lib/libssl.a" ] && [ -f "$INSTALL_DIR/lib/libcrypto.a" ] && [ -d "$INSTALL_DIR/include/openssl" ]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "✓ OpenSSL already built (cache hit)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Install location: $INSTALL_DIR"
  echo "Libraries:"
  echo "  - $INSTALL_DIR/lib/libssl.a"
  echo "  - $INSTALL_DIR/lib/libcrypto.a"
  echo "Headers: $INSTALL_DIR/include/openssl"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 0
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "OpenSSL Build Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "NDK:           $NDK"
echo "ABI:           $ABI"
echo "API Level:     $API"
echo "OpenSSL Target: $OPENSSL_TARGET"
echo "Architecture:  $ARCH"
echo "Source:        $SRC_PATH"
echo "Build Dir:     $BUILD_DIR"
echo "Install Dir:   $INSTALL_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if sources are already cached (verify critical files exist)
SOURCES_CACHED=false
if [ -d "$BUILD_DIR" ] && \
   [ -f "$BUILD_DIR/Configure" ] && \
   [ -d "$BUILD_DIR/crypto" ] && \
   [ -d "$BUILD_DIR/util" ] && \
   [ -d "$BUILD_DIR/util/perl" ]; then
  # Verify that util/perl has the required module
  if [ -f "$BUILD_DIR/util/perl/OpenSSL/fallback.pm" ]; then
    SOURCES_CACHED=true
  fi
fi

# Clean previous build only if sources are not cached
if [ "$SOURCES_CACHED" = false ] && [ -d "$BUILD_DIR" ]; then
  echo "Cleaning previous build (incomplete cache detected)..."
  rm -rf "$BUILD_DIR"
fi

# Set up NDK toolchain paths
NDK_TOOLCHAIN="$NDK/toolchains/llvm/prebuilt"

# Detect host OS for NDK toolchain (Linux or macOS only)
if [ -d "$NDK_TOOLCHAIN/linux-x86_64" ]; then
  NDK_TOOLCHAIN="$NDK_TOOLCHAIN/linux-x86_64"
elif [ -d "$NDK_TOOLCHAIN/darwin-x86_64" ]; then
  NDK_TOOLCHAIN="$NDK_TOOLCHAIN/darwin-x86_64"
else
  echo "Error: Could not find NDK toolchain in $NDK_TOOLCHAIN"
  echo "  Expected linux-x86_64 or darwin-x86_64"
  exit 1
fi

echo "Using NDK toolchain: $NDK_TOOLCHAIN"

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

# Set up environment for cross-compilation
export ANDROID_NDK_ROOT="$NDK"
export ANDROID_NDK_HOME="$NDK"
# Do NOT set CROSS_COMPILE - it makes Configure search for gcc
# Instead, we'll pass compiler tools directly
export PATH="$NDK_TOOLCHAIN/bin:$PATH"

# Set compiler variables (OpenSSL Configure will use these)
export CC="$NDK_TOOLCHAIN/bin/${TARGET_PREFIX}${API}-clang"
export CXX="$NDK_TOOLCHAIN/bin/${TARGET_PREFIX}${API}-clang++"
export AR="$NDK_TOOLCHAIN/bin/llvm-ar"
export RANLIB="$NDK_TOOLCHAIN/bin/llvm-ranlib"
export STRIP="$NDK_TOOLCHAIN/bin/llvm-strip"
export NM="$NDK_TOOLCHAIN/bin/llvm-nm"

# Verify compiler exists
if [ ! -f "$CC" ]; then
  echo "Error: Compiler not found: $CC"
  echo "Verify NDK installation and API level"
  exit 1
fi

echo "Compiler: $CC"
echo "AR: $AR"
echo "RANLIB: $RANLIB"
echo "STRIP: $STRIP"

# Copy sources only if not cached
if [ "$SOURCES_CACHED" = true ]; then
  echo ""
  echo "✓ OpenSSL sources already cached, skipping copy..."
else
  echo ""
  echo "Copying OpenSSL sources to build directory (this may take a few minutes)..."
  
  # Create build directory
  mkdir -p "$BUILD_DIR"
  
  # Copy with progress indicator
  if command -v rsync >/dev/null 2>&1; then
    # Use rsync for progress if available
    rsync -a --info=progress2 "$SRC_PATH/" "$BUILD_DIR/"
  else
    # Use cp with manual progress indicator
    total_files=$(find "$SRC_PATH" -type f 2>/dev/null | wc -l)
    current=0
    find "$SRC_PATH" -type f | while read -r file; do
      rel_path="${file#$SRC_PATH/}"
      mkdir -p "$BUILD_DIR/$(dirname "$rel_path")"
      cp "$file" "$BUILD_DIR/$rel_path"
      current=$((current + 1))
      if [ $((current % 100)) -eq 0 ]; then
        percent=$((current * 100 / total_files))
        printf "\rProgress: [%-50s] %d%% (%d/%d files)" "$(printf '#%.0s' $(seq 1 $((percent/2))))" "$percent" "$current" "$total_files"
      fi
    done
    echo ""
  fi
  echo "✓ Sources copied successfully"
fi

# Create temporary wrapper directory for compiler tools (before changing directory)
WRAPPER_DIR="$BUILD_DIR/.toolchain_wrappers"
mkdir -p "$WRAPPER_DIR"

# Create wrapper scripts that point to clang tools
# OpenSSL Configure searches for tools with the target prefix, so we create wrappers
cat > "$WRAPPER_DIR/${TARGET_PREFIX}-gcc" <<EOF
#!/bin/sh
exec "$CC" "\$@"
EOF

cat > "$WRAPPER_DIR/${TARGET_PREFIX}-g++" <<EOF
#!/bin/sh
exec "$CXX" "\$@"
EOF

cat > "$WRAPPER_DIR/${TARGET_PREFIX}-ar" <<EOF
#!/bin/sh
exec "$AR" "\$@"
EOF

cat > "$WRAPPER_DIR/${TARGET_PREFIX}-ranlib" <<EOF
#!/bin/sh
exec "$RANLIB" "\$@"
EOF

cat > "$WRAPPER_DIR/${TARGET_PREFIX}-strip" <<EOF
#!/bin/sh
exec "$STRIP" "\$@"
EOF

cat > "$WRAPPER_DIR/${TARGET_PREFIX}-nm" <<EOF
#!/bin/sh
exec "$NM" "\$@"
EOF

# Make wrappers executable
chmod +x "$WRAPPER_DIR"/*

# Add wrapper directory to PATH (before NDK toolchain so it takes precedence)
export PATH="$WRAPPER_DIR:$PATH"

# Verify wrapper is accessible
if ! command -v "${TARGET_PREFIX}-gcc" >/dev/null 2>&1; then
  echo "Error: Wrapper ${TARGET_PREFIX}-gcc not found in PATH"
  echo "PATH: $PATH"
  exit 1
fi

echo "Wrapper created: $(command -v ${TARGET_PREFIX}-gcc)"

# Change to build directory
cd "$BUILD_DIR"

# Apply vcpkg-style patch to disable automatic NDK detection
# This prevents Configure from searching for "NDK aarch64-linux-android-gcc"
ANDROID_CONF="$BUILD_DIR/Configurations/15-android.conf"
if [ -f "$ANDROID_CONF" ] && ! grep -q "^            if (0) {" "$ANDROID_CONF"; then
  echo "Applying patch to disable automatic NDK detection (vcpkg-style)..."
  # Apply the same patch that vcpkg uses: wrap the NDK detection in "if (0) {"
  # This matches the vcpkg patch exactly
  sed -i '/^            # see if there is NDK clang on \$PATH/a\            if (0) {' "$ANDROID_CONF"
  # Close the if(0) block before android_ndk definition
  sed -i '/^            \$android_ndk = {/i\            }' "$ANDROID_CONF"
fi

# Configure OpenSSL
echo ""
echo "[1/3] Configuring OpenSSL..."

# Export all compiler tools so Configure can find them
export CC
export CXX
export AR
export RANLIB
export STRIP
export NM

# Also export wrappers as the expected gcc names for Configure
export "${TARGET_PREFIX//-/_}_GCC"="$(command -v ${TARGET_PREFIX}-gcc 2>/dev/null || echo "$WRAPPER_DIR/${TARGET_PREFIX}-gcc")"

# Verify wrappers are accessible
echo "Verifying wrapper accessibility..."
if command -v "${TARGET_PREFIX}-gcc" >/dev/null 2>&1; then
  echo "  ✓ Wrapper found: $(command -v ${TARGET_PREFIX}-gcc)"
  # Test that wrapper actually works
  if "$(command -v ${TARGET_PREFIX}-gcc)" --version >/dev/null 2>&1; then
    echo "  ✓ Wrapper is executable"
  else
    echo "  ✗ Wrapper exists but is not executable or broken"
    exit 1
  fi
else
  echo "  ✗ Wrapper not found in PATH"
  exit 1
fi

# Configure OpenSSL
# Pass compiler tools directly - don't use --cross-compile-prefix as it causes path issues
# After patching, Configure will use the exported CC/AR/etc variables directly
./Configure "$OPENSSL_TARGET" \
  --release \
  -D__ANDROID_API__=$API \
  no-shared \
  --prefix="$INSTALL_DIR" \
  --openssldir="$INSTALL_DIR" \
  CC="$CC" \
  CXX="$CXX" \
  AR="$AR" \
  RANLIB="$RANLIB" \
  NM="$NM" \
  STRIP="$STRIP" \
  no-asm

if [ $? -ne 0 ]; then
  echo "Error: OpenSSL Configure failed"
  exit 1
fi

# Fix Makefile: Replace CROSS_COMPILE variable usage with actual compiler paths
# Configure generates CC=$(CROSS_COMPILE)/path which expands to aarch64-linux-android-/path
# We need to replace the entire assignment with the actual compiler path
echo "Fixing Makefile compiler paths..."
sed -i "s|^CC=\$(CROSS_COMPILE)/.*|CC=$CC|" "$BUILD_DIR/Makefile"
sed -i "s|^CXX=\$(CROSS_COMPILE)/.*|CXX=$CXX|" "$BUILD_DIR/Makefile"
sed -i "s|^AR=\$(CROSS_COMPILE).*|AR=$AR|" "$BUILD_DIR/Makefile"
sed -i "s|^RANLIB=\$(CROSS_COMPILE).*|RANLIB=$RANLIB|" "$BUILD_DIR/Makefile"
sed -i "s|^NM=\$(CROSS_COMPILE).*|NM=$NM|" "$BUILD_DIR/Makefile"
sed -i "s|^STRIP=\$(CROSS_COMPILE).*|STRIP=$STRIP|" "$BUILD_DIR/Makefile"

# Build OpenSSL
echo ""
echo "[2/3] Building OpenSSL (this may take 10-15 minutes)..."
NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
make -j$NPROC

if [ $? -ne 0 ]; then
  echo "Error: OpenSSL build failed"
  exit 1
fi

# Install OpenSSL
echo ""
echo "[3/3] Installing OpenSSL..."
make install_sw

if [ $? -ne 0 ]; then
  echo "Error: OpenSSL install failed"
  exit 1
fi

# Verify installation
echo ""
echo "Verifying installation..."
if [ ! -f "$INSTALL_DIR/lib/libssl.a" ] || [ ! -f "$INSTALL_DIR/lib/libcrypto.a" ]; then
  echo "Error: OpenSSL libraries not found in $INSTALL_DIR/lib"
  exit 1
fi

if [ ! -d "$INSTALL_DIR/include/openssl" ]; then
  echo "Error: OpenSSL headers not found in $INSTALL_DIR/include"
  exit 1
fi

# Clean up wrapper directory
if [ -d "$WRAPPER_DIR" ]; then
  rm -rf "$WRAPPER_DIR"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ OpenSSL build completed successfully"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Install location: $INSTALL_DIR"
echo "Libraries:"
echo "  - $INSTALL_DIR/lib/libssl.a"
echo "  - $INSTALL_DIR/lib/libcrypto.a"
echo "Headers: $INSTALL_DIR/include/openssl"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
