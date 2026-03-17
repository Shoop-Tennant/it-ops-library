<#!
.SYNOPSIS
  Clears Microsoft Teams cache for a user profile with safe defaults.

.DESCRIPTION
  Stops Teams processes (classic and new Teams), clears common cache folders,
  and optionally relaunches Teams. Designed for endpoint troubleshooting and
  supports -WhatIf via ShouldProcess for all changes.

.PARAMETER UserProfile
  Target user profile path. Defaults to the current user's profile.

.PARAMETER SkipRelaunch
  Do not relaunch Teams after clearing cache.

.EXAMPLE
  pwsh ./PowerShell/Clear-TeamsCache.ps1 -Verbose

.EXAMPLE
  pwsh ./PowerShell/Clear-TeamsCache.ps1 -UserProfile "C:\Users\jsmith" -SkipRelaunch -Verbose

.NOTES
  PowerShell 5.1+ compatible. Writes a transcript to a user-writable folder.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$UserProfile = $env:USERPROFILE,
  [switch]$SkipRelaunch
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

$cachePaths = @(
  (Join-PathParts -Base $UserProfile -Parts @('AppData', 'Roaming', 'Microsoft', 'Teams'))
  (Join-PathParts -Base $UserProfile -Parts @('AppData', 'Local', 'Microsoft', 'Teams'))
  (Join-PathParts -Base $UserProfile -Parts @('AppData', 'Local', 'Packages', 'MSTeams_8wekyb3d8bbwe', 'LocalCache'))
  (Join-PathParts -Base $UserProfile -Parts @('AppData', 'Local', 'Packages', 'MSTeams_8wekyb3d8bbwe', 'LocalState'))
  (Join-PathParts -Base $UserProfile -Parts @('AppData', 'Local', 'Packages', 'MicrosoftTeams_8wekyb3d8bbwe', 'LocalCache'))
  (Join-PathParts -Base $UserProfile -Parts @('AppData', 'Local', 'Packages', 'MicrosoftTeams_8wekyb3d8bbwe', 'LocalState'))
) | Select-Object -Unique

$classicExe = Join-PathParts -Base $UserProfile -Parts @('AppData', 'Local', 'Microsoft', 'Teams', 'current', 'Teams.exe')
$newExe = Join-PathParts -Base $UserProfile -Parts @('AppData', 'Local', 'Microsoft', 'WindowsApps', 'ms-teams.exe')

try {
  if (-not $IsWindowsHost) {
    $warnings.Add('This script targets Windows endpoints; running in non-Windows mode will do discovery only.') | Out-Null
    return [pscustomobject]@{
      Script = $scriptName
      UserProfile = $UserProfile
      SkipRelaunch = [bool]$SkipRelaunch
      CachePaths = $cachePaths
      TeamsExePaths = @($classicExe, $newExe)
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
      SkipRelaunch = [bool]$SkipRelaunch
      CachePaths = $cachePaths
      TeamsExePaths = @($classicExe, $newExe)
      Actions = $actions
      Warnings = $warnings
      LogPath = $logPath
    }
  }

  $teamsProcesses = @('Teams', 'ms-teams', 'TeamsClassic', 'TeamsBootstrapper', 'Teams.exe', 'ms-teams.exe')
  $running = @()
  if (Get-Command Get-Process -ErrorAction SilentlyContinue) {
    $running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $teamsProcesses -contains $_.Name }
  }

  foreach ($p in $running) {
    if ($PSCmdlet.ShouldProcess($p.Name, 'Stop Teams process')) {
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

  foreach ($path in $cachePaths) {
    if (Test-Path -LiteralPath $path) {
      if ($PSCmdlet.ShouldProcess($path, 'Remove Teams cache contents')) {
        try {
          Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction Stop
          Add-Action -Action 'Clear-Cache' -Target $path -Result 'Cleared'
        } catch {
          Add-Action -Action 'Clear-Cache' -Target $path -Result "Failed: $($_.Exception.Message)"
        }
      } else {
        Add-Action -Action 'Clear-Cache' -Target $path -Result 'WhatIf'
      }
    } else {
      Add-Action -Action 'Clear-Cache' -Target $path -Result 'NotFound'
    }
  }

  if (-not $SkipRelaunch) {
    if (Test-Path -LiteralPath $newExe) {
      if ($PSCmdlet.ShouldProcess($newExe, 'Start Teams (new)')) {
        try {
          Start-Process -FilePath $newExe -ErrorAction Stop | Out-Null
          Add-Action -Action 'Start-Process' -Target $newExe -Result 'Started'
        } catch {
          Add-Action -Action 'Start-Process' -Target $newExe -Result "Failed: $($_.Exception.Message)"
        }
      } else {
        Add-Action -Action 'Start-Process' -Target $newExe -Result 'WhatIf'
      }
    } elseif (Test-Path -LiteralPath $classicExe) {
      if ($PSCmdlet.ShouldProcess($classicExe, 'Start Teams (classic)')) {
        try {
          Start-Process -FilePath $classicExe -ErrorAction Stop | Out-Null
          Add-Action -Action 'Start-Process' -Target $classicExe -Result 'Started'
        } catch {
          Add-Action -Action 'Start-Process' -Target $classicExe -Result "Failed: $($_.Exception.Message)"
        }
      } else {
        Add-Action -Action 'Start-Process' -Target $classicExe -Result 'WhatIf'
      }
    } else {
      $warnings.Add('Teams executable not found for relaunch.') | Out-Null
    }
  }

  [pscustomobject]@{
    Script = $scriptName
    UserProfile = $UserProfile
    SkipRelaunch = [bool]$SkipRelaunch
    CachePaths = $cachePaths
    TeamsExePaths = @($classicExe, $newExe)
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
