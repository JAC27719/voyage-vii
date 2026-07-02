# ADR-0012: SQLite General-Purpose Database

- Status: Accepted
- Date: 2026-07-01

## Context

Voyage VII is local-first desktop software. The first v2 slice must package,
launch, retain, observe, retry, and shut down its runtime safely on Windows 11
x64. The earlier plan used PostgreSQL as the general-purpose relational store
and TigerBeetle as the financial ledger store.

PostgreSQL proved technically viable, but it makes the local desktop runtime
carry a server process, credential lifecycle, native source build, packaged
runtime tree, external development database, and shutdown path that are larger
than the current product slice needs. SQLite better matches the local-first
deployment shape while preserving SQL migrations and relational documentation.

## Decision

SQLite replaces PostgreSQL as the general-purpose relational database for the
current v2 slice. TigerBeetle remains the specialized ledger database and is
still accessed through its static C ABI.

The Zig API remains the only database client. The desktop host and UI still
have no direct database access. The API accesses SQLite through the official
SQLite C API and owns SQLite connection, migration, health, retry, backup-safe
checkpoint, and shutdown behavior inside the process boundary. SQLite is not a
separate managed child process.

Executable SQL migrations remain authoritative for the implemented relational
schema. `docs/database/sqlite.dbml` is the required dbdiagram.io-compatible
visual representation of the implemented SQLite schema. Every reviewed task
that changes a relational table, column, type, constraint, index, trigger, or
relation owns and updates both the migration and DBML. Proposed schemas remain
under `docs/database/proposed/` and never appear in the implemented diagram.

SQLite runs in WAL mode with a configured busy timeout. The first slice does
not add automatic reset, repair, migration downgrade, or backup UI. Any future
backup feature must coordinate with WAL checkpointing and database file
consistency rather than copying arbitrary live files.

External development mode no longer requires a PostgreSQL server. It may use an
explicit SQLite database path plus the external TigerBeetle address. Docker and
Compose are not active project workflows.

## Rejected alternatives

- Continuing to ship PostgreSQL as the general-purpose database for the
  desktop-first slice.
- Making SQLite a desktop-host concern or allowing UI-side database access.
- Replacing TigerBeetle with SQLite for ledger balances and transfers in this
  amendment.
- Keeping PostgreSQL as a second supported general-purpose database mode in the
  current slice.
- Copying live SQLite data files as a backup or repair substitute.

## Consequences

PostgreSQL-specific implementation, lifecycle, packaging, CLI, manifest, DBML,
and error contracts are superseded for future work. Integrated
PostgreSQL feasibility and adapter commits remain historical evidence, but new
tasks must not build on PostgreSQL unless a later ADR reintroduces it.

The runtime becomes smaller: managed mode initializes and retains SQLite files
instead of starting a PostgreSQL process, generating database passwords, binding
ports, and supervising server shutdown. The API still must treat the database
as durable user data: migrations are transactional, checksum drift is rejected,
busy waits are bounded, logs are sanitized, and writes never occur outside the
approved data root.

Dependency pins, packaging provenance, task ownership, HTTP component IDs,
error codes, manifests, and database documentation must be amended before
additional runtime or HTTP implementation proceeds.

## Supersession

This ADR supersedes the PostgreSQL-specific portions of ADR-0001, ADR-0002,
ADR-0003, ADR-0004, ADR-0007, ADR-0008, and ADR-0011. It does not supersede the
single API database-client boundary, TigerBeetle C ABI decision, local-first
process boundary, token model, Windows 11 x64 current gate, or ADR rule that
accepted records are changed only by new superseding ADRs.
