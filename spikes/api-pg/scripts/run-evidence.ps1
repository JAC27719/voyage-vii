param(
    [Parameter(Mandatory = $true)]
    [string] $Zig,

    [string] $PostgresHost = "127.0.0.1",
    [int] $PostgresPort = 55432,
    [string] $PostgresDatabase = "postgres",
    [string] $PostgresUser = "postgres",
    [string] $NonresponsiveHost = "10.255.255.1",
    [int] $NonresponsivePort = 5432,
    [int] $EndpointPort = 18080
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$evidence = Join-Path $root "evidence"
$cache = Join-Path $root "cache"
New-Item -ItemType Directory -Force -Path $evidence, $cache | Out-Null

function Get-Sha256Lower {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $resolved = Resolve-Path -LiteralPath $Path
    $stream = [IO.File]::OpenRead($resolved)
    try {
        $sha256 = [Security.Cryptography.SHA256]::Create()
        try {
            $hash = $sha256.ComputeHash($stream)
            return -join ($hash | ForEach-Object { $_.ToString("x2") })
        }
        finally {
            $sha256.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-ChildProcessIds {
    param(
        [Parameter(Mandatory = $true)]
        [int] $ParentProcessId
    )

    @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $ParentProcessId" |
        ForEach-Object { [int] $_.ProcessId })
}

if ([string]::IsNullOrEmpty($env:PGPASSWORD)) {
    throw "Set PGPASSWORD from the ignored runtime password file before running evidence"
}

$env:ZIG_GLOBAL_CACHE_DIR = Join-Path $cache "global"
$env:ZIG_LOCAL_CACHE_DIR = Join-Path $cache "local"

Push-Location $root
try {
$patch = Resolve-Path -LiteralPath (Join-Path $root "../../patches/pg.zig/windows-connect-timeout.patch")
$patchHash = Get-Sha256Lower -Path $patch
"patch_sha256=$patchHash" | Tee-Object (Join-Path $evidence "pg-patch-sha256.log")
if ($patchHash -ne "02d6791ab6bdb147c34972e0076992840be7e5fea2e51e6cdac94455033c578c") {
    throw "Unexpected pg.zig patch SHA-256"
}

& $Zig version 2>&1 | Tee-Object (Join-Path $evidence "zig-version.log")
$fetchLog = Join-Path $evidence "clean-fetch.log"
"command=$Zig build --fetch" | Tee-Object $fetchLog
& $Zig build --fetch 2>&1 | Tee-Object -Append $fetchLog
"exit=$LASTEXITCODE" | Tee-Object -Append $fetchLog
if ($LASTEXITCODE -ne 0) {
    throw "Dependency fetch failed"
}

$targets = @(
    "x86_64-windows-msvc",
    "x86_64-macos",
    "aarch64-macos",
    "x86_64-linux-gnu"
)
foreach ($target in $targets) {
    $buildLog = Join-Path $evidence "build-$target.log"
    "command=$Zig build -Dtarget=$target --prefix $(Join-Path $root "zig-out/$target")" |
        Tee-Object $buildLog
    & $Zig build "-Dtarget=$target" --prefix (Join-Path $root "zig-out/$target") 2>&1 |
        Tee-Object -Append $buildLog
    "exit=$LASTEXITCODE" | Tee-Object -Append $buildLog
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed for $target"
    }
}

$nativeBuildLog = Join-Path $evidence "build-native.log"
"command=$Zig build --prefix $(Join-Path $root "zig-out/native")" |
    Tee-Object $nativeBuildLog
& $Zig build --prefix (Join-Path $root "zig-out/native") 2>&1 |
    Tee-Object -Append $nativeBuildLog
"exit=$LASTEXITCODE" | Tee-Object -Append $nativeBuildLog
if ($LASTEXITCODE -ne 0) {
    throw "Native build failed"
}

$binary = Join-Path $root "zig-out/native/bin/api-pg-spike.exe"

$serverStdout = Join-Path $evidence "endpoint-stdout.log"
$serverStderr = Join-Path $evidence "endpoint-stderr.log"
$server = Start-Process -FilePath $binary `
    -ArgumentList @("serve", "$EndpointPort") `
    -RedirectStandardOutput $serverStdout `
    -RedirectStandardError $serverStderr `
    -WindowStyle Hidden `
    -PassThru
try {
    $endpoint = "http://127.0.0.1:$EndpointPort/probe"
    $response = $null
    for ($attempt = 0; $attempt -lt 15; $attempt++) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri $endpoint -TimeoutSec 1
            break
        }
        catch {
            Start-Sleep -Seconds 1
        }
    }
    if ($null -eq $response) {
        throw "Endpoint probe did not return within 15 seconds"
    }
    $endpointEvidence = @(
        "status_code=$($response.StatusCode)"
        "content_type=$($response.Headers["Content-Type"])"
        "body=$($response.Content)"
    )
    $endpointEvidence | Tee-Object (Join-Path $evidence "endpoint-probe.log")
    if ($response.StatusCode -ne 200) {
        throw "Endpoint returned unexpected status"
    }
    if ($response.Content -ne '{"dependency":"api.zig","status":"ok"}') {
        throw "Endpoint returned unexpected body"
    }
}
finally {
    $childrenBeforeStop = Get-ChildProcessIds -ParentProcessId $server.Id
    $shutdownStatus = "not_sent"
    $shutdownBody = ""
    try {
        $shutdownResponse = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$EndpointPort/shutdown" -TimeoutSec 2
        $shutdownStatus = [string] $shutdownResponse.StatusCode
        $shutdownBody = [string] $shutdownResponse.Content
    }
    catch {
        $shutdownStatus = "request_failed"
        $shutdownBody = $_.Exception.Message
    }
    try {
        Wait-Process -Id $server.Id -Timeout 20 -ErrorAction Stop
    }
    catch {
        if (Get-Process -Id $server.Id -ErrorAction SilentlyContinue) {
            throw
        }
    }
    $serverStillRunning = Get-Process -Id $server.Id -ErrorAction SilentlyContinue
    $childrenAfterStop = Get-ChildProcessIds -ParentProcessId $server.Id
    @(
        "server_process_id=$($server.Id)"
        "shutdown_status=$shutdownStatus"
        "shutdown_body=$shutdownBody"
        "children_before_stop=$($childrenBeforeStop -join ',')"
        "server_running_after_stop=$([bool] $serverStillRunning)"
        "children_after_stop=$($childrenAfterStop -join ',')"
    ) | Tee-Object (Join-Path $evidence "supervisor-shutdown.log")
    if ($serverStillRunning) {
        throw "Endpoint process survived supervisor stop"
    }
    if ($shutdownStatus -ne "200") {
        throw "Endpoint shutdown route did not return 200 before process exit"
    }
    if ($shutdownBody -ne '{"shutdown":"accepted"}') {
        throw "Endpoint shutdown route returned unexpected body"
    }
    if ($childrenAfterStop.Count -ne 0) {
        throw "Endpoint process left surviving descendants"
    }
}

for ($attempt = 1; $attempt -le 2; $attempt++) {
    $deadlineLog = Join-Path $evidence "pg-nonresponsive-$attempt.log"
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    & $binary pg-probe $NonresponsiveHost $NonresponsivePort $PostgresDatabase $PostgresUser 2>&1 |
        Tee-Object $deadlineLog
    $exit = $LASTEXITCODE
    $stopwatch.Stop()
    "elapsed_ms=$($stopwatch.ElapsedMilliseconds)" | Tee-Object -Append $deadlineLog
    "exit=$exit" | Tee-Object -Append $deadlineLog
    if ($exit -eq 0) {
        throw "Nonresponsive-destination probe unexpectedly succeeded"
    }
    if ($stopwatch.ElapsedMilliseconds -lt 4500 -or $stopwatch.ElapsedMilliseconds -gt 8000) {
        throw "Nonresponsive-destination probe did not hit the five-second deadline"
    }
}

& $binary pg-probe $PostgresHost 1 $PostgresDatabase $PostgresUser 2>&1 |
    Tee-Object (Join-Path $evidence "pg-unavailable.log")
if ($LASTEXITCODE -eq 0) {
    throw "Unavailable-server probe unexpectedly succeeded"
}

$validPassword = $env:PGPASSWORD
$env:PGPASSWORD = "[redacted-invalid-password]"
& $binary pg-probe $PostgresHost $PostgresPort $PostgresDatabase $PostgresUser 2>&1 |
    Tee-Object (Join-Path $evidence "pg-auth-failure.log")
if ($LASTEXITCODE -eq 0) {
    throw "Authentication-failure probe unexpectedly succeeded"
}

$env:PGPASSWORD = $validPassword
& $binary pg-probe $PostgresHost $PostgresPort $PostgresDatabase $PostgresUser 2>&1 |
    Tee-Object (Join-Path $evidence "pg-probe.log")
if ($LASTEXITCODE -ne 0) {
    throw "PostgreSQL SELECT 1 probe failed"
}

git diff --check 2>&1 | Tee-Object (Join-Path $evidence "git-diff-check.log")
if ($LASTEXITCODE -ne 0) {
    throw "git diff --check failed"
}
}
finally {
    Pop-Location
}
