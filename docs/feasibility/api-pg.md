# FEAS-001 — api.zig and pg.zig Compatibility

## Result

**Windows 11 x64 feasibility proven under ADR-0011.** The pinned `api.zig`
revision and the pinned `pg.zig` `zig-0.15` upstream baseline plus the one
authorized repository patch compile with Zig `0.15.2`, run the deterministic
endpoint on native Windows x64, execute `SELECT 1` through pg.zig, bound a
controlled nonresponsive TCP connect at the five-second deadline, and exit at
the supervisor process boundary with no surviving descendants.

Native macOS Intel, macOS Apple Silicon, and Linux runtime support remains
deferred by ADR-0011. Cross-builds are retained only as informational
non-native structural evidence.

No dependency was forked or substituted.

## Frozen inputs and provenance

| Input | Exact source | SHA-256 / resolution |
| --- | --- | --- |
| Zig 0.15.2 Windows x64 | `https://ziglang.org/download/0.15.2/zig-x86_64-windows-0.15.2.zip` | `3a0ed1e8799a2f8ce2a6e6290a9ff22e6906f8227865911fb7ddedc3cc14cb0c`; matches the official Zig release index |
| api.zig | `https://github.com/muhammad-fiaz/api.zig/archive/f9a287916ad0e34fda71c8e5b619c5774c8fbb45.tar.gz` | commit API resolved the requested full SHA unchanged; downloaded archive `2471893730b213439878eb5fde36a75337fdf553ef9f883e0a8e91ceb39e1445` |
| pg.zig upstream baseline | `https://github.com/karlseguin/pg.zig/archive/12e48fc57b78486e338e8707448d9a87597dd3ad.tar.gz` | commit API resolved the requested full SHA unchanged; downloaded archive `2ee37e9b164731ef958732aea5a0a620d23b162fd831d7bda966f4043ecd71ad` |
| pg.zig Windows connect-timeout patch | `patches/pg.zig/windows-connect-timeout.patch` | `02d6791ab6bdb147c34972e0076992840be7e5fea2e51e6cdac94455033c578c` |
| PostgreSQL 18.4 | `https://ftp.postgresql.org/pub/source/v18.4/postgresql-18.4.tar.bz2` | `81a81ec695fb0c7901407defaa1d2f7973617154cf27ba74e3a7ab8e64436094`; matches the adjacent official `.sha256` file |

`build.zig.zon` uses immutable full-commit URLs and Zig content hashes. The
spike build copies the exact pg.zig package, verifies upstream
`src/stream.zig` SHA-256
`91d1ab1b4ed1a456b1bd9f5d9b68ff327eca036ecc6db4dddf8889af21e28abe`, applies
only `patches/pg.zig/windows-connect-timeout.patch`, and imports that patched
module. The patch only changes Windows TCP connect behavior: it uses a
nonblocking socket, polls for 5,000 ms, closes on timeout through the existing
error cleanup path, restores blocking mode after success, and creates no
background thread or detached work.

PostgreSQL was compiled without source changes from the verified official
tarball in an Ubuntu 24.04 x64 multi-stage Docker build:

```text
./configure --prefix=/opt/postgresql \
  --without-icu --without-readline --without-zlib
make -j"$(nproc)" world-bin
make install-world-bin
```

Runtime identity:

```text
postgres (PostgreSQL) 18.4
docker image sha256:e8feca503b3288d6f9913431b19cfb4ede68db855d14a410760cb05f67d43543
```

The FEAS-001 Windows proof exercises the native Windows client process against
this source-built PostgreSQL 18.4 server. It is not a Windows-native
PostgreSQL packaging claim; that belongs to later packaging/runtime tasks.

## Build evidence

Evidence was regenerated from `spikes/api-pg` with
`ZIG_GLOBAL_CACHE_DIR=cache/global` and `ZIG_LOCAL_CACHE_DIR=cache/local`.
Full command logs are generated under ignored `spikes/api-pg/evidence/`.

```text
zig version
0.15.2

zig build --fetch
exit=0

zig build -Dtarget=x86_64-windows-msvc --prefix zig-out/x86_64-windows-msvc
exit=0
zig build -Dtarget=x86_64-macos --prefix zig-out/x86_64-macos
exit=0
zig build -Dtarget=aarch64-macos --prefix zig-out/aarch64-macos
exit=0
zig build -Dtarget=x86_64-linux-gnu --prefix zig-out/x86_64-linux-gnu
exit=0

zig build --prefix zig-out/native
exit=0
```

The non-Windows targets above are cross-builds only and do not imply runtime
support. `scripts/inspect-binaries.ps1` parsed each executable header:

