# RUNTIME-002 — Managed SQLite Lifecycle

**Implementer inference:** Low  
**Prerequisites:** `API-005` and `RUNTIME-001` approved.

## Frozen inputs

Use ADR-0012, SQLite pins from `DEPENDENCY-PINS.md`, manifest/CLI/error contracts from `CONTRACTS.md`, exact deadlines/retries from `TIMEOUTS.md`, native source/layout rules from `PACKAGING.md`, and only the SQLite seams authorized by `PLAN-002`. Stop if shared files must change.

## Objective

Initialize, open, probe, retain, checkpoint, and close the managed SQLite database safely.

## Procedure

1. Detect pristine versus initialized versus invalid SQLite data roots without destructive guessing.
2. Create only root-contained database and WAL paths with restrictive platform permissions.
3. Open SQLite with the approved flags and configure WAL, foreign keys, and busy timeout.
4. Probe readiness, apply migrations, and expose sanitized state.
5. Retry initial open plus delays of one, two, and four seconds.
6. On shutdown, quiesce writers, perform the approved checkpoint/close sequence within ten seconds, and then rely on the common process boundary if the API must exit.

## Acceptance evidence

- First-run, retained-run, unavailable source/build input, corrupt root, wrong permissions, busy database, failed migration, checkpoint/close, and forced-process-exit tests.
- All native runtime evidence is Windows 11 x64. Optional non-Windows
  compilation is informational only.
- Path, SQL-value, and CLI/log leakage checks.
- `zig build test` through the static aggregate registration and `git diff --check`.

## Reviewer focus

Verify initialization never overwrites non-pristine data, SQLite files remain root-contained, WAL/checkpoint behavior is bounded, and sanitized errors do not expose local paths or SQL values.
