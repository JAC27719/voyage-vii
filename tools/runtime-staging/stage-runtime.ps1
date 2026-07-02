#requires -Version 7.0

[CmdletBinding()]
param(
  [string]$SourcesPath = "runtime/sources.json",
  [string]$OutputRoot,
  [string]$CacheRoot,
  [string]$ReportRoot,
  [switch]$Offline,
  [switch]$AllowTestSources
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RepoRoot {
  $root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
  return $root
}

function Resolve-RepoPath([string]$Path) {
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }
  return [System.IO.Path]::GetFullPath((Join-Path (Get-RepoRoot) $Path))
}

function Assert-UnderRoot([string]$Path, [string]$Root) {
  $resolved = [System.IO.Path]::GetFullPath($Path)
  $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
  $rootWithSeparator = $resolvedRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
  if ($resolved -ne $resolvedRoot -and -not $resolved.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Path escapes root: $resolved"
  }
  return $resolved
}

function Assert-ExactPath([string]$Actual, [string]$Expected, [string]$Name) {
  $resolvedActual = [System.IO.Path]::GetFullPath($Actual)
  $resolvedExpected = [System.IO.Path]::GetFullPath($Expected)
  if ($resolvedActual -ne $resolvedExpected) {
    throw "$Name must use the checked-in source manifest path: $resolvedExpected"
  }
  return $resolvedActual
}

