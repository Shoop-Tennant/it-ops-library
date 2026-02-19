# Prompt Card: Printer Triage (Spooler Reset + Queue Listing + Safe Fixes)

## Purpose
Triage common printer issues by checking spooler health, listing print queues, clearing stuck jobs, and applying safe non-destructive fixes. Designed for L1/L2 first-response before escalating to print server or Zebra-specific troubleshooting.

## Inputs (fill these in)
- Environment: (Win10 / Win11 / Server 2019 / Server 2022)
- Tooling context: (local pwsh, NinjaOne, etc.)
- Target: `<COMPUTERNAME>` (local or remote)
- Constraints: (requires local admin for spooler restart; non-destructive; no driver changes)

## Guardrails
- Do not include internal domains/hostnames/ticket numbers in examples.
- Prefer read-only validation first (list queues and spooler status before making changes).
- Avoid destructive actions unless explicitly requested.
- Output must be copy/paste ready.
- Do not uninstall or modify printer drivers.
- Do not delete printer ports or change printer configurations.
- Clearing stuck jobs is safe; removing printers is not (requires operator confirmation).
- Log every action for ticket documentation.

## What I want you to produce
1) PowerShell script (or function) with:
   - comment-based help
   - clear parameters (`ComputerName`, optional `-ResetSpooler` switch, optional `-ClearStuckJobs` switch)
   - try/catch + useful error messages
   - logging (Write-Host or Write-Verbose)
   - diagnostic steps (always run):
     1. Check Print Spooler service status
     2. List all installed printers (`Get-Printer`) with status, port, driver
     3. List print jobs across all queues (`Get-PrintJob`) with status, size, owner
     4. Flag any jobs in Error state
     5. Check for common issues: spooler crash events in System log (last 24h)
   - fix steps (only when switches are passed):
     1. `-ClearStuckJobs`: Remove jobs in Error state from all queues
     2. `-ResetSpooler`: Stop Spooler, clear `C:\Windows\System32\spool\PRINTERS\*`, restart Spooler
   - summary output: table of printers, job counts, actions taken
2) Brief "How to run" instructions
3) Validation checklist + rollback note

## Output format
- Script in a single code block
- Then instructions + checklist

## Validation checklist
- [ ] Spooler service status reported correctly
- [ ] All printers listed with status and port info
- [ ] Stuck/error jobs identified and listed
- [ ] If `-ResetSpooler` used: spooler restarted cleanly, spool folder cleared
- [ ] If `-ClearStuckJobs` used: error jobs removed, healthy jobs untouched
- [ ] No printers removed or drivers modified
- [ ] Output is clean enough to paste into a ticket

## Rollback note
- Cleared print jobs cannot be restored; users will need to reprint.
- Spooler reset is safe; printers and drivers are preserved. If a printer disappears after spooler reset, it was likely a per-session printer (e.g., redirected RDP printer) and will return on next session.

## Example inputs
```powershell
# Diagnostic only (read-only, no changes)
.\Invoke-PrinterTriage.ps1 -Verbose

# Diagnostic + clear stuck jobs
.\Invoke-PrinterTriage.ps1 -ClearStuckJobs -Verbose

# Full triage: clear jobs + reset spooler
.\Invoke-PrinterTriage.ps1 -ClearStuckJobs -ResetSpooler -Verbose

# Remote machine
.\Invoke-PrinterTriage.ps1 -ComputerName "YOURPC" -Verbose
```
