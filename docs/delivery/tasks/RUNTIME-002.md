# RUNTIME-002 — Managed PostgreSQL Lifecycle

**Implementer inference:** Low  
**Prerequisites:** `API-002` and `RUNTIME-001` approved.

## Frozen inputs

Use PostgreSQL `18.4` from `DEPENDENCY-PINS.md`, manifest/CLI/error contracts from `CONTRACTS.md`, exact deadlines/retries from `TIMEOUTS.md`, native source/layout rules from `PACKAGING.md`, and only API-001's predeclared managed-PostgreSQL seam. Stop if shared files must change.

## Objective

Initialize, start, probe, retain, and stop the packaged PostgreSQL instance safely.

## Procedure

1. Detect pristine versus initialized versus invalid data roots without destructive guessing.
2. On pristine roots, run initialization with UTF-8/C locale and SCRAM.
3. Generate a random persisted database secret and apply restrictive platform permissions.
4. Configure loopback-only binding and a dynamic port.
5. Start PostgreSQL within the managed process containment boundary.
6. Probe readiness, apply migrations, and expose sanitized state.
7. Retry initial startup plus delays of one, two, and four seconds.
8. On shutdown, request fast graceful shutdown, wait ten seconds, then escalate through the common process boundary.

## Acceptance evidence

- First-run, retained-run, unavailable binary, corrupt root, wrong permissions, occupied port, failed migration, graceful shutdown, and forced shutdown tests.
- Secret-permission and CLI/log leakage checks.
- `zig build test` through the static aggregate registration and `git diff --check`.

## Reviewer focus

Verify initialization never runs on non-pristine data, secrets avoid arguments/logs, and every child/temporary credential file is cleaned safely.
