# 🚀 Azure Private DNS Proof of Concept

A straightforward demonstration of Azure Private DNS with hub-and-spoke architecture, showing how developers can deploy storage accounts with private endpoints without needing DNS zone access.

## 📘 What This Proves

This POC demonstrates that:

1. **Developers can deploy private endpoints** for Azure PaaS services (like Storage) in their own spoke VNets
2. **DNS "just works"** - private endpoint DNS records are automatically created in centrally-managed DNS zones
3. **On-premises integration works** - simulated on-prem network can resolve Azure private endpoints and vice versa
4. **VM name resolution works** - VMs across all networks can resolve each other using the `example.pvt` domain

## 🏗️ Architecture

### Networks

- **Hub VNet (10.0.0.0/16)** - Platform team owned
  - Azure DNS Private Resolver (inbound + outbound endpoints)
  - Private DNS zones: `privatelink.blob.core.windows.net` and `example.pvt`
  - DNS forwarding ruleset

- **Spoke VNet (10.1.0.0/16)** - Developer owned
  - Developer VM (10.1.0.10)
  - Storage account with private endpoint (10.1.1.x)

- **On-Prem VNet (10.255.0.0/16)** - Simulated on-premises
  - DNS server VM (10.255.0.10) running dnsmasq
  - Client VM (10.255.0.11)

### DNS Resolution Flow

```
Azure VM queries example.pvt
  ↓
Hub DNS Resolver (10.0.0.4)
  ↓
Forwards to On-Prem DNS (10.255.0.10)
  ↓
On-Prem DNS serves from /etc/hosts
```

```
On-Prem VM queries storage.blob.core.windows.net
  ↓
On-Prem DNS (10.255.0.10)
  ↓
Forwards privatelink.* to Hub Resolver (10.0.0.4)
  ↓
Hub Resolver queries Private DNS Zone
  ↓
Returns private endpoint IP (10.1.1.x)
```

## 🚀 Quick Start

### Prerequisites

1. Azure subscription
2. PowerShell with Az module installed
3. SSH key pair for VM access

```powershell
# Install Az module if needed
Install-Module -Name Az -Repository PSGallery -Force

# Login to Azure
Connect-AzAccount
```

### Deploy

```powershell
# Generate SSH key (if you don't have one)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/dnspoc -C "dnspoc"

# Deploy everything with your SSH public key
$sshKey = Get-Content ~/.ssh/dnspoc.pub
./deploy.ps1 -SSHPublicKey $sshKey

# Optional: specify a different region
./deploy.ps1 -SSHPublicKey $sshKey -Location "eastus"
```

**Duration:** ~15-20 minutes

### Test DNS Resolution

```powershell
# Add public IPs to VMs for SSH access
./scripts/add-public-ip.ps1 -VMName "dnspoc-vm-spoke-dev" -ResourceGroupName "dnspoc-rg-spoke"
./scripts/add-public-ip.ps1 -VMName "dnspoc-vm-onprem-client" -ResourceGroupName "dnspoc-rg-onprem"

# Get public IPs
$spokeVm = Get-AzPublicIpAddress -ResourceGroupName "dnspoc-rg-spoke" -Name "dnspoc-vm-spoke-dev-pip"
$onpremVm = Get-AzPublicIpAddress -ResourceGroupName "dnspoc-rg-onprem" -Name "dnspoc-vm-onprem-client-pip"

Write-Host "Spoke VM IP: $($spokeVm.IpAddress)"
Write-Host "On-Prem VM IP: $($onpremVm.IpAddress)"

# SSH to spoke VM and test
ssh -i ~/.ssh/dnspoc azureuser@<spoke-vm-public-ip>

# Inside spoke VM, test DNS resolution:
nslookup dnspoc12345.blob.core.windows.net    # Should resolve to 10.1.1.x (private endpoint)
nslookup dnspoc-vm-spoke-dev.example.pvt       # Should resolve to 10.1.0.10
nslookup dnspoc-vm-onprem-dns.example.pvt      # Should resolve to 10.255.0.10
nslookup microsoft.com                          # Should resolve to public IP
```

