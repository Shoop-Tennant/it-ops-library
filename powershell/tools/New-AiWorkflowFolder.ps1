function New-AiWorkflowFolder {
    [CmdletBinding()]
    param(
        # Example: itsm-helix-doc-review
        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z0-9]+(-[a-z0-9]+)*$')]
        [string] $Name,

        # Default root for local-only workflows
        [string] $Root = "$env:USERPROFILE\AiLocal\workflows",

        # Create a README.md from template
        [switch] $Readme,

        # Open the folder after creation
        [switch] $Open
    )

    $wfPath = Join-Path $Root $Name

    # Create structure
    $folders = @(
        $wfPath,
        (Join-Path $wfPath 'inputs-raw'),
        (Join-Path $wfPath 'outputs-sanitized'),
        (Join-Path $wfPath 'outputs-final'),
        (Join-Path $wfPath 'notes')
    )

    foreach ($f in $folders) {
        New-Item -ItemType Directory -Path $f -Force | Out-Null
    }

    # Optional README
    if ($Readme) {
        $readmePath = Join-Path $wfPath 'README.md'
        if (-not (Test-Path $readmePath)) {
            $today = (Get-Date).ToString('yyyy-MM-dd')
@"
# Workflow: $Name

## Purpose
Briefly describe what this workflow does and what “done” looks like.

## Inputs / Outputs
**Inputs (raw, sensitive):**
- `inputs-raw/`  
  - Never commit to git.
  - Treat as confidential (may contain URLs, emails, tokens, internal names).

**Outputs (sanitized working set):**
- `outputs-sanitized/`  
  - Redacted versions used for AI tools (Cowork/Copilot/etc.).
  - Replace secrets with placeholders: `<REDACTED:EMAIL>`, `<REDACTED:URL>`, `<REDACTED:HOST>`, `<REDACTED:TOKEN>`, etc.

**Final outputs (shareable):**
- `outputs-final/`  
  - Only sanitized, manager-ready deliverables.
  - Safe to copy to SharePoint/Drive for sharing.

**Notes / scratch:**
- `notes/`  
  - Decisions, assumptions, run logs, next steps.

## Guardrails
- Do **not** store tokens/secrets in any output.
- Do **not** paste raw internal links into final deliverables.
- Prefer “one source of truth”: final content lives in `outputs-final/`.

## Runbook (How to use)
1) Copy source files into `inputs-raw/`
2) Sanitize into `outputs-sanitized/`
3) Run AI review/generation using `outputs-sanitized/`
4) Place final deliverables into `outputs-final/`
5) Copy final deliverables to share location (if needed)

## Status
- Owner: Jeremy
- Created: $today
- Last updated: $today
"@ | Out-File -FilePath $readmePath -Encoding utf8
        }
    }

    Write-Host "Created workflow folder: $wfPath"

    if ($Open) {
        Invoke-Item $wfPath
    }

    # Return the path for piping/automation
    return $wfPath
}