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
echo -e "\n${BLUE}[1/4] Verificando herramientas necesarias...${NC}"
check_command git
check_command wget
check_command tar
echo -e "${GREEN}✓ Todas las herramientas están instaladas${NC}"

# Verificar NDK
echo -e "\n${BLUE}[2/4] Verificando Android NDK...${NC}"

# 1. Verificar variable de entorno ANDROID_NDK_HOME o NDK_HOME
if [ -n "$ANDROID_NDK_HOME" ] && [ -d "$ANDROID_NDK_HOME" ]; then
    echo -e "${GREEN}✓ NDK encontrado en ANDROID_NDK_HOME: $ANDROID_NDK_HOME${NC}"
elif [ -n "$NDK_HOME" ] && [ -d "$NDK_HOME" ]; then
    export ANDROID_NDK_HOME="$NDK_HOME"
    echo -e "${GREEN}✓ NDK encontrado en NDK_HOME: $NDK_HOME${NC}"
fi

# 2. Buscar en local.properties
if [ -z "$ANDROID_NDK_HOME" ] && [ -f "$PROJECT_ROOT/android/local.properties" ]; then
    NDK_DIR=$(grep "ndk.dir" "$PROJECT_ROOT/android/local.properties" | cut -d'=' -f2 | tr -d ' ')
    if [ -n "$NDK_DIR" ] && [ -d "$NDK_DIR" ]; then
        export ANDROID_NDK_HOME="$NDK_DIR"
        echo -e "${GREEN}✓ NDK encontrado en local.properties: $NDK_DIR${NC}"
    fi
fi

# 3. Intentar detectar desde ANDROID_HOME/ANDROID_SDK_ROOT
if [ -z "$ANDROID_NDK_HOME" ]; then
    SDK_ROOT="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
    if [ -n "$SDK_ROOT" ] && [ -d "$SDK_ROOT/ndk" ]; then
        # Buscar la versión más reciente del NDK (puede ser formato "26.3.11579264" o "26.3.11579264-2")
        LATEST_NDK_DIR=$(find "$SDK_ROOT/ndk" -maxdepth 1 -type d \( -name "*-*" -o -name "[0-9]*" \) | sort -V | tail -n 1)
        if [ -n "$LATEST_NDK_DIR" ] && [ -d "$LATEST_NDK_DIR" ]; then
            export ANDROID_NDK_HOME="$LATEST_NDK_DIR"
            echo -e "${GREEN}✓ NDK detectado automáticamente desde ANDROID_HOME: $(basename "$LATEST_NDK_DIR")${NC}"
        fi
    fi
fi

# 4. Buscar en ubicaciones comunes de Linux
if [ -z "$ANDROID_NDK_HOME" ]; then
    # Obtener el usuario actual si $HOME no está configurado
    USER_HOME="${HOME:-$(eval echo ~$(whoami))}"
    
    COMMON_PATHS=(
        "$USER_HOME/android-sdk/ndk"
        "$HOME/android-sdk/ndk"
        "$HOME/Android/Sdk/ndk"
        "$HOME/.android/ndk"
        "/opt/android-sdk/ndk"
        "/usr/local/android-sdk/ndk"
    )
    
    for BASE_PATH in "${COMMON_PATHS[@]}"; do
        if [ -d "$BASE_PATH" ]; then
            # Buscar la versión más reciente (puede ser formato "26.3.11579264" o "26.3.11579264-2")
            # Usar find para obtener todos los directorios y ordenarlos por versión
            LATEST_NDK_DIR=$(find "$BASE_PATH" -maxdepth 1 -type d ! -path "$BASE_PATH" 2>/dev/null | sort -V | tail -n 1)
            if [ -n "$LATEST_NDK_DIR" ] && [ -d "$LATEST_NDK_DIR" ]; then
                export ANDROID_NDK_HOME="$LATEST_NDK_DIR"
                echo -e "${GREEN}✓ NDK detectado automáticamente: $(basename "$LATEST_NDK_DIR")${NC}"
                break
            fi
        fi
    done
fi

if [ -z "$ANDROID_NDK_HOME" ]; then
    echo -e "${RED}Error: Android NDK no encontrado${NC}"
    echo -e "${YELLOW}Opciones:${NC}"
    echo "  1. Configurar variable de entorno: export ANDROID_NDK_HOME=\$HOME/android-sdk/ndk/26.3.11579264"
    echo "  2. Crear android/local.properties con: ndk.dir=\$HOME/android-sdk/ndk/26.3.11579264"
    echo "  3. Asegurar que ANDROID_HOME esté configurado correctamente"
    echo ""
    echo -e "${YELLOW}Ubicaciones buscadas:${NC}"
    echo "  - ANDROID_NDK_HOME o NDK_HOME"
    echo "  - android/local.properties (ndk.dir)"
    echo "  - \$ANDROID_HOME/ndk/"
    echo "  - \$HOME/android-sdk/ndk/"
    echo "  - \$HOME/Android/Sdk/ndk/"
    exit 1
