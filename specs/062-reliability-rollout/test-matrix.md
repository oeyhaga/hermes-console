# Device test matrix (Pixel 9 Pro, QA package `dev.xpetalab.hermesconsole.qa`)

Harness (currently in the session scratchpad — promote to `tool/qa/device/` before PRs): `qa.sh` (adb helpers), `t_*.sh` scenarios, `sheet.py` (contact sheets). Method: seed the composer with a `SEND` intent (no typing), tap send at (844,1921) with the keyboard closed, capture with `screencap`. Install: profile build, higher `--build-number`, `adb install -r`, confirm `versionCode`. An invalid run (e.g. the prompt was never sent) is recorded as **invalid**, not as pass.

Legend: ✅ passed with evidence · ❌ failed · ⏳ to run · A/B = compared with pure 1.2.11 (build 9011).

| ID | Item | Scenario | Expected | Result |
|---|---|---|---|---|
| D-01 | F1 | Share text from adb `SEND` into an empty android-share session | text in composer, no error banner, no 4007 in logcat | ✅ |
| D-02 | F2 | Share link + subject + thumbnail (`-d`/grant) | composer = URL only, no attachment | ✅ |
| D-02b | F2 | Share text+subject / image / `.txt` file | subject+text unchanged / image attaches / file attaches | ✅ |
| D-03 | F3 | Start a long turn; drop the connection (Wi-Fi off/on **only if adb is not on Wi-Fi**, otherwise use a dashboard restart by the owner) | after ≤ ~10 s the turn stops saying "working", no error bubble | ⏳ |
| D-04 | F4 | Foreground `sleep 130` | never "Modelo sin respuesta"; pill shows elapsed time; completes | ✅ |
| D-04b | F4 | ≥5 min of real silence | non-terminal "no recent activity" hint, no failure | ⏳ |
| D-05 | F5 | Delegate to a subagent, kill the parent turn | pill stops spinning only when the roster confirms absence | ⏳ |
| D-06 | F6 | Long transcript scrolled up while pill visible | arrow above the pill, tappable, scrolls to bottom | ✅ |
| D-07 | F7 | Background process with notify | system row "Background Process Finished…" between the two replies (after reload) | ✅ |
| D-07b | F7/F8 | Same, **live** (app stays open) | no bubble overwritten, row present without reopening | ⏳ (pure 1.2.11 fails: A/B ✅) |
| D-08 | F9 | Ask for 1–45 then a tool | after completion the numbers survive as a collapsed reasoning block (or reply text) | ⏳ |
| D-09 | F12 | Ask for image / PDF / audio / video / `.txt` from a host path | each shows a real preview and can be saved | image ✅ · txt ❌ (raw `MEDIA:`) · pdf/audio/video ⏳ |
| D-10 | F11 | Trigger the top banner and each bottom notice, keyboard open/closed | no colour bar; no overlap with composer/dock/others | ⏳ |
| D-11 | F10 | Background subagent + Home list + chat | chip/pill stays while a child runs, clears on authoritative absence, no flapping (≥30 frames) | ❌ on pure 1.2.11 and on combined → ⏳ after F10 |
| D-12 | F14 | **Force-stop the app mid-turn**, wait ≥60 s, reopen | same chat, correct working/finished state, no lost/duplicated content, draft kept | ⏳ (now) |
| D-12b | F14 | Swipe away from recents / `am kill` (process death) instead of force-stop | same as D-12 | ⏳ |
| D-13 | F13 | Talk on the tablet; phone Console in background | phone gets a notification when the turn finishes / needs input | ⏳ (after research) |
| D-14 | all | Rotate, dark/light, large font, keyboard open, split-screen | no overlap/regression | ⏳ |
| D-15 | all | Cold start after each install | no crash (`logcat -b crash`), data intact | ✅ so far |

## Evidence rules
Every row stores: build number, date/time, screenshot(s) or contact sheet, the log line, and for A/B the pure-main result. Rows are re-run after any merge that touches their hotspot (plan §3).
