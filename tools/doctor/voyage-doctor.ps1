#requires -Version 7.0

[CmdletBinding()]
param(
  [switch]$Json
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

function Test-UnderRoot([string]$Path, [string]$Root) {
  $resolved = [System.IO.Path]::GetFullPath($Path)
  $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
  $rootWithSeparator = $resolvedRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
  return $resolved -eq $resolvedRoot -or $resolved.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-CommandVersion([string]$Name, [string[]]$Arguments) {
  $command = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $command) {
    return [pscustomobject]@{ name = $Name; found = $false; path = $null; version = $null; ok = $false }
  }
  $output = try {
    (& $command.Source @Arguments 2>&1 | Select-Object -First 1) -join "`n"
  } catch {
    $_.Exception.Message
  }
  return [pscustomobject]@{ name = $Name; found = $true; path = $command.Source; version = $output; ok = $true }
}

function Get-PinnedCommandVersion([string]$Name, [string[]]$Arguments, [string]$Expected, [string]$Pattern) {
  $result = Get-CommandVersion $Name $Arguments
  $result | Add-Member -NotePropertyName expected -NotePropertyValue $Expected
  $result.ok = $result.found -and [string]$result.version -match $Pattern
  return $result
}

function Test-DockerReady {
  $docker = Get-Command "docker" -ErrorAction SilentlyContinue
  if (-not $docker) {
    return [pscustomobject]@{ found = $false; ready = $false; compose = $false; message = "Docker CLI is missing." }
  }
  $info = & $docker.Source "info" "--format" "{{.ServerVersion}}" 2>&1
  $infoText = ($info -join "`n")
  $ready = $LASTEXITCODE -eq 0 -and $infoText -notmatch "error during connect|access is denied|permission denied"
  $compose = $false
  if ($ready) {
    & $docker.Source "compose" "version" *> $null
    $compose = $LASTEXITCODE -eq 0
  }
  return [pscustomobject]@{
    found = $true
    ready = $ready
    compose = $compose
    message = if ($ready) { "Docker engine $infoText is reachable." } else { $infoText }
  }
}

function Test-ApiImagePin {
  $image = [Environment]::GetEnvironmentVariable("VOYAGE_VII_API_IMAGE", "Process")
  $ok = -not [string]::IsNullOrWhiteSpace($image) -and $image -match '^[^:@\s]+(?:/[^:@\s]+)*:0\.1\.0@sha256:[0-9a-f]{64}$'
  return [pscustomobject]@{
    set = -not [string]::IsNullOrWhiteSpace($image)
    ok = $ok
    value = if ($image) { $image -replace '@sha256:[0-9a-f]{64}$', '@sha256:[redacted-digest]' } else { $null }
    message = if ($ok) { "Exact 0.1.0 digest pin is present." } else { "Set VOYAGE_VII_API_IMAGE to name:0.1.0@sha256:<64 lowercase hex> before compose smoke runs." }
  }
}

function Test-WebView2 {
  if (-not $IsWindows) {
    return [pscustomobject]@{ found = $false; message = "WebView2 is only required on Windows." }
  }
  $clientId = "{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
  $keys = @(
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$clientId",
    "HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$clientId"
  )
  foreach ($key in $keys) {
    if (Test-Path $key) {
      $props = Get-ItemProperty $key
      return [pscustomobject]@{ found = $true; version = $props.pv; message = "WebView2 runtime found." }
    }
  }
  return [pscustomobject]@{ found = $false; version = $null; message = "Install Microsoft Edge WebView2 Runtime for Tauri desktop support." }
}

function Test-WritablePath([string]$Path) {
  $root = Get-RepoRoot
  $resolved = [System.IO.Path]::GetFullPath($Path)
  if (-not (Test-UnderRoot $resolved $root)) {
    return [pscustomobject]@{ path = $resolved; writable = $false; message = "Path is outside the repository." }
  }
  try {
    $null = New-Item -ItemType Directory -Force -Path $resolved
    $probe = Join-Path $resolved ".voyage-doctor-$([System.Guid]::NewGuid().ToString("N"))"
    Set-Content -LiteralPath $probe -Value "ok" -NoNewline -Encoding ascii
    Remove-Item -LiteralPath $probe -Force
    return [pscustomobject]@{ path = $resolved; writable = $true; message = "Writable." }
  } catch {
    return [pscustomobject]@{ path = $resolved; writable = $false; message = $_.Exception.Message }
  }
}

$root = Get-RepoRoot
$platform = [pscustomobject]@{
  os = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
  architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
  windowsBuild = [Environment]::OSVersion.Version.Build
  supported = $IsWindows -and [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq [System.Runtime.InteropServices.Architecture]::X64 -and [Environment]::OSVersion.Version.Build -ge 22000
  message = if ($IsWindows) { "Windows 11 x64 is the current supported target." } else { "Non-Windows targets are deferred and unsupported for current operations." }
}

$report = [pscustomobject]@{
  schemaVersion = 1
  repository = $root
  platform = $platform
  tools = @(
    Get-PinnedCommandVersion "pwsh" @("--version") "PowerShell 7 or newer" '^PowerShell 7\.'
    Get-CommandVersion "git" @("--version")
    Get-PinnedCommandVersion "bun" @("--version") "1.3.14" '^1\.3\.14$'
    Get-PinnedCommandVersion "rustc" @("--version") "1.96.0" '^rustc 1\.96\.0\b'
    Get-PinnedCommandVersion "cargo" @("--version") "1.96.0" '^cargo 1\.96\.0\b'
    Get-PinnedCommandVersion "zig" @("version") "0.15.2" '^0\.15\.2$'
    Get-CommandVersion "docker" @("--version")
    Get-CommandVersion "cl" @()
    Get-CommandVersion "link" @()
    Get-CommandVersion "rc" @("/?")
  )
  docker = Test-DockerReady
  composeApiImage = Test-ApiImagePin
  webView2 = Test-WebView2
  writablePaths = @(
    Test-WritablePath (Resolve-RepoPath "tools/bootstrap/.cache")
    Test-WritablePath (Resolve-RepoPath "tools/runtime-staging/.cache")
    Test-WritablePath (Resolve-RepoPath "tools/runtime-staging/reports")
    Test-WritablePath (Resolve-RepoPath "apps/desktop/src-tauri/resources")
  )
  instructions = @(
    "Install pinned toolchains from docs/planning/v2/DEPENDENCY-PINS.md.",
    "Install Docker Desktop with Compose v2 for compose profile readiness.",
    "Install Microsoft Edge WebView2 Runtime for Windows desktop support.",
    "Run scripts/bootstrap/bootstrap.ps1 -Profile desktop for project-local frontend and Rust dependency preparation.",
    "Run scripts/bootstrap/bootstrap.ps1 -Profile packaging to reuse the runtime staging cache."
  )
}

if ($Json) {
  $report | ConvertTo-Json -Depth 10
  return
}

Write-Host "Voyage VII doctor"
Write-Host "repository: $($report.repository)"
Write-Host "platform: $($report.platform.os) / $($report.platform.architecture) / supported=$($report.platform.supported)"
Write-Host ""
Write-Host "tools"
foreach ($tool in $report.tools) {
  $expected = if ($tool.PSObject.Properties["expected"]) { "; expected=$($tool.expected)" } else { "" }
  Write-Host ("- {0}: found={1}; ok={2}; version={3}{4}" -f $tool.name, $tool.found, $tool.ok, $tool.version, $expected)
}
Write-Host ""
Write-Host "docker: ready=$($report.docker.ready); compose=$($report.docker.compose); $($report.docker.message)"
Write-Host "compose image: ok=$($report.composeApiImage.ok); $($report.composeApiImage.message)"
Write-Host "webview2: found=$($report.webView2.found); $($report.webView2.message)"
Write-Host ""
Write-Host "writable paths"
foreach ($path in $report.writablePaths) {
  Write-Host ("- {0}: writable={1}; {2}" -f $path.path, $path.writable, $path.message)
}
Write-Host ""
Write-Host "instructions"
foreach ($instruction in $report.instructions) {
  Write-Host "- $instruction"
}
