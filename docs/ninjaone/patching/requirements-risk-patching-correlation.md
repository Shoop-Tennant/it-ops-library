# Requirements: Sanitize + Correlate (Patching vs Vulns vs Risk vs Inventory)

## Purpose
Create a repeatable offline workflow that:
1) Ingests raw exports from multiple tools (NinjaOne, Lansweeper, Arctic Wolf),
2) Sanitizes them (removes/masks sensitive identifiers),
3) Normalizes them into comparable tabular data,
4) Correlates endpoints across sources using a stable, sanitized endpoint key,
5) Produces a single report and CSV summary that show how patching posture aligns with vulnerability/risk posture.

This is specifically for cross-source correlation (not a simple “file diff”).

---

## Scope

### In-scope sources (initial)
- **NinjaOne Patching**: “OS patching enabled / patching status” export (PDF/CSV/XLSX)
- **NinjaOne Vulnerabilities**: “Active vulnerabilities” export (XLSX/CSV)
- **Lansweeper Inventory**: monthly export (XLSX/CSV)
- **Arctic Wolf Risks**: “Risks …” export (**CSV**)

### In-scope file types
- CSV, XLSX, TXT
- PDF supported as *fallback* (pdftotext), but structured CSV/XLSX is preferred.

### Out-of-scope (for now)
- OCR/scanned PDFs
- API calls / online lookups
- “Fixing” source data quality issues (we report gaps instead)

---

## Folder Layout (repo standard)

### Raw (NOT committed)
- `ninjaone/patching/dashboard/samples/raw/`

### Sanitized intermediate (NOT committed by default)
- `ninjaone/patching/dashboard/samples/sanitized/`

### Output (safe to share/commit)
- `ninjaone/patching/dashboard/samples/output/`

### Private correlation state (NOT committed)
- `ninjaone/patching/dashboard/samples/_private/`
  - `salt.txt`
  - `pseudonym_map.json` (optional)

---

## Primary Correlation Key (authoritative)

### Lansweeper
- Column: **`Asset name`**
- Example: `100N9S3`

### Arctic Wolf
- Column: **`Asset name`**
- Same format as Lansweeper.

### Canonical JoinKey Rules
1) Read `Asset name`
2) Normalize:
   - `JoinKey = UPPER(TRIM(AssetName))`
3) Pseudonymize deterministically:
   - `EndpointKey = ENDPOINT_####` derived from `JoinKey` + local `salt.txt`

### Join Confidence
- For LS + AW matches, set:
  - `JoinConfidence = ASSETNAME`

> IMPORTANT: Asset names are treated as sensitive identifiers and MUST NOT appear in any output artifacts.

---

## NinjaOne Mapping Rule (realistic constraint)
NinjaOne often uses **Device Name / Hostname / Display Name**, which may not equal `Asset name`.

Therefore the workflow MUST:
- Correlate **Lansweeper ↔ Arctic Wolf** with high confidence via Asset name.
- Attempt NinjaOne ↔ Asset name mapping using heuristics.
- If mapping cannot be confidently established, the output MUST show the record as an **unmatched coverage gap**, not silently drop it.

### Optional Crosswalk (recommended)
To make NinjaOne correlation deterministic when names differ, support an optional file:

- `ninjaone/patching/dashboard/samples/raw/endpoint_crosswalk.csv`

Format:
- `AssetName,NinjaDeviceName`
Example:
- `100N9S3,PC-100N9S3`
- `100N9S3,100N9S3`

If present, crosswalk MUST override heuristics.

---

## Sanitization Requirements (non-negotiable)

### Must remove/mask
- Hostnames / device names / FQDN
- Domains / tenant/company identifiers
- Emails/UPNs/usernames
- IP addresses, MAC addresses
- Serial numbers / UUIDs / asset tags
- File paths containing user/profile identifiers

### Must preserve (where possible)
- Severity, priority, numeric counts
- Column structure and row meaning
- Date/time stamps (unless they uniquely identify a person; generally OK)

