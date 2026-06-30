# PLAN-001 — Windows Scope and Native Lifecycle Recovery Amendment

**Implementer inference:** Low
**Prerequisites:** `DOC-001` approved.

## Frozen inputs

Use only the coordinator-authorized decisions recorded in ADR-0011. Preserve
existing feasibility reports and spike/application code as historical evidence.
Do not modify Git state.

## Objective

Make Windows 11 x64 the truthful sole current gate, preserve portable
architecture seams, authorize the exact bounded lifecycle recovery, defer
native macOS/Linux packages, and make the delivery graph internally consistent.

## Procedure

1. Add ADR-0011 with explicit partial supersession of ADRs 0003, 0006, 0007,
   0008, 0009, and 0010.
2. Amend planning contracts, lifecycle limits, package scope, and handoff
   documents without changing historical feasibility reports.
3. Remove `PACKAGE-002` and `PACKAGE-003` from the current registry/task-guide
   set and preserve their intent under `docs/planning/v2/future/`.
4. Make `FEAS-001` and `FEAS-002` depend on `RESET-001` and `PLAN-001`.
5. Update every affected current task guide to use Windows-only native
   acceptance while retaining explicit portable interfaces.
6. Make `AUDIT-001` depend on every remaining registered task other than itself.
7. Record a complete worker submission using the `WORKFLOW.md` placeholder
   revision convention.

## Acceptance evidence

- `tasks.json` validates against the unchanged registry schema.
- There are 29 unique registered tasks, all dependencies resolve, the graph is
  acyclic and wave-ordered, and `AUDIT-001` depends on the other 28 tasks.
- Every registered guide exists, every current guide is registered, and
  `PACKAGE-002`/`PACKAGE-003` have no current registry or dependency edge.
- Current-gate requirements consistently name Windows 11 x64; non-Windows
  evidence is explicitly deferred/informational.
- ADR-0011 contains every required section and explicit supersession.
- Local Markdown links resolve and `git diff --check` passes for owned changes.

## Reviewer focus

Reject any weakened token, data-preservation, database-shutdown, redaction, or
process-containment rule; any broadened dependency patch; any unsupported
native-platform claim; any current PACKAGE-002/003 edge; or any edit outside
the owned documentation paths.
