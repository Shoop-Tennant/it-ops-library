#!/usr/bin/env bash
# vm-troubleshoot.sh — Interactive VM diagnostics and fix suggestions
#
# Usage:
#   ./vm-troubleshoot.sh <vmid> [node]
#   ./vm-troubleshoot.sh 100           # auto-detect node
#   ./vm-troubleshoot.sh 100 pve02     # specify node
#   ./vm-troubleshoot.sh 100 --fix-boot-disk    # attempt boot disk fix
#
# Checks:
#   - VM exists and which node it's on
#   - Run state (running/stopped/paused)
#   - Boot configuration (bootdisk vs actual disks)
#   - Disk layout (scsi0/virtio0, unused disks)
#   - Network config (cloud-init, bridge)
#   - GPU passthrough (hostpci config)
#   - Guest agent status
#   - SSH reachability (if VM is running)
#   - Cloud-init status (via guest agent)
#
# Suggests fixes for:
#   - Orphaned OS disk (unused0 issue from Terraform clone)
#   - Boot disk mismatch (bootdisk points to wrong slot)
#   - Guest agent not installed
#   - Cloud-init network failure
#   - GPU attachment issues
#
# Exit codes: 0=healthy, 1=issues found

set -uo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/$(date +%Y-%m-%d).log"
SSH_OPTS="-o ConnectTimeout=8 -o BatchMode=yes -o StrictHostKeyChecking=no"

declare -A NODE_IPS=( [pve01]="192.168.4.10" [pve02]="192.168.4.11" [pve03-7090]="192.168.4.12" [pve04-7090]="192.168.4.13" )
GATEWAY="192.168.4.1"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

mkdir -p "$LOG_DIR"
_ts() { date '+%Y-%m-%d %H:%M:%S'; }
ok()   { local m="[$(_ts)] [OK]    $*"; echo -e "${GREEN}✅ ${m}${NC}"; echo "${m}" >> "$LOG_FILE"; }
warn() { local m="[$(_ts)] [WARN]  $*"; echo -e "${YELLOW}⚠️  ${m}${NC}"; echo "${m}" >> "$LOG_FILE"; ISSUES_FOUND=true; }
fail() { local m="[$(_ts)] [FAIL]  $*"; echo -e "${RED}❌ ${m}${NC}"; echo "${m}" >> "$LOG_FILE"; ISSUES_FOUND=true; }
info() { local m="[$(_ts)] [INFO]  $*"; echo -e "${m}"; echo "${m}" >> "$LOG_FILE"; }
fix()  { echo -e "${CYAN}  💡 Fix: $*${NC}"; echo "[FIX] $*" >> "$LOG_FILE"; }
hdr()  { echo -e "\n${BOLD}${CYAN}$*${NC}"; }

ISSUES_FOUND=false
FIX_BOOT_DISK=false
VMID=""
NODE_HINT=""

usage() {
    echo ""
    echo -e "${BOLD}Usage:${NC} $SCRIPT_NAME <vmid> [node] [--fix-boot-disk]"
    echo ""
    echo "  vmid             VM ID to diagnose"
    echo "  node             Proxmox node (optional — auto-detected)"
    echo "  --fix-boot-disk  Attempt to fix boot disk mismatch automatically"
    echo ""
    echo "  Examples:"
    echo "    $SCRIPT_NAME 100"
    echo "    $SCRIPT_NAME 100 pve02"
    echo "    $SCRIPT_NAME 100 --fix-boot-disk"
    exit 2
}

# Parse args
for arg in "$@"; do
    [[ "$arg" == "--fix-boot-disk" ]] && FIX_BOOT_DISK=true && continue
    [[ "$arg" =~ ^[0-9]+$ ]] && VMID="$arg" && continue
    [[ "${NODE_IPS[$arg]+_}" ]] && NODE_HINT="$arg" && continue
    echo "Unknown argument: $arg"; usage
done

[[ -z "$VMID" ]] && usage

# ─────────────────────────────────────────────────────────────────────────────
# Find which node owns this VMID
# ─────────────────────────────────────────────────────────────────────────────
NODE=""
NODE_IP=""

