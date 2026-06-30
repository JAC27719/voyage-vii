# FEAS-003 — Architecture Go/No-Go Decision

## Decision

**GO for the Windows 11 x64 production implementation wave.**

The Windows 11 x64 integration evidence now proves the required chain:

```text
official PostgreSQL 18.4 source tarball
  -> native Windows x64 PostgreSQL runtime built from source
  -> packaged desktop runtime layout
  -> first-party Windows x64 executable probe
```

The same executable also links the approved `api.zig`, patched `pg.zig`, and
official TigerBeetle static C client in one Zig `0.15.2` process. A live HTTP
request successfully probed the packaged native PostgreSQL runtime and the
official TigerBeetle Windows server from the same process.

No alternate PostgreSQL supplier, unofficial binary distribution, Docker
runtime fallback, fork, proxy, or client binding is selected.

## Scope and prerequisites

Inputs were limited to the approved FEAS-001 and FEAS-002 outputs:

- `api.zig` commit `f9a287916ad0e34fda71c8e5b619c5774c8fbb45`.
- `pg.zig` upstream baseline
  `12e48fc57b78486e338e8707448d9a87597dd3ad`.
- Approved pg.zig Windows connect-timeout patch
  `02d6791ab6bdb147c34972e0076992840be7e5fea2e51e6cdac94455033c578c`.
- TigerBeetle `0.17.7` official tag
  `4abc0229ae411fffd669a5a07f50fe3e20b88af0`.
- Official unmodified TigerBeetle C client static archive built from that tag
  with Zig `0.14.1`.
- PostgreSQL `18.4` official source tarball
  `https://ftp.postgresql.org/pub/source/v18.4/postgresql-18.4.tar.bz2`.

## PostgreSQL Windows x64 runtime evidence

PostgreSQL was built from the official source tarball with the native MSVC
Windows toolchain and installed into an ignored runtime output:

```text
source_tarball_sha256=81a81ec695fb0c7901407defaa1d2f7973617154cf27ba74e3a7ab8e64436094
source_path=spikes/integration/runtime/postgresql-src
build_path=spikes/integration/runtime/postgresql-build
install_path=spikes/integration/runtime/postgresql-windows-x64
packaged_runtime_path=spikes/integration/runtime/desktop-runtime/resources/runtime
package_file_count=1929
```

Build toolchain:

```text
PostgreSQL version=18.4
host system=windows x86_64
build system=windows x86_64
C compiler=msvc 19.39.33523
linker=link
Meson=1.11.1
Ninja=1.13.0
WinFlexBison package sha256=8d324b62be33604b2c45ad1dd34ab93d722534448f55a16ca7292de32b6ac135
win_bison=3.8.2
win_flex=2.6.4
```

Recorded Meson options:

```text
--buildtype release
-Ddocs=disabled
-Dtap_tests=disabled
-Dssl=none
-Dgssapi=disabled
-Dicu=disabled
-Dldap=disabled
-Dplperl=disabled
-Dplpython=disabled
-Dpltcl=disabled
-Dreadline=disabled
-Dzlib=disabled
-Dlz4=disabled
-Dzstd=disabled
-Dnls=disabled
-Duuid=none
```

Packaged runtime architecture and hashes:

| Packaged file | SHA-256 | PE machine |
| --- | --- | --- |
| `postgresql/bin/postgres.exe` | `570050daddb78285c234cda0002df1df6f4a647e6a7092d271be0512c74e7aac` | `0x8664` |
| `postgresql/bin/initdb.exe` | `caf28ce8a546c42a217f75604ae93569f10967e8011cdd058e3acd0da4d7e666` | `0x8664` |
| `postgresql/bin/pg_ctl.exe` | `1672ae39e33b8e129eb68aac8b71e128f581650c46a2eaef13bf88dae01ca549` | `0x8664` |
| `postgresql/bin/psql.exe` | `e8a8ef2768d2a8021c26d189abd5aaeb6111894fd126e7179deb5ae2df33cfea` | `0x8664` |
| `postgresql/bin/libpq.dll` | `5ac39fa0f74878c1e5f86da5422e1e3916360c1c526ef669ac947de1edf6d8ae` | `0x8664` |
| `licenses/postgresql/COPYRIGHT` | `3d6af92ff8a4c2cdf69afb1cf44edea727922f5cd0cf8b5f72b11cdecac8fdfd` | n/a |

Packaged runtime commands that passed:

```text
postgres (PostgreSQL) 18.4
initdb (PostgreSQL) 18.4
pg_ctl (PostgreSQL) 18.4
psql (PostgreSQL) 18.4
```

