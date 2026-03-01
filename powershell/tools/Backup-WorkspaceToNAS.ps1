#Requires -Version 5.1
<#
.SYNOPSIS
    Backs up local Workspace folders to a TrueNAS share via Robocopy.

.DESCRIPTION
    Mirrors Docs, Inbox, Tools, and Scratch to the NAS using Robocopy /MIR.
    Repos are excluded (GitHub is the backup). Secrets are excluded by policy.

    Source folders that do not exist on disk are skipped with a warning rather
    than causing the whole backup to fail.

.PARAMETER WorkspaceRoot
    Root of the local Workspace tree. Defaults to C:\Workspace.

.PARAMETER NasRoot
    UNC root of the backup share. Defaults to \\TRUENAS\jeremy\backups\Workspace.

.EXAMPLE
    .\Backup-WorkspaceToNAS.ps1
    Runs with default paths.

.EXAMPLE
    .\Backup-WorkspaceToNAS.ps1 -WhatIf
    Shows what would be mirrored without touching any files.

.NOTES
    Run via: ws-backup.cmd
    Tests:   Invoke-Pester ./powershell/tests/Backup-WorkspaceToNAS.Tests.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param (
    [string] $WorkspaceRoot = 'C:\Workspace',
    [string] $NasRoot       = '\\TRUENAS\jeremy\backups\Workspace'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-BackupTargets {
    <#
    .SYNOPSIS Returns the ordered list of folder names to back up.
    .NOTES Isolated as a function so tests can verify coverage without running robocopy.
    #>
    @('Docs', 'Inbox', 'Tools', 'Scratch')
}

function Invoke-WorkspaceBackup {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [string]   $WorkspaceRoot = 'C:\Workspace',
        [string]   $NasRoot       = '\\TRUENAS\jeremy\backups\Workspace',
        [string[]] $Targets       = (Get-BackupTargets)
    )

    foreach ($folder in $Targets) {
        $src  = Join-Path $WorkspaceRoot $folder
        $dest = Join-Path $NasRoot $folder

        if (-not (Test-Path -LiteralPath $src)) {
            Write-Warning "Source not found, skipping: $src"
            continue
        }

        New-Item -ItemType Directory -Force -Path $dest | Out-Null

        if ($PSCmdlet.ShouldProcess("$src -> $dest", 'robocopy /MIR')) {
            robocopy $src $dest /MIR /R:1 /W:1 /XJ
        }
    }
}

# Run automatically when invoked as a script; skipped when dot-sourced for testing.
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-WorkspaceBackup -WorkspaceRoot $WorkspaceRoot -NasRoot $NasRoot
}
