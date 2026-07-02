# ADR-0010: Repository Delivery and First-Slice Scope

- Status: Accepted
- Date: 2026-06-29

## Context

The v1 attempt changed product, cloud, deployment, and local-runtime layers
before native process and packaging boundaries were proven. V2 needs a
reviewable delivery unit with visible decisions and a deliberately narrow
first slice.

## Decision

V1 remains in Git history while its active .NET, Terraform, AWS, deployment,
and seeder implementation is removed. V2 development occurs on
`codex/voyage-vii-v2`, created from current `origin/main` in a Codex-managed
worktree. Delivery uses one staged pull request with logical commits and a
merge commit. The repository is renamed only after that pull request merges.
It remains private and no license is added yet.

Task implementation follows
[the delegated delivery workflow](../delivery/WORKFLOW.md): explicit owned
paths, approved prerequisites, low-inference implementers, coordinator-owned
Git state, exact verification evidence, and independent review. Documentation
is versioned in Markdown. Accepted ADRs are superseded by new records rather
than rewritten.

When tradeoffs conflict, the frozen priority order is:

1. Correctness
2. Safety and data preservation
3. Portability
4. Simplicity
5. Performance

The first slice proves bootstrap, managed desktop runtime, status, bounded
retries, sanitized diagnostics, safe shutdown, and native smoke tests on
Windows 11 x64. It excludes financial product behavior,
cloud/deployment, telemetry/metrics, production distribution, and automated
database upgrade, reset, repair, or backup. Historical rationale remains in
[RETROSPECTIVE.md](../planning/v2/RETROSPECTIVE.md); deferred financial ideas
remain in [FUTURE-FINANCE.md](../planning/v2/FUTURE-FINANCE.md).

## Rejected alternatives

- Continuing to evolve the active v1 implementation.
- Working outside the managed branch/worktree or splitting the first slice
  across uncoordinated pull requests.
- Renaming or licensing the repository before the frozen delivery point.
- Hiding changed decisions by rewriting accepted ADR history.
- Pulling financial features, cloud deployment, production publishing, or
  destructive database recovery into the first slice.

## Consequences

Architecture and safety decisions stay visible and independently reviewable.
Implementation stops when owned seams cannot satisfy frozen decisions. Scope
growth requires an explicit coordinator decision rather than implementer
inference.

## Supersession

Changing repository history treatment, branch/worktree policy, pull-request
shape, rename/license timing, ADR history policy, delegated delivery controls,
tradeoff priority order, or first-slice scope requires a new ADR that
explicitly supersedes this record.
