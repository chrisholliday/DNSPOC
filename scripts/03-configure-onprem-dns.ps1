#Requires -Modules Az.Accounts, Az.Network

<#
.SYNOPSIS
    Stage 3: Update on-prem VNet DNS to use the on-prem DNS server
.DESCRIPTION
    After verifying the DNS server works, this updates the VNet DNS settings
    to point to the on-prem DNS server and restarts VMs to pick up the new settings.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$config = @{
    ResourceGroups = @{
        OnPrem = 'dnspoc-rg-onprem'
    }
    DnsServerIP    = '10.255.0.10'
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
    Write-Header 'STAGE 3: Configure On-Prem VNet DNS'
    
    # Verify Azure connection
    Write-Step 'Verifying Azure connection'
    $context = Get-AzContext
    if (-not $context) {
        throw 'Not connected to Azure. Run Connect-AzAccount first.'
    }
    Write-Success "Connected as $($context.Account.Id)"
    
    # Verify DNS server is working
    Write-Step 'Verifying DNS server is operational'
    Write-Host '    Testing DNS resolution on DNS server...' -ForegroundColor Gray
    
    $dnsTest = az vm run-command invoke `
        --resource-group $config.ResourceGroups.OnPrem `
        --name 'dnspoc-vm-onprem-dns' `
        --command-id RunShellScript `
        --scripts 'nslookup microsoft.com 127.0.0.1 2>&1 | grep -i address' `
        --query 'value[0].message' `
        --output tsv 2>&1
    
    if ($dnsTest -like '*Address:*' -and $dnsTest -notlike '*connection refused*') {
        Write-Success 'DNS server is responding'
    }
    else {
        Write-Host '    ⚠ Warning: DNS server may not be fully operational' -ForegroundColor Yellow
        Write-Host "    Test output: $dnsTest" -ForegroundColor Gray
        $continue = Read-Host "`nContinue anyway? (y/N)"
        if ($continue -ne 'y') {
            exit 0
        }
    }
    
    # Update VNet DNS settings
    Write-Step 'Updating on-prem VNet DNS settings'
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $config.ResourceGroups.OnPrem -Name 'dnspoc-vnet-onprem'
    $vnet.DhcpOptions.DnsServers = @($config.DnsServerIP)
    $vnet | Set-AzVirtualNetwork | Out-Null
    Write-Success "VNet DNS updated to: $($config.DnsServerIP)"
    
    # Add on-prem VNet link to DNS forwarding ruleset (if not already linked)
    Write-Step 'Adding on-prem VNet to DNS forwarding ruleset'
    $hubResourceGroup = 'dnspoc-rg-hub'
    $rulesetName = 'dnspoc-forwarding-ruleset'
    $linkName = 'dnspoc-vnet-onprem-link'
    
    $existingLink = Get-AzResource -ResourceGroupName $hubResourceGroup `
        -ResourceType 'Microsoft.Network/dnsForwardingRulesets/virtualNetworkLinks' `
        -Name "$rulesetName/$linkName" `
        -ErrorAction SilentlyContinue
    
    if (-not $existingLink) {
        Write-Host '    • Linking on-prem VNet to DNS forwarding ruleset...' -ForegroundColor Gray
        $onpremVnetId = $vnet.Id
        
        $linkResource = New-AzResource -ResourceGroupName $hubResourceGroup `
            -ResourceType 'Microsoft.Network/dnsForwardingRulesets/virtualNetworkLinks' `
            -Name "$rulesetName/$linkName" `
            -Properties @{
            virtualNetwork = @{
                id = $onpremVnetId
            }
        } `
            -Force -ErrorAction SilentlyContinue
        
        if ($linkResource) {
            Write-Success 'On-prem VNet linked to DNS forwarding ruleset'
        }
        else {
            Write-Host '    ⚠ Could not link on-prem VNet (may already be linked)' -ForegroundColor Yellow
        }
    }
    else {
        Write-Success 'On-prem VNet already linked to DNS forwarding ruleset'
    }
    
    # Restart VMs to pick up new DNS
    Write-Step 'Restarting VMs to apply DNS settings'
    Write-Host '    • Restarting dnspoc-vm-onprem-client...' -ForegroundColor Gray
    Restart-AzVM -ResourceGroupName $config.ResourceGroups.OnPrem -Name 'dnspoc-vm-onprem-client' -NoWait | Out-Null
    
    Write-Success 'VM restart initiated'
    Write-Host '    VMs will pick up new DNS settings on next DHCP renewal or reboot' -ForegroundColor Gray
    
    Write-Header 'STAGE 3 COMPLETE'
    
    Write-Host "`nWhat was configured:" -ForegroundColor Cyan
    Write-Host "  ✓ On-prem VNet DNS set to $($config.DnsServerIP)" -ForegroundColor Gray
    Write-Host '  ✓ Client VM restarted' -ForegroundColor Gray
    
    Write-Host "`nNext steps:" -ForegroundColor Cyan
    Write-Host '  1. Wait 2-3 minutes for VM to restart' -ForegroundColor White
    
    Write-Host "`n  2. Test DNS from client VM:" -ForegroundColor White
    Write-Host "     az vm run-command invoke --resource-group $($config.ResourceGroups.OnPrem) --name dnspoc-vm-onprem-client --command-id RunShellScript --scripts 'cat /etc/resolv.conf; nslookup microsoft.com; nslookup dnspoc-vm-spoke-dev.example.pvt'" -ForegroundColor Gray
    
    Write-Host "`n  3. If all works, your on-prem DNS is fully configured!" -ForegroundColor White
    
}
catch {
    Write-Host "`n✗ Error: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
