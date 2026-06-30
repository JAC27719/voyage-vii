# ADR-0009: Static UI Modules and the Desktop Bridge

- Status: Accepted
- Date: 2026-06-29

## Context

The first UI exists to expose runtime state and bounded recovery without
creating a second process supervisor, a dynamic plugin boundary, or financial
product scope.

## Decision

The SolidJS application uses a static module registry and a manually typed
HTTP client checked against shared schemas and fixtures. Tauri exposes only
`get_runtime_snapshot` and `open_logs`. It emits
`voyage-vii://runtime-changed` with only generation and state; the UI then
calls `get_runtime_snapshot`. The snapshot contract is the exact type frozen
in [ARCHITECTURE.md](../planning/v2/ARCHITECTURE.md). The supervisor token
never enters JavaScript.

The first window is `1100×720`, resizable, and remembers geometry. The UI uses
system theme, WCAG AA contrast, technical component names, and a minimal
status-focused sidebar. It provides component retry, retry-all, open logs, and
copy sanitized diagnostics. DevTools are debug-only.

Unexpected API exits use a rolling budget of three restarts in five minutes; a
fourth exit is terminal. Shutdown and frontend request timing follow
[TIMEOUTS.md](../planning/v2/TIMEOUTS.md).

## Rejected alternatives

- Runtime-discovered or remotely loaded UI modules.
- Generated behavior that diverges from the shared schemas and fixtures.
- Exposing database access, financial logic, or supervisor authority to the
  UI.
- Sending connection secrets in runtime-change events.
- Shipping DevTools in non-debug builds.

## Consequences

The UI remains a small, auditable view of one desktop-supervised runtime. State
events are hints to fetch the current generation rather than copies of
credentials. Recovery actions use the frozen API rather than direct process or
database control.

## Supersession

Changing module registration, the typed-client source of truth, Tauri command
surface, event payload, supervisor-token custody, restart budget, or frozen
first-slice UI contract requires a new ADR that explicitly supersedes this
record.
