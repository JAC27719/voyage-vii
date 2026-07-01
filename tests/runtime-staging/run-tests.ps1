#requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$tool = Join-Path $repo "tools/runtime-staging/stage-runtime.ps1"
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("voyage-vii-runtime-staging-tests-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $temp | Out-Null

function New-TestPe([string]$Path, [UInt16]$Machine) {
  $bytes = New-Object byte[] 128
  $bytes[0] = 0x4D
  $bytes[1] = 0x5A
  [BitConverter]::GetBytes([int]0x40).CopyTo($bytes, 0x3C)
  $bytes[0x40] = 0x50
  $bytes[0x41] = 0x45
  $bytes[0x42] = 0
  $bytes[0x43] = 0
  [BitConverter]::GetBytes($Machine).CopyTo($bytes, 0x44)
  [System.IO.File]::WriteAllBytes($Path, $bytes)
}

function New-Zip([string]$Path, [hashtable]$Entries, [string]$SymlinkEntry) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
  $zip = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
  try {
    foreach ($name in $Entries.Keys) {
      $entry = $zip.CreateEntry($name)
      $stream = $entry.Open()
      try {
        $bytes = [System.IO.File]::ReadAllBytes($Entries[$name])
        $stream.Write($bytes, 0, $bytes.Length)
      } finally {
        $stream.Dispose()
      }
    }
    if ($SymlinkEntry) {
      $entry = $zip.CreateEntry($SymlinkEntry)
      $entry.ExternalAttributes = 0xA000 -shl 16
    }
  } finally {
    $zip.Dispose()
  }
}

function New-RawZip([string]$Path, [array]$Entries) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
  $zip = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
  try {
    foreach ($spec in $Entries) {
      $entry = $zip.CreateEntry($spec.name)
      if ($spec.path) {
        $stream = $entry.Open()
        try {
          $bytes = [System.IO.File]::ReadAllBytes($spec.path)
          $stream.Write($bytes, 0, $bytes.Length)
        } finally {
          $stream.Dispose()
        }
      }
    }
  } finally {
    $zip.Dispose()
  }
}

function Add-ZipDirectory([string]$Path, [string]$DirectoryEntry) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Update)
  try {
    $zip.CreateEntry($DirectoryEntry) | Out-Null
  } finally {
    $zip.Dispose()
  }
}

