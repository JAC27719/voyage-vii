# Platform Module Registry Proposal

Status: planning draft, non-executable design note.

This note proposes the first static platform module registry shape after
ADR-0013 through ADR-0016. It is not an accepted ADR, manifest schema,
runtime configuration file, database migration, DBML update, or implementation
contract. Implementation tasks may use it as input only after their owned
paths and acceptance checks are reviewed.

Read with:

- [ADR-0013: Platform Runtime and Module Gateway](../adr/0013-platform-runtime-and-module-gateway.md);
- [ADR-0014: Gateway Clients, Grants, and Audit Metadata](../adr/0014-gateway-clients-grants-and-audit-metadata.md);
- [ADR-0015: Module Contracts and Capability Manifests](../adr/0015-module-contracts-and-capability-manifests.md);
- [ADR-0016: Import, Export, and Simulation Boundaries](../adr/0016-import-export-and-simulation-boundaries.md);
- [Platform and Module Boundary Slice](platform-module-boundary-slice.md);
- [Finance Module PRD](../../modules/finance/spec/PRD.md).

## Purpose

The first registry should prove that the Rust/Tauri platform can know about a
first-party finance module without hard-coding UI assumptions or exposing the
finance adapter as the product contract.

The first implementation may be static and build-time. Its data shape should
still look like a future manifest so a later manifest file can replace the
hard-coded registry without changing gateway callers.

## Registry Record

Each registered module should have one platform-owned record:

```text
module:
  id
  display_name
  version
  lifecycle_state
  product_prd_path
  source_root
  capabilities
  operations
  reports
  events
  storage
  specialty_engines
  adapter
  import_export
  simulation
```

`id` is stable and lowercase. `display_name` is user-facing. `version` is the
module contract version, not necessarily the app package version.
`lifecycle_state` starts as one of:

- `available`;
- `disabled`;
- `unavailable`;
- `migrationRequired`.

The initial registry should include only `finance`.

## Capabilities And Operations

Capabilities use ADR-0014's shared vocabulary:

- `read`;
- `create`;
- `update`;
- `archive`;
- `search`;
- `import`;
- `export`;
- `simulate`;
- `report`.

Operations are public gateway operations declared by the module contract. An
operation names:

- operation id;
- required capability;
- required scope shape;
- request schema id;
- response schema id;
- audit object id policy;
- availability state.

Availability state starts as:

- `available`;
- `reserved`;
- `deferred`;
- `unavailable`.

`reserved` means the registry shape is present for a planned public operation
but implementation is not available. `deferred` means the capability belongs
to the module contract but is intentionally later than the first boundary
slice.

## Storage Declaration

Storage declaration should separate platform ownership from module ownership.

The platform owns shared SQLite lifecycle and platform namespaces for:

- local users;
- module registry metadata;
- grants;
- audit metadata;
- import/export manifests;
- simulation run metadata.

A module record may declare module-owned SQLite namespaces inside the
platform-managed shared database. A module record must not declare ownership of
platform namespaces or another module's namespace.

For finance, the proposed module-owned namespace is `finance`. The namespace
is intended for ledger metadata, account metadata, periods, budgets, and
lifecycle state. This note does not create migrations, tables, or DBML.

## Specialty Engines

Specialty engines are explicit and restricted. A registry record declares:

- engine id;
- owning module id;
- purpose;
- required capabilities or operations;
- exclusivity;
- lifecycle owner;
- provenance source.

For finance, TigerBeetle is declared as finance-only for ledger balances and
transfers. No other module receives TigerBeetle access from the platform
registry.

## Adapter Declaration

The adapter declaration describes implementation requirements without making
the adapter a public contract:

```text
adapter:
  kind
  source_root
  runtime_mode
  lifecycle_owner
  health_model
  compatibility_boundary
```

For finance:

- `kind`: `zig-api`;
- `source_root`: `modules/finance/adapters/zig-api/`;
- `runtime_mode`: managed by the platform lifecycle;
- `lifecycle_owner`: platform;
- `health_model`: compatibility bridge to the existing runtime status model;
- `compatibility_boundary`: private adapter routes remain implementation
  details until replaced by gateway operations.

The adapter declaration must not expose supervisor tokens, private URLs,
database paths, local user paths, or specialty-engine handles to ordinary
gateway callers.

## Proposed Finance Record

The first static registry record should be equivalent to:

```text
module:
  id: finance
  display_name: Finance
  version: 0.1.0-proposed
  lifecycle_state: available
  product_prd_path: modules/finance/spec/PRD.md
  source_root: modules/finance
  capabilities:
    read: available
    create: reserved
    update: reserved
    archive: reserved
    search: reserved
    import: deferred
    export: deferred
    simulate: deferred
    report: reserved
  operations:
    runtime_status: available
    list_accounts: reserved
    create_account: reserved
    post_entry: reserved
    archive_account: reserved
    search_entries: reserved
    balance_sheet: reserved
    period_activity: reserved
    budget_variance: reserved
    export_finance: deferred
    import_finance: deferred
    run_forecast: deferred
  reports:
    balance_sheet: reserved
    period_activity: reserved
    budget_variance: reserved
  events:
    finance.lifecycle_changed: reserved
    finance.account_changed: reserved
    finance.entry_posted: reserved
    finance.period_changed: reserved
    finance.budget_changed: reserved
  storage:
    sqlite_namespace: finance
    sqlite_owner: finance
    platform_user_reference: required
  specialty_engines:
    tigerbeetle:
      owner: finance
      purpose: ledger_balances_and_transfers
      exclusive: true
  adapter:
    kind: zig-api
    source_root: modules/finance/adapters/zig-api/
    lifecycle_owner: platform
```

The `runtime_status` operation is listed only as a compatibility bridge for
the existing app-status slice. Product finance operations remain reserved or
deferred until implementation tasks add gateway operations and tests.

## Validation Expectations

The first implementation task that adds a static registry should test:

- every module id is unique;
- every capability is in the ADR-0014 vocabulary;
- every operation references a declared capability;
- every schema id is present or explicitly reserved;
- every SQLite namespace owner is unique;
- platform namespaces cannot be claimed by modules;
- TigerBeetle is restricted to finance;
- adapter source roots stay inside the owning module path;
- no registry value contains tokens, local absolute paths, credentials,
  private adapter URLs, or database connection strings.

## Non-Goals

This proposal does not implement:

- manifest file loading;
- JSON Schema validation;
- SQLite migrations;
- implemented DBML changes;
- gateway routing;
- grants or audit storage;
- import/export formats;
- simulation sandboxes;
- finance product workflows;
- dynamic modules.
