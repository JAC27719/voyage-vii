# ADR-0011: Windows Scope and Native Lifecycle Recovery

- Status: Accepted
- Date: 2026-06-29

## Context

The initial feasibility work produced native Windows evidence and useful
non-native cross-build observations, but native macOS workers are unavailable
and the pinned libraries expose three lifecycle constraints: api.zig has no
public stop API, upstream pg.zig cannot bound a Windows TCP connect, and
TigerBeetle C `tb_client_deinit` may block synchronously. Continuing to require
four native platforms would block the current slice without improving its
Windows safety.

## Decision

Windows 11 x64 (`x86_64-pc-windows-msvc`) is the sole current build, runtime,
package, smoke, CI, documentation, and completion gate. Native macOS Intel,
macOS Apple Silicon, and Linux runs/packages are deferred. Cross-target
compilation and non-Windows stubs may be retained only as informational,
non-native, non-support evidence.

Cross-platform architecture remains mandatory. Core contracts, business logic,
and runtime orchestration cannot expose Windows-native types.
Process/filesystem/platform behavior stays behind explicit interfaces,
target-bearing manifests and the smoke launcher remain extensible, and
implementers avoid needless Windows coupling.

The exact api.zig pin remains unchanged. Graceful API shutdown means accepting
the supervisor shutdown route, quiescing requests, protecting and stopping
PostgreSQL, TigerBeetle, logs, and owned resources, and then exiting the API
process. The api.zig accept loop need not return; Windows closes its listener at
process exit. Tauri remains final containment owner and verifies no descendants.
FEAS-001 proves bounded application cleanup, process exit, and no descendants,
not library-loop return.

The pg.zig upstream baseline remains
`12e48fc57b78486e338e8707448d9a87597dd3ad`. One repository-owned compatibility
patch is authorized at `patches/pg.zig/windows-connect-timeout.patch`. Its only
scope is a cancellable five-second Windows TCP connect deadline: close the
socket on timeout, join or leave no background work, and preserve public
behavior otherwise. The build verifies the exact upstream base, applies the
patch deterministically, and records its SHA-256. Production may consume only
that upstream commit plus the exact FEAS-001 reviewer-approved patch hash
recorded in `DEPENDENCY-PINS.md`. Forks, substitute clients, and unrelated
edits are prohibited. FEAS-001 includes a controlled nonresponsive-destination
timeout test.

Official unmodified TigerBeetle C `tb_client_deinit` remains the production
call. Production runs it on a dedicated shutdown thread with a 10-second
watchdog. A normal return is joined. If it misses the watchdog, the API process
terminates immediately with mandatory exit code `7` (`native shutdown
timeout`); process exit is the cancellation boundary, so no background work
survives. During intentional desktop shutdown Tauri does not restart this exit
and continues containment/reaping. During normal operation it is terminal
restart-budget behavior. FEAS-002 measures real deinit under 10 seconds and
uses an injectable fake stalled-deinit child fixture whose parent verifies exit
`7`, no more than 12 seconds wall time, and no surviving process.
`native_shutdown_timeout` maps to HTTP `503` only if observable before exit.

Token boundaries, data preservation, database shutdown, redaction, and process
containment are unchanged and may not be weakened.

## Rejected alternatives

- Keeping unavailable native macOS/Linux evidence as a current blocker.
- Treating cross-build success as native execution or support.
- Exposing Windows-native types through core contracts or orchestration.
- Forking/replacing api.zig or pg.zig, or broadening the pg.zig patch.
- Modifying `tb_client_deinit`, detaching a stuck shutdown thread, or allowing
  background native work to outlive the API process.
- Weakening tokens, data safety, database shutdown, or final containment.

## Consequences

The current slice can proceed against a truthful Windows-only support claim.
The compatibility patch is narrow, hash-pinned, and independently reviewed.
API shutdown is bounded at the process boundary, and TigerBeetle's potentially
uninterruptible native call has a deterministic containment outcome.

Native macOS/Linux work returns through a future ADR/task wave and must produce
new native evidence. Existing feasibility reports remain historical truth;
their Ubuntu observations and non-Windows cross-builds do not confer support.

## Supersession

This record supersedes:

- ADR-0003's requirement that all four targets gate native-client feasibility
  and its blanket prohibition on any pg.zig patch;
- ADR-0006's rule that every timed-out operation itself cancels and releases
  resources, only for the documented `tb_client_deinit` process-exit boundary;
- ADR-0007's unpatched pg.zig provenance criterion, only for the exact
  reviewer-approved compatibility patch;
- ADR-0008's four-artifact current distribution and native-test gate;
- ADR-0009's restart handling, only for exit `7` during intentional shutdown;
- ADR-0010's all-four-target first-slice completion criterion.

Changing current platform scope, portability boundaries, api.zig shutdown
meaning, patch path/scope/base/hash policy, TigerBeetle watchdog/exit behavior,
or the preserved safety rules requires a new ADR explicitly superseding this
record.
