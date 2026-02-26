#!/usr/bin/env pwsh
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$ClientId,

  [Parameter(Mandatory = $true)]
  [string]$ClientSecret,

  [Parameter()]
  [string]$Instance = 'us2.ninjarmm.com',

  [Parameter()]
  [string]$TokenPath = 'C:\ProgramData\NinjaOne\PatchOpsDashboard\tokens.json',

  [Parameter()]
  [string]$TitlePrefix = 'Patch Operations Dashboard',

  [Parameter()]
  [int]$PageSize = 200,

  [Parameter()]
  [string]$RedirectUri,

  [Parameter()]
  [switch]$NoBrowser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

function Load-Tokens {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Token file not found: $Path"
  }
  $raw = Get-Content -Path $Path -Raw | ConvertFrom-Json
  return @{
    access_token  = Unprotect-Secret $raw.access_token
    refresh_token = Unprotect-Secret $raw.refresh_token
    token_type    = $raw.token_type
    scope         = $raw.scope
    expires_at    = $raw.expires_at
  }
}

function Save-Tokens {
  param(
    [string]$Path,
    [hashtable]$Tokens
  )
  $folder = Split-Path -Parent $Path
  if ($folder -and -not (Test-Path -LiteralPath $folder)) {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
  }
  $payload = [ordered]@{
    access_token  = Protect-Secret $Tokens.access_token
    refresh_token = Protect-Secret $Tokens.refresh_token
    token_type    = $Tokens.token_type
    scope         = $Tokens.scope
    expires_at    = $Tokens.expires_at
  }
  $payload | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
}

function Get-NinjaOneApiUrl {
  param(
    [string]$BaseUrl,
    [string]$Path,
    [hashtable]$Query
  )
  $builder = [System.UriBuilder]::new("$BaseUrl$Path")
  if ($Query -and $Query.Count -gt 0) {
    $pairs = foreach ($key in $Query.Keys) {
      if ($null -ne $Query[$key] -and $Query[$key] -ne '') {
        '{0}={1}' -f $key, [uri]::EscapeDataString([string]$Query[$key])
      }
    }
    $builder.Query = [string]::Join('&', $pairs)
  }
  return $builder.Uri.AbsoluteUri
}

function Get-HttpStatusCode {
  param([System.Management.Automation.ErrorRecord]$ErrorRecord)
  try {
    if ($ErrorRecord.Exception -and $ErrorRecord.Exception.Response -and $ErrorRecord.Exception.Response.StatusCode) {
      return [int]$ErrorRecord.Exception.Response.StatusCode
    }
  } catch { }

  $text = $null
  if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
    $text = [string]$ErrorRecord.ErrorDetails.Message
  } elseif ($ErrorRecord.Exception -and $ErrorRecord.Exception.Message) {
    $text = [string]$ErrorRecord.Exception.Message
  }

  if ($text) {
    if ($text -match '\bHTTP\s+(\d{3})\b') { return [int]$Matches[1] }
    if ($text -match '"status"\s*:\s*(\d{3})') { return [int]$Matches[1] }
  }
  return $null
}

