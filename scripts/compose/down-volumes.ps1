[CmdletBinding()]
param(
    [switch] $ConfirmDestructiveDown
)

$ErrorActionPreference = "Stop"

if (-not $ConfirmDestructiveDown) {
    throw "This removes Voyage VII Compose containers and named volumes. Re-run with -ConfirmDestructiveDown when that data loss is intended."
}

$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$composeFile = Join-Path $root "compose.yaml"

& docker compose --file $composeFile down --volumes --remove-orphans
if ($LASTEXITCODE -ne 0) {
    throw "docker compose down --volumes failed with exit code $LASTEXITCODE."
}