function Get-Sha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function New-Manifest([string]$Path, [string]$SqliteZip, [string]$TigerZip, [string]$LicenseZip, [hashtable]$Override = @{}) {
  $sqliteHash = Get-Sha256 $SqliteZip
  $tigerHash = Get-Sha256 $TigerZip
  $licenseHash = Get-Sha256 $LicenseZip
  $manifest = [ordered]@{
    schemaVersion = 1
    productVersion = "0.1.0"
    target = "x86_64-pc-windows-msvc"
    cachePath = "cache"
    outputPath = "out"
    reportPath = "reports"
    components = @(
      [ordered]@{
        id = "api"
        version = "0.1.0"
        kind = "first-party-build"
        target = "x86_64-pc-windows-msvc"
        path = "api/voyage-vii-api.exe"
        licensePath = $null
        source = [ordered]@{ kind = "first-party-build"; url = $null; revision = $null }
        status = "pending-package-task"
      },
      [ordered]@{
        id = "sqlite"
        version = "3.53.3"
        kind = "official-source"
        target = "x86_64-pc-windows-msvc"
        archive = [ordered]@{
          url = ([System.Uri](Resolve-Path $SqliteZip).Path).AbsoluteUri
          revision = "3.53.3"
          format = "zip"
          size = (Get-Item -LiteralPath $SqliteZip).Length
          sha256 = $sqliteHash
        }
        requiredFiles = @(
          [ordered]@{ archivePath = "sqlite-amalgamation-3530300/sqlite3.c"; destination = "sqlite/sqlite3.c"; sha256 = Get-Sha256 (Join-Path $temp "sqlite3.c") },
          [ordered]@{ archivePath = "sqlite-amalgamation-3530300/sqlite3.h"; destination = "sqlite/sqlite3.h"; sha256 = Get-Sha256 (Join-Path $temp "sqlite3.h") }
        )
        license = [ordered]@{ kind = "public-domain"; url = "https://www.sqlite.org/copyright.html"; destination = "licenses/sqlite/PUBLIC-DOMAIN.txt"; notice = "SQLite public domain" }
      },
      [ordered]@{
        id = "tigerbeetle"
        version = "0.17.7"
        kind = "official-release"
        target = "x86_64-pc-windows-msvc"
        archive = [ordered]@{
          url = ([System.Uri](Resolve-Path $TigerZip).Path).AbsoluteUri
          revision = "0.17.7"
          format = "zip"
          sha256 = $tigerHash
        }
        requiredFiles = @(
          [ordered]@{ archivePath = "tigerbeetle.exe"; destination = "tigerbeetle/tigerbeetle.exe"; sha256 = Get-Sha256 (Join-Path $temp "tigerbeetle.exe"); peMachine = "0x8664" }
        )
        licenseArchive = [ordered]@{
          url = ([System.Uri](Resolve-Path $LicenseZip).Path).AbsoluteUri
          revision = "0.17.7"
          format = "zip"
          sha256 = $licenseHash
          licenseArchivePath = "tigerbeetle-0.17.7/LICENSE"
          licenseSha256 = Get-Sha256 (Join-Path $temp "LICENSE")
          destination = "licenses/tigerbeetle/LICENSE"
        }
      }
    )
  }
  foreach ($key in $Override.Keys) {
    $manifest[$key] = $Override[$key]
  }
  $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Invoke-Stage([string]$Manifest, [string]$CaseName, [switch]$Offline) {
  $caseRoot = Join-Path $temp $CaseName
  New-Item -ItemType Directory -Force -Path $caseRoot | Out-Null
  & $tool -SourcesPath $Manifest -OutputRoot (Join-Path $caseRoot "out") -CacheRoot (Join-Path $caseRoot "cache") -ReportRoot (Join-Path $caseRoot "reports") -AllowTestSources -Offline:$Offline | Out-Null
  return $caseRoot
}

function Expect-Fail([scriptblock]$Block, [string]$Name) {
  try {
    & $Block
  } catch {
    Write-Host "PASS expected failure: $Name"
    return
  }
  throw "Expected failure did not happen: $Name"
}

try {
  Set-Content -LiteralPath (Join-Path $temp "sqlite3.c") -Value "sqlite c" -Encoding ascii
  Set-Content -LiteralPath (Join-Path $temp "sqlite3.h") -Value "sqlite h" -Encoding ascii
  Set-Content -LiteralPath (Join-Path $temp "LICENSE") -Value "apache license" -Encoding ascii
  New-TestPe (Join-Path $temp "tigerbeetle.exe") 0x8664
  New-TestPe (Join-Path $temp "wrong.exe") 0x014c

  $sqliteZip = Join-Path $temp "sqlite.zip"
  $tigerZip = Join-Path $temp "tiger.zip"
  $licenseZip = Join-Path $temp "license.zip"
  New-Zip $sqliteZip @{
    "sqlite-amalgamation-3530300/sqlite3.c" = Join-Path $temp "sqlite3.c"
    "sqlite-amalgamation-3530300/sqlite3.h" = Join-Path $temp "sqlite3.h"
  } $null
  New-Zip $tigerZip @{ "tigerbeetle.exe" = Join-Path $temp "tigerbeetle.exe" } $null
  New-Zip $licenseZip @{ "tigerbeetle-0.17.7/LICENSE" = Join-Path $temp "LICENSE" } $null

  $manifest = Join-Path $temp "sources.json"
  New-Manifest $manifest $sqliteZip $tigerZip $licenseZip
  $first = Invoke-Stage $manifest "warm-cache"
  & $tool -SourcesPath $manifest -OutputRoot (Join-Path $first "out") -CacheRoot (Join-Path $first "cache") -ReportRoot (Join-Path $first "reports") -AllowTestSources -Offline | Out-Null
  if (-not (Test-Path (Join-Path $first "out/manifest.inputs.json"))) { throw "manifest inputs missing" }
  Write-Host "PASS warm-cache and offline run"

  Expect-Fail { Invoke-Stage $manifest "offline-miss" -Offline } "offline cache miss"

  $corruptManifest = Join-Path $temp "corrupt.json"
  New-Manifest $corruptManifest $sqliteZip $tigerZip $licenseZip
  (Get-Content -Raw $corruptManifest).Replace((Get-Sha256 $sqliteZip), ("0" * 64)) | Set-Content -LiteralPath $corruptManifest -Encoding utf8
  Expect-Fail { Invoke-Stage $corruptManifest "corrupt" } "corrupt archive"

  $traversalZip = Join-Path $temp "traversal.zip"
  New-Zip $traversalZip @{
    "../escape.txt" = Join-Path $temp "sqlite3.c"
    "sqlite-amalgamation-3530300/sqlite3.c" = Join-Path $temp "sqlite3.c"
    "sqlite-amalgamation-3530300/sqlite3.h" = Join-Path $temp "sqlite3.h"
  } $null
  $traversalManifest = Join-Path $temp "traversal.json"
  New-Manifest $traversalManifest $traversalZip $tigerZip $licenseZip
  Expect-Fail { Invoke-Stage $traversalManifest "traversal" } "archive traversal"

  $traversalDirectoryZip = Join-Path $temp "traversal-directory.zip"
  New-Zip $traversalDirectoryZip @{
    "sqlite-amalgamation-3530300/sqlite3.c" = Join-Path $temp "sqlite3.c"
    "sqlite-amalgamation-3530300/sqlite3.h" = Join-Path $temp "sqlite3.h"
  } $null
  Add-ZipDirectory $traversalDirectoryZip "../escape/"
  $traversalDirectoryManifest = Join-Path $temp "traversal-directory.json"
  New-Manifest $traversalDirectoryManifest $traversalDirectoryZip $tigerZip $licenseZip
  Expect-Fail { Invoke-Stage $traversalDirectoryManifest "traversal-directory" } "archive traversal directory"

  $absoluteZip = Join-Path $temp "absolute.zip"
  New-RawZip $absoluteZip @(
    @{ name = "/absolute.txt"; path = Join-Path $temp "sqlite3.c" },
    @{ name = "sqlite-amalgamation-3530300/sqlite3.c"; path = Join-Path $temp "sqlite3.c" },
    @{ name = "sqlite-amalgamation-3530300/sqlite3.h"; path = Join-Path $temp "sqlite3.h" }
  )
  $absoluteManifest = Join-Path $temp "absolute.json"
  New-Manifest $absoluteManifest $absoluteZip $tigerZip $licenseZip
  Expect-Fail { Invoke-Stage $absoluteManifest "absolute" } "archive absolute path"

  $duplicateZip = Join-Path $temp "duplicate-zip.zip"
  New-RawZip $duplicateZip @(
    @{ name = "sqlite-amalgamation-3530300/sqlite3.c"; path = Join-Path $temp "sqlite3.c" },
    @{ name = "sqlite-amalgamation-3530300/sqlite3.c"; path = Join-Path $temp "sqlite3.c" },
    @{ name = "sqlite-amalgamation-3530300/sqlite3.h"; path = Join-Path $temp "sqlite3.h" }
  )
  $duplicateZipManifest = Join-Path $temp "duplicate-zip.json"
  New-Manifest $duplicateZipManifest $duplicateZip $tigerZip $licenseZip
  Expect-Fail { Invoke-Stage $duplicateZipManifest "duplicate-zip" } "duplicate zip entry"

  $symlinkZip = Join-Path $temp "symlink.zip"
  New-Zip $symlinkZip @{
    "sqlite-amalgamation-3530300/sqlite3.c" = Join-Path $temp "sqlite3.c"
    "sqlite-amalgamation-3530300/sqlite3.h" = Join-Path $temp "sqlite3.h"
  } "sqlite-amalgamation-3530300/link"
  $symlinkManifest = Join-Path $temp "symlink.json"
  New-Manifest $symlinkManifest $symlinkZip $tigerZip $licenseZip
  Expect-Fail { Invoke-Stage $symlinkManifest "symlink" } "archive symlink"

  $missingZip = Join-Path $temp "missing.zip"
  New-Zip $missingZip @{ "sqlite-amalgamation-3530300/sqlite3.c" = Join-Path $temp "sqlite3.c" } $null
  $missingManifest = Join-Path $temp "missing.json"
  New-Manifest $missingManifest $missingZip $tigerZip $licenseZip
  Expect-Fail { Invoke-Stage $missingManifest "missing" } "missing file"

  $duplicateManifest = Join-Path $temp "duplicate.json"
  New-Manifest $duplicateManifest $sqliteZip $tigerZip $licenseZip
  $dup = Get-Content -Raw $duplicateManifest | ConvertFrom-Json
  $dup.components[1].requiredFiles[1].destination = "sqlite/sqlite3.c"
  $dup | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $duplicateManifest -Encoding utf8
  Expect-Fail { Invoke-Stage $duplicateManifest "duplicate" } "duplicate destination"

  $escapeManifest = Join-Path $temp "destination-escape.json"
  New-Manifest $escapeManifest $sqliteZip $tigerZip $licenseZip
  $escape = Get-Content -Raw $escapeManifest | ConvertFrom-Json
  $escape.components[1].requiredFiles[0].destination = "../sqlite3.c"
  $escape | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $escapeManifest -Encoding utf8
  Expect-Fail { Invoke-Stage $escapeManifest "destination-escape" } "destination escape"

  $wrongTigerZip = Join-Path $temp "wrong-tiger.zip"
  New-Zip $wrongTigerZip @{ "tigerbeetle.exe" = Join-Path $temp "wrong.exe" } $null
  $wrongManifest = Join-Path $temp "wrong.json"
  New-Manifest $wrongManifest $sqliteZip $wrongTigerZip $licenseZip
  Expect-Fail { Invoke-Stage $wrongManifest "wrong-machine" } "wrong architecture"

  $wrongTargetManifest = Join-Path $temp "wrong-target.json"
  New-Manifest $wrongTargetManifest $sqliteZip $tigerZip $licenseZip @{ target = "x86_64-unknown-linux-gnu" }
  Expect-Fail { Invoke-Stage $wrongTargetManifest "wrong-target" } "wrong target"

  Expect-Fail {
    & $tool -SourcesPath (Join-Path $repo "runtime/sources.json") -OutputRoot $repo -Offline | Out-Null
  } "unsafe production output root"

  $alternateProductionManifest = Join-Path $temp "alternate-production-sources.json"
  Copy-Item -LiteralPath (Join-Path $repo "runtime/sources.json") -Destination $alternateProductionManifest
  Expect-Fail {
    & $tool -SourcesPath $alternateProductionManifest -Offline | Out-Null
  } "alternate production source manifest"

  Write-Host "runtime staging tests passed"
} finally {
  Remove-Item -LiteralPath $temp -Recurse -Force
}
