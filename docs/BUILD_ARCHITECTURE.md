# Build Architecture

## Overview

This document explains the build system architecture for Telegram Cloud Android, which uses **PowerShell as an orchestrator** for native shell scripts.

## Architecture Diagram

```
Windows (PowerShell)
  ├─ build-complete.ps1
  │   ├─ Detects: bash, NDK, SDK
  │   ├─ Downloads dependencies
  │   └─ Calls individual build scripts
  │
  ├─ build_openssl_android.ps1 ─────┐
  ├─ build_libcurl_android.ps1 ─────┼─ PowerShell Orchestrators
  └─ build_sqlcipher_android.ps1 ───┘
       │
       ├─ Detect bash (Git for Windows / WSL)
       ├─ Convert Windows paths → Unix paths
       └─ Execute: bash build_*.sh
            │
            ├─ build_openssl_android.sh ─────┐
            ├─ build_libcurl_android.sh ─────┼─ Native Shell Scripts
            └─ build_sqlcipher_android.sh ───┘
                 │
                 └─ Cross-compile for Android using NDK

Linux/macOS (Bash)
  └─ build-complete.sh
      ├─ build_openssl_android.sh
      ├─ build_libcurl_android.sh
      └─ build_sqlcipher_android.sh
```

## Why This Approach?

### Single Source of Truth
- **Shell scripts** contain all build logic
- Work identically on Windows (bash), WSL, Linux, and macOS
- No duplication between PowerShell and shell scripts

### Simplicity
- PowerShell scripts are **~150 lines** (vs ~440 lines before)
- Easy to understand and maintain
- Clear separation of concerns

### Cross-Platform
- Same shell scripts work everywhere
- PowerShell only handles Windows-specific concerns (path conversion, bash detection)
- Linux/macOS users can run shell scripts directly

### Maintainability
- Adding new dependencies: just create one shell script
- Debugging: check shell script logs, not complex PowerShell logic
- Testing: shell scripts can be tested independently

## Components

### 1. PowerShell Orchestrators

Located in: `telegram-cloud-cpp/third_party/android_build_scripts/*.ps1`

**Purpose:** Detect bash and execute shell scripts on Windows

**Responsibilities:**
- Validate input parameters
- Find bash (Git for Windows or WSL)
- Convert Windows paths to Unix format
- Execute corresponding shell script
- Check exit codes and report errors

**Example:**
```powershell
# build_openssl_android.ps1
param([string]$ndk, [string]$srcPath, [string]$outDir)

# 1. Find bash
$bashPath = Find-Bash

# 2. Convert paths
$ndkUnix = Convert-WindowsPathToUnix $ndk

# 3. Execute shell script
& $bashPath build_openssl_android.sh -ndk $ndkUnix -srcPath $srcPathUnix -outDir $outDirUnix

# 4. Check result
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
```

### 2. Native Shell Scripts

Located in: `telegram-cloud-cpp/third_party/android_build_scripts/*.sh`

**Purpose:** Cross-compile native libraries for Android

**Responsibilities:**
- Parse command-line arguments (flag-based: `-ndk`, `-abi`, etc.)
- Validate paths and parameters
- Set up NDK environment variables
- Configure and build the library
- Install to output directory
- Verify installation

**Example:**
```bash
# build_openssl_android.sh
while [[ $# -gt 0 ]]; do
  case $1 in
    -ndk) NDK="$2"; shift 2 ;;
    -abi) ABI="$2"; shift 2 ;;
    # ... more arguments
  esac
done

# Set up NDK environment
export CC="$NDK_TOOLCHAIN/bin/${TARGET_PREFIX}${API}-clang"
export PATH="$NDK_TOOLCHAIN/bin:$PATH"

# Configure and build
./Configure android-arm64 -D__ANDROID_API__=$API no-shared
make -j$(nproc)
make install_sw
```

### 3. Main Build Script

Located in: `scripts/powershell/build-complete.ps1` (Windows) or `scripts/shell/build-complete.sh` (Linux/macOS)

**Purpose:** Orchestrate the complete build process

