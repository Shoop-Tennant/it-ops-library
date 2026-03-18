# Laptop Rebuild Checklist

**Purpose:** Complete step-by-step setup guide for rebuilding the primary dev laptop from scratch.
**Environment:** Windows 11 + WSL2, IT Systems Analyst / Team Lead workstation
**Last verified:** 2026-03-18

---

## Phase 0 — Before You Wipe

- [ ] Verify Google Drive is fully synced (`C:\Users\jerem\My Drive\` — green checkmarks in tray)
- [ ] Verify GitHub repos are fully pushed (`git status` clean on all clones)
- [ ] Export browser bookmarks + profiles
- [ ] Export VS Code settings (Settings Sync or manual export)
- [ ] Note any local secrets not in Google Drive (check `Workspace\Secrets\`)
- [ ] Screenshot or export NinjaOne/Intune device record (serial, asset tag)
- [ ] Note Bitlocker recovery key location

---

## Phase 1 — Windows 11 Base Install

- [ ] Install Windows 11 (clean install or OEM recovery)
- [ ] Run Windows Update — full pass until no updates remain
- [ ] Sign in to Microsoft account (links OneDrive + activation)
- [ ] Sign in to Google Drive for Desktop — wait for sync to complete
- [ ] Verify `C:\Users\jerem\My Drive\Workspace\` appears and is populated

---

## Phase 2 — Core CLI Tools

Open **Windows Terminal** (PowerShell tab) for all steps below.

### Winget (verify it's available)
```powershell
winget --version
```
If missing: update **App Installer** from Microsoft Store.

### PowerShell 7
```powershell
winget install -e --id Microsoft.PowerShell
pwsh -v
```

### Git
```powershell
winget install -e --id Git.Git
git --version
```

### Node.js LTS (required for Claude Code, Codex, Gemini)
```powershell
winget install -e --id OpenJS.NodeJS.LTS
```
Restart terminal, then verify:
```powershell
node -v
npm -v
```

### VS Code
```powershell
winget install -e --id Microsoft.VisualStudioCode
code --version
```

### ripgrep
```powershell
winget install -e --id BurntSushi.ripgrep.MSVC
rg --version
```

### GitHub CLI
```powershell
winget install -e --id GitHub.cli
gh auth login
```

---

## Phase 3 — WSL2 Setup

```powershell
# Enable WSL2 (requires restart)
wsl --install
# After restart:
wsl --set-default-version 2
wsl --install -d Ubuntu
```

Once Ubuntu is running, update and install base tools:
```bash
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y git curl wget unzip build-essential
```

### WSL Git config
```bash
git config --global user.name "Jeremy Shoop"
git config --global user.email "your@email.com"
git config --global core.autocrlf false
git config --global core.eol lf
```

### WSL SSH key
```bash
ssh-keygen -t ed25519 -C "laptop-wsl2-$(date +%Y%m%d)"
cat ~/.ssh/id_ed25519.pub
# Add to GitHub: Settings → SSH Keys
```

---

## Phase 4 — AI CLI Stack

### Claude Code
```powershell
npm install -g @anthropic-ai/claude-code
claude --version
```
Auth:
```powershell
claude
# Follow prompts to authenticate with Anthropic account
```

### Codex CLI
```powershell
npm install -g @openai/codex
codex --version
```

### Gemini CLI
```powershell
npm install -g @google/gemini-cli
gemini --help
```

### Verify all CLIs
```powershell
claude --version
codex --version
gemini --help
node -v
npm -v
rg --version
pwsh -v
```

---

## Phase 5 — Clone Repos

```powershell
# Workspace is already on Google Drive — just clone into the Repos folder
Set-Location "C:\Users\jerem\My Drive\Workspace\Repos"
git clone https://github.com/Shoop-Tennant/it-ops-library.git
Set-Location .\it-ops-library
git status
```

Open in VS Code:
```powershell
code "C:\Users\jerem\My Drive\Workspace\Repos\it-ops-library"
```

Or open the workspace file directly:
```powershell
code "C:\Users\jerem\My Drive\Workspace\Repos\it-ops-library\.vscode\it-ops-library.code-workspace"
```

---

## Phase 6 — VS Code Extensions

Install via command palette (`Ctrl+Shift+X`) or CLI:

```powershell
# WSL integration
code --install-extension ms-vscode-remote.remote-wsl

# PowerShell
code --install-extension ms-vscode.powershell

# Git
code --install-extension eamodio.gitlens

# Markdown
code --install-extension yzhang.markdown-all-in-one

# Terraform
code --install-extension hashicorp.terraform

# GitHub Copilot (if licensed)
code --install-extension github.copilot
```

Enable Settings Sync (if using):
- `Ctrl+Shift+P` → "Settings Sync: Turn On"

---

## Phase 7 — PATH and Launchers

### Add npm global bin to PATH (if not automatic)
```powershell
$npmBin = npm config get prefix
$currentPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notlike "*$npmBin*") {
    [System.Environment]::SetEnvironmentVariable("PATH", "$currentPath;$npmBin", "User")
    Write-Host "Added $npmBin to PATH. Restart terminal."
}
```

### Restore Tools launchers to PATH
The `ws.cmd`, `ws-claude.cmd`, etc. launchers live at:
```
C:\Users\jerem\My Drive\Workspace\Tools\bin\
```

Add to user PATH:
```powershell
$toolsBin = "C:\Users\jerem\My Drive\Workspace\Tools\bin"
$currentPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notlike "*$toolsBin*") {
    [System.Environment]::SetEnvironmentVariable("PATH", "$currentPath;$toolsBin", "User")
    Write-Host "Added Tools\bin to PATH. Restart terminal."
}
```

Verify:
```powershell
where.exe ws.cmd
ws.cmd
```

---

## Phase 8 — Backup Script

Update and verify `Backup-WorkspaceToNAS.ps1`:
```powershell
# Correct source path (Google Drive location)
# C:\Users\jerem\My Drive\Workspace\

