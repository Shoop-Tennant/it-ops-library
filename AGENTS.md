# AGENTS.md

## Purpose
Guidance for coding agents working in this repository.

## Repo Focus
- Build and maintain automation for patching/risk reporting.
- Main area: `ninjaone/patching/dashboard/`.

## Important Paths
- Source scripts: `ninjaone/patching/dashboard/src/`
- Docs: `ninjaone/patching/dashboard/docs/`
- Sample raw inputs: `ninjaone/patching/dashboard/samples/raw/`
- Sample outputs: `ninjaone/patching/dashboard/samples/output/`
- Private local-only data: `ninjaone/patching/dashboard/samples/_private/`

## Safety Rules
- Do not modify raw exports in place.
- Do not put secrets/tokens in code or committed files.
- Treat `samples/_private/` as non-shareable.
- Keep output artifacts free of direct identifiers when generating sanitized reports.

## Preferred Workflows
- NinjaOne monthly markdown report:
  - `pwsh ninjaone/patching/dashboard/src/PatchOperationsDashboard.ps1 -WhatIf`
- NinjaOne API export for correlation:
  - `pwsh ninjaone/patching/dashboard/src/Export-NinjaOneCorrelationData.ps1`

## Change Scope
- Make focused edits only for requested tasks.
- Do not revert unrelated user changes.
- If unsure about data mapping assumptions, document them in output/report notes.

# Repository Guidelines

## Repo Rules
- No network usage.
- Never add secrets, tenant IDs, or user emails to code or docs.
- All new PowerShell scripts must include comment-based help, `SupportsShouldProcess`, and `-WhatIf` support.
- Keep scripts PowerShell 5.1+ compatible unless explicitly stated otherwise.
- Prefer non-destructive actions; rename to `.bak` instead of delete.
- Any prompt card referencing a script must match the real path and parameters.

## Repo Map
- `PowerShell/`: PowerShell scripts and functions.
- `prompts/`: Prompt cards and templates for script/runbook generation.
- `docs/`: Repo notes and environment state.
- `samples/`: Sample inputs/outputs.
- `scripts/`: Task batches and workflow notes.

## Project Structure & Module Organization
- `PowerShell/Functions/`: reusable functions (e.g., `Remove-PiiFromString.ps1`).
- `PowerShell/Tools/`: standalone tools (e.g., `Sanitize-File.ps1`).
- `prompts/powershell/`: prompt cards and templates for generating scripts/runbooks.
- `docs/`: repo notes and environment state.
- `samples/`: sample inputs/outputs (e.g., sanitization samples).
- `scripts/`: task batches and workflow notes (markdown).

## Build, Test, and Development Commands
This repo is mostly content and PowerShell scripts. There are no documented build or dev commands. Run scripts directly with PowerShell, for example:
- `pwsh ./PowerShell/Tools/Sanitize-File.ps1 -Path ./samples/sanitization/input_sample.txt`
If you add automation, document it here and in `README.md`.

## Coding Style & Naming Conventions
- PowerShell scripts: `Verb-Noun.ps1` (e.g., `Get-DiagnosticsBundle.ps1`).
- Prompt cards: kebab-case filenames (e.g., `reset-windows-update-components.md`).
- Use comment-based help for PowerShell scripts and prefer `Write-Verbose` for logging.
- Keep examples sanitized (no internal hostnames/ticket IDs) per prompt card rules.

## Testing Guidelines
No formal test framework is present. If you add tests:
- Prefer a simple, repeatable command (e.g., `pwsh ./tests/run.ps1`).
- Name tests to match the script under test (e.g., `Sanitize-File.Tests.ps1`).
- Include a short note on expected output or assertions.

## Commit & Pull Request Guidelines
Commit conventions are not defined. Use clear, scoped messages (e.g., `Add Clear-TeamsCache prompt card`).
PRs should include:
- A brief summary of changes.
- Any new scripts or prompt cards added.
- Links to related issues (if applicable).
- Example usage or sample output when behavior changes.

## Security & Configuration Notes
- Sanitize data before sharing externally; use `Remove-PiiFromString` or `Sanitize-File.ps1`.
- Keep credentials and internal identifiers out of examples and docs.

## Agent-Specific Instructions
- Follow prompt card templates in `prompts/powershell/PromptCard_Template.md`.
- Keep outputs copy/paste-ready for tickets or KBs.
- Prefer read-only diagnostics before destructive actions.
