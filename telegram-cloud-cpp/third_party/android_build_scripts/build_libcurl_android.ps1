param(
    [string]$ndk,
    [string]$abi = "arm64-v8a",
    [int]$api = 28,
    [string]$opensslDir,
    [string]$srcPath,
    [string]$outDir
)

$ErrorActionPreference = "Stop"

if (-not $ndk -or -not $opensslDir -or -not $srcPath -or -not $outDir) {
    Write-Error "Usage: -ndk <ndk-path> -opensslDir <openssl-build-dir> -srcPath <curl-source> -outDir <output-dir>"
    Write-Host "Example: .\build_libcurl_android.ps1 -ndk C:\Android\ndk\25.2.9519653 -opensslDir C:\builds\openssl\build_arm64_v8a -srcPath C:\sources\curl-8.7.1 -outDir C:\builds\libcurl"
    exit 1
}

if (-not (Test-Path $srcPath)) {
    Write-Error "libcurl source no encontrado: $srcPath"
    exit 1
}

if (-not (Test-Path "$opensslDir/installed")) {
    Write-Error "OpenSSL compilado no encontrado en: $opensslDir/installed"
    Write-Host "Asegúrate de compilar OpenSSL primero."
    exit 1
}

$abiNormalized = $abi -replace "-", "_"
$buildDir = Join-Path $outDir "build_$abiNormalized"

# Limpiar build anterior
if (Test-Path $buildDir) {
    Write-Host "Limpiando build anterior..."
    Remove-Item -Recurse -Force $buildDir
}

New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
$installDir = Join-Path $buildDir "installed"
New-Item -ItemType Directory -Force -Path $installDir | Out-Null

$toolchain = Join-Path $ndk "build/cmake/android.toolchain.cmake"
if (-not (Test-Path $toolchain)) {
    Write-Error "CMake toolchain no encontrado: $toolchain"
    exit 1
}

# Verificar CMake
$cmakePath = Get-Command cmake -ErrorAction SilentlyContinue
if (-not $cmakePath) {
    Write-Error "CMake no está instalado. Instálalo desde: https://cmake.org/download/"
    exit 1
}

Push-Location $buildDir

try {
    Write-Host "Configurando libcurl para $abi (API $api)..."
    Write-Host "OpenSSL: $opensslDir/installed"
    
    $cmakeArgs = @(
        "-G", "Ninja",
        "-DCMAKE_TOOLCHAIN_FILE=$toolchain",
        "-DANDROID_ABI=$abi",
        "-DANDROID_PLATFORM=android-$api",
        "-DCMAKE_BUILD_TYPE=Release",
        "-DCMAKE_INSTALL_PREFIX=$installDir",
        "-DBUILD_CURL_EXE=OFF",
        "-DBUILD_SHARED_LIBS=OFF",
        "-DCURL_STATICLIB=ON",
        "-DCURL_USE_OPENSSL=ON",
        "-DOPENSSL_ROOT_DIR=$opensslDir/installed",
        "-DOPENSSL_INCLUDE_DIR=$opensslDir/installed/include",
        "-DOPENSSL_CRYPTO_LIBRARY=$opensslDir/installed/lib/libcrypto.a",
        "-DOPENSSL_SSL_LIBRARY=$opensslDir/installed/lib/libssl.a",
        "-DCURL_DISABLE_LDAP=ON",
        "-DCURL_DISABLE_LDAPS=ON",
        "-DCURL_CA_BUNDLE=none",
        "-DCURL_CA_PATH=none",
        "-S", $srcPath,
        "-B", "."
    )
    
    & cmake @cmakeArgs
    
    if ($LASTEXITCODE -ne 0) {
        throw "CMake configure falló con código: $LASTEXITCODE"
    }
    
    Write-Host "Compilando libcurl..."
    & cmake --build . --config Release --parallel $([Environment]::ProcessorCount)
    
    if ($LASTEXITCODE -ne 0) {
        throw "Build falló con código: $LASTEXITCODE"
    }
    
    Write-Host "Instalando libcurl..."
    & cmake --install . --config Release
    
    if ($LASTEXITCODE -ne 0) {
        throw "Install falló con código: $LASTEXITCODE"
    }
    
    Write-Host "`n✓ libcurl compilado exitosamente"
    Write-Host "Ubicación: $installDir"
    Write-Host "Include: $installDir/include"
    Write-Host "Libs: $installDir/lib"
    
} catch {
    Write-Error "Error compilando libcurl: $_"
    exit 1
} finally {
    Pop-Location
}
