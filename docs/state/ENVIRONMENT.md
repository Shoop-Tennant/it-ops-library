# Environment (Source of Truth)

## Dev Host
- OS: Windows 11 + WSL2 (Ubuntu)
- Repo path (Windows): C:\Workspace\Repos\it-ops-library
- Repo path (WSL): ~/git/it-ops-library
- Editor: VS Code (WSL extension)
- AI: Claude Code in VS Code

## Workspace Layout
- C:\Workspace\Docs\   → Junction → C:\Users\jerem\My Drive\Workspace\Docs (Google Drive)
- C:\Workspace\Inbox\  → Junction → C:\Users\jerem\My Drive\Workspace\Inbox (Google Drive)
- C:\Workspace\Repos\  — local git repos (backed up via GitHub)
- C:\Workspace\Tools\  — launchers + scripts (local only; back up via NAS script)
- C:\Workspace\Scratch\ — ephemeral work (local only)
- C:\Workspace\Secrets\ — local only; never committed

## Launchers
- Location: C:\Workspace\Tools\bin\
- On user PATH: yes (set via [Environment]::SetEnvironmentVariable 'User')
- Available: ws.cmd, ws-claude.cmd, ws-code.cmd, ws-backup.cmd,
             ws-open.cmd, ws-root.cmd, ws-codex.cmd, ws-gemini.cmd

## Backup
- Script: C:\Workspace\Tools\Backup-WorkspaceToNAS.ps1
- Run via: ws-backup.cmd
- Target: \\TRUENAS\jeremy\backups\Workspace
- Covers: Docs, Inbox, Tools, Scratch (Robocopy /MIR)
- Does NOT cover: Repos (use GitHub), Secrets

## Git
- Branch: main
- Remote: origin (GitHub, user: Shoop-Tennant)
