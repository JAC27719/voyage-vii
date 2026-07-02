# FEAS-003 generated evidence

Run `scripts/build-postgresql-windows.ps1` to build PostgreSQL `18.4` from the
official source tarball with the native Windows x64 MSVC/Meson toolchain.

Run `scripts/package-postgresql-runtime.ps1` to stage the installed PostgreSQL
output under the ignored desktop runtime shape:

```text
spikes/integration/runtime/desktop-runtime/resources/runtime/postgresql
spikes/integration/runtime/desktop-runtime/resources/runtime/licenses/postgresql
```

For the integrated probe, start packaged `postgres.exe` directly from that
runtime tree, wait for a local `psql` `SELECT 1` readiness probe, then run
`scripts/run-evidence.ps1` with the exact Zig `0.15.2` executable, the approved
TigerBeetle static client library/header paths, and `PGPASSWORD` set for the
local PostgreSQL trust-auth evidence cluster.

Generated logs, downloads, toolchains, runtime state, and binaries are ignored.
