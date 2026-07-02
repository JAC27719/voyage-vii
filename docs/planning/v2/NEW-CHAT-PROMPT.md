# New Implementation Chat Prompt

Copy the text below into the new implementation chat:

> Implement Voyage VII v2 using the persisted repository plan.
>
> Start by reading:
>
> - `docs/planning/v2/START-HERE.md`
> - `docs/planning/v2/ARCHITECTURE.md`
> - `docs/planning/v2/DECISIONS.md`
> - `docs/planning/v2/DEPENDENCY-PINS.md`
> - `docs/planning/v2/CONTRACTS.md`
> - `docs/planning/v2/TIMEOUTS.md`
> - `docs/planning/v2/PACKAGING.md`
> - `docs/planning/v2/IMPLEMENTATION-PLAN.md`
> - `docs/delivery/WORKFLOW.md`
> - `docs/delivery/tasks.json`
>
> Work only from a Codex-managed worktree. Preserve user changes. Create `codex/voyage-vii-v2` from the latest `origin/main` before implementation.
>
> Assign implementation workers with low inference. They must execute only their approved task guides and escalate ambiguity rather than improvising. Assign a different high-scrutiny reviewer to every task. Send findings back to the original worker and use the same reviewer for rechecks. Integrate only approved revisions.
>
> The sole current support and completion target is Windows 11 x64
> (`x86_64-pc-windows-msvc`). Keep platform boundaries extensible, but treat
> non-Windows stubs and cross-builds as informational only. Do not claim them as
> native execution or support.
>
> Confirm `PLAN-001` is approved and integrated, then resume `FEAS-001` and
> `FEAS-002` with their original worker/reviewer pairs. Follow task dependencies
> and path ownership. Do not implement financial features, cloud deployment, or
> deferred native macOS/Linux packaging.
