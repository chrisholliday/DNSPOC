#Requires -Modules Az.Accounts, Az.Resources

<#
.SYNOPSIS
    Simplified teardown script for DNS POC
.DESCRIPTION
    Removes all resource groups created by the DNS POC
.PARAMETER Force
    Skip confirmation prompts
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Hardcoded resource group names
$resourceGroups = @(
    'dnspoc-rg-hub',
    'dnspoc-rg-spoke',
    'dnspoc-rg-onprem'
)

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "    ✓ $Message" -ForegroundColor Green
}

try {
    Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host '║                   DNS POC - TEARDOWN                              ║' -ForegroundColor Yellow
    Write-Host '╚═══════════════════════════════════════════════════════════════════╝' -ForegroundColor Yellow

    # Verify Azure connection
    Write-Step 'Verifying Azure connection'
    $context = Get-AzContext
    if (-not $context) {
        throw 'Not connected to Azure. Run Connect-AzAccount first.'
    }
    Write-Success "Connected as $($context.Account.Id)"
    
    # Check which resource groups exist
    Write-Step 'Checking for DNS POC resource groups'
    $existingRGs = @()
    foreach ($rgName in $resourceGroups) {
        $rg = Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue
        if ($rg) {
            $existingRGs += $rgName
            Write-Host "    • Found: $rgName" -ForegroundColor White
        }
        else {
            Write-Host "    • Not found: $rgName" -ForegroundColor Gray
        }
    }
    
    if ($existingRGs.Count -eq 0) {
        Write-Host "`nNo DNS POC resource groups found. Nothing to delete." -ForegroundColor Green
        return
    }
    
    # Confirm deletion
    if (-not $Force) {
        Write-Host "`nThe following resource groups will be DELETED:" -ForegroundColor Yellow
        foreach ($rgName in $existingRGs) {
            Write-Host "  • $rgName" -ForegroundColor Red
        }
        Write-Host "`nThis action cannot be undone!" -ForegroundColor Red
        $confirmation = Read-Host "`nType 'yes' to confirm deletion"
        if ($confirmation -ne 'yes') {
            Write-Host 'Deletion cancelled.' -ForegroundColor Yellow
            return
        }
    }
    
    # Delete resource groups
    Write-Step 'Deleting resource groups'
    foreach ($rgName in $existingRGs) {
        Write-Host "    Deleting $rgName..." -ForegroundColor Yellow
        Remove-AzResourceGroup -Name $rgName -Force | Out-Null
        Write-Success "Deleted $rgName"
    }
    
    Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host '║                    TEARDOWN COMPLETE                              ║' -ForegroundColor Green
    Write-Host '╚═══════════════════════════════════════════════════════════════════╝' -ForegroundColor Green
    
}
catch {
    Write-Host "`n✗ Teardown failed: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
