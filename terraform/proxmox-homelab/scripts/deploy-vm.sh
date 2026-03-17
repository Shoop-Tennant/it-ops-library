#!/usr/bin/env bash
# deploy-vm.sh — Generic VM deployment from ubuntu-2404-cloud template
#
# Usage:
#   ./deploy-vm.sh <node> <vmid> <name> <ip> <cores> <ram_mb> <disk>
#   ./deploy-vm.sh --dry-run pve01 200 test-vm 192.168.4.50 4 8192 50G
#
# Examples:
#   ./deploy-vm.sh pve01 200 test-vm 192.168.4.50 4 8192 50G
#   ./deploy-vm.sh pve02 201 dev-box 192.168.4.51 8 16384 100G
#   ./deploy-vm.sh --dry-run pve01 202 staging 192.168.4.52 4 8192 50G
#
# Prerequisites:
#   - SSH key authorized on all Proxmox nodes (root@<node>)
#   - ubuntu-2404-cloud template exists on target node
#   - eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519
#
# Exit codes: 0=success, 1=error, 2=usage error

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/$(date +%Y-%m-%d).log"
TEMPLATE="ubuntu-2404-cloud"
GATEWAY="192.168.4.1"
NAMESERVER="1.1.1.1"
STORAGE="local-lvm"
SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no"
CI_USER="${CI_USER:-ubuntu}"
CI_PASSWORD="${CI_PASSWORD:-}"

# ─────────────────────────────────────────────────────────────────────────────
# Colors
# ─────────────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'; BOLD='\033[1m'

# ─────────────────────────────────────────────────────────────────────────────
# Logging
# ─────────────────────────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"
_ts() { date '+%H:%M:%S'; }
log()  { local m="[$(date +%Y-%m-%d\ %H:%M:%S)] [INFO]  $*"; echo -e "${m}"; echo "${m}" >> "$LOG_FILE"; }
ok()   { local m="[$(date +%Y-%m-%d\ %H:%M:%S)] [OK]    $*"; echo -e "${GREEN}✅ ${m}${NC}"; echo "${m}" >> "$LOG_FILE"; }
warn() { local m="[$(date +%Y-%m-%d\ %H:%M:%S)] [WARN]  $*"; echo -e "${YELLOW}⚠️  ${m}${NC}"; echo "${m}" >> "$LOG_FILE"; }
fail() { local m="[$(date +%Y-%m-%d\ %H:%M:%S)] [ERROR] $*"; echo -e "${RED}❌ ${m}${NC}" >&2; echo "${m}" >> "$LOG_FILE"; }

die()  { fail "$*"; exit 1; }
die2() { fail "$*"; usage; exit 2; }

# ─────────────────────────────────────────────────────────────────────────────
# Usage
# ─────────────────────────────────────────────────────────────────────────────
usage() {
    echo ""
    echo -e "${BOLD}Usage:${NC} $SCRIPT_NAME [--dry-run] <node> <vmid> <name> <ip> <cores> <ram_mb> <disk>"
    echo ""
    echo "  node      Proxmox node name (pve01, pve02, pve03-7090, pve04-7090)"
    echo "  vmid      VM ID (e.g. 200) — must not already exist"
    echo "  name      VM hostname"
    echo "  ip        Static IP address (e.g. 192.168.4.50)"
    echo "  cores     CPU cores"
    echo "  ram_mb    RAM in MB (e.g. 8192)"
    echo "  disk      Disk size (e.g. 50G)"
    echo ""
    echo "  --dry-run Show commands without executing"
    echo ""
    echo "  Environment vars:"
    echo "    CI_USER      Cloud-init username (default: ubuntu)"
    echo "    CI_PASSWORD  Cloud-init password (default: none)"
    echo "    SSH_KEY_FILE Path to SSH public key to inject (default: ~/.ssh/id_ed25519.pub)"
    echo ""
    echo "  Examples:"
    echo "    $SCRIPT_NAME pve01 200 test-vm 192.168.4.50 4 8192 50G"
    echo "    $SCRIPT_NAME --dry-run pve02 201 dev-box 192.168.4.51 8 16384 100G"
}

