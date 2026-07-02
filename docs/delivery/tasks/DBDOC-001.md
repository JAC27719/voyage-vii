# DBDOC-001 — Database DBML Documentation

**Implementer inference:** Low  
**Prerequisites:** `API-005` and `API-003` approved.

## Frozen inputs

Use the database rules in `ARCHITECTURE.md`, the implemented DBML and synchronization README approved with `API-005`, `CONTRACTS.md`, and the deferred mappings in `FUTURE-FINANCE.md`. Do not change `docs/database/sqlite.dbml`; a mismatch returns to the API-005 migration review unit.

## Objective

Independently verify the version-controlled implemented SQLite DBML and create a separate factual map of TigerBeetle structures and clearly labeled proposed documentation.

## Owned scope

`docs/database/README.md`, `docs/database/tigerbeetle.md`, `docs/database/proposed/**`, and `docs/database/review/**`. Do not modify `docs/database/sqlite.dbml`, migrations, or production database code. If the approved migrations and implemented DBML disagree, stop and return the conflict to the `API-005` worker and reviewer for one migration/DBML revision.

## Procedure

1. Read every approved SQLite migration in execution order.
2. Independently reconstruct the resulting implemented schema and compare it with the already approved `docs/database/sqlite.dbml`.
3. Verify namespaces, actual database types, primary keys, foreign keys, nullability, defaults, unique constraints, indexes, and relationship direction.
4. Record the comparison under `docs/database/review/**`; return discrepancies rather than editing implemented DBML.
5. Do not add deferred finance tables to the implemented diagram.
6. If proposed finance diagrams are needed, place them under `docs/database/proposed/` and mark every file as unimplemented.
7. Create `docs/database/tigerbeetle.md` documenting accounts/transfers fields, identifier conversions, ledger/code assignments, and links to SQLite identifiers without presenting TigerBeetle as relational SQL tables.
8. Review and, if needed, correct only non-schema prose in `docs/database/README.md`, preserving its SQL-migration precedence and same-review-unit rule.
9. Import `sqlite.dbml` into dbdiagram.io or validate it with a coordinator-approved compatible parser. Record the validation method and result.
10. Check all files for credentials, connection strings, private paths, and real user data.

## Acceptance evidence

- Table-by-table comparison against the final applied migrations.
- Exact approved DBML parser command and successful output against the API-005 revision.
- Constraint, index, and relation checklist.
- Clear separation of implemented and proposed schemas.
- TigerBeetle mapping review against the approved adapter and deferred-domain decisions.
- Sensitive-content scan and `git diff --check`.

## Reviewer focus

Independently reconstruct the final SQLite schema from migrations and compare it with DBML. Verify relation direction, nullability, defaults, types, constraints, indexes, and triggers. Confirm proposed structures are unmistakably separated and TigerBeetle documentation does not invent relational guarantees.

## Ongoing rule

Every task that changes SQLite migrations must own and update `docs/database/sqlite.dbml` in the same revision. There is no baseline exception. The reviewer must reject schema changes whose DBML is missing or stale.
