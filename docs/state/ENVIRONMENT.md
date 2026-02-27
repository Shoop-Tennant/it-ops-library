# Environment (Source of Truth)

## Dev Host
- OS: Windows 11 (primary)
- Repo path (Windows): `C:\Users\jsp6\git\it-ops-library`
- Editor: VS Code (Windows-native)
- Shell: PowerShell 7 (`pwsh`) preferred; PowerShell 5.1 (`powershell.exe`) available
- AI tooling: Claude Code, Codex CLI, Gemini CLI (all Windows, via npm)
- WSL2 (Ubuntu): available but not primary — VPN can disrupt WSL2 networking

## Backup
- Target: TrueNAS share mapped as Z: in Windows
- Backup folder: `Z:\Claude\Work_Backups`
- Method: Robocopy (from Windows)

## Git
- Branch: main
- Remote: origin (GitHub, user: Shoop-Tennant)
- Commit/push from: Windows (primary)
