# ADR-0004: Managed and External Runtime Modes

- Status: Accepted
- Date: 2026-06-29

## Context

The desktop must run self-contained local databases while development also
needs a reproducible Compose environment. These uses require explicit,
non-overlapping runtime configuration and a tightly bounded network exception.

## Decision

The API has explicit `managed` and `external` modes. Its command line is the
sole configuration source; no environment, configuration-file, registry, or
profile precedence exists. Managed mode rejects development-container and
external-database flags. External mode requires every database connection
flag defined in [CONTRACTS.md](../planning/v2/CONTRACTS.md).

Managed and packaged API and database traffic is loopback-only. In external
development-container mode only, PostgreSQL and TigerBeetle share an internal,
unpublished Compose bridge with the API. The API may listen on
`0.0.0.0:7800` inside its container only when Compose publishes it host-side
as `127.0.0.1:7800`; database ports are never host-published and the API
advertises `http://127.0.0.1:7800`.

Compose runs PostgreSQL and TigerBeetle concurrently using images pinned by
tag and digest, named volumes, and non-root users where supported.
TigerBeetle `seccomp=unconfined` is permitted only in local development. The
container exception does not relax authentication, exact-origin CORS, request
limits, redaction, or ephemeral API-generated tokens.

## Rejected alternatives

- Implicit mode selection or configuration from ambient state.
- Allowing external-database flags in managed mode.
- Publishing either database port to the host.
- Advertising or publishing the API on a non-loopback host interface.
- Carrying the local-development seccomp exception into packaged operation.

## Consequences

The same API supports self-managed desktop operation and external development
without making packaged operation network-public. Passwords are supplied by
an absolute password-file path and are never copied into arguments, manifests,
or logs. The exact CLI and URL validation remain governed by
[CONTRACTS.md](../planning/v2/CONTRACTS.md).

## Supersession

Changing modes, configuration sources, loopback requirements, Compose
publication, or the bounded container exception requires a new ADR that
explicitly supersedes this record.
