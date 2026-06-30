# Voyage VII v2 Implementation Plan

## Execution model

Implementation is split into reviewed task packets. Implementers run with low inference and do not make design decisions. Each packet has a different reviewer. A dependent task starts only after prerequisite revisions are approved.

The coordinator alone creates branches, stages, commits, pushes, opens the pull request, changes task scope, and resolves architectural ambiguity.

## Waves

### Wave 0 — Governance and reset

1. `GUIDES-001`: validate and activate delegation controls, including the frozen dependency, contract, timeout, and packaging sources.
2. `RESET-001`: remove active v1 code while preserving history and user work.
3. `DOC-001`: add ADRs, governance, retrospective, privacy, and agent guidance.

### Wave 1 — Feasibility

1. `FEAS-001`: prove api.zig and pg.zig with PostgreSQL 18.4.
2. `FEAS-002`: prove the static TigerBeetle C ABI.
3. `FEAS-003`: prove all three dependencies coexist in one executable, prove the prescribed native runtime acquisition/build strategy, and declare go/no-go.

`FEAS-001` and `FEAS-002` may run in parallel after reset. Any required-target failure stops implementation for an ADR.

### Wave 2 — API and managed runtime

1. `API-001`: CLI, configuration, handshake, schemas, shell, and buildable static seams for later API modules.
2. `API-002`: PostgreSQL adapter, migrations, and synchronized implemented-schema DBML.
3. `API-003`: TigerBeetle adapter.
4. `DBDOC-001`: independently verify implemented-schema DBML and create TigerBeetle mapping/proposed-schema documentation without separating DBML from its migration review unit.
5. `API-004`: REST routes, authorization, probes, retries, and shutdown.
6. `RUNTIME-001`: paths, manifests, locking, child processes, ports, and logs.
7. `RUNTIME-002`: managed PostgreSQL lifecycle.
8. `RUNTIME-003`: managed TigerBeetle lifecycle.
9. `RUNTIME-004`: integrated managed supervisor.
10. `COMPOSE-001`: external-mode local environment.

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

### Wave 5 — Portable artifacts

1. `PACKAGE-004`: implement the predeclared native distributable smoke harness.
2. `PACKAGE-001`: Windows x64 ZIP and native smoke execution.
3. `PACKAGE-002`: separate macOS Intel and Apple Silicon app ZIPs and native smoke execution.
4. `PACKAGE-003`: Linux x64 AppImage and native smoke execution.

After the smoke harness is approved, the three platform packages may run in parallel on native workers. Each package task must exercise its exact artifact with the harness and record the final artifact/runtime hashes. `AUDIT-001` repeats all four package tests against the final integrated artifacts.

### Wave 6 — Delivery

1. `CI-001`: non-deployment GitHub Actions and dependency automation after all native package tasks.
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

- api.zig, pg.zig, and the TigerBeetle C ABI work on every target.
- Compose starts the external API and both databases.
- Desktop managed mode initializes, retains, probes, retries, and shuts down both databases.
- App and supervisor tokens remain within their intended trust boundaries.
- No child process survives application shutdown.
- All four native distributables pass first-run and retained-run smoke tests.
- Runtime artifacts contain exact provenance, hashes, licenses, and no credentials/debug files.
- Every package uses the exact layout, naming, source, and sealing policy in `PACKAGING.md`.
- The implemented PostgreSQL schema is accurately represented by importable DBML, and TigerBeetle identifier mappings are documented separately.
- Documentation setup commands have been independently executed.
- No active .NET, Terraform, AWS deployment, or obsolete CI remains.
- `AUDIT-001` has no unresolved P0–P2 findings.
