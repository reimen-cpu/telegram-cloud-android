param(
    [string]$ndk,
    [string]$abi = "arm64-v8a",
    [int]$api = 28,
    [string]$srcPath,
    [string]$outDir
)

$ErrorActionPreference = "Stop"

# Validate required parameters
if (-not $ndk -or -not $srcPath -or -not $outDir) {
    Write-Error "Usage: -ndk <ndk-path> -srcPath <openssl-source> -outDir <output-dir>"
    Write-Host "Example: .\build_openssl_android.ps1 -ndk C:\Android\ndk\25.2.9519653 -srcPath C:\sources\openssl-3.2.0 -outDir C:\builds\openssl"
    exit 1
}

if (-not (Test-Path $srcPath)) {
    Write-Error "OpenSSL source path not found: $srcPath"
    exit 1
}

if (-not (Test-Path $ndk)) {
    Write-Error "NDK path not found: $ndk"
    exit 1
}

# Map ABI to OpenSSL architecture
$archMap = @{
    "arm64-v8a" = "android-arm64"
    "armeabi-v7a" = "android-arm"
    "x86" = "android-x86"
    "x86_64" = "android-x86_64"
}

if (-not $archMap.ContainsKey($abi)) {
    Write-Error "Unsupported ABI: $abi. Use: arm64-v8a, armeabi-v7a, x86, x86_64"
    exit 1
}

$opensslTarget = $archMap[$abi]
$abiNormalized = $abi -replace "-", "_"
$buildDir = Join-Path $outDir "build_$abiNormalized"

# Clean previous build
if (Test-Path $buildDir) {
    Write-Host "Cleaning previous build..."
    Remove-Item -Recurse -Force $buildDir
}

New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

# Copy sources to build dir (OpenSSL needs to configure in-place)
Write-Host "Copying OpenSSL sources..."
Copy-Item -Recurse -Force "$srcPath/*" $buildDir

# Configure environment for NDK
$ndkToolchain = Join-Path $ndk "toolchains/llvm/prebuilt/windows-x86_64"
if (-not (Test-Path $ndkToolchain)) {
    Write-Error "NDK toolchain not found: $ndkToolchain"
    exit 1
}

$PATH_BACKUP = $env:PATH
$env:ANDROID_NDK_ROOT = $ndk
$env:ANDROID_NDK_HOME = $ndk

# CRITICAL: Add NDK to PATH first (use proper Windows path separators)
$ndkBinPath = Join-Path $ndkToolchain "bin"
$env:PATH = "$ndkBinPath;$env:PATH"
Write-Host "✓ NDK toolchain agregado al PATH: $ndkBinPath"

# Debug: Show NDK environment
Write-Host "  ANDROID_NDK_ROOT: $env:ANDROID_NDK_ROOT"

Push-Location $buildDir