# ─────────────────────────────────────────────────────────────────────────────
# Dry-run wrapper
# ─────────────────────────────────────────────────────────────────────────────
DRY_RUN=false
run() {
    if $DRY_RUN; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $*"
        echo "[DRY-RUN] $*" >> "$LOG_FILE"
    else
        log "Running: $*"
        eval "$@"
    fi
}

pve() { run "ssh $SSH_OPTS root@${NODE} \"$*\""; }

# ─────────────────────────────────────────────────────────────────────────────
# Parse args
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    shift
fi

[[ $# -ne 7 ]] && die2 "Expected 7 arguments, got $#"

NODE="$1"
VMID="$2"
VM_NAME="$3"
VM_IP="$4"
CORES="$5"
RAM="$6"
DISK="$7"

SSH_KEY_FILE="${SSH_KEY_FILE:-${HOME}/.ssh/id_ed25519.pub}"

# ─────────────────────────────────────────────────────────────────────────────
# Validate args
# ─────────────────────────────────────────────────────────────────────────────
validate_args() {
    [[ "$VMID" =~ ^[0-9]+$ ]]    || die2 "VMID must be a number: $VMID"
    [[ "$CORES" =~ ^[0-9]+$ ]]   || die2 "Cores must be a number: $CORES"
    [[ "$RAM" =~ ^[0-9]+$ ]]     || die2 "RAM must be a number (MB): $RAM"
    [[ "$DISK" =~ ^[0-9]+G$ ]]   || die2 "Disk must be in format NNNg (e.g. 50G): $DISK"
    [[ "$VM_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die2 "IP does not look valid: $VM_IP"
    [[ -f "$SSH_KEY_FILE" ]]     || die "SSH public key not found: $SSH_KEY_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# Pre-flight checks
# ─────────────────────────────────────────────────────────────────────────────
preflight() {
    log "=== PRE-FLIGHT CHECKS ==="

    log "Checking SSH connectivity to ${NODE}..."
    ssh $SSH_OPTS "root@${NODE}" 'hostname' &>/dev/null \
        || die "Cannot SSH to root@${NODE}. Add your key to Proxmox root's authorized_keys, then run:
  eval \"\$(ssh-agent -s)\" && ssh-add ~/.ssh/id_ed25519"
    ok "SSH to ${NODE}: connected"

    log "Checking template '${TEMPLATE}' exists on ${NODE}..."
    TMPL_EXISTS=$(ssh $SSH_OPTS "root@${NODE}" "qm list | grep -c '${TEMPLATE}'" 2>/dev/null || echo 0)
    [[ "$TMPL_EXISTS" -gt 0 ]] || die "Template '${TEMPLATE}' not found on ${NODE}. Run the template setup commands from the repo README."
    ok "Template '${TEMPLATE}' found"

    log "Checking VMID ${VMID} is not already in use..."
    VMID_EXISTS=$(ssh $SSH_OPTS "root@${NODE}" "qm list | awk '{print \$1}' | grep -c '^${VMID}$'" 2>/dev/null || echo 0)
    [[ "$VMID_EXISTS" -eq 0 ]] || die "VMID ${VMID} already exists on ${NODE}. Choose a different ID."
    ok "VMID ${VMID}: available"

    log "Checking storage '${STORAGE}' available on ${NODE}..."
    STORAGE_EXISTS=$(ssh $SSH_OPTS "root@${NODE}" "pvesm list ${STORAGE}" &>/dev/null && echo 1 || echo 0)
    [[ "$STORAGE_EXISTS" -eq 1 ]] || die "Storage '${STORAGE}' not available on ${NODE}"
    ok "Storage '${STORAGE}': available"
}

# ─────────────────────────────────────────────────────────────────────────────
# Deploy
# ─────────────────────────────────────────────────────────────────────────────
deploy_vm() {
    log "=== DEPLOYING VM ==="
    log "  Node:   ${NODE}"
    log "  VMID:   ${VMID}"
    log "  Name:   ${VM_NAME}"
    log "  IP:     ${VM_IP}/22 (gw ${GATEWAY})"
    log "  CPU:    ${CORES} cores"
    log "  RAM:    ${RAM} MB"
    log "  Disk:   ${DISK}"

    SSH_PUB_KEY=$(cat "$SSH_KEY_FILE")

    # Clone template
    log "Cloning ${TEMPLATE} → VM ${VMID} (${VM_NAME})..."
    pve "qm clone \$(qm list | grep '${TEMPLATE}' | awk '{print \$1}' | head -1) ${VMID} --name ${VM_NAME} --full 1"
    ok "Clone complete"

    # CPU + RAM
    log "Configuring CPU (${CORES} cores) and RAM (${RAM} MB)..."
    pve "qm set ${VMID} --cores ${CORES} --sockets 1 --cpu host --memory ${RAM}"
    ok "CPU and RAM set"

    # Disk resize
    log "Resizing disk to ${DISK}..."
    pve "qm resize ${VMID} scsi0 ${DISK}"
    ok "Disk resized to ${DISK}"

    # Cloud-init: user, password, SSH key, network
    log "Configuring cloud-init (user=${CI_USER}, ip=${VM_IP}/22)..."
    local ci_cmd="qm set ${VMID} --ciuser '${CI_USER}'"
    [[ -n "$CI_PASSWORD" ]] && ci_cmd+=" --cipassword '${CI_PASSWORD}'"
    ci_cmd+=" --sshkeys '${SSH_PUB_KEY}'"
    ci_cmd+=" --ipconfig0 'ip=${VM_IP}/22,gw=${GATEWAY}'"
    ci_cmd+=" --nameserver '${NAMESERVER}'"
    pve "$ci_cmd"
    ok "Cloud-init configured"

    # Guest agent
    pve "qm set ${VMID} --agent 1"

    # Start VM
    log "Starting VM ${VMID}..."
    pve "qm start ${VMID}"
    ok "VM started"
}

# ─────────────────────────────────────────────────────────────────────────────
# Verify
# ─────────────────────────────────────────────────────────────────────────────
verify_vm() {
    log "=== VERIFICATION ==="

    if $DRY_RUN; then
        warn "Dry-run: skipping SSH verification"
        return
    fi

    log "Waiting for VM to boot and cloud-init to complete (up to 3 min)..."
    local attempts=0
    until ssh $SSH_OPTS "${CI_USER}@${VM_IP}" 'hostname' &>/dev/null; do
        attempts=$((attempts + 1))
        if [[ $attempts -ge 18 ]]; then
            warn "VM not reachable via SSH at ${VM_IP} after 3 minutes"
            warn "Troubleshoot with: ./vm-troubleshoot.sh ${VMID}"
            warn "Or check console: ssh root@${NODE} 'qm terminal ${VMID}'"
            return 1
        fi
        warn "Attempt ${attempts}/18 — waiting 10s..."
        sleep 10
    done
    ok "SSH reachable at ${VM_IP}"

    # Check cloud-init
    local ci_status
    ci_status=$(ssh $SSH_OPTS "${CI_USER}@${VM_IP}" 'cloud-init status 2>/dev/null || echo unknown')
    log "Cloud-init status: ${ci_status}"
    echo "${ci_status}" | grep -q "done" && ok "Cloud-init: done" || warn "Cloud-init status: ${ci_status}"

    # Check IP
    local actual_ip
    actual_ip=$(ssh $SSH_OPTS "${CI_USER}@${VM_IP}" "ip -4 addr show ens18 2>/dev/null | grep -oP '(?<=inet )[^/]+' | head -1")
    [[ "$actual_ip" == "$VM_IP" ]] && ok "IP confirmed: ${actual_ip}" || warn "IP mismatch — expected ${VM_IP}, got ${actual_ip}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BOLD}=== deploy-vm.sh ===${NC}"
    log "Started at $(date)"
    log "Log: ${LOG_FILE}"
    echo ""

    validate_args
    if ! $DRY_RUN; then
        preflight
    else
        warn "Dry-run mode — no changes will be made"
    fi
    deploy_vm
    verify_vm

    echo ""
    ok "VM ${VM_NAME} (${VMID}) deployed successfully"
    log "  SSH:  ssh ${CI_USER}@${VM_IP}"
    log "  Node: ${NODE}"
    log "  Troubleshoot: ./vm-troubleshoot.sh ${VMID}"
}

main "$@"
