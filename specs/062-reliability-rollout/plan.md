# Plan 062 — branch topology, merge order, gates, rollback

## 1. Branch topology (all local; nothing pushed)

Base for every product branch is `origin/main` (`616afdd`, 1.2.11). Always `git fetch` and compare with `gh api repos/xP3ta/hermes-console/compare/<base>...main` before starting: the first worktree was created on stale 1.2.10 (207 files apart).

| Branch | Item | Base | Depends on |
|---|---|---|---|
| `fix/android-share-provisional-draft` | F1 | main | — |
| `fix/android-share-link-text-only` | F2 | main | — (Kotlin only) |
| `fix/console-scroll-button-behind-pills` | F6 | main | — (re-indents the bottom overlay in `chat_screen.dart`) |
| `fix/console-process-complete-visible` | F7 | main | — |
| `fix/console-subagent-pill-stuck` | F5 | main | — |
| `fix/console-terminal-authority` | F3 | main | — |
| `fix/console-watchdog-never-fails-turn` | F4 | terminal-authority | F3 |
| `fix/console-reasoning-and-sidecar-parity` | F9 | combined | F7 (shares the local-cache display-kind rule) |
| `fix/console-live-turn-overwrites-bubble` | F8 | combined | F7 (its regression asserts the process row) |
| `feat/console-background-work-visibility` | F10 | combined | F3, F5 (reads their authoritative signals) |
| `feat/console-notifications-design` | F11 | combined | F6 (bottom stack) |
| `test/reliability-combined-1212` | integration | main + all merges | **test-only, never a PR** |

`fix/console-reasoning…` and `fix/console-live…` were cut from the combined branch: before opening PRs, **re-create each as a single cherry-picked commit on top of its dependency chain** (or stack the PRs) so each PR diff is only its own change.

## 2. Proposed PR / merge order (smallest blast radius first)

1. F2 (Kotlin only) → 2. F1 → 3. F6 → 4. F7 → 5. F5 → 6. F3 → 7. F4 → 8. F9 → 9. F8 → 10. F10 → 11. F11.
Rationale: independent and low-risk items land first and shrink the diff the risky ones (F3/F4/F10 change liveness semantics) are rebased onto. After **each** merge the remaining branches are rebased/merged forward and re-verified (gate G1) before the next.

## 3. Conflict and interaction hotspots

| Hotspot | Touched by | Handling |
|---|---|---|
| `lib/core/screens/chat_screen.dart` bottom overlay | F6, F4 (`reassureAfter`), F10, F11 | F6 re-indents the block; resolve by keeping F6's structure and re-adding the other edits (done once for F4). F10/F11 must only add inside the new column. |
| `lib/core/services/active_chat_service.dart` | F3, F4, F5, F8, F9, F10 | regions are distinct (roster probe / watchdog / subagent roster / external-turn insert / normalisation / status.update). Any merge → run `terminal_authority_test`, `active_chat_service_test`, `active_chat_resume_snapshot_test`, `desktop_disconnect_recovery_test`. |
| `session_reconciler.dart`, `local_transcript_store.dart`, `chat_render_projection.dart` | F7, F9, F8 | `cacheableDisplayKinds` and `_isStructuredUserEvent` are deliberately narrow (`process_complete` only); keep the guard tests. |
| `lib/l10n/app_*.arb` | F4, F7, F10, F11 | append-only keys; run `flutter gen-l10n` after every merge (stale generated getters look like compile errors). |
| **Semantic interaction: F3 × F4 × F10** | all decide "is the turn/session working" | one truth per layer: F3 = authoritative absence closes a turn; F4 = silence is a hint only; F10 = activity model reads F3/F5 signals and adds hysteresis. Interaction tests + device scenarios D-03/D-04/D-11 (test-matrix) are mandatory after any of the three changes. |

## 4. Verification gates

- **G0 (per branch, before commit)**: targeted tests for touched areas, `flutter analyze --no-pub`, `git diff --check`, gitleaks on changed files, grep for personal paths/IPs/tokens, **no pure-format hunks** (tools reformat pre-existing lines — check and revert), causal RED recorded before the fix.
- **G1 (integration)**: merge into `test/reliability-combined-1212`, `flutter gen-l10n`, analyze, then ONE full `flutter test --no-pub --concurrency=1` alone on an idle machine (parallel suites cause flaky failures). Any failing test is re-run in isolation and compared with the pure-main behaviour before being called flaky.
- **G2 (device)**: build a `--profile --flavor qa --target-platform android-arm64` APK (debug-signed, same key as the installed QA app), bump `--build-number`, `adb install -r`, run `test-matrix.md`, keep captures.
- **G3 (A/B)**: for any "regression or not?" question install the pure-main profile build with a higher build number and repeat the same scenario (done for F8/F10 — both pre-existing).
- **G4 (owner)**: owner tests on the Pixel; explicit go-ahead required.
- **G5 (PR)**: PRs opened only after G4, English text, CI green, one PR per item, in the order of §2.
- **G6 (merge)**: only on explicit owner approval; after each merge repeat G1–G2 on the next branch.

## 5. Rollback

- One item = one commit/PR → `git revert` of that commit alone must leave the rest working (SC-07). Verified by reverting each item in a scratch worktree and running the targeted suites before opening its PR.
- Behaviour changes with a product decision (F9 shows reasoning, plegado) are isolated to one render path so they can be switched off in one place.
- Device safety: never uninstall the QA package (it holds pairing/data); the original 1.2.11-qa APK (9009) and the pure-main profile build (9011) are kept for comparison. Downgrades are impossible (versionCode), so every test build gets a higher `--build-number`.

## 6. Release path (1.2.12)

Owner-decided. Signed builds use the owner's upload key through `tool/release/double_build.sh` (key path only, never read); public texts in English; thank contributors; only after G4+G6. The upstream Hermes checkout is 184 commits behind: re-check Desktop's liveness/reconnect/media code against newer upstream before release.
