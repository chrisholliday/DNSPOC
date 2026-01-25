#Requires -Modules Az.Accounts, Az.Resources, Az.Network

<#
.SYNOPSIS
    Configures DNS forwarding ruleset to forward queries to on-prem DNS
.DESCRIPTION
    Creates DNS forwarding ruleset with rules to forward public and on-prem queries
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

function Write-ErrorMessage {
    param([string]$Message)
    Write-Host "    ✗ $Message" -ForegroundColor Red
}

try {
    # Load configuration
    Write-Step "Loading configuration"
    $config = Get-Content $ConfigPath | ConvertFrom-Json
    $hubOutputs = Get-Content "$PSScriptRoot/../.outputs/hub-outputs.json" | ConvertFrom-Json
    $spokeOutputs = Get-Content "$PSScriptRoot/../.outputs/spoke-outputs.json" | ConvertFrom-Json
    $onpremOutputs = Get-Content "$PSScriptRoot/../.outputs/onprem-outputs.json" | ConvertFrom-Json
    Write-Success "Configuration loaded"

    $hubRgName = $config.resourceGroups.hub
    $resolverName = "$($config.envPrefix)-resolver-hub"
    $rulesetName = "$($config.envPrefix)-ruleset-hub"
    $onpremDnsIP = $onpremOutputs.dnsServerIP.value

    Write-Step "Deploying DNS forwarding ruleset"
    
    # Deploy ruleset using Bicep
    $rulesetDeployment = New-AzResourceGroupDeployment `
        -Name "ruleset-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
        -ResourceGroupName $hubRgName `
        -TemplateFile "$PSScriptRoot/../bicep/dns-forwarding-ruleset.bicep" `
        -rulesetName $rulesetName `
        -location $config.location `
        -outboundEndpointIds @($hubOutputs.resolverOutboundEndpointId.value) `
        -vnetLinks @(
            @{
                name = "$($config.envPrefix)-vnet-spoke-link"
                vnetId = $spokeOutputs.spokeVnetId.value
            },
            @{
                name = "$($config.envPrefix)-vnet-onprem-link"
                vnetId = $onpremOutputs.onpremVnetId.value
            }
        ) `
        -forwardingRules @(
            @{
                name = "forward-to-onprem"
                domainName = "."
                targetDnsServers = @(
                    @{
                        ipAddress = $onpremDnsIP
                        port = 53
                    }
                )
            }
        ) `
        -Verbose

    if ($rulesetDeployment.ProvisioningState -ne 'Succeeded') {
        throw "Ruleset deployment failed"
    }

    Write-Success "DNS forwarding ruleset configured"
    Write-Host "`nForwarding Configuration:" -ForegroundColor Yellow
    Write-Host "  All queries (.) forward to: $onpremDnsIP" -ForegroundColor Gray

} catch {
    Write-ErrorMessage "Configuration failed: $_"
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
