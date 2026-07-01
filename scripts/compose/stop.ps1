[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$composeFile = Join-Path $root "compose.yaml"

& docker compose --file $composeFile stop --timeout 20
if ($LASTEXITCODE -ne 0) {
    throw "docker compose stop failed with exit code $LASTEXITCODE."
}
