param(
    [Parameter(Mandatory = $true)]
    [string] $Zig
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$root = Split-Path -Parent $PSScriptRoot
$cache = Join-Path $root "cache"
$evidence = Join-Path $root "evidence"
$runtime = Join-Path $root "runtime"
$source = Join-Path $root "source"
New-Item -ItemType Directory -Force -Path $cache, $evidence, $runtime, $source | Out-Null

$sqliteVersion = "3.53.3"
$sqliteArchiveName = "sqlite-amalgamation-3530300.zip"
$sqliteRelativeUrl = "2026/$sqliteArchiveName"
$sqliteUrl = "https://www.sqlite.org/$sqliteRelativeUrl"
$sqliteSha3 = "d45c688a8cb23f68611a894a756a12d7eb6ab6e9e2468ca70adbeab3808b5ab9"
$sqliteSize = 2945929
$archive = Join-Path $cache $sqliteArchiveName
$extractRoot = Join-Path $source "sqlite-amalgamation-3530300"
$database = Join-Path $runtime "feas-004.sqlite3"

function Get-Sha256Lower {
    param([Parameter(Mandatory = $true)][string] $Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-Sha3Lower {
    param([Parameter(Mandatory = $true)][string] $Path)
    $stream = [IO.File]::OpenRead((Resolve-Path -LiteralPath $Path))
    try {
        $hash = [Security.Cryptography.SHA3_256]::HashData($stream)
        return -join ($hash | ForEach-Object { $_.ToString("x2") })
    }
    finally {
        $stream.Dispose()
    }
}

"url=$sqliteUrl" | Tee-Object (Join-Path $evidence "source-provenance.log")
"version=$sqliteVersion" | Tee-Object -Append (Join-Path $evidence "source-provenance.log")
"archive=$sqliteArchiveName" | Tee-Object -Append (Join-Path $evidence "source-provenance.log")
"expected_size=$sqliteSize" | Tee-Object -Append (Join-Path $evidence "source-provenance.log")
"expected_sha3_256=$sqliteSha3" | Tee-Object -Append (Join-Path $evidence "source-provenance.log")
"license=SQLite public domain dedication, https://www.sqlite.org/copyright.html" |
    Tee-Object -Append (Join-Path $evidence "source-provenance.log")

Invoke-WebRequest -UseBasicParsing -Uri $sqliteUrl -OutFile $archive -TimeoutSec 60
$actualSize = (Get-Item -LiteralPath $archive).Length
$actualSha3 = Get-Sha3Lower -Path $archive
if ($actualSize -ne $sqliteSize) {
    throw "SQLite archive size mismatch: expected $sqliteSize actual $actualSize"
}
if ($actualSha3 -ne $sqliteSha3) {
    throw "SQLite archive SHA3-256 mismatch: expected $sqliteSha3 actual $actualSha3"
}

"archive_sha3_256=$actualSha3" | Tee-Object (Join-Path $evidence "input-hashes.log")
"archive_sha256=$(Get-Sha256Lower -Path $archive)" | Tee-Object -Append (Join-Path $evidence "input-hashes.log")

if (Test-Path -LiteralPath $source) {
    Get-ChildItem -LiteralPath $source -Force | Remove-Item -Recurse -Force
}
Expand-Archive -LiteralPath $archive -DestinationPath $source -Force
if (-not (Test-Path -LiteralPath (Join-Path $extractRoot "sqlite3.c"))) {
    throw "Extracted SQLite amalgamation did not contain sqlite3.c"
}
if (-not (Test-Path -LiteralPath (Join-Path $extractRoot "sqlite3.h"))) {
    throw "Extracted SQLite amalgamation did not contain sqlite3.h"
}

"sqlite3_c_sha256=$(Get-Sha256Lower -Path (Join-Path $extractRoot 'sqlite3.c'))" |
    Tee-Object -Append (Join-Path $evidence "input-hashes.log")
"sqlite3_h_sha256=$(Get-Sha256Lower -Path (Join-Path $extractRoot 'sqlite3.h'))" |
    Tee-Object -Append (Join-Path $evidence "input-hashes.log")

$env:ZIG_GLOBAL_CACHE_DIR = Join-Path $cache "zig-global"
$env:ZIG_LOCAL_CACHE_DIR = Join-Path $cache "zig-local"

Push-Location $root
try {
    & $Zig version 2>&1 | Tee-Object (Join-Path $evidence "zig-version.log")
    if ($LASTEXITCODE -ne 0) {
        throw "zig version failed"
    }

    $buildLog = Join-Path $evidence "build-native.log"
    "command=$Zig build -Dsqlite-amalgamation=$extractRoot -Doptimize=ReleaseSafe --prefix zig-out/native" |
        Tee-Object $buildLog
    & $Zig build "-Dsqlite-amalgamation=$extractRoot" -Doptimize=ReleaseSafe --prefix (Join-Path $root "zig-out/native") 2>&1 |
        Tee-Object -Append $buildLog
    "exit=$LASTEXITCODE" | Tee-Object -Append $buildLog
    if ($LASTEXITCODE -ne 0) {
        throw "SQLite spike build failed"
    }

    $binary = Join-Path $root "zig-out/native/bin/sqlite-spike.exe"
    "sqlite_spike_exe_sha256=$(Get-Sha256Lower -Path $binary)" |
        Tee-Object (Join-Path $evidence "output-hashes.log")

    if (Test-Path -LiteralPath $database) {
        Remove-Item -LiteralPath $database -Force
    }
    foreach ($suffix in "-wal", "-shm") {
        $sidecar = "$database$suffix"
        if (Test-Path -LiteralPath $sidecar) {
            Remove-Item -LiteralPath $sidecar -Force
        }
    }

    $runLog = Join-Path $evidence "run-native.log"
    "command=$binary $database" | Tee-Object $runLog
    & $binary $database 2>&1 | Tee-Object -Append $runLog
    "exit=$LASTEXITCODE" | Tee-Object -Append $runLog
    if ($LASTEXITCODE -ne 0) {
        throw "SQLite spike run failed"
    }

    git diff --check 2>&1 | Tee-Object (Join-Path $evidence "git-diff-check.log")
    if ($LASTEXITCODE -ne 0) {
        throw "git diff --check failed"
    }
}
finally {
    Pop-Location
}
