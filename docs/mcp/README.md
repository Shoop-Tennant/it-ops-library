# MCP Guide

## Why MCP Matters Here
MCP provides a consistent tools interface for safely generating, reviewing, and refining IT Ops scripts and prompt cards. It reduces copy/paste errors and keeps runs auditable.

## Local-First Approach
Use local tools first; add a gateway later if needed. The priority is repeatable, safe execution on endpoints without unnecessary network dependencies.

## Roles
- Claude Code: drafting, polishing, and review.
- Codex CLI: multi-file edits, refactors, and test loops.

## Permissions Posture
- Read-only for recon and discovery.
- Workspace-write for doc/script updates.
- On-request approvals for commands and sensitive actions.

## Secrets
- Never store secrets in the repo.
- Use a secrets manager (organization standard) for tokens and credentials.
