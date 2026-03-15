# Deployment Report — Proxmox Homelab
**Generated:** 2026-03-15 15:48:14

> **IMPORTANT:** All SSH/SCP operations failed — WSL2 execution environment does not have
> L3 network routing to homelab LAN (192.168.4.0/24). Results below reflect attempted
> execution. Items marked ❌ require re-running from a host with network access to the homelab
> (e.g., directly from the Proxmox nodes, or via a jump host on the 192.168.4.0/24 subnet).

---

## Cluster Quorum
- Quorate: ❌ UNKNOWN (SSH unreachable)
- Nodes voting: ❌ UNKNOWN / 4
- Command attempted: `pvecm status` on pve01 (192.168.4.10)

---

## Node Health

| Node | IP | API (8006) | NFS Mounted | IOMMU/DMAR |
|------|----|-----------|-------------|------------|
| pve01 | 192.168.4.10 | ❌ Unreachable | ❌ Unreachable | ❌ Unreachable |
| pve02 | 192.168.4.11 | ❌ Unreachable | ❌ Unreachable | ❌ Unreachable |
| pve03-7090 | 192.168.4.12 | ❌ Unreachable | ❌ Unreachable | ❌ Unreachable |
| pve04-7090 | 192.168.4.13 | ❌ Unreachable | ❌ Unreachable | ❌ Unreachable |

**Commands attempted per node:**
- `curl -sk https://127.0.0.1:8006/api2/json/version`
- `df -h | grep truenas-nfs`
- `dmesg | grep -e DMAR -e IOMMU | head -5`

---

## GPU PCI Addresses

| Node | GPU Model | PCI ID | Formatted Address |
|------|-----------|--------|-------------------|
| pve01 | Quadro P4000 | 10de:1bb1 | ❌ UNKNOWN (SSH unreachable) |
| pve02 | RTX A4500 | 10de:25b6 | ❌ UNKNOWN (SSH unreachable) |

**File:** `terraform/proxmox-homelab/GPU_PCI_ADDRESSES.txt`
**To populate:** SSH into each node and run `lspci -nn | grep <device_id>`

---

## Docker VM (ubuntu-docker @ 192.168.4.20)

| Check | Status | Detail |
|-------|--------|--------|
| Static IP confirmed | ❌ UNKNOWN | SSH unreachable |
| qemu-guest-agent | ❌ UNKNOWN | SSH unreachable |
| Docker installed | ❌ UNKNOWN | SSH unreachable |
| Docker version | ❌ UNKNOWN | SSH unreachable |
| Docker Compose version | ❌ UNKNOWN | SSH unreachable |
| hello-world test | ❌ UNKNOWN | SSH unreachable |

---

## /etc/hosts Sync

| Node | File Deployed | Ping pve01 | Ping pve02 |
|------|--------------|------------|------------|
| pve01 | ❌ SCP failed | N/A | N/A |
| pve02 | ❌ SCP failed | N/A | N/A |
| pve03-7090 | ❌ SCP failed | N/A | N/A |
| pve04-7090 | ❌ SCP failed | N/A | N/A |

**Local file written:** `etc.hosts.cluster` (ready to SCP when network access is available)

---

## NFS Mount Status

| Node | Mounted | Mount Path |
|------|---------|------------|
| pve01 | ❌ UNKNOWN | truenas-nfs (192.168.4.5) |
| pve02 | ❌ UNKNOWN | truenas-nfs (192.168.4.5) |
| pve03-7090 | ❌ UNKNOWN | truenas-nfs (192.168.4.5) |
| pve04-7090 | ❌ UNKNOWN | truenas-nfs (192.168.4.5) |

---

## Root Cause: Network Isolation

The WSL2 shell used for this deployment run does not have a route to the homelab LAN
(192.168.4.0/24). This is expected when running Claude Code from the Windows host rather
than from inside the homelab network.

**To re-run successfully, execute from one of:**
1. Directly on a Proxmox node (jump via web terminal)
2. A host on the 192.168.4.0/24 LAN with the SSH key deployed to all nodes
3. A VPN/tunnel connecting this host to the homelab network

**SSH key required:** The `id_ed25519` key at `~/.ssh/id_ed25519` must be authorized
on all Proxmox nodes (`/root/.ssh/authorized_keys`).

---

## Files Generated This Run

| File | Status |
|------|--------|
| `terraform/proxmox-homelab/GPU_PCI_ADDRESSES.txt` | ✅ Written (addresses TBD) |
| `etc.hosts.cluster` | ✅ Written (ready to deploy) |
| `DEPLOYMENT_REPORT.md` | ✅ This file |
| `NEXT_STEPS.md` | ✅ Written |
| `DEPLOYMENT_LOG_20260315_154413.txt` | ✅ Written |

---

## Next Steps
See **NEXT_STEPS.md**
