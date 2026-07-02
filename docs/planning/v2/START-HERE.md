# Voyage VII v2 — Start Here

This directory is the durable handoff for rebuilding Hydro as Voyage VII.

No product implementation has started. The current slice supports only Windows
11 x64 (`x86_64-pc-windows-msvc`). Native macOS Intel, macOS Apple Silicon, and
Linux work is deferred to a future ADR/task wave and does not block this slice.
Non-Windows cross-builds are informational structural evidence only.

The next implementation chat must:

1. Read this file, `ARCHITECTURE.md`, `DECISIONS.md`, `DEPENDENCY-PINS.md`, `CONTRACTS.md`, `TIMEOUTS.md`, `PACKAGING.md`, `IMPLEMENTATION-PLAN.md`, and `docs/delivery/WORKFLOW.md`.
2. Confirm the current worktree is clean and preserve all user changes.
3. From a Codex-managed worktree, update `origin/main` and create `codex/voyage-vii-v2`.
4. Validate `docs/delivery/tasks.json`.
5. Confirm `PLAN-001` is approved and integrated before resuming `FEAS-001` or
   `FEAS-002`. Then follow the current registry dependencies.
6. Assign implementers with **low inference**. They execute only their guide and escalate ambiguity.
7. Assign a different reviewer with **high scrutiny** to every implementation task.
8. Integrate a task only after the same reviewer has approved the submitted revision.

## Source of truth

- `ARCHITECTURE.md`: frozen component boundaries and public contracts.
- `DECISIONS.md`: accepted decisions, constraints, and exclusions.
- `DEPENDENCY-PINS.md`: exact toolchain, native, NPM, and Rust direct dependency pins.
- `CONTRACTS.md`: exact version, CLI, origin, token, HTTP, and manifest contracts.
- `TIMEOUTS.md`: exact runtime, test, CI, and retention limits.
- `PACKAGING.md`: exact artifact layouts, names, sealing policy, and native provenance.
- `IMPLEMENTATION-PLAN.md`: waves, dependencies, and completion criteria.
- `FUTURE-FINANCE.md`: deferred financial-domain design input.
- `RETROSPECTIVE.md`: lessons from the first attempt.
- `docs/delivery/WORKFLOW.md`: worker, reviewer, and coordinator protocol.
- `docs/delivery/tasks.json`: machine-readable task registry.
- `docs/delivery/tasks/*.md`: self-contained implementation packets.
- `future/`: explicitly deferred native macOS/Linux package intent; these files
  are not current task guides and confer no support claim.

The user no longer requires preservation of obsolete local Terraform cache/state
or IDE state. Their cleanup may be performed separately by the coordinator after
the exact local paths are identified; `PLAN-001` changes documentation only and
does not itself delete those paths.

If documents conflict, stop and ask the coordinator to amend the documents. Implementers must not resolve architectural conflicts themselves.
