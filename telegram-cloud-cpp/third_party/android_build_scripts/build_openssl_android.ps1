param(
    [string]$ndk,
    [string]$abi = "arm64-v8a",
    [int]$api = 24,
    [string]$srcPath,
    [string]$outDir
)

$ErrorActionPreference = "Stop"

# Validate required parameters
if (-not $ndk -or -not $srcPath -or -not $outDir) {
    Write-Error "Usage: -ndk <ndk-path> -srcPath <openssl-source> -outDir <output-dir>"
    Write-Host "Example: .\build_openssl_android.ps1 -ndk C:\Android\ndk\25.2.9519653 -srcPath C:\sources\openssl-3.2.0 -outDir C:\builds\openssl"
    exit 1
}

if (-not (Test-Path $srcPath)) {
    Write-Error "OpenSSL source path not found: $srcPath"
    exit 1
}

if (-not (Test-Path $ndk)) {
    Write-Error "NDK path not found: $ndk"
    exit 1
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$buildDir = Join-Path $outDir "build_$abi"
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

$toolchain = Join-Path $ndk "build/cmake/android.toolchain.cmake"
if (-not (Test-Path $toolchain)) {
    Write-Error "CMake toolchain not found at $toolchain"
    exit 1
}

Push-Location $buildDir

try {
    Write-Host "Configuring OpenSSL build for ABI=$abi API=$api"
    
    cmake -G "Ninja" `
        -DCMAKE_TOOLCHAIN_FILE="$toolchain" `
        -DANDROID_ABI="$abi" `
        -DANDROID_PLATFORM="android-$api" `
        -DCMAKE_BUILD_TYPE=Release `
        -DOPENSSL_USE_STATIC_LIBS=ON `
        -S "$srcPath" -B .
    
    if ($LASTEXITCODE -ne 0) {
        throw "CMake configuration failed with exit code: $LASTEXITCODE"
    }
    
    Write-Host "Building OpenSSL..."
    cmake --build . --config Release -- -j
    
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed with exit code: $LASTEXITCODE"
    }
    
    Write-Host "`nOpenSSL build finished successfully"
    Write-Host "Artifacts in: $buildDir"
    
} catch {
    Write-Error "Error building OpenSSL: $_"
    Pop-Location
    exit 1
}

Pop-Location
