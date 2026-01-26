#Requires -Modules Az.Accounts, Az.Resources, Az.Storage

<#
.SYNOPSIS
    Deploys the spoke network infrastructure for the DNS POC
.DESCRIPTION
    Deploys spoke VNet, developer VM, storage account with private endpoint.
    Automatically generates a unique storage account name if needed.
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

function Test-StorageAccountNameAvailable {
    param([string]$Name)
    
    try {
        $result = Get-AzStorageAccountNameAvailability -Name $Name
        return $result.NameAvailable
    }
    catch {
        Write-Warning "Could not verify name availability: $_"
        return $false
    }
}

function New-UniqueStorageAccountName {
    param(
        [string]$Prefix = 'dnspocsa',
        [string]$Suffix = 'spoke'
    )
    
    # Storage account naming rules: 3-24 characters, lowercase letters and numbers only, globally unique
    $maxAttempts = 10
    $attempt = 0
    
    Write-Step 'Generating unique storage account name'
    
    while ($attempt -lt $maxAttempts) {
        $random = Get-Random -Minimum 1000 -Maximum 9999
        $name = "$Prefix$Suffix$random".ToLower()
        
        # Validate length
        if ($name.Length -gt 24 -or $name.Length -lt 3) {
            Write-Warning "Generated name '$name' is invalid length (must be 3-24 characters)."
            return $null
        }
        
        # Validate characters
        if ($name -notmatch '^[a-z0-9]+$') {
            Write-Warning "Generated name '$name' contains invalid characters."
            return $null
        }
        
        Write-Host "  Checking: $name..." -ForegroundColor Gray -NoNewline
        
        if (Test-StorageAccountNameAvailable -Name $name) {
            Write-Host ' ✓ Available!' -ForegroundColor Green
            return $name
        }
        else {
            Write-Host ' (unavailable)' -ForegroundColor Yellow
        }
        
        $attempt++
    }
    
    Write-ErrorMessage "Could not find available storage account name after $maxAttempts attempts."
    return $null
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
    # Use location from config.json if not provided via parameter
    if ([string]::IsNullOrWhiteSpace($Location)) {
        $Location = $config.location
        Write-Step "Using location from config.json: $Location"
    }
    else {
        Write-Step "Using specified location: $Location"
    }
    # Validate or generate storage account name
    $storageAccountName = $config.storageAccountName
    $isPlaceholder = ($storageAccountName -eq 'YOUR_STORAGE_ACCOUNT_NAME_HERE' -or 
        $storageAccountName -eq 'dnspocsaspoke1234' -or 
        [string]::IsNullOrWhiteSpace($storageAccountName))
    
    if ($isPlaceholder) {
        $storageAccountName = New-UniqueStorageAccountName
        if (-not $storageAccountName) {
            throw 'Failed to generate unique storage account name. Please verify Azure connectivity.'
        }
        Write-Success "Generated storage account name: $storageAccountName"
        $config.storageAccountName = $storageAccountName
    }
    else {
        Write-Step 'Validating storage account name availability'
        Write-Host "  Checking: $storageAccountName..." -ForegroundColor Gray -NoNewline
        if (Test-StorageAccountNameAvailable -Name $storageAccountName) {
            Write-Host ' ✓ Available' -ForegroundColor Green
        }
        else {
            throw "Storage account name '$storageAccountName' is not available. Update config.json with a unique name or remove it to auto-generate."
        }
    }

    # Load hub outputs
    Write-Step 'Loading hub deployment outputs'
    if (-not (Test-Path $HubOutputsPath)) {
        throw "Hub outputs file not found: $HubOutputsPath. Please run deploy-hub.ps1 first."
    }
    $hubOutputs = Get-Content $HubOutputsPath | ConvertFrom-Json
    Write-Success 'Hub outputs loaded'

    # Create resource group
    Write-Step 'Creating spoke resource group'
    $spokeRgName = $config.resourceGroups.spoke
    New-AzResourceGroup -Name $spokeRgName -Location $Location -Force | Out-Null
    Write-Success "Resource group created: $spokeRgName"

    # Deploy spoke infrastructure
    Write-Step 'Deploying spoke infrastructure (VNet, VM, Storage Account with Private Endpoint)'
    $spokeDeployment = New-AzResourceGroupDeployment `
        -Name "spoke-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
        -ResourceGroupName $spokeRgName `
        -TemplateFile "$PSScriptRoot/../bicep/spoke.bicep" `
        -location $Location `
        -envPrefix $config.envPrefix `
        -spokeVnetAddressPrefix $config.networking.spoke.addressPrefix `
        -hubVnetId $hubOutputs.hubVnetId.value `
        -hubVnetName $hubOutputs.hubVnetName.value `
        -hubResourceGroupName $config.resourceGroups.hub `
        -hubResolverInboundIP $hubOutputs.resolverInboundIP.value `
        -blobPrivateDnsZoneId $hubOutputs.blobPrivateDnsZoneId.value `
        -blobPrivateDnsZoneName $hubOutputs.blobPrivateDnsZoneName.value `
        -vmPrivateDnsZoneId $hubOutputs.vmPrivateDnsZoneId.value `
        -vmPrivateDnsZoneName $hubOutputs.vmPrivateDnsZoneName.value `
        -sshPublicKey $config.sshPublicKey `
        -adminUsername $config.adminUsername `
        -storageAccountName $storageAccountName `
        -Verbose

    if ($spokeDeployment.ProvisioningState -ne 'Succeeded') {
        throw "Spoke deployment failed with state: $($spokeDeployment.ProvisioningState)"
    }

    Write-Success 'Spoke infrastructure deployed successfully'
    Write-Host "`nSpoke Outputs:" -ForegroundColor Yellow
    $spokeDeployment.Outputs.GetEnumerator() | ForEach-Object {
        Write-Host "  $($_.Key): $($_.Value.Value)" -ForegroundColor Gray
    }

    # Save outputs to file
    $outputsDir = "$PSScriptRoot/../.outputs"
    if (-not (Test-Path $outputsDir)) {
        New-Item -ItemType Directory -Path $outputsDir -Force | Out-Null
    }
    $outputsPath = Join-Path $outputsDir 'spoke-outputs.json'
    $spokeDeployment.Outputs | ConvertTo-Json -Depth 10 | Out-File $outputsPath
    Write-Success "Spoke outputs saved to: $outputsPath"

    Write-Host "`n✓ Spoke deployment completed successfully!" -ForegroundColor Green
    exit 0

}
catch {
    Write-ErrorMessage "Deployment failed: $_"
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
