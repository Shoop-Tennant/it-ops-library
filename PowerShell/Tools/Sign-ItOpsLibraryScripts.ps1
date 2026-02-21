<#
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

  [bool]$Recurse = $true
)

$ErrorActionPreference = 'Stop'

$IsWindowsHost = $true
if ($PSVersionTable.PSEdition -eq 'Core') {
  $IsWindowsHost = $IsWindows
} else {
  $IsWindowsHost = ($env:OS -eq 'Windows_NT')
}

if (-not $IsWindowsHost) {
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
  try {
    $sig = Set-AuthenticodeSignature -FilePath $file.FullName -Certificate $cert -ErrorAction Stop
    [pscustomobject]@{
      File = $file.FullName
      Status = $sig.Status
      StatusMessage = $sig.StatusMessage
      Error = $null
    }
  } catch {
    [pscustomobject]@{
      File = $file.FullName
      Status = 'Error'
      StatusMessage = 'Failed to sign file'
      Error = $_.Exception.Message
    }
  }
}

$results | Format-Table -AutoSize
$results
