#Requires -Modules Az.Accounts, Az.Resources

<#
.SYNOPSIS
    Stage 1: Deploy on-prem network and DNS server with Azure default DNS
.DESCRIPTION
    Deploys the on-prem infrastructure with Azure DNS so that cloud-init can install packages.
    After this completes, verify DNS server is working, then run stage 2 to update VNet DNS settings.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Location = 'centralus'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$config = @{
    EnvPrefix      = 'dnspoc'
    Location       = $Location
    AdminUsername  = 'azureuser'
    ResourceGroups = @{
        Hub    = 'dnspoc-rg-hub'
        OnPrem = 'dnspoc-rg-onprem'
    }
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

try {
    Write-Header 'STAGE 1: Deploy On-Prem Infrastructure'
    
    # Verify Azure connection
    Write-Step 'Verifying Azure connection'
    $context = Get-AzContext
    if (-not $context) {
        throw 'Not connected to Azure. Run Connect-AzAccount first.'
    }
    Write-Success "Connected as $($context.Account.Id)"
    
    # Get SSH key
    $sshKeyPath = "$home\.ssh\dnspoc.pub"
    if (-not (Test-Path $sshKeyPath)) {
        throw "SSH public key not found at $sshKeyPath. Generate one first with: ssh-keygen -t rsa -b 4096 -f ~/.ssh/dnspoc"
    }
    $sshPublicKey = (Get-Content $sshKeyPath -Raw).Trim()
    
    # Get hub information
    Write-Step 'Getting hub infrastructure information'
    $hubVnet = Get-AzVirtualNetwork -ResourceGroupName $config.ResourceGroups.Hub -Name 'dnspoc-vnet-hub' -ErrorAction SilentlyContinue
    if (-not $hubVnet) {
        throw 'Hub VNet not found. Deploy hub infrastructure first with: .\deploy.ps1'
    }
    
    # Get hub resolver IP from deployment outputs or calculate it (should be .4 in hub subnet)
    $hubResolverInboundIP = '10.0.0.4'
    Write-Success "Hub resolver IP: $hubResolverInboundIP"
    
    # Deploy on-prem with Azure default DNS
    Write-Step 'Deploying on-prem infrastructure (using Azure default DNS for now)'
    Write-Host '    • This allows cloud-init to install and configure dnsmasq' -ForegroundColor Gray
    Write-Host '    • Forwarding rules configured to resolve private endpoints' -ForegroundColor Gray
    Write-Host '    • After deployment, DNS server will be configured as VNet DNS in stage 2' -ForegroundColor Gray
    
    $onpremDeployment = New-AzResourceGroupDeployment `
        -Name "onprem-stage1-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
        -ResourceGroupName $config.ResourceGroups.OnPrem `
        -TemplateFile "$PSScriptRoot\..\bicep\onprem.bicep" `
        -envPrefix $config.EnvPrefix `
        -location $config.Location `
        -hubVnetId $hubVnet.Id `
        -hubVnetName $hubVnet.Name `
        -hubResourceGroupName $config.ResourceGroups.Hub `
        -hubResolverInboundIP $hubResolverInboundIP `
        -sshPublicKey $sshPublicKey `
        -Verbose
    
    if ($onpremDeployment.ProvisioningState -ne 'Succeeded') {
        throw 'On-prem deployment failed'
    }
    Write-Success 'On-prem infrastructure deployed'
    
    # Wait for cloud-init to complete
    Write-Step 'Waiting for cloud-init to complete (120 seconds)'
    Start-Sleep -Seconds 120
    
    # Verify dnsmasq is running
    Write-Step 'Verifying dnsmasq installation'
    Write-Host '    • This may take 1-2 minutes as VM agent becomes ready...' -ForegroundColor Gray
    
    $maxAttempts = 3
    $attempt = 0
    $dnsmasqRunning = $false
    
    while ($attempt -lt $maxAttempts -and -not $dnsmasqRunning) {
        $attempt++
        if ($attempt -gt 1) {
            Write-Host "    • Retry attempt $attempt/$maxAttempts..." -ForegroundColor Gray
            Start-Sleep -Seconds 30
        }
        
        try {
            $result = az vm run-command invoke `
                --resource-group $config.ResourceGroups.OnPrem `
                --name 'dnspoc-vm-onprem-dns' `
                --command-id RunShellScript `
                --scripts 'systemctl is-active dnsmasq' `
                --query 'value[0].message' `
                --output tsv `
                --no-wait:$false 2>&1
            
            if ($result -like '*running*') {
                Write-Success 'dnsmasq is running'
                $dnsmasqRunning = $true
            }
            elseif ($result -like '*inactive*') {
                Write-Host '    ⚠ dnsmasq is inactive. It may still be starting up...' -ForegroundColor Yellow
            }
        }
        catch {
            if ($attempt -lt $maxAttempts) {
                Write-Host '    • VM agent not ready yet. Retrying...' -ForegroundColor Gray
            }
            else {
                Write-Host '    ⚠ Unable to verify dnsmasq status. Check manually with:' -ForegroundColor Yellow
                Write-Host "      az vm run-command invoke --resource-group $($config.ResourceGroups.OnPrem) --name dnspoc-vm-onprem-dns --command-id RunShellScript --scripts 'systemctl status dnsmasq'" -ForegroundColor Gray
            }
        }
    }
    
    Write-Header 'STAGE 1 COMPLETE'
    
    Write-Host "`nWhat was deployed:" -ForegroundColor Cyan
    Write-Host '  ✓ On-prem VNet (10.255.0.0/16) with Azure default DNS' -ForegroundColor Gray
    Write-Host '  ✓ DNS server VM (10.255.0.10) with dnsmasq installed' -ForegroundColor Gray
    Write-Host '  ✓ Client VM (10.255.0.11)' -ForegroundColor Gray
    Write-Host '  ✓ VNet peering to hub' -ForegroundColor Gray
    
    Write-Host "`nNext steps:" -ForegroundColor Cyan
    Write-Host '  1. Test DNS server manually (should work):' -ForegroundColor White
    Write-Host '     • Internet: nslookup microsoft.com 127.0.0.1' -ForegroundColor Gray
    Write-Host '     • Local domain: nslookup dnspoc-vm-spoke-dev.example.pvt 127.0.0.1' -ForegroundColor Gray
    Write-Host '     • Storage account: nslookup <storagename>.blob.core.windows.net 127.0.0.1' -ForegroundColor Gray
    
    Write-Host "`n  2. Once DNS works, run Stage 2 to update VNet DNS settings:" -ForegroundColor White
    Write-Host '     .\scripts\03-configure-onprem-dns.ps1' -ForegroundColor Gray
    
}
catch {
    Write-Host "`n✗ Error: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
