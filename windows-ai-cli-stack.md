# Windows AI CLI Stack Setup (Primary Dev on Windows)

## Goal

Make Windows the primary environment for this repo:
- Clone `it-ops-library` on Windows
- Install Claude Code CLI
- Install Node.js LTS (needed for Codex CLI + Gemini CLI via npm)
- Install Codex CLI + Gemini CLI
- Install useful add-ons (PowerShell 7, ripgrep, VS Code, etc.)
- Verify everything works
- Keep secrets safe (no keys committed)

> **Current status:** Claude Code and Codex CLI are already installed. Resume from Step 5 (Gemini CLI) or run Step 7 sanity checks to confirm full state.

---

## Guardrails (Do Not Break These)

- **Do not commit** API keys, tokens, cookies, internal domains, hostnames, or share paths.
- Keep examples sanitized: `example.com`, `server01`, `\\server01\share\...`.
- Only make file changes inside this repo clone:
  - `C:\Users\jsp6\git\it-ops-library`

---

## Step 0 — Prereqs checklist

Open **Windows Terminal** (PowerShell tab) and verify:

```powershell
git --version
winget --version
```

If `winget` is missing: install/update **App Installer** from Microsoft Store, then retry.

---

## Step 1 — Clone the repo on Windows (Primary Clone)

```powershell
New-Item -ItemType Directory -Path C:\Users\jsp6\git -Force | Out-Null
Set-Location C:\Users\jsp6\git

git clone https://github.com/Shoop-Tennant/it-ops-library.git
Set-Location .\it-ops-library

git status
```

### Normalize line endings (avoid churn)

```powershell
git config core.autocrlf false
git config core.eol lf
```

---

## Step 2 — Install Node.js LTS (Required for npm-based CLIs)

```powershell
winget install -e --id OpenJS.NodeJS.LTS
```

Restart terminal (PATH refresh), then verify:

```powershell
node -v
npm -v
```

---

## Step 3 — Install Claude Code CLI ✅ Already installed

> Skip if already installed. Verify with `claude --version`.

Install via npm (requires Node.js from Step 2):

```powershell
npm install -g @anthropic-ai/claude-code
```

Verify:

```powershell
where.exe claude
claude --version
```

If `where.exe claude` returns nothing, close and reopen the terminal (PATH refresh).

Docs: https://docs.anthropic.com/en/docs/claude-code

---

## Step 4 — Install OpenAI Codex CLI ✅ Already installed

> Skip if already installed. Verify with `codex --version`.

```powershell
npm install -g @openai/codex
```

Verify:

```powershell
where.exe codex
codex --version
```

First run — auth (interactive):

```powershell
codex
```

---

## Step 5 — Install Google Gemini CLI

```powershell
npm install -g @google/gemini-cli
```

Verify:

```powershell
where.exe gemini
gemini --help
```

First run — auth (interactive):

```powershell
gemini
```

---

## Step 6 — Recommended add-ons (Quality of life)

### PowerShell 7 (pwsh)

```powershell
winget install -e --id Microsoft.PowerShell
pwsh -v
```

### ripgrep (rg) for fast searching

```powershell
winget install -e --id BurntSushi.ripgrep.MSVC
rg --version
```

### VS Code (if not installed)

```powershell
winget install -e --id Microsoft.VisualStudioCode
code --version
```

Open the repo:

```powershell
code C:\Users\jsp6\git\it-ops-library
```

### GitHub CLI (optional but useful)

```powershell
winget install -e --id GitHub.cli
gh --version
```

---

## Step 7 — Sanity checks (must pass)

From repo root:

```powershell
Set-Location C:\Users\jsp6\git\it-ops-library

git status
claude --version
codex --version
gemini --help
node -v
npm -v
rg --version
pwsh -v
```

---

## Step 8 — Repo workflow rules

- **Windows is the primary clone**: commit and push from Windows.
- WSL2 is optional/reference only. VPN can interfere with WSL2 networking — prefer native Windows when on VPN.
- Avoid committing from both Windows and WSL to prevent line-ending conflicts.

---

## Troubleshooting

### "Command not found" after install

Close and reopen the terminal (PATH refresh), then recheck:

```powershell
where.exe <tool>
```

If still missing, confirm the npm global bin path is in PATH:

```powershell
npm config get prefix
# Typical result: C:\Users\jsp6\AppData\Roaming\npm

[System.Environment]::GetEnvironmentVariable("PATH", "User")
```

Add it to PATH if missing:

```powershell
$npmBin = npm config get prefix
$currentPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notlike "*$npmBin*") {
    [System.Environment]::SetEnvironmentVariable("PATH", "$currentPath;$npmBin", "User")
    Write-Host "Added $npmBin to PATH. Restart terminal."
}
```

---

### No admin / winget blocked

If winget is unavailable or blocked by policy:

**Node.js — direct installer (no winget):**
1. Download LTS `.msi` from [nodejs.org](https://nodejs.org/)
2. Run installer — it sets PATH automatically
3. Restart terminal and verify `node -v`

**Node.js — per-user install via nvm-windows (no admin needed):**
1. Download the nvm-windows installer from [github.com/coreybutler/nvm-windows/releases](https://github.com/coreybutler/nvm-windows/releases)
2. Choose per-user install (no admin prompt)
3. Then:

```powershell
nvm install lts
nvm use lts
node -v
```

**PowerShell 7 — per-user MSI:**
- Download from [github.com/PowerShell/PowerShell/releases](https://github.com/PowerShell/PowerShell/releases)
- Choose the `.msi` per-user option (no admin)

**VS Code — per-user installer:**
- Download "User Installer" from [code.visualstudio.com](https://code.visualstudio.com/)
- No admin required

**ripgrep — portable binary:**
1. Download `rg.exe` from [github.com/BurntSushi/ripgrep/releases](https://github.com/BurntSushi/ripgrep/releases)
2. Place in a folder on your PATH (e.g., `C:\Users\jsp6\bin\`)

---

### VPN and WSL2 networking

WSL2 uses a virtual network adapter that some VPNs disrupt (DNS or routing breaks while on VPN).

**Preferred:** Use native Windows PowerShell for all work while on VPN — no WSL2 needed.

**WSL2 DNS workaround** (may not survive VPN reconnects):

```bash
# Run inside WSL2
echo -e "[network]\ngenerateResolvConf = false" | sudo tee /etc/wsl.conf
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
```

---

### Claude Code install issues

If `npm install -g @anthropic-ai/claude-code` fails:
- Verify Node.js is installed: `node -v`
- Check npm global prefix: `npm config get prefix`
- Try: `npm install -g @anthropic-ai/claude-code --no-fund --no-audit`
- See official docs: https://docs.anthropic.com/en/docs/claude-code

---

## References

| Tool | Package | Source |
|---|---|---|
| Node.js LTS | `OpenJS.NodeJS.LTS` (winget) | [nodejs.org](https://nodejs.org/) |
| Claude Code | `@anthropic-ai/claude-code` (npm) | [docs.anthropic.com/en/docs/claude-code](https://docs.anthropic.com/en/docs/claude-code) |
| Codex CLI | `@openai/codex` (npm) | [github.com/openai/codex](https://github.com/openai/codex) |
| Gemini CLI | `@google/gemini-cli` (npm) | [github.com/google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli) |
| nvm-windows | per-user Node.js mgr | [github.com/coreybutler/nvm-windows](https://github.com/coreybutler/nvm-windows) |
