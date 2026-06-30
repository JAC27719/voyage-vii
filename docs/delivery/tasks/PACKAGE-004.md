# PACKAGE-004 — Native Distributable Smoke Harness

**Implementer inference:** Low  
**Prerequisites:** `DESKTOP-002`, `DESKTOP-003`, `DESKTOP-004`, and `HARDEN-001` approved.

## Frozen inputs

Use the DESKTOP-001 predeclared smoke seam, product/manifest contracts in `CONTRACTS.md`, deadlines in `TIMEOUTS.md`, and paths/names/provenance in `PACKAGING.md`. Replace only owned smoke stub paths. Stop if a manifest, lockfile, shared configuration, main entrypoint, or static test registration must change.

## Objective

Implement and verify the reusable native smoke harness that each later platform package task uses against its actual distributable.

## Procedure

1. Implement desktop `--smoke-test --data-root <absolute-temporary-path>`.
2. Bypass window creation and all normal user-data locations.
3. Validate packaged runtime paths and hashes.
4. Start managed mode, enforce the 15-second handshake and 60-second readiness deadlines separately, and verify component versions/states.
5. Shut down, confirm the process group is empty, and repeat using the same data root.
6. Emit one credential-free `VOYAGE_VII_SMOKE` JSON line.
7. Support launch adapters for Windows extracted ZIP, macOS bundle executable, and Linux AppImage/extraction fallback using the exact layouts in `PACKAGING.md`.
8. Require canonical temp parent and sentinel before cleanup; preserve failures.

## Acceptance evidence

- Rust/frontend frozen checks from DESKTOP-001 plus smoke-harness unit/integration tests using controlled artifact fixtures.
- Tests for every target launch adapter, manifest/hash rejection, 15/60-second deadline separation, fresh/retained run, empty process group, redaction, and cleanup safety.
- Preserved sanitized failure example and `git diff --check`.
- No claim that final native artifacts passed; PACKAGE-001/002/003 supply those exact artifact hashes and native executions.

## Reviewer focus

Verify isolation from normal user data, timeout enforcement, package-authenticity checks, result redaction, cleanup guards, and that no shared desktop file changed.