### Teardown

```powershell
# Delete everything
./teardown.ps1

# Skip confirmation prompt
./teardown.ps1 -Force
```

## 🎯 What Makes This Simple

This is a **proof of concept**, not a production-ready solution. Simplifications:

✅ **Hardcoded values** - No config files, everything is in the scripts  
✅ **Fixed IPs** - All VMs use static IPs for predictability  
✅ **Minimal scripts** - Two scripts: deploy and teardown  
✅ **No abstractions** - Direct Bicep deployments without unnecessary modules  
✅ **Clear naming** - Resources named `dnspoc-*` consistently  

## 📝 Key Files

- `deploy.ps1` - Complete deployment orchestration
- `teardown.ps1` - Complete cleanup
- `test.ps1` - Connection information and testing guide
- `bicep/hub.bicep` - Hub network, DNS resolver, private DNS zones, forwarding rules
- `bicep/spoke.bicep` - Spoke network, developer VM, storage with private endpoint
- `bicep/onprem.bicep` - On-prem simulation with dnsmasq DNS server
- `scripts/add-public-ip.ps1` - Adds public IP to VMs for SSH access

## 🔍 Validation Tests

After deployment, these should all work:

| Test | Location | Command | Expected Result |
|------|----------|---------|----------------|
| Private endpoint DNS | Spoke VM | `nslookup <storage>.blob.core.windows.net` | 10.1.1.x |
| VM name resolution | Spoke VM | `nslookup dnspoc-vm-spoke-dev.example.pvt` | 10.1.0.10 |
| On-prem VM resolution | Spoke VM | `nslookup dnspoc-vm-onprem-dns.example.pvt` | 10.255.0.10 |
| Internet DNS | Spoke VM | `nslookup microsoft.com` | Public IP |
| Private endpoint from on-prem | On-Prem VM | `nslookup <storage>.blob.core.windows.net` | 10.1.1.x |

## 🔒 What Developers Don't Need

- ✅ Access to Private DNS zones
- ✅ Permissions to create DNS records
- ✅ Knowledge of DNS resolver configuration
- ✅ Access to hub network

They just deploy their storage account with a private endpoint, and DNS works automatically!

## 💡 Real-World Usage

In production, you would:

- Use Azure Policy to enforce private endpoints
- Implement proper RBAC with least privilege
- Use separate subscriptions for hub and spokes
- Implement network security with NSGs and Azure Firewall
- Use Azure Bastion instead of public IPs for VM access
- Automate with CI/CD pipelines
- Monitor with Azure Monitor and Log Analytics

But for a POC, this simple approach proves the concept works.

## 🐛 Troubleshooting

### DNS not resolving

```bash
# Check DNS server on VM
cat /etc/resolv.conf

# Should show hub resolver IP: 10.0.0.4 (for spoke/hub VMs)
# Should show on-prem DNS: 10.255.0.10 (for on-prem VMs)
```

### On-prem DNS issues

```bash
# SSH to on-prem DNS server
ssh -i ~/.ssh/dnspoc azureuser@<onprem-dns-ip>

# Check dnsmasq status
sudo systemctl status dnsmasq

# View DNS query logs
sudo tail -f /var/log/dnsmasq.log

# Check hosts file
cat /etc/hosts | grep example.pvt
```

### Private endpoint not resolving

```bash
# Check if private endpoint exists
az network private-endpoint list --resource-group dnspoc-rg-spoke --output table

# Check DNS zone records
az network private-dns record-set a list --zone-name privatelink.blob.core.windows.net --resource-group dnspoc-rg-hub --output table
```

## 📚 Learn More

- [Azure Private DNS](https://learn.microsoft.com/azure/dns/private-dns-overview)
- [Azure DNS Private Resolver](https://learn.microsoft.com/azure/dns/dns-private-resolver-overview)
- [Private Endpoints](https://learn.microsoft.com/azure/private-link/private-endpoint-overview)
- [Hub-Spoke Network Topology](https://learn.microsoft.com/azure/architecture/reference-architectures/hybrid-networking/hub-spoke)

## 📄 License

MIT License - See LICENSE file for details
