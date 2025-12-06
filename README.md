# Telegram Cloud Android

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Android](https://img.shields.io/badge/Android-9.0%2B-green.svg)](https://www.android.com/)

Aplicación Android para gestionar archivos en la nube usando Telegram como backend. **Tu nube, tus reglas.**

## 🚀 Características Principales

### Sin Límites de Tamaño ni Almacenamiento

**⚠️ IMPORTANTE: Esta aplicación NO tiene límites de tamaño de archivo ni de almacenamiento.**

- **Archivos grandes**: Utiliza subida por fragmentos (chunked upload) de 4MB para archivos de cualquier tamaño
- **Almacenamiento ilimitado**: Telegram no impone límites prácticos de almacenamiento
- **Múltiples bots**: Soporte para múltiples tokens de bot para mayor capacidad y velocidad
- **Subida paralela**: Los fragmentos se suben en paralelo usando todos los bots disponibles

### Funcionalidades

- 📤 **Subida y descarga de archivos** con interfaz nativa de Android
- 🖼️ **Galería de medios** con sincronización automática de fotos y videos
- 🔐 **Backups cifrados** con contraseña
- 🔗 **Generación de archivos .link** para compartir múltiples archivos fácilmente
- 📱 **Interfaz moderna** construida con Jetpack Compose y Material Design 3
- 🔄 **Sincronización en segundo plano** con WorkManager
- 🔍 **Búsqueda y filtrado** de archivos
- 💾 **Base de datos cifrada** con SQLCipher
- 📥 **Descarga desde enlaces** protegidos con contraseña
- 🎬 **Reproducción de videos** con Media3/ExoPlayer
- 🔒 **Gestión de permisos** para Android 13+ (Media permissions)
- ⚡ **Operaciones en lote** para múltiples archivos

## 📋 Requisitos

- **Android 9.0 (API 28)** o superior
- **Bot de Telegram** configurado con permisos apropiados
- **Canal de Telegram** (opcional, para almacenamiento)
- **Conexión a Internet** para sincronizar archivos

### Para Compilar desde Código Fuente

- **Android SDK** con API 28+
- **Android NDK** (Versión probada: **r25c** / `25.2.9519653`)
- **CMake 3.22+**
- **Gradle 8.0+**
- **Linux/WSL** (Recomendado Ubuntu 22.04+)
- **Paquetes del sistema**: `git`, `wget`, `tar`, `perl`, `build-essential`, `tcl`, `dos2unix`

## 📦 Instalación

### Opción 1: Descargar APK (Recomendado)

1. Ve a la sección [Releases](https://github.com/reimen-cpu/telegram-cloud-android/releases)
2. Descarga la última versión de la APK
3. Instala en tu dispositivo Android

### Opción 2: Compilar desde Código Fuente

Ver sección [Compilación Manual](#-compilación-manual) más abajo.

## ⚙️ Configuración Inicial

1. **Crear un Bot de Telegram**:
   - Abre [@BotFather](https://t.me/BotFather) en Telegram
   - Envía `/newbot` y sigue las instrucciones
   - Guarda el token del bot

2. **Configurar la Aplicación**:
   - Abre Telegram Cloud Android
   - Ingresa el token del bot
   - Ingresa el ID del canal (opcional)
   - Guarda la configuración

## 🔨 Compilación Manual

⚠️ **Nota:** Los scripts automáticos (`build-complete.sh`) se encuentran en desarrollo. Para garantizar una compilación exitosa sin errores de dependencias, sigue este procedimiento manual paso a paso.

### 1. Configurar Entorno

Instala las herramientas necesarias y define las variables de entorno. Ajusta `ANDROID_NDK_HOME` según tu instalación real.

```bash
# Instalar dependencias del sistema (Ubuntu/Debian/WSL)
sudo apt-get update
sudo apt-get install -y git wget tar perl build-essential tcl dos2unix

# Definir variables (Ajusta la versión del NDK si es diferente)
export ANDROID_HOME="$HOME/android-sdk"
export ANDROID_NDK_HOME="$HOME/android-sdk/ndk/25.2.9519653"
export API=28
2. Crear Wrapper para CMake
Este paso es crítico. Crea un "wrapper" que intercepta las llamadas a CMake para inyectar las rutas de OpenSSL y corregir flags incompatibles con Ninja (como -j vacío).
code
Bash
mkdir -p "$HOME/cmake-wrap"
cat > "$HOME/cmake-wrap/cmake" << 'EOF'
#!/bin/bash
# Wrapper para corregir compilación en Android NDK

for arg in "$@"; do
  # Corregir error de Ninja: "-j" vacío -> "-jN"
  if [ "$arg" = "--build" ]; then
    exec /usr/bin/cmake --build . -- -j$(nproc)
  fi
  # Corregir error de Ninja: "--config Release" no soportado
  if [ "$arg" = "--install" ]; then
    exec /usr/bin/cmake --install .
  fi
done

# Inyectar rutas de OpenSSL y forzar librerías estáticas
exec /usr/bin/cmake \
  -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DOPENSSL_ROOT_DIR="$OPENSSL_ROOT_DIR" \
  -DOPENSSL_INCLUDE_DIR="$OPENSSL_ROOT_DIR/include" \
  -DOPENSSL_CRYPTO_LIBRARY="$OPENSSL_ROOT_DIR/lib/libcrypto.a" \
  -DOPENSSL_SSL_LIBRARY="$OPENSSL_ROOT_DIR/lib/libssl.a" \
  "$@"
EOF

chmod +x "$HOME/cmake-wrap/cmake"
export PATH="$HOME/cmake-wrap:$PATH"
3. Descargar y Preparar Código Fuente
Descargamos las dependencias y preparamos SQLCipher manualmente (generando la amalgamación y el archivo CMakeLists.txt).
code
Bash
mkdir -p $HOME/android-native-sources
cd $HOME/android-native-sources

# --- Descargar ---
wget https://www.openssl.org/source/openssl-3.2.0.tar.gz && tar xf openssl-3.2.0.tar.gz
wget https://curl.se/download/curl-8.7.1.tar.gz && tar xf curl-8.7.1.tar.gz
git clone https://github.com/sqlcipher/sqlcipher.git

# --- Preparar SQLCipher ---
cd sqlcipher
./configure
make sqlite3.c

# Crear CMakeLists.txt para SQLCipher
cat > CMakeLists.txt << 'EOF'
cmake_minimum_required(VERSION 3.22)
project(sqlcipher C)
find_package(OpenSSL REQUIRED)
add_library(sqlcipher STATIC sqlite3.c)
target_include_directories(sqlcipher PUBLIC ${OPENSSL_INCLUDE_DIR} ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_definitions(sqlcipher PRIVATE
    -DSQLITE_HAS_CODEC -DSQLITE_TEMP_STORE=2 -DSQLITE_ENABLE_JSON1
    -DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS3_PARENTHESIS -DSQLITE_ENABLE_FTS5
    -DSQLITE_ENABLE_RTREE -DSQLCIPHER_CRYPTO_OPENSSL -DANDROID
    -DSQLITE_EXTRA_INIT=sqlcipher_extra_init
    -DSQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown
)
target_link_libraries(sqlcipher Private OpenSSL::Crypto)
install(TARGETS sqlcipher ARCHIVE DESTINATION lib)
install(FILES sqlite3.h DESTINATION include)
EOF
4. Compilar Dependencias Nativas
Regresa a la raíz del repositorio (cd ~/ruta/al/repo) y ejecuta este bloque. Compilará OpenSSL, Libcurl y SQLCipher para arm64-v8a y armeabi-v7a.
Nota: Se aplica no-asm para ARMv7 para evitar errores de relocación.
code
Bash
mkdir -p $HOME/android-native-builds/{openssl,libcurl,sqlcipher}

for ABI in arm64-v8a armeabi-v7a; do
  echo ">>> Compilando para $ABI..."
  
  # Configurar flags específicos por arquitectura
  OPENSSL_OPTS=""
  if [ "$ABI" == "armeabi-v7a" ]; then
      OPENSSL_OPTS="no-asm" # Fix para error R_ARM_REL32
  fi

  # 1. OpenSSL
  # Modificamos script al vuelo para inyectar opciones si es necesario
  sed -i "s|./Configure|./Configure $OPENSSL_OPTS -fPIC|g" telegram-cloud-cpp/third_party/android_build_scripts/build_openssl_android.sh
  
  ./telegram-cloud-cpp/third_party/android_build_scripts/build_openssl_android.sh \
    -ndk "$ANDROID_NDK_HOME" -abi "$ABI" -api "$API" \
    -srcPath "$HOME/android-native-sources/openssl-3.2.0" \
    -outDir "$HOME/android-native-builds/openssl"

  # Configurar entorno para el wrapper de CMake
  export OPENSSL_ROOT_DIR="$HOME/android-native-builds/openssl/build_${ABI}/installed"
  
  # 2. Libcurl
  ./telegram-cloud-cpp/third_party/android_build_scripts/build_libcurl_android.sh \
    -ndk "$ANDROID_NDK_HOME" -abi "$ABI" -api "$API" \
    -opensslDir "$OPENSSL_ROOT_DIR" \
    -srcPath "$HOME/android-native-sources/curl-8.7.1" \
    -outDir "$HOME/android-native-builds/libcurl"

  # Fix: Mover librería si quedó en lib64
  if [ -f "$HOME/android-native-builds/libcurl/build_${ABI}/installed/lib64/libcurl.a" ]; then
      mkdir -p "$HOME/android-native-builds/libcurl/build_${ABI}/installed/lib"
      cp "$HOME/android-native-builds/libcurl/build_${ABI}/installed/lib64/libcurl.a" \
         "$HOME/android-native-builds/libcurl/build_${ABI}/installed/lib/"
  fi

  # 3. SQLCipher
  ./telegram-cloud-cpp/third_party/android_build_scripts/build_sqlcipher_android.sh \
    -ndk "$ANDROID_NDK_HOME" -abi "$ABI" -api "$API" \
    -opensslDir "$OPENSSL_ROOT_DIR" \
    -srcPath "$HOME/android-native-sources/sqlcipher" \
    -outDir "$HOME/android-native-builds/sqlcipher"
done
5. Compilar APK con Gradle
Finalmente, configura el proyecto Android y genera la APK.
code
Bash
# 1. Crear local.properties con rutas absolutas
cat > android/local.properties <<EOF
sdk.dir=$ANDROID_HOME
ndk.dir=$ANDROID_NDK_HOME
native.openssl.arm64-v8a=$HOME/android-native-builds/openssl/build_arm64_v8a/installed
native.curl.arm64-v8a=$HOME/android-native-builds/libcurl/build_arm64_v8a/installed
native.sqlcipher.arm64-v8a=$HOME/android-native-builds/sqlcipher/build_arm64_v8a/installed
native.openssl.armeabi-v7a=$HOME/android-native-builds/openssl/build_armeabi_v7a/installed
native.curl.armeabi-v7a=$HOME/android-native-builds/libcurl/build_armeabi_v7a/installed
native.sqlcipher.armeabi-v7a=$HOME/android-native-builds/sqlcipher/build_armeabi_v7a/installed
EOF

# 2. Corregir formato de gradlew (si usas WSL)
dos2unix android/gradlew
chmod +x android/gradlew

# 3. Compilar
cd android
./gradlew assembleDebug
La APK generada estará en: android/app/build/outputs/apk/debug/app-debug.apk
📁 Estructura del Proyecto
code
Code
telegram-cloud-android/
├── README.md                      # Este archivo
├── scripts/                       # Scripts experimentales
├── android/                       # Proyecto Android (Kotlin)
├── telegram-cloud-cpp/            # Core nativo (C++)
│   ├── src/                       # Lógica compartida
│   └── third_party/               # Scripts de dependencias
🏗️ Arquitectura
Frontend: Android (Kotlin + Jetpack Compose)
Backend: C++ nativo compartido
Seguridad: SQLCipher + OpenSSL
Red: Libcurl optimizado con HTTP/2
🤝 Contribuir
Las contribuciones son bienvenidas. Haz Fork, crea una rama y envía tu Pull Request.
📝 Licencia
GNU General Public License v3.0 - ver LICENSE.
Tu nube, tus reglas. 🚀
