# ADR-0004: Managed and External Runtime Modes

- Status: Superseded in part by the current Docker/Compose removal decision
- Date: 2026-06-29

## Context

The desktop must run self-contained local databases. Earlier planning also
included a reproducible Compose environment; Docker and Compose have since been
removed from the active project workflow until a real use case is approved.

## Decision

The API has explicit `managed` and `external` modes. Its command line is the
sole configuration source; no environment, configuration-file, registry, or
profile precedence exists. Managed mode rejects external-database flags.
External mode requires every database connection flag defined in
[CONTRACTS.md](../planning/v2/CONTRACTS.md).

Managed and packaged API and database traffic is loopback-only. Docker and
Compose are not active project workflows. Authentication, exact-origin CORS,
request limits, redaction, and ephemeral API-generated tokens remain required.

## Rejected alternatives

- Implicit mode selection or configuration from ambient state.
- Allowing external-database flags in managed mode.
- Publishing either database port to the host.
- Advertising or publishing the API on a non-loopback host interface.
- Reintroducing Docker/Compose without an approved use case.

## Consequences

The same API supports self-managed desktop operation and external development
without making packaged operation network-public. Passwords are supplied by
an absolute password-file path and are never copied into arguments, manifests,
or logs. The exact CLI and URL validation remain governed by
[CONTRACTS.md](../planning/v2/CONTRACTS.md).

## Supersession

Changing modes, configuration sources, loopback requirements, or the
Docker/Compose removal decision requires a new ADR that explicitly supersedes
this record.
