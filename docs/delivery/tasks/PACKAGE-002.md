# PACKAGE-002 — macOS Intel and Apple Silicon Bundles

**Implementer inference:** Low  
**Prerequisites:** `PACKAGE-004` approved.

## Frozen inputs

Use exact pins from `DEPENDENCY-PINS.md`, manifest/version contracts from `CONTRACTS.md`, package deadlines from `TIMEOUTS.md`, and macOS names/layout/provenance/ad-hoc policy from `PACKAGING.md`. Do not select another signing identity, supplier, name, or layout.

## Objective

Produce separate native Intel and Apple Silicon `.app` ZIPs.

## Procedure

1. Build `x86_64-apple-darwin` and `aarch64-apple-darwin` separately; do not create a universal app.
2. Place runtime assets under `Contents/Resources/resources/runtime`, fill the final API source commit/output hash, and emit final manifest v1.
3. Preserve execute permissions.
4. Inspect every Mach-O for the package's single expected architecture.
5. Ad-hoc seal nested Mach-O files leaf-first with identity `-`, then ad-hoc seal the app.
6. Run `codesign --verify --deep --strict` before zipping and after extraction.
7. Zip each app with metadata-preserving tooling and create SHA-256 files.
8. Read root `VERSION`, use the two exact `0.1.0` artifact names in `PACKAGING.md`, and label artifacts ad-hoc sealed, unnotarized, and intended for testing.

## Acceptance evidence

- Bundle identity and architecture inventories.
- Permission and code-sign verification before and after extraction.
- Readiness, retained-run, shutdown, and no-orphan results on both architectures.
- Execute the approved PACKAGE-004 harness against each exact app ZIP and record artifact/runtime hashes and elapsed times.
- Prove no Developer ID identity, signing secret, or notarization step exists; include `git diff --check`.

## Reviewer focus

Reject mixed architectures, missing resources/permissions, incorrect signing order, shell-profile dependencies, or misleading distribution claims.
