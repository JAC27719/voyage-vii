param(
    [int] $Port = 55432
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $root "runtime"
$passwordFile = Join-Path $runtime "pg-password.txt"
$container = "voyage-vii-feas-001-pg"
$volume = "voyage-vii-feas-001-pgdata"
$image = "voyage-vii-feas-001-postgresql:18.4"

New-Item -ItemType Directory -Force -Path $runtime | Out-Null
if (-not (Test-Path -LiteralPath $passwordFile)) {
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $password = [Convert]::ToBase64String($bytes)
    [System.IO.File]::WriteAllText($passwordFile, $password)
}

docker build --file (Join-Path $root "Dockerfile.postgresql") --tag $image $root
if ($LASTEXITCODE -ne 0) {
    throw "PostgreSQL 18.4 source build failed"
}

docker rm --force $container 2>$null | Out-Null
docker volume rm --force $volume 2>$null | Out-Null
docker volume create $volume | Out-Null
docker run --detach `
    --name $container `
    --publish "127.0.0.1:${Port}:5432" `
    --env "PGDATA=/var/lib/postgresql/data" `
    --env "POSTGRES_PASSWORD_FILE=/run/secrets/postgres-password" `
    --mount "type=bind,source=$passwordFile,target=/run/secrets/postgres-password,readonly" `
    --mount "type=volume,source=$volume,target=/var/lib/postgresql/data" `
    $image
if ($LASTEXITCODE -ne 0) {
    throw "PostgreSQL 18.4 container failed to start"
}

for ($attempt = 0; $attempt -lt 60; $attempt++) {
    docker exec $container pg_isready --host 127.0.0.1 --port 5432 --username postgres |
        Out-Null
    if ($LASTEXITCODE -eq 0) {
        docker exec $container postgres --version
        exit 0
    }
    Start-Sleep -Seconds 1
}

docker logs $container
throw "PostgreSQL 18.4 did not become ready within 60 seconds"
