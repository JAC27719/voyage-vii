# PLAN-002 — SQLite Database Posture Amendment

**Implementer inference:** Low
**Prerequisites:** `API-003` integrated.

## Frozen inputs

Use ADR-0012 as the coordinator-authorized decision. Preserve existing
PostgreSQL feasibility, adapter, and integration records as historical evidence
unless a task guide explicitly supersedes them. Do not modify production
runtime behavior except where task packets must be retargeted away from
PostgreSQL.

## Objective

Replace PostgreSQL with SQLite as the general-purpose database for future v2
work, retain TigerBeetle as the ledger database, and make the delivery graph
internally consistent before additional runtime or HTTP work proceeds.

## Procedure

1. Add ADR-0012 with explicit partial supersession of the PostgreSQL-specific
   portions of earlier ADRs.
2. Amend planning contracts, dependency pins, timeouts, package layout, future
   finance notes, and handoff documents from PostgreSQL to SQLite.
3. Add `FEAS-004` to freeze and prove the official SQLite source integration.
4. Add `API-005` for the production SQLite adapter, migrations, and implemented
   DBML.
5. Retarget `DBDOC-001`, `API-004`, `RUNTIME-002`, `RUNTIME-004`,
   `COMPOSE-001`, packaging, documentation, testing, and audit dependencies to
   the SQLite path where needed.
6. Preserve already integrated PostgreSQL work as superseded historical
   evidence, not as an active prerequisite for new implementation.
7. Record a complete worker submission using the `WORKFLOW.md` placeholder
   revision convention.

## Acceptance evidence

- `tasks.json` validates against the unchanged registry schema.
- All task IDs are unique, dependencies resolve, the graph is acyclic and
  wave-ordered, and `AUDIT-001` depends on every current task except itself.
- PostgreSQL-specific active task packets are replaced or clearly marked
  historical/superseded.
- Public contracts consistently use `sqlite` component IDs, retry paths, and
  error codes.
- ADR-0012 contains every required section and explicit supersession.
- Local Markdown links resolve and `git diff --check` passes for owned changes.

## Reviewer focus

Reject any hidden PostgreSQL prerequisite in future work, any accidental removal
of TigerBeetle, any UI/desktop direct database access, any unpinned SQLite
source claim before `FEAS-004`, or any weakened data-preservation, redaction,
token, shutdown, or review-unit rule.
