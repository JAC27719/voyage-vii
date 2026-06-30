# FEAS-003 Windows Native Evidence

This file preserves the reviewable, sanitized excerpts from the Windows 11 x64
FEAS-003 run. Generated `.log` files, downloaded archives, caches, runtime
data, and binaries remain ignored.

## Toolchains and Inputs

```text
zig_version=0.15.2
zig_sha256=d408dd38eed3e5204af841bcebf70502a4dbbb8399a3a3262be55059370bc018
pg_patch_sha256=02d6791ab6bdb147c34972e0076992840be7e5fea2e51e6cdac94455033c578c
tb_exe_sha256=fcb78aa4536e765e2cc15e6f2e222b17c00a325b87e497b1509471682e903a48
tb_client_lib_sha256=1edf28ac840cc44ae98a8782d066da525df8257a6c90df921164d706ff232c02
tb_client_header_sha256=3ad1dd26fb67f3c89c971072cf22ad4a833971f6a40947ca562db2685587964d
```

PostgreSQL source-build input:

```text
official_url=https://ftp.postgresql.org/pub/source/v18.4/postgresql-18.4.tar.bz2
source_tarball_sha256=81a81ec695fb0c7901407defaa1d2f7973617154cf27ba74e3a7ab8e64436094
version=18.4
host_system=windows x86_64
build_system=windows x86_64
c_compiler=msvc 19.39.33523
meson=1.11.1
ninja=1.13.0
winflexbison_sha256=8d324b62be33604b2c45ad1dd34ab93d722534448f55a16ca7292de32b6ac135
win_bison=3.8.2
win_flex=2.6.4
```

TigerBeetle inputs from the approved FEAS-002 evidence:

```text
release_url=https://github.com/tigerbeetle/tigerbeetle/releases/download/0.17.7/tigerbeetle-x86_64-windows.zip
release_zip_sha256=ad1d8a77df5589f4181eb73abc560f5b17cdb9ac68b700093a9878fd46e448c7
source_url=https://github.com/tigerbeetle/tigerbeetle/archive/refs/tags/0.17.7.zip
source_zip_sha256=b343fa0e4501a063a47b893ec39f278133c93cb67c585dfe81b64ccee7186e9a
tag=0.17.7
commit=4abc0229ae411fffd669a5a07f50fe3e20b88af0
license_sha256=eb3d7b5485466acbd81f2b496f595ab637d2792e268206b27d99e793bdb67549
```

## Commands

```powershell
zig build --fetch
exit=0

zig build `
  -Dtb-client-lib=<approved FEAS-002 tb_client.lib> `
  -Dtb-client-include=<approved FEAS-002 src/clients/c> `
  -Doptimize=ReleaseSafe `
  --prefix zig-out/native
exit=0

spikes/integration/scripts/build-postgresql-windows.ps1 `
  -Source <postgresql-18.4-source> `
  -Build <postgresql-build> `
  -Prefix <postgresql-install> `
  -PythonToolchain <python-toolchain>
exit=0

spikes/integration/scripts/package-postgresql-runtime.ps1 `
  -Install <postgresql-install> `
  -Source <postgresql-18.4-source> `
  -Output spikes/integration/runtime/desktop-runtime/resources/runtime
exit=0

tigerbeetle.exe format --cluster=0 --replica=0 --replica-count=1 --development <data-file>
exit=0

tigerbeetle.exe start --addresses=127.0.0.1:3006 --development <data-file>

integration-spike.exe serve 18086 127.0.0.1 55432 postgres postgres 127.0.0.1:3006
Invoke-WebRequest http://127.0.0.1:18086/probe
Invoke-WebRequest http://127.0.0.1:18086/shutdown
```

## Packaged Runtime Outputs

```text
package_file_count=1929
postgresql/bin/postgres.exe sha256=570050daddb78285c234cda0002df1df6f4a647e6a7092d271be0512c74e7aac pe_machine=0x8664
postgresql/bin/initdb.exe sha256=caf28ce8a546c42a217f75604ae93569f10967e8011cdd058e3acd0da4d7e666 pe_machine=0x8664
postgresql/bin/pg_ctl.exe sha256=1672ae39e33b8e129eb68aac8b71e128f581650c46a2eaef13bf88dae01ca549 pe_machine=0x8664
postgresql/bin/psql.exe sha256=e8a8ef2768d2a8021c26d189abd5aaeb6111894fd126e7179deb5ae2df33cfea pe_machine=0x8664
postgresql/bin/libpq.dll sha256=5ac39fa0f74878c1e5f86da5422e1e3916360c1c526ef669ac947de1edf6d8ae pe_machine=0x8664
licenses/postgresql/COPYRIGHT sha256=3d6af92ff8a4c2cdf69afb1cf44edea727922f5cd0cf8b5f72b11cdecac8fdfd
```

The packaged runtime command probes passed:

```text
postgres (PostgreSQL) 18.4
initdb (PostgreSQL) 18.4
pg_ctl (PostgreSQL) 18.4
psql (PostgreSQL) 18.4
postgres_packaged_probe=passed
```

## Integration Build and Probe

```text
integration_exe_sha256=f87e266d1877c9831dd6972cc7a7bef3211d0496fbe123c18ffef478a7e1e429
integration_exe_pe_machine=0x8664
```

HTTP response:

```text
status_code=200
content_type=application/json
body={"status":"ok","postgres":"ok","tigerbeetle":"ok"}
```

Integration stderr:

```text
[OK] http://127.0.0.1:18086
[INFO] Running in single-threaded mode
pg_probe=passed value=1
pg_cleanup=complete
tb_lookup=passed result_size=0 callbacks=1 elapsed_ms=1012 deinit_ms=60
integration_probe=passed pg_value=1 tb_result_size=0 tb_callbacks=1 tb_deinit_ms=60
```

TigerBeetle server excerpt:

```text
release=0.17.7
release_client_min=0.16.4
git_commit=4abc0229ae411fffd669a5a07f50fe3e20b88af0
0: cluster=0: listening on 127.0.0.1:3006
```

Shutdown:

```text
server_process_id=52556
shutdown_status=200
shutdown_body={"shutdown":"accepted"}
children_before_stop=26440
server_running_after_stop=False
children_after_stop=
```

## Hygiene Checks

```text
zig fmt --check build.zig src/main.zig
PASS

git diff --check
PASS
```
