# Telegram Cloud Android

Aplicación Android para gestionar archivos en la nube usando Telegram como backend, no hay limites de tamaño por archivo, no hay limites de almacenamiento total. Tu nube, tus reglas.

Para descargar la apk directamente: https://github.com/reimen-cpu/telegram-cloud-android/releases/tag/v1.0.0
<<<<<<< HEAD

## 🚀 Inicio Rápido

### Opción A: Build Automático (Todo en uno)

```bash
# Linux/macOS
git clone https://github.com/reimen-cpu/telegram-cloud-android
cd telegram-cloud-android
chmod +x scripts/shell/*.sh      # Dar permisos de ejecución
./scripts/shell/build-complete.sh   # Descarga + compila + genera APK
```

```powershell
# Windows (PowerShell como Administrador)
git clone https://github.com/reimen-cpu/telegram-cloud-android
cd telegram-cloud-android
.\scripts\powershell\build-complete.ps1   # Descarga + compila + genera APK
```

El script automático:
1. ✓ Descarga OpenSSL, libcurl y SQLCipher
2. ✓ Compila las tres librerías para Android
3. ✓ Configura `local.properties` automáticamente
4. ✓ Genera la APK release

**Tiempo estimado:** 15-30 minutos (dependiendo de tu hardware).

### Opción B: Paso a Paso Manual

Si prefieres control manual del proceso:

```bash
# 1. Clonar repositorio
git clone https://github.com/reimen-cpu/telegram-cloud-android
cd telegram-cloud-android

# 2. Descargar dependencias
chmod +x scripts/shell/setup-dependencies.sh   # Linux/macOS
./scripts/shell/setup-dependencies.sh

# 3. Compilar dependencias nativas (ver guía completa abajo)

# 4. Configurar local.properties con las rutas

# 5. Compilar APK
cd android
./gradlew assembleRelease
```