The desktop-compatible lifecycle proof starts `postgres.exe` directly from the
packaged runtime and has the first-party supervisor own shutdown. On this Codex
host, `pg_ctl start` attempts PostgreSQL's Windows restricted-token restart path
and reports `error code 87`; direct `postgres.exe` launch from the packaged
runtime starts successfully and accepts local SQL connections.

## Integration executable evidence

The tracked integration spike lives under `spikes/integration/`. Generated
downloads, caches, runtime data, logs, toolchains, and binaries are ignored.

Build command:

```powershell
zig build `
  -Dtb-client-lib=C:\Users\jcane\AppData\Local\Temp\hydra-feas-002\tigerbeetle-git\src\clients\c\lib\x86_64-windows\tb_client.lib `
  -Dtb-client-include=C:\Users\jcane\AppData\Local\Temp\hydra-feas-002\tigerbeetle-git\src\clients\c `
  -Doptimize=ReleaseSafe `
  --prefix zig-out/native
```

Native Windows x64 build result from the full packaged-runtime evidence run:

```text
zig version=0.15.2
build_fetch_exit=0
build_native_exit=0
integration_exe_sha256=f87e266d1877c9831dd6972cc7a7bef3211d0496fbe123c18ffef478a7e1e429
integration_exe_pe_machine=0x8664
```

The one temporary HTTP request was:

```text
GET http://127.0.0.1:18086/probe
```

Response:

```text
status_code=200
content_type=application/json
body={"status":"ok","postgres":"ok","tigerbeetle":"ok"}
```

The process stderr for that request recorded both native probes:

```text
pg_probe=passed value=1
pg_cleanup=complete
tb_lookup=passed result_size=0 callbacks=1 elapsed_ms=1012 deinit_ms=60
integration_probe=passed pg_value=1 tb_result_size=0 tb_callbacks=1 tb_deinit_ms=60
```

Shutdown evidence:

```text
server_process_id=52556
shutdown_status=200
shutdown_body={"shutdown":"accepted"}
children_before_stop=26440
server_running_after_stop=False
children_after_stop=
```

Reviewable raw evidence is preserved in
[`spikes/integration/evidence/windows-native-evidence.md`](../../spikes/integration/evidence/windows-native-evidence.md).
That staged file records the sanitized command transcripts, hashes, endpoint
responses, shutdown output, and native runtime logs used for this decision.
The original `.log` files are generated and intentionally ignored.

## Dependency and architecture inventory

| Component | Source / build input | Evidence hash / architecture |
| --- | --- | --- |
| Zig application toolchain | `spikes/api-pg/toolchain/zig-x86_64-windows-0.15.2/zig.exe` | `d408dd38eed3e5204af841bcebf70502a4dbbb8399a3a3262be55059370bc018`; version `0.15.2` |
| pg.zig patch | `patches/pg.zig/windows-connect-timeout.patch` | `02d6791ab6bdb147c34972e0076992840be7e5fea2e51e6cdac94455033c578c` |
| PostgreSQL source | Official PostgreSQL `18.4` source tarball | `81a81ec695fb0c7901407defaa1d2f7973617154cf27ba74e3a7ab8e64436094` |
| PostgreSQL packaged runtime | Native Windows x64 build from official source, packaged under `resources/runtime/postgresql` | `postgres.exe` hash `570050daddb78285c234cda0002df1df6f4a647e6a7092d271be0512c74e7aac`; PE machine `0x8664` |
| TigerBeetle server | official Windows x64 release asset extracted executable | `fcb78aa4536e765e2cc15e6f2e222b17c00a325b87e497b1509471682e903a48`; PE machine `0x8664` |
| TigerBeetle C header | official tag generated `src/clients/c/tb_client.h` | `3ad1dd26fb67f3c89c971072cf22ad4a833971f6a40947ca562db2685587964d` |
| TigerBeetle C static client | official tag build output `tb_client.lib` | `1edf28ac840cc44ae98a8782d066da525df8257a6c90df921164d706ff232c02`; COFF archive with `tb_client_init`, `tb_client_submit`, `tb_client_deinit`; AMD64 markers present |
| Integration executable | first-party FEAS-003 build output | `f87e266d1877c9831dd6972cc7a7bef3211d0496fbe123c18ffef478a7e1e429`; PE machine `0x8664` |

TigerBeetle server runtime log:

```text
release=0.17.7
release_client_min=0.16.4
git_commit=4abc0229ae411fffd669a5a07f50fe3e20b88af0
0: cluster=0: listening on 127.0.0.1:3006
```

## Provenance matrix

