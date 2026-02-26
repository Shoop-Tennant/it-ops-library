#!/usr/bin/env pwsh
$currentVersion = $PSVersionTable.PSVersion
if ($currentVersion.Major -lt 7) {
  $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
  $pwshPath = if ($pwshCommand) { $pwshCommand.Source } else { $null }
  if (-not $pwshPath) {
    Write-Host "[PatchOps] PowerShell 7+ (pwsh) is required but was not found in PATH."
    exit 1
  }
  $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
  $argsList = @()
  foreach ($arg in $args) { $argsList += $arg }
  $argumentList = @('-NoProfile', '-File', $scriptPath) + $argsList
  $proc = Start-Process -FilePath $pwshPath -ArgumentList $argumentList -Wait -PassThru
  exit $proc.ExitCode
}

<#
.SYNOPSIS
  Patch Operations Dashboard for NinjaOne (OS + 3rd-party).
.DESCRIPTION
  Generates monthly OS and software patch metrics, then publishes Knowledge Base articles
  in NinjaOne or writes markdown locally when -WhatIf is used.
.NOTES
  Do not log client secrets or tokens. Tokens are stored encrypted per-user.
#>
function Invoke-PatchOperationsDashboard {
  [CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$NoKb,
    [switch]$DebugApi,
    [Parameter()]
    [string]$ReportMonth,

    [Parameter()]
    [string]$ClientId,

    [Parameter()]
    [string]$ClientSecret,

    [Parameter()]
    [string]$Instance,

    [Parameter()]
    [string]$RedirectUri = 'http://localhost:8400/callback',

    [Parameter()]
    [string]$Scope = 'monitoring management offline_access',

    [Parameter()]
    [string]$TokenPath,

    [Parameter()]
    [switch]$NoBrowser,

    [Parameter()]
    [string[]]$PatchKBSpotlight = @(),

    [Parameter()]
    [string[]]$SoftwareAllowlist = @(),

    [Parameter()]
    [string[]]$SoftwareBlocklist = @(),

    [Parameter()]
    [switch]$IncludeDrivers,

    [Parameter()]
    [int]$PageSize = 2000,

    [Parameter()]
    [int]$MaxPages = 100
  )

  Set-StrictMode -Version Latest
  $ErrorActionPreference = 'Stop'

  function Write-Info {
    param([string]$Message)
    Write-Host "[PatchOps] $Message"
  }

  function Resolve-ConfigValue {
    param(
      [string]$Value,
      [string[]]$EnvNames
    )
    if ($Value) { return $Value }
    foreach ($name in $EnvNames) {
      $envValue = [Environment]::GetEnvironmentVariable($name)
      if ($envValue) { return $envValue }
    }
    return $null
  }

  function Get-TokenPath {
    param([string]$Requested)
    if ($Requested) { return $Requested }
    if ($IsWindows) {
      return Join-Path $env:ProgramData 'NinjaOne\\PatchOpsDashboard\\tokens.json'
    }
    $base = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME '.config' }
    return Join-Path $base 'NinjaOne/PatchOpsDashboard/tokens.json'
  }

  function Protect-Secret {
    param([string]$PlainText)
    if ([string]::IsNullOrWhiteSpace($PlainText)) { return $null }
    $secure = ConvertTo-SecureString -String $PlainText -AsPlainText -Force
    return ConvertFrom-SecureString -SecureString $secure
  }

  function Unprotect-Secret {
    param([string]$CipherText)
    if ([string]::IsNullOrWhiteSpace($CipherText)) { return $null }
    $secure = ConvertTo-SecureString -String $CipherText
    return (New-Object System.Net.NetworkCredential('', $secure)).Password
  }

