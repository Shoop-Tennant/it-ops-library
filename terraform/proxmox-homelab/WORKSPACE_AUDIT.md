# Workspace Audit — Proxmox Homelab
**Date:** 2026-03-16

---

## 1. Git Status

**Branch:** main (up to date with origin/main)
**Modified (4):** GPU_PCI_ADDRESSES.txt, outputs.tf, ubuntu-docker-vm.tf, variables.tf
**Untracked (38):** All new files from this session — TF configs, scripts, deploy logs, docs

### Action needed: Commit and push

---

## 2. File Organization Issues

### Deployment logs (should NOT be committed)
These are timestamped script output logs — ephemeral, large, contain terminal escape codes.
**Total: 2.5 MB of noise across 15 log files.**

| File | Size | Verdict |
|:-----|:-----|:--------|
| AI_NODE_DEPLOYMENT_20260316_152447.txt | 1.2 MB | Gitignore |
| P4000_GPU_DEPLOYMENT_20260316_191719.txt | 1.3 MB | Gitignore |
| DEPLOYMENT_COMPLETE_20260315_201305.txt | 41 KB | Gitignore |
| AI_NODE_DEPLOYMENT_*.txt (9 more) | ~10 KB each | Gitignore |
| DEPLOYMENT_COMPLETE_*.txt (2 more) | ~6 KB each | Gitignore |
| DEPLOYMENT_LOG_*.txt | 7 KB | Gitignore |
| VM_REBUILD_SUCCESS_*.txt (2) | ~12 KB total | Gitignore |
| P4000_GPU_DEPLOYMENT_20260316_191159.txt | 1 KB | Gitignore |
| OLLAMA_GPU_TEST.txt | 0.5 KB | Gitignore |
| GPU_VERIFICATION.txt | 2 KB | Gitignore |

### Documentation (SHOULD be committed)
| File | Purpose | Commit? |
|:-----|:--------|:--------|
| SESSION_RESUME.md | Session state for resume | Yes |
| FULL_DEPLOYMENT_REPORT.md | Architecture overview | Yes |
| ANYTHINGLLM_DEPLOYMENT.txt | AnythingLLM setup guide | Yes |
| ANYTHINGLLM_UPGRADE.txt | P4000→A4500 migration | Yes |
| LITELLM_DEPLOYMENT.txt | LiteLLM proxy setup | Yes |
| A4500_ADVANCED_VFIO_ATTEMPTS.txt | Laptop GPU passthrough fix | Yes |
| GPU_VALIDATION.txt | IOMMU/PCI reference | Yes |
| GPU_PCI_ADDRESSES.txt | PCI address reference | Yes |
| NEXT_STEPS.md | Future work | Yes |

### Terraform configs (SHOULD be committed)
| File | Commit? |
|:-----|:--------|
| ai-node-a4500.tf | Yes |
| ai-node-p4000.tf | Yes |
| outputs.tf (modified) | Yes |
| ubuntu-docker-vm.tf (modified) | Yes |
| variables.tf (modified) | Yes |

### Scripts (SHOULD be committed)
| File | Commit? |
|:-----|:--------|
| deploy.sh | Yes |
| ai-node-deploy.sh | Yes |
| ai-node-p4000-deploy.sh | Yes |
| rebuild.sh | Yes |
| scripts/ (directory) | Yes |

### Should NOT be committed
| File | Reason |
|:-----|:-------|
| rebuild.tfplan | Binary plan file, environment-specific |
| terraform.tfvars | Already in root .gitignore (secrets) |

---

## 3. Script Permissions

All scripts show `rwxrwxrwx` — this is expected on `/mnt/c/` (Windows filesystem).
WSL mounts NTFS with full perms. No chmod needed.

---

## 4. SSH Config

All hosts present and correct:
- pve01 (192.168.4.10) — direct
- pve02 (192.168.4.11) — direct
- pve03-7090 (192.168.4.12) — direct
- pve04-7090 (192.168.4.13) — direct
- ubuntu-docker (192.168.4.20) — ProxyJump via pve02
- ai-node (192.168.4.15) — ProxyJump via pve02
- ai-node-p4000 (192.168.4.16) — ProxyJump via pve01

**No issues.**

---

## 5. Skills

- ~/skills/user/proxmox-homelab/SKILL.md exists
- No .claude/skills/ directory (skills loaded from ~/skills/)

**No issues.**

---

## 6. Claude Memory

- ~/.claude/projects/-mnt-c-Workspace/memory/MEMORY.md exists (1.3 KB)
- No context.md (not required, CLAUDE.md at repo root handles this)

**No issues.**

---

## 7. Remote Docker Compose

Both configs present on ubuntu-docker:
- /opt/anythingllm/docker-compose.yml — AnythingLLM (port 3001)
- /opt/litellm/config.yaml + docker-compose.yml — LiteLLM (port 4000)
- Both containers running and healthy

**No issues.**

---

## 8. Recommended .gitignore

Add to `terraform/proxmox-homelab/.gitignore`:

```
# Deployment logs (timestamped script output)
*_DEPLOYMENT_*.txt
DEPLOYMENT_COMPLETE_*.txt
DEPLOYMENT_LOG_*.txt
VM_REBUILD_SUCCESS_*.txt
P4000_GPU_DEPLOYMENT_*.txt
OLLAMA_GPU_TEST.txt
GPU_VERIFICATION.txt

# Terraform artifacts
*.tfplan
.terraform/
.terraform.lock.hcl

# Claude session data
.claude/
```

---

## 9. Recommended Commit Plan

**Commit 1:** Add .gitignore
**Commit 2:** Add AI node Terraform configs + scripts
  - ai-node-a4500.tf, ai-node-p4000.tf
  - ai-node-deploy.sh, ai-node-p4000-deploy.sh
  - deploy.sh, rebuild.sh, scripts/
  - Modified: outputs.tf, ubuntu-docker-vm.tf, variables.tf
**Commit 3:** Add documentation
  - SESSION_RESUME.md, FULL_DEPLOYMENT_REPORT.md, NEXT_STEPS.md
  - ANYTHINGLLM_DEPLOYMENT.txt, ANYTHINGLLM_UPGRADE.txt
  - LITELLM_DEPLOYMENT.txt, A4500_ADVANCED_VFIO_ATTEMPTS.txt
  - GPU_VALIDATION.txt, GPU_PCI_ADDRESSES.txt
