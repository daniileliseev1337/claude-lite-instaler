# LLM Base Foundation Installer

Offline, current-user installer engine for target-bound LLM-base packages on
Windows 10/11.

Supported targets are exactly `claude`, `codex`, and `opencode`. Kimi is not a
standalone target; it can only be selected as a provider model inside OpenCode.
The installer never selects or silently replaces a model.

Current release status: `FOUNDATION_SYNTHETIC_PASS`;
`FULL_RELEASE_NOT_PASS`.

The synthetic verdict covers isolated fake-home acceptance in PowerShell 7 and
Windows PowerShell 5.1. It does not authorize a live-device canary or employee
rollout.

Real employee package status: `BLOCKED_APPROVED_FOUNDATION_SOURCE`. This
repository does not contain an independently approved immutable rendered
LLM-base source plus frozen per-component evidence inventory, so no production
ZIP is published.

## Distribution contract

- one package is bound to one target;
- Claude, Codex, and OpenCode packages can be installed side by side;
- `consumer` is the default role; `hub` requires an explicit CLI choice;
- sync direction is strictly `hub-to-consumer`;
- consumer push, feedback upload, and session upload are disabled;
- credentials and auth stores are never package destinations;
- declared source identity is recomputed from the complete approved source
  tree;
- the exact active set is enforced by both builder and runtime;
- the full build repository must not be installed inside a native client home.

The rendered-file bridge is
[`contracts/foundation/rendered-target-map.json`](contracts/foundation/rendered-target-map.json).
The release procedure and fail-closed source gate are explained in
[`docs/RENDERED-SOURCE-CONTRACT.md`](docs/RENDERED-SOURCE-CONTRACT.md).

## Development commands

```powershell
pwsh -NoProfile -File .\tests\run-tests.ps1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
pwsh -NoProfile -File .\tools\bundle-installer.ps1 -OutputPath .\.work\install.ps1
pwsh -NoProfile -File .\tools\run-foundation-acceptance.ps1
```

Employee operations are documented in
[`docs/FOUNDATION-OPERATIONS.md`](docs/FOUNDATION-OPERATIONS.md).
The offline visual guide remains at
[`docs/codex-foundation-dashboard.html`](docs/codex-foundation-dashboard.html)
for compatibility with earlier links.