### Stable Pseudonymization Requirement (critical)
Because correlation is the goal, sanitization MUST create stable pseudonyms:
- The same raw `JoinKey` MUST map to the same `EndpointKey` for the run.
- Use local salt stored in `_private/salt.txt`.
- Private mapping file MAY be written for troubleshooting:
  - `_private/pseudonym_map.json`
- Mapping file MUST NOT be written into `output/`.

---

## Normalization Requirements

### Convert to CSV whenever possible
- CSV: ingest directly
- XLSX: export to CSV (first sheet minimum; ideally each sheet separately)
- PDF: `pdftotext -layout` as fallback; attempt structured parse only if feasible

### Normalized dataset schema (minimum)
Each normalized, sanitized dataset MUST include:
- `EndpointKey` (pseudonym)
- `JoinConfidence` (`ASSETNAME`, `CROSSWALK`, `HEURISTIC`, etc.)
- `Source` (one of: `Lansweeper`, `ArcticWolf`, `NinjaPatching`, `NinjaVulns`)
- Source-specific metric columns (see below)

---

## Correlation Requirements

### Required metrics (high value)
1) Coverage:
   - Total unique endpoints across all sources
   - Unique endpoints per source
   - Match rates (AW↔LS, Ninja↔AssetName)
2) Patching posture (NinjaOne):
   - Count patching enabled/disabled (if available)
   - Compliance % summary (avg/median) if available
   - Missing/failed counts if available
3) Vulnerability posture (NinjaOne):
   - Severity breakdown: Critical/High/Medium/Low (counts)
4) Arctic Wolf posture:
   - Risk severity breakdown (counts)
   - Optional: top risk categories/titles (sanitized)
5) Inventory posture (Lansweeper):
   - Helpful metadata columns (OS, model) may be included, but sanitized if identifying

### Overlap Sets (the “so what”)
The report MUST include counts + a top list (sanitized) for:
- **High-risk endpoints**: (AW High/Critical) AND (Ninja Critical/High vulns OR patching disabled)
- **Patching disabled + risk present**
- **Critical/High vulns but missing from patching dataset**
- **High risks but missing from Lansweeper inventory** (inventory gap)

### Risk Score (simple, adjustable)
Compute a combined score per endpoint:
- +10 if patching disabled
- +5 per Critical vuln
- +3 per High vuln
- +1 per Medium vuln
- +5 per High Arctic Wolf risk
- +2 per Medium Arctic Wolf risk

Output top 25 endpoints by score (sanitized `EndpointKey` only).

---

## Output Artifacts (safe)

### 1) Markdown report
- `ninjaone/patching/dashboard/samples/output/risk_patching_correlation.md`

Required sections:
1) Executive Summary (bullets)
2) Inputs used (filenames + timestamps)
3) Coverage overview (table)
4) Lansweeper summary
5) Arctic Wolf summary
6) NinjaOne patching summary
7) NinjaOne vulnerability summary
8) Correlation findings (overlap sets)
9) Top risk endpoints (sanitized)
10) Notes & assumptions (definitions, mapping caveats, parsing limits)

### 2) CSV summary (per endpoint)
- `ninjaone/patching/dashboard/samples/output/risk_patching_correlation.csv`

Required columns (use blanks when not available):
- `EndpointKey`
- `JoinConfidence`
- `PatchingEnabled`
- `CompliancePct`
- `MissingCount`
- `FailedCount`
- `VulnCritical`
- `VulnHigh`
- `VulnMedium`
- `VulnLow`
- `AWRiskCritical` (if AW has Critical)
- `AWRiskHigh`
- `AWRiskMedium`
- `AWRiskLow`
- `RiskScore`

---

## Guardrails / Safety
- Never modify raw files in-place.
- Never write unsanitized identifiers into `output/`.
- Prefer structured comparison (CSV) over text diffs.
- If a source cannot be mapped to endpoints, report the gap explicitly.

---

## Acceptance Criteria
- Running the pipeline produces:
  - sanitized normalized datasets (non-PII)
  - correlation markdown report
  - correlation endpoint CSV summary
- Output contains match rates + overlap sets + top risk endpoints.
- No obvious PII appears in output artifacts.