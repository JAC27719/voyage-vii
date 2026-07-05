# ADR-0014: Gateway Clients, Grants, and Audit Metadata

- Status: Accepted
- Date: 2026-07-05

## Context

ADR-0013 makes Rust/Tauri the Voyage VII platform runtime and gateway owner.
That gateway cannot become the product boundary unless every supported caller
uses the same identity, authorization, revocation, and audit rules. The first
v2 slice only modeled an app token and supervisor token for the desktop-to-Zig
API boundary. That model protects the compatibility adapter, but it is not a
durable permission model for UI, CLI, MCP, internal platform work, and future
module calls.

Voyage VII remains a local-first single-owner application. The current product
direction does not add remote users, collaboration, telemetry, cloud accounts,
or sharing. The grant and audit model therefore needs to be local, explicit,
revocable, and useful for accountability without recording private life data.

## Decision

The platform gateway recognizes four local caller surfaces:

- `ui`: the bundled desktop UI;
- `cli`: future local command-line clients;
- `mcp`: future local MCP clients for agent harnesses;
- `internal`: platform-originated maintenance, lifecycle, and background work.

Every gateway request has a caller identity. The identity must include caller
surface, stable caller id, local user id, request id, and invocation context.
The first implementation may use one OS-trusted local owner, but the gateway
shape must not rely on JavaScript, CLI, MCP, or module adapters impersonating
the platform. Caller identity is resolved by the platform before module
routing.

Gateway authorization uses explicit scoped grants. A grant names:

- local user id;
- caller id;
- caller surface;
- module id;
- capability;
- scope;
- lifecycle state;
- creation and revocation metadata.

The shared capability vocabulary is:

- `read`;
- `create`;
- `update`;
- `archive`;
- `search`;
- `import`;
- `export`;
- `simulate`;
- `report`.

`archive` covers domain-safe archive, close, revoke, reversal, and correction
workflows by default. Irreversible deletion is not part of the shared
capability vocabulary and requires a future module-specific ADR or contract
that justifies the stronger operation and permission.

Scopes are module-defined but platform-enforced. A scope must be serializable,
stable, and narrower than unrestricted storage access. A scope may name a
module-wide operation, object class, stable object id, report, import/export
format, or simulation kind. Scopes must not expose local filesystem paths,
tokens, raw private payloads, specialty-engine handles, or private adapter
routes to ordinary callers.

Grant denial is the default. Missing, expired, revoked, malformed, or
out-of-scope grants fail before private module adapter access. Revocation takes
effect for all later gateway requests. The current request may finish or fail
according to the operation's transaction rules, but no new module operation may
start from a revoked grant. Revocation does not delete prior audit records.

Gateway calls record metadata-only audit events. Initial audit fields are:

- request id;
- timestamp;
- local user id;
- caller id;
- caller surface;
- module id;
- capability;
- scope;
- outcome;
- error code when present;
- stable object identifiers when safe;
- parent request id for internal follow-on work when present.

Audit records must not contain account names, amounts, raw entries, raw import
rows, report bodies, simulation inputs, tokens, authorization headers, local
filesystem paths containing usernames, adapter URLs, database connection
strings, private payloads, or credentials. Audit logs are local application
data, not telemetry, metrics, analytics, or crash reporting.

The gateway is the only supported path from UI, CLI, MCP, and agents to module
behavior. Ordinary callers must not call private module adapter APIs, bypass
the gateway to read module schemas, access SQLite directly, access
TigerBeetle, receive supervisor tokens, or infer implementation-specific
storage and process details. Module adapters trust only platform-supplied
caller and grant context; they do not mint grants for ordinary callers.

The existing app token, supervisor token, stdout handshake, strict origin CORS,
CSP, loopback requirements, and shutdown route remain the compatibility
security boundary for the current finance Zig adapter. Those tokens are not
the product grant model and must not be exposed as grants to UI, CLI, MCP, or
agents. The supervisor token still authorizes only platform-controlled
shutdown and must never enter JavaScript or ordinary client surfaces.

This ADR does not implement executable CLI or MCP commands, remote accounts,
collaboration, cloud sync, telemetry, final module manifest schemas,
import/export formats, simulation sandbox behavior, backup/restore, or
irreversible delete semantics.

## Rejected alternatives

- Treating possession of the existing app token as sufficient product
  authorization.
- Giving JavaScript, CLI, MCP, or agents supervisor authority.
- Letting clients call private module adapter APIs and auditing after the
  fact.
- Recording domain payloads, amounts, account names, raw imports, or report
  bodies in audit records.
- Making audit records telemetry, metrics, analytics, or cloud diagnostics.
- Granting broad filesystem, database, or specialty-engine access instead of
  module capabilities and scopes.
- Adding irreversible deletion to the shared capability vocabulary.

## Consequences

Future UI, CLI, and MCP work must enter through the platform gateway with a
resolved caller identity and an explicit grant. The UI may keep its current
runtime-status bridge during compatibility work, but finance and future module
behavior must be routed through the gateway before it is treated as a product
surface.

The platform needs durable local storage for grants, revocation metadata, and
metadata-only audit records. The exact schema belongs to later implementation
tasks and any module-contract ADRs that define platform and module namespace
boundaries. Any implemented SQLite schema change still owns the synchronized
DBML update in the same reviewed task.

The finance Zig adapter can remain protected by its current token and loopback
contracts while the platform gateway matures. Adapter routes are compatibility
implementation details, not public product contracts for UI, CLI, MCP, or
agents.

Tests for the first gateway implementation must prove grant denial by default,
revocation before new work, no ordinary caller access to private adapter APIs
or supervisor tokens, and audit redaction of prohibited sensitive fields.

## Supersession

This ADR supersedes the portions of ADR-0005 that model authorization only as
desktop app and supervisor bearer tokens for the app-to-API boundary. Those
tokens remain compatibility credentials for the finance Zig adapter, but the
platform gateway grant model is the product authorization boundary.

This ADR supersedes the portions of ADR-0009 that restrict JavaScript-facing
access to only the current runtime snapshot and log seams. The bundled UI is
now an official gateway client for granted module capabilities. The existing
runtime snapshot, log opening, token custody, event payload, window behavior,
restart budget, and debug-only DevTools rules remain in force until changed by
a later ADR or reviewed implementation task.

This ADR does not supersede the no-cookies, no-telemetry, strict-origin CORS,
CSP, memory-only token, route-scoped supervisor-token, loopback, request-limit,
redaction, Windows 11 x64 support, local-first/no-cloud, SQLite migration and
DBML synchronization, or explicit-ADR supersession rules.
