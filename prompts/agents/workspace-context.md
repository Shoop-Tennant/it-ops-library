# Workspace Context — Jeremy Shoop (IT Systems Analyst / Team Lead)

> **Purpose:** Paste this prompt at the start of a Gemini session to orient it to Jeremy's
> workspace, tools, and conventions. It covers the physical layout, Google Drive junctions,
> repos, launchers, backup strategy, and how everything connects.

---

## Who I Am

- **Role:** IT Systems Analyst / Team Lead supporting global IT ops (NA/APAC/EMEA).
- **Company context:** Industrial floor cleaning machines; mix of end-user, manufacturing,
  and warehouse workflows.
- **Primary domains:** Azure/Entra ID, Intune, NinjaOne (RMM), BMC Helix (ITSM),
  Lansweeper (CMDB), SAP S/4HANA, Zebra printing, M365 admin.
- **GitHub:** `Shoop-Tennant`

---

## Primary Languages & Tools

| Language / Tool | Usage |
|---|---|
| PowerShell 7 (`pwsh`) | Primary scripting — Windows-first |
| Terraform (HCL) | Cloud infra via Terraform Cloud |
| SQL (T-SQL) | Lansweeper + reporting queries |
| Python | Lightweight automation + data scrubbing |
| Bash | Only when explicitly needed |
| VS Code | Editor (Windows-native) |
| Git + GitHub | Version control; user: `Shoop-Tennant` |
| Claude Code CLI | AI coding assistant (primary) |
| Codex CLI | Secondary AI coding CLI |
| Gemini CLI | You — tertiary AI assistant |

---

## Workspace Layout (`C:\Workspace\`)

This is the root of all local work. Not all of it is in git — understand what's local-only vs cloud-backed.

```
C:\Workspace\
├── Docs\       ← JUNCTION → Google Drive (see below)
├── Inbox\      ← JUNCTION → Google Drive (see below)
├── Repos\      ← Local git repos, backed up to GitHub
│   └── it-ops-library\   ← Main IT ops repo (public: github.com/Shoop-Tennant/it-ops-library)
├── Tools\      ← Launchers, helper scripts — local only, backed up to NAS
│   ├── bin\    ← Shortcut launchers on user PATH
│   ├── Backup-WorkspaceToNAS.ps1
│   └── GoodMorning-HealthCheck.ps1
├── AI\         ← AI model cache and logs — local only
├── Scratch\    ← Ephemeral work — local only, backed up to NAS
└── Secrets\    ← Local only; NEVER committed to git
```

---

## Google Drive Junctions (Critical Detail)

`C:\Workspace\Docs\` and `C:\Workspace\Inbox\` are **Windows directory junctions**, not real folders.
They point to Google Drive (stream-synced via Google Drive for Desktop):

| Junction path | Actual target |
|---|---|
| `C:\Workspace\Docs\` | `C:\Users\<username>\My Drive\Workspace\Docs` |
| `C:\Workspace\Inbox\` | `C:\Users\<username>\My Drive\Workspace\Inbox` |

**What this means in practice:**
- Files written to `C:\Workspace\Docs\` or `C:\Workspace\Inbox\` are **automatically synced to Google Drive**.
- There is no separate copy — the junction IS the Google Drive folder.
- Reading/writing via the junction path works the same as any local folder.
- If Google Drive for Desktop isn't running, these paths will still resolve on disk but
  changes won't sync until Drive restarts.
- Never store secrets or raw exports here — they would be uploaded to Google Drive.

**Intended use:**
- `Docs\` — reference documents, KB drafts, runbooks (sanitized, shareable)
- `Inbox\` — inbound files to review or process (treat as staging; sanitize before sharing)

---

## Repos (`C:\Workspace\Repos\`)

Currently one repo: **`it-ops-library`**
- **GitHub:** `https://github.com/Shoop-Tennant/it-ops-library`
- **Branch:** `main`
- **Purpose:** Shared IT ops resource library — PowerShell scripts, AI prompt cards,
  sanitization tools, NinjaOne dashboards, runbooks, and docs.

### it-ops-library folder structure

