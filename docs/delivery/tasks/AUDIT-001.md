# AUDIT-001 — Independent Final Integration Audit

**Implementer inference:** Low for procedure; no production edits allowed  
**Prerequisites:** Every other task listed in `tasks.json` approved and integrated.

## Frozen inputs

Audit against the complete planning baseline, especially `DEPENDENCY-PINS.md`, `CONTRACTS.md`, `TIMEOUTS.md`, `PACKAGING.md`, and the canonical revision rules in `WORKFLOW.md`.

## Objective

Independently trace the complete integrated system against the frozen plan and route defects back through their original review loops.

## Procedure

1. Assign an auditor that implemented none of the production packets.
2. Record the audited commit and verify the task registry.
3. Map every frozen requirement to code, tests, documentation, or artifact evidence.
4. Inspect the complete diff for v1 remnants, scope creep, tracked binaries, credentials, and unreviewed paths.
5. Re-run Compose, fresh/retained managed mode, security checks, and the final
   Windows ZIP smoke test with the approved PACKAGE-004 harness and exact
   integrated artifact/runtime hashes.
6. Send each finding to the task's original worker and reviewer.
7. Do not patch production code in the audit task.
8. Re-run the audit against the corrected final revision.

## Acceptance evidence

- Requirement traceability matrix.
- Integrated revision and task-approval inventory.
- Complete native Windows verification links and an audit that no cross-build
  is represented as native/support evidence.
- Finding ownership and closure table.
- Final statement of residual risks.
- Independent canonical revision-hash recomputation, registry/schema/graph commands, final package commands, and `git diff --check`.

## Reviewer focus

The coordinator reviews the audit procedure and evidence. Completion requires no unresolved P0–P2 finding and explicit disposition of every P3.
