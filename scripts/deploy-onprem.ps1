#Requires -Modules Az.Accounts, Az.Resources

<#
.SYNOPSIS
    Deploys the on-premises simulation infrastructure for the DNS POC
.DESCRIPTION
    Deploys on-prem VNet, DNS server VM, and client VM
.PARAMETER ConfigPath
    Path to the configuration JSON file
.PARAMETER HubOutputsPath
    Path to the hub deployment outputs JSON file
.PARAMETER Location
    Azure region for deployment
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "$PSScriptRoot/../config/config.json",
    
    [Parameter(Mandatory = $false)]
    [string]$HubOutputsPath = "$PSScriptRoot/../.outputs/hub-outputs.json",
    
    [Parameter(Mandatory = $false)]
    [string]$Location = ''
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

function Write-ErrorMessage {
    param([string]$Message)
    Write-Host "    ✗ $Message" -ForegroundColor Red
}

try {
    # Load configuration
    Write-Step 'Loading configuration'
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath"
    }
    $config = Get-Content $ConfigPath | ConvertFrom-Json
    Write-Success 'Configuration loaded'
    
    # Use location from config.json if not provided via parameter
    if ([string]::IsNullOrWhiteSpace($Location)) {
        $Location = $config.location
        Write-Step "Using location from config.json: $Location"
    }
    else {
        Write-Step "Using specified location: $Location"
    }

    # Load hub outputs
    Write-Step 'Loading hub deployment outputs'
    if (-not (Test-Path $HubOutputsPath)) {
        throw "Hub outputs file not found: $HubOutputsPath. Please run deploy-hub.ps1 first."
    }
    $hubOutputs = Get-Content $HubOutputsPath | ConvertFrom-Json
    Write-Success 'Hub outputs loaded'

    # Ensure we're logged in to Azure
    Write-Step 'Checking Azure connection'
    $context = Get-AzContext
    if (-not $context) {
        throw 'Not logged in to Azure. Please run Connect-AzAccount first.'
    }
    Write-Success "Connected to Azure subscription: $($context.Subscription.Name)"

    # Create resource group
    Write-Step 'Creating on-prem resource group'
    $onpremRgName = $config.resourceGroups.onprem
    New-AzResourceGroup -Name $onpremRgName -Location $Location -Force | Out-Null
    Write-Success "Resource group created: $onpremRgName"

    # Deploy on-prem infrastructure
    Write-Step 'Deploying on-prem infrastructure (VNet, DNS server, Client VM)'
    $onpremDeployment = New-AzResourceGroupDeployment `
        -Name "onprem-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
        -ResourceGroupName $onpremRgName `
        -TemplateFile "$PSScriptRoot/../bicep/onprem.bicep" `
        -location $Location `
        -envPrefix $config.envPrefix `
        -onpremVnetAddressPrefix $config.networking.onprem.addressPrefix `
        -hubVnetId $hubOutputs.hubVnetId.value `
        -hubVnetName $hubOutputs.hubVnetName.value `
        -hubResourceGroupName $config.resourceGroups.hub `
        -vmPrivateDnsZoneId $hubOutputs.vmPrivateDnsZoneId.value `
        -vmPrivateDnsZoneName $hubOutputs.vmPrivateDnsZoneName.value `
        -sshPublicKey $config.sshPublicKey `
        -adminUsername $config.adminUsername `
        -dnsServerIP $config.networking.onprem.dnsServerIP `
        -Verbose

    if ($onpremDeployment.ProvisioningState -ne 'Succeeded') {
        throw "On-prem deployment failed with state: $($onpremDeployment.ProvisioningState)"
    }

    Write-Success 'On-prem infrastructure deployed successfully'
    Write-Host "`nOn-Prem Outputs:" -ForegroundColor Yellow
    $onpremDeployment.Outputs.GetEnumerator() | ForEach-Object {
        Write-Host "  $($_.Key): $($_.Value.Value)" -ForegroundColor Gray
    }

    # Save outputs to file
    $outputsDir = "$PSScriptRoot/../.outputs"
    if (-not (Test-Path $outputsDir)) {
        New-Item -ItemType Directory -Path $outputsDir -Force | Out-Null
    }
    $outputsPath = Join-Path $outputsDir 'onprem-outputs.json'
    $onpremDeployment.Outputs | ConvertTo-Json -Depth 10 | Out-File $outputsPath
    Write-Success "On-prem outputs saved to: $outputsPath"

    Write-Host "`n✓ On-prem deployment completed successfully!" -ForegroundColor Green
    exit 0

}
catch {
    Write-ErrorMessage "Deployment failed: $_"
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
