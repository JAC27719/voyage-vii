# ADR-0007: Dependency Pins and Native Provenance

- Status: Accepted
- Date: 2026-06-29

## Context

Portable native builds cannot be audited or reproduced if toolchains,
dependencies, source suppliers, actions, or binary origins drift silently.

## Decision

All direct toolchain, Zig, NPM, and Rust dependencies use the exact versions
and revisions in
[DEPENDENCY-PINS.md](../planning/v2/DEPENDENCY-PINS.md). Manifests use exact
constraints, dependency lockfiles are committed, and reproducible builds
reject resolution drift. An unlisted direct dependency or pin change requires
a coordinator-approved planning amendment or ADR.

PostgreSQL `18.4` comes from its official source tarball and is built natively
for each target. TigerBeetle `0.17.7` comes from an official target release
asset when one exists; otherwise its official tag is built with Zig `0.14.1`.
The API is a first-party build of the audited repository commit with Zig
`0.15.2`. Required source URLs, immutable revisions, archive and output hashes,
targets, toolchains, licenses, notices, and manifest fields follow
[PACKAGING.md](../planning/v2/PACKAGING.md).

The private first-party API has no invented license or source URL and is
excluded from third-party notices. GitHub Actions are pinned by full commit SHA
with read-only permissions and no secrets. Dependabot is enabled without
automerge.

## Rejected alternatives

- Version ranges, tags, wildcards, resolution drift, or uncommitted lockfiles.
- Unofficial suppliers, substitute database builds, or alternate source
  revisions.
- Inventing a license or source URL for the private first-party API.
- Mutable action references, write permissions, CI secrets, or automated
  dependency merges.

## Consequences

Every dependency-owning task records manifest excerpts, a clean-lockfile build
or installation, a direct-dependency search, and lockfile paths. Native
artifacts carry target-specific provenance and hashes. Generated runtimes and
packages remain untracked; CI artifacts are retained seven days.

## Supersession

Changing a frozen direct pin, source supplier, provenance field, first-party
license treatment, workflow pinning, or dependency-update policy requires a
new ADR or coordinator-approved planning amendment that explicitly supersedes
the affected decision.
