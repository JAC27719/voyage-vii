#requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$tool = Join-Path $repo "tools/package-smoke/voyage-package-smoke.ps1"
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("voyage-vii-package-smoke-tests-" + [System.Guid]::NewGuid().ToString("N"))

function New-FixturePackage([string]$Name) {
  $root = Join-Path $temp $Name
  New-Item -ItemType Directory -Force -Path (Join-Path $root "resources/runtime/api") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $root "resources/runtime/tigerbeetle") | Out-Null
  Set-Content -LiteralPath (Join-Path $root "Voyage VII.exe") -Value "fixture" -Encoding ascii
  Set-Content -LiteralPath (Join-Path $root "resources/runtime/manifest.json") -Value "{}" -Encoding ascii
  Set-Content -LiteralPath (Join-Path $root "resources/runtime/api/voyage-vii-api.exe") -Value "api" -Encoding ascii
  Set-Content -LiteralPath (Join-Path $root "resources/runtime/tigerbeetle/tigerbeetle.exe") -Value "tb" -Encoding ascii
  Set-Content -LiteralPath (Join-Path $root "resources/runtime/THIRD-PARTY-NOTICES.txt") -Value "notices" -Encoding ascii
  return $root
}

function Expect-Fail([scriptblock]$Block, [string]$Pattern) {
  try {
    & $Block
    throw "Expected failure matching '$Pattern'."
  } catch {
    if ($_.Exception.Message -notmatch $Pattern) {
      throw
    }
  }
}

New-Item -ItemType Directory -Force -Path $temp | Out-Null
try {
  $missingExe = Join-Path $temp "missing-exe"
  New-Item -ItemType Directory -Force -Path (Join-Path $missingExe "resources/runtime/api") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $missingExe "resources/runtime/tigerbeetle") | Out-Null
  Set-Content -LiteralPath (Join-Path $missingExe "resources/runtime/manifest.json") -Value "{}" -Encoding ascii
  Expect-Fail { & $tool -ExtractedRoot $missingExe -DataRoot (Join-Path $temp "data1") } "desktop executable"

  $missingRuntime = New-FixturePackage "missing-runtime"
  Remove-Item -LiteralPath (Join-Path $missingRuntime "resources/runtime/api/voyage-vii-api.exe") -Force
  Expect-Fail { & $tool -ExtractedRoot $missingRuntime -DataRoot (Join-Path $temp "data2") } "missing"

  $validLayout = New-FixturePackage "valid-layout"
  Expect-Fail { & $tool -ExtractedRoot $validLayout -DataRoot (Join-Path $temp "data3") } "Package smoke failed|not a valid application"

  Write-Host "package smoke adapter tests passed"
} finally {
  Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
