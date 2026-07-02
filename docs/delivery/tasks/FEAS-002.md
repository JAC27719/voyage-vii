# FEAS-002 — Prove TigerBeetle Static C ABI Compatibility

**Implementer inference:** Low  
**Prerequisites:** `RESET-001` and `PLAN-001` approved.

## Frozen inputs

Use `DEPENDENCY-PINS.md`, `TIMEOUTS.md`, ADR-0011, and the Windows
TigerBeetle acquisition fallback in `PACKAGING.md` exactly. Use the official
Windows `0.17.7` release asset when present; otherwise build the official
`0.17.7` tag with Zig `0.14.1`. Do not select another supplier.

## Objective

Prove TigerBeetle `0.17.7` can be reached through its C ABI from a Zig `0.15.2`
executable natively on Windows 11 x64, including the bounded process-exit
shutdown contract.

## Procedure

1. Obtain or build the official client using TigerBeetle's required Zig `0.14.1`.
2. Record source, revision, build command, target, hash, and license.
3. Link the client statically into the isolated Zig spike.
4. Connect to a real local TigerBeetle server and perform a harmless lookup.
5. Exercise unavailable server, timeout, client shutdown, and callback completion.
6. Measure real official `tb_client_deinit` completion and prove it returns in
   less than ten seconds on native Windows 11 x64.
7. Add an injectable fake stalled-deinit child fixture. Its parent must verify
   exit code `7`, at most 12 seconds wall time, and no surviving process.
8. Keep official `tb_client_deinit` unmodified and run production-equivalent
   deinit on a dedicated shutdown thread with a ten-second watchdog.
9. Optional non-Windows cross-compilation is informational only and must be
   labeled non-native and unsupported.
10. Do not substitute the TigerBeetle CLI, a sidecar proxy, or another language binding.

## Acceptance evidence

- Client provenance and hashes.
- Link maps or dependency inspection.
- Native Windows lookup results and target architecture output.
- Callback-lifetime, real deinit-under-ten-seconds, and cleanup evidence.
- Fake stalled-deinit parent evidence for exit `7`, wall time no more than 12
  seconds, and no surviving process.
- Optional cross-target output labeled non-native/non-support.
- Exact source URL/tag/hash, `zig version`, build command, native lookup command, five-second timeout evidence, and `git diff --check` output.

## Reviewer focus

Reproduce the Windows lookup and both deinit paths, inspect static/native
linking and process containment, and reject unsupported ABI assumptions,
detached shutdown work, or hidden CLI invocation.
