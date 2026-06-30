param(
    [Parameter(Mandatory = $true)]
    [string] $Source,

    [Parameter(Mandatory = $true)]
    [string] $Patch,

    [Parameter(Mandatory = $true)]
    [string] $Output
)

$ErrorActionPreference = "Stop"

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

$expectedStreamSha256 = "91d1ab1b4ed1a456b1bd9f5d9b68ff327eca036ecc6db4dddf8889af21e28abe"
$expectedPatchSha256 = "02d6791ab6bdb147c34972e0076992840be7e5fea2e51e6cdac94455033c578c"
$sourceRoot = Resolve-Path -LiteralPath $Source
$patchPath = Resolve-Path -LiteralPath $Patch

if ((Get-Sha256Lower -Path $patchPath) -ne $expectedPatchSha256) {
    throw "pg.zig patch SHA-256 mismatch"
}

New-Item -ItemType Directory -Force -Path $Output | Out-Null
Get-ChildItem -LiteralPath $sourceRoot -Force |
    Copy-Item -Destination $Output -Recurse -Force
$outputRoot = (Resolve-Path -LiteralPath $Output).Path
$repoRoot = (git rev-parse --show-toplevel)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to resolve Git repository root for deterministic patch application"
}
Push-Location $repoRoot
try {
    $gitOutputRoot = (Resolve-Path -LiteralPath $outputRoot -Relative).
        TrimStart(".", "\", "/").
        Replace("\", "/")
}
finally {
    Pop-Location
}

$streamPath = Join-Path $Output "src/stream.zig"
$actualStreamSha256 = Get-Sha256Lower -Path $streamPath
if ($actualStreamSha256 -ne $expectedStreamSha256) {
    throw "pg.zig upstream src/stream.zig hash mismatch: expected $expectedStreamSha256 got $actualStreamSha256"
}

Push-Location $repoRoot
try {
    git apply --check --unidiff-zero --whitespace=nowarn --directory="$gitOutputRoot" $patchPath
    if ($LASTEXITCODE -ne 0) {
        throw "pg.zig patch check failed"
    }

    git apply --unidiff-zero --whitespace=nowarn --directory="$gitOutputRoot" $patchPath
    if ($LASTEXITCODE -ne 0) {
        throw "pg.zig patch application failed"
    }
}
finally {
    Pop-Location
}

$patchedStreamSha256 = Get-Sha256Lower -Path $streamPath
if ($patchedStreamSha256 -eq $expectedStreamSha256) {
    throw "pg.zig patch did not change src/stream.zig"
}
