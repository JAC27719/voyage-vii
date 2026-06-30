# PACKAGE-001 — Windows x64 Portable ZIP

**Implementer inference:** Low  
**Prerequisites:** `PACKAGE-004` approved.

## Frozen inputs

Use exact pins from `DEPENDENCY-PINS.md`, manifest/version contracts from `CONTRACTS.md`, package deadlines from `TIMEOUTS.md`, and Windows naming/layout/provenance from `PACKAGING.md`. Do not choose alternate sources, names, versions, or layouts.

## Objective

Produce and validate the Windows 11 x64 portable artifact.

## Procedure

1. Build native `x86_64-pc-windows-msvc` release artifacts.
2. Stage the matching verified runtime.
3. Assemble the desktop executable and sibling `resources/runtime`, fill the final API source commit/output hash, and emit final manifest v1.
4. Suppress visible consoles for child processes.
5. Exclude PDBs, caches, source maps, build metadata, and credentials.
6. Read root `VERSION` and create `voyage-vii_0.1.0_windows-x86_64.zip` and SHA-256.
7. Extract and test from a path containing spaces and non-ASCII characters.
8. Document Windows 11 and WebView2 requirements; do not create an installer.

## Acceptance evidence

- PE architecture inventory.
- Runtime-manifest validation after extraction.
- No-console-flash, readiness, retained-run, graceful-shutdown, and no-orphan results.
- File-write check proving user data is not stored beside the app.
- Execute the approved PACKAGE-004 harness against the exact ZIP for fresh and retained runs; record artifact/runtime hashes, elapsed times, and empty process tree.
- Package-script command transcript and `git diff --check`.

## Reviewer focus

Inspect ZIP contents, resource fallback, architecture, checksum, console behavior, data location, and absence of unsupported/debug files.
