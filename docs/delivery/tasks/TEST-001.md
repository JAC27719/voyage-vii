# TEST-001 — Reusable Cross-Stack Test Orchestration

**Implementer inference:** Low  
**Prerequisites:** `RUNTIME-004`, `COMPOSE-001`, `DESKTOP-002`, and `DESKTOP-003` approved.

## Frozen inputs

Use exact response/manifests/origins from `CONTRACTS.md`, 120-second step and 20-minute aggregate limits from `TIMEOUTS.md`, and package layouts from `PACKAGING.md`.

## Objective

Expose consistent Windows 11 x64 commands for unit, Compose, managed, failure,
and package verification.

## Procedure

1. Provide `unit`, `compose-smoke`, `managed-smoke`, `managed-failure`, `package-smoke`, and `all`.
2. Reuse product entrypoints and shared fixtures; do not reimplement lifecycle behavior in the harness.
3. Allocate isolated canonical temporary roots with a sentinel.
4. Enforce 120 seconds per step and 20 minutes overall.
5. Capture sanitized logs and process inventories.
6. Preserve failed roots and print their paths.
7. Delete successful roots only after validating the sentinel and canonical parent.
8. Verify process groups are empty after every test.

## Acceptance evidence

- Successful command matrix.
- Intentional timeout, interruption, stale lock, occupied resource, unwritable root, corrupt asset, and malformed handshake runs.
- Cleanup escape-prevention tests.
- Orphan-process checks.
- Windows-native execution for all current gates; any non-Windows compile
  experiment is labeled informational/non-support.
- Exact invocations for all six commands, measured timeout output, preserved failure-root locations, and `git diff --check`.

## Reviewer focus

Interrupt the harness, inspect cleanup guards, confirm actual product paths are exercised, and verify diagnostics contain no credentials.
