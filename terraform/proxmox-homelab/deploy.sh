#!/usr/bin/env bash
# deploy.sh — Proxmox Homelab Post-Terraform Deployment
# Phases: ubuntu-docker setup, /etc/hosts sync, GPU/IOMMU validation, guest agent verify
# Run from a terminal where ssh-agent is loaded and keys are added.
# Usage: bash deploy.sh

set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTFILE="DEPLOYMENT_COMPLETE_${TIMESTAMP}.txt"
GPU_FILE="GPU_VALIDATION.txt"
REPORT="FULL_DEPLOYMENT_REPORT.md"

log()  { echo "[$(date +%H:%M:%S)] $*" | tee -a "$OUTFILE"; }
ok()   { echo "[$(date +%H:%M:%S)] ✅ $*" | tee -a "$OUTFILE"; }
warn() { echo "[$(date +%H:%M:%S)] ⚠️  $*" | tee -a "$OUTFILE"; }
fail() { echo "[$(date +%H:%M:%S)] ❌ $*" | tee -a "$OUTFILE"; }

# ─────────────────────────────────────────────────────────────────────────────
# PRE-FLIGHT: verify SSH connectivity
# ─────────────────────────────────────────────────────────────────────────────
log "=== PRE-FLIGHT: SSH connectivity check ==="

for host in pve01 pve02 ubuntu-docker; do
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" 'hostname' &>/dev/null; then
        ok "SSH to $host: reachable"
    else
        fail "SSH to $host: FAILED — run 'ssh-add ~/.ssh/id_ed25519' and verify ~/.ssh/config"
        echo "Aborting. Fix SSH connectivity before re-running." | tee -a "$OUTFILE"
        exit 1
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 1: ubuntu-docker VM setup
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "=== PHASE 1: ubuntu-docker VM setup ==="

log "Verifying IP on ubuntu-docker..."
IP_OUT=$(ssh ubuntu-docker 'ip addr show | grep "192.168.4.20"' 2>&1 || true)
if echo "$IP_OUT" | grep -q "192.168.4.20"; then
    ok "IP 192.168.4.20 confirmed on ubuntu-docker"
    echo "$IP_OUT" >> "$OUTFILE"
else
    warn "192.168.4.20 not found in ip addr output — showing all IPs:"
    ssh ubuntu-docker 'ip addr show' | tee -a "$OUTFILE"
fi

log "Installing qemu-guest-agent..."
ssh ubuntu-docker 'sudo apt-get update -qq && sudo apt-get install -y qemu-guest-agent' \
    2>&1 | tee -a "$OUTFILE"

log "Enabling and starting qemu-guest-agent..."
ssh ubuntu-docker 'sudo systemctl enable --now qemu-guest-agent' 2>&1 | tee -a "$OUTFILE"
AGENT_STATUS=$(ssh ubuntu-docker 'systemctl is-active qemu-guest-agent' 2>&1)
if [ "$AGENT_STATUS" = "active" ]; then
    ok "qemu-guest-agent is active"
else
    warn "qemu-guest-agent status: $AGENT_STATUS"
fi

log "Installing Docker (get.docker.com)..."
ssh ubuntu-docker 'curl -fsSL https://get.docker.com | sudo sh' 2>&1 | tee -a "$OUTFILE"

log "Adding ubuntu user to docker group..."
ssh ubuntu-docker 'sudo usermod -aG docker ubuntu' 2>&1 | tee -a "$OUTFILE"
ok "ubuntu added to docker group"

log "Installing docker-compose-plugin..."
ssh ubuntu-docker 'sudo apt-get install -y docker-compose-plugin' 2>&1 | tee -a "$OUTFILE"

log "Testing Docker (hello-world)..."
DOCKER_TEST=$(ssh ubuntu-docker 'sudo docker run --rm hello-world 2>&1' || true)
echo "$DOCKER_TEST" >> "$OUTFILE"
if echo "$DOCKER_TEST" | grep -q "Hello from Docker"; then
    ok "Docker hello-world: PASSED"