**¿Primera vez?** Ver la guía completa en [Compilación desde Código Fuente](#compilación-desde-código-fuente).

## Características

- 📤 **Subida y descarga de archivos**: Gestiona tus archivos en Telegram con interfaz nativa de Android
- 🖼️ **Galería de medios**: Sincroniza automáticamente tus fotos y videos con la nube
- 🔐 **Backups cifrados**: Crea y restaura backups protegidos con contraseña
- 🔗 **Compartir enlaces**: Genera archivos `.link` para compartir múltiples archivos fácilmente
- 📱 **Interfaz moderna**: UI construida con Jetpack Compose y Material Design 3
- 🔄 **Sincronización en segundo plano**: Uploads y downloads continúan ejecutándose con WorkManager
- 🔍 **Búsqueda y filtrado**: Encuentra tus archivos rápidamente con búsqueda y ordenamiento
- 💾 **Base de datos cifrada**: Utiliza SQLCipher para almacenar datos de forma segura

## Requisitos

- Android 9.0 (API 28) o superior
- Bot de Telegram configurado con permisos apropiados
- Canal de Telegram (opcional, para almacenamiento)

## Compilación desde Código Fuente

### Prerrequisitos

1. **Android Studio Hedgehog o superior**
2. **Android SDK** con API 28 o superior
3. **Android NDK r25c** (específicamente: 25.2.9519653)
4. **CMake 3.22** o superior (incluido con Android SDK)
5. **Git** para clonar el repositorio

**Windows:** Requiere herramientas adicionales (Perl, Bash). Ver [REQUISITOS_WINDOWS.md](docs/REQUISITOS_WINDOWS.md) para guía completa.

### Paso 1: Clonar el Repositorio

```bash
git clone https://github.com/reimen-cpu/telegram-cloud-android
cd telegram-cloud-android
```

### Paso 2: Descargar Dependencias Nativas

El proyecto requiere tres librerías nativas: **OpenSSL, libcurl y SQLCipher**. 

#### 2.1 Opción A: Script Automático (Recomendado)

Usa el script incluido que descarga todo automáticamente:

```bash
# Linux/macOS
./scripts/shell/setup-dependencies.sh
```

```powershell
# Windows (PowerShell)
.\scripts\powershell\setup-dependencies.ps1
```

Esto descargará las fuentes en `~/android-native-sources` (Linux/macOS) o `%USERPROFILE%\android-native-sources` (Windows).

#### 2.2 Opción B: Descarga Manual

Si prefieres descargar manualmente:

```bash
# Linux/macOS
mkdir -p ~/android-native-sources
cd ~/android-native-sources

# Descargar OpenSSL 3.2.0
wget https://www.openssl.org/source/openssl-3.2.0.tar.gz
tar -xzf openssl-3.2.0.tar.gz

# Descargar libcurl 8.7.1
wget https://curl.se/download/curl-8.7.1.tar.gz
tar -xzf curl-8.7.1.tar.gz

# Clonar SQLCipher
git clone https://github.com/sqlcipher/sqlcipher.git
```

```powershell
# Windows (PowerShell) - Descargar y extraer manualmente:
# 1. OpenSSL: https://www.openssl.org/source/openssl-3.2.0.tar.gz
# 2. libcurl: https://curl.se/download/curl-8.7.1.tar.gz
# 3. SQLCipher: git clone https://github.com/sqlcipher/sqlcipher.git
# Extraer todo en: C:\android-native-sources\
```

### Paso 3: Compilar las Dependencias Nativas

**Variables de entorno comunes:**

```bash
# Linux/macOS
export NDK="$HOME/Android/Sdk/ndk/25.2.9519653"
export API=28
export ABI="arm64-v8a"
export OUT_DIR="$HOME/android-native-builds"
export SRC_DIR="$HOME/android-native-sources"
```

```powershell
# Windows (PowerShell)
$env:NDK = "C:\Android\Sdk\ndk\25.2.9519653"  # Ajustar según tu instalación
$API = 28
$ABI = "arm64-v8a"
$OUT_DIR = "C:\android-native-builds"
$SRC_DIR = "C:\android-native-sources"
```

**Compilar en orden (cada librería depende de la anterior):**

```bash
# Linux/macOS
cd telegram-cloud-android

# 1. OpenSSL
./telegram-cloud-cpp/third_party/android_build_scripts/build_openssl_android.sh \
  -ndk "$NDK" -abi "$ABI" -api $API \
  -srcPath "$SRC_DIR/openssl-3.2.0" \
  -outDir "$OUT_DIR/openssl"

# 2. libcurl (necesita OpenSSL)
./telegram-cloud-cpp/third_party/android_build_scripts/build_libcurl_android.sh \
  -ndk "$NDK" -abi "$ABI" -api $API \
  -opensslDir "$OUT_DIR/openssl/build_arm64" \
  -srcPath "$SRC_DIR/curl-8.7.1" \
  -outDir "$OUT_DIR/libcurl"

# 3. SQLCipher (necesita OpenSSL)
./telegram-cloud-cpp/third_party/android_build_scripts/build_sqlcipher_android.sh \
  -ndk "$NDK" -abi "$ABI" -api $API \
  -opensslDir "$OUT_DIR/openssl/build_arm64" \
  -srcPath "$SRC_DIR/sqlcipher" \
  -outDir "$OUT_DIR/sqlcipher"
```

```powershell
# Windows (PowerShell)
cd telegram-cloud-android

# 1. OpenSSL
.\telegram-cloud-cpp\third_party\android_build_scripts\build_openssl_android.ps1 `
  -ndk $env:NDK -abi $ABI -api $API `
  -srcPath "$SRC_DIR\openssl-3.2.0" `
  -outDir "$OUT_DIR\openssl"

# 2. libcurl (necesita OpenSSL)
.\telegram-cloud-cpp\third_party\android_build_scripts\build_libcurl_android.ps1 `
  -ndk $env:NDK -abi $ABI -api $API `
  -opensslDir "$OUT_DIR\openssl\build_arm64" `
  -srcPath "$SRC_DIR\curl-8.7.1" `
  -outDir "$OUT_DIR\libcurl"

# 3. SQLCipher (necesita OpenSSL)
.\telegram-cloud-cpp\third_party\android_build_scripts\build_sqlcipher_android.ps1 `
  -ndk $env:NDK -abi $ABI -api $API `
  -opensslDir "$OUT_DIR\openssl\build_arm64" `
  -srcPath "$SRC_DIR\sqlcipher" `
  -outDir "$OUT_DIR\sqlcipher"
```

**Para compilar múltiples arquitecturas**, repite el proceso con `ABI="armeabi-v7a"` (cambia `build_arm64` por `build_armv7` en los paths).

> **Nota:** La compilación puede tardar 10-20 minutos por arquitectura dependiendo de tu hardware.

### Paso 4: Configurar Rutas de Librerías

Crea el archivo `android/local.properties` con las rutas a tus compilaciones:

```properties
sdk.dir=/ruta/a/Android/Sdk
ndk.dir=/ruta/a/Android/Sdk/ndk/25.2.9519653

# Rutas a las librerías compiladas (ajustar según tu sistema)
native.openssl.arm64-v8a=/ruta/a/android-native-builds/openssl/build_arm64
native.curl.arm64-v8a=/ruta/a/android-native-builds/libcurl/build_arm64
native.sqlcipher.arm64-v8a=/ruta/a/android-native-builds/sqlcipher/build_arm64

# Si compilaste para armeabi-v7a también:
native.openssl.armeabi-v7a=/ruta/a/android-native-builds/openssl/build_armv7
native.curl.armeabi-v7a=/ruta/a/android-native-builds/libcurl/build_armv7
native.sqlcipher.armeabi-v7a=/ruta/a/android-native-builds/sqlcipher/build_armv7
```

### Paso 5: Compilar la APK

```bash
cd android
./gradlew assembleRelease
```

La APK se generará en: `android/app/build/outputs/apk/release/app-release.apk`

### Para F-Droid

F-Droid compilará automáticamente todas las dependencias desde fuente. Ver [FDROID_COMPLIANCE.md](FDROID_COMPLIANCE.md) y [BUILD_NATIVE_DEPENDENCIES.md](BUILD_NATIVE_DEPENDENCIES.md) para más detalles.

### Solución de Problemas

**Error: `sqlite3.h` o `openssl/evp.h` not found**
- Las dependencias nativas no están compiladas o las rutas en `local.properties` son incorrectas
- Verifica que existen los archivos `.a` en las carpetas de salida
- Asegúrate de que las rutas en `local.properties` son absolutas y correctas

**Error: NDK not found**
- Instala NDK r25c desde Android Studio: Tools → SDK Manager → SDK Tools → NDK (Side by side)
- Verifica la ruta en `local.properties`

**Error en scripts de compilación**
- Verifica que los scripts tienen permisos de ejecución (Linux/macOS): `chmod +x *.sh`
- En Windows, ejecuta PowerShell como Administrador si hay problemas de permisos

## Estructura del proyecto

```
.
├── android/                 # Proyecto Android principal
│   ├── app/
│   │   ├── src/main/
│   │   │   ├── java/       # Código fuente Kotlin
│   │   │   └── res/        # Recursos Android
│   │   └── build.gradle.kts
│   └── build.gradle.kts
└── telegram-cloud-cpp/      # Core nativo C++ (biblioteca compartida)
    ├── android_jni/         # Wrapper JNI para Android
    └── third_party/         # Dependencias de terceros
```

## Configuración inicial

1. Abre la aplicación
2. Ve a Configuración (Settings)
3. Ingresa tu **Bot Token** de Telegram
4. Configura el **Channel ID** donde se almacenarán los archivos
5. Opcionalmente, configura un **Chat ID** adicional

### Obtener Bot Token

1. Abre [@BotFather](https://t.me/botfather) en Telegram
2. Crea un nuevo bot con `/newbot`
3. Copia el token proporcionado
4. Opcionalmente, configura permisos con `/setprivacy`

## Uso

### Subir archivos

1. Toca el botón "Upload" en la pantalla principal
2. Selecciona los archivos que deseas subir
3. Los archivos se subirán en segundo plano y aparecerán en tu biblioteca

### Sincronizar galería

1. Ve a la sección "Gallery"
2. Toca "Scan Media" para buscar fotos y videos en tu dispositivo
3. Selecciona los archivos que deseas sincronizar
4. Toca "Sync All" para comenzar la sincronización

### Crear backup

1. Ve al menú (☰)
2. Selecciona "Create backup"
3. Define una contraseña para cifrar el backup
4. El backup se guardará en tu dispositivo

### Restaurar backup

1. Ve al menú
2. Selecciona "Restore backup"
3. Selecciona el archivo de backup
4. Ingresa la contraseña cuando se solicite

### Compartir archivos

1. Selecciona uno o más archivos en la biblioteca
2. Toca "Share"
3. Elige crear un archivo `.link` para compartir múltiples archivos
4. El archivo se compartirá a través del selector de Android

## Tecnologías utilizadas

- **Kotlin** - Lenguaje principal
- **Jetpack Compose** - UI moderna declarativa
- **Material Design 3** - Sistema de diseño
- **Android Architecture Components** - ViewModel, Room, WorkManager
- **Retrofit** - Cliente HTTP para API de Telegram
- **SQLCipher** - Base de datos cifrada
- **C++/JNI** - Core nativo compartido con la versión de escritorio
- **CMake** - Sistema de build para código nativo

## Dependencias principales

- AndroidX (Core, Lifecycle, Compose, Navigation)
- Material Components
- Retrofit & OkHttp
- Room Database
- WorkManager
- Coil (carga de imágenes)
- Media3/ExoPlayer (reproducción de video)

## Licencia

Ver archivo [LICENSE](LICENSE) para más detalles.

## Contribuir

Las contribuciones son bienvenidas. Por favor:

1. Fork el repositorio
2. Crea una rama para tu feature (`git checkout -b feature/nueva-funcionalidad`)
3. Commit tus cambios (`git commit -am 'Añadir nueva funcionalidad'`)
4. Push a la rama (`git push origin feature/nueva-funcionalidad`)
5. Abre un Pull Request

## Soporte

Para reportar bugs o solicitar features, por favor abre un issue en GitHub.

## Notas

- Esta aplicación utiliza la API de Telegram Bot para almacenar archivos
- Los archivos se almacenan en tus propios canales/chats de Telegram
- Requiere conexión a internet para funcionar
- La sincronización funciona mejor con conexión estable

## 📚 Documentación Adicional

- [REQUISITOS_WINDOWS.md](docs/REQUISITOS_WINDOWS.md) - **Requisitos y guía para compilar en Windows**
- [BUILD_NATIVE_DEPENDENCIES.md](docs/BUILD_NATIVE_DEPENDENCIES.md) - Guía detallada de compilación de dependencias nativas
- [FDROID_COMPLIANCE.md](docs/FDROID_COMPLIANCE.md) - Verificación de cumplimiento con políticas de F-Droid
- [ESTRUCTURA_REPOSITORIO.md](docs/ESTRUCTURA_REPOSITORIO.md) - Estructura y organización del repositorio
- [telegram-cloud-cpp/README-android.md](telegram-cloud-cpp/README-android.md) - Detalles técnicos de integración JNI

## Enlaces relacionados

- [telegram-cloud-cpp](telegram-cloud-cpp/) - Core nativo compartido (C++)
- [SQLCipher](https://github.com/sqlcipher/sqlcipher) - Base de datos cifrada
- [OpenSSL](https://www.openssl.org/) - Librería criptográfica
- [libcurl](https://curl.se/) - Cliente HTTP/HTTPS

