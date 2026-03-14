# Changelog

All notable changes to `it-ops-library` are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Added
- `prompts/agents/helix-reviewer.md` — Generic ITSM build doc second-opinion reviewer prompt (promoted from Helix project workspace). Covers sanitization, P0/P1/P2 risk rubric, UAT checklist, scoring model, and multi-doc rollup pattern.
- `prompts/agents/helix-reviewer-task-template.md` — Portable task template for running a full ITSM review batch. Replaces machine-specific paths with relative references.

---

## [0.4.0] — 2026-03-01

### Added
- `docs/state/workspace-context.md` agent prompt for AI onboarding to current repo state
- Repo reorganization: cleaned stale docs, unified structure after branch merges

### Changed
- Consolidated state tracking docs into `docs/state/`

---

## [0.3.0] — 2026-02-15

### Added
- `powershell/tools/New-AiWorkflowFolder.ps1` — scaffolds structured AI workflow folders
- `powershell/tools/Backup-WorkspaceToNAS.ps1` extended to cover Tools and Scratch directories
- `powershell/tests/Backup-WorkspaceToNAS.Tests.ps1` — Pester coverage for backup tool

### Fixed
- `Remove-PiiFromString.ps1` — allow empty string input; fix sanitize tool paths
- Git index casing fixes across `powershell/` directory

---

## [0.2.0] — 2026-01-20

### Added
- `ninjaone/patching/` module — NinjaOne patch operations dashboard tooling
  - `PatchOperationsDashboard.ps1` — multi-org dashboard generator
  - `Export-NinjaOneCorrelationData.ps1` — API export for correlation/migration evidence
  - `Test-PatchOpsKb.ps1` — dashboard validation script
  - Dashboard samples (Feb 2026) for 4 pilot organizations
- `prompts/agents/sanitize-compare-patching.md` and `sanitize-correlate-risk-patching.md` — agent prompts for patching analysis

### Fixed
- Sanitized samples in `samples/sanitization/` — removed PII from test fixtures
- `.gitignore` updated to suppress Windows ADS metadata files

---

## [0.1.0] — 2025-12-15

### Added
- Initial repo scaffold: `docs/`, `powershell/`, `prompts/`, `samples/`, `scripts/`
- `AGENTS.md`, `CLAUDE.md`, `README.md` — core repo docs
- `docs/standards.md` — contribution and naming standards
- `docs/decisions/0001-repo-structure.md` — ADR for repo structure
- `docs/security/code-signing.md` + `Sign-ItOpsLibraryScripts.ps1` — code signing guide and helper
- `docs/setup/windows-ai-cli-stack.md` — AI CLI environment setup guide
- `docs/state/` — QUEST_LOG, REPO_MAP, WHERE_I_LEFT_OFF, ENVIRONMENT, AGENT_WORKFLOW
- Core PowerShell scripts: Clear-TeamsCache, Get-DiagnosticsBundle, Invoke-PrinterTriage, Repair-OutlookOst, Reset-WindowsUpdateComponents
- `powershell/functions/Remove-PiiFromString.ps1` — PII redaction utility
- `powershell/tests/Remove-PiiFromString.Tests.ps1` — Pester test suite
- `powershell/tools/Sanitize-File.ps1` — file sanitization tool
- `prompts/powershell/` — prompt card framework with template, README, backlog, and 5 endpoint cards
- `samples/sanitization/` — PII redaction test fixtures
- `.editorconfig`, `.gitattributes`, `.gitignore`, `.vscode/` workspace config

---

*Dates are approximate based on commit history. Semantic versioning adopted from this release forward.*
