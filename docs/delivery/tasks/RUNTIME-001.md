# RUNTIME-001 — Cross-Platform Runtime Substrate

**Implementer inference:** Low  
**Prerequisites:** `API-001` approved.

## Frozen inputs

Use writable and packaged manifest v1 from `CONTRACTS.md`, limits from `TIMEOUTS.md`, layouts/provenance from `PACKAGING.md`, and only API-001's predeclared runtime seams. Stop if shared build, dependency, entrypoint, or aggregate-test files must change.

## Objective

Provide safe platform primitives for manifests, paths, locking, ports, child processes, and rotating logs.

## Procedure

1. Implement and validate writable-root manifest v1 exactly as frozen in `CONTRACTS.md`.
2. Canonicalize every path and reject absolute/relative escape from approved roots.
3. Acquire one exclusive OS lock before component mutation.
4. Allocate loopback ports and handle bind races without using public interfaces.
5. Implement Windows Job Object containment with kill-on-close.
6. Implement Unix process-group containment and reaping.
7. Rotate structured logs under the approximately 50 MiB aggregate budget.
8. Validate target identity, packaged manifest v1, file hashes, executable flags, source metadata, and exact schema version.

## Acceptance evidence

- Path traversal, symlink, malformed manifest, wrong-target, hash mismatch, lock contention, port race, rotation, and forced-child cleanup tests.
- Native Windows and Unix containment evidence.
- `zig build test` through API-001's aggregate registration and `git diff --check`.

## Reviewer focus

Audit canonicalization before mutation, lock lifetime, process-handle ownership, and cleanup safety under abrupt termination.
