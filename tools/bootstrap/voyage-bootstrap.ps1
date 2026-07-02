#requires -Version 7.0

[CmdletBinding()]
param(
  [ValidateSet("compose", "desktop", "packaging", "all")]
  [string]$Profile = "all",
  [switch]$Offline
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
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
    throw "Path escapes repository root: $resolved"
  }
  return $resolved
}

function Assert-Windows11X64 {
  if (-not $IsWindows) {
    throw "Unsupported platform. Current bootstrap profiles are Windows 11 x64 only; other OS targets are deferred."
  }
  if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne [System.Runtime.InteropServices.Architecture]::X64) {
    throw "Unsupported architecture. Current bootstrap profiles require Windows 11 x64."
  }
  if ([Environment]::OSVersion.Version.Build -lt 22000) {
    throw "Unsupported Windows version. Current bootstrap profiles require Windows 11 x64."
  }
}

function Invoke-Logged {
  param(
    [string]$FilePath,
    [string[]]$Arguments,
    [string]$WorkingDirectory,
    [hashtable]$Environment = @{}
  )

  Write-Host "> $FilePath $($Arguments -join ' ')"
  $previous = @{}
  foreach ($key in $Environment.Keys) {
    $previous[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
    [Environment]::SetEnvironmentVariable($key, [string]$Environment[$key], "Process")
  }
  Push-Location $WorkingDirectory
  try {
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
      throw "Command failed with exit code $LASTEXITCODE`: $FilePath"
    }
  } finally {
    Pop-Location
    foreach ($key in $Environment.Keys) {
      [Environment]::SetEnvironmentVariable($key, $previous[$key], "Process")
    }
  }
}

function Get-CommandPath([string]$Name, [switch]$Required) {
  $command = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $command -and $Required) {
    throw "Missing required command '$Name'. Install the pinned toolchain documented in docs/planning/v2/DEPENDENCY-PINS.md."
  }
  return $command
}

function Get-CommandOutput([string]$FilePath, [string[]]$Arguments) {
  $output = & $FilePath @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed with exit code $LASTEXITCODE`: $FilePath $($Arguments -join ' ')`n$($output -join "`n")"
  }
  return ($output | Select-Object -First 1)
}

function Assert-CommandVersion([string]$Name, [string[]]$Arguments, [string]$Expected, [string]$Pattern) {
  $command = Get-CommandPath $Name -Required
  $version = [string](Get-CommandOutput $command.Source $Arguments)
  if ($version -notmatch $Pattern) {
    throw "$Name version mismatch. Expected $Expected from docs/planning/v2/DEPENDENCY-PINS.md; found '$version'."
  }
  return $command
}

function Assert-WebView2 {
  $clientId = "{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
  $keys = @(
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$clientId",
    "HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$clientId"
  )
  foreach ($key in $keys) {
    if (Test-Path $key) { return }
  }
  throw "Missing Microsoft Edge WebView2 Runtime. Install it for Windows desktop support."
}

function Test-ApiImagePin([string]$Image) {
  return $Image -match '^[^:@\s]+(?:/[^:@\s]+)*:0\.1\.0@sha256:[0-9a-f]{64}$'
}

function Initialize-ProjectCaches {
  $root = Get-RepoRoot
  $cacheRoot = Assert-UnderRoot (Resolve-RepoPath "tools/bootstrap/.cache") $root
  $null = New-Item -ItemType Directory -Force -Path $cacheRoot
  return $cacheRoot
}

function Invoke-ComposeProfile {
  Write-Host "profile: compose"
  Get-CommandPath "docker" -Required | Out-Null
  Invoke-Logged "docker" @("compose", "version") (Get-RepoRoot)
  $apiImage = [Environment]::GetEnvironmentVariable("VOYAGE_VII_API_IMAGE", "Process")
  if ([string]::IsNullOrWhiteSpace($apiImage)) {
    Write-Host "VOYAGE_VII_API_IMAGE is not set. Compose smoke needs an exact image pin like registry.example/voyage-vii-api:0.1.0@sha256:<64 lowercase hex>."
  } elseif (-not (Test-ApiImagePin $apiImage)) {
    throw "VOYAGE_VII_API_IMAGE must be an exact 0.1.0 digest pin: name:0.1.0@sha256:<64 lowercase hex>."
  } else {
    Invoke-Logged "docker" @("compose", "--file", "compose.yaml", "config", "--quiet") (Get-RepoRoot)
  }
  Write-Host "compose bootstrap is readiness-only; set VOYAGE_VII_API_IMAGE to an exact pinned API image before using scripts/compose/up.ps1."
}

function Invoke-DesktopProfile {
  Write-Host "profile: desktop"
  $root = Get-RepoRoot
  $cacheRoot = Initialize-ProjectCaches
  $bun = Assert-CommandVersion "bun" @("--version") "Bun 1.3.14" '^1\.3\.14$'
  Assert-CommandVersion "rustc" @("--version") "Rust 1.96.0" '^rustc 1\.96\.0\b' | Out-Null
  Assert-CommandVersion "cargo" @("--version") "Rust/Cargo 1.96.0" '^cargo 1\.96\.0\b' | Out-Null
  Assert-WebView2

  $bunCache = Assert-UnderRoot (Join-Path $cacheRoot "bun") $root
  $desktopDeps = Assert-UnderRoot (Join-Path $cacheRoot "desktop-deps") $root
  $cargoHome = Assert-UnderRoot (Join-Path $cacheRoot "cargo-home") $root
  $cargoTarget = Assert-UnderRoot (Join-Path $cacheRoot "cargo-target") $root
  $null = New-Item -ItemType Directory -Force -Path $bunCache, $desktopDeps, $cargoHome, $cargoTarget
  Copy-Item -LiteralPath (Resolve-RepoPath "apps/desktop/package.json") -Destination (Join-Path $desktopDeps "package.json") -Force
  Copy-Item -LiteralPath (Resolve-RepoPath "apps/desktop/bun.lock") -Destination (Join-Path $desktopDeps "bun.lock") -Force

  $bunArgs = @("install", "--frozen-lockfile")
  if ($Offline) { $bunArgs += "--offline" }
  Invoke-Logged $bun.Source $bunArgs $desktopDeps @{ BUN_INSTALL_CACHE_DIR = $bunCache }

  $cargoArgs = @("fetch", "--locked")
  if ($Offline) { $cargoArgs += "--offline" }
  Invoke-Logged "cargo" $cargoArgs (Resolve-RepoPath "apps/desktop/src-tauri") @{
    CARGO_HOME = $cargoHome
    CARGO_TARGET_DIR = $cargoTarget
  }
}

function Invoke-PackagingProfile {
  Write-Host "profile: packaging"
  $stageScript = Resolve-RepoPath "tools/runtime-staging/stage-runtime.ps1"
  $args = @("-NoProfile", "-File", $stageScript)
  if ($Offline) { $args += "-Offline" }
  Invoke-Logged "pwsh" $args (Get-RepoRoot)
}

Assert-Windows11X64

$profiles = if ($Profile -eq "all") {
  @("compose", "desktop", "packaging")
} else {
  @($Profile)
}

foreach ($item in $profiles) {
  switch ($item) {
    "compose" { Invoke-ComposeProfile }
    "desktop" { Invoke-DesktopProfile }
    "packaging" { Invoke-PackagingProfile }
  }
}

Write-Host "bootstrap complete: $Profile"