**Steps:**
1. Verify requirements (bash, NDK, SDK)
2. Download dependencies (OpenSSL, libcurl, SQLCipher)
3. Build each dependency in order
4. Update `android/local.properties`
5. Build APK with Gradle

### 4. Utility Scripts

#### `check-requirements.ps1`
Validates all prerequisites before building:
- Bash availability
- Android SDK + NDK
- Disk space (5GB minimum)
- Write permissions

#### `setup-dependencies.ps1`
Downloads source code for:
- OpenSSL 3.2.0
- libcurl 8.7.1
- SQLCipher (latest)

## Path Conversion

Windows paths must be converted to Unix format for bash:

| Windows Path | Unix Path |
|--------------|-----------|
| `C:\Android\ndk` | `/c/android/ndk` |
| `D:\sources\openssl-3.2.0` | `/d/sources/openssl-3.2.0` |
| `C:\Users\Name\builds` | `/c/users/name/builds` |

**Implementation:**
```powershell
function Convert-WindowsPathToUnix {
    param([string]$path)
    
    # Convert backslashes to forward slashes
    $path = $path -replace '\\', '/'
    
    # Convert drive letter (C:\ → /c/)
    $path = $path -replace '^([A-Z]):', '/$1'
    
    # Lowercase drive letter
    return $path.ToLower()
}
```

## Build Methods

### OpenSSL
**Method:** Configure + make (native OpenSSL build system)

**Why not CMake?** OpenSSL doesn't officially support CMake. The correct method is:
```bash
./Configure android-arm64 -D__ANDROID_API__=28 no-shared
make -j$(nproc)
make install_sw
```

**Key Points:**
- Must copy sources to build directory (configures in-place)
- Requires perl and make (included in Git for Windows)
- Set `CC`, `AR`, `RANLIB` environment variables for NDK

### libcurl
**Method:** CMake (officially supported)

```bash
cmake -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DCURL_USE_OPENSSL=ON \
  -DOPENSSL_ROOT_DIR=/path/to/openssl
```

### SQLCipher
**Method:** CMake (recommended for Android)

```bash
cmake -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake \
  -DSQLITE_HAS_CODEC=ON \
  -DSQLCIPHER_CRYPTO_OPENSSL=ON
```

## Debugging Guide

### Build Fails: "Bash not found"

**Solution:**
```powershell
# Install Git for Windows
# https://git-scm.com/download/win

# Or use WSL
wsl --install
```

### Build Fails: "Compiler not found"

**Check:**
1. NDK is installed: `$env:ANDROID_NDK_HOME`
2. API level matches NDK: `ls "$NDK/toolchains/llvm/prebuilt/windows-x86_64/bin"`
3. Compiler exists: `aarch64-linux-android28-clang.cmd`

**Solution:**
- Install NDK r25c from Android Studio SDK Manager
- Or set correct API level (21-33 supported by NDK r25c)

### Build Fails: "OpenSSL Configure failed"

**Enable verbose mode:**
```powershell
.\build_openssl_android.ps1 -ndk $NDK -srcPath $SRC -outDir $OUT -Verbose
```

**Check log:**
- `build-openssl.log` - PowerShell orchestrator log
- Build directory - OpenSSL Configure output

**Common issues:**
- Perl not found → Install Git for Windows
- Make not found → Install Git for Windows
- Wrong architecture → Check ABI parameter

### Build Fails: "Permission denied"

**Solution:**
```powershell
# Run PowerShell as Administrator
# Or check antivirus isn't blocking

# Verify write permissions
.\scripts\powershell\check-requirements.ps1
```

### Want to see exact commands?

**Use verbose mode:**
```powershell
.\scripts\powershell\build-complete.ps1 -Verbose
```

This will:
- Log all commands to `build.log`
- Show environment variables
- Display path conversions
- Show exact bash commands executed

## Adding New Dependencies

To add a new native library:

### 1. Create Shell Script

