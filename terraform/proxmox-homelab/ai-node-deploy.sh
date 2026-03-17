#!/usr/bin/env bash
# ai-node-deploy.sh — Post-Terraform setup for ai-node-a4500
# Installs NVIDIA drivers, CUDA, and Ollama. Verifies GPU passthrough.
#
# Prerequisites:
#   - terraform apply has completed (VM exists and is running)
#   - eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519
#   - ~/.ssh/config has an 'ai-node' entry (added by this script if missing)
#
# Usage: bash ai-node-deploy.sh

set -euo pipefail
cd "$(dirname "$0")"

SKIP_GPU=false
for arg in "$@"; do
  [ "$arg" = "--skip-gpu" ] && SKIP_GPU=true
done

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTFILE="AI_NODE_DEPLOYMENT_${TIMESTAMP}.txt"
AI_IP="192.168.4.15"
AI_USER="ubuntu"
AI_HOST="ai-node"

log()  { local msg="[$(date +%H:%M:%S)] $*";    echo "$msg"; echo "$msg" >> "$OUTFILE"; }
ok()   { local msg="[$(date +%H:%M:%S)] ✅ $*"; echo "$msg"; echo "$msg" >> "$OUTFILE"; }
warn() { local msg="[$(date +%H:%M:%S)] ⚠️  $*"; echo "$msg"; echo "$msg" >> "$OUTFILE"; }
fail() { local msg="[$(date +%H:%M:%S)] ❌ $*"; echo "$msg"; echo "$msg" >> "$OUTFILE"; }

SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no"

# Use the 'ai-node' SSH alias so ProxyJump through pve02 applies automatically
ai() { ssh $SSH_OPTS "${AI_HOST}" "$@" 2>&1 | tee -a "$OUTFILE"; }

# ─────────────────────────────────────────────────────────────────────────────
# SSH CONFIG: add ai-node entry if missing
# ─────────────────────────────────────────────────────────────────────────────
if ! grep -q "Host ai-node" ~/.ssh/config 2>/dev/null; then
    log "Adding ai-node to ~/.ssh/config..."
    cat >> ~/.ssh/config <<EOF

Host ai-node
    HostName ${AI_IP}
    User ${AI_USER}
    ProxyJump root@192.168.4.11
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
EOF
    ok "ai-node added to ~/.ssh/config"
fi

# ─────────────────────────────────────────────────────────────────────────────
# PRE-FLIGHT
# ─────────────────────────────────────────────────────────────────────────────
log "=== PRE-FLIGHT: SSH connectivity to pve02 and ai-node ==="

if ! ssh $SSH_OPTS pve02 'hostname' &>/dev/null; then
    fail "SSH to pve02 failed — run: eval \"\$(ssh-agent -s)\" && ssh-add ~/.ssh/id_ed25519"
    exit 1
fi
ok "pve02 reachable"

log "Finding ai-node-a4500 VM ID on pve02..."
VM_ID_EARLY=$(ssh $SSH_OPTS pve02 "qm list | grep ai-node-a4500 | awk '{print \$1}'" 2>/dev/null | tr -d '[:space:]' || echo "")
if [ -z "$VM_ID_EARLY" ]; then
    fail "Cannot find ai-node-a4500 on pve02 — did terraform apply succeed?"
    exit 1
fi
log "VM ID: $VM_ID_EARLY"

log "Checking for orphaned OS disk (unused0 from template clone)..."
UNUSED=$(ssh $SSH_OPTS pve02 "qm config ${VM_ID_EARLY} | grep '^unused0'" 2>/dev/null || echo "")
if [ -n "$UNUSED" ]; then
    log "Found unused0 (OS disk): $UNUSED — fixing disk layout..."
    ssh $SSH_OPTS pve02 "qm stop ${VM_ID_EARLY} --timeout 30" 2>/dev/null || true
    sleep 5
    # Remove the empty virtio0 placeholder disk
    ssh $SSH_OPTS pve02 "qm set ${VM_ID_EARLY} --delete virtio0" 2>&1 | tee -a "$OUTFILE"
    # Move OS disk to virtio0
    DISK_NAME=$(echo "$UNUSED" | awk -F': ' '{print $2}' | awk -F',' '{print $1}')
    ssh $SSH_OPTS pve02 "qm set ${VM_ID_EARLY} --virtio0 ${DISK_NAME}" 2>&1 | tee -a "$OUTFILE"
    # Resize to 120G
    ssh $SSH_OPTS pve02 "qm resize ${VM_ID_EARLY} virtio0 120G" 2>&1 | tee -a "$OUTFILE"
    # Fix boot order
    ssh $SSH_OPTS pve02 "qm set ${VM_ID_EARLY} --boot order=virtio0" 2>&1 | tee -a "$OUTFILE"
    ok "Disk layout fixed — OS on virtio0 at 120G"
    # Start VM
    ssh $SSH_OPTS pve02 "qm start ${VM_ID_EARLY}" 2>&1 | tee -a "$OUTFILE"
    log "Waiting 90s for cloud-init after disk fix..."
    sleep 90
