# ADR-0015: Module Contracts and Capability Manifests

- Status: Accepted
- Date: 2026-07-05

## Context

ADR-0013 makes Rust/Tauri the platform runtime and module gateway owner.
ADR-0014 defines gateway clients, scoped grants, revocation, and
metadata-only audit records. The remaining boundary gap is the module contract
itself: the platform needs a tech-neutral way to know what a first-party module
is, which capabilities it exposes, what storage it owns, what adapters it
needs, and which public operations callers may request through the gateway.

The first v2 slice treated api.zig and its native dependencies as the app-wide
backend substrate. The current product direction makes finance the first
module and keeps the existing Zig implementation as finance's `zig-api`
adapter. Future modules must not inherit Zig, TigerBeetle, private finance
routes, or finance storage assumptions merely because those choices exist for
finance.

The project needs one accepted contract shape before implementation adds a
platform module registry, manifest files, or gateway routing for finance and
future modules.

## Decision

Modules are first-party product domains with tech-neutral contracts. A module
contract is expressed through a capability manifest plus referenced public
schemas. The first implementation may keep the registry static and build-time,
but the registry metadata must use the same shape as the manifest so a later
manifest file can replace hard-coded registration without changing gateway
caller behavior.

A module manifest must declare:

- module id, display name, version, and lifecycle state;
- owning repository path and product PRD path;
- supported capabilities from ADR-0014's shared vocabulary;
- required permission scopes for each capability;
- public request and response schema identifiers;
- public operations and the capability each operation requires;
- events emitted to the platform;
- reports exposed to callers;
- import and export format identifiers and availability state;
- simulation capability and availability state;
- shared storage namespace ownership;
- shared-engine requirements;
- specialty-engine requirements and restrictions;
- adapter kind, adapter source root, runtime needs, and lifecycle needs;
- pinned runtime inputs and provenance requirements;
- backup-safety and export-safety notes.

Public schemas are part of the module contract. They describe gateway-facing
request, response, event, import, export, simulation, and report shapes. They
must not expose private adapter routes, database connection details, local
filesystem paths, credentials, supervisor tokens, specialty-engine handles, or
implementation-only table layouts unless an accepted ADR deliberately makes
that shape public.

The platform owns manifest loading, validation, registration, adapter
lifecycle orchestration, shared storage lifecycle, gateway authorization, and
cross-module mediation. Modules own domain behavior and domain data models
behind the manifest. Modules may choose different implementation adapters
after reviewed ADR/task approval, but callers interact with the public module
contract through the platform gateway rather than with adapter-specific APIs.

SQLite is the common shared relational engine. The platform owns SQLite
lifecycle and platform schemas or namespaces for cross-module concepts such as
local users, module registry metadata, grants, audit metadata, import/export
manifests, and simulation run metadata. A module may own declared schemas or
namespaces inside that platform-managed SQLite database. A module must not read
or write another module's namespace directly. Cross-module access requires a
gateway operation with an explicit grant and a public contract.

Executable SQL migrations remain authoritative for implemented SQLite schema.
Any reviewed task that changes implemented relational tables, columns, types,
constraints, indexes, triggers, relations, or migrations still owns and updates
the synchronized implemented DBML in the same task. Proposed public schemas,
manifest schemas, and import/export schemas must remain separate from the
implemented DBML until executable migrations are accepted.

Specialty engines are opt-in and module-restricted. A manifest must justify
each specialty engine, declare which capabilities and operations need it, and
state whether access is exclusive to that module. No module receives a
specialty-engine grant by default.

Finance is the first registered module:

- module id: `finance`;
- adapter kind: `zig-api`;
- adapter source root: `modules/finance/adapters/zig-api/`;
- shared SQLite namespace owner: finance ledger metadata, account metadata,
  periods, budgets, and lifecycle state;
- specialty engine: TigerBeetle for finance ledger balances and transfers
  only;
- initial reports: balance sheet, period activity, and budget variance;
- import/export: contract-required but user-facing workflows may remain
  unavailable until later implementation;
- simulation: contract-required for finance forecasting, with executable
  sandbox behavior deferred to ADR-0016 and later tasks.

Other modules must not use TigerBeetle or any other specialty engine unless a
module PRD and reviewed ADR justify the dependency, declare its manifest
requirements, and define platform enforcement.

This ADR does not add dynamic third-party module installation, final JSON
Schema file paths, executable manifest parsing, implemented platform or module
SQLite migrations, implemented import/export formats, executable simulation
sandboxes, backup/restore, cloud sync, collaboration, or new finance ledger
semantics.

## Rejected alternatives

- Treating api.zig routes as the universal module contract.
- Making the existing SolidJS static module list the durable module registry.
- Letting module contracts expose private adapter URLs, schema internals, or
  storage paths as public APIs.
- Giving every module the same implementation stack or specialty engines.
- Allowing modules to own private SQLite databases by default.
- Updating implemented DBML from proposed manifest or schema files before
  executable migrations exist.
- Granting TigerBeetle access to non-finance modules without a future module
  PRD and reviewed ADR.

## Consequences

Future module work must start by updating or adding a manifest-shaped contract
and public schemas before the gateway treats the module as a product surface.
Implementation adapters are replaceable behind the contract. Private adapter
routes can continue as compatibility details, but they are not the public
contract for UI, CLI, MCP, agents, or future callers.

The platform module registry now needs validation tests for identity,
capability names, scope declarations, storage namespace ownership,
specialty-engine restrictions, adapter source roots, and availability states.
Gateway tests must prove callers can only request declared public operations
with granted capabilities and scopes.

The finance Zig adapter remains valid as finance's first implementation
adapter. Its current SQLite and TigerBeetle behavior can be bridged during
compatibility work, but future finance product routes and reports must be
published through the module contract and platform gateway.

Platform-managed SQLite and module-owned namespaces become a required design
surface for future implementation tasks. Those tasks must preserve the rule
that executable migrations and implemented DBML change together.

## Supersession

This ADR supersedes the portions of ADR-0003 that make api.zig and its native
client stack the app-wide implementation substrate. api.zig remains an
approved implementation choice for the finance `zig-api` adapter and the
TigerBeetle C ABI remains the approved finance specialty-engine client
boundary.

This ADR supersedes the portions of ADR-0007 that assume one app runtime
artifact set is sufficient to describe every backend implementation
requirement. Future module manifests must declare adapter runtime needs,
pinned runtime inputs, provenance requirements, and specialty-engine
requirements per module.

This ADR supersedes the portions of ADR-0012 that make SQLite a single
API-owned database boundary. SQLite remains the general-purpose relational
engine, but the platform owns shared SQLite lifecycle and modules own declared
schemas or namespaces inside that platform-managed database. The SQL migration
and implemented DBML synchronization rule remains in force.

This ADR does not supersede Windows 11 x64 current support, local-first and
no-cloud boundaries, no-telemetry rules, strict token custody, TigerBeetle's
finance ledger role, the static C ABI requirement for current TigerBeetle
access, package provenance requirements, or the explicit-ADR supersession rule.
