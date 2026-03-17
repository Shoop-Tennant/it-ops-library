#!/usr/bin/env bash
# night-shutdown.sh — End-of-night health check, report, and git sync
#
# Usage:
#   ./night-shutdown.sh              # health check + git commit/push
#   ./night-shutdown.sh --shutdown   # also powers down VMs after checks
#
# What it does:
#   1. Runs cluster health check
#   2. Checks GPU status on both AI nodes (nvidia-smi)
#   3. Checks Ollama service on both AI nodes
#   4. Checks AnythingLLM + LiteLLM containers
#   5. Generates nightly report (logs/nightly/YYYY-MM-DD.md)
#   6. Git add/commit/push
#   7. Prints summary with tomorrow's recommended tasks
#
# Prerequisites:
#   eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
NIGHTLY_DIR="${SCRIPT_DIR}/logs/nightly"
DATE=$(date +%Y-%m-%d)
REPORT="${NIGHTLY_DIR}/${DATE}.md"
SSH_OPTS="-o ConnectTimeout=8 -o BatchMode=yes -o StrictHostKeyChecking=no"

SHUTDOWN=false
for arg in "$@"; do
    [[ "$arg" == "--shutdown" ]] && SHUTDOWN=true
done

mkdir -p "$NIGHTLY_DIR"

# Colors
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

# Status tracking
declare -A STATUS

ok()   { echo -e "${GREEN}  ✅ $*${NC}"; }
fail() { echo -e "${RED}  ❌ $*${NC}"; }
warn() { echo -e "${YELLOW}  ⚠️  $*${NC}"; }
hdr()  { echo -e "\n${BOLD}${CYAN}$*${NC}"; }

