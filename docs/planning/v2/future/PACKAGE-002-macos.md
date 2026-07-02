# Deferred PACKAGE-002 Intent — macOS Intel and Apple Silicon Bundles

This is preserved design intent, not a current delivery task. It has been
removed from `docs/delivery/tasks.json`; none of its prerequisites, procedure,
or evidence gates the Windows 11 x64 slice. A future ADR/task wave must
revalidate every value before activation.

**Implementer inference:** Low
**Former prerequisites:** `PACKAGE-004` approved.

## Inputs preserved at deferral

The former guide used the then-current exact pins, manifest/version contracts,
deadlines, macOS names/layout/provenance, and ad-hoc sealing policy. A future
ADR must freeze their replacements; this document is not a current normative
source.

The former artifact names are preserved only as non-normative historical
examples:

- `voyage-vii_0.1.0_macos-x86_64.app.zip`
- `voyage-vii_0.1.0_macos-aarch64.app.zip`

## Objective

Future objective: produce separate native Intel and Apple Silicon `.app` ZIPs.

## Procedure

1. Build `x86_64-apple-darwin` and `aarch64-apple-darwin` separately; do not create a universal app.
2. Place runtime assets under `Contents/Resources/resources/runtime`, fill the final API source commit/output hash, and emit final manifest v1.
3. Preserve execute permissions.
4. Inspect every Mach-O for the package's single expected architecture.
5. Ad-hoc seal nested Mach-O files leaf-first with identity `-`, then ad-hoc seal the app.
6. Run `codesign --verify --deep --strict` before zipping and after extraction.
7. Zip each app with metadata-preserving tooling and create SHA-256 files.
8. Read root `VERSION`, use the names frozen by the future ADR, and label
   artifacts according to that ADR's sealing and distribution policy.

## Acceptance evidence

- Bundle identity and architecture inventories.
- Permission and code-sign verification before and after extraction.
- Readiness, retained-run, shutdown, and no-orphan results on both architectures.
- Execute the approved PACKAGE-004 harness against each exact app ZIP and record artifact/runtime hashes and elapsed times.
- Prove no Developer ID identity, signing secret, or notarization step exists; include `git diff --check`.

## Reviewer focus

Reject mixed architectures, missing resources/permissions, incorrect signing order, shell-profile dependencies, or misleading distribution claims.
