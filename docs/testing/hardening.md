# HARDEN-001 hardening evidence

HARDEN-001 uses `tests/hardening/run-hardening.ps1` as the reproducible
Windows 11 x64 entrypoint. The runner writes sanitized logs and summaries under
`%TEMP%\voyage-vii-hardening\<guid>` and preserves the report root for audit.

## Commands

- Full local matrix:
  `pwsh -NoProfile -File tests/hardening/run-hardening.ps1 -Command all`
- Contract and pin scan:
  `pwsh -NoProfile -File tests/hardening/run-hardening.ps1 -Command contract-scan`
- Runtime and failure matrix:
  `pwsh -NoProfile -File tests/hardening/run-hardening.ps1 -Command runtime-matrix`
- Isolated package/runtime staging:
  `pwsh -NoProfile -File tests/hardening/run-hardening.ps1 -Command package-matrix`
- Artifact and redaction scan:
  `pwsh -NoProfile -File tests/hardening/run-hardening.ps1 -Command artifact-scan`
- Startup/process timing baseline:
  `pwsh -NoProfile -File tests/hardening/run-hardening.ps1 -Command performance-baseline`

## Coverage

- Token scope, exact CORS, request-limit, stable-error, timeout, packaging, and
  dependency requirements are checked against the frozen planning records.
- Runtime crash, malformed handshake, missing handshake, duplicate handshake,
  forced shutdown, exit-7 shutdown, env stripping, token redaction, restart
  budget, shutdown-token scope, grandchild cleanup, stale lock, occupied
  resource, corrupt runtime asset, unsafe paths, wrong architecture, and
  offline cache cases are exercised through the desktop runtime tests,
  runtime-staging safety tests, and the reusable TEST-001 harness.
- Package smoke stages runtime output and reports into the hardening temp root,
  not repository runtime/report paths.
- Artifact scanning searches hardening logs and generated reports for tokens,
  authorization headers, SQLite path leakage, and private absolute paths.
- The full run removes its isolated Cargo test-build cache before artifact
  scanning so compiler scratch binaries do not become retained audit artifacts.
- Performance evidence records managed-smoke elapsed time and process
  working-set delta. Full packaged-app idle memory and log-rotation evidence
  remains gated by PACKAGE-004 and PACKAGE-001.

## Owner-routed defects

The HARDEN-001 scan found stale PostgreSQL references after the approved SQLite
posture change. These are not fixed in HARDEN-001 because they fall outside
`tests/hardening/**` and `docs/testing/hardening.md`.

- `contracts/**` still contains PostgreSQL schemas and fixtures for status,
  runtime manifest, writable manifest, and error codes.
- `services/api/src/runtime/manifest/root.zig` still models PostgreSQL as a
  packaged and writable runtime component.
- `services/api/src/main.zig`, `services/api/src/postgres/root.zig`, and
  `services/api/src/runtime/postgresql/root.zig` still retain PostgreSQL seams.
- Ownership route: API-001 and RUNTIME-001 for API/runtime contracts and code,
  with PLAN-002 as the governing SQLite posture amendment.

## Local limitations

- The local host currently exposes Zig 0.14 syntax behavior to `zig build test`;
  full API unit completion requires the frozen application Zig 0.15.2 toolchain.