check_ssh() {
    local host=$1 label=$2
    if ssh $SSH_OPTS "$host" 'hostname' &>/dev/null; then
        STATUS[$label]="UP"
        return 0
    else
        STATUS[$label]="DOWN"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   Shoop-Homelab — Nightly Shutdown       ║${NC}"
echo -e "${BOLD}║   $(date '+%Y-%m-%d %H:%M:%S')                      ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# 1. Cluster health check
# ─────────────────────────────────────────────────────────────────────────────
hdr "1. Cluster Health Check"
if [[ -x "${SCRIPT_DIR}/cluster-health.sh" ]]; then
    "${SCRIPT_DIR}/cluster-health.sh" --quiet 2>/dev/null
    if [[ $? -eq 0 ]]; then
        ok "Cluster health: all checks passed"
        STATUS[cluster]="HEALTHY"
    else
        warn "Cluster health: some checks failed (see cluster-health log)"
        STATUS[cluster]="DEGRADED"
    fi
else
    warn "cluster-health.sh not found or not executable"
    STATUS[cluster]="SKIPPED"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2. Proxmox node connectivity
# ─────────────────────────────────────────────────────────────────────────────
hdr "2. Proxmox Nodes"
check_ssh pve01 pve01 && ok "pve01 (192.168.4.10): reachable" || fail "pve01 (192.168.4.10): unreachable"
check_ssh pve02 pve02 && ok "pve02 (192.168.4.11): reachable" || fail "pve02 (192.168.4.11): unreachable"

# ─────────────────────────────────────────────────────────────────────────────
# 3. GPU checks (nvidia-smi inside VMs)
# ─────────────────────────────────────────────────────────────────────────────
hdr "3. GPU Status"

# A4500 on ai-node-a4500 (192.168.4.15, via pve02)
if [[ "${STATUS[pve02]}" == "UP" ]]; then
    A4500_SMI=$(ssh $SSH_OPTS -J root@192.168.4.11 ubuntu@192.168.4.15 \
        "nvidia-smi --query-gpu=name,memory.total,memory.used,temperature.gpu --format=csv,noheader" 2>/dev/null || echo "")
    if [[ -n "$A4500_SMI" ]]; then
        ok "A4500 (pve02): $A4500_SMI"
        STATUS[gpu_a4500]="OK"
    else
        fail "A4500 (pve02): nvidia-smi failed or VM unreachable"
        STATUS[gpu_a4500]="FAIL"
    fi
else
    fail "A4500: skipped (pve02 unreachable)"
    STATUS[gpu_a4500]="SKIP"
fi

# P4000 on ai-node-p4000 (192.168.4.16, via pve01)
if [[ "${STATUS[pve01]}" == "UP" ]]; then
    P4000_SMI=$(ssh $SSH_OPTS -J root@192.168.4.10 ubuntu@192.168.4.16 \
        "nvidia-smi --query-gpu=name,memory.total,memory.used,temperature.gpu --format=csv,noheader" 2>/dev/null || echo "")
    if [[ -n "$P4000_SMI" ]]; then
        ok "P4000 (pve01): $P4000_SMI"
        STATUS[gpu_p4000]="OK"
    else
        fail "P4000 (pve01): nvidia-smi failed or VM unreachable"
        STATUS[gpu_p4000]="FAIL"
    fi
else
    fail "P4000: skipped (pve01 unreachable)"
    STATUS[gpu_p4000]="SKIP"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4. Ollama status
# ─────────────────────────────────────────────────────────────────────────────
hdr "4. Ollama Services"

# A4500 Ollama
OLLAMA_A4500=$(curl -s --max-time 5 http://192.168.4.15:11434/api/tags 2>/dev/null || echo "")
if echo "$OLLAMA_A4500" | python3 -c "import sys,json; json.load(sys.stdin)" &>/dev/null; then
    MODELS_A4500=$(echo "$OLLAMA_A4500" | python3 -c "import sys,json; print(', '.join(m['name'] for m in json.load(sys.stdin)['models']))" 2>/dev/null)
    ok "Ollama A4500 (192.168.4.15:11434): $MODELS_A4500"
    STATUS[ollama_a4500]="OK"
else
    fail "Ollama A4500 (192.168.4.15:11434): not responding"
    STATUS[ollama_a4500]="FAIL"
fi

# P4000 Ollama
OLLAMA_P4000=$(curl -s --max-time 5 http://192.168.4.16:11434/api/tags 2>/dev/null || echo "")
if echo "$OLLAMA_P4000" | python3 -c "import sys,json; json.load(sys.stdin)" &>/dev/null; then
    MODELS_P4000=$(echo "$OLLAMA_P4000" | python3 -c "import sys,json; print(', '.join(m['name'] for m in json.load(sys.stdin)['models']))" 2>/dev/null)
    ok "Ollama P4000 (192.168.4.16:11434): $MODELS_P4000"
    STATUS[ollama_p4000]="OK"
else
    fail "Ollama P4000 (192.168.4.16:11434): not responding"
    STATUS[ollama_p4000]="FAIL"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 5. Container status (AnythingLLM + LiteLLM)
# ─────────────────────────────────────────────────────────────────────────────
hdr "5. Docker Containers (ubuntu-docker)"

if [[ "${STATUS[pve02]}" == "UP" ]]; then
    CONTAINERS=$(ssh $SSH_OPTS -J root@192.168.4.11 ubuntu@192.168.4.20 \
        "docker ps --format '{{.Names}}|{{.Status}}'" 2>/dev/null || echo "")

    # AnythingLLM
    ALLM_STATUS=$(echo "$CONTAINERS" | grep "anythingllm" | cut -d'|' -f2)
    if echo "$ALLM_STATUS" | grep -qi "up"; then
        ok "AnythingLLM: $ALLM_STATUS"
        STATUS[anythingllm]="OK"
    else
        fail "AnythingLLM: ${ALLM_STATUS:-not running}"
        STATUS[anythingllm]="FAIL"
    fi

    # LiteLLM
    LITE_STATUS=$(echo "$CONTAINERS" | grep "litellm" | cut -d'|' -f2)
    if echo "$LITE_STATUS" | grep -qi "up"; then
        ok "LiteLLM: $LITE_STATUS"
        STATUS[litellm]="OK"
    else
        fail "LiteLLM: ${LITE_STATUS:-not running}"
        STATUS[litellm]="FAIL"
    fi
else
    fail "Containers: skipped (pve02 unreachable)"
    STATUS[anythingllm]="SKIP"
    STATUS[litellm]="SKIP"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 6. Generate nightly report
# ─────────────────────────────────────────────────────────────────────────────
hdr "6. Generating Report"

s() { local k=$1; echo "${STATUS[$k]:-UNKNOWN}"; }
icon() { local v=$1; [[ "$v" == "OK" || "$v" == "UP" || "$v" == "HEALTHY" ]] && echo "pass" || echo "FAIL"; }

cat > "$REPORT" <<EOF
# Nightly Report — ${DATE}
**Generated:** $(date '+%Y-%m-%d %H:%M:%S')

## Service Status

| Service | Status | Details |
|:--------|:-------|:--------|
| Cluster | $(s cluster) | pve01=$(s pve01), pve02=$(s pve02) |
| GPU A4500 | $(s gpu_a4500) | ${A4500_SMI:-N/A} |
| GPU P4000 | $(s gpu_p4000) | ${P4000_SMI:-N/A} |
| Ollama A4500 | $(s ollama_a4500) | ${MODELS_A4500:-N/A} |
| Ollama P4000 | $(s ollama_p4000) | ${MODELS_P4000:-N/A} |
| AnythingLLM | $(s anythingllm) | http://192.168.4.20:3001 |
| LiteLLM | $(s litellm) | http://192.168.4.20:4000 |

## Architecture

\`\`\`
Browser/API Client
    |
    +---> AnythingLLM (192.168.4.20:3001) ---> Ollama A4500 (192.168.4.15:11434)
    |                                            RTX A4500 16GB, qwen2.5:14b
    +---> LiteLLM    (192.168.4.20:4000)
              |
              +--- gpt-3.5-turbo ---> Ollama P4000 (192.168.4.16:11434)
              |                        Quadro P4000 8GB, qwen2.5:7b
              +--- gpt-4        ---> Ollama A4500 (192.168.4.15:11434)
                                      RTX A4500 16GB, qwen2.5:14b
\`\`\`

## Git
$(cd "$REPO_DIR" && git log --oneline -1 2>/dev/null || echo "no commits")

## Recommended Next Tasks
- Investigate pve03/pve04 (offline since last session)
- Clean up corosync.conf stale ring0 IPs
- Load test with larger models (qwen2.5:32b if VRAM allows)
- Set up Ollama model auto-pull on boot
- Configure AnythingLLM workspaces for IT KB ingestion
EOF

ok "Report: ${REPORT}"

# ─────────────────────────────────────────────────────────────────────────────
# 7. Git operations
# ─────────────────────────────────────────────────────────────────────────────
hdr "7. Git Sync"

cd "$REPO_DIR" || { fail "Cannot cd to $REPO_DIR"; exit 1; }

CHANGES=$(git status --porcelain 2>/dev/null | wc -l)
if [[ "$CHANGES" -eq 0 ]]; then
    ok "Working tree clean — nothing to commit"
    STATUS[git]="CLEAN"
else
    echo -e "  ${CHANGES} file(s) to stage"
    git add -A 2>/dev/null
    COMMIT_MSG="nightly: $(date '+%Y-%m-%d %H:%M') — $(s cluster) cluster, $(s gpu_a4500) A4500, $(s gpu_p4000) P4000"
    git commit -m "$COMMIT_MSG" --quiet 2>/dev/null
    if [[ $? -eq 0 ]]; then
        COMMIT_HASH=$(git rev-parse --short HEAD)
        ok "Committed: ${COMMIT_HASH} — ${COMMIT_MSG}"

        git push --quiet 2>/dev/null
        if [[ $? -eq 0 ]]; then
            ok "Pushed to origin/main"
            STATUS[git]="PUSHED"
        else
            warn "Push failed — run 'git push' manually"
            STATUS[git]="COMMIT_ONLY"
        fi
    else
        warn "Nothing to commit (changes may be gitignored)"
        STATUS[git]="CLEAN"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# 8. Optional VM shutdown
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$SHUTDOWN" == true ]]; then
    hdr "8. Shutting Down VMs"

    if [[ "${STATUS[pve02]}" == "UP" ]]; then
        echo -e "  Stopping ai-node-a4500 (102)..."
        ssh $SSH_OPTS pve02 "qm shutdown 102 --timeout 60" 2>/dev/null && ok "ai-node-a4500: stopped" || warn "ai-node-a4500: shutdown failed"

        echo -e "  Stopping ubuntu-docker (100)..."
        ssh $SSH_OPTS pve02 "qm shutdown 100 --timeout 60" 2>/dev/null && ok "ubuntu-docker: stopped" || warn "ubuntu-docker: shutdown failed"
    fi

    if [[ "${STATUS[pve01]}" == "UP" ]]; then
        echo -e "  Stopping ai-node-p4000 (103)..."
        ssh $SSH_OPTS pve01 "qm shutdown 103 --timeout 60" 2>/dev/null && ok "ai-node-p4000: stopped" || warn "ai-node-p4000: shutdown failed"
    fi

    ok "All VMs shutdown complete"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║            NIGHTLY SUMMARY               ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""

for key in cluster pve01 pve02 gpu_a4500 gpu_p4000 ollama_a4500 ollama_p4000 anythingllm litellm git; do
    val="${STATUS[$key]:-UNKNOWN}"
    case "$val" in
        OK|UP|HEALTHY|PUSHED|CLEAN) echo -e "  ${GREEN}✅${NC} ${key}: ${val}" ;;
        DEGRADED|COMMIT_ONLY)       echo -e "  ${YELLOW}⚠️${NC}  ${key}: ${val}" ;;
        *)                          echo -e "  ${RED}❌${NC} ${key}: ${val}" ;;
    esac
done

echo ""
echo -e "  ${CYAN}Report:${NC} ${REPORT}"
[[ -n "${COMMIT_HASH:-}" ]] && echo -e "  ${CYAN}Commit:${NC} ${COMMIT_HASH}"
echo ""

if [[ "$SHUTDOWN" == true ]]; then
    echo -e "  ${BOLD}VMs are shut down. To start tomorrow:${NC}"
    echo -e "    ssh pve01 'pvecm expected 1 && qm start 103'"
    echo -e "    ssh pve02 'pvecm expected 1 && qm start 100 && qm start 102'"
fi

echo -e "  ${BOLD}Tomorrow's tasks:${NC}"
echo -e "    - Investigate pve03/pve04 offline nodes"
echo -e "    - Clean corosync.conf stale IPs"
echo -e "    - Configure AnythingLLM workspaces"
echo ""