function Save-Tokens {
  param(
    [string]$Path,
    [hashtable]$Tokens
  )
  $folder = Split-Path -Parent $Path
  if (-not (Test-Path $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
  $payload = [ordered]@{
    access_token  = Protect-Secret $Tokens.access_token
    refresh_token = Protect-Secret $Tokens.refresh_token
    token_type    = $Tokens.token_type
    scope         = $Tokens.scope
    expires_at    = $Tokens.expires_at
  }
  $payload | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
}

function Load-Tokens {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return $null }
  $raw = Get-Content -Path $Path -Raw | ConvertFrom-Json
  return @{
    access_token  = Unprotect-Secret $raw.access_token
    refresh_token = Unprotect-Secret $raw.refresh_token
    token_type    = $raw.token_type
    scope         = $raw.scope
    expires_at    = $raw.expires_at
  }
}

function Get-OAuthEndpoints {
  param([string]$InstanceHost)
  $base = "https://$InstanceHost"
  return @{
    Authorize = "$base/ws/oauth/authorize"
    Token     = "$base/ws/oauth/token"
  }
}

function Start-LocalOAuthListener {
  param([string]$RedirectUri)
  $uri = [Uri]$RedirectUri
  $listener = New-Object System.Net.HttpListener
  $prefix = "{0}://{1}:{2}{3}" -f $uri.Scheme, $uri.Host, $uri.Port, ($uri.AbsolutePath.TrimEnd('/') + '/')
  $listener.Prefixes.Add($prefix)
  $listener.Start()
  return @{ Listener = $listener; Prefix = $prefix }
}

function Stop-LocalOAuthListener {
  param($Listener)
  try { $Listener.Stop() } catch { }
  try { $Listener.Close() } catch { }
}

function Get-AuthorizationCode {
  param(
    [string]$AuthorizeUrl,
    [string]$RedirectUri,
    [string]$ExpectedState,
    [switch]$NoBrowser
  )
  $listenerInfo = Start-LocalOAuthListener -RedirectUri $RedirectUri
  try {
    if (-not $NoBrowser) {
      Start-Process $AuthorizeUrl | Out-Null
      Write-Info "Opened browser for authorization."
    } else {
      Write-Info "Open this URL to authorize: $AuthorizeUrl"
    }

    Write-Info "Waiting for OAuth redirect on $($listenerInfo.Prefix) ..."
    while ($true) {
      $context = $listenerInfo.Listener.GetContext()
      $request = $context.Request
      $response = $context.Response

      $code = $request.QueryString['code']
      $state = $request.QueryString['state']
      $error = $request.QueryString['error']

      if ($error) {
        $errorMessage = "Authorization failed: $error"
        $buffer = [Text.Encoding]::UTF8.GetBytes($errorMessage)
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.OutputStream.Close()
        throw $errorMessage
      }

      if ($ExpectedState -and $state -and $state -ne $ExpectedState) {
        Write-Info "Ignoring OAuth callback with unmatched state."
        $message = "This callback does not match the current authorization session. Return to the original prompt and try again."
        $buffer = [Text.Encoding]::UTF8.GetBytes($message)
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.OutputStream.Close()
        continue
      }

      if (-not $code) {
        $message = "Waiting for authorization code."
        $buffer = [Text.Encoding]::UTF8.GetBytes($message)
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.OutputStream.Close()
        continue
      }

      $message = "Authorization complete. You may close this window."
      $buffer = [Text.Encoding]::UTF8.GetBytes($message)
      $response.ContentLength64 = $buffer.Length
      $response.OutputStream.Write($buffer, 0, $buffer.Length)
      $response.OutputStream.Close()

      return @{ Code = $code; State = $state }
    }
  } finally {
    Stop-LocalOAuthListener -Listener $listenerInfo.Listener
  }
}

function Request-Token {
  param(
    [string]$TokenUrl,
    [hashtable]$Body
  )
  return Invoke-RestMethod -Method Post -Uri $TokenUrl -Body $Body -ContentType 'application/x-www-form-urlencoded'
}

function Get-AccessToken {
  param(
    [string]$InstanceHost,
    [string]$ClientId,
    [string]$ClientSecret,
    [string]$RedirectUri,
    [string]$Scope,
    [string]$TokenPath,
    [switch]$NoBrowser
  )
  $oauth = Get-OAuthEndpoints -InstanceHost $InstanceHost
  $tokens = Load-Tokens -Path $TokenPath

  if ($tokens -and $tokens.expires_at) {
    $expiresAt = [DateTimeOffset]::Parse($tokens.expires_at)
    if ($expiresAt -gt [DateTimeOffset]::UtcNow.AddMinutes(5)) {
      return $tokens
    }
  }

  if ($tokens -and $tokens.refresh_token) {
    Write-Info "Refreshing access token."
    $refreshResponse = Request-Token -TokenUrl $oauth.Token -Body @{
      grant_type    = 'refresh_token'
      refresh_token = $tokens.refresh_token
      client_id     = $ClientId
      client_secret = $ClientSecret
    }
    $tokens = @{
      access_token  = $refreshResponse.access_token
      refresh_token = $refreshResponse.refresh_token
      token_type    = $refreshResponse.token_type
      scope         = $refreshResponse.scope
      expires_at    = [DateTimeOffset]::UtcNow.AddSeconds($refreshResponse.expires_in).ToString('o')
    }
    Save-Tokens -Path $TokenPath -Tokens $tokens
    return $tokens
  }

  Write-Info "Starting first-run OAuth flow."
  $state = [Guid]::NewGuid().ToString('N')
  $authorizeUrl = "$($oauth.Authorize)?response_type=code&client_id=$ClientId&redirect_uri=$([Uri]::EscapeDataString($RedirectUri))&scope=$([Uri]::EscapeDataString($Scope))&state=$state"
  $authResult = Get-AuthorizationCode -AuthorizeUrl $authorizeUrl -RedirectUri $RedirectUri -ExpectedState $state -NoBrowser:$NoBrowser

  if ($authResult.State -and $authResult.State -ne $state) {
    throw "OAuth state mismatch."
  }

  $tokenResponse = Request-Token -TokenUrl $oauth.Token -Body @{
    grant_type    = 'authorization_code'
    code          = $authResult.Code
    redirect_uri  = $RedirectUri
    client_id     = $ClientId
    client_secret = $ClientSecret
  }

  $tokens = @{
    access_token  = $tokenResponse.access_token
    refresh_token = $tokenResponse.refresh_token
    token_type    = $tokenResponse.token_type
    scope         = $tokenResponse.scope
    expires_at    = [DateTimeOffset]::UtcNow.AddSeconds($tokenResponse.expires_in).ToString('o')
  }
  Save-Tokens -Path $TokenPath -Tokens $tokens
  return $tokens
}

function Invoke-NinjaOneApi {
  param(
    [string]$Method,
    [string]$BaseUrl,
    [string]$Path,
    [hashtable]$Headers,
    [hashtable]$Query,
    [object]$Body
  )
  $uri = Get-NinjaOneApiUrl -BaseUrl $BaseUrl -Path $Path -Query $Query
  $params = @{
    Method  = $Method
    Uri     = $uri
    Headers = $Headers
  }
  if ($Body) {
    $params.Body = ConvertTo-Json -InputObject $Body -Depth 8
    $params.ContentType = 'application/json'
  }
  Write-Host "[PatchOps][API] $Method $uri"
  return Invoke-RestMethod @params
}

function Get-NinjaOneApiUrl {
  param(
    [string]$BaseUrl,
    [string]$Path,
    [hashtable]$Query
  )
  $uriBuilder = [System.UriBuilder]::new("$BaseUrl$Path")
  if ($Query) {
    $pairs = @()
    foreach ($key in $Query.Keys) {
      if ($null -ne $Query[$key] -and $Query[$key] -ne '') {
        $pairs += "{0}={1}" -f $key, [Uri]::EscapeDataString([string]$Query[$key])
      }
    }
    $uriBuilder.Query = [string]::Join('&', $pairs)
  }
  return $uriBuilder.Uri.AbsoluteUri
}

function Invoke-NinjaOnePagedQuery {
  param(
    [string]$BaseUrl,
    [string]$Path,
    [hashtable]$Headers,
    [hashtable]$Query,
    [int]$PageSize,
    [int]$MaxPages
  )
  $all = @()
  $cursor = $null
  $seenCursors = @{}
  for ($page = 1; $page -le $MaxPages; $page++) {
    $queryWithCursor = @{}
    if ($Query) { $Query.Keys | ForEach-Object { $queryWithCursor[$_] = $Query[$_] } }
    $queryWithCursor['pageSize'] = $PageSize
    if ($cursor) { $queryWithCursor['cursor'] = $cursor }

    if ($DebugApi -and $Path -in @('/api/v2/queries/os-patches', '/api/v2/queries/software-patches')) {
      $debugUrl = Get-NinjaOneApiUrl -BaseUrl $BaseUrl -Path $Path -Query $queryWithCursor
      Write-Host "[DebugApi] Query request URL: $debugUrl"
    }

    $response = Invoke-NinjaOneApi -Method 'GET' -BaseUrl $BaseUrl -Path $Path -Headers $Headers -Query $queryWithCursor
    $collection = $null
    if ($response -and $response.PSObject -and $response.PSObject.Properties) {
      foreach ($collectionName in @('results', 'items', 'data', 'articles')) {
        $prop = $response.PSObject.Properties[$collectionName]
        if ($null -eq $prop -or $null -eq $prop.Value) { continue }
        if ($prop.Value -is [string]) { continue }
        if ($prop.Value -is [System.Collections.IDictionary]) { continue }
        if ($prop.Value -isnot [System.Collections.IEnumerable]) { continue }

        $collection = @(Ensure-Array $prop.Value)
        break
      }
    }

    if ($null -ne $collection) {
      $items = $collection
      $all += $items
      if ($items.Count -lt $PageSize) { break }

      $nextCursor = $null
      if ($response.PSObject.Properties.Name -contains 'cursor' -and $response.cursor) {
        if ($response.cursor -is [string]) {
          $nextCursor = [string]$response.cursor
        } elseif ($response.cursor.PSObject.Properties.Name -contains 'name' -and $response.cursor.name) {
          $nextCursor = [string]$response.cursor.name
        }
      }

      if (-not $nextCursor) { break }
      if ($seenCursors.ContainsKey($nextCursor)) { break }
      $seenCursors[$nextCursor] = $true
      $cursor = $nextCursor
      continue
    }

    if ($response -is [System.Collections.IEnumerable] -and -not ($response -is [string])) {
      $items = @(Ensure-Array $response)
      $all += $items
      if ($items.Count -lt $PageSize) { break }
      continue
    }

    $all += @(Ensure-Array $response)
    break
  }
  return $all
}

function Get-DeviceId {
  param([object]$Item)
  foreach ($name in @('deviceId','nodeId','device.id','deviceId.id')) {
    if ($Item.PSObject.Properties.Name -contains $name) {
      return $Item.$name
    }
  }
  if ($Item.device -and $Item.device.id) { return $Item.device.id }
  return $null
}

function Get-ItemName {
  param([object]$Item)
  foreach ($name in @('name','title','productName','softwareName','patchName')) {
    if ($Item.PSObject.Properties.Name -contains $name -and $Item.$name) {
      return [string]$Item.$name
    }
  }
  return $null
}

function Normalize-MonthRange {
  param([string]$ReportMonth)
  if ([string]::IsNullOrWhiteSpace($ReportMonth)) {
    $start = Get-Date -Day 1 -Hour 0 -Minute 0 -Second 0
  } else {
    $start = [DateTime]::ParseExact($ReportMonth, 'MMMM yyyy', $null)
  }
  $end = $start.AddMonths(1).AddSeconds(-1)
  return @{ Start = $start; End = $end }
}

function Build-ReportMarkdown {
  param(
    [string]$Title,
    [string]$MonthLabel,
    [hashtable]$Metrics,
    [object[]]$TopOffenders,
    [object[]]$OsDetails,
    [object[]]$SoftwareDetails,
    [string[]]$Notes,
    [string[]]$PatchKBSpotlight
  )
  $PatchKBSpotlight = @(Ensure-Array $PatchKBSpotlight)
  $TopOffenders = @(Ensure-Array $TopOffenders)
  $OsDetails = @(Ensure-Array $OsDetails)
  $SoftwareDetails = @(Ensure-Array $SoftwareDetails)
  $Notes = @(Ensure-Array $Notes)

  $lines = @()
  $lines += "# $Title"
  $lines += ""
  $lines += "**Reporting Month:** $MonthLabel"
  $lines += ""
  $lines += "## Executive Summary"
  $lines += "- **OS Patches:** Scanned $($Metrics.OS.Scanned), Missing $($Metrics.OS.Missing), Installed $($Metrics.OS.Installed), Failed $($Metrics.OS.Failed)"
  $lines += "- **Software Patches:** Scanned $($Metrics.Software.Scanned), Missing $($Metrics.Software.Missing), Installed $($Metrics.Software.Installed), Failed $($Metrics.Software.Failed)"
  $lines += ""

  if ($PatchKBSpotlight.Count -gt 0) {
    $lines += "## Patch KB Spotlight"
    foreach ($kb in $PatchKBSpotlight) { $lines += "- $kb" }
    $lines += ""
  }

  $lines += "## Top Offenders"
  if ($TopOffenders.Count -eq 0) {
    $lines += "- None"
  } else {
    foreach ($offender in $TopOffenders) {
      $lines += "- $($offender.Name) (Missing/Failed: $($offender.Count))"
    }
  }
  $lines += ""

  $lines += "## OS Patching"
  if ($OsDetails.Count -eq 0) {
    $lines += "- No OS patch exceptions detected for the period."
  } else {
    foreach ($row in $OsDetails) {
      $lines += "- $($row.Name) | Missing: $($row.Missing) | Failed: $($row.Failed)"
    }
  }
  $lines += ""

  $lines += "## Software Patching"
  if ($SoftwareDetails.Count -eq 0) {
    $lines += "- No software patch exceptions detected for the period."
  } else {
    foreach ($row in $SoftwareDetails) {
      $lines += "- $($row.Name) | Missing: $($row.Missing) | Failed: $($row.Failed)"
    }
  }
  $lines += ""

  $lines += "## Notes / Caveats"
  foreach ($note in $Notes) { $lines += "- $note" }

  return $lines -join "`n"
}

function Write-MarkdownReport {
  param(
    [string]$OutputDir,
    [string]$FileName,
    [string]$Content
  )
  if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force -WhatIf:$false -Confirm:$false | Out-Null }
  $path = Join-Path $OutputDir $FileName
  Set-Content -Path $path -Value $Content -Encoding UTF8 -WhatIf:$false -Confirm:$false
  return $path
}

