#Requires -Modules Az.Accounts, Az.Resources, Az.Network, Az.Compute, Az.Storage

<#
.SYNOPSIS
    Validates that the DNS POC deployment was successful
.DESCRIPTION
    Performs comprehensive checks on deployed resources to ensure everything is configured correctly.
    Catches common deployment issues before manual testing begins.
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

# Counters for results
$checksTotal = 0
$checksPass = 0
$checksFail = 0

function Write-Header {
    param([string]$Message)
    Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║ $($Message.PadRight(65)) ║" -ForegroundColor Cyan
    Write-Host '╚═══════════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
}

function Write-CheckStart {
    param([string]$Message)
    Write-Host "`n  ⏳ $Message..." -ForegroundColor Gray -NoNewline
}

function Write-CheckPass {
    Write-Host ' ✓' -ForegroundColor Green
    $script:checksPass++
}

function Write-CheckFail {
    param([string]$Details = '')
    Write-Host ' ✗' -ForegroundColor Red
    if ($Details) {
        Write-Host "      └─ $Details" -ForegroundColor Red
    }
    $script:checksFail++
}

function Write-Section {
    param([string]$Message)
    Write-Host "`n[▶] $Message" -ForegroundColor Yellow
}

function Invoke-Check {
    param(
        [string]$Name,
        [scriptblock]$ScriptBlock
    )
    
    $script:checksTotal++
    Write-CheckStart $Name
    
    try {
        $result = & $ScriptBlock
        if ($result) {
            Write-CheckPass
            return $true
        }
        else {
            Write-CheckFail
            return $false
        }
    }
    catch {
        Write-CheckFail $_.Exception.Message
        return $false
    }
}

