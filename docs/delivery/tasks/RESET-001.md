# RESET-001 — Remove the Active V1 Implementation

**Implementer inference:** Low  
**Prerequisites:** `GUIDES-001` approved.

## Objective

Remove active v1 .NET, Terraform, AWS, deployment, seeder, and obsolete automation files while retaining Git history and unrelated user work.

## Procedure

1. Inventory tracked v1 paths and submit the inventory to the coordinator before deletion.
2. Classify every path as remove, retain unchanged, or escalate.
3. Remove only coordinator-approved v1 paths.
4. Preserve `.git`, `.agents`, `.codex`, planning documents, and untracked or unrelated user files.
5. Leave a minimal directory skeleton only where required by approved follow-on guides.
6. Search remaining tracked content for `.csproj`, `.sln`, Terraform, AWS deployment, old product names, and obsolete workflows.

## Acceptance evidence

- Before/after tracked-file inventory.
- Approved deletion list.
- Search results for prohibited v1 entrypoints.
- Git status demonstrating no unrelated deletion.
- `git diff --name-status <candidate-base> -- <approved paths>`, prohibited-entrypoint `rg` output, and `git diff --check`.

## Reviewer focus

Compare the submitted deletion list with the original tree, inspect retained legacy references, and verify nothing was discarded merely because it was unfamiliar. Return omissions or unsafe deletions to the worker.
