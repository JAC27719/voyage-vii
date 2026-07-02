# FEAS-003 — Architecture Go/No-Go Gate

**Implementer inference:** Low  
**Prerequisites:** `FEAS-001` and `FEAS-002` approved.

## Frozen inputs

Use all pins from `DEPENDENCY-PINS.md`, deadlines from `TIMEOUTS.md`, and the exact source/acquisition rules from `PACKAGING.md`. No worker may select an alternate runtime supplier.

## Objective

Demonstrate api.zig, the approved pg.zig baseline/patch, and the TigerBeetle C
ABI coexist in one Zig executable and prove the prescribed
PostgreSQL/TigerBeetle acquisition and native-build strategy on Windows 11 x64.

## Procedure

1. Reuse only approved spike outputs and exact pins.
2. Implement one temporary HTTP request that probes PostgreSQL and TigerBeetle.
3. Build and run natively on Windows 11 x64. Optional cross-builds are
   non-gating structural evidence labeled non-native/non-support.
4. On Windows x64, build PostgreSQL `18.4` from its official source tarball and
   verify the approved TigerBeetle `0.17.7` release asset or official-tag
   source build.
5. Record exact official URLs, immutable revisions/tags, download hashes, toolchains, native build commands, targets, output hashes, licenses, and architecture inspection. These are the only inputs DESKTOP-004 may consume.
6. Record memory/link/runtime conflicts and clean shutdown behavior.
7. Produce a factual `GO` or `NO-GO` report.
8. On any Windows gate or prescribed-provenance failure, stop. Do not select a
   fallback; request an ADR decision.

## Acceptance evidence

- Native Windows response and shutdown output.
- Dependency and architecture inventory.
- Windows PostgreSQL source-build and TigerBeetle release-or-source provenance
  matrix with exact commands, URLs, hashes, toolchains, outputs, and licenses.
- Explicit gate decision with links to raw evidence.
- `git diff --check` output.

## Reviewer focus

Independently validate the Windows gate. Non-Windows observations never confer
support or block approval.
