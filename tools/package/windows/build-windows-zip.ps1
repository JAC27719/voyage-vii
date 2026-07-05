#requires -Version 7.0

[CmdletBinding()]
param(
  [string]$ZigPath,
  [string]$TigerBeetleClientLib,
  [string]$TigerBeetleClientInclude,
  [string]$OutputRoot = "tools/package/windows/artifacts",
  [string]$BuildRoot = "tools/package/windows/build",
  [string]$ReportRoot = "tools/package/windows/reports",
  [switch]$Offline,
  [switch]$SkipSmoke
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProductExeName = "Voyage VII.exe"
$Target = "x86_64-pc-windows-msvc"
$ArtifactPrefix = "voyage-vii"
$SmokePrefix = "VOYAGE_VII_SMOKE "

function Get-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
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
    throw "Path escaped expected root."
  }
  return $resolved
}

function Invoke-Step([string]$Name, [scriptblock]$Block) {
  Write-Host "==> $Name"
  & $Block
}

function Invoke-CommandChecked([string]$FileName, [string[]]$Arguments, [string]$WorkingDirectory) {
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $command = if ([System.IO.Path]::IsPathRooted($FileName)) {
    $FileName
  } else {
    $candidates = @(Get-Command $FileName -All -ErrorAction Stop)
    $application = $candidates | Where-Object { $_.CommandType -eq "Application" } | Select-Object -First 1
    if ($application) { $application.Source } else { $candidates[0].Source }
  }
  $psi.FileName = $command
  foreach ($arg in $Arguments) { [void]$psi.ArgumentList.Add($arg) }
  $psi.WorkingDirectory = $WorkingDirectory
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $process = [System.Diagnostics.Process]::Start($psi)
  $stdout = $process.StandardOutput.ReadToEndAsync()
  $stderr = $process.StandardError.ReadToEndAsync()
  $process.WaitForExit()
  if ($process.ExitCode -ne 0) {
    throw "Command failed ($FileName $($Arguments -join ' ')): $($stderr.Result)"
  }
  return [pscustomobject]@{ Stdout = $stdout.Result; Stderr = $stderr.Result }
}

function Get-FileSha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-CleanTrackedInputs([string[]]$Paths) {
  $result = Invoke-CommandChecked "git" (@("status", "--porcelain", "--untracked-files=no", "--") + $Paths) (Get-RepoRoot)
  if (-not [string]::IsNullOrWhiteSpace($result.Stdout)) {
    throw "Tracked package inputs have uncommitted changes. Commit or revert package inputs before producing the final ZIP.`n$($result.Stdout.Trim())"
  }
}

function Get-PeHeader([string]$Path) {
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -lt 0x5e -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) {
    throw "Not a PE executable."
  }
  $peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
  if ($peOffset -lt 0 -or ($peOffset + 0x5e) -gt $bytes.Length) { throw "Invalid PE header." }
  if ($bytes[$peOffset] -ne 0x50 -or $bytes[$peOffset + 1] -ne 0x45 -or $bytes[$peOffset + 2] -ne 0 -or $bytes[$peOffset + 3] -ne 0) {
    throw "Invalid PE signature."
  }
  return [pscustomobject]@{
    Bytes = $bytes
    PeOffset = $peOffset
    Machine = ("0x{0:x4}" -f [BitConverter]::ToUInt16($bytes, $peOffset + 4))
    SubsystemOffset = $peOffset + 0x5c
    Subsystem = [BitConverter]::ToUInt16($bytes, $peOffset + 0x5c)
  }
}

function Set-PeSubsystemWindowsGui([string]$Path) {
  $header = Get-PeHeader $Path
  $bytes = $header.Bytes
  [BitConverter]::GetBytes([uint16]2).CopyTo($bytes, $header.SubsystemOffset)
  [System.IO.File]::WriteAllBytes($Path, $bytes)
}

function Assert-Pe([string]$Path, [string]$ExpectedMachine, $ExpectedSubsystem) {
  $header = Get-PeHeader $Path
  if ($header.Machine -ne $ExpectedMachine) { throw "Unexpected PE machine for $(Split-Path -Leaf $Path): $($header.Machine)" }
  if ($null -ne $ExpectedSubsystem -and $header.Subsystem -ne [uint16]$ExpectedSubsystem) {
    throw "Unexpected PE subsystem for $(Split-Path -Leaf $Path): $($header.Subsystem)"
  }
  return $header
}

