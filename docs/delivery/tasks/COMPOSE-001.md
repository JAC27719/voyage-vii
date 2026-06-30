# COMPOSE-001 — External-Mode Compose Environment

**Implementer inference:** Low  
**Prerequisites:** `API-004` approved.

## Frozen inputs

Use external-mode CLI, development-container exception, tokens, origin/auth, and handshake rules from `CONTRACTS.md`; container limits from `TIMEOUTS.md`; and exact component pins from `DEPENDENCY-PINS.md`. Do not add fixed tokens, implicit environment configuration, alternate ports, or published database ports.

## Objective

Provide one local command that runs PostgreSQL, TigerBeetle, and the Zig API in external mode.

## Procedure

1. Pin PostgreSQL, TigerBeetle, and API images by exact tag and digest.
2. Use named volumes and non-root execution where the image supports it.
3. Put API, PostgreSQL, and TigerBeetle on an internal non-published bridge. Do not host-publish PostgreSQL or TigerBeetle.
4. Run the API with explicit frozen external CLI flags, a PostgreSQL password secret file, `--development-container`, `--listen 0.0.0.0:7800`, `--advertised-api-url http://127.0.0.1:7800`, and development origin `http://localhost:1420`; it must not spawn managed databases.
5. Publish the API host-side only as `127.0.0.1:7800`.
6. Keep API-generated app/supervisor tokens distinct and ephemeral. A launcher captures the one attached-stdout handshake directly into process memory, redacts it from the console, and never persists it.
7. Disable the API service's Compose logging driver so handshake stdout cannot enter Docker logs; API stderr is captured only by the attached launcher under the same redaction boundary.
8. Add health checks and dependency conditions without masking terminal failures.
9. Apply `seccomp=unconfined` only to TigerBeetle and document it as development-only.
10. Provide safe normal stop and an explicit destructive `down --volumes` command.

## Acceptance evidence

- `docker compose config` output plus image-tag/digest and network/publication audit.
- Clean-volume and retained-volume startup.
- Authenticated status/retry checks using only the in-memory captured app token.
- Docker-log scan proving no handshake/token/API log persistence.
- `docker compose down` normal teardown and separately authorized `docker compose down --volumes` verification.
- `git diff --check`.

## Reviewer focus

Check external-mode purity, port exposure, token labeling, volume safety, non-root behavior, and absence of cloud/deployment content.
