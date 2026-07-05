# Platform and Module Boundary Slice

Status: planning draft, not an accepted ADR or implementation contract.

This slice describes the first implementation-planning boundary after the
platform/module ADRs are accepted. It is intentionally smaller than the full
holistic app vision: prove one gateway, one static module registry, and one
finance adapter integration path before adding more modules, enforced schemas,
or cross-module behavior.

Read with:

- [Voyage VII Product Requirements](../../product/spec/PRD.md);
- [Voyage VII Modules](../../modules/README.md);
- [Platform and Module ADR Supersession Plan](platform-module-adr-supersession-plan.md);
- [Platform Module Registry Proposal](platform-module-registry-proposal.md).

## Slice outcome

The first boundary slice is complete when Voyage VII has a documented and
implemented platform seam where:

- the Rust/Tauri platform owns the local gateway;
- the bundled UI reaches finance through the gateway;
- future CLI and MCP clients have reserved gateway entry points;
- finance is registered as a first-party static module;
- the current Zig adapter remains finance-owned and is launched or called
  through platform-owned lifecycle rules;
- the platform owns shared SQLite lifecycle and records finance as a schema or
  namespace owner;
- TigerBeetle is recorded as a finance-only specialty engine;
- gateway calls carry caller identity, requested capability, and module scope;
- audit records capture metadata without sensitive domain payloads.

## Non-goals

This slice must not promise or implement:

- dynamic third-party modules;
- cloud sync or sharing;
- cross-module simulation;
- final JSON schemas for every module contract;
- backup/restore;
- direct UI, CLI, MCP, or agent access to private finance adapter APIs;
- replacement of the existing finance ledger model.

## Boundary components

### Platform gateway

The gateway is the only supported app-level entry point for UI, CLI, MCP, and
future callers. It is responsible for:

- resolving caller identity;
- checking grants;
- routing requests to module public operations;
- adding request ids;
- recording metadata-only audit events;
- normalizing errors;
- preventing clients from reaching module schema objects, specialty engines,
  or private adapter APIs.

### Shared Storage

The first boundary should treat SQLite as a platform-managed shared database.
The platform owns lifecycle, connection policy, and platform schemas for
cross-module concerns such as users, module registry metadata, grants, audit
metadata, import/export manifests, and simulation run metadata.

Modules own schema or namespace boundaries inside shared storage. Finance owns
finance schema objects for ledger metadata, but it must not own the platform
user schema. Gateway grants and audit metadata are one enforcement layer; the
schema namespace boundary is another. Modules must not directly read or write
another module's namespace.

TigerBeetle should be modeled as a finance-only specialty engine in this
slice. The registry should make that restriction visible so future modules do
not accidentally inherit TigerBeetle access just because finance uses it.

### Static module registry

The first registry can be build-time static. It should expose finance with:

- module id: `finance`;
- lifecycle state;
- supported public capabilities;
- adapter kind: `zig-api`;
- runtime needs;
- shared SQLite schema or namespace ownership;
- specialty engine requirements: TigerBeetle restricted to finance;
- import/export availability state;
- simulation availability state.

The registry should be shaped so a later manifest file can replace hard-coded
metadata without changing caller behavior.

### Finance adapter bridge

The finance adapter bridge keeps the existing Zig implementation usable while
the platform boundary evolves. It should:

- treat `modules/finance/adapters/zig-api/` as finance-owned source;
- hide adapter-specific process details from UI, CLI, and MCP callers;
- preserve current SQLite and TigerBeetle behavior until superseded while
  planning toward platform-managed shared SQLite and finance-only TigerBeetle
  access;
- avoid exposing raw adapter routes as the public long-term contract;
- keep adapter launch, shutdown, and health observation under platform
  lifecycle control.

### Client surfaces

The bundled UI is the first active gateway client. CLI and MCP should be
reserved as first-class clients in the gateway shape even if their user-facing
commands/tools are not implemented in the first slice.

Client behavior should be consistent:

- request through the gateway;
- receive scoped errors;
- never receive supervisor tokens or private adapter credentials;
- never infer storage paths, schema names, specialty-engine handles, or
  implementation stack details.

### Audit metadata

Audit should start as metadata-only and local. Initial fields should be:

- request id;
- timestamp;
- caller id;
- surface: `ui`, `cli`, `mcp`, or `internal`;
- module id;
- capability;
- scope;
- outcome;
- stable object identifiers when safe.

Audit records must not include account names, amounts, raw entries, tokens,
authorization headers, local filesystem paths containing usernames, or private
payloads.

## First task candidates

1. Complete and integrate ADR-0013 through ADR-0016.
2. Complete and integrate the non-executable [module registry design note](platform-module-registry-proposal.md) or proposed manifest.
3. Run `PLATFORM-001` to add Rust platform gateway interfaces and static
   finance module registration without changing finance behavior.
4. Add a storage boundary design note for shared SQLite schemas and specialty
   engine restrictions.
5. Route the existing UI runtime/status reads through the gateway seam.
6. Add metadata-only audit scaffolding for gateway calls.
7. Add CLI and MCP reserved interface notes after the gateway seam is stable.

Each task should own a narrow path set and preserve existing app startup until
the gateway has parity with the current desktop bridge.

## Acceptance checks

The slice should require:

- unit tests for gateway routing and grant denial;
- tests proving UI calls do not bypass the gateway;
- tests proving audit records omit sensitive fields;
- tests proving module calls cannot cross declared schema or specialty-engine
  boundaries without a grant;
- a staging or smoke check that the desktop still starts with finance
  registered;
- documentation that maps accepted ADR decisions to the implemented boundary.

Full package generation, final manifest schemas, and CLI/MCP executable
surfaces can remain later tasks if this first slice keeps their gateway
extension points visible.