function Get-Header {
  param([string]$AccessToken)
  return @{ Authorization = "Bearer $AccessToken" }
}

function Ensure-Array {
  param($Value)
  if ($null -eq $Value) { return @() }
  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) { return @($Value) }
  return @($Value)
}

function Get-ObjectPropertyValue {
  param(
    [object]$InputObject,
    [string[]]$Names
  )
  if ($null -eq $InputObject -or -not $Names) { return $null }

  foreach ($name in $Names) {
    if ([string]::IsNullOrWhiteSpace($name)) { continue }
    if ($InputObject -is [System.Collections.IDictionary]) {
      if ($InputObject.Contains($name)) {
        return $InputObject[$name]
      }
      continue
    }

    if ($InputObject.PSObject -and $InputObject.PSObject.Properties) {
      $property = $InputObject.PSObject.Properties[$name]
      if ($null -ne $property) {
        return $property.Value
      }
    }
  }

  return $null
}

function Merge-Items {
  param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$Collections
  )
  $merged = @()
  foreach ($collection in $Collections) {
    $merged += Ensure-Array $collection
  }
  return $merged
}

$ClientId = Resolve-ConfigValue -Value $ClientId -EnvNames @('ninjaoneClientId','NINJAONECLIENTID','NINJAONE_CLIENT_ID')
$ClientSecret = Resolve-ConfigValue -Value $ClientSecret -EnvNames @('ninjaoneClientSecret','NINJAONECLIENTSECRET','NINJAONE_CLIENT_SECRET')
$Instance = Resolve-ConfigValue -Value $Instance -EnvNames @('ninjaoneInstance','NINJAONEINSTANCE','NINJAONE_INSTANCE')

if (-not $ClientId -or -not $ClientSecret -or -not $Instance) {
  throw "Missing required NinjaOne configuration. Ensure ninjaoneClientId, ninjaoneClientSecret, and ninjaoneInstance are set."
}

$tokenPath = Get-TokenPath -Requested $TokenPath
$monthRange = Normalize-MonthRange -ReportMonth $ReportMonth
$monthLabel = $monthRange.Start.ToString('MMMM yyyy')

Write-Info "Preparing Patch Operations Dashboard for $monthLabel"

$tokens = Get-AccessToken -InstanceHost $Instance -ClientId $ClientId -ClientSecret $ClientSecret -RedirectUri $RedirectUri -Scope $Scope -TokenPath $tokenPath -NoBrowser:$NoBrowser
$headers = Get-Header -AccessToken $tokens.access_token
$baseUrl = "https://$Instance"

$osMissing = @(Invoke-NinjaOnePagedQuery -BaseUrl $baseUrl -Path '/api/v2/queries/os-patches' -Headers $headers -Query @{
  status = 'PENDING'
} -PageSize $PageSize -MaxPages $MaxPages)
$osFailed = @(Invoke-NinjaOnePagedQuery -BaseUrl $baseUrl -Path '/api/v2/queries/os-patches' -Headers $headers -Query @{
  status = 'FAILED'
} -PageSize $PageSize -MaxPages $MaxPages)
$osRejected = @(Invoke-NinjaOnePagedQuery -BaseUrl $baseUrl -Path '/api/v2/queries/os-patches' -Headers $headers -Query @{
  status = 'REJECTED'
} -PageSize $PageSize -MaxPages $MaxPages)

$osInstalled = @(Invoke-NinjaOnePagedQuery -BaseUrl $baseUrl -Path '/api/v2/queries/os-patch-installs' -Headers $headers -Query @{
  status = 'INSTALLED'
} -PageSize $PageSize -MaxPages $MaxPages)
$osFailedInstalls = @(Invoke-NinjaOnePagedQuery -BaseUrl $baseUrl -Path '/api/v2/queries/os-patch-installs' -Headers $headers -Query @{
  status = 'FAILED'
} -PageSize $PageSize -MaxPages $MaxPages)

$softwareMissing = @(Invoke-NinjaOnePagedQuery -BaseUrl $baseUrl -Path '/api/v2/queries/software-patches' -Headers $headers -Query @{
  status = 'PENDING'
} -PageSize $PageSize -MaxPages $MaxPages)
$softwareFailed = @(Invoke-NinjaOnePagedQuery -BaseUrl $baseUrl -Path '/api/v2/queries/software-patches' -Headers $headers -Query @{
  status = 'FAILED'
} -PageSize $PageSize -MaxPages $MaxPages)
$softwareRejected = @(Invoke-NinjaOnePagedQuery -BaseUrl $baseUrl -Path '/api/v2/queries/software-patches' -Headers $headers -Query @{
  status = 'REJECTED'
} -PageSize $PageSize -MaxPages $MaxPages)

$softwareInstalled = @(Invoke-NinjaOnePagedQuery -BaseUrl $baseUrl -Path '/api/v2/queries/software-patch-installs' -Headers $headers -Query @{
  status = 'INSTALLED'
} -PageSize $PageSize -MaxPages $MaxPages)
$softwareFailedInstalls = @(Invoke-NinjaOnePagedQuery -BaseUrl $baseUrl -Path '/api/v2/queries/software-patch-installs' -Headers $headers -Query @{
  status = 'FAILED'
} -PageSize $PageSize -MaxPages $MaxPages)

