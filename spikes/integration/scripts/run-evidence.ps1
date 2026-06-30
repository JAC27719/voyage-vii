param(
    [Parameter(Mandatory = $true)]
    [string] $Zig,

    [Parameter(Mandatory = $true)]
    [string] $TigerBeetleExe,

    [Parameter(Mandatory = $true)]
    [string] $TigerBeetleClientLib,

    [Parameter(Mandatory = $true)]
    [string] $TigerBeetleClientInclude,

    [string] $PostgresHost = "127.0.0.1",
    [int] $PostgresPort = 55432,
    [string] $PostgresDatabase = "postgres",
    [string] $PostgresUser = "postgres",
    [int] $EndpointPort = 18083,
    [int] $TigerBeetlePort = 3003
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$evidence = Join-Path $root "evidence"
$cache = Join-Path $root "cache"
$runtime = Join-Path $root "runtime"
New-Item -ItemType Directory -Force -Path $evidence, $cache, $runtime | Out-Null

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
$tbAddress = "127.0.0.1:$TigerBeetlePort"
$tbData = Join-Path $runtime "0_0.tigerbeetle"
$serverStdout = Join-Path $evidence "tigerbeetle-stdout.log"
$serverStderr = Join-Path $evidence "tigerbeetle-stderr.log"
$apiStdout = Join-Path $evidence "api-stdout.log"
$apiStderr = Join-Path $evidence "api-stderr.log"

Push-Location $root
try {
    "zig_sha256=$(Get-Sha256Lower -Path $Zig)" | Tee-Object (Join-Path $evidence "input-hashes.log")
    "tb_exe_sha256=$(Get-Sha256Lower -Path $TigerBeetleExe)" | Tee-Object -Append (Join-Path $evidence "input-hashes.log")
    "tb_client_lib_sha256=$(Get-Sha256Lower -Path $TigerBeetleClientLib)" | Tee-Object -Append (Join-Path $evidence "input-hashes.log")
    "tb_client_header_sha256=$(Get-Sha256Lower -Path (Join-Path $TigerBeetleClientInclude 'tb_client.h'))" | Tee-Object -Append (Join-Path $evidence "input-hashes.log")
    "pg_patch_sha256=$(Get-Sha256Lower -Path (Join-Path $root '../../patches/pg.zig/windows-connect-timeout.patch'))" | Tee-Object -Append (Join-Path $evidence "input-hashes.log")

    & $Zig version 2>&1 | Tee-Object (Join-Path $evidence "zig-version.log")

    $fetchLog = Join-Path $evidence "clean-fetch.log"
    "command=$Zig build --fetch" | Tee-Object $fetchLog
    & $Zig build --fetch 2>&1 | Tee-Object -Append $fetchLog
    "exit=$LASTEXITCODE" | Tee-Object -Append $fetchLog
    if ($LASTEXITCODE -ne 0) {
        throw "Dependency fetch failed"
    }

    $buildLog = Join-Path $evidence "build-native.log"
    "command=$Zig build -Dtb-client-lib=$TigerBeetleClientLib -Dtb-client-include=$TigerBeetleClientInclude -Doptimize=ReleaseSafe --prefix zig-out/native" |
        Tee-Object $buildLog
    & $Zig build "-Dtb-client-lib=$TigerBeetleClientLib" "-Dtb-client-include=$TigerBeetleClientInclude" -Doptimize=ReleaseSafe --prefix (Join-Path $root "zig-out/native") 2>&1 |
        Tee-Object -Append $buildLog
    "exit=$LASTEXITCODE" | Tee-Object -Append $buildLog
    if ($LASTEXITCODE -ne 0) {
        throw "Native integration build failed"
    }

    $binary = Join-Path $root "zig-out/native/bin/integration-spike.exe"
    "integration_exe_sha256=$(Get-Sha256Lower -Path $binary)" | Tee-Object (Join-Path $evidence "output-hashes.log")

    if (Test-Path -LiteralPath $tbData) {
        Remove-Item -LiteralPath $tbData -Force
    }
    & $TigerBeetleExe format --cluster=0 --replica=0 --replica-count=1 --development $tbData 2>&1 |
        Tee-Object (Join-Path $evidence "tigerbeetle-format.log")
    if ($LASTEXITCODE -ne 0) {
        throw "TigerBeetle format failed"
    }
    $tbServer = Start-Process -FilePath $TigerBeetleExe `
        -ArgumentList @("start", "--addresses=$tbAddress", "--development", $tbData) `
        -RedirectStandardOutput $serverStdout `
        -RedirectStandardError $serverStderr `
        -WindowStyle Hidden `
        -PassThru
    try {
        Start-Sleep -Seconds 2
        $apiServer = Start-Process -FilePath $binary `
            -ArgumentList @("serve", "$EndpointPort", $PostgresHost, "$PostgresPort", $PostgresDatabase, $PostgresUser, $tbAddress) `
            -RedirectStandardOutput $apiStdout `
            -RedirectStandardError $apiStderr `
            -WindowStyle Hidden `
            -PassThru
        try {
            $endpoint = "http://127.0.0.1:$EndpointPort/probe"
            $response = $null
            for ($attempt = 0; $attempt -lt 20; $attempt++) {
                try {
                    $response = Invoke-WebRequest -UseBasicParsing -Uri $endpoint -TimeoutSec 10
                    break
                }
                catch {
                    Start-Sleep -Seconds 1
                }
            }
            if ($null -eq $response) {
                throw "Integration endpoint probe did not return"
            }
            @(
                "status_code=$($response.StatusCode)"
                "content_type=$($response.Headers["Content-Type"])"
                "body=$($response.Content)"
            ) | Tee-Object (Join-Path $evidence "endpoint-probe.log")
            if ($response.StatusCode -ne 200) {
                throw "Integration endpoint returned unexpected status"
            }
            if ($response.Content -ne '{"status":"ok","postgres":"ok","tigerbeetle":"ok"}') {
                throw "Integration endpoint returned unexpected body"
            }
        }
        finally {
            if ($apiServer -and -not $apiServer.HasExited) {
                $childrenBeforeStop = Get-ChildProcessIds -ParentProcessId $apiServer.Id
                $shutdownResponse = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$EndpointPort/shutdown" -TimeoutSec 2
                try {
                    Wait-Process -Id $apiServer.Id -Timeout 20 -ErrorAction Stop
                }
                catch {
                    if (Get-Process -Id $apiServer.Id -ErrorAction SilentlyContinue) {
                        throw
                    }
                }
                $apiStillRunning = Get-Process -Id $apiServer.Id -ErrorAction SilentlyContinue
                $childrenAfterStop = Get-ChildProcessIds -ParentProcessId $apiServer.Id
                @(
                    "server_process_id=$($apiServer.Id)"
                    "shutdown_status=$($shutdownResponse.StatusCode)"
                    "shutdown_body=$($shutdownResponse.Content)"
                    "children_before_stop=$($childrenBeforeStop -join ',')"
                    "server_running_after_stop=$([bool] $apiStillRunning)"
                    "children_after_stop=$($childrenAfterStop -join ',')"
                ) | Tee-Object (Join-Path $evidence "shutdown.log")
                if ($apiStillRunning) {
                    throw "Integration API process survived shutdown"
                }
                if ($childrenAfterStop.Count -ne 0) {
                    throw "Integration API left descendants"
                }
            }
        }
    }
    finally {
        if ($tbServer -and -not $tbServer.HasExited) {
            Stop-Process -Id $tbServer.Id
            Wait-Process -Id $tbServer.Id -Timeout 10 -ErrorAction SilentlyContinue
        }
    }

    git diff --check 2>&1 | Tee-Object (Join-Path $evidence "git-diff-check.log")
    if ($LASTEXITCODE -ne 0) {
        throw "git diff --check failed"
    }
}
finally {
    Pop-Location
}
