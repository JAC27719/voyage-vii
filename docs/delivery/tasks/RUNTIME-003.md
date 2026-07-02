# RUNTIME-003 — Managed TigerBeetle Lifecycle

**Implementer inference:** Low  
**Prerequisites:** `API-003` and `RUNTIME-001` approved.

## Frozen inputs

Use TigerBeetle `0.17.7` and Zig `0.14.1` from `DEPENDENCY-PINS.md`, manifest/error contracts from `CONTRACTS.md`, exact deadlines/retries from `TIMEOUTS.md`, native source/layout rules from `PACKAGING.md`, and only API-001's predeclared managed-TigerBeetle seam. Stop if shared files must change.

## Objective

Format only pristine storage and safely supervise the packaged single-replica TigerBeetle service.

## Procedure

1. Classify the data directory as pristine, initialized, or invalid.
2. On pristine roots only, generate and persist a random cluster ID and format one replica.
3. Configure a 128 MiB cache and dynamic loopback address.
4. Start within the common process containment boundary.
5. Probe through the production C adapter.
6. Apply the initial plus one-, two-, and four-second retry policy.
7. Refuse automatic reformat, reset, or repair of existing or damaged data.
8. Request graceful shutdown for ten seconds, then escalate and reap the process.

## Acceptance evidence

- First-run, retained-run, non-pristine, corrupt root, wrong binary, occupied port, retry, and shutdown tests.
- All native runtime evidence is Windows 11 x64. Optional non-Windows
  compilation is informational only.
- Proof that damaged data remains untouched.
- `zig build test` through the static aggregate registration and `git diff --check`.

## Reviewer focus

Inspect pristine detection, cluster-ID persistence, command construction, and all branches that might accidentally format existing storage.
