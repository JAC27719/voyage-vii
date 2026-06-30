# FEAS-003 — Architecture Go/No-Go Gate

**Implementer inference:** Low  
**Prerequisites:** `FEAS-001` and `FEAS-002` approved.

## Frozen inputs

Use all pins from `DEPENDENCY-PINS.md`, deadlines from `TIMEOUTS.md`, and the exact source/acquisition rules from `PACKAGING.md`. No worker may select an alternate runtime supplier.

## Objective

Demonstrate api.zig, pg.zig, and the TigerBeetle C ABI coexist in one Zig executable and prove the prescribed PostgreSQL/TigerBeetle acquisition and native-build strategy on all required targets.

## Procedure

1. Reuse only approved spike outputs and exact pins.
2. Implement one temporary HTTP request that probes PostgreSQL and TigerBeetle.
3. Build for all target triples and run on every native target.
4. On every target, build PostgreSQL `18.4` from its official source tarball and verify the approved TigerBeetle `0.17.7` release asset or official-tag source build.
5. Record exact official URLs, immutable revisions/tags, download hashes, toolchains, native build commands, targets, output hashes, licenses, and architecture inspection. These are the only inputs DESKTOP-004 may consume.
6. Record memory/link/runtime conflicts and clean shutdown behavior.
7. Produce a factual `GO` or `NO-GO` report.
8. On any required-target or prescribed-provenance failure, stop. Do not select a fallback; request an ADR decision.

## Acceptance evidence

- Native response and shutdown output for four targets.
- Dependency and architecture inventory.
- Four-target PostgreSQL source-build and TigerBeetle release-or-source provenance matrix with exact commands, URLs, hashes, toolchains, outputs, and licenses.
- Explicit gate decision with links to raw evidence.
- `git diff --check` output.

## Reviewer focus

Independently validate the gate. Approval is permitted only when every target passes the approved architecture unchanged.
