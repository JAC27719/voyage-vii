# ADR-0003: Zig REST and Native Database Clients

- Status: Accepted
- Date: 2026-06-29

## Context

Native compatibility and cross-platform packaging are architectural
constraints. The REST framework and database clients must therefore be proven
on all supported targets before feature implementation.

## Decision

The API is a Zig `0.15.2` executable using api.zig at
`f9a287916ad0e34fda71c8e5b619c5774c8fbb45`. PostgreSQL access uses the
`zig-0.15` pg.zig revision
`12e48fc57b78486e338e8707448d9a87597dd3ad`. TigerBeetle is version `0.17.7`
and is accessed through its static C ABI; its client is built with required
Zig `0.14.1`.

Compatibility of api.zig with pg.zig and of the TigerBeetle C ABI is proved
before production implementation. All four supported targets gate the
architecture. Failure to use api.zig or the static TigerBeetle C ABI on any
target stops implementation for an explicit go/no-go ADR.

## Rejected alternatives

- Silently replacing api.zig, pg.zig, the TigerBeetle C ABI, or the transport.
- Advancing feature work before the compatibility gates complete.
- Treating success on only one target as architecture proof.

## Consequences

The native seams remain visible and independently testable. Direct versions
and revisions are exact; the complete dependency requirements are governed by
[DEPENDENCY-PINS.md](../planning/v2/DEPENDENCY-PINS.md).

## Supersession

Changing the API language, REST framework, PostgreSQL client, TigerBeetle
client boundary, required toolchains, or compatibility gate requires a new ADR
that explicitly supersedes this record.
