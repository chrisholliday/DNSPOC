#Requires -Modules Az.Accounts, Az.Resources

<#
.SYNOPSIS
    Simplified deployment script for DNS POC - hardcoded for demonstration purposes
.DESCRIPTION
    Deploys hub, spoke, and on-prem infrastructure with hardcoded values
.PARAMETER SSHPublicKey
    SSH public key for VM access (required)
.PARAMETER Location
    Azure region (defaults to centralus)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "SSH public key for VM access. Example: 'ssh-rsa AAAA...'")]
    [string]$SSHPublicKey,
    
    [Parameter(Mandatory = $false)]
    [string]$Location = 'centralus'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Hardcoded configuration for POC
$config = @{
    EnvPrefix      = 'dnspoc'
    Location       = $Location
    AdminUsername  = 'azureuser'
    ResourceGroups = @{
        Hub    = 'dnspoc-rg-hub'
        Spoke  = 'dnspoc-rg-spoke'
        OnPrem = 'dnspoc-rg-onprem'
    }
    OnPremDnsIP    = '10.255.0.10'
}

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

function Get-ValidatedSshPublicKey {
    param([string]$InputKey)

    if ([string]::IsNullOrWhiteSpace($InputKey)) {
        throw 'SSH public key is required. Provide the key content or a path to a .pub file.'
    }

    $expandedPath = $InputKey
    if ($expandedPath -match '^(~\\|~/)') {
        $expandedPath = $expandedPath -replace '^(~\\|~/)', "$HOME\\"
    }

    if (Test-Path -LiteralPath $expandedPath) {
        $InputKey = Get-Content -LiteralPath $expandedPath -Raw
    }

    if ($InputKey -match 'BEGIN OPENSSH PRIVATE KEY') {
        throw 'The SSH key provided is a PRIVATE key. Provide the PUBLIC key (e.g., ~/.ssh/dnspoc.pub).' 
    }

    $keyLine = ($InputKey -split "`r?`n" | Where-Object { $_ -match '^(ssh-(rsa|ed25519)|ecdsa-sha2-nistp)' } | Select-Object -First 1)
    if (-not $keyLine) {
        $keyLine = $InputKey.Trim()
    }

    if ($keyLine -notmatch '^(ssh-(rsa|ed25519)|ecdsa-sha2-nistp)\s+[A-Za-z0-9+/=]+(\s+.*)?$') {
        throw 'Invalid SSH public key format. Provide the public key content (single line starting with ssh-rsa/ssh-ed25519/ecdsa-sha2-nistp) or a .pub file path.'
    }

    return $keyLine.Trim()
}

