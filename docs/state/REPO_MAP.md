# Repo Map

## Root
- `/` — repo root: config files (`.editorconfig`, `.gitattributes`, `.gitignore`), `README.md`, `CLAUDE.md`, `AGENTS.md`

## powershell/
- `powershell/` — endpoint scripts (runnable, top-level)
- `powershell/functions/` — dot-sourceable reusable functions (one function per file)
- `powershell/tools/` — standalone tools; may dot-source from `functions/`
- `powershell/tests/` — Pester test files (`<FunctionName>.Tests.ps1`)

## prompts/
- `prompts/powershell/` — PowerShell prompt card library
- `prompts/powershell/endpoint/` — endpoint troubleshooting prompt cards
- `prompts/agents/` — agent task prompt cards and orchestration templates

## ninjaone/
- `ninjaone/patching/` — NinjaOne patching module
- `ninjaone/patching/dashboard/` — patch operations dashboard scripts and docs
- `ninjaone/patching/dashboard/src/` — PowerShell source scripts
- `ninjaone/patching/dashboard/samples/` — sanitized sample dashboard outputs
- `ninjaone/patching/policies/` — placeholder for policy configs
- `ninjaone/patching/reporting/` — placeholder for reporting scripts
- `ninjaone/patching/runbooks/` — placeholder for runbooks
- `ninjaone/patching/scripts/` — placeholder for ad-hoc scripts

## docs/
- `docs/decisions/` — Architecture Decision Records (ADRs)
- `docs/mcp/` — MCP guidance and configuration notes
- `docs/security/` — code signing and security guidance
- `docs/setup/` — environment and tooling setup guides
- `docs/state/` — live environment and workflow state (not versioned history)

## samples/
- `samples/sanitization/` — synthetic input/output fixtures for PII sanitization testing

## scripts/
- `scripts/` — agent batch task definitions and orchestration notes
