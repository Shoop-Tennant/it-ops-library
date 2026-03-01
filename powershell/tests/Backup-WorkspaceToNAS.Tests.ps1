#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
.SYNOPSIS
    Pester tests for Backup-WorkspaceToNAS.

.NOTES
    Run from the repo root:
        Invoke-Pester ./powershell/tests/Backup-WorkspaceToNAS.Tests.ps1 -Output Detailed

    Requires Pester 5+. Install if missing:
        Install-Module Pester -Force -Scope CurrentUser
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '../tools/Backup-WorkspaceToNAS.ps1')
}

Describe 'Get-BackupTargets' {

    It 'Returns exactly four targets' {
        Get-BackupTargets | Should -HaveCount 4
    }

    It 'Includes Docs' {
        Get-BackupTargets | Should -Contain 'Docs'
    }

    It 'Includes Inbox' {
        Get-BackupTargets | Should -Contain 'Inbox'
    }

    It 'Includes Tools' {
        Get-BackupTargets | Should -Contain 'Tools'
    }

    It 'Includes Scratch' {
        Get-BackupTargets | Should -Contain 'Scratch'
    }
}

Describe 'Invoke-WorkspaceBackup' {

    BeforeEach {
        Mock Test-Path  { $true }
        Mock New-Item   {}
        Mock robocopy   {}
    }

    It 'Calls robocopy once per target when all sources exist' {
        Invoke-WorkspaceBackup -WorkspaceRoot 'C:\FakeWorkspace' -NasRoot '\\NAS\backup' `
            -Targets @('Docs', 'Inbox', 'Tools', 'Scratch')

        Should -Invoke robocopy -Exactly 4 -Scope It
    }

    It 'Passes the correct source path to robocopy' {
        Invoke-WorkspaceBackup -WorkspaceRoot 'C:\FakeWorkspace' -NasRoot '\\NAS\backup' `
            -Targets @('Tools')

        Should -Invoke robocopy -Exactly 1 -Scope It -ParameterFilter {
            $args[0] -eq 'C:\FakeWorkspace\Tools'
        }
    }

    It 'Passes the correct destination path to robocopy' {
        Invoke-WorkspaceBackup -WorkspaceRoot 'C:\FakeWorkspace' -NasRoot '\\NAS\backup' `
            -Targets @('Scratch')

        Should -Invoke robocopy -Exactly 1 -Scope It -ParameterFilter {
            $args[1] -eq '\\NAS\backup\Scratch'
        }
    }

    It 'Creates the destination directory before calling robocopy' {
        Invoke-WorkspaceBackup -WorkspaceRoot 'C:\FakeWorkspace' -NasRoot '\\NAS\backup' `
            -Targets @('Docs')

        Should -Invoke New-Item -Exactly 1 -Scope It -ParameterFilter {
            $Path -eq '\\NAS\backup\Docs'
        }
    }

    It 'Skips a target and warns when source does not exist' {
        Mock Test-Path { $false }

        { Invoke-WorkspaceBackup -WorkspaceRoot 'C:\FakeWorkspace' -NasRoot '\\NAS\backup' `
            -Targets @('Docs') -WarningAction SilentlyContinue } | Should -Not -Throw

        Should -Invoke robocopy -Exactly 0 -Scope It
    }

    It 'Does not call robocopy when -WhatIf is specified' {
        Invoke-WorkspaceBackup -WorkspaceRoot 'C:\FakeWorkspace' -NasRoot '\\NAS\backup' `
            -Targets @('Docs', 'Inbox', 'Tools', 'Scratch') -WhatIf

        Should -Invoke robocopy -Exactly 0 -Scope It
    }
}
