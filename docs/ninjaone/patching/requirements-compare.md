# Requirements: Sanitize + Compare Reports (Patching / Vulnerabilities)

## Goal
Automate a repeatable pipeline that:
1) Takes raw exports (PDF/XLSX/CSV/TXT),
2) Produces sanitized copies safe for sharing,
3) Compares two datasets (ex: SCCM vs NinjaOne OR Month A vs Month B),
4) Outputs a single comparison document that summarizes patching success.

## Scope
### In-scope input types
- PDF exports (ex: "OS Patching-Has OS patching enabled-...")
- Excel exports (.xlsx) (ex: "Active vulnerabilities", "LS February")
- CSV exports
- Text exports (.txt)

### Out-of-scope
- OCR of scanned PDFs (unless explicitly enabled)
- Files requiring cloud login/API calls (this pipeline is offline by default)

## Folder Convention
Raw files must live here (not committed to git):
- `docs/ninjaone/patching/dashboard/samples/raw/`

Outputs:
- Sanitized files: `docs/ninjaone/patching/dashboard/samples/sanitized/`
- Comparison artifacts: `docs/ninjaone/patching/dashboard/samples/output/`

## Sanitization Requirements
The sanitizer MUST remove or mask:
- Usernames, emails, UPNs
- Hostnames, device names
- Domains, tenant names
- IP addresses, MAC addresses
- Serial numbers, asset tags, UUIDs
- File paths containing user/profile identifiers
- Any customer/company identifiers if present

Sanitization MUST:
- Preserve metrics and column structure where possible (especially for CSV/XLSX)
- Write sanitized output to `samples/sanitized/` with the same base filename + `.sanitized`

## Normalization Requirements
Before comparing, the pipeline MUST normalize inputs:
- PDF -> `.txt` using `pdftotext -layout` (preferred)
- XLSX -> `.csv` per sheet (or at least first sheet) using python/pandas
- CSV -> keep as CSV
- TXT -> keep as TXT

## Comparison Requirements
The comparator MUST support two modes:

### Mode A: Dataset-to-dataset (recommended)
Compare two inputs explicitly (ex: SCCM export vs NinjaOne export)

### Mode B: Most-recent pair in a folder
If two inputs are not specified, compare the two newest files matching a prefix.

Comparator outputs MUST include:
- Coverage: total rows, total unique devices (if detectable)
- Key metrics: compliance %, missing count, failed count (if detectable)
- Deltas: NinjaOne - SCCM (or New - Old) on compliance and counts
- Top deltas: worst/best devices (if device + compliance exist)
- Gaps: devices that appear in one dataset but not the other

Column detection SHOULD be heuristic:
- Device: name/hostname/computer/device
- Compliance: compliance/% compliant
- Missing: missing/required/needed
- Failed: failed/error

## Final Output: Comparison Document
A single markdown file:
- `docs/ninjaone/patching/dashboard/samples/output/patching_comparison.md`

Structure:
1) Executive Summary (3-6 bullets)
2) Inputs (file names, timestamps)
3) SCCM Summary (or Dataset A)
4) NinjaOne Summary (or Dataset B)
5) Delta Summary (table)
6) Notable outliers (top improvements/regressions)
7) Notes (assumptions + definition differences)

## Safety / Guardrails
- NEVER modify raw files in place
- NEVER commit raw files
- Sanitized outputs should be safe to paste into tickets/Teams
- If sanitization would destroy key metrics, log a warning and preserve metric fields

## Acceptance Criteria
- Running the pipeline produces sanitized outputs and a comparison doc with no obvious PII.
- Re-running is deterministic (same outputs from same inputs).
- Works in WSL Ubuntu with PowerShell 7 + Python 3.