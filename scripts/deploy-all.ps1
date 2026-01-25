#Requires -Modules Az.Accounts, Az.Resources

<#
.SYNOPSIS
    Complete deployment orchestrator for the DNS POC environment
.DESCRIPTION
    Orchestrates the complete deployment of hub, spoke, and on-prem infrastructure
.PARAMETER ConfigPath
    Path to the configuration JSON file
.PARAMETER Location
    Azure region for deployment
.PARAMETER SkipHub
    Skip hub deployment (if already deployed)
.PARAMETER SkipSpoke
    Skip spoke deployment
.PARAMETER SkipOnprem
    Skip on-prem deployment
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "$PSScriptRoot/../config/config.json",
    
    [Parameter(Mandatory = $false)]
    [string]$Location = '',
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipHub,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipSpoke,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipOnprem
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Header {
    param([string]$Message)
    Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║ $($Message.PadRight(65)) ║" -ForegroundColor Cyan
    Write-Host '╚═══════════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "    ✓ $Message" -ForegroundColor Green
}

function Write-ErrorMessage {
    param([string]$Message)
    Write-Host "    ✗ $Message" -ForegroundColor Red
}

function Get-SSHKeyPath {
    <#
    .SYNOPSIS
        Gets the expected SSH key path for the current OS
    #>
    param([string]$KeyName = 'dnspoc')
    
    if ($IsWindows -or ($PSVersionTable.PSVersion.Major -lt 6)) {
        return Join-Path $env:USERPROFILE ".ssh\$KeyName"
    }
    else {
        return Join-Path $HOME ".ssh/$KeyName"
    }
}

function Test-SSHKeyExists {
    <#
    .SYNOPSIS
        Tests if SSH key pair exists for the current OS
    #>
    param([string]$KeyName = 'dnspoc')
    
    $keyPath = Get-SSHKeyPath -KeyName $KeyName
    return (Test-Path $keyPath) -and (Test-Path "$keyPath.pub")
}

function Invoke-SSHKeyGeneration {
    <#
    .SYNOPSIS
        Invokes the SSH key generation script
    #>
    param([string]$KeyName = 'dnspoc')
    
    $scriptPath = Join-Path $PSScriptRoot 'New-SSHKeyPair.ps1'
    if (-not (Test-Path $scriptPath)) {
        throw "SSH key generation script not found: $scriptPath"
    }
    
    & $scriptPath -KeyName $KeyName
    return $LASTEXITCODE -eq 0
}