find_node() {
    hdr "─── Locating VM ${VMID} ───"

    if [[ -n "$NODE_HINT" ]]; then
        local ip="${NODE_IPS[$NODE_HINT]}"
        local found
        found=$(ssh $SSH_OPTS "root@${ip}" "qm list | awk '{print \$1}' | grep -c '^${VMID}$'" 2>/dev/null || echo 0)
        if [[ "$found" -gt 0 ]]; then
            NODE="$NODE_HINT"
            NODE_IP="$ip"
            ok "VM ${VMID} found on ${NODE} (${NODE_IP}) [user-specified]"
            return
        else
            fail "VM ${VMID} NOT found on ${NODE_HINT} — searching all nodes..."
        fi
    fi

    for node in "${!NODE_IPS[@]}"; do
        local ip="${NODE_IPS[$node]}"
        if ! ssh $SSH_OPTS "root@${ip}" 'hostname' &>/dev/null 2>&1; then
            warn "${node} (${ip}): SSH unreachable — skipping"
            continue
        fi
        local found
        found=$(ssh $SSH_OPTS "root@${ip}" "qm list | awk '{print \$1}' | grep -c '^${VMID}$'" 2>/dev/null || echo 0)
        if [[ "$found" -gt 0 ]]; then
            NODE="$node"
            NODE_IP="$ip"
            ok "VM ${VMID} found on ${NODE} (${NODE_IP})"
            return
        fi
    done

    fail "VM ${VMID} not found on any reachable node"
    fail "Checked nodes: ${!NODE_IPS[*]}"
    exit 1
}

pve() { ssh $SSH_OPTS "root@${NODE_IP}" "$*" 2>/dev/null || echo ""; }

# ─────────────────────────────────────────────────────────────────────────────
# Run state
# ─────────────────────────────────────────────────────────────────────────────
VM_STATUS=""
check_state() {
    hdr "─── VM State ───"
    local qm_status
    qm_status=$(pve "qm status ${VMID}")
    VM_STATUS=$(echo "$qm_status" | awk '{print $2}')
    info "qm status ${VMID}: ${qm_status}"

    case "$VM_STATUS" in
        running) ok "VM ${VMID}: running" ;;
        stopped) warn "VM ${VMID}: stopped"
                 fix "Start VM: ssh root@${NODE_IP} 'qm start ${VMID}'" ;;
        paused)  warn "VM ${VMID}: paused"
                 fix "Resume VM: ssh root@${NODE_IP} 'qm resume ${VMID}'" ;;
        *)        fail "VM ${VMID}: unknown state '${VM_STATUS}'" ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Full config dump + analysis
# ─────────────────────────────────────────────────────────────────────────────
VM_CONFIG=""
BOOT_DISK=""
ACTUAL_BOOT_DEVICE=""
VM_IP_CONFIG=""

check_config() {
    hdr "─── VM Configuration ───"
    VM_CONFIG=$(pve "qm config ${VMID}")
    info "--- qm config ${VMID} ---"
    echo "$VM_CONFIG" | while IFS= read -r line; do info "  ${line}"; done
}

