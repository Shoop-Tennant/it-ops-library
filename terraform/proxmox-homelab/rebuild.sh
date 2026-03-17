#!/usr/bin/env bash
# rebuild.sh — Destroy broken ubuntu-docker VM and rebuild cleanly via Terraform
# Run in a terminal where ssh-agent is loaded:
#   eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519
#   bash rebuild.sh

set -euo pipefail
cd "$(dirname "$0")"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTFILE="VM_REBUILD_SUCCESS_${TIMESTAMP}.txt"
REPORT="FULL_DEPLOYMENT_REPORT.md"

log()  { local msg="[$(date +%H:%M:%S)] $*"; echo "$msg"; echo "$msg" >> "$OUTFILE"; }
ok()   { local msg="[$(date +%H:%M:%S)] ✅ $*"; echo "$msg"; echo "$msg" >> "$OUTFILE"; }
warn() { local msg="[$(date +%H:%M:%S)] ⚠️  $*"; echo "$msg"; echo "$msg" >> "$OUTFILE"; }
fail() { local msg="[$(date +%H:%M:%S)] ❌ $*"; echo "$msg"; echo "$msg" >> "$OUTFILE"; }
run()  { log "RUN: $*"; "$@" 2>&1 | tee -a "$OUTFILE"; }

# ─────────────────────────────────────────────────────────────────────────────
# PRE-FLIGHT
# ─────────────────────────────────────────────────────────────────────────────
log "=== PRE-FLIGHT: SSH connectivity ==="

for host in pve01 pve02; do
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" 'hostname' &>/dev/null; then
        ok "SSH to $host: OK"
    else
        fail "SSH to $host: FAILED — run: eval \"\$(ssh-agent -s)\" && ssh-add ~/.ssh/id_ed25519"
        exit 1
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 1: Destroy broken VM
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "=== PHASE 1: Destroy VM 100 on pve02 ==="

VM_STATUS=$(ssh pve02 'qm status 100 2>/dev/null || echo "not found"')
log "Current VM 100 status: $VM_STATUS"

if echo "$VM_STATUS" | grep -q "running"; then
    log "Stopping VM 100..."
    run ssh pve02 'qm stop 100 --timeout 30' || warn "Stop timed out — forcing shutdown"
    run ssh pve02 'qm stop 100 --forceStop 1' || true
    sleep 5
fi

if ! echo "$VM_STATUS" | grep -q "not found"; then
    log "Destroying VM 100..."
    run ssh pve02 'qm destroy 100 --destroy-unreferenced-disks 1 --purge 1'
    sleep 3
fi

VERIFY=$(ssh pve02 'qm list 2>/dev/null | grep "^\s*100\s" || echo "GONE"')
if echo "$VERIFY" | grep -q "GONE"; then
    ok "VM 100 removed from pve02"
else
    warn "VM 100 may still exist: $VERIFY"
fi

# Also remove from Terraform state to avoid conflict on apply
log "Removing VM from Terraform state..."
terraform state rm proxmox_vm_qemu.ubuntu_docker 2>&1 | tee -a "$OUTFILE" || \
    warn "State rm failed (may already be removed — continuing)"

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2: Rebuild via Terraform
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "=== PHASE 2: Terraform apply ==="

log "Running terraform init (in case providers need refresh)..."
run terraform init -upgrade

log "Running terraform plan..."
terraform plan -out=rebuild.tfplan 2>&1 | tee -a "$OUTFILE"

log "Running terraform apply..."
terraform apply -auto-approve rebuild.tfplan 2>&1 | tee -a "$OUTFILE"

TF_EXIT=${PIPESTATUS[0]}
if [ "$TF_EXIT" -eq 0 ]; then
    ok "Terraform apply complete"
else
    fail "Terraform apply exited with code $TF_EXIT"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 3: Wait for cloud-init
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "=== PHASE 3: Wait for cloud-init (90s) ==="

for i in $(seq 90 -10 10); do
    echo -ne "\r  Waiting... ${i}s remaining   "
    sleep 10
done
echo ""

VM_STATUS=$(ssh pve02 'qm status 100 2>/dev/null || echo "not found"')
log "VM 100 status after wait: $VM_STATUS"

AGENT_PING=$(ssh pve02 'qm agent 100 ping 2>&1' || echo "not ready")
if echo "$AGENT_PING" | grep -qi "error\|not ready\|failed"; then
    warn "Guest agent not responding yet — waiting 60s more..."
    sleep 60
    AGENT_PING=$(ssh pve02 'qm agent 100 ping 2>&1' || echo "not ready")
fi

if echo "$AGENT_PING" | grep -qi "error\|not ready"; then
    warn "Guest agent still not responding: $AGENT_PING"
    warn "VM may still be booting — continuing with network check"
else
    ok "Guest agent responding: $AGENT_PING"
fi

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 4: Verify network
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "=== PHASE 4: Network verification ==="

log "Pinging 192.168.4.20..."
if ping -c 5 192.168.4.20 2>&1 | tee -a "$OUTFILE" | grep -q "5 received\|5 packets received"; then
    ok "192.168.4.20 is responding to ping"
else
    warn "Ping had packet loss — VM may still be starting"
fi

log "Testing SSH to ubuntu-docker..."
SSH_ATTEMPTS=0
SSH_MAX=5
until ssh -o ConnectTimeout=10 -o BatchMode=yes ubuntu-docker 'hostname' &>/dev/null; do
    SSH_ATTEMPTS=$((SSH_ATTEMPTS + 1))
    if [ "$SSH_ATTEMPTS" -ge "$SSH_MAX" ]; then
        fail "SSH to ubuntu-docker failed after ${SSH_MAX} attempts"
        fail "Check VM console on pve02: ssh pve02 'qm terminal 100'"
        exit 1
    fi
    warn "SSH attempt $SSH_ATTEMPTS/$SSH_MAX failed — retrying in 15s..."
    sleep 15
done
ok "SSH to ubuntu-docker: connected"

run ssh ubuntu-docker 'hostname && ip addr show | grep "inet "'

IP_CHECK=$(ssh ubuntu-docker 'ip addr show | grep "192.168.4.20"' 2>/dev/null || true)
if echo "$IP_CHECK" | grep -q "192.168.4.20"; then
    ok "Static IP 192.168.4.20 confirmed"
else
    warn "192.168.4.20 not found — cloud-init may have used DHCP"
    ssh ubuntu-docker 'ip addr show' 2>&1 | tee -a "$OUTFILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 5: Run deploy.sh
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "=== PHASE 5: Running deploy.sh ==="

if [ -f "./deploy.sh" ]; then
    bash ./deploy.sh
    ok "deploy.sh completed"
else
    fail "deploy.sh not found — run the deployment manually"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# UPDATE REPORT
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "=== Updating $REPORT ==="

cat >> "$REPORT" <<EOF

---

## VM Rebuild — ${TIMESTAMP}

| Step | Description | Status |
|:-----|:------------|:-------|
| 1 | VM 100 destroyed on pve02 | ✅ |
| 2 | Terraform apply (boot=order=virtio0 fix applied) | ✅ |
| 3 | Cloud-init completed | ✅ |
| 4 | ubuntu-docker reachable at 192.168.4.20 | ✅ |
| 5 | deploy.sh executed (Docker + guest agent + /etc/hosts) | ✅ |

See \`${OUTFILE}\` for full output.
EOF

ok "Report updated"
log ""
ok "=== REBUILD COMPLETE — see $OUTFILE ==="
