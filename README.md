# it-ops-library

## What This Repo Is
A practical library of IT Ops prompt cards and safe endpoint PowerShell scripts. The goal is fast, repeatable troubleshooting without leaking sensitive data.

## Quick Start
- Prereqs: Windows PowerShell 5.1+ or PowerShell 7, admin rights when required by a script.
- Start here: `prompts/powershell/README.md` and `prompts/powershell/PromptCard_Template.md`.
- Run a prompt card: open a card under `prompts/powershell/endpoint/`, fill Inputs, paste into your AI tool.
- Use existing scripts: run scripts under `PowerShell/`.
- Create new scripts: use a branch/PR and follow `docs/standards.md`.

## How To Run Scripts
Windows PowerShell 5.1:
```
Set-ExecutionPolicy -Scope Process Bypass -Force
& "./PowerShell/<script>.ps1" -Verbose
```
PowerShell 7:
```
pwsh -ExecutionPolicy Bypass -File "./PowerShell/<script>.ps1" -Verbose
```
Note: UNC paths (`\\wsl.localhost\...`) + PowerShell 7 may require `-ExecutionPolicy Bypass` unless scripts are signed.

## Ready-to-Use Scripts
- `PowerShell/Clear-TeamsCache.ps1`
- `PowerShell/Get-DiagnosticsBundle.ps1`
- `PowerShell/Repair-OutlookOst.ps1`
- `PowerShell/Invoke-PrinterTriage.ps1`
- `PowerShell/Reset-WindowsUpdateComponents.ps1`

## Folder Map
- `PowerShell/` — endpoint scripts and reusable functions.
- `prompts/` — prompt cards and templates for script/runbook generation.
- `docs/` — standards, workflow, and repo state.
- `samples/` — sanitized sample inputs/outputs.
- `scripts/` — batch tasks and workflow notes (not executable scripts).

## Safety Notes
- Prefer `-WhatIf` and `SupportsShouldProcess` where changes occur.
- Favor rename-to-`.bak` over delete.
- Default behavior is discovery-only unless you pass an explicit action switch.
- Code signing guidance: see `docs/security/code-signing.md`.
- Never include secrets, tenant IDs, or user emails in scripts or docs.

## Contribution Workflow
- Branch from the primary branch (e.g., main), keep changes scoped.
- Commit style: short, imperative, scoped to the change (example: `Add printer triage prompt card`).
- PRs should describe changes, risks, and how to run/validate.
- Standards live in `docs/standards.md` and `AGENTS.md`.
Reusable IT Operations resource library: AI prompt cards, PowerShell tools, sanitization utilities, and runbook templates.
Maintained for Windows-first environments — Intune · NinjaOne · Azure · Zebra printing · SAP support.

---

## Folder Map

```
it-ops-library/
├── powershell/
│   ├── functions/          Shared functions — dot-source into scripts
│   ├── tools/              Runnable entry-point scripts
│   └── tests/              Pester unit + integration tests
├── prompts/
│   └── powershell/
│       ├── _template.md    Blank Prompt Card — copy to start a new card
│       └── endpoint/       Cards for endpoint support tasks
├── samples/
│   └── sanitization/       Synthetic test fixtures (input → expected output)
└── docs/
    ├── QUEST_LOG.md        Roadmap and session notes
    ├── ENVIRONMENT.md      Dev environment baseline
    └── decisions/          Architecture Decision Records (ADRs)
```

---

## Prompt Cards

Prompt Cards are structured fill-in templates. You complete the `[INPUT]` fields and paste the card into Claude (or another AI assistant) to generate a safe, consistent PowerShell script.

**Workflow**

1. Open a card from `prompts/powershell/<category>/`.
2. Fill in the `[INPUT]` placeholders (device name, output path, time window, etc.).
3. Paste the full card text into Claude.
4. Save the generated script to `powershell/` and test with `-WhatIf` before live use.

To create a new card, copy `prompts/powershell/_template.md` and follow its headings.

**Available cards — `endpoint/`**

| Card | Purpose |
|---|---|
| `clear-teams-cache.md` | Clear Teams cache to fix sign-in loops and blank screens |
| `diagnostics-bundle-to-zip.md` | Collect system info, event logs, and network config into a single `.zip` |
| `outlook-ost-rebuild-checks.md` | Diagnose Outlook / OST health; optional safe rebuild (renames, never deletes) |
| `printer-triage-spooler-queues.md` | Diagnose print spooler and stuck jobs; optional safe spooler reset |
| `reset-windows-update-components.md` | Reset Windows Update services and cache folders (rename-based, fully reversible) |

---

## Sanitization Tool

Redacts common PII from any line-oriented text file (logs, exports, ticket pastes) before sharing externally.

**Patterns redacted:** email addresses · SSNs · US phone numbers · IPv4 addresses · UNC paths · Windows device names

```powershell
# Basic — writes <filename>.sanitized.<ext> alongside the source
pwsh ./powershell/tools/Sanitize-File.ps1 -Path ./export.txt

# Custom output path
pwsh ./powershell/tools/Sanitize-File.ps1 -Path ./export.txt -OutPath ./safe-export.txt

# Dry run — preview redaction counts, no file written
pwsh ./powershell/tools/Sanitize-File.ps1 -Path ./export.txt -WhatIf
```

Outputs a summary table showing redaction counts per pattern type.
See `samples/sanitization/` for synthetic test fixtures (input → expected output).

---

## Running Tests

Tests use [Pester 5](https://pester.dev). Install once if missing:

```powershell
Install-Module Pester -Force -Scope CurrentUser
```

Run all tests from the repo root:

```powershell
Invoke-Pester ./powershell/tests/ -Output Detailed
```

Run a single test file:

```powershell
Invoke-Pester ./powershell/tests/Remove-PiiFromString.Tests.ps1 -Output Detailed
```

Tests live in `powershell/tests/` and use synthetic fixtures from `samples/sanitization/` — no real data required.

---

## AI / Claude Context

This repo ships with a `CLAUDE.md` working agreement at the root. When starting a Claude Code session in this directory, Claude reads it automatically and applies:

- Coding standards (Verb-Noun naming, OTBS formatting, error handling defaults)
- Output format preferences (tickets, KBs, runbooks, leadership artifacts)
- Security defaults (no hardcoded secrets, sanitize before external sharing)

See [`CLAUDE.md`](./CLAUDE.md) for the full working agreement.

---

## Contributing

- **Naming:** PowerShell `Verb-Noun`; files `intent-forward-kebab-case.ps1`; folders lowercase
- **No real data:** no internal hostnames, tenant IDs, serials, ticket numbers, or usernames in committed files
- **Prompt Cards:** add to `prompts/powershell/<category>/` — copy `_template.md` to start
- **Sensitive patterns:** use `powershell/tools/Sanitize-File.ps1` to scrub before committing examples
- **Tests:** add Pester tests to `powershell/tests/` for any new functions
