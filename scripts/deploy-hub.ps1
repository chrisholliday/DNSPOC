#Requires -Modules Az.Accounts, Az.Resources

<#
.SYNOPSIS
    Deploys the hub network infrastructure for the DNS POC
.DESCRIPTION
    Deploys hub VNet, DNS Private Resolver, and Private DNS zones
.PARAMETER ConfigPath
    Path to the configuration JSON file
.PARAMETER Location
    Azure region for deployment
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "$PSScriptRoot/../config/config.json",
    
    [Parameter(Mandatory = $false)]
    [string]$Location = 'eastus'
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

    # Ensure we're logged in to Azure
    Write-Step 'Checking Azure connection'
    $context = Get-AzContext
    if (-not $context) {
        throw 'Not logged in to Azure. Please run Connect-AzAccount first.'
    }
    Write-Success "Connected to Azure subscription: $($context.Subscription.Name)"

    # Create resource group
    Write-Step 'Creating hub resource group'
    $hubRgName = $config.resourceGroups.hub
    New-AzResourceGroup -Name $hubRgName -Location $Location -Force | Out-Null
    Write-Success "Resource group created: $hubRgName"

    # Deploy hub infrastructure
    Write-Step 'Deploying hub infrastructure (VNet, DNS Resolver, Private DNS zones)'
    $hubDeployment = New-AzResourceGroupDeployment `
        -Name "hub-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
        -ResourceGroupName $hubRgName `
        -TemplateFile "$PSScriptRoot/../bicep/hub.bicep" `
        -location $Location `
        -envPrefix $config.envPrefix `
        -hubVnetAddressPrefix $config.networking.hub.addressPrefix `
        -Verbose

    if ($hubDeployment.ProvisioningState -ne 'Succeeded') {
        throw "Hub deployment failed with state: $($hubDeployment.ProvisioningState)"
    }

    Write-Success 'Hub infrastructure deployed successfully'
    Write-Host "`nHub Outputs:" -ForegroundColor Yellow
    $hubDeployment.Outputs.GetEnumerator() | ForEach-Object {
        Write-Host "  $($_.Key): $($_.Value.Value)" -ForegroundColor Gray
    }

    # Save outputs to file for use by other scripts
    $outputsPath = "$PSScriptRoot/../config/hub-outputs.json"
    $hubDeployment.Outputs | ConvertTo-Json -Depth 10 | Out-File $outputsPath
    Write-Success "Hub outputs saved to: $outputsPath"

    Write-Host "`n✓ Hub deployment completed successfully!" -ForegroundColor Green

}
catch {
    Write-ErrorMessage "Deployment failed: $_"
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