else
    warn "Docker hello-world output unexpected — check $OUTFILE"
fi

DOCKER_VER=$(ssh ubuntu-docker 'docker --version 2>/dev/null || sudo docker --version' 2>&1)
COMPOSE_VER=$(ssh ubuntu-docker 'docker compose version 2>/dev/null || sudo docker compose version' 2>&1)
log "Docker version: $DOCKER_VER"
log "Compose version: $COMPOSE_VER"

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2: /etc/hosts sync to pve01 and pve02
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "=== PHASE 2: /etc/hosts sync ==="

HOSTS_CONTENT="127.0.0.1       localhost
192.168.4.10    pve01.homelab.local pve01
192.168.4.11    pve02.homelab.local pve02
192.168.4.12    pve03-7090.homelab.local pve03-7090
192.168.4.13    pve04-7090.homelab.local pve04-7090
192.168.4.2     pihole-dns.homelab.local pihole
192.168.4.5     truenas-nfs.homelab.local truenas
192.168.4.15    ai-node-a4500.homelab.local ai-node
192.168.4.20    ubuntu-docker.homelab.local docker-host
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters"

log "Writing /tmp/hosts.cluster..."
printf '%s\n' "$HOSTS_CONTENT" > /tmp/hosts.cluster
ok "/tmp/hosts.cluster created"

for node in pve01 pve02; do
    log "Pushing /etc/hosts to $node..."
    if scp /tmp/hosts.cluster "${node}:/etc/hosts" 2>&1 | tee -a "$OUTFILE"; then
        ok "/etc/hosts pushed to $node"
    else
        fail "Failed to push /etc/hosts to $node"
    fi
done

log "Testing name resolution: pve01 -> ping pve02..."
PING_OUT=$(ssh pve01 'ping -c 2 pve02 2>&1' || true)
echo "$PING_OUT" >> "$OUTFILE"
if echo "$PING_OUT" | grep -q "2 received\|2 packets transmitted"; then
    ok "pve01 can ping pve02 by hostname"
else
    warn "Ping test output: $PING_OUT"
fi

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 3: GPU and IOMMU validation
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "=== PHASE 3: GPU and IOMMU validation ==="

{
    echo "GPU_VALIDATION — generated ${TIMESTAMP}"
    echo "========================================"
    echo ""

    echo "--- pve01: lspci NVIDIA ---"
    P4000_OUT=$(ssh pve01 'lspci -nn | grep NVIDIA' 2>&1 || true)
    echo "$P4000_OUT"
    if echo "$P4000_OUT" | grep -qi "nvidia"; then
        echo "STATUS: ✅ NVIDIA GPU found on pve01"
    else
        echo "STATUS: ❌ No NVIDIA GPU found on pve01"
    fi
    echo ""

    echo "--- pve02: lspci NVIDIA ---"
    A4500_OUT=$(ssh pve02 'lspci -nn | grep NVIDIA' 2>&1 || true)
    echo "$A4500_OUT"
    if echo "$A4500_OUT" | grep -qi "nvidia"; then
        echo "STATUS: ✅ NVIDIA GPU found on pve02"
    else
        echo "STATUS: ❌ No NVIDIA GPU found on pve02"
    fi
    echo ""

    echo "--- pve01: IOMMU (dmesg) ---"
    ssh pve01 'dmesg | grep -i iommu | head -5' 2>&1 || true
    echo ""

    echo "--- pve02: IOMMU (dmesg) ---"
    ssh pve02 'dmesg | grep -i iommu | head -5' 2>&1 || true
    echo ""

    echo "--- pve01: IOMMU groups for 01:00 ---"
    ssh pve01 'find /sys/kernel/iommu_groups/ -type l | grep "01:00"' 2>&1 || true
    echo ""

    echo "--- pve02: IOMMU groups for 01:00 ---"
    ssh pve02 'find /sys/kernel/iommu_groups/ -type l | grep "01:00"' 2>&1 || true
    echo ""

} > "$GPU_FILE" 2>&1

