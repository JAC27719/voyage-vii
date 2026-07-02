# DOC-002 Command Verification

Host: Windows 11 x64.

All commands below are documented in the development, operations, or packaging
runbooks. Output roots are local evidence paths; token, user path, and runtime
diagnostics are redacted by the scripts where applicable.

Evidence root:

```text
C:\Users\jcane\AppData\Local\Temp\voyage-vii-doc-002-2a21f0f30a1c454b945045d7e8f4ea70
```

| Command | Result | Evidence |
| --- | --- | --- |
| `pwsh -NoProfile -File tools/doctor/voyage-doctor.ps1` | pass | `doctor.stdout.log`, `doctor.stderr.log`, `doctor.exit.txt` |
| `pwsh -NoProfile -File tools/doctor/voyage-doctor.ps1 -Json` | pass | `doctor-json.stdout.log`, `doctor-json.stderr.log`, `doctor-json.exit.txt` |
| `pwsh -NoProfile -File scripts/bootstrap/bootstrap.ps1 -Profile compose` | pass | `bootstrap-compose.stdout.log`, `bootstrap-compose.stderr.log`, `bootstrap-compose.exit.txt` |
| `pwsh -NoProfile -File scripts/bootstrap/bootstrap.ps1 -Profile desktop` | pass | `bootstrap-desktop.stdout.log`, `bootstrap-desktop.stderr.log`, `bootstrap-desktop.exit.txt` |
| `pwsh -NoProfile -File scripts/bootstrap/bootstrap.ps1 -Profile packaging -Offline` | pass | `bootstrap-packaging.stdout.log`, `bootstrap-packaging.stderr.log`, `bootstrap-packaging.exit.txt` |
| `pwsh -NoProfile -File scripts/bootstrap/bootstrap.ps1 -Profile all -Offline` | pass | `bootstrap-all.stdout.log`, `bootstrap-all.stderr.log`, `bootstrap-all.exit.txt` |
| `$env:VOYAGE_VII_API_IMAGE = "voyage-vii-api:0.1.0@sha256:0000000000000000000000000000000000000000000000000000000000000000"; docker compose --file compose.yaml config --quiet` | pass | `compose-config-synthetic.stdout.log`, `compose-config-synthetic.stderr.log`, `compose-config-synthetic.exit.txt` |
| `$env:VOYAGE_VII_API_IMAGE = "voyage-vii-api:0.1.0@sha256:0000000000000000000000000000000000000000000000000000000000000000"; pwsh -NoProfile -File scripts/compose/stop.ps1` | discrepancy | `compose-stop-with-pin.stderr.log` shows Docker Desktop Linux engine pipe access denied on this host; command shape and image interpolation are correct, but Docker engine access was unavailable to this operator session. |
| `pwsh -NoProfile -File scripts/test/test.ps1 -Command unit` | discrepancy | `test-unit.stderr.log`; preserved harness root `C:\Users\jcane\AppData\Local\Temp\voyage-vii-tests\unit-cf34a4eaba6c4c179b0819cbe74192ca`; desktop lint failed because ESLint `10.6.0` called `util.styleText`, unavailable in the active Node `20.10.0` runtime. |
| `pwsh -NoProfile -File scripts/test/test.ps1 -Command managed-smoke` | pass | `test-managed-smoke.stdout.log`, `test-managed-smoke.stderr.log`, `test-managed-smoke.exit.txt` |
| `pwsh -NoProfile -File scripts/test/test.ps1 -Command managed-failure` | pass | `test-managed-failure.stdout.log`, `test-managed-failure.stderr.log`, `test-managed-failure.exit.txt` |
| `pwsh -NoProfile -File scripts/test/test.ps1 -Command package-smoke` | pass | `test-package-smoke.stdout.log`, `test-package-smoke.stderr.log`, `test-package-smoke.exit.txt` |
| `pwsh -NoProfile -File tests/hardening/run-hardening.ps1 -Command all` | pass | `hardening-all.stdout.log`, `hardening-all.stderr.log`, `hardening-all.exit.txt` |
| `pwsh -NoProfile -File tests/package-smoke/run-tests.ps1` | pass | `package-smoke-fixtures.stdout.log`, `package-smoke-fixtures.stderr.log`, `package-smoke-fixtures.exit.txt` |
| `pwsh -NoProfile -File tests/runtime-staging/run-tests.ps1` | pass | `runtime-staging-fixtures.stdout.log`, `runtime-staging-fixtures.stderr.log`, `runtime-staging-fixtures.exit.txt` |
| `pwsh -NoProfile -File tools/package/windows/build-windows-zip.ps1 -Offline` | discrepancy | `package-build-offline.stderr.log`; desktop frontend build failed in this operator session with `EPERM: operation not permitted, uv_spawn 'C:\WINDOWS\system32\cmd.exe'` and a native Tailwind binding load error. PACKAGE-001 remains the integrated successful package-build evidence. |
| `pwsh -NoProfile -File tools/package-smoke/voyage-package-smoke.ps1 -ExtractedRoot C:\Users\jcane\projects\hydra\tools\package\windows\build\package-root` | pass | `package-smoke-existing-root.stdout.log`, `package-smoke-existing-root.stderr.log`, `package-smoke-existing-root.exit.txt` |
