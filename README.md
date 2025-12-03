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
- **Android NDK** (recomendado r25c o r26)
- **CMake 3.22+**
- **Gradle 8.0+**
- **Linux/macOS** para compilar dependencias nativas (OpenSSL, libcurl, SQLCipher)
- **Perl** (requerido para OpenSSL)

## 📦 Instalación

### Opción 1: Descargar APK (Recomendado)

1. Ve a la sección [Releases](https://github.com/reimen-cpu/telegram-cloud-android/releases)
2. Descarga la última versión de la APK
3. Instala en tu dispositivo Android

### Opción 2: Compilar desde Código Fuente

Ver sección [Compilación](#-compilación) más abajo.

## ⚙️ Configuración Inicial

1. **Crear un Bot de Telegram**:
   - Abre [@BotFather](https://t.me/BotFather) en Telegram
   - Envía `/newbot` y sigue las instrucciones
   - Guarda el token del bot

2. **Configurar el Bot** (opcional pero recomendado):
   - Envía `/setprivacy` a BotFather
   - Selecciona tu bot
   - Elige `Disable` para permitir que el bot acceda a todos los mensajes

3. **Crear un Canal** (opcional):
   - Crea un canal privado en Telegram
   - Agrega tu bot como administrador con permisos de envío
   - Obtén el ID del canal (puedes usar [@userinfobot](https://t.me/userinfobot))

4. **Configurar la Aplicación**:
   - Abre Telegram Cloud Android
   - Ingresa el token del bot
   - Ingresa el ID del canal (opcional)
   - Guarda la configuración

## 🎯 Uso Básico

### Subir Archivos

1. Toca el botón de subida en la pantalla principal
2. Selecciona uno o múltiples archivos
3. Los archivos se subirán automáticamente a Telegram
4. Archivos grandes (>4MB) se dividen automáticamente en fragmentos

### Descargar Archivos

1. Toca cualquier archivo en la lista
2. Selecciona "Descargar"
3. El archivo se descargará a tu carpeta de Descargas

### Sincronizar Galería

1. Ve a la sección "Galería"
2. Toca "Escanear medios" para encontrar fotos y videos
3. Toca "Sincronizar todo" para subir todos los medios a Telegram

### Compartir Archivos

1. Selecciona uno o múltiples archivos
2. Toca "Compartir"
3. Define una contraseña
4. Se generará un archivo `.link` que puedes compartir
5. Otros usuarios pueden descargar usando el archivo `.link` y la contraseña

### Crear Backup

1. Ve a Configuración
2. Toca "Crear backup"
3. Define una contraseña
4. El backup se guardará en tu carpeta de Descargas

## 🔨 Compilación

### Compilación Completa (Linux/macOS)

El script `build-complete.sh` automatiza todo el proceso:

```bash
# 1. Clonar el repositorio
git clone https://github.com/reimen-cpu/telegram-cloud-android.git
cd telegram-cloud-android

# 2. Ejecutar script de compilación completa
./scripts/shell/build-complete.sh
```

El script:
- Verifica herramientas necesarias
- Detecta Android NDK automáticamente
- Descarga dependencias (OpenSSL, libcurl, SQLCipher)
- Compila dependencias nativas para arm64-v8a y armeabi-v7a
- Compila la APK con Gradle

### Compilación Manual

#### 1. Configurar Variables de Entorno

```bash
export ANDROID_NDK_HOME="$HOME/android-sdk/ndk/26.3.11579264"
export ANDROID_HOME="$HOME/android-sdk"
export API=28
export ABIS="arm64-v8a armeabi-v7a"
```

#### 2. Descargar Dependencias

```bash
./scripts/shell/setup-dependencies.sh
```

#### 3. Compilar Dependencias Nativas

```bash
# Para cada ABI
for ABI in arm64-v8a armeabi-v7a; do
  # OpenSSL
  ./telegram-cloud-cpp/third_party/android_build_scripts/build_openssl_android.sh \
    -ndk "$ANDROID_NDK_HOME" \
    -abi "$ABI" \
    -api 28 \
    -srcPath "$HOME/android-native-sources/openssl-3.2.0" \
    -outDir "$HOME/android-native-builds/openssl"

  # libcurl
  ./telegram-cloud-cpp/third_party/android_build_scripts/build_libcurl_android.sh \
    -ndk "$ANDROID_NDK_HOME" \
    -abi "$ABI" \
    -api 28 \
    -opensslDir "$HOME/android-native-builds/openssl/build_${ABI//-/_}/installed" \
    -srcPath "$HOME/android-native-sources/curl-8.7.1" \
    -outDir "$HOME/android-native-builds/libcurl"

  # SQLCipher
  ./telegram-cloud-cpp/third_party/android_build_scripts/build_sqlcipher_android.sh \
    -ndk "$ANDROID_NDK_HOME" \
    -abi "$ABI" \
    -api 28 \
    -opensslDir "$HOME/android-native-builds/openssl/build_${ABI//-/_}/installed" \
    -srcPath "$HOME/android-native-sources/sqlcipher" \
    -outDir "$HOME/android-native-builds/sqlcipher"
done
```

#### 4. Configurar local.properties

```properties
sdk.dir=/ruta/a/android-sdk
ndk.dir=/ruta/a/android-sdk/ndk/26.3.11579264
native.openssl.arm64-v8a=/ruta/a/android-native-builds/openssl/build_arm64_v8a/installed
native.curl.arm64-v8a=/ruta/a/android-native-builds/libcurl/build_arm64_v8a/installed
native.sqlcipher.arm64-v8a=/ruta/a/android-native-builds/sqlcipher/build_arm64_v8a/installed
native.openssl.armeabi-v7a=/ruta/a/android-native-builds/openssl/build_armeabi_v7a/installed
native.curl.armeabi-v7a=/ruta/a/android-native-builds/libcurl/build_armeabi_v7a/installed
native.sqlcipher.armeabi-v7a=/ruta/a/android-native-builds/sqlcipher/build_armeabi_v7a/installed
```

#### 5. Compilar APK

```bash
cd android
./gradlew assembleDebug    # Para APK de depuración
./gradlew assembleRelease  # Para APK de release (requiere keystore)
```

### Compilación en Windows

Ver [docs/REQUISITOS_WINDOWS.md](docs/REQUISITOS_WINDOWS.md) para instrucciones específicas de Windows.

## 📁 Estructura del Proyecto

```
telegram-cloud-android/
├── README.md                      # Este archivo
├── CHANGELOG.md                   # Historial de cambios
├── LICENSE                        # Licencia GPL v3
├── metadata.yml                   # Metadatos para F-Droid
│
├── docs/                          # Documentación
│   ├── BUILD_NATIVE_DEPENDENCIES.md
│   ├── BUILD_ARCHITECTURE.md
│   ├── FDROID_COMPLIANCE.md
│   ├── REQUISITOS_WINDOWS.md
│   └── ...
│
├── scripts/                       # Scripts de automatización
│   ├── shell/
│   │   ├── setup-dependencies.sh
│   │   └── build-complete.sh
│   └── powershell/
│       ├── setup-dependencies.ps1
│       └── build-complete.ps1
│
├── android/                       # Proyecto Android
│   ├── app/
│   │   ├── src/main/java/        # Código Kotlin
│   │   └── src/main/res/         # Recursos Android
│   └── build.gradle.kts
│
└── telegram-cloud-cpp/            # Core nativo C++
    ├── include/                   # Headers C++
    ├── src/                       # Código fuente C++
    ├── android_jni/               # JNI bindings
    └── third_party/
        └── android_build_scripts/ # Scripts de compilación nativa
```

## 🏗️ Arquitectura

- **Frontend**: Android (Kotlin + Jetpack Compose)
- **Backend**: C++ nativo compartido con versión desktop
- **Comunicación**: JNI para interacción entre Kotlin y C++
- **Almacenamiento**: SQLCipher (base de datos cifrada)
- **Red**: libcurl con OpenSSL
- **Sincronización**: WorkManager para operaciones en segundo plano

## 🔒 Seguridad

- **Base de datos cifrada**: SQLCipher con clave derivada de credenciales
- **Almacenamiento seguro**: DataStore para tokens y configuración
- **Backups protegidos**: Archivos ZIP cifrados con contraseña
- **Enlaces protegidos**: Archivos `.link` requieren contraseña para descargar
- **Sin servicios externos**: Todo se almacena en tus propios canales/chats de Telegram

## 🤝 Contribuir

Las contribuciones son bienvenidas. Por favor:

1. Fork el repositorio
2. Crea una rama para tu feature (`git checkout -b feature/AmazingFeature`)
3. Commit tus cambios (`git commit -m 'Add some AmazingFeature'`)
4. Push a la rama (`git push origin feature/AmazingFeature`)
5. Abre un Pull Request

## 📝 Licencia

Este proyecto está licenciado bajo la **GNU General Public License v3.0** - ver el archivo [LICENSE](LICENSE) para más detalles.

## 🔗 Enlaces

- **Repositorio**: [https://github.com/reimen-cpu/telegram-cloud-android](https://github.com/reimen-cpu/telegram-cloud-android)
- **Releases**: [https://github.com/reimen-cpu/telegram-cloud-android/releases](https://github.com/reimen-cpu/telegram-cloud-android/releases)
- **Issues**: [https://github.com/reimen-cpu/telegram-cloud-android/issues](https://github.com/reimen-cpu/telegram-cloud-android/issues)
- **Autor**: [Reimen Torres](https://github.com/reimen-cpu)

## ⚠️ Notas Importantes

- Esta aplicación utiliza la API de Telegram Bot para almacenar archivos
- Los archivos se almacenan en tus propios canales/chats de Telegram
- **No hay límites de tamaño de archivo ni de almacenamiento** gracias a la subida por fragmentos
- La aplicación no depende de servicios propietarios
- Todas las dependencias son de código abierto
- Compatible con F-Droid (ver [docs/FDROID_COMPLIANCE.md](docs/FDROID_COMPLIANCE.md))

---

**Tu nube, tus reglas.** 🚀
