# PACKAGE-003 — Linux x64 AppImage

**Implementer inference:** Low  
**Prerequisites:** `PACKAGE-004` approved.

## Frozen inputs

Use exact pins from `DEPENDENCY-PINS.md`, manifest/version contracts from `CONTRACTS.md`, package deadlines from `TIMEOUTS.md`, and Linux naming/layout/provenance from `PACKAGING.md`. Do not choose another build base, supplier, name, or layout.

## Objective

Produce and validate the Linux x64 AppImage.

## Procedure

1. Build and test on the frozen Ubuntu 24.04 x64 baseline.
2. Build native `x86_64-unknown-linux-gnu` and stage the matching runtime.
3. Stage runtime under AppDir `usr/lib/voyage-vii/resources/runtime`, fill the final API source commit/output hash, emit final manifest v1, and include only necessary Tauri/WebKitGTK/AppImage dependencies.
4. Inspect ELF architecture, interpreter, dynamic dependencies, and required glibc versions.
5. Scope PostgreSQL library-path changes to its child process.
6. Read root `VERSION` and create `voyage-vii_0.1.0_linux-x86_64.AppImage` and SHA-256.
7. Support direct execution and `APPIMAGE_EXTRACT_AND_RUN=1` where FUSE is unavailable.

## Acceptance evidence

- AppImage inventory, executable bit, ELF and `ldd` results.
- Direct/extracted readiness, retained-run, shutdown, and no-orphan results.
- Proof that data uses the platform application-data directory.
- Execute the approved PACKAGE-004 harness against the exact AppImage in direct and extraction-fallback modes; record artifact/runtime hashes and elapsed times.
- Package-script command transcript and `git diff --check`.

## Reviewer focus

Check build baseline, glibc compatibility, missing libraries, scoped environment changes, resource completeness, and checksum.
