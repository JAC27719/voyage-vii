# Repository Governance

Voyage VII v2 uses delegated delivery with explicit task ownership,
low-inference implementation, coordinator-controlled Git state, and independent
review. The normative procedure is
[the delegated delivery workflow](../delivery/WORKFLOW.md); root agent
instructions are in [AGENTS.md](../../AGENTS.md).

The joint normative sources are
[START-HERE](../planning/v2/START-HERE.md),
[ARCHITECTURE](../planning/v2/ARCHITECTURE.md),
[DECISIONS](../planning/v2/DECISIONS.md),
[DEPENDENCY-PINS](../planning/v2/DEPENDENCY-PINS.md),
[CONTRACTS](../planning/v2/CONTRACTS.md),
[TIMEOUTS](../planning/v2/TIMEOUTS.md),
[PACKAGING](../planning/v2/PACKAGING.md), the
[task registry](../delivery/tasks.json), assigned
[task guides](../delivery/tasks/), and accepted records in the
[ADR index](../adr/README.md). These sources must agree; none has blanket
precedence over the others. On a conflict, a worker stops and escalates to the
coordinator. Only a later accepted ADR that explicitly names and supersedes a
prior decision changes that decision.

An implementer stops and escalates instead of choosing an architecture,
dependency, interface, fallback, or expanded scope. Verification evidence must
include the complete changed-path set and the prescribed commands and results.
The coordinator alone stages a complete task submission and identifies the
reviewable revision. A separate reviewer reproduces relevant checks and either
approves that exact revision or returns concrete findings.

Historical lessons are linked in the
[v1 retrospective](../planning/v2/RETROSPECTIVE.md). Financial-domain ideas are
not part of the first slice and remain only in the
[deferred finance record](../planning/v2/FUTURE-FINANCE.md).
