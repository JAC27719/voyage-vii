# ADR-0005: Authentication, Handshake, and HTTP Boundaries

- Status: Accepted
- Date: 2026-06-29

## Context

Local processes still cross a security boundary. The desktop needs an
authenticated API connection without persisting secrets or exposing supervisor
authority to JavaScript.

## Decision

In every mode, the API generates distinct app and supervisor tokens as
independent 32-byte CSPRNG values encoded as unpadded base64url. Tokens are
memory-only, never logged or persisted, and have disjoint route scopes.
Authentication uses `Authorization: Bearer` with constant-time comparison.
There are no cookies, telemetry, or metrics.

On request, the API binds, validates its loopback HTTP advertised URL, and
emits exactly the stdout-v1 handshake defined in
[CONTRACTS.md](../planning/v2/CONTRACTS.md) before asynchronous database
initialization. The handshake deadline is 15 seconds with a maximum size of
16 KiB; database readiness has its separate 60-second deadline. All logs go to
stderr.

HTTP exposes only the frozen health, status, retry, retry-all, and shutdown
routes and exact schemas, statuses, exit codes, stable error set, and request
ID behavior in `CONTRACTS.md`. CORS accepts only the configured exact origin
without credentials, CSP is strict, and request bodies are limited to 64 KiB.
The supervisor token authorizes shutdown only and never enters JavaScript.

## Rejected alternatives

- A shared app/supervisor token or supervisor authority in JavaScript.
- Persisted, user-supplied, ambient, or logged tokens.
- Cookies or credentialed CORS.
- Emitting the handshake before bind and URL validation.
- Adding public routes, response shapes, or error codes outside the frozen
  contract.

## Consequences

Possession of an app token cannot authorize shutdown, and local transport does
not substitute for authentication. The handshake is available before database
readiness without conflating the two deadlines. Timeout and cancellation
behavior is governed by [TIMEOUTS.md](../planning/v2/TIMEOUTS.md).

## Supersession

Changing token generation, custody, scope, authentication, handshake framing,
origins, routes, schemas, error codes, or public security limits requires a new
ADR that explicitly supersedes this record and the affected frozen contract.
