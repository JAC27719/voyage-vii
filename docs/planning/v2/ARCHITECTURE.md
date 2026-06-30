# Voyage VII v2 Architecture

## Product boundary

Voyage VII is a local-first desktop application. The first v2 slice proves that
the complete runtime can be developed, packaged, launched, observed, retried,
and shut down safely on Windows 11 x64.

TigerBeetle is not the REST server. The REST server is a Zig executable using api.zig. That executable connects to PostgreSQL through pg.zig and to TigerBeetle through TigerBeetle's C ABI.

```text
SolidJS / Tailwind UI
        |
        | authenticated loopback REST
        v
Zig API using api.zig
   |                    |
   | pg.zig             | TigerBeetle C ABI
   v                    v
PostgreSQL          TigerBeetle

Tauri / Rust
   |
   +-- window, single-instance behavior, API launch, handshake,
       token custody, logs, restart policy, and final process containment
```

Tauri contains no database access or financial business logic. The Zig API owns and supervises PostgreSQL and TigerBeetle in managed mode.

## Identity and targets

- Product: `Voyage VII`
- Slug: `voyage-vii`
- API executable: `voyage-vii-api`
- Bundle ID: `io.github.jac27719.voyage-vii`
- Windows 11 x64: `x86_64-pc-windows-msvc`

Windows 11 x64 is the sole current build, runtime, package, smoke, and
completion gate. macOS Intel (`x86_64-apple-darwin`), macOS Apple Silicon
(`aarch64-apple-darwin`), and Linux x64 (`x86_64-unknown-linux-gnu`) are
deferred future targets. Cross-builds and stubs for them are informational only
and do not confer native evidence or support.

Portability remains an architectural constraint: core contracts, business
logic, and runtime orchestration cannot expose Windows-native types.
Platform/process/filesystem paths stay behind explicit interfaces,
target-bearing manifests remain extensible, and current implementation avoids
needless Windows coupling.

## Pinned foundations

- Application Zig: `0.15.2`
- api.zig: `f9a287916ad0e34fda71c8e5b619c5774c8fbb45`
- pg.zig `zig-0.15`: `12e48fc57b78486e338e8707448d9a87597dd3ad`
- TigerBeetle: `0.17.7`, client built with its required Zig `0.14.1`
- PostgreSQL: `18.4`
- Tauri: version 2

All toolchain, NPM, and Rust direct pins are frozen in `DEPENDENCY-PINS.md`. Manifests use exact constraints and committed lockfiles. A failure to use api.zig or the static TigerBeetle C ABI on any target is a stop-the-line ADR decision. No worker may silently substitute another framework, dependency, supplier, or transport.

## API process contract

The exact CLI, origins, handshake, exit codes, response schemas, stable errors, and manifest schemas are frozen in `CONTRACTS.md`.

Requirements:

- The API binds and emits the validated handshake before asynchronous database initialization.
- Handshake arrives within 15 seconds and is no larger than 16 KiB.
- URL is HTTP and loopback-only, with no credentials, path, query, or fragment.
- Tokens are distinct 32-byte CSPRNG values encoded base64url.
- Tokens are memory-only and never logged.
- All logs go to stderr.
- Initial database readiness target is 60 seconds.
- Exit codes `0`, `2`, `3`, `4`, `5`, and `6` have the mandatory meanings in `CONTRACTS.md`.
- Exit code `7` means `native shutdown timeout`.
- Runtime and protocol deadlines use `TIMEOUTS.md`.

The pinned api.zig accept loop has no public stop API. Graceful API shutdown
therefore accepts the supervisor route, quiesces requests, protects and stops
PostgreSQL, TigerBeetle, logs, and owned resources, and exits the API process.
The accept loop need not return; Windows closes the listener at process exit.

## REST contract

Implement only the routes and exact request/response contracts in `CONTRACTS.md`. The checked-in schemas and fixtures created by `API-001` encode that frozen contract and are the source of truth for Zig, Rust, and TypeScript.

CORS accepts only the exact configured origin without credentials. Tokens use `Authorization: Bearer` and constant-time comparison. Every response includes `X-Request-Id`. Request bodies are limited to 64 KiB. Retry and shutdown return `202 Accepted`; healthy or duplicate retries return `accepted: false` without restarting a component.

