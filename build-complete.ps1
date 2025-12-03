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

# Verificar Git
Write-Host "`n[1/5] Verificando herramientas necesarias..."
try {
    git --version | Out-Null
    Write-ColorOutput Green "✓ Git está instalado"
} catch {
    Write-ColorOutput Red "Error: Git no está instalado"
    exit 1
}

# Verificar NDK
Write-Host "`n[2/5] Verificando Android NDK..."
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
Write-Host "`n[3/5] Descargando dependencias..."
& .\setup-dependencies.ps1

# Compilar OpenSSL
Write-Host "`n[4/5] Compilando dependencias nativas..."
Write-ColorOutput Yellow "  [4.1/4.3] Compilando OpenSSL (esto puede tardar ~10 min)..."
& .\telegram-cloud-cpp\third_party\android_build_scripts\build_openssl_android.ps1 `
    -ndk $NDK `
    -abi $ABI `
    -api $API `
    -srcPath "$DEPS_DIR\openssl-3.2.0" `
    -outDir "$BUILD_DIR\openssl"

# Compilar libcurl
Write-ColorOutput Yellow "  [4.2/4.3] Compilando libcurl..."
$ABI_NORMALIZED = $ABI -replace "-", "_"
& .\telegram-cloud-cpp\third_party\android_build_scripts\build_libcurl_android.ps1 `
    -ndk $NDK `
    -abi $ABI `
    -api $API `
    -opensslDir "$BUILD_DIR\openssl\build_$ABI_NORMALIZED" `
    -srcPath "$DEPS_DIR\curl-8.7.1" `
    -outDir "$BUILD_DIR\libcurl"

# Compilar SQLCipher
Write-ColorOutput Yellow "  [4.3/4.3] Compilando SQLCipher..."
& .\telegram-cloud-cpp\third_party\android_build_scripts\build_sqlcipher_android.ps1 `
    -ndk $NDK `
    -abi $ABI `
    -api $API `
    -opensslDir "$BUILD_DIR\openssl\build_$ABI_NORMALIZED" `
    -srcPath "$DEPS_DIR\sqlcipher" `
    -outDir "$BUILD_DIR\sqlcipher"

# Actualizar local.properties
Write-ColorOutput Yellow "`nActualizando android\local.properties..."
$localPropsPath = "android\local.properties"
$propsContent = @"

# Rutas de dependencias nativas (generadas por build-complete.ps1)
native.openssl.$ABI=$BUILD_DIR\openssl\build_$ABI_NORMALIZED
native.curl.$ABI=$BUILD_DIR\libcurl\build_$ABI_NORMALIZED
native.sqlcipher.$ABI=$BUILD_DIR\sqlcipher\build_$ABI_NORMALIZED
"@

Add-Content -Path $localPropsPath -Value $propsContent
Write-ColorOutput Green "✓ local.properties actualizado"

# Compilar APK
Write-Host "`n[5/5] Compilando APK..."
Set-Location android
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

