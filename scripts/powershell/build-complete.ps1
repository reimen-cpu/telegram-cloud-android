# Script de compilación completa para Telegram Cloud Android
# Este script descarga dependencias, las compila y genera la APK

$ErrorActionPreference = "Stop"

function Write-ColorOutput($ForegroundColor, $Message) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    Write-Output $Message
    $host.UI.RawUI.ForegroundColor = $fc
}

Write-ColorOutput Green "╔════════════════════════════════════════════════════╗"
Write-ColorOutput Green "║   Telegram Cloud Android - Build Complete         ║"
Write-ColorOutput Green "╚════════════════════════════════════════════════════╝"

# Verificar Git y Bash
Write-Host "`n[1/5] Verificando herramientas necesarias..."
try {
    git --version | Out-Null
    Write-ColorOutput Green "✓ Git está instalado"
} catch {
    Write-ColorOutput Red "Error: Git no está instalado"
    exit 1
}

# Verificar Bash (necesario para compilar dependencias nativas)
$bashPath = $null
$bash = Get-Command bash -ErrorAction SilentlyContinue
if ($bash) {
    $bashPath = $bash.Source
    Write-ColorOutput Green "✓ Bash disponible: $bashPath"
} else {
    # Buscar en ubicaciones comunes de Git for Windows
    $gitBashPaths = @(
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files (x86)\Git\bin\bash.exe",
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe"
    )
    
    foreach ($path in $gitBashPaths) {
        if (Test-Path $path) {
            $bashPath = $path
            Write-ColorOutput Green "✓ Bash encontrado: $bashPath"
            break
        }
    }
}

if (-not $bashPath) {
    # Verificar si WSL está disponible
    $wsl = Get-Command wsl -ErrorAction SilentlyContinue
    if ($wsl) {
        Write-ColorOutput Yellow "⚠ Bash no encontrado, pero WSL está disponible"
        Write-Host "  Nota: La compilación puede ser más lenta con WSL"
        Write-Host "  Recomendado: Instalar Git for Windows para mejor rendimiento"
    } else {
        Write-ColorOutput Red @"
Error: Bash no encontrado. Necesario para compilar dependencias nativas.

RECOMENDADO: Instalar Git for Windows
  https://git-scm.com/download/win
  Incluye bash, perl, y make necesarios para OpenSSL.

ALTERNATIVA: Instalar WSL
  wsl --install

Después de instalar, reiniciar PowerShell y ejecutar este script nuevamente.
"@
        exit 1
    }
}

# Inicializar submódulos si es necesario
Write-Host "`n[2/6] Verificando submódulos de Git..."
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$telegramCppPath = Join-Path $projectRoot "telegram-cloud-cpp"

if (-not (Test-Path "$telegramCppPath\.git")) {
    Write-Host "Inicializando submódulos de Git..."
    Push-Location $projectRoot
    try {
        git submodule sync
        git submodule update --init --recursive
        if ($LASTEXITCODE -ne 0) {
            Write-ColorOutput Yellow "Advertencia: Falló la actualización recursiva. Intentando actualización simple..."
            git submodule update --init
        }
        
        if ($LASTEXITCODE -ne 0) {
            Write-ColorOutput Red "Error al inicializar submódulos"
            exit 1
        }
        Write-ColorOutput Green "✓ Submódulos inicializados correctamente"
    } finally {
        Pop-Location
    }
} else {
    Write-ColorOutput Green "✓ Submódulos ya están inicializados"
}

# Verificar NDK
Write-Host "`n[3/6] Verificando Android NDK..."
$NDK = $env:ANDROID_NDK_HOME
if (-not $NDK) {
    $NDK = $env:NDK_HOME
}

if (-not $NDK -and (Test-Path "android\local.properties")) {
    $localProps = Get-Content "android\local.properties"
    $ndkLine = $localProps | Where-Object { $_ -match "ndk.dir=" }
    if ($ndkLine) {
        $NDK = ($ndkLine -split "=", 2)[1].Trim()
    }
}

# Intentar detectar desde ANDROID_HOME/ANDROID_SDK_ROOT
if (-not $NDK) {
    $SDK_ROOT = $env:ANDROID_HOME
    if (-not $SDK_ROOT) {
        $SDK_ROOT = $env:ANDROID_SDK_ROOT
    }
    if ($SDK_ROOT -and (Test-Path "$SDK_ROOT\ndk\25.2.9519653")) {
        $NDK = "$SDK_ROOT\ndk\25.2.9519653"
        Write-ColorOutput Green "✓ NDK detectado automáticamente desde ANDROID_HOME"
    }
}

if (-not $NDK -or -not (Test-Path $NDK)) {
    Write-ColorOutput Red "Error: Android NDK no encontrado"
    Write-ColorOutput Yellow "Opciones:"
    Write-Host "  1. Configurar variable de entorno: `$env:ANDROID_NDK_HOME = 'C:\Android\ndk\25.2.9519653'"
    Write-Host "  2. Crear android\local.properties con: ndk.dir=C:/Android/ndk/25.2.9519653"
    Write-Host "  3. Asegurar que ANDROID_HOME esté configurado correctamente"
    exit 1
}

