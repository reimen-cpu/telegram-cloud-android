# Check Build Requirements Script
# Verifies all prerequisites are met before starting the build

$ErrorActionPreference = "Stop"

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "Checking Build Requirements"
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host ""

$allGood = $true

# 1. Check for bash
Write-Host "[1/5] Checking for bash..."
$bashPath = $null
$bash = Get-Command bash -ErrorAction SilentlyContinue
if ($bash) {
    $bashPath = $bash.Source
} else {
    $gitBashPaths = @(
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files (x86)\Git\bin\bash.exe",
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe"
    )
    
    foreach ($path in $gitBashPaths) {
        if (Test-Path $path) {
            $bashPath = $path
            break
        }
    }
}

if ($bashPath) {
    Write-Host "  ✓ Bash found: $bashPath" -ForegroundColor Green
    
    # Check bash version
    $bashVersion = & $bashPath --version 2>&1 | Select-Object -First 1
    Write-Host "    Version: $bashVersion" -ForegroundColor Gray
} else {
    Write-Host "  ✗ Bash not found" -ForegroundColor Red
    Write-Host "    Install Git for Windows: https://git-scm.com/download/win" -ForegroundColor Yellow
    $allGood = $false
}

# 2. Check for Android SDK
Write-Host ""
Write-Host "[2/5] Checking for Android SDK..."
$sdkRoot = $env:ANDROID_HOME
if (-not $sdkRoot) {
    $sdkRoot = $env:ANDROID_SDK_ROOT
}

if ($sdkRoot -and (Test-Path $sdkRoot)) {
    Write-Host "  ✓ Android SDK found: $sdkRoot" -ForegroundColor Green
} else {
    Write-Host "  ✗ Android SDK not found" -ForegroundColor Red
    Write-Host "    Set ANDROID_HOME environment variable" -ForegroundColor Yellow
    Write-Host "    Example: `$env:ANDROID_HOME = 'C:\Android\Sdk'" -ForegroundColor Yellow
    $allGood = $false
}

# 3. Check for Android NDK
Write-Host ""
Write-Host "[3/5] Checking for Android NDK..."
$ndkPath = $env:ANDROID_NDK_HOME
if (-not $ndkPath) {
    $ndkPath = $env:NDK_HOME
}

# Try to find in SDK
if (-not $ndkPath -and $sdkRoot) {
    $ndkInSdk = Join-Path $sdkRoot "ndk\25.2.9519653"
    if (Test-Path $ndkInSdk) {
        $ndkPath = $ndkInSdk
    }
}

if ($ndkPath -and (Test-Path $ndkPath)) {
    Write-Host "  ✓ Android NDK found: $ndkPath" -ForegroundColor Green
    
    # Check NDK version
    $sourceProps = Join-Path $ndkPath "source.properties"
    if (Test-Path $sourceProps) {
        $version = Get-Content $sourceProps | Where-Object { $_ -match "Pkg.Revision" } | ForEach-Object { ($_ -split "=")[1].Trim() }
        Write-Host "    Version: $version" -ForegroundColor Gray
    }
} else {
    Write-Host "  ✗ Android NDK not found" -ForegroundColor Red
    Write-Host "    Install NDK r25c from Android Studio SDK Manager" -ForegroundColor Yellow
    Write-Host "    Or set ANDROID_NDK_HOME environment variable" -ForegroundColor Yellow
    $allGood = $false
}

# 4. Check disk space
Write-Host ""
Write-Host "[4/5] Checking disk space..."
$drive = (Get-Location).Drive
$freeSpace = $drive.Free / 1GB

if ($freeSpace -ge 5) {
    Write-Host "  ✓ Disk space: $([math]::Round($freeSpace, 2)) GB free" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Disk space: $([math]::Round($freeSpace, 2)) GB free (minimum 5GB recommended)" -ForegroundColor Yellow
}

# 5. Check write permissions
Write-Host ""
Write-Host "[5/5] Checking write permissions..."
$testDir = Join-Path $env:TEMP "build-test-$(Get-Random)"
try {
    New-Item -ItemType Directory -Path $testDir -Force | Out-Null
    $testFile = Join-Path $testDir "test.txt"
    "test" | Out-File -FilePath $testFile -Force
    Remove-Item -Recurse -Force $testDir
    Write-Host "  ✓ Write permissions OK" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Write permission test failed" -ForegroundColor Red
    Write-Host "    Try running PowerShell as Administrator" -ForegroundColor Yellow
    $allGood = $false
}

# Summary
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if ($allGood) {
    Write-Host "✓ All requirements met! Ready to build." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  .\scripts\powershell\build-complete.ps1"
} else {
    Write-Host "✗ Some requirements are missing" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please install missing components and run this script again."
    exit 1
}
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
