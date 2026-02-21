# PowerShell Code Signing

## Why Signing Matters (PowerShell 7 + UNC Paths)
PowerShell 7 often treats scripts on UNC paths (for example, `\\wsl.localhost\...`) as remote. If your execution policy is `RemoteSigned` or `AllSigned`, unsigned scripts from UNC paths can be blocked. Signing eliminates this friction and provides integrity guarantees.

## Enterprise Path (Recommended)
- Use an internal code-signing certificate issued by your enterprise PKI.
- Trust the publisher via GPO or Intune.
- Execution policy guidance:
  - `RemoteSigned`: Allows local unsigned scripts; requires signatures for remote/UNC.
  - `AllSigned`: Requires signatures for all scripts, including local; highest assurance, more operational overhead.

## Dev Path (Personal PC)
For local development and testing:
1. Create a self-signed code-signing certificate in `Cert:\CurrentUser\My`.
2. Import the cert into both:
   - `Cert:\CurrentUser\TrustedPublisher`
   - `Cert:\CurrentUser\Root`
3. Use that certificate thumbprint to sign scripts.

Note: Without Root trust, signatures may appear untrusted or show `UnknownError` even if signing succeeded.

## How to Sign
Use `Set-AuthenticodeSignature` with a certificate thumbprint.

## How to Verify
Use `Get-AuthenticodeSignature` to check status and signer.

## Troubleshooting
- Check policies: `Get-ExecutionPolicy -List`.
- Common error: “not digitally signed” when policy requires signing.
- Temporary workaround: set `Process` scope to Bypass for the current session only.

## Cleanup (Dev Cert)
Remove the dev cert from:
- `Cert:\CurrentUser\My`
- `Cert:\CurrentUser\TrustedPublisher`
- `Cert:\CurrentUser\Root`

## Warnings
- Never commit certificates or private keys.
- Do not store secrets in the repo.

## Notes
- Timestamping is optional; it can improve validity after a cert expires but requires a timestamp server.
