# Guía: Subir Telegram Cloud Android a GitHub

Esta guía te mostrará paso a paso cómo subir el proyecto `android` y `telegram-cloud-cpp` al repositorio `telegram-cloud-android` en GitHub.

## Prerequisitos

- Cuenta de GitHub creada
- Git instalado en tu sistema
- Acceso a GitHub desde tu terminal (configurado con SSH o HTTPS)

## Paso 1: Verificar que los archivos sensibles estén excluidos

Asegúrate de que el `.gitignore` esté funcionando correctamente:

```bash
cd "c:\Users\Lenovo\Desktop\android app"
```

Verifica que estos archivos/carpetas NO se suban:
- `keystore/` (debe estar en .gitignore)
- `android/local.properties` (debe estar en .gitignore)
- `build/` (debe estar en .gitignore)

## Paso 2: Crear el repositorio en GitHub

1. Ve a https://github.com
2. Haz clic en el botón "+" en la esquina superior derecha
3. Selecciona "New repository"
4. Configura:
   - **Repository name**: `telegram-cloud-android`
   - **Description**: `Aplicación Android para gestionar archivos en la nube usando Telegram como backend`
   - **Visibility**: Public (requerido para F-Droid)
   - **NO marques** "Initialize this repository with a README"
   - **NO agregues** .gitignore ni LICENSE (ya los tenemos)
5. Haz clic en "Create repository"

## Paso 3: Inicializar Git en el directorio del proyecto (si no está)

```bash
cd "c:\Users\Lenovo\Desktop\android app"

# Verificar si ya hay un repositorio git
git status
```

Si ya existe un repositorio git, puedes seguir con el Paso 4. Si no, inicializa uno nuevo:

```bash
# Inicializar git (solo si no existe)
git init
```

## Paso 4: Configurar el repositorio remoto

```bash
# Verificar remotos existentes
git remote -v

# Si ya existe un remoto, elimínalo o renómbralo
git remote remove origin  # Solo si ya existe

# Agregar el remoto de GitHub
git remote add origin https://github.com/reimen-cpu/telegram-cloud-android.git
```

## Paso 5: Preparar los archivos para el commit

### 5.1. Agregar solo los archivos necesarios

Vamos a agregar solo los proyectos que necesitas:

```bash
# Agregar archivos raíz del proyecto
git add .gitignore
git add README.md
git add LICENSE
git add CHANGELOG.md
git add metadata.yml
git add BUILD_NATIVE_DEPENDENCIES.md
git add FDROID_COMPLIANCE.md

# Agregar proyecto Android
git add android/

# Agregar telegram-cloud-cpp
git add telegram-cloud-cpp/
```

### 5.2. Verificar qué se va a subir

```bash
# Ver el estado
git status

# Ver qué archivos se agregaron (preview)
git status --short
```

**IMPORTANTE**: Verifica que NO se incluyan:
- `keystore/`
- `local.properties`
- `build/`
- Proyectos no relacionados (ab-download-manager, Gallery, M3UAndroid, sqlcipher, sqlcipher-android)

Si ves alguno de estos, revisa el `.gitignore` y ajusta si es necesario.

## Paso 6: Hacer el commit inicial

```bash
git commit -m "Initial commit: Telegram Cloud Android app

- Android app with Jetpack Compose UI
- Native C++ core (telegram-cloud-cpp)
- Documentation for F-Droid compliance
- Build scripts for native dependencies
- GPL v3 license"
```

## Paso 7: Configurar la rama principal (main/master)

```bash
# Renombrar la rama actual a main (si es necesario)
git branch -M main

# O si prefieres master
# git branch -M master
```

## Paso 8: Subir a GitHub

```bash
# Subir al repositorio remoto
git push -u origin main
```

Si GitHub te pide autenticación:
- **HTTPS**: Te pedirá usuario y token de acceso personal
- **SSH**: Asegúrate de tener configuradas tus claves SSH

## Paso 9: Verificar en GitHub

1. Ve a https://github.com/reimen-cpu/telegram-cloud-android
2. Verifica que todos los archivos estén presentes
3. Verifica que NO estén los archivos sensibles (keystore, local.properties)

## Estructura Final del Repositorio

Tu repositorio debe verse así:

```
telegram-cloud-android/
├── .gitignore
├── README.md
├── LICENSE
├── CHANGELOG.md
├── metadata.yml
├── BUILD_NATIVE_DEPENDENCIES.md
├── FDROID_COMPLIANCE.md
├── android/
│   ├── app/
│   ├── build.gradle.kts
│   ├── settings.gradle.kts
│   └── ...
└── telegram-cloud-cpp/
    ├── CMakeLists.txt
    ├── src/
    ├── include/
    ├── android_jni/
    └── ...
```

## Solución de Problemas

### Error: "fatal: remote origin already exists"

```bash
git remote remove origin
git remote add origin https://github.com/reimen-cpu/telegram-cloud-android.git
```

### Error: "Permission denied" o problemas de autenticación

**Opción 1: Usar Personal Access Token (HTTPS)**
1. Ve a GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Genera un nuevo token con permisos `repo`
3. Usa el token como contraseña cuando Git lo pida

**Opción 2: Configurar SSH**
```bash
# Generar clave SSH (si no tienes)
ssh-keygen -t ed25519 -C "reimentorresl@gmail.com"

# Agregar la clave a ssh-agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Copiar la clave pública
cat ~/.ssh/id_ed25519.pub
# Pegar en GitHub → Settings → SSH and GPG keys → New SSH key

# Cambiar el remoto a SSH
git remote set-url origin git@github.com:reimen-cpu/telegram-cloud-android.git
```

### Error: Archivos sensibles se van a subir

```bash
# Detener el proceso
git reset

# Verificar .gitignore
cat .gitignore

# Agregar excepciones al .gitignore si es necesario
# Luego volver a agregar archivos
```

### Si accidentalmente ya subiste archivos sensibles

```bash
# Eliminar del historial de Git (CUIDADO: esto reescribe la historia)
git rm --cached android/local.properties
git rm --cached -r keystore/

# Hacer commit de la eliminación
git commit -m "Remove sensitive files"

# Si ya los subiste, necesitarás hacer force push (solo en repos nuevos)
git push -f origin main
```

## Próximos Pasos

1. ✅ Verificar que todo esté en GitHub
2. ✅ Crear un release inicial (v1.0.0) en GitHub
3. ✅ Actualizar el README con badges si lo deseas
4. ✅ Preparar para solicitar inclusión en F-Droid

## Notas Importantes

- **NUNCA** subas el archivo `keystore/telegram-cloud-release.jks` a GitHub
- **NUNCA** subas `local.properties` con tus rutas locales
- El repositorio debe ser **público** para F-Droid
- Mantén el historial limpio y descriptivo en los commits

