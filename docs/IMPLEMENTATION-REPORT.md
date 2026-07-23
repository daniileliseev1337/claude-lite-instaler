# Codex Foundation Mini-Installer — implementation report

Date: 2026-07-23

## Verdict

- `FOUNDATION_SYNTHETIC: PASS`
- `EMPLOYEE_PACKAGE: BLOCKED_APPROVED_FOUNDATION_SOURCE`
- `INDEPENDENT_AUDIT: NOT_RUN`
- `FULL_RELEASE: NOT_PASS`

The installer engine is implemented and verified only against injected
fake-home roots. No live vendor home, config, cache, credential store or device
installation was changed.

## Frozen authority

- Design SHA-256:
  `86765B00010EE6698259B542E6BF042C5D304F8D04F40F10B3A215F30A62DBDD`
- Plan SHA-256:
  `C6527D961C42D7A625F28792026E8DEE4DD705473B2468C775E6CB37C0AEED53`
- Permission nonce:
  `93d25250083404f3066860ac3d49a6f4656b6751d78b07e19995521c9aa4df30`
- Permission receipt SHA-256:
  `10D17B34B8896B30525EE6B9250DBB645C1D47E34E7DC39CF2EB3E4BA575234F`

## Implemented surface

- strict bounded UTF-8 JSON and closed manifest/inventory contracts;
- portable path, Unicode, reserved-name, collision and reparse rejection;
- deterministic active/quarantine classifier and package tree;
- zero-write `plan` with compatibility, ownership and conflict checks;
- journaled current-user transaction, snapshot, doctor and inventory;
- byte-exact rollback with conflict-safe interrupted staging cleanup;
- five-command CLI: `plan`, `install`, `doctor`, `inventory`, `rollback`;
- deterministic one-file offline bundle with AST denylist;
- safe doctor JSON and offline employee HTML guide.

## Synthetic evidence

Acceptance attempt
`14d2d13b7513f33f07956f04336a88d412dca45189f8bc897cb34020dcc82cc4`
was run against implementation commit
`6c792eb76ff7c416bad66d99cc6648fcdb759231`.

- PowerShell 7.6.1: 96/96 tests PASS
- Windows PowerShell 5.1.26100.6725: 96/96 tests PASS
- bundle determinism: PASS
- security matrix: PASS
- full fake-home E2E and failure injection: PASS
- seeded secret scan: PASS
- generated bundle SHA-256:
  `391c3a93fc9a7bdf0bde95324a376e969bba147df3dd066f6a8eed593e348080`
- synthetic manifest SHA-256:
  `10bf21163471996e08705ed3351b81329861b953cf38189efc60077f440cdb13`

The final handoff must cite a fresh acceptance attempt bound to the final
repository commit, because this report itself changes that commit.

## Blocking source gate

The project-local search found no artifact satisfying all required fields:

- approved immutable `git` or `content-sha256` source identity;
- byte/hash inventory for every source file;
- per-component acceptance verdict and evidence IDs;
- exact supported Codex version tuple;
- independent `PASSED` for that source/evidence package.

The older safe skills inventory contains 135 file rows only. It has no closed
component verdict/evidence/source-identity contract. The older DANIILPC
acceptance explicitly marks canonical source freshness `FAIL/BLOCKER`; it also
forbids treating the live home as rollout source.

Therefore the synthetic fixture is never promoted, and no employee ZIP or
sidecar is created.

## Remaining release gates

1. Produce and independently approve an immutable rendered Codex-base source
   plus frozen acceptance inventory.
2. Build the real package twice, compare deterministic ZIP/SHA-256, and rerun
   this acceptance runner against that payload.
3. Obtain fresh independent read-only audit. The current permission explicitly
   denies paid/model runtime, so this implementation session cannot claim it.
4. Request separate exact permission for project package evidence.
5. Request separate DANIILPC canary write permission.
6. Only after a clean canary may a 1–2 employee pilot be considered.
