# Runbook: Sanitize + Correlate Risk vs Patching (LS + Arctic Wolf + NinjaOne)

## What this does
Takes raw exports from:
- Lansweeper (inventory)
- Arctic Wolf (risks)
- NinjaOne (patching + vulnerabilities)

Then:
- Sanitizes identifiers (safe to share)
- Correlates endpoints across sources
- Produces a single markdown report + a per-endpoint CSV

---

## One-time Setup

### 1) Create folders
From repo root (WSL):
```bash
mkdir -p ninjaone/patching/dashboard/samples/{raw,sanitized,output,_private}