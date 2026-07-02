# Packaging Runbook

The current distributable is the Windows 11 x64 portable ZIP:

```text
voyage-vii_0.1.0_windows-x86_64.zip
```

There is no installer, production signing, notarization, or auto-update in this
slice. Native macOS and Linux packages are deferred under
[future planning](../planning/v2/future/README.md).

## Build

Run from the repository root after the runtime-staging cache and approved native
inputs are available:

```powershell
pwsh -NoProfile -File tools/package/windows/build-windows-zip.ps1 -Offline
```

If the approved FEAS-002 TigerBeetle C client evidence directory is unavailable,
pass `-TigerBeetleClientLib` and `-TigerBeetleClientInclude` pointing at an
approved official `0.17.7` C client build.

## Smoke Extracted ZIP

After extracting the ZIP to an absolute directory, run:

```powershell
pwsh -NoProfile -File tools/package-smoke/voyage-package-smoke.ps1 -ExtractedRoot <absolute extracted package root>
```

The package smoke harness validates the portable layout, runtime manifest,
handshake/status contract, fresh startup, retained startup, and clean shutdown.

## Layout

The ZIP contains:

```text
Voyage VII.exe
resources/runtime/manifest.json
resources/runtime/api/voyage-vii-api.exe
resources/runtime/sqlite/...
resources/runtime/tigerbeetle/tigerbeetle.exe
resources/runtime/licenses/...
resources/runtime/THIRD-PARTY-NOTICES.txt
```

Generated package outputs are ignored by Git under:

```text
tools/package/windows/artifacts/
tools/package/windows/build/
tools/package/windows/reports/
```

See the detailed [Windows packaging report](windows.md).
