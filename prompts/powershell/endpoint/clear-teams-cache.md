# Prompt Card: Clear Teams Cache + Relaunch

## Purpose
Clear the Microsoft Teams client cache to resolve common issues (sign-in loops, blank screens, stale data, slow performance) and relaunch Teams cleanly. Works for both classic Teams and new Teams.

## Inputs (fill these in)
- Environment: (Win10 / Win11)
- Tooling context: (local pwsh, NinjaOne, user self-service, etc.)
- Target: `<USERNAME>` on `<COMPUTERNAME>`
- Constraints: (user-safe; must close Teams gracefully; no data loss)

## Guardrails
- Do not include internal domains/hostnames/ticket numbers in examples.
- Prefer read-only validation first (check if Teams is running before killing it).
- Avoid destructive actions unless explicitly requested.
- Output must be copy/paste ready.
- Warn the user to save any in-progress chats/meetings before running.
- Do not delete chat history or user config; only clear cache/tmp/GPU cache folders.
- Detect classic Teams vs. new Teams and handle the correct cache paths.

## What I want you to produce
1) PowerShell script (or function) with:
   - comment-based help
   - clear parameters (optional `-SkipRelaunch` switch)
   - try/catch + useful error messages
   - logging (Write-Host or Write-Verbose)
   - steps:
     1. Check if Teams process(es) are running
     2. Gracefully stop Teams (with timeout, then force if needed)
     3. Identify cache paths:
        - Classic: `$env:APPDATA\Microsoft\Teams\Cache`, `blob_storage`, `databases`, `GPUCache`, `Local Storage`, `tmp`
        - New Teams: `$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache`
     4. Delete cache folders
     5. Log what was removed and total size freed
     6. Relaunch Teams (unless `-SkipRelaunch`)
2) Brief "How to run" instructions
3) Validation checklist + rollback note

## Output format
- Script in a single code block
- Then instructions + checklist

## Validation checklist
- [ ] Teams process stopped before cache deletion
- [ ] Cache folders removed (or confirmed empty)
- [ ] Teams relaunched and user can sign in
- [ ] No user data lost (chat history, settings intact)
- [ ] Script output shows size of cache cleared

## Rollback note
Cache is regenerated automatically on next Teams launch. No rollback needed. If Teams fails to launch after clearing, try a full uninstall/reinstall.

## Example inputs
```powershell
# Standard run: close Teams, clear cache, relaunch
.\Clear-TeamsCache.ps1 -Verbose

# Clear cache only, don't relaunch
.\Clear-TeamsCache.ps1 -SkipRelaunch

# Via NinjaOne (runs as SYSTEM, target user profile)
.\Clear-TeamsCache.ps1 -UserProfile "C:\Users\jsmith"
```
