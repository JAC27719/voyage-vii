# Development Runbook

These commands are supported only on Windows 11 x64. Run them from the
repository root in PowerShell 7 unless a command says otherwise.

## Toolchain

The frozen direct toolchain pins are:

- Zig `0.15.2` for the application API.
- Zig `0.14.1` for the TigerBeetle C client build.
- Rust `1.96.0`.
- Bun `1.3.14`.
- TigerBeetle `0.17.7`.
- SQLite `3.53.3`.

Install missing host tools explicitly. Project scripts do not silently perform
privileged installation.

## Environment Doctor

```powershell
pwsh -NoProfile -File tools/doctor/voyage-doctor.ps1
```

For machine-readable output:

```powershell
pwsh -NoProfile -File tools/doctor/voyage-doctor.ps1 -Json
```

## Bootstrap Profiles

Compose profile readiness:

```powershell
pwsh -NoProfile -File scripts/bootstrap/bootstrap.ps1 -Profile compose
```

Desktop dependency readiness:

```powershell
pwsh -NoProfile -File scripts/bootstrap/bootstrap.ps1 -Profile desktop
```

Runtime staging readiness:

```powershell
pwsh -NoProfile -File scripts/bootstrap/bootstrap.ps1 -Profile packaging -Offline
```

Run all current bootstrap profiles:

```powershell
pwsh -NoProfile -File scripts/bootstrap/bootstrap.ps1 -Profile all -Offline
```

## External Compose Mode

Compose runs the API in external mode with API-owned SQLite storage and
TigerBeetle on an internal Compose network. The API is published host-side only
on `127.0.0.1:7800`; TigerBeetle is not host-published. The API advertises
`http://127.0.0.1:7800` and uses development origin `http://localhost:1420`.

The API image must be an approved exact `0.1.0` tag and digest pin. DOC-002
does not document a live Compose startup command because no approved
first-party API image digest is currently recorded for operator use. The
verified local command is the Compose configuration check with an exact pin
shape:

```powershell
$env:VOYAGE_VII_API_IMAGE = "voyage-vii-api:0.1.0@sha256:0000000000000000000000000000000000000000000000000000000000000000"
docker compose --file compose.yaml config --quiet
```

Normal stop is safe to run when Compose containers exist:

```powershell
$env:VOYAGE_VII_API_IMAGE = "voyage-vii-api:0.1.0@sha256:0000000000000000000000000000000000000000000000000000000000000000"
pwsh -NoProfile -File scripts/compose/stop.ps1
```

Destructive volume removal exists in `scripts/compose/down-volumes.ps1` and is
intentionally not a normal runbook command.

## Managed Desktop Mode

Managed desktop mode launches `voyage-vii-api` from the packaged runtime,
captures the stdout handshake in memory, keeps the supervisor token out of
JavaScript, and exposes the app token only through the desktop bridge snapshot.
Managed and packaged traffic is loopback-only.

The writable application root contains:

```text
manifest.json
runtime.lock
logs/
sqlite/
tigerbeetle/
```

The desktop supervisor restarts unexpected API exits up to three times in five
minutes. A fourth exit is terminal. During intentional shutdown it sends the
supervisor-authenticated shutdown request, waits up to 20 seconds for graceful
API exit, terminates the process group, waits five seconds, then force-kills
and reaps it.

## Test Commands

Unit and static checks:

```powershell
pwsh -NoProfile -File scripts/test/test.ps1 -Command unit
```

Compose smoke with an approved image pin is a CI-001-gated command and remains
blocked until an approved exact API image digest is available.

Managed smoke:

```powershell
pwsh -NoProfile -File scripts/test/test.ps1 -Command managed-smoke
```

Managed failure matrix:

```powershell
pwsh -NoProfile -File scripts/test/test.ps1 -Command managed-failure
```

Package smoke staging:

```powershell
pwsh -NoProfile -File scripts/test/test.ps1 -Command package-smoke
```

Hardening matrix:

```powershell
pwsh -NoProfile -File tests/hardening/run-hardening.ps1 -Command all
```

Package-smoke adapter fixtures:

```powershell
pwsh -NoProfile -File tests/package-smoke/run-tests.ps1
```

Runtime-staging fixtures:

```powershell
pwsh -NoProfile -File tests/runtime-staging/run-tests.ps1
```

Each harness step is bounded to 120 seconds. Local aggregate test runs are
bounded to 20 minutes.

## Module Registration

The UI uses a static SolidJS module registry. Future modules must follow the
registered route/client/schema pattern already established in the desktop
source, and any public contract change must first update the frozen contract
records and ADRs through a new reviewed task.

Accepted ADRs are immutable. Changed decisions are recorded by adding a new ADR
that explicitly supersedes earlier records; see [ADR index](../adr/README.md).

## Verified Commands

DOC-002 command verification is recorded in
[command-verification.md](command-verification.md).
