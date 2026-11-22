# Spec 2 W7 (Reporting, enforcement and moderation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Summary (one paragraph).** W7 is three batches, ten tasks, three migrations (each with its grants twin and a self-revoke), one new edge function, a new web entry point (the moderation console) and the report and appeal flows in the app. **W7a** (Tasks 1–4) → `20261121100000_dating_v2_reports.sql` (+ `20261121100010_dating_v2_reports_grants.sql`): reports v2 (the 14 categories and priorities of §3.7, the review clock, the evidence snapshot, one open case per person with every match linked and held from the purge, the automatic steps, corroborated interim holds, credibility weighting, restrictions v2 per type, the report and evidence purges, `submit_dating_report` and the v1 report RPCs removed) and its contract A–D (Task 1); what the restricted person sees, one appeal, carry-over at re-registration, an ended suspension released to a pause, the decisions the console calls, deletion keeping open cases, the races (Task 2); the report sheet everywhere §3.5–§3.7 put Report (Task 3); the restricted screen, the appeal, the section's cards, the manual, and the W7a gate (Task 4). **W7b** (Tasks 5–7) → `20261121110000_dating_v2_moderation_console.sql` (+ `…110010_…_grants.sql`): moderators, the append-only audit, read-time sensitive routing (S-5), the `moderation_*` functions, the SLA alerts and their cron (Task 5); the `dating-moderation` edge function, aal2 (TOTP) on every call, storage keys signed and never answered (Task 6); the console, `lib/console/main_console.dart`, its web page and CI build, and the W7b gate (Task 7). **W7c** (Tasks 8–10) → `20261121120000_dating_v2_escalations.sql` (+ `…120010_…_grants.sql`): escalations (a record, never a send), the law-enforcement request log, the transparency summary, the 2-year purges (Task 8); the console's escalation, log and summary (Task 9); the moderation runbook, the law-enforcement policy draft, the `DATING_MODE_SPEC.md` §8 and chat spec §5.1/§5.2 amendments, and the W7c gate (Task 10).

**Replayed.** Every task below was replayed in order in a scratch copy of the repo at `e4251c66` (on a clone of `attune_spec3a`): every "Create … with exactly" block, every build, edit and splice script, ARB fragment, `gen-l10n`, `dart format`, test command, mutant set, the web build, the race script on an idle scratch database and the Deno CI line. The Expected lines are what that replay printed (Replay record, end of plan).

**Goal:** Build Spec 2's reporting, enforcement and moderation (§3.7, §6.2–§6.6, W7) on the W1–W6 server and app: a report from every place a person meets someone (a conversation's Safety sheet, a safety card, the ended list for 30 days, a card on Today) that snapshots the evidence and never bans anyone by itself; interim holds only when P0 reports are corroborated; a restricted person who sees the category and appeals once to a different person; restrictions that survive deletion and come back with their appeal; a separate, TOTP-gated moderation console whose every action is audited and which never shows a case that needs sensitive routing to someone without it; escalations and law-enforcement requests that are always a person's recorded decision; and Dating still off in production.

**Architecture:** Server first in each batch, then the edge function, then the app or the console. Every re-created SQL function is taken from its LIVE body (`pg_get_functiondef` on `attune_spec3a` after the earlier waves, saved to `$D/before_w7a/` and `$D/before_w7c/`) with only the lines marked `-- Spec 2 W7a` / `W7c` changed (`marked_diff.py` checks); W7b re-creates none. A report is a safety write (no phone check, no eligibility check, as Block, R-36); the target's report lock (an advisory lock on the number's code) serialises two reports about one person, so the second sees the first. The automatic steps are read-time predicates over open cases (removed from new generation while a credible P0/P1 report's case is open, by account or by number), so a deletion can't shake them off and a closed case lifts them. Restrictions keep the four types; a trigger makes each type do what §6.3 says. The console is a separate Flutter web entry point that imports only `lib/console/**`, Flutter and `supabase_flutter` (test-pinned); it reaches the server only through the `dating-moderation` edge function, which needs an aal2 session and calls one `moderation_*` function per action with the signed-in moderator's id; the database refuses anyone who is not an active moderator and writes the audit. In the app, the report sheet sends the report itself under one key per sheet (a busy retry is the same report), and the restricted screen reads the person's own restriction, one entry per account (D8).

**Tech Stack:** Supabase Postgres 17 (RLS, `SECURITY DEFINER`, pg_cron, `extensions.hmac`, pg_net, advisory locks), psql, Python 3 (build, edit, splice and mutation scripts), Deno 2.8.1 (the edge function and its tests, frozen lock `.github/deno-w9.lock`), Flutter 3.29.1 / Dart 3.7 / Riverpod 2.6 / go_router, `supabase_flutter` (app and console; `functions.invoke`, `auth.mfa`), `flutter build web`. No new package.

**Spec:** `docs/superpowers/specs/2026-10-24-dating-mode-design.md` — §8 W7 (W7a, W7b, W7c, the gate line); §3.5 (the ended section), §3.6 (the Safety sheet's Report, the cards' Report), §3.7 (the whole section), §3.14 (`/dating/restricted`), §3.15 (Report sheet; Restricted, hold, appeal rows); §4.3 (`dating_reports`, `dating_account_restrictions`, `dating_report_evidence`, `dating_moderation_cases`, `dating_moderators`, `dating_moderation_actions`, `dating_appeals`, `dating_escalations`, `law_enforcement_requests`), §4.4 (Reports, appeals; `moderation_*`), §4.5, §4.6 (`dating-moderation-sla`), §4.7 (`dating-moderation`), §4.8 (reports 2 years; evidence; cases and actions; the law-enforcement log), §4.9 W7a–W7c, §4.10 (every row tagged W7); §6.2–§6.6, §6.8, §6.9 (`dating.report.{category}`, `dating.hold.p0`, `dating.appeal.*`, `dating.overturned.{country}`); §7.1 (`dating_v2_moderation_contracts.sql`), §7.2 S1, S2, S8, S11, S18, §7.3 (`dating-moderation`), §7.4, §7.5 mutants 13, 14, 15, 26, §7.7 (a report and an appeal under TalkBack and VoiceOver); §1.5 (`DATING_MODE_SPEC.md` §8; chat spec §5.1, §5.2). `docs/superpowers/specs/2026-10-24-cross-spec-review.md` — S-4, S-5, F-6. Carries: `.superpowers/sdd/2026-11-21-spec2-w7/carries.md` (every item mapped below). Format reference: `docs/superpowers/plans/2026-11-20-spec2-w6-chat.md`. The W6 ledger (`.superpowers/sdd/2026-11-20-spec2-w6-chat/progress.md`) and its final server fix report (the owner and deploy list W7 builds on).

## Global Constraints

- **Where and how.** Work in the main working tree on `main` (`/Users/user/attune`). HEAD is `e4251c66` (S2 W1–W6 committed). The owner may have uncommitted edits (`supabase/.temp/cli-latest`, `backup-before-planning-p2.sql`): never revert, stash, stage, checkout or reformat them. **An owner-approved client fix (the "slow fallback re-read") is being built in `lib/features/dating/chat/` while this plan is written** (`dating_chat_screen.dart`, `conversations_screen.dart`, `dating_chat_repository.dart`, `dating_chat_providers.dart`, their tests and `test/features/dating/support/dating_chat_fakes.dart`). It lands before W7 is built. W7a edits four chat files: `chat_sheets.dart`, `safety_card.dart`, `dating_chat_screen.dart` (the Safety sheet's switch, a `_report` method before `_block`, the card's `onReport`) and `conversations_screen.dart` (the ended rows); none of its anchors sits inside the fix's hunks (the fix's header comments, its `_inFlight`/`_route` fields, `_read`'s page call, the build's signal listener). Checked while planning against the fix as it then stood uncommitted in the main tree: every anchor of `edit_app_T3.py` occurs exactly once there too. If an anchor moved because the fix changed again, make the same change to the current text and say so in the task report; re-run Task 3's chat and Today tests and its mutants after the fix's own tests pass. W7 never edits the repository, the providers or `dating_chat_fakes.dart` (its own fakes are `test/features/dating/support/dating_report_fakes.dart`). Every edit to an existing file is an exact replacement made by a script that asserts each anchor occurs once (`anchor.py`).
- **NO commits.** No `git add`, `git commit`, `git stash`, `git checkout`, `git reset`, `git rm` (delete files with `rm`). Where a skill says "commit", instead: **do not commit; record the tree in the report** with `T=$(mktemp -u); GIT_INDEX_FILE=$T git read-tree HEAD && GIT_INDEX_FILE=$T git add -A && GIT_INDEX_FILE=$T git write-tree; rm -f $T` (a private index; the real index is untouched). The controller commits after each batch's final review.
- **Formatting.** Never `dart format` a pre-existing file (the repo uses an older formatter; formatting reflows it). `dart format` only the files a task creates. A later task that edits a file an earlier W7 task created does it with a generated anchor script already in `dart format` style (`edit_app_T9.py`) and does not run the formatter on it.
- **SQL target.** Contracts run only on `attune_spec3a`, from the repo root. A file with a top-level `BEGIN;` runs as `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f F`; one without runs wrapped (`suite.sh` does both). Migrations and their twins are applied with `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f <file>`. Confirm the target first (`psql -X -d attune_spec3a -Atc 'select current_database()'` prints `attune_spec3a`). **NEVER `attune_test`. NEVER run `scripts/local_pg_setup.sh` or `scripts/local_pg_grants.sql`** — but DO append each new twin's `\i` line to `scripts/local_pg_grants.sql` (`grants_line.py`). Mutants run inside one transaction that the contract's own `ROLLBACK` ends (`mutate.py`, with the grants twin applied after each migration mutant). An `IF a OR b` in a DO block has no evaluation order: every call that writes is its own statement first. A comparison that can read NULL uses `IS DISTINCT FROM`.
- **Migrations.** `20261121100000_dating_v2_reports.sql`, `20261121110000_dating_v2_moderation_console.sql`, `20261121120000_dating_v2_escalations.sql`, each with its `…10_…_grants.sql` twin, later than every file in `supabase/migrations/` (the newest is `20261120120010_dating_v2_chat_guided_grants.sql`). If `ls supabase/migrations | sort | tail -1` shows anything at or after `20261121100000` when Task 1 starts, shift all six to the next free hours keeping their order and change every header, `\i` line and command. Each file is one `BEGIN; … COMMIT;`, idempotent at its own task (applied twice, `exit=0` both times), with `SET LOCAL lock_timeout = '5s'`, and **ends by revoking everything it creates from PUBLIC, anon, authenticated and service_role** (the W6 final pattern: a push that stops between a migration and its twin fails closed); the twin grants. Every new function: `SECURITY DEFINER SET search_path = ''` (pure ones `IMMUTABLE`, trigger guards without definer where they need none), fully-qualified names; `GRANT EXECUTE … TO authenticated` only for the four app RPCs (`report_dating_match`, `report_dating_introduction`, `get_my_dating_restriction`, `submit_dating_appeal`); `service_role` only for the `moderation_*` functions (the edge function's); everything else the database's own. Re-created functions start from their LIVE body and change only lines marked `-- Spec 2 W7a|W7c`. Answers are fixed `{ok, reason}` codes, never a raise but the unsigned caller; input is validated before any write so no constraint error echoes input; NULL never counts as eligible, corroborating or allowed.
- **The W5 and W6 lessons, in this wave.** Reads that write are `VOLATILE` (`get_my_dating_restriction` carries over and releases; `moderation_case` writes the audit). Exposure-reducing writes never wait on ticks, workers, the purge or moderation (a report's block and a P0 close happen in the report itself; a deletion never waits on a case and never fails on the audit). Cron sweeps lock users `FOR KEY SHARE SKIP LOCKED`, each person in their own block, counted (`dating.release.busy`, `dating.release.failed`). Purge steps stay one subtransaction per step with their retries counted. Every new failure path is a `dating.` counter listed in health (W7a lists W7's once, Ruling R-57). D8: every sheet closes on an account change and shows nothing of the last account; every D8 test first asserts the page is on screen. The shown-set rule: nothing W7 adds animates or announces except a new sent or error line (live regions). The chat holds safety cards by id; a reported card is removed from the held map explicitly (a re-read only adds). The masker's 1,000-code-point cap is untouched (W7 masks nothing).
- **Production stays off.** No Dating flag turns on in production; no migration turns a flag on, sets `attune_environment`, names a moderator or sets the alert webhook. W7 adds no flag (every W7 surface sits behind the existing `dating_mode_enabled` and the console's moderator rows). The report's sent line says "In testing, reports go to the test review queue." until the project is in production mode (R-50); the production gate (owner checklist) makes sure a named moderator reads reports before that.
- **Vendors and data.** No vendor call in any test (Deno tests inject the RPC and storage; no `--allow-net`). Never read `.env*`, credentials or the keychain. No audit row, SLA alert, metric or log holds a name, an id of a reported person in an alert, a report's text, a routing value or a special-category answer. The console never receives a storage key (signed URLs only, 60 s), never a reporter's identity, never CSAM.
- **Copy.** New app strings go into `lib/i10n/app_en.arb` under `dating_` only through `python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py <fragment>`, then `flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package`. Straight apostrophes. Copy names people ("this person" without a name), never "they" for the other person (§3.7's own category labels excepted: they are the reporter's words). Every displayed date goes through `MyDateFormat`. Exact spec strings are copied verbatim; strings this plan adds are marked "Plan copy" in their ARB description and listed for the reviewers (Owner checklist). The app never shows a server's text. The console is an internal tool in English only (R-58), its strings in its own files.
- **UI.** Every new Dating screen and sheet is under `AllowLargeText`; sheets carry `datingSheetSettings(...)` and `DatingSheetTracker`. §3.15: the report sheet and the restricted, hold and appeal screens never animate. Goldens at 1.0, 1.3, 2.0 and RTL (`expectFlowGoldens`), the three guidelines (`expectFlowGuidelines`), the large-text audit at 2.0 (`0 site(s) to fix`). Text fields never let the keyboard learn (`enableSuggestions`, `autocorrect`, `enableIMEPersonalizedLearning` all false). Error red is the theme's (`FlowErrorLine`); busy and offline are calm lines.
- **Off limits.** Games (`test/architecture/games_untouched_test.dart` stays green), Opinions beyond calling S1 W9b's two existing review-queue RPCs from the console (R-61), `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`, `lib/home/home_screen.dart` and its latch (byte-identical; `shasum -c .superpowers/sdd/2026-11-07-spec2-w3/latch.sha`), `quick_exit_service.dart`, `auth_provider.dart`, `lib/main.dart`, `lib/app/app.dart`, `lib/app/routing/app_router.dart`, every applied migration, every Spec 1 file, every edge function but `dating-moderation` (new), the couples chat. **No deploys** (`supabase db push`, function deploys, secrets, the console's hosting and app builds are the owner's; Owner checklist).
- **Fixture ids.** The moderation contract's people are `7a700000-0000-0000-0000-` + the 12-digit code (`pg_temp.id('nn')`) with phones `+1555971nn`; ranges per batch so later sections never collide: A–D `01–59`, E–H `60–83`, W7b I–M `85–129`, W7c N–P `130–159`. The race script's W7 cases use `51–55` in its own id space.
- **Gates, every batch (Tasks 4, 7 and 10).** (1) The wrapped SQL suite on `attune_spec3a`: no new FAIL (baseline **161 PASS / 14 FAIL**, or 160 / 15 when `quiet_hours_contracts.sql` meets its clock-dependent hour; **162 / 14** from Task 1, which adds `dating_v2_moderation_contracts.sql`). (2) Full `flutter test`: no failure beyond the known flakes outside Dating (`chat_controller_test:259`, `chat_screen_list_anchor` D<0, `reflection_journal` at a date boundary, the three `healing_journal_large_text` goldens (they fail at `e4251c66` itself: the replay's every full run is `-3` with exactly those), `planning_recent`, `story_outbox_notices_test` "Discard asks first…", `chat_upload_progress_cancel_test`, `story_review_test` "final review #1"; re-run a failing file alone before calling it a flake); the count moves by the tests each task adds (listed per task). (3) `flutter analyze --no-pub lib test`: **571 issues, 0 new**. (4) `shasum -c .superpowers/sdd/2026-11-04-spec1-w10-accessibility-docs/w10-1.0.sha` and `shasum -c .superpowers/sdd/2026-11-04-spec1-w9/flag_off.sha`: every line `OK`. (5) `scripts/concurrency/dating_kill_switch_races.sh` on an **IDLE** scratch database (load under about 4; another agent may be running Flutter tests: wait, or note the load) built from `pg_dump -s attune_spec3a` plus the config tables' data, dropped after: every case `PASS` (42 from Task 2 on). (6) The Deno CI line (`.github/workflows/tests.yml` job `deno-w9`, frozen lock) passes in full and its `deno check` line is clean. (7) `test/architecture/games_untouched_test.dart` passes and the latch is `OK`. (8) Each task's named mutants all RED (a `CONTRACT VIOLATED` line, or `KILLED`), the RED line quoted in the report; a `COMPILE` or an `anchor missing` is a broken mutant to fix, never a kill; an equivalent mutant is retired with its reason in the task, never silently. (9) From Task 7: `flutter build web -t lib/console/main_console.dart` builds.



## Review Focus

Five things a real person will meet that this wave must survive. Each is pinned to tests that fail if it regresses.

1. **A malicious or retaliatory report** (one person reports another out of spite, twice from the same account, from a second account on the same phone, from a two-day-old account, or after their own messages to the target raised a money ask or sexual pressure). Expect: no hold, no ban, no closed match on the target's side beyond the reporter's own conversation; the target is only left out of new introductions while a credible P0/P1 case is open; the moderator reads the credibility note. Tests: Task 1 contract B (one P0 → no hold, mutant 13) and C (the same reporter on a new number, a young account, two accounts on one phone, a tripped reporter: no hold; mutants `m14_tripped_counts`, `same_reporter_counts`, `shared_phone_counts`, `young_reporter_counts`, `tripped_auto_step`).
2. **Reporting someone who is already gone** (the conversation ended by unmatch, block, a hold or the other's deletion; a chat only the two numbers' block ended; 29 days later; 31 days later). Expect: Report is there and works for 30 days (the ended list, the chat's Safety sheet, a safety card), the report keeps the deleted person's number's code and the block is kept by number; after 30 days, "This isn't available any more." Tests: Task 1 contract A (29 and 31 days) and D (after deletion; mutants `deleted_side_unstamped`, `number_block_dropped`, `window_forever`); Task 2 contract H (`ended_hides_number_block`); Task 3 widgets (the ended list's Report; mutant `ended_reports_wrong_chat`).
3. **A restricted person who deletes the account and comes back on the same number** to escape a suspension, or whose suspension simply runs out. Expect: the restriction comes back with its category and one appeal, Dating can't be begun or activated; an accepted appeal ends it everywhere; a suspension that ends leaves Dating paused, never suspended for good; a parked number carries nothing. Tests: Task 2 contract G (mutants `carry_none`, `carry_parked`, `carry_no_appeal`, `accept_record_kept`) and H (`sweep_skips`, `lift_no_release`, `cron_missing`).
4. **A moderator without sensitive routing opening a same-gender case** (in the queue, by a guessed id, by claiming, dismissing or recording an escalation on it), or anyone reading routing out of the audit. Expect: the case is absent from their queue and every action answers `case_unavailable`, the same answer as a case that doesn't exist; nothing about routing is stored or written anywhere; an unreadable identity routes. Tests: Task 5 contract J (mutant 26 `m26_queue_shows_routed`, `open_ignores_routing`, `unreadable_not_routed`, `pair_not_judged`); Task 8 contract N (`case_unavailable` for an escalation on a missing case); the canary's no-routing-column and console-decrypt checks.
5. **An account switch on a shared phone with a report sheet or the restricted screen open** (a sibling signs in mid-report). Expect: no frame of the next account shows the last account's report, its category or its restriction; nothing is sent as the next account; the sheet closes. Tests: Task 3 widget `D8: another account sees nothing of an open report sheet` (asserts the sheet is on screen first; mutant `sheet_shows_next_account`); Task 4 widget `D8: another account sees nothing of the last one's restriction` (mutant `read_not_per_account`).

## Pre-flight (read before Task 1)

### Shared files and interfaces between tasks

| File or interface | Tasks | Rule |
|---|---|---|
| `.superpowers/sdd/2026-11-21-spec2-w7/` (`$D`) | 1 creates the tools, baselines and `before_w7a/`; every task adds its scripts and outputs | `suite.sh`, `grants_line.py`, `dmut.py`, `denomut.py`, `anchor.py`, `marked_diff.py` are W6's, copied unchanged; `mutate.py` is W6's with `W7_DB`; `splice.py` is new |
| `supabase/migrations/20261121100000_dating_v2_reports.sql` | 1 builds it (`build_mig_W7a.py`: `mig_T1_head.sql`, the re-created functions, the self-revoke); 2 adds `mig_T2.sql` (at the head's `-- @@W7A-T2@@`) and its two re-created functions, and builds again | the builder includes Task 2's section, edits and revokes when `mig_T2.sql` exists |
| `…100010_dating_v2_reports_grants.sql` | 1 creates (ends with `-- @@W7A-T2-GRANTS@@`); 2 splices `twin_T2.sql` there | |
| `supabase/tests/dating_v2_moderation_contracts.sql` | 1 creates (A–D, then `-- @@W7A-T2@@`); 2 splices E–H (ends `-- @@W7B@@`); 5 splices I–M (ends `-- @@W7C@@`); 8 splices N–P (ends `-- @@W7-END@@`) | helpers `pg_temp.id`, `ready`, `man`, `call`, `j`, `probe`, `report`, `match`, `say`, `held`, `excluded`, `marked`, `delete_account`, `metric`, `key`; from Task 5 `try_sql`, `as_service`, the `w7_posts` pg_net recorder |
| `supabase/tests/{dating_rls_canary,service_role_grants_test,dating_mode_contracts,dating_v2_verification_contracts,dating_v2_setup_contracts}.sql` | 1, 2, 5, 8 | exact edits (`edit_tests_T{1,2,5,8}.py`); the canary's W7 rows go above its Checks line, behind `-- @@W7A-T2-CANARY@@` and `-- @@W7C-CANARY@@`; never a loosened check |
| `scripts/concurrency/dating_kill_switch_races.sh` | 2 | two new cases; W3c's "a gone hit's Dating hold vs exit" now sleeps in the introductions (a hold no longer touches the profile, R-53); the reset clears the race people's reports and cases |
| `private.dating_place_restriction`, `private.dating_close_case`, `private.dating_decide_appeal` | 1 (place, close), 2 (decide) create; 5 calls them from the console | one writer of a restriction; closing always stamps `decided_at` |
| `private.dating_moderator`, `private.dating_case_for`, `private.dating_audit` | 5 creates; 8 uses | every console function: the moderator, the case they may see, one audit row |
| `get_dating_operational_health` | 1 re-creates (W7's counters and the reports block) | W7b/W7c add no counter of their own (R-57) |
| `private.dating_purge_steps`, `private.dating_purge_step` | 1 re-creates (evidence, reports, the case links' hold); 8 re-creates (the audit, escalations, the log) | each from its live body |
| `lib/features/dating/report/*.dart`, `test/features/dating/support/dating_report_fakes.dart` | 3 creates the data layer, the sheet and the fakes; 4 the restricted screen | `DatingReportGateway` is complete in Task 3; the fake implements all of it |
| `lib/features/dating/chat/{chat_sheets,safety_card,dating_chat_screen,conversations_screen}.dart`, `today/{block_sheet,today_screen}.dart` | 3 (`edit_app_T3.py`) | see "Where and how" for the concurrent chat fix |
| `lib/features/dating/{routes/dating_routes,section/dating_section,data/dating_home}.dart`, the manual, `test/architecture/text_scale_routes_test.dart` | 4 (`edit_app_T4.py`) | |
| `supabase/functions/dating-moderation/*`, `supabase/config.toml`, `.github/workflows/tests.yml` | 6 creates the function and edits CI and config; 7 adds the console's CI job; 9 adds W7c's actions (`edit_fn_T9.py`) | |
| `lib/console/**`, `web/index.html`, `test/console/*` | 7 creates; 9 adds the law-enforcement page and the escalation (`edit_app_T9.py`) | the console imports only `lib/console`, Flutter and `supabase_flutter` (test-pinned) |
| `lib/i10n/app_en.arb` + generated | 3, 4 | `arb_fragment_T{3,4}.txt` via `arb_append.py`, then gen-l10n |

### Carries → tasks

| # | Carry (`carries.md`) | Where |
|---|---|---|
| 1 | W5 (M-15): captions pointing at image content (a QR code or number in a photo) → image OCR/QR moderation | **Ruled out of W7**: no W7 section asks for image OCR; the photo queue (Task 5's `moderation_photos`) lets a person reject such a photo (`unsafe`). Owner checklist 8 (a later wave or the W10 gate). |
| 2 | W5: the card's More menu Report | Task 3 (`DatingCardMore.report`, `report_dating_introduction`; widget `the card on Today: More offers Report`) |
| 3 | W5: "W7a: close unconfirmed signal cases at account deletion"; T8 N-3 (that closure must not count as a decision, or keep the case open userless) | **N-3's alternative is built (Ruling R-66)**: deletion keeps every open case open, without the account, under the number's code, so a re-registered sender stays throttled; a moderator closes an orphaned case. Task 2 contract H (`deletion_closes_cases` mutant). |
| 4 | W5 T8 N-2: an orphaned open dragnet case follows a recycled number | R-66 + the runbook (§3: close an orphaned case with no action unless it warrants one) + Owner checklist 2 (DPIA line). |
| 5 | W5: DPIA lists `dating_moderation_cases.target_phone_hmac` | Owner checklist 2. |
| 6 | W6 T2 N-4: a chat blocked only by the numbers is in neither list | Task 1 (`get_my_dating_matches` lists it under ended; the report accepts it); Task 2 contract H (`ended_hides_number_block`). |
| 7 | W6 T4: the chat's message map never shrinks on a re-read; a hidden or reported message must be removed explicitly | Task 3: a reported **safety card** leaves the chat's held map by id (`card_kept_after_report`, `card_dismissal_unsent`). No W7 path hides a delivered message (§6.4's actions don't include removing one), so there is no message to remove; recorded here. |
| 8 | W6 T5: closing a signal case must set `decided_at` | Task 1 creates `private.dating_close_case`, which always stamps it; Task 2's contract H and mutant `close_no_decided_at` pin it; Task 5 (every console close goes through it). |
| 9 | W6 T8: `dating_reports` needs the §4.8 2-year purge | Task 1 (purge steps `reports`, `report_evidence`; contract D; mutants `reports_kept_forever`, `open_case_reports_purged`, `evidence_kept_forever`, `evidence_ignores_restriction`). |
| 10 | W6 final M-16: link every match a case's evidence comes from; the purge's hold reads the link | Task 1 (`dating_case_matches`, `dating_open_chat_case` and the report case link; the purge's hold; contract D; mutants `case_link_missing`, `signal_link_missing`, `purge_ignores_links`). |
| 11 | R-43: Report on the Safety sheet, each card and the ended list (30 days); restore the manual's Report wording | Task 3 (all three, and Today's card); Task 4 (the manual's `dating_money` warning and `dating_chat` topic say report again, plus a `dating_report` topic). |
| 12 | W6 gate row for `dating_match_messaging` lists "Report (W7a) built" | W7a builds it; Owner checklist 1 (the gate row's evidence). |
| 13 | W6 T5 M-4: a retired safety config editable | **Already fixed** by W6's final server fix (M-6: the guard freezes on `activated_at`; W6 contract FF11). Nothing in W7. |
| 14 | The slow fallback re-read in flight | "Where and how" (Global Constraints): the four chat files W7a edits and why the anchors miss the fix's hunks. |

### Rulings (the spec wins over this plan; each records its cost if wrong)

- **Ruling R-49:** reports v2 add three columns §4.3 doesn't name: `reporter_phone_hmac` (corroboration needs "different phone HMACs", and must still work after the reporter's deletion), `auto_step` (the report took §6.2's automatic step: credible P0/P1) and `request_key` (a replay answers exactly as the first). v1 rows' `safety_concern` and `sexual_content` become `other` and `explicit_content`. The evidence is the last 50 messages of the conversation, both sides together, raw (the moderator needs what was said), encrypted with the field key; without the key the report stands, counted (`dating.report.evidence_unavailable`). Cost if wrong: a column, or 50 more messages.
- **Ruling R-50 (owner-visible):** the review clock. P0: four **staffed** hours (08:00–22:00 GMT), never more than 24 hours (a report at 21:00 is due 11:00 the next day); P1 24 h, P2 48 h, P3 72 h. The sent line says "within {n} hours" under 48 hours, else "within {n} days", from the report's own clock; it says "In testing, reports go to the test review queue." until the project is in production mode (`attune_environment = 'production'`), which the W7 gate allows only once the moderator is named. Cost if wrong: one function and two strings.
- **Ruling R-51:** a restriction inserted without a source (the three CSAM paths, W4's age paths, older tests) takes one from its type: a hold is `csam_hash`/`csam`, an age review `age_assurance`/`underage_risk`, else `moderator`. Holds, age reviews and closer looks are never appealable (§6.3: "not until decided", "via the ID route", "none visible"), except a hold carried to a new account, which keeps its one appeal. Cost if wrong: a default.
- **Ruling R-52:** at an account's deletion its side of every match keeps the number's code (`dating_matches.low_phone_hmac`/`high_phone_hmac`), so the other person can still report for 30 days (§6.2) and the report names the number; "Also block" after the other's deletion is kept by number. Cost if wrong: two columns (purged with the match).
- **Ruling R-53 (owner-visible):** a suspension that ends — lifted, an accepted appeal, or past its date — leaves Dating **paused** (reason `gates`), never suspended for good: the lift at once, a cron every 15 minutes (`release-dating-suspensions`) for one that ran out; the person taps Resume. Per §6.3 a hold no longer suspends the enrolment or closes matches (W3c's CSAM hold did both): the person is hidden from introductions and can't send; their conversations stay open. A CSAM hit still places Spec 1's `safety_review` account hold, which closes the whole app. Cost if wrong: the person reads "Dating is paused" after a suspension and taps Resume.
- **Ruling R-54:** the restricted person's read and the appeal are not phone-checked: a restricted person may be unable to re-verify a new phone, and the read shows only their own restriction's category. Cost if wrong: one guard line each.
- **Ruling R-55 (spec amended):** carry-over at re-registration happens in the restricted person's read (`get_my_dating_restriction`, which the section's restricted card opens), not in `begin_dating_enrollment`: begin refuses the person (`not_eligible`), and its raise would roll the copy back. The record itself refuses the account from the start (good standing reads it). Cost if wrong: none (the person sees the same screen).
- **Ruling R-56 (owner-visible):** the age check's [Verify with ID] opens Contact support (Dating has no ID route outside setup); once support has seen the ID, the moderator lifts the age check from its case (the console's Lift, which lifts a hold or an age check placed by a report or a moderator). A confirmed minor's Spec 1 account hold is cleared only by Spec 1's support path. Cost if wrong: an in-app ID route later.
- **Ruling R-57:** W7a's health lists W7's counters once, W7b's SLA counters included, so W7b and W7c never re-create health. Cost if wrong: none.
- **Ruling R-58:** the console is plain Flutter (no Riverpod, no GoRouter, English only, an internal tool): `lib/console/main_console.dart` with `web/index.html` (the repo had no `web/`); its URL and key are `--dart-define`s at the owner's build; CI builds it on every push; `build/console` is ignored. Cost if wrong: a refactor of an internal tool.
- **Ruling R-59:** `dating-moderation` has `verify_jwt = false` (a browser's CORS preflight carries no token): `request.ts` checks every token with `requireUser`, reads `aal` from that token and refuses anything below `aal2`; CORS only for the `DATING_CONSOLE_ORIGIN` secret (none set: no browser origin). Cost if wrong: one config line.
- **Ruling R-60 (owner-visible):** the law-enforcement log and the transparency summary are the safety owner's to **read** too (§6.4 says "record (safety owner only)"): least privilege for the most sensitive log. Cost if wrong: one role check.
- **Ruling R-61 (owner-visible, flagged):** the console's Opinions page calls **only** S1 W9b's two review-queue RPCs (`admin_list_priority_reports`, `admin_confirm_content_removal`) through two audited `moderation_*` wrappers, and touches nothing else in Opinions. S1 W9b has no "mark reviewed" RPC, so a priority report stays in queue v0 until its post is removed or a person marks it from the SQL editor, as today. Cost if wrong: one Opinions RPC, owner-approved, later.
- **Ruling R-62:** `moderation_confirm_minor` is a second Dating caller of Spec 1's `place_account_hold` (§6.3: "when a moderator confirms a minor on an `underage_risk` case"); W4's R8 caller list gains it. Cost if wrong: none.
- **Ruling R-63:** a P0 report from a conversation closes it with the new closed reason `reported` (30-day window) and writes the pair marker (W6, never introduced again); from a card it takes the card away. A report is a safety write: no phone or eligibility check (R-36), membership only, 10 a day (the existing limit). Cost if wrong: one reason value.
- **Ruling R-64:** an appeal's outcome is in-app only (§3.7): accepted → "Your appeal was accepted. Dating is open again." on the Dating section for 7 days (`get_dating_home` carries `appeal_accepted` only when true, so no other home answer changes) and on the restricted screen; rejected → "We looked again and the decision stands." on the restricted screen. No push. Cost if wrong: a push later.
- **Ruling R-65:** `under_review` (a closer look) is never visible: good standing ignores it, generation leaves the person out (§6.3). Cost if wrong: none.
- **Ruling R-66 (DPIA):** a deletion keeps every open report or signal case open, without the account, under the number's code (W5 T8 N-3's alternative), so a re-registered dragnet sender stays throttled and a reported person stays out of new introductions; a moderator closes an orphaned case. Cost if wrong: a recycled number's new owner is throttled until a moderator closes the case.
- **Ruling R-67:** the audit is append-only: an UPDATE is refused except a foreign key's own SET NULL (a purged case, a deleted account: deletion never fails on the audit); a DELETE only from the purge, at 2 years. Cost if wrong: none.
- **Ruling R-68:** the SLA alert is one line per priority per run about the oldest case past its time ("P0 case waiting 3 h 40 m", from its creation), to `app_setting('moderation_alert_webhook')` (Vault); without one, counted and nothing sent. Cost if wrong: one string.
- **Ruling R-36 (carried):** Block, Unmatch, Close kindly and now Report are gated by neither the phone nor eligibility, only membership.

## Interfaces this plan consumes (read from the current code)

- **Spec 1:** `private.bump_metric_internal(text)`, `public.place_account_hold(uuid, text, text)`, `public.app_setting(text)`, `net.http_post`, `public.admin_list_priority_reports(int)`, `public.admin_confirm_content_removal(text, uuid)`, `UrlLauncherUtils.launchEmail`, `AppConstants.supportEmail`, `supportCountryProvider`, `supportResourcesProvider` (`SupportResources.emergency`), `MyDateFormat`, `AllowLargeText`, `expectFlowGoldens`, `expectFlowGuidelines`, `tapInReach`, `_shared/attune_auth.ts` (`requireUser`, `serviceRoleClient`, `HttpError`), `_shared/error_code.ts`.
- **S2 W1–W6 (live):** `private.dating_lock_setup(uuid)`, `private.dating_field_encrypt/decrypt`, `public.dating_phone_hmac_for_user(uuid)`, `private.dating_key_ok(text)`, `public.claim_dating_idempotency`, `public.check_dating_rate_limit`, `public.block_dating_match`, `public.block_dating_introduction`, `private.dating_mark_pair`, `private.dating_bump_chat`, `private.dating_pair_blocked`, `private.dating_pair_is_man_woman`, `public.dating_account_in_good_standing`, `private.dating_generation_removed`, `public.enforce_dating_restriction_change`, `private.dating_deletion_carry`, `private.dating_open_signal_case`, `private.dating_open_chat_case`, `private.dating_purge_steps/step`, `public.purge_dating_retention`, `public.get_my_dating_matches(boolean)`, `public.get_dating_home()`, `public.get_dating_operational_health()`, `public.record_dating_csam_hold`, `public.decide_dating_human_review`, `public.publish_country_config`, `dating_moderation_cases`, `dating_safety_events`, `dating_trusted_devices`, `enforcement_records`; app: `DatingRpc`, `DatingActionKeys`, `datingAccountProvider`, `datingLifecycleGatewayProvider`, `datingOnlineProvider`, `datingSheetSettings`, `DatingSheetTracker`, `DatingCalmLine`, `datingRoute()`, `datingRootBackButton`, `DatingPaths`, `showDatingSafetySheet`, `DatingSafetyCardView`, `showDatingCardMoreSheet`, `FakeDatingChat`, `FakeDatingToday`, `pumpDatingShell`, `datingShellOverrides`.

## Interfaces this plan produces (for W8 onward)

- **SQL (W7a):** `dating_reports` + `match_id`, `introduction_id`, `reporter_phone_hmac`, `priority`, `reporter_tripped_family`, `counts_for_corroboration`, `auto_step`, `state`, `sla_due_at`, `case_id`, `request_key`; `dating_report_evidence`; `dating_case_matches`; `dating_moderation_cases` + `appeal_id`; `dating_account_restrictions` + `category`, `source`, `case_id`, `decided_by`, `appealable`, `carried_from`; `dating_appeals`; `dating_matches` + `low_phone_hmac`, `high_phone_hmac`, closed reason `reported`; `enforcement_records` + `case_id`. `report_dating_match(key, match, category, details, also_block)` and `report_dating_introduction(key, intro, category, details, also_block)` → `{ok, review: 'testing'|'staffed', sla_hours}` | `{ok:false, reason: invalid|report_unavailable|rate_limited|busy}`; `get_my_dating_restriction()` → `{ok, restriction: null | {id, type: hold|age_review|suspended, ends_at, category, can_appeal, appeal: null | {state, submitted_at, decided_at}}, appeal_accepted}`; `submit_dating_appeal(key, restriction, text)` → `{ok}` | `invalid|appeal_unavailable|already_appealed|busy`; internal `private.dating_place_restriction(user, type, category, source, case, decided_by, ends_at, appealable)`, `private.dating_close_case(case, decider, outcome)`, `private.dating_decide_appeal(appeal, decider, decider_is_owner, accept)`, `private.dating_report_excluded(user)`, `private.dating_carry_over(user)`, `private.dating_release_suspension(user)`; cron `release-dating-suspensions` (every 15 minutes); `get_dating_home()` + `appeal_accepted` (only when true).
- **SQL (W7b):** `dating_moderators`, `dating_moderation_actions` (append-only); `moderation_whoami`, `moderation_queue`, `moderation_case`, `moderation_claim`, `moderation_dismiss`, `moderation_place_hold`, `moderation_lift_hold`, `moderation_restrict`, `moderation_ask_for_id`, `moderation_confirm_minor`, `moderation_note`, `moderation_decide_appeal`, `moderation_photos`, `moderation_photo_decide`, `moderation_verifications`, `moderation_verification_decide`, `moderation_countries`, `moderation_publish_country`, `moderation_opinions_queue`, `moderation_opinions_remove`, `moderation_audit_log` (each `(p_actor uuid, …)`, the service role's); `private.dating_case_needs_sensitive_routing(case) → boolean`; `dating_moderation_sla_check(at)` and its cron `dating-moderation-sla`.
- **SQL (W7c):** `dating_escalations`, `law_enforcement_requests`; `moderation_record_escalation`, `moderation_le_requests`, `moderation_record_le_request`, `moderation_transparency_summary`; `private.dating_transparency_summary(from, to)`; purge steps `moderation_actions`, `escalations`, `law_enforcement_requests`.
- **Edge:** `dating-moderation` (POST `{action, …}`; `ACTIONS` maps each to one function; `handleModeration(body, {userId, aal}, deps)`, `aalOf(token)`).
- **App:** `lib/features/dating/report/{dating_report.dart (DatingReportCategory, datingReportLabel, DatingReportAnswer, DatingRestriction, DatingRestrictionRead, DatingAppeal, DatingReportTarget, DatingReportMatch, DatingReportCard, DatingReportOutcome), dating_report_repository.dart (DatingReportGateway, DatingReportRepository), dating_report_providers.dart (datingReportGatewayProvider, datingRestrictionProvider), report_sheet.dart (showDatingReportSheet, DatingReportSheet), restricted_screen.dart (DatingRestrictedScreen, datingRestrictionLabel, showDatingAppealSheet, datingSupportContactProvider)}`; `DatingPaths.restricted`; `DatingSafetyChoice.report`; `DatingCardMore`; `DatingHome.appealAccepted`; test support `FakeDatingReport`, `datingReportOverrides`.
- **Console:** `lib/console/{main_console.dart, console_api.dart (ConsoleApi, ConsoleAnswer, SupabaseConsoleApi), console_auth.dart (ConsoleAuth, ConsoleSession, SupabaseConsoleAuth), console_app.dart (ConsoleApp, ConsoleGate, ConsoleHome, ConsolePage, ConsoleMe, consoleReason), screens/{queue_screen, case_screen, console_lists, law_enforcement_screen}.dart}`; test support `test/console/console_fakes.dart`.

## File map

**W7a.** Task 1 creates `$D/{mutate.py, splice.py, before_w7a/, sql-baseline.txt, analyze-baseline.txt, flutter-baseline.txt, mig_T1_head.sql, build_mig_W7a.py, edit_tests_T1.py, mut_T1.py}`, `supabase/migrations/20261121100000_dating_v2_reports.sql`, `…100010_…_grants.sql`, `supabase/tests/dating_v2_moderation_contracts.sql`; modifies `dating_rls_canary.sql`, `service_role_grants_test.sql`, `dating_mode_contracts.sql`, `scripts/local_pg_grants.sql`. Task 2 creates `$D/{mig_T2.sql, twin_T2.sql, contract_T2.sql, edit_tests_T2.py, edit_races_T2.py, mut_T2.py}`; rebuilds the migration and the twin; modifies the contract, the canary, the race script. Task 3 creates `lib/features/dating/report/{dating_report.dart, dating_report_repository.dart, dating_report_providers.dart, report_sheet.dart}`, `test/features/dating/support/dating_report_fakes.dart`, `test/features/dating/report/report_sheet_test.dart` and its goldens, `$D/{arb_fragment_T3.txt, edit_app_T3.py, mut_T3_dart.py}`; modifies the four chat files and Today's two; regenerates `dating_chat_card.*` and `today_more_sheet.*` goldens. Task 4 creates `lib/features/dating/report/restricted_screen.dart`, `test/features/dating/report/restricted_screen_test.dart` and its goldens, `$D/{arb_fragment_T4.txt, edit_app_T4.py, mut_T4_dart.py}`; modifies the routes, the home model, the section, the text-scale audit and the manual.

**W7b.** Task 5 creates `supabase/migrations/20261121110000_dating_v2_moderation_console.sql`, `…110010_…_grants.sql`, `$D/{contract_T5.sql, edit_tests_T5.py, mut_T5.py}`; modifies the contract, the canary, `service_role_grants_test.sql`, `dating_v2_verification_contracts.sql`, `dating_v2_setup_contracts.sql`, `scripts/local_pg_grants.sql`. Task 6 creates `supabase/functions/dating-moderation/{handler.ts, request.ts, index.ts, handler.test.ts}`, `$D/{edit_ci_T6.py, mut_T6.py}`; modifies `tests.yml`, `config.toml`. Task 7 creates `lib/console/{main_console.dart, console_api.dart, console_auth.dart, console_app.dart, screens/queue_screen.dart, screens/case_screen.dart, screens/console_lists.dart}`, `web/index.html`, `test/console/{console_fakes.dart, console_test.dart}`, `$D/{edit_ci_T7.py, mut_T7_dart.py}`; modifies `tests.yml`.

**W7c.** Task 8 creates `$D/{before_w7c/, mig_T8_head.sql, build_mig_W7c.py, contract_T8.sql, edit_tests_T8.py, mut_T8.py}`, `supabase/migrations/20261121120000_dating_v2_escalations.sql`, `…120010_…_grants.sql`; modifies the contract, the canary, `service_role_grants_test.sql`, `scripts/local_pg_grants.sql`. Task 9 creates `lib/console/screens/law_enforcement_screen.dart`, `test/console/console_le_test.dart`, `$D/{edit_fn_T9.py, edit_app_T9.py, mut_T9.py, mut_T9_dart.py}`; modifies the edge function, its test, `console_app.dart`, `case_screen.dart`. Task 10 creates `lib/architecture/DATING_MODERATION_RUNBOOK.md`, `lib/architecture/DATING_LAW_ENFORCEMENT_POLICY.md`, `$D/edit_docs_T10.py`; modifies `lib/architecture/DATING_MODE_SPEC.md`, `lib/architecture/DATING_CHAT_SAFETY_SPEC.md`, the design spec (four amendment notes).

**Not edited:** `lib/main.dart`, `lib/app/app.dart`, `lib/app/routing/app_router.dart`, `lib/home/home_screen.dart`, `quick_exit_service.dart`, `auth_provider.dart`, `lib/features/chat/**`, `lib/features/games/**`, `lib/features/dating/chat/{dating_chat_repository,dating_chat_providers}.dart`, `test/features/dating/support/dating_chat_fakes.dart`, every applied migration, `scripts/local_pg_setup.sh`, every edge function but the new one, `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`, Opinions.

---

## Batch W7a — reports, restrictions, appeals, Report in the app

### Task 1: The W7 tool folder, the baselines, migration `dating_v2_reports` (reports v2, evidence, automatic steps, corroboration, cases, restrictions v2, the purge) and its contract A–D (§3.7, §4.3, §4.8, §4.9 W7a, §4.10, §6.2, §6.3, §7.1, §7.5 mutants 13–14; carries 6, 9, 10; R-49–R-53, R-57, R-63, R-65, R-66)

**Files:**
- Create: `$D/{mutate.py, splice.py, before_w7a/, sql-baseline.txt, analyze-baseline.txt, flutter-baseline.txt, mig_T1_head.sql, build_mig_W7a.py, edit_tests_T1.py, mut_T1.py}` (and `suite.sh`, `grants_line.py`, `dmut.py`, `denomut.py`, `anchor.py`, `marked_diff.py` copied from W6), `supabase/migrations/20261121100000_dating_v2_reports.sql`, `supabase/migrations/20261121100010_dating_v2_reports_grants.sql`, `supabase/tests/dating_v2_moderation_contracts.sql`
- Modify: `supabase/tests/{dating_rls_canary,service_role_grants_test,dating_mode_contracts}.sql`, `scripts/local_pg_grants.sql`

**Interfaces:**
- Consumes: the live bodies of the ten functions in Step 4 (read from `attune_spec3a`); W1's `dating_phone_hmac_for_user`, `private.dating_field_encrypt`, `private.dating_key_ok`; W3's `claim_dating_idempotency`, `check_dating_rate_limit`, `private.dating_lock_setup`; W5's `dating_moderation_cases`, `private.dating_open_signal_case`; W6's `dating_messages`, `dating_safety_events`, `private.dating_mark_pair`, `private.dating_bump_chat`, `private.dating_pair_blocked`, `block_dating_match`, `block_dating_introduction`.
- Produces: reports v2 (`dating_reports` columns, `dating_report_evidence`, `dating_case_matches`), restrictions v2 (`dating_account_restrictions` columns, `private.dating_restriction_defaults()`), `dating_appeals` (the table; Task 2 its functions), `dating_matches.low_phone_hmac`/`high_phone_hmac`, closed reason `reported`, `enforcement_records.case_id`; `private.dating_report_priority(text)`, `private.dating_report_sla_due(text, timestamptz)`, `private.dating_reporter_tripped(uuid, uuid)`, `private.dating_report_excluded(uuid)`, `private.dating_snapshot_evidence(uuid, uuid, text)`, `private.dating_report_case(uuid)`, `private.dating_report_corroborated(uuid)`, `private.dating_place_restriction(uuid, text, text, text, uuid, uuid, timestamptz, boolean)`, `private.dating_release_suspension(uuid)`, `private.dating_close_case(uuid, uuid, text)` (stamps `decided_at`, settles the case's reports), `private.dating_file_report(…)`, `private.dating_report_answer(uuid)`; `report_dating_match(text, uuid, text, text, boolean)`, `report_dating_introduction(text, uuid, text, text, boolean)`; health's W7 counters.

- [ ] **Step 1: Check the target and the free timestamps**

```bash
psql -X -d attune_spec3a -Atc 'select current_database()'
ls supabase/migrations | sort | tail -1
git rev-parse --short HEAD
```

Expected: `attune_spec3a`; `20261120120010_dating_v2_chat_guided_grants.sql`; `e4251c66` (or a later commit of the owner's: then read `git log --oneline e4251c66..HEAD` and say in the report what changed; the concurrent chat fix may land in between, see Global Constraints). If the last migration is at or after `20261121100000`, shift the six W7 timestamps (Global Constraints).

- [ ] **Step 2: The tool folder**

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7; mkdir -p $D/mut
for f in suite.sh grants_line.py dmut.py denomut.py anchor.py marked_diff.py; do cp .superpowers/sdd/2026-11-20-spec2-w6/$f $D/$f; done
sed -e 's/W6_DB/W7_DB/g' -e 's/Spec 2 W6 mutation runner/Spec 2 W7 mutation runner/' .superpowers/sdd/2026-11-20-spec2-w6/mutate.py > $D/mutate.py
chmod +x $D/suite.sh
grep -c W7_DB $D/mutate.py
```

Expected: `2`.

Create `$D/splice.py` with exactly:

```python
#!/usr/bin/env python3
# usage: splice.py <file> <marker> <section file>: the section goes in at
# the marker (which occurs exactly once; the section brings the next one).
import pathlib, sys
f, marker, sec = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])
s = f.read_text()
assert s.count(marker + '\n') == 1, f'{f}: marker {marker} occurs {s.count(marker)} times'
f.write_text(s.replace(marker + '\n', sec.read_text()))
print(f'{f}: {sec.name} spliced at {marker}')
```

- [ ] **Step 3: The baselines**

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
$D/suite.sh attune_spec3a > $D/sql-baseline.txt; echo "$(grep -c '^PASS' $D/sql-baseline.txt) PASS, $(grep -c '^FAIL' $D/sql-baseline.txt) FAIL"
flutter analyze --no-pub lib test > $D/analyze-baseline.txt 2>&1; tail -1 $D/analyze-baseline.txt
flutter test --no-pub --reporter compact > $D/flutter-baseline.txt 2>&1; tr '\r' '\n' < $D/flutter-baseline.txt | grep -E '^[0-9:]+ \+[0-9]+' | tail -1 | grep -oE '\+[0-9]+( ~[0-9]+)?( -[0-9]+)?: (All tests passed!|Some tests failed\.)'
shasum -c .superpowers/sdd/2026-11-04-spec1-w10-accessibility-docs/w10-1.0.sha | grep -vc ': OK$'
shasum -c .superpowers/sdd/2026-11-04-spec1-w9/flag_off.sha | grep -vc ': OK$'
shasum -c .superpowers/sdd/2026-11-07-spec2-w3/latch.sha
psql -X -d attune_spec3a -Atc "select key || '=' || enabled from public.feature_flags order by key" > $D/flags-baseline.txt; wc -l < $D/flags-baseline.txt | tr -d ' '
```

Expected: `161 PASS, 14 FAIL` (or `160 PASS, 15 FAIL` when `quiet_hours_contracts.sql` meets its clock-dependent hour); `571 issues found. (ran in …)`; `+8622 -3: Some tests failed.`, the three `test/accessibility/w10/healing_journal_large_text_test.dart` goldens (`journal list and entry, 390 wide, text 1.0`, `1.3`, `2.0`), which fail at `e4251c66` on their own too (the journal list's dates move with the day: a known flake, Global Constraints) — any other failure is named in the report; `0`; `0`; `lib/home/home_screen.dart: OK`; `44` (the feature flags, recorded for the W7c gate's "flags unchanged"). The full run takes 12–15 minutes on an idle machine; a known flake (Global Constraints) may fail it: name each in the report.

- [ ] **Step 4: Save the live bodies the migration re-creates**

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7; mkdir -p $D/before_w7a
for sig in 'public.enforce_dating_restriction_change()' 'public.dating_account_in_good_standing(uuid)' 'private.dating_generation_removed(uuid,timestamp with time zone,jsonb)' 'private.dating_purge_steps()' 'private.dating_purge_step(text,timestamp with time zone)' 'private.dating_open_chat_case(uuid,uuid,text,text)' 'private.dating_deletion_carry(uuid,boolean)' 'public.get_my_dating_matches(boolean)' 'public.get_dating_home()' 'public.get_dating_operational_health()'; do
  psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)" > "$D/before_w7a/$sig.sql"
done
ls $D/before_w7a | wc -l | tr -d ' '
```

Expected: `10`. (`get_dating_home()` is re-created by Task 2's edit only; the builder re-creates it once Task 2's section exists.)

- [ ] **Step 5: Write the failing contract**

Create `supabase/tests/dating_v2_moderation_contracts.sql` with exactly (sections A–D; Task 2 splices E–H at `-- @@W7A-T2@@`):

```sql
-- supabase/tests/dating_v2_moderation_contracts.sql
-- Spec 2 W7a (§3.7, §4.3, §4.8, §6.2, §6.3, §7.1, §7.2 S8, S11, §7.5
-- mutants 13-15; W6 carries T2 N-4, T5, T8, M-16): the 14 categories and
-- their priorities, the answers, the evidence, the report windows (A);
-- the automatic steps, never a ban (B); corroboration and credibility, the
-- holds (C); one case per person, every match linked and held from the
-- purge, a report about a deleted account (D). Task 2 adds what the
-- restricted person sees, the appeal, carry-over, deletion and release
-- (E onward). Fixture ids are 7a7000..-nn and phones +1555971nn, unique
-- in the suite; each section takes its own range of nn (A-D 01-59, E-H
-- 60-83, W7b I-M 85-129, W7c N-P 130-159).
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_moderation_contracts.sql
BEGIN;

DO $$
BEGIN
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w7-moderation-key', true);
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w7-field-key-0123456789abcdef-0123', true);
  PERFORM set_config('app.settings.dating_push_key', 'spec2-w7-push-key', true);
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
  SELECT ('7a700000-0000-0000-0000-' || lpad(p_n, 12, '0'))::uuid;
$$;
CREATE FUNCTION pg_temp.dev(p_n text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT md5('w7-device-' || p_n);
$$;
-- A current candidate (the chat contract's fixture person) with every
-- answer in [o] over the defaults; "phone" names another fixture's number
-- (the same person on a new account), "device" another's phone.
CREATE FUNCTION pg_temp.ready(p_n text, o jsonb DEFAULT '{}') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_u constant uuid := pg_temp.id(p_n);
  d constant jsonb := '{"identity": "woman", "seeking": ["man"], "country": "GH", "region": "AA", "years": 30,
    "days": 40, "phone": null, "device": null}'::jsonb || o;
  v_phone constant text := '+1555971' || coalesce(d ->> 'phone', p_n);
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (v_u, ltrim(v_phone, '+'), now(), now() - make_interval(days => (d ->> 'days')::int));
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (v_u, v_phone, 'Mod ' || p_n, 'dating', now() - make_interval(days => (d ->> 'days')::int), now(), '2');
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (v_u, (current_date - make_interval(years => (d ->> 'years')::int) - interval '10 days')::date);
  INSERT INTO public.dating_enrollments (user_id, state, opted_in_at, activated_at) VALUES (v_u, 'active', now(), now());
  INSERT INTO public.dating_profiles (user_id, display_name, profile_state, moderation_state, verification_state,
    country_code, region_code, intention, timeline_visible, not_married_attested_at, attestation_version,
    children_have, children_want, faith_visible)
  VALUES (v_u, 'Mod ' || p_n, 'active', 'approved', 'verified', d ->> 'country', d ->> 'region',
    'committed', true, now(), '2026-10-v1', false, 'yes', false);
  INSERT INTO public.dating_preferences (user_id, min_age, max_age, region_scope, open_abroad, want_must_match, exclude_parents)
  VALUES (v_u, 25, 40, 'region', '{}', false, false);
  INSERT INTO public.dating_profile_sensitive (user_id, identity_enc, seeking_enc)
  VALUES (v_u, private.dating_field_encrypt(jsonb_build_object('identity', d ->> 'identity', 'pools', jsonb_build_array(d ->> 'identity'))),
          private.dating_field_encrypt(jsonb_build_object('seeking', d -> 'seeking')));
  INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer, moderation_state)
  SELECT v_u, n, CASE n WHEN 1 THEN 'perfect_sunday' ELSE 'ask_me_about' END, 'A moderation fixture answer ' || n, 'approved'
    FROM generate_series(1, 2) AS n;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state, csam_state)
  SELECT v_u, 'w7/' || v_u || '/' || n || '.jpg', n, 'approved', 'clear' FROM generate_series(1, 2) AS n;
  INSERT INTO public.dating_age_verifications (user_id, age_method, age_result, age_vendor, age_decided_at,
    identity_method, identity_result, identity_vendor, identity_decided_at)
  VALUES (v_u, 'id', 'pass', 'contract', now(), 'liveness_compare', 'pass', 'contract', now());
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT v_u, 'w7-consent-' || p, p, 'granted', 'dating-2.0', clock_timestamp()
    FROM unnest(ARRAY['dating_terms', 'dating_opt_in', 'special_category_profile']) AS p;
  INSERT INTO public.dating_trusted_devices (user_id, device_hash, verified_at, last_seen_at)
  VALUES (v_u, encode(extensions.digest(pg_temp.dev(coalesce(d ->> 'device', p_n)), 'sha256'), 'hex'), now(), now());
  RETURN v_u;
END $$;
CREATE FUNCTION pg_temp.man(p_n text, o jsonb DEFAULT '{}') RETURNS uuid LANGUAGE sql AS $$
  SELECT pg_temp.ready(p_n, '{"identity": "man", "seeking": ["woman"]}'::jsonb || o);
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
-- [p_sql] as [p] on the phone [p_device] (NULL: no header); the error's
-- SQLSTATE and message when it raises.
CREATE FUNCTION pg_temp.call(p uuid, p_device text, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  PERFORM pg_temp.as_person(p, p_device);
  EXECUTE p_sql INTO v;
  PERFORM pg_temp.as_db();
  RETURN coalesce(v, '<NULL>');
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.as_db();
  RETURN SQLSTATE || ':' || SQLERRM;
END $$;
-- The same, as jsonb, on the person's own phone (a raised error is
-- {"raised": "<state>:<message>"}).
CREATE FUNCTION pg_temp.j(p uuid, p_n text, p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v text := pg_temp.call(p, pg_temp.dev(p_n), p_sql);
BEGIN
  RETURN v::jsonb;
EXCEPTION WHEN invalid_text_representation THEN
  RETURN jsonb_build_object('raised', v);
END $$;
-- Runs [p_setup] and [p_probe], then undoes both (a savepoint).
CREATE FUNCTION pg_temp.probe(p_setup text[], p_probe text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
  v_sql text;
BEGIN
  BEGIN
    FOREACH v_sql IN ARRAY p_setup LOOP
      EXECUTE v_sql;
    END LOOP;
    EXECUTE p_probe INTO v;
    RAISE EXCEPTION 'w7:probe_undo';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'w7:probe_undo' THEN
      RAISE;
    END IF;
  END;
  RETURN coalesce(v, '<NULL>');
END $$;
CREATE FUNCTION pg_temp.metric(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce((SELECT sum(c.count) FROM public.metric_counters AS c
                    WHERE c.day = (now() AT TIME ZONE 'utc')::date AND c.key = p_key), 0)::bigint;
$$;
CREATE FUNCTION pg_temp.key(p text) RETURNS text LANGUAGE sql AS $$
  SELECT 'w7-' || p || '-' || replace(gen_random_uuid()::text, '-', '');
$$;
-- An active match of two days, and its id.
CREATE FUNCTION pg_temp.match(p_a uuid, p_b uuid) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, matched_at, pair_key)
  VALUES (least(p_a, p_b), greatest(p_a, p_b), 'active', now() - interval '2 days', public.dating_pair_key(p_a, p_b))
  RETURNING id;
$$;
-- [p_n] messages from [p_from] in [p_m] (as stored by send), oldest first.
CREATE FUNCTION pg_temp.say(p_m uuid, p_from uuid, p_body text, p_n int DEFAULT 1) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.dating_messages (match_id, sender_side, sender_user_id, body, body_masked, mask_version, idempotency_key,
                                      created_at)
  SELECT p_m, CASE WHEN m.user_low_id = p_from THEN 'low' ELSE 'high' END, p_from, p_body || CASE WHEN p_n > 1 THEN ' ' || g ELSE '' END,
         p_body, 1, pg_temp.key('say'), clock_timestamp()
    FROM public.dating_matches AS m, generate_series(1, p_n) AS g WHERE m.id = p_m;
$$;
-- [p_by]'s report of [p_cat] on match [p_m]: the answer.
CREATE FUNCTION pg_temp.report(p_by uuid, p_n text, p_m uuid, p_cat text, p_block boolean DEFAULT false,
                               p_details text DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p_by, p_n, format('SELECT public.report_dating_match(%L, %L, %L, %L, %L)',
                                     pg_temp.key('r' || p_n), p_m, p_cat, p_details, p_block));
$$;
CREATE FUNCTION pg_temp.excluded(p uuid) RETURNS boolean LANGUAGE sql AS $$
  SELECT private.dating_generation_removed(p, now(), (private.dating_intro_config()).o_config);
$$;
CREATE FUNCTION pg_temp.marked(p_a uuid, p_b uuid) RETURNS boolean LANGUAGE sql AS $$
  SELECT EXISTS (SELECT 1 FROM public.dating_pair_markers AS k
                  WHERE k.pair_code = private.dating_pair_code(public.dating_phone_hmac_for_user(p_a),
                                                               public.dating_phone_hmac_for_user(p_b)));
$$;
-- The person's live restrictions, 'type/source/category/appealable', sorted.
CREATE FUNCTION pg_temp.held(p uuid) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce(string_agg(r.restriction_type || '/' || r.source || '/' || coalesce(r.category, '-') || '/' || r.appealable,
                             ' ' ORDER BY r.restriction_type), '')
    FROM public.dating_account_restrictions AS r
   WHERE r.user_id = p AND r.lifted_at IS NULL AND (r.ends_at IS NULL OR r.ends_at > now());
$$;
-- The full deletion path: prepare twice (delete-account retries), as the
-- service role, then Auth's delete.
CREATE FUNCTION pg_temp.delete_account(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM public.prepare_account_deletion(p);
  PERFORM public.prepare_account_deletion(p);
  RESET ROLE;
  DELETE FROM auth.users WHERE id = p;
END $$;

-- =====================================================================
-- A. (§3.7, §6.2, §7.2 S8) The 14 categories and their priorities; a
--    report's answer, its row (the match, the target and both numbers'
--    codes, the clock, the case), its evidence (the last 50 messages,
--    encrypted); invalid input; who may report and for how long (a match
--    open or ended within 30 days; a phone that isn't checked may report:
--    a safety write, as Block); a replay; the day's limit of 10.
-- =====================================================================
DO $a$
DECLARE
  v_a constant uuid := pg_temp.ready('01');
  v_b constant uuid := pg_temp.man('02');
  v_c constant uuid := pg_temp.man('03');
  v_d constant uuid := pg_temp.ready('04');
  v_e constant uuid := pg_temp.man('05');
  v_m uuid;
  v_old uuid;
  v_de uuid;
  v jsonb;
  v_again jsonb;
  v_key text := pg_temp.key('a-replay');
  v_r public.dating_reports;
  v_snap jsonb;
  v_n bigint := pg_temp.metric('dating.report.harassment');
  v_got text;
  i int;
BEGIN
  IF (SELECT string_agg(c || '=' || private.dating_report_priority(c), ' ' ORDER BY ord)
        FROM unnest(ARRAY['underage_risk', 'csam', 'child_safety', 'threat_to_life', 'sextortion', 'romance_scam', 'threats',
                          'entrapment', 'harassment', 'explicit_content', 'impersonation', 'hiding_relationship', 'spam',
                          'other']) WITH ORDINALITY AS x(c, ord))
     IS DISTINCT FROM 'underage_risk=P0 csam=P0 child_safety=P0 threat_to_life=P0 sextortion=P1 romance_scam=P1 threats=P1 '
                      'entrapment=P1 harassment=P2 explicit_content=P2 impersonation=P2 hiding_relationship=P2 spam=P3 other=P3'
     OR private.dating_report_priority('safety_concern') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the categories and priorities are not §3.7''s';
  END IF;
  -- The clock: four staffed hours for P0 (08:00-22:00 GMT), never past 24.
  IF private.dating_report_sla_due('P0', '2026-12-01 09:00+00') IS DISTINCT FROM '2026-12-01 13:00+00'::timestamptz
     OR private.dating_report_sla_due('P0', '2026-12-01 20:00+00') IS DISTINCT FROM '2026-12-02 10:00+00'::timestamptz
     OR private.dating_report_sla_due('P0', '2026-12-01 23:00+00') IS DISTINCT FROM '2026-12-02 12:00+00'::timestamptz
     OR private.dating_report_sla_due('P0', '2026-12-01 03:00+00') IS DISTINCT FROM '2026-12-01 12:00+00'::timestamptz
     OR private.dating_report_sla_due('P1', '2026-12-01 03:00+00') IS DISTINCT FROM '2026-12-02 03:00+00'::timestamptz
     OR private.dating_report_sla_due('P2', '2026-12-01 03:00+00') IS DISTINCT FROM '2026-12-03 03:00+00'::timestamptz
     OR private.dating_report_sla_due('P3', '2026-12-01 03:00+00') IS DISTINCT FROM '2026-12-04 03:00+00'::timestamptz THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the review clock is not §6.2''s';
  END IF;

  v_m := pg_temp.match(v_a, v_b);
  PERFORM pg_temp.say(v_m, v_b, 'w7-first-five', 5);
  PERFORM pg_temp.say(v_m, v_a, 'hello from a', 25);
  PERFORM pg_temp.say(v_m, v_b, 'w7-evidence-marker', 25);
  v := pg_temp.report(v_a, '01', v_m, 'harassment', false, '  He kept writing.  ');
  IF v IS DISTINCT FROM '{"ok": true, "review": "testing", "sla_hours": 48}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a report read % (ok, testing, 48 hours)', v;
  END IF;
  SELECT * INTO v_r FROM public.dating_reports WHERE reporter_user_id = v_a AND match_id = v_m;
  IF v_r.category <> 'harassment' OR v_r.priority <> 'P2' OR v_r.details IS DISTINCT FROM 'He kept writing.'
     OR v_r.target_user_id IS DISTINCT FROM v_b OR v_r.target_phone_hmac IS DISTINCT FROM public.dating_phone_hmac_for_user(v_b)
     OR v_r.reporter_phone_hmac IS DISTINCT FROM public.dating_phone_hmac_for_user(v_a)
     OR v_r.state <> 'open' OR v_r.case_id IS NULL OR v_r.introduction_id IS NOT NULL
     OR v_r.sla_due_at NOT BETWEEN now() + interval '47 hours 59 minutes' AND now() + interval '48 hours 1 minute' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the report row is wrong: %', to_jsonb(v_r) - 'details';
  END IF;
  -- Evidence: the last 50 of 55, both sides, oldest first, encrypted.
  IF (SELECT message_count FROM public.dating_report_evidence WHERE report_id = v_r.id) IS DISTINCT FROM 50
     OR (SELECT position('w7-evidence-marker' IN encode(snapshot_enc, 'escape')) FROM public.dating_report_evidence
          WHERE report_id = v_r.id) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the evidence is not 50 encrypted messages';
  END IF;
  v_snap := private.dating_field_decrypt((SELECT snapshot_enc FROM public.dating_report_evidence WHERE report_id = v_r.id));
  IF jsonb_array_length(v_snap -> 'messages') <> 50
     OR v_snap #>> '{messages,0,text}' IS DISTINCT FROM 'hello from a 1'
     OR v_snap #>> '{messages,0,from}' IS DISTINCT FROM 'reporter'
     OR v_snap #>> '{messages,49,from}' IS DISTINCT FROM 'reported'
     OR v_snap #>> '{messages,49,text}' IS DISTINCT FROM 'w7-evidence-marker 25'
     OR (SELECT count(*) FROM jsonb_array_elements(v_snap -> 'messages') AS e WHERE e ->> 'text' LIKE 'w7-first-five%') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the evidence is not the last 50 messages, both sides: %', v_snap #> '{messages,0}';
  END IF;
  IF pg_temp.metric('dating.report.harassment') IS DISTINCT FROM v_n + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the report was not counted under its category';
  END IF;
  -- Invalid input names nothing; a non-member reads report_unavailable.
  v_got := concat_ws(' ',
    pg_temp.report(v_a, '01', v_m, 'safety_concern') ->> 'reason',
    pg_temp.report(v_a, '01', v_m, 'spam', false, repeat('x', 501)) ->> 'reason',
    pg_temp.report(v_a, '01', NULL, 'spam') ->> 'reason',
    pg_temp.j(v_a, '01', format('SELECT public.report_dating_match(''short'', %L, ''spam'', NULL, false)', v_m)) ->> 'reason',
    pg_temp.j(v_a, '01', format('SELECT public.report_dating_match(%L, %L, ''spam'', NULL, NULL)', pg_temp.key('n'), v_m)) ->> 'reason',
    pg_temp.report(v_c, '03', v_m, 'spam') ->> 'reason',
    pg_temp.report(v_c, '03', gen_random_uuid(), 'spam') ->> 'reason');
  IF v_got IS DISTINCT FROM 'invalid invalid invalid invalid invalid report_unavailable report_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: invalid input or a stranger read %', v_got;
  END IF;
  -- A replay answers the same and files nothing more.
  -- (Every call that writes is its own statement: an IF's OR has no order.)
  v := pg_temp.j(v_a, '01', format('SELECT public.report_dating_match(%L, %L, ''spam'', NULL, false)', v_key, v_m));
  v_again := pg_temp.j(v_a, '01', format('SELECT public.report_dating_match(%L, %L, ''spam'', NULL, false)', v_key, v_m));
  IF v IS DISTINCT FROM v_again OR (v ->> 'sla_hours') IS DISTINCT FROM '72'
     OR (SELECT count(*) FROM public.dating_reports WHERE reporter_user_id = v_a AND category = 'spam') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replay filed a second report or answered differently';
  END IF;
  -- An ended match within its 30 days may be reported; past them, not.
  -- A phone that isn't checked may report (no header at all).
  UPDATE public.dating_matches SET state = 'unmatched', closed_reason = 'unmatched', closed_at = now() - interval '29 days',
         evidence_until = now() + interval '1 day' WHERE id = v_m;
  v_got := pg_temp.call(v_a, NULL, format('SELECT public.report_dating_match(%L, %L, ''other'', NULL, false) ->> ''ok''',
                                          pg_temp.key('a-nophone'), v_m));
  v_old := pg_temp.match(v_a, v_c);
  UPDATE public.dating_matches SET state = 'unmatched', closed_reason = 'unmatched', closed_at = now() - interval '31 days',
         evidence_until = now() - interval '1 day' WHERE id = v_old;
  v := pg_temp.report(v_a, '01', v_old, 'other');
  IF v_got IS DISTINCT FROM 'true' OR v ->> 'reason' IS DISTINCT FROM 'report_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 30-day window (or the phoneless report) read %', v_got;
  END IF;
  -- 10 a day (the existing limit).
  v_de := pg_temp.match(v_d, v_e);
  FOR i IN 1..10 LOOP
    IF (pg_temp.report(v_d, '04', v_de, 'spam') ->> 'ok') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: report % of the day was refused', i;
    END IF;
  END LOOP;
  IF pg_temp.report(v_d, '04', v_de, 'spam') ->> 'reason' IS DISTINCT FROM 'rate_limited' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 11th report of the day was not rate_limited';
  END IF;
  -- Without the field key the report stands, without evidence, counted.
  v_got := pg_temp.probe(ARRAY[$p$SELECT set_config('app.settings.dating_field_key', '', true)$p$],
    format($p$SELECT (pg_temp.report(%L, '05', %L, 'threats') ->> 'ok') || '/'
                     || (SELECT count(*) FROM public.dating_report_evidence AS e JOIN public.dating_reports AS r ON r.id = e.report_id
                          WHERE r.reporter_user_id = %L AND r.category = 'threats') || '/'
                     || pg_temp.metric('dating.report.evidence_unavailable')$p$, v_e, v_de, v_e));
  IF v_got IS DISTINCT FROM 'true/0/' || (pg_temp.metric('dating.report.evidence_unavailable') + 1) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without the field key a report read % (true/0/counted)', v_got;
  END IF;
END $a$;

-- =====================================================================
-- B. (§6.2, §7.5 mutant 13) The automatic steps, never a ban: one P0
--    report closes the reporter's match (reported, 30-day window, never
--    introduced again) and removes the person from new generation, but
--    holds nothing; P1 removes from generation; P2's step is the
--    reporter's own block; impersonation takes no step beyond it; P3
--    takes none. A card on Today can be reported too.
-- =====================================================================
DO $b$
DECLARE
  v_a constant uuid := pg_temp.ready('10');
  v_b constant uuid := pg_temp.man('11');
  v_c constant uuid := pg_temp.ready('12');
  v_d constant uuid := pg_temp.man('13');
  v_e constant uuid := pg_temp.ready('14');
  v_f constant uuid := pg_temp.man('15');
  v_g constant uuid := pg_temp.ready('16');
  v_h constant uuid := pg_temp.man('17');
  v_k constant uuid := pg_temp.man('18');
  v_m uuid;
  v_m2 uuid;
  v_m3 uuid;
  v_m4 uuid;
  v_m5 uuid;
  v_i uuid;
  v jsonb;
  v_got text;
BEGIN
  v_m := pg_temp.match(v_a, v_b);
  v := pg_temp.report(v_a, '10', v_m, 'threat_to_life');
  IF (v ->> 'ok') IS DISTINCT FROM 'true' OR (v ->> 'sla_hours')::int NOT BETWEEN 1 AND 24 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a P0 report read %', v;
  END IF;
  IF (SELECT state || '/' || closed_reason || '/' || (evidence_until > now() + interval '29 days')::text
        FROM public.dating_matches WHERE id = v_m) IS DISTINCT FROM 'closed/reported/true'
     OR NOT pg_temp.marked(v_a, v_b)
     OR NOT EXISTS (SELECT 1 FROM public.dating_chat_signals WHERE user_id = v_b AND match_id = v_m) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a P0 report did not close the reporter''s match for good, or the other was not told';
  END IF;
  IF pg_temp.held(v_b) <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one P0 report placed a hold (§6.2: only when corroborated): %', pg_temp.held(v_b);
  END IF;
  IF NOT pg_temp.excluded(v_b) OR NOT public.dating_candidate_is_current(v_b) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a P0 report did not remove the person from new generation only (excluded %, current %)',
      pg_temp.excluded(v_b), public.dating_candidate_is_current(v_b);
  END IF;
  IF (SELECT c.kind || '/' || c.priority || '/' || c.state FROM public.dating_moderation_cases AS c
       JOIN public.dating_reports AS r ON r.case_id = c.id WHERE r.match_id = v_m) IS DISTINCT FROM 'report/P0/open' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the P0 report has no open P0 case';
  END IF;
  -- P1: removed from generation; the match stays (no block asked).
  v_m2 := pg_temp.match(v_c, v_d);
  PERFORM pg_temp.report(v_c, '12', v_m2, 'romance_scam');
  IF (SELECT state FROM public.dating_matches WHERE id = v_m2) <> 'active' OR NOT pg_temp.excluded(v_d) OR pg_temp.held(v_d) <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a P1 report did more or less than remove the person from generation';
  END IF;
  -- P2 with the block (the toggle's default): blocked, nothing else.
  v_m3 := pg_temp.match(v_e, v_f);
  PERFORM pg_temp.report(v_e, '14', v_m3, 'harassment', true);
  IF (SELECT state || '/' || closed_reason FROM public.dating_matches WHERE id = v_m3) IS DISTINCT FROM 'blocked/blocked'
     OR NOT EXISTS (SELECT 1 FROM public.dating_blocks WHERE blocker_user_id = v_e AND blocked_user_id = v_f)
     OR pg_temp.excluded(v_f) OR pg_temp.held(v_f) <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a P2 report with the block did not block only';
  END IF;
  -- §6.2: impersonation takes no automatic step beyond the reporter's
  -- block; P3 takes none.
  v_m4 := pg_temp.match(v_g, v_h);
  PERFORM pg_temp.report(v_g, '16', v_m4, 'impersonation', true);
  v_m5 := pg_temp.match(v_g, v_k);
  PERFORM pg_temp.report(v_g, '16', v_m5, 'spam');
  IF pg_temp.excluded(v_h) OR pg_temp.held(v_h) <> '' OR (SELECT state FROM public.dating_matches WHERE id = v_m4) <> 'blocked'
     OR (SELECT auto_step FROM public.dating_reports WHERE match_id = v_m4)
     OR pg_temp.excluded(v_k) OR (SELECT state FROM public.dating_matches WHERE id = v_m5) <> 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: impersonation or spam took an automatic step';
  END IF;
  -- A card on Today: a P0 report without the block takes the card away
  -- and the pair is never introduced again; no evidence (no messages).
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version,
                                           visible_from_low, visible_from_high, expires_at)
  VALUES (public.dating_pair_key(v_c, v_k), least(v_c, v_k), greatest(v_c, v_k), 'presented', 'introductions_v2',
          now() - interval '1 hour', now() - interval '1 hour', now() + interval '6 days')
  RETURNING id INTO v_i;
  v := pg_temp.j(v_c, '12', format('SELECT public.report_dating_introduction(%L, %L, ''child_safety'', NULL, false)',
                                   pg_temp.key('b-card'), v_i));
  v_got := pg_temp.j(v_f, '15', format('SELECT public.report_dating_introduction(%L, %L, ''spam'', NULL, false)',
                                       pg_temp.key('b-card2'), v_i)) ->> 'reason';
  IF (v ->> 'ok') IS DISTINCT FROM 'true' OR (SELECT state FROM public.dating_introductions WHERE id = v_i) <> 'invalidated'
     OR NOT pg_temp.marked(v_c, v_k) OR NOT pg_temp.excluded(v_k)
     OR EXISTS (SELECT 1 FROM public.dating_report_evidence AS e JOIN public.dating_reports AS r ON r.id = e.report_id
                 WHERE r.introduction_id = v_i)
     OR v_got IS DISTINCT FROM 'report_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a card report read % (a stranger: %)', v, v_got;
  END IF;
END $b$;

-- =====================================================================
-- C. (§6.2, §6.3, §7.2 S2, S11, §7.5 mutant 14) Corroboration and
--    credibility: two independent P0 reports hold the person (matches
--    stay open, no sending, hidden from Today); the same reporter twice,
--    a reporter under 72 hours, two reporters on one phone, or a
--    reporter whose own messages tripped sexual_pressure or
--    financial_request, never count; underage_risk with the person's
--    tier-3 age_signal (or a second underage_risk) is an age review that
--    closes every match; a CSAM hit holds at once.
-- =====================================================================
DO $c$
DECLARE
  v_t constant uuid := pg_temp.man('20');
  v_r1 constant uuid := pg_temp.ready('21');
  v_r2 constant uuid := pg_temp.ready('22');
  v_r3 constant uuid := pg_temp.ready('23');
  v_t2 constant uuid := pg_temp.man('24');
  v_young constant uuid := pg_temp.ready('25', '{"days": 2}');
  v_twin constant uuid := pg_temp.ready('26', '{"device": "21"}');
  v_t3 constant uuid := pg_temp.man('27');
  v_trip constant uuid := pg_temp.ready('28');
  v_r5 constant uuid := pg_temp.ready('29');
  v_t4 constant uuid := pg_temp.man('30');
  v_r6 constant uuid := pg_temp.ready('31');
  v_r7 constant uuid := pg_temp.ready('32');
  v_t5 constant uuid := pg_temp.man('33');
  v_r8 constant uuid := pg_temp.ready('34');
  v_m1 uuid;
  v_m2 uuid;
  v_m3 uuid;
  v_n bigint := pg_temp.metric('dating.hold.p0');
  v_case uuid;
  v_got text;
BEGIN
  v_m1 := pg_temp.match(v_t, v_r1);
  v_m2 := pg_temp.match(v_t, v_r2);
  v_m3 := pg_temp.match(v_t, v_r3);
  PERFORM pg_temp.report(v_r1, '21', v_m1, 'csam');
  IF pg_temp.held(v_t) <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one P0 report held the person';
  END IF;
  PERFORM pg_temp.report(v_r2, '22', v_m2, 'threat_to_life');
  SELECT case_id INTO v_case FROM public.dating_reports WHERE match_id = v_m2;
  IF pg_temp.held(v_t) IS DISTINCT FROM 'moderation_hold/report/threat_to_life/false'
     OR (SELECT case_id FROM public.dating_account_restrictions WHERE user_id = v_t) IS DISTINCT FROM v_case
     OR pg_temp.metric('dating.hold.p0') IS DISTINCT FROM v_n + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two independent P0 reports did not hold (%)', pg_temp.held(v_t);
  END IF;
  -- §6.3: a hold keeps the other match open, stops the person's messages,
  -- and hides them.
  v_got := pg_temp.j(v_t, '20', format('SELECT public.send_dating_message(%L, %L, ''hello'')', pg_temp.key('c-send'), v_m3)) ->> 'ok';
  IF (SELECT state FROM public.dating_matches WHERE id = v_m3) <> 'active'
     OR v_got IS DISTINCT FROM 'false'
     OR public.dating_candidate_is_current(v_t)
     OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_t) <> 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the hold closed a match, let the person send, or left them on Today';
  END IF;
  IF (SELECT count(*) FROM public.dating_case_matches WHERE case_id = v_case) <> 2
     OR (SELECT count(*) FROM public.dating_reports WHERE case_id = v_case) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the two reports are not one case linking both matches';
  END IF;
  -- The same reporter twice, a new account, a second account on the first
  -- reporter's phone: none corroborates.
  PERFORM pg_temp.report(v_r1, '21', pg_temp.match(v_t2, v_r1), 'csam');
  -- The same account on a new number, its phone forgotten (only the
  -- account says it is the same reporter).
  UPDATE auth.users SET phone = '15559719921' WHERE id = v_r1;
  DELETE FROM public.dating_trusted_devices WHERE user_id = v_r1;
  PERFORM pg_temp.report(v_r1, '21', (SELECT id FROM public.dating_matches WHERE user_low_id = least(v_t2, v_r1)
                                        AND user_high_id = greatest(v_t2, v_r1)), 'child_safety');
  INSERT INTO public.dating_trusted_devices (user_id, device_hash, verified_at, last_seen_at)
  VALUES (v_r1, encode(extensions.digest(pg_temp.dev('21'), 'sha256'), 'hex'), now(), now());
  PERFORM pg_temp.report(v_young, '25', pg_temp.match(v_t2, v_young), 'csam');
  PERFORM pg_temp.report(v_twin, '26', pg_temp.match(v_t2, v_twin), 'csam');
  IF pg_temp.held(v_t2) <> '' OR (SELECT counts_for_corroboration FROM public.dating_reports WHERE reporter_user_id = v_young) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a repeat, a new account or one phone corroborated a hold: %', pg_temp.held(v_t2);
  END IF;
  -- A reporter whose own messages to the person tripped financial_request
  -- in that match: no automatic step, never counts (S11); the case shows
  -- the family.
  v_m1 := pg_temp.match(v_t3, v_trip);
  INSERT INTO public.dating_safety_events (match_id, at_risk_user_id, sender_user_id, rule_id, family, tier, config_version,
                                           source_event_key)
  VALUES (v_m1, v_t3, v_trip, 'financial_request:momo', 'financial_request', 2, 'dating_chat_v1', 'w7-c-trip');
  PERFORM pg_temp.report(v_trip, '28', v_m1, 'underage_risk');
  IF (SELECT reporter_tripped_family || '/' || counts_for_corroboration || '/' || auto_step FROM public.dating_reports
       WHERE reporter_user_id = v_trip) IS DISTINCT FROM 'financial_request/false/false'
     OR pg_temp.excluded(v_t3) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a tripped reporter''s report took a step or counts';
  END IF;
  PERFORM pg_temp.report(v_r5, '29', pg_temp.match(v_t3, v_r5), 'underage_risk');
  IF pg_temp.held(v_t3) <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a tripped reporter''s report corroborated a hold (mutant 14): %', pg_temp.held(v_t3);
  END IF;
  -- underage_risk and the person's own tier-3 age_signal in that match: an
  -- age review, every match closed as age_review (S2).
  v_m1 := pg_temp.match(v_t4, v_r6);
  v_m2 := pg_temp.match(v_t4, v_r7);
  INSERT INTO public.dating_safety_events (match_id, at_risk_user_id, sender_user_id, rule_id, family, tier, config_version,
                                           source_event_key)
  VALUES (v_m1, v_r6, v_t4, 'age_signal:shs', 'age_signal', 3, 'dating_chat_v1', 'w7-c-age');
  PERFORM pg_temp.report(v_r6, '31', v_m1, 'underage_risk');
  IF pg_temp.held(v_t4) IS DISTINCT FROM 'age_review/report/underage_risk/false'
     OR (SELECT count(*) FROM public.dating_matches WHERE id IN (v_m1, v_m2) AND closed_reason = 'age_review') <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: underage_risk with an age signal read % and did not close every match as age_review',
      pg_temp.held(v_t4);
  END IF;
  -- A CSAM hit holds at once (source csam_hash), matches stay open.
  v_m1 := pg_temp.match(v_t5, v_r8);
  PERFORM public.record_dating_csam_hold(v_t5);
  IF pg_temp.held(v_t5) IS DISTINCT FROM 'moderation_hold/csam_hash/csam/false'
     OR (SELECT state FROM public.dating_matches WHERE id = v_m1) <> 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a CSAM hit read % (a hold at once, matches open)', pg_temp.held(v_t5);
  END IF;
  -- One writer: a live restriction of a type is never doubled.
  IF private.dating_place_restriction(v_t5, 'moderation_hold', 'csam', 'report', NULL, NULL, NULL, false)
       IS DISTINCT FROM (SELECT id FROM public.dating_account_restrictions WHERE user_id = v_t5) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second hold was placed';
  END IF;
END $c$;

-- =====================================================================
-- D. (§4.3, §4.8, W6 M-16, R-52) One open report case per person: a
--    later report joins it (its priority and clock the most urgent), and
--    every match it comes from is linked and held from the purge while it
--    is open, released once it closes; a signal case links a later hit's
--    match; a report after the other's deletion keeps the number's code,
--    and the next account on that number is out of new generation while
--    the case is open; its block is kept by number.
-- =====================================================================
DO $d$
DECLARE
  v_t constant uuid := pg_temp.man('40');
  v_a constant uuid := pg_temp.ready('41');
  v_b constant uuid := pg_temp.ready('42');
  v_s constant uuid := pg_temp.man('43');
  v_x constant uuid := pg_temp.ready('44');
  v_y constant uuid := pg_temp.ready('45');
  v_g constant uuid := pg_temp.man('46');
  v_h constant uuid := pg_temp.ready('47');
  v_g2 uuid;
  v_m1 uuid;
  v_m2 uuid;
  v_case uuid;
  v_hold_case uuid;
  v_hmac text;
  v jsonb;
BEGIN
  v_m1 := pg_temp.match(v_t, v_a);
  v_m2 := pg_temp.match(v_t, v_b);
  PERFORM pg_temp.report(v_a, '41', v_m1, 'spam');
  PERFORM pg_temp.report(v_b, '42', v_m2, 'sextortion');
  SELECT id INTO v_case FROM public.dating_moderation_cases WHERE kind = 'report' AND target_user_id = v_t;
  IF (SELECT count(*) FROM public.dating_moderation_cases WHERE kind = 'report' AND target_user_id = v_t) <> 1
     OR (SELECT priority FROM public.dating_moderation_cases WHERE id = v_case) <> 'P1'
     OR (SELECT sla_due_at FROM public.dating_moderation_cases WHERE id = v_case)
        IS DISTINCT FROM (SELECT min(sla_due_at) FROM public.dating_reports WHERE case_id = v_case)
     OR (SELECT count(*) FROM public.dating_case_matches WHERE case_id = v_case) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two reports about one person are not one P1 case linking both matches';
  END IF;
  -- The second match (not the case's own) ends past its window: held by
  -- the link while the case is open, purged once it is closed.
  UPDATE public.dating_matches SET state = 'unmatched', closed_reason = 'unmatched', closed_at = now() - interval '40 days',
         evidence_until = now() - interval '10 days' WHERE id = v_m2;
  PERFORM public.purge_dating_retention(now());
  IF NOT EXISTS (SELECT 1 FROM public.dating_matches WHERE id = v_m2) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge deleted a match an open case links (W6 M-16)';
  END IF;
  IF private.dating_close_case(v_case, v_a, 'dismissed') IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the case would not close';
  END IF;
  PERFORM public.purge_dating_retention(now());
  IF EXISTS (SELECT 1 FROM public.dating_matches WHERE id = v_m2) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closed case still holds its linked match';
  END IF;
  -- A signal case links the match of a later hit (W6 M-16).
  v_m1 := pg_temp.match(v_s, v_x);
  v_m2 := pg_temp.match(v_s, v_y);
  PERFORM private.dating_open_chat_case(v_s, v_m1, 'chat_financial_request', 'P1');
  PERFORM private.dating_open_chat_case(v_s, v_m2, 'chat_financial_request', 'P1');
  IF (SELECT count(*) FROM public.dating_case_matches AS l JOIN public.dating_moderation_cases AS c ON c.id = l.case_id
       WHERE c.target_user_id = v_s AND c.signal_kind = 'chat_financial_request') <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a later hit''s match was not linked to the open signal case';
  END IF;
  -- The other's account is deleted: the match keeps their number's code,
  -- the report names it, and the next account on that number is out of
  -- new generation while the case is open. The block is kept by number.
  v_m1 := pg_temp.match(v_g, v_h);
  v_hmac := public.dating_phone_hmac_for_user(v_g);
  PERFORM pg_temp.delete_account(v_g);
  IF (SELECT CASE WHEN user_low_id IS NULL THEN low_phone_hmac ELSE high_phone_hmac END FROM public.dating_matches WHERE id = v_m1)
       IS DISTINCT FROM v_hmac THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the deleted side''s number''s code is not on the match';
  END IF;
  v := pg_temp.report(v_h, '47', v_m1, 'threats', true);
  IF (v ->> 'ok') IS DISTINCT FROM 'true'
     OR (SELECT target_user_id IS NULL AND target_phone_hmac = v_hmac FROM public.dating_reports WHERE match_id = v_m1) IS NOT TRUE
     OR NOT EXISTS (SELECT 1 FROM public.dating_block_hmacs
                     WHERE blocker_hmac = public.dating_phone_hmac_for_user(v_h) AND blocked_hmac = v_hmac) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a report after the other''s deletion lost the number or its block';
  END IF;
  v_g2 := pg_temp.man('48', '{"phone": "46"}');
  IF NOT pg_temp.excluded(v_g2) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new account on the reported number is in new generation while the case is open';
  END IF;
  -- §4.8 (W6 T8 carry): reports go at 2 years, unless their case is still
  -- open; evidence 180 days after its case closed, unless a restriction
  -- from that case is still live.
  v_m1 := pg_temp.match(v_x, v_y);
  PERFORM pg_temp.say(v_m1, v_y, 'w7-d-purge', 1);
  PERFORM pg_temp.report(v_x, '44', v_m1, 'spam');
  PERFORM pg_temp.report(v_y, '45', v_m1, 'harassment');
  SELECT case_id INTO v_case FROM public.dating_reports WHERE reporter_user_id = v_x AND match_id = v_m1;
  PERFORM private.dating_close_case(v_case, v_x, 'dismissed');
  UPDATE public.dating_moderation_cases SET decided_at = now() - interval '181 days' WHERE id = v_case;
  UPDATE public.dating_reports SET created_at = now() - interval '2 years 1 day' WHERE case_id = v_case;
  SELECT case_id INTO v_hold_case FROM public.dating_reports WHERE reporter_user_id = v_y AND match_id = v_m1;
  PERFORM private.dating_close_case(v_hold_case, v_y, 'restricted');
  UPDATE public.dating_moderation_cases SET decided_at = now() - interval '200 days' WHERE id = v_hold_case;
  PERFORM private.dating_place_restriction(v_x, 'suspended', 'harassment', 'moderator', v_hold_case, v_y, NULL, true);
  PERFORM public.purge_dating_retention(now());
  IF EXISTS (SELECT 1 FROM public.dating_reports WHERE case_id = v_case)
     OR NOT EXISTS (SELECT 1 FROM public.dating_reports WHERE case_id = v_hold_case)
     OR NOT EXISTS (SELECT 1 FROM public.dating_report_evidence AS e JOIN public.dating_reports AS r ON r.id = e.report_id
                     WHERE r.case_id = v_hold_case) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge kept a 2-year report, or took evidence a live restriction needs';
  END IF;
  UPDATE public.dating_account_restrictions SET lifted_at = now() WHERE case_id = v_hold_case;
  PERFORM public.purge_dating_retention(now());
  IF EXISTS (SELECT 1 FROM public.dating_report_evidence AS e JOIN public.dating_reports AS r ON r.id = e.report_id
              WHERE r.case_id = v_hold_case)
     OR NOT EXISTS (SELECT 1 FROM public.dating_reports WHERE case_id = v_hold_case) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: evidence outlived its closed case by 180 days, or the report went with it';
  END IF;
  UPDATE public.dating_reports SET created_at = now() - interval '2 years 1 day' WHERE reporter_user_id = v_h;
  PERFORM public.purge_dating_retention(now());
  IF NOT EXISTS (SELECT 1 FROM public.dating_reports WHERE reporter_user_id = v_h) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge deleted a report whose case is still open';
  END IF;
END $d$;

-- @@W7A-T2@@

DO $$ BEGIN RAISE NOTICE 'dating_v2_moderation_contracts: all held'; END $$;
ROLLBACK;
```

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_moderation_contracts.sql 2>&1 | grep -m1 -oE 'ERROR: .*'
```

Expected: `ERROR:  column r.source does not exist` (section A's first read of restrictions v2).

- [ ] **Step 6: Write the migration**

Create `$D/mig_T1_head.sql` with exactly (sections 1–12 of the migration: the categories and the clock, reports v2, evidence, cases and their links, restrictions v2, appeals, the match's phone codes, the helpers, the report RPCs; Task 2's section goes in at `-- @@W7A-T2@@`):

```sql
-- ---------------------------------------------------------------------
-- 1. Categories, priorities and the review clock (§3.7, §6.2).
-- ---------------------------------------------------------------------
-- The 14 categories of §3.7 and their priority; NULL is no category.
CREATE OR REPLACE FUNCTION private.dating_report_priority(p_category text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE p_category
    WHEN 'underage_risk' THEN 'P0' WHEN 'csam' THEN 'P0' WHEN 'child_safety' THEN 'P0' WHEN 'threat_to_life' THEN 'P0'
    WHEN 'sextortion' THEN 'P1' WHEN 'romance_scam' THEN 'P1' WHEN 'threats' THEN 'P1' WHEN 'entrapment' THEN 'P1'
    WHEN 'harassment' THEN 'P2' WHEN 'explicit_content' THEN 'P2' WHEN 'impersonation' THEN 'P2'
    WHEN 'hiding_relationship' THEN 'P2'
    WHEN 'spam' THEN 'P3' WHEN 'other' THEN 'P3' END;
$$;

-- §6.2's human targets. P0: four staffed hours (08:00-22:00 GMT, every
-- day), never more than 24 hours; P1 24 h, P2 48 h, P3 72 h (Ruling R-50).
CREATE OR REPLACE FUNCTION private.dating_report_sla_due(p_priority text, p_at timestamptz)
RETURNS timestamptz
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_local timestamp := p_at AT TIME ZONE 'UTC';
  v_day timestamp := date_trunc('day', p_at AT TIME ZONE 'UTC');
  v_due timestamp;
BEGIN
  IF p_at IS NULL THEN
    RETURN NULL;
  END IF;
  CASE p_priority
  WHEN 'P0' THEN
    IF v_local < v_day + interval '8 hours' THEN
      v_due := v_day + interval '12 hours';
    ELSIF v_local < v_day + interval '18 hours' THEN
      v_due := v_local + interval '4 hours';
    ELSIF v_local < v_day + interval '22 hours' THEN
      v_due := v_day + interval '1 day 8 hours' + (interval '4 hours' - (v_day + interval '22 hours' - v_local));
    ELSE
      v_due := v_day + interval '1 day 12 hours';
    END IF;
    RETURN least(v_due AT TIME ZONE 'UTC', p_at + interval '24 hours');
  WHEN 'P1' THEN RETURN p_at + interval '24 hours';
  WHEN 'P2' THEN RETURN p_at + interval '48 hours';
  WHEN 'P3' THEN RETURN p_at + interval '72 hours';
  ELSE RETURN NULL;
  END CASE;
END;
$$;

-- ---------------------------------------------------------------------
-- 2. Reports v2 (§4.3, §6.2): the match or introduction, the priority,
--    the reporter's number's code (corroboration, R-49), credibility, the
--    state and the case. Old v1 categories are mapped (Ruling R-49).
-- ---------------------------------------------------------------------
ALTER TABLE public.dating_reports
  ADD COLUMN IF NOT EXISTS match_id uuid,
  ADD COLUMN IF NOT EXISTS introduction_id uuid,
  ADD COLUMN IF NOT EXISTS reporter_phone_hmac text,
  ADD COLUMN IF NOT EXISTS priority text,
  ADD COLUMN IF NOT EXISTS reporter_tripped_family text,
  ADD COLUMN IF NOT EXISTS counts_for_corroboration boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS auto_step boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS state text NOT NULL DEFAULT 'open',
  ADD COLUMN IF NOT EXISTS sla_due_at timestamptz,
  ADD COLUMN IF NOT EXISTS case_id uuid,
  ADD COLUMN IF NOT EXISTS request_key text;
CREATE UNIQUE INDEX IF NOT EXISTS dating_reports_request_key_idx ON public.dating_reports (reporter_user_id, request_key)
  WHERE request_key IS NOT NULL;
ALTER TABLE public.dating_reports DROP CONSTRAINT IF EXISTS dating_reports_category_check;
UPDATE public.dating_reports
   SET category = CASE category WHEN 'safety_concern' THEN 'other' WHEN 'sexual_content' THEN 'explicit_content' END
 WHERE category IN ('safety_concern', 'sexual_content');
-- A row written without them (W1's fixtures, a definer's insert) takes its
-- priority and its clock from its category.
CREATE OR REPLACE FUNCTION private.dating_report_defaults()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.priority := coalesce(NEW.priority, private.dating_report_priority(NEW.category));
  NEW.sla_due_at := coalesce(NEW.sla_due_at, private.dating_report_sla_due(NEW.priority, coalesce(NEW.created_at, now())));
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS dating_reports_defaults ON public.dating_reports;
CREATE TRIGGER dating_reports_defaults BEFORE INSERT ON public.dating_reports
  FOR EACH ROW EXECUTE FUNCTION private.dating_report_defaults();
UPDATE public.dating_reports SET priority = private.dating_report_priority(category) WHERE priority IS NULL;
UPDATE public.dating_reports SET sla_due_at = private.dating_report_sla_due(priority, created_at) WHERE sla_due_at IS NULL;
ALTER TABLE public.dating_reports ALTER COLUMN priority SET NOT NULL;
ALTER TABLE public.dating_reports ADD CONSTRAINT dating_reports_category_check CHECK (category IN (
  'underage_risk', 'csam', 'child_safety', 'threat_to_life', 'sextortion', 'romance_scam', 'threats', 'entrapment',
  'harassment', 'explicit_content', 'impersonation', 'hiding_relationship', 'spam', 'other'));
ALTER TABLE public.dating_reports DROP CONSTRAINT IF EXISTS dating_reports_priority_check;
ALTER TABLE public.dating_reports ADD CONSTRAINT dating_reports_priority_check CHECK (priority IN ('P0', 'P1', 'P2', 'P3'));
ALTER TABLE public.dating_reports DROP CONSTRAINT IF EXISTS dating_reports_state_check;
ALTER TABLE public.dating_reports ADD CONSTRAINT dating_reports_state_check
  CHECK (state IN ('open', 'in_review', 'upheld', 'not_upheld', 'closed_no_action'));
ALTER TABLE public.dating_reports DROP CONSTRAINT IF EXISTS dating_reports_reporter_phone_hmac_check;
ALTER TABLE public.dating_reports ADD CONSTRAINT dating_reports_reporter_phone_hmac_check
  CHECK (reporter_phone_hmac IS NULL OR reporter_phone_hmac ~ '^[0-9a-f]{64}$');
ALTER TABLE public.dating_reports DROP CONSTRAINT IF EXISTS dating_reports_tripped_check;
ALTER TABLE public.dating_reports ADD CONSTRAINT dating_reports_tripped_check
  CHECK (reporter_tripped_family IS NULL OR reporter_tripped_family IN ('sexual_pressure', 'financial_request'));
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint WHERE conname = 'dating_reports_match_id_fkey') THEN
    ALTER TABLE public.dating_reports ADD CONSTRAINT dating_reports_match_id_fkey
      FOREIGN KEY (match_id) REFERENCES public.dating_matches (id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint WHERE conname = 'dating_reports_introduction_id_fkey') THEN
    ALTER TABLE public.dating_reports ADD CONSTRAINT dating_reports_introduction_id_fkey
      FOREIGN KEY (introduction_id) REFERENCES public.dating_introductions (id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint WHERE conname = 'dating_reports_case_id_fkey') THEN
    ALTER TABLE public.dating_reports ADD CONSTRAINT dating_reports_case_id_fkey
      FOREIGN KEY (case_id) REFERENCES public.dating_moderation_cases (id) ON DELETE SET NULL;
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS dating_reports_case_idx ON public.dating_reports (case_id);
CREATE INDEX IF NOT EXISTS dating_reports_target_idx ON public.dating_reports (target_user_id);
CREATE INDEX IF NOT EXISTS dating_reports_target_hmac_idx ON public.dating_reports (target_phone_hmac);
CREATE INDEX IF NOT EXISTS dating_reports_reporter_idx ON public.dating_reports (reporter_user_id, created_at);
CREATE INDEX IF NOT EXISTS dating_reports_created_idx ON public.dating_reports (created_at);

-- Evidence (§6.2): the last 50 messages of the conversation, both sides,
-- encrypted with the field key; kept until the case closes + 180 days, or
-- while an enforcement record from it lasts (§4.8; the purge decides).
CREATE TABLE IF NOT EXISTS public.dating_report_evidence (
  report_id uuid PRIMARY KEY REFERENCES public.dating_reports (id) ON DELETE CASCADE,
  snapshot_enc bytea NOT NULL,
  message_count integer NOT NULL CHECK (message_count BETWEEN 0 AND 50),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.dating_report_evidence ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------
-- 3. Cases (§4.3): one open report case per person (by account, or by
--    the number's code once the account is gone); appeals are cases too.
--    Every match a case's evidence comes from is linked (W6 M-16), and
--    the purge's hold reads the link.
-- ---------------------------------------------------------------------
ALTER TABLE public.dating_moderation_cases ADD COLUMN IF NOT EXISTS appeal_id uuid;
CREATE UNIQUE INDEX IF NOT EXISTS dating_moderation_cases_open_report_idx
  ON public.dating_moderation_cases (target_user_id)
  WHERE kind = 'report' AND state IN ('open', 'in_review') AND target_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS dating_moderation_cases_report_hmac_idx
  ON public.dating_moderation_cases (target_phone_hmac) WHERE kind = 'report';
CREATE TABLE IF NOT EXISTS public.dating_case_matches (
  case_id uuid NOT NULL REFERENCES public.dating_moderation_cases (id) ON DELETE CASCADE,
  match_id uuid NOT NULL REFERENCES public.dating_matches (id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (case_id, match_id)
);
CREATE INDEX IF NOT EXISTS dating_case_matches_match_idx ON public.dating_case_matches (match_id);
ALTER TABLE public.dating_case_matches ENABLE ROW LEVEL SECURITY;
INSERT INTO public.dating_case_matches (case_id, match_id)
SELECT c.id, c.match_id FROM public.dating_moderation_cases AS c WHERE c.match_id IS NOT NULL
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- 4. Restrictions v2 (§4.3, §6.3): the category shown, where it came
--    from, its case, who decided, whether it can be appealed, and the
--    record it was carried from. Rows inserted without a source take one
--    from their type (the CSAM paths' holds, W4's age reviews; R-51).
-- ---------------------------------------------------------------------
ALTER TABLE public.dating_account_restrictions
  ADD COLUMN IF NOT EXISTS category text,
  ADD COLUMN IF NOT EXISTS source text,
  ADD COLUMN IF NOT EXISTS case_id uuid,
  ADD COLUMN IF NOT EXISTS decided_by uuid,
  ADD COLUMN IF NOT EXISTS appealable boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS carried_from uuid;
ALTER TABLE public.dating_account_restrictions DROP CONSTRAINT IF EXISTS dating_account_restrictions_category_check;
ALTER TABLE public.dating_account_restrictions ADD CONSTRAINT dating_account_restrictions_category_check
  CHECK (category IS NULL OR category IN (
    'underage_risk', 'csam', 'child_safety', 'threat_to_life', 'sextortion', 'romance_scam', 'threats', 'entrapment',
    'harassment', 'explicit_content', 'impersonation', 'hiding_relationship', 'spam', 'other'));
ALTER TABLE public.dating_account_restrictions DROP CONSTRAINT IF EXISTS dating_account_restrictions_source_check;
ALTER TABLE public.dating_account_restrictions ADD CONSTRAINT dating_account_restrictions_source_check
  CHECK (source IN ('report', 'moderator', 'csam_hash', 'age_assurance', 'carried_over'));
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint WHERE conname = 'dating_account_restrictions_case_id_fkey') THEN
    ALTER TABLE public.dating_account_restrictions ADD CONSTRAINT dating_account_restrictions_case_id_fkey
      FOREIGN KEY (case_id) REFERENCES public.dating_moderation_cases (id) ON DELETE SET NULL;
  END IF;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS dating_account_restrictions_carried_idx
  ON public.dating_account_restrictions (user_id, carried_from) WHERE carried_from IS NOT NULL;

CREATE OR REPLACE FUNCTION private.dating_restriction_defaults()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.source IS NULL THEN
    NEW.source := CASE NEW.restriction_type WHEN 'moderation_hold' THEN 'csam_hash'
                                            WHEN 'age_review' THEN 'age_assurance'
                                            ELSE 'moderator' END;
    IF NEW.category IS NULL THEN
      NEW.category := CASE NEW.restriction_type WHEN 'moderation_hold' THEN 'csam'
                                                WHEN 'age_review' THEN 'underage_risk' END;
    END IF;
  END IF;
  -- §6.3: a hold is not appealable until decided, an age review goes
  -- through the ID check, a closer look is never shown; a carried
  -- restriction keeps its one appeal (§6.3), unless it is an age review.
  IF NEW.restriction_type IN ('age_review', 'under_review')
     OR (NEW.restriction_type = 'moderation_hold' AND NEW.source IS DISTINCT FROM 'carried_over') THEN
    NEW.appealable := false;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS dating_account_restrictions_defaults ON public.dating_account_restrictions;
CREATE TRIGGER dating_account_restrictions_defaults
  BEFORE INSERT ON public.dating_account_restrictions
  FOR EACH ROW EXECUTE FUNCTION private.dating_restriction_defaults();
UPDATE public.dating_account_restrictions
   SET source = CASE restriction_type WHEN 'moderation_hold' THEN 'csam_hash' WHEN 'age_review' THEN 'age_assurance'
                                      ELSE 'moderator' END,
       category = coalesce(category, CASE restriction_type WHEN 'moderation_hold' THEN 'csam'
                                                           WHEN 'age_review' THEN 'underage_risk' END),
       appealable = restriction_type = 'suspended'
 WHERE source IS NULL;
ALTER TABLE public.dating_account_restrictions ALTER COLUMN source SET NOT NULL;

-- Appeals (§3.7, §6.3): one per restriction, decided by another person.
CREATE TABLE IF NOT EXISTS public.dating_appeals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restriction_id uuid NOT NULL UNIQUE REFERENCES public.dating_account_restrictions (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users (id) ON DELETE CASCADE,
  text text CHECK (text IS NULL OR char_length(text) BETWEEN 1 AND 500),
  submitted_at timestamptz NOT NULL DEFAULT now(),
  state text NOT NULL DEFAULT 'open' CHECK (state IN ('open', 'accepted', 'rejected')),
  decided_by uuid,
  decided_at timestamptz,
  CHECK ((state = 'open') = (decided_at IS NULL)),
  CHECK ((state = 'open') = (decided_by IS NULL))
);
CREATE INDEX IF NOT EXISTS dating_appeals_user_idx ON public.dating_appeals (user_id, decided_at);
ALTER TABLE public.dating_appeals ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint WHERE conname = 'dating_moderation_cases_appeal_id_fkey') THEN
    ALTER TABLE public.dating_moderation_cases ADD CONSTRAINT dating_moderation_cases_appeal_id_fkey
      FOREIGN KEY (appeal_id) REFERENCES public.dating_appeals (id) ON DELETE CASCADE;
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- 5. Matches and enforcement records (§6.2, §6.3): a match closed by a
--    P0 report says so; each side's number's code is kept on the match
--    when that side's account is deleted, so the other can still report
--    for 30 days (R-52); a carried record names its case.
-- ---------------------------------------------------------------------
ALTER TABLE public.dating_matches
  ADD COLUMN IF NOT EXISTS low_phone_hmac text,
  ADD COLUMN IF NOT EXISTS high_phone_hmac text;
ALTER TABLE public.dating_matches DROP CONSTRAINT IF EXISTS dating_matches_phone_hmac_check;
ALTER TABLE public.dating_matches ADD CONSTRAINT dating_matches_phone_hmac_check
  CHECK ((low_phone_hmac IS NULL OR low_phone_hmac ~ '^[0-9a-f]{64}$')
         AND (high_phone_hmac IS NULL OR high_phone_hmac ~ '^[0-9a-f]{64}$'));
DO $$
DECLARE
  v_name text;
BEGIN
  SELECT c.conname INTO v_name FROM pg_catalog.pg_constraint AS c
   WHERE c.conrelid = 'public.dating_matches'::regclass AND c.contype = 'c'
     AND pg_catalog.pg_get_constraintdef(c.oid) LIKE '%closed_reason%' AND pg_catalog.pg_get_constraintdef(c.oid) LIKE '%unmatched%';
  IF v_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.dating_matches DROP CONSTRAINT %I', v_name);
  END IF;
END $$;
ALTER TABLE public.dating_matches ADD CONSTRAINT dating_matches_closed_reason_check CHECK (closed_reason IS NULL OR closed_reason IN (
  'unmatched', 'blocked', 'closed_kindly', 'exit', 'account_restricted', 'age_review', 'age_verification_invalid',
  'couple_linked', 'other_linked', 'account_deleted', 'reported', 'other'));
ALTER TABLE public.enforcement_records ADD COLUMN IF NOT EXISTS case_id uuid;

-- ---------------------------------------------------------------------
-- 6. The report's pieces.
-- ---------------------------------------------------------------------
-- §6.2 credibility: the reporter's own messages to the target in this
-- match tripped sexual_pressure or financial_request (the family only).
CREATE OR REPLACE FUNCTION private.dating_reporter_tripped(p_reporter uuid, p_match uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT min(e.family) FROM public.dating_safety_events AS e
   WHERE p_match IS NOT NULL AND p_reporter IS NOT NULL
     AND e.match_id = p_match AND e.sender_user_id = p_reporter
     AND e.family IN ('sexual_pressure', 'financial_request');
$$;

-- §6.2: removed from new generation while an open report case holds a
-- credible P0 or P1 report about the person (by account or number).
CREATE OR REPLACE FUNCTION private.dating_report_excluded(p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT p_user IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.dating_reports AS r
      JOIN public.dating_moderation_cases AS c ON c.id = r.case_id
     WHERE c.kind = 'report' AND c.state IN ('open', 'in_review')
       AND r.auto_step AND r.priority IN ('P0', 'P1')
       AND (c.target_user_id = p_user
            OR c.target_phone_hmac = public.dating_phone_hmac_for_user(p_user)));
$$;

-- §6.2 evidence: the last 50 messages of the conversation, both sides, as
-- the reporter's and the other person's, encrypted. -1: no field key
-- (counted; the report stands without it).
CREATE OR REPLACE FUNCTION private.dating_snapshot_evidence(p_report uuid, p_match uuid, p_reporter_side text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_json jsonb;
  v_n integer;
  v_enc bytea;
BEGIN
  IF p_match IS NULL THEN
    RETURN 0;
  END IF;
  SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'from', CASE WHEN x.sender_side = p_reporter_side THEN 'reporter' ELSE 'reported' END,
           'kind', x.kind, 'at', x.created_at, 'text', x.body) ORDER BY x.created_at, x.id), '[]'::jsonb),
         count(*)::int
    INTO v_json, v_n
    FROM (SELECT d.id, d.sender_side, d.kind, d.created_at, d.body FROM public.dating_messages AS d
           WHERE d.match_id = p_match ORDER BY d.created_at DESC, d.id DESC LIMIT 50) AS x;
  BEGIN
    v_enc := private.dating_field_encrypt(pg_catalog.jsonb_build_object('v', 1, 'messages', v_json));
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'dating:field_key_missing' THEN
      RAISE;
    END IF;
    PERFORM private.bump_metric_internal('dating.report.evidence_unavailable');
    RETURN -1;
  END;
  INSERT INTO public.dating_report_evidence (report_id, snapshot_enc, message_count)
  VALUES (p_report, v_enc, v_n)
  ON CONFLICT (report_id) DO NOTHING;
  RETURN v_n;
END;
$$;

-- One open report case per person: the report joins it (its priority and
-- clock the most urgent of its reports), and its match is linked.
CREATE OR REPLACE FUNCTION private.dating_report_case(p_report uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  r public.dating_reports;
  v_case uuid;
BEGIN
  SELECT * INTO r FROM public.dating_reports AS x WHERE x.id = p_report;
  SELECT c.id INTO v_case FROM public.dating_moderation_cases AS c
   WHERE c.kind = 'report' AND c.state IN ('open', 'in_review')
     AND ((r.target_user_id IS NOT NULL AND c.target_user_id = r.target_user_id)
          OR (r.target_phone_hmac IS NOT NULL AND c.target_phone_hmac = r.target_phone_hmac))
   ORDER BY (c.target_user_id = r.target_user_id) DESC NULLS LAST, c.created_at
   LIMIT 1
   FOR UPDATE;
  IF v_case IS NULL THEN
    INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, target_phone_hmac, report_id, match_id, sla_due_at)
    VALUES ('report', r.priority, r.target_user_id, r.target_phone_hmac, r.id, r.match_id, r.sla_due_at)
    RETURNING id INTO v_case;
  ELSE
    UPDATE public.dating_moderation_cases AS c
       SET priority = least(c.priority, r.priority),
           sla_due_at = least(c.sla_due_at, r.sla_due_at),
           target_user_id = coalesce(c.target_user_id, r.target_user_id),
           target_phone_hmac = coalesce(c.target_phone_hmac, r.target_phone_hmac)
     WHERE c.id = v_case;
  END IF;
  UPDATE public.dating_reports AS x SET case_id = v_case WHERE x.id = r.id;
  IF r.match_id IS NOT NULL THEN
    INSERT INTO public.dating_case_matches (case_id, match_id) VALUES (v_case, r.match_id) ON CONFLICT DO NOTHING;
  END IF;
  RETURN v_case;
END;
$$;

-- §6.2 corroboration for an interim hold: another counting P0 report in
-- an open case about the same person, from another account on another
-- number, the two reporters sharing no phone; or, for underage_risk, a
-- tier-3 age_signal the person sent in this match. 'age_review' when
-- both sides are about age, else 'moderation_hold'; NULL: no hold.
CREATE OR REPLACE FUNCTION private.dating_report_corroborated(p_report uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  r public.dating_reports;
  v_other text;
  v_age boolean;
BEGIN
  SELECT * INTO r FROM public.dating_reports AS x WHERE x.id = p_report;
  IF r.id IS NULL OR NOT r.counts_for_corroboration OR r.priority <> 'P0' OR r.target_user_id IS NULL THEN
    RETURN NULL;
  END IF;
  SELECT o.category INTO v_other
    FROM public.dating_reports AS o
    JOIN public.dating_moderation_cases AS c ON c.id = o.case_id
   WHERE c.kind = 'report' AND c.state IN ('open', 'in_review')
     AND o.id <> r.id AND o.counts_for_corroboration AND o.priority = 'P0'
     AND (o.target_user_id = r.target_user_id OR o.target_phone_hmac = r.target_phone_hmac)
     AND o.reporter_user_id IS DISTINCT FROM r.reporter_user_id
     AND o.reporter_phone_hmac IS NOT NULL AND r.reporter_phone_hmac IS NOT NULL
     AND o.reporter_phone_hmac <> r.reporter_phone_hmac
     AND NOT EXISTS (SELECT 1 FROM public.dating_trusted_devices AS a
                       JOIN public.dating_trusted_devices AS b ON b.device_hash = a.device_hash
                      WHERE a.user_id = o.reporter_user_id AND b.user_id = r.reporter_user_id)
   ORDER BY (o.category = 'underage_risk') DESC
   LIMIT 1;
  v_age := r.category = 'underage_risk' AND r.match_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.dating_safety_events AS e
     WHERE e.match_id = r.match_id AND e.family = 'age_signal' AND e.sender_user_id = r.target_user_id);
  IF r.category = 'underage_risk' AND (v_age OR v_other = 'underage_risk') THEN
    RETURN 'age_review';
  END IF;
  RETURN CASE WHEN v_other IS NOT NULL THEN 'moderation_hold' END;
END;
$$;

-- The one writer of a restriction (W7a holds; W7b's console decisions):
-- a live one of the same type is kept, never doubled.
CREATE OR REPLACE FUNCTION private.dating_place_restriction(p_user uuid, p_type text, p_category text, p_source text,
                                                            p_case uuid, p_decided_by uuid, p_ends_at timestamptz,
                                                            p_appealable boolean)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id uuid;
BEGIN
  SELECT r.id INTO v_id FROM public.dating_account_restrictions AS r
   WHERE r.user_id = p_user AND r.restriction_type = p_type AND r.lifted_at IS NULL
     AND r.starts_at <= now() AND (r.ends_at IS NULL OR r.ends_at > now())
   ORDER BY r.created_at LIMIT 1;
  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, case_id, decided_by,
                                                  ends_at, appealable)
  VALUES (p_user, p_type, p_category, p_source, p_case, p_decided_by, p_ends_at, coalesce(p_appealable, true))
  RETURNING id INTO v_id;
  IF p_source = 'report' AND p_type IN ('moderation_hold', 'age_review') THEN
    PERFORM private.bump_metric_internal('dating.hold.p0');
  END IF;
  RETURN v_id;
END;
$$;

-- The shared core of both report RPCs (the caller holds the reporter's
-- setup lock and the target's report lock): the report, its evidence, its
-- case, its count, and a corroborated hold. Returns the report's id.
CREATE OR REPLACE FUNCTION private.dating_file_report(p_reporter uuid, p_target uuid, p_target_hmac text, p_match uuid,
                                                      p_intro uuid, p_category text, p_details text, p_reporter_side text,
                                                      p_key text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_priority constant text := private.dating_report_priority(p_category);
  v_tripped constant text := private.dating_reporter_tripped(p_reporter, p_match);
  v_hmac constant text := public.dating_phone_hmac_for_user(p_reporter);
  v_old_enough boolean;
  v_id uuid;
  v_case uuid;
  v_hold text;
BEGIN
  v_old_enough := coalesce((SELECT u.created_at <= now() - interval '72 hours' FROM public.users AS u WHERE u.id = p_reporter), false);
  INSERT INTO public.dating_reports (reporter_user_id, target_user_id, target_phone_hmac, reporter_phone_hmac, category,
                                     details, match_id, introduction_id, priority, reporter_tripped_family,
                                     counts_for_corroboration, auto_step, sla_due_at, request_key)
  VALUES (p_reporter, p_target, p_target_hmac, v_hmac, p_category, p_details, p_match, p_intro, v_priority, v_tripped,
          v_priority = 'P0' AND v_tripped IS NULL AND v_old_enough AND v_hmac IS NOT NULL,
          -- §6.2: P0 and P1 remove from new generation; impersonation and
          -- the other P2/P3 categories take no automatic step.
          v_tripped IS NULL AND v_priority IN ('P0', 'P1'),
          private.dating_report_sla_due(v_priority, now()), p_key)
  RETURNING id INTO v_id;
  IF p_target_hmac IS NULL THEN
    PERFORM private.bump_metric_internal('dating.report.hmac_missing');
  END IF;
  PERFORM private.dating_snapshot_evidence(v_id, p_match, p_reporter_side);
  v_case := private.dating_report_case(v_id);
  PERFORM private.bump_metric_internal('dating.report.' || p_category);
  v_hold := private.dating_report_corroborated(v_id);
  IF v_hold IS NOT NULL THEN
    PERFORM private.dating_place_restriction(p_target, v_hold, p_category, 'report', v_case, NULL, NULL, false);
  END IF;
  RETURN v_id;
END;
$$;

-- What a sent report answers: whether a person reads it yet, and in how
-- many hours at most (from its clock).
CREATE OR REPLACE FUNCTION private.dating_report_answer(p_report uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT pg_catalog.jsonb_build_object('ok', true,
           'review', CASE WHEN private.attune_environment() = 'production' THEN 'staffed' ELSE 'testing' END,
           'sla_hours', greatest(1, ceil(extract(epoch FROM (r.sla_due_at - r.created_at)) / 3600)::int))
    FROM public.dating_reports AS r WHERE r.id = p_report;
$$;

-- A suspension that ended (lifted, or past its date) leaves Dating
-- paused, never suspended for good: the person resumes when ready
-- (R-53). The lift does it at once (the restriction trigger); Task 2's
-- cron does it for one that ran out.
CREATE OR REPLACE FUNCTION private.dating_release_suspension(p_user uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.dating_enrollments AS e
     SET state = 'paused', paused_at = coalesce(e.paused_at, now()), pause_reason = coalesce(e.pause_reason, 'gates'),
         updated_at = now()
   WHERE e.user_id = p_user AND e.state = 'suspended'
     AND NOT EXISTS (SELECT 1 FROM public.dating_account_restrictions AS r
                      WHERE r.user_id = p_user AND r.restriction_type IN ('suspended', 'age_review')
                        AND r.lifted_at IS NULL AND r.starts_at <= now() AND (r.ends_at IS NULL OR r.ends_at > now()));
  RETURN FOUND;
END;
$$;

-- ---------------------------------------------------------------------
-- 7. The report RPCs v2 (§3.7, §6.2). A safety write: no phone check and
--    no eligibility check (as Block, R-36); only membership. 10 a day.
--    From a match: while it is open, and for 30 days after it ended for
--    any reason (unmatch, block, close, the other's deletion), including
--    a chat only the two numbers' block ended (W6 T2 N-4).
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.report_dating_match(text, uuid, text, text);
DROP FUNCTION IF EXISTS public.report_dating_introduction(text, uuid, text, text);
DROP FUNCTION IF EXISTS public.submit_dating_report(text, uuid, text, text);

CREATE OR REPLACE FUNCTION public.report_dating_match(p_idempotency_key text, p_match_id uuid, p_category text,
                                                      p_details text, p_also_block boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_details constant text := NULLIF(btrim(coalesce(p_details, '')), '');
  v_m public.dating_matches;
  v_other uuid;
  v_hmac text;
  v_side text;
  v_report uuid;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_match_id IS NULL OR NOT private.dating_key_ok(p_idempotency_key) OR private.dating_report_priority(p_category) IS NULL
     OR coalesce(char_length(v_details), 0) > 500 OR p_also_block IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(v_user);
      IF EXISTS (SELECT 1 FROM public.dating_rpc_idempotency AS k
                  WHERE k.user_id = v_user AND k.operation = 'report_dating_match' AND k.idempotency_key = p_idempotency_key) THEN
        SELECT r.id INTO v_report FROM public.dating_reports AS r
         WHERE r.reporter_user_id = v_user AND r.request_key = 'match:' || p_idempotency_key;
        RETURN coalesce(private.dating_report_answer(v_report), pg_catalog.jsonb_build_object('ok', true));
      END IF;
      -- The match without a lock (who is in it never changes but to NULL),
      -- then the target's report lock, then the match row (send's order).
      SELECT * INTO v_m FROM public.dating_matches AS m
       WHERE m.id = p_match_id AND v_user IN (m.user_low_id, m.user_high_id);
      IF NOT FOUND
         OR NOT (v_m.state = 'active' OR v_m.evidence_until > now()) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'report_unavailable');
      END IF;
      v_side := CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END;
      v_other := CASE WHEN v_side = 'low' THEN v_m.user_high_id ELSE v_m.user_low_id END;
      v_hmac := coalesce(public.dating_phone_hmac_for_user(v_other),
                         CASE WHEN v_side = 'low' THEN v_m.high_phone_hmac ELSE v_m.low_phone_hmac END);
      PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('dating_report_target'),
                                               pg_catalog.hashtext(coalesce(v_hmac, v_other::text, p_match_id::text)));
      SELECT * INTO v_m FROM public.dating_matches AS m WHERE m.id = p_match_id FOR UPDATE;
      BEGIN
        PERFORM public.check_dating_rate_limit('report', 10, interval '1 day');
      EXCEPTION WHEN invalid_parameter_value THEN
        IF SQLERRM IS DISTINCT FROM 'rate_limited' THEN
          RAISE;
        END IF;
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'rate_limited');
      END;
      PERFORM public.claim_dating_idempotency('report_dating_match', p_idempotency_key);
      v_report := private.dating_file_report(v_user, v_other, v_hmac, p_match_id, NULL, p_category, v_details, v_side,
                                             'match:' || p_idempotency_key);
      IF p_also_block AND v_other IS NOT NULL THEN
        PERFORM public.block_dating_match(p_idempotency_key, p_match_id);
      ELSIF p_also_block AND v_hmac IS NOT NULL AND public.dating_phone_hmac_for_user(v_user) IS NOT NULL THEN
        -- The other account is gone: the block is kept by number.
        INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac, purge_after)
        VALUES (public.dating_phone_hmac_for_user(v_user), v_hmac, now() + interval '2 years')
        ON CONFLICT (blocker_hmac, blocked_hmac) DO NOTHING;
      END IF;
      -- §6.2 P0: the reporter's match closes (once a report is in, the
      -- pair is never introduced again).
      IF private.dating_report_priority(p_category) = 'P0' AND v_m.state = 'active'
         AND EXISTS (SELECT 1 FROM public.dating_matches AS m WHERE m.id = p_match_id AND m.state = 'active') THEN
        UPDATE public.dating_matches AS m
           SET state = 'closed', closed_reason = 'reported', closed_at = coalesce(m.closed_at, now()),
               evidence_until = now() + interval '30 days'
         WHERE m.id = p_match_id AND m.state = 'active';
        IF v_other IS NOT NULL THEN
          PERFORM private.dating_mark_pair(v_user, v_other);
        END IF;
        PERFORM private.dating_bump_chat(x.u, p_match_id)
           FROM (VALUES (v_user), (v_other)) AS x(u) WHERE x.u IS NOT NULL;
      END IF;
      RETURN private.dating_report_answer(v_report);
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- From a card on Today (an introduction the reporter is in, any state,
-- while it exists): no evidence (there is no conversation).
CREATE OR REPLACE FUNCTION public.report_dating_introduction(p_idempotency_key text, p_introduction_id uuid,
                                                             p_category text, p_details text,
                                                             p_also_block boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_details constant text := NULLIF(btrim(coalesce(p_details, '')), '');
  v_other uuid;
  v_hmac text;
  v_report uuid;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_introduction_id IS NULL OR NOT private.dating_key_ok(p_idempotency_key) OR private.dating_report_priority(p_category) IS NULL
     OR coalesce(char_length(v_details), 0) > 500 OR p_also_block IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(v_user);
      IF EXISTS (SELECT 1 FROM public.dating_rpc_idempotency AS k
                  WHERE k.user_id = v_user AND k.operation = 'report_dating_introduction' AND k.idempotency_key = p_idempotency_key) THEN
        SELECT r.id INTO v_report FROM public.dating_reports AS r
         WHERE r.reporter_user_id = v_user AND r.request_key = 'card:' || p_idempotency_key;
        RETURN coalesce(private.dating_report_answer(v_report), pg_catalog.jsonb_build_object('ok', true));
      END IF;
      SELECT CASE WHEN i.user_low_id = v_user THEN i.user_high_id ELSE i.user_low_id END INTO v_other
        FROM public.dating_introductions AS i
       WHERE i.id = p_introduction_id AND v_user IN (i.user_low_id, i.user_high_id);
      IF NOT FOUND OR v_other IS NULL THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'report_unavailable');
      END IF;
      v_hmac := public.dating_phone_hmac_for_user(v_other);
      PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('dating_report_target'),
                                               pg_catalog.hashtext(coalesce(v_hmac, v_other::text)));
      BEGIN
        PERFORM public.check_dating_rate_limit('report', 10, interval '1 day');
      EXCEPTION WHEN invalid_parameter_value THEN
        IF SQLERRM IS DISTINCT FROM 'rate_limited' THEN
          RAISE;
        END IF;
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'rate_limited');
      END;
      PERFORM public.claim_dating_idempotency('report_dating_introduction', p_idempotency_key);
      v_report := private.dating_file_report(v_user, v_other, v_hmac, NULL, p_introduction_id, p_category, v_details, NULL,
                                             'card:' || p_idempotency_key);
      IF p_also_block THEN
        PERFORM public.block_dating_introduction(p_idempotency_key, p_introduction_id);
      ELSIF private.dating_report_priority(p_category) = 'P0' THEN
        UPDATE public.dating_introductions AS i SET state = 'invalidated'
         WHERE i.id = p_introduction_id AND i.state IN ('generated', 'presented', 'interested');
        PERFORM private.dating_mark_pair(v_user, v_other);
      END IF;
      RETURN private.dating_report_answer(v_report);
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- ---------------------------------------------------------------------
-- 7b. Closing a case (W7b's console calls it, never a client): it always
--     stamps decided_at (W6 T5: the cleared-signal filter reads it) and
--     settles the case's reports.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.dating_close_case(p_case uuid, p_decider uuid, p_outcome text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_state text;
BEGIN
  IF p_outcome IS NULL OR p_outcome NOT IN ('dismissed', 'held', 'restricted', 'asked_for_id', 'no_action', 'orphaned',
                                            'accepted', 'rejected') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  SELECT c.state INTO v_state FROM public.dating_moderation_cases AS c WHERE c.id = p_case FOR UPDATE;
  IF v_state IS NULL OR v_state NOT IN ('open', 'in_review') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
  END IF;
  UPDATE public.dating_moderation_cases AS c
     SET state = CASE WHEN p_outcome IN ('no_action', 'orphaned') THEN 'closed' ELSE 'decided' END,
         decided_at = now(), outcome = p_outcome, assigned_to = coalesce(c.assigned_to, p_decider)
   WHERE c.id = p_case;
  UPDATE public.dating_reports AS r
     SET state = CASE WHEN p_outcome IN ('held', 'restricted', 'asked_for_id') THEN 'upheld'
                      WHEN p_outcome = 'dismissed' THEN 'not_upheld' ELSE 'closed_no_action' END
   WHERE r.case_id = p_case;
  RETURN pg_catalog.jsonb_build_object('ok', true);
END;
$$;

-- @@W7A-T2@@
```

Create `$D/build_mig_W7a.py` with exactly:

```python
#!/usr/bin/env python3
"""Spec 2 W7a: builds supabase/migrations/20261121100000_dating_v2_reports.sql
from mig_T1_head.sql (with Task 2's mig_T2.sql at its marker, when it
exists), the functions below re-created from their LIVE bodies (saved to
before_w7a/ before the migration is applied) with only the lines marked
"-- Spec 2 W7a" changed, and the self-revoke tail. Every anchor must occur
exactly once."""
import pathlib

D = pathlib.Path('.superpowers/sdd/2026-11-21-spec2-w7')
B = D / 'before_w7a'
T = 'Spec 2 W7a'

EDITS = {
    # §6.3, §4.10: per type. A hold hides the person and stops their
    # messages (good standing), matches stay open; an age review or a
    # suspension closes them; a closer look shows nothing. A lift releases
    # an ended suspension to a pause.
    'public.enforce_dating_restriction_change()': [
        ("""  IF NEW.lifted_at IS NULL AND NEW.starts_at <= now()
     AND (NEW.ends_at IS NULL OR NEW.ends_at > now()) THEN
""", f"""  IF NEW.lifted_at IS NULL AND NEW.starts_at <= now()
     AND (NEW.ends_at IS NULL OR NEW.ends_at > now()) THEN
   IF NEW.restriction_type IN ('suspended', 'age_review') THEN -- {T} (§6.3): these close every match
"""),
        ("""      CASE WHEN NEW.restriction_type = 'age_review' THEN 'age_review' ELSE 'account_restricted' END); -- Spec 2 W4a
  END IF;
""", f"""      CASE WHEN NEW.restriction_type = 'age_review' THEN 'age_review' ELSE 'account_restricted' END); -- Spec 2 W4a
   ELSIF NEW.restriction_type = 'moderation_hold' THEN -- {T} (§6.3): hidden from introductions, matches stay open
    PERFORM public.invalidate_dating_for_user(NEW.user_id, 'moderation_hold'); -- {T}: introductions only
   END IF; -- {T}: under_review shows nothing (generation leaves the person out)
  ELSIF TG_OP = 'UPDATE' AND NEW.lifted_at IS NOT NULL AND OLD.lifted_at IS NULL THEN -- {T} (R-53)
    PERFORM private.dating_release_suspension(NEW.user_id); -- {T}: an ended suspension becomes a pause
  END IF;
"""),
    ],
    # §6.3: a closer look (under_review) is never visible: it doesn't touch
    # the person's own standing; generation leaves them out instead.
    'public.dating_account_in_good_standing(uuid)': [
        ("""    WHERE dar.user_id = p_user_id
      AND dar.lifted_at IS NULL
""", f"""    WHERE dar.user_id = p_user_id
      AND dar.restriction_type <> 'under_review' -- {T} (§6.3): a closer look is never visible
      AND dar.lifted_at IS NULL
"""),
        ("""    WHERE er.scope = 'dating'
      AND er.phone_hmac = public.dating_phone_hmac_for_user(p_user_id)
""", f"""    WHERE er.scope = 'dating'
      AND er.restriction_type <> 'under_review' -- {T}
      AND er.phone_hmac = public.dating_phone_hmac_for_user(p_user_id)
"""),
    ],
    # §6.2: a credible P0/P1 report in an open case, or a closer look,
    # removes the person from new generation.
    'private.dating_generation_removed(uuid,timestamp with time zone,jsonb)': [
        ("""  SELECT private.dating_throttled(p_user)
""", f"""  SELECT (private.dating_throttled(p_user) -- {T}: (the dragnet throttle's rule)
"""),
        ("""         >= coalesce((p_cfg #>> '{dragnet,throttled_daily_max}')::int, 1);
""", f"""         >= coalesce((p_cfg #>> '{{dragnet,throttled_daily_max}}')::int, 1)) -- {T}
     OR private.dating_report_excluded(p_user) -- {T} (§6.2): an open P0/P1 report case
     OR EXISTS (SELECT 1 FROM public.dating_account_restrictions AS r -- {T} (§6.3): a closer look
                 WHERE r.user_id = p_user AND r.restriction_type = 'under_review' AND r.lifted_at IS NULL -- {T}
                   AND r.starts_at <= p_at AND (r.ends_at IS NULL OR r.ends_at > p_at)); -- {T}
"""),
    ],
    # §4.8: reports at 2 years, evidence at the case's close + 180 days.
    'private.dating_purge_steps()': [
        ("""  SELECT ARRAY['matches', 'introductions', 'pair_markers', 'moderation_cases', 'opener_hashes',
""", f"""  SELECT ARRAY['matches', 'introductions', 'pair_markers', -- {T}: and the report evidence and reports
               'report_evidence', 'reports', 'moderation_cases', 'opener_hashes', -- {T}
"""),
    ],
    'private.dating_purge_step(text,timestamp with time zone)': [
        ("""                 AND NOT EXISTS (SELECT 1 FROM public.dating_moderation_cases AS c
                                  WHERE c.match_id = x.id AND c.state IN ('open', 'in_review'))
                 AND NOT EXISTS (SELECT 1 FROM public.dating_safety_events AS e
                                  WHERE e.match_id = x.id AND e.created_at > p_now - interval '7 days')
                 LIMIT 5000
""", f"""                 AND NOT EXISTS (SELECT 1 FROM public.dating_moderation_cases AS c
                                  WHERE c.match_id = x.id AND c.state IN ('open', 'in_review'))
                 AND NOT EXISTS (SELECT 1 FROM public.dating_case_matches AS l -- {T} (W6 M-16): every match a case links
                                   JOIN public.dating_moderation_cases AS c ON c.id = l.case_id -- {T}
                                  WHERE l.match_id = x.id AND c.state IN ('open', 'in_review')) -- {T}
                 AND NOT EXISTS (SELECT 1 FROM public.dating_safety_events AS e
                                  WHERE e.match_id = x.id AND e.created_at > p_now - interval '7 days')
                 LIMIT 5000
"""),
        ("""                 AND NOT EXISTS (SELECT 1 FROM public.dating_moderation_cases AS c
                                  WHERE c.match_id = x.id AND c.state IN ('open', 'in_review'))
                 AND NOT EXISTS (SELECT 1 FROM public.dating_safety_events AS e
                                  WHERE e.match_id = x.id AND e.created_at > p_now - interval '7 days');
""", f"""                 AND NOT EXISTS (SELECT 1 FROM public.dating_moderation_cases AS c
                                  WHERE c.match_id = x.id AND c.state IN ('open', 'in_review'))
                 AND NOT EXISTS (SELECT 1 FROM public.dating_case_matches AS l -- {T}
                                   JOIN public.dating_moderation_cases AS c ON c.id = l.case_id -- {T}
                                  WHERE l.match_id = x.id AND c.state IN ('open', 'in_review')) -- {T}
                 AND NOT EXISTS (SELECT 1 FROM public.dating_safety_events AS e
                                  WHERE e.match_id = x.id AND e.created_at > p_now - interval '7 days');
"""),
        ("""      WHEN 'pair_markers' THEN
""", f"""      -- {T} (§4.8): evidence until its case closes + 180 days, or while a
      -- {T} restriction or a carried record from that case lasts.
      WHEN 'report_evidence' THEN -- {T}
        DELETE FROM public.dating_report_evidence AS e -- {T}
         USING public.dating_reports AS r, public.dating_moderation_cases AS c -- {T}
         WHERE r.id = e.report_id AND c.id = r.case_id AND c.state IN ('decided', 'closed') -- {T}
           AND coalesce(c.decided_at, c.created_at) < p_now - interval '180 days' -- {T}
           AND NOT EXISTS (SELECT 1 FROM public.dating_account_restrictions AS x -- {T}
                            WHERE x.case_id = c.id AND x.lifted_at IS NULL AND (x.ends_at IS NULL OR x.ends_at > p_now)) -- {T}
           AND NOT EXISTS (SELECT 1 FROM public.enforcement_records AS k -- {T}
                            WHERE k.case_id = c.id AND k.purge_after > p_now -- {T}
                              AND (k.effect_until IS NULL OR k.effect_until > p_now)); -- {T}
      -- {T} (§4.8, W6 T8 carry): reports at 2 years (their evidence goes
      -- {T} with them); one whose case is still open stays (Ruling P-3).
      WHEN 'reports' THEN -- {T}
        DELETE FROM public.dating_reports AS r -- {T}
         WHERE r.created_at < p_now - interval '2 years' -- {T}
           AND NOT EXISTS (SELECT 1 FROM public.dating_moderation_cases AS c -- {T}
                            WHERE c.id = r.case_id AND c.state IN ('open', 'in_review')); -- {T}
      WHEN 'pair_markers' THEN
"""),
    ],
    # W6 final M-16: every match a signal case's evidence comes from is
    # linked, the first or a later one.
    'private.dating_open_chat_case(uuid,uuid,text,text)': [
        ("""       AND c.state IN ('open', 'in_review') AND c.match_id IS NULL;
  END IF;
  RETURN v_opened;
""", f"""       AND c.state IN ('open', 'in_review') AND c.match_id IS NULL;
  END IF;
  INSERT INTO public.dating_case_matches (case_id, match_id) -- {T} (W6 final M-16): a later hit's match too
  SELECT c.id, p_match FROM public.dating_moderation_cases AS c -- {T}
   WHERE p_match IS NOT NULL AND c.kind = 'signal' AND c.signal_kind = p_signal AND c.state IN ('open', 'in_review') -- {T}
     AND (c.target_user_id = p_sender OR c.target_phone_hmac = public.dating_phone_hmac_for_user(p_sender)) -- {T}
  ON CONFLICT DO NOTHING; -- {T}
  RETURN v_opened;
"""),
    ],
    # §6.3 step 1 names the case; R-52: each deleted side's number's code
    # stays on its matches, so the other can report for 30 days.
    'private.dating_deletion_carry(uuid,boolean)': [
        ("""  INSERT INTO public.enforcement_records (phone_hmac, scope, source_restriction_id, restriction_type,
                                          category, confirmed_report_count, effect_until, purge_after)
  SELECT s.phone_hmac, 'dating', dar.id, dar.restriction_type, to_jsonb(dar) ->> 'category',
""", f"""  INSERT INTO public.enforcement_records (phone_hmac, scope, source_restriction_id, restriction_type,
                                          category, confirmed_report_count, effect_until, purge_after, case_id) -- {T}
  SELECT s.phone_hmac, 'dating', dar.id, dar.restriction_type, dar.category, -- {T}
"""),
        ("""         dar.ends_at, now() + interval '2 years'
""", f"""         dar.ends_at, now() + interval '2 years', dar.case_id -- {T}
"""),
        ("""    -- 4. Reports about the person keep the number's HMAC (the cascade sets
""", f"""    -- {T} (R-52): the person's matches keep the number's code, so the other
    -- {T} can still report them for 30 days.
    UPDATE public.dating_matches AS m SET low_phone_hmac = v_hmac -- {T}
     WHERE m.user_low_id = p_user AND m.low_phone_hmac IS NULL; -- {T}
    UPDATE public.dating_matches AS m SET high_phone_hmac = v_hmac -- {T}
     WHERE m.user_high_id = p_user AND m.high_phone_hmac IS NULL; -- {T}
    -- 4. Reports about the person keep the number's HMAC (the cascade sets
"""),
    ],
    # W6 T2 N-4: a chat only the two numbers' block ended is in the ended
    # list, with its Report.
    'public.get_my_dating_matches(boolean)': [
        ("""       AND (m.state <> 'active' OR m.user_low_id IS NULL OR m.user_high_id IS NULL)
       AND m.evidence_until > now();
""", f"""       AND (((m.state <> 'active' OR m.user_low_id IS NULL OR m.user_high_id IS NULL) AND m.evidence_until > now()) -- {T}
            OR (m.state = 'active' AND private.dating_pair_blocked(m.user_low_id, m.user_high_id))); -- {T} (W6 T2 N-4)
"""),
    ],
    'public.get_dating_operational_health()': [
        ("""                        'dating.mask.failed']) AS k(key)), -- Spec 2 W6c (final server fix, I-8): the masker's fail-closed fallback
""", f"""                        'dating.mask.failed', -- Spec 2 W6c (final server fix, I-8): the masker's fail-closed fallback; {T}: and
                        'dating.report.evidence_unavailable', 'dating.report.hmac_missing', 'dating.carry_over.applied', -- {T}
                        'dating.release.busy', 'dating.release.failed', 'dating.hold.p0', -- {T}
                        'dating.sla.alert_unconfigured', 'dating.sla.alert_failed', -- {T}: W7b's (Ruling R-57: listed once, here)
                        'dating.moderation.not_moderator']) AS k(key)), -- {T}
    -- {T} (§6.2): open report and appeal cases by priority, past their clock,
    -- {T} and reports about a number with no code (the key was missing).
    'reports_open',(SELECT jsonb_build_object( -- {T}
                      'P0', count(*) FILTER (WHERE c.priority = 'P0'), 'P1', count(*) FILTER (WHERE c.priority = 'P1'), -- {T}
                      'P2', count(*) FILTER (WHERE c.priority = 'P2'), 'P3', count(*) FILTER (WHERE c.priority = 'P3'), -- {T}
                      'past_due', count(*) FILTER (WHERE c.sla_due_at < now())) -- {T}
                    FROM public.dating_moderation_cases AS c -- {T}
                   WHERE c.kind IN ('report', 'appeal') AND c.state IN ('open', 'in_review')), -- {T}
    'reports_without_hmac_30d',(SELECT count(*) FROM public.dating_reports AS r -- {T}
                                 WHERE r.target_phone_hmac IS NULL AND r.created_at >= now() - interval '30 days'), -- {T}
"""),
    ],
}

EDITS_T2 = {
    # §3.7: an accepted appeal is said on the Dating section for 7 days.
    'public.get_dating_home()': [
        ("""  v_has := jsonb_build_object('has_data', private.dating_has_data(v_user)); -- Spec 2 W3a (C-2)
""", f"""  v_has := jsonb_build_object('has_data', private.dating_has_data(v_user)) -- {T}: and an accepted appeal (§3.7), only when there is one
           || CASE WHEN private.dating_appeal_accepted(v_user) THEN jsonb_build_object('appeal_accepted', true) ELSE '{{}}'::jsonb END; -- {T}
"""),
    ],
}

TAIL = """
-- ---------------------------------------------------------------------
-- 14. Self-revoke (the W6 final pattern): nothing this migration creates
--     is any API role's until the twin grants it.
-- ---------------------------------------------------------------------
REVOKE ALL ON TABLE public.dating_report_evidence, public.dating_case_matches, public.dating_appeals
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  private.dating_report_priority(text), private.dating_report_sla_due(text, timestamptz),
  private.dating_report_defaults(), private.dating_restriction_defaults(),
  private.dating_reporter_tripped(uuid, uuid), private.dating_report_excluded(uuid),
  private.dating_snapshot_evidence(uuid, uuid, text), private.dating_report_case(uuid),
  private.dating_report_corroborated(uuid),
  private.dating_place_restriction(uuid, text, text, text, uuid, uuid, timestamptz, boolean),
  private.dating_file_report(uuid, uuid, text, uuid, uuid, text, text, text, text), private.dating_report_answer(uuid),
  private.dating_release_suspension(uuid), private.dating_close_case(uuid, uuid, text),
  public.report_dating_match(text, uuid, text, text, boolean),
  public.report_dating_introduction(text, uuid, text, text, boolean)
  FROM PUBLIC, anon, authenticated, service_role;
"""

TAIL_T2 = """REVOKE ALL ON FUNCTION
  private.dating_carry_over(uuid), private.dating_release_expired_suspensions(),
  public.get_my_dating_restriction(), private.dating_appeal_accepted(uuid),
  public.submit_dating_appeal(text, uuid, text),
  private.dating_decide_appeal(uuid, uuid, boolean, boolean)
  FROM PUBLIC, anon, authenticated, service_role;
"""

HEADER = """-- Spec 2 W7a (§3.7, §4.3, §4.8, §4.9 W7a, §4.10, §6.2, §6.3, §7.1): reports,
-- restrictions, appeals.
--   * Reports v2: the 14 categories and priorities of §3.7, the match or
--     introduction, the reporter's number's code (corroboration), the
--     credibility note, the state, the 4/24/48/72-hour clock, the case.
--     report_dating_match and report_dating_introduction v2 (five
--     arguments, fixed answers); submit_dating_report removed (§4.10).
--   * Evidence: the last 50 messages, encrypted with the field key.
--   * Automatic steps (§6.2), never a ban: a P0 report closes the
--     reporter's match; P0 and P1 remove the person from new generation
--     while the case is open; an interim hold only when corroborated (two
--     independent P0 reports, or underage_risk with a tier-3 age_signal:
--     then an age review); a reporter whose own messages tripped
--     sexual_pressure or financial_request takes no automatic step and
--     never counts.
--   * Cases: one open report case per person; every match a case comes
--     from is linked and held from the purge (W6 M-16).
--   * Restrictions v2: category, source, case, decider, appealable; per
--     type (§6.3): a hold keeps matches open, an age review or a
--     suspension closes them, a closer look shows nothing.
--   * The restricted person's read, one appeal, carry-over at
--     re-registration, an ended suspension released to a pause, the
--     decisions W7b's console calls (close a case, decide an appeal).
--   * The purge: reports at 2 years, evidence at the case's close + 180
--     days (§4.8; W6 T8 carry).
-- Nothing here turns a flag on. Grants in
-- 20261121100010_dating_v2_reports_grants.sql; this file revokes what it
-- creates from every API role first (the W6 final pattern).
"""


def live(sig):
    return (B / f'{sig}.sql').read_text().rstrip('\n')


def edited(sig, edits):
    text = live(sig)
    for old, new in edits[sig]:
        n = text.count(old)
        assert n == 1, f'{sig}: anchor occurs {n} times: {old[:70]!r}'
        assert T in new, f'{sig}: a replacement without the tag'
        text = text.replace(old, new)
    return text + ';\n'


head = (D / 'mig_T1_head.sql').read_text()
t2 = D / 'mig_T2.sql'
tail = TAIL
funcs = [edited(s, EDITS) for s in EDITS]
if t2.exists():
    assert head.count('-- @@W7A-T2@@\n') == 1
    head = head.replace('-- @@W7A-T2@@\n', t2.read_text())
    tail += TAIL_T2
    funcs += [edited(s, EDITS_T2) for s in EDITS_T2]
body = (HEADER + 'BEGIN;\nSET LOCAL lock_timeout = \'5s\';\n\n' + head
        + '\n-- ---------------------------------------------------------------------\n'
        + '-- 13. Functions re-created from their live bodies; only the lines marked\n'
        + '--     "-- Spec 2 W7a" change.\n'
        + '-- ---------------------------------------------------------------------\n'
        + '\n'.join(funcs) + tail + '\nCOMMIT;\n')
out = pathlib.Path('supabase/migrations/20261121100000_dating_v2_reports.sql')
out.write_text(body)
print(f'{out}: {len(funcs)} re-created function(s), {body.count(chr(10))} lines')
```

Create `supabase/migrations/20261121100010_dating_v2_reports_grants.sql` with exactly (Task 2 splices its grants at `-- @@W7A-T2-GRANTS@@`):

```sql
-- Spec 2 W7a: grants for 20261121100000_dating_v2_reports.sql. The
-- evidence, the case links and the appeals are no API role's, the service
-- role included (the console reaches them through W7b's definer
-- functions); the two report RPCs, the restricted person's read and the
-- appeal are the app's; every helper and the console's decisions are the
-- database's own.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON TABLE public.dating_report_evidence FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.dating_case_matches FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.dating_appeals FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_report_priority(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_report_sla_due(text, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_report_defaults() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_restriction_defaults() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_reporter_tripped(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_report_excluded(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_snapshot_evidence(uuid, uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_report_case(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_report_corroborated(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_place_restriction(uuid, text, text, text, uuid, uuid, timestamptz, boolean)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_file_report(uuid, uuid, text, uuid, uuid, text, text, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_report_answer(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_release_suspension(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.report_dating_match(text, uuid, text, text, boolean) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.report_dating_match(text, uuid, text, text, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.report_dating_introduction(text, uuid, text, text, boolean) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.report_dating_introduction(text, uuid, text, text, boolean) TO authenticated;
REVOKE ALL ON FUNCTION private.dating_close_case(uuid, uuid, text) FROM PUBLIC, anon, authenticated, service_role;
-- @@W7A-T2-GRANTS@@
COMMIT;
```

- [ ] **Step 7: Build and apply**

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
python3 -I $D/build_mig_W7a.py
for f in supabase/migrations/20261121100000_dating_v2_reports.sql supabase/migrations/20261121100010_dating_v2_reports_grants.sql; do
  for run in 1 2; do psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $f > /dev/null 2> $D/apply_err.txt; rc=$?; echo "$(basename $f) run $run exit=$rc"; grep -v NOTICE $D/apply_err.txt || true; done
done
python3 -I $D/marked_diff.py $D/before_w7a attune_spec3a 'Spec 2 W7a'; echo "marked_diff exit=$?"
python3 -I $D/grants_line.py supabase/migrations/20261120120010_dating_v2_chat_guided_grants.sql 'Spec 2 W7a: reports, restrictions, appeals (twin of 20261121100000)' supabase/migrations/20261121100010_dating_v2_reports_grants.sql
```

Expected: `supabase/migrations/20261121100000_dating_v2_reports.sql: 9 re-created function(s), 1341 lines`; four `exit=0` lines and nothing else printed for them; ten marked-diff lines each ending `OK` (`private.dating_deletion_carry(uuid,boolean): 9 added line(s), 3 removed OK`, `private.dating_generation_removed(…): 6 added line(s), 2 removed OK`, `private.dating_open_chat_case(…): 5 added line(s), 0 removed OK`, `private.dating_purge_step(…): 25 added line(s), 0 removed OK`, `private.dating_purge_steps(): 2 added line(s), 1 removed OK`, `public.dating_account_in_good_standing(uuid): 2 added line(s), 0 removed OK`, `public.enforce_dating_restriction_change(): 6 added line(s), 0 removed OK`, `public.get_dating_home(): 0 added line(s), 0 removed OK` (Task 2 re-creates it), `public.get_dating_operational_health(): 15 added line(s), 1 removed OK`, `public.get_my_dating_matches(boolean): 2 added line(s), 2 removed OK`) and `marked_diff exit=0`; `local_pg_grants.sql: one \i block added`.

- [ ] **Step 8: Run the contract**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_moderation_contracts.sql 2>&1 | tail -1
```

Expected: `psql:supabase/tests/dating_v2_moderation_contracts.sql:670: NOTICE:  dating_v2_moderation_contracts: all held`.

- [ ] **Step 9: The existing contracts meet reports v2**

Create `$D/edit_tests_T1.py` with exactly:

```python
#!/usr/bin/env python3
# Spec 2 W7a Task 1: the existing contracts meet reports v2. The canary
# takes the evidence, the case links and the appeals (no API role's), the
# two report RPCs v2 (the app's) and the helpers (the database's own), and
# drops the v1 report RPCs and submit_dating_report (§4.10); the
# service-role test lists the three tables among the ones no API role
# reads; the mode contract's raw-target report check becomes "it is gone".
import importlib.util
import pathlib

spec = importlib.util.spec_from_file_location('anchor', '.superpowers/sdd/2026-11-21-spec2-w7/anchor.py')
anchor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(anchor)

anchor.edit('supabase/tests/dating_rls_canary.sql', [(
    """-- ---------------------------------------------------------------------
-- Checks (every batch adds its rows above this line).
""",
    """-- Spec 2 W7a Task 1: reports v2. The evidence, the case links and the
-- appeals are no API role's, the service role included (the console's
-- definer functions read them, W7b); the report RPCs v2 are the app's; the
-- v1 report RPCs and submit_dating_report are gone (§4.10).
DELETE FROM allowed_fn WHERE sig IN ('report_dating_introduction(text,uuid,text,text)',
                                     'report_dating_match(text,uuid,text,text)',
                                     'submit_dating_report(text,uuid,text,text)');
INSERT INTO allowed_rel (name, authenticated, service_dml) VALUES
  ('dating_report_evidence', '', ''),
  ('dating_case_matches', '', ''),
  ('dating_appeals', '', '');
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('report_dating_match(text,uuid,text,text,boolean)', 'authenticated', ''),
  ('report_dating_introduction(text,uuid,text,text,boolean)', 'authenticated', ''),
  ('private.dating_report_priority(text)', '', ''),
  ('private.dating_report_sla_due(text,timestamp with time zone)', '', ''),
  ('private.dating_report_defaults()', '', ''),
  ('private.dating_restriction_defaults()', '', ''),
  ('private.dating_reporter_tripped(uuid,uuid)', '', ''),
  ('private.dating_report_excluded(uuid)', '', ''),
  ('private.dating_snapshot_evidence(uuid,uuid,text)', '', ''),
  ('private.dating_report_case(uuid)', '', ''),
  ('private.dating_report_corroborated(uuid)', '', ''),
  ('private.dating_place_restriction(uuid,text,text,text,uuid,uuid,timestamp with time zone,boolean)', '', ''),
  ('private.dating_file_report(uuid,uuid,text,uuid,uuid,text,text,text,text)', '', ''),
  ('private.dating_report_answer(uuid)', '', ''),
  ('private.dating_release_suspension(uuid)', '', ''),
  ('private.dating_close_case(uuid,uuid,text)', '', '');
-- @@W7A-T2-CANARY@@

-- ---------------------------------------------------------------------
-- Checks (every batch adds its rows above this line).
""")], 'W7a Task 1')

for old in ("""                          -- Spec 2 W6c: the guided skips, written by one definer RPC.
                          'dating_guided_skips')
    AND NOT has_table_privilege('service_role', c.oid, 'SELECT');""",
            """                          -- Spec 2 W6c: the guided skips, written by one definer RPC.
                          'dating_guided_skips')
    -- Spec 2 W1b (batch-4 fix round 1, C-1): the service role only reads"""):
    new = old.replace("""                          'dating_guided_skips')""",
                      """                          'dating_guided_skips',
                          -- Spec 2 W7a: the report evidence (encrypted), the case
                          -- links and the appeals; W7b's console reaches them
                          -- through its definer functions only.
                          'dating_report_evidence', 'dating_case_matches', 'dating_appeals')""")
    anchor.edit('supabase/tests/service_role_grants_test.sql', [(old, new)], 'W7a Task 1')

anchor.edit('supabase/tests/dating_mode_contracts.sql', [(
    """  IF has_function_privilege('authenticated','public.submit_dating_report(text,uuid,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'authenticated can execute raw-target report RPC';
  END IF;""",
    """  -- Spec 2 W7a (§4.10, Fable M1): the raw-target report RPC is gone; the
  -- v2 report RPCs resolve the target from the caller's own match or card.
  IF to_regprocedure('public.submit_dating_report(text,uuid,text,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'the raw-target report RPC still exists';
  END IF;""")], 'W7a Task 1')
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
python3 -I $D/edit_tests_T1.py
$D/suite.sh attune_spec3a > $D/sql-after-T1.txt; echo "$(grep -c '^PASS' $D/sql-after-T1.txt) PASS, $(grep -c '^FAIL' $D/sql-after-T1.txt) FAIL"
diff <(grep FAIL $D/sql-baseline.txt) <(grep FAIL $D/sql-after-T1.txt)
```

Expected: the four edit lines (`dating_rls_canary.sql: 1 edit(s) (W7a Task 1)`, `service_role_grants_test.sql: 1 edit(s) (W7a Task 1)` twice, `dating_mode_contracts.sql: 1 edit(s) (W7a Task 1)`); `162 PASS, 14 FAIL`; the diff prints nothing (the new contract is the one more PASS).

- [ ] **Step 10: The mutants (§7.5 mutants 13 and 14; carries 6, 9, 10)**

Create `$D/mut_T1.py` with exactly:

```python
# Spec 2 W7a Task 1 mutants (mutate.py on 20261121100000_dating_v2_reports.sql):
# each must make dating_v2_moderation_contracts.sql fail with a CONTRACT VIOLATED line.
MUTS = {
    # §7.5 mutant 13: one uncorroborated P0 report holds.
    'm13_hold_on_one_p0': ("RETURN CASE WHEN v_other IS NOT NULL THEN 'moderation_hold' END;", "RETURN 'moderation_hold';"),
    # §7.5 mutant 14: a tripped reporter counts for corroboration.
    'm14_tripped_counts': ("v_priority = 'P0' AND v_tripped IS NULL AND v_old_enough AND v_hmac IS NOT NULL,",
                           "v_priority = 'P0' AND v_old_enough AND v_hmac IS NOT NULL,"),
    'tripped_auto_step': ("v_tripped IS NULL AND v_priority IN ('P0', 'P1'),", "v_priority IN ('P0', 'P1'),"),
    'p2_auto_step': ("v_tripped IS NULL AND v_priority IN ('P0', 'P1'),", "v_tripped IS NULL AND v_priority IN ('P0', 'P1', 'P2'),"),
    'young_reporter_counts': ("v_priority = 'P0' AND v_tripped IS NULL AND v_old_enough AND v_hmac IS NOT NULL,",
                              "v_priority = 'P0' AND v_tripped IS NULL AND v_hmac IS NOT NULL,"),
    'same_reporter_counts': ("AND o.reporter_user_id IS DISTINCT FROM r.reporter_user_id", "AND true"),
    'shared_phone_counts': ("     AND NOT EXISTS (SELECT 1 FROM public.dating_trusted_devices AS a",
                            "     AND true OR NOT EXISTS (SELECT 1 FROM public.dating_trusted_devices AS a"),
    'age_signal_ignored': ("  IF r.category = 'underage_risk' AND (v_age OR v_other = 'underage_risk') THEN",
                           "  IF r.category = 'underage_risk' AND v_other = 'underage_risk' THEN"),
    'evidence_oldest': ("WHERE d.match_id = p_match ORDER BY d.created_at DESC, d.id DESC LIMIT 50) AS x;",
                        "WHERE d.match_id = p_match ORDER BY d.created_at, d.id LIMIT 50) AS x;"),
    'evidence_plain': ("    v_enc := private.dating_field_encrypt(pg_catalog.jsonb_build_object('v', 1, 'messages', v_json));",
                       "    v_enc := '\\x01'::bytea || convert_to(pg_catalog.jsonb_build_object('v', 1, 'messages', v_json)::text, 'UTF8');"),
    'window_forever': ("IF NOT FOUND\n         OR NOT (v_m.state = 'active' OR v_m.evidence_until > now()) THEN", "IF NOT FOUND THEN"),
    'stranger_reports': ("       WHERE m.id = p_match_id AND v_user IN (m.user_low_id, m.user_high_id);\n      IF NOT FOUND",
                         "       WHERE m.id = p_match_id;\n      IF NOT FOUND"),
    'no_rate_limit': ("      SELECT * INTO v_m FROM public.dating_matches AS m WHERE m.id = p_match_id FOR UPDATE;\n      BEGIN\n        PERFORM public.check_dating_rate_limit('report', 10, interval '1 day');",
                      "      SELECT * INTO v_m FROM public.dating_matches AS m WHERE m.id = p_match_id FOR UPDATE;\n      BEGIN\n        PERFORM 1;"),
    'phone_gated': ("  FOR v_try IN 1..3 LOOP\n    BEGIN\n      PERFORM private.dating_lock_setup(v_user);\n      IF EXISTS (SELECT 1 FROM public.dating_rpc_idempotency AS k\n                  WHERE k.user_id = v_user AND k.operation = 'report_dating_match'",
                    "  IF public.dating_require_trusted_device() IS NOT TRUE THEN\n    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reverify_device');\n  END IF;\n  FOR v_try IN 1..3 LOOP\n    BEGIN\n      PERFORM private.dating_lock_setup(v_user);\n      IF EXISTS (SELECT 1 FROM public.dating_rpc_idempotency AS k\n                  WHERE k.user_id = v_user AND k.operation = 'report_dating_match'"),
    'p0_no_close': ("        UPDATE public.dating_matches AS m\n           SET state = 'closed', closed_reason = 'reported'",
                    "        UPDATE public.dating_matches AS m\n           SET state = m.state, closed_reason = m.closed_reason"),
    'p0_no_marker': ("        IF v_other IS NOT NULL THEN\n          PERFORM private.dating_mark_pair(v_user, v_other);",
                     "        IF false THEN\n          PERFORM private.dating_mark_pair(v_user, v_other);"),
    'hold_closes_matches': ("   IF NEW.restriction_type IN ('suspended', 'age_review') THEN",
                            "   IF NEW.restriction_type IN ('suspended', 'age_review', 'moderation_hold') THEN"),
    'generation_ignores_reports': ("     OR private.dating_report_excluded(p_user) -- Spec 2 W7a (§6.2): an open P0/P1 report case",
                                   "     OR false -- Spec 2 W7a (§6.2): an open P0/P1 report case"),
    'excluded_ignores_number': ("            OR c.target_phone_hmac = public.dating_phone_hmac_for_user(p_user)));",
                                "            OR false));"),
    'case_link_missing': ("    INSERT INTO public.dating_case_matches (case_id, match_id) VALUES (v_case, r.match_id) ON CONFLICT DO NOTHING;",
                          "    NULL;"),
    'purge_ignores_links': ('MULTI', [
        ("                                  WHERE l.match_id = x.id AND c.state IN ('open', 'in_review')) -- Spec 2 W7a\n                 AND NOT EXISTS (SELECT 1 FROM public.dating_safety_events AS e\n                                  WHERE e.match_id = x.id AND e.created_at > p_now - interval '7 days')\n                 LIMIT 5000",
         "                                  WHERE l.match_id = x.id AND false) -- Spec 2 W7a\n                 AND NOT EXISTS (SELECT 1 FROM public.dating_safety_events AS e\n                                  WHERE e.match_id = x.id AND e.created_at > p_now - interval '7 days')\n                 LIMIT 5000"),
        ("                                  WHERE l.match_id = x.id AND c.state IN ('open', 'in_review')) -- Spec 2 W7a\n                 AND NOT EXISTS (SELECT 1 FROM public.dating_safety_events AS e\n                                  WHERE e.match_id = x.id AND e.created_at > p_now - interval '7 days');",
         "                                  WHERE l.match_id = x.id AND false) -- Spec 2 W7a\n                 AND NOT EXISTS (SELECT 1 FROM public.dating_safety_events AS e\n                                  WHERE e.match_id = x.id AND e.created_at > p_now - interval '7 days');")]),
    'signal_link_missing': ("   WHERE p_match IS NOT NULL AND c.kind = 'signal'", "   WHERE false AND c.kind = 'signal'"),
    'deleted_side_unstamped': ("    UPDATE public.dating_matches AS m SET low_phone_hmac = v_hmac -- Spec 2 W7a\n     WHERE m.user_low_id = p_user AND m.low_phone_hmac IS NULL; -- Spec 2 W7a\n    UPDATE public.dating_matches AS m SET high_phone_hmac = v_hmac -- Spec 2 W7a\n     WHERE m.user_high_id = p_user AND m.high_phone_hmac IS NULL; -- Spec 2 W7a",
                               "    NULL;"),
    'number_block_dropped': ("        INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac, purge_after)\n        VALUES (public.dating_phone_hmac_for_user(v_user), v_hmac, now() + interval '2 years')",
                             "        INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac, purge_after)\n        SELECT public.dating_phone_hmac_for_user(v_user), v_hmac, now() + interval '2 years' WHERE false"),
    'reports_kept_forever': ("         WHERE r.created_at < p_now - interval '2 years' -- Spec 2 W7a", "         WHERE false -- Spec 2 W7a"),
    'evidence_kept_forever': ("           AND coalesce(c.decided_at, c.created_at) < p_now - interval '180 days' -- Spec 2 W7a",
                              "           AND false -- Spec 2 W7a"),
    'evidence_ignores_restriction': ("           AND NOT EXISTS (SELECT 1 FROM public.dating_account_restrictions AS x -- Spec 2 W7a",
                                     "           AND true OR NOT EXISTS (SELECT 1 FROM public.dating_account_restrictions AS x -- Spec 2 W7a"),
    'open_case_reports_purged': ("           AND NOT EXISTS (SELECT 1 FROM public.dating_moderation_cases AS c -- Spec 2 W7a\n                            WHERE c.id = r.case_id AND c.state IN ('open', 'in_review')); -- Spec 2 W7a",
                                 "           AND true; -- Spec 2 W7a"),
    'card_p0_kept': ("        UPDATE public.dating_introductions AS i SET state = 'invalidated'\n         WHERE i.id = p_introduction_id",
                     "        UPDATE public.dating_introductions AS i SET state = i.state\n         WHERE i.id = p_introduction_id"),
}
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
python3 -I $D/mutate.py supabase/migrations/20261121100000_dating_v2_reports.sql supabase/tests/dating_v2_moderation_contracts.sql $D/mut_T1.py $D/mut supabase/migrations/20261121100010_dating_v2_reports_grants.sql > $D/mut_T1.txt 2>&1
grep -c 'CONTRACT VIOLATED' $D/mut_T1.txt; grep -v 'CONTRACT VIOLATED' $D/mut_T1.txt
```

Expected: `29`, and nothing else printed (the second `grep` exits 1 on no lines). Among them: `m13_hold_on_one_p0: ERROR:  CONTRACT VIOLATED: …`, `m14_tripped_counts: …`, `same_reporter_counts: …`, `deleted_side_unstamped: …`, `purge_ignores_links: …`, `reports_kept_forever: …`.

- [ ] **Step 11: Record the tree**

Do not commit; record the tree in the report (`T=$(mktemp -u); GIT_INDEX_FILE=$T git read-tree HEAD && GIT_INDEX_FILE=$T git add -A && GIT_INDEX_FILE=$T git write-tree; rm -f $T`).

### Task 2: What the restricted person sees, one appeal, carry-over, release, the console's decisions, deletion, the races (§3.7, §4.3, §4.6, §6.3, §7.1, §7.5 mutant 15, §7.6; carries 3, 6, 8; R-53–R-55, R-64, R-66)

**Files:**
- Create: `$D/{mig_T2.sql, twin_T2.sql, contract_T2.sql, edit_tests_T2.py, edit_races_T2.py, mut_T2.py}`
- Modify (rebuild): `supabase/migrations/20261121100000_dating_v2_reports.sql`, `…100010_dating_v2_reports_grants.sql`; `supabase/tests/dating_v2_moderation_contracts.sql` (E–H), `supabase/tests/dating_rls_canary.sql`, `scripts/concurrency/dating_kill_switch_races.sh`

**Interfaces:**
- Consumes: Task 1's tables and helpers; the live `get_dating_home()` (saved in Task 1 Step 4); W3's `private.dating_has_data(uuid)`; pg_cron.
- Produces: `private.dating_carry_over(uuid)`, `private.dating_release_expired_suspensions()` and its cron `release-dating-suspensions` (`*/15 * * * *`), `get_my_dating_restriction()` (VOLATILE: it carries over), `private.dating_appeal_accepted(uuid)`, `submit_dating_appeal(text, uuid, text)`, `private.dating_decide_appeal(uuid, uuid, boolean, boolean)`; `get_dating_home()` + `appeal_accepted` (only when true).

- [ ] **Step 1: Write the failing contract sections**

Create `$D/contract_T2.sql` with exactly (sections E–H; it ends with W7b's marker):

```sql
-- =====================================================================
-- E. (§3.7, §6.3, R-54) What the restricted person sees: the shown
--    restriction (closed for good, then until a date, then the age check,
--    then a hold; a closer look never), its category, whether it can be
--    appealed; never who reported, what they wrote or the evidence. Read
--    on a phone that isn't checked too.
-- =====================================================================
DO $e$
DECLARE
  v_h constant uuid := pg_temp.man('60');
  v_age constant uuid := pg_temp.man('61');
  v_s constant uuid := pg_temp.man('62');
  v_p constant uuid := pg_temp.man('63');
  v_u constant uuid := pg_temp.man('64');
  v_n constant uuid := pg_temp.man('65');
  v_rep constant uuid := pg_temp.ready('66');
  v_m uuid;
  v_case uuid;
  v jsonb;
  v_ends timestamptz := date_trunc('second', now() + interval '7 days');
BEGIN
  v_m := pg_temp.match(v_h, v_rep);
  PERFORM pg_temp.report(v_rep, '66', v_m, 'threats', false, 'w7-secret-details');
  SELECT case_id INTO v_case FROM public.dating_reports WHERE match_id = v_m;
  PERFORM private.dating_place_restriction(v_h, 'moderation_hold', 'threat_to_life', 'report', v_case, NULL, NULL, false);
  v := pg_temp.call(v_h, NULL, 'SELECT public.get_my_dating_restriction()')::jsonb;
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v -> 'restriction') AS k)
       IS DISTINCT FROM ARRAY['appeal', 'can_appeal', 'category', 'ends_at', 'id', 'type']
     OR v #>> '{restriction,type}' IS DISTINCT FROM 'hold' OR v #>> '{restriction,category}' IS DISTINCT FROM 'threat_to_life'
     OR (v #>> '{restriction,can_appeal}')::boolean OR v -> 'restriction' -> 'ends_at' <> 'null'::jsonb
     OR v -> 'restriction' -> 'appeal' <> 'null'::jsonb OR (v ->> 'appeal_accepted')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the hold reads %', v;
  END IF;
  IF position('w7-secret-details' IN v::text) > 0 OR position(v_rep::text IN v::text) > 0
     OR position('Mod 66' IN v::text) > 0 OR position(v_case::text IN v::text) > 0 OR position('report' IN v::text) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the restricted person''s read names the reporter, the report or the case: %', v;
  END IF;
  PERFORM private.dating_place_restriction(v_age, 'age_review', 'underage_risk', 'report', NULL, NULL, NULL, false);
  PERFORM private.dating_place_restriction(v_s, 'suspended', 'romance_scam', 'moderator', NULL, v_rep, v_ends, true);
  PERFORM private.dating_place_restriction(v_p, 'moderation_hold', 'csam', 'report', NULL, NULL, NULL, false);
  PERFORM private.dating_place_restriction(v_p, 'suspended', 'harassment', 'moderator', NULL, v_rep, NULL, true);
  PERFORM private.dating_place_restriction(v_u, 'under_review', 'spam', 'moderator', NULL, v_rep, NULL, false);
  IF pg_temp.j(v_age, '61', 'SELECT public.get_my_dating_restriction()') #>> '{restriction,type}' IS DISTINCT FROM 'age_review'
     OR (pg_temp.j(v_age, '61', 'SELECT public.get_my_dating_restriction()') #>> '{restriction,can_appeal}')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the age check reads wrong';
  END IF;
  v := pg_temp.j(v_s, '62', 'SELECT public.get_my_dating_restriction()');
  IF v #>> '{restriction,type}' IS DISTINCT FROM 'suspended' OR (v #>> '{restriction,ends_at}')::timestamptz IS DISTINCT FROM v_ends
     OR NOT (v #>> '{restriction,can_appeal}')::boolean OR v #>> '{restriction,category}' IS DISTINCT FROM 'romance_scam' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a suspension until a date reads %', v;
  END IF;
  v := pg_temp.j(v_p, '63', 'SELECT public.get_my_dating_restriction()');
  IF v #>> '{restriction,type}' IS DISTINCT FROM 'suspended' OR v -> 'restriction' -> 'ends_at' <> 'null'::jsonb
     OR v #>> '{restriction,category}' IS DISTINCT FROM 'harassment' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: closed for good is not shown before a hold: %', v;
  END IF;
  -- A closer look is never shown, leaves the person's standing alone, and
  -- keeps them out of new generation.
  IF pg_temp.j(v_u, '64', 'SELECT public.get_my_dating_restriction()') IS DISTINCT FROM
       '{"ok": true, "restriction": null, "appeal_accepted": false}'::jsonb
     OR NOT public.dating_account_in_good_standing(v_u) OR NOT pg_temp.excluded(v_u)
     OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_u) <> 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closer look showed, changed standing, or left the person in generation';
  END IF;
  IF pg_temp.j(v_n, '65', 'SELECT public.get_my_dating_restriction()') IS DISTINCT FROM
       '{"ok": true, "restriction": null, "appeal_accepted": false}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: someone with no restriction reads one';
  END IF;
END $e$;

-- =====================================================================
-- F. (§3.7, §6.3, §7.5 mutant 15) One appeal, to a live appealable
--    restriction of one's own, opening an appeal case due in 7 days;
--    decided by someone other than the restriction's decider, or by the
--    safety owner 24 hours on when the owner decided it; accepting lifts
--    the restriction, leaves Dating paused (never suspended for good) and
--    says so on the section for 7 days; rejecting keeps it.
-- =====================================================================
DO $f$
DECLARE
  v_x constant uuid := pg_temp.man('67');
  v_mod constant uuid := pg_temp.ready('68');
  v_mod2 constant uuid := pg_temp.ready('69');
  v_y constant uuid := pg_temp.man('80');
  v_owner constant uuid := pg_temp.ready('81');
  v_z constant uuid := pg_temp.man('82');
  v_r uuid;
  v_r2 uuid;
  v_hold uuid;
  v_a uuid;
  v_a2 uuid;
  v_key constant text := pg_temp.key('f-appeal');
  v jsonb;
  v_got text;
  v_acc bigint := pg_temp.metric('dating.appeal.accepted');
  v_rej bigint := pg_temp.metric('dating.appeal.rejected');
BEGIN
  v_r := private.dating_place_restriction(v_x, 'suspended', 'harassment', 'moderator', NULL, v_mod, NULL, true);
  IF (SELECT state FROM public.dating_enrollments WHERE user_id = v_x) <> 'suspended' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a suspension left Dating open';
  END IF;
  v := pg_temp.j(v_x, '67', format('SELECT public.submit_dating_appeal(%L, %L, %L)', v_key, v_r, '  I didn''t do this.  '));
  SELECT id INTO v_a FROM public.dating_appeals WHERE restriction_id = v_r;
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT text || '/' || state FROM public.dating_appeals WHERE id = v_a) IS DISTINCT FROM 'I didn''t do this./open'
     OR (SELECT kind || '/' || priority || '/' || state || '/' || (sla_due_at BETWEEN now() + interval '6 days 23 hours' AND now() + interval '7 days 1 hour')
           FROM public.dating_moderation_cases WHERE appeal_id = v_a) IS DISTINCT FROM 'appeal/P2/open/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an appeal read % and opened no 7-day appeal case', v;
  END IF;
  v_got := concat_ws(' ',
    pg_temp.j(v_x, '67', format('SELECT public.submit_dating_appeal(%L, %L, NULL)', v_key, v_r)) ->> 'ok',
    pg_temp.j(v_x, '67', format('SELECT public.submit_dating_appeal(%L, %L, NULL)', pg_temp.key('f2'), v_r)) ->> 'reason',
    pg_temp.j(v_y, '80', format('SELECT public.submit_dating_appeal(%L, %L, NULL)', pg_temp.key('f3'), v_r)) ->> 'reason',
    pg_temp.j(v_x, '67', format('SELECT public.submit_dating_appeal(%L, %L, %L)', pg_temp.key('f4'), v_r, repeat('x', 501))) ->> 'reason');
  IF v_got IS DISTINCT FROM 'true already_appealed appeal_unavailable invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replay, a second appeal, a stranger or a long text read %', v_got;
  END IF;
  v := pg_temp.j(v_x, '67', 'SELECT public.get_my_dating_restriction()');
  IF (v #>> '{restriction,can_appeal}')::boolean OR v #>> '{restriction,appeal,state}' IS DISTINCT FROM 'open' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after the appeal the read is %', v;
  END IF;
  -- A hold is not appealable until decided.
  v_hold := private.dating_place_restriction(v_z, 'moderation_hold', 'csam', 'report', NULL, NULL, NULL, false);
  IF pg_temp.j(v_z, '82', format('SELECT public.submit_dating_appeal(%L, %L, NULL)', pg_temp.key('f5'), v_hold)) ->> 'reason'
       IS DISTINCT FROM 'appeal_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hold could be appealed';
  END IF;
  -- Mutant 15: the decider of the restriction can't decide its appeal.
  IF private.dating_decide_appeal(v_a, v_mod, false, true) IS DISTINCT FROM '{"ok": false, "reason": "same_decider"}'::jsonb
     OR private.dating_decide_appeal(v_a, v_mod, true, true) IS DISTINCT FROM '{"ok": false, "reason": "same_decider"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the first decider decided the appeal';
  END IF;
  v := private.dating_decide_appeal(v_a, v_mod2, false, true);
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT lifted_at IS NULL FROM public.dating_account_restrictions WHERE id = v_r)
     OR (SELECT state || '/' || pause_reason FROM public.dating_enrollments WHERE user_id = v_x) IS DISTINCT FROM 'paused/gates'
     OR (SELECT state || '/' || outcome || '/' || (decided_at IS NOT NULL) FROM public.dating_moderation_cases WHERE appeal_id = v_a)
        IS DISTINCT FROM 'decided/accepted/true'
     OR pg_temp.metric('dating.appeal.accepted') IS DISTINCT FROM v_acc + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an accepted appeal did not lift the restriction, pause Dating and close its case';
  END IF;
  v := pg_temp.j(v_x, '67', 'SELECT public.get_my_dating_restriction()');
  v_got := private.dating_decide_appeal(v_a, v_mod2, false, false) ->> 'reason';
  IF v IS DISTINCT FROM '{"ok": true, "restriction": null, "appeal_accepted": true}'::jsonb
     OR NOT coalesce((pg_temp.j(v_x, '67', 'SELECT public.get_dating_home()') ->> 'appeal_accepted')::boolean, false)
     OR v_got IS DISTINCT FROM 'appeal_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the accepted appeal reads % (and on the section), or was decided twice', v;
  END IF;
  -- The owner, working alone, decides their own decision's appeal only 24
  -- hours after it was sent; rejecting keeps the restriction.
  v_r2 := private.dating_place_restriction(v_y, 'suspended', 'spam', 'moderator', NULL, v_owner, NULL, true);
  PERFORM pg_temp.j(v_y, '80', format('SELECT public.submit_dating_appeal(%L, %L, NULL)', pg_temp.key('f6'), v_r2));
  SELECT id INTO v_a2 FROM public.dating_appeals WHERE restriction_id = v_r2;
  UPDATE public.dating_appeals SET submitted_at = now() - interval '23 hours' WHERE id = v_a2;
  v_got := private.dating_decide_appeal(v_a2, v_owner, true, false) ->> 'reason';
  UPDATE public.dating_appeals SET submitted_at = now() - interval '25 hours' WHERE id = v_a2;
  IF v_got IS DISTINCT FROM 'same_decider'
     OR private.dating_decide_appeal(v_a2, v_owner, false, false) ->> 'reason' IS DISTINCT FROM 'same_decider' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the solo owner decided before 24 hours, or a non-owner after';
  END IF;
  v := private.dating_decide_appeal(v_a2, v_owner, true, false);
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT lifted_at FROM public.dating_account_restrictions WHERE id = v_r2) IS NOT NULL
     OR pg_temp.j(v_y, '80', 'SELECT public.get_my_dating_restriction()') #>> '{restriction,appeal,state}' IS DISTINCT FROM 'rejected'
     OR pg_temp.metric('dating.appeal.rejected') IS DISTINCT FROM v_rej + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner''s rejection after 24 hours did not stand';
  END IF;
END $f$;

-- =====================================================================
-- G. (§6.3, §7.1, §7.2 S1, S6) Carry-over: a restriction survives the
--    account's deletion and comes back on the next account on the number,
--    from carried_over, with its category and one appeal, once; that
--    person cannot begin or activate Dating; accepting the appeal ends the
--    record. A parked account carries nothing (Spec 1 O3).
-- =====================================================================
DO $g$
DECLARE
  v_c constant uuid := pg_temp.man('70');
  v_mod constant uuid := pg_temp.ready('83');
  v_p constant uuid := pg_temp.man('72');
  v_c2 uuid;
  v_hmac text;
  v jsonb;
  v_r uuid;
  v_a uuid;
  v_got text;
BEGIN
  PERFORM private.dating_place_restriction(v_c, 'suspended', 'harassment', 'moderator', NULL, v_mod, NULL, true);
  v_hmac := public.dating_phone_hmac_for_user(v_c);
  PERFORM pg_temp.delete_account(v_c);
  IF NOT EXISTS (SELECT 1 FROM public.enforcement_records WHERE phone_hmac = v_hmac AND scope = 'dating'
                    AND restriction_type = 'suspended' AND category = 'harassment') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the suspension did not survive the deletion';
  END IF;
  v_c2 := pg_temp.man('71', '{"phone": "70"}');
  -- Beginning Dating refuses (Ruling R-55: the person's read carries it).
  v_got := pg_temp.call(v_c2, pg_temp.dev('71'), format('SELECT (public.begin_dating_enrollment(''dating-2.0'', %L)).state',
                                                       pg_temp.key('g-begin')));
  IF v_got IS DISTINCT FROM '22023:not_eligible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a carried restriction let the person begin Dating: %', v_got;
  END IF;
  v := pg_temp.j(v_c2, '71', 'SELECT public.get_my_dating_restriction()');
  PERFORM pg_temp.j(v_c2, '71', 'SELECT public.get_my_dating_restriction()');
  IF v #>> '{restriction,type}' IS DISTINCT FROM 'suspended' OR v #>> '{restriction,category}' IS DISTINCT FROM 'harassment'
     OR NOT (v #>> '{restriction,can_appeal}')::boolean
     OR pg_temp.held(v_c2) IS DISTINCT FROM 'suspended/carried_over/harassment/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the next account on the number reads % (carried once, with its appeal)', v;
  END IF;
  UPDATE public.dating_enrollments SET state = 'paused', pause_reason = 'user' WHERE user_id = v_c2;
  v_got := pg_temp.call(v_c2, pg_temp.dev('71'), format('SELECT (public.activate_dating_profile(%L)).state', pg_temp.key('g-act')));
  IF v_got IS DISTINCT FROM '22023:activation_gates_not_met' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a restricted person could activate: %', v_got;
  END IF;
  v_r := (v #>> '{restriction,id}')::uuid;
  PERFORM pg_temp.j(v_c2, '71', format('SELECT public.submit_dating_appeal(%L, %L, NULL)', pg_temp.key('g-ap'), v_r));
  SELECT id INTO v_a FROM public.dating_appeals WHERE restriction_id = v_r;
  v := private.dating_decide_appeal(v_a, v_mod, false, true);
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR NOT public.dating_account_in_good_standing(v_c2)
     OR EXISTS (SELECT 1 FROM public.enforcement_records WHERE phone_hmac = v_hmac AND scope = 'dating'
                   AND (effect_until IS NULL OR effect_until > now())) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: accepting the carried appeal left the record in force';
  END IF;
  -- A parked account (its number presumed someone else's) carries nothing.
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, category, purge_after)
  VALUES (public.dating_phone_hmac_for_user(v_p), 'dating', 'suspended', 'spam', now() + interval '1 year');
  UPDATE public.users SET phone_released_at = now(), parked_phone_hmac = public.dating_phone_hmac_for_user(v_p) WHERE id = v_p;
  v_got := private.dating_carry_over(v_p)::text;
  IF v_got <> '0' OR pg_temp.held(v_p) <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a parked account carried a record';
  END IF;
END $g$;

-- =====================================================================
-- H. (§6.3, §4.8; W5 carry T8 N-2/N-3, W6 T2 N-4, W6 T5) Deletion keeps
--    an open case open (userless, by number), so a new account on the
--    number stays throttled; a chat only the two numbers' block ended is
--    in the ended list and can be reported; a suspension that ran out or
--    was lifted becomes a pause (the cron every 15 minutes, the lift at
--    once); closing a case stamps decided_at and settles its reports; the
--    v1 report RPCs are gone.
-- =====================================================================
DO $h$
DECLARE
  v_s constant uuid := pg_temp.man('73');
  v_x constant uuid := pg_temp.ready('75');
  v_y constant uuid := pg_temp.man('76');
  v_z constant uuid := pg_temp.man('77');
  v_w constant uuid := pg_temp.man('78');
  v_q constant uuid := pg_temp.ready('79');
  v_s2 uuid;
  v_m uuid;
  v_r uuid;
  v_case uuid;
  v_hmac text;
  v jsonb;
  v_got text;
BEGIN
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, target_phone_hmac, signal_kind)
  VALUES ('signal', 'P2', v_s, public.dating_phone_hmac_for_user(v_s), 'dragnet')
  RETURNING id INTO v_case;
  v_hmac := public.dating_phone_hmac_for_user(v_s);
  PERFORM pg_temp.delete_account(v_s);
  IF (SELECT state || '/' || (target_user_id IS NULL) || '/' || (target_phone_hmac = v_hmac) FROM public.dating_moderation_cases
       WHERE id = v_case) IS DISTINCT FROM 'open/true/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the deletion closed or emptied an open case (W5 T8 N-3)';
  END IF;
  v_s2 := pg_temp.man('74', '{"phone": "73"}');
  IF NOT private.dating_throttled(v_s2) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a re-registered sender escaped the open dragnet case';
  END IF;
  -- W6 T2 N-4: blocked by the numbers alone, the chat is ended and reportable.
  v_m := pg_temp.match(v_x, v_y);
  INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac)
  VALUES (public.dating_phone_hmac_for_user(v_y), public.dating_phone_hmac_for_user(v_x));
  v := pg_temp.j(v_x, '75', 'SELECT public.get_my_dating_matches(true)');
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v -> 'ended') AS e WHERE e ->> 'match_id' = v_m::text)
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v -> 'conversations') AS e WHERE e ->> 'match_id' = v_m::text) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a chat ended by the numbers'' block is not in the ended list: %', v;
  END IF;
  v := pg_temp.report(v_x, '75', v_m, 'harassment');
  IF (v ->> 'ok') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a chat ended by the numbers'' block could not be reported: %', v;
  END IF;
  -- A suspension that ran out: the cron makes it a pause.
  v_r := private.dating_place_restriction(v_z, 'suspended', 'spam', 'moderator', NULL, v_q, now() + interval '1 hour', true);
  UPDATE public.dating_account_restrictions SET ends_at = now() - interval '1 minute' WHERE id = v_r;
  IF (SELECT state FROM public.dating_enrollments WHERE user_id = v_z) <> 'suspended' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the fixture''s suspension did not suspend';
  END IF;
  PERFORM private.dating_release_expired_suspensions();
  IF (SELECT state || '/' || pause_reason FROM public.dating_enrollments WHERE user_id = v_z) IS DISTINCT FROM 'paused/gates'
     OR NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'release-dating-suspensions' AND schedule = '*/15 * * * *'
                       AND command = 'SELECT private.dating_release_expired_suspensions()') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a suspension that ran out was not released to a pause by the 15-minute cron';
  END IF;
  -- A lift releases at once.
  v_r := private.dating_place_restriction(v_w, 'suspended', 'spam', 'moderator', NULL, v_q, NULL, true);
  UPDATE public.dating_account_restrictions SET lifted_at = now() WHERE id = v_r;
  IF (SELECT state || '/' || pause_reason FROM public.dating_enrollments WHERE user_id = v_w) IS DISTINCT FROM 'paused/gates' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a lifted suspension left Dating suspended';
  END IF;
  -- W6 T5: closing a case stamps decided_at, and settles its reports.
  SELECT case_id INTO v_case FROM public.dating_reports WHERE match_id = v_m;
  v_got := private.dating_close_case(v_case, v_q, 'bogus') ->> 'reason';
  v_got := v_got || ' ' || (private.dating_close_case(v_case, v_q, 'restricted') ->> 'ok');
  v_got := v_got || ' ' || (private.dating_close_case(v_case, v_q, 'dismissed') ->> 'reason');
  IF v_got IS DISTINCT FROM 'invalid true case_unavailable'
     OR (SELECT state || '/' || outcome || '/' || (decided_at IS NOT NULL) FROM public.dating_moderation_cases WHERE id = v_case)
        IS DISTINCT FROM 'decided/restricted/true'
     OR EXISTS (SELECT 1 FROM public.dating_reports WHERE case_id = v_case AND state <> 'upheld') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: closing a case read % without stamping it or its reports', v_got;
  END IF;
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, signal_kind)
  VALUES ('signal', 'P2', v_q, 'dragnet') RETURNING id INTO v_case;
  PERFORM private.dating_close_case(v_case, v_y, 'no_action');
  IF (SELECT state || '/' || (decided_at IS NOT NULL) FROM public.dating_moderation_cases WHERE id = v_case)
       IS DISTINCT FROM 'closed/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: closing a signal case left decided_at empty (W6 T5)';
  END IF;
  IF to_regprocedure('public.submit_dating_report(text,uuid,text,text)') IS NOT NULL
     OR to_regprocedure('public.report_dating_match(text,uuid,text,text)') IS NOT NULL
     OR to_regprocedure('public.report_dating_introduction(text,uuid,text,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a v1 report RPC is still there (§4.10)';
  END IF;
END $h$;

-- @@W7B@@
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
python3 -I $D/splice.py supabase/tests/dating_v2_moderation_contracts.sql '-- @@W7A-T2@@' $D/contract_T2.sql
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_moderation_contracts.sql 2>&1 | grep -m1 -oE 'ERROR: .*'
```

Expected: `ERROR:  invalid input syntax for type json` (section E's first call: `get_my_dating_restriction` doesn't exist yet, and the helper's raise is not an answer).

- [ ] **Step 2: The migration's Task 2 section and grants**

Create `$D/mig_T2.sql` with exactly:

```sql
-- ---------------------------------------------------------------------
-- 8. Carry-over at re-registration (§6.3): each live Dating enforcement
--    record on this number becomes a restriction of this account, from
--    'carried_over', with its category and its one appeal (an age review
--    goes through the ID check). Never for a parked account (Spec 1 O3,
--    built default no). Idempotent per record.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.dating_carry_over(p_user uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_hmac text;
  v_n integer;
BEGIN
  IF p_user IS NULL OR EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = p_user AND u.phone_released_at IS NOT NULL) THEN
    RETURN 0;
  END IF;
  v_hmac := public.dating_phone_hmac_for_user(p_user);
  IF v_hmac IS NULL THEN
    RETURN 0;
  END IF;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, case_id, ends_at,
                                                  appealable, carried_from)
  SELECT p_user, er.restriction_type, er.category, 'carried_over',
         (SELECT c.id FROM public.dating_moderation_cases AS c WHERE c.id = er.case_id),
         er.effect_until, er.restriction_type <> 'age_review', er.id
    FROM public.enforcement_records AS er
   WHERE er.scope = 'dating' AND er.phone_hmac = v_hmac
     AND (er.effect_until IS NULL OR er.effect_until > now()) AND er.purge_after > now()
     AND er.restriction_type IN ('suspended', 'under_review', 'age_review', 'moderation_hold')
     AND NOT EXISTS (SELECT 1 FROM public.dating_account_restrictions AS x
                      WHERE x.user_id = p_user AND x.carried_from = er.id)
  ON CONFLICT (user_id, carried_from) WHERE carried_from IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n > 0 THEN
    PERFORM private.bump_metric_internal('dating.carry_over.applied');
  END IF;
  RETURN v_n;
END;
$$;

-- ---------------------------------------------------------------------
-- 9. The cron for a suspension that ran out (the lift's release is in
--    section 6): every 15 minutes, users key-share, skip locked, each
--    person in its own block, counted.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.dating_release_expired_suspensions()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user uuid;
  v_n integer := 0;
BEGIN
  FOR v_user IN
    SELECT e.user_id FROM public.dating_enrollments AS e
     WHERE e.state = 'suspended'
       AND NOT EXISTS (SELECT 1 FROM public.dating_account_restrictions AS r
                        WHERE r.user_id = e.user_id AND r.restriction_type IN ('suspended', 'age_review')
                          AND r.lifted_at IS NULL AND r.starts_at <= now() AND (r.ends_at IS NULL OR r.ends_at > now()))
     ORDER BY e.user_id
     LIMIT 500
  LOOP
    BEGIN
      PERFORM 1 FROM public.users AS u WHERE u.id = v_user FOR KEY SHARE SKIP LOCKED;
      IF NOT FOUND THEN
        PERFORM private.bump_metric_internal('dating.release.busy');
        CONTINUE;
      END IF;
      IF private.dating_release_suspension(v_user) THEN
        v_n := v_n + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      PERFORM private.bump_metric_internal('dating.release.failed');
    END;
  END LOOP;
  RETURN v_n;
END;
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname = 'cron') THEN
    PERFORM cron.unschedule(j.jobid) FROM cron.job AS j WHERE j.jobname = 'release-dating-suspensions';
    PERFORM cron.schedule('release-dating-suspensions', '*/15 * * * *', $c$SELECT private.dating_release_expired_suspensions()$c$);
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- 10. What the restricted person sees (§3.7): the restriction shown
--     first (closed for good, then until a date, then the age check,
--     then a hold; a closer look never), its category, whether it can be
--     appealed, and the appeal's state. Never who reported, what they
--     wrote, the evidence, the case or who decided. A read that writes
--     (the carry-over, a release): VOLATILE. Not phone-checked: a
--     restricted person may not be able to check a new phone (R-54).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_dating_restriction()
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  r public.dating_account_restrictions;
  a public.dating_appeals;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  PERFORM private.dating_carry_over(v_user);
  PERFORM private.dating_release_suspension(v_user);
  SELECT * INTO r FROM public.dating_account_restrictions AS x
   WHERE x.user_id = v_user AND x.restriction_type <> 'under_review'
     AND x.lifted_at IS NULL AND x.starts_at <= now() AND (x.ends_at IS NULL OR x.ends_at > now())
   ORDER BY CASE WHEN x.restriction_type = 'suspended' AND x.ends_at IS NULL THEN 0
                 WHEN x.restriction_type = 'suspended' THEN 1
                 WHEN x.restriction_type = 'age_review' THEN 2 ELSE 3 END,
            x.ends_at DESC NULLS FIRST, x.created_at DESC
   LIMIT 1;
  IF r.id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'restriction', NULL,
                                         'appeal_accepted', private.dating_appeal_accepted(v_user));
  END IF;
  SELECT * INTO a FROM public.dating_appeals AS x WHERE x.restriction_id = r.id;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'appeal_accepted', private.dating_appeal_accepted(v_user),
    'restriction', pg_catalog.jsonb_build_object(
      'id', r.id,
      'type', CASE r.restriction_type WHEN 'moderation_hold' THEN 'hold' ELSE r.restriction_type END,
      'ends_at', r.ends_at,
      'category', r.category,
      'can_appeal', r.appealable AND a.id IS NULL,
      'appeal', CASE WHEN a.id IS NULL THEN NULL
                     ELSE pg_catalog.jsonb_build_object('state', a.state, 'submitted_at', a.submitted_at,
                                                        'decided_at', a.decided_at) END));
END;
$$;

-- An appeal of this person's accepted in the last 7 days (§3.7: "Your
-- appeal was accepted. Dating is open again.", on the Dating section).
CREATE OR REPLACE FUNCTION private.dating_appeal_accepted(p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.dating_appeals AS a
                  WHERE a.user_id = p_user AND a.state = 'accepted' AND a.decided_at > now() - interval '7 days');
$$;

-- ---------------------------------------------------------------------
-- 11. One appeal (§3.7, §6.3): to a live, appealable restriction of the
--     caller's, once; it opens an appeal case due in 7 days. Not
--     phone-checked (R-54). The text is optional, at most 500 characters.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_dating_appeal(p_idempotency_key text, p_restriction_id uuid, p_text text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_text constant text := NULLIF(btrim(coalesce(p_text, '')), '');
  r public.dating_account_restrictions;
  v_appeal uuid;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_restriction_id IS NULL OR NOT private.dating_key_ok(p_idempotency_key) OR coalesce(char_length(v_text), 0) > 500 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(v_user);
      IF EXISTS (SELECT 1 FROM public.dating_rpc_idempotency AS k
                  WHERE k.user_id = v_user AND k.operation = 'submit_dating_appeal' AND k.idempotency_key = p_idempotency_key) THEN
        RETURN pg_catalog.jsonb_build_object('ok', true);
      END IF;
      SELECT * INTO r FROM public.dating_account_restrictions AS x
       WHERE x.id = p_restriction_id AND x.user_id = v_user
       FOR UPDATE;
      IF r.id IS NULL OR NOT r.appealable OR r.lifted_at IS NOT NULL OR r.starts_at > now()
         OR (r.ends_at IS NOT NULL AND r.ends_at <= now()) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'appeal_unavailable');
      END IF;
      IF EXISTS (SELECT 1 FROM public.dating_appeals AS a WHERE a.restriction_id = r.id) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'already_appealed');
      END IF;
      PERFORM public.claim_dating_idempotency('submit_dating_appeal', p_idempotency_key);
      INSERT INTO public.dating_appeals (restriction_id, user_id, text) VALUES (r.id, v_user, v_text)
      RETURNING id INTO v_appeal;
      INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, target_phone_hmac, appeal_id, sla_due_at)
      VALUES ('appeal', 'P2', v_user, public.dating_phone_hmac_for_user(v_user), v_appeal, now() + interval '7 days');
      PERFORM private.bump_metric_internal('dating.appeal.submitted');
      RETURN pg_catalog.jsonb_build_object('ok', true);
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- ---------------------------------------------------------------------
-- 12. The decision W7b's console calls on an appeal (never a client's):
--     decided by someone other than the restriction's decider, or by the
--     safety owner at least 24 hours after the appeal when the owner made
--     the decision (§4.3, §6.3, mutant 15). Accepting lifts the
--     restriction (the lift releases the suspension) and ends a carried
--     record. (Closing a case is Task 1's, section 7b.)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.dating_decide_appeal(p_appeal uuid, p_decider uuid, p_decider_owner boolean,
                                                        p_accept boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  a public.dating_appeals;
  r public.dating_account_restrictions;
  v_case uuid;
  v_country text;
BEGIN
  IF p_appeal IS NULL OR p_decider IS NULL OR p_accept IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  SELECT * INTO a FROM public.dating_appeals AS x WHERE x.id = p_appeal FOR UPDATE;
  IF a.id IS NULL OR a.state <> 'open' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'appeal_unavailable');
  END IF;
  SELECT * INTO r FROM public.dating_account_restrictions AS x WHERE x.id = a.restriction_id FOR UPDATE;
  IF r.decided_by IS NOT NULL AND r.decided_by = p_decider
     AND NOT (coalesce(p_decider_owner, false) AND now() >= a.submitted_at + interval '24 hours') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'same_decider');
  END IF;
  UPDATE public.dating_appeals AS x
     SET state = CASE WHEN p_accept THEN 'accepted' ELSE 'rejected' END, decided_by = p_decider, decided_at = now()
   WHERE x.id = a.id;
  SELECT c.id INTO v_case FROM public.dating_moderation_cases AS c
   WHERE c.appeal_id = a.id AND c.state IN ('open', 'in_review');
  IF v_case IS NOT NULL THEN
    PERFORM private.dating_close_case(v_case, p_decider, CASE WHEN p_accept THEN 'accepted' ELSE 'rejected' END);
  END IF;
  IF p_accept THEN
    UPDATE public.dating_account_restrictions AS x SET lifted_at = now() WHERE x.id = r.id AND x.lifted_at IS NULL;
    IF r.carried_from IS NOT NULL THEN
      UPDATE public.enforcement_records AS er SET effect_until = now()
       WHERE er.id = r.carried_from AND (er.effect_until IS NULL OR er.effect_until > now());
    END IF;
    UPDATE public.dating_reports AS x SET state = 'not_upheld' WHERE r.case_id IS NOT NULL AND x.case_id = r.case_id;
    SELECT lower(p.country_code::text) INTO v_country FROM public.dating_profiles AS p WHERE p.user_id = a.user_id;
    PERFORM private.bump_metric_internal('dating.appeal.accepted');
    IF v_country ~ '^[a-z]{2}$' THEN
      PERFORM private.bump_metric_internal('dating.overturned.' || v_country);
    END IF;
  ELSE
    PERFORM private.bump_metric_internal('dating.appeal.rejected');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true);
END;
$$;
```

Create `$D/twin_T2.sql` with exactly:

```sql
-- Task 2: the restricted person's read and the appeal are the app's; the
-- carry-over, the release cron and the appeal's decision are the database's own.
REVOKE ALL ON FUNCTION private.dating_carry_over(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_release_expired_suspensions() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_appeal_accepted(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_decide_appeal(uuid, uuid, boolean, boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_my_dating_restriction() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_dating_restriction() TO authenticated;
REVOKE ALL ON FUNCTION public.submit_dating_appeal(text, uuid, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.submit_dating_appeal(text, uuid, text) TO authenticated;
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
python3 -I $D/splice.py supabase/migrations/20261121100010_dating_v2_reports_grants.sql '-- @@W7A-T2-GRANTS@@' $D/twin_T2.sql
python3 -I $D/build_mig_W7a.py
for f in supabase/migrations/20261121100000_dating_v2_reports.sql supabase/migrations/20261121100010_dating_v2_reports_grants.sql; do
  for run in 1 2; do psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $f > /dev/null 2> $D/apply_err.txt; rc=$?; echo "$(basename $f) run $run exit=$rc"; grep -v NOTICE $D/apply_err.txt || true; done
done
python3 -I $D/marked_diff.py $D/before_w7a attune_spec3a 'Spec 2 W7a'; echo "marked_diff exit=$?"
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_moderation_contracts.sql 2>&1 | tail -1
```

Expected: `…_grants.sql: twin_T2.sql spliced at -- @@W7A-T2-GRANTS@@`; `supabase/migrations/20261121100000_dating_v2_reports.sql: 10 re-created function(s), 1765 lines`; four `exit=0` lines; the ten marked-diff lines `OK`, `public.get_dating_home(): 2 added line(s), 1 removed OK` now, and `marked_diff exit=0`; `psql:supabase/tests/dating_v2_moderation_contracts.sql:998: NOTICE:  dating_v2_moderation_contracts: all held`.

- [ ] **Step 3: The canary and the races**

Create `$D/edit_tests_T2.py` with exactly:

```python
#!/usr/bin/env python3
# Spec 2 W7a Task 2: the canary takes the restricted person's read and the
# appeal (the app's), and the carry-over, the release cron and the
# appeal's decision W7b's console calls (the database's own).
import importlib.util

spec = importlib.util.spec_from_file_location('anchor', '.superpowers/sdd/2026-11-21-spec2-w7/anchor.py')
anchor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(anchor)

anchor.edit('supabase/tests/dating_rls_canary.sql', [(
    """-- @@W7A-T2-CANARY@@
""",
    """-- Spec 2 W7a Task 2: the restricted person's read and the appeal are the
-- app's; the rest is the database's own.
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('get_my_dating_restriction()', 'authenticated', ''),
  ('submit_dating_appeal(text,uuid,text)', 'authenticated', ''),
  ('private.dating_carry_over(uuid)', '', ''),
  ('private.dating_release_expired_suspensions()', '', ''),
  ('private.dating_appeal_accepted(uuid)', '', ''),
  ('private.dating_decide_appeal(uuid,uuid,boolean,boolean)', '', '');
""")], 'W7a Task 2')
```

Create `$D/edit_races_T2.py` with exactly:

```python
#!/usr/bin/env python3
# Spec 2 W7a Task 2: two race cases. Two P0 reports about one person at
# the same moment make one case and one hold (the target's report lock
# serialises them, so the second sees the first); a report while the
# reported person leaves completes with no deadlock (the report waits on
# the match row the leave holds, then finds it ended within its window).
# The reset clears the race people's reports and cases.
import importlib.util

spec = importlib.util.spec_from_file_location('anchor', '.superpowers/sdd/2026-11-21-spec2-w7/anchor.py')
anchor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(anchor)

P = 'scripts/concurrency/dating_kill_switch_races.sh'
anchor.edit(P, [
    ("""#   a leave vs the same person's send from another phone (Spec 2 W6 final
#     server fix, I-5): every closer locks the match before it bumps a
#     chat signal, send's order, so they serialise: no deadlock.
""", """#   a leave vs the same person's send from another phone (Spec 2 W6 final
#     server fix, I-5): every closer locks the match before it bumps a
#     chat signal, send's order, so they serialise: no deadlock.
#   two P0 reports about one person at once (Spec 2 W7a, §6.2): the
#     target's report lock serialises them, so the second sees the first:
#     one case, one hold, both answered.
#   a report while the reported person leaves (Spec 2 W7a): the report
#     waits on the match row the leave holds, then finds the conversation
#     ended within its 30 days: both land, no deadlock.
"""),
    ("""# Spec 2 W3c (Task 9, B; R-25): a gone hit's Dating hold
# (record_dating_csam_hold, the photo row deleted mid-scan) takes the
# person's setup lock before the enrolment and profile its hold suspends
# (it sleeps holding the enrolment), as exit does: the two serialise, exit
# completes and the hold is kept.
run "a gone hit's Dating hold vs exit (the hold first)" "$FX_PHOTO" \\
  "SET race.sleep_dating_profiles_update = '2:race.s1';
   SELECT public.record_dating_csam_hold(race.id('04')) ->> 'ok';" \\
  "SELECT pg_sleep(0.5);
   SELECT race.call(race.id('04'), format('SELECT to_jsonb(public.exit_dating_mode(%L))', race.key('exit'))) ->> 'state';" \\
  "SELECT CASE WHEN NOT (SELECT is_called FROM race.s1) THEN 'the hold never reached the profile (no race)'""",
     """# Spec 2 W3c (Task 9, B; R-25): a gone hit's Dating hold
# (record_dating_csam_hold, the photo row deleted mid-scan) takes the
# person's setup lock before the rows its hold changes, as exit does: the
# two serialise, exit completes and the hold is kept. Spec 2 W7a (§6.3): a
# hold no longer suspends the enrolment or pauses the profile; it takes
# the person's introductions away, so it sleeps holding one of those.
run "a gone hit's Dating hold vs exit (the hold first)" "$FX_PHOTO
SELECT race.person('06', 'GB', 'TLI', 'man', ARRAY['woman']);
SELECT race.intro(race.id('04'), race.id('06'));" \\
  "SET race.sleep_dating_introductions_update = '2:race.s1';
   SELECT public.record_dating_csam_hold(race.id('04')) ->> 'ok';" \\
  "SELECT pg_sleep(0.5);
   SELECT race.call(race.id('04'), format('SELECT to_jsonb(public.exit_dating_mode(%L))', race.key('exit'))) ->> 'state';" \\
  "SELECT CASE WHEN NOT (SELECT is_called FROM race.s1) THEN 'the hold never reached the introductions (no race)'"""),
    ("""  DELETE FROM public.dating_rpc_idempotency WHERE user_id::text LIKE '5e2f%';
""", """  DELETE FROM public.dating_rpc_idempotency WHERE user_id::text LIKE '5e2f%';
  DELETE FROM public.dating_reports WHERE reporter_user_id::text LIKE '5e2f%' OR target_user_id::text LIKE '5e2f%'; -- Spec 2 W7a
  DELETE FROM public.dating_moderation_cases WHERE target_user_id::text LIKE '5e2f%'; -- Spec 2 W7a
"""),
    ("""$P -c "SELECT race.reset(); UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_candidate_generation';" > /dev/null 2>&1
exit $fail""", """# Spec 2 W7a (§6.2): two P0 reports about one person at once. B (51)
# reports csam and sleeps in the P0 close's match update, holding the
# target's report lock; C (52, its own phone) reports threat_to_life 0.5 s
# in: it waits on that lock, then sees B's counting report: one case with
# both reports, one moderation_hold, both answered ok, no deadlock.
FX_TWO_P0="SELECT race.reset(); ALTER SEQUENCE race.s1 RESTART;
SELECT race.ready('51', 'woman', ARRAY['man']), race.ready('52', 'woman', ARRAY['man']), race.ready('53', 'man', ARRAY['woman']);
UPDATE public.dating_trusted_devices SET device_hash = encode(extensions.digest('race-device-52', 'sha256'), 'hex')
 WHERE user_id = race.id('52');
INSERT INTO race.outcome SELECT 'p0_m1', race.match(race.id('51'), race.id('53'))::text;
INSERT INTO race.outcome SELECT 'p0_m2', race.match(race.id('52'), race.id('53'))::text;"
P0_M1="(SELECT result::uuid FROM race.outcome WHERE name = 'p0_m1')"
P0_M2="(SELECT result::uuid FROM race.outcome WHERE name = 'p0_m2')"
run "two P0 reports about one person at once: one case, one hold" "$FX_TWO_P0" \\
  "SET race.sleep_dating_matches_update = '1.5:race.s1';
   INSERT INTO race.outcome VALUES ('p0_a', race.call(race.id('51'), format('SELECT public.report_dating_match(%L, %L, ''csam'', NULL, false)', race.key('p0a'), $P0_M1))::text);" \\
  "SELECT pg_sleep(0.5);
   INSERT INTO race.outcome SELECT 'p0_overlap', (SELECT is_called FROM race.s1)::text;
   SELECT clock_timestamp() AS tb \\\\gset
   INSERT INTO race.outcome VALUES ('p0_b', race.call(race.id('52'), format('SELECT public.report_dating_match(%L, %L, ''threat_to_life'', NULL, false)', race.key('p0b'), $P0_M2))::text);
   INSERT INTO race.outcome VALUES ('p0_b_s', round(extract(epoch FROM clock_timestamp() - :'tb'::timestamptz), 2)::text);" \\
  "SELECT CASE WHEN (SELECT result::jsonb ->> 'ok' FROM race.outcome WHERE name = 'p0_a') IS DISTINCT FROM 'true'
                 OR (SELECT result::jsonb ->> 'ok' FROM race.outcome WHERE name = 'p0_b') IS DISTINCT FROM 'true'
               THEN 'a report answered ' || coalesce((SELECT string_agg(result, ' | ') FROM race.outcome WHERE name IN ('p0_a', 'p0_b')), 'none')
               WHEN (SELECT count(*) FROM public.dating_account_restrictions WHERE user_id = race.id('53')
                       AND restriction_type = 'moderation_hold' AND lifted_at IS NULL) <> 1 THEN 'not exactly one hold'
               WHEN (SELECT count(*) FROM public.dating_moderation_cases WHERE target_user_id = race.id('53') AND kind = 'report'
                       AND state IN ('open', 'in_review')) <> 1 THEN 'not exactly one open case'
               WHEN (SELECT count(*) FROM public.dating_reports AS r JOIN public.dating_moderation_cases AS c ON c.id = r.case_id
                      WHERE c.target_user_id = race.id('53')) <> 2 THEN 'the case does not hold both reports'
               WHEN (SELECT result FROM race.outcome WHERE name = 'p0_overlap') IS DISTINCT FROM 'true'
                 OR coalesce((SELECT result::numeric FROM race.outcome WHERE name = 'p0_b_s'), 0) < 0.5
               THEN 'the second report did not wait on the first (no race)'
               ELSE 'ok' END;" serialised

# Spec 2 W7a: a report while the reported person leaves. T (55) leaves and
# sleeps in exit's match update (holding the match row); R (54) reports
# with the block 0.5 s in: the report waits on the row, then reads the
# conversation ended (exit, its 30-day window), files the report and the
# block. No deadlock; the leave lands.
FX_REPORT_EXIT="SELECT race.reset(); ALTER SEQUENCE race.s1 RESTART;
SELECT race.ready('54', 'woman', ARRAY['man']), race.ready('55', 'man', ARRAY['woman']);
INSERT INTO race.outcome SELECT 're_match', race.match(race.id('54'), race.id('55'))::text;"
RE_MATCH="(SELECT result::uuid FROM race.outcome WHERE name = 're_match')"
run "a report while the reported person leaves: no deadlock" "$FX_REPORT_EXIT" \\
  "SET race.sleep_dating_matches_update = '1.5:race.s1';
   INSERT INTO race.outcome VALUES ('re_exit', race.call(race.id('55'), format('SELECT to_jsonb(public.exit_dating_mode(%L))', race.key('re-exit'))) ->> 'state');" \\
  "SELECT pg_sleep(0.5);
   INSERT INTO race.outcome SELECT 're_overlap', (SELECT is_called FROM race.s1)::text;
   INSERT INTO race.outcome VALUES ('re_report', race.call(race.id('54'), format('SELECT public.report_dating_match(%L, %L, ''threats'', NULL, true)', race.key('re-report'), $RE_MATCH))::text);" \\
  "SELECT CASE WHEN (SELECT result FROM race.outcome WHERE name = 're_exit') IS DISTINCT FROM 'exited' THEN 'leave lost'
               WHEN (SELECT result::jsonb ->> 'ok' FROM race.outcome WHERE name = 're_report') IS DISTINCT FROM 'true'
               THEN 'the report answered ' || coalesce((SELECT result FROM race.outcome WHERE name = 're_report'), 'none')
               WHEN NOT EXISTS (SELECT 1 FROM public.dating_reports WHERE reporter_user_id = race.id('54') AND match_id = $RE_MATCH)
               THEN 'no report was filed'
               WHEN NOT EXISTS (SELECT 1 FROM public.dating_blocks WHERE blocker_user_id = race.id('54') AND blocked_user_id = race.id('55'))
               THEN 'the block was lost'
               WHEN (SELECT result FROM race.outcome WHERE name = 're_overlap') IS DISTINCT FROM 'true'
               THEN 'the leave was not holding the match (no race)'
               ELSE 'ok' END;" serialised

$P -c "SELECT race.reset(); UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_candidate_generation';" > /dev/null 2>&1
exit $fail"""),
], 'W7a Task 2')
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
python3 -I $D/edit_tests_T2.py
python3 -I $D/edit_races_T2.py
bash -n scripts/concurrency/dating_kill_switch_races.sh && echo "syntax ok"
$D/suite.sh attune_spec3a > $D/sql-after-T2.txt; echo "$(grep -c '^PASS' $D/sql-after-T2.txt) PASS, $(grep -c '^FAIL' $D/sql-after-T2.txt) FAIL"
diff <(grep FAIL $D/sql-baseline.txt) <(grep FAIL $D/sql-after-T2.txt)
```

Expected: `dating_rls_canary.sql: 1 edit(s) (W7a Task 2)`; `dating_kill_switch_races.sh: 4 edit(s) (W7a Task 2)`; `syntax ok`; `162 PASS, 14 FAIL`; no diff.

The race script runs at the W7a gate (Task 4 Step 6), on a scratch database, when the machine is idle.

- [ ] **Step 4: The mutants (§7.5 mutant 15; carries 3, 6, 8), and Task 1's again**

Create `$D/mut_T2.py` with exactly:

```python
# Spec 2 W7a Task 2 mutants (mutate.py on 20261121100000_dating_v2_reports.sql):
# each must make dating_v2_moderation_contracts.sql fail with a CONTRACT VIOLATED line.
MUTS = {
    # §7.5 mutant 15: the same decider on an appeal.
    'm15_same_decider': ("  IF r.decided_by IS NOT NULL AND r.decided_by = p_decider\n", "  IF false AND r.decided_by = p_decider\n"),
    'owner_no_wait': ("     AND NOT (coalesce(p_decider_owner, false) AND now() >= a.submitted_at + interval '24 hours') THEN",
                      "     AND NOT coalesce(p_decider_owner, false) THEN"),
    'owner_bit_ignored': ("     AND NOT (coalesce(p_decider_owner, false) AND now() >= a.submitted_at + interval '24 hours') THEN",
                          "     AND NOT (now() >= a.submitted_at + interval '24 hours') THEN"),
    'hold_appealable': ("     OR (NEW.restriction_type = 'moderation_hold' AND NEW.source IS DISTINCT FROM 'carried_over') THEN",
                        "     OR false THEN"),
    'accept_no_lift': ("    UPDATE public.dating_account_restrictions AS x SET lifted_at = now() WHERE x.id = r.id AND x.lifted_at IS NULL;",
                       "    NULL;"),
    'accept_record_kept': ("      UPDATE public.enforcement_records AS er SET effect_until = now()\n       WHERE er.id = r.carried_from",
                           "      UPDATE public.enforcement_records AS er SET effect_until = er.effect_until\n       WHERE er.id = r.carried_from"),
    'lift_no_release': ("    PERFORM private.dating_release_suspension(NEW.user_id); -- Spec 2 W7a: an ended suspension becomes a pause",
                        "    NULL; -- Spec 2 W7a: an ended suspension becomes a pause"),
    'cron_missing': ("    PERFORM cron.schedule('release-dating-suspensions', '*/15 * * * *', $c$SELECT private.dating_release_expired_suspensions()$c$);",
                     "    NULL;"),
    'sweep_skips': ("      IF private.dating_release_suspension(v_user) THEN", "      IF false THEN"),
    'carry_none': ("  ON CONFLICT (user_id, carried_from) WHERE carried_from IS NOT NULL DO NOTHING;\n  GET DIAGNOSTICS v_n = ROW_COUNT;",
                   "  ON CONFLICT (user_id, carried_from) WHERE carried_from IS NOT NULL DO NOTHING;\n  DELETE FROM public.dating_account_restrictions AS x WHERE x.user_id = p_user AND x.source = 'carried_over';\n  GET DIAGNOSTICS v_n = ROW_COUNT;"),
    'carry_parked': ("  IF p_user IS NULL OR EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = p_user AND u.phone_released_at IS NOT NULL) THEN",
                     "  IF p_user IS NULL THEN"),
    'carry_no_appeal': ("         er.effect_until, er.restriction_type <> 'age_review', er.id", "         er.effect_until, false, er.id"),
    'read_shows_closer_look': ("   WHERE x.user_id = v_user AND x.restriction_type <> 'under_review'", "   WHERE x.user_id = v_user"),
    'read_names_case': ("      'category', r.category,\n", "      'category', r.category, 'case', r.case_id,\n"),
    'read_order_hold_first': ("   ORDER BY CASE WHEN x.restriction_type = 'suspended' AND x.ends_at IS NULL THEN 0",
                              "   ORDER BY CASE WHEN x.restriction_type = 'suspended' AND x.ends_at IS NULL THEN 4"),
    'appeal_on_hold_allowed': ("      IF r.id IS NULL OR NOT r.appealable OR r.lifted_at IS NOT NULL", "      IF r.id IS NULL OR r.lifted_at IS NOT NULL"),
    'appeal_stranger': ("       WHERE x.id = p_restriction_id AND x.user_id = v_user\n       FOR UPDATE;",
                        "       WHERE x.id = p_restriction_id\n       FOR UPDATE;"),
    'close_no_decided_at': ("         decided_at = now(), outcome = p_outcome", "         outcome = p_outcome"),
    'close_reports_untouched': ("   WHERE r.case_id = p_case;\n  RETURN pg_catalog.jsonb_build_object('ok', true);",
                                "   WHERE false;\n  RETURN pg_catalog.jsonb_build_object('ok', true);"),
    'deletion_closes_cases': ("    -- 4. Reports about the person keep the number's HMAC (the cascade sets",
                              "    UPDATE public.dating_moderation_cases AS c SET state = 'closed', decided_at = now() WHERE c.target_user_id = p_user;\n    -- 4. Reports about the person keep the number's HMAC (the cascade sets"),
    'ended_hides_number_block': ("            OR (m.state = 'active' AND private.dating_pair_blocked(m.user_low_id, m.user_high_id))); -- Spec 2 W7a (W6 T2 N-4)",
                                 "            OR false); -- Spec 2 W7a (W6 T2 N-4)"),
    'closer_look_visible': ("      AND dar.restriction_type <> 'under_review' -- Spec 2 W7a (§6.3): a closer look is never visible",
                            "      AND true -- Spec 2 W7a (§6.3): a closer look is never visible"),
    'closer_look_generated': ("     OR EXISTS (SELECT 1 FROM public.dating_account_restrictions AS r -- Spec 2 W7a (§6.3): a closer look",
                              "     OR false AND EXISTS (SELECT 1 FROM public.dating_account_restrictions AS r -- Spec 2 W7a (§6.3): a closer look"),
    'home_never_says_accepted': ("           || CASE WHEN private.dating_appeal_accepted(v_user) THEN", "           || CASE WHEN false THEN"),
}
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
python3 -I $D/mutate.py supabase/migrations/20261121100000_dating_v2_reports.sql supabase/tests/dating_v2_moderation_contracts.sql $D/mut_T2.py $D/mut supabase/migrations/20261121100010_dating_v2_reports_grants.sql > $D/mut_T2.txt 2>&1
grep -c 'CONTRACT VIOLATED' $D/mut_T2.txt; grep -v 'CONTRACT VIOLATED' $D/mut_T2.txt
python3 -I $D/mutate.py supabase/migrations/20261121100000_dating_v2_reports.sql supabase/tests/dating_v2_moderation_contracts.sql $D/mut_T1.py $D/mut supabase/migrations/20261121100010_dating_v2_reports_grants.sql > $D/mut_T1b.txt 2>&1
grep -c 'CONTRACT VIOLATED' $D/mut_T1b.txt; grep -v 'CONTRACT VIOLATED' $D/mut_T1b.txt
```

Expected: `24` and nothing else; `29` and nothing else (Task 1's set on the full migration). Among Task 2's: `m15_same_decider: ERROR:  CONTRACT VIOLATED: …`, `carry_none: …`, `close_no_decided_at: …`, `deletion_closes_cases: …`.

- [ ] **Step 5: Record the tree**

Do not commit; record the tree in the report.

### Task 3: Report in the app: the data layer, the sheet, the Safety sheet, each card, the ended list, Today's card (§3.5, §3.6, §3.7, §3.15 Report; D8; carries 2, 7, 11; R-43, R-50, R-63)

**Files:**
- Create: `lib/features/dating/report/{dating_report.dart, dating_report_repository.dart, dating_report_providers.dart, report_sheet.dart}`, `test/features/dating/support/dating_report_fakes.dart`, `test/features/dating/report/report_sheet_test.dart` and its goldens (`dating_report_sheet.*`), `$D/{arb_fragment_T3.txt, edit_app_T3.py, mut_T3_dart.py}`
- Modify: `lib/features/dating/chat/{chat_sheets,safety_card,dating_chat_screen,conversations_screen}.dart`, `lib/features/dating/today/{block_sheet,today_screen}.dart`, `lib/i10n/app_en.arb` + generated; regenerates `test/features/dating/chat/goldens/dating_chat_card.*` (the card's Report button) and `test/features/dating/today/goldens/today_more_sheet.*` (the More sheet's Report row)

**Interfaces:**
- Consumes: Task 1's `report_dating_match`, `report_dating_introduction`; Task 2's `get_my_dating_restriction`, `submit_dating_appeal`; W3's `DatingRpc`, `DatingActionKeys`, `datingAccountProvider`, `datingOnlineProvider`, `datingSheetSettings`, `DatingSheetTracker`; W6's `showDatingSafetySheet`, `DatingSafetyCardView`, `showDatingCardMoreSheet`, `FakeDatingChat`, `FakeDatingToday`, `pumpDatingShell`.
- Produces: `DatingReportCategory` (14, in §3.7's order), `datingReportLabel`, `DatingReportAnswer`, `DatingRestriction`, `DatingRestrictionRead`, `DatingAppeal`, `DatingReportTarget` (`DatingReportMatch`, `DatingReportCard`), `DatingReportOutcome`; `DatingReportGateway` (`reportMatch`, `reportIntroduction`, `restriction`, `appeal`), `DatingReportRepository`, `datingReportGatewayProvider`, `datingRestrictionProvider` (per account, autoDispose); `showDatingReportSheet(context, account, name, target) → DatingReportOutcome?`; `DatingSafetyChoice.report`; `DatingCardMore {report, block}`; test `FakeDatingReport`, `datingReportOverrides`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/dating/support/dating_report_fakes.dart` with exactly:

```dart
// Spec 2 W7a: the report gateway faked as the server answers: a report or
// an appeal is ok (testing, P2's 48 hours) unless a test sets an answer;
// every call is recorded with its key, so a retry after busy is seen to be
// the same request; the support directory is faked with a Ghana-style
// emergency number unless a test asks for none.
import 'dart:async';

import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/report/dating_report_providers.dart';
import 'package:attune/features/dating/report/dating_report_repository.dart';
import 'package:attune/features/safety/data/support_resources_repository.dart';
import 'package:attune/features/safety/presentation/providers/support_resources_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingReportCall {
  const DatingReportCall(
    this.key,
    this.target,
    this.category,
    this.details,
    this.alsoBlock,
  );

  final String key;
  final DatingReportTarget target;
  final DatingReportCategory category;
  final String? details;
  final bool alsoBlock;
}

class FakeDatingReport implements DatingReportGateway {
  final reports = <DatingReportCall>[];
  final appeals = <(String, String, String?)>[];
  DatingReportAnswer answer = const DatingReportAnswer(ok: true, slaHours: 48);
  DatingReportAnswer appealAnswer = const DatingReportAnswer(ok: true);
  DatingRestrictionRead read = DatingRestrictionRead.none;
  int reads = 0;
  Completer<void>? hold;

  @override
  Future<DatingReportAnswer> report(
    String key,
    DatingReportTarget target,
    DatingReportCategory category,
    String? details, {
    required bool alsoBlock,
  }) async {
    reports.add(DatingReportCall(key, target, category, details, alsoBlock));
    final held = hold;
    if (held != null) await held.future;
    return answer;
  }

  @override
  Future<DatingRestrictionRead> restriction() async {
    reads++;
    return read;
  }

  @override
  Future<DatingReportAnswer> appeal(
    String key,
    String restrictionId,
    String? text,
  ) async {
    appeals.add((key, restrictionId, text));
    final held = hold;
    if (held != null) await held.future;
    return appealAnswer;
  }
}

const datingTestEmergency = SupportResource(
  id: 'gh-112',
  countryCode: 'GH',
  category: SupportCategory.emergency,
  name: 'Emergency',
  phone: '112',
);

List<Override> datingReportOverrides(
  FakeDatingReport fake, {
  bool emergency = true,
}) => [
  datingReportGatewayProvider.overrideWithValue(fake),
  supportCountryProvider.overrideWith((ref) async => 'GH'),
  supportResourcesProvider.overrideWith(
    (ref, country) async => SupportResources(
      country: 'GH',
      countrySupported: true,
      catalogueVersion: 'test',
      resources: emergency ? const [datingTestEmergency] : const [],
      fromServer: true,
    ),
  ),
];
```

Create `test/features/dating/report/report_sheet_test.dart` with exactly:

```dart
// Spec 2 W7a Task 3 (§3.5, §3.6, §3.7, §3.15 Report sheet; R-43; D8; W6
// carry T4): the answers fail closed; the repository sends its one RPC
// per target; the sheet: 14 labelled categories, "Also block" on for P0 to
// P2 until touched, the 500-character field, nothing sent offline, one
// key per report (a busy retry is the same request), the thanks with the
// review time or the testing line and the emergency number, the money
// line with Pause Dating; Report reaches the Safety sheet (first), each
// safety card (the reported card leaves the chat at once), the ended list
// and the card's More on Today; another account sees nothing of an open
// sheet; goldens at 1.0, 1.3, 2.0 and RTL; the three guidelines.

import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/report/dating_report_repository.dart';
import 'package:attune/features/dating/report/report_sheet.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_chat_fakes.dart';
import '../support/dating_report_fakes.dart';
import '../support/dating_shell.dart';
import '../support/dating_today_fakes.dart';

Future<void> tap(WidgetTester t, Finder finder) async {
  await tapInReach(t, finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

const _card = DatingSafetyCard(
  id: 'e1',
  messageId: 'd2',
  family: 'financial_request',
);

void main() {
  final loc = AppLocalizationsEn();

  test('the answers fail closed; the categories are §3.7\'s', () {
    expect(
      DatingReportAnswer.fromJson({
        'ok': true,
        'review': 'testing',
        'sla_hours': 48,
      }).slaHours,
      48,
    );
    expect(
      DatingReportAnswer.fromJson({'ok': true, 'review': 'staffed'}).testing,
      isFalse,
    );
    expect(DatingReportAnswer.fromJson({'ok': true}).testing, isTrue);
    for (final r in ['rate_limited', 'report_unavailable', 'invalid']) {
      expect(DatingReportAnswer.fromJson({'ok': false, 'reason': r}).reason, r);
    }
    expect(
      DatingReportAnswer.fromJson({
        'ok': false,
        'reason': 'Kofi blocked',
      }).reason,
      'failed',
    );
    expect(DatingReportAnswer.fromJson('x').reason, 'failed');
    expect(DatingReportCategory.values.map((c) => c.wire), [
      'underage_risk',
      'csam',
      'child_safety',
      'threat_to_life',
      'sextortion',
      'romance_scam',
      'threats',
      'entrapment',
      'harassment',
      'explicit_content',
      'impersonation',
      'hiding_relationship',
      'spam',
      'other',
    ]);
    expect(
      DatingReportCategory.values.where((c) => c.blockByDefault).length,
      12,
    );
    expect(DatingReportCategory.spam.blockByDefault, isFalse);
  });

  test('the repository sends one RPC per target, with the toggle', () async {
    final calls = <(String, Map<String, dynamic>?)>[];
    final repo = DatingReportRepository(
      DatingRpc.withCall((fn, params) async {
        calls.add((fn, params));
        return {'ok': true, 'review': 'testing', 'sla_hours': 4};
      }),
    );
    await repo.report(
      'k1',
      const DatingReportMatch('m1'),
      DatingReportCategory.csam,
      null,
      alsoBlock: true,
    );
    await repo.report(
      'k2',
      const DatingReportCard('i1'),
      DatingReportCategory.spam,
      'x',
      alsoBlock: false,
    );
    await repo.appeal('k3', 'r1', 'Why');
    await repo.restriction();
    expect(calls.map((c) => c.$1), [
      'report_dating_match',
      'report_dating_introduction',
      'submit_dating_appeal',
      'get_my_dating_restriction',
    ]);
    expect(calls[0].$2, {
      'p_idempotency_key': 'k1',
      'p_match_id': 'm1',
      'p_category': 'csam',
      'p_details': null,
      'p_also_block': true,
    });
    expect(calls[1].$2!['p_introduction_id'], 'i1');
    expect(calls[2].$2, {
      'p_idempotency_key': 'k3',
      'p_restriction_id': 'r1',
      'p_text': 'Why',
    });
  });

  Future<DatingShell> chat(
    WidgetTester t,
    FakeDatingReport report, {
    FakeDatingChat? fake,
    bool online = true,
    bool emergency = true,
  }) => pumpDatingShell(
    t,
    initial: '/dating/chat/m1',
    online: online,
    overrides: [
      ...datingChatOverrides(fake ?? FakeDatingChat()),
      ...datingReportOverrides(report, emergency: emergency),
    ],
  );

  Future<void> openReport(WidgetTester t) async {
    await tap(t, find.bySemanticsLabel(loc.dating_chatSafetyLabel));
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_reportTitle('Kofi')));
    await t.pumpAndSettle();
  }

  testWidgets('the Safety sheet offers Report first; the sheet sends one '
      'report with the toggle on for P0-P2 until touched, and thanks with '
      'the testing line and the number', (t) async {
    final report = FakeDatingReport();
    await chat(t, report);
    await tap(t, find.bySemanticsLabel(loc.dating_chatSafetyLabel));
    await t.pumpAndSettle();
    final first = t.getTopLeft(find.text(loc.dating_reportTitle('Kofi')));
    final block = t.getTopLeft(find.text(loc.dating_blockRow('Kofi')));
    expect(first.dy, lessThan(block.dy));
    await tap(t, find.text(loc.dating_reportTitle('Kofi')));
    await t.pumpAndSettle();
    for (final c in DatingReportCategory.values) {
      expect(find.text(datingReportLabel(loc, c)), findsOneWidget);
    }
    Switch toggle() => t.widget<Switch>(
      find.descendant(
        of: find.byKey(const ValueKey('dating_report_block')),
        matching: find.byType(Switch),
      ),
    );
    final send = find.byKey(const ValueKey('dating_report_send'));
    await tap(t, send);
    expect(report.reports, isEmpty, reason: 'no category, nothing sent');
    await tap(t, find.text(loc.dating_reportSpam));
    expect(toggle().value, isFalse);
    await tap(t, find.text(loc.dating_reportHarassment));
    expect(toggle().value, isTrue);
    await tap(t, find.byKey(const ValueKey('dating_report_block')));
    await tap(t, find.text(loc.dating_reportThreatToLife));
    expect(toggle().value, isFalse, reason: 'a touched toggle stays put');
    await t.enterText(
      find.byKey(const ValueKey('dating_report_details')),
      '  He kept writing.  ',
    );
    await tap(t, send);
    await t.pumpAndSettle();
    expect(report.reports, hasLength(1));
    final r = report.reports.single;
    expect(r.target, isA<DatingReportMatch>());
    expect(r.target.id, 'm1');
    expect(r.category, DatingReportCategory.threatToLife);
    expect(r.details, 'He kept writing.');
    expect(r.alsoBlock, isFalse);
    expect(find.text(loc.dating_reportSentTitle), findsOneWidget);
    expect(find.text(loc.dating_reportSentTesting('112')), findsOneWidget);
  });

  testWidgets('staffed: the review time in words; no emergency entry: the '
      'local line; a money report adds its line and pauses Dating', (t) async {
    final report =
        FakeDatingReport()
          ..answer = const DatingReportAnswer(
            ok: true,
            testing: false,
            slaHours: 24,
          );
    final shell = await chat(t, report, emergency: false);
    await openReport(t);
    await tap(t, find.text(loc.dating_reportMoney));
    await tap(t, find.byKey(const ValueKey('dating_report_send')));
    await t.pumpAndSettle();
    expect(
      find.text(loc.dating_reportSentNoNumber(loc.dating_reportHours(24))),
      findsOneWidget,
    );
    expect(find.text(loc.dating_reportScam), findsOneWidget);
    await tap(t, find.byKey(const ValueKey('dating_report_pause')));
    await t.pumpAndSettle();
    expect(shell.life.calls, ['pause']);
    expect(find.text(loc.dating_pausedLine), findsOneWidget);
    expect(loc.dating_reportDays(3), '3 days');
    expect(loc.dating_reportHours(1), '1 hour');
  });

  testWidgets('offline nothing is sent; busy keeps the key, so the retry '
      'is the same report; a refusal is its own line', (t) async {
    final report = FakeDatingReport();
    await chat(t, report, online: false);
    await openReport(t);
    await tap(t, find.text(loc.dating_reportSpam));
    expect(find.text(loc.dating_reportOffline), findsOneWidget);
    await tap(t, find.byKey(const ValueKey('dating_report_send')));
    expect(report.reports, isEmpty);

    final busy = FakeDatingReport()..answer = DatingReportAnswer.busy;
    await chat(t, busy);
    await openReport(t);
    await tap(t, find.text(loc.dating_reportSpam));
    await tap(t, find.byKey(const ValueKey('dating_report_send')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_busy), findsOneWidget);
    busy.answer = const DatingReportAnswer(ok: false, reason: 'rate_limited');
    await tap(t, find.byKey(const ValueKey('dating_report_send')));
    await t.pumpAndSettle();
    expect(busy.reports, hasLength(2));
    expect(busy.reports[1].key, busy.reports[0].key);
    expect(find.text(loc.dating_errorRateLimited), findsOneWidget);
  });

  testWidgets('a reported safety card leaves the chat at once, by id, and '
      'its dismissal is sent; with "Also block" the chat is ended here', (
    t,
  ) async {
    final fake = FakeDatingChat()..cardList = const [_card];
    final report = FakeDatingReport();
    await chat(t, report, fake: fake);
    expect(find.byKey(const ValueKey('dating_card_e1')), findsOneWidget);
    await tap(t, find.byKey(const ValueKey('dating_card_report')));
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_reportMoney));
    await tap(t, find.byKey(const ValueKey('dating_report_send')));
    await t.pumpAndSettle();
    await tap(t, find.byKey(const ValueKey('dating_report_close')));
    await t.pumpAndSettle();
    expect(report.reports.single.alsoBlock, isTrue);
    expect(find.byKey(const ValueKey('dating_card_e1')), findsNothing);
    expect(fake.dismissed, contains('e1'));
    expect(find.text(loc.dating_blockDone('Kofi')), findsOneWidget);
  });

  testWidgets('the ended list: its line, and only Report, for each row', (
    t,
  ) async {
    final fake = FakeDatingChat(
      list: datingConversationsJson(
        rows: const [],
        ended: [
          {
            'match_id': 'm9',
            'display_name': 'Yaw',
            'ended_at': '2026-11-19T10:00:00Z',
          },
        ],
      ),
    );
    final report = FakeDatingReport();
    await pumpDatingShell(
      t,
      initial: DatingPaths.chats,
      overrides: [
        ...datingChatOverrides(fake),
        ...datingReportOverrides(report),
      ],
    );
    expect(find.text(loc.dating_endedReportLine), findsOneWidget);
    expect(
      find.bySemanticsLabel(loc.dating_reportTitle('Yaw')),
      findsOneWidget,
    );
    await tap(t, find.byKey(const ValueKey('dating_chats_report_m9')));
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_reportSextortion));
    await tap(t, find.byKey(const ValueKey('dating_report_send')));
    await t.pumpAndSettle();
    expect(report.reports.single.target.id, 'm9');
    expect(report.reports.single.target, isA<DatingReportMatch>());
  });

  testWidgets('the card on Today: More offers Report, which reports the '
      'introduction', (t) async {
    final today = FakeDatingToday();
    final report = FakeDatingReport();
    await pumpDatingShell(
      t,
      initial: DatingPaths.today,
      overrides: [
        ...datingTodayOverrides(today),
        ...datingReportOverrides(report),
      ],
    );
    await tapInReach(t, find.text(loc.dating_cardMore));
    await t.pumpAndSettle();
    await tapInReach(t, find.text(loc.dating_reportTitle('Kofi')));
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_reportSpam));
    await tap(t, find.byKey(const ValueKey('dating_report_send')));
    await t.pumpAndSettle();
    expect(report.reports.single.target, isA<DatingReportCard>());
    expect(report.reports.single.alsoBlock, isFalse);
  });

  testWidgets('D8: another account sees nothing of an open report sheet, '
      'which closes sending nothing', (t) async {
    final report = FakeDatingReport();
    final shell = await chat(t, report);
    await openReport(t);
    expect(find.text(loc.dating_reportSend), findsOneWidget);
    await tap(t, find.text(loc.dating_reportSpam));
    shell.container.read(datingTestAccount.notifier).state = 'kwame';
    await t.pump();
    expect(find.text(loc.dating_reportSend), findsNothing);
    expect(find.text(loc.dating_reportSpam), findsNothing);
    await t.pumpAndSettle();
    expect(report.reports, isEmpty);
  });

  testWidgets('the sheet: goldens at 1.0, 1.3, 2.0 and RTL; the three '
      'guidelines; the sent state too', (t) async {
    final report = FakeDatingReport();
    Widget screen() => Consumer(
      builder:
          (context, ref, _) => const Scaffold(
            body: DatingReportSheet(
              account: 'ama',
              name: 'Kofi',
              target: DatingReportMatch('m1'),
            ),
          ),
    );
    final overrides = [
      ...datingShellOverrides(),
      ...datingReportOverrides(report),
    ];
    await expectFlowGoldens(
      t,
      'dating_report_sheet',
      screen,
      overrides: overrides,
    );
    await pumpFlowScreen(t, screen, overrides: overrides);
    await expectFlowGuidelines(t);
    await tap(t, find.text(loc.dating_reportHarassment));
    await tap(t, find.byKey(const ValueKey('dating_report_send')));
    await t.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/dating_report_sheet.sent.png'),
    );
    await expectFlowGuidelines(t);
  });
}
```

```bash
flutter test --no-pub test/features/dating/report/report_sheet_test.dart 2>&1 | grep -oE "Error: Error when reading '[^']*'" | head -1
```

Expected: `Error: Error when reading 'lib/features/dating/report/dating_report.dart'`.

- [ ] **Step 2: The copy**

Create `$D/arb_fragment_T3.txt` with exactly:

```text
  "dating_reportTitle": "Report {name}",
  "@dating_reportTitle": {"description": "Spec 2 §3.7 the report sheet's title, the Safety sheet's row, the card's and the ended row's button label. Plan copy.", "placeholders": {"name": {"type": "String"}}},
  "dating_reportTitleNoName": "Report this person",
  "@dating_reportTitleNoName": {"description": "Spec 2 §3.7 the report sheet's title with no name. Plan copy."},
  "dating_report": "Report",
  "@dating_report": {"description": "Spec 2 §3.6 a safety card's and an ended conversation's Report button; the card's More row."},
  "dating_reportWhat": "What happened?",
  "@dating_reportWhat": {"description": "Spec 2 §3.7 the categories' group label. Plan copy."},
  "dating_reportUnderage": "They might be under 18",
  "@dating_reportUnderage": {"description": "Spec 2 §3.7 underage_risk (P0)."},
  "dating_reportCsam": "Sexual content involving a child",
  "@dating_reportCsam": {"description": "Spec 2 §3.7 csam (P0)."},
  "dating_reportChildSafety": "Asked about or for access to children",
  "@dating_reportChildSafety": {"description": "Spec 2 §3.7 child_safety (P0)."},
  "dating_reportThreatToLife": "Threatened to kill or seriously hurt someone",
  "@dating_reportThreatToLife": {"description": "Spec 2 §3.7 threat_to_life (P0)."},
  "dating_reportSextortion": "Threatening to share images of me",
  "@dating_reportSextortion": {"description": "Spec 2 §3.7 sextortion (P1)."},
  "dating_reportMoney": "Asked me for money",
  "@dating_reportMoney": {"description": "Spec 2 §3.7 romance_scam (P1)."},
  "dating_reportThreats": "Threatened me",
  "@dating_reportThreats": {"description": "Spec 2 §3.7 threats (P1)."},
  "dating_reportEntrapment": "I think it's a fake profile set up to trap people",
  "@dating_reportEntrapment": {"description": "Spec 2 §3.7 entrapment (P1)."},
  "dating_reportHarassment": "Harassing me",
  "@dating_reportHarassment": {"description": "Spec 2 §3.7 harassment (P2)."},
  "dating_reportExplicit": "Sent sexual messages I didn't want",
  "@dating_reportExplicit": {"description": "Spec 2 §3.7 explicit_content (P2)."},
  "dating_reportImpersonation": "Using someone else's photos or identity",
  "@dating_reportImpersonation": {"description": "Spec 2 §3.7 impersonation (P2)."},
  "dating_reportMarried": "Married or in a relationship",
  "@dating_reportMarried": {"description": "Spec 2 §3.7 hiding_relationship (P2)."},
  "dating_reportSpam": "Spam or selling something",
  "@dating_reportSpam": {"description": "Spec 2 §3.7 spam (P3)."},
  "dating_reportOther": "Something else",
  "@dating_reportOther": {"description": "Spec 2 §3.7 other (P3)."},
  "dating_reportMore": "Tell us more (optional)",
  "@dating_reportMore": {"description": "Spec 2 §3.7 the 500-character field."},
  "dating_reportBlock": "Also block {name}",
  "@dating_reportBlock": {"description": "Spec 2 §3.7 the toggle (on for P0-P2).", "placeholders": {"name": {"type": "String"}}},
  "dating_reportBlockNoName": "Also block this person",
  "@dating_reportBlockNoName": {"description": "Spec 2 §3.7 the toggle with no name. Plan copy."},
  "dating_reportSend": "Send report",
  "@dating_reportSend": {"description": "Spec 2 §3.7 the button."},
  "dating_reportOffline": "You're offline. Your report will need a connection; nothing has been sent.",
  "@dating_reportOffline": {"description": "Spec 2 §3.15 Report sheet offline."},
  "dating_reportSentTitle": "Thanks for telling us",
  "@dating_reportSentTitle": {"description": "Spec 2 §3.7 the sent state's heading. Plan copy (the spec's first sentence, without its full stop)."},
  "dating_reportSent": "A person reviews every report, and we aim to look at reports like this within {within}. If you're in danger now, call {number}.",
  "@dating_reportSent": {"description": "Spec 2 §3.7 sent, once the moderator is named (W7 gate: matches the staffed hours). {within} is dating_reportHours or dating_reportDays; {number} the country's emergency number (S1 W7a).", "placeholders": {"within": {"type": "String"}, "number": {"type": "String"}}},
  "dating_reportSentNoNumber": "A person reviews every report, and we aim to look at reports like this within {within}. If you're in danger now, call your local emergency number.",
  "@dating_reportSentNoNumber": {"description": "Spec 2 §3.7 sent, with no emergency entry for the country. Plan copy.", "placeholders": {"within": {"type": "String"}}},
  "dating_reportSentTesting": "In testing, reports go to the test review queue. If you're in danger now, call {number}.",
  "@dating_reportSentTesting": {"description": "Spec 2 §3.7 sent, until the moderator is named (development).", "placeholders": {"number": {"type": "String"}}},
  "dating_reportSentTestingNoNumber": "In testing, reports go to the test review queue. If you're in danger now, call your local emergency number.",
  "@dating_reportSentTestingNoNumber": {"description": "Spec 2 §3.7 sent in testing, with no emergency entry. Plan copy."},
  "dating_reportHours": "{count, plural, =1{1 hour} other{{count} hours}}",
  "@dating_reportHours": {"description": "Spec 2 §3.7 {SLA in words}, under 48 hours. Plan copy.", "placeholders": {"count": {"type": "int"}}},
  "dating_reportDays": "{count, plural, =1{1 day} other{{count} days}}",
  "@dating_reportDays": {"description": "Spec 2 §3.7 {SLA in words}, 48 hours or more. Plan copy.", "placeholders": {"count": {"type": "int"}}},
  "dating_reportScam": "You did the right thing. Scammers are skilled; this isn't on you.",
  "@dating_reportScam": {"description": "Spec 2 §3.7 after romance_scam (09 P7 fix 3)."},
  "dating_endedReportLine": "You can still report a problem for 30 days.",
  "@dating_endedReportLine": {"description": "Spec 2 §3.5 the ended section's line."}
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py $D/arb_fragment_T3.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package > /dev/null 2>&1; echo "gen-l10n exit=$?"
```

Expected: `added 32 keys`; `gen-l10n exit=0`.

- [ ] **Step 3: The data layer and the sheet**

Create `lib/features/dating/report/dating_report.dart` with exactly:

```dart
// Spec 2 W7a (§3.7, §6.2, §6.3): a report's categories and answer, the
// restriction its person sees, and the appeal. Every answer is a fixed
// code the app maps to its own copy; a server's text is never shown.
import 'package:attune/i10n/generated/app_localizations.dart';

/// §3.7's 14 categories, in the sheet's order, with their priority (0 is
/// P0). "Also block" starts on for P0 to P2.
enum DatingReportCategory {
  underageRisk('underage_risk', 0),
  csam('csam', 0),
  childSafety('child_safety', 0),
  threatToLife('threat_to_life', 0),
  sextortion('sextortion', 1),
  romanceScam('romance_scam', 1),
  threats('threats', 1),
  entrapment('entrapment', 1),
  harassment('harassment', 2),
  explicitContent('explicit_content', 2),
  impersonation('impersonation', 2),
  hidingRelationship('hiding_relationship', 2),
  spam('spam', 3),
  other('other', 3);

  const DatingReportCategory(this.wire, this.priority);

  final String wire;
  final int priority;

  bool get blockByDefault => priority <= 2;

  static DatingReportCategory? fromWire(Object? wire) {
    for (final c in values) {
      if (c.wire == wire) return c;
    }
    return null;
  }
}

/// §3.7's label, as the person who reports reads it.
String datingReportLabel(AppLocalizations loc, DatingReportCategory c) =>
    switch (c) {
      DatingReportCategory.underageRisk => loc.dating_reportUnderage,
      DatingReportCategory.csam => loc.dating_reportCsam,
      DatingReportCategory.childSafety => loc.dating_reportChildSafety,
      DatingReportCategory.threatToLife => loc.dating_reportThreatToLife,
      DatingReportCategory.sextortion => loc.dating_reportSextortion,
      DatingReportCategory.romanceScam => loc.dating_reportMoney,
      DatingReportCategory.threats => loc.dating_reportThreats,
      DatingReportCategory.entrapment => loc.dating_reportEntrapment,
      DatingReportCategory.harassment => loc.dating_reportHarassment,
      DatingReportCategory.explicitContent => loc.dating_reportExplicit,
      DatingReportCategory.impersonation => loc.dating_reportImpersonation,
      DatingReportCategory.hidingRelationship => loc.dating_reportMarried,
      DatingReportCategory.spam => loc.dating_reportSpam,
      DatingReportCategory.other => loc.dating_reportOther,
    };

/// The codes a report or an appeal answers; anything else is `failed`.
const datingReportReasons = {
  'invalid',
  'report_unavailable',
  'rate_limited',
  'appeal_unavailable',
  'already_appealed',
  'busy',
  'failed',
};

String _fixed(Object? reason) =>
    reason is String && datingReportReasons.contains(reason)
        ? reason
        : 'failed';

DateTime? _time(Object? raw) =>
    raw is String ? DateTime.tryParse(raw)?.toUtc() : null;

/// What a sent report (or an appeal) answers. [testing]: no named
/// moderator reads it yet (§3.7: "In testing, reports go to the test
/// review queue."); [slaHours]: within how many hours at most.
class DatingReportAnswer {
  const DatingReportAnswer({
    required this.ok,
    this.reason,
    this.testing = true,
    this.slaHours,
  });

  static const busy = DatingReportAnswer(ok: false, reason: 'busy');
  static const failed = DatingReportAnswer(ok: false, reason: 'failed');

  final bool ok;
  final String? reason;
  final bool testing;
  final int? slaHours;

  factory DatingReportAnswer.fromJson(Object? raw) {
    if (raw is! Map) return failed;
    if (raw['ok'] != true) {
      return DatingReportAnswer(ok: false, reason: _fixed(raw['reason']));
    }
    final hours = raw['sla_hours'];
    return DatingReportAnswer(
      ok: true,
      testing: raw['review'] != 'staffed',
      slaHours: hours is int && hours > 0 ? hours : null,
    );
  }
}

enum DatingRestrictionType { hold, ageReview, suspended }

enum DatingAppealState { open, accepted, rejected }

class DatingAppeal {
  const DatingAppeal({required this.state, this.decidedAt});

  final DatingAppealState state;
  final DateTime? decidedAt;

  static DatingAppeal? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final state = switch (raw['state']) {
      'open' => DatingAppealState.open,
      'accepted' => DatingAppealState.accepted,
      'rejected' => DatingAppealState.rejected,
      _ => null,
    };
    if (state == null) return null;
    return DatingAppeal(state: state, decidedAt: _time(raw['decided_at']));
  }
}

/// §3.7 the restriction shown: never who reported, what they wrote or the
/// evidence (the server sends none of it).
class DatingRestriction {
  const DatingRestriction({
    required this.id,
    required this.type,
    this.endsAt,
    this.category,
    this.canAppeal = false,
    this.appeal,
  });

  final String id;
  final DatingRestrictionType type;

  /// Suspended only: null is closed for good.
  final DateTime? endsAt;
  final DatingReportCategory? category;
  final bool canAppeal;
  final DatingAppeal? appeal;

  static DatingRestriction? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String) return null;
    final type = switch (raw['type']) {
      'hold' => DatingRestrictionType.hold,
      'age_review' => DatingRestrictionType.ageReview,
      'suspended' => DatingRestrictionType.suspended,
      _ => null,
    };
    if (type == null) return null;
    return DatingRestriction(
      id: raw['id'] as String,
      type: type,
      endsAt: _time(raw['ends_at']),
      category: DatingReportCategory.fromWire(raw['category']),
      canAppeal: raw['can_appeal'] == true,
      appeal: DatingAppeal.fromJson(raw['appeal']),
    );
  }
}

/// get_my_dating_restriction's answer.
class DatingRestrictionRead {
  const DatingRestrictionRead({
    required this.ok,
    this.reason,
    this.restriction,
    this.appealAccepted = false,
  });

  static const none = DatingRestrictionRead(ok: true);
  static const busy = DatingRestrictionRead(ok: false, reason: 'busy');
  static const failed = DatingRestrictionRead(ok: false, reason: 'failed');

  final bool ok;
  final String? reason;
  final DatingRestriction? restriction;
  final bool appealAccepted;

  factory DatingRestrictionRead.fromJson(Object? raw) {
    if (raw is! Map || raw['ok'] != true) return failed;
    return DatingRestrictionRead(
      ok: true,
      restriction: DatingRestriction.fromJson(raw['restriction']),
      appealAccepted: raw['appeal_accepted'] == true,
    );
  }
}

/// Where a report is about: a conversation, or a card on Today.
sealed class DatingReportTarget {
  const DatingReportTarget(this.id);

  final String id;
}

class DatingReportMatch extends DatingReportTarget {
  const DatingReportMatch(super.id);
}

class DatingReportCard extends DatingReportTarget {
  const DatingReportCard(super.id);
}

/// What the report sheet did, for the screen that opened it.
class DatingReportOutcome {
  const DatingReportOutcome({required this.blocked, this.paused = false});

  /// The person asked to block too (the report's answer was ok).
  final bool blocked;

  /// After a money report the person paused Dating from the sheet.
  final bool paused;
}
```

Create `lib/features/dating/report/dating_report_repository.dart` with exactly:

```dart
// Spec 2 W7a (§3.7, §4.4 Reports, appeals): the report, the restricted
// person's read and the appeal, all through the Dating RPC client. Every
// call is bounded (DatingRpc); a failure answers failed or busy, never the
// error's text.
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/report/dating_report.dart';

abstract class DatingReportGateway {
  /// §3.7 a report of [category] about the other person of [target].
  Future<DatingReportAnswer> report(
    String key,
    DatingReportTarget target,
    DatingReportCategory category,
    String? details, {
    required bool alsoBlock,
  });

  /// The restriction this person sees, if any.
  Future<DatingRestrictionRead> restriction();

  /// One appeal of [restrictionId], with an optional [text].
  Future<DatingReportAnswer> appeal(
    String key,
    String restrictionId,
    String? text,
  );
}

class DatingReportRepository implements DatingReportGateway {
  DatingReportRepository(this._rpc);

  final DatingRpc _rpc;

  Future<T> _guard<T>(
    Future<dynamic> Function() call,
    T Function(Object? raw) parse,
    T busy,
    T failed,
  ) async {
    try {
      return parse(await call());
    } on DatingBusy {
      return busy;
    } catch (_) {
      return failed;
    }
  }

  @override
  Future<DatingReportAnswer> report(
    String key,
    DatingReportTarget target,
    DatingReportCategory category,
    String? details, {
    required bool alsoBlock,
  }) => _guard(
    () => _rpc(
      switch (target) {
        DatingReportMatch() => 'report_dating_match',
        DatingReportCard() => 'report_dating_introduction',
      },
      {
        'p_idempotency_key': key,
        switch (target) {
          DatingReportMatch() => 'p_match_id',
          DatingReportCard() => 'p_introduction_id',
        }: target.id,
        'p_category': category.wire,
        'p_details': details,
        'p_also_block': alsoBlock,
      },
    ),
    DatingReportAnswer.fromJson,
    DatingReportAnswer.busy,
    DatingReportAnswer.failed,
  );

  @override
  Future<DatingRestrictionRead> restriction() => _guard(
    () => _rpc('get_my_dating_restriction'),
    DatingRestrictionRead.fromJson,
    DatingRestrictionRead.busy,
    DatingRestrictionRead.failed,
  );

  @override
  Future<DatingReportAnswer> appeal(
    String key,
    String restrictionId,
    String? text,
  ) => _guard(
    () => _rpc('submit_dating_appeal', {
      'p_idempotency_key': key,
      'p_restriction_id': restrictionId,
      'p_text': text,
    }),
    DatingReportAnswer.fromJson,
    DatingReportAnswer.busy,
    DatingReportAnswer.failed,
  );
}
```

Create `lib/features/dating/report/dating_report_providers.dart` with exactly:

```dart
// Spec 2 W7a (§3.7; D8 shared phones): the report gateway, and the
// restricted person's read, one entry per account, in memory only.
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/report/dating_report_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final datingReportGatewayProvider = Provider<DatingReportGateway>(
  (ref) => DatingReportRepository(ref.watch(datingRpcProvider)),
);

/// The restriction [account] sees: the next account's entry starts
/// loading, never holding the last one's.
final datingRestrictionProvider = FutureProvider.autoDispose
    .family<DatingRestrictionRead, String?>((ref, account) async {
      if (account == null) return DatingRestrictionRead.none;
      return ref.read(datingReportGatewayProvider).restriction();
    });
```

Create `lib/features/dating/report/report_sheet.dart` with exactly:

```dart
// Spec 2 W7a (§3.7, §3.15 Report sheet; §6.2; D8): the report sheet, from
// a conversation's Safety sheet, a safety card, the ended list or a card
// on Today. The 14 categories as one radio group with their full labels,
// "Tell us more (optional)" (500 characters, the keyboard never learns),
// "Also block {Name}" (on for P0 to P2 until the person touches it), Send
// report. Offline nothing is sent. Sent: the thanks with the review time
// (or, while no named moderator reads reports, the testing line) and the
// emergency number; after a money report, "You did the right thing." with
// Pause Dating. Never animated beyond the sheet itself; one key per sheet,
// so a retry after busy is the same report; another account on the phone
// sees nothing of it and the sheet closes.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/lock/dating_sheets.dart';
import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/report/dating_report_providers.dart';
import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/features/safety/data/support_resources_repository.dart';
import 'package:attune/features/safety/presentation/providers/support_resources_providers.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The report sheet about [name] (empty: no name), opened as [account];
/// null when nothing was sent.
Future<DatingReportOutcome?> showDatingReportSheet(
  BuildContext context, {
  required String? account,
  required String name,
  required DatingReportTarget target,
}) => showModalBottomSheet<DatingReportOutcome>(
  context: context,
  routeSettings: datingSheetSettings('report'),
  isScrollControlled: true,
  builder:
      (sheet) => DatingSheetTracker(
        child: AllowLargeText(
          child: DatingReportSheet(
            account: account,
            name: name,
            target: target,
          ),
        ),
      ),
);

class DatingReportSheet extends ConsumerStatefulWidget {
  const DatingReportSheet({
    super.key,
    required this.account,
    required this.name,
    required this.target,
  });

  final String? account;
  final String name;
  final DatingReportTarget target;

  @override
  ConsumerState<DatingReportSheet> createState() => _DatingReportSheetState();
}

class _DatingReportSheetState extends ConsumerState<DatingReportSheet> {
  final _keys = DatingActionKeys();
  final _details = TextEditingController();
  DatingReportCategory? _category;
  bool _block = true;
  bool _blockTouched = false;
  bool _busy = false;
  String? _reason;
  DatingReportAnswer? _sent;
  bool _pausing = false;
  bool _paused = false;
  bool _pauseFailed = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (next == widget.account) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
    });
  }

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  DatingReportOutcome? get _outcome =>
      _sent == null
          ? null
          : DatingReportOutcome(blocked: _block, paused: _paused);

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      Navigator.of(context).pop(_outcome);
    } else {
      route.navigator?.removeRoute(route);
    }
  }

  void _choose(DatingReportCategory? c) {
    if (c == null || _busy) return;
    setState(() {
      _category = c;
      if (!_blockTouched) _block = c.blockByDefault;
    });
  }

  Future<void> _send() async {
    final c = _category;
    if (c == null || _busy) return;
    final account = widget.account;
    final details = _details.text.trim();
    setState(() {
      _busy = true;
      _reason = null;
    });
    final key = _keys.keyFor('report', [
      c.wire,
      details,
      _block,
      widget.target.id,
    ]);
    final r = await ref
        .read(datingReportGatewayProvider)
        .report(
          key,
          widget.target,
          c,
          details.isEmpty ? null : details,
          alsoBlock: _block,
        );
    _keys.settle('report', reason: r.reason);
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _sent = r;
      } else {
        _reason = r.reason;
      }
    });
  }

  Future<void> _pause() async {
    if (_pausing || _paused) return;
    final account = widget.account;
    setState(() {
      _pausing = true;
      _pauseFailed = false;
    });
    final r = await ref
        .read(datingLifecycleGatewayProvider)
        .pause(_keys.keyFor('pause', account));
    _keys.settle('pause', error: r.error);
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    setState(() {
      _pausing = false;
      _paused = r.ok;
      _pauseFailed = !r.ok;
    });
  }

  String _error(AppLocalizations loc, String reason) => switch (reason) {
    'rate_limited' => loc.dating_errorRateLimited,
    'report_unavailable' => loc.dating_cardGone,
    'busy' => loc.dating_busy,
    _ => loc.dating_errorGeneric,
  };

  @override
  Widget build(BuildContext context) {
    if (ref.watch(datingAccountProvider) != widget.account) {
      return const SizedBox.shrink();
    }
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final sent = _sent;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.md,
            Spacing.md,
            Spacing.md + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children:
                sent == null
                    ? _choosing(context, loc, theme)
                    : _thanks(context, loc, theme, sent),
          ),
        ),
      ),
    );
  }

  List<Widget> _choosing(
    BuildContext context,
    AppLocalizations loc,
    ThemeData theme,
  ) {
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final name = widget.name;
    return [
      Semantics(
        header: true,
        child: Text(
          name.isEmpty
              ? loc.dating_reportTitleNoName
              : loc.dating_reportTitle(name),
          style: theme.textTheme.titleLarge,
        ),
      ),
      const SizedBox(height: Spacing.sm),
      Text(loc.dating_reportWhat, style: theme.textTheme.bodyLarge),
      const SizedBox(height: Spacing.xs),
      Semantics(
        container: true,
        label: loc.dating_reportWhat,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in DatingReportCategory.values)
              RadioListTile<DatingReportCategory>(
                key: ValueKey('dating_report_${c.wire}'),
                value: c,
                groupValue: _category,
                onChanged: _busy ? null : _choose,
                contentPadding: EdgeInsets.zero,
                title: Text(datingReportLabel(loc, c)),
              ),
          ],
        ),
      ),
      const SizedBox(height: Spacing.sm),
      TextField(
        key: const ValueKey('dating_report_details'),
        controller: _details,
        enabled: !_busy,
        maxLength: 500,
        maxLines: 4,
        minLines: 2,
        enableSuggestions: false,
        autocorrect: false,
        enableIMEPersonalizedLearning: false,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: loc.dating_reportMore,
          border: const OutlineInputBorder(),
        ),
      ),
      SwitchListTile(
        key: const ValueKey('dating_report_block'),
        value: _block,
        contentPadding: EdgeInsets.zero,
        onChanged:
            _busy
                ? null
                : (v) => setState(() {
                  _block = v;
                  _blockTouched = true;
                }),
        title: Text(
          name.isEmpty
              ? loc.dating_reportBlockNoName
              : loc.dating_reportBlock(name),
        ),
      ),
      if (!online) DatingCalmLine(loc.dating_reportOffline),
      if (_reason case final reason?)
        FlowErrorLine(text: _error(loc, reason), liveRegion: true),
      const SizedBox(height: Spacing.sm),
      FlowPrimaryButton(
        key: const ValueKey('dating_report_send'),
        label: loc.dating_reportSend,
        busy: _busy,
        onPressed: _category != null && online && !_busy ? _send : null,
      ),
    ];
  }

  List<Widget> _thanks(
    BuildContext context,
    AppLocalizations loc,
    ThemeData theme,
    DatingReportAnswer sent,
  ) {
    final number = _emergencyNumber();
    final hours = sent.slaHours;
    final within =
        hours == null
            ? null
            : hours < 48
            ? loc.dating_reportHours(hours)
            : loc.dating_reportDays((hours / 24).ceil());
    final line =
        sent.testing || within == null
            ? (number == null
                ? loc.dating_reportSentTestingNoNumber
                : loc.dating_reportSentTesting(number))
            : (number == null
                ? loc.dating_reportSentNoNumber(within)
                : loc.dating_reportSent(within, number));
    final scam = _category == DatingReportCategory.romanceScam;
    return [
      Semantics(
        header: true,
        child: Text(
          loc.dating_reportSentTitle,
          style: theme.textTheme.titleLarge,
        ),
      ),
      const SizedBox(height: Spacing.sm),
      Semantics(
        liveRegion: true,
        child: Text(line, style: theme.textTheme.bodyLarge),
      ),
      if (scam) ...[
        const SizedBox(height: Spacing.md),
        Text(loc.dating_reportScam, style: theme.textTheme.bodyLarge),
        const SizedBox(height: Spacing.sm),
        if (_paused)
          DatingCalmLine(loc.dating_pausedLine)
        else
          FlowPrimaryButton(
            key: const ValueKey('dating_report_pause'),
            label: loc.dating_settingsPause,
            busy: _pausing,
            onPressed: _pausing ? null : _pause,
          ),
        if (_pauseFailed)
          FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
      ],
      const SizedBox(height: Spacing.sm),
      FlowSecondaryButton(
        key: const ValueKey('dating_report_close'),
        label: loc.dating_close,
        onPressed: _close,
      ),
    ];
  }

  /// The country's emergency number (S1 W7a), or null for the "your
  /// local emergency number" line (still loading, none, or a failure).
  String? _emergencyNumber() {
    final country = ref.watch(supportCountryProvider).valueOrNull;
    final read = ref.watch(supportResourcesProvider(country));
    if (read.hasError) return null;
    final list = read.valueOrNull?.emergency ?? const <SupportResource>[];
    for (final r in list) {
      if (r.phone case final phone? when phone.trim().isNotEmpty) return phone;
    }
    return null;
  }
}
```

- [ ] **Step 4: Report on the Safety sheet, each card, the ended list and Today's card**

Create `$D/edit_app_T3.py` with exactly (formatter-style edits; the files are W5's and W6's, never formatted):

```python
#!/usr/bin/env python3
# Spec 2 W7a Task 3 (§3.5, §3.6, §3.7; R-43; W6 carry T4): Report reaches
# every place the spec names. The Safety sheet's first row; each safety
# card's Report (a card reported is taken off this chat at once, by id:
# the held map never shrinks on a re-read); each row of the ended list
# (30 days, with its line); the card's More on Today. Formatter-style edits
# (the files are W5's and W6's, never formatted). The chat files are also
# being edited by the owner-approved fallback-poll fix: every anchor here
# sits outside its hunks.
import importlib.util

spec = importlib.util.spec_from_file_location('anchor', '.superpowers/sdd/2026-11-21-spec2-w7/anchor.py')
anchor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(anchor)

CHAT = 'lib/features/dating/chat/'

anchor.edit(CHAT + 'chat_sheets.dart', [
    ("""/// What the Safety sheet's person chose.
enum DatingSafetyChoice {
  block,""", """/// What the Safety sheet's person chose.
enum DatingSafetyChoice {
  // Spec 2 W7a (§3.6, R-43): Report, first; open for 30 days after the end.
  report,
  block,"""),
    ("""  return _frame(context, loc.dating_chatSafety, [
    if (!blocked)""", """  return _frame(context, loc.dating_chatSafety, [
    row(
      name.isEmpty
          ? loc.dating_reportTitleNoName
          : loc.dating_reportTitle(name),
      Icons.flag_outlined,
      DatingSafetyChoice.report,
    ),
    if (!blocked)"""),
], 'W7a Task 3')

anchor.edit(CHAT + 'safety_card.dart', [
    ("""    required this.onDismiss,
    this.ended = false,""", """    required this.onDismiss,
    this.onReport,
    this.ended = false,"""),
    ("""  final VoidCallback onDismiss;

  /// The conversation has ended""", """  final VoidCallback onDismiss;

  /// Spec 2 W7a (§3.6, R-43): the card's Report (null: none offered).
  final VoidCallback? onReport;

  /// The conversation has ended"""),
    ("""                  if (!widget.ended)
                    TextButton(
                      key: const ValueKey('dating_card_block'),""", """                  if (widget.onReport case final onReport?)
                    TextButton(
                      key: const ValueKey('dating_card_report'),
                      style: plain,
                      onPressed: onReport,
                      child: Text(loc.dating_report),
                    ),
                  if (!widget.ended)
                    TextButton(
                      key: const ValueKey('dating_card_block'),"""),
], 'W7a Task 3')

anchor.edit(CHAT + 'dating_chat_screen.dart', [
    ("""import 'package:attune/features/dating/chat/safety_card.dart';
""", """import 'package:attune/features/dating/chat/safety_card.dart';
import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/report/report_sheet.dart';
"""),
    ("""    if (!mounted || _account != account || choice == null) return;
    switch (choice) {
      case DatingSafetyChoice.block:
        await _block(name);""", """    if (!mounted || _account != account || choice == null) return;
    switch (choice) {
      case DatingSafetyChoice.report:
        await _report(name);
      case DatingSafetyChoice.block:
        await _block(name);"""),
    ("""  /// §3.6 Block: confirmed, then sent once (from the Safety sheet or a
  /// card).""", """  /// Spec 2 W7a (§3.7): the report sheet sends it. Reported from a [card],
  /// the card goes from this chat at once, by id (W6 carry T4: a re-read
  /// only adds cards, so a reported one is removed here). With "Also
  /// block", this side has blocked: as Block.
  Future<void> _report(String name, {DatingSafetyCard? card}) async {
    final account = _account;
    final outcome = await showDatingReportSheet(
      context,
      account: account,
      name: name,
      target: DatingReportMatch(widget.matchId),
    );
    if (outcome == null || !mounted || _account != account) return;
    setState(() {
      if (card != null) {
        _dismissedCards.add(card.id);
        _cards.remove(card.id);
      }
      if (outcome.blocked) {
        _blockedName = name;
        _composer.clear();
        _outgoing.clear();
      }
    });
    if (card != null && account != null) {
      _pendingDismissals(account).add(card.id);
      if (_online) unawaited(_sendDismissals(account));
    }
    unawaited(_read());
  }

  /// §3.6 Block: confirmed, then sent once (from the Safety sheet or a
  /// card)."""),
    ("""                              onBlock: () => _block(name),
                              onDismiss: () => _dismiss(c),""", """                              onBlock: () => _block(name),
                              onReport: () => _report(name, card: c),
                              onDismiss: () => _dismiss(c),"""),
], 'W7a Task 3')

anchor.edit(CHAT + 'conversations_screen.dart', [
    ("""import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
""", """import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/report/report_sheet.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
"""),
    ("""            child: Semantics(
              header: true,
              child: Text(
                loc.dating_chatsEnded,
                style: theme.textTheme.titleMedium,
              ),
            ),
          ),
          for (final e in d.ended)
            Semantics(
              container: true,
              child: ListTile(
                key: ValueKey('dating_chats_ended_${e.matchId}'),
                title: Text(
                  e.displayName.isEmpty
                      ? loc.dating_chatTitleNoName
                      : e.displayName,
                ),
                subtitle: Text(loc.dating_chatEnded),
              ),
            ),""", """            child: Semantics(
              header: true,
              child: Text(
                loc.dating_chatsEnded,
                style: theme.textTheme.titleMedium,
              ),
            ),
          ),
          // Spec 2 W7a (§3.5): the ended section's line, and only Report.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            child: Text(
              loc.dating_endedReportLine,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          for (final e in d.ended)
            Semantics(
              container: true,
              child: ListTile(
                key: ValueKey('dating_chats_ended_${e.matchId}'),
                title: Text(
                  e.displayName.isEmpty
                      ? loc.dating_chatTitleNoName
                      : e.displayName,
                ),
                subtitle: Text(loc.dating_chatEnded),
                trailing: TextButton(
                  key: ValueKey('dating_chats_report_${e.matchId}'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () async {
                    final account = ProviderScope.containerOf(
                      context,
                    ).read(datingAccountProvider);
                    final outcome = await showDatingReportSheet(
                      context,
                      account: account,
                      name: e.displayName,
                      target: DatingReportMatch(e.matchId),
                    );
                    if (outcome != null) reread();
                  },
                  child: Text(
                    loc.dating_report,
                    semanticsLabel:
                        e.displayName.isEmpty
                            ? loc.dating_reportTitleNoName
                            : loc.dating_reportTitle(e.displayName),
                  ),
                ),
              ),
            ),"""),
], 'W7a Task 3')

TODAY = 'lib/features/dating/today/'
anchor.edit(TODAY + 'block_sheet.dart', [
    ("""// R-36): the card's overflow and the Block confirm. The overflow offers
// Block (W7a adds Report). The confirm names the person, says the person
// won't be told and won't be introduced again, and answers once: a second
// tap does nothing. Offline, Block waits (nothing is queued). Either sheet
// shows nothing of the last account once the signed-in account changes,
// and closes choosing nothing. Today sends the block.
""", """// R-36): the card's overflow and the Block confirm. The overflow offers
// Report (Spec 2 W7a, §3.7) and Block. The confirm names the person, says
// the person won't be told and won't be introduced again, and answers
// once: a second tap does nothing. Offline, Block waits (nothing is
// queued). Either sheet shows nothing of the last account once the
// signed-in account changes, and closes choosing nothing. Today sends the
// block (and the report sheet sends a report).
"""),
    ("""/// The overflow on [name]'s card, opened as [account]: true when Block was
/// chosen.
Future<bool> showDatingCardMoreSheet(
  BuildContext context, {
  required String? account,
  required String name,
}) => _show(
  context,
  'card-more',
  account,
  (context, close) => _MoreSheet(name: name, close: close),
);""", """/// What the card's overflow chose (Spec 2 W7a).
enum DatingCardMore { report, block }

/// The overflow on [name]'s card, opened as [account]: Report, Block, or
/// null for nothing.
Future<DatingCardMore?> showDatingCardMoreSheet(
  BuildContext context, {
  required String? account,
  required String name,
}) async {
  DatingCardMore? chosen;
  final picked = await _show(
    context,
    'card-more',
    account,
    (context, close) => _MoreSheet(
      name: name,
      close: close,
      choose: (c) => chosen = c,
    ),
  );
  return picked ? chosen : null;
}"""),
    ("""class _MoreSheet extends StatelessWidget {
  const _MoreSheet({required this.name, required this.close});

  final String name;
  final void Function(bool) close;
""", """class _MoreSheet extends StatelessWidget {
  const _MoreSheet({
    required this.name,
    required this.close,
    required this.choose,
  });

  final String name;
  final void Function(bool) close;
  final void Function(DatingCardMore) choose;
"""),
    ("""            const SizedBox(height: Spacing.sm),
            InfoRowWidget(
              title: _row(loc, name),""", """            const SizedBox(height: Spacing.sm),
            InfoRowWidget(
              title:
                  name.isEmpty
                      ? loc.dating_reportTitleNoName
                      : loc.dating_reportTitle(name),
              subtitle: '',
              icon: Icons.flag_outlined,
              showAvatar: false,
              disableTrailing: true,
              padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
              onTap: () {
                choose(DatingCardMore.report);
                close(true);
              },
            ),
            InfoRowWidget(
              title: _row(loc, name),"""),
    ("""              padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
              onTap: () => close(true),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockSheet""", """              padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
              onTap: () {
                choose(DatingCardMore.block);
                close(true);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockSheet"""),
], 'W7a Task 3')

anchor.edit(TODAY + 'today_screen.dart', [
    ("""import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
""", """import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/report/report_sheet.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
"""),
    ("""    final more = await showDatingCardMoreSheet(
      context,
      account: account,
      name: name,
    );
    if (!more || !mounted || _account != account) return;""", """    final more = await showDatingCardMoreSheet(
      context,
      account: account,
      name: name,
    );
    if (more == null || !mounted || _account != account) return;
    // Spec 2 W7a (§3.7): Report from the card; with "Also block" the card
    // is blocked by the report itself, so it collapses as a block does.
    if (more == DatingCardMore.report) {
      final outcome = await showDatingReportSheet(
        context,
        account: account,
        name: name,
        target: DatingReportCard(c.id),
      );
      if (outcome == null || !mounted || _account != account) return;
      setState(() {
        if (outcome.blocked) {
          _blocked[c.id] = name;
          _photos.remove(c.id);
          DatingPhotoMemory.forget('introduction', c.id);
        }
      });
      return;
    }"""),
], 'W7a Task 3')
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
python3 -I $D/edit_app_T3.py
dart format lib/features/dating/report test/features/dating/report test/features/dating/support/dating_report_fakes.dart 2>&1 | tail -1
flutter analyze --no-pub lib/features/dating test/features/dating 2>&1 | tail -1
flutter test --no-pub --update-goldens test/features/dating/report/report_sheet_test.dart test/features/dating/chat/safety_cards_test.dart test/features/dating/chat/safety_cards_fix1_test.dart test/features/dating/today/block_fix1_test.dart 2>&1 | tr '\r' '\n' | tail -1 | grep -oE 'All tests passed!|Some tests failed\.'
flutter test --no-pub test/features/dating 2>&1 | tr '\r' '\n' | grep -E '^[0-9:]+ \+[0-9]+' | tail -1 | grep -oE '\+[0-9]+( ~[0-9]+)?( -[0-9]+)?: (All tests passed!|Some tests failed\.)'
git status --short test | grep -c 'goldens/.*\.png'
```

Expected: the six edit lines (`chat_sheets.dart: 2 edit(s) (W7a Task 3)`, `safety_card.dart: 3 edit(s)`, `dating_chat_screen.dart: 4 edit(s)`, `conversations_screen.dart: 2 edit(s)`, `block_sheet.dart: 5 edit(s)`, `today_screen.dart: 2 edit(s)`); `Formatted 6 files (0 changed) in … seconds.`; `No issues found! (ran in …)`; `All tests passed!` (the report sheet's goldens written, the card's and the More sheet's regenerated); `+1393: All tests passed!` (every Dating test, the report sheet's 10 among them); `9` (five `dating_chat_card.*` with the card's Report, four `today_more_sheet.*` with the More sheet's Report row).

- [ ] **Step 5: The mutants**

Create `$D/mut_T3_dart.py` with exactly:

```python
# Spec 2 W7a Task 3: Dart mutants (dmut.py). Each must turn a named test red;
# a COMPILE is a broken mutant, never a kill.
R = 'lib/features/dating/report/report_sheet.dart'
T = ['test/features/dating/report/report_sheet_test.dart']
MUTS = {
    'safety_row_missing': ('lib/features/dating/chat/chat_sheets.dart',
                           '      DatingSafetyChoice.report,\n    ),', '      DatingSafetyChoice.block,\n    ),', T),
    'card_kept_after_report': ('lib/features/dating/chat/dating_chat_screen.dart',
                               '        _dismissedCards.add(card.id);\n        _cards.remove(card.id);\n      }\n      if (outcome.blocked) {',
                               '        _dismissedCards.add(card.id);\n      }\n      if (outcome.blocked) {', T),
    'card_dismissal_unsent': ('lib/features/dating/chat/dating_chat_screen.dart',
                              '      _pendingDismissals(account).add(card.id);\n      if (_online) unawaited(_sendDismissals(account));',
                              '      if (_online) unawaited(_sendDismissals(account));', T),
    'block_default_fixed': (R, '      if (!_blockTouched) _block = c.blockByDefault;', '      if (!_blockTouched) _block = true;', T),
    'touched_toggle_reset': (R, '      if (!_blockTouched) _block = c.blockByDefault;', '      _block = c.blockByDefault;', T),
    'offline_sends': (R, 'onPressed: _category != null && online && !_busy ? _send : null,',
                      'onPressed: _category != null && !_busy ? _send : null,', T),
    'busy_new_key': (R, "    _keys.settle('report', reason: r.reason);", "    _keys.settle('report');", T),
    'details_untrimmed': (R, '    final details = _details.text.trim();', '    final details = _details.text;', T),
    'testing_line_ignored': (R, '        sent.testing || within == null', '        within == null', T),
    'scam_line_missing': (R, '    final scam = _category == DatingReportCategory.romanceScam;', '    final scam = false;', T),
    'sheet_shows_next_account': (R, '    if (ref.watch(datingAccountProvider) != widget.account) {\n      return const SizedBox.shrink();\n    }\n    final loc = AppLocalizations.of(context)!;\n    final theme = Theme.of(context);\n    final sent = _sent;',
                                 '    final loc = AppLocalizations.of(context)!;\n    final theme = Theme.of(context);\n    final sent = _sent;', T),
    'ended_reports_wrong_chat': ('lib/features/dating/chat/conversations_screen.dart',
                                 '                      target: DatingReportMatch(e.matchId),', "                      target: const DatingReportMatch('m1'),", T),
    'today_report_is_block': ('lib/features/dating/today/today_screen.dart',
                              '    if (more == DatingCardMore.report) {', '    if (more == null) {', T),
}
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7; python3 -I $D/dmut.py $D/mut_T3_dart.py > $D/mut_T3_dart.txt 2>&1; tail -1 $D/mut_T3_dart.txt
```

Expected: `13/13 killed`.

- [ ] **Step 6: Record the tree**

Do not commit; record the tree in the report.

### Task 4: The restricted screen, the appeal, the section's restricted card, the manual, and the W7a gate (§3.7 restricted, §3.15, §6.3; D8; carry 11; R-54, R-56, R-64)

**Files:**
- Create: `lib/features/dating/report/restricted_screen.dart`, `test/features/dating/report/restricted_screen_test.dart` and its goldens (`dating_restricted.*`), `$D/{arb_fragment_T4.txt, edit_app_T4.py, mut_T4_dart.py}`
- Modify: `lib/features/dating/routes/dating_routes.dart`, `lib/features/dating/data/dating_home.dart`, `lib/features/dating/section/dating_section.dart`, `test/architecture/text_scale_routes_test.dart`, `lib/app/documentations/user_manual/data/dating_mode_docs.dart`, `lib/i10n/app_en.arb` + generated

**Interfaces:**
- Consumes: Task 3's gateway, models, providers and fakes; Spec 1's `UrlLauncherUtils.launchEmail`, `AppConstants.supportEmail`, `MyDateFormat`; W3's `datingRoute()`, `datingMeLocation`.
- Produces: `DatingRestrictedScreen`, `datingRestrictionLabel`, `showDatingAppealSheet`, `datingSupportContactProvider`; `DatingPaths.restricted` (`/dating/restricted`, route `datingRestricted`); `DatingHome.appealAccepted`; the section's restricted card's "See why"; the manual's `dating_report` topic.

- [ ] **Step 1: Write the failing tests**

Create `test/features/dating/report/restricted_screen_test.dart` with exactly:

```dart
// Spec 2 W7a Task 4 (§3.1, §3.7, §3.15 Restricted, hold, appeal; §6.3;
// R-43, R-56; D8): the restricted screen at /dating/restricted: the
// category first in the person's own words, each type's copy, Appeal once
// where allowed (sent once under one key; offline it waits), the appeal's
// state, Contact support, the age check's Verify with ID through support;
// the section's restricted, hold and age-check cards lead there and an
// accepted appeal is said on the section; another account starts from
// nothing; goldens at 1.0, 1.3, 2.0 and RTL; the three guidelines; the
// manual says Report again.
import 'package:attune/app/documentations/user_manual/data/dating_mode_docs.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/report/restricted_screen.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/section/dating_section.dart';
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

final _ends = DateTime.utc(2026, 12, 1, 12);

DatingRestrictionRead _read(
  DatingRestrictionType type, {
  DateTime? ends,
  DatingReportCategory? category = DatingReportCategory.harassment,
  bool canAppeal = false,
  DatingAppeal? appeal,
}) => DatingRestrictionRead(
  ok: true,
  restriction: DatingRestriction(
    id: 'r1',
    type: type,
    endsAt: ends,
    category: category,
    canAppeal: canAppeal,
    appeal: appeal,
  ),
);

void main() {
  final loc = AppLocalizationsEn();

  test('the restriction read fails closed and names no one', () {
    final r = DatingRestrictionRead.fromJson({
      'ok': true,
      'appeal_accepted': false,
      'restriction': {
        'id': 'r1',
        'type': 'hold',
        'ends_at': null,
        'category': 'threat_to_life',
        'can_appeal': false,
        'appeal': null,
      },
    });
    expect(r.restriction!.type, DatingRestrictionType.hold);
    expect(r.restriction!.category, DatingReportCategory.threatToLife);
    expect(DatingRestrictionRead.fromJson({'ok': false}).ok, isFalse);
    expect(
      DatingRestriction.fromJson({'id': 'x', 'type': 'under_review'}),
      isNull,
    );
    expect(
      DatingAppeal.fromJson({'state': 'rejected'})!.state,
      DatingAppealState.rejected,
    );
    for (final c in DatingReportCategory.values) {
      expect(datingRestrictionLabel(loc, c), isNotEmpty);
      // The person's own plain words, never the reporter's voice.
      expect(datingRestrictionLabel(loc, c), isNot(matches(RegExp(r'\bme\b'))));
      expect(datingRestrictionLabel(loc, c), isNot(startsWith('They')));
    }
    expect(datingRestrictionLabel(loc, null), loc.dating_reasonOther);
  });

  Future<(DatingShell, FakeDatingReport, List<String>)> open(
    WidgetTester t,
    DatingRestrictionRead read, {
    bool online = true,
  }) async {
    final fake = FakeDatingReport()..read = read;
    final contacted = <String>[];
    final shell = await pumpDatingShell(
      t,
      initial: DatingPaths.restricted,
      online: online,
      overrides: [
        ...datingReportOverrides(fake),
        datingSupportContactProvider.overrideWithValue(
          (context) async => contacted.add('support'),
        ),
      ],
    );
    return (shell, fake, contacted);
  }

  testWidgets('a hold: the category first, the hold\'s words, no Appeal', (
    t,
  ) async {
    await open(
      t,
      _read(
        DatingRestrictionType.hold,
        category: DatingReportCategory.threatToLife,
      ),
    );
    final about = loc.dating_restrictedAbout(loc.dating_reasonThreatToLife);
    expect(find.text(about), findsOneWidget);
    expect(find.text(loc.dating_restrictedHold), findsOneWidget);
    expect(
      t.getTopLeft(find.text(about)).dy,
      lessThan(t.getTopLeft(find.text(loc.dating_restrictedHold)).dy),
    );
    expect(find.text(loc.dating_appeal), findsNothing);
    expect(find.text(loc.flow_holdContact), findsOneWidget);
  });

  testWidgets('until a date: the reason, the date, what it means, Appeal '
      'once; sent, the screen reads again and says so', (t) async {
    final (shell, fake, _) = await open(
      t,
      _read(DatingRestrictionType.suspended, ends: _ends, canAppeal: true),
    );
    expect(
      find.text(loc.dating_restrictedReason(loc.dating_reasonHarassment)),
      findsOneWidget,
    );
    expect(
      find.text(
        loc.dating_restrictedUntil(MyDateFormat.toDate(_ends.toLocal())),
      ),
      findsOneWidget,
    );
    expect(find.text(loc.dating_restrictedMeans), findsOneWidget);
    await tapInReach(t, find.byKey(const ValueKey('dating_restricted_appeal')));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('dating_appeal_text')),
      '  I didn\'t do this.  ',
    );
    fake.read = _read(
      DatingRestrictionType.suspended,
      ends: _ends,
      appeal: const DatingAppeal(state: DatingAppealState.open),
    );
    await tapInReach(t, find.byKey(const ValueKey('dating_appeal_send')));
    await t.pumpAndSettle();
    expect(fake.appeals.single.$2, 'r1');
    expect(fake.appeals.single.$3, 'I didn\'t do this.');
    expect(fake.reads, 2);
    expect(find.text(loc.dating_appealSent), findsOneWidget);
    expect(find.text(loc.dating_appeal), findsNothing);
    expect(shell.location, DatingPaths.restricted);
  });

  testWidgets('the appeal waits offline; busy keeps its key', (t) async {
    final (_, fake, _) = await open(
      t,
      _read(DatingRestrictionType.suspended, canAppeal: true),
      online: false,
    );
    expect(find.text(loc.dating_restrictedClosed), findsOneWidget);
    await tapInReach(t, find.byKey(const ValueKey('dating_restricted_appeal')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_offline), findsOneWidget);
    await tapInReach(t, find.byKey(const ValueKey('dating_appeal_send')));
    await t.pump();
    expect(fake.appeals, isEmpty);

    final (_, busy, _) = await open(
      t,
      _read(DatingRestrictionType.suspended, canAppeal: true),
    );
    busy.appealAnswer = DatingReportAnswer.busy;
    await tapInReach(t, find.byKey(const ValueKey('dating_restricted_appeal')));
    await t.pumpAndSettle();
    await tapInReach(t, find.byKey(const ValueKey('dating_appeal_send')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_busy), findsOneWidget);
    busy.appealAnswer = const DatingReportAnswer(ok: true);
    await tapInReach(t, find.byKey(const ValueKey('dating_appeal_send')));
    await t.pumpAndSettle();
    expect(busy.appeals, hasLength(2));
    expect(busy.appeals[1].$1, busy.appeals[0].$1);
  });

  testWidgets('the age check: its words, Verify with ID through support; '
      'a rejected appeal; nothing left; an accepted appeal', (t) async {
    final (_, _, contacted) = await open(
      t,
      _read(DatingRestrictionType.ageReview, category: null),
    );
    expect(find.text(loc.dating_sectionAgeReview), findsOneWidget);
    await tapInReach(t, find.byKey(const ValueKey('dating_restricted_verify')));
    await t.pump();
    expect(contacted, ['support']);
    await open(
      t,
      _read(
        DatingRestrictionType.suspended,
        appeal: const DatingAppeal(state: DatingAppealState.rejected),
      ),
    );
    expect(find.text(loc.dating_appealRejected), findsOneWidget);
    await open(t, DatingRestrictionRead.none);
    expect(find.text(loc.dating_restrictedNone), findsOneWidget);
    await open(t, const DatingRestrictionRead(ok: true, appealAccepted: true));
    expect(find.text(loc.dating_appealAccepted), findsOneWidget);
  });

  testWidgets('D8: another account sees nothing of the last one\'s '
      'restriction', (t) async {
    final (shell, fake, _) = await open(
      t,
      _read(DatingRestrictionType.hold, category: DatingReportCategory.csam),
    );
    final about = loc.dating_restrictedAbout(loc.dating_reasonCsam);
    expect(find.text(about), findsOneWidget);
    fake.read = DatingRestrictionRead.none;
    shell.container.read(datingTestAccount.notifier).state = 'kwame';
    await t.pump();
    expect(find.text(about), findsNothing);
    await t.pumpAndSettle();
    expect(find.text(about), findsNothing);
  });

  Future<FlowHarness> section(WidgetTester t, DatingHome state) async {
    await t.pumpWidget(const SizedBox());
    return pumpFlowScreen(
      t,
      () => const Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: DatingSection(),
        ),
      ),
      overrides: [
        ...datingShellOverrides(home: FakeDatingHomeGateway(home: state)),
        homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
        homeStateServiceProvider.overrideWithValue(
          HomeStateService(
            FakeHomeStateGateway(state: homeJson(path: 'dating')),
          ),
        ),
      ],
    );
  }

  testWidgets('the section: restricted, hold and the age check lead to the '
      'screen; an accepted appeal is said on the active and paused cards', (
    t,
  ) async {
    for (final s in [
      DatingHomeState.restricted,
      DatingHomeState.hold,
      DatingHomeState.ageReview,
    ]) {
      await section(t, DatingHome(state: s));
      await tapInReach(t, find.text(loc.dating_restrictedSeeWhy));
      await t.pumpAndSettle();
      expect(find.text('at ${DatingPaths.restricted}'), findsOneWidget);
    }
    await section(
      t,
      const DatingHome(
        state: DatingHomeState.paused,
        pauseReason: DatingPauseReason.gates,
        appealAccepted: true,
      ),
    );
    expect(find.text(loc.dating_appealAccepted), findsOneWidget);
    expect(find.text(loc.dating_sectionPaused), findsOneWidget);
    await section(t, const DatingHome(state: DatingHomeState.active));
    expect(find.text(loc.dating_appealAccepted), findsNothing);
    expect(
      DatingHome.fromJson({
        'state': 'active',
        'appeal_accepted': true,
      }).appealAccepted,
      isTrue,
    );
  });

  testWidgets('goldens at 1.0, 1.3, 2.0 and RTL; the three guidelines', (
    t,
  ) async {
    final fake =
        FakeDatingReport()
          ..read = _read(
            DatingRestrictionType.suspended,
            ends: _ends,
            canAppeal: true,
          );
    Widget screen() => const DatingRestrictedScreen();
    final overrides = [
      ...datingShellOverrides(),
      ...datingReportOverrides(fake),
    ];
    await expectFlowGoldens(
      t,
      'dating_restricted',
      screen,
      overrides: overrides,
    );
    await pumpFlowScreen(t, screen, overrides: overrides);
    await expectFlowGuidelines(t);
  });

  testWidgets('the manual says Report again (R-43) and explains reporting '
      'and restrictions', (t) async {
    late BuildContext context;
    await t.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    String content(String id) =>
        DatingModeDocs()
            .getSections(context)
            .expand((s) => s.contents)
            .firstWhere((c) => c.id == id)
            .content;
    expect(content('dating_money'), contains('report them'));
    expect(content('dating_chat'), contains('lets you report, block'));
    expect(content('dating_report'), contains('appeal once'));
  });
}
```

```bash
flutter test --no-pub test/features/dating/report/restricted_screen_test.dart 2>&1 | grep -oE "Error: Error when reading '[^']*'" | head -1
```

Expected: `Error: Error when reading 'lib/features/dating/report/restricted_screen.dart'`.

- [ ] **Step 2: The copy**

Create `$D/arb_fragment_T4.txt` with exactly:

```text
  "dating_restrictedSeeWhy": "See why",
  "@dating_restrictedSeeWhy": {"description": "Spec 2 §3.7 the section's restricted, hold and age-check cards open the restricted screen. Plan copy."},
  "dating_restrictedLoading": "Checking your Dating account.",
  "@dating_restrictedLoading": {"description": "Spec 2 §3.7 the restricted screen while it reads (never animated). Plan copy."},
  "dating_restrictedNone": "Nothing is restricting your Dating account.",
  "@dating_restrictedNone": {"description": "Spec 2 §3.7 the restricted screen when nothing is restricted any more. Plan copy."},
  "dating_restrictedAbout": "About: {label}",
  "@dating_restrictedAbout": {"description": "Spec 2 §3.7 the hold's category line (read first).", "placeholders": {"label": {"type": "String"}}},
  "dating_restrictedReason": "Reason: {label}.",
  "@dating_restrictedReason": {"description": "Spec 2 §3.7 a suspension's category line (read first).", "placeholders": {"label": {"type": "String"}}},
  "dating_restrictedHold": "Your Dating profile is paused while we look into a report. This isn't a decision yet. We aim to finish within 24 hours.",
  "@dating_restrictedHold": {"description": "Spec 2 §3.7 interim hold (P0, corroborated)."},
  "dating_restrictedVerifyId": "Verify with ID",
  "@dating_restrictedVerifyId": {"description": "Spec 2 §3.7 the age check's button (Ruling R-56: through support)."},
  "dating_restrictedUntil": "Your Dating account is restricted until {date}.",
  "@dating_restrictedUntil": {"description": "Spec 2 §3.7 suspended (temporary); {date} through MyDateFormat.", "placeholders": {"date": {"type": "String"}}},
  "dating_restrictedMeans": "What this means: you can't be introduced or send Dating messages until then. The rest of Attune works as usual.",
  "@dating_restrictedMeans": {"description": "Spec 2 §3.7 suspended (temporary)."},
  "dating_restrictedClosed": "Your Dating account has been closed.",
  "@dating_restrictedClosed": {"description": "Spec 2 §3.7 suspended (permanent)."},
  "dating_appeal": "Appeal",
  "@dating_appeal": {"description": "Spec 2 §3.7 [Appeal] (once) and the appeal sheet's title."},
  "dating_appealHint": "Tell us what happened (optional, 500 characters)",
  "@dating_appealHint": {"description": "Spec 2 §3.7 the appeal's field."},
  "dating_appealSend": "Send appeal",
  "@dating_appealSend": {"description": "Spec 2 §3.7 the appeal's button."},
  "dating_appealSent": "Appeal sent. A different person from the one who made the first decision will look at it within 7 days.",
  "@dating_appealSent": {"description": "Spec 2 §3.7 after the appeal (shown while it is open)."},
  "dating_appealAccepted": "Your appeal was accepted. Dating is open again.",
  "@dating_appealAccepted": {"description": "Spec 2 §3.7 outcome in-app (the section, 7 days)."},
  "dating_appealRejected": "We looked again and the decision stands.",
  "@dating_appealRejected": {"description": "Spec 2 §3.7 outcome in-app (with the category above it)."},
  "dating_reasonUnderage": "Concerns about age",
  "@dating_reasonUnderage": {"description": "Spec 2 §6.3 underage_risk, as the restricted person reads it. Plan copy for the reviewers."},
  "dating_reasonCsam": "Sexual content involving a child",
  "@dating_reasonCsam": {"description": "Spec 2 §6.3 csam. Plan copy."},
  "dating_reasonChildSafety": "The safety of children",
  "@dating_reasonChildSafety": {"description": "Spec 2 §6.3 child_safety. Plan copy."},
  "dating_reasonThreatToLife": "Threatening to kill or seriously hurt someone",
  "@dating_reasonThreatToLife": {"description": "Spec 2 §6.3 threat_to_life. Plan copy."},
  "dating_reasonSextortion": "Threatening to share someone's images",
  "@dating_reasonSextortion": {"description": "Spec 2 §6.3 sextortion. Plan copy."},
  "dating_reasonMoney": "Asking for money",
  "@dating_reasonMoney": {"description": "Spec 2 §6.3 romance_scam. Plan copy."},
  "dating_reasonThreats": "Threatening someone",
  "@dating_reasonThreats": {"description": "Spec 2 §6.3 threats. Plan copy."},
  "dating_reasonEntrapment": "A profile set up to trap people",
  "@dating_reasonEntrapment": {"description": "Spec 2 §6.3 entrapment. Plan copy."},
  "dating_reasonHarassment": "Harassment",
  "@dating_reasonHarassment": {"description": "Spec 2 §6.3 harassment. Plan copy."},
  "dating_reasonExplicit": "Sexual messages someone didn't want",
  "@dating_reasonExplicit": {"description": "Spec 2 §6.3 explicit_content. Plan copy."},
  "dating_reasonImpersonation": "Using someone else's photos or identity",
  "@dating_reasonImpersonation": {"description": "Spec 2 §6.3 impersonation. Plan copy."},
  "dating_reasonMarried": "Being married or in a relationship",
  "@dating_reasonMarried": {"description": "Spec 2 §6.3 hiding_relationship. Plan copy."},
  "dating_reasonSpam": "Spam or selling",
  "@dating_reasonSpam": {"description": "Spec 2 §6.3 spam. Plan copy."},
  "dating_reasonOther": "Breaking Dating's rules",
  "@dating_reasonOther": {"description": "Spec 2 §6.3 other, or no category. Plan copy."}
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py $D/arb_fragment_T4.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package > /dev/null 2>&1; echo "gen-l10n exit=$?"
```

Expected: `added 30 keys`; `gen-l10n exit=0`.

- [ ] **Step 3: The screen**

Create `lib/features/dating/report/restricted_screen.dart` with exactly:

```dart
// Spec 2 W7a (§3.7 Restricted card and screen, Appeal; §3.15 Restricted,
// hold, appeal; §6.3; D8): what a restricted person reads at
// /dating/restricted. The category first ("About:" for a hold, "Reason:"
// otherwise, in the person's own plain words, never the reporter's), then
// what it means; [Appeal] once, where the restriction allows it, and
// [Contact support]; the age check's [Verify with ID] goes through support
// (Ruling R-56). Never who reported, what they wrote, or the evidence (the
// server sends none of it). Nothing here moves; the appeal waits offline;
// another account on the phone starts from nothing.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/utils/constants.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/utils/url_launcher_utils.dart';
import 'package:attune/core/widgets/app_content_width.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/lock/dating_sheets.dart';
import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/report/dating_report_providers.dart';
import 'package:attune/features/dating/routes/dating_root_back.dart';
import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// §6.3 "Category shown": the plain label the restricted person reads
/// (never the reporter's words; plan copy for the reviewers).
String datingRestrictionLabel(AppLocalizations loc, DatingReportCategory? c) =>
    switch (c) {
      DatingReportCategory.underageRisk => loc.dating_reasonUnderage,
      DatingReportCategory.csam => loc.dating_reasonCsam,
      DatingReportCategory.childSafety => loc.dating_reasonChildSafety,
      DatingReportCategory.threatToLife => loc.dating_reasonThreatToLife,
      DatingReportCategory.sextortion => loc.dating_reasonSextortion,
      DatingReportCategory.romanceScam => loc.dating_reasonMoney,
      DatingReportCategory.threats => loc.dating_reasonThreats,
      DatingReportCategory.entrapment => loc.dating_reasonEntrapment,
      DatingReportCategory.harassment => loc.dating_reasonHarassment,
      DatingReportCategory.explicitContent => loc.dating_reasonExplicit,
      DatingReportCategory.impersonation => loc.dating_reasonImpersonation,
      DatingReportCategory.hidingRelationship => loc.dating_reasonMarried,
      DatingReportCategory.spam => loc.dating_reasonSpam,
      DatingReportCategory.other || null => loc.dating_reasonOther,
    };

/// Opens the support email (the section's own Contact support).
typedef DatingSupportContact = Future<void> Function(BuildContext context);

final datingSupportContactProvider = Provider<DatingSupportContact>(
  (ref) =>
      (context) => UrlLauncherUtils.launchEmail(
        context: context,
        email: AppConstants.supportEmail,
      ),
);

class DatingRestrictedScreen extends ConsumerWidget {
  const DatingRestrictedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final account = ref.watch(datingAccountProvider);
    final read = ref.watch(datingRestrictionProvider(account));
    return AllowLargeText(
      child: Scaffold(
        appBar: AppBar(
          leading: datingRootBackButton(context),
          title: Text(loc.flow_slotDatingTitle),
        ),
        body: SafeArea(
          child: ListView(
            padding: AppContentWidth.padded(
              context,
              const EdgeInsets.all(Spacing.md),
            ),
            children: switch (read) {
              AsyncData(value: final r) when r.ok => _body(
                context,
                ref,
                loc,
                r,
              ),
              AsyncData() || AsyncError() => [
                FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
                const SizedBox(height: Spacing.sm),
                FlowSecondaryButton(
                  label: loc.dating_retry,
                  onPressed:
                      () => ref.invalidate(datingRestrictionProvider(account)),
                ),
              ],
              _ => [DatingCalmLine(loc.dating_restrictedLoading)],
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations loc,
    DatingRestrictionRead read,
  ) {
    final theme = Theme.of(context);
    final r = read.restriction;
    Widget para(String text, {Key? key}) => Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Text(text, style: theme.textTheme.bodyLarge),
    );
    final support = FlowSecondaryButton(
      key: const ValueKey('dating_restricted_support'),
      label: loc.flow_holdContact,
      onPressed: () => ref.read(datingSupportContactProvider)(context),
    );
    if (r == null) {
      return [
        para(
          read.appealAccepted
              ? loc.dating_appealAccepted
              : loc.dating_restrictedNone,
        ),
      ];
    }
    final label = datingRestrictionLabel(loc, r.category);
    final appeal = r.appeal;
    return [
      if (r.type == DatingRestrictionType.hold)
        para(
          loc.dating_restrictedAbout(label),
          key: const ValueKey('dating_restricted_category'),
        )
      else if (r.type == DatingRestrictionType.suspended)
        para(
          loc.dating_restrictedReason(label),
          key: const ValueKey('dating_restricted_category'),
        ),
      ...switch (r.type) {
        DatingRestrictionType.hold => [para(loc.dating_restrictedHold)],
        DatingRestrictionType.ageReview => [
          para(loc.dating_sectionAgeReview),
          FlowPrimaryButton(
            key: const ValueKey('dating_restricted_verify'),
            label: loc.dating_restrictedVerifyId,
            onPressed: () => ref.read(datingSupportContactProvider)(context),
          ),
          const SizedBox(height: Spacing.sm),
        ],
        DatingRestrictionType.suspended when r.endsAt == null => [
          para(loc.dating_restrictedClosed),
        ],
        DatingRestrictionType.suspended => [
          para(
            loc.dating_restrictedUntil(
              MyDateFormat.toDate(r.endsAt!.toLocal()),
            ),
          ),
          para(loc.dating_restrictedMeans),
        ],
      },
      if (appeal?.state == DatingAppealState.open)
        DatingCalmLine(loc.dating_appealSent)
      else if (appeal?.state == DatingAppealState.rejected)
        DatingCalmLine(loc.dating_appealRejected),
      if (r.canAppeal)
        FlowPrimaryButton(
          key: const ValueKey('dating_restricted_appeal'),
          label: loc.dating_appeal,
          onPressed: () async {
            final account = ref.read(datingAccountProvider);
            if (await showDatingAppealSheet(
                  context,
                  account: account,
                  restrictionId: r.id,
                ) &&
                context.mounted) {
              ref.invalidate(datingRestrictionProvider(account));
            }
          },
        ),
      const SizedBox(height: Spacing.sm),
      support,
    ];
  }
}

/// §3.7 the appeal, opened as [account]: true once it was sent.
Future<bool> showDatingAppealSheet(
  BuildContext context, {
  required String? account,
  required String restrictionId,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      routeSettings: datingSheetSettings('appeal'),
      isScrollControlled: true,
      builder:
          (sheet) => DatingSheetTracker(
            child: AllowLargeText(
              child: _AppealSheet(
                account: account,
                restrictionId: restrictionId,
              ),
            ),
          ),
    ) ==
    true;

class _AppealSheet extends ConsumerStatefulWidget {
  const _AppealSheet({required this.account, required this.restrictionId});

  final String? account;
  final String restrictionId;

  @override
  ConsumerState<_AppealSheet> createState() => _AppealSheetState();
}

class _AppealSheetState extends ConsumerState<_AppealSheet> {
  final _keys = DatingActionKeys();
  final _text = TextEditingController();
  bool _busy = false;
  String? _reason;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (next == widget.account) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _close(false));
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _close(bool sent) {
    if (_closed || !mounted) return;
    _closed = true;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      Navigator.of(context).pop(sent);
    } else {
      route.navigator?.removeRoute(route);
    }
  }

  Future<void> _send() async {
    if (_busy) return;
    final account = widget.account;
    final text = _text.text.trim();
    setState(() {
      _busy = true;
      _reason = null;
    });
    final r = await ref
        .read(datingReportGatewayProvider)
        .appeal(
          _keys.keyFor('appeal', [widget.restrictionId, text]),
          widget.restrictionId,
          text.isEmpty ? null : text,
        );
    _keys.settle('appeal', reason: r.reason);
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    // already_appealed: the first one stands; the screen reads it again.
    if (r.ok || r.reason == 'already_appealed') {
      _close(true);
      return;
    }
    setState(() {
      _busy = false;
      _reason = r.reason;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(datingAccountProvider) != widget.account) {
      return const SizedBox.shrink();
    }
    final loc = AppLocalizations.of(context)!;
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final reason = _reason;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.md,
          Spacing.md,
          Spacing.md + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                loc.dating_appeal,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              key: const ValueKey('dating_appeal_text'),
              controller: _text,
              enabled: !_busy,
              maxLength: 500,
              maxLines: 5,
              minLines: 3,
              enableSuggestions: false,
              autocorrect: false,
              enableIMEPersonalizedLearning: false,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: loc.dating_appealHint,
                border: const OutlineInputBorder(),
              ),
            ),
            if (!online) DatingCalmLine(loc.dating_offline),
            if (reason != null)
              FlowErrorLine(
                text: switch (reason) {
                  'busy' => loc.dating_busy,
                  'appeal_unavailable' => loc.dating_cardGone,
                  _ => loc.dating_errorGeneric,
                },
                liveRegion: true,
              ),
            const SizedBox(height: Spacing.sm),
            FlowPrimaryButton(
              key: const ValueKey('dating_appeal_send'),
              label: loc.dating_appealSend,
              busy: _busy,
              onPressed: online && !_busy ? _send : null,
            ),
            const SizedBox(height: Spacing.sm),
            FlowSecondaryButton(
              label: loc.dating_close,
              onPressed: () => _close(false),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: The route, the home model, the section, the audit and the manual**

Create `$D/edit_app_T4.py` with exactly:

```python
#!/usr/bin/env python3
# Spec 2 W7a Task 4 (§3.1, §3.7, §3.14, §3.15; R-43): /dating/restricted
# behind the lock gate; the section's restricted, hold and age-check cards
# lead there; an accepted appeal is said on the section for 7 days; the
# home reads it; the text-scale audit lists the route; the manual says
# Report again (R-43) and gains the report and appeal topic.
# Formatter-style edits (W3, W5 and W6 files, never formatted).
import importlib.util

spec = importlib.util.spec_from_file_location('anchor', '.superpowers/sdd/2026-11-21-spec2-w7/anchor.py')
anchor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(anchor)

anchor.edit('lib/features/dating/routes/dating_routes.dart', [
    ("""import 'package:attune/features/dating/not_open/dating_not_open_screen.dart';
""", """import 'package:attune/features/dating/not_open/dating_not_open_screen.dart';
import 'package:attune/features/dating/report/restricted_screen.dart';
"""),
    ("""  static const checkin = '/dating/checkin';
""", """  static const checkin = '/dating/checkin';

  /// Spec 2 W7a (§3.7): the restricted, hold and age-check screen.
  static const restricted = '/dating/restricted';
"""),
    ("""  datingRoute(
    DatingPaths.checkin,
    'datingCheckin',
    signedIn,
    (s) => const DatingCheckinScreen(),
    back: () => RouteNames.home,
  ),
];""", """  datingRoute(
    DatingPaths.checkin,
    'datingCheckin',
    signedIn,
    (s) => const DatingCheckinScreen(),
    back: () => RouteNames.home,
  ),
  // Spec 2 W7a (§3.7, §3.15): nothing here moves; alone, back is Me.
  datingRoute(
    DatingPaths.restricted,
    'datingRestricted',
    signedIn,
    (s) => const DatingRestrictedScreen(),
    back: datingMeLocation,
  ),
];"""),
], 'W7a Task 4')

anchor.edit('lib/features/dating/data/dating_home.dart', [
    ("""    this.check = DatingPauseCheck.unknown,
  });""", """    this.check = DatingPauseCheck.unknown,
    this.appealAccepted = false,
  });"""),
    ("""  /// A verification pause only (Spec 2 W4b, Task 3 M-4).
  final DatingPauseCheck check;
""", """  /// A verification pause only (Spec 2 W4b, Task 3 M-4).
  final DatingPauseCheck check;

  /// Spec 2 W7a (§3.7): an appeal was accepted in the last 7 days.
  final bool appealAccepted;
"""),
    ("""      check: DatingPauseCheck.fromWire(json['check']),
    );""", """      check: DatingPauseCheck.fromWire(json['check']),
      appealAccepted: json['appeal_accepted'] == true,
    );"""),
], 'W7a Task 4')

anchor.edit('lib/features/dating/section/dating_section.dart', [
    ("""      case DatingHomeState.active:
        return _SectionCard(
          title: loc.flow_slotDatingTitle,
          lines: [loc.dating_sectionActive],""", """      case DatingHomeState.active:
        return _SectionCard(
          title: loc.flow_slotDatingTitle,
          lines: [
            // Spec 2 W7a (§3.7): for 7 days after an accepted appeal.
            if (h.appealAccepted) loc.dating_appealAccepted,
            loc.dating_sectionActive,
          ],"""),
    ("""      case DatingHomeState.restricted:
        return _plain(loc, loc.dating_sectionRestricted, settings);
      case DatingHomeState.hold:
        return _plain(loc, loc.dating_sectionHold, settings);
      case DatingHomeState.ageReview:
        return _plain(loc, loc.dating_sectionAgeReview, settings);""", """      // Spec 2 W7a (§3.7): each leads to the screen with its category.
      case DatingHomeState.restricted:
        return _restricted(
          context,
          loc,
          loc.dating_sectionRestricted,
          settings,
        );
      case DatingHomeState.hold:
        return _restricted(context, loc, loc.dating_sectionHold, settings);
      case DatingHomeState.ageReview:
        return _restricted(
          context,
          loc,
          loc.dating_sectionAgeReview,
          settings,
        );"""),
    ("""  Widget _plain(AppLocalizations loc, String line, Widget? settings) =>""", """  Widget _restricted(
    BuildContext context,
    AppLocalizations loc,
    String line,
    Widget? settings,
  ) => _SectionCard(
    title: loc.flow_slotDatingTitle,
    lines: [line],
    children: [
      FlowSecondaryButton(
        key: const ValueKey('dating_section_restricted'),
        label: loc.dating_restrictedSeeWhy,
        onPressed: () => context.push(DatingPaths.restricted),
      ),
      if (settings != null) settings,
    ],
  );

  Widget _plain(AppLocalizations loc, String line, Widget? settings) =>"""),
    ("""    final ended = check == DatingPauseCheck.ended;
    return _SectionCard(
      title: loc.flow_slotDatingTitle,
      lines: [if (!ended) line],""", """    final ended = check == DatingPauseCheck.ended;
    return _SectionCard(
      title: loc.flow_slotDatingTitle,
      lines: [
        // Spec 2 W7a (§3.7): an accepted appeal leaves Dating paused.
        if (h.appealAccepted) loc.dating_appealAccepted,
        if (!ended) line,
      ],"""),
], 'W7a Task 4')

anchor.edit('test/architecture/text_scale_routes_test.dart', [
    ("""  'datingCheckin',
""", """  'datingCheckin',
  // Spec 2 W7a (§3.7): the restricted screen.
  'datingRestricted',
"""),
], 'W7a Task 4')

anchor.edit('lib/app/documentations/user_manual/data/dating_mode_docs.dart', [
    ("""              'When you match, you can write to each other in Conversations: text only, up to 1,000 characters. Phone numbers, emails, usernames and links show as "•••" until you both tap Swap contacts, which you can offer from three days after you match; once you\\'ve both swapped, it can\\'t be undone. There are no read receipts, and nobody can see when you\\'re online or typing. The shield at the top of a conversation lets you block, unmatch, close kindly, plan a meet, say you\\'ve met, or find safety resources. Unmatching ends the conversation for both of you, and you won\\'t be introduced again.',""",
     """              'When you match, you can write to each other in Conversations: text only, up to 1,000 characters. Phone numbers, emails, usernames and links show as "•••" until you both tap Swap contacts, which you can offer from three days after you match; once you\\'ve both swapped, it can\\'t be undone. There are no read receipts, and nobody can see when you\\'re online or typing. The shield at the top of a conversation lets you report, block, unmatch, close kindly, plan a meet, say you\\'ve met, or find safety resources. Unmatching ends the conversation for both of you, and you won\\'t be introduced again.',"""),
    ("""              'Never send money, account details or mobile money to someone you haven\\'t met in person, whatever the story. If someone asks, block them from the shield at the top of the conversation.',
          type: ManualContentType.warning,
        ),""", """              'Never send money, account details or mobile money to someone you haven\\'t met in person, whatever the story. If someone asks, report them from the shield at the top of the conversation.',
          type: ManualContentType.warning,
        ),
        // Spec 2 W7a (§3.7, §6.2, §6.3): reporting, and restrictions.
        ManualContent(
          id: 'dating_report',
          title: 'Reporting, and if your account is restricted',
          numberPrefix: '7',
          content:
              'Report someone from the shield in a conversation, from a safety card, from a card on Today, or from a conversation that ended in the last 30 days. Choose what happened and, if you like, tell us more. A person reviews every report. The other person is never told who reported them or what you wrote. Reporting never bans anyone by itself: for the most serious reports, a profile is paused only when the reports are confirmed. If your Dating account is restricted, Dating shows why, in a word or two, and you can appeal once. A different person from the one who made the decision looks at your appeal, usually within 7 days. The rest of Attune works as usual.',
          type: ManualContentType.text,
        ),"""),
], 'W7a Task 4')
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
python3 -I $D/edit_app_T4.py
dart format lib/features/dating/report test/features/dating/report 2>&1 | tail -1
flutter analyze --no-pub lib test 2>&1 | tail -1
flutter test --no-pub --update-goldens test/features/dating/report/restricted_screen_test.dart 2>&1 | tr '\r' '\n' | tail -1 | grep -oE 'All tests passed!|Some tests failed\.'
flutter test --no-pub test/features/dating test/architecture test/app 2>&1 | tr '\r' '\n' | grep -E '^[0-9:]+ \+[0-9]+' | tail -1 | grep -oE '\+[0-9]+( ~[0-9]+)?( -[0-9]+)?: (All tests passed!|Some tests failed\.)'
```

Expected: the five edit lines (`dating_routes.dart: 3 edit(s) (W7a Task 4)`, `dating_home.dart: 3 edit(s)`, `dating_section.dart: 4 edit(s)`, `text_scale_routes_test.dart: 1 edit(s)`, `dating_mode_docs.dart: 2 edit(s)`); `Formatted 7 files (0 changed) in … seconds.`; `571 issues found. (ran in …)` (no new issue); `All tests passed!` (the restricted screen's goldens written); `+1617: All tests passed!` (Dating, the architecture tests and the manual's guards; the restricted screen's 9 among them).

- [ ] **Step 5: The mutants**

Create `$D/mut_T4_dart.py` with exactly:

```python
# Spec 2 W7a Task 4: Dart mutants (dmut.py).
S = 'lib/features/dating/report/restricted_screen.dart'
T = ['test/features/dating/report/restricted_screen_test.dart']
MUTS = {
    'hold_says_reason': (S, '          loc.dating_restrictedAbout(label),', '          loc.dating_restrictedReason(label),', T),
    'appeal_always_offered': (S, '      if (r.canAppeal)', '      if (true)', T),
    'no_read_after_appeal': (S, '              ref.invalidate(datingRestrictionProvider(account));\n            }\n          },',
                             '            }\n          },', T),
    'appeal_untrimmed': (S, '    final text = _text.text.trim();', '    final text = _text.text;', T),
    'appeal_offline_sends': (S, '              onPressed: online && !_busy ? _send : null,', '              onPressed: !_busy ? _send : null,', T),
    'appeal_busy_new_key': (S, "    _keys.settle('appeal', reason: r.reason);", "    _keys.settle('appeal');", T),
    'verify_goes_nowhere': (S, "            key: const ValueKey('dating_restricted_verify'),\n            label: loc.dating_restrictedVerifyId,\n            onPressed: () => ref.read(datingSupportContactProvider)(context),",
                            "            key: const ValueKey('dating_restricted_verify'),\n            label: loc.dating_restrictedVerifyId,\n            onPressed: () {},", T),
    'read_not_per_account': (S, '    final read = ref.watch(datingRestrictionProvider(account));',
                             "    final read = ref.watch(datingRestrictionProvider('ama'));", T),
    'section_see_why_nowhere': ('lib/features/dating/section/dating_section.dart',
                                '        onPressed: () => context.push(DatingPaths.restricted),', '        onPressed: () {},', T),
    'accepted_not_said_paused': ('lib/features/dating/section/dating_section.dart',
                                 '        // Spec 2 W7a (§3.7): an accepted appeal leaves Dating paused.\n        if (h.appealAccepted) loc.dating_appealAccepted,',
                                 '        // Spec 2 W7a (§3.7): an accepted appeal leaves Dating paused.', T),
    'home_ignores_accepted': ('lib/features/dating/data/dating_home.dart',
                              "      appealAccepted: json['appeal_accepted'] == true,", '      appealAccepted: false,', T),
}
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7; python3 -I $D/dmut.py $D/mut_T4_dart.py > $D/mut_T4_dart.txt 2>&1; tail -1 $D/mut_T4_dart.txt
```

Expected: `11/11 killed`.

- [ ] **Step 6: The W7a gate**

Run the race script only when the machine is idle (`uptime` load below about 4; another agent's Flutter runs make the timing cases flake): otherwise wait, or note the load in the report.

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
$D/suite.sh attune_spec3a > $D/sql-W7a.txt; echo "$(grep -c '^PASS' $D/sql-W7a.txt) PASS, $(grep -c '^FAIL' $D/sql-W7a.txt) FAIL"
diff <(grep FAIL $D/sql-baseline.txt) <(grep FAIL $D/sql-W7a.txt)
flutter analyze --no-pub lib test > $D/analyze-W7a.txt 2>&1; tail -1 $D/analyze-W7a.txt
flutter test --no-pub --reporter compact > $D/flutter-W7a.txt 2>&1; tr '\r' '\n' < $D/flutter-W7a.txt | grep -E '^[0-9:]+ \+[0-9]+' | tail -1 | grep -oE '\+[0-9]+( ~[0-9]+)?( -[0-9]+)?: (All tests passed!|Some tests failed\.)'
shasum -c .superpowers/sdd/2026-11-04-spec1-w10-accessibility-docs/w10-1.0.sha | grep -vc ': OK$'; shasum -c .superpowers/sdd/2026-11-04-spec1-w9/flag_off.sha | grep -vc ': OK$'
shasum -c .superpowers/sdd/2026-11-07-spec2-w3/latch.sha; flutter test --no-pub test/architecture/games_untouched_test.dart 2>&1 | tr '\r' '\n' | tail -1 | grep -oE 'All tests passed!|Some tests failed\.'
python3 scripts/large_text_audit.py --scale 2.0 test/features/dating/report 2>&1 | tail -1
uptime
dropdb --if-exists w7race 2>/dev/null; createdb w7race
pg_dump -s attune_spec3a | psql -X -q -d w7race > /dev/null 2>&1
pg_dump -a -t public.metric_key_prefixes -t public.feature_flags -t public.country_safety_config -t private.dating_calling_codes -t public.dating_algorithm_configs -t public.dating_safety_configs -t private.dating_phone_trunk_rules -t private.flag_production_gates attune_spec3a | psql -X -q -d w7race > /dev/null 2>&1
bash scripts/concurrency/dating_kill_switch_races.sh w7race > $D/race_W7a.txt 2>&1; grep -c '^PASS' $D/race_W7a.txt; grep -v '^PASS' $D/race_W7a.txt
dropdb w7race
```

Expected: `162 PASS, 14 FAIL`; no diff; `571 issues found. (ran in …)`; `+8641 -3: Some tests failed.` (+19 since the baseline: Task 3's 10 and Task 4's 9; the three failures are the baseline's `healing_journal_large_text_test.dart` goldens, nothing else); `0`; `0`; `lib/home/home_screen.dart: OK`; `All tests passed!`; `SCALE 2.0: 0 site(s) to fix, 0 listed apart`; the load (replay: 9.60, every case passed); `42`, nothing else (W7a's two new cases among them). The mutants: Tasks 1–4.

- [ ] **Step 7: Record the tree**

Do not commit; record the tree in the report.

---

## Batch W7b — the moderation console

### Task 5: Migration `dating_v2_moderation_console`: moderators, the audit, sensitive routing at read time, the queue, the case, every action, the appeals, photos, verifications, countries, Opinions v0, the SLA check (§4.3, §4.6, §6.3, §6.4, §6.9, §7.1, §7.2, §7.5 mutant 26; S-5; R-56, R-60–R-62, R-67, R-68)

**Files:**
- Create: `supabase/migrations/20261121110000_dating_v2_moderation_console.sql`, `supabase/migrations/20261121110010_dating_v2_moderation_console_grants.sql`, `$D/{contract_T5.sql, edit_tests_T5.py, mut_T5.py}`
- Modify: `supabase/tests/dating_v2_moderation_contracts.sql` (I–M), `supabase/tests/{dating_rls_canary,service_role_grants_test,dating_v2_verification_contracts,dating_v2_setup_contracts}.sql`, `scripts/local_pg_grants.sql`

**Interfaces:**
- Consumes: Task 1's `private.dating_place_restriction`, `private.dating_report_case`; Task 2's `private.dating_close_case`, `private.dating_decide_appeal`; W3's `private.dating_pair_is_man_woman`, `dating_profile_sensitive`, `private.dating_field_decrypt`; W4's `decide_dating_human_review`, `dating_verification_sessions`; W3's photo states; W1's `publish_country_config`; Spec 1's `place_account_hold`, `app_setting`, `net.http_post`, S1 W9b's `admin_list_priority_reports(int)` and `admin_confirm_content_removal(text, uuid)` (only these two, R-61).
- Produces: `dating_moderators`, `dating_moderation_actions`; the `moderation_*` functions (Interfaces produced); `private.dating_audit`, `private.dating_moderator`, `private.dating_case_for`, `private.dating_case_needs_sensitive_routing`, `private.dating_evidence_messages`, `private.dating_lift_case_holds`; `dating_moderation_sla_check(timestamptz)` and the cron `dating-moderation-sla` (`*/15 * * * *`).

- [ ] **Step 1: Write the failing contract sections**

Create `$D/contract_T5.sql` with exactly (sections I–M; it ends with W7c's marker):

```sql
-- [p_sql] run: 'ok', or the error's SQLSTATE and message.
CREATE FUNCTION pg_temp.try_sql(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  RETURN SQLSTATE || ':' || SQLERRM;
END $$;
-- [p_sql] as the service role (its claims too): 'ok', or the error.
CREATE FUNCTION pg_temp.as_service(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'DISCARD PLANS';
  PERFORM set_config('request.jwt.claims', '{"role": "service_role"}', true);
  EXECUTE 'SET LOCAL ROLE service_role';
  EXECUTE p_sql;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN SQLSTATE || ':' || SQLERRM;
END $$;

-- =====================================================================
-- I. (§4.3, §4.4, §6.4, §7.3) The console's people and its audit: only an
--    active moderator gets an answer (anyone else: not_moderator,
--    counted); the moderation_* functions are the service role's alone;
--    the audit is append-only (an UPDATE or DELETE is refused; only the
--    purge may delete, and only at 2 years).
-- =====================================================================
DO $i$
DECLARE
  v_mod constant uuid := pg_temp.ready('85');
  v_off constant uuid := pg_temp.ready('86');
  v_stranger constant uuid := pg_temp.ready('87');
  v_target constant uuid := pg_temp.man('111');
  v_n bigint := pg_temp.metric('dating.moderation.not_moderator');
  v_got text;
  v_id uuid;
  v_case uuid;
BEGIN
  INSERT INTO public.dating_moderators (user_id, role) VALUES (v_mod, 'moderator');
  INSERT INTO public.dating_moderators (user_id, role, active) VALUES (v_off, 'moderator', false);
  IF public.moderation_whoami(v_mod) IS DISTINCT FROM
       '{"ok": true, "role": "moderator", "languages": [], "sensitive_routing_allowed": false}'::jsonb
     OR public.moderation_whoami(v_off) IS DISTINCT FROM '{"ok": false, "reason": "not_moderator"}'::jsonb
     OR public.moderation_queue(v_stranger) IS DISTINCT FROM '{"ok": false, "reason": "not_moderator"}'::jsonb
     OR public.moderation_case(v_stranger, gen_random_uuid()) IS DISTINCT FROM '{"ok": false, "reason": "not_moderator"}'::jsonb
     OR pg_temp.metric('dating.moderation.not_moderator') < v_n + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the console answered someone who is not an active moderator';
  END IF;
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_got
    FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname LIKE 'moderation\_%'
     AND (has_function_privilege('authenticated', p.oid, 'EXECUTE') OR has_function_privilege('anon', p.oid, 'EXECUTE')
          OR NOT has_function_privilege('service_role', p.oid, 'EXECUTE'));
  IF v_got IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a moderation function is not the service role''s alone: %', v_got;
  END IF;
  PERFORM private.dating_audit(v_mod, NULL, 'note', NULL, '{"note": "x"}');
  SELECT id INTO v_id FROM public.dating_moderation_actions WHERE actor_id = v_mod;
  v_got := pg_temp.try_sql(format('UPDATE public.dating_moderation_actions SET action = ''claim'' WHERE id = %L', v_id))
        || ' ' || pg_temp.try_sql(format('DELETE FROM public.dating_moderation_actions WHERE id = %L', v_id))
        || ' ' || pg_temp.probe(ARRAY[$p$SELECT set_config('attune.dating_audit_purge', 'on', true)$p$],
                    format('SELECT pg_temp.try_sql(%L)', format('DELETE FROM public.dating_moderation_actions WHERE id = %L', v_id)));
  IF v_got IS DISTINCT FROM '42501:audit:append_only 42501:audit:append_only 42501:audit:append_only' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the audit is not append-only (a young row under the purge''s setting too): %', v_got;
  END IF;
  v_got := pg_temp.probe(ARRAY[$p$SELECT set_config('attune.dating_audit_purge', 'on', true)$p$,
                               $p$ALTER TABLE public.dating_moderation_actions DISABLE TRIGGER dating_moderation_actions_append_only$p$,
                               format($p$UPDATE public.dating_moderation_actions SET created_at = now() - interval '2 years 1 day' WHERE id = %L$p$, v_id),
                               $p$ALTER TABLE public.dating_moderation_actions ENABLE TRIGGER dating_moderation_actions_append_only$p$],
                         format('SELECT pg_temp.try_sql(%L)', format('DELETE FROM public.dating_moderation_actions WHERE id = %L', v_id)));
  IF v_got IS DISTINCT FROM 'ok' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge could not delete a 2-year-old audit row: %', v_got;
  END IF;
  -- A foreign key's own SET NULL passes: the case purged, the person's
  -- account deleted (deletion never fails on the audit).
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, signal_kind, state, decided_at, outcome)
  VALUES ('signal', 'P2', v_target, 'dragnet', 'closed', now(), 'no_action') RETURNING id INTO v_case;
  PERFORM private.dating_audit(v_mod, v_case, 'dismiss', v_target);
  v_got := pg_temp.try_sql(format('DELETE FROM public.dating_moderation_cases WHERE id = %L', v_case))
        || ' ' || pg_temp.try_sql(format('SELECT pg_temp.delete_account(%L)', v_target));
  IF v_got IS DISTINCT FROM 'ok ok'
     OR (SELECT count(*) FROM public.dating_moderation_actions
          WHERE actor_id = v_mod AND action = 'dismiss' AND case_id IS NULL AND target_user_id IS NULL) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a purged case or a deleted account did not leave its audit row behind, unnamed';
  END IF;
END $i$;

-- =====================================================================
-- J. (§6.4, §7.1 routing, §7.5 mutant 26; S-5) Read-time routing: a case
--    whose people are not a woman and a man is left out of the queue of a
--    moderator without sensitive_routing_allowed, and opening or claiming
--    it reads case_unavailable (as a case that doesn't exist); a man-woman
--    case is the same for both; an unreadable identity routes; nothing
--    about routing reaches the audit.
-- =====================================================================
DO $j$
DECLARE
  v_mod constant uuid := pg_temp.ready('88');
  v_owner constant uuid := pg_temp.ready('89');
  v_w1 constant uuid := pg_temp.ready('90');
  v_w2 constant uuid := pg_temp.ready('91', '{"seeking": ["woman"]}');
  v_m constant uuid := pg_temp.man('92');
  v_w3 constant uuid := pg_temp.ready('93');
  v_nb constant uuid := pg_temp.ready('94', '{"identity": "non_binary", "seeking": ["woman"]}');
  v_same uuid;
  v_mw uuid;
  v_lone uuid;
  q jsonb;
BEGIN
  INSERT INTO public.dating_moderators (user_id, role) VALUES (v_mod, 'moderator');
  INSERT INTO public.dating_moderators (user_id, role, sensitive_routing_allowed) VALUES (v_owner, 'safety_owner', true);
  PERFORM pg_temp.report(v_w1, '90', pg_temp.match(v_w1, v_w2), 'harassment');
  SELECT case_id INTO v_same FROM public.dating_reports WHERE reporter_user_id = v_w1;
  PERFORM pg_temp.report(v_w3, '93', pg_temp.match(v_w3, v_m), 'harassment');
  SELECT case_id INTO v_mw FROM public.dating_reports WHERE reporter_user_id = v_w3;
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, signal_kind)
  VALUES ('signal', 'P2', v_nb, 'dragnet') RETURNING id INTO v_lone;
  q := public.moderation_queue(v_mod);
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(q -> 'cases') AS c WHERE (c ->> 'id')::uuid IN (v_same, v_lone))
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(q -> 'cases') AS c WHERE (c ->> 'id')::uuid = v_mw) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the queue showed a not-man-woman case to a moderator without routing (mutant 26)';
  END IF;
  IF public.moderation_case(v_mod, v_same) IS DISTINCT FROM '{"ok": false, "reason": "case_unavailable"}'::jsonb
     OR public.moderation_case(v_mod, v_same) IS DISTINCT FROM public.moderation_case(v_mod, gen_random_uuid())
     OR public.moderation_claim(v_mod, v_same) IS DISTINCT FROM '{"ok": false, "reason": "case_unavailable"}'::jsonb
     OR public.moderation_dismiss(v_mod, v_lone) IS DISTINCT FROM '{"ok": false, "reason": "case_unavailable"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a routed case opened (or answered differently from a missing one) without routing';
  END IF;
  q := public.moderation_queue(v_owner);
  IF (SELECT count(*) FROM jsonb_array_elements(q -> 'cases') AS c WHERE (c ->> 'id')::uuid IN (v_same, v_lone, v_mw)) <> 3
     OR (public.moderation_case(v_owner, v_same) ->> 'ok')::boolean IS NOT TRUE
     OR (public.moderation_case(v_mod, v_mw) ->> 'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner (or the moderator on a man-woman case) could not read a case';
  END IF;
  -- An identity that can't be read routes (fails closed).
  IF pg_temp.probe(ARRAY[format('UPDATE public.dating_profile_sensitive SET identity_enc = NULL WHERE user_id = %L', v_m)],
                   format('SELECT private.dating_case_needs_sensitive_routing(%L)::text', v_mw)) IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unreadable identity did not route';
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_moderation_actions AS a
              WHERE a.detail::text ~* '(routing|sensitive|identity|gender|woman|man\M|non_binary|seeking)') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the audit holds a routing or identity value';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns AS c
              WHERE c.table_schema IN ('public', 'private') AND c.column_name LIKE '%routing%'
                AND NOT (c.table_name = 'dating_moderators' AND c.column_name = 'sensitive_routing_allowed')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a column stores routing (S-5)';
  END IF;
END $j$;

-- =====================================================================
-- K. (§6.4 Case) One case: its reports with their text, the credibility
--    note and the evidence; the person as others see them (name, age,
--    region, approved prompts and photos) and nothing special-category;
--    prior cases by account or number; the safety families by name; never
--    who reported; opening it is audited.
-- =====================================================================
DO $k$
DECLARE
  v_mod constant uuid := pg_temp.ready('95');
  v_t constant uuid := pg_temp.man('96');
  v_r constant uuid := pg_temp.ready('97');
  v_m uuid;
  v_case uuid;
  v jsonb;
BEGIN
  INSERT INTO public.dating_moderators (user_id, role) VALUES (v_mod, 'moderator');
  v_m := pg_temp.match(v_t, v_r);
  PERFORM pg_temp.say(v_m, v_t, 'w7-k-evidence', 2);
  INSERT INTO public.dating_safety_events (match_id, at_risk_user_id, sender_user_id, rule_id, family, tier, config_version,
                                           source_event_key)
  VALUES (v_m, v_t, v_r, 'sexual_pressure:x', 'sexual_pressure', 1, 'dating_chat_v1', 'w7-k-trip'),
         (v_m, v_r, v_t, 'financial_request:momo', 'financial_request', 2, 'dating_chat_v1', 'w7-k-money');
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, target_phone_hmac, signal_kind, state, decided_at,
                                              outcome)
  VALUES ('signal', 'P2', NULL, public.dating_phone_hmac_for_user(v_t), 'dragnet', 'closed', now(), 'no_action');
  PERFORM pg_temp.report(v_r, '97', v_m, 'romance_scam', false, 'He asked for momo.');
  SELECT case_id INTO v_case FROM public.dating_reports WHERE match_id = v_m;
  v := public.moderation_case(v_mod, v_case);
  IF v #>> '{reports,0,details}' IS DISTINCT FROM 'He asked for momo.'
     OR v #>> '{reports,0,reporter_triggered}' IS DISTINCT FROM 'sexual_pressure'
     OR jsonb_array_length(v #> '{reports,0,evidence}') <> 2
     OR v #>> '{reports,0,evidence,0,text}' IS DISTINCT FROM 'w7-k-evidence 1'
     OR v #>> '{profile,display_name}' IS DISTINCT FROM 'Mod 96' OR (v #>> '{profile,age}')::int <> 30
     OR v #>> '{profile,region}' IS DISTINCT FROM 'AA' OR jsonb_array_length(v #> '{profile,photos}') <> 2
     OR jsonb_array_length(v #> '{profile,prompts}') <> 2
     OR jsonb_array_length(v -> 'prior') <> 1
     OR (SELECT array_agg(f ORDER BY f) FROM jsonb_array_elements_text(v -> 'families') AS f)
        IS DISTINCT FROM ARRAY['financial_request', 'sexual_pressure'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the case reads %', v - 'reports';
  END IF;
  IF position(v_r::text IN v::text) > 0 OR position('Mod 97' IN v::text) > 0
     OR v::text ~ '"(identity|seeking|faith|marital|pronouns|pools|reporter_user_id|reporter_phone_hmac)"' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the case names the reporter or a special-category answer';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_moderation_actions WHERE case_id = v_case AND action = 'open_case'
                    AND actor_id = v_mod AND detail = '{}'::jsonb) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: opening a case was not audited';
  END IF;
END $k$;

-- =====================================================================
-- L. (§6.3, §6.4) The actions: claim; hold and lift it; dismiss (lifts the
--    case's interim holds, stamps decided_at); restrict until a date (the
--    case decided, its holds lifted, the person suspended and appealable);
--    a closer look; ask for ID; confirm a minor (Spec 1's account hold,
--    once, three arguments); a note; an appeal decided through the
--    console (the restriction's decider refused); photos; verifications;
--    countries (publishing is the safety owner's); S1 W9b's Opinions queue
--    through its own RPCs; the audit log. Every action, one audit row.
-- =====================================================================
DO $l$
DECLARE
  v_mod constant uuid := pg_temp.ready('98');
  v_mod2 constant uuid := pg_temp.ready('99');
  v_owner constant uuid := pg_temp.ready('100');
  v_t1 constant uuid := pg_temp.man('101');
  v_t2 constant uuid := pg_temp.man('102');
  v_t3 constant uuid := pg_temp.man('103');
  v_t4 constant uuid := pg_temp.man('104');
  v_r1 constant uuid := pg_temp.ready('105');
  v_r2 constant uuid := pg_temp.ready('106');
  v_r3 constant uuid := pg_temp.ready('107');
  v_r4 constant uuid := pg_temp.ready('108');
  v_c1 uuid;
  v_c2 uuid;
  v_c3 uuid;
  v_c4 uuid;
  v_restr uuid;
  v_appeal_case uuid;
  v_photo uuid;
  v_ends constant timestamptz := date_trunc('second', now() + interval '14 days');
  v jsonb;
  v_got text;
  v_audit bigint;
BEGIN
  INSERT INTO public.dating_moderators (user_id, role) VALUES (v_mod, 'moderator'), (v_mod2, 'moderator');
  INSERT INTO public.dating_moderators (user_id, role, sensitive_routing_allowed) VALUES (v_owner, 'safety_owner', true);
  PERFORM pg_temp.report(v_r1, '105', pg_temp.match(v_t1, v_r1), 'harassment');
  SELECT case_id INTO v_c1 FROM public.dating_reports WHERE reporter_user_id = v_r1;
  PERFORM pg_temp.report(v_r2, '106', pg_temp.match(v_t2, v_r2), 'threats');
  SELECT case_id INTO v_c2 FROM public.dating_reports WHERE reporter_user_id = v_r2;
  PERFORM pg_temp.report(v_r3, '107', pg_temp.match(v_t3, v_r3), 'underage_risk');
  SELECT case_id INTO v_c3 FROM public.dating_reports WHERE reporter_user_id = v_r3;
  PERFORM pg_temp.report(v_r4, '108', pg_temp.match(v_t4, v_r4), 'spam');
  SELECT case_id INTO v_c4 FROM public.dating_reports WHERE reporter_user_id = v_r4;
  v_audit := (SELECT count(*) FROM public.dating_moderation_actions);
  -- Claim, hold, lift, dismiss.
  v_got := concat_ws(' ', public.moderation_claim(v_mod, v_c1) ->> 'ok',
                          public.moderation_place_hold(v_mod, v_c1, 'bogus') ->> 'reason');
  v_got := v_got || ' ' || (public.moderation_place_hold(v_mod, v_c1, 'harassment') ->> 'ok');
  IF v_got IS DISTINCT FROM 'true invalid true'
     OR (SELECT state || '/' || assigned_to::text FROM public.dating_moderation_cases WHERE id = v_c1)
        IS DISTINCT FROM 'in_review/' || v_mod
     OR pg_temp.held(v_t1) IS DISTINCT FROM 'moderation_hold/moderator/harassment/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: claim or hold read % (%)', v_got, pg_temp.held(v_t1);
  END IF;
  v := public.moderation_lift_hold(v_mod, v_c1);
  IF (v ->> 'lifted')::int <> 1 OR pg_temp.held(v_t1) <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: lifting the hold read %', v;
  END IF;
  PERFORM private.dating_place_restriction(v_t1, 'moderation_hold', 'harassment', 'report', v_c1, NULL, NULL, false);
  v := public.moderation_dismiss(v_mod, v_c1);
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb OR pg_temp.held(v_t1) <> ''
     OR (SELECT state || '/' || outcome || '/' || (decided_at IS NOT NULL) FROM public.dating_moderation_cases WHERE id = v_c1)
        IS DISTINCT FROM 'decided/dismissed/true'
     OR (SELECT state FROM public.dating_reports WHERE case_id = v_c1) <> 'not_upheld' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dismissing read % or left the interim hold, the stamp or the reports', v;
  END IF;
  -- Restrict until a date; the person can appeal; another moderator
  -- decides it (the decider can't).
  v_got := public.moderation_restrict(v_mod, v_c2, 'suspended', now() - interval '1 day', 'threats') ->> 'reason';
  v := public.moderation_restrict(v_mod, v_c2, 'suspended', v_ends, 'threats');
  IF v_got IS DISTINCT FROM 'invalid' OR v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.held(v_t2) IS DISTINCT FROM 'suspended/moderator/threats/true'
     OR (SELECT state || '/' || outcome FROM public.dating_moderation_cases WHERE id = v_c2) IS DISTINCT FROM 'decided/restricted'
     OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_t2) <> 'suspended' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: restricting read % (%)', v, pg_temp.held(v_t2);
  END IF;
  SELECT id INTO v_restr FROM public.dating_account_restrictions WHERE user_id = v_t2 AND lifted_at IS NULL;
  PERFORM pg_temp.j(v_t2, '102', format('SELECT public.submit_dating_appeal(%L, %L, NULL)', pg_temp.key('l-ap'), v_restr));
  SELECT c.id INTO v_appeal_case FROM public.dating_moderation_cases AS c JOIN public.dating_appeals AS a ON a.id = c.appeal_id
   WHERE a.restriction_id = v_restr;
  IF (public.moderation_case(v_mod2, v_appeal_case) #>> '{appeal,restriction,category}') IS DISTINCT FROM 'threats'
     OR public.moderation_decide_appeal(v_mod, v_appeal_case, true) IS DISTINCT FROM '{"ok": false, "reason": "same_decider"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the appeal case reads wrong or its decider decided it';
  END IF;
  v := public.moderation_decide_appeal(v_mod2, v_appeal_case, true);
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb OR pg_temp.held(v_t2) <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another moderator could not accept the appeal: %', v;
  END IF;
  -- A minor confirmed: Spec 1's account hold, once, naming the case.
  v := public.moderation_confirm_minor(v_mod, v_c3);
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT count(*) FROM public.account_holds WHERE user_id = v_t3 AND kind = 'age_review' AND reason_ref = v_c3::text) <> 1
     OR pg_temp.held(v_t3) NOT LIKE 'age_review/report/underage_risk/false%' AND pg_temp.held(v_t3) NOT LIKE 'age_review/moderator%'
     OR public.moderation_confirm_minor(v_mod, v_c4) ->> 'reason' IS DISTINCT FROM 'case_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: confirming a minor read % (one account hold, an underage_risk case only)', v;
  END IF;
  -- Ask for ID; a closer look; a note.
  v_got := public.moderation_note(v_mod, v_c4, repeat('x', 1001)) ->> 'reason';
  v_got := v_got || ' ' || (public.moderation_note(v_mod, v_c4, 'Checked the evidence.') ->> 'ok');
  v_got := v_got || ' ' || (public.moderation_ask_for_id(v_mod, v_c4) ->> 'ok');
  IF v_got IS DISTINCT FROM 'invalid true true' OR pg_temp.held(v_t4) IS DISTINCT FROM 'age_review/moderator/underage_risk/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: note or ask for ID read % (%)', v_got, pg_temp.held(v_t4);
  END IF;
  -- R-56: once support has seen the ID, the moderator lifts the age check.
  v := public.moderation_lift_hold(v_mod, v_c4);
  IF (v ->> 'lifted')::int <> 1 OR pg_temp.held(v_t4) <> ''
     OR (SELECT state || '/' || pause_reason FROM public.dating_enrollments WHERE user_id = v_t4) IS DISTINCT FROM 'paused/gates' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: lifting the age check read % (%)', v, pg_temp.held(v_t4);
  END IF;
  -- Photos.
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state, csam_state, rejection_reason)
  VALUES (v_t1, 'w7/review.jpg', 3, 'needs_review', 'clear', 'needs_review') RETURNING id INTO v_photo;
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(public.moderation_photos(v_mod) -> 'photos') AS p
                  WHERE (p ->> 'id')::uuid = v_photo)
     OR public.moderation_photo_decide(v_mod, v_photo, false, NULL) ->> 'reason' IS DISTINCT FROM 'invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the photo queue or its refusal read wrong';
  END IF;
  v := public.moderation_photo_decide(v_mod, v_photo, false, 'face_unclear');
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT moderation_state || '/' || rejection_reason FROM public.dating_profile_photos WHERE id = v_photo)
        IS DISTINCT FROM 'rejected/face_unclear'
     OR public.moderation_photo_decide(v_mod, v_photo, true, NULL) ->> 'reason' IS DISTINCT FROM 'photo_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: deciding a photo read %', v;
  END IF;
  -- Countries: the moderator reads, only the owner publishes.
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(public.moderation_countries(v_mod) -> 'countries') AS c
                  WHERE c ->> 'country' = 'GH')
     OR public.moderation_publish_country(v_mod, 'GH', '{"open_regions": ["AA"]}') IS DISTINCT FROM
        '{"ok": false, "reason": "safety_owner_only"}'::jsonb
     OR (public.moderation_publish_country(v_owner, 'GH', '{"open_regions": ["AA", "AH"]}') ->> 'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: countries read or published wrong';
  END IF;
  -- Opinions review queue v0 through its own RPCs (as the service role).
  v_got := pg_temp.as_service(format('SELECT public.moderation_opinions_queue(%L, 10)', v_mod));
  IF v_got IS DISTINCT FROM 'ok' OR public.moderation_opinions_remove(v_mod, 'forum_post', gen_random_uuid()) ->> 'reason'
       IS DISTINCT FROM 'invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Opinions queue read %', v_got;
  END IF;
  -- Every action, one audit row; the log lists them newest first.
  IF (SELECT count(*) FROM public.dating_moderation_actions) - v_audit
       <> (SELECT count(*) FROM public.dating_moderation_actions WHERE created_at = now() AND actor_id IN (v_mod, v_mod2, v_owner))
     OR NOT EXISTS (SELECT 1 FROM public.dating_moderation_actions WHERE action = 'restrict' AND case_id = v_c2
                       AND detail = jsonb_build_object('type', 'suspended', 'ends_at', v_ends, 'category', 'threats'))
     OR (SELECT count(DISTINCT action) FROM public.dating_moderation_actions WHERE actor_id IN (v_mod, v_mod2, v_owner)
           AND action IN ('claim', 'hold', 'lift_hold', 'dismiss', 'restrict', 'decide_appeal', 'confirm_minor', 'note',
                          'ask_for_id', 'photo_decide', 'publish_country', 'opinions_view')) <> 12 -- each of them
     OR jsonb_array_length(public.moderation_audit_log(v_mod, 5) -> 'actions') <> 5 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the actions are not each one audit row';
  END IF;
END $l$;

-- =====================================================================
-- M. (§4.6, §6.5) SLA alerts: every 15 minutes; past its clock, one
--    content-free line per priority about the oldest case ("P0 case
--    waiting 3 h 40 m"), to the webhook; without one, counted, nothing
--    sent.
-- =====================================================================
-- pg_net replaced, inside this transaction only, by a recorder (the
-- reaction_push_kick contract's way).
CREATE TEMP TABLE w7_posts (url text, body jsonb) ON COMMIT DROP;
CREATE OR REPLACE FUNCTION net.http_post(
  url text, body jsonb DEFAULT '{}'::jsonb, params jsonb DEFAULT '{}'::jsonb,
  headers jsonb DEFAULT '{}'::jsonb, timeout_milliseconds integer DEFAULT 5000)
RETURNS bigint LANGUAGE plpgsql AS $$
BEGIN
  IF current_setting('test.post_fails', true) = 'on' THEN
    RAISE EXCEPTION 'stub: pg_net is down';
  END IF;
  INSERT INTO pg_temp.w7_posts VALUES (url, body);
  RETURN 1;
END $$;
DO $m$
DECLARE
  v_t constant uuid := pg_temp.man('110');
  v_n bigint := pg_temp.metric('dating.sla.alert_unconfigured');
  v_f bigint := pg_temp.metric('dating.sla.alert_failed');
  v jsonb;
BEGIN
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, sla_due_at, created_at)
  VALUES ('report', 'P0', v_t, now() - interval '1 hour', now() - interval '3 hours 40 minutes');
  PERFORM set_config('app.settings.moderation_alert_webhook', '', true);
  v := public.dating_moderation_sla_check(now());
  IF (v ->> 'alerts')::int <> 0 OR pg_temp.metric('dating.sla.alert_unconfigured') <= v_n
     OR EXISTS (SELECT 1 FROM pg_temp.w7_posts) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without a webhook the check read % (counted, nothing sent)', v;
  END IF;
  PERFORM set_config('app.settings.moderation_alert_webhook', 'https://alerts.invalid/hook', true);
  v := public.dating_moderation_sla_check(now());
  IF (v ->> 'alerts')::int < 1
     OR NOT EXISTS (SELECT 1 FROM pg_temp.w7_posts AS q
                     WHERE q.url = 'https://alerts.invalid/hook' AND q.body = '{"text": "P0 case waiting 3 h 40 m"}'::jsonb)
     OR EXISTS (SELECT 1 FROM pg_temp.w7_posts AS q
                 WHERE (SELECT array_agg(k) FROM jsonb_object_keys(q.body) AS k) <> ARRAY['text']
                    OR q.body ->> 'text' !~ '^P[0-3] case waiting [0-9]+ h [0-9]+ m$')
     OR NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dating-moderation-sla' AND schedule = '*/15 * * * *'
                       AND command = 'SELECT public.dating_moderation_sla_check()') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the SLA alert is missing, carries more than its line, or has no cron';
  END IF;
  PERFORM set_config('test.post_fails', 'on', true);
  PERFORM public.dating_moderation_sla_check(now());
  IF pg_temp.metric('dating.sla.alert_failed') <= v_f THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed alert was not counted';
  END IF;
  PERFORM set_config('test.post_fails', '', true);
  PERFORM set_config('app.settings.moderation_alert_webhook', '', true);
END $m$;

-- @@W7C@@
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
python3 -I $D/splice.py supabase/tests/dating_v2_moderation_contracts.sql '-- @@W7B@@' $D/contract_T5.sql
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_moderation_contracts.sql 2>&1 | grep -m1 -oE 'ERROR: .*'
```

Expected: `ERROR:  relation "public.dating_moderators" does not exist`.

- [ ] **Step 2: The migration and its grants**

Create `supabase/migrations/20261121110000_dating_v2_moderation_console.sql` with exactly:

```sql
-- Spec 2 W7b (§4.3, §4.4 moderation_*, §4.6 dating-moderation-sla, §4.9
-- W7b, §6.4, §6.5, §7.1 routing rows, §7.5 mutant 26; S-5): the console's
-- server side.
--   * dating_moderators (role, sensitive_routing_allowed, languages,
--     active) and dating_moderation_actions, append-only (a trigger
--     refuses every UPDATE, and every DELETE but the purge's, at 2 years).
--   * Read-time sensitive routing (S-5): dating_case_needs_sensitive_routing
--     decrypts the identities of the people a case puts side by side (the
--     members of its matches, its reporters; an appeal: its restriction's
--     case too) inside the transaction and answers only true or false; a
--     case it answers true for is left out of the queue, and refused on open
--     with the ordinary case_unavailable, for anyone without
--     sensitive_routing_allowed. Nothing about routing is stored, logged or
--     written to the audit. An unknown identity routes (fails closed).
--   * moderation_* functions, the service role's alone, called only by the
--     dating-moderation edge function with the moderator's id: whoami, the
--     queue, claim, the case, dismiss, hold, lift a hold, restrict, ask for
--     ID, confirm a minor (Spec 1's age_review account hold, §6.3), a note,
--     decide an appeal, photos, verifications, countries (publish: the
--     safety owner only), S1 W9b's Opinions review queue v0 through its own
--     two RPCs, the audit log. Every action writes one audit row.
--   * dating_moderation_sla_check() and its cron (every 15 minutes): a
--     content-free alert per priority past its clock ("P0 case waiting 3 h
--     40 m") to app_setting('moderation_alert_webhook'), counted when unset.
-- Nothing here turns a flag on or names a moderator (the owner adds rows).
-- Grants in 20261121110010_dating_v2_moderation_console_grants.sql; this
-- file revokes what it creates from every API role first.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- ---------------------------------------------------------------------
-- 1. Moderators and the audit log.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.dating_moderators (
  user_id uuid PRIMARY KEY REFERENCES public.users (id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('moderator', 'safety_owner')),
  sensitive_routing_allowed boolean NOT NULL DEFAULT false,
  languages text[] NOT NULL DEFAULT '{}',
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.dating_moderators ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.dating_moderation_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id uuid REFERENCES public.dating_moderation_cases (id) ON DELETE SET NULL,
  actor_id uuid NOT NULL,
  action text NOT NULL CHECK (action IN (
    'open_case', 'claim', 'dismiss', 'hold', 'lift_hold', 'restrict', 'ask_for_id', 'confirm_minor', 'note',
    'decide_appeal', 'photo_decide', 'verification_decide', 'publish_country', 'opinions_view', 'opinions_remove',
    'escalation', 'law_enforcement_request')),
  target_user_id uuid REFERENCES public.users (id) ON DELETE SET NULL,
  detail jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(detail) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS dating_moderation_actions_case_idx ON public.dating_moderation_actions (case_id);
CREATE INDEX IF NOT EXISTS dating_moderation_actions_created_idx ON public.dating_moderation_actions (created_at DESC);
ALTER TABLE public.dating_moderation_actions ENABLE ROW LEVEL SECURITY;

-- Append-only: no UPDATE but a foreign key's own SET NULL (the case
-- purged, the person's account deleted), nothing else changed; a DELETE
-- only from the purge (it sets attune.dating_audit_purge for its own
-- transaction) and only at 2 years.
CREATE OR REPLACE FUNCTION private.dating_moderation_actions_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.id = OLD.id AND NEW.actor_id = OLD.actor_id AND NEW.action = OLD.action
     AND NEW.detail = OLD.detail AND NEW.created_at = OLD.created_at
     AND (NEW.case_id IS NULL OR NEW.case_id = OLD.case_id)
     AND (NEW.target_user_id IS NULL OR NEW.target_user_id = OLD.target_user_id)
     AND (NEW.case_id IS DISTINCT FROM OLD.case_id OR NEW.target_user_id IS DISTINCT FROM OLD.target_user_id) THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'DELETE' AND current_setting('attune.dating_audit_purge', true) = 'on'
     AND OLD.created_at < now() - interval '2 years' THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'audit:append_only' USING ERRCODE = '42501';
END;
$$;
DROP TRIGGER IF EXISTS dating_moderation_actions_append_only ON public.dating_moderation_actions;
CREATE TRIGGER dating_moderation_actions_append_only
  BEFORE UPDATE OR DELETE ON public.dating_moderation_actions
  FOR EACH ROW EXECUTE FUNCTION private.dating_moderation_actions_guard();

CREATE OR REPLACE FUNCTION private.dating_audit(p_actor uuid, p_case uuid, p_action text, p_target uuid,
                                                p_detail jsonb DEFAULT '{}'::jsonb)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  INSERT INTO public.dating_moderation_actions (case_id, actor_id, action, target_user_id, detail)
  VALUES (p_case, p_actor, p_action, (SELECT u.id FROM public.users AS u WHERE u.id = p_target),
          coalesce(p_detail, '{}'::jsonb));
$$;

CREATE OR REPLACE FUNCTION private.dating_moderator(p_actor uuid)
RETURNS public.dating_moderators
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT m.* FROM public.dating_moderators AS m WHERE m.user_id = p_actor AND m.active;
$$;

-- ---------------------------------------------------------------------
-- 2. Read-time sensitive routing (S-5).
-- ---------------------------------------------------------------------
-- A person's own identity answer ('woman', 'man', ...), or the one held
-- through a move; NULL when there is none or it can't be read.
CREATE OR REPLACE FUNCTION private.dating_identity_of(p_user uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN (SELECT private.dating_field_decrypt(coalesce(s.identity_enc, s.held_identity_enc)) ->> 'identity'
            FROM public.dating_profile_sensitive AS s WHERE s.user_id = p_user);
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END;
$$;

-- True when the case puts side by side two people who are not a woman and
-- a man, or when anyone it concerns can't be read: only this boolean ever
-- leaves the function.
CREATE OR REPLACE FUNCTION private.dating_case_needs_sensitive_routing(p_case uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  c public.dating_moderation_cases;
  v_target text;
  v_other uuid;
  v_from uuid;
BEGIN
  SELECT * INTO c FROM public.dating_moderation_cases AS x WHERE x.id = p_case;
  IF c.id IS NULL THEN
    RETURN true;
  END IF;
  v_target := private.dating_identity_of(c.target_user_id);
  IF v_target IS NULL OR v_target NOT IN ('woman', 'man') THEN
    RETURN true;
  END IF;
  IF c.kind = 'appeal' THEN
    SELECT r.case_id INTO v_from FROM public.dating_appeals AS a
      JOIN public.dating_account_restrictions AS r ON r.id = a.restriction_id
     WHERE a.id = c.appeal_id;
    IF v_from IS NOT NULL AND v_from <> c.id AND private.dating_case_needs_sensitive_routing(v_from) THEN
      RETURN true;
    END IF;
  END IF;
  FOR v_other IN
    SELECT x.u FROM (
      SELECT unnest(ARRAY[m.user_low_id, m.user_high_id]) AS u
        FROM public.dating_matches AS m
       WHERE m.id = c.match_id
          OR m.id IN (SELECT l.match_id FROM public.dating_case_matches AS l WHERE l.case_id = c.id)
      UNION ALL
      SELECT r.reporter_user_id FROM public.dating_reports AS r WHERE r.case_id = c.id OR r.id = c.report_id
    ) AS x
     WHERE x.u IS DISTINCT FROM c.target_user_id
  LOOP
    IF NOT private.dating_pair_is_man_woman(v_target, private.dating_identity_of(v_other)) THEN
      RETURN true;
    END IF;
  END LOOP;
  RETURN false;
END;
$$;

-- The case as [p_mod] may see it: NULL when it doesn't exist or needs the
-- routing they lack (one answer for both).
CREATE OR REPLACE FUNCTION private.dating_case_for(p_mod public.dating_moderators, p_case uuid)
RETURNS public.dating_moderation_cases
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT c.* FROM public.dating_moderation_cases AS c
   WHERE p_mod.user_id IS NOT NULL AND c.id = p_case
     AND (p_mod.sensitive_routing_allowed OR NOT private.dating_case_needs_sensitive_routing(c.id));
$$;

-- A report's evidence, decrypted (the messages only; NULL when unreadable).
CREATE OR REPLACE FUNCTION private.dating_evidence_messages(p_report uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN (SELECT private.dating_field_decrypt(e.snapshot_enc) -> 'messages'
            FROM public.dating_report_evidence AS e WHERE e.report_id = p_report);
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END;
$$;

-- ---------------------------------------------------------------------
-- 3. The console's reads.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.moderation_whoami(p_actor uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'role', v_mod.role,
    'sensitive_routing_allowed', v_mod.sensitive_routing_allowed, 'languages', to_jsonb(v_mod.languages));
END;
$$;

-- Open cases by priority and time to their clock; a case needing routing
-- only for those allowed (decided now, never stored).
CREATE OR REPLACE FUNCTION public.moderation_queue(p_actor uuid, p_limit integer DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
BEGIN
  IF v_mod.user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'cases', coalesce((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
             'id', c.id, 'kind', c.kind, 'priority', c.priority, 'state', c.state, 'signal_kind', c.signal_kind,
             'category', (SELECT r.category FROM public.dating_reports AS r WHERE r.case_id = c.id
                           ORDER BY r.priority, r.created_at LIMIT 1),
             'reports', (SELECT count(*) FROM public.dating_reports AS r WHERE r.case_id = c.id),
             'sla_due_at', c.sla_due_at, 'created_at', c.created_at,
             'mine', c.assigned_to = p_actor, 'claimed', c.assigned_to IS NOT NULL,
             'gone', c.target_user_id IS NULL)
           ORDER BY c.priority, c.sla_due_at NULLS LAST, c.created_at)
      FROM (SELECT x.* FROM public.dating_moderation_cases AS x
             WHERE x.state IN ('open', 'in_review')
               AND (v_mod.sensitive_routing_allowed OR NOT private.dating_case_needs_sensitive_routing(x.id))
             ORDER BY x.priority, x.sla_due_at NULLS LAST, x.created_at
             LIMIT greatest(1, least(coalesce(p_limit, 50), 200))) AS c), '[]'::jsonb));
END;
$$;

-- One case: what §6.4 lists, never the reporter's identity, never a
-- special-category answer (no function here reads one), never CSAM.
CREATE OR REPLACE FUNCTION public.moderation_case(p_actor uuid, p_case uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  c public.dating_moderation_cases;
  v_hmac text;
  v_profile jsonb;
  v_appeal jsonb;
BEGIN
  IF v_mod.user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  c := private.dating_case_for(v_mod, p_case);
  IF c.id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
  END IF;
  v_hmac := coalesce(c.target_phone_hmac, public.dating_phone_hmac_for_user(c.target_user_id));
  SELECT pg_catalog.jsonb_build_object(
           'display_name', p.display_name, 'age', public.account_age(p.user_id),
           'country', p.country_code, 'region', p.region_code,
           'prompts', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('prompt', q.prompt_id, 'answer', q.answer)
                                         ORDER BY q.position)
                                  FROM public.dating_prompts AS q WHERE q.user_id = p.user_id AND q.moderation_state = 'approved'),
                               '[]'::jsonb),
           'photos', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('position', f.position, 'key', f.storage_key)
                                        ORDER BY f.position)
                                 FROM public.dating_profile_photos AS f
                                WHERE f.user_id = p.user_id AND f.moderation_state = 'approved' AND f.csam_state = 'clear'),
                              '[]'::jsonb))
    INTO v_profile
    FROM public.dating_profiles AS p WHERE p.user_id = c.target_user_id;
  IF c.kind = 'appeal' THEN
    SELECT pg_catalog.jsonb_build_object('text', a.text, 'submitted_at', a.submitted_at, 'state', a.state,
             'restriction', pg_catalog.jsonb_build_object('type', r.restriction_type, 'category', r.category,
                              'source', r.source, 'ends_at', r.ends_at, 'starts_at', r.starts_at,
                              'decided_by_me', r.decided_by = p_actor))
      INTO v_appeal
      FROM public.dating_appeals AS a JOIN public.dating_account_restrictions AS r ON r.id = a.restriction_id
     WHERE a.id = c.appeal_id;
  END IF;
  PERFORM private.dating_audit(p_actor, c.id, 'open_case', c.target_user_id);
  RETURN pg_catalog.jsonb_build_object('ok', true,
    'case', pg_catalog.jsonb_build_object('id', c.id, 'kind', c.kind, 'priority', c.priority, 'state', c.state,
              'signal_kind', c.signal_kind, 'sla_due_at', c.sla_due_at, 'created_at', c.created_at,
              'decided_at', c.decided_at, 'outcome', c.outcome, 'mine', c.assigned_to = p_actor,
              'gone', c.target_user_id IS NULL),
    'reports', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                           'id', r.id, 'category', r.category, 'priority', r.priority, 'details', r.details,
                           'created_at', r.created_at, 'state', r.state,
                           -- §6.2: "The reporter's messages in this chat triggered: {family}"
                           'reporter_triggered', r.reporter_tripped_family,
                           'evidence', private.dating_evidence_messages(r.id))
                         ORDER BY r.created_at)
                          FROM public.dating_reports AS r WHERE r.case_id = c.id OR r.id = c.report_id), '[]'::jsonb),
    'profile', v_profile,
    'prior', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id', x.id, 'kind', x.kind,
                         'state', x.state, 'outcome', x.outcome, 'created_at', x.created_at) ORDER BY x.created_at DESC)
                        FROM public.dating_moderation_cases AS x
                       WHERE x.id <> c.id
                         AND ((c.target_user_id IS NOT NULL AND x.target_user_id = c.target_user_id)
                              OR (v_hmac IS NOT NULL AND x.target_phone_hmac = v_hmac))), '[]'::jsonb),
    'families', coalesce((SELECT pg_catalog.jsonb_agg(DISTINCT e.family)
                            FROM public.dating_safety_events AS e
                           WHERE e.match_id = c.match_id
                              OR e.match_id IN (SELECT l.match_id FROM public.dating_case_matches AS l WHERE l.case_id = c.id)),
                         '[]'::jsonb),
    'appeal', v_appeal);
END;
$$;

-- ---------------------------------------------------------------------
-- 4. The console's actions. Each: the moderator, the case they may see
--    (else case_unavailable), one audit row; the detail holds fixed keys
--    only (never routing, never a special-category value).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.moderation_claim(p_actor uuid, p_case uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  c public.dating_moderation_cases;
BEGIN
  IF v_mod.user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  c := private.dating_case_for(v_mod, p_case);
  IF c.id IS NULL OR c.state NOT IN ('open', 'in_review') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
  END IF;
  UPDATE public.dating_moderation_cases AS x SET assigned_to = p_actor, state = 'in_review' WHERE x.id = c.id;
  PERFORM private.dating_audit(p_actor, c.id, 'claim', c.target_user_id);
  RETURN pg_catalog.jsonb_build_object('ok', true);
END;
$$;

-- The interim holds a report case placed are lifted with it.
CREATE OR REPLACE FUNCTION private.dating_lift_case_holds(p_case uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  UPDATE public.dating_account_restrictions AS r SET lifted_at = now()
   WHERE r.case_id = p_case AND r.source = 'report' AND r.restriction_type IN ('moderation_hold', 'age_review')
     AND r.lifted_at IS NULL;
$$;

-- Dismiss: no action (a signal case's dismissal lifts its throttle).
CREATE OR REPLACE FUNCTION public.moderation_dismiss(p_actor uuid, p_case uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  c public.dating_moderation_cases;
  v jsonb;
BEGIN
  IF v_mod.user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  c := private.dating_case_for(v_mod, p_case);
  IF c.id IS NULL OR c.kind = 'appeal' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
  END IF;
  v := private.dating_close_case(c.id, p_actor, 'dismissed');
  IF (v ->> 'ok')::boolean THEN
    PERFORM private.dating_lift_case_holds(c.id);
    PERFORM private.dating_audit(p_actor, c.id, 'dismiss', c.target_user_id);
  END IF;
  RETURN v;
END;
$$;

-- Hold: an interim hold by a person (not appealable until decided).
CREATE OR REPLACE FUNCTION public.moderation_place_hold(p_actor uuid, p_case uuid, p_category text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  c public.dating_moderation_cases;
BEGIN
  IF v_mod.user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  IF private.dating_report_priority(p_category) IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  c := private.dating_case_for(v_mod, p_case);
  IF c.id IS NULL OR c.state NOT IN ('open', 'in_review') OR c.target_user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
  END IF;
  PERFORM private.dating_place_restriction(c.target_user_id, 'moderation_hold', p_category, 'moderator', c.id, p_actor,
                                           NULL, false);
  UPDATE public.dating_moderation_cases AS x SET state = 'in_review', assigned_to = coalesce(x.assigned_to, p_actor)
   WHERE x.id = c.id;
  PERFORM private.dating_audit(p_actor, c.id, 'hold', c.target_user_id, pg_catalog.jsonb_build_object('category', p_category));
  RETURN pg_catalog.jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.moderation_lift_hold(p_actor uuid, p_case uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  c public.dating_moderation_cases;
  v_n integer;
BEGIN
  IF v_mod.user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  c := private.dating_case_for(v_mod, p_case);
  IF c.id IS NULL OR c.target_user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
  END IF;
  -- Ruling R-56: a hold, or an age check once support has seen the ID.
  UPDATE public.dating_account_restrictions AS r SET lifted_at = now()
   WHERE r.user_id = c.target_user_id AND r.restriction_type IN ('moderation_hold', 'age_review') AND r.lifted_at IS NULL
     AND r.source IN ('report', 'moderator');
  GET DIAGNOSTICS v_n = ROW_COUNT;
  PERFORM private.dating_audit(p_actor, c.id, 'lift_hold', c.target_user_id);
  RETURN pg_catalog.jsonb_build_object('ok', true, 'lifted', v_n);
END;
$$;

-- Restrict (§6.3): suspended (until a date, or for good) or a closer look
-- (under_review); the case's interim holds go; the case is decided.
CREATE OR REPLACE FUNCTION public.moderation_restrict(p_actor uuid, p_case uuid, p_type text, p_ends_at timestamptz,
                                                      p_category text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  c public.dating_moderation_cases;
BEGIN
  IF v_mod.user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  IF p_type IS NULL OR p_type NOT IN ('suspended', 'under_review') OR private.dating_report_priority(p_category) IS NULL
     OR (p_ends_at IS NOT NULL AND p_ends_at <= now()) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  c := private.dating_case_for(v_mod, p_case);
  IF c.id IS NULL OR c.state NOT IN ('open', 'in_review') OR c.target_user_id IS NULL OR c.kind = 'appeal' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
  END IF;
  PERFORM private.dating_lift_case_holds(c.id);
  PERFORM private.dating_place_restriction(c.target_user_id, p_type, p_category, 'moderator', c.id, p_actor, p_ends_at,
                                           p_type = 'suspended');
  PERFORM private.dating_close_case(c.id, p_actor, 'restricted');
  PERFORM private.dating_audit(p_actor, c.id, 'restrict', c.target_user_id,
    pg_catalog.jsonb_build_object('type', p_type, 'ends_at', p_ends_at, 'category', p_category));
  RETURN pg_catalog.jsonb_build_object('ok', true);
END;
$$;

-- Ask for ID: the person's Dating waits for an ID check (an age review);
-- the case is decided.
CREATE OR REPLACE FUNCTION public.moderation_ask_for_id(p_actor uuid, p_case uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  c public.dating_moderation_cases;
BEGIN
  IF v_mod.user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  c := private.dating_case_for(v_mod, p_case);
  IF c.id IS NULL OR c.state NOT IN ('open', 'in_review') OR c.target_user_id IS NULL OR c.kind = 'appeal' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
  END IF;
  PERFORM private.dating_place_restriction(c.target_user_id, 'age_review', 'underage_risk', 'moderator', c.id, p_actor,
                                           NULL, false);
  PERFORM private.dating_close_case(c.id, p_actor, 'asked_for_id');
  PERFORM private.dating_audit(p_actor, c.id, 'ask_for_id', c.target_user_id);
  RETURN pg_catalog.jsonb_build_object('ok', true);
END;
$$;

-- §6.3: a moderator confirms a minor on an underage_risk case: Spec 1's
-- account-level age review (three arguments, I-7) closes the whole app.
CREATE OR REPLACE FUNCTION public.moderation_confirm_minor(p_actor uuid, p_case uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  c public.dating_moderation_cases;
BEGIN
  IF v_mod.user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  c := private.dating_case_for(v_mod, p_case);
  IF c.id IS NULL OR c.state NOT IN ('open', 'in_review') OR c.target_user_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.dating_reports AS r WHERE r.case_id = c.id AND r.category = 'underage_risk') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
  END IF;
  PERFORM private.dating_place_restriction(c.target_user_id, 'age_review', 'underage_risk', 'moderator', c.id, p_actor,
                                           NULL, false);
  PERFORM public.place_account_hold(c.target_user_id, 'age_review', c.id::text);
  PERFORM private.dating_close_case(c.id, p_actor, 'restricted');
  PERFORM private.dating_audit(p_actor, c.id, 'confirm_minor', c.target_user_id);
  RETURN pg_catalog.jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.moderation_note(p_actor uuid, p_case uuid, p_note text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  c public.dating_moderation_cases;
  v_note constant text := NULLIF(btrim(coalesce(p_note, '')), '');
BEGIN
  IF v_mod.user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  IF v_note IS NULL OR char_length(v_note) > 1000 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  c := private.dating_case_for(v_mod, p_case);
  IF c.id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
  END IF;
  PERFORM private.dating_audit(p_actor, c.id, 'note', c.target_user_id, pg_catalog.jsonb_build_object('note', v_note));
  RETURN pg_catalog.jsonb_build_object('ok', true);
END;
$$;

-- Appeals (§6.3): W7a's rule decides who may (mutant 15).
CREATE OR REPLACE FUNCTION public.moderation_decide_appeal(p_actor uuid, p_case uuid, p_accept boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  c public.dating_moderation_cases;
  v jsonb;
BEGIN
  IF v_mod.user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  c := private.dating_case_for(v_mod, p_case);
  IF c.id IS NULL OR c.kind <> 'appeal' OR c.appeal_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
  END IF;
  v := private.dating_decide_appeal(c.appeal_id, p_actor, v_mod.role = 'safety_owner', p_accept);
  IF (v ->> 'ok')::boolean THEN
    PERFORM private.dating_audit(p_actor, c.id, 'decide_appeal', c.target_user_id,
                                 pg_catalog.jsonb_build_object('accept', p_accept));
  END IF;
  RETURN v;
END;
$$;

-- Photos waiting for a person (§6.4): approve, or reject with a reason.
CREATE OR REPLACE FUNCTION public.moderation_photos(p_actor uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
BEGIN
  IF v_mod.user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'photos', coalesce((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id', f.id, 'position', f.position, 'key', f.storage_key,
             'reason', f.rejection_reason, 'created_at', f.created_at) ORDER BY f.created_at)
      FROM public.dating_profile_photos AS f
     WHERE f.moderation_state = 'needs_review' AND f.csam_state = 'clear'), '[]'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION public.moderation_photo_decide(p_actor uuid, p_photo uuid, p_approve boolean, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  v_user uuid;
BEGIN
  IF v_mod.user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  IF p_approve IS NULL OR (NOT p_approve AND (p_reason IS NULL OR p_reason NOT IN ('face_unclear', 'too_small', 'contains_child', 'unsafe'))) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  UPDATE public.dating_profile_photos AS f
     SET moderation_state = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
         rejection_reason = CASE WHEN p_approve THEN NULL ELSE p_reason END
   WHERE f.id = p_photo AND f.moderation_state = 'needs_review' AND f.csam_state = 'clear'
  RETURNING f.user_id INTO v_user;
  IF v_user IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'photo_unavailable');
  END IF;
  PERFORM private.dating_audit(p_actor, NULL, 'photo_decide', v_user,
    pg_catalog.jsonb_build_object('approve', p_approve, 'reason', CASE WHEN p_approve THEN NULL ELSE p_reason END));
  RETURN pg_catalog.jsonb_build_object('ok', true);
END;
$$;

-- Verifications waiting for a person (§6.4): the gesture photos' paths
-- (the edge function signs them) beside the approved photos.
CREATE OR REPLACE FUNCTION public.moderation_verifications(p_actor uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
BEGIN
  IF v_mod.user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'sessions', coalesce((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id', s.id, 'step', s.step, 'kind', s.kind,
             'gestures', to_jsonb(s.gestures), 'since', coalesce(s.awaiting_since, s.updated_at),
             'review_paths', CASE WHEN s.step = 'human' THEN pg_catalog.jsonb_build_array(s.id || '/1.jpg', s.id || '/2.jpg')
                                  ELSE '[]'::jsonb END,
             'photos', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('position', f.position, 'key', f.storage_key)
                                          ORDER BY f.position)
                                   FROM public.dating_profile_photos AS f
                                  WHERE f.user_id = s.user_id AND f.moderation_state = 'approved' AND f.csam_state = 'clear'),
                                '[]'::jsonb)) ORDER BY coalesce(s.awaiting_since, s.updated_at))
      FROM public.dating_verification_sessions AS s WHERE s.state = 'awaiting_review'), '[]'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION public.moderation_verification_decide(p_actor uuid, p_session uuid, p_outcome text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  v_user uuid;
  v jsonb;
BEGIN
  IF v_mod.user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  SELECT s.user_id INTO v_user FROM public.dating_verification_sessions AS s WHERE s.id = p_session;
  v := public.decide_dating_human_review(p_session, p_outcome, p_actor);
  IF (v ->> 'ok')::boolean THEN
    PERFORM private.dating_audit(p_actor, NULL, 'verification_decide', v_user,
                                 pg_catalog.jsonb_build_object('outcome', p_outcome));
  END IF;
  RETURN v;
END;
$$;

-- Countries (§6.4): the current rows; publishing is the safety owner's.
CREATE OR REPLACE FUNCTION public.moderation_countries(p_actor uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
BEGIN
  IF v_mod.user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'countries', coalesce((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('country', c.country_code, 'version', c.version, 'tier', c.tier,
             'dating_enabled', c.dating_enabled, 'same_gender_enabled', c.same_gender_enabled,
             'open_regions', to_jsonb(c.open_regions), 'published_at', c.published_at) ORDER BY c.country_code)
      FROM public.country_safety_config AS c WHERE c.is_current), '[]'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION public.moderation_publish_country(p_actor uuid, p_country text, p_values jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  v jsonb;
BEGIN
  IF v_mod.user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  IF v_mod.role <> 'safety_owner' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'safety_owner_only');
  END IF;
  v := public.publish_country_config(p_country, p_values);
  IF (v ->> 'ok')::boolean THEN
    PERFORM private.dating_audit(p_actor, NULL, 'publish_country', NULL,
                                 pg_catalog.jsonb_build_object('country', upper(p_country)));
  END IF;
  RETURN v;
END;
$$;

-- S1 W9b's review queue v0, through its own two RPCs only.
CREATE OR REPLACE FUNCTION public.moderation_opinions_queue(p_actor uuid, p_limit integer DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
BEGIN
  IF v_mod.user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  PERFORM private.dating_audit(p_actor, NULL, 'opinions_view', NULL);
  RETURN pg_catalog.jsonb_build_object('ok', true, 'reports',
    public.admin_list_priority_reports(greatest(1, least(coalesce(p_limit, 50), 200))));
END;
$$;

CREATE OR REPLACE FUNCTION public.moderation_opinions_remove(p_actor uuid, p_type text, p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
BEGIN
  IF v_mod.user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  IF p_type IS NULL OR p_type NOT IN ('opinion', 'comment') OR p_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  PERFORM public.admin_confirm_content_removal(p_type, p_id);
  PERFORM private.dating_audit(p_actor, NULL, 'opinions_remove', NULL, pg_catalog.jsonb_build_object('type', p_type));
  RETURN pg_catalog.jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.moderation_audit_log(p_actor uuid, p_limit integer DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
BEGIN
  IF v_mod.user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'actions', coalesce((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id', a.id, 'at', a.created_at, 'actor', a.actor_id,
             'mine', a.actor_id = p_actor, 'action', a.action, 'case_id', a.case_id, 'detail', a.detail)
           ORDER BY a.created_at DESC, a.id)
      FROM (SELECT x.* FROM public.dating_moderation_actions AS x
             ORDER BY x.created_at DESC, x.id LIMIT greatest(1, least(coalesce(p_limit, 100), 500))) AS a), '[]'::jsonb));
END;
$$;

-- ---------------------------------------------------------------------
-- 5. SLA alerts (§4.6, §6.5): every 15 minutes, for each priority with an
--    open case past its clock, one content-free line about the oldest
--    ("P0 case waiting 3 h 40 m"): no id, no name, no category.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.dating_moderation_sla_check(p_now timestamptz DEFAULT now())
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_hook constant text := public.app_setting('moderation_alert_webhook');
  r record;
  v_n integer := 0;
  v_mins integer;
BEGIN
  FOR r IN
    SELECT c.priority, min(c.created_at) AS oldest
      FROM public.dating_moderation_cases AS c
     WHERE c.state IN ('open', 'in_review') AND c.sla_due_at < p_now
     GROUP BY c.priority ORDER BY c.priority
  LOOP
    IF v_hook IS NULL THEN
      PERFORM private.bump_metric_internal('dating.sla.alert_unconfigured');
      CONTINUE;
    END IF;
    v_mins := greatest(0, floor(extract(epoch FROM p_now - r.oldest) / 60))::int;
    BEGIN
      PERFORM net.http_post(
        url := v_hook,
        headers := pg_catalog.jsonb_build_object('Content-Type', 'application/json'),
        body := pg_catalog.jsonb_build_object('text',
          r.priority || ' case waiting ' || (v_mins / 60) || ' h ' || (v_mins % 60) || ' m'));
      v_n := v_n + 1;
    EXCEPTION WHEN OTHERS THEN
      PERFORM private.bump_metric_internal('dating.sla.alert_failed');
    END;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('alerts', v_n);
END;
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname = 'cron') THEN
    PERFORM cron.unschedule(j.jobid) FROM cron.job AS j WHERE j.jobname = 'dating-moderation-sla';
    PERFORM cron.schedule('dating-moderation-sla', '*/15 * * * *', $c$SELECT public.dating_moderation_sla_check()$c$);
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- 6. Self-revoke (the W6 final pattern).
-- ---------------------------------------------------------------------
REVOKE ALL ON TABLE public.dating_moderators, public.dating_moderation_actions FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  private.dating_moderation_actions_guard(), private.dating_audit(uuid, uuid, text, uuid, jsonb),
  private.dating_moderator(uuid), private.dating_identity_of(uuid), private.dating_case_needs_sensitive_routing(uuid),
  private.dating_case_for(public.dating_moderators, uuid), private.dating_evidence_messages(uuid),
  private.dating_lift_case_holds(uuid),
  public.moderation_whoami(uuid), public.moderation_queue(uuid, integer), public.moderation_case(uuid, uuid),
  public.moderation_claim(uuid, uuid), public.moderation_dismiss(uuid, uuid), public.moderation_place_hold(uuid, uuid, text),
  public.moderation_lift_hold(uuid, uuid), public.moderation_restrict(uuid, uuid, text, timestamptz, text),
  public.moderation_ask_for_id(uuid, uuid), public.moderation_confirm_minor(uuid, uuid),
  public.moderation_note(uuid, uuid, text), public.moderation_decide_appeal(uuid, uuid, boolean),
  public.moderation_photos(uuid), public.moderation_photo_decide(uuid, uuid, boolean, text),
  public.moderation_verifications(uuid), public.moderation_verification_decide(uuid, uuid, text),
  public.moderation_countries(uuid), public.moderation_publish_country(uuid, text, jsonb),
  public.moderation_opinions_queue(uuid, integer), public.moderation_opinions_remove(uuid, text, uuid),
  public.moderation_audit_log(uuid, integer), public.dating_moderation_sla_check(timestamptz)
  FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
```

Create `supabase/migrations/20261121110010_dating_v2_moderation_console_grants.sql` with exactly:

```sql
-- Spec 2 W7b: grants for 20261121110000_dating_v2_moderation_console.sql. The
-- moderators and the audit are no API role's (the console's definer
-- functions read and write them); the moderation_* functions are the
-- service role's alone (the dating-moderation edge function calls them
-- with the moderator's id after checking the moderator's aal2 session); the
-- SLA check is the cron's; the helpers are the database's own.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON TABLE public.dating_moderators FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.dating_moderation_actions FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_moderation_actions_guard() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_audit(uuid, uuid, text, uuid, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_moderator(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_identity_of(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_case_needs_sensitive_routing(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_case_for(public.dating_moderators, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_evidence_messages(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_lift_case_holds(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_moderation_sla_check(timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.moderation_whoami(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_whoami(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_queue(uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_queue(uuid, integer) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_case(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_case(uuid, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_claim(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_claim(uuid, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_dismiss(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_dismiss(uuid, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_place_hold(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_place_hold(uuid, uuid, text) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_lift_hold(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_lift_hold(uuid, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_restrict(uuid, uuid, text, timestamptz, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_restrict(uuid, uuid, text, timestamptz, text) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_ask_for_id(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_ask_for_id(uuid, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_confirm_minor(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_confirm_minor(uuid, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_note(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_note(uuid, uuid, text) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_decide_appeal(uuid, uuid, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_decide_appeal(uuid, uuid, boolean) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_photos(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_photos(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_photo_decide(uuid, uuid, boolean, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_photo_decide(uuid, uuid, boolean, text) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_verifications(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_verifications(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_verification_decide(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_verification_decide(uuid, uuid, text) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_countries(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_countries(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_publish_country(uuid, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_publish_country(uuid, text, jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_opinions_queue(uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_opinions_queue(uuid, integer) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_opinions_remove(uuid, text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_opinions_remove(uuid, text, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_audit_log(uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_audit_log(uuid, integer) TO service_role;
COMMIT;
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
for f in supabase/migrations/20261121110000_dating_v2_moderation_console.sql supabase/migrations/20261121110010_dating_v2_moderation_console_grants.sql; do
  for run in 1 2; do psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $f > /dev/null 2> $D/apply_err.txt; rc=$?; echo "$(basename $f) run $run exit=$rc"; grep -v NOTICE $D/apply_err.txt || true; done
done
python3 -I $D/grants_line.py supabase/migrations/20261121100010_dating_v2_reports_grants.sql 'Spec 2 W7b: the moderation console (twin of 20261121110000)' supabase/migrations/20261121110010_dating_v2_moderation_console_grants.sql
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_moderation_contracts.sql 2>&1 | tail -1
```

Expected: four `exit=0` lines and nothing else printed for them; `local_pg_grants.sql: one \i block added`; `psql:supabase/tests/dating_v2_moderation_contracts.sql:1412: NOTICE:  dating_v2_moderation_contracts: all held`.

- [ ] **Step 3: The existing contracts meet the console**

Create `$D/edit_tests_T5.py` with exactly:

```python
#!/usr/bin/env python3
# Spec 2 W7b Task 5: the existing contracts meet the console. The canary
# takes the moderators and the audit (no API role's), the moderation_*
# functions (the service role's alone) and the helpers (the database's
# own); its decrypt scan allows the moderation_* functions, whose only
# ways to a decrypted value are the routing check (a boolean) and the
# evidence (messages), never naming the sensitive table or the decrypter
# themselves (a new check pins that). The service-role test lists the two
# tables; the verification contract's place_account_hold callers gain the
# console's confirm-a-minor (§6.3).
import importlib.util

spec = importlib.util.spec_from_file_location('anchor', '.superpowers/sdd/2026-11-21-spec2-w7/anchor.py')
anchor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(anchor)

FNS = ['moderation_whoami(uuid)', 'moderation_queue(uuid,integer)', 'moderation_case(uuid,uuid)',
       'moderation_claim(uuid,uuid)', 'moderation_dismiss(uuid,uuid)', 'moderation_place_hold(uuid,uuid,text)',
       'moderation_lift_hold(uuid,uuid)',
       'moderation_restrict(uuid,uuid,text,timestamp with time zone,text)', 'moderation_ask_for_id(uuid,uuid)',
       'moderation_confirm_minor(uuid,uuid)', 'moderation_note(uuid,uuid,text)',
       'moderation_decide_appeal(uuid,uuid,boolean)', 'moderation_photos(uuid)',
       'moderation_photo_decide(uuid,uuid,boolean,text)', 'moderation_verifications(uuid)',
       'moderation_verification_decide(uuid,uuid,text)', 'moderation_countries(uuid)',
       'moderation_publish_country(uuid,text,jsonb)', 'moderation_opinions_queue(uuid,integer)',
       'moderation_opinions_remove(uuid,text,uuid)', 'moderation_audit_log(uuid,integer)']
rows = ',\n'.join(f"  ('{f}', '', 'service_role')" for f in FNS)

anchor.edit('supabase/tests/dating_rls_canary.sql', [
    ("""-- ---------------------------------------------------------------------
-- Checks (every batch adds its rows above this line).
""", f"""-- Spec 2 W7b Task 5: the console. The moderators and the audit are no API
-- role's; the moderation_* functions are the service role's alone (the
-- dating-moderation edge function's); the rest is the database's own.
INSERT INTO allowed_rel (name, authenticated, service_dml) VALUES
  ('dating_moderators', '', ''),
  ('dating_moderation_actions', '', '');
INSERT INTO allowed_fn (sig, clients, service) VALUES
{rows},
  ('dating_moderation_sla_check(timestamp with time zone)', '', ''),
  ('private.dating_moderation_actions_guard()', '', ''),
  ('private.dating_audit(uuid,uuid,text,uuid,jsonb)', '', ''),
  ('private.dating_moderator(uuid)', '', ''),
  ('private.dating_identity_of(uuid)', '', ''),
  ('private.dating_case_needs_sensitive_routing(uuid)', '', ''),
  ('private.dating_case_for(dating_moderators,uuid)', '', ''),
  ('private.dating_evidence_messages(uuid)', '', ''),
  ('private.dating_lift_case_holds(uuid)', '', '');
-- @@W7C-CANARY@@

-- ---------------------------------------------------------------------
-- Checks (every batch adds its rows above this line).
"""),
    ("""   WHERE d.name NOT IN ('dating_field_decrypt', 'dating_export_for_job', 'publish_country_config')
     AND has_function_privilege('service_role', d.oid, 'EXECUTE');""",
     """   WHERE d.name NOT IN ('dating_field_decrypt', 'dating_export_for_job', 'publish_country_config')
     -- Spec 2 W7b (§6.4, S-5): the console's functions; pinned below.
     AND d.name NOT LIKE 'moderation\\_%'
     AND has_function_privilege('service_role', d.oid, 'EXECUTE');"""),
    ("""  SELECT string_agg(c.table_name || '.' || c.column_name, ', ') INTO v_bad
    FROM information_schema.columns AS c
   WHERE c.table_schema = 'public' AND c.column_name LIKE '%routing%'""",
     """  -- Spec 2 W7b (§6.4, S-5): a moderation_* function never names the
  -- decrypter or the sensitive table itself; it reaches a decrypted value
  -- only through the routing check (a boolean) or the evidence (messages).
  SELECT string_agg(p.oid::regprocedure::text, ', ') INTO v_bad
    FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname LIKE 'moderation\\_%'
     AND (p.prosrc ~ '(dating_field_decrypt|dating_profile_sensitive|dating_identity_of)'
          OR (p.prosrc ~ 'private\\.dating_\\w+_decrypt'));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a console function reads a sensitive value directly: %', v_bad;
  END IF;
  IF pg_get_function_result('private.dating_case_needs_sensitive_routing(uuid)'::regprocedure) <> 'boolean' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the routing check answers more than true or false';
  END IF;
  SELECT string_agg(c.table_name || '.' || c.column_name, ', ') INTO v_bad
    FROM information_schema.columns AS c
   WHERE c.table_schema = 'public' AND c.column_name LIKE '%routing%'"""),
], 'W7b Task 5')

for old in ("""                          'dating_report_evidence', 'dating_case_matches', 'dating_appeals')
    AND NOT has_table_privilege('service_role', c.oid, 'SELECT');""",
            """                          'dating_report_evidence', 'dating_case_matches', 'dating_appeals')
    -- Spec 2 W1b (batch-4 fix round 1, C-1): the service role only reads"""):
    new = old.replace("""                          'dating_report_evidence', 'dating_case_matches', 'dating_appeals')""",
                      """                          'dating_report_evidence', 'dating_case_matches', 'dating_appeals',
                          -- Spec 2 W7b: the moderators and the audit; the console's
                          -- functions read and write them.
                          'dating_moderators', 'dating_moderation_actions')""")
    anchor.edit('supabase/tests/service_role_grants_test.sql', [(old, new)], 'W7b Task 5')

anchor.edit('supabase/tests/dating_v2_verification_contracts.sql', [(
    """  IF v_got IS DISTINCT FROM 'consume_fresh_start(text,text), correct_my_birth_date(date), private.handle_csam_match(text,text,uuid,text,text,boolean,text), record_dating_age_far_below(uuid,uuid,text), set_my_birth_date(date)' THEN""",
    """  -- Spec 2 W7b (§6.3): a moderator confirming a minor is the other Dating caller.
  IF v_got IS DISTINCT FROM 'consume_fresh_start(text,text), correct_my_birth_date(date), moderation_confirm_minor(uuid,uuid), private.handle_csam_match(text,text,uuid,text,text,boolean,text), record_dating_age_far_below(uuid,uuid,text), set_my_birth_date(date)' THEN""")],
    'W7b Task 5')

# The setup contract pins every function that reads Dating photos: the
# console's case, photo queue, photo decision and verification reads join
# it (the service role's; they return storage keys only to the edge
# function, which signs them for 60 seconds).
anchor.edit('supabase/tests/dating_v2_setup_contracts.sql', [
    ("""  -- Spec 2 W5b photo keys for dating-photo-urls (the service role's: the
  -- Spec 2 W5b phone first, never before mutual interest when chosen).
""", """  -- Spec 2 W5b photo keys for dating-photo-urls (the service role's: the
  -- Spec 2 W5b phone first, never before mutual interest when chosen).
  -- Spec 2 W7b: the console's case, photo queue, photo decision and
  -- Spec 2 W7b verification reads (the service role's: keys only to the
  -- Spec 2 W7b dating-moderation edge function, which signs them).
"""),
    ("""public.list_dating_profile_photos():authenticated; public.prepare_account_deletion(uuid):service_role;""",
     """public.list_dating_profile_photos():authenticated; public.moderation_case(uuid, uuid):service_role; public.moderation_photo_decide(uuid, uuid, boolean, text):service_role; public.moderation_photos(uuid):service_role; public.moderation_verifications(uuid):service_role; public.prepare_account_deletion(uuid):service_role;"""),
], 'W7b Task 5')
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
python3 -I $D/edit_tests_T5.py
$D/suite.sh attune_spec3a > $D/sql-after-T5.txt; echo "$(grep -c '^PASS' $D/sql-after-T5.txt) PASS, $(grep -c '^FAIL' $D/sql-after-T5.txt) FAIL"
diff <(grep FAIL $D/sql-baseline.txt) <(grep FAIL $D/sql-after-T5.txt)
```

Expected: the five edit lines (`dating_rls_canary.sql: 3 edit(s) (W7b Task 5)`, `service_role_grants_test.sql: 1 edit(s) (W7b Task 5)` twice, `dating_v2_verification_contracts.sql: 1 edit(s)`, `dating_v2_setup_contracts.sql: 2 edit(s)`); `162 PASS, 14 FAIL`; no diff.

- [ ] **Step 4: The mutants (§7.5 mutant 26; S-5)**

Create `$D/mut_T5.py` with exactly:

```python
# Spec 2 W7b Task 5 mutants (mutate.py on 20261121110000_dating_v2_moderation_console.sql):
# each must make dating_v2_moderation_contracts.sql fail with a CONTRACT VIOLATED line.
MUTS = {
    # §7.5 mutant 26: the queue shows a not-man-woman case to a reviewer without routing.
    'm26_queue_shows_routed': ("               AND (v_mod.sensitive_routing_allowed OR NOT private.dating_case_needs_sensitive_routing(x.id))",
                               "               AND true"),
    'open_ignores_routing': ("     AND (p_mod.sensitive_routing_allowed OR NOT private.dating_case_needs_sensitive_routing(c.id));",
                             "     AND true;"),
    'unreadable_not_routed': ("  IF v_target IS NULL OR v_target NOT IN ('woman', 'man') THEN\n    RETURN true;",
                              "  IF false THEN\n    RETURN true;"),
    'pair_not_judged': ("    IF NOT private.dating_pair_is_man_woman(v_target, private.dating_identity_of(v_other)) THEN",
                        "    IF false THEN"),
    'audit_update_allowed': ("  RAISE EXCEPTION 'audit:append_only' USING ERRCODE = '42501';",
                             "  RETURN CASE WHEN TG_OP = 'UPDATE' THEN NEW ELSE OLD END;"),
    'audit_blocks_fk_set_null': ("  IF TG_OP = 'UPDATE' AND NEW.id = OLD.id AND NEW.actor_id = OLD.actor_id AND NEW.action = OLD.action",
                                 "  IF false AND NEW.id = OLD.id AND NEW.actor_id = OLD.actor_id AND NEW.action = OLD.action"),
    'audit_young_purgeable': ("     AND OLD.created_at < now() - interval '2 years' THEN", "     THEN"),
    'inactive_moderator_answered': ("  SELECT m.* FROM public.dating_moderators AS m WHERE m.user_id = p_actor AND m.active;",
                                    "  SELECT m.* FROM public.dating_moderators AS m WHERE m.user_id = p_actor;"),
    'case_names_reporter': ("                           'reporter_triggered', r.reporter_tripped_family,",
                            "                           'reporter_triggered', r.reporter_tripped_family, 'by', r.reporter_user_id,"),
    'open_unaudited': ("  PERFORM private.dating_audit(p_actor, c.id, 'open_case', c.target_user_id);", "  NULL;"),
    'dismiss_keeps_holds': ("    PERFORM private.dating_lift_case_holds(c.id);\n    PERFORM private.dating_audit(p_actor, c.id, 'dismiss', c.target_user_id);",
                            "    PERFORM private.dating_audit(p_actor, c.id, 'dismiss', c.target_user_id);"),
    'restrict_case_left_open': ("  PERFORM private.dating_close_case(c.id, p_actor, 'restricted');\n  PERFORM private.dating_audit(p_actor, c.id, 'restrict', c.target_user_id,",
                                "  PERFORM private.dating_audit(p_actor, c.id, 'restrict', c.target_user_id,"),
    'publish_by_anyone': ("  IF v_mod.role <> 'safety_owner' THEN\n    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'safety_owner_only');",
                          "  IF false THEN\n    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'safety_owner_only');"),
    'minor_on_any_case': ("     OR NOT EXISTS (SELECT 1 FROM public.dating_reports AS r WHERE r.case_id = c.id AND r.category = 'underage_risk') THEN",
                          "     THEN"),
    'claim_unaudited': ("  PERFORM private.dating_audit(p_actor, c.id, 'claim', c.target_user_id);", "  NULL;"),
    'lift_ignores_age_check': ("   WHERE r.user_id = c.target_user_id AND r.restriction_type IN ('moderation_hold', 'age_review') AND r.lifted_at IS NULL",
                               "   WHERE r.user_id = c.target_user_id AND r.restriction_type = 'moderation_hold' AND r.lifted_at IS NULL"),
    'sla_body_names_priority_count': ("          r.priority || ' case waiting ' || (v_mins / 60) || ' h ' || (v_mins % 60) || ' m'));",
                                      "          r.priority || ' case waiting ' || (v_mins / 60) || ' h ' || (v_mins % 60) || ' m', 'oldest', r.oldest));"),
    'sla_unconfigured_uncounted': ("      PERFORM private.bump_metric_internal('dating.sla.alert_unconfigured');", "      NULL;"),
    'sla_failure_uncounted': ("      PERFORM private.bump_metric_internal('dating.sla.alert_failed');", "      NULL;"),
    'sla_no_cron': ("    PERFORM cron.schedule('dating-moderation-sla', '*/15 * * * *', $c$SELECT public.dating_moderation_sla_check()$c$);",
                    "    NULL;"),
}
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
python3 -I $D/mutate.py supabase/migrations/20261121110000_dating_v2_moderation_console.sql supabase/tests/dating_v2_moderation_contracts.sql $D/mut_T5.py $D/mut supabase/migrations/20261121110010_dating_v2_moderation_console_grants.sql > $D/mut_T5.txt 2>&1
grep -c 'CONTRACT VIOLATED' $D/mut_T5.txt; grep -v 'CONTRACT VIOLATED' $D/mut_T5.txt
```

Expected: `20`, and nothing else printed. Among them: `m26_queue_shows_routed: ERROR:  CONTRACT VIOLATED: …`, `open_ignores_routing: …`, `unreadable_not_routed: …`, `claim_unaudited: …`, `audit_blocks_fk_set_null: …`, `lift_ignores_age_check: …`.

- [ ] **Step 5: Record the tree**

Do not commit; record the tree in the report.

### Task 6: The `dating-moderation` edge function: aal2, the moderator's id from the token, one function per action, signed photo URLs, CORS for the console's origin only (§4.7, §6.4; F-6; R-59)

**Files:**
- Create: `supabase/functions/dating-moderation/{handler.ts, request.ts, index.ts, handler.test.ts}`, `$D/{edit_ci_T6.py, mut_T6.py}`
- Modify: `.github/workflows/tests.yml` (the Deno test and check lines), `supabase/config.toml` (`[functions.dating-moderation] verify_jwt = false`)

**Interfaces:**
- Consumes: Task 5's `moderation_*` functions (service role); `_shared/attune_auth.ts` (`requireUser`, `serviceRoleClient`, `HttpError`), `_shared/error_code.ts`; the `dating-photos` bucket (W3).
- Produces: `ACTIONS` (action → function and its arguments), `handleModeration(body, {userId, aal}, deps)`, `aalOf(token)`; the secret `DATING_CONSOLE_ORIGIN` (Owner checklist 4).

- [ ] **Step 1: Write the failing tests**

Create `supabase/functions/dating-moderation/handler.test.ts` with exactly (Task 9 adds W7c's actions):

```typescript
// Spec 2 W7b (§4.7, §6.4, §7.3): dating-moderation. Refuses without aal2
// (TOTP) before any call, and an unknown action or bad input before any
// call; calls exactly one moderation_* function with the signed-in
// moderator's id (an actor in the body is ignored); passes the database's
// not_moderator through; storage keys never leave (signed for 60 seconds,
// a key that fails to sign is url null); a server's text or an error is
// never answered (busy); the wiring: no-store, CORS only for the console's
// origin, an unauthorised caller is unauthorized, only an error's code is
// logged.
import { aalOf, ACTIONS, handleModeration, type ModerationDeps, PHOTO_BUCKET, REVIEW_BUCKET } from "./handler.ts";
import { handleRequest, type ModerationClient } from "./request.ts";
import { HttpError } from "../_shared/attune_auth.ts";

function eq(actual: unknown, expected: unknown, why = "") {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${why} expected ${e}, got ${a}`);
}

const ME = "99999999-2222-4333-8444-555555555555";
const CASE = "11111111-2222-4333-8444-555555555555";
const MOD = { userId: ME, aal: "aal2" };

interface Seen {
  rpc: Array<[string, Record<string, unknown>]>;
  signed: Array<[string, string[], number]>;
}

function deps(data: unknown, seen: Seen, opts: { error?: boolean; rejects?: boolean; signThrows?: boolean } = {}): ModerationDeps {
  return {
    rpc: (fn, args) => {
      seen.rpc.push([fn, args]);
      if (opts.rejects) return Promise.reject(new Error("server text: connection reset"));
      return Promise.resolve(opts.error ? { data: null, error: { message: "secret detail" } } : { data, error: null });
    },
    sign: (bucket, keys, seconds) => {
      seen.signed.push([bucket, keys, seconds]);
      if (opts.signThrows) return Promise.reject(new Error("storage down"));
      return Promise.resolve(keys.map((k) => ({ path: k, signedUrl: k === "bad" ? null : `https://s.test/${bucket}/${k}?t` })));
    },
  };
}

const fresh = (): Seen => ({ rpc: [], signed: [] });

Deno.test("no aal2, no call: TOTP is needed for every action", async () => {
  for (const aal of ["aal1", null]) {
    const seen = fresh();
    eq(await handleModeration({ action: "queue" }, { userId: ME, aal }, deps({ ok: true }, seen)), {
      ok: false,
      reason: "mfa_required",
    });
    eq(seen.rpc.length, 0);
  }
});

Deno.test("an unknown action or bad input is invalid, before any call", async () => {
  const seen = fresh();
  for (const body of [
    {},
    { action: "drop_table" },
    { action: "toString" },
    { action: "case", case_id: "x" },
    { action: "hold", case_id: CASE, category: "safety_concern" },
    { action: "restrict", case_id: CASE, type: "banned", category: "spam" },
    { action: "restrict", case_id: CASE, type: "suspended", category: "spam", ends_at: "soon" },
    { action: "note", case_id: CASE, note: "x".repeat(1001) },
    { action: "decide_appeal", case_id: CASE, accept: "yes" },
    { action: "verification_decide", session_id: CASE, outcome: "maybe" },
    { action: "publish_country", country: "gh", values: {} },
    { action: "opinions_remove", type: "forum_post", id: CASE },
  ]) {
    eq(await handleModeration(body, MOD, deps({ ok: true }, seen)), { ok: false, reason: "invalid" }, JSON.stringify(body));
  }
  eq(seen.rpc.length, 0);
});

Deno.test("one function per action, as the signed-in moderator (a body actor is ignored)", async () => {
  const seen = fresh();
  await handleModeration({ action: "restrict", case_id: CASE.toUpperCase(), type: "suspended", category: "threats",
    ends_at: "2026-12-05T10:00:00Z", p_actor: "someone-else" }, MOD, deps({ ok: true }, seen));
  eq(seen.rpc, [["moderation_restrict", {
    p_actor: ME,
    p_case: CASE,
    p_type: "suspended",
    p_ends_at: "2026-12-05T10:00:00.000Z",
    p_category: "threats",
  }]]);
  const expected: Record<string, string> = {
    whoami: "moderation_whoami", queue: "moderation_queue", case: "moderation_case", claim: "moderation_claim",
    dismiss: "moderation_dismiss", hold: "moderation_place_hold", lift_hold: "moderation_lift_hold",
    restrict: "moderation_restrict", ask_for_id: "moderation_ask_for_id", confirm_minor: "moderation_confirm_minor",
    note: "moderation_note", decide_appeal: "moderation_decide_appeal", photos: "moderation_photos",
    photo_decide: "moderation_photo_decide", verifications: "moderation_verifications",
    verification_decide: "moderation_verification_decide", countries: "moderation_countries",
    publish_country: "moderation_publish_country", opinions_queue: "moderation_opinions_queue",
    opinions_remove: "moderation_opinions_remove", audit: "moderation_audit_log",
  };
  for (const [action, fn] of Object.entries(expected)) eq(ACTIONS[action]?.fn, fn, action);
});

Deno.test("the database's refusals pass through as fixed codes; anything else is busy", async () => {
  eq(await handleModeration({ action: "queue" }, MOD, deps({ ok: false, reason: "not_moderator" }, fresh())), {
    ok: false,
    reason: "not_moderator",
  });
  eq(await handleModeration({ action: "queue" }, MOD, deps({ ok: false, reason: "Kofi is restricted" }, fresh())), {
    ok: false,
    reason: "busy",
  });
  eq(await handleModeration({ action: "queue" }, MOD, deps(null, fresh(), { error: true })), { ok: false, reason: "busy" });
  eq(await handleModeration({ action: "queue" }, MOD, deps(null, fresh(), { rejects: true })), { ok: false, reason: "busy" });
});

Deno.test("a case's photos, the photo queue and a verification are signed for 60 s; no key leaves", async () => {
  const seen = fresh();
  const a = await handleModeration({ action: "case", case_id: CASE }, MOD, deps({
    ok: true,
    case: { id: CASE },
    profile: { display_name: "Kofi", photos: [{ position: 1, key: "u/1.jpg" }, { position: 2, key: "bad" }] },
  }, seen));
  eq((a as Record<string, unknown>).profile, {
    display_name: "Kofi",
    photos: [{ position: 1, url: `https://s.test/${PHOTO_BUCKET}/u/1.jpg?t` }, { position: 2, url: null }],
  });
  const v = await handleModeration({ action: "verifications" }, MOD, deps({
    ok: true,
    sessions: [{ id: "s1", photos: [{ position: 1, key: "u/1.jpg" }], review_paths: ["s1/1.jpg", "s1/2.jpg"] }],
  }, seen));
  eq((v as Record<string, unknown>).sessions, [{
    id: "s1",
    photos: [{ position: 1, url: `https://s.test/${PHOTO_BUCKET}/u/1.jpg?t` }],
    review: [`https://s.test/${REVIEW_BUCKET}/s1/1.jpg?t`, `https://s.test/${REVIEW_BUCKET}/s1/2.jpg?t`],
  }]);
  const p = await handleModeration({ action: "photos" }, MOD, deps({ ok: true, photos: [{ id: "f1", key: "u/3.jpg" }] }, seen));
  eq((p as Record<string, unknown>).photos, [{ id: "f1", url: `https://s.test/${PHOTO_BUCKET}/u/3.jpg?t` }]);
  for (const [, , seconds] of seen.signed) eq(seconds, 60);
  for (const answer of [a, v, p]) {
    if (/"key"|review_paths|u\/1\.jpg"/.test(JSON.stringify(answer))) throw new Error("a storage key left the function");
  }
  const failed = await handleModeration({ action: "photos" }, MOD, deps({ ok: true, photos: [{ id: "f1", key: "k" }] }, fresh(), {
    signThrows: true,
  }));
  eq((failed as Record<string, unknown>).photos, [{ id: "f1", url: null }]);
});

Deno.test("aalOf reads the token's aal claim, and nothing else", () => {
  const enc = (o: unknown) => btoa(JSON.stringify(o)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
  eq(aalOf(`h.${enc({ sub: ME, aal: "aal2" })}.s`), "aal2");
  eq(aalOf(`h.${enc({ sub: ME })}.s`), null);
  eq(aalOf("garbage"), null);
  eq(aalOf("h.!!!.s"), null);
});

function client(data: unknown, seen: Seen): ModerationClient {
  return {
    rpc: (fn, args) => {
      seen.rpc.push([fn, args]);
      return Promise.resolve({ data, error: null });
    },
    storage: { from: () => ({ createSignedUrls: () => Promise.resolve({ data: [], error: null }) }) },
  };
}

Deno.test("the wiring: no-store, CORS only for the console's origin, unauthorized, codes only in logs", async () => {
  const aal2 = `h.${btoa(JSON.stringify({ aal: "aal2" }))}.s`;
  const post = (origin: string) =>
    new Request("https://f.test/dating-moderation", {
      method: "POST",
      headers: { Authorization: `Bearer ${aal2}`, Origin: origin, "Content-Type": "application/json" },
      body: JSON.stringify({ action: "whoami" }),
    });
  const seen = fresh();
  const wiring = { requireUser: () => Promise.resolve({ id: ME }), client: () => client({ ok: true, role: "moderator" }, seen),
    origin: "https://console.test" };
  const ok = await handleRequest(post("https://console.test"), wiring);
  eq(ok.headers.get("Cache-Control"), "no-store");
  eq(ok.headers.get("Access-Control-Allow-Origin"), "https://console.test");
  eq(await ok.json(), { ok: true, role: "moderator" });
  eq(seen.rpc, [["moderation_whoami", { p_actor: ME }]]);
  const other = await handleRequest(post("https://evil.test"), wiring);
  eq(other.headers.get("Access-Control-Allow-Origin"), null);
  const none = await handleRequest(post("https://console.test"), { ...wiring, origin: null });
  eq(none.headers.get("Access-Control-Allow-Origin"), null);
  const unauth = await handleRequest(post("https://console.test"), {
    ...wiring,
    requireUser: () => Promise.reject(new HttpError("Invalid authorization token", 401)),
  });
  eq(unauth.status, 401);
  eq(await unauth.json(), { ok: false, reason: "unauthorized" });
  const logged: unknown[][] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => logged.push(args);
  try {
    const broken = await handleRequest(post("https://console.test"), {
      ...wiring,
      client: () => {
        throw Object.assign(new Error("phone +233244000000 leaked"), { code: "PGRST301" });
      },
    });
    eq(broken.status, 500);
    eq(await broken.json(), { ok: false, reason: "busy" });
  } finally {
    console.error = original;
  }
  eq(logged, [["dating-moderation failed:", "PGRST301"]]);
  eq((await handleRequest(new Request("https://f.test/x", { method: "GET" }), wiring)).status, 405);
});
```

```bash
(cd supabase/functions && deno test --allow-read --frozen dating-moderation/handler.test.ts 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -m1 -oE "Cannot find module '[^']*'" | sed "s#'file://.*/supabase/functions/#'#")
```

Expected: `Cannot find module 'dating-moderation/handler.ts'`.

- [ ] **Step 2: The function**

Create `supabase/functions/dating-moderation/handler.ts` with exactly (Task 9 adds W7c's actions):

```typescript
// supabase/functions/dating-moderation/handler.ts
// Spec 2 W7b (§4.7, §6.4, §7.3; S-5): the console's API. One POST body
// {action, ...}; each action is one moderation_* service function, called
// with the signed-in moderator's id (never one from the body). Every call
// needs a session at aal2 (TOTP); the database refuses anyone who is not an
// active moderator (not_moderator) and writes every action to the audit.
// Storage keys never leave: a case's photos, the photo queue's and a
// verification's photos are signed here for 60 seconds and only the URLs
// are answered. A refusal is a fixed code; a server's text or an error is
// never answered and nothing but an error's code is logged.
export type RpcResult = { data: unknown; error: unknown };

export interface ModerationDeps {
  rpc(fn: string, args: Record<string, unknown>): PromiseLike<RpcResult>;
  /// Signs [keys] in [bucket] for [seconds]; throws when Storage can't.
  sign(bucket: string, keys: string[], seconds: number): Promise<Array<{ path: string | null; signedUrl: string | null }>>;
  rpcTimeoutMs?: number;
}

export interface Caller {
  userId: string;
  /// The session's authenticator assurance level ('aal1', 'aal2').
  aal: string | null;
}

export type Answer = { ok: true; [key: string]: unknown } | { ok: false; reason: string };

export const SIGNED_URL_SECONDS = 60;
export const RPC_TIMEOUT_MS = 10_000;
export const PHOTO_BUCKET = "dating-profile-photos";
export const REVIEW_BUCKET = "dating-verification-review";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const CATEGORIES = new Set([
  "underage_risk", "csam", "child_safety", "threat_to_life", "sextortion", "romance_scam", "threats", "entrapment",
  "harassment", "explicit_content", "impersonation", "hiding_relationship", "spam", "other",
]);
/// The fixed codes the console may read; anything else is busy.
export const REASONS: ReadonlySet<string> = new Set([
  "invalid", "not_moderator", "case_unavailable", "same_decider", "appeal_unavailable", "photo_unavailable",
  "session_unavailable", "safety_owner_only", "mfa_required", "busy",
]);

type Body = Record<string, unknown>;
const id = (v: unknown): string | null => (typeof v === "string" && UUID.test(v.toLowerCase()) ? v.toLowerCase() : null);
const text = (v: unknown, max: number): string | null =>
  typeof v === "string" && v.trim().length > 0 && v.length <= max ? v : null;
const limit = (v: unknown, def: number, max: number): number =>
  typeof v === "number" && Number.isInteger(v) && v >= 1 && v <= max ? v : def;

/// Each action: its function and its arguments (null: invalid input).
export const ACTIONS: Record<string, { fn: string; args: (b: Body) => Record<string, unknown> | null }> = {
  whoami: { fn: "moderation_whoami", args: () => ({}) },
  queue: { fn: "moderation_queue", args: (b) => ({ p_limit: limit(b.limit, 50, 200) }) },
  case: { fn: "moderation_case", args: (b) => (id(b.case_id) ? { p_case: id(b.case_id) } : null) },
  claim: { fn: "moderation_claim", args: (b) => (id(b.case_id) ? { p_case: id(b.case_id) } : null) },
  dismiss: { fn: "moderation_dismiss", args: (b) => (id(b.case_id) ? { p_case: id(b.case_id) } : null) },
  hold: {
    fn: "moderation_place_hold",
    args: (b) =>
      id(b.case_id) && typeof b.category === "string" && CATEGORIES.has(b.category)
        ? { p_case: id(b.case_id), p_category: b.category }
        : null,
  },
  lift_hold: { fn: "moderation_lift_hold", args: (b) => (id(b.case_id) ? { p_case: id(b.case_id) } : null) },
  restrict: {
    fn: "moderation_restrict",
    args: (b) => {
      const endsAt = b.ends_at === null || b.ends_at === undefined
        ? null
        : typeof b.ends_at === "string" && !Number.isNaN(Date.parse(b.ends_at))
        ? new Date(b.ends_at).toISOString()
        : undefined;
      return id(b.case_id) && (b.type === "suspended" || b.type === "under_review") && endsAt !== undefined &&
          typeof b.category === "string" && CATEGORIES.has(b.category)
        ? { p_case: id(b.case_id), p_type: b.type, p_ends_at: endsAt, p_category: b.category }
        : null;
    },
  },
  ask_for_id: { fn: "moderation_ask_for_id", args: (b) => (id(b.case_id) ? { p_case: id(b.case_id) } : null) },
  confirm_minor: { fn: "moderation_confirm_minor", args: (b) => (id(b.case_id) ? { p_case: id(b.case_id) } : null) },
  note: {
    fn: "moderation_note",
    args: (b) => (id(b.case_id) && text(b.note, 1000) ? { p_case: id(b.case_id), p_note: b.note } : null),
  },
  decide_appeal: {
    fn: "moderation_decide_appeal",
    args: (b) => (id(b.case_id) && typeof b.accept === "boolean" ? { p_case: id(b.case_id), p_accept: b.accept } : null),
  },
  photos: { fn: "moderation_photos", args: () => ({}) },
  photo_decide: {
    fn: "moderation_photo_decide",
    args: (b) =>
      id(b.photo_id) && typeof b.approve === "boolean"
        ? { p_photo: id(b.photo_id), p_approve: b.approve, p_reason: typeof b.reason === "string" ? b.reason : null }
        : null,
  },
  verifications: { fn: "moderation_verifications", args: () => ({}) },
  verification_decide: {
    fn: "moderation_verification_decide",
    args: (b) =>
      id(b.session_id) && (b.outcome === "pass" || b.outcome === "fail" || b.outcome === "ask_for_id")
        ? { p_session: id(b.session_id), p_outcome: b.outcome }
        : null,
  },
  countries: { fn: "moderation_countries", args: () => ({}) },
  publish_country: {
    fn: "moderation_publish_country",
    args: (b) =>
      typeof b.country === "string" && /^[A-Z]{2}$/.test(b.country) && b.values !== null && typeof b.values === "object" &&
        !Array.isArray(b.values)
        ? { p_country: b.country, p_values: b.values }
        : null,
  },
  opinions_queue: { fn: "moderation_opinions_queue", args: (b) => ({ p_limit: limit(b.limit, 50, 200) }) },
  opinions_remove: {
    fn: "moderation_opinions_remove",
    args: (b) => ((b.type === "opinion" || b.type === "comment") && id(b.id) ? { p_type: b.type, p_id: id(b.id) } : null),
  },
  audit: { fn: "moderation_audit_log", args: (b) => ({ p_limit: limit(b.limit, 100, 500) }) },
};

function withTimeout<T>(p: PromiseLike<T>, ms: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const late = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error("timeout")), ms);
  });
  return Promise.race([Promise.resolve(p), late]).finally(() => clearTimeout(timer));
}

type Photo = { key?: unknown; url?: string | null; [k: string]: unknown };

/// Replaces every {key} in [photos] with {url} signed in [bucket]; a key
/// that fails to sign gets url null. Keys never stay in the answer.
async function signAll(photos: Photo[], bucket: string, deps: ModerationDeps): Promise<Photo[]> {
  const keys = photos.map((p) => (typeof p.key === "string" ? p.key : null)).filter((k): k is string => k !== null);
  let signed: Array<{ path: string | null; signedUrl: string | null }> = [];
  if (keys.length > 0) {
    try {
      signed = await deps.sign(bucket, keys, SIGNED_URL_SECONDS);
    } catch {
      signed = [];
    }
  }
  const byKey = new Map(signed.filter((s) => s.path !== null).map((s) => [s.path as string, s.signedUrl]));
  return photos.map(({ key, ...rest }) => ({ ...rest, url: typeof key === "string" ? byKey.get(key) ?? null : null }));
}

async function signPaths(paths: unknown, deps: ModerationDeps): Promise<Array<string | null>> {
  const list = Array.isArray(paths) ? paths.filter((p): p is string => typeof p === "string") : [];
  if (list.length === 0) return [];
  try {
    const signed = await deps.sign(REVIEW_BUCKET, list, SIGNED_URL_SECONDS);
    const byPath = new Map(signed.filter((s) => s.path !== null).map((s) => [s.path as string, s.signedUrl]));
    return list.map((p) => byPath.get(p) ?? null);
  } catch {
    return list.map(() => null);
  }
}

/// Signs what [action]'s answer carries as storage keys.
async function signed(action: string, data: Record<string, unknown>, deps: ModerationDeps): Promise<Record<string, unknown>> {
  if (action === "case" && data.profile && typeof data.profile === "object") {
    const profile = data.profile as Record<string, unknown>;
    return {
      ...data,
      profile: { ...profile, photos: await signAll(Array.isArray(profile.photos) ? profile.photos : [], PHOTO_BUCKET, deps) },
    };
  }
  if (action === "photos" && Array.isArray(data.photos)) {
    return { ...data, photos: await signAll(data.photos, PHOTO_BUCKET, deps) };
  }
  if (action === "verifications" && Array.isArray(data.sessions)) {
    const sessions = [];
    for (const s of data.sessions as Array<Record<string, unknown>>) {
      const { review_paths, ...rest } = s;
      sessions.push({
        ...rest,
        photos: await signAll(Array.isArray(s.photos) ? s.photos : [], PHOTO_BUCKET, deps),
        review: await signPaths(review_paths, deps),
      });
    }
    return { ...data, sessions };
  }
  return data;
}

export async function handleModeration(body: unknown, caller: Caller, deps: ModerationDeps): Promise<Answer> {
  const b = (body && typeof body === "object" && !Array.isArray(body) ? body : {}) as Body;
  const action = typeof b.action === "string" ? b.action : "";
  const entry = Object.prototype.hasOwnProperty.call(ACTIONS, action) ? ACTIONS[action] : undefined;
  if (!entry) return { ok: false, reason: "invalid" };
  // §6.4: TOTP for every call, read or write.
  if (caller.aal !== "aal2") return { ok: false, reason: "mfa_required" };
  const args = entry.args(b);
  if (args === null) return { ok: false, reason: "invalid" };
  let res: RpcResult;
  try {
    res = await withTimeout(deps.rpc(entry.fn, { p_actor: caller.userId, ...args }), deps.rpcTimeoutMs ?? RPC_TIMEOUT_MS);
  } catch {
    return { ok: false, reason: "busy" };
  }
  if (res.error || !res.data || typeof res.data !== "object" || Array.isArray(res.data)) {
    return { ok: false, reason: "busy" };
  }
  const data = res.data as Record<string, unknown>;
  if (data.ok !== true) {
    const reason = typeof data.reason === "string" && REASONS.has(data.reason) ? data.reason : "busy";
    return { ok: false, reason };
  }
  return { ...(await signed(action, data, deps)), ok: true };
}

/// The session's assurance level from a JWT's payload ('aal' claim); null
/// when it can't be read. The token itself is checked by Auth first.
export function aalOf(token: string): string | null {
  const part = token.split(".")[1];
  if (!part) return null;
  try {
    const json = atob(part.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(part.length / 4) * 4, "="));
    const aal = (JSON.parse(json) as { aal?: unknown }).aal;
    return typeof aal === "string" ? aal : null;
  } catch {
    return null;
  }
}
```

Create `supabase/functions/dating-moderation/request.ts` with exactly:

```typescript
// supabase/functions/dating-moderation/request.ts
// Spec 2 W7b (§6.4): the HTTP wiring for handler.ts, kept out of index.ts so
// a test drives it with the user check, the service client and the
// console's origin injected. The caller is the signed-in moderator (their
// JWT, checked by Auth); the session's aal comes from that token. Only the
// console's own origin (the DATING_CONSOLE_ORIGIN secret) gets CORS
// headers; with none set, no browser origin is allowed. Every answer is
// no-store. Only an error's code is ever logged.
import { HttpError } from "../_shared/attune_auth.ts";
import { errorCode } from "../_shared/error_code.ts";
import { aalOf, handleModeration, type RpcResult } from "./handler.ts";

/// The slice of the service-role client this function uses.
export interface ModerationClient {
  rpc(fn: string, args: Record<string, unknown>): PromiseLike<RpcResult>;
  storage: {
    from(bucket: string): {
      createSignedUrls(keys: string[], seconds: number): Promise<{
        data: Array<{ path: string | null; signedUrl: string | null }> | null;
        error: unknown;
      }>;
    };
  };
}

export interface Wiring {
  requireUser(req: Request): Promise<{ id: string }>;
  client(): ModerationClient;
  origin: string | null;
}

function headers(req: Request, origin: string | null): Record<string, string> {
  const h: Record<string, string> = { "Content-Type": "application/json", "Cache-Control": "no-store" };
  if (origin !== null && req.headers.get("Origin") === origin) {
    h["Access-Control-Allow-Origin"] = origin;
    h["Access-Control-Allow-Headers"] = "authorization, content-type, apikey, x-client-info";
    h["Access-Control-Allow-Methods"] = "POST, OPTIONS";
    h["Vary"] = "Origin";
  }
  return h;
}

export async function handleRequest(req: Request, wiring: Wiring): Promise<Response> {
  const answer = (body: Record<string, unknown>, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: headers(req, wiring.origin) });
  if (req.method === "OPTIONS") return answer({ ok: true });
  if (req.method !== "POST") return answer({ ok: false, reason: "invalid" }, 405);
  try {
    const user = await wiring.requireUser(req);
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
    const supabase = wiring.client();
    const body = await req.json().catch(() => ({}));
    const result = await handleModeration(body, { userId: user.id, aal: aalOf(token) }, {
      rpc: (fn, args) => supabase.rpc(fn, args),
      sign: async (bucket, keys, seconds) => {
        const { data, error } = await supabase.storage.from(bucket).createSignedUrls(keys, seconds);
        if (error || !data) throw new Error("storage_unavailable");
        return data.map((d) => ({ path: d.path ?? null, signedUrl: d.signedUrl ?? null }));
      },
    });
    return answer(result);
  } catch (error) {
    if (error instanceof HttpError) return answer({ ok: false, reason: "unauthorized" }, error.status);
    console.error("dating-moderation failed:", errorCode(error));
    return answer({ ok: false, reason: "busy" }, 500);
  }
}
```

Create `supabase/functions/dating-moderation/index.ts` with exactly:

```typescript
// supabase/functions/dating-moderation/index.ts
// Spec 2 W7b (§4.7, §6.4): serves request.ts with the live user check, the
// service-role client and the console's origin (DATING_CONSOLE_ORIGIN).
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, serviceRoleClient } from "../_shared/attune_auth.ts";
import { handleRequest } from "./request.ts";

serve((req) =>
  handleRequest(req, {
    requireUser,
    client: serviceRoleClient,
    origin: Deno.env.get("DATING_CONSOLE_ORIGIN") ?? null,
  })
);
```

Create `$D/edit_ci_T6.py` with exactly:

```python
#!/usr/bin/env python3
# Spec 2 W7b Task 6: CI runs the console API's tests and type-checks its
# wiring under the frozen lock; config.toml names the function (verify_jwt
# off: a browser's CORS preflight carries no token; request.ts checks every
# caller with requireUser, and the database every moderator).
import importlib.util

spec = importlib.util.spec_from_file_location('anchor', '.superpowers/sdd/2026-11-21-spec2-w7/anchor.py')
anchor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(anchor)

anchor.edit('.github/workflows/tests.yml', [
    (" _shared/dating_chat_safety.test.ts process-dating-safety-outbox/handler.test.ts\n",
     " _shared/dating_chat_safety.test.ts process-dating-safety-outbox/handler.test.ts dating-moderation/handler.test.ts\n"),
    ("dating-photo-urls/index.ts process-dating-safety-outbox/index.ts\n",
     "dating-photo-urls/index.ts process-dating-safety-outbox/index.ts dating-moderation/index.ts\n"),
], 'W7b Task 6')

anchor.edit('supabase/config.toml', [(
    """[functions.process-dating-safety-outbox]
verify_jwt = true
""", """[functions.process-dating-safety-outbox]
verify_jwt = true

# Spec 2 W7b (§6.4): the moderation console's API. A browser's CORS preflight
# carries no token, so the gateway's check is off; request.ts checks every
# caller's token with requireUser and needs aal2 (TOTP), and every
# moderation_* function refuses anyone who is not an active moderator.
[functions.dating-moderation]
verify_jwt = false
""")], 'W7b Task 6')
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
python3 -I $D/edit_ci_T6.py
(cd supabase/functions && deno test --allow-read --frozen dating-moderation/handler.test.ts 2>&1 | grep -E 'passed|failed' | tail -1 | sed 's/\x1b\[[0-9;]*m//g')
(cd supabase/functions && eval "$(grep -m1 -oE 'deno test --allow-read [^"]*' ../../.github/workflows/tests.yml)" 2>&1 | grep -E 'passed|failed' | tail -1 | sed 's/\x1b\[[0-9;]*m//g')
(cd supabase/functions && eval "$(grep -m1 -oE 'deno check [^"]*dating-moderation/index.ts' ../../.github/workflows/tests.yml)" > /dev/null 2>&1; echo "deno check exit=$?")
```

Expected: `.github/workflows/tests.yml: 2 edit(s) (W7b Task 6)`; `supabase/config.toml: 1 edit(s) (W7b Task 6)`; `ok | 7 passed | 0 failed (…)`; `ok | 245 passed | 0 failed (…)` (the CI line, the function's 7 among them); `deno check exit=0`.

- [ ] **Step 3: The mutants**

Create `$D/mut_T6.py` with exactly:

```python
# Spec 2 W7b Task 6: Deno mutants (denomut.py).
TESTS = ['dating-moderation/handler.test.ts']
H = 'supabase/functions/dating-moderation/handler.ts'
R = 'supabase/functions/dating-moderation/request.ts'
MUTS = {
    'aal_skipped': (H, [('  if (caller.aal !== "aal2") return { ok: false, reason: "mfa_required" };\n', '')]),
    'body_actor_used': (H, [('{ p_actor: caller.userId, ...args }', '{ p_actor: caller.userId, ...args, ...(typeof b.p_actor === "string" ? { p_actor: b.p_actor } : {}) }')]),
    'keys_leak': (H, [('photos.map(({ key, ...rest }) => ({ ...rest, url:', 'photos.map(({ key, ...rest }) => ({ ...rest, key, url:')]),
    'server_text_passes': (H, [('const reason = typeof data.reason === "string" && REASONS.has(data.reason) ? data.reason : "busy";', 'const reason = String(data.reason);')]),
    'url_lives_an_hour': (H, [('export const SIGNED_URL_SECONDS = 60;', 'export const SIGNED_URL_SECONDS = 3600;')]),
    'prototype_action': (H, [('Object.prototype.hasOwnProperty.call(ACTIONS, action) ? ACTIONS[action] : undefined', 'ACTIONS[action]')]),
    'invalid_reaches_db': (H, [('  if (args === null) return { ok: false, reason: "invalid" };\n', '')]),
    'cors_any_origin': (R, [('if (origin !== null && req.headers.get("Origin") === origin) {', 'if (origin !== null) {')]),
    'log_message': (R, [('console.error("dating-moderation failed:", errorCode(error));', 'console.error("dating-moderation failed:", String(error));')]),
    'cache_allowed': (R, [('"Cache-Control": "no-store"', '"Cache-Control": "private"')]),
}
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7; python3 -I $D/denomut.py $D/mut_T6.py 2>&1 | tail -1
```

Expected: `10/10 killed`.

- [ ] **Step 4: Record the tree**

Do not commit; record the tree in the report.

### Task 7: The console (a separate web entry point with TOTP, built in CI), the queue, a case, the lists, and the W7b gate (§6.4; F-6; S-5; R-58, R-61)

**Files:**
- Create: `lib/console/{main_console.dart, console_api.dart, console_auth.dart, console_app.dart}`, `lib/console/screens/{queue_screen.dart, case_screen.dart, console_lists.dart}`, `web/index.html`, `test/console/{console_fakes.dart, console_test.dart}`, `$D/{edit_ci_T7.py, mut_T7_dart.py}`
- Modify: `.github/workflows/tests.yml` (the `console-web` job)

**Interfaces:**
- Consumes: Task 6's actions and answers; `supabase_flutter` (`Supabase.initialize`, `auth.signInWithOtp`, `auth.verifyOTP`, `auth.mfa.{listFactors, enroll, challengeAndVerify, getAuthenticatorAssuranceLevel}`, `functions.invoke`).
- Produces: `ConsoleApi`, `ConsoleAnswer`, `SupabaseConsoleApi`, `ConsoleAuth`, `ConsoleSession`, `SupabaseConsoleAuth`, `ConsoleApp`, `ConsoleGate`, `ConsoleHome`, `ConsolePage`, `ConsoleMe`, `consoleReason`; `QueueScreen`, `CaseScreen`, `AppealsScreen`, `PhotosScreen`, `VerificationsScreen`, `CountriesScreen`, `OpinionsScreen`, `AuditScreen`; test `FakeConsoleApi`, `FakeConsoleAuth`.

- [ ] **Step 1: Write the failing tests**

Create `test/console/console_fakes.dart` with exactly:

```dart
// Spec 2 W7b (§6.4): the console's fakes: an API that records every call
// and answers what a test sets (ok by default), the sign-in steps, and the
// console pumped as a signed-in moderator at desktop size.
import 'package:attune/console/console_api.dart';
import 'package:attune/console/console_app.dart';
import 'package:attune/console/console_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeConsoleApi implements ConsoleApi {
  FakeConsoleApi(this.answers);

  final Map<String, ConsoleAnswer> answers;
  final calls = <(String, Map<String, Object?>)>[];

  @override
  Future<ConsoleAnswer> call(
    String action, [
    Map<String, Object?> params = const {},
  ]) async {
    calls.add((action, params));
    return answers[action] ?? const ConsoleAnswer(ok: true);
  }

  List<Map<String, Object?>> of(String action) => [
    for (final c in calls)
      if (c.$1 == action) c.$2,
  ];
}

class FakeConsoleAuth implements ConsoleAuth {
  FakeConsoleAuth(this.state);

  ConsoleSession state;
  final codes = <String>[];

  @override
  Future<ConsoleSession> session() async => state;

  @override
  Future<bool> sendCode(String phone) async => phone.startsWith('+');

  @override
  Future<bool> verifyCode(String phone, String code) async {
    codes.add(code);
    if (code != '123456') return false;
    state = ConsoleSession.needsTotp;
    return true;
  }

  @override
  Future<ConsoleEnrolment?> enrol() async =>
      const ConsoleEnrolment(factorId: 'f1', secret: 'JBSWY3DPEHPK3PXP');

  @override
  Future<bool> verifyTotp(String code, {String? factorId}) async {
    codes.add('$code/$factorId');
    if (code != '654321') return false;
    state = ConsoleSession.ready;
    return true;
  }

  @override
  Future<void> signOut() async => state = ConsoleSession.signedOut;
}

const consoleMe = ConsoleAnswer(
  ok: true,
  data: {'ok': true, 'role': 'moderator', 'sensitive_routing_allowed': false},
);
const consoleOwner = ConsoleAnswer(
  ok: true,
  data: {'ok': true, 'role': 'safety_owner', 'sensitive_routing_allowed': true},
);

final consoleQueue = ConsoleAnswer(
  ok: true,
  data: {
    'ok': true,
    'cases': [
      {
        'id': 'c1',
        'kind': 'report',
        'priority': 'P0',
        'category': 'threat_to_life',
        'state': 'open',
        'reports': 2,
        'sla_due_at':
            DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
        'mine': false,
        'claimed': false,
        'gone': false,
      },
      {
        'id': 'c2',
        'kind': 'signal',
        'priority': 'P1',
        'signal_kind': 'dragnet',
        'claimed': true,
      },
      {'id': 'c3', 'kind': 'appeal', 'priority': 'P2', 'claimed': false},
    ],
  },
);

const consoleCase = ConsoleAnswer(
  ok: true,
  data: {
    'ok': true,
    'case': {
      'id': 'c1',
      'kind': 'report',
      'priority': 'P0',
      'state': 'in_review',
      'mine': true,
    },
    'reports': [
      {
        'id': 'r1',
        'category': 'underage_risk',
        'priority': 'P0',
        'state': 'open',
        'details': 'She said she is in SHS.',
        'reporter_triggered': 'sexual_pressure',
        'evidence': [
          {
            'from': 'reported',
            'kind': 'text',
            'at': '2026-11-20T10:00:00Z',
            'text': 'after BECE',
          },
        ],
      },
    ],
    'profile': {
      'display_name': 'Kofi',
      'age': 31,
      'country': 'GH',
      'region': 'AA',
      'prompts': [
        {'prompt': 'perfect_sunday', 'answer': 'Church, then jollof.'},
      ],
      'photos': [],
    },
    'prior': [
      {
        'kind': 'signal',
        'state': 'closed',
        'outcome': 'no_action',
        'created_at': '2026-11-01',
      },
    ],
    'families': ['age_signal'],
    'appeal': null,
  },
);

Future<FakeConsoleApi> pumpHome(
  WidgetTester t, {
  ConsoleAnswer me = consoleMe,
  Map<String, ConsoleAnswer> answers = const {},
}) async {
  await t.pumpWidget(const SizedBox()); // a fresh console each time
  t.view.physicalSize = const Size(1400, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final api = FakeConsoleApi({
    'whoami': me,
    'queue': consoleQueue,
    'case': consoleCase,
    ...answers,
  });
  await t.pumpWidget(
    ConsoleApp(api: api, auth: FakeConsoleAuth(ConsoleSession.ready)),
  );
  await t.pumpAndSettle();
  return api;
}
```

Create `test/console/console_test.dart` with exactly:

```dart
// Spec 2 W7b Task 7 (§6.4; F-6): the moderation console. Sign-in is the
// phone's code, then TOTP (a first sign-in enrols), then the server's
// moderator check; the queue lists the server's cases by page, claims and
// opens them; a case shows its reports (text, credibility, evidence), the
// person as others see them, the families, earlier cases and an appeal,
// and each action sends one request with the case's id; a refused case
// reads as unavailable; photos, verifications, Opinions, countries (the
// owner publishes) and the audit. The console imports only lib/console,
// Flutter and the Supabase client, and nothing else imports it.
import 'dart:io';

import 'package:attune/console/console_api.dart';
import 'package:attune/console/console_app.dart';
import 'package:attune/console/console_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'console_fakes.dart';

void main() {
  testWidgets('sign-in: the code, then TOTP, then the moderator check', (
    t,
  ) async {
    final api = FakeConsoleApi({'whoami': consoleMe, 'queue': consoleQueue});
    final auth = FakeConsoleAuth(ConsoleSession.signedOut);
    await t.pumpWidget(ConsoleApp(api: api, auth: auth));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('console_phone')),
      '+233244000000',
    );
    await t.tap(find.byKey(const ValueKey('console_next')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('console_code')), '000000');
    await t.tap(find.byKey(const ValueKey('console_next')));
    await t.pumpAndSettle();
    expect(find.text("That code didn't work."), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('console_code')), '123456');
    await t.tap(find.byKey(const ValueKey('console_next')));
    await t.pumpAndSettle();
    expect(
      find.text('Enter the code from your authenticator app.'),
      findsOneWidget,
    );
    expect(api.of('whoami'), isEmpty, reason: 'nothing is asked before aal2');
    await t.enterText(find.byKey(const ValueKey('console_totp')), '654321');
    await t.tap(find.byKey(const ValueKey('console_verify')));
    await t.pumpAndSettle();
    expect(api.of('whoami'), hasLength(1));
    expect(find.text('Moderator'), findsOneWidget);
    expect(find.byKey(const ValueKey('console_case_c1')), findsOneWidget);
  });

  testWidgets('a first sign-in enrols an authenticator app; someone who is '
      'not a moderator stays out', (t) async {
    final api = FakeConsoleApi({
      'whoami': const ConsoleAnswer(ok: false, reason: 'not_moderator'),
    });
    final auth = FakeConsoleAuth(ConsoleSession.needsEnrol);
    await t.pumpWidget(ConsoleApp(api: api, auth: auth));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('console_enrol')));
    await t.pumpAndSettle();
    expect(find.text('Key: JBSWY3DPEHPK3PXP'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('console_totp')), '654321');
    await t.tap(find.byKey(const ValueKey('console_verify')));
    await t.pumpAndSettle();
    expect(auth.codes.last, '654321/f1');
    expect(find.text("This account isn't a moderator."), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('the queue by page: claim sends the case\'s id and reads '
      'again; appeals and signals have their own pages', (t) async {
    final api = await pumpHome(t);
    expect(find.text('P0 · report · threat_to_life'), findsOneWidget);
    expect(find.textContaining('2 reports'), findsOneWidget);
    expect(find.byKey(const ValueKey('console_case_c2')), findsNothing);
    expect(find.byKey(const ValueKey('console_case_c3')), findsNothing);
    await t.tap(find.text('Claim'));
    await t.pumpAndSettle();
    expect(api.of('claim'), [
      {'case_id': 'c1'},
    ]);
    expect(api.of('queue'), hasLength(2));
    await t.tap(find.text('Appeals'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('console_case_c3')), findsOneWidget);
    await t.tap(find.text('Signals'));
    await t.pumpAndSettle();
    expect(find.text('P1 · signal · dragnet'), findsOneWidget);
  });

  testWidgets('a case: its reports, the credibility note, the evidence, the '
      'person, the families and earlier cases; each action is one request', (
    t,
  ) async {
    final api = await pumpHome(t);
    await t.tap(find.byKey(const ValueKey('console_case_c1')));
    await t.pumpAndSettle();
    expect(find.text('"She said she is in SHS."'), findsOneWidget);
    expect(
      find.text(
        "The reporter's messages in this chat triggered: sexual_pressure",
      ),
      findsOneWidget,
    );
    expect(find.text('Evidence (1 messages)'), findsOneWidget);
    expect(find.text('Kofi · 31 · GH · AA'), findsOneWidget);
    expect(find.text('perfect_sunday: Church, then jollof.'), findsOneWidget);
    expect(find.text('age_signal'), findsOneWidget);
    expect(find.textContaining('no_action'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('console_hold')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('console_category_underage_risk')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('console_restrict')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('console_restrict_save')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('console_minor')));
    await t.tap(find.byKey(const ValueKey('console_minor')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('console_add_note')));
    await t.tap(find.byKey(const ValueKey('console_add_note')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('console_note')), 'Checked.');
    await t.tap(find.byKey(const ValueKey('console_note_save')));
    await t.pumpAndSettle();
    expect(api.of('hold'), [
      {'case_id': 'c1', 'category': 'underage_risk'},
    ]);
    final restrict = api.of('restrict').single;
    expect(restrict['type'], 'suspended');
    expect(restrict['category'], 'harassment');
    final ends = DateTime.parse(restrict['ends_at']! as String);
    expect(ends.difference(DateTime.now()).inDays, inInclusiveRange(6, 7));
    expect(api.of('confirm_minor'), [
      {'case_id': 'c1'},
    ]);
    expect(api.of('note'), [
      {'case_id': 'c1', 'note': 'Checked.'},
    ]);
    expect(api.of('case').length, 5, reason: 'read again after each action');
  });

  testWidgets('a refused case reads as unavailable; an appeal decided by '
      'its decider says so', (t) async {
    final api = await pumpHome(
      t,
      answers: {
        'case': const ConsoleAnswer(ok: false, reason: 'case_unavailable'),
      },
    );
    await t.tap(find.byKey(const ValueKey('console_case_c1')));
    await t.pumpAndSettle();
    expect(find.text("This case isn't available."), findsOneWidget);
    api.answers['case'] = const ConsoleAnswer(
      ok: true,
      data: {
        'ok': true,
        'case': {
          'id': 'c3',
          'kind': 'appeal',
          'priority': 'P2',
          'state': 'open',
        },
        'reports': [],
        'appeal': {
          'text': 'I did not.',
          'restriction': {
            'type': 'suspended',
            'category': 'harassment',
            'ends_at': null,
          },
        },
      },
    );
    api.answers['decide_appeal'] = const ConsoleAnswer(
      ok: false,
      reason: 'same_decider',
    );
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.text('Appeals'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('console_case_c3')));
    await t.pumpAndSettle();
    expect(find.text('"I did not."'), findsOneWidget);
    expect(
      find.text('Restriction: suspended · harassment · until closed for good'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('console_dismiss')), findsNothing);
    await t.tap(find.byKey(const ValueKey('console_appeal_accept')));
    await t.pumpAndSettle();
    expect(api.of('decide_appeal'), [
      {'case_id': 'c3', 'accept': true},
    ]);
    expect(
      find.text(
        'A different person from the one who made the decision must decide this appeal.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('photos, verifications, Opinions and the audit', (t) async {
    final api = await pumpHome(
      t,
      answers: {
        'photos': const ConsoleAnswer(
          ok: true,
          data: {
            'ok': true,
            'photos': [
              {
                'id': 'p1',
                'position': 3,
                'reason': 'needs_review',
                'url': null,
              },
            ],
          },
        ),
        'verifications': const ConsoleAnswer(
          ok: true,
          data: {
            'ok': true,
            'sessions': [
              {
                'id': 's1',
                'step': 'human',
                'kind': 'activation',
                'gestures': ['smile', 'left'],
                'review': [],
                'photos': [],
              },
            ],
          },
        ),
        'opinions_queue': const ConsoleAnswer(
          ok: true,
          data: {
            'ok': true,
            'reports': [
              {
                'report_id': 'o1',
                'reason': 'Someone may be at risk',
                'excerpt': 'I cannot go on',
                'content_type': 'opinion',
                'content_id': 'op1',
                'content_removed': false,
              },
            ],
          },
        ),
        'audit': const ConsoleAnswer(
          ok: true,
          data: {
            'ok': true,
            'actions': [
              {
                'action': 'claim',
                'mine': true,
                'at': '2026-11-21T10:00:00Z',
                'detail': {},
              },
            ],
          },
        ),
      },
    );
    await t.tap(find.text('Photos'));
    await t.pumpAndSettle();
    await t.tap(find.text('Approve'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('console_photo_reject_p1')));
    await t.pumpAndSettle();
    await t.tap(find.text('face_unclear').last);
    await t.pumpAndSettle();
    expect(api.of('photo_decide'), [
      {'photo_id': 'p1', 'approve': true},
      {'photo_id': 'p1', 'approve': false, 'reason': 'face_unclear'},
    ]);
    await t.tap(find.text('Verifications'));
    await t.pumpAndSettle();
    expect(find.text('Gestures: smile, left'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('console_pass_s1')));
    await t.pumpAndSettle();
    expect(api.of('verification_decide'), [
      {'session_id': 's1', 'outcome': 'pass'},
    ]);
    await t.tap(find.text('Opinions'));
    await t.pumpAndSettle();
    expect(find.textContaining('keep the post or escalate it'), findsOneWidget);
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(api.of('opinions_remove'), [
      {'type': 'opinion', 'id': 'op1'},
    ]);
    await t.tap(find.text('Audit'));
    await t.pumpAndSettle();
    expect(find.text('claim (you)'), findsOneWidget);
  });

  testWidgets('countries: a moderator reads; only the safety owner publishes', (
    t,
  ) async {
    const countries = ConsoleAnswer(
      ok: true,
      data: {
        'ok': true,
        'countries': [
          {
            'country': 'GH',
            'tier': 1,
            'version': 3,
            'dating_enabled': false,
            'same_gender_enabled': false,
          },
        ],
      },
    );
    await pumpHome(t, answers: {'countries': countries});
    await t.tap(find.text('Countries'));
    await t.pumpAndSettle();
    expect(find.text('GH · tier 1 · v3'), findsOneWidget);
    expect(find.byKey(const ValueKey('console_publish')), findsNothing);
    final api = await pumpHome(
      t,
      me: consoleOwner,
      answers: {'countries': countries},
    );
    await t.tap(find.text('Countries'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('console_country_code')), 'gh');
    await t.enterText(
      find.byKey(const ValueKey('console_country_values')),
      '{"dating_enabled": true}',
    );
    await t.tap(find.byKey(const ValueKey('console_publish')));
    await t.pumpAndSettle();
    expect(api.of('publish_country'), [
      {
        'country': 'GH',
        'values': {'dating_enabled': true},
      },
    ]);
  });

  test('the console imports only lib/console, Flutter and the Supabase '
      'client; nothing else imports the console', () {
    final allowed = RegExp(
      r"^import '(dart:[a-z_]+|package:flutter/[a-z_]+\.dart|package:supabase_flutter/supabase_flutter\.dart|package:attune/console/[a-z_/]+\.dart)'",
    );
    for (final f
        in Directory(
          'lib/console',
        ).listSync(recursive: true).whereType<File>()) {
      for (final line in f.readAsLinesSync().where(
        (l) => l.startsWith('import '),
      )) {
        expect(allowed.hasMatch(line), isTrue, reason: '${f.path}: $line');
      }
    }
    for (final f
        in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (f.path.startsWith('lib/console/') || !f.path.endsWith('.dart')) {
        continue;
      }
      expect(
        f.readAsStringSync().contains('package:attune/console/'),
        isFalse,
        reason: f.path,
      );
    }
  });
}
```

```bash
flutter test --no-pub test/console/console_test.dart 2>&1 | grep -oE "Error: Error when reading '[^']*'" | head -1
```

Expected: `Error: Error when reading 'lib/console/console_api.dart'`.

- [ ] **Step 2: The console**

Create `lib/console/main_console.dart` with exactly:

```dart
// Spec 2 W7b (§6.4, F-6): the moderation console, a separate web entry
// point (flutter build web -t lib/console/main_console.dart), hosted as a
// private static site behind an access gate. It imports only lib/console
// and the web-safe Supabase client. The project's URL and anon key come
// from --dart-define at build time (no file holds them).
import 'package:attune/console/console_api.dart';
import 'package:attune/console/console_app.dart';
import 'package:attune/console/console_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    publishableKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  final client = Supabase.instance.client;
  runApp(
    ConsoleApp(
      api: SupabaseConsoleApi(client),
      auth: SupabaseConsoleAuth(client),
    ),
  );
}
```

Create `lib/console/console_api.dart` with exactly:

```dart
// Spec 2 W7b (§6.4): the console's one way to the server: the
// dating-moderation edge function, one action per call. Every answer is a
// fixed code or the function's data; a failure is busy, never its text.
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class ConsoleAnswer {
  const ConsoleAnswer({required this.ok, this.reason, this.data = const {}});

  static const busy = ConsoleAnswer(ok: false, reason: 'busy');

  final bool ok;
  final String? reason;
  final Map<String, dynamic> data;

  List<Map<String, dynamic>> list(String key) => [
    for (final row in (data[key] is List ? data[key] as List : const []))
      if (row is Map) Map<String, dynamic>.from(row),
  ];

  factory ConsoleAnswer.fromJson(Object? raw) {
    if (raw is! Map) return busy;
    final data = Map<String, dynamic>.from(raw);
    if (data['ok'] != true) {
      final reason = data['reason'];
      return ConsoleAnswer(
        ok: false,
        reason: reason is String ? reason : 'busy',
      );
    }
    return ConsoleAnswer(ok: true, data: data);
  }
}

abstract class ConsoleApi {
  Future<ConsoleAnswer> call(
    String action, [
    Map<String, Object?> params = const {},
  ]);
}

class SupabaseConsoleApi implements ConsoleApi {
  SupabaseConsoleApi(this._client);

  final SupabaseClient _client;

  static const timeout = Duration(seconds: 20);

  @override
  Future<ConsoleAnswer> call(
    String action, [
    Map<String, Object?> params = const {},
  ]) async {
    try {
      final r = await _client.functions
          .invoke('dating-moderation', body: {...params, 'action': action})
          .timeout(timeout);
      return ConsoleAnswer.fromJson(r.data);
    } on FunctionException catch (e) {
      return e.status == 401
          ? const ConsoleAnswer(ok: false, reason: 'unauthorized')
          : ConsoleAnswer.fromJson(e.details);
    } catch (_) {
      return ConsoleAnswer.busy;
    }
  }
}
```

Create `lib/console/console_auth.dart` with exactly:

```dart
// Spec 2 W7b (§6.4): signing in to the console: the moderator's Attune
// phone account (a code by SMS), then TOTP (aal2). A first sign-in enrols
// an authenticator app; the console never stores anything itself (the
// Supabase session is the web client's own).
import 'package:supabase_flutter/supabase_flutter.dart';

enum ConsoleSession { signedOut, needsEnrol, needsTotp, ready }

class ConsoleEnrolment {
  const ConsoleEnrolment({required this.factorId, required this.secret});

  final String factorId;

  /// The key to type into an authenticator app.
  final String secret;
}

abstract class ConsoleAuth {
  Future<ConsoleSession> session();
  Future<bool> sendCode(String phone);
  Future<bool> verifyCode(String phone, String code);
  Future<ConsoleEnrolment?> enrol();
  Future<bool> verifyTotp(String code, {String? factorId});
  Future<void> signOut();
}

class SupabaseConsoleAuth implements ConsoleAuth {
  SupabaseConsoleAuth(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  @override
  Future<ConsoleSession> session() async {
    if (_auth.currentSession == null) return ConsoleSession.signedOut;
    final level = _auth.mfa.getAuthenticatorAssuranceLevel();
    if (level.currentLevel == AuthenticatorAssuranceLevels.aal2) {
      return ConsoleSession.ready;
    }
    try {
      final factors = await _auth.mfa.listFactors();
      return factors.totp.isEmpty
          ? ConsoleSession.needsEnrol
          : ConsoleSession.needsTotp;
    } catch (_) {
      return ConsoleSession.signedOut;
    }
  }

  @override
  Future<bool> sendCode(String phone) async {
    try {
      await _auth.signInWithOtp(phone: phone, shouldCreateUser: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> verifyCode(String phone, String code) async {
    try {
      await _auth.verifyOTP(type: OtpType.sms, phone: phone, token: code);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ConsoleEnrolment?> enrol() async {
    try {
      final r = await _auth.mfa.enroll(
        factorType: FactorType.totp,
        issuer: 'Attune console',
      );
      final totp = r.totp;
      return totp == null
          ? null
          : ConsoleEnrolment(factorId: r.id, secret: totp.secret);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> verifyTotp(String code, {String? factorId}) async {
    try {
      final id = factorId ?? (await _auth.mfa.listFactors()).totp.first.id;
      await _auth.mfa.challengeAndVerify(factorId: id, code: code);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {}
  }
}
```

Create `lib/console/console_app.dart` with exactly (Task 9 adds the law-enforcement page):

```dart
// Spec 2 W7b (§6.4): the console's shell. Signed out: the phone and its
// code; then TOTP (a first sign-in enrols an authenticator app); then the
// server says whether this account is an active moderator. Only then the
// pages: the queue, appeals, signals, photos, verifications, Opinions,
// countries and the audit. Nothing here is stored on the device by the
// console itself.
import 'package:attune/console/console_api.dart';
import 'package:attune/console/console_auth.dart';
import 'package:attune/console/screens/case_screen.dart';
import 'package:attune/console/screens/console_lists.dart';
import 'package:attune/console/screens/queue_screen.dart';
import 'package:flutter/material.dart';

const kConsoleTitle = 'Attune moderation';

/// The moderator's role and routing, from whoami.
class ConsoleMe {
  const ConsoleMe({required this.role, required this.routing});

  final String role;
  final bool routing;

  bool get owner => role == 'safety_owner';
}

/// What the console reads for a fixed code.
String consoleReason(String? reason) => switch (reason) {
  'case_unavailable' => "This case isn't available.",
  'same_decider' =>
    'A different person from the one who made the decision must decide this appeal.',
  'appeal_unavailable' => "This appeal isn't open any more.",
  'photo_unavailable' => "This photo isn't waiting any more.",
  'session_unavailable' => "This check isn't waiting any more.",
  'safety_owner_only' => 'Only the safety owner can do this.',
  'not_moderator' => "This account isn't a moderator.",
  'mfa_required' => 'Enter your authenticator code again.',
  'unauthorized' => 'Sign in again.',
  'invalid' => 'Check what you entered.',
  _ => 'Something went wrong. Try again.',
};

class ConsoleApp extends StatelessWidget {
  const ConsoleApp({super.key, required this.api, required this.auth});

  final ConsoleApi api;
  final ConsoleAuth auth;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: kConsoleTitle,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: const Color(0xFF2E7D32)),
    home: ConsoleGate(api: api, auth: auth),
  );
}

class ConsoleGate extends StatefulWidget {
  const ConsoleGate({super.key, required this.api, required this.auth});

  final ConsoleApi api;
  final ConsoleAuth auth;

  @override
  State<ConsoleGate> createState() => _ConsoleGateState();
}

class _ConsoleGateState extends State<ConsoleGate> {
  ConsoleSession? _session;
  ConsoleMe? _me;
  String? _line;
  bool _busy = false;
  bool _codeSent = false;
  ConsoleEnrolment? _enrolment;
  final _phone = TextEditingController();
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final session = await widget.auth.session();
    ConsoleMe? me;
    String? line;
    if (session == ConsoleSession.ready) {
      final r = await widget.api('whoami');
      if (r.ok) {
        me = ConsoleMe(
          role: r.data['role'] as String? ?? 'moderator',
          routing: r.data['sensitive_routing_allowed'] == true,
        );
      } else {
        line = consoleReason(r.reason);
      }
    }
    if (!mounted) return;
    setState(() {
      _session = session;
      _me = me;
      _line = line;
      _busy = false;
      _code.clear();
    });
  }

  Future<void> _step(Future<bool> Function() action, String failed) async {
    setState(() {
      _busy = true;
      _line = null;
    });
    final ok = await action();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _line = failed;
      });
      return;
    }
    await _refresh();
  }

  Future<void> _signOut() async {
    await widget.auth.signOut();
    setState(() {
      _codeSent = false;
      _enrolment = null;
    });
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    if (_session == ConsoleSession.ready && me != null) {
      return ConsoleHome(api: widget.api, me: me, onSignOut: _signOut);
    }
    return Scaffold(
      appBar: AppBar(title: const Text(kConsoleTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              ..._form(context),
              if (_line case final line?)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    line,
                    key: const ValueKey('console_line'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _form(BuildContext context) {
    switch (_session) {
      case null:
        return const [Text('Checking your session.')];
      case ConsoleSession.signedOut:
        return [
          const Text('Sign in with your Attune phone number.'),
          TextField(
            key: const ValueKey('console_phone'),
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Phone number'),
          ),
          if (_codeSent)
            TextField(
              key: const ValueKey('console_code'),
              controller: _code,
              decoration: const InputDecoration(labelText: 'Code'),
            ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('console_next'),
            onPressed:
                _busy
                    ? null
                    : _codeSent
                    ? () => _step(
                      () => widget.auth.verifyCode(
                        _phone.text.trim(),
                        _code.text.trim(),
                      ),
                      "That code didn't work.",
                    )
                    : () async {
                      setState(() => _busy = true);
                      final ok = await widget.auth.sendCode(_phone.text.trim());
                      if (!mounted) return;
                      setState(() {
                        _busy = false;
                        _codeSent = ok;
                        _line = ok ? null : "We couldn't send a code.";
                      });
                    },
            child: Text(_codeSent ? 'Sign in' : 'Send code'),
          ),
        ];
      case ConsoleSession.needsEnrol:
        final enrolment = _enrolment;
        return [
          const Text(
            'Set up your authenticator app. Every sign-in needs its code.',
          ),
          if (enrolment == null)
            FilledButton(
              key: const ValueKey('console_enrol'),
              onPressed:
                  _busy
                      ? null
                      : () async {
                        final e = await widget.auth.enrol();
                        if (!mounted) return;
                        setState(() {
                          _enrolment = e;
                          _line =
                              e == null
                                  ? 'Something went wrong. Try again.'
                                  : null;
                        });
                      },
              child: const Text('Set up'),
            )
          else ...[
            SelectableText('Key: ${enrolment.secret}'),
            ..._totp(factorId: enrolment.factorId),
          ],
          TextButton(onPressed: _signOut, child: const Text('Sign out')),
        ];
      case ConsoleSession.needsTotp:
        return [
          const Text('Enter the code from your authenticator app.'),
          ..._totp(),
          TextButton(onPressed: _signOut, child: const Text('Sign out')),
        ];
      case ConsoleSession.ready:
        return [
          const Text('Checking your moderator access.'),
          TextButton(onPressed: _signOut, child: const Text('Sign out')),
        ];
    }
  }

  List<Widget> _totp({String? factorId}) => [
    TextField(
      key: const ValueKey('console_totp'),
      controller: _code,
      decoration: const InputDecoration(labelText: 'Authenticator code'),
    ),
    const SizedBox(height: 12),
    FilledButton(
      key: const ValueKey('console_verify'),
      onPressed:
          _busy
              ? null
              : () => _step(
                () => widget.auth.verifyTotp(
                  _code.text.trim(),
                  factorId: factorId,
                ),
                "That code didn't work.",
              ),
      child: const Text('Verify'),
    ),
  ];
}

/// The console's pages, by destination.
enum ConsolePage {
  queue('Queue', Icons.inbox_outlined),
  appeals('Appeals', Icons.gavel_outlined),
  signals('Signals', Icons.sensors_outlined),
  photos('Photos', Icons.photo_outlined),
  verifications('Verifications', Icons.verified_user_outlined),
  opinions('Opinions', Icons.forum_outlined),
  countries('Countries', Icons.public_outlined),
  audit('Audit', Icons.history_outlined);

  const ConsolePage(this.label, this.icon);

  final String label;
  final IconData icon;
}

class ConsoleHome extends StatefulWidget {
  const ConsoleHome({
    super.key,
    required this.api,
    required this.me,
    required this.onSignOut,
  });

  final ConsoleApi api;
  final ConsoleMe me;
  final VoidCallback onSignOut;

  @override
  State<ConsoleHome> createState() => _ConsoleHomeState();
}

class _ConsoleHomeState extends State<ConsoleHome> {
  ConsolePage _page = ConsolePage.queue;

  void _openCase(String id) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CaseScreen(api: widget.api, me: widget.me, caseId: id),
    ),
  );

  Widget _body() => switch (_page) {
    ConsolePage.queue => QueueScreen(
      key: const ValueKey('queue'),
      api: widget.api,
      kinds: const {'report', 'photo', 'verification', 'csam_hit'},
      onOpen: _openCase,
    ),
    ConsolePage.appeals => QueueScreen(
      key: const ValueKey('appeals'),
      api: widget.api,
      kinds: const {'appeal'},
      onOpen: _openCase,
    ),
    ConsolePage.signals => QueueScreen(
      key: const ValueKey('signals'),
      api: widget.api,
      kinds: const {'signal'},
      onOpen: _openCase,
    ),
    ConsolePage.photos => PhotosScreen(api: widget.api),
    ConsolePage.verifications => VerificationsScreen(api: widget.api),
    ConsolePage.opinions => OpinionsScreen(api: widget.api),
    ConsolePage.countries => CountriesScreen(api: widget.api, me: widget.me),
    ConsolePage.audit => AuditScreen(api: widget.api),
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('$kConsoleTitle · ${_page.label}'),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(
            child: Text(widget.me.owner ? 'Safety owner' : 'Moderator'),
          ),
        ),
        TextButton(onPressed: widget.onSignOut, child: const Text('Sign out')),
      ],
    ),
    body: Row(
      children: [
        // Every page reachable at any window height: the rail scrolls.
        LayoutBuilder(
          builder:
              (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: NavigationRail(
                      selectedIndex: _page.index,
                      labelType: NavigationRailLabelType.all,
                      onDestinationSelected:
                          (i) => setState(() => _page = ConsolePage.values[i]),
                      destinations: [
                        for (final p in ConsolePage.values)
                          NavigationRailDestination(
                            icon: Icon(p.icon),
                            label: Text(p.label),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _body()),
      ],
    ),
  );
}
```

Create `lib/console/screens/queue_screen.dart` with exactly:

```dart
// Spec 2 W7b (§6.4 Queue): open cases by priority and time to their clock
// (the server leaves out a case that needs routing this moderator lacks);
// claim from the row; open a case.
import 'package:attune/console/console_api.dart';
import 'package:attune/console/console_app.dart';
import 'package:flutter/material.dart';

/// "in 2 h 5 m" or "5 m late", from now.
String consoleDue(DateTime? due, DateTime now) {
  if (due == null) return 'no clock';
  final d = due.difference(now);
  final m = d.inMinutes.abs();
  final text = '${m ~/ 60} h ${m % 60} m';
  return d.isNegative ? '$text late' : 'in $text';
}

class QueueScreen extends StatefulWidget {
  const QueueScreen({
    super.key,
    required this.api,
    required this.kinds,
    required this.onOpen,
    this.now,
  });

  final ConsoleApi api;
  final Set<String> kinds;
  final void Function(String caseId) onOpen;
  final DateTime Function()? now;

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  ConsoleAnswer? _read;
  String? _line;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.api('queue', {'limit': 200});
    if (mounted) setState(() => _read = r);
  }

  Future<void> _claim(String id) async {
    final r = await widget.api('claim', {'case_id': id});
    if (!mounted) return;
    setState(() => _line = r.ok ? null : consoleReason(r.reason));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final read = _read;
    if (read == null) return const Center(child: Text('Loading the queue.'));
    if (!read.ok) {
      return Center(
        child: TextButton(
          onPressed: _load,
          child: Text('${consoleReason(read.reason)} Retry'),
        ),
      );
    }
    final now = (widget.now ?? DateTime.now)();
    final cases = [
      for (final c in read.list('cases'))
        if (widget.kinds.contains(c['kind'])) c,
    ];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          if (_line case final line?)
            Padding(padding: const EdgeInsets.all(12), child: Text(line)),
          if (cases.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nothing is waiting.'),
            ),
          for (final c in cases)
            ListTile(
              key: ValueKey('console_case_${c['id']}'),
              title: Text(
                [
                  c['priority'],
                  c['kind'],
                  c['category'] ?? c['signal_kind'],
                ].whereType<String>().join(' · '),
              ),
              subtitle: Text(
                [
                  consoleDue(DateTime.tryParse('${c['sla_due_at']}'), now),
                  if (c['reports'] is int && (c['reports'] as int) > 1)
                    '${c['reports']} reports',
                  if (c['mine'] == true)
                    'yours'
                  else if (c['claimed'] == true)
                    'claimed',
                  if (c['gone'] == true) 'account deleted',
                ].join(' · '),
              ),
              trailing:
                  c['claimed'] == true
                      ? null
                      : TextButton(
                        onPressed: () => _claim('${c['id']}'),
                        child: const Text('Claim'),
                      ),
              onTap: () => widget.onOpen('${c['id']}'),
            ),
        ],
      ),
    );
  }
}
```

Create `lib/console/screens/case_screen.dart` with exactly (Task 9 adds the escalation):

```dart
// Spec 2 W7b (§6.4 Case, Appeals; §6.2, §6.3): one case as the server
// gives it: its reports (the text, the credibility note, the evidence),
// the person as others see them, prior cases, the safety families by name,
// an appeal's restriction. The actions: claim, dismiss, hold, lift a hold,
// restrict, ask for ID, confirm a minor (an underage_risk case), a note,
// and an appeal's accept or reject. Every action is the server's to allow;
// the page reads the case again after each. Never the reporter, never a
// special-category answer, never CSAM (the server sends none of them).
import 'package:attune/console/console_api.dart';
import 'package:attune/console/console_app.dart';
import 'package:flutter/material.dart';

/// §3.7's categories, in the console's order (a hold's or a restriction's).
const kConsoleCategories = [
  'underage_risk',
  'csam',
  'child_safety',
  'threat_to_life',
  'sextortion',
  'romance_scam',
  'threats',
  'entrapment',
  'harassment',
  'explicit_content',
  'impersonation',
  'hiding_relationship',
  'spam',
  'other',
];

class CaseScreen extends StatefulWidget {
  const CaseScreen({
    super.key,
    required this.api,
    required this.me,
    required this.caseId,
  });

  final ConsoleApi api;
  final ConsoleMe me;
  final String caseId;

  @override
  State<CaseScreen> createState() => _CaseScreenState();
}

class _CaseScreenState extends State<CaseScreen> {
  ConsoleAnswer? _read;
  String? _line;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.api('case', {'case_id': widget.caseId});
    if (mounted) setState(() => _read = r);
  }

  Future<void> _act(
    String action, [
    Map<String, Object?> extra = const {},
  ]) async {
    setState(() {
      _busy = true;
      _line = null;
    });
    final r = await widget.api(action, {'case_id': widget.caseId, ...extra});
    if (!mounted) return;
    setState(() {
      _busy = false;
      _line = r.ok ? 'Done.' : consoleReason(r.reason);
    });
    await _load();
  }

  Future<String?> _pickCategory(String title) => showDialog<String>(
    context: context,
    builder:
        (context) => SimpleDialog(
          title: Text(title),
          children: [
            for (final c in kConsoleCategories)
              SimpleDialogOption(
                key: ValueKey('console_category_$c'),
                onPressed: () => Navigator.of(context).pop(c),
                child: Text(c),
              ),
          ],
        ),
  );

  Future<void> _hold() async {
    final c = await _pickCategory('Hold: category');
    if (c != null) await _act('hold', {'category': c});
  }

  Future<void> _restrict() async {
    final chosen = await showDialog<(String, int?, String)>(
      context: context,
      builder: (context) => const _RestrictDialog(),
    );
    if (chosen == null) return;
    final (type, days, category) = chosen;
    await _act('restrict', {
      'type': type,
      'category': category,
      'ends_at':
          days == null
              ? null
              : DateTime.now()
                  .toUtc()
                  .add(Duration(days: days))
                  .toIso8601String(),
    });
  }

  Future<void> _note() async {
    final note = await showDialog<String>(
      context: context,
      builder: (context) => const _NoteDialog(),
    );
    if (note != null && note.trim().isNotEmpty) {
      await _act('note', {'note': note});
    }
  }

  @override
  Widget build(BuildContext context) {
    final read = _read;
    return Scaffold(
      appBar: AppBar(title: const Text('Case')),
      body: switch (read) {
        null => const Center(child: Text('Loading the case.')),
        ConsoleAnswer(ok: false) => Center(
          child: Text(
            consoleReason(read.reason),
            key: const ValueKey('console_case_refused'),
          ),
        ),
        _ => _case(context, read.data),
      },
    );
  }

  Widget _case(BuildContext context, Map<String, dynamic> data) {
    final theme = Theme.of(context);
    final c = Map<String, dynamic>.from(data['case'] as Map? ?? const {});
    final reports = [
      for (final r in (data['reports'] as List? ?? const []))
        if (r is Map) Map<String, dynamic>.from(r),
    ];
    final profile =
        data['profile'] is Map
            ? Map<String, dynamic>.from(data['profile'] as Map)
            : null;
    final appeal =
        data['appeal'] is Map
            ? Map<String, dynamic>.from(data['appeal'] as Map)
            : null;
    final open = c['state'] == 'open' || c['state'] == 'in_review';
    final underage = reports.any((r) => r['category'] == 'underage_risk');
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(text, style: theme.textTheme.titleMedium),
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          [
            c['priority'],
            c['kind'],
            c['state'],
            c['signal_kind'],
            c['outcome'],
          ].whereType<String>().join(' · '),
          style: theme.textTheme.titleLarge,
        ),
        if (c['gone'] == true) const Text('The account was deleted.'),
        if (_line case final line?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(line, key: const ValueKey('console_case_line')),
          ),
        if (reports.isNotEmpty) heading('Reports'),
        for (final r in reports)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${r['priority']} · ${r['category']} · ${r['state']}'),
                  if (r['details'] is String) Text('"${r['details']}"'),
                  if (r['reporter_triggered'] is String)
                    Text(
                      "The reporter's messages in this chat triggered: ${r['reporter_triggered']}",
                      key: ValueKey('console_credibility_${r['id']}'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  if (r['evidence'] is List)
                    ExpansionTile(
                      title: Text(
                        'Evidence (${(r['evidence'] as List).length} messages)',
                      ),
                      children: [
                        for (final m
                            in (r['evidence'] as List).whereType<Map>())
                          ListTile(
                            dense: true,
                            title: Text('${m['text']}'),
                            subtitle: Text('${m['from']} · ${m['at']}'),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        if (profile != null) ...[
          heading('As others see them'),
          Text(
            [
              profile['display_name'],
              profile['age'],
              profile['country'],
              profile['region'],
            ].where((v) => v != null).join(' · '),
          ),
          for (final p
              in (profile['prompts'] as List? ?? const []).whereType<Map>())
            Text('${p['prompt']}: ${p['answer']}'),
          Wrap(
            spacing: 8,
            children: [
              for (final p
                  in (profile['photos'] as List? ?? const []).whereType<Map>())
                if (p['url'] is String)
                  Image.network(
                    p['url'] as String,
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (_, __, ___) => const SizedBox(width: 120, height: 120),
                  ),
            ],
          ),
        ],
        if ((data['families'] as List? ?? const []).isNotEmpty) ...[
          heading('Safety families in the chat'),
          Text((data['families'] as List).join(', ')),
        ],
        if ((data['prior'] as List? ?? const []).isNotEmpty) ...[
          heading('Earlier cases (this account or number)'),
          for (final p in (data['prior'] as List).whereType<Map>())
            Text(
              '${p['kind']} · ${p['state']} · ${p['outcome'] ?? '-'} · ${p['created_at']}',
            ),
        ],
        if (appeal != null) ...[
          heading('Appeal'),
          Text(appeal['text'] is String ? '"${appeal['text']}"' : 'No text.'),
          if (appeal['restriction'] is Map)
            Text(
              'Restriction: ${(appeal['restriction'] as Map)['type']} · '
              '${(appeal['restriction'] as Map)['category']} · '
              'until ${(appeal['restriction'] as Map)['ends_at'] ?? 'closed for good'}',
            ),
        ],
        heading('Actions'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (open && c['kind'] != 'appeal') ...[
              if (c['mine'] != true)
                OutlinedButton(
                  onPressed: _busy ? null : () => _act('claim'),
                  child: const Text('Claim'),
                ),
              OutlinedButton(
                key: const ValueKey('console_dismiss'),
                onPressed: _busy ? null : () => _act('dismiss'),
                child: const Text('Dismiss'),
              ),
              OutlinedButton(
                key: const ValueKey('console_hold'),
                onPressed: _busy ? null : _hold,
                child: const Text('Hold'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _act('lift_hold'),
                child: const Text('Lift hold'),
              ),
              OutlinedButton(
                key: const ValueKey('console_restrict'),
                onPressed: _busy ? null : _restrict,
                child: const Text('Restrict'),
              ),
              OutlinedButton(
                key: const ValueKey('console_ask_id'),
                onPressed: _busy ? null : () => _act('ask_for_id'),
                child: const Text('Ask for ID'),
              ),
              if (underage)
                OutlinedButton(
                  key: const ValueKey('console_minor'),
                  onPressed: _busy ? null : () => _act('confirm_minor'),
                  child: const Text('Confirm a minor'),
                ),
            ],
            if (open && c['kind'] == 'appeal') ...[
              FilledButton(
                key: const ValueKey('console_appeal_accept'),
                onPressed:
                    _busy
                        ? null
                        : () => _act('decide_appeal', {'accept': true}),
                child: const Text('Accept appeal'),
              ),
              OutlinedButton(
                key: const ValueKey('console_appeal_reject'),
                onPressed:
                    _busy
                        ? null
                        : () => _act('decide_appeal', {'accept': false}),
                child: const Text('Reject appeal'),
              ),
            ],
            OutlinedButton(
              key: const ValueKey('console_add_note'),
              onPressed: _busy ? null : _note,
              child: const Text('Add a note'),
            ),
          ],
        ),
      ],
    );
  }
}

class _RestrictDialog extends StatefulWidget {
  const _RestrictDialog();

  @override
  State<_RestrictDialog> createState() => _RestrictDialogState();
}

class _RestrictDialogState extends State<_RestrictDialog> {
  String _type = 'suspended';
  int? _days = 7;
  String _category = 'harassment';

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Restrict'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButton<String>(
          key: const ValueKey('console_restrict_type'),
          value: _type,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 'suspended', child: Text('Suspend')),
            DropdownMenuItem(
              value: 'under_review',
              child: Text('A closer look (not shown)'),
            ),
          ],
          onChanged: (v) => setState(() => _type = v ?? _type),
        ),
        DropdownButton<int?>(
          key: const ValueKey('console_restrict_days'),
          value: _days,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 7, child: Text('7 days')),
            DropdownMenuItem(value: 30, child: Text('30 days')),
            DropdownMenuItem(value: 90, child: Text('90 days')),
            DropdownMenuItem(value: null, child: Text('For good')),
          ],
          onChanged: (v) => setState(() => _days = v),
        ),
        DropdownButton<String>(
          key: const ValueKey('console_restrict_category'),
          value: _category,
          isExpanded: true,
          items: [
            for (final c in kConsoleCategories)
              DropdownMenuItem(value: c, child: Text(c)),
          ],
          onChanged: (v) => setState(() => _category = v ?? _category),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('console_restrict_save'),
        onPressed: () => Navigator.of(context).pop((_type, _days, _category)),
        child: const Text('Restrict'),
      ),
    ],
  );
}

/// A note, its field owned by the dialog (disposed with it).
class _NoteDialog extends StatefulWidget {
  const _NoteDialog();

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add a note'),
    content: TextField(
      key: const ValueKey('console_note'),
      controller: _text,
      maxLength: 1000,
      maxLines: 4,
      decoration: const InputDecoration(
        helperText:
            "Never write someone's gender, faith or who they want to meet.",
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('console_note_save'),
        onPressed: () => Navigator.of(context).pop(_text.text),
        child: const Text('Save'),
      ),
    ],
  );
}
```

Create `lib/console/screens/console_lists.dart` with exactly:

```dart
// Spec 2 W7b (§6.4): the console's other pages. Photos waiting for a
// person (approve, or reject with a reason); verifications waiting for a
// person (the gesture photos beside the approved ones: pass, fail, ask for
// ID); S1 W9b's Opinions review queue v0 through its own RPCs (at-risk
// first; keep or escalate an at-risk item unless it breaks a rule on its
// own); countries (publishing is the safety owner's); the audit.
import 'dart:convert';

import 'package:attune/console/console_api.dart';
import 'package:attune/console/console_app.dart';
import 'package:flutter/material.dart';

/// Loads [action] once, and again after [act] or on demand.
abstract class _ListState<T extends StatefulWidget> extends State<T> {
  ConsoleAnswer? read;
  String? line;
  bool busy = false;

  ConsoleApi get api;
  String get action;
  Map<String, Object?> get params => const {};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final r = await api(action, params);
    if (mounted) setState(() => read = r);
  }

  Future<void> act(String action, Map<String, Object?> params) async {
    setState(() {
      busy = true;
      line = null;
    });
    final r = await api(action, params);
    if (!mounted) return;
    setState(() {
      busy = false;
      line = r.ok ? 'Done.' : consoleReason(r.reason);
    });
    await load();
  }

  Widget page(List<Widget> Function(ConsoleAnswer read) rows) {
    final r = read;
    if (r == null) return const Center(child: Text('Loading.'));
    if (!r.ok) {
      return Center(
        child: TextButton(
          onPressed: load,
          child: Text('${consoleReason(r.reason)} Retry'),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (line case final l?)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(l, key: const ValueKey('console_list_line')),
          ),
        ...rows(r),
      ],
    );
  }
}

Widget _image(Object? url) =>
    url is String
        ? Image.network(
          url,
          width: 120,
          height: 120,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox(width: 120, height: 120),
        )
        : const SizedBox(
          width: 120,
          height: 120,
          child: Center(child: Text('No image')),
        );

class PhotosScreen extends StatefulWidget {
  const PhotosScreen({super.key, required this.api});

  final ConsoleApi api;

  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends _ListState<PhotosScreen> {
  @override
  ConsoleApi get api => widget.api;

  @override
  String get action => 'photos';

  @override
  Widget build(BuildContext context) => page(
    (r) => [
      if (r.list('photos').isEmpty) const Text('No photo is waiting.'),
      for (final p in r.list('photos'))
        Card(
          key: ValueKey('console_photo_${p['id']}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _image(p['url']),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Photo ${p['position']} · ${p['reason'] ?? ''}'),
                ),
                FilledButton(
                  onPressed:
                      busy
                          ? null
                          : () => act('photo_decide', {
                            'photo_id': p['id'],
                            'approve': true,
                          }),
                  child: const Text('Approve'),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  key: ValueKey('console_photo_reject_${p['id']}'),
                  tooltip: 'Reject',
                  onSelected:
                      (reason) => act('photo_decide', {
                        'photo_id': p['id'],
                        'approve': false,
                        'reason': reason,
                      }),
                  itemBuilder:
                      (_) => [
                        for (final reason in const [
                          'face_unclear',
                          'too_small',
                          'contains_child',
                          'unsafe',
                        ])
                          PopupMenuItem(value: reason, child: Text(reason)),
                      ],
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Reject'),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class VerificationsScreen extends StatefulWidget {
  const VerificationsScreen({super.key, required this.api});

  final ConsoleApi api;

  @override
  State<VerificationsScreen> createState() => _VerificationsScreenState();
}

class _VerificationsScreenState extends _ListState<VerificationsScreen> {
  @override
  ConsoleApi get api => widget.api;

  @override
  String get action => 'verifications';

  @override
  Widget build(BuildContext context) => page(
    (r) => [
      if (r.list('sessions').isEmpty) const Text('No check is waiting.'),
      for (final s in r.list('sessions'))
        Card(
          key: ValueKey('console_session_${s['id']}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${s['step']} · ${s['kind']} · since ${s['since']}'),
                if (s['gestures'] is List)
                  Text('Gestures: ${(s['gestures'] as List).join(', ')}'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final u in (s['review'] as List? ?? const []))
                      _image(u),
                  ],
                ),
                const Text('Approved photos'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final p
                        in (s['photos'] as List? ?? const []).whereType<Map>())
                      _image(p['url']),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    if (s['step'] == 'human') ...[
                      FilledButton(
                        key: ValueKey('console_pass_${s['id']}'),
                        onPressed:
                            busy
                                ? null
                                : () => act('verification_decide', {
                                  'session_id': s['id'],
                                  'outcome': 'pass',
                                }),
                        child: const Text('Identity passes'),
                      ),
                      OutlinedButton(
                        onPressed:
                            busy
                                ? null
                                : () => act('verification_decide', {
                                  'session_id': s['id'],
                                  'outcome': 'fail',
                                }),
                        child: const Text('Identity fails'),
                      ),
                    ],
                    OutlinedButton(
                      onPressed:
                          busy
                              ? null
                              : () => act('verification_decide', {
                                'session_id': s['id'],
                                'outcome': 'ask_for_id',
                              }),
                      child: const Text('Ask for ID'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class OpinionsScreen extends StatefulWidget {
  const OpinionsScreen({super.key, required this.api});

  final ConsoleApi api;

  @override
  State<OpinionsScreen> createState() => _OpinionsScreenState();
}

class _OpinionsScreenState extends _ListState<OpinionsScreen> {
  @override
  ConsoleApi get api => widget.api;

  @override
  String get action => 'opinions_queue';

  @override
  Widget build(BuildContext context) => page(
    (r) => [
      const Text(
        "Opinions review queue v0. Someone may be at risk: keep the post or escalate it; remove it only when it breaks a rule on its own.",
      ),
      const SizedBox(height: 8),
      if (r.list('reports').isEmpty)
        const Text('No priority report is waiting.'),
      for (final p in r.list('reports'))
        Card(
          key: ValueKey('console_opinion_${p['report_id']}'),
          child: ListTile(
            title: Text('${p['reason']}'),
            subtitle: Text('${p['excerpt'] ?? ''}'),
            trailing:
                p['content_removed'] == true
                    ? const Text('Removed')
                    : TextButton(
                      onPressed:
                          busy
                              ? null
                              : () => act('opinions_remove', {
                                'type': p['content_type'],
                                'id': p['content_id'],
                              }),
                      child: const Text('Remove'),
                    ),
          ),
        ),
    ],
  );
}

class CountriesScreen extends StatefulWidget {
  const CountriesScreen({super.key, required this.api, required this.me});

  final ConsoleApi api;
  final ConsoleMe me;

  @override
  State<CountriesScreen> createState() => _CountriesScreenState();
}

class _CountriesScreenState extends _ListState<CountriesScreen> {
  final _country = TextEditingController();
  final _values = TextEditingController(text: '{}');

  @override
  ConsoleApi get api => widget.api;

  @override
  String get action => 'countries';

  @override
  void dispose() {
    _country.dispose();
    _values.dispose();
    super.dispose();
  }

  void _publish() {
    Object? values;
    try {
      values = jsonDecode(_values.text);
    } catch (_) {
      values = null;
    }
    if (values is! Map) {
      setState(() => line = consoleReason('invalid'));
      return;
    }
    act('publish_country', {
      'country': _country.text.trim().toUpperCase(),
      'values': values,
    });
  }

  @override
  Widget build(BuildContext context) => page(
    (r) => [
      for (final c in r.list('countries'))
        ListTile(
          key: ValueKey('console_country_${c['country']}'),
          title: Text('${c['country']} · tier ${c['tier']} · v${c['version']}'),
          subtitle: Text(
            'Dating ${c['dating_enabled'] == true ? 'on' : 'off'} · same gender '
            '${c['same_gender_enabled'] == true ? 'on' : 'off'} · regions ${c['open_regions'] ?? 'all'}',
          ),
        ),
      if (widget.me.owner) ...[
        const Divider(),
        const Text('Publish (safety owner)'),
        TextField(
          key: const ValueKey('console_country_code'),
          controller: _country,
          decoration: const InputDecoration(labelText: 'Country (GH)'),
        ),
        TextField(
          key: const ValueKey('console_country_values'),
          controller: _values,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Values (JSON)'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          key: const ValueKey('console_publish'),
          onPressed: busy ? null : _publish,
          child: const Text('Publish'),
        ),
      ],
    ],
  );
}

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key, required this.api});

  final ConsoleApi api;

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends _ListState<AuditScreen> {
  @override
  ConsoleApi get api => widget.api;

  @override
  String get action => 'audit';

  @override
  Map<String, Object?> get params => const {'limit': 200};

  @override
  Widget build(BuildContext context) => page(
    (r) => [
      for (final a in r.list('actions'))
        ListTile(
          dense: true,
          title: Text('${a['action']}${a['mine'] == true ? ' (you)' : ''}'),
          subtitle: Text('${a['at']} · ${a['detail']}'),
        ),
    ],
  );
}
```

Create `web/index.html` with exactly:

```html
<!DOCTYPE html>
<html>
<head>
  <!-- Spec 2 W7b (§6.4, F-6): the moderation console's page. The only web
       entry point is lib/console/main_console.dart; it is hosted as a
       private static site behind an access gate, never indexed. -->
  <base href="$FLUTTER_BASE_HREF">
  <meta charset="UTF-8">
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="robots" content="noindex, nofollow">
  <meta name="referrer" content="no-referrer">
  <title>Attune moderation</title>
</head>
<body>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>
```

Create `$D/edit_ci_T7.py` with exactly:

```python
#!/usr/bin/env python3
# Spec 2 W7b Task 7 (§6.4, F-6): CI builds the moderation console's web
# entry point (flutter build web -t lib/console/main_console.dart, to
# build/console), its own job, on every push.
import importlib.util

spec = importlib.util.spec_from_file_location('anchor', '.superpowers/sdd/2026-11-21-spec2-w7/anchor.py')
anchor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(anchor)

anchor.edit('.github/workflows/tests.yml', [(
    """  deno-w9:
""", """  console-web:
    # Spec 2 W7b (§6.4, F-6): the moderation console is a separate web entry
    # point that imports only lib/console and the Supabase client
    # (test/console/console_test.dart pins that). It must build for the web
    # on every push; the project's URL and key are --dart-define values the
    # owner passes at a real build, never committed.
    name: Moderation console web build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: 3.29.1
          channel: stable
          cache: true

      - name: Install dependencies
        run: flutter pub get

      - name: Build the console
        run: flutter build web -t lib/console/main_console.dart -o "$PWD/build/console" --no-pub

  deno-w9:
""")], 'W7b Task 7')
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
python3 -I $D/edit_ci_T7.py
dart format lib/console test/console 2>&1 | tail -1
flutter analyze --no-pub lib/console test/console 2>&1 | tail -1
flutter test --no-pub test/console 2>&1 | tr '\r' '\n' | grep -E '^[0-9:]+ \+[0-9]+' | tail -1 | grep -oE '\+[0-9]+( ~[0-9]+)?( -[0-9]+)?: (All tests passed!|Some tests failed\.)'
flutter build web -t lib/console/main_console.dart -o "$PWD/build/console" --no-pub > $D/web_build.txt 2>&1; echo "web build exit=$?"; ls build/console/main.dart.js
git check-ignore -q build/console && echo "build/console ignored"
```

Expected: `.github/workflows/tests.yml: 1 edit(s) (W7b Task 7)`; `Formatted 9 files (0 changed) in … seconds.`; `No issues found! (ran in …)`; `+8: All tests passed!`; `web build exit=0`; `build/console/main.dart.js`; `build/console ignored`.

- [ ] **Step 3: The mutants**

Create `$D/mut_T7_dart.py` with exactly:

```python
# Spec 2 W7b Task 7: Dart mutants (dmut.py) on the console.
T = ['test/console/console_test.dart']
Q = 'lib/console/screens/queue_screen.dart'
C = 'lib/console/screens/case_screen.dart'
L = 'lib/console/screens/console_lists.dart'
A = 'lib/console/console_app.dart'
MUTS = {
    'queue_ignores_kind': (Q, "        if (widget.kinds.contains(c['kind'])) c,", '        c,', T),
    'claim_wrong_case': (Q, "                        onPressed: () => _claim('${c['id']}'),", "                        onPressed: () => _claim('x'),", T),
    'case_not_read_again': (C, "      _line = r.ok ? 'Done.' : consoleReason(r.reason);\n    });\n    await _load();", "      _line = r.ok ? 'Done.' : consoleReason(r.reason);\n    });", T),
    'credibility_hidden': (C, "                  if (r['reporter_triggered'] is String)", "                  if (false)", T),
    'restrict_days_ignored': (C, '.add(Duration(days: days))', '.add(const Duration(days: 365))', T),
    'publish_for_anyone': (L, '      if (widget.me.owner) ...[', '      if (true) ...[', T),
    'whoami_before_aal2': (A, '    if (session == ConsoleSession.ready) {', '    if (true) {', T),
    'non_moderator_admitted': (A, '      } else {\n        line = consoleReason(r.reason);\n      }', "      } else {\n        me = const ConsoleMe(role: 'moderator', routing: false);\n      }", T),
    'reject_reason_dropped': (L, "                        'reason': reason,\n", '', T),
    'opinions_remove_report_id': (L, "                                'id': p['content_id'],", "                                'id': p['report_id'],", T),
}
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7; python3 -I $D/dmut.py $D/mut_T7_dart.py > $D/mut_T7_dart.txt 2>&1; tail -1 $D/mut_T7_dart.txt
```

Expected: `10/10 killed`.

- [ ] **Step 4: The W7b gate**

Run the race script only when the machine is idle (Task 4 Step 6).

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
$D/suite.sh attune_spec3a > $D/sql-W7b.txt; echo "$(grep -c '^PASS' $D/sql-W7b.txt) PASS, $(grep -c '^FAIL' $D/sql-W7b.txt) FAIL"
diff <(grep FAIL $D/sql-baseline.txt) <(grep FAIL $D/sql-W7b.txt)
flutter analyze --no-pub lib test > $D/analyze-W7b.txt 2>&1; tail -1 $D/analyze-W7b.txt
flutter test --no-pub --reporter compact > $D/flutter-W7b.txt 2>&1; tr '\r' '\n' < $D/flutter-W7b.txt | grep -E '^[0-9:]+ \+[0-9]+' | tail -1 | grep -oE '\+[0-9]+( ~[0-9]+)?( -[0-9]+)?: (All tests passed!|Some tests failed\.)'
shasum -c .superpowers/sdd/2026-11-04-spec1-w10-accessibility-docs/w10-1.0.sha | grep -vc ': OK$'; shasum -c .superpowers/sdd/2026-11-04-spec1-w9/flag_off.sha | grep -vc ': OK$'
shasum -c .superpowers/sdd/2026-11-07-spec2-w3/latch.sha; flutter test --no-pub test/architecture/games_untouched_test.dart 2>&1 | tr '\r' '\n' | tail -1 | grep -oE 'All tests passed!|Some tests failed\.'
(cd supabase/functions && eval "$(grep -m1 -oE 'deno test --allow-read [^"]*' ../../.github/workflows/tests.yml)" 2>&1 | grep -E 'passed|failed' | tail -1 | sed 's/\x1b\[[0-9;]*m//g')
uptime
dropdb --if-exists w7race 2>/dev/null; createdb w7race
pg_dump -s attune_spec3a | psql -X -q -d w7race > /dev/null 2>&1
pg_dump -a -t public.metric_key_prefixes -t public.feature_flags -t public.country_safety_config -t private.dating_calling_codes -t public.dating_algorithm_configs -t public.dating_safety_configs -t private.dating_phone_trunk_rules -t private.flag_production_gates attune_spec3a | psql -X -q -d w7race > /dev/null 2>&1
bash scripts/concurrency/dating_kill_switch_races.sh w7race > $D/race_W7b.txt 2>&1; grep -c '^PASS' $D/race_W7b.txt; grep -v '^PASS' $D/race_W7b.txt
dropdb w7race
```

Expected: `162 PASS, 14 FAIL`; no diff; `571 issues found. (ran in …)`; `+8649 -3: Some tests failed.` (+8 since W7a: the console's 8; the same three baseline failures); `0`; `0`; `lib/home/home_screen.dart: OK`; `All tests passed!`; `ok | 245 passed | 0 failed (…)`; the load (replay: 5.21); `42`, nothing else. The mutants: Tasks 5–7.

- [ ] **Step 5: Record the tree**

Do not commit; record the tree in the report.

---

## Batch W7c — escalation, the law-enforcement log, transparency, the runbook

### Task 8: Migration `dating_v2_escalations`: recorded escalations (never sent), the law-enforcement log, the transparency summary, the 2-year purge (§4.3, §4.8, §6.5, §6.6, §7.1; R-60, R-67)

**Files:**
- Create: `$D/{before_w7c/, mig_T8_head.sql, build_mig_W7c.py, contract_T8.sql, edit_tests_T8.py, mut_T8.py}`, `supabase/migrations/20261121120000_dating_v2_escalations.sql`, `supabase/migrations/20261121120010_dating_v2_escalations_grants.sql`
- Modify: `supabase/tests/dating_v2_moderation_contracts.sql` (N–P), `supabase/tests/{dating_rls_canary,service_role_grants_test}.sql`, `scripts/local_pg_grants.sql`

**Interfaces:**
- Consumes: Task 5's `private.dating_moderator`, `private.dating_case_for`, `private.dating_audit`; the live purge steps (re-created by Task 1).
- Produces: `dating_escalations`, `law_enforcement_requests`; `moderation_record_escalation(uuid, uuid, text, text)`, `moderation_le_requests(uuid)`, `moderation_record_le_request(uuid, uuid, jsonb)`, `moderation_transparency_summary(uuid, date, date)`, `private.dating_transparency_summary(date, date)`; purge steps `moderation_actions`, `escalations`, `law_enforcement_requests`.

- [ ] **Step 1: Save the live bodies the migration re-creates**

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7; mkdir -p $D/before_w7c
for sig in 'private.dating_purge_steps()' 'private.dating_purge_step(text,timestamp with time zone)'; do
  psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)" > "$D/before_w7c/$sig.sql"
done
ls $D/before_w7c | wc -l | tr -d ' '
```

Expected: `2`.

- [ ] **Step 2: Write the failing contract sections**

Create `$D/contract_T8.sql` with exactly (sections N–P; it ends with the end marker):

```sql
-- =====================================================================
-- N. (§6.5, §7.1 escalation rows) An escalation is a record of what a
--    person did, never an automatic send: the console records its kind
--    (CSA 292 only as the victim's-consent kind) and one audit row;
--    nothing that names the table makes a call, and no trigger sits on it.
-- =====================================================================
DO $n$
DECLARE
  v_mod constant uuid := pg_temp.ready('130');
  v_t constant uuid := pg_temp.man('131');
  v_r constant uuid := pg_temp.ready('132');
  v_case uuid;
  v_posts bigint := (SELECT count(*) FROM pg_temp.w7_posts);
  v_got text;
BEGIN
  INSERT INTO public.dating_moderators (user_id, role) VALUES (v_mod, 'moderator');
  PERFORM pg_temp.report(v_r, '132', pg_temp.match(v_t, v_r), 'sextortion');
  SELECT case_id INTO v_case FROM public.dating_reports WHERE reporter_user_id = v_r;
  v_got := public.moderation_record_escalation(v_mod, v_case, 'csa_292', NULL) ->> 'reason';
  v_got := v_got || ' ' || (public.moderation_record_escalation(v_mod, v_case, 'csa_292_with_consent', 'CSA-2026-0001') ->> 'ok');
  v_got := v_got || ' ' || (public.moderation_record_escalation(v_mod, gen_random_uuid(), 'police', NULL) ->> 'reason');
  IF v_got IS DISTINCT FROM 'invalid true case_unavailable'
     OR (SELECT kind || '/' || reference || '/' || recorded_by FROM public.dating_escalations WHERE case_id = v_case)
        IS DISTINCT FROM 'csa_292_with_consent/CSA-2026-0001/' || v_mod
     OR NOT EXISTS (SELECT 1 FROM public.dating_moderation_actions WHERE case_id = v_case AND action = 'escalation'
                       AND detail = '{"kind": "csa_292_with_consent"}'::jsonb) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recording an escalation read % or was not audited', v_got;
  END IF;
  IF (SELECT count(*) FROM pg_temp.w7_posts) <> v_posts
     OR EXISTS (SELECT 1 FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
                 WHERE n.nspname IN ('public', 'private') AND p.prosrc ~ 'dating_escalations'
                   AND p.prosrc ~ '(net\.http_post|invoke_edge_function|scheduled_notifications|pg_notify)')
     OR EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.dating_escalations'::regclass AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an escalation sends something by itself (§6.5: always a human decision)';
  END IF;
END $n$;

-- =====================================================================
-- O. (§6.4 Law-enforcement log, §6.6) The log is the safety owner's: a
--    moderator can't read it, record in it or read the summary; a request
--    is recorded pending, then decided (what was disclosed named; refused
--    and contested name nothing), the person's notice stamped once; bad
--    input names nothing; the audit holds the decision only.
-- =====================================================================
DO $o$
DECLARE
  v_mod constant uuid := pg_temp.ready('133');
  v_owner constant uuid := pg_temp.ready('134');
  v_t constant uuid := pg_temp.man('135');
  v jsonb;
  v_id uuid;
  v_got text;
BEGIN
  INSERT INTO public.dating_moderators (user_id, role) VALUES (v_mod, 'moderator');
  INSERT INTO public.dating_moderators (user_id, role, sensitive_routing_allowed) VALUES (v_owner, 'safety_owner', true);
  v_got := concat_ws(' ', public.moderation_le_requests(v_mod) ->> 'reason',
                          public.moderation_record_le_request(v_mod, NULL, '{}') ->> 'reason',
                          public.moderation_transparency_summary(v_mod, '2026-07-01', '2026-10-01') ->> 'reason');
  IF v_got IS DISTINCT FROM 'safety_owner_only safety_owner_only safety_owner_only' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a moderator reached the law-enforcement log: %', v_got;
  END IF;
  v := public.moderation_record_le_request(v_owner, NULL, jsonb_build_object(
         'received_at', '2026-11-20T09:00:00Z', 'jurisdiction', 'GH', 'legal_basis', 'Court order 12/2026',
         'scope', 'Account details of one user', 'target_user_id', v_t));
  v_id := (v ->> 'id')::uuid;
  IF (v ->> 'ok')::boolean IS NOT TRUE
     OR (SELECT decision || '/' || (decided_at IS NULL) || '/' || target_user_id FROM public.law_enforcement_requests WHERE id = v_id)
        IS DISTINCT FROM 'pending/true/' || v_t THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recording a request read %', v;
  END IF;
  v_got := concat_ws(' ',
    public.moderation_record_le_request(v_owner, v_id, '{"decision": "disclosed"}') ->> 'reason',
    public.moderation_record_le_request(v_owner, v_id, '{"decision": "refused", "disclosed_categories": ["profile"]}') ->> 'reason',
    public.moderation_record_le_request(v_owner, v_id, '{"decision": "disclosed", "disclosed_categories": ["gps"]}') ->> 'reason',
    public.moderation_record_le_request(v_owner, NULL, '{"received_at": "2026-11-20", "jurisdiction": "Ghana", "legal_basis": "x", "scope": "y"}') ->> 'reason',
    public.moderation_record_le_request(v_owner, NULL, '{"received_at": "soon", "jurisdiction": "GH", "legal_basis": "x", "scope": "y"}') ->> 'reason');
  IF v_got IS DISTINCT FROM 'invalid invalid invalid invalid invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: bad decisions or input read %', v_got;
  END IF;
  v := public.moderation_record_le_request(v_owner, v_id,
         '{"decision": "partly_disclosed", "disclosed_categories": ["account", "restrictions"], "user_notified": true}');
  IF (v ->> 'ok')::boolean IS NOT TRUE
     OR (SELECT decision || '/' || array_to_string(disclosed_categories, ',') || '/' || (decided_by = v_owner)
                || '/' || (user_notified_at IS NOT NULL)
           FROM public.law_enforcement_requests WHERE id = v_id) IS DISTINCT FROM 'partly_disclosed/account,restrictions/true/true'
     OR jsonb_array_length(public.moderation_le_requests(v_owner) -> 'requests') < 1
     OR EXISTS (SELECT 1 FROM public.dating_moderation_actions WHERE action = 'law_enforcement_request'
                   AND actor_id = v_owner AND detail - 'decision' <> '{}'::jsonb) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: deciding a request read %, or the audit holds more than the decision', v;
  END IF;
  PERFORM pg_temp.delete_account(v_t);
  IF (SELECT target_user_id FROM public.law_enforcement_requests WHERE id = v_id) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the log kept a deleted account''s id';
  END IF;
END $o$;

-- =====================================================================
-- P. (§6.6, §4.8) The transparency summary counts exactly what fell in
--    its window (requests by country and decision, those met, reports by
--    category, actions, appeals, overturned; nothing carried, no names);
--    the purge removes the audit, escalations and the log at 2 years.
-- =====================================================================
DO $p$
DECLARE
  v_owner constant uuid := pg_temp.ready('136');
  v_a constant uuid := pg_temp.man('137');
  v_b constant uuid := pg_temp.man('138');
  v_r1 uuid;
  v_r2 uuid;
  v jsonb;
  v_n bigint;
BEGIN
  INSERT INTO public.dating_moderators (user_id, role, sensitive_routing_allowed) VALUES (v_owner, 'safety_owner', true);
  INSERT INTO public.law_enforcement_requests (received_at, jurisdiction, legal_basis, scope, decision, disclosed_categories,
                                               decided_at, decided_by)
  VALUES ('2026-08-01', 'GH', 'order', 'one account', 'disclosed', '{account}', '2026-08-02', v_owner),
         ('2026-08-05', 'GH', 'letter', 'all chats', 'refused', '{}', '2026-08-06', v_owner),
         ('2026-09-01', 'GB', 'warrant', 'one account', 'partly_disclosed', '{account,reports}', '2026-09-02', v_owner),
         ('2026-10-02', 'GB', 'warrant', 'outside', 'refused', '{}', '2026-10-03', v_owner);
  INSERT INTO public.dating_reports (category, created_at) VALUES
    ('harassment', '2026-07-10'), ('harassment', '2026-07-11'), ('spam', '2026-09-30'), ('spam', '2026-06-30');
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, created_at, starts_at, ends_at)
  VALUES (v_a, 'suspended', 'harassment', 'moderator', '2026-08-01', '2026-08-01', '2026-08-15') RETURNING id INTO v_r1;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, created_at, starts_at, ends_at)
  VALUES (v_b, 'moderation_hold', 'csam', 'report', '2026-08-03', '2026-08-03', '2026-08-04') RETURNING id INTO v_r2;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, created_at, starts_at, ends_at, carried_from)
  VALUES (v_b, 'suspended', 'spam', 'carried_over', '2026-08-04', '2026-08-04', '2026-08-05', gen_random_uuid());
  INSERT INTO public.dating_appeals (restriction_id, user_id, submitted_at, state, decided_by, decided_at)
  VALUES (v_r1, v_a, '2026-08-02', 'accepted', v_owner, '2026-08-03'),
         (v_r2, v_b, '2026-08-04', 'rejected', v_owner, '2026-08-05');
  v := public.moderation_transparency_summary(v_owner, '2026-07-01', '2026-10-01');
  IF v -> 'summary' IS DISTINCT FROM jsonb_build_object(
       'from', '2026-07-01', 'to', '2026-10-01',
       'requests', '{"GB": {"partly_disclosed": 1}, "GH": {"refused": 1, "disclosed": 1}}'::jsonb,
       'requests_met', 2,
       'reports', '{"spam": 1, "harassment": 2}'::jsonb,
       'actions', '{"suspended": 1, "moderation_hold": 1}'::jsonb,
       'appeals', 2, 'overturned', 1)
     OR public.moderation_transparency_summary(v_owner, '2026-10-01', '2026-07-01') ->> 'reason' IS DISTINCT FROM 'invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the transparency summary read %', v;
  END IF;
  -- The purge: 2 years for the audit, escalations and the log.
  INSERT INTO public.law_enforcement_requests (received_at, jurisdiction, legal_basis, scope)
  VALUES (now() - interval '2 years 1 day', 'GH', 'old', 'old'), (now() - interval '1 year', 'GH', 'kept', 'kept');
  INSERT INTO public.dating_escalations (kind, recorded_by, recorded_at)
  VALUES ('police', v_owner, now() - interval '2 years 1 day'), ('iwf', v_owner, now() - interval '1 year');
  ALTER TABLE public.dating_moderation_actions DISABLE TRIGGER dating_moderation_actions_append_only;
  INSERT INTO public.dating_moderation_actions (actor_id, action, created_at)
  VALUES (v_owner, 'note', now() - interval '2 years 1 day'), (v_owner, 'claim', now() - interval '1 year');
  ALTER TABLE public.dating_moderation_actions ENABLE TRIGGER dating_moderation_actions_append_only;
  v := public.purge_dating_retention(now());
  IF EXISTS (SELECT 1 FROM public.law_enforcement_requests WHERE legal_basis = 'old')
     OR NOT EXISTS (SELECT 1 FROM public.law_enforcement_requests WHERE legal_basis = 'kept')
     OR EXISTS (SELECT 1 FROM public.dating_escalations WHERE kind = 'police' AND recorded_by = v_owner)
     OR NOT EXISTS (SELECT 1 FROM public.dating_escalations WHERE kind = 'iwf' AND recorded_by = v_owner)
     OR EXISTS (SELECT 1 FROM public.dating_moderation_actions WHERE actor_id = v_owner AND action = 'note')
     OR NOT EXISTS (SELECT 1 FROM public.dating_moderation_actions WHERE actor_id = v_owner AND action = 'claim')
     OR v ->> 'moderation_actions' IS NULL OR (v ->> 'moderation_actions') LIKE 'failed%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge read % (2 years for the audit, escalations and the log)', v;
  END IF;
END $p$;

-- @@W7-END@@
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
python3 -I $D/splice.py supabase/tests/dating_v2_moderation_contracts.sql '-- @@W7C@@' $D/contract_T8.sql
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_moderation_contracts.sql 2>&1 | grep -m1 -oE 'ERROR: .*'
```

Expected: `ERROR:  function public.moderation_record_escalation(uuid, uuid, unknown, unknown) does not exist`.

- [ ] **Step 3: The migration and its grants**

Create `$D/mig_T8_head.sql` with exactly:

```sql
-- ---------------------------------------------------------------------
-- 1. Escalations (§4.3, §6.5): a record of what a person did, never a
--    send. No trigger, no queue, no HTTP call reads this table; sextortion
--    to CSA 292 is recorded only with the victim's consent (its own kind).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.dating_escalations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id uuid REFERENCES public.dating_moderation_cases (id) ON DELETE SET NULL,
  kind text NOT NULL CHECK (kind IN ('police', 'ncmec', 'iwf', 'csa', 'csa_292_with_consent')),
  recorded_by uuid NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  reference text CHECK (reference IS NULL OR char_length(reference) BETWEEN 1 AND 200)
);
CREATE INDEX IF NOT EXISTS dating_escalations_case_idx ON public.dating_escalations (case_id);
ALTER TABLE public.dating_escalations ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------
-- 2. The law-enforcement request log (§4.3, §6.6): every request and its
--    decision, by the safety owner.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.law_enforcement_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  received_at timestamptz NOT NULL,
  jurisdiction text NOT NULL CHECK (jurisdiction ~ '^[A-Z]{2}$'),
  legal_basis text NOT NULL CHECK (char_length(legal_basis) BETWEEN 1 AND 300),
  scope text NOT NULL CHECK (char_length(scope) BETWEEN 1 AND 500),
  emergency boolean NOT NULL DEFAULT false,
  target_user_id uuid REFERENCES public.users (id) ON DELETE SET NULL,
  decision text NOT NULL DEFAULT 'pending'
    CHECK (decision IN ('pending', 'disclosed', 'partly_disclosed', 'refused', 'contested')),
  disclosed_categories text[] NOT NULL DEFAULT '{}'
    CHECK (disclosed_categories <@ ARRAY['account', 'profile', 'messages', 'reports', 'restrictions', 'verification']::text[]),
  user_notified_at timestamptz,
  decided_by uuid,
  decided_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((decision IN ('disclosed', 'partly_disclosed')) = (cardinality(disclosed_categories) > 0)),
  CHECK ((decision = 'pending') = (decided_at IS NULL))
);
CREATE INDEX IF NOT EXISTS law_enforcement_requests_received_idx ON public.law_enforcement_requests (received_at);
ALTER TABLE public.law_enforcement_requests ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------
-- 3. The console's escalation, the log and the transparency summary.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.moderation_record_escalation(p_actor uuid, p_case uuid, p_kind text, p_reference text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  c public.dating_moderation_cases;
  v_ref constant text := NULLIF(btrim(coalesce(p_reference, '')), '');
BEGIN
  IF v_mod.user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  IF p_kind IS NULL OR p_kind NOT IN ('police', 'ncmec', 'iwf', 'csa', 'csa_292_with_consent')
     OR coalesce(char_length(v_ref), 0) > 200 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  c := private.dating_case_for(v_mod, p_case);
  IF c.id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
  END IF;
  INSERT INTO public.dating_escalations (case_id, kind, recorded_by, reference) VALUES (c.id, p_kind, p_actor, v_ref);
  PERFORM private.dating_audit(p_actor, c.id, 'escalation', c.target_user_id, pg_catalog.jsonb_build_object('kind', p_kind));
  RETURN pg_catalog.jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.moderation_le_requests(p_actor uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
BEGIN
  IF v_mod.user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  IF v_mod.role <> 'safety_owner' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'safety_owner_only');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'requests', coalesce((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id', r.id, 'received_at', r.received_at,
             'jurisdiction', r.jurisdiction, 'legal_basis', r.legal_basis, 'scope', r.scope, 'emergency', r.emergency,
             'decision', r.decision, 'disclosed_categories', to_jsonb(r.disclosed_categories),
             'user_notified_at', r.user_notified_at, 'decided_at', r.decided_at) ORDER BY r.received_at DESC)
      FROM public.law_enforcement_requests AS r), '[]'::jsonb));
END;
$$;

-- A request as received (pending), or its decision; the safety owner only.
CREATE OR REPLACE FUNCTION public.moderation_record_le_request(p_actor uuid, p_request uuid, p_values jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  v_id uuid;
  v_decision text := coalesce(p_values ->> 'decision', 'pending');
  v_cats text[];
BEGIN
  IF v_mod.user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  IF v_mod.role <> 'safety_owner' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'safety_owner_only');
  END IF;
  IF p_values IS NULL OR jsonb_typeof(p_values) <> 'object' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  BEGIN
    v_cats := ARRAY(SELECT jsonb_array_elements_text(coalesce(p_values -> 'disclosed_categories', '[]'::jsonb)));
    IF p_request IS NULL THEN
      INSERT INTO public.law_enforcement_requests (received_at, jurisdiction, legal_basis, scope, emergency, target_user_id,
                                                   decision, disclosed_categories, decided_by, decided_at)
      VALUES ((p_values ->> 'received_at')::timestamptz, p_values ->> 'jurisdiction', p_values ->> 'legal_basis',
              p_values ->> 'scope', coalesce((p_values ->> 'emergency')::boolean, false),
              (SELECT u.id FROM public.users AS u WHERE u.id = (p_values ->> 'target_user_id')::uuid),
              v_decision, v_cats, CASE WHEN v_decision <> 'pending' THEN p_actor END,
              CASE WHEN v_decision <> 'pending' THEN now() END)
      RETURNING id INTO v_id;
    ELSE
      UPDATE public.law_enforcement_requests AS r
         SET decision = v_decision, disclosed_categories = v_cats,
             decided_by = CASE WHEN v_decision <> 'pending' THEN p_actor END,
             decided_at = CASE WHEN v_decision <> 'pending' THEN now() END,
             user_notified_at = CASE WHEN (p_values ->> 'user_notified')::boolean THEN coalesce(r.user_notified_at, now())
                                     ELSE r.user_notified_at END
       WHERE r.id = p_request
      RETURNING r.id INTO v_id;
      IF v_id IS NULL THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
      END IF;
    END IF;
  EXCEPTION WHEN check_violation OR not_null_violation OR invalid_text_representation OR datetime_field_overflow
               OR invalid_datetime_format THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END;
  PERFORM private.dating_audit(p_actor, NULL, 'law_enforcement_request', NULL,
    pg_catalog.jsonb_build_object('decision', v_decision));
  RETURN pg_catalog.jsonb_build_object('ok', true, 'id', v_id);
END;
$$;

-- §6.6: the quarterly transparency summary over [p_from, p_to): requests
-- by country and decision (and how many were met in whole or part),
-- reports by category, actions taken, appeals and how many were
-- overturned. Counts only; no person, no case.
CREATE OR REPLACE FUNCTION private.dating_transparency_summary(p_from date, p_to date)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH w AS (SELECT p_from::timestamptz AS lo, p_to::timestamptz AS hi)
  SELECT pg_catalog.jsonb_build_object(
    'from', p_from, 'to', p_to,
    'requests', coalesce((SELECT pg_catalog.jsonb_object_agg(x.jurisdiction, x.decisions)
                            FROM (SELECT r.jurisdiction, pg_catalog.jsonb_object_agg(r.decision, r.n) AS decisions
                                    FROM (SELECT q.jurisdiction, q.decision, count(*) AS n
                                            FROM public.law_enforcement_requests AS q, w
                                           WHERE q.received_at >= w.lo AND q.received_at < w.hi
                                           GROUP BY 1, 2) AS r
                                   GROUP BY r.jurisdiction) AS x), '{}'::jsonb),
    'requests_met', (SELECT count(*) FROM public.law_enforcement_requests AS q, w
                      WHERE q.received_at >= w.lo AND q.received_at < w.hi
                        AND q.decision IN ('disclosed', 'partly_disclosed')),
    'reports', coalesce((SELECT pg_catalog.jsonb_object_agg(x.category, x.n)
                           FROM (SELECT r.category, count(*) AS n FROM public.dating_reports AS r, w
                                  WHERE r.created_at >= w.lo AND r.created_at < w.hi GROUP BY 1) AS x), '{}'::jsonb),
    'actions', coalesce((SELECT pg_catalog.jsonb_object_agg(x.restriction_type, x.n)
                           FROM (SELECT a.restriction_type, count(*) AS n FROM public.dating_account_restrictions AS a, w
                                  WHERE a.created_at >= w.lo AND a.created_at < w.hi AND a.source <> 'carried_over'
                                  GROUP BY 1) AS x), '{}'::jsonb),
    'appeals', (SELECT count(*) FROM public.dating_appeals AS a, w WHERE a.submitted_at >= w.lo AND a.submitted_at < w.hi),
    'overturned', (SELECT count(*) FROM public.dating_appeals AS a, w
                    WHERE a.submitted_at >= w.lo AND a.submitted_at < w.hi AND a.state = 'accepted'));
$$;

CREATE OR REPLACE FUNCTION public.moderation_transparency_summary(p_actor uuid, p_from date, p_to date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
BEGIN
  IF v_mod.user_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  IF v_mod.role <> 'safety_owner' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'safety_owner_only');
  END IF;
  IF p_from IS NULL OR p_to IS NULL OR p_to <= p_from OR p_to - p_from > 366 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'summary', private.dating_transparency_summary(p_from, p_to));
END;
$$;
```

Create `$D/build_mig_W7c.py` with exactly:

```python
#!/usr/bin/env python3
"""Spec 2 W7c: builds supabase/migrations/20261121120000_dating_v2_escalations.sql
from mig_T8_head.sql, the purge's two functions re-created from their LIVE
bodies (saved to before_w7c/ before the migration is applied) with only
the lines marked "-- Spec 2 W7c" changed, and the self-revoke tail. Every
anchor must occur exactly once."""
import pathlib

D = pathlib.Path('.superpowers/sdd/2026-11-21-spec2-w7')
B = D / 'before_w7c'
T = 'Spec 2 W7c'

EDITS = {
    # §4.8: moderation actions, escalations and the law-enforcement log at
    # 2 years.
    'private.dating_purge_steps()': [
        ("""               'session_context'];
""", f"""               'session_context', 'moderation_actions', 'escalations', 'law_enforcement_requests']; -- {T}
"""),
    ],
    'private.dating_purge_step(text,timestamp with time zone)': [
        ("""        DELETE FROM public.dating_session_context AS c WHERE c.checked_at < p_now - interval '30 days';
      END CASE;
""", f"""        DELETE FROM public.dating_session_context AS c WHERE c.checked_at < p_now - interval '30 days';
      -- {T} (§4.8): the audit at 2 years: the append-only guard lets only
      -- {T} this step's delete through, and only rows 2 years old.
      WHEN 'moderation_actions' THEN -- {T}
        PERFORM pg_catalog.set_config('attune.dating_audit_purge', 'on', true); -- {T}
        DELETE FROM public.dating_moderation_actions AS a WHERE a.created_at < p_now - interval '2 years'; -- {T}
      WHEN 'escalations' THEN -- {T}
        DELETE FROM public.dating_escalations AS e WHERE e.recorded_at < p_now - interval '2 years'; -- {T}
      WHEN 'law_enforcement_requests' THEN -- {T}
        DELETE FROM public.law_enforcement_requests AS r WHERE r.received_at < p_now - interval '2 years'; -- {T}
      END CASE;
"""),
    ],
}

HEADER = """-- Spec 2 W7c (§4.3, §4.8, §4.9 W7c, §6.5, §6.6, §7.1): escalations, the
-- law-enforcement request log, the transparency summary.
--   * dating_escalations: what a person did (police, NCMEC, IWF, Ghana's
--     CSA, CSA 292 with the victim's consent), never an automatic send:
--     nothing here, and nothing reading this table, makes a call.
--   * law_enforcement_requests: every request and its decision, recorded
--     and read by the safety owner only.
--   * The transparency summary (§6.6): requests by country and decision,
--     how many were met, reports by category, actions taken, appeals and
--     how many were overturned; counts only.
--   * The purge: moderation actions, escalations and the request log at 2
--     years (§4.8).
-- Nothing here turns a flag on. Grants in
-- 20261121120010_dating_v2_escalations_grants.sql; this file revokes what
-- it creates from every API role first.
"""

TAIL = """
-- ---------------------------------------------------------------------
-- 5. Self-revoke (the W6 final pattern).
-- ---------------------------------------------------------------------
REVOKE ALL ON TABLE public.dating_escalations, public.law_enforcement_requests
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  public.moderation_record_escalation(uuid, uuid, text, text), public.moderation_le_requests(uuid),
  public.moderation_record_le_request(uuid, uuid, jsonb), private.dating_transparency_summary(date, date),
  public.moderation_transparency_summary(uuid, date, date)
  FROM PUBLIC, anon, authenticated, service_role;
"""


def edited(sig):
    text = (B / f'{sig}.sql').read_text().rstrip('\n')
    for old, new in EDITS[sig]:
        n = text.count(old)
        assert n == 1, f'{sig}: anchor occurs {n} times: {old[:70]!r}'
        text = text.replace(old, new)
    return text + ';\n'


body = (HEADER + 'BEGIN;\nSET LOCAL lock_timeout = \'5s\';\n\n' + (D / 'mig_T8_head.sql').read_text()
        + '\n-- ---------------------------------------------------------------------\n'
        + '-- 4. The purge, re-created from its live body; only the lines marked\n'
        + '--    "-- Spec 2 W7c" change.\n'
        + '-- ---------------------------------------------------------------------\n'
        + '\n'.join(edited(s) for s in EDITS) + TAIL + '\nCOMMIT;\n')
out = pathlib.Path('supabase/migrations/20261121120000_dating_v2_escalations.sql')
out.write_text(body)
print(f'{out}: {len(EDITS)} re-created function(s), {body.count(chr(10))} lines')
```

Create `supabase/migrations/20261121120010_dating_v2_escalations_grants.sql` with exactly:

```sql
-- Spec 2 W7c: grants for 20261121120000_dating_v2_escalations.sql. The
-- escalations and the law-enforcement log are no API role's; the console's
-- three functions are the service role's alone (the dating-moderation edge
-- function's; the database refuses all but the safety owner on the log and
-- the summary); the summary's query is the database's own.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON TABLE public.dating_escalations FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.law_enforcement_requests FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_transparency_summary(date, date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.moderation_record_escalation(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_record_escalation(uuid, uuid, text, text) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_le_requests(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_le_requests(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_record_le_request(uuid, uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_record_le_request(uuid, uuid, jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_transparency_summary(uuid, date, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_transparency_summary(uuid, date, date) TO service_role;
COMMIT;
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
python3 -I $D/build_mig_W7c.py
for f in supabase/migrations/20261121120000_dating_v2_escalations.sql supabase/migrations/20261121120010_dating_v2_escalations_grants.sql; do
  for run in 1 2; do psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $f > /dev/null 2> $D/apply_err.txt; rc=$?; echo "$(basename $f) run $run exit=$rc"; grep -v NOTICE $D/apply_err.txt || true; done
done
python3 -I $D/marked_diff.py $D/before_w7c attune_spec3a 'Spec 2 W7c'; echo "marked_diff exit=$?"
python3 -I $D/grants_line.py supabase/migrations/20261121110010_dating_v2_moderation_console_grants.sql 'Spec 2 W7c: escalations, the law-enforcement log (twin of 20261121120000)' supabase/migrations/20261121120010_dating_v2_escalations_grants.sql
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_moderation_contracts.sql 2>&1 | tail -1
```

Expected: `supabase/migrations/20261121120000_dating_v2_escalations.sql: 2 re-created function(s), 401 lines`; four `exit=0` lines; `private.dating_purge_step(text,timestamp with time zone): 9 added line(s), 0 removed OK`, `private.dating_purge_steps(): 1 added line(s), 1 removed OK`, `marked_diff exit=0`; `local_pg_grants.sql: one \i block added`; `psql:supabase/tests/dating_v2_moderation_contracts.sql:1574: NOTICE:  dating_v2_moderation_contracts: all held`.

- [ ] **Step 4: The existing contracts meet W7c**

Create `$D/edit_tests_T8.py` with exactly:

```python
#!/usr/bin/env python3
# Spec 2 W7c Task 8: the canary takes the escalations and the
# law-enforcement log (no API role's), the console's three functions (the
# service role's alone) and the summary's query (the database's own); the
# service-role test lists the two tables.
import importlib.util

spec = importlib.util.spec_from_file_location('anchor', '.superpowers/sdd/2026-11-21-spec2-w7/anchor.py')
anchor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(anchor)

anchor.edit('supabase/tests/dating_rls_canary.sql', [(
    """-- @@W7C-CANARY@@
""", """-- Spec 2 W7c Task 8: escalations and the law-enforcement log.
INSERT INTO allowed_rel (name, authenticated, service_dml) VALUES
  ('dating_escalations', '', ''),
  ('law_enforcement_requests', '', '');
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('moderation_record_escalation(uuid,uuid,text,text)', '', 'service_role'),
  ('moderation_le_requests(uuid)', '', 'service_role'),
  ('moderation_record_le_request(uuid,uuid,jsonb)', '', 'service_role'),
  ('moderation_transparency_summary(uuid,date,date)', '', 'service_role'),
  ('private.dating_transparency_summary(date,date)', '', '');
""")], 'W7c Task 8')

for old in ("""                          'dating_moderators', 'dating_moderation_actions')
    AND NOT has_table_privilege('service_role', c.oid, 'SELECT');""",
            """                          'dating_moderators', 'dating_moderation_actions')
    -- Spec 2 W1b (batch-4 fix round 1, C-1): the service role only reads"""):
    new = old.replace("""                          'dating_moderators', 'dating_moderation_actions')""",
                      """                          'dating_moderators', 'dating_moderation_actions',
                          -- Spec 2 W7c: escalations and the law-enforcement log.
                          'dating_escalations', 'law_enforcement_requests')""")
    anchor.edit('supabase/tests/service_role_grants_test.sql', [(old, new)], 'W7c Task 8')
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
python3 -I $D/edit_tests_T8.py
$D/suite.sh attune_spec3a > $D/sql-after-T8.txt; echo "$(grep -c '^PASS' $D/sql-after-T8.txt) PASS, $(grep -c '^FAIL' $D/sql-after-T8.txt) FAIL"
diff <(grep FAIL $D/sql-baseline.txt) <(grep FAIL $D/sql-after-T8.txt)
```

Expected: `dating_rls_canary.sql: 1 edit(s) (W7c Task 8)`, `service_role_grants_test.sql: 1 edit(s) (W7c Task 8)` twice; `162 PASS, 14 FAIL`; no diff.

- [ ] **Step 5: The mutants**

Create `$D/mut_T8.py` with exactly:

```python
# Spec 2 W7c Task 8 mutants (mutate.py on 20261121120000_dating_v2_escalations.sql):
# each must make dating_v2_moderation_contracts.sql fail with a CONTRACT VIOLATED line.
MUTS = {
    'escalation_sends': ("  INSERT INTO public.dating_escalations (case_id, kind, recorded_by, reference) VALUES (c.id, p_kind, p_actor, v_ref);",
                         "  INSERT INTO public.dating_escalations (case_id, kind, recorded_by, reference) VALUES (c.id, p_kind, p_actor, v_ref);\n  PERFORM net.http_post(url := 'https://police.invalid/report', body := '{}'::jsonb);"),
    # The function's check; the table's own CHECK still refuses the row, so
    # the contract fails with that error (a kill, the one line that is not
    # CONTRACT VIOLATED).
    'csa_292_without_consent': ("  IF p_kind IS NULL OR p_kind NOT IN ('police', 'ncmec', 'iwf', 'csa', 'csa_292_with_consent')",
                                "  IF p_kind IS NULL OR p_kind NOT IN ('police', 'ncmec', 'iwf', 'csa', 'csa_292_with_consent', 'csa_292')"),
    'log_open_to_moderators': ('MULTI', [
        ("""  IF v_mod.role <> 'safety_owner' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'safety_owner_only');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'requests', coalesce((""",
         """  RETURN pg_catalog.jsonb_build_object('ok', true, 'requests', coalesce((""")]),
    'record_open_to_moderators': ('MULTI', [
        ("""  IF v_mod.role <> 'safety_owner' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'safety_owner_only');
  END IF;
  IF p_values IS NULL OR jsonb_typeof(p_values) <> 'object' THEN""",
         """  IF p_values IS NULL OR jsonb_typeof(p_values) <> 'object' THEN""")]),
    'summary_open_to_moderators': ('MULTI', [
        ("""  IF v_mod.role <> 'safety_owner' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'safety_owner_only');
  END IF;
  IF p_from IS NULL""", """  IF p_from IS NULL""")]),
    'audit_names_country': ("    pg_catalog.jsonb_build_object('decision', v_decision));",
                            "    pg_catalog.jsonb_build_object('decision', v_decision, 'jurisdiction', p_values ->> 'jurisdiction'));"),
    'summary_counts_carried': ("                                  WHERE a.created_at >= w.lo AND a.created_at < w.hi AND a.source <> 'carried_over'",
                               "                                  WHERE a.created_at >= w.lo AND a.created_at < w.hi"),
    'met_counts_refused': ("                        AND q.decision IN ('disclosed', 'partly_disclosed')),",
                           "                        AND q.decision <> 'pending'),"),
    'overturned_counts_all': ("                    WHERE a.submitted_at >= w.lo AND a.submitted_at < w.hi AND a.state = 'accepted'));",
                              "                    WHERE a.submitted_at >= w.lo AND a.submitted_at < w.hi));"),
    'purge_keeps_audit': ("        DELETE FROM public.dating_moderation_actions AS a WHERE a.created_at < p_now - interval '2 years'; -- Spec 2 W7c",
                          "        DELETE FROM public.dating_moderation_actions AS a WHERE false; -- Spec 2 W7c"),
    'purge_keeps_escalations': ("        DELETE FROM public.dating_escalations AS e WHERE e.recorded_at < p_now - interval '2 years'; -- Spec 2 W7c",
                                "        DELETE FROM public.dating_escalations AS e WHERE false; -- Spec 2 W7c"),
    'purge_log_one_year': ("        DELETE FROM public.law_enforcement_requests AS r WHERE r.received_at < p_now - interval '2 years'; -- Spec 2 W7c",
                           "        DELETE FROM public.law_enforcement_requests AS r WHERE r.received_at < p_now - interval '11 months'; -- Spec 2 W7c"),
}
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
python3 -I $D/mutate.py supabase/migrations/20261121120000_dating_v2_escalations.sql supabase/tests/dating_v2_moderation_contracts.sql $D/mut_T8.py $D/mut supabase/migrations/20261121120010_dating_v2_escalations_grants.sql > $D/mut_T8.txt 2>&1
grep -c 'CONTRACT VIOLATED' $D/mut_T8.txt; grep -v 'CONTRACT VIOLATED' $D/mut_T8.txt
python3 -I $D/mutate.py supabase/migrations/20261121110000_dating_v2_moderation_console.sql supabase/tests/dating_v2_moderation_contracts.sql $D/mut_T5.py $D/mut supabase/migrations/20261121110010_dating_v2_moderation_console_grants.sql > $D/mut_T5b.txt 2>&1
grep -c 'CONTRACT VIOLATED' $D/mut_T5b.txt; grep -v 'CONTRACT VIOLATED' $D/mut_T5b.txt
```

Expected: `11`, then one line, `csa_292_without_consent: ERROR:  new row for relation "dating_escalations" violates check constraint "dating_escalations_kind_check"` (the function's check removed, the table's own CHECK still refuses the row: the contract fails, a kill; recorded in `mut_T8.py`); `20` and nothing else (Task 5's set again, on W7c's database).

- [ ] **Step 6: Record the tree**

Do not commit; record the tree in the report.

### Task 9: The console's law-enforcement page and "Record an escalation" (§6.4, §6.5, §6.6; R-60)

**Files:**
- Create: `lib/console/screens/law_enforcement_screen.dart`, `test/console/console_le_test.dart`, `$D/{edit_fn_T9.py, edit_app_T9.py, mut_T9.py, mut_T9_dart.py}`
- Modify: `supabase/functions/dating-moderation/{handler.ts, handler.test.ts}`, `lib/console/console_app.dart`, `lib/console/screens/case_screen.dart`

**Interfaces:**
- Consumes: Task 8's four functions; Tasks 6–7's function and console.
- Produces: actions `escalate`, `le_requests`, `le_record`, `transparency`; `ConsolePage.lawEnforcement`, `LawEnforcementScreen`, `kConsoleDisclosed`; the case's "Record an escalation".

- [ ] **Step 1: Write the failing tests**

Create `test/console/console_le_test.dart` with exactly:

```dart
// Spec 2 W7c Task 9 (§6.4, §6.5, §6.6): the law-enforcement page is the
// safety owner's (a moderator's console asks nothing); a request is
// recorded, then decided with what was disclosed and whether the person
// was told; the transparency summary for a window; a case records an
// escalation (CSA 292 only as the consent kind), one request.
import 'package:attune/console/console_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'console_fakes.dart';

void main() {
  testWidgets('a moderator\'s console asks nothing of the log', (t) async {
    final api = await pumpHome(t);
    await t.tap(find.text('Law enforcement'));
    await t.pumpAndSettle();
    expect(
      find.text('The law-enforcement log is the safety owner\'s.'),
      findsOneWidget,
    );
    expect(api.of('le_requests'), isEmpty);
  });

  testWidgets('the owner records a request, decides it, and counts a quarter', (
    t,
  ) async {
    final api = await pumpHome(
      t,
      me: consoleOwner,
      answers: {
        'le_requests': const ConsoleAnswer(
          ok: true,
          data: {
            'ok': true,
            'requests': [
              {
                'id': 'l1',
                'jurisdiction': 'GH',
                'decision': 'pending',
                'received_at': '2026-11-20',
                'legal_basis': 'Court order',
                'scope': 'One account',
              },
            ],
          },
        ),
        'transparency': const ConsoleAnswer(
          ok: true,
          data: {
            'ok': true,
            'summary': {'requests_met': 2},
          },
        ),
      },
    );
    await t.tap(find.text('Law enforcement'));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('console_le_jurisdiction')),
      'gh',
    );
    await t.enterText(
      find.byKey(const ValueKey('console_le_basis')),
      'Court order',
    );
    await t.enterText(
      find.byKey(const ValueKey('console_le_scope')),
      'One account',
    );
    await t.tap(find.byKey(const ValueKey('console_le_record')));
    await t.pumpAndSettle();
    final recorded = api.of('le_record').single;
    final values = recorded['values']! as Map<String, Object?>;
    expect(values['jurisdiction'], 'GH');
    expect(values['legal_basis'], 'Court order');
    expect(values.containsKey('received_at'), isTrue);
    expect(recorded.containsKey('request_id'), isFalse);
    await t.tap(find.text('Decide'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('console_le_decision')));
    await t.pumpAndSettle();
    await t.tap(find.text('Partly disclosed').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('console_le_disclosed_account')));
    await t.tap(find.byKey(const ValueKey('console_le_told')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('console_le_decide_save')));
    await t.pumpAndSettle();
    expect(api.of('le_record').last, {
      'request_id': 'l1',
      'values': {
        'decision': 'partly_disclosed',
        'disclosed_categories': ['account'],
        'user_notified': true,
      },
    });
    await t.ensureVisible(find.byKey(const ValueKey('console_le_from')));
    await t.enterText(
      find.byKey(const ValueKey('console_le_from')),
      '2026-07-01',
    );
    await t.enterText(
      find.byKey(const ValueKey('console_le_to')),
      '2026-10-01',
    );
    await t.ensureVisible(find.byKey(const ValueKey('console_le_summary')));
    await t.tap(find.byKey(const ValueKey('console_le_summary')));
    await t.pumpAndSettle();
    expect(api.of('transparency'), [
      {'from': '2026-07-01', 'to': '2026-10-01'},
    ]);
    expect(find.textContaining('"requests_met": 2'), findsOneWidget);
  });

  testWidgets('a case records an escalation: its kind and their reference', (
    t,
  ) async {
    final api = await pumpHome(t);
    await t.tap(find.byKey(const ValueKey('console_case_c1')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('console_escalate')));
    await t.tap(find.byKey(const ValueKey('console_escalate')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('console_escalation_kind')));
    await t.pumpAndSettle();
    await t.tap(find.text("CSA 292, with the person's consent").last);
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('console_escalation_reference')),
      ' CSA-2026-0001 ',
    );
    await t.tap(find.byKey(const ValueKey('console_escalation_save')));
    await t.pumpAndSettle();
    expect(api.of('escalate'), [
      {
        'case_id': 'c1',
        'kind': 'csa_292_with_consent',
        'reference': 'CSA-2026-0001',
      },
    ]);
  });
}
```

Create `$D/edit_fn_T9.py` with exactly (the function's four actions and their tests):

```python
#!/usr/bin/env python3
# Spec 2 W7c Task 9 (§6.4, §6.5, §6.6): the console API's escalation, the
# law-enforcement log and the transparency summary; their tests.
import importlib.util

spec = importlib.util.spec_from_file_location('anchor', '.superpowers/sdd/2026-11-21-spec2-w7/anchor.py')
anchor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(anchor)

F = 'supabase/functions/dating-moderation/'
anchor.edit(F + 'handler.ts', [
    ("""  audit: { fn: "moderation_audit_log", args: (b) => ({ p_limit: limit(b.limit, 100, 500) }) },
};""", """  audit: { fn: "moderation_audit_log", args: (b) => ({ p_limit: limit(b.limit, 100, 500) }) },
  // Spec 2 W7c (§6.5, §6.6): an escalation (a record, never a send), the
  // law-enforcement log and the transparency summary (the safety owner's).
  escalate: {
    fn: "moderation_record_escalation",
    args: (b) =>
      id(b.case_id) && typeof b.kind === "string" && ESCALATIONS.has(b.kind) &&
        (b.reference === undefined || b.reference === null || text(b.reference, 200))
        ? { p_case: id(b.case_id), p_kind: b.kind, p_reference: typeof b.reference === "string" ? b.reference : null }
        : null,
  },
  le_requests: { fn: "moderation_le_requests", args: () => ({}) },
  le_record: {
    fn: "moderation_record_le_request",
    args: (b) =>
      (b.request_id === undefined || b.request_id === null || id(b.request_id)) && b.values !== null &&
        typeof b.values === "object" && !Array.isArray(b.values)
        ? { p_request: b.request_id ? id(b.request_id) : null, p_values: b.values }
        : null,
  },
  transparency: {
    fn: "moderation_transparency_summary",
    args: (b) =>
      typeof b.from === "string" && DAY.test(b.from) && typeof b.to === "string" && DAY.test(b.to)
        ? { p_from: b.from, p_to: b.to }
        : null,
  },
};"""),
    ("""const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
""", """const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const DAY = /^\\d{4}-\\d{2}-\\d{2}$/;
/// Spec 2 W7c (§6.5): CSA 292 only with the victim's consent (its own kind).
const ESCALATIONS = new Set(["police", "ncmec", "iwf", "csa", "csa_292_with_consent"]);
"""),
], 'W7c Task 9')

anchor.edit(F + 'handler.test.ts', [
    ("""    opinions_remove: "moderation_opinions_remove", audit: "moderation_audit_log",
  };""", """    opinions_remove: "moderation_opinions_remove", audit: "moderation_audit_log",
    escalate: "moderation_record_escalation", le_requests: "moderation_le_requests",
    le_record: "moderation_record_le_request", transparency: "moderation_transparency_summary",
  };"""),
    ("""Deno.test("aalOf reads the token's aal claim, and nothing else", () => {""",
     """Deno.test("W7c: an escalation is recorded (CSA 292 only with consent); the log and the summary", async () => {
  const seen = fresh();
  const ok = deps({ ok: true }, seen);
  eq(await handleModeration({ action: "escalate", case_id: CASE, kind: "csa_292" }, MOD, ok), { ok: false, reason: "invalid" });
  eq(await handleModeration({ action: "transparency", from: "2026-7-1", to: "2026-10-01" }, MOD, ok), {
    ok: false,
    reason: "invalid",
  });
  eq(await handleModeration({ action: "le_record", request_id: "x", values: {} }, MOD, ok), { ok: false, reason: "invalid" });
  eq(seen.rpc.length, 0);
  await handleModeration({ action: "escalate", case_id: CASE, kind: "csa_292_with_consent", reference: "CSA-1" }, MOD, ok);
  await handleModeration({ action: "le_record", values: { jurisdiction: "GH" } }, MOD, ok);
  await handleModeration({ action: "transparency", from: "2026-07-01", to: "2026-10-01" }, MOD, ok);
  eq(seen.rpc, [
    ["moderation_record_escalation", { p_actor: ME, p_case: CASE, p_kind: "csa_292_with_consent", p_reference: "CSA-1" }],
    ["moderation_record_le_request", { p_actor: ME, p_request: null, p_values: { jurisdiction: "GH" } }],
    ["moderation_transparency_summary", { p_actor: ME, p_from: "2026-07-01", p_to: "2026-10-01" }],
  ]);
});

Deno.test("aalOf reads the token's aal claim, and nothing else", () => {"""),
], 'W7c Task 9')
```

```bash
flutter test --no-pub test/console/console_le_test.dart 2>&1 | tr '\r' '\n' | grep -E '^[0-9:]+ \+[0-9]+' | tail -1 | grep -oE '\+[0-9]+( -[0-9]+)?: (All tests passed!|Some tests failed\.)'
```

Expected: `+0 -3: Some tests failed.` (the test imports only the console's fakes and API, so it compiles; there is no law-enforcement page or escalation yet).

- [ ] **Step 2: The function's actions, the page, the escalation**

Create `lib/console/screens/law_enforcement_screen.dart` with exactly:

```dart
// Spec 2 W7c (§6.4 Law-enforcement log, §6.6): the safety owner's page.
// Every request is recorded as received, then decided (what was disclosed,
// whether the person was told); the quarterly transparency summary counts
// what fell in a window. A moderator sees only that the page is the safety
// owner's (the server refuses them anyway).
import 'dart:convert';

import 'package:attune/console/console_api.dart';
import 'package:attune/console/console_app.dart';
import 'package:flutter/material.dart';

/// What can be disclosed (the server's list).
const kConsoleDisclosed = [
  'account',
  'profile',
  'messages',
  'reports',
  'restrictions',
  'verification',
];

class LawEnforcementScreen extends StatefulWidget {
  const LawEnforcementScreen({super.key, required this.api, required this.me});

  final ConsoleApi api;
  final ConsoleMe me;

  @override
  State<LawEnforcementScreen> createState() => _LawEnforcementScreenState();
}

class _LawEnforcementScreenState extends State<LawEnforcementScreen> {
  ConsoleAnswer? _read;
  ConsoleAnswer? _summary;
  String? _line;
  bool _busy = false;
  final _jurisdiction = TextEditingController();
  final _basis = TextEditingController();
  final _scope = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.me.owner) _load();
  }

  @override
  void dispose() {
    for (final c in [_jurisdiction, _basis, _scope, _from, _to]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final r = await widget.api('le_requests');
    if (mounted) setState(() => _read = r);
  }

  Future<void> _record(String? id, Map<String, Object?> values) async {
    setState(() {
      _busy = true;
      _line = null;
    });
    final r = await widget.api('le_record', {
      if (id != null) 'request_id': id,
      'values': values,
    });
    if (!mounted) return;
    setState(() {
      _busy = false;
      _line = r.ok ? 'Recorded.' : consoleReason(r.reason);
    });
    await _load();
  }

  Future<void> _decide(String id) async {
    final chosen = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => const _DecideDialog(),
    );
    if (chosen != null) await _record(id, chosen);
  }

  Future<void> _transparency() async {
    final r = await widget.api('transparency', {
      'from': _from.text.trim(),
      'to': _to.text.trim(),
    });
    if (mounted) setState(() => _summary = r);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.me.owner) {
      return const Center(
        child: Text('The law-enforcement log is the safety owner\'s.'),
      );
    }
    final read = _read;
    final summary = _summary;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_line case final line?)
          Text(line, key: const ValueKey('console_le_line')),
        Text(
          'Record a request',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        TextField(
          key: const ValueKey('console_le_jurisdiction'),
          controller: _jurisdiction,
          decoration: const InputDecoration(labelText: 'Country (GH)'),
        ),
        TextField(
          key: const ValueKey('console_le_basis'),
          controller: _basis,
          decoration: const InputDecoration(labelText: 'Legal basis'),
        ),
        TextField(
          key: const ValueKey('console_le_scope'),
          controller: _scope,
          decoration: const InputDecoration(labelText: 'What is asked for'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          key: const ValueKey('console_le_record'),
          onPressed:
              _busy
                  ? null
                  : () => _record(null, {
                    'received_at': DateTime.now().toUtc().toIso8601String(),
                    'jurisdiction': _jurisdiction.text.trim().toUpperCase(),
                    'legal_basis': _basis.text.trim(),
                    'scope': _scope.text.trim(),
                  }),
          child: const Text('Record'),
        ),
        const Divider(height: 32),
        if (read == null)
          const Text('Loading the log.')
        else if (!read.ok)
          Text(consoleReason(read.reason))
        else
          for (final r in read.list('requests'))
            ListTile(
              key: ValueKey('console_le_${r['id']}'),
              title: Text(
                '${r['jurisdiction']} · ${r['decision']} · ${r['received_at']}',
              ),
              subtitle: Text(
                '${r['legal_basis']} · ${r['scope']}'
                '${r['user_notified_at'] == null ? '' : ' · person told'}',
              ),
              trailing: TextButton(
                onPressed: _busy ? null : () => _decide('${r['id']}'),
                child: const Text('Decide'),
              ),
            ),
        const Divider(height: 32),
        Text(
          'Transparency summary',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        TextField(
          key: const ValueKey('console_le_from'),
          controller: _from,
          decoration: const InputDecoration(labelText: 'From (2026-07-01)'),
        ),
        TextField(
          key: const ValueKey('console_le_to'),
          controller: _to,
          decoration: const InputDecoration(labelText: 'To (2026-10-01)'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const ValueKey('console_le_summary'),
          onPressed: _transparency,
          child: const Text('Count'),
        ),
        if (summary != null)
          SelectableText(
            summary.ok
                ? const JsonEncoder.withIndent(
                  '  ',
                ).convert(summary.data['summary'])
                : consoleReason(summary.reason),
            key: const ValueKey('console_le_summary_text'),
          ),
      ],
    );
  }
}

class _DecideDialog extends StatefulWidget {
  const _DecideDialog();

  @override
  State<_DecideDialog> createState() => _DecideDialogState();
}

class _DecideDialogState extends State<_DecideDialog> {
  String _decision = 'refused';
  final _disclosed = <String>{};
  bool _told = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Decide'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButton<String>(
            key: const ValueKey('console_le_decision'),
            value: _decision,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'refused', child: Text('Refused')),
              DropdownMenuItem(value: 'contested', child: Text('Contested')),
              DropdownMenuItem(value: 'disclosed', child: Text('Disclosed')),
              DropdownMenuItem(
                value: 'partly_disclosed',
                child: Text('Partly disclosed'),
              ),
            ],
            onChanged: (v) => setState(() => _decision = v ?? _decision),
          ),
          for (final c in kConsoleDisclosed)
            CheckboxListTile(
              key: ValueKey('console_le_disclosed_$c'),
              value: _disclosed.contains(c),
              title: Text(c),
              onChanged:
                  (v) => setState(
                    () => v == true ? _disclosed.add(c) : _disclosed.remove(c),
                  ),
            ),
          CheckboxListTile(
            key: const ValueKey('console_le_told'),
            value: _told,
            title: const Text('The person was told'),
            onChanged: (v) => setState(() => _told = v ?? false),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('console_le_decide_save'),
        onPressed:
            () => Navigator.of(context).pop(<String, Object?>{
              'decision': _decision,
              'disclosed_categories': [
                for (final c in kConsoleDisclosed)
                  if (_disclosed.contains(c)) c,
              ],
              'user_notified': _told,
            }),
        child: const Text('Save'),
      ),
    ],
  );
}
```

Create `$D/edit_app_T9.py` with exactly:

```python
#!/usr/bin/env python3
# Spec 2 W7c Task 9 (§6.4, §6.5, §6.6): the console's law-enforcement page
# (the safety owner's) and a case's "Record an escalation". Edits in
# dart format style to files Task 7 created.
import importlib.util

spec = importlib.util.spec_from_file_location('anchor', '.superpowers/sdd/2026-11-21-spec2-w7/anchor.py')
anchor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(anchor)

anchor.edit('lib/console/console_app.dart', [
    ("""import 'package:attune/console/screens/console_lists.dart';
""", """import 'package:attune/console/screens/console_lists.dart';
import 'package:attune/console/screens/law_enforcement_screen.dart';
"""),
    ("""  countries('Countries', Icons.public_outlined),
""", """  countries('Countries', Icons.public_outlined),
  lawEnforcement('Law enforcement', Icons.policy_outlined),
"""),
    ("""    ConsolePage.audit => AuditScreen(api: widget.api),
""", """    ConsolePage.lawEnforcement => LawEnforcementScreen(
      api: widget.api,
      me: widget.me,
    ),
    ConsolePage.audit => AuditScreen(api: widget.api),
"""),
], 'W7c Task 9')

anchor.edit('lib/console/screens/case_screen.dart', [
    ("""  Future<void> _note() async {""", """  /// Spec 2 W7c (§6.5): what a person did, recorded; never a send.
  Future<void> _escalate() async {
    final chosen = await showDialog<(String, String)>(
      context: context,
      builder: (context) => const _EscalationDialog(),
    );
    if (chosen == null) return;
    final (kind, reference) = chosen;
    await _act('escalate', {
      'kind': kind,
      if (reference.trim().isNotEmpty) 'reference': reference.trim(),
    });
  }

  Future<void> _note() async {"""),
    ("""              key: const ValueKey('console_add_note'),
              onPressed: _busy ? null : _note,
              child: const Text('Add a note'),
            ),
          ],""", """              key: const ValueKey('console_add_note'),
              onPressed: _busy ? null : _note,
              child: const Text('Add a note'),
            ),
            OutlinedButton(
              key: const ValueKey('console_escalate'),
              onPressed: _busy ? null : _escalate,
              child: const Text('Record an escalation'),
            ),
          ],"""),
], 'W7c Task 9')

with open('lib/console/screens/case_screen.dart', 'a') as f:
    f.write("""
/// Spec 2 W7c (§6.5): the escalation's kind and the reference the other
/// body gave; CSA 292 only with the victim's consent.
class _EscalationDialog extends StatefulWidget {
  const _EscalationDialog();

  @override
  State<_EscalationDialog> createState() => _EscalationDialogState();
}

class _EscalationDialogState extends State<_EscalationDialog> {
  String _kind = 'police';
  final _reference = TextEditingController();

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record an escalation'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButton<String>(
          key: const ValueKey('console_escalation_kind'),
          value: _kind,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 'police', child: Text('Police')),
            DropdownMenuItem(value: 'ncmec', child: Text('NCMEC')),
            DropdownMenuItem(value: 'iwf', child: Text('IWF')),
            DropdownMenuItem(
              value: 'csa',
              child: Text('Cyber Security Authority'),
            ),
            DropdownMenuItem(
              value: 'csa_292_with_consent',
              child: Text('CSA 292, with the person\\'s consent'),
            ),
          ],
          onChanged: (v) => setState(() => _kind = v ?? _kind),
        ),
        TextField(
          key: const ValueKey('console_escalation_reference'),
          controller: _reference,
          maxLength: 200,
          decoration: const InputDecoration(labelText: 'Their reference'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('console_escalation_save'),
        onPressed: () => Navigator.of(context).pop((_kind, _reference.text)),
        child: const Text('Record'),
      ),
    ],
  );
}
""")
print('lib/console/screens/case_screen.dart: the escalation dialog appended (W7c Task 9)')
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
python3 -I $D/edit_fn_T9.py
python3 -I $D/edit_app_T9.py
dart format lib/console test/console 2>&1 | tail -1
flutter analyze --no-pub lib/console test/console 2>&1 | tail -1
flutter test --no-pub test/console 2>&1 | tr '\r' '\n' | grep -E '^[0-9:]+ \+[0-9]+' | tail -1 | grep -oE '\+[0-9]+( ~[0-9]+)?( -[0-9]+)?: (All tests passed!|Some tests failed\.)'
(cd supabase/functions && deno test --allow-read --frozen dating-moderation/handler.test.ts 2>&1 | grep -E 'passed|failed' | tail -1 | sed 's/\x1b\[[0-9;]*m//g')
flutter build web -t lib/console/main_console.dart -o "$PWD/build/console" --no-pub > $D/web_build.txt 2>&1; echo "web build exit=$?"
```

Expected: `handler.ts: 2 edit(s) (W7c Task 9)`, `handler.test.ts: 2 edit(s)`, `console_app.dart: 3 edit(s)`, `case_screen.dart: 2 edit(s)`, `lib/console/screens/case_screen.dart: the escalation dialog appended (W7c Task 9)`; `Formatted 11 files (0 changed) in … seconds.`; `No issues found! (ran in …)`; `+11: All tests passed!` (the console's 8 and the log's 3); `ok | 8 passed | 0 failed (…)`; `web build exit=0`.

- [ ] **Step 3: The mutants**

Create `$D/mut_T9.py` with exactly:

```python
# Spec 2 W7c Task 9: Deno mutants (denomut.py).
TESTS = ['dating-moderation/handler.test.ts']
H = 'supabase/functions/dating-moderation/handler.ts'
MUTS = {
    'csa_292_without_consent': (H, [('const ESCALATIONS = new Set(["police", "ncmec", "iwf", "csa", "csa_292_with_consent"]);',
                                     'const ESCALATIONS = new Set(["police", "ncmec", "iwf", "csa", "csa_292_with_consent", "csa_292"]);')]),
    'any_day': (H, [('const DAY = /^\\d{4}-\\d{2}-\\d{2}$/;', 'const DAY = /./;')]),
    'bad_request_id': (H, [('      (b.request_id === undefined || b.request_id === null || id(b.request_id)) && b.values !== null &&',
                            '      b.values !== null &&')]),
}
```

Create `$D/mut_T9_dart.py` with exactly:

```python
# Spec 2 W7c Task 9: Dart mutants (dmut.py) on the console.
T = ['test/console/console_le_test.dart']
LE = 'lib/console/screens/law_enforcement_screen.dart'
C = 'lib/console/screens/case_screen.dart'
MUTS = {
    'log_shown_to_moderator': (LE, '    if (!widget.me.owner) {\n      return const Center(', '    if (false) {\n      return const Center(', T),
    'country_not_upper': (LE, "                    'jurisdiction': _jurisdiction.text.trim().toUpperCase(),", "                    'jurisdiction': _jurisdiction.text.trim(),", T),
    'told_dropped': (LE, "              'user_notified': _told,\n", '', T),
    'reference_untrimmed': (C, "      if (reference.trim().isNotEmpty) 'reference': reference.trim(),", "      if (reference.trim().isNotEmpty) 'reference': reference,", T),
}
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
python3 -I $D/denomut.py $D/mut_T9.py 2>&1 | tail -1
python3 -I $D/dmut.py $D/mut_T9_dart.py > $D/mut_T9_dart.txt 2>&1; tail -1 $D/mut_T9_dart.txt
```

Expected: `3/3 killed`; `4/4 killed`.

- [ ] **Step 4: Record the tree**

Do not commit; record the tree in the report.

### Task 10: The runbook, the law-enforcement policy draft, the specs amended, and the W7c gate (§6.4–§6.6, §8 W7; R-55, R-56, R-66)

**Files:**
- Create: `lib/architecture/DATING_MODERATION_RUNBOOK.md`, `lib/architecture/DATING_LAW_ENFORCEMENT_POLICY.md`, `$D/edit_docs_T10.py`
- Modify: `lib/architecture/DATING_MODE_SPEC.md` (v1.5, §8.1), `lib/architecture/DATING_CHAT_SAFETY_SPEC.md` (v2.1: §5.1, §5.2, the changelog), `docs/superpowers/specs/2026-10-24-dating-mode-design.md` (four amendment notes: §4.3's reports and restrictions rows, §4.9's carry-over, §6.3's "At a new account")

**Interfaces:**
- Consumes: everything above.
- Produces: the runbook (§6.4–§6.6, the W7 production gate's named people), the policy draft for counsel (§6.6).

- [ ] **Step 1: The documents**

Create `lib/architecture/DATING_MODERATION_RUNBOOK.md` with exactly:

```markdown
# Attune — Dating moderation runbook

**Status:** Draft 1 (2026-11-21, Spec 2 W7c). Owned by the safety owner. Not
in force until the W7 production gate is met: the safety owner, a moderator
who reads Twi, Ga and Pidgin, and out-of-hours P0 cover are named and
trained on this runbook; counsel has signed the law-enforcement policy
(`DATING_LAW_ENFORCEMENT_POLICY.md`); the report copy's review time matches
the staffed hours below.

**Source:** `docs/superpowers/specs/2026-10-24-dating-mode-design.md` §6.2–§6.6.
Where this runbook and the design spec differ, the spec wins and this file
is corrected.

## 1. Roles and hours

- **Safety owner:** the owner. Publishes country configuration, keeps the
  law-enforcement log, decides appeals of their own decisions only 24 hours
  after the appeal (the console enforces this), and is the only person who
  sees cases that need sensitive routing (§6 below).
- **Moderator:** one contracted moderator who reads Twi, Ga and Pidgin.
- **Out-of-hours P0 cover:** a named person on call for P0 cases outside
  staffed hours.
- **Staffed hours:** 08:00–22:00 GMT, every day. A P0 report is due within
  four staffed hours and never more than 24 hours; P1 within 24 hours; P2
  within 48 hours; P3 within 72 hours. The pilot's size is set so the
  measured P0 load fits this capacity.
- **SLA alerts:** every 15 minutes the database sends one content-free line
  per priority with a case past its time ("P0 case waiting 3 h 40 m") to the
  on-call channel (`moderation_alert_webhook`). It names no person and no
  case: open the console to see it.

## 2. Working in the console

- Sign in with your Attune phone account and your authenticator code. The
  console works only behind the access gate, on a managed device.
- **Claim** a case before working it, so nobody else does.
- Every action you take (opening a case, claiming, each decision, a note)
  is written to the audit log, which nobody can edit.
- **Notes** never name someone's gender, who they want to meet, their faith
  or marital history; write what you saw and why you decided.

## 3. Triage, category by category

For every report: read the reports and their text, the evidence (the last
50 messages, both sides), earlier cases on the same account or number, and
the safety families raised in the chat. If the case shows "The reporter's
messages in this chat triggered: …", weigh the report with that in mind: it
took no automatic step and did not count towards a hold.

| Category | Priority | Look for | Decision options | Record |
|---|---|---|---|---|
| `underage_risk` | P0 | age cues in the evidence (school years, exams), an `age_signal` family, the profile | ask for ID; confirm a minor (closes the whole app, Spec 1's age review); dismiss | `underage_risk` |
| `csam` | P0 | **never view an image**; the case is the report alone | hold; escalate (NCMEC, IWF or Ghana's Cyber Security Authority, through Spec 1 W7b's runbook); restrict | `csam` |
| `child_safety` | P0 | questions about children's routines or access | hold; restrict; escalate to police if a child is at risk now | `child_safety` |
| `threat_to_life` | P0 | a specific threat, a place, a time | hold; escalate to police in the person's country (numbers from `support_resources`); restrict | `threat_to_life` |
| `sextortion` | P1 | threats to share images, payment demands | restrict; with the victim's consent only, record an escalation to CSA 292 (Ghana) or Report Fraud / the Revenge Porn Helpline (UK) | `sextortion` |
| `romance_scam` | P1 | money, airtime or mobile-money asks; a `financial_request` family | restrict | `romance_scam` |
| `threats` | P1 | threats short of life | restrict; hold if continuing | `threats` |
| `entrapment` | P1 | a profile built to lure people (photos, prompts, earlier cases) | restrict | `entrapment` |
| `harassment` | P2 | repeated unwanted messages | restrict for a time; dismiss | `harassment` |
| `explicit_content` | P2 | unwanted sexual messages | restrict for a time; dismiss | `explicit_content` |
| `impersonation` | P2 | someone else's photos or name | ask for ID; restrict | `impersonation` |
| `hiding_relationship` | P2 | evidence of a current marriage | restrict; dismiss | `hiding_relationship` |
| `spam` | P3 | selling, links | restrict; dismiss | `spam` |
| `other` | P3 | read it | any | the closest category |

Signals (dragnet, duplicate opener, money asks across matches, device
accounts): open the case, read what triggered it, and either dismiss it
(dismissing a dragnet case lifts its throttle) or restrict. A case whose
account was deleted stays open under the number's code until you close it:
if nothing in it warrants action, close it with no action.

Appeals: read the restriction, the original decision and the appeal. You
cannot decide an appeal of your own decision (the safety owner may, alone,
24 hours after the appeal). Accept to lift the restriction; reject and the
person reads "We looked again and the decision stands."

## 4. Never

- Never ban on one report or one phrase. A phrase never restricts anyone;
  an interim hold needs two independent P0 reports, or an `underage_risk`
  report with the person's own age cue.
- Never use nationality, network, name or region as a signal.
- Never act on a report whose substance is someone's gender identity: close
  it with no action.
- Never contact police, NCMEC, the IWF or the CSA automatically. Every
  escalation is your decision, recorded in the console after you made it.
- Never view, download or describe CSAM. A hash hit holds the account and
  goes to the safety owner's reporting path without any image being shown.

## 5. Escalation

Always a human decision, recorded with **Record an escalation** (the kind
and the other body's reference):

- **Imminent threat to life:** police in the person's country (numbers from
  `support_resources`).
- **CSAM:** NCMEC's CyberTipline, the IWF, or Ghana's Cyber Security
  Authority, through Spec 1 W7b's runbook.
- **Sextortion:** CSA 292 (Ghana) or Report Fraud / the Revenge Porn
  Helpline (UK), **only with the victim's consent** (the kind is "CSA 292,
  with the person's consent").

## 6. Sensitive routing

A case that puts side by side two people who are not a woman and a man, or
anyone whose answer can't be read, is shown only to people with sensitive
routing (initially only the safety owner). The console decides this each
time it shows the queue or a case; nothing records it. If you are told a
case "isn't available", that is all you need to know.

## 7. Wellbeing

- No exposure to CSAM, ever.
- After any P0 involving violence, step off the queue for the rest of the
  shift; the out-of-hours cover or the safety owner takes over.

## 8. Review cadence

- Weekly: overturned decisions by country (`dating.overturned.{country}`)
  and appeals accepted against rejected.
- Quarterly: the transparency summary (the console's Law enforcement page)
  for the published report: requests by country and decision, requests met,
  reports by category, actions taken, appeals and overturned.
```

Create `lib/architecture/DATING_LAW_ENFORCEMENT_POLICY.md` with exactly:

```markdown
# Attune — Law-enforcement requests: policy (draft)

**Status:** Draft 1 (2026-11-21, Spec 2 W7c). For counsel: the final text is
counsel's, signed at W10 (Spec 2 §6.6). Not published until then.

**Source:** `docs/superpowers/specs/2026-10-24-dating-mode-design.md` §6.6,
§4.8 (what Attune keeps and for how long), §6.8 (the DPIA).

## What this policy says

1. **Valid legal process only.** Attune discloses user data only in response
   to valid legal process from a competent authority in the user's
   jurisdiction, reviewed by the safety owner and counsel, or in an
   emergency involving imminent risk to life. An emergency disclosure is a
   human decision, recorded in the request log.
2. **Only what Attune keeps.** Attune can disclose only what it keeps
   (`§4.8` of the design). It never holds GPS, location history, selfie
   videos, ID images or face templates. Special-category answers (gender
   identity, who someone would like to meet, faith, marital history) are
   deleted when someone leaves Dating, and moderators cannot read them at
   all.
3. **No identification by orientation or gender identity.** Attune does not
   volunteer, and will contest where the law allows, any request whose
   purpose is to identify people by sexual orientation or gender identity.
4. **Telling the person.** Users are told about a request unless the law
   forbids it or telling them would put someone in danger.
5. **Every request is logged** in `law_enforcement_requests` (received, the
   jurisdiction, the legal basis, the scope, the decision, what was
   disclosed by category, when the person was told, who decided) and
   counted in a quarterly transparency summary: requests by country and
   decision, how many were met in whole or in part, reports by category,
   actions taken, appeals and how many were overturned.

## How a request is handled (the safety owner)

1. Record it in the console's Law enforcement page as received (pending).
2. With counsel, check the authority, the jurisdiction and the legal basis;
   narrow the scope to what the law requires.
3. Decide: refused, contested, disclosed or partly disclosed. Record what
   was disclosed by category (account, profile, messages, reports,
   restrictions, verification): never more than the decision covers.
4. Tell the person unless the law forbids it or it would put someone in
   danger; record when.
5. The log is kept 2 years (§4.8), then deleted by the daily purge.

## Questions for counsel

- Ghana (Act 843, the Cybersecurity Act) and the UK: which authorities and
  instruments count as valid legal process; the emergency standard.
- Whether 2 years is the right retention for the log.
- The wording of the published policy and the transparency report.
```

Create `$D/edit_docs_T10.py` with exactly:

```python
#!/usr/bin/env python3
# Spec 2 W7c Task 10 (§1.5, §4.3, §6.3, §8 W7c): the doc amendments.
# DATING_MODE_SPEC.md §8 (category shown, one human appeal, corroborated P0
# holds); DATING_CHAT_SAFETY_SPEC.md §5.1 (report-driven interim holds for
# corroborated P0 only; a phrase never restricts) and §5.2 (the 14
# categories) as Version 2.1; the design spec's tables say what W7 built
# (the plan's rulings R-49, R-51, R-52, R-55).
import importlib.util

spec = importlib.util.spec_from_file_location('anchor', '.superpowers/sdd/2026-11-21-spec2-w7/anchor.py')
anchor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(anchor)

anchor.edit('lib/architecture/DATING_MODE_SPEC.md', [
    ("""**Version:** 1.4 (Spec 2 W2 amended §2, §2.1, §3.1 and §3.2; the rest of the Spec 2 §1.5 amendments follow in W3–W7, then 2.0)  """,
     """**Version:** 1.5 (Spec 2 W2 amended §2, §2.1, §3.1 and §3.2; Spec 2 W7c amended §8; the rest of the Spec 2 §1.5 amendments follow, then 2.0)  """),
    ("""Safety events, dismissals, reports, and blocks never improve or reduce an Alignment score. Blocks are exclusion controls; reports are moderation inputs, not psychological traits.
""", """Safety events, dismissals, reports, and blocks never improve or reduce an Alignment score. Blocks are exclusion controls; reports are moderation inputs, not psychological traits.

### 8.1 Reports, restrictions and appeals (Spec 2 W7, approved under Q20)

The design spec (`docs/superpowers/specs/2026-10-24-dating-mode-design.md` §3.7, §6.2–§6.6) governs; in short:

- **Fourteen report categories in four priorities** (P0 `underage_risk`, `csam`, `child_safety`, `threat_to_life`; P1 `sextortion`, `romance_scam`, `threats`, `entrapment`; P2 `harassment`, `explicit_content`, `impersonation`, `hiding_relationship`; P3 `spam`, `other`), each with a human review time (P0 within four staffed hours and never more than 24; P1 24 hours; P2 48; P3 72). Every report snapshots the last 50 messages, encrypted; reports stay open for 30 days after a conversation ends, the other's deletion included.
- **No automatic ban.** One P0 report closes the reporter's conversation and removes the person from new introductions while the case is open; P1 removes from new introductions; P2's step is the reporter's own block. An **interim hold only when corroborated**: two independent P0 reports (different people, numbers and phones, each account at least 72 hours old), or an `underage_risk` report with the person's own age cue in that conversation (then an age check). A reporter whose own messages raised sexual pressure or a money ask takes no automatic step and never counts.
- **The category is shown; the reporter never is.** A restricted person reads the category in plain words, never who reported, what they wrote or the evidence, and can **appeal once**, to a different person from the one who decided (the safety owner, working alone, only 24 hours after the appeal).
- **Restrictions survive deletion** as phone-number codes for 2 years and come back, with their category and their one appeal, on a new account on the same number.
- **Moderation** happens in a separate console (TOTP, an audited log, read-time sensitive routing); escalations to police, NCMEC, the IWF or Ghana's CSA are always a person's recorded decision, never automatic (`DATING_MODERATION_RUNBOOK.md`, `DATING_LAW_ENFORCEMENT_POLICY.md`).
"""),
], 'W7c Task 10')

anchor.edit('lib/architecture/DATING_CHAT_SAFETY_SPEC.md', [
    ("""**Status:** Version 2.0 (2026-11-20, Spec 2 W6c). The v2.0 amendments""",
     """**Status:** Version 2.1 (2026-11-21, Spec 2 W7c: §5.1 and §5.2). The v2.0 amendments"""),
    ("""A tier-2 or tier-3 trigger creates a moderation queue entry. It never
directly restricts an account. Restriction follows human moderation review,
recorded in `dating_account_restrictions`, whose existing types
(`suspended`, `under_review`, `age_review`, `moderation_hold`) are the
enforcement vocabulary.
""", """A tier-2 or tier-3 trigger creates a moderation queue entry. It never
directly restricts an account. Restriction follows human moderation review,
recorded in `dating_account_restrictions`, whose existing types
(`suspended`, `under_review`, `age_review`, `moderation_hold`) are the
enforcement vocabulary.

**Version 2.1 (Spec 2 W7):** reports, not phrases, may place one interim
step before a person decides: a `moderation_hold` (hidden from
introductions, no sending; conversations stay open) only when a P0 report
is corroborated (two independent P0 reports, or an `underage_risk` report
with the person's own tier-3 `age_signal` in that conversation, which
places an `age_review` instead). A phrase trigger still never restricts
anyone, and a reporter whose own messages tripped `sexual_pressure` or
`financial_request` in that conversation never triggers a step.
"""),
    ("""The categories already exist in `dating_reports` and are unchanged:
`harassment`, `impersonation`, `romance_scam`, `spam`, `underage_risk`,
`other`. `romance_scam` is the dedicated scam category the plan requires.
""", """**Version 2.1 (Spec 2 W7):** the design spec's 14 categories replace the
v1 list (old `safety_concern` and `sexual_content` rows became `other` and
`explicit_content`): P0 `underage_risk`, `csam`, `child_safety`,
`threat_to_life`; P1 `sextortion`, `romance_scam`, `threats`, `entrapment`;
P2 `harassment`, `explicit_content`, `impersonation`, `hiding_relationship`;
P3 `spam`, `other`. `romance_scam` stays the dedicated scam category.
"""),
    ("""## Changelog

""", """## Changelog

- **2026-11-21** — Version 2.1: §5.1 (report-driven interim holds for
  corroborated P0 only) and §5.2 (the 14 categories), Spec 2 W7c.

"""),
], 'W7c Task 10')

S = 'docs/superpowers/specs/2026-10-24-dating-mode-design.md'
anchor.edit(S, [
    ("""`sla_due_at`, `case_id`; categories = §3.7 |""",
     """`sla_due_at`, `case_id`; categories = §3.7 *(amended S2 W7a: also `reporter_phone_hmac` (corroboration: different numbers), `auto_step` (the report took §6.2's automatic step) and `request_key` (a replay answers as the first); v1 `safety_concern`/`sexual_content` rows became `other`/`explicit_content`; `dating_report_evidence` holds at most 50 messages)* |"""),
    ("""keep the four types (`suspended`, `under_review`, `age_review`, `moderation_hold`) |""",
     """keep the four types (`suspended`, `under_review`, `age_review`, `moderation_hold`) *(amended S2 W7a: also `carried_from` (the enforcement record a carried restriction came from, once per record); a row inserted without a source takes one from its type; `dating_matches` gains `low_phone_hmac`/`high_phone_hmac` (a deleted side's number's code, so the other can still report) and the closed reason `reported`)* |"""),
    ("""computed at read time inside the console's definer functions (§6.4) and never stored |""",
     """computed at read time inside the console's definer functions (§6.4) and never stored *(amended S2 W7a: `appeal_id`; one open report case per person; `dating_case_matches` links every match a case comes from, and the purge's hold reads it)* |"""),
    ("""- **At a new account** with the same phone: `begin_dating_enrollment` finds the enforcement record and copies it into a new restriction""",
     """- **At a new account** with the same phone: *(amended S2 W7a: the person's restriction read `get_my_dating_restriction`, not `begin_dating_enrollment`, whose refusal would roll the copy back)* finds the enforcement record and copies it into a new restriction"""),
], 'W7c Task 10')
```

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
python3 -I $D/edit_docs_T10.py
grep -c 'Spec 2 W7' lib/architecture/DATING_MODE_SPEC.md lib/architecture/DATING_CHAT_SAFETY_SPEC.md
grep -c 'amended S2 W7' docs/superpowers/specs/2026-10-24-dating-mode-design.md
```

Expected: `DATING_MODE_SPEC.md: 2 edit(s) (W7c Task 10)`, `DATING_CHAT_SAFETY_SPEC.md: 4 edit(s) (W7c Task 10)`, `2026-10-24-dating-mode-design.md: 4 edit(s) (W7c Task 10)`; `lib/architecture/DATING_MODE_SPEC.md:2`, `lib/architecture/DATING_CHAT_SAFETY_SPEC.md:4`; `4`.

- [ ] **Step 2: The W7c gate**

Run the race script only when the machine is idle (Task 4 Step 6).

```bash
D=.superpowers/sdd/2026-11-21-spec2-w7
$D/suite.sh attune_spec3a > $D/sql-W7c.txt; echo "$(grep -c '^PASS' $D/sql-W7c.txt) PASS, $(grep -c '^FAIL' $D/sql-W7c.txt) FAIL"
diff <(grep FAIL $D/sql-baseline.txt) <(grep FAIL $D/sql-W7c.txt)
flutter analyze --no-pub lib test > $D/analyze-W7c.txt 2>&1; tail -1 $D/analyze-W7c.txt
flutter test --no-pub --reporter compact > $D/flutter-W7c.txt 2>&1; tr '\r' '\n' < $D/flutter-W7c.txt | grep -E '^[0-9:]+ \+[0-9]+' | tail -1 | grep -oE '\+[0-9]+( ~[0-9]+)?( -[0-9]+)?: (All tests passed!|Some tests failed\.)'
shasum -c .superpowers/sdd/2026-11-04-spec1-w10-accessibility-docs/w10-1.0.sha | grep -vc ': OK$'; shasum -c .superpowers/sdd/2026-11-04-spec1-w9/flag_off.sha | grep -vc ': OK$'
shasum -c .superpowers/sdd/2026-11-07-spec2-w3/latch.sha; flutter test --no-pub test/architecture/games_untouched_test.dart 2>&1 | tr '\r' '\n' | tail -1 | grep -oE 'All tests passed!|Some tests failed\.'
(cd supabase/functions && eval "$(grep -m1 -oE 'deno test --allow-read [^"]*' ../../.github/workflows/tests.yml)" 2>&1 | grep -E 'passed|failed' | tail -1 | sed 's/\x1b\[[0-9;]*m//g')
psql -X -d attune_spec3a -Atc "select key || '=' || enabled from public.feature_flags order by key" | diff $D/flags-baseline.txt - && echo "flags unchanged"
uptime
dropdb --if-exists w7race 2>/dev/null; createdb w7race
pg_dump -s attune_spec3a | psql -X -q -d w7race > /dev/null 2>&1
pg_dump -a -t public.metric_key_prefixes -t public.feature_flags -t public.country_safety_config -t private.dating_calling_codes -t public.dating_algorithm_configs -t public.dating_safety_configs -t private.dating_phone_trunk_rules -t private.flag_production_gates attune_spec3a | psql -X -q -d w7race > /dev/null 2>&1
bash scripts/concurrency/dating_kill_switch_races.sh w7race > $D/race_W7c.txt 2>&1; grep -c '^PASS' $D/race_W7c.txt; grep -v '^PASS' $D/race_W7c.txt
dropdb w7race
```

Expected: `162 PASS, 14 FAIL`; no diff; `571 issues found. (ran in …)`; `+8652 -3: Some tests failed.` (+3 since W7b: the log's 3; the same three baseline failures); `0`; `0`; `lib/home/home_screen.dart: OK`; `All tests passed!`; `ok | 246 passed | 0 failed (…)`; `flags unchanged`; the load (replay: 6.98); `42`, nothing else. The mutants: Tasks 8–9 (and Task 5's again).

- [ ] **Step 3: Record the tree**

Do not commit; record the tree in the report.

---

## Owner checklist (nothing here is done by an implementer)

1. **W7's production gate (spec §8 W7; recorded in `private.flag_production_gates` before Dating reaches production).**
   - The safety owner, a moderator who reads Twi, Ga and Pidgin, and out-of-hours P0 cover are named and trained on `lib/architecture/DATING_MODERATION_RUNBOOK.md` (Task 10).
   - Counsel signs the law-enforcement policy (`lib/architecture/DATING_LAW_ENFORCEMENT_POLICY.md` is draft 1 with counsel's questions; the final text is counsel's).
   - The SLA sentence matches staffed hours: the runbook's 08:00–22:00 GMT, P0 four staffed hours and never more than 24, P1 24 h, P2 48 h, P3 72 h, and the report's sent line ("we aim to look at reports like this within {n} hours/days", R-50) agree with the hours the named people actually staff. If the hours change, `private.dating_report_sla_due` changes with them (one function).
   - W6's `dating_match_messaging` gate row lists "Report (W7a) built": W7a builds it (Tasks 1–4); record the evidence (this plan's W7a gate) in that row.
2. **DPIA lines (Rulings R-49, R-52, R-66, R-67).**
   - Reports: category, priority, text (the reporter's own words, encrypted at rest by the database), the reporter's number's code (corroboration), the evidence (the last 50 messages, both sides, encrypted with the field key; kept until the case closes + 180 days, longer while a restriction from it stands); reports kept 2 years; the case, its actions and the audit 2 years.
   - Phone codes on a match after a deletion (`low_phone_hmac`, `high_phone_hmac`): kept with the match (30 days sealed, then purged), for a report within 30 days and a block by number.
   - Open cases at deletion: kept open without the account under the number's code (W5 T8 N-2/N-3, R-66) until a moderator closes them; the runbook says to close an orphaned case with no action unless it warrants one. W5's `dating_moderation_cases.target_phone_hmac` line (carry 5) belongs here too.
   - The audit (`dating_moderation_actions`): who acted, what, when, on which case; never a routing value, a special-category answer or a report's text; append-only, 2 years.
   - The law-enforcement log and the transparency summary (counsel: retention, the published report's wording).
3. **Owner decisions (one line each).** R-50: P0 four staffed hours (08:00–22:00 GMT) and never more than 24 — confirm the hours. R-53: an ended suspension leaves Dating paused (the person taps Resume), and a hold no longer suspends or closes matches — confirm. R-56: the age check's Verify with ID goes to Contact support, and a moderator lifts the age check after support has seen the ID — confirm, or ask for an in-app ID route later. R-60: the law-enforcement log and the summary are read by the safety owner only — confirm. **R-61 (flagged): the console's Opinions page uses only S1 W9b's two existing RPCs; there is no "mark reviewed", so a priority report stays in queue v0 until its post is removed — confirm, or approve one Opinions RPC in a later wave.** R-66: deletion keeps open cases open, userless — confirm with counsel. Visible for a nod: R-49 (extra report columns, the old categories' mapping, 50 messages), R-51, R-52, R-54, R-55 (spec amended), R-57, R-58, R-59, R-62, R-63, R-64 (no push for an appeal outcome), R-65, R-67, R-68.
4. **Deploy (owner only; Dating stays off in production).**
   - `supabase db push` after every earlier undeployed wave (Spec 1 W1–W10, Spec 2 W1–W6), in order: `20261121100000_dating_v2_reports.sql`, `20261121100010_dating_v2_reports_grants.sql`, `20261121110000_dating_v2_moderation_console.sql`, `20261121110010_dating_v2_moderation_console_grants.sql`, `20261121120000_dating_v2_escalations.sql`, `20261121120010_dating_v2_escalations_grants.sql`. Each migration self-revokes: a push that stops between a migration and its twin leaves the new functions callable by nobody.
   - Deploy `dating-moderation` (`verify_jwt = false` is in `supabase/config.toml`; the function checks every token itself and needs aal2). Set the secret `DATING_CONSOLE_ORIGIN` to the console's exact origin (no trailing slash); without it no browser can call the function.
   - Crons after the push (the migrations schedule them where pg_cron exists): `release-dating-suspensions` and `dating-moderation-sla`, both every 15 minutes. Alerts on health's W7 counters: `dating.report.evidence_unavailable`, `dating.report.hmac_missing`, `dating.release.busy`, `dating.release.failed`, `dating.sla.alert_unconfigured`, `dating.sla.alert_failed`, `dating.moderation.not_moderator`, and health's `reports_open` (open cases by priority and `past_due`).
   - Vault: `moderation_alert_webhook` (the on-call channel; one content-free line per priority per run, R-68). `dating_field_key` must be present (without it a report stands without evidence, counted).
   - Moderator rows: insert the safety owner (`role = 'safety_owner'`, `sensitive_routing = true`) and the moderator (`role = 'moderator'`) into `dating_moderators` by hand in the SQL editor (no migration names a person). Both enrol TOTP at first sign-in.
   - The console: `flutter build web -t lib/console/main_console.dart -o build/console --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…` (the publishable key), hosted as a private static site behind an access gate on managed devices, never indexed (`web/index.html` says `noindex`). Its origin is `DATING_CONSOLE_ORIGIN`.
   - Ship the W7 app build with or after the W7a push (the build calls `report_dating_match` v2, `get_my_dating_restriction` and `submit_dating_appeal`; with Dating off nothing reaches them). W7a drops the v1 report RPCs and `submit_dating_report`: no shipped build calls them (Dating off).
   - Production mode (`attune_environment = 'production'`) only after item 1: until then the sent line says reports go to the test review queue (R-50).
5. **§7.7 device checks for W7 (release builds, the development project, `supabase/sql/dev_enable_spec2_dating_flags.sql` run).**
   - TalkBack and VoiceOver: a report from the chat's Safety sheet, from a safety card, from the ended list and from Today's card More (every category read with its label, the details field, Also block, Send, the sent line); the restricted screen (hold, age check, suspension) and an appeal (field, Send appeal, "Appeal sent. A different person from the one who made the first decision will look at it within 7 days.").
   - 200% text and RTL on the report sheet, the restricted screen and the appeal sheet; no animation on any of them.
   - A P0 report from a chat: the conversation ends for both at once (the 30-day ended list on both sides); the other person is left out of new introductions; a second independent P0 report about them places a hold: they can't send, the section shows the hold card, "See why" shows "Your Dating profile is paused while we look into a report. This isn't a decision yet. We aim to finish within 24 hours." and no appeal.
   - An accepted appeal: the section shows "Your appeal was accepted. Dating is open again." for 7 days; a rejected one shows "We looked again and the decision stands." on the restricted screen.
   - A second account on the same phone sees nothing of the first's report sheet or restriction (D8), and quick exit from the report sheet and the restricted screen leaves nothing of them.
   - The console in a browser: sign-in, TOTP enrolment and challenge, the queue, a case (claim, a note, a decision), a case that needs routing is absent for the moderator and present for the safety owner, the audit, the law-enforcement page for the safety owner only; an SLA alert arrives in the on-call channel with no name or id.
6. **Plan copy for the reviewers** (marked "Plan copy" in the ARB descriptions; Tasks 3 and 4's fragments): the sheet's details hint, the testing and staffed sent lines, the busy and unavailable lines, the restricted screen's ends and appeal lines, the appeal sheet's title, field and sent line, the accepted line, the support line for the age check, and the manual's `dating_report` topic.
7. **Still open from W2–W6 (unchanged by W7):** W6's production gate (the chat safety spec §12 boxes, the DV specialist's sign-off, the cultural lexicon); W5's gate and carries 10 and 12; W4's vendor contracts and DPIA biometric section; W3's cultural, LGBTQ+, Ghana legal and counsel reviews and the CSAM matcher; W2's clinician's note and DV reads.
8. **Carried to later waves (recorded, not built here):** image OCR/QR moderation of photos (W5 M-15, carry 1: the console's photo queue rejects such a photo as `unsafe` meanwhile); an in-app ID route for the age check (R-56); a push for an appeal's outcome (R-64); an Opinions "mark reviewed" RPC (R-61, owner-approved only); W8's device wipe registry entries for the report sheet and the restricted screen (neither keeps anything on the device today).

---

## Spec coverage (self-review)

| Spec | Where |
|---|---|
| §3.5 the ended section's Report (30 days) | Task 1 (A: 29 and 31 days; `get_my_dating_matches` lists number-blocked chats), Task 3 (the ended row's Report) |
| §3.6 the Safety sheet's Report, each card's Report | Task 3 (`DatingSafetyChoice.report`, the card's Report; widgets) |
| §3.7 categories, priorities, text, also block, the sent line, evidence | Task 1 (A, B), Task 3 (the sheet; widgets and goldens) |
| §3.7 restricted, hold, age check, suspension, appeal, outcome | Task 2 (E–G), Task 4 (the screen, the appeal sheet, the section's cards) |
| §3.14 `/dating/restricted` | Task 4 (`DatingPaths.restricted`; the text-scale audit) |
| §3.15 Report sheet; Restricted, hold, appeal rows (no motion, large text, dark, errors, offline) | Tasks 3, 4 (goldens at 1.0/1.3/2.0/RTL, guidelines, the large-text audit) |
| §4.3 tables (reports v2, evidence, cases, restrictions v2, moderators, actions, appeals, escalations, the log) | Tasks 1, 2, 5, 8 |
| §4.4 reports, appeals, `moderation_*` | Tasks 1, 2, 5, 8 |
| §4.5 RLS and grants | every twin; the canary (Tasks 1, 2, 5, 8) |
| §4.6 `dating-moderation-sla` (and `release-dating-suspensions`) | Task 5 (M), Task 2 (H) |
| §4.7 `dating-moderation` | Tasks 6, 9 |
| §4.8 reports 2 years, evidence, cases and actions, the log | Task 1 (D), Task 8 (P) |
| §4.9 W7a–W7c; §4.10 every W7 row (`submit_dating_report` removed, v1 report RPCs replaced) | Tasks 1, 5, 8; Task 1 (the mode contract's "it is gone") |
| §6.2 triage, automatic steps, never a ban, corroboration, credibility | Task 1 (B, C), the runbook |
| §6.3 restriction types, appeals, carry-over, the age route | Tasks 1, 2, 4, 5 (`moderation_confirm_minor`, `moderation_lift_hold`) |
| §6.4 the console: TOTP, audit, routing, the queues | Tasks 5–7 |
| §6.5 escalation (a person's recorded decision) | Task 8 (N), Task 9 |
| §6.6 law-enforcement log, transparency | Task 8 (O), Task 9, Task 10 (the policy draft) |
| §6.8 DPIA lines | Owner checklist 2 |
| §6.9 `dating.report.{category}`, `dating.hold.p0`, `dating.appeal.*`, `dating.overturned.{country}` | Tasks 1, 2, 5 (each counted; health lists W7's, R-57) |
| §7.1 `dating_v2_moderation_contracts.sql` | A–P across Tasks 1, 2, 5, 8 |
| §7.2 S1, S2, S8, S11, S18 | C (corroboration), J (routing), E–G (appeal, carry-over), the canary |
| §7.3 `dating-moderation` | Task 6 (handler tests, CI), Task 9 |
| §7.4 widget tests | Tasks 3, 4, 7, 9 |
| §7.5 mutants 13, 14, 15, 26 | Task 1 (`m13_hold_on_one_p0`, `m14_tripped_counts`), Task 2 (`m15_same_decider`), Task 5 (`m26_queue_shows_routed`) |
| §7.6 races | Task 2 (two P0 reports at once; a report while the person leaves; W3c's hold case adapted) |
| §7.7 W7 device checks | Owner checklist 5 |
| §8 W7 gate | Owner checklist 1 |
| §1.5 `DATING_MODE_SPEC.md` §8, chat spec §5.1/§5.2 | Task 10 |
| Cross-spec S-4, S-5, F-6 | Task 5 (S-5 read-time routing, nothing stored), Task 7 (F-6 web entry point, CI build), Task 1 (S-4: no ban from one report) |
| Carries 1–14 | the Carries table |
| Review Focus 1–5 | the tests named there |

Placeholder scan: no "TBD"/"TODO"/"fill in" in a step; every step gives its exact file, code, command and expected line. Type consistency checked by name across tasks: `DatingReportGateway` is complete in Task 3 and `FakeDatingReport` implements all of it; Task 4 adds no gateway method; `ConsolePage` gains `lawEnforcement` in Task 9 and every `switch` over it is exhaustive (the analyzer); the SQL signatures in the twins match the migrations (the canary and `marked_diff.py`); `handler.ts`'s `ACTIONS` names exactly the functions the twins grant to `service_role`.

---

## Replay record (2026-11-21)

The plan was built in a scratch copy of the repo at `e4251c66` on a clone of `attune_spec3a`, then replayed from this text: a fresh scratch copy at `e4251c66` (the W7 tool folder holding only `carries.md`; W6's tool folder, the W10/W9 shas, the latch and `arb_append.py` copied in, as in the main tree), a fresh clone of `attune_spec3a` (`createdb -T`), and a script that wrote every "Create … with exactly" block and ran every `bash` block in order, with the database name swapped for the clone's. The first replay (in four runs: 1–2, 3–4, 5–7, 8–10) found five things the plan now fixes:

1. Task 1's contract D closes cases with `private.dating_close_case`, which Task 2 created: the contract stopped at `function private.dating_close_case(uuid, uuid, unknown) does not exist`. Closing a case moved to Task 1's section 7b (with its revoke, its grant line and its canary row); Task 2 keeps the appeal's decision.
2. Task 5's mutant `claim_unaudited` survived: contract L counted the console's audited actions (`< 12`), which other actions' rows still met. L now requires each of the twelve actions by name (`count(DISTINCT action) <> 12`); the mutant is RED.
3. Task 6's "see it fail" filter looked for Deno's old message; Deno 2.8 says `Cannot find module '…'` (the filter now matches it).
4. Task 9's failing test compiles before the page exists (it imports only the console's fakes and API), so its "see it fail" line is the test count, `+0 -3: Some tests failed.`
5. Task 10's count of amendment notes in the design spec used the wrong tag (the notes say `amended S2 W7…`).

Two things the replay showed that are not W7's: `test/accessibility/w10/healing_journal_large_text_test.dart`'s three goldens fail at `e4251c66` itself (alone too: the journal list's dates move with the day), so every full run below is `-3` with exactly those three; and the mutant `csa_292_without_consent` is killed by the table's own CHECK (an error, not a `CONTRACT VIOLATED` line; kept, with its reason in `mut_T8.py`).

After those fixes the plan was replayed again end to end on a new scratch copy and a new clone (Tasks 1–10 in one run; Task 1 Step 3's full Flutter baseline reused from the first replay's run on the same commit, every other command run afresh), and every Expected line below matched. The replayed tree equals the built tree file for file (one trailing blank line in `edit_tests_T5.py` aside); the goldens are byte-identical. The race script ran at each gate at load 5.2–9.6 in the final replay (4.6–5.1 in the first; the machine shared with another agent's Flutter runs, which the plan says to wait out): every case passed both times. The clones (`w7build`, `w7replay`, the gates' `w7race`) and both scratch copies were dropped afterwards; `attune_spec3a` holds no W7 object (it was only read and cloned); the main tree changed only by this file.

| Check | W7a (after Task 4) | W7b (after Task 7) | W7c (after Task 10) |
|---|---|---|---|
| Migration + twin, applied twice | 4 × `exit=0` (Tasks 1 and 2) | 4 × `exit=0` | 4 × `exit=0` |
| `marked_diff.py` | 10 functions `OK` (Task 1: 9 re-created; Task 2: 10) | — (none re-created) | 2 functions `OK` |
| SQL suite (wrapped) | 162 PASS / 14 FAIL, the baseline's 14 fails only | 162 / 14, same fails | 162 / 14, same fails |
| `dating_v2_moderation_contracts.sql` | `all held` (A–D, then + E–H) | `all held` (+ I–M) | `all held` (+ N–P) |
| SQL mutants | T1 29 / 29, T2 24 / 24, T1 after T2 29 / 29 RED | T5 20 / 20 RED | T8 12 / 12 (11 `CONTRACT VIOLATED`, 1 the table's CHECK), T5 again 20 / 20 |
| Race script (scratch DB built by the gate) | 42 / 42 PASS (two new W7a cases) | 42 / 42 | 42 / 42 |
| Deno (CI line, frozen lock) | — | 245 passed, 0 failed; `deno check` clean | 246 passed, 0 failed |
| Deno mutants | — | T6 10 / 10 killed | T9 3 / 3 |
| Dart mutants | T3 13 / 13, T4 11 / 11 | T7 10 / 10 | T9 4 / 4 |
| `flutter analyze --no-pub lib test` | 571, no new issue | 571 | 571 |
| Full `flutter test` | +8641 −3 (baseline +8622 −3; the same three) | +8649 −3 | +8652 −3 |
| Console web build | — | `exit=0`, `build/console` ignored | `exit=0` |
| Large-text audit at 2.0 (`test/features/dating/report`) | 0 sites | — | — |
| W10 / W9 golden shas, latch, Games guard | 0 / 0 / OK / passed | 0 / 0 / OK / passed | 0 / 0 / OK / passed |
| Feature flags | — | — | unchanged (44 rows, as at the baseline) |
