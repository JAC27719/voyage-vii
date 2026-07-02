# CLEANUP-001 — Repository Hygiene Before CI

**Implementer inference:** Low
**Prerequisites:** `PACKAGE-005` approved.

## Frozen inputs

Use the repository delivery workflow, current `.gitignore` rules, package
artifact policy, and generated-output exclusions already approved by the
desktop, runtime-staging, bootstrap, test, hardening, and package tasks.

## Objective

Clean the repository before CI work starts, ensuring only source, scripts,
configuration, tests, and reviewed documentation are tracked.

## Procedure

1. Inventory tracked and untracked generated outputs, caches, package
   artifacts, local dependency folders, and report directories.
2. Update ignore rules only for generated or local-only paths that should never
   be committed.
3. Remove accidental tracked generated artifacts only when they are proven
   unnecessary and in scope for this task.
4. Preserve unrelated user files and local caches.
5. Produce a short hygiene report that lists retained ignored outputs and any
   tracked cleanup.

## Acceptance evidence

- `git status --short --untracked-files=all` before and after cleanup.
- Tracked generated-artifact audit.
- Ignore-rule validation for desktop, runtime staging, package, bootstrap, and
  test outputs.
- Registry validation and `git diff --check`.

## Reviewer focus

Confirm no user work is deleted, no required source/runtime fixture is ignored
or untracked accidentally, generated outputs are excluded consistently, and
CI remains blocked until this hygiene gate is approved.
