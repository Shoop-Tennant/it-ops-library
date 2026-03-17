#!/usr/bin/env bash
# setup-ssh-keys.sh
# Distributes the WSL workstation public key to all Proxmox cluster nodes.
# Safe to re-run — idempotent, no duplicate entries written.
#
# Prerequisites:
#   - SSH agent loaded with a key that is already authorized on each node
#     (e.g. the Proxmox cluster key, or run from a node's own shell)
#   - ~/.ssh/id_ed25519_homelab.pub exists on this workstation
#
# Usage:
#   ./setup-ssh-keys.sh
#   ./setup-ssh-keys.sh --dry-run

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────

declare -A NODES=(
  [pve01]=192.168.4.10
  [pve02]=192.168.4.11
  [pve03]=192.168.4.12
  [pve04]=192.168.4.13
)

PUBKEY_FILE="${HOME}/.ssh/id_ed25519_homelab.pub"
DRY_RUN=false

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o PasswordAuthentication=no
  -o ConnectTimeout=10
  -o BatchMode=yes
)

# ── Colour helpers ────────────────────────────────────────────────────────────

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ── Arg parse ─────────────────────────────────────────────────────────────────

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

# ── Preflight ─────────────────────────────────────────────────────────────────

if [[ ! -f "$PUBKEY_FILE" ]]; then
  echo -e "${RED}ERROR:${NC} Public key not found: $PUBKEY_FILE"
  exit 1
fi

PUBKEY=$(cat "$PUBKEY_FILE")
if [[ -z "$PUBKEY" ]]; then
  echo -e "${RED}ERROR:${NC} Public key file is empty: $PUBKEY_FILE"
  exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Proxmox SSH Key Distribution"
echo "  Key: $PUBKEY_FILE"
echo "  Key fingerprint: $(ssh-keygen -lf "$PUBKEY_FILE" 2>/dev/null | awk '{print $2}')"
echo "  Dry run: $DRY_RUN"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# ── Per-node results (for summary table) ──────────────────────────────────────

declare -A RESULTS

# ── Process each node ─────────────────────────────────────────────────────────

for NODE in $(echo "${!NODES[@]}" | tr ' ' '\n' | sort); do
  IP="${NODES[$NODE]}"
  echo -n "  $NODE ($IP) ... "

  # Test connectivity first
  if ! ssh "${SSH_OPTS[@]}" "root@${IP}" 'exit 0' 2>/dev/null; then
    echo -e "${RED}✗ unreachable${NC}"
    RESULTS[$NODE]="UNREACHABLE"
    continue
  fi

  # Check if key is already present
  ALREADY_PRESENT=$(ssh "${SSH_OPTS[@]}" "root@${IP}" \
    "grep -qF '${PUBKEY}' /root/.ssh/authorized_keys 2>/dev/null && echo yes || echo no")

  if [[ "$ALREADY_PRESENT" == "yes" ]]; then
    echo -e "${YELLOW}⚠️  $NODE — already present, skipped${NC}"
    RESULTS[$NODE]="ALREADY_PRESENT"
    continue
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${GREEN}✅ $NODE — would install (dry run)${NC}"
    RESULTS[$NODE]="DRY_RUN"
    continue
  fi

  # Install key
  ssh "${SSH_OPTS[@]}" "root@${IP}" bash <<EOF
set -euo pipefail
mkdir -p /root/.ssh
chmod 700 /root/.ssh
echo '${PUBKEY}' >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
EOF

  echo -e "${GREEN}✅ $NODE — key installed${NC}"
  RESULTS[$NODE]="INSTALLED"
done

# ── Summary table ─────────────────────────────────────────────────────────────

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  %-8s  %-16s  %s\n" "NODE" "IP" "RESULT"
printf "  %-8s  %-16s  %s\n" "--------" "----------------" "------"

PASS=0; SKIP=0; FAIL=0

for NODE in $(echo "${!NODES[@]}" | tr ' ' '\n' | sort); do
  IP="${NODES[$NODE]}"
  STATUS="${RESULTS[$NODE]:-UNKNOWN}"

  case "$STATUS" in
    INSTALLED)      ICON="✅"; LABEL="installed";       ((PASS++)) ;;
    ALREADY_PRESENT) ICON="⚠️ "; LABEL="already present"; ((SKIP++)) ;;
    DRY_RUN)        ICON="🔍"; LABEL="dry run (skipped)"; ((SKIP++)) ;;
    UNREACHABLE)    ICON="❌"; LABEL="unreachable";      ((FAIL++)) ;;
    *)              ICON="❓"; LABEL="unknown";           ((FAIL++)) ;;
  esac

  printf "  %-8s  %-16s  %s %s\n" "$NODE" "$IP" "$ICON" "$LABEL"
done

echo
printf "  Installed: %d  |  Skipped: %d  |  Failed: %d\n" "$PASS" "$SKIP" "$FAIL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "$FAIL" -gt 0 ]]; then
  echo
  echo -e "${YELLOW}One or more nodes were unreachable.${NC}"
  echo "  To authorize manually, paste this into each node's Proxmox web shell:"
  echo
  echo "    mkdir -p /root/.ssh && chmod 700 /root/.ssh"
  echo "    echo '${PUBKEY}' >> /root/.ssh/authorized_keys"
  echo "    chmod 600 /root/.ssh/authorized_keys"
  echo
  exit 1
fi

exit 0
