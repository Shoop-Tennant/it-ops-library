# Homelab Operations Scripts

Operational scripts for the **Shoop-Homelab** Proxmox cluster.

**Cluster:** 4-node Proxmox 9.1.1 | Network: `192.168.4.0/22` | Gateway: `192.168.4.1`

---

## Quick Reference

| Script | Purpose | Key Flag |
|:-------|:--------|:---------|
| `deploy-vm.sh` | Deploy VM from template | `--dry-run` |
| `gpu-passthrough-setup.sh` | Configure VFIO on a node | `--dry-run` |
| `cluster-health.sh` | Full cluster health check | `--quiet` |
| `vm-troubleshoot.sh` | Diagnose a specific VM | `--fix-boot-disk` |
| `ollama-install.sh` | Install NVIDIA + Ollama on AI node | `--dry-run` |

**All scripts:** support `--dry-run` | log to `logs/YYYY-MM-DD.log` | exit 0=OK, 1=error, 2=usage

---

## Prerequisites

```bash
# SSH agent loaded with your key
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# SSH key must be in /root/.ssh/authorized_keys on all Proxmox nodes.
# Add via Proxmox web UI console if not already done:
#   echo "$(cat ~/.ssh/id_ed25519.pub)" >> /root/.ssh/authorized_keys

# Make scripts executable
chmod +x scripts/*.sh
```

---

## deploy-vm.sh

Deploy a VM from the `ubuntu-2404-cloud` template.

```bash
# Syntax
./deploy-vm.sh [--dry-run] <node> <vmid> <name> <ip> <cores> <ram_mb> <disk>

# Examples
./deploy-vm.sh pve01 200 test-vm 192.168.4.50 4 8192 50G
./deploy-vm.sh pve02 201 dev-box 192.168.4.51 8 16384 100G
./deploy-vm.sh --dry-run pve01 202 staging 192.168.4.52 4 8192 50G

# With custom cloud-init user
CI_USER=admin ./deploy-vm.sh pve01 200 my-vm 192.168.4.50 4 8192 50G
```

**What it does:**
1. Validates args and SSH connectivity
2. Clones `ubuntu-2404-cloud` template
3. Sets CPU, RAM, disk size
4. Configures cloud-init (user, SSH key, static IP)
5. Starts VM and waits for SSH

**Node IPs:**

| Node | IP |
|:-----|:---|
| pve01 | 192.168.4.10 |
| pve02 | 192.168.4.11 |
| pve03-7090 | 192.168.4.12 |
| pve04-7090 | 192.168.4.13 |

**IP allocation guidelines:**

| Range | Use |
|:------|:----|
| .1 | Gateway (Eero) |
| .2 | pihole-dns |
| .5 | TrueNAS |
| .10–.13 | Proxmox nodes |
| .15 | ai-node-a4500 |
| .16 | ai-node-p4000 |
| .20 | ubuntu-docker |
| .50+ | Free for new VMs |

---

## gpu-passthrough-setup.sh

Configure VFIO/IOMMU on a Proxmox node so a GPU can be passed through to a VM.

```bash
# Syntax
./gpu-passthrough-setup.sh [--dry-run] <node> <pci_address>

# Examples
./gpu-passthrough-setup.sh pve01 0000:01:00        # Quadro P4000
./gpu-passthrough-setup.sh pve02 0000:01:00        # RTX A4500 (GA104GLM)
./gpu-passthrough-setup.sh --dry-run pve01 0000:01:00

# Discover PCI address first
ssh root@192.168.4.10 'lspci -nn | grep NVIDIA'
```

**What it does:**
1. Checks IOMMU enabled (`dmesg | grep -i iommu`)
2. Auto-discovers GPU and audio device IDs
3. Checks IOMMU group isolation
4. Writes `/etc/modprobe.d/vfio.conf`
5. Adds vfio modules to `/etc/modules`
6. Blacklists nouveau/nvidia on host
7. Runs `update-initramfs -u -k all`
8. **Requires reboot** to activate

**GPU reference:**

