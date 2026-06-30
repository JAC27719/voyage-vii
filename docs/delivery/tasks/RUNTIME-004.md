# RUNTIME-004 — Integrated Managed Runtime Supervisor

**Implementer inference:** Low  
**Prerequisites:** `API-004`, `RUNTIME-002`, and `RUNTIME-003` approved.

## Frozen inputs

Use status/handshake/manifest/error contracts from `CONTRACTS.md`, every lifecycle deadline from `TIMEOUTS.md`, and only API-001's predeclared supervisor seam. Stop if shared build, dependency, entrypoint, or aggregate-test files must change.

## Objective

Coordinate both managed databases and publish truthful API lifecycle state.

## Procedure

1. Acquire the root lock and validate assets before mutation.
2. Start PostgreSQL and TigerBeetle concurrently where safe.
3. Complete PostgreSQL migrations and both production adapter probes.
4. Preserve the already emitted post-bind handshake and reach full database readiness within 60 seconds without conflating the two deadlines.
5. Maintain independent component states and attempts.
6. Retry only the requested failed component and suppress concurrent duplicate retry.
7. Coordinate API shutdown by quiescing requests, stopping/protecting both
   databases, logs, and owned resources, then exiting the API process. The
   api.zig accept loop need not return.
8. Treat exit `7` as terminal/restart-budget behavior during normal operation;
   expose `native_shutdown_timeout` only if observable before exit.
9. Measure idle memory and record any breach of the approximate 500 MiB target.

## Acceptance evidence

- Fresh and retained startup timing.
- One-component and two-component failure/recovery matrices.
- Shutdown during initialization, probe, retry, and healthy operation.
- Windows process-tree-empty and memory measurements, including exit-7
  containment.
- `zig build test` through the static aggregate registration and `git diff --check`.

## Reviewer focus

Verify transition accuracy, no healthy-component disruption, bounded retries, root-lock lifetime, and complete process cleanup.
