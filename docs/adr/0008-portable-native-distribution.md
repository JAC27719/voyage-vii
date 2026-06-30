# ADR-0008: Portable Native Distribution

- Status: Accepted
- Date: 2026-06-29

## Context

Packaging is part of the runtime architecture because every supported desktop
must contain and safely launch the same pinned API and database components.

## Decision

Version `0.1.0` is read from the repository-root `VERSION` file. The first
slice produces a Windows x64 portable ZIP, separate zipped Intel and Apple
Silicon macOS app bundles, and a Linux x64 AppImage. Exact target triples,
artifact names, packaged runtime locations, tree layout, manifest schema, and
native provenance are governed by
[PACKAGING.md](../planning/v2/PACKAGING.md) and
[CONTRACTS.md](../planning/v2/CONTRACTS.md).

Every distributable is built and smoke-tested on its native platform. Ubuntu
24.04 x64 is the Linux build/test baseline, and the AppImage supports direct
execution and `APPIMAGE_EXTRACT_AND_RUN=1`.

macOS runnable smoke artifacts are ad-hoc sealed with identity `-`: nested
Mach-O files leaf-first, then the app, followed by strict verification before
zipping and after extraction. They are described as ad-hoc sealed and
unnotarized. Developer ID signing, notarization, installers, auto-update, and
production publishing are excluded.

Bootstrap tooling is project-local and never silently performs privileged
installation.

## Rejected alternatives

- Declaring completion from cross-compilation or a subset of the four targets.
- Installers or production-distribution claims in the first slice.
- Calling macOS smoke artifacts unsigned or notarized.
- Privileged installation without an explicit user action.
- Packaging native components without the frozen manifest and provenance.

## Consequences

All four portable artifacts gate completion. Native CI jobs may use the frozen
90-minute budget, and artifacts are retained seven days. The package tree
contains the API, PostgreSQL, TigerBeetle, applicable licenses, notices, and
version-1 runtime manifest at the exact platform location.

## Supersession

Changing supported targets, artifact forms, native test requirements, runtime
locations, macOS sealing, Linux baseline, or first-slice distribution scope
requires a new ADR that explicitly supersedes this record.
