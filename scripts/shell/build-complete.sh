#!/bin/bash
# Script de compilación completa para Telegram Cloud Android
# Este script descarga dependencias, las compila y genera la APK

set -e  # Exit on error

# Obtener la ruta del proyecto (dos niveles arriba del script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Telegram Cloud Android - Build Complete         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"

# Función para verificar comandos
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}Error: $1 no está instalado${NC}"
        exit 1
    fi
}

# Verificar herramientas necesarias
echo -e "\n${BLUE}[1/5] Verificando herramientas necesarias...${NC}"
check_command git
check_command wget
check_command tar
echo -e "${GREEN}✓ Todas las herramientas están instaladas${NC}"

# Inicializar submódulos si es necesario
echo -e "\n${BLUE}[2/6] Verificando submódulos de Git...${NC}"
TELEGRAM_CPP_PATH="$PROJECT_ROOT/telegram-cloud-cpp"

if [ ! -d "$TELEGRAM_CPP_PATH/.git" ]; then
    echo "Inicializando submódulos de Git..."
    cd "$PROJECT_ROOT"
    if git submodule update --init --recursive; then
        echo -e "${GREEN}✓ Submódulos inicializados correctamente${NC}"
    else
        echo -e "${RED}Error al inicializar submódulos${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Submódulos ya están inicializados${NC}"
fi

# Verificar NDK
echo -e "\n${BLUE}[3/6] Verificando Android NDK...${NC}"
if [ -z "$ANDROID_NDK_HOME" ] && [ -z "$NDK_HOME" ]; then
    if [ -f "$PROJECT_ROOT/android/local.properties" ]; then
        NDK_DIR=$(grep "ndk.dir" "$PROJECT_ROOT/android/local.properties" | cut -d'=' -f2 | tr -d ' ')
        if [ -n "$NDK_DIR" ] && [ -d "$NDK_DIR" ]; then
            export ANDROID_NDK_HOME="$NDK_DIR"
            echo -e "${GREEN}✓ NDK encontrado en local.properties: $NDK_DIR${NC}"
        fi
    fi
fi

# Intentar detectar desde ANDROID_HOME/ANDROID_SDK_ROOT
if [ -z "$ANDROID_NDK_HOME" ]; then
    SDK_ROOT="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
    if [ -n "$SDK_ROOT" ] && [ -d "$SDK_ROOT/ndk/25.2.9519653" ]; then
        export ANDROID_NDK_HOME="$SDK_ROOT/ndk/25.2.9519653"
        echo -e "${GREEN}✓ NDK detectado automáticamente desde ANDROID_HOME${NC}"
    fi
fi

if [ -z "$ANDROID_NDK_HOME" ]; then
    echo -e "${RED}Error: Android NDK no encontrado${NC}"
    echo -e "${YELLOW}Opciones:${NC}"
    echo "  1. Configurar variable de entorno: export ANDROID_NDK_HOME=/ruta/a/ndk/25.2.9519653"
    echo "  2. Crear android/local.properties con: ndk.dir=/ruta/a/ndk/25.2.9519653"
    echo "  3. Asegurar que ANDROID_HOME esté configurado correctamente"
    exit 1
fi

NDK="$ANDROID_NDK_HOME"
echo -e "${GREEN}✓ NDK: $NDK${NC}"

# Configuración
API=${API:-28}
ABI=${ABI:-arm64-v8a}
DEPS_DIR="${DEPS_DIR:-$HOME/android-native-sources}"
BUILD_DIR="${BUILD_DIR:-$HOME/android-native-builds}"

echo -e "\n${YELLOW}Configuración:${NC}"
echo -e "  API Level: $API"
echo -e "  ABI: $ABI"
echo -e "  Dependencias: $DEPS_DIR"
echo -e "  Build output: $BUILD_DIR"

# Descargar dependencias
echo -e "\n${BLUE}[4/6] Descargando dependencias...${NC}"
"$SCRIPT_DIR/setup-dependencies.sh"

# Compilar OpenSSL
echo -e "\n${BLUE}[5/6] Compilando dependencias nativas...${NC}"
echo -e "${YELLOW}  [4.1/4.3] Compilando OpenSSL (esto puede tardar ~10 min)...${NC}"
"$PROJECT_ROOT/telegram-cloud-cpp/third_party/android_build_scripts/build_openssl_android.sh" \
  -ndk "$NDK" \
  -abi "$ABI" \
  -api "$API" \
  -srcPath "$DEPS_DIR/openssl-3.2.0" \
  -outDir "$BUILD_DIR/openssl"

# Compilar libcurl
echo -e "${YELLOW}  [4.2/4.3] Compilando libcurl...${NC}"
"$PROJECT_ROOT/telegram-cloud-cpp/third_party/android_build_scripts/build_libcurl_android.sh" \
  -ndk "$NDK" \
  -abi "$ABI" \
  -api "$API" \
  -opensslDir "$BUILD_DIR/openssl/build_${ABI//-/_}" \
  -srcPath "$DEPS_DIR/curl-8.7.1" \
  -outDir "$BUILD_DIR/libcurl"

# Compilar SQLCipher
echo -e "${YELLOW}  [4.3/4.3] Compilando SQLCipher...${NC}"
"$PROJECT_ROOT/telegram-cloud-cpp/third_party/android_build_scripts/build_sqlcipher_android.sh" \
  -ndk "$NDK" \
  -abi "$ABI" \
  -api "$API" \
  -opensslDir "$BUILD_DIR/openssl/build_${ABI//-/_}" \
  -srcPath "$DEPS_DIR/sqlcipher" \
  -outDir "$BUILD_DIR/sqlcipher"

# Actualizar local.properties
echo -e "\n${YELLOW}Actualizando android/local.properties...${NC}"
ABI_NORMALIZED=${ABI//-/_}
cat >> "$PROJECT_ROOT/android/local.properties" << EOF

# Rutas de dependencias nativas (generadas por build-complete.sh)
native.openssl.$ABI=$BUILD_DIR/openssl/build_${ABI_NORMALIZED}
native.curl.$ABI=$BUILD_DIR/libcurl/build_${ABI_NORMALIZED}
native.sqlcipher.$ABI=$BUILD_DIR/sqlcipher/build_${ABI_NORMALIZED}
EOF

echo -e "${GREEN}✓ local.properties actualizado${NC}"

# Compilar APK
echo -e "\n${BLUE}[6/6] Compilando APK...${NC}"
cd "$PROJECT_ROOT/android"
./gradlew assembleRelease

APK_PATH="app/build/outputs/apk/release/app-release.apk"
if [ -f "$APK_PATH" ]; then
    echo -e "\n${GREEN}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║            ✓ Compilación exitosa                   ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
    echo -e "\n${GREEN}APK generada en:${NC}"
    echo -e "  $(pwd)/$APK_PATH"
    
    # Información de la APK
    if command -v aapt &> /dev/null; then
        echo -e "\n${YELLOW}Información de la APK:${NC}"
        aapt dump badging "$APK_PATH" | grep -E "package:|sdkVersion:|targetSdkVersion:"
    fi
else
    echo -e "${RED}Error: No se generó la APK${NC}"
    exit 1
fi
