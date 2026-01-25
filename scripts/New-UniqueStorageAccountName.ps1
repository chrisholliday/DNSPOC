#Requires -Modules Az.Accounts, Az.Storage

<#
.SYNOPSIS
    Generates and validates a globally unique storage account name
.DESCRIPTION
    Creates a storage account name following the project naming convention and verifies it's available
.PARAMETER Prefix
    Prefix for the storage account name (default: dnspocsa)
.PARAMETER Suffix
    Suffix to identify the environment (default: spoke)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Prefix = 'dnspocsa',
    
    [Parameter(Mandatory = $false)]
    [string]$Suffix = 'spoke'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Test-StorageAccountNameAvailable {
    param([string]$Name)
    
    try {
        $result = Get-AzStorageAccountNameAvailability -Name $Name
        return $result.NameAvailable
    }
    catch {
        Write-Warning "Could not verify name availability. Please ensure you're logged in to Azure."
        return $false
    }
}

function New-UniqueStorageAccountName {
    param(
        [string]$Prefix,
        [string]$Suffix
    )
    
    # Storage account naming rules:
    # - 3-24 characters
    # - Lowercase letters and numbers only
    # - Must be globally unique
    
    $maxAttempts = 10
    $attempt = 0
    
    Write-Host "`nGenerating unique storage account name..." -ForegroundColor Cyan
    
    while ($attempt -lt $maxAttempts) {
        # Generate random 4-digit number
        $random = Get-Random -Minimum 1000 -Maximum 9999
        
        # Construct name: prefix + suffix + random
        $name = "$Prefix$Suffix$random".ToLower()
        
        # Validate length (3-24 characters)
        if ($name.Length -gt 24) {
            Write-Warning "Generated name '$name' is too long (max 24 characters). Try shorter prefix/suffix."
            return $null
        }
        
        if ($name.Length -lt 3) {
            Write-Warning "Generated name '$name' is too short (min 3 characters)."
            return $null
        }
        
        # Validate characters (only lowercase letters and numbers)
        if ($name -notmatch '^[a-z0-9]+$') {
            Write-Warning "Generated name '$name' contains invalid characters. Use only lowercase letters and numbers."
            return $null
        }
        
        Write-Host "  Checking: $name..." -ForegroundColor Gray -NoNewline
        
        # Check if available
        if (Test-StorageAccountNameAvailable -Name $name) {
            Write-Host ' ✓ Available!' -ForegroundColor Green
            return $name
        }
        else {
            Write-Host ' (taken)' -ForegroundColor Yellow
        }
        
        $attempt++
    }
    
    Write-Warning "Could not find an available name after $maxAttempts attempts."
    return $null
}

try {
    # Verify Azure connection
    $context = Get-AzContext
    if (-not $context) {
        Write-Host 'Not logged in to Azure. Please run Connect-AzAccount first.' -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Azure Subscription: $($context.Subscription.Name)" -ForegroundColor Cyan
    
    # Generate unique name
    $uniqueName = New-UniqueStorageAccountName -Prefix $Prefix -Suffix $Suffix
    
    if ($uniqueName) {
        Write-Host "`n✓ Generated unique storage account name:" -ForegroundColor Green
        Write-Host "  $uniqueName" -ForegroundColor White -BackgroundColor DarkGreen
        
        Write-Host "`nUpdate your config/config.json file:" -ForegroundColor Yellow
        Write-Host '  "storageAccountName": "' -NoNewline -ForegroundColor Gray
        Write-Host $uniqueName -NoNewline -ForegroundColor White
        Write-Host '",' -ForegroundColor Gray
        
        # Copy to clipboard if available
        try {
            Set-Clipboard -Value $uniqueName
            Write-Host "`n✓ Name copied to clipboard!" -ForegroundColor Green
        }
        catch {
            # Clipboard not available, that's okay
        }
    }
    else {
        Write-Host "`n✗ Failed to generate unique name. Try again or choose a different prefix/suffix." -ForegroundColor Red
        exit 1
    }
    
}
catch {
    Write-Host "✗ Error: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
