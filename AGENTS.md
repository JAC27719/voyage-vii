# Codex repository guidance

- Use a Codex-managed worktree for tasks that write Git state.
- Never create nested clones, subrepositories, or temporary Git repositories inside this workspace.
- Run branch, commit, push, and pull-request operations only from the managed worktree.
- Preserve user changes; do not overwrite or discard unrelated work.
- Work only on an assigned task whose prerequisites are approved or integrated.
- Modify only the task's owned paths. Stop and escalate when a required change falls outside them or conflicts with a frozen decision.
- Configure implementers for low inference: follow the task packet and frozen records without making architecture, dependency, interface, fallback, or scope decisions.
- Do not stage, commit, switch branches, push, or open a pull request when acting as an implementer.
- Run every acceptance and verification check required by the task and report the complete changed-path set, commands, results, limitations, risks, and escalations.
- Submit each implementation to an independent high-scrutiny reviewer. Reviewers do not edit the submission and must reproduce relevant checks against the coordinator-issued staged revision.
- Keep SQLite migrations and the corresponding implemented DBML update in the same owned and reviewed task.

The complete role, revision, review, and rework rules are in
[the delegated delivery workflow](docs/delivery/WORKFLOW.md). Frozen decisions
and their governing ADRs are indexed in [docs/adr/README.md](docs/adr/README.md).