$softwareMissingFiltered = $softwareMissing
$softwareFailedFiltered = $softwareFailed
$softwareRejectedFiltered = $softwareRejected
if ($SoftwareAllowlist.Count -gt 0) {
  $softwareMissingFiltered = $softwareMissingFiltered | Where-Object { $SoftwareAllowlist -contains (Get-ItemName $_) }
  $softwareFailedFiltered = $softwareFailedFiltered | Where-Object { $SoftwareAllowlist -contains (Get-ItemName $_) }
  $softwareRejectedFiltered = $softwareRejectedFiltered | Where-Object { $SoftwareAllowlist -contains (Get-ItemName $_) }
}
if ($SoftwareBlocklist.Count -gt 0) {
  $softwareMissingFiltered = $softwareMissingFiltered | Where-Object { $SoftwareBlocklist -notcontains (Get-ItemName $_) }
  $softwareFailedFiltered = $softwareFailedFiltered | Where-Object { $SoftwareBlocklist -notcontains (Get-ItemName $_) }
  $softwareRejectedFiltered = $softwareRejectedFiltered | Where-Object { $SoftwareBlocklist -notcontains (Get-ItemName $_) }
}
$softwareMissingFiltered = @(Ensure-Array $softwareMissingFiltered)
$softwareFailedFiltered = @(Ensure-Array $softwareFailedFiltered)
$softwareRejectedFiltered = @(Ensure-Array $softwareRejectedFiltered)

$offenders = @{}
foreach ($item in (Merge-Items $osMissing $osFailed $osRejected $softwareMissingFiltered $softwareFailedFiltered $softwareRejectedFiltered)) {
  $deviceId = Get-DeviceId $item
  if (-not $deviceId) { continue }
  if (-not $offenders.ContainsKey($deviceId)) { $offenders[$deviceId] = 0 }
  $offenders[$deviceId]++
}

$deviceMap = @{}
$deviceOrgMap = @{}
try {
  $devices = @(Invoke-NinjaOnePagedQuery -BaseUrl $baseUrl -Path '/api/v2/devices' -Headers $headers -Query @{} -PageSize $PageSize -MaxPages $MaxPages)
  foreach ($device in $devices) {
    if ($device.id -and $device.systemName) {
      $deviceMap[$device.id] = $device.systemName
    }
    if ($device.id -and $device.organizationId) {
      $deviceOrgMap[$device.id] = $device.organizationId
    }
  }
} catch {
  Write-Info "Device lookup failed: $($_.Exception.Message)"
}

function Build-Offenders {
  param([hashtable]$OffenderCounts)
  return $OffenderCounts.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 10 | ForEach-Object {
    [pscustomobject]@{
      Id    = $_.Key
      Name  = if ($deviceMap.ContainsKey($_.Key)) { $deviceMap[$_.Key] } else { $_.Key }
      Count = $_.Value
    }
  }
}

$topOffenders = Build-Offenders -OffenderCounts $offenders

function Filter-ItemsByOrg {
  param(
    [object[]]$Items,
    [int]$OrganizationId
  )
  return @($Items | Where-Object {
    $deviceId = Get-DeviceId $_
    $deviceId -and $deviceOrgMap.ContainsKey($deviceId) -and $deviceOrgMap[$deviceId] -eq $OrganizationId
  })
}

function Build-Metrics {
  param(
    [object[]]$OsMissingItems,
    [object[]]$OsFailedItems,
    [object[]]$OsRejectedItems,
    [object[]]$OsInstalledItems,
    [object[]]$OsFailedInstallItems,
    [object[]]$SoftwareMissingItems,
    [object[]]$SoftwareFailedItems,
    [object[]]$SoftwareRejectedItems,
    [object[]]$SoftwareInstalledItems,
    [object[]]$SoftwareFailedInstallItems
  )
  $OsMissingItems = @(Ensure-Array $OsMissingItems)
  $OsFailedItems = @(Ensure-Array $OsFailedItems)
  $OsRejectedItems = @(Ensure-Array $OsRejectedItems)
  $OsInstalledItems = @(Ensure-Array $OsInstalledItems)
  $OsFailedInstallItems = @(Ensure-Array $OsFailedInstallItems)
  $SoftwareMissingItems = @(Ensure-Array $SoftwareMissingItems)
  $SoftwareFailedItems = @(Ensure-Array $SoftwareFailedItems)
  $SoftwareRejectedItems = @(Ensure-Array $SoftwareRejectedItems)
  $SoftwareInstalledItems = @(Ensure-Array $SoftwareInstalledItems)
  $SoftwareFailedInstallItems = @(Ensure-Array $SoftwareFailedInstallItems)

  $osMissingCount = $OsMissingItems.Count + $OsFailedItems.Count + $OsRejectedItems.Count
  $softwareMissingCount = $SoftwareMissingItems.Count + $SoftwareFailedItems.Count + $SoftwareRejectedItems.Count

  $osScanned = @(Merge-Items $OsMissingItems $OsFailedItems $OsRejectedItems $OsInstalledItems $OsFailedInstallItems | ForEach-Object { Get-DeviceId $_ } | Where-Object { $_ }) | Select-Object -Unique | Measure-Object | Select-Object -ExpandProperty Count
  $softwareScanned = @(Merge-Items $SoftwareMissingItems $SoftwareFailedItems $SoftwareRejectedItems $SoftwareInstalledItems $SoftwareFailedInstallItems | ForEach-Object { Get-DeviceId $_ } | Where-Object { $_ }) | Select-Object -Unique | Measure-Object | Select-Object -ExpandProperty Count

  return @{
    OS = @{
      Scanned   = $osScanned
      Missing   = $osMissingCount
      Installed = $OsInstalledItems.Count
      Failed    = $OsFailedInstallItems.Count
    }
    Software = @{
      Scanned   = $softwareScanned
      Missing   = $softwareMissingCount
      Installed = $SoftwareInstalledItems.Count
      Failed    = $SoftwareFailedInstallItems.Count
    }
  }
}

$metrics = Build-Metrics -OsMissingItems $osMissing -OsFailedItems $osFailed -OsRejectedItems $osRejected -OsInstalledItems $osInstalled -OsFailedInstallItems $osFailedInstalls -SoftwareMissingItems $softwareMissingFiltered -SoftwareFailedItems $softwareFailedFiltered -SoftwareRejectedItems $softwareRejectedFiltered -SoftwareInstalledItems $softwareInstalled -SoftwareFailedInstallItems $softwareFailedInstalls

$osSummary = @{}
foreach ($item in (Merge-Items $osMissing $osRejected)) {
  $deviceId = Get-DeviceId $item
  if (-not $deviceId) { continue }
  if (-not $osSummary.ContainsKey($deviceId)) { $osSummary[$deviceId] = [ordered]@{ Missing = 0; Failed = 0 } }
  $osSummary[$deviceId].Missing++
}
foreach ($item in $osFailed) {
  $deviceId = Get-DeviceId $item
  if (-not $deviceId) { continue }
  if (-not $osSummary.ContainsKey($deviceId)) { $osSummary[$deviceId] = [ordered]@{ Missing = 0; Failed = 0 } }
  $osSummary[$deviceId].Failed++
}
$osDetails = $osSummary.GetEnumerator() | Sort-Object { $_.Value.Missing + $_.Value.Failed } -Descending | Select-Object -First 10 | ForEach-Object {
  [pscustomobject]@{
    Name    = if ($deviceMap.ContainsKey($_.Key)) { $deviceMap[$_.Key] } else { $_.Key }
    Missing = $_.Value.Missing
    Failed  = $_.Value.Failed
  }
}

