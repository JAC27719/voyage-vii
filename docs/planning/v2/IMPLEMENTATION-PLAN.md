# Voyage VII v2 Implementation Plan

## Execution model

Implementation is split into reviewed task packets. Implementers run with low inference and do not make design decisions. Each packet has a different reviewer. A dependent task starts only after prerequisite revisions are approved.

The coordinator alone creates branches, stages, commits, pushes, opens the pull request, changes task scope, and resolves architectural ambiguity.

## Waves

### Wave 0 — Governance and reset

1. `GUIDES-001`: validate and activate delegation controls, including the frozen dependency, contract, timeout, and packaging sources.
2. `RESET-001`: remove active v1 code while preserving history and user work.
3. `DOC-001`: add ADRs, governance, retrospective, privacy, and agent guidance.
4. `PLAN-001`: amend the current platform scope and approve the bounded native
   lifecycle recovery in ADR-0011.

### Wave 1 — Feasibility

1. `FEAS-001`: historical PostgreSQL/api.zig proof, superseded for future work by ADR-0012.
2. `FEAS-002`: prove the static TigerBeetle C ABI.
3. `FEAS-003`: historical PostgreSQL/TigerBeetle coexistence proof, superseded in part by ADR-0012.

`FEAS-001` and `FEAS-002` may run in parallel after `RESET-001` and `PLAN-001`
are approved. Their native acceptance gate is Windows 11 x64 only. Optional
cross-target compilation is non-gating structural evidence and must be labeled
non-native and unsupported. A Windows-gate failure stops implementation for an
ADR.

### Wave 2 — API and managed runtime

1. `API-001`: CLI, configuration, handshake, schemas, shell, and buildable static seams for later API modules.
2. `API-002`: historical PostgreSQL adapter, superseded for future work by ADR-0012.
3. `API-003`: TigerBeetle adapter.
4. `PLAN-002`: amend the database posture to SQLite after API-003.
5. `FEAS-004`: freeze and prove official SQLite native integration.
6. `API-005`: SQLite adapter, migrations, and synchronized implemented-schema DBML.
7. `DBDOC-001`: independently verify implemented-schema DBML and create TigerBeetle mapping/proposed-schema documentation without separating DBML from its migration review unit.
8. `API-004`: REST routes, authorization, probes, retries, and shutdown.
9. `RUNTIME-001`: paths, manifests, locking, child processes, ports, and logs.
10. `RUNTIME-002`: managed SQLite lifecycle.
11. `RUNTIME-003`: managed TigerBeetle lifecycle.
12. `RUNTIME-004`: integrated managed supervisor.
13. `COMPOSE-001`: external-mode local environment.

Adapters and runtime substrate may proceed in parallel after `API-001` where path ownership permits.

### Wave 3 — Desktop

1. `DESKTOP-001`: Tauri foundation, complete pinned manifests/configuration, security boundary, and buildable static seams for later desktop modules.
2. `DESKTOP-002`: Rust API-process supervisor.
3. `DESKTOP-003`: SolidJS system-status UI.
4. `DESKTOP-004`: verified runtime acquisition and staging.

After `DESKTOP-001`, supervisor, UI, and staging work may proceed concurrently in disjoint paths. Later packets replace only their predeclared modules and stop if a shared manifest, lockfile, configuration, or main entrypoint would need modification.

### Wave 4 — Tooling and hardening

1. `TOOL-001`: project-local bootstrap and environment doctor.
2. `TEST-001`: reusable cross-stack verification.
3. `HARDEN-001`: failure matrix and security/redaction hardening.

### Wave 5 — Portable artifacts and pre-CI stabilization

1. `PACKAGE-004`: implement the predeclared Windows distributable smoke harness
   behind an adapter seam that can host future platform launchers.
2. `PACKAGE-001`: Windows x64 ZIP and native smoke execution.
3. `PACKAGE-005`: packaged desktop launch repair for the normal user-facing
   runtime path.
4. `CLEANUP-001`: repository hygiene, ignore-policy, and tracked-artifact audit
   before CI automation.

After the smoke harness is approved, `PACKAGE-001` exercises the exact Windows
ZIP and records the final artifact/runtime hashes. `AUDIT-001` repeats that
Windows package test against the final integrated artifact. macOS Intel/Apple
Silicon and Linux packaging intent is preserved under
[`future/`](future/) for a future ADR/task wave.
CI does not start until the packaged desktop launches through the normal app
path and the repository cleanup gate is approved.

### Wave 6 — Delivery

1. `CI-001`: non-deployment Windows GitHub Actions and dependency automation
   after `CLEANUP-001`.
2. `DOC-002`: verified development and operations runbooks after CI, DBML documentation, and repository governance.
3. `AUDIT-001`: independent end-to-end audit.

## Integration checkpoints

After each wave, the coordinator:

1. Confirms every integrated task matches its approved revision hash.
2. Runs all currently available aggregate checks.
3. Verifies no unrelated paths changed.
4. Updates the task registry.
5. Creates logical commits only for approved work.

## Final acceptance

- api.zig, the official SQLite C API integration, and the TigerBeetle C ABI
  work natively on Windows 11 x64.
- Native managed workflows start the API with SQLite storage and TigerBeetle.
- Desktop managed mode initializes, retains, probes, retries, and shuts down both databases.
- App and supervisor tokens remain within their intended trust boundaries.
- No child process survives application shutdown.
- The Windows x64 ZIP passes native first-run and retained-run smoke tests.
- Runtime artifacts contain exact provenance, hashes, licenses, and no credentials/debug files.
- Every package uses the exact layout, naming, source, and sealing policy in `PACKAGING.md`.
- The implemented SQLite schema is accurately represented by importable DBML, and TigerBeetle identifier mappings are documented separately.
- Documentation setup commands have been independently executed.
- No active .NET, Terraform, AWS deployment, or obsolete CI remains.
- `AUDIT-001` has no unresolved P0–P2 findings.

## Portability guardrails

- The current build, runtime, package, smoke, CI, documentation, and completion
  gates are Windows 11 x64 only.
- Core contracts, business logic, and runtime orchestration do not expose
  Windows-native types.
- Platform process, filesystem, path, locking, and containment behavior remains
  behind explicit interfaces.
- Target-bearing manifests and smoke launch adapters remain extensible.
- A non-Windows stub or cross-build experiment is informational only and never
  supported/native evidence.
- Native macOS Intel, macOS Apple Silicon, and Linux work returns only through a
  future ADR/task wave.
