# Prompt Card: Reset Windows Update Components

## Purpose
Safely reset Windows Update components (stop services, clear caches, re-register DLLs, restart services) when updates are stuck, failing, or reporting stale status. Includes pre/post verification.

## Inputs (fill these in)
- Environment: (Win10 / Win11 / Server 2019 / Server 2022)
- Tooling context: (local pwsh, NinjaOne, Intune Remediation, etc.)
- Target: `<COMPUTERNAME>` (local or remote)
- Constraints: (requires local admin; schedule during maintenance window if server)

## Guardrails
- Do not include internal domains/hostnames/ticket numbers in examples.
- Prefer read-only validation first (check service state before making changes).
- Avoid destructive actions unless explicitly requested.
- Output must be copy/paste ready.
- Rename (not delete) SoftwareDistribution and catroot2 folders so they can be restored.
- Do not force a reboot; advise the operator when one is needed.
- Log every step so the operator can see exactly what changed.

## What I want you to produce
1) PowerShell script (or function) with:
   - comment-based help
   - clear parameters (`ComputerName`, optional `-WhatIf` support)
   - try/catch + useful error messages
   - logging (Write-Host or Write-Verbose)
   - steps:
     1. Pre-check: capture service states (wuauserv, bits, cryptsvc, msiserver)
     2. Stop the four services
     3. Rename `SoftwareDistribution` to `SoftwareDistribution.bak.<timestamp>`
     4. Rename `catroot2` to `catroot2.bak.<timestamp>`
     5. Re-register Windows Update DLLs (common set)
     6. Restart the four services
     7. Post-check: verify services are running, trigger `usoclient StartScan` or `wuauclt /detectnow`
2) Brief "How to run" instructions
3) Validation checklist + rollback note

## Output format
- Script in a single code block
- Then instructions + checklist

## Validation checklist
- [ ] All four services stopped cleanly before rename
- [ ] Backup folders created with timestamp suffix
- [ ] All four services restarted successfully
- [ ] `Get-WindowsUpdate` or Settings > Windows Update shows scan in progress
- [ ] No unexpected errors in script log output

## Rollback note
1. Stop the four services again.
2. Delete the new (empty) `SoftwareDistribution` and `catroot2` folders.
3. Rename the `.bak.<timestamp>` folders back to original names.
4. Restart the four services.

## Example inputs
```powershell
# Local machine, standard reset
.\Reset-WindowsUpdateComponents.ps1 -Verbose

# Dry run (if -WhatIf supported)
.\Reset-WindowsUpdateComponents.ps1 -WhatIf

# Remote via NinjaOne (stdout capture)
.\Reset-WindowsUpdateComponents.ps1
```
