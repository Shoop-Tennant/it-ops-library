# Patch Operations Dashboard (NinjaOne)

Generates monthly OS + 3rd-party patching reports and publishes Knowledge Base articles under **Knowledge Base > Monthly Reports**. Supports `-WhatIf` to write markdown locally instead of creating KB articles.

## Prerequisites
- PowerShell 7+ on the automation device.
- NinjaOne API App with Authorization Code flow.
- Custom fields on the automation device:
  - `ninjaoneClientId` (text)
  - `ninjaoneClientSecret` (secure)
  - `ninjaoneInstance` (text, example: `us2.ninjarmm.com`)

## NinjaOne API App (OAuth)
1. Go to **Administration > Apps > API**.
2. Add a new API application.
3. Set **Application Platform** to **API Services (Machine-to-Machine)**.
4. Enable grant types:
   - Authorization Code
   - Refresh Token
5. Scopes: `monitoring` and `management` (plus `offline_access` for refresh tokens).
6. Redirect URI: `http://localhost:8400/callback`.
7. Save and copy the **Client ID** and **Client Secret**.

## Custom Fields
Create the following at the **Organization** or **Global** level:
- `ninjaoneClientId` (Text)
- `ninjaoneClientSecret` (Secure)
- `ninjaoneInstance` (Text)

Populate the fields on the automation device:
- `ninjaoneClientId`: Client ID from the API App
- `ninjaoneClientSecret`: Client Secret from the API App
- `ninjaoneInstance`: tenant domain only (no `https://`)

## Install Script in NinjaOne
1. Go to **Administration > Library > Automation**.
2. Add a new PowerShell script.
3. Paste the contents of `ninjaone/patching/dashboard/src/PatchOperationsDashboard.ps1`.
4. Save and schedule monthly (e.g., 1st of month, 2:00 AM).

## Run Locally
```powershell
pwsh ninjaone/patching/dashboard/src/PatchOperationsDashboard.ps1 -ReportMonth "January 2026" -WhatIf
```

The first run prompts for OAuth authorization in a browser and stores tokens securely for subsequent runs.

## API Export for Migration Evidence
To build SCCM-vs-NinjaOne comparison inputs from live NinjaOne API data, run:

```powershell
pwsh ninjaone/patching/dashboard/src/Export-NinjaOneCorrelationData.ps1
```

Outputs are written to `ninjaone/patching/dashboard/samples/raw/`:
- `ninjaone_devices_<timestamp>.csv`
- `ninjaone_patching_by_device_<timestamp>.csv`
- `ninjaone_vulnerabilities_<timestamp>.csv` (best-effort endpoint data, endpoint mapping depends on available API endpoint)
- `endpoint_crosswalk.template_<timestamp>.csv` (fill `AssetName` to map to Lansweeper/Arctic Wolf keys)
- `manifest.ninjaone_api_<timestamp>.yml`
- `ninjaone_api_pull_summary_<timestamp>.json`

Optional:
- `-IncludeRawEventExports` writes full OS/software patch event JSON snapshots.
- `-OutputDir <path>` writes to a custom folder.

## Parameters
- `-ReportMonth "MMMM yyyy"`: Target reporting month. Defaults to current month.
- `-ClientId`, `-ClientSecret`, `-Instance`: Override custom fields.
- `-RedirectUri`: Defaults to `http://localhost:8400/callback`.
- `-Scope`: Defaults to `monitoring management offline_access`.
- `-NoBrowser`: Print the authorization URL instead of opening a browser.
- `-PatchKBSpotlight`: List of KB numbers to highlight.
- `-SoftwareAllowlist`: Only include software titles that match this list.
- `-SoftwareBlocklist`: Exclude software titles that match this list.
- `-IncludeDrivers`: Include driver/firmware/hardware-related software in inventory (if supported by API).
- `-WhatIf`: Write markdown reports under `ninjaone/patching/dashboard/samples` instead of publishing KB articles.

## Output
KB article naming:
- `Patch Operations Dashboard - All Organizations - [Month Year]`
- `Patch Operations Dashboard - [Organization Name] - [Month Year]`

## Scheduling
Use **Administration > Policies > Automation > Scheduled Scripts** to run monthly. The script uses refresh tokens after the first interactive run.

## Notes
- Tokens are stored per-user in an encrypted JSON file (DPAPI on Windows).
- If the Knowledge Base folder name differs from `Monthly Reports`, update the script in `Publish-KbArticle`.
