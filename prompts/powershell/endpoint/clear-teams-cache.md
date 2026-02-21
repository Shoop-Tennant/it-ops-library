# Prompt Card: Clear Teams Cache

## Purpose
Clear Microsoft Teams cache safely for a user and optionally relaunch Teams.

## Inputs (fill these in)
- Environment: (Win10 / Win11)
- Tooling context: (local pwsh, NinjaOne, etc.)
- Target: `<USERPROFILE>` (optional for SYSTEM/NinjaOne)
- Constraints: (non-admin, user-safe, no data loss)

## Guardrails
- Do not include internal domains/hostnames/ticket numbers in examples.
- Prefer read-only validation first.
- Avoid destructive actions unless explicitly requested.
- Output must be copy/paste ready.

## What I want you to produce
1) PowerShell script (or function) with:
   - comment-based help
   - clear parameters (`UserProfile`, `SkipRelaunch`)
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
  - `& "./PowerShell/Clear-TeamsCache.ps1" -Verbose`
- PowerShell 7:
  - `pwsh -ExecutionPolicy Bypass -File "./PowerShell/Clear-TeamsCache.ps1" -Verbose`
- If running from `\\wsl.localhost` UNC paths, PowerShell 7 may require `-ExecutionPolicy Bypass` unless scripts are signed.

## Example inputs
```powershell
# Current user, relaunch Teams
pwsh ./PowerShell/Clear-TeamsCache.ps1 -Verbose

# Target specific profile (SYSTEM context), do not relaunch
pwsh ./PowerShell/Clear-TeamsCache.ps1 -UserProfile "C:\Users\jsmith" -SkipRelaunch -Verbose
```
