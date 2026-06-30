# FEAS-001 — Prove api.zig and pg.zig Compatibility

**Implementer inference:** Low  
**Prerequisites:** `RESET-001` approved.

## Frozen inputs

Use the exact Zig, api.zig, pg.zig, and PostgreSQL pins in `DEPENDENCY-PINS.md`, adapter limits in `TIMEOUTS.md`, and PostgreSQL source policy in `PACKAGING.md`. Do not select alternate revisions or suppliers.

## Objective

Prove the pinned api.zig and pg.zig revisions work with Zig `0.15.2` and PostgreSQL `18.4` before production scaffolding.

## Procedure

1. Create an isolated spike using only the approved revisions.
2. Build one api.zig endpoint and expose a deterministic response.
3. Connect through pg.zig to PostgreSQL `18.4` and execute `SELECT 1`.
4. Exercise clean connection, unavailable server, authentication failure, and graceful cleanup.
5. Compile for all target triples and run natively on each required platform.
6. Document exact commands, dependency provenance, and any source incompatibility.
7. Do not patch or fork a dependency without a coordinator-approved ADR amendment.

## Acceptance evidence

- Clean-cache dependency and build logs.
- Native endpoint and PostgreSQL probe results.
- Cross-target build matrix.
- Binary architecture inspection.
- Failure-path output with secrets redacted.
- Exact `zig version`, clean-cache `zig build`, native probe commands, source URL/hash, and `git diff --check` output.

## Reviewer focus

Reproduce from a clean cache, confirm exact pins, and ensure no alternative HTTP or PostgreSQL client was introduced.
