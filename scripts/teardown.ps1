#Requires -Modules Az.Accounts, Az.Resources

<#
.SYNOPSIS
    Tears down all DNS POC infrastructure
.DESCRIPTION
    Removes all resource groups and associated resources for the DNS POC
.PARAMETER ConfigPath
    Path to the configuration JSON file
.PARAMETER Force
    Skip confirmation prompts
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "$PSScriptRoot/../config/config.json",
    
    [Parameter(Mandatory = $false)]
    [switch]$Force
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

function Write-ErrorMessage {
    param([string]$Message)
    Write-Host "    ✗ $Message" -ForegroundColor Red
}

function Write-Warning {
    param([string]$Message)
    Write-Host "    ⚠ $Message" -ForegroundColor Yellow
}

try {
    Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║                    DNS POC - TEARDOWN                             ║" -ForegroundColor Red
    Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Red

    # Load configuration
    Write-Step "Loading configuration"
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath"
    }
    $config = Get-Content $ConfigPath | ConvertFrom-Json
    Write-Success "Configuration loaded"

    # Ensure we're logged in to Azure
    Write-Step "Checking Azure connection"
    $context = Get-AzContext
    if (-not $context) {
        throw "Not logged in to Azure. Please run Connect-AzAccount first."
    }
    Write-Success "Connected to subscription: $($context.Subscription.Name)"

    # Get resource groups
    $resourceGroups = @(
        $config.resourceGroups.hub,
        $config.resourceGroups.spoke,
        $config.resourceGroups.onprem
    )

    # Check which resource groups exist
    Write-Step "Checking for existing resource groups"
    $existingRgs = @()
    foreach ($rgName in $resourceGroups) {
        $rg = Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue
        if ($rg) {
            $existingRgs += $rgName
            Write-Host "    Found: $rgName" -ForegroundColor Yellow
        }
    }

    if ($existingRgs.Count -eq 0) {
        Write-Success "No resource groups found. Nothing to delete."
        return
    }

    # Confirmation
    if (-not $Force) {
        Write-Host "`n⚠️  WARNING: This will DELETE the following resource groups and ALL resources within them:" -ForegroundColor Red
        foreach ($rgName in $existingRgs) {
            Write-Host "    - $rgName" -ForegroundColor Yellow
        }
        Write-Host "`nThis action CANNOT be undone!`n" -ForegroundColor Red
        
        $confirmation = Read-Host "Type 'DELETE' to confirm"
        if ($confirmation -ne 'DELETE') {
            Write-Host "`nTeardown cancelled." -ForegroundColor Yellow
            return
        }
    }

    # Delete resource groups
    Write-Step "Deleting resource groups (this may take several minutes)"
    
    $jobs = @()
    foreach ($rgName in $existingRgs) {
        Write-Host "    Starting deletion: $rgName" -ForegroundColor Yellow
        $job = Remove-AzResourceGroup -Name $rgName -Force -AsJob
        $jobs += @{
            Job = $job
            Name = $rgName
        }
    }

    # Wait for all deletions to complete
    Write-Host "`n    Waiting for deletions to complete..." -ForegroundColor Cyan
    foreach ($jobInfo in $jobs) {
        $job = $jobInfo.Job
        $rgName = $jobInfo.Name
        
        $job | Wait-Job | Out-Null
        
        if ($job.State -eq 'Completed') {
            Write-Success "Deleted: $rgName"
        } else {
            Write-ErrorMessage "Failed to delete: $rgName"
            Receive-Job -Job $job
        }
        
        Remove-Job -Job $job
    }

    # Clean up output files
    Write-Step "Cleaning up output files"
    $outputFiles = @(
        "$PSScriptRoot/../config/hub-outputs.json",
        "$PSScriptRoot/../config/spoke-outputs.json",
        "$PSScriptRoot/../config/onprem-outputs.json"
    )
    
    foreach ($file in $outputFiles) {
        if (Test-Path $file) {
            Remove-Item $file -Force
            Write-Success "Removed: $(Split-Path -Leaf $file)"
        }
    }

    Write-Host "`n✓ Teardown completed successfully!" -ForegroundColor Green
    Write-Host "All resources have been deleted." -ForegroundColor Green

} catch {
    Write-ErrorMessage "Teardown failed: $_"
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
