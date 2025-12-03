# Compilación de Dependencias Nativas para Android

Este documento describe el proceso para compilar las dependencias nativas requeridas por Telegram Cloud Android: OpenSSL, libcurl y SQLCipher.

## Requisitos Previos

- Android NDK r25c o superior
- Android SDK con API nivel 24 o superior
- CMake 3.22 o superior
- Fuentes de OpenSSL 3.x
- Fuentes de libcurl 8.x
- Fuentes de SQLCipher

## Descarga de Fuentes

### OpenSSL
```bash
wget https://www.openssl.org/source/openssl-3.2.0.tar.gz
tar -xzf openssl-3.2.0.tar.gz
```

### libcurl
```bash
wget https://curl.se/download/curl-8.7.1.tar.gz
tar -xzf curl-8.7.1.tar.gz
```

### SQLCipher
```bash
git clone https://github.com/sqlcipher/sqlcipher.git
cd sqlcipher
# Asegúrate de usar una versión compatible
```

## Compilación

Los scripts de compilación están ubicados en `telegram-cloud-cpp/third_party/android_build_scripts/`.

### Scripts Disponibles

- `build_openssl_android.sh` (Linux/macOS only)
- `build_libcurl_android.sh` (Linux/macOS only)
- `build_sqlcipher_android.sh` (Linux/macOS only)

### Linux/macOS (Recomendado)

```bash
export NDK="/ruta/al/android-ndk-r25c"
export API=24
export ABI="arm64-v8a"
export OUT_DIR="/ruta/donde/guardar/librerias"

# Compilar OpenSSL
./telegram-cloud-cpp/third_party/android_build_scripts/build_openssl_android.sh \
  -ndk "$NDK" \
  -abi "$ABI" \
  -api $API \
  -srcPath "/ruta/a/openssl-3.2.0" \
  -outDir "$OUT_DIR/openssl"

# Compilar libcurl (requiere OpenSSL)
./telegram-cloud-cpp/third_party/android_build_scripts/build_libcurl_android.sh \
  -ndk "$NDK" \
  -abi "$ABI" \
  -api $API \
  -opensslDir "$OUT_DIR/openssl/build_arm64" \
  -srcPath "/ruta/a/curl-8.7.1" \
  -outDir "$OUT_DIR/libcurl"

# Compilar SQLCipher (requiere OpenSSL)
./telegram-cloud-cpp/third_party/android_build_scripts/build_sqlcipher_android.sh \
  -ndk "$NDK" \
  -abi "$ABI" \
  -api $API \
  -opensslDir "$OUT_DIR/openssl/build_arm64" \
  -srcPath "/ruta/a/sqlcipher" \
  -outDir "$OUT_DIR/sqlcipher"
```

### Nota sobre Windows

Los scripts de autobuild están diseñados solo para Linux/macOS con Linux NDK. Si necesitas compilar en Windows, usa WSL con Linux NDK o compila manualmente con herramientas Windows.

## Múltiples ABIs

Para compilar para múltiples arquitecturas (arm64-v8a, armeabi-v7a, x86_64), repite el proceso anterior para cada ABI cambiando el parámetro `-abi`.

## Configuración en el Proyecto Android

Una vez compiladas las librerías, configura las rutas en `android/local.properties`:

```properties
sdk.dir=/ruta/a/android/sdk
ndk.dir=/ruta/a/android/ndk/25.2.9519653

# Librerías nativas (ajusta las rutas según tu configuración)
native.openssl.arm64-v8a=/ruta/a/openssl/build_arm64
native.openssl.armeabi-v7a=/ruta/a/openssl/build_armv7
native.curl.arm64-v8a=/ruta/a/libcurl/build_arm64
native.curl.armeabi-v7a=/ruta/a/libcurl/build_armv7
native.sqlcipher.arm64-v8a=/ruta/a/sqlcipher/build_arm64
native.sqlcipher.armeabi-v7a=/ruta/a/sqlcipher/build_armv7
```

Alternativamente, puedes usar variables de entorno:

```bash
export VCPKG_ROOT="/ruta/a/vcpkg/installed/arm64-android"
```

## Para F-Droid

F-Droid necesita poder compilar estas dependencias desde fuente. Asegúrate de que:

1. Los scripts de compilación estén incluidos en el repositorio
2. Las instrucciones estén claramente documentadas
3. Los scripts no dependan de herramientas propietarias
4. Se especifiquen las versiones exactas de las fuentes utilizadas

### Versiones Recomendadas

- OpenSSL: 3.2.0 o superior
- libcurl: 8.7.1 o superior
- SQLCipher: versión estable más reciente del repositorio oficial

### Verificación

Después de compilar, verifica que se generaron los siguientes archivos:

- `libssl.a` y `libcrypto.a` (OpenSSL)
- `libcurl.a` (libcurl)
- `libsqlcipher.a` (SQLCipher)

Estos archivos deben estar en las carpetas `lib` de sus respectivos directorios de salida.

## Notas Importantes

- SQLCipher debe compilarse con las mismas configuraciones de cifrado que la versión de escritorio si necesitas compatibilidad binaria de bases de datos
- Los backups son independientes de plataforma pero los detalles de cifrado deben coincidir
- Las librerías compiladas son específicas de cada ABI; no puedes usar una librería arm64 en un dispositivo armeabi-v7a

## Solución de Problemas

### Error: NDK not found
Asegúrate de que la variable `NDK` apunte a la ruta correcta del NDK.

### Error: OpenSSL not found al compilar libcurl
Verifica que la ruta de OpenSSL sea correcta y que las librerías estén compiladas.

### Error: CMake not found
Instala CMake y asegúrate de que esté en tu PATH.

## Referencias

- [Documentación de Android NDK](https://developer.android.com/ndk/guides)
- [OpenSSL Documentation](https://www.openssl.org/docs/)
- [libcurl Documentation](https://curl.se/docs/)
- [SQLCipher Documentation](https://www.zetetic.net/sqlcipher/)

