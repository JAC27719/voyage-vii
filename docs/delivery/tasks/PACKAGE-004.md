# PACKAGE-004 — Windows Distributable Smoke Harness

**Implementer inference:** Low  
**Prerequisites:** `DESKTOP-002`, `DESKTOP-003`, `DESKTOP-004`, and `HARDEN-001` approved.

## Frozen inputs

Use the DESKTOP-001 predeclared smoke seam, product/manifest contracts in `CONTRACTS.md`, deadlines in `TIMEOUTS.md`, and paths/names/provenance in `PACKAGING.md`. Replace only owned smoke stub paths and the coordinator-authorized desktop entrypoint dispatch needed for `--smoke-test`. Stop if a manifest, lockfile, shared configuration, runtime-supervisor module, or non-smoke static test registration must change.

## Objective

Implement and verify the Windows native smoke harness used by `PACKAGE-001`
against its actual ZIP, with an explicit launcher interface for future
platform adapters.

## Procedure

1. Implement desktop `--smoke-test --data-root <absolute-temporary-path>`.
2. Bypass window creation and all normal user-data locations.
3. Validate packaged runtime paths and hashes.
4. Start managed mode, enforce the 15-second handshake and 60-second readiness deadlines separately, and verify component versions/states.
5. Shut down, confirm the process group is empty, and repeat using the same data root.
6. Emit one credential-free `VOYAGE_VII_SMOKE` JSON line.
7. Implement the Windows extracted-ZIP launch adapter using the exact layout in
   `PACKAGING.md`. Keep an adapter/interface seam for future launchers, but do
   not implement or claim macOS/Linux support.
8. Require canonical temp parent and sentinel before cleanup; preserve failures.

## Acceptance evidence

- Rust/frontend frozen checks from DESKTOP-001 plus smoke-harness unit/integration tests using controlled artifact fixtures.
- Tests for the Windows launch adapter and generic adapter seam, manifest/hash
  rejection, 15/60-second deadline separation, fresh/retained run, empty Job
  Object/process tree, redaction, and cleanup safety.
- Preserved sanitized failure example and `git diff --check`.
- No claim that the final native artifact passed; `PACKAGE-001` supplies the
  exact ZIP hash and native execution.

## Reviewer focus

Verify isolation from normal user data, timeout enforcement, package-authenticity checks, result redaction, cleanup guards, and that no shared desktop file changed.
