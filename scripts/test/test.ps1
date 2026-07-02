#requires -Version 7.0

[CmdletBinding()]
param(
  [ValidateSet("unit", "compose-smoke", "managed-smoke", "managed-failure", "package-smoke", "all")]
  [string]$Command = "all",
  [string]$ApiImage,
  [switch]$KeepSuccessfulRoots
)

$script = Join-Path $PSScriptRoot "../../tools/test-harness/voyage-test.ps1"
& $script -Command $Command -ApiImage $ApiImage -KeepSuccessfulRoots:$KeepSuccessfulRoots
exit $LASTEXITCODE
