# PLATFORM-001 - Static Platform Gateway and Finance Registry Seam

**Implementer inference:** Low
**Prerequisites:** `AUDIT-001` integrated, ADR-0013 through ADR-0016 accepted
and integrated, and `docs/planning/platform-module-registry-proposal.md`
integrated.

## Frozen inputs

Use ADR-0013, ADR-0014, ADR-0015, ADR-0016,
`docs/planning/platform-module-boundary-slice.md`,
`docs/planning/platform-module-registry-proposal.md`,
`product/spec/PRD.md`, `modules/README.md`, and
`modules/finance/spec/PRD.md`.

Preserve the current desktop startup, runtime supervision, runtime snapshot,
log-opening command, token custody, Windows 11 x64 support claim, and finance
Zig adapter behavior. Do not infer manifest schemas, database schemas,
import/export formats, simulation behavior, CLI commands, MCP tools, or
finance product workflows beyond the frozen inputs.

## Objective

Add a buildable Rust/Tauri platform seam for gateway-facing module registration
without changing finance behavior. The seam must statically register finance,
reserve UI/CLI/MCP/internal caller shapes, validate the registry constraints
from the proposal, and leave the existing runtime/status workflow working.

## Owned paths

- `apps/desktop/src-tauri/src/platform/**`
- `apps/desktop/src-tauri/src/main.rs`, limited to declaring the platform
  module and invoking its self-test or static registration checks.

Stop and escalate if the task requires changes to manifests, lockfiles,
frontend files, packaged runtime layout, the finance Zig adapter, SQLite
migrations, DBML, task registry files, or any existing runtime supervisor
behavior outside the narrow `main.rs` hook.

## Procedure

1. Add a Rust `platform` module under `apps/desktop/src-tauri/src/platform/`.
2. Define gateway-facing value types for caller surface, caller identity,
   capability, operation availability, module lifecycle state, storage
   namespace declaration, specialty engine declaration, adapter declaration,
   report declaration, event declaration, and module registration.
3. Use only ADR-0014's capability vocabulary:
   `read`, `create`, `update`, `archive`, `search`, `import`, `export`,
   `simulate`, and `report`.
4. Add a static finance registration equivalent to the proposal:
   module id `finance`, adapter kind `zig-api`, adapter source root
   `modules/finance/adapters/zig-api/`, SQLite namespace `finance`, and
   finance-only TigerBeetle for ledger balances and transfers.
5. Mark finance product operations as `reserved` or `deferred` except for a
   compatibility `runtime_status` operation if needed to represent the current
   status slice.
6. Add validation that rejects duplicate module ids, unknown capabilities,
   operations that reference undeclared capabilities, module claims on
   platform namespaces, duplicate SQLite namespace owners, non-finance
   TigerBeetle ownership, adapter source roots outside the owning module path,
   and registry strings containing tokens, credentials, local absolute paths,
   private adapter URLs, or database connection strings.
7. Reserve caller surfaces `ui`, `cli`, `mcp`, and `internal` in type-level or
   testable registry/gateway scaffolding. Do not implement user-facing CLI or
   MCP commands.
8. Wire only the minimum `main.rs` hook needed for module compilation and
   static self-test registration. Preserve the existing Tauri command names,
   runtime snapshot behavior, open-logs behavior, and startup sequence.
9. Add focused Rust unit tests for every validation rule above and for the
   exact finance registration values.
10. Record a complete worker submission using the `WORKFLOW.md` placeholder
    revision convention.

## Acceptance evidence

- `rustup run 1.96.0 cargo fmt --check` passes from
  `apps/desktop/src-tauri`.
- `rustup run 1.96.0 cargo test --locked platform` passes from
  `apps/desktop/src-tauri`.
- Existing focused runtime tests still pass with
  `rustup run 1.96.0 cargo test --locked runtime`.
- A registry validation test proves finance is the only registered module,
  TigerBeetle is finance-only, platform namespaces cannot be claimed by
  finance, and adapter source roots remain under `modules/finance`.
- A redaction/safety test or source audit proves no registry value contains
  app tokens, supervisor tokens, credentials, local absolute user paths,
  database connection strings, or private adapter URLs.
- `git diff --check` passes for all owned changes.
- The complete changed-path set is limited to the owned paths.

## Reviewer focus

Reject any implementation that changes finance behavior, adds product finance
routes, adds CLI/MCP commands, exposes private adapter routes as public
contracts, weakens token custody, changes startup/supervisor behavior, touches
manifests or lockfiles, touches migrations or DBML, grants TigerBeetle to any
non-finance module, or allows module ownership of platform namespaces.
