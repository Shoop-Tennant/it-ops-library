# Session Handoff — Chat 1.0 → Chat 2.0

**Date:** 2026-03-18
**Repo:** `Shoop-Tennant/it-ops-library` (main, clean)
**Last commit:** `6cf80d7` — ops: add setup-ssh-keys.sh to distribute WSL key to all Proxmox nodes

---

## Workspace — Canonical Paths (UPDATED)

> Workspace was consolidated to Google Drive this session. All old `C:\Workspace` paths are now `C:\Users\jerem\My Drive\Workspace`.

| Context | Path |
|:--------|:-----|
| Windows | `C:\Users\jerem\My Drive\Workspace\` |
| WSL | `/mnt/c/Users/jerem/My Drive/Workspace/` |
| Repo (Windows) | `C:\Users\jerem\My Drive\Workspace\Repos\it-ops-library\` |
| Repo (WSL) | `/mnt/c/Users/jerem/My Drive/Workspace/Repos/it-ops-library/` |
| Docs (GDrive synced) | `C:\Users\jerem\My Drive\Workspace\Docs\` |
| Tools | `C:\Users\jerem\My Drive\Workspace\Tools\` |

**Backup at:** `C:\Workspace-Backup-20260318_170229\` (old location, safe to delete after verification)

**Files needing path updates (do before deleting old workspace):**
- `C:\Users\jerem\My Drive\Workspace\Tools\Backup-WorkspaceToNAS.ps1` — update source path
- `docs/state/ENVIRONMENT.md` — still reflects old `C:\Workspace` paths (update in Chat 2.0)
- `terraform/proxmox-homelab/SESSION_RESUME.md` — resume prompt references old path (update in Chat 2.0)

---

## Infrastructure State (as of 2026-03-16, SESSION_RESUME.md)

### Proxmox Cluster

| VM | ID | Node | IP | Status |
|:---|:---|:-----|:---|:-------|
| ubuntu-docker | 100 | pve02 | 192.168.4.20 | Running — Docker 29.3.0, Compose v5.1.0, AnythingLLM |
| ai-node-a4500 | 102 | pve02 | 192.168.4.15 | Running — RTX A4500 Laptop 16GB, Ollama, qwen2.5:7b |
| ai-node-p4000 | 103 | pve01 | 192.168.4.16 | Running — Quadro P4000 8GB, Ollama, qwen2.5:7b + nomic-embed-text |

### Services

| Service | Host | URL |
|:--------|:-----|:----|
| AnythingLLM | ubuntu-docker | http://192.168.4.20:3001 |
| LiteLLM Proxy | ubuntu-docker | http://192.168.4.20:4000 |
| Ollama (P4000) | ai-node-p4000 | http://192.168.4.16:11434 |
| Ollama (A4500) | ai-node-a4500 | http://192.168.4.15:11434 |

### Cluster Quorum (degraded)
- pve03 + pve04 are offline
- Both pve01 + pve02 are running `pvecm expected 1`
- **Fix needed:** Update or remove offline nodes from corosync.conf

### GPU Passthrough
- **pve01 — Quadro P4000:** Standard VFIO, `rombar=1`, working
- **pve02 — RTX A4500 Laptop (GA104GLM):** Required laptop workarounds:
  - `/etc/modprobe.d/vfio-pci.conf`: `disable_vga=1`, `disable_idle_d3=1`
  - Kernel param: `video=efifb:off`
  - VM hostpci: `rombar=0` (laptop VBIOS — critical)

---

## Repo State

### Branches
- `main` — clean, fully pushed
- `quest/agent-assisted` — ready to prep; needs `PowerShell/` → `powershell/` rename, then PR
- `feature/ninjaone-patching` — merged (PR #6 closed)

### Active Quests
1. **Repo Front Door + Standards** (in progress) — README, standards, MCP guide, repo map, workflow
2. **Quest 2: Backup-WorkspaceToNAS.ps1** — extend to cover Tools\ and Scratch\ (not started)
3. **Proxmox: Cluster quorum cleanup** — pve03/pve04 offline, corosync stale IPs
4. **Proxmox: Terraform drift** — ubuntu-docker has `bootdisk: scsi0` vs TF `virtio0`; check plan before apply

### Key State Files
| File | Purpose |
|:-----|:--------|
| `docs/state/ENVIRONMENT.md` | Dev environment source of truth (needs path update) |
| `docs/state/WHERE_I_LEFT_OFF.md` | Last-known clean state (2026-03-01) |
| `docs/state/QUEST_LOG.md` | Active and completed quests |
| `terraform/proxmox-homelab/SESSION_RESUME.md` | Homelab infrastructure state |
| `NEXT_STEPS.md` | Proxmox deployment next steps |

---

## Dev Environment

- **OS:** Windows 11 + WSL2 (Ubuntu)
- **Editor:** VS Code (WSL extension or native Windows)
- **Primary AI CLI:** Claude Code (`claude`)
- **Also installed:** Codex CLI (`codex`), Gemini CLI (`gemini`)
- **Shell preference:** PowerShell native on VPN; WSL2 otherwise
- **Git identity:** GitHub user `Shoop-Tennant`
- **SSH auth socket:** Not inherited by Claude Bash tool — find with `ls /tmp/ssh-*/agent.*` and test each

### AI Stack (Workspace)
- `C:\Users\jerem\My Drive\Workspace\AI\cache\` — model cache
- `C:\Users\jerem\My Drive\Workspace\AI\logs\` — inference logs
- `C:\Users\jerem\My Drive\Workspace\AI\models\` — local models

---

## What Was Done in Chat 1.0

1. **Workspace path audit** — identified mismatch between handoff doc (`C:\Users\jerem\My Drive\Workspace`) and reality (`C:\Workspace`)
2. **Consolidation script created** — `Tools/consolidate-to-google-drive.sh`
3. **Workspace consolidated** — all dirs moved/cloned to `C:\Users\jerem\My Drive\Workspace\`
4. **it-ops-library re-cloned** — fresh clone from GitHub origin at new path
5. **Backup created** — `C:\Workspace-Backup-20260318_170229\`
6. **Old workspace preserved** — delete pending your verification

---

## Immediate Tasks for Chat 2.0

### Priority 1 — Housekeeping (do first)
- [ ] Verify old workspace can be deleted: `rm -rf /mnt/c/Workspace`
- [ ] Update `ENVIRONMENT.md` paths from `C:\Workspace` → `C:\Users\jerem\My Drive\Workspace`
- [ ] Update `SESSION_RESUME.md` resume prompt path
- [ ] Update `Backup-WorkspaceToNAS.ps1` source path in Tools

### Priority 2 — Repo Work
- [ ] Fix `quest/agent-assisted`: rename `PowerShell/` → `powershell/`, open PR
- [ ] Continue Repo Front Door quest: finalize README, standards, MCP guide

### Priority 3 — Homelab
- [ ] Clean up corosync cluster (pve03/pve04 offline nodes)
- [ ] Run `terraform plan` on ubuntu-docker to check bootdisk drift

---

## Prompt to Resume in Chat 2.0

```
We're continuing from SESSION_HANDOFF_1.0_to_2.0.md in it-ops-library.

Repo: /mnt/c/Users/jerem/My Drive/Workspace/Repos/it-ops-library/
Read SESSION_HANDOFF_1.0_to_2.0.md for full context.

Workspace was consolidated to Google Drive this session — all paths now under:
  Windows: C:\Users\jerem\My Drive\Workspace\
  WSL: /mnt/c/Users/jerem/My Drive/Workspace/

Start with Priority 1 housekeeping tasks listed in the handoff doc.
```
