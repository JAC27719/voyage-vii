# V1 Retrospective

## What happened

The first attempt combined product discovery, a .NET REST service, cloud infrastructure, Terraform, AWS deployment, GitHub Actions automation, and local development before the desktop runtime boundary had been proven.

The result was a system with too many uncertain layers changing at once. Local-first packaging, native database lifecycle, cross-platform process ownership, and data safety were not established before deployment automation was introduced.

## Lessons carried into v2

- Prove the riskiest technical seams before building product features.
- Establish one owner for every process and credential.
- Treat native packaging as an architectural constraint, not a final release chore.
- Keep cloud deployment out of a local-first milestone.
- Separate reversible development conveniences from production runtime behavior.
- Pin toolchains and binary provenance early.
- Require native evidence on every promised target.
- Keep design decisions, operating procedures, and failure behavior in the repository.
- Make task ownership explicit and serialize overlapping changes.
- Use low-inference implementers so design choices remain visible and reviewable.
- Use independent reviewers and return concrete findings to the original worker.
- Do not automate destructive recovery while data-format and upgrade policy remain unsettled.

## V2 response

V2 begins with compatibility gates, runtime ownership, safe local lifecycle,
portable architecture boundaries, and native Windows 11 x64 desktop/package
smoke tests. Native macOS/Linux execution is a future wave. Financial features
remain documented but deferred until the runtime foundation is demonstrably
reliable.
