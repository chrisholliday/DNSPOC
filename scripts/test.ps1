#Requires -Modules Az.Accounts, Az.Compute

<#
.SYNOPSIS
    Simplified DNS testing guide for DNS POC
.DESCRIPTION
    Displays connection information and test commands for validating DNS resolution
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Hardcoded configuration
$resourceGroups = @{
    Hub = 'dnspoc-rg-hub'
    Spoke = 'dnspoc-rg-spoke'
    OnPrem = 'dnspoc-rg-onprem'
}

function Write-Header {
    param([string]$Message)
    Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║ $($Message.PadRight(65)) ║" -ForegroundColor Cyan
    Write-Host '╚═══════════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Message)
    Write-Host "`n$Message" -ForegroundColor Cyan
}

try {
    Write-Header "DNS POC - TEST GUIDE"
    
    # Verify Azure connection
    $context = Get-AzContext
    if (-not $context) {
        throw 'Not connected to Azure. Run Connect-AzAccount first.'
    }
    
    # Get VM information
    Write-Step '📍 VM Connection Information'
    
    $spokeVm = Get-AzVM -ResourceGroupName $resourceGroups.Spoke -Name 'dnspoc-vm-spoke-dev' -Status -ErrorAction SilentlyContinue
    $onpremClient = Get-AzVM -ResourceGroupName $resourceGroups.OnPrem -Name 'dnspoc-vm-onprem-client' -Status -ErrorAction SilentlyContinue
    $onpremDns = Get-AzVM -ResourceGroupName $resourceGroups.OnPrem -Name 'dnspoc-vm-onprem-dns' -Status -ErrorAction SilentlyContinue
    
    if (-not $spokeVm) {
        throw "Spoke VM not found. Has the deployment completed successfully?"
    }
    
    # Get network interfaces and private IPs
    $spokeNic = Get-AzNetworkInterface -ResourceId $spokeVm.NetworkProfile.NetworkInterfaces[0].Id
    $spokePrivateIP = $spokeNic.IpConfigurations[0].PrivateIpAddress
    
    $onpremClientNic = Get-AzNetworkInterface -ResourceId $onpremClient.NetworkProfile.NetworkInterfaces[0].Id
    $onpremClientPrivateIP = $onpremClientNic.IpConfigurations[0].PrivateIpAddress
    
    $onpremDnsNic = Get-AzNetworkInterface -ResourceId $onpremDns.NetworkProfile.NetworkInterfaces[0].Id
    $onpremDnsPrivateIP = $onpremDnsNic.IpConfigurations[0].PrivateIpAddress
    
    # Check for public IPs
    Write-Host "Spoke Dev VM (dnspoc-vm-spoke-dev)" -ForegroundColor Yellow
    Write-Host "  Private IP: $spokePrivateIP" -ForegroundColor White
    
    $spokePip = Get-AzPublicIpAddress -ResourceGroupName $resourceGroups.Spoke -Name 'dnspoc-vm-spoke-dev-pip' -ErrorAction SilentlyContinue
    if ($spokePip) {
        Write-Host "  Public IP:  $($spokePip.IpAddress)" -ForegroundColor Green
        Write-Host "  SSH:        ssh -i ~/.ssh/dnspoc azureuser@$($spokePip.IpAddress)" -ForegroundColor Gray
    } else {
        Write-Host "  Public IP:  Not assigned" -ForegroundColor Gray
        Write-Host "  To add:     ./scripts/add-public-ip.ps1 -VMName 'dnspoc-vm-spoke-dev' -ResourceGroupName '$($resourceGroups.Spoke)'" -ForegroundColor Gray
    }
    
    Write-Host "`nOn-Prem Client VM (dnspoc-vm-onprem-client)" -ForegroundColor Yellow
    Write-Host "  Private IP: $onpremClientPrivateIP" -ForegroundColor White
    
    $onpremPip = Get-AzPublicIpAddress -ResourceGroupName $resourceGroups.OnPrem -Name 'dnspoc-vm-onprem-client-pip' -ErrorAction SilentlyContinue
    if ($onpremPip) {
        Write-Host "  Public IP:  $($onpremPip.IpAddress)" -ForegroundColor Green
        Write-Host "  SSH:        ssh -i ~/.ssh/dnspoc azureuser@$($onpremPip.IpAddress)" -ForegroundColor Gray
    } else {
        Write-Host "  Public IP:  Not assigned" -ForegroundColor Gray
        Write-Host "  To add:     ./scripts/add-public-ip.ps1 -VMName 'dnspoc-vm-onprem-client' -ResourceGroupName '$($resourceGroups.OnPrem)'" -ForegroundColor Gray
    }
    
    Write-Host "`nOn-Prem DNS Server (dnspoc-vm-onprem-dns)" -ForegroundColor Yellow
    Write-Host "  Private IP: $onpremDnsPrivateIP" -ForegroundColor White
    
    # Get storage account name
    $storageAccounts = Get-AzStorageAccount -ResourceGroupName $resourceGroups.Spoke
    if ($storageAccounts.Count -gt 0) {
        $storageAccountName = $storageAccounts[0].StorageAccountName
    } else {
        $storageAccountName = '<storage-account-name>'
    }
    
    # Display test scenarios
    Write-Header "🧪 DNS RESOLUTION TESTS"
    
    Write-Host "`n1️⃣  Test Private Endpoint Resolution (from Spoke VM)" -ForegroundColor Yellow
    Write-Host "   Tests that Azure private endpoints resolve to private IPs" -ForegroundColor Gray
    Write-Host "   Command: nslookup $storageAccountName.blob.core.windows.net" -ForegroundColor White
    Write-Host "   Expected: Should resolve to 10.1.1.x (private endpoint in spoke)" -ForegroundColor Green
    
    Write-Host "`n2️⃣  Test VM Name Resolution (from Spoke VM)" -ForegroundColor Yellow
    Write-Host "   Tests that example.pvt domain resolves via on-prem DNS" -ForegroundColor Gray
    Write-Host "   Command: nslookup dnspoc-vm-spoke-dev.example.pvt" -ForegroundColor White
    Write-Host "   Expected: Should resolve to $spokePrivateIP" -ForegroundColor Green
    Write-Host "   Command: nslookup dnspoc-vm-onprem-dns.example.pvt" -ForegroundColor White
    Write-Host "   Expected: Should resolve to $onpremDnsPrivateIP" -ForegroundColor Green
    
    Write-Host "`n3️⃣  Test Internet DNS (from Spoke VM)" -ForegroundColor Yellow
    Write-Host "   Tests that public DNS works through forwarding chain" -ForegroundColor Gray
    Write-Host "   Command: nslookup microsoft.com" -ForegroundColor White
    Write-Host "   Expected: Should resolve to public IP address" -ForegroundColor Green
    
    Write-Host "`n4️⃣  Test Private Endpoint from On-Prem" -ForegroundColor Yellow
    Write-Host "   Tests hybrid DNS - on-prem can resolve Azure private endpoints" -ForegroundColor Gray
    Write-Host "   Command: nslookup $storageAccountName.blob.core.windows.net" -ForegroundColor White
    Write-Host "   Expected: Should resolve to 10.1.1.x" -ForegroundColor Green
    
    Write-Host "`n5️⃣  Test VM Resolution from On-Prem" -ForegroundColor Yellow
    Write-Host "   Tests that on-prem can resolve Azure VM names" -ForegroundColor Gray
    Write-Host "   Command: nslookup dnspoc-vm-spoke-dev.example.pvt" -ForegroundColor White
    Write-Host "   Expected: Should resolve to $spokePrivateIP" -ForegroundColor Green
    
    Write-Header "🔍 DNS FLOW DIAGRAM"
    
    Write-Host "`nAzure VM → Private Endpoint:" -ForegroundColor Cyan
    Write-Host "  VM → Hub Resolver (10.0.0.4) → Private DNS Zone → Private IP" -ForegroundColor Gray
    
    Write-Host "`nAzure VM → example.pvt:" -ForegroundColor Cyan
    Write-Host "  VM → Hub Resolver (10.0.0.4) → Forwarding Rule → On-Prem DNS (10.255.0.10) → /etc/hosts" -ForegroundColor Gray
    
    Write-Host "`nAzure VM → Internet:" -ForegroundColor Cyan
    Write-Host "  VM → Hub Resolver (10.0.0.4) → Forwarding Rule → On-Prem DNS (10.255.0.10) → Public DNS (8.8.8.8)" -ForegroundColor Gray
    
    Write-Host "`nOn-Prem → Private Endpoint:" -ForegroundColor Cyan
    Write-Host "  VM → On-Prem DNS (10.255.0.10) → Forwarding Rule → Hub Resolver (10.0.0.4) → Private DNS Zone → Private IP" -ForegroundColor Gray
    
    Write-Header "📝 TROUBLESHOOTING"
    
    Write-Host "`nIf DNS isn't working:" -ForegroundColor Yellow
    Write-Host "`n1. Check VM DNS settings:" -ForegroundColor White
    Write-Host "   cat /etc/resolv.conf" -ForegroundColor Gray
    Write-Host "   Should show: nameserver 10.0.0.4 (for spoke VM)" -ForegroundColor Gray
    Write-Host "   Should show: nameserver 10.255.0.10 (for on-prem VMs)" -ForegroundColor Gray
    
    Write-Host "`n2. Test DNS server directly:" -ForegroundColor White
    Write-Host "   nslookup microsoft.com 10.0.0.4" -ForegroundColor Gray
    Write-Host "   nslookup dnspoc-vm-spoke-dev.example.pvt 10.255.0.10" -ForegroundColor Gray
    
    Write-Host "`n3. Check on-prem DNS server (SSH to dnspoc-vm-onprem-dns):" -ForegroundColor White
    Write-Host "   sudo systemctl status dnsmasq" -ForegroundColor Gray
    Write-Host "   sudo tail -f /var/log/dnsmasq.log" -ForegroundColor Gray
    Write-Host "   cat /etc/hosts | grep example.pvt" -ForegroundColor Gray
    
    Write-Host "`n4. Check private DNS records:" -ForegroundColor White
    Write-Host "   az network private-dns record-set a list --zone-name privatelink.blob.core.windows.net --resource-group $($resourceGroups.Hub) --output table" -ForegroundColor Gray
    
    Write-Host ""
    
} catch {
    Write-Host "`n✗ Error: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
