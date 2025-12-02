param(
    [string]$ndk,
    [string]$abi = "arm64-v8a",
    [int]$api = 24,
    [string]$srcPath,
    [string]$outDir = "$(Join-Path $PSScriptRoot 'out' )"
)

if (-not $ndk) {
    Write-Error "Please pass -ndk <path-to-ndk> or set environment variable NDK_HOME"
    exit 1
}

if (-not (Test-Path $srcPath)) {
    Write-Error "OpenSSL source path not found: $srcPath"
    exit 1
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$buildDir = Join-Path $outDir "build_$abi"
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

$toolchain = Join-Path $ndk "build/cmake/android.toolchain.cmake"
if (-not (Test-Path $toolchain)) { Write-Error "CMake toolchain not found at $toolchain"; exit 1 }

Push-Location $buildDir

Write-Host "Configuring OpenSSL build for ABI=$abi API=$api"

cmake -G "Ninja" `
    -DCMAKE_TOOLCHAIN_FILE="$toolchain" `
    -DANDROID_ABI="$abi" `
    -DANDROID_PLATFORM="android-$api" `
    -DCMAKE_BUILD_TYPE=Release `
    -DOPENSSL_USE_STATIC_LIBS=ON `
    -S "$srcPath" -B .

cmake --build . --config Release -- -j

Write-Host "OpenSSL build finished. Artifacts in $buildDir"
Pop-Location
