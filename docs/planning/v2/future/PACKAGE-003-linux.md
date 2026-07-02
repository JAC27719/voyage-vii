# Deferred PACKAGE-003 Intent — Linux x64 AppImage

This is preserved design intent, not a current delivery task. It has been
removed from `docs/delivery/tasks.json`; none of its prerequisites, procedure,
or evidence gates the Windows 11 x64 slice. A future ADR/task wave must
revalidate every value before activation.

**Implementer inference:** Low
**Former prerequisites:** `PACKAGE-004` approved.

## Inputs preserved at deferral

The former guide used the then-current exact pins, manifest/version contracts,
deadlines, Linux names/layout/provenance, and Ubuntu baseline. A future ADR must
freeze their replacements; this document is not a current normative source.

The former artifact name
`voyage-vii_0.1.0_linux-x86_64.AppImage` is preserved only as a non-normative
historical example.

## Objective

Future objective: produce and validate the Linux x64 AppImage.

## Procedure

1. Build and test on the frozen Ubuntu 24.04 x64 baseline.
2. Build native `x86_64-unknown-linux-gnu` and stage the matching runtime.
3. Stage runtime under AppDir `usr/lib/voyage-vii/resources/runtime`, fill the final API source commit/output hash, emit final manifest v1, and include only necessary Tauri/WebKitGTK/AppImage dependencies.
4. Inspect ELF architecture, interpreter, dynamic dependencies, and required glibc versions.
5. Scope any native library-path changes to their child process.
6. Read root `VERSION`, create the artifact name frozen by the future ADR, and
   record its SHA-256.
7. Support direct execution and `APPIMAGE_EXTRACT_AND_RUN=1` where FUSE is unavailable.

## Acceptance evidence

- AppImage inventory, executable bit, ELF and `ldd` results.
- Direct/extracted readiness, retained-run, shutdown, and no-orphan results.
- Proof that data uses the platform application-data directory.
- Execute the approved PACKAGE-004 harness against the exact AppImage in direct and extraction-fallback modes; record artifact/runtime hashes and elapsed times.
- Package-script command transcript and `git diff --check`.

## Reviewer focus

Check build baseline, glibc compatibility, missing libraries, scoped environment changes, resource completeness, and checksum.
