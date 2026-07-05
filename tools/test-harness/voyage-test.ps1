#requires -Version 7.0

[CmdletBinding()]
param(
  [ValidateSet("unit", "managed-smoke", "managed-failure", "package-smoke", "all")]
  [string]$Command = "all",
  [switch]$KeepSuccessfulRoots
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$StepTimeoutSeconds = 120
$AggregateTimeoutSeconds = 1200
$StartedAt = Get-Date
$env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"
$env:POWERSHELL_TELEMETRY_OPTOUT = "1"
$env:VSCMD_SKIP_SENDTELEMETRY = "1"

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
    throw "Unsupported platform. Current cross-stack gates require Windows 11 x64; non-Windows execution is informational only."
  }
}

function Assert-AggregateBudget {
  $elapsed = ((Get-Date) - $script:StartedAt).TotalSeconds
  if ($elapsed -gt $AggregateTimeoutSeconds) {
    throw "Aggregate test budget exceeded: $([math]::Round($elapsed, 1))s > ${AggregateTimeoutSeconds}s."
  }
}

function New-TestRoot([string]$Name) {
  $parent = Join-Path ([System.IO.Path]::GetTempPath()) "voyage-vii-tests"
  $root = Join-Path $parent ("$Name-$([System.Guid]::NewGuid().ToString("N"))")
  $resolvedParent = [System.IO.Path]::GetFullPath($parent)
  $resolvedRoot = [System.IO.Path]::GetFullPath($root)
  if (-not $resolvedRoot.StartsWith($resolvedParent + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Temporary root escaped canonical parent: $resolvedRoot"
  }
  New-Item -ItemType Directory -Force -Path $resolvedRoot | Out-Null
  Set-Content -LiteralPath (Join-Path $resolvedRoot ".voyage-test-root") -Value "sentinel" -Encoding ascii
  New-Item -ItemType Directory -Force -Path (Join-Path $resolvedRoot "logs") | Out-Null
  return $resolvedRoot
}

function Remove-TestRoot([string]$Root) {
  if ($KeepSuccessfulRoots) { return }
  $resolved = [System.IO.Path]::GetFullPath($Root)
  $parent = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetTempPath()) "voyage-vii-tests"))
  $sentinel = Join-Path $resolved ".voyage-test-root"
  if (-not $resolved.StartsWith($parent + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing cleanup outside canonical test parent: $resolved"
  }
  if (-not (Test-Path -LiteralPath $sentinel)) {
    throw "Refusing cleanup without sentinel: $resolved"
  }
  Remove-Item -LiteralPath $resolved -Recurse -Force
}

function Redact-Log([string]$Text) {
  $redacted = $Text -replace 'VOYAGE_VII_HANDSHAKE\s+\{.*\}', 'VOYAGE_VII_HANDSHAKE [redacted]'
  $redacted = $redacted -replace '(Authorization:\s*Bearer\s+)[A-Za-z0-9._~+/=-]+', '$1[redacted]'
  $redacted = $redacted -replace '"appToken"\s*:\s*"[^"]+"', '"appToken":"[redacted]"'
  $redacted = $redacted -replace '"supervisorToken"\s*:\s*"[^"]+"', '"supervisorToken":"[redacted]"'
  $redacted = $redacted -replace '(--sqlite-path\s+)"?[^"\s]+"?', '$1[redacted-sqlite-path]'
  $redacted = $redacted -replace '[A-Za-z]:\\[^\r\n"]+\.sqlite(?:3|db)?', '[redacted-sqlite-path]'
  return $redacted
}

function Write-ProcessInventory([string]$Root, [string]$Name) {
  $path = Join-Path $Root "logs/$Name-processes.txt"
  Get-Process | Sort-Object ProcessName, Id | ForEach-Object {
    "{0}`t{1}" -f $_.Id, $_.ProcessName
  } | Set-Content -LiteralPath $path -Encoding utf8
  return $path
}

function Format-CommandLine([string]$FilePath, [string[]]$Arguments) {
  $parts = @($FilePath) + $Arguments
  return ($parts | ForEach-Object {
    if ($_ -match '[\s"]') {
      '"' + ($_ -replace '"', '\"') + '"'
    } else {
      $_
    }
  }) -join " "
}

