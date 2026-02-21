<#!
.SYNOPSIS
  Collects a lightweight diagnostics bundle and zips it to a target path.

.DESCRIPTION
  Gathers system info, network configuration, dsregcmd status, installed apps
  summary, and Windows Update logs summary where feasible. Optionally exports
  System and Application event logs filtered to the last N days.

.PARAMETER OutputPath
  Destination folder or full zip path. Defaults to $env:TEMP.

.PARAMETER IncludeEventLogs
  Export System and Application event logs for the last N days.

.PARAMETER Days
  Number of days back for event log filtering. Default is 3.

.EXAMPLE
  pwsh ./PowerShell/Get-DiagnosticsBundle.ps1 -Verbose

.EXAMPLE
  pwsh ./PowerShell/Get-DiagnosticsBundle.ps1 -OutputPath C:\Temp -IncludeEventLogs -Days 7 -Verbose

.NOTES
  PowerShell 5.1+ compatible. Writes a transcript to a user-writable folder.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$OutputPath,
  [switch]$IncludeEventLogs,
  [int]$Days = 3
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
      ComputerName = $env:COMPUTERNAME
      TempFolder = $TempRoot
      ZipPath = $null
      IncludeEventLogs = [bool]$IncludeEventLogs
      Days = $Days
      Actions = $actions
      Warnings = $warnings
      LogPath = $logPath
    }
  }

  $computer = $env:COMPUTERNAME
  $bundleName = "DiagnosticsBundle-{0}-{1}" -f $computer, $timestamp
  $bundleRoot = Join-Path $TempRoot $bundleName
  $null = New-Item -ItemType Directory -Path $bundleRoot -Force

  if (-not $OutputPath) {
    $OutputPath = $TempRoot
  }

  $zipPath = $OutputPath
  if (-not $zipPath.EndsWith('.zip')) {
    $zipPath = Join-Path $OutputPath ("{0}.zip" -f $bundleName)
  }

  $files = @(
    @{ Name = 'systeminfo.txt'; Command = { systeminfo } },
    @{ Name = 'ipconfig_all.txt'; Command = { ipconfig /all } },
    @{ Name = 'route_print.txt'; Command = { route print } },
    @{ Name = 'winsock_show.txt'; Command = { netsh winsock show catalog } },
    @{ Name = 'dsregcmd_status.txt'; Command = { dsregcmd /status } }
  )

  foreach ($f in $files) {
    $outFile = Join-Path $bundleRoot $f.Name
    if ($PSCmdlet.ShouldProcess($outFile, 'Write diagnostics output')) {
      try {
        & $f.Command | Out-File -FilePath $outFile -Encoding UTF8
        Add-Action -Action 'Collect' -Target $outFile -Result 'Written'
      } catch {
        Add-Action -Action 'Collect' -Target $outFile -Result "Failed: $($_.Exception.Message)"
      }
    } else {
      Add-Action -Action 'Collect' -Target $outFile -Result 'WhatIf'
    }
  }

  # Installed apps summary (lightweight)
  $appsOut = Join-Path $bundleRoot 'installed_apps.txt'
  if ($PSCmdlet.ShouldProcess($appsOut, 'Write installed apps summary')) {
    try {
      $apps = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
        Where-Object { $_.DisplayName } |
        Sort-Object DisplayName

      $apps += Get-ItemProperty "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
        Where-Object { $_.DisplayName } |
        Sort-Object DisplayName

      $apps | Format-Table -AutoSize | Out-String | Out-File -FilePath $appsOut -Encoding UTF8
      Add-Action -Action 'Collect' -Target $appsOut -Result 'Written'
    } catch {
      Add-Action -Action 'Collect' -Target $appsOut -Result "Failed: $($_.Exception.Message)"
    }
  } else {
    Add-Action -Action 'Collect' -Target $appsOut -Result 'WhatIf'
  }

  # Windows Update logs summary where feasible
  $wuOut = Join-Path $bundleRoot 'windows_update_summary.txt'
  if ($PSCmdlet.ShouldProcess($wuOut, 'Write Windows Update summary')) {
    try {
      $wuSummary = New-Object System.Collections.Generic.List[string]
      $wuSummary.Add('Windows Update summary:') | Out-Null

      $wuLog = Join-Path $env:WINDIR 'WindowsUpdate.log'
      if ($wuLog -and (Test-Path -LiteralPath $wuLog)) {
        $wuSummary.Add("WindowsUpdate.log exists at $wuLog") | Out-Null
        Get-Content -LiteralPath $wuLog -Tail 200 | Out-File -FilePath $wuOut -Encoding UTF8
      } else {
        $wuSummary.Add('WindowsUpdate.log not found (expected on some systems).') | Out-Null
        $wuSummary | Out-File -FilePath $wuOut -Encoding UTF8
      }
      Add-Action -Action 'Collect' -Target $wuOut -Result 'Written'
    } catch {
      Add-Action -Action 'Collect' -Target $wuOut -Result "Failed: $($_.Exception.Message)"
    }
  } else {
    Add-Action -Action 'Collect' -Target $wuOut -Result 'WhatIf'
  }

  if ($IncludeEventLogs) {
    if (Get-Command wevtutil -ErrorAction SilentlyContinue) {
      $since = (Get-Date).AddDays(-[math]::Abs($Days))
      $systemEvtx = Join-Path $bundleRoot 'System.evtx'
      $appEvtx = Join-Path $bundleRoot 'Application.evtx'

      if ($PSCmdlet.ShouldProcess($systemEvtx, 'Export System event log')) {
        try {
          $q = "*[System[TimeCreated[timediff(@SystemTime) <= {0}]]]" -f ([int]((Get-Date) - $since).TotalMilliseconds)
          wevtutil epl System $systemEvtx /q:$q
          Add-Action -Action 'Export-EventLog' -Target $systemEvtx -Result 'Written'
        } catch {
          Add-Action -Action 'Export-EventLog' -Target $systemEvtx -Result "Failed: $($_.Exception.Message)"
        }
      } else {
        Add-Action -Action 'Export-EventLog' -Target $systemEvtx -Result 'WhatIf'
      }

      if ($PSCmdlet.ShouldProcess($appEvtx, 'Export Application event log')) {
        try {
          $q = "*[System[TimeCreated[timediff(@SystemTime) <= {0}]]]" -f ([int]((Get-Date) - $since).TotalMilliseconds)
          wevtutil epl Application $appEvtx /q:$q
          Add-Action -Action 'Export-EventLog' -Target $appEvtx -Result 'Written'
        } catch {
          Add-Action -Action 'Export-EventLog' -Target $appEvtx -Result "Failed: $($_.Exception.Message)"
        }
      } else {
        Add-Action -Action 'Export-EventLog' -Target $appEvtx -Result 'WhatIf'
      }
    } else {
      $warnings.Add('wevtutil not found; skipping event log export.') | Out-Null
    }
  }

  if ($PSCmdlet.ShouldProcess($zipPath, 'Create diagnostics bundle zip')) {
    try {
      if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
      }
      Add-Type -AssemblyName System.IO.Compression.FileSystem
      [System.IO.Compression.ZipFile]::CreateFromDirectory($bundleRoot, $zipPath)
      Add-Action -Action 'Zip' -Target $zipPath -Result 'Created'
    } catch {
      Add-Action -Action 'Zip' -Target $zipPath -Result "Failed: $($_.Exception.Message)"
    }
  } else {
    Add-Action -Action 'Zip' -Target $zipPath -Result 'WhatIf'
  }

  [pscustomobject]@{
    Script = $scriptName
    ComputerName = $computer
    TempFolder = $bundleRoot
    ZipPath = $zipPath
    IncludeEventLogs = [bool]$IncludeEventLogs
    Days = $Days
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
