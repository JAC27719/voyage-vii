# DESKTOP-004 — Verified Portable Runtime Staging

**Implementer inference:** Low  
**Prerequisites:** `DESKTOP-001` and `FEAS-003` approved.

## Frozen inputs

Use exact pins from `DEPENDENCY-PINS.md`, manifest v1 from `CONTRACTS.md`,
limits from `TIMEOUTS.md`, and the approved Windows URLs/hashes/toolchains and
layout required by `PACKAGING.md` and FEAS-003. Do not choose another supplier,
archive, version, target, or layout.

## Objective

Acquire and stage exact Windows x64 runtime binaries safely and reproducibly
without tracking generated binaries while keeping the source-manifest schema
target-extensible.

## Procedure

1. Check in a source manifest with schema version, component/version, target, FEAS-003-approved official URL/revision, source SHA-256, archive format, required files, executable paths, and license metadata.
2. Download to a temporary file, verify hash, and atomically promote into a hash-addressed local cache.
3. Reject absolute archive paths, `..`, escaping links, duplicate destinations, missing files, and wrong architecture.
4. Never execute downloaded content during staging.
5. Stage third-party runtimes into the exact target-relative locations in `PACKAGING.md`, retain required PostgreSQL libraries/share files, and define the first-party API component slot.
6. Exclude headers, debug symbols, server documentation, caches, and unrelated tools.
7. Generate manifest-v1 inputs for PostgreSQL/TigerBeetle and an unfilled first-party API slot; package tasks supply the audited API commit/output hash and generate the final manifest.
8. Generate combined notices and license copies.
9. Provide offline mode that succeeds only with verified cached inputs.
10. Ensure staging leaves the checked-in source manifest unchanged and all generated content ignored.
11. Reject any claim that non-Windows cross-build or staged stub output is a
    supported/native runtime.

## Acceptance evidence

- Idempotent warm-cache and offline runs.
- Corrupt, traversal, symlink, duplicate, missing-file, and wrong-target negative tests.
- Staged tree, size totals, hash validation, and license inventory.
- Clean Git status for generated assets.
- Exact source-manifest validation command, staging test command, final staged-tree/hash/license report locations, and `git diff --check`.
- Native staging evidence is Windows 11 x64 only.

## Reviewer focus

Audit provenance, extraction safety, target validation, PostgreSQL runtime completeness, license coverage, and ignored binary output.
