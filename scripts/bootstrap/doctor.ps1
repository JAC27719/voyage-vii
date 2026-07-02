#requires -Version 7.0

[CmdletBinding()]
param(
  [switch]$Json
)

$script = Join-Path $PSScriptRoot "../../tools/doctor/voyage-doctor.ps1"
& $script -Json:$Json
exit $LASTEXITCODE
