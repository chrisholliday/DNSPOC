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

```text
Azure VM queries example.pvt
  ↓
Hub DNS Resolver (10.0.0.4)
  ↓
Forwards to On-Prem DNS (10.255.0.10)
  ↓
On-Prem DNS serves from /etc/hosts
```

```text
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

```text
Azure VM queries google.com
  ↓
Hub DNS Resolver (10.0.0.4)
  ↓
Forwards to On-Prem DNS (10.255.0.10)
  ↓
On-Prem DNS forwards to public DNS (8.8.8.8)
  ↓
Returns public IP
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

# Deploy in stages for better control and testing

# STAGE 0: Deploy hub and spoke infrastructure
./scripts/01-deploy-hub-spoke.ps1 -SSHPublicKey (Get-Content ~/.ssh/dnspoc.pub)

# STAGE 1: Deploy on-prem infrastructure with Azure default DNS
./scripts/02-deploy-onprem.ps1

# STAGE 2: Configure on-prem VNet to use the on-prem DNS server
./scripts/03-configure-onprem-dns.ps1

# Optional: specify a different region for stage 0
./scripts/01-deploy-hub-spoke.ps1 -SSHPublicKey (Get-Content ~/.ssh/dnspoc.pub) -Location "eastus"
```

**Total Duration:** ~25-30 minutes (includes 60 second wait for cloud-init and 2-3 min for VM restart)

### Test DNS Resolution

See [TESTING-GUIDE.md](./TESTING-GUIDE.md) for comprehensive testing scenarios.

Quick validation:

```powershell
# Test DNS server directly
az vm run-command invoke --resource-group dnspoc-rg-onprem --name dnspoc-vm-onprem-dns `
  --command-id RunShellScript `
  --scripts "nslookup microsoft.com 127.0.0.1; nslookup dnspoc-vm-spoke-dev.example.pvt 127.0.0.1"

# After stage 2, test client VM (wait 2-3 min for VM restart)
$storageAccount = (Get-AzStorageAccount -ResourceGroupName dnspoc-rg-spoke).StorageAccountName
az vm run-command invoke --resource-group dnspoc-rg-onprem --name dnspoc-vm-onprem-client `
  --command-id RunShellScript `
  --scripts "nslookup microsoft.com; nslookup $storageAccount.blob.core.windows.net"
```

### Teardown

```powershell
# Delete everything
./scripts/teardown.ps1

# Skip confirmation prompt
./scripts/teardown.ps1 -Force
```

## 🎯 What Makes This Simple

This is a **proof of concept**, not a production-ready solution. Simplifications:

✅ **Hardcoded values** - No config files, everything is in the scripts  
✅ **Fixed IPs** - All VMs use static IPs for predictability  
✅ **Small script set** - One deploy script plus two on-prem stages  
✅ **No abstractions** - Direct Bicep deployments without unnecessary modules  
✅ **Clear naming** - Resources named `dnspoc-*` consistently  

## 📝 Key Files

- `scripts/01-deploy-hub-spoke.ps1` - Stage 0: hub + spoke deployment
- `scripts/02-deploy-onprem.ps1` - Stage 1: on-prem deployment (Azure default DNS)
- `scripts/03-configure-onprem-dns.ps1` - Stage 2: switch VNet DNS to on-prem
- `scripts/teardown.ps1` - Complete cleanup
- `scripts/test.ps1` - Connection info and test guidance
- `bicep/hub.bicep` - Hub network, DNS resolver, private DNS zones, forwarding rules
- `bicep/spoke.bicep` - Spoke network, developer VM, storage with private endpoint
- `bicep/onprem.bicep` - On-prem simulation with dnsmasq DNS server
- `scripts/add-public-ip.ps1` - Adds public IP to VMs for SSH access

## 🔍 Validation Tests

After deployment, these should all work:

| Test | Location | Command | Expected Result |
| --- | --- | --- | --- |
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
