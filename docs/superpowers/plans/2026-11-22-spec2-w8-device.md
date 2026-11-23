# Spec 2 W8 (Device discretion and travel) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Summary (one paragraph).** W8 is two batches, nine tasks and one migration (with its grants twin and a self-revoke), one new edge function, and native Android and iOS work on the existing `attune/safety` and `attune/device` channels. **W8a** (Tasks 1–3, no migration): Dating's last in-memory data joins Spec 1's device wipe registry (the report and appeal request keys; an order-20 sweep, §6.7's `spec2.section_caches`), every Dating page goes blank in quick exit's first frame (the W6 decoy carry), the screen is protected while any Dating page is open (Android `FLAG_SECURE`; iOS blurs Dating while the screen is captured, `sceneCaptureState` with the `isCaptured` fallback), no gallery saves, and every Dating route, push tap and deep link is pinned behind the Dating lock (the route list read from `datingRoutes()`; every server push writer audited neutral by a new SQL contract). **W8b** (Tasks 4–9) → `20261122100000_dating_v2_traveller.sql` (+ `20261122100010_dating_v2_traveller_grants.sql`): the flag `dating_traveller_detection` (off), the device check's record (the IP's country only, at most one record per 15 minutes, the location signal at 7), the trip on the one context row, `dating_eligibility` gate 7, the home's `away` state, `trip` and plain-icon offer, the person's trip choice (Task 4); what a trip hides in the reads, and two W7 carries (the restriction and appeal `review`; a reference-code clash is busy) (Task 5); `dating-device-check` with a deploy-time DB-IP Lite table behind `IpCountryResolver` (Task 6); the app's device check, the away card, the trip's note and `/dating/away`, the Android network country, and the restricted screen in testing (Task 7); the plain app icon for everyone (Android aliases, iOS alternate icon, Settings → App icon, the D13 offer) (Task 8); the docs and the W8b gate (Task 9).

**Replayed.** Every task below was replayed in order in a scratch copy of the repo at `296b7216` on a clone of `attune_spec3a`: every "Create … with exactly" block, every edit, build, splice and mutant script, ARB fragment, `gen-l10n`, `dart format`, test command, golden generation, the Deno CI line, both batch gates (the race script at W8b on an idle scratch database) and the native checks (a debug APK build; the Swift type-check against the iOS SDK; `actool` on the asset catalogue). The Expected lines are what that replay printed (Replay record, end of plan).

**Goal:** Build Spec 2's device discretion and travel (§2.3, §2.5, §3.11, §6.7, W8) on the W1–W7 server and app: nothing of Dating left in memory or on screen after quick exit or sign-out while the Dating lock, the Safety PIN and the app icon stay; Dating's screens kept out of screenshots, recordings and the app switcher; every way into Dating behind the lock; a traveller in a place where Dating or same-gender introductions aren't allowed hidden there (on their phone and from others' Today) with a once-per-trip in-app note and their own choices; a plain app icon for everyone; and Dating still off in production (the new flag off).

**Architecture:** W8a is client and native only. The wipe reuses W3a's `DatingSessionMemory` hook and W5b's `DatingPageWatch` counter (every Dating page is counted): the counter's first page turns the screen protection on and its last turns it off, and a `DatingSurface` notifier the order-0 wipe entry flips blanks every page in the decoy's first frame. W8b is server first: `record_dating_device_check` (the service role's) wraps W1b's unchanged `record_dating_session_context`; the IP is resolved to a country in the edge function and never leaves it; what a trip hides is one predicate, `private.dating_trip_hides(viewer, other, kind)`, read by the authenticated reads only (the service role never reaches a decrypting function, S-4); the trip's kind and once-per-trip note are read by `get_dating_home()` (authenticated; it may decrypt), never by the service role's record. Every re-created function starts from its LIVE body (saved to `$D/before_w8b/`) with only lines marked `-- Spec 2 W8b` changed (`marked_diff.py`). The app's device check runs from Me's Dating section, at most once per 15 minutes while it shows, only for someone with Dating data. The plain icon's state lives in the OS (launcher aliases, iOS alternate icon), never in a stored key.

**Tech Stack:** Supabase Postgres 17 (RLS, `SECURITY DEFINER`, advisory locks), psql, Python 3 (edit, build, splice and mutation scripts), Deno 2.8.1 (the edge function and its tests, frozen lock `.github/deno-w9.lock`), Flutter 3.29.1 / Dart 3.7 / Riverpod 2.6 / go_router, Kotlin (MainActivity), Swift (AppDelegate), Android resources and an Xcode asset catalogue. No new package.

**Spec:** `docs/superpowers/specs/2026-10-24-dating-mode-design.md` — §8 W8 (W8a, W8b, the gate line); §2.1 (gate 7), §2.3, §2.5, §3.0 (Lock, Discretion), §3.1 (`away`), §3.2 D13 (the plain-icon offer, A-11), §3.11, §3.12 (App icon), §3.13, §3.14 (`/dating/away`), §3.15 (Not open, traveller; Settings), §4.3 (`dating_session_context`), §4.4 (`dating_effective_context`, `record_dating_session_context`), §4.7 (`dating-device-check`), §4.8 (session context), §4.9 W8a/W8b, §4.10 (rows tagged W8: `device_wipes.dart`, `MainActivity.kt`, the manifest and the asset catalogue, `quick_exit_service.dart` and `auth_provider.dart` not edited), §5.1, §5.2 (filters 1 and 4), §5.10 (location mismatch), §6.7, §7.1, §7.2 S4 and S19, §7.3 (`dating-device-check`), §7.4, §7.5, §7.7 (lock screen, screenshots, icon, traveller with a VPN; release builds, F-4); C-2, C-3, F-4, A-11, I-9, I-14. Spec 1 (`docs/superpowers/specs/2026-10-24-app-flow-identity-design.md`): §5.8 (the device wipe registry), D19, §3.9 (the Dating lock). Carries: `.superpowers/sdd/2026-11-22-spec2-w8/carries.md` (every item mapped below). Format reference: `docs/superpowers/plans/2026-11-21-spec2-w7-moderation.md`. The W7 ledger (`.superpowers/sdd/2026-11-21-spec2-w7-moderation/progress.md`) and its final client and server reports.

## Global Constraints

- **Where and how.** Work in the main working tree on `main` (`/Users/user/attune`). HEAD is `296b7216` (S2 W1–W7 committed). The owner may have uncommitted edits (`supabase/.temp/cli-latest`, `backup-before-planning-p2.sql`): never revert, stash, stage, checkout, reformat or read them into anything. Every edit to an existing file is an exact replacement made by a script that asserts each anchor occurs once (`$D/anchor.py`). If an anchor moved because the live code changed after this plan was written, make the same change to the current text and say so in the task report (live code is the truth).
- **NO commits.** No `git add`, `git commit`, `git stash`, `git checkout`, `git reset`, `git rm` (delete files with `rm`). Where a skill says "commit", instead: **do not commit; record the tree in the report** with `T=$(mktemp -u); GIT_INDEX_FILE=$T git read-tree HEAD && GIT_INDEX_FILE=$T git add -A && GIT_INDEX_FILE=$T git write-tree; rm -f $T` (a private index; the real index is untouched). The controller commits after each batch's final review.
- **Formatting.** Never `dart format` a pre-existing file (the repo uses an older formatter; formatting reflows it). `dart format` only the files a task creates. A later task that edits a file an earlier W8 task created does it with an anchor script already in `dart format` style and does not run the formatter on it.
- **SQL target.** Contracts run only on `attune_spec3a`, from the repo root. A file with a top-level `BEGIN;` runs as `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f F`; one without runs wrapped (`suite.sh` does both). Migrations and their twins are applied with `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f <file>`. Confirm the target first (`psql -X -d attune_spec3a -Atc 'select current_database()'` prints `attune_spec3a`). **NEVER `attune_test`. NEVER run `scripts/local_pg_setup.sh` or `scripts/local_pg_grants.sql`** — but DO append the twin's `\i` line to `scripts/local_pg_grants.sql` (`grants_line.py`). SQL mutants run inside one transaction that the contract's own `ROLLBACK` ends (`mutate.py`, with the twin applied after each migration mutant; `W8_DB` names the database). An `IF a OR b` in a DO block has no evaluation order: every call that writes is its own statement first. A comparison that can read NULL uses `IS DISTINCT FROM`; a row value is "absent" by its key (`(r).user_id IS NULL`), never `r IS NULL`.
- **Migrations.** `20261122100000_dating_v2_traveller.sql` and `20261122100010_dating_v2_traveller_grants.sql`, later than every file in `supabase/migrations/` (the newest is `20261121120010_dating_v2_escalations_grants.sql`). If `ls supabase/migrations | sort | tail -1` shows anything at or after `20261122100000` when Task 4 starts, shift both to the next free hour keeping their order and change every header, `\i` line and command. W8a has no migration (§4.9). The migration is one `BEGIN; … COMMIT;`, idempotent (applied twice, `exit=0` both times), with `SET LOCAL lock_timeout = '5s'`, and **ends by revoking everything it creates from PUBLIC, anon, authenticated and service_role** (the W6 final pattern: a push that stops between the migration and its twin fails closed); the twin grants. Every new function: `SECURITY DEFINER SET search_path = ''`, fully-qualified names; `GRANT EXECUTE … TO authenticated` only for `set_dating_trip_choice`; `service_role` only for `record_dating_device_check` (the edge function's); everything else the database's own. Re-created functions start from their LIVE body and change only lines marked `-- Spec 2 W8b`. Answers are fixed `{ok, reason}` codes; input is validated before any write; NULL never counts as allowed, trusted or home.
- **The W5–W7 lessons, in this wave.** Reads that write are `VOLATILE` (W8 adds no read that writes: the home stays `STABLE`; the trip's note is marked seen by the person's choice, a write). Exposure-reducing writes never wait (Keep it hidden needs no trusted phone; a trip's hiding needs no tick: the reads and gate 7 read the context as it is). Every failure path is counted in health or answers a fixed code (`dating.restriction.busy` for the carry-over's clash; the device check's refusals are fixed codes; the signal reuses `dating.signal.location_mismatch`). D8: the trip's note and its page show nothing of the last account; the D8 test first asserts the page is on screen. The shown-set rule: nothing W8 adds animates or announces except the note's busy and error lines (live regions); the traveller's screens never animate (§3.15). Mutant runs never rewrite a file another agent is testing: W8's `dmut.py` and `denomut.py` copy the tree (`mirror.py`) and mutate only the copy.
- **Production stays off.** No Dating flag turns on in production; the migration inserts `dating_traveller_detection` **off** with its production gate row and turns nothing on; no migration sets `attune_environment`. Only `supabase/sql/dev_enable_spec2_dating_flags.sql` (development only, never a migration) turns the new flag on. The device check records the session context with the flag off too (W5's same-gender freshness and §2.3's 14-day freshness already read it, and both fail closed without it); the flag decides what a trip changes (gate 7, the home's `trip`, the reads' hiding, the location signal).
- **Device discretion (C-2, C-3).** Quick exit and sign-out wipe Dating's caches only through Spec 1's registry; **never the Dating lock, the Safety PIN or the app icon**, never a scheduled check-in. `quick_exit_service.dart`, `auth_provider.dart` and `lib/app/device_wipes.dart` are not edited (W3a already added the one line). No key, value or file name the app writes contains "dating" (§3.0, S19): the trip choice is on the server, the icon is the OS's, the place's country is memory only.
- **Native code.** Only these native files change: `MainActivity.kt` (`attune/safety`: `setSecure`, `appIcon`, `setAppIcon`; `attune/device`: `networkCountryIso`), `AndroidManifest.xml` (the two launcher aliases), new Android resources for the plain icon, `AppDelegate.swift` (an `attune/safety` channel on iOS: `setSecure` with the capture watch, `appIcon`, `setAppIcon`), the asset catalogue's `IconPlain.appiconset` and three `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` lines in `project.pbxproj`. Native behaviour can't run under `flutter test`: the Dart side is pinned through mock channels, the native text by source pins, and everything else is on the owner's device-check list (§7.7). Device checks run on **release** builds (F-4).
- **Copy.** New app strings go into `lib/i10n/app_en.arb` under `dating_` only through `python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py <fragment>`, then `flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package`. Straight apostrophes. Exact spec strings are copied verbatim; strings this plan adds are marked "Plan copy" in their ARB description and listed for the reviewers (Owner checklist). The app never shows a server's text.
- **UI.** Every new Dating screen is under `AllowLargeText`. §3.15: the traveller's note and page never animate; App icon is a standard list. Goldens at 1.0, 1.3, 2.0 and RTL (`expectFlowGoldens`), the three guidelines (`expectFlowGuidelines`), the large-text audit at 2.0 over `test/features/dating/device` (`0 site(s) to fix`); both new routes are listed as audited in `test/architecture/text_scale_routes_test.dart`. Busy and offline are calm lines; error red is the theme's (`FlowErrorLine`).
- **Off limits.** Games (`test/architecture/games_untouched_test.dart` stays green), Opinions, `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`, `lib/home/home_screen.dart` and its latch (`shasum -c .superpowers/sdd/2026-11-07-spec2-w3/latch.sha`), `quick_exit_service.dart`, `auth_provider.dart`, `lib/main.dart`, `lib/app/app.dart`, `lib/app/routing/app_router.dart`, `lib/app/device_wipes.dart`, Spec 1's Settings screen, every applied migration, every edge function but `dating-device-check` (new). **No deploys** (`supabase db push`, function deploys, the IP table's build and upload, app builds for the stores are the owner's; Owner checklist). No `.env*`, credentials or keychain. No subagents for the replay; Opus for every role.
- **Fixture ids.** The device contract's people are `8a800000-0000-0000-0000-` + the 12-digit code (`pg_temp.id('nn')`) with phones `+1555981nn`: B `01–29`, C `30–59`.
- **Gates, every batch (Tasks 3 and 9; `$D/gate.sh`).** (1) The wrapped SQL suite on `attune_spec3a`: no new FAIL against `$D/sql-baseline.txt` (baseline **162 PASS / 14 FAIL**; **163 / 14** from Task 3, which adds `dating_v2_device_contracts.sql`). (2) Full `flutter test`: no failure beyond the known ones (at `296b7216` itself, in the replay: the three `healing_journal_large_text` goldens and `chat_screen_test` "Swap: disabled before 72 hours…", whose fixed clock `datingChatT0` is now in the past; neither is W8's) and the known flakes ( `chat_controller_test:259`, `chat_screen_list_anchor` D<0, `reflection_journal` at a date boundary, `planning_recent`, `story_outbox_notices_test` "Discard asks first…", `chat_upload_progress_cancel_test`, `story_review_test` "final review #1"; re-run a failing file alone before calling it a flake); the count moves by the tests each task adds. (3) `flutter analyze --no-pub lib test`: **571 issues, 0 new**. (4) `shasum -c` of the W10 and W9 sha lists: every line `OK`. (5) W8b: `scripts/concurrency/dating_kill_switch_races.sh` on an **IDLE** scratch database (load under about 4; another agent may be running Flutter tests: wait, or note the load) built from `pg_dump -s attune_spec3a` plus the config tables' data, dropped after: every case `PASS`. (6) The Deno CI line (`.github/workflows/tests.yml` job `deno-w9`, frozen lock) passes in full and its `deno check` line is clean. (7) The Games guard passes and the latch is `OK`. (8) Each task's named mutants all RED (a `CONTRACT VIOLATED` line, or `KILLED`), the RED line quoted in the report; a `COMPILE` or an `anchor missing` is a broken mutant to fix, never a kill; an equivalent mutant is retired with its reason in the task, never silently. (9) The feature flags: one more row than at the baseline, none newly on.

## Review Focus

Five things a real person will meet that this wave must survive. Each is pinned to tests that fail if it regresses.

1. **Quick exit pressed while Dating is on screen, with typed words in a report sheet** (Today, a chat, the meeting kit; a report's details half-typed; iOS, where the app stays alive behind the decoy). Expect: no frame of Dating under the decoy's slide-in; nothing typed, no photo and no dismissal left in memory; the Dating lock and the Safety PIN still set; the check-in still scheduled. Tests: Task 1 `quick exit from Today|a chat|the meeting kit…`, `no frame of Dating shows once quick exit is pressed`, `quick exit never cancels a scheduled check-in` (mutants `keys_not_wiped`, `surface_not_registered`, `page_ignores_surface`).
2. **Someone opens Dating from a notification or a link on a phone with the Dating lock on** (a cold start from the tray, a deep link to a chat, any page a later wave adds). Expect: the Safety PIN first, nothing of the page built before it, then the page asked for. Tests: Task 3 (every route in `datingRoutes()`, from inside the app, as a cold start and by the platform's route; every push type; mutants `lock_ignored`, `checkin_push_to_me`).
3. **A UK user who meets women opens Attune in Accra, or a Ghana user lands in Dubai** (and a VPN hides one of them). Expect: in Accra her same-gender introductions and conversations are hidden on her phone and she is off the other woman's Today, while man-woman introductions continue; in Dubai the Dating section shows only the away card, conversations come back on "Show it on this phone anyway", and nobody new is introduced; one in-app note per trip, never a push; home again, everything returns at once. A VPN reads as home (§2.3). Tests: Task 4 contract B3–B5, Task 5 contract C1–C2 (mutants `not_hidden_from_others`, `man_woman_hidden`, `away_ignores_show_here`, `show_here_exposes_others`, `gate7_ignores_flag`, `trip_ends_early`), Task 7 widgets.
4. **A shared phone: another account signs in while a traveller's note or the App icon page is open.** Expect: no frame of the last account's trip, its place or its choice; nothing sent as the next account. Tests: Task 7 `D8: another account sees nothing of an open note` (asserts the page is on screen first).
5. **The phone can't tell where it is or refuses a change** (no IP table deployed, the edge function down, no install id, an iPhone that asks to confirm the icon and the person cancels). Expect: an unresolved IP is the phone's country (never a block, never an error); a failed check changes nothing on screen; no install id is `device_unavailable`; a refused icon change says "That didn't change. Try again." and the icon stays. Tests: Task 6 (`no table, or a bad one, resolves nothing`; refusals), Task 7 (`no check for…`; an answer that agrees reads nothing again), Task 8 (`a refusal says so…`, `a phone that can't change it…`).

## Pre-flight (read before Task 1)

`D=.superpowers/sdd/2026-11-22-spec2-w8` throughout. The tool folder holds `carries.md` and W8's tools: `suite.sh`, `marked_diff.py`, `anchor.py`, `grants_line.py`, `splice.py` (W7's, copied unchanged), `mutate.py` (W7's with `W8_DB`), and `mirror.py`, `dmut.py`, `denomut.py` (W7's runners changed to mutate a private copy of the tree, never the working tree).

### Shared files and interfaces between tasks

| File or interface | Tasks | Rule |
|---|---|---|
| `lib/features/dating/routes/dating_page_watch.dart` | 1 (`DatingSurface`), 2 (`DatingDiscretion`, `DatingCaptureCover`) | Task 2's anchors are Task 1's text |
| `lib/features/dating/dating_device_wipes.dart` | 1 | two entries added; W3a's three kept |
| `supabase/tests/dating_v2_device_contracts.sql` | 3 creates (A, then `-- @@W8B@@`); 4 splices B (ends `-- @@W8B-T5@@`); 5 splices C (ends `-- @@W8-END@@`) | helpers from B on: `pg_temp.id`, `dev`, `hash`, `ready`, `uk`, `as_person`, `as_db`, `j`, `check`, `age`, `ctx`, `flag`, `key`, `home`; from C: `intro`, `match`, `today`, `chats` |
| `supabase/migrations/20261122100000_dating_v2_traveller.sql` | 4 builds it (`build_mig_W8b.py`: `mig_T4_head.sql`, the re-created functions, the self-revoke); 5 adds `mig_T5.sql` (at `-- @@W8B-T5@@`) and `edits_T5.py`, and builds again | the builder includes Task 5's section, edits and revokes when they exist |
| `…100010_dating_v2_traveller_grants.sql` | 4 creates (ends with `-- @@W8B-T5-GRANTS@@`); 5 splices `twin_T5.sql` there | |
| `supabase/tests/dating_rls_canary.sql` | 4 (W8b rows above the Checks line, then `-- @@W8B-T5-CANARY@@`), 5 (the review helper's row at the marker) | never a loosened check |
| `lib/features/dating/routes/dating_routes.dart` | 7 (`/dating/away`), 8 (`/dating/app-icon`) | Task 8's anchors are Task 7's text |
| `lib/features/dating/section/dating_section.dart`, `data/dating_home.dart`, `report/{dating_report,restricted_screen}.dart` | 7 | |
| `test/features/dating/support/dating_shell.dart` | 7 (the trip fakes in every shell) | |
| `lib/app/documentations/user_manual/data/dating_mode_docs.dart` | 3 (`dating_screen`), 8 (`dating_app_icon`) | Task 8's anchor is Task 3's text |
| `test/architecture/text_scale_routes_test.dart` | 7 (`datingAway`), 8 (`datingAppIcon`) | |
| `android/.../MainActivity.kt` | 2 (`setSecure`), 7 (`networkCountryIso`), 8 (`appIcon`, `setAppIcon`) | each task's anchors are the earlier tasks' text |
| `ios/Runner/AppDelegate.swift` | 2 (the channel, `setSecure`), 8 (`appIcon`, `setAppIcon`) | |
| `lib/i10n/app_en.arb` + generated | 7, 8 | fragments via `arb_append.py`, then gen-l10n |

### Carries → tasks

| # | Carry (`carries.md`) | Where |
|---|---|---|
| 1 | W5: lazy per-card photo loading on Today | **Ruled out of W8 (R-82)**: a data-use change, not discretion; §7.7's W10 data-use measurement decides whether it is needed. Owner checklist 9. |
| 2 | W5/W6: `FLAG_SECURE` on Dating screens; chat "screenshots blocked, app switcher covered" | Task 2 (Android `FLAG_SECURE`, iOS capture blur; the app switcher is `AppPrivacyCover`'s, unchanged). |
| 3 | W6 final: quick exit's decoy shows ~300 ms of Dating | Task 1 (`DatingSurface`: every Dating page blank in the decoy's first frame, from a Dating file; Spec 1's files untouched). |
| 4 | W6/W7: the chat's caches and the report/appeal pending maps in the wipe registry | Task 1: the report and appeal request keys (their signature holds what was typed) join `DatingSessionMemory`; the unsent card and timebox dismissals were W6's; the chat's held message map is the chat page's state and goes with the page; `DatingPhotoMemory` and the meet plan (with its check-in time) are swept again at order 20. The console is web-only (no device wipe). |
| 5 | W7 M-6: `review` on the restriction read and the appeal's answer | Task 5 (server), Task 7 (the restricted screen drops the 24-hour and 7-day sentences in testing). |
| 6 | W7 n4-2: a reference-code clash in the carry-over answers busy; n4-1 (optional) re-home a carried check | n4-2: Task 5 (`unique_violation` joins the read's busy handler, counted). **n4-1 ruled out**: the W7 final review accepted it as a recorded engineering repair; no person-visible effect. |
| 7 | W7 final client: a codeless ID email (W4's own age check) can't be matched | **Ruled out of W8**: W4's own age check has no case to hang a code on; it needs a server change to W4's restriction and a client line, and the runbook already asks for the code by reply. Owner checklist 10 (a W10 item if wanted). |
| 8 | Every Dating push type and route honours the Dating lock | Task 3 (every route from `datingRoutes()`, cold start and deep link; every push type the app routes; the server's push writers audited neutral, contract A). |
| 9 | Parallel rule: replay on its own copy and clone; Opus for everything | Global Constraints and the Replay record. |

### Rulings (the spec wins over this plan; each records its cost if wrong)

- **Ruling R-69:** W3a already added `registerDatingDeviceWipes()` (in `lib/features/dating/dating_device_wipes.dart`, not the spec's `data/dating_device_wipe.dart`) and its one line in `device_wipes.dart`, with W3a's, W5b's and W6c's entries. W8a adds two entries there: §6.7's `spec2.section_caches` (order 20, both moments, bound 1 s, `clearDatingDeviceData`: every Dating memory again after Spec 1's entries) and `spec2.dating_surface` (order 0, so it runs before Spec 1's awaited entries: every Dating page blank in the decoy's first frame). Cost if wrong: one file move.
- **Ruling R-70:** "invalidates every Dating provider": every Dating provider that holds data is `autoDispose` (W3's architecture test) and goes with its page; the ones that outlive pages (the unlock, the unsent dismissals, now the report and appeal keys) are emptied through `DatingSessionMemory`. No Dating deep link is held outside a route (the unlock's `from` is in its route, which quick exit's `go()` removes). Cost if wrong: none.
- **Ruling R-71:** the screen is protected while **any** Dating page is open (`DatingPageWatch`'s count), a stricter reading of "a Dating route on top": the Safety PIN setup pushed over Dating is protected too. iOS gains an `attune/safety` channel (`setSecure` watches the capture state and answers it; `captureChanged` while watching); quick exit's `finishAndRemoveTask` stays Android-only. Cost if wrong: none.
- **Ruling R-72 (owner-visible):** `record_dating_device_check` (new, the service role's) wraps W1b's `record_dating_session_context`, which keeps its signature, its contract and its streak rule; the wrapper records at most once per 15 minutes (§2.3), so "7 in a row" (§5.10) is seven records at least 15 minutes apart: someone abroad who opens Attune across about two hours raises one P3 `location_mismatch` signal case (never an automatic action, flag on only). Cost if wrong: count one record per day (one line).
- **Ruling R-73:** `dating-device-check` answers `{ok: true, trusted, away, note: null | {country}}`; `note.country` is the place while it restricts more than home (for the note's words only, held in memory). The trip's kind and whether its note is still to show come from `get_dating_home()`'s `trip` (authenticated; it reads the person's identity), never from the service role's record (the canary's S-4 scan). Cost if wrong: none.
- **Ruling R-74 ⚑ (owner decision):** the IP table is DB-IP's "IP to Country Lite" (CC BY 4.0; the app's licences and the privacy notice must say "IP Geolocation by DB-IP"), built at deploy time by `scripts/ip_country/build_ip_country.ts` into a compact table (IPv4 ranges, IPv6 at /64; merged per country; an estimated 4–6 MB, about 2 MB IPv4-only), shipped as the function's static file (`config.toml` `static_files`), git-ignored, refreshed monthly. With no table every IP is unresolved and the database falls back to the phone and network countries (as for a VPN). Nothing large enters the repo. Owner: approve the source and its attribution, the size (or IPv4-only), the monthly refresh, or instead use Cloudflare's `cf-ipcountry` if the project's front door provides it (the `IpCountryResolver` seam takes either). Cost if wrong: one resolver.
- **Ruling R-75:** the SIM's country is never sent: no computation in §2.3 reads it (the network's country is the place). Cost if wrong: one field.
- **Ruling R-76:** the app checks from Me's Dating section, for someone with Dating data on a phone Dating can use (not `feature_unavailable`, `country_closed`, `region_closed` or `reverify_device`), at most once per 15 minutes while the section shows; an answer that disagrees with the home shown (a trip began or ended) reads the home once more. Cost if wrong: none.
- **Ruling R-77:** "Show it on this phone anyway" is the person's own `show_here` on their one context row (no device key, no "dating" on disk); only their own reads honour it; it ends with the trip. "Pause Dating" and "Set a PIN" first mark the note seen as "Keep it hidden"; "Set a PIN" is offered only while the Dating lock is off. Cost if wrong: one column.
- **Ruling R-78:** a trip is `away_from_home` (the IP's country ≠ the Dating country); it ends after 7 days of records not away (`home_since`), which clears the note's mark and `show_here`. A VPN reads as home (§2.3 accepts it). Cost if wrong: one column.
- **Ruling R-79:** what a trip hides (flag on): gate 7 for candidates (not for setup), so an away person is out of every Today and their own Today and introductions are refused; on the traveller's own phone, every conversation (ended ones too) while Dating isn't allowed there, and every introduction, conversation, message read and match moment that isn't man-woman while same-gender isn't; from another person's Today, a non-man-woman introduction with someone where same-gender isn't allowed. The service role's photo signer and the digest are not filtered (the service role never reaches a decrypting function, S-4); a hidden card's photos need its id, which the hidden card no longer shows. Cost if wrong: a stale id fetches photos.
- **Ruling R-80 ⚑ (owner decision):** the plain icon for everyone: Android moves the launcher entry to two activity-aliases (`.IconDefault` on, `.IconPlain` off; neutral names; the app's own label, `attune`, as the manifest has it), and MainActivity keeps a MAIN/LAUNCHER filter with a scheme no launcher sends, so the Flutter tool (which needs an `activity` with MAIN and LAUNCHER) still starts it while launchers list one icon; iOS uses the alternate icon `IconPlain`. The choice lives in the OS and survives quick exit and sign-out (protective; another account on the phone keeps it). It is reached from Dating settings and D13; **a row in Spec 1's Settings for people who never use Dating needs a Spec 1 file edit: owner to approve** (one `SettingsConfig` row opening `/dating/app-icon`, or a non-Dating route). The ring artwork is a placeholder a designer may replace (no other app's icon). Cost if wrong: one row.
- **Ruling R-81:** W7's carries: the restriction read and the appeal's answers carry `review` (`private.dating_review_mode()`, the report's rule); the app reads `staffed` only from the server's `review: 'staffed'` (a read built in code, as W7's tests build them, keeps W7's staffed lines) and in testing shows the plain hold line and "Appeal sent. A different person from the one who made the first decision will look at it." A clash in the carry-over (`unique_violation`) joins the read's busy answer, counted `dating.restriction.busy`. Cost if wrong: none.
- **Ruling R-82:** lazy per-card photo loading (W5 carry) is out of W8 (Carries 1). Cost if wrong: one W10 task.
- **Ruling R-84:** W8's traveller rows live in a new contract file, `dating_v2_device_contracts.sql` (with W8a's push audit), not in `dating_v2_matching_contracts.sql` (§7.1), so W8's mutants run against W8's contract alone; the matching contract still passes unchanged. Cost if wrong: a file move.
- **Ruling R-83:** no new race case: two device checks at once serialise on the person's advisory lock and the second finds the row fresh (no second record); the contract pins the sequential case. Cost if wrong: one race case later.

## Interfaces this plan consumes (read from the current code)

- **Spec 1:** `DeviceWipeRegistry`, `DeviceWipeEntry`, `WipeMoment` (`lib/core/device/device_wipe_registry.dart`), `registerDeviceWipes([registry])` (`lib/app/device_wipes.dart`), `QuickExitService` (`clearStories`, `exitOverride`), `QuickExitZone`, `DatingLockStore` (`me_section_lock`), `datingLockProvider`, `setDatingLock`, `AllowLargeText`, `FlowFrame`, `FlowPrimaryButton`, `FlowSecondaryButton`, `FlowTextLink`, `FlowErrorLine`, `expectFlowGoldens`, `expectFlowGuidelines`, `pumpFlowScreen`, `tapInReach`, `countryNameFor`, `_shared/attune_auth.ts` (`requireUser`, `serviceRoleClient`, `HttpError`), `_shared/client_ip.ts` (`clientIp`), `_shared/error_code.ts`, `private.bump_metric_internal`, `private.attune_environment()`, `buildNanoEmbryoNotificationConfig()`.
- **S2 W1–W7 (live):** `public.record_dating_session_context(uuid, text, text)`, `public.dating_effective_context(text, text, text, text)`, `public.dating_session_context` (with `trip_note_shown_at`, `mismatch_streak`), `private.dating_device_state(uuid, text)`, `private.dating_iso_country`, `private.dating_phone_country`, `private.dating_same_gender_on`, `private.dating_identity_of`, `private.dating_pair_is_man_woman`, `private.dating_open_signal_case`, `private.dating_field_decrypt`, `private.dating_key_ok`, `public.claim_dating_idempotency`, `public.dating_require_trusted_device`, `public.dating_flag_enabled`, `public.dating_eligibility(uuid, text)`, `public.dating_candidate_is_current`, `private.dating_visible_introductions`, `public.get_dating_home()`, `public.get_my_dating_today()`, `public.get_my_dating_introductions()`, `public.act_on_dating_introduction`, `public.get_my_dating_matches(boolean)`, `public.get_dating_messages`, `public.get_my_dating_restriction()`, `public.submit_dating_appeal`, `private.dating_carry_over`, `private.flag_production_gates`; app: `DatingSessionMemory`, `DatingPageWatch`, `DatingPhotoMemory`, `DatingPlanMemory`, `DatingActionKeys`, `datingWrite`, `DatingRpc`, `datingRpcProvider`, `datingSupabaseClientProvider`, `datingAccountProvider`, `datingHomeProvider`, `datingLifecycleGatewayProvider`, `datingOnlineProvider`, `datingReportKeysProvider`, `datingPendingCardDismissalsProvider`, `setDatingLockInDating`, `datingRoute`, `datingRoutes`, `DatingPaths`, `datingRootBackButton`, `DatingCalmLine`, `DatingStartLink`, `datingCountryName`, `deviceHashOf` (`dating-photo-urls/handler.ts`); test support `pumpDatingShell`, `datingShellOverrides`, `datingHomeOnlyOverrides`, `datingTestAccount`, `FakeDatingHomeGateway`, `FakeDatingLifecycleGateway`, `FakeDatingChat`, `FakeDatingToday`, `FakeDatingReport`, `datingTodayOverrides`, `datingChatOverrides`, `datingReportOverrides`, `datingTestPng`.

## Interfaces this plan produces (for W9 onward)

- **SQL (W8b):** flag `dating_traveller_detection` (off) and its production gate; `dating_session_context` + `home_since timestamptz`, `show_here boolean`; `public.record_dating_device_check(p_user uuid, p_device_hash text, p_ip_country text, p_network_country text) → {ok, trusted, away, here}` | `{ok:false, reason: unavailable|invalid}` (service role); `public.set_dating_trip_choice(p_idempotency_key text, p_show_here boolean) → {ok}` | `{ok:false, reason: invalid|reverify_device|no_trip}` (authenticated); `private.dating_traveller_on()`, `private.dating_wants_same_gender(uuid)`, `private.dating_trip_hides(viewer uuid, other uuid, kind text)`, `private.dating_trip_json(uuid) → {} | {trip: {kind: away|same_gender, note, show_here}}`, `private.dating_icon_offer_json(uuid) → {} | {offer_plain_icon: true}`, `private.dating_review_mode() → staffed|testing`; `dating_eligibility` gate 7 (`away`); `get_dating_home()` state `away`, `trip`, `offer_plain_icon` (setup); `get_my_dating_restriction()` + `review`; `submit_dating_appeal` ok answers + `review`.
- **Edge:** `dating-device-check` (POST `{network_country?}` → `{ok, trusted, away, note}`; `handleDeviceCheck(body, {userId, deviceHash, ipCountry}, deps)`, `IpCountryResolver`, `RangeTable`, `loadResolver`, `buildTable`).
- **App:** `lib/features/dating/device/{dating_surface.dart (DatingSurface, DatingBlankPage), dating_discretion.dart (DatingDiscretion, DatingCaptureCover), network_country.dart (NetworkCountry), dating_trip.dart (DatingDeviceCheck, DatingTripGateway, DatingTripRepository, datingTripGatewayProvider, datingNetworkCountryProvider, datingTripPlaceProvider, checkDatingDevice, kDatingDeviceCheckEvery), trip_note.dart (DatingTripNote, DatingAwayScreen, datingTripTitle, datingTripBody), app_icon.dart (AppIconChoice, AppIconControl, PlatformAppIcon, appIconControlProvider, appIconProvider)}`, `lib/features/dating/settings/app_icon_screen.dart (DatingAppIconScreen)`; `clearDatingDeviceData()`; `DatingHomeState.away`, `DatingTrip`, `DatingTripKind`, `DatingHome.trip`, `DatingHome.offerPlainIcon`; `DatingPaths.away`, `DatingPaths.appIcon`; `DatingActionKeys.clear()`; `DatingRestrictionRead.staffed`; native `attune/safety` `setSecure` / `captureChanged` / `appIcon` / `setAppIcon`, `attune/device` `networkCountryIso`; test support `FakeDatingTrip`, `datingTripOverrides`.

## File map

**W8a.** Task 1 creates `lib/features/dating/device/dating_surface.dart`, `test/features/dating/device/dating_device_wipe_test.dart`, `$D/{sql-baseline.txt, analyze-baseline.txt, flutter-baseline.txt, edit_app_T1.py, mut_T1_dart.py}`; modifies `dating_rpc.dart`, `report/dating_report_providers.dart`, `routes/dating_page_watch.dart`, `dating_device_wipes.dart`. Task 2 creates `lib/features/dating/device/dating_discretion.dart`, `test/features/dating/device/dating_discretion_test.dart`, `$D/{edit_app_T2.py, edit_native_T2.py, mut_T2_dart.py}`; modifies `dating_page_watch.dart`, `MainActivity.kt`, `AppDelegate.swift`. Task 3 creates `supabase/tests/dating_v2_device_contracts.sql`, `test/features/dating/device/dating_lock_entry_test.dart`, `$D/{edit_docs_T3.py, mut_T3.py, mut_T3_dart.py, gate.sh}`; modifies the manual.

**W8b.** Task 4 creates `$D/{before_w8b/, mig_T4_head.sql, build_mig_W8b.py, contract_T4.sql, edit_tests_T4.py, mut_T4.py}`, `supabase/migrations/20261122100000_dating_v2_traveller.sql`, `…100010_…_grants.sql`; modifies the device contract, the canary, `scripts/local_pg_grants.sql`. Task 5 creates `$D/{mig_T5.sql, edits_T5.py, twin_T5.sql, contract_T5.sql, edit_tests_T5.py, mut_T5.py}`; rebuilds the migration and the twin; modifies the device contract, the canary, `dating_v2_moderation_contracts.sql`. Task 6 creates `supabase/functions/dating-device-check/{ip_country.ts, ip_table_build.ts, handler.ts, request.ts, index.ts, handler.test.ts}`, `scripts/ip_country/build_ip_country.ts`, `$D/{edit_ci_T6.py, mut_T6.py}`; modifies `tests.yml`, `config.toml`, `.gitignore`. Task 7 creates `lib/features/dating/device/{network_country.dart, dating_trip.dart, trip_note.dart}`, `test/features/dating/support/dating_trip_fakes.dart`, `test/features/dating/device/trip_test.dart` and its goldens, `$D/{arb_fragment_T7.txt, edit_app_T7.py, edit_native_T7.py, edit_tests_T7.py, edit_tests_T7b.py, mut_T7_dart.py}`; modifies the home model, the routes, the section, the restricted screen and its model, `MainActivity.kt`, `dating_shell.dart`, the text-scale audit. Task 8 creates `lib/features/dating/device/app_icon.dart`, `lib/features/dating/settings/app_icon_screen.dart`, the Android plain-icon resources, `ios/Runner/Assets.xcassets/IconPlain.appiconset/`, `test/features/dating/device/app_icon_test.dart` and its goldens, `$D/{make_plain_icon.py, arb_fragment_T8.txt, edit_native_T8.py, edit_app_T8.py, edit_tests_T8.py, mut_T8_dart.py}`; modifies the manifest, `MainActivity.kt`, `AppDelegate.swift`, `project.pbxproj`, the routes, Dating settings, D13, the manual, the settings order test, the text-scale audit; regenerates `dating_settings_bottom.*` goldens. Task 9 creates `$D/edit_docs_T9.py`; modifies the design spec (six amendment notes) and `supabase/sql/dev_enable_spec2_dating_flags.sql`.

**Not edited:** `lib/main.dart`, `lib/app/app.dart`, `lib/app/routing/app_router.dart`, `lib/app/device_wipes.dart`, `lib/home/home_screen.dart`, `quick_exit_service.dart`, `auth_provider.dart`, Spec 1's Settings screen, `lib/features/chat/**`, `lib/features/games/**`, Opinions, every applied migration, `scripts/local_pg_setup.sh`, every edge function but the new one, `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`.

---

## Batch W8a — quick exit, screen protection, the lock on taps and links (no migration)

### Task 1: The baselines, Dating's last memory in the device wipe, and no frame of Dating under the decoy (§6.7, §7.4, §7.7; C-2, C-3; carries 3, 4; R-69, R-70)

**Files:**
- Create: `lib/features/dating/device/dating_surface.dart`, `test/features/dating/device/dating_device_wipe_test.dart`, `$D/{sql-baseline.txt, analyze-baseline.txt, flutter-baseline.txt, edit_app_T1.py, mut_T1_dart.py}`
- Modify: `lib/features/dating/data/dating_rpc.dart` (`DatingActionKeys.clear`), `lib/features/dating/report/dating_report_providers.dart` (the keys tracked), `lib/features/dating/routes/dating_page_watch.dart` (the blank page), `lib/features/dating/dating_device_wipes.dart` (two entries, `clearDatingDeviceData`)
- Test: `test/features/dating/device/dating_device_wipe_test.dart`

**Interfaces:**
- Consumes: `DeviceWipeRegistry.instance`, `registerDeviceWipes()`, `QuickExitService.{clearStories, exitOverride}`, `QuickExitZone`, `DatingSessionMemory.track(owner, ref, clear)`, `DatingPhotoMemory.{put, get, key, length, clear}`, `DatingPlanMemory`, `datingReportKeysProvider`, `datingPendingCardDismissalsProvider`, `pumpDatingShell`.
- Produces: `DatingSurface.{hidden, hide(), reset()}`, `DatingBlankPage` (key `dating_blank_page`), `DatingActionKeys.clear()`, `clearDatingDeviceData()`, registry entries `spec2.dating_surface` (order 0) and `spec2.section_caches` (order 20).

- [ ] **Step 1: Check the tool folder and record the baselines**

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
ls $D | tr '\n' ' '; echo
psql -X -d attune_spec3a -Atc 'select current_database()'
bash $D/suite.sh attune_spec3a > $D/sql-baseline.txt; echo "SQL $(grep -c ^PASS $D/sql-baseline.txt) PASS / $(grep -c ^FAIL $D/sql-baseline.txt) FAIL"
flutter analyze --no-pub lib test > $D/analyze-baseline.txt 2>&1; tail -1 $D/analyze-baseline.txt
flutter test --no-pub --reporter compact > $D/flutter-baseline.txt 2>&1; tr '\r' '\n' < $D/flutter-baseline.txt | grep -oE '\+[0-9]+( ~[0-9]+)?( -[0-9]+)?: (All tests passed!|Some tests failed\.)' | tail -1
psql -X -d attune_spec3a -Atc "select count(*) || ' rows, ' || count(*) filter (where enabled) || ' on' from public.feature_flags"
```

Expected: `anchor.py carries.md denomut.py dmut.py grants_line.py marked_diff.py mirror.py mutate.py splice.py suite.sh`; `attune_spec3a`; `SQL 162 PASS / 14 FAIL` (161 / 15 when `quiet_hours_contracts.sql` meets its clock-dependent hour); `571 issues found.`; `+8906 -4: Some tests failed.` (the three `healing_journal_large_text` goldens and `chat_screen_test` "Swap: disabled before 72 hours…": both fail at `296b7216` itself, the first at its date boundary, the second because its fixed clock `datingChatT0` is now in the past); `44 rows, 6 on`.

- [ ] **Step 2: Write the failing test**

Create `test/features/dating/device/dating_device_wipe_test.dart` with exactly:

````dart
// Spec 2 W8a (§6.7, §7.4, §7.7; C-2, C-3; carries 3, 4): quick exit and
// sign-out reach Dating only through Spec 1's device wipe registry, and
// leave no Dating data in memory: the other people's photos and their
// decoded copies, the unsent dismissals, the report and appeal request
// keys (what was typed), the meet plan. The Dating lock and the Safety PIN
// stay (sign-out clears the lock: Spec 1), a scheduled check-in is never
// cancelled, a hanging entry never stalls the exit, and no frame of Dating
// shows once quick exit is pressed (the W6 decoy carry).
import 'dart:async';

import 'package:attune/app/device_wipes.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/dating/chat/dating_chat_providers.dart';
import 'package:attune/features/dating/chat/plan_meet_screen.dart';
import 'package:attune/features/dating/dating_device_wipes.dart';
import 'package:attune/features/dating/device/dating_surface.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart';
import 'package:attune/features/dating/report/dating_report_providers.dart';
import 'package:attune/features/dating/routes/dating_page_watch.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/today/dating_photo_memory.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/safety/presentation/widgets/quick_exit_zone.dart';
import 'package:attune/features/stories/data/story_device_wipe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dating_chat_fakes.dart';
import '../support/dating_shell.dart';
import '../support/dating_today_fakes.dart';

Future<void> _quickExit(WidgetTester t) async {
  for (var i = 0; i < 3; i++) {
    await t.tap(find.byKey(const Key('quick_exit_zone')), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// Every Dating memory W8a wipes, filled as a person using Dating fills it.
Future<({String photo, String reportKey, Set<String> dismissals})> _fill(
  DatingShell s,
) async {
  final key = DatingPhotoMemory.key('introduction', 'i9', 1);
  DatingPhotoMemory.put(key, datingTestPng);
  final reportKey = s.container.read(datingReportKeysProvider('ama')).keyFor(
    'report:m1',
    ['harassment', 'What they wrote to me', false],
  );
  final dismissals = s.container.read(
    datingPendingCardDismissalsProvider('ama'),
  )..add('card-1');
  DatingPlanMemory.place = 'Accra Mall food court';
  DatingPlanMemory.at = DateTime(2026, 11, 22, 18);
  DatingPlanMemory.account = 'ama';
  DatingPlanMemory.checkinAt = DateTime(2026, 11, 22, 21);
  return (photo: key, reportKey: reportKey, dismissals: dismissals);
}

void _expectWiped(
  DatingShell s,
  ({String photo, String reportKey, Set<String> dismissals}) filled,
) {
  expect(DatingPhotoMemory.get(filled.photo), isNull);
  expect(DatingPhotoMemory.length, 0);
  expect(
    PaintingBinding.instance.imageCache.containsKey(MemoryImage(datingTestPng)),
    isFalse,
  );
  expect(filled.dismissals, isEmpty);
  // The same report again is a new request: the old key (and the words
  // it was made from) is gone.
  expect(
    s.container.read(datingReportKeysProvider('ama')).keyFor('report:m1', [
      'harassment',
      'What they wrote to me',
      false,
    ]),
    isNot(filled.reportKey),
  );
  expect(DatingPlanMemory.place, isNull);
  expect(DatingPlanMemory.checkinAt, isNull);
}

void main() {
  setUp(() {
    DeviceWipeRegistry.instance.clear();
    registerDeviceWipes();
    QuickExitService.clearStories = () async {};
    QuickExitService.exitOverride = () async {};
    addTearDown(() {
      QuickExitService.clearStories = clearStoryDeviceCaches;
      QuickExitService.exitOverride = null;
      DeviceWipeRegistry.instance.clear();
      DatingSurface.reset();
    });
  });

  test('Dating registers its entries: none protective, the sweep at 20', () {
    final registry = DeviceWipeRegistry();
    registerDatingDeviceWipes(registry);
    final ids = {for (final e in registry.entries) e.id: e};
    expect(ids.keys, {
      'spec2.dating_session',
      'spec2.dating_photos',
      'spec2.dating_plan',
      'spec2.dating_surface',
      'spec2.section_caches',
    });
    final sweep = ids['spec2.section_caches']!;
    expect(sweep.order, 20);
    expect(sweep.moments, {WipeMoment.quickExit, WipeMoment.signOut});
    expect(sweep.bound, const Duration(seconds: 1));
    expect(ids['spec2.dating_surface']!.order, 0);
    for (final e in registry.entries) {
      expect(e.protective, isFalse, reason: e.id);
      expect(e.keys, isEmpty, reason: e.id);
    }
  });

  for (final (place, path, overrides) in [
    ('Today', DatingPaths.today, datingTodayOverrides(FakeDatingToday())),
    ('a chat', DatingPaths.chat('m1'), datingChatOverrides(FakeDatingChat())),
    (
      'the meeting kit',
      DatingPaths.plan('m1'),
      datingChatOverrides(FakeDatingChat()),
    ),
  ]) {
    testWidgets('quick exit from $place: Dating memory empty; the lock and '
        'the Safety PIN unchanged', (t) async {
      final s = await pumpDatingShell(
        t,
        initial: path,
        locked: true,
        pinSet: true,
        overrides: overrides,
        wrap: (router, child) => QuickExitZone(router: router, child: child),
      );
      // The PIN was asked for on the way in (the lock is on).
      s.container.read(datingUnlockedProvider.notifier).unlock();
      s.router.go(path);
      await t.pumpAndSettle();
      expect(s.location, path);
      final filled = await _fill(s);
      await _quickExit(t);
      await t.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('DECOY'), findsOneWidget);
      expect(DatingPageWatch.open, 0);
      _expectWiped(s, filled);
      expect(s.lock.on, isTrue);
      expect(
        await const FlutterSecureStorage().read(key: 'safety_pin_hash'),
        isNotNull,
      );
    });
  }

  testWidgets('quick exit never cancels a scheduled check-in', (t) async {
    final chat = FakeDatingChat()..checkinAt = DateTime(2026, 11, 22, 21);
    await pumpDatingShell(
      t,
      initial: DatingPaths.plan('m1'),
      overrides: datingChatOverrides(chat),
      wrap: (router, child) => QuickExitZone(router: router, child: child),
    );
    final before = List.of(chat.checkins);
    await _quickExit(t);
    await t.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('DECOY'), findsOneWidget);
    expect(chat.checkins, before);
    expect(chat.checkinAt, isNotNull);
  });

  testWidgets('no frame of Dating shows once quick exit is pressed', (t) async {
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.today,
      overrides: datingTodayOverrides(FakeDatingToday()),
      wrap: (router, child) => QuickExitZone(router: router, child: child),
    );
    expect(find.textContaining('Kofi'), findsWidgets);
    for (var i = 0; i < 3; i++) {
      await t.tap(
        find.byKey(const Key('quick_exit_zone')),
        warnIfMissed: false,
      );
      if (i < 2) await t.pump(const Duration(milliseconds: 50));
    }
    // The decoy's first frame: its transition has only begun, and the
    // Today page under it is already blank.
    await t.pump();
    expect(find.textContaining('Kofi', skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('dating_blank_page')), findsWidgets);
    await t.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('DECOY'), findsOneWidget);
    // Dating opened again afterwards shows as before.
    s.router.go(DatingPaths.today);
    await t.pumpAndSettle();
    expect(find.textContaining('Kofi'), findsWidgets);
    expect(find.byKey(const ValueKey('dating_blank_page')), findsNothing);
  });

  testWidgets('sign-out empties the same memory; the Safety PIN stays '
      '(the lock is Spec 1\'s to clear at sign-out)', (t) async {
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.today,
      pinSet: true,
      overrides: datingTodayOverrides(FakeDatingToday()),
    );
    final filled = await _fill(s);
    await DeviceWipeRegistry.instance.run(WipeMoment.signOut);
    await t.pump();
    expect(find.byKey(const ValueKey('dating_blank_page')), findsWidgets);
    _expectWiped(s, filled);
    expect(
      await const FlutterSecureStorage().read(key: 'safety_pin_hash'),
      isNotNull,
    );
  });

  testWidgets('a hanging Dating entry never stalls the exit', (t) async {
    DeviceWipeRegistry.instance.register(
      DeviceWipeEntry(
        id: 'spec2.test_hang',
        order: 20,
        moments: const {WipeMoment.quickExit},
        run: () => Completer<void>().future,
      ),
    );
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.today,
      overrides: datingTodayOverrides(FakeDatingToday()),
      wrap: (router, child) => QuickExitZone(router: router, child: child),
    );
    final filled = await _fill(s);
    await _quickExit(t);
    await t.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('DECOY'), findsOneWidget);
    _expectWiped(s, filled);
  });
}
````

- [ ] **Step 3: Run it to see it fail**

```bash
flutter test --no-pub test/features/dating/device/dating_device_wipe_test.dart 2>&1 | tr '\r' '\n' | grep -E "Error: (Error when reading|Couldn't|Undefined)|Some tests failed" | head -3
```

Expected: a compile error naming `dating_surface.dart` (it doesn't exist yet), then `Some tests failed.`

- [ ] **Step 4: Create `DatingSurface` and `DatingBlankPage`**

Create `lib/features/dating/device/dating_surface.dart` with exactly:

````dart
// Spec 2 W8a (§6.7; W6 final carry: quick exit's decoy slid in over about
// 300 ms of Dating): once quick exit or sign-out runs, every Dating page
// shows a blank page of the theme's background, in the same frame the
// decoy starts. A Dating page opened after every one of them is gone shows
// again (DatingPageWatch). Memory only.
import 'package:flutter/material.dart';

abstract final class DatingSurface {
  /// True from quick exit or sign-out until every Dating page is gone.
  static final hidden = ValueNotifier<bool>(false);

  /// The device wipe entry: synchronous before its first await, so the
  /// pages are blank before the decoy's first frame.
  static Future<void> hide() async {
    hidden.value = true;
  }

  static void reset() => hidden.value = false;
}

/// What a Dating page shows once [DatingSurface] is hidden: nothing.
class DatingBlankPage extends StatelessWidget {
  const DatingBlankPage({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const ValueKey('dating_blank_page'),
    color: Theme.of(context).scaffoldBackgroundColor,
    child: const SizedBox.expand(),
  );
}
````

- [ ] **Step 5: The keys' clear, the tracked report keys, the blank page and the two entries**

Create `.superpowers/sdd/2026-11-22-spec2-w8/edit_app_T1.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W8a Task 1 (§6.7, §7.4; C-2, C-3; carries 3, 4): Dating's last
# in-memory data joins the device wipe. The report and appeal request keys
# (they hold what was typed, as the key's signature) are emptied with the
# session; Dating's pages go blank the moment quick exit or sign-out runs
# (no frame of Dating under the decoy's transition); a second, later entry
# sweeps every Dating memory again after Spec 1's own entries (§6.7's
# spec2.section_caches, order 20). Formatter-style edits (W3a-W7 files,
# never formatted).
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-22-spec2-w8/anchor.py')['edit']

edit('lib/features/dating/data/dating_rpc.dart', [
    ("""    _held.remove(action);
  }
}
""", """    _held.remove(action);
  }

  /// Spec 2 W8a (§6.7): every held key goes (quick exit, sign-out).
  void clear() => _held.clear();
}
"""),
], 'T1 keys clear')

edit('lib/features/dating/report/dating_report_providers.dart', [
    ("""import 'package:attune/features/dating/data/dating_rpc.dart';
""", """import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart'
    show DatingSessionMemory;
"""),
    ("""/// that is final frees the key.
final datingReportKeysProvider = Provider.family<DatingActionKeys, String?>(
  (ref, account) => DatingActionKeys(),
);
""", """/// that is final frees the key. Spec 2 W8a (§6.7): a key's
/// signature holds what was typed, so quick exit and sign-out empty it
/// (Dating's session entry in the device wipe registry).
final datingReportKeysProvider = Provider.family<DatingActionKeys, String?>((
  ref,
  account,
) {
  final keys = DatingActionKeys();
  DatingSessionMemory.track(keys, ref, keys.clear);
  return keys;
});
"""),
], 'T1 report keys')

edit('lib/features/dating/routes/dating_page_watch.dart', [
    ("""// sign-out clear them too (the device wipe registry).
import 'package:attune/features/dating/today/dating_photo_memory.dart';
""", """// sign-out clear them too (the device wipe registry).
//
// Spec 2 W8a (§6.7; W6 final carry: the quick-exit decoy's transition
// showed about 300 ms of Dating): every page shows nothing once quick exit
// or sign-out has run (DatingSurface), until every Dating page is gone.
import 'package:attune/features/dating/device/dating_surface.dart';
import 'package:attune/features/dating/today/dating_photo_memory.dart';
"""),
    ("""  void initState() {
    super.initState();
    DatingPageWatch._open++;
  }
""", """  void initState() {
    super.initState();
    // W8a: a page opened after every Dating page is gone shows again.
    if (DatingPageWatch._open <= 0) {
      DatingSurface.reset();
    }
    DatingPageWatch._open++;
  }
"""),
    ("""      DatingPageWatch._open = 0;
      DatingPhotoMemory.clearForLeave();
""", """      DatingPageWatch._open = 0;
      DatingPhotoMemory.clearForLeave();
      DatingSurface.reset();
"""),
    ("""  Widget build(BuildContext context) => widget.child;
""", """  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: DatingSurface.hidden,
    child: widget.child,
    builder:
        (context, hidden, child) =>
            hidden ? const DatingBlankPage() : child!,
  );
"""),
], 'T1 page watch')

edit('lib/features/dating/dating_device_wipes.dart', [
    ("""// adds the caches here; quick_exit_service.dart and auth_provider.dart are
// never edited. Nothing here is protective: the Dating lock stays.
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/dating/chat/plan_meet_screen.dart';
""", """// adds the caches here; quick_exit_service.dart and auth_provider.dart are
// never edited. Nothing here is protective: the Dating lock stays.
// Spec 2 W8a (§6.7): the pages go blank first (order 0, before Spec 1's
// awaited entries), and §6.7's spec2.section_caches sweeps every Dating
// memory again after them (order 20). No entry touches the lock, the
// Safety PIN, the app icon or a scheduled check-in, and none awaits I/O.
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/dating/chat/plan_meet_screen.dart';
import 'package:attune/features/dating/device/dating_surface.dart';
"""),
    ("""      run: DatingPlanMemory.clear,
    ),
  );
}
""", """      run: DatingPlanMemory.clear,
    ),
  );
  // Spec 2 W8a (§6.7; W6 final carry): no frame of Dating under the decoy.
  (registry ?? DeviceWipeRegistry.instance).register(
    const DeviceWipeEntry(
      id: 'spec2.dating_surface',
      moments: {WipeMoment.signOut, WipeMoment.quickExit},
      run: DatingSurface.hide,
    ),
  );
  // Spec 2 W8a (§6.7): every Dating memory again, after Spec 1's entries.
  (registry ?? DeviceWipeRegistry.instance).register(
    const DeviceWipeEntry(
      id: 'spec2.section_caches',
      order: 20,
      moments: {WipeMoment.signOut, WipeMoment.quickExit},
      run: clearDatingDeviceData,
    ),
  );
}

/// §6.7's sweep: the session (unlock, open answers, unsent dismissals, the
/// report and appeal keys), the other people's photos with their decoded
/// copies, and the meet plan with the check-in time the kit read. Memory
/// only: no I/O, no SharedPreferences, no platform channel, and the
/// check-in itself stays scheduled on the server (safety).
Future<void> clearDatingDeviceData() async {
  await DatingSessionMemory.clear();
  await DatingPhotoMemory.clear();
  await DatingPlanMemory.clear();
}
"""),
], 'T1 wipe entries')
````

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
dart format lib/features/dating/device/dating_surface.dart test/features/dating/device/dating_device_wipe_test.dart
python3 -I $D/edit_app_T1.py
```

Expected: `Formatted 2 files (0 changed)`, then `lib/features/dating/data/dating_rpc.dart: 1 edit(s) (T1 keys clear)`, `…dating_report_providers.dart: 2 edit(s) (T1 report keys)`, `…dating_page_watch.dart: 4 edit(s) (T1 page watch)`, `…dating_device_wipes.dart: 2 edit(s) (T1 wipe entries)`.

- [ ] **Step 6: Run the test and the analyzer**

```bash
flutter test --no-pub test/features/dating/device/dating_device_wipe_test.dart 2>&1 | tr '\r' '\n' | grep -oE '\+[0-9]+( -[0-9]+)?: (All tests passed!|Some tests failed\.)' | tail -1
flutter analyze --no-pub lib/features/dating test/features/dating/device 2>&1 | tail -1
```

Expected: `+8: All tests passed!`; `No issues found!`

- [ ] **Step 7: The mutants (each must turn the test red)**

Create `.superpowers/sdd/2026-11-22-spec2-w8/mut_T1_dart.py` with exactly:

````python
# Spec 2 W8a Task 1: Dart mutants (dmut.py, in a private copy). Each must
# turn the device wipe test red; a COMPILE is a broken mutant, never a kill.
T = ['test/features/dating/device/dating_device_wipe_test.dart']
W = 'lib/features/dating/dating_device_wipes.dart'
P = 'lib/features/dating/routes/dating_page_watch.dart'
MUTS = {
    'keys_not_wiped': ('lib/features/dating/report/dating_report_providers.dart',
                       '  DatingSessionMemory.track(keys, ref, keys.clear);\n', '', T),
    'keys_clear_noop': ('lib/features/dating/data/dating_rpc.dart',
                        '  void clear() => _held.clear();\n', '  void clear() {}\n', T),
    'surface_not_registered': (W, "      id: 'spec2.dating_surface',\n      moments: {WipeMoment.signOut, WipeMoment.quickExit},\n",
                               "      id: 'spec2.dating_surface',\n      moments: {WipeMoment.signOut},\n", T),
    'sweep_not_after_spec1': (W, '      order: 20,\n', '      order: 0,\n', T),
    'sweep_skips_signout': (W, "      order: 20,\n      moments: {WipeMoment.signOut, WipeMoment.quickExit},\n",
                            "      order: 20,\n      moments: {WipeMoment.quickExit},\n", T),
    # The page listens to a notifier nobody flips (the line survives Task 2).
    'page_ignores_surface': (P, '    valueListenable: DatingSurface.hidden,\n', '    valueListenable: ValueNotifier<bool>(false),\n', T),
    # Both resets go (either alone suffices: the last page's dispose, or
    # the first new page's init).
    'blank_never_resets': (P, [('    if (DatingPageWatch._open <= 0) {\n      DatingSurface.reset();\n', '    if (DatingPageWatch._open <= 0) {\n'),
                               ('      DatingPhotoMemory.clearForLeave();\n      DatingSurface.reset();\n',
                                '      DatingPhotoMemory.clearForLeave();\n')], None, T),
}
````

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
python3 -I $D/dmut.py $D/mut_T1_dart.py | tee $D/mut_T1_dart.txt | tail -1
```

Expected: `7/7 killed` (every line `KILLED`; `dmut.py` mutates a private copy of the tree, never the working tree).

- [ ] **Step 8: Record the tree (do not commit)**

```bash
T=$(mktemp -u); GIT_INDEX_FILE=$T git read-tree HEAD && GIT_INDEX_FILE=$T git add -A && GIT_INDEX_FILE=$T git write-tree; rm -f $T
```

### Task 2: The screen protection: Android `FLAG_SECURE`, the iOS capture blur, no gallery saves (§3.0 Discretion, §6.7, §7.4, §7.7; F-4; carry 2; R-71)

**Files:**
- Create: `lib/features/dating/device/dating_discretion.dart`, `test/features/dating/device/dating_discretion_test.dart`, `$D/{edit_app_T2.py, edit_native_T2.py, mut_T2_dart.py}`
- Modify: `lib/features/dating/routes/dating_page_watch.dart`, `android/app/src/main/kotlin/com/barsopus/attune/MainActivity.kt` (`attune/safety`: `setSecure`), `ios/Runner/AppDelegate.swift` (an `attune/safety` channel: `setSecure`, the capture watch, `captureChanged`)
- Test: `test/features/dating/device/dating_discretion_test.dart`

**Interfaces:**
- Consumes: Task 1's `DatingPageWatch` text (its first page and last page), `pumpDatingShell`, `RouteNames.safetyPin`.
- Produces: `DatingDiscretion.{channel, captured, setSecure(bool), secure, reset()}`, `DatingCaptureCover` (key `dating_capture_cover` while captured); native `attune/safety` `setSecure(bool) → bool` (Android always `false`; iOS whether the screen is captured now) and iOS's `captureChanged(bool)` calls.

- [ ] **Step 1: Write the failing test**

Create `test/features/dating/device/dating_discretion_test.dart` with exactly:

````dart
// Spec 2 W8a (§3.0 Discretion, §6.7, §7.4, §7.7; F-4): the screen is
// protected while any Dating page is open: setSecure(true) on the
// attune/safety channel when the first one opens, setSecure(false) when
// the last one closes (mock channel; FLAG_SECURE itself is a device
// check). A page pushed over Dating keeps it; a go() from one Dating page
// to another never drops it. On iOS a Dating page blurs while the screen
// is captured (the answer, then captureChanged), and nothing else does.
// No Dating file shows a network image, offers a long press or shares a
// file (no gallery saves).
import 'dart:io';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/features/dating/device/dating_discretion.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dating_shell.dart';

const _channel = MethodChannel('attune/safety');

void main() {
  final calls = <Object?>[];
  var captured = false;

  setUp(() {
    calls.clear();
    captured = false;
    DatingDiscretion.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method != 'setSecure') return null;
          calls.add(call.arguments);
          return captured && call.arguments == true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null),
    );
  });

  /// iOS saying the capture changed.
  Future<void> nativeSays(WidgetTester t, bool on) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'attune/safety',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('captureChanged', on),
          ),
          (_) {},
        );
    await t.pump();
  }

  testWidgets('FLAG_SECURE: on with the first Dating page, kept from one '
      'Dating page to the next and under a page pushed over it, off after '
      'the last', (t) async {
    final s = await pumpDatingShell(t);
    expect(calls, isEmpty);
    s.router.push(DatingPaths.settings);
    await t.pumpAndSettle();
    expect(calls, [true]);
    expect(DatingDiscretion.secure, isTrue);
    s.router.push(DatingPaths.neverIntroduce);
    await t.pumpAndSettle();
    s.router.go(DatingPaths.settings);
    await t.pumpAndSettle();
    s.router.push(RouteNames.safetyPin);
    await t.pumpAndSettle();
    expect(find.text('PIN SETUP'), findsOneWidget);
    expect(calls, [true]);
    s.router.pop();
    await t.pumpAndSettle();
    s.router.go(RouteNames.home);
    await t.pumpAndSettle();
    expect(calls, [true, false]);
    expect(DatingDiscretion.secure, isFalse);
  });

  testWidgets('a deep link straight into Dating is protected from its first '
      'frame', (t) async {
    await pumpDatingShell(t, initial: DatingPaths.chats);
    expect(calls, [true]);
  });

  testWidgets('iOS: a Dating page blurs while the screen is captured, and '
      'clears when capture ends', (t) async {
    captured = true;
    final s = await pumpDatingShell(t, initial: DatingPaths.settings);
    expect(find.byKey(const ValueKey('dating_capture_cover')), findsOneWidget);
    await nativeSays(t, false);
    expect(find.byKey(const ValueKey('dating_capture_cover')), findsNothing);
    await nativeSays(t, true);
    expect(find.byKey(const ValueKey('dating_capture_cover')), findsOneWidget);
    s.router.go(RouteNames.home);
    await t.pumpAndSettle();
    // Off Dating, a late captureChanged blurs nothing.
    await nativeSays(t, true);
    expect(DatingDiscretion.captured.value, isFalse);
    expect(
      find.byKey(const ValueKey('dating_capture_cover'), skipOffstage: false),
      findsNothing,
    );
  });

  test(
    'the native side: FLAG_SECURE on attune/safety (Android); the '
    'capture watch with sceneCaptureState and the isCaptured fallback (iOS)',
    () {
      final kt =
          File(
            'android/app/src/main/kotlin/com/barsopus/attune/MainActivity.kt',
          ).readAsStringSync();
      expect(kt, contains('"setSecure" ->'));
      expect(
        kt,
        contains('window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)'),
      );
      expect(
        kt,
        contains('window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)'),
      );
      final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      expect(swift, contains('name: "attune/safety"'));
      expect(swift, contains('case "setSecure":'));
      expect(swift, contains('sceneCaptureState == .active'));
      expect(swift, contains('UITraitSceneCaptureState.self'));
      expect(swift, contains('screen.isCaptured'));
      expect(swift, contains('UIScreen.capturedDidChangeNotification'));
      expect(swift, contains('invokeMethod("captureChanged"'));
    },
  );

  test('no gallery saves: no Dating file shows a network image, offers a '
      'long press, saves to the gallery or shares a file', () {
    final banned = RegExp(
      r'Image\.network|NetworkImage|cached_network_image|onLongPress|'
      r'image_gallery_saver|package:gal/|saveImage|shareXFiles|shareFiles|XFile\(',
    );
    for (final f in Directory(
      'lib/features/dating',
    ).listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      expect(banned.hasMatch(src), isFalse, reason: f.path);
      // The meeting kit shares its words through the share sheet, never
      // a photo or a file.
      if (src.contains('share_plus')) {
        expect(f.path, endsWith('chat/plan_meet_screen.dart'));
      }
    }
  });
}
````

- [ ] **Step 2: Run it to see it fail**

```bash
flutter test --no-pub test/features/dating/device/dating_discretion_test.dart 2>&1 | tr '\r' '\n' | grep -E "Error: (Error when reading|Couldn't)|Some tests failed" | head -2
```

Expected: a compile error naming `dating_discretion.dart`, then `Some tests failed.`

- [ ] **Step 3: Create `DatingDiscretion` and `DatingCaptureCover`**

Create `lib/features/dating/device/dating_discretion.dart` with exactly:

````dart
// Spec 2 W8a (§3.0 Discretion, §6.7, §7.4; F-4): while any Dating page is
// open, the screen is protected. Android: FLAG_SECURE on the window
// (screenshots and screen recording come out black, the Recents thumbnail
// too). iOS can't block screenshots: the app switcher is covered by the
// existing AppPrivacyCover, and Dating pages blur while the screen is
// being captured (recorded or mirrored): sceneCaptureState on iOS 17 and
// later, UIScreen.isCaptured before. Both through the existing
// attune/safety channel (MainActivity.kt, AppDelegate.swift): setSecure
// answers whether the screen is captured now, and iOS calls
// captureChanged(bool) while it watches. Nothing is stored or sent.
import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

abstract final class DatingDiscretion {
  static const channel = MethodChannel('attune/safety');

  /// True while iOS says the screen is being captured (never on Android:
  /// FLAG_SECURE blanks the capture itself).
  static final captured = ValueNotifier<bool>(false);

  static bool _secure = false;
  static bool _listening = false;

  /// Whether the last call asked for protection (tests).
  @visibleForTesting
  static bool get secure => _secure;

  /// [on]: the first Dating page opened; off: the last one closed. Never
  /// throws: a phone without the channel (a test, the web) stays as it is.
  static Future<void> setSecure(bool on) async {
    _secure = on;
    if (!_listening) {
      _listening = true;
      channel.setMethodCallHandler(_onCall);
    }
    if (!on) captured.value = false;
    try {
      final now = await channel.invokeMethod<bool>('setSecure', on);
      // A late answer for an earlier call changes nothing.
      if (_secure == on) captured.value = on && now == true;
    } catch (_) {
      // No channel here: nothing to protect with.
    }
  }

  static Future<Object?> _onCall(MethodCall call) async {
    if (call.method == 'captureChanged') {
      captured.value = _secure && call.arguments == true;
    }
    return null;
  }

  /// Back to the first launch's state (tests).
  @visibleForTesting
  static void reset() {
    _secure = false;
    _listening = false;
    captured.value = false;
  }
}

/// A Dating page while the screen is being captured: blurred past reading,
/// and not announced (a recording can carry a screen reader's voice).
class DatingCaptureCover extends StatelessWidget {
  const DatingCaptureCover({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: DatingDiscretion.captured,
    child: child,
    builder:
        (context, captured, child) =>
            captured
                ? ExcludeSemantics(
                  key: const ValueKey('dating_capture_cover'),
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                    child: AbsorbPointer(child: child),
                  ),
                )
                : child!,
  );
}
````

- [ ] **Step 4: The page watch turns the protection on and off and blurs while captured; the native side**

Create `.superpowers/sdd/2026-11-22-spec2-w8/edit_app_T2.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W8a Task 2 (§3.0, §6.7, §7.4; F-4): the screen is protected while
# any Dating page is open (the first opens it, the last closes it), and a
# page blurs while iOS says the screen is captured. Formatter-style edits
# (Task 1's text of DatingPageWatch).
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-22-spec2-w8/anchor.py')['edit']

edit('lib/features/dating/routes/dating_page_watch.dart', [
    ("""// or sign-out has run (DatingSurface), until every Dating page is gone.
import 'package:attune/features/dating/device/dating_surface.dart';
""", """// or sign-out has run (DatingSurface), until every Dating page is gone.
// W8a Task 2 (§6.7; F-4): while any Dating page is open the screen is
// protected (FLAG_SECURE on Android) and pages blur while iOS says the
// screen is captured (DatingDiscretion). A stricter reading of "a Dating
// route on top": a page pushed over a Dating page (the PIN setup) is
// protected too.
import 'dart:async';

import 'package:attune/features/dating/device/dating_discretion.dart';
import 'package:attune/features/dating/device/dating_surface.dart';
"""),
    ("""    if (DatingPageWatch._open <= 0) {
      DatingSurface.reset();
    }
    DatingPageWatch._open++;
  }
""", """    if (DatingPageWatch._open <= 0) {
      DatingSurface.reset();
      // W8a Task 2: the first page turns the protection on.
      unawaited(DatingDiscretion.setSecure(true));
    }
    DatingPageWatch._open++;
  }
"""),
    ("""      DatingPhotoMemory.clearForLeave();
      DatingSurface.reset();
""", """      DatingPhotoMemory.clearForLeave();
      DatingSurface.reset();
      // W8a Task 2: the last page turns it off.
      unawaited(DatingDiscretion.setSecure(false));
"""),
    ("""            hidden ? const DatingBlankPage() : child!,
  );
""", """            hidden
                ? const DatingBlankPage()
                : DatingCaptureCover(child: child!),
  );
"""),
], 'T2 page watch')
````

Create `.superpowers/sdd/2026-11-22-spec2-w8/edit_native_T2.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W8a Task 2 (§3.0, §6.7, §7.7; F-4): the attune/safety channel
# gains setSecure. Android: FLAG_SECURE on the window while any Dating page
# is open. iOS (the channel is new there; quick exit's finishAndRemoveTask
# stays Android-only): watch the screen's capture state while any Dating
# page is open (sceneCaptureState from iOS 17, UIScreen.isCaptured before)
# and say captureChanged(bool). Exact edits; the device checks are the
# owner's (§7.7).
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-22-spec2-w8/anchor.py')['edit']

edit('android/app/src/main/kotlin/com/barsopus/attune/MainActivity.kt', [
    ("""import android.telephony.TelephonyManager
""", """import android.telephony.TelephonyManager
import android.view.WindowManager
"""),
    ("""        // Quick exit (Spec 2; research 06 §3 F3 (2)): leave AND drop the
        // task, so Attune is not left in Recents. The only method on this
        // channel; nothing is logged or sent. Reply first: once the activity
        // finishes the engine may be gone.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "attune/safety")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "finishAndRemoveTask" -> {
                        result.success(null)
                        finishAndRemoveTask()
                    }
""", """        // Quick exit (Spec 2; research 06 §3 F3 (2)): leave AND drop the
        // task, so Attune is not left in Recents. Nothing is logged or sent.
        // Reply first: once the activity finishes the engine may be gone.
        // Spec 2 W8a (§6.7): setSecure(bool) puts FLAG_SECURE on the window
        // while any Dating page is open (screenshots, screen recording and
        // the Recents thumbnail come out blank) and takes it off after the
        // last one; it answers false (Android never reports a capture).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "attune/safety")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "finishAndRemoveTask" -> {
                        result.success(null)
                        finishAndRemoveTask()
                    }
                    "setSecure" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(false)
                    }
"""),
], 'T2 Android')

edit('ios/Runner/AppDelegate.swift', [
    ("""  private var ageSignalsChannel: FlutterMethodChannel?
  private var switcherCover: UIView?
""", """  private var ageSignalsChannel: FlutterMethodChannel?
  private var switcherCover: UIView?
  // Spec 2 W8a (§6.7; F-4): attune/safety on iOS. While any Dating page is
  // open the screen's capture state is watched (recording, mirroring) and
  // every change is sent as captureChanged(bool); the Dating pages blur.
  // iOS can't block a screenshot; the app switcher is covered above.
  private var safetyChannel: FlutterMethodChannel?
  private var captureWatching = false
  private var captureObserver: NSObjectProtocol?
  private var captureRegistration: Any?
"""),
    ("""    TogetherLiveActivityChannel.register(with: controller.binaryMessenger)
""", """    let safety = FlutterMethodChannel(
      name: "attune/safety",
      binaryMessenger: controller.binaryMessenger
    )
    safetyChannel = safety
    safety.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "setSecure":
        let on = (call.arguments as? Bool) ?? false
        self?.watchCapture(on)
        result(on && (self?.screenIsCaptured() ?? false))
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    TogetherLiveActivityChannel.register(with: controller.binaryMessenger)
"""),
    ("""  private func showSwitcherCover() {
""", """  // Spec 2 W8a (F-4): sceneCaptureState where available (iOS 17 and
  // later), the deprecated UIScreen.isCaptured only before.
  private func screenIsCaptured() -> Bool {
    if #available(iOS 17.0, *), let scene = window?.windowScene {
      return scene.traitCollection.sceneCaptureState == .active
    }
    return window?.screen.isCaptured ?? false
  }

  private func watchCapture(_ on: Bool) {
    guard on != captureWatching else { return }
    captureWatching = on
    if !on {
      if let observer = captureObserver {
        NotificationCenter.default.removeObserver(observer)
        captureObserver = nil
      }
      if #available(iOS 17.0, *), let registration = captureRegistration as? UITraitChangeRegistration {
        window?.windowScene?.unregisterForTraitChanges(registration)
      }
      captureRegistration = nil
      return
    }
    if #available(iOS 17.0, *), let scene = window?.windowScene {
      captureRegistration = scene.registerForTraitChanges(
        [UITraitSceneCaptureState.self]
      ) { [weak self] (_: UIWindowScene, _: UITraitCollection) in
        self?.sendCapture()
      }
    } else {
      captureObserver = NotificationCenter.default.addObserver(
        forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.sendCapture() }
    }
  }

  private func sendCapture() {
    guard captureWatching else { return }
    safetyChannel?.invokeMethod("captureChanged", arguments: screenIsCaptured())
  }

  private func showSwitcherCover() {
"""),
], 'T2 iOS')
````

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
dart format lib/features/dating/device/dating_discretion.dart test/features/dating/device/dating_discretion_test.dart
python3 -I $D/edit_app_T2.py
python3 -I $D/edit_native_T2.py
```

Expected: `Formatted 2 files (0 changed)`; `…dating_page_watch.dart: 4 edit(s) (T2 page watch)`; `…MainActivity.kt: 2 edit(s) (T2 Android)`; `ios/Runner/AppDelegate.swift: 3 edit(s) (T2 iOS)`.

- [ ] **Step 5: Run the tests, the analyzer, and type-check the Swift against the iOS SDK**

```bash
flutter test --no-pub test/features/dating/device 2>&1 | tr '\r' '\n' | grep -oE '\+[0-9]+( -[0-9]+)?: (All tests passed!|Some tests failed\.)' | tail -1
flutter analyze --no-pub lib/features/dating test/features/dating/device 2>&1 | tail -1
S=$(mktemp -d); printf 'import Flutter\nclass GeneratedPluginRegistrant { static func register(with registry: FlutterPluginRegistry) {} }\nenum TogetherLiveActivityChannel { static func register(with messenger: FlutterBinaryMessenger) {} }\n' > $S/Stub.swift
FW=$(dirname $(dirname $(readlink -f $(which flutter))))/bin/cache/artifacts/engine/ios/Flutter.xcframework/ios-arm64
xcrun --sdk iphoneos swiftc -typecheck -target arm64-apple-ios12.0 -sdk $(xcrun --sdk iphoneos --show-sdk-path) -F $FW ios/Runner/AppDelegate.swift $S/Stub.swift; echo "swift exit=$?"; rm -rf $S
```

Expected: `+13: All tests passed!`; `No issues found!`; `swift exit=0` with no warning (the Runner target ships at iOS 12.0: `sceneCaptureState` is behind `#available(iOS 17.0, *)`). On a machine without Xcode the Swift check is the owner's (Owner checklist 4).

- [ ] **Step 6: The mutants**

Create `.superpowers/sdd/2026-11-22-spec2-w8/mut_T2_dart.py` with exactly:

````python
# Spec 2 W8a Task 2: Dart mutants (dmut.py, in a private copy).
T = ['test/features/dating/device/dating_discretion_test.dart']
P = 'lib/features/dating/routes/dating_page_watch.dart'
X = 'lib/features/dating/device/dating_discretion.dart'
MUTS = {
    'secure_never_on': (P, '      unawaited(DatingDiscretion.setSecure(true));\n', '', T),
    'secure_never_off': (P, '      unawaited(DatingDiscretion.setSecure(false));\n', '', T),
    'answer_ignored': (X, '      if (_secure == on) captured.value = on && now == true;\n', '', T),
    'capture_change_ignored': (X, "      captured.value = _secure && call.arguments == true;\n",
                               "      captured.value = captured.value;\n", T),
    'capture_after_leave': (X, "      captured.value = _secure && call.arguments == true;\n",
                            "      captured.value = call.arguments == true;\n", T),
    'cover_not_used': (P, '                : DatingCaptureCover(child: child!),\n', '                : child!,\n', T),
    'android_never_clears': ('android/app/src/main/kotlin/com/barsopus/attune/MainActivity.kt',
                             '                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)\n',
                             '                            Unit\n', T),
    'ios_no_fallback': ('ios/Runner/AppDelegate.swift', '    return window?.screen.isCaptured ?? false\n',
                        '    return false\n', T),
}
````

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
python3 -I $D/dmut.py $D/mut_T2_dart.py | tee $D/mut_T2_dart.txt | tail -1
```

Expected: `8/8 killed`.

- [ ] **Step 7: Record the tree (do not commit)** — as Task 1 Step 8.

### Task 3: Every Dating route, push tap and deep link behind the lock; every Dating push neutral; the manual; the W8a gate (§3.0 Lock, §3.13, §3.14, §7.4, §7.7; I-9; carry 8)

**Files:**
- Create: `supabase/tests/dating_v2_device_contracts.sql` (section A), `test/features/dating/device/dating_lock_entry_test.dart`, `$D/{edit_docs_T3.py, mut_T3.py, mut_T3_dart.py, gate.sh}`
- Modify: `lib/app/documentations/user_manual/data/dating_mode_docs.dart` (`dating_screen`)
- Test: both new files

**Interfaces:**
- Consumes: `datingRoutes()`, `DatingPaths`, `datingRedirect`, `DatingLockGate`, `buildNanoEmbryoNotificationConfig()`, `private.dating_queue_me_update`, `public.schedule_dating_checkin`.
- Produces: `dating_v2_device_contracts.sql` with section A and the marker `-- @@W8B@@`; `$D/gate.sh <W8a|W8b> <db>`.

- [ ] **Step 1: Write the contract (section A) and the route test**

Create `supabase/tests/dating_v2_device_contracts.sql` with exactly:

````sql
-- supabase/tests/dating_v2_device_contracts.sql
-- Spec 2 W8 (§3.13, §2.3, §2.5, §3.11, §6.7, §7.1, §7.2 S4): device
-- discretion and travel.
--   A (W8a). Every Dating push is neutral: every function that writes the
--      push queue and is Dating's (by name, or by naming a Dating relation)
--      writes only the types me_update and me_checkin, titled "Attune",
--      routed to me or me_checkin, and no literal it writes there says
--      "dating" (§3.13, I-9). The app routes exactly those (and the old
--      dating_mutual_match, to Me, for one release: A-7).
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_device_contracts.sql
BEGIN;

-- =====================================================================
-- A. Every Dating push is neutral (W8a).
-- =====================================================================
DO $$
DECLARE
  r record;
  v_types text[];
  v_bad text := '';
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure::text AS sig, p.prosrc AS src
      FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
     WHERE n.nspname IN ('public', 'private') AND p.prokind = 'f'
       AND p.prosrc ~ 'scheduled_notifications'
       AND p.prosrc ~* '\m(insert\s+into|update)\s+public\.scheduled_notifications'
       AND (p.proname ~ '(dating|moderation)' OR p.prosrc ~ 'public\.dating_\w+')
  LOOP
    v_types := ARRAY(SELECT DISTINCT m[1] FROM regexp_matches(r.src, '''type''\s*,\s*''([a-z_]+)''', 'g') AS m);
    -- A writer (an insert) names its type; an update (a cancel) needs none.
    IF (r.src ~* '\minsert\s+into\s+public\.scheduled_notifications' AND cardinality(v_types) = 0)
       OR NOT (v_types <@ ARRAY['me_update', 'me_checkin']) THEN
      v_bad := v_bad || format(E'\n  %s writes push types %s', r.sig, v_types);
    END IF;
    IF r.src ~ '''route''\s*,\s*''' AND EXISTS (
         SELECT 1 FROM regexp_matches(r.src, '''route''\s*,\s*''([a-z_]+)''', 'g') AS m
          WHERE m[1] NOT IN ('me', 'me_checkin')) THEN
      v_bad := v_bad || format(E'\n  %s routes a push outside me and me_checkin', r.sig);
    END IF;
    IF EXISTS (SELECT 1 FROM regexp_matches(r.src, '''title''\s*,\s*''([^'']*)''', 'g') AS m WHERE m[1] <> 'Attune') THEN
      v_bad := v_bad || format(E'\n  %s titles a push other than Attune', r.sig);
    END IF;
    -- Every literal on a line that builds the payload (the one naming its
    -- type): none says "dating".
    IF EXISTS (SELECT 1 FROM regexp_split_to_table(r.src, E'\n') AS l
                WHERE l ~ '''type''\s*,' AND l ~* '''[^'']*dating[^'']*''') THEN
      v_bad := v_bad || format(E'\n  %s puts "dating" in a push payload', r.sig);
    END IF;
  END LOOP;
  IF v_bad <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a Dating push is not neutral:%', v_bad;
  END IF;
  -- The writers this audit reads (so a rename can't empty it).
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'dating_queue_me_update')
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'schedule_dating_checkin') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Dating push writers moved; the audit reads nothing';
  END IF;
END $$;

-- @@W8B@@
DO $$ BEGIN RAISE NOTICE 'dating_v2_device_contracts: all held'; END $$;
ROLLBACK;
````

Create `test/features/dating/device/dating_lock_entry_test.dart` with exactly:

````dart
// Spec 2 W8a (§3.0 Lock, §3.13, §3.14, §7.4, §7.7; I-9; carry: every
// Dating push type and route honours the Dating lock): with the lock on,
// every Dating route asks for the Safety PIN first, whether it is opened
// from inside the app, by a deep link (the platform's route) or as the
// first page of a cold start; nothing of the page is built until then.
// Every Dating push the server can send (me_update, me_checkin; the old
// dating_mutual_match for one release) opens Me or the check-in, the
// check-in behind the PIN. The route list is read from datingRoutes(), so
// a route a later wave adds is covered without editing this file.
import 'package:attune/core/notifications/config/notification_config.dart';
import 'package:attune/core/notifications/domain/entities/app_notification.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart';
import 'package:attune/features/dating/routes/dating_page_watch.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/dating_shell.dart';

/// Every Dating route's path with sample parameters (the unlock aside).
List<String> datingLocations() {
  final paths = <String>[];
  void walk(List<RouteBase> routes, String prefix) {
    for (final r in routes) {
      if (r is GoRoute) {
        final full = r.path.startsWith('/') ? r.path : '$prefix/${r.path}';
        paths.add(full);
        walk(r.routes, full);
      } else {
        walk(r.routes, prefix);
      }
    }
  }

  walk(datingRoutes(signedIn: () => true), '');
  return [
    for (final p in paths)
      if (p != DatingPaths.unlock)
        p.replaceAllMapped(
          RegExp(r':(\w+)'),
          (m) => m[1] == 'step' ? 'how' : 'm1',
        ),
  ];
}

void main() {
  final locations = datingLocations();

  test('the route list is the whole Dating group', () {
    expect(locations, contains(DatingPaths.today));
    expect(locations, contains(DatingPaths.checkin));
    expect(locations, contains(DatingPaths.plan('m1')));
    expect(locations.every((l) => l.startsWith('/dating/')), isTrue);
    expect(locations.length, greaterThanOrEqualTo(14));
  });

  for (final location in locations) {
    testWidgets('locked: $location asks for the PIN first, from inside the '
        'app and as a cold start', (t) async {
      final s = await pumpDatingShell(t, locked: true, pinSet: true);
      s.router.go(location);
      await t.pumpAndSettle();
      expect(s.location, startsWith('${DatingPaths.unlock}?from='));
      expect(
        Uri.parse(s.location).queryParameters['from'],
        location,
        reason: 'the unlock comes back to the place asked for',
      );
      // Only the unlock page is built.
      expect(DatingPageWatch.open, 1);
      final cold = await pumpDatingShell(
        t,
        initial: location,
        locked: true,
        pinSet: true,
      );
      expect(cold.location, startsWith('${DatingPaths.unlock}?from='));
      expect(DatingPageWatch.open, 1);
    });
  }

  testWidgets('a deep link (the platform\'s route) into a chat asks for the '
      'PIN first', (t) async {
    final s = await pumpDatingShell(t, locked: true, pinSet: true);
    await t.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(
        const MethodCall('pushRouteInformation', {
          'location': '/dating/chat/m1',
          'state': null,
        }),
      ),
      (_) {},
    );
    await t.pumpAndSettle();
    expect(s.location, startsWith('${DatingPaths.unlock}?from='));
    expect(s.container.read(datingUnlockedProvider), isFalse);
  });

  for (final (type, route, lockedTo, openTo) in [
    ('me_update', 'me', '/home?tab=me', '/home?tab=me'),
    ('dating_mutual_match', 'me', '/home?tab=me', '/home?tab=me'),
    (
      'me_checkin',
      'me_checkin',
      '${DatingPaths.unlock}?from=',
      DatingPaths.checkin,
    ),
  ]) {
    for (final locked in [true, false]) {
      testWidgets('the $type push (locked: $locked)', (t) async {
        late BuildContext tapContext;
        final s = await pumpDatingShell(
          t,
          initial: '/somewhere',
          locked: locked,
          pinSet: true,
          extraRoutes: [
            GoRoute(
              path: '/somewhere',
              builder:
                  (context, _) => Builder(
                    builder: (c) {
                      tapContext = c;
                      return const Scaffold(body: Text('ELSEWHERE'));
                    },
                  ),
            ),
          ],
        );
        buildNanoEmbryoNotificationConfig().onNotificationTap!(
          AppNotification(
            id: 'n1',
            title: 'Attune',
            body: 'You have something new in Attune.',
            data: {'type': type, 'route': route},
            createdAt: DateTime.utc(2026, 11, 22, 9),
          ),
          tapContext,
        );
        await t.pumpAndSettle();
        expect(s.location, startsWith(locked ? lockedTo : openTo));
      });
    }
  }
}
````

- [ ] **Step 2: Run both (they pin what W3a and W6c built; W8 adds no route yet)**

```bash
dart format test/features/dating/device/dating_lock_entry_test.dart
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_device_contracts.sql 2>&1 | grep -oE 'all held|CONTRACT VIOLATED.*'
flutter test --no-pub test/features/dating/device/dating_lock_entry_test.dart 2>&1 | tr '\r' '\n' | grep -oE '\+[0-9]+( -[0-9]+)?: (All tests passed!|Some tests failed\.)' | tail -1
```

Expected: `Formatted 1 file (0 changed)`; `all held`; `+22: All tests passed!` (the route list; 14 routes, each locked from inside the app and as a cold start; the deep link; six push cases; Tasks 7 and 8 add two routes, so the file reaches `+24`). These tests pass on the live code: W3a built the gate; this task pins it. The mutants (Step 4) show they bite.

- [ ] **Step 3: The manual says what the screen protection and quick exit do**

Create `.superpowers/sdd/2026-11-22-spec2-w8/edit_docs_T3.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W8a Task 3 (§6.7, §7.7): the manual's "On your phone" says what
# the screen protection and quick exit do (Plan copy, for the copy
# reviewer). Formatter-style edit (W3c's file, never formatted).
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-22-spec2-w8/anchor.py')['edit']

edit('lib/app/documentations/user_manual/data/dating_mode_docs.dart', [
    ("""              'On a new phone, a phone restored from a backup, or after a problem with your phone or the app, Dating asks you to check it\\'s you before it shows anything: a short video check, or a person looks at two quick photos. It never asks for your ID again. Dating keeps working on up to three of your phones, and a phone you haven\\'t used for Dating in 180 days needs the check again. If you started setting up Dating on another phone and hadn\\'t passed the check yet, you start again on this one, so your answers stay private. Starting again keeps your "Never introduce me" list, and you can still delete it from Leave Dating and delete my data. People kept on your list from before stay protected but aren\\'t shown, and can\\'t be removed one at a time: to remove them, leave Dating and delete your data. If Attune can\\'t check your phone at all, close Attune and open it again; if that keeps happening, contact support.',
          type: ManualContentType.text,
        ),
      ],
""", """              'On a new phone, a phone restored from a backup, or after a problem with your phone or the app, Dating asks you to check it\\'s you before it shows anything: a short video check, or a person looks at two quick photos. It never asks for your ID again. Dating keeps working on up to three of your phones, and a phone you haven\\'t used for Dating in 180 days needs the check again. If you started setting up Dating on another phone and hadn\\'t passed the check yet, you start again on this one, so your answers stay private. Starting again keeps your "Never introduce me" list, and you can still delete it from Leave Dating and delete my data. People kept on your list from before stay protected but aren\\'t shown, and can\\'t be removed one at a time: to remove them, leave Dating and delete your data. If Attune can\\'t check your phone at all, close Attune and open it again; if that keeps happening, contact support.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_screen',
          title: 'Screenshots and quick exit',
          numberPrefix: '4',
          content:
              // Spec 2 W8a (§6.7; Plan copy): the screen protection and
              // what quick exit keeps.
              'On Android, a screenshot or a screen recording of Dating comes out blank. An iPhone can\\'t block a screenshot, so Attune hides its screen in the app switcher and blurs Dating while the screen is being recorded or shared. Dating\\'s photos are never saved to your phone or your gallery. Quick exit forgets everything Dating was showing; your Dating lock and your Safety PIN stay as they are.',
          type: ManualContentType.text,
        ),
      ],
"""),
], 'T3 manual')
````

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
python3 -I $D/edit_docs_T3.py
flutter test --no-pub test/app/documentations 2>&1 | tr '\r' '\n' | grep -oE '\+[0-9]+( -[0-9]+)?: (All tests passed!|Some tests failed\.)' | tail -1
```

Expected: `…dating_mode_docs.dart: 1 edit(s) (T3 manual)`; `+30: All tests passed!`

- [ ] **Step 4: The mutants (SQL: each adds a Dating push writer that breaks the neutral rule, or hides the writers; Dart: the lock, the check-in push, the update push)**

Create `.superpowers/sdd/2026-11-22-spec2-w8/mut_T3.py` with exactly:

````python
# Spec 2 W8a Task 3 mutants (mutate.py; RAW: each adds a Dating push
# writer that breaks the neutral rule, or hides the writers). Each must
# make dating_v2_device_contracts.sql fail with a CONTRACT VIOLATED line.
def writer(payload):
    return f"""CREATE FUNCTION private.dating_w8_mutant_push(p_user uuid) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata, created_at, updated_at)
  VALUES (p_user, 'immediate', now(), 'pending',
          pg_catalog.jsonb_build_object({payload}), now(), now());
$f$;"""
MUTS = {
    'dating_type': ('RAW', writer("'type', 'dating_match', 'route', 'me', 'title', 'Attune', 'body', 'x'")),
    'not_attune_title': ('RAW', writer("'type', 'me_update', 'route', 'me', 'title', 'New match', 'body', 'x'")),
    'dating_route': ('RAW', writer("'type', 'me_update', 'route', 'dating_chat', 'title', 'Attune', 'body', 'x'")),
    'dating_body': ('RAW', writer("'type', 'me_update', 'route', 'me', 'title', 'Attune', 'body', 'Your dating match'")),
    'untyped_writer': ('RAW', writer("'route', 'me', 'title', 'Attune', 'body', 'x'")),
    'writers_renamed': ('RAW', """ALTER FUNCTION private.dating_queue_me_update(uuid, text, text, timestamptz) RENAME TO w8_mut_a;
ALTER FUNCTION private.dating_queue_me_update(uuid, text, text) RENAME TO w8_mut_b;"""),
}
````

Create `.superpowers/sdd/2026-11-22-spec2-w8/mut_T3_dart.py` with exactly:

````python
# Spec 2 W8a Task 3: Dart mutants (dmut.py, in a private copy).
T = ['test/features/dating/device/dating_lock_entry_test.dart']
U = 'lib/features/dating/lock/dating_unlock.dart'
N = 'lib/core/notifications/config/notification_config.dart'
MUTS = {
    # The redirect and the page's gate both guard; both go.
    'lock_ignored': (U, [('  if (!locked || container.read(datingUnlockedProvider)) return null;\n', '  return null;\n'),
                         ('    if (!lock.hasError && lock.valueOrNull == false) return widget.child;\n',
                          '    return widget.child;\n')], None, T),
    'checkin_push_to_me': (N, "          GoRouter.of(context).go('/dating/checkin');\n",
                           "          GoRouter.of(context).go(homeLocation(tab: AppTab.me));\n", T),
    'me_update_to_chats': (N, """        case 'me_update':
        case 'dating_mutual_match':
          GoRouter.of(context).go(homeLocation(tab: AppTab.me));
""", """        case 'me_update':
        case 'dating_mutual_match':
          GoRouter.of(context).go('/dating/chats');
""", T),
}
````

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
W8_DB=attune_spec3a python3 -I $D/mutate.py supabase/tests/dating_v2_device_contracts.sql supabase/tests/dating_v2_device_contracts.sql $D/mut_T3.py $D/mut | tee $D/mut_T3.txt | grep -c 'CONTRACT VIOLATED'
python3 -I $D/dmut.py $D/mut_T3_dart.py | tee $D/mut_T3_dart.txt | tail -1
```

Expected: `6` (every SQL mutant's line is `CONTRACT VIOLATED: …`); `3/3 killed`.

- [ ] **Step 5: The W8a gate**

Create `.superpowers/sdd/2026-11-22-spec2-w8/gate.sh` with exactly:

````bash
#!/bin/bash
# Spec 2 W8 batch gate. usage (repo root): gate.sh <W8a|W8b> [db]
# db defaults to attune_spec3a (the replay passes its clone). Writes
# $D/gate-<batch>.txt, one line per check. W8b adds the race script on an
# idle scratch database built from <db> (dropped after).
B=$1; DB=${2:-attune_spec3a}
D=.superpowers/sdd/2026-11-22-spec2-w8
O=$D/gate-$B.txt; : > $O
[ "$(psql -X -d "$DB" -Atc 'select current_database()')" = "$DB" ] || { echo "no database $DB" >> $O; exit 1; }
$D/suite.sh "$DB" > $D/sql-$B.txt
echo "SQL $(grep -c '^PASS' $D/sql-$B.txt) PASS, $(grep -c '^FAIL' $D/sql-$B.txt) FAIL" >> $O
echo "SQL-NEW-FAILS: $(comm -13 <(grep FAIL $D/sql-baseline.txt | sort) <(grep FAIL $D/sql-$B.txt | sort) | tr '\n' ' ')" >> $O
echo "DEVICE $(psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -f supabase/tests/dating_v2_device_contracts.sql 2>&1 | grep -oE 'all held|CONTRACT VIOLATED.*' | head -1)" >> $O
(cd supabase/functions && eval "$(grep -m1 -oE 'deno test --allow-read [^"]*' ../../.github/workflows/tests.yml)" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^ok \||^FAILED' | tail -1) | sed 's/^/DENO /' >> $O
(cd supabase/functions && eval "$(grep -m1 -oE 'deno check --lock[^"]*' ../../.github/workflows/tests.yml)" > /dev/null 2>&1; echo "DENO-CHECK exit=$?") >> $O
flutter analyze --no-pub lib test > $D/analyze-$B.txt 2>&1; echo "ANALYZE $(tail -1 $D/analyze-$B.txt)" >> $O
echo "W10SHA $(shasum -c .superpowers/sdd/2026-11-04-spec1-w10-accessibility-docs/w10-1.0.sha | grep -vc ': OK$')" >> $O
echo "W9SHA $(shasum -c .superpowers/sdd/2026-11-04-spec1-w9/flag_off.sha | grep -vc ': OK$')" >> $O
echo "LATCH $(shasum -c .superpowers/sdd/2026-11-07-spec2-w3/latch.sha)" >> $O
echo "LARGETEXT $(python3 scripts/large_text_audit.py --scale 2.0 test/features/dating/device 2>&1 | tail -1)" >> $O
# The audit draws the 1.0 goldens at 2.0; their diagnostics are not results.
rm -rf test/features/dating/device/failures
flutter test --no-pub test/architecture/games_untouched_test.dart 2>&1 | tr '\r' '\n' | grep -oE 'All tests passed!|Some tests failed\.' | tail -1 | sed 's/^/GAMES /' >> $O
echo "FLAGS $(psql -X -d "$DB" -Atc "select count(*) || ' rows, ' || count(*) filter (where enabled) || ' on' from public.feature_flags")" >> $O
if [ "$B" = W8b ]; then
  R=w8race_$$
  dropdb --if-exists $R 2>/dev/null; createdb $R
  pg_dump -s "$DB" | psql -X -q -d $R > /dev/null 2>&1
  pg_dump -a -t public.metric_key_prefixes -t public.feature_flags -t public.country_safety_config -t private.dating_calling_codes \
    -t private.dating_phone_trunk_rules -t private.flag_production_gates -t public.dating_algorithm_configs \
    -t public.dating_safety_configs "$DB" | psql -X -q -d $R > /dev/null 2>&1
  echo "LOAD-BEFORE-RACES $(uptime | sed 's/.*load averages*: //')" >> $O
  bash scripts/concurrency/dating_kill_switch_races.sh $R > $D/race-$B.txt 2>&1
  echo "RACES $(grep -c '^PASS' $D/race-$B.txt) PASS, $(grep -c '^FAIL' $D/race-$B.txt) FAIL" >> $O
  dropdb $R
fi
flutter test --no-pub --reporter compact > $D/flutter-$B.txt 2>&1
echo "FLUTTER $(tr '\r' '\n' < $D/flutter-$B.txt | grep -E '^[0-9:]+ \+[0-9]+' | tail -1 | grep -oE '\+[0-9]+( ~[0-9]+)?( -[0-9]+)?: (All tests passed!|Some tests failed\.)')" >> $O
echo "FLUTTER-FAILS:" >> $O
tr '\r' '\n' < $D/flutter-$B.txt | grep -E '\[E\][[:space:]]*$' | sed -E 's/^[0-9:]+ \+[0-9]+( ~[0-9]+)?( -[0-9]+)?: //; s#.*/test/#test/#; s/ \[E\][[:space:]]*$//' | sort -u | sed 's/^/  /' >> $O
echo DONE >> $O
cat $O
````

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
chmod +x $D/gate.sh
bash $D/gate.sh W8a attune_spec3a
```

Expected (the replay's): 

```text
SQL 163 PASS, 14 FAIL
SQL-NEW-FAILS:
DEVICE all held
DENO ok | 266 passed | 0 failed
DENO-CHECK exit=0
ANALYZE 571 issues found.
W10SHA 0
W9SHA 0
LATCH lib/home/home_screen.dart: OK
LARGETEXT SCALE 2.0: 0 site(s) to fix, 0 listed apart
GAMES All tests passed!
FLAGS 44 rows, 6 on
FLUTTER +8941 -4: Some tests failed.
FLUTTER-FAILS:
  test/accessibility/w10/healing_journal_large_text_test.dart: journal list and entry, 390 wide, text 1.0
  test/accessibility/w10/healing_journal_large_text_test.dart: journal list and entry, 390 wide, text 1.3
  test/accessibility/w10/healing_journal_large_text_test.dart: journal list and entry, 390 wide, text 2.0
  test/features/dating/chat/chat_screen_test.dart: the chat Swap: disabled before 72 hours with its time; open: the sheet and its card, then Swap; each state after
DONE
```

`+8941` is the baseline's `+8906` and Tasks 1–3's 35 tests; the four failures are the baseline's own.

- [ ] **Step 6: Record the tree (do not commit).**

## Batch W8b — the plain icon and the traveller

### Task 4: Migration `dating_v2_traveller` (part 1): the flag, the trip on the context row, the device check's record, gate 7, the home's away state, trip and icon offer, the trip choice, and contract B (§2.1, §2.3, §2.5, §3.1, §3.2 D13, §3.11, §4.3, §4.4, §4.9 W8b, §5.10, §7.1; I-14; R-72, R-73, R-77, R-78)

**Files:**
- Create: `$D/{before_w8b/, mig_T4_head.sql, build_mig_W8b.py, contract_T4.sql, edit_tests_T4.py, mut_T4.py}`, `supabase/migrations/20261122100000_dating_v2_traveller.sql` (built), `supabase/migrations/20261122100010_dating_v2_traveller_grants.sql`
- Modify: `supabase/tests/dating_v2_device_contracts.sql` (B at `-- @@W8B@@`), `supabase/tests/dating_rls_canary.sql`, `supabase/tests/dating_v2_client_reads_contracts.sql` (one pinned home shape), `scripts/local_pg_grants.sql` (one `\i` line)
- Test: `dating_v2_device_contracts.sql` B1–B6

**Interfaces:**
- Consumes: the live `public.dating_eligibility(uuid,text)` and `public.get_dating_home()` (saved in Step 1); `record_dating_session_context(uuid,text,text)` (unchanged: W1b's writer and streak); `private.dating_device_state`, `private.dating_open_signal_case(user, 'location_mismatch', 'P3')`, `private.dating_identity_of`, `private.dating_pair_is_man_woman`, `private.dating_same_gender_on`, `private.dating_field_decrypt`, `public.claim_dating_idempotency`, `private.dating_key_ok`, `public.dating_require_trusted_device`.
- Produces: see "Interfaces this plan produces" (SQL); for Task 5, the marker `-- @@W8B-T5@@` in the head and in the contract, `-- @@W8B-T5-GRANTS@@` in the twin, `-- @@W8B-T5-CANARY@@` in the canary, and `private.dating_trip_hides(viewer, other, kind)` (`kind` `introduction` or `match`).

- [ ] **Step 1: Save the live bodies Tasks 4 and 5 re-create (before anything is applied)**

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8; mkdir -p $D/before_w8b
ls supabase/migrations | sort | tail -1
for sig in "public.dating_eligibility(uuid,text)" "public.get_dating_home()" "public.get_my_dating_today()" "public.get_my_dating_introductions()" "public.act_on_dating_introduction(text,uuid,text)" "public.get_my_dating_matches(boolean)" "public.get_dating_messages(uuid,timestamp with time zone,integer)" "public.get_my_dating_restriction()" "public.submit_dating_appeal(text,uuid,text)"; do
  psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)" > "$D/before_w8b/$sig.sql"
done
ls $D/before_w8b | wc -l | tr -d ' '
```

Expected: `20261121120010_dating_v2_escalations_grants.sql`; `9`.

- [ ] **Step 2: Write contract B and splice it into the device contract**

Create `.superpowers/sdd/2026-11-22-spec2-w8/contract_T4.sql` with exactly:

````sql
-- =====================================================================
-- Setup for B onward (W8b): the keys, the flags (the traveller flag is
-- turned on here only, inside this file's transaction), Ghana and the UK
-- open, and the people. Fixture ids 8a800000-...-0000000000nn, phones
-- +1555981nn: B 01-29, C 30-59.
-- =====================================================================
DO $$
BEGIN
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w8-device-key', true);
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w8-field-key-0123456789abcdef-0123', true);
  PERFORM set_config('app.settings.dating_push_key', 'spec2-w8-push-key', true);
END $$;
SELECT private.seed_dating_exclusion_key_fingerprint() AS seeded \gset
SELECT private.seed_dating_field_key_fingerprint() AS seeded_field \gset
INSERT INTO public.feature_flags (key, enabled)
VALUES ('dating_mode_enabled', true), ('dating_candidate_generation', true), ('dating_same_gender_matching', true),
       ('dating_match_messaging', true), ('dating_profile_photos', true)
ON CONFLICT (key) DO UPDATE SET enabled = true;
SELECT public.publish_country_config('GH', '{"dating_enabled": true, "open_regions": ["AA", "AH"]}') AS gh \gset
SELECT public.publish_country_config('GB', '{"dating_enabled": true}') AS gb \gset
UPDATE public.dating_algorithm_configs SET state = 'retired', retired_at = now() WHERE state = 'active';
UPDATE public.dating_algorithm_configs
   SET state = 'active', activated_at = now(), product_review_ref = 'DEV-product', clinical_review_ref = 'DEV-clinical',
       fairness_review_ref = 'DEV-fairness', safety_review_ref = 'DEV-safety'
 WHERE version = 'introductions_v2';

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('8a800000-0000-0000-0000-' || lpad(p_n, 12, '0'))::uuid;
$$;
-- The phone's install id (the x-attune-device header) and its hash.
CREATE FUNCTION pg_temp.dev(p_n text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT md5('w8-device-' || p_n);
$$;
CREATE FUNCTION pg_temp.hash(p_n text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT encode(extensions.digest(pg_temp.dev(p_n), 'sha256'), 'hex');
$$;
CREATE FUNCTION pg_temp.ready(p_n text, o jsonb DEFAULT '{}') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_u constant uuid := pg_temp.id(p_n);
  d constant jsonb := '{"identity": "woman", "seeking": ["man"], "country": "GH", "region": "AA", "years": 30,
    "days": 40, "phone": null, "state": "active"}'::jsonb || o;
  v_phone constant text := coalesce(d ->> 'phone', '+1555981' || p_n);
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (v_u, ltrim(v_phone, '+'), now(), now() - make_interval(days => (d ->> 'days')::int));
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (v_u, v_phone, 'Trip ' || p_n, 'dating', now() - make_interval(days => (d ->> 'days')::int), now(), '2');
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (v_u, (current_date - make_interval(years => (d ->> 'years')::int) - interval '10 days')::date);
  INSERT INTO public.dating_enrollments (user_id, state, opted_in_at, activated_at)
  VALUES (v_u, d ->> 'state', now(), CASE WHEN d ->> 'state' = 'active' THEN now() END);
  INSERT INTO public.dating_profiles (user_id, display_name, profile_state, moderation_state, verification_state,
    country_code, region_code, intention, timeline_visible, not_married_attested_at, attestation_version,
    children_have, children_want, faith_visible)
  VALUES (v_u, 'Trip ' || p_n, 'active', 'approved', 'verified', d ->> 'country', d ->> 'region',
    'committed', true, now(), '2026-10-v1', false, 'yes', false);
  INSERT INTO public.dating_preferences (user_id, min_age, max_age, region_scope, open_abroad, want_must_match, exclude_parents)
  VALUES (v_u, 25, 40, 'country', '{}', false, false);
  INSERT INTO public.dating_profile_sensitive (user_id, identity_enc, seeking_enc)
  VALUES (v_u, private.dating_field_encrypt(jsonb_build_object('identity', d ->> 'identity', 'pools', jsonb_build_array(d ->> 'identity'))),
          private.dating_field_encrypt(jsonb_build_object('seeking', d -> 'seeking')));
  INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer, moderation_state)
  SELECT v_u, n, CASE n WHEN 1 THEN 'perfect_sunday' ELSE 'ask_me_about' END, 'A traveller fixture answer ' || n, 'approved'
    FROM generate_series(1, 2) AS n;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state, csam_state)
  SELECT v_u, 'w8/' || v_u || '/' || n || '.jpg', n, 'approved', 'clear' FROM generate_series(1, 2) AS n;
  INSERT INTO public.dating_age_verifications (user_id, age_method, age_result, age_vendor, age_decided_at,
    identity_method, identity_result, identity_vendor, identity_decided_at)
  VALUES (v_u, 'id', 'pass', 'contract', now(), 'liveness_compare', 'pass', 'contract', now());
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT v_u, 'w8-consent-' || p, p, 'granted', 'dating-2.0', clock_timestamp()
    FROM unnest(ARRAY['dating_terms', 'dating_opt_in', 'special_category_profile']) AS p;
  INSERT INTO public.dating_trusted_devices (user_id, device_hash, verified_at, last_seen_at)
  VALUES (v_u, pg_temp.hash(p_n), now(), now());
  RETURN v_u;
END $$;
-- A UK person (region TLI).
CREATE FUNCTION pg_temp.uk(p_n text, o jsonb DEFAULT '{}') RETURNS uuid LANGUAGE sql AS $$
  SELECT pg_temp.ready(p_n, '{"country": "GB", "region": "TLI", "phone": null}'::jsonb || o);
$$;
CREATE FUNCTION pg_temp.as_person(p uuid, p_device text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.headers', CASE WHEN p_device IS NULL THEN '' ELSE json_build_object('x-attune-device', p_device)::text END, true);
END $$;
CREATE FUNCTION pg_temp.as_db() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.headers', '', true);
END $$;
-- [p]'s own call from phone [p_n] (null: no install id), as jsonb.
CREATE FUNCTION pg_temp.j(p uuid, p_n text, p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  PERFORM pg_temp.as_person(p, CASE WHEN p_n IS NULL THEN NULL ELSE pg_temp.dev(p_n) END);
  EXECUTE p_sql INTO v;
  PERFORM pg_temp.as_db();
  RETURN v::jsonb;
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.as_db();
  RETURN jsonb_build_object('raised', SQLSTATE || ':' || SQLERRM);
END $$;
-- dating-device-check's call, as the service role: [p] on phone [p_n].
CREATE FUNCTION pg_temp.check(p uuid, p_n text, p_ip text, p_net text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.record_dating_device_check(p, CASE WHEN p_n IS NULL THEN NULL ELSE pg_temp.hash(p_n) END, p_ip, p_net);
  RESET ROLE;
  RETURN v;
END $$;
-- The row's last check moves [p_min] minutes back (the next check records).
CREATE FUNCTION pg_temp.age(p uuid, p_min int) RETURNS void LANGUAGE sql AS $$
  UPDATE public.dating_session_context SET checked_at = checked_at - make_interval(mins => p_min) WHERE user_id = p;
$$;
CREATE FUNCTION pg_temp.ctx(p uuid) RETURNS public.dating_session_context LANGUAGE sql AS $$
  SELECT * FROM public.dating_session_context WHERE user_id = p;
$$;
CREATE FUNCTION pg_temp.flag(p_on boolean) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.feature_flags (key, enabled) VALUES ('dating_traveller_detection', p_on)
  ON CONFLICT (key) DO UPDATE SET enabled = EXCLUDED.enabled;
$$;
CREATE FUNCTION pg_temp.key(p text) RETURNS text LANGUAGE sql AS $$
  SELECT 'w8-' || p || '-' || replace(gen_random_uuid()::text, '-', '');
$$;
CREATE FUNCTION pg_temp.home(p uuid, p_n text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, p_n, 'SELECT public.get_dating_home()');
$$;

-- =====================================================================
-- B1. The flag is off as the migration leaves it, with its production
--     gate; record_dating_device_check is the service role's alone and
--     the trip choice the app's.
-- =====================================================================
DO $$
BEGIN
  IF (SELECT enabled FROM public.feature_flags WHERE key = 'dating_traveller_detection') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_traveller_detection is not off';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM private.flag_production_gates WHERE flag_key = 'dating_traveller_detection') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_traveller_detection has no production gate';
  END IF;
  IF has_function_privilege('authenticated', 'public.record_dating_device_check(uuid,text,text,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.record_dating_device_check(uuid,text,text,text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.set_dating_trip_choice(text,boolean)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.set_dating_trip_choice(text,boolean)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the W8b grants are wrong';
  END IF;
END $$;

-- =====================================================================
-- B2. The device check records only for someone with Dating data, from a
--     phone Dating trusts (or before any is bound), at most once per 15
--     minutes; refusals are fixed codes; no country is stored.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.uk('01');
  v_x constant uuid := pg_temp.id('02');
  v jsonb;
  v_at timestamptz;
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at) VALUES (v_x, '155598102', now());
  INSERT INTO public.users (id, phone, display_name) VALUES (v_x, '+155598102', 'No dating');
  IF pg_temp.check(gen_random_uuid(), '01', 'GB') ->> 'reason' IS DISTINCT FROM 'unavailable'
     OR pg_temp.check(v_a, '01', 'G1') ->> 'reason' IS DISTINCT FROM 'invalid'
     OR pg_temp.check(v_a, '01', 'GB', 'ABC') ->> 'reason' IS DISTINCT FROM 'invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a bad device check is not a fixed refusal';
  END IF;
  v := pg_temp.check(v_a, '99', 'AE');
  IF v IS DISTINCT FROM '{"ok": true, "away": false, "here": null, "trusted": false}'::jsonb OR (pg_temp.ctx(v_a)).user_id IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a phone Dating does not trust recorded a context: %', v;
  END IF;
  v := pg_temp.check(v_x, NULL, 'AE');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR EXISTS (SELECT 1 FROM public.dating_session_context WHERE user_id = v_x) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: someone with no Dating data got a context row: %', v;
  END IF;
  v := pg_temp.check(v_a, '01', 'fr');
  IF (v ->> 'trusted')::boolean IS NOT TRUE OR (pg_temp.ctx(v_a)).away_from_home IS NOT TRUE
     OR (pg_temp.ctx(v_a)).mismatch_streak IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the first check did not record: % %', v, to_jsonb(pg_temp.ctx(v_a));
  END IF;
  v_at := (pg_temp.ctx(v_a)).checked_at;
  PERFORM pg_temp.check(v_a, '01', 'ES');
  IF (pg_temp.ctx(v_a)).checked_at IS DISTINCT FROM v_at OR (pg_temp.ctx(v_a)).mismatch_streak IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a check within 15 minutes recorded again';
  END IF;
  PERFORM pg_temp.age(v_a, 16);
  PERFORM pg_temp.check(v_a, '01', 'ES');
  IF (pg_temp.ctx(v_a)).mismatch_streak IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a check 16 minutes later did not count';
  END IF;
  -- No column can hold a country or an address: every one is a flag, a
  -- number, a time or the person's id.
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'dating_session_context'
                AND data_type IN ('text', 'character', 'character varying', 'inet', 'cidr', 'jsonb', 'json', 'bytea', 'ARRAY')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_session_context has a column that can hold a country or an address';
  END IF;
END $$;

-- =====================================================================
-- B3. Gate 7 (§2.1): with the flag on, a candidate whose latest context
--     says Dating isn't allowed where they are is 'away' (and out of
--     others' days); setup goes ahead; with the flag off nothing changes.
--     The answer names the place only while it restricts, and only with
--     the flag on.
-- =====================================================================
DO $$
DECLARE
  v_g constant uuid := pg_temp.ready('03');
  v jsonb;
BEGIN
  v := pg_temp.check(v_g, '03', 'AE');
  IF v ->> 'away' IS DISTINCT FROM 'false' OR v ->> 'here' IS NOT NULL
     OR public.dating_eligibility(v_g, 'candidate') IS DISTINCT FROM 'eligible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the flag off a trip changed something: % %', v, public.dating_eligibility(v_g, 'candidate');
  END IF;
  PERFORM pg_temp.flag(true);
  PERFORM pg_temp.age(v_g, 16);
  v := pg_temp.check(v_g, '03', 'AE');
  IF v IS DISTINCT FROM '{"ok": true, "away": true, "here": "AE", "trusted": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the check in the UAE answered %', v;
  END IF;
  IF public.dating_eligibility(v_g, 'candidate') IS DISTINCT FROM 'away'
     OR public.dating_eligibility(v_g, 'setup') IS DISTINCT FROM 'eligible'
     OR public.dating_candidate_is_current(v_g) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: gate 7 is wrong: % / %', public.dating_eligibility(v_g, 'candidate'),
      public.dating_eligibility(v_g, 'setup');
  END IF;
  -- Back in Ghana: the gate opens at once.
  PERFORM pg_temp.age(v_g, 16);
  v := pg_temp.check(v_g, '03', 'GH');
  IF public.dating_eligibility(v_g, 'candidate') IS DISTINCT FROM 'eligible' OR v ->> 'here' IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: home again, the gate stayed shut: %', v;
  END IF;
  PERFORM pg_temp.flag(false);
END $$;

-- =====================================================================
-- B4. The home (§3.1, §3.11): away is its own state with the trip; a UK
--     person who meets women visiting Ghana carries a same-gender trip
--     (state active), one who meets men none; the note shows until the
--     person chooses; the plain-icon offer is for Tier 1/2 at D13 only.
--     With the flag off: no trip, no away.
-- =====================================================================
DO $$
DECLARE
  v_g constant uuid := pg_temp.ready('04');
  v_w constant uuid := pg_temp.uk('05', '{"seeking": ["woman"]}');
  v_m constant uuid := pg_temp.uk('06');
  v_s constant uuid := pg_temp.ready('07', '{"state": "profile_draft"}');
  v_u constant uuid := pg_temp.uk('08', '{"state": "profile_draft"}');
  v jsonb;
BEGIN
  PERFORM pg_temp.flag(true);
  PERFORM pg_temp.check(v_g, '04', 'AE');
  v := pg_temp.home(v_g, '04');
  IF v ->> 'state' IS DISTINCT FROM 'away'
     OR v -> 'trip' IS DISTINCT FROM '{"kind": "away", "note": true, "show_here": false}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the away home is %', v;
  END IF;
  PERFORM pg_temp.check(v_w, '05', 'GH');
  PERFORM pg_temp.check(v_m, '06', 'GH');
  v := pg_temp.home(v_w, '05');
  IF v ->> 'state' IS DISTINCT FROM 'active'
     OR v -> 'trip' IS DISTINCT FROM '{"kind": "same_gender", "note": true, "show_here": false}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a same-gender trip home is %', v;
  END IF;
  v := pg_temp.home(v_m, '06');
  IF v ->> 'state' IS DISTINCT FROM 'active' OR v ? 'trip' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a man-woman person in Ghana carries a trip: %', v;
  END IF;
  -- D13: Ghana (Tier 1) is offered the plain icon, the UK (Tier 3) not.
  IF (pg_temp.home(v_s, '07') ->> 'offer_plain_icon') IS DISTINCT FROM 'true'
     OR pg_temp.home(v_u, '08') ? 'offer_plain_icon'
     OR pg_temp.home(v_g, '04') ? 'offer_plain_icon' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the plain-icon offer is wrong: % / %', pg_temp.home(v_s, '07'), pg_temp.home(v_u, '08');
  END IF;
  PERFORM pg_temp.flag(false);
  v := pg_temp.home(v_g, '04');
  IF v ->> 'state' IS DISTINCT FROM 'active' OR v ? 'trip' OR pg_temp.home(v_w, '05') ? 'trip' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the flag off the home shows a trip: %', v;
  END IF;
END $$;

-- =====================================================================
-- B5. The trip choice (§3.11): Show it on this phone anyway and Keep it
--     hidden each mark the note seen; a replay is the same answer;
--     showing needs a trusted phone, keeping it hidden doesn't; nothing to
--     choose is no_trip; a trip ends after 7 days back home (the note may
--     show on the next one; showing ends with it).
-- =====================================================================
DO $$
DECLARE
  v_g constant uuid := pg_temp.ready('09');
  v_k constant text := pg_temp.key('show');
  v jsonb;
BEGIN
  PERFORM pg_temp.flag(true);
  IF pg_temp.j(v_g, '09', format('SELECT public.set_dating_trip_choice(%L, true)', pg_temp.key('none'))) ->> 'reason'
     IS DISTINCT FROM 'no_trip' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a choice with no trip was taken';
  END IF;
  PERFORM pg_temp.check(v_g, '09', 'AE');
  IF pg_temp.j(v_g, '09', 'SELECT public.set_dating_trip_choice(''short'', true)') ->> 'reason' IS DISTINCT FROM 'invalid'
     OR pg_temp.j(v_g, '09', format('SELECT public.set_dating_trip_choice(%L, NULL)', v_k)) ->> 'reason' IS DISTINCT FROM 'invalid'
     OR pg_temp.j(v_g, '98', format('SELECT public.set_dating_trip_choice(%L, true)', pg_temp.key('x'))) ->> 'reason'
        IS DISTINCT FROM 'reverify_device' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a bad trip choice was taken';
  END IF;
  v := pg_temp.j(v_g, '09', format('SELECT public.set_dating_trip_choice(%L, true)', v_k));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.home(v_g, '09') -> 'trip' IS DISTINCT FROM '{"kind": "away", "note": false, "show_here": true}'::jsonb
     OR pg_temp.j(v_g, '09', format('SELECT public.set_dating_trip_choice(%L, true)', v_k)) IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Show it on this phone anyway answered % and left %', v, pg_temp.home(v_g, '09');
  END IF;
  -- Keeping it hidden reduces exposure: from any phone.
  v := pg_temp.j(v_g, '98', format('SELECT public.set_dating_trip_choice(%L, false)', pg_temp.key('hide')));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb OR (pg_temp.ctx(v_g)).show_here IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Keep it hidden answered %', v;
  END IF;
  PERFORM pg_temp.j(v_g, '09', format('SELECT public.set_dating_trip_choice(%L, true)', pg_temp.key('show2')));
  -- Home for 6 days: the same trip. For 8: it ended.
  PERFORM pg_temp.age(v_g, 16);
  PERFORM pg_temp.check(v_g, '09', 'GH');
  UPDATE public.dating_session_context SET home_since = now() - interval '6 days' WHERE user_id = v_g;
  PERFORM pg_temp.age(v_g, 16);
  PERFORM pg_temp.check(v_g, '09', 'GH');
  IF (pg_temp.ctx(v_g)).trip_note_shown_at IS NULL OR (pg_temp.ctx(v_g)).show_here IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 6 days home ended the trip';
  END IF;
  UPDATE public.dating_session_context SET home_since = now() - interval '8 days' WHERE user_id = v_g;
  PERFORM pg_temp.age(v_g, 16);
  PERFORM pg_temp.check(v_g, '09', 'GH');
  IF (pg_temp.ctx(v_g)).trip_note_shown_at IS NOT NULL OR (pg_temp.ctx(v_g)).show_here IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 8 days home did not end the trip: %', to_jsonb(pg_temp.ctx(v_g));
  END IF;
  IF pg_temp.j(v_g, '09', format('SELECT public.set_dating_trip_choice(%L, true)', pg_temp.key('home'))) ->> 'reason'
     IS DISTINCT FROM 'no_trip' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a choice was taken at home';
  END IF;
  -- Abroad again: the next trip's note shows.
  PERFORM pg_temp.age(v_g, 16);
  PERFORM pg_temp.check(v_g, '09', 'AE');
  IF pg_temp.home(v_g, '09') -> 'trip' ->> 'note' IS DISTINCT FROM 'true' OR (pg_temp.ctx(v_g)).home_since IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the next trip has no note';
  END IF;
  PERFORM pg_temp.flag(false);
  IF pg_temp.j(v_g, '09', format('SELECT public.set_dating_trip_choice(%L, true)', pg_temp.key('off'))) ->> 'reason'
     IS DISTINCT FROM 'no_trip' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a trip choice was taken with the flag off';
  END IF;
END $$;

-- =====================================================================
-- B6. The location signal (§5.10): with the flag on, 7 checks in a row
--     away from the Dating country open one low-priority signal case;
--     with the flag off, none.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.uk('10');
  v_b constant uuid := pg_temp.uk('11');
BEGIN
  PERFORM pg_temp.flag(true);
  FOR i IN 1..8 LOOP
    PERFORM pg_temp.check(v_a, '10', 'FR');
    PERFORM pg_temp.age(v_a, 16);
    IF i = 6 AND EXISTS (SELECT 1 FROM public.dating_moderation_cases WHERE target_user_id = v_a) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the signal opened before 7';
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM public.dating_moderation_cases
       WHERE target_user_id = v_a AND kind = 'signal' AND signal_kind = 'location_mismatch' AND priority = 'P3') IS DISTINCT FROM 1::bigint THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 7 checks away did not open one P3 location signal';
  END IF;
  PERFORM pg_temp.flag(false);
  FOR i IN 1..8 LOOP
    PERFORM pg_temp.check(v_b, '11', 'FR');
    PERFORM pg_temp.age(v_b, 16);
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.dating_moderation_cases WHERE target_user_id = v_b) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the location signal opened with the flag off';
  END IF;
END $$;

-- @@W8B-T5@@
````

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
python3 -I $D/splice.py supabase/tests/dating_v2_device_contracts.sql '-- @@W8B@@' $D/contract_T4.sql
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_device_contracts.sql 2>&1 | grep -E 'ERROR' | head -1
```

Expected: `…contract_T4.sql spliced at -- @@W8B@@`; then an error from the missing W8b objects (the flag's row, `record_dating_device_check`), e.g. `ERROR:  CONTRACT VIOLATED: dating_traveller_detection is not off`.

- [ ] **Step 3: The new objects (the migration's head), the builder, the twin**

Create `.superpowers/sdd/2026-11-22-spec2-w8/mig_T4_head.sql` with exactly:

````sql
-- ---------------------------------------------------------------------
-- 1. The flag (off; supabase/sql/dev_enable_spec2_dating_flags.sql turns
--    it on in development) and its production gate (Spec 1's gate
--    trigger). The device check records the context with the flag off
--    too (W5's same-gender and freshness rules read it); the flag decides
--    what a trip changes: gate 7, the trip in the home, the reads' hiding
--    and the location signal.
-- ---------------------------------------------------------------------
INSERT INTO private.flag_production_gates (flag_key, gate) VALUES
  ('dating_traveller_detection', 'Spec 2 W8 gate: the section 7.7 device checks pass on release builds (lock screen, screenshots, the plain icon, a traveller with a VPN set to Ghana and to the UAE on a UK account); the IP database attribution is in the app''s licences and the privacy notice')
ON CONFLICT (flag_key) DO NOTHING;
INSERT INTO public.feature_flags (key, enabled) VALUES ('dating_traveller_detection', false)
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------
-- 2. The trip, on the one overwritten row (§2.3, §2.5): since when the
--    person has been back home (a trip ends after 7 days of it), and the
--    person's own "Show it on this phone anyway". Still no country and no
--    history.
-- ---------------------------------------------------------------------
ALTER TABLE public.dating_session_context
  ADD COLUMN IF NOT EXISTS home_since timestamptz,
  ADD COLUMN IF NOT EXISTS show_here boolean NOT NULL DEFAULT false;

-- ---------------------------------------------------------------------
-- 3. Helpers.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.dating_traveller_on()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(public.dating_flag_enabled('dating_traveller_detection'), false);
$$;

-- Whether [p_user] has any pool or seeking value beyond man-woman (§2.5):
-- a woman or a man in their own pool only, seeking only the other. An
-- answer that can't be read counts as yes (the note shows; nothing opens).
CREATE OR REPLACE FUNCTION private.dating_wants_same_gender(p_user uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_identity jsonb;
  v_seeking jsonb;
  v_me text;
  v_pools text[];
  v_seek text[];
BEGIN
  SELECT private.dating_field_decrypt(s.identity_enc), private.dating_field_decrypt(s.seeking_enc)
    INTO v_identity, v_seeking
    FROM public.dating_profile_sensitive AS s WHERE s.user_id = p_user;
  v_me := v_identity ->> 'identity';
  v_pools := ARRAY(SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(v_identity -> 'pools') = 'array'
                                                         THEN v_identity -> 'pools' END));
  v_seek := ARRAY(SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(v_seeking -> 'seeking') = 'array'
                                                        THEN v_seeking -> 'seeking' END));
  RETURN NOT coalesce(v_me IN ('woman', 'man')
                      AND v_pools = ARRAY[v_me]
                      AND v_seek = ARRAY[CASE v_me WHEN 'woman' THEN 'man' ELSE 'woman' END], false);
EXCEPTION WHEN OTHERS THEN
  RETURN true;
END;
$$;

-- §2.5: whether the trip hides the pair of [p_viewer] and [p_other] from
-- [p_viewer] now. On the viewer's own phone (unless they chose "Show it on
-- this phone anyway"): everything while Dating isn't allowed where they
-- are, and every pair that isn't man-woman while same-gender isn't. From
-- another person's Today ([p_kind] 'introduction'): a pair that isn't
-- man-woman while the other person is somewhere same-gender isn't allowed.
-- With the flag off, nothing. An identity that can't be read is not
-- man-woman (hidden).
CREATE OR REPLACE FUNCTION private.dating_trip_hides(p_viewer uuid, p_other uuid, p_kind text)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_me public.dating_session_context;
  v_them public.dating_session_context;
  v_mw boolean;
BEGIN
  IF p_viewer IS NULL OR NOT private.dating_traveller_on() THEN
    RETURN false;
  END IF;
  SELECT * INTO v_me FROM public.dating_session_context AS c WHERE c.user_id = p_viewer;
  IF v_me.user_id IS NOT NULL AND NOT v_me.show_here AND v_me.dating_allowed_here IS FALSE THEN
    RETURN true;
  END IF;
  -- The other side gone (a deleted account's ended chat): nothing more to judge.
  IF p_other IS NULL THEN
    RETURN false;
  END IF;
  SELECT * INTO v_them FROM public.dating_session_context AS c WHERE c.user_id = p_other;
  IF NOT ((v_me.user_id IS NOT NULL AND NOT v_me.show_here AND v_me.same_gender_allowed_here IS FALSE)
          OR (p_kind = 'introduction' AND v_them.user_id IS NOT NULL AND v_them.same_gender_allowed_here IS FALSE)) THEN
    RETURN false;
  END IF;
  v_mw := private.dating_pair_is_man_woman(private.dating_identity_of(p_viewer), private.dating_identity_of(p_other));
  RETURN NOT coalesce(v_mw, false);
END;
$$;

-- The trip as the person's home shows it (§3.1 away, §3.11): its kind,
-- whether the in-app note is still to show (once per trip, never a push)
-- and the person's own "Show it on this phone anyway". Only with the flag
-- on and only while the place (never home) restricts: Dating not allowed
-- here, or same-gender not allowed here while it would be at home and the
-- person has a value beyond man-woman. Otherwise {}.
CREATE OR REPLACE FUNCTION private.dating_trip_json(p_user uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_c public.dating_session_context;
  v_kind text;
BEGIN
  IF p_user IS NULL OR NOT private.dating_traveller_on() THEN
    RETURN '{}'::jsonb;
  END IF;
  SELECT * INTO v_c FROM public.dating_session_context AS c WHERE c.user_id = p_user;
  IF v_c.user_id IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;
  v_kind := CASE
    WHEN v_c.dating_allowed_here IS FALSE THEN 'away'
    WHEN v_c.same_gender_allowed_here IS FALSE
         AND coalesce(private.dating_same_gender_on((SELECT p.country_code::text FROM public.dating_profiles AS p
                                                      WHERE p.user_id = p_user)), false)
         AND private.dating_wants_same_gender(p_user) THEN 'same_gender' END;
  IF v_kind IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;
  RETURN pg_catalog.jsonb_build_object('trip', pg_catalog.jsonb_build_object(
    'kind', v_kind, 'note', v_c.trip_note_shown_at IS NULL, 'show_here', v_c.show_here));
END;
$$;

-- §3.2 D13, §6.7: the plain-icon offer, when the effective tier is 1 or 2
-- (the latest context's, else the phone's and the Dating country's: a VPN
-- never hides the offer). Only when true, so no other home answer changes.
CREATE OR REPLACE FUNCTION private.dating_icon_offer_json(p_user uuid)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE WHEN coalesce(
           (SELECT c.effective_tier FROM public.dating_session_context AS c WHERE c.user_id = p_user),
           (public.dating_effective_context(
              private.dating_phone_country((SELECT a.phone FROM auth.users AS a WHERE a.id = p_user)),
              (SELECT p.country_code::text FROM public.dating_profiles AS p WHERE p.user_id = p_user),
              NULL, NULL) ->> 'effective_tier')::smallint, 3) <= 2
         THEN '{"offer_plain_icon": true}'::jsonb ELSE '{}'::jsonb END;
$$;

-- ---------------------------------------------------------------------
-- 4. The device check (§2.3, §4.4, §4.7): dating-device-check's one call.
--    The IP is resolved to a country in the edge function and never
--    reaches the database; only the country codes come here, are used in
--    the moment and are never stored. A phone Dating doesn't trust records
--    nothing. Only someone with Dating data gets a row. At most one record
--    per 15 minutes (§2.3), so the away streak counts checks at least 15
--    minutes apart; the location signal opens at 7 in a row (§5.10, flag
--    on). A trip ends after 7 days back home: the note may show again on
--    the next one, and "Show it on this phone anyway" ends with it.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_dating_device_check(
  p_user uuid, p_device_hash text, p_ip_country text, p_network_country text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_state text;
  v_row public.dating_session_context;
  v_on constant boolean := private.dating_traveller_on();
  v_here text;
BEGIN
  IF p_user IS NULL OR NOT EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = p_user) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  IF (p_ip_country IS NOT NULL AND p_ip_country !~ '^[A-Za-z]{2}$')
     OR (p_network_country IS NOT NULL AND p_network_country !~ '^[A-Za-z]{2}$')
     OR (p_device_hash IS NOT NULL AND p_device_hash !~ '^[0-9a-f]{64}$') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  v_state := private.dating_device_state(p_user, p_device_hash);
  IF v_state IS DISTINCT FROM 'trusted' AND v_state IS DISTINCT FROM 'unbound' THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'trusted', false, 'away', false, 'here', NULL);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_enrollments AS e WHERE e.user_id = p_user) THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'trusted', v_state = 'trusted', 'away', false, 'here', NULL);
  END IF;
  -- Two checks at once (two opens): the second waits, then finds the row fresh.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('dating_device_check'), pg_catalog.hashtext(p_user::text));
  SELECT * INTO v_row FROM public.dating_session_context AS c WHERE c.user_id = p_user;
  IF v_row.user_id IS NULL OR v_row.checked_at <= now() - interval '15 minutes' THEN
    PERFORM public.record_dating_session_context(p_user, upper(p_ip_country), upper(p_network_country));
    UPDATE public.dating_session_context AS c
       SET home_since = CASE WHEN c.away_from_home THEN NULL ELSE coalesce(c.home_since, now()) END
     WHERE c.user_id = p_user
    RETURNING * INTO v_row;
    IF NOT v_row.away_from_home AND v_row.home_since <= now() - interval '7 days'
       AND (v_row.trip_note_shown_at IS NOT NULL OR v_row.show_here) THEN
      UPDATE public.dating_session_context AS c SET trip_note_shown_at = NULL, show_here = false
       WHERE c.user_id = p_user RETURNING * INTO v_row;
    END IF;
    IF v_on AND v_row.mismatch_streak = 7 THEN
      PERFORM private.dating_open_signal_case(p_user, 'location_mismatch', 'P3');
    END IF;
  END IF;
  -- The place, for the note's words only, while it restricts more than
  -- home: Dating isn't allowed there, or same-gender isn't, away from home.
  IF v_on AND (v_row.dating_allowed_here IS FALSE
               OR (v_row.same_gender_allowed_here IS FALSE AND v_row.away_from_home)) THEN
    v_here := private.dating_iso_country(upper(coalesce(p_ip_country, p_network_country)));
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'trusted', v_state = 'trusted',
    'away', v_on AND v_row.dating_allowed_here IS FALSE, 'here', v_here);
END;
$$;

-- ---------------------------------------------------------------------
-- 5. The person's choice on a trip (§3.11): "Show it on this phone anyway"
--    (show_here true: only what this person's own reads hide; the server
--    still makes no introduction the context forbids) or "Keep it hidden"
--    (false). Either marks the note seen for the trip. Keeping it hidden
--    reduces exposure, so it needs no trusted phone; showing does.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_dating_trip_choice(p_idempotency_key text, p_show_here boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_show_here IS NULL OR private.dating_key_ok(p_idempotency_key) IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF p_show_here AND public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  IF NOT private.dating_traveller_on() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'no_trip');
  END IF;
  IF NOT public.claim_dating_idempotency('set_dating_trip_choice', p_idempotency_key) THEN
    RETURN pg_catalog.jsonb_build_object('ok', true);
  END IF;
  UPDATE public.dating_session_context AS c
     SET show_here = p_show_here, trip_note_shown_at = coalesce(c.trip_note_shown_at, now())
   WHERE c.user_id = v_user
     AND (c.dating_allowed_here IS FALSE OR (c.same_gender_allowed_here IS FALSE AND c.away_from_home));
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'no_trip');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true);
END;
$$;

-- @@W8B-T5@@
````

Create `.superpowers/sdd/2026-11-22-spec2-w8/build_mig_W8b.py` with exactly:

````python
#!/usr/bin/env python3
"""Spec 2 W8b: builds supabase/migrations/20261122100000_dating_v2_traveller.sql
from mig_T4_head.sql (and Task 5's mig_T5.sql at its marker, when it
exists), the functions below re-created from their LIVE bodies (saved to
before_w8b/ before the migration is first applied) with only the lines
marked "-- Spec 2 W8b" changed (Task 5's edits_T5.py adds its own), and the
self-revoke tail. Every anchor must occur exactly once."""
import pathlib, runpy

D = pathlib.Path('.superpowers/sdd/2026-11-22-spec2-w8')
B = D / 'before_w8b'
T = 'Spec 2 W8b'

EDITS = {
    # §2.1 gate 7: candidates only, with the flag; setup goes ahead.
    'public.dating_eligibility(uuid,text)': [
        ("""  -- 8. Spec 2 W4b (§2.1, R-17): a trusted device, for the caller's own requests.
  RETURN private.dating_device_gate(p_user); -- Spec 2 W4b
""", f"""  -- 7. {T} (§2.1, §2.5): here and now. Candidates only, with the flag:
  -- {T} the latest session context says Dating isn't allowed where the person is.
  IF p_scope = 'candidate' AND private.dating_traveller_on() -- {T}
     AND EXISTS (SELECT 1 FROM public.dating_session_context AS c -- {T}
                  WHERE c.user_id = p_user AND c.dating_allowed_here IS FALSE) THEN -- {T}
    RETURN 'away'; -- {T}
  END IF; -- {T}
  -- 8. Spec 2 W4b (§2.1, R-17): a trusted device, for the caller's own requests.
  RETURN private.dating_device_gate(p_user); -- Spec 2 W4b
"""),
    ],
    # §3.1 away, §3.11: an active person away is 'away' with the trip; an
    # active or cooling-off person on a same-gender trip carries the trip;
    # D13 (setup) carries the plain-icon offer.
    'public.get_dating_home()': [
        ("""    v_cand := public.dating_eligibility(v_user, 'candidate'); -- Spec 2 W3a
""", f"""    v_cand := public.dating_eligibility(v_user, 'candidate'); -- Spec 2 W3a
    IF v_cand IS NOT DISTINCT FROM 'away' THEN -- {T} (§2.1 gate 7, §3.1, §3.11)
      RETURN coalesce(v_has, '{{"has_data": true}}') || jsonb_build_object('state', 'away') -- {T}
             || private.dating_trip_json(v_user); -- {T}
    END IF; -- {T}
"""),
        ("""      RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'cool_off', 'first_drop_at', private.dating_first_drop_at(v_user, v_after)); -- Spec 2 W3a (C-2)
""", f"""      RETURN coalesce(v_has, '{{"has_data": true}}') || jsonb_build_object('state', 'cool_off', 'first_drop_at', private.dating_first_drop_at(v_user, v_after)) -- Spec 2 W3a (C-2); {T}
             || private.dating_trip_json(v_user); -- {T} (§3.11): a same-gender trip
"""),
        ("""    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'active'); -- Spec 2 W3a (C-2)
""", f"""    RETURN coalesce(v_has, '{{"has_data": true}}') || jsonb_build_object('state', 'active') -- Spec 2 W3a (C-2); {T}
           || private.dating_trip_json(v_user); -- {T} (§3.11): a same-gender trip
"""),
        ("""  RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'setup_in_progress', 'next_step', private.dating_next_step(v_user), -- Spec 2 W3a (C-2)
    'first_drop_at', CASE WHEN v_undated THEN NULL -- Spec 2 W3a (D13; fix round 1, M-4)
      ELSE private.dating_first_drop_at(v_user, greatest(now(), -- Spec 2 W3a
      (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours')) END); -- Spec 2 W3a
""", f"""  RETURN coalesce(v_has, '{{"has_data": true}}') || jsonb_build_object('state', 'setup_in_progress', 'next_step', private.dating_next_step(v_user), -- Spec 2 W3a (C-2)
    'first_drop_at', CASE WHEN v_undated THEN NULL -- Spec 2 W3a (D13; fix round 1, M-4)
      ELSE private.dating_first_drop_at(v_user, greatest(now(), -- Spec 2 W3a
      (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours')) END) -- Spec 2 W3a; {T}
    || private.dating_icon_offer_json(v_user); -- {T} (§3.2 D13, A-11): the plain-icon offer in Tier 1/2
"""),
    ],
}

HEADER = """-- Spec 2 W8b (§2.1 gate 7, §2.3, §2.5, §3.1, §3.11, §4.3, §4.4, §4.9 W8b,
-- §5.10, §6.7, §7.1; R-71..R-80): the traveller. The flag
-- dating_traveller_detection (off); the device check's record (the IP's
-- country only, never the IP; a phone Dating doesn't trust records
-- nothing; at most one record per 15 minutes; the location signal at 7);
-- the trip on the one overwritten row; gate 7; the away state, the trip
-- and the plain-icon offer in the home; the person's trip choice.
-- Grants in 20261122100010_dating_v2_traveller_grants.sql. Ends by revoking
-- everything it creates from every API role (the W6 final pattern: a push
-- that stops between this file and its twin fails closed).
"""

TAIL = """
-- ---------------------------------------------------------------------
-- Self-revoke (the W6 final pattern); the twin grants.
-- ---------------------------------------------------------------------
REVOKE ALL ON FUNCTION
  private.dating_traveller_on(), private.dating_wants_same_gender(uuid),
  private.dating_trip_hides(uuid, uuid, text), private.dating_trip_json(uuid),
  private.dating_icon_offer_json(uuid),
  public.record_dating_device_check(uuid, text, text, text),
  public.set_dating_trip_choice(text, boolean)
  FROM PUBLIC, anon, authenticated, service_role;
"""

if (D / 'edits_T5.py').exists():
    t5 = runpy.run_path(str(D / 'edits_T5.py'))
    for sig, pairs in t5['EDITS'].items():
        EDITS.setdefault(sig, []).extend(pairs)
    TAIL += t5['TAIL']


def edited(sig):
    text = (B / f'{sig}.sql').read_text().rstrip('\n')
    for old, new in EDITS[sig]:
        n = text.count(old)
        assert n == 1, f'{sig}: anchor occurs {n} times: {old[:70]!r}'
        text = text.replace(old, new)
    return text + ';\n'


head = (D / 'mig_T4_head.sql').read_text()
if (D / 'mig_T5.sql').exists():
    assert head.count('-- @@W8B-T5@@\n') == 1
    head = head.replace('-- @@W8B-T5@@\n', (D / 'mig_T5.sql').read_text())
body = (HEADER + 'BEGIN;\nSET LOCAL lock_timeout = \'5s\';\n\n' + head
        + '\n-- ---------------------------------------------------------------------\n'
        + '-- Re-created from their live bodies; only the lines marked\n'
        + '-- "-- Spec 2 W8b" change.\n'
        + '-- ---------------------------------------------------------------------\n'
        + '\n'.join(edited(s) for s in EDITS) + TAIL + '\nCOMMIT;\n')
out = pathlib.Path('supabase/migrations/20261122100000_dating_v2_traveller.sql')
out.write_text(body)
print(f'{out}: {len(EDITS)} re-created function(s), {body.count(chr(10))} lines')
````

Create `supabase/migrations/20261122100010_dating_v2_traveller_grants.sql` with exactly:

````sql
-- Spec 2 W8b: grants for 20261122100000_dating_v2_traveller.sql. The device
-- check's record is the service role's alone (dating-device-check's); the
-- trip choice is the app's; the helpers are the database's own.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION private.dating_traveller_on() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_wants_same_gender(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_trip_hides(uuid, uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_trip_json(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_icon_offer_json(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.record_dating_device_check(uuid, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_dating_device_check(uuid, text, text, text) TO service_role;
REVOKE ALL ON FUNCTION public.set_dating_trip_choice(text, boolean) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.set_dating_trip_choice(text, boolean) TO authenticated;
-- @@W8B-T5-GRANTS@@
COMMIT;
````

- [ ] **Step 4: Build, apply twice, check the marked lines**

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
python3 -I $D/build_mig_W8b.py
for i in 1 2; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261122100000_dating_v2_traveller.sql > /dev/null 2>&1; echo "migration exit=$?"
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261122100010_dating_v2_traveller_grants.sql > /dev/null 2>&1; echo "twin exit=$?"
done
python3 -I $D/marked_diff.py $D/before_w8b attune_spec3a 'Spec 2 W8b' | grep -v ' 0 added'; echo "marked_diff exit=${PIPESTATUS[0]}"
```

Expected: `supabase/migrations/20261122100000_dating_v2_traveller.sql: 2 re-created function(s), 550 lines`; four `exit=0`; `public.dating_eligibility(uuid,text): 7 added line(s), 0 removed OK`, `public.get_dating_home(): 10 added line(s), 3 removed OK`, `marked_diff exit=0`.

- [ ] **Step 5: The canary takes W8b's functions; the grants harness its twin**

Create `.superpowers/sdd/2026-11-22-spec2-w8/edit_tests_T4.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W8b Task 4: the canary takes W8b's functions (the device check's
# record the service role's, the trip choice the app's, the helpers the
# database's own), above its Checks line, behind a marker Task 5 uses; W3a's
# client-reads contract reads the D13 plain-icon offer on a Ghana (Tier 1)
# person's setup home (the replay found the pinned shape); the grants
# harness ends with the twin's \i line (grants_line.py).
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-22-spec2-w8/anchor.py')['edit']

edit('supabase/tests/dating_rls_canary.sql', [
    ("""  -- Round 4 (N3-1): the orphaned ID check's record test.
  ('private.dating_case_id_record_live(uuid)', '', '');

-- ---------------------------------------------------------------------
-- Checks (every batch adds its rows above this line).
""", """  -- Round 4 (N3-1): the orphaned ID check's record test.
  ('private.dating_case_id_record_live(uuid)', '', '');
-- Spec 2 W8b Task 4: the traveller. The device check's record is the
-- service role's alone (dating-device-check's); the trip choice is the
-- app's; the helpers are the database's own.
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('record_dating_device_check(uuid,text,text,text)', '', 'service_role'),
  ('set_dating_trip_choice(text,boolean)', 'authenticated', ''),
  ('private.dating_traveller_on()', '', ''),
  ('private.dating_wants_same_gender(uuid)', '', ''),
  ('private.dating_trip_hides(uuid,uuid,text)', '', ''),
  ('private.dating_trip_json(uuid)', '', ''),
  ('private.dating_icon_offer_json(uuid)', '', '');
-- @@W8B-T5-CANARY@@

-- ---------------------------------------------------------------------
-- Checks (every batch adds its rows above this line).
"""),
], 'T4 canary')

edit('supabase/tests/dating_v2_client_reads_contracts.sql', [
    ("""     OR pg_temp.home(v_undated_setup) IS DISTINCT FROM '{"state": "setup_in_progress", "next_step": "looking-for", "first_drop_at": null}'::jsonb THEN
""", """     OR pg_temp.home(v_undated_setup) IS DISTINCT FROM '{"state": "setup_in_progress", "next_step": "looking-for", "first_drop_at": null, "offer_plain_icon": true}'::jsonb THEN -- Spec 2 W8b: Ghana is Tier 1 (D13's offer)
"""),
], 'T4 W3a home shape')
````

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
python3 -I $D/edit_tests_T4.py
python3 -I $D/grants_line.py supabase/migrations/20261121120010_dating_v2_escalations_grants.sql 'Spec 2 W8b: the traveller (twin of 20261122100000)' supabase/migrations/20261122100010_dating_v2_traveller_grants.sql
for f in dating_v2_device_contracts dating_rls_canary country_safety_config_contracts dating_v2_matching_contracts dating_v2_client_reads_contracts dating_v2_home_contracts; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$f.sql > /dev/null 2>&1 && echo "$f exit=0" || echo "$f FAILED"
done
```

Expected: `…dating_rls_canary.sql: 1 edit(s) (T4 canary)`, `…dating_v2_client_reads_contracts.sql: 1 edit(s) (T4 W3a home shape)`; `local_pg_grants.sql: one \i block added`; six lines ending `exit=0` (the canary's S-4 scan holds: the service role's record reaches no decrypting function; W3a's pinned setup home of a Ghana person now carries D13's `offer_plain_icon`, found by the replay's full suite).

- [ ] **Step 6: The mutants**

Create `.superpowers/sdd/2026-11-22-spec2-w8/mut_T4.py` with exactly:

````python
# Spec 2 W8b Task 4 mutants (mutate.py on 20261122100000_dating_v2_traveller.sql,
# the twin applied after each). Each must make dating_v2_device_contracts.sql
# fail with a CONTRACT VIOLATED line.
MUTS = {
    'gate7_ignores_flag': ("  IF p_scope = 'candidate' AND private.dating_traveller_on() -- Spec 2 W8b\n",
                           "  IF p_scope = 'candidate' -- Spec 2 W8b\n"),
    'gate7_setup_too': ("  IF p_scope = 'candidate' AND private.dating_traveller_on() -- Spec 2 W8b\n",
                        "  IF private.dating_traveller_on() -- Spec 2 W8b\n"),
    'no_throttle': ("  IF v_row.user_id IS NULL OR v_row.checked_at <= now() - interval '15 minutes' THEN\n",
                    "  IF true THEN\n"),
    'untrusted_records': ("  IF v_state IS DISTINCT FROM 'trusted' AND v_state IS DISTINCT FROM 'unbound' THEN\n",
                          "  IF false THEN\n"),
    'anyone_records': ("  IF NOT EXISTS (SELECT 1 FROM public.dating_enrollments AS e WHERE e.user_id = p_user) THEN\n",
                       "  IF false THEN\n"),
    'trip_never_ends': ("    IF NOT v_row.away_from_home AND v_row.home_since <= now() - interval '7 days'\n",
                        "    IF NOT v_row.away_from_home AND v_row.home_since <= now() - interval '70 days'\n"),
    'trip_ends_early': ("    IF NOT v_row.away_from_home AND v_row.home_since <= now() - interval '7 days'\n",
                        "    IF NOT v_row.away_from_home AND v_row.home_since <= now() - interval '5 days'\n"),
    'signal_without_flag': ("    IF v_on AND v_row.mismatch_streak = 7 THEN\n", "    IF v_row.mismatch_streak = 7 THEN\n"),
    'signal_at_6': ("    IF v_on AND v_row.mismatch_streak = 7 THEN\n", "    IF v_on AND v_row.mismatch_streak >= 6 THEN\n"),
    'here_without_flag': ("  IF v_on AND (v_row.dating_allowed_here IS FALSE\n", "  IF (v_row.dating_allowed_here IS FALSE\n"),
    'away_not_a_state': ("    IF v_cand IS NOT DISTINCT FROM 'away' THEN -- Spec 2 W8b (§2.1 gate 7, §3.1, §3.11)\n",
                         "    IF false THEN -- Spec 2 W8b (§2.1 gate 7, §3.1, §3.11)\n"),
    'note_always': ("    'kind', v_kind, 'note', v_c.trip_note_shown_at IS NULL, 'show_here', v_c.show_here));\n",
                    "    'kind', v_kind, 'note', true, 'show_here', v_c.show_here));\n"),
    'trip_for_man_woman': ("         AND private.dating_wants_same_gender(p_user) THEN 'same_gender' END;\n",
                           "         THEN 'same_gender' END;\n"),
    'wants_inverted': ("  RETURN NOT coalesce(v_me IN ('woman', 'man')\n", "  RETURN coalesce(v_me IN ('woman', 'man')\n"),
    'trip_without_flag': ("""  IF p_user IS NULL OR NOT private.dating_traveller_on() THEN
    RETURN '{}'::jsonb;
  END IF;
  SELECT * INTO v_c FROM public.dating_session_context AS c WHERE c.user_id = p_user;""",
                          """  IF p_user IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;
  SELECT * INTO v_c FROM public.dating_session_context AS c WHERE c.user_id = p_user;"""),
    'icon_offer_everyone': ("              NULL, NULL) ->> 'effective_tier')::smallint, 3) <= 2\n",
                            "              NULL, NULL) ->> 'effective_tier')::smallint, 3) <= 3\n"),
    'show_without_trusted_phone': ("  IF p_show_here AND public.dating_require_trusted_device() IS NOT TRUE THEN\n", "  IF false THEN\n"),
    'hide_needs_trusted_phone': ("  IF p_show_here AND public.dating_require_trusted_device() IS NOT TRUE THEN\n",
                                 "  IF public.dating_require_trusted_device() IS NOT TRUE THEN\n"),
    'choice_at_home': ("     AND (c.dating_allowed_here IS FALSE OR (c.same_gender_allowed_here IS FALSE AND c.away_from_home));\n",
                       "     AND (c.dating_allowed_here IS FALSE OR c.same_gender_allowed_here IS FALSE);\n"),
    'choice_without_flag': ("""  IF NOT private.dating_traveller_on() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'no_trip');
  END IF;
  IF NOT public.claim_dating_idempotency""", """  IF NOT public.claim_dating_idempotency"""),
}
````

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
W8_DB=attune_spec3a python3 -I $D/mutate.py supabase/migrations/20261122100000_dating_v2_traveller.sql supabase/tests/dating_v2_device_contracts.sql $D/mut_T4.py $D/mut supabase/migrations/20261122100010_dating_v2_traveller_grants.sql | tee $D/mut_T4.txt | grep -c 'CONTRACT VIOLATED'
```

Expected: `20` (every line `CONTRACT VIOLATED: …`).

- [ ] **Step 7: Record the tree (do not commit).**

### Task 5: Migration `dating_v2_traveller` (part 2): what a trip hides in the reads; the W7 carries (`review`, the busy clash); contract C (§2.5, §5.2 filters 1 and 4, §7.2 S4; W7 carries M-6, n4-2; R-79, R-81)

**Files:**
- Create: `$D/{mig_T5.sql, edits_T5.py, twin_T5.sql, contract_T5.sql, edit_tests_T5.py, mut_T5.py}`
- Modify: the migration (rebuilt), the twin (spliced), `dating_v2_device_contracts.sql` (C), `dating_rls_canary.sql`, `dating_v2_moderation_contracts.sql` (four pinned shapes gain `review: testing`)
- Test: contract C1–C3

**Interfaces:**
- Consumes: Task 4's `private.dating_trip_hides`, `pg_temp.check`, `pg_temp.flag`, `pg_temp.uk`, `pg_temp.ready`; the saved bodies of the seven reads.
- Produces: `private.dating_review_mode()`; the reads' hiding; `get_my_dating_restriction()` and `submit_dating_appeal`'s ok answers with `review`.

- [ ] **Step 1: Write contract C and splice it**

Create `.superpowers/sdd/2026-11-22-spec2-w8/contract_T5.sql` with exactly:

````sql
-- C helpers: an introduction visible to both now, an active match, a
-- message, and the people in a read.
CREATE FUNCTION pg_temp.intro(p_a uuid, p_b uuid) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version,
                                           visible_from_low, visible_from_high, expires_at)
  VALUES (public.dating_pair_key(p_a, p_b), least(p_a, p_b), greatest(p_a, p_b), 'presented', 'introductions_v2',
          now() - interval '1 hour', now() - interval '1 hour', now() + interval '6 days')
  RETURNING id;
$$;
CREATE FUNCTION pg_temp.match(p_a uuid, p_b uuid) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, matched_at, pair_key)
  VALUES (least(p_a, p_b), greatest(p_a, p_b), 'active', now() - interval '2 days', public.dating_pair_key(p_a, p_b))
  RETURNING id;
$$;
-- The introduction ids on [p]'s Today, sorted.
CREATE FUNCTION pg_temp.today(p uuid, p_n text) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce((SELECT string_agg(c ->> 'id', ',' ORDER BY c ->> 'id')
                     FROM jsonb_array_elements(v -> 'cards') AS c), '')
         || CASE WHEN v ->> 'ok' = 'true' THEN '' ELSE '!' || (v ->> 'reason') END
    FROM (SELECT pg_temp.j(p, p_n, 'SELECT public.get_my_dating_today()') AS v) AS x;
$$;
-- The match ids in [p]'s conversations, then the ended ones as e:<id>, sorted.
CREATE FUNCTION pg_temp.chats(p uuid, p_n text) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce((SELECT string_agg(c ->> 'match_id', ',' ORDER BY c ->> 'match_id')
                     FROM jsonb_array_elements(v -> 'conversations') AS c), '')
         || coalesce((SELECT string_agg(',e:' || (c ->> 'match_id'), '' ORDER BY c ->> 'match_id')
                        FROM jsonb_array_elements(v -> 'ended') AS c), '')
    FROM (SELECT pg_temp.j(p, p_n, 'SELECT public.get_my_dating_matches(true)') AS v) AS x;
$$;

-- =====================================================================
-- C1. A same-gender trip (§2.5): a UK woman who meets women, in Accra.
--     On her phone her same-gender introduction and conversation are
--     hidden (Today, the introductions read, acting, the list, the
--     messages, the match moment); on the other woman's Today she is
--     hidden too; the other woman's conversation with her stays; a
--     man-woman traveller keeps every introduction. "Show it on this
--     phone anyway" shows hers on her phone only. With the flag off
--     nothing is hidden.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.uk('30', '{"seeking": ["woman"]}');
  v_b constant uuid := pg_temp.uk('31', '{"seeking": ["woman"]}');
  v_c constant uuid := pg_temp.uk('32', '{"seeking": ["woman"]}');
  v_e constant uuid := pg_temp.uk('33', '{"identity": "man", "seeking": ["woman"]}');
  v_f constant uuid := pg_temp.uk('34');
  v_ab uuid;
  v_ac uuid;
  v_ef uuid;
  v jsonb;
BEGIN
  v_ab := pg_temp.intro(v_a, v_b);
  v_ef := pg_temp.intro(v_e, v_f);
  v_ac := pg_temp.match(v_a, v_c);
  -- The match moment, still unseen on both sides.
  IF pg_temp.today(v_a, '30') IS DISTINCT FROM v_ab::text OR pg_temp.chats(v_a, '30') IS DISTINCT FROM v_ac::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the fixture is not visible before the trip: % / %', pg_temp.today(v_a, '30'), pg_temp.chats(v_a, '30');
  END IF;
  PERFORM pg_temp.flag(true);
  PERFORM pg_temp.check(v_a, '30', 'GH');
  PERFORM pg_temp.check(v_e, '33', 'GH');
  v := pg_temp.j(v_a, '30', 'SELECT public.get_my_dating_today()');
  IF pg_temp.today(v_a, '30') IS DISTINCT FROM '' OR jsonb_array_length(v -> 'moments') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: her same-gender introduction or moment shows on her phone in Accra: %', v;
  END IF;
  IF jsonb_array_length(pg_temp.j(v_a, '30', 'SELECT public.get_my_dating_introductions()') -> 'cards') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the introductions read shows it';
  END IF;
  IF pg_temp.j(v_a, '30', format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', pg_temp.key('act'), v_ab)) ->> 'reason'
     IS DISTINCT FROM 'introduction_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hidden introduction could be acted on';
  END IF;
  IF pg_temp.chats(v_a, '30') IS DISTINCT FROM ''
     OR pg_temp.j(v_a, '30', format('SELECT public.get_dating_messages(%L)', v_ac)) ->> 'reason' IS DISTINCT FROM 'match_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: her same-gender conversation shows on her phone in Accra';
  END IF;
  IF pg_temp.today(v_b, '31') IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: she is on the other woman''s Today while in Accra';
  END IF;
  IF pg_temp.chats(v_c, '32') IS DISTINCT FROM v_ac::text
     OR pg_temp.j(v_c, '32', format('SELECT public.get_dating_messages(%L)', v_ac)) ->> 'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the other woman lost their conversation';
  END IF;
  IF pg_temp.today(v_e, '33') IS DISTINCT FROM v_ef::text OR pg_temp.today(v_f, '34') IS DISTINCT FROM v_ef::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a man-woman introduction was hidden on a trip';
  END IF;
  -- Show it on this phone anyway: on hers only.
  PERFORM pg_temp.j(v_a, '30', format('SELECT public.set_dating_trip_choice(%L, true)', pg_temp.key('c1')));
  IF pg_temp.today(v_a, '30') IS DISTINCT FROM v_ab::text OR pg_temp.chats(v_a, '30') IS DISTINCT FROM v_ac::text
     OR pg_temp.today(v_b, '31') IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Show it on this phone anyway is wrong: % / % / %',
      pg_temp.today(v_a, '30'), pg_temp.chats(v_a, '30'), pg_temp.today(v_b, '31');
  END IF;
  PERFORM pg_temp.j(v_a, '30', format('SELECT public.set_dating_trip_choice(%L, false)', pg_temp.key('c1b')));
  PERFORM pg_temp.flag(false);
  IF pg_temp.today(v_a, '30') IS DISTINCT FROM v_ab::text OR pg_temp.today(v_b, '31') IS DISTINCT FROM v_ab::text
     OR pg_temp.chats(v_a, '30') IS DISTINCT FROM v_ac::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the flag off a trip still hides something';
  END IF;
END $$;

-- =====================================================================
-- C2. Away where Dating isn't allowed (§2.5): a Ghana person in the UAE.
--     Their conversations, ended ones too, are hidden on their phone
--     unless they choose to show them; the other person keeps the
--     conversation; their Today is not theirs to read (gate 7) and they
--     are on nobody's.
-- =====================================================================
DO $$
DECLARE
  v_g constant uuid := pg_temp.ready('35');
  v_h constant uuid := pg_temp.ready('36', '{"identity": "man", "seeking": ["woman"]}');
  v_k constant uuid := pg_temp.ready('37', '{"identity": "man", "seeking": ["woman"]}');
  v_x constant uuid := pg_temp.ready('41', '{"identity": "man", "seeking": ["woman"]}');
  v_gh uuid;
  v_gk uuid;
  v_gx uuid;
BEGIN
  v_gh := pg_temp.match(v_g, v_h);
  v_gk := pg_temp.intro(v_g, v_k);
  -- An ended conversation, still listed for its 30 days.
  v_gx := pg_temp.match(v_g, v_x);
  UPDATE public.dating_matches SET state = 'closed', closed_reason = 'unmatched', closed_at = now() - interval '2 days',
         evidence_until = now() + interval '28 days' WHERE id = v_gx;
  IF pg_temp.chats(v_g, '35') IS DISTINCT FROM v_gh::text || ',e:' || v_gx THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the C2 fixture is not listed: %', pg_temp.chats(v_g, '35');
  END IF;
  PERFORM pg_temp.flag(true);
  PERFORM pg_temp.check(v_g, '35', 'AE');
  IF pg_temp.chats(v_g, '35') IS DISTINCT FROM ''
     OR pg_temp.j(v_g, '35', format('SELECT public.get_dating_messages(%L)', v_gh)) ->> 'reason' IS DISTINCT FROM 'match_unavailable'
     OR pg_temp.today(v_g, '35') IS DISTINCT FROM '!not_eligible'
     OR pg_temp.today(v_k, '37') IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: away, Dating shows: % / % / %', pg_temp.chats(v_g, '35'), pg_temp.today(v_g, '35'),
      pg_temp.today(v_k, '37');
  END IF;
  IF pg_temp.chats(v_h, '36') IS DISTINCT FROM v_gh::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the other person lost the conversation with someone away';
  END IF;
  PERFORM pg_temp.j(v_g, '35', format('SELECT public.set_dating_trip_choice(%L, true)', pg_temp.key('c2')));
  IF pg_temp.chats(v_g, '35') IS DISTINCT FROM v_gh::text || ',e:' || v_gx OR pg_temp.today(v_k, '37') IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: shown anyway, the conversations did not come back (or the card did)';
  END IF;
  PERFORM pg_temp.flag(false);
END $$;

-- =====================================================================
-- C3. (W7 carries) The restriction read and the appeal's answer say
--     whether a person reviews now: staffed only in production with an
--     active safety owner and moderator (M-6); a reference-code clash in
--     the carry-over is busy, counted, never an error (n4-2).
-- =====================================================================
DO $$
DECLARE
  v_p constant uuid := pg_temp.ready('38');
  v_o constant uuid := pg_temp.ready('39');
  v_m constant uuid := pg_temp.ready('40');
  v_busy bigint;
  v jsonb;
  v_key text;
BEGIN
  IF pg_temp.j(v_p, '38', 'SELECT public.get_my_dating_restriction()') ->> 'review' IS DISTINCT FROM 'testing' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the restriction read has no testing review';
  END IF;
  INSERT INTO public.dating_moderators (user_id, role) VALUES (v_o, 'safety_owner'), (v_m, 'moderator');
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  IF private.dating_review_mode() IS DISTINCT FROM 'staffed'
     OR pg_temp.j(v_p, '38', 'SELECT public.get_my_dating_restriction()') ->> 'review' IS DISTINCT FROM 'staffed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production with a safety owner and a moderator is not staffed';
  END IF;
  UPDATE public.dating_moderators SET active = false WHERE user_id = v_m;
  IF private.dating_review_mode() IS DISTINCT FROM 'testing' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no active moderator still reads staffed';
  END IF;
  PERFORM set_config('app.settings.attune_environment', '', true);
  -- n4-2: the carry-over raising unique_violation answers busy.
  SELECT coalesce(sum(count), 0) INTO v_busy FROM public.metric_counters WHERE key = 'dating.restriction.busy';
  CREATE FUNCTION private.dating_carry_over_w8_clash() RETURNS trigger LANGUAGE plpgsql AS $t$
  BEGIN
    RAISE unique_violation USING MESSAGE = 'w8 clash';
  END $t$;
  CREATE TRIGGER w8_clash BEFORE INSERT ON public.dating_account_restrictions
    FOR EACH ROW EXECUTE FUNCTION private.dating_carry_over_w8_clash();
  INSERT INTO public.enforcement_records (scope, phone_hmac, restriction_type, category, effect_until, purge_after)
  VALUES ('dating', public.dating_phone_hmac_for_user(v_p), 'suspended', 'harassment', now() + interval '10 days',
          now() + interval '2 years');
  -- The read is its own statement (an IF a OR b has no evaluation order).
  v := pg_temp.j(v_p, '38', 'SELECT public.get_my_dating_restriction()');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "busy"}'::jsonb
     OR (SELECT coalesce(sum(count), 0) FROM public.metric_counters WHERE key = 'dating.restriction.busy') <> v_busy + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reference-code clash raised or went uncounted: %', v;
  END IF;
  DROP TRIGGER w8_clash ON public.dating_account_restrictions;
  DROP FUNCTION private.dating_carry_over_w8_clash();
  -- With the clash gone the record carries: the restriction and its one
  -- appeal say testing too, the replay as the first.
  v := pg_temp.j(v_p, '38', 'SELECT public.get_my_dating_restriction()');
  IF v ->> 'review' IS DISTINCT FROM 'testing' OR v #>> '{restriction,type}' IS DISTINCT FROM 'suspended' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the carried restriction read is %', v;
  END IF;
  v_key := pg_temp.key('ap');
  v := pg_temp.j(v_p, '38', format('SELECT public.submit_dating_appeal(%L, %L, NULL)', v_key, v #>> '{restriction,id}'));
  IF v IS DISTINCT FROM '{"ok": true, "review": "testing"}'::jsonb
     OR pg_temp.j(v_p, '38', format('SELECT public.submit_dating_appeal(%L, %L, NULL)', v_key,
                                    (SELECT id FROM public.dating_account_restrictions WHERE user_id = v_p)))
        IS DISTINCT FROM '{"ok": true, "review": "testing"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the appeal answered % (or its replay differs)', v;
  END IF;
END $$;

-- @@W8-END@@
````

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
python3 -I $D/splice.py supabase/tests/dating_v2_device_contracts.sql '-- @@W8B-T5@@' $D/contract_T5.sql
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_device_contracts.sql 2>&1 | grep -E 'ERROR' | head -1
```

Expected: `…contract_T5.sql spliced at -- @@W8B-T5@@`; `ERROR:  CONTRACT VIOLATED: her same-gender introduction or moment shows on her phone in Accra: …`

- [ ] **Step 2: The review helper, the reads' edits, the twin's line**

Create `.superpowers/sdd/2026-11-22-spec2-w8/mig_T5.sql` with exactly:

````sql
-- ---------------------------------------------------------------------
-- 6. (W7 carry M-6) Whether a person reads reports, restrictions and
--    appeals now: 'staffed' only in production with an active safety
--    owner and an active moderator (the report's own rule, W7 final I-9);
--    otherwise 'testing', and the app drops every review-time sentence.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.dating_review_mode()
RETURNS text
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE WHEN private.attune_environment() = 'production'
               AND EXISTS (SELECT 1 FROM public.dating_moderators AS m WHERE m.active AND m.role = 'safety_owner')
               AND EXISTS (SELECT 1 FROM public.dating_moderators AS m WHERE m.active AND m.role = 'moderator')
              THEN 'staffed' ELSE 'testing' END;
$$;

````

Create `.superpowers/sdd/2026-11-22-spec2-w8/edits_T5.py` with exactly:

````python
# Spec 2 W8b Task 5: the reads a trip hides (§2.5), and two W7 carries
# (M-6: the restriction read and the appeal's answer say whether a person
# reviews now; n4-2: a reference-code clash in the carry-over is busy).
# build_mig_W8b.py adds these edits to its own and TAIL to its tail.
T = 'Spec 2 W8b'
OTHER_I = "CASE WHEN v_i.user_low_id = v_user THEN v_i.user_high_id ELSE v_i.user_low_id END"
EDITS = {
    'public.get_my_dating_today()': [
        ("""    CONTINUE WHEN v_card IS NULL;
""", f"""    CONTINUE WHEN v_card IS NULL;
    CONTINUE WHEN private.dating_trip_hides(v_user, {OTHER_I}, 'introduction'); -- {T} (§2.5)
"""),
        ("""     AND CASE WHEN m.user_low_id = v_user THEN m.low_moment_seen_at ELSE m.high_moment_seen_at END IS NULL;
""", f"""     AND CASE WHEN m.user_low_id = v_user THEN m.low_moment_seen_at ELSE m.high_moment_seen_at END IS NULL -- {T}
     AND NOT private.dating_trip_hides(v_user, p.user_id, 'match'); -- {T} (§2.5)
"""),
    ],
    'public.get_my_dating_introductions()': [
        ("""    IF v_card IS NOT NULL THEN
""", f"""    IF v_card IS NOT NULL AND NOT private.dating_trip_hides(v_user, {OTHER_I}, 'introduction') THEN -- {T} (§2.5)
"""),
    ],
    'public.act_on_dating_introduction(text,uuid,text)': [
        ("""      IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM private.dating_visible_introductions(v_user) AS x WHERE x.id = v_i.id) THEN
""", f"""      IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM private.dating_visible_introductions(v_user) AS x WHERE x.id = v_i.id) -- {T}
         OR private.dating_trip_hides(v_user, {OTHER_I}, 'introduction') THEN -- {T} (§2.5): hidden on a trip
"""),
    ],
    'public.get_my_dating_matches(boolean)': [
        ("""             AND NOT private.dating_pair_blocked(m.user_low_id, m.user_high_id)) AS c; -- fix round 1 (M-5)
""", f"""             AND NOT private.dating_pair_blocked(m.user_low_id, m.user_high_id) -- fix round 1 (M-5); {T}
             AND NOT private.dating_trip_hides(v_user, s.other, 'match')) AS c; -- {T} (§2.5): hidden on this phone on a trip
"""),
        ("""     WHERE v_user IN (m.user_low_id, m.user_high_id)
       AND (((m.state <> 'active'""", f"""     WHERE v_user IN (m.user_low_id, m.user_high_id)
       AND NOT private.dating_trip_hides(v_user, CASE WHEN m.user_low_id = v_user THEN m.user_high_id ELSE m.user_low_id END, 'match') -- {T}
       AND (((m.state <> 'active'"""),
    ],
    'public.get_dating_messages(uuid,timestamp with time zone,integer)': [
        ("""  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable');
  END IF;
  v_side := """, f"""  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable');
  END IF;
  IF private.dating_trip_hides(v_user, CASE WHEN v_m.user_low_id = v_user THEN v_m.user_high_id ELSE v_m.user_low_id END, 'match') THEN -- {T} (§2.5)
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable'); -- {T}: hidden on this phone on a trip
  END IF; -- {T}
  v_side := """),
    ],
    'public.get_my_dating_restriction()': [
        ("""  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
""", f"""  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure -- {T}
            OR unique_violation THEN -- {T} (W7 carry n4-2): a reference-code clash is busy, never an error
"""),
        ("""    RETURN pg_catalog.jsonb_build_object('ok', true, 'restriction', NULL,
                                         'appeal_accepted', private.dating_appeal_accepted(v_user));
""", f"""    RETURN pg_catalog.jsonb_build_object('ok', true, 'restriction', NULL,
                                         'appeal_accepted', private.dating_appeal_accepted(v_user), -- {T}
                                         'review', private.dating_review_mode()); -- {T} (W7 carry M-6)
"""),
        ("""  RETURN pg_catalog.jsonb_build_object('ok', true, 'appeal_accepted', private.dating_appeal_accepted(v_user),
""", f"""  RETURN pg_catalog.jsonb_build_object('ok', true, 'appeal_accepted', private.dating_appeal_accepted(v_user),
    'review', private.dating_review_mode(), -- {T} (W7 carry M-6)
"""),
    ],
    'public.submit_dating_appeal(text,uuid,text)': [
        ("""                  WHERE k.user_id = v_user AND k.operation = 'submit_dating_appeal' AND k.idempotency_key = p_idempotency_key) THEN
        RETURN pg_catalog.jsonb_build_object('ok', true);
""", f"""                  WHERE k.user_id = v_user AND k.operation = 'submit_dating_appeal' AND k.idempotency_key = p_idempotency_key) THEN
        RETURN pg_catalog.jsonb_build_object('ok', true, 'review', private.dating_review_mode()); -- {T} (W7 carry M-6)
"""),
        ("""      PERFORM private.bump_metric_internal('dating.appeal.submitted');
      RETURN pg_catalog.jsonb_build_object('ok', true);
""", f"""      PERFORM private.bump_metric_internal('dating.appeal.submitted');
      RETURN pg_catalog.jsonb_build_object('ok', true, 'review', private.dating_review_mode()); -- {T} (W7 carry M-6)
"""),
    ],
}
TAIL = """REVOKE ALL ON FUNCTION private.dating_review_mode() FROM PUBLIC, anon, authenticated, service_role;
"""
````

Create `.superpowers/sdd/2026-11-22-spec2-w8/twin_T5.sql` with exactly:

````sql
REVOKE ALL ON FUNCTION private.dating_review_mode() FROM PUBLIC, anon, authenticated, service_role;
````

- [ ] **Step 3: Rebuild, apply twice, marked lines, the canary and W7's pinned shapes**

Create `.superpowers/sdd/2026-11-22-spec2-w8/edit_tests_T5.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W8b Task 5: the canary takes the review helper (the database's
# own); W7's moderation contract reads the restriction and the appeal's
# answer with their new review field (W7 carry M-6: 'testing' there, no
# moderator rows in production mode). Exact edits; nothing loosened.
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-22-spec2-w8/anchor.py')['edit']

edit('supabase/tests/dating_rls_canary.sql', [
    ("""-- @@W8B-T5-CANARY@@
""", """-- Spec 2 W8b Task 5 (W7 carry M-6): whether a person reviews now.
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('private.dating_review_mode()', '', '');
"""),
], 'T5 canary')

S = 'supabase/tests/dating_v2_moderation_contracts.sql'
edit(S, [
    ("""  IF pg_temp.j(v_u, '64', 'SELECT public.get_my_dating_restriction()') IS DISTINCT FROM
       '{"ok": true, "restriction": null, "appeal_accepted": false}'::jsonb
""", """  IF pg_temp.j(v_u, '64', 'SELECT public.get_my_dating_restriction()') IS DISTINCT FROM
       '{"ok": true, "review": "testing", "restriction": null, "appeal_accepted": false}'::jsonb -- Spec 2 W8b (M-6)
"""),
    ("""  IF pg_temp.j(v_n, '65', 'SELECT public.get_my_dating_restriction()') IS DISTINCT FROM
       '{"ok": true, "restriction": null, "appeal_accepted": false}'::jsonb THEN
""", """  IF pg_temp.j(v_n, '65', 'SELECT public.get_my_dating_restriction()') IS DISTINCT FROM
       '{"ok": true, "review": "testing", "restriction": null, "appeal_accepted": false}'::jsonb THEN -- Spec 2 W8b (M-6)
"""),
    ("""  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT text || '/' || state FROM public.dating_appeals WHERE id = v_a) IS DISTINCT FROM 'I didn''t do this./open'
""", """  IF v IS DISTINCT FROM '{"ok": true, "review": "testing"}'::jsonb -- Spec 2 W8b (M-6)
     OR (SELECT text || '/' || state FROM public.dating_appeals WHERE id = v_a) IS DISTINCT FROM 'I didn''t do this./open'
"""),
    ("""  IF v IS DISTINCT FROM '{"ok": true, "restriction": null, "appeal_accepted": true}'::jsonb
""", """  IF v IS DISTINCT FROM '{"ok": true, "review": "testing", "restriction": null, "appeal_accepted": true}'::jsonb -- Spec 2 W8b (M-6)
"""),
], 'T5 W7 contract shapes')
````

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
python3 -I $D/splice.py supabase/migrations/20261122100010_dating_v2_traveller_grants.sql '-- @@W8B-T5-GRANTS@@' $D/twin_T5.sql
python3 -I $D/build_mig_W8b.py
for i in 1 2; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261122100000_dating_v2_traveller.sql > /dev/null 2>&1; echo "migration exit=$?"
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261122100010_dating_v2_traveller_grants.sql > /dev/null 2>&1; echo "twin exit=$?"
done
python3 -I $D/marked_diff.py $D/before_w8b attune_spec3a 'Spec 2 W8b' | grep -c ' OK$'; echo "marked_diff exit=${PIPESTATUS[0]}"
python3 -I $D/edit_tests_T5.py
for f in dating_v2_device_contracts dating_rls_canary dating_v2_moderation_contracts dating_v2_matching_contracts dating_v2_chat_contracts; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$f.sql > /dev/null 2>&1 && echo "$f exit=0" || echo "$f FAILED"
done
```

Expected: `…twin_T5.sql spliced at -- @@W8B-T5-GRANTS@@`; `…: 9 re-created function(s), 1100 lines`; four `exit=0`; `9`, `marked_diff exit=0`; `…dating_rls_canary.sql: 1 edit(s) (T5 canary)`, `…dating_v2_moderation_contracts.sql: 4 edit(s) (T5 W7 contract shapes)`; five lines ending `exit=0`.

- [ ] **Step 4: The mutants (Task 5's, then Task 4's again on the rebuilt migration)**

Create `.superpowers/sdd/2026-11-22-spec2-w8/mut_T5.py` with exactly:

````python
# Spec 2 W8b Task 5 mutants (mutate.py on 20261122100000_dating_v2_traveller.sql,
# the twin after each). Each must make dating_v2_device_contracts.sql fail
# with a CONTRACT VIOLATED line.
O = "CASE WHEN v_i.user_low_id = v_user THEN v_i.user_high_id ELSE v_i.user_low_id END"
MUTS = {
    'today_shows_hidden': (f"    CONTINUE WHEN private.dating_trip_hides(v_user, {O}, 'introduction'); -- Spec 2 W8b (§2.5)\n", ''),
    'moment_shows_hidden': ("     AND NOT private.dating_trip_hides(v_user, p.user_id, 'match'); -- Spec 2 W8b (§2.5)\n", "     ;\n"),
    'intros_read_shows_hidden': (f"    IF v_card IS NOT NULL AND NOT private.dating_trip_hides(v_user, {O}, 'introduction') THEN -- Spec 2 W8b (§2.5)\n",
                                 "    IF v_card IS NOT NULL THEN\n"),
    'act_on_hidden': (f"         OR private.dating_trip_hides(v_user, {O}, 'introduction') THEN -- Spec 2 W8b (§2.5): hidden on a trip\n",
                      "         THEN\n"),
    'chats_show_hidden': ("             AND NOT private.dating_trip_hides(v_user, s.other, 'match')) AS c; -- Spec 2 W8b (§2.5): hidden on this phone on a trip\n",
                          "             ) AS c;\n"),
    'ended_show_hidden': ("       AND NOT private.dating_trip_hides(v_user, CASE WHEN m.user_low_id = v_user THEN m.user_high_id ELSE m.user_low_id END, 'match') -- Spec 2 W8b\n", ''),
    'messages_show_hidden': ("    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable'); -- Spec 2 W8b: hidden on this phone on a trip\n",
                             "    NULL;\n"),
    'not_hidden_from_others': ("          OR (p_kind = 'introduction' AND v_them.user_id IS NOT NULL AND v_them.same_gender_allowed_here IS FALSE)) THEN\n",
                               "          ) THEN\n"),
    'away_ignores_show_here': ("  IF v_me.user_id IS NOT NULL AND NOT v_me.show_here AND v_me.dating_allowed_here IS FALSE THEN\n",
                               "  IF v_me.user_id IS NOT NULL AND v_me.dating_allowed_here IS FALSE THEN\n"),
    'show_here_exposes_others': ("          OR (p_kind = 'introduction' AND v_them.user_id IS NOT NULL AND v_them.same_gender_allowed_here IS FALSE)) THEN\n",
                                 "          OR (p_kind = 'introduction' AND v_them.user_id IS NOT NULL AND NOT v_them.show_here AND v_them.same_gender_allowed_here IS FALSE)) THEN\n"),
    'man_woman_hidden': ("  RETURN NOT coalesce(v_mw, false);\n", "  RETURN true;\n"),
    'review_without_moderator': ("               AND EXISTS (SELECT 1 FROM public.dating_moderators AS m WHERE m.active AND m.role = 'moderator')\n              THEN 'staffed'", "              THEN 'staffed'"),
    'review_always_testing': ("              THEN 'staffed' ELSE 'testing' END;\n", "              THEN 'testing' ELSE 'testing' END;\n"),
    'clash_raises': ("            OR unique_violation THEN -- Spec 2 W8b (W7 carry n4-2): a reference-code clash is busy, never an error\n",
                     "            THEN\n"),
    'restriction_without_review': ("    'review', private.dating_review_mode(), -- Spec 2 W8b (W7 carry M-6)\n", ''),
    'appeal_without_review': ("      PERFORM private.bump_metric_internal('dating.appeal.submitted');\n      RETURN pg_catalog.jsonb_build_object('ok', true, 'review', private.dating_review_mode()); -- Spec 2 W8b (W7 carry M-6)\n",
                              "      PERFORM private.bump_metric_internal('dating.appeal.submitted');\n      RETURN pg_catalog.jsonb_build_object('ok', true);\n"),
    'replay_without_review': ("idempotency_key = p_idempotency_key) THEN\n        RETURN pg_catalog.jsonb_build_object('ok', true, 'review', private.dating_review_mode()); -- Spec 2 W8b (W7 carry M-6)\n",
                              "idempotency_key = p_idempotency_key) THEN\n        RETURN pg_catalog.jsonb_build_object('ok', true);\n"),
}
````

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
M=supabase/migrations/20261122100000_dating_v2_traveller.sql; C=supabase/tests/dating_v2_device_contracts.sql; G=supabase/migrations/20261122100010_dating_v2_traveller_grants.sql
W8_DB=attune_spec3a python3 -I $D/mutate.py $M $C $D/mut_T5.py $D/mut $G | tee $D/mut_T5.txt | grep -c 'CONTRACT VIOLATED'
W8_DB=attune_spec3a python3 -I $D/mutate.py $M $C $D/mut_T4.py $D/mut $G | tee $D/mut_T4_afterT5.txt | grep -c 'CONTRACT VIOLATED'
```

Expected: `17`; `20`.

- [ ] **Step 5: Record the tree (do not commit).**

### Task 6: The `dating-device-check` edge function, the IP table and its builder (§2.3, §4.7, §7.3; R-73, R-74, R-75)

**Files:**
- Create: `supabase/functions/dating-device-check/{ip_country.ts, ip_table_build.ts, handler.ts, request.ts, index.ts, handler.test.ts}`, `scripts/ip_country/build_ip_country.ts`, `$D/{edit_ci_T6.py, mut_T6.py}`
- Modify: `.github/workflows/tests.yml` (the test and check lines), `supabase/config.toml` (the function, its static file), `.gitignore` (the built table)
- Test: `supabase/functions/dating-device-check/handler.test.ts`

**Interfaces:**
- Consumes: `record_dating_device_check` (Task 4), `requireUser`, `serviceRoleClient`, `HttpError`, `clientIp`, `errorCode`, `deviceHashOf` (`dating-photo-urls/handler.ts`).
- Produces: POST `dating-device-check` `{network_country?: "AE"}` → `{ok: true, trusted, away, note: null | {country}}` | `{ok: false, reason: invalid|unavailable|device_unavailable|busy|unauthorized}`; `IpCountryResolver`, `NO_RESOLVER`, `RangeTable`, `loadResolver(url, read?)`, `parseIpv4`, `parseIpv6`, `buildTable(csv)`.

- [ ] **Step 1: Write the failing test**

Create `supabase/functions/dating-device-check/handler.test.ts` with exactly:

````ts
// Spec 2 W8b (§2.3, §4.7, §7.3; R-71..R-76): dating-device-check. The IP
// becomes a country in the request and is never stored, logged, passed on
// or answered; the network country is two upper-case letters or nothing;
// a phone with no install id is device_unavailable; refusals are fixed
// codes, a server error or a slow call busy; the answer carries only
// trusted, away and the place's country for the note. The IP table: ranges
// from DB-IP's CSV, merged, gaps and the space outside answer null, IPv6
// by its top 64 bits; no table or a bad one answers null for every IP.
import { type Caller, type DeviceCheckDeps, handleDeviceCheck, RPC_TIMEOUT_MS } from "./handler.ts";
import { handleRequest } from "./request.ts";
import { loadResolver, NO_RESOLVER, parseIpv6, RangeTable } from "./ip_country.ts";
import { buildTable } from "./ip_table_build.ts";
import { HttpError } from "../_shared/attune_auth.ts";
import { deviceHashOf as verificationHash } from "../dating-verification/handler.ts";
import { deviceHashOf } from "../dating-photo-urls/handler.ts";

function eq(actual: unknown, expected: unknown, why = "") {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${why} expected ${e}, got ${a}`);
}

const USER = "99999999-2222-4333-8444-555555555555";
const HASH = "a".repeat(64);
const CALLER: Caller = { userId: USER, deviceHash: HASH, ipCountry: "AE" };
const never = <T>() => new Promise<T>(() => {});

interface Opts {
  error?: boolean;
  rejects?: boolean;
  hangs?: boolean;
}

function deps(data: unknown, seen: Array<[string, Record<string, unknown>]>, opts: Opts = {}): DeviceCheckDeps {
  return {
    rpc: (fn, args) => {
      seen.push([fn, args]);
      if (opts.rejects) return Promise.reject(new Error("server text: connection reset"));
      if (opts.hangs) return never();
      return Promise.resolve({ data: opts.error ? null : data, error: opts.error ? { message: "server text" } : null });
    },
    rpcTimeoutMs: 20,
  };
}

const OK = { ok: true, trusted: true, away: true, here: "AE" };

Deno.test("the check: the caller's id, the phone's hash, the IP and network countries; the answer's three fields", async () => {
  const seen: Array<[string, Record<string, unknown>]> = [];
  const a = await handleDeviceCheck({ network_country: "AE", p_user: "someone-else" }, CALLER, deps(OK, seen));
  eq(a, { ok: true, trusted: true, away: true, note: { country: "AE" } });
  eq(seen, [["record_dating_device_check", { p_user: USER, p_device_hash: HASH, p_ip_country: "AE", p_network_country: "AE" }]]);
  const b = await handleDeviceCheck({}, { ...CALLER, ipCountry: null }, deps({ ok: true, trusted: false, away: false, here: null }, seen));
  eq(b, { ok: true, trusted: false, away: false, note: null });
  eq(seen[1][1].p_ip_country, null);
  eq(seen[1][1].p_network_country, null);
  // A same-gender trip: the phone is trusted, Dating isn't hidden, the
  // note names the place.
  const c = await handleDeviceCheck({}, CALLER, deps({ ok: true, trusted: true, away: false, here: "GH" }, seen));
  eq(c, { ok: true, trusted: true, away: false, note: { country: "GH" } });
});

Deno.test("a bad network country is invalid and calls nothing; a bad IP country is no country", async () => {
  for (const bad of ["ae", "AEE", 7, "A1", "", {}]) {
    const seen: Array<[string, Record<string, unknown>]> = [];
    eq(await handleDeviceCheck({ network_country: bad }, CALLER, deps(OK, seen)), { ok: false, reason: "invalid" }, String(bad));
    eq(seen.length, 0);
  }
  const seen: Array<[string, Record<string, unknown>]> = [];
  await handleDeviceCheck({}, { ...CALLER, ipCountry: "1.2.3.4" }, deps(OK, seen));
  eq(seen[0][1].p_ip_country, null);
});

Deno.test("no install id: device_unavailable, nothing called", async () => {
  const seen: Array<[string, Record<string, unknown>]> = [];
  eq(await handleDeviceCheck({}, { ...CALLER, deviceHash: null }, deps(OK, seen)), { ok: false, reason: "device_unavailable" });
  eq(seen.length, 0);
});

Deno.test("refusals are fixed codes; errors, rejections and slow calls are busy; a bad place is no note", async () => {
  const seen: Array<[string, Record<string, unknown>]> = [];
  eq(await handleDeviceCheck({}, CALLER, deps({ ok: false, reason: "invalid" }, seen)), { ok: false, reason: "invalid" });
  eq(await handleDeviceCheck({}, CALLER, deps({ ok: false, reason: "unavailable" }, seen)), { ok: false, reason: "unavailable" });
  eq(await handleDeviceCheck({}, CALLER, deps({ ok: false, reason: "server text" }, seen)), { ok: false, reason: "busy" });
  eq(await handleDeviceCheck({}, CALLER, deps(OK, seen, { error: true })), { ok: false, reason: "busy" });
  eq(await handleDeviceCheck({}, CALLER, deps(OK, seen, { rejects: true })), { ok: false, reason: "busy" });
  eq(await handleDeviceCheck({}, CALLER, deps(OK, seen, { hangs: true })), { ok: false, reason: "busy" });
  eq(await handleDeviceCheck({}, CALLER, deps("text", seen)), { ok: false, reason: "busy" });
  eq(await handleDeviceCheck({}, CALLER, deps({ ...OK, here: "Abu Dhabi" }, seen)), { ok: true, trusted: true, away: true, note: null });
  eq(RPC_TIMEOUT_MS, 5000);
});

const CSV = [
  "1.0.0.0,1.0.0.255,AU",
  "1.0.1.0,1.0.3.255,CN",
  "1.0.4.0,1.0.7.255,CN",
  "5.0.0.0,5.0.0.255,AE",
  '"41.66.0.0","41.66.255.255","GH"',
  "255.255.255.0,255.255.255.255,ZZX",
  "2001:db8::,2001:db8:ffff:ffff:ffff:ffff:ffff:ffff,GB",
  "2c0f:f000::,2c0f:f0ff:ffff:ffff:ffff:ffff:ffff:ffff,GH",
  "not,a,row",
].join("\n");

Deno.test("the table: ranges, merges, gaps and the space outside; IPv6 by its top 64 bits", () => {
  const t = new RangeTable(buildTable(CSV));
  eq(t.country("1.0.0.0"), "AU");
  eq(t.country("1.0.0.255"), "AU");
  eq(t.country("1.0.2.9"), "CN");
  eq(t.country("1.0.7.255"), "CN");
  eq(t.country("1.0.8.0"), null);
  eq(t.country("0.255.255.255"), null);
  eq(t.country("5.0.0.7"), "AE");
  eq(t.country("41.66.12.1"), "GH");
  eq(t.country("41.67.0.0"), null);
  eq(t.country("255.255.255.9"), null);
  eq(t.country("2001:db8::1"), "GB");
  eq(t.country("2001:DB8:0:0:1::"), "GB");
  eq(t.country("2001:db9::"), null);
  eq(t.country("2c0f:f012:3::4"), "GH");
  eq(t.country("::1"), null);
  eq(t.country("not an address"), null);
  eq(t.country("1.2.3.256"), null);
  // CN's two adjacent ranges are one: 1.0.0.0 (AU), 1.0.1.0 (CN), 1.0.8.0
  // (gap), 5.0.0.0 (AE), 5.0.1.0 (gap), 41.66.0.0 (GH), 41.67.0.0 (gap).
  const bytes = buildTable(CSV);
  const view = new DataView(bytes.buffer);
  eq([view.getUint32(5), view.getUint32(9)], [7, 4]);
  eq(parseIpv6("::ffff:1.2.3.4"), null);
  eq(parseIpv6("1::2::3"), null);
});

function isNone(r: unknown, why: string) {
  if (r !== NO_RESOLVER) throw new Error(`${why}: a resolver was loaded`);
}

Deno.test("no table, or a bad one, resolves nothing", async () => {
  const missing = await loadResolver(new URL("./no-such-table.bin", import.meta.url));
  isNone(missing, "no file");
  eq(missing.country("5.0.0.7"), null);
  const bad = await loadResolver(new URL("file:///x"), () => Promise.resolve(new Uint8Array([0x41, 0x49, 0x50, 0x43, 1, 0, 0])));
  isNone(bad, "a header only");
  const short = buildTable(CSV).slice(0, -1);
  isNone(await loadResolver(new URL("file:///x"), () => Promise.resolve(short)), "one byte short");
  const v2 = buildTable(CSV);
  v2[4] = 2;
  isNone(await loadResolver(new URL("file:///x"), () => Promise.resolve(v2)), "another version");
  const good = await loadResolver(new URL("file:///x"), () => Promise.resolve(buildTable(CSV)));
  eq(good.country("41.66.0.1"), "GH");
});

Deno.test("the request: the address becomes a country and goes no further; no-store; fixed refusals", async () => {
  const logged: unknown[][] = [];
  const realError = console.error, realLog = console.log, realWarn = console.warn;
  console.error = (...a: unknown[]) => logged.push(a);
  console.log = (...a: unknown[]) => logged.push(a);
  console.warn = (...a: unknown[]) => logged.push(a);
  try {
    const calls: Array<[string, Record<string, unknown>]> = [];
    const looked: string[] = [];
    const wiring = {
      requireUser: (_: Request) => Promise.resolve({ id: USER }),
      client: () => ({
        rpc: (fn: string, args: Record<string, unknown>) => {
          calls.push([fn, args]);
          return Promise.resolve({ data: OK, error: null });
        },
      }),
      resolver: () => Promise.resolve({ country: (ip: string) => (looked.push(ip), "AE") }),
    };
    const id = "0123456789abcdef0123456789abcdef";
    const res = await handleRequest(new Request("https://fn.test/dating-device-check", {
      method: "POST",
      headers: { "cf-connecting-ip": "5.0.0.7", "x-forwarded-for": "9.9.9.9", "x-attune-device": id },
      body: JSON.stringify({ network_country: "AE" }),
    }), wiring);
    eq(res.headers.get("Cache-Control"), "no-store");
    const text = await res.text();
    eq(JSON.parse(text), { ok: true, trusted: true, away: true, note: { country: "AE" } });
    eq(looked, ["5.0.0.7"]);
    eq(calls[0][1].p_device_hash, await deviceHashOf(id));
    for (const where of [text, JSON.stringify(calls), JSON.stringify(logged)]) {
      if (where.includes("5.0.0.7") || where.includes("9.9.9.9")) throw new Error(`the address leaked: ${where}`);
    }
    // No address the front door gave: no lookup, no country.
    looked.length = 0;
    await handleRequest(new Request("https://fn.test/", { method: "POST", headers: { "x-attune-device": id }, body: "{}" }), wiring);
    eq(looked, []);
    eq(calls[1][1].p_ip_country, null);
    // A resolver that throws is no country, never an error.
    const broken = { ...wiring, resolver: () => Promise.reject(new Error("table")) };
    const r2 = await handleRequest(new Request("https://fn.test/", {
      method: "POST",
      headers: { "cf-connecting-ip": "5.0.0.7", "x-attune-device": id },
      body: "{}",
    }), broken);
    eq(r2.status, 200);
    eq(calls[2][1].p_ip_country, null);
    const denied = await handleRequest(new Request("https://fn.test/", { method: "POST", body: "{}" }), {
      ...wiring,
      requireUser: () => Promise.reject(new HttpError("unauthorized", 401)),
    });
    eq([denied.status, await denied.json()], [401, { ok: false, reason: "unauthorized" }]);
    eq((await handleRequest(new Request("https://fn.test/", { method: "GET" }), wiring)).status, 405);
    eq((await handleRequest(new Request("https://fn.test/", { method: "OPTIONS" }), wiring)).status, 200);
    const failing = await handleRequest(new Request("https://fn.test/", {
      method: "POST",
      headers: { "cf-connecting-ip": "5.0.0.7", "x-attune-device": id },
      body: "{}",
    }), { ...wiring, client: () => { throw new Error("5.0.0.7 server text"); } });
    eq([failing.status, await failing.json()], [500, { ok: false, reason: "busy" }]);
    if (JSON.stringify(logged).includes("5.0.0.7")) throw new Error("an error's text was logged");
  } finally {
    console.error = realError;
    console.log = realLog;
    console.warn = realWarn;
  }
});

Deno.test("the phone's hash is dating-verification's", async () => {
  const id = "0123456789abcdef0123456789abcdef";
  eq(await deviceHashOf(id), await verificationHash(id));
});
````

- [ ] **Step 2: Run it to see it fail**

```bash
(cd supabase/functions && deno test --allow-read --allow-env --lock=../../.github/deno-w9.lock --frozen dating-device-check/handler.test.ts 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "Module not found|Cannot find module|error:" | head -1)
```

Expected: `TS2307 [ERROR]: Cannot find module '…/supabase/functions/dating-device-check/handler.ts'.`

- [ ] **Step 3: The resolver, the table builder, the handler, the wiring, the entry point and the CLI**

Create `supabase/functions/dating-device-check/ip_country.ts` with exactly:

````ts
// supabase/functions/dating-device-check/ip_country.ts
// Spec 2 W8b (§2.3; R-74): the IP country, behind the IpCountryResolver
// seam. The table is DB-IP's IP to Country Lite (CC BY 4.0, refreshed
// monthly), built into a compact file at deploy time
// (scripts/ip_country/build_ip_country.ts) and shipped as this function's
// static file, never committed. An address is only ever looked up here, in
// memory: never stored, logged or sent. No table, an unreadable one, or an
// address it doesn't cover answers null, and the database then uses the
// phone and network countries (§2.3: as for a VPN).
//
// The file ("AIPC", version 1): magic(4) version(1) n4(u32 BE) n6(u32 BE),
// then n4 IPv4 range starts (u32 BE) and their n4 countries (2 ASCII bytes;
// "--" is no country), then n6 IPv6 range starts as their top 64 bits (u64
// BE) and their n6 countries. Starts ascend; a range runs to the next start.

export interface IpCountryResolver {
  /// Upper-case ISO 3166-1 alpha-2, or null.
  country(ip: string): string | null;
}

export const NO_RESOLVER: IpCountryResolver = { country: () => null };

const MAGIC = [0x41, 0x49, 0x50, 0x43]; // "AIPC"
const IPV4 = /^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$/;

export function parseIpv4(ip: string): number | null {
  if (!IPV4.test(ip)) return null;
  return ip.split(".").reduce((n, part) => n * 256 + Number(part), 0);
}

/// The top 64 bits of an IPv6 address (enough for every allocation the
/// table holds), or null. An IPv4-mapped address is not IPv6 here.
export function parseIpv6(ip: string): bigint | null {
  const s = ip.trim().toLowerCase();
  if (!s.includes(":") || !/^[0-9a-f:.]+$/.test(s) || s.split("::").length > 2) return null;
  const [head, tail] = s.includes("::") ? s.split("::") : [s, undefined];
  const groups = (part: string | undefined) => (part === undefined || part === "" ? [] : part.split(":"));
  const left = groups(head);
  const right = groups(tail);
  let words: string[];
  if (tail === undefined) {
    words = left;
  } else {
    const fill = 8 - left.length - right.length;
    if (fill < 1) return null;
    words = [...left, ...Array(fill).fill("0"), ...right];
  }
  if (words.length !== 8 || words.some((w) => !/^[0-9a-f]{1,4}$/.test(w))) return null;
  let top = 0n;
  for (const w of words.slice(0, 4)) top = (top << 16n) | BigInt(parseInt(w, 16));
  return top;
}

function countryAt(bytes: Uint8Array, at: number): string | null {
  const code = String.fromCharCode(bytes[at], bytes[at + 1]);
  return /^[A-Z]{2}$/.test(code) ? code : null;
}

export class RangeTable implements IpCountryResolver {
  readonly #bytes: Uint8Array;
  readonly #view: DataView;
  readonly #n4: number;
  readonly #n6: number;

  /// Throws on a file that isn't a version-1 table of the right length.
  constructor(bytes: Uint8Array) {
    if (bytes.length < 13 || MAGIC.some((m, i) => bytes[i] !== m) || bytes[4] !== 1) {
      throw new Error("ip_table_invalid");
    }
    this.#bytes = bytes;
    this.#view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    this.#n4 = this.#view.getUint32(5);
    this.#n6 = this.#view.getUint32(9);
    if (bytes.length !== 13 + this.#n4 * 6 + this.#n6 * 10) throw new Error("ip_table_invalid");
  }

  country(ip: string): string | null {
    const v4 = parseIpv4(ip.trim());
    if (v4 !== null) {
      const i = this.#last(this.#n4, (k) => this.#view.getUint32(13 + k * 4) <= v4);
      return i < 0 ? null : countryAt(this.#bytes, 13 + this.#n4 * 4 + i * 2);
    }
    const v6 = parseIpv6(ip);
    if (v6 === null) return null;
    const base = 13 + this.#n4 * 6;
    const i = this.#last(this.#n6, (k) => this.#view.getBigUint64(base + k * 8) <= v6);
    return i < 0 ? null : countryAt(this.#bytes, base + this.#n6 * 8 + i * 2);
  }

  /// The last index in [0, n) whose start is at or below the address.
  #last(n: number, atOrBelow: (k: number) => boolean): number {
    let lo = 0;
    let hi = n - 1;
    let found = -1;
    while (lo <= hi) {
      const mid = (lo + hi) >>> 1;
      if (atOrBelow(mid)) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }
}

/// The table at [url]; no file or an unreadable one is NO_RESOLVER.
export async function loadResolver(url: URL, read: (u: URL) => Promise<Uint8Array> = Deno.readFile): Promise<IpCountryResolver> {
  try {
    return new RangeTable(await read(url));
  } catch {
    return NO_RESOLVER;
  }
}
````

Create `supabase/functions/dating-device-check/ip_table_build.ts` with exactly:

````ts
// supabase/functions/dating-device-check/ip_table_build.ts
// Spec 2 W8b (R-74): DB-IP's country CSV ("start,end,country" per line,
// IPv4 and IPv6 mixed) to the compact table ip_country.ts reads. Adjacent
// ranges of one country merge; gaps become "--" (no country); IPv6 is kept
// at its top 64 bits. Used by scripts/ip_country/build_ip_country.ts at
// deploy time, and by the tests.
import { parseIpv4, parseIpv6 } from "./ip_country.ts";

const TOP64 = (1n << 64n) - 1n;
const V4_TOP = 0xffffffff;

type Range<T> = { start: T; end: T; country: string };

/// Sorted starts and countries: an overlap keeps the first range, a gap is
/// "--", one country's adjacent ranges are one. [after] is the address
/// after [x], or null at the top of the space.
function merge<T extends number | bigint>(ranges: Range<T>[], after: (x: T) => T | null): Array<[T, string]> {
  ranges.sort((a, b) => (a.start < b.start ? -1 : a.start > b.start ? 1 : 0));
  const out: Array<[T, string]> = [];
  let next: T | null = null;
  let started = false;
  for (const r of ranges) {
    if (started && next === null) break;
    if (started && r.start < (next as T)) continue;
    if (started && r.start > (next as T)) out.push([next as T, "--"]);
    const last = out[out.length - 1];
    if (!(started && last !== undefined && last[1] === r.country && r.start === next)) out.push([r.start, r.country]);
    next = after(r.end);
    started = true;
  }
  if (started && next !== null) out.push([next, "--"]);
  return out;
}

export function buildTable(csv: string): Uint8Array {
  const v4: Range<number>[] = [];
  const v6: Range<bigint>[] = [];
  for (const raw of csv.split(/\r?\n/)) {
    const [a, b, c] = raw.replaceAll('"', "").split(",").map((x) => x.trim());
    if (!a || !b || !c || !/^[A-Z]{2}$/.test(c)) continue;
    const s4 = parseIpv4(a), e4 = parseIpv4(b);
    if (s4 !== null && e4 !== null && s4 <= e4) {
      v4.push({ start: s4, end: e4, country: c });
      continue;
    }
    const s6 = parseIpv6(a), e6 = parseIpv6(b);
    if (s6 !== null && e6 !== null && s6 <= e6) v6.push({ start: s6, end: e6, country: c });
  }
  const r4 = merge(v4, (x) => (x === V4_TOP ? null : x + 1));
  const r6 = merge(v6, (x) => (x === TOP64 ? null : x + 1n));
  const out = new Uint8Array(13 + r4.length * 6 + r6.length * 10);
  const view = new DataView(out.buffer);
  out.set([0x41, 0x49, 0x50, 0x43, 1]);
  view.setUint32(5, r4.length);
  view.setUint32(9, r6.length);
  let at = 13;
  for (const [start] of r4) (view.setUint32(at, start), (at += 4));
  for (const [, c] of r4) (out.set([c.charCodeAt(0), c.charCodeAt(1)], at), (at += 2));
  for (const [start] of r6) (view.setBigUint64(at, start), (at += 8));
  for (const [, c] of r6) (out.set([c.charCodeAt(0), c.charCodeAt(1)], at), (at += 2));
  return out;
}
````

Create `supabase/functions/dating-device-check/handler.ts` with exactly:

````ts
// supabase/functions/dating-device-check/handler.ts
// Spec 2 W8b (§2.3, §2.5, §3.11, §4.7; R-71..R-76): where the person is,
// in the moment. The caller is the signed-in person; the IP's country
// (resolved in request.ts, the address dropped there) and, on Android, the
// network country the app sends go to record_dating_device_check (the
// service role's) with the phone's hash; it records the session context
// (at most once per 15 minutes) and answers whether this phone is trusted,
// whether Dating is hidden here, and, while the place restricts, its
// country for the in-app note's words. The answer is {ok:true, trusted,
// away, note: null | {country}} or {ok:false, reason} with a fixed code.
// Never an address, a server's text or an error; nothing is logged.
export type RpcResult = { data: unknown; error: unknown };

export interface DeviceCheckDeps {
  rpc(fn: string, args: Record<string, unknown>): PromiseLike<RpcResult>;
  /// The database call's bound (default RPC_TIMEOUT_MS; tests pass their own).
  rpcTimeoutMs?: number;
}

export interface Caller {
  userId: string;
  deviceHash: string | null;
  /// The request's IP country (null: not resolved, as for a VPN).
  ipCountry: string | null;
}

export type Answer =
  | { ok: true; trusted: boolean; away: boolean; note: { country: string } | null }
  | { ok: false; reason: string };

export const RPC_TIMEOUT_MS = 5_000;
const CODE = /^[A-Z]{2}$/;
const REFUSALS: ReadonlySet<string> = new Set(["invalid", "unavailable"]);

function withTimeout<T>(p: PromiseLike<T>, ms: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const late = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error("timeout")), ms);
  });
  return Promise.race([Promise.resolve(p), late]).finally(() => clearTimeout(timer));
}

export async function handleDeviceCheck(body: unknown, caller: Caller, deps: DeviceCheckDeps): Promise<Answer> {
  const b = (body ?? {}) as Record<string, unknown>;
  const net = b.network_country;
  if (net !== undefined && net !== null && (typeof net !== "string" || !CODE.test(net))) {
    return { ok: false, reason: "invalid" };
  }
  // W4 fix round 1 (I-4): a phone with no install id can't be checked.
  if (caller.deviceHash === null) return { ok: false, reason: "device_unavailable" };
  const ip = caller.ipCountry !== null && CODE.test(caller.ipCountry) ? caller.ipCountry : null;
  let res: RpcResult;
  try {
    res = await withTimeout(deps.rpc("record_dating_device_check", {
      p_user: caller.userId,
      p_device_hash: caller.deviceHash,
      p_ip_country: ip,
      p_network_country: typeof net === "string" ? net : null,
    }), deps.rpcTimeoutMs ?? RPC_TIMEOUT_MS);
  } catch {
    return { ok: false, reason: "busy" };
  }
  if (res.error) return { ok: false, reason: "busy" };
  const d = res.data as { ok?: unknown; reason?: unknown; trusted?: unknown; away?: unknown; here?: unknown } | null;
  if (d === null || typeof d !== "object") return { ok: false, reason: "busy" };
  if (d.ok !== true) {
    return { ok: false, reason: typeof d.reason === "string" && REFUSALS.has(d.reason) ? d.reason : "busy" };
  }
  return {
    ok: true,
    trusted: d.trusted === true,
    away: d.away === true,
    note: typeof d.here === "string" && CODE.test(d.here) ? { country: d.here } : null,
  };
}
````

Create `supabase/functions/dating-device-check/request.ts` with exactly:

````ts
// supabase/functions/dating-device-check/request.ts
// Spec 2 W8b (§2.3, §4.7): the HTTP wiring for handler.ts, kept out of
// index.ts so a test drives it with the user check, the service client and
// the resolver injected. The caller's address (client_ip.ts: Cloudflare's
// cf-connecting-ip, else the right-most x-forwarded-for hop) is turned
// into a country here and dropped: it is never stored, logged, passed on
// or answered. The x-attune-device header is hashed and only the hash is
// passed on. Every answer is Cache-Control: no-store. Only an error's code
// is ever logged.
import { HttpError } from "../_shared/attune_auth.ts";
import { clientIp } from "../_shared/client_ip.ts";
import { errorCode } from "../_shared/error_code.ts";
import { deviceHashOf } from "../dating-photo-urls/handler.ts";
import { handleDeviceCheck, type RpcResult } from "./handler.ts";
import type { IpCountryResolver } from "./ip_country.ts";

/// The slice of the service-role client this function uses.
export interface DeviceCheckClient {
  rpc(fn: string, args: Record<string, unknown>): PromiseLike<RpcResult>;
}

export interface Wiring {
  requireUser(req: Request): Promise<{ id: string }>;
  client(): DeviceCheckClient;
  resolver(): Promise<IpCountryResolver>;
}

function answer(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

export async function handleRequest(req: Request, wiring: Wiring): Promise<Response> {
  if (req.method === "OPTIONS") return answer({ ok: true });
  if (req.method !== "POST") return answer({ ok: false, reason: "invalid" }, 405);
  try {
    const user = await wiring.requireUser(req);
    const supabase = wiring.client();
    const body = await req.json().catch(() => ({}));
    let ipCountry: string | null = null;
    try {
      const ip = clientIp(req.headers);
      ipCountry = ip === "unknown" ? null : (await wiring.resolver()).country(ip);
    } catch {
      ipCountry = null;
    }
    const result = await handleDeviceCheck(body, {
      userId: user.id,
      deviceHash: await deviceHashOf(req.headers.get("x-attune-device")),
      ipCountry,
    }, { rpc: (fn, args) => supabase.rpc(fn, args) });
    return answer(result);
  } catch (error) {
    if (error instanceof HttpError) return answer({ ok: false, reason: "unauthorized" }, error.status);
    console.error("dating-device-check failed:", errorCode(error));
    return answer({ ok: false, reason: "busy" }, 500);
  }
}
````

Create `supabase/functions/dating-device-check/index.ts` with exactly:

````ts
// supabase/functions/dating-device-check/index.ts
// Spec 2 W8b (§4.7): serves request.ts with the live user check, the
// service-role client and the IP table shipped as this function's static
// file (ip_country.bin, built at deploy time; none: every IP unresolved).
// The table is read once per instance.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, serviceRoleClient } from "../_shared/attune_auth.ts";
import { type IpCountryResolver, loadResolver } from "./ip_country.ts";
import { handleRequest } from "./request.ts";

let table: Promise<IpCountryResolver> | null = null;
const resolver = () => (table ??= loadResolver(new URL("./ip_country.bin", import.meta.url)));

serve((req) => handleRequest(req, { requireUser, client: serviceRoleClient, resolver }));
````

Create `scripts/ip_country/build_ip_country.ts` with exactly:

````ts
// scripts/ip_country/build_ip_country.ts
// Spec 2 W8b (R-74; Owner checklist): builds dating-device-check's IP
// table from DB-IP's "IP to Country Lite" CSV (CC BY 4.0: the app's
// licences and the privacy notice carry "IP Geolocation by DB-IP",
// https://db-ip.com). Run at deploy time, monthly:
//   curl -sSfL -o /tmp/dbip.csv.gz https://download.db-ip.com/free/dbip-country-lite-$(date +%Y-%m).csv.gz
//   gunzip -f /tmp/dbip.csv.gz
//   deno run --allow-read --allow-write scripts/ip_country/build_ip_country.ts /tmp/dbip.csv \
//     supabase/functions/dating-device-check/ip_country.bin
// The output is git-ignored; config.toml ships it as the function's static
// file.
import { buildTable } from "../../supabase/functions/dating-device-check/ip_table_build.ts";
import { RangeTable } from "../../supabase/functions/dating-device-check/ip_country.ts";

const [src, out] = Deno.args;
if (!src || !out) {
  console.error("usage: build_ip_country.ts <dbip-country-lite.csv> <ip_country.bin>");
  Deno.exit(2);
}
const table = buildTable(await Deno.readTextFile(src));
new RangeTable(table); // refuses a malformed result before it is written
await Deno.writeFile(out, table);
const view = new DataView(table.buffer);
console.log(`${out}: ${view.getUint32(5)} IPv4 and ${view.getUint32(9)} IPv6 ranges, ${table.length} bytes`);
````

- [ ] **Step 4: CI, config and the ignored table**

Create `.superpowers/sdd/2026-11-22-spec2-w8/edit_ci_T6.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W8b Task 6 (§4.7, §7.3; R-74): CI runs dating-device-check's tests
# and type-checks its wiring under the frozen lock (no new remote module);
# config.toml names the function (the caller is the signed-in person) and
# ships the IP table as its static file; the built table is git-ignored.
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-22-spec2-w8/anchor.py')['edit']

edit('.github/workflows/tests.yml', [
    (""" process-dating-safety-outbox/handler.test.ts dating-moderation/handler.test.ts
""", """ process-dating-safety-outbox/handler.test.ts dating-moderation/handler.test.ts dating-device-check/handler.test.ts
"""),
    ("""      # dating-moderation (Task 7, Task 6 M-8: the step's name).
      - name: Type-check the Dating edge functions' wiring
        working-directory: supabase/functions
        run: deno check --lock=../../.github/deno-w9.lock --frozen dating-verification/index.ts dating-photo-urls/index.ts process-dating-safety-outbox/index.ts dating-moderation/index.ts
""", """      # dating-moderation (Task 7, Task 6 M-8: the step's name); W8b
      # dating-device-check and its IP table builder.
      - name: Type-check the Dating edge functions' wiring
        working-directory: supabase/functions
        run: deno check --lock=../../.github/deno-w9.lock --frozen dating-verification/index.ts dating-photo-urls/index.ts process-dating-safety-outbox/index.ts dating-moderation/index.ts dating-device-check/index.ts ../../scripts/ip_country/build_ip_country.ts
"""),
], 'T6 CI')

edit('supabase/config.toml', [
    ("""[functions.dating-photo-urls]
verify_jwt = true
""", """[functions.dating-photo-urls]
verify_jwt = true

# Spec 2 W8b (§2.3, §4.7): where the person is, in the moment. The caller is
# the signed-in person; the IP table (DB-IP Lite, built at deploy time by
# scripts/ip_country/build_ip_country.ts, git-ignored) ships as its static
# file.
[functions.dating-device-check]
verify_jwt = true
static_files = ["./functions/dating-device-check/ip_country.bin"]
"""),
], 'T6 config')

with open('.gitignore', 'a') as f:
    f.write('\n# Spec 2 W8b (R-74): the IP table, built at deploy time from DB-IP Lite.\n'
            'supabase/functions/dating-device-check/ip_country.bin\n')
print('.gitignore: the IP table ignored')
````

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
python3 -I $D/edit_ci_T6.py
(cd supabase/functions && deno test --allow-read --allow-env --lock=../../.github/deno-w9.lock --frozen dating-device-check/handler.test.ts 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^ok \||^FAILED')
(cd supabase/functions && eval "$(grep -m1 -oE 'deno test --allow-read [^"]*' ../../.github/workflows/tests.yml)" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^ok \||^FAILED' | tail -1)
(cd supabase/functions && eval "$(grep -m1 -oE 'deno check --lock[^"]*' ../../.github/workflows/tests.yml)" > /dev/null 2>&1; echo "deno check exit=$?")
git check-ignore -q supabase/functions/dating-device-check/ip_country.bin && echo ignored
```

Expected: `.github/workflows/tests.yml: 2 edit(s) (T6 CI)`, `supabase/config.toml: 1 edit(s) (T6 config)`, `.gitignore: the IP table ignored`; `ok | 8 passed | 0 failed`; `ok | 274 passed | 0 failed`; `deno check exit=0`; `ignored`.

- [ ] **Step 5: The mutants**

Create `.superpowers/sdd/2026-11-22-spec2-w8/mut_T6.py` with exactly:

````python
# Spec 2 W8b Task 6: Deno mutants (denomut.py, in a private copy).
TESTS = ['dating-device-check/handler.test.ts']
H = 'supabase/functions/dating-device-check/handler.ts'
R = 'supabase/functions/dating-device-check/request.ts'
I = 'supabase/functions/dating-device-check/ip_country.ts'
B = 'supabase/functions/dating-device-check/ip_table_build.ts'
MUTS = {
    'net_unvalidated': (H, [('(typeof net !== "string" || !CODE.test(net))', '(typeof net !== "string")')]),
    'no_device_ok': (H, [('  if (caller.deviceHash === null) return { ok: false, reason: "device_unavailable" };\n', '')]),
    'body_user': (H, [('      p_user: caller.userId,\n', '      p_user: typeof b.p_user === "string" ? b.p_user : caller.userId,\n')]),
    'server_reason_passed': (H, [('typeof d.reason === "string" && REFUSALS.has(d.reason) ? d.reason : "busy"',
                                  'typeof d.reason === "string" ? d.reason : "busy"')]),
    'long_timeout': (H, [('export const RPC_TIMEOUT_MS = 5_000;', 'export const RPC_TIMEOUT_MS = 50_000;')]),
    'note_unchecked': (H, [('note: typeof d.here === "string" && CODE.test(d.here) ? { country: d.here } : null,',
                            'note: typeof d.here === "string" ? { country: d.here } : null,')]),
    'away_from_trusted': (H, [('    away: d.away === true,\n', '    away: d.trusted === true,\n')]),
    'address_logged': (R, [('      const ip = clientIp(req.headers);\n', '      const ip = clientIp(req.headers);\n      console.log("check", ip);\n')]),
    'resolver_error_raises': (R, [("""    try {
      const ip = clientIp(req.headers);
      ipCountry = ip === "unknown" ? null : (await wiring.resolver()).country(ip);
    } catch {
      ipCountry = null;
    }
""", """    const ip = clientIp(req.headers);
    ipCountry = ip === "unknown" ? null : (await wiring.resolver()).country(ip);
""")]),
    'no_store_dropped': (R, [('headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },',
                              'headers: { "Content-Type": "application/json" },')]),
    'range_start_missed': (I, [('this.#view.getUint32(13 + k * 4) <= v4', 'this.#view.getUint32(13 + k * 4) < v4')]),
    'v6_ignored': (I, [('    const v6 = parseIpv6(ip);\n', '    const v6 = null as bigint | null;\n')]),
    'bad_length_accepted': (I, [("    if (bytes.length !== 13 + this.#n4 * 6 + this.#n6 * 10) throw new Error(\"ip_table_invalid\");\n", '')]),
    'gap_not_written': (B, [("    if (started && r.start > (next as T)) out.push([next as T, \"--\"]);\n", '')]),
    'no_merge': (B, [('    if (!(started && last !== undefined && last[1] === r.country && r.start === next)) out.push([r.start, r.country]);\n',
                      '    out.push([r.start, r.country]);\n')]),
    'end_not_closed': (B, [('  if (started && next !== null) out.push([next, "--"]);\n', '')]),
}
````

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
python3 -I $D/denomut.py $D/mut_T6.py | tee $D/mut_T6.txt | tail -1
```

Expected: `16/16 killed` (`denomut.py` mutates a private copy of `supabase/functions`).

- [ ] **Step 6: Record the tree (do not commit).**

### Task 7: The app's device check, the away card, the trip's note and `/dating/away`, the Android network country, and the restricted screen in testing (§2.3, §2.5, §3.1 away, §3.11, §3.14, §3.15, §7.4; D8; W7 carry M-6; R-73, R-75–R-79, R-81)

**Files:**
- Create: `lib/features/dating/device/{network_country.dart, dating_trip.dart, trip_note.dart}`, `test/features/dating/support/dating_trip_fakes.dart`, `test/features/dating/device/trip_test.dart` and `test/features/dating/device/goldens/dating_away.*.png`, `$D/{arb_fragment_T7.txt, edit_app_T7.py, edit_native_T7.py, edit_tests_T7.py, edit_tests_T7b.py, mut_T7_dart.py}`
- Modify: `lib/features/dating/data/dating_home.dart` (`away`, `DatingTrip`, `trip`, `offerPlainIcon`), `lib/features/dating/routes/dating_routes.dart` (`/dating/away`), `lib/features/dating/section/dating_section.dart` (the check, the note, the away card), `lib/features/dating/report/{dating_report,restricted_screen}.dart` (`staffed`), `MainActivity.kt` (`attune/device`: `networkCountryIso`), `test/features/dating/support/dating_shell.dart` (the trip fakes in every shell), `test/architecture/text_scale_routes_test.dart` (`datingAway`), `lib/i10n/app_en.arb` + generated
- Test: `test/features/dating/device/trip_test.dart`

**Interfaces:**
- Consumes: `dating-device-check` (Task 6), `set_dating_trip_choice` and the home's `away`, `trip`, `offer_plain_icon` (Task 4), the restriction read's `review` (Task 5); `datingWrite`, `DatingActionKeys`, `datingLifecycleGatewayProvider.pause`, `setDatingLockInDating`, `datingLockProvider`, `datingCountryName`, `DatingCalmLine`.
- Produces: see "Interfaces this plan produces" (App); `DatingPaths.away`; the section's keys `dating_trip_note_<account>`, the note's `dating_trip_{hide,show,pause,pin}` and `dating_trip_body`.

- [ ] **Step 1: The fakes, and the failing test**

Create `test/features/dating/support/dating_trip_fakes.dart` with exactly:

````dart
// Spec 2 W8b: the device check and the trip choice faked for widget tests.
// Every call is recorded; a check can be held open (D8 tests).
import 'dart:async';

import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/device/dating_trip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FakeDatingTrip implements DatingTripGateway {
  FakeDatingTrip({
    this.answer = const DatingDeviceCheck(ok: true, trusted: true),
  });

  DatingDeviceCheck answer;
  DatingWrite choice = const DatingWrite(ok: true);
  final checks = <String?>[];
  final choices = <(String key, bool showHere)>[];
  Completer<void>? checkHold;

  @override
  Future<DatingDeviceCheck> check({String? networkCountry}) async {
    checks.add(networkCountry);
    final held = checkHold;
    if (held != null) await held.future;
    return answer;
  }

  @override
  Future<DatingWrite> choose(String key, {required bool showHere}) async {
    choices.add((key, showHere));
    return choice;
  }
}

/// The trip overrides: [fake] and the network country [network].
List<Override> datingTripOverrides(FakeDatingTrip fake, {String? network}) => [
  datingTripGatewayProvider.overrideWithValue(fake),
  datingNetworkCountryProvider.overrideWithValue(() async => network),
];
````

Create `test/features/dating/device/trip_test.dart` with exactly:

````dart
// Spec 2 W8b (§2.3, §2.5, §3.1 away, §3.11, §3.14, §3.15, §7.4; R-75..R-79;
// D8): the device check, the away card, the trip's note and its four
// choices, the note's own page; and the restricted screen's lines in
// testing (W7 carry M-6). The check runs only for someone with Dating
// data on a phone Dating can use, at most once per 15 minutes while the
// section shows, sends the network country, and reads the home again
// when a trip began or ended. The note names the place only while this
// phone's check said so. Never animated; every choice waits offline;
// busy is calm; another account sees nothing of the last one's trip.
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/device/dating_trip.dart';
import 'package:attune/features/dating/device/network_country.dart';
import 'package:attune/features/dating/device/trip_note.dart';
import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_report_fakes.dart';
import '../support/dating_shell.dart';
import '../support/dating_trip_fakes.dart';

final loc = AppLocalizationsEn();

const _away = DatingHome(
  state: DatingHomeState.away,
  hasData: true,
  trip: DatingTrip(kind: DatingTripKind.away, note: true),
);
const _sameGender = DatingHome(
  state: DatingHomeState.active,
  hasData: true,
  trip: DatingTrip(kind: DatingTripKind.sameGender, note: true),
);

class _Section {
  _Section(this.home, this.trip, this.life);
  final FakeDatingHomeGateway home;
  final FakeDatingTrip trip;
  final FakeDatingLifecycleGateway life;
}

Future<_Section> _pump(
  WidgetTester t,
  DatingHome state, {
  DatingDeviceCheck answer = const DatingDeviceCheck(ok: true, trusted: true),
  String? network,
  bool online = true,
}) async {
  await t.pumpWidget(const SizedBox());
  final home = FakeDatingHomeGateway(home: state);
  final trip = FakeDatingTrip(answer: answer);
  final life = FakeDatingLifecycleGateway();
  await pumpFlowScreen(
    t,
    () => const Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: DatingSection(),
      ),
    ),
    overrides: [
      ...datingShellOverrides(home: home, life: life, online: online),
      ...datingTripOverrides(trip, network: network),
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
      homeStateServiceProvider.overrideWithValue(
        HomeStateService(FakeHomeStateGateway(state: homeJson(path: 'dating'))),
      ),
    ],
  );
  await t.pumpAndSettle();
  return _Section(home, trip, life);
}

void main() {
  group('the models', () {
    test('the home reads away, the trip and the plain-icon offer', () {
      final h = DatingHome.fromJson({
        'state': 'away',
        'has_data': true,
        'trip': {'kind': 'away', 'note': true, 'show_here': false},
        'offer_plain_icon': true,
      });
      expect(h.state, DatingHomeState.away);
      expect(h.trip?.kind, DatingTripKind.away);
      expect(h.trip?.note, isTrue);
      expect(h.offerPlainIcon, isTrue);
      final s = DatingHome.fromJson({
        'state': 'active',
        'trip': {'kind': 'same_gender', 'note': false, 'show_here': true},
      });
      expect(s.trip?.kind, DatingTripKind.sameGender);
      expect(s.trip?.showHere, isTrue);
      expect(DatingHome.fromJson({'state': 'active'}).trip, isNull);
      expect(
        DatingHome.fromJson({
          'state': 'active',
          'trip': {'kind': 'x'},
        }).trip,
        isNull,
      );
      expect(DatingHome.fromJson({'state': 'active'}).offerPlainIcon, isFalse);
    });

    test('the check\'s answer, and when it disagrees with the home shown', () {
      final a = DatingDeviceCheck.fromJson({
        'ok': true,
        'trusted': true,
        'away': true,
        'note': {'country': 'AE'},
      });
      expect(
        [a.ok, a.trusted, a.away, a.noteCountry],
        [true, true, true, 'AE'],
      );
      expect(
        DatingDeviceCheck.fromJson({'ok': false, 'reason': 'busy'}).ok,
        isFalse,
      );
      expect(
        DatingDeviceCheck.fromJson({
          'ok': true,
          'note': {'country': 'Dubai'},
        }).noteCountry,
        isNull,
      );
      const home = DatingHome(state: DatingHomeState.active);
      expect(a.disagreesWith(home), isTrue);
      expect(a.disagreesWith(_away), isFalse);
      const there = DatingDeviceCheck(ok: true, noteCountry: 'GH');
      expect(there.disagreesWith(_sameGender), isFalse);
      const back = DatingDeviceCheck(ok: true);
      expect(back.disagreesWith(_sameGender), isTrue);
      expect(back.disagreesWith(home), isFalse);
    });

    test(
      'the network country: Android only, two letters, upper case',
      () async {
        final calls = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NetworkCountry.channel, (call) async {
              calls.add(call.method);
              return calls.length == 1 ? 'ae' : 'United';
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(NetworkCountry.channel, null),
        );
        expect(
          await NetworkCountry.read(platform: TargetPlatform.android),
          'AE',
        );
        expect(
          await NetworkCountry.read(platform: TargetPlatform.android),
          isNull,
        );
        expect(await NetworkCountry.read(platform: TargetPlatform.iOS), isNull);
        expect(calls, ['networkCountryIso', 'networkCountryIso']);
      },
    );
  });

  group('the device check', () {
    testWidgets('someone with Dating data: once per 15 minutes, with the '
        'network country; a trip that began reads the home again', (t) async {
      final s = await _pump(
        t,
        const DatingHome(state: DatingHomeState.active, hasData: true),
        answer: const DatingDeviceCheck(ok: true, trusted: true, away: true),
        network: 'AE',
      );
      expect(s.trip.checks, ['AE']);
      expect(s.home.reads, 2);
      // The app comes back: the home is read again, the check waits.
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(s.home.reads, greaterThan(2));
      expect(s.trip.checks, ['AE']);
    });

    testWidgets('an answer that agrees with the home reads nothing again', (
      t,
    ) async {
      final s = await _pump(
        t,
        const DatingHome(state: DatingHomeState.active, hasData: true),
      );
      expect(s.trip.checks, [null]);
      expect(s.home.reads, 1);
    });

    for (final home in [
      const DatingHome(state: DatingHomeState.notStarted),
      const DatingHome(state: DatingHomeState.reverifyDevice, hasData: true),
      const DatingHome(
        state: DatingHomeState.countryClosed,
        hasData: true,
        country: 'NG',
      ),
    ]) {
      testWidgets('no check for ${home.state.wire} (data: ${home.hasData})', (
        t,
      ) async {
        final s = await _pump(t, home);
        expect(s.trip.checks, isEmpty);
      });
    }
  });

  group('the note', () {
    testWidgets('away: the note is the card, with the place and the four '
        'choices; nothing moves', (t) async {
      await _pump(
        t,
        _away,
        answer: const DatingDeviceCheck(
          ok: true,
          trusted: true,
          away: true,
          noteCountry: 'AE',
        ),
      );
      expect(find.text(loc.dating_tripAwayTitle), findsOneWidget);
      expect(
        find.text(loc.dating_tripAwayBody('United Arab Emirates')),
        findsOneWidget,
      );
      for (final label in [
        loc.dating_tripKeepHidden,
        loc.dating_tripShowAnyway,
        loc.dating_tripPause,
        loc.dating_tripSetPin,
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text(loc.dating_sectionAway), findsNothing);
      expect(find.byType(AnimatedOpacity), findsNothing);
      await expectFlowGuidelines(t);
    });

    testWidgets('no place known yet: "while you\'re away"', (t) async {
      await _pump(t, _away);
      expect(find.text(loc.dating_tripAwayBodyNoPlace), findsOneWidget);
    });

    testWidgets('a same-gender trip: the note above the active card', (
      t,
    ) async {
      await _pump(
        t,
        _sameGender,
        answer: const DatingDeviceCheck(
          ok: true,
          trusted: true,
          noteCountry: 'GH',
        ),
      );
      expect(find.text(loc.dating_tripSameGenderTitle), findsOneWidget);
      expect(find.text(loc.dating_tripSameGenderBody('Ghana')), findsOneWidget);
      expect(find.text(loc.dating_sectionOpenToday), findsOneWidget);
      expect(
        t.getTopLeft(find.text(loc.dating_tripSameGenderTitle)).dy,
        lessThan(t.getTopLeft(find.text(loc.dating_sectionOpenToday)).dy),
      );
    });

    testWidgets('Keep it hidden: the choice under one key, then the home '
        'again', (t) async {
      final s = await _pump(t, _away);
      final before = s.home.reads;
      s.home.home = const DatingHome(
        state: DatingHomeState.away,
        hasData: true,
        trip: DatingTrip(kind: DatingTripKind.away),
      );
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_hide')));
      await t.pumpAndSettle();
      expect(s.trip.choices.single.$2, isFalse);
      expect(s.home.reads, greaterThan(before));
      expect(find.text(loc.dating_tripAwayTitle), findsNothing);
      expect(find.text(loc.dating_sectionAway), findsOneWidget);
    });

    testWidgets('Show it on this phone anyway: shown, the away card offers '
        'the conversations', (t) async {
      final s = await _pump(t, _away);
      s.home.home = const DatingHome(
        state: DatingHomeState.away,
        hasData: true,
        trip: DatingTrip(kind: DatingTripKind.away, showHere: true),
      );
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_show')));
      await t.pumpAndSettle();
      expect(s.trip.choices.single.$2, isTrue);
      expect(find.text(loc.dating_chatsTitle), findsOneWidget);
    });

    testWidgets('Pause Dating: kept hidden first, then paused', (t) async {
      final s = await _pump(t, _away);
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_pause')));
      await t.pumpAndSettle();
      expect(s.trip.choices.single.$2, isFalse);
      expect(s.life.calls, ['pause']);
    });

    testWidgets('a failed pause says so and stays', (t) async {
      final s = await _pump(t, _away);
      s.life.result = const DatingLifecycleResult.refused(
        DatingLifecycleError.busy,
      );
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_pause')));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_busy), findsOneWidget);
      expect(find.text(loc.dating_tripAwayTitle), findsOneWidget);
    });

    testWidgets('busy is a calm line; a failure the error line; no trip any '
        'more just reads the home', (t) async {
      final s = await _pump(t, _away);
      s.trip.choice = DatingWrite.busy;
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_hide')));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_busy), findsOneWidget);
      s.trip.choice = DatingWrite.failed;
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_hide')));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_errorGeneric), findsOneWidget);
      // The same key both times: the outcome was unknown.
      expect(s.trip.choices[0].$1, s.trip.choices[1].$1);
      s.trip.choice = const DatingWrite(ok: false, reason: 'no_trip');
      s.home.home = const DatingHome(
        state: DatingHomeState.active,
        hasData: true,
      );
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_hide')));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_tripAwayTitle), findsNothing);
      expect(find.text(loc.dating_sectionOpenToday), findsOneWidget);
    });

    testWidgets('offline every choice waits', (t) async {
      final s = await _pump(t, _away, online: false);
      expect(find.text(loc.dating_offline), findsWidgets);
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_hide')));
      await t.pumpAndSettle();
      expect(s.trip.choices, isEmpty);
    });
  });

  group('the page', () {
    testWidgets('/dating/away: the note for this account\'s trip; the gone '
        'line without one', (t) async {
      final trip = FakeDatingTrip();
      await pumpDatingShell(
        t,
        initial: DatingPaths.away,
        home: FakeDatingHomeGateway(home: _away),
        overrides: datingTripOverrides(trip),
      );
      expect(find.text(loc.dating_tripAwayTitle), findsOneWidget);
      expect(find.text(loc.dating_tripAwayBodyNoPlace), findsOneWidget);
      await pumpDatingShell(
        t,
        initial: DatingPaths.away,
        home: FakeDatingHomeGateway(
          home: const DatingHome(state: DatingHomeState.active, hasData: true),
        ),
      );
      expect(find.text(loc.dating_cardGone), findsOneWidget);
      expect(find.text(loc.dating_tripAwayTitle), findsNothing);
    });

    testWidgets('D8: another account sees nothing of an open note', (t) async {
      final home = FakeDatingHomeGateway(home: _away);
      final s = await pumpDatingShell(t, initial: DatingPaths.away, home: home);
      expect(find.text(loc.dating_tripAwayTitle), findsOneWidget);
      home.home = const DatingHome(
        state: DatingHomeState.active,
        hasData: true,
      );
      s.container.read(datingTestAccount.notifier).state = 'kofi';
      await t.pump();
      expect(find.text(loc.dating_tripAwayTitle), findsNothing);
      await t.pumpAndSettle();
      expect(find.text(loc.dating_tripAwayTitle), findsNothing);
      expect(find.text(loc.dating_cardGone), findsOneWidget);
    });
  });

  testWidgets('the page: goldens at 1.0, 1.3, 2.0 and RTL; the three '
      'guidelines', (t) async {
    Widget screen() => const DatingAwayScreen();
    final overrides = [
      ...datingShellOverrides(home: FakeDatingHomeGateway(home: _away)),
      ...datingTripOverrides(FakeDatingTrip()),
    ];
    await expectFlowGoldens(t, 'dating_away', screen, overrides: overrides);
    await pumpFlowScreen(t, screen, overrides: overrides);
    await expectFlowGuidelines(t);
  });

  group('the restricted screen in testing (W7 carry M-6)', () {
    Future<void> open(WidgetTester t, Map<String, Object?> json) async {
      final fake =
          FakeDatingReport()..read = DatingRestrictionRead.fromJson(json);
      await pumpDatingShell(
        t,
        initial: DatingPaths.restricted,
        overrides: datingReportOverrides(fake),
      );
    }

    Map<String, Object?> hold(String? review) => {
      'ok': true,
      if (review != null) 'review': review,
      'restriction': {
        'id': 'r1',
        'type': 'hold',
        'category': 'threat_to_life',
        'source': 'p0_interim',
        'can_appeal': false,
      },
    };

    Map<String, Object?> appealed(String? review) => {
      'ok': true,
      if (review != null) 'review': review,
      'restriction': {
        'id': 'r2',
        'type': 'suspended',
        'category': 'harassment',
        'source': 'moderator',
        'ends_at': '2026-12-20T10:00:00Z',
        'can_appeal': false,
        'appeal': {'state': 'open', 'submitted_at': '2026-11-22T10:00:00Z'},
      },
    };

    for (final review in [null, 'testing']) {
      testWidgets('review $review: no review time anywhere', (t) async {
        await open(t, hold(review));
        expect(find.text(loc.dating_restrictedHoldPlain), findsOneWidget);
        expect(find.text(loc.dating_restrictedHold), findsNothing);
        await open(t, appealed(review));
        expect(find.text(loc.dating_appealSentTesting), findsOneWidget);
        expect(find.text(loc.dating_appealSent), findsNothing);
      });
    }

    testWidgets(
      'staffed: the interim hold\'s 24 hours and the appeal\'s 7 days',
      (t) async {
        await open(t, hold('staffed'));
        expect(find.text(loc.dating_restrictedHold), findsOneWidget);
        await open(t, appealed('staffed'));
        expect(find.text(loc.dating_appealSent), findsOneWidget);
      },
    );
  });
}
````

- [ ] **Step 2: Run it to see it fail**

```bash
flutter test --no-pub test/features/dating/device/trip_test.dart 2>&1 | tr '\r' '\n' | grep -E "Error: (Error when reading|Couldn't)|Some tests failed" | head -2
```

Expected: a compile error naming `lib/features/dating/device/network_country.dart` (the first of the three files Step 3 creates), then `Some tests failed.`

- [ ] **Step 3: The network country, the data layer, the note and its page**

Create `lib/features/dating/device/network_country.dart` with exactly:

````dart
// Spec 2 W8b (§2.3): on Android, the mobile network's country
// (TelephonyManager.getNetworkCountryIso) through MainActivity's
// attune/device channel, for dating-device-check. No permission; nothing
// stored. The SIM's country is never sent (§2.3's computation uses the
// network's, R-75). iOS has no equivalent and answers null.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class NetworkCountry {
  static const channel = MethodChannel('attune/device');

  /// Upper-case ISO 3166-1 alpha-2, or null.
  static Future<String?> read({TargetPlatform? platform}) async {
    if ((platform ?? defaultTargetPlatform) != TargetPlatform.android) {
      return null;
    }
    try {
      final iso = await channel
          .invokeMethod<String>('networkCountryIso')
          .timeout(const Duration(seconds: 1));
      if (iso == null || !RegExp(r'^[A-Za-z]{2}$').hasMatch(iso)) return null;
      return iso.toUpperCase();
    } catch (_) {
      return null;
    }
  }
}
````

Create `lib/features/dating/device/dating_trip.dart` with exactly:

````dart
// Spec 2 W8b (§2.3, §2.5, §3.11; R-75..R-79): where the phone is, and the
// person's choice on a trip. The check goes to dating-device-check through
// the Dating-scoped client (its device header), with the network country
// on Android; the choice is set_dating_trip_choice. Every call is bounded;
// a failure answers failed or busy, never the error's text. The place's
// country is held in memory for the note's words, one entry per account.
import 'dart:async';

import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/data/dating_supabase_client.dart';
import 'package:attune/features/dating/device/network_country.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// §2.3: at most one check per 15 minutes while the section shows.
const kDatingDeviceCheckEvery = Duration(minutes: 15);

/// dating-device-check's answer.
class DatingDeviceCheck {
  const DatingDeviceCheck({
    required this.ok,
    this.trusted = false,
    this.away = false,
    this.noteCountry,
  });

  static const failed = DatingDeviceCheck(ok: false);

  final bool ok;
  final bool trusted;

  /// Dating isn't allowed where the phone is (the flag on).
  final bool away;

  /// While the place restricts: its country, for the note's words.
  final String? noteCountry;

  factory DatingDeviceCheck.fromJson(Object? raw) {
    if (raw is! Map || raw['ok'] != true) return failed;
    final note = raw['note'];
    final country = note is Map ? note['country'] : null;
    return DatingDeviceCheck(
      ok: true,
      trusted: raw['trusted'] == true,
      away: raw['away'] == true,
      noteCountry:
          country is String && RegExp(r'^[A-Z]{2}$').hasMatch(country)
              ? country
              : null,
    );
  }

  /// The home shown is from before a trip began or ended.
  bool disagreesWith(DatingHome home) =>
      away != (home.state == DatingHomeState.away) ||
      (away && home.trip == null) ||
      (noteCountry == null && home.trip != null);
}

abstract class DatingTripGateway {
  /// Where the phone is now; [networkCountry] on Android.
  Future<DatingDeviceCheck> check({String? networkCountry});

  /// §3.11: "Show it on this phone anyway" ([showHere]) or "Keep it
  /// hidden", under [key]; either marks the note seen for the trip.
  Future<DatingWrite> choose(String key, {required bool showHere});
}

typedef DatingDeviceCheckInvoke =
    Future<Object?> Function(Map<String, Object?> body);

class DatingTripRepository implements DatingTripGateway {
  DatingTripRepository(this._rpc, this._invoke);

  factory DatingTripRepository.of(DatingRpc rpc, SupabaseClient c) =>
      DatingTripRepository(
        rpc,
        (body) async =>
            (await c.functions.invoke('dating-device-check', body: body)).data,
      );

  final DatingRpc _rpc;
  final DatingDeviceCheckInvoke _invoke;

  static const timeout = Duration(seconds: 15);

  @override
  Future<DatingDeviceCheck> check({String? networkCountry}) async {
    try {
      return DatingDeviceCheck.fromJson(
        await _invoke({
          if (networkCountry != null) 'network_country': networkCountry,
        }).timeout(timeout),
      );
    } catch (_) {
      return DatingDeviceCheck.failed;
    }
  }

  @override
  Future<DatingWrite> choose(String key, {required bool showHere}) =>
      datingWrite(
        () => _rpc.call('set_dating_trip_choice', {
          'p_idempotency_key': key,
          'p_show_here': showHere,
        }),
      );
}

final datingTripGatewayProvider = Provider<DatingTripGateway>(
  (ref) => DatingTripRepository.of(
    ref.watch(datingRpcProvider),
    ref.watch(datingSupabaseClientProvider),
  ),
);

/// The network country's read (tests replace it).
final datingNetworkCountryProvider = Provider<Future<String?> Function()>(
  (ref) => NetworkCountry.read,
);

/// The place of [account]'s trip, from the last check (memory only, gone
/// with the section and the note).
final datingTripPlaceProvider = StateProvider.autoDispose
    .family<String?, String?>((ref, account) => null);

/// One device check; never throws (no gateway in a build without a
/// backend, no channel: a failed check changes nothing).
Future<DatingDeviceCheck> checkDatingDevice(WidgetRef ref) async {
  try {
    final network = await ref.read(datingNetworkCountryProvider)();
    return await ref
        .read(datingTripGatewayProvider)
        .check(networkCountry: network);
  } catch (_) {
    return DatingDeviceCheck.failed;
  }
}
````

Create `lib/features/dating/device/trip_note.dart` with exactly:

````dart
// Spec 2 W8b (§2.5, §3.11, §3.15; R-77, R-78; D8): the traveller's note
// and its four choices, in Me's Dating section once per trip and on its
// own page (/dating/away). Never a push, never animated. "Keep it hidden"
// and "Show it on this phone anyway" are the person's trip choice (the
// server's; showing changes only what this phone shows); "Pause Dating"
// and "Set a PIN" mark the note seen (Keep it hidden) and then do what
// they say. The place is named only while this phone's last check said
// so (memory only); otherwise the note says "while you're away".
// Offline every choice waits; busy and failures are calm lines; another
// account on the phone sees nothing of the last one's trip.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/device/dating_trip.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/lock/dating_unlock.dart'
    show setDatingLockInDating;
import 'package:attune/features/dating/routes/dating_root_back.dart';
import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The note's title for [trip].
String datingTripTitle(AppLocalizations loc, DatingTrip trip) =>
    trip.kind == DatingTripKind.away
        ? loc.dating_tripAwayTitle
        : loc.dating_tripSameGenderTitle;

/// The note's words for [trip], naming [country] when it is known.
String datingTripBody(AppLocalizations loc, DatingTrip trip, String? country) {
  final name = country == null ? null : datingCountryName(loc, country);
  return switch ((trip.kind, name)) {
    (DatingTripKind.away, final String n) => loc.dating_tripAwayBody(n),
    (DatingTripKind.away, null) => loc.dating_tripAwayBodyNoPlace,
    (DatingTripKind.sameGender, final String n) => loc
        .dating_tripSameGenderBody(n),
    (DatingTripKind.sameGender, null) => loc.dating_tripSameGenderBodyNoPlace,
  };
}

/// The note and its choices; [onDone] after a choice the server took.
class DatingTripNote extends ConsumerStatefulWidget {
  const DatingTripNote({
    super.key,
    required this.trip,
    required this.country,
    required this.onDone,
    this.card = true,
  });

  final DatingTrip trip;
  final String? country;
  final VoidCallback onDone;

  /// In Me's section (a card) or as a page's body.
  final bool card;

  @override
  ConsumerState<DatingTripNote> createState() => _DatingTripNoteState();
}

enum _TripAction { hide, show, pause, pin }

class _DatingTripNoteState extends ConsumerState<DatingTripNote> {
  final _keys = DatingActionKeys();
  _TripAction? _busy;
  String? _error;

  /// The account the choice was made for (D8).
  String? _account;

  @override
  void initState() {
    super.initState();
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (previous == next || !mounted) return;
      setState(() {
        _busy = null;
        _error = null;
      });
    });
  }

  Future<void> _run(_TripAction action) async {
    if (_busy != null) return;
    final account = ref.read(datingAccountProvider);
    _account = account;
    setState(() {
      _busy = action;
      _error = null;
    });
    final show = action == _TripAction.show;
    final choice = await ref
        .read(datingTripGatewayProvider)
        .choose(_keys.keyFor('trip', [account, show]), showHere: show);
    _keys.settle('trip', reason: choice.reason);
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    // No trip any more (it ended, or the flag is off): nothing to choose,
    // and the home says so when read again.
    if (!choice.ok && choice.reason != 'no_trip') {
      setState(() {
        _busy = null;
        _error = choice.reason;
      });
      return;
    }
    if (action == _TripAction.pause) {
      final paused = await ref
          .read(datingLifecycleGatewayProvider)
          .pause(_keys.keyFor('pause', account));
      _keys.settle('pause', error: paused.error);
      if (!mounted || ref.read(datingAccountProvider) != account) return;
      if (!paused.ok) {
        setState(() {
          _busy = null;
          _error =
              paused.error == DatingLifecycleError.busy ? 'busy' : 'failed';
        });
        return;
      }
    }
    if (action == _TripAction.pin) {
      await setDatingLockInDating(context, ref, true);
      if (!mounted || ref.read(datingAccountProvider) != account) return;
    }
    setState(() => _busy = null);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final account = ref.watch(datingAccountProvider);
    final locked = ref.watch(datingLockProvider).valueOrNull ?? false;
    final trip = widget.trip;
    final error = _account == account ? _error : null;
    VoidCallback? act(_TripAction a) =>
        online && _busy == null ? () => _run(a) : null;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            datingTripTitle(loc, trip),
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          datingTripBody(loc, trip, widget.country),
          key: const ValueKey('dating_trip_body'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.md),
        if (!online) DatingCalmLine(loc.dating_offline),
        if (error == 'busy') DatingCalmLine(loc.dating_busy),
        if (error != null && error != 'busy')
          FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
        FlowPrimaryButton(
          key: const ValueKey('dating_trip_hide'),
          label: loc.dating_tripKeepHidden,
          busy: _busy == _TripAction.hide,
          onPressed: act(_TripAction.hide),
        ),
        if (!trip.showHere) ...[
          const SizedBox(height: Spacing.sm),
          FlowSecondaryButton(
            key: const ValueKey('dating_trip_show'),
            label: loc.dating_tripShowAnyway,
            busy: _busy == _TripAction.show,
            onPressed: act(_TripAction.show),
          ),
        ],
        const SizedBox(height: Spacing.sm),
        FlowSecondaryButton(
          key: const ValueKey('dating_trip_pause'),
          label: loc.dating_tripPause,
          busy: _busy == _TripAction.pause,
          onPressed: act(_TripAction.pause),
        ),
        if (!locked) ...[
          const SizedBox(height: Spacing.sm),
          FlowSecondaryButton(
            key: const ValueKey('dating_trip_pin'),
            label: loc.dating_tripSetPin,
            busy: _busy == _TripAction.pin,
            onPressed: act(_TripAction.pin),
          ),
        ],
      ],
    );
    if (!widget.card) return content;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: content,
        ),
      ),
    );
  }
}

/// §3.14 /dating/away: the note on its own page, for this account's trip;
/// with no trip (it ended, another account) the gone line.
class DatingAwayScreen extends ConsumerWidget {
  const DatingAwayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final account = ref.watch(datingAccountProvider);
    final home = ref.watch(datingHomeProvider(account));
    final trip = home.hasError ? null : home.valueOrNull?.trip;
    final Widget body;
    if (home.isLoading && !home.hasValue) {
      body = const SizedBox(height: 96);
    } else if (trip == null) {
      body = DatingCalmLine(loc.dating_cardGone);
    } else {
      body = DatingTripNote(
        key: ValueKey('dating_trip_page_$account'),
        trip: trip,
        country: ref.watch(datingTripPlaceProvider(account)),
        card: false,
        onDone: () {
          ref.invalidate(datingHomeProvider(account));
          final back = datingRootBackButton(context);
          if (back == null && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
      );
    }
    return AllowLargeText(
      child: Scaffold(
        appBar: AppBar(
          leading: datingRootBackButton(context),
          title: Text(loc.flow_slotDatingTitle),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.md),
            child: KeyedSubtree(key: ValueKey(account), child: body),
          ),
        ),
      ),
    );
  }
}
````

- [ ] **Step 4: The copy**

Create `.superpowers/sdd/2026-11-22-spec2-w8/arb_fragment_T7.txt` with exactly:

````text
  "dating_tripAwayTitle": "Dating is hidden while you're away",
  "@dating_tripAwayTitle": {"description": "Spec 2 §3.11 the traveller's note where Dating isn't allowed (in-app, once per trip, never a push; never animated)."},
  "dating_tripAwayBody": "While you're in {country}, your Dating section is hidden on this phone and nobody new is introduced to you. Your conversations are safe and come back when you leave.",
  "@dating_tripAwayBody": {"description": "Spec 2 §3.11 the note's words; {country} is where the phone is.", "placeholders": {"country": {"type": "String"}}},
  "dating_tripAwayBodyNoPlace": "While you're away, your Dating section is hidden on this phone and nobody new is introduced to you. Your conversations are safe and come back when you leave.",
  "@dating_tripAwayBodyNoPlace": {"description": "Spec 2 §3.11 the note's words when this phone doesn't know the place yet (the check hasn't answered). Plan copy (the spec's line without the place)."},
  "dating_tripSameGenderTitle": "Some introductions are paused while you're away",
  "@dating_tripSameGenderTitle": {"description": "Spec 2 §3.11 the traveller's note where same-gender introductions aren't allowed. LGBTQ+ safety reviewer."},
  "dating_tripSameGenderBody": "While you're in {country}, introductions between people of the same gender are switched off for you, and the ones you have are hidden on this phone. They come back when you leave.",
  "@dating_tripSameGenderBody": {"description": "Spec 2 §3.11 the note's words; {country} is where the phone is. LGBTQ+ safety reviewer.", "placeholders": {"country": {"type": "String"}}},
  "dating_tripSameGenderBodyNoPlace": "While you're away, introductions between people of the same gender are switched off for you, and the ones you have are hidden on this phone. They come back when you leave.",
  "@dating_tripSameGenderBodyNoPlace": {"description": "Spec 2 §3.11 the same, without the place. Plan copy (the spec's line without the place). LGBTQ+ safety reviewer."},
  "dating_tripKeepHidden": "Keep it hidden",
  "@dating_tripKeepHidden": {"description": "Spec 2 §3.11 the default choice."},
  "dating_tripShowAnyway": "Show it on this phone anyway",
  "@dating_tripShowAnyway": {"description": "Spec 2 §3.11 changes only what this phone shows; nobody new is introduced."},
  "dating_tripPause": "Pause Dating",
  "@dating_tripPause": {"description": "Spec 2 §3.11."},
  "dating_tripSetPin": "Set a PIN",
  "@dating_tripSetPin": {"description": "Spec 2 §3.11 turns on the Dating lock (the Safety PIN first if there is none); hidden when the lock is already on."},
  "dating_tripMore": "What this means",
  "@dating_tripMore": {"description": "Spec 2 §3.1 away: the section's link to the note's page. Plan copy."},
  "dating_appealSentTesting": "Appeal sent. A different person from the one who made the first decision will look at it.",
  "@dating_appealSentTesting": {"description": "Spec 2 §3.7 an appeal sent while nobody reviews yet (W7 carry M-6: no review time in testing). Plan copy (the W7 final reviewer's line). DV reviewer."}
````

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py $D/arb_fragment_T7.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package > /dev/null 2>&1; echo "gen-l10n exit=$?"
```

Expected: `added 12 keys`; `gen-l10n exit=0`.

- [ ] **Step 5: The home, the route, the section, the restricted screen, the network country on Android, the shells and the audit list**

Create `.superpowers/sdd/2026-11-22-spec2-w8/edit_app_T7.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W8b Task 7 (§2.3, §2.5, §3.1 away, §3.11, §3.14 /dating/away,
# §3.15; R-75..R-79; W7 carry M-6): the home reads the away state, the trip
# and the plain-icon offer; the section runs the device check (once per 15
# minutes while it shows, only for someone with Dating data), shows the
# away card and the trip's note; /dating/away is the note's own page; the
# restricted screen drops its review-time sentences in testing.
# Formatter-style edits (W3a-W7 files, never formatted).
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-22-spec2-w8/anchor.py')['edit']

edit('lib/features/dating/data/dating_home.dart', [
    ("""  notStarted('not_started'),
  setupInProgress('setup_in_progress');
""", """  notStarted('not_started'),
  setupInProgress('setup_in_progress'),
  // Spec 2 W8b (§2.1 gate 7, §3.1): Dating isn't allowed where the person is.
  away('away');
"""),
    ("""class DatingHome {
  const DatingHome({
""", """/// Spec 2 W8b (§2.5, §3.11): what a trip hides, from get_dating_home.
enum DatingTripKind { away, sameGender }

/// Spec 2 W8b (§3.11): the trip the home names: its kind, whether its
/// in-app note is still to show (once per trip, never a push), and the
/// person's own "Show it on this phone anyway". Null: no trip.
class DatingTrip {
  const DatingTrip({
    required this.kind,
    this.note = false,
    this.showHere = false,
  });

  final DatingTripKind kind;
  final bool note;
  final bool showHere;

  static DatingTrip? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = switch (raw['kind']) {
      'away' => DatingTripKind.away,
      'same_gender' => DatingTripKind.sameGender,
      _ => null,
    };
    if (kind == null) return null;
    return DatingTrip(
      kind: kind,
      note: raw['note'] == true,
      showHere: raw['show_here'] == true,
    );
  }
}

class DatingHome {
  const DatingHome({
"""),
    ("""    this.appealAccepted = false,
  });
""", """    this.appealAccepted = false,
    this.trip,
    this.offerPlainIcon = false,
  });
"""),
    ("""  /// Spec 2 W7a (§3.7): an appeal was accepted in the last 7 days.
  final bool appealAccepted;
""", """  /// Spec 2 W7a (§3.7): an appeal was accepted in the last 7 days.
  final bool appealAccepted;

  /// Spec 2 W8b (§3.11): the trip, when the place restricts.
  final DatingTrip? trip;

  /// Spec 2 W8b (§3.2 D13, A-11): the effective tier is 1 or 2.
  final bool offerPlainIcon;
"""),
    ("""      appealAccepted: json['appeal_accepted'] == true,
    );
""", """      appealAccepted: json['appeal_accepted'] == true,
      trip: DatingTrip.fromJson(json['trip']),
      offerPlainIcon: json['offer_plain_icon'] == true,
    );
"""),
], 'T7 home')

edit('lib/features/dating/routes/dating_routes.dart', [
    ("""import 'package:attune/features/dating/chat/plan_meet_screen.dart';
""", """import 'package:attune/features/dating/chat/plan_meet_screen.dart';
import 'package:attune/features/dating/device/trip_note.dart';
"""),
    ("""  /// Spec 2 W7a (§3.7): the restricted, hold and age-check screen.
  static const restricted = '/dating/restricted';
""", """  /// Spec 2 W7a (§3.7): the restricted, hold and age-check screen.
  static const restricted = '/dating/restricted';

  /// Spec 2 W8b (§3.11, §3.14): the traveller's note and choices.
  static const away = '/dating/away';
"""),
    ("""    (s) => const DatingRestrictedScreen(),
    back: datingMeLocation,
  ),
];""", """    (s) => const DatingRestrictedScreen(),
    back: datingMeLocation,
  ),
  // Spec 2 W8b (§3.11, §3.15): nothing here moves; alone, back is Me.
  datingRoute(
    DatingPaths.away,
    'datingAway',
    signedIn,
    (s) => const DatingAwayScreen(),
    back: datingMeLocation,
  ),
];"""),
], 'T7 routes')

edit('lib/features/dating/section/dating_section.dart', [
    ("""import 'package:attune/features/dating/data/dating_rpc.dart';
""", """import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/device/dating_trip.dart';
import 'package:attune/features/dating/device/trip_note.dart';
"""),
    ("""  /// Final client fix (M-4): the account whose email app didn't open from
  /// Contact support here (said in the app's own words, with the address).
  String? _noMailFor;
""", """  /// Final client fix (M-4): the account whose email app didn't open from
  /// Contact support here (said in the app's own words, with the address).
  String? _noMailFor;

  /// Spec 2 W8b (§2.3): when this section last checked where the phone is,
  /// per account (memory only; the server keeps one record per 15 minutes
  /// whatever the app sends).
  final _checkedAt = <String, DateTime>{};
"""),
    ("""        _noMailFor = null;
      });
    });
  }
""", """        _noMailFor = null;
      });
    });
    // Spec 2 W8b (§2.3): each good home read may check where the phone is.
    ref.listenManual<AsyncValue<DatingHome>>(
      datingHomeProvider(ref.read(datingAccountProvider)),
      (_, next) => _maybeCheck(next.valueOrNull),
    );
  }

  /// Spec 2 W8b (§2.3, §2.5): someone with Dating data, on a phone Dating
  /// can use, checks where they are at most once per 15 minutes while the
  /// section shows; when the answer disagrees with the home shown (a trip
  /// began or ended), the home is read again once.
  Future<void> _maybeCheck(DatingHome? home) async {
    final account = ref.read(datingAccountProvider);
    if (account == null || home == null || !home.hasData) return;
    if (const {
      DatingHomeState.featureUnavailable,
      DatingHomeState.countryClosed,
      DatingHomeState.regionClosed,
      DatingHomeState.reverifyDevice,
    }.contains(home.state)) {
      return;
    }
    final last = _checkedAt[account];
    final now = DateTime.now();
    if (last != null && now.difference(last) < kDatingDeviceCheckEvery) return;
    _checkedAt[account] = now;
    final answer = await checkDatingDevice(ref);
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    ref.read(datingTripPlaceProvider(account).notifier).state =
        answer.noteCountry;
    if (answer.ok && answer.disagreesWith(home)) _refresh();
  }
"""),
    ("""    final data = home.hasError ? null : home.valueOrNull;
    final Object key;
    final Widget child;
    if (data != null) {
      key = data.state;
      child = _card(context, loc, data, online);
""", """    final data = home.hasError ? null : home.valueOrNull;
    // Spec 2 W8b (§3.11): the place of a trip, held while the section shows
    // (watched from the first frame, so a check's answer is never lost).
    final place = ref.watch(datingTripPlaceProvider(account));
    final Object key;
    final Widget child;
    if (data != null) {
      key = data.state;
      // Spec 2 W8b (§3.11): the trip's note, once per trip, above the card
      // (away, it is the card).
      final trip = data.trip;
      child =
          trip != null && trip.note
              ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DatingTripNote(
                    key: ValueKey('dating_trip_note_$account'),
                    trip: trip,
                    country: place,
                    onDone: _refresh,
                  ),
                  if (data.state != DatingHomeState.away)
                    _card(context, loc, data, online),
                ],
              )
              : _card(context, loc, data, online);
"""),
    ("""      case DatingHomeState.paused:
        return _paused(context, loc, h, online, settings);
""", """      case DatingHomeState.paused:
        return _paused(context, loc, h, online, settings);
      // Spec 2 W8b (§3.1, §3.11): hidden while away; shown on this phone
      // anyway, the conversations stay one tap away.
      case DatingHomeState.away:
        return _SectionCard(
          title: loc.flow_slotDatingTitle,
          lines: [loc.dating_sectionAway],
          onTap: () => context.push(DatingPaths.away),
          children: [
            FlowTextLink(
              label: loc.dating_tripMore,
              alignment: AlignmentDirectional.centerStart,
              onPressed: () => context.push(DatingPaths.away),
            ),
            if (h.trip?.showHere ?? false)
              FlowSecondaryButton(
                label: loc.dating_chatsTitle,
                onPressed: () => context.push(DatingPaths.chats),
              ),
            if (settings != null) settings,
          ],
        );
"""),
], 'T7 section')

edit('lib/features/dating/report/dating_report.dart', [
    ("""    this.restriction,
    this.appealAccepted = false,
  });

  static const none = DatingRestrictionRead(ok: true);
""", """    this.restriction,
    this.appealAccepted = false,
    this.staffed = true,
  });

  static const none = DatingRestrictionRead(ok: true);
"""),
    ("""  final DatingRestriction? restriction;
  final bool appealAccepted;

  /// Task 2 fix round:""", """  final DatingRestriction? restriction;
  final bool appealAccepted;

  /// Spec 2 W8b (W7 carry M-6): a person reviews now (the server's
  /// `review: staffed`). Read from the server, anything else (testing, or
  /// no answer) is false and the screen makes no review-time promise; a
  /// read built in code (W7's tests) keeps W7's staffed lines.
  final bool staffed;

  /// Task 2 fix round:"""),
    ("""      restriction: DatingRestriction.fromJson(raw['restriction']),
      appealAccepted: raw['appeal_accepted'] == true,
    );
""", """      restriction: DatingRestriction.fromJson(raw['restriction']),
      appealAccepted: raw['appeal_accepted'] == true,
      staffed: raw['review'] == 'staffed',
    );
"""),
], 'T7 M-6 model')

edit('lib/features/dating/report/restricted_screen.dart', [
    ("""          _Para(
            r.interimHold
                ? loc.dating_restrictedHold
                : loc.dating_restrictedHoldPlain,
""", """          // Spec 2 W8b (W7 carry M-6): and only while a person reviews.
          _Para(
            r.interimHold && read.staffed
                ? loc.dating_restrictedHold
                : loc.dating_restrictedHoldPlain,
"""),
    ("""        _Para(
          loc.dating_appealSent,
          key: const ValueKey('dating_restricted_appeal_state'),
""", """        // Spec 2 W8b (W7 carry M-6): no review time in testing.
        _Para(
          read.staffed ? loc.dating_appealSent : loc.dating_appealSentTesting,
          key: const ValueKey('dating_restricted_appeal_state'),
"""),
], 'T7 M-6 screen')
````

Create `.superpowers/sdd/2026-11-22-spec2-w8/edit_native_T7.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W8b Task 7 (§2.3; R-75): Android's attune/device channel gains the
# mobile network's country, for dating-device-check (no permission; the
# SIM's country stays the phone step's only). Exact edit; the device check
# is the owner's (§7.7).
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-22-spec2-w8/anchor.py')['edit']

edit('android/app/src/main/kotlin/com/barsopus/attune/MainActivity.kt', [
    ("""                        result.success(
                            if (iso != null && iso.length == 2) iso.uppercase() else null,
                        )
                    }
                    else -> result.notImplemented()
""", """                        result.success(
                            if (iso != null && iso.length == 2) iso.uppercase() else null,
                        )
                    }
                    // Spec 2 W8b (§2.3): the network's country, for Dating's
                    // device check (the place, never stored by the phone).
                    "networkCountryIso" -> {
                        val telephony =
                            getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
                        val iso = telephony?.networkCountryIso
                        result.success(
                            if (iso != null && iso.length == 2) iso.uppercase() else null,
                        )
                    }
                    else -> result.notImplemented()
"""),
], 'T7 Android')
````

Create `.superpowers/sdd/2026-11-22-spec2-w8/edit_tests_T7.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W8b Task 7: every Dating shell fakes the device check (no test
# reaches the edge function; the network country is none). Exact edits
# (W3's test support file).
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-22-spec2-w8/anchor.py')['edit']

S = 'test/features/dating/support/dating_shell.dart'
edit(S, [
    ("""import 'dating_fakes.dart';
import 'dating_verify_fakes.dart';
""", """import 'dating_fakes.dart';
import 'dating_trip_fakes.dart';
import 'dating_verify_fakes.dart';
"""),
    ("""        // Spec 2 W6a: the chat is faked unless a test says otherwise.
        ...datingChatOverrides(FakeDatingChat()),
        ...datingKitOverrides,
        ...overrides,
""", """        // Spec 2 W6a: the chat is faked unless a test says otherwise.
        ...datingChatOverrides(FakeDatingChat()),
        ...datingKitOverrides,
        // Spec 2 W8b: the device check is faked unless a test says otherwise.
        ...datingTripOverrides(FakeDatingTrip()),
        ...overrides,
"""),
    ("""  datingAbroadGatewayProvider.overrideWithValue(FakeAbroad()),
  ...datingChatOverrides(FakeDatingChat()),
  ...datingKitOverrides,
];
""", """  datingAbroadGatewayProvider.overrideWithValue(FakeAbroad()),
  ...datingChatOverrides(FakeDatingChat()),
  ...datingKitOverrides,
  // Spec 2 W8b: the device check is faked.
  ...datingTripOverrides(FakeDatingTrip()),
];
"""),
    ("""  datingLockAccountProvider.overrideWith((ref) => Stream.value(account)),
  datingOnlineProvider.overrideWith((ref) => Stream.value(true)),
];""", """  datingLockAccountProvider.overrideWith((ref) => Stream.value(account)),
  datingOnlineProvider.overrideWith((ref) => Stream.value(true)),
  // Spec 2 W8b: the device check is faked.
  ...datingTripOverrides(FakeDatingTrip()),
];"""),
], 'T7 shell')
````

Create `.superpowers/sdd/2026-11-22-spec2-w8/edit_tests_T7b.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W8b Task 7: /dating/away is audited at 2.0 (its goldens and the
# large-text audit over test/features/dating/device). Exact edit.
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-22-spec2-w8/anchor.py')['edit']
edit('test/architecture/text_scale_routes_test.dart', [
    ("""  // Spec 2 W7a (§3.7): the restricted screen.
  'datingRestricted',
""", """  // Spec 2 W7a (§3.7): the restricted screen.
  'datingRestricted',
  // Spec 2 W8b (§3.11): the traveller's note.
  'datingAway',
"""),
], 'T7 audit list')
````

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
dart format lib/features/dating/device/network_country.dart lib/features/dating/device/dating_trip.dart lib/features/dating/device/trip_note.dart test/features/dating/support/dating_trip_fakes.dart test/features/dating/device/trip_test.dart
python3 -I $D/edit_app_T7.py
python3 -I $D/edit_native_T7.py
python3 -I $D/edit_tests_T7.py
python3 -I $D/edit_tests_T7b.py
flutter analyze --no-pub lib/features/dating test/features/dating 2>&1 | tail -1
```

Expected: `Formatted 5 files (0 changed)`; `…dating_home.dart: 5 edit(s) (T7 home)`, `…dating_routes.dart: 3 edit(s) (T7 routes)`, `…dating_section.dart: 5 edit(s) (T7 section)`, `…dating_report.dart: 3 edit(s) (T7 M-6 model)`, `…restricted_screen.dart: 2 edit(s) (T7 M-6 screen)`, `…MainActivity.kt: 1 edit(s) (T7 Android)`, `…dating_shell.dart: 4 edit(s) (T7 shell)`, `…text_scale_routes_test.dart: 1 edit(s) (T7 audit list)`; `No issues found!`

- [ ] **Step 6: The goldens, the tests, the large-text audit**

```bash
flutter test --no-pub --update-goldens test/features/dating/device/trip_test.dart --plain-name goldens > /dev/null 2>&1; ls test/features/dating/device/goldens | grep -c dating_away
flutter test --no-pub test/features/dating/device/trip_test.dart test/architecture/text_scale_routes_test.dart 2>&1 | tr '\r' '\n' | grep -oE '\+[0-9]+( -[0-9]+)?: (All tests passed!|Some tests failed\.)' | tail -1
python3 scripts/large_text_audit.py --scale 2.0 test/features/dating/device 2>&1 | tail -1
```

Expected: `4`; `+30: All tests passed!`; `SCALE 2.0: 0 site(s) to fix, 0 listed apart`.

- [ ] **Step 7: Every Dating, Me and settings test still passes (the section and the shell changed)**

```bash
flutter test --no-pub test/features/dating test/features/me test/architecture test/core/notifications test/app/documentations 2>&1 | tr '\r' '\n' | grep -E '\[E\]|: (All tests passed!|Some tests failed\.)' | tail -3
```

Expected: `+1864 -1: Some tests failed.`, the one failure `chat_screen_test.dart` "Swap: disabled before 72 hours…" (it fails at `296b7216` too: its fixed clock is now in the past; Global Constraints, gate 2). Any other failure is this task's.

- [ ] **Step 8: The mutants**

Create `.superpowers/sdd/2026-11-22-spec2-w8/mut_T7_dart.py` with exactly:

````python
# Spec 2 W8b Task 7: Dart mutants (dmut.py, in a private copy).
T = ['test/features/dating/device/trip_test.dart']
S = 'lib/features/dating/section/dating_section.dart'
N = 'lib/features/dating/device/trip_note.dart'
R = 'lib/features/dating/device/dating_trip.dart'
X = 'lib/features/dating/report/restricted_screen.dart'
MUTS = {
    'check_without_data': (S, '    if (account == null || home == null || !home.hasData) return;\n',
                           '    if (account == null || home == null) return;\n', T),
    'check_every_time': (S, '    if (last != null && now.difference(last) < kDatingDeviceCheckEvery) return;\n', '', T),
    'no_refresh_on_change': (S, '    if (answer.ok && answer.disagreesWith(home)) _refresh();\n', '', T),
    'place_dropped': (S, '        answer.noteCountry;\n', '        null;\n', T),
    'note_never_shown': (S, '          trip != null && trip.note\n', '          trip != null && trip.note && false\n', T),
    'away_card_no_chats': (S, '            if (h.trip?.showHere ?? false)\n', '            if (false)\n', T),
    'network_not_sent': (R, '        .check(networkCountry: network);\n', '        .check();\n', T),
    'never_disagrees': (R, '  bool disagreesWith(DatingHome home) =>\n',
                        '  bool disagreesWith(DatingHome home) => false;\n  // ignore: unused_element\n  bool _was(DatingHome home) =>\n', T),
    'show_is_hide': (N, '    final show = action == _TripAction.show;\n', '    const show = false;\n', T),
    'pause_never_pauses': (N, '    if (action == _TripAction.pause) {\n', '    if (false) {\n', T),
    'no_trip_is_error': (N, "    if (!choice.ok && choice.reason != 'no_trip') {\n", '    if (!choice.ok) {\n', T),
    'offline_choices_open': (N, '        online && _busy == null ? () => _run(a) : null;\n', '        _busy == null ? () => _run(a) : null;\n', T),
    'trip_unread': ('lib/features/dating/data/dating_home.dart', "      trip: DatingTrip.fromJson(json['trip']),\n", '', T),
    'hold_promise_in_testing': (X, '            r.interimHold && read.staffed\n', '            r.interimHold\n', T),
    'appeal_promise_in_testing': (X, '          read.staffed ? loc.dating_appealSent : loc.dating_appealSentTesting,\n',
                                  '          loc.dating_appealSent,\n', T),
    'staffed_unread': ('lib/features/dating/report/dating_report.dart', "      staffed: raw['review'] == 'staffed',\n", '', T),
}
````

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
python3 -I $D/dmut.py $D/mut_T7_dart.py | tee $D/mut_T7_dart.txt | tail -1
```

Expected: `16/16 killed`.

- [ ] **Step 9: Record the tree (do not commit).**

### Task 8: The plain app icon for everyone: Android aliases, the iOS alternate icon, Settings → App icon, the D13 offer (§3.2 D13, §3.12, §6.7, §7.4 icon test, §7.7; A-11; R-80)

**Files:**
- Create: `lib/features/dating/device/app_icon.dart`, `lib/features/dating/settings/app_icon_screen.dart`, `android/app/src/main/res/{values/plain_icon.xml, drawable/ic_launcher_plain_foreground.xml, mipmap-anydpi-v26/ic_launcher_plain.xml, mipmap/ic_launcher_plain.xml}`, `ios/Runner/Assets.xcassets/IconPlain.appiconset/{Contents.json, IconPlain-1024.png}`, `test/features/dating/device/app_icon_test.dart` and `goldens/dating_app_icon.*.png`, `$D/{make_plain_icon.py, arb_fragment_T8.txt, edit_native_T8.py, edit_app_T8.py, edit_tests_T8.py, mut_T8_dart.py}`
- Modify: `AndroidManifest.xml`, `MainActivity.kt`, `AppDelegate.swift`, `project.pbxproj`, `dating_routes.dart` (`/dating/app-icon`), `dating_settings_screen.dart` (the row), `setup/ready_step.dart` (the offer), the manual (`dating_app_icon`), `dating_settings_rows_test.dart` (the order), `text_scale_routes_test.dart` (`datingAppIcon`), `lib/i10n/app_en.arb` + generated; regenerates `test/features/dating/settings/goldens/dating_settings_bottom.*.png`
- Test: `test/features/dating/device/app_icon_test.dart`

**Interfaces:**
- Consumes: Task 2's `attune/safety` handlers (the anchors), Task 7's routes and the home's `offerPlainIcon`, Task 3's manual text.
- Produces: `AppIconChoice`, `AppIconControl`, `PlatformAppIcon`, `appIconControlProvider`, `appIconProvider`, `DatingAppIconScreen`, `DatingPaths.appIcon`; native `appIcon → default|plain|unsupported`, `setAppIcon(default|plain) → bool`.

- [ ] **Step 1: Write the failing test**

Create `test/features/dating/device/app_icon_test.dart` with exactly:

````dart
// Spec 2 W8b (§3.2 D13, §3.12, §6.7, §7.4 icon widget test, §7.7; A-11;
// R-80): the plain app icon for everyone. The channel maps the phone's
// answer and never throws; the page shows the icon on the home screen,
// changes it (offline too), says what iOS and Android do, and says so when
// the phone refuses or can't; Dating settings lists App icon for everyone;
// D13 offers it only in Tier 1/2; quick exit and sign-out never touch it
// (protective, C-2). The native side is pinned by its text (the change
// itself is a device check, §7.7).
import 'dart:io';

import 'package:attune/app/device_wipes.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/device/app_icon.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/settings/app_icon_screen.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/ready_step.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_setup_fakes.dart';
import '../support/dating_shell.dart';

final loc = AppLocalizationsEn();
const _channel = MethodChannel('attune/safety');

class FakeAppIcon implements AppIconControl {
  FakeAppIcon([this.icon = AppIconChoice.attune]);

  AppIconChoice? icon;
  bool refuse = false;
  final chosen = <AppIconChoice>[];

  @override
  Future<AppIconChoice?> current() async => icon;

  @override
  Future<bool> choose(AppIconChoice choice) async {
    chosen.add(choice);
    if (refuse) return false;
    icon = choice;
    return true;
  }
}

void main() {
  group('the channel', () {
    final calls = <MethodCall>[];
    Object? answer;
    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            calls.add(call);
            if (answer is Exception) throw answer!;
            return answer;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, null),
      );
    });

    test('reads the icon on the home screen', () async {
      const icon = PlatformAppIcon();
      answer = 'plain';
      expect(await icon.current(), AppIconChoice.plain);
      answer = 'default';
      expect(await icon.current(), AppIconChoice.attune);
      answer = 'unsupported';
      expect(await icon.current(), isNull);
      answer = PlatformException(code: 'x');
      expect(await icon.current(), isNull);
      expect(calls.map((c) => c.method).toSet(), {'appIcon'});
    });

    test('changes it, and a refusal or an error is false', () async {
      const icon = PlatformAppIcon();
      answer = true;
      expect(await icon.choose(AppIconChoice.plain), isTrue);
      expect(calls.last.arguments, 'plain');
      expect(await icon.choose(AppIconChoice.attune), isTrue);
      expect(calls.last.arguments, 'default');
      answer = false;
      expect(await icon.choose(AppIconChoice.plain), isFalse);
      answer = PlatformException(code: 'x');
      expect(await icon.choose(AppIconChoice.plain), isFalse);
    });
  });

  group('the page', () {
    Future<FakeAppIcon> open(
      WidgetTester t, {
      FakeAppIcon? fake,
      bool online = true,
    }) async {
      final icon = fake ?? FakeAppIcon();
      await pumpDatingShell(
        t,
        initial: DatingPaths.appIcon,
        online: online,
        overrides: [appIconControlProvider.overrideWithValue(icon)],
      );
      return icon;
    }

    RadioListTile<AppIconChoice> tile(WidgetTester t, AppIconChoice c) =>
        t.widget(find.byKey(ValueKey('dating_app_icon_${c.name}')));

    testWidgets('the icon now; Plain changes it, offline too; Attune back', (
      t,
    ) async {
      final icon = await open(t, online: false);
      expect(find.text(loc.dating_appIconIntro), findsOneWidget);
      expect(tile(t, AppIconChoice.attune).groupValue, AppIconChoice.attune);
      await tapInReach(t, find.text(loc.dating_appIconPlain));
      await t.pumpAndSettle();
      expect(icon.chosen, [AppIconChoice.plain]);
      expect(tile(t, AppIconChoice.plain).groupValue, AppIconChoice.plain);
      await tapInReach(t, find.text(loc.dating_appIconAttune));
      await t.pumpAndSettle();
      expect(icon.chosen, [AppIconChoice.plain, AppIconChoice.attune]);
      expect(find.text(loc.dating_appIconFailed), findsNothing);
    });

    testWidgets('Android says the app may close; iOS that it asks', (t) async {
      await open(t);
      expect(find.text(loc.dating_appIconAndroid), findsOneWidget);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await open(t);
        expect(find.text(loc.dating_appIconIos), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a refusal says so and keeps the icon as it was', (t) async {
      final icon = await open(t, fake: FakeAppIcon()..refuse = true);
      await tapInReach(t, find.text(loc.dating_appIconPlain));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_appIconFailed), findsOneWidget);
      expect(tile(t, AppIconChoice.attune).groupValue, AppIconChoice.attune);
      expect(icon.icon, AppIconChoice.attune);
    });

    testWidgets('a phone that can\'t change it says so, no choices', (t) async {
      await open(t, fake: FakeAppIcon(null));
      expect(find.text(loc.dating_appIconUnsupported), findsOneWidget);
      expect(find.text(loc.dating_appIconPlain), findsNothing);
    });

    testWidgets('goldens at 1.0, 1.3, 2.0 and RTL; the three guidelines', (
      t,
    ) async {
      Widget screen() => const DatingAppIconScreen();
      final overrides = [
        ...datingShellOverrides(),
        appIconControlProvider.overrideWithValue(FakeAppIcon()),
      ];
      await expectFlowGoldens(
        t,
        'dating_app_icon',
        screen,
        overrides: overrides,
      );
      await pumpFlowScreen(t, screen, overrides: overrides);
      await expectFlowGuidelines(t);
    });
  });

  testWidgets('Dating settings lists App icon for everyone and opens it', (
    t,
  ) async {
    await pumpDatingShell(
      t,
      initial: DatingPaths.settings,
      overrides: [
        appIconControlProvider.overrideWithValue(
          FakeAppIcon(AppIconChoice.plain),
        ),
      ],
    );
    final row = find.text(loc.dating_appIconTitle);
    await t.ensureVisible(row);
    await t.pumpAndSettle();
    expect(find.text(loc.dating_appIconPlain), findsOneWidget);
    await tapInReach(t, row);
    await t.pumpAndSettle();
    expect(find.byType(DatingAppIconScreen), findsOneWidget);
  });

  group('D13', () {
    Future<void> ready(WidgetTester t, {required bool offer}) async {
      await t.pumpWidget(const SizedBox());
      await pumpFlowScreen(
        t,
        () => DatingReadyStep(
          nav: DatingStepNav(next: (_) {}, back: () {}, toMe: () {}),
        ),
        overrides: [
          ...datingShellOverrides(
            home: FakeDatingHomeGateway(
              home: DatingHome(
                state: DatingHomeState.setupInProgress,
                firstDropAt: DateTime.utc(2026, 12, 1, 19),
                offerPlainIcon: offer,
              ),
            ),
          ),
          datingSetupGatewayProvider.overrideWithValue(
            FakeDatingSetupGateway(
              profile: const DatingMyProfile(dropTime: '19:00:00'),
            ),
          ),
        ],
      );
      await t.pumpAndSettle();
    }

    testWidgets('the plain-icon offer only in Tier 1/2', (t) async {
      await ready(t, offer: false);
      expect(find.text(loc.dating_readyPlainIcon), findsNothing);
      await ready(t, offer: true);
      expect(find.text(loc.dating_readyPlainIcon), findsOneWidget);
      expect(find.text(loc.dating_readyPlainIconButton), findsOneWidget);
    });
  });

  testWidgets('quick exit and sign-out never touch the icon', (t) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call.method);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null),
    );
    final registry = DeviceWipeRegistry();
    registerDeviceWipes(registry);
    await registry.run(WipeMoment.quickExit);
    await registry.run(WipeMoment.signOut);
    expect(calls.where((m) => m.contains('Icon')), isEmpty);
    for (final e in registry.entries) {
      expect(e.keys.where((k) => k.contains('icon')), isEmpty, reason: e.id);
    }
  });

  test('the native side: two launcher aliases, MainActivity found by the '
      'tool but listed by no launcher, the icon methods, iOS\'s alternate '
      'icon', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:name=".IconDefault"'));
    expect(manifest, contains('android:name=".IconPlain"'));
    expect(RegExp('android:enabled="false"').allMatches(manifest).length, 1);
    expect(manifest, contains('<data android:scheme="attune-tool-launch"/>'));
    expect(
      RegExp(r'IconPlain[\s\S]*?</activity-alias>').stringMatch(manifest),
      contains('android.intent.category.LAUNCHER'),
    );
    expect(manifest.toLowerCase(), isNot(contains('dating')));
    final kt =
        File(
          'android/app/src/main/kotlin/com/barsopus/attune/MainActivity.kt',
        ).readAsStringSync();
    expect(kt, contains('"appIcon" ->'));
    expect(kt, contains('"setAppIcon" ->'));
    expect(kt, contains('PackageManager.DONT_KILL_APP'));
    final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(swift, contains('setAlternateIconName(name)'));
    expect(swift, contains('"IconPlain"'));
    final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(
      'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = IconPlain;'
          .allMatches(pbx)
          .length,
      3,
    );
    expect(
      File(
        'ios/Runner/Assets.xcassets/IconPlain.appiconset/IconPlain-1024.png',
      ).existsSync(),
      isTrue,
    );
  });
}
````

- [ ] **Step 2: Run it to see it fail**

```bash
flutter test --no-pub test/features/dating/device/app_icon_test.dart 2>&1 | tr '\r' '\n' | grep -E "Error: (Error when reading|Couldn't)|Some tests failed" | head -2
```

Expected: a compile error naming `app_icon.dart`, then `Some tests failed.`

- [ ] **Step 3: The icon's control and its page**

Create `lib/features/dating/device/app_icon.dart` with exactly:

````dart
// Spec 2 W8b (§6.7, §3.2 D13; R-80): the plain app icon, for everyone.
// Android: one of two launcher aliases is on (MainActivity's appIcon and
// setAppIcon on attune/safety); iOS: the alternate icon IconPlain
// (AppDelegate's; iOS shows its own alert). The choice lives in the OS,
// never in a key the app stores, so quick exit and sign-out can't touch
// it (protective, C-2). Never throws: a phone without the channel answers
// null and changes nothing.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppIconChoice { attune, plain }

abstract class AppIconControl {
  /// The icon on the home screen now; null when this phone can't say or
  /// can't change it.
  Future<AppIconChoice?> current();

  /// True once the phone took [choice].
  Future<bool> choose(AppIconChoice choice);
}

class PlatformAppIcon implements AppIconControl {
  const PlatformAppIcon();

  static const channel = MethodChannel('attune/safety');

  @override
  Future<AppIconChoice?> current() async {
    try {
      return switch (await channel.invokeMethod<String>('appIcon')) {
        'plain' => AppIconChoice.plain,
        'default' => AppIconChoice.attune,
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> choose(AppIconChoice choice) async {
    try {
      return await channel.invokeMethod<bool>(
            'setAppIcon',
            choice == AppIconChoice.plain ? 'plain' : 'default',
          ) ==
          true;
    } catch (_) {
      return false;
    }
  }
}

final appIconControlProvider = Provider<AppIconControl>(
  (ref) => const PlatformAppIcon(),
);

/// The icon on the home screen, read again whenever it is shown.
final appIconProvider = FutureProvider.autoDispose<AppIconChoice?>(
  (ref) => ref.watch(appIconControlProvider).current(),
);
````

Create `lib/features/dating/settings/app_icon_screen.dart` with exactly:

````dart
// Spec 2 W8b (§3.12 App icon, §6.7, §3.15 standard list; R-80): Settings ->
// App icon: "Attune" or "Plain". The choice is the phone's (no server, so
// it works offline) and stays through quick exit and sign-out. iOS asks
// the person to confirm with its own alert; Android may close Attune while
// the launcher changes; both are said before the choice. A phone that
// can't change the icon says so.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/device/app_icon.dart';
import 'package:attune/features/dating/routes/dating_root_back.dart';
import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingAppIconScreen extends ConsumerStatefulWidget {
  const DatingAppIconScreen({super.key});

  @override
  ConsumerState<DatingAppIconScreen> createState() =>
      _DatingAppIconScreenState();
}

class _DatingAppIconScreenState extends ConsumerState<DatingAppIconScreen> {
  bool _busy = false;
  bool _failed = false;

  Future<void> _choose(AppIconChoice choice) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final ok = await ref.read(appIconControlProvider).choose(choice);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = !ok;
    });
    ref.invalidate(appIconProvider);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final read = ref.watch(appIconProvider);
    final current = read.valueOrNull;
    final known = read.hasValue && !read.hasError;
    Widget option(AppIconChoice choice, String label, Widget preview) =>
        RadioListTile<AppIconChoice>(
          key: ValueKey('dating_app_icon_${choice.name}'),
          contentPadding: EdgeInsets.zero,
          value: choice,
          groupValue: current,
          onChanged:
              _busy || current == null ? null : (c) => _choose(c ?? choice),
          title: Text(label),
          secondary: ExcludeSemantics(child: preview),
        );
    return AllowLargeText(
      child: Scaffold(
        appBar: AppBar(
          leading: datingRootBackButton(context),
          title: Text(loc.dating_appIconTitle),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(loc.dating_appIconIntro, style: theme.textTheme.bodyLarge),
                const SizedBox(height: Spacing.md),
                if (known && current == null)
                  DatingCalmLine(loc.dating_appIconUnsupported)
                else ...[
                  Semantics(
                    container: true,
                    label: loc.dating_appIconTitle,
                    child: Column(
                      children: [
                        option(
                          AppIconChoice.attune,
                          loc.dating_appIconAttune,
                          const _AttuneIconPreview(),
                        ),
                        option(
                          AppIconChoice.plain,
                          loc.dating_appIconPlain,
                          const _PlainIconPreview(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    defaultTargetPlatform == TargetPlatform.iOS
                        ? loc.dating_appIconIos
                        : loc.dating_appIconAndroid,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (_failed)
                  FlowErrorLine(
                    text: loc.dating_appIconFailed,
                    liveRegion: true,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The usual icon, as a sign (the launcher art itself is the platform's).
class _AttuneIconPreview extends StatelessWidget {
  const _AttuneIconPreview();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.favorite, color: scheme.onPrimary, size: 24),
    );
  }
}

/// The plain icon as the home screen shows it: one light ring on slate.
class _PlainIconPreview extends StatelessWidget {
  const _PlainIconPreview();

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: const Color(0xFF56616B),
      borderRadius: BorderRadius.circular(10),
    ),
    alignment: Alignment.center,
    child: Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFECEFF1), width: 3),
      ),
    ),
  );
}
````

Create `.superpowers/sdd/2026-11-22-spec2-w8/arb_fragment_T8.txt` with exactly:

````text
  "dating_appIconTitle": "App icon",
  "@dating_appIconTitle": {"description": "Spec 2 §3.12, §6.7 Settings -> App icon (the title and the Dating settings row)."},
  "dating_appIconIntro": "Some people like their apps to look plain. The icon on your home screen changes; Attune works the same.",
  "@dating_appIconIntro": {"description": "Spec 2 §6.7 the App icon page's first line (the spec's D13 sentence, then what changes). Plan copy (second sentence)."},
  "dating_appIconAttune": "Attune",
  "@dating_appIconAttune": {"description": "Spec 2 §6.7 the usual icon."},
  "dating_appIconPlain": "Plain",
  "@dating_appIconPlain": {"description": "Spec 2 §6.7 the plain icon."},
  "dating_appIconIos": "Your iPhone will ask you to confirm the change.",
  "@dating_appIconIos": {"description": "Spec 2 §6.7 iOS shows a system alert on change; the copy says so. Plan copy."},
  "dating_appIconAndroid": "Your phone may close Attune while the icon changes.",
  "@dating_appIconAndroid": {"description": "Spec 2 §6.7 Android may close the app while the launcher entry changes. Plan copy."},
  "dating_appIconFailed": "That didn't change. Try again.",
  "@dating_appIconFailed": {"description": "Spec 2 §6.7 the phone refused the change. Plan copy."},
  "dating_appIconUnsupported": "This phone can't change Attune's icon.",
  "@dating_appIconUnsupported": {"description": "Spec 2 §6.7 a phone without alternate icons. Plan copy."},
  "dating_readyPlainIcon": "Some people like their apps to look plain.",
  "@dating_readyPlainIcon": {"description": "Spec 2 §3.2 D13 the plain-icon offer (effective tier 1 or 2; A-11)."},
  "dating_readyPlainIconButton": "Choose an app icon",
  "@dating_readyPlainIconButton": {"description": "Spec 2 §3.2 D13 opens Settings -> App icon."}
````

- [ ] **Step 4: The icon's art (Android vectors; the iOS PNG, made by a script)**

Create `android/app/src/main/res/values/plain_icon.xml` with exactly:

````xml
<?xml version="1.0" encoding="utf-8"?>
<!-- Spec 2 W8b (§6.7): the plain app icon's slate. -->
<resources>
    <color name="ic_launcher_plain_background">#56616B</color>
</resources>
````

Create `android/app/src/main/res/drawable/ic_launcher_plain_foreground.xml` with exactly:

````xml
<?xml version="1.0" encoding="utf-8"?>
<!-- Spec 2 W8b (§6.7): the plain app icon's one light ring, an abstract
     shape that is no other app's icon (iOS draws the same: IconPlain). -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#00000000"
        android:strokeColor="#FFECEFF1"
        android:strokeWidth="5"
        android:pathData="M54,36.5a17.5,17.5 0,1 1,0 35a17.5,17.5 0,1 1,0 -35z" />
</vector>
````

Create `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_plain.xml` with exactly:

````xml
<?xml version="1.0" encoding="utf-8"?>
<!-- Spec 2 W8b (§6.7): the plain app icon (Android 8 and later). -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/ic_launcher_plain_background"/>
  <foreground android:drawable="@drawable/ic_launcher_plain_foreground"/>
</adaptive-icon>
````

Create `android/app/src/main/res/mipmap/ic_launcher_plain.xml` with exactly:

````xml
<?xml version="1.0" encoding="utf-8"?>
<!-- Spec 2 W8b (§6.7): the plain app icon before Android 8 (minSdk 24). -->
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item>
        <shape android:shape="rectangle">
            <solid android:color="@color/ic_launcher_plain_background" />
            <corners android:radius="12dp" />
        </shape>
    </item>
    <item android:drawable="@drawable/ic_launcher_plain_foreground" />
</layer-list>
````

Create `ios/Runner/Assets.xcassets/IconPlain.appiconset/Contents.json` with exactly:

````json
{
  "images" : [
    {
      "filename" : "IconPlain-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
````

Create `.superpowers/sdd/2026-11-22-spec2-w8/make_plain_icon.py` with exactly:

````python
#!/usr/bin/env python3
"""Spec 2 W8b Task 8 (§6.7): the plain app icon's 1024 x 1024 PNG for iOS
(opaque, as the App Store needs): a slate square with one light ring, an
abstract shape that is no other app's icon. Android draws the same shape
from vectors (res/drawable/ic_launcher_plain_foreground.xml). Pure Python
(zlib), deterministic: the same bytes on every run.
usage: make_plain_icon.py <out.png>"""
import struct, sys, zlib

N = 1024
BG = (86, 97, 107)       # #56616B
RING = (236, 239, 241)   # #ECEFF1
R, W = 300.0, 56.0       # the ring's radius and width, at the centre
c = (N - 1) / 2.0
rows = []
for y in range(N):
    row = bytearray(b'\x00')
    dy = y - c
    for x in range(N):
        d = abs(((x - c) ** 2 + dy * dy) ** 0.5 - R)
        a = max(0.0, min(1.0, W / 2.0 + 0.5 - d))  # 1 px of edge blending
        row += bytes(round(BG[i] + (RING[i] - BG[i]) * a) for i in range(3))
    rows.append(bytes(row))
raw = b''.join(rows)

def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)

png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', N, N, 8, 2, 0, 0, 0))
       + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))
open(sys.argv[1], 'wb').write(png)
print(f'{sys.argv[1]}: {N}x{N}, {len(png)} bytes')
````

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
python3 -I $D/make_plain_icon.py ios/Runner/Assets.xcassets/IconPlain.appiconset/IconPlain-1024.png
shasum -a 256 ios/Runner/Assets.xcassets/IconPlain.appiconset/IconPlain-1024.png | cut -c1-64
```

Expected: `…IconPlain-1024.png: 1024x1024, 20582 bytes`; `a84cd4659c111d648df3c11a31227acafbdb2a7df22bc5046d6f183bb067ae34`.

- [ ] **Step 5: The native side, the route, the settings row, the D13 offer, the manual, the order test**

Create `.superpowers/sdd/2026-11-22-spec2-w8/edit_native_T8.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W8b Task 8 (§6.7, §7.7; R-80): the plain app icon for everyone.
# Android: the launcher entry moves to two activity-aliases of MainActivity,
# .IconDefault (on) and .IconPlain (off; no "dating" in any name, the app's
# own label); MainActivity keeps a MAIN/LAUNCHER filter that only an
# explicit start matches (it names a scheme no launcher sends), so the
# Flutter tool still finds its launch activity and the launcher shows one
# icon. attune/safety gains appIcon and setAppIcon (the alias states, never
# a stored key). iOS: the alternate icon IconPlain (asset catalogue,
# ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES on the Runner target's three
# configurations) and the same two methods (setAlternateIconName; iOS shows
# its own alert). Exact edits; the device checks are the owner's (§7.7).
import pathlib, runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-22-spec2-w8/anchor.py')['edit']

edit('android/app/src/main/AndroidManifest.xml', [
    ("""            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
            <!-- Custom scheme""", """            <!-- Spec 2 W8b (§6.7): the launcher entry is one of the two
                 aliases below (the plain icon). This filter names a scheme
                 no launcher sends, so no launcher lists MainActivity, but
                 the Flutter tool (which looks for MAIN and LAUNCHER on an
                 activity) still starts it explicitly. -->
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
                <data android:scheme="attune-tool-launch"/>
            </intent-filter>
            <!-- Custom scheme"""),
    ("""        <!-- The photo crop screen (image_cropper; Spec 2 W3c T10). -->
""", """        <!-- Spec 2 W8b (§6.7): Settings > App icon. Exactly one of these is
             on (MainActivity's attune/safety setAppIcon switches them); neutral
             names only; the plain one carries the app's own label. -->
        <activity-alias
            android:name=".IconDefault"
            android:targetActivity=".MainActivity"
            android:enabled="true"
            android:exported="true"
            android:icon="@mipmap/ic_launcher"
            android:label="attune">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity-alias>
        <activity-alias
            android:name=".IconPlain"
            android:targetActivity=".MainActivity"
            android:enabled="false"
            android:exported="true"
            android:icon="@mipmap/ic_launcher_plain"
            android:label="attune">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity-alias>
        <!-- The photo crop screen (image_cropper; Spec 2 W3c T10). -->
"""),
], 'T8 manifest')

edit('android/app/src/main/kotlin/com/barsopus/attune/MainActivity.kt', [
    ("""import android.content.Context
import android.content.Intent
""", """import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
"""),
    ("""                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(false)
                    }
""", """                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(false)
                    }
                    // Spec 2 W8b (§6.7): the app icon is the launcher alias
                    // that is on; nothing else is stored.
                    "appIcon" -> result.success(if (aliasOn(plainIcon)) "plain" else "default")
                    "setAppIcon" -> {
                        val plain = call.arguments == "plain"
                        try {
                            setAlias(if (plain) plainIcon else defaultIcon, true)
                            setAlias(if (plain) defaultIcon else plainIcon, false)
                            result.success(true)
                        } catch (_: Throwable) {
                            result.success(false)
                        }
                    }
"""),
    ("""    // 18 and over is adult; a band that ends under 18 is supervised when a
""", """    // Spec 2 W8b (§6.7): the two launcher aliases (AndroidManifest.xml).
    private val defaultIcon get() = ComponentName(this, "com.barsopus.attune.IconDefault")
    private val plainIcon get() = ComponentName(this, "com.barsopus.attune.IconPlain")

    private fun aliasOn(alias: ComponentName): Boolean =
        when (packageManager.getComponentEnabledSetting(alias)) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED -> false
            // As the manifest says: only the default is on.
            else -> alias == defaultIcon
        }

    private fun setAlias(alias: ComponentName, on: Boolean) {
        packageManager.setComponentEnabledSetting(
            alias,
            if (on) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )
    }

    // 18 and over is adult; a band that ends under 18 is supervised when a
"""),
], 'T8 Android')

edit('ios/Runner/AppDelegate.swift', [
    ("""      case "setSecure":
        let on = (call.arguments as? Bool) ?? false
        self?.watchCapture(on)
        result(on && (self?.screenIsCaptured() ?? false))
""", """      case "setSecure":
        let on = (call.arguments as? Bool) ?? false
        self?.watchCapture(on)
        result(on && (self?.screenIsCaptured() ?? false))
      // Spec 2 W8b (§6.7): the app icon is iOS's alternate icon; nothing
      // else is stored. iOS shows its own alert on a change.
      case "appIcon":
        guard UIApplication.shared.supportsAlternateIcons else {
          result("unsupported")
          return
        }
        result(UIApplication.shared.alternateIconName == "IconPlain" ? "plain" : "default")
      case "setAppIcon":
        guard UIApplication.shared.supportsAlternateIcons else {
          result(false)
          return
        }
        let name: String? = (call.arguments as? String) == "plain" ? "IconPlain" : nil
        UIApplication.shared.setAlternateIconName(name) { error in
          result(error == nil)
        }
"""),
], 'T8 iOS')

p = pathlib.Path('ios/Runner.xcodeproj/project.pbxproj')
s = p.read_text()
old = '\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;\n'
assert s.count(old) == 3, s.count(old)
p.write_text(s.replace(old, old.replace('APPICON_NAME = AppIcon', 'ALTERNATE_APPICON_NAMES = IconPlain') + old))
print('ios/Runner.xcodeproj/project.pbxproj: 3 edit(s) (T8 alternate icon)')
````

Create `.superpowers/sdd/2026-11-22-spec2-w8/edit_app_T8.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W8b Task 8 (§3.2 D13, §3.12, §6.7; A-11; R-80): Settings -> App
# icon (/dating/app-icon), its row in Dating settings (for everyone, in
# §3.12's order, before the Dating lock; it needs no connection), the D13
# offer in Tier 1/2, the manual's topic, and the route's 2.0 audit.
# Formatter-style edits (W3-W8a files, never formatted).
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-22-spec2-w8/anchor.py')['edit']

edit('lib/features/dating/routes/dating_routes.dart', [
    ("""import 'package:attune/features/dating/settings/abroad_screen.dart';
""", """import 'package:attune/features/dating/settings/abroad_screen.dart';
import 'package:attune/features/dating/settings/app_icon_screen.dart';
"""),
    ("""  /// Spec 2 W8b (§3.11, §3.14): the traveller's note and choices.
  static const away = '/dating/away';
""", """  /// Spec 2 W8b (§3.11, §3.14): the traveller's note and choices.
  static const away = '/dating/away';

  /// Spec 2 W8b (§3.12, §6.7): Settings -> App icon.
  static const appIcon = '/dating/app-icon';
"""),
    ("""    (s) => const DatingAwayScreen(),
    back: datingMeLocation,
  ),
];""", """    (s) => const DatingAwayScreen(),
    back: datingMeLocation,
  ),
  // Spec 2 W8b (§3.12, §3.15): a standard list; alone, back is settings.
  datingRoute(
    DatingPaths.appIcon,
    'datingAppIcon',
    signedIn,
    (s) => const DatingAppIconScreen(),
    motion: (s) => DatingMotion.sharedAxis,
    back: () => DatingPaths.settings,
  ),
];"""),
], 'T8 routes')

edit('lib/features/dating/settings/dating_settings_screen.dart', [
    ("""import 'package:attune/features/dating/data/dating_never_introduce.dart';
""", """import 'package:attune/features/dating/data/dating_never_introduce.dart';
import 'package:attune/features/dating/device/app_icon.dart';
"""),
    ("""                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.lock_outline),
                  title: Text(loc.flow_lockTitle),
""", """                // Spec 2 W8b (§3.12, §6.7): App icon, for everyone, in
                // the spec's order; the phone's own setting, so offline too.
                row(
                  loc.dating_appIconTitle,
                  switch (ref.watch(appIconProvider).valueOrNull) {
                    AppIconChoice.plain => loc.dating_appIconPlain,
                    AppIconChoice.attune => loc.dating_appIconAttune,
                    null => '',
                  },
                  Icons.apps_outlined,
                  () => context.push(DatingPaths.appIcon),
                  evenOffline: true,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.lock_outline),
                  title: Text(loc.flow_lockTitle),
"""),
], 'T8 settings')

edit('lib/features/dating/setup/ready_step.dart', [
    ("""          // A-11: "Some people like their apps to look plain." arrives with
          // Settings -> App icon in W8b.
""", """          // Spec 2 W8b (A-11): the plain-icon offer, when the effective
          // tier is 1 or 2 (the home says so).
          if (ref.watch(datingHomeProvider(account)).valueOrNull?.offerPlainIcon ??
              false) ...[
            const SizedBox(height: Spacing.md),
            Text(loc.dating_readyPlainIcon, style: theme.textTheme.bodyMedium),
            DatingStartLink(
              label: loc.dating_readyPlainIconButton,
              onPressed: () => context.push(DatingPaths.appIcon),
            ),
          ],
"""),
    ("""import 'package:attune/features/dating/routes/dating_setup_steps.dart';
""", """import 'package:attune/features/dating/routes/dating_routes.dart'
    show DatingPaths;
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
"""),
], 'T8 D13')

edit('lib/app/documentations/user_manual/data/dating_mode_docs.dart', [
    ("""              'On Android, a screenshot or a screen recording of Dating comes out blank. An iPhone can\\'t block a screenshot, so Attune hides its screen in the app switcher and blurs Dating while the screen is being recorded or shared. Dating\\'s photos are never saved to your phone or your gallery. Quick exit forgets everything Dating was showing; your Dating lock and your Safety PIN stay as they are.',
          type: ManualContentType.text,
        ),
""", """              'On Android, a screenshot or a screen recording of Dating comes out blank. An iPhone can\\'t block a screenshot, so Attune hides its screen in the app switcher and blurs Dating while the screen is being recorded or shared. Dating\\'s photos are never saved to your phone or your gallery. Quick exit forgets everything Dating was showing; your Dating lock and your Safety PIN stay as they are.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_app_icon',
          title: 'A plain app icon',
          numberPrefix: '5',
          content:
              // Spec 2 W8b (§6.7; Plan copy).
              'In Dating settings, App icon changes Attune\\'s icon on your home screen to a plain one; its name stays the same. An iPhone asks you to confirm the change; on Android your phone may close Attune while it changes. Quick exit and signing out never change it back: only you do, in App icon.',
          type: ManualContentType.text,
        ),
"""),
], 'T8 manual')

edit('test/architecture/text_scale_routes_test.dart', [
    ("""  // Spec 2 W8b (§3.11): the traveller's note.
  'datingAway',
""", """  // Spec 2 W8b (§3.11): the traveller's note.
  'datingAway',
  // Spec 2 W8b (§3.12, §6.7): Settings -> App icon.
  'datingAppIcon',
"""),
], 'T8 audit list')
````

Create `.superpowers/sdd/2026-11-22-spec2-w8/edit_tests_T8.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W8b Task 8: W3's settings order test meets App icon (§3.12: after
# Never introduce me, before the Dating lock; W3 pinned it absent until
# W8b). Exact edit; nothing loosened.
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-22-spec2-w8/anchor.py')['edit']
edit('test/features/dating/settings/dating_settings_rows_test.dart', [
    ("""        'Never introduce me to these numbers',
        'Dating lock',
""", """        'Never introduce me to these numbers',
        // Spec 2 W8b (§3.12): App icon, for everyone.
        'App icon',
        'Dating lock',
"""),
    ("""      expect(find.textContaining('App icon'), findsNothing);
""", """      expect(find.text('App icon'), findsOneWidget); // Spec 2 W8b
"""),
], 'T8 settings order')
````

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py $D/arb_fragment_T8.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package > /dev/null 2>&1; echo "gen-l10n exit=$?"
dart format lib/features/dating/device/app_icon.dart lib/features/dating/settings/app_icon_screen.dart test/features/dating/device/app_icon_test.dart
python3 -I $D/edit_native_T8.py
python3 -I $D/edit_app_T8.py
python3 -I $D/edit_tests_T8.py
flutter analyze --no-pub lib/features/dating test/features/dating 2>&1 | tail -1
```

Expected: `added 10 keys`; `gen-l10n exit=0`; `Formatted 3 files (0 changed)`; `…AndroidManifest.xml: 2 edit(s) (T8 manifest)`, `…MainActivity.kt: 3 edit(s) (T8 Android)`, `ios/Runner/AppDelegate.swift: 1 edit(s) (T8 iOS)`, `ios/Runner.xcodeproj/project.pbxproj: 3 edit(s) (T8 alternate icon)`; `…dating_routes.dart: 3 edit(s) (T8 routes)`, `…dating_settings_screen.dart: 2 edit(s) (T8 settings)`, `…ready_step.dart: 2 edit(s) (T8 D13)`, `…dating_mode_docs.dart: 1 edit(s) (T8 manual)`, `…text_scale_routes_test.dart: 1 edit(s) (T8 audit list)`; `…dating_settings_rows_test.dart: 2 edit(s) (T8 settings order)`; `No issues found!`

- [ ] **Step 6: The goldens (the new page; Dating settings' bottom gains the App icon row), the tests, the audit**

```bash
flutter test --no-pub --update-goldens test/features/dating/device/app_icon_test.dart --plain-name goldens > /dev/null 2>&1
flutter test --no-pub --update-goldens test/features/dating/settings/dating_t12_fix1_test.dart --plain-name 'M-4: goldens' > /dev/null 2>&1
ls test/features/dating/device/goldens | grep -c dating_app_icon
flutter test --no-pub test/features/dating/device test/features/dating/settings test/features/dating/setup test/architecture test/app/documentations 2>&1 | tr '\r' '\n' | grep -E '\[E\]|: (All tests passed!|Some tests failed\.)' | tail -2
python3 scripts/large_text_audit.py --scale 2.0 test/features/dating/device 2>&1 | tail -1
```

Expected: `4`; `+686: All tests passed!`; `SCALE 2.0: 0 site(s) to fix, 0 listed apart`. Look at `test/features/dating/settings/goldens/dating_settings_bottom.scale1.0.png`: the only change is the App icon row above the Dating lock.

- [ ] **Step 7: The native builds: a debug APK (the manifest merges, the Kotlin compiles, the launcher sees one icon), the Swift type-check, the asset catalogue**

```bash
flutter build apk --debug --no-pub --target-platform android-arm64 2>&1 | tail -1
AAPT=$(ls ~/Library/Android/sdk/build-tools/*/aapt2 | tail -1)
$AAPT dump xmltree --file AndroidManifest.xml build/app/outputs/flutter-apk/app-debug.apk | grep -cE 'IconPlain|IconDefault|attune-tool-launch'
S=$(mktemp -d); printf 'import Flutter\nclass GeneratedPluginRegistrant { static func register(with registry: FlutterPluginRegistry) {} }\nenum TogetherLiveActivityChannel { static func register(with messenger: FlutterBinaryMessenger) {} }\n' > $S/Stub.swift
FW=$(dirname $(dirname $(readlink -f $(which flutter))))/bin/cache/artifacts/engine/ios/Flutter.xcframework/ios-arm64
xcrun --sdk iphoneos swiftc -typecheck -target arm64-apple-ios12.0 -sdk $(xcrun --sdk iphoneos --show-sdk-path) -F $FW ios/Runner/AppDelegate.swift $S/Stub.swift; echo "swift exit=$?"
xcrun actool --compile $S --platform iphoneos --minimum-deployment-target 12.0 --target-device iphone --target-device ipad --app-icon AppIcon --alternate-app-icon IconPlain --output-partial-info-plist $S/info.plist --output-format human-readable-text ios/Runner/Assets.xcassets > /dev/null 2>&1
plutil -extract CFBundleIcons.CFBundleAlternateIcons.IconPlain.CFBundleIconName raw $S/info.plist; rm -rf $S build/app
```

Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`; `3`; `swift exit=0`; `IconPlain`. (Without the Android SDK or Xcode these are the owner's: Owner checklist 4.)

- [ ] **Step 8: The mutants**

Create `.superpowers/sdd/2026-11-22-spec2-w8/mut_T8_dart.py` with exactly:

````python
# Spec 2 W8b Task 8: Dart mutants (dmut.py, in a private copy).
T = ['test/features/dating/device/app_icon_test.dart']
A = 'lib/features/dating/device/app_icon.dart'
P = 'lib/features/dating/settings/app_icon_screen.dart'
MUTS = {
    'always_plain': (A, "            choice == AppIconChoice.plain ? 'plain' : 'default',\n", "            'plain',\n", T),
    'plain_misread': (A, "        'plain' => AppIconChoice.plain,\n", "        'plain' => AppIconChoice.attune,\n", T),
    'refusal_silent': (P, '      _failed = !ok;\n', '      _failed = false;\n', T),
    'unsupported_offers': (P, '                if (known && current == null)\n', '                if (false)\n', T),
    'ios_note_everywhere': (P, '                    defaultTargetPlatform == TargetPlatform.iOS\n', '                    true\n', T),
    'never_read_again': (P, '    ref.invalidate(appIconProvider);\n', '', T),
    'settings_row_dead': ('lib/features/dating/settings/dating_settings_screen.dart',
                          '                  () => context.push(DatingPaths.appIcon),\n', '                  () {},\n', T),
    'offer_for_everyone': ('lib/features/dating/setup/ready_step.dart',
                           '          if (ref.watch(datingHomeProvider(account)).valueOrNull?.offerPlainIcon ??\n              false) ...[\n',
                           '          if (true) ...[\n', T),
    'wipe_resets_icon': ('lib/features/dating/dating_device_wipes.dart', [
        ("import 'package:attune/features/dating/device/dating_surface.dart';\n",
         "import 'package:attune/features/dating/device/dating_surface.dart';\nimport 'package:attune/features/dating/device/app_icon.dart';\n"),
        ('  await DatingPlanMemory.clear();\n}\n',
         '  await DatingPlanMemory.clear();\n  await const PlatformAppIcon().choose(AppIconChoice.attune);\n}\n')], None, T),
    'plain_on_at_install': ('android/app/src/main/AndroidManifest.xml', '            android:enabled="false"\n',
                            '            android:enabled="true"\n', T),
}
````

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
python3 -I $D/dmut.py $D/mut_T8_dart.py | tee $D/mut_T8_dart.txt | tail -1
```

Expected: `10/10 killed`.

- [ ] **Step 9: Record the tree (do not commit).**

### Task 9: The design spec's notes, the development flag, every W8 mutant again, and the W8b gate (§1.5 pattern, §4.9; Owner checklist)

**Files:**
- Create: `$D/edit_docs_T9.py`
- Modify: `docs/superpowers/specs/2026-10-24-dating-mode-design.md` (six `amended S2 W8` notes), `supabase/sql/dev_enable_spec2_dating_flags.sql` (`dating_traveller_detection`, development only)

- [ ] **Step 1: The notes and the development flag**

Create `.superpowers/sdd/2026-11-22-spec2-w8/edit_docs_T9.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W8b Task 9: the design spec says what W8 built where it differs
# (six amendment notes, the W7 pattern), and the development flag script
# turns the traveller flag on in development only (never a migration).
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-22-spec2-w8/anchor.py')['edit']
S = 'docs/superpowers/specs/2026-10-24-dating-mode-design.md'
edit(S, [
    ("""- on Android only, the SIM country and the network country (`TelephonyManager.getSimCountryIso` / `getNetworkCountryIso`), sent by the client. iOS sends none.
""", """- on Android only, the SIM country and the network country (`TelephonyManager.getSimCountryIso` / `getNetworkCountryIso`), sent by the client. iOS sends none. *(amended S2 W8: only the network country is sent; no computation reads the SIM's (R-75). `dating-device-check` calls `record_dating_device_check`, which keeps W1b's `record_dating_session_context` as the writer and records at most once per 15 minutes, so the away streak counts checks at least 15 minutes apart (R-72).)*
"""),
    ("""- The person may choose "Show it on this phone anyway"; that only changes what the device displays. The server still makes no same-gender introduction while the context forbids it.
""", """- The person may choose "Show it on this phone anyway"; that only changes what the device displays. The server still makes no same-gender introduction while the context forbids it. *(amended S2 W8: the choice is the person's, kept on their one context row (`show_here`) and read by their own reads only; it ends with the trip. A trip ends after 7 days of checks that are not away from home (R-77, R-78).)*
"""),
    ("""| `dating-device-check` | new | resolves the IP country (never logged), takes the Android SIM/network country, calls `record_dating_session_context`, returns `{trusted, away, note}` |
""", """| `dating-device-check` | new | resolves the IP country (never logged), takes the Android SIM/network country, calls `record_dating_session_context`, returns `{trusted, away, note}` *(amended S2 W8: the network country only; calls `record_dating_device_check`; `note` is `{country}` while the place restricts; the in-app note's once-per-trip flag is the home's `trip`, R-73, R-76)* |
"""),
    ("""It does not cancel a scheduled check-in (safety).
""", """It does not cancel a scheduled check-in (safety). *(amended S2 W8: `registerDatingDeviceWipes()` lives in `lib/features/dating/dating_device_wipes.dart` since W3a, with W3a's, W5b's and W6c's entries; W8a adds `spec2.section_caches` (order 20, as above: every Dating memory again, the report and appeal keys included) and `spec2.dating_surface` (order 0: every Dating page blank in quick exit's first frame). The Dating providers hold no data past their pages (autoDispose, a test pins it); no pending Dating deep link exists outside a route (R-69, R-70).)*
"""),
    ("""and the deprecated `UIScreen.isCaptured` only as the fallback on older systems (F-4).
""", """and the deprecated `UIScreen.isCaptured` only as the fallback on older systems (F-4). *(amended S2 W8: protected while any Dating page is open, a stricter reading of "on top": a page pushed over Dating keeps it, R-71.)*
"""),
    ("""Prompted at D13 when the effective tier is 1 or 2.
""", """Prompted at D13 when the effective tier is 1 or 2. *(amended S2 W8: the plain alias carries the app's own label; the launcher entry moves to two aliases and MainActivity keeps a launcher filter only an explicit start matches (the Flutter tool's); the choice lives in the OS, survives quick exit and sign-out, and is in Dating settings until a Spec 1 Settings row is approved (R-80).)*
"""),
], 'T9 design spec')

edit('supabase/sql/dev_enable_spec2_dating_flags.sql', [
    ("""    ('dating_age_assurance', true), -- Spec 2 W4a
""", """    ('dating_age_assurance', true), -- Spec 2 W4a
    ('dating_traveller_detection', true), -- Spec 2 W8b
"""),
], 'T9 dev flags')
````

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
python3 -I $D/edit_docs_T9.py
grep -c 'amended S2 W8' docs/superpowers/specs/2026-10-24-dating-mode-design.md
```

Expected: `…dating-mode-design.md: 6 edit(s) (T9 design spec)`, `…dev_enable_spec2_dating_flags.sql: 1 edit(s) (T9 dev flags)`; `6`.

- [ ] **Step 2: Every W8 mutant set again, on the finished tree**

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
M=supabase/migrations/20261122100000_dating_v2_traveller.sql; C=supabase/tests/dating_v2_device_contracts.sql; G=supabase/migrations/20261122100010_dating_v2_traveller_grants.sql
for s in T4 T5; do echo "$s $(W8_DB=attune_spec3a python3 -I $D/mutate.py $M $C $D/mut_$s.py $D/mut $G | grep -c 'CONTRACT VIOLATED')"; done
echo "T3 $(W8_DB=attune_spec3a python3 -I $D/mutate.py $C $C $D/mut_T3.py $D/mut | grep -c 'CONTRACT VIOLATED')"
for s in T1 T2 T3 T7 T8; do echo "$s $(python3 -I $D/dmut.py $D/mut_${s}_dart.py | tail -1)"; done
echo "T6 $(python3 -I $D/denomut.py $D/mut_T6.py | tail -1)"
```

Expected: `T4 20`, `T5 17`, `T3 6`; `T1 7/7 killed`, `T2 8/8 killed`, `T3 3/3 killed`, `T7 16/16 killed`, `T8 10/10 killed`; `T6 16/16 killed`.

- [ ] **Step 3: The W8b gate (wait for an idle machine for the race script)**

```bash
D=.superpowers/sdd/2026-11-22-spec2-w8
uptime
bash $D/gate.sh W8b attune_spec3a
```

Expected (the replay's): 

```text
SQL 163 PASS, 14 FAIL
SQL-NEW-FAILS:
DEVICE all held
DENO ok | 274 passed | 0 failed
DENO-CHECK exit=0
ANALYZE 571 issues found.
W10SHA 0
W9SHA 0
LATCH lib/home/home_screen.dart: OK
LARGETEXT SCALE 2.0: 0 site(s) to fix, 0 listed apart
GAMES All tests passed!
FLAGS 45 rows, 6 on
LOAD-BEFORE-RACES 2.95 3.30 4.20
RACES 54 PASS, 0 FAIL
FLUTTER +8983 -4: Some tests failed.
FLUTTER-FAILS:
  (the same four as the baseline's)
DONE
```

`+8983` is W8a's `+8941` and the 42 tests Tasks 7–8 add (`trip_test` 23, `app_icon_test` 11, two more locked routes in `dating_lock_entry_test`, and the tests that run once per `DatingHomeState`, which gained `away`); the four failures are the baseline's own; the flags gained one row (`dating_traveller_detection`, off).

- [ ] **Step 4: Record the tree (do not commit).**

---

## Owner checklist (nothing here is done by an implementer)

1. **⚑ The IP table (R-74).** Approve DB-IP's "IP to Country Lite" (CC BY 4.0) and its attribution ("IP Geolocation by DB-IP", https://db-ip.com) in the app's licences page and the privacy notice; the size (IPv4 and IPv6 at /64, an estimated 4–6 MB; IPv4-only about 2 MB); the monthly refresh. Or choose Cloudflare's `cf-ipcountry` instead, if the project's front door sends it (one resolver). Before each deploy of `dating-device-check`: download the month's CSV, build `supabase/functions/dating-device-check/ip_country.bin` with `scripts/ip_country/build_ip_country.ts` (its header has the commands), deploy (the `static_files` line ships it). Without the file every IP is unresolved: the phone's country decides, as for a VPN.
2. **⚑ The plain icon in Spec 1's Settings (R-80).** "For everyone" (§6.7): approve one row in Spec 1's Settings → Safety opening App icon for people who never use Dating (a Spec 1 file edit), or keep it in Dating settings and D13. A designer may replace the ring artwork (`make_plain_icon.py`, the Android vector), never with another app's icon.
3. **Deploys.** `supabase db push` (one migration and its twin; the self-revoke means a push that stops between them fails closed), deploy `dating-device-check` (after item 1), then app builds. The flag `dating_traveller_detection` stays off in production; its production gate row names the W8 gate.
4. **The §7.7 device checks, on release builds (F-4)**, Android (a Tecno or Itel, a mid Samsung, a Pixel) and iOS (an iPhone SE, a current iPhone; iOS 16 for the `isCaptured` fallback and iOS 17+ for `sceneCaptureState`): the lock screen shows only "Attune" / "You have something new in Attune." and a tap with the Dating lock on asks for the PIN; quick exit from Today, a chat and the meeting kit leaves nothing of Dating on return, with the Dating lock, the Safety PIN and the icon unchanged, and no frame of Dating under the decoy; Android screenshots and screen recordings of every Dating screen come out black (the Recents thumbnail too), and the protection ends after the last Dating page; iOS covers the app switcher and blurs Dating while recording or mirroring; the plain icon on Android (one launcher icon, the app's own name; the phone may close Attune while it changes; `flutter run` still starts the app) and iOS (the system alert; Cancel leaves the icon); the traveller: a VPN set to Ghana and to the UAE on a UK account, the in-app note once, never a push; the Android network country (a SIM abroad, a Wi-Fi-only tablet). Where this plan's machine lacked Xcode or the Android SDK, the Swift type-check, `actool` and the debug APK (Task 2 Step 5, Task 8 Step 7) are also the owner's.
5. **Copy reviewers.** Plan copy (listed with "Plan copy" in its ARB description): `dating_tripAwayBodyNoPlace`, `dating_tripSameGenderBodyNoPlace`, `dating_tripMore`, `dating_appealSentTesting` (DV reviewer), `dating_appIconIntro` (second sentence), `dating_appIconIos`, `dating_appIconAndroid`, `dating_appIconFailed`, `dating_appIconUnsupported`; the manual's `dating_screen` and `dating_app_icon`. The LGBTQ+ safety reviewer reads both same-gender trip lines (spec and Plan copy) with §2.4's copy.
6. **Moderation load (R-72).** The location signal opens a P3 case at 7 records away from the Dating country at least 15 minutes apart (about two hours of app use abroad), with the flag on. If that is too many cases for travellers, say so: counting one record per day is one line.
7. **DPIA lines.** The session context gains `home_since` and `show_here` (no country, no history; overwritten; deleted after 30 days without a check, as before); the IP is resolved to a country in the edge function and never stored, logged or sent to the database; the network country is used in the moment and never stored; the app icon is the phone's.
8. **The W7 production precondition stands** (W7 final client review): Dating is never on in production without an active moderator and safety owner. With W8 the restricted screen and the appeal line follow the server's `review` (no 24-hour or 7-day promise while nobody reviews).
9. **Carried, not built:** lazy per-card photo loading on Today (W5) — decide after §7.7's data-use measurement (R-82).
10. **Carried, not built:** a reference code for W4's own age check (W7 final client), so a codeless ID email can be matched; today the runbook asks for the code by reply.

## Spec coverage (self-review)

| Spec | Where |
|---|---|
| §8 W8a: `registerDatingDeviceWipes()` and its line; Dating's entry for quick exit and sign-out, never the lock, the PIN or the icon (C-2, C-3) | Task 1 (R-69, R-70); Task 8 (the icon untouched by both moments) |
| §8 W8a: `FLAG_SECURE` through `attune/safety`; the iOS capture blur (F-4); no gallery saves | Task 2 |
| §8 W8a: every Dating route, push tap and deep link honours the Dating lock; tests: quick-exit and sign-out widget tests, `FLAG_SECURE`, lock and push routing | Tasks 1, 2, 3 |
| §3.13, I-9: every Dating push neutral | Task 3 (contract A) |
| §8 W8b: migration 1 (`dating_v2_traveller`); `dating_eligibility` gate 7; flag `dating_traveller_detection`; traveller filtering in reads; mismatch signal | Tasks 4, 5 |
| §2.3: the IP country with a bundled DB-IP Lite Country table behind `IpCountryResolver`, never stored or logged; the Android network country; at most once per 15 minutes; `dating_session_context` one row, no country | Tasks 4, 6, 7 (R-72–R-75) |
| §2.5, §3.11: hide on the device, no new introductions, off others' Today; same-gender pairs on a same-gender trip; the note once per trip, never a push; Show it on this phone anyway, Pause Dating, Set a PIN; a Ghana SIM in London never turns same-gender on | Tasks 4, 5, 7 (R-76–R-79); W5's `dating_person` keys same-gender on the Dating country (unchanged) |
| §3.1 `away`; §3.14 `/dating/away`; §3.15 traveller (no motion, labelled) | Task 7 |
| §3.2 D13 plain-icon offer (A-11); §3.12 App icon; §6.7 plain icon for everyone (alias, alternate icon, system alert copy) | Task 8 (R-80; Spec 1's Settings row ⚑) |
| §4.7 `dating-device-check` `{trusted, away, note}` | Task 6 (R-73) |
| §5.10 location mismatch at 7 | Task 4 (B6) |
| §7.1 W8b traveller rows; §7.2 S4 (UK user with IP Ghana: no same-gender, hidden in reads; IP UAE: not allowed here; Ghana SIM in London; the note in-app) | Tasks 4, 5 (`dating_v2_device_contracts.sql` B, C; R-84) |
| §7.2 S19: no Dating data on disk | unchanged W3 test; W8 writes no key (the choice is the server's, the icon the OS's) |
| §7.3 `dating-device-check`: tier computation stays in the database (W1b's contract); the IP never in logs or responses | Task 6 |
| §7.4: quick exit and sign-out through the registry, caches empty, lock/PIN/icon unchanged, a slow entry doesn't stall; `FLAG_SECURE` on push and pop (mock channel); push routing; icon widget test | Tasks 1, 2, 3, 8 |
| §7.7: lock screen, screenshots, icon, traveller with a VPN; release builds | Owner checklist 4 |
| §1.5 pattern: amendment notes where W8 differs | Task 9 |
| Carries 1–9 | Pre-flight table |

## Replay record (2026-11-22)

The plan was built in a scratch copy of the repo at `296b7216` on a clone of `attune_spec3a` (`w8build`), then replayed from this text: a fresh scratch copy at `296b7216` (the W8 tool folder holding `carries.md` and the tools listed in Pre-flight; the W10 and W9 sha lists, the latch and `arb_append.py` copied in, as in the main tree), a fresh clone of `attune_spec3a` (`createdb -T`), and a script that wrote every "Create … with exactly" block and ran every `bash` block in order, with the database name swapped for the clone's. The first replay ran Tasks 1–9 end to end, both gates included (the W8b gate's race script at load 2.95). It found five things the plan now fixes:

1. **Task 4: a W3a contract pins the setup home's exact shape.** D13's `offer_plain_icon` (a Ghana person is Tier 1) broke `dating_v2_client_reads_contracts.sql`; the W8b gate's `SQL-NEW-FAILS` line caught it. Task 4 now updates that one pinned shape (`edit_tests_T4.py`) and runs the contract with the others.
2. **Task 9: two of Task 1's mutants anchored on Task 1's text that Task 2 rewrites** (`blank_never_resets`, `page_ignores_surface`: `anchor … occurs 0 times`). Task 1 now writes the first page's reset as a block (the finished file is byte-identical), and both mutants use lines that survive Task 2.
3. **Task 3:** the route test is `+22` at Task 3 (14 routes); Tasks 7 and 8 add two.
4. **The gate's failure list** printed reporter counters, not tests; it now prints each failing test, and removes the large-text audit's golden diagnostics (`test/features/dating/device/failures/`, git-ignored) after the audit.
5. **Expected wording:** `arb_append.py` prints `added N keys`; Deno 2.8's missing module is `TS2307 … Cannot find module`; Task 7's first missing file is `network_country.dart`; `dating_v2_client_reads_contracts.sql` prints no notice, so the contract loops print each file's exit status.

One thing the replay showed that is not W8's: `test/features/dating/chat/chat_screen_test.dart` "Swap: disabled before 72 hours…" fails at `296b7216` itself (alone too): its fixed clock `datingChatT0` (2026-11-20 18:00 UTC) plus two days is now in the past. With the three date-bound `healing_journal_large_text` goldens, every full run is `-4` with exactly those four.

After those fixes Tasks 1–5 were replayed again on a new scratch copy and a new clone (every block but the full Flutter runs and the gates, which the first replay ran on the same commands): every Expected line matched, and the full SQL suite on the second clone read `163 PASS / 14 FAIL`, no new fail. Task 1's mutants with the new anchors were run on the finished tree (`7/7 killed`). The replayed tree equals the built tree file for file (git-ignored golden diagnostics aside; the fixed contract line aside, which the second replay carries); the goldens and the icon's PNG are byte-identical. The clones (`w8build`, `w8replay`, `w8replay2`, `w8probe`, the gate's race database) and the scratch copies were dropped afterwards; `attune_spec3a` holds no W8 object (it was only read and cloned); the main tree changed only by this file and the tool folder `.superpowers/sdd/2026-11-22-spec2-w8/` (the tools listed in Pre-flight).

| Check | W8a (after Task 3) | W8b (after Task 9) |
|---|---|---|
| Migration + twin, applied twice | — (no migration) | 4 × `exit=0` at Task 4 and again at Task 5 |
| `marked_diff.py` | — | 2 functions `OK` (Task 4), 9 (Task 5) |
| SQL suite (wrapped) | 163 PASS / 14 FAIL, the baseline's 14 fails only | 163 / 14, same fails (first replay: 162 / 15 before fix 1) |
| `dating_v2_device_contracts.sql` | `all held` (A) | `all held` (A, B1–B6, C1–C3) |
| SQL mutants | T3 6 / 6 RED | T4 20 / 20, T5 17 / 17, T4 after T5 20 / 20, T3 again 6 / 6 |
| Race script (scratch DB built by the gate) | — (no SQL change) | 54 / 54 PASS (load 2.95) |
| Deno (CI line, frozen lock) | 266 passed, 0 failed; `deno check` clean | 274 passed, 0 failed; `deno check` clean |
| Deno mutants | — | T6 16 / 16 killed |
| Dart mutants (private copy of the tree) | T1 7 / 7, T2 8 / 8, T3 3 / 3 | T7 16 / 16, T8 10 / 10; T1–T3 again (after fix 2) |
| `flutter analyze --no-pub lib test` | 571, no new issue | 571 |
| Full `flutter test` | +8941 −4 (baseline +8906 −4; the same four) | +8983 −4 (the same four) |
| Large-text audit at 2.0 (`test/features/dating/device`) | 0 sites | 0 sites |
| W10 / W9 golden shas, latch, Games guard | 0 / 0 / OK / passed | 0 / 0 / OK / passed |
| Native | Swift type-check `exit=0` (iOS 12 target) | debug APK built (aliases and tool filter in the merged manifest: 3); Swift `exit=0`; `actool` lists `IconPlain` as an alternate icon |
| Feature flags | 44 rows, 6 on (unchanged) | 45 rows, 6 on (`dating_traveller_detection` off) |
