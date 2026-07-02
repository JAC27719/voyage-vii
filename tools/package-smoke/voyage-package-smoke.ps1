#requires -Version 7.0

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$ExtractedRoot,
  [string]$DataRoot,
  [switch]$KeepDataRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-FullPath([string]$Path) {
  return [System.IO.Path]::GetFullPath($Path)
}

function Assert-Windows11X64 {
  if (-not $IsWindows -or [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne [System.Runtime.InteropServices.Architecture]::X64 -or [Environment]::OSVersion.Version.Build -lt 22000) {
    throw "PACKAGE-004 smoke requires Windows 11 x64."
  }
}

function New-SmokeDataRoot {
  $parent = Join-Path ([System.IO.Path]::GetTempPath()) "voyage-vii-package-smoke"
  $root = Join-Path $parent ([System.Guid]::NewGuid().ToString("N"))
  $resolvedParent = Resolve-FullPath $parent
  $resolvedRoot = Resolve-FullPath $root
  if (-not $resolvedRoot.StartsWith($resolvedParent + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Smoke data root escaped canonical parent."
  }
  New-Item -ItemType Directory -Force -Path $resolvedRoot | Out-Null
  Set-Content -LiteralPath (Join-Path $resolvedRoot ".voyage-package-smoke-root") -Value "sentinel" -Encoding ascii
  return $resolvedRoot
}

function Remove-SmokeDataRoot([string]$Root) {
  if ($KeepDataRoot) { return }
  $resolved = Resolve-FullPath $Root
  $parent = Resolve-FullPath (Join-Path ([System.IO.Path]::GetTempPath()) "voyage-vii-package-smoke")
  if (-not $resolved.StartsWith($parent + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing cleanup outside canonical package-smoke parent."
  }
  if (-not (Test-Path -LiteralPath (Join-Path $resolved ".voyage-package-smoke-root"))) {
    throw "Refusing cleanup without package-smoke sentinel."
  }
  Remove-Item -LiteralPath $resolved -Recurse -Force
}

function Find-DesktopExe([string]$Root) {
  $expected = Join-Path $Root "Voyage VII.exe"
  if (Test-Path -LiteralPath $expected) { return (Resolve-FullPath $expected) }
  $matches = @(Get-ChildItem -LiteralPath $Root -Filter "*.exe" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "Voyage|voyage" })
  if ($matches.Count -eq 1) { return $matches[0].FullName }
  throw "Could not find a single Voyage VII desktop executable in extracted package root."
}

function Test-PackageLayout([string]$Root, [string]$Exe) {
  $runtime = Join-Path $Root "resources/runtime"
  foreach ($path in @(
      $runtime,
      (Join-Path $runtime "manifest.json"),
      (Join-Path $runtime "api/voyage-vii-api.exe"),
      (Join-Path $runtime "tigerbeetle/tigerbeetle.exe"),
      (Join-Path $runtime "THIRD-PARTY-NOTICES.txt")
    )) {
    if (-not (Test-Path -LiteralPath $path)) {
      throw "Package smoke layout check failed: required runtime file is missing."
    }
  }
  if (-not (Test-Path -LiteralPath $Exe)) {
    throw "Package smoke layout check failed: desktop executable missing."
  }
}

function Invoke-Smoke([string]$Exe, [string]$Root) {
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $Exe
  [void]$psi.ArgumentList.Add("--smoke-test")
  [void]$psi.ArgumentList.Add("--data-root")
  [void]$psi.ArgumentList.Add($Root)
  $psi.WorkingDirectory = Split-Path -Parent $Exe
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $process = [System.Diagnostics.Process]::Start($psi)
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  if (-not $process.WaitForExit(120000)) {
    try { $process.Kill($true) } catch {}
    throw "Package smoke timed out after 120 seconds."
  }
  $stdout = $stdoutTask.Result
  $stderr = $stderrTask.Result
  if ($process.ExitCode -ne 0) {
    $redacted = $stderr -replace '[A-Za-z]:[\\/][^\r\n\t ]+', '[redacted-path]'
    $redacted = $redacted -replace 'Authorization:\s*Bearer\s+[A-Za-z0-9_-]+', 'Authorization: Bearer [redacted]'
    throw "Package smoke failed with exit code $($process.ExitCode): $redacted"
  }
  $lines = @($stdout -split "`r?`n" | Where-Object { $_.Trim() })
  if ($lines.Count -ne 1 -or -not $lines[0].StartsWith("VOYAGE_VII_SMOKE ")) {
    throw "Package smoke did not emit exactly one VOYAGE_VII_SMOKE line."
  }
  $json = $lines[0].Substring("VOYAGE_VII_SMOKE ".Length) | ConvertFrom-Json
  if ($json.schemaVersion -ne 1 -or $json.productVersion -ne "0.1.0" -or $json.target -ne "x86_64-pc-windows-msvc") {
    throw "Package smoke emitted an unexpected summary contract."
  }
  Write-Output $lines[0]
}

Assert-Windows11X64
$root = Resolve-FullPath $ExtractedRoot
$data = if ($DataRoot) { Resolve-FullPath $DataRoot } else { New-SmokeDataRoot }
$createdData = -not $DataRoot
try {
  if (-not (Test-Path -LiteralPath $data)) {
    New-Item -ItemType Directory -Force -Path $data | Out-Null
  }
  $exe = Find-DesktopExe $root
  Test-PackageLayout $root $exe
  Invoke-Smoke $exe $data
} finally {
  if ($createdData) {
    Remove-SmokeDataRoot $data
  }
}
