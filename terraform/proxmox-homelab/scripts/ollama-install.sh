#!/usr/bin/env bash
# ollama-install.sh — AI node setup: NVIDIA drivers + Ollama (GPU or CPU mode)
#
# Usage:
#   ./ollama-install.sh [--dry-run] <vm_ip> <mode>
#
# Modes:
#   gpu   — Install NVIDIA driver 550, verify GPU in lspci, install Ollama, test inference
#   cpu   — Install Ollama only, test CPU inference
#
# Examples:
#   ./ollama-install.sh 192.168.4.16 gpu   # ai-node-p4000 (pve01, Quadro P4000)
#   ./ollama-install.sh 192.168.4.15 gpu   # ai-node-a4500 (pve02, RTX A4500)
#   ./ollama-install.sh 192.168.4.50 cpu   # any VM, CPU-only
#   ./ollama-install.sh --dry-run 192.168.4.16 gpu
#
# Prerequisites:
#   - VM is running and SSH-reachable at vm_ip
#   - SSH key authorized for ubuntu@vm_ip (or set VM_USER env var)
#   - If gpu mode: GPU must already be attached via pvesh (see gpu-passthrough-setup.sh)
#   - eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519
#
# What this installs:
#   - System updates (apt)
#   - NVIDIA driver 550 + nvidia-utils (gpu mode only)
#   - Ollama (latest via install.sh)
#   - Pulls qwen2.5:7b for inference testing
#
# After install, Ollama API is available at: http://<vm_ip>:11434
#
# Exit codes: 0=success, 1=error, 2=usage error

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/$(date +%Y-%m-%d).log"
SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no"
VM_USER="${VM_USER:-ubuntu}"
DEFAULT_MODEL="${OLLAMA_MODEL:-qwen2.5:7b}"
NVIDIA_DRIVER_VERSION="${NVIDIA_DRIVER:-550}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'; BOLD='\033[1m'

mkdir -p "$LOG_DIR"
_ts() { date '+%Y-%m-%d %H:%M:%S'; }
log()  { local m="[$(_ts)] [INFO]  $*"; echo -e "${m}"; echo "${m}" >> "$LOG_FILE"; }
ok()   { local m="[$(_ts)] [OK]    $*"; echo -e "${GREEN}✅ ${m}${NC}"; echo "${m}" >> "$LOG_FILE"; }
warn() { local m="[$(_ts)] [WARN]  $*"; echo -e "${YELLOW}⚠️  ${m}${NC}"; echo "${m}" >> "$LOG_FILE"; }
fail() { local m="[$(_ts)] [ERROR] $*"; echo -e "${RED}❌ ${m}${NC}" >&2; echo "${m}" >> "$LOG_FILE"; }
die()  { fail "$*"; exit 1; }
die2() { fail "$*"; usage; exit 2; }

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && { DRY_RUN=true; shift; }

usage() {
    echo ""
    echo -e "${BOLD}Usage:${NC} $SCRIPT_NAME [--dry-run] <vm_ip> <mode>"
    echo ""
    echo "  vm_ip    IP address of the target VM"
    echo "  mode     gpu | cpu"
    echo ""
    echo "  --dry-run   Show what would run without executing"
    echo ""
    echo "  Environment vars:"
    echo "    VM_USER           SSH user (default: ubuntu)"
    echo "    OLLAMA_MODEL      Model to pull (default: qwen2.5:7b)"
    echo "    NVIDIA_DRIVER     Driver version (default: 550)"
    echo ""
    echo "  Examples:"
    echo "    $SCRIPT_NAME 192.168.4.16 gpu"
    echo "    $SCRIPT_NAME 192.168.4.15 gpu"
    echo "    $SCRIPT_NAME 192.168.4.50 cpu"
    echo "    $SCRIPT_NAME --dry-run 192.168.4.16 gpu"
}

