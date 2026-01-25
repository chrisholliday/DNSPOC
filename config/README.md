# Configuration Instructions

## Before Deployment

1. **SSH Key**: Replace `YOUR_SSH_PUBLIC_KEY_HERE` in `config.json` with your actual SSH public key

   **Windows:**
   ```powershell
   ssh-keygen -t rsa -b 4096 -f "$env:USERPROFILE\.ssh\dnspoc"
   Get-Content "$env:USERPROFILE\.ssh\dnspoc.pub"
   ```

   **macOS / Linux:**
   ```powershell
   ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/dnspoc"
   Get-Content "$HOME/.ssh/dnspoc.pub"
   ```

2. **Storage Account Name**: Update `storageAccountName` in `config.json` to be globally unique
   - Must be 3-24 characters
   - Lowercase letters and numbers only
   - Must be globally unique across all of Azure

   **Helper Script** - Use this PowerShell script to generate and validate a unique name:

   ```powershell
   # Generate a unique name following the naming convention
   ../scripts/New-UniqueStorageAccountName.ps1
   
   # Or specify custom prefix/suffix
   ../scripts/New-UniqueStorageAccountName.ps1 -Prefix "dnspocsa" -Suffix "dev"
   ```

   The script will check availability and copy the name to your clipboard.

3. **Location**: Optionally change `location` if you prefer a different Azure region

## Configuration File Structure

- **envPrefix**: Naming prefix for all resources
- **location**: Azure region for deployment
- **adminUsername**: Linux VM admin username
- **sshPublicKey**: SSH public key for VM access
- **storageAccountName**: Globally unique storage account name
- **resourceGroups**: Names for hub, spoke, and on-prem resource groups
- **networking**: Address spaces and subnet configurations for all networks

## Deployment Outputs

After each deployment script runs, outputs are saved to:

- `hub-outputs.json` - Hub infrastructure details
- `spoke-outputs.json` - Spoke infrastructure details
- `onprem-outputs.json` - On-prem infrastructure details

These files are automatically used by subsequent deployment scripts.
