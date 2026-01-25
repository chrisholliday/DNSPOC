#Requires -Modules Az.Accounts, Az.Network

<#
.SYNOPSIS
    Adds a public IP to a VM for SSH access
.DESCRIPTION
    Temporarily adds a public IP to a VM's NIC for testing/SSH access
.PARAMETER VMName
    Name of the VM
.PARAMETER ResourceGroupName
    Resource group containing the VM
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$VMName,
    
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "    ✓ $Message" -ForegroundColor Green
}

try {
    Write-Step "Getting VM information"
    $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName
    if (-not $vm) {
        throw "VM not found: $VMName"
    }
    Write-Success "Found VM: $VMName"
    
    Write-Step "Getting NIC information"
    $nicId = $vm.NetworkProfile.NetworkInterfaces[0].Id
    $nic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName | Where-Object { $_.Id -eq $nicId }
    Write-Success "Found NIC: $($nic.Name)"
    
    # Check if public IP already exists
    if ($nic.IpConfigurations[0].PublicIpAddress) {
        $existingPipId = $nic.IpConfigurations[0].PublicIpAddress.Id
        $existingPip = Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName | Where-Object { $_.Id -eq $existingPipId }
        Write-Success "VM already has public IP: $($existingPip.IpAddress)"
        Write-Host "`nSSH command:" -ForegroundColor Yellow
        Write-Host "  ssh azureuser@$($existingPip.IpAddress)" -ForegroundColor White
        return
    }
    
    Write-Step "Creating public IP address"
    $pipName = "$VMName-pip"
    $pip = New-AzPublicIpAddress `
        -Name $pipName `
        -ResourceGroupName $ResourceGroupName `
        -Location $vm.Location `
        -AllocationMethod Static `
        -Sku Standard
    Write-Success "Public IP created: $($pip.IpAddress)"
    
    Write-Step "Associating public IP with NIC"
    $nic.IpConfigurations[0].PublicIpAddress = $pip
    Set-AzNetworkInterface -NetworkInterface $nic | Out-Null
    Write-Success "Public IP associated"
    
    Write-Host "`n✓ Public IP successfully added!" -ForegroundColor Green
    Write-Host "`nConnection Information:" -ForegroundColor Cyan
    Write-Host "  VM Name: $VMName" -ForegroundColor White
    Write-Host "  Public IP: $($pip.IpAddress)" -ForegroundColor White
    Write-Host "  SSH Command: ssh azureuser@$($pip.IpAddress)" -ForegroundColor Yellow
    
    Write-Host "`nNote: Remember to remove the public IP when done:" -ForegroundColor Yellow
    Write-Host "  Remove-AzPublicIpAddress -Name $pipName -ResourceGroupName $ResourceGroupName -Force" -ForegroundColor Gray

} catch {
    Write-Host "✗ Failed: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
