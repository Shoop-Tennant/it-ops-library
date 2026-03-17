#!/usr/bin/env bash
# ai-node-p4000-deploy.sh — Post-Terraform setup for ai-node-p4000
# Attaches Quadro P4000, installs NVIDIA drivers + Ollama, verifies GPU inference.
#
# Prerequisites:
#   - terraform apply has completed (VM exists and is running)
#   - eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519
#   - pve01 VFIO configured (vfio-pci bound to 01:00.0 and 01:00.1)
#
# Usage:
#   bash ai-node-p4000-deploy.sh              # full deploy with GPU
#   bash ai-node-p4000-deploy.sh --skip-gpu   # CPU-only (skip GPU attach + NVIDIA)

set -euo pipefail
cd "$(dirname "$0")"

SKIP_GPU=false
for arg in "$@"; do
  [ "$arg" = "--skip-gpu" ] && SKIP_GPU=true
done

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTFILE="P4000_GPU_DEPLOYMENT_${TIMESTAMP}.txt"
AI_IP="192.168.4.16"
AI_USER="ubuntu"
AI_HOST="ai-node-p4000"
PVE_HOST="pve01"
PVE_IP="192.168.4.10"
GPU_PCI="0000:01:00"   # covers 01:00.0 (GPU) + 01:00.1 (audio) as a group

log()  { local msg="[$(date +%H:%M:%S)] $*";    echo "$msg"; echo "$msg" >> "$OUTFILE"; }
ok()   { local msg="[$(date +%H:%M:%S)] ✅ $*"; echo "$msg"; echo "$msg" >> "$OUTFILE"; }
warn() { local msg="[$(date +%H:%M:%S)] ⚠️  $*"; echo "$msg"; echo "$msg" >> "$OUTFILE"; }
fail() { local msg="[$(date +%H:%M:%S)] ❌ $*"; echo "$msg"; echo "$msg" >> "$OUTFILE"; }

SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no"

# ai() runs a command on the AI node VM
ai() { ssh $SSH_OPTS "${AI_HOST}" "$@" 2>&1 | tee -a "$OUTFILE"; }

# ─────────────────────────────────────────────────────────────────────────────
# SSH CONFIG: add ai-node-p4000 entry if missing
# ─────────────────────────────────────────────────────────────────────────────
if ! grep -q "Host ai-node-p4000" ~/.ssh/config 2>/dev/null; then
    log "Adding ai-node-p4000 to ~/.ssh/config..."
    cat >> ~/.ssh/config <<EOF

Host ai-node-p4000
    HostName ${AI_IP}
    User ${AI_USER}
    ProxyJump root@${PVE_IP}
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
EOF
    ok "ai-node-p4000 added to ~/.ssh/config"
fi

# ─────────────────────────────────────────────────────────────────────────────
# PRE-FLIGHT
# ─────────────────────────────────────────────────────────────────────────────
log "=== PRE-FLIGHT: SSH connectivity to ${PVE_HOST} and ai-node-p4000 ==="

if ! ssh $SSH_OPTS ${PVE_HOST} 'hostname' &>/dev/null; then
    fail "SSH to ${PVE_HOST} failed — run: eval \"\$(ssh-agent -s)\" && ssh-add ~/.ssh/id_ed25519"
    exit 1
fi
ok "${PVE_HOST} reachable"

log "Finding ai-node-p4000 VM ID on ${PVE_HOST}..."
VM_ID=$(ssh $SSH_OPTS ${PVE_HOST} "qm list | grep ai-node-p4000 | awk '{print \$1}'" 2>/dev/null | tr -d '[:space:]' || echo "")
if [ -z "$VM_ID" ]; then
    fail "Cannot find ai-node-p4000 on ${PVE_HOST} — did terraform apply succeed?"
    exit 1
fi
ok "VM ID: $VM_ID"

