#!/usr/bin/env bash
# cluster-health.sh — Full Proxmox cluster health validation
#
# Usage:
#   ./cluster-health.sh [--json] [--quiet]
#
# Checks:
#   - Cluster quorum and node count
#   - Per-node API health and PVE version
#   - NFS storage (truenas-nfs) mount status on all nodes
#   - GPU presence on pve01 (P4000) and pve02 (A4500)
#   - Key VM status (ubuntu-docker, ai-node-a4500, ai-node-p4000)
#   - Corosync ring0 IP consistency
#
# Output:
#   - Colorized terminal report
#   - Markdown report written to logs/cluster-health-YYYY-MM-DD.md
#   - Exit 0 if all checks pass, 1 if any check fails
#
# Exit codes: 0=all healthy, 1=one or more checks failed

set -uo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/$(date +%Y-%m-%d).log"
REPORT_FILE="${LOG_DIR}/cluster-health-$(date +%Y-%m-%d).md"
SSH_OPTS="-o ConnectTimeout=8 -o BatchMode=yes -o StrictHostKeyChecking=no"

# Cluster config
PRIMARY_NODE="pve01"
PRIMARY_IP="192.168.4.10"
declare -A NODE_IPS=( [pve01]="192.168.4.10" [pve02]="192.168.4.11" [pve03-7090]="192.168.4.12" [pve04-7090]="192.168.4.13" )
NFS_STORAGE="truenas-nfs"
EXPECTED_PVE_VERSION="9"   # major version check
EXPECTED_NODES=4

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

JSON_MODE=false
QUIET=false
OVERALL_STATUS=0

for arg in "$@"; do
    [[ "$arg" == "--json" ]]  && JSON_MODE=true
    [[ "$arg" == "--quiet" ]] && QUIET=true
done

mkdir -p "$LOG_DIR"
_ts() { date '+%Y-%m-%d %H:%M:%S'; }
log()  { local m="[$(_ts)] [INFO]  $*"; $QUIET || echo -e "${m}"; echo "${m}" >> "$LOG_FILE"; }
ok()   { local m="[$(_ts)] [OK]    $*"; $QUIET || echo -e "${GREEN}✅ ${m}${NC}"; echo "${m}" >> "$LOG_FILE"; }
warn() { local m="[$(_ts)] [WARN]  $*"; $QUIET || echo -e "${YELLOW}⚠️  ${m}${NC}"; echo "${m}" >> "$LOG_FILE"; }
fail() { local m="[$(_ts)] [FAIL]  $*"; $QUIET || echo -e "${RED}❌ ${m}${NC}"; echo "${m}" >> "$LOG_FILE"; OVERALL_STATUS=1; }
hdr()  { $QUIET || echo -e "\n${BOLD}${CYAN}$*${NC}"; }

pve_ssh() { ssh $SSH_OPTS "root@${PRIMARY_IP}" "$*" 2>/dev/null || echo ""; }

