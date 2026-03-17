# Session Resume — Proxmox Homelab Deployment
**Last session:** 2026-03-16
**Pick up from:** Both GPU nodes operational, AnythingLLM deployed

---

## Current Infrastructure State

| VM | ID | Node | IP | Status |
|:---|:---|:-----|:---|:-------|
| ubuntu-docker | 100 | pve02 | 192.168.4.20 | Running — Docker 29.3.0, Compose v5.1.0, AnythingLLM |
| ai-node-a4500 | 102 | pve02 | 192.168.4.15 | GPU Ollama — RTX A4500 Laptop (16GB), NVIDIA 580.126.09, qwen2.5:7b |
| ai-node-p4000 | 103 | pve01 | 192.168.4.16 | GPU Ollama — Quadro P4000 (8GB), NVIDIA 580.126.09, qwen2.5:7b + nomic-embed-text |

### Services

| Service | Host | URL | Backend |
|:--------|:-----|:----|:--------|
| AnythingLLM | ubuntu-docker | http://192.168.4.20:3001 | Ollama @ 192.168.4.15:11434 (RTX A4500) |
| LiteLLM Proxy | ubuntu-docker | http://192.168.4.20:4000 | Dual-GPU: gpt-3.5→P4000, gpt-4→A4500 |
| Ollama (P4000) | ai-node-p4000 | http://192.168.4.16:11434 | Quadro P4000, 8GB VRAM |
| Ollama (A4500) | ai-node-a4500 | http://192.168.4.15:11434 | RTX A4500 Laptop, 16GB VRAM |

---

## What Was Completed This Session

- A4500 GPU passthrough on pve02 — FIXED (was DMA -22, now working)
  - Added /etc/modprobe.d/vfio-pci.conf: disable_vga=1, disable_idle_d3=1
  - Added kernel param: video=efifb:off
  - VM hostpci0: 0000:01:00,pcie=1,rombar=0 (rombar=0 key for laptop GPU)
  - nvidia-smi: RTX A4500 Laptop GPU, 16384 MiB VRAM, 0.10s inference
- Deployed AnythingLLM on ubuntu-docker (http://192.168.4.20:3001)
  - Connected to Ollama on ai-node-p4000 (192.168.4.16:11434)
  - Pulled nomic-embed-text embedding model on P4000 node
  - Compose at /opt/anythingllm/docker-compose.yml
- Fixed pve01 template 9000 (missing OS disk — imported ubuntu-2404-cloud.img)
- Terraform apply: ai-node-p4000 VM 103 created on pve01
- P4000 GPU passthrough deployed: NVIDIA 580.126.09, qwen2.5:7b on GPU
- Set Ollama to 0.0.0.0:11434 on both AI nodes

---

## GPU Passthrough Summary

### pve01 — Quadro P4000

| Item | Value |
|:-----|:------|
| GPU | Quadro P4000 (GP104GL) |
| PCI ID | 10de:1bb1 + 10de:10f0 |
| VRAM | 8192 MiB |
| hostpci | 0000:01:00,pcie=1,rombar=1 |
| Config | Standard VFIO (no laptop workarounds needed) |

### pve02 — RTX A4500 Laptop GPU

| Item | Value |
|:-----|:------|
| GPU | RTX A4500 Laptop GPU (GA104GLM) |
| PCI ID | 10de:24ba + 10de:228b |
| VRAM | 16384 MiB |
| hostpci | 0000:01:00,pcie=1,rombar=0 |
| Laptop workarounds | disable_vga=1, disable_idle_d3=1, video=efifb:off, rombar=0 |

---

## Cluster Quorum (still degraded)

**Current state:** `pvecm expected 1` on both pve01 and pve02.
**Root cause:** pve03 + pve04 offline. Corosync ring has stale IPs.
**Fix needed:** Update corosync.conf or remove offline nodes.

---

## Known Issues / Outstanding Work

| Priority | Issue | Fix |
|:---------|:------|:----|
| MED | Cluster quorum degraded (pve03/pve04 offline) | Investigate or remove from cluster |
| MED | Corosync ring0 IPs stale | Update `/etc/pve/corosync.conf` |
| LOW | ubuntu-docker TF drift (bootdisk: scsi0) | Check `terraform plan` before applying |
| LOW | pve01 template scsi0 vs TF virtio0 | Deploy script handles swap |
| LOW | AnythingLLM could use A4500 as secondary backend | Point to 192.168.4.15:11434 for 16GB models |

---

## Terraform State

```
proxmox_lxc.pihole               → 192.168.4.2  (pve01)
proxmox_vm_qemu.ubuntu_docker    → 192.168.4.20 (pve02)
proxmox_vm_qemu.ai_node_a4500   → 192.168.4.15 (pve02) — RTX A4500 16GB GPU
proxmox_vm_qemu.ai_node_p4000   → 192.168.4.16 (pve01) — Quadro P4000 8GB GPU
```

---

## Key Files

| File | Purpose |
|:-----|:--------|
| `ai-node-p4000.tf` | P4000 AI node VM config (pve01) |
| `ai-node-p4000-deploy.sh` | P4000 deploy: disk fix + GPU + NVIDIA + Ollama |
| `ai-node-a4500.tf` | A4500 AI node VM config (pve02) |
| `ai-node-deploy.sh` | A4500 deploy script |
| `ubuntu-docker-vm.tf` | Docker host VM config |
| `deploy.sh` | ubuntu-docker deploy script |
| `GPU_VALIDATION.txt` | lspci + IOMMU group details |
| `ANYTHINGLLM_DEPLOYMENT.txt` | AnythingLLM setup and access |
| `A4500_ADVANCED_VFIO_ATTEMPTS.txt` | Laptop GPU passthrough workarounds |

---

## Resume Prompt

```
We're continuing Proxmox homelab deployment work.
Repo: C:/Workspace/Repos/it-ops-library/terraform/proxmox-homelab/
Read SESSION_RESUME.md for full context.

Both AI GPU nodes fully operational:
- ai-node-p4000 (VM 103, pve01): Quadro P4000 8GB, Ollama @ 192.168.4.16:11434
- ai-node-a4500 (VM 102, pve02): RTX A4500 16GB, Ollama @ 192.168.4.15:11434
- AnythingLLM: http://192.168.4.20:3001 (backed by P4000)

Remaining work:
- pve03/pve04 offline (connection error 595)
- Corosync cluster cleanup
- Optional: Point AnythingLLM at A4500 for larger models (16GB VRAM)
```
