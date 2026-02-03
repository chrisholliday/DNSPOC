# DNS POC - Deployment Guide

## Prerequisites

1. **Azure PowerShell Module**

   ```powershell
   Install-Module -Name Az -Repository PSGallery -Force
   ```

2. **Azure Account**

   ```powershell
   Connect-AzAccount
   Set-AzContext -SubscriptionId "your-subscription-id"
   ```

3. **SSH Command-line Tool**
   - Windows: Included with PowerShell 7.1+ or Git for Windows
   - macOS / Linux: Pre-installed with OpenSSH

## Deployment

This project uses a **staged deployment** to avoid cloud-init DNS bootstrap issues on the on-prem DNS server VM.

### Stage 1: Hub + Spoke

```powershell
# Generate SSH key if needed
ssh-keygen -t rsa -b 4096 -f ~/.ssh/dnspoc

# Deploy hub and spoke infrastructure
$sshKey = Get-Content ~/.ssh/dnspoc.pub
./scripts/01-deploy-hub-spoke.ps1 -SSHPublicKey $sshKey

# Optional: override location (defaults to centralus)
./scripts/01-deploy-hub-spoke.ps1 -SSHPublicKey $sshKey -Location "eastus"
```

### Stage 2: On-Prem Infrastructure (Azure Default DNS)

```powershell
./scripts/02-deploy-onprem.ps1
```

### Stage 3: Switch On-Prem VNet DNS to the On-Prem DNS Server

```powershell
./scripts/03-configure-onprem-dns.ps1
```

## Validation

After deployment completes, validate DNS resolution using the test helper and the testing guide:

```powershell
# Get VM connection info and test commands
./scripts/test.ps1
```

See [TESTING-GUIDE.md](TESTING-GUIDE.md) for comprehensive test scenarios.

## Testing

```powershell
# Get test instructions and VM connection info
./scripts/test.ps1
```

## Cleanup

```powershell
# Remove all resources
./scripts/teardown.ps1

# Skip confirmation prompt
./scripts/teardown.ps1 -Force
```

## Project Structure

```text
DNSPOC/
├── bicep/                      # Main Bicep templates
│   ├── hub.bicep               # Hub network deployment
│   ├── spoke.bicep             # Spoke network deployment
│   ├── onprem.bicep            # On-prem simulation
│   └── dns-forwarding-ruleset.bicep
├── modules/                    # Reusable Bicep modules
│   ├── vnet.bicep
│   ├── nsg.bicep
│   ├── vm.bicep
│   ├── dns-resolver.bicep
│   ├── private-dns-zone.bicep
│   ├── storage-private-endpoint.bicep
│   ├── vnet-peering.bicep
│   └── dns-forwarding-ruleset.bicep
├── scripts/                    # PowerShell deployment scripts
│   ├── 01-deploy-hub-spoke.ps1  # Stage 1: hub + spoke
│   ├── 02-deploy-onprem.ps1
│   ├── 03-configure-onprem-dns.ps1
│   ├── test.ps1
│   ├── teardown.ps1
│   └── add-public-ip.ps1
└── Readme.md                   # Project overview
```

## Troubleshooting

### Deployment Fails

- Check Azure connection: `Get-AzContext`
- Re-run Stage 1 to recreate hub + spoke outputs
- Confirm on-prem deployment uses Stage 2 before Stage 3

### DNS Resolution Issues

- Verify DNS Private Resolver is running
- Check VNet peerings are in "Connected" state
- Validate Private DNS Zone links
- Review DNS forwarding ruleset configuration

### VM Connection Issues

VMs are deployed without public IPs for security. Options:

1. **Add public IP temporarily** (for testing)

   ```powershell
   ./scripts/add-public-ip.ps1 -VMName "dnspoc-vm-spoke-dev" -ResourceGroupName "dnspoc-rg-spoke"
   ssh -i ~/.ssh/dnspoc azureuser@<public-ip>
   ```

2. **Use Azure Bastion** (recommended for secure access)
   - Deploy Azure Bastion to the hub VNet
   - Connect through Azure Portal: VM → Connect → Bastion
   - No public IPs needed, no SSH keys required in browser
   - See [Azure Bastion documentation](https://learn.microsoft.com/azure/bastion/bastion-overview)

3. **Use Azure Serial Console** (for emergency access)
   - Requires no network connectivity
   - Access through Azure Portal: VM → Serial console

## Estimated Costs

Based on East US pricing (approximate):

- DNS Private Resolver: ~$0.30/hour
- VMs (3x Standard_B1s, 1x Standard_B2s): ~$0.10/hour
- Storage Account: < $0.01/hour
- VNet Peerings: Data transfer charges only

**Total: ~$0.41/hour or ~$10/day**

## Duration

- Full deployment: 15-20 minutes
- Teardown: 5-10 minutes

## Next Steps

After deployment:

1. Run `scripts/test.ps1` to get testing instructions
2. SSH to VMs and validate DNS resolution
3. Review Azure Portal for deployed resources
4. Run `scripts/teardown.ps1` when finished
