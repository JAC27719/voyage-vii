# Deferred Financial-Domain Decisions

These decisions guide future design but are outside the first v2 implementation slice.

Any future relational finance design starts under `docs/database/proposed/` as DBML. It moves into `docs/database/postgresql.dbml` only in the same reviewed task that adds the executable SQL migration. TigerBeetle account and transfer structures remain documented as external mappings rather than PostgreSQL tables.

## Ledger model

- One OS-trusted local user, one single-person USD ledger.
- Strict double-entry accounting on a cash basis.
- PostgreSQL owns user, ledger, account metadata, periods, budgets, and lifecycle state.
- TigerBeetle alone stores balances and transfers; MVP does not duplicate transaction rows in SQL.
- Account classes use RED ALE: Revenue, Expense, Dividend, Asset, Liability, Equity.
- TigerBeetle ledger codes: Asset `1`, Liability `2`, Equity `3`, Revenue `4`, Expense `5`, Dividend `6`.
- Create one friendly default account for every class; custom accounts may use any class.
- Account classification is immutable.
- Archive requires a zero balance and closes the TigerBeetle account; reopening is supported.
- Default accounts may be renamed but not archived.

## Identifiers and transfer metadata

- Use PostgreSQL-native UUIDv7.
- Convert canonical UUID big-endian bytes to TigerBeetle `u128`.
- Derive the TigerBeetle ledger `u32` from domain-separated BLAKE3.
- Store effective epoch-day in `user_data_64`; reserve remaining user-data fields.
- Derive reversal identifiers through a documented XOR namespace.
- Use SQL-first deterministic lifecycle operations.

## MVP transaction behavior

- Manual two-account entries only.
- Defer splits, import, recurring entries, reconciliation, and attachments.
- Build history from account-history scans, merge and deduplicate per request, order by effective date, and use an opaque cursor.
- Require a 100,000-entry performance test before retaining that history design.

## Periods, budgets, and reports

- Support weekly, 14-day, and calendar-month periods with an anchor for interval schedules.
- Schedule changes apply from a future anchor.
- Maintain current and next periods.
- Period states: draft, active, closing, closed.
- Close Revenue, Expense, and Dividend into Equity using a deterministic SQL close intent.
- Corrections post in the current period.
- Budgets may target all six account classes.
- Budget values are fixed cents or basis points of planned revenue and represent planned net movement.
- Do not enforce a balancing constraint on budgets.
- Initial reports: balance sheet, period activity, and budget variance.
- Defer export.
