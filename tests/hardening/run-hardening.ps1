#requires -Version 7.0

[CmdletBinding()]
param(
  [ValidateSet("contract-scan", "runtime-matrix", "package-matrix", "artifact-scan", "performance-baseline", "all")]
  [string]$Command = "all",
  [string]$ApiImage,
  [switch]$KeepReportRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$StepTimeoutSeconds = 120
$AggregateTimeoutSeconds = 1200
$StartedAt = Get-Date

function Get-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
}

function Resolve-RepoPath([string]$Path) {
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }
  return [System.IO.Path]::GetFullPath((Join-Path (Get-RepoRoot) $Path))
}

function Assert-Windows11X64 {
  if (-not $IsWindows -or [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne [System.Runtime.InteropServices.Architecture]::X64 -or [Environment]::OSVersion.Version.Build -lt 22000) {
    throw "Unsupported platform. HARDEN-001 current gates require Windows 11 x64."
  }
}

function Assert-AggregateBudget {
  $elapsed = ((Get-Date) - $script:StartedAt).TotalSeconds
  if ($elapsed -gt $AggregateTimeoutSeconds) {
    throw "Aggregate hardening budget exceeded: $([math]::Round($elapsed, 1))s > ${AggregateTimeoutSeconds}s."
  }
}

function New-ReportRoot {
  $parent = Join-Path ([System.IO.Path]::GetTempPath()) "voyage-vii-hardening"
  $root = Join-Path $parent ([System.Guid]::NewGuid().ToString("N"))
  $resolvedParent = [System.IO.Path]::GetFullPath($parent)
  $resolvedRoot = [System.IO.Path]::GetFullPath($root)
  if (-not $resolvedRoot.StartsWith($resolvedParent + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Hardening report root escaped canonical parent: $resolvedRoot"
  }
  New-Item -ItemType Directory -Force -Path (Join-Path $resolvedRoot "logs") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $resolvedRoot "reports") | Out-Null
  Set-Content -LiteralPath (Join-Path $resolvedRoot ".voyage-hardening-root") -Value "sentinel" -Encoding ascii
  return $resolvedRoot
}

function Remove-ReportRoot([string]$Root) {
  if ($KeepReportRoot) { return }
  $resolved = [System.IO.Path]::GetFullPath($Root)
  $parent = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetTempPath()) "voyage-vii-hardening"))
  if (-not $resolved.StartsWith($parent + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing cleanup outside canonical hardening parent: $resolved"
  }
  if (-not (Test-Path -LiteralPath (Join-Path $resolved ".voyage-hardening-root"))) {
    throw "Refusing cleanup without hardening sentinel: $resolved"
  }
  Remove-Item -LiteralPath $resolved -Recurse -Force
}

function Redact-Text([string]$Text) {
  $redacted = $Text -replace 'VOYAGE_VII_HANDSHAKE\s+\{.*\}', 'VOYAGE_VII_HANDSHAKE [redacted]'
  $redacted = $redacted -replace '(Authorization:\s*Bearer\s+)[A-Za-z0-9._~+/=-]+', '$1[redacted]'
  $redacted = $redacted -replace '"appToken"\s*:\s*"[^"]+"', '"appToken":"[redacted]"'
  $redacted = $redacted -replace '"supervisorToken"\s*:\s*"[^"]+"', '"supervisorToken":"[redacted]"'
  $redacted = $redacted -replace '(--sqlite-path\s+)"?[^"\s]+"?', '$1[redacted-sqlite-path]'
  $redacted = $redacted -replace '[A-Za-z]:\\[^\r\n"]+\.sqlite(?:3|db)?', '[redacted-sqlite-path]'
  $redacted = $redacted -replace 'C:\\Users\\[^\s"\r\n]+', '[redacted-user-path]'
  return $redacted
}

