# Architecture Decision Records

Accepted records are immutable decision history. A changed decision is made by
adding a new ADR that names the records or frozen decisions it supersedes; an
accepted record is not rewritten to conceal its former decision.

## Index

| ADR | Decision |
| --- | --- |
| [ADR-0001](0001-local-first-process-boundaries.md) | Local-first process and supervision boundaries |
| [ADR-0002](0002-postgresql-and-tigerbeetle-ownership.md) | PostgreSQL, TigerBeetle, and schema-document ownership |
| [ADR-0003](0003-zig-rest-and-native-database-clients.md) | Zig REST service and native database clients |
| [ADR-0004](0004-managed-and-external-runtime-modes.md) | Managed and external runtime modes |
| [ADR-0005](0005-authentication-handshake-and-http-boundaries.md) | Authentication, handshake, and HTTP boundaries |
| [ADR-0006](0006-writable-roots-locking-and-local-lifecycle.md) | Writable roots, locking, and local lifecycle |
| [ADR-0007](0007-dependency-pins-and-native-provenance.md) | Dependency pins and native provenance |
| [ADR-0008](0008-portable-native-distribution.md) | Portable native distribution |
| [ADR-0009](0009-static-ui-modules-and-desktop-bridge.md) | Static UI modules and the desktop bridge |
| [ADR-0010](0010-repository-delivery-and-first-slice-scope.md) | Repository delivery and first-slice scope |
| [ADR-0011](0011-windows-scope-and-native-lifecycle-recovery.md) | Windows scope and bounded native lifecycle recovery |

## Architecture coverage

Every decision area in
[the frozen architecture](../planning/v2/ARCHITECTURE.md) is governed here:

| Architecture area | ADR |
| --- | --- |
| Product boundary | [ADR-0001](0001-local-first-process-boundaries.md) |
| Identity and targets | [ADR-0008](0008-portable-native-distribution.md), superseded in part by [ADR-0011](0011-windows-scope-and-native-lifecycle-recovery.md) |
| Pinned foundations | [ADR-0003](0003-zig-rest-and-native-database-clients.md), [ADR-0007](0007-dependency-pins-and-native-provenance.md), superseded in part by [ADR-0011](0011-windows-scope-and-native-lifecycle-recovery.md) |
| API process contract | [ADR-0005](0005-authentication-handshake-and-http-boundaries.md), [ADR-0006](0006-writable-roots-locking-and-local-lifecycle.md), superseded in part by [ADR-0011](0011-windows-scope-and-native-lifecycle-recovery.md) |
| REST contract | [ADR-0005](0005-authentication-handshake-and-http-boundaries.md) |
| Desktop contract | [ADR-0009](0009-static-ui-modules-and-desktop-bridge.md), superseded in part by [ADR-0011](0011-windows-scope-and-native-lifecycle-recovery.md) |
| Managed data | [ADR-0006](0006-writable-roots-locking-and-local-lifecycle.md) |
| Database schema documentation | [ADR-0002](0002-postgresql-and-tigerbeetle-ownership.md) |
| Packaged runtime | [ADR-0008](0008-portable-native-distribution.md), superseded in part by [ADR-0011](0011-windows-scope-and-native-lifecycle-recovery.md) |
| Development-container network exception | [ADR-0004](0004-managed-and-external-runtime-modes.md) |

## Frozen-decision mapping

The tradeoff priorities and every accepted decision in
[the v2 decision baseline](../planning/v2/DECISIONS.md) map to a governing ADR:

