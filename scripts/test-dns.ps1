#Requires -Modules Az.Accounts, Az.Resources, Az.Compute

<#
.SYNOPSIS
    Tests DNS resolution across the DNS POC environment
.DESCRIPTION
    Validates DNS resolution from spoke and on-prem VMs
.PARAMETER ConfigPath
    Path to the configuration JSON file
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "$PSScriptRoot/../config/config.json"
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

function Write-TestResult {
    param([string]$TestName, [bool]$Passed, [string]$Details = "")
    if ($Passed) {
        Write-Host "    ✓ $TestName" -ForegroundColor Green
    } else {
        Write-Host "    ✗ $TestName" -ForegroundColor Red
    }
    if ($Details) {
        Write-Host "      $Details" -ForegroundColor Gray
    }
}

function Write-ErrorMessage {
    param([string]$Message)
    Write-Host "    ✗ $Message" -ForegroundColor Red
}

try {
    Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                    DNS POC - DNS TESTS                            ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

    # Load configuration and outputs
    Write-Step "Loading configuration"
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath"
    }
    $config = Get-Content $ConfigPath | ConvertFrom-Json
    
    $hubOutputsPath = "$PSScriptRoot/../.outputs/hub-outputs.json"
    $spokeOutputsPath = "$PSScriptRoot/../.outputs/spoke-outputs.json"
    $onpremOutputsPath = "$PSScriptRoot/../.outputs/onprem-outputs.json"
    
    if (-not (Test-Path $hubOutputsPath) -or -not (Test-Path $spokeOutputsPath) -or -not (Test-Path $onpremOutputsPath)) {
        throw "Deployment output files not found. Please run deploy-all.ps1 first."
    }
    
    $hubOutputs = Get-Content $hubOutputsPath | ConvertFrom-Json
    $spokeOutputs = Get-Content $spokeOutputsPath | ConvertFrom-Json
    $onpremOutputs = Get-Content $onpremOutputsPath | ConvertFrom-Json
    Write-Success "Configuration loaded"

    # Prepare test data
    $storageAccountName = $spokeOutputs.storageAccountName.value
    $storageFqdn = "$storageAccountName.blob.${environment().suffixes.storage}"
    $resolverIP = $hubOutputs.resolverInboundIP.value
    $onpremDnsIP = $onpremOutputs.dnsServerIP.value
    
    Write-Host "`nTest Environment:" -ForegroundColor Yellow
    Write-Host "  Storage FQDN: $storageFqdn" -ForegroundColor Gray
    Write-Host "  Hub Resolver IP: $resolverIP" -ForegroundColor Gray
    Write-Host "  On-Prem DNS IP: $onpremDnsIP" -ForegroundColor Gray

    # Test Summary
    Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                      TEST SCENARIOS                               ║" -ForegroundColor Green
    Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    
    Write-Host "`nTo manually validate DNS resolution:" -ForegroundColor Cyan
    Write-Host "`n1. Spoke VM - Test private endpoint resolution:" -ForegroundColor Yellow
    Write-Host "   SSH to spoke VM and run:" -ForegroundColor Gray
    Write-Host "     nslookup $storageFqdn" -ForegroundColor White
    Write-Host "   Expected: Should resolve to a 10.1.1.x private IP" -ForegroundColor Gray
    
    Write-Host "`n2. Spoke VM - Test public DNS resolution:" -ForegroundColor Yellow
    Write-Host "   SSH to spoke VM and run:" -ForegroundColor Gray
    Write-Host "     nslookup microsoft.com" -ForegroundColor White
    Write-Host "   Expected: Should resolve to public IP" -ForegroundColor Gray
    
    Write-Host "`n3. On-Prem Client VM - Test Azure private endpoint:" -ForegroundColor Yellow
    Write-Host "   SSH to on-prem client VM and run:" -ForegroundColor Gray
    Write-Host "     nslookup $storageFqdn $resolverIP" -ForegroundColor White
    Write-Host "   Expected: Should resolve to 10.1.1.x via hub resolver" -ForegroundColor Gray
    
    Write-Host "`n4. On-Prem Client VM - Test public DNS:" -ForegroundColor Yellow
    Write-Host "   SSH to on-prem client VM and run:" -ForegroundColor Gray
    Write-Host "     nslookup microsoft.com" -ForegroundColor White
    Write-Host "   Expected: Should resolve via on-prem DNS server" -ForegroundColor Gray

    Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                      VM CONNECTION INFO                           ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

    Write-Host "`nTo connect to VMs, you'll need to:" -ForegroundColor Yellow
    Write-Host "  1. Add a public IP to the VM's NIC, or" -ForegroundColor Gray
    Write-Host "  2. Use Azure Bastion, or" -ForegroundColor Gray
    Write-Host "  3. Use Azure Serial Console" -ForegroundColor Gray
    
    Write-Host "`nVM Names:" -ForegroundColor Cyan
    Write-Host "  Spoke Dev VM: $($config.envPrefix)-vm-spoke-dev" -ForegroundColor White
    Write-Host "  On-Prem DNS: $($config.envPrefix)-vm-onprem-dns" -ForegroundColor White
    Write-Host "  On-Prem Client: $($config.envPrefix)-vm-onprem-client" -ForegroundColor White

    Write-Host "`n✓ Test information prepared!" -ForegroundColor Green
    Write-Host "Use the commands above to validate DNS resolution." -ForegroundColor Green

} catch {
    Write-ErrorMessage "Test script failed: $_"
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