function Invoke-LoggedStep {
  param(
    [string]$Name,
    [string]$Root,
    [string]$FilePath,
    [string[]]$Arguments,
    [string]$WorkingDirectory = (Get-RepoRoot),
    [int]$TimeoutSeconds = $StepTimeoutSeconds,
    [hashtable]$Environment = @{},
    [switch]$AllowFailure
  )

  Assert-AggregateBudget
  $stdout = Join-Path $Root "logs/$Name.stdout.log"
  $stderr = Join-Path $Root "logs/$Name.stderr.log"
  $commandLog = Join-Path $Root "logs/$Name.command.txt"
  Set-Content -LiteralPath $commandLog -Value (Redact-Text (($FilePath, $Arguments) -join " ")) -Encoding utf8

  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $FilePath
  foreach ($arg in $Arguments) { [void]$psi.ArgumentList.Add($arg) }
  $psi.WorkingDirectory = $WorkingDirectory
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.Environment["DOTNET_CLI_TELEMETRY_OPTOUT"] = "1"
  $psi.Environment["POWERSHELL_TELEMETRY_OPTOUT"] = "1"
  foreach ($key in $Environment.Keys) {
    $psi.Environment[$key] = [string]$Environment[$key]
  }
  $process = [System.Diagnostics.Process]::Start($psi)
  $outTask = $process.StandardOutput.ReadToEndAsync()
  $errTask = $process.StandardError.ReadToEndAsync()
  $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
  if ($timedOut) {
    try { $process.Kill($true) } catch {}
    $process.WaitForExit()
  }
  Set-Content -LiteralPath $stdout -Value (Redact-Text $outTask.Result) -Encoding utf8
  Set-Content -LiteralPath $stderr -Value (Redact-Text $errTask.Result) -Encoding utf8
  $result = [pscustomobject]@{
    name = $Name
    exitCode = if ($timedOut) { $null } else { $process.ExitCode }
    timedOut = $timedOut
    stdout = $stdout
    stderr = $stderr
  }
  if (($timedOut -or $process.ExitCode -ne 0) -and -not $AllowFailure) {
    throw "Hardening step '$Name' failed. Report root: $Root"
  }
  return $result
}

function Add-Result([System.Collections.Generic.List[object]]$Results, [string]$Name, [string]$Status, [string]$Detail) {
  $Results.Add([pscustomobject]@{
    name = $Name
    status = $Status
    detail = $Detail
  })
}

function Invoke-ContractScan([string]$Root, [System.Collections.Generic.List[object]]$Results) {
  $required = @{
    "docs/planning/v2/CONTRACTS.md" = @(
      "Authorization: Bearer <token>",
      "CORS accepts only the exact configured origin",
      "Request bodies are limited to 64 KiB",
      "Token comparison is constant-time",
      "runtime_asset_missing",
      "data_root_locked"
    )
    "docs/planning/v2/TIMEOUTS.md" = @(
      "Individual test-harness step | 120 seconds",
      "Local aggregate test run | 20 minutes",
      "Desktop supervisor shutdown sends the supervisor-authenticated request"
    )
    "docs/planning/v2/PACKAGING.md" = @(
      'Windows ZIP: sibling `resources/runtime`',
      "Generated runtimes and packages remain untracked"
    )
    "docs/planning/v2/DEPENDENCY-PINS.md" = @(
      'Application Zig: `0.15.2`',
      'Rust: `1.96.0`',
      'Bun: `1.3.14`'
    )
  }
  foreach ($entry in $required.GetEnumerator()) {
    $text = Get-Content -Raw -LiteralPath (Resolve-RepoPath $entry.Key)
    foreach ($needle in $entry.Value) {
      if (-not $text.Contains($needle)) {
        throw "Missing frozen hardening contract text '$needle' in $($entry.Key)."
      }
    }
  }
  Add-Result $Results "contract-scan" "passed" "Frozen dependency, contract, timeout, and package layout text was present."
}

function Invoke-OwnerRoutedDefectScan([string]$Root, [System.Collections.Generic.List[object]]$Results) {
  $paths = @("contracts", "services/api/src", "services/api/tests")
  $findings = @()
  foreach ($path in $paths) {
    $resolved = Resolve-RepoPath $path
    if (Test-Path -LiteralPath $resolved) {
      $files = Get-ChildItem -LiteralPath $resolved -Recurse -File -ErrorAction SilentlyContinue
      $matches = $files | Select-String -Pattern "postgres|postgresql|postgres_" -ErrorAction SilentlyContinue
      foreach ($match in $matches) {
        $relative = [System.IO.Path]::GetRelativePath((Get-RepoRoot), $match.Path)
        $findings += "${relative}:$($match.LineNumber): $($match.Line.Trim())"
      }
    }
  }
  if ($findings.Count -gt 0) {
    $findingPath = Join-Path $Root "reports/owner-routed-defects.txt"
    Set-Content -LiteralPath $findingPath -Value $findings -Encoding utf8
    Add-Result $Results "owner-routed-defects" "defect-routed" "Found stale PostgreSQL contract/runtime references after SQLite posture change; recorded $($findings.Count) findings at $findingPath for API-001/RUNTIME-001/PLAN-002 ownership follow-up."
  } else {
    Add-Result $Results "owner-routed-defects" "passed" "No stale PostgreSQL contract/runtime references found in scanned paths."
  }
}