function Copy-CleanDirectory([string]$Source, [string]$Destination) {
  if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  foreach ($child in Get-ChildItem -LiteralPath $Source -Force) {
    Copy-Item -LiteralPath $child.FullName -Destination $Destination -Recurse -Force
  }
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

function Assert-FinalManifest([string]$ManifestPath, [string]$Version, [string]$ApiHash, [string]$ApiRevision) {
  $manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
  if ($manifest.schemaVersion -ne 1 -or $manifest.productVersion -ne $Version -or $manifest.target -ne $Target) {
    throw "Final runtime manifest header is invalid."
  }
  $expected = @("api", "sqlite", "tigerbeetle")
  if (@($manifest.components).Count -ne 3) { throw "Final runtime manifest must contain exactly three components." }
  for ($index = 0; $index -lt $expected.Count; $index++) {
    $component = $manifest.components[$index]
    if ($component.id -ne $expected[$index]) { throw "Final runtime manifest component order is invalid." }
    if (-not (Test-RelativePosixPath $component.path)) { throw "Final runtime manifest contains an unsafe path." }
    if ($component.sha256 -notmatch '^[a-f0-9]{64}$') { throw "Final runtime manifest contains an invalid hash." }
  }
  if ($manifest.components[0].sha256 -ne $ApiHash) { throw "Final runtime manifest API hash mismatch." }
  if ($manifest.components[0].source.kind -ne "first-party-build" -or $null -ne $manifest.components[0].source.url -or $manifest.components[0].source.revision -ne $ApiRevision) {
    throw "Final runtime manifest API source is invalid."
  }
}

function Write-FinalManifest([string]$RuntimeRoot, [string]$Version, [string]$ApiHash, [string]$ApiRevision) {
  $inputsPath = Join-Path $RuntimeRoot "manifest.inputs.json"
  $inputs = Get-Content -Raw -LiteralPath $inputsPath | ConvertFrom-Json
  $components = @()
  foreach ($component in $inputs.components) {
    if ($component.id -eq "api") {
      $components += [pscustomobject]@{
        id = "api"
        version = $Version
        path = "api/voyage-vii-api.exe"
        sha256 = $ApiHash
        licensePath = $null
        source = [pscustomobject]@{ kind = "first-party-build"; url = $null; revision = $ApiRevision }
      }
    } else {
      $components += [pscustomobject]@{
        id = $component.id
        version = $component.version
        path = $component.path
        sha256 = $component.sha256
        licensePath = $component.licensePath
        source = $component.source
      }
    }
  }
  $manifest = [pscustomobject]@{
    schemaVersion = 1
    productVersion = $Version
    target = $Target
    components = $components
  }
  $manifestPath = Join-Path $RuntimeRoot "manifest.json"
  Set-Content -LiteralPath $manifestPath -Value ($manifest | ConvertTo-Json -Depth 20) -Encoding utf8
  Remove-Item -LiteralPath $inputsPath -Force
  Assert-FinalManifest $manifestPath $Version $ApiHash $ApiRevision
}

function Assert-NoForbiddenPackageFiles([string]$PackageRoot) {
  $forbidden = Get-ChildItem -LiteralPath $PackageRoot -Recurse -File | Where-Object {
    $relative = $_.FullName.Substring($PackageRoot.Length + 1).Replace("\", "/")
    $_.Name -match '\.(pdb|map)$' -or
    $relative -match '(^|/)(\.git|\.zig-cache|target|node_modules|cache|reports|build)/'
  }
  if ($forbidden) {
    throw "Package contains forbidden debug/build files."
  }
}

function New-ZipFromRoot([string]$SourceRoot, [string]$ZipPath) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
  $zip = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
  try {
    foreach ($file in Get-ChildItem -LiteralPath $SourceRoot -Recurse -File | Sort-Object FullName) {
      $relative = $file.FullName.Substring($SourceRoot.Length + 1).Replace("\", "/")
      [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $relative, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
  } finally {
    $zip.Dispose()
  }
}

function Assert-ZipContents([string]$ZipPath, [string[]]$RequiredEntries) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
  try {
    $entries = @($zip.Entries | ForEach-Object { $_.FullName })
    foreach ($required in $RequiredEntries) {
      if ($entries -notcontains $required) { throw "ZIP is missing required entry: $required" }
    }
    if ($entries | Where-Object { $_ -match '\.(pdb|map)$|manifest\.inputs\.json$' }) {
      throw "ZIP contains forbidden debug or build metadata."
    }
  } finally {
    $zip.Dispose()
  }
}

function Invoke-PackageSmoke([string]$ZipPath, [string]$ExtractRoot) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  if (Test-Path -LiteralPath $ExtractRoot) { Remove-Item -LiteralPath $ExtractRoot -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $ExtractRoot | Out-Null
  [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $ExtractRoot)
  $tool = Resolve-RepoPath "tools/package-smoke/voyage-package-smoke.ps1"
  $result = Invoke-CommandChecked "pwsh" @("-NoProfile", "-File", $tool, "-ExtractedRoot", $ExtractRoot) (Get-RepoRoot)
  $line = @($result.Stdout -split "`r?`n" | Where-Object { $_.StartsWith($SmokePrefix) })
  if ($line.Count -ne 1) { throw "Package smoke did not emit exactly one smoke summary." }
  return $line[0].Substring($SmokePrefix.Length) | ConvertFrom-Json
}

function New-RustupCargoRunner([string]$Path) {
  Set-Content -LiteralPath $Path -Value "@echo off`r`nrustup run 1.96.0 cargo %*`r`n" -Encoding ascii
  return $Path
}

$repoRoot = Get-RepoRoot
$version = (Get-Content -Raw -LiteralPath (Join-Path $repoRoot "VERSION")).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "VERSION must be semver-like." }

$zig = if ($ZigPath) { Resolve-RepoPath $ZigPath } else { Resolve-RepoPath "spikes/api-pg/toolchain/zig-x86_64-windows-0.15.2/zig.exe" }
if (-not (Test-Path -LiteralPath $zig)) { throw "Pinned Zig 0.15.2 executable was not found." }
$zigVersion = (& $zig version).Trim()
if ($zigVersion -ne "0.15.2") { throw "Pinned Zig must report 0.15.2, got $zigVersion." }

$tbLib = if ($TigerBeetleClientLib) {
  [System.IO.Path]::GetFullPath($TigerBeetleClientLib)
} else {
  "C:\Users\jcane\AppData\Local\Temp\hydra-feas-002\tigerbeetle-git\src\clients\c\lib\x86_64-windows\tb_client.lib"
}
$tbInclude = if ($TigerBeetleClientInclude) {
  [System.IO.Path]::GetFullPath($TigerBeetleClientInclude)
} else {
  "C:\Users\jcane\AppData\Local\Temp\hydra-feas-002\tigerbeetle-git\src\clients\c"
}
if (-not (Test-Path -LiteralPath $tbLib) -or -not (Test-Path -LiteralPath $tbInclude)) {
  throw "Approved TigerBeetle C client inputs are required. Pass -TigerBeetleClientLib and -TigerBeetleClientInclude."
}
if ((Get-FileSha256 $tbLib) -ne "1edf28ac840cc44ae98a8782d066da525df8257a6c90df921164d706ff232c02") {
  throw "TigerBeetle C client library hash does not match approved FEAS-002 evidence."
}
$tbHeader = Join-Path $tbInclude "tb_client.h"
if (-not (Test-Path -LiteralPath $tbHeader)) {
  throw "TigerBeetle C client header is required at tb_client.h."
}
if ((Get-FileSha256 $tbHeader) -ne "3ad1dd26fb67f3c89c971072cf22ad4a833971f6a40947ca562db2685587964d") {
  throw "TigerBeetle C client header hash does not match approved FEAS-002 evidence."
}

$output = Resolve-RepoPath $OutputRoot
$build = Resolve-RepoPath $BuildRoot
$reports = Resolve-RepoPath $ReportRoot
foreach ($path in @($output, $build, $reports)) {
  Assert-UnderRoot $path $repoRoot | Out-Null
  New-Item -ItemType Directory -Force -Path $path | Out-Null
}
$cargoRunner = New-RustupCargoRunner (Join-Path $build "cargo-rustup-1.96.cmd")

$artifactName = "$ArtifactPrefix`_$($version)_windows-x86_64.zip"
$zipPath = Join-Path $output $artifactName
$shaPath = "$zipPath.sha256"
$packageRoot = Join-Path $build "package-root"
$apiPrefix = Join-Path $build "api-prefix"
$extractRoot = Join-Path ([System.IO.Path]::GetTempPath()) "voyage vii package smoke - 測試"
$runtimeOutput = Resolve-RepoPath "apps/desktop/src-tauri/resources/runtime"
$desktopRoot = Resolve-RepoPath "apps/desktop"
$desktopTauriRoot = Resolve-RepoPath "apps/desktop/src-tauri"
$apiRoot = Resolve-RepoPath "modules/finance/adapters/zig-api"
$apiRevision = (Invoke-CommandChecked "git" @("log", "-1", "--format=%H", "--", "modules/finance/adapters/zig-api") $repoRoot).Stdout.Trim()

Assert-CleanTrackedInputs @(
  "VERSION",
  "apps/desktop/package.json",
  "apps/desktop/bun.lock",
  "apps/desktop/index.html",
  "apps/desktop/tsconfig.json",
  "apps/desktop/vite.config.ts",
  "apps/desktop/src",
  "apps/desktop/src-tauri/Cargo.toml",
  "apps/desktop/src-tauri/Cargo.lock",
  "apps/desktop/src-tauri/build.rs",
  "apps/desktop/src-tauri/tauri.conf.json",
  "apps/desktop/src-tauri/capabilities",
  "apps/desktop/src-tauri/permissions",
  "apps/desktop/src-tauri/src",
  "apps/desktop/src-tauri/tests",
  "runtime/sources.json",
  "tools/runtime-staging",
  "tools/package-smoke",
  "modules/finance/adapters/zig-api/build.zig",
  "modules/finance/adapters/zig-api/build.zig.zon",
  "modules/finance/adapters/zig-api/migrations",
  "modules/finance/adapters/zig-api/src",
  "modules/finance/adapters/zig-api/tests",
  "tools/package/windows/build-windows-zip.ps1"
)

Invoke-Step "install desktop dependencies" {
  Invoke-CommandChecked "bun" @("install", "--frozen-lockfile") $desktopRoot | Out-Null
}

Invoke-Step "build desktop frontend" {
  Invoke-CommandChecked "bun" @("run", "build") $desktopRoot | Out-Null
}

Invoke-Step "build desktop executable" {
  Invoke-CommandChecked "bun" @("run", "tauri", "build", "--runner", $cargoRunner, "--target", $Target, "--no-bundle", "--ci") $desktopRoot | Out-Null
}

Invoke-Step "stage verified runtime" {
  $args = @("-NoProfile", "-File", (Resolve-RepoPath "tools/runtime-staging/stage-runtime.ps1"))
  if ($Offline) { $args += "-Offline" }
  Invoke-CommandChecked "pwsh" $args $repoRoot | Out-Null
}

Invoke-Step "build API executable" {
  if (Test-Path -LiteralPath $apiPrefix) { Remove-Item -LiteralPath $apiPrefix -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $apiPrefix | Out-Null
  $sqliteSource = Join-Path $runtimeOutput "sqlite"
  Invoke-CommandChecked $zig @(
    "build",
    "-Dtarget=x86_64-windows-msvc",
    "-Doptimize=ReleaseSafe",
    "-Dsqlite-amalgamation=$sqliteSource",
    "-Dtb-client-lib=$tbLib",
    "-Dtb-client-include=$tbInclude",
    "--prefix",
    $apiPrefix
  ) $apiRoot | Out-Null
}

Invoke-Step "assemble portable package root" {
  if (Test-Path -LiteralPath $packageRoot) { Remove-Item -LiteralPath $packageRoot -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null

  $desktopExe = Join-Path $desktopTauriRoot "target/$Target/release/voyage-vii-desktop.exe"
  $apiExe = Join-Path $apiPrefix "bin/voyage-vii-api.exe"
  if (-not (Test-Path -LiteralPath $desktopExe)) { throw "Desktop release executable not found." }
  if (-not (Test-Path -LiteralPath $apiExe)) { throw "API release executable not found." }

  Copy-Item -LiteralPath $desktopExe -Destination (Join-Path $packageRoot $ProductExeName)
  $packagedRuntime = Join-Path $packageRoot "resources/runtime"
  Copy-CleanDirectory $runtimeOutput $packagedRuntime
  $packagedApi = Join-Path $packagedRuntime "api"
  New-Item -ItemType Directory -Force -Path $packagedApi | Out-Null
  Copy-Item -LiteralPath $apiExe -Destination (Join-Path $packagedApi "voyage-vii-api.exe") -Force
  Copy-CleanDirectory (Join-Path $apiRoot "migrations") (Join-Path $packagedApi "migrations")

  Set-PeSubsystemWindowsGui (Join-Path $packageRoot $ProductExeName)
  $apiHash = Get-FileSha256 (Join-Path $packagedRuntime "api/voyage-vii-api.exe")
  Write-FinalManifest $packagedRuntime $version $apiHash $apiRevision
  Assert-NoForbiddenPackageFiles $packageRoot
}

Invoke-Step "verify packaged PE inventory" {
  $desktopHeader = Assert-Pe (Join-Path $packageRoot $ProductExeName) "0x8664" ([uint16]2)
  $apiHeader = Assert-Pe (Join-Path $packageRoot "resources/runtime/api/voyage-vii-api.exe") "0x8664" $null
  $tbHeader = Assert-Pe (Join-Path $packageRoot "resources/runtime/tigerbeetle/tigerbeetle.exe") "0x8664" $null
  $script:peInventory = @(
    [pscustomobject]@{ path = $ProductExeName; machine = $desktopHeader.Machine; subsystem = $desktopHeader.Subsystem },
    [pscustomobject]@{ path = "resources/runtime/api/voyage-vii-api.exe"; machine = $apiHeader.Machine; subsystem = $apiHeader.Subsystem },
    [pscustomobject]@{ path = "resources/runtime/tigerbeetle/tigerbeetle.exe"; machine = $tbHeader.Machine; subsystem = $tbHeader.Subsystem }
  )
}

Invoke-Step "create ZIP and checksum" {
  New-ZipFromRoot $packageRoot $zipPath
  $zipHash = Get-FileSha256 $zipPath
  Set-Content -LiteralPath $shaPath -Value "$zipHash  $artifactName" -Encoding ascii
  Assert-ZipContents $zipPath @(
    $ProductExeName,
    "resources/runtime/manifest.json",
    "resources/runtime/api/voyage-vii-api.exe",
    "resources/runtime/api/migrations/001_schema_migrations.sql",
    "resources/runtime/sqlite/sqlite3.c",
    "resources/runtime/tigerbeetle/tigerbeetle.exe",
    "resources/runtime/THIRD-PARTY-NOTICES.txt"
  )
}

$smokeSummary = $null
if (-not $SkipSmoke) {
  Invoke-Step "extract and run PACKAGE-004 smoke harness" {
    $script:smokeSummary = Invoke-PackageSmoke $zipPath $extractRoot
  }
}

Invoke-Step "write packaging report" {
  $files = Get-ChildItem -LiteralPath $packageRoot -Recurse -File | ForEach-Object {
    [pscustomobject]@{
      path = $_.FullName.Substring($packageRoot.Length + 1).Replace("\", "/")
      size = $_.Length
      sha256 = Get-FileSha256 $_.FullName
    }
  } | Sort-Object path
  $report = [pscustomobject]@{
    schemaVersion = 1
    productVersion = $version
    target = $Target
    artifact = [pscustomobject]@{
      path = $zipPath
      sha256 = Get-FileSha256 $zipPath
      sha256File = $shaPath
    }
    apiRevision = $apiRevision
    zigVersion = $zigVersion
    peInventory = $peInventory
    fileCount = @($files).Count
    files = $files
    smoke = $smokeSummary
    residualRisks = @(
      "Desktop executable subsystem is patched to Windows GUI in the package copy; API/TigerBeetle child process creation visibility remains governed by runtime source outside PACKAGE-001 owned paths."
    )
  }
  $jsonPath = Join-Path $reports "last-run.json"
  Set-Content -LiteralPath $jsonPath -Value ($report | ConvertTo-Json -Depth 20) -Encoding utf8
  $smokeState = if ($smokeSummary) { "PASS" } else { "SKIPPED" }
  $md = @(
    "# Windows Package Report",
    "",
    "- artifact: ``$artifactName``",
    "- sha256: ``$($report.artifact.sha256)``",
    "- target: ``$Target``",
    "- API revision: ``$apiRevision``",
    "- smoke: $smokeState",
    "",
    "| Path | Machine | Subsystem |",
    "| --- | --- | --- |"
  )
  foreach ($pe in $peInventory) {
    $md += "| $($pe.path) | $($pe.machine) | $($pe.subsystem) |"
  }
  Set-Content -LiteralPath (Join-Path $reports "last-run.md") -Value ($md -join "`n") -Encoding utf8
  Write-Output "artifact: $zipPath"
  Write-Output "sha256: $($report.artifact.sha256)"
  Write-Output "report: $jsonPath"
}
