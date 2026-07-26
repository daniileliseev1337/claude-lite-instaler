# LLM Base Foundation Installer — implementation report

Date: 2026-07-26

## Verdict

- `FOUNDATION_SYNTHETIC: PASS`
- `EMPLOYEE_PACKAGE: BLOCKED_APPROVED_FOUNDATION_SOURCE`
- `INDEPENDENT_AUDIT: PENDING`
- `FULL_RELEASE: NOT_PASS`

The engine is verified only against injected fake-home roots. No live client
home, config, cache, credential store, login, subscription or device
installation was changed.

## Implemented surface

- manifest/inventory schema v2 for exactly Claude, Codex, and OpenCode;
- Kimi rejected as a standalone target;
- target-native managed path allowlists;
- OpenCode core, config, agent, metadata, skill and launcher destinations;
- target-isolated state, transactions, doctor, inventory and rollback;
- generic target-client version compatibility without model selection;
- explicit `consumer` default and optional `hub` role;
- strict `hub-to-consumer` manifest contract;
- consumer push, feedback upload, session upload and credentials all forced
  to `false`;
- credentials/auth-store paths excluded from the destination allowlist;
- deterministic rendered-file bridge from LLM-base to Foundation;
- cryptographic binding of the declared identity to the complete approved
  source tree;
- builder and runtime enforcement of the exact rendered active set;
- zero-write plan, exact install confirmation and conflict-safe apply;
- write-ahead install and rollback progress with interruption recovery;
- bounded safe doctor report and deterministic one-file offline bundle.

## Synthetic evidence

The latest interactive development run completed in both shells:

- PowerShell 7.6.1: 115/115 tests PASS;
- Windows PowerShell 5.1.26100.6725: 115/115 tests PASS;
- side-by-side Claude/Codex/OpenCode fake-home install: PASS;
- install and rollback interruption matrices plus byte-exact recovery: PASS;
- bundle determinism and external-process denylist: PASS;
- seeded secret scan: PASS;
- source-tree identity binding and rendered-target map rejection tests: PASS.

These 115/115 observations are not yet retained as immutable acceptance
evidence. The final handoff must cite a fresh acceptance attempt after the
final branch commit. A test run against uncommitted files is useful
development evidence, but it is not release evidence.

## Blocking source gate

The repositories still do not contain an approved immutable rendered source
with all required bindings:

- immutable git/tree or content-SHA identity;
- byte/hash inventory for every rendered file;
- per-component acceptance verdict and evidence IDs;
- exact supported target-client versions;
- independent PASSED review of that source/evidence package.

The full build repository is intentionally rejected as a package source when
it is located inside Claude, Codex, shared-agent or OpenCode live homes. A raw
clone into a client discovery path is not a substitute for target rendering.

Therefore the synthetic fixture is never promoted and no employee ZIP or
sidecar is created.

## Remaining release gates

1. Freeze and independently approve one rendered source per target.
2. Build each real package twice and compare deterministic ZIP/SHA-256.
3. Rerun dual-shell acceptance against those exact payloads.
4. Obtain fresh independent read-only audit.
5. Request separate permission for one live-device canary.
6. Compare real token usage on matched clean-chat prompts.
7. Only then consider a small employee pilot.