else
    ok "No unused0 found — disk layout looks correct"
fi

log "Waiting for ai-node SSH (via ProxyJump pve02 → ${AI_IP})..."
SSH_ATTEMPTS=0
until ssh $SSH_OPTS "${AI_HOST}" 'hostname' &>/dev/null; do
    SSH_ATTEMPTS=$((SSH_ATTEMPTS + 1))
    if [ "$SSH_ATTEMPTS" -ge 12 ]; then
        fail "ai-node not reachable after 3 minutes — check VM console: ssh pve02 then: qm terminal ${VM_ID_EARLY}"
        exit 1
    fi
    warn "Attempt $SSH_ATTEMPTS/12 — retrying in 15s..."
    sleep 15
done
ok "ai-node SSH: connected"

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 0: Attach GPU via pvesh (Terraform can't set mapped PCI devices)
# ─────────────────────────────────────────────────────────────────────────────
if [ "$SKIP_GPU" = true ]; then
    log "=== PHASE 0: GPU attachment SKIPPED (--skip-gpu) — running CPU-only mode ==="
    log "GPU can be added later: pvesh set /nodes/pve02/qemu/\${VM_ID}/config --hostpci0 mapping=rtx-a4500,pcie=1"
else

log ""
log "=== PHASE 0: Attach RTX A4500 via pvesh ==="

VM_ID=$(echo "$VM_ID_EARLY" | tr -d '[:space:]')
if [ -z "$VM_ID" ]; then
    fail "Could not find ai-node-a4500 VM ID on pve02"
    exit 1
fi
log "VM ID: $VM_ID"

HOSTPCI=$(ssh $SSH_OPTS pve02 "qm config ${VM_ID} | grep hostpci0" 2>/dev/null || echo "")
if echo "$HOSTPCI" | grep -q "rtx-a4500\|01:00"; then
    ok "hostpci0 already set: $HOSTPCI"
else
    log "Stopping VM to attach GPU..."
    ssh $SSH_OPTS pve02 "qm stop ${VM_ID} --timeout 30" 2>&1 | tee -a "$OUTFILE" || true
    sleep 5
    log "Attaching RTX A4500 (mapping=rtx-a4500)..."
    ssh $SSH_OPTS pve02 "pvesh set /nodes/pve02/qemu/${VM_ID}/config \
        --hostpci0 mapping=rtx-a4500,pcie=1,rombar=1" 2>&1 | tee -a "$OUTFILE"
    ok "hostpci0 set"
    log "Starting VM..."
    ssh $SSH_OPTS pve02 "qm start ${VM_ID}" 2>&1 | tee -a "$OUTFILE"
    log "Waiting 60s for boot after GPU attach..."
    sleep 60
    SSH_ATTEMPTS=0
    until ssh $SSH_OPTS "${AI_USER}@${AI_IP}" 'hostname' &>/dev/null; do
        SSH_ATTEMPTS=$((SSH_ATTEMPTS + 1))
        if [ "$SSH_ATTEMPTS" -ge 8 ]; then
            fail "VM did not come back after GPU attach — check: ssh pve02 'qm terminal ${VM_ID}'"
            exit 1
        fi
        warn "Post-attach SSH attempt $SSH_ATTEMPTS/8 — waiting 15s..."
        sleep 15
    done
    ok "VM back online with GPU attached"
fi # end inner hostpci check

fi # end SKIP_GPU check

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 1: Disk resize (template disk ~8GB, need 120GB)
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "=== PHASE 1: Disk resize ==="

DISK_SIZE=$(ai 'df -h / | awk "NR==2{print \$2}"' 2>/dev/null || echo "unknown")
log "Current root disk size: $DISK_SIZE"

if echo "$DISK_SIZE" | grep -qE "^[0-9]+(\.[0-9]+)?G$"; then
    SIZE_GB=$(echo "$DISK_SIZE" | grep -oE '[0-9]+')
    if [ "$SIZE_GB" -lt 50 ]; then
        log "Disk is ${DISK_SIZE} — resizing to 120G on Proxmox side..."
        VM_ID=$(ssh $SSH_OPTS pve02 'qm list | grep ai-node-a4500 | awk "{print \$1}"' 2>/dev/null || echo "")
        if [ -z "$VM_ID" ]; then
            warn "Could not auto-detect VM ID — trying ID 101"
            VM_ID="101"
        fi
        log "VM ID: $VM_ID"
        ssh $SSH_OPTS pve02 "qm resize ${VM_ID} scsi0 120G" 2>&1 | tee -a "$OUTFILE"
        log "Expanding partition inside VM..."
        ai 'sudo growpart /dev/sda 1 && sudo resize2fs /dev/sda1' || \
        ai 'sudo growpart /dev/vda 1 && sudo resize2fs /dev/vda1' || \
            warn "growpart failed — may need manual resize"
        DISK_SIZE=$(ai 'df -h / | awk "NR==2{print \$2}"')
        ok "Disk after resize: $DISK_SIZE"
    else
        ok "Disk already ${DISK_SIZE} — no resize needed"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2: System update
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "=== PHASE 2: System update ==="

ai 'sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq'
ok "System updated"

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 3: NVIDIA drivers
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "=== PHASE 3: NVIDIA driver install (nvidia-driver-550) ==="

# Check if GPU is visible inside the VM
GPU_CHECK=$(ai 'lspci | grep -i nvidia' 2>/dev/null || true)
if echo "$GPU_CHECK" | grep -qi "nvidia"; then
    ok "GPU visible inside VM: $GPU_CHECK"
else
    warn "No NVIDIA GPU visible in lspci — passthrough may not be active"
    warn "Check: ssh pve02 'qm config <vmid> | grep hostpci'"
    echo "$GPU_CHECK" >> "$OUTFILE"
fi

ai 'sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nvidia-driver-550 nvidia-utils-550' \
    2>&1 | tee -a "$OUTFILE"
ok "NVIDIA driver 550 installed"

log "Rebooting for driver activation..."
ssh $SSH_OPTS "${AI_USER}@${AI_IP}" 'sudo reboot' || true
sleep 5

log "Waiting 90s for reboot..."
sleep 90

SSH_ATTEMPTS=0
until ssh $SSH_OPTS "${AI_HOST}" 'hostname' &>/dev/null; do
    SSH_ATTEMPTS=$((SSH_ATTEMPTS + 1))
    if [ "$SSH_ATTEMPTS" -ge 8 ]; then
        fail "VM did not come back after reboot — check console: ssh pve02 then: qm terminal ${VM_ID_EARLY}"
        exit 1
    fi
    warn "Post-reboot SSH attempt $SSH_ATTEMPTS/8 — waiting 15s..."
    sleep 15
done
ok "VM back online after reboot"

log "Verifying GPU with nvidia-smi..."
NVIDIA_SMI=$(ai 'nvidia-smi' 2>&1 || true)
echo "$NVIDIA_SMI" >> "$OUTFILE"
echo "$NVIDIA_SMI"

if echo "$NVIDIA_SMI" | grep -qi "RTX A4500\|A4500\|GA104"; then
    ok "nvidia-smi: RTX A4500 confirmed"
elif echo "$NVIDIA_SMI" | grep -qi "NVIDIA"; then
    ok "nvidia-smi: NVIDIA GPU detected"
    warn "GPU model string unexpected — verify it's the A4500"
else
    fail "nvidia-smi did not detect GPU — check passthrough config"
fi

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 4: Ollama install
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "=== PHASE 4: Ollama install ==="

ai 'curl -fsSL https://ollama.com/install.sh | sh' 2>&1 | tee -a "$OUTFILE"
ai 'sudo systemctl enable --now ollama' 2>&1 | tee -a "$OUTFILE"
sleep 5

OLLAMA_STATUS=$(ai 'systemctl is-active ollama' 2>/dev/null || echo "unknown")
if [ "$OLLAMA_STATUS" = "active" ]; then
    ok "Ollama service: active"
else
    warn "Ollama service status: $OLLAMA_STATUS"
fi

OLLAMA_VER=$(ai 'ollama --version' 2>/dev/null || echo "unknown")
log "Ollama version: $OLLAMA_VER"

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 5: Pull model and test inference
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "=== PHASE 5: Model pull + inference test (qwen2.5:7b) ==="

log "Pulling qwen2.5:7b (this may take several minutes)..."
ai 'ollama pull qwen2.5:7b' 2>&1 | tee -a "$OUTFILE"
ok "qwen2.5:7b pulled"

log "Running inference test (via REST API)..."
INFERENCE=$(ai 'curl -s http://localhost:11434/api/generate \
    -d "{\"model\":\"qwen2.5:7b\",\"prompt\":\"Say hello in exactly 5 words\",\"stream\":false}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)[\"response\"])" 2>/dev/null || echo ""')
echo "$INFERENCE" >> "$OUTFILE"
if [ -n "$INFERENCE" ]; then
    ok "Inference test: responded"
    log "Response: $INFERENCE"
else
    warn "Inference returned empty response"
fi

# GPU memory check
GPU_MEM=$(ai "nvidia-smi --query-gpu=name,memory.total,memory.used --format=csv,noheader" 2>/dev/null || true)
log "GPU memory: $GPU_MEM"
echo "$GPU_MEM" >> "$OUTFILE"

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "=== DEPLOYMENT COMPLETE ==="
log "Output: $OUTFILE"
log ""
ok "ai-node-a4500 is ready at ${AI_IP}"
log "  SSH:    ssh ai-node"
log "  Ollama: http://${AI_IP}:11434"
log "  Models: ssh ai-node 'ollama list'"
