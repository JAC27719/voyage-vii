# Voyage VII v2 Decision Record

This is the accepted decision baseline. Changes require an ADR that explicitly supersedes the affected decision.

## Priorities

When tradeoffs conflict, prefer:

1. Correctness
2. Safety and data preservation
3. Portability
4. Simplicity
5. Performance

## Accepted decisions

- Preserve v1 in Git history but remove its active .NET, Terraform, AWS, deployment, and seeder implementation.
- Develop on `codex/voyage-vii-v2`, created from the latest `origin/main` in a Codex-managed worktree.
- Keep the repository private and do not add a license yet.
- Use one staged pull request with logical commits and a merge commit.
- Rename the repository only after the v2 pull request merges.
- Use Zig/api.zig for REST, pg.zig for PostgreSQL, and the TigerBeetle C ABI.
- Make the Zig API the database supervisor; make Tauri the API supervisor.
- Support explicit API `managed` and `external` modes.
- Keep app and supervisor bearer tokens separate, API-generated, and ephemeral in every mode.
- Keep managed and packaged database and API traffic on loopback.
- Permit external development-container mode to use an internal non-published Compose bridge for API-to-database traffic. The API may listen on `0.0.0.0:7800` only inside the container when host publication is exclusively `127.0.0.1:7800`; database ports remain unpublished.
- Use no cookies, telemetry, or metrics.
- Keep DevTools debug-only.
- Use strict CSP and exact-origin CORS.
- Use structured rotating logs without names, amounts, tokens, authorization headers, SQL values, or raw exceptions.
- Use PostgreSQL and TigerBeetle concurrently in Compose for development.
- Pin images by tag and digest; use named volumes and non-root users where supported.
- Permit TigerBeetle `seccomp=unconfined` only in local development.
- Use a static SolidJS module registry and a manually typed client checked against shared schemas/fixtures.
- Use system theme, WCAG AA contrast, technical component names, and a minimal status-focused sidebar.
- Keep the first UI window at `1100×720`, resizable, with remembered geometry.
- Provide component retry, retry-all, open logs, and copy sanitized diagnostics.
- Use project-local bootstrap tooling; never silently perform privileged installations.
- Build and smoke-test every distributable on its native platform.
- Pin GitHub Actions by full SHA with read-only permissions and no secrets.
- Use Dependabot without automerge.
- Keep documentation versioned in Markdown; ADRs are superseded rather than rewritten.
- Freeze exact direct dependencies in `DEPENDENCY-PINS.md`, shared interfaces in `CONTRACTS.md`, limits in `TIMEOUTS.md`, and artifact provenance/layout in `PACKAGING.md`.
- Track the implemented PostgreSQL schema and relations in version-controlled, dbdiagram.io-compatible DBML.
- Keep executable SQL migrations authoritative, but require the corresponding DBML update in the same reviewed schema-change task.
- Keep proposed schemas separate from the implemented diagram and document TigerBeetle mappings without pretending TigerBeetle is relational.

## First-slice exclusions

- Financial product schema or behavior
- Onboarding, accounts, transactions, transfers, budgets, or reports
- Imports, reconciliation, recurring transactions, splits, attachments, and export
- Cloud infrastructure or deployment
- Telemetry and metrics
- Installers, Developer ID signing, notarization, auto-update, or production publishing; macOS ad-hoc `-` sealing for runnable smoke artifacts remains permitted and required
- Database upgrade, reset, repair, or automated backup tooling

## Completion definition

The slice is complete when a developer can:

1. Bootstrap the project on every supported platform.
2. Run PostgreSQL, TigerBeetle, and the API through Compose.
3. Run the desktop app with managed local databases.
4. See accurate component state and perform bounded retries.
5. Open logs and copy sanitized diagnostics.
6. Stop the app without secrets, data loss, or orphan processes.
7. Smoke-test all four portable native artifacts.
