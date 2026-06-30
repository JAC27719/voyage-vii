# DESKTOP-003 — SolidJS System-Status UI

**Implementer inference:** Low  
**Prerequisites:** `DESKTOP-001` and `API-004` approved.

## Frozen inputs

Use the DESKTOP-001 frontend seam and exact dependencies/scripts, `DEPENDENCY-PINS.md`, response/origin contracts in `CONTRACTS.md`, and the ten-second HTTP/probe timings in `TIMEOUTS.md`. Replace only owned frontend stubs/paths. Stop if a package manifest, lockfile, shared configuration, or base entrypoint must change.

## Objective

Implement the accessible status-only desktop interface using the shared contracts.

## Procedure

1. Consume the strict TypeScript, Solid Router, Tailwind, ESLint, Prettier, Vitest, Testing Library, and accessibility configuration established by DESKTOP-001.
2. Add a static module registry with only `system` at `/system/status`; redirect `/`.
3. Fetch the runtime snapshot at startup and after every runtime-change event.
4. Keep `appToken` in memory only.
5. Build a typed client for `CONTRACTS.md` that adds `Authorization: Bearer`, handles `X-Request-Id`, uses the ten-second HTTP deadline, aborts obsolete requests, and never automatically replays mutations.
6. Refresh the snapshot once after a generation change or `401`.
7. Poll every second while launching/restarting/unhealthy/retrying and every ten seconds while healthy, without overlap.
8. Render starting, healthy, and degraded summaries plus PostgreSQL/TigerBeetle cards.
9. Add component retry, retry-all, open logs, and copy sanitized diagnostics.
10. Use semantic structure, visible focus, keyboard access, WCAG AA colors, system theme, and restrained polite announcements.

## Acceptance evidence

- Tests for every state, intervals, no-overlap, generation change, `401`, fetch failure, retry, and mutation non-replay.
- Accessibility scan and keyboard notes.
- Screenshots for primary states and both themes.
- Production bundle token/database-access scan.
- DESKTOP-001's frozen frontend typecheck/lint/format-check/test/build commands and `git diff --check` pass with no manifest, lockfile, shared-config, or base-entrypoint diff.
- Current desktop acceptance is Windows 11 x64; portable frontend contracts
  remain platform-neutral.

## Reviewer focus

Verify shared-contract use, memory-only tokens, polling cleanup, retry semantics, diagnostic sanitization, and status communication beyond color.
