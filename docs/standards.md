# Standards

## Naming Conventions
- PowerShell scripts: `Verb-Noun.ps1` (examples: `Get-DiagnosticsBundle.ps1`, `Reset-WindowsUpdateComponents.ps1`).
- Prompt cards: kebab-case filenames (example: `reset-windows-update-components.md`).

## Folder Conventions
- `PowerShell/` — scripts and reusable functions.
- `prompts/` — prompt cards and templates.
- `docs/` — standards, workflow, and state.
- `samples/` — sanitized sample inputs/outputs.
- `scripts/` — batch tasks and workflow notes.

## Script Requirements
- Comment-based help: `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`, `.NOTES`.
- `SupportsShouldProcess` for any changes.
- Logging: write a transcript/log to a user-writable folder.
- Structured output: return a `PSCustomObject` summary.

## Output Schema Baseline
Every script should emit a summary object with at least:
- `Script`
- `ComputerName`
- `Timestamp`
- `Actions`
- `Warnings`
- `LogPath`
- `UserProfile` (if applicable)

## Error Handling Rules
- Do not hard-crash for “app not installed” or missing components.
- Emit warnings and return a summary object instead.

## PII and Sanitization
- Never commit secrets, tenant IDs, or user emails.
- Sanitize logs or examples before sharing.
