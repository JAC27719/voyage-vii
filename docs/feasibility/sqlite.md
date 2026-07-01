# FEAS-004 SQLite Native Integration

## Decision

GO for SQLite as the general-purpose database native input, subject to using
only the official SQLite amalgamation source frozen below.

## Frozen source

- Product: SQLite amalgamation
- Version: `3.53.3`
- Official URL: `https://www.sqlite.org/2026/sqlite-amalgamation-3530300.zip`
- Archive name: `sqlite-amalgamation-3530300.zip`
- Size: `2945929` bytes
- SHA3-256:
  `d45c688a8cb23f68611a894a756a12d7eb6ab6e9e2468ca70adbeab3808b5ab9`
- License posture: SQLite public domain dedication,
  `https://www.sqlite.org/copyright.html`

The source is the unmodified official amalgamation containing `sqlite3.c` and
`sqlite3.h`. FEAS-004 approves no wrapper dependency, fork, binary
distribution, alternate supplier, or SQLite compile-time option.

## Evidence procedure

The evidence script is `spikes/sqlite/scripts/run-evidence.ps1`. It downloads
the official archive, verifies the exact byte size and SHA3-256 hash, extracts
the amalgamation, records source hashes, builds the Zig spike with application
Zig `0.15.2`, runs the native scenario, and records output under
`spikes/sqlite/evidence/`.

Approved build shape:

```text
zig build -Dsqlite-amalgamation=<verified sqlite-amalgamation-3530300 directory> -Doptimize=ReleaseSafe
```

Approved SQLite compile-time options: none. The unmodified `sqlite3.c` is
compiled directly into the Zig executable and linked with libc.

## Native behavior covered

The spike opens a root-local SQLite database path, configures WAL mode, enables
foreign keys, configures a 5000 ms busy timeout, performs a transaction that
creates and writes a `schema_migrations` table, runs `SELECT 1`, verifies the
inserted migration count, and closes the database handle.

## Acceptance summary

Evidence was generated on Windows 11 x64 with application Zig `0.15.2` using
`spikes/sqlite/scripts/run-evidence.ps1`.

- Official source URL, version, size, SHA3-256, and license record: PASS.
- Native Windows 11 x64 Zig build and run: PASS.
- WAL, foreign-key, busy-timeout, migration-table, transaction, `SELECT 1`, and
  clean close output: PASS.
- SQLite wrapper/fork/binary-distribution search: PASS.
- `git diff --check`: PASS.

Recorded hashes:

- Archive SHA3-256:
  `d45c688a8cb23f68611a894a756a12d7eb6ab6e9e2468ca70adbeab3808b5ab9`
- Archive SHA-256:
  `646421e12aac110282ef8cc68f1a62d4bb15fc7b8f09da0b53e29ee690500431`
- `sqlite3.c` SHA-256:
  `87497ab605bedd0dbee27a209c1eeff8c89b229b13f921a7efdbb81a13f779fd`
- `sqlite3.h` SHA-256:
  `4ff81af4849acabc76fc8349abb926814395072617ca18e08800abf734ab7612`
- `sqlite-spike.exe` SHA-256:
  `d17ed581378108967a370bea1a15b60aa7a6ec006eb4a4065dabe4a956466801`

Native run output confirmed:

```text
sqlite_header_version=3.53.3
sqlite_header_source_id=2026-06-26 20:14:12 d4c0e51e4aeb96955b99185ab9cde75c339e2c29c3f3f12428d364a10d782c62
open=ok
wal=ok journal_mode=wal
foreign_keys=ok value=1
busy_timeout=ok value_ms=5000
transaction=ok migration_table=ok
select_probe=ok value=1
migration_count=ok value=1
close=ok
```

Generated evidence logs are under ignored `spikes/sqlite/evidence/` and are
not tracked.
