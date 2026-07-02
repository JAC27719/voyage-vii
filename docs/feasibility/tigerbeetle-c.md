# FEAS-002 — TigerBeetle static C ABI feasibility

## Result

**PASS for the current Windows-only slice.**

On native Windows 11 x64, the isolated Zig `0.15.2` spike links directly to
the official TigerBeetle `0.17.7` static C client built with TigerBeetle's
required Zig `0.14.1`.

The spike uses the real C ABI functions `tb_client_init`, `tb_client_submit`,
and the official unmodified `tb_client_deinit`. It does not use the
TigerBeetle CLI as a client, a proxy, sidecar, shared library, or another
language binding.

ADR-0011 supersedes the earlier four-native-target gate. Native macOS and
Linux execution is deferred and is not part of this slice's support claim.
Non-Windows cross-build output, if retained, is informational only.

## Provenance

The official `0.17.7` release is
<https://github.com/tigerbeetle/tigerbeetle/releases/tag/0.17.7>. Its tag
resolves directly to commit
`4abc0229ae411fffd669a5a07f50fe3e20b88af0` and tree
`7e8dc721dcedd9b5f58bc5754090acbc0cd8d45e`.

The release assets contain the Windows server executable but no standalone
C-client archive. Therefore the `PACKAGING.md` fallback applies: build the
official tag with Zig `0.14.1`.

| Input | Official URL | SHA-256 |
| --- | --- | --- |
| TigerBeetle `0.17.7` source ZIP | <https://github.com/tigerbeetle/tigerbeetle/archive/refs/tags/0.17.7.zip> | `b343fa0e4501a063a47b893ec39f278133c93cb67c585dfe81b64ccee7186e9a` |
| Zig `0.14.1` Windows x64 | <https://ziglang.org/download/0.14.1/zig-x86_64-windows-0.14.1.zip> | `554f5378228923ffd558eac35e21af020c73789d87afeabf4bfd16f2e6feed2c` |
| Zig `0.15.2` Windows x64 | <https://ziglang.org/download/0.15.2/zig-x86_64-windows-0.15.2.zip> | `3a0ed1e8799a2f8ce2a6e6290a9ff22e6906f8227865911fb7ddedc3cc14cb0c` |
| TigerBeetle Windows x64 server | <https://github.com/tigerbeetle/tigerbeetle/releases/download/0.17.7/tigerbeetle-x86_64-windows.zip> | `ad1d8a77df5589f4181eb73abc560f5b17cdb9ac68b700093a9878fd46e448c7` |

The two Zig hashes match Zig's official release index. The server asset hash
matches the digest published by the official GitHub release. The extracted
server executable hash is
`fcb78aa4536e765e2cc15e6f2e222b17c00a325b87e497b1509471682e903a48`;
`tigerbeetle version` reported
`TigerBeetle version 0.17.7+4abc022`.

TigerBeetle is licensed under Apache-2.0. The license used for this evidence is
the tag's repository-root `LICENSE`, with SHA-256
`eb3d7b5485466acbd81f2b496f595ab637d2792e268206b27d99e793bdb67549`.

The generated `tb_client.h` hash is
`3ad1dd26fb67f3c89c971072cf22ad4a833971f6a40947ca562db2685587964d`.

## Static client build

The TigerBeetle-client toolchain reported exactly:

```text
0.14.1
```

From a detached checkout of the immutable official commit, the C client build
command was:

```powershell
zig build clients:c `
  '-Dgit-commit=4abc0229ae411fffd669a5a07f50fe3e20b88af0' `
  '-Dconfig-release=0.17.7' `
  '-Dconfig-release-client-min=0.16.4' `
  -Drelease
```

The explicit release values are required. A preliminary artifact built without
them identified itself as development release `65535.0.0`, and the real
`0.17.7` server correctly rejected it as `client_release_too_high`. That
preliminary artifact was discarded and is not used in any passing evidence.

