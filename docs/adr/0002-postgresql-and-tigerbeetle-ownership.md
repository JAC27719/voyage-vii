# ADR-0002: PostgreSQL and TigerBeetle Ownership

- Status: Accepted
- Date: 2026-06-29

## Context

The runtime uses both PostgreSQL and TigerBeetle, but they have different data
models and documentation needs. An implemented relational diagram must not
drift from executable migrations, and TigerBeetle must not be represented as a
relational database.

## Decision

The Zig API is the only database client and supervises PostgreSQL and
TigerBeetle concurrently in managed mode. PostgreSQL is accessed through
pg.zig; TigerBeetle is accessed through its C ABI.

Executable SQL migrations are authoritative for the implemented PostgreSQL
schema. `docs/database/postgresql.dbml` is the required dbdiagram.io-compatible
visual representation. Every reviewed task that changes a relational table,
column, type, constraint, index, or relation owns and updates both the
migration and DBML. Proposed schemas remain under `docs/database/proposed/`
and never appear in the implemented diagram.

TigerBeetle is non-relational. Its account and transfer field mappings and
links to PostgreSQL identifiers belong in `docs/database/tigerbeetle.md`, not
in fictitious relational tables. Financial product behavior is not implemented
in this slice; its separate, non-authoritative future record is
[FUTURE-FINANCE.md](../planning/v2/FUTURE-FINANCE.md).

## Rejected alternatives

- Allowing the desktop host or UI to become a second database client.
- Updating a migration without its implemented DBML representation.
- Mixing proposed tables into the implemented schema diagram.
- Modeling TigerBeetle as relational tables.
- Treating deferred financial-domain decisions as first-slice behavior.

## Consequences

Schema-changing work is serialized as one owned review unit. DBML contains
schema namespaces, keys, nullability, defaults, constraints, indexes, relation
direction, and concise domain notes, but no credentials, connection strings,
local paths, or production data.

## Supersession

Changing database ownership, adapter boundaries, schema authority, DBML
synchronization, or TigerBeetle's documentation model requires a new ADR that
explicitly supersedes this record.