# ─────────────────────────────────────────────────────────────────────────────
# Boot disk analysis
# ─────────────────────────────────────────────────────────────────────────────
check_boot_disk() {
    hdr "─── Boot Disk Analysis ───"

    BOOT_DISK=$(echo "$VM_CONFIG" | grep '^bootdisk:' | awk '{print $2}')
    local boot_order
    boot_order=$(echo "$VM_CONFIG" | grep '^boot:' | sed 's/boot: //')

    info "bootdisk:  ${BOOT_DISK:-not set}"
    info "boot:      ${boot_order:-not set}"

    # Find all disk-like lines
    local disks
    disks=$(echo "$VM_CONFIG" | grep -E '^(scsi|virtio|ide|sata)[0-9]+:' | grep -v cloudinit || echo "")
    info "Disks in config:"
    echo "$disks" | while IFS= read -r line; do info "  ${line}"; done

    # Find unused disks
    local unused
    unused=$(echo "$VM_CONFIG" | grep '^unused' || echo "")
    if [[ -n "$unused" ]]; then
        fail "Orphaned disks found (unused*) — OS disk likely stranded!"
        echo "$unused" | while IFS= read -r line; do fail "  ${line}"; done
        fix "This is the Terraform disk slot mismatch issue."
        fix "Run the disk fix procedure:"
        local unused_disk
        unused_disk=$(echo "$unused" | head -1 | awk -F': ' '{print $2}' | awk -F',' '{print $1}')
        local active_disk_slot
        active_disk_slot=$(echo "$disks" | head -1 | cut -d: -f1)
        fix "  ssh root@${NODE_IP}"
        fix "  qm stop ${VMID} --timeout 30"
        fix "  qm set ${VMID} --delete ${active_disk_slot}"
        fix "  qm set ${VMID} --${active_disk_slot} ${unused_disk}"
        fix "  qm resize ${VMID} ${active_disk_slot} 50G"
        fix "  qm set ${VMID} --boot order=${active_disk_slot}"
        fix "  qm start ${VMID}"
        if $FIX_BOOT_DISK; then
            apply_disk_fix "$unused_disk" "$active_disk_slot"
        fi
    else
        ok "No orphaned disks (unused*)"
    fi

    # Check bootdisk matches actual disk
    if [[ -n "$BOOT_DISK" ]]; then
        local bootdisk_in_config
        bootdisk_in_config=$(echo "$VM_CONFIG" | grep "^${BOOT_DISK}:" | head -1)
        if [[ -z "$bootdisk_in_config" ]]; then
            fail "bootdisk '${BOOT_DISK}' not found in disk config — VM will not boot!"
            fix "Fix bootdisk to match actual disk:"
            local first_disk_slot
            first_disk_slot=$(echo "$disks" | grep -v cloudinit | head -1 | cut -d: -f1)
            fix "  ssh root@${NODE_IP} 'qm set ${VMID} --bootdisk ${first_disk_slot}'"
            fix "  ssh root@${NODE_IP} 'qm set ${VMID} --boot order=${first_disk_slot}'"
        else
            ok "bootdisk '${BOOT_DISK}' exists in config: ${bootdisk_in_config}"
        fi
    fi
}

apply_disk_fix() {
    local unused_disk="$1"
    local active_slot="$2"
    warn "Applying disk fix automatically (--fix-boot-disk)..."

    ssh $SSH_OPTS "root@${NODE_IP}" "qm stop ${VMID} --timeout 30" 2>/dev/null || true
    sleep 5
    ssh $SSH_OPTS "root@${NODE_IP}" "qm set ${VMID} --delete ${active_slot}" 2>/dev/null
    ssh $SSH_OPTS "root@${NODE_IP}" "qm set ${VMID} --${active_slot} ${unused_disk}" 2>/dev/null
    ssh $SSH_OPTS "root@${NODE_IP}" "qm resize ${VMID} ${active_slot} 50G" 2>/dev/null
    ssh $SSH_OPTS "root@${NODE_IP}" "qm set ${VMID} --boot order=${active_slot}" 2>/dev/null
    ssh $SSH_OPTS "root@${NODE_IP}" "qm start ${VMID}" 2>/dev/null
    ok "Disk fix applied — VM restarted"
}