function Test-RelativePosixPath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  if ($Path.StartsWith("/") -or $Path -match "^[A-Za-z]:") { return $false }
  if ($Path.Contains("\")) { return $false }
  foreach ($part in $Path.Split("/")) {
    if ($part -eq "" -or $part -eq "." -or $part -eq "..") { return $false }
  }
  return $true
}

function Assert-RelativePosixPath([string]$Path, [string]$Name) {
  if (-not (Test-RelativePosixPath $Path)) {
    throw "Invalid $Name path: $Path"
  }
}

function Get-OptionalProperty($Object, [string]$Name) {
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Get-FileSha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-FileSha3_256([string]$Path) {
  $stream = [System.IO.File]::OpenRead($Path)
  try {
    $hash = [System.Security.Cryptography.SHA3_256]::HashData($stream)
    return [Convert]::ToHexString($hash).ToLowerInvariant()
  } finally {
    $stream.Dispose()
  }
}

function Get-CachePath($Archive, [string]$CacheRootPath) {
  $name = [System.IO.Path]::GetFileName(([System.Uri]$Archive.url).AbsolutePath)
  if ([string]::IsNullOrWhiteSpace($name)) { throw "Archive URL has no file name: $($Archive.url)" }
  $sha256 = Get-OptionalProperty $Archive "sha256"
  $sha3 = Get-OptionalProperty $Archive "sha3_256"
  $hash = if ($sha256) { $sha256 } else { $sha3 }
  if (-not $hash) { throw "Archive has no cache hash: $($Archive.url)" }
  return Join-Path (Join-Path $CacheRootPath $hash) $name
}

function Copy-UriToFile([string]$Url, [string]$Destination, [switch]$AllowTestSources) {
  $uri = [System.Uri]$Url
  if ($uri.Scheme -eq "file" -and $AllowTestSources) {
    Copy-Item -LiteralPath $uri.LocalPath -Destination $Destination
    return
  }
  if ($uri.Scheme -ne "https") {
    throw "Only HTTPS source archives are allowed: $Url"
  }
  Invoke-WebRequest -Uri $Url -OutFile $Destination
}

function Assert-ArchiveHash($Archive, [string]$Path) {
  $size = Get-OptionalProperty $Archive "size"
  $sha256 = Get-OptionalProperty $Archive "sha256"
  $sha3 = Get-OptionalProperty $Archive "sha3_256"
  if ($size -and ((Get-Item -LiteralPath $Path).Length -ne [int64]$size)) {
    throw "Size mismatch for $($Archive.url)"
  }
  if ($sha256) {
    $actual = Get-FileSha256 $Path
    if ($actual -ne $sha256) { throw "SHA-256 mismatch for $($Archive.url): $actual" }
  }
  if ($sha3) {
    $actual = Get-FileSha3_256 $Path
    if ($actual -ne $sha3) { throw "SHA3-256 mismatch for $($Archive.url): $actual" }
  }
}

function Get-VerifiedArchive($Archive, [string]$CacheRootPath, [switch]$Offline, [switch]$AllowTestSources) {
  $cachePath = Get-CachePath $Archive $CacheRootPath
  if (Test-Path -LiteralPath $cachePath) {
    Assert-ArchiveHash $Archive $cachePath
    return $cachePath
  }
  if ($Offline) {
    throw "Offline cache miss for $($Archive.url)"
  }

  $cacheDir = Split-Path -Parent $cachePath
  New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
  $temp = Join-Path $cacheDir ([System.Guid]::NewGuid().ToString("N") + ".download")
  Copy-UriToFile $Archive.url $temp -AllowTestSources:$AllowTestSources
  Assert-ArchiveHash $Archive $temp
  Move-Item -LiteralPath $temp -Destination $cachePath
  return $cachePath
}

function Open-Zip([string]$Path) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  return [System.IO.Compression.ZipFile]::OpenRead($Path)
}

function Assert-ZipSafe($Zip) {
  $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($entry in $Zip.Entries) {
    $name = $entry.FullName.Replace("\", "/").TrimEnd("/")
    Assert-RelativePosixPath $name "archive entry"
    $mode = ($entry.ExternalAttributes -shr 16) -band 0xF000
    if ($mode -eq 0xA000) { throw "Archive symlink entry rejected: $name" }
    if (-not $seen.Add($name)) { throw "Duplicate archive destination rejected: $name" }
  }
}

function Get-ZipEntry($Zip, [string]$ArchivePath) {
  Assert-RelativePosixPath $ArchivePath "required archive"
  $matches = @($Zip.Entries | Where-Object { $_.FullName.Replace("\", "/") -eq $ArchivePath })
  if ($matches.Count -ne 1) { throw "Required archive file missing: $ArchivePath" }
  return $matches[0]
}

function Copy-ZipEntry($Zip, [string]$ArchivePath, [string]$Destination, [string]$ExpectedSha256) {
  $entry = Get-ZipEntry $Zip $ArchivePath
  $parent = Split-Path -Parent $Destination
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  $entryStream = $entry.Open()
  try {
    $out = [System.IO.File]::Create($Destination)
    try {
      $entryStream.CopyTo($out)
    } finally {
      $out.Dispose()
    }
  } finally {
    $entryStream.Dispose()
  }
  if ($ExpectedSha256) {
    $actual = Get-FileSha256 $Destination
    if ($actual -ne $ExpectedSha256) { throw "SHA-256 mismatch for extracted $ArchivePath" }
  }
}

function Get-PeMachine([string]$Path) {
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -lt 66 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
    throw "Not a PE executable: $Path"
  }
  $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
  if ($peOffset -lt 0 -or ($peOffset + 6) -gt $bytes.Length) { throw "Invalid PE header: $Path" }
  if ($bytes[$peOffset] -ne 0x50 -or $bytes[$peOffset + 1] -ne 0x45 -or $bytes[$peOffset + 2] -ne 0 -or $bytes[$peOffset + 3] -ne 0) {
    throw "Invalid PE signature: $Path"
  }
  return ("0x{0:x4}" -f [BitConverter]::ToUInt16($bytes, $peOffset + 4))
}

function Stage-RequiredFiles($Component, [string]$ArchivePath, [string]$StageRoot) {
  $zip = Open-Zip $ArchivePath
  try {
    Assert-ZipSafe $zip
    $destinations = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $Component.requiredFiles) {
      Assert-RelativePosixPath $file.archivePath "required archive"
      Assert-RelativePosixPath $file.destination "destination"
      if (-not $destinations.Add($file.destination)) { throw "Duplicate manifest destination rejected: $($file.destination)" }
      $dest = Assert-UnderRoot (Join-Path $StageRoot ($file.destination -replace "/", [System.IO.Path]::DirectorySeparatorChar)) $StageRoot
      Copy-ZipEntry $zip $file.archivePath $dest $file.sha256
      $peMachine = Get-OptionalProperty $file "peMachine"
      if ($peMachine) {
        $actualMachine = Get-PeMachine $dest
        if ($actualMachine -ne $peMachine) { throw "Wrong PE machine for $($file.destination): $actualMachine" }
      }
    }
  } finally {
    $zip.Dispose()
  }
}

function Stage-LicenseArchive($LicenseArchive, [string]$ArchivePath, [string]$StageRoot) {
  $zip = Open-Zip $ArchivePath
  try {
    Assert-ZipSafe $zip
    Assert-RelativePosixPath $LicenseArchive.destination "license destination"
    $dest = Assert-UnderRoot (Join-Path $StageRoot ($LicenseArchive.destination -replace "/", [System.IO.Path]::DirectorySeparatorChar)) $StageRoot
    Copy-ZipEntry $zip $LicenseArchive.licenseArchivePath $dest $LicenseArchive.licenseSha256
  } finally {
    $zip.Dispose()
  }
}

function Write-JsonFile([string]$Path, $Value) {
  $json = $Value | ConvertTo-Json -Depth 20
  Set-Content -LiteralPath $Path -Value $json -Encoding utf8
}

$repoRoot = Get-RepoRoot
$sourceFile = Resolve-RepoPath $SourcesPath
if (-not $AllowTestSources) {
  Assert-ExactPath $sourceFile (Resolve-RepoPath "runtime/sources.json") "SourcesPath" | Out-Null
}
$sources = Get-Content -Raw -LiteralPath $sourceFile | ConvertFrom-Json

if ($sources.schemaVersion -ne 1) { throw "Unsupported source manifest schemaVersion" }
if ($sources.target -ne "x86_64-pc-windows-msvc") { throw "Unsupported runtime staging target: $($sources.target)" }
if ($sources.productVersion -ne "0.1.0") { throw "Unsupported product version: $($sources.productVersion)" }

$output = if ($OutputRoot) { Resolve-RepoPath $OutputRoot } else { Resolve-RepoPath $sources.outputPath }
$cache = if ($CacheRoot) { Resolve-RepoPath $CacheRoot } else { Resolve-RepoPath $sources.cachePath }
$reports = if ($ReportRoot) { Resolve-RepoPath $ReportRoot } else { Resolve-RepoPath $sources.reportPath }
if (-not $AllowTestSources) {
  Assert-ExactPath $output (Resolve-RepoPath $sources.outputPath) "OutputRoot" | Out-Null
  Assert-ExactPath $cache (Resolve-RepoPath $sources.cachePath) "CacheRoot" | Out-Null
  Assert-ExactPath $reports (Resolve-RepoPath $sources.reportPath) "ReportRoot" | Out-Null
}

$stage = "$output.__staging.$([System.Guid]::NewGuid().ToString("N"))"
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
New-Item -ItemType Directory -Force -Path $cache | Out-Null
New-Item -ItemType Directory -Force -Path $reports | Out-Null

$components = @()
try {
  foreach ($component in $sources.components) {
    if ($component.target -and $component.target -ne $sources.target) { throw "Component $($component.id) has wrong target $($component.target)" }
    switch ($component.id) {
      "api" {
        Assert-RelativePosixPath $component.path "api path"
        $components += [pscustomobject]@{
          id = "api"
          version = $component.version
          path = $component.path
          sha256 = $null
          licensePath = $null
          source = $component.source
          status = "pending-package-task"
        }
      }
      "sqlite" {
        $archivePath = Get-VerifiedArchive $component.archive $cache -Offline:$Offline -AllowTestSources:$AllowTestSources
        Stage-RequiredFiles $component $archivePath $stage
        Assert-RelativePosixPath $component.license.destination "sqlite license"
        $licensePath = Assert-UnderRoot (Join-Path $stage ($component.license.destination -replace "/", [System.IO.Path]::DirectorySeparatorChar)) $stage
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $licensePath) | Out-Null
        Set-Content -LiteralPath $licensePath -Encoding utf8 -Value $component.license.notice
        $components += [pscustomobject]@{
          id = "sqlite"
          version = $component.version
          path = "sqlite/sqlite3.c"
          sha256 = (Get-FileSha256 (Join-Path $stage "sqlite/sqlite3.c"))
          licensePath = $component.license.destination
          source = [pscustomobject]@{ kind = "official-source"; url = $component.archive.url; revision = $component.archive.revision }
        }
      }
      "tigerbeetle" {
        $archivePath = Get-VerifiedArchive $component.archive $cache -Offline:$Offline -AllowTestSources:$AllowTestSources
        Stage-RequiredFiles $component $archivePath $stage
        $licenseArchivePath = Get-VerifiedArchive $component.licenseArchive $cache -Offline:$Offline -AllowTestSources:$AllowTestSources
        Stage-LicenseArchive $component.licenseArchive $licenseArchivePath $stage
        $components += [pscustomobject]@{
          id = "tigerbeetle"
          version = $component.version
          path = "tigerbeetle/tigerbeetle.exe"
          sha256 = (Get-FileSha256 (Join-Path $stage "tigerbeetle/tigerbeetle.exe"))
          licensePath = $component.licenseArchive.destination
          source = [pscustomobject]@{ kind = "official-release"; url = $component.archive.url; revision = $component.archive.revision }
        }
      }
      default { throw "Unsupported component id: $($component.id)" }
    }
  }

  $notices = @(
    "Voyage VII third-party notices",
    "",
    "SQLite 3.53.3: public domain dedication. Source: https://www.sqlite.org/2026/sqlite-amalgamation-3530300.zip",
    "TigerBeetle 0.17.7: Apache-2.0. Source: https://github.com/tigerbeetle/tigerbeetle/releases/download/0.17.7/tigerbeetle-x86_64-windows.zip"
  ) -join "`n"
  Set-Content -LiteralPath (Join-Path $stage "THIRD-PARTY-NOTICES.txt") -Encoding utf8 -Value $notices

  $manifestInputs = [pscustomobject]@{
    schemaVersion = 1
    productVersion = $sources.productVersion
    target = $sources.target
    generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    components = $components
  }
  Write-JsonFile (Join-Path $stage "manifest.inputs.json") $manifestInputs

  $files = Get-ChildItem -LiteralPath $stage -Recurse -File | ForEach-Object {
    [pscustomobject]@{
      path = $_.FullName.Substring($stage.Length + 1).Replace("\", "/")
      size = $_.Length
      sha256 = Get-FileSha256 $_.FullName
    }
  } | Sort-Object path

  $report = [pscustomobject]@{
    schemaVersion = 1
    target = $sources.target
    outputPath = $sources.outputPath
    fileCount = @($files).Count
    totalBytes = (@($files) | Measure-Object -Property size -Sum).Sum
    files = $files
  }

  $reportJson = Join-Path $reports "last-run.json"
  Write-JsonFile $reportJson $report
  $reportText = @(
    "# Runtime Staging Report",
    "",
    "- target: $($report.target)",
    "- file count: $($report.fileCount)",
    "- total bytes: $($report.totalBytes)",
    "",
    "| Path | Bytes | SHA-256 |",
    "| --- | ---: | --- |"
  )
  foreach ($file in $files) {
    $reportText += "| {0} | {1} | `{2}` |" -f $file.path, $file.size, $file.sha256
  }
  Set-Content -LiteralPath (Join-Path $reports "last-run.md") -Encoding utf8 -Value ($reportText -join "`n")

  $previousOutput = "$output.__previous.$([System.Guid]::NewGuid().ToString("N"))"
  if (Test-Path -LiteralPath $previousOutput) { Remove-Item -LiteralPath $previousOutput -Recurse -Force }
  if (Test-Path -LiteralPath $output) { Move-Item -LiteralPath $output -Destination $previousOutput }
  Move-Item -LiteralPath $stage -Destination $output
  if (Test-Path -LiteralPath $previousOutput) { Remove-Item -LiteralPath $previousOutput -Recurse -Force }
  Write-Output "staged runtime: $output"
  Write-Output "report: $reportJson"
} catch {
  if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
  throw
}
