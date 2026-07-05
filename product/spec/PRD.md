# Voyage VII Product Requirements

Status: target product PRD, not an accepted ADR.

This document describes the intended product direction for Voyage VII as a
holistic local-first life engine. It does not supersede accepted ADRs or the
current v2 implementation records. Any implementation work that changes frozen
architecture, process ownership, public contracts, storage ownership, or
runtime responsibilities must first add a reviewed ADR that explicitly
supersedes the affected records.

## Product vision

Voyage VII is a local-first engine for managing personal life domains. The
primary user is one local owner who controls their own data, runs the main
application locally, and can choose the surface that drives the engine:

- the bundled desktop UI;
- a local CLI;
- a local MCP server for agent harnesses such as Codex and Claude.

The bundled UI is a replaceable client, not the product boundary. The durable
product is the local engine, its module contracts, its permission model, and
the data it safely manages.

Finance is the first concrete module. Future lifestyle modules should be added
only when their product domain, module contract, import/export shape, and
platform integration points are clear.

The first module structure is described in [Voyage VII Modules](../../modules/README.md),
with the initial finance module PRD at
[Finance Module PRD](../../modules/finance/spec/PRD.md).

## Platform responsibilities

The target platform runtime is Rust/Tauri. It owns app-level orchestration and
security concerns:

- local runtime lifecycle, including headless operation;
- a single gateway for UI, CLI, MCP, and future callers;
- module registry and module lifecycle;
- module adapter and database lifecycle orchestration;
- caller identity, scoped grants, revocation, and authorization checks;
- metadata-only audit records;
- cross-module access mediation;
- import/export orchestration;
- simulation sandbox orchestration;
- platform settings and other platform-owned durable metadata.

Modules own domain behavior and durable domain data models behind published
contracts. The platform owns shared database lifecycle, connection policy,
adapter lifecycle, and cross-module storage coordination. The platform must
not require all modules to use the same implementation stack. Each module
implementation adapter declares its stack, pinned runtime inputs, storage
needs, and process/lifecycle needs through future ADR and task governance.

## Storage Model

The target storage model is shared platform-managed databases, not a separate
private database per module. Modules receive isolated ownership through
declared schemas or namespaces inside shared engines, gateway-mediated access,
scoped grants, and audit metadata.

SQLite is expected to be the common local relational dependency for most
modules. The platform should manage the SQLite database lifecycle and reserve
a platform schema or namespace for cross-module concepts such as local users,
module registry metadata, grants, audit metadata, import/export manifests,
and simulation run metadata. Each module should declare its own schema or
namespace for domain tables and migrations.

Specialty storage engines must be explicitly declared and restricted. Finance
may use TigerBeetle for ledger balances and transfers because that requirement
belongs to the finance domain. Other modules must not use TigerBeetle unless a
future module PRD and reviewed ADR justify that dependency and the platform
grants the module access.

This target direction is expected to require future ADRs that supersede parts
of the current v2 architecture, especially the accepted decisions that make the
Zig API the whole app backend and make Tauri only the API supervisor.

## Access surfaces

The bundled UI, CLI, and MCP server are official clients of the same local
gateway. None should bypass the gateway to call private module APIs or read
module storage directly.

All callers receive explicit scoped grants. A grant names the caller, module,
capability, and scope. The shared capability vocabulary is:

- read;
- create/write;
- update/edit;
- archive/delete;
- search;
- import;
- export;
- simulate;
- report.

Modules should prefer archive, close, or revoke workflows over irreversible
delete. Irreversible deletion requires a module-specific justification and a
stronger permission than ordinary edit access.

Audit records must be useful for accountability without exposing private life
data. They should record metadata such as actor, capability, scope, timestamp,
request id, and stable object identifiers. They must not record tokens, names,
amounts, raw records, authorization headers, or sensitive values.

## Module model

Modules are first-party, repository-owned, and statically registered at build
time in the initial architecture. Module manifests remain required so the
platform has a stable contract shape and can evolve toward dynamic modules
later without changing the product model.

Every module must eventually publish a tech-neutral manifest and schemas that
define:

- module identity, version, and lifecycle state;
- capabilities and required permission scopes;
- events emitted to the platform;
- import and export formats;
- simulation support, if any;
- reports exposed to callers;
- storage namespace ownership, shared-engine requirements, specialty-engine
  requirements, and backup-safety notes;
- adapter requirements and supported runtime modes;
- public request and response schemas.

The manifest and schemas are future interface artifacts. This PRD does not add
enforced schema files.

Cross-module access is gateway-mediated. A module that needs another module's
data asks the platform for a capability-backed view or operation. It must not
reach into another module's schema namespace, storage objects, specialty
engine resources, or private adapter API.

## Import, export, and backup

Import/export is a portable data exchange feature. Each module must define
versioned canonical import/export formats, and the platform may bundle several
module exports into one portable app package.

Backup/restore is a separate future platform feature. It has stronger
consistency requirements than export and must coordinate with module storage
schemas, shared storage engines, specialty engines, and platform metadata
rather than copying arbitrary live files.

Cloud sync and selective sharing are deferred. Current module identifiers,
permissions, export formats, and audit metadata should leave room for future
sync and sharing, but this PRD does not require cloud accounts, remote
services, collaboration workflows, or shared ownership.

## Simulation

Simulation is a platform capability. The platform owns sandbox lifecycle,
copied or fresh input data, run metadata, and result storage. Modules provide
simulation-capable adapters when their domain supports projections or
forecasts.

Simulation data is isolated from real module data. Simulation results may
export recommendations, reports, or draft plans, but they must not directly
mutate real module stores. Any real change must go through the ordinary module
workflow and permission checks.

Cross-module simulations are intentionally undecided. The platform should not
promise composition across modules until multiple modules define compatible
simulation contracts.

## Success criteria

This product direction is ready for implementation planning when:

- the holistic PRD and module PRDs clearly distinguish target product intent
  from accepted ADRs;
- future ADR supersession needs are visible before implementation starts;
- each new module can be placed under `modules/<name>/` with local product and
  operational context;
- shared storage boundaries distinguish platform schemas, module schemas, and
  restricted specialty engines;
- UI, CLI, and MCP are treated as first-class gateway clients;
- agents can discover safe, scoped read/write/search/import/export/simulate
  capabilities without depending on UI internals;
- finance remains the first concrete module without making its Zig adapter the
  universal app backend.