fi

NDK="$ANDROID_NDK_HOME"
echo -e "${GREEN}✓ NDK: $NDK${NC}"

# Configuración
API=${API:-28}
# Compilar para ambos ABIs que usa Gradle
ABIS=${ABIS:-"arm64-v8a armeabi-v7a"}
DEPS_DIR="${DEPS_DIR:-$HOME/android-native-sources}"
BUILD_DIR="${BUILD_DIR:-$HOME/android-native-builds}"

echo -e "\n${YELLOW}Configuración:${NC}"
echo -e "  API Level: $API"
echo -e "  ABIs: $ABIS"
echo -e "  Dependencias: $DEPS_DIR"
echo -e "  Build output: $BUILD_DIR"

# Descargar dependencias
echo -e "\n${BLUE}[3/4] Descargando dependencias...${NC}"
"$SCRIPT_DIR/setup-dependencies.sh"

# Compilar dependencias para cada ABI
echo -e "\n${BLUE}[4/4] Compilando dependencias nativas...${NC}"
for ABI in $ABIS; do
    ABI_NORMALIZED=${ABI//-/_}
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Compilando para ABI: $ABI${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Compilar OpenSSL
    echo -e "${YELLOW}  [4.1/4.3] Compilando OpenSSL para $ABI (esto puede tardar ~10 min)...${NC}"
    "$PROJECT_ROOT/telegram-cloud-cpp/third_party/android_build_scripts/build_openssl_android.sh" \
      -ndk "$NDK" \
      -abi "$ABI" \
      -api "$API" \
      -srcPath "$DEPS_DIR/openssl-3.2.0" \
      -outDir "$BUILD_DIR/openssl"

    # Compilar libcurl
    echo -e "${YELLOW}  [4.2/4.3] Compilando libcurl para $ABI...${NC}"
    "$PROJECT_ROOT/telegram-cloud-cpp/third_party/android_build_scripts/build_libcurl_android.sh" \
      -ndk "$NDK" \
      -abi "$ABI" \
      -api "$API" \
      -opensslDir "$BUILD_DIR/openssl/build_${ABI_NORMALIZED}/installed" \
      -srcPath "$DEPS_DIR/curl-8.7.1" \
      -outDir "$BUILD_DIR/libcurl"

    # Compilar SQLCipher
    echo -e "${YELLOW}  [4.3/4.3] Compilando SQLCipher para $ABI...${NC}"
    "$PROJECT_ROOT/telegram-cloud-cpp/third_party/android_build_scripts/build_sqlcipher_android.sh" \
      -ndk "$NDK" \
      -abi "$ABI" \
      -api "$API" \
      -opensslDir "$BUILD_DIR/openssl/build_${ABI_NORMALIZED}/installed" \
      -srcPath "$DEPS_DIR/sqlcipher" \
      -outDir "$BUILD_DIR/sqlcipher"
done

# Actualizar local.properties
echo -e "\n${YELLOW}Actualizando android/local.properties...${NC}"

# Detectar SDK automáticamente si no está configurado
SDK_DIR=""
if [ -n "$ANDROID_HOME" ] && [ -d "$ANDROID_HOME" ]; then
    SDK_DIR="$ANDROID_HOME"
elif [ -n "$ANDROID_SDK_ROOT" ] && [ -d "$ANDROID_SDK_ROOT" ]; then
    SDK_DIR="$ANDROID_SDK_ROOT"
else
    # Buscar en ubicaciones comunes
    USER_HOME="${HOME:-$(eval echo ~$(whoami))}"
    COMMON_SDK_PATHS=(
        "$USER_HOME/android-sdk"
        "$HOME/android-sdk"
        "$HOME/Android/Sdk"
        "/opt/android-sdk"
        "/usr/local/android-sdk"
    )
    
    for SDK_PATH in "${COMMON_SDK_PATHS[@]}"; do
        if [ -d "$SDK_PATH" ] && [ -d "$SDK_PATH/platforms" ]; then
            SDK_DIR="$SDK_PATH"
            break
        fi
    done
fi

# Si el NDK está configurado, intentar inferir el SDK desde el NDK
if [ -z "$SDK_DIR" ] && [ -n "$ANDROID_NDK_HOME" ]; then
    # El NDK suele estar en $SDK/ndk/version, así que subir dos niveles
    NDK_PARENT=$(dirname "$ANDROID_NDK_HOME")
    SDK_CANDIDATE=$(dirname "$NDK_PARENT")
    if [ -d "$SDK_CANDIDATE" ] && [ -d "$SDK_CANDIDATE/platforms" ]; then
        SDK_DIR="$SDK_CANDIDATE"
    fi
fi

# Crear o actualizar local.properties
LOCAL_PROPERTIES="$PROJECT_ROOT/android/local.properties"
if [ ! -f "$LOCAL_PROPERTIES" ]; then
    touch "$LOCAL_PROPERTIES"
fi

# Agregar o actualizar sdk.dir
if [ -n "$SDK_DIR" ]; then
    if grep -q "^sdk.dir=" "$LOCAL_PROPERTIES"; then
        sed -i "s|^sdk.dir=.*|sdk.dir=$SDK_DIR|" "$LOCAL_PROPERTIES"
    else
        echo "sdk.dir=$SDK_DIR" >> "$LOCAL_PROPERTIES"
    fi
    echo -e "${GREEN}✓ SDK configurado: $SDK_DIR${NC}"
else
    echo -e "${YELLOW}⚠ SDK no detectado automáticamente. Configura sdk.dir en local.properties${NC}"
fi

# Agregar o actualizar ndk.dir
if [ -n "$ANDROID_NDK_HOME" ]; then
    if grep -q "^ndk.dir=" "$LOCAL_PROPERTIES"; then
        sed -i "s|^ndk.dir=.*|ndk.dir=$ANDROID_NDK_HOME|" "$LOCAL_PROPERTIES"
    else
        echo "ndk.dir=$ANDROID_NDK_HOME" >> "$LOCAL_PROPERTIES"
    fi
    echo -e "${GREEN}✓ NDK configurado: $ANDROID_NDK_HOME${NC}"
fi

# Agregar rutas de dependencias nativas
for ABI in $ABIS; do
    ABI_NORMALIZED=${ABI//-/_}
    cat >> "$PROJECT_ROOT/android/local.properties" << EOF

# Rutas de dependencias nativas para $ABI (generadas por build-complete.sh)
native.openssl.$ABI=$BUILD_DIR/openssl/build_${ABI_NORMALIZED}/installed
native.curl.$ABI=$BUILD_DIR/libcurl/build_${ABI_NORMALIZED}/installed
native.sqlcipher.$ABI=$BUILD_DIR/sqlcipher/build_${ABI_NORMALIZED}/installed
EOF
done

echo -e "${GREEN}✓ local.properties actualizado${NC}"

# Preguntar tipo de build
echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}¿Qué tipo de APK deseas generar?${NC}"
echo -e "  1) Debug (por defecto, más rápido, para desarrollo)"
echo -e "  2) Release (optimizado, requiere keystore para firmar)"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
read -p "Selecciona [1/2] (default: 1): " BUILD_TYPE_INPUT
BUILD_TYPE_INPUT=${BUILD_TYPE_INPUT:-1}
KEYSTORE_OPTION=""

if [ "$BUILD_TYPE_INPUT" = "2" ]; then
    BUILD_TYPE="release"
    BUILD_TASK="assembleRelease"
    APK_DIR="release"
    
    # Verificar si existe keystore configurado
    KEYSTORE_FILE="$PROJECT_ROOT/android/app/keystore.jks"
    KEYSTORE_PROPS="$PROJECT_ROOT/android/keystore.properties"
    
    # Cambiar al directorio android para crear el keystore
    cd "$PROJECT_ROOT/android"
    
    if [ ! -f "$KEYSTORE_FILE" ] || [ ! -f "$KEYSTORE_PROPS" ]; then
        echo -e "\n${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}Configuración de Keystore para Release${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "Para generar una APK Release firmada, necesitas un keystore."
        echo -e "Opciones:"
        echo -e "  1) Crear un nuevo keystore (recomendado para desarrollo)"
        echo -e "  2) Usar un keystore existente"
        echo -e "  3) Generar APK sin firmar (no instalable en dispositivos)"
        read -p "Selecciona [1/2/3] (default: 1): " KEYSTORE_OPTION
        KEYSTORE_OPTION=${KEYSTORE_OPTION:-1}
        
        case "$KEYSTORE_OPTION" in
            1)
                echo -e "\n${YELLOW}Creando nuevo keystore...${NC}"
                read -p "Alias del keystore (default: telegramcloud): " KEYSTORE_ALIAS
                KEYSTORE_ALIAS=${KEYSTORE_ALIAS:-telegramcloud}
                read -sp "Contraseña del keystore: " KEYSTORE_PASSWORD
                echo ""
                read -sp "Confirmar contraseña: " KEYSTORE_PASSWORD_CONFIRM
                echo ""
                
                if [ "$KEYSTORE_PASSWORD" != "$KEYSTORE_PASSWORD_CONFIRM" ]; then
                    echo -e "${RED}Error: Las contraseñas no coinciden${NC}"
                    exit 1
                fi
                
                read -p "Nombre completo (default: Telegram Cloud): " KEY_NAME
                KEY_NAME=${KEY_NAME:-"Telegram Cloud"}
                read -p "Organización (default: Telegram Cloud): " KEY_ORG
                KEY_ORG=${KEY_ORG:-"Telegram Cloud"}
                read -p "Ciudad (default: Unknown): " KEY_CITY
                KEY_CITY=${KEY_CITY:-"Unknown"}
                read -p "Estado/Provincia (default: Unknown): " KEY_STATE
                KEY_STATE=${KEY_STATE:-"Unknown"}
                read -p "País (código de 2 letras, default: US): " KEY_COUNTRY
                KEY_COUNTRY=${KEY_COUNTRY:-"US"}
                
                # Crear keystore
                keytool -genkey -v -keystore "app/keystore.jks" \
                    -alias "$KEYSTORE_ALIAS" \
                    -keyalg RSA -keysize 2048 -validity 10000 \
                    -storepass "$KEYSTORE_PASSWORD" \
                    -keypass "$KEYSTORE_PASSWORD" \
                    -dname "CN=$KEY_NAME, OU=$KEY_ORG, O=$KEY_ORG, L=$KEY_CITY, ST=$KEY_STATE, C=$KEY_COUNTRY" \
                    2>&1
                
                if [ $? -ne 0 ]; then
                    echo -e "${RED}Error: No se pudo crear el keystore${NC}"
                    exit 1
                fi
                
                # Crear keystore.properties en la raíz del proyecto Android
                cat > "keystore.properties" << EOF
storeFile=app/keystore.jks
storePassword=$KEYSTORE_PASSWORD
keyAlias=$KEYSTORE_ALIAS
keyPassword=$KEYSTORE_PASSWORD
EOF
                chmod 600 "keystore.properties"
                
                echo -e "${GREEN}✓ Keystore creado exitosamente${NC}"
                echo -e "${YELLOW}⚠ IMPORTANTE: Guarda la contraseña del keystore de forma segura${NC}"
                echo -e "${YELLOW}   Sin ella no podrás actualizar la app en el futuro${NC}"
                ;;
            2)
                read -p "Ruta al archivo keystore (.jks o .keystore): " EXISTING_KEYSTORE
                if [ ! -f "$EXISTING_KEYSTORE" ]; then
                    echo -e "${RED}Error: El archivo keystore no existe${NC}"
                    exit 1
                fi
                
                # Copiar keystore al proyecto
                cp "$EXISTING_KEYSTORE" "app/keystore.jks"
                
                read -sp "Contraseña del keystore: " KEYSTORE_PASSWORD
                echo ""
                read -p "Alias del keystore: " KEYSTORE_ALIAS
                
                # Crear keystore.properties en la raíz del proyecto Android
                cat > "keystore.properties" << EOF
