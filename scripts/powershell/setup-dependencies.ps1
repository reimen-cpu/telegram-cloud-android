# Script para descargar automáticamente las dependencias nativas
# Telegram Cloud Android - Setup Dependencies (PowerShell)

$ErrorActionPreference = "Stop"

# Colores
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) {
        Write-Output $args
    }
    $host.UI.RawUI.ForegroundColor = $fc
}

Write-ColorOutput Green "=== Telegram Cloud Android - Setup Dependencies ==="

# Configuración
$DEPS_DIR = if ($env:DEPS_DIR) { $env:DEPS_DIR } else { "$env:USERPROFILE\android-native-sources" }
$OPENSSL_VERSION = if ($env:OPENSSL_VERSION) { $env:OPENSSL_VERSION } else { "3.2.0" }
$CURL_VERSION = if ($env:CURL_VERSION) { $env:CURL_VERSION } else { "8.7.1" }

Write-ColorOutput Yellow "Directorio de dependencias: $DEPS_DIR"

# Crear directorio
New-Item -ItemType Directory -Force -Path $DEPS_DIR | Out-Null
Set-Location $DEPS_DIR

# Verificar Git
Write-Host "`nVerificando herramientas necesarias..."
try {
    git --version | Out-Null
    Write-ColorOutput Green "✓ Git está instalado"
} catch {
    Write-ColorOutput Red "Error: Git no está instalado"
    Write-Host "Descarga Git desde: https://git-scm.com/download/win"
    exit 1
}

# Función para descargar archivos
function Download-File {
    param (
        [string]$Url,
        [string]$Output
    )
    
    if (Test-Path $Output) {
        Write-ColorOutput Green "✓ $Output ya existe, omitiendo descarga"
        return
    }
    
    Write-ColorOutput Yellow "Descargando $Output..."
    
    try {
        # Usar Invoke-WebRequest (PowerShell nativo)
        $ProgressPreference = 'SilentlyContinue'  # Más rápido sin progress bar
        Invoke-WebRequest -Uri $Url -OutFile $Output -UseBasicParsing
        Write-ColorOutput Green "✓ Descarga completada: $Output"
    } catch {
        Write-ColorOutput Red "Error al descargar $Url"
        Write-Host $_.Exception.Message
        exit 1
    }
}

# 1. Descargar OpenSSL
Write-Host "`n[1/3] Descargando OpenSSL $OPENSSL_VERSION..."
$OPENSSL_TAR = "openssl-$OPENSSL_VERSION.tar.gz"
$OPENSSL_DIR = "openssl-$OPENSSL_VERSION"
$OPENSSL_URL = "https://www.openssl.org/source/$OPENSSL_TAR"

if (Test-Path $OPENSSL_DIR) {
    Write-ColorOutput Green "✓ OpenSSL ya está descargado en $OPENSSL_DIR"
} else {
    Download-File -Url $OPENSSL_URL -Output $OPENSSL_TAR
    
    Write-ColorOutput Yellow "Extrayendo OpenSSL..."
    # Verificar si tar está disponible (Windows 10 1803+)
    try {
        tar -xzf $OPENSSL_TAR
        Write-ColorOutput Green "✓ OpenSSL extraído en $OPENSSL_DIR"
    } catch {
        Write-ColorOutput Yellow "⚠ tar no disponible. Extrae manualmente $OPENSSL_TAR"
        Write-Host "O usa 7-Zip: https://www.7-zip.org/"
    }
}

# 2. Descargar libcurl
Write-Host "`n[2/3] Descargando libcurl $CURL_VERSION..."
$CURL_TAR = "curl-$CURL_VERSION.tar.gz"
$CURL_DIR = "curl-$CURL_VERSION"
$CURL_URL = "https://curl.se/download/$CURL_TAR"

if (Test-Path $CURL_DIR) {
    Write-ColorOutput Green "✓ libcurl ya está descargado en $CURL_DIR"
} else {
    Download-File -Url $CURL_URL -Output $CURL_TAR
    
    Write-ColorOutput Yellow "Extrayendo libcurl..."
    try {
        tar -xzf $CURL_TAR
        Write-ColorOutput Green "✓ libcurl extraído en $CURL_DIR"
    } catch {
        Write-ColorOutput Yellow "⚠ tar no disponible. Extrae manualmente $CURL_TAR"
        Write-Host "O usa 7-Zip: https://www.7-zip.org/"
    }
}

# 3. Clonar SQLCipher
Write-Host "`n[3/3] Clonando SQLCipher..."
$SQLCIPHER_DIR = "sqlcipher"

if (Test-Path $SQLCIPHER_DIR) {
    Write-ColorOutput Green "✓ SQLCipher ya está clonado en $SQLCIPHER_DIR"
    Write-ColorOutput Yellow "Actualizando SQLCipher..."
    Set-Location $SQLCIPHER_DIR
    try {
        git pull
    } catch {
        Write-ColorOutput Yellow "⚠ No se pudo actualizar SQLCipher (puede ser normal)"
    }
    Set-Location ..
} else {
    git clone https://github.com/sqlcipher/sqlcipher.git $SQLCIPHER_DIR
    Write-ColorOutput Green "✓ SQLCipher clonado en $SQLCIPHER_DIR"
}

# Resumen
Write-Host "`n"
Write-ColorOutput Green "=== ✓ Todas las dependencias están listas ==="
Write-Host "`nUbicación: $DEPS_DIR"
Write-Host "`nDependencias descargadas:"
Write-Host "  - OpenSSL $OPENSSL_VERSION : $DEPS_DIR\$OPENSSL_DIR"
Write-Host "  - libcurl $CURL_VERSION : $DEPS_DIR\$CURL_DIR"
Write-Host "  - SQLCipher: $DEPS_DIR\$SQLCIPHER_DIR"

Write-Host "`nPróximo paso:"
Write-ColorOutput Yellow "Compilar las dependencias nativas usando los scripts en:"
Write-Host "  telegram-cloud-cpp\third_party\android_build_scripts\"
Write-Host "`nVer: BUILD_NATIVE_DEPENDENCIES.md para instrucciones detalladas"

