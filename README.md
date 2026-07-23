# Codex Foundation Mini-Installer

Offline, current-user installer for the approved Codex Foundation scope.

This repository is independent from the project documentation repository. It
does not read live vendor homes as package source and all tests use injected
roots below `.work/`.

Current release status: `FOUNDATION_SYNTHETIC_PASS`;
`FULL_RELEASE_NOT_PASS`.

The synthetic verdict covers only isolated fake-home acceptance. It does not
authorize a DANIILPC canary or an employee rollout.

Real employee package status: `BLOCKED_APPROVED_FOUNDATION_SOURCE`. The
repository does not contain an approved immutable rendered Codex-base source
and frozen component evidence inventory, so no production ZIP is published.

## Development commands

```powershell
pwsh -NoProfile -File .\tests\run-tests.ps1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
pwsh -NoProfile -File .\tools\bundle-installer.ps1 -OutputPath .\.work\install.ps1
pwsh -NoProfile -File .\tools\run-foundation-acceptance.ps1
```

Employee operations are documented in
[`docs/FOUNDATION-OPERATIONS.md`](docs/FOUNDATION-OPERATIONS.md).
The offline visual guide is
[`docs/codex-foundation-dashboard.html`](docs/codex-foundation-dashboard.html).