# ─────────────────────────────────────────────────────────────────────────────
# Network config
# ─────────────────────────────────────────────────────────────────────────────
check_network() {
    hdr "─── Network Configuration ───"

    local net0
    net0=$(echo "$VM_CONFIG" | grep '^net0:' || echo "")
    VM_IP_CONFIG=$(echo "$VM_CONFIG" | grep '^ipconfig0:' || echo "")
    local nameserver
    nameserver=$(echo "$VM_CONFIG" | grep '^nameserver:' || echo "")

    info "net0:      ${net0:-not set}"
    info "ipconfig0: ${VM_IP_CONFIG:-not set}"
    info "nameserver:${nameserver:-not set}"

    [[ -z "$net0" ]] && fail "net0 not configured" && fix "qm set ${VMID} --net0 virtio,bridge=vmbr0" && return
    ok "net0 configured: ${net0}"

    if [[ -z "$VM_IP_CONFIG" ]]; then
        fail "ipconfig0 not set — VM will use DHCP or no network"
        fix "qm set ${VMID} --ipconfig0 'ip=192.168.4.X/22,gw=${GATEWAY}'"
    elif echo "$VM_IP_CONFIG" | grep -qv '/22'; then
        warn "ipconfig0 may use wrong prefix — ensure /22 not /24"
        info "  Current: ${VM_IP_CONFIG}"
        fix "Should be: ip=192.168.4.X/22,gw=${GATEWAY}"
    else
        ok "ipconfig0: ${VM_IP_CONFIG}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# GPU passthrough
# ─────────────────────────────────────────────────────────────────────────────
check_gpu() {
    hdr "─── GPU Passthrough ───"

    local hostpci
    hostpci=$(echo "$VM_CONFIG" | grep '^hostpci' || echo "")

    if [[ -z "$hostpci" ]]; then
        info "No GPU attached (hostpci not configured)"
        info "  To attach: pvesh set /nodes/${NODE}/qemu/${VMID}/config --hostpci0 0000:01:00,pcie=1,rombar=1"
        return
    fi

    info "hostpci config:"
    echo "$hostpci" | while IFS= read -r line; do info "  ${line}"; done

    # Verify machine type is q35
    local machine
    machine=$(echo "$VM_CONFIG" | grep '^machine:' | awk '{print $2}')
    if [[ "$machine" == "q35" ]]; then
        ok "Machine type: q35 (required for PCIe passthrough)"
    else
        fail "Machine type: ${machine:-i440fx (default)} — PCIe passthrough requires q35"
        fix "qm set ${VMID} --machine q35"
    fi

    # Check vfio bound on host
    local pci_addr
    pci_addr=$(echo "$hostpci" | head -1 | grep -oP '[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}' | head -1)
    if [[ -n "$pci_addr" ]]; then
        local driver
        driver=$(pve "cat /sys/bus/pci/devices/${pci_addr}.0/driver/module/drivers 2>/dev/null || echo 'unbound'")
        if echo "$driver" | grep -q "vfio"; then
            ok "Host driver for ${pci_addr}: vfio-pci"
        else
            fail "Host driver for ${pci_addr}: ${driver} (must be vfio-pci for passthrough)"
            fix "Run: ./gpu-passthrough-setup.sh ${NODE} ${pci_addr}"
        fi
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Guest agent
# ─────────────────────────────────────────────────────────────────────────────
VM_ACTUAL_IP=""
check_guest_agent() {
    hdr "─── Guest Agent ───"

    local agent_config
    agent_config=$(echo "$VM_CONFIG" | grep '^agent:' | awk '{print $2}')

    if [[ "$agent_config" != "1" && "$agent_config" != "enabled=1" ]]; then
        warn "Guest agent not enabled in VM config (agent=${agent_config:-not set})"
        fix "qm set ${VMID} --agent 1"
    else
        ok "Guest agent: enabled in config"
    fi

    if [[ "$VM_STATUS" != "running" ]]; then
        info "VM not running — skipping live agent check"
        return
    fi

    local agent_ping
    agent_ping=$(pve "qm agent ${VMID} ping 2>/dev/null && echo ok || echo fail")
    if [[ "$agent_ping" == "ok" ]]; then
        ok "Guest agent: responding to ping"

        # Get actual IP via guest agent
        VM_ACTUAL_IP=$(pve "qm agent ${VMID} network-get-interfaces 2>/dev/null \
            | python3 -c \"
import sys, json
data = json.load(sys.stdin)
for iface in data:
    if iface.get('name','') in ('ens18','eth0','enp0s18'):
        for addr in iface.get('ip-addresses',[]):
            if addr.get('ip-address-type')=='ipv4':
                print(addr['ip-address'])
                break
\" 2>/dev/null || echo ''")
        [[ -n "$VM_ACTUAL_IP" ]] && ok "Actual IP (via guest agent): ${VM_ACTUAL_IP}" \
            || warn "Could not retrieve IP via guest agent"

        # Cloud-init status
        local ci_status
        ci_status=$(pve "qm agent ${VMID} exec -- cloud-init status 2>/dev/null | grep -oP '(?<=status: )\w+' || echo unknown")
        case "$ci_status" in
            done) ok "Cloud-init status: done" ;;
            running) warn "Cloud-init still running" ;;
            error) fail "Cloud-init status: error"
                   fix "Check: qm agent ${VMID} exec -- 'cat /var/log/cloud-init-output.log | tail -30'" ;;
            *) warn "Cloud-init status: ${ci_status}" ;;
        esac
    else
        fail "Guest agent: not responding"
        fix "Install inside VM: sudo apt-get install -y qemu-guest-agent && sudo systemctl enable --now qemu-guest-agent"
        fix "Access VM console: ssh root@${NODE_IP} 'qm terminal ${VMID}'"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# SSH reachability
