# DESKTOP-001 — Tauri Desktop Foundation

**Implementer inference:** Low  
**Prerequisites:** `API-001` approved.

## Frozen inputs

Use every direct pin in `DEPENDENCY-PINS.md`, the product/origin/snapshot contracts in `CONTRACTS.md`, deadlines in `TIMEOUTS.md`, and runtime locations in `PACKAGING.md`. Do not choose versions, dependencies, scripts, origins, layouts, or shared module interfaces.

## Objective

Create the complete locked-down Tauri 2/SolidJS foundation, manifests, configuration, and buildable static seams without implementing runtime supervision or product features.

## Procedure

1. Scaffold Tauri 2, SolidJS, Vite, TypeScript, Tailwind, and Bun with the exact pins in `DEPENDENCY-PINS.md`, exact manifest constraints, and committed lockfiles.
2. Own and create all Cargo/package manifests, lockfiles, build scripts, HTML, TypeScript/Vite/Tailwind/ESLint/Prettier/Vitest configuration, base frontend entrypoints, Tauri configuration, and capabilities.
3. Declare every listed future direct Rust/NPM dependency and approved package script required by DESKTOP-002, DESKTOP-003, and PACKAGE-004 now; listed but unused dependencies may be omitted only when no approved future packet requires them.
4. Create buildable static `runtime` and `smoke` Rust modules, frontend app/module seams, and aggregate Rust/frontend test registration. Wire them from the shared entrypoints.
5. Configure product `Voyage VII`, version from root `VERSION`, and bundle ID `io.github.jac27719.voyage-vii`.
6. Configure a resizable `1100×720` main window, initially hidden until geometry restoration.
7. Initialize single-instance behavior before other plugins; a second launch restores and focuses the first.
8. Support system light/dark theme and remembered window state.
9. Expose only `get_runtime_snapshot` and pathless `open_logs`.
10. Deny JavaScript shell, filesystem, process, and arbitrary opener privileges.
11. Apply local-only CSP with Tauri IPC and the exact packaged/development origins from `CONTRACTS.md`.
12. Add a simple VII icon master and generated platform sizes.
13. Make Windows 11 x64 the only current build/runtime acceptance target while
    keeping target-bearing configuration and platform seams extensible.

Later desktop packets replace only their owned stub/module paths. If a later task would need a manifest, lockfile, shared configuration, shared entrypoint, or static-registration change, it must stop for coordinator reassignment.

## Acceptance evidence

- `rustc --version` reports `1.96.0`; `bun --version` reports `1.3.14`.
- `cargo fmt --check`, `cargo clippy --all-targets --all-features -- -D warnings`, and `cargo test --all-targets` pass.
- `bun install --frozen-lockfile`, the declared frontend typecheck/lint/format-check/test scripts, and the production build pass.
- Manifest searches prove exact requirements, no unlisted direct dependency, and static import/registration of runtime, smoke, and UI seams.
- `git diff --check` passes.
- Capability and CSP inventory.
- Single-instance and geometry-restoration notes.
- Light/dark screenshots.
- Native evidence is Windows 11 x64 only; any non-Windows cross-build is
  explicitly informational/non-support.

## Reviewer focus

Check plugin order, exact identity, permissions, CSP, arbitrary-path resistance, lockfiles, and absence of premature runtime or business logic.
