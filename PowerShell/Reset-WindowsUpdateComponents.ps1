<#!
.SYNOPSIS
  Resets Windows Update components with safe defaults.

.DESCRIPTION
  Stops Windows Update related services, renames SoftwareDistribution and
  Catroot2 folders, then restarts services. Optional Aggressive mode performs
  additional BITS cleanup. Optional DISM and SFC steps are clearly gated.

.PARAMETER Aggressive
  Additional cleanup such as BITS queue reset (still guarded by ShouldProcess).

.PARAMETER RunDISM
  Run DISM /RestoreHealth (can take time).

.PARAMETER RunSFC
  Run sfc /scannow (can take time).

.EXAMPLE
  pwsh ./PowerShell/Reset-WindowsUpdateComponents.ps1 -Verbose

.EXAMPLE
  pwsh ./PowerShell/Reset-WindowsUpdateComponents.ps1 -Aggressive -RunDISM -Verbose

.NOTES
  PowerShell 5.1+ compatible. Writes a transcript to a user-writable folder.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
  [switch]$Aggressive,
  [switch]$RunDISM,
  [switch]$RunSFC
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
      Aggressive = [bool]$Aggressive
      RunDISM = [bool]$RunDISM
      RunSFC = [bool]$RunSFC
      Actions = $actions
      Warnings = $warnings
      LogPath = $logPath
    }
  }

  $services = @('wuauserv', 'bits', 'cryptsvc', 'msiserver')

  foreach ($svc in $services) {
    if ($PSCmdlet.ShouldProcess($svc, 'Stop service')) {
      if (Get-Command Stop-Service -ErrorAction SilentlyContinue) {
        try {
          Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
          Add-Action -Action 'Stop-Service' -Target $svc -Result 'Stopped'
        } catch {
          Add-Action -Action 'Stop-Service' -Target $svc -Result "Failed: $($_.Exception.Message)"
        }
      } else {
        $warnings.Add('Stop-Service not available; skipping service stop.') | Out-Null
      }
    } else {
      Add-Action -Action 'Stop-Service' -Target $svc -Result 'WhatIf'
    }
  }

  if ($env:WINDIR) {
    $sd = Join-Path $env:WINDIR 'SoftwareDistribution'
    $cr = Join-Path $env:WINDIR 'System32\\catroot2'

    $sdNew = "$sd.old.$timestamp"
    $crNew = "$cr.old.$timestamp"

    if ($PSCmdlet.ShouldProcess($sd, "Rename to $sdNew")) {
      try {
        if (Test-Path -LiteralPath $sd) {
          Rename-Item -LiteralPath $sd -NewName (Split-Path -Leaf $sdNew) -ErrorAction Stop
          Add-Action -Action 'Rename-Path' -Target $sd -Result "Renamed to $sdNew"
        } else {
          Add-Action -Action 'Rename-Path' -Target $sd -Result 'NotFound'
        }
      } catch {
        Add-Action -Action 'Rename-Path' -Target $sd -Result "Failed: $($_.Exception.Message)"
      }
    } else {
      Add-Action -Action 'Rename-Path' -Target $sd -Result 'WhatIf'
    }

    if ($PSCmdlet.ShouldProcess($cr, "Rename to $crNew")) {
      try {
        if (Test-Path -LiteralPath $cr) {
          Rename-Item -LiteralPath $cr -NewName (Split-Path -Leaf $crNew) -ErrorAction Stop
          Add-Action -Action 'Rename-Path' -Target $cr -Result "Renamed to $crNew"
        } else {
          Add-Action -Action 'Rename-Path' -Target $cr -Result 'NotFound'
        }
      } catch {
        Add-Action -Action 'Rename-Path' -Target $cr -Result "Failed: $($_.Exception.Message)"
      }
    } else {
      Add-Action -Action 'Rename-Path' -Target $cr -Result 'WhatIf'
    }
  } else {
    $warnings.Add('WINDIR not set; skipping SoftwareDistribution/Catroot2 reset.') | Out-Null
  }

  if ($Aggressive) {
    if ($PSCmdlet.ShouldProcess('BITS', 'Reset BITS job queue')) {
      if (Get-Command bitsadmin -ErrorAction SilentlyContinue) {
        try {
          bitsadmin /reset /allusers | Out-Null
          Add-Action -Action 'BITS-Reset' -Target 'AllUsers' -Result 'Reset'
        } catch {
          Add-Action -Action 'BITS-Reset' -Target 'AllUsers' -Result "Failed: $($_.Exception.Message)"
        }
      } else {
        $warnings.Add('bitsadmin not available; skipping BITS reset.') | Out-Null
      }
    } else {
      Add-Action -Action 'BITS-Reset' -Target 'AllUsers' -Result 'WhatIf'
    }
  }

  foreach ($svc in $services) {
    if ($PSCmdlet.ShouldProcess($svc, 'Start service')) {
      if (Get-Command Start-Service -ErrorAction SilentlyContinue) {
        try {
          Start-Service -Name $svc -ErrorAction SilentlyContinue
          Add-Action -Action 'Start-Service' -Target $svc -Result 'Started'
        } catch {
          Add-Action -Action 'Start-Service' -Target $svc -Result "Failed: $($_.Exception.Message)"
        }
      } else {
        $warnings.Add('Start-Service not available; skipping service start.') | Out-Null
      }
    } else {
      Add-Action -Action 'Start-Service' -Target $svc -Result 'WhatIf'
    }
  }

  if ($RunDISM) {
    $warnings.Add('Running DISM /RestoreHealth can take time and requires admin.') | Out-Null
    if ($PSCmdlet.ShouldProcess('DISM', 'Run DISM /RestoreHealth')) {
      if (Get-Command dism -ErrorAction SilentlyContinue) {
        try {
          dism /Online /Cleanup-Image /RestoreHealth | Out-String | Out-Null
          Add-Action -Action 'DISM' -Target 'RestoreHealth' -Result 'Completed'
        } catch {
          Add-Action -Action 'DISM' -Target 'RestoreHealth' -Result "Failed: $($_.Exception.Message)"
        }
      } else {
        $warnings.Add('dism not available; skipping DISM run.') | Out-Null
      }
    } else {
      Add-Action -Action 'DISM' -Target 'RestoreHealth' -Result 'WhatIf'
    }
  }

  if ($RunSFC) {
    $warnings.Add('Running sfc /scannow can take time and requires admin.') | Out-Null
    if ($PSCmdlet.ShouldProcess('SFC', 'Run sfc /scannow')) {
      if (Get-Command sfc -ErrorAction SilentlyContinue) {
        try {
          sfc /scannow | Out-String | Out-Null
          Add-Action -Action 'SFC' -Target 'scannow' -Result 'Completed'
        } catch {
          Add-Action -Action 'SFC' -Target 'scannow' -Result "Failed: $($_.Exception.Message)"
        }
      } else {
        $warnings.Add('sfc not available; skipping SFC run.') | Out-Null
      }
    } else {
      Add-Action -Action 'SFC' -Target 'scannow' -Result 'WhatIf'
    }
  }

  [pscustomobject]@{
    Script = $scriptName
    Aggressive = [bool]$Aggressive
    RunDISM = [bool]$RunDISM
    RunSFC = [bool]$RunSFC
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