storeFile=app/keystore.jks
storePassword=$KEYSTORE_PASSWORD
keyAlias=$KEYSTORE_ALIAS
keyPassword=$KEYSTORE_PASSWORD
EOF
                chmod 600 "keystore.properties"
                
                echo -e "${GREEN}✓ Keystore configurado${NC}"
                ;;
            3)
                echo -e "${YELLOW}Generando APK Release sin firmar...${NC}"
                echo -e "${YELLOW}⚠ Esta APK NO se puede instalar en dispositivos${NC}"
                ;;
        esac
    else
        echo -e "${GREEN}✓ Keystore ya configurado${NC}"
    fi
else
    BUILD_TYPE="debug"
    BUILD_TASK="assembleDebug"
    APK_DIR="debug"
fi

# Compilar APK
echo -e "\n${BLUE}Compilando APK ${BUILD_TYPE^^} con Gradle...${NC}"
cd "$PROJECT_ROOT/android"
./gradlew "$BUILD_TASK"

# Buscar la APK generada
APK_PATH=""
if [ "$BUILD_TYPE" = "release" ]; then
    if [ -f "app/build/outputs/apk/release/app-release.apk" ]; then
        APK_PATH="app/build/outputs/apk/release/app-release.apk"
    elif [ -f "app/build/outputs/apk/release/app-release-unsigned.apk" ]; then
        APK_PATH="app/build/outputs/apk/release/app-release-unsigned.apk"
    fi
else
    if [ -f "app/build/outputs/apk/debug/app-debug.apk" ]; then
        APK_PATH="app/build/outputs/apk/debug/app-debug.apk"
    fi
fi

if [ -n "$APK_PATH" ] && [ -f "$APK_PATH" ]; then
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

