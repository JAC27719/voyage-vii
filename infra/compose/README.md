# Voyage VII local Compose

This is a development-only external-mode runtime for Windows 11 x64 hosts with
the approved local container runtime.

The environment runs:

- TigerBeetle `0.17.7`, pinned as
  `ghcr.io/tigerbeetle/tigerbeetle:0.17.7@sha256:d431d365a24d0d626f699169803812e08bb95fc19677ce032b6775150654aae6`
- the first-party API image supplied through `VOYAGE_VII_API_IMAGE`, which must
  be an exact `:0.1.0@sha256:<64 hex chars>` pin

Only the API is published to the host, and only as `127.0.0.1:7800`. TigerBeetle
is reachable only on the internal Compose bridge. SQLite is an API-owned file
inside the `api-data` volume and has no network port.

TigerBeetle uses `seccomp=unconfined` only for this local development Compose
environment. Do not copy that exception into packaged or production runtime
configurations.

## Commands

Start and attach through the redacting launcher:

```powershell
.\scripts\compose\up.ps1 -ApiImage "registry.example/voyage-vii-api:0.1.0@sha256:<64 hex chars>"
```

Stop without removing volumes:

```powershell
.\scripts\compose\stop.ps1
```

Destroy containers and volumes only when explicitly authorized:

```powershell
.\scripts\compose\down-volumes.ps1 -ConfirmDestructiveDown
```

The launcher captures the single API stdout handshake in process memory,
redacts it from console output, uses the in-memory app token for status and
retry checks, and never writes tokens or handshakes to disk. The API service
uses Docker's `none` logging driver so the handshake and API output are
unavailable through `docker logs`.
