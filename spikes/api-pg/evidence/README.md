# FEAS-001 Evidence Outputs

Run `scripts/run-evidence.ps1` with the exact Zig `0.15.2` executable and a
PostgreSQL `18.4` instance. The script writes full command output here,
including the pg.zig patch SHA-256, Zig fetch/build command exits, native
Windows endpoint proof, repeated five-second nonresponsive connect deadline,
unavailable/auth/success PostgreSQL probes, and supervisor process-exit
evidence.

Generated logs, caches, dependency sources, toolchains, database data, and
binaries are intentionally ignored and are not part of the submitted revision.
