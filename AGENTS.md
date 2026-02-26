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