$softwareSummary = @{}
foreach ($item in (Merge-Items $softwareMissingFiltered $softwareRejectedFiltered)) {
  $deviceId = Get-DeviceId $item
  if (-not $deviceId) { continue }
  if (-not $softwareSummary.ContainsKey($deviceId)) { $softwareSummary[$deviceId] = [ordered]@{ Missing = 0; Failed = 0 } }
  $softwareSummary[$deviceId].Missing++
}
foreach ($item in $softwareFailedFiltered) {
  $deviceId = Get-DeviceId $item
  if (-not $deviceId) { continue }
  if (-not $softwareSummary.ContainsKey($deviceId)) { $softwareSummary[$deviceId] = [ordered]@{ Missing = 0; Failed = 0 } }
  $softwareSummary[$deviceId].Failed++
}
$softwareDetails = $softwareSummary.GetEnumerator() | Sort-Object { $_.Value.Missing + $_.Value.Failed } -Descending | Select-Object -First 10 | ForEach-Object {
  [pscustomobject]@{
    Name    = if ($deviceMap.ContainsKey($_.Key)) { $deviceMap[$_.Key] } else { $_.Key }
    Missing = $_.Value.Missing
    Failed  = $_.Value.Failed
  }
}

$notes = @(
  "Missing counts include pending, failed, and rejected patches detected between $($monthRange.Start.ToString('yyyy-MM-dd')) and $($monthRange.End.ToString('yyyy-MM-dd')).",
  "Devices that were offline or did not scan during the month may be underrepresented in results.",
  "Software section reflects allowlist/blocklist filters if configured."
)

function Get-ApiArgumentValue {
    param(
        [object[]]$Arguments,
        [string[]]$Names
    )

    foreach ($arg in $Arguments) {
        if ($arg -is [System.Collections.IDictionary]) {
            foreach ($name in $Names) {
                foreach ($key in $arg.Keys) {
                    if ([string]$key -ieq $name) {
                        return $arg[$key]
                    }
                }
            }
        }
    }

    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $arg = $Arguments[$i]
        if ($arg -isnot [string]) {
            continue
        }
        $normalizedArg = $arg.TrimEnd(':')

        foreach ($name in $Names) {
            if ($normalizedArg -ieq "-$name") {
                if ($i + 1 -lt $Arguments.Count) {
                    return $Arguments[$i + 1]
                }
                return $null
            }
        }
    }

    return $null
}

function Convert-ApiArgumentsToHashtable {
    param(
        [object[]]$Arguments
    )

    if ($Arguments.Count -eq 1 -and $Arguments[0] -is [System.Collections.IDictionary]) {
        $nativeParams = @{}
        foreach ($key in $Arguments[0].Keys) {
            $cleanKey = ([string]$key).TrimEnd(':')
            $nativeParams[$cleanKey] = $Arguments[0][$key]
        }
        return $nativeParams
    }

    $nativeParams = @{}
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $arg = $Arguments[$i]
        if ($arg -isnot [string] -or -not $arg.StartsWith('-')) {
            continue
        }

        $name = $arg.TrimStart('-').TrimEnd(':')
        $hasNext = $i + 1 -lt $Arguments.Count
        if ($hasNext -and -not ($Arguments[$i + 1] -is [string] -and $Arguments[$i + 1].StartsWith('-'))) {
            $nativeParams[$name] = $Arguments[$i + 1]
            $i++
        } else {
            $nativeParams[$name] = $true
        }
    }

    return $nativeParams
}

function Test-KbApiUri {
    param(
        [string]$Uri
    )

    if ([string]::IsNullOrWhiteSpace($Uri)) {
        return $false
    }

    return $Uri -match '(?i)(/kb\b|/knowledge[-_]?base\b|knowledgebase|knowledge-base)'
}

function Get-KbHttpErrorInfo {
    param(
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $statusCode = $null
    $body = $null

    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        $body = $ErrorRecord.ErrorDetails.Message
    }

    $response = $ErrorRecord.Exception.Response
    if ($response) {
        if ($response -is [System.Net.Http.HttpResponseMessage]) {
            if (-not $statusCode) {
                $statusCode = [int]$response.StatusCode
            }
            if (-not $body -and $response.Content) {
                try {
                    $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                } catch {
                    # Keep a best-effort error body.
                }
            }
        } else {
            if (-not $statusCode) {
                try {
                    $statusCode = [int]$response.StatusCode
                } catch {
                    # Leave unknown status when conversion is not possible.
                }
            }
            if (-not $body) {
                try {
                    $stream = $response.GetResponseStream()
                    if ($stream) {
                        $reader = [System.IO.StreamReader]::new($stream)
                        try {
                            $body = $reader.ReadToEnd()
                        } finally {
                            $reader.Dispose()
                            $stream.Dispose()
                        }
                    }
                } catch {
                    # Keep a best-effort error body.
                }
            }
        }
    }

    if (-not $body -and $ErrorRecord.Exception.Message) {
        $body = $ErrorRecord.Exception.Message
    }

    return @{
        StatusCode = $statusCode
        Body       = $body
    }
}

function Throw-KbApiFailure {
    param(
        [string]$Method,
        [string]$Uri,
        [object]$StatusCode,
        [string]$Body
    )

    $statusText = if ($null -ne $StatusCode -and $StatusCode -ne '') { $StatusCode } else { 'unknown' }
    $bodyText = if ([string]::IsNullOrWhiteSpace($Body)) { '<empty>' } else { $Body }
    throw "KB API request failed: method=$Method uri=$Uri status=$statusText body=$bodyText"
}

function Test-KbApiStatusCode {
    param(
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [int]$StatusCode
    )

    if (-not $ErrorRecord -or -not $ErrorRecord.Exception -or [string]::IsNullOrWhiteSpace($ErrorRecord.Exception.Message)) {
        return $false
    }

    return $ErrorRecord.Exception.Message -match ("status={0}(\D|$)" -f $StatusCode)
}

function Write-KbApiDebug {
    param(
        [string]$Method,
        [string]$Uri,
        [object]$Body
    )

    if (-not $DebugApi) {
        return
    }

    $bodyText = if ($null -eq $Body) { '<null>' } else { [string]$Body }
    if ($bodyText.Length -gt 500) {
        $bodyText = $bodyText.Substring(0, 500) + '...'
    }

    Write-Host ("[DebugApi] KB request {0} {1}`n[DebugApi] Body: {2}" -f $Method, $Uri, $bodyText)
}

function Invoke-RestMethod {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$RemainingArgs
    )

    $uri = [string](Get-ApiArgumentValue -Arguments $RemainingArgs -Names @('Uri'))
    $method = [string](Get-ApiArgumentValue -Arguments $RemainingArgs -Names @('Method'))
    if ([string]::IsNullOrWhiteSpace($method)) {
        $method = 'GET'
    }
    $method = $method.ToUpperInvariant()
    $body = Get-ApiArgumentValue -Arguments $RemainingArgs -Names @('Body')
    $isKbRequest = Test-KbApiUri -Uri $uri

    if ($isKbRequest) {
        Write-KbApiDebug -Method $method -Uri $uri -Body $body
        if ($NoKb -and $method -notin @('GET', 'HEAD', 'OPTIONS')) {
            Write-Host ("Skipping KB API request due to -NoKb: {0} {1}" -f $method, $uri)
            return $null
        }
    }

    $nativeParams = Convert-ApiArgumentsToHashtable -Arguments $RemainingArgs
    try {
        return Microsoft.PowerShell.Utility\Invoke-RestMethod @nativeParams
    } catch {
        if (-not $isKbRequest) {
            throw
        }
        $errorInfo = Get-KbHttpErrorInfo -ErrorRecord $_
        Throw-KbApiFailure -Method $method -Uri $uri -StatusCode $errorInfo.StatusCode -Body $errorInfo.Body
    }
}

