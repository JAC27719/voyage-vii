# ADR-0006: Writable Roots, Locking, and Local Lifecycle

- Status: Accepted
- Date: 2026-06-29

## Context

Managed native databases need durable local state, single-owner process
control, bounded recovery, and diagnostics that do not leak private data.

## Decision

The writable application root contains `manifest.json`, `runtime.lock`,
`logs/`, `postgresql/`, and `tigerbeetle/`. The runtime holds an exclusive OS
lock. The version-1 writable manifest follows
[CONTRACTS.md](../planning/v2/CONTRACTS.md); credentials and secrets remain in
separate files with restrictive permissions.

In managed mode, PostgreSQL uses a random persisted SCRAM secret, loopback
binding, UTF-8/C locale, pool size two, and fast shutdown. TigerBeetle uses a
random persisted cluster ID, one local replica, and a 128 MiB cache.
TigerBeetle formatting is allowed only for a demonstrably pristine root.

Database startup is the initial attempt followed by retries after one, two,
and four seconds. Healthy probes occur ten seconds after completion;
transitioning or unhealthy probes occur one second after completion. Probes
never overlap. PostgreSQL uses `SELECT 1`; TigerBeetle uses a real harmless
lookup. All operation, shutdown, and supervisor deadlines are the exact values
in [TIMEOUTS.md](../planning/v2/TIMEOUTS.md).

Structured rotating logs should total near 50 MiB and exclude names, amounts,
tokens, authorization headers, handshake content, SQL values, secrets, and raw
exceptions. Copied diagnostics follow the same redaction policy. Idle memory
targets approximately 500 MiB or less.

There is no database upgrade, reset, repair, or automated backup tooling in
this slice.

## Rejected alternatives

- Starting without the exclusive root lock.
- Storing credentials or secrets in either manifest.
- Formatting TigerBeetle when root pristineness is not demonstrated.
- Overlapping probes or continuing timed-out work in the background.
- Automated destructive recovery or backup behavior in this slice.
- Unsanitized logs or diagnostics.

## Consequences

One runtime owns each writable root. Recovery is bounded and observable but
never silently destructive. Timeouts cancel and release resources before
replacement work. The public privacy summary is [PRIVACY.md](../../PRIVACY.md).

## Supersession

Changing root layout, locking, credential storage, initialization safety,
retry/probe behavior, recovery scope, or redaction requires a new ADR that
explicitly supersedes this record.
