# Codex repository guidance

- Use a Codex-managed worktree for tasks that write Git state.
- Never create nested clones, subrepositories, or temporary Git repositories inside this workspace.
- Run branch, commit, push, and pull-request operations only from the managed worktree.
- Preserve user changes; do not overwrite or discard unrelated work.