try {
    Write-Header 'DNS POC - SIMPLE DEPLOYMENT'

    $SSHPublicKey = Get-ValidatedSshPublicKey -InputKey $SSHPublicKey
    
    # Verify Azure connection
    Write-Step 'Verifying Azure connection'
    $context = Get-AzContext
    if (-not $context) {
        throw 'Not connected to Azure. Run Connect-AzAccount first.'
    }
    Write-Success "Connected as $($context.Account.Id)"
    
    # Create resource groups
    Write-Step 'Creating resource groups'
    foreach ($rgName in $config.ResourceGroups.Values) {
        $rg = Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue
        if (-not $rg) {
            New-AzResourceGroup -Name $rgName -Location $config.Location | Out-Null
            Write-Success "Created $rgName"
        }
        else {
            Write-Host "    • $rgName already exists" -ForegroundColor Gray
        }
    }
    
    # Deploy Hub
    Write-Step 'Deploying hub infrastructure (DNS resolver, private DNS zones, forwarding)'
    $hubDeployment = New-AzResourceGroupDeployment `
        -Name "hub-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
        -ResourceGroupName $config.ResourceGroups.Hub `
        -TemplateFile "$PSScriptRoot/../bicep/hub.bicep" `
        -envPrefix $config.EnvPrefix `
        -location $config.Location `
        -onpremDnsServerIP $config.OnPremDnsIP `
        -Verbose

    if ($hubDeployment.ProvisioningState -ne 'Succeeded') {
        throw 'Hub deployment failed'
    }
    Write-Success 'Hub infrastructure deployed'
    
    # Generate unique storage account name
    $storageAccountName = "dnspoc$((Get-Random -Minimum 10000 -Maximum 99999))"
    Write-Host "    • Storage account name: $storageAccountName" -ForegroundColor Gray
    
    # Deploy Spoke
    Write-Step 'Deploying spoke infrastructure (developer network, VM, storage with private endpoint)'
    $spokeDeployment = New-AzResourceGroupDeployment `
        -Name "spoke-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
        -ResourceGroupName $config.ResourceGroups.Spoke `
        -TemplateFile "$PSScriptRoot/../bicep/spoke.bicep" `
        -envPrefix $config.EnvPrefix `
        -location $config.Location `
        -hubVnetId $hubDeployment.Outputs.hubVnetId.Value `
        -hubVnetName $hubDeployment.Outputs.hubVnetName.Value `
        -hubResourceGroupName $config.ResourceGroups.Hub `
        -hubResolverInboundIP $hubDeployment.Outputs.resolverInboundIP.Value `
        -blobPrivateDnsZoneId $hubDeployment.Outputs.blobPrivateDnsZoneId.Value `
        -blobPrivateDnsZoneName $hubDeployment.Outputs.blobPrivateDnsZoneName.Value `
        -sshPublicKey $SSHPublicKey `
        -adminUsername $config.AdminUsername `
        -storageAccountName $storageAccountName `
        -Verbose

    if ($spokeDeployment.ProvisioningState -ne 'Succeeded') {
        throw 'Spoke deployment failed'
    }
    Write-Success 'Spoke infrastructure deployed'
    
    # Update hub forwarding ruleset to link to spoke and on-prem VNets
    Write-Step 'Updating DNS forwarding ruleset with VNet links'
    
    # Get on-prem VNet ID if it exists
    $onpremVnet = Get-AzVirtualNetwork -ResourceGroupName $config.ResourceGroups.OnPrem -Name "$($config.EnvPrefix)-vnet-onprem" -ErrorAction SilentlyContinue
    
    $vnetLinks = @(
        @{
            name   = "$($config.EnvPrefix)-vnet-spoke-link"
            vnetId = $spokeDeployment.Outputs.spokeVnetId.Value
        }
    )
    
    if ($onpremVnet) {
        $vnetLinks += @{
            name   = "$($config.EnvPrefix)-vnet-onprem-link"
            vnetId = $onpremVnet.Id
        }
    }
    
    $rulesetDeployment = New-AzResourceGroupDeployment `
        -Name "ruleset-update-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
        -ResourceGroupName $config.ResourceGroups.Hub `
        -TemplateFile "$PSScriptRoot/../bicep/dns-forwarding-ruleset.bicep" `
        -rulesetName "$($config.EnvPrefix)-forwarding-ruleset" `
        -location $config.Location `
        -outboundEndpointIds @($hubDeployment.Outputs.resolverOutboundEndpointId.Value) `
        -vnetLinks $vnetLinks `
        -forwardingRules @(
        @{
            name             = 'forward-example-pvt'
            domainName       = 'example.pvt.'
            targetDnsServers = @(
                @{
                    ipAddress = $config.OnPremDnsIP
                    port      = 53
                }
            )
        },
        @{
            name             = 'forward-internet-dns'
            domainName       = '.'
            targetDnsServers = @(
                @{
                    ipAddress = $config.OnPremDnsIP
                    port      = 53
                }
            )
        }
    ) `
        -Verbose

    if ($rulesetDeployment.ProvisioningState -ne 'Succeeded') {
        throw 'Ruleset update failed'
    }
    Write-Success 'DNS forwarding ruleset updated'
    
    # Display deployment summary
    Write-Header 'STAGE 1 COMPLETE - HUB & SPOKE DEPLOYED'
    
    Write-Host "`nDeployment Summary:" -ForegroundColor Green
    Write-Host "  Environment Prefix: $($config.EnvPrefix)" -ForegroundColor White
    Write-Host "  Location: $($config.Location)" -ForegroundColor White
    Write-Host "  Storage Account: $storageAccountName" -ForegroundColor White
    Write-Host "  Hub Resolver IP: $($hubDeployment.Outputs.resolverInboundIP.Value)" -ForegroundColor White
    
    Write-Host "`nVM Private IPs:" -ForegroundColor Green
    Write-Host "  Spoke Dev VM: $($spokeDeployment.Outputs.spokeDevVmPrivateIP.Value) ($($config.EnvPrefix)-vm-spoke-dev)" -ForegroundColor White
    
    Write-Host "`nNext Steps:" -ForegroundColor Yellow
    Write-Host '  1. Deploy on-prem infrastructure (Stage 1):' -ForegroundColor White
    Write-Host '     Run: ./scripts/deploy-onprem-stage1.ps1' -ForegroundColor Cyan
    Write-Host "`n  2. Configure on-prem DNS (Stage 2):" -ForegroundColor White
    Write-Host '     Run: ./scripts/deploy-onprem-stage2.ps1' -ForegroundColor Cyan
    Write-Host "`n  3. Run comprehensive tests:" -ForegroundColor White
    Write-Host '     See TESTING-GUIDE.md for all test scenarios' -ForegroundColor Gray
    Write-Host "`n  4. For SSH access to VMs (optional):" -ForegroundColor White
    Write-Host "     Run: ./scripts/add-public-ip.ps1 -VMName '$($config.EnvPrefix)-vm-spoke-dev' -ResourceGroupName '$($config.ResourceGroups.Spoke)'" -ForegroundColor Gray
    
}
catch {
    Write-Host "`n✗ Deployment failed: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