| Runtime | Official source and immutable revision | Acquisition and build commands | Download / input hashes | Output hashes and architecture | License path / notice input | Gate result |
| --- | --- | --- | --- | --- | --- | --- |
| PostgreSQL `18.4` | Official source tarball `https://ftp.postgresql.org/pub/source/v18.4/postgresql-18.4.tar.bz2`; upstream release version `18.4` | Download and extract the official tarball into `spikes/integration/runtime/postgresql-src`; run `spikes/integration/scripts/build-postgresql-windows.ps1 -Source <source> -Build <build> -Prefix <install> -PythonToolchain <python-toolchain>`; run `spikes/integration/scripts/package-postgresql-runtime.ps1 -Install <install> -Source <source> -Output spikes/integration/runtime/desktop-runtime/resources/runtime`; run direct `postgres.exe` packaged-runtime probe | Source tarball SHA-256 `81a81ec695fb0c7901407defaa1d2f7973617154cf27ba74e3a7ab8e64436094`; WinFlexBison package SHA-256 `8d324b62be33604b2c45ad1dd34ab93d722534448f55a16ca7292de32b6ac135` | `postgresql/bin/postgres.exe` SHA-256 `570050daddb78285c234cda0002df1df6f4a647e6a7092d271be0512c74e7aac`, PE `0x8664`; `postgresql/bin/initdb.exe` `caf28ce8a546c42a217f75604ae93569f10967e8011cdd058e3acd0da4d7e666`, PE `0x8664`; `postgresql/bin/pg_ctl.exe` `1672ae39e33b8e129eb68aac8b71e128f581650c46a2eaef13bf88dae01ca549`, PE `0x8664`; `postgresql/bin/psql.exe` `e8a8ef2768d2a8021c26d189abd5aaeb6111894fd126e7179deb5ae2df33cfea`, PE `0x8664`; `postgresql/bin/libpq.dll` `5ac39fa0f74878c1e5f86da5422e1e3916360c1c526ef669ac947de1edf6d8ae`, PE `0x8664` | Packaged `licenses/postgresql/COPYRIGHT`, SHA-256 `3d6af92ff8a4c2cdf69afb1cf44edea727922f5cd0cf8b5f72b11cdecac8fdfd`; later notice input is PostgreSQL copyright text from the official source tarball | Pass |
| TigerBeetle `0.17.7` server | Official Windows x64 release asset `https://github.com/tigerbeetle/tigerbeetle/releases/download/0.17.7/tigerbeetle-x86_64-windows.zip`; official tag `0.17.7`; commit `4abc0229ae411fffd669a5a07f50fe3e20b88af0` | Reuse approved FEAS-002 official release acquisition; run `tigerbeetle.exe format --cluster=0 --replica=0 --replica-count=1 --development <data-file>`; run `tigerbeetle.exe start --addresses=127.0.0.1:<port> --development <data-file>` for the combined probe | Release ZIP SHA-256 `ad1d8a77df5589f4181eb73abc560f5b17cdb9ac68b700093a9878fd46e448c7`; extracted server executable SHA-256 `fcb78aa4536e765e2cc15e6f2e222b17c00a325b87e497b1509471682e903a48` | `tigerbeetle.exe` SHA-256 `fcb78aa4536e765e2cc15e6f2e222b17c00a325b87e497b1509471682e903a48`, PE `0x8664`; runtime reported release `0.17.7`, client minimum `0.16.4`, commit `4abc0229ae411fffd669a5a07f50fe3e20b88af0` | Official tag repository-root `LICENSE`, SHA-256 `eb3d7b5485466acbd81f2b496f595ab637d2792e268206b27d99e793bdb67549`; later notice input is Apache-2.0 text from that tag | Pass |
| TigerBeetle C client | Official source ZIP `https://github.com/tigerbeetle/tigerbeetle/archive/refs/tags/0.17.7.zip`; official tag `0.17.7`; commit `4abc0229ae411fffd669a5a07f50fe3e20b88af0` | Reuse approved FEAS-002 official tag checkout and build; build the static C client with TigerBeetle-required Zig `0.14.1`; link FEAS-003 with `-Dtb-client-lib=<approved tb_client.lib> -Dtb-client-include=<approved src/clients/c>` | Source ZIP SHA-256 `b343fa0e4501a063a47b893ec39f278133c93cb67c585dfe81b64ccee7186e9a`; `tb_client.h` SHA-256 `3ad1dd26fb67f3c89c971072cf22ad4a833971f6a40947ca562db2685587964d`; `tb_client.lib` SHA-256 `1edf28ac840cc44ae98a8782d066da525df8257a6c90df921164d706ff232c02` | Static archive `tb_client.lib` SHA-256 `1edf28ac840cc44ae98a8782d066da525df8257a6c90df921164d706ff232c02`; COFF archive contains `tb_client_init`, `tb_client_submit`, `tb_client_deinit`; AMD64 markers present; no TigerBeetle DLL dependency | Official tag repository-root `LICENSE`, SHA-256 `eb3d7b5485466acbd81f2b496f595ab637d2792e268206b27d99e793bdb67549`; later notice input is Apache-2.0 text from that tag | Pass |
| First-party integration executable | Repository worktree at candidate base `6ef9f3829ef2512f1fd0bb03c60219ccb8cc8c62`; FEAS-003 spike sources under `spikes/integration/**`; api.zig `f9a287916ad0e34fda71c8e5b619c5774c8fbb45`; pg.zig `12e48fc57b78486e338e8707448d9a87597dd3ad` plus approved patch | `zig build --fetch`; `zig build -Dtb-client-lib=<approved tb_client.lib> -Dtb-client-include=<approved src/clients/c> -Doptimize=ReleaseSafe --prefix zig-out/native`; run `integration-spike.exe serve <port> <pg-host> <pg-port> <database> <user> <tb-address>`; probe `GET /probe`; shutdown `GET /shutdown` | Zig `0.15.2` executable SHA-256 `d408dd38eed3e5204af841bcebf70502a4dbbb8399a3a3262be55059370bc018`; pg.zig patch SHA-256 `02d6791ab6bdb147c34972e0076992840be7e5fea2e51e6cdac94455033c578c`; TigerBeetle inputs as above | Integration executable SHA-256 `f87e266d1877c9831dd6972cc7a7bef3211d0496fbe123c18ffef478a7e1e429`, PE `0x8664`; `/probe` returned `{"status":"ok","postgres":"ok","tigerbeetle":"ok"}`; `/shutdown` returned `{"shutdown":"accepted"}` and left no descendants | First-party private spike has no license path and is not a third-party notice input; final production API license/source manifest remains deferred to packaging tasks | Pass for feasibility spike; final API hash belongs to later package task |

