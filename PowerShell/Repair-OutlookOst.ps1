<#!
.SYNOPSIS
  Finds Outlook OST files and optionally renames them to trigger rebuild.

.DESCRIPTION
  Detects OST locations for a user profile, optionally closes Outlook, and
  when -Rebuild is specified, renames OST files to .bak (no deletion). Uses
  ShouldProcess for any changes.

.PARAMETER UserProfile
  Target user profile path. Defaults to current user's profile.

.PARAMETER Rebuild
  Rename OST files to .bak to force Outlook to rebuild.

.PARAMETER CloseOutlook
  Close Outlook before performing actions.

.EXAMPLE
  pwsh ./PowerShell/Repair-OutlookOst.ps1 -Verbose

.EXAMPLE
  pwsh ./PowerShell/Repair-OutlookOst.ps1 -UserProfile "C:\Users\jsmith" -CloseOutlook -Rebuild -Verbose

.NOTES
  PowerShell 5.1+ compatible. Writes a transcript to a user-writable folder.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$UserProfile = $env:USERPROFILE,
  [switch]$Rebuild,
  [switch]$CloseOutlook
)

$ErrorActionPreference = 'Stop'

$scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $env:TEMP ("{0}-{1}.log" -f $scriptName, $timestamp)
Start-Transcript -Path $logPath | Out-Null

$actions = New-Object System.Collections.Generic.List[object]
$warnings = New-Object System.Collections.Generic.List[string]

function Add-Action {
  param([string]$Action, [string]$Target, [string]$Result)
  $actions.Add([pscustomobject]@{
    Action = $Action
    Target = $Target
    Result = $Result
  }) | Out-Null
}

try {
  if (-not (Test-Path -LiteralPath $UserProfile)) {
    throw "UserProfile path not found: $UserProfile"
  }

  if ($CloseOutlook) {
    $outlook = Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue
    foreach ($p in $outlook) {
      if ($PSCmdlet.ShouldProcess($p.Name, 'Stop Outlook process')) {
        try {
          Stop-Process -Id $p.Id -Force -ErrorAction Stop
          Add-Action -Action 'Stop-Process' -Target $p.Name -Result 'Stopped'
        } catch {
          Add-Action -Action 'Stop-Process' -Target $p.Name -Result "Failed: $($_.Exception.Message)"
        }
      } else {
        Add-Action -Action 'Stop-Process' -Target $p.Name -Result 'WhatIf'
      }
    }
  }

  $ostRoots = @(
    Join-Path $UserProfile 'AppData\Local\Microsoft\Outlook',
    Join-Path $UserProfile 'AppData\Local\Microsoft\Office\16.0\Outlook'
  ) | Select-Object -Unique

  $ostFiles = @()
  foreach ($root in $ostRoots) {
    if (Test-Path -LiteralPath $root) {
      $ostFiles += Get-ChildItem -LiteralPath $root -Filter *.ost -File -ErrorAction SilentlyContinue
    }
  }

  if (-not $ostFiles) {
    $warnings.Add('No OST files found for the specified user profile.') | Out-Null
  }

  foreach ($f in $ostFiles) {
    if ($Rebuild) {
      $bak = "$($f.FullName).bak"
      if ($PSCmdlet.ShouldProcess($f.FullName, "Rename OST to $bak")) {
        try {
          Rename-Item -LiteralPath $f.FullName -NewName ($f.Name + '.bak') -ErrorAction Stop
          Add-Action -Action 'Rename-OST' -Target $f.FullName -Result "Renamed to $($f.Name).bak"
        } catch {
          Add-Action -Action 'Rename-OST' -Target $f.FullName -Result "Failed: $($_.Exception.Message)"
        }
      } else {
        Add-Action -Action 'Rename-OST' -Target $f.FullName -Result 'WhatIf'
      }
    } else {
      Add-Action -Action 'Detect-OST' -Target $f.FullName -Result 'Found'
    }
  }

  $summary = [pscustomobject]@{
    Script = $scriptName
    UserProfile = $UserProfile
    Rebuild = [bool]$Rebuild
    CloseOutlook = [bool]$CloseOutlook
    OstFiles = $ostFiles.FullName
    Actions = $actions
    Warnings = $warnings
    LogPath = $logPath
  }

  $summary
}
finally {
  Stop-Transcript | Out-Null
}
