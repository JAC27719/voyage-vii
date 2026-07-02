$ErrorActionPreference = "Stop"
$container = "voyage-vii-feas-001-pg"
$volume = "voyage-vii-feas-001-pgdata"

docker stop --timeout 10 $container
if ($LASTEXITCODE -ne 0) {
    throw "PostgreSQL container did not stop gracefully"
}

docker rm $container
if ($LASTEXITCODE -ne 0) {
    throw "PostgreSQL container removal failed"
}

docker volume rm $volume
if ($LASTEXITCODE -ne 0) {
    throw "PostgreSQL data volume removal failed"
}
