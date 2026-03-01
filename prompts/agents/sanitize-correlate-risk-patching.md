# Agent: Sanitize + Correlate (Risk vs Patching) — LS + Arctic Wolf + NinjaOne

## Objective
Sanitize multiple exports and generate a correlation report that aligns:
- Lansweeper inventory posture
- Arctic Wolf risk posture
- NinjaOne patching posture
- NinjaOne vulnerability posture

Primary goal is cross-source correlation (not a plain diff).

---

## Inputs

### Required input folder
- `ninjaone/patching/dashboard/samples/raw/`

### Preferred pairing mechanism
- Use manifest: `ninjaone/patching/dashboard/samples/raw/manifest.yml`

### Optional crosswalk
- `ninjaone/patching/dashboard/samples/raw/endpoint_crosswalk.csv`
  - Columns: `AssetName,NinjaDeviceName`
  - If present, it overrides heuristics for NinjaOne matching.

---

## Outputs

### Sanitized intermediates (do not commit by default)
- `ninjaone/patching/dashboard/samples/sanitized/`

### Final safe artifacts
- `ninjaone/patching/dashboard/samples/output/risk_patching_correlation.md`
- `ninjaone/patching/dashboard/samples/output/risk_patching_correlation.csv`

### Private correlation state (never commit)
- `ninjaone/patching/dashboard/samples/_private/salt.txt`
- `ninjaone/patching/dashboard/samples/_private/pseudonym_map.json` (optional)

---

## Constraints / Guardrails
- Do not modify raw files in place.
- Do not emit unsanitized identifiers in output artifacts.
- Stable pseudonymization is required to preserve correlation.
- Treat `Asset name` as sensitive; do not output it.

---

## Source Rules (authoritative)
### Lansweeper
- Endpoint column is: `Asset name`
- JoinKey = UPPER(TRIM(Asset name))

### Arctic Wolf
- Endpoint column is: `Asset name` (same format as LS)
- JoinKey = UPPER(TRIM(Asset name))

### Correlation Key
- Primary JoinKey for AW↔LS is AssetName (normalized).
- Pseudonymize JoinKey → `EndpointKey` using local salt from `_private/salt.txt`
- Set `JoinConfidence = ASSETNAME` for these matches.

### NinjaOne correlation
- If crosswalk exists:
  - Map Ninja device name → AssetName deterministically
  - Set `JoinConfidence = CROSSWALK`
- Else heuristic:
  - Try to match Ninja device identifiers to AssetName by string equivalence after normalization
  - If no match, report as coverage gap (do not drop silently)
  - Set `JoinConfidence = HEURISTIC` where applicable

---

## Required Steps

### 1) Ensure folders exist
Create if missing:
- `samples/raw`
- `samples/sanitized`
- `samples/output`
- `samples/_private`

### 2) Load manifest and select files
Use `manifest.yml` if present; otherwise choose the most recent likely files per source.

Expected sources:
- Lansweeper monthly export (XLSX/CSV)
- Arctic Wolf risks export (CSV)
- NinjaOne patching export (PDF/CSV/XLSX)
- NinjaOne vulnerabilities export (XLSX/CSV)

### 3) Normalize inputs to CSV
- CSV: ingest directly
- XLSX: export to CSV (first sheet minimum; ideally each sheet)
- PDF: convert to text via `pdftotext -layout` (best-effort parse; document limitations)

### 4) Create stable pseudonyms (EndpointKey)
- Ensure `_private/salt.txt` exists; create it if missing.
- For LS + AW:
  - Read `Asset name`
  - Normalize: UPPER(TRIM)
  - Use this as JoinKey
- Convert JoinKey to deterministic `EndpointKey`:
  - Store any internal mapping only in `_private/pseudonym_map.json` (optional)
- NEVER output raw JoinKey or AssetName outside `_private/`.

### 5) Sanitize PII from all other fields
Mask or remove:
- emails/UPNs/usernames
- hostnames/device names/FQDN
- domains/tenant/company identifiers
- IP/MAC
- serials/UUIDs/asset tags
- user paths

Preserve:
- severity values
- counts
- dates (unless uniquely identifying)

### 6) Extract/standardize metrics by source
Create per-source standardized fields (where possible):

#### Lansweeper
- `EndpointKey`, `Source=Lansweeper`
- Optional metadata: OS version, device type (sanitized if needed)

#### Arctic Wolf
- `EndpointKey`, `Source=ArcticWolf`
- Severity buckets: Critical/High/Medium/Low (derive counts per EndpointKey)
- Optional: top risk titles/categories (sanitized; do not include hostnames)

#### NinjaOne Patching
- `EndpointKey` if mapped; else store as unmapped group
- `PatchingEnabled` (true/false if available)
- `CompliancePct`, `MissingCount`, `FailedCount` if available

#### NinjaOne Vulnerabilities
- `EndpointKey` if mapped
- `VulnCritical/VulnHigh/VulnMedium/VulnLow` counts per EndpointKey

### 7) Correlate (join) across sources
Join primarily on `EndpointKey`.

Compute:
- Coverage counts per source
- Match rates (AW↔LS, Ninja↔AssetName)
- Overlap set counts:
  - Patching disabled AND (Critical/High vulns OR High/Critical risks)
  - Critical/High vulns but missing from patching data
  - High/Critical risks but missing from inventory
- RiskScore per EndpointKey:
  - +10 patching disabled
  - +5 per critical vuln
  - +3 per high vuln
  - +1 per medium vuln
  - +5 per high AW risk
  - +2 per medium AW risk

### 8) Generate outputs
#### CSV
Write:
- `samples/output/risk_patching_correlation.csv`

Columns (required):
- EndpointKey
- JoinConfidence
- PatchingEnabled
- CompliancePct
- MissingCount
- FailedCount
- VulnCritical
- VulnHigh
- VulnMedium
- VulnLow
- AWRiskCritical
- AWRiskHigh
- AWRiskMedium
- AWRiskLow
- RiskScore

#### Markdown report
Write:
- `samples/output/risk_patching_correlation.md`

Required structure:
1) Executive Summary (3–6 bullets)
2) Inputs used (filenames + timestamps)
3) Coverage overview (table)
4) Lansweeper summary
5) Arctic Wolf summary
6) NinjaOne patching summary
7) NinjaOne vulnerability summary
8) Correlation findings (overlap sets + match rates)
9) Top 25 endpoints by RiskScore (EndpointKey only)
10) Notes & assumptions (mapping caveats + parsing limitations)

---

## Done When
- Output CSV + report exist with no obvious PII.
- LS↔AW match is deterministic via Asset name.
- NinjaOne mapping is clearly reported (match % + gaps).