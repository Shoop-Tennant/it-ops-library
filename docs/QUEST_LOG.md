# Quest Log — it-ops-library

## Current Main Quest
Build an IT Ops library repo with: prompts + scripts + runbooks + sanitization pack.

---

## Quests

- [x] Quest 1: Sanitization Pack v1 (tool + samples + Pester tests) — done
- [ ] Quest 2: Backup automation — extend Backup-WorkspaceToNAS.ps1 to cover Tools\ and Scratch\
- [x] Quest 3: Repo standards (editorconfig, gitattributes, folder conventions, ADR 0001) — done

---

## Open Branches

### feature/ninjaone-patching
- **Status:** Blocked — do not merge yet
- **Value:** NinjaOne patching dashboard (3 large PS1 scripts), agent prompts, AGENTS.md
- **Blocker:** 4 sample files in `ninjaone/patching/dashboard/samples/` contain real device
  names and internal site names (Falkenberg, Tennant Internal). Must be replaced with
  synthetic equivalents before this can merge to main.
- **Also:** committed PDF should move to Drive; CLAUDE.md / ENVIRONMENT.md / .gitignore
  all diverged from main and need conflict resolution.
- **Next action:** Sanitize samples, remove PDF, resolve conflicts, open PR.

### quest/agent-assisted
- **Status:** Ready to prep — structural fix needed
- **Value:** 5 generated PS1 scripts (Teams, Diagnostics, Printer, Outlook, WU reset),
  code-signing guide + helper, AGENTS.md, updated prompt cards and README.
- **Blocker:** Scripts committed under old `PowerShell/` (uppercase) path — conflicts
  with Phase 1 rename to `powershell/` (lowercase). Case matters on WSL/Linux.
- **Next action:** Rename PowerShell/ → powershell/ on the branch, then open PR.

---

## Session Notes

### 2026-03-01
- Did: Phases 1–4 repo hygiene (rename, editorconfig, gitattributes, gitignore,
  README, Pester tests, ADR 0001). Gitignored .claude/. Verified and documented
  workspace layout + launchers in ENVIRONMENT.md. Triaged 3 remote branches.
- Result: main is clean. sidequest-agent-factory deleted (was empty). Two branches
  kept open with documented blockers above.
- Next: Quest 2 (extend backup script) or prep quest/agent-assisted for merge.