# ─────────────────────────────────────────────────────────────────────────────
# Check connectivity
# ─────────────────────────────────────────────────────────────────────────────
check_connectivity() {
    hdr "─── SSH Connectivity ───"

    if ! ssh $SSH_OPTS "root@${PRIMARY_IP}" 'hostname' &>/dev/null; then
        fail "Cannot reach primary node ${PRIMARY_NODE} (${PRIMARY_IP}) via SSH"
        fail "Most checks will be skipped. Fix SSH access first:"
        fail "  eval \"\$(ssh-agent -s)\" && ssh-add ~/.ssh/id_ed25519"
        return 1
    fi
    ok "${PRIMARY_NODE} (${PRIMARY_IP}): SSH reachable"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Cluster quorum
# ─────────────────────────────────────────────────────────────────────────────
QUORUM_STATUS=""
ONLINE_NODES=0
check_quorum() {
    hdr "─── Cluster Quorum ───"

    local pvecm_out
    pvecm_out=$(pve_ssh "pvecm status 2>/dev/null")

    if [[ -z "$pvecm_out" ]]; then
        fail "pvecm status returned no output"
        return
    fi

    # Quorate
    local quorate
    quorate=$(echo "$pvecm_out" | grep -i "quorate" | awk '{print $NF}')
    if [[ "$quorate" == "1" || "$quorate" == "Yes" ]]; then
        ok "Cluster: quorate"
        QUORUM_STATUS="QUORATE"
    else
        fail "Cluster: NOT quorate (quorate=${quorate})"
        QUORUM_STATUS="NOT_QUORATE"
    fi

    # Node count
    local expected_votes=$((EXPECTED_NODES * 1))
    local total_votes
    total_votes=$(echo "$pvecm_out" | grep -i "total votes" | awk '{print $NF}')
    local expected_votes_actual
    expected_votes_actual=$(echo "$pvecm_out" | grep -i "expected votes" | awk '{print $NF}')
    ONLINE_NODES="${total_votes:-0}"
    log "Total votes: ${total_votes:-unknown} / Expected: ${expected_votes_actual:-unknown}"

    if [[ "${total_votes}" == "${expected_votes_actual}" ]] && [[ "${total_votes}" -ge "$EXPECTED_NODES" ]]; then
        ok "All ${EXPECTED_NODES} nodes voting"
    else
        fail "Node vote mismatch — total=${total_votes:-?}, expected=${expected_votes_actual:-?}"
    fi

    # Show node list
    local node_list
    node_list=$(pve_ssh "pvecm nodes 2>/dev/null" || echo "")
    log "Node list:\n${node_list}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Per-node API health
# ─────────────────────────────────────────────────────────────────────────────
declare -A NODE_API_STATUS
check_node_apis() {
    hdr "─── Node API Health ───"

    for node in "${!NODE_IPS[@]}"; do
        local ip="${NODE_IPS[$node]}"
        local http_code
        http_code=$(curl -sk -o /dev/null -w "%{http_code}" "https://${ip}:8006/api2/json/version" \
            --max-time 5 2>/dev/null || echo "000")

        local version=""
        if [[ "$http_code" == "200" || "$http_code" == "401" ]]; then
            # 401 = auth required but API is up
            version=$(curl -sk "https://${ip}:8006/api2/json/version" --max-time 5 2>/dev/null \
                | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('version','?'))" 2>/dev/null || echo "?")
            ok "${node} (${ip}): API up — PVE ${version}"
            NODE_API_STATUS[$node]="UP"
        else
            fail "${node} (${ip}): API unreachable (HTTP ${http_code})"
            NODE_API_STATUS[$node]="DOWN"
        fi
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# NFS storage
# ─────────────────────────────────────────────────────────────────────────────
check_nfs() {
    hdr "─── NFS Storage (${NFS_STORAGE}) ───"

    for node in "${!NODE_IPS[@]}"; do
        local ip="${NODE_IPS[$node]}"
        if [[ "${NODE_API_STATUS[$node]:-DOWN}" == "DOWN" ]]; then
            warn "${node}: skipping NFS check (API down)"
            continue
        fi

        local nfs_status
        nfs_status=$(ssh $SSH_OPTS "root@${ip}" \
            "pvesm status | grep '${NFS_STORAGE}'" 2>/dev/null || echo "")

        if echo "$nfs_status" | grep -q "available\|active"; then
            local used total
            used=$(echo "$nfs_status" | awk '{print $5}')
            total=$(echo "$nfs_status" | awk '{print $4}')
            ok "${node}: ${NFS_STORAGE} — available (${used}/${total} bytes used)"
        elif [[ -z "$nfs_status" ]]; then
            fail "${node}: ${NFS_STORAGE} not found in pvesm output"
        else
            fail "${node}: ${NFS_STORAGE} — ${nfs_status}"
        fi
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# GPU presence check
# ─────────────────────────────────────────────────────────────────────────────
declare -A GPU_STATUS
check_gpus() {
    hdr "─── GPU Presence ───"

    # pve01 — Quadro P4000 (10de:1bb1)
    local p4000_out
    p4000_out=$(ssh $SSH_OPTS "root@${NODE_IPS[pve01]}" \
        "lspci -nn | grep -i '1bb1\|P4000\|GP104GL'" 2>/dev/null || echo "")
    if [[ -n "$p4000_out" ]]; then
        ok "pve01: Quadro P4000 present — ${p4000_out}"
        GPU_STATUS[pve01]="OK"
    else
        warn "pve01: Quadro P4000 (10de:1bb1) not found via lspci"
        GPU_STATUS[pve01]="MISSING"
    fi

    # pve01 — check vfio binding
    local p4000_driver
    p4000_driver=$(ssh $SSH_OPTS "root@${NODE_IPS[pve01]}" \
        "cat /sys/bus/pci/devices/0000:01:00.0/driver/module/drivers 2>/dev/null || echo 'unbound'" || echo "unknown")
    if echo "$p4000_driver" | grep -q "vfio"; then
        ok "pve01: P4000 driver = vfio-pci ✓"
    else
        warn "pve01: P4000 driver = ${p4000_driver} (not vfio-pci — passthrough not ready)"
    fi

    # pve02 — RTX A4500 (10de:24ba — laptop variant)
    local a4500_out
    a4500_out=$(ssh $SSH_OPTS "root@${NODE_IPS[pve02]}" \
        "lspci -nn | grep -i '24ba\|A4500\|GA104'" 2>/dev/null || echo "")
    if [[ -n "$a4500_out" ]]; then
        ok "pve02: RTX A4500 (GA104GLM) present — ${a4500_out}"
        GPU_STATUS[pve02]="OK"
    else
        warn "pve02: RTX A4500 (10de:24ba) not found via lspci"
        GPU_STATUS[pve02]="MISSING"
    fi

    # pve02 — check vfio binding
    local a4500_driver
    a4500_driver=$(ssh $SSH_OPTS "root@${NODE_IPS[pve02]}" \
        "cat /sys/bus/pci/devices/0000:01:00.0/driver/module/drivers 2>/dev/null || echo 'unbound'" || echo "unknown")
    if echo "$a4500_driver" | grep -q "vfio"; then
        ok "pve02: A4500 driver = vfio-pci ✓"
    else
        warn "pve02: A4500 driver = ${a4500_driver} (not vfio-pci — passthrough not ready)"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Key VM status
# ─────────────────────────────────────────────────────────────────────────────
check_vms() {
    hdr "─── Key VM Status ───"

    declare -A TARGET_VMS=(
        [ubuntu-docker]="${NODE_IPS[pve02]}"
        [ai-node-a4500]="${NODE_IPS[pve02]}"
        [ai-node-p4000]="${NODE_IPS[pve01]}"
    )

    for vm_name in "${!TARGET_VMS[@]}"; do
        local node_ip="${TARGET_VMS[$vm_name]}"
        local vm_info
        vm_info=$(ssh $SSH_OPTS "root@${node_ip}" \
            "qm list | grep '${vm_name}'" 2>/dev/null || echo "")

        if [[ -z "$vm_info" ]]; then
            warn "${vm_name}: not found on node ${node_ip}"
            continue
        fi

        local vmid status
        vmid=$(echo "$vm_info" | awk '{print $1}')
        status=$(echo "$vm_info" | awk '{print $3}')

        if [[ "$status" == "running" ]]; then
            ok "${vm_name} (ID=${vmid}): running"

            # Quick guest agent ping
            local agent_ok
            agent_ok=$(ssh $SSH_OPTS "root@${node_ip}" \
                "qm agent ${vmid} ping 2>/dev/null && echo ok || echo fail" || echo "fail")
            if [[ "$agent_ok" == "ok" ]]; then
                ok "${vm_name}: guest agent responding"
            else
                warn "${vm_name}: guest agent not responding (qemu-guest-agent may not be installed)"
            fi
        else
            fail "${vm_name} (ID=${vmid}): ${status}"
        fi
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Corosync ring0 IP check
# ─────────────────────────────────────────────────────────────────────────────
check_corosync() {
    hdr "─── Corosync Ring0 IPs ───"

    local corosync_conf
    corosync_conf=$(pve_ssh "cat /etc/pve/corosync.conf 2>/dev/null || echo ''")

    if [[ -z "$corosync_conf" ]]; then
        warn "Could not read /etc/pve/corosync.conf"
        return
    fi

    local legacy_ips=("192.168.4.2" "192.168.4.3" "192.168.4.4")
    local found_legacy=false

    for ip in "${legacy_ips[@]}"; do
        if echo "$corosync_conf" | grep -q "$ip"; then
            warn "Legacy IP ${ip} found in corosync.conf (pre-migration address)"
            warn "  Action: Update ring0_addr entries to match 192.168.4.10–.13"
            found_legacy=true
        fi
    done

    if ! $found_legacy; then
        ok "Corosync ring0 IPs: no legacy addresses detected"
    else
        warn "Non-critical: cluster is functional, but corosync.conf should be updated"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Write markdown report
# ─────────────────────────────────────────────────────────────────────────────
write_report() {
    local status_str
    [[ $OVERALL_STATUS -eq 0 ]] && status_str="✅ HEALTHY" || status_str="❌ DEGRADED"

    cat > "$REPORT_FILE" <<MDEOF
# Cluster Health Report — Shoop-Homelab
**Generated:** $(date '+%Y-%m-%d %H:%M:%S')
**Status:** ${status_str}

## Node Summary
| Node | IP | API | GPU |
|:-----|:---|:----|:----|
| pve01 | 192.168.4.10 | ${NODE_API_STATUS[pve01]:-?} | ${GPU_STATUS[pve01]:-N/A} (P4000) |
| pve02 | 192.168.4.11 | ${NODE_API_STATUS[pve02]:-?} | ${GPU_STATUS[pve02]:-N/A} (A4500) |
| pve03-7090 | 192.168.4.12 | ${NODE_API_STATUS[pve03-7090]:-?} | — |
| pve04-7090 | 192.168.4.13 | ${NODE_API_STATUS[pve04-7090]:-?} | — |

## Quorum
- Status: ${QUORUM_STATUS:-UNKNOWN}
- Online nodes: ${ONLINE_NODES:-?} / ${EXPECTED_NODES}

## NFS Storage
- Pool: ${NFS_STORAGE}
- Expected on all 4 nodes

## Service IPs
| Service | IP |
|:--------|:---|
| pihole-dns (LXC) | 192.168.4.2 |
| truenas-nfs | 192.168.4.5 |
| ubuntu-docker | 192.168.4.20 |
| ai-node-a4500 | 192.168.4.15 |
| ai-node-p4000 | 192.168.4.16 |

## Log
See: \`${LOG_FILE}\`
MDEOF

    log "Markdown report written: ${REPORT_FILE}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║   Shoop-Homelab — Cluster Health     ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"
    log "Started: $(date)"
    log "Log: ${LOG_FILE}"
    echo ""

    check_connectivity || { write_report; exit 1; }
    check_quorum
    check_node_apis
    check_nfs
    check_gpus
    check_vms
    check_corosync
    write_report

    echo ""
    echo -e "${BOLD}─── Result ───${NC}"
    if [[ $OVERALL_STATUS -eq 0 ]]; then
        ok "All checks passed — cluster is healthy"
    else
        fail "One or more checks failed — review output above"
        log "Full log: ${LOG_FILE}"
        log "Report:   ${REPORT_FILE}"
    fi
    echo ""
    log "Report: ${REPORT_FILE}"

    exit $OVERALL_STATUS
}

main "$@"
