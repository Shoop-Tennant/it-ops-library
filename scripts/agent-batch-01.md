# Agent Batch 01 — PowerShell Prompt Cards (1–5)

## Inputs
- Template: prompts/powershell/PromptCard_Template.md
- Backlog: prompts/powershell/BACKLOG.md

## Task
Create Prompt Cards for BACKLOG items 1–5:
1. Diagnostics bundle to zip
2. Reset Windows Update components (safe)
3. Clear Teams cache + relaunch (user-safe)
4. Outlook cache / OST rebuild guidance + checks
5. Printer triage (spooler reset + queue listing + safe fixes)

## Output requirements
- One file per card, saved under the correct folder:
  - endpoint/ for diagnostics, Teams, Outlook, Windows Update
  - tickets-kb/ or endpoint/ for printer triage (your call, be consistent)
- Use kebab-case filenames, e.g.:
  - diagnostics-bundle-to-zip.md
  - reset-windows-update-components.md
  - clear-teams-cache.md
  - outlook-ost-rebuild-checks.md
  - printer-triage-spooler-queues.md
- Must follow PromptCard_Template headings.
- Sanitize examples (example.com, server01, no internal domains/hostnames/shares/ticket IDs).
- Include: guardrails, required inputs, output format, validation checklist, rollback note.