Write-ColorOutput Green "✓ NDK: $NDK"

# Configuración
$API = if ($env:API) { $env:API } else { 28 }
$ABI = if ($env:ABI) { $env:ABI } else { "arm64-v8a" }
$DEPS_DIR = if ($env:DEPS_DIR) { $env:DEPS_DIR } else { "$env:USERPROFILE\android-native-sources" }
$BUILD_DIR = if ($env:BUILD_DIR) { $env:BUILD_DIR } else { "$env:USERPROFILE\android-native-builds" }

Write-Host "`nConfiguración:"
Write-Host "  API Level: $API"
Write-Host "  ABI: $ABI"
Write-Host "  Dependencias: $DEPS_DIR"
Write-Host "  Build output: $BUILD_DIR"

# Descargar dependencias
Write-Host "`n[4/6] Descargando dependencias..."
& "$PSScriptRoot\setup-dependencies.ps1"

# Compilar OpenSSL
Write-Host "`n[5/6] Compilando dependencias nativas..."
Write-ColorOutput Yellow "  [4.1/4.3] Compilando OpenSSL (esto puede tardar ~10 min)..."
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
& "$projectRoot\telegram-cloud-cpp\third_party\android_build_scripts\build_openssl_android.ps1" `
    -ndk $NDK `
    -abi $ABI `
    -api $API `
    -srcPath "$DEPS_DIR\openssl-3.2.0" `
    -outDir "$BUILD_DIR\openssl"

if ($LASTEXITCODE -ne 0) {
    Write-ColorOutput Red "Error compilando OpenSSL"
    exit 1
}

# Compilar libcurl
Write-ColorOutput Yellow "  [4.2/4.3] Compilando libcurl..."
$ABI_NORMALIZED = $ABI -replace "-", "_"
& "$projectRoot\telegram-cloud-cpp\third_party\android_build_scripts\build_libcurl_android.ps1" `
    -ndk $NDK `
    -abi $ABI `
    -api $API `
    -opensslDir "$BUILD_DIR\openssl\build_$ABI_NORMALIZED" `
    -srcPath "$DEPS_DIR\curl-8.7.1" `
    -outDir "$BUILD_DIR\libcurl"

if ($LASTEXITCODE -ne 0) {
    Write-ColorOutput Red "Error compilando libcurl"
    exit 1
}

# Compilar SQLCipher
Write-ColorOutput Yellow "  [4.3/4.3] Compilando SQLCipher..."
& "$projectRoot\telegram-cloud-cpp\third_party\android_build_scripts\build_sqlcipher_android.ps1" `
    -ndk $NDK `
    -abi $ABI `
    -api $API `
    -opensslDir "$BUILD_DIR\openssl\build_$ABI_NORMALIZED" `
    -srcPath "$DEPS_DIR\sqlcipher" `
    -outDir "$BUILD_DIR\sqlcipher"

if ($LASTEXITCODE -ne 0) {
    Write-ColorOutput Red "Error compilando SQLCipher"
    exit 1
}

# Actualizar local.properties
Write-ColorOutput Yellow "`nActualizando android\local.properties..."
$localPropsPath = Join-Path $projectRoot "android\local.properties"
$propsContent = @"

# Rutas de dependencias nativas (generadas por build-complete.ps1)
native.openssl.$ABI=$BUILD_DIR\openssl\build_$ABI_NORMALIZED\installed
native.curl.$ABI=$BUILD_DIR\libcurl\build_$ABI_NORMALIZED\installed
native.sqlcipher.$ABI=$BUILD_DIR\sqlcipher\build_$ABI_NORMALIZED\installed
"@

Add-Content -Path $localPropsPath -Value $propsContent
Write-ColorOutput Green "✓ local.properties actualizado"

# Compilar APK
Write-Host "`n[6/6] Compilando APK..."
Set-Location (Join-Path $projectRoot "android")
& .\gradlew.bat assembleRelease

$APK_PATH = "app\build\outputs\apk\release\app-release.apk"
if (Test-Path $APK_PATH) {
    Write-Host "`n"
    Write-ColorOutput Green "╔════════════════════════════════════════════════════╗"
    Write-ColorOutput Green "║            ✓ Compilación exitosa                   ║"
    Write-ColorOutput Green "╚════════════════════════════════════════════════════╝"
    Write-Host "`nAPK generada en:"
    Write-Host "  $(Get-Location)\$APK_PATH"
    
    # Tamaño del APK
    $apkSize = (Get-Item $APK_PATH).Length / 1MB
    Write-Host "`nTamaño: $([math]::Round($apkSize, 2)) MB"
} else {
    Write-ColorOutput Red "Error: No se generó la APK"
    exit 1
}
