#requires -Version 7.0

[CmdletBinding()]
param(
  [string]$OutputRoot = $env:RUNNER_TEMP
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$zig014Hash = "554f5378228923ffd558eac35e21af020c73789d87afeabf4bfd16f2e6feed2c"
$tigerBeetleSourceHash = "b343fa0e4501a063a47b893ec39f278133c93cb67c585dfe81b64ccee7186e9a"
$clientLibHash = "1edf28ac840cc44ae98a8782d066da525df8257a6c90df921164d706ff232c02"
$clientHeaderHash = "3ad1dd26fb67f3c89c971072cf22ad4a833971f6a40947ca562db2685587964d"

function Assert-UnderRoot([string]$Path, [string]$Root) {
  $resolved = [System.IO.Path]::GetFullPath($Path)
  $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
  $rootWithSeparator = $resolvedRoot.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  ) + [System.IO.Path]::DirectorySeparatorChar
  if ($resolved -ne $resolvedRoot -and -not $resolved.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Path escaped expected root."
  }
  return $resolved
}

function Assert-FileSha256([string]$Path, [string]$Expected, [string]$Name) {
  $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne $Expected) {
    throw "$Name hash mismatch. Expected $Expected, got $actual."
  }
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  throw "OutputRoot is required."
}

$root = Assert-UnderRoot (Join-Path $OutputRoot "voyage-vii-tb-client") $OutputRoot
$zigRoot = Join-Path $root "zig-0.14.1"
$sourceZip = Join-Path $root "tigerbeetle-0.17.7.zip"
$sourceRoot = Join-Path $root "tigerbeetle-0.17.7"
New-Item -ItemType Directory -Force -Path $root | Out-Null

$zigZip = Join-Path $root "zig-x86_64-windows-0.14.1.zip"
Invoke-WebRequest -Uri "https://ziglang.org/download/0.14.1/zig-x86_64-windows-0.14.1.zip" -OutFile $zigZip
Assert-FileSha256 $zigZip $zig014Hash "Zig 0.14.1 archive"
Expand-Archive -LiteralPath $zigZip -DestinationPath $zigRoot
$zig014 = Get-ChildItem -LiteralPath $zigRoot -Recurse -Filter zig.exe -File | Select-Object -First 1
if (-not $zig014) {
  throw "Zig 0.14.1 executable not found."
}
if ((& $zig014.FullName version).Trim() -ne "0.14.1") {
  throw "Zig 0.14.1 executable reported the wrong version."
}

Invoke-WebRequest -Uri "https://github.com/tigerbeetle/tigerbeetle/archive/refs/tags/0.17.7.zip" -OutFile $sourceZip
Assert-FileSha256 $sourceZip $tigerBeetleSourceHash "TigerBeetle 0.17.7 source"
Expand-Archive -LiteralPath $sourceZip -DestinationPath $root

Push-Location $sourceRoot
try {
  & $zig014.FullName build clients:c `
    "-Dgit-commit=4abc0229ae411fffd669a5a07f50fe3e20b88af0" `
    "-Dconfig-release=0.17.7" `
    "-Dconfig-release-client-min=0.16.4" `
    -Drelease
  if ($LASTEXITCODE -ne 0) {
    throw "TigerBeetle C client build failed."
  }
} finally {
  Pop-Location
}

$clientLib = Join-Path $sourceRoot "src/clients/c/lib/x86_64-windows/tb_client.lib"
$clientInclude = Join-Path $sourceRoot "src/clients/c"
$clientHeader = Join-Path $clientInclude "tb_client.h"
Assert-FileSha256 $clientLib $clientLibHash "TigerBeetle C client library"
Assert-FileSha256 $clientHeader $clientHeaderHash "TigerBeetle C client header"

if ($env:GITHUB_ENV) {
  "TB_CLIENT_LIB=$clientLib" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
  "TB_CLIENT_INCLUDE=$clientInclude" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
}

Write-Output "TB_CLIENT_LIB=$clientLib"
Write-Output "TB_CLIENT_INCLUDE=$clientInclude"
