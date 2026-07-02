#requires -Version 7.0

[CmdletBinding()]
param(
  [ValidateSet("unit", "managed-smoke", "managed-failure", "package-smoke", "all")]
  [string]$Command = "all",
  [switch]$KeepSuccessfulRoots
)

$script = Join-Path $PSScriptRoot "../../tools/test-harness/voyage-test.ps1"
& $script -Command $Command -KeepSuccessfulRoots:$KeepSuccessfulRoots
exit $LASTEXITCODE
