#!/bin/bash
# Script para descargar automáticamente las dependencias nativas
# Telegram Cloud Android - Setup Dependencies

set -e  # Exit on error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Telegram Cloud Android - Setup Dependencies ===${NC}"

# Configuración
DEPS_DIR="${DEPS_DIR:-$HOME/android-native-sources}"
OPENSSL_VERSION="${OPENSSL_VERSION:-3.2.0}"
CURL_VERSION="${CURL_VERSION:-8.7.1}"

echo -e "${YELLOW}Directorio de dependencias: $DEPS_DIR${NC}"

# Crear directorio
mkdir -p "$DEPS_DIR"
cd "$DEPS_DIR"

# Función para verificar si un comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Verificar herramientas necesarias
echo -e "\n${YELLOW}Verificando herramientas necesarias...${NC}"
MISSING_TOOLS=()

if ! command_exists wget && ! command_exists curl; then
    MISSING_TOOLS+=("wget o curl")
fi

if ! command_exists tar; then
    MISSING_TOOLS+=("tar")
fi

if ! command_exists git; then
    MISSING_TOOLS+=("git")
fi

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    echo -e "${RED}Error: Faltan las siguientes herramientas:${NC}"
    printf '%s\n' "${MISSING_TOOLS[@]}"
    echo "Instálalas antes de continuar."
    exit 1
fi

echo -e "${GREEN}✓ Todas las herramientas necesarias están instaladas${NC}"

# Función para descargar con wget o curl
download_file() {
    local url="$1"
    local output="$2"
    
    if [ -f "$output" ]; then
        echo -e "${GREEN}✓ $output ya existe, omitiendo descarga${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}Descargando $output...${NC}"
    
    if command_exists wget; then
        wget -O "$output" "$url" || return 1
    elif command_exists curl; then
        curl -L -o "$output" "$url" || return 1
    else
        echo -e "${RED}Error: No se encontró wget ni curl${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Descarga completada: $output${NC}"
}

# 1. Descargar OpenSSL
echo -e "\n${YELLOW}[1/3] Descargando OpenSSL ${OPENSSL_VERSION}...${NC}"
OPENSSL_TAR="openssl-${OPENSSL_VERSION}.tar.gz"
OPENSSL_DIR="openssl-${OPENSSL_VERSION}"
OPENSSL_URL="https://www.openssl.org/source/${OPENSSL_TAR}"

if [ -d "$OPENSSL_DIR" ]; then
    echo -e "${GREEN}✓ OpenSSL ya está descargado en $OPENSSL_DIR${NC}"
else
    download_file "$OPENSSL_URL" "$OPENSSL_TAR"
    echo -e "${YELLOW}Extrayendo OpenSSL...${NC}"
    tar -xzf "$OPENSSL_TAR"
    echo -e "${GREEN}✓ OpenSSL extraído en $OPENSSL_DIR${NC}"
fi

# 2. Descargar libcurl
echo -e "\n${YELLOW}[2/3] Descargando libcurl ${CURL_VERSION}...${NC}"
CURL_TAR="curl-${CURL_VERSION}.tar.gz"
CURL_DIR="curl-${CURL_VERSION}"
CURL_URL="https://curl.se/download/${CURL_TAR}"

if [ -d "$CURL_DIR" ]; then
    echo -e "${GREEN}✓ libcurl ya está descargado en $CURL_DIR${NC}"
else
    download_file "$CURL_URL" "$CURL_TAR"
    echo -e "${YELLOW}Extrayendo libcurl...${NC}"
    tar -xzf "$CURL_TAR"
    echo -e "${GREEN}✓ libcurl extraído en $CURL_DIR${NC}"
fi

# 3. Clonar SQLCipher
echo -e "\n${YELLOW}[3/3] Clonando SQLCipher...${NC}"
SQLCIPHER_DIR="sqlcipher"

if [ -d "$SQLCIPHER_DIR" ]; then
    echo -e "${GREEN}✓ SQLCipher ya está clonado en $SQLCIPHER_DIR${NC}"
    echo -e "${YELLOW}Actualizando SQLCipher...${NC}"
    cd "$SQLCIPHER_DIR"
    git pull || echo -e "${YELLOW}⚠ No se pudo actualizar SQLCipher (puede ser normal)${NC}"
    cd ..
else
    git clone https://github.com/sqlcipher/sqlcipher.git "$SQLCIPHER_DIR"
    echo -e "${GREEN}✓ SQLCipher clonado en $SQLCIPHER_DIR${NC}"
fi

# Resumen
echo -e "\n${GREEN}=== ✓ Todas las dependencias están listas ===${NC}"
echo -e "\nUbicación: ${GREEN}$DEPS_DIR${NC}"
echo -e "\nDependencias descargadas:"
echo -e "  - OpenSSL ${OPENSSL_VERSION}: $DEPS_DIR/$OPENSSL_DIR"
echo -e "  - libcurl ${CURL_VERSION}: $DEPS_DIR/$CURL_DIR"
echo -e "  - SQLCipher: $DEPS_DIR/$SQLCIPHER_DIR"

echo -e "\n${YELLOW}Próximo paso:${NC}"
echo -e "Compilar las dependencias nativas usando los scripts en:"
echo -e "  telegram-cloud-cpp/third_party/android_build_scripts/"
echo -e "\nVer: ${GREEN}BUILD_NATIVE_DEPENDENCIES.md${NC} para instrucciones detalladas"

