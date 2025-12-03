param(
    [string]$ndk,
    [string]$abi = "arm64-v8a",
    [int]$api = 28,
    [string]$opensslDir,
    [string]$srcPath,
    [string]$outDir
)

$ErrorActionPreference = "Stop"

# Validate required parameters
if (-not $ndk -or -not $opensslDir -or -not $srcPath -or -not $outDir) {
    Write-Error "Usage: -ndk <ndk-path> -opensslDir <openssl-build-dir> -srcPath <sqlcipher-source> -outDir <output-dir>"
    Write-Host "Example: .\build_sqlcipher_android.ps1 -ndk C:\Android\ndk\25.2.9519653 -opensslDir C:\builds\openssl\build_arm64_v8a -srcPath C:\sources\sqlcipher -outDir C:\builds\sqlcipher"
    exit 1
}

if (-not (Test-Path $srcPath)) {
    Write-Error "SQLCipher source not found: $srcPath"
    exit 1
}

if (-not (Test-Path $ndk)) {
    Write-Error "NDK path not found: $ndk"
    exit 1
}

if (-not (Test-Path $opensslDir)) {
    Write-Error "OpenSSL build directory not found: $opensslDir"
    Write-Host "Make sure to build OpenSSL first."
    exit 1
}

# Map ABI to compiler target
$targetMap = @{
    "arm64-v8a" = "aarch64-linux-android"
    "armeabi-v7a" = "armv7a-linux-androideabi"
    "x86" = "i686-linux-android"
    "x86_64" = "x86_64-linux-android"
}

if (-not $targetMap.ContainsKey($abi)) {
    Write-Error "Unsupported ABI: $abi. Use: arm64-v8a, armeabi-v7a, x86, x86_64"
    exit 1
}

$target = $targetMap[$abi]
$abiNormalized = $abi -replace "-", "_"
$buildDir = Join-Path $outDir "build_$abiNormalized"

# Clean previous build
if (Test-Path $buildDir) {
    Write-Host "Cleaning previous build..."
    Remove-Item -Recurse -Force $buildDir
}

New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

# Copy sources to build dir
Write-Host "Copying SQLCipher sources..."
Copy-Item -Recurse -Force "$srcPath/*" $buildDir

$ndkToolchain = Join-Path $ndk "toolchains/llvm/prebuilt/windows-x86_64"
$cc = Join-Path $ndkToolchain "bin/$target$api-clang.cmd"
$ar = Join-Path $ndkToolchain "bin/llvm-ar.exe"
$ranlib = Join-Path $ndkToolchain "bin/llvm-ranlib.exe"

if (-not (Test-Path $cc)) {
    Write-Error "Compiler not found: $cc"
    exit 1
}

$PATH_BACKUP = $env:PATH
$env:PATH = "$ndkToolchain/bin;$env:PATH"

Push-Location $buildDir

try {
    Write-Host "Configuring SQLCipher for $abi (API $api)..."
    
    # Check if bash is available
    $bashPath = Get-Command bash -ErrorAction SilentlyContinue
    if (-not $bashPath) {
        throw @"
Bash is not installed. SQLCipher requires bash to build on Windows.

Options:
1. Install Git for Windows (includes bash): https://git-scm.com/download/win
2. Use WSL: wsl --install and build from Linux
3. Use MSYS2: https://www.msys2.org/

After installing, restart PowerShell and run this script again.
"@
    }
    
    Write-Host "✓ Bash found: $($bashPath.Source)"
    
    $installDir = Join-Path $buildDir "installed"
    
    # Create configuration script for bash
    $configScript = @"
#!/bin/bash
export CC="$($cc -replace '\\', '/')"
export AR="$($ar -replace '\\', '/')"
export RANLIB="$($ranlib -replace '\\', '/')"
export CFLAGS="-fPIC -DSQLITE_HAS_CODEC -I$($opensslDir -replace '\\', '/')/include"
export LDFLAGS="-L$($opensslDir -replace '\\', '/')/lib"
export LIBS="-lcrypto"

./configure \
    --host=$target \
    --enable-tempstore=yes \
    --disable-tcl \
    --enable-static \
    --disable-shared \
    --prefix=$($installDir -replace '\\', '/')

make -j$([Environment]::ProcessorCount)
make install
"@
    
    $configScript | Out-File -FilePath "build_script.sh" -Encoding ASCII
    
    Write-Host "Running configure and make..."
    & bash ./build_script.sh
    
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed with exit code: $LASTEXITCODE"
    }
    
    Write-Host "`nSQLCipher build finished successfully"
    Write-Host "Location: $installDir"
    Write-Host "Include: $installDir/include"
    Write-Host "Libs: $installDir/lib"
    
} catch {
    Write-Error "Error building SQLCipher: $_"
    Pop-Location
    $env:PATH = $PATH_BACKUP
    exit 1
}

Pop-Location
$env:PATH = $PATH_BACKUP
