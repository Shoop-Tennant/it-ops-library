# Prompt Card: Reset Windows Update Components (Safe)

## Purpose
Reset Windows Update components safely with optional advanced steps.

## Inputs (fill these in)
- Environment: (Win10 / Win11 / Server 2019 / Server 2022)
- Tooling context: (local pwsh, NinjaOne, etc.)
- Target: `<COMPUTERNAME>` (local only)
- Constraints: (admin required, change window)

## Guardrails
- Do not include internal domains/hostnames/ticket numbers in examples.
- Prefer read-only validation first.
- Avoid destructive actions unless explicitly requested.
- Output must be copy/paste ready.

## What I want you to produce
1) PowerShell script (or function) with:
   - comment-based help
   - clear parameters (`Aggressive`, `RunDISM`, `RunSFC`)
   - try/catch + useful error messages
   - logging (Write-Host or Write-Verbose)
2) Brief “How to run” instructions
3) Validation checklist + rollback note (if applicable)

## Output format
- Script in a single code block
- Then instructions + checklist

## Run Commands
- Windows PowerShell 5.1:
  - `Set-ExecutionPolicy -Scope Process Bypass`
  - `& "./PowerShell/Reset-WindowsUpdateComponents.ps1" -Verbose`
- PowerShell 7:
  - `pwsh -ExecutionPolicy Bypass -File "./PowerShell/Reset-WindowsUpdateComponents.ps1" -Verbose`
- If running from `\\wsl.localhost` UNC paths, PowerShell 7 may require `-ExecutionPolicy Bypass` unless scripts are signed.

## Example inputs
```powershell
# Standard safe reset
pwsh ./PowerShell/Reset-WindowsUpdateComponents.ps1 -Verbose

# Aggressive reset with DISM/SFC
pwsh ./PowerShell/Reset-WindowsUpdateComponents.ps1 -Aggressive -RunDISM -RunSFC -Verbose
```
