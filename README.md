# Hydra

Hydra is a .NET 10 REST API backed by PostgreSQL and TigerBeetle. This repository
contains the initial local-development environment, connectivity API, test-data
seeder, AWS infrastructure, and GitHub delivery pipelines.

> [!WARNING]
> The AWS TigerBeetle stack is a single-replica **development** deployment. It is
> not highly available and must not hold production financial data. Follow the
> [TigerBeetle cluster recommendations](https://docs.tigerbeetle.com/operating/cluster/)
> before creating a production environment.

## Run locally

Prerequisites are Docker Desktop and Docker Compose. Copy `.env.example` to
`.env` if you want to override the safe local defaults.

```shell
docker compose up --build
```

The API is available at:

- `http://localhost:8080/health/live` — process liveness only.
- `http://localhost:8080/status` — PostgreSQL and TigerBeetle connectivity.

Host tools such as a VS Code TigerBeetle extension must connect with cluster
ID `0` and the numeric address `127.0.0.1:3000`. TigerBeetle does not use a
username, password, TLS, or a SQL connection string in this local environment.
The API status check performs a real `lookup_accounts` request, so a healthy
TigerBeetle result confirms that the server processed and answered a request.
The server and .NET client are both pinned to `0.17.5`. A tool whose bundled
TigerBeetle client is newer than `0.17.5` cannot connect to this replica; check
the tool's client version when its address and cluster ID are otherwise correct.

Check the container and its persisted data volume with:

```shell
docker compose ps tigerbeetle
docker compose logs tigerbeetle
docker volume inspect hydra_tigerbeetle-data
```

Seed deterministic test accounts and a transfer:

```shell
docker compose --profile tools run --rm seeder
```

The seed command is idempotent. PostgreSQL intentionally has no schema or seed
rows yet; the seeder only verifies its connection.

Stop the environment while retaining data:

```shell
docker compose down
```

Explicitly erase all local database data:

```shell
docker compose down --volumes
```

Database files live only in Docker named volumes. `.env`, database exports,
TigerBeetle files, Terraform state, and build output are excluded from Git.

## Configuration

The API accepts either `ConnectionStrings__Postgres` or the split
`Postgres__Host`, `Postgres__Port`, `Postgres__Database`,
`Postgres__Username`, and `Postgres__Password` settings. AWS uses split
settings so ECS can inject the RDS-managed username and password without
putting a connection string into Terraform state.

TigerBeetle uses:

- `TigerBeetle__ClusterId`
- `TigerBeetle__Addresses` — a comma-separated list of replica addresses.

`GET /status` returns HTTP 200 only when both dependencies answer. Failures
return HTTP 503 and sanitized component status without exception or credential
details. ECS uses `/health/live`, preventing database outages from causing API
restart loops.

## Tests

CI is the authoritative .NET 10 environment:

```shell
dotnet restore Hydra.slnx
dotnet build Hydra.slnx --configuration Release --no-restore
dotnet test Hydra.slnx --configuration Release --no-build
```

The GitHub CI workflow also builds both images, starts the full Compose stack,
runs the seeder twice, verifies `/status`, simulates a PostgreSQL outage,
validates Terraform, and scans for committed secrets.

## AWS bootstrap and deployment

The Terraform states are intentionally independent:

1. `foundation` — VPC, networking, security groups, Cloud Map, and ECR.
2. `postgres` — private encrypted RDS PostgreSQL.
3. `tigerbeetle` — private EC2 replica and retained encrypted EBS volume.
4. `api` — ECS Fargate, one-off seeder task, and API Gateway HTTPS endpoint.

An AWS administrator performs the one-time bootstrap locally:

```shell
terraform -chdir=infra/bootstrap init
terraform -chdir=infra/bootstrap apply
terraform -chdir=infra/bootstrap output
```

Bootstrap creates the versioned, encrypted state bucket and GitHub OIDC roles.
Create a GitHub Environment named `dev`, then add these repository variables
from the Terraform outputs:

| GitHub variable | Value |
| --- | --- |
| `TF_STATE_BUCKET` | `state_bucket` |
| `AWS_FOUNDATION_ROLE_ARN` | `deployment_role_arns.foundation` |
| `AWS_POSTGRES_ROLE_ARN` | `deployment_role_arns.postgres` |
| `AWS_TIGERBEETLE_ROLE_ARN` | `deployment_role_arns.tigerbeetle` |
| `AWS_API_ROLE_ARN` | `deployment_role_arns.api` |

No AWS access keys are stored in GitHub. Deploy the initial environment in this
order using each workflow's **Run workflow** button:

1. Deploy foundation
2. Deploy PostgreSQL
3. Deploy TigerBeetle
4. Deploy API

After bootstrap, successful changes on `main` deploy only the affected
component. Images are immutable and tagged with the Git commit SHA. Database
and TigerBeetle plans reject deletion of stateful storage. ECS deployment
circuit breaking retains the previously healthy API task definition.

The **Seed dev data** workflow is always manual and runs the same seeder as a
one-off private Fargate task.

## Operational notes

- RDS is private, encrypted, single-AZ, backed up for seven days, and protected
  against deletion and Terraform destroy.
- TigerBeetle runs directly under systemd on a private `t3.large`. Its EBS
  volume and network interface survive EC2 replacement; upgrades may cause
  brief dev downtime.
- API Gateway supplies the public HTTPS URL. ECS, RDS, and TigerBeetle have no
  public ingress.
- CloudWatch retains application logs for 14 days and includes initial alarms
  for API errors, RDS CPU/storage, EC2 status, and TigerBeetle service failure.
- Major PostgreSQL upgrades and a production TigerBeetle topology require a
  separate, reviewed migration plan.
