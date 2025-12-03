param(
    [string]$ndk,
    [string]$abi = "arm64-v8a",
    [int]$api = 28,
    [string]$opensslDir,
    [string]$srcPath,
    [string]$outDir,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"

# Enable verbose output if requested
if ($Verbose) {
    $VerbosePreference = "Continue"
    Start-Transcript -Path "build-sqlcipher.log" -Append
}

# Validate required parameters
if (-not $ndk -or -not $srcPath -or -not $outDir) {
    Write-Error @"
Usage: -ndk <ndk-path> -srcPath <sqlcipher-source> -outDir <output-dir>

Example:
  .\build_sqlcipher_android.ps1 -ndk C:\Android\ndk\25.2.9519653 -srcPath C:\sources\sqlcipher -outDir C:\builds\sqlcipher

Optional parameters:
  -opensslDir <dir> OpenSSL installation directory (optional)
  -abi <abi>        Default: arm64-v8a
  -api <api-level>  Default: 28
  -Verbose          Enable detailed logging
"@
    exit 1
}

# Helper function to find bash
function Find-Bash {
    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if ($bash) {
        return $bash.Source
    }
    
    $gitBashPaths = @(
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files (x86)\Git\bin\bash.exe",
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe"
    )
    
    foreach ($path in $gitBashPaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    
    throw "Bash not found. Install Git for Windows: https://git-scm.com/download/win"
}

# Helper function to convert Windows path to Unix path
function Convert-WindowsPathToUnix {
    param(
        [string]$path,
        [string]$bashPath
    )
    
    if (-not [System.IO.Path]::IsPathRooted($path)) {
        $resolved = Resolve-Path $path -ErrorAction SilentlyContinue
        if ($resolved) {
            $path = $resolved
        } else {
            $path = Join-Path (Get-Location) $path
        }
    }
    
    $path = $path.ToString()
    $path = $path -replace '\\', '/'
    
    # Detect if using WSL or Git Bash
    $isWSL = $bashPath -like "*system32*" -or $bashPath -like "*wsl*" -or $bashPath -like "*\Windows\*bash.exe"
    
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
Write-Host "SQLCipher Build (PowerShell Orchestrator)"
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

# Get shell script path first
$shellScript = Join-Path $PSScriptRoot "build_sqlcipher_android.sh"
if (-not (Test-Path $shellScript)) {
    Write-Error "Shell script not found: $shellScript"
    exit 1
}

# Convert paths to Unix format
$ndkUnix = Convert-WindowsPathToUnix $ndk $bashPath
$srcPathUnix = Convert-WindowsPathToUnix $srcPath $bashPath
$outDirUnix = Convert-WindowsPathToUnix $outDir $bashPath
$shellScriptUnix = Convert-WindowsPathToUnix $shellScript $bashPath

# Build arguments array
$bashArgs = @($shellScriptUnix, "-ndk", $ndkUnix, "-abi", $abi, "-api", $api, "-srcPath", $srcPathUnix, "-outDir", $outDirUnix)

if ($opensslDir) {
    $opensslDirUnix = Convert-WindowsPathToUnix $opensslDir $bashPath
    $bashArgs += @("-opensslDir", $opensslDirUnix)
    
    if ($Verbose) {
        Write-Verbose "Path conversions:"
        Write-Verbose "  NDK:     $ndk → $ndkUnix"
        Write-Verbose "  OpenSSL: $opensslDir → $opensslDirUnix"
        Write-Verbose "  Source:  $srcPath → $srcPathUnix"
        Write-Verbose "  Output:  $outDir → $outDirUnix"
    }
} else {
    if ($Verbose) {
        Write-Verbose "Path conversions:"
        Write-Verbose "  NDK:    $ndk → $ndkUnix"
        Write-Verbose "  Source: $srcPath → $srcPathUnix"
        Write-Verbose "  Output: $outDir → $outDirUnix"
    }
}

Write-Host ""
Write-Host "Executing native shell script..."

# Detect if using WSL
$isWSL = $bashPath -like "*system32*" -or $bashPath -like "*wsl*" -or $bashPath -like "*\Windows\*bash.exe"

if ($Verbose) {
    $cmdLine = ($bashArgs | ForEach-Object { if ($_ -match '\s') { "'$_'" } else { $_ } }) -join ' '
    Write-Verbose "Command: bash $cmdLine"
}

# Execute bash script
# Set ANDROID_NDK_HOST_PLATFORM to force Windows toolchain when running from PowerShell
$env:ANDROID_NDK_HOST_PLATFORM = "windows-x86_64"

if ($isWSL) {
    # For WSL, construct command as string and execute via bash -c
    function Escape-SingleQuotes {
        param([string]$str)
        return $str -replace "'", "'\''"
    }
    
    $scriptEscaped = Escape-SingleQuotes $shellScriptUnix
    $ndkEscaped = Escape-SingleQuotes $ndkUnix
    $srcEscaped = Escape-SingleQuotes $srcPathUnix
    $outEscaped = Escape-SingleQuotes $outDirUnix
    
    if ($opensslDir) {
        $opensslEscaped = Escape-SingleQuotes $opensslDirUnix
        $wslCmd = "export ANDROID_NDK_HOST_PLATFORM=windows-x86_64 && bash '$scriptEscaped' -ndk '$ndkEscaped' -abi '$abi' -api $api -opensslDir '$opensslEscaped' -srcPath '$srcEscaped' -outDir '$outEscaped'"
    } else {
        $wslCmd = "export ANDROID_NDK_HOST_PLATFORM=windows-x86_64 && bash '$scriptEscaped' -ndk '$ndkEscaped' -abi '$abi' -api $api -srcPath '$srcEscaped' -outDir '$outEscaped'"
    }
    
    Write-Verbose "Executing via WSL: wsl bash -c `"$wslCmd`""
    & wsl bash -c $wslCmd
} else {
    # For Git Bash, set environment variable and use direct execution with array
    $env:ANDROID_NDK_HOST_PLATFORM = "windows-x86_64"
    & $bashPath @bashArgs
}

if ($LASTEXITCODE -ne 0) {
    Write-Error "SQLCipher build failed with exit code: $LASTEXITCODE"
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
