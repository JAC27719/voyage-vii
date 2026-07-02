# Voyage VII v2 Frozen Contracts

This document freezes the shared process, HTTP, manifest, and version contracts. Implementers must consume these values directly and stop if an owned seam cannot implement them without changing another task's paths.

## Product version

The product version is `0.1.0`. The repository-root `VERSION` file is the sole source and contains exactly `0.1.0` plus a trailing newline. `API-001` creates it. Package names and runtime manifests read this file rather than duplicating the value.

## API CLI

The API executable is `voyage-vii-api`.

```text
voyage-vii-api serve \
  --runtime managed|external \
  --runtime-root <absolute-path> \
  --data-root <absolute-path> \
  --allowed-origin <origin> \
  --handshake stdout-v1 \
  [--listen <ip:port>] \
  [--advertised-api-url <url>] \
  [external database flags]
```

`--runtime-root`, `--data-root`, `--allowed-origin`, and `--handshake stdout-v1` are required in both modes. `--listen` defaults to `127.0.0.1:0`. `--advertised-api-url` defaults to the actual bound loopback URL and must always be an HTTP loopback URL with no credentials, path, query, or fragment.

Managed mode rejects every external database flag.

External mode requires all of:

- `--sqlite-path <absolute-path>`
- `--tigerbeetle-address <address>`

The SQLite path must be absolute, root-contained, and logged only through
sanitized diagnostics.

A non-loopback `--listen` value is rejected. Docker and Compose are not active
project workflows.

The CLI is the sole configuration source. There are no implicit environment-variable, configuration-file, registry, or user-profile values and therefore no configuration-precedence rules.

Other commands are:

- `voyage-vii-api self-test`
- `voyage-vii-api version`

Exit codes are mandatory:

- `0`: normal completion
- `2`: configuration failure
- `3`: data-root lock failure
- `4`: runtime-asset failure
- `5`: bind or startup failure
- `6`: self-test failure
- `7`: native shutdown timeout

## Origins and transport

Accepted origins are exact single values:

- Windows packaged: `http://tauri.localhost`
- development: `http://localhost:1420`

Future macOS/Linux origins require a future ADR/task wave and are not current
support contracts.

Managed and packaged traffic is loopback-only. Docker and Compose are not
active project workflows.

## Handshake and tokens

When requested, stdout contains exactly one line:

```text
VOYAGE_VII_HANDSHAKE {"protocolVersion":1,"apiUrl":"http://127.0.0.1:<port>","appToken":"<base64url>","supervisorToken":"<base64url>"}
```

The API binds, validates its advertised URL, and emits the handshake before asynchronous database initialization. The handshake and database-readiness deadlines are distinct and are frozen in `TIMEOUTS.md`.

In every mode, the API generates distinct app and supervisor tokens as independent 32-byte CSPRNG values encoded as unpadded base64url. Tokens are memory-only and never logged or persisted. HTTP authentication uses `Authorization: Bearer <token>`.

## HTTP rules

- CORS accepts only the exact configured origin and never permits credentials.
- Request bodies are limited to 64 KiB.
- Token comparison is constant-time.
- Every response includes `X-Request-Id`; response JSON that includes a request ID uses the same value.
- JSON field names use camelCase.

Routes:

| Method and route | Authorization |
| --- | --- |
| `GET /health/live` | Unauthenticated |
| `GET /health/ready` | Unauthenticated |
| `GET /api/v1/system/status` | App token only |
| `POST /api/v1/system/components/{sqlite\|tigerbeetle}/retry` | App token only |
| `POST /api/v1/system/retry` | App token only |
| `POST /api/v1/system/shutdown` | Supervisor token only |

App and supervisor scopes are disjoint. On an authenticated route, a missing or invalid bearer token returns `401 unauthorized`; a valid token from the wrong scope returns `403 forbidden`.

Exact-origin CORS preflight `OPTIONS` for each listed route is unauthenticated and returns `204` with no body. A rejected origin returns `403 origin_not_allowed`.

Health bodies are exactly:

```json
{"status":"live"}
```

```json
{"status":"ready"}
```

```json
{"status":"notReady"}
```

Readiness returns `200` only for `ready`; `notReady` returns `503`.

The status route returns `200`. Its response has `schemaVersion: 1`, `requestId`, `overallState`, and `components`.

