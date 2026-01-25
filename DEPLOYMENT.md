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

## Configuration

1. **Generate SSH Key Pair (Optional - will be prompted if missing)**

   The deployment will automatically check for an SSH key at `~/.ssh/dnspoc` and offer to generate one if needed.

   To pre-generate manually:

   ```powershell
   ./scripts/New-SSHKeyPair.ps1
   ```

2. **Edit `config/config.json`:**
   - Update `sshPublicKey` with your public key content (from `~/.ssh/dnspoc.pub`), or leave as `YOUR_SSH_PUBLIC_KEY_HERE` to be prompted during deployment
   - Leave `storageAccountName` empty (`""`) — a unique name will be auto-generated during the spoke deployment
   - Optionally change `location` for your preferred region

## Deployment

### Quick Start - Full Deployment

```powershell
# Deploy everything
./scripts/deploy-all.ps1
```

### Step-by-Step Deployment

```powershell
# 1. Deploy Hub (VNet, DNS Resolver, Private DNS Zones)
./scripts/deploy-hub.ps1

# 2. Deploy Spoke (VNet, VM, Storage with Private Endpoint)
./scripts/deploy-spoke.ps1

# 3. Deploy On-Prem Simulation (VNet, DNS Server, Client VM)
./scripts/deploy-onprem.ps1

# 4. Configure DNS Forwarding
./scripts/configure-dns-forwarding.ps1
```

### Partial Deployment

```powershell
# Skip already deployed components
./scripts/deploy-all.ps1 -SkipHub -SkipSpoke
```

## Testing

```powershell
# Get test instructions and VM connection info
./scripts/test-dns.ps1
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
│   ├── deploy-all.ps1          # Main orchestrator
│   ├── deploy-hub.ps1
│   ├── deploy-spoke.ps1
│   ├── deploy-onprem.ps1
│   ├── configure-dns-forwarding.ps1
│   ├── test-dns.ps1
│   └── teardown.ps1
├── config/                     # Configuration files
│   ├── config.json             # Main configuration
│   ├── README.md               # Config instructions
│   └── *-outputs.json          # Deployment outputs (generated)
└── Readme.md                   # Project overview
```

## Troubleshooting

### Deployment Fails

- Check Azure connection: `Get-AzContext`
- Verify configuration: Review `config/config.json`
- Check output files: `config/*-outputs.json`

### DNS Resolution Issues

- Verify DNS Private Resolver is running
- Check VNet peerings are in "Connected" state
- Validate Private DNS Zone links
- Review DNS forwarding ruleset configuration

### VM Connection Issues

VMs are deployed without public IPs for security. Options:

1. Add public IP temporarily via Azure Portal
2. Use Azure Bastion
3. Use Azure Serial Console

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

1. Run `test-dns.ps1` to get testing instructions
2. SSH to VMs and validate DNS resolution
3. Review Azure Portal for deployed resources
4. Run `teardown.ps1` when finished