`build_newlib_android.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -ndk) NDK="$2"; shift 2 ;;
    -abi) ABI="$2"; shift 2 ;;
    -api) API="$2"; shift 2 ;;
    -srcPath) SRC_PATH="$2"; shift 2 ;;
    -outDir) OUT_DIR="$2"; shift 2 ;;
  esac
done

# Validate parameters
if [ -z "$NDK" ] || [ -z "$SRC_PATH" ] || [ -z "$OUT_DIR" ]; then
  echo "Error: Missing required parameters"
  exit 1
fi

# Build logic here
# ...
```

### 2. Create PowerShell Orchestrator

`build_newlib_android.ps1`:
```powershell
param([string]$ndk, [string]$srcPath, [string]$outDir)

$ErrorActionPreference = "Stop"

# Find bash
$bashPath = Find-Bash

# Convert paths
$ndkUnix = Convert-WindowsPathToUnix $ndk
$srcPathUnix = Convert-WindowsPathToUnix $srcPath
$outDirUnix = Convert-WindowsPathToUnix $outDir

# Execute shell script
$shellScript = Join-Path $PSScriptRoot "build_newlib_android.sh"
$shellScriptUnix = Convert-WindowsPathToUnix $shellScript

& $bashPath $shellScriptUnix -ndk $ndkUnix -srcPath $srcPathUnix -outDir $outDirUnix

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
```

### 3. Add to build-complete.ps1

```powershell
# Compilar NewLib
Write-Host "[4.4/4.4] Compilando NewLib..."
& "$projectRoot\telegram-cloud-cpp\third_party\android_build_scripts\build_newlib_android.ps1" `
    -ndk $NDK `
    -abi $ABI `
    -api $API `
    -srcPath "$DEPS_DIR\newlib-1.0.0" `
    -outDir "$BUILD_DIR\newlib"
```

### 4. Update local.properties

```powershell
$propsContent = @"
native.newlib.$ABI=$BUILD_DIR\newlib\build_$ABI_NORMALIZED\installed
"@
Add-Content -Path $localPropsPath -Value $propsContent
```

## Testing

### Unit Tests

Run `check-requirements.ps1` to verify environment:
```powershell
.\scripts\powershell\check-requirements.ps1
```

### Integration Tests

Test individual libraries:
```powershell
# Test OpenSSL
.\telegram-cloud-cpp\third_party\android_build_scripts\build_openssl_android.ps1 `
    -ndk $NDK -abi arm64-v8a -api 28 `
    -srcPath $SRC -outDir $OUT -Verbose

# Verify output
ls $OUT\build_arm64_v8a\installed\lib\*.a
ls $OUT\build_arm64_v8a\installed\include\openssl\*.h
```

### Full Build Test

```powershell
# Clean build
rm -r $env:USERPROFILE\android-native-builds -Force

# Run complete build
.\scripts\powershell\build-complete.ps1

# Verify APK
ls android\app\build\outputs\apk\release\app-release.apk
```

## Performance

### Build Times (on modern hardware)

| Component | Time | Notes |
|-----------|------|-------|
| OpenSSL | 10-15 min | Depends on CPU cores |
| libcurl | 2-3 min | Faster with CMake |
| SQLCipher | 1-2 min | Small codebase |
| **Total** | **15-20 min** | First build only |

### Optimization Tips

1. **Use SSD** for source and build directories
2. **More CPU cores** = faster OpenSSL build
3. **Incremental builds** are much faster (don't clean unless needed)
4. **Parallel builds** are automatic (`make -j$(nproc)`)

## Troubleshooting Checklist

- [ ] Bash is installed and in PATH
- [ ] Git for Windows includes perl and make
- [ ] Android NDK r25c is installed
- [ ] NDK path is correct in environment variables
- [ ] Source code is downloaded
- [ ] Sufficient disk space (5GB+)
- [ ] Antivirus isn't blocking build tools
- [ ] Running PowerShell as Administrator (if permission errors)
- [ ] Paths don't contain spaces or special characters

## References

- [OpenSSL Compilation Guide](https://wiki.openssl.org/index.php/Compilation_and_Installation)
- [Android NDK Documentation](https://developer.android.com/ndk/guides)
- [CMake Android Toolchain](https://developer.android.com/ndk/guides/cmake)
- [Git for Windows](https://git-scm.com/download/win)
