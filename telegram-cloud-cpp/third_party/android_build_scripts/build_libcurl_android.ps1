param(
    [string]$ndk,
    [string]$abi = "arm64-v8a",
    [int]$api = 24,
    [string]$opensslDir,
    [string]$srcPath,
    [string]$outDir = "$(Join-Path $PSScriptRoot 'out' )"
)

if (-not $ndk) { Write-Error "Please pass -ndk <path-to-ndk>"; exit 1 }
if (-not (Test-Path $srcPath)) { Write-Error "curl source path not found: $srcPath"; exit 1 }
if (-not (Test-Path $opensslDir)) { Write-Error "OpenSSL dir not found: $opensslDir"; exit 1 }

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$buildDir = Join-Path $outDir "build_$abi"
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

$toolchain = Join-Path $ndk "build/cmake/android.toolchain.cmake"
if (-not (Test-Path $toolchain)) { Write-Error "CMake toolchain not found at $toolchain"; exit 1 }

Push-Location $buildDir

Write-Host "Configuring libcurl build for ABI=$abi API=$api, OPENSSL_ROOT=$opensslDir"

cmake -G "Ninja" `
    -DCMAKE_TOOLCHAIN_FILE="$toolchain" `
    -DANDROID_ABI="$abi" `
    -DANDROID_PLATFORM="android-$api" `
    -DCMAKE_BUILD_TYPE=Release `
    -DHTTP_ONLY=OFF `
    -DCURL_USE_OPENSSL=ON `
    -DOPENSSL_ROOT_DIR="$opensslDir" `
    -DCMAKE_INSTALL_PREFIX="$buildDir/install" `
    -S "$srcPath" -B .

cmake --build . --config Release -- -j
cmake --install . --config Release

Write-Host "libcurl build finished. Installed to $buildDir/install"
Pop-Location
