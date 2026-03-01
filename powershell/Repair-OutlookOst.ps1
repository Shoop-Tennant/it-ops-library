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

$IsWindowsHost = $true
if ($PSVersionTable.PSEdition -eq 'Core') {
  $IsWindowsHost = $IsWindows
} else {
  $IsWindowsHost = ($env:OS -eq 'Windows_NT')
}

if (-not $UserProfile -or $UserProfile.Trim() -eq '') {
  $UserProfile = $HOME
}
if (-not $UserProfile -or $UserProfile.Trim() -eq '') {
  $UserProfile = [IO.Path]::GetTempPath()
}
$UserProfile = [string]$UserProfile

function Join-PathParts {
  param(
    [Parameter(Mandatory)][string]$Base,
    [Parameter(Mandatory)][string[]]$Parts
  )
  $segments = @($Base) + @($Parts) | Where-Object { $_ -and $_.Trim() }
  [System.IO.Path]::Combine([string[]]$segments)
}

$scriptName = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$TempRoot = @($env:TEMP, $env:TMP, [IO.Path]::GetTempPath()) | Where-Object { $_ -and $_.Trim() } | Select-Object -First 1
$null = New-Item -ItemType Directory -Path $TempRoot -Force
$logPath = Join-Path $TempRoot ("{0}-{1}.log" -f $scriptName, $timestamp)

$TranscriptStarted = $false
if ((Get-Command Start-Transcript -ErrorAction SilentlyContinue) -and ($WhatIfPreference -eq $false)) {
  Start-Transcript -Path $logPath | Out-Null
  $TranscriptStarted = $true
}

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

$ostRoots = @(
  (Join-PathParts -Base $UserProfile -Parts @('AppData', 'Local', 'Microsoft', 'Outlook'))
  (Join-PathParts -Base $UserProfile -Parts @('AppData', 'Local', 'Microsoft', 'Office', '16.0', 'Outlook'))
) | Select-Object -Unique

try {
  if (-not $IsWindowsHost) {
    $warnings.Add('This script targets Windows endpoints; running in non-Windows mode will do discovery only.') | Out-Null
    return [pscustomobject]@{
      Script = $scriptName
      UserProfile = $UserProfile
      Rebuild = [bool]$Rebuild
      CloseOutlook = [bool]$CloseOutlook
      OstRoots = $ostRoots
      OstFiles = @()
      Actions = $actions
      Warnings = $warnings
      LogPath = $logPath
    }
  }

  if (-not $UserProfile -or -not (Test-Path -LiteralPath $UserProfile)) {
    $warnings.Add("UserProfile path not found: $UserProfile") | Out-Null
    return [pscustomobject]@{
      Script = $scriptName
      UserProfile = $UserProfile
      Rebuild = [bool]$Rebuild
      CloseOutlook = [bool]$CloseOutlook
      OstRoots = $ostRoots
      OstFiles = @()
      Actions = $actions
      Warnings = $warnings
      LogPath = $logPath
    }
  }

  if ($CloseOutlook -and (Get-Command Get-Process -ErrorAction SilentlyContinue)) {
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

  [pscustomobject]@{
    Script = $scriptName
    UserProfile = $UserProfile
    Rebuild = [bool]$Rebuild
    CloseOutlook = [bool]$CloseOutlook
    OstRoots = $ostRoots
    OstFiles = $ostFiles.FullName
    Actions = $actions
    Warnings = $warnings
    LogPath = $logPath
  }
}
finally {
  if ($TranscriptStarted -and (Get-Command Stop-Transcript -ErrorAction SilentlyContinue)) {
    Stop-Transcript | Out-Null
  }
}
