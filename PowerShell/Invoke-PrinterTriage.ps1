<#!
.SYNOPSIS
  Triage printer issues by collecting spooler/printer state and optional fixes.

.DESCRIPTION
  Gathers spooler status, installed printers, printer ports, and recent print-
  related event log entries. Optional actions include restarting the spooler
  and clearing the spool queue (with restart), all guarded by ShouldProcess.

.PARAMETER PrinterName
  Optional printer name filter when summarizing printers.

.PARAMETER RestartSpooler
  Restart the Print Spooler service.

.PARAMETER ClearQueue
  Clear spooler queue contents and restart spooler.

.EXAMPLE
  pwsh ./PowerShell/Invoke-PrinterTriage.ps1 -Verbose

.EXAMPLE
  pwsh ./PowerShell/Invoke-PrinterTriage.ps1 -ClearQueue -Verbose

.NOTES
  PowerShell 5.1+ compatible. Writes a transcript to a user-writable folder.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$PrinterName,
  [switch]$RestartSpooler,
  [switch]$ClearQueue
)

$ErrorActionPreference = 'Stop'

$IsWindowsHost = $true
if ($PSVersionTable.PSEdition -eq 'Core') {
  $IsWindowsHost = $IsWindows
} else {
  $IsWindowsHost = ($env:OS -eq 'Windows_NT')
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

try {
  if (-not $IsWindowsHost) {
    $warnings.Add('This script targets Windows endpoints; running in non-Windows mode will do discovery only.') | Out-Null
    return [pscustomobject]@{
      Script = $scriptName
      SpoolerStatus = $null
      Printers = @()
      Ports = @()
      RecentPrintEvents = @()
      Actions = $actions
      Warnings = $warnings
      LogPath = $logPath
    }
  }

  $spooler = $null
  if (Get-Command Get-Service -ErrorAction SilentlyContinue) {
    $spooler = Get-Service -Name Spooler -ErrorAction SilentlyContinue
  } else {
    $warnings.Add('Get-Service not available; skipping spooler status.') | Out-Null
  }

  $printers = @()
  $ports = @()
  try {
    if (Get-Command Get-Printer -ErrorAction SilentlyContinue) {
      $printers = Get-Printer -ErrorAction SilentlyContinue
    } else {
      $warnings.Add('Get-Printer not available; skipping printer list.') | Out-Null
    }
    if (Get-Command Get-PrinterPort -ErrorAction SilentlyContinue) {
      $ports = Get-PrinterPort -ErrorAction SilentlyContinue
    } else {
      $warnings.Add('Get-PrinterPort not available; skipping printer ports.') | Out-Null
    }
  } catch {
    $warnings.Add('Get-Printer or Get-PrinterPort failed. Printer cmdlets may be unavailable.') | Out-Null
  }

  if ($PrinterName) {
    $printers = $printers | Where-Object { $_.Name -like "*$PrinterName*" }
  }

  $printEvents = @()
  if (Get-Command Get-WinEvent -ErrorAction SilentlyContinue) {
    $since = (Get-Date).AddDays(-1)
    try {
      $printEvents = Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $since } -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderName -match 'Print' -or $_.Id -in 307, 805, 808, 842 }
    } catch {
      $warnings.Add('Failed to query print-related event logs.') | Out-Null
    }
  } else {
    $warnings.Add('Get-WinEvent not available; skipping event log query.') | Out-Null
  }

  if ($ClearQueue) {
    if ($env:WINDIR) {
      $spoolPath = Join-Path $env:WINDIR 'System32\spool\PRINTERS'
      if ($PSCmdlet.ShouldProcess($spoolPath, 'Clear spooler queue and restart spooler')) {
        try {
          if ($spooler -and $spooler.Status -ne 'Stopped' -and (Get-Command Stop-Service -ErrorAction SilentlyContinue)) {
            Stop-Service -Name Spooler -Force -ErrorAction Stop
            Add-Action -Action 'Stop-Service' -Target 'Spooler' -Result 'Stopped'
          }
          Get-ChildItem -LiteralPath $spoolPath -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
          Add-Action -Action 'Clear-Queue' -Target $spoolPath -Result 'Cleared'
          if (Get-Command Start-Service -ErrorAction SilentlyContinue) {
            Start-Service -Name Spooler -ErrorAction Stop
            Add-Action -Action 'Start-Service' -Target 'Spooler' -Result 'Started'
          }
        } catch {
          Add-Action -Action 'Clear-Queue' -Target $spoolPath -Result "Failed: $($_.Exception.Message)"
        }
      } else {
        Add-Action -Action 'Clear-Queue' -Target $spoolPath -Result 'WhatIf'
      }
    } else {
      $warnings.Add('WINDIR not set; skipping spooler queue clear.') | Out-Null
    }
  } elseif ($RestartSpooler) {
    if ($PSCmdlet.ShouldProcess('Spooler', 'Restart Print Spooler service')) {
      if (Get-Command Restart-Service -ErrorAction SilentlyContinue) {
        try {
          Restart-Service -Name Spooler -Force -ErrorAction Stop
          Add-Action -Action 'Restart-Service' -Target 'Spooler' -Result 'Restarted'
        } catch {
          Add-Action -Action 'Restart-Service' -Target 'Spooler' -Result "Failed: $($_.Exception.Message)"
        }
      } else {
        $warnings.Add('Restart-Service not available; skipping spooler restart.') | Out-Null
      }
    } else {
      Add-Action -Action 'Restart-Service' -Target 'Spooler' -Result 'WhatIf'
    }
  }

  [pscustomobject]@{
    Script = $scriptName
    SpoolerStatus = if ($spooler) { $spooler.Status } else { $null }
    Printers = $printers | Select-Object Name, DriverName, PortName, ShareName, Status
    Ports = $ports | Select-Object Name, PrinterHostAddress, PortNumber, Protocol
    RecentPrintEvents = $printEvents | Select-Object TimeCreated, Id, ProviderName, Message
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
