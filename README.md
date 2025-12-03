# Telegram Cloud Android

Aplicación Android para gestionar archivos en la nube usando Telegram como backend, no hay limites de tamaño por archivo, no hay limites de almacenamiento total. Tu nube, tus reglas.

Para descargar la apk directamente: https://github.com/reimen-cpu/telegram-cloud-android/releases/tag/v1.0.0

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

## Compilación

### Prerrequisitos

1. **Android Studio Hedgehog o superior**
2. **Android SDK y NDK r25c o superior**
3. **Librerías nativas compiladas**:
   - OpenSSL 3.x
   - libcurl 8.x
   - SQLCipher

### Configuración del entorno

1. Clona el repositorio:
```bash
git clone https://github.com/reimen-cpu/telegram-cloud-android
cd android
```

2. **Compilar dependencias nativas** (ver sección abajo)

3. Configura las rutas de las librerías nativas. Puedes hacerlo de dos formas:

   **Opción A: Variables de entorno (recomendado para CI/F-Droid)**
   ```bash
   export VCPKG_ROOT=/ruta/a/vcpkg/installed/arm64-android
   ```

   **Opción B: Archivo local.properties** (solo para desarrollo local, no se sube al repo)
   ```properties
   sdk.dir=/ruta/a/android/sdk
   ndk.dir=/ruta/a/android/ndk/25.2.9519653
   native.openssl.arm64-v8a=/ruta/a/openssl/installed/arm64-android
   native.curl.arm64-v8a=/ruta/a/curl/installed/arm64-android
   native.sqlcipher.arm64-v8a=/ruta/a/sqlcipher/installed/arm64-android
   ```

4. Abre el proyecto en Android Studio y sincroniza Gradle

5. Compila la aplicación:
```bash
./gradlew assembleRelease
```

## Compilación de dependencias nativas

El proyecto requiere librerías nativas compiladas para Android. Consulta [telegram-cloud-cpp/README-android.md](telegram-cloud-cpp/README-android.md) para instrucciones detalladas.

### Resumen rápido:

1. Descarga los fuentes de OpenSSL, libcurl y SQLCipher
2. Usa los scripts en `telegram-cloud-cpp/third_party/android_build_scripts/`:
   ```powershell
   # Ejemplo para Windows (PowerShell)
   .\telegram-cloud-cpp\third_party\android_build_scripts\build_openssl_android.ps1 -ndk $NDK -abi arm64-v8a -api 24 -srcPath $OPENSSL_SRC -outDir $OUTPUT
   ```
3. Configura las rutas en `local.properties` o variables de entorno

### Para F-Droid

F-Droid compilará las dependencias desde fuente. Asegúrate de que:
- Los scripts de compilación estén incluidos en el repositorio
- Las instrucciones estén documentadas en el README
- No haya dependencias de binarios precompilados

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

## Enlaces relacionados

- [telegram-cloud-cpp](telegram-cloud-cpp/) - Core nativo compartido
- [Documentación de compilación para Android](telegram-cloud-cpp/README-android.md)

