# Finance Module Skill

Use this skill when working on Voyage VII finance-domain planning,
documentation, or future finance implementation tasks.

## Context

Finance is the first concrete Voyage VII module. It is a single-owner USD
personal finance domain with strict cash-basis double-entry accounting,
finance-owned SQLite schema metadata, finance-only TigerBeetle balances and
transfers, periods, budgets, reports, and isolated simulations.

The app platform owns gateway access, permissions, audit metadata, CLI/MCP/UI
surfaces, shared database lifecycle, adapter lifecycle, import/export
orchestration, and simulation sandbox orchestration. Finance owns finance
domain behavior and its schema namespace behind module contracts.

## Workflow

1. Read `modules/finance/spec/PRD.md`.
2. Read `product/spec/PRD.md` and `modules/README.md`.
3. Read repository `AGENTS.md`.
4. Read `docs/adr/README.md` before changing architecture-facing decisions.
5. If changing finance storage, confirm the task owns both executable
   migrations and implemented DBML updates.
6. Keep finance changes behind gateway/module contracts.
7. Verify that examples and logs contain no real names, amounts, tokens, raw
   records, or credentials.

## Safe operating defaults

- Prefer archive, close, reversal, and correction over irreversible delete.
- Treat import/export formats as versioned contracts.
- Treat simulations as read-only snapshots or fresh sandbox data.
- Treat SQLite as shared and platform-managed; finance owns a schema or
  namespace, not a private app database.
- Treat TigerBeetle as finance-only unless a future ADR grants another module
  access.
- Treat `modules/finance/adapters/zig-api/` as the current finance-owned Zig
  adapter location while accepted ADRs remain authoritative until superseded.
