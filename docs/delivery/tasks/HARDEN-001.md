# HARDEN-001 — Runtime and Security Hardening

**Implementer inference:** Low  
**Prerequisites:** `TEST-001` and `TOOL-001` approved.

## Frozen inputs

Verify exact dependencies in `DEPENDENCY-PINS.md`, interfaces/manifests in `CONTRACTS.md`, every limit in `TIMEOUTS.md`, and artifact provenance/layout in `PACKAGING.md`. Deviations are defects returned to the original owner, not new design choices.

## Objective

Exercise the integrated system against the agreed failure and security matrix without redesigning production behavior.

## Procedure

1. Test token scope, constant-time comparison integration, exact CORS, request limits, and error sanitization.
2. Test corrupt/missing runtime files, wrong architecture, unwritable roots, stale locks, occupied ports, and interrupted prior runs.
3. Test process crashes during initialization, probe, retry, and shutdown.
4. Verify fresh and retained startup on every native target.
5. Scan logs, diagnostics, panic output, artifacts, and manifests for tokens, database secrets, headers, SQL values, private absolute paths, and debug files.
6. Measure startup timing, idle memory, and log rotation against targets.
7. Route production defects to the owning original task rather than fixing outside owned paths.

## Acceptance evidence

- Complete fault matrix with reproducible commands.
- Redaction and artifact scan results.
- Native startup/process cleanup results.
- Performance measurements and documented deviations.
- Exact fault-matrix commands/output locations, pin/contract/timeout/layout searches, and `git diff --check`.

## Reviewer focus

Reproduce representative failures from every subsystem and ensure all discovered production defects were returned to their owning workers and re-reviewed.
