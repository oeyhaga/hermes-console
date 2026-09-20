# Tasks 062 — ordered checklist

Legend: `[x]` done · `[~]` in progress · `[ ]` todo. Owners: **Sol** = `claude-multi` GPT worker, **Sonnet** = design agent, **Me** = orchestrator.

## Phase 0 — Close what is in flight
- [x] T001 F1–F9 committed on their own branches; gitleaks + analyze + diff-check clean (Me)
- [x] T002 Combined branch merged, analyze clean, ONE full suite alone: 6013 passed, 0 failed (Me) — re-run after F8/F9/F10/F11 merge
- [~] T003 F10 background-work visibility: activity model → in-chat indicator → Home/list chip → backend-started turns (Sol)
- [~] T004 F11 notifications restyle + notice placement, Desktop as reference (Sonnet)
- [~] T005 F12 media research → plan (Sol); F13 cross-device notification research → plan (Sol)
- [~] T006 D-12/D-12b app force-closed mid-turn (Me, on device now)

## Phase 1 — Integrate safely (per plan §2 order)
- [ ] T010 Review each Sol/Sonnet diff myself (production hunks, format noise script + re-verify, gitleaks) before commit
- [ ] T011 Merge into `test/reliability-combined-1212`, `flutter gen-l10n`, analyze
- [ ] T012 Interaction tests for F3×F4×F10 (turn ended + background child; silence hint + roster absence; hysteresis under polling gaps) — write RED first
- [ ] T013 Full suite alone on the combined branch → 0 failures (any failure re-run alone and on pure main)
- [ ] T014 Revert-one-item check for each branch in a scratch worktree (SC-07)

## Phase 2 — Device matrix (`test-matrix.md`)
- [ ] T020 Build profile APK (new `--build-number`), install, confirm `versionCode`
- [ ] T021 Run D-01…D-15 with contact sheets; store evidence under the scratch QA folder
- [ ] T022 A/B against pure 1.2.11 for every ❌/⏳ that could be pre-existing
- [ ] T023 Promote the harness scripts to `tool/qa/device/` (own PR, no product code)

## Phase 3 — Follow-up features (after Phase 2 is green)
- [ ] T030 F12 media: card+preview+download per type (image/video/audio/document), from a host path, real content loading, states, reopen persistence — Desktop parity, security review
- [ ] T031 F13 cross-device notifications: implement the recommended option from the research; test on phone AND tablet
- [ ] T032 F14 fixes discovered by D-12/D-12b (catch-up on launch)
- [ ] T033 Live commentary classification if the gateway starts forwarding the item phase (backend dependency — report only)

## Phase 4 — PRs (only after owner go)
- [ ] T040 Cut clean single-commit branches on top of the dependency chain (fix/console-reasoning…, fix/console-live… were cut from combined)
- [ ] T041 Open PRs in plan §2 order, English text, CI green; owner tests each on the Pixel; explicit go before every merge
- [ ] T042 After each merge: rebase the next branch, repeat G1–G2

## Phase 5 — Release 1.2.12 (owner decision)
- [ ] T050 Re-check Desktop reference vs newer upstream; changelog; signed build via the release scripts; owner uploads

## Guards for every task
Never uninstall the QA app · never read secrets or `key.properties` · nothing pushed/merged by the agent · one writer per worktree · ≤3 parallel agents · an invalid test run is not a pass.
