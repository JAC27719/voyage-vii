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