function Get-ProcessParentId([int]$ProcessId) {
  if (-not ("VoyageProcessQuery" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class VoyageProcessQuery {
  [StructLayout(LayoutKind.Sequential)]
  private struct PROCESS_BASIC_INFORMATION {
    public IntPtr Reserved1;
    public IntPtr PebBaseAddress;
    public IntPtr Reserved2_0;
    public IntPtr Reserved2_1;
    public IntPtr UniqueProcessId;
    public IntPtr InheritedFromUniqueProcessId;
  }

  [DllImport("ntdll.dll")]
  private static extern int NtQueryInformationProcess(
    IntPtr processHandle,
    int processInformationClass,
    ref PROCESS_BASIC_INFORMATION processInformation,
    int processInformationLength,
    out int returnLength);

  public static int ParentProcessId(IntPtr processHandle) {
    PROCESS_BASIC_INFORMATION info = new PROCESS_BASIC_INFORMATION();
    int returnLength;
    int status = NtQueryInformationProcess(
      processHandle,
      0,
      ref info,
      Marshal.SizeOf(typeof(PROCESS_BASIC_INFORMATION)),
      out returnLength);
    if (status != 0) {
      return -1;
    }
    return info.InheritedFromUniqueProcessId.ToInt32();
  }
}
"@
  }

  try {
    $process = [System.Diagnostics.Process]::GetProcessById($ProcessId)
    return [VoyageProcessQuery]::ParentProcessId($process.Handle)
  } catch {
    return -1
  }
}

function Get-DescendantProcesses([int]$ParentId) {
  $all = @(Get-Process | ForEach-Object {
    [pscustomobject]@{
      ProcessId = $_.Id
      ParentProcessId = Get-ProcessParentId $_.Id
      Name = $_.ProcessName
    }
  })
  $pending = @($ParentId)
  $descendants = @()
  while ($pending.Count -gt 0) {
    $current = $pending[0]
    $pending = @($pending | Select-Object -Skip 1)
    $children = @($all | Where-Object { $_.ParentProcessId -eq $current })
    foreach ($child in $children) {
      $descendants += $child
      $pending += [int]$child.ProcessId
    }
  }
  return $descendants
}

function Assert-NoDescendantProcesses([string]$Name, [int]$ParentId, [string]$Root) {
  Start-Sleep -Milliseconds 250
  $descendants = @(Get-DescendantProcesses $ParentId)
  if ($descendants.Count -gt 0) {
    $inventory = Join-Path $Root "logs/$Name-descendants.txt"
    $descendants | ForEach-Object {
      "{0}`t{1}`tparent={2}" -f $_.ProcessId, $_.Name, $_.ParentProcessId
    } | Set-Content -LiteralPath $inventory -Encoding utf8
    throw "Step '$Name' left descendant processes running. Preserved root: $Root"
  }
}

function Resolve-ProcessCommand {
  param(
    [string]$FilePath,
    [string[]]$Arguments
  )

  $command = Get-Command $FilePath -ErrorAction SilentlyContinue
  if ($null -eq $command) {
    return @{
      FilePath = $FilePath
      Arguments = $Arguments
    }
  }

  $source = $command.Source
  if ([string]::IsNullOrWhiteSpace($source)) {
    $source = $command.Path
  }
  if ([string]::IsNullOrWhiteSpace($source)) {
    $source = $command.Name
  }

  if ([System.IO.Path]::GetExtension($source) -ieq ".ps1") {
    return @{
      FilePath = "pwsh"
      Arguments = @("-NoProfile", "-File", $source) + $Arguments
    }
  }

  return @{
    FilePath = $source
    Arguments = $Arguments
  }
}

function Invoke-Step {
  param(
    [string]$Name,
    [string]$Root,
    [string]$FilePath,
    [string[]]$Arguments,
    [string]$WorkingDirectory = (Get-RepoRoot),
    [int]$TimeoutSeconds = $StepTimeoutSeconds,
    [hashtable]$Environment = @{}
  )

  Assert-AggregateBudget
  $stdout = Join-Path $Root "logs/$Name.stdout.log"
  $stderr = Join-Path $Root "logs/$Name.stderr.log"
  $resolvedCommand = Resolve-ProcessCommand $FilePath $Arguments
  Set-Content -LiteralPath (Join-Path $Root "logs/$Name.command.txt") -Value (Redact-Log (Format-CommandLine $resolvedCommand.FilePath $resolvedCommand.Arguments)) -Encoding utf8
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $resolvedCommand.FilePath
  foreach ($arg in $resolvedCommand.Arguments) { [void]$psi.ArgumentList.Add($arg) }
  $psi.WorkingDirectory = $WorkingDirectory
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.Environment["DOTNET_CLI_TELEMETRY_OPTOUT"] = "1"
  $psi.Environment["POWERSHELL_TELEMETRY_OPTOUT"] = "1"
  $psi.Environment["VSCMD_SKIP_SENDTELEMETRY"] = "1"
  foreach ($key in $Environment.Keys) {
    $psi.Environment[$key] = [string]$Environment[$key]
  }
  $process = [System.Diagnostics.Process]::Start($psi)
  $outTask = $process.StandardOutput.ReadToEndAsync()
  $errTask = $process.StandardError.ReadToEndAsync()
  if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
    try { $process.Kill($true) } catch {}
    $process.WaitForExit()
    Set-Content -LiteralPath $stdout -Value (Redact-Log $outTask.Result) -Encoding utf8
    Set-Content -LiteralPath $stderr -Value (Redact-Log $errTask.Result) -Encoding utf8
    Assert-NoDescendantProcesses $Name $process.Id $Root
    throw "Step '$Name' timed out after ${TimeoutSeconds}s. Preserved root: $Root"
  }
  Set-Content -LiteralPath $stdout -Value (Redact-Log $outTask.Result) -Encoding utf8
  Set-Content -LiteralPath $stderr -Value (Redact-Log $errTask.Result) -Encoding utf8
  Assert-NoDescendantProcesses $Name $process.Id $Root
  if ($process.ExitCode -ne 0) {
    throw "Step '$Name' failed with exit code $($process.ExitCode). Preserved root: $Root"
  }
}

