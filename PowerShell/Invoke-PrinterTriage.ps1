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
  $spooler = Get-Service -Name Spooler -ErrorAction SilentlyContinue

  $printers = @()
  $ports = @()
  try {
    $printers = Get-Printer -ErrorAction SilentlyContinue
    $ports = Get-PrinterPort -ErrorAction SilentlyContinue
  } catch {
    $warnings.Add('Get-Printer or Get-PrinterPort failed. Printer cmdlets may be unavailable.') | Out-Null
  }

  if ($PrinterName) {
    $printers = $printers | Where-Object { $_.Name -like "*$PrinterName*" }
  }

  $since = (Get-Date).AddDays(-1)
  $printEvents = @()
  try {
    $printEvents = Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $since } -ErrorAction SilentlyContinue |
      Where-Object { $_.ProviderName -match 'Print' -or $_.Id -in 307, 805, 808, 842 }
  } catch {
    $warnings.Add('Failed to query print-related event logs.') | Out-Null
  }

  if ($ClearQueue) {
    $spoolPath = Join-Path $env:WINDIR 'System32\spool\PRINTERS'
    if ($PSCmdlet.ShouldProcess($spoolPath, 'Clear spooler queue and restart spooler')) {
      try {
        if ($spooler.Status -ne 'Stopped') {
          Stop-Service -Name Spooler -Force -ErrorAction Stop
          Add-Action -Action 'Stop-Service' -Target 'Spooler' -Result 'Stopped'
        }
        Get-ChildItem -LiteralPath $spoolPath -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Add-Action -Action 'Clear-Queue' -Target $spoolPath -Result 'Cleared'
        Start-Service -Name Spooler -ErrorAction Stop
        Add-Action -Action 'Start-Service' -Target 'Spooler' -Result 'Started'
      } catch {
        Add-Action -Action 'Clear-Queue' -Target $spoolPath -Result "Failed: $($_.Exception.Message)"
      }
    } else {
      Add-Action -Action 'Clear-Queue' -Target $spoolPath -Result 'WhatIf'
    }
  } elseif ($RestartSpooler) {
    if ($PSCmdlet.ShouldProcess('Spooler', 'Restart Print Spooler service')) {
      try {
        Restart-Service -Name Spooler -Force -ErrorAction Stop
        Add-Action -Action 'Restart-Service' -Target 'Spooler' -Result 'Restarted'
      } catch {
        Add-Action -Action 'Restart-Service' -Target 'Spooler' -Result "Failed: $($_.Exception.Message)"
      }
    } else {
      Add-Action -Action 'Restart-Service' -Target 'Spooler' -Result 'WhatIf'
    }
  }

  $summary = [pscustomobject]@{
    Script = $scriptName
    SpoolerStatus = $spooler.Status
    Printers = $printers | Select-Object Name, DriverName, PortName, ShareName, Status
    Ports = $ports | Select-Object Name, PrinterHostAddress, PortNumber, Protocol
    RecentPrintEvents = $printEvents | Select-Object TimeCreated, Id, ProviderName, Message
    Actions = $actions
    Warnings = $warnings
    LogPath = $logPath
  }

  $summary
}
finally {
  Stop-Transcript | Out-Null
}
