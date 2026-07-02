param(
    [Parameter(Mandatory = $true)]
    [string] $Source,

    [Parameter(Mandatory = $true)]
    [string] $Build,

    [Parameter(Mandatory = $true)]
    [string] $Prefix,

    [Parameter(Mandatory = $true)]
    [string] $PythonToolchain
)

$ErrorActionPreference = "Stop"

$vsDevCmd = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"
if (-not (Test-Path -LiteralPath $vsDevCmd)) {
    throw "Visual Studio developer command prompt not found at $vsDevCmd"
}

$batch = Join-Path (Split-Path -Parent $Build) "build-postgresql-windows.cmd"
$toolBin = Join-Path $PythonToolchain "bin"
$gitUsrBin = "C:\Program Files\Git\usr\bin"
$winFlexBisonBin = Join-Path (Split-Path -Parent $PythonToolchain) "winflexbison\extracted"
$content = @"
@echo off
setlocal
call "$vsDevCmd" -arch=x64 -host_arch=x64
if errorlevel 1 exit /b %errorlevel%
set "PYTHONPATH=$PythonToolchain"
set "MSYS2_ARG_CONV_EXCL=*"
set "PATH=$toolBin;$winFlexBisonBin;%PATH%;$gitUsrBin"
where cl
if errorlevel 1 exit /b %errorlevel%
where perl
if errorlevel 1 exit /b %errorlevel%
where win_flex
if errorlevel 1 exit /b %errorlevel%
where win_bison
if errorlevel 1 exit /b %errorlevel%
where meson
if errorlevel 1 exit /b %errorlevel%
where ninja
if errorlevel 1 exit /b %errorlevel%
if exist "$Build" rmdir /s /q "$Build"
if exist "$Prefix" rmdir /s /q "$Prefix"
meson setup "$Build" "$Source" --prefix "$Prefix" --buildtype release -Ddocs=disabled -Dtap_tests=disabled -Dssl=none -Dgssapi=disabled -Dicu=disabled -Dldap=disabled -Dplperl=disabled -Dplpython=disabled -Dpltcl=disabled -Dreadline=disabled -Dzlib=disabled -Dlz4=disabled -Dzstd=disabled -Dnls=disabled -Duuid=none
if errorlevel 1 exit /b %errorlevel%
meson compile -C "$Build"
if errorlevel 1 exit /b %errorlevel%
meson install -C "$Build"
if errorlevel 1 exit /b %errorlevel%
"@

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Build) | Out-Null
[IO.File]::WriteAllText($batch, $content)
cmd /c "`"$batch`""
if ($LASTEXITCODE -ne 0) {
    throw "PostgreSQL Windows native build failed with exit $LASTEXITCODE"
}
