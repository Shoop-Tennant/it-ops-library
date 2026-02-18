# Prompt Card: <TITLE>

## Purpose
<What this prompt is for>

## Inputs (fill these in)
- Environment: (Win11 / Server / WSL / etc.)
- Tooling context: (local pwsh, NinjaOne, Intune, etc.)
- Target: (<COMPUTERNAME>, <USER>, <PATH>, <TENANT>, etc.)
- Constraints: (non-admin, L1-safe, change window, etc.)

## Guardrails
- Do not include internal domains/hostnames/ticket numbers in examples.
- Prefer read-only validation first.
- Avoid destructive actions unless explicitly requested.
- Output must be copy/paste ready.

## What I want you to produce
1) PowerShell script (or function) with:
   - comment-based help
   - clear parameters
   - try/catch + useful error messages
   - logging (Write-Host or Write-Verbose)
2) Brief “How to run” instructions
3) Validation checklist + rollback note (if applicable)

## Output format
- Script in a single code block
- Then instructions + checklist

## Example inputs
<Provide sanitized sample inputs>
