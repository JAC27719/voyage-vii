# ADR-0001: Local-First Process Boundaries

- Status: Accepted
- Date: 2026-06-29

## Context

The first v2 slice must prove a complete local desktop runtime without
reintroducing the uncertain cloud and process ownership of v1. The UI, desktop
host, API, PostgreSQL, and TigerBeetle need one explicit owner at every process
boundary.

## Decision

Voyage VII is a local-first desktop application. SolidJS/Tailwind UI traffic
goes through authenticated REST to a Zig API. The API connects to PostgreSQL
and TigerBeetle and owns both database processes in managed mode. Tauri owns
the window, single-instance behavior, API launch and final containment,
handshake consumption, token custody, logs, restart policy, and shutdown.

Tauri contains no database access or financial business logic. TigerBeetle is
not the REST server. The first slice does not include cloud infrastructure or
deployment. Process shutdown must leave neither data loss nor orphan
processes.

## Rejected alternatives

- Making Tauri or the UI access either database directly.
- Making TigerBeetle the REST server.
- Giving more than one layer responsibility for supervising the same process.
- Introducing cloud deployment into the local-runtime slice.

## Consequences

The Zig API is the single database-facing service and Tauri is the single API
supervisor. Managed lifecycle, retry, observation, and containment are
architecture work rather than packaging afterthoughts. The exact boundaries
and completion criteria remain frozen in
[ARCHITECTURE.md](../planning/v2/ARCHITECTURE.md).

## Supersession

Any change to process ownership, direct database access, the local-first
boundary, or the absence of cloud deployment requires a new ADR that explicitly
supersedes this record and the affected frozen planning decisions.
