# COMPOSE-001 - Superseded Docker/Compose Environment

Docker and Compose are removed from the active project workflow. This packet is
retained only as historical delivery context; it must not be used to recreate
project Dockerfiles, Compose files, container image builders, or Compose smoke
gates without a newly approved use case.

**Implementer inference:** Low  
**Prerequisites:** `API-004` approved.

## Frozen inputs

Current frozen inputs come from the Docker/Compose removal decision in
`DECISIONS.md` and the loopback-only transport contract in `CONTRACTS.md`.

## Objective

No active implementation objective. The former objective was superseded by the
decision to support the native managed desktop workflow and remove Docker until
there is a real project use case.

## Procedure

No active procedure. Do not recreate Docker/Compose files or commands without a
newly approved task.

## Acceptance evidence

- Active Docker/Compose files, helper scripts, bootstrap profile, test command,
  doctor check, and CI gate remain absent.
- `git diff --check`.

## Reviewer focus

Check that Docker/Compose does not return without an approved use case.
