param(
    [string]$ndk,
    [string]$abi = "arm64-v8a",
    [int]$api = 28,
    [string]$srcPath,
    [string]$outDir
)

$ErrorActionPreference = "Stop"

if (-not $ndk) {
    Write-Error "Uso: -ndk <path-to-ndk> -srcPath <openssl-source> -outDir <output-dir>"
    exit 1
}

if (-not (Test-Path $srcPath)) {
    Write-Error "OpenSSL source path no encontrado: $srcPath"
    exit 1
}

# Mapear ABI a arquitectura de OpenSSL
$archMap = @{
    "arm64-v8a" = "android-arm64"
    "armeabi-v7a" = "android-arm"
    "x86" = "android-x86"
    "x86_64" = "android-x86_64"
}

if (-not $archMap.ContainsKey($abi)) {
    Write-Error "ABI no soportado: $abi. Use: arm64-v8a, armeabi-v7a, x86, x86_64"
    exit 1
}

$opensslTarget = $archMap[$abi]
$abiNormalized = $abi -replace "-", "_"
$buildDir = Join-Path $outDir "build_$abiNormalized"

# Limpiar directorio de build anterior
if (Test-Path $buildDir) {
    Write-Host "Limpiando build anterior..."
    Remove-Item -Recurse -Force $buildDir
}

New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

# Configurar variables de entorno para NDK
$ndkToolchain = Join-Path $ndk "toolchains/llvm/prebuilt/windows-x86_64"
$PATH_BACKUP = $env:PATH
$env:PATH = "$ndkToolchain/bin;$env:PATH"
$env:ANDROID_NDK_ROOT = $ndk

# Copiar fuentes a build dir (OpenSSL necesita configurarse in-place)
Write-Host "Copiando fuentes de OpenSSL..."
Copy-Item -Recurse -Force "$srcPath/*" $buildDir

Push-Location $buildDir

try {
    Write-Host "Configurando OpenSSL para $opensslTarget (API $api)..."
    
    # Verificar si perl está disponible
    $perlPath = Get-Command perl -ErrorAction SilentlyContinue
    if (-not $perlPath) {
        Write-Error @"
Perl no está instalado. OpenSSL requiere Perl para compilar.

Opciones:
1. Instalar Strawberry Perl: https://strawberryperl.com/
2. Instalar Git for Windows (incluye Perl): https://git-scm.com/download/win
3. Usar WSL: wsl --install y compilar desde Linux

Después de instalar, reinicia PowerShell y vuelve a ejecutar este script.
"@
        exit 1
    }
    
    Write-Host "✓ Perl encontrado: $($perlPath.Source)"
    
    # Configurar OpenSSL con los parámetros correctos
    $configArgs = @(
        $opensslTarget,
        "-D__ANDROID_API__=$api",
        "no-shared",
        "--prefix=$buildDir/installed",
        "--openssldir=$buildDir/installed"
    )
    
    Write-Host "Ejecutando: perl Configure $($configArgs -join ' ')"
    & perl Configure @configArgs
    
    if ($LASTEXITCODE -ne 0) {
        throw "Configure falló con código: $LASTEXITCODE"
    }
    
    Write-Host "Compilando OpenSSL (esto puede tardar 10-15 minutos)..."
    & make -j$([Environment]::ProcessorCount)
    
    if ($LASTEXITCODE -ne 0) {
        throw "Make falló con código: $LASTEXITCODE"
    }
    
    Write-Host "Instalando OpenSSL..."
    & make install_sw
    
    if ($LASTEXITCODE -ne 0) {
        throw "Install falló con código: $LASTEXITCODE"
    }
    
    Write-Host "`n✓ OpenSSL compilado exitosamente"
    Write-Host "Ubicación: $buildDir/installed"
    Write-Host "Include: $buildDir/installed/include"
    Write-Host "Libs: $buildDir/installed/lib"
    
} catch {
    Write-Error "Error compilando OpenSSL: $_"
    exit 1
} finally {
    Pop-Location
    $env:PATH = $PATH_BACKUP
}
