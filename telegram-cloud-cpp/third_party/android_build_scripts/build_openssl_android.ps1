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
$PATH_BACKUP = $env:PATH
$env:PATH = "$ndkToolchain/bin;$env:PATH"
$env:ANDROID_NDK_ROOT = $ndk

Push-Location $buildDir

try {
    Write-Host "Configuring OpenSSL for $opensslTarget (API $api)..."
    
    # Check if perl is available
    $perlPath = Get-Command perl -ErrorAction SilentlyContinue
    if (-not $perlPath) {
        throw @"
Perl is not installed. OpenSSL requires Perl to build.

Options:
1. Install Strawberry Perl: https://strawberryperl.com/
2. Install Git for Windows (includes Perl): https://git-scm.com/download/win
3. Use WSL: wsl --install and build from Linux

After installing, restart PowerShell and run this script again.
"@
    }
    
    Write-Host "✓ Perl found: $($perlPath.Source)"
    
    # Configure OpenSSL with correct parameters
    $configArgs = @(
        $opensslTarget,
        "-D__ANDROID_API__=$api",
        "no-shared",
        "--prefix=$buildDir/installed",
        "--openssldir=$buildDir/installed"
    )
    
    Write-Host "Running: perl Configure $($configArgs -join ' ')"
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
