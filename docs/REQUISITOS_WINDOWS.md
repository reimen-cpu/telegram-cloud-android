# Requisitos para Compilar en Windows

Para compilar Telegram Cloud Android en Windows, necesitas instalar algunas herramientas adicionales debido a que las dependencias nativas (OpenSSL, libcurl, SQLCipher) requieren herramientas de compilación Unix.

## ✅ Herramientas Requeridas

### 1. Git for Windows
**Incluye:** Git, Bash, Perl, herramientas Unix básicas

- **Descarga:** https://git-scm.com/download/win
- **Instalar:** Selecciona "Use Git and optional Unix tools from the Command Prompt"

**Verificar instalación:**
```powershell
git --version
bash --version
perl --version
```

### 2. Android Studio
**Incluye:** Android SDK, NDK, CMake

- **Descarga:** https://developer.android.com/studio
- **Instalar componentes:**
  - Android SDK Platform 34
  - Android NDK r25c (25.2.9519653)
  - CMake 3.22.1

**Verificar instalación:**
```powershell
sdkmanager --list_installed
# Debe mostrar ndk;25.2.9519653 y cmake;3.22.1
```

### 3. Ninja Build System
**Incluye:** Sistema de build rápido para CMake

- **Opción A:** Ya incluido en Android SDK (CMake trae Ninja)
- **Opción B:** Descargar desde https://github.com/ninja-build/ninja/releases

**Verificar:**
```powershell
ninja --version
```

## 🔧 Variables de Entorno

Configura estas variables de entorno (o el script las detectará automáticamente):

```powershell
$env:ANDROID_HOME = "C:\Android"  # Ajustar según tu instalación
$env:ANDROID_NDK_HOME = "C:\Android\ndk\25.2.9519653"
```

## 🚀 Proceso de Compilación

### Opción 1: Script Automático (Recomendado)

```powershell
# Clonar repositorio
git clone https://github.com/reimen-cpu/telegram-cloud-android
cd telegram-cloud-android

# Ejecutar build completo
.\build-complete.ps1
```

**Tiempo estimado:** 20-30 minutos en la primera compilación

### Opción 2: Paso a Paso

```powershell
# 1. Descargar dependencias
.\setup-dependencies.ps1

# 2. Compilar OpenSSL
.\telegram-cloud-cpp\third_party\android_build_scripts\build_openssl_android.ps1 `
    -ndk "C:\Android\ndk\25.2.9519653" `
    -abi "arm64-v8a" `
    -api 28 `
    -srcPath "C:\Users\$env:USERNAME\android-native-sources\openssl-3.2.0" `
    -outDir "C:\Users\$env:USERNAME\android-native-builds\openssl"

# 3. Compilar libcurl
.\telegram-cloud-cpp\third_party\android_build_scripts\build_libcurl_android.ps1 `
    -ndk "C:\Android\ndk\25.2.9519653" `
    -abi "arm64-v8a" `
    -api 28 `
    -opensslDir "C:\Users\$env:USERNAME\android-native-builds\openssl\build_arm64_v8a" `
    -srcPath "C:\Users\$env:USERNAME\android-native-sources\curl-8.7.1" `
    -outDir "C:\Users\$env:USERNAME\android-native-builds\libcurl"

# 4. Compilar SQLCipher
.\telegram-cloud-cpp\third_party\android_build_scripts\build_sqlcipher_android.ps1 `
    -ndk "C:\Android\ndk\25.2.9519653" `
    -abi "arm64-v8a" `
    -api 28 `
    -opensslDir "C:\Users\$env:USERNAME\android-native-builds\openssl\build_arm64_v8a" `
    -srcPath "C:\Users\$env:USERNAME\android-native-sources\sqlcipher" `
    -outDir "C:\Users\$env:USERNAME\android-native-builds\sqlcipher"

# 5. Compilar APK
cd android
.\gradlew.bat assembleRelease
```

## ⚠️ Problemas Comunes

### Error: Perl no encontrado
```
Perl no está instalado. OpenSSL requiere Perl para compilar.
```

**Solución:** Instalar Git for Windows (incluye Perl) o Strawberry Perl

### Error: Bash no encontrado
```
Bash no está instalado. SQLCipher requiere bash para compilar.
```

**Solución:** Instalar Git for Windows (incluye Bash)

### Error: NDK no encontrado
```
Error: Android NDK no encontrado
```

**Solución:**
1. Instalar NDK desde Android Studio: Tools → SDK Manager → SDK Tools → NDK (Side by side)
2. Verificar versión: `sdkmanager --list_installed | grep ndk`
3. Debe ser r25c (25.2.9519653)

### Error: make not found
```
make: The term 'make' is not recognized
```

**Solución:** Asegúrate que Git for Windows esté en PATH:
```powershell
$env:PATH += ";C:\Program Files\Git\usr\bin"
```

### Error: CMake no encuentra Ninja
```
CMake Error: CMake was unable to find a build program corresponding to "Ninja"
```

**Solución:**
1. El Ninja de Android SDK debe estar en PATH
2. O agregar manualmente: `$env:PATH += ";C:\Android\cmake\3.22.1\bin\ninja.exe"`

## 💡 Alternativa: WSL (Windows Subsystem for Linux)

Si tienes problemas con las herramientas Windows, usa WSL:

```powershell
# Instalar WSL
wsl --install

# En WSL
wsl
cd /mnt/c/Users/$USER/telegram-cloud-android
chmod +x *.sh
./build-complete.sh
```

**Ventajas:**
- Entorno Linux nativo
- Todos los scripts .sh funcionan sin modificación
- Más confiable para compilación de dependencias Unix

## 📊 Requisitos de Sistema

- **CPU:** Procesador de 4+ núcleos recomendado
- **RAM:** 8GB mínimo, 16GB recomendado
- **Disco:** ~10GB libres para dependencias y builds
- **SO:** Windows 10 versión 1903 o superior (para WSL2)

## 🎯 Verificación Final

Después de instalar todo:

```powershell
# Verificar todas las herramientas
git --version
bash --version
perl --version
cmake --version
ninja --version
sdkmanager --list_installed

# Todo debe mostrar versiones correctas
```

## 🔗 Enlaces Útiles

- [Git for Windows](https://git-scm.com/download/win)
- [Android Studio](https://developer.android.com/studio)
- [Android NDK](https://developer.android.com/ndk)
- [Strawberry Perl](https://strawberryperl.com/) (alternativa)
- [WSL Documentation](https://docs.microsoft.com/windows/wsl/)