| Target | Build status | Header inspection | SHA-256 |
| --- | --- | --- | --- |
| `x86_64-pc-windows-msvc` | PASS | PE32+, x86_64 | `32d1e8b8d1ec63a002bd4e3683d293950ab340d63923d6cae1636cf756a5c27e` |
| `x86_64-apple-darwin` | informational cross-build PASS | Mach-O 64, x86_64 | `dbc9745af58caaba238ea3ad70e662ce55b5c398cf642d610ffb4704f5240610` |
| `aarch64-apple-darwin` | informational cross-build PASS | Mach-O 64, aarch64 | `97062379b2ced0966c11e3b9c6909f6e87be36c4cce77ae62fba422559a51440` |
| `x86_64-unknown-linux-gnu` | informational cross-build PASS | ELF64, x86_64 | `18419a59753cec2f7fb6a3218a5eb6721bb81f9e41e4c4f364f0dd19cd37e376` |

## Native Windows endpoint and shutdown evidence

The endpoint response is deterministic:

```json
{"dependency":"api.zig","status":"ok"}
```

Windows x64 evidence from `scripts/run-evidence.ps1`:

```text
status_code=200
content_type=application/json
body={"dependency":"api.zig","status":"ok"}

server_process_id=8672
shutdown_status=200
shutdown_body={"shutdown":"accepted"}
children_before_stop=36484
server_running_after_stop=False
children_after_stop=
```

The pinned api.zig accept loop still has no public library-level stop API.
Under ADR-0011, the proof boundary is the process route: the Windows process
accepts `/shutdown`, exits within the evidence timeout, and leaves no surviving
descendant process. The api.zig accept loop need not return.

## Native Windows pg.zig evidence

The spike uses `pg.Conn.openAndAuth`, TLS disabled for the loopback feasibility
probe, `rowOpts("SELECT 1", ...)` with a 3,000 ms query timeout, and deferred
`Conn.deinit`. Passwords are read from `PGPASSWORD`, zeroed before release, and
never printed.

Successful probe:

```text
pg_probe=passed value=1
pg_cleanup=complete
exit=0
```

Unavailable server:

```text
pg_probe=failed category=server_unavailable error=ConnectionRefused
spike_exit=failed error=ConnectionRefused
exit=1
```

Authentication failure:

```text
pg_probe=failed category=authentication_failed error=PG
spike_exit=failed error=PG
exit=1
```

Controlled nonresponsive destination against `10.255.255.1:5432`, repeated:

```text
pg_probe=failed category=server_unavailable error=ConnectionTimedOut
spike_exit=failed error=ConnectionTimedOut
elapsed_ms=5063
exit=1

pg_probe=failed category=server_unavailable error=ConnectionTimedOut
spike_exit=failed error=ConnectionTimedOut
elapsed_ms=5040
exit=1
```

The timeout path is synchronous. It creates no helper thread, closes the socket
through the existing error cleanup path, and returns a sanitized stable error.

PostgreSQL cleanup:

```text
scripts/stop-postgresql.ps1
exit=0
```

The stop script uses `docker stop --timeout 10`, removes the FEAS-owned
container, and removes the FEAS-owned data volume.

## Reproduction

From `spikes/api-pg`, with the official PostgreSQL archive at
`downloads/postgresql-18.4.tar.bz2` and the exact Zig executable supplied:

```powershell
./scripts/start-postgresql.ps1
$env:PGPASSWORD = [IO.File]::ReadAllText(
  (Resolve-Path runtime/pg-password.txt)
)
./scripts/run-evidence.ps1 -Zig <absolute-path-to-zig-0.15.2>
./scripts/inspect-binaries.ps1
./scripts/stop-postgresql.ps1
Remove-Item Env:PGPASSWORD
git diff --check -- spikes/api-pg docs/feasibility/api-pg.md patches/pg.zig/windows-connect-timeout.patch
```

Generated downloads, dependency trees, toolchains, caches, binaries, database
data, and logs are intentionally ignored.

## Limitations and risks

1. Native macOS Intel, macOS Apple Silicon, and Linux runtime support is
   explicitly deferred by ADR-0011.
2. The PostgreSQL server used for FEAS-001 was source-built in Docker on
   Ubuntu 24.04 x64. This proves Windows native client compatibility with
   PostgreSQL 18.4, not Windows-native PostgreSQL packaging.
3. The controlled nonresponsive destination uses `10.255.255.1:5432`; reviewers
   should rerun it on Windows and confirm the same five-second timeout window
   in their network environment.
4. TLS was intentionally disabled for this loopback feasibility probe; no TLS
   compatibility claim is made.