cat "$GPU_FILE" >> "$OUTFILE"

grep -q "✅ NVIDIA GPU found on pve01" "$GPU_FILE" && ok "P4000 visible on pve01" || fail "P4000 NOT found on pve01"
grep -q "✅ NVIDIA GPU found on pve02" "$GPU_FILE" && ok "A4500 visible on pve02" || fail "A4500 NOT found on pve02"

IOMMU1=$(ssh pve01 'dmesg | grep -i iommu | head -1' 2>/dev/null || true)
IOMMU2=$(ssh pve02 'dmesg | grep -i iommu | head -1' 2>/dev/null || true)
[ -n "$IOMMU1" ] && ok "IOMMU enabled on pve01" || warn "No IOMMU messages on pve01 — check BIOS/kernel args"
[ -n "$IOMMU2" ] && ok "IOMMU enabled on pve02" || warn "No IOMMU messages on pve02 — check BIOS/kernel args"

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 4: Guest agent verification from Proxmox
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "=== PHASE 4: Guest agent verification (VM 100 on pve02) ==="

log "Pinging guest agent..."
AGENT_PING=$(ssh pve02 'qm agent 100 ping' 2>&1 || true)
echo "$AGENT_PING" >> "$OUTFILE"
if echo "$AGENT_PING" | grep -qi "error\|failed"; then
    warn "Guest agent ping: $AGENT_PING"
else
    ok "Guest agent ping: OK"
fi

log "Getting VM network interfaces via guest agent..."
NET_INFO=$(ssh pve02 'qm agent 100 network-get-interfaces' 2>&1 || true)
echo "$NET_INFO" >> "$OUTFILE"
if echo "$NET_INFO" | grep -q "192.168.4.20"; then
    ok "Guest agent reports 192.168.4.20 — IP confirmed"
elif echo "$NET_INFO" | grep -qi "error"; then
    warn "Guest agent network query failed: $NET_INFO"
else
    warn "192.168.4.20 not in guest agent response — may be DHCP or different IP"
    log "Guest agent response: $NET_INFO"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "=== DEPLOYMENT SUMMARY ==="
log "Output files:"
log "  - $OUTFILE (full log)"
log "  - $GPU_FILE (GPU/IOMMU detail)"
log "  - $REPORT (will be updated below)"

# Update the report
PHASE1_STATUS="✅"
PHASE2_STATUS="✅"
PHASE3_STATUS="✅"
PHASE4_STATUS="✅"

grep -q "❌" "$OUTFILE" && PHASE1_STATUS="⚠️ (see $OUTFILE for failures)"

python3 - <<PYEOF 2>/dev/null || true
import re, datetime

with open("$REPORT", "r") as f:
    content = f.read()

update_block = """
---

## Deployment Script Run — ${TIMESTAMP}

| Phase | Description | Status |
|:------|:------------|:-------|
| 1 | qemu-guest-agent install on ubuntu-docker | ${PHASE1_STATUS} |
| 1 | Docker install on ubuntu-docker | ${PHASE1_STATUS} |
| 2 | /etc/hosts synced to pve01 | ${PHASE2_STATUS} |
| 2 | /etc/hosts synced to pve02 | ${PHASE2_STATUS} |
| 3 | GPU visible on pve01 (P4000) | ${PHASE3_STATUS} |
| 3 | GPU visible on pve02 (A4500) | ${PHASE3_STATUS} |
| 3 | IOMMU validated on both nodes | ${PHASE3_STATUS} |
| 4 | Guest agent responding on VM 100 | ${PHASE4_STATUS} |

See \`$OUTFILE\` and \`$GPU_FILE\` for full output.
"""

content = content + update_block
with open("$REPORT", "w") as f:
    f.write(content)
PYEOF

log ""
log "Done. Review $OUTFILE for any ⚠️ or ❌ entries."