# ─────────────────────────────────────────────────────────────────────────────
# DISK FIX: move unused0 (OS disk) → virtio0, resize to 120G
# ─────────────────────────────────────────────────────────────────────────────
log "Checking for orphaned OS disk (unused0 from template clone)..."
UNUSED=$(ssh $SSH_OPTS ${PVE_HOST} "qm config ${VM_ID} | grep '^unused0'" 2>/dev/null || echo "")
if [ -n "$UNUSED" ]; then
    log "Found unused0: $UNUSED — fixing disk layout..."
    ssh $SSH_OPTS ${PVE_HOST} "qm stop ${VM_ID} --timeout 30" 2>/dev/null || true
    sleep 5
    ssh $SSH_OPTS ${PVE_HOST} "qm set ${VM_ID} --delete virtio0" 2>&1 | tee -a "$OUTFILE"
    DISK_NAME=$(echo "$UNUSED" | awk -F': ' '{print $2}' | awk -F',' '{print $1}')
    ssh $SSH_OPTS ${PVE_HOST} "qm set ${VM_ID} --virtio0 ${DISK_NAME}" 2>&1 | tee -a "$OUTFILE"
    ssh $SSH_OPTS ${PVE_HOST} "qm resize ${VM_ID} virtio0 120G" 2>&1 | tee -a "$OUTFILE"
    ssh $SSH_OPTS ${PVE_HOST} "qm set ${VM_ID} --boot order=virtio0" 2>&1 | tee -a "$OUTFILE"
    ok "Disk layout fixed — OS on virtio0 at 120G"
    ssh $SSH_OPTS ${PVE_HOST} "qm start ${VM_ID}" 2>&1 | tee -a "$OUTFILE"
    log "Waiting 90s for cloud-init after disk fix..."
    sleep 90
else
    ok "No unused0 — disk layout correct"
fi

log "Waiting for ai-node-p4000 SSH..."
SSH_ATTEMPTS=0
until ssh $SSH_OPTS "${AI_HOST}" 'hostname' &>/dev/null; do
    SSH_ATTEMPTS=$((SSH_ATTEMPTS + 1))
    if [ "$SSH_ATTEMPTS" -ge 12 ]; then
        fail "ai-node-p4000 not reachable after 3 minutes"
        fail "Check console: ssh ${PVE_HOST} then: qm terminal ${VM_ID}"
        exit 1
    fi
    warn "Attempt $SSH_ATTEMPTS/12 — retrying in 15s..."
    sleep 15
done
ok "ai-node-p4000 SSH: connected"

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 0: Attach GPU via pvesh
# ─────────────────────────────────────────────────────────────────────────────
if [ "$SKIP_GPU" = true ]; then
    log "=== PHASE 0: GPU attachment SKIPPED (--skip-gpu) ==="
    log "GPU can be added later:"
    log "  pvesh set /nodes/${PVE_HOST}/qemu/${VM_ID}/config --hostpci0 ${GPU_PCI},pcie=1,rombar=1"
else
    log ""
    log "=== PHASE 0: Attach Quadro P4000 via pvesh ==="

    # Verify vfio-pci is bound before attaching
    DRIVER=$(ssh $SSH_OPTS ${PVE_HOST} "cat /sys/bus/pci/devices/0000:01:00.0/driver/module/drivers 2>/dev/null || echo 'unknown'" || echo "unknown")
    log "Current driver for 01:00.0: $DRIVER"
    if echo "$DRIVER" | grep -q "vfio"; then
        ok "vfio-pci bound to P4000"
    else
        warn "vfio-pci NOT bound — GPU may not pass through correctly"
        warn "Run on pve01: echo '10de 1bb0' > /sys/bus/pci/drivers/vfio-pci/new_id"
    fi

    HOSTPCI=$(ssh $SSH_OPTS ${PVE_HOST} "qm config ${VM_ID} | grep hostpci0" 2>/dev/null || echo "")
    if echo "$HOSTPCI" | grep -q "01:00\|p4000\|P4000"; then
        ok "hostpci0 already set: $HOSTPCI"
    else
        log "Stopping VM to attach GPU..."
        ssh $SSH_OPTS ${PVE_HOST} "qm stop ${VM_ID} --timeout 30" 2>&1 | tee -a "$OUTFILE" || true
        sleep 5
        log "Attaching Quadro P4000 (${GPU_PCI})..."
        ssh $SSH_OPTS ${PVE_HOST} \
            "pvesh set /nodes/${PVE_HOST}/qemu/${VM_ID}/config --hostpci0 ${GPU_PCI},pcie=1,rombar=1" \
            2>&1 | tee -a "$OUTFILE"
        ok "hostpci0 set"
        log "Starting VM..."
        ssh $SSH_OPTS ${PVE_HOST} "qm start ${VM_ID}" 2>&1 | tee -a "$OUTFILE"
        log "Waiting 60s for boot after GPU attach..."
        sleep 60
        SSH_ATTEMPTS=0
        until ssh $SSH_OPTS "${AI_HOST}" 'hostname' &>/dev/null; do
            SSH_ATTEMPTS=$((SSH_ATTEMPTS + 1))
            if [ "$SSH_ATTEMPTS" -ge 8 ]; then
                fail "VM did not come back after GPU attach"
                fail "Check console: ssh ${PVE_HOST} then: qm terminal ${VM_ID}"
                exit 1
            fi
            warn "Post-attach SSH attempt $SSH_ATTEMPTS/8 — waiting 15s..."
            sleep 15
        done
        ok "VM back online with GPU attached"
    fi
