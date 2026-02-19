# Prompt Card: Diagnostics Bundle to Zip

## Purpose
Collect a diagnostics bundle (system info, event logs, network config, disk health) and compress it into a single zip for easy attachment to a ticket or handoff to L2/L3.

## Inputs (fill these in)
- Environment: (Win10 / Win11 / Server 2019 / Server 2022)
- Tooling context: (local pwsh, NinjaOne, Intune Remediation, etc.)
- Target: `<COMPUTERNAME>` (local or remote)
- Constraints: (admin required for event logs; read-only safe)

## Guardrails
- Do not include internal domains/hostnames/ticket numbers in examples.
- Prefer read-only validation first.
- Avoid destructive actions unless explicitly requested.
- Output must be copy/paste ready.
- Do not collect credentials, certificates, or registry hives containing secrets.
- Limit event log depth (e.g., last 24-48 hours) to keep zip size reasonable.

## What I want you to produce
1) PowerShell script (or function) with:
   - comment-based help
   - clear parameters (`ComputerName`, `OutputPath`, `HoursBack`)
   - try/catch + useful error messages per section (so one failure doesn't kill the whole bundle)
   - logging (Write-Host or Write-Verbose)
   - sections to collect:
     - `systeminfo` or `Get-ComputerInfo`
     - Event logs: System + Application (errors/warnings, last N hours)
     - `ipconfig /all`, `Get-NetAdapter`, `Get-NetIPConfiguration`
     - `Get-Volume` / disk free space
     - Installed hotfixes (`Get-HotFix`)
   - Compress all output into a single `.zip` using `Compress-Archive`
2) Brief "How to run" instructions
3) Validation checklist + rollback note (if applicable)

## Output format
- Script in a single code block
- Then instructions + checklist

## Validation checklist
- [ ] Script runs without error on target OS
- [ ] Zip file exists at expected path and is non-empty
- [ ] Each section file is present inside the zip
- [ ] No sensitive data (credentials, certs, PII) in output
- [ ] Event log entries are scoped to requested time window

## Rollback note
This script is read-only (no system changes). Delete the generated zip and temp folder to clean up.

## Example inputs
```powershell
# Local machine, last 24 hours, output to desktop
.\Get-DiagnosticsBundle.ps1 -ComputerName "YOURPC" -OutputPath "$env:USERPROFILE\Desktop" -HoursBack 24

# Remote machine via NinjaOne (stdout capture)
.\Get-DiagnosticsBundle.ps1 -ComputerName "YOURPC" -OutputPath "C:\Temp" -HoursBack 48
```
