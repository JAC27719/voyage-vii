# PACKAGE-005 — Repair Packaged Desktop Runtime Launch

**Implementer inference:** Low
**Prerequisites:** `PACKAGE-001` approved.

## Frozen inputs

Use the Windows portable ZIP layout from `PACKAGING.md`, the runtime process
and token contracts from `CONTRACTS.md`, and the existing package smoke harness
without introducing installer formats or new runtime dependencies.

## Objective

Fix the normal user-facing packaged desktop startup path so the desktop shell
launches the bundled API from the extracted ZIP and the system-status UI can
advance past pending component state.

## Procedure

1. Resolve the packaged runtime root from the extracted executable directory's
   `resources/runtime` layout before falling back to Tauri resource paths.
2. Keep the API executable, runtime root, data root, allowed origin, handshake,
   and shutdown behavior unchanged.
3. Add focused tests for the portable runtime layout and required runtime
   files.
4. Rebuild the Windows ZIP and manually launch the packaged executable long
   enough to confirm the bundled API starts.
5. Report the ZIP SHA-256 and process-cleanup result.

## Acceptance evidence

- Focused desktop runtime tests.
- Rust format check.
- Windows ZIP rebuild with PACKAGE-004 smoke.
- Manual packaged-launch check showing the API process starts and no
  Voyage VII or TigerBeetle process remains after shutdown.
- Registry validation and `git diff --check`.

## Reviewer focus

Verify the fix uses the real ZIP layout, does not hide missing runtime files,
preserves token/process containment behavior, and blocks CI if packaged launch
is still unverified.