## Memory, link, runtime, and shutdown observations

- `api.zig`, patched `pg.zig`, and the TigerBeetle C static archive link into
  one Windows x64 Zig executable.
- The combined request opens a PostgreSQL connection to the packaged native
  runtime, executes `SELECT 1`, closes it with `Conn.deinit`, initializes a
  TigerBeetle C client, submits a harmless
  `TB_OPERATION_LOOKUP_ACCOUNTS`, receives one callback, and calls the official
  unmodified `tb_client_deinit` on a dedicated shutdown thread.
- No callback-count, context-pointer, packet-status, or shutdown timing conflict
  was observed in the combined process.
- The TigerBeetle lookup completed with empty result size `0`, exactly one
  callback, and `tb_client_deinit` returned in `60` ms.
- The API process accepted `/shutdown`, exited within the evidence timeout, and
  left no surviving child processes.

## Checks

```text
zig fmt --check build.zig src/main.zig
PASS

zig build --fetch
exit=0

zig build -Dtb-client-lib=<approved-tb-client-lib> -Dtb-client-include=<approved-tb-client-include> -Doptimize=ReleaseSafe --prefix zig-out/native
exit=0

scripts/build-postgresql-windows.ps1
exit=0

scripts/package-postgresql-runtime.ps1
exit=0

scripts/run-evidence.ps1 against packaged native PostgreSQL
probe=passed
```

## Residual risks and follow-up constraints

1. Production packaging must consume only the recorded source/build/package
   path for PostgreSQL. Generated binaries remain ignored and must be rebuilt
   by the packaging task.
2. Production lifecycle work should start `postgres.exe` directly and let the
   Hydra desktop supervisor own shutdown. `pg_ctl start` is not the selected
   desktop lifecycle mechanism because it trips PostgreSQL's restricted-token
   restart path on this host.
3. PostgreSQL was built as a minimal local desktop runtime with TLS and optional
   compression/internationalization/client-language integrations disabled. This
   FEAS-003 decision does not make an external TLS/server compatibility claim.
4. The integration spike is feasibility code only; it does not implement the
   production API, supervisor, runtime staging, or package manifest.
5. Native macOS Intel, macOS Apple Silicon, and Linux remain deferred by
   ADR-0011 and are not approved by this evidence.

`DESKTOP-004` may proceed for Windows 11 x64 using this source-build-package
path as the approved PostgreSQL runtime input.
