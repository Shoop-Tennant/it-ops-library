# Prompt Card: Outlook OST Rebuild Checks

## Purpose
Detect Outlook OST files and optionally rename them to force a rebuild.

## Inputs (fill these in)
- Environment: (Win10 / Win11)
- Tooling context: (local pwsh, NinjaOne, etc.)
- Target: `<USERPROFILE>` (optional for SYSTEM/NinjaOne)
- Constraints: (user-safe, no deletion)

## Guardrails
- Do not include internal domains/hostnames/ticket numbers in examples.
- Prefer read-only validation first.
- Avoid destructive actions unless explicitly requested.
- Output must be copy/paste ready.

## What I want you to produce
1) PowerShell script (or function) with:
   - comment-based help
   - clear parameters (`UserProfile`, `Rebuild`, `CloseOutlook`)
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
  - `& "./PowerShell/Repair-OutlookOst.ps1" -Verbose`
- PowerShell 7:
  - `pwsh -ExecutionPolicy Bypass -File "./PowerShell/Repair-OutlookOst.ps1" -Verbose`
- If running from `\\wsl.localhost` UNC paths, PowerShell 7 may require `-ExecutionPolicy Bypass` unless scripts are signed.

## NinjaOne / Remote Runbook Notes
- Run context: User context preferred; SYSTEM requires `-UserProfile` to target the correct profile.
- `-UserProfile`: Pass when running as SYSTEM or fixing a different user; use `C:\Users\<name>` from device/user inventory.
- L1/L2 safety: Do not use `-Rebuild` without user approval; always try detection first.
- Escalate if: OST rebuild fails, Outlook won't launch after rename, or profile path is missing.
- Expected outputs: `LogPath` in summary; OST is renamed to `.bak` (not deleted).

## Example inputs
```powershell
# Detect OST files only
pwsh ./PowerShell/Repair-OutlookOst.ps1 -Verbose

# Close Outlook and rebuild OST for a specific user profile
pwsh ./PowerShell/Repair-OutlookOst.ps1 -UserProfile "C:\Users\jsmith" -CloseOutlook -Rebuild -Verbose
```