try {
    Write-Header 'DNS POC - Deployment Validation'
    
    # Load configuration
    Write-Section 'Configuration Validation'
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath"
    }
    $config = Get-Content $ConfigPath | ConvertFrom-Json
    Write-CheckStart 'Configuration file exists'
    Write-CheckPass
    $script:checksTotal++
    
    # Check Azure context
    Write-Section 'Azure Connection'
    $context = Get-AzContext
    if (-not $context) {
        throw 'Not logged in to Azure. Please run Connect-AzAccount first.'
    }
    
    Write-CheckStart 'Azure subscription connected'
    Write-CheckPass
    $script:checksTotal++
    Write-Host "      └─ Subscription: $($context.Subscription.Name)" -ForegroundColor Gray
    
    # Validate output files exist
    Write-Section 'Deployment Outputs'
    $hubOutputsPath = "$PSScriptRoot/../.outputs/hub-outputs.json"
    $spokeOutputsPath = "$PSScriptRoot/../.outputs/spoke-outputs.json"
    $onpremOutputsPath = "$PSScriptRoot/../.outputs/onprem-outputs.json"
    
    Invoke-Check 'Hub outputs file exists' {
        Test-Path $hubOutputsPath
    } | Out-Null
    
    Invoke-Check 'Spoke outputs file exists' {
        Test-Path $spokeOutputsPath
    } | Out-Null
    
    Invoke-Check 'On-Prem outputs file exists' {
        Test-Path $onpremOutputsPath
    } | Out-Null
    
    if (-not ((Test-Path $hubOutputsPath) -and (Test-Path $spokeOutputsPath) -and (Test-Path $onpremOutputsPath))) {
        Write-Host "`n⚠️  Output files missing. Run deploy-all.ps1 first." -ForegroundColor Yellow
        exit 1
    }
    
    $hubOutputs = Get-Content $hubOutputsPath | ConvertFrom-Json
    $spokeOutputs = Get-Content $spokeOutputsPath | ConvertFrom-Json
    $onpremOutputs = Get-Content $onpremOutputsPath | ConvertFrom-Json
    
    # Validate resource groups
    Write-Section 'Resource Groups'
    
    Invoke-Check 'Hub resource group exists' {
        $rg = Get-AzResourceGroup -Name $config.resourceGroups.hub -ErrorAction SilentlyContinue
        $rg -ne $null
    } | Out-Null
    
    Invoke-Check 'Spoke resource group exists' {
        $rg = Get-AzResourceGroup -Name $config.resourceGroups.spoke -ErrorAction SilentlyContinue
        $rg -ne $null
    } | Out-Null
    
    Invoke-Check 'On-Prem resource group exists' {
        $rg = Get-AzResourceGroup -Name $config.resourceGroups.onprem -ErrorAction SilentlyContinue
        $rg -ne $null
    } | Out-Null
    
    # Validate Hub resources
    Write-Section 'Hub Network Resources'
    
    Invoke-Check 'Hub VNet exists' {
        $vnet = Get-AzVirtualNetwork -Name $hubOutputs.hubVnetName.value `
            -ResourceGroupName $config.resourceGroups.hub -ErrorAction SilentlyContinue
        $vnet -ne $null
    } | Out-Null
    
    Invoke-Check 'Hub has inbound resolver endpoint' {
        $resources = Get-AzResource -ResourceGroupName $config.resourceGroups.hub `
            -ResourceType 'Microsoft.Network/dnsResolvers/inboundEndpoints' -ErrorAction SilentlyContinue
        $resources.Count -gt 0
    } | Out-Null
    
    Invoke-Check 'Hub has outbound resolver endpoint' {
        $resources = Get-AzResource -ResourceGroupName $config.resourceGroups.hub `
            -ResourceType 'Microsoft.Network/dnsResolvers/outboundEndpoints' -ErrorAction SilentlyContinue
        $resources.Count -gt 0
    } | Out-Null
    
    # Validate Private DNS Zones
    Write-Section 'Private DNS Zones'
    
    Invoke-Check 'Blob private DNS zone exists' {
        $zone = Get-AzPrivateDnsZone -ResourceGroupName $config.resourceGroups.hub `
            -Name 'privatelink.blob.core.windows.net' -ErrorAction SilentlyContinue
        $zone -ne $null
    } | Out-Null
    
    Invoke-Check 'VM private DNS zone exists' {
        $zone = Get-AzPrivateDnsZone -ResourceGroupName $config.resourceGroups.hub `
            -Name 'example.pvt' -ErrorAction SilentlyContinue
        $zone -ne $null
    } | Out-Null
    
    # Validate Spoke resources
    Write-Section 'Spoke Network Resources'
    
    Invoke-Check 'Spoke VNet exists' {
        $vnet = Get-AzVirtualNetwork -Name $spokeOutputs.spokeVnetName.value `
            -ResourceGroupName $config.resourceGroups.spoke -ErrorAction SilentlyContinue
        $vnet -ne $null
    } | Out-Null
    
    Invoke-Check 'Spoke VM exists' {
        $vm = Get-AzVM -ResourceGroupName $config.resourceGroups.spoke `
            -Name 'dnspoc-vm-spoke-dev' -ErrorAction SilentlyContinue
        $vm -ne $null
    } | Out-Null
    
    Invoke-Check 'Spoke VM is running' {
        $vm = Get-AzVM -ResourceGroupName $config.resourceGroups.spoke `
            -Name 'dnspoc-vm-spoke-dev' -Status -ErrorAction SilentlyContinue
        $vm.InstanceView.Statuses | Where-Object { $_.Code -eq 'PowerState/running' }
    } | Out-Null
    
    Invoke-Check 'Storage account exists' {
        $sa = Get-AzStorageAccount -ResourceGroupName $config.resourceGroups.spoke `
            -Name $spokeOutputs.storageAccountName.value -ErrorAction SilentlyContinue
        $sa -ne $null
    } | Out-Null
    
    # Validate On-Prem resources
    Write-Section 'On-Premises Simulation Resources'
    
    Invoke-Check 'On-Prem VNet exists' {
        $vnet = Get-AzVirtualNetwork -Name $onpremOutputs.onpremVnetName.value `
            -ResourceGroupName $config.resourceGroups.onprem -ErrorAction SilentlyContinue
        $vnet -ne $null
    } | Out-Null
    
    Invoke-Check 'On-Prem DNS VM exists' {
        $vm = Get-AzVM -ResourceGroupName $config.resourceGroups.onprem `
            -Name 'dnspoc-vm-onprem-dns' -ErrorAction SilentlyContinue
        $vm -ne $null
    } | Out-Null
    
    Invoke-Check 'On-Prem DNS VM is running' {
        $vm = Get-AzVM -ResourceGroupName $config.resourceGroups.onprem `
            -Name 'dnspoc-vm-onprem-dns' -Status -ErrorAction SilentlyContinue
        $vm.InstanceView.Statuses | Where-Object { $_.Code -eq 'PowerState/running' }
    } | Out-Null
    
    Invoke-Check 'On-Prem client VM exists' {
        $vm = Get-AzVM -ResourceGroupName $config.resourceGroups.onprem `
            -Name 'dnspoc-vm-onprem-client' -ErrorAction SilentlyContinue
        $vm -ne $null
    } | Out-Null
    
    Invoke-Check 'On-Prem client VM is running' {
        $vm = Get-AzVM -ResourceGroupName $config.resourceGroups.onprem `
            -Name 'dnspoc-vm-onprem-client' -Status -ErrorAction SilentlyContinue
        $vm.InstanceView.Statuses | Where-Object { $_.Code -eq 'PowerState/running' }
    } | Out-Null
    
    # Validate VNet Peering
    Write-Section 'VNet Peering'
    
    Invoke-Check 'Hub-to-Spoke peering exists' {
        $peering = Get-AzVirtualNetworkPeering -VirtualNetworkName $hubOutputs.hubVnetName.value `
            -ResourceGroupName $config.resourceGroups.hub `
            -Name '*spoke*' -ErrorAction SilentlyContinue
        $peering -ne $null
    } | Out-Null
    
    Invoke-Check 'Hub-to-OnPrem peering exists' {
        $peering = Get-AzVirtualNetworkPeering -VirtualNetworkName $hubOutputs.hubVnetName.value `
            -ResourceGroupName $config.resourceGroups.hub `
            -Name '*onprem*' -ErrorAction SilentlyContinue
        $peering -ne $null
    } | Out-Null
    
    # Summary
    Write-Header 'Validation Summary'
    Write-Host "`n  Total Checks: $checksTotal" -ForegroundColor Cyan
    Write-Host "  ✓ Passed: $checksPass" -ForegroundColor Green
    if ($checksFail -gt 0) {
        Write-Host "  ✗ Failed: $checksFail" -ForegroundColor Red
    }
    else {
        Write-Host "  ✗ Failed: $checksFail" -ForegroundColor Green
    }
    
    Write-Host "`n" -ForegroundColor White
    
    if ($checksFail -eq 0) {
        Write-Host '✓ All validation checks passed!' -ForegroundColor Green -BackgroundColor DarkGreen
        Write-Host "`nDeployment is ready for testing. Next steps:" -ForegroundColor Cyan
        Write-Host '  1. Run: ./scripts/test-dns.ps1' -ForegroundColor White
        Write-Host '  2. Add public IPs: ./scripts/add-public-ip.ps1' -ForegroundColor White
        Write-Host '  3. SSH into VMs and perform manual DNS tests' -ForegroundColor White
        exit 0
    }
    else {
        Write-Host "✗ Validation failed with $checksFail error(s)" -ForegroundColor Red -BackgroundColor DarkRed
        Write-Host "`nPlease review the failures above and run deploy-all.ps1 again." -ForegroundColor Yellow
        exit 1
    }
    
}
catch {
    Write-Host "`n✗ Validation error: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