[[ $# -ne 2 ]] && die2 "Expected 2 arguments, got $#"

VM_IP="$1"
MODE="$2"

[[ "$VM_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die2 "IP does not look valid: ${VM_IP}"
[[ "$MODE" == "gpu" || "$MODE" == "cpu" ]] || die2 "Mode must be 'gpu' or 'cpu', got: ${MODE}"

SSH_HOST="${VM_USER}@${VM_IP}"

run() {
    if $DRY_RUN; then
        echo -e "${YELLOW}[DRY-RUN]${NC} ssh ${SSH_HOST} '$*'"
        echo "[DRY-RUN] ssh ${SSH_HOST} '$*'" >> "$LOG_FILE"
    else
        log "→ $*"
        ssh $SSH_OPTS "$SSH_HOST" "$*" 2>&1 | tee -a "$LOG_FILE"
    fi
}

run_local() {
    if $DRY_RUN; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $*"
    else
        log "Local: $*"
        eval "$*"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Pre-flight
# ─────────────────────────────────────────────────────────────────────────────
preflight() {
    log "=== PRE-FLIGHT ==="

    log "Testing SSH to ${SSH_HOST}..."
    if ! ssh $SSH_OPTS "$SSH_HOST" 'hostname' &>/dev/null; then
        die "Cannot SSH to ${SSH_HOST}.
  Check:
    1. VM is running
    2. SSH agent loaded: eval \"\$(ssh-agent -s)\" && ssh-add ~/.ssh/id_ed25519
    3. VM IP is correct and cloud-init applied networking
    4. Run: ./vm-troubleshoot.sh <vmid>"
    fi
    local hostname
    hostname=$(ssh $SSH_OPTS "$SSH_HOST" 'hostname' 2>/dev/null)
    ok "SSH connected — hostname: ${hostname}"

    if [[ "$MODE" == "gpu" ]]; then
        log "Checking GPU is visible (lspci)..."
        local gpu_lspci
        gpu_lspci=$(ssh $SSH_OPTS "$SSH_HOST" 'lspci | grep -i nvidia' 2>/dev/null || echo "")
        if [[ -n "$gpu_lspci" ]]; then
            ok "GPU visible: ${gpu_lspci}"
        else
            die "No NVIDIA GPU visible via lspci inside VM.
  This means GPU passthrough is not working.
  Steps to fix:
    1. Check GPU is attached: ssh root@<pve-node> 'qm config <vmid> | grep hostpci'
    2. If missing: pvesh set /nodes/<node>/qemu/<vmid>/config --hostpci0 0000:01:00,pcie=1,rombar=1
    3. Reboot VM after attaching
    4. Verify VFIO: ./gpu-passthrough-setup.sh <node> 0000:01:00"
        fi
    fi

    # Check free disk space (need ~5GB for drivers + model)
    local free_gb
    free_gb=$(ssh $SSH_OPTS "$SSH_HOST" "df -BG / | awk 'NR==2 {print \$4}' | tr -d G" 2>/dev/null || echo 0)
    if [[ "$free_gb" -lt 10 ]]; then
        warn "Low disk space: ${free_gb}GB free (need ~10GB for NVIDIA drivers + model)"
        warn "Disk resize: ssh root@<node> 'qm resize <vmid> virtio0 +50G'"
        warn "Then inside VM: sudo growpart /dev/vda 1 && sudo resize2fs /dev/vda1"
    else
        ok "Disk space: ${free_gb}GB free"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# System update
# ─────────────────────────────────────────────────────────────────────────────
phase_system_update() {
    log ""
    log "=== PHASE 1: System Update ==="
    run 'sudo apt-get update -qq'
    run 'sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq'
    run 'sudo apt-get install -y -qq curl python3 net-tools'
    ok "System updated"
}

# ─────────────────────────────────────────────────────────────────────────────
# NVIDIA drivers (GPU mode only)
# ─────────────────────────────────────────────────────────────────────────────
phase_nvidia() {
    log ""
    log "=== PHASE 2: NVIDIA Driver Install (nvidia-driver-${NVIDIA_DRIVER_VERSION}) ==="

    # Check if already installed
    local nvidia_installed
    nvidia_installed=$(ssh $SSH_OPTS "$SSH_HOST" \
        "dpkg -l nvidia-driver-${NVIDIA_DRIVER_VERSION} 2>/dev/null | grep -c '^ii'" 2>/dev/null || echo 0)

    if [[ "$nvidia_installed" -gt 0 ]]; then
        ok "nvidia-driver-${NVIDIA_DRIVER_VERSION}: already installed"
    else
        log "Installing nvidia-driver-${NVIDIA_DRIVER_VERSION}..."
        run "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
            nvidia-driver-${NVIDIA_DRIVER_VERSION} \
            nvidia-utils-${NVIDIA_DRIVER_VERSION}"
        ok "NVIDIA driver ${NVIDIA_DRIVER_VERSION} installed"

        log "Rebooting for driver activation..."
        $DRY_RUN || ssh $SSH_OPTS "$SSH_HOST" 'sudo reboot' || true
        $DRY_RUN || sleep 5
        $DRY_RUN || { log "Waiting 120s for reboot..."; sleep 120; }

        $DRY_RUN || {
            local attempts=0
            until ssh $SSH_OPTS "$SSH_HOST" 'hostname' &>/dev/null; do
                attempts=$((attempts + 1))
                [[ $attempts -ge 12 ]] && die "VM did not come back after NVIDIA driver reboot"
                warn "Post-reboot attempt ${attempts}/12 — waiting 15s..."
                sleep 15
            done
            ok "VM back online after reboot"
        }
    fi

    # Verify nvidia-smi
    log "Running nvidia-smi..."
    if $DRY_RUN; then
        warn "[DRY-RUN] Would run: nvidia-smi"
    else
        local smi_output
        smi_output=$(ssh $SSH_OPTS "$SSH_HOST" 'nvidia-smi 2>&1' || echo "")
        echo "$smi_output" | tee -a "$LOG_FILE"

        if echo "$smi_output" | grep -qi "Quadro P4000\|GP104\|RTX A4500\|GA104\|NVIDIA"; then
            ok "nvidia-smi: GPU detected"
        else
            die "nvidia-smi did not detect GPU — check passthrough config
  Steps:
    1. Verify hostpci in VM config
    2. Check vfio binding on Proxmox host
    3. Try: ./gpu-passthrough-setup.sh <node> 0000:01:00"
        fi

        # Save nvidia-smi output
        echo "$smi_output" > "${LOG_DIR}/nvidia-smi-${VM_IP}.txt"
        ok "nvidia-smi output saved: ${LOG_DIR}/nvidia-smi-${VM_IP}.txt"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Ollama install
# ─────────────────────────────────────────────────────────────────────────────
phase_ollama() {
    log ""
    log "=== PHASE 3: Ollama Install ==="

    # Check if already installed
    local ollama_installed
    ollama_installed=$(ssh $SSH_OPTS "$SSH_HOST" 'which ollama 2>/dev/null && echo 1 || echo 0')

    if [[ "$ollama_installed" == "1" ]]; then
        local ollama_ver
        ollama_ver=$(ssh $SSH_OPTS "$SSH_HOST" 'ollama --version 2>/dev/null || echo unknown')
        ok "Ollama already installed: ${ollama_ver}"
    else
        log "Installing Ollama..."
        run 'curl -fsSL https://ollama.com/install.sh | sh'
        ok "Ollama installed"
    fi

    # Enable and start service
    run 'sudo systemctl enable --now ollama'
    sleep 3

    local ollama_status
    if $DRY_RUN; then
        warn "[DRY-RUN] Would check: systemctl is-active ollama"
    else
        ollama_status=$(ssh $SSH_OPTS "$SSH_HOST" 'systemctl is-active ollama 2>/dev/null || echo unknown')
        if [[ "$ollama_status" == "active" ]]; then
            ok "Ollama service: active"
        else
            warn "Ollama service status: ${ollama_status}"
            warn "Check: ssh ${SSH_HOST} 'journalctl -u ollama --no-pager | tail -20'"
        fi
    fi

    # Expose Ollama on all interfaces (for network access)
    local env_file="/etc/systemd/system/ollama.service.d/override.conf"
    run "sudo mkdir -p /etc/systemd/system/ollama.service.d"
    run "printf '[Service]\nEnvironment=\"OLLAMA_HOST=0.0.0.0:11434\"\n' | sudo tee ${env_file} > /dev/null"
    run 'sudo systemctl daemon-reload && sudo systemctl restart ollama'
    sleep 3
    ok "Ollama configured to listen on 0.0.0.0:11434"
}

# ─────────────────────────────────────────────────────────────────────────────
# Pull model + inference test
# ─────────────────────────────────────────────────────────────────────────────
phase_inference() {
    log ""
    log "=== PHASE 4: Model Pull + Inference Test (${DEFAULT_MODEL}) ==="

    # Pull model
    log "Pulling ${DEFAULT_MODEL} (this may take several minutes)..."
    run "ollama pull ${DEFAULT_MODEL}"
    ok "${DEFAULT_MODEL} pulled"

    # Basic inference test
    log "Running inference test..."
    if $DRY_RUN; then
        warn "[DRY-RUN] Would run: ollama run ${DEFAULT_MODEL} 'Hello'"
    else
        local response
        response=$(ssh $SSH_OPTS "$SSH_HOST" \
            "curl -s http://localhost:11434/api/generate \
                -d '{\"model\":\"${DEFAULT_MODEL}\",\"prompt\":\"Say hello in exactly 5 words.\",\"stream\":false}' \
                | python3 -c \"import sys,json; print(json.load(sys.stdin)['response'])\" 2>/dev/null" \
            || echo "")

        if [[ -n "$response" ]]; then
            ok "Inference: responded"
            log "Response: ${response}"
        else
            warn "Inference returned empty response — check Ollama service"
            warn "Debug: ssh ${SSH_HOST} 'journalctl -u ollama --no-pager | tail -30'"
        fi
    fi

    # GPU memory utilization check (gpu mode)
    if [[ "$MODE" == "gpu" ]] && ! $DRY_RUN; then
        log ""
        log "GPU memory after inference:"
        ssh $SSH_OPTS "$SSH_HOST" \
            "nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free,utilization.gpu \
             --format=csv,noheader" 2>/dev/null | tee -a "$LOG_FILE" || true
    fi

    # Timed inference test
    if ! $DRY_RUN; then
        log "Running timed inference test..."
        local timing_result
        timing_result=$(ssh $SSH_OPTS "$SSH_HOST" \
            "curl -s http://localhost:11434/api/generate \
                -d '{\"model\":\"${DEFAULT_MODEL}\",\"prompt\":\"Explain containerization in 2 sentences.\",\"stream\":false}' \
                | python3 -c \"
import sys, json
d = json.load(sys.stdin)
eval_dur = d.get('eval_duration', 0) / 1e9
eval_cnt = d.get('eval_count', 0)
tps = eval_cnt / eval_dur if eval_dur > 0 else 0
print(f'tokens: {eval_cnt}, time: {eval_dur:.1f}s, speed: {tps:.1f} tok/s')
print(d['response'])
\" 2>/dev/null" || echo "timing unavailable")
        log "Timing: ${timing_result}"
        echo "$timing_result" > "${LOG_DIR}/inference-timing-${VM_IP}.txt"
        ok "Timing saved: ${LOG_DIR}/inference-timing-${VM_IP}.txt"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Install qemu-guest-agent (if not present)
# ─────────────────────────────────────────────────────────────────────────────
phase_guest_agent() {
    log ""
    log "=== PHASE 0: Guest Agent ==="
    local agent_installed
    agent_installed=$(ssh $SSH_OPTS "$SSH_HOST" \
        "dpkg -l qemu-guest-agent 2>/dev/null | grep -c '^ii'" 2>/dev/null || echo 0)

    if [[ "$agent_installed" -gt 0 ]]; then
        ok "qemu-guest-agent: already installed"
    else
        log "Installing qemu-guest-agent..."
        run 'sudo apt-get install -y qemu-guest-agent'
        run 'sudo systemctl enable --now qemu-guest-agent'
        ok "qemu-guest-agent installed and started"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    ok "AI node setup complete"
    echo ""
    log "  Mode:    ${MODE}"
    log "  VM IP:   ${VM_IP}"
    log "  Model:   ${DEFAULT_MODEL}"
    log ""
    log "  Access:"
    log "    SSH:    ssh ${VM_USER}@${VM_IP}"
    log "    API:    http://${VM_IP}:11434"
    log "    Models: ssh ${VM_USER}@${VM_IP} 'ollama list'"
    log ""
    log "  Quick test:"
    log "    curl http://${VM_IP}:11434/api/generate \\"
    log "      -d '{\"model\":\"${DEFAULT_MODEL}\",\"prompt\":\"Hello\",\"stream\":false}'"
    [[ "$MODE" == "gpu" ]] && log "    GPU:  ssh ${VM_USER}@${VM_IP} 'nvidia-smi'"
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo ""
    log "Log: ${LOG_FILE}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BOLD}=== ollama-install.sh ===${NC}"
    log "Started: $(date)"
    log "Target:  ${VM_USER}@${VM_IP} | Mode: ${MODE} | Model: ${DEFAULT_MODEL}"
    log "Log:     ${LOG_FILE}"
    $DRY_RUN && warn "Dry-run mode — no changes will be made"
    echo ""

    preflight
    phase_guest_agent
    phase_system_update
    [[ "$MODE" == "gpu" ]] && phase_nvidia
    phase_ollama
    phase_inference
    print_summary
}

main "$@"
