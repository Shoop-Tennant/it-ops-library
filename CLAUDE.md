# CLAUDE.md — Jeremy Shoop (IT Systems Analyst / Team Lead)

> **Purpose:** Working agreement for how Claude should generate **code**, **runbooks**, **KB articles**, and **leadership artifacts** that fit Jeremy's real environment (Azure/Intune/Terraform/NinjaOne/Lansweeper/BMC Helix/SAP + printing).

---

## 0) Operating Context (for better assumptions)

- Corporate IT Ops / Systems Analysis supporting global sites (NA/APAC/EMEA).
- Company builds industrial floor cleaning machines; mix of **end-user**, **manufacturing**, and **warehouse** workflows.
- Frequent support domains: **Intune + mobile**, **Zebra printing**, **SAP S/4HANA**, **device lifecycle**, **CMDB/reporting**.
- "Paste-ready" output is the goal (tickets/Teams/KB/runbooks/scripts).

---

## 1) Tech Stack & Environment

### Primary languages
- **PowerShell** (Windows-first; 5.1 and 7 depending on host)
- **Terraform (HCL)** (Terraform Cloud)
- **SQL (T‑SQL)** for Lansweeper/reporting queries
- **Python** for lightweight automation + data generation/scrubbing
- **Bash** only if explicitly requested / unavoidable

### Key tools / platforms
- **Azure / Entra ID / Intune**
- **Terraform Cloud**
- **NinjaOne** (RMM rollout, patching, agent install workflows; **Scripts must output to `Write-Host`/stdout for RMM log capture**)
- **BMC Helix (Smart IT / Knowledge / Catalog as applicable)**
- **Lansweeper** (inventory + SQL-backed reporting)
- **SAP S/4HANA** support context (Fiori/RFUI)
- **Zebra printers** (ZPL/CPCL concepts, DPI/layout issues, print servers)
- **M365 admin** (licenses, identity/device posture)
- **VS Code + Git** (scripts, prompt libraries, markdown KB/runbooks)

