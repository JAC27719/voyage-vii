# Voyage VII v2 Packaging and Provenance

This document freezes current Windows artifact naming, runtime location, native
source policy, and provenance. macOS and Linux packaging is deferred under
[`future/`](future/) and does not gate this slice.

## Version and artifact names

The product version is `0.1.0`, read from the repository-root `VERSION` file.

- Windows: `voyage-vii_0.1.0_windows-x86_64.zip`

Package tools must derive the versioned names from `VERSION`; the literal names above are contract examples for the frozen version.

## Exact packaged runtime locations

- Windows ZIP: sibling `resources/runtime`

Each location contains the v1 manifest defined in `CONTRACTS.md` and:

```text
manifest.json
api/voyage-vii-api[.exe]
postgresql/...
tigerbeetle/tigerbeetle[.exe]
licenses/...
THIRD-PARTY-NOTICES.txt
```

## Runtime sources

- PostgreSQL comes from the official PostgreSQL `18.4` source tarball and is
  built natively for Windows x64.
- TigerBeetle comes from the official Windows x64 `0.17.7` release asset. If no
  applicable asset exists, build the official `0.17.7` tag with Zig `0.14.1`.
- The API is always a first-party native build from the audited repository commit using Zig `0.15.2`. Its manifest source has `kind: first-party-build`, `url: null`, and the full audited Git commit as `revision`; its `licensePath` is `null`.

No worker may select an alternate supplier, unofficial binary distribution, substitute database build, or different source revision.

For PostgreSQL and TigerBeetle on Windows x64, record:

- absolute official HTTPS URL and immutable revision or tag;
- downloaded source/archive SHA-256;
- build target and toolchain version;
- packaged output SHA-256;
- license path and combined-notice entry.

For the first-party API, record the full audited Git commit, build target and Zig toolchain, and packaged output SHA-256. The private repository intentionally has no license: the API has no license copy, is excluded from third-party notices, and uses `licensePath: null` and `source.url: null`. No worker may invent a license or URL.

`FEAS-003` proves these acquisition/build paths on native Windows 11 x64 and
records the exact URLs, hashes, commands, and toolchains. `DESKTOP-004`
consumes that approved evidence, stages the Windows third-party runtimes, and
defines the first-party API component slot. `PACKAGE-001` fills the API source
commit and output hash, emits the final runtime manifest, and verifies the
final packaged tree.

Generated runtimes and packages remain untracked. CI artifacts are retained for seven days.