| Node | GPU | PCI Address | Device IDs |
|:-----|:----|:------------|:-----------|
| pve01 | Quadro P4000 (GP104GL) | 0000:01:00.0 | 10de:1bb1, 10de:228b |
| pve02 | RTX A4500 (GA104GLM — laptop variant) | 0000:01:00.0 | 10de:24ba, 10de:228b |

> **Warning:** The A4500 in pve02 is a laptop GPU variant (`0x24ba`). It works but is more
> likely to cause boot loops than the workstation P4000. Always test base VM boot before attaching.

**After reboot, verify:**
```bash
ssh root@pve01 'cat /sys/bus/pci/devices/0000:01:00.0/driver/module/drivers'
# Expected: pci:vfio-pci
```

---

## cluster-health.sh

Full cluster validation — quorum, APIs, NFS, GPUs, key VMs.

```bash
# Standard run
./cluster-health.sh

# Quiet (suppress per-check output, only show errors)
./cluster-health.sh --quiet

# Suppress terminal output entirely
./cluster-health.sh --quiet 2>&1 | grep -E "FAIL|WARN"
```

**Checks performed:**

| Check | Description |
|:------|:------------|
| SSH connectivity | Primary node reachable |
| Quorum | `pvecm status` — all 4 nodes voting |
| Node APIs | HTTP 200 on all 4 node APIs, PVE version |
| NFS storage | `truenas-nfs` available on all nodes |
| GPU presence | P4000 on pve01, A4500 on pve02 via lspci |
| VFIO binding | GPU bound to vfio-pci (passthrough-ready) |
| Key VMs | ubuntu-docker, ai-node-a4500, ai-node-p4000 |
| Guest agents | Agent responding on running VMs |
| Corosync | Ring0 IPs match current /22 addressing |

**Output:**
- Terminal: colorized ✅/❌/⚠️
- Markdown: `logs/cluster-health-YYYY-MM-DD.md`
- Exit 0 = all healthy, 1 = any failure

---

## vm-troubleshoot.sh

Diagnose a specific VM and get actionable fix suggestions.

```bash
# Syntax
./vm-troubleshoot.sh <vmid> [node] [--fix-boot-disk]

# Auto-detect which node the VM is on
./vm-troubleshoot.sh 100

# Specify node for faster lookup
./vm-troubleshoot.sh 100 pve02

# Attempt automatic boot disk fix (for Terraform unused0 issue)
./vm-troubleshoot.sh 100 --fix-boot-disk
```

**Diagnoses:**

| Check | What it detects |
|:------|:----------------|
| Node location | Which Proxmox node owns the VMID |
| Run state | running/stopped/paused |
| Full config | `qm config` output |
| Boot disk | bootdisk vs actual disk slots |
| Disk orphans | `unused*` disks from Terraform clone mismatch |
| Network | ipconfig0 format, /22 prefix check |
| GPU | hostpci config, vfio binding, q35 machine type |
| Guest agent | Config enabled + live ping |
| SSH | Reachability at configured IP |
| Cloud-init | Status via guest agent |

**Common issues it detects:**

| Issue | Cause | Fix |
|:------|:------|:----|
| `unused0` in config | Terraform disk slot mismatch | `--fix-boot-disk` flag |
| `bootdisk` not in config | Wrong boot disk reference | Script provides exact command |
| Guest agent not responding | Not installed in VM | Script provides install command |
| SSH not reachable | Cloud-init network failed | Script provides netplan fix |
| GPU driver not vfio-pci | VFIO not configured | Directs to `gpu-passthrough-setup.sh` |

---

## ollama-install.sh

Install NVIDIA drivers (optional) + Ollama on an AI node VM.

```bash
# Syntax
./ollama-install.sh [--dry-run] <vm_ip> <mode>

# GPU mode (P4000 node — pve01)
./ollama-install.sh 192.168.4.16 gpu

# GPU mode (A4500 node — pve02)
./ollama-install.sh 192.168.4.15 gpu

# CPU mode (any VM)
./ollama-install.sh 192.168.4.50 cpu

# Dry run
./ollama-install.sh --dry-run 192.168.4.16 gpu

# Custom model
OLLAMA_MODEL=llama3.2:3b ./ollama-install.sh 192.168.4.16 gpu
```

