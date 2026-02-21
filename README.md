# it-ops-library

## What This Repo Is
A practical library of IT Ops prompt cards and safe endpoint PowerShell scripts. The goal is fast, repeatable troubleshooting without leaking sensitive data.

## Quick Start
- Prereqs: Windows PowerShell 5.1+ or PowerShell 7, admin rights when required by a script.
- Start here: `prompts/powershell/README.md` and `prompts/powershell/PromptCard_Template.md`.
- Run a prompt card: open a card under `prompts/powershell/endpoint/`, fill Inputs, paste into your AI tool, and save the generated script under `PowerShell/`.

## How To Run Scripts
Windows PowerShell 5.1:
```
Set-ExecutionPolicy -Scope Process Bypass
& "./PowerShell/<script>.ps1" -Verbose
```
PowerShell 7:
```
pwsh -ExecutionPolicy Bypass -File "./PowerShell/<script>.ps1" -Verbose
```
Note: If running from `\\wsl.localhost` UNC paths, PowerShell 7 may require `-ExecutionPolicy Bypass` unless scripts are signed.

## Folder Map
- `PowerShell/` — endpoint scripts and reusable functions.
- `prompts/` — prompt cards and templates for script/runbook generation.
- `docs/` — standards, workflow, and repo state.
- `samples/` — sanitized sample inputs/outputs.
- `scripts/` — batch tasks and workflow notes.

## Safety Notes
- Prefer `-WhatIf` and `SupportsShouldProcess` where changes occur.
- Favor rename-to-`.bak` over delete.
- Never include secrets, tenant IDs, or user emails in scripts or docs.

## Contribution Workflow
- Branch from the current working branch, keep changes scoped.
- Commit style: short, imperative, scoped to the change (example: `Add printer triage prompt card`).
- PRs should describe changes, risks, and how to run/validate.
- Standards live in `docs/standards.md` and `AGENTS.md`.