```
it-ops-library\
├── powershell\
│   ├── functions\    ← Dot-sourceable reusable functions
│   ├── tools\        ← Standalone runnable tools
│   └── tests\        ← Pester test files
├── prompts\
│   ├── powershell\endpoint\   ← Endpoint troubleshooting prompt cards
│   └── agents\                ← AI agent context/task prompts (you are here)
├── ninjaone\patching\         ← NinjaOne patching dashboard + scripts
├── docs\
│   ├── decisions\    ← Architecture Decision Records (ADRs)
│   ├── setup\        ← Tooling setup guides
│   ├── state\        ← Live environment state docs
│   └── security\     ← Code signing guidance
├── samples\sanitization\      ← Synthetic PII test fixtures
└── scripts\                   ← Agent batch task definitions
```

---

## Launchers (`C:\Workspace\Tools\bin\` — on PATH)

These are `.cmd` shortcuts for quick access:

| Launcher | What it does |
|---|---|
| `ws.cmd` | Open `C:\Workspace` in Explorer |
| `ws-code.cmd` | Open workspace in VS Code |
| `ws-claude.cmd` | Launch Claude Code CLI |
| `ws-codex.cmd` | Launch Codex CLI |
| `ws-gemini.cmd` | Launch Gemini CLI |
| `ws-backup.cmd` | Run `Backup-WorkspaceToNAS.ps1` |
| `ws-open.cmd` | Open workspace root (alias) |
| `ws-root.cmd` | `cd` to workspace root |

---

## Backup Strategy

| What | How | Where |
|---|---|---|
| `Docs\`, `Inbox\`, `Tools\`, `Scratch\` | Robocopy `/MIR` via `Backup-WorkspaceToNAS.ps1` | `\\TRUENAS\jeremy\backups\Workspace` |
| `Repos\` | GitHub (git push) | `github.com/Shoop-Tennant` |
| `Docs\` + `Inbox\` | Also auto-synced via Google Drive junction | Google Drive |
| `Secrets\` | NOT backed up anywhere — local only | — |

`GoodMorning-HealthCheck.ps1` verifies junctions, toolchain, NAS reachability, and git status.
Run it at the start of a session: `pwsh C:\Workspace\Tools\GoodMorning-HealthCheck.ps1`

---

## Coding Standards (Short Version)

- **PowerShell:** `Verb-Noun` naming, OTBS braces, 4-space indent, `$ErrorActionPreference = 'Stop'`,
  `Try/Catch` around real actions, `SupportsShouldProcess` for mutations, Comment-Based Help on reusable scripts.
- **Commits:** Conventional commits (`feat:`, `fix:`, `chore:`, `docs:`), imperative subject line.
- **Sanitization:** Never commit real emails, hostnames, tenant IDs, serials, or tokens.
  Use placeholders: `USER@COMPANY.COM`, `DEVICE1234`, `10.x.x.x`, `<username>`.
- **Secrets:** Never in code, never in git. Always prompt, vault ref, or managed identity.
- **Data files:** `.csv`, `.xlsx`, `.log` are gitignored by default — only synthetic samples in `samples/` are committed.

---

## What NOT to Do

- Do not write files to `C:\Workspace\Secrets\`
- Do not commit anything with real internal hostnames, share paths, or usernames
- Do not use `powershell.exe` — use `pwsh` (PowerShell 7)
- Do not use local terraform state — always use remote/cloud backend
- Do not use `git add -A` blindly — stage files explicitly

---

## Quick Reference — Where Things Live

| Need | Location |
|---|---|
| Reusable PS function | `powershell/functions/` |
| Runnable tool/script | `powershell/tools/` |
| Pester test | `powershell/tests/` |
| Prompt card for Claude/Gemini | `prompts/agents/` |
| Endpoint prompt card | `prompts/powershell/endpoint/` |
| Setup/environment guide | `docs/setup/` |
| Architecture decision | `docs/decisions/` (new ADR) |
| Synthetic test data | `samples/sanitization/` |
| NinjaOne work | `ninjaone/patching/` |
| Google Drive docs | `C:\Workspace\Docs\` (auto-syncs) |
| Staging/inbound files | `C:\Workspace\Inbox\` (auto-syncs) |
| Ephemeral scratch work | `C:\Workspace\Scratch\` |
