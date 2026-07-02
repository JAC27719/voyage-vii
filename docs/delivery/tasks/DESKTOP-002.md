# DESKTOP-002 — Tauri Process Supervisor

**Implementer inference:** Low  
**Prerequisites:** `DESKTOP-001`, `RUNTIME-004`, and `DESKTOP-004` approved.

## Frozen inputs

Use the DESKTOP-001 predeclared runtime seam, `DEPENDENCY-PINS.md`, `CONTRACTS.md`, `TIMEOUTS.md`, and `PACKAGING.md`. Replace only `src-tauri/src/runtime/**`, the existing runtime hook points in `src-tauri/src/main.rs`, owned runtime tests, and fake fixtures. The `main.rs` edit is limited to installing the runtime supervisor state, starting it from setup, serving `get_runtime_snapshot` from that state, and preserving the already-declared command names. Stop if any manifest, lockfile, shared configuration, capability/permission file, or static test registration must change.

## Objective

Supervise the packaged Zig API, protect both tokens, and contain the complete child process tree.

## Procedure

1. Implement one `RuntimeSupervisor` state machine; UI commands read snapshots and never manipulate children directly.
2. Resolve packaged runtime resources internally. Allow override only in development/smoke mode.
3. Remove inherited `VOYAGE_VII_*` variables and pass explicit approved CLI arguments.
4. Spawn with piped stdout/stderr and no interactive stdin in a Windows Job
   Object. Keep containment behind a platform interface without exposing
   Windows-native types to the supervisor state machine.
5. Parse only the prefixed handshake within 15 seconds and 16 KiB and suppress it from logs.
6. Validate every handshake field before publishing the connection.
7. Keep both tokens in Rust memory and expose only the app token.
8. Increment generation for every replacement connection and emit credential-free change events.
9. Enforce three restarts in a rolling five minutes.
10. Implement the exact 20-second graceful, five-second terminate, force-kill, and reap shutdown sequence.
11. During intentional shutdown, do not restart API exit `7`; continue final
    Job Object containment, reap, and verify no descendants. During normal
    operation, apply terminal/restart-budget behavior.
12. Use a fake API fixture for valid, delayed, malformed, duplicate, missing,
    crash, grandchild, exit-7, and shutdown scenarios.

## Acceptance evidence

- State-transition table and deterministic restart tests.
- Token scan over logs, events, panic output, and files.
- Graceful, forced, and exit-7 process-tree cleanup on native Windows 11 x64.
- Concurrent close/restart race tests.
- `cargo fmt --check`, `cargo clippy --all-targets --all-features -- -D warnings`, `cargo test --all-targets`, and `git diff --check` pass without manifest, capability, permission, shared-configuration, or static-registration changes.

## Reviewer focus

Audit token custody, bounded parsing, single launch path, exit-7 restart
semantics, reader/handle cleanup, and Windows Job Object containment.
