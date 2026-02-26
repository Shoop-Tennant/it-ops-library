#!/usr/bin/env pwsh

<#
.SYNOPSIS
  Export NinjaOne API data needed for SCCM-vs-NinjaOne migration analysis.
.DESCRIPTION
  Pulls endpoint, OS patch, 3rd-party patch, and vulnerability data from NinjaOne API,
  then writes raw CSV artifacts under samples/raw for downstream correlation/reporting.
.NOTES
  - Uses OAuth Authorization Code + Refresh Token.
  - Never logs client secret or token values.
  - Intended to produce raw inputs; sanitization happens in later pipeline steps.
#>

[CmdletBinding()]
param(
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
  [string]$OutputDir,

  [Parameter()]
  [int]$PageSize = 1000,

  [Parameter()]
  [int]$MaxPages = 200,

  [Parameter()]
  [switch]$NoBrowser,

  [Parameter()]
  [switch]$IncludeRawEventExports
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info {
  param([string]$Message)
  Write-Host "[NinjaExport] $Message"
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

function Get-DefaultTokenPath {
  if ($IsWindows) {
    return Join-Path $env:ProgramData 'NinjaOne\PatchOpsDashboard\tokens.json'
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
  $payload | ConvertTo-Json -Depth 6 | Set-Content -Path $Path -Encoding UTF8
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
      Write-Info "Opened browser for OAuth authorization."
    } else {
      Write-Info "Open this URL to authorize: $AuthorizeUrl"
    }

    Write-Info "Waiting for OAuth redirect on $($listenerInfo.Prefix)"
    while ($true) {
      $context = $listenerInfo.Listener.GetContext()
      $request = $context.Request
      $response = $context.Response

      $code = $request.QueryString['code']
      $state = $request.QueryString['state']
      $error = $request.QueryString['error']

      if ($error) {
        $message = "Authorization failed: $error"
        $buffer = [Text.Encoding]::UTF8.GetBytes($message)
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.OutputStream.Close()
        throw $message
      }

      if ($ExpectedState -and $state -and $state -ne $ExpectedState) {
        $message = "State mismatch. Retry from the original authorization flow."
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

      $ok = "Authorization complete. You may close this window."
      $okBytes = [Text.Encoding]::UTF8.GetBytes($ok)
      $response.ContentLength64 = $okBytes.Length
      $response.OutputStream.Write($okBytes, 0, $okBytes.Length)
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
    Write-Info "Refreshing OAuth access token."
    $refresh = Request-Token -TokenUrl $oauth.Token -Body @{
      grant_type    = 'refresh_token'
      refresh_token = $tokens.refresh_token
      client_id     = $ClientId
      client_secret = $ClientSecret
    }
    $updated = @{
      access_token  = $refresh.access_token
      refresh_token = $refresh.refresh_token
      token_type    = $refresh.token_type
      scope         = $refresh.scope
      expires_at    = [DateTimeOffset]::UtcNow.AddSeconds($refresh.expires_in).ToString('o')
    }
    Save-Tokens -Path $TokenPath -Tokens $updated
    return $updated
  }

  Write-Info "Starting first-run OAuth flow."
  $state = [Guid]::NewGuid().ToString('N')
  $authorizeUrl = "$($oauth.Authorize)?response_type=code&client_id=$ClientId&redirect_uri=$([Uri]::EscapeDataString($RedirectUri))&scope=$([Uri]::EscapeDataString($Scope))&state=$state"
  $authResult = Get-AuthorizationCode -AuthorizeUrl $authorizeUrl -RedirectUri $RedirectUri -ExpectedState $state -NoBrowser:$NoBrowser

  if ($authResult.State -and $authResult.State -ne $state) {
    throw "OAuth state mismatch."
  }

  $token = Request-Token -TokenUrl $oauth.Token -Body @{
    grant_type    = 'authorization_code'
    code          = $authResult.Code
    redirect_uri  = $RedirectUri
    client_id     = $ClientId
    client_secret = $ClientSecret
  }

  $saved = @{
    access_token  = $token.access_token
    refresh_token = $token.refresh_token
    token_type    = $token.token_type
    scope         = $token.scope
    expires_at    = [DateTimeOffset]::UtcNow.AddSeconds($token.expires_in).ToString('o')
  }
  Save-Tokens -Path $TokenPath -Tokens $saved
  return $saved
}

function Ensure-Array {
  param($Value)
  if ($null -eq $Value) { return @() }
  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) { return @($Value) }
  return @($Value)
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
      if ($null -eq $Query[$key] -or $Query[$key] -eq '') { continue }
      $pairs += "{0}={1}" -f $key, [Uri]::EscapeDataString([string]$Query[$key])
    }
    $uriBuilder.Query = [string]::Join('&', $pairs)
  }
  return $uriBuilder.Uri.AbsoluteUri
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
  Write-Info "API $Method $Path"
  return Invoke-RestMethod @params
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

function Try-NinjaOnePagedQuery {
  param(
    [string]$BaseUrl,
    [string]$Path,
    [hashtable]$Headers,
    [hashtable]$Query,
    [int]$PageSize,
    [int]$MaxPages
  )
  try {
    $results = @(Invoke-NinjaOnePagedQuery -BaseUrl $BaseUrl -Path $Path -Headers $Headers -Query $Query -PageSize $PageSize -MaxPages $MaxPages)
    return @{
      Success = $true
      Results = $results
      Error   = $null
    }
  } catch {
    return @{
      Success = $false
      Results = @()
      Error   = $_.Exception.Message
    }
  }
}

function Get-Value {
  param(
    [object]$InputObject,
    [string[]]$Names
  )
  if ($null -eq $InputObject) { return $null }

  foreach ($name in $Names) {
    if ([string]::IsNullOrWhiteSpace($name)) { continue }
    if ($InputObject -is [System.Collections.IDictionary]) {
      if ($InputObject.Contains($name)) { return $InputObject[$name] }
      continue
    }
    if ($InputObject.PSObject -and $InputObject.PSObject.Properties) {
      $prop = $InputObject.PSObject.Properties[$name]
      if ($null -ne $prop) { return $prop.Value }
    }
  }
  return $null
}

function Get-DeviceId {
  param([object]$Item)
  $candidate = Get-Value -InputObject $Item -Names @('deviceId', 'nodeId', 'device_id', 'id')
  if ($candidate) { return [string]$candidate }
  $deviceObj = Get-Value -InputObject $Item -Names @('device')
  if ($deviceObj) {
    $nested = Get-Value -InputObject $deviceObj -Names @('id', 'deviceId', 'nodeId')
    if ($nested) { return [string]$nested }
  }
  return $null
}

function Get-DeviceName {
  param([object]$Device)
  $name = Get-Value -InputObject $Device -Names @('systemName', 'name', 'hostname', 'deviceName')
  if ($name) { return [string]$name }
  return $null
}

function Convert-ToNullableInt {
  param([object]$Value)
  if ($null -eq $Value) { return $null }
  $text = [string]$Value
  if ([string]::IsNullOrWhiteSpace($text)) { return $null }
  try { return [int]$text } catch { return $null }
}

function Get-OrCreateMetricRecord {
  param(
    [hashtable]$MetricMap,
    [string]$DeviceId,
    [string]$DeviceName,
    [string]$OrganizationId,
    [object]$PatchingEnabled
  )
  if (-not $MetricMap.ContainsKey($DeviceId)) {
    $MetricMap[$DeviceId] = [ordered]@{
      DeviceId                    = $DeviceId
      NinjaDeviceName             = $DeviceName
      OrganizationId              = $OrganizationId
      PatchingEnabled             = ''
      OsPendingCount              = 0
      OsFailedCount               = 0
      OsRejectedCount             = 0
      OsInstalledCount            = 0
      OsFailedInstallCount        = 0
      SoftwarePendingCount        = 0
      SoftwareFailedCount         = 0
      SoftwareRejectedCount       = 0
      SoftwareInstalledCount      = 0
      SoftwareFailedInstallCount  = 0
      MissingCount                = 0
      FailedCount                 = 0
      InstalledCount              = 0
      CompliancePct               = ''
    }
  }

  if ($DeviceName) { $MetricMap[$DeviceId].NinjaDeviceName = $DeviceName }
  if ($OrganizationId) { $MetricMap[$DeviceId].OrganizationId = $OrganizationId }
  if ($null -ne $PatchingEnabled -and $PatchingEnabled -ne '') {
    if ($PatchingEnabled -is [bool]) {
      $MetricMap[$DeviceId].PatchingEnabled = if ($PatchingEnabled) { 'true' } else { 'false' }
    } else {
      $text = [string]$PatchingEnabled
      if ($text -match '^(true|false)$') {
        $MetricMap[$DeviceId].PatchingEnabled = $text.ToLowerInvariant()
      }
    }
  }

  return $MetricMap[$DeviceId]
}

function Add-StatusCounts {
  param(
    [hashtable]$MetricMap,
    [object[]]$Records,
    [hashtable]$DeviceNameMap,
    [hashtable]$OrgMap,
    [string]$MetricKey
  )
  foreach ($item in (Ensure-Array $Records)) {
    $deviceId = Get-DeviceId $item
    if (-not $deviceId) { continue }
    $name = if ($DeviceNameMap.ContainsKey($deviceId)) { $DeviceNameMap[$deviceId] } else { $null }
    $org = if ($OrgMap.ContainsKey($deviceId)) { $OrgMap[$deviceId] } else { $null }
    $record = Get-OrCreateMetricRecord -MetricMap $MetricMap -DeviceId $deviceId -DeviceName $name -OrganizationId $org -PatchingEnabled $null
    $record[$MetricKey]++
  }
}

function Get-EndpointVulnerabilityRows {
  param(
    [string]$BaseUrl,
    [hashtable]$Headers,
    [int]$PageSize,
    [int]$MaxPages
  )
  $candidates = @(
    @{ Path = '/api/v2/queries/vulnerabilities'; Query = @{ status = 'ACTIVE' } },
    @{ Path = '/api/v2/queries/vulnerability-findings'; Query = @{ status = 'ACTIVE' } },
    @{ Path = '/api/v2/queries/cves'; Query = @{ status = 'ACTIVE' } },
    @{ Path = '/api/v2/vulnerabilities'; Query = @{} }
  )

  foreach ($candidate in $candidates) {
    $result = Try-NinjaOnePagedQuery -BaseUrl $BaseUrl -Path $candidate.Path -Headers $Headers -Query $candidate.Query -PageSize $PageSize -MaxPages $MaxPages
    if (-not $result.Success) {
      Write-Info "Vulnerability query not available: $($candidate.Path) ($($result.Error))"
      continue
    }
    if ($result.Results.Count -eq 0) {
      Write-Info "Vulnerability query returned 0 rows: $($candidate.Path)"
      continue
    }
    Write-Info "Vulnerability query succeeded: $($candidate.Path) ($($result.Results.Count) rows)"
    return @{
      Path    = $candidate.Path
      Records = @(Ensure-Array $result.Results)
    }
  }

  return @{
    Path    = ''
    Records = @()
  }
}

function To-BoolText {
  param([object]$Value)
  if ($null -eq $Value) { return '' }
  if ($Value -is [bool]) { return if ($Value) { 'true' } else { 'false' } }
  $text = [string]$Value
  if ($text -match '^(true|false)$') { return $text.ToLowerInvariant() }
  return ''
}

$repoRoot = $null
try {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..') -ErrorAction Stop).Path
} catch {
  $repoRoot = $null
}

$defaultRawDir = if ($repoRoot) {
  Join-Path $repoRoot 'ninjaone/patching/dashboard/samples/raw'
} else {
  Join-Path $PSScriptRoot 'samples/raw'
}
$OutputDir = if ($OutputDir) { $OutputDir } else { $defaultRawDir }
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

$ClientId = Resolve-ConfigValue -Value $ClientId -EnvNames @('ninjaoneClientId', 'NINJAONECLIENTID', 'NINJAONE_CLIENT_ID')
$ClientSecret = Resolve-ConfigValue -Value $ClientSecret -EnvNames @('ninjaoneClientSecret', 'NINJAONECLIENTSECRET', 'NINJAONE_CLIENT_SECRET')
$Instance = Resolve-ConfigValue -Value $Instance -EnvNames @('ninjaoneInstance', 'NINJAONEINSTANCE', 'NINJAONE_INSTANCE')
$TokenPath = if ($TokenPath) { $TokenPath } else { Get-DefaultTokenPath }

if (-not $ClientId -or -not $ClientSecret -or -not $Instance) {
  throw "Missing NinjaOne auth configuration. Provide ClientId/ClientSecret/Instance or set env/custom fields."
}

Write-Info "Collecting NinjaOne API data from instance: $Instance"
$tokens = Get-AccessToken -InstanceHost $Instance -ClientId $ClientId -ClientSecret $ClientSecret -RedirectUri $RedirectUri -Scope $Scope -TokenPath $TokenPath -NoBrowser:$NoBrowser
$headers = @{ Authorization = "Bearer $($tokens.access_token)" }
$baseUrl = "https://$Instance"

$devices = @(Invoke-NinjaOnePagedQuery -BaseUrl $baseUrl -Path '/api/v2/devices' -Headers $headers -Query @{} -PageSize $PageSize -MaxPages $MaxPages)
Write-Info "Fetched devices: $($devices.Count)"

$deviceNameMap = @{}
$deviceOrgMap = @{}
$devicePatchEnabledMap = @{}
$deviceRows = @()

foreach ($device in $devices) {
  $id = [string](Get-Value -InputObject $device -Names @('id', 'deviceId', 'nodeId'))
  if (-not $id) { continue }
  $name = Get-DeviceName -Device $device
  $orgId = [string](Get-Value -InputObject $device -Names @('organizationId', 'organizationID', 'orgId'))
  $patchEnabled = Get-Value -InputObject $device -Names @('patchManagementEnabled', 'patchingEnabled', 'osPatchingEnabled')

  if ($name) { $deviceNameMap[$id] = $name }
  if ($orgId) { $deviceOrgMap[$id] = $orgId }
  $patchBool = To-BoolText -Value $patchEnabled
  if ($patchBool) { $devicePatchEnabledMap[$id] = $patchBool }

  $deviceRows += [pscustomobject]@{
    DeviceId           = $id
    NinjaDeviceName    = $name
    OrganizationId     = $orgId
    PatchingEnabled    = $patchBool
    DeviceType         = [string](Get-Value -InputObject $device -Names @('deviceType', 'type'))
    OperatingSystem    = [string](Get-Value -InputObject $device -Names @('operatingSystem', 'os', 'osName'))
    LastSeen           = [string](Get-Value -InputObject $device -Names @('lastSeen', 'lastContact'))
  }
}

Write-Info "Collecting patch query datasets."
$osPending = @(Invoke-NinjaOnePagedQuery -BaseUrl $baseUrl -Path '/api/v2/queries/os-patches' -Headers $headers -Query @{ status = 'PENDING' } -PageSize $PageSize -MaxPages $MaxPages)
$osFailed = @(Invoke-NinjaOnePagedQuery -BaseUrl $baseUrl -Path '/api/v2/queries/os-patches' -Headers $headers -Query @{ status = 'FAILED' } -PageSize $PageSize -MaxPages $MaxPages)
$osRejected = @(Invoke-NinjaOnePagedQuery -BaseUrl $baseUrl -Path '/api/v2/queries/os-patches' -Headers $headers -Query @{ status = 'REJECTED' } -PageSize $PageSize -MaxPages $MaxPages)
$osInstalled = @(Invoke-NinjaOnePagedQuery -BaseUrl $baseUrl -Path '/api/v2/queries/os-patch-installs' -Headers $headers -Query @{ status = 'INSTALLED' } -PageSize $PageSize -MaxPages $MaxPages)
$osFailedInstalls = @(Invoke-NinjaOnePagedQuery -BaseUrl $baseUrl -Path '/api/v2/queries/os-patch-installs' -Headers $headers -Query @{ status = 'FAILED' } -PageSize $PageSize -MaxPages $MaxPages)

$softwarePending = @(Invoke-NinjaOnePagedQuery -BaseUrl $baseUrl -Path '/api/v2/queries/software-patches' -Headers $headers -Query @{ status = 'PENDING' } -PageSize $PageSize -MaxPages $MaxPages)
$softwareFailed = @(Invoke-NinjaOnePagedQuery -BaseUrl $baseUrl -Path '/api/v2/queries/software-patches' -Headers $headers -Query @{ status = 'FAILED' } -PageSize $PageSize -MaxPages $MaxPages)
$softwareRejected = @(Invoke-NinjaOnePagedQuery -BaseUrl $baseUrl -Path '/api/v2/queries/software-patches' -Headers $headers -Query @{ status = 'REJECTED' } -PageSize $PageSize -MaxPages $MaxPages)
$softwareInstalled = @(Invoke-NinjaOnePagedQuery -BaseUrl $baseUrl -Path '/api/v2/queries/software-patch-installs' -Headers $headers -Query @{ status = 'INSTALLED' } -PageSize $PageSize -MaxPages $MaxPages)
$softwareFailedInstalls = @(Invoke-NinjaOnePagedQuery -BaseUrl $baseUrl -Path '/api/v2/queries/software-patch-installs' -Headers $headers -Query @{ status = 'FAILED' } -PageSize $PageSize -MaxPages $MaxPages)

$metricMap = @{}
foreach ($device in $deviceRows) {
  $baseRecord = Get-OrCreateMetricRecord -MetricMap $metricMap -DeviceId $device.DeviceId -DeviceName $device.NinjaDeviceName -OrganizationId $device.OrganizationId -PatchingEnabled ($device.PatchingEnabled)
  if (-not $baseRecord.PatchingEnabled -and $devicePatchEnabledMap.ContainsKey($device.DeviceId)) {
    $baseRecord.PatchingEnabled = $devicePatchEnabledMap[$device.DeviceId]
  }
}

Add-StatusCounts -MetricMap $metricMap -Records $osPending -DeviceNameMap $deviceNameMap -OrgMap $deviceOrgMap -MetricKey 'OsPendingCount'
Add-StatusCounts -MetricMap $metricMap -Records $osFailed -DeviceNameMap $deviceNameMap -OrgMap $deviceOrgMap -MetricKey 'OsFailedCount'
Add-StatusCounts -MetricMap $metricMap -Records $osRejected -DeviceNameMap $deviceNameMap -OrgMap $deviceOrgMap -MetricKey 'OsRejectedCount'
Add-StatusCounts -MetricMap $metricMap -Records $osInstalled -DeviceNameMap $deviceNameMap -OrgMap $deviceOrgMap -MetricKey 'OsInstalledCount'
Add-StatusCounts -MetricMap $metricMap -Records $osFailedInstalls -DeviceNameMap $deviceNameMap -OrgMap $deviceOrgMap -MetricKey 'OsFailedInstallCount'

Add-StatusCounts -MetricMap $metricMap -Records $softwarePending -DeviceNameMap $deviceNameMap -OrgMap $deviceOrgMap -MetricKey 'SoftwarePendingCount'
Add-StatusCounts -MetricMap $metricMap -Records $softwareFailed -DeviceNameMap $deviceNameMap -OrgMap $deviceOrgMap -MetricKey 'SoftwareFailedCount'
Add-StatusCounts -MetricMap $metricMap -Records $softwareRejected -DeviceNameMap $deviceNameMap -OrgMap $deviceOrgMap -MetricKey 'SoftwareRejectedCount'
Add-StatusCounts -MetricMap $metricMap -Records $softwareInstalled -DeviceNameMap $deviceNameMap -OrgMap $deviceOrgMap -MetricKey 'SoftwareInstalledCount'
Add-StatusCounts -MetricMap $metricMap -Records $softwareFailedInstalls -DeviceNameMap $deviceNameMap -OrgMap $deviceOrgMap -MetricKey 'SoftwareFailedInstallCount'

$patchRows = @()
foreach ($entry in $metricMap.GetEnumerator()) {
  $row = $entry.Value
  $row.MissingCount = $row.OsPendingCount + $row.OsFailedCount + $row.OsRejectedCount + $row.SoftwarePendingCount + $row.SoftwareFailedCount + $row.SoftwareRejectedCount
  $row.FailedCount = $row.OsFailedCount + $row.OsFailedInstallCount + $row.SoftwareFailedCount + $row.SoftwareFailedInstallCount
  $row.InstalledCount = $row.OsInstalledCount + $row.SoftwareInstalledCount

  $denominator = $row.MissingCount + $row.InstalledCount
  if ($denominator -gt 0) {
    $row.CompliancePct = [Math]::Round(($row.InstalledCount / $denominator) * 100, 2)
    if (-not $row.PatchingEnabled) { $row.PatchingEnabled = 'true' }
  } elseif (-not $row.PatchingEnabled) {
    $row.PatchingEnabled = ''
  }

  $patchRows += [pscustomobject]$row
}

Write-Info "Collecting vulnerability data (best effort)."
$vulnResult = Get-EndpointVulnerabilityRows -BaseUrl $baseUrl -Headers $headers -PageSize $PageSize -MaxPages $MaxPages
$vulnRecords = @(Ensure-Array $vulnResult.Records)

$vulnNormalized = @()
foreach ($item in $vulnRecords) {
  $deviceId = Get-DeviceId $item
  $deviceName = if ($deviceId -and $deviceNameMap.ContainsKey($deviceId)) { $deviceNameMap[$deviceId] } else { '' }
  $severity = [string](Get-Value -InputObject $item -Names @('severity', 'riskSeverity', 'severityLevel'))
  $cve = [string](Get-Value -InputObject $item -Names @('cve', 'cveId', 'vulnerabilityId', 'id'))
  $status = [string](Get-Value -InputObject $item -Names @('status', 'state'))
  $score = [string](Get-Value -InputObject $item -Names @('score', 'riskScore', 'cvssScore'))

  $vulnNormalized += [pscustomobject]@{
    DeviceId        = $deviceId
    NinjaDeviceName = $deviceName
    Severity        = $severity
    VulnerabilityId = $cve
    Status          = $status
    Score           = $score
    SourcePath      = $vulnResult.Path
  }
}

$stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$devicesFile = "ninjaone_devices_$stamp.csv"
$patchFile = "ninjaone_patching_by_device_$stamp.csv"
$vulnFile = "ninjaone_vulnerabilities_$stamp.csv"
$summaryFile = "ninjaone_api_pull_summary_$stamp.json"
$crosswalkTemplateFile = "endpoint_crosswalk.template_$stamp.csv"
$manifestFile = "manifest.ninjaone_api_$stamp.yml"

$devicesPath = Join-Path $OutputDir $devicesFile
$patchPath = Join-Path $OutputDir $patchFile
$vulnPath = Join-Path $OutputDir $vulnFile
$summaryPath = Join-Path $OutputDir $summaryFile
$crosswalkTemplatePath = Join-Path $OutputDir $crosswalkTemplateFile
$manifestPath = Join-Path $OutputDir $manifestFile

$deviceRows | Sort-Object NinjaDeviceName | Export-Csv -Path $devicesPath -NoTypeInformation -Encoding UTF8
$patchRows | Sort-Object NinjaDeviceName | Export-Csv -Path $patchPath -NoTypeInformation -Encoding UTF8
$vulnNormalized | Export-Csv -Path $vulnPath -NoTypeInformation -Encoding UTF8

$crosswalkRows = $patchRows | Sort-Object NinjaDeviceName | ForEach-Object {
  [pscustomobject]@{
    AssetName       = ''
    NinjaDeviceName = $_.NinjaDeviceName
  }
}
$crosswalkRows | Export-Csv -Path $crosswalkTemplatePath -NoTypeInformation -Encoding UTF8

if ($IncludeRawEventExports) {
  $rawOsPath = Join-Path $OutputDir "ninjaone_os_patch_events_$stamp.json"
  $rawSoftwarePath = Join-Path $OutputDir "ninjaone_software_patch_events_$stamp.json"
  $rawPayload = [ordered]@{
    osPending           = $osPending
    osFailed            = $osFailed
    osRejected          = $osRejected
    osInstalled         = $osInstalled
    osFailedInstalls    = $osFailedInstalls
  }
  $rawPayload | ConvertTo-Json -Depth 8 | Set-Content -Path $rawOsPath -Encoding UTF8

  $rawSoftware = [ordered]@{
    softwarePending        = $softwarePending
    softwareFailed         = $softwareFailed
    softwareRejected       = $softwareRejected
    softwareInstalled      = $softwareInstalled
    softwareFailedInstalls = $softwareFailedInstalls
  }
  $rawSoftware | ConvertTo-Json -Depth 8 | Set-Content -Path $rawSoftwarePath -Encoding UTF8
  Write-Info "Wrote raw patch event JSON exports."
}

$summary = [ordered]@{
  instance                          = $Instance
  generatedAtUtc                    = [DateTimeOffset]::UtcNow.ToString('o')
  files                             = @{
    devicesCsv            = $devicesFile
    patchingByDeviceCsv   = $patchFile
    vulnerabilitiesCsv    = $vulnFile
    crosswalkTemplateCsv  = $crosswalkTemplateFile
    generatedManifestYml  = $manifestFile
  }
  counts = @{
    devices                       = $deviceRows.Count
    patchingDeviceRows            = $patchRows.Count
    vulnerabilityRows             = $vulnNormalized.Count
    osPendingRows                 = $osPending.Count
    osFailedRows                  = $osFailed.Count
    osRejectedRows                = $osRejected.Count
    softwarePendingRows           = $softwarePending.Count
    softwareFailedRows            = $softwareFailed.Count
    softwareRejectedRows          = $softwareRejected.Count
  }
  vulnerabilityQueryPathUsed        = $vulnResult.Path
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -Path $summaryPath -Encoding UTF8

$manifestText = @"
run_name: "NinjaOne API Pull ($stamp)"

inputs:
  ninjaone_devices:
    path: "$devicesFile"

  ninjaone_patching_by_device:
    path: "$patchFile"

  ninjaone_vulnerabilities:
    path: "$vulnFile"

  endpoint_crosswalk_template:
    path: "$crosswalkTemplateFile"
"@
$manifestText | Set-Content -Path $manifestPath -Encoding UTF8

Write-Info "Wrote: $devicesPath"
Write-Info "Wrote: $patchPath"
Write-Info "Wrote: $vulnPath"
Write-Info "Wrote: $crosswalkTemplatePath"
Write-Info "Wrote: $manifestPath"
Write-Info "Wrote: $summaryPath"
Write-Info "Done."
