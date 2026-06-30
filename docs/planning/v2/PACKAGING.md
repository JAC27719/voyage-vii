# Voyage VII v2 Packaging and Provenance

This document freezes artifact naming, runtime locations, native source policy, and provenance.

## Version and artifact names

The product version is `0.1.0`, read from the repository-root `VERSION` file.

- Windows: `voyage-vii_0.1.0_windows-x86_64.zip`
- macOS Intel: `voyage-vii_0.1.0_macos-x86_64.app.zip`
- macOS Apple Silicon: `voyage-vii_0.1.0_macos-aarch64.app.zip`
- Linux: `voyage-vii_0.1.0_linux-x86_64.AppImage`

Package tools must derive the versioned names from `VERSION`; the literal names above are contract examples for the frozen version.

## Exact packaged runtime locations

- Windows ZIP: sibling `resources/runtime`
- macOS app: `Contents/Resources/resources/runtime`
- Linux AppDir: `usr/lib/voyage-vii/resources/runtime`

Each location contains the v1 manifest defined in `CONTRACTS.md` and:

```text
manifest.json
api/voyage-vii-api[.exe]
postgresql/...
tigerbeetle/tigerbeetle[.exe]
licenses/...
THIRD-PARTY-NOTICES.txt
```

## macOS sealing policy

Developer ID signing and notarization are excluded. For runnable smoke artifacts, ad-hoc identity `-` sealing is permitted and required:

1. ad-hoc seal nested Mach-O files leaf-first;
2. ad-hoc seal the app;
3. run `codesign --verify --deep --strict` before zipping and after extraction.

These artifacts are described as **ad-hoc sealed and unnotarized**, not unsigned. No signing secret, certificate, CI identity, entitlement expansion, or production-distribution claim is permitted.

## Linux baseline

Linux native builds use Ubuntu 24.04 x64 as the build and test baseline. The AppImage must support direct execution and `APPIMAGE_EXTRACT_AND_RUN=1`.

## Runtime sources

- PostgreSQL comes from the official PostgreSQL `18.4` source tarball and is built natively for each target.
- TigerBeetle comes from an official `0.17.7` release asset when one exists for the target. If no applicable asset exists, build the official `0.17.7` tag with Zig `0.14.1`.
- The API is always a first-party native build from the audited repository commit using Zig `0.15.2`. Its manifest source has `kind: first-party-build`, `url: null`, and the full audited Git commit as `revision`; its `licensePath` is `null`.

No worker may select an alternate supplier, unofficial binary distribution, substitute database build, or different source revision.

For PostgreSQL and TigerBeetle on every target, record:

- absolute official HTTPS URL and immutable revision or tag;
- downloaded source/archive SHA-256;
- build target and toolchain version;
- packaged output SHA-256;
- license path and combined-notice entry.

For the first-party API, record the full audited Git commit, build target and Zig toolchain, and packaged output SHA-256. The private repository intentionally has no license: the API has no license copy, is excluded from third-party notices, and uses `licensePath: null` and `source.url: null`. No worker may invent a license or URL.

`FEAS-003` proves these acquisition/build paths on all four targets and records the exact URLs, hashes, commands, and toolchains. `DESKTOP-004` consumes that approved evidence, stages third-party runtimes, and defines the first-party API component slot. Each native package task fills the API source commit and output hash, emits the final runtime manifest, and verifies the final packaged tree.

Generated runtimes and packages remain untracked. CI artifacts are retained for seven days.
