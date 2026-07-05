# ADR-0016: Import, Export, and Simulation Boundaries

- Status: Accepted
- Date: 2026-07-05

## Context

ADR-0013 defines the platform gateway and module authority. ADR-0014 defines
gateway clients, grants, revocation, and metadata-only audit. ADR-0015 defines
module contracts and capability manifests. Those decisions make import,
export, and simulation visible as platform-orchestrated capabilities, but they
do not yet separate portable data exchange from backup/restore or define how
simulation data stays isolated from real module data.

The first v2 slice treated writable roots, package layout, and implemented
SQLite DBML as the main durable-data surfaces. That was enough for runtime
packaging and smoke tests, but it is not enough for a module product model.
Portable import/export needs versioned module formats and platform bundle
orchestration. Backup/restore needs a stronger future consistency model across
platform schemas, module schemas, SQLite WAL/checkpoints, TigerBeetle, module
adapters, and runtime state. Simulation needs isolated data and run metadata so
forecasts can be explored without mutating real records.

## Decision

Import/export is a portable data exchange capability, not backup/restore. The
platform owns export bundle orchestration, import orchestration, manifesting,
caller authorization, audit metadata, and coordination across modules. Modules
own their canonical versioned import and export formats and validate their
domain records behind the platform gateway.

A platform export bundle may contain platform-owned metadata plus one or more
module exports. The bundle must include version, producer, target module ids,
module export format ids, creation metadata, integrity metadata, and enough
manifest information for the platform to reject unsupported or incompatible
imports before domain writes begin. Export bundles must not contain tokens,
supervisor credentials, local absolute paths, database connection strings,
raw logs, runtime manifests containing secrets, or private adapter
configuration.

A module export format must be canonical, versioned, documented by the module
contract, and stable enough for later import validation. Module exports may
contain domain data only through the approved public export schema. They must
not expose private adapter routes, implementation-only table layouts,
specialty-engine handles, or audit payloads. Finance export must coordinate
its SQLite namespace data and TigerBeetle-derived ledger state through a
future reviewed contract; it must not claim to be a backup of live finance
storage.

Import is a gateway operation. The platform authorizes the caller, validates
the bundle envelope, routes module payloads to declared module import
operations, records metadata-only audit events, and prevents partial
cross-module writes from being presented as a successful import. Modules
validate domain payloads and produce module-specific import plans, errors, or
writes through their public contract. Import must not bypass grants, module
schemas, specialty-engine restrictions, or adapter lifecycle rules.

Backup/restore is a separate future platform feature. It must coordinate
consistent storage state across platform schemas, module schemas, SQLite WAL
and checkpoints, TigerBeetle, adapter lifecycle, runtime locks, manifests, and
package/runtime version compatibility. This ADR does not approve live file copy
as backup, automatic reset, repair, migration downgrade, or restore tooling.

Simulation is a platform capability backed by module contracts. The platform
owns simulation sandbox lifecycle, simulation run metadata, input selection,
copied or fresh data setup, result storage, authorization, and audit metadata.
Modules may provide simulation-capable operations when their contract declares
the `simulate` capability and a simulation availability state.

Simulation data is isolated from real module data. A simulation may use a
snapshot copy, synthetic input, or explicit scenario input, but simulation
operations must not mutate real module stores, real TigerBeetle state, real
platform grants, or real audit history. Promoting a simulated recommendation
to real data requires a separate ordinary gateway operation with the required
capability and scope.

Simulation result contracts may be deterministic, stochastic, or both. A
deterministic simulation must declare the input snapshot, parameters, and
versioned algorithm inputs needed to reproduce the result. A stochastic
simulation must declare random seed handling, distribution/version metadata,
and uncertainty output shape. Results must not include prohibited audit
payloads, tokens, credentials, local paths, raw private adapter details, or
storage handles.

Cross-module simulation composition is not promised. A future ADR must define
composition semantics, dependency ordering, consistency guarantees, and
failure behavior before one simulation run spans multiple modules as a single
product feature.

This ADR does not implement import/export formats, export bundle files,
importers, simulation sandboxes, cross-module simulation, backup/restore,
cloud sync, collaboration, automatic reset, repair, migration downgrade, or new
finance ledger behavior.

## Rejected alternatives

- Treating export bundles as backup or restore artifacts.
- Copying live SQLite, TigerBeetle, runtime, or package files as a portable
  export feature.
- Letting modules import or export by bypassing the platform gateway.
- Letting simulations write directly into real module storage.
- Recording simulation inputs, report bodies, account names, amounts, tokens,
  credentials, or raw private records in audit metadata.
- Promising cross-module simulation composition before multiple modules have
  compatible contracts.
- Treating implemented DBML as the only durable data portability contract.

## Consequences

Import/export implementation must add platform bundle orchestration plus
module-owned canonical formats instead of exposing raw database files.
User-facing export can arrive before backup/restore, but it must be described
truthfully as portable exchange data with format and compatibility limits.

Backup/restore remains intentionally deferred. Future backup work must address
runtime quiescence, SQLite consistency, TigerBeetle consistency, module adapter
lifecycle, platform metadata, package/runtime versions, encryption or custody
policy if needed, and restore failure behavior before it is exposed to users.

Simulation implementation must create isolated storage and run metadata before
module simulation operations become product features. Tests must prove
simulation cannot mutate real module storage, real specialty-engine state, or
real grants, and that promotion from simulation to real data goes through an
ordinary granted gateway operation.

Finance simulations may use deterministic forecasts and stochastic shock
models only through a finance-declared simulation contract. Finance import and
export formats must coordinate SQLite metadata and TigerBeetle ledger state
without claiming to be backup/restore.

## Supersession

This ADR supersedes the portions of ADR-0006 that treat writable roots and
local lifecycle as the only durable app data coordination boundary. Writable
root locking, redaction, runtime safety, and the absence of automatic reset,
repair, and backup tooling remain in force until a later ADR supersedes them.

This ADR supersedes the portions of ADR-0008 that conflate packaged runtime
layout with portable app data concerns. Package layout and runtime provenance
remain governed by ADR-0008, ADR-0011, and ADR-0012, but portable data exchange
is governed by platform export bundles and module export formats.

This ADR supersedes the portions of ADR-0012 that make implemented SQLite
schema documentation the main durable data portability surface. Implemented
DBML remains required for reviewed SQLite migrations, but import/export and
simulation use platform/module contracts and versioned public schemas.

This ADR does not supersede Windows 11 x64 current support, local-first and
no-cloud boundaries, no-telemetry rules, strict token custody, SQLite
migration and DBML synchronization, TigerBeetle's finance ledger role, package
provenance requirements, or the explicit-ADR supersession rule.