fi # end SKIP_GPU check

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 1: System update
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "=== PHASE 1: System update ==="
ai 'sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq'
ok "System updated"

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2: NVIDIA drivers (only if GPU attached)
# ─────────────────────────────────────────────────────────────────────────────
if [ "$SKIP_GPU" = false ]; then
    log ""
    log "=== PHASE 2: NVIDIA driver install (nvidia-driver-550) ==="

    GPU_CHECK=$(ai 'lspci | grep -i nvidia' 2>/dev/null || true)
    if echo "$GPU_CHECK" | grep -qi "nvidia\|quadro\|P4000"; then
        ok "GPU visible inside VM: $GPU_CHECK"
    else
        fail "No NVIDIA GPU visible in lspci — passthrough failed"
        fail "Check pve01 VFIO config and IOMMU group"
        echo "$GPU_CHECK" >> "$OUTFILE"
        exit 1
    fi

    ai 'sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nvidia-driver-550 nvidia-utils-550' \
        2>&1 | tee -a "$OUTFILE"
    ok "NVIDIA driver 550 installed"

    log "Rebooting for driver activation..."
    ssh $SSH_OPTS "${AI_HOST}" 'sudo reboot' || true
    sleep 5
    log "Waiting 90s for reboot..."
    sleep 90

    SSH_ATTEMPTS=0
    until ssh $SSH_OPTS "${AI_HOST}" 'hostname' &>/dev/null; do
        SSH_ATTEMPTS=$((SSH_ATTEMPTS + 1))
        if [ "$SSH_ATTEMPTS" -ge 8 ]; then
            fail "VM did not come back after reboot"
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

    if echo "$NVIDIA_SMI" | grep -qi "Quadro P4000\|P4000\|GP104"; then
        ok "nvidia-smi: Quadro P4000 confirmed"
    elif echo "$NVIDIA_SMI" | grep -qi "NVIDIA"; then
        ok "nvidia-smi: NVIDIA GPU detected"
        warn "GPU model string unexpected — verify it's the P4000"
    else
        fail "nvidia-smi did not detect GPU — check passthrough config"
        exit 1
    fi

    # Save GPU verification
    echo "$NVIDIA_SMI" > GPU_VERIFICATION.txt
    ok "GPU verification saved to GPU_VERIFICATION.txt"
fi

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 3: Ollama install
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "=== PHASE 3: Ollama install ==="
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
# PHASE 4: Pull model and test inference
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "=== PHASE 4: Model pull + inference test (qwen2.5:7b) ==="

log "Pulling qwen2.5:7b..."
ai 'ollama pull qwen2.5:7b' 2>&1 | tee -a "$OUTFILE"
ok "qwen2.5:7b pulled"

log "Running inference test (REST API)..."
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

# Timed inference test for GPU comparison
if [ "$SKIP_GPU" = false ]; then
    log "Running timed inference test..."
    {
        echo "=== OLLAMA GPU INFERENCE TIMING ==="
        echo "Node: ai-node-p4000 (pve01, Quadro P4000)"
        echo "Model: qwen2.5:7b"
        echo "Date: $(date)"
        echo ""
        ai 'time curl -s http://localhost:11434/api/generate \
            -d "{\"model\":\"qwen2.5:7b\",\"prompt\":\"Explain quantum computing in 2 sentences\",\"stream\":false}" \
            | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[\"response\"]); print(f\"eval_duration: {d.get(\\\"eval_duration\\\",0)/1e9:.2f}s\")"'
    } > OLLAMA_GPU_TEST.txt 2>&1
    ok "Timing saved to OLLAMA_GPU_TEST.txt"
fi

# GPU memory check
if [ "$SKIP_GPU" = false ]; then
    GPU_MEM=$(ai "nvidia-smi --query-gpu=name,memory.total,memory.used --format=csv,noheader" 2>/dev/null || true)
    log "GPU memory: $GPU_MEM"
    echo "$GPU_MEM" >> "$OUTFILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "=== DEPLOYMENT COMPLETE ==="
log "Output: $OUTFILE"
log ""
ok "ai-node-p4000 is ready at ${AI_IP}"
log "  SSH:    ssh ai-node-p4000"
log "  Ollama: http://${AI_IP}:11434"
log "  Models: ssh ai-node-p4000 'ollama list'"
if [ "$SKIP_GPU" = false ]; then
    log "  GPU:    Quadro P4000 (8GB VRAM)"
fi
