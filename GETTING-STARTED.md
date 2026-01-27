# Quick Start Guide

## 🚀 Deploy the DNS POC

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
# 1. Generate SSH key (if you don't have one)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/dnspoc

# 2. Deploy everything with your SSH public key
$sshKey = Get-Content ~/.ssh/dnspoc.pub
./deploy.ps1 -SSHPublicKey $sshKey

# Optional: specify a different region (defaults to centralus)
./deploy.ps1 -SSHPublicKey $sshKey -Location "eastus"
```

**Duration:** ~15-20 minutes

### Test DNS Resolution

```powershell
# Get connection info and test instructions
./test.ps1

# Add public IPs to VMs for SSH access
./scripts/add-public-ip.ps1 -VMName "dnspoc-vm-spoke-dev" -ResourceGroupName "dnspoc-rg-spoke"
./scripts/add-public-ip.ps1 -VMName "dnspoc-vm-onprem-client" -ResourceGroupName "dnspoc-rg-onprem"

# Get public IPs
$spokeVm = Get-AzPublicIpAddress -ResourceGroupName "dnspoc-rg-spoke" -Name "dnspoc-vm-spoke-dev-pip"
$onpremVm = Get-AzPublicIpAddress -ResourceGroupName "dnspoc-rg-onprem" -Name "dnspoc-vm-onprem-client-pip"

# SSH to spoke VM and test DNS
ssh -i ~/.ssh/dnspoc azureuser@$($spokeVm.IpAddress)
```

Inside the VM, run these tests:

```bash
# Test private endpoint DNS
nslookup <storage-account>.blob.core.windows.net
# Expected: Should resolve to 10.1.1.x (private endpoint)

# Test VM name resolution (example.pvt domain)
nslookup dnspoc-vm-spoke-dev.example.pvt
# Expected: Should resolve to 10.1.0.10

nslookup dnspoc-vm-onprem-dns.example.pvt
# Expected: Should resolve to 10.255.0.10

# Test internet DNS resolution
nslookup microsoft.com
# Expected: Should resolve to public IP
```

### Cleanup

```powershell
# Delete everything
./teardown.ps1

# Skip confirmation prompt
./teardown.ps1 -Force
```

## 📚 Learn More

- **What's in the POC:** See [README.md](README.md)
- **What was fixed:** See [FIXES-APPLIED.md](FIXES-APPLIED.md)
- **Architecture details:** See [DEPLOYMENT.md](DEPLOYMENT.md)

## 🎯 What This Proves

✅ **Developers can deploy private endpoints** without needing DNS zone access

✅ **DNS records are automatic** - created automatically in centrally-managed zones

✅ **Hybrid DNS works** - on-prem can resolve Azure resources and vice versa

✅ **The hub-spoke model scales** - multiple spokes can use the central resolver

## 🔍 Key Files

- `deploy.ps1` - Deploy everything
- `teardown.ps1` - Delete everything
- `test.ps1` - Testing guide and connection info
- `bicep/hub.bicep` - Hub infrastructure (resolver, DNS zones, forwarding)
- `bicep/spoke.bicep` - Spoke infrastructure (developer network, storage)
- `bicep/onprem.bicep` - On-prem simulation (DNS server, client)
- `scripts/add-public-ip.ps1` - Add SSH access to VMs

## ❓ Troubleshooting

**DNS not working?**

SSH to the on-prem DNS server and check:

```bash
sudo systemctl status dnsmasq
sudo tail -f /var/log/dnsmasq.log
cat /etc/hosts | grep example.pvt
```

**Can't SSH to VMs?**

Make sure you added public IPs:

```powershell
./scripts/add-public-ip.ps1 -VMName "dnspoc-vm-spoke-dev" -ResourceGroupName "dnspoc-rg-spoke"
```

**Storage account name?**

The deployment generates a random name. Check the deployment output or Azure portal.

---

**Ready to prove Azure Private DNS works? Run `./deploy.ps1` and you're done!** 🎉
