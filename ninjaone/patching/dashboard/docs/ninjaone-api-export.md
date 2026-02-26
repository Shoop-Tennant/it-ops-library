# NinjaOne API Export for Correlation

## Purpose
Generate raw NinjaOne data for migration validation and correlation with SCCM/Lansweeper/Arctic Wolf datasets.

## Script
- `ninjaone/patching/dashboard/src/Export-NinjaOneCorrelationData.ps1`

## What it pulls
- Devices: `/api/v2/devices`
- OS patches:
  - `/api/v2/queries/os-patches` (`PENDING`, `FAILED`, `REJECTED`)
  - `/api/v2/queries/os-patch-installs` (`INSTALLED`, `FAILED`)
- 3rd-party software patches:
  - `/api/v2/queries/software-patches` (`PENDING`, `FAILED`, `REJECTED`)
  - `/api/v2/queries/software-patch-installs` (`INSTALLED`, `FAILED`)
- Vulnerabilities (best effort): tries known candidate endpoints and records which path worked.

## Run
```powershell
pwsh ninjaone/patching/dashboard/src/Export-NinjaOneCorrelationData.ps1 `
  -Instance "us2.ninjarmm.com" `
  -ClientId "<client-id>" `
  -ClientSecret "<client-secret>"
```

Or rely on existing env/custom fields:
- `ninjaoneClientId` / `NINJAONE_CLIENT_ID`
- `ninjaoneClientSecret` / `NINJAONE_CLIENT_SECRET`
- `ninjaoneInstance` / `NINJAONE_INSTANCE`

## Output files
Under `ninjaone/patching/dashboard/samples/raw/`:
- `ninjaone_devices_<timestamp>.csv`
- `ninjaone_patching_by_device_<timestamp>.csv`
- `ninjaone_vulnerabilities_<timestamp>.csv`
- `endpoint_crosswalk.template_<timestamp>.csv`
- `manifest.ninjaone_api_<timestamp>.yml`
- `ninjaone_api_pull_summary_<timestamp>.json`

## Notes
- `endpoint_crosswalk.template_*.csv` must be filled to deterministically map Ninja device names to `AssetName` join keys.
- `CompliancePct` in `ninjaone_patching_by_device_*.csv` is computed as:
  - `InstalledCount / (InstalledCount + MissingCount) * 100`
- If vulnerability endpoint data is aggregate-only for your tenant, endpoint fields may be blank in the vulnerability CSV.
