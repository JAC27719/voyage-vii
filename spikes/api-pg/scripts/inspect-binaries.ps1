param(
    [string] $OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "zig-out")
)

$ErrorActionPreference = "Stop"

function Read-U16LE([byte[]] $Bytes, [int] $Offset) {
    return [BitConverter]::ToUInt16($Bytes, $Offset)
}

function Read-U32LE([byte[]] $Bytes, [int] $Offset) {
    return [BitConverter]::ToUInt32($Bytes, $Offset)
}

function Inspect-Binary([string] $Target, [string] $Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $format = "unknown"
    $machine = "unknown"

    if ($bytes[0] -eq 0x4d -and $bytes[1] -eq 0x5a) {
        $format = "PE32+"
        $pe = Read-U32LE $bytes 0x3c
        if (
            $bytes[$pe] -ne 0x50 -or
            $bytes[$pe + 1] -ne 0x45 -or
            $bytes[$pe + 2] -ne 0 -or
            $bytes[$pe + 3] -ne 0
        ) {
            throw "$Path has an invalid PE signature"
        }
        $machine = switch (Read-U16LE $bytes ($pe + 4)) {
            0x8664 { "x86_64" }
            default { "unexpected" }
        }
    }
    elseif (
        $bytes[0] -eq 0x7f -and
        $bytes[1] -eq 0x45 -and
        $bytes[2] -eq 0x4c -and
        $bytes[3] -eq 0x46
    ) {
        $format = "ELF64"
        $machine = switch (Read-U16LE $bytes 18) {
            0x003e { "x86_64" }
            default { "unexpected" }
        }
    }
    elseif (
        $bytes[0] -eq 0xcf -and
        $bytes[1] -eq 0xfa -and
        $bytes[2] -eq 0xed -and
        $bytes[3] -eq 0xfe
    ) {
        $format = "Mach-O 64"
        $machine = switch (Read-U32LE $bytes 4) {
            0x01000007 { "x86_64" }
            0x0100000c { "aarch64" }
            default { "unexpected" }
        }
    }

    if ($machine -eq "unexpected" -or $format -eq "unknown") {
        throw "$Path did not match its expected binary architecture"
    }

    [pscustomobject]@{
        target = $Target
        format = $format
        machine = $machine
        bytes = $bytes.Length
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

$inputs = [ordered]@{
    "x86_64-pc-windows-msvc" = Join-Path $OutputRoot "x86_64-windows-msvc/bin/api-pg-spike.exe"
    "x86_64-apple-darwin" = Join-Path $OutputRoot "x86_64-macos/bin/api-pg-spike"
    "aarch64-apple-darwin" = Join-Path $OutputRoot "aarch64-macos/bin/api-pg-spike"
    "x86_64-unknown-linux-gnu" = Join-Path $OutputRoot "x86_64-linux-gnu/bin/api-pg-spike"
}

foreach ($entry in $inputs.GetEnumerator()) {
    Inspect-Binary $entry.Key $entry.Value
}
