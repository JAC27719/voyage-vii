# Privacy

Voyage VII is local-first. Application data and credentials remain local; in
managed operation, state is kept in the local writable application root. The
first v2 slice has no cloud deployment, telemetry, or metrics.

Managed and packaged application traffic is restricted to loopback. Docker and
Compose are not active project workflows. Exact-origin CORS and bearer
authentication still apply.

Logs and copied diagnostics are sanitized. They must not contain names,
amounts, credentials, tokens, authorization headers, handshake content, SQL
values, raw native exceptions, or secrets. Credential-file paths and contents
are not logged beyond sanitized diagnostics.

The governing security and transport decisions are recorded in
[ADR-0004](docs/adr/0004-managed-and-external-runtime-modes.md),
[ADR-0005](docs/adr/0005-authentication-handshake-and-http-boundaries.md), and
[ADR-0006](docs/adr/0006-writable-roots-locking-and-local-lifecycle.md).