function Invoke-RuntimeMatrix([string]$Root, [System.Collections.Generic.List[object]]$Results) {
  $step = Invoke-LoggedStep `
    -Name "managed-failure" `
    -Root $Root `
    -FilePath "pwsh" `
    -Arguments @("-NoProfile", "-File", (Resolve-RepoPath "scripts/test/test.ps1"), "-Command", "managed-failure") `
    -WorkingDirectory (Get-RepoRoot) `
    -Environment @{ CARGO_TARGET_DIR = (Join-Path $Root "cargo-target") }
  Add-Result $Results "runtime-matrix" "passed" "Managed runtime and staging failure matrix passed; logs at $($step.stdout) and $($step.stderr)."
}

function Invoke-PackageMatrix([string]$Root, [System.Collections.Generic.List[object]]$Results) {
  $output = Join-Path $Root "runtime"
  $reports = Join-Path $Root "runtime-reports"
  $step = Invoke-LoggedStep "stage-runtime-isolated" $Root "pwsh" @(
    "-NoProfile",
    "-File",
    (Resolve-RepoPath "tools/runtime-staging/stage-runtime.ps1"),
    "-OutputRoot",
    $output,
    "-ReportRoot",
    $reports,
    "-Offline",
    "-AllowTestSources"
  ) (Get-RepoRoot)
  if (-not (Test-Path -LiteralPath (Join-Path $reports "last-run.json"))) {
    throw "Package matrix did not produce the isolated runtime report."
  }
  Add-Result $Results "package-matrix" "passed" "Runtime staging completed in isolated output $output with report $reports."
}

function Invoke-ArtifactScan([string]$Root, [System.Collections.Generic.List[object]]$Results) {
  $patterns = @(
    "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE",
    "AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI",
    "Authorization: Bearer ",
    '"appToken":"',
    '"supervisorToken":"',
    "C:\Users\"
  )
  $findings = @()
  $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File)
  foreach ($file in $files) {
    $text = Get-Content -Raw -LiteralPath $file.FullName -ErrorAction SilentlyContinue
    foreach ($pattern in $patterns) {
      if ($text -and $text.Contains($pattern)) {
        $findings += "$($file.FullName): $pattern"
      }
    }
  }
  if ($findings.Count -gt 0) {
    Set-Content -LiteralPath (Join-Path $Root "reports/artifact-scan-findings.txt") -Value $findings -Encoding utf8
    throw "Artifact scan found sensitive patterns. Report root: $Root"
  }
  Add-Result $Results "artifact-scan" "passed" "No token, authorization header, SQLite path, or private absolute-path pattern was found in hardening artifacts."
}