function Invoke-WithRoot([string]$Name, [scriptblock]$Body) {
  $root = New-TestRoot $Name
  Write-ProcessInventory $root "before" | Out-Null
  try {
    & $Body $root
    Write-ProcessInventory $root "after" | Out-Null
    Remove-TestRoot $root
    Write-Host "$Name passed"
  } catch {
    Write-ProcessInventory $root "failed" | Out-Null
    Write-Host "preserved failed root: $root"
    throw
  }
}

function Invoke-Unit {
  Invoke-WithRoot "unit" {
    param($root)
    Invoke-Step "desktop-typecheck" $root "bun" @("run", "typecheck") (Resolve-RepoPath "apps/desktop")
    Invoke-Step "desktop-lint" $root "bun" @("run", "lint") (Resolve-RepoPath "apps/desktop")
    Invoke-Step "desktop-format-check" $root "bun" @("run", "format-check") (Resolve-RepoPath "apps/desktop")
    Invoke-Step "desktop-rust-tests" $root "rustup" @("run", "1.96.0", "cargo", "test", "--locked") (Resolve-RepoPath "apps/desktop/src-tauri")
    Invoke-Step "runtime-staging-tests" $root "pwsh" @("-NoProfile", "-File", (Resolve-RepoPath "tests/runtime-staging/run-tests.ps1")) (Get-RepoRoot)
    Invoke-Step "api-zig-tests" $root "zig" @("build", "test") (Resolve-RepoPath "modules/finance/adapters/zig-api")
  }
}

function Invoke-ManagedSmoke {
  Invoke-WithRoot "managed-smoke" {
    param($root)
    Invoke-Step "desktop-runtime-tests" $root "rustup" @("run", "1.96.0", "cargo", "test", "--locked", "runtime") (Resolve-RepoPath "apps/desktop/src-tauri")
  }
}

