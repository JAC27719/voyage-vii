# FEAS-001 — Prove api.zig and pg.zig Compatibility

**Implementer inference:** Low  
**Prerequisites:** `RESET-001` and `PLAN-001` approved.

## Frozen inputs

Use the exact Zig, api.zig, pg.zig upstream baseline, authorized patch path,
and PostgreSQL pins in `DEPENDENCY-PINS.md`, the lifecycle decision in
ADR-0011, adapter limits in `TIMEOUTS.md`, and Windows source policy in
`PACKAGING.md`. Do not select alternate revisions or suppliers.

## Objective

Prove the pinned api.zig and the exact pg.zig baseline plus bounded patch work
with Zig `0.15.2` and PostgreSQL `18.4` natively on Windows 11 x64 before
production scaffolding.

## Procedure

1. Create an isolated spike using only the approved revisions.
2. Build one api.zig endpoint and expose a deterministic response.
3. Connect through pg.zig to PostgreSQL `18.4` and execute `SELECT 1`.
4. Add only `patches/pg.zig/windows-connect-timeout.patch`. Verify the exact
   upstream base before applying it, apply it deterministically, and record its
   SHA-256. Its sole behavior change is a cancellable five-second Windows TCP
   connect deadline that closes the timed-out socket and leaves no background
   work.
5. Exercise clean connection, unavailable server, authentication failure, a
   controlled nonresponsive destination that reaches the five-second connect
   deadline, and graceful cleanup.
6. Prove native Windows 11 x64 application cleanup and process exit after the
   supervisor shutdown route, with PostgreSQL/log/owned resources protected and
   no surviving descendants. The api.zig accept loop need not return.
7. Optional non-Windows cross-compilation is informational only and must be
   labeled non-native and unsupported.
8. Document exact commands, dependency provenance, patch application/hash, and
   any source incompatibility.
9. Do not fork or substitute a dependency, and do not apply any additional or
   unapproved patch beyond the one exact authorized pg.zig patch.

## Acceptance evidence

- Clean-cache dependency and build logs.
- Native Windows endpoint and PostgreSQL probe results.
- Controlled nonresponsive-destination evidence: five-second timeout, closed
  socket, joined/absent background work, and repeatability.
- Deterministic exact-base patch application and lowercase SHA-256 for
  coordinator recording in `DEPENDENCY-PINS.md` after approval.
- Bounded Windows application cleanup/process exit and no-descendant evidence.
- Optional cross-target build matrix clearly labeled non-native/non-support.
- Binary architecture inspection.
- Failure-path output with secrets redacted.
- Exact `zig version`, clean-cache `zig build`, native probe commands, source URL/hash, and `git diff --check` output.

## Reviewer focus

Reproduce from a clean cache on Windows 11 x64, inspect the patch for exact
scope, verify its hash and timeout cleanup, and ensure no alternative HTTP or
PostgreSQL client was introduced. Approval does not require api.zig's library
accept loop to return.