try {
    Write-Header 'DNS POC - Complete Deployment'
    
    $startTime = Get-Date
    
    # Validate configuration file exists
    Write-Step 'Validating configuration'
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath"
    }
    Write-Success 'Configuration file found'
    
    # Validate SSH key exists (or offer to generate it)
    Write-Step 'Checking SSH key pair'
    $keyName = 'dnspoc'
    $keyPath = Get-SSHKeyPath -KeyName $keyName
    
    if (-not (Test-SSHKeyExists -KeyName $keyName)) {
        Write-Host "`n⚠️  SSH key not found: $keyPath" -ForegroundColor Yellow
        Write-Host 'The deployment will need an SSH public key in config/config.json' -ForegroundColor Gray
        
        $response = Read-Host "`nGenerate SSH key pair now? (y/n)"
        if ($response -eq 'y') {
            Write-Host ''
            if (Invoke-SSHKeyGeneration -KeyName $keyName) {
                Write-Host "`n✓ SSH key generated successfully" -ForegroundColor Green
                Write-Host 'Please copy the public key from above and paste it into config/config.json' -ForegroundColor Yellow
                $continueResponse = Read-Host 'Continue with deployment? (y/n)'
                if ($continueResponse -ne 'y') {
                    Write-Host 'Deployment cancelled.' -ForegroundColor Yellow
                    exit 0
                }
            }
            else {
                throw 'SSH key generation failed'
            }
        }
        else {
            throw "SSH key is required for deployment. Run './scripts/New-SSHKeyPair.ps1' to generate one."
        }
    }
    else {
        Write-Success "SSH key pair exists: $keyPath"
    }
    
    # Load config to check SSH public key
    Write-Step 'Validating SSH public key in configuration'
    $config = Get-Content $ConfigPath | ConvertFrom-Json
    
    # Use location from config.json if not provided via parameter
    if ([string]::IsNullOrWhiteSpace($Location)) {
        $Location = $config.location
        Write-Success "Using location from config.json: $Location"
    }
    else {
        Write-Success "Using specified location: $Location"
    }
    
    if ([string]::IsNullOrWhiteSpace($config.sshPublicKey) -or $config.sshPublicKey -eq 'YOUR_SSH_PUBLIC_KEY_HERE') {
        Write-Host "`n⚠️  SSH public key not configured in config/config.json" -ForegroundColor Yellow
        Write-Host "Public key content from: $keyPath.pub" -ForegroundColor Gray
        
        try {
            $pubKeyContent = Get-Content "$keyPath.pub"
            Write-Host "`nPublic Key Content:" -ForegroundColor Yellow
            Write-Host '───────────────────────────────────────────────────────────────────' -ForegroundColor Gray
            Write-Host $pubKeyContent -ForegroundColor White
            Write-Host '───────────────────────────────────────────────────────────────────' -ForegroundColor Gray
            
            Write-Host "`nPlease add this to config/config.json:" -ForegroundColor Cyan
            Write-Host "  `"sshPublicKey`": `"$pubKeyContent`"," -ForegroundColor Gray
            
            $continueResponse = Read-Host "`nHave you updated config/config.json? (y/n)"
            if ($continueResponse -ne 'y') {
                throw 'Configuration incomplete. Please update config/config.json with the SSH public key.'
            }
            
            # Reload config after user update
            $config = Get-Content $ConfigPath | ConvertFrom-Json
            if ([string]::IsNullOrWhiteSpace($config.sshPublicKey) -or $config.sshPublicKey -eq 'YOUR_SSH_PUBLIC_KEY_HERE') {
                throw 'SSH public key still not configured in config/config.json'
            }
        }
        catch {
            if ($_.Exception.Message -like '*not found*') {
                throw "Could not read SSH public key from: $keyPath.pub"
            }
            throw $_
        }
    }
    else {
        Write-Success 'SSH public key configured'
    }
    
    # Ensure we're logged in to Azure
    Write-Step 'Checking Azure connection'
    $context = Get-AzContext
    if (-not $context) {
        throw 'Not logged in to Azure. Please run Connect-AzAccount first.'
    }
    Write-Success "Connected to subscription: $($context.Subscription.Name)"
    
    # Deploy Hub
    if (-not $SkipHub) {
        Write-Header 'Deploying Hub Infrastructure'
        & "$PSScriptRoot/deploy-hub.ps1" -ConfigPath $ConfigPath -Location $Location
        if ($LASTEXITCODE -ne 0) {
            throw 'Hub deployment failed'
        }
    }
    else {
        Write-Step 'Skipping hub deployment (already deployed)'
    }
    
    # Deploy Spoke
    if (-not $SkipSpoke) {
        Write-Header 'Deploying Spoke Infrastructure'
        & "$PSScriptRoot/deploy-spoke.ps1" -ConfigPath $ConfigPath -Location $Location
        if ($LASTEXITCODE -ne 0) {
            throw 'Spoke deployment failed'
        }
    }
    else {
        Write-Step 'Skipping spoke deployment'
    }
    
    # Deploy On-Prem
    if (-not $SkipOnprem) {
        Write-Header 'Deploying On-Premises Simulation'
        & "$PSScriptRoot/deploy-onprem.ps1" -ConfigPath $ConfigPath -Location $Location
        if ($LASTEXITCODE -ne 0) {
            throw 'On-prem deployment failed'
        }
    }
    else {
        Write-Step 'Skipping on-prem deployment'
    }
    
    # Configure DNS forwarding ruleset (if on-prem was deployed)
    if (-not $SkipOnprem) {
        Write-Header 'Configuring DNS Forwarding'
        & "$PSScriptRoot/configure-dns-forwarding.ps1" -ConfigPath $ConfigPath
        if ($LASTEXITCODE -ne 0) {
            Write-Warning 'DNS forwarding configuration encountered issues but continuing...'
        }
    }
    
    $endTime = Get-Date
    $duration = $endTime - $startTime
    
    Write-Header 'Deployment Complete!'
    Write-Host "`nTotal deployment time: $($duration.ToString('mm\:ss'))" -ForegroundColor Yellow
    Write-Host "`nNext steps:" -ForegroundColor Cyan
    Write-Host '  1. Run test-dns.ps1 to validate DNS resolution' -ForegroundColor White
    Write-Host '  2. SSH to VMs to perform manual testing' -ForegroundColor White
    Write-Host '  3. Run teardown.ps1 when finished to clean up resources' -ForegroundColor White
    
}
catch {
    Write-ErrorMessage "Deployment failed: $_"
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    Write-Host "`nTo retry, fix the issue and run deploy-all.ps1 again" -ForegroundColor Yellow
    exit 1
}
