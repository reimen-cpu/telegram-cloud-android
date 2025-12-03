param(
    [string]$ndk,
    [string]$abi = "arm64-v8a",
    [int]$api = 28,
    [string]$opensslDir,
    [string]$srcPath,
    [string]$outDir
)

$ErrorActionPreference = "Stop"

if (-not $ndk -or -not $opensslDir -or -not $srcPath) {
    Write-Error "Uso: -ndk <ndk-path> -opensslDir <openssl-build-dir> -srcPath <sqlcipher-source> -outDir <output-dir>"
    exit 1
}

if (-not (Test-Path $srcPath)) {
    Write-Error "SQLCipher source no encontrado: $srcPath"
    exit 1
}

if (-not (Test-Path "$opensslDir/installed")) {
    Write-Error "OpenSSL compilado no encontrado en: $opensslDir/installed"
    Write-Host "Asegúrate de compilar OpenSSL primero."
    exit 1
}

# Mapear ABI a tripleta de compilador
$targetMap = @{
    "arm64-v8a" = "aarch64-linux-android"
    "armeabi-v7a" = "armv7a-linux-androideabi"
    "x86" = "i686-linux-android"
    "x86_64" = "x86_64-linux-android"
}

if (-not $targetMap.ContainsKey($abi)) {
    Write-Error "ABI no soportado: $abi"
    exit 1
}

$target = $targetMap[$abi]
$abiNormalized = $abi -replace "-", "_"
$buildDir = Join-Path $outDir "build_$abiNormalized"

# Limpiar build anterior
if (Test-Path $buildDir) {
    Write-Host "Limpiando build anterior..."
    Remove-Item -Recurse -Force $buildDir
}

New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

# Copiar fuentes a build dir
Write-Host "Copiando fuentes de SQLCipher..."
Copy-Item -Recurse -Force "$srcPath/*" $buildDir

$ndkToolchain = Join-Path $ndk "toolchains/llvm/prebuilt/windows-x86_64"
$cc = Join-Path $ndkToolchain "bin/$target$api-clang.cmd"
$ar = Join-Path $ndkToolchain "bin/llvm-ar.exe"
$ranlib = Join-Path $ndkToolchain "bin/llvm-ranlib.exe"

if (-not (Test-Path $cc)) {
    Write-Error "Compilador no encontrado: $cc"
    exit 1
}

$PATH_BACKUP = $env:PATH
$env:PATH = "$ndkToolchain/bin;$env:PATH"

Push-Location $buildDir

try {
    Write-Host "Configurando SQLCipher para $abi (API $api)..."
    
    # Verificar si bash está disponible (necesario para configure)
    $bashPath = Get-Command bash -ErrorAction SilentlyContinue
    if (-not $bashPath) {
        Write-Error @"
Bash no está instalado. SQLCipher requiere bash para compilar en Windows.

Opciones:
1. Instalar Git for Windows (incluye bash): https://git-scm.com/download/win
2. Usar WSL: wsl --install y compilar desde Linux
3. Usar MSYS2: https://www.msys2.org/

Después de instalar, reinicia PowerShell y vuelve a ejecutar este script.
"@
        exit 1
    }
    
    Write-Host "✓ Bash encontrado: $($bashPath.Source)"
    
    $opensslInstall = "$opensslDir/installed"
    $installDir = Join-Path $buildDir "installed"
    
    # Crear script de configuración para bash
    $configScript = @"
#!/bin/bash
export CC="$($cc -replace '\\', '/')"
export AR="$($ar -replace '\\', '/')"
export RANLIB="$($ranlib -replace '\\', '/')"
export CFLAGS="-fPIC -DSQLITE_HAS_CODEC -I$($opensslInstall -replace '\\', '/')/include"
export LDFLAGS="-L$($opensslInstall -replace '\\', '/')/lib"
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
    
    Write-Host "Ejecutando configure y make..."
    & bash ./build_script.sh
    
    if ($LASTEXITCODE -ne 0) {
        throw "Build falló con código: $LASTEXITCODE"
    }
    
    Write-Host "`n✓ SQLCipher compilado exitosamente"
    Write-Host "Ubicación: $installDir"
    Write-Host "Include: $installDir/include"
    Write-Host "Libs: $installDir/lib"
    
} catch {
    Write-Error "Error compilando SQLCipher: $_"
    exit 1
} finally {
    Pop-Location
    $env:PATH = $PATH_BACKUP
}