## Desktop contract

Tauri exposes only:

- `get_runtime_snapshot`
- `open_logs`

```ts
type RuntimeSnapshot = {
  generation: number;
  state: "launching" | "connected" | "restarting" | "failed" | "stopping";
  connection?: {
    apiUrl: string;
    appToken: string;
  };
  error?: {
    code: string;
    message: string;
  };
};
```

Tauri emits `voyage-vii://runtime-changed` containing only `generation` and `state`. The UI then calls `get_runtime_snapshot`. The supervisor token never enters JavaScript.

Unexpected API exits use a rolling budget of three restarts in five minutes. A
fourth exit is terminal. Exit `7` is terminal/restart-budget behavior during
normal operation. During intentional desktop shutdown Tauri must not restart
exit `7`; it remains the final process-containment owner, verifies no
descendants, and uses the 20-second graceful, five-second terminate,
force-kill-and-reap sequence.

All other desktop and adapter deadlines use `TIMEOUTS.md`.

## Managed data

The writable application root contains:

```text
manifest.json
runtime.lock
logs/
postgresql/
tigerbeetle/
```

- Hold an exclusive OS lock.
- PostgreSQL uses a random persisted SCRAM secret, loopback binding, UTF-8/C locale, pool size two, and fast shutdown.
- TigerBeetle uses a random persisted cluster ID, one local replica, and a 128 MiB cache.
- TigerBeetle formatting is allowed only for a demonstrably pristine root.
- Database startup retries are initial attempt plus three retries after one, two, and four seconds.
- Healthy probes run every ten seconds; transitioning/unhealthy probes run every second without overlap.
- PostgreSQL probe is `SELECT 1`; TigerBeetle probe is a real harmless lookup.
- Total rotating logs should remain near 50 MiB.
- Idle memory target is approximately 500 MiB or less.
- There is no automatic reset, repair, migration upgrade, or backup feature in this slice.
- The writable manifest is exactly version 1 from `CONTRACTS.md`; credentials remain in separate restricted files.

## Database schema documentation

Track the implemented PostgreSQL schema in `docs/database/postgresql.dbml` using DBML accepted by dbdiagram.io.

- SQL migrations remain the executable runtime source of truth.
- The DBML file is the required visual/design representation of the same schema.
- Every migration that changes a table, column, type, constraint, index, or relation must update DBML in the same reviewed task.
- DBML must include schema namespaces, primary and foreign keys, nullability, defaults, unique constraints, indexes, relation direction, and concise domain notes.
- `docs/database/README.md` explains how to import the file into dbdiagram.io and how synchronization is reviewed.
- Proposed, unimplemented schemas belong under `docs/database/proposed/` and must be labeled as proposals. They must never appear in `postgresql.dbml`.
- TigerBeetle is not relational. Its account/transfer field mappings and links to PostgreSQL identifiers belong in `docs/database/tigerbeetle.md`, not as fictitious relational tables in the implemented PostgreSQL diagram.
- DBML and companion documentation must contain no credentials, connection strings, local paths, or production data.

## Packaged runtime

Artifact naming, Windows runtime location, native source policy, and provenance
are frozen in `PACKAGING.md`. The packaged manifest is exactly version 1 from
`CONTRACTS.md`.

Deliverables:

- Windows x64 portable ZIP

Native macOS and Linux packages, sealing/layout requirements, installers,
automatic updates, and production distribution are deferred. CI retention is
seven days.

## Development-container network exception

Managed and packaged operation remains loopback-only. In external development-container mode only:

- PostgreSQL and TigerBeetle traffic uses an internal, non-published Compose bridge.
- The API listens on `0.0.0.0:7800` only inside its container.
- Compose publishes that API port host-side exclusively as `127.0.0.1:7800`.
- PostgreSQL and TigerBeetle ports are never host-published.
- The API advertises `http://127.0.0.1:7800`.
- Exact-origin CORS, bearer authentication, ephemeral API-generated tokens, request limits, and redaction remain mandatory.
