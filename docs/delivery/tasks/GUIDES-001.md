# GUIDES-001 — Validate and Activate Delegation Controls

**Implementer inference:** Low  
**Reviewer:** A different agent using high scrutiny  
**Prerequisites:** Coordinator has created `codex/voyage-vii-v2` from current `origin/main`.

## Objective

Confirm that the persisted plan is complete, internally consistent, and usable as the sole implementation handoff.

## Owned scope

`docs/planning/v2/**` and `docs/delivery/**`. Do not change application code or Git state.

## Procedure

1. Read every planning document and task guide, including `DEPENDENCY-PINS.md`, `CONTRACTS.md`, `TIMEOUTS.md`, and `PACKAGING.md`.
2. Validate `tasks.json` against `task-registry.schema.json`.
3. Confirm every dependency ID resolves and the graph has no cycle.
4. Confirm every task has owned paths, exclusions, a low-inference setting, acceptance checks, evidence, and reviewer checks.
5. Search for conflicts in versions, CLI flags, route names, response schemas, target names, timeouts, tokens, provenance, and packaging layout.
6. Report any conflict to the coordinator; do not choose between conflicting requirements.
7. Update only planning documents explicitly corrected by the coordinator.

## Acceptance evidence

- `Test-Json -Path docs/delivery/tasks.json -SchemaFile docs/delivery/task-registry.schema.json` returns `True`.
- A read-only graph traversal reports no duplicate task ID, unresolved dependency, or cycle and confirms guide prerequisites match `dependsOn`.
- A read-only file scan confirms every registry guide exists, its filename/title ID matches, and every required source-of-truth link resolves.
- A cross-contract checklist covers versions, CLI, routes, responses, targets, timeouts, tokens, manifests, provenance, and packaging.
- `git status --short --untracked-files=all` and `git diff --name-only` are recorded without modifying the index; all submitted paths are listed for coordinator staging.
- Registry metadata is `submitted` with the assigned worker/reviewer and `pending-coordinator-staged-hash`.

## Reviewer focus

Independently repeat validation, sample every wave, and confirm no implementation task requires an unstated design decision. Return findings to this worker until approved.