function Invoke-WebRequest {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$RemainingArgs
    )

    $uri = [string](Get-ApiArgumentValue -Arguments $RemainingArgs -Names @('Uri'))
    $method = [string](Get-ApiArgumentValue -Arguments $RemainingArgs -Names @('Method'))
    if ([string]::IsNullOrWhiteSpace($method)) {
        $method = 'GET'
    }
    $method = $method.ToUpperInvariant()
    $body = Get-ApiArgumentValue -Arguments $RemainingArgs -Names @('Body')
    $isKbRequest = Test-KbApiUri -Uri $uri

    if ($isKbRequest) {
        Write-KbApiDebug -Method $method -Uri $uri -Body $body
        if ($NoKb -and $method -notin @('GET', 'HEAD', 'OPTIONS')) {
            Write-Host ("Skipping KB API request due to -NoKb: {0} {1}" -f $method, $uri)
            return $null
        }
    }

    $nativeParams = Convert-ApiArgumentsToHashtable -Arguments $RemainingArgs
    try {
        $response = Microsoft.PowerShell.Utility\Invoke-WebRequest @nativeParams
    } catch {
        if (-not $isKbRequest) {
            throw
        }
        $errorInfo = Get-KbHttpErrorInfo -ErrorRecord $_
        Throw-KbApiFailure -Method $method -Uri $uri -StatusCode $errorInfo.StatusCode -Body $errorInfo.Body
    }

    if ($isKbRequest -and $response -and ($response.PSObject.Properties.Name -contains 'StatusCode')) {
        $statusCode = $null
        try {
            $statusCode = [int]$response.StatusCode
        } catch {
            # If status cannot be parsed, do not force failure here.
        }

        if ($null -ne $statusCode -and ($statusCode -lt 200 -or $statusCode -ge 300)) {
            $content = $null
            if ($response.PSObject.Properties.Name -contains 'Content') {
                $content = [string]$response.Content
            }
            Throw-KbApiFailure -Method $method -Uri $uri -StatusCode $statusCode -Body $content
        }
    }

    return $response
}

$orgs = @(Invoke-NinjaOnePagedQuery -BaseUrl $baseUrl -Path '/api/v2/organizations' -Headers $headers -Query @{} -PageSize $PageSize -MaxPages $MaxPages)

