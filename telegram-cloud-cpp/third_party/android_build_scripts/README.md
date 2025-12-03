Android build scripts for native dependencies
===========================================

This folder contains helper scripts to cross-compile OpenSSL, libcurl and SQLCipher for Android using the Android NDK. **These scripts are designed for Linux/macOS only and use Linux NDK.**

High-level notes / requirements
- **Linux or macOS** (autobuild only supports Linux/macOS)
- Android NDK installed (recommended r25c or r26) - **Linux NDK version**
- Android SDK (for general Android builds)
- CMake 3.22+ (NDK includes a CMake version; scripts use NDK's toolchain file)
- Bash shell
- Internet access to clone source repositories (or download tarballs and set env vars to point to them)
- Perl (required for OpenSSL Configure script)

Overview of scripts
- `build_openssl_android.sh`
  Builds OpenSSL for a given ABI and API level using the Linux NDK toolchain (Configure + make).

- `build_libcurl_android.sh`
  Builds libcurl linking against the OpenSSL build output using CMake.

- `build_sqlcipher_android.sh`
  Builds SQLCipher (sqlite with codec) for Android and links to OpenSSL if requested using CMake.

Usage (Linux/macOS example)
1. Set environment variables (adjust paths for your machine):

```bash
export NDK="$HOME/android-sdk/ndk/26.3.11579264"
export API=24
export ABI="arm64-v8a"
export OUT="$HOME/android-native-builds"
```

2. Build OpenSSL:

```bash
./build_openssl_android.sh \
  -ndk "$NDK" \
  -abi "$ABI" \
  -api $API \
  -srcPath "$HOME/android-native-sources/openssl-3.2.0" \
  -outDir "$OUT/openssl"
```

3. Build libcurl:

```bash
./build_libcurl_android.sh \
  -ndk "$NDK" \
  -abi "$ABI" \
  -api $API \
  -opensslDir "$OUT/openssl/build_arm64_v8a/installed" \
  -srcPath "$HOME/android-native-sources/curl-8.7.1" \
  -outDir "$OUT/libcurl"
```

4. Build SQLCipher:

```bash
./build_sqlcipher_android.sh \
  -ndk "$NDK" \
  -abi "$ABI" \
  -api $API \
  -opensslDir "$OUT/openssl/build_arm64_v8a/installed" \
  -srcPath "$HOME/android-native-sources/sqlcipher" \
  -outDir "$OUT/sqlcipher"
```

After building, point your Android/CMake configuration to the produced library directories and headers. Example CMake options:

```cmake
-DOPENSSL_ROOT_DIR=<out>/openssl/build_arm64_v8a/installed
-DCURL_ROOT=<out>/libcurl/build_arm64_v8a/installed
-DSQLCIPHER_ROOT=<out>/sqlcipher/build_arm64_v8a/installed
```

Notes and troubleshooting
- **Linux NDK required**: These scripts are designed for Linux/macOS with Linux NDK only
- For reproducibility, pin OpenSSL/libcurl/sqlcipher versions matching your desktop build where possible
- Some projects include Android-specific patches or CMake helper files; consult their README if the CMake approach fails
- OpenSSL uses Configure + make (not CMake) as per OpenSSL's official build system 
