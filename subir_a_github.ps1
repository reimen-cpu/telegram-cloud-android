# Script para subir Telegram Cloud Android a GitHub
# Ejecutar desde el directorio raíz del proyecto

Write-Host "=== Preparando repositorio para GitHub ===" -ForegroundColor Cyan

# Verificar que estamos en el directorio correcto
$currentDir = Get-Location
Write-Host "Directorio actual: $currentDir" -ForegroundColor Yellow

# Verificar que existe la carpeta android
if (-not (Test-Path "android")) {
    Write-Host "ERROR: No se encontró la carpeta 'android'" -ForegroundColor Red
    exit 1
}

# Verificar que existe la carpeta telegram-cloud-cpp
if (-not (Test-Path "telegram-cloud-cpp")) {
    Write-Host "ERROR: No se encontró la carpeta 'telegram-cloud-cpp'" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Verificando archivos sensibles ===" -ForegroundColor Cyan

# Verificar que keystore no se va a subir
if (Test-Path "keystore") {
    Write-Host "✓ Carpeta keystore encontrada (será excluida por .gitignore)" -ForegroundColor Green
} else {
    Write-Host "✓ No hay carpeta keystore" -ForegroundColor Green
}

# Verificar .gitignore
if (Test-Path ".gitignore") {
    Write-Host "✓ .gitignore encontrado" -ForegroundColor Green
    
    # Verificar que keystore está en .gitignore
    $gitignoreContent = Get-Content ".gitignore" -Raw
    if ($gitignoreContent -match "keystore") {
        Write-Host "✓ keystore está en .gitignore" -ForegroundColor Green
    } else {
        Write-Host "⚠ ADVERTENCIA: keystore no está en .gitignore" -ForegroundColor Yellow
    }
} else {
    Write-Host "⚠ ADVERTENCIA: No se encontró .gitignore" -ForegroundColor Yellow
}

Write-Host "`n=== Configurando Git ===" -ForegroundColor Cyan

# Inicializar git si no existe
if (-not (Test-Path ".git")) {
    Write-Host "Inicializando repositorio Git..." -ForegroundColor Yellow
    git init
} else {
    Write-Host "✓ Repositorio Git ya existe" -ForegroundColor Green
}

# Configurar remoto
$remoteUrl = "https://github.com/reimen-cpu/telegram-cloud-android.git"
$currentRemote = git remote get-url origin 2>$null

if ($currentRemote) {
    Write-Host "Remoto actual: $currentRemote" -ForegroundColor Yellow
    $changeRemote = Read-Host "¿Cambiar el remoto a $remoteUrl? (s/n)"
    if ($changeRemote -eq "s" -or $changeRemote -eq "S") {
        git remote remove origin
        git remote add origin $remoteUrl
        Write-Host "✓ Remoto configurado" -ForegroundColor Green
    }
} else {
    git remote add origin $remoteUrl
    Write-Host "✓ Remoto agregado" -ForegroundColor Green
}

Write-Host "`n=== Preparando archivos para commit ===" -ForegroundColor Cyan

# Agregar archivos principales
Write-Host "Agregando archivos principales..." -ForegroundColor Yellow
git add .gitignore
git add README.md
git add LICENSE
git add CHANGELOG.md
git add metadata.yml
git add BUILD_NATIVE_DEPENDENCIES.md
git add FDROID_COMPLIANCE.md
git add GUIA_SUBIR_GITHUB.md

Write-Host "Agregando proyecto Android..." -ForegroundColor Yellow
git add android/

Write-Host "Agregando telegram-cloud-cpp..." -ForegroundColor Yellow
git add telegram-cloud-cpp/

Write-Host "`n=== Estado de los archivos ===" -ForegroundColor Cyan
git status --short

Write-Host "`n=== IMPORTANTE: Revisa la lista de arriba ===" -ForegroundColor Yellow
Write-Host "Asegúrate de que NO aparezcan:" -ForegroundColor Yellow
Write-Host "  - keystore/" -ForegroundColor Red
Write-Host "  - local.properties" -ForegroundColor Red
Write-Host "  - Proyectos no relacionados (ab-download-manager, Gallery, etc.)" -ForegroundColor Red

$continuar = Read-Host "`n¿Todo se ve bien? ¿Continuar con el commit? (s/n)"

if ($continuar -ne "s" -and $continuar -ne "S") {
    Write-Host "Cancelado. Puedes revisar y ejecutar manualmente:" -ForegroundColor Yellow
    Write-Host "  git status" -ForegroundColor Cyan
    Write-Host "  git commit -m 'Initial commit'" -ForegroundColor Cyan
    exit 0
}

Write-Host "`n=== Creando commit ===" -ForegroundColor Cyan
$commitMessage = @"
Initial commit: Telegram Cloud Android app

- Android app with Jetpack Compose UI
- Native C++ core (telegram-cloud-cpp)
- Documentation for F-Droid compliance
- Build scripts for native dependencies
- GPL v3 license
"@

git commit -m $commitMessage

Write-Host "✓ Commit creado" -ForegroundColor Green

Write-Host "`n=== Configurando rama main ===" -ForegroundColor Cyan
git branch -M main

Write-Host "`n=== Listo para subir ===" -ForegroundColor Cyan
Write-Host "Ejecuta el siguiente comando para subir a GitHub:" -ForegroundColor Yellow
Write-Host "  git push -u origin main" -ForegroundColor Cyan
Write-Host "`nO ejecuta este script con el parámetro -push para subir automáticamente:" -ForegroundColor Yellow
Write-Host "  .\subir_a_github.ps1 -push" -ForegroundColor Cyan

if ($args -contains "-push") {
    Write-Host "`n=== Subiendo a GitHub ===" -ForegroundColor Cyan
    git push -u origin main
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n✓ ¡Subido exitosamente a GitHub!" -ForegroundColor Green
        Write-Host "Visita: https://github.com/reimen-cpu/telegram-cloud-android" -ForegroundColor Cyan
    } else {
        Write-Host "`n✗ Error al subir. Verifica tu autenticación con GitHub." -ForegroundColor Red
    }
}

