# Operations Runbook

Voyage VII v2 operates locally on Windows 11 x64. Managed and packaged traffic
is loopback-only. The development-container exception is limited to Compose
external mode and does not relax CORS, token, advertised URL, or host-publication
rules.

## Process Ownership

The Tauri desktop process owns the API process. The Zig API owns SQLite access
and supervises TigerBeetle in managed mode. Tauri does not access databases or
financial business logic.

The API executable is `voyage-vii-api`. Its supported commands are:

- `voyage-vii-api serve`
- `voyage-vii-api self-test`
- `voyage-vii-api version`

Exit codes are:

- `0`: normal completion
- `2`: configuration failure
- `3`: data-root lock failure
- `4`: runtime-asset failure
- `5`: bind or startup failure
- `6`: self-test failure
- `7`: native shutdown timeout

## Tokens And HTTP

The API emits one stdout handshake line when requested. It contains the
loopback API URL, app token, and supervisor token. Tokens are distinct
API-generated 32-byte CSPRNG values, memory-only, and never logged or persisted.

HTTP authentication uses `Authorization: Bearer <token>`.

- App-token routes: system status and retry routes.
- Supervisor-token route: system shutdown.
- Health routes are unauthenticated.

Accepted origins are exactly:

- Windows packaged: `http://tauri.localhost`
- Development: `http://localhost:1420`

Every response includes `X-Request-Id`. Request bodies are limited to 64 KiB.

## Ports

Managed and packaged mode bind loopback only. Compose external mode uses
`--listen 0.0.0.0:7800` only inside the API container and advertises
`http://127.0.0.1:7800`. Compose publishes the API host-side only as
`127.0.0.1:7800`. TigerBeetle is internal to the Compose network and is not
host-published.

## Status And Retry

System status returns `overallState` as `starting`, `ready`, `degraded`, or
`stopping`. Component states are `starting`, `healthy`, `retrying`,
`unhealthy`, `stopping`, or `stopped`.

Components are `sqlite` and `tigerbeetle`. Retry-all never restarts a healthy
component. Healthy-component and duplicate-active retries return
`accepted: false`.

## Logs And Diagnostics

Logs are structured and redacted. They must not contain names, amounts, tokens,
authorization headers, SQL values, raw native exceptions, handshakes, local
cache paths, or user data. Total rotating logs should remain near 50 MiB.

Use the desktop `open_logs` command through the UI to open logs. Use sanitized
diagnostics only when reporting failures.

## Shutdown

The desktop supervisor sends the supervisor-authenticated shutdown request,
waits up to 20 seconds for graceful API exit, terminates the process group,
waits five seconds, then force-kills and reaps it.

SQLite close and checkpoint are bounded to 10 seconds. TigerBeetle graceful
process stop is bounded to 10 seconds. Official TigerBeetle C
`tb_client_deinit` runs on a dedicated shutdown thread with a 10-second
watchdog; if it misses the watchdog, the API exits with code `7`.

## Backups

There is no automatic backup feature in this slice. To make a manual backup,
stop the application first, confirm no Voyage VII, `voyage-vii-api`, or
TigerBeetle process remains, then copy the stopped writable application root as
a directory.

Do not copy live SQLite or TigerBeetle files while the application is running.

## Absent Features

This slice does not include automatic reset, repair, upgrade, automatic backup,
installers, production signing, notarization, auto-update, telemetry, metrics,
cloud deployment, or financial product behavior.

Native macOS and Linux support is deferred to a future ADR/task wave.
