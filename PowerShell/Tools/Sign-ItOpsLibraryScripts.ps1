<#!
.SYNOPSIS
  Signs PowerShell scripts in this repository using a code-signing certificate.

.DESCRIPTION
  Finds .ps1 files under the specified path and applies Set-AuthenticodeSignature
  with the provided certificate thumbprint.

.PARAMETER Thumbprint
  The thumbprint of the code-signing certificate in the CurrentUser or LocalMachine store.

.PARAMETER Path
  Root path to scan for scripts. Defaults to the repo PowerShell folder.

.PARAMETER Recurse
  When set, include subfolders. Defaults to true.

.EXAMPLE
  pwsh ./PowerShell/Tools/Sign-ItOpsLibraryScripts.ps1 -Thumbprint "ABC123..."

.EXAMPLE
  pwsh ./PowerShell/Tools/Sign-ItOpsLibraryScripts.ps1 -Thumbprint "ABC123..." -Path ./PowerShell -Recurse

.NOTES
  PowerShell 5.1+ compatible. Windows-only.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [string]$Thumbprint,

  [string]$Path = (Join-Path $PSScriptRoot '..'),

  [switch]$Recurse = $true
)

$ErrorActionPreference = 'Stop'

if (-not $IsWindows) {
  Write-Warning 'This script is Windows-only. Code signing requires Windows certificate stores.'
  return
}

$cert = Get-ChildItem -Path Cert:\CurrentUser\My\$Thumbprint -ErrorAction SilentlyContinue
if (-not $cert) {
  $cert = Get-ChildItem -Path Cert:\LocalMachine\My\$Thumbprint -ErrorAction SilentlyContinue
}

if (-not $cert) {
  throw "Certificate not found for thumbprint: $Thumbprint"
}

$files = @()
if ($Recurse) {
  $files = Get-ChildItem -Path $Path -Filter *.ps1 -File -Recurse -ErrorAction Stop
} else {
  $files = Get-ChildItem -Path $Path -Filter *.ps1 -File -ErrorAction Stop
}

$results = foreach ($file in $files) {
  $sig = Set-AuthenticodeSignature -FilePath $file.FullName -Certificate $cert -ErrorAction SilentlyContinue
  [pscustomobject]@{
    File = $file.FullName
    Status = $sig.Status
    StatusMessage = $sig.StatusMessage
  }
}

$results | Format-Table -AutoSize
$results
