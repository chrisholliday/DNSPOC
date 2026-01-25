#Requires -Version 5.1

<#
.SYNOPSIS
    Gets the proper SSH key path for the current platform
.DESCRIPTION
    Returns the correct SSH key path based on the operating system
.PARAMETER KeyName
    Name of the SSH key (default: dnspoc)
.OUTPUTS
    System.String - Full path to the SSH key
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$KeyName = 'dnspoc'
)

$ErrorActionPreference = 'Stop'

# Detect OS
if ($IsWindows -or ($PSVersionTable.PSVersion.Major -lt 6)) {
    # Windows PowerShell or Windows PowerShell Core
    $sshPath = Join-Path $env:USERPROFILE '.ssh' $KeyName
}
elseif ($IsMacOS -or $IsLinux) {
    # PowerShell on macOS or Linux
    $sshPath = Join-Path $HOME '.ssh' $KeyName
}
else {
    throw 'Unable to determine operating system'
}

Write-Output $sshPath
