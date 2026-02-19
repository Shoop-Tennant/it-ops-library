# Prompt Card: Outlook Cache / OST Rebuild Guidance + Checks

## Purpose
Diagnose Outlook performance or sync issues related to the OST (offline cache) file, gather size/health info, and provide guided steps to safely rebuild the OST. Includes pre-checks to rule out other causes first.

## Inputs (fill these in)
- Environment: (Win10 / Win11, Outlook version: 2021 / M365 Apps / New Outlook)
- Tooling context: (local pwsh, NinjaOne, user self-service, etc.)
- Target: `<USERNAME>` on `<COMPUTERNAME>`
- Constraints: (user-safe; Outlook must be closed for OST rename; no mailbox data loss)

## Guardrails
- Do not include internal domains/hostnames/ticket numbers in examples.
- Prefer read-only validation first (check OST size, profile status before changes).
- Avoid destructive actions unless explicitly requested.
- Output must be copy/paste ready.
- Never delete the OST outright; always rename to `.ost.bak.<timestamp>` so it can be restored.
- Remind the operator that OST rebuild triggers a full mailbox resync (bandwidth + time).
- Check for New Outlook vs. classic Outlook; New Outlook does not use OST files.

## What I want you to produce
1) PowerShell script (or function) with:
   - comment-based help
   - clear parameters (`UserProfile`, optional `-RebuildOst` switch)
   - try/catch + useful error messages
   - logging (Write-Host or Write-Verbose)
   - diagnostic steps:
     1. Detect Outlook version (classic vs. New Outlook)
     2. Locate OST file(s) under `$env:LOCALAPPDATA\Microsoft\Outlook\` (or user-specified path)
     3. Report OST file size(s) and last modified date
     4. Check if Outlook process is running
     5. Check Outlook profile count via registry
     6. (Optional) Check recent Outlook-related event log errors
   - rebuild steps (only if `-RebuildOst` passed):
     1. Confirm Outlook is closed (stop if not)
     2. Rename OST to `.ost.bak.<timestamp>`
     3. Log the rename action
     4. Advise operator to relaunch Outlook and monitor resync
2) Brief "How to run" instructions
3) Validation checklist + rollback note

## Output format
- Script in a single code block
- Then instructions + checklist

## Validation checklist
- [ ] Script correctly identifies Outlook version
- [ ] OST file path, size, and last modified date reported
- [ ] Outlook process state checked before any rename
- [ ] If rebuild requested: OST renamed (not deleted), backup file exists
- [ ] No data loss; original OST preserved as `.bak`
- [ ] Operator advised on expected resync time/bandwidth

## Rollback note
1. Close Outlook.
2. Delete the newly created (empty/partial) OST file.
3. Rename the `.ost.bak.<timestamp>` file back to the original `.ost` name.
4. Relaunch Outlook.

## Example inputs
```powershell
# Diagnostic only (read-only, no changes)
.\Repair-OutlookOst.ps1 -Verbose

# Diagnostic + rebuild OST for specific user profile
.\Repair-OutlookOst.ps1 -UserProfile "C:\Users\jsmith" -RebuildOst -Verbose

# Via NinjaOne (runs as SYSTEM, target user profile)
.\Repair-OutlookOst.ps1 -UserProfile "C:\Users\jsmith"
```
