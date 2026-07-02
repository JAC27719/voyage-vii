# Cross-stack harness fixtures

`scripts/test/test.ps1` owns the reusable Windows 11 x64 cross-stack commands.
The harness creates isolated temporary roots under the system temp directory,
adds a `.voyage-test-root` sentinel, writes sanitized logs and process
inventories, preserves failed roots, and removes successful roots only after the
sentinel and canonical parent checks pass.

The `managed-failure` command runs the desktop runtime failure tests, the
runtime-staging safety suite, and harness-level fixtures for timeout, cleanup
escape prevention, stale lock, occupied resource, unwritable root, corrupt
asset, malformed handshake and SQLite-path redaction, command trace capture,
and descendant-process cleanup.

Available commands are:

- `unit`
- `managed-smoke`
- `managed-failure`
- `package-smoke`
- `all`
