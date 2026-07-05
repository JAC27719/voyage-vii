# ADR-0013: Platform Runtime and Module Gateway

- Status: Accepted
- Date: 2026-07-05

## Context

Voyage VII's first v2 slice proved a local Windows desktop runtime with a
Tauri supervisor, SolidJS UI, Zig API process, SQLite, and TigerBeetle. That
slice intentionally did not ship financial product behavior or a durable
module boundary.

The next product direction makes Voyage VII a local-first engine whose
durable boundary is the platform runtime, gateway, module contracts, and user
data rather than one bundled UI or one backend implementation stack. Finance
is the first concrete module. The existing Zig API implementation has been
restructured under `modules/finance/adapters/zig-api/`, but accepted ADRs still
describe it as the whole app backend until a superseding decision changes that
authority.

Before implementation can route product behavior through modules, the project
needs one accepted process and ownership boundary for the Rust/Tauri platform,
the app gateway, the static module registry, adapter lifecycle, shared storage
lifecycle, and the compatibility path for the existing finance Zig adapter.

## Decision

Rust/Tauri is the Voyage VII platform runtime. It owns the local app gateway,
module registry, module adapter lifecycle orchestration, shared storage
lifecycle authority, client-facing command surfaces, and final process
containment.

The platform gateway is the only supported app-level entry point for the
bundled UI and for future local CLI and MCP clients. UI, CLI, MCP, and agent
harnesses must not call private module adapter APIs, read module schema
objects directly, access specialty engine handles, infer storage paths, or
receive supervisor credentials. Gateway requests must be shaped to carry a
caller identity, target module, requested capability, scope, request id, and
normalized error outcome, even while the detailed grant and audit model remains
governed by a later ADR.

Modules are first-party product domains registered by the platform. The first
registry is static and build-time. It must be shaped so a future manifest file
can replace hard-coded metadata without changing caller behavior. The registry
records at least module id, lifecycle state, public capability names, adapter
kind, runtime needs, shared SQLite namespace ownership, specialty engine
requirements, and import/export and simulation availability state.

Finance is the first registered module. The current Zig API is the
finance-owned `zig-api` adapter, not the universal app backend. Its source
remains under `modules/finance/adapters/zig-api/`. Existing finance adapter
behavior, routes, SQLite migrations, TigerBeetle usage, package layout, and
runtime smoke coverage remain valid compatibility behavior until reviewed
implementation tasks replace them behind the gateway.

The platform owns shared SQLite lifecycle authority for the target module
model. SQLite remains the common local relational engine, but modules own
declared schemas or namespaces inside platform-managed storage rather than
private app databases by default. The existing finance adapter may continue to
execute current SQLite access during the compatibility phase; later tasks must
move or enforce lifecycle and namespace behavior only through reviewed ADRs and
tasks that also preserve the migration and DBML review rule.

TigerBeetle is a finance-only specialty engine in this architecture. The
platform registry must make specialty engine access explicit so future modules
do not inherit TigerBeetle access merely because finance uses it.

The existing app/supervisor token and shutdown containment model remains the
compatibility security boundary for the finance Zig adapter until the gateway
client, grant, revocation, and audit metadata ADR supersedes it. The supervisor
token still must not enter JavaScript or any future ordinary client surface.

This ADR does not add dynamic third-party modules, remote accounts, cloud sync,
sharing, final module manifest schemas, executable CLI or MCP commands, backup
or restore behavior, cross-module simulation, or new financial ledger
semantics.

## Rejected alternatives

- Continuing to treat the Zig API as the universal Voyage VII backend.
- Letting the bundled UI, CLI, MCP, or agents call finance adapter routes as
  the long-term public contract.
- Giving each module an independent private database lifecycle by default.
- Making TigerBeetle a platform-wide engine available to every future module.
- Introducing dynamic third-party module loading before first-party static
  module boundaries are proven.
- Folding grant, audit, manifest, import/export, simulation, or backup details
  into this ADR before their planned records are written.

## Consequences

Future product implementation starts at the platform gateway and module
registry, not by adding public routes directly to the finance adapter. The
desktop UI remains replaceable client code. CLI and MCP are first-class future
clients of the same gateway shape, but their executable surfaces are not
implemented by this decision.

The existing finance Zig adapter stays useful while the platform boundary
evolves. Compatibility tasks may bridge to it, launch it, probe it, and shut it
down through platform-owned lifecycle rules, but callers must not treat its
private routes or storage details as stable product contracts.

Shared SQLite ownership becomes a platform/module boundary to design and test.
Any task that changes implemented SQLite tables, columns, constraints, indexes,
triggers, relations, or migrations still owns the synchronized implemented
DBML update in the same reviewed task.

Follow-up ADRs must define gateway clients, grants, revocation, metadata-only
audit records, module manifests, storage namespace validation, import/export,
and simulation before implementation relies on those details.

## Supersession

This ADR supersedes the portions of ADR-0001 that make the Zig API the
universal database-facing service and make Tauri only the API supervisor. Tauri
is now the platform runtime and gateway owner. The finance Zig API remains a
managed adapter behind that platform boundary.

This ADR supersedes the portions of ADR-0004 that define managed and external
runtime modes only around one app-wide API process. Future modes are
platform-owned lifecycle configurations that may orchestrate module adapters
and shared storage. Existing finance adapter CLI and loopback rules remain
valid compatibility contracts until reviewed tasks replace them.

This ADR supersedes the portions of ADR-0009 that make the desktop bridge the
only app command surface and treat the static UI module registry as the app's
module authority. The platform gateway and static platform module registry are
now the authority boundary. The existing UI status bridge, token custody,
window behavior, and debug-only DevTools rules remain in force until changed by
a later ADR.

This ADR does not supersede the Windows 11 x64 current support gate,
local-first/no-cloud boundary, no-telemetry rule, strict origin and token
safety requirements, TigerBeetle C ABI decision, SQLite migration and DBML
synchronization rule, package provenance rules, or the requirement to change
accepted decisions only through explicit superseding ADRs.