The consumed Windows static archive is:

```text
C:\Users\jcane\AppData\Local\Temp\hydra-feas-002\tigerbeetle-git\src\clients\c\lib\x86_64-windows\tb_client.lib
```

Hash and size:

```text
sha256=1edf28ac840cc44ae98a8782d066da525df8257a6c90df921164d706ff232c02
length=810444
```

The generated client, server, data, cache, and executable artifacts remain
untracked under `%TEMP%\hydra-feas-002`.

## Zig 0.15.2 consumer build

The application toolchain reported exactly:

```text
0.15.2
```

The native Windows build command was:

```powershell
zig build `
  "-Dtb-client-lib=C:\Users\jcane\AppData\Local\Temp\hydra-feas-002\tigerbeetle-git\src\clients\c\lib\x86_64-windows\tb_client.lib" `
  "-Dtb-client-include=C:\Users\jcane\AppData\Local\Temp\hydra-feas-002\tigerbeetle-git\src\clients\c" `
  -Doptimize=ReleaseSafe `
  --prefix C:\Users\jcane\AppData\Local\Temp\hydra-feas-002\spike-out-v2
```

The resulting executable is:

```text
C:\Users\jcane\AppData\Local\Temp\hydra-feas-002\spike-out-v2\bin\tigerbeetle-c-spike.exe
sha256=d213db1690c063abb2857fd2cc1d517148dbb1b8abae0013f8316c514f27d67e
length=990208
```

## Windows x64 native runtime evidence

Host: Windows 11 x64. The evidence executable reported:

```text
native_target=x86_64-windows pointer_bits=64
```

The local server was prepared and started with:

```powershell
tigerbeetle.exe format --cluster=0 --replica=0 --replica-count=1 --development 0_0.tigerbeetle
tigerbeetle.exe start --addresses=127.0.0.1:3000 --development 0_0.tigerbeetle
```

The server log identified:

```text
release=0.17.7
release_client_min=0.16.4
git_commit=4abc0229ae411fffd669a5a07f50fe3e20b88af0
0: cluster=0: listening on 127.0.0.1:3000
```

The native lookup command and result were:

```powershell
tigerbeetle-c-spike.exe lookup 127.0.0.1:3000
```

```text
native_target=x86_64-windows pointer_bits=64
lookup=ok result_size=0 callbacks=1 elapsed_ms=973 deinit_ms=35 cleanup=ok
```

This is a real `TB_OPERATION_LOOKUP_ACCOUNTS` request for a nonexistent
account in a newly formatted cluster. An empty successful result is the
expected harmless lookup. The official `tb_client_deinit` call ran on the
dedicated shutdown thread and returned in 35 ms, below the frozen ten-second
watchdog.

The unavailable-server command and result were:

```powershell
tigerbeetle-c-spike.exe unavailable 127.0.0.1:30999
```

```text
native_target=x86_64-windows pointer_bits=64
unavailable=timeout timeout_ms=4995 callback_status=5 callbacks=1 deinit_ms=1406 cleanup=ok
```

The wait budget is exactly five seconds. On timeout, the spike deinitializes
the client to cancel the outstanding operation. Status `5` is
`TB_PACKET_CLIENT_SHUTDOWN`. The callback ran exactly once, its global context
matched the packet's user-data pointer, and official deinit returned on the
shutdown thread before the pinned packet and completion state left scope.

The explicit shutdown command and result were:

```powershell
tigerbeetle-c-spike.exe shutdown 127.0.0.1:30999
```

```text
native_target=x86_64-windows pointer_bits=64
shutdown=ok callback_status=5 callbacks=1 deinit_ms=70 cleanup=ok
```

Again, the official deinit returned on the shutdown thread below the frozen
ten-second watchdog and was joined before callback state left scope.

The full final native-run server output is under:

```text
C:\Users\jcane\AppData\Local\Temp\hydra-feas-002\native-evidence-watchdog-4815b31d31b44e469d00dc3c0d186cae
```

