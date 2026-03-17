#!/usr/bin/env bash
# gpu-passthrough-setup.sh — Configure VFIO/IOMMU GPU passthrough on a Proxmox node
#
# Usage:
#   ./gpu-passthrough-setup.sh [--dry-run] <node> <pci_address>
#
# Examples:
#   ./gpu-passthrough-setup.sh pve01 0000:01:00        # P4000 on pve01
#   ./gpu-passthrough-setup.sh pve02 0000:01:00        # A4500 on pve02
#   ./gpu-passthrough-setup.sh --dry-run pve01 0000:01:00
#
# What this script does:
#   1. Validates IOMMU is enabled (or tells you how to enable it)
#   2. Discovers GPU + audio device IDs from the PCI address
#   3. Checks IOMMU group isolation (warns if not isolated)
#   4. Writes /etc/modprobe.d/vfio.conf with GPU device IDs
#   5. Adds vfio modules to /etc/modules
#   6. Updates initramfs
#   7. Warns that a reboot is required
#
# After reboot, verify with:
#   cat /sys/bus/pci/devices/0000:01:00.0/driver/module/drivers
#   # Should show: pci:vfio-pci
#
# Exit codes: 0=success, 1=error, 2=usage error

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/$(date +%Y-%m-%d).log"
SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'; BOLD='\033[1m'

mkdir -p "$LOG_DIR"
log()  { local m="[$(date +%Y-%m-%d\ %H:%M:%S)] [INFO]  $*"; echo -e "${m}"; echo "${m}" >> "$LOG_FILE"; }
ok()   { local m="[$(date +%Y-%m-%d\ %H:%M:%S)] [OK]    $*"; echo -e "${GREEN}✅ ${m}${NC}"; echo "${m}" >> "$LOG_FILE"; }
warn() { local m="[$(date +%Y-%m-%d\ %H:%M:%S)] [WARN]  $*"; echo -e "${YELLOW}⚠️  ${m}${NC}"; echo "${m}" >> "$LOG_FILE"; }
fail() { local m="[$(date +%Y-%m-%d\ %H:%M:%S)] [ERROR] $*"; echo -e "${RED}❌ ${m}${NC}" >&2; echo "${m}" >> "$LOG_FILE"; }
die()  { fail "$*"; exit 1; }
die2() { fail "$*"; usage; exit 2; }

usage() {
    echo ""
    echo -e "${BOLD}Usage:${NC} $SCRIPT_NAME [--dry-run] <node> <pci_address>"
    echo ""
    echo "  node         Proxmox node name (pve01, pve02, etc.)"
    echo "  pci_address  PCI slot without function (e.g. 0000:01:00)"
    echo ""
    echo "  --dry-run    Show what would be done without making changes"
    echo ""
    echo "  Examples:"
    echo "    $SCRIPT_NAME pve01 0000:01:00"
    echo "    $SCRIPT_NAME --dry-run pve02 0000:01:00"
}

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && { DRY_RUN=true; shift; }
[[ $# -ne 2 ]] && die2 "Expected 2 arguments, got $#"

NODE="$1"
PCI_BASE="$2"      # e.g. 0000:01:00 (no .0 suffix)
PCI_GPU="${PCI_BASE}.0"
PCI_AUDIO="${PCI_BASE}.1"

run() {
    if $DRY_RUN; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $*"
        echo "[DRY-RUN] $*" >> "$LOG_FILE"
    else
        log "Running: $*"
        eval "$@"
    fi
}
pve()     { run "ssh $SSH_OPTS root@${NODE} \"$*\""; }
pve_get() { ssh $SSH_OPTS "root@${NODE}" "$*" 2>/dev/null || echo ""; }

# ─────────────────────────────────────────────────────────────────────────────
# Pre-flight
# ─────────────────────────────────────────────────────────────────────────────
preflight() {
    log "=== PRE-FLIGHT ==="

    ssh $SSH_OPTS "root@${NODE}" 'hostname' &>/dev/null \
        || die "Cannot SSH to root@${NODE}. Check SSH key authorization."
    ok "SSH to ${NODE}: connected"

    # Validate PCI address format
    [[ "$PCI_BASE" =~ ^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}$ ]] \
        || die2 "PCI address format must be XXXX:XX:XX (e.g. 0000:01:00), got: ${PCI_BASE}"

    # Check device exists
    local dev_info
    dev_info=$(pve_get "lspci -nn -s ${PCI_GPU} 2>/dev/null")
    [[ -n "$dev_info" ]] || die "PCI device ${PCI_GPU} not found on ${NODE}. Run: ssh root@${NODE} 'lspci -nn | grep -i nvidia'"
    log "GPU device: ${dev_info}"
    ok "PCI device ${PCI_GPU}: found"
}

# ─────────────────────────────────────────────────────────────────────────────
# Check IOMMU
# ─────────────────────────────────────────────────────────────────────────────
check_iommu() {
    log "=== CHECKING IOMMU ==="

    local iommu_dmesg
    iommu_dmesg=$(pve_get "dmesg | grep -i iommu | head -5")

    if echo "$iommu_dmesg" | grep -qi "iommu enabled\|DMAR.*remapping\|AMD-Vi"; then
        ok "IOMMU is enabled"
        log "${iommu_dmesg}"
    else
        warn "IOMMU may not be enabled. dmesg output:"
        log "${iommu_dmesg:-  (no iommu messages found)}"
        warn "To enable IOMMU, edit /etc/default/grub on ${NODE}:"
        warn "  For Intel: GRUB_CMDLINE_LINUX_DEFAULT=\"quiet intel_iommu=on iommu=pt\""
        warn "  For AMD:   GRUB_CMDLINE_LINUX_DEFAULT=\"quiet amd_iommu=on iommu=pt\""
        warn "Then: update-grub && reboot"
        warn "Continuing anyway — VFIO config will still be written."
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Discover device IDs
# ─────────────────────────────────────────────────────────────────────────────
discover_device_ids() {
    log "=== DISCOVERING DEVICE IDs ==="

    GPU_ID=$(pve_get "lspci -nn -s ${PCI_GPU} | grep -oP '\[\K[0-9a-f]{4}:[0-9a-f]{4}(?=\])' | tail -1")
    [[ -n "$GPU_ID" ]] || die "Could not extract device ID from ${PCI_GPU}"
    log "GPU device ID: ${GPU_ID}"
    ok "GPU: ${GPU_ID}"

    AUDIO_ID=$(pve_get "lspci -nn -s ${PCI_AUDIO} | grep -oP '\[\K[0-9a-f]{4}:[0-9a-f]{4}(?=\])' | tail -1")
    if [[ -n "$AUDIO_ID" ]]; then
        ok "Audio function: ${AUDIO_ID}"
        DEVICE_IDS="${GPU_ID},${AUDIO_ID}"
    else
        warn "No audio function found at ${PCI_AUDIO} — using GPU only"
        DEVICE_IDS="${GPU_ID}"
    fi

    log "VFIO device IDs: ${DEVICE_IDS}"

    # Show full GPU info for the log
    local full_info
    full_info=$(pve_get "lspci -nn -s ${PCI_GPU}")
    log "Full GPU info: ${full_info}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Check IOMMU group isolation
# ─────────────────────────────────────────────────────────────────────────────
check_iommu_group() {
    log "=== CHECKING IOMMU GROUP ISOLATION ==="

    local iommu_group_path
    iommu_group_path=$(pve_get "readlink -f /sys/bus/pci/devices/${PCI_GPU}/iommu_group")
    local group_num="${iommu_group_path##*/}"
    log "IOMMU group: ${group_num}"

    local group_members
    group_members=$(pve_get "ls /sys/bus/pci/devices/${PCI_GPU}/iommu_group/devices/")
    log "Group members:"
    log "${group_members}"

    # Count PCIe endpoint devices (exclude root ports which are OK)
    local endpoint_count
    endpoint_count=$(pve_get "
        for dev in /sys/bus/pci/devices/${PCI_GPU}/iommu_group/devices/*; do
            devclass=\$(cat \"\$dev/class\" 2>/dev/null || echo 0x000000)
            # 0x060400 = PCIe root port / bridge — these are OK in the group
            [[ \"\$devclass\" != \"0x060400\" ]] && echo \"\$(basename \$dev)\"
        done | wc -l
    " || echo "unknown")

    if [[ "$endpoint_count" -le 2 ]]; then
        ok "IOMMU group ${group_num}: well isolated (${endpoint_count} endpoint(s))"
    else
        warn "IOMMU group ${group_num} has ${endpoint_count} endpoints — may not be fully isolated"
        warn "Group members: ${group_members}"
        warn "If passthrough fails, you may need ACS override (adds security risk)"
        warn "ACS override GRUB option: pcie_acs_override=downstream,multifunction"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Configure VFIO
# ─────────────────────────────────────────────────────────────────────────────
configure_vfio() {
    log "=== CONFIGURING VFIO ==="

    # Check current state
    local current_vfio_conf
    current_vfio_conf=$(pve_get "cat /etc/modprobe.d/vfio.conf 2>/dev/null || echo ''")

    if echo "$current_vfio_conf" | grep -q "${GPU_ID}"; then
        ok "GPU ${GPU_ID} already in /etc/modprobe.d/vfio.conf"
        log "Current config: ${current_vfio_conf}"
    else
        log "Writing /etc/modprobe.d/vfio.conf with device IDs: ${DEVICE_IDS}..."
        pve "cat > /etc/modprobe.d/vfio.conf << 'VFIOEOF'
options vfio-pci ids=${DEVICE_IDS}
options vfio-pci disable_vga=1
VFIOEOF"
        ok "/etc/modprobe.d/vfio.conf written"
    fi

    # Add vfio modules to /etc/modules
    local modules_file="/etc/modules"
    local vfio_modules=("vfio" "vfio_iommu_type1" "vfio_pci")

    for mod in "${vfio_modules[@]}"; do
        local mod_present
        mod_present=$(pve_get "grep -c '^${mod}$' ${modules_file} 2>/dev/null || echo 0")
        if [[ "$mod_present" -eq 0 ]]; then
            log "Adding ${mod} to ${modules_file}..."
            pve "echo '${mod}' >> ${modules_file}"
            ok "Added: ${mod}"
        else
            ok "${mod}: already in ${modules_file}"
        fi
    done

    # Blacklist nouveau/nvidia on the host (if present)
    local blacklist_file="/etc/modprobe.d/blacklist-nvidia.conf"
    local blacklist_exists
    blacklist_exists=$(pve_get "test -f ${blacklist_file} && echo 1 || echo 0")
    if [[ "$blacklist_exists" -eq 0 ]]; then
        log "Writing ${blacklist_file} to prevent host driver loading..."
        pve "cat > ${blacklist_file} << 'BLEOF'
blacklist nouveau
blacklist nvidia
blacklist nvidiafb
BLEOF"
        ok "Host NVIDIA/nouveau blacklisted"
    else
        ok "Blacklist file already exists: ${blacklist_file}"
    fi

    # Update initramfs
    log "Updating initramfs (update-initramfs -u -k all)..."
    pve "update-initramfs -u -k all 2>&1 | tail -5"
    ok "initramfs updated"
}

# ─────────────────────────────────────────────────────────────────────────────
# Show current driver binding
# ─────────────────────────────────────────────────────────────────────────────
check_current_driver() {
    log "=== CURRENT DRIVER STATUS ==="
    local current_driver
    current_driver=$(pve_get "cat /sys/bus/pci/devices/${PCI_GPU}/driver/module/drivers 2>/dev/null || echo 'none/unbound'")
    log "Current driver for ${PCI_GPU}: ${current_driver}"

    if echo "$current_driver" | grep -q "vfio"; then
        ok "vfio-pci already bound — no reboot needed"
        REBOOT_NEEDED=false
    else
        warn "Current driver: ${current_driver}"
        REBOOT_NEEDED=true
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
REBOOT_NEEDED=true

main() {
    echo ""
    echo -e "${BOLD}=== gpu-passthrough-setup.sh ===${NC}"
    log "Started at $(date)"
    log "Node: ${NODE} | PCI: ${PCI_BASE}"
    echo ""

    $DRY_RUN && warn "Dry-run mode — no changes will be made"

    preflight
    check_iommu
    discover_device_ids
    check_iommu_group
    check_current_driver
    configure_vfio

    echo ""
    echo -e "${BOLD}=== SUMMARY ===${NC}"
    ok "VFIO configuration complete for ${PCI_GPU} on ${NODE}"
    log "  GPU device IDs: ${DEVICE_IDS}"
    log "  vfio.conf:      /etc/modprobe.d/vfio.conf"
    log "  modules:        /etc/modules (vfio, vfio_iommu_type1, vfio_pci)"

    if $REBOOT_NEEDED; then
        echo ""
        warn "═══════════════════════════════════════════════"
        warn "REBOOT REQUIRED on ${NODE} to activate VFIO"
        warn "  ssh root@${NODE} 'reboot'"
        warn "After reboot, verify:"
        warn "  ssh root@${NODE} 'cat /sys/bus/pci/devices/${PCI_GPU}/driver/module/drivers'"
        warn "  # Expected: pci:vfio-pci"
        warn "═══════════════════════════════════════════════"
    fi

    echo ""
    log "Hostpci0 value for Terraform / pvesh:"
    log "  ${PCI_BASE},pcie=1,rombar=1"
    log ""
    log "pvesh command to attach to a VM:"
    log "  pvesh set /nodes/${NODE}/qemu/<VMID>/config --hostpci0 ${PCI_BASE},pcie=1,rombar=1"
}

main "$@"
