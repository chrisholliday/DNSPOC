# 🚀 Quick Start Guide

## 1. Prerequisites Check

```powershell
# Verify Az module is installed
Get-Module -ListAvailable -Name Az

# If not installed:
Install-Module -Name Az -Repository PSGallery -Force

# Login to Azure
Connect-AzAccount

# Verify context
Get-AzContext
```

## 2. Configure Settings

1. **Create your configuration file:**

```powershell
# Copy the example config to create your own
Copy-Item config/config.json.example config/config.json
```

1. **Configure SSH Key:**

The deployment will automatically check for an SSH key and offer to generate one if needed. You can also pre-generate one:

```powershell
# Auto-generate SSH key for your OS (Windows, macOS, or Linux)
./scripts/New-SSHKeyPair.ps1
```

Then copy the public key content from your `.ssh/dnspoc.pub` file into `config/config.json`.

1. **Review other settings in `config/config.json`:**

- **SSH Public Key**: Will be populated automatically if you run `New-SSHKeyPair.ps1`, or the deployment script will prompt you to add it
- **Storage Account Name**: Leave empty (`""`) — a unique name will be auto-generated during deployment
- **Location**: (Optional) Change from `centralus` to your preferred Azure region if desired

**Notes:**

- Storage account names must be globally unique. The deployment script will automatically generate and validate a unique name for you.
- To override the location during deployment, pass `-Location "yourregion"` to the deploy script

## 3. Deploy

```powershell
# Deploy everything (uses location from config.json)
./scripts/deploy-all.ps1

# Or override the location
./scripts/deploy-all.ps1 -Location "eastus"
```

**Duration:** ~15-20 minutes

## 4. Validate Deployment

After deployment completes, validate that all resources were created successfully:

```powershell
# Run validation checks
./scripts/Validate-Deployment.ps1
```

This will verify:

- All resource groups were created
- VNets and subnets are in place
- DNS Resolver with inbound/outbound endpoints
- Private DNS zones are linked
- VMs are created and running
- Storage account exists
- VNet peering is configured

## 5. Test

```powershell
# Get test instructions
./scripts/test-dns.ps1

# Add public IP to VMs for SSH access
./scripts/add-public-ip.ps1 -VMName "dnspoc-vm-spoke-dev" -ResourceGroupName "dnspoc-rg-spoke"
./scripts/add-public-ip.ps1 -VMName "dnspoc-vm-onprem-client" -ResourceGroupName "dnspoc-rg-onprem"

# SSH to VMs and test DNS

# Windows
ssh -i "$env:USERPROFILE\.ssh\dnspoc" azureuser@<public-ip>

# macOS / Linux
ssh -i "$HOME/.ssh/dnspoc" azureuser@<public-ip>

# Inside VM:
nslookup <storage-account>.blob.core.windows.net
nslookup microsoft.com
```

## 6. Cleanup

```powershell
# Remove all resources
./scripts/teardown.ps1
```

## Common Commands

```powershell
# Validate deployment after deploy-all.ps1
./scripts/Validate-Deployment.ps1

# Deploy only hub
./scripts/deploy-hub.ps1

# Deploy only spoke
./scripts/deploy-spoke.ps1

# Deploy only on-prem
./scripts/deploy-onprem.ps1

# Redeploy with skip flags
./scripts/deploy-all.ps1 -SkipHub

# Run DNS tests
./scripts/test-dns.ps1

# Force teardown without confirmation
./scripts/teardown.ps1 -Force
```

## Troubleshooting

**Issue:** `Configuration file not found`

- **Fix:** Run scripts from project root or specify `-ConfigPath`

**Issue:** `Hub outputs file not found`

- **Fix:** Run `deploy-hub.ps1` before `deploy-spoke.ps1`

**Issue:** `Storage account name already exists`

- **Fix:** Change `storageAccountName` in `config/config.json` to be unique

**Issue:** Can't SSH to VMs

- **Fix:** Add public IP using `add-public-ip.ps1` script

## What Gets Deployed

### Hub Resource Group (dnspoc-rg-hub)

- Virtual Network (10.0.0.0/16)
- DNS Private Resolver
- Private DNS Zone: privatelink.blob.core.windows.net
- Private DNS Zone: example.pvt

### Spoke Resource Group (dnspoc-rg-spoke)

- Virtual Network (10.1.0.0/16)
- Storage Account with Private Endpoint
- Ubuntu VM for testing

### On-Prem Resource Group (dnspoc-rg-onprem)

- Virtual Network (10.255.0.0/16)
- Ubuntu VM with dnsmasq (DNS server)
- Ubuntu VM (client)

## Expected Results

✅ Spoke VM resolves storage private endpoint to 10.1.1.x
✅ Spoke VM resolves public DNS (microsoft.com)
✅ On-prem client resolves storage via hub resolver
✅ On-prem client resolves public DNS via on-prem DNS

## Cost Estimate

~$0.41/hour or ~$10/day

Remember to run `teardown.ps1` when done!