### Execution Environment (The "Dev Box")
- **Primary Host:** Windows (native) — `C:\Users\jsp6\git\`
- **WSL2 (Ubuntu):** Available but not primary; VPN can disrupt WSL2 networking — use native Windows when on VPN.
- **Editor:** VS Code (Windows-native)
- **Backup Strategy:** Active work in `C:\Users\jsp6\git\`, mirrored to `Z:\Claude\Work_Backups` (TrueNAS) via Robocopy.
- **Version Control:** GitHub User `Shoop-Tennant` (Private Repos).
- **Implications:**
  - PowerShell is `powershell.exe` (Windows 5.1) or `pwsh` (PowerShell 7).
  - File paths use backslashes on Windows (`C:\Users\jsp6\git\`).
  - Local Azure auth: `az login` (Windows) or `az login --use-device-code` (WSL/headless).

---

## 2) Coding Standards & Style

### Naming conventions
- PowerShell: **Verb-Noun** (approved verbs when possible)
- Prefer clear, org-scoped nouns/prefixes where helpful:
  - `Get-TennantDevice`, `New-ZebraPrinterBatch`, `Export-LansweeperReport`
- Variables: `camelCase` for locals; parameters in `PascalCase`
- Files: intent-forward names (e.g., `New-ZebraPrinters-FromCsv.ps1`)

### Error handling
- Scripts: default to `$ErrorActionPreference = 'Stop'`
- Use `Try/Catch` around any "real" action (installs, deletes, network calls, API, print server changes).
- Prefer idempotency: detect existing state before writing changes.
- Fail loud + actionable: `throw` with short operator guidance + underlying exception details.

### Commenting / docs
- Reusable scripts: **Comment-Based Help** at the top
- Inline comments only for non-obvious logic
- KB/runbooks use consistent headings:
  - **Purpose / Scope**
  - **Prereqs / Access**
  - **Steps**
  - **Validation**
  - **Rollback**
  - **Owner / Last Verified**

### Formatting & linting
- PowerShell: **OTBS**, 4-space indentation, avoid backticks, prefer splatting
- Use **PSScriptAnalyzer** where practical
- Terraform: `terraform fmt` always; module layout consistent and readable

---

## 3) Common Commands (Shortcuts)

### Build/Run
- `pwsh .\<script>.ps1 [-Verbose] [-WhatIf]`
- `terraform init`
- `terraform plan`
- `terraform apply` (**Warning:** Ensure remote backend first)

### Test
- `Invoke-Pester` (when scripts/modules warrant tests)
- `terraform validate`

### Lint/Check
- `Invoke-ScriptAnalyzer -Path .\ -Recurse`
- `terraform fmt -recursive` (and `-check` when enforcing)

---

## 4) Architecture & Security

### Sensitive data rules (default-safe)
- **Never** hardcode credentials/tokens/secrets/certs.
- Prefer: secure prompt, vault reference, or managed identity patterns.
- When sharing output outside internal IT, **sanitize** by default:
  - emails, tenant IDs, device names, serials, asset IDs, internal hostnames, IPs, screenshots with identifiers
- If Jeremy pastes lots of raw content or sensitive identifiers:
  - **Flag it** + suggest redactions for future sharing.

### Azure / cloud specifics
- Azure-first (AWS only if explicitly needed).
- **Terraform State:** **Never** use local state; always enforce `remote` or `cloud` backend to prevent locking/loss.
- Tagging standard (minimum):
  - `CostCenter`, `Owner`, `Environment`, `Application` (or `Service`)
- Prefer Managed Identity > client secrets (where possible).
- Modules: start generic, then align to internal best practices once available.

### Logging expectations
- Operator-grade logging: timestamp, severity, action, target, result
- Prefer:
  - `Start-Transcript` when appropriate
  - a simple `Write-Log` helper (INFO/WARN/ERROR) writing to a predictable path:
    - `C:\Logs\<ScriptName>.log` or `.\Logs\<ScriptName>.log`

---

## 5) Output Formats Jeremy Uses Most

### Ticket / Teams update format (default)
- **BLUF (1–2 lines):** what happened + current status
- **Impact:** who/what is affected
- **Action taken:** bullets
- **Next steps:** owner + due date (if known)
- **Ask / decision needed:** if applicable

### KB / Runbook format (default)
- Title (system + task + scope)
- Symptoms / Trigger
- Environment / Preconditions
- Step-by-step (copy/paste commands)
- Validation ("what good looks like")
- Rollback / Safety notes
- References / links
- Owner + Last verified date

---

## 6) Leadership / Team-Lead / Manager Mode

> Treat leadership work like an **ops system**: templates, repeatable workflows, metrics, and clear comms.

### What Claude should generate in leadership mode
- **Weekly status updates** (team + projects): accomplishments, risks, next week, asks
- **1:1 agendas**: wins, blockers, growth, commitments, follow-ups
- **Project governance artifacts**:
  - RAID (Risks/Assumptions/Issues/Dependencies)
  - Decision log (date, decision, rationale, owner)
  - RACI (Responsible/Accountable/Consulted/Informed)
  - Stakeholder update template (exec-friendly)
- **Delegation-ready task breakdowns**:
  - tasks with acceptance criteria, definition of done, and handoff notes
- **Performance / growth**:
  - development plans per teammate, skill matrices, shadowing plans, quarterly goals
- **Vendor/finance support**:
  - quote comparison tables, renewal tracking, licensing cleanup plans, Opex notes

### How Claude should "sound" in leadership mode
- Concise, professional, operator tone
- Bias to clarity: owners, dates, decisions, and next steps
- No fluff; don't over-explain standard stuff
- If ambiguous: make a best guess and state assumptions explicitly

### "Claude Code" leadership automations (examples)
- Turn exports into leadership summaries:
  - Jira/BMC export → weekly dashboard + top blockers
  - Lansweeper export → lifecycle counts by site/cost center
  - NinjaOne patch/CVE export → remediation scorecard
- Generate repeatable templates:
  - RAID + Decision log in markdown
  - Meeting minutes → action items with owners/dates
- Lightweight scripts:
  - Normalize/clean data for reporting (CSV → clean CSV)
  - Redaction/sanitization helper for sharing examples externally

---

## 7) Claude Behavior (Default)

### Tone
- Paste-ready, structured, practical
- Junior-friendly explanations only when it helps decision-making

### Reasoning
- Explain non-obvious choices (cmdlet/flag/order-of-ops)
- Don't explain basic syntax unless asked
- Always include validation + rollback notes when changes are involved

### Safety / privacy
- If input looks too sensitive: call it out and suggest redactions
- Prefer generalized placeholders in examples:
  - `USER@COMPANY.COM`, `DEVICE1234`, `TENANT_ID`, `10.x.x.x`

---

## 8) Quick Templates (copy/paste)

### Weekly status (team lead)
- **Wins:**
- **In-progress:**
- **Risks/Blockers:**
- **Next week focus:**
- **Asks / Decisions needed:**

### 1:1 agenda
- **Quick personal check-in (2 min)**
- **Wins since last time**
- **Blockers / where I can help**
- **Growth / learning focus**
- **Commitments before next 1:1** (owner + date)

### Decision log entry
- **Date:**
- **Decision:**
- **Rationale:**
- **Owner:**
- **Impacted systems/teams:**
- **Follow-ups:**

---

## Shell Cheat Sheet (Bash vs PowerShell)

### How to tell which shell you're in
- **Bash (WSL):** prompt looks like `jeremy@Shoop:~/...$`
- **PowerShell:** prompt looks like `PS C:\Users\jsp6\...>`

### Rule of thumb
- If you see **here-doc syntax** like `<<EOF` or `<<'EOF'` → run in **Bash**
- If you see **PowerShell here-string** like `@' ... '@` → run in **PowerShell**

### Creating files safely

**Bash (WSL):**
```bash
cat > path/to/file.md <<'EOF'
content here
EOF
```

**PowerShell:**
```powershell
@'
content here
'@ | Set-Content -LiteralPath path\to\file.md -Encoding utf8
```

### Common mistake
- Copying the **bash file-creation command** into a `.ps1` file makes PowerShell throw parser errors.
- `.ps1` files must contain **PowerShell code only**.

### Public-safe content (GitHub hygiene)
- Do **not** commit real internal domains, hostnames, share paths, usernames, ticket numbers, or customer data.
- Use neutral examples like `example.com` and `\\server01\share\...`.