function Invoke-ManagedFailure {
  Invoke-WithRoot "managed-failure" {
    param($root)
    Invoke-Step "desktop-runtime-failure-tests" $root "rustup" @("run", "1.96.0", "cargo", "test", "--locked", "runtime") (Resolve-RepoPath "apps/desktop/src-tauri")
    Invoke-Step "runtime-staging-failure-tests" $root "pwsh" @("-NoProfile", "-File", (Resolve-RepoPath "tests/runtime-staging/run-tests.ps1")) (Get-RepoRoot)
    Invoke-HarnessSelfTests $root
  }
}

function Invoke-PackageSmoke {
  Invoke-WithRoot "package-smoke" {
    param($root)
    Invoke-Step `
      -Name "stage-runtime-offline" `
      -Root $root `
      -FilePath "pwsh" `
      -Arguments @(
        "-NoProfile",
        "-File",
        (Resolve-RepoPath "tools/runtime-staging/stage-runtime.ps1"),
        "-OutputRoot",
        (Join-Path $root "runtime"),
        "-ReportRoot",
        (Join-Path $root "reports"),
        "-Offline",
        "-AllowTestSources"
      ) `
      -WorkingDirectory (Get-RepoRoot)
  }
}

function Invoke-HarnessSelfTests([string]$Root) {
  $escape = Join-Path ([System.IO.Path]::GetTempPath()) "voyage-vii-tests-escape"
  New-Item -ItemType Directory -Force -Path $escape | Out-Null
  try {
    Remove-TestRoot $escape
    throw "Cleanup escape prevention did not reject outside root."
  } catch {
    if ($_.Exception.Message -notmatch "outside canonical test parent|without sentinel") { throw }
  } finally {
    Remove-Item -LiteralPath $escape -Recurse -Force -ErrorAction SilentlyContinue
  }

  $lock = Join-Path $Root "stale.lock"
  Set-Content -LiteralPath $lock -Value "stale" -Encoding ascii
  if (-not (Test-Path -LiteralPath $lock)) { throw "Stale lock fixture was not created." }

  $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
  $listener.Start()
  try {
    $port = $listener.LocalEndpoint.Port
    if ($port -le 0) { throw "Occupied-resource fixture did not bind a port." }
  } finally {
    $listener.Stop()
  }

  $unwritable = Join-Path $Root "unwritable"
  New-Item -ItemType Directory -Force -Path $unwritable | Out-Null
  Set-Content -LiteralPath (Join-Path $unwritable "README.txt") -Value "fixture" -Encoding ascii

  $corrupt = Join-Path $Root "corrupt-asset.zip"
  Set-Content -LiteralPath $corrupt -Value "not a zip" -Encoding ascii

  $badHandshake = 'VOYAGE_VII_HANDSHAKE {"protocolVersion":2,"appToken":"secret","supervisorToken":"secret"}'
  $redacted = Redact-Log $badHandshake
  if ($redacted -match "secret" -or $redacted -notmatch "\[redacted\]") {
    throw "Malformed handshake redaction failed."
  }
  $sqliteLog = 'voyage-vii-api serve --sqlite-path C:\Users\someone\AppData\Local\Voyage\data.sqlite3'
  if ((Redact-Log $sqliteLog) -match "someone|data\.sqlite3") {
    throw "SQLite path redaction failed."
  }

  try {
    Invoke-Step "intentional-timeout" $Root "pwsh" @("-NoProfile", "-Command", "Start-Sleep -Seconds 3") (Get-RepoRoot) 1
    throw "Intentional timeout did not fail."
  } catch {
    if ($_.Exception.Message -notmatch "timed out") { throw }
  }

  Write-Host "managed failure fixtures passed"
}

Assert-Windows11X64

switch ($Command) {
  "unit" { Invoke-Unit }
  "managed-smoke" { Invoke-ManagedSmoke }
  "managed-failure" { Invoke-ManagedFailure }
  "package-smoke" { Invoke-PackageSmoke }
  "all" {
    Invoke-Unit
    Invoke-ManagedSmoke
    Invoke-ManagedFailure
    Invoke-PackageSmoke
  }
}
