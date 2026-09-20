# Spec 062 — Console reliability: integration and safe rollout

**Status**: active · **Date**: 2026-09-20 · **Base**: `origin/main` = release 1.2.11 (`616afdd`) · **Target**: 1.2.12
**Supersedes for rollout purposes**: spec 061 (its addendum stays valid for the technical slices).

## 1. Problem

Long coding sessions from Hermes Console are unreliable in ways Hermes Desktop is not: false "Modelo sin respuesta", phantom "working" states, content that disappears, no visible sign that background work or a subagent is running, media that never shows, no cross-device notifications. A dozen independent fixes are now in flight. **The risk is no longer any single bug — it is that many correct changes interact badly, or are not really applied on the device.** This spec defines what "done" means and how we prove it.

## 2. Guiding rules (owner-set, non-negotiable)

1. **Hermes Desktop is the reference.** Read its source (`~/.hermes/hermes-agent/apps/desktop/src`) and replicate it unless Console cannot (mobile constraint) — deviations are written down with the reason.
2. **Truthful activity, both directions.** If Hermes is working (foreground turn, subagent, background process, backend-started turn) Console shows it; if nothing is running Console never shows "working". A state never flaps between adjacent polls.
3. **No content loss, and content type is visible** (reply, reasoning, system notice, tool, media).
4. **Media really loads**: real thumbnail/preview immediately, honest progress and error+retry, survives reopening the chat, save/share action. Never a raw `MEDIA:` tag, blank box or half-built card.
5. **Closing the app must not hurt**: work continues on the backend and, on reopening, the chat is as if nothing happened.
6. **Nothing merges before the owner tests on the Pixel** and gives an explicit go. No push/merge/PR-merge by the agent. Public text in English.

## 3. Scope (work items)

| ID | Item | State |
|---|---|---|
| F1 | Android Share: empty `android-share` session is an unpersisted draft (no 4007) | done, device ✅ |
| F2 | Android Share: paste only the shared link, no title/thumbnail | done, device ✅ |
| F3 | Terminal authority: `session.active_list` closes a dead turn | done, device ❌ untested |
| F4 | Watchdog never fails a turn on silence (5 min hint) | done, device ✅ |
| F5 | Subagent pill settles only on authoritative absence | done, device ❌ untested |
| F6 | Scroll-to-bottom button above the pills | done, device ✅ |
| F7 | `process_complete` rows shown | done, device ✅ (on reload) |
| F8 | Backend-started turn appended, not overwriting | done, device ⏳ |
| F9a | Reply text from `codex_message_items` (privacy-neutral) | in progress (Sol) |
| F9b | Show durable reasoning as a collapsed block (reverses the "mobile never carries reasoning" privacy contract) | **parked — owner decision** |
| F10 | Background-work visibility (one activity model: chat + Home/list) | in progress (Sol) |
| F11 | In-app notifications restyle + floating-notice placement | in progress (Sonnet, Desktop as reference) |
| F12 | Media delivery (image/video/audio/document, download from a host path) | research (Sol) |
| F13 | Cross-device notifications (tablet→phone, Desktop, TUI) | research (Sol) |
| F14 | App fully closed → state restored, work continues | device test now; fixes as found |

Non-goals: changing Hermes Agent/Desktop/Gateway; backend TTFB limits; long-session token bloat (recommend fresh sessions).

## 4. Success criteria (all device-verifiable unless stated)

- **SC-01** Every F-item passes its row in `test-matrix.md` on the Pixel, on the combined build.
- **SC-02** For every claimed regression/no-regression there is an A/B against the pure 1.2.11 build.
- **SC-03** Full test suite on the combined branch: 0 failures, run alone on an idle machine.
- **SC-04** `flutter analyze` clean, `git diff --check` clean, gitleaks clean, no personal path/IP/token in any diff, no pure-format hunks in unrelated lines.
- **SC-05** Force-closing the app mid-turn and reopening after ≥60 s shows the same conversation with no lost or duplicated content and the correct working/finished state.
- **SC-06** No floating notice intersects the composer, the keyboard, the dock or another notice in any tested state (tested by rect assertions and by device captures).
- **SC-07** Each fix is its own commit/PR and can be reverted alone without breaking the others.
