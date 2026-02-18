<#
.SYNOPSIS
  Sanitizes a text-based file by redacting common PII patterns.

.DESCRIPTION
  Reads a file line-by-line, redacts common PII using Remove-PiiFromString,
  writes a sanitized copy, and prints a summary of redactions.

  Supported: .txt, .log, .md, .csv (anything line-oriented)

.EXAMPLE
  pwsh ./PowerShell/Tools/Sanitize-File.ps1 -Path ./export.txt

.EXAMPLE
  pwsh ./PowerShell/Tools/Sanitize-File.ps1 -Path ./export.txt -OutPath ./export.sanitized.txt
#>

[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)]
  [string]$Path,

  [string]$OutPath
)

$ErrorActionPreference = 'Stop'

$inFile = Resolve-Path -LiteralPath $Path

if (-not $OutPath -or [string]::IsNullOrWhiteSpace($OutPath)) {
  $dir  = Split-Path -Parent $inFile
  $base = [IO.Path]::GetFileNameWithoutExtension($inFile)
  $ext  = [IO.Path]::GetExtension($inFile)
  if (-not $ext) { $ext = '.txt' }
  $OutPath = Join-Path $dir ("{0}.sanitized{1}" -f $base, $ext)
}

$outFile = $OutPath

# Dot-source the function
$fnPath = Join-Path $PSScriptRoot '../Functions/Remove-PiiFromString.ps1'
$fnPath = Resolve-Path -LiteralPath $fnPath
. $fnPath

# Patterns for counting (kept roughly aligned with Remove-PiiFromString)
$patterns = [ordered]@{
  EMAIL      = '[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}'
  SSN        = '\b\d{3}-\d{2}-\d{4}\b'
  PHONE      = '\b(\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b'
  IP_ADDRESS = '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'
  UNC_PATH   = '\\\\[A-Za-z0-9._\-]+\\[A-Za-z0-9$._\-\\]+'
  DEVICE     = '\b[A-Z]{2,6}-[A-Z]{0,4}-?\d{3,6}\b'
}

$counts = [ordered]@{}
foreach ($k in $patterns.Keys) { $counts[$k] = 0 }

$lineCount = 0

if ($PSCmdlet.ShouldProcess($outFile, "Write sanitized output")) {
  $writer = New-Object System.IO.StreamWriter($outFile, $false, [System.Text.Encoding]::UTF8)
  try {
    Get-Content -LiteralPath $inFile -ReadCount 500 | ForEach-Object {
      foreach ($line in $_) {
        $lineCount++

        foreach ($k in $patterns.Keys) {
          $counts[$k] += ([regex]::Matches($line, $patterns[$k])).Count
        }

        $sanitized = $line | Remove-PiiFromString
        $writer.WriteLine($sanitized)
      }
    }
  }
  finally {
    $writer.Flush()
    $writer.Dispose()
  }

  Write-Host ""
  Write-Host "Sanitize-File complete:"
  Write-Host "  Input : $inFile"
  Write-Host "  Output: $outFile"
  Write-Host "  Lines : $lineCount"
  Write-Host "  Redactions:"
  foreach ($k in $counts.Keys) {
    Write-Host ("    {0,-10} {1}" -f $k, $counts[$k])
  }
}