| Frozen decision | ADR |
| --- | --- |
| Tradeoff priority order: correctness; safety and data preservation; portability; simplicity; performance | [ADR-0010](0010-repository-delivery-and-first-slice-scope.md) |
| Preserve v1 in history while removing its active implementation | [ADR-0010](0010-repository-delivery-and-first-slice-scope.md) |
| Develop on the named branch in a Codex-managed worktree | [ADR-0010](0010-repository-delivery-and-first-slice-scope.md) |
| Keep the repository private and unlicensed for now | [ADR-0010](0010-repository-delivery-and-first-slice-scope.md) |
| Use one staged pull request, logical commits, and a merge commit | [ADR-0010](0010-repository-delivery-and-first-slice-scope.md) |
| Rename the repository only after merge | [ADR-0010](0010-repository-delivery-and-first-slice-scope.md) |
| Use Zig/api.zig, pg.zig, and the TigerBeetle C ABI | [ADR-0003](0003-zig-rest-and-native-database-clients.md) |
| Make the Zig API the database supervisor and Tauri the API supervisor | [ADR-0001](0001-local-first-process-boundaries.md) |
| Support explicit managed and external API modes | [ADR-0004](0004-managed-and-external-runtime-modes.md) |
| Keep separate, API-generated ephemeral app and supervisor tokens | [ADR-0005](0005-authentication-handshake-and-http-boundaries.md) |
| Keep managed and packaged traffic on loopback | [ADR-0004](0004-managed-and-external-runtime-modes.md) |
| Permit only the bounded development-container network exception | [ADR-0004](0004-managed-and-external-runtime-modes.md) |
| Use no cookies, telemetry, or metrics | [ADR-0005](0005-authentication-handshake-and-http-boundaries.md) |
| Keep DevTools debug-only | [ADR-0009](0009-static-ui-modules-and-desktop-bridge.md) |
| Use strict CSP and exact-origin CORS | [ADR-0005](0005-authentication-handshake-and-http-boundaries.md) |
| Use redacted structured rotating logs | [ADR-0006](0006-writable-roots-locking-and-local-lifecycle.md) |
| Run PostgreSQL and TigerBeetle concurrently in Compose | [ADR-0004](0004-managed-and-external-runtime-modes.md) |
| Pin images by tag and digest and use bounded container privileges | [ADR-0004](0004-managed-and-external-runtime-modes.md) |
| Limit TigerBeetle `seccomp=unconfined` to local development | [ADR-0004](0004-managed-and-external-runtime-modes.md) |
| Use a static SolidJS module registry and schema-checked typed client | [ADR-0009](0009-static-ui-modules-and-desktop-bridge.md) |
| Use the frozen accessible, status-focused visual design | [ADR-0009](0009-static-ui-modules-and-desktop-bridge.md) |
| Use a resizable `1100×720` first window with remembered geometry | [ADR-0009](0009-static-ui-modules-and-desktop-bridge.md) |
| Provide retry, retry-all, logs, and sanitized diagnostics | [ADR-0009](0009-static-ui-modules-and-desktop-bridge.md) |
| Use project-local bootstrap tooling without silent privilege elevation | [ADR-0008](0008-portable-native-distribution.md) |
| Build and smoke-test the current Windows distributable natively; defer macOS/Linux | [ADR-0011](0011-windows-scope-and-native-lifecycle-recovery.md) |
| Pin Actions by full SHA with read-only permissions and no secrets | [ADR-0007](0007-dependency-pins-and-native-provenance.md) |
| Use Dependabot without automerge | [ADR-0007](0007-dependency-pins-and-native-provenance.md) |
| Version Markdown documentation and supersede ADRs rather than rewrite them | [ADR-0010](0010-repository-delivery-and-first-slice-scope.md) |
| Freeze dependencies, interfaces, limits, and packaging in named records | [ADR-0007](0007-dependency-pins-and-native-provenance.md) |
| Track implemented PostgreSQL schema and relations in DBML | [ADR-0002](0002-postgresql-and-tigerbeetle-ownership.md) |
| Keep SQL authoritative and update DBML in the same reviewed task | [ADR-0002](0002-postgresql-and-tigerbeetle-ownership.md) |
| Separate proposed schemas and document TigerBeetle as non-relational | [ADR-0002](0002-postgresql-and-tigerbeetle-ownership.md) |
| Keep portable interfaces while Windows 11 x64 is the sole current target | [ADR-0011](0011-windows-scope-and-native-lifecycle-recovery.md) |
| Use process-boundary api.zig shutdown, one bounded pg.zig patch, and exit-7 TigerBeetle containment | [ADR-0011](0011-windows-scope-and-native-lifecycle-recovery.md) |

The [v1 retrospective](../planning/v2/RETROSPECTIVE.md) remains the historical
record. Financial behavior is deferred and is linked, not adopted, in the
[future finance record](../planning/v2/FUTURE-FINANCE.md).
