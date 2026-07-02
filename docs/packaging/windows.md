# Windows Portable ZIP

PACKAGE-001 produces the current Voyage VII distributable:

```text
voyage-vii_0.1.0_windows-x86_64.zip
```

The ZIP is portable and does not install system services. It requires Windows
11 x64 and the Microsoft Edge WebView2 runtime.

## Build

Run from the repository root:

```powershell
pwsh -NoProfile -File tools/package/windows/build-windows-zip.ps1
```

Use `-Offline` after the runtime-staging cache is warm. The script uses:

- root `VERSION` for the artifact name;
- Bun `1.3.14` for the desktop frontend;
- Rust `1.96.0` for the Tauri host;
- pinned Zig `0.15.2` at
  `spikes/api-pg/toolchain/zig-x86_64-windows-0.15.2/zig.exe`;
- approved TigerBeetle `0.17.7` C client inputs from FEAS-002, with
  `tb_client.h` SHA-256
  `3ad1dd26fb67f3c89c971072cf22ad4a833971f6a40947ca562db2685587964d`
  and `tb_client.lib` SHA-256
  `1edf28ac840cc44ae98a8782d066da525df8257a6c90df921164d706ff232c02`;
- the verified runtime staging pipeline from `tools/runtime-staging`;
- the approved PACKAGE-004 smoke harness for extracted-package validation.

If the FEAS-002 local evidence directory is unavailable, pass
`-TigerBeetleClientLib` and `-TigerBeetleClientInclude` pointing at an approved
official `0.17.7` C client build.

## Outputs

Generated outputs are ignored by Git:

```text
tools/package/windows/artifacts/
tools/package/windows/build/
tools/package/windows/reports/
```

The package root inside the ZIP is:

```text
Voyage VII.exe
resources/runtime/manifest.json
resources/runtime/api/voyage-vii-api.exe
resources/runtime/sqlite/...
resources/runtime/tigerbeetle/tigerbeetle.exe
resources/runtime/licenses/...
resources/runtime/THIRD-PARTY-NOTICES.txt
```

The script writes `last-run.json` and `last-run.md` reports with artifact hash,
PE inventory, package file hashes, API source revision, and smoke summary.

## Validation

The build script validates:

- Windows x64 PE machine values for the desktop, API, and TigerBeetle binaries;
- Windows GUI subsystem on the packaged desktop executable;
- clean tracked package inputs before stamping the API source revision;
- approved FEAS-002 TigerBeetle C client header and library hashes;
- final runtime manifest v1 with the first-party API revision and SHA-256;
- absence of PDBs, source maps, caches, source build metadata, and
  `manifest.inputs.json`;
- ZIP contents and SHA-256 sidecar;
- extraction from a temporary path containing spaces and non-ASCII characters;
- PACKAGE-004 fresh and retained smoke startup against the exact ZIP.

The desktop executable subsystem is patched in the packaged copy to avoid a
visible console window. API and TigerBeetle child-process creation visibility is
governed by runtime source outside PACKAGE-001's owned paths.
