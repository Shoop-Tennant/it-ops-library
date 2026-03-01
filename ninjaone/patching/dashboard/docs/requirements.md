# Patch Operations Dashboard (NinjaOne) – OS + 3rd Party

## Environment
- Runner device has custom fields:
  - ninjaoneClientId (text)
  - ninjaoneClientSecret (secure)
  - ninjaoneInstance (text) = us2.ninjarmm.com

## Goal
Generate monthly reporting covering:
- OS patching status/outcomes
- 3rd-party software patching status/outcomes
Publish as NinjaOne KB articles under: Knowledge Base > Monthly Reports
- Patch Operations Dashboard - All Organizations - [Month Year]
- Patch Operations Dashboard - [Organization Name] - [Month Year]

## Auth
- Use NinjaOne OAuth Authorization Code flow.
- Redirect URI: http://localhost:8400/callback (or match what’s configured in the app).
- First run: interactive auth in browser to capture code.
- Subsequent runs: use refresh token / stored tokens.
- Never log client secret or tokens. Store tokens securely.

## Output content
- Executive summary KPIs (scanned/missing/installed/failed; OS vs software)
- Top offenders (devices with most missing/failed)
- OS patching section
- Software patching section (allowlisted titles)
- Notes/caveats (offline devices, scan aborted, etc.)

## Deliverables
- ninjaone/patching/dashboard/src/PatchOperationsDashboard.ps1 (PowerShell 7+)
- ninjaone/patching/dashboard/README.md (setup + run + scheduling)
- Support -WhatIf to write markdown locally instead of creating KB articles.
