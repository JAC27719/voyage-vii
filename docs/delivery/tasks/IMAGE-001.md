# IMAGE-001 - Superseded Compose API image

**Implementer inference:** Low
**Prerequisites:** `API-005`, `COMPOSE-001`, `TEST-001`, and `CI-001` approved.

Docker and Compose are removed from the active project workflow. This packet is
retained only as historical delivery context; do not build, publish, or require
a project API container image without a newly approved use case.

## Frozen inputs

Use the Docker/Compose removal decision in `DECISIONS.md`, loopback-only
contracts from `CONTRACTS.md`, verification entrypoints from `TEST-001`, and
provenance rules from `PACKAGING.md`.

## Objective

No active implementation objective. The former image-build objective was
superseded by the decision to remove Docker/Compose and rely on the native
managed desktop workflow.

## Procedure

No active procedure. Do not add a project API container image or Docker helper
without a newly approved task.

## Acceptance evidence

- Active Docker/Compose files, image builders, bootstrap profile, test command,
  doctor check, and CI gate remain absent.
- `Test-Json -Path docs/delivery/tasks.json -SchemaFile
  docs/delivery/task-registry.schema.json` and `git diff --check`.

## Reviewer focus

Verify Docker/Compose does not return, no deployment/cloud or registry scope
slipped in, and unsupported native Linux desktop claims were not introduced.