try {
    Write-Host "Configuring OpenSSL for $opensslTarget (API $api)..."
    
    # Check if perl is available - prioritize Strawberry Perl over Git Perl
    # Git Perl is minimal and lacks modules needed by OpenSSL (Locale::Maketext::Simple)
    $perlPath = $null
    
    # First try: Strawberry Perl (complete distribution with all modules)
    $strawberryPaths = @(
        "C:\Strawberry\perl\bin",
        "$env:SystemDrive\Strawberry\perl\bin",
        "$env:ProgramFiles\Strawberry\perl\bin"
    )
    
    foreach ($sbPath in $strawberryPaths) {
        if (Test-Path "$sbPath\perl.exe") {
            Write-Host "✓ Strawberry Perl encontrado: $sbPath"
            # PREPEND to PATH to keep NDK at front
            $env:PATH = "$sbPath;$env:PATH"
            $perlPath = Get-Command perl -ErrorAction SilentlyContinue
            break
        }
    }
    
    # Second try: System PATH
    if (-not $perlPath) {
        $perlPath = Get-Command perl -ErrorAction SilentlyContinue
        if ($perlPath) {
            Write-Host "✓ Perl encontrado en PATH: $($perlPath.Source)"
        }
    }
    
    # Last resort: Git for Windows (may lack required modules)
    if (-not $perlPath) {
        $gitPerlPaths = @(
            "C:\Program Files\Git\usr\bin",
            "C:\Program Files (x86)\Git\usr\bin",
            "$env:ProgramFiles\Git\usr\bin",
            "${env:ProgramFiles(x86)}\Git\usr\bin"
        )
        
        foreach ($gitPath in $gitPerlPaths) {
            if (Test-Path "$gitPath\perl.exe") {
                Write-Host "⚠ Usando Git Perl (puede faltar módulos). Recomendado: Strawberry Perl"
                Write-Host "  Descargar: https://strawberryperl.com/"
                $env:PATH = "$gitPath;$env:PATH"
                $perlPath = Get-Command perl -ErrorAction SilentlyContinue
                break
            }
        }
    }
    
    if (-not $perlPath) {
        throw @"
Perl no encontrado. OpenSSL requiere Perl con módulos completos.

RECOMENDADO - Instalar Strawberry Perl:
  https://strawberryperl.com/
  Incluye todos los módulos que OpenSSL necesita.

Alternativas:
  - Usar WSL: wsl --install y compilar desde Linux

Después de instalar, reiniciar PowerShell y ejecutar este script nuevamente.
"@
    }
    
    Write-Host "✓ Perl: $($perlPath.Source)"
    
    # Check if make is available (OpenSSL needs GNU make)
    $makePath = Get-Command make -ErrorAction SilentlyContinue
    
    if (-not $makePath) {
        # Try gmake (common in Strawberry Perl)
        $makePath = Get-Command gmake -ErrorAction SilentlyContinue
        if ($makePath) {
            Set-Alias -Name make -Value gmake -Scope Script
            Write-Host "✓ Make: gmake (Strawberry Perl)"
        }
    }
    
    if (-not $makePath) {
        # Search in Strawberry Perl installation
        $strawberryMakePaths = @(
            "C:\Strawberry\c\bin\gmake.exe",
            "C:\Strawberry\c\bin\mingw32-make.exe"
        )
        
        foreach ($makeBin in $strawberryMakePaths) {
            if (Test-Path $makeBin) {
                $strawberryBinDir = Split-Path -Parent $makeBin
                # PREPEND to keep NDK/Perl at front
                $env:PATH = "$strawberryBinDir;$env:PATH"
                $makeCmd = Split-Path -Leaf $makeBin
                $makeCmd = $makeCmd -replace '\.exe$', ''
                Set-Alias -Name make -Value $makeCmd -Scope Script
                Write-Host "✓ Make: $makeCmd (Strawberry Perl)"
                $makePath = Get-Command $makeCmd -ErrorAction SilentlyContinue
                break
            }
        }
    }
    
    if (-not $makePath) {
        # Try Git for Windows
        $gitBinPaths = @(
            "C:\Program Files\Git\usr\bin",
            "C:\Program Files (x86)\Git\usr\bin",
            "$env:ProgramFiles\Git\usr\bin"
        )
        foreach ($gitPath in $gitBinPaths) {
            if (Test-Path "$gitPath\make.exe") {
                # PREPEND to keep NDK/Perl at front
                $env:PATH = "$gitPath;$env:PATH"
                Write-Host "✓ Make encontrado en Git for Windows"
                $makePath = Get-Command make -ErrorAction SilentlyContinue
                break
            }
        }
    }
    
    if (-not $makePath) {
        throw @"
Make no encontrado. OpenSSL requiere GNU Make para compilar.

RECOMENDADO:
- Strawberry Perl incluye gmake: https://strawberryperl.com/
  Ya tienes Perl, verifica que C:\Strawberry\c\bin esté en PATH

Alternativa:
- Instalar Git for Windows: https://git-scm.com/download/win

Después de instalar, reiniciar PowerShell y ejecutar este script nuevamente.
"@
    }
    
    # Configure NDK environment variables for OpenSSL
    # Problem: OpenSSL busca "aarch64-linux-android-clang" pero NDK r25c tiene "aarch64-linux-android28-clang"
    # Solución: Crear wrappers temporales sin el número API
    $target = switch ($abi) {
        "arm64-v8a" { "aarch64-linux-android" }
        "armeabi-v7a" { "armv7a-linux-androideabi" }
        "x86" { "i686-linux-android" }
        "x86_64" { "x86_64-linux-android" }
    }
    
    # Crear directorio temporal para wrappers
    $wrapperDir = Join-Path $buildDir "ndk_wrappers"
    New-Item -ItemType Directory -Force -Path $wrapperDir | Out-Null
    
    # Crear wrappers que llamen a los compiladores reales con API level
    $compilerReal = Join-Path $ndkBinPath "$target$api-clang.cmd"
    $compilerPlusReal = Join-Path $ndkBinPath "$target$api-clang++.cmd"
    
    if (-not (Test-Path $compilerReal)) {
        throw "NDK compiler not found: $compilerReal`nVerify NDK installation."
    }
    
    # Wrapper para clang (sin número API en el nombre)
    $clangWrapper = Join-Path $wrapperDir "$target-clang.cmd"
    "@echo off`n`"$compilerReal`" %*" | Out-File -FilePath $clangWrapper -Encoding ASCII
    
    # Wrapper para clang++
    $clangPlusWrapper = Join-Path $wrapperDir "$target-clang++.cmd"
    "@echo off`n`"$compilerPlusReal`" %*" | Out-File -FilePath $clangPlusWrapper -Encoding ASCII
    
    # Agregar wrapper dir al PATH (ANTES del NDK real)
    $env:PATH = "$wrapperDir;$env:PATH"
    
    Write-Host "✓ NDK compiler wrappers creados"
    Write-Host "  $target-clang.cmd → $target$api-clang.cmd"
    Write-Host "  Wrapper dir: $wrapperDir"
    Write-Host "  ANDROID_NDK_HOME: $env:ANDROID_NDK_HOME"
    
    # Configure OpenSSL with correct parameters
    $installPrefix = $buildDir -replace '\\', '/'
    $configArgs = @(
        $opensslTarget,
        "-D__ANDROID_API__=$api",
        "no-shared",
        "--prefix=$installPrefix/installed",
        "--openssldir=$installPrefix/installed"
    )
    
    Write-Host "`nEjecutando OpenSSL Configure..."
    Write-Host "perl Configure $($configArgs -join ' ')"
    Write-Host "`nEsto puede tardar 1-2 minutos...`n"
    & perl Configure @configArgs
    
    if ($LASTEXITCODE -ne 0) {
        throw "Configure failed with exit code: $LASTEXITCODE"
    }
    
    Write-Host "Building OpenSSL (this may take 10-15 minutes)..."
    & make -j$([Environment]::ProcessorCount)
    
    if ($LASTEXITCODE -ne 0) {
        throw "Make failed with exit code: $LASTEXITCODE"
    }
    
    Write-Host "Installing OpenSSL..."
    & make install_sw
    
    if ($LASTEXITCODE -ne 0) {
        throw "Install failed with exit code: $LASTEXITCODE"
    }
    
    Write-Host "`n✓ OpenSSL built successfully"
    Write-Host "Location: $buildDir/installed"
    Write-Host "Include: $buildDir/installed/include"
    Write-Host "Libs: $buildDir/installed/lib"
    
} catch {
    Write-Error "Error building OpenSSL: $_"
    Pop-Location
    $env:PATH = $PATH_BACKUP
    exit 1
}

Pop-Location
$env:PATH = $PATH_BACKUP