function Publish-KbArticle {
  param(
    [string]$Title,
    [string]$Body,
    [int]$OrganizationId,
    [string]$MonthLabel,
    [hashtable]$Headers,
    [string]$BaseUrl,
    [int]$PageSize,
    [int]$MaxPages
  )
  if ($OrganizationId -le 0) {
    Write-Info "Skipping KB publish for aggregate report '$Title' (organizationId=$OrganizationId is not supported for article create)."
    return
  }

  function Find-ExistingKbArticle {
    param(
      [string]$Title,
      [int]$OrganizationId,
      [hashtable]$Headers,
      [string]$BaseUrl,
      [int]$PageSize,
      [int]$MaxPages
    )

    $lookupTargets = @(
      @{
        Path     = '/api/v2/knowledgebase/organization/articles'
        Query    = @{ articleName = $Title; organisationIds = $OrganizationId }
        MatchOrg = $true
      },
      @{
        Path     = '/api/v2/knowledgebase/global/articles'
        Query    = @{ articleName = $Title }
        MatchOrg = $false
      },
      @{
        Path     = '/api/v2/knowledgebase/global/articles'
        Query    = @{}
        MatchOrg = $false
      },
      @{
        Path     = '/api/v2/knowledgebase/articles'
        Query    = @{ articleName = $Title }
        MatchOrg = $false
      },
      @{
        Path     = '/api/v2/knowledgebase/articles'
        Query    = @{}
        MatchOrg = $false
      }
    )

    foreach ($target in $lookupTargets) {
      $rawItems = @()
      try {
        $rawItems = @(Invoke-NinjaOnePagedQuery -BaseUrl $BaseUrl -Path $target.Path -Headers $Headers -Query $target.Query -PageSize $PageSize -MaxPages $MaxPages)
      } catch {
        if ((Test-KbApiStatusCode -ErrorRecord $_ -StatusCode 400) -or
            (Test-KbApiStatusCode -ErrorRecord $_ -StatusCode 404) -or
            (Test-KbApiStatusCode -ErrorRecord $_ -StatusCode 405)) {
          continue
        }
        throw
      }

      if ($rawItems.Count -eq 0) { continue }

      foreach ($item in $rawItems) {
        $name = Get-ObjectPropertyValue -InputObject $item -Names @('articleName', 'name', 'title')
        if ([string]::IsNullOrWhiteSpace([string]$name) -or [string]$name -ne $Title) {
          continue
        }

        $id = Get-ObjectPropertyValue -InputObject $item -Names @('id', 'articleId')
        if ($null -eq $id -or [string]::IsNullOrWhiteSpace([string]$id)) {
          continue
        }

        $itemOrg = Get-ObjectPropertyValue -InputObject $item -Names @('organizationId', 'organisationId')
        if ($target.MatchOrg -or (-not [string]::IsNullOrWhiteSpace([string]$itemOrg))) {
          if ([string]$itemOrg -ne [string]$OrganizationId) {
            continue
          }
        }

        return [pscustomobject]@{
          id   = [string]$id
          path = [string]$target.Path
          name = [string]$name
        }
      }
    }

    return $null
  }

  function Update-KbArticleById {
    param(
      [string]$ArticleId,
      [string]$SourcePath,
      [string]$Title,
      [string]$Body,
      [int]$OrganizationId,
      [object]$TargetFolder,
      [hashtable]$Headers,
      [string]$BaseUrl
    )

    $payloadVariants = @(
      [ordered]@{
        id              = $ArticleId
        articleName     = $Title
        article         = $Body
        organizationId  = $OrganizationId
        relatedEntities = @()
      },
      [ordered]@{
        id              = $ArticleId
        articleName     = $Title
        article         = $Body
        organisationId  = $OrganizationId
        relatedEntities = @()
      },
      [ordered]@{
        id              = $ArticleId
        name            = $Title
        article         = $Body
        organizationId  = $OrganizationId
        relatedEntities = @()
      },
      [ordered]@{
        id              = $ArticleId
        name            = $Title
        article         = $Body
        organisationId  = $OrganizationId
        relatedEntities = @()
      },
      [ordered]@{
        id              = $ArticleId
        name            = $Title
        content         = $Body
        organizationId  = $OrganizationId
        relatedEntities = @()
      },
      [ordered]@{
        id              = $ArticleId
        name            = $Title
        content         = $Body
        organisationId  = $OrganizationId
        relatedEntities = @()
      },
      [ordered]@{
        id             = $ArticleId
        name           = $Title
        body           = $Body
        organizationId = $OrganizationId
      },
      [ordered]@{
        id             = $ArticleId
        name           = $Title
        body           = $Body
        organisationId = $OrganizationId
      },
      [ordered]@{
        id             = $ArticleId
        name           = $Title
        description    = $Body
        organizationId = $OrganizationId
      },
      [ordered]@{
        id             = $ArticleId
        name           = $Title
        description    = $Body
        organisationId = $OrganizationId
      }
    )
    if ($TargetFolder -and $TargetFolder.id) {
      foreach ($variant in $payloadVariants) {
        $variant.folderId = $TargetFolder.id
      }
    }

    $updatePaths = @()
    if (-not [string]::IsNullOrWhiteSpace($SourcePath)) {
      $updatePaths += "$SourcePath/$ArticleId"
    }
    $updatePaths += @(
      "/api/v2/knowledgebase/organization/articles/$ArticleId",
      "/api/v2/knowledgebase/global/articles/$ArticleId",
      "/api/v2/knowledgebase/articles/$ArticleId"
    )
    $updatePaths = $updatePaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    $lastError = $null
    foreach ($updatePath in $updatePaths) {
      $requestBodies = @($payloadVariants)
      if ($updatePath -notlike '/api/v2/knowledgebase/organization/articles/*') {
        foreach ($variant in $payloadVariants) {
          $requestBodies += ,@($variant)
        }
      }

      $methodOrder = @('PUT', 'PATCH')
      foreach ($updateMethod in $methodOrder) {
        for ($bodyIndex = 0; $bodyIndex -lt $requestBodies.Count; $bodyIndex++) {
          $requestBody = $requestBodies[$bodyIndex]
          try {
            Invoke-NinjaOneApi -Method $updateMethod -BaseUrl $BaseUrl -Path $updatePath -Headers $Headers -Body $requestBody | Out-Null
            Write-Info "KB update succeeded via $updateMethod $updatePath for '$Title'."
            return
          } catch {
            $lastError = $_
            $hasMoreBodies = $bodyIndex -lt $requestBodies.Count - 1

            if (Test-KbApiStatusCode -ErrorRecord $_ -StatusCode 400) {
              if ($hasMoreBodies) {
                continue
              }
              break
            }
            if ((Test-KbApiStatusCode -ErrorRecord $_ -StatusCode 404) -or
                (Test-KbApiStatusCode -ErrorRecord $_ -StatusCode 405)) {
              break
            }

            throw
          }
        }
      }
    }

    if ($lastError) {
      if ((Test-KbApiStatusCode -ErrorRecord $lastError -StatusCode 400) -or
          (Test-KbApiStatusCode -ErrorRecord $lastError -StatusCode 404) -or
          (Test-KbApiStatusCode -ErrorRecord $lastError -StatusCode 405)) {
        Write-Info "KB article '$Title' exists (id=$ArticleId) but could not be updated with available endpoints. Leaving existing article unchanged."
        return
      }
      throw $lastError
    }
    throw "KB update failed for article id '$ArticleId' with no explicit API error."
  }

  $folderResponse = Invoke-NinjaOneApi -Method 'GET' -BaseUrl $BaseUrl -Path '/api/v2/knowledgebase/folder' -Headers $Headers -Query @{} 
  $folders = @(Ensure-Array $folderResponse)
  $targetFolder = $folders | Where-Object { $_.name -eq 'Monthly Reports' } | Select-Object -First 1

  $articleQuery = @{
    articleName     = $Title
    organisationIds = $OrganizationId
  }
  $existingArticle = Find-ExistingKbArticle -Title $Title -OrganizationId $OrganizationId -Headers $Headers -BaseUrl $BaseUrl -PageSize $PageSize -MaxPages $MaxPages
  $payload = [ordered]@{
    name = $Title
    body = $Body
    organizationId = $OrganizationId
  }
  if ($targetFolder) { $payload.folderId = $targetFolder.id }
  $createPayloadVariants = @(
    [ordered]@{
      articleName     = $Title
      article         = $Body
      organizationId  = $OrganizationId
      relatedEntities = @()
    },
    [ordered]@{
      articleName     = $Title
      article         = $Body
      organisationId  = $OrganizationId
      relatedEntities = @()
    },
    [ordered]@{
      name            = $Title
      article         = $Body
      organizationId  = $OrganizationId
      relatedEntities = @()
    },
    [ordered]@{
      name            = $Title
      article         = $Body
      organisationId  = $OrganizationId
      relatedEntities = @()
    },
    [ordered]@{
      name            = $Title
      content         = $Body
      organizationId  = $OrganizationId
      relatedEntities = @()
    },
    [ordered]@{
      name            = $Title
      content         = $Body
      organisationId  = $OrganizationId
      relatedEntities = @()
    },
    [ordered]@{
      name           = $Title
      body           = $Body
      organizationId = $OrganizationId
    },
    [ordered]@{
      name           = $Title
      body           = $Body
      organisationId = $OrganizationId
    },
    [ordered]@{
      name           = $Title
      description    = $Body
      organizationId = $OrganizationId
    },
    [ordered]@{
      name           = $Title
      description    = $Body
      organisationId = $OrganizationId
    }
  )
  if ($targetFolder -and $targetFolder.id) {
    foreach ($variant in $createPayloadVariants) {
      $variant.folderId = $targetFolder.id
    }
  }

  if ($existingArticle -and $existingArticle.id) {
    $payload.id = $existingArticle.id
    if ($existingArticle.path) {
      Write-Info "Found existing KB article '$Title' (id=$($existingArticle.id)) via $($existingArticle.path)."
    }
    Write-Info "Skipping KB update for '$Title' because this tenant rejects article updates via public KB endpoints."
  } else {
    if ($PSCmdlet.ShouldProcess($Title, 'Create Knowledge Base article')) {
      $createTargets = @(
        @{ Method = 'POST'; Path = '/api/v2/knowledgebase/articles' },
        @{ Method = 'PUT';  Path = '/api/v2/knowledgebase/articles' },
        @{ Method = 'POST'; Path = '/api/v2/knowledgebase/organization/articles' },
        @{ Method = 'PUT';  Path = '/api/v2/knowledgebase/organization/articles' },
        @{ Method = 'POST'; Path = '/api/v2/knowledgebase/global/articles' },
        @{ Method = 'PUT';  Path = '/api/v2/knowledgebase/global/articles' }
      )

      $lastError = $null
      $created = $false
      $createdPath = $null
      $createdMethod = $null
      for ($i = 0; $i -lt $createTargets.Count; $i++) {
        $target = $createTargets[$i]
        $requestBodies = @($createPayloadVariants)
        if ($target.Path -eq '/api/v2/knowledgebase/articles') {
          $primaryArrayPayloads = @(
            @([ordered]@{
              articleName     = $Title
              article         = $Body
              organizationId  = $OrganizationId
              relatedEntities = @()
            }),
            @([ordered]@{
              articleName     = $Title
              article         = $Body
              organisationId  = $OrganizationId
              relatedEntities = @()
            }),
            @([ordered]@{
              name            = $Title
              article         = $Body
              organizationId  = $OrganizationId
              relatedEntities = @()
            }),
            @([ordered]@{
              name            = $Title
              article         = $Body
              organisationId  = $OrganizationId
              relatedEntities = @()
            })
          )
          if ($targetFolder -and $targetFolder.id) {
            foreach ($payloadArray in $primaryArrayPayloads) {
              if ($payloadArray.Count -gt 0) {
                $payloadArray[0].folderId = $targetFolder.id
              }
            }
          }
          $requestBodies = @($primaryArrayPayloads + $requestBodies)
        }
        if ($target.Path -notlike '/api/v2/knowledgebase/organization/articles*') {
          foreach ($variant in $createPayloadVariants) {
            $requestBodies += ,@($variant)
          }
        }

        $moveToNextEndpoint = $false
        for ($bodyIndex = 0; $bodyIndex -lt $requestBodies.Count; $bodyIndex++) {
          $requestBody = $requestBodies[$bodyIndex]
          try {
            Invoke-NinjaOneApi -Method $target.Method -BaseUrl $BaseUrl -Path $target.Path -Headers $Headers -Body $requestBody | Out-Null
            $lastError = $null
            $created = $true
            $createdPath = $target.Path
            $createdMethod = $target.Method
            break
          } catch {
            $lastError = $_
            $is405 = Test-KbApiStatusCode -ErrorRecord $_ -StatusCode 405
            $is400 = Test-KbApiStatusCode -ErrorRecord $_ -StatusCode 400
            $hasMoreBodies = $bodyIndex -lt $requestBodies.Count - 1

            if ($is400 -and $hasMoreBodies) {
              Write-Info "KB create $($target.Method) $($target.Path) returned 400 for payload variant $($bodyIndex + 1). Trying next payload shape."
              continue
            }
            if ($is400 -and $i -lt $createTargets.Count - 1) {
              Write-Info "KB create $($target.Method) $($target.Path) returned 400 for all tested payload variants. Trying next create endpoint."
              $moveToNextEndpoint = $true
              break
            }

            if ($is405 -and $i -lt $createTargets.Count - 1) {
              Write-Info "KB create $($target.Method) $($target.Path) returned 405. Trying next create endpoint."
              $moveToNextEndpoint = $true
              break
            }

            throw
          }
        }

        if ($created) { break }
        if ($moveToNextEndpoint) { continue }
      }

      if (-not $created -and $lastError) {
        throw $lastError
      }
      if (-not $created -and -not $lastError) {
        throw "KB create failed with no explicit API error."
      }

      if ($createdPath) {
        Write-Info "KB create succeeded via $createdMethod $createdPath for '$Title'."
      }

      if ($created -and $targetFolder -and $targetFolder.id -and $createdPath -eq '/api/v2/knowledgebase/articles') {
        $createdArticles = Invoke-NinjaOneApi -Method 'GET' -BaseUrl $BaseUrl -Path '/api/v2/knowledgebase/organization/articles' -Headers $Headers -Query $articleQuery
        $createdMatches = @(Ensure-Array $createdArticles)
        if ($createdMatches.Count -gt 0 -and $createdMatches[0].id) {
          $movePayload = [ordered]@{
            id             = $createdMatches[0].id
            name           = $Title
            body           = $Body
            organizationId = $OrganizationId
            folderId       = $targetFolder.id
          }
          try {
            Invoke-NinjaOneApi -Method 'PUT' -BaseUrl $BaseUrl -Path "/api/v2/knowledgebase/organization/articles/$($createdMatches[0].id)" -Headers $Headers -Body $movePayload | Out-Null
            Write-Info "KB article '$Title' assigned to folder '$($targetFolder.name)'."
          } catch {
            Write-Info "KB article '$Title' was created but could not be moved to folder '$($targetFolder.name)'."
          }
        } else {
          Write-Info "KB article '$Title' was created but could not be re-queried for folder assignment."
        }
      }
    }
  }
}

