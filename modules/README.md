# Voyage VII Modules

Status: target module structure, not an accepted ADR.

Modules are first-party product domains owned in this repository. A module
contains its durable product context close to the implementation that will
eventually satisfy it. The app platform remains responsible for gateway,
permissions, audit metadata, module registration, adapter lifecycle, shared
database lifecycle, import/export orchestration, and simulation orchestration.

The initial module registration model is static and build-time. Dynamic module
installation is future-compatible but not promised by this document.

The holistic product direction is defined in
[Voyage VII Product Requirements](../product/spec/PRD.md).

## Required shape

Each module should use this structure:

```text
modules/<name>/
  AGENTS.md
  SKILL.md
  spec/
    PRD.md
  adapters/
    <stack-or-runtime>/
```

`spec/` holds durable product and domain requirements that are independent of
the implementation stack. `adapters/` holds stack-specific implementation work
after a reviewed ADR or task approves that adapter. A module may omit
`adapters/` until implementation begins.

`AGENTS.md` gives engineers and coding agents local rules for working in the
module. `SKILL.md` gives agent harnesses domain workflows and safe operating
patterns derived from the module PRD and contracts. These files are
operational guides; they do not override the PRD, accepted ADRs, or reviewed
contracts.

## Module contracts

Every module must eventually publish a tech-neutral manifest and schemas. The
contract must declare:

- identity and version;
- supported capabilities;
- permission scopes;
- public request and response shapes;
- events;
- import and export formats;
- simulation support;
- reports;
- storage namespace ownership;
- shared-engine requirements;
- specialty-engine requirements;
- adapter/runtime requirements.

The shared capability vocabulary is:

- read;
- create/write;
- update/edit;
- archive/delete;
- search;
- import;
- export;
- simulate;
- report.

Modules should prefer archive, close, or revoke behavior over irreversible
delete. If a module needs irreversible deletion, its PRD must justify the need
and require a stronger permission.

## Storage Boundaries

Modules should not assume they own private database files. The target model is
platform-managed shared databases with module-owned schemas or namespaces.
SQLite is expected to be the common local relational engine for most modules.
The platform owns cross-module schemas for users, module registry metadata,
grants, audit metadata, import/export manifests, and simulation run metadata.

Module schemas are still ownership boundaries. A module must not read or write
another module's schema namespace directly. Cross-module data access goes
through the platform gateway with scoped grants and audit metadata.

Specialty engines are opt-in and restricted. Finance may declare TigerBeetle
for ledger balances and transfers. Other modules may not use TigerBeetle or
any other specialty engine without a module PRD and reviewed ADR that justify
the dependency and define platform enforcement.

## Current modules

- [Finance](finance/spec/PRD.md): the first concrete module, preserving the
  deferred finance baseline and colocating the current Zig API implementation
  as the finance-owned `adapters/zig-api` adapter.
