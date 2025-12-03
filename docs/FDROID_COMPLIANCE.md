# Verificación de Cumplimiento F-Droid

Este documento verifica el cumplimiento del proyecto con las políticas de F-Droid.

## ✅ Servicios Propietarios

- **No usa Google Play Services**: Verificado - no se encontraron dependencias de GMS
- **No usa Firebase**: Verificado - no se encontraron dependencias de Firebase
- **No usa servicios propietarios**: La aplicación solo se comunica con Telegram Bot API (público)

## ✅ Dependencias Open Source

Todas las dependencias son de código abierto:

### Bibliotecas Android
- AndroidX Core, Lifecycle, Activity, Navigation - Apache 2.0
- Jetpack Compose - Apache 2.0
- Material Design Components - Apache 2.0
- Room Database - Apache 2.0
- WorkManager - Apache 2.0
- DataStore - Apache 2.0

### Bibliotecas de Red
- Retrofit - Apache 2.0
- OkHttp - Apache 2.0
- Moshi - Apache 2.0

### Otras Bibliotecas
- SQLCipher - BSD-style license
- Coil - Apache 2.0
- Glide - Apache 2.0 / BSD
- Media3/ExoPlayer - Apache 2.0
- Gson - Apache 2.0
- Kotlin Coroutines - Apache 2.0

### Código Nativo
- OpenSSL - Apache 2.0 / Dual license
- libcurl - MIT/X derivate license
- SQLCipher - BSD-style license
- nlohmann/json - MIT

## ✅ Permisos Justificados

Todos los permisos tienen justificación clara:

1. **INTERNET** - Necesario para comunicarse con Telegram Bot API
2. **READ_MEDIA_IMAGES/VIDEO/AUDIO** - Necesario para sincronizar galería de medios
3. **READ_EXTERNAL_STORAGE** (API ≤ 32) - Compatibilidad con versiones antiguas
4. **POST_NOTIFICATIONS** - Mostrar progreso de uploads/downloads
5. **FOREGROUND_SERVICE** - Ejecutar operaciones en segundo plano
6. **FOREGROUND_SERVICE_DATA_SYNC** - Específico para sincronización de datos
7. **VIBRATE** - Feedback háptico para acciones del usuario

## ✅ Tracking y Analytics

- **No hay código de tracking**: Verificado
- **No hay analytics**: Verificado
- **No hay recopilación de datos de usuarios**: La aplicación solo se comunica con Telegram

## ✅ Código Fuente

- **Código fuente completo disponible**: Sí, en el repositorio
- **Licencia compatible**: GPL v3 (compatible con F-Droid)
- **Sin binarios propietarios**: Todos los binarios se compilan desde fuente

## ✅ Dependencias Nativas

- **Compilables desde fuente**: Sí, con scripts incluidos
- **Instrucciones documentadas**: Ver BUILD_NATIVE_DEPENDENCIES.md
- **Sin dependencias de binarios precompilados**: Las librerías se compilan durante el build

## ✅ Build Configuration

- **No depende de local.properties críticamente**: El build puede usar variables de entorno
- **Reproducible**: El build es reproducible con las instrucciones documentadas
- **Sin claves secretas hardcodeadas**: No se encontraron claves en el código

## ✅ Manifest

- **No requiere root**: `android:requestLegacyExternalStorage` no presente
- **Backup configurado**: `allowBackup="true"` con reglas personalizadas
- **Exported components seguros**: Solo MainActivity está exported (necesario para launcher)

## ⚠️ Notas para F-Droid

1. **Dependencias nativas**: F-Droid necesitará compilar OpenSSL, libcurl y SQLCipher. Los scripts están en `telegram-cloud-cpp/third_party/android_build_scripts/`

2. **Versiones específicas**: Asegurar que se usen versiones compatibles:
   - OpenSSL 3.x
   - libcurl 8.x
   - SQLCipher última versión estable

3. **Metadata**: El archivo `metadata.yml` está incluido como referencia, pero F-Droid requerirá crear su propia entrada en `fdroiddata`

4. **Capturas de pantalla**: Preparar al menos 2-3 capturas para F-Droid

## ✅ Conclusión

El proyecto cumple con todas las políticas de F-Droid:

- ✅ Software libre (GPL v3)
- ✅ Sin servicios propietarios
- ✅ Dependencias open source
- ✅ Permisos justificados
- ✅ Sin tracking/analytics
- ✅ Código fuente completo disponible
- ✅ Build reproducible

Listo para solicitud de inclusión en F-Droid.

