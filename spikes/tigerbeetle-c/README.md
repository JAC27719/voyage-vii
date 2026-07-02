# TigerBeetle static C ABI spike

This spike links a Zig `0.15.2` executable directly to the official
TigerBeetle `0.17.7` static C client built with Zig `0.14.1`.

It has four native evidence scenarios:

- `lookup`: perform a harmless `lookup_accounts` against a real server.
- `unavailable`: enforce the frozen five-second request limit, then close the
  client and verify cancellation callback completion.
- `shutdown`: close a client with a request in flight and verify exactly one
  `TB_PACKET_CLIENT_SHUTDOWN` callback before stack state is released.
- `fake_stalled_parent`: launch an injected stalled-deinit child fixture and
  verify exit code `7`, at most 12 seconds wall time, and no surviving child
  process.

Every production-equivalent close uses the official unmodified
`tb_client_deinit` on a dedicated shutdown thread with the frozen ten-second
watchdog. A normal return is joined before callback and packet state leave
scope. If a deinit call misses the watchdog, the process exits with code `7`;
the fake stalled fixture proves that process boundary without modifying the
official TigerBeetle client.

The build intentionally requires explicit paths to the official header and
static library. It contains no download fallback, CLI invocation, proxy, or
alternate binding.

```text
zig build -Dtb-client-lib=<absolute-static-library-path> \
  -Dtb-client-include=<absolute-directory-containing-tb_client.h> \
  -Doptimize=ReleaseSafe
```

Run a scenario with:

```text
zig build run <same-build-options> -- lookup 127.0.0.1:3000
```

Run the injected process-boundary fixture with:

```text
zig build run <same-build-options> -- fake_stalled_parent
```

See `docs/feasibility/tigerbeetle-c.md` for the frozen acquisition commands,
hashes, native evidence, and platform limitations.
