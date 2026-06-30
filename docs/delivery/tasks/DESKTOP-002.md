# DESKTOP-002 — Tauri Process Supervisor

**Implementer inference:** Low  
**Prerequisites:** `DESKTOP-001`, `RUNTIME-004`, and `DESKTOP-004` approved.

## Frozen inputs

Use the DESKTOP-001 predeclared runtime seam, `DEPENDENCY-PINS.md`, `CONTRACTS.md`, `TIMEOUTS.md`, and `PACKAGING.md`. Replace only `src-tauri/src/runtime/**`, its owned tests, and fake fixtures. Stop if any manifest, lockfile, shared configuration, main entrypoint, or static test registration must change.

## Objective

Supervise the packaged Zig API, protect both tokens, and contain the complete child process tree.

## Procedure

1. Implement one `RuntimeSupervisor` state machine; UI commands read snapshots and never manipulate children directly.
2. Resolve packaged runtime resources internally. Allow override only in development/smoke mode.
3. Remove inherited `VOYAGE_VII_*` variables and pass explicit approved CLI arguments.
4. Spawn with piped stdout/stderr and no interactive stdin in a Windows Job Object or Unix process group.
5. Parse only the prefixed handshake within 15 seconds and 16 KiB and suppress it from logs.
6. Validate every handshake field before publishing the connection.
7. Keep both tokens in Rust memory and expose only the app token.
8. Increment generation for every replacement connection and emit credential-free change events.
9. Enforce three restarts in a rolling five minutes.
10. Implement the exact 20-second graceful, five-second terminate, force-kill, and reap shutdown sequence.
11. Use a fake API fixture for valid, delayed, malformed, duplicate, missing, crash, grandchild, and shutdown scenarios.

## Acceptance evidence

- State-transition table and deterministic restart tests.
- Token scan over logs, events, panic output, and files.
- Graceful and forced process-tree cleanup on every native platform.
- Concurrent close/restart race tests.
- `cargo fmt --check`, `cargo clippy --all-targets --all-features -- -D warnings`, `cargo test --all-targets`, and `git diff --check` pass without manifest or shared-entrypoint changes.

## Reviewer focus

Audit token custody, bounded parsing, single launch path, restart budget, reader/handle cleanup, and native process containment.
