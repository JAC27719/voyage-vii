# TOOL-001 — Project-Local Bootstrap and Doctor

**Implementer inference:** Low  
**Prerequisites:** `DESKTOP-004` and `COMPOSE-001` approved.

## Frozen inputs

Use exact toolchains/dependencies from `DEPENDENCY-PINS.md`, target and manifest contracts from `CONTRACTS.md`, operation limits from `TIMEOUTS.md`, and provenance/layout rules from `PACKAGING.md`. Do not add a supplier or download mechanism.

## Objective

Provide repeatable dependency preparation and diagnostic commands without privileged or global mutation.

## Procedure

1. Implement profiles `compose`, `desktop`, `packaging`, and `all`.
2. Detect the OS/architecture and compare it with the supported target matrix.
3. Verify required system prerequisites and print platform-specific installation instructions.
4. Download only project-local, pinned, checksum-verified dependencies.
5. Reuse the runtime staging cache rather than creating a second download mechanism.
6. Provide a doctor report for tool versions, Docker readiness, native build prerequisites, WebView requirements, and writable cache/data paths.
7. Support warm-cache and documented offline behavior.
8. Never invoke privileged installers or alter user-global configuration.

## Acceptance evidence

- Clean and warm-cache runs for every profile.
- Missing/wrong-version prerequisite scenarios.
- Offline success and failure behavior.
- Proof of no writes outside documented project-local caches.
- Exact per-profile commands and outputs on each supported platform, filesystem mutation inventory, and `git diff --check`.

## Reviewer focus

Run on supported platforms, inspect mutation boundaries, and reject hidden global installs, floating downloads, or duplicated provenance logic.
