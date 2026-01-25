#Requires -Version 5.1

<#
.SYNOPSIS
    Platform-aware SSH key generation script
.DESCRIPTION
    Generates SSH key pair with correct paths for Windows, macOS, or Linux
.PARAMETER KeyName
    Name of the SSH key pair (default: dnspoc)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$KeyName = 'dnspoc'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "    ✓ $Message" -ForegroundColor Green
}

try {
    # Determine SSH directory based on OS
    Write-Step 'Detecting operating system'
    
    if ($IsWindows -or ($PSVersionTable.PSVersion.Major -lt 6)) {
        $sshDir = Join-Path $env:USERPROFILE '.ssh'
        $osType = 'Windows'
    }
    elseif ($IsMacOS) {
        $sshDir = Join-Path $HOME '.ssh'
        $osType = 'macOS'
    }
    elseif ($IsLinux) {
        $sshDir = Join-Path $HOME '.ssh'
        $osType = 'Linux'
    }
    else {
        throw 'Unable to determine operating system'
    }
    
    Write-Success "OS detected: $osType"
    
    # Create .ssh directory if it doesn't exist
    Write-Step 'Setting up SSH directory'
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
        Write-Success "Created: $sshDir"
    }
    else {
        Write-Success "SSH directory exists: $sshDir"
    }
    
    # Check if key already exists
    $keyPath = Join-Path $sshDir $KeyName
    $pubKeyPath = "$keyPath.pub"
    
    if (Test-Path $keyPath) {
        Write-Host "`n⚠️  SSH key already exists: $keyPath" -ForegroundColor Yellow
        $response = Read-Host 'Overwrite? (y/n)'
        if ($response -ne 'y') {
            Write-Host 'Cancelled. Using existing key.' -ForegroundColor Yellow
            exit 0
        }
    }
    
    # Generate SSH key
    Write-Step 'Generating SSH key pair'
    ssh-keygen -t rsa -b 4096 -f $keyPath -N '' -C "dnspoc-$(hostname)"
    
    if (-not $?) {
        throw 'SSH key generation failed'
    }
    
    Write-Success 'SSH key pair generated'
    
    # Display public key
    Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host '║                     SSH KEY GENERATED!                             ║' -ForegroundColor Green
    Write-Host '╚═══════════════════════════════════════════════════════════════════╝' -ForegroundColor Green
    
    Write-Host "`nPrivate Key: $keyPath" -ForegroundColor Cyan
    Write-Host "Public Key:  $pubKeyPath" -ForegroundColor Cyan
    
    Write-Host "`nPublic Key Content:" -ForegroundColor Yellow
    Write-Host '───────────────────────────────────────────────────────────────────' -ForegroundColor Gray
    Get-Content $pubKeyPath | Write-Host -ForegroundColor White
    Write-Host '───────────────────────────────────────────────────────────────────' -ForegroundColor Gray
    
    # Copy to clipboard if available
    try {
        $pubKeyContent = Get-Content $pubKeyPath
        Set-Clipboard -Value $pubKeyContent
        Write-Success 'Public key copied to clipboard!'
    }
    catch {
        Write-Host "`nNote: Could not copy to clipboard. Copy the key above manually." -ForegroundColor Yellow
    }
    
    Write-Host "`nNext step: Paste the public key into config/config.json" -ForegroundColor Cyan
    
}
catch {
    Write-Host "`n✗ Error: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