# ─────────────────────────────────────────────────────────────────────────────
check_ssh() {
    hdr "─── SSH Reachability ───"

    if [[ "$VM_STATUS" != "running" ]]; then
        info "VM not running — skipping SSH check"
        return
    fi

    # Determine IP to check
    local check_ip="${VM_ACTUAL_IP}"
    if [[ -z "$check_ip" ]]; then
        check_ip=$(echo "$VM_IP_CONFIG" | grep -oP '(?<=ip=)[^/]+')
    fi

    if [[ -z "$check_ip" ]]; then
        warn "Cannot determine VM IP for SSH test"
        return
    fi

    info "Testing SSH to ubuntu@${check_ip}..."
    if ssh $SSH_OPTS "ubuntu@${check_ip}" 'hostname' &>/dev/null 2>&1; then
        ok "SSH to ubuntu@${check_ip}: connected"

        # Check IP matches expected
        local actual_ip
        actual_ip=$(ssh $SSH_OPTS "ubuntu@${check_ip}" "ip -4 addr show ens18 2>/dev/null | grep -oP '(?<=inet )[^/]+' | head -1" || echo "")
        if [[ -n "$actual_ip" ]]; then
            info "  VM reports: ${actual_ip}"
            [[ "$actual_ip" == "$check_ip" ]] && ok "IP matches expected" || warn "IP mismatch: VM is ${actual_ip}, expected ${check_ip}"
        fi
    else
        fail "SSH to ubuntu@${check_ip}: not reachable"
        fix "Check cloud-init network config: ssh root@${NODE_IP} 'qm terminal ${VMID}'"
        fix "Inside VM: ip addr show && cloud-init status && cat /var/log/cloud-init-output.log | tail -20"
        fix "If DHCP: sudo netplan set ethernets.ens18.dhcp4=false && sudo netplan set ethernets.ens18.addresses=[${check_ip}/22] && sudo netplan apply"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo -e "${BOLD}─── Diagnostic Summary ───${NC}"
    echo -e "  VM ID:   ${VMID}"
    echo -e "  Node:    ${NODE} (${NODE_IP})"
    echo -e "  State:   ${VM_STATUS:-unknown}"
    [[ -n "$VM_ACTUAL_IP" ]] && echo -e "  IP:      ${VM_ACTUAL_IP}"
    echo ""

    if $ISSUES_FOUND; then
        fail "Issues found — review 💡 Fix suggestions above"
        echo ""
        echo -e "  Full log: ${LOG_FILE}"
        exit 1
    else
        ok "No issues found — VM appears healthy"
        exit 0
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BOLD}=== vm-troubleshoot.sh — VM ${VMID} ===${NC}"
    info "Started: $(date)"
    info "Log: ${LOG_FILE}"

    find_node
    check_state
    check_config
    check_boot_disk
    check_network
    check_gpu
    check_guest_agent
    check_ssh
    print_summary
}

main "$@"
