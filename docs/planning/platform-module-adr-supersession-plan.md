# Platform and Module ADR Supersession Plan

Status: planning draft, not an accepted ADR.

This plan translates the holistic Voyage VII PRD and module restructure into
the ADR work needed before implementation changes platform/runtime authority,
public access surfaces, storage ownership, or module contracts. Accepted ADRs
remain authoritative until a future reviewed ADR explicitly supersedes the
affected records.

Read with:

- [Voyage VII Product Requirements](../../product/spec/PRD.md);
- [Voyage VII Modules](../../modules/README.md);
- [Finance Module PRD](../../modules/finance/spec/PRD.md);
- [Architecture Decision Records](../adr/README.md).

## Supersession goals

The future ADR set must make these target decisions explicit:

- Rust/Tauri is the platform runtime and gateway owner.
- UI, CLI, and MCP are first-class gateway clients.
- Modules are first-party product domains with tech-neutral contracts.
- The finance Zig API is a finance-owned adapter, not the whole app backend.
- The platform owns shared database lifecycle and module adapter lifecycle.
- Modules own schemas or namespaces inside shared databases rather than
  private database files by default.
- Specialty engines such as TigerBeetle are module-declared and restricted.
- Gateway authorization uses scoped grants, revocation, and metadata-only
  audit records.
- Import/export and simulation are platform-orchestrated capabilities backed
  by module contracts.

## ADR sequence

### ADR-0013: Platform Runtime and Module Gateway

Purpose: redefine the product process boundary around a Rust/Tauri platform
runtime that owns gateway, module registry, runtime lifecycle, and headless
operation.

Expected supersession:

- ADR-0001 portions that make the Zig API the single database-facing service
  and Tauri only the API supervisor;
- ADR-0004 portions that define managed/external modes around one API process;
- ADR-0009 portions that make the desktop bridge the only app command surface.

Must decide:

- platform-owned gateway responsibilities;
- platform-owned shared database lifecycle responsibilities;
- static first-party module registration model;
- module lifecycle and adapter process ownership;
- compatibility path for the existing finance Zig adapter;
- what remains from the existing app/supervisor token model.

Out of scope:

- final module manifest schemas;
- cloud sync;
- dynamic third-party plugins.

### ADR-0014: Gateway Clients, Grants, and Audit Metadata

Purpose: define UI, CLI, and MCP as official gateway clients with common
identity, scoped grants, revocation, and metadata-only audit behavior.

Expected supersession:

- ADR-0005 portions that only model app and supervisor bearer tokens for the
  desktop-to-API boundary;
- ADR-0009 portions that restrict JavaScript-facing access to the current
  runtime snapshot and log seams.

Must decide:

- local caller identity model;
- grant vocabulary and scope shape;
- revocation behavior;
- audit metadata fields and prohibited sensitive fields;
- gateway enforcement rule that clients do not call private module adapters.

Out of scope:

- remote accounts;
- collaboration or sharing;
- telemetry.

### ADR-0015: Module Contracts and Capability Manifests

Purpose: freeze the first version of module manifests and tech-neutral
contract requirements for first-party modules.

Expected supersession:

- ADR-0003 portions that make api.zig and native clients the app-wide
  implementation substrate;
- ADR-0007 portions that assume one app runtime artifact set is enough to
  describe all backend implementation requirements;
- ADR-0012 portions that make SQLite a single API-owned database boundary
  rather than a platform-managed shared database with module schemas.

Must decide:

- manifest identity, version, lifecycle, capabilities, permission scopes,
  events, reports, and adapter requirements;
- schema or namespace ownership and validation expectations;
- how module storage requirements are declared for shared engines;
- how platform schemas for users, grants, audit metadata, import/export, and
  simulation metadata coexist with module schemas;
- how finance declares TigerBeetle as a restricted specialty engine without
  making it available to every future module.

Out of scope:

- dynamic module installation;
- third-party module trust model.

### ADR-0016: Import, Export, and Simulation Boundaries

Purpose: separate portable import/export from backup/restore and define the
platform/module split for sandboxed simulations.

Expected supersession:

- ADR-0006 portions that treat writable roots and local lifecycle as the only
  durable app data coordination boundary;
- ADR-0008 portions that conflate packaged runtime layout with all portable
  app artifact concerns;
- ADR-0012 portions that assume implemented SQLite schema documentation is the
  main durable data portability surface without platform/module schema
  separation.

Must decide:

- platform-owned export bundle orchestration;
- module-owned canonical import/export formats;
- coordination across platform schemas, module schemas, and specialty engines;
- simulation sandbox lifecycle and isolation guarantees;
- deterministic versus stochastic simulation result expectations;
- explicit statement that backup/restore is a separate future feature.

Out of scope:

- cross-module simulation composition;
- cloud backup or sync.

## Ordering dependencies

ADR-0013 should land first because it determines the process and authority
boundary. ADR-0014 depends on ADR-0013 because grants and audit are enforced by
the gateway. ADR-0015 depends on ADR-0013 because module contracts need the
module lifecycle and registry shape. ADR-0016 depends on ADR-0015 because
import/export and simulation need module-declared capabilities and schemas.

## Implementation gates

No implementation task should change the following until the corresponding ADR
is accepted:

- gateway routing or module lifecycle authority;
- CLI or MCP write access;
- grant, revocation, or audit storage;
- manifest/schema enforcement;
- shared database lifecycle or schema namespace enforcement;
- specialty-engine grants such as TigerBeetle access;
- import/export executable contracts;
- simulation sandbox behavior;
- finance storage semantics beyond the currently accepted SQLite and
  TigerBeetle model.

The existing module restructure may remain as documentation and source layout.
It does not by itself supersede accepted runtime, security, or storage ADRs.
