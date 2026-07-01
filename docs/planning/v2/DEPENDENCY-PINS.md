# Voyage VII v2 Dependency Pins

These are the frozen direct dependency and toolchain pins as of 2026-06-29. Manifests must use exact constraints, lockfiles must be committed, and reproducible builds must reject resolution drift.

No worker may introduce an unlisted direct dependency or change a frozen direct pin without a coordinator-approved planning amendment or ADR. A listed dependency may be omitted when it is unused. Transitive dependencies are governed by committed lockfiles.

## Toolchains and native foundations

- Application Zig: `0.15.2`
- TigerBeetle-client Zig: `0.14.1`
- Rust: `1.96.0`
- Bun: `1.3.14`
- api.zig: `f9a287916ad0e34fda71c8e5b619c5774c8fbb45`
- TigerBeetle: `0.17.7`
- SQLite: authorized by ADR-0012; exact version, official archive URL, and
  archive hash are frozen by `FEAS-004` before `API-005` may begin.

Zig dependency declarations must resolve the exact listed revisions. The
SQLite build must use the official amalgamation archive frozen by `FEAS-004`
or stop for a coordinator amendment. No fork, substitute client, unofficial
binary, or unrelated SQLite compile-time feature selection is permitted without
a new ADR or planning amendment. Native source and release provenance must also
satisfy `PACKAGING.md`.

## NPM direct dependencies

Package manifests must use the exact version text shown, with no `^`, `~`, range, tag, or wildcard.

| Package | Version |
| --- | --- |
| `@tauri-apps/cli` | `2.11.4` |
| `@tauri-apps/api` | `2.11.1` |
| `solid-js` | `1.9.13` |
| `@solidjs/router` | `0.16.1` |
| `vite` | `8.1.0` |
| `vite-plugin-solid` | `2.11.12` |
| `typescript` | `6.0.3` |
| `tailwindcss` | `4.3.2` |
| `@tailwindcss/vite` | `4.3.2` |
| `eslint` | `10.6.0` |
| `typescript-eslint` | `8.62.1` |
| `eslint-plugin-solid` | `0.14.5` |
| `eslint-config-prettier` | `10.1.8` |
| `prettier` | `3.9.3` |
| `prettier-plugin-tailwindcss` | `0.8.0` |
| `eslint-plugin-prettier` | `5.5.6` |
| `vitest` | `4.1.9` |
| `@vitest/coverage-v8` | `4.1.9` |
| `@solidjs/testing-library` | `0.8.10` |
| `@testing-library/jest-dom` | `6.9.1` |
| `axe-core` | `4.12.1` |
| `jsdom` | `29.1.1` |

## Rust direct crates

Cargo manifests must use exact requirements in the form `=version`. Target-specific crates remain direct pins in the applicable target dependency section.

| Crate | Version |
| --- | --- |
| `tauri` | `2.11.3` |
| `tauri-build` | `2.6.3` |
| `tauri-plugin-single-instance` | `2.4.2` |
| `tauri-plugin-window-state` | `2.4.1` |
| `tauri-plugin-opener` | `2.5.4` |
| `serde` | `1.0.228` |
| `serde_json` | `1.0.150` |
| `tokio` | `1.52.3` |
| `reqwest` | `0.13.4` |
| `url` | `2.5.8` |
| `base64` | `0.22.1` |
| `subtle` | `2.6.1` |
| `anyhow` | `1.0.103` |
| `thiserror` | `2.0.18` |
| `tracing` | `0.1.44` |
| `tracing-subscriber` | `0.3.23` |
| `zeroize` | `1.9.0` |
| `rand` | `0.10.1` |
| `libc` | `0.2.186` |
| `windows` | `0.62.2` |
| `nix` | `0.31.3` |
| `tempfile` | `3.27.0` |

## Verification

Every dependency-owning task records:

1. the relevant manifest excerpts;
2. a clean-lockfile installation or build;
3. a search proving no direct range, tag, or unlisted dependency was introduced; and
4. the committed lockfile paths.
