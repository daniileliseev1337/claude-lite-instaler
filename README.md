# Codex Foundation Mini-Installer

Offline, current-user installer for the approved Codex Foundation scope.

This repository is independent from the project documentation repository. It
does not read live vendor homes as package source and all tests use injected
roots below `.work/`.

Current release status: `NOT_BUILT`.

## Development commands

```powershell
pwsh -NoProfile -File .\tests\run-tests.ps1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
pwsh -NoProfile -File .\tools\bundle-installer.ps1 -OutputPath .\.work\install.ps1
```

Employee operations are documented in
[`docs/FOUNDATION-OPERATIONS.md`](docs/FOUNDATION-OPERATIONS.md).
