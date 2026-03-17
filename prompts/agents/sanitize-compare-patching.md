# Agent: Sanitize + Compare Patching Reports

## Objective
Sanitize raw report exports and generate a patching success comparison document.

## Inputs
Raw files are located in:
- docs/ninjaone/patching/dashboard/samples/raw/

## Output Targets
1) Sanitized files written to:
- docs/ninjaone/patching/dashboard/samples/sanitized/

2) Comparison document written to:
- docs/ninjaone/patching/dashboard/samples/output/patching_comparison.md

## Constraints / Guardrails
- Do not commit raw files.
- Do not modify raw files in place.
- Remove/mask PII (emails, UPNs, hostnames, domains, IP/MAC, serials, asset tags).
- Prefer structured comparisons (CSV) over text diffs when possible.

## Required Steps
1) Create folders if missing:
   - samples/raw, samples/sanitized, samples/output

2) Normalize:
   - PDF -> TXT via `pdftotext -layout`
   - XLSX -> CSV (first sheet minimum; ideally each sheet) via python/pandas
   - CSV/TXT pass through

3) Sanitize:
   - Use existing repo tool: `PowerShell/Tools/Sanitize-File.ps1` for TXT/CSV
   - If XLSX converted to CSV, sanitize the CSV outputs
   - Ensure masked identifiers are consistent (ex: DEVICE_001) so comparisons still work

4) Compare:
   - If exactly 2 comparable datasets exist, compare them
   - If more exist, compare most recent NinjaOne vs most recent SCCM (by filename hints), otherwise compare two newest
   - Produce summary metrics + deltas + outliers

5) Generate `patching_comparison.md` using the required structure from requirements doc.

## Definition Hints
- SCCM files often include compliance/missing/failed by device or collection.
- NinjaOne exports may include "OS patching enabled" or patching status fields.
- Use heuristic column detection if exact column names differ.

## Done When
- Sanitized outputs exist with no obvious PII.
- patching_comparison.md exists and includes executive summary + delta section.