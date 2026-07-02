# AUDIT-001 Final Integration Audit

## Status

Verdict: `PASS`

Audited commit:

```text
39762eb21593a9b2ef3b61d41de2ef4482b13865
```

Evidence root:

```text
C:\Users\jcane\AppData\Local\Temp\voyage-vii-audit-001-08c7549fe4ac44e1a5d7a1f15d0ebf20
```

AUDIT-001 made no production edits.

## Task Inventory

`docs/delivery/tasks.json` validates against
`docs/delivery/task-registry.schema.json`. Docker/Compose delivery packets are
now superseded by the project decision to remove Docker until there is a real
use case. The supported local developer path is the native managed desktop
workflow.

## Requirement Traceability

| Requirement area | Evidence |
| --- | --- |
| Windows 11 x64 current target only | Planning baseline, ADR-0011, CI-001 Windows runners, DOC-002 runbooks |
| Exact toolchain and dependency pins | `docs/planning/v2/DEPENDENCY-PINS.md`, package report, CI setup |
| API CLI, handshake, tokens, routes, status, retry, shutdown | `docs/planning/v2/CONTRACTS.md`, API tests, managed smoke, package smoke |
| Runtime timeouts and shutdown containment | `docs/planning/v2/TIMEOUTS.md`, HARDEN-001, PACKAGE-004, managed smoke |
| SQLite implemented schema and DBML sync | API-005 and DBDOC-001 registry evidence, `docs/database/README.md` |
| TigerBeetle C ABI and managed lifecycle | FEAS-002, API-003, RUNTIME-003, HARDEN-001, package report |
| Docker/Compose posture | Active Dockerfiles, Compose files, container build helpers, Compose scripts, Compose CI gate, and Compose smoke commands removed |
| Desktop managed mode and UI boundary | DESKTOP-001 through DESKTOP-004 registry evidence, managed smoke |
| Windows ZIP layout, provenance, and smoke | PACKAGE-001, PACKAGE-004, PACKAGE-005 registry evidence, package report, extracted package smoke |
| Non-deployment CI and dependency automation | CI-001 registry evidence and `.github/workflows/ci.yml` |
| Verified runbooks | DOC-002 registry evidence and `docs/development/command-verification.md` |

## Checks Performed

| Check | Result | Evidence |
| --- | --- | --- |
| Registry schema | Pass | `Test-Json -Path docs/delivery/tasks.json -SchemaFile docs/delivery/task-registry.schema.json` |
| Non-audit task integration inventory | Pass | PowerShell task registry scan |
| Tracked generated artifacts and ZIP/PDB audit | Pass | `git ls-files` scan found no tracked `node_modules`, `dist`, `target`, package output, ZIP, or PDB artifacts |
| v1/Terraform/AWS/deployment remnants | Pass | `git ls-files` scan found no active v1 .NET, Terraform, AWS, or deployment workflow paths |
| Credential/token pattern scan | Pass | `rg` scans found no bearer tokens, app/supervisor token values, or AWS access key patterns in tracked source excluding generated caches |
| Docker/Compose active surface removal | Pass | `compose.yaml`, `scripts/compose`, `services/api/Dockerfile`, `tools/container` builder, Compose CI job, bootstrap profile, doctor check, and `compose-smoke` command removed |
| Managed smoke | Pass | `managed-smoke.exit.txt`, `managed-smoke.stdout.log` |
| Hardening matrix | Pass | `hardening-all.exit.txt`, `hardening-all.stdout.log` |
| Extracted package smoke | Pass | `package-smoke-existing-root.exit.txt`, `package-smoke-existing-root.stdout.log` |
| Offline package rebuild rerun | Pass | `pwsh -NoProfile -File tools/package/windows/build-windows-zip.ps1 -Offline` completed from the audited revision in an approved operator environment; `tools/package/windows/reports/last-run.md` records smoke `PASS` |

Latest package report at `tools/package/windows/reports/last-run.md` records:

- artifact: `voyage-vii_0.1.0_windows-x86_64.zip`
- artifact SHA-256: `d2aab5b256a164f65bf3d4ec357af370d3ec5c477c7464e6a324ab08b5039f2a`
- target: `x86_64-pc-windows-msvc`
- API revision: `39db9e0c76ab1541c37037983e0c60b79a87b71b`
- smoke: `PASS`

## Findings

### AUDIT-001-F1 [P2] Real Compose smoke was gated

Requirement:
AUDIT-001 previously required re-running Compose as part of the final
integration audit.

Evidence:
The project decision is to remove Docker/Compose until there is a real use
case. The active Compose surface was removed instead of keeping a local-only
image build path: Compose files, Dockerfiles, container builder scripts,
Compose helper scripts, CI Compose gate, bootstrap profile, doctor check, and
Compose smoke command are no longer active project entrypoints.

Required correction:
Closed by superseding the Docker/Compose requirement and removing the active
Docker/Compose workflow.

Owner route:
IMAGE-001, COMPOSE-001, TEST-001, CI-001, and AUDIT-001 records.

### AUDIT-001-F2 [P2] Final ZIP rebuild failed in this operator session

Requirement:
AUDIT-001 requires final package commands and final Windows ZIP smoke evidence
against the audited revision.

Evidence:
Initial sandboxed execution of
`tools/package/windows/build-windows-zip.ps1 -Offline` failed before packaging
while running `bun run build`. A rerun from an approved operator environment
completed successfully from audited commit
`39762eb21593a9b2ef3b61d41de2ef4482b13865`, created
`voyage-vii_0.1.0_windows-x86_64.zip` with SHA-256
`d2aab5b256a164f65bf3d4ec357af370d3ec5c477c7464e6a324ab08b5039f2a`, and
completed the packaged smoke harness. The package report records target
`x86_64-pc-windows-msvc`, API revision
`39db9e0c76ab1541c37037983e0c60b79a87b71b`, and smoke `PASS`.

Required correction:
Closed by the successful operator-environment rerun and updated package report.

Owner route:
Coordinator, with PACKAGE-001/PACKAGE-004 evidence owners.

## Finding Closure

| Finding | Status | Closure evidence |
| --- | --- | --- |
| AUDIT-001-F1 | closed | Docker/Compose active workflow removed; no Compose smoke gate remains |
| AUDIT-001-F2 | closed | Fresh offline Windows ZIP build passed; package report records SHA-256 `d2aab5b256a164f65bf3d4ec357af370d3ec5c477c7464e6a324ab08b5039f2a` and smoke `PASS` |

## Residual Risks

- Native macOS and Linux support remains deferred and is not represented as
  native evidence.
- Existing generated package and runtime outputs remain ignored local state.
- Historical planning and delivery records may mention Docker/Compose as prior
  context, but active scripts, CI, and runbooks no longer expose Docker
  commands.

## Conclusion

The integrated repository has no remaining open P0-P2 audit findings in this
audit record. Registry, governance, tracked-artifact hygiene, credential scans,
managed smoke, hardening, and fresh Windows ZIP smoke passed. Docker/Compose is
not an active acceptance surface.
