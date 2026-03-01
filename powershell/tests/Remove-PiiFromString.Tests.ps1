#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
.SYNOPSIS
    Pester tests for Remove-PiiFromString.

.DESCRIPTION
    Covers each redaction pattern individually, validates pipeline support and
    clean-input pass-through, and runs a fixture-based integration test against
    the synthetic samples in samples/sanitization/.

.NOTES
    Run from the repo root:
        Invoke-Pester ./powershell/tests/Remove-PiiFromString.Tests.ps1 -Output Detailed

    Requires Pester 5+. Install if missing:
        Install-Module Pester -Force -Scope CurrentUser
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '../functions/Remove-PiiFromString.ps1')
}

Describe 'Remove-PiiFromString' {

    Context 'Email addresses' {
        It 'Redacts a standard email address' {
            'Contact john.doe@example.com for help' | Remove-PiiFromString |
                Should -Be 'Contact [EMAIL] for help'
        }

        It 'Redacts an email with plus addressing' {
            'Reply-to: user+tag@example.org' | Remove-PiiFromString |
                Should -Be 'Reply-to: [EMAIL]'
        }
    }

    Context 'SSNs' {
        It 'Redacts a Social Security Number (XXX-XX-XXXX)' {
            'SSN on file: 123-45-6789' | Remove-PiiFromString |
                Should -Be 'SSN on file: [SSN]'
        }
    }

    Context 'Phone numbers' {
        It 'Redacts a dashed US phone number' {
            'Main line: 612-555-1234' | Remove-PiiFromString |
                Should -Be 'Main line: [PHONE]'
        }

        It 'Redacts a dotted US phone number' {
            'Main line: 612.555.1234' | Remove-PiiFromString |
                Should -Be 'Main line: [PHONE]'
        }
    }

    Context 'IPv4 addresses' {
        It 'Redacts an IPv4 address' {
            'Request from 10.22.33.44 blocked' | Remove-PiiFromString |
                Should -Be 'Request from [IP_ADDRESS] blocked'
        }
    }

    Context 'UNC paths' {
        It 'Redacts a UNC path' {
            'Export at \\server01\share\Exports\case123\export.txt' | Remove-PiiFromString |
                Should -Be 'Export at [UNC_PATH]'
        }
    }

    Context 'Windows device names' {
        It 'Redacts a standard device name (PREFIX-SITE-NNNN)' {
            'Device WS-NA-0042 checked in' | Remove-PiiFromString |
                Should -Be 'Device [DEVICE] checked in'
        }
    }

    Context 'Multiple patterns on one line' {
        It 'Redacts all patterns present simultaneously' {
            'Contact john.doe@example.com or call 612-555-1234' | Remove-PiiFromString |
                Should -Be 'Contact [EMAIL] or call [PHONE]'
        }

        It 'Redacts IP and device on the same line' {
            'User from 10.22.33.44 on device WS-NA-0042' | Remove-PiiFromString |
                Should -Be 'User from [IP_ADDRESS] on device [DEVICE]'
        }
    }

    Context 'Pipeline input' {
        It 'Processes multiple strings piped in sequence' {
            $results = 'hello@example.com', 'no pii here', '10.0.0.1' |
                Remove-PiiFromString

            $results[0] | Should -Be '[EMAIL]'
            $results[1] | Should -Be 'no pii here'
            $results[2] | Should -Be '[IP_ADDRESS]'
        }
    }

    Context 'Clean input' {
        It 'Returns the string unchanged when no PII is detected' {
            'No sensitive data in this line.' | Remove-PiiFromString |
                Should -Be 'No sensitive data in this line.'
        }

        It 'Returns an empty string unchanged' {
            '' | Remove-PiiFromString | Should -Be ''
        }
    }

    Context 'Fixture: samples/sanitization/' {
        It 'Matches input_sample.sanitized.txt line-for-line' {
            $inputPath    = Join-Path $PSScriptRoot '../../samples/sanitization/input_sample.txt'
            $expectedPath = Join-Path $PSScriptRoot '../../samples/sanitization/input_sample.sanitized.txt'

            $actual   = Get-Content -LiteralPath $inputPath    | Remove-PiiFromString
            $expected = Get-Content -LiteralPath $expectedPath

            $actual | Should -Be $expected
        }
    }
}