function Get-ObjectPropertyValue {
  param(
    [object]$InputObject,
    [string[]]$Names
  )
  if ($null -eq $InputObject -or -not $Names) {
    return $null
  }

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

function Invoke-NinjaOneGetPaged {
  param(
    [string]$BaseUrl,
    [string]$Path,
    [hashtable]$Headers,
    [int]$PageSize = 200,
    [hashtable]$Query
  )
  $all = @()
  $cursor = $null
  $seen = @{}

  for ($page = 1; $page -le 200; $page++) {
    $query = @{}
    if ($Query) {
      foreach ($key in $Query.Keys) {
        $query[$key] = $Query[$key]
      }
    }
    if (-not $query.ContainsKey('pageSize')) {
      $query.pageSize = $PageSize
    }
    if ($cursor) { $query.cursor = $cursor }
    $uri = Get-NinjaOneApiUrl -BaseUrl $BaseUrl -Path $Path -Query $query

    $resp = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers
    if ($null -eq $resp) { break }

    $itemsFromEnvelope = $null
    if ($resp.PSObject -and $resp.PSObject.Properties) {
      foreach ($collectionName in @('results', 'items', 'data', 'articles')) {
        $collectionProp = $resp.PSObject.Properties[$collectionName]
        if ($null -eq $collectionProp) { continue }

        $collectionValue = $collectionProp.Value
        if ($null -eq $collectionValue) { continue }
        if ($collectionValue -is [string]) { continue }
        if ($collectionValue -is [System.Collections.IDictionary]) { continue }
        if ($collectionValue -isnot [System.Collections.IEnumerable]) { continue }

        $itemsFromEnvelope = @($collectionValue)
        break
      }
    }

    if ($null -ne $itemsFromEnvelope) {
      $items = @($itemsFromEnvelope)
      $all += $items
      if ($items.Count -lt $PageSize) { break }

      $nextCursor = $null
      if ($resp.PSObject.Properties.Name -contains 'cursor' -and $resp.cursor) {
        if ($resp.cursor -is [string]) {
          $nextCursor = [string]$resp.cursor
        } elseif ($resp.cursor.PSObject.Properties.Name -contains 'name' -and $resp.cursor.name) {
          $nextCursor = [string]$resp.cursor.name
        }
      }
      if (-not $nextCursor) { break }
      if ($seen.ContainsKey($nextCursor)) { break }
      $seen[$nextCursor] = $true
      $cursor = $nextCursor
      continue
    }

    if ($resp -is [System.Collections.IEnumerable] -and -not ($resp -is [string])) {
      $items = @($resp)
      $all += $items
      if ($items.Count -lt $PageSize) { break }
      continue
    }

    # Some endpoints may return a single object instead of an array.
    $all += @($resp)
    break
  }

  return $all
}

function Invoke-KbOrganizationArticleFallback {
  param(
    [string]$BaseUrl,
    [hashtable]$Headers,
    [int]$PageSize
  )
  $organizations = @()
  try {
    $organizations = @(Invoke-NinjaOneGetPaged -BaseUrl $BaseUrl -Path '/api/v2/organizations' -Headers $Headers -PageSize $PageSize)
  } catch {
    $status = Get-HttpStatusCode -ErrorRecord $_
    if ($status -eq 405) {
      Write-Host "Endpoint not supported for this tenant: GET /api/v2/organizations (405)."
      return @()
    }
    throw
  }

  if ($organizations.Count -eq 0) {
    return @()
  }

  Write-Host "Fallback: organization article list was empty; querying per organization ($($organizations.Count) orgs)."
  $all = @()

  foreach ($org in $organizations) {
    if (-not $org.id) { continue }
    $orgLabel = if ($org.name) { "$($org.name) [$($org.id)]" } else { "Org [$($org.id)]" }

    $queryVariants = @(
      @{ organisationIds = $org.id },
      @{ organizationIds = $org.id },
      @{ organisationId = $org.id },
      @{ organizationId = $org.id }
    )

    $queryAttempted = $false
    $statusMessages = @()
    foreach ($query in $queryVariants) {
      $queryName = @($query.Keys)[0]
      try {
        $items = @(Invoke-NinjaOneGetPaged -BaseUrl $BaseUrl -Path '/api/v2/knowledgebase/organization/articles' -Headers $Headers -PageSize $PageSize -Query $query)
        $all += $items
        $queryAttempted = $true
        Write-Host "Fallback org $orgLabel using '$queryName': $($items.Count) articles."
        break
      } catch {
        $status = Get-HttpStatusCode -ErrorRecord $_
        if ($status -in @(400, 404)) {
          $statusMessages += "$queryName=$status"
          continue
        }
        if ($status -eq 405) {
          $statusMessages += "$queryName=405"
          break
        }
        throw
      }
    }

    if (-not $queryAttempted -and $statusMessages.Count -gt 0) {
      Write-Host "Fallback org $orgLabel had no supported query shape ($($statusMessages -join ', '))."
    }
  }

  return $all
}

$baseUrl = "https://$Instance"
$tokens = Load-Tokens -Path $TokenPath
if ([string]::IsNullOrWhiteSpace($tokens.refresh_token)) {
  throw "Refresh token is missing or unreadable in $TokenPath"
}

$tokenResponse = Invoke-RestMethod `
  -Method Post `
  -Uri "$baseUrl/ws/oauth/token" `
  -ContentType 'application/x-www-form-urlencoded' `
  -Body @{
    grant_type    = 'refresh_token'
    refresh_token = $tokens.refresh_token
    client_id     = $ClientId.Trim()
    client_secret = $ClientSecret.Trim()
  }

$accessToken = [string]$tokenResponse.access_token
if ([string]::IsNullOrWhiteSpace($accessToken)) {
  throw "Token endpoint returned no access_token. Raw response: $($tokenResponse | ConvertTo-Json -Depth 8)"
}

$updated = @{
  access_token  = $accessToken
  refresh_token = if ($tokenResponse.refresh_token) { [string]$tokenResponse.refresh_token } else { [string]$tokens.refresh_token }
  token_type    = [string]$tokenResponse.token_type
  scope         = [string]$tokenResponse.scope
  expires_at    = [DateTimeOffset]::UtcNow.AddSeconds([int]$tokenResponse.expires_in).ToString('o')
}
Save-Tokens -Path $TokenPath -Tokens $updated

$headers = @{
  Authorization = "Bearer $accessToken"
  Accept        = 'application/json'
}

$folders = @(Invoke-NinjaOneGetPaged -BaseUrl $baseUrl -Path '/api/v2/knowledgebase/folder' -Headers $headers -PageSize $PageSize)
$folderMap = @{}
foreach ($folder in $folders) {
  if ($folder.id) { $folderMap[[string]$folder.id] = [string]$folder.name }
}

$orgArticles = @()
$orgEndpointSupported = $true
try {
  $orgArticles = @(Invoke-NinjaOneGetPaged -BaseUrl $baseUrl -Path '/api/v2/knowledgebase/organization/articles' -Headers $headers -PageSize $PageSize)
} catch {
  $status = Get-HttpStatusCode -ErrorRecord $_
  if ($status -eq 405) {
    $orgEndpointSupported = $false
    Write-Host "Endpoint not supported for this tenant: GET /api/v2/knowledgebase/organization/articles (405)."
  } else {
    throw
  }
}

if ($orgEndpointSupported -and $orgArticles.Count -eq 0) {
  $orgArticles = @(Invoke-KbOrganizationArticleFallback -BaseUrl $baseUrl -Headers $headers -PageSize $PageSize)
}

$globalArticles = @()
$globalEndpointUsed = $null
$globalCandidatePaths = @(
  '/api/v2/knowledgebase/global/articles',
  '/api/v2/knowledgebase/articles'
)
foreach ($globalPath in $globalCandidatePaths) {
  try {
    $globalArticles = @(Invoke-NinjaOneGetPaged -BaseUrl $baseUrl -Path $globalPath -Headers $headers -PageSize $PageSize)
    $globalEndpointUsed = $globalPath
    break
  } catch {
    $status = Get-HttpStatusCode -ErrorRecord $_
    if ($status -in @(404, 405)) {
      Write-Host "Endpoint not supported for this tenant: GET $globalPath ($status)."
      continue
    }
    throw
  }
}
$articles = @($orgArticles + $globalArticles)

function Get-ArticleTitle {
  param([object]$Article)
  $title = Get-ObjectPropertyValue -InputObject $Article -Names @('articleName', 'name', 'title')
  if ($null -ne $title -and -not [string]::IsNullOrWhiteSpace([string]$title)) {
    return [string]$title
  }
  return $null
}

function Get-ArticleContent {
  param([object]$Article)
  $content = Get-ObjectPropertyValue -InputObject $Article -Names @(
    'article',
    'body',
    'content',
    'description',
    'html',
    'text'
  )
  if ($null -eq $content) { return $null }
  return [string]$content
}

function Get-ArticleDownloadInfo {
  param(
    [string]$BaseUrl,
    [hashtable]$Headers,
    [object]$ArticleId
  )
  if ($null -eq $ArticleId -or [string]::IsNullOrWhiteSpace([string]$ArticleId)) {
    return $null
  }

  $path = "/api/v2/knowledgebase/article/$ArticleId/download"
  $uri = Get-NinjaOneApiUrl -BaseUrl $BaseUrl -Path $path -Query @{}
  try {
    $response = Invoke-WebRequest -Method Get -Uri $uri -Headers $Headers
    $bytes = 0
    if ($response.PSObject.Properties.Name -contains 'RawContentLength' -and $null -ne $response.RawContentLength) {
      $bytes = [int64]$response.RawContentLength
    } elseif ($response.PSObject.Properties.Name -contains 'Content' -and $null -ne $response.Content) {
      $bytes = ([Text.Encoding]::UTF8.GetByteCount([string]$response.Content))
    }

    $contentType = $null
    if ($response.PSObject.Properties.Name -contains 'Headers' -and $response.Headers) {
      $contentType = [string]$response.Headers['Content-Type']
    }
    $preview = $null
    if ($response.PSObject.Properties.Name -contains 'Content' -and $response.Content) {
      $raw = [string]$response.Content
      $preview = if ($raw.Length -gt 80) { $raw.Substring(0, 80) + '...' } else { $raw }
    }

    return [pscustomobject]@{
      bytes       = $bytes
      contentType = $contentType
      preview     = $preview
      error       = $null
    }
  } catch {
    $status = Get-HttpStatusCode -ErrorRecord $_
    return [pscustomobject]@{
      bytes       = 0
      contentType = $null
      preview     = $null
      error       = if ($status) { "HTTP $status" } else { "request-failed" }
    }
  }
}

function Get-ArticleDetailInfo {
  param(
    [string]$BaseUrl,
    [hashtable]$Headers,
    [object]$ArticleId
  )
  if ($null -eq $ArticleId -or [string]::IsNullOrWhiteSpace([string]$ArticleId)) {
    return $null
  }

  $candidatePaths = @(
    "/api/v2/knowledgebase/organization/articles/$ArticleId",
    "/api/v2/knowledgebase/global/articles/$ArticleId",
    "/api/v2/knowledgebase/articles/$ArticleId",
    "/api/v2/knowledgebase/article/$ArticleId"
  )

  foreach ($path in $candidatePaths) {
    $uri = Get-NinjaOneApiUrl -BaseUrl $BaseUrl -Path $path -Query @{}
    try {
      $resp = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers
      if ($null -eq $resp) { continue }

      $content = Get-ObjectPropertyValue -InputObject $resp -Names @('article', 'body', 'content', 'description', 'html', 'text')
      if ($null -ne $content -and -not [string]::IsNullOrWhiteSpace([string]$content)) {
        $text = [string]$content
        return [pscustomobject]@{
          bytes   = [Text.Encoding]::UTF8.GetByteCount($text)
          source  = $path
          preview = if ($text.Length -gt 80) { $text.Substring(0, 80) + '...' } else { $text }
          error   = $null
        }
      }

      # Endpoint succeeded but returned object without visible content fields.
      return [pscustomobject]@{
        bytes   = 0
        source  = $path
        preview = $null
        error   = 'no-content-field'
      }
    } catch {
      $status = Get-HttpStatusCode -ErrorRecord $_
      if ($status -in @(400, 404, 405)) { continue }
      return [pscustomobject]@{
        bytes   = 0
        source  = $path
        preview = $null
        error   = if ($status) { "HTTP $status" } else { "request-failed" }
      }
    }
  }

  return [pscustomobject]@{
    bytes   = 0
    source  = $null
    preview = $null
    error   = 'no-supported-detail-endpoint'
  }
}

$articleRows = @(
  $articles | ForEach-Object {
    $title = Get-ArticleTitle -Article $_
    $content = Get-ArticleContent -Article $_
    $id = Get-ObjectPropertyValue -InputObject $_ -Names @('id', 'articleId')
    $organizationId = Get-ObjectPropertyValue -InputObject $_ -Names @('organizationId')
    $organisationId = Get-ObjectPropertyValue -InputObject $_ -Names @('organisationId')
    $folderId = Get-ObjectPropertyValue -InputObject $_ -Names @('folderId')
    $lastUpdated = Get-ObjectPropertyValue -InputObject $_ -Names @('lastUpdated', 'lastModified', 'updatedAt')
    $contentLength = if ([string]::IsNullOrEmpty($content)) { 0 } else { $content.Length }
    $contentPreview = if ($contentLength -gt 80) { $content.Substring(0, 80) + '...' } else { $content }

    if ($title -or $id -or $organizationId -or $organisationId -or $folderId -or $lastUpdated -or ($contentLength -gt 0)) {
      [pscustomobject]@{
        title          = $title
        id             = $id
        organizationId = $organizationId
        organisationId = $organisationId
        folderId       = $folderId
        folderName     = $folderMap[[string]$folderId]
        lastUpdated    = $lastUpdated
        contentLength  = $contentLength
        contentPreview = $contentPreview
      }
    }
  }
)

$matches = @(
  $articleRows | Where-Object {
    $_.title -and $_.title -like "$TitlePrefix*"
  }
)

$matchesDetailed = @(
  $matches | ForEach-Object {
    $detail = Get-ArticleDetailInfo -BaseUrl $baseUrl -Headers $headers -ArticleId $_.id
    $download = Get-ArticleDownloadInfo -BaseUrl $baseUrl -Headers $headers -ArticleId $_.id
    $effectiveBytes = 0
    if ($detail -and $detail.bytes -gt 0) {
      $effectiveBytes = [int64]$detail.bytes
    } elseif ($download -and $download.bytes -gt 0) {
      $effectiveBytes = [int64]$download.bytes
    }
    [pscustomobject]@{
      title          = $_.title
      id             = $_.id
      organizationId = $_.organizationId
      organisationId = $_.organisationId
      folderId       = $_.folderId
      folderName     = $_.folderName
      contentLength  = $_.contentLength
      contentPreview = $_.contentPreview
      detailBytes    = if ($detail) { $detail.bytes } else { 0 }
      detailSource   = if ($detail) { $detail.source } else { $null }
      detailError    = if ($detail) { $detail.error } else { 'not-requested' }
      downloadBytes  = if ($download) { $download.bytes } else { 0 }
      downloadType   = if ($download) { $download.contentType } else { $null }
      downloadError  = if ($download) { $download.error } else { 'not-requested' }
      effectiveBytes = $effectiveBytes
      lastUpdated    = $_.lastUpdated
    }
  }
)
$matchesWithContent = @($matchesDetailed | Where-Object { $_.effectiveBytes -gt 0 })
$matchesWithoutContent = @($matchesDetailed | Where-Object { $_.effectiveBytes -le 0 })

Write-Host "Token OK. Access token length: $($accessToken.Length)"
Write-Host "Folders returned: $($folders.Count)"
Write-Host "Org articles returned: $($orgArticles.Count)"
Write-Host "Global articles returned: $($globalArticles.Count)"
if ($globalEndpointUsed) {
  Write-Host "Global endpoint used: $globalEndpointUsed"
}
Write-Host "Combined articles returned: $($articleRows.Count)"
if ($articles.Count -ne $articleRows.Count) {
  Write-Host "Combined raw payload items: $($articles.Count) (non-article objects ignored)."
}
Write-Host "Matching '$TitlePrefix*': $($matches.Count)"
Write-Host "Matching with content: $($matchesWithContent.Count)"
Write-Host "Matching with empty content: $($matchesWithoutContent.Count)"
if ($matchesDetailed.Count -gt 0) {
  Write-Host 'Content checks:'
  foreach ($item in $matchesDetailed | Sort-Object title) {
    $detailErr = if ([string]::IsNullOrWhiteSpace([string]$item.detailError)) { '<none>' } else { [string]$item.detailError }
    $downloadErr = if ([string]::IsNullOrWhiteSpace([string]$item.downloadError)) { '<none>' } else { [string]$item.downloadError }
    Write-Host ("  - id={0} effectiveBytes={1} detailBytes={2} detailSource={3} detailError={4} downloadBytes={5} downloadError={6} title={7}" -f $item.id, $item.effectiveBytes, $item.detailBytes, $item.detailSource, $detailErr, $item.downloadBytes, $downloadErr, $item.title)
  }
}

if ($matches.Count -gt 0) {
  $matchesDetailed |
    Select-Object title, id, organizationId, organisationId, folderId, folderName, contentLength, detailBytes, detailSource, detailError, downloadBytes, downloadType, downloadError, effectiveBytes, lastUpdated |
    Sort-Object title |
    Format-Table -AutoSize
} else {
  Write-Host 'No Patch Operations Dashboard articles found. Showing first 15 KB articles:'
  $articleRows |
    Select-Object -First 15 title, id, organizationId, organisationId, folderId, folderName, contentLength, contentPreview, lastUpdated |
    Format-Table -AutoSize
}