- `overallState`: `starting | ready | degraded | stopping`
- component `id`: `sqlite | tigerbeetle`
- component `displayName`: technical display name
- component `version`: pinned version
- component `state`: `starting | healthy | retrying | unhealthy | stopping | stopped`
- component `lastCheckedAt`: nullable RFC3339 UTC timestamp
- component `attemptCount`: unsigned 32-bit integer
- component `error`: nullable sanitized error object using the standard error shape

Retry returns `202`:

```json
{"requestId":"opaque-id","accepted":true,"targets":["sqlite"]}
```

`targets` contains only requested component IDs in stable `sqlite`, `tigerbeetle` order. Healthy-component and duplicate-active retries return `accepted: false` without restart. Retry-all never restarts a healthy component.

Shutdown returns `202`:

```json
{"requestId":"opaque-id","accepted":true}
```

A second shutdown request after stopping begins returns `503 shutting_down`.

Errors use:

```json
{
  "error": {
    "code": "stable_machine_code",
    "message": "Sanitized user-safe message",
    "requestId": "opaque-id"
  }
}
```

The complete allowed error-code set is:

- `invalid_request`
- `body_too_large`
- `unauthorized`
- `forbidden`
- `origin_not_allowed`
- `method_not_allowed`
- `not_found`
- `component_not_found`
- `retry_not_allowed`
- `service_unavailable`
- `shutting_down`
- `internal_error`
- `sqlite_unavailable`
- `sqlite_busy`
- `sqlite_timeout`
- `tigerbeetle_unavailable`
- `tigerbeetle_timeout`
- `native_shutdown_timeout`
- `runtime_asset_missing`
- `runtime_asset_invalid`
- `data_root_locked`

Exact HTTP status mapping:

| Status | Error codes |
| --- | --- |
| `400` | `invalid_request` |
| `401` | `unauthorized` |
| `403` | `forbidden`, `origin_not_allowed` |
| `404` | `not_found`, `component_not_found` |
| `405` | `method_not_allowed` |
| `409` | `retry_not_allowed`, `data_root_locked` |
| `413` | `body_too_large` |
| `500` | `internal_error` |
| `503` | `service_unavailable`, `shutting_down`, `sqlite_unavailable`, `sqlite_busy`, `sqlite_timeout`, `tigerbeetle_unavailable`, `tigerbeetle_timeout`, `native_shutdown_timeout`, `runtime_asset_missing`, `runtime_asset_invalid` |

Valid retry requests remain `202`; the status route remains `200`; health statuses remain as frozen above.

Workers may map native causes only to this set. Adding or renaming a public code requires a coordinator amendment.

`native_shutdown_timeout` is returned as HTTP `503` only if the TigerBeetle
deinitialization watchdog failure is observable before mandatory process exit.
The API otherwise terminates immediately with exit code `7`.

## Packaged runtime manifest v1

`resources/runtime/manifest.json` is version 1 and contains:

- `schemaVersion`: integer `1`
- `productVersion`: `0.1.0`, read from `VERSION`
- `target`: the current frozen Windows target triple; the field remains
  extensible for future target-bearing manifests
- `components`: array in stable `api`, `sqlite`, `tigerbeetle` order

Each component contains:

- `id`: `api | sqlite | tigerbeetle`
- `version`
- `path`: relative POSIX path
- `sha256`: 64-character lowercase hexadecimal SHA-256
- `licensePath`: required relative POSIX path for `sqlite` and `tigerbeetle`; exactly `null` for the first-party `api`
- `source`:
  - `kind`: `official-source | official-release | first-party-build`
  - `url`: required absolute HTTPS URL for `official-source` and `official-release`; exactly `null` for `first-party-build`
  - `revision`: immutable tag/source revision for official components; the full audited Git commit for `first-party-build`

The private first-party API intentionally has no license or source URL; workers must not invent either value. The manifest contains no secret, credential, absolute path, token, local cache path, or user data.

## Writable-root manifest v1

The writable-root `manifest.json` contains:

- `schemaVersion`: integer `1`
- `productVersion`: `0.1.0`
- `target`: the current frozen Windows target triple; the field remains
  extensible for future targets
- `createdAt`: RFC3339 UTC timestamp
- `components`: object containing the SQLite and TigerBeetle versions

Nonsecret cluster identifiers may be present when needed for validation. Database secrets are stored separately with restrictive permissions when a component requires them and never appear in the manifest.
