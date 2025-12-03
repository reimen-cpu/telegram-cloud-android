param(
    [string]$ndk,
    [string]$abi = "arm64-v8a",
    [int]$api = 28,
    [string]$srcPath,
    [string]$outDir,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"

# Enable verbose output if requested
if ($Verbose) {
    $VerbosePreference = "Continue"
    Start-Transcript -Path "build-openssl.log" -Append
}

# Validate required parameters
if (-not $ndk -or -not $srcPath -or -not $outDir) {
    Write-Error @"
Usage: -ndk <ndk-path> -srcPath <openssl-source> -outDir <output-dir>

Example:
  .\build_openssl_android.ps1 -ndk C:\Android\ndk\25.2.9519653 -srcPath C:\sources\openssl-3.2.0 -outDir C:\builds\openssl

Optional parameters:
  -abi <abi>        Default: arm64-v8a (options: arm64-v8a, armeabi-v7a, x86, x86_64)
  -api <api-level>  Default: 28
  -Verbose          Enable detailed logging
"@
    exit 1
}

# Helper function to find bash
function Find-Bash {
    # Check if bash is in PATH
    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if ($bash) {
        Write-Verbose "Found bash in PATH: $($bash.Source)"
        return $bash.Source
    }
    
    # Search common Git for Windows locations
    $gitBashPaths = @(
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files (x86)\Git\bin\bash.exe",
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe"
    )
    
    foreach ($path in $gitBashPaths) {
        if (Test-Path $path) {
            Write-Verbose "Found bash at: $path"
            return $path
        }
    }
    
    throw @"
Bash not found. Required to build OpenSSL on Windows.

RECOMMENDED: Install Git for Windows
  https://git-scm.com/download/win
  Includes bash, perl, and make needed for OpenSSL.

ALTERNATIVE: Use WSL
  wsl --install

After installation, restart PowerShell and run this script again.
"@
}

# Helper function to convert Windows path to Unix path
function Convert-WindowsPathToUnix {
    param(
        [string]$path,
        [string]$bashPath
    )
    
    # Resolve to absolute path if relative
    if (-not [System.IO.Path]::IsPathRooted($path)) {
        $resolved = Resolve-Path $path -ErrorAction SilentlyContinue
        if ($resolved) {
            $path = $resolved
        } else {
            # Path doesn't exist yet, make it absolute
            $path = Join-Path (Get-Location) $path
        }
    }
    
    # Convert to string if it's a PathInfo object
    $path = $path.ToString()
    
    # Convert backslashes to forward slashes
    $path = $path -replace '\\', '/'
    
    # Detect if using WSL or Git Bash
    $isWSL = $bashPath -like "*system32*" -or $bashPath -like "*wsl*" -or $bashPath -like "*\Windows\*bash.exe"
    
    # Convert drive letter based on bash type
    if ($path -match '^([A-Z]):') {
        $drive = $matches[1].ToLower()
        if ($isWSL) {
            # WSL format: C:\ → /mnt/c/
            $path = $path -replace '^[A-Z]:', "/mnt/$drive"
        } else {
            # Git bash format: C:\ → /c/
            $path = $path -replace '^[A-Z]:', "/$drive"
        }
    }
    
    return $path
}

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "OpenSSL Build (PowerShell Orchestrator)"
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Find bash
Write-Host "Detecting bash..."
try {
    $bashPath = Find-Bash
    Write-Host "✓ Bash found: $bashPath"
} catch {
    Write-Error $_
    exit 1
}

# Convert paths to Unix format
Write-Verbose "Converting Windows paths to Unix format..."
$ndkUnix = Convert-WindowsPathToUnix $ndk $bashPath
$srcPathUnix = Convert-WindowsPathToUnix $srcPath $bashPath
$outDirUnix = Convert-WindowsPathToUnix $outDir $bashPath

if ($Verbose) {
    Write-Verbose "Path conversions:"
    Write-Verbose "  NDK:     $ndk → $ndkUnix"
    Write-Verbose "  Source:  $srcPath → $srcPathUnix"
    Write-Verbose "  Output:  $outDir → $outDirUnix"
}

# Get shell script path
$shellScript = Join-Path $PSScriptRoot "build_openssl_android.sh"
if (-not (Test-Path $shellScript)) {
    Write-Error "Shell script not found: $shellScript"
    exit 1
}

$shellScriptUnix = Convert-WindowsPathToUnix $shellScript $bashPath

Write-Host ""
Write-Host "Executing native shell script..."

# Detect if using WSL
$isWSL = $bashPath -like "*system32*" -or $bashPath -like "*wsl*" -or $bashPath -like "*\Windows\*bash.exe"

# Build command arguments array properly
$bashArgs = @($shellScriptUnix, "-ndk", $ndkUnix, "-abi", $abi, "-api", "$api", "-srcPath", $srcPathUnix, "-outDir", $outDirUnix)

if ($Verbose) {
    $cmdLine = ($bashArgs | ForEach-Object { if ($_ -match '\s') { "'$_'" } else { $_ } }) -join ' '
    Write-Verbose "Command: bash $cmdLine"
}

# Execute bash script
# Set ANDROID_NDK_HOST_PLATFORM to force Windows toolchain when running from PowerShell
$env:ANDROID_NDK_HOST_PLATFORM = "windows-x86_64"

if ($isWSL) {
    # For WSL, construct command as string and execute via bash -c
    # Escape single quotes in paths by replacing ' with '\''
    function Escape-SingleQuotes {
        param([string]$str)
        return $str -replace "'", "'\''"
    }
    
    $scriptEscaped = Escape-SingleQuotes $shellScriptUnix
    $ndkEscaped = Escape-SingleQuotes $ndkUnix
    $srcEscaped = Escape-SingleQuotes $srcPathUnix
    $outEscaped = Escape-SingleQuotes $outDirUnix
    
    # Export environment variable in the bash command
    $wslCmd = "export ANDROID_NDK_HOST_PLATFORM=windows-x86_64 && bash '$scriptEscaped' -ndk '$ndkEscaped' -abi '$abi' -api $api -srcPath '$srcEscaped' -outDir '$outEscaped'"
    
    Write-Verbose "Executing via WSL: wsl bash -c `"$wslCmd`""
    & wsl bash -c $wslCmd
} else {
    # For Git Bash, set environment variable and use direct execution with array
    $env:ANDROID_NDK_HOST_PLATFORM = "windows-x86_64"
    & $bashPath @bashArgs
}

# Check exit code
if ($LASTEXITCODE -ne 0) {
    Write-Error "OpenSSL build failed with exit code: $LASTEXITCODE"
    if ($Verbose) {
        Stop-Transcript
    }
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "✓ PowerShell orchestrator completed successfully"
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if ($Verbose) {
    Stop-Transcript
}
