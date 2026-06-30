# SEAM-001 — Predeclare API Adapter Build Seams

**Implementer inference:** Low  
**Prerequisites:** `API-001`, `FEAS-002`, and `FEAS-003` approved.

## Frozen inputs

Use the approved FEAS-002/FEAS-003 TigerBeetle C ABI inputs, API-001's Zig
package layout, and the delegated workflow rule that shared build and aggregate
test files have one active owner. Do not implement PostgreSQL migrations,
PostgreSQL adapter behavior, TigerBeetle adapter behavior, or runtime
supervision in this task.

## Objective

Create the shared build, package, and aggregate-test seams required by API-002
and API-003 so those low-inference tasks can stay inside their owned adapter
paths.

## Procedure

1. Add the `services/api/migrations` package path needed for authoritative SQL
   migrations, with only a placeholder file until API-002 adds real migrations.
2. Add build options for the approved TigerBeetle C client static library and
   include directory.
3. Wire the TigerBeetle include path, object file, libc, and required Windows
   system libraries only when both native inputs are supplied; reject a partial
   native input configuration.
4. Expose a build options module that lets later adapter code know whether the
   TigerBeetle native C client was supplied.
5. Add aggregate test registration stubs for PostgreSQL and TigerBeetle adapter
   tests without implementing adapter behavior.

## Acceptance evidence

- `zig build` and `zig build test` continue to pass without TigerBeetle native
  inputs.
- A partial TigerBeetle native input configuration fails during build
  configuration.
- Build wiring supports both executable and aggregate-test artifacts.
- `git diff --check` passes.

## Reviewer focus

Verify that the task only creates shared seams, preserves API-002/API-003
adapter ownership, rejects partial native configuration, does not consume
unapproved TigerBeetle suppliers, and leaves production behavior unchanged.
