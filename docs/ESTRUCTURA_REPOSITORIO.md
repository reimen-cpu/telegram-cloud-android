# Estructura del Repositorio para GitHub

Este documento describe qué incluir en el repositorio de GitHub para permitir que cualquier usuario compile la app desde cero.

## ✅ Qué DEBE estar en el repositorio

### Código fuente de la aplicación
```
android/                          # Proyecto Android principal
├── app/
│   ├── src/main/java/           # Código Kotlin de la app
│   └── build.gradle.kts         # Configuración de build
├── build.gradle.kts
├── settings.gradle.kts
└── gradle/                      # Wrapper de Gradle (incluir)
```

### Core nativo (C++)
```
telegram-cloud-cpp/              # Librería nativa compartida
├── include/                     # Headers C++
├── src/                         # Implementación C++
├── android_jni/                 # Wrapper JNI para Android
├── CMakeLists.txt              # Build nativo
└── third_party/
    ├── android_build_scripts/   # Scripts para compilar dependencias
    │   ├── build_openssl_android.ps1
    │   ├── build_openssl_android.sh
    │   ├── build_libcurl_android.ps1
    │   ├── build_libcurl_android.sh
    │   ├── build_sqlcipher_android.ps1
    │   └── build_sqlcipher_android.sh
    ├── json/                    # nlohmann/json (incluido)
    └── httplib/                 # cpp-httplib (si se usa)
```

### Documentación
```
README.md                        # Guía principal
BUILD_NATIVE_DEPENDENCIES.md    # Compilación de dependencias
FDROID_COMPLIANCE.md            # Cumplimiento F-Droid
ESTRUCTURA_REPOSITORIO.md       # Este archivo
LICENSE                         # Licencia GPL v3
CHANGELOG.md                    # Historial de cambios
```

## ❌ Qué NO debe estar en el repositorio

### Código fuente de dependencias externas
```
❌ sqlcipher/                   # NO incluir - clonar externamente
❌ sqlcipher-android/           # NO incluir - clonar externamente  
❌ openssl-3.2.0/              # NO incluir - descargar desde openssl.org
❌ curl-8.7.1/                 # NO incluir - descargar desde curl.se
```

**Razón:** Estas son dependencias externas grandes que deben obtenerse desde sus repositorios oficiales. Documentar cómo obtenerlas en el README.

### Artefactos de compilación
```
❌ build/                      # Ignorado por .gitignore
❌ *.apk                       # Releases van a GitHub Releases
❌ *.aab                       # No en el código fuente
❌ *.so, *.a                   # Librerías compiladas (regenerables)
❌ .gradle/                    # Cache de Gradle
❌ .idea/                      # Configuración de IDE
❌ local.properties            # Configuración local
```

### Archivos sensibles
```
❌ keystore/                   # NUNCA subir keystores
❌ *.jks, *.keystore          # Claves de firma
❌ .env                        # Variables de entorno
❌ config.ini                  # Configuración con secretos
```

## 📋 Opción 1: Submódulos de Git (Recomendado para F-Droid)

Si usas submódulos de Git, F-Droid puede clonar las dependencias automáticamente:

```bash
# Añadir SQLCipher como submódulo
git submodule add https://github.com/sqlcipher/sqlcipher.git external/sqlcipher

# Actualizar scripts para usar external/sqlcipher como srcPath por defecto
```

**Ventajas:**
- F-Droid puede clonar automáticamente
- Control de versiones de dependencias
- No duplicas código

**Desventajas:**
- Los usuarios deben hacer `git clone --recursive` o `git submodule update --init`

## 📋 Opción 2: Documentar Dependencias (Más simple)

Documentar claramente en el README cómo descargar las dependencias:

```markdown
## Dependencias Externas

Antes de compilar, descarga estas dependencias:

1. OpenSSL 3.2.0: https://www.openssl.org/source/openssl-3.2.0.tar.gz
2. libcurl 8.7.1: https://curl.se/download/curl-8.7.1.tar.gz
3. SQLCipher: git clone https://github.com/sqlcipher/sqlcipher.git
```

**Ventajas:**
- Más simple para usuarios casuales
- No necesita entender submódulos

**Desventajas:**
- F-Droid necesita configuración adicional en metadata.yml

## 🎯 Recomendación Final

Para máxima compatibilidad con F-Droid y facilidad de uso:

1. **NO incluir** carpetas `sqlcipher/`, `sqlcipher-android/`, ni fuentes de OpenSSL/curl
2. **Documentar claramente** en el README cómo descargar las fuentes
3. **Incluir scripts** de compilación que automáticamente busquen las fuentes en ubicaciones estándar
4. **Crear** un script `setup-dependencies.sh` que descargue todo automáticamente:

```bash
#!/bin/bash
# setup-dependencies.sh

DEPS_DIR="$HOME/android-native-sources"
mkdir -p "$DEPS_DIR"
cd "$DEPS_DIR"

echo "Descargando OpenSSL..."
wget -nc https://www.openssl.org/source/openssl-3.2.0.tar.gz
tar -xzf openssl-3.2.0.tar.gz

echo "Descargando libcurl..."
wget -nc https://curl.se/download/curl-8.7.1.tar.gz
tar -xzf curl-8.7.1.tar.gz

echo "Clonando SQLCipher..."
[ ! -d sqlcipher ] && git clone https://github.com/sqlcipher/sqlcipher.git

echo "Dependencias listas en: $DEPS_DIR"
```

5. **Para F-Droid**: Crear `metadata.yml` con instrucciones de build que incluyan la descarga de dependencias

## Verificación antes de subir a GitHub

```bash
# 1. Limpiar artefactos de build
cd android
./gradlew clean

# 2. Eliminar dependencias externas del repo (si existen)
cd ..
rm -rf sqlcipher/ sqlcipher-android/ openssl-* curl-*

# 3. Verificar .gitignore
git status
# No debe aparecer: build/, *.apk, *.so, local.properties

# 4. Commit y push
git add .
git commit -m "Estructura lista para GitHub/F-Droid"
git push
```

## Para el usuario que clona desde GitHub

El flujo será:

```bash
# 1. Clonar el repo
git clone https://github.com/tu-usuario/telegram-cloud-android.git
cd telegram-cloud-android

# 2. Descargar dependencias (opción A: script automático)
./setup-dependencies.sh

# 2. Descargar dependencias (opción B: manual)
# Seguir instrucciones en README.md

# 3. Compilar dependencias nativas
# Seguir BUILD_NATIVE_DEPENDENCIES.md

# 4. Configurar local.properties
# Ver README.md

# 5. Compilar la app
cd android
./gradlew assembleRelease
```

## Estado Actual

Según tu estructura, parece que ya tienes:
- ✅ `sqlcipher/` - código fuente de SQLCipher (¿debe eliminarse del repo?)
- ✅ `sqlcipher-android/` - wrapper de Android (¿debe eliminarse del repo?)
- ✅ Scripts de compilación en `telegram-cloud-cpp/third_party/android_build_scripts/`
- ✅ Documentación (README, BUILD_NATIVE_DEPENDENCIES, FDROID_COMPLIANCE)

**Decisión necesaria:** ¿Mantener `sqlcipher/` en el repo o eliminarlo y documentar cómo descargarlo?

Para F-Droid es mejor **NO incluirlo** y usar submódulos o documentar la descarga.

