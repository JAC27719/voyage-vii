param(
    [Parameter(Mandatory = $true)]
    [string] $Install,

    [Parameter(Mandatory = $true)]
    [string] $Source,

    [Parameter(Mandatory = $true)]
    [string] $Output
)

$ErrorActionPreference = "Stop"

$installPath = (Resolve-Path -LiteralPath $Install).Path
$sourcePath = (Resolve-Path -LiteralPath $Source).Path

if (-not (Test-Path -LiteralPath (Join-Path $installPath "bin\postgres.exe"))) {
    throw "PostgreSQL install does not contain bin\postgres.exe: $installPath"
}

if (-not (Test-Path -LiteralPath (Join-Path $sourcePath "COPYRIGHT"))) {
    throw "PostgreSQL source does not contain COPYRIGHT: $sourcePath"
}

if (Test-Path -LiteralPath $Output) {
    Remove-Item -LiteralPath $Output -Recurse -Force
}

$postgresOutput = Join-Path $Output "postgresql"
$licenseOutput = Join-Path $Output "licenses\postgresql"

New-Item -ItemType Directory -Force -Path $postgresOutput | Out-Null
New-Item -ItemType Directory -Force -Path $licenseOutput | Out-Null

Copy-Item -Path (Join-Path $installPath "*") -Destination $postgresOutput -Recurse -Force
Copy-Item -LiteralPath (Join-Path $sourcePath "COPYRIGHT") -Destination (Join-Path $licenseOutput "COPYRIGHT") -Force

$requiredFiles = @(
    "postgresql\bin\postgres.exe",
    "postgresql\bin\initdb.exe",
    "postgresql\bin\pg_ctl.exe",
    "postgresql\bin\psql.exe",
    "postgresql\bin\libpq.dll",
    "licenses\postgresql\COPYRIGHT"
)

foreach ($relativePath in $requiredFiles) {
    $candidate = Join-Path $Output $relativePath
    if (-not (Test-Path -LiteralPath $candidate)) {
        throw "Packaged PostgreSQL runtime is missing $relativePath"
    }
}

Write-Host "packaged_postgresql_runtime=$Output"
