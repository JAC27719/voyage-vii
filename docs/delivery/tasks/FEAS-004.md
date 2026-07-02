# FEAS-004 — Prove SQLite Native Integration

**Implementer inference:** Low
**Prerequisites:** `PLAN-002` approved.

## Frozen inputs

Use ADR-0012, the dependency policy in `DEPENDENCY-PINS.md`, Windows-only
current gate rules from ADR-0011, and the existing Zig/api.zig foundation. Do
not modify production API behavior beyond spike/provenance evidence.

## Objective

Freeze the exact official SQLite amalgamation source and prove it can be built
and called from the Zig API toolchain on Windows 11 x64.

## Procedure

1. Select only an official sqlite.org amalgamation archive and record its
   version, immutable download URL, and archive hash.
2. Build a minimal Zig spike with application Zig `0.15.2` that links the
   unmodified SQLite C source.
3. Exercise open, WAL configuration, foreign-key enablement, busy-timeout
   configuration, transaction, simple migration-table DDL, `SELECT 1`, and
   clean close on Windows 11 x64.
4. Record compile flags, source provenance, license evidence, and generated
   binary evidence needed by packaging.
5. Amend `DEPENDENCY-PINS.md` only if all evidence passes, replacing the
   `FEAS-004` placeholder with the exact SQLite version, official archive URL,
   archive hash, and approved compile-time options.

## Acceptance evidence

- Official SQLite source URL, version, hash, and license evidence.
- Native Windows 11 x64 Zig build and run output for the SQLite spike.
- WAL, foreign-key, busy-timeout, migration-table, transaction, probe, and close
  results.
- Search proving no unapproved SQLite wrapper, fork, binary distribution, or
  alternate supplier was introduced.
- `git diff --check`.

## Reviewer focus

Reject unofficial SQLite sources, wrapper dependencies, hidden binary inputs,
mutable URLs without hashes, feature flags that change durability semantics, or
any claim of production adapter behavior before `API-005`.