`server.stderr.log` contains the server provenance, startup, client
connection, and client disconnect lines. This location is ephemeral local
evidence, not a tracked runtime.

## Bounded stalled-deinit fixture

The production-equivalent rule is: call official unmodified
`tb_client_deinit` on a dedicated shutdown thread, join a normal return, and
if the call misses the ten-second watchdog, exit the process immediately with
code `7`. Process exit is the cancellation boundary.

The spike includes an injected fake stalled-deinit child mode. The parent mode
launches that child, waits for process termination, and verifies exit `7`, no
more than 12 seconds wall time, and no surviving child process. The real
TigerBeetle client is not modified for this fixture.

The parent command was run under an outer 20-second harness:

```powershell
tigerbeetle-c-spike.exe fake_stalled_parent
```

Result:

```text
native_target=x86_64-windows pointer_bits=64
native_target=x86_64-windows pointer_bits=64
native_shutdown_timeout watchdog_ms=10003 exit_code=7
fake_stalled_deinit=ok child_exit=7 wall_ms=10032 limit_ms=12000 no_surviving_process=true
```

The parent process exited `0` after proving the child exited `7` within the
ADR-0011 12-second observation limit and was reaped.

## Link inspection

Microsoft COFF/PE Dumper `14.39.33523.0` reported the static archive as
`machine (x64)` and listed `tb_client_init`, `tb_client_submit`, and
`tb_client_deinit` as archive members.

The consumer executable dependency table contains Windows system and C runtime
DLLs only:

```text
api-ms-win-crt-heap-l1-1-0.dll
api-ms-win-crt-private-l1-1-0.dll
api-ms-win-crt-runtime-l1-1-0.dll
api-ms-win-crt-stdio-l1-1-0.dll
api-ms-win-crt-string-l1-1-0.dll
KERNEL32.dll
ntdll.dll
WS2_32.dll
ADVAPI32.dll
api-ms-win-crt-environment-l1-1-0.dll
api-ms-win-crt-math-l1-1-0.dll
```

There is no `tb_client.dll` or other TigerBeetle dynamic dependency. This
proves the TigerBeetle client was linked as a static archive. It does not claim
that the Windows C runtime or operating-system libraries are statically linked.

## Native platform matrix

| Native target | Runtime status | Support status |
| --- | --- | --- |
| Windows 11 x64 (`x86_64-pc-windows-msvc`) | Pass | Current slice supported |
| macOS Intel (`x86_64-apple-darwin`) | Not run | Deferred by ADR-0011 |
| macOS Apple Silicon (`aarch64-apple-darwin`) | Not run | Deferred by ADR-0011 |
| Linux x64 (`x86_64-unknown-linux-gnu`) | Not run | Deferred by ADR-0011 |

No native macOS or Linux compatibility claim is made by this report.

## Checks and residual risks

- `zig fmt --check build.zig src/main.zig`: pass with Zig `0.15.2`.
- Windows native ReleaseSafe build: pass.
- Windows lookup against a real local TigerBeetle `0.17.7` server: pass.
- Unavailable-server five-second timeout, cancellation callback, and deinit
  cleanup: pass.
- Explicit shutdown cancellation callback and deinit cleanup: pass.
- Fake stalled-deinit parent/child process-boundary proof: pass.
- `git diff --check`: pass with empty output.
- Per-owned-file `git diff --no-index --check -- NUL <path>`: zero
  whitespace warnings for all four submitted paths.

Residual risks:

- This spike proves the static C ABI path and shutdown containment behavior; it
  is not production orchestration code.
- Future macOS and Linux support requires new native task evidence.
- The fake stalled-deinit fixture proves the process boundary for a controlled
  injected stall. Real production containment still depends on the supervisor
  honoring ADR-0011 and treating exit `7` as terminal during intentional
  shutdown.
