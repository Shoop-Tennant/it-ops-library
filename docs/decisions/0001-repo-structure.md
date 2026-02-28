# ADR 0001 — Repository Structure and Conventions

| Field  | Value |
|--------|-------|
| Date   | 2026-02-28 |
| Status | Accepted |
| Author | Jeremy Shoop |

---

## Context

`it-ops-library` is a shared IT Ops resource library covering PowerShell tooling,
AI prompt cards, runbooks, and documentation. It is maintained by a small team
operating across Windows, WSL2, and a TrueNAS backup share.

Early development produced inconsistent folder casing (`PowerShell/` vs `prompts/`),
a near-empty README, no line-ending enforcement, and no documented rationale for
what belongs in the repo versus in the team's shared Drive workspace.

This ADR records the structural decisions made during the Phase 1–4 hygiene pass
so future contributors (and future Claude sessions) understand the *why*, not just
the *what*.

---

## Decisions

### 1. All folder names are lowercase

**Decision:** Every folder in the repo uses lowercase (e.g., `powershell/`, `functions/`,
`tools/`, `tests/`, `docs/`, `prompts/`).

**Rationale:** The primary execution environment is WSL2 (Linux), where the filesystem
is case-sensitive. Mixed casing (`PowerShell/Functions/`) causes path resolution failures
when scripts dot-source each other or when Pester resolves fixture paths. Lowercase
everywhere eliminates the class of bug entirely and is consistent with Linux conventions
and this repo's other tooling (Terraform, shell scripts).

---

### 2. Top-level folder layout reflects artifact type, not platform

**Decision:** Top-level folders separate artifacts by *what they are*, not *which tool
they target*:

```
powershell/     Language-specific code (functions, scripts, tests)
prompts/        AI prompt cards (further divided by language)
samples/        Synthetic test fixtures only — never real data
docs/           Project documentation, runbooks, decisions
scripts/        Agent task definitions and orchestration docs
```

**Rationale:** A flat, purpose-driven layout scales better than a platform-driven one.
When Terraform or Python tooling is added, it gets its own top-level folder
(`terraform/`, `python/`) following the same internal convention as `powershell/`.
Prompt cards under `prompts/` are subdivided by target language (`prompts/powershell/`,
`prompts/terraform/`) because the card content is language-specific.

---

### 3. `powershell/` internal layout: `functions/` / `tools/` / `tests/`

**Decision:** Inside `powershell/`, three subfolders with defined semantics:

| Subfolder | Contains | Rules |
|-----------|----------|-------|
| `functions/` | Dot-sourceable function files | One function per file, filename matches function name |
| `tools/` | Runnable entry-point scripts | May dot-source from `functions/`; must support `-WhatIf` where actions are taken |
| `tests/` | Pester test files | Named `<FunctionName>.Tests.ps1`; use fixtures from `samples/` |

**Rationale:** Separating library code (`functions/`) from entry points (`tools/`) mirrors
module patterns in larger PowerShell projects and keeps dot-source paths predictable.
Tests are co-located with code (in `powershell/`) rather than in a top-level `tests/`
folder so they travel with the language they exercise.

---

### 4. Naming conventions

**Decision:**

| Artifact | Convention | Example |
|----------|-----------|---------|
| PowerShell functions | `Verb-Noun` (approved verb) | `Remove-PiiFromString` |
| PowerShell script files | `Verb-Noun.ps1` | `Sanitize-File.ps1` |
| Prompt Card files | `intent-kebab-case.md` | `clear-teams-cache.md` |
| ADR files | `NNNN-short-title.md` | `0001-repo-structure.md` |
| Meta/template files | Underscore prefix | `_template.md` |
| Folders | Lowercase, hyphen-separated if multi-word | `tools/`, `test-data/` |

**Rationale:** PowerShell conventions follow the language's own standards (approved verbs
via `Get-Verb`). Kebab-case for markdown files is consistent with GitHub rendering and
avoids spaces in paths. Underscore-prefixed files sort to the top in directory listings,
making templates and meta-files easy to spot.

---

### 5. `.editorconfig` and `.gitattributes` enforce encoding and line endings

**Decision:** Both files are committed to the repo root.

- `.editorconfig`: UTF-8, LF, 4-space indent for PowerShell, 2-space for everything else.
- `.gitattributes`: `* text=auto eol=lf` as the default; explicit `eol=lf` per extension
  for `.ps1`, `.psm1`, `.psd1`, `.md`, `.tf`, `.json`, `.yaml`; binary declarations for
  image and executable types.

**Rationale:** The team edits files on Windows (CRLF default) and executes them in WSL2
(LF required). Without enforcement, CRLF can silently corrupt PowerShell here-strings,
break shebang lines, and cause spurious diffs. Git-level enforcement is more reliable than
editor configuration alone because it applies at checkin regardless of editor or OS.

---

### 6. `.gitignore` blocks data exports and secrets by default

**Decision:** `.gitignore` excludes `*.csv`, `*.xlsx`, `*.xls`, `*.log`, `*.cred`,
`*.pfx`, `*.pem`, `*.key`, `secrets/`, `.env`, and Terraform state files.
A targeted exception (`!samples/**/*.csv`) allows synthetic fixture data.

**Rationale:** Lansweeper, NinjaOne, and Intune exports contain device names, serials,
usernames, and internal IPs. A default-deny pattern for data file types means a
contributor must make a deliberate, visible choice to commit data — they cannot
accidentally drag in an export. The exception for `samples/**` keeps synthetic fixtures
committable without loosening the broader rule.

---

## What Belongs in the Repo vs. the Drive Workspace

### In the repo (version-controlled, team-visible)

- PowerShell functions, tools, and Pester tests
- Prompt Cards (sanitized examples, no real org data)
- Synthetic test fixtures (`samples/`)
- Documentation: runbooks, ADRs, quest log, environment baseline
- Agent task definitions (`scripts/`)
- Config files: `.editorconfig`, `.gitattributes`, `.gitignore`, `CLAUDE.md`

### In the Drive workspace / NAS only (never committed)

| Item | Why |
|------|-----|
| Lansweeper / NinjaOne / Intune CSV exports | Contain real device names, serials, IPs |
| Script transcript logs (`*.log`) | May capture real hostnames, credentials, or output |
| Sanitized output files (`*.sanitized`) | Intermediate artifacts, not source |
| Azure credentials, service principal secrets | Secret material |
| Certificates and keys (`*.pfx`, `*.pem`, `*.key`) | Secret material |
| Real-data test inputs | Only synthetic data belongs in `samples/` |
| Drafts referencing internal ticket numbers or hostnames | Scrub before committing |

### Grey area — decide per case

| Item | Guidance |
|------|----------|
| Runbooks with internal system names | Replace with generalized placeholders before committing; keep originals on Drive |
| NinjaOne script output samples | Sanitize with `Sanitize-File.ps1` first; commit only the sanitized version |
| KB article drafts | Acceptable if scrubbed; use `Remove-PiiFromString` on any pasted content |

---

## Consequences

- New contributors can orient quickly using the folder map in `README.md` without needing
  to ask about conventions.
- Automated enforcement (`.editorconfig`, `.gitattributes`, `.gitignore`) reduces the
  review burden for casing and encoding issues.
- The ADR series (`docs/decisions/`) provides a lightweight audit trail for future
  structural changes — add a new ADR rather than silently changing conventions.
- When this repo grows to include Terraform or Python tooling, the same pattern applies:
  new top-level folder, same internal convention (`functions/`, `tools/`, `tests/`),
  new ADR if the decision is non-obvious.
