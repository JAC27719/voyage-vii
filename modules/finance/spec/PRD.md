# Finance Module PRD

Status: target module PRD, not an accepted ADR.

The finance module is the first concrete Voyage VII product module. This
document preserves the deferred financial-domain decisions from
`docs/planning/v2/FUTURE-FINANCE.md` except where the holistic product PRD
reframes ownership around modules and the Rust/Tauri platform gateway.

This PRD does not implement schemas, migrations, or executable contracts. The
current Zig adapter location reflects the approved module restructuring, while
future implementation changes must use reviewed tasks and any required
superseding ADRs.

Read this PRD with the holistic
[Voyage VII Product Requirements](../../../product/spec/PRD.md) and the
[module structure guide](../../README.md).

## Module purpose

Finance helps the single local owner model their personal money using strict
cash-basis double-entry accounting, budgets, periods, reports, and isolated
forecast simulations. It exposes finance capabilities through the app gateway
to the bundled UI, CLI, and MCP server. Callers must not bypass the gateway to
reach private finance APIs, finance schema objects, or finance specialty
storage resources.

The Zig/api.zig work belongs to the finance implementation adapter, not to the
whole app platform. The current adapter is colocated at
`modules/finance/adapters/zig-api/`. Accepted ADRs and current v2
implementation records remain authoritative until a future reviewed ADR
explicitly supersedes them.

## Ledger model

Finance starts with one OS-trusted local user and one single-person USD
ledger.

The ledger uses strict double-entry accounting on a cash basis. Finance owns
its SQLite schema or namespace for ledger, account metadata, periods, budgets,
and lifecycle state inside the platform-managed shared SQLite database.
Cross-module user records belong to the platform schema and are referenced by
finance rather than owned by finance. TigerBeetle is a finance-only specialty
engine for balances and transfers. The MVP does not duplicate transaction rows
in SQL.

Account classes use RED ALE:

- Revenue;
- Expense;
- Dividend;
- Asset;
- Liability;
- Equity.

TigerBeetle ledger codes are:

- Asset: `1`;
- Liability: `2`;
- Equity: `3`;
- Revenue: `4`;
- Expense: `5`;
- Dividend: `6`.

Finance creates one friendly default account for every class. Custom accounts
may use any class. Account classification is immutable. Default accounts may
be renamed but not archived. Non-default account archival requires a zero
balance and closes the TigerBeetle account; reopening is supported.

## Identifiers and transfer metadata

Finance uses application-generated UUIDv7 identifiers stored canonically in
its SQLite schema. Canonical UUID big-endian bytes convert to TigerBeetle
`u128` values.

The TigerBeetle ledger `u32` is derived from domain-separated BLAKE3. The
effective epoch-day is stored in `user_data_64`; remaining user-data fields
are reserved. Reversal identifiers are derived through a documented XOR
namespace.

Lifecycle operations are SQL-first and deterministic.

## MVP behavior

The MVP supports manual two-account entries only. Splits, recurring entries,
reconciliation, attachments, and polished user-facing import/export workflows
are deferred.

History is built from account-history scans, merged and deduplicated per
request, ordered by effective date, and exposed with an opaque cursor. A
100,000-entry performance test is required before retaining this history
design.

Periods support weekly, 14-day, and calendar-month schedules with an anchor
for interval schedules. Schedule changes apply from a future anchor. Finance
maintains current and next periods.

Period states are:

- draft;
- active;
- closing;
- closed.

Closing moves Revenue, Expense, and Dividend into Equity using a deterministic
SQL close intent. Corrections post in the current period.

Budgets may target all six account classes. Budget values are fixed cents or
basis points of planned revenue and represent planned net movement. Budgets do
not require a balancing constraint.

Initial reports are:

- balance sheet;
- period activity;
- budget variance.

## Import and export

Finance must define canonical versioned import/export schemas as part of its
future module contract. User-facing import/export workflows can ship after the
finance MVP, but the module design must not block portable export, simulation
input creation, or future app-level export bundles.

Finance export is not backup. Backup/restore remains a future platform
feature with stronger consistency requirements across the shared SQLite
database, finance schema, TigerBeetle, and platform metadata.

## Simulation and forecasting

Finance supports isolated forecasts and simulations through the platform
simulation engine. The platform owns sandbox lifecycle, copied or fresh input
data, run metadata, and result storage. Finance provides the finance-specific
simulation adapter.

Finance simulations should support:

- deterministic forecasts from current accounts, periods, budgets, and planned
  activity;
- scenario inputs that alter income, expense, timing, balances, or budget
  assumptions;
- stochastic shock modeling for unexpected events or plan disruptions.

Simulation results may produce recommendations, reports, or exportable plans.
They must not directly mutate real finance data. Any real change must go
through ordinary finance workflows and gateway permission checks.

Cross-module simulation composition is undecided and is not promised by this
module PRD.

## Capabilities

Finance should expose capabilities through the app gateway using the shared
module vocabulary:

- read finance records and reports;
- create/write accounts, entries, budgets, and periods when allowed;
- update/edit mutable metadata and planned values;
- archive/delete only through domain-safe archive, close, or correction
  workflows by default;
- search account, entry, period, budget, and report views;
- import data through future canonical schemas;
- export data through future canonical schemas;
- simulate forecasts and scenarios;
- report balance sheet, period activity, and budget variance.

Every capability requires scoped grants. Audit records should contain metadata
such as actor, capability, scope, timestamp, request id, and stable object
identifiers, but must not contain account names, amounts, tokens, raw entries,
authorization headers, or sensitive values.

## Out of scope for this PRD pass

- executable SQLite migrations;
- implemented DBML changes;
- enforced module manifest or JSON schema files;
- implemented shared SQLite schema namespacing;
- implemented platform database lifecycle changes;
- direct cloud sync or sharing behavior;
- backup/restore;
- dynamic module installation;
- cross-module simulation promises.
