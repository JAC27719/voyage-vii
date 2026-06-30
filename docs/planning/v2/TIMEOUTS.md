# Voyage VII v2 Timeouts and Budgets

These values are frozen. “Bounded” in a task guide means the applicable value below; workers must not choose a different duration.

## Runtime and protocol

| Operation | Limit |
| --- | --- |
| API handshake | 15 seconds; maximum 16 KiB |
| Initial full database readiness | 60 seconds |
| PostgreSQL connect | 5 seconds |
| PostgreSQL pool acquisition | 5 seconds |
| PostgreSQL query or probe | 3 seconds |
| TigerBeetle request/callback | 5 seconds |
| Frontend HTTP request | 10 seconds |
| Healthy component probe interval | 10 seconds |
| Transitioning or unhealthy component probe interval | 1 second |
| PostgreSQL graceful stop | 10 seconds |
| TigerBeetle process graceful stop | 10 seconds |
| TigerBeetle C `tb_client_deinit` watchdog | 10 seconds |
| Adapter cancellation/shutdown | 10 seconds |

Component startup uses the initial attempt followed by retries after one, two, and four seconds.

Desktop supervisor shutdown sends the supervisor-authenticated request, waits up to 20 seconds overall for graceful API exit, terminates the process group, waits five seconds, then force-kills and reaps it.

## Test and CI

| Operation | Limit |
| --- | --- |
| Individual test-harness step | 120 seconds |
| Local aggregate test run | 20 minutes |
| Ordinary CI job | 30 minutes |
| Native build or package CI job | 90 minutes |
| CI artifact retention | 7 days |

## Enforcement

- A timeout cancels the operation, releases resources, and returns only a sanitized stable error.
- Timed-out work must not continue in the background or overlap its replacement.
- Exception: official unmodified TigerBeetle C `tb_client_deinit` may be
  synchronously uninterruptible. Production calls it on a dedicated shutdown
  thread. If it misses the 10-second watchdog, the API process terminates
  immediately with exit code `7`; process exit is the cancellation boundary,
  and no background work survives. The parent must observe exit `7` within 12
  seconds in the injected stalled-deinit fixture.
- Probe schedulers measure the interval after completion and never overlap probes.
- Timeout diagnostics contain the operation name and elapsed duration, never secrets, authorization headers, SQL values, native raw exceptions, or handshake content.
