# Finance Module Agent Guidance

This file gives operational guidance for agents working in the finance module.
It does not override repository `AGENTS.md`, accepted ADRs, reviewed task
packets, or the finance PRD.

## Boundaries

- Treat `modules/finance/spec/PRD.md` as the local product source for finance
  intent.
- Treat `product/spec/PRD.md` and `modules/README.md` as the target app and
  module-structure context for finance.
- Treat accepted ADRs and current v2 planning records as authoritative until a
  reviewed ADR explicitly supersedes them.
- Treat `modules/finance/adapters/zig-api/` as the current finance-owned Zig
  adapter location.
- Do not move or reframe the Zig adapter again without a reviewed task that
  owns the affected paths.
- Do not add SQLite migrations without updating the implemented DBML in the
  same reviewed task.
- Do not let UI, CLI, MCP, or agents bypass the app gateway to call private
  finance APIs, finance schema objects, or finance specialty storage directly.

## Domain rules

- Preserve strict cash-basis double-entry accounting.
- Keep account class immutable after creation.
- Prefer archive, close, reversal, or correction workflows over destructive
  deletion.
- Keep TigerBeetle balances and transfers separate from SQLite metadata unless
  a future reviewed task changes that model.
- Treat SQLite as a platform-managed shared database in the target model, with
  finance owning only its schema or namespace.
- Treat TigerBeetle as a finance-only specialty engine unless a future ADR
  grants another module access.
- Keep finance simulations isolated from real finance data.

## Documentation rules

- Keep product requirements in `spec/`.
- Keep stack-specific implementation notes under the relevant `adapters/`
  path.
- Mark proposed schemas as proposals until executable migrations and DBML are
  reviewed together.
- Never include credentials, local user data, account names, amounts, tokens,
  or raw private records in docs, logs, fixtures, or examples.
