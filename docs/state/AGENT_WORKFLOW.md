# Agent Workflow (Option C)

## Overview
Option C is a repeatable “agent-assisted” loop: recon, write, review, then commit with explicit checks.

## Recon Prompt
- Map repo structure and identify target files.
- Confirm constraints (no network, safe defaults).
- List missing dependencies or gaps.

## Write Prompt
- Make scoped edits only.
- Keep changes minimal and reversible.
- Use templates where available.

## Review Prompt
- Re-read diffs for correctness and safety.
- Confirm required params, logging, and `-WhatIf` behavior.
- Ensure prompt cards match real script paths and parameters.

## Commit Checklist
- [ ] `git status` is clean except intended files
- [ ] Tests or `-WhatIf` runs completed (if applicable)
- [ ] Docs updated when behavior changes
- [ ] No secrets or internal identifiers
- [ ] Commit message is short and specific

## Redaction Rules
- No personal emails.
- No tokens, secrets, or tenant IDs.
- Avoid sensitive asset tags if they reveal internal inventory.
