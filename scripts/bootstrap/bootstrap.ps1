#requires -Version 7.0

[CmdletBinding()]
param(
  [ValidateSet("desktop", "packaging", "all")]
  [string]$Profile = "all",
  [switch]$Offline
)

$script = Join-Path $PSScriptRoot "../../tools/bootstrap/voyage-bootstrap.ps1"
& $script -Profile $Profile -Offline:$Offline
exit $LASTEXITCODE