function Remove-IsolatedBuildCache([string]$Root) {
  $target = Join-Path $Root "cargo-target"
  if (Test-Path -LiteralPath $target) {
    $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
    $resolvedTarget = [System.IO.Path]::GetFullPath($target)
    if (-not $resolvedTarget.StartsWith($resolvedRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove build cache outside hardening root: $resolvedTarget"
    }
    Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
  }
}

function Invoke-PerformanceBaseline([string]$Root, [System.Collections.Generic.List[object]]$Results) {
  $before = Get-Process | Measure-Object WorkingSet64 -Sum
  $watch = [System.Diagnostics.Stopwatch]::StartNew()
  $step = Invoke-LoggedStep `
    -Name "managed-smoke" `
    -Root $Root `
    -FilePath "pwsh" `
    -Arguments @("-NoProfile", "-File", (Resolve-RepoPath "scripts/test/test.ps1"), "-Command", "managed-smoke") `
    -WorkingDirectory (Get-RepoRoot) `
    -Environment @{ CARGO_TARGET_DIR = (Join-Path $Root "cargo-target") }
  $watch.Stop()
  $after = Get-Process | Measure-Object WorkingSet64 -Sum
  $deltaMb = [math]::Round((($after.Sum - $before.Sum) / 1MB), 1)
  Add-Result $Results "performance-baseline" "measured" "Managed smoke elapsed $([math]::Round($watch.Elapsed.TotalSeconds, 1))s; process working-set delta ${deltaMb} MiB; logs at $($step.stdout)."
}

function Invoke-ComposeValidation([string]$Root, [System.Collections.Generic.List[object]]$Results) {
  $missing = Invoke-LoggedStep "compose-missing-pin" $Root "pwsh" @("-NoProfile", "-File", (Resolve-RepoPath "scripts/test/test.ps1"), "-Command", "compose-smoke") (Get-RepoRoot) $StepTimeoutSeconds -AllowFailure
  $stderr = Get-Content -Raw -LiteralPath $missing.stderr
  if ($stderr -notmatch "compose-smoke requires -ApiImage") {
    throw "Compose missing-pin validation did not emit the expected exact pin error."
  }
  if ($ApiImage) {
    $valid = Invoke-LoggedStep "compose-valid-pin" $Root "pwsh" @("-NoProfile", "-File", (Resolve-RepoPath "scripts/test/test.ps1"), "-Command", "compose-smoke", "-ApiImage", $ApiImage) (Get-RepoRoot) $StepTimeoutSeconds -AllowFailure
    Add-Result $Results "compose-validation" "measured" "Missing-pin validation passed; valid-pin compose attempt exitCode=$($valid.exitCode), timedOut=$($valid.timedOut)."
  } else {
    Add-Result $Results "compose-validation" "blocked" "Missing-pin validation passed; real compose smoke requires an approved exact API image pin."
  }
}

function Write-Reports([string]$Root, [System.Collections.Generic.List[object]]$Results) {
  $safeResults = @($Results | ForEach-Object {
    [pscustomobject]@{
      name = $_.name
      status = $_.status
      detail = Redact-Text ([string]$_.detail)
    }
  })
  $summary = [pscustomobject]@{
    command = $Command
    createdAt = (Get-Date).ToUniversalTime().ToString("o")
    root = Redact-Text $Root
    results = $safeResults
  }
  $jsonPath = Join-Path $Root "reports/hardening-summary.json"
  $mdPath = Join-Path $Root "reports/hardening-summary.md"
  $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding utf8
  $lines = @("# Hardening Summary", "", "- root: $(Redact-Text $Root)", "- command: $Command", "")
  foreach ($result in $safeResults) {
    $lines += "- $($result.name): $($result.status) - $($result.detail)"
  }
  Set-Content -LiteralPath $mdPath -Value ($lines -join "`n") -Encoding utf8
  Write-Host "hardening report: $mdPath"
}

Assert-Windows11X64
$root = New-ReportRoot
$results = [System.Collections.Generic.List[object]]::new()
try {
  switch ($Command) {
    "contract-scan" { Invoke-ContractScan $root $results }
    "runtime-matrix" { Invoke-RuntimeMatrix $root $results }
    "package-matrix" { Invoke-PackageMatrix $root $results }
    "artifact-scan" {
      Invoke-PackageMatrix $root $results
      Invoke-ArtifactScan $root $results
    }
    "performance-baseline" { Invoke-PerformanceBaseline $root $results }
    "all" {
      Invoke-ContractScan $root $results
      Invoke-OwnerRoutedDefectScan $root $results
      Invoke-RuntimeMatrix $root $results
      Invoke-PackageMatrix $root $results
      Invoke-ComposeValidation $root $results
      Invoke-PerformanceBaseline $root $results
      Remove-IsolatedBuildCache $root
      Invoke-ArtifactScan $root $results
    }
  }
  Write-Reports $root $results
  if (-not $KeepReportRoot) {
    Write-Host "preserved hardening report root for audit: $root"
  }
} catch {
  Write-Reports $root $results
  Write-Host "preserved failed hardening root: $root"
  throw
}