# Verify NAS share is accessible
Test-Path "\\TRUENAS\jeremy\backups"

# Run manually to verify
pwsh "C:\Users\jerem\My Drive\Workspace\Tools\Backup-WorkspaceToNAS.ps1"
```

---

## Phase 9 — Proxmox / Homelab Access

### SSH access to Proxmox nodes
```bash
# From WSL2 — distribute new laptop key to all nodes
# (run from it-ops-library repo root)
bash terraform/proxmox-homelab/setup-ssh-keys.sh
```

Or manually:
```bash
for NODE in 192.168.4.10 192.168.4.11 192.168.4.12 192.168.4.13; do
  ssh-copy-id -i ~/.ssh/id_ed25519.pub root@$NODE
done
```

### Verify homelab services
```bash
# AnythingLLM
curl -s http://192.168.4.20:3001 | head -5

# Ollama (P4000)
curl -s http://192.168.4.16:11434/api/tags | python3 -m json.tool

# Ollama (A4500)
curl -s http://192.168.4.15:11434/api/tags | python3 -m json.tool

# LiteLLM
curl -s http://192.168.4.20:4000/health | python3 -m json.tool
```

---

## Phase 10 — Final Sanity Checks

```powershell
# Run from repo root in PowerShell
Set-Location "C:\Users\jerem\My Drive\Workspace\Repos\it-ops-library"

git status                    # should be: nothing to commit
git remote get-url origin     # should show github.com/Shoop-Tennant/it-ops-library
claude --version
codex --version
node -v
npm -v
rg --version
pwsh -v
gh auth status
```

```bash
# Run from WSL2
cd "/mnt/c/Users/jerem/My Drive/Workspace/Repos/it-ops-library"
git status
ssh-add -l                   # confirm SSH agent has key loaded
ssh root@192.168.4.10 'pvecm status'  # confirm homelab access
```

---

## Troubleshooting

### "Command not found" after npm install
Close and reopen terminal (PATH refresh), then:
```powershell
where.exe <tool>
npm config get prefix
```

### winget blocked by policy
Use direct installers:
- Node.js: download LTS `.msi` from nodejs.org
- PowerShell 7: download `.msi` from github.com/PowerShell/PowerShell/releases (per-user option)
- VS Code: download "User Installer" from code.visualstudio.com (no admin)
- ripgrep: download `rg.exe` from github.com/BurntSushi/ripgrep/releases, place in PATH

### WSL2 DNS broken on VPN
WSL2 networking disrupts with some VPNs. Workaround:
```bash
echo -e "[network]\ngenerateResolvConf = false" | sudo tee /etc/wsl.conf
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
```
**Preferred:** Use native Windows PowerShell when on VPN.

### Google Drive not syncing
- Check tray icon — must show green checkmarks, not spinning
- If stuck: sign out and back in to Google Drive for Desktop
- Do NOT proceed to wipe until sync is fully complete

### SSH_AUTH_SOCK not available in Claude Bash tool
Claude Code's Bash tool does not inherit SSH_AUTH_SOCK. To use SSH:
```bash
# Find the agent socket
ls /tmp/ssh-*/agent.*

# Test each
SSH_AUTH_SOCK=/tmp/ssh-XXXXX/agent.NNNNN ssh-add -l

# Prepend to any SSH command
export SSH_AUTH_SOCK=/tmp/ssh-XXXXX/agent.NNNNN
ssh root@192.168.4.10 'pvecm status'
```

---

## References

| Resource | Location |
|:---------|:---------|
| Repo | `C:\Users\jerem\My Drive\Workspace\Repos\it-ops-library\` |
| Homelab state | `terraform/proxmox-homelab/SESSION_RESUME.md` |
| Environment source of truth | `docs/state/ENVIRONMENT.md` |
| AI CLI stack setup | `docs/setup/windows-ai-cli-stack.md` |
| Backup script | `C:\Users\jerem\My Drive\Workspace\Tools\Backup-WorkspaceToNAS.ps1` |
| GitHub | github.com/Shoop-Tennant/it-ops-library |
