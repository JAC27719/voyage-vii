# FEAS-002 — Prove TigerBeetle Static C ABI Compatibility

**Implementer inference:** Low  
**Prerequisites:** `RESET-001` approved.

## Frozen inputs

Use `DEPENDENCY-PINS.md`, `TIMEOUTS.md`, and the TigerBeetle acquisition fallback in `PACKAGING.md` exactly. Use an official `0.17.7` release asset when present for the target; otherwise build the official `0.17.7` tag with Zig `0.14.1`. Do not select another supplier.

## Objective

Prove TigerBeetle `0.17.7` can be reached through its C ABI from a Zig `0.15.2` executable on every target.

## Procedure

1. Obtain or build the official client using TigerBeetle's required Zig `0.14.1`.
2. Record source, revision, build command, target, hash, and license.
3. Link the client statically into the isolated Zig spike.
4. Connect to a real local TigerBeetle server and perform a harmless lookup.
5. Exercise unavailable server, timeout, client shutdown, and callback completion.
6. Build and run natively for Windows x64, macOS x64/arm64, and Linux x64.
7. Do not substitute the TigerBeetle CLI, a sidecar proxy, or another language binding.

## Acceptance evidence

- Client provenance and hashes.
- Link maps or dependency inspection.
- Native lookup results and target architecture output.
- Callback-lifetime and cleanup evidence.
- Exact source URL/tag/hash, `zig version`, build command, native lookup command, five-second timeout evidence, and `git diff --check` output.

## Reviewer focus

Reproduce the lookup, inspect static/native linking, and reject unsupported ABI assumptions or hidden CLI invocation.