**What it installs:**

| Phase | CPU Mode | GPU Mode |
|:------|:---------|:---------|
| 0. qemu-guest-agent | ✅ | ✅ |
| 1. System updates | ✅ | ✅ |
| 2. NVIDIA driver 550 | ❌ | ✅ |
| 3. Ollama (latest) | ✅ | ✅ |
| 4. Model pull + test | ✅ | ✅ |

**After install:**
```bash
# API endpoint
curl http://192.168.4.16:11434/api/generate \
  -d '{"model":"qwen2.5:7b","prompt":"Hello","stream":false}'

# List models
ssh ubuntu@192.168.4.16 'ollama list'

# GPU status
ssh ubuntu@192.168.4.16 'nvidia-smi'
```

---

## Logging

All scripts append to `logs/YYYY-MM-DD.log`. Specific outputs:

| File | Created by |
|:-----|:-----------|
| `logs/YYYY-MM-DD.log` | All scripts |
| `logs/cluster-health-YYYY-MM-DD.md` | cluster-health.sh |
| `logs/nvidia-smi-<ip>.txt` | ollama-install.sh (gpu) |
| `logs/inference-timing-<ip>.txt` | ollama-install.sh |

```bash
# Follow today's log
tail -f logs/$(date +%Y-%m-%d).log

# View all cluster health reports
ls -lt logs/cluster-health-*.md | head

# Search for errors
grep "\[FAIL\]\|\[ERROR\]" logs/$(date +%Y-%m-%d).log
```

---

## Common Workflows

### Deploy and configure a new AI node

```bash
# 1. Deploy VM from template
./deploy-vm.sh pve01 205 ai-node-new 192.168.4.55 8 24576 30G

# 2. Troubleshoot if needed
./vm-troubleshoot.sh 205

# 3. Configure GPU passthrough on host (if not already done)
./gpu-passthrough-setup.sh pve01 0000:01:00
# ssh root@pve01 'reboot'  # if VFIO not yet active

# 4. Attach GPU to VM (after VFIO active)
SSH_NODE=pve01; VM_ID=205; GPU_PCI=0000:01:00
ssh root@192.168.4.10 "pvesh set /nodes/${SSH_NODE}/qemu/${VM_ID}/config --hostpci0 ${GPU_PCI},pcie=1,rombar=1"

# 5. Install Ollama
./ollama-install.sh 192.168.4.55 gpu
```

### Full cluster health check (daily/weekly)

```bash
./cluster-health.sh
# Report: logs/cluster-health-$(date +%Y-%m-%d).md
```

### Debug a VM that won't boot

```bash
# Run diagnostics
./vm-troubleshoot.sh <vmid>

# If boot disk mismatch found (Terraform unused0 issue)
./vm-troubleshoot.sh <vmid> --fix-boot-disk

# If GPU causing boot loop
ssh root@<node-ip> 'qm set <vmid> --delete hostpci0 && qm start <vmid>'

# Access serial console
ssh root@<node-ip> 'qm terminal <vmid>'
```

---

## Key Commands (Proxmox)

```bash
# Cluster
pvecm status                     # quorum + node list
pvecm nodes                      # node IDs

# VM management
qm list                          # all VMs on this node
qm status <VMID>
qm start/stop/reboot <VMID>
qm config <VMID>                 # full config
qm set <VMID> --delete hostpci0  # remove GPU
qm agent <VMID> ping             # test guest agent
qm terminal <VMID>               # serial console (Ctrl+O to exit)

# Disk operations
qm resize <VMID> virtio0 120G
qm set <VMID> --boot order=virtio0

# GPU discovery
lspci -nn | grep NVIDIA
lspci -nn | grep 10de
find /sys/kernel/iommu_groups/ -type l | grep 01:00
cat /sys/bus/pci/devices/0000:01:00.0/driver/module/drivers
```
