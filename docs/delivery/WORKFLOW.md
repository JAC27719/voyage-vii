# Delegated Delivery Workflow

## Roles

### Coordinator

- Owns architecture and scope decisions.
- Creates and manages the Git branch from the Codex-managed worktree.
- Assigns tasks only when prerequisites are approved.
- Prevents concurrent ownership conflicts.
- Preserves unrelated index and worktree content.
- Stages exactly one complete task submission, including new and deleted files, and issues its canonical revision identity.
- Commits, pushes, and opens the pull request.
- Integrates only the exact revision approved by the reviewer.

### Implementer

Implementers must be configured for **low inference**.

- Receive only the task packet, frozen architecture, and prerequisite outputs needed for the task.
- Execute the prescribed steps and acceptance checks.
- Modify only owned paths.
- Do not make architectural, dependency, interface, fallback, or scope decisions.
- Do not stage, commit, switch branches, push, or open pull requests.
- Stop and escalate if requirements conflict, evidence is unavailable, a prerequisite is invalid, or an unlisted change is necessary.
- Never interpret silence as permission to improvise.
- A task that changes the SQLite schema must own and update both the executable migration and `docs/database/sqlite.dbml`; otherwise it must stop for coordinator reassignment.

### Reviewer

Reviewers are separate from implementers and use **high scrutiny**.

- Do not edit files.
- Review the exact submitted revision.
- Verify the coordinator-staged path set and independently recompute the canonical staged-diff hash before reviewing content.
- Reproduce relevant checks rather than relying solely on worker claims.
- Check acceptance criteria, architecture, security, failure behavior, tests, and owned-path compliance.
- Send changes back to the original implementer and copy the coordinator.
- Re-review corrections until the exact revision is approved.

## Status model

```text
blocked → ready → in_progress → submitted
        → changes_requested → in_progress → submitted
        → approved → integrated
```

`blocked` may become `ready` only when every `dependsOn` task is approved or integrated. Only the coordinator marks a task integrated.

On worker handoff, metadata records `status: submitted`, the assigned worker and reviewer, the candidate base, complete changed paths, summary, acceptance evidence, and `revision: pending-coordinator-staged-hash`. That placeholder remains inside the staged task content throughout review. `changes_requested` and every correction cycle require a newly staged full submission and new out-of-band canonical revision identity.

## Revision identity

The worker reports its candidate base commit, complete changed-path list, and evidence. The worker does not stage.

The coordinator alone:

1. verifies every submitted path is owned and no required task change is omitted;
2. preserves unrelated index and worktree content;
3. stages exactly the full task submission, including new and deleted files; and
4. computes the canonical revision:

```text
<base-commit-sha>:<sha256>
```

`<sha256>` is the lowercase SHA-256 of the raw bytes emitted by:

```text
git diff --cached --binary --full-index --no-ext-diff --no-color <base-commit-sha> -- <exact submitted paths>
```

Path arguments are the coordinator-verified complete submitted-path list in deterministic ordinal order. Hash the command's raw stdout bytes without text decoding or newline conversion.

This staged diff includes tracked, newly added, and deleted submitted files. The coordinator-issued identity is the only reviewable revision. The coordinator sends it out-of-band in the review assignment, and the reviewer repeats it in `Reviewed revision`. The reviewer independently verifies the staged path set, command, raw-byte hash, and diff. Any correction requires the coordinator to restage the complete task and issue a new out-of-band identity.

Immediately before integration, the coordinator confirms the same staged paths and recomputes the identity. A mismatch invalidates approval. After approval, the coordinator commits and integrates the exact approved staged task diff unchanged.

Only after that integration, the coordinator performs a separate metadata-only `docs/delivery/tasks.json` update that records the canonical submission revision, reviewer verdict and review identity, and `integrated` status. The coordinator verifies this mechanical registry update independently; it must not alter task deliverables or be folded into the approved task diff.

Keeping `pending-coordinator-staged-hash` inside the reviewed diff avoids a self-referential hash whose value would change when recorded. Later implementation tasks normally do not own `docs/delivery/tasks.json`; the coordinator owns these post-integration registry updates. The coordinator must never clear, overwrite, or include unrelated staged or worktree content.

## Worker submission

```text
Task:
Revision:
Candidate base:
Changed paths:
Summary:
Acceptance evidence:
  - criterion
  - command
  - result
Native platforms exercised:
Known limitations:
Residual risks:
Escalations:
```

`Revision` remains `pending-coordinator-staged-hash` in the submitted and staged task content. The coordinator supplies the canonical identity out-of-band with the review assignment; it is recorded in `tasks.json` only by the separate post-integration metadata update.

The worker includes complete output locations, not selectively copied success lines. Secrets must be redacted before evidence is recorded.

## Reviewer response

```text
Verdict: APPROVED | CHANGES_REQUESTED | BLOCKED
Reviewed revision:

Acceptance:
- [pass/fail] Criterion and evidence

Findings:
- REV-001 [P0-P3] path:line
  Requirement:
  Evidence:
  Required correction:
  Verification:

Residual risks:
```

Severity:

- `P0`: data loss, credential exposure, destructive behavior, or fundamental architecture violation.
- `P1`: required behavior is broken or a target cannot build/run.
- `P2`: important correctness, safety, test, or documentation gap.
- `P3`: bounded maintainability or clarity issue.

`APPROVED` requires no unresolved P0–P2 finding. P3 findings must either be corrected or explicitly accepted by the coordinator.

## Rework loop

1. Reviewer sends numbered findings to the original implementer.
2. Implementer changes only the requested scope or escalates a conflict.
3. Implementer returns a resolution table mapping every finding to files and verification.
4. The coordinator restages the complete corrected submission and issues a new canonical revision.
5. Reviewer checks the new revision and every prior finding.
6. Repeat until approved.

## Parallel work

- Parallel tasks must have disjoint owned paths and approved prerequisites.
- Shared manifests and lockfiles have one active owner.
- SQLite migrations and the implemented DBML diagram are one review unit even when that requires serializing otherwise independent work.
- A task needing another owner’s path stops and requests coordinator reassignment.
- Reviewers may read the full tree but cannot edit it.

## Handoff safety

Before implementation, a new chat must read `docs/planning/v2/START-HERE.md`. If the repository branch, task registry, or architecture does not match the documented baseline, stop and reconcile it before assigning workers.