$allTitle = "Patch Operations Dashboard - All Organizations - $monthLabel"
$allMarkdown = Build-ReportMarkdown -Title $allTitle -MonthLabel $monthLabel -Metrics $metrics -TopOffenders $topOffenders -OsDetails $osDetails -SoftwareDetails $softwareDetails -Notes $notes -PatchKBSpotlight $PatchKBSpotlight

if ($WhatIfPreference) {
  $outputDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'samples'
  $path = Write-MarkdownReport -OutputDir $outputDir -FileName "PatchOperationsDashboard-AllOrgs-$($monthRange.Start.ToString('yyyy-MM')).md" -Content $allMarkdown
  Write-Info "Wrote WhatIf report: $path"
} else {
  Publish-KbArticle -Title $allTitle -Body $allMarkdown -OrganizationId 0 -MonthLabel $monthLabel -Headers $headers -BaseUrl $baseUrl -PageSize $PageSize -MaxPages $MaxPages
}

foreach ($org in $orgs) {
  $orgTitle = "Patch Operations Dashboard - $($org.name) - $monthLabel"

  $orgOsMissing = Filter-ItemsByOrg -Items $osMissing -OrganizationId $org.id
  $orgOsFailed = Filter-ItemsByOrg -Items $osFailed -OrganizationId $org.id
  $orgOsRejected = Filter-ItemsByOrg -Items $osRejected -OrganizationId $org.id
  $orgOsInstalled = Filter-ItemsByOrg -Items $osInstalled -OrganizationId $org.id
  $orgOsFailedInstalls = Filter-ItemsByOrg -Items $osFailedInstalls -OrganizationId $org.id

  $orgSoftwareMissing = Filter-ItemsByOrg -Items $softwareMissingFiltered -OrganizationId $org.id
  $orgSoftwareFailed = Filter-ItemsByOrg -Items $softwareFailedFiltered -OrganizationId $org.id
  $orgSoftwareRejected = Filter-ItemsByOrg -Items $softwareRejectedFiltered -OrganizationId $org.id
  $orgSoftwareInstalled = Filter-ItemsByOrg -Items $softwareInstalled -OrganizationId $org.id
  $orgSoftwareFailedInstalls = Filter-ItemsByOrg -Items $softwareFailedInstalls -OrganizationId $org.id

  $orgMetrics = Build-Metrics -OsMissingItems $orgOsMissing -OsFailedItems $orgOsFailed -OsRejectedItems $orgOsRejected -OsInstalledItems $orgOsInstalled -OsFailedInstallItems $orgOsFailedInstalls -SoftwareMissingItems $orgSoftwareMissing -SoftwareFailedItems $orgSoftwareFailed -SoftwareRejectedItems $orgSoftwareRejected -SoftwareInstalledItems $orgSoftwareInstalled -SoftwareFailedInstallItems $orgSoftwareFailedInstalls

  $orgOffenders = @{}
  foreach ($item in (Merge-Items $orgOsMissing $orgOsFailed $orgOsRejected $orgSoftwareMissing $orgSoftwareFailed $orgSoftwareRejected)) {
    $deviceId = Get-DeviceId $item
    if (-not $deviceId) { continue }
    if (-not $orgOffenders.ContainsKey($deviceId)) { $orgOffenders[$deviceId] = 0 }
    $orgOffenders[$deviceId]++
  }
  $orgTopOffenders = Build-Offenders -OffenderCounts $orgOffenders

  $orgOsSummary = @{}
  foreach ($item in (Merge-Items $orgOsMissing $orgOsRejected)) {
    $deviceId = Get-DeviceId $item
    if (-not $deviceId) { continue }
    if (-not $orgOsSummary.ContainsKey($deviceId)) { $orgOsSummary[$deviceId] = [ordered]@{ Missing = 0; Failed = 0 } }
    $orgOsSummary[$deviceId].Missing++
  }
  foreach ($item in $orgOsFailed) {
    $deviceId = Get-DeviceId $item
    if (-not $deviceId) { continue }
    if (-not $orgOsSummary.ContainsKey($deviceId)) { $orgOsSummary[$deviceId] = [ordered]@{ Missing = 0; Failed = 0 } }
    $orgOsSummary[$deviceId].Failed++
  }
  $orgOsDetails = $orgOsSummary.GetEnumerator() | Sort-Object { $_.Value.Missing + $_.Value.Failed } -Descending | Select-Object -First 10 | ForEach-Object {
    [pscustomobject]@{
      Name    = if ($deviceMap.ContainsKey($_.Key)) { $deviceMap[$_.Key] } else { $_.Key }
      Missing = $_.Value.Missing
      Failed  = $_.Value.Failed
    }
  }

  $orgSoftwareSummary = @{}
  foreach ($item in (Merge-Items $orgSoftwareMissing $orgSoftwareRejected)) {
    $deviceId = Get-DeviceId $item
    if (-not $deviceId) { continue }
    if (-not $orgSoftwareSummary.ContainsKey($deviceId)) { $orgSoftwareSummary[$deviceId] = [ordered]@{ Missing = 0; Failed = 0 } }
    $orgSoftwareSummary[$deviceId].Missing++
  }
  foreach ($item in $orgSoftwareFailed) {
    $deviceId = Get-DeviceId $item
    if (-not $deviceId) { continue }
    if (-not $orgSoftwareSummary.ContainsKey($deviceId)) { $orgSoftwareSummary[$deviceId] = [ordered]@{ Missing = 0; Failed = 0 } }
    $orgSoftwareSummary[$deviceId].Failed++
  }
  $orgSoftwareDetails = $orgSoftwareSummary.GetEnumerator() | Sort-Object { $_.Value.Missing + $_.Value.Failed } -Descending | Select-Object -First 10 | ForEach-Object {
    [pscustomobject]@{
      Name    = if ($deviceMap.ContainsKey($_.Key)) { $deviceMap[$_.Key] } else { $_.Key }
      Missing = $_.Value.Missing
      Failed  = $_.Value.Failed
    }
  }

  $orgMarkdown = Build-ReportMarkdown -Title $orgTitle -MonthLabel $monthLabel -Metrics $orgMetrics -TopOffenders $orgTopOffenders -OsDetails $orgOsDetails -SoftwareDetails $orgSoftwareDetails -Notes $notes -PatchKBSpotlight $PatchKBSpotlight
  if ($WhatIfPreference) {
    $outputDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'samples'
    $safeName = ($org.name -replace '[^a-zA-Z0-9-_]','_')
    $path = Write-MarkdownReport -OutputDir $outputDir -FileName "PatchOperationsDashboard-$safeName-$($monthRange.Start.ToString('yyyy-MM')).md" -Content $orgMarkdown
    Write-Info "Wrote WhatIf report: $path"
  } else {
    Publish-KbArticle -Title $orgTitle -Body $orgMarkdown -OrganizationId $org.id -MonthLabel $monthLabel -Headers $headers -BaseUrl $baseUrl -PageSize $PageSize -MaxPages $MaxPages
  }
}

Write-Info "Done."
}

Invoke-PatchOperationsDashboard @args
