# Spec 2 W9 (Couple link and export) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Summary (one paragraph).** W9 is **two batches and seven tasks**, one migration (with its grants twin and a self-revoke), one changed edge function, and the app's couple link. **W9a** (Tasks 1–4, server) → `20261123100000_dating_v2_couple_link.sql` (+ `20261123100010_dating_v2_couple_link_grants.sql`): the flag `dating_couple_link` (off) with its production gate; link requests, Not right now, taking it back, and the second Yes's one transaction, which **calls the invite exchange's own `accept_relationship_invite_v2` unchanged** (the controller's ruling: one pairing path), closes every other open conversation neutrally and keeps the first messages only when both chose it, masked unless both swapped; the chat header's `link` and the link page's read; contract L with a link-equals-invite proof (Task 1); the link origin (members only, S-6), How we met, the Relationship home's offer, `dating_export_for_job` (S-4, three logged reads a job) and `export_relationship` re-created from its live body with the How we met card, contract E and `data_export_contracts.sql`'s own-data Dating part (Task 2); the push audit follows every write into its table's triggers in every schema (carry 1), Today's inner window edges (carry 3) and three race cases for the second Yes (Task 3); `build-data-exports` writes `dating.json` through a new `dating_part.ts`, the TypeScript push guard counts `send-notification` calls (carry 2), and the W9a gate (Task 4). **W9b** (Tasks 5–7, app): the Safety sheet's "Become a couple on Attune", the chat's link cards, `/dating/link/:matchId` with "What are we agreeing to?" and "You decided together." (Task 5); the Relationship home's one appended `HomeCard` (`link_offer`), asked only while the app already knows the flag is on (the controller's ruling: zero extra calls with it off), About us's "The day you matched" chip through a client override of Spec 1's provider, and its How we met row and card (Task 6); the design spec's notes, the development flag, every mutant again and the W9b gate (Task 7).

**Replayed.** Every task below was replayed in order in a fresh scratch copy of the repo at HEAD `cbf7b30b` on a fresh clone of `attune_spec3a`: every "Create … with exactly" block, every edit, build, splice and mutant script, the ARB fragment, `gen-l10n`, `dart format`, every test command, the golden generation, the Deno CI line, the race script and both batch gates. The Expected lines are what that replay printed (Replay record, end of plan).

**Goal:** Build Spec 2's couple link and export (§3.9, §4.2–§4.4, §4.7, §7.1, W9) on the W1–W8 server and app: two people who met in Dating become a couple on Attune only when both say yes, through the same pairing path as an invite; nothing about the other person is ever revealed by asking; their first messages are kept only when both chose it; About us offers the day they matched; 30 days on, each may delete their Dating data from the Relationship home; "Download my data" carries the person's own Dating data and nothing of anyone else's; and Dating stays off in production (the new flag off).

**Architecture:** Server first. The second Yes takes both people's Dating setup locks (every Dating writer's first lock), the match, the request, then both users rows (the invite exchange's order), inserts the pending row `create-relationship-invite` inserts and calls `accept_relationship_invite_v2` unchanged, so every trigger fires as for an invite (the relationship guard pauses both with `relationship`, old ended chapters are archived); then it sets the asker's path, closes every open conversation of either person and writes the link's origin. What the chat shows (`link`) is one helper read after each read's own trip check (S-5). The Relationship side (origin, How we met, the offer) is read by the relationship's two members only, with one opaque refusal each. The export's Dating part is the only service-role path to decrypted fields (S-4), bound to a building job. The app adds `lib/features/dating/link/` (models, gateway, the link page, the home card, About us's chip and row) and appends one entry each to `ConversationsScreen`'s card list and About us. Every re-created function starts from its LIVE body (saved to `$D/before_w9/`) with only lines marked `-- Spec 2 W9` changed (`marked_diff.py`).

**Tech Stack:** Supabase Postgres 17 (RLS, `SECURITY DEFINER`, advisory locks), psql, Python 3 (edit, build, splice and mutation scripts), Deno 2.8.1 (frozen lock `.github/deno-w9.lock`), Flutter 3.29.1 / Dart 3.7 / Riverpod 2.6 / go_router. No new package, no new remote module.

**Spec:** `docs/superpowers/specs/2026-10-24-dating-mode-design.md` — §3.9 (Couple link), §3.6 (the Safety sheet's row), §3.14 (`/dating/link/:matchId`), §3.15 (Couple link: motion, accessibility, offline), §4.1, §4.2 (S-4), §4.3 (`dating_couple_link_requests`, `couple_how_we_met`, `dating_export_reads`), §4.4 (Couple link; `dating_export_for_job`), §4.5, §4.7 (`build-data-exports`), §4.8 (How-we-met card), §4.9 W9, §4.10 (rows tagged W9: `export_relationship`, `build-data-exports`, `conversations_screen.dart`, `data_export_contracts.sql:229-233`, flag `dating_couple_link`), §6.8, §6.9 (`dating.couple_link`), §7.1 (`dating_v2_link_contracts.sql`), §7.3, §7.4 (the Relationship-home card test), §7.5 (mutants 21, 22, 23, 28), §8 W9, §9 R9 and R20, C-4, I-12, I-13, S-4, S-5, S-6, A-3. Spec 1 (`docs/superpowers/specs/2026-10-24-app-flow-identity-design.md`): the invite exchange (W4), About us (W5: `aboutUsDateSuggestionsProvider`, the AU2 slot), `set_user_path_internal` (W1b). Carries: `.superpowers/sdd/2026-11-23-spec2-w9/carries.md` (every item mapped below). Format reference: `docs/superpowers/plans/2026-11-22-spec2-w8-device.md`. Memory: `spec2_w8_device_status.md`, `spec2_w7_moderation_status.md`. The controller's two rulings during planning: reuse the invite exchange (R-W9-1, with the equivalence contract L9), and HEAD is `cbf7b30b` (Games only; no W9 file changed).

## Global Constraints

- **Where and how.** Work in the main working tree on `main` (`/Users/user/attune`). HEAD is `cbf7b30b` (S2 W1–W8 committed, then a Games-only merge: `lib/features/games/platform/`, This or That, two routes in `app_router.dart`, `chat_screen.dart`'s `_openGames`/`openGameRoute`; no `supabase/` change). **W9 touches none of those files** (not `lib/app/routing/app_router.dart`, not `chat_screen.dart`, nothing under `lib/features/games/`); every file this plan edits is byte-identical at `fba46cff` and `cbf7b30b` (`git diff --name-only fba46cff cbf7b30b` lists none of them). The owner may have uncommitted edits (`supabase/.temp/cli-latest`, `backup-before-planning-p2.sql`): never revert, stash, stage, checkout, reformat or read them into anything. Every edit to an existing file is an exact replacement made by a script that asserts each anchor occurs once (`$D/anchor.py`). If an anchor moved because the live code changed after this plan was written, make the same change to the current text and say so in the task report (live code is the truth).
- **NO commits.** No `git add`, `git commit`, `git stash`, `git checkout`, `git reset`, `git rm` (delete files with `rm`). Where a skill says "commit", instead: **do not commit; record the tree in the report** with `T=$(mktemp -u); GIT_INDEX_FILE=$T git read-tree HEAD && GIT_INDEX_FILE=$T git add -A && GIT_INDEX_FILE=$T git write-tree; rm -f $T` (a private index; the real index is untouched). The controller commits after each batch's final review.
- **Formatting.** Never `dart format` a pre-existing file. `dart format` only the files a task creates (the blocks below are already in `dart format` style). TypeScript is not formatted (the repo's isn't).
- **SQL target.** Contracts run only on `attune_spec3a`, from the repo root. A file with a top-level `BEGIN;` runs as `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f F`; one without runs wrapped (`suite.sh` does both). Migrations and twins are applied with `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f <file>`. Confirm the target first (`psql -X -d attune_spec3a -Atc 'select current_database()'` prints `attune_spec3a`). **NEVER `attune_test`. NEVER run `scripts/local_pg_setup.sh` or `scripts/local_pg_grants.sql`** — but DO append the twin's `\i` line to `scripts/local_pg_grants.sql` (`grants_line.py`). SQL mutants run inside one transaction the contract's own `ROLLBACK` ends (`mutate.py`; `W9_DB` names the database). **An `IF a OR b` in a DO block has no evaluation order: every call that writes is its own statement first** (the replay found two such in contract L). A comparison that can read NULL uses `IS DISTINCT FROM`. In plpgsql, a `CASE … END` inside an `IF` condition is parenthesised (the parser ends the condition at the CASE's first `THEN`).
- **Migrations.** `20261123100000_dating_v2_couple_link.sql` and `20261123100010_dating_v2_couple_link_grants.sql`, later than every file in `supabase/migrations/` (the newest is `20261122100010_dating_v2_traveller_grants.sql`). If `ls supabase/migrations | sort | tail -1` shows anything at or after `20261123100000` when Task 1 starts, shift both to the next free hour keeping their order and change every header, `\i` line and command. The migration is one `BEGIN; … COMMIT;`, idempotent (applied twice, `exit=0` both times), with `SET LOCAL lock_timeout = '5s'`, and **ends by revoking everything it creates from PUBLIC, anon, authenticated and service_role** (a push that stops between the migration and its twin fails closed); the twin grants. Every new function: `SECURITY DEFINER SET search_path = ''`, fully-qualified names; `GRANT EXECUTE … TO authenticated` only for the couple link's nine client RPCs; `service_role` only for `dating_export_for_job`; the helpers the database's own. Every new table: RLS on, nothing for any API role (S-5: the service role neither). Re-created functions (`private.dating_chat_header`, `public.export_relationship`) start from their LIVE body and change only lines marked `-- Spec 2 W9`. Answers are fixed `{ok, reason}` codes; input is validated before any write; NULL never counts as allowed.
- **One pairing path (R-W9-1).** `confirm_dating_couple_link` makes the relationship by inserting the pending row `create-relationship-invite` inserts (`user_a`, `status 'pending'`, `invite_code`, `invite_expires_at`; the code is 12 characters no one is shown, 7 days) and calling `public.accept_relationship_invite_v2(confirmer, code)` **unchanged**. Not edited: `accept_relationship_invite_v2`, `set_user_path_internal`, `adopt_couple_profile_drafts`, any invite screen, `create-relationship-invite`, `accept-invite`. Contract L9 proves a link and an invite produce the same rows and side effects.
- **The W5–W8 lessons, in this wave.** Reads that write are `VOLATILE` (W9's reads write nothing; `dating_export_for_job` logs its read and is volatile). Exposure-reducing writes never wait: Not right now and taking a request back need no flag and no trusted phone. Every refusal is a fixed code; the app never shows a server's text. S-5 and the viewer-visible pair rule bind every new read (carries 4, 5): the chat's `link` and the link page are read after the reader's own trip check (`private.dating_trip_hides(viewer, other, 'match', sg)` with the phone's `p_show_same_gender`); asking answers from the asker's life only; nothing W9 returns names a gender, a pool, a trip or `me_section_view`. D8: the link page, the home card and About us's row show nothing of the last account. Mutant runs never rewrite a file another agent is testing (`dmut.py`, `denomut.py` mutate a private copy).
- **Production stays off.** The migration inserts `dating_couple_link` **off** with its production gate row and turns nothing on; no migration sets `attune_environment`. Only `supabase/sql/dev_enable_spec2_dating_flags.sql` (development only, never a migration) turns the new flag on (Task 7). With the flag off: asking, the second Yes and the link page answer `unavailable`; the chat's `link` is null; the origin and How we met answer their opaque refusals; the offer is none.
- **Copy.** New app strings go into `lib/i10n/app_en.arb` under `dating_` only through `python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py <fragment>`, then `flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package`. Straight apostrophes. §3.9's strings are copied verbatim; strings this plan adds are marked "Plan copy" in their ARB description and listed for the reviewers (Owner checklist).
- **UI.** The link page is under `AllowLargeText`; §3.15: one settle (≤ 600 ms, once; a 150 ms fade under reduce motion) on "You decided together." only, nothing else moves; the "What are we agreeing to?" text is read before its buttons; offline the second Yes says "You're offline. Nothing has changed yet." Goldens at 1.0, 1.3, 2.0 and RTL (`expectFlowGoldens`), the three guidelines (`expectFlowGuidelines`), the large-text audit at 2.0 over `test/features/dating/link` (`0 site(s) to fix`); `datingLink` listed as audited in `test/architecture/text_scale_routes_test.dart`.
- **Shared files (regression risk, flagged).** `lib/features/chat/presentation/screens/conversations_screen.dart` (Relationship home): **one** appended `HomeCard` (`link_offer`), included only while the server reports an offer; the `const` card list becomes non-const for that one entry; the chat card, the story rings, the Journals and Together cards and every Games entry point are untouched (C-4, R20; Task 6 pins order and presence). `lib/features/couple_profile/presentation/couple_profile_providers.dart` (Spec 1): `aboutUsDateSuggestionsProvider`'s body becomes Dating's chip, one line (the "client override" of I-12 cannot be a `ProviderScope` override: `lib/main.dart` is off limits). `lib/features/couple_profile/presentation/screens/about_us_screen.dart` (Spec 1): one row, How we met, that renders nothing unless the couple kept the card. `lib/app/documentations/user_manual/data/documentation_flags.dart` (the manual's flag read): **unchanged as built** (R-W9-16 as built: the couple-link flag is its own one read, `lib/core/flags/couple_link_flag.dart`; the plan's manual edit was withdrawn in Task 5's fix round 1). Spec 1's W10 golden sha list and the latch must stay `OK`.
- **Off limits.** Games (`test/architecture/games_untouched_test.dart` stays green; nothing under `lib/features/games/`), `chat_screen.dart`, `lib/app/routing/app_router.dart`, Opinions, `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`, `lib/home/home_screen.dart` and its latch (`shasum -c .superpowers/sdd/2026-11-07-spec2-w3/latch.sha`; W9 imports `relationshipModeResyncSignal` from it, never edits it), `quick_exit_service.dart`, `auth_provider.dart`, `lib/main.dart`, `lib/app/app.dart`, every applied migration, every invite function and screen, every edge function but `build-data-exports` (one module added, one line in `parts.ts`). **No deploys** (`supabase db push`, function deploys, app builds are the owner's; Owner checklist). No `.env*`, credentials or keychain. No subagents for the replay; Opus for every implementer and reviewer.
- **Fixture ids.** The link contract's people are `8a900000-0000-0000-0000-` + the 12-digit code (`pg_temp.id('nn')`) with phones `+1555982nn`: L `01–32`, E `50–63` (swept against the whole suite: unused). The device contract's new C1d uses `140–143`. The race cases use `race.id('64')`, `race.id('65')`.
- **Gates, every batch (Tasks 4 and 7; `$D/gate.sh`).** (1) The wrapped SQL suite on `attune_spec3a`: no new FAIL against `$D/sql-baseline.txt` (baseline **163 PASS / 14 FAIL** by day; `quiet_hours_contracts.sql` fails between 22:00 and 08:00 UTC, its real clock; **164 / 14** from Task 1, which adds `dating_v2_link_contracts.sql`). (2) `dating_v2_link_contracts.sql` and `dating_v2_device_contracts.sql`: `all held`. (3) The Deno CI line (`.github/workflows/tests.yml` job `deno-w9`, frozen lock) passes in full (**279 → 283**) and its `deno check` line is clean; `build-data-exports/` passes with `--no-lock` (its tests use `fflate`, which the frozen lock doesn't hold; not in CI). (4) `flutter analyze --no-pub lib test`: **571 issues, 0 new**. (5) `shasum -c` of the W10 and W9 sha lists: every line `OK`; the latch `OK`. (6) The Games guard passes. (7) The feature flags: **46 rows, 6 on** (one more row than the baseline's 45, none newly on). (8) `scripts/concurrency/dating_kill_switch_races.sh` on an **IDLE** scratch database (load under about 4; wait, or note the load) built from `pg_dump -s attune_spec3a` plus the config tables' data, dropped after: **58 → 61** PASS. (9) Full `flutter test`: no failure beyond the known ones (at `cbf7b30b`: **+9621 −3**, the three `healing_journal_large_text` goldens; re-run a failing file alone before calling it a flake: `chat_controller_test:259`, `chat_screen_list_anchor` D<0, `reflection_journal` at a date boundary, `planning_recent`, `story_outbox_notices_test`, `chat_upload_progress_cancel_test`, `story_review_test`); the count moves by the tests each task adds. (10) Each task's named mutants all RED (a `CONTRACT VIOLATED` line, or `KILLED`), the RED line quoted in the report; a `COMPILE` or an `anchor missing` is a broken mutant to fix, never a kill.

## Review Focus

Five things a real person will meet that this wave must survive. Each is pinned to tests that fail if it regresses.

1. **The second Yes meets the asker changing their mind or their life at the same moment** (the asker takes it back, leaves Dating, or switches to Just for me while the other taps "Yes, let's"; or a double tap). Expect: one couple or none, never half a couple (a relationship without both paths, a closed chat with no relationship, a second relationship); no caller sees an error. Tests: Task 3 races 64–66 (linked / closed / both land), Task 1 L6 (a replay is the same couple), L5 (a lapsed request links nothing), Task 5 `the private step is read in full, then Ask {Name} sends this side's Yes … once`.
2. **Someone secretly partnered** (S18): the other person is in an Attune relationship, or under a hold, and the asker taps "Ask". Expect: the asker's answer is the same as for anyone (nothing about the other person's life); the second Yes is refused (`unavailable`, "This isn't possible right now.") and changes nothing. Tests: Task 1 L8 (mutant `ask_reveals_other`; the invite exchange's own refusals), Task 5 `a refusal is a calm line and nothing moves`.
3. **A same-gender couple where one is in Accra on a trip** (carry 5). Expect: the request never reveals the trip (the asker's answer is the same either way); on the traveller's phone the chat and the request stay hidden and can't be answered, unless "Show it on this phone anyway"; a man-woman pair is unaffected. Tests: Task 1 L8 (mutant `confirm_ignores_trip`), W8's B12 catalogue extended (asking and the second Yes write only past the hiding).
4. **First messages that hold a phone number or a handle**, and one person who didn't want them kept. Expect: How we met only when both ticked the box, masked exactly as both saw it unless both swapped, nothing the other never saw (an unrevealed guided answer); About us's row only for a couple that kept it. Tests: Task 1 L6, L7 (mutants `keep_one_side`, `m_unmasked`, `keeps_unseen`), Task 2 E3, Task 6 `About us shows How we met …`.
5. **"Download my data" after a Dating start** (and a worker that retries a failing part). Expect: the person's own Dating data (their own answers decrypted, their own sent messages as they wrote them) and nothing of anyone they matched (no name, age, message, or why a chat ended), no id; a job that isn't building, or a fourth read of one job, is refused. Tests: Task 2 E5 (mutants 22, 23, `read_limit_gone`, `export_counterpart_name`), `data_export_contracts.sql` 1b, Task 4 `dating.json is the job's own call, by the job id alone`.

## Pre-flight (read before Task 1)

`D=.superpowers/sdd/2026-11-23-spec2-w9` throughout. The tool folder holds `carries.md`; Task 1 copies W8's tools into it (`suite.sh`, `anchor.py`, `splice.py`, `marked_diff.py`, `grants_line.py`, `mutate.py` with `W9_DB`, `mirror.py`, `dmut.py`, `denomut.py`), unchanged but for their names.

### Shared files and interfaces between tasks

| File or interface | Tasks | Rule |
|---|---|---|
| `supabase/tests/dating_v2_link_contracts.sql` | 1 creates (L1–L9, then `-- @@W9-T2@@`); 2 splices E1–E5 there | helpers from L: `pg_temp.id`, `dev`, `hash`, `ready`, `uk`, `as_person`, `as_db`, `j`, `key`, `match`, `side`, `say`, `we_met`, `swap`, `ask`, `yes`, `no`, `take_back`, `link`, `page`, `rels`, `check`, `delta`; from E: `couple`, `origin`, `how`, `offer`, `dismiss`, `export`, `job` |
| `supabase/migrations/20261123100000_dating_v2_couple_link.sql` | 1 builds it (`build_mig_W9.py`: `mig_T1_head.sql`, the re-created header, the self-revoke); 2 adds `mig_T2.sql` (at `-- @@W9-T2@@`) and `edits_T2.py`, and builds again | the builder includes Task 2's section, edits, tables and functions when they exist |
| `…100010_dating_v2_couple_link_grants.sql` | 1 creates (ends with `-- @@W9-T2-GRANTS@@`); 2 splices `twin_T2.sql` there | |
| `supabase/tests/dating_rls_canary.sql` | 1 (rows above its Checks line, then `-- @@W9-T2-CANARY@@`), 2 (rows at the marker) | never a loosened check |
| `supabase/tests/dating_v2_device_contracts.sql` (W8's) | 1 (B12's catalogue meets the couple link), 3 (§A's walk; C1d) | Task 3's anchors are Task 1's text where they meet |
| `lib/features/dating/link/dating_link.dart` | 5 creates (chat and couple sides, all providers) | Task 6 reads its providers |
| `lib/features/dating/link/link_screen.dart` | 5 creates (`DatingLinkMoment`, `datingGoToCouple`) | Task 6's card reuses the moment |
| `lib/i10n/app_en.arb` + generated | 5 (every W9 string, Task 6's too) | one fragment via `arb_append.py`, then gen-l10n |
| `test/features/dating/support/dating_shell.dart` | 5 (the link faked in every shell) | |

### Carries → tasks

| # | Carry (`carries.md`) | Where |
|---|---|---|
| 1 | §A push audit blind spots: follow a Dating function's writes into non-Dating tables whose triggers queue pushes, trigger functions outside public/private, quoted schemas, MERGE, dynamic SQL; the link's relationships row | Task 3 (`edit_tests_T3.py`: every schema's SQL/plpgsql functions; write → the table's triggers for that operation; quoted/qualified/MERGE queue writes; no other queue table, no `send-notification`/OneSignal, no EXECUTE built at run time; eight RAW mutants, W8's 31 still RED). The link's own pushes: Task 1 L9 (it queues none; the walk from it reaches only cancel-only writers). |
| 2 | Deno guard counts `functions.invoke('send-notification')`; `build-data-exports` changes within the guard | Task 4 (`sendNotification` kind; `send-checkin-reminders/index.ts` listed; `dating_part.ts` touches no queue). |
| 3 | C1c inner window edges: a 13-day-old message, a 6-day-old match; mutants shrinking the windows | Task 3 (C1d; `today_message_window_12`, `today_match_window_5`). |
| 4 | S-5 / viewer-visible pair rule on every new read | Tasks 1, 2 (each read after the reader's own trip check, or relationship-scoped with no Dating field; L8, E2–E4); Global Constraints. |
| 5 | Can a hidden (trip) match be linked; the request must not reveal the trip | Task 1 (R-W9-6: hidden on the caller's own phone → `match_unavailable` unless "Show it on this phone anyway"; the other side's trip never changes the asker's answer; L8). |
| 6 | "Become a couple" deferred to W9; `theyMet` parsed but unused | Task 5 (the Safety row needs `weMet || theyMet` and the server's `link.state == none`; mutant `they_met_ignored`). |
| 7 | A person's own Dating messages in "Download my data"; `data_export_contracts.sql:229-233` | Task 2 (`dating_export_for_job`, E5, 1b), Task 4 (`dating.json`). |
| 8 | `dating_weMetNoted` never says whether the other is told | Ruled: unchanged (R-W9-12); the other side learns only through the link's own state. Owner question 10. |
| — | Conversations screen: one appended `HomeCard` only | Task 6 (Global Constraints: shared files). |
| — | `export_relationship` re-created from its LIVE body | Task 2 (`before_w9/`, `edits_T2.py`, `marked_diff.py`). |

### Rulings (the spec wins over this plan; each records its cost if wrong)

- **Ruling R-W9-1 (the controller's):** one pairing path. The invite exchange has no internal SQL for the pending row (`create-relationship-invite` inserts it directly), and `accept_relationship_invite_v2(p_acceptor, p_invite_code)` is the exchange's own service-role function. The second Yes inserts the pending row with the edge function's columns and calls `accept_relationship_invite_v2` unchanged (the acceptance row, the acceptor's path, both people's other pending invites, About us's drafts, the invite metrics, every trigger); it then sets the asker's path itself. Its refusals (`invite:*`, `account:hold`, `relationship:already_open`) undo the whole attempt and answer `unavailable`. Contract L9 proves a link and an invite make the same relationships row, the same acceptance row and the same rows in every table that references `relationships`. Owner questions 1 and 2. Cost if wrong: one helper extracted later.
- **Ruling R-W9-2:** the chat's header carries `link` (`private.dating_link_json`, read after `get_dating_messages`' own trip check), and the link page reads `get_dating_couple_link(p_match_id, p_show_same_gender)` (a read §4.4 does not list: a cold-start deep link to `/dating/link/:matchId` has no chat to read). Request and confirm take `p_show_same_gender` as every read that hides (W8 R-T5-1). Cost if wrong: none.
- **Ruling R-W9-3:** the link's origin and each side's two once-only moments live in a new table, `dating_link_origins` (relationship-scoped, purged with the relationship): the match row is purged 30 days after the link (its evidence window), the very day the offer is due, so neither the request nor the match can hold them. "Both see (once)": the confirmer at once; the asker the first time they are on their chat, the link page or the Relationship home's `link_offer` card, which shows "You decided together." before the 30-day offer. Owner question 12. Cost if wrong: one column.
- **Ruling R-W9-4:** lock order: both setup locks (`private.dating_lock_setup_pair`), the match, the request, both users rows lowest id first; a retry loop for deadlocks and lock timeouts (`lock_timeout 2s`), `busy` on the third. Race 66 shows one Spec 1 path change met mid-way is retried inside the second Yes and both land.
- **Ruling R-W9-5:** after "Not right now" the asker may ask again only 14 days on (`not_ready`, "{Name} isn't ready yet."); the decliner may ask any time; a request lapses 14 days on with no copy; the asker can take an open request back ("Take it back", Plan copy). Owner question 4.
- **Ruling R-W9-6 (carries 4, 5):** asking checks only the asker's own life (an open Attune relationship, an account hold), never the other person's; the second Yes relies on the invite exchange's own checks of both. A chat the caller's own trip hides is `match_unavailable` for the page, asking and the second Yes unless the phone shows it anyway; the other side's trip never changes the asker's answer (they see the request once it shows on their phone, or it lapses).
- **Ruling R-W9-7:** the link queues no push and no in-app notice (the invite's "Your partner joined Attune" is accept-invite's, never the database's, and would not be neutral). The asker learns at their next open (R-W9-3). Owner question 3.
- **Ruling R-W9-8:** "Delete my Dating data" opens Leave Dating (`/dating/leave`, §3.8, behind the Dating lock, with its deleted/kept lists); leaving removes the Dating data the offer needs, so the card goes. "Keep for now" is `dismiss_dating_post_link_offer('delete')`, never asked again. Owner question 11.
- **Ruling R-W9-9:** the export's own-data scope: enrolment, profile, the person's own sensitive answers (decrypted), preferences, settings, prompts, photos (metadata only, no files), consents, verification results, trusted phones (dates only), never-introduce labels (no digits), the gentle-wait reflection, date reflections, conversations (`conversation-n`, matched date, open or ended, and only their own sent messages, as written), reports they made (category, details, date; never whom), restrictions and appeals. No counterpart's name, age, message or the reason a chat ended; no id. `NULL` (no `dating.json`) with no Dating data. A missing field key raises `export:unavailable` (the worker retries). Owner question 8; counsel's W9 gate.
- **Ruling R-W9-10:** How we met holds the first 50 messages both could see (text and revealed guided answers; Close kindly's message excluded), ordered as the chat shows them, each `{by, kind, question_id, text, at}` (`by` the sender's id; the reads say `mine`, the export `me`/`partner`). Owner question 6.
- **Ruling R-W9-11:** flags: asking, the second Yes and the link page need `dating_couple_link` and the chat's flags; the origin, How we met and the offer need `dating_couple_link`; Not right now and taking back need none. Owner question 7.
- **Ruling R-W9-12:** `dating_weMetNoted` ("Noted that you met.") is unchanged; the Become a couple copy never says who said We met (carry 8). Owner question 10.
- **Ruling R-W9-13:** the push audit (carry 1) follows writes by operation (an INSERT to the INSERT triggers, …) and treats the push queue's own triggers (its guards) as before: audited only when they are Dating's. With that, the extended walk reaches no new non-neutral writer and needs no exemption.
- **Ruling R-W9-14:** the app's files live in `lib/features/dating/link/` (the Dating feature's layout since W3a; §3.9 says `presentation/link/`). The About us "client override" is the provider's own body (I-12 forbids touching Spec 1's SQL, and the only `ProviderScope` is in the off-limits `lib/main.dart`). Cost if wrong: a file move.
- **Ruling R-W9-16 (the controller's; as built, Task 5 fix rounds 1 and 2, Task 7):** the Relationship home and About us make **no** couple-link call unless the app knows `dating_couple_link` is on. Dating's flags are server-only (`feature_flags` RLS hides `dating_%` rows). `get_dating_home()` is re-created from its live body with one marked change: every answer to a signed-in caller carries `couple_link: true` while the flag is on, nothing while it is off (contract E6), including the `reverify_device` answer a request with no device header gets. The app learns it from **one** `get_dating_home()` read per account per process: `datingCoupleLinkReadProvider(account)` (`lib/features/dating/link/dating_link.dart`) reads through `coupleLinkFlagReadProvider` (`lib/core/flags/couple_link_flag.dart`, new), which calls the RPC on the app's own client (`supabaseClientProvider`), never Dating's, so no install id goes out (every couple makes this read, Dating or not; it is not Dating traffic, S-7, R15; without the header `get_dating_home()` stores nothing). An answer is kept for the process (`keepAlive`) and is not re-read on resume; a failed read is off (fail closed) and is read again on the next resume or reconnect, only while it has failed; another account reads anew (D8). `DatingFeatureFlags.flagsFrom` turns the answer into flags; `datingCoupleLinkOnProvider` gates the offer, the origin and How we met. **The user manual is untouched:** `documentation_flags.dart` and its source pins are HEAD's (the plan's first design, the manual's `documentationFlagsProvider`, was withdrawn: it is about ten reads, re-read on every resume, and would have put them on every couple's home). `test/architecture/dating_device_header_test.dart` names `couple_link_flag.dart` as the one deliberate exception to W4b's rule that Dating uses only Dating's client. With the flag off in production: one `get_dating_home()` read per couple account per process, and no offer, origin or How we met call. Cost: a server-side flag flip reaches a running app only at its next launch or account switch.
- **Ruling R-W9-15:** the export's Deno step is its own module, `dating_part.ts`, whose tests run in the frozen-lock CI line; `parts.ts`' own tests import `fflate`, which the lock doesn't hold, so the gate runs `build-data-exports/` with `--no-lock` (not CI).

## Owner questions (decisions only the owner can make; the build proceeds on each default)

1. **No internal SQL for the invite's pending row.** `create-relationship-invite` inserts it in TypeScript. Default: the second Yes inserts the same columns itself and calls `accept_relationship_invite_v2` unchanged; L9 proves link = invite. Alternative: extract `private.create_relationship_invite_row()` and change the edge function to call it (an invite-path edit this wave may not make).
2. **Invite metrics.** Reusing `accept_relationship_invite_v2` bumps `invite_accepted`, `_24h` and `_7d` for every Dating link. Default: accept it (aggregate counts, no Dating word; `dating.couple_link` counts links separately). Alternative: subtract `dating.couple_link` in the dashboard.
3. **A push to the asker when the other says yes.** Default: none (R-W9-7); they see "You decided together." at their next open. Alternative: the neutral "You have something new in Attune." (`me_update`, to Me).
4. **After "Not right now".** Default: the asker can ask again 14 days later; the decliner any time. Alternative: never again from that chat, or 7 days.
5. **Plan copy to sign off** (copy, DV and LGBTQ+ reviewers): "You've asked {Name}.", "Take it back", "This isn't possible right now.", "Your Dating profiles are paused.", "How we met", "Opens your first messages", "Your first messages, as you both saw them.", "You", "Your partner"; the HomeCard's spoken label "Your Dating profile" (English, like the other cards). Default: ship as Plan copy behind the off flag; sign before production.
6. **What How we met keeps.** Default: the first 50 text messages and revealed guided answers both could see, masked unless both swapped, Close kindly's message excluded, no photos. Alternative: text only, or a different count.
7. **The couple's card when Dating is switched off.** Default: How we met and the match-date chip follow `dating_couple_link` (hidden while it is off; the rows stay). Alternative: always shown to a couple that kept it.
8. **The export's scope** (counsel's W9 gate). Default: R-W9-9 (own data, own sent messages, reports made with their details, never-introduce labels without digits, photo metadata without files). Alternatives: include photo files (the media manifest), or leave out report details.
9. **A same-gender couple linking while one is in a Tier 1 country.** Default: allowed when the chat shows on that phone (the person chose "Show it on this phone anyway"); the Relationship space does not hide by trip. LGBTQ+ reviewer to confirm.
10. **Does "We met" tell the other person?** Default: "Noted that you met." stays as it is; the other side only sees Become a couple on Attune appear. Alternative: "Noted that you met. {Name} can see this."
11. **"Delete my Dating data".** Default: opens Leave Dating (its deleted/kept lists, "Pause instead"). Alternative: a one-tap delete from the card.
12. **Where the asker sees "You decided together."** Default: chat, link page or the Relationship home's card, whichever comes first (R-W9-3). Alternative: only on the Relationship home.
13. **HomeCard label language.** Default: the English literal "Your Dating profile" (the other cards' labels are English literals). Alternative: localise all card labels (a Relationship-file change).

## Interfaces this plan consumes (read from the current code)

- **Spec 1 / Relationship:** `public.accept_relationship_invite_v2(uuid, text)` (service role; the invite exchange's), `public.set_user_path_internal(uuid, text)`, `public.adopt_couple_profile_drafts` (through accept), `relationships` triggers (`relationship_dating_guard` → `sync_dating_pause_on_relationship` → `pause_dating_for_relationship_user`, `relationship_one_open_chapter_guard`, `relationship_archive_on_new_chapter`), `public.account_holds`, `public.data_export_jobs`, `public.export_who`, `private.bump_metric_internal`, `private.flag_production_gates`; app: `aboutUsDateSuggestionsProvider`, `AboutUsDateSuggestion`, `TogetherSince`, `DatePrecision`, `AboutUsScreen`, `ConversationsScreen`, `HomeCard`, `ReorderableHomeCards`, `resolveHomeCardOrder`, `homeCardOrderRepositoryProvider`, `CardInkWell`, `homeStateProvider`, `relationshipModeResyncSignal`, `homeLocation`, `AppTab`, `currentLocaleProvider`, `MyDateFormat`, `expectFlowGoldens`, `expectFlowGuidelines`, `pumpFlowScreen`, `tapInReach`, `FakeCoupleProfileServer`, `aboutUsJson`.
- **S2 W1–W8 (live):** `public.dating_matches` (`closed_reason` already allows `couple_linked` and `other_linked`), `public.dating_messages`, `private.dating_message_visible`, `private.dating_message_sort_at`, `private.dating_pair_blocked`, `private.dating_bump_chat`, `private.dating_lock_setup`, `private.dating_lock_setup_pair`, `private.dating_key_ok`, `private.dating_chat_on`, `public.dating_flag_enabled`, `public.dating_require_trusted_device`, `private.dating_same_gender_hiding`, `private.dating_trip_hides(uuid,uuid,text,boolean)`, `private.dating_chat_header` (re-created), `public.get_dating_messages`, `private.dating_has_data`, `private.dating_field_decrypt`, `private.dating_exit_internal`; app: `DatingRpc`, `DatingBusy`, `DatingActionKeys`, `datingRpcProvider`, `datingAccountProvider`, `DatingTripPhone.showFor`, `datingRoute`, `DatingPaths`, `DatingRootBack`, `datingRootBackButton`, `DatingCalmLine`, `DatingReverifyLine`, `datingSheetRefused`, `datingOnlineProvider`, `DatingChatHeader`, `showDatingSafetySheet`, `DatingSafetyChoice`, `reduceMotionOf`; test support `pumpDatingShell`, `datingShellOverrides`, `datingTestAccount`, `FakeDatingChat`, `datingPageJson`, `datingChatOverrides`.

## Interfaces this plan produces (for W10 onward)

- **SQL:** flag `dating_couple_link` (off) and its production gate; tables `dating_couple_link_requests`, `couple_how_we_met`, `dating_link_origins`, `dating_export_reads`; `public.get_dating_couple_link(uuid, boolean) → {ok, display_name, link}`; `public.request_dating_couple_link(p_key text, p_match_id uuid, p_keep_messages boolean, p_show_same_gender boolean DEFAULT false) → {ok, request_id}` | `{ok:false, reason: invalid|unavailable|reverify_device|match_unavailable|closed|asked_you|not_yet|not_ready|busy}`; `public.confirm_dating_couple_link(p_key text, p_request_id uuid, p_keep_messages boolean, p_show_same_gender boolean DEFAULT false) → {ok, relationship_id}` | `{ok:false, reason: invalid|unavailable|reverify_device|request_unavailable|match_unavailable|asked|closed|busy}`; `public.decline_dating_couple_link(uuid)`, `public.cancel_dating_couple_link(uuid) → {ok}` | `{ok:false, reason: invalid|request_unavailable|linked|busy}`; `public.get_dating_link_origin(uuid) → {ok, matched_at}` | `link_origin_unavailable`; `public.get_how_we_met(uuid) → {ok, items:[{mine, kind, question_id, text, at}]}` | `how_we_met_unavailable`; `public.get_dating_post_link_offer() → {ok, offer: null|'linked'|'delete'}`; `public.dismiss_dating_post_link_offer(p_offer text) → {ok}` | `invalid|offer_unavailable`; `public.dating_export_for_job(uuid) → jsonb | NULL` (service role; raises `export:not_building`, `export:read_limit`, `export:unavailable`); `get_dating_home()` + `couple_link: true` while the flag is on (R-W9-16); `private.dating_link_on()`, `private.dating_link_blocked(uuid)`, `private.dating_link_json(dating_matches, text)`; `export_relationship` + `how_we_met`; the chat header's `link`.
- **Edge:** `build-data-exports/dating_part.ts` (`addDatingPart(supabase, jobId, zip) → Promise<boolean>`, `DatingZip`).
- **App:** `lib/features/dating/link/{dating_link.dart (DatingLinkState, DatingLink, DatingLinkPage, DatingLinkAnswer, DatingPostLinkOffer, DatingHowWeMetItem, DatingLinkGateway, DatingLinkRepository, datingLinkGatewayProvider, datingPostLinkOfferProvider, datingLinkOriginProvider, datingHowWeMetProvider, datingLinkReasons), link_screen.dart (DatingLinkScreen, DatingLinkMoment, datingGoToCouple, datingLinkName, kDatingLinkSettle), link_offer_card.dart (DatingLinkOfferCard, datingLinkOfferShown, datingLinkOfferCardId, datingLinkOfferCardLabel), how_we_met.dart (datingAboutUsDateSuggestions, DatingHowWeMetRow, DatingHowWeMetScreen)}`; `DatingChatHeader.link`; `DatingFeatureFlags.coupleLink`, `DatingFeatureFlags.flagsOn`, `DatingFeatureFlags.flagsFrom`, `datingCoupleLinkOnProvider`; `DatingSafetyChoice.becomeCouple`; `showDatingSafetySheet(canLink:)`; `DatingPaths.link(matchId)`; route `datingLink`; test support `FakeDatingLink`, `datingLinkOverrides`.

## File map

**W9a.** Task 1 creates `supabase/tests/dating_v2_link_contracts.sql`, `$D/{before_w9/, mig_T1_head.sql, build_mig_W9.py, edit_tests_T1.py, mut_T1.py, sql-baseline.txt, analyze-baseline.txt, flutter-baseline.txt}`, `supabase/migrations/20261123100000_dating_v2_couple_link.sql` (built), `…100010_…_grants.sql`; modifies the canary, the device contract (B12), `service_role_grants_test.sql`, `scripts/local_pg_grants.sql`. Task 2 creates `$D/{mig_T2.sql, edits_T2.py, twin_T2.sql, contract_T2.sql, edit_tests_T2.py, mut_T2.py}`; rebuilds the migration and the twin; modifies the link contract, the canary, `data_export_contracts.sql`, `service_role_grants_test.sql`, and the reflections, never-introduce and photos pins (`dating_v2_{home,identity,setup}_contracts.sql`). Task 3 creates `$D/{edit_tests_T3.py, edit_tests_T3b.py, race_T3.sh, edit_race_T3.py, mut_T3.py}`; modifies the device contract (§A, C1d) and the race script. Task 4 creates `supabase/functions/build-data-exports/{dating_part.ts, dating_part.test.ts}`, `$D/{edit_export_T4.py, edit_deno_T4.py, mut_T4.py, gate.sh}`; modifies `parts.ts`, `_architecture/push_queue_writers.test.ts`, `tests.yml`.

**W9b.** Task 5 creates `lib/features/dating/link/{dating_link.dart, link_screen.dart}`, `test/features/dating/support/dating_link_fakes.dart`, `test/features/dating/link/link_test.dart` and its goldens, `$D/{edit_app_T5.py, arb_fragment_T5.txt, edit_tests_T5.py, mut_T5_dart.py}`; modifies `dating_chat.dart`, `chat_sheets.dart`, `dating_chat_screen.dart`, `dating_routes.dart`, the ARB and generated files, `dating_shell.dart`, `text_scale_routes_test.dart`. Task 6 creates `lib/features/dating/link/{link_offer_card.dart, how_we_met.dart}`, `test/features/dating/link/relationship_side_test.dart`, `$D/{edit_app_T6.py, mut_T6_dart.py}`; modifies `conversations_screen.dart`, `couple_profile_providers.dart`, `about_us_screen.dart`. Task 7 creates `$D/edit_docs_T7.py`; modifies the design spec (seven `amended S2 W9` notes) and `supabase/sql/dev_enable_spec2_dating_flags.sql`.

**Not edited:** `lib/main.dart`, `lib/app/app.dart`, `lib/app/routing/app_router.dart`, `lib/home/home_screen.dart`, `chat_screen.dart`, `quick_exit_service.dart`, `auth_provider.dart`, `lib/features/games/**`, Opinions, every invite function, screen and edge function, `accept_relationship_invite_v2`, `set_user_path_internal`, every applied migration, `scripts/local_pg_setup.sh`, every edge function but `build-data-exports`, `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`.

---

## Batch W9a — the couple link, its origin and the export (server)

### Task 1: Migration `dating_v2_couple_link` (part 1): the flag, the request, the second Yes through the invite exchange, the chat's link, and contract L (§3.9 steps 1–3, §4.3, §4.4, §4.9 W9, §7.1; mutant 21; R-W9-1, R-W9-2, R-W9-4–R-W9-7, R-W9-10, R-W9-11)

**Files:**
- Create: `supabase/tests/dating_v2_link_contracts.sql`, `$D/{before_w9/, mig_T1_head.sql, build_mig_W9.py, edit_tests_T1.py, mut_T1.py, sql-baseline.txt, analyze-baseline.txt, flutter-baseline.txt}`, `supabase/migrations/20261123100000_dating_v2_couple_link.sql` (built), `supabase/migrations/20261123100010_dating_v2_couple_link_grants.sql`
- Modify: `supabase/tests/dating_rls_canary.sql`, `supabase/tests/dating_v2_device_contracts.sql` (B12's catalogue), `supabase/tests/service_role_grants_test.sql` (the couple link's tables, S-5), `scripts/local_pg_grants.sql` (one `\i` line)
- Test: `dating_v2_link_contracts.sql` L1–L9

**Interfaces:**
- Consumes: see "Interfaces this plan consumes"; the live `private.dating_chat_header(dating_matches,text)` and `public.export_relationship(uuid,uuid)` (saved in Step 2).
- Produces: the couple link's tables and functions (see "Interfaces this plan produces"); for Task 2 the markers `-- @@W9-T2@@` (head, contract), `-- @@W9-T2-GRANTS@@` (twin), `-- @@W9-T2-CANARY@@` (canary).

- [ ] **Step 1: The tool folder and the baselines**

```bash
D=.superpowers/sdd/2026-11-23-spec2-w9; W8=.superpowers/sdd/2026-11-22-spec2-w8
ls $D/carries.md
for f in suite.sh anchor.py splice.py mutate.py mirror.py dmut.py denomut.py grants_line.py marked_diff.py; do cp $W8/$f $D/; done
sed -i '' 's/W8_DB/W9_DB/g; s/Spec 2 W8 mutation runner/Spec 2 W9 mutation runner (W8'"'"'s)/; s/of it when the plan says so/of it: the replay passes its clone/' $D/mutate.py
sed -i '' 's/w8dmut-/w9dmut-/; s/Spec 2 W8 Dart mutation runner (W7'"'"'s dmut.py/Spec 2 W9 Dart mutation runner (W8'"'"'s dmut.py/' $D/dmut.py
sed -i '' 's/w8denomut-/w9denomut-/; s/Spec 2 W8 Deno mutation runner (W7'"'"'s/Spec 2 W9 Deno mutation runner (W8'"'"'s/' $D/denomut.py
sed -i '' 's/Spec 2 W8 (lesson from W7/Spec 2 W9 (W8'"'"'s; lesson from W7/' $D/mirror.py
grep -c W9_DB $D/mutate.py
ls supabase/migrations | sort | tail -1
psql -X -d attune_spec3a -Atc 'select current_database()'
bash $D/suite.sh attune_spec3a > $D/sql-baseline.txt; echo "$(grep -c '^PASS' $D/sql-baseline.txt) PASS $(grep -c '^FAIL' $D/sql-baseline.txt) FAIL"
flutter analyze --no-pub lib test > $D/analyze-baseline.txt 2>&1; tail -1 $D/analyze-baseline.txt
flutter test --no-pub --reporter compact > $D/flutter-baseline.txt 2>&1; tr '\r' '\n' < $D/flutter-baseline.txt | grep -E '^[0-9:]+ \+[0-9]+' | tail -1 | grep -oE '\+[0-9]+( -[0-9]+)?'
```

Expected: `carries.md`; `2`; `20261122100010_dating_v2_traveller_grants.sql`; `attune_spec3a`; `163 PASS 14 FAIL` (by day; at night `162 PASS 15 FAIL`, the extra one `quiet_hours_contracts.sql`); `571 issues found. (ran in …)`; `+9621 -3` (the three `healing_journal_large_text` goldens).

- [ ] **Step 2: Save the live bodies Tasks 1 and 2 re-create (before anything is applied: the chat header, `export_relationship`, `get_dating_home`)**

```bash
D=.superpowers/sdd/2026-11-23-spec2-w9; mkdir -p $D/before_w9
for sig in "private.dating_chat_header(dating_matches,text)" "public.export_relationship(uuid,uuid)" "public.get_dating_home()"; do
  psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)" > "$D/before_w9/$sig.sql"
done
ls $D/before_w9 | wc -l | tr -d ' '
```

Expected: `3`.

- [ ] **Step 3: Write contract L**

Create `supabase/tests/dating_v2_link_contracts.sql` with exactly:

````sql
-- supabase/tests/dating_v2_link_contracts.sql
-- Spec 2 W9 (§3.9, §4.3, §4.4, §7.1; S-4, S-5, S-6, A-3, I-12, I-13):
-- "Become a couple on Attune" and the export's own-data Dating part.
--   L (Task 1). The couple link: no relationships row before both say
--      yes; the second Yes makes an active relationship through the
--      invite exchange's rows, pauses both, closes every other open
--      conversation with the neutral reason, sets both paths; the first
--      messages are kept only when both chose it, masked unless both
--      swapped (A-3); a request says nothing about the other person (S-5,
--      carry 5).
--   E (Task 2). The origin, How we met, the post-link offer, the export.
-- Fixture ids 8a900000-0000-0000-0000-0000000000nn, phones +1555982nn:
-- L 01-49, E 50-89.
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_link_contracts.sql
BEGIN;

-- =====================================================================
-- Setup: the keys, the flags (dating_couple_link is turned on below, after
-- L1 reads it off, inside this file's transaction), Ghana and the UK open.
-- =====================================================================
DO $$
BEGIN
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w9-link-key', true);
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w9-field-key-0123456789abcdef-0123', true);
  PERFORM set_config('app.settings.dating_push_key', 'spec2-w9-push-key', true);
END $$;
SELECT private.seed_dating_exclusion_key_fingerprint() AS seeded \gset
SELECT private.seed_dating_field_key_fingerprint() AS seeded_field \gset
INSERT INTO public.feature_flags (key, enabled)
VALUES ('dating_mode_enabled', true), ('dating_same_gender_matching', true), ('dating_match_messaging', true),
       ('dating_profile_photos', true)
ON CONFLICT (key) DO UPDATE SET enabled = true;
SELECT public.publish_country_config('GH', '{"dating_enabled": true, "open_regions": ["AA", "AH"]}') AS gh \gset
SELECT public.publish_country_config('GB', '{"dating_enabled": true}') AS gb \gset

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('8a900000-0000-0000-0000-' || lpad(p_n, 12, '0'))::uuid;
$$;
CREATE FUNCTION pg_temp.dev(p_n text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT md5('w9-link-' || p_n);
$$;
CREATE FUNCTION pg_temp.hash(p_n text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT encode(extensions.digest(pg_temp.dev(p_n), 'sha256'), 'hex');
$$;
-- A person in Dating, active, verified, on their trusted phone.
CREATE FUNCTION pg_temp.ready(p_n text, o jsonb DEFAULT '{}') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_u constant uuid := pg_temp.id(p_n);
  d constant jsonb := '{"identity": "woman", "seeking": ["man"], "country": "GH", "region": "AA", "years": 30,
    "days": 40, "state": "active"}'::jsonb || o;
  v_phone constant text := '+1555982' || p_n;
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (v_u, ltrim(v_phone, '+'), now(), now() - make_interval(days => (d ->> 'days')::int));
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (v_u, v_phone, 'Link ' || p_n, 'dating', now() - make_interval(days => (d ->> 'days')::int), now(), '2');
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (v_u, (current_date - make_interval(years => (d ->> 'years')::int) - interval '10 days')::date);
  INSERT INTO public.dating_enrollments (user_id, state, opted_in_at, activated_at)
  VALUES (v_u, d ->> 'state', now(), CASE WHEN d ->> 'state' = 'active' THEN now() END);
  INSERT INTO public.dating_profiles (user_id, display_name, profile_state, moderation_state, verification_state,
    country_code, region_code, intention, timeline_visible, not_married_attested_at, attestation_version,
    children_have, children_want, faith_visible)
  VALUES (v_u, 'Link ' || p_n, 'active', 'approved', 'verified', d ->> 'country', d ->> 'region',
    'committed', true, now(), '2026-10-v1', false, 'yes', false);
  INSERT INTO public.dating_preferences (user_id, min_age, max_age, region_scope, open_abroad, want_must_match, exclude_parents)
  VALUES (v_u, 25, 40, 'country', '{}', false, false);
  INSERT INTO public.dating_profile_sensitive (user_id, identity_enc, seeking_enc)
  VALUES (v_u, private.dating_field_encrypt(jsonb_build_object('identity', d ->> 'identity', 'pools', jsonb_build_array(d ->> 'identity'))),
          private.dating_field_encrypt(jsonb_build_object('seeking', d -> 'seeking')));
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT v_u, 'w9-consent-' || p, p, 'granted', 'dating-2.0', clock_timestamp()
    FROM unnest(ARRAY['dating_terms', 'dating_opt_in', 'special_category_profile']) AS p;
  INSERT INTO public.dating_trusted_devices (user_id, device_hash, verified_at, last_seen_at)
  VALUES (v_u, pg_temp.hash(p_n), now(), now());
  RETURN v_u;
END $$;
-- A UK person (region TLI).
CREATE FUNCTION pg_temp.uk(p_n text, o jsonb DEFAULT '{}') RETURNS uuid LANGUAGE sql AS $$
  SELECT pg_temp.ready(p_n, '{"country": "GB", "region": "TLI"}'::jsonb || o);
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
CREATE FUNCTION pg_temp.key(p text) RETURNS text LANGUAGE sql AS $$
  SELECT 'w9-' || p || '-' || replace(gen_random_uuid()::text, '-', '');
$$;
CREATE FUNCTION pg_temp.match(p_a uuid, p_b uuid, p_days int DEFAULT 10) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, matched_at, pair_key, chat_started_at)
  VALUES (least(p_a, p_b), greatest(p_a, p_b), 'active', now() - make_interval(days => p_days), public.dating_pair_key(p_a, p_b),
          now() - make_interval(days => p_days))
  RETURNING id;
$$;
-- [p]'s side of match [m].
CREATE FUNCTION pg_temp.side(m uuid, p uuid) RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN x.user_low_id = p THEN 'low' ELSE 'high' END FROM public.dating_matches AS x WHERE x.id = m;
$$;
-- A message from [p] in [m], [p_min] minutes ago (masked text 'masked n').
CREATE FUNCTION pg_temp.say(m uuid, p uuid, p_n int, p_min int, p_kind text DEFAULT 'text', p_q text DEFAULT NULL)
RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.dating_messages (match_id, sender_side, sender_user_id, kind, question_id, body, body_masked,
                                      mask_version, idempotency_key, created_at)
  VALUES (m, pg_temp.side(m, p), p, p_kind, p_q, 'plain ' || p_n, 'masked ' || p_n, 1, 'w9-say-' || m || '-' || p_n,
          now() - make_interval(mins => p_min));
$$;
CREATE FUNCTION pg_temp.we_met(m uuid, p uuid) RETURNS void LANGUAGE sql AS $$
  UPDATE public.dating_matches SET low_we_met_at = CASE WHEN user_low_id = p THEN now() ELSE low_we_met_at END,
                                   high_we_met_at = CASE WHEN user_high_id = p THEN now() ELSE high_we_met_at END
   WHERE id = m;
$$;
CREATE FUNCTION pg_temp.swap(m uuid) RETURNS void LANGUAGE sql AS $$
  UPDATE public.dating_matches SET low_swap_at = now(), high_swap_at = now() WHERE id = m;
$$;
CREATE FUNCTION pg_temp.ask(p uuid, p_n text, m uuid, p_keep boolean, p_show boolean DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, p_n, format('SELECT public.request_dating_couple_link(%L, %L, %L%s)', pg_temp.key('ask'), m, p_keep,
                                  CASE WHEN p_show IS NULL THEN '' ELSE format(', p_show_same_gender => %L', p_show) END));
$$;
CREATE FUNCTION pg_temp.yes(p uuid, p_n text, r uuid, p_keep boolean, p_show boolean DEFAULT NULL, p_key text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, p_n, format('SELECT public.confirm_dating_couple_link(%L, %L, %L%s)', coalesce(p_key, pg_temp.key('yes')), r, p_keep,
                                  CASE WHEN p_show IS NULL THEN '' ELSE format(', p_show_same_gender => %L', p_show) END));
$$;
CREATE FUNCTION pg_temp.no(p uuid, p_n text, r uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, p_n, format('SELECT public.decline_dating_couple_link(%L)', r));
$$;
CREATE FUNCTION pg_temp.take_back(p uuid, p_n text, r uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, p_n, format('SELECT public.cancel_dating_couple_link(%L)', r));
$$;
-- The chat header's link, and the link page's read, as [p] sees [m].
CREATE FUNCTION pg_temp.link(p uuid, p_n text, m uuid, p_show boolean DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
  SELECT coalesce(v -> 'chat' -> 'link', CASE WHEN v ->> 'ok' = 'true' THEN 'null'::jsonb
                                              ELSE jsonb_build_object('read', coalesce(v ->> 'reason', v ->> 'raised')) END)
    FROM (SELECT pg_temp.j(p, p_n, format('SELECT public.get_dating_messages(%L%s)', m,
                           CASE WHEN p_show IS NULL THEN '' ELSE format(', p_show_same_gender => %L', p_show) END)) AS v) AS x;
$$;
CREATE FUNCTION pg_temp.page(p uuid, p_n text, m uuid, p_show boolean DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, p_n, format('SELECT public.get_dating_couple_link(%L%s)', m,
                   CASE WHEN p_show IS NULL THEN '' ELSE format(', p_show_same_gender => %L', p_show) END));
$$;
-- Every relationships row either person is in.
CREATE FUNCTION pg_temp.rels(p_a uuid, p_b uuid) RETURNS bigint LANGUAGE sql AS $$
  SELECT count(*) FROM public.relationships AS r WHERE r.user_a IN (p_a, p_b) OR r.user_b IN (p_a, p_b);
$$;
-- dating-device-check's call, as the service role (a same-gender trip).
CREATE FUNCTION pg_temp.check(p uuid, p_n text, p_ip text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.record_dating_device_check(p, pg_temp.hash(p_n), p_ip, NULL);
  RESET ROLE;
  RETURN v;
END $$;

-- =====================================================================
-- L1. The flag is off as the migration leaves it, with its production
--     gate; with it off nothing links. The couple link's functions are
--     the app's alone; its tables nobody's (S-5).
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('01');
  v_b constant uuid := pg_temp.ready('02', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v_t text;
BEGIN
  IF (SELECT enabled FROM public.feature_flags WHERE key = 'dating_couple_link') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_couple_link is not off';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM private.flag_production_gates WHERE flag_key = 'dating_couple_link') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_couple_link has no production gate';
  END IF;
  v_m := pg_temp.match(v_a, v_b);
  PERFORM pg_temp.we_met(v_m, v_a);
  IF pg_temp.ask(v_a, '01', v_m, true) ->> 'reason' IS DISTINCT FROM 'unavailable'
     OR pg_temp.page(v_a, '01', v_m) ->> 'reason' IS DISTINCT FROM 'unavailable'
     OR pg_temp.link(v_a, '01', v_m) IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the flag off the couple link answers: % / % / %',
      pg_temp.ask(v_a, '01', v_m, true), pg_temp.page(v_a, '01', v_m), pg_temp.link(v_a, '01', v_m);
  END IF;
  FOREACH v_t IN ARRAY ARRAY['public.get_dating_couple_link(uuid,boolean)',
                             'public.request_dating_couple_link(text,uuid,boolean,boolean)',
                             'public.decline_dating_couple_link(uuid)', 'public.cancel_dating_couple_link(uuid)',
                             'public.confirm_dating_couple_link(text,uuid,boolean,boolean)'] LOOP
    IF NOT has_function_privilege('authenticated', v_t, 'EXECUTE') OR has_function_privilege('anon', v_t, 'EXECUTE')
       OR has_function_privilege('service_role', v_t, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % is not the app''s alone', v_t;
    END IF;
  END LOOP;
  FOREACH v_t IN ARRAY ARRAY['public.dating_couple_link_requests', 'public.couple_how_we_met', 'public.dating_link_origins'] LOOP
    IF has_table_privilege('anon', v_t, 'SELECT') OR has_table_privilege('authenticated', v_t, 'SELECT')
       OR has_table_privilege('service_role', v_t, 'SELECT') OR has_table_privilege('service_role', v_t, 'INSERT') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % is readable or writable by an API role (S-5)', v_t;
    END IF;
  END LOOP;
END $$;

UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_couple_link';

-- =====================================================================
-- L2. Before either says We met there is nothing to ask (not_yet; the
--     header offers nothing); once either has, both may (state none). The
--     link page reads the other person's first name. The answers are the
--     same as the chat's header.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('03');
  v_b constant uuid := pg_temp.ready('04', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v jsonb;
BEGIN
  v_m := pg_temp.match(v_a, v_b);
  IF pg_temp.link(v_a, '03', v_m) IS DISTINCT FROM 'null'::jsonb
     OR pg_temp.ask(v_a, '03', v_m, false) ->> 'reason' IS DISTINCT FROM 'not_yet' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Become a couple is offered before We met: %', pg_temp.link(v_a, '03', v_m);
  END IF;
  PERFORM pg_temp.we_met(v_m, v_b);
  v := pg_temp.page(v_a, '03', v_m);
  IF pg_temp.link(v_a, '03', v_m) IS DISTINCT FROM '{"state": "none"}'::jsonb
     OR pg_temp.link(v_b, '04', v_m) IS DISTINCT FROM '{"state": "none"}'::jsonb
     OR v IS DISTINCT FROM jsonb_build_object('ok', true, 'display_name', 'Link 04', 'link', '{"state": "none"}'::jsonb) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after the other side''s We met: % / % / %', pg_temp.link(v_a, '03', v_m),
      pg_temp.link(v_b, '04', v_m), v;
  END IF;
  IF pg_temp.page(v_a, NULL, v_m) ->> 'reason' IS DISTINCT FROM 'reverify_device'
     OR pg_temp.page(pg_temp.ready('05'), '05', v_m) ->> 'reason' IS DISTINCT FROM 'match_unavailable'
     OR pg_temp.ask(pg_temp.id('05'), '05', v_m, false) ->> 'reason' IS DISTINCT FROM 'match_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the link page answers another phone or a stranger';
  END IF;
END $$;

-- =====================================================================
-- L3. Asking (step 1): the asker's Yes and keep choice; a replay is the
--     same request; the other side sees asked_you, the asker asked; no
--     relationships row before both say yes (mutant 21), not even when the
--     asker "confirms" their own request; the other side's own ask is
--     asked_you; nothing is said about the other person.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('06');
  v_b constant uuid := pg_temp.ready('07', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v jsonb;
  v_r uuid;
BEGIN
  v_m := pg_temp.match(v_a, v_b);
  PERFORM pg_temp.we_met(v_m, v_a);
  v := pg_temp.ask(v_a, '06', v_m, true);
  v_r := (v ->> 'request_id')::uuid;
  IF (v ->> 'ok')::boolean IS NOT TRUE OR v_r IS NULL
     OR pg_temp.ask(v_a, '06', v_m, true) IS DISTINCT FROM v THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: asking (or its replay) answered % / %', v, pg_temp.ask(v_a, '06', v_m, true);
  END IF;
  IF pg_temp.link(v_a, '06', v_m) IS DISTINCT FROM jsonb_build_object('state', 'asked', 'request_id', v_r)
     OR pg_temp.link(v_b, '07', v_m) IS DISTINCT FROM jsonb_build_object('state', 'asked_you', 'request_id', v_r) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the headers after asking: % / %', pg_temp.link(v_a, '06', v_m), pg_temp.link(v_b, '07', v_m);
  END IF;
  IF (SELECT count(*) FROM public.dating_couple_link_requests WHERE match_id = v_m) <> 1
     OR (SELECT r.state || ':' || r.requested_by_side || ':' || (CASE WHEN r.requested_by_side = 'low' THEN r.low_keep_messages
                                                                    ELSE r.high_keep_messages END)
           FROM public.dating_couple_link_requests AS r WHERE r.id = v_r) IS DISTINCT FROM 'open:' || pg_temp.side(v_m, v_a) || ':true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the request row is wrong';
  END IF;
  IF pg_temp.rels(v_a, v_b) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a relationships row exists after the first Yes';
  END IF;
  v := pg_temp.yes(v_a, '06', v_r, true);
  IF v IS DISTINCT FROM '{"ok": false, "reason": "asked"}'::jsonb OR pg_temp.rels(v_a, v_b) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the asker''s own confirmation made the couple: %', v;
  END IF;
  IF pg_temp.ask(v_b, '07', v_m, false) IS DISTINCT FROM '{"ok": false, "reason": "asked_you"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the other side could open a second request';
  END IF;
  IF (SELECT state FROM public.dating_enrollments WHERE user_id = v_a) IS DISTINCT FROM 'active'
     OR (SELECT path FROM public.users WHERE id = v_b) IS DISTINCT FROM 'dating' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: asking changed someone''s Dating or path';
  END IF;
END $$;

-- =====================================================================
-- L4. "Not right now" (step 2) and taking it back: only the other side
--     declines, only the asker takes back (each replay ok); the asker then
--     reads not_ready and can't ask again for 14 days; the decliner may ask
--     at once; after 14 days the asker may ask again.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('08');
  v_b constant uuid := pg_temp.ready('09', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v_r uuid;
  v_r2 uuid;
BEGIN
  v_m := pg_temp.match(v_a, v_b);
  PERFORM pg_temp.we_met(v_m, v_a);
  v_r := (pg_temp.ask(v_a, '08', v_m, false) ->> 'request_id')::uuid;
  IF pg_temp.no(v_a, '08', v_r) ->> 'reason' IS DISTINCT FROM 'request_unavailable'
     OR pg_temp.take_back(v_b, '09', v_r) ->> 'reason' IS DISTINCT FROM 'request_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the wrong side could decline or take back';
  END IF;
  IF pg_temp.no(v_b, '09', v_r) IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.no(v_b, '09', v_r) IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Not right now (or its replay) failed';
  END IF;
  IF pg_temp.link(v_a, '08', v_m) IS DISTINCT FROM '{"state": "not_ready"}'::jsonb
     OR pg_temp.link(v_b, '09', v_m) IS DISTINCT FROM '{"state": "none"}'::jsonb
     OR pg_temp.ask(v_a, '08', v_m, false) IS DISTINCT FROM '{"ok": false, "reason": "not_ready"}'::jsonb
     OR pg_temp.yes(v_b, '09', v_r, false) ->> 'reason' IS DISTINCT FROM 'request_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after Not right now: % / % / %', pg_temp.link(v_a, '08', v_m), pg_temp.link(v_b, '09', v_m),
      pg_temp.ask(v_a, '08', v_m, false);
  END IF;
  v_r2 := (pg_temp.ask(v_b, '09', v_m, false) ->> 'request_id')::uuid;
  IF v_r2 IS NULL OR pg_temp.take_back(v_b, '09', v_r2) IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.take_back(v_b, '09', v_r2) IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.link(v_a, '08', v_m) IS DISTINCT FROM '{"state": "not_ready"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the decliner''s own ask and its take-back: %', pg_temp.link(v_a, '08', v_m);
  END IF;
  UPDATE public.dating_couple_link_requests SET decided_at = now() - interval '13 days' WHERE id = v_r;
  IF pg_temp.ask(v_a, '08', v_m, false) IS DISTINCT FROM '{"ok": false, "reason": "not_ready"}'::jsonb
     OR pg_temp.link(v_a, '08', v_m) IS DISTINCT FROM '{"state": "not_ready"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 13 days after Not right now the asker could ask again';
  END IF;
  UPDATE public.dating_couple_link_requests SET decided_at = now() - interval '15 days' WHERE id = v_r;
  IF (pg_temp.ask(v_a, '08', v_m, false) ->> 'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 15 days after Not right now the asker still can''t ask';
  END IF;
END $$;

-- =====================================================================
-- L5. A request lapses after 14 days with no copy: the header shows
--     nothing of it, the second Yes is refused, and either may ask anew.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('10');
  v_b constant uuid := pg_temp.ready('11', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v_r uuid;
  v jsonb;
BEGIN
  v_m := pg_temp.match(v_a, v_b, 30);
  PERFORM pg_temp.we_met(v_m, v_a);
  v_r := (pg_temp.ask(v_a, '10', v_m, false) ->> 'request_id')::uuid;
  UPDATE public.dating_couple_link_requests SET created_at = now() - interval '15 days', expires_at = now() - interval '1 day'
   WHERE id = v_r;
  IF pg_temp.link(v_b, '11', v_m) IS DISTINCT FROM '{"state": "none"}'::jsonb
     OR pg_temp.link(v_a, '10', v_m) IS DISTINCT FROM '{"state": "none"}'::jsonb
     OR pg_temp.yes(v_b, '11', v_r, false) ->> 'reason' IS DISTINCT FROM 'request_unavailable'
     OR pg_temp.rels(v_a, v_b) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a lapsed request still shows or links: %', pg_temp.link(v_b, '11', v_m);
  END IF;
  v := pg_temp.ask(v_b, '11', v_m, false);
  IF (v ->> 'ok')::boolean IS NOT TRUE
     OR (SELECT state FROM public.dating_couple_link_requests WHERE id = v_r) IS DISTINCT FROM 'expired' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new request after a lapsed one';
  END IF;
END $$;

-- =====================================================================
-- L6. The second Yes (step 3): one transaction. An active relationship
--     through the invite exchange's rows (pending with a code, then active
--     with both, an acceptance row), the asker as user_a; both paused with
--     'relationship'; both paths Relationship; this conversation closed
--     couple_linked, every other open one of either person other_linked
--     (the other people's chats read ended, with nothing of the link);
--     their other requests cancelled; the first messages kept (both chose
--     it), masked (they hadn't both swapped), only what both could see;
--     the origin's match date; the asker's "You decided together." still
--     to come. A replay is the same couple.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('12');
  v_b constant uuid := pg_temp.ready('13', '{"identity": "man", "seeking": ["woman"]}');
  v_c constant uuid := pg_temp.ready('14', '{"identity": "man", "seeking": ["woman"]}');
  v_d constant uuid := pg_temp.ready('15');
  v_m uuid;
  v_ac uuid;
  v_bd uuid;
  v_r uuid;
  v_rc uuid;
  v jsonb;
  v_rel uuid;
  v_items jsonb;
BEGIN
  v_m := pg_temp.match(v_a, v_b, 20);
  v_ac := pg_temp.match(v_a, v_c, 5);
  v_bd := pg_temp.match(v_b, v_d, 5);
  PERFORM pg_temp.say(v_m, v_a, 1, 300);
  PERFORM pg_temp.say(v_m, v_b, 2, 200);
  -- A guided answer only A gave: B never saw it, so it is not kept.
  PERFORM pg_temp.say(v_m, v_a, 3, 150, 'guided_answer', 'good_saturday');
  PERFORM pg_temp.say(v_m, v_a, 4, 100);
  PERFORM pg_temp.we_met(v_m, v_b);
  PERFORM pg_temp.we_met(v_ac, v_a);
  v_rc := (pg_temp.ask(v_c, '14', v_ac, false) ->> 'request_id')::uuid;
  v_r := (pg_temp.ask(v_a, '12', v_m, true) ->> 'request_id')::uuid;
  v := pg_temp.yes(v_b, '13', v_r, true);
  v_rel := (v ->> 'relationship_id')::uuid;
  IF (v ->> 'ok')::boolean IS NOT TRUE OR v_rel IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the second Yes answered %', v;
  END IF;
  IF (SELECT r.status || ':' || (r.user_a = v_a) || ':' || (r.user_b = v_b) || ':' || (r.invite_code IS NULL)
             || ':' || (r.invite_accepted_at IS NOT NULL)
        FROM public.relationships AS r WHERE r.id = v_rel) IS DISTINCT FROM 'active:true:true:true:true'
     OR pg_temp.rels(v_a, v_b) <> 1
     OR NOT EXISTS (SELECT 1 FROM public.relationship_invite_acceptances AS x
                     WHERE x.relationship_id = v_rel AND x.accepted_by = v_b AND x.invite_code_hash ~ '^[0-9a-f]{64}$') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the relationship is not the invite exchange''s';
  END IF;
  IF (SELECT string_agg(e.state || '/' || coalesce(e.pause_reason, '-'), ',' ORDER BY e.user_id)
        FROM public.dating_enrollments AS e WHERE e.user_id IN (v_a, v_b)) IS DISTINCT FROM 'paused/relationship,paused/relationship'
     OR (SELECT string_agg(u.path, ',' ORDER BY u.id) FROM public.users AS u WHERE u.id IN (v_a, v_b))
        IS DISTINCT FROM 'relationship,relationship' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: both are not paused for the relationship on the Relationship path';
  END IF;
  IF (SELECT state || '/' || closed_reason || '/' || (evidence_until > now() + interval '29 days') FROM public.dating_matches WHERE id = v_m)
        IS DISTINCT FROM 'closed/couple_linked/true'
     OR (SELECT string_agg(state || '/' || closed_reason, ',' ORDER BY id) FROM public.dating_matches WHERE id IN (v_ac, v_bd))
        IS DISTINCT FROM 'closed/other_linked,closed/other_linked' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the conversations did not close as they should';
  END IF;
  IF (pg_temp.j(v_c, '14', format('SELECT public.get_dating_messages(%L)', v_ac)) -> 'chat' ->> 'state') IS DISTINCT FROM 'ended'
     OR pg_temp.link(v_c, '14', v_ac) IS DISTINCT FROM 'null'::jsonb
     OR pg_temp.link(v_d, '15', v_bd) IS DISTINCT FROM 'null'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.dating_chat_signals WHERE user_id = v_c AND match_id = v_ac)
     OR NOT EXISTS (SELECT 1 FROM public.dating_chat_signals WHERE user_id = v_d AND match_id = v_bd)
     OR (SELECT state FROM public.dating_couple_link_requests WHERE id = v_rc) IS DISTINCT FROM 'cancelled' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the other people''s chats read more than an end: %', pg_temp.link(v_c, '14', v_ac);
  END IF;
  SELECT items INTO v_items FROM public.couple_how_we_met WHERE relationship_id = v_rel;
  IF jsonb_array_length(v_items) <> 3
     OR (SELECT string_agg(x ->> 'text', ',' ORDER BY n) FROM jsonb_array_elements(v_items) WITH ORDINALITY AS t(x, n))
        IS DISTINCT FROM 'masked 1,masked 2,masked 4'
     OR (v_items -> 0 ->> 'by') IS DISTINCT FROM v_a::text OR (v_items -> 1 ->> 'by') IS DISTINCT FROM v_b::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: How we met is not the first messages as both saw them: %', v_items;
  END IF;
  IF (SELECT o.matched_at FROM public.dating_link_origins AS o WHERE o.relationship_id = v_rel)
       IS DISTINCT FROM (SELECT matched_at FROM public.dating_matches WHERE id = v_m)
     OR (SELECT state || '/' || (relationship_id = v_rel) FROM public.dating_couple_link_requests WHERE id = v_r) IS DISTINCT FROM 'linked/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the origin or the request is wrong';
  END IF;
  IF pg_temp.link(v_a, '12', v_m) IS DISTINCT FROM '{"state": "linked", "moment": true}'::jsonb
     OR pg_temp.link(v_b, '13', v_m) IS DISTINCT FROM '{"state": "linked", "moment": false}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: "You decided together." is not still to come for the asker alone: % / %',
      pg_temp.link(v_a, '12', v_m), pg_temp.link(v_b, '13', v_m);
  END IF;
  IF pg_temp.yes(v_b, '13', v_r, true) IS DISTINCT FROM jsonb_build_object('ok', true, 'relationship_id', v_rel)
     OR pg_temp.rels(v_a, v_b) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replay of the second Yes made something else';
  END IF;
END $$;

-- =====================================================================
-- L7. Keep our first messages: only when both chose it (either side's
--     yes alone keeps nothing); once both swapped, the plain text (A-3).
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('16');
  v_b constant uuid := pg_temp.ready('17', '{"identity": "man", "seeking": ["woman"]}');
  v_c constant uuid := pg_temp.ready('18');
  v_d constant uuid := pg_temp.ready('19', '{"identity": "man", "seeking": ["woman"]}');
  v_e constant uuid := pg_temp.ready('31');
  v_f constant uuid := pg_temp.ready('32', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v_m2 uuid;
  v_rel uuid;
BEGIN
  v_m := pg_temp.match(v_a, v_b);
  PERFORM pg_temp.say(v_m, v_a, 1, 60);
  PERFORM pg_temp.we_met(v_m, v_a);
  v_rel := (pg_temp.yes(v_b, '17', (pg_temp.ask(v_a, '16', v_m, true) ->> 'request_id')::uuid, false) ->> 'relationship_id')::uuid;
  IF v_rel IS NULL OR EXISTS (SELECT 1 FROM public.couple_how_we_met WHERE relationship_id = v_rel) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one side''s choice kept the first messages';
  END IF;
  -- The asker didn't choose it, the other side did: nothing kept either.
  v_m := pg_temp.match(v_e, v_f);
  PERFORM pg_temp.say(v_m, v_e, 1, 60);
  PERFORM pg_temp.we_met(v_m, v_e);
  v_rel := (pg_temp.yes(v_f, '32', (pg_temp.ask(v_e, '31', v_m, false) ->> 'request_id')::uuid, true) ->> 'relationship_id')::uuid;
  IF v_rel IS NULL OR EXISTS (SELECT 1 FROM public.couple_how_we_met WHERE relationship_id = v_rel) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the other side''s choice alone kept the first messages';
  END IF;
  v_m2 := pg_temp.match(v_c, v_d);
  PERFORM pg_temp.say(v_m2, v_d, 1, 60);
  PERFORM pg_temp.swap(v_m2);
  PERFORM pg_temp.we_met(v_m2, v_c);
  v_rel := (pg_temp.yes(v_c, '18', (pg_temp.ask(v_d, '19', v_m2, true) ->> 'request_id')::uuid, true) ->> 'relationship_id')::uuid;
  IF (SELECT items -> 0 ->> 'text' FROM public.couple_how_we_met WHERE relationship_id = v_rel) IS DISTINCT FROM 'plain 1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after both swapped How we met is not the plain text';
  END IF;
END $$;

-- =====================================================================
-- L8. Refusals that say nothing about the other person (Ruling R-W9-6,
--     carry 5): asking never depends on the other's life (an Attune
--     relationship, a same-gender trip that hides the chat on their
--     phone); the second Yes refuses (unavailable) while either is in an
--     open Attune relationship or under a hold, and changes nothing; a
--     blocked pair is closed; a chat the confirmer's own trip hides is
--     match_unavailable unless "Show it on this phone anyway".
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('20');
  v_b constant uuid := pg_temp.ready('21', '{"identity": "man", "seeking": ["woman"]}');
  v_x constant uuid := pg_temp.ready('22');
  v_g constant uuid := pg_temp.uk('23', '{"seeking": ["woman"]}');
  v_h constant uuid := pg_temp.uk('24', '{"seeking": ["woman"]}');
  v_p constant uuid := pg_temp.ready('25');
  v_q constant uuid := pg_temp.ready('26', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v_gh uuid;
  v_pq uuid;
  v_r uuid;
  v_rel uuid;
  v jsonb;
BEGIN
  -- B is in an Attune relationship with X (Dating paused, the chat kept).
  v_m := pg_temp.match(v_a, v_b);
  PERFORM pg_temp.we_met(v_m, v_a);
  INSERT INTO public.relationships (user_a, user_b, status, invite_accepted_at) VALUES (v_b, v_x, 'active', now())
  RETURNING id INTO v_rel;
  v := pg_temp.ask(v_a, '20', v_m, false);
  IF (v ->> 'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: asking told the asker about the other''s relationship: %', v;
  END IF;
  v_r := (v ->> 'request_id')::uuid;
  IF pg_temp.yes(v_b, '21', v_r, false) IS DISTINCT FROM '{"ok": false, "reason": "unavailable"}'::jsonb
     OR pg_temp.rels(v_a, v_a) <> 0
     OR (SELECT state FROM public.dating_couple_link_requests WHERE id = v_r) IS DISTINCT FROM 'open'
     OR (SELECT state FROM public.dating_matches WHERE id = v_m) IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the second Yes linked someone in another relationship';
  END IF;
  DELETE FROM public.relationships WHERE id = v_rel;
  INSERT INTO public.account_holds (user_id, kind, reason_ref) VALUES (v_a, 'age_review', 'w9-hold');
  IF pg_temp.yes(v_b, '21', v_r, false) IS DISTINCT FROM '{"ok": false, "reason": "unavailable"}'::jsonb
     OR pg_temp.rels(v_a, v_b) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the second Yes linked someone under a hold';
  END IF;
  DELETE FROM public.account_holds WHERE user_id = v_a;
  INSERT INTO public.dating_blocks (blocker_user_id, blocked_user_id, pair_key) VALUES (v_a, v_b, public.dating_pair_key(v_a, v_b));
  IF pg_temp.yes(v_b, '21', v_r, false) IS DISTINCT FROM '{"ok": false, "reason": "closed"}'::jsonb
     OR pg_temp.link(v_b, '21', v_m) IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a blocked pair could link';
  END IF;
  -- G and H, two UK women; H in Accra on a same-gender trip: the chat is
  -- hidden on H's phone. G's ask is answered as at home; H can't see or
  -- answer it there, unless "Show it on this phone anyway".
  INSERT INTO public.feature_flags (key, enabled) VALUES ('dating_traveller_detection', true)
  ON CONFLICT (key) DO UPDATE SET enabled = true;
  v_gh := pg_temp.match(v_g, v_h);
  PERFORM pg_temp.we_met(v_gh, v_g);
  PERFORM pg_temp.check(v_h, '24', 'GH');
  IF pg_temp.link(v_h, '24', v_gh) ->> 'read' IS DISTINCT FROM 'match_unavailable'
     OR pg_temp.page(v_h, '24', v_gh) ->> 'reason' IS DISTINCT FROM 'match_unavailable'
     OR pg_temp.ask(v_h, '24', v_gh, false) ->> 'reason' IS DISTINCT FROM 'match_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the fixture''s trip does not hide the chat on her phone';
  END IF;
  v := pg_temp.ask(v_g, '23', v_gh, false);
  IF (v ->> 'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the other''s trip changed the asker''s answer: %', v;
  END IF;
  v_r := (v ->> 'request_id')::uuid;
  IF pg_temp.yes(v_h, '24', v_r, false) ->> 'reason' IS DISTINCT FROM 'match_unavailable' OR pg_temp.rels(v_g, v_h) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a chat hidden on her phone could be answered there';
  END IF;
  IF pg_temp.page(v_h, '24', v_gh, true) -> 'link' IS DISTINCT FROM jsonb_build_object('state', 'asked_you', 'request_id', v_r) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Show it on this phone anyway does not show her the request';
  END IF;
  v := pg_temp.yes(v_h, '24', v_r, false, true);
  IF (v ->> 'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Show it on this phone anyway does not let her answer';
  END IF;
  -- A man and a woman: the trip flag changes nothing.
  v_pq := pg_temp.match(v_p, v_q);
  PERFORM pg_temp.we_met(v_pq, v_q);
  IF (pg_temp.yes(v_q, '26', (pg_temp.ask(v_p, '25', v_pq, false) ->> 'request_id')::uuid, false) ->> 'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a man-woman pair could not link';
  END IF;
END $$;

-- =====================================================================
-- L9. (Ruling R-W9-1, the controller's: one pairing path) A Dating link
--     and an invite make the same couple. Pair P (Dating: P asks, Q says
--     yes) and pair I (an invite: the pending row create-relationship-
--     invite inserts, then accept_relationship_invite_v2 as accept-invite
--     calls it). The same relationships row (every column's value, times
--     and ids only as set or not), the same acceptance row, the same rows
--     in every table that hangs off a relationship (timeline, About us,
--     everything; Dating's own link tables aside), the same invite
--     metrics, both paths Relationship. The link queues no push and no
--     in-app notice at all (Ruling R-W9-7; the invite's own push is
--     accept-invite's, never the database's); any push it did queue would
--     be neutral (carry 1; section A of dating_v2_device_contracts.sql
--     audits the walk).
-- =====================================================================
-- [p_rel]'s row as a shape: every column but its ids and members, a time
-- as set or not.
CREATE FUNCTION pg_temp.rel_shape(p_rel uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_object_agg(e.key, CASE WHEN jsonb_typeof(e.value) = 'null' THEN 'null'::jsonb
                                      WHEN e.key ~ '(_at|_on)$' THEN '"set"'::jsonb ELSE e.value END)
    FROM public.relationships AS r, jsonb_each(to_jsonb(r) - ARRAY['id', 'user_a', 'user_b']) AS e
   WHERE r.id = p_rel;
$$;
-- How many rows of each table that references relationships hang off
-- [p_rel] (Dating's own link tables aside).
CREATE FUNCTION pg_temp.effects(p_rel uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  c record;
  v_n bigint;
  v_out jsonb := '{}';
BEGIN
  FOR c IN
    SELECT k.conrelid::regclass::text AS t, a.attname AS col
      FROM pg_constraint AS k JOIN pg_attribute AS a ON a.attrelid = k.conrelid AND a.attnum = k.conkey[1]
     WHERE k.contype = 'f' AND k.confrelid = 'public.relationships'::regclass AND cardinality(k.conkey) = 1
  LOOP
    CONTINUE WHEN c.t IN ('dating_link_origins', 'couple_how_we_met', 'dating_couple_link_requests', 'dating_former_partner_exclusions');
    EXECUTE format('SELECT count(*) FROM %s WHERE %I = $1', c.t, c.col) INTO v_n USING p_rel;
    IF v_n > 0 THEN
      v_out := v_out || jsonb_build_object(c.t, v_n);
    END IF;
  END LOOP;
  RETURN v_out;
END $$;
CREATE FUNCTION pg_temp.queued(p_a uuid, p_b uuid) RETURNS bigint LANGUAGE sql AS $$
  SELECT (SELECT count(*) FROM public.scheduled_notifications AS s WHERE s.user_id IN (p_a, p_b))
       + (SELECT count(*) FROM public.in_app_notifications AS n WHERE n.user_id IN (p_a, p_b));
$$;
CREATE FUNCTION pg_temp.delta(a jsonb, b jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT coalesce(jsonb_object_agg(k, (b ->> k)::bigint - coalesce((a ->> k)::bigint, 0)), '{}'::jsonb)
    FROM jsonb_object_keys(b) AS k WHERE (b ->> k)::bigint IS DISTINCT FROM coalesce((a ->> k)::bigint, 0);
$$;
CREATE FUNCTION pg_temp.invite_metrics() RETURNS jsonb LANGUAGE sql AS $$
  SELECT coalesce(jsonb_object_agg(m.key, m.count), '{}'::jsonb) FROM public.metric_counters AS m
   WHERE m.day = (now() AT TIME ZONE 'utc')::date AND m.key LIKE 'invite_accepted%';
$$;
DO $$
DECLARE
  v_p constant uuid := pg_temp.ready('27');
  v_q constant uuid := pg_temp.ready('28', '{"identity": "man", "seeking": ["woman"]}');
  v_i constant uuid := pg_temp.id('29');
  v_k constant uuid := pg_temp.id('30');
  v_m uuid;
  v_link uuid;
  v_inv uuid;
  v_before jsonb;
  v_link_metrics jsonb;
  v_inv_metrics jsonb;
  v_queued bigint;
BEGIN
  -- I and K: two adults with no Dating, I on the Relationship path (the
  -- inviter has chosen it before inviting).
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (v_i, '155598229', now(), now() - interval '40 days'), (v_k, '155598230', now(), now() - interval '40 days');
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (v_i, '+155598229', 'Invite 29', 'relationship', now() - interval '40 days', now(), '2'),
         (v_k, '+155598230', 'Invite 30', NULL, now() - interval '40 days', now(), '2');
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (v_i, current_date - interval '30 years'), (v_k, current_date - interval '30 years');
  -- The Dating link.
  v_m := pg_temp.match(v_p, v_q);
  PERFORM pg_temp.we_met(v_m, v_p);
  v_queued := pg_temp.queued(v_p, v_q);
  v_before := pg_temp.invite_metrics();
  v_link := (pg_temp.yes(v_q, '28', (pg_temp.ask(v_p, '27', v_m, false) ->> 'request_id')::uuid, false) ->> 'relationship_id')::uuid;
  v_link_metrics := pg_temp.invite_metrics();
  IF v_link IS NULL OR pg_temp.queued(v_p, v_q) <> v_queued THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the link failed or queued a push or notice: % queued', pg_temp.queued(v_p, v_q) - v_queued;
  END IF;
  -- The invite, as the two edge functions write it.
  INSERT INTO public.relationships (user_a, status, invite_code, invite_expires_at)
  VALUES (v_i, 'pending', 'W9EQ29', now() + interval '7 days') RETURNING id INTO v_inv;
  IF (public.accept_relationship_invite_v2(v_k, 'W9EQ29') ->> 'relationship_id')::uuid IS DISTINCT FROM v_inv THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the invite fixture did not accept';
  END IF;
  v_inv_metrics := pg_temp.invite_metrics();
  IF pg_temp.rel_shape(v_link) IS DISTINCT FROM pg_temp.rel_shape(v_inv) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the link''s relationships row differs from an invite''s: % / %',
      pg_temp.rel_shape(v_link), pg_temp.rel_shape(v_inv);
  END IF;
  IF (SELECT count(*) FROM public.relationship_invite_acceptances WHERE relationship_id = v_link AND accepted_by = v_q
         AND invite_code_hash ~ '^[0-9a-f]{64}$') <> 1
     OR (SELECT count(*) FROM public.relationship_invite_acceptances WHERE relationship_id = v_inv AND accepted_by = v_k
            AND invite_code_hash = encode(extensions.digest('W9EQ29', 'sha256'), 'hex')) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the acceptance rows differ';
  END IF;
  IF pg_temp.effects(v_link) IS DISTINCT FROM pg_temp.effects(v_inv) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the link''s side effects differ from an invite''s: % / %',
      pg_temp.effects(v_link), pg_temp.effects(v_inv);
  END IF;
  IF pg_temp.delta(v_before, v_link_metrics) IS DISTINCT FROM pg_temp.delta(v_link_metrics, v_inv_metrics) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the invite metrics differ: % / %', pg_temp.delta(v_before, v_link_metrics),
      pg_temp.delta(v_link_metrics, v_inv_metrics);
  END IF;
  IF (SELECT string_agg(u.path, ',' ORDER BY u.id) FROM public.users AS u WHERE u.id IN (v_p, v_q, v_i, v_k))
       IS DISTINCT FROM 'relationship,relationship,relationship,relationship' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the paths differ';
  END IF;
END $$;

-- @@W9-T2@@
DO $$ BEGIN RAISE NOTICE 'dating_v2_link_contracts: all held'; END $$;
ROLLBACK;
````

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_link_contracts.sql 2>&1 | grep -E 'ERROR' | head -1
```

Expected: an error from the missing W9 objects: `…ERROR:  CONTRACT VIOLATED: dating_couple_link is not off` (no flag row yet).

- [ ] **Step 4: The new objects (the migration's head), the builder, the twin**

Create `.superpowers/sdd/2026-11-23-spec2-w9/mig_T1_head.sql` with exactly:

````sql
-- ---------------------------------------------------------------------
-- 1. The flag (off; supabase/sql/dev_enable_spec2_dating_flags.sql turns
--    it on in development) and its production gate (Spec 1's gate
--    trigger). With it off nothing W9 adds answers anything but
--    unavailable (and the reads answer nothing to show).
-- ---------------------------------------------------------------------
INSERT INTO private.flag_production_gates (flag_key, gate) VALUES
  ('dating_couple_link', 'Spec 2 W9 gate: counsel confirms the export scope (own data only, own sent messages, no counterpart data) and the How we met copy rule (both consent); the copy, DV and LGBTQ+ reviewers sign the Become a couple copy')
ON CONFLICT (flag_key) DO NOTHING;
INSERT INTO public.feature_flags (key, enabled) VALUES ('dating_couple_link', false)
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------
-- 2. The tables (§4.3). Every one: RLS on, nothing for any API role (the
--    self-revoke and the twin; S-5: no service role either). Reads and
--    writes go through the definer functions below.
-- ---------------------------------------------------------------------
-- A request to become a couple, one open per match (§3.9 steps 1-3). The
-- requester's own Yes is its confirmation; it lapses 14 days on, with no
-- copy. Deleted with its match (the 30-day evidence window's purge).
CREATE TABLE IF NOT EXISTS public.dating_couple_link_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id uuid NOT NULL REFERENCES public.dating_matches (id) ON DELETE CASCADE,
  requested_by_side text NOT NULL CHECK (requested_by_side IN ('low', 'high')),
  low_confirmed_at timestamptz,
  high_confirmed_at timestamptz,
  low_keep_messages boolean NOT NULL DEFAULT false,
  high_keep_messages boolean NOT NULL DEFAULT false,
  state text NOT NULL DEFAULT 'open' CHECK (state IN ('open', 'linked', 'declined', 'cancelled', 'expired')),
  relationship_id uuid REFERENCES public.relationships (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT now() + interval '14 days',
  decided_at timestamptz,
  CONSTRAINT dating_couple_link_requests_requester_confirmed CHECK (
    (requested_by_side = 'low' AND low_confirmed_at IS NOT NULL)
    OR (requested_by_side = 'high' AND high_confirmed_at IS NOT NULL)),
  -- §3.9: no relationship before both say yes.
  CONSTRAINT dating_couple_link_requests_linked_by_both CHECK (
    state <> 'linked' OR (low_confirmed_at IS NOT NULL AND high_confirmed_at IS NOT NULL AND relationship_id IS NOT NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS dating_couple_link_requests_one_open
  ON public.dating_couple_link_requests (match_id) WHERE state = 'open';
CREATE INDEX IF NOT EXISTS dating_couple_link_requests_match_idx
  ON public.dating_couple_link_requests (match_id, created_at DESC);
ALTER TABLE public.dating_couple_link_requests ENABLE ROW LEVEL SECURITY;

-- "How we met" (§3.9 step 3, A-3): the first 50 messages, copied only when
-- both chose it, masked unless both had swapped. Purged with the
-- relationship (§4.8). items: [{by, kind, question_id, text, at}], by the
-- sender's user id (the reads and the export say "me" or "partner").
CREATE TABLE IF NOT EXISTS public.couple_how_we_met (
  relationship_id uuid PRIMARY KEY REFERENCES public.relationships (id) ON DELETE CASCADE,
  items jsonb NOT NULL CHECK (jsonb_typeof(items) = 'array' AND jsonb_array_length(items) BETWEEN 1 AND 50),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.couple_how_we_met ENABLE ROW LEVEL SECURITY;

-- Where a relationship came from (S-6, I-12; Ruling R-W9-3): the day the
-- two matched, when they linked, and each side's two once-only moments:
-- "You decided together." seen, and the 30-day offer closed ("Keep for
-- now" never asks again). Purged with the relationship; a deleted account
-- leaves its side empty. Read only by members (get_dating_link_origin,
-- get_dating_post_link_offer).
CREATE TABLE IF NOT EXISTS public.dating_link_origins (
  relationship_id uuid PRIMARY KEY REFERENCES public.relationships (id) ON DELETE CASCADE,
  matched_at timestamptz NOT NULL,
  linked_at timestamptz NOT NULL DEFAULT now(),
  low_user_id uuid REFERENCES public.users (id) ON DELETE SET NULL,
  high_user_id uuid REFERENCES public.users (id) ON DELETE SET NULL,
  low_moment_seen_at timestamptz,
  high_moment_seen_at timestamptz,
  low_offer_closed_at timestamptz,
  high_offer_closed_at timestamptz
);
CREATE INDEX IF NOT EXISTS dating_link_origins_low_idx ON public.dating_link_origins (low_user_id);
CREATE INDEX IF NOT EXISTS dating_link_origins_high_idx ON public.dating_link_origins (high_user_id);
ALTER TABLE public.dating_link_origins ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------
-- 3. Helpers.
-- ---------------------------------------------------------------------
-- The couple link's switch: its own flag and the chat's (a link starts in
-- a chat).
CREATE OR REPLACE FUNCTION private.dating_link_on()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.dating_flag_enabled('dating_couple_link') IS TRUE AND private.dating_chat_on() IS TRUE;
$$;

-- Ruling R-W9-6: someone in an Attune relationship (active or paused) or
-- under an account hold can't ask. Asked of the caller alone (a request
-- never says anything about the other person's life); at the second Yes
-- the invite exchange's own checks ask it of both.
CREATE OR REPLACE FUNCTION private.dating_link_blocked(p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT p_user IS NULL
      OR EXISTS (SELECT 1 FROM public.relationships AS r
                  WHERE p_user IN (r.user_a, r.user_b) AND r.status IN ('active', 'paused'))
      OR EXISTS (SELECT 1 FROM public.account_holds AS h
                  WHERE h.user_id = p_user AND h.resolved_at IS NULL);
$$;

-- What the chat shows of the couple link, for [p_side] of [p_m] (§3.9;
-- Ruling R-W9-2): null (nothing; Become a couple not offered), or
-- {state}: 'none' (either has said We met: this side may ask), 'asked'
-- (this side asked; waiting), 'asked_you' (the other side asked: the card
-- and the sheet), 'not_ready' (the other side said Not right now to this
-- side's request, for 14 days), 'linked' (with 'moment': this side has
-- not seen "You decided together." yet). A lapsed request is nothing.
-- Read only after the reader's own trip check (S-5): it names no gender,
-- pool or trip.
CREATE OR REPLACE FUNCTION private.dating_link_json(p_m public.dating_matches, p_side text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_other constant uuid := CASE WHEN p_side = 'low' THEN p_m.user_high_id ELSE p_m.user_low_id END;
  v_r public.dating_couple_link_requests;
  v_o public.dating_link_origins;
BEGIN
  IF p_m.id IS NULL OR p_side NOT IN ('low', 'high') OR NOT private.dating_link_on() THEN
    RETURN NULL;
  END IF;
  IF p_m.state = 'closed' AND p_m.closed_reason = 'couple_linked' THEN
    SELECT o.* INTO v_o FROM public.dating_couple_link_requests AS r
      JOIN public.dating_link_origins AS o ON o.relationship_id = r.relationship_id
     WHERE r.match_id = p_m.id AND r.state = 'linked';
    IF v_o.relationship_id IS NULL THEN
      RETURN NULL;
    END IF;
    RETURN pg_catalog.jsonb_build_object('state', 'linked', 'moment',
      (CASE WHEN p_side = 'low' THEN v_o.low_moment_seen_at ELSE v_o.high_moment_seen_at END) IS NULL);
  END IF;
  IF p_m.state <> 'active' OR v_other IS NULL OR p_m.user_low_id IS NULL OR p_m.user_high_id IS NULL
     OR private.dating_pair_blocked(p_m.user_low_id, p_m.user_high_id) THEN
    RETURN NULL;
  END IF;
  SELECT * INTO v_r FROM public.dating_couple_link_requests AS r
   WHERE r.match_id = p_m.id AND r.state = 'open' AND r.expires_at > now();
  IF v_r.id IS NOT NULL THEN
    RETURN pg_catalog.jsonb_build_object('state', CASE WHEN v_r.requested_by_side = p_side THEN 'asked' ELSE 'asked_you' END,
                                         'request_id', v_r.id);
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_couple_link_requests AS r
              WHERE r.match_id = p_m.id AND r.state = 'declined' AND r.requested_by_side = p_side
                AND r.decided_at > now() - interval '14 days') THEN
    RETURN pg_catalog.jsonb_build_object('state', 'not_ready');
  END IF;
  IF p_m.low_we_met_at IS NULL AND p_m.high_we_met_at IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN pg_catalog.jsonb_build_object('state', 'none');
END;
$$;

-- ---------------------------------------------------------------------
-- 4. The couple link (§3.9, §4.4).
-- ---------------------------------------------------------------------
-- The link page's read (§3.14 /dating/link/:matchId; Ruling R-W9-2): the
-- other person's first name and the link's state, as the chat's header
-- shows them, behind the same trip check as the chat (S-5).
CREATE OR REPLACE FUNCTION public.get_dating_couple_link(p_match_id uuid, p_show_same_gender boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_m public.dating_matches;
  v_side text;
  v_sg boolean;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_match_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF NOT private.dating_link_on() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  SELECT * INTO v_m FROM public.dating_matches AS m
   WHERE m.id = p_match_id AND v_user IN (m.user_low_id, m.user_high_id)
     AND (m.state = 'active' OR m.evidence_until > now());
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable');
  END IF;
  v_sg := CASE WHEN coalesce(p_show_same_gender, false) THEN false ELSE private.dating_same_gender_hiding(v_user) END;
  IF private.dating_trip_hides(v_user, CASE WHEN v_m.user_low_id = v_user THEN v_m.user_high_id ELSE v_m.user_low_id END,
                               'match', v_sg) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable');
  END IF;
  v_side := CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END;
  RETURN pg_catalog.jsonb_build_object('ok', true,
    'display_name', (SELECT p.display_name FROM public.dating_profiles AS p
                      WHERE p.user_id = CASE WHEN v_side = 'low' THEN v_m.user_high_id ELSE v_m.user_low_id END),
    'link', private.dating_link_json(v_m, v_side));
END;
$$;

-- Step 1: "Ask {Name}". The requester's Yes, and whether they would keep
-- the first messages. A replay (or a second tap) answers the same;
-- refusals are fixed codes. Ruling R-W9-6: only the caller's own life is
-- asked (never the other person's); Ruling R-W9-5: after the other side's
-- "Not right now" this side may ask again only 14 days on (not_ready);
-- the other side may ask any time. Carry 5 (S-5): a match the caller's own
-- trip hides is match_unavailable, as every read; the other side's trip
-- changes nothing in the answer (they see the request once it shows on
-- their phone).
CREATE OR REPLACE FUNCTION public.request_dating_couple_link(p_key text, p_match_id uuid, p_keep_messages boolean,
                                                           p_show_same_gender boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_m public.dating_matches;
  v_side text;
  v_other uuid;
  v_r public.dating_couple_link_requests;
  v_sg boolean;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_match_id IS NULL OR p_keep_messages IS NULL OR NOT private.dating_key_ok(p_key) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF NOT private.dating_link_on() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(v_user); -- the shared lock order (setup first)
      SELECT * INTO v_m FROM public.dating_matches AS m
       WHERE m.id = p_match_id AND v_user IN (m.user_low_id, m.user_high_id) FOR NO KEY UPDATE;
      IF NOT FOUND THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable');
      END IF;
      v_side := CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END;
      v_other := CASE WHEN v_side = 'low' THEN v_m.user_high_id ELSE v_m.user_low_id END;
      v_sg := CASE WHEN coalesce(p_show_same_gender, false) THEN false ELSE private.dating_same_gender_hiding(v_user) END;
      IF private.dating_trip_hides(v_user, v_other, 'match', v_sg) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable');
      END IF;
      IF v_m.state <> 'active' OR v_m.user_low_id IS NULL OR v_m.user_high_id IS NULL
         OR private.dating_pair_blocked(v_m.user_low_id, v_m.user_high_id) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'closed');
      END IF;
      -- A lapsed request ends (with no copy) before anything is asked again.
      UPDATE public.dating_couple_link_requests AS r SET state = 'expired', decided_at = r.expires_at
       WHERE r.match_id = p_match_id AND r.state = 'open' AND r.expires_at <= now();
      SELECT * INTO v_r FROM public.dating_couple_link_requests AS r WHERE r.match_id = p_match_id AND r.state = 'open';
      IF v_r.id IS NOT NULL THEN
        IF v_r.requested_by_side = v_side THEN
          RETURN pg_catalog.jsonb_build_object('ok', true, 'request_id', v_r.id);
        END IF;
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'asked_you');
      END IF;
      IF v_m.low_we_met_at IS NULL AND v_m.high_we_met_at IS NULL THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_yet');
      END IF;
      IF EXISTS (SELECT 1 FROM public.dating_couple_link_requests AS r
                  WHERE r.match_id = p_match_id AND r.state = 'declined' AND r.requested_by_side = v_side
                    AND r.decided_at > now() - interval '14 days') THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_ready');
      END IF;
      IF private.dating_link_blocked(v_user) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'unavailable');
      END IF;
      INSERT INTO public.dating_couple_link_requests (match_id, requested_by_side, low_confirmed_at, high_confirmed_at,
                                                      low_keep_messages, high_keep_messages)
      VALUES (p_match_id, v_side, CASE WHEN v_side = 'low' THEN now() END, CASE WHEN v_side = 'high' THEN now() END,
              v_side = 'low' AND p_keep_messages, v_side = 'high' AND p_keep_messages)
      RETURNING * INTO v_r;
      -- Both chats read the request (the asker's other phone too).
      PERFORM private.dating_bump_chat(v_m.user_low_id, p_match_id);
      PERFORM private.dating_bump_chat(v_m.user_high_id, p_match_id);
      PERFORM private.bump_metric_internal('dating.couple_link.asked');
      RETURN pg_catalog.jsonb_build_object('ok', true, 'request_id', v_r.id);
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- "Not right now" (step 2): the other side's answer. Nothing is said to
-- anyone but the asker ("{Name} isn't ready yet.", from the header). An
-- exposure-reducing write: no flag, no trusted phone (W5-W7 lesson). A
-- replay answers ok.
CREATE OR REPLACE FUNCTION public.decline_dating_couple_link(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_r public.dating_couple_link_requests;
  v_m public.dating_matches;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_request_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(v_user);
      SELECT m.* INTO v_m FROM public.dating_couple_link_requests AS r
        JOIN public.dating_matches AS m ON m.id = r.match_id
       WHERE r.id = p_request_id AND v_user IN (m.user_low_id, m.user_high_id)
         FOR NO KEY UPDATE OF m;
      SELECT * INTO v_r FROM public.dating_couple_link_requests AS r WHERE r.id = p_request_id FOR UPDATE;
      IF v_m.id IS NULL OR v_r.requested_by_side = (CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'request_unavailable');
      END IF;
      IF v_r.state = 'declined' THEN
        RETURN pg_catalog.jsonb_build_object('ok', true);
      END IF;
      IF v_r.state <> 'open' OR v_r.expires_at <= now() THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'request_unavailable');
      END IF;
      UPDATE public.dating_couple_link_requests SET state = 'declined', decided_at = now() WHERE id = p_request_id;
      PERFORM private.dating_bump_chat(v_m.user_low_id, v_m.id);
      PERFORM private.dating_bump_chat(v_m.user_high_id, v_m.id);
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

-- The asker takes it back while it is open (the other side's card goes;
-- nothing is said). Exposure-reducing too. A replay answers ok; once linked
-- it is too late (linked).
CREATE OR REPLACE FUNCTION public.cancel_dating_couple_link(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_r public.dating_couple_link_requests;
  v_m public.dating_matches;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_request_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(v_user);
      SELECT m.* INTO v_m FROM public.dating_couple_link_requests AS r
        JOIN public.dating_matches AS m ON m.id = r.match_id
       WHERE r.id = p_request_id AND v_user IN (m.user_low_id, m.user_high_id)
         FOR NO KEY UPDATE OF m;
      SELECT * INTO v_r FROM public.dating_couple_link_requests AS r WHERE r.id = p_request_id FOR UPDATE;
      IF v_m.id IS NULL OR v_r.requested_by_side <> (CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'request_unavailable');
      END IF;
      IF v_r.state = 'cancelled' THEN
        RETURN pg_catalog.jsonb_build_object('ok', true);
      END IF;
      IF v_r.state = 'linked' THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'linked');
      END IF;
      IF v_r.state <> 'open' THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'request_unavailable');
      END IF;
      UPDATE public.dating_couple_link_requests SET state = 'cancelled', decided_at = now() WHERE id = p_request_id;
      PERFORM private.dating_bump_chat(v_m.user_low_id, v_m.id);
      PERFORM private.dating_bump_chat(v_m.user_high_id, v_m.id);
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

-- Step 3: the second Yes, in one transaction (§3.9, §8 W9; Rulings
-- R-W9-1, R-W9-4). Locks: both people's setup locks (every Dating
-- writer's first lock), the match and the request, then both users rows
-- lowest id first (the invite exchange's order; its own locks are then
-- already held). The relationship is made by the invite exchange itself
-- (Ruling R-W9-1): the pending row create-relationship-invite inserts,
-- then accept_relationship_invite_v2 unchanged (active with both members,
-- the relationship_invite_acceptances row), so every existing trigger
-- fires as it does for an invite: the
-- relationship guard pauses Dating for both (with 'relationship'), the
-- new chapter archives old ended ones. Then both paths become
-- Relationship, every other open conversation of either person closes as
-- 'other_linked' (the neutral "This conversation has ended."), this one as
-- 'couple_linked'; the first 50 messages are kept only when both chose it,
-- masked unless both swapped (A-3). No push (Ruling R-W9-7). A replay by
-- the confirmer answers the same relationship.
CREATE OR REPLACE FUNCTION public.confirm_dating_couple_link(p_key text, p_request_id uuid, p_keep_messages boolean,
                                                           p_show_same_gender boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_low uuid;
  v_high uuid;
  v_m public.dating_matches;
  v_r public.dating_couple_link_requests;
  v_side text;
  v_asker uuid;
  v_sg boolean;
  v_code text;
  v_rel uuid;
  v_acc jsonb;
  v_closed uuid[];
  v_both boolean;
  v_items jsonb;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_request_id IS NULL OR p_keep_messages IS NULL OR NOT private.dating_key_ok(p_key) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF NOT private.dating_link_on() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  -- The pair, read without a lock, so both setup locks come first.
  SELECT m.user_low_id, m.user_high_id INTO v_low, v_high
    FROM public.dating_couple_link_requests AS r JOIN public.dating_matches AS m ON m.id = r.match_id
   WHERE r.id = p_request_id AND v_user IN (m.user_low_id, m.user_high_id);
  IF v_low IS NULL OR v_high IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'request_unavailable');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup_pair(v_low, v_high);
      SELECT m.* INTO v_m FROM public.dating_couple_link_requests AS r
        JOIN public.dating_matches AS m ON m.id = r.match_id
       WHERE r.id = p_request_id AND v_user IN (m.user_low_id, m.user_high_id)
         FOR UPDATE OF m;
      SELECT * INTO v_r FROM public.dating_couple_link_requests AS r WHERE r.id = p_request_id FOR UPDATE;
      IF v_m.id IS NULL THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'request_unavailable');
      END IF;
      v_side := CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END;
      IF v_r.state = 'linked' AND v_r.requested_by_side <> v_side AND v_r.relationship_id IS NOT NULL THEN
        RETURN pg_catalog.jsonb_build_object('ok', true, 'relationship_id', v_r.relationship_id);
      END IF;
      v_sg := CASE WHEN coalesce(p_show_same_gender, false) THEN false ELSE private.dating_same_gender_hiding(v_user) END;
      IF private.dating_trip_hides(v_user, CASE WHEN v_side = 'low' THEN v_m.user_high_id ELSE v_m.user_low_id END,
                                   'match', v_sg) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable');
      END IF;
      IF v_r.state <> 'open' OR v_r.expires_at <= now() THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'request_unavailable');
      END IF;
      -- §3.9: the asker's own Yes is the first; it never makes the couple.
      IF v_r.requested_by_side = v_side THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'asked');
      END IF;
      IF v_m.state <> 'active' OR v_m.user_low_id IS NULL OR v_m.user_high_id IS NULL
         OR private.dating_pair_blocked(v_m.user_low_id, v_m.user_high_id) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'closed');
      END IF;
      -- Both users rows, lowest id first (the invite exchange's order).
      -- Either in an open Attune relationship or under a hold: the invite
      -- exchange's own checks refuse it below (unavailable).
      PERFORM 1 FROM public.users AS u WHERE u.id IN (v_m.user_low_id, v_m.user_high_id) ORDER BY u.id FOR UPDATE;
      v_asker := CASE WHEN v_r.requested_by_side = 'low' THEN v_m.user_low_id ELSE v_m.user_high_id END;
      -- The invite exchange itself (Ruling R-W9-1, the controller's: one
      -- pairing path). The pending row create-relationship-invite inserts
      -- (its columns; a 12-character code no one is shown, 7 days), then the
      -- invite exchange's own accept_relationship_invite_v2, unchanged: the
      -- pending -> active transition, the acceptance row, the acceptor's
      -- own and the inviter's other pending invites gone, the acceptor's
      -- path, About us's drafts and the invite metrics, with every trigger
      -- firing as for an invite.
      v_code := upper(left(replace(gen_random_uuid()::text, '-', ''), 12));
      INSERT INTO public.relationships (user_a, status, invite_code, invite_expires_at)
      VALUES (v_asker, 'pending', v_code, now() + interval '7 days')
      RETURNING id INTO v_rel;
      v_acc := public.accept_relationship_invite_v2(v_user, v_code);
      IF (v_acc ->> 'relationship_id')::uuid IS DISTINCT FROM v_rel OR (v_acc ->> 'status') IS DISTINCT FROM 'active' THEN
        RAISE EXCEPTION 'link:invite_mismatch';
      END IF;
      -- The asker's path too (the invite exchange sets only the acceptor's).
      PERFORM public.set_user_path_internal(v_asker, 'relationship');
      -- Every open conversation of either person closes; this one as linked.
      SELECT coalesce(pg_catalog.array_agg(x.id), '{}'::uuid[]) INTO v_closed
        FROM (SELECT m.id FROM public.dating_matches AS m
               WHERE m.state = 'active'
                 AND (m.user_low_id IN (v_m.user_low_id, v_m.user_high_id) OR m.user_high_id IN (v_m.user_low_id, v_m.user_high_id))
               ORDER BY m.id FOR NO KEY UPDATE OF m) AS x;
      UPDATE public.dating_matches AS m
         SET state = 'closed', closed_at = coalesce(m.closed_at, now()), evidence_until = now() + interval '30 days',
             closed_reason = CASE WHEN m.id = v_m.id THEN 'couple_linked' ELSE 'other_linked' END
       WHERE m.id = ANY (v_closed);
      UPDATE public.dating_couple_link_requests AS r SET state = 'cancelled', decided_at = now()
       WHERE r.match_id = ANY (v_closed) AND r.state = 'open' AND r.id <> p_request_id;
      PERFORM private.dating_bump_chat(x.u, m.id)
         FROM public.dating_matches AS m CROSS JOIN LATERAL (VALUES (m.user_low_id), (m.user_high_id)) AS x(u)
        WHERE m.id = ANY (v_closed);
      -- "How we met" (A-3): only when both chose it; masked unless both swapped.
      IF p_keep_messages AND (CASE WHEN v_r.requested_by_side = 'low' THEN v_r.low_keep_messages ELSE v_r.high_keep_messages END) THEN
        v_both := v_m.low_swap_at IS NOT NULL AND v_m.high_swap_at IS NOT NULL;
        SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                 'by', q.sender_user_id, 'kind', q.kind, 'question_id', q.question_id,
                 'text', CASE WHEN v_both THEN q.body ELSE q.body_masked END, 'at', q.k) ORDER BY q.k, q.id)
          INTO v_items
          FROM (SELECT d.*, private.dating_message_sort_at(d) AS k FROM public.dating_messages AS d
                 WHERE d.match_id = v_m.id AND d.kind IN ('text', 'guided_answer')
                   AND private.dating_message_visible(d, 'low') AND private.dating_message_visible(d, 'high')
                 ORDER BY private.dating_message_sort_at(d), d.id LIMIT 50) AS q;
        IF v_items IS NOT NULL THEN
          INSERT INTO public.couple_how_we_met (relationship_id, items) VALUES (v_rel, v_items);
        END IF;
      END IF;
      INSERT INTO public.dating_link_origins (relationship_id, matched_at, linked_at, low_user_id, high_user_id,
                                              low_moment_seen_at, high_moment_seen_at)
      VALUES (v_rel, v_m.matched_at, now(), v_m.user_low_id, v_m.user_high_id,
              CASE WHEN v_side = 'low' THEN now() END, CASE WHEN v_side = 'high' THEN now() END);
      UPDATE public.dating_couple_link_requests
         SET state = 'linked', relationship_id = v_rel, decided_at = now(),
             low_confirmed_at = coalesce(low_confirmed_at, CASE WHEN v_side = 'low' THEN now() END),
             high_confirmed_at = coalesce(high_confirmed_at, CASE WHEN v_side = 'high' THEN now() END),
             low_keep_messages = CASE WHEN v_side = 'low' THEN p_keep_messages ELSE low_keep_messages END,
             high_keep_messages = CASE WHEN v_side = 'high' THEN p_keep_messages ELSE high_keep_messages END
       WHERE id = p_request_id;
      PERFORM private.bump_metric_internal('dating.couple_link');
      RETURN pg_catalog.jsonb_build_object('ok', true, 'relationship_id', v_rel);
    EXCEPTION
      WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
        IF v_try = 3 THEN
          RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
        END IF;
      WHEN raise_exception THEN
        -- The invite exchange's refusals (a relationship opened meanwhile,
        -- a hold, an age), or a busy pause: the whole attempt is undone.
        IF SQLERRM IN ('relationship:already_open', 'account:hold') OR SQLERRM LIKE 'invite:%' THEN
          RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'unavailable');
        END IF;
        IF SQLERRM = 'dating:busy' THEN
          RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
        END IF;
        RAISE;
    END;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- @@W9-T2@@
````

Create `.superpowers/sdd/2026-11-23-spec2-w9/build_mig_W9.py` with exactly:

````python
#!/usr/bin/env python3
"""Spec 2 W9: builds supabase/migrations/20261123100000_dating_v2_couple_link.sql
from mig_T1_head.sql (and Task 2's mig_T2.sql at its marker, when it
exists), the functions below re-created from their LIVE bodies (saved to
before_w9/ before the migration is first applied) with only the lines
marked "-- Spec 2 W9" changed (Task 2's edits_T2.py adds its own), and the
self-revoke tail. Every anchor must occur exactly once."""
import pathlib, runpy

D = pathlib.Path('.superpowers/sdd/2026-11-23-spec2-w9')
B = D / 'before_w9'
T = 'Spec 2 W9'

EDITS = {
    # §3.9, Ruling R-W9-2: the chat's header carries the couple link, after
    # get_dating_messages' own trip check.
    'private.dating_chat_header(dating_matches,text)': [
        ("""               END); -- Spec 2 W6c
END;""", f"""               END, -- Spec 2 W6c; {T}
    'link', private.dating_link_json(p_m, p_side)); -- {T} (§3.9): the couple link, as this side sees it
END;"""),
    ],
}

HEADER = """-- Spec 2 W9 (§3.9, §4.3, §4.4, §4.9 W9, §7.1; S-4, S-6, A-3, I-12, I-13,
-- C-4; Rulings R-W9-1..R-W9-9): "Become a couple on Attune". The flag
-- dating_couple_link (off); link requests, the second Yes's one
-- transaction (the invite exchange's row transitions, both paused, both
-- paths Relationship, every other open conversation closed neutrally,
-- the first messages kept only when both chose it, masked unless both
-- swapped), the link origin (members only), the post-link offer, How we
-- met, the export's own-data Dating part (dating_export_for_job, bound
-- to a building job, at most three reads, each recorded) and
-- export_relationship re-created from its live body with the How we met
-- card. Grants in 20261123100010_dating_v2_couple_link_grants.sql. Ends by
-- revoking everything it creates from every API role (the W6 final
-- pattern: a push that stops between this file and its twin fails
-- closed).
"""

TABLES = ['public.dating_couple_link_requests', 'public.couple_how_we_met', 'public.dating_link_origins']
FUNCS = ['private.dating_link_on()', 'private.dating_link_blocked(uuid)',
         'private.dating_link_json(public.dating_matches, text)',
         'public.get_dating_couple_link(uuid, boolean)',
         'public.request_dating_couple_link(text, uuid, boolean, boolean)',
         'public.decline_dating_couple_link(uuid)', 'public.cancel_dating_couple_link(uuid)',
         'public.confirm_dating_couple_link(text, uuid, boolean, boolean)']

if (D / 'edits_T2.py').exists():
    t2 = runpy.run_path(str(D / 'edits_T2.py'))
    for sig, pairs in t2['EDITS'].items():
        EDITS.setdefault(sig, []).extend(pairs)
    TABLES += t2['TABLES']
    FUNCS += t2['FUNCS']


def edited(sig):
    text = (B / f'{sig}.sql').read_text().rstrip('\n')
    for old, new in EDITS[sig]:
        n = text.count(old)
        assert n == 1, f'{sig}: anchor occurs {n} times: {old[:70]!r}'
        text = text.replace(old, new)
    return text + ';\n'


TAIL = ('\n-- ---------------------------------------------------------------------\n'
        '-- Self-revoke (the W6 final pattern); the twin grants.\n'
        '-- ---------------------------------------------------------------------\n'
        'REVOKE ALL ON TABLE\n  ' + ',\n  '.join(TABLES) + '\n  FROM PUBLIC, anon, authenticated, service_role;\n'
        'REVOKE ALL ON FUNCTION\n  ' + ',\n  '.join(FUNCS) + '\n  FROM PUBLIC, anon, authenticated, service_role;\n')

head = (D / 'mig_T1_head.sql').read_text()
if (D / 'mig_T2.sql').exists():
    assert head.count('-- @@W9-T2@@\n') == 1
    head = head.replace('-- @@W9-T2@@\n', (D / 'mig_T2.sql').read_text())
body = (HEADER + 'BEGIN;\nSET LOCAL lock_timeout = \'5s\';\n\n' + head
        + '\n-- ---------------------------------------------------------------------\n'
        + '-- Re-created from their live bodies; only the lines marked\n'
        + '-- "-- Spec 2 W9" change.\n'
        + '-- ---------------------------------------------------------------------\n'
        + '\n'.join(edited(s) for s in EDITS) + TAIL + '\nCOMMIT;\n')
out = pathlib.Path('supabase/migrations/20261123100000_dating_v2_couple_link.sql')
out.write_text(body)
print(f'{out}: {len(EDITS)} re-created function(s), {body.count(chr(10))} lines')
````

Create `supabase/migrations/20261123100010_dating_v2_couple_link_grants.sql` with exactly:

````sql
-- Spec 2 W9: grants for 20261123100000_dating_v2_couple_link.sql. The new
-- tables are nobody's (S-5: the service role's neither); the couple link's
-- reads and writes are the app's; the helpers are the database's own.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON TABLE public.dating_couple_link_requests FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.couple_how_we_met FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.dating_link_origins FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_link_on() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_link_blocked(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_link_json(public.dating_matches, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_dating_couple_link(uuid, boolean) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_couple_link(uuid, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.request_dating_couple_link(text, uuid, boolean, boolean) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.request_dating_couple_link(text, uuid, boolean, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.decline_dating_couple_link(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.decline_dating_couple_link(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.cancel_dating_couple_link(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.cancel_dating_couple_link(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.confirm_dating_couple_link(text, uuid, boolean, boolean) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.confirm_dating_couple_link(text, uuid, boolean, boolean) TO authenticated;
-- @@W9-T2-GRANTS@@
COMMIT;
````

- [ ] **Step 5: Build, apply twice, check the marked lines**

```bash
D=.superpowers/sdd/2026-11-23-spec2-w9
python3 -I $D/build_mig_W9.py
for i in 1 2; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261123100000_dating_v2_couple_link.sql > /dev/null 2>&1; echo "migration exit=$?"
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261123100010_dating_v2_couple_link_grants.sql > /dev/null 2>&1; echo "twin exit=$?"
done
python3 -I $D/marked_diff.py $D/before_w9 attune_spec3a 'Spec 2 W9' | grep -v ' 0 added'; echo "marked_diff exit=${PIPESTATUS[0]}"
```

Expected: `supabase/migrations/20261123100000_dating_v2_couple_link.sql: 1 re-created function(s), 677 lines`; four `exit=0`; `private.dating_chat_header(dating_matches,text): 2 added line(s), 1 removed OK`; `marked_diff exit=0`.

- [ ] **Step 6: The canary and W8's catalogue take the couple link; the grants harness its twin**

Create `.superpowers/sdd/2026-11-23-spec2-w9/edit_tests_T1.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W9 Task 1: the canary takes W9a's first tables and functions (the
# tables nobody's, S-5; the couple link the app's; the helpers the
# database's own), above its Checks line, behind a marker Task 2 uses.
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-23-spec2-w9/anchor.py')['edit']

edit('supabase/tests/dating_rls_canary.sql', [
    ("""UPDATE allowed_fn SET sig = 'get_dating_messages(uuid,timestamp with time zone,integer,boolean)' WHERE sig = 'get_dating_messages(uuid,timestamp with time zone,integer)';

-- ---------------------------------------------------------------------
-- Checks (every batch adds its rows above this line).
""", """UPDATE allowed_fn SET sig = 'get_dating_messages(uuid,timestamp with time zone,integer,boolean)' WHERE sig = 'get_dating_messages(uuid,timestamp with time zone,integer)';
-- Spec 2 W9 Task 1: the couple link. Its tables are nobody's (S-5: the
-- service role's neither); its reads and writes the app's; its helpers
-- the database's own.
INSERT INTO allowed_rel (name, authenticated, service_dml) VALUES
  ('dating_couple_link_requests', '', ''),
  ('couple_how_we_met', '', ''),
  ('dating_link_origins', '', '');
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('private.dating_link_on()', '', ''),
  ('private.dating_link_blocked(uuid)', '', ''),
  ('private.dating_link_json(dating_matches,text)', '', ''),
  ('get_dating_couple_link(uuid,boolean)', 'authenticated', ''),
  ('request_dating_couple_link(text,uuid,boolean,boolean)', 'authenticated', ''),
  ('decline_dating_couple_link(uuid)', 'authenticated', ''),
  ('cancel_dating_couple_link(uuid)', 'authenticated', ''),
  ('confirm_dating_couple_link(text,uuid,boolean,boolean)', 'authenticated', '');
-- @@W9-T2-CANARY@@

-- ---------------------------------------------------------------------
-- Checks (every batch adds its rows above this line).
"""),
], 'T1 canary')

# W8's catalogue (B12) meets the couple link: asking and the second Yes read
# the same-gender rule (the trip check, carry 5) and write, only past it;
# before it, only their row locks (the match; and the request).
edit('supabase/tests/dating_v2_device_contracts.sql', [
    ("""  IF v_writers IS DISTINCT FROM ARRAY['public.act_on_dating_introduction', 'public.get_dating_home', 'public.get_dating_messages',
                                      'public.get_my_dating_introductions', 'public.get_my_dating_matches',
                                      'public.get_my_dating_today'] THEN""",
     """  IF v_writers IS DISTINCT FROM ARRAY['public.act_on_dating_introduction', 'public.confirm_dating_couple_link', -- Spec 2 W9
                                      'public.get_dating_home', 'public.get_dating_messages',
                                      'public.get_my_dating_introductions', 'public.get_my_dating_matches',
                                      'public.get_my_dating_today', 'public.request_dating_couple_link'] THEN -- Spec 2 W9"""),
    ("""  IF v_probe IS DISTINCT FROM ARRAY['public.act_on_dating_introduction', 'public.get_dating_home', 'public.get_dating_messages',
                                    'public.get_my_dating_introductions', 'public.get_my_dating_matches',
                                    'public.get_my_dating_today', 'public.zz_w8_read'] THEN""",
     """  IF v_probe IS DISTINCT FROM ARRAY['public.act_on_dating_introduction', 'public.confirm_dating_couple_link', -- Spec 2 W9
                                    'public.get_dating_home', 'public.get_dating_messages',
                                    'public.get_my_dating_introductions', 'public.get_my_dating_matches',
                                    'public.get_my_dating_today', 'public.request_dating_couple_link', -- Spec 2 W9
                                    'public.zz_w8_read'] THEN"""),
    ("""    RAISE EXCEPTION 'CONTRACT VIOLATED: acting writes before the hiding';
  END IF;
""", """    RAISE EXCEPTION 'CONTRACT VIOLATED: acting writes before the hiding';
  END IF;
  -- Spec 2 W9 (carry 5): asking and the second Yes write only past the
  -- hiding; before it, only their row locks (the match; and the request).
  FOREACH v_sig IN ARRAY ARRAY['public.request_dating_couple_link(text,uuid,boolean,boolean):1',
                               'public.confirm_dating_couple_link(text,uuid,boolean,boolean):2'] LOOP
    v_src := (SELECT p.prosrc FROM pg_proc AS p WHERE p.oid = split_part(v_sig, ':', 1)::regprocedure);
    IF regexp_count(left(v_src, position('dating_trip_hides' IN v_src)), '(\\minsert\\M|\\mupdate\\M|\\mdelete\\M|claim_dating_idempotency|bump_metric|dating_field_encrypt|dating_open_signal_case|nextval|set_config)', 1, 'i')
         <> split_part(v_sig, ':', 2)::int THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % writes before the hiding', split_part(v_sig, ':', 1);
    END IF;
  END LOOP;
"""),
], 'T1 device catalogue')

# The service role's grants test lists the tables no API role holds (S-5):
# the couple link's (read and written only through definer functions).
edit('supabase/tests/service_role_grants_test.sql', [
    ("""                          'dating_escalations', 'law_enforcement_requests')
    AND NOT has_table_privilege('service_role', c.oid, 'SELECT');""",
     """                          'dating_escalations', 'law_enforcement_requests',
                          -- Spec 2 W9: the couple link's tables (S-5).
                          'dating_link_origins', 'couple_how_we_met')
    AND NOT has_table_privilege('service_role', c.oid, 'SELECT');"""),
    ("""                          'dating_escalations', 'law_enforcement_requests')
    -- Spec 2 W1b (batch-4 fix round 1, C-1)""",
     """                          'dating_escalations', 'law_enforcement_requests',
                          -- Spec 2 W9: the couple link's tables (S-5).
                          'dating_link_origins', 'couple_how_we_met')
    -- Spec 2 W1b (batch-4 fix round 1, C-1)"""),
], 'T1 service role grants')
````

```bash
D=.superpowers/sdd/2026-11-23-spec2-w9
python3 -I $D/edit_tests_T1.py
python3 -I $D/grants_line.py supabase/migrations/20261122100010_dating_v2_traveller_grants.sql 'Spec 2 W9: the couple link (twin of 20261123100000)' supabase/migrations/20261123100010_dating_v2_couple_link_grants.sql
for f in dating_v2_link_contracts dating_rls_canary dating_v2_device_contracts service_role_grants_test dating_v2_chat_contracts dating_v2_eligibility_contracts dating_v2_client_reads_contracts; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$f.sql > /dev/null 2>&1 && echo "$f exit=0" || echo "$f FAILED"
done
```

Expected: `…dating_rls_canary.sql: 1 edit(s) (T1 canary)`, `…dating_v2_device_contracts.sql: 3 edit(s) (T1 device catalogue)`, `…service_role_grants_test.sql: 2 edit(s) (T1 service role grants)`; `local_pg_grants.sql: one \i block added`; seven lines ending `exit=0` (the build found W8's B12 catalogue pins every function that reads the same-gender rule and writes: asking and the second Yes join it, and write only past their trip check; the first replay's W9a gate found `service_role_grants_test.sql` lists every table the service role may not read: the couple link's join it, S-5).

- [ ] **Step 7: The mutants**

Create `.superpowers/sdd/2026-11-23-spec2-w9/mut_T1.py` with exactly:

````python
# Spec 2 W9 Task 1 mutants (mutate.py on 20261123100000_dating_v2_couple_link.sql,
# the twin applied after each). Each must make dating_v2_link_contracts.sql
# fail with a CONTRACT VIOLATED line.
MUTS = {
    # Spec mutant 21: the couple is made on the first Yes.
    'm21_link_on_first_yes': ("""      IF v_r.requested_by_side = v_side THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'asked');
      END IF;
""", ""),
    'flag_ignored': ("  SELECT public.dating_flag_enabled('dating_couple_link') IS TRUE AND private.dating_chat_on() IS TRUE;\n",
                     "  SELECT private.dating_chat_on() IS TRUE;\n"),
    'ask_before_we_met': ("""      IF v_m.low_we_met_at IS NULL AND v_m.high_we_met_at IS NULL THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_yet');
      END IF;
""", ""),
    'offer_before_we_met': ("""  IF p_m.low_we_met_at IS NULL AND p_m.high_we_met_at IS NULL THEN
    RETURN NULL;
  END IF;
""", ""),
    'not_ready_gone': ("                    AND r.decided_at > now() - interval '14 days') THEN\n        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_ready');",
                       "                    AND r.decided_at > now() + interval '1 second') THEN\n        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_ready');"),
    'not_ready_12_days': ("                    AND r.decided_at > now() - interval '14 days') THEN\n        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_ready');",
                          "                    AND r.decided_at > now() - interval '12 days') THEN\n        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_ready');"),
    'ask_reveals_other': ("      IF private.dating_link_blocked(v_user) THEN\n",
                          "      IF private.dating_link_blocked(v_user) OR private.dating_link_blocked(v_other) THEN\n"),
    'lapsed_still_shows': ("   WHERE r.match_id = p_m.id AND r.state = 'open' AND r.expires_at > now();\n",
                           "   WHERE r.match_id = p_m.id AND r.state = 'open';\n"),
    'confirm_after_lapse': ("""      IF v_r.state <> 'open' OR v_r.expires_at <= now() THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'request_unavailable');
      END IF;
      -- §3.9""", """      IF v_r.state <> 'open' THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'request_unavailable');
      END IF;
      -- §3.9"""),
    'decline_by_asker': ("      IF v_m.id IS NULL OR v_r.requested_by_side = (CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END) THEN\n",
                         "      IF v_m.id IS NULL THEN\n"),
    'cancel_by_other': ("      IF v_m.id IS NULL OR v_r.requested_by_side <> (CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END) THEN\n",
                        "      IF v_m.id IS NULL THEN\n"),
    'confirm_ignores_block': ("""      IF v_m.state <> 'active' OR v_m.user_low_id IS NULL OR v_m.user_high_id IS NULL
         OR private.dating_pair_blocked(v_m.user_low_id, v_m.user_high_id) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'closed');
      END IF;
      -- Both users rows""", """      IF v_m.state <> 'active' OR v_m.user_low_id IS NULL OR v_m.user_high_id IS NULL THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'closed');
      END IF;
      -- Both users rows"""),
    'confirm_ignores_trip': ("""      IF private.dating_trip_hides(v_user, CASE WHEN v_side = 'low' THEN v_m.user_high_id ELSE v_m.user_low_id END,
                                   'match', v_sg) THEN""", """      IF false THEN"""),
    'asker_path_kept': ("      PERFORM public.set_user_path_internal(v_asker, 'relationship');\n", ""),
    'own_acceptance': ("      v_acc := public.accept_relationship_invite_v2(v_user, v_code);\n",
                       "      UPDATE public.relationships SET user_b = v_user, status = 'active', invite_code = NULL, invite_accepted_at = now() WHERE id = v_rel;\n"
                       "      v_acc := pg_catalog.jsonb_build_object('relationship_id', v_rel, 'status', 'active');\n"),
    'others_stay_open': ("               WHERE m.state = 'active'\n                 AND (m.user_low_id IN",
                         "               WHERE m.state = 'active' AND m.id = v_m.id\n                 AND (m.user_low_id IN"),
    'others_not_neutral': ("             closed_reason = CASE WHEN m.id = v_m.id THEN 'couple_linked' ELSE 'other_linked' END\n",
                           "             closed_reason = 'couple_linked'\n"),
    'keep_one_side': ("      IF p_keep_messages AND (CASE WHEN v_r.requested_by_side = 'low' THEN v_r.low_keep_messages ELSE v_r.high_keep_messages END) THEN\n",
                      "      IF p_keep_messages THEN\n"),
    'm_unmasked': ("        v_both := v_m.low_swap_at IS NOT NULL AND v_m.high_swap_at IS NOT NULL;\n", "        v_both := true;\n"),
    'keeps_unseen': ("                   AND private.dating_message_visible(d, 'low') AND private.dating_message_visible(d, 'high')\n",
                     "\n"),
    'moment_both_seen': ("              CASE WHEN v_side = 'low' THEN now() END, CASE WHEN v_side = 'high' THEN now() END);\n",
                         "              now(), now());\n"),
    'header_no_link': ("    'link', private.dating_link_json(p_m, p_side)); -- Spec 2 W9 (§3.9): the couple link, as this side sees it\n",
                       "    'link', NULL); -- Spec 2 W9 (§3.9): the couple link, as this side sees it\n"),
}
````

```bash
D=.superpowers/sdd/2026-11-23-spec2-w9
W9_DB=attune_spec3a python3 -I $D/mutate.py supabase/migrations/20261123100000_dating_v2_couple_link.sql supabase/tests/dating_v2_link_contracts.sql $D/mut_T1.py $D/mut supabase/migrations/20261123100010_dating_v2_couple_link_grants.sql | tee $D/mut_T1.txt | grep -c 'CONTRACT VIOLATED'
```

Expected: `22` (every line `CONTRACT VIOLATED: …`; `m21_link_on_first_yes`: `the asker's own confirmation made the couple`).

- [ ] **Step 8: Record the tree (do not commit).**

### Task 2: Migration `dating_v2_couple_link` (part 2): the origin, How we met, the offer, the export binding, `export_relationship`, the flag in `get_dating_home`; contract E; the export contract (§3.9 steps 4–6, §4.2, §4.3, §4.4, §4.8, §4.10, §7.1; S-4, S-6, I-12, I-13; mutants 22, 23, 28; R-W9-3, R-W9-8, R-W9-9, R-W9-16)

**Files:**
- Create: `$D/{mig_T2.sql, edits_T2.py, twin_T2.sql, contract_T2.sql, edit_tests_T2.py, mut_T2.py}`
- Modify: the migration (rebuilt), the twin (`-- @@W9-T2-GRANTS@@`), `supabase/tests/dating_v2_link_contracts.sql` (E at `-- @@W9-T2@@`), `supabase/tests/dating_rls_canary.sql` (`-- @@W9-T2-CANARY@@`), `supabase/tests/data_export_contracts.sql` (`:229-233` and section 1b), `supabase/tests/service_role_grants_test.sql`, and three catalogue pins: `dating_v2_home_contracts.sql` (H9, reflections), `dating_v2_identity_contracts.sql` (never-introduce), `dating_v2_setup_contracts.sql` (photos)
- Test: `dating_v2_link_contracts.sql` E1–E6; `data_export_contracts.sql` 1b

**Interfaces:**
- Consumes: Task 1's tables and markers; `before_w9/public.export_relationship(uuid,uuid).sql`.
- Produces: `get_dating_link_origin`, `get_how_we_met`, `get_dating_post_link_offer`, `dismiss_dating_post_link_offer`, `dating_export_for_job`, `dating_export_reads`, `export_relationship.how_we_met` (Tasks 4–6 read them).

- [ ] **Step 1: The new section, the re-created export, the twin's lines**

Create `.superpowers/sdd/2026-11-23-spec2-w9/mig_T2.sql` with exactly:

````sql
-- ---------------------------------------------------------------------
-- 5. Where the couple came from, and what follows (§3.9 steps 4-6; S-6,
--    I-12, C-4; Rulings R-W9-3, R-W9-8).
-- ---------------------------------------------------------------------
-- The match date for About us's chip (I-12), to the relationship's two
-- members only, while it is open (active or paused). Anyone else, a
-- relationship with no Dating origin, an ended one, or the flag off: the
-- same opaque answer (S-6). The validity check never branches on
-- membership first (Fable H2).
CREATE OR REPLACE FUNCTION public.get_dating_link_origin(p_relationship_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_at timestamptz;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  SELECT o.matched_at INTO v_at
    FROM public.dating_link_origins AS o JOIN public.relationships AS r ON r.id = o.relationship_id
   WHERE p_relationship_id IS NOT NULL AND o.relationship_id = p_relationship_id
     AND v_user IN (r.user_a, r.user_b) AND r.status IN ('active', 'paused')
     AND public.dating_flag_enabled('dating_couple_link') IS TRUE;
  IF v_at IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'link_origin_unavailable');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'matched_at', v_at);
END;
$$;

-- The "How we met" card (§3.9 step 3, §8 W9: a row on About us opens it),
-- to the two members only, while the relationship is open: each message
-- as both saw it, "mine" for the reader's own. Anyone else, no card, or
-- the flag off: the same opaque answer.
CREATE OR REPLACE FUNCTION public.get_how_we_met(p_relationship_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_items jsonb;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  SELECT h.items INTO v_items
    FROM public.couple_how_we_met AS h JOIN public.relationships AS r ON r.id = h.relationship_id
   WHERE p_relationship_id IS NOT NULL AND h.relationship_id = p_relationship_id
     AND v_user IN (r.user_a, r.user_b) AND r.status IN ('active', 'paused')
     AND public.dating_flag_enabled('dating_couple_link') IS TRUE;
  IF v_items IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'how_we_met_unavailable');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'items',
    (SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
              'mine', (x.v ->> 'by') = v_user::text, 'kind', x.v ->> 'kind', 'question_id', x.v -> 'question_id',
              'text', x.v ->> 'text', 'at', x.v -> 'at') ORDER BY x.n)
       FROM pg_catalog.jsonb_array_elements(v_items) WITH ORDINALITY AS x(v, n)));
END;
$$;

-- What the Relationship home's link_offer card shows for the caller (C-4;
-- Ruling R-W9-3): 'linked' ("You decided together.", once, for whoever did
-- not see it at the second Yes), then from 30 days after linking 'delete'
-- ("Delete your Dating profile and preferences?", until either answer,
-- and only while there is Dating data to delete), else null. Only the
-- caller's open relationship's origin counts.
CREATE OR REPLACE FUNCTION public.get_dating_post_link_offer()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_o public.dating_link_origins;
  v_low boolean;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_flag_enabled('dating_couple_link') IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'offer', NULL);
  END IF;
  SELECT o.* INTO v_o
    FROM public.dating_link_origins AS o JOIN public.relationships AS r ON r.id = o.relationship_id
   WHERE v_user IN (o.low_user_id, o.high_user_id) AND v_user IN (r.user_a, r.user_b) AND r.status IN ('active', 'paused')
   ORDER BY o.linked_at DESC LIMIT 1;
  IF v_o.relationship_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'offer', NULL);
  END IF;
  v_low := v_o.low_user_id = v_user;
  IF (CASE WHEN v_low THEN v_o.low_moment_seen_at ELSE v_o.high_moment_seen_at END) IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'offer', 'linked');
  END IF;
  IF now() >= v_o.linked_at + interval '30 days'
     AND (CASE WHEN v_low THEN v_o.low_offer_closed_at ELSE v_o.high_offer_closed_at END) IS NULL
     AND private.dating_has_data(v_user) THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'offer', 'delete');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'offer', NULL);
END;
$$;

-- The card's answers (Ruling R-W9-3): 'linked' once "You decided
-- together." has shown; 'delete' for "Keep for now" (never asked again).
-- "Delete my Dating data" opens Leave Dating (§3.8), whose exit removes
-- the data the offer needs. A replay answers ok.
CREATE OR REPLACE FUNCTION public.dismiss_dating_post_link_offer(p_offer text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_rel uuid;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_offer IS NULL OR p_offer NOT IN ('linked', 'delete') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  SELECT o.relationship_id INTO v_rel
    FROM public.dating_link_origins AS o JOIN public.relationships AS r ON r.id = o.relationship_id
   WHERE v_user IN (o.low_user_id, o.high_user_id) AND v_user IN (r.user_a, r.user_b) AND r.status IN ('active', 'paused')
   ORDER BY o.linked_at DESC LIMIT 1;
  IF v_rel IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'offer_unavailable');
  END IF;
  UPDATE public.dating_link_origins AS o
     SET low_moment_seen_at = CASE WHEN p_offer = 'linked' AND o.low_user_id = v_user
                                   THEN coalesce(o.low_moment_seen_at, now()) ELSE o.low_moment_seen_at END,
         high_moment_seen_at = CASE WHEN p_offer = 'linked' AND o.high_user_id = v_user
                                    THEN coalesce(o.high_moment_seen_at, now()) ELSE o.high_moment_seen_at END,
         low_offer_closed_at = CASE WHEN p_offer = 'delete' AND o.low_user_id = v_user
                                    THEN coalesce(o.low_offer_closed_at, now()) ELSE o.low_offer_closed_at END,
         high_offer_closed_at = CASE WHEN p_offer = 'delete' AND o.high_user_id = v_user
                                     THEN coalesce(o.high_offer_closed_at, now()) ELSE o.high_offer_closed_at END
   WHERE o.relationship_id = v_rel;
  RETURN pg_catalog.jsonb_build_object('ok', true);
END;
$$;

-- ---------------------------------------------------------------------
-- 6. The export's own-data Dating part (§4.2, §4.3, S-4, I-13; Ruling
--    R-W9-9).
-- ---------------------------------------------------------------------
-- Each call of dating_export_for_job, by job: no content (S-4).
CREATE TABLE IF NOT EXISTS public.dating_export_reads (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  job_id uuid NOT NULL REFERENCES public.data_export_jobs (id) ON DELETE CASCADE,
  read_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS dating_export_reads_job_idx ON public.dating_export_reads (job_id);
ALTER TABLE public.dating_export_reads ENABLE ROW LEVEL SECURITY;

-- The one service-role path to decrypted fields (S-4): no user id; the job
-- must be building (its user is the one who asked, through
-- request_my_export); at most three calls a job (the worker's three tries
-- of a part), each recorded. The person's own data only: what they set up
-- and chose (decrypted), their own sent messages (as they wrote them), and
-- nothing about anyone they matched (no name, no age, no message of
-- theirs, no reason a conversation ended). No id of any kind. NULL when
-- there is no Dating data (build-data-exports then writes no dating.json).
CREATE OR REPLACE FUNCTION public.dating_export_for_job(p_job_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_job public.data_export_jobs;
  v_user uuid;
  v_s public.dating_profile_sensitive;
  v_identity jsonb;
  v_seeking jsonb;
  v_faith jsonb;
  v_marital jsonb;
BEGIN
  SELECT * INTO v_job FROM public.data_export_jobs AS j WHERE j.id = p_job_id FOR UPDATE;
  IF v_job.id IS NULL OR v_job.status IS DISTINCT FROM 'building' THEN
    RAISE EXCEPTION 'export:not_building';
  END IF;
  IF (SELECT count(*) FROM public.dating_export_reads AS x WHERE x.job_id = p_job_id) >= 3 THEN
    RAISE EXCEPTION 'export:read_limit';
  END IF;
  INSERT INTO public.dating_export_reads (job_id) VALUES (p_job_id);
  v_user := v_job.user_id;
  IF NOT (private.dating_has_data(v_user)
          OR EXISTS (SELECT 1 FROM public.dating_consent_events AS c WHERE c.user_id = v_user)
          OR EXISTS (SELECT 1 FROM public.dating_messages AS d WHERE d.sender_user_id = v_user)
          OR EXISTS (SELECT 1 FROM public.dating_enrollments AS e WHERE e.user_id = v_user)) THEN
    RETURN NULL;
  END IF;
  SELECT * INTO v_s FROM public.dating_profile_sensitive AS s WHERE s.user_id = v_user;
  BEGIN
    v_identity := private.dating_field_decrypt(v_s.identity_enc);
    v_seeking := private.dating_field_decrypt(v_s.seeking_enc);
    v_faith := private.dating_field_decrypt(v_s.faith_enc);
    v_marital := private.dating_field_decrypt(v_s.marital_enc);
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
      RAISE EXCEPTION 'export:unavailable';
    END IF;
    RAISE;
  END;
  RETURN pg_catalog.jsonb_build_object(
    'format', 'attune-dating-export', 'version', 1, 'generated_at', now(),
    'about', 'Your own Dating data: what you set up and chose, and the messages you sent. Nothing anyone else wrote or chose is in it.',
    'enrolment', (SELECT pg_catalog.jsonb_build_object('state', e.state, 'terms_version', e.terms_version,
                    'opted_in_at', e.opted_in_at, 'activated_at', e.activated_at, 'paused_at', e.paused_at,
                    'pause_reason', e.pause_reason, 'exited_at', e.exited_at)
                    FROM public.dating_enrollments AS e WHERE e.user_id = v_user),
    'profile', (SELECT pg_catalog.jsonb_build_object('display_name', p.display_name, 'country', p.country_code,
                  'region', p.region_code, 'side', p.side_code, 'intention', p.intention,
                  'marriage_timeline', p.marriage_timeline, 'timeline_visible', p.timeline_visible,
                  'attested_not_married_at', p.not_married_attested_at, 'children_have', p.children_have,
                  'children_want', p.children_want, 'family_involvement', p.family_involvement,
                  'gender_visible', p.gender_visible, 'faith_visible', p.faith_visible, 'marital_visible', p.marital_visible,
                  'photos_after_mutual', p.photos_after_mutual, 'state', p.profile_state, 'verified_at', p.verified_at)
                  FROM public.dating_profiles AS p WHERE p.user_id = v_user),
    'about_you', pg_catalog.jsonb_build_object('identity', v_identity, 'seeking', v_seeking -> 'seeking',
                                               'faith', v_faith, 'marital', v_marital ->> 'marital'),
    'preferences', (SELECT pg_catalog.jsonb_build_object('min_age', d.min_age, 'max_age', d.max_age,
                      'region_scope', d.region_scope, 'open_abroad', to_jsonb(d.open_abroad),
                      'want_must_match', d.want_must_match, 'exclude_parents', d.exclude_parents)
                      FROM public.dating_preferences AS d WHERE d.user_id = v_user),
    'settings', (SELECT pg_catalog.jsonb_build_object('drop_time', to_char(t.drop_time, 'HH24:MI'), 'data_saver', t.data_saver,
                   'digest_push', t.digest_push, 'chat_push', t.chat_push, 'show_when_away', t.show_when_away)
                   FROM public.dating_settings AS t WHERE t.user_id = v_user),
    'prompts', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('prompt', q.prompt_id, 'answer', q.answer,
                           'state', q.moderation_state) ORDER BY q.position)
                           FROM public.dating_prompts AS q WHERE q.user_id = v_user), '[]'::jsonb),
    'photos', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('position', f.position, 'caption', f.caption,
                          'state', f.moderation_state, 'added_at', f.created_at) ORDER BY f.position)
                          FROM public.dating_profile_photos AS f WHERE f.user_id = v_user), '[]'::jsonb),
    'consents', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('purpose', c.purpose, 'action', c.action,
                            'policy_version', c.policy_version, 'at', c.occurred_at) ORDER BY c.occurred_at, c.created_at)
                            FROM public.dating_consent_events AS c WHERE c.user_id = v_user), '[]'::jsonb),
    'verification', (SELECT pg_catalog.jsonb_build_object('age_method', a.age_method, 'age_result', a.age_result,
                       'age_decided_at', a.age_decided_at, 'identity_method', a.identity_method,
                       'identity_result', a.identity_result, 'identity_decided_at', a.identity_decided_at,
                       'revoked_at', a.revoked_at)
                       FROM public.dating_age_verifications AS a WHERE a.user_id = v_user),
    'trusted_phones', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('verified_at', t.verified_at,
                                  'last_seen_at', t.last_seen_at) ORDER BY t.verified_at)
                                  FROM public.dating_trusted_devices AS t WHERE t.user_id = v_user), '[]'::jsonb),
    'never_introduce', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('label', n.label, 'added_at', n.created_at)
                                   ORDER BY n.created_at)
                                   FROM public.dating_never_introduce AS n WHERE n.owner_user_id = v_user), '[]'::jsonb),
    'gentle_wait', (SELECT pg_catalog.jsonb_build_object('answers', g.answers, 'saved_at', g.saved_at)
                      FROM public.dating_gentle_wait_reflections AS g WHERE g.user_id = v_user),
    'date_reflections', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('response', r.response, 'note', r.note,
                                    'at', r.created_at) ORDER BY r.created_at)
                                    FROM public.dating_date_reflections AS r WHERE r.author_user_id = v_user), '[]'::jsonb),
    'conversations', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                                 'name', 'conversation-' || c.n, 'matched_at', c.matched_at,
                                 'state', CASE WHEN c.state = 'active' THEN 'open' ELSE 'ended' END, 'ended_at', c.closed_at,
                                 'my_messages', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                                     'at', d.created_at, 'kind', d.kind, 'question', d.question_id, 'text', d.body)
                                     ORDER BY d.created_at, d.id)
                                   FROM public.dating_messages AS d
                                  WHERE d.match_id = c.id AND d.sender_user_id = v_user), '[]'::jsonb)) ORDER BY c.n)
                                 FROM (SELECT m.id, m.matched_at, m.state, m.closed_at,
                                              row_number() OVER (ORDER BY m.matched_at, m.id) AS n
                                         FROM public.dating_matches AS m
                                        WHERE v_user IN (m.user_low_id, m.user_high_id)) AS c), '[]'::jsonb),
    'reports_i_made', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('category', r.category,
                                  'details', r.details, 'at', r.created_at) ORDER BY r.created_at)
                                  FROM public.dating_reports AS r WHERE r.reporter_user_id = v_user), '[]'::jsonb),
    'restrictions', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('type', x.restriction_type,
                                'category', x.category, 'starts_at', x.starts_at, 'ends_at', x.ends_at,
                                'lifted_at', x.lifted_at) ORDER BY x.starts_at)
                                FROM public.dating_account_restrictions AS x WHERE x.user_id = v_user), '[]'::jsonb),
    'appeals', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('text', a.text, 'state', a.state,
                           'submitted_at', a.submitted_at, 'decided_at', a.decided_at) ORDER BY a.submitted_at)
                           FROM public.dating_appeals AS a WHERE a.user_id = v_user), '[]'::jsonb));
END;
$$;
````

Create `.superpowers/sdd/2026-11-23-spec2-w9/edits_T2.py` with exactly:

````python
# Spec 2 W9 Task 2: build_mig_W9.py adds these edits, tables and functions
# to its own. export_relationship re-created from its live body with the
# How we met card (I-13, R9): 'me' or 'partner', never an id, as About us.
T = 'Spec 2 W9'
EDITS = {
    'public.export_relationship(uuid,uuid)': [
        ("""    'family', coalesce((""", f"""    -- {T} (§3.9, I-13): the How we met card, each message as both saw it.
    'how_we_met', (SELECT jsonb_agg(jsonb_build_object( -- {T}
        'from', public.export_who(p_user_id, (x.v->>'by')::uuid), 'kind', x.v->>'kind', -- {T}
        'text', x.v->>'text', 'at', x.v->'at') ORDER BY x.n) -- {T}
      FROM public.couple_how_we_met h, jsonb_array_elements(h.items) WITH ORDINALITY AS x(v, n) -- {T}
      WHERE h.relationship_id = p_relationship_id), -- {T}
    'family', coalesce(("""),
    ],
}
# The controller's ruling (R-W9-16): Dating's flags are server-only (RLS
# hides dating_% rows), so the app learns dating_couple_link from the
# Dating read it already makes once per process for everyone
# (documentationFlagsProvider's get_dating_home): every answer carries
# couple_link: true while the flag is on, nothing while it is off.
EDITS['public.get_dating_home()'] = [
    ("""           || CASE WHEN private.dating_appeal_accepted(v_user) THEN jsonb_build_object('appeal_accepted', true) ELSE '{}'::jsonb END; -- Spec 2 W7a""",
     f"""           || CASE WHEN private.dating_appeal_accepted(v_user) THEN jsonb_build_object('appeal_accepted', true) ELSE '{{}}'::jsonb END -- Spec 2 W7a; {T}
           || CASE WHEN public.dating_flag_enabled('dating_couple_link') IS TRUE THEN jsonb_build_object('couple_link', true) ELSE '{{}}'::jsonb END; -- {T} (R-W9-16)"""),
]
TABLES = ['public.dating_export_reads']
FUNCS = ['public.get_dating_link_origin(uuid)', 'public.get_how_we_met(uuid)',
         'public.get_dating_post_link_offer()', 'public.dismiss_dating_post_link_offer(text)',
         'public.dating_export_for_job(uuid)']
````

Create `.superpowers/sdd/2026-11-23-spec2-w9/twin_T2.sql` with exactly:

````sql
-- Spec 2 W9 Task 2: the origin, How we met and the offer are the app's;
-- the export's Dating part is the service role's alone (S-4).
REVOKE ALL ON TABLE public.dating_export_reads FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_dating_link_origin(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_link_origin(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.get_how_we_met(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_how_we_met(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.get_dating_post_link_offer() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_post_link_offer() TO authenticated;
REVOKE ALL ON FUNCTION public.dismiss_dating_post_link_offer(text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.dismiss_dating_post_link_offer(text) TO authenticated;
REVOKE ALL ON FUNCTION public.dating_export_for_job(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dating_export_for_job(uuid) TO service_role;
````

- [ ] **Step 2: Build, apply twice, check the marked lines**

```bash
D=.superpowers/sdd/2026-11-23-spec2-w9
python3 -I $D/splice.py supabase/migrations/20261123100010_dating_v2_couple_link_grants.sql '-- @@W9-T2-GRANTS@@' $D/twin_T2.sql
python3 -I $D/build_mig_W9.py
for i in 1 2; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261123100000_dating_v2_couple_link.sql > /dev/null 2>&1; echo "migration exit=$?"
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261123100010_dating_v2_couple_link_grants.sql > /dev/null 2>&1; echo "twin exit=$?"
done
python3 -I $D/marked_diff.py $D/before_w9 attune_spec3a 'Spec 2 W9'; echo "marked_diff exit=$?"
```

Expected: `…grants.sql: twin_T2.sql spliced at -- @@W9-T2-GRANTS@@`; `…: 3 re-created function(s), 1372 lines` (the plan's text; `1387 lines` once Task 2's fix round 1 is in: C-1's revoke, the export binding's order); four `exit=0`; `private.dating_chat_header(dating_matches,text): 2 added line(s), 1 removed OK`, `public.export_relationship(uuid,uuid): 6 added line(s), 0 removed OK`, `public.get_dating_home(): 2 added line(s), 1 removed OK`, `marked_diff exit=0`.

- [ ] **Step 3: Contract E, the canary's rows, the export contract**

Create `.superpowers/sdd/2026-11-23-spec2-w9/contract_T2.sql` with exactly:

````sql
-- =====================================================================
-- Setup for E (Task 2): a couple linked through Dating, the reads of
-- what follows, and the export's call as the worker makes it.
-- =====================================================================
-- [p] and [q] matched, both said We met; [p] asks, [q] says yes, both
-- keep the first messages; the relationship's id.
CREATE FUNCTION pg_temp.couple(p uuid, p_n text, q uuid, q_n text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_m uuid := pg_temp.match(p, q);
  v_rel uuid;
BEGIN
  PERFORM pg_temp.say(v_m, p, 1, 300);
  PERFORM pg_temp.say(v_m, q, 2, 200);
  PERFORM pg_temp.we_met(v_m, p);
  v_rel := (pg_temp.yes(q, q_n, (pg_temp.ask(p, p_n, v_m, true) ->> 'request_id')::uuid, true) ->> 'relationship_id')::uuid;
  IF v_rel IS NULL THEN
    RAISE EXCEPTION 'E setup: the couple did not link';
  END IF;
  RETURN v_rel;
END $$;
CREATE FUNCTION pg_temp.origin(p uuid, p_rel uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, NULL, format('SELECT public.get_dating_link_origin(%L)', p_rel));
$$;
CREATE FUNCTION pg_temp.how(p uuid, p_rel uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, NULL, format('SELECT public.get_how_we_met(%L)', p_rel));
$$;
CREATE FUNCTION pg_temp.offer(p uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, NULL, 'SELECT public.get_dating_post_link_offer()');
$$;
CREATE FUNCTION pg_temp.dismiss(p uuid, p_what text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, NULL, format('SELECT public.dismiss_dating_post_link_offer(%L)', p_what));
$$;
-- The worker's call (build-data-exports, the service role's), or its error.
CREATE FUNCTION pg_temp.export(p_job uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.dating_export_for_job(p_job);
  RESET ROLE;
  RETURN coalesce(v, 'null'::jsonb);
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  RETURN jsonb_build_object('raised', SQLERRM);
END $$;
CREATE FUNCTION pg_temp.job(p uuid, p_status text) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.data_export_jobs (user_id, status, claimed_at) VALUES (p, p_status, now()) RETURNING id;
$$;
-- The opaque answers (S-6): one text each, whatever the reason.
CREATE FUNCTION pg_temp.no_origin() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT '{"ok": false, "reason": "link_origin_unavailable"}'::jsonb;
$$;
CREATE FUNCTION pg_temp.no_card() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT '{"ok": false, "reason": "how_we_met_unavailable"}'::jsonb;
$$;

-- =====================================================================
-- E1. What follows the link is the app's; the export's Dating part is the
--     service role's alone, with no user id (S-4): no
--     dating_export_for_user exists; the read log is nobody's.
-- =====================================================================
DO $$
DECLARE
  v_t text;
BEGIN
  FOREACH v_t IN ARRAY ARRAY['public.get_dating_link_origin(uuid)', 'public.get_how_we_met(uuid)',
                             'public.get_dating_post_link_offer()', 'public.dismiss_dating_post_link_offer(text)'] LOOP
    IF NOT has_function_privilege('authenticated', v_t, 'EXECUTE') OR has_function_privilege('anon', v_t, 'EXECUTE')
       OR has_function_privilege('service_role', v_t, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % is not the app''s alone', v_t;
    END IF;
  END LOOP;
  IF has_function_privilege('authenticated', 'public.dating_export_for_job(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.dating_export_for_job(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.dating_export_for_job(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_export_for_job is not the service role''s alone';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'dating_export_for_user') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a dating_export_for_user exists (S-4)';
  END IF;
  IF has_table_privilege('service_role', 'public.dating_export_reads', 'SELECT')
     OR has_table_privilege('authenticated', 'public.dating_export_reads', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the export read log is readable by an API role';
  END IF;
END $$;

-- =====================================================================
-- E2. The link origin (S-6, mutant 28): the match date, to the two
--     members only, while the relationship is open; a stranger, a
--     relationship that never came from Dating, an ended one, no id, the
--     flag off: the same answer.
-- =====================================================================
DO $$
DECLARE
  v_x constant uuid := pg_temp.ready('50');
  v_y constant uuid := pg_temp.ready('51', '{"identity": "man", "seeking": ["woman"]}');
  v_z constant uuid := pg_temp.ready('52');
  v_w constant uuid := pg_temp.ready('53');
  v_v constant uuid := pg_temp.ready('54', '{"identity": "man", "seeking": ["woman"]}');
  v_rel uuid;
  v_plain uuid;
  v_at timestamptz;
BEGIN
  v_rel := pg_temp.couple(v_x, '50', v_y, '51');
  SELECT m.matched_at INTO v_at FROM public.dating_matches AS m JOIN public.dating_couple_link_requests AS r ON r.match_id = m.id
   WHERE r.relationship_id = v_rel;
  IF pg_temp.origin(v_x, v_rel) IS DISTINCT FROM jsonb_build_object('ok', true, 'matched_at', v_at)
     OR pg_temp.origin(v_y, v_rel) IS DISTINCT FROM jsonb_build_object('ok', true, 'matched_at', v_at) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the members don''t read the match date: %', pg_temp.origin(v_x, v_rel);
  END IF;
  INSERT INTO public.relationships (user_a, user_b, status, invite_accepted_at) VALUES (v_w, v_v, 'active', now())
  RETURNING id INTO v_plain;
  IF pg_temp.origin(v_z, v_rel) IS DISTINCT FROM pg_temp.no_origin()
     OR pg_temp.origin(v_w, v_plain) IS DISTINCT FROM pg_temp.no_origin()
     OR pg_temp.origin(v_x, NULL) IS DISTINCT FROM pg_temp.no_origin()
     OR pg_temp.origin(v_x, v_plain) IS DISTINCT FROM pg_temp.no_origin() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the origin answers a stranger or a relationship with no Dating origin differently';
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_couple_link';
  IF pg_temp.origin(v_x, v_rel) IS DISTINCT FROM pg_temp.no_origin() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the origin answers with the flag off';
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_couple_link';
  UPDATE public.relationships SET status = 'ended', ended_at = now() WHERE id = v_rel;
  IF pg_temp.origin(v_x, v_rel) IS DISTINCT FROM pg_temp.no_origin() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the origin answers for an ended relationship';
  END IF;
END $$;

-- =====================================================================
-- E3. How we met: to the two members only, each message as both saw it,
--     "mine" for the reader's own; a stranger or a couple with no card:
--     the same answer. export_relationship carries the card ('me' or
--     'partner', never an id; I-13), and none for a couple without one.
-- =====================================================================
DO $$
DECLARE
  v_x constant uuid := pg_temp.ready('55');
  v_y constant uuid := pg_temp.ready('56', '{"identity": "man", "seeking": ["woman"]}');
  v_z constant uuid := pg_temp.ready('57');
  v_rel uuid;
  v jsonb;
  e jsonb;
BEGIN
  v_rel := pg_temp.couple(v_x, '55', v_y, '56');
  v := pg_temp.how(v_x, v_rel);
  IF v -> 'items' IS DISTINCT FROM (
       SELECT jsonb_agg(jsonb_build_object('mine', x ->> 'by' = v_x::text, 'kind', 'text', 'question_id', NULL,
                                           'text', x ->> 'text', 'at', x -> 'at') ORDER BY n)
         FROM public.couple_how_we_met AS h, jsonb_array_elements(h.items) WITH ORDINALITY AS t(x, n)
        WHERE h.relationship_id = v_rel)
     OR jsonb_array_length(v -> 'items') <> 2 OR (v -> 'items' -> 0 ->> 'mine')::boolean IS NOT TRUE
     OR (pg_temp.how(v_y, v_rel) -> 'items' -> 0 ->> 'mine')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: How we met reads wrong: % / %', v, pg_temp.how(v_y, v_rel);
  END IF;
  IF pg_temp.how(v_z, v_rel) IS DISTINCT FROM pg_temp.no_card() OR pg_temp.how(v_x, NULL) IS DISTINCT FROM pg_temp.no_card() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: How we met answers a stranger';
  END IF;
  e := public.export_relationship(v_x, v_rel);
  IF e -> 'how_we_met' IS DISTINCT FROM jsonb_build_array(
         jsonb_build_object('from', 'me', 'kind', 'text', 'text', 'masked 1', 'at', v -> 'items' -> 0 -> 'at'),
         jsonb_build_object('from', 'partner', 'kind', 'text', 'text', 'masked 2', 'at', v -> 'items' -> 1 -> 'at'))
     OR (e -> 'how_we_met')::text ~ '[0-9a-f]{8}-[0-9a-f]{4}-' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: export_relationship lacks the How we met card: %', e -> 'how_we_met';
  END IF;
  DELETE FROM public.couple_how_we_met WHERE relationship_id = v_rel;
  IF pg_temp.how(v_x, v_rel) IS DISTINCT FROM pg_temp.no_card()
     OR NOT (public.export_relationship(v_x, v_rel) ? 'how_we_met')
     OR public.export_relationship(v_x, v_rel) -> 'how_we_met' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a couple without a card reads one';
  END IF;
END $$;

-- =====================================================================
-- E4. The Relationship home's card (C-4, Ruling R-W9-3): the asker reads
--     'linked' until they have seen "You decided together." (the
--     confirmer saw it at the second Yes); from 30 days after linking both
--     read 'delete' while they have Dating data, until either answer;
--     "Keep for now" never asks again; leaving Dating ends it. Answers
--     are fixed codes; a replay is ok.
-- =====================================================================
DO $$
DECLARE
  v_x constant uuid := pg_temp.ready('58');
  v_y constant uuid := pg_temp.ready('59', '{"identity": "man", "seeking": ["woman"]}');
  v_z constant uuid := pg_temp.ready('60');
  v_rel uuid;
BEGIN
  v_rel := pg_temp.couple(v_x, '58', v_y, '59');
  IF pg_temp.offer(v_x) IS DISTINCT FROM '{"ok": true, "offer": "linked"}'::jsonb
     OR pg_temp.offer(v_y) IS DISTINCT FROM '{"ok": true, "offer": null}'::jsonb
     OR pg_temp.offer(v_z) IS DISTINCT FROM '{"ok": true, "offer": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the card after linking: % / %', pg_temp.offer(v_x), pg_temp.offer(v_y);
  END IF;
  IF pg_temp.dismiss(v_x, 'linked') IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.dismiss(v_x, 'linked') IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.offer(v_x) IS DISTINCT FROM '{"ok": true, "offer": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: "You decided together." shows again';
  END IF;
  IF pg_temp.dismiss(v_x, 'other') IS DISTINCT FROM '{"ok": false, "reason": "invalid"}'::jsonb
     OR pg_temp.dismiss(v_z, 'delete') IS DISTINCT FROM '{"ok": false, "reason": "offer_unavailable"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a bad dismissal is not a fixed refusal';
  END IF;
  UPDATE public.dating_link_origins SET linked_at = now() - interval '29 days' WHERE relationship_id = v_rel;
  IF pg_temp.offer(v_x) IS DISTINCT FROM '{"ok": true, "offer": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 30-day offer came early';
  END IF;
  UPDATE public.dating_link_origins SET linked_at = now() - interval '31 days' WHERE relationship_id = v_rel;
  IF pg_temp.offer(v_x) IS DISTINCT FROM '{"ok": true, "offer": "delete"}'::jsonb
     OR pg_temp.offer(v_y) IS DISTINCT FROM '{"ok": true, "offer": "delete"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 30-day offer did not come: % / %', pg_temp.offer(v_x), pg_temp.offer(v_y);
  END IF;
  IF pg_temp.dismiss(v_y, 'delete') IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.offer(v_y) IS DISTINCT FROM '{"ok": true, "offer": null}'::jsonb
     OR pg_temp.offer(v_x) IS DISTINCT FROM '{"ok": true, "offer": "delete"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Keep for now is not this person''s alone, for good';
  END IF;
  PERFORM private.dating_exit_internal(v_x, false);
  IF pg_temp.offer(v_x) IS DISTINCT FROM '{"ok": true, "offer": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the offer stays after leaving Dating: %', pg_temp.offer(v_x);
  END IF;
END $$;

-- =====================================================================
-- E5. The export binding (S-4, mutants 22, 23): for A's building job,
--     A's own Dating data (decrypted) and A's own sent messages, none of
--     B's though they matched, no name or age of B's, no id; a queued,
--     ready, failed or unknown job: export:not_building; a fourth call
--     for one job: export:read_limit; every call logged, nothing else;
--     no Dating data: nothing (null).
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('61');
  v_b constant uuid := pg_temp.ready('62', '{"identity": "man", "seeking": ["woman"]}');
  v_n constant uuid := pg_temp.id('63');
  v_m uuid;
  v_job uuid;
  v jsonb;
  v_s text;
BEGIN
  v_m := pg_temp.match(v_a, v_b);
  PERFORM pg_temp.say(v_m, v_a, 1, 300);
  PERFORM pg_temp.say(v_m, v_b, 2, 200);
  PERFORM pg_temp.say(v_m, v_a, 3, 100);
  v_job := pg_temp.job(v_a, 'building');
  v := pg_temp.export(v_job);
  IF v ->> 'format' IS DISTINCT FROM 'attune-dating-export'
     OR v -> 'about_you' -> 'identity' ->> 'identity' IS DISTINCT FROM 'woman'
     OR v -> 'about_you' -> 'seeking' IS DISTINCT FROM '["man"]'::jsonb
     OR v -> 'profile' ->> 'display_name' IS DISTINCT FROM 'Link 61'
     OR jsonb_array_length(v -> 'conversations') <> 1
     OR (SELECT string_agg(x ->> 'text', ',' ORDER BY n) FROM jsonb_array_elements(v -> 'conversations' -> 0 -> 'my_messages')
                                                          WITH ORDINALITY AS t(x, n)) IS DISTINCT FROM 'plain 1,plain 3' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the export is not A''s own data: %', v;
  END IF;
  v_s := v::text;
  IF v_s LIKE '%plain 2%' OR v_s LIKE '%masked%' OR v_s LIKE '%Link 62%'
     OR v_s ~ '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the export holds B''s words or name, or an id';
  END IF;
  PERFORM pg_temp.export(v_job);
  PERFORM pg_temp.export(v_job);
  IF pg_temp.export(v_job) IS DISTINCT FROM '{"raised": "export:read_limit"}'::jsonb
     OR (SELECT count(*) FROM public.dating_export_reads WHERE job_id = v_job) <> 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a fourth read of one job was allowed, or the reads were not logged';
  END IF;
  IF pg_temp.export(pg_temp.job(v_a, 'queued')) IS DISTINCT FROM '{"raised": "export:not_building"}'::jsonb
     OR pg_temp.export(pg_temp.job(v_a, 'ready')) IS DISTINCT FROM '{"raised": "export:not_building"}'::jsonb
     OR pg_temp.export(pg_temp.job(v_a, 'failed')) IS DISTINCT FROM '{"raised": "export:not_building"}'::jsonb
     OR pg_temp.export(gen_random_uuid()) IS DISTINCT FROM '{"raised": "export:not_building"}'::jsonb
     OR pg_temp.export(NULL) IS DISTINCT FROM '{"raised": "export:not_building"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a job that isn''t building was read';
  END IF;
  INSERT INTO auth.users (id, phone, phone_confirmed_at) VALUES (v_n, '155598263', now());
  INSERT INTO public.users (id, phone, display_name) VALUES (v_n, '+155598263', 'No dating');
  IF pg_temp.export(pg_temp.job(v_n, 'building')) IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: someone with no Dating data got a dating part';
  END IF;
END $$;

-- =====================================================================
-- E6. (Ruling R-W9-16) The app learns the flag from the Dating read it
--     already makes (get_dating_home): every answer, to anyone (in Dating
--     or not, any phone), carries couple_link: true while the flag is on
--     and nothing while it is off, so a phone with the flag off asks
--     nothing more.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('64');
  v_n constant uuid := pg_temp.id('65');
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at) VALUES (v_n, '155598265', now());
  INSERT INTO public.users (id, phone, display_name, path) VALUES (v_n, '+155598265', 'No dating', 'relationship');
  IF pg_temp.j(v_a, '64', 'SELECT public.get_dating_home()') ->> 'couple_link' IS DISTINCT FROM 'true'
     OR pg_temp.j(v_a, NULL, 'SELECT public.get_dating_home()') ->> 'couple_link' IS DISTINCT FROM 'true'
     OR pg_temp.j(v_n, NULL, 'SELECT public.get_dating_home()') ->> 'couple_link' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the flag on the Dating read does not say so: %',
      pg_temp.j(v_n, NULL, 'SELECT public.get_dating_home()');
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_couple_link';
  IF pg_temp.j(v_a, '64', 'SELECT public.get_dating_home()') ? 'couple_link'
     OR pg_temp.j(v_n, NULL, 'SELECT public.get_dating_home()') ? 'couple_link' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the flag off the Dating read names the couple link';
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_couple_link';
END $$;
````

Create `.superpowers/sdd/2026-11-23-spec2-w9/edit_tests_T2.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W9 Task 2: the canary takes the origin, How we met, the offer
# (the app's), the export's Dating part (the service role's alone, S-4),
# its read log (nobody's) and export_relationship (it now names
# couple_how_we_met; still nobody's but the database's); the export
# contract asserts the own-data dating part (data_export_contracts.sql
# :229-233; §4.10, I-13). The export's Dating part is a new reader of the
# reflections, the never-introduce list and the photos (the person's own,
# for their own export): three catalogue pins take it; the service role's
# grants test lists its read log among the tables no API role holds.
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-23-spec2-w9/anchor.py')['edit']

edit('supabase/tests/dating_rls_canary.sql', [
    ("""-- @@W9-T2-CANARY@@
""", """-- Spec 2 W9 Task 2: the origin, How we met and the post-link offer are
-- the app's; the export's Dating part is the service role's alone (S-4)
-- and its read log nobody's; export_relationship names couple_how_we_met
-- now and stays the database's own.
INSERT INTO allowed_rel (name, authenticated, service_dml) VALUES
  ('dating_export_reads', '', '');
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('get_dating_link_origin(uuid)', 'authenticated', ''),
  ('get_how_we_met(uuid)', 'authenticated', ''),
  ('get_dating_post_link_offer()', 'authenticated', ''),
  ('dismiss_dating_post_link_offer(text)', 'authenticated', ''),
  ('dating_export_for_job(uuid)', '', 'service_role'),
  ('export_relationship(uuid,uuid)', '', '');
"""),
], 'T2 canary')

edit('supabase/tests/data_export_contracts.sql', [
    ("""  FOREACH k IN ARRAY ARRAY['analysis', 'patterns', 'compatibility', 'safety', 'dating', 'forum'] LOOP
    IF b ? k OR (b->'personal') ? k OR r ? k THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a "%" section exists', k;
    END IF;
  END LOOP;
""", """  -- Spec 2 W9 (S-4, I-13): Dating is never a section of the bundle; the
  -- own-data dating part is its own file, from dating_export_for_job with
  -- the building job (1b below).
  FOREACH k IN ARRAY ARRAY['analysis', 'patterns', 'compatibility', 'safety', 'dating', 'forum'] LOOP
    IF b ? k OR (b->'personal') ? k OR r ? k THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a "%" section exists', k;
    END IF;
  END LOOP;
"""),
    ("""-- 2. The media manifest.
""", """-- 1b. Spec 2 W9 (S-4, I-13): the own-data dating part. U and P met in
-- Dating and linked; with U's export building, dating_export_for_job (the
-- worker's, as the service role) gives U's own Dating data and U's own
-- sent message, nothing of P's, no id; for a job not building it refuses.
DO $$
DECLARE
  v_job uuid;
  v_m uuid;
  d jsonb;
BEGIN
  INSERT INTO public.dating_enrollments (user_id, state, opted_in_at, paused_at, pause_reason)
  VALUES (pg_temp.u(), 'paused', now() - interval '40 days', now() - interval '1 day', 'relationship');
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, matched_at, closed_at, closed_reason, evidence_until)
  VALUES (least(pg_temp.u(), pg_temp.p()), greatest(pg_temp.u(), pg_temp.p()), 'closed', now() - interval '20 days',
          now() - interval '1 day', 'couple_linked', now() + interval '29 days')
  RETURNING id INTO v_m;
  INSERT INTO public.dating_messages (match_id, sender_side, sender_user_id, body, body_masked, mask_version, idempotency_key, created_at)
  VALUES (v_m, CASE WHEN pg_temp.u() < pg_temp.p() THEN 'low' ELSE 'high' END, pg_temp.u(), 'Una wrote this in Dating',
          'Una wrote this in Dating', 1, 'w9-export-u', now() - interval '19 days'),
         (v_m, CASE WHEN pg_temp.p() < pg_temp.u() THEN 'low' ELSE 'high' END, pg_temp.p(), 'Paa wrote this in Dating',
          'Paa wrote this in Dating', 1, 'w9-export-p', now() - interval '18 days');
  INSERT INTO public.data_export_jobs (user_id, status, claimed_at) VALUES (pg_temp.u(), 'building', now()) RETURNING id INTO v_job;
  EXECUTE 'SET LOCAL ROLE service_role';
  d := public.dating_export_for_job(v_job);
  RESET ROLE;
  IF d ->> 'format' IS DISTINCT FROM 'attune-dating-export' OR d -> 'enrolment' ->> 'state' IS DISTINCT FROM 'paused'
     OR jsonb_array_length(d -> 'conversations') <> 1
     OR d -> 'conversations' -> 0 -> 'my_messages' -> 0 ->> 'text' IS DISTINCT FROM 'Una wrote this in Dating'
     OR jsonb_array_length(d -> 'conversations' -> 0 -> 'my_messages') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the own-data dating part is wrong: %', d;
  END IF;
  IF d::text LIKE '%Paa%' OR d::text ~ '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the dating part holds the partner''s words, name or an id: %', d;
  END IF;
  UPDATE public.data_export_jobs SET status = 'ready' WHERE id = v_job;
  BEGIN
    EXECUTE 'SET LOCAL ROLE service_role';
    PERFORM public.dating_export_for_job(v_job);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a ready job was read';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'export:not_building' THEN
      RAISE;
    END IF;
  END;
  RESET ROLE;
  DELETE FROM public.data_export_jobs WHERE id = v_job;
  DELETE FROM public.dating_matches WHERE id = v_m;
  DELETE FROM public.dating_enrollments WHERE user_id = pg_temp.u();
END $$;

-- 2. The media manifest.
"""),
], 'T2 export contract')

edit('supabase/tests/service_role_grants_test.sql', [
    ("""                          'dating_link_origins', 'couple_how_we_met')
    AND NOT has_table_privilege('service_role', c.oid, 'SELECT');""",
     """                          'dating_link_origins', 'couple_how_we_met', 'dating_export_reads')
    AND NOT has_table_privilege('service_role', c.oid, 'SELECT');"""),
    ("""                          'dating_link_origins', 'couple_how_we_met')
    -- Spec 2 W1b (batch-4 fix round 1, C-1)""",
     """                          'dating_link_origins', 'couple_how_we_met', 'dating_export_reads')
    -- Spec 2 W1b (batch-4 fix round 1, C-1)"""),
], 'T2 service role grants')

edit('supabase/tests/dating_v2_home_contracts.sql', [
    ("""  IF v IS DISTINCT FROM 'get_my_gentle_wait_reflection(), private.dating_carry_on_auth_user_delete(), '""",
     """  -- Spec 2 W9 (S-4, I-13): the export's Dating part, for the person's own export only.
  IF v IS DISTINCT FROM 'dating_export_for_job(uuid), get_my_gentle_wait_reflection(), private.dating_carry_on_auth_user_delete(), '"""),
], 'T2 reflections pin')

edit('supabase/tests/dating_v2_identity_contracts.sql', [
    ("""     IS DISTINCT FROM 'add_dating_never_introduce(text,text,text),dating_never_introduce_excludes(uuid,uuid),""",
     """     -- Spec 2 W9 (S-4, I-13): and the export's Dating part (the person's own labels, never a number).
     IS DISTINCT FROM 'add_dating_never_introduce(text,text,text),dating_export_for_job(uuid),dating_never_introduce_excludes(uuid,uuid),"""),
], 'T2 never-introduce pin')

edit('supabase/tests/dating_v2_setup_contracts.sql', [
    ("""public.create_dating_photo_upload_intent(text):authenticated; public.dating_photo_keys_for_viewer""",
     """public.create_dating_photo_upload_intent(text):authenticated; public.dating_export_for_job(uuid):service_role; public.dating_photo_keys_for_viewer"""),
    ("""  -- Spec 2 W7b: the console's case, photo queue, photo decision and""",
     """  -- Spec 2 W9 (S-4, I-13): the export's Dating part lists the person's own
  -- Spec 2 W9 photos (position, caption, state, date; never a key or a file).
  -- Spec 2 W7b: the console's case, photo queue, photo decision and"""),
], 'T2 photos pin')
````

```bash
D=.superpowers/sdd/2026-11-23-spec2-w9
python3 -I $D/splice.py supabase/tests/dating_v2_link_contracts.sql '-- @@W9-T2@@' $D/contract_T2.sql
python3 -I $D/edit_tests_T2.py
for f in dating_v2_link_contracts dating_rls_canary data_export_contracts dating_v2_device_contracts service_role_grants_test dating_v2_home_contracts dating_v2_identity_contracts dating_v2_setup_contracts; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$f.sql > /dev/null 2>&1 && echo "$f exit=0" || echo "$f FAILED"
done
```

Expected: `…dating_v2_link_contracts.sql: contract_T2.sql spliced at -- @@W9-T2@@`; `…dating_rls_canary.sql: 1 edit(s) (T2 canary)`, `…data_export_contracts.sql: 2 edit(s) (T2 export contract)`, `…service_role_grants_test.sql: 2 edit(s) (T2 service role grants)`, `…dating_v2_home_contracts.sql: 1 edit(s) (T2 reflections pin)`, `…dating_v2_identity_contracts.sql: 1 edit(s) (T2 never-introduce pin)`, `…dating_v2_setup_contracts.sql: 2 edit(s) (T2 photos pin)`; eight lines ending `exit=0` (the canary's S-4 scan holds: `dating_export_for_job` is the service role's one decrypting path; `export_relationship` names `couple_how_we_met` now and stays the database's own. The first replay's W9a gate found three W2–W3 catalogue pins that list every function reading the reflections, the never-introduce list and the photos: the export's Dating part is a new, reviewed reader of each, the person's own).

- [ ] **Step 4: The mutants (Task 2's, then Task 1's on the rebuilt migration)**

Create `.superpowers/sdd/2026-11-23-spec2-w9/mut_T2.py` with exactly:

````python
# Spec 2 W9 Task 2 mutants (mutate.py on 20261123100000_dating_v2_couple_link.sql,
# the twin applied after each). Each must make dating_v2_link_contracts.sql
# fail with a CONTRACT VIOLATED line.
MUTS = {
    # Spec mutant 22: the export includes the counterpart's messages.
    'm22_counterpart_messages': ("                                  WHERE d.match_id = c.id AND d.sender_user_id = v_user), '[]'::jsonb)) ORDER BY c.n)\n",
                                 "                                  WHERE d.match_id = c.id), '[]'::jsonb)) ORDER BY c.n)\n"),
    # Spec mutant 23: a job that isn't building is read, or the user id is an argument.
    'm23_not_building': ("  IF v_job.id IS NULL OR v_job.status IS DISTINCT FROM 'building' THEN\n    RAISE EXCEPTION 'export:not_building';\n",
                         "  IF v_job.id IS NULL THEN\n    RAISE EXCEPTION 'export:not_building';\n"),
    'm23_for_user': ('RAW', "CREATE FUNCTION public.dating_export_for_user(p_user uuid) RETURNS jsonb LANGUAGE sql AS 'SELECT NULL::jsonb';"),
    # Spec mutant 28: the origin skips the membership check.
    'm28_origin_anyone': ("""   WHERE p_relationship_id IS NOT NULL AND o.relationship_id = p_relationship_id
     AND v_user IN (r.user_a, r.user_b) AND r.status IN ('active', 'paused')
     AND public.dating_flag_enabled('dating_couple_link') IS TRUE;
  IF v_at IS NULL THEN""", """   WHERE p_relationship_id IS NOT NULL AND o.relationship_id = p_relationship_id
     AND r.status IN ('active', 'paused')
     AND public.dating_flag_enabled('dating_couple_link') IS TRUE;
  IF v_at IS NULL THEN"""),
    'origin_ended': ("""     AND v_user IN (r.user_a, r.user_b) AND r.status IN ('active', 'paused')
     AND public.dating_flag_enabled('dating_couple_link') IS TRUE;
  IF v_at IS NULL THEN""", """     AND v_user IN (r.user_a, r.user_b)
     AND public.dating_flag_enabled('dating_couple_link') IS TRUE;
  IF v_at IS NULL THEN"""),
    'origin_flag_ignored': ("""     AND public.dating_flag_enabled('dating_couple_link') IS TRUE;
  IF v_at IS NULL THEN""", """  ;
  IF v_at IS NULL THEN"""),
    'card_anyone': ("""   WHERE p_relationship_id IS NOT NULL AND h.relationship_id = p_relationship_id
     AND v_user IN (r.user_a, r.user_b) AND r.status IN ('active', 'paused')""",
                    """   WHERE p_relationship_id IS NOT NULL AND h.relationship_id = p_relationship_id
     AND r.status IN ('active', 'paused')"""),
    'card_mine_inverted': ("              'mine', (x.v ->> 'by') = v_user::text,", "              'mine', (x.v ->> 'by') <> v_user::text,"),
    'export_relationship_no_card': ("    'how_we_met', (SELECT jsonb_agg(jsonb_build_object( -- Spec 2 W9\n",
                                    "    'how_we_met_gone', (SELECT jsonb_agg(jsonb_build_object( -- Spec 2 W9\n"),
    'export_card_ids': ("        'from', public.export_who(p_user_id, (x.v->>'by')::uuid), 'kind', x.v->>'kind', -- Spec 2 W9\n",
                        "        'from', x.v->>'by', 'kind', x.v->>'kind', -- Spec 2 W9\n"),
    'moment_never_shown': ("  IF (CASE WHEN v_low THEN v_o.low_moment_seen_at ELSE v_o.high_moment_seen_at END) IS NULL THEN\n",
                           "  IF false THEN\n"),
    'offer_early': ("  IF now() >= v_o.linked_at + interval '30 days'\n", "  IF now() >= v_o.linked_at + interval '28 days'\n"),
    'offer_without_data': ("     AND (CASE WHEN v_low THEN v_o.low_offer_closed_at ELSE v_o.high_offer_closed_at END) IS NULL\n     AND private.dating_has_data(v_user) THEN\n",
                           "     AND (CASE WHEN v_low THEN v_o.low_offer_closed_at ELSE v_o.high_offer_closed_at END) IS NULL THEN\n"),
    'keep_asks_again': ("     AND (CASE WHEN v_low THEN v_o.low_offer_closed_at ELSE v_o.high_offer_closed_at END) IS NULL\n",
                        "\n"),
    'keep_for_both': ("         low_offer_closed_at = CASE WHEN p_offer = 'delete' AND o.low_user_id = v_user\n",
                      "         low_offer_closed_at = CASE WHEN p_offer = 'delete'\n"),
    'read_limit_gone': ("  IF (SELECT count(*) FROM public.dating_export_reads AS x WHERE x.job_id = p_job_id) >= 3 THEN\n",
                        "  IF (SELECT count(*) FROM public.dating_export_reads AS x WHERE x.job_id = p_job_id) >= 4 THEN\n"),
    'reads_unlogged': ("  INSERT INTO public.dating_export_reads (job_id) VALUES (p_job_id);\n", ""),
    'export_not_decrypted': ("    'about_you', pg_catalog.jsonb_build_object('identity', v_identity,", "    'about_you', pg_catalog.jsonb_build_object('identity', NULL,"),
    'export_counterpart_name': ("                                 'name', 'conversation-' || c.n, 'matched_at', c.matched_at,\n",
                                "                                 'name', (SELECT p.display_name FROM public.dating_profiles AS p WHERE p.user_id IN (SELECT m2.user_low_id FROM public.dating_matches AS m2 WHERE m2.id = c.id UNION SELECT m3.user_high_id FROM public.dating_matches AS m3 WHERE m3.id = c.id) AND p.user_id <> v_user), 'matched_at', c.matched_at,\n"),
    'export_for_nobody': ("""          OR EXISTS (SELECT 1 FROM public.dating_enrollments AS e WHERE e.user_id = v_user)) THEN
    RETURN NULL;""", """          OR true) THEN
    RETURN NULL;"""),
}
# R-W9-16: the flag in the Dating read.
MUTS.update({
    'home_flag_always': ("           || CASE WHEN public.dating_flag_enabled('dating_couple_link') IS TRUE THEN jsonb_build_object('couple_link', true) ELSE '{}'::jsonb END; -- Spec 2 W9 (R-W9-16)\n",
                         "           || jsonb_build_object('couple_link', true); -- Spec 2 W9 (R-W9-16)\n"),
    'home_flag_never': ("           || CASE WHEN public.dating_flag_enabled('dating_couple_link') IS TRUE THEN jsonb_build_object('couple_link', true) ELSE '{}'::jsonb END; -- Spec 2 W9 (R-W9-16)\n",
                        "           || '{}'::jsonb; -- Spec 2 W9 (R-W9-16)\n"),
})
````

```bash
D=.superpowers/sdd/2026-11-23-spec2-w9
M=supabase/migrations/20261123100000_dating_v2_couple_link.sql; C=supabase/tests/dating_v2_link_contracts.sql; G=supabase/migrations/20261123100010_dating_v2_couple_link_grants.sql
for s in T2 T1; do echo "$s $(W9_DB=attune_spec3a python3 -I $D/mutate.py $M $C $D/mut_$s.py $D/mut $G | tee $D/mut_$s.txt | grep -c 'CONTRACT VIOLATED')"; done
```

Expected: `T2 22`, `T1 22` (`m22_counterpart_messages`: `the export is not A's own data`; `m23_not_building`: `a job that isn't building was read`; `m23_for_user`: `a dating_export_for_user exists (S-4)`; `m28_origin_anyone`: `the origin answers a stranger …`).

- [ ] **Step 5: Record the tree (do not commit).**

### Task 3: The push audit follows every write (carry 1), Today's inner window edges (carry 3), and the second Yes's races (R-W9-4, R-W9-13)

**Files:**
- Create: `$D/{edit_tests_T3.py, edit_tests_T3b.py, race_T3.sh, edit_race_T3.py, mut_T3.py}`
- Modify: `supabase/tests/dating_v2_device_contracts.sql` (§A's walk; C1d), `scripts/concurrency/dating_kill_switch_races.sh` (three cases)
- Test: the device contract (A, C1d); the race script (cases 64–66)

**Interfaces:**
- Consumes: Task 1's `confirm_dating_couple_link`, `cancel_dating_couple_link`, `request_dating_couple_link`; W8's §A helpers (`pg_temp.w8a_*`) and C-section helpers (`pg_temp.ready`, `match`, `today_json`, `flag`).
- Produces: temp tables `w9a_fn`, `w9a_edge`, `w9a_dat`, `w9a_reach` inside the device contract (the walk W10 extends).

- [ ] **Step 1: §A follows writes; C1d**

Create `.superpowers/sdd/2026-11-23-spec2-w9/edit_tests_T3.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W9 Task 3 (carry 1): section A of the device contract follows a
# Dating function's writes. The walk now runs over every schema's SQL and
# plpgsql functions (a trigger function outside public and private is
# seen), and besides calls by name it follows each write (INSERT, UPDATE,
# DELETE, MERGE; quoted or schema-qualified, or inside a literal run by
# EXECUTE) to the triggers that fire on that table for that operation, so
# a Dating function's write into relationships, timeline_events,
# game_sessions or any other table brings that table's triggers into the
# audit. A queue write may be quoted, schema-qualified or a MERGE. Three
# more rules over everything the walk reaches: no write to the other
# queue tables (in_app_notifications, message_notification_outbox,
# verdict_notification_outbox; the queue's own triggers aside), no call
# to send-notification or OneSignal, and no EXECUTE of a statement built
# at run time (format, a variable, ||), which the audit could not follow.
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-23-spec2-w9/anchor.py')['edit']
C = 'supabase/tests/dating_v2_device_contracts.sql'
edit(C, [
    ("""--      to a fixpoint. The app routes exactly those (and the old
--      dating_mutual_match, to Me, for one release: A-7).
""", """--      to a fixpoint. The app routes exactly those (and the old
--      dating_mutual_match, to Me, for one release: A-7).
--      Spec 2 W9 (carry 1): the walk covers every schema's SQL and
--      plpgsql functions and follows each write to the triggers that fire
--      on that table for that operation (a Dating write into
--      relationships, timeline_events, game_sessions ... brings their
--      triggers in); a queue write may be quoted, schema-qualified or a
--      MERGE; nothing reached writes the other queue tables, calls
--      send-notification or OneSignal, or EXECUTEs a statement built at
--      run time.
"""),
    ("""    RETURN NEXT;
    v_start := i + 2;
  END LOOP;
END $f$;

DO $$
DECLARE
  r record;
  c record;
""", """    RETURN NEXT;
    v_start := i + 2;
  END LOOP;
END $f$;

-- Spec 2 W9 (carry 1): the functions (every schema's SQL and plpgsql
-- ones), the edges (a call by name; a write, to each trigger that fires on
-- its table for its operation) and the walk from Dating's functions to its
-- fixpoint, tagged by root as before.
CREATE TEMP TABLE w9a_fn AS
  SELECT p.oid, p.oid::regprocedure::text AS sig, p.proname::text AS proname, p.prosrc AS src
    FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
   WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND p.prokind IN ('f', 'p')
     AND p.prolang IN (SELECT l.oid FROM pg_language AS l WHERE l.lanname IN ('plpgsql', 'sql'));
CREATE TEMP TABLE w9a_edge AS
  SELECT DISTINCT c.oid AS a, f.oid AS b
    FROM w9a_fn AS c CROSS JOIN LATERAL regexp_matches(c.src, '([a-z_][a-z0-9_]*)\\s*\\(', 'gi') AS m
    JOIN w9a_fn AS f ON f.proname = lower(m[1])
  UNION
  SELECT DISTINCT c.oid, t.tgfoid
    FROM w9a_fn AS c CROSS JOIN LATERAL regexp_matches(c.src,
           '\\m(insert\\s+into|update|delete\\s+from|merge\\s+into)\\s+(?:only\\s+)?(?:"?([a-z_][a-z0-9_]*)"?\\s*\\.\\s*)?"?([a-z_][a-z0-9_]*)"?', 'gi') AS m
    JOIN pg_class AS tc ON tc.relname = lower(m[3]) AND tc.relkind IN ('r', 'p')
    JOIN pg_namespace AS tn ON tn.oid = tc.relnamespace AND tn.nspname = coalesce(lower(m[2]), 'public')
    JOIN pg_trigger AS t ON t.tgrelid = tc.oid AND NOT t.tgisinternal
   WHERE (lower(m[1]) ~ '^insert' AND t.tgtype & 4 <> 0) OR (lower(m[1]) = 'update' AND t.tgtype & 16 <> 0)
      OR (lower(m[1]) ~ '^delete' AND t.tgtype & 8 <> 0) OR lower(m[1]) ~ '^merge';
CREATE TEMP TABLE w9a_dat AS
  SELECT fn.* FROM w9a_fn AS fn
   WHERE fn.proname ~ '(dating|moderation)' OR fn.src ~ '(public|private)\\.dating_\\w+'
      OR fn.oid IN (SELECT t.tgfoid FROM pg_trigger AS t JOIN pg_class AS tc ON tc.oid = t.tgrelid
                     JOIN pg_namespace AS tn ON tn.oid = tc.relnamespace
                    WHERE NOT t.tgisinternal AND tn.nspname NOT IN ('pg_catalog', 'information_schema')
                      AND tc.relname ~ '^dating_');
CREATE TEMP TABLE w9a_reach AS
  WITH RECURSIVE reach (root, oid) AS (
    SELECT CASE WHEN d.proname = 'moderation_opinions_remove' THEN d.proname ELSE 'dating' END, d.oid FROM w9a_dat AS d
    UNION
    SELECT reach.root, e.b FROM reach JOIN w9a_edge AS e ON e.a = reach.oid)
  SELECT * FROM reach;

DO $$
DECLARE
  r record;
  c record;
"""),
    ("""  FOR r IN
    WITH RECURSIVE fn AS (
      SELECT p.oid, p.oid::regprocedure::text AS sig, p.proname, p.prosrc AS src
        FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
       WHERE n.nspname IN ('public', 'private') AND p.prokind IN ('f', 'p')),
    trg AS (
      SELECT DISTINCT t.tgfoid AS oid
        FROM pg_trigger AS t JOIN pg_class AS tc ON tc.oid = t.tgrelid JOIN pg_namespace AS tn ON tn.oid = tc.relnamespace
       WHERE NOT t.tgisinternal AND tn.nspname IN ('public', 'private') AND tc.relname ~ '^dating_'),
    dat AS (
      SELECT * FROM fn WHERE fn.proname ~ '(dating|moderation)' OR fn.src ~ '(public|private)\\.dating_\\w+'
                          OR fn.oid IN (SELECT trg.oid FROM trg)),
    -- The walk, to its fixpoint, tagged by root: 'dating' from every Dating
    -- function but the exempt root, which walks under its own name.
    reach (root, oid) AS (
      SELECT CASE WHEN dat.proname = 'moderation_opinions_remove'
                  THEN dat.proname::text ELSE 'dating' END, dat.oid FROM dat
      UNION
      SELECT reach.root, f.oid
        FROM reach JOIN fn AS caller ON caller.oid = reach.oid
        JOIN fn AS f ON caller.src ~ ('\\m' || f.proname || '\\s*\\(')),
    wr AS (
      SELECT * FROM fn
       WHERE fn.src ~* '\\m(insert\\s+into|update)\\s+(public\\.)?"?scheduled_notifications\\M')
""", """  FOR r IN
    -- Spec 2 W9 (carry 1): the walk is w9a_reach (above); a queue write may
    -- be quoted, schema-qualified or a MERGE.
    WITH fn AS (SELECT * FROM w9a_fn),
    dat AS (SELECT * FROM w9a_dat),
    reach AS (SELECT * FROM w9a_reach),
    wr AS (
      SELECT * FROM fn
       WHERE fn.src ~* '\\m(insert\\s+into|update|merge\\s+into)\\s+(only\\s+)?("?[a-z_]+"?\\s*\\.\\s*)?"?scheduled_notifications"?\\M')
"""),
    ("""    IF r.src ~* '\\minsert\\s+into\\s+(public\\.)?"?scheduled_notifications\\M' AND v_k = 0 THEN""",
     """    IF r.src ~* '\\m(insert\\s+into|merge\\s+into)\\s+(only\\s+)?("?[a-z_]+"?\\s*\\.\\s*)?"?scheduled_notifications"?\\M' AND v_k = 0 THEN -- Spec 2 W9"""),
    ("""  -- The body helper: every body it returns is one of the copies, and each
  -- is the whole answer (fix round 2, Re-M-3: never a copy || more).
""", """  -- Spec 2 W9 (carry 1): nothing the Dating walk reaches writes another
  -- queue table (the push queue's own triggers aside), calls
  -- send-notification or OneSignal, or EXECUTEs a statement built at run
  -- time (format, a variable, ||: a write the walk could not follow).
  FOR r IN
    SELECT f.oid, f.sig, f.src FROM w9a_fn AS f
     WHERE f.oid IN (SELECT x.oid FROM w9a_reach AS x WHERE x.root = 'dating')
  LOOP
    IF r.src ~* '\\m(insert\\s+into|update|merge\\s+into)\\s+(only\\s+)?("?[a-z_]+"?\\s*\\.\\s*)?"?(in_app_notifications|message_notification_outbox|verdict_notification_outbox)"?\\M'
       AND r.oid NOT IN (SELECT t.tgfoid FROM pg_trigger AS t
                          WHERE t.tgrelid = 'public.scheduled_notifications'::regclass AND NOT t.tgisinternal) THEN
      v_bad := v_bad || format(E'\\n  %s writes a notification queue other than the neutral push queue', r.sig);
    END IF;
    IF r.src ~* '(send-notification|onesignal)' THEN
      v_bad := v_bad || format(E'\\n  %s sends a notification itself', r.sig);
    END IF;
    IF lower(pg_temp.w8a_mask(r.src)) ~ '\\mexecute\\s+(?!''|\\$)' THEN
      v_bad := v_bad || format(E'\\n  %s runs a statement built at run time, which the audit cannot follow', r.sig);
    END IF;
  END LOOP;
  -- The body helper: every body it returns is one of the copies, and each
  -- is the whole answer (fix round 2, Re-M-3: never a copy || more).
"""),
    ("""    SELECT wr.oid, wr.sig, wr.src FROM wr
     WHERE wr.oid IN (SELECT reach.oid FROM reach
                       WHERE (reach.root, wr.proname::text) IS DISTINCT FROM ('moderation_opinions_remove', 'enqueue_forum_notification'))
""", """    SELECT wr.oid, wr.sig, wr.src FROM wr
     WHERE wr.oid IN (SELECT reach.oid FROM reach
                       WHERE (reach.root, wr.proname::text) IS DISTINCT FROM ('moderation_opinions_remove', 'enqueue_forum_notification'))
       -- Spec 2 W9: the push queue's own triggers (its guards, reached now
       -- through every write to it) are audited only when they are Dating's
       -- (the UNION below), as before.
       AND wr.oid NOT IN (SELECT t.tgfoid FROM pg_trigger AS t
                           WHERE t.tgrelid = 'public.scheduled_notifications'::regclass AND NOT t.tgisinternal)
"""),
], 'T3 push audit (carry 1)')
````

Create `.superpowers/sdd/2026-11-23-spec2-w9/edit_tests_T3b.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W9 Task 3 (carry 3, W8 C1c's inner edges): Today's open-chat
# pause keeps dating_open_chats' windows from the inside too: a match whose
# last message is 13 days old counts, and so does a 6-day-old match with
# no message. Fixtures 140-143.
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-23-spec2-w9/anchor.py')['edit']
edit('supabase/tests/dating_v2_device_contracts.sql', [
    ("""-- =====================================================================
-- C2. Away where Dating isn't allowed (§2.5): a Ghana person in the UAE.
""", """-- =====================================================================
-- C1d. (Spec 2 W9, carry 3) C1c's windows from the inside: an old match
--      whose last message is 13 days old counts, and so does a match 6
--      days old with no message; with a fresh one that is the pause (3),
--      on Today and in dating_open_chats alike. Fixtures 140-143.
-- =====================================================================
DO $$
DECLARE
  v_p constant uuid := pg_temp.ready('140');
  v_at constant int := coalesce(((private.dating_intro_config()).o_config ->> 'open_chat_pause_at')::int, 3);
  v_men uuid[] := '{}';
  v_m uuid[] := '{}';
  v_state text;
  v_open int;
BEGIN
  PERFORM pg_temp.flag(false);
  FOR i IN 141 .. 143 LOOP
    v_men := v_men || pg_temp.ready(i::text, '{"identity": "man", "seeking": ["woman"]}');
    v_m := v_m || pg_temp.match(v_p, v_men[i - 140]);
  END LOOP;
  -- 1: 20 days old, its last message 13 days ago; 2: 6 days old, no
  -- message; 3: fresh.
  UPDATE public.dating_matches SET matched_at = now() - interval '20 days' WHERE id = v_m[1];
  UPDATE public.dating_matches SET matched_at = now() - interval '6 days' WHERE id = v_m[2];
  INSERT INTO public.dating_messages (match_id, sender_side, sender_user_id, body, body_masked, mask_version, idempotency_key, created_at)
  VALUES (v_m[1], CASE WHEN v_men[1] < v_p THEN 'low' ELSE 'high' END, v_men[1], 'hello', 'hello', 1, 'w9-c1d-1',
          now() - interval '13 days');
  v_state := pg_temp.today_json(v_p, '140') ->> 'today_state';
  v_open := private.dating_open_chats(v_p, now());
  IF v_at <> 3 OR v_open IS DISTINCT FROM 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the C1d fixture is not 3 open conversations (pause at %): %', v_at, v_open;
  END IF;
  IF v_state IS DISTINCT FROM 'paused_open_chats' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Today''s open-chat pause drops a conversation inside its windows: % with % open',
      v_state, v_open;
  END IF;
END $$;

-- =====================================================================
-- C2. Away where Dating isn't allowed (§2.5): a Ghana person in the UAE.
"""),
], 'T3 C1d (carry 3)')
````

```bash
D=.superpowers/sdd/2026-11-23-spec2-w9
python3 -I $D/edit_tests_T3.py
python3 -I $D/edit_tests_T3b.py
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_device_contracts.sql 2>&1 | grep -oE 'all held|CONTRACT VIOLATED.*' | head -1
```

Expected: `…dating_v2_device_contracts.sql: 6 edit(s) (T3 push audit (carry 1))`, `…: 1 edit(s) (T3 C1d (carry 3))`; `all held` (the replay found the queue's own guard, `scheduled_notifications_quiet_guard`, reached through every write to the queue; R-W9-13 audits the queue's own triggers only when they are Dating's, as W8 did).

- [ ] **Step 2: The mutants (W9's, then W8's §A set again)**

Create `.superpowers/sdd/2026-11-23-spec2-w9/mut_T3.py` with exactly:

````python
# Spec 2 W9 Task 3 mutants (mutate.py; RAW: each adds a Dating writer the
# W8 audit could not see: carry 1). Each must make
# dating_v2_device_contracts.sql fail with a CONTRACT VIOLATED line.
P = "jsonb_build_object('type', 'dating_match', 'route', 'dating', 'title', 'New Dating match', 'body', 'Someone likes you')"
MUTS = {
    # A Dating function writes a couple's timeline: its trigger's push
    # (notify_partner_moment_logged) names the moment.
    'writes_timeline': ('RAW', """CREATE FUNCTION public.zz_w9_dating_moment(p_rel uuid, p_user uuid) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at) VALUES (p_rel, p_user, 'moment', 'We met on Dating', current_date)
$f$;"""),
    # A trigger function outside public and private, on a Dating table.
    'trigger_elsewhere': ('RAW', """CREATE SCHEMA zz_w9;
CREATE FUNCTION zz_w9.push() RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, metadata)
  VALUES (NEW.user_low_id, 'dating_match', now(), """ + P + """);
  RETURN NEW;
END $f$;
CREATE TRIGGER zz_w9_push AFTER INSERT ON public.dating_matches FOR EACH ROW EXECUTE FUNCTION zz_w9.push();"""),
    'quoted_queue': ('RAW', """CREATE FUNCTION public.zz_w9_dating_quoted(p uuid) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO "public"."scheduled_notifications" (user_id, notification_type, scheduled_for, metadata)
  VALUES (p, 'dating_match', now(), """ + P + """)
$f$;"""),
    'merge_queue': ('RAW', """CREATE FUNCTION public.zz_w9_dating_merge(p uuid) RETURNS void LANGUAGE sql AS $f$
  MERGE INTO public.scheduled_notifications AS s USING (SELECT p AS u) AS x ON false
  WHEN NOT MATCHED THEN INSERT (user_id, notification_type, scheduled_for, metadata)
  VALUES (x.u, 'dating_match', now(), """ + P + """)
$f$;"""),
    'dynamic_queue': ('RAW', """CREATE FUNCTION public.zz_w9_dating_dynamic(p uuid) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  EXECUTE format('INSERT INTO public.%I (user_id, notification_type, scheduled_for) VALUES ($1, $2, now())', 'scheduled_notifications')
    USING p, 'dating_match';
END $f$;"""),
    'in_app_queue': ('RAW', """CREATE FUNCTION public.zz_w9_dating_in_app(p uuid) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO public.in_app_notifications (user_id, title, body) VALUES (p, 'Attune', 'You have something new in Attune.')
$f$;"""),
    'calls_send_notification': ('RAW', """CREATE FUNCTION public.zz_w9_dating_http(p uuid) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  PERFORM net.http_post(url := 'https://x.supabase.co/functions/v1/send-notification', body := jsonb_build_object('user_id', p));
END $f$;"""),
    # Behind a helper that is not Dating's: the write is followed through it.
    'helper_writes_timeline': ('RAW', """CREATE FUNCTION public.zz_w9_log(p_rel uuid, p_user uuid) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at) VALUES (p_rel, p_user, 'moment', 'A moment', current_date)
$f$;
CREATE FUNCTION public.zz_w9_dating_via(p_rel uuid, p_user uuid) RETURNS void LANGUAGE sql AS $f$
  SELECT public.zz_w9_log(p_rel, p_user)
$f$;"""),
}
# Carry 3: Today's windows shrink (LIVE on get_my_dating_today's body).
MUTS.update({
    'today_message_window_12': ('LIVE', ('public.get_my_dating_today(boolean)', [
        ("WHERE d.match_id = m.id AND d.created_at > now() - interval '14 days')) -- Spec 2 W8b",
         "WHERE d.match_id = m.id AND d.created_at > now() - interval '12 days')) -- Spec 2 W8b")])),
    'today_match_window_5': ('LIVE', ('public.get_my_dating_today(boolean)', [
        ("AND (m.matched_at > now() - interval '7 days' -- Spec 2 W8b",
         "AND (m.matched_at > now() - interval '5 days' -- Spec 2 W8b")])),
})
````

```bash
D=.superpowers/sdd/2026-11-23-spec2-w9; C=supabase/tests/dating_v2_device_contracts.sql
echo "T3 $(W9_DB=attune_spec3a python3 -I $D/mutate.py $C $C $D/mut_T3.py $D/mut | tee $D/mut_T3.txt | grep -c 'CONTRACT VIOLATED')"
echo "W8-T3 $(W9_DB=attune_spec3a python3 -I $D/mutate.py $C $C .superpowers/sdd/2026-11-22-spec2-w8/mut_T3.py $D/mut | tee $D/mut_W8T3.txt | grep -c 'CONTRACT VIOLATED')"
```

Expected: `T3 10` (`writes_timeline`: `notify_partner_moment_logged() puts keys {'title','body','type','relationship_id'} in a push payload`; `trigger_elsewhere`: `zz_w9.push() writes push type 'dating_match'`; `dynamic_queue`: `runs a statement built at run time …`; `today_message_window_12`: `Today's open-chat pause drops a conversation inside its windows`), `W8-T3 31`.

- [ ] **Step 3: The race cases**

Create `.superpowers/sdd/2026-11-23-spec2-w9/race_T3.sh` with exactly:

````bash
# Spec 2 W9 (§3.9, Ruling R-W9-4): the second Yes meets the asker. The
# confirm takes both setup locks first (every Dating writer's first lock),
# then the match, the request and both users rows. (64) the asker takes
# the request back while the second Yes sleeps in its last write: the
# take-back waits at the asker's setup lock, then finds it linked (linked).
# (65) the asker leaves Dating (exit sleeps holding the asker's setup lock)
# while the second Yes runs: it waits, then finds the chat ended (closed);
# no relationship. (66) the asker's path change (Just for me) sleeps
# holding the asker's users row while the second Yes runs: one of them
# retries inside itself, both land, the couple is linked on the
# Relationship path. No caller sees an error.
FX_LINK="SELECT race.reset(); ALTER SEQUENCE race.s1 RESTART;
DELETE FROM public.relationships WHERE user_a::text LIKE '5e2f%' OR user_b::text LIKE '5e2f%';
SELECT race.ready('64', 'woman', ARRAY['man']), race.ready('65', 'man', ARRAY['woman']);
UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_couple_link';
INSERT INTO race.outcome SELECT 'lk_match', race.match(race.id('64'), race.id('65'))::text;
UPDATE public.dating_matches SET low_we_met_at = now() WHERE id = (SELECT result::uuid FROM race.outcome WHERE name = 'lk_match');
INSERT INTO race.outcome SELECT 'lk_req', race.call(race.id('64'), format('SELECT public.request_dating_couple_link(%L, %L, true)',
  race.key('ask'), (SELECT result FROM race.outcome WHERE name = 'lk_match'))) ->> 'request_id';"
LK_YES="race.call(race.id('65'), format('SELECT public.confirm_dating_couple_link(%L, %L, true)', race.key('yes'),
  (SELECT result FROM race.outcome WHERE name = 'lk_req')))::text"
LK_LINKED="(SELECT r.state FROM public.dating_couple_link_requests AS r WHERE r.id = (SELECT result::uuid FROM race.outcome WHERE name = 'lk_req'))"
LK_RELS="(SELECT count(*) FROM public.relationships WHERE race.id('64') IN (user_a, user_b) AND status = 'active')"
run "the asker takes it back while the second Yes sleeps: linked, one couple, no deadlock" "$FX_LINK" \
  "SET race.sleep_dating_couple_link_requests_update = '1.5:race.s1';
   INSERT INTO race.outcome SELECT 'lk_yes', $LK_YES;" \
  "SELECT pg_sleep(0.5);
   INSERT INTO race.outcome SELECT 'lk_overlap', (SELECT is_called FROM race.s1)::text;
   INSERT INTO race.outcome SELECT 'lk_back', race.call(race.id('64'), format('SELECT public.cancel_dating_couple_link(%L)',
     (SELECT result FROM race.outcome WHERE name = 'lk_req')))::text;" \
  "SELECT CASE WHEN (SELECT result FROM race.outcome WHERE name = 'lk_overlap') IS DISTINCT FROM 'true'
               THEN 'the take-back did not run while the second Yes slept (no race)'
               WHEN (SELECT result::jsonb ->> 'ok' FROM race.outcome WHERE name = 'lk_yes') IS DISTINCT FROM 'true'
               THEN 'the second Yes answered ' || coalesce((SELECT result FROM race.outcome WHERE name = 'lk_yes'), '-')
               WHEN (SELECT result::jsonb FROM race.outcome WHERE name = 'lk_back') IS DISTINCT FROM '{\"ok\": false, \"reason\": \"linked\"}'::jsonb
               THEN 'the take-back answered ' || coalesce((SELECT result FROM race.outcome WHERE name = 'lk_back'), '-')
               WHEN $LK_LINKED IS DISTINCT FROM 'linked' OR $LK_RELS <> 1
               THEN 'not one linked couple'
               ELSE 'ok' END;" serialised

run "the asker leaves Dating while the second Yes waits: closed, no couple, no deadlock" "$FX_LINK" \
  "SET race.sleep_dating_profile_sensitive_delete = '1.5:race.s1';
   INSERT INTO race.outcome SELECT 'lk_exit', race.call(race.id('64'), format('SELECT to_jsonb(public.exit_dating_mode(%L))', race.key('exit'))) ->> 'state';" \
  "SELECT pg_sleep(0.5);
   INSERT INTO race.outcome SELECT 'lk_overlap', (SELECT is_called FROM race.s1)::text;
   INSERT INTO race.outcome SELECT 'lk_yes', $LK_YES;" \
  "SELECT CASE WHEN (SELECT result FROM race.outcome WHERE name = 'lk_overlap') IS DISTINCT FROM 'true'
               THEN 'the second Yes did not run while the leave slept (no race)'
               WHEN (SELECT result FROM race.outcome WHERE name = 'lk_exit') IS DISTINCT FROM 'exited'
               THEN 'the leave answered ' || coalesce((SELECT result FROM race.outcome WHERE name = 'lk_exit'), '-')
               WHEN (SELECT result::jsonb FROM race.outcome WHERE name = 'lk_yes') IS DISTINCT FROM '{\"ok\": false, \"reason\": \"closed\"}'::jsonb
               THEN 'the second Yes answered ' || coalesce((SELECT result FROM race.outcome WHERE name = 'lk_yes'), '-')
               WHEN $LK_RELS <> 0 THEN 'a couple was made with someone who left'
               ELSE 'ok' END;" serialised

run "the asker's path change while the second Yes runs: both land, linked on the Relationship path" "$FX_LINK" \
  "SET race.sleep_users_update = '1.5:race.s1';
   INSERT INTO race.outcome SELECT 'lk_path', race.call(race.id('64'), 'SELECT public.set_my_path(''just_me'')') ->> 'tab';" \
  "SELECT pg_sleep(0.5);
   INSERT INTO race.outcome SELECT 'lk_overlap', (SELECT is_called FROM race.s1)::text;
   INSERT INTO race.outcome SELECT 'lk_yes', $LK_YES;" \
  "SELECT CASE WHEN (SELECT result FROM race.outcome WHERE name = 'lk_overlap') IS DISTINCT FROM 'true'
               THEN 'the second Yes did not run while the path change slept (no race)'
               WHEN (SELECT result FROM race.outcome WHERE name = 'lk_path') IS NULL
               THEN 'the path change answered nothing'
               WHEN (SELECT result::jsonb ->> 'ok' FROM race.outcome WHERE name = 'lk_yes') IS DISTINCT FROM 'true'
               THEN 'the second Yes answered ' || coalesce((SELECT result FROM race.outcome WHERE name = 'lk_yes'), '-')
               WHEN $LK_RELS <> 1 OR (SELECT path FROM public.users WHERE id = race.id('64')) IS DISTINCT FROM 'relationship'
               THEN 'not linked on the Relationship path: ' || coalesce((SELECT path FROM public.users WHERE id = race.id('64')), '-')
               ELSE 'ok' END;"
````

Create `.superpowers/sdd/2026-11-23-spec2-w9/edit_race_T3.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W9 Task 3: three race cases for the second Yes (race_T3.sh), the
# couple link's table and users in the delay list, and the clean-up that
# removes the race people's relationships and turns the link's flag off.
# Exact edits.
import pathlib, runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-23-spec2-w9/anchor.py')['edit']
cases = pathlib.Path('.superpowers/sdd/2026-11-23-spec2-w9/race_T3.sh').read_text()
edit('scripts/concurrency/dating_kill_switch_races.sh', [
    ("""                           'dating_session_context'] LOOP -- Spec 2 W8b (Task 4 fix round 1, M-5): a device check that sleeps
""", """                           'dating_session_context', -- Spec 2 W8b (Task 4 fix round 1, M-5): a device check that sleeps
                           'dating_couple_link_requests', 'users'] LOOP -- Spec 2 W9: a second Yes, a path change that sleeps
"""),
    ("""$P -c "SELECT race.reset(); UPDATE public.feature_flags SET enabled = false WHERE key IN ('dating_candidate_generation', 'dating_traveller_detection');" > /dev/null 2>&1 # Spec 2 W8b: and the traveller flag
""", cases + """$P -c "SELECT race.reset(); DELETE FROM public.relationships WHERE user_a::text LIKE '5e2f%' OR user_b::text LIKE '5e2f%'; UPDATE public.feature_flags SET enabled = false WHERE key IN ('dating_candidate_generation', 'dating_traveller_detection', 'dating_couple_link');" > /dev/null 2>&1 # Spec 2 W8b: and the traveller flag; Spec 2 W9: the couple link's
"""),
], 'T3 races')
````

```bash
D=.superpowers/sdd/2026-11-23-spec2-w9
python3 -I $D/edit_race_T3.py
uptime
R=w9race_t3; dropdb --if-exists $R 2>/dev/null; createdb $R
pg_dump -s attune_spec3a | psql -X -q -d $R > /dev/null 2>&1
pg_dump -a -t public.metric_key_prefixes -t public.feature_flags -t public.country_safety_config -t private.dating_calling_codes \
  -t private.dating_phone_trunk_rules -t private.flag_production_gates -t public.dating_algorithm_configs \
  -t public.dating_safety_configs attune_spec3a | psql -X -q -d $R > /dev/null 2>&1
bash scripts/concurrency/dating_kill_switch_races.sh $R > $D/race-T3.txt 2>&1
echo "RACES $(grep -c '^PASS' $D/race-T3.txt) PASS, $(grep -c '^FAIL' $D/race-T3.txt) FAIL"; tail -3 $D/race-T3.txt
dropdb $R
```

Expected: `…dating_kill_switch_races.sh: 2 edit(s) (T3 races)`; `RACES 61 PASS, 0 FAIL`; the last three lines `PASS  the asker takes it back while the second Yes sleeps: linked, one couple, no deadlock …`, `PASS  the asker leaves Dating while the second Yes waits: closed, no couple, no deadlock …`, `PASS  the asker's path change while the second Yes runs: both land, linked on the Relationship path (deadlocks detected and retried: 1)` (Spec 1's path change holds the users row, the second Yes holds the setup locks; one is retried inside itself; no caller sees an error).

- [ ] **Step 4: Record the tree (do not commit).**

### Task 4: `build-data-exports` writes `dating.json`; the TypeScript push guard counts `send-notification`; the W9a gate (§4.7, §7.3; S-4, I-13; carries 2, 7; R-W9-15)

**Files:**
- Create: `supabase/functions/build-data-exports/{dating_part.ts, dating_part.test.ts}`, `$D/{edit_export_T4.py, edit_deno_T4.py, mut_T4.py, gate.sh}`
- Modify: `supabase/functions/build-data-exports/parts.ts` (one import, one line), `supabase/functions/_architecture/push_queue_writers.test.ts`, `.github/workflows/tests.yml` (the CI line)
- Test: `dating_part.test.ts`, `push_queue_writers.test.ts`

**Interfaces:**
- Consumes: Task 2's `dating_export_for_job(p_job_id)`.
- Produces: `addDatingPart(supabase, jobId, zip): Promise<boolean>`.

- [ ] **Step 1: The dating part and its tests**

Create `supabase/functions/build-data-exports/dating_part.ts` with exactly:

````typescript
// supabase/functions/build-data-exports/dating_part.ts
//
// Spec 2 W9 (§4.7, S-4, I-13): the export's own-data Dating part. One
// added step in the data phase: dating_export_for_job, with the job being
// built and nothing else (no user id: the database takes the person from
// the job, refuses a job that isn't building and allows three reads a
// job). Its answer is written as dating.json; no Dating data, no file.
// The existing parts are unchanged.

/** The one thing this needs of the part's zip. */
export type DatingZip = { add(name: string, bytes: Uint8Array): void };

/** Adds dating.json for [jobId]; false when the person has no Dating data. */
// deno-lint-ignore no-explicit-any
export async function addDatingPart(supabase: any, jobId: string, zip: DatingZip): Promise<boolean> {
  const { data, error } = await supabase.rpc("dating_export_for_job", { p_job_id: jobId });
  if (error) throw error;
  if (data === null || data === undefined) return false;
  zip.add("dating.json", new TextEncoder().encode(JSON.stringify(data)));
  return true;
}
````

Create `supabase/functions/build-data-exports/dating_part.test.ts` with exactly:

````typescript
// Spec 2 W9 (§7.3, S-4, I-13): the dating part comes only from
// dating_export_for_job with the job being built; nothing else is asked.
import { assert, assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { addDatingPart } from "./dating_part.ts";

type Call = { fn: string; params: Record<string, unknown> };

function fake(answer: { data?: unknown; error?: unknown }) {
  const calls: Call[] = [];
  const files: Record<string, Uint8Array> = {};
  const client = {
    rpc: (fn: string, params: Record<string, unknown> = {}) => {
      calls.push({ fn, params });
      return Promise.resolve({ data: answer.data ?? null, error: answer.error ?? null });
    },
  };
  const zip = { add: (name: string, bytes: Uint8Array) => (files[name] = bytes) };
  return { client, calls, files, zip };
}

Deno.test("dating.json is the job's own call, by the job id alone", async () => {
  const part = { format: "attune-dating-export", conversations: [{ name: "conversation-1", my_messages: [] }] };
  const { client, calls, files, zip } = fake({ data: part });
  assertEquals(await addDatingPart(client, "job-7", zip), true);
  assertEquals(calls, [{ fn: "dating_export_for_job", params: { p_job_id: "job-7" } }]);
  assertEquals(Object.keys(files), ["dating.json"]);
  assertEquals(JSON.parse(new TextDecoder().decode(files["dating.json"])), part);
});

Deno.test("no Dating data: no file", async () => {
  const { client, files, zip } = fake({ data: null });
  assertEquals(await addDatingPart(client, "job-8", zip), false);
  assertEquals(Object.keys(files), []);
});

Deno.test("a refusal fails the part (the worker retries it; nothing is written)", async () => {
  const { client, files, zip } = fake({ error: { message: "export:not_building" } });
  await assertRejects(() => addDatingPart(client, "job-9", zip));
  assertEquals(Object.keys(files), []);
});

Deno.test("the data phase adds the part after the bundle, and never names a user id", async () => {
  const src = await Deno.readTextFile(new URL("./parts.ts", import.meta.url));
  const bundle = src.indexOf('rpc("export_bundle"');
  const dating = src.indexOf("addDatingPart(supabase, job.id, zip)");
  assert(bundle > -1 && dating > bundle, "export_bundle, then the dating part");
  assert(dating < src.indexOf('if (job.phase === "chat")'), "in the data phase");
  const part = await Deno.readTextFile(new URL("./dating_part.ts", import.meta.url));
  assert(!/user_id|p_user/.test(part.replace(/\/\/.*$/gm, "")), "no user id is sent");
});
````

Create `.superpowers/sdd/2026-11-23-spec2-w9/edit_export_T4.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W9 Task 4 (§4.7, S-4, I-13): build-data-exports' data phase adds
# the own-data Dating part after the bundle, by the job alone; the other
# parts are unchanged. Exact edit.
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-23-spec2-w9/anchor.py')['edit']
edit('supabase/functions/build-data-exports/parts.ts', [
    ('''} from "./bundle.ts";
''', '''} from "./bundle.ts";
import { addDatingPart } from "./dating_part.ts";
'''),
    ('''    zip.add("README.txt", enc.encode(readme(bundle)));
    return { next: { ...fresh, phase: rels.length > 0 ? "chat" : "media", rel_index: 1 }, leftOut };''',
     '''    zip.add("README.txt", enc.encode(readme(bundle)));
    // Spec 2 W9 (S-4, I-13): the own-data Dating part, by the job alone.
    await addDatingPart(supabase, job.id, zip);
    return { next: { ...fresh, phase: rels.length > 0 ? "chat" : "media", rel_index: 1 }, leftOut };'''),
], 'T4 export data phase')
````

Create `.superpowers/sdd/2026-11-23-spec2-w9/edit_deno_T4.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W9 Task 4 (carry 2): the TypeScript push guard also counts a call
# to the send-notification function (functions.invoke or its URL) as
# sending a push; its one caller, send-checkin-reminders, is listed. CI runs
# the export's dating part tests under the frozen lock (no new module).
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-23-spec2-w9/anchor.py')['edit']
G = 'supabase/functions/_architecture/push_queue_writers.test.ts'
edit(G, [
    ("""// names a queue table, uses the shared enqueuePush helper (or imports its
// module), or reaches OneSignal. The list is exact both ways: a listed""",
     """// names a queue table, uses the shared enqueuePush helper (or imports its
// module), reaches OneSignal, or (Spec 2 W9, carry 2) calls the
// send-notification function (functions.invoke or its URL). The list is
// exact both ways: a listed"""),
    ("""  "generate-verdict/index.ts": ["verdict_notification_outbox"],
};""", """  "generate-verdict/index.ts": ["verdict_notification_outbox"],
  // Spec 2 W9 (carry 2): the check-in reminders call send-notification.
  "send-checkin-reminders/index.ts": ["sendNotification"],
};"""),
    ("""/** What a file's code touches: queue tables, the queue helper, OneSignal. */""",
     """/** What a file's code touches: queue tables, the queue helper, OneSignal,
 * the send-notification function (Spec 2 W9). */"""),
    ("""    found.add("onesignal");
  }
  return [...found].sort();""", """    found.add("onesignal");
  }
  if (/\\.invoke\\(\\s*["'`]send-notification["'`]/.test(code) || /functions\\/v1\\/send-notification/.test(code)) {
    found.add("sendNotification");
  }
  return [...found].sort();"""),
    ("""  assertEquals(touches(`const idx = "in_app_notifications_chat_outbox_idx";`), []);
});""", """  assertEquals(touches(`const idx = "in_app_notifications_chat_outbox_idx";`), []);
  // Spec 2 W9 (carry 2): calling send-notification sends a push.
  assertEquals(touches(`await supabase.functions.invoke('send-notification', { body })`), ["sendNotification"]);
  assertEquals(touches("await db.functions.invoke(`send-notification`, {})"), ["sendNotification"]);
  assertEquals(touches(`await fetch(url + "/functions/v1/send-notification", {})`), ["sendNotification"]);
  assertEquals(touches(`// functions.invoke('send-notification') is not called here`), []);
});"""),
], 'T4 push guard (carry 2)')
edit('.github/workflows/tests.yml', [
    (""" dating-device-check/handler.test.ts _architecture/push_queue_writers.test.ts
""", """ dating-device-check/handler.test.ts _architecture/push_queue_writers.test.ts build-data-exports/dating_part.test.ts
"""),
], 'T4 CI line')
````

```bash
D=.superpowers/sdd/2026-11-23-spec2-w9
python3 -I $D/edit_export_T4.py
python3 -I $D/edit_deno_T4.py
cd supabase/functions
eval "$(grep -m1 -oE 'deno test --allow-read [^"]*' ../../.github/workflows/tests.yml)" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^ok \||^FAILED' | tail -1
eval "$(grep -m1 -oE 'deno check --lock[^"]*' ../../.github/workflows/tests.yml)" > /dev/null 2>&1; echo "deno check exit=$?"
deno test --allow-read --allow-env --no-lock build-data-exports/ 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^ok \||^FAILED' | tail -1
```

Expected: `…parts.ts: 2 edit(s) (T4 export data phase)`, `…push_queue_writers.test.ts: 5 edit(s) (T4 push guard (carry 2))`, `.github/workflows/tests.yml: 1 edit(s) (T4 CI line)`; `ok | 283 passed | 0 failed (…)`; `deno check exit=0`; `ok | 26 passed | 0 failed (…)`.

- [ ] **Step 2: The Deno mutants**

Create `.superpowers/sdd/2026-11-23-spec2-w9/mut_T4.py` with exactly:

````python
# Spec 2 W9 Task 4: Deno mutants (denomut.py, in a private copy).
TESTS = ['build-data-exports/dating_part.test.ts', '_architecture/push_queue_writers.test.ts']
F = 'supabase/functions/build-data-exports/'
G = 'supabase/functions/_architecture/push_queue_writers.test.ts'
MUTS = {
    'part_skipped': (F + 'parts.ts', [("    await addDatingPart(supabase, job.id, zip);\n", "")]),
    'part_sends_user': (F + 'dating_part.ts', [('{ p_job_id: jobId }', '{ p_job_id: jobId, p_user_id: "u" }')]),
    'part_swallows_error': (F + 'dating_part.ts', [('  if (error) throw error;\n', '  if (error) return false;\n')]),
    'part_file_for_nothing': (F + 'dating_part.ts', [('  if (data === null || data === undefined) return false;\n', '')]),
    'part_wrong_name': (F + 'dating_part.ts', [('zip.add("dating.json"', 'zip.add("data.json"')]),
    'invoke_unseen': (G, [("""  if (/\\.invoke\\(\\s*["'`]send-notification["'`]/.test(code) || /functions\\/v1\\/send-notification/.test(code)) {""",
                           """  if (/functions\\/v1\\/send-notification/.test(code)) {""")]),
    'url_unseen': (G, [("""  if (/\\.invoke\\(\\s*["'`]send-notification["'`]/.test(code) || /functions\\/v1\\/send-notification/.test(code)) {""",
                        """  if (/\\.invoke\\(\\s*["'`]send-notification["'`]/.test(code)) {""")]),
    'caller_unlisted': (G, [('  "send-checkin-reminders/index.ts": ["sendNotification"],\n', '')]),
}
````

```bash
D=.superpowers/sdd/2026-11-23-spec2-w9
python3 -I $D/denomut.py $D/mut_T4.py | tee $D/mut_T4.txt | tail -1
```

Expected: `8/8 killed`.

- [ ] **Step 3: The W9a gate (wait for an idle machine for the race script)**

Create `.superpowers/sdd/2026-11-23-spec2-w9/gate.sh` with exactly:

````bash
#!/bin/bash
# Spec 2 W9 batch gate. usage (repo root): gate.sh <W9a|W9b> [db]
# db defaults to attune_spec3a (the replay passes its clone). Writes
# $D/gate-<batch>.txt, one line per check. Both batches run the race script
# on an idle scratch database built from <db> (dropped after).
B=$1; DB=${2:-attune_spec3a}
D=.superpowers/sdd/2026-11-23-spec2-w9
O=$D/gate-$B.txt; : > $O
[ "$(psql -X -d "$DB" -Atc 'select current_database()')" = "$DB" ] || { echo "no database $DB" >> $O; exit 1; }
H=$(date -u +%H)
$D/suite.sh "$DB" > $D/sql-$B.txt
echo "SQL $(grep -c '^PASS' $D/sql-$B.txt) PASS, $(grep -c '^FAIL' $D/sql-$B.txt) FAIL" >> $O
echo "SQL-NEW-FAILS: $(comm -13 <(grep FAIL $D/sql-baseline.txt | sort) <(grep FAIL $D/sql-$B.txt | sort) | tr '\n' ' ')" >> $O
# quiet_hours_contracts.sql reads the real clock and fails when the suite
# starts between 22:00 and 08:00 UTC (W8 R-T3-5; not W9's).
if (( 10#$H >= 22 || 10#$H < 8 )); then
  echo "SQL-NOTE: suite run at ${H}h UTC (22:00-08:00): a quiet_hours_contracts.sql FAIL is the real clock; re-run it by day" >> $O
fi
echo "LINK $(psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -f supabase/tests/dating_v2_link_contracts.sql 2>&1 | grep -oE 'all held|CONTRACT VIOLATED.*' | head -1)" >> $O
echo "DEVICE $(psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -f supabase/tests/dating_v2_device_contracts.sql 2>&1 | grep -oE 'all held|CONTRACT VIOLATED.*' | head -1)" >> $O
(cd supabase/functions && eval "$(grep -m1 -oE 'deno test --allow-read [^"]*' ../../.github/workflows/tests.yml)" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^ok \||^FAILED' | tail -1) | sed 's/^/DENO /' >> $O
(cd supabase/functions && eval "$(grep -m1 -oE 'deno check --lock[^"]*' ../../.github/workflows/tests.yml)" > /dev/null 2>&1; echo "DENO-CHECK exit=$?") >> $O
# The export's own tests use a module the frozen lock does not hold (they
# are not in CI); run from the cache with no lock.
(cd supabase/functions && deno test --allow-read --allow-env --no-lock build-data-exports/ 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^ok \||^FAILED' | tail -1) | sed 's/^/DENO-EXPORTS /' >> $O
flutter analyze --no-pub lib test > $D/analyze-$B.txt 2>&1; echo "ANALYZE $(tail -1 $D/analyze-$B.txt)" >> $O
echo "W10SHA $(shasum -c .superpowers/sdd/2026-11-04-spec1-w10-accessibility-docs/w10-1.0.sha | grep -vc ': OK$')" >> $O
echo "W9SHA $(shasum -c .superpowers/sdd/2026-11-04-spec1-w9/flag_off.sha | grep -vc ': OK$')" >> $O
echo "LATCH $(shasum -c .superpowers/sdd/2026-11-07-spec2-w3/latch.sha)" >> $O
if [ -d test/features/dating/link ]; then
  echo "LARGETEXT $(python3 scripts/large_text_audit.py --scale 2.0 test/features/dating/link 2>&1 | tail -1)" >> $O
  # The audit draws the 1.0 goldens at 2.0; their diagnostics are not results.
  rm -rf test/features/dating/link/failures
fi
flutter test --no-pub test/architecture/games_untouched_test.dart 2>&1 | tr '\r' '\n' | grep -oE 'All tests passed!|Some tests failed\.' | tail -1 | sed 's/^/GAMES /' >> $O
echo "FLAGS $(psql -X -d "$DB" -Atc "select count(*) || ' rows, ' || count(*) filter (where enabled) || ' on' from public.feature_flags")" >> $O
R=w9race_$$
dropdb --if-exists $R 2>/dev/null; createdb $R
pg_dump -s "$DB" | psql -X -q -d $R > /dev/null 2>&1
pg_dump -a -t public.metric_key_prefixes -t public.feature_flags -t public.country_safety_config -t private.dating_calling_codes \
  -t private.dating_phone_trunk_rules -t private.flag_production_gates -t public.dating_algorithm_configs \
  -t public.dating_safety_configs "$DB" | psql -X -q -d $R > /dev/null 2>&1
echo "LOAD-BEFORE-RACES $(uptime | sed 's/.*load averages*: //')" >> $O
bash scripts/concurrency/dating_kill_switch_races.sh $R > $D/race-$B.txt 2>&1
echo "RACES $(grep -c '^PASS' $D/race-$B.txt) PASS, $(grep -c '^FAIL' $D/race-$B.txt) FAIL" >> $O
dropdb $R
flutter test --no-pub --reporter compact > $D/flutter-$B.txt 2>&1
echo "FLUTTER $(tr '\r' '\n' < $D/flutter-$B.txt | grep -E '^[0-9:]+ \+[0-9]+' | tail -1 | grep -oE '\+[0-9]+( ~[0-9]+)?( -[0-9]+)?: (All tests passed!|Some tests failed\.)')" >> $O
echo "FLUTTER-FAILS:" >> $O
tr '\r' '\n' < $D/flutter-$B.txt | grep -E '\[E\][[:space:]]*$' | sed -E 's/^[0-9:]+ \+[0-9]+( ~[0-9]+)?( -[0-9]+)?: //; s#.*/test/#test/#; s/ \[E\][[:space:]]*$//' | sort -u | sed 's/^/  /' >> $O
echo DONE >> $O
cat $O
````

```bash
D=.superpowers/sdd/2026-11-23-spec2-w9
chmod +x $D/gate.sh
uptime
bash $D/gate.sh W9a attune_spec3a
```

Expected (the replay's):

```text
SQL 164 PASS, 14 FAIL
SQL-NEW-FAILS:
LINK all held
DEVICE all held
DENO ok | 283 passed | 0 failed (8s)
DENO-CHECK exit=0
DENO-EXPORTS ok | 26 passed | 0 failed (432ms)
ANALYZE skipped (W9_GATE_SKIP_FLUTTER: Tasks 5-6 in flight; the W9b gate runs it)
W10SHA 0
W9SHA 0
LATCH lib/home/home_screen.dart: OK
LARGETEXT skipped (W9_GATE_SKIP_FLUTTER)
GAMES All tests passed!
FLAGS 46 rows, 6 on
RACES skipped here (W9_GATE_SKIP_RACES: run separately at load < 4; see below)
FLUTTER skipped (W9_GATE_SKIP_FLUTTER: Tasks 5-6 in flight; the W9b gate runs the full suite)
DONE
# race_gate_T4.sh (load < 4), then the four race mutants on the W9-only cases:
LOAD-BEFORE-RACES 16:16 2.81 7.48 9.21
RACES 62 PASS, 0 FAIL
MUT cancel_toctou: 1 FAIL (race 64) restore=0
MUT ignores_closed: 1 FAIL (race 65) restore=0
MUT no_retry: 1 FAIL (race 66) restore=0
MUT no_linked_replay: 1 FAIL (race 67) restore=0
W9-ONLY AFTER RESTORE 4 PASS, 0 FAIL
# gate_muts_T4.sh (SQL mutants, CONTRACT VIOLATED/all) and denomut.py:
T1 23/23  T2 22/22  T2b 1/1  T2c 6/6  T4b 3/3  T3 10/10  T3b 2/2  T3c 9/9  W8-T3 31/31  T4 8/8 killed
```

- [ ] **Step 4: Record the tree (do not commit).**

---

## Batch W9b — the app: the link, the Relationship home, About us

### Task 5: The chat's link and `/dating/link/:matchId` (§3.6, §3.9 steps 1–4, §3.14, §3.15, §7.4; carry 6; R-W9-2, R-W9-3, R-W9-5, R-W9-14)

**Files:**
- Create: `lib/features/dating/link/{dating_link.dart, link_screen.dart}`, `test/features/dating/support/dating_link_fakes.dart`, `test/features/dating/link/link_test.dart` and its goldens (`test/features/dating/link/goldens/dating_link_{ask,answer,moment}.{scale1.0,scale1.3,scale2.0,rtl}.png`), `$D/{edit_app_T5.py, arb_fragment_T5.txt, edit_tests_T5.py, mut_T5_dart.py}`
- Modify: `lib/features/dating/chat/{dating_chat.dart, chat_sheets.dart, dating_chat_screen.dart}`, `lib/features/dating/routes/dating_routes.dart`, `lib/features/dating/domain/services/dating_feature_flags.dart`, `lib/app/documentations/user_manual/data/documentation_flags.dart` (shared: R-W9-16), `lib/i10n/app_en.arb` + generated, `test/features/dating/support/dating_shell.dart`, `test/architecture/text_scale_routes_test.dart`, `test/app/documentations/documentation_registry_flags_test.dart`
- As built (R-W9-16 as built): `documentation_flags.dart` and `documentation_registry_flags_test.dart` stay HEAD's; created instead `lib/core/flags/couple_link_flag.dart` and `test/features/dating/link/couple_link_flag_test.dart`; Task 7 adds one assert to `test/architecture/dating_device_header_test.dart` naming the flag read as the one non-Dating client.
- Test: `link_test.dart`

**Interfaces:**
- Consumes: Task 1's RPCs and the header's `link`; Task 2's origin, How we met and offer RPCs (the gateway carries all of them).
- Produces: see "Interfaces this plan produces" (App); Task 6 uses `datingLinkGatewayProvider`, `datingPostLinkOfferProvider`, `datingLinkOriginProvider`, `datingHowWeMetProvider`, `DatingLinkMoment`, `datingGoToCouple`, `FakeDatingLink`, `datingLinkOverrides`, and every W9 string.

- [ ] **Step 1: The models, the gateway and the page**

Create `lib/features/dating/link/dating_link.dart` with exactly:

````dart
// Spec 2 W9 (§3.9, §4.4; S-5, S-6, I-12, C-4): "Become a couple on Attune"
// as the server sends it, and its calls. The chat side (the link page's
// read, asking, the second Yes, Not right now, taking it back) goes
// through the Dating RPC client with this phone's "Show it on this phone
// anyway" (R-T5-1), as every Dating read. The couple side (the match date
// for About us, How we met, the Relationship home's card) is read by the
// relationship's members only. Every field is read defensively; a server's
// text is never shown; memory only (D20).
import 'package:attune/app/documentations/user_manual/data/documentation_flags.dart'
    show documentationFlagsProvider;
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/device/trip_phone.dart';
import 'package:attune/features/dating/domain/services/dating_feature_flags.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The couple link's fixed refusals (any other answer is `failed`).
const datingLinkReasons = {
  'invalid',
  'unavailable',
  'reverify_device',
  'match_unavailable',
  'request_unavailable',
  'closed',
  'not_yet',
  'not_ready',
  'asked',
  'asked_you',
  'linked',
  'busy',
};

String _fixed(Object? reason) =>
    reason is String && datingLinkReasons.contains(reason) ? reason : 'failed';

/// What the chat shows of the link, for this side (the server's `link`).
enum DatingLinkState {
  /// Either has said We met: this side may ask.
  none,

  /// This side asked; waiting for the other.
  asked,

  /// The other side asked: the card and the sheet.
  askedYou,

  /// The other side said Not right now to this side's request (14 days).
  notReady,

  /// The couple linked (this conversation ended with it).
  linked,
}

class DatingLink {
  const DatingLink({required this.state, this.requestId, this.moment = false});

  final DatingLinkState state;
  final String? requestId;

  /// [DatingLinkState.linked]: "You decided together." is still to show.
  final bool moment;

  static DatingLink? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final state = switch (raw['state']) {
      'none' => DatingLinkState.none,
      'asked' => DatingLinkState.asked,
      'asked_you' => DatingLinkState.askedYou,
      'not_ready' => DatingLinkState.notReady,
      'linked' => DatingLinkState.linked,
      _ => null,
    };
    if (state == null) return null;
    final id = raw['request_id'];
    final requestId = id is String ? id : null;
    if ((state == DatingLinkState.asked || state == DatingLinkState.askedYou) &&
        requestId == null) {
      return null;
    }
    return DatingLink(
      state: state,
      requestId: requestId,
      moment: raw['moment'] == true,
    );
  }
}

/// The link page's read: the other person's first name and the link.
class DatingLinkPage {
  const DatingLinkPage({
    this.ok = false,
    this.reason,
    this.displayName = '',
    this.link,
  });

  static const failed = DatingLinkPage(reason: 'failed');
  static const busy = DatingLinkPage(reason: 'busy');

  final bool ok;
  final String? reason;
  final String displayName;
  final DatingLink? link;

  factory DatingLinkPage.fromJson(Object? raw) {
    if (raw is! Map) return failed;
    if (raw['ok'] != true) return DatingLinkPage(reason: _fixed(raw['reason']));
    final name = raw['display_name'];
    return DatingLinkPage(
      ok: true,
      displayName: name is String ? name.trim() : '',
      link: DatingLink.fromJson(raw['link']),
    );
  }
}

/// An answer of asking, the second Yes, Not right now or taking it back.
class DatingLinkAnswer {
  const DatingLinkAnswer({
    required this.ok,
    this.reason,
    this.requestId,
    this.relationshipId,
  });

  static const failed = DatingLinkAnswer(ok: false, reason: 'failed');
  static const busy = DatingLinkAnswer(ok: false, reason: 'busy');

  final bool ok;
  final String? reason;
  final String? requestId;
  final String? relationshipId;

  factory DatingLinkAnswer.fromJson(Object? raw) {
    if (raw is! Map) return failed;
    if (raw['ok'] != true) {
      return DatingLinkAnswer(ok: false, reason: _fixed(raw['reason']));
    }
    String? text(String key) => raw[key] is String ? raw[key] as String : null;
    return DatingLinkAnswer(
      ok: true,
      requestId: text('request_id'),
      relationshipId: text('relationship_id'),
    );
  }
}

/// What the Relationship home's `link_offer` card shows (C-4).
enum DatingPostLinkOffer {
  none,

  /// "You decided together.", once.
  linked,

  /// "Delete your Dating profile and preferences?", from 30 days on.
  delete,
}

/// One message of the How we met card, as both saw it.
class DatingHowWeMetItem {
  const DatingHowWeMetItem({
    required this.mine,
    required this.text,
    required this.at,
    this.questionId,
  });

  final bool mine;
  final String text;
  final DateTime at;
  final String? questionId;

  static DatingHowWeMetItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final text = raw['text'];
    final at =
        raw['at'] is String ? DateTime.tryParse(raw['at'] as String) : null;
    if (text is! String || at == null) return null;
    final q = raw['question_id'];
    return DatingHowWeMetItem(
      mine: raw['mine'] == true,
      text: text,
      at: at.toUtc(),
      questionId: q is String ? q : null,
    );
  }
}

abstract class DatingLinkGateway {
  /// The link page's read of [matchId].
  Future<DatingLinkPage> page(String matchId);

  /// Step 1: this side's Yes ("Ask {Name}").
  Future<DatingLinkAnswer> ask(
    String key,
    String matchId, {
    required bool keep,
  });

  /// Step 3: the second Yes ("Yes, let's").
  Future<DatingLinkAnswer> confirm(
    String key,
    String requestId, {
    required bool keep,
  });

  /// Step 2: "Not right now".
  Future<DatingLinkAnswer> decline(String requestId);

  /// The asker takes it back.
  Future<DatingLinkAnswer> cancel(String requestId);

  /// The match date for About us's chip; null when there is none.
  Future<DateTime?> origin(String relationshipId);

  /// How we met; null when there is no card (or it can't be read).
  Future<List<DatingHowWeMetItem>?> howWeMet(String relationshipId);

  /// The Relationship home's card for the signed-in person.
  Future<DatingPostLinkOffer> offer();

  /// The card answered: [offer] 'linked' (seen) or 'delete' (Keep for now).
  Future<bool> dismiss(DatingPostLinkOffer offer);
}

class DatingLinkRepository implements DatingLinkGateway {
  DatingLinkRepository(this._rpc, {Future<bool> Function()? showSameGender})
    : _showSameGender = showSameGender;

  final DatingRpc _rpc;

  /// This phone's "Show it on this phone anyway" for the signed-in account.
  final Future<bool> Function()? _showSameGender;

  Future<bool> _show() async {
    try {
      return await (_showSameGender?.call() ?? Future.value(false));
    } catch (_) {
      return false;
    }
  }

  Future<DatingLinkAnswer> _answer(
    String fn,
    Map<String, dynamic> params,
  ) async {
    try {
      return DatingLinkAnswer.fromJson(await _rpc.call(fn, params));
    } on DatingBusy {
      return DatingLinkAnswer.busy;
    } catch (_) {
      return DatingLinkAnswer.failed;
    }
  }

  @override
  Future<DatingLinkPage> page(String matchId) async {
    try {
      return DatingLinkPage.fromJson(
        await _rpc.call('get_dating_couple_link', {
          'p_match_id': matchId,
          'p_show_same_gender': await _show(),
        }),
      );
    } on DatingBusy {
      return DatingLinkPage.busy;
    } catch (_) {
      return DatingLinkPage.failed;
    }
  }

  @override
  Future<DatingLinkAnswer> ask(
    String key,
    String matchId, {
    required bool keep,
  }) async => _answer('request_dating_couple_link', {
    'p_key': key,
    'p_match_id': matchId,
    'p_keep_messages': keep,
    'p_show_same_gender': await _show(),
  });

  @override
  Future<DatingLinkAnswer> confirm(
    String key,
    String requestId, {
    required bool keep,
  }) async => _answer('confirm_dating_couple_link', {
    'p_key': key,
    'p_request_id': requestId,
    'p_keep_messages': keep,
    'p_show_same_gender': await _show(),
  });

  @override
  Future<DatingLinkAnswer> decline(String requestId) =>
      _answer('decline_dating_couple_link', {'p_request_id': requestId});

  @override
  Future<DatingLinkAnswer> cancel(String requestId) =>
      _answer('cancel_dating_couple_link', {'p_request_id': requestId});

  @override
  Future<DateTime?> origin(String relationshipId) async {
    try {
      final r = await _rpc.call('get_dating_link_origin', {
        'p_relationship_id': relationshipId,
      });
      if (r is! Map || r['ok'] != true || r['matched_at'] is! String) {
        return null;
      }
      return DateTime.tryParse(r['matched_at'] as String)?.toUtc();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<DatingHowWeMetItem>?> howWeMet(String relationshipId) async {
    try {
      final r = await _rpc.call('get_how_we_met', {
        'p_relationship_id': relationshipId,
      });
      if (r is! Map || r['ok'] != true || r['items'] is! List) return null;
      final items = [
        for (final i in (r['items'] as List).map(DatingHowWeMetItem.fromJson))
          if (i != null) i,
      ];
      return items.isEmpty ? null : items;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<DatingPostLinkOffer> offer() async {
    try {
      final r = await _rpc.call('get_dating_post_link_offer', {});
      if (r is! Map || r['ok'] != true) return DatingPostLinkOffer.none;
      return switch (r['offer']) {
        'linked' => DatingPostLinkOffer.linked,
        'delete' => DatingPostLinkOffer.delete,
        _ => DatingPostLinkOffer.none,
      };
    } catch (_) {
      return DatingPostLinkOffer.none;
    }
  }

  @override
  Future<bool> dismiss(DatingPostLinkOffer offer) async {
    if (offer == DatingPostLinkOffer.none) return false;
    try {
      final r = await _rpc.call('dismiss_dating_post_link_offer', {
        'p_offer': offer == DatingPostLinkOffer.linked ? 'linked' : 'delete',
      });
      return r is Map && r['ok'] == true;
    } catch (_) {
      return false;
    }
  }
}

final datingLinkGatewayProvider = Provider<DatingLinkGateway>(
  (ref) => DatingLinkRepository(
    ref.watch(datingRpcProvider),
    // The account signed in at each call (D8).
    showSameGender:
        () => DatingTripPhone.showFor(ref.read(datingAccountProvider)),
  ),
);

/// The controller's ruling (R-W9-16): whether this client already knows
/// dating_couple_link is on, from the Dating read the app makes once per
/// process for everyone (documentationFlagsProvider: get_dating_home, re-read
/// on resume). Not known, or off: nothing below asks the server anything.
final datingCoupleLinkOnProvider = Provider.autoDispose<bool>(
  (ref) =>
      ref
          .watch(documentationFlagsProvider)
          .valueOrNull
          ?.contains(DatingFeatureFlags.coupleLink) ??
      false,
);

/// The Relationship home's card for [account] (null: signed out, none).
final datingPostLinkOfferProvider = FutureProvider.autoDispose
    .family<DatingPostLinkOffer, String?>((ref, account) async {
      if (account == null || !ref.watch(datingCoupleLinkOnProvider)) {
        return DatingPostLinkOffer.none;
      }
      return ref.read(datingLinkGatewayProvider).offer();
    });

/// The match date of [relationshipId], read by a member (I-12).
final datingLinkOriginProvider = FutureProvider.autoDispose
    .family<DateTime?, (String?, String)>((ref, key) async {
      if (key.$1 == null || !ref.watch(datingCoupleLinkOnProvider)) {
        return null;
      }
      return ref.read(datingLinkGatewayProvider).origin(key.$2);
    });

/// How we met of [relationshipId], read by a member.
final datingHowWeMetProvider = FutureProvider.autoDispose
    .family<List<DatingHowWeMetItem>?, (String?, String)>((ref, key) async {
      if (key.$1 == null || !ref.watch(datingCoupleLinkOnProvider)) {
        return null;
      }
      return ref.read(datingLinkGatewayProvider).howWeMet(key.$2);
    });
````

Create `lib/features/dating/link/link_screen.dart` with exactly:

````dart
// Spec 2 W9 (§3.9 steps 1-4, §3.14 /dating/link/:matchId, §3.15; D8):
// "Become a couple on Attune". The private "What are we agreeing to?"
// page, read in full before its buttons: for the asker [Ask {Name}]
// [Not now] with "Keep our first messages"; for the other side, after
// "{Name} would like to become a couple on Attune.", [Yes, let's]
// [Not right now] with their own "Keep our first messages". After the
// second Yes, "You decided together." with the one settle (at most 600
// ms, once; a fade under reduce motion), then the Relationship home. The
// asker sees the same moment once (here, in the chat, or on the
// Relationship home's card). Nothing else moves. Offline nothing is
// sent ("You're offline. Nothing has changed yet." for the second Yes);
// busy and failures are calm lines; another account on the phone sees
// nothing of the last one's; nothing is done once quick exit or sign-out
// has run (W8a).
import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/link/dating_link.dart';
import 'package:attune/features/dating/lock/dating_sheets.dart'
    show datingSheetRefused;
import 'package:attune/features/dating/routes/dating_root_back.dart';
import 'package:attune/features/dating/routes/dating_routes.dart'
    show DatingPaths;
import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/features/dating/verify/dating_reverify_line.dart';
import 'package:attune/features/onboarding/domain/home_state.dart' show AppTab;
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart'
    show homeStateProvider;
import 'package:attune/home/home_location.dart';
import 'package:attune/home/home_screen.dart' show relationshipModeResyncSignal;
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// §3.15: the one settle on "You decided together.", at most 600 ms.
const kDatingLinkSettle = Duration(milliseconds: 600);

/// [name], or "this person" when the server has none.
String datingLinkName(AppLocalizations loc, String name) =>
    name.isEmpty ? loc.dating_cardThisPerson : name;

/// After the couple linked: Spec 1's home reads the new path, then the
/// Relationship home.
Future<void> datingGoToCouple(BuildContext context, WidgetRef ref) async {
  final account = ref.read(datingAccountProvider);
  if (account != null) {
    unawaited(ref.read(homeStateProvider(account).notifier).refresh());
  }
  relationshipModeResyncSignal.value++;
  if (context.mounted) context.go(homeLocation(tab: AppTab.chat));
}

/// "You decided together.": one settle, at most 600 ms, once (a fade under
/// reduce motion), announced; [onContinue] goes on.
class DatingLinkMoment extends StatefulWidget {
  const DatingLinkMoment({super.key, required this.onContinue, this.body});

  final VoidCallback? onContinue;
  final String? body;

  @override
  State<DatingLinkMoment> createState() => _DatingLinkMomentState();
}

class _DatingLinkMomentState extends State<DatingLinkMoment>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: kDatingLinkSettle,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotionOf(context)) {
      _settle.duration = const Duration(milliseconds: 150);
    }
    _settle.forward();
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final still = reduceMotionOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedBuilder(
          animation: _settle,
          builder: (context, child) {
            final t = Curves.easeOutCubic.transform(_settle.value);
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, still ? 0 : 12 * (1 - t)),
                child: child,
              ),
            );
          },
          child: Semantics(
            liveRegion: true,
            header: true,
            child: Text(
              loc.dating_linkDecided,
              key: const ValueKey('dating_link_decided'),
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
        if (widget.body != null) ...[
          const SizedBox(height: Spacing.sm),
          Text(
            widget.body!,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: Spacing.lg),
        FlowPrimaryButton(
          key: const ValueKey('dating_link_continue'),
          label: loc.flow_continue,
          onPressed: widget.onContinue,
        ),
      ],
    );
  }
}

/// §3.14 /dating/link/:matchId.
class DatingLinkScreen extends ConsumerStatefulWidget {
  const DatingLinkScreen({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<DatingLinkScreen> createState() => _DatingLinkScreenState();
}

enum _LinkBusy { ask, yes, no, back }

class _DatingLinkScreenState extends ConsumerState<DatingLinkScreen> {
  final _keys = DatingActionKeys();
  DatingLinkPage? _page;
  String? _account;
  bool _keep = false;
  _LinkBusy? _busy;
  String? _error;

  /// The second Yes landed here: the moment, then the Relationship home.
  bool _decided = false;

  @override
  void initState() {
    super.initState();
    _account = ref.read(datingAccountProvider);
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (previous == next || !mounted) return;
      // D8: another account sees nothing of the last one's.
      setState(() {
        _account = next;
        _page = null;
        _keep = false;
        _busy = null;
        _error = null;
        _decided = false;
      });
      _keys.clear();
      unawaited(_read());
    });
    unawaited(_read());
  }

  Future<void> _read() async {
    final account = _account;
    if (account == null) return;
    final page = await ref.read(datingLinkGatewayProvider).page(widget.matchId);
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    setState(() => _page = page);
  }

  /// Back to the chat (as the only page, the chat itself).
  void _back() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go(DatingPaths.chat(widget.matchId));
    }
  }

  Future<void> _run(
    _LinkBusy what,
    Future<DatingLinkAnswer> Function() call,
  ) async {
    // W8a: nothing is done under quick exit's decoy.
    if (_busy != null || datingSheetRefused) return;
    final account = _account;
    if (account == null) return;
    setState(() {
      _busy = what;
      _error = null;
    });
    final r = await call();
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    setState(() {
      _busy = null;
      _error = r.ok ? null : r.reason;
    });
    if (!r.ok) {
      // A refusal that means the link moved on: read it again.
      if (const {
        'asked',
        'asked_you',
        'not_ready',
        'request_unavailable',
        'closed',
        'match_unavailable',
      }.contains(r.reason)) {
        unawaited(_read());
      }
      return;
    }
    switch (what) {
      case _LinkBusy.yes:
        setState(() => _decided = true);
      case _LinkBusy.ask:
        unawaited(_read());
      case _LinkBusy.no || _LinkBusy.back:
        _back();
    }
  }

  Widget _agreeing(AppLocalizations loc, String name, {required bool asker}) {
    final theme = Theme.of(context);
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final requestId = _page?.link?.requestId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!asker) ...[
          Text(
            loc.dating_linkAskedYou(name),
            key: const ValueKey('dating_link_asked_you'),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: Spacing.md),
        ],
        Semantics(
          header: true,
          child: Text(
            loc.dating_linkAgreeingTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          loc.dating_linkAgreeingBody,
          key: const ValueKey('dating_link_body'),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: Spacing.md),
        MergeSemantics(
          child: CheckboxListTile(
            key: const ValueKey('dating_link_keep'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _keep,
            onChanged:
                _busy == null
                    ? (v) => setState(() => _keep = v ?? false)
                    : null,
            title: Text(loc.dating_linkKeep(name)),
          ),
        ),
        const SizedBox(height: Spacing.md),
        if (!online)
          DatingCalmLine(asker ? loc.dating_offline : loc.dating_linkOffline),
        if (_error == 'busy') DatingCalmLine(loc.dating_busy),
        if (_error == 'reverify_device') const DatingReverifyLine(),
        if (_error == 'match_unavailable' ||
            _error == 'request_unavailable' ||
            _error == 'closed')
          DatingCalmLine(loc.dating_cardGone),
        if (_error == 'unavailable') DatingCalmLine(loc.dating_linkUnavailable),
        if (_error == 'failed' || _error == 'invalid')
          FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
        if (asker) ...[
          FlowPrimaryButton(
            key: const ValueKey('dating_link_ask'),
            label: loc.dating_linkAsk(name),
            busy: _busy == _LinkBusy.ask,
            onPressed:
                online && _busy == null
                    ? () => _run(
                      _LinkBusy.ask,
                      () => ref
                          .read(datingLinkGatewayProvider)
                          .ask(
                            _keys.keyFor('ask', [
                              _account,
                              widget.matchId,
                              _keep,
                            ]),
                            widget.matchId,
                            keep: _keep,
                          ),
                    )
                    : null,
          ),
          const SizedBox(height: Spacing.sm),
          FlowSecondaryButton(
            key: const ValueKey('dating_link_not_now'),
            label: loc.dating_linkNotNow,
            onPressed: _busy == null ? _back : null,
          ),
        ] else ...[
          FlowPrimaryButton(
            key: const ValueKey('dating_link_yes'),
            label: loc.dating_linkYes,
            busy: _busy == _LinkBusy.yes,
            onPressed:
                online && _busy == null && requestId != null
                    ? () => _run(
                      _LinkBusy.yes,
                      () => ref
                          .read(datingLinkGatewayProvider)
                          .confirm(
                            _keys.keyFor('yes', [_account, requestId, _keep]),
                            requestId,
                            keep: _keep,
                          ),
                    )
                    : null,
          ),
          const SizedBox(height: Spacing.sm),
          FlowSecondaryButton(
            key: const ValueKey('dating_link_not_right_now'),
            label: loc.dating_linkNotRightNow,
            busy: _busy == _LinkBusy.no,
            onPressed:
                online && _busy == null && requestId != null
                    ? () => _run(
                      _LinkBusy.no,
                      () => ref
                          .read(datingLinkGatewayProvider)
                          .decline(requestId),
                    )
                    : null,
          ),
        ],
      ],
    );
  }

  Widget _body(AppLocalizations loc) {
    final page = _page;
    if (_decided) {
      return DatingLinkMoment(onContinue: () => datingGoToCouple(context, ref));
    }
    if (page == null) return const SizedBox(height: 96);
    if (!page.ok) {
      return switch (page.reason) {
        'reverify_device' => const DatingReverifyLine(),
        'busy' => DatingCalmLine(loc.dating_busy),
        'failed' => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
            const SizedBox(height: Spacing.sm),
            FlowSecondaryButton(label: loc.dating_tryAgain, onPressed: _read),
          ],
        ),
        _ => DatingCalmLine(loc.dating_cardGone),
      };
    }
    final name = datingLinkName(loc, page.displayName);
    final link = page.link;
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    switch (link?.state) {
      case DatingLinkState.none:
        return _agreeing(loc, name, asker: true);
      case DatingLinkState.askedYou:
        return _agreeing(loc, name, asker: false);
      case DatingLinkState.asked:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DatingCalmLine(loc.dating_linkAsked(name)),
            const SizedBox(height: Spacing.md),
            if (_error == 'busy') DatingCalmLine(loc.dating_busy),
            if (_error == 'failed')
              FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
            FlowSecondaryButton(
              key: const ValueKey('dating_link_take_back'),
              label: loc.dating_linkTakeBack,
              busy: _busy == _LinkBusy.back,
              onPressed:
                  online && _busy == null && link?.requestId != null
                      ? () => _run(
                        _LinkBusy.back,
                        () => ref
                            .read(datingLinkGatewayProvider)
                            .cancel(link!.requestId!),
                      )
                      : null,
            ),
          ],
        );
      case DatingLinkState.notReady:
        return DatingCalmLine(loc.dating_linkNotReady(name));
      case DatingLinkState.linked:
        return DatingLinkMoment(
          onContinue: () async {
            unawaited(
              ref
                  .read(datingLinkGatewayProvider)
                  .dismiss(DatingPostLinkOffer.linked),
            );
            await datingGoToCouple(context, ref);
          },
        );
      case null:
        return DatingCalmLine(loc.dating_cardGone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return AllowLargeText(
      child: Scaffold(
        appBar: AppBar(
          leading: datingRootBackButton(context),
          title: Text(loc.dating_linkBecome),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.md),
            child: KeyedSubtree(key: ValueKey(_account), child: _body(loc)),
          ),
        ),
      ),
    );
  }
}
````

- [ ] **Step 2: The chat, the Safety sheet and the route; the strings**

Create `.superpowers/sdd/2026-11-23-spec2-w9/edit_app_T5.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W9 Task 5 (§3.9 steps 1-4, §3.14; carry 6): the chat's header
# carries the couple link; the Safety sheet offers "Become a couple on
# Attune" once either has said We met (theyMet wired: the other side's We
# met counts, as the server's link state says); the chat's top card shows
# the other side's request, the asker's own, "{Name} isn't ready yet." and
# "You decided together."; /dating/link/:matchId is the link page.
# Formatter-style edits (W6-W8 files, never formatted).
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-23-spec2-w9/anchor.py')['edit']

edit('lib/features/dating/chat/dating_chat.dart', [
    ("""// have swapped. Memory only (D20): nothing here is written to disk.
""", """// have swapped. Memory only (D20): nothing here is written to disk.
import 'package:attune/features/dating/link/dating_link.dart';
"""),
    ("""    this.theyMet = false,
    this.timebox,
  });""", """    this.theyMet = false,
    this.timebox,
    this.link,
  });"""),
    ("""  /// 'day21'), never a date.
  final String? timebox;
""", """  /// 'day21'), never a date.
  final String? timebox;

  /// Spec 2 W9 (§3.9): the couple link as this side sees it (null: none to
  /// show, and Become a couple not offered).
  final DatingLink? link;
"""),
    ("""              ? raw['timebox'] as String
              : null,
    );""", """              ? raw['timebox'] as String
              : null,
      link: DatingLink.fromJson(raw['link']),
    );"""),
], 'T5 header link')

edit('lib/features/dating/chat/chat_sheets.dart', [
    ("""  weMet,
  planMeet,
}""", """  weMet,
  planMeet,
  // Spec 2 W9 (§3.9): Become a couple on Attune.
  becomeCouple,
}"""),
    ("""  bool weMet = false,
  bool blocked = false,
}) => _show<DatingSafetyChoice>(context, 'chat-safety', account, (""",
     """  bool weMet = false,
  bool blocked = false,
  // Spec 2 W9 (§3.9): either has said We met and nothing is asked yet.
  bool canLink = false,
}) => _show<DatingSafetyChoice>(context, 'chat-safety', account, ("""),
    ("""    if (!ended && !weMet)
      row(loc.dating_weMet, Icons.handshake_outlined, DatingSafetyChoice.weMet),
  ]);""", """    if (!ended && !weMet)
      row(loc.dating_weMet, Icons.handshake_outlined, DatingSafetyChoice.weMet),
    // Spec 2 W9 (§3.6, §3.9): once either has tapped We met.
    if (!ended && canLink)
      row(
        loc.dating_linkBecome,
        Icons.favorite_border,
        DatingSafetyChoice.becomeCouple,
      ),
  ]);"""),
], 'T5 Safety sheet')

edit('lib/features/dating/chat/dating_chat_screen.dart', [
    ("""import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
""", """import 'package:attune/features/dating/link/dating_link.dart';
import 'package:attune/features/dating/link/link_screen.dart'
    show DatingLinkMoment, datingGoToCouple;
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
"""),
    ("""      weMet: header.weMet,
      // M-7: just blocked here: Block is not offered again.
      blocked: _blockedName != null,
    );""", """      weMet: header.weMet,
      // M-7: just blocked here: Block is not offered again.
      blocked: _blockedName != null,
      // Spec 2 W9 (§3.9; carry 6): either side's We met, nothing asked yet.
      canLink:
          (header.weMet || header.theyMet) &&
          header.link?.state == DatingLinkState.none,
    );"""),
    ("""        // Fix round 1: "Noted that you met." (never whether they're told).
        _say(r.ok ? 'we_met' : r.reason);
        unawaited(_read());
    }
  }
""", """        // Fix round 1: "Noted that you met." (never whether they're told).
        _say(r.ok ? 'we_met' : r.reason);
        unawaited(_read());
      case DatingSafetyChoice.becomeCouple:
        await _openLink();
    }
  }

  /// Spec 2 W9 (§3.9): the link page; the chat reads again on return.
  Future<void> _openLink() async {
    await context.push(DatingPaths.link(widget.matchId));
    if (mounted) unawaited(_read());
  }

  /// Spec 2 W9: the asker takes the request back (from the top card).
  Future<void> _takeBack(String requestId) async {
    final account = _account;
    if (!_online) {
      _say('offline');
      return;
    }
    final r = await ref.read(datingLinkGatewayProvider).cancel(requestId);
    if (!mounted || _account != account) return;
    _say(r.ok ? null : r.reason);
    unawaited(_read());
  }
"""),
    ("""    final out = <Widget>[];
    final pendingBoxes =""", """    final out = <Widget>[];
    // Spec 2 W9 (§3.9 steps 2-4): the couple link, above everything else.
    final link = h.link;
    switch (link?.state) {
      case DatingLinkState.askedYou:
        out.add(
          card('link:asked_you', 'dating_link_card', [
            title(loc.dating_linkAskedYou(name)),
            actions([
              button('dating_link_see', loc.dating_linkSee, () => unawaited(_openLink())),
            ]),
          ]),
        );
      case DatingLinkState.asked:
        out.add(
          card('link:asked', 'dating_link_card', [
            title(loc.dating_linkAsked(name)),
            actions([
              button(
                'dating_link_take_back',
                loc.dating_linkTakeBack,
                () => unawaited(_takeBack(link!.requestId!)),
              ),
            ]),
          ]),
        );
      case DatingLinkState.notReady:
        out.add(card('link:not_ready', 'dating_link_card', [title(loc.dating_linkNotReady(name))]));
      case DatingLinkState.linked when link!.moment:
        out.add(
          card('link:linked', 'dating_link_card', [
            DatingLinkMoment(
              onContinue: () async {
                unawaited(ref.read(datingLinkGatewayProvider).dismiss(DatingPostLinkOffer.linked));
                await datingGoToCouple(context, ref);
              },
            ),
          ]),
        );
      case _:
        break;
    }
    final pendingBoxes ="""),
], 'T5 chat screen')

edit('lib/features/dating/routes/dating_routes.dart', [
    ("""import 'package:attune/features/dating/device/trip_note.dart';
""", """import 'package:attune/features/dating/device/trip_note.dart';
import 'package:attune/features/dating/link/link_screen.dart';
"""),
    ("""  static const appIcon = '/dating/app-icon';
""", """  static const appIcon = '/dating/app-icon';

  /// Spec 2 W9 (§3.9, §3.14): Become a couple on Attune, for one chat.
  static String link(String matchId) => '/dating/link/$matchId';
"""),
    ("""    back: () => DatingPaths.settings,
  ),
];""", """    back: () => DatingPaths.settings,
  ),
  // Spec 2 W9 (§3.9, §3.15): nothing here moves but the moment's settle;
  // alone, back is its chat.
  datingRoute('/dating/link/:matchId', 'datingLink', signedIn, (s) {
    final id = s.pathParameters['matchId'] ?? '';
    return DatingRootBack(
      to: () => DatingPaths.chat(id),
      child: DatingLinkScreen(matchId: id),
    );
  }),
];"""),
], 'T5 route')

# The controller's ruling (R-W9-16): the app learns dating_couple_link from
# the Dating read it already makes once per process for everyone
# (documentationFlagsProvider's get_dating_home; Dating's flags are
# server-only), so a phone with the flag off asks nothing more. The one
# call now yields both Dating flags. Exact edits (W3a's file; the manual's
# shared flags file: one branch).
edit('lib/features/dating/domain/services/dating_feature_flags.dart', [
    ("""  static const String profilePhotos = 'dating_profile_photos';
""", """  static const String profilePhotos = 'dating_profile_photos';

  /// Spec 2 W9 (R-W9-16): Become a couple on Attune and what follows it.
  static const String coupleLink = 'dating_couple_link';
"""),
    ("""  static Future<bool> isDatingModeAvailable(SupabaseClient supabase) async {
    try {
      final result = await supabase.rpc('get_dating_home');
      if (result is! Map) return false;
      final state = result['state'];
      return state is String && state != 'feature_unavailable';
    } catch (_) {
      return false;
    }
  }""",
     """  static Future<bool> isDatingModeAvailable(SupabaseClient supabase) async =>
      (await flagsOn(supabase)).contains(datingModeEnabled);

  /// Spec 2 W9 (R-W9-16): the Dating flags on for this client, from one
  /// get_dating_home() answer: [datingModeEnabled] unless it answers
  /// `feature_unavailable`, [coupleLink] while it carries `couple_link`.
  /// Any error or unexpected shape is none.
  static Future<Set<String>> flagsOn(SupabaseClient supabase) async {
    try {
      return flagsFrom(await supabase.rpc('get_dating_home'));
    } catch (_) {
      return const <String>{};
    }
  }

  /// [flagsOn]'s reading of one answer.
  static Set<String> flagsFrom(Object? result) {
    if (result is! Map) return const <String>{};
    final state = result['state'];
    return {
      if (state is String && state != 'feature_unavailable') datingModeEnabled,
      if (result['couple_link'] == true) coupleLink,
    };
  }"""),
], 'T5 Dating flags')

edit('lib/app/documentations/user_manual/data/documentation_flags.dart', [
    ("""    for (final flag in DocumentationRegistry.allRequiredFlags) {
      // R-35: dating_% flags are server-only; Dating's own read answers,
      // on Dating's own client (T12 carry E; W4b's device header).
      final on = flag == DatingFeatureFlags.datingModeEnabled
          ? await DatingFeatureFlags.isDatingModeAvailable(
            ref.read(datingSupabaseClientProvider),
          )
          : await ChatFeatureFlags.isEnabled(client, flag);
      if (on) enabled.add(flag);
    }""", """    for (final flag in DocumentationRegistry.allRequiredFlags) {
      // R-35: dating_% flags are server-only; Dating's own read answers,
      // on Dating's own client (T12 carry E; W4b's device header). Spec 2
      // W9 (R-W9-16): the same one read also says dating_couple_link.
      if (flag == DatingFeatureFlags.datingModeEnabled) {
        enabled.addAll(
          await DatingFeatureFlags.flagsOn(
            ref.read(datingSupabaseClientProvider),
          ),
        );
        continue;
      }
      if (await ChatFeatureFlags.isEnabled(client, flag)) enabled.add(flag);
    }"""),
], 'T5 manual flags read')
````

Create `.superpowers/sdd/2026-11-23-spec2-w9/arb_fragment_T5.txt` with exactly:

````text
  "dating_linkBecome": "Become a couple on Attune",
  "@dating_linkBecome": {"description": "Spec 2 §3.6, §3.9 the Safety sheet's row (once either has tapped We met) and the link page's title."},
  "dating_linkAgreeingTitle": "What are we agreeing to?",
  "@dating_linkAgreeingTitle": {"description": "Spec 2 §3.9 the private step's title."},
  "dating_linkAgreeingBody": "Your Dating profiles pause for both of you. You'll share a private space for the two of you. Either of you can end it at any time.",
  "@dating_linkAgreeingBody": {"description": "Spec 2 §3.9 what linking means, read in full before the buttons."},
  "dating_linkKeep": "Keep our first messages as a 'How we met' card (only if {name} agrees too)",
  "@dating_linkKeep": {"description": "Spec 2 §3.9 the checkbox (each side ticks their own; kept only when both did, A-3).", "placeholders": {"name": {"type": "String"}}},
  "dating_linkAsk": "Ask {name}",
  "@dating_linkAsk": {"description": "Spec 2 §3.9 step 1's button.", "placeholders": {"name": {"type": "String"}}},
  "dating_linkNotNow": "Not now",
  "@dating_linkNotNow": {"description": "Spec 2 §3.9 step 1: nothing is asked."},
  "dating_linkAskedYou": "{name} would like to become a couple on Attune.",
  "@dating_linkAskedYou": {"description": "Spec 2 §3.9 step 2, in the other person's chat and on the link page.", "placeholders": {"name": {"type": "String"}}},
  "dating_linkSee": "See what this means",
  "@dating_linkSee": {"description": "Spec 2 §3.9 step 2: opens the same page."},
  "dating_linkYes": "Yes, let's",
  "@dating_linkYes": {"description": "Spec 2 §3.9 step 2: the second Yes."},
  "dating_linkNotRightNow": "Not right now",
  "@dating_linkNotRightNow": {"description": "Spec 2 §3.9 step 2: declines; only the asker is told (dating_linkNotReady)."},
  "dating_linkNotReady": "{name} isn't ready yet.",
  "@dating_linkNotReady": {"description": "Spec 2 §3.9 step 2: what the asker sees after Not right now (for 14 days).", "placeholders": {"name": {"type": "String"}}},
  "dating_linkDecided": "You decided together.",
  "@dating_linkDecided": {"description": "Spec 2 §3.9 step 4, with the one settle (≤ 600 ms, once)."},
  "dating_linkDecidedBody": "Your Dating profiles are paused.",
  "@dating_linkDecidedBody": {"description": "Plan copy (W9 Ruling R-W9-3): under You decided together. on the Relationship home's card, for the asker who wasn't there for the second Yes."},
  "dating_linkOffline": "You're offline. Nothing has changed yet.",
  "@dating_linkOffline": {"description": "Spec 2 §3.15 the second confirmation offline."},
  "dating_linkAsked": "You've asked {name}.",
  "@dating_linkAsked": {"description": "Plan copy (W9): the asker's own request, waiting, in the chat and on the link page.", "placeholders": {"name": {"type": "String"}}},
  "dating_linkTakeBack": "Take it back",
  "@dating_linkTakeBack": {"description": "Plan copy (W9): the asker withdraws the open request (nothing is said to the other person)."},
  "dating_linkUnavailable": "This isn't possible right now.",
  "@dating_linkUnavailable": {"description": "Plan copy (W9): the server's unavailable (one of you is in another Attune relationship or under a hold; it never says which)."},
  "dating_linkMatchedChip": "The day you matched: {date}",
  "@dating_linkMatchedChip": {"description": "Spec 2 §3.9 step 5 About us's AU2 chip (never pre-filled).", "placeholders": {"date": {"type": "String"}}},
  "dating_linkOfferTitle": "Delete your Dating profile and preferences?",
  "@dating_linkOfferTitle": {"description": "Spec 2 §3.9 step 6, 30 days after linking, once, on the Relationship home."},
  "dating_linkOfferBody": "You can set up Dating again later.",
  "@dating_linkOfferBody": {"description": "Spec 2 §3.9 step 6."},
  "dating_linkOfferDelete": "Delete my Dating data",
  "@dating_linkOfferDelete": {"description": "Spec 2 §3.9 step 6: opens Leave Dating (§3.8)."},
  "dating_linkOfferKeep": "Keep for now",
  "@dating_linkOfferKeep": {"description": "Spec 2 §3.9 step 6: never asks again."},
  "dating_howWeMetRow": "How we met",
  "@dating_howWeMetRow": {"description": "Plan copy (W9): About us's row and the card's title."},
  "dating_howWeMetRowHint": "Opens your first messages",
  "@dating_howWeMetRowHint": {"description": "Plan copy (W9): the row's screen reader hint."},
  "dating_howWeMetIntro": "Your first messages, as you both saw them.",
  "@dating_howWeMetIntro": {"description": "Plan copy (W9): the How we met card's line (masked details stay masked, A-3)."},
  "dating_howWeMetYou": "You",
  "@dating_howWeMetYou": {"description": "Plan copy (W9): the reader's own message on the How we met card."},
  "dating_howWeMetThem": "Your partner",
  "@dating_howWeMetThem": {"description": "Plan copy (W9): the other's message on the How we met card."}
````

```bash
D=.superpowers/sdd/2026-11-23-spec2-w9
python3 -I $D/edit_app_T5.py
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py $D/arb_fragment_T5.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package > /dev/null 2>&1; echo "gen-l10n exit=$?"
dart format lib/features/dating/link/dating_link.dart lib/features/dating/link/link_screen.dart
```

Expected: `…dating_chat.dart: 4 edit(s) (T5 header link)`, `…chat_sheets.dart: 3 edit(s) (T5 Safety sheet)`, `…dating_chat_screen.dart: 4 edit(s) (T5 chat screen)`, `…dating_routes.dart: 3 edit(s) (T5 route)`, `…dating_feature_flags.dart: 2 edit(s) (T5 Dating flags)`, `…documentation_flags.dart: 1 edit(s) (T5 manual flags read)`; `added 27 keys`; `gen-l10n exit=0`; `Formatted 2 files (0 changed) …`.

- [ ] **Step 3: The fakes, the shells, the audit's route list, the tests and their goldens**

Create `test/features/dating/support/dating_link_fakes.dart` with exactly:

````dart
// Spec 2 W9: the couple link faked for widget tests. Every answer is the
// test's; every call is recorded; an answer can be held open (D8 tests).
import 'dart:async';

import 'package:attune/features/dating/link/dating_link.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FakeDatingLink implements DatingLinkGateway {
  FakeDatingLink({
    this.pageAnswer = const DatingLinkPage(
      ok: true,
      displayName: 'Kofi',
      link: DatingLink(state: DatingLinkState.none),
    ),
    this.offerAnswer = DatingPostLinkOffer.none,
  });

  DatingLinkPage pageAnswer;
  DatingLinkAnswer answer = const DatingLinkAnswer(ok: true, requestId: 'r1');
  DatingPostLinkOffer offerAnswer;
  DateTime? originAnswer;
  List<DatingHowWeMetItem>? howAnswer;
  Completer<void>? hold;

  final pages = <String>[];
  final asks = <(String key, String matchId, bool keep)>[];
  final confirms = <(String key, String requestId, bool keep)>[];
  final declines = <String>[];
  final cancels = <String>[];
  final origins = <String>[];
  final hows = <String>[];
  int offers = 0;
  final dismissals = <DatingPostLinkOffer>[];

  Future<DatingLinkAnswer> _answer() async {
    final held = hold;
    if (held != null) await held.future;
    return answer;
  }

  @override
  Future<DatingLinkPage> page(String matchId) async {
    pages.add(matchId);
    return pageAnswer;
  }

  @override
  Future<DatingLinkAnswer> ask(
    String key,
    String matchId, {
    required bool keep,
  }) {
    asks.add((key, matchId, keep));
    return _answer();
  }

  @override
  Future<DatingLinkAnswer> confirm(
    String key,
    String requestId, {
    required bool keep,
  }) {
    confirms.add((key, requestId, keep));
    return _answer();
  }

  @override
  Future<DatingLinkAnswer> decline(String requestId) {
    declines.add(requestId);
    return _answer();
  }

  @override
  Future<DatingLinkAnswer> cancel(String requestId) {
    cancels.add(requestId);
    return _answer();
  }

  @override
  Future<DateTime?> origin(String relationshipId) async {
    origins.add(relationshipId);
    return originAnswer;
  }

  @override
  Future<List<DatingHowWeMetItem>?> howWeMet(String relationshipId) async {
    hows.add(relationshipId);
    return howAnswer;
  }

  @override
  Future<DatingPostLinkOffer> offer() async {
    offers++;
    return offerAnswer;
  }

  @override
  Future<bool> dismiss(DatingPostLinkOffer offer) async {
    dismissals.add(offer);
    offerAnswer = DatingPostLinkOffer.none;
    return true;
  }
}

List<Override> datingLinkOverrides(FakeDatingLink fake) => [
  datingLinkGatewayProvider.overrideWithValue(fake),
];
````

Create `.superpowers/sdd/2026-11-23-spec2-w9/edit_tests_T5.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W9 Task 5: every Dating shell fakes the couple link (no test
# reaches the server). Exact edits (W3's test support file).
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-23-spec2-w9/anchor.py')['edit']
edit('test/features/dating/support/dating_shell.dart', [
    ("""import 'dating_trip_fakes.dart';
""", """import 'dating_trip_fakes.dart';
import 'dating_link_fakes.dart';
"""),
    ("""        // Spec 2 W8b: the device check is faked unless a test says otherwise.
        ...datingTripOverrides(FakeDatingTrip()),
        ...overrides,""", """        // Spec 2 W8b: the device check is faked unless a test says otherwise.
        ...datingTripOverrides(FakeDatingTrip()),
        // Spec 2 W9: the couple link is faked unless a test says otherwise.
        ...datingLinkOverrides(FakeDatingLink()),
        ...overrides,"""),
    ("""  // Spec 2 W8b: the device check is faked.
  ...datingTripOverrides(FakeDatingTrip()),
];

/// The Dating section's overrides""", """  // Spec 2 W8b: the device check is faked.
  ...datingTripOverrides(FakeDatingTrip()),
  // Spec 2 W9: the couple link is faked.
  ...datingLinkOverrides(FakeDatingLink()),
];

/// The Dating section's overrides"""),
], 'T5 shell fakes')

# The link page is audited at 2.0 (its goldens and the large-text audit
# over test/features/dating/link). Exact edit.
edit('test/architecture/text_scale_routes_test.dart', [
    ("""  // Spec 2 W8b (§3.12, §6.7; R-80): App icon, in Dating and in Settings.
  'datingAppIcon',
""", """  // Spec 2 W8b (§3.12, §6.7; R-80): App icon, in Dating and in Settings.
  'datingAppIcon',
  // Spec 2 W9 (§3.9, §3.14): Become a couple on Attune.
  'datingLink',
"""),
], 'T5 text-scale audit')

# R-W9-16: the manual's flag read keeps answering dating_mode_enabled from
# get_dating_home on Dating's own client; one call now also says
# dating_couple_link. W3a's source pin follows the new shape. Exact edit.
edit('test/app/documentations/documentation_registry_flags_test.dart', [
    ("""    // dating_mode_enabled itself is answered by get_dating_home (R-35),
    // on Dating's own client, never the global one (T12 carry E).
    expect(
      source,
      matches(RegExp(
        r'flag == DatingFeatureFlags\\.datingModeEnabled\\s*\\?\\s*'
        r'await DatingFeatureFlags\\.isDatingModeAvailable\\(\\s*'
        r'ref\\.read\\(datingSupabaseClientProvider\\),?\\s*\\)',
      )),
    );""", """    // dating_mode_enabled itself is answered by get_dating_home (R-35),
    // on Dating's own client, never the global one (T12 carry E). Spec 2 W9
    // (R-W9-16): the same one read also says dating_couple_link.
    expect(
      source,
      matches(RegExp(
        r'if \\(flag == DatingFeatureFlags\\.datingModeEnabled\\) \\{\\s*'
        r'enabled\\.addAll\\(\\s*await DatingFeatureFlags\\.flagsOn\\(\\s*'
        r'ref\\.read\\(datingSupabaseClientProvider\\),?\\s*\\),?\\s*\\);\\s*continue;',
      )),
    );"""),
], 'T5 manual flags pin')
````

Create `test/features/dating/link/link_test.dart` with exactly:

````dart
// Spec 2 W9 (§3.6, §3.9 steps 1-4, §3.14, §3.15, §7.4; carry 6; D8):
// "Become a couple on Attune" in the chat and on /dating/link/:matchId.
import 'dart:async';

import 'package:attune/features/dating/link/dating_link.dart';
import 'package:attune/features/dating/link/link_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_chat_fakes.dart';
import '../support/dating_link_fakes.dart';
import '../support/dating_shell.dart';

const _asked = DatingLinkPage(
  ok: true,
  displayName: 'Kofi',
  link: DatingLink(state: DatingLinkState.askedYou, requestId: 'r9'),
);

/// The chat's page with [link] in its header (and either side's We met).
FakeDatingChat _chat(Map<String, Object?>? link, {bool theyMet = true}) {
  final page = datingPageJson();
  final chat = page['chat']! as Map<String, Object?>;
  chat['we_met'] = {'mine': false, 'theirs': theyMet};
  chat['link'] = link;
  return FakeDatingChat(page: page);
}

Future<DatingShell> _link(
  WidgetTester t,
  FakeDatingLink fake, {
  bool online = true,
}) => pumpDatingShell(
  t,
  initial: '/dating/link/m1',
  online: online,
  overrides: datingLinkOverrides(fake),
);

Future<DatingShell> _inChat(
  WidgetTester t,
  FakeDatingChat chat,
  FakeDatingLink fake,
) => pumpDatingShell(
  t,
  initial: '/dating/chat/m1',
  overrides: [...datingChatOverrides(chat), ...datingLinkOverrides(fake)],
);

void main() {
  group('the Safety sheet (§3.6; carry 6)', () {
    for (final (what, link, theyMet, offered) in [
      (
        'the other side said We met, nothing asked',
        <String, Object?>{'state': 'none'},
        true,
        true,
      ),
      ('nobody said We met', null, false, false),
      (
        'already asked',
        <String, Object?>{'state': 'asked', 'request_id': 'r1'},
        true,
        false,
      ),
    ]) {
      testWidgets('Become a couple on Attune: $what', (t) async {
        await _inChat(t, _chat(link, theyMet: theyMet), FakeDatingLink());
        await tapInReach(
          t,
          find.bySemanticsLabel('Safety options for this conversation'),
        );
        await t.pumpAndSettle();
        expect(
          find.text('Become a couple on Attune'),
          offered ? findsOneWidget : findsNothing,
        );
      });
    }

    testWidgets('its row opens the link page for this chat', (t) async {
      final fake = FakeDatingLink();
      await _inChat(t, _chat({'state': 'none'}), fake);
      await tapInReach(
        t,
        find.bySemanticsLabel('Safety options for this conversation'),
      );
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Become a couple on Attune'));
      await t.pumpAndSettle();
      expect(find.byType(DatingLinkScreen), findsOneWidget);
      expect(fake.pages, ['m1']);
      expect(find.text('What are we agreeing to?'), findsOneWidget);
    });
  });

  group('asking (step 1)', () {
    testWidgets('the private step is read in full, then Ask {Name} sends this '
        'side\'s Yes with its keep choice, once', (t) async {
      final fake = FakeDatingLink();
      fake.hold = Completer<void>();
      await _link(t, fake);
      expect(find.text('What are we agreeing to?'), findsOneWidget);
      expect(
        find.text(
          "Your Dating profiles pause for both of you. You'll share a private space for the two of you. "
          'Either of you can end it at any time.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          "Keep our first messages as a 'How we met' card (only if Kofi agrees too)",
        ),
        findsOneWidget,
      );
      await tapInReach(t, find.byKey(const ValueKey('dating_link_keep')));
      await t.pump();
      await tapInReach(t, find.text('Ask Kofi'));
      await tapInReach(t, find.text('Ask Kofi'));
      await t.pump();
      expect(fake.asks, hasLength(1));
      expect(fake.asks.single.$2, 'm1');
      expect(fake.asks.single.$3, isTrue);
      fake.pageAnswer = const DatingLinkPage(
        ok: true,
        displayName: 'Kofi',
        link: DatingLink(state: DatingLinkState.asked, requestId: 'r1'),
      );
      fake.hold!.complete();
      await t.pumpAndSettle();
      expect(find.text("You've asked Kofi."), findsOneWidget);
      expect(find.text('Take it back'), findsOneWidget);
    });

    testWidgets('Not now asks nothing and goes back to the chat', (t) async {
      final fake = FakeDatingLink();
      final s = await _link(t, fake);
      await tapInReach(t, find.text('Not now'));
      await t.pumpAndSettle();
      expect(fake.asks, isEmpty);
      expect(s.location, '/dating/chat/m1');
    });

    testWidgets('Take it back withdraws the request', (t) async {
      final fake = FakeDatingLink(
        pageAnswer: const DatingLinkPage(
          ok: true,
          displayName: 'Kofi',
          link: DatingLink(state: DatingLinkState.asked, requestId: 'r1'),
        ),
      );
      await _link(t, fake);
      await tapInReach(t, find.text('Take it back'));
      await t.pumpAndSettle();
      expect(fake.cancels, ['r1']);
    });
  });

  group('the other side (steps 2-4)', () {
    testWidgets(
      'Yes, let\'s sends the second Yes with this side\'s own choice; '
      '"You decided together." settles once, then the Relationship home',
      (t) async {
        final fake = FakeDatingLink(pageAnswer: _asked);
        fake.answer = const DatingLinkAnswer(ok: true, relationshipId: 'rel-1');
        final s = await _link(t, fake);
        expect(
          find.text('Kofi would like to become a couple on Attune.'),
          findsOneWidget,
        );
        await tapInReach(t, find.text("Yes, let's"));
        await t.pump();
        expect(fake.confirms.single.$2, 'r9');
        expect(fake.confirms.single.$3, isFalse);
        expect(find.text('You decided together.'), findsOneWidget);
        // One settle, at most 600 ms: half-way in, then still.
        double opacity() =>
            t
                .widget<Opacity>(
                  find
                      .ancestor(
                        of: find.text('You decided together.'),
                        matching: find.byType(Opacity),
                      )
                      .first,
                )
                .opacity;
        await t.pump(const Duration(milliseconds: 300));
        expect(opacity(), lessThan(1));
        await t.pump(const Duration(milliseconds: 300));
        expect(opacity(), 1);
        await tapInReach(t, find.text('Continue'));
        await t.pumpAndSettle();
        expect(s.location, startsWith('/home?tab=chat'));
      },
    );

    testWidgets('Not right now declines and goes back to the chat', (t) async {
      final fake = FakeDatingLink(pageAnswer: _asked);
      final s = await _link(t, fake);
      await tapInReach(t, find.text('Not right now'));
      await t.pumpAndSettle();
      expect(fake.declines, ['r9']);
      expect(fake.confirms, isEmpty);
      expect(s.location, '/dating/chat/m1');
    });

    testWidgets('offline the second Yes waits: "You\'re offline. Nothing has '
        'changed yet."', (t) async {
      final fake = FakeDatingLink(pageAnswer: _asked);
      await _link(t, fake, online: false);
      expect(
        find.text("You're offline. Nothing has changed yet."),
        findsOneWidget,
      );
      await tapInReach(t, find.text("Yes, let's"));
      await t.pump();
      expect(fake.confirms, isEmpty);
    });

    testWidgets('a refusal is a calm line and nothing moves', (t) async {
      final fake = FakeDatingLink(pageAnswer: _asked);
      fake.answer = const DatingLinkAnswer(ok: false, reason: 'unavailable');
      final s = await _link(t, fake);
      await tapInReach(t, find.text("Yes, let's"));
      await t.pumpAndSettle();
      expect(find.text("This isn't possible right now."), findsOneWidget);
      expect(find.text('You decided together.'), findsNothing);
      expect(s.location, '/dating/link/m1');
    });

    testWidgets('the asker who wasn\'t there sees the moment once, and it is '
        'marked seen', (t) async {
      final fake = FakeDatingLink(
        pageAnswer: const DatingLinkPage(
          ok: true,
          displayName: 'Kofi',
          link: DatingLink(state: DatingLinkState.linked, moment: true),
        ),
      );
      final s = await _link(t, fake);
      expect(find.text('You decided together.'), findsOneWidget);
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(fake.dismissals, [DatingPostLinkOffer.linked]);
      expect(s.location, startsWith('/home?tab=chat'));
    });
  });

  group('the chat\'s card (§3.9 step 2)', () {
    testWidgets('the other side\'s request, with See what this means', (
      t,
    ) async {
      final fake = FakeDatingLink(pageAnswer: _asked);
      await _inChat(t, _chat({'state': 'asked_you', 'request_id': 'r9'}), fake);
      expect(
        find.text('Kofi would like to become a couple on Attune.'),
        findsOneWidget,
      );
      await tapInReach(t, find.text('See what this means'));
      await t.pumpAndSettle();
      expect(find.byType(DatingLinkScreen), findsOneWidget);
      expect(find.text("Yes, let's"), findsOneWidget);
    });

    testWidgets(
      "Not right now's answer to the asker: {Name} isn't ready yet.",
      (t) async {
        await _inChat(t, _chat({'state': 'not_ready'}), FakeDatingLink());
        expect(find.text("Kofi isn't ready yet."), findsOneWidget);
      },
    );

    testWidgets('the asker can take it back from the chat', (t) async {
      final fake = FakeDatingLink();
      await _inChat(t, _chat({'state': 'asked', 'request_id': 'r1'}), fake);
      expect(find.text("You've asked Kofi."), findsOneWidget);
      await tapInReach(t, find.text('Take it back'));
      await t.pumpAndSettle();
      expect(fake.cancels, ['r1']);
    });
  });

  testWidgets('D8: another account sees nothing of the last one\'s link page', (
    t,
  ) async {
    final fake = FakeDatingLink(pageAnswer: _asked);
    final s = await _link(t, fake);
    expect(
      find.text('Kofi would like to become a couple on Attune.'),
      findsOneWidget,
    );
    fake.pageAnswer = const DatingLinkPage(reason: 'match_unavailable');
    s.container.read(datingTestAccount.notifier).state = 'kwame';
    await t.pump();
    expect(find.textContaining('Kofi'), findsNothing);
    await t.pumpAndSettle();
    expect(find.textContaining('Kofi'), findsNothing);
    expect(find.text("This isn't available any more."), findsOneWidget);
  });

  for (final (name, page) in [
    (
      'dating_link_ask',
      const DatingLinkPage(
        ok: true,
        displayName: 'Kofi',
        link: DatingLink(state: DatingLinkState.none),
      ),
    ),
    ('dating_link_answer', _asked),
    (
      'dating_link_moment',
      const DatingLinkPage(
        ok: true,
        displayName: 'Kofi',
        link: DatingLink(state: DatingLinkState.linked, moment: true),
      ),
    ),
  ]) {
    testWidgets('goldens and the three guidelines: $name', (t) async {
      final overrides = [
        ...datingShellOverrides(),
        ...datingLinkOverrides(FakeDatingLink(pageAnswer: page)),
      ];
      Widget screen() => const DatingLinkScreen(matchId: 'm1');
      await expectFlowGoldens(t, name, screen, overrides: overrides);
      await pumpFlowScreen(t, screen, overrides: overrides);
      await expectFlowGuidelines(t);
    });
  }

  test('the server\'s link is read defensively', () {
    expect(
      DatingLink.fromJson({'state': 'asked'}),
      isNull,
      reason: 'a request with no id',
    );
    expect(DatingLink.fromJson({'state': 'odd'}), isNull);
    expect(
      DatingLink.fromJson({'state': 'linked', 'moment': true})!.moment,
      isTrue,
    );
    expect(
      DatingLinkAnswer.fromJson({
        'ok': false,
        'reason': 'Kofi is married',
      }).reason,
      'failed',
    );
    expect(
      DatingLinkPage.fromJson({
        'ok': true,
        'display_name': ' Kofi ',
        'link': null,
      }).displayName,
      'Kofi',
    );
  });
}
````

```bash
D=.superpowers/sdd/2026-11-23-spec2-w9
python3 -I $D/edit_tests_T5.py
dart format test/features/dating/support/dating_link_fakes.dart test/features/dating/link/link_test.dart
flutter test --no-pub --update-goldens test/features/dating/link/link_test.dart > /dev/null 2>&1; ls test/features/dating/link/goldens | wc -l | tr -d ' '
flutter test --no-pub test/features/dating/link/link_test.dart test/architecture/text_scale_routes_test.dart test/features/dating/device/dating_lock_entry_test.dart test/app/documentations 2>&1 | tr '\r' '\n' | grep -E '^[0-9:]+ \+[0-9]+.*(All tests passed|Some tests failed)' | tail -1
python3 scripts/large_text_audit.py --scale 2.0 test/features/dating/link 2>&1 | tail -1; rm -rf test/features/dating/link/failures
flutter analyze --no-pub lib test 2>&1 | tail -1
```

Expected: `…dating_shell.dart: 3 edit(s) (T5 shell fakes)`, `…text_scale_routes_test.dart: 1 edit(s) (T5 text-scale audit)`, `…documentation_registry_flags_test.dart: 1 edit(s) (T5 manual flags pin)`; `Formatted 2 files (0 changed) …`; `12`; `+82: All tests passed!` (Task 5's build of the plan's text; `+100` on the finished tree, with Task 5's fix rounds); `SCALE 2.0: 0 site(s) to fix, 0 listed apart`; `571 issues found. …` (no new issue).

- [ ] **Step 4: The Dart mutants**

Create `.superpowers/sdd/2026-11-23-spec2-w9/mut_T5_dart.py` with exactly:

````python
# Spec 2 W9 Task 5: Dart mutants (dmut.py, in a private copy).
L = 'lib/features/dating/link/link_screen.dart'
C = 'lib/features/dating/chat/dating_chat_screen.dart'
T = ['test/features/dating/link/link_test.dart']
MUTS = {
    'row_always': (C, """      canLink:
          (header.weMet || header.theyMet) &&
          header.link?.state == DatingLinkState.none,""", """      canLink: true,""", T),
    'they_met_ignored': (C, """          (header.weMet || header.theyMet) &&""", """          header.weMet &&""", T),
    'keep_not_asked': (L, """                            widget.matchId,
                            keep: _keep,""", """                            widget.matchId,
                            keep: false,""", T),
    'keep_not_confirmed': (L, """                            requestId,
                            keep: _keep,""", """                            requestId,
                            keep: true,""", T),
    'no_moment': (L, """        setState(() => _decided = true);""", """        _back();""", T),
    'offline_yes': (L, """            busy: _busy == _LinkBusy.yes,
            onPressed:
                online && _busy == null && requestId != null""", """            busy: _busy == _LinkBusy.yes,
            onPressed:
                _busy == null && requestId != null""", T),
    'moment_unmarked': (L, """              ref
                  .read(datingLinkGatewayProvider)
                  .dismiss(DatingPostLinkOffer.linked),""", """              Future<void>.value(),""", T),
    'settle_long': (L, """const kDatingLinkSettle = Duration(milliseconds: 600);""", """const kDatingLinkSettle = Duration(milliseconds: 900);""", T),
    'd8_keeps_page': (L, """        _page = null;
""", "", T),
    'not_ready_unsaid': (C, """      case DatingLinkState.notReady:""", """      case DatingLinkState.notReady when false:""", T),
    'take_back_declines': (C, """    final r = await ref.read(datingLinkGatewayProvider).cancel(requestId);""",
                           """    final r = await ref.read(datingLinkGatewayProvider).decline(requestId);""", T),
}
````

```bash
D=.superpowers/sdd/2026-11-23-spec2-w9
python3 -I $D/dmut.py $D/mut_T5_dart.py | tee $D/mut_T5_dart.txt | tail -1
```

Expected: `11/11 killed`.

- [ ] **Step 5: Record the tree (do not commit).**

### Task 6: The Relationship home's `link_offer` card, About us's chip and How we met (§3.9 steps 4–6, §7.4; C-4, I-12, R20; R-W9-3, R-W9-8, R-W9-14)

**Files:**
- Create: `lib/features/dating/link/{link_offer_card.dart, how_we_met.dart}`, `test/features/dating/link/relationship_side_test.dart`, `$D/{edit_app_T6.py, mut_T6_dart.py}`
- Modify (shared files, regression risk flagged in Global Constraints): `lib/features/chat/presentation/screens/conversations_screen.dart` (one appended `HomeCard`), `lib/features/couple_profile/presentation/couple_profile_providers.dart` (the provider's body, one line, and its import), `lib/features/couple_profile/presentation/screens/about_us_screen.dart` (one row, one import)
- Test: `relationship_side_test.dart`

**Interfaces:**
- Consumes: Task 5's providers, gateway, `DatingLinkMoment`, `FakeDatingLink`; Spec 1's `AboutUsDateSuggestion`, `TogetherSince`, `DatePrecision`.
- Produces: `DatingLinkOfferCard`, `datingLinkOfferShown(WidgetRef)`, `datingLinkOfferCardId`, `datingLinkOfferCardLabel`, `datingAboutUsDateSuggestions(Ref, String)`, `DatingHowWeMetRow`, `DatingHowWeMetScreen`.

- [ ] **Step 1: The card, the chip and the row**

Create `lib/features/dating/link/link_offer_card.dart` with exactly:

````dart
// Spec 2 W9 (§3.9 steps 4 and 6; C-4; Ruling R-W9-3): the Relationship
// home's one Dating card, HomeCard `link_offer` on ConversationsScreen
// (the screen includes it only while [datingPostLinkOfferProvider] reports
// an offer; it lives here, so nothing of Dating is in the chat feature but
// that one entry). For the asker who has not seen it: "You decided
// together." with the one settle, once ([Continue] marks it seen). From 30
// days after linking: "Delete your Dating profile and preferences? You can
// set up Dating again later." [Delete my Dating data] opens Leave Dating
// (§3.8, behind the Dating lock; leaving removes the data the card needs)
// [Keep for now] (never asked again). Each answer is sent once; the card
// goes as soon as it is answered.
import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/link/dating_link.dart';
import 'package:attune/features/dating/link/link_screen.dart'
    show DatingLinkMoment;
import 'package:attune/features/dating/routes/dating_routes.dart'
    show DatingPaths;
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// C-4: the card's id in the person's saved order, and its name for a
/// screen reader (the spec's label; the other cards' are English too).
const datingLinkOfferCardId = 'link_offer';
const datingLinkOfferCardLabel = 'Your Dating profile';

/// Whether the Relationship home shows the `link_offer` card now.
bool datingLinkOfferShown(WidgetRef ref) {
  final account = ref.watch(datingAccountProvider);
  final offer = ref.watch(datingPostLinkOfferProvider(account)).valueOrNull;
  return offer != null && offer != DatingPostLinkOffer.none;
}

class DatingLinkOfferCard extends ConsumerStatefulWidget {
  const DatingLinkOfferCard({super.key});

  @override
  ConsumerState<DatingLinkOfferCard> createState() =>
      _DatingLinkOfferCardState();
}

class _DatingLinkOfferCardState extends ConsumerState<DatingLinkOfferCard> {
  bool _sent = false;

  Future<void> _answer(String? account, DatingPostLinkOffer offer) async {
    if (_sent) return;
    setState(() => _sent = true);
    await ref.read(datingLinkGatewayProvider).dismiss(offer);
    if (!mounted) return;
    ref.invalidate(datingPostLinkOfferProvider(account));
    setState(() => _sent = false);
  }

  Future<void> _delete(String? account) async {
    await context.push(DatingPaths.leave);
    if (!mounted) return;
    ref.invalidate(datingPostLinkOfferProvider(account));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final account = ref.watch(datingAccountProvider);
    final offer = ref.watch(datingPostLinkOfferProvider(account)).valueOrNull;
    final Widget content;
    switch (offer) {
      case DatingPostLinkOffer.linked:
        content = DatingLinkMoment(
          body: loc.dating_linkDecidedBody,
          onContinue:
              _sent ? null : () => _answer(account, DatingPostLinkOffer.linked),
        );
      case DatingPostLinkOffer.delete:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                loc.dating_linkOfferTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              loc.dating_linkOfferBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              children: [
                TextButton(
                  key: const ValueKey('dating_link_offer_keep'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    foregroundColor: theme.colorScheme.onSurface,
                  ),
                  onPressed:
                      _sent
                          ? null
                          : () => _answer(account, DatingPostLinkOffer.delete),
                  child: Text(loc.dating_linkOfferKeep),
                ),
                FilledButton.tonal(
                  key: const ValueKey('dating_link_offer_delete'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: _sent ? null : () => unawaited(_delete(account)),
                  child: Text(loc.dating_linkOfferDelete),
                ),
              ],
            ),
          ],
        );
      case DatingPostLinkOffer.none || null:
        return const SizedBox.shrink();
    }
    return CardInkWell(
      borderRadius: BorderRadiusTokens.floatingNavAll,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: KeyedSubtree(
          key: ValueKey('dating_link_offer_$account'),
          child: content,
        ),
      ),
    );
  }
}
````

Create `lib/features/dating/link/how_we_met.dart` with exactly:

````dart
// Spec 2 W9 (§3.9 steps 3 and 5, §8 W9; I-12): what About us shows of
// the couple's Dating start. The AU2 chip "The day you matched: {date}"
// through the client override of Spec 1's aboutUsDateSuggestionsProvider
// (never pre-filled: a tap fills it), and one row, "How we met", opening
// the card of the first messages as both saw them. Both are read by the
// relationship's members only, and show nothing when there is nothing
// (no Dating origin, no card, the flag off, a failed read).
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/providers/locale_provider.dart'
    show currentLocaleProvider;
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/couple_profile/domain/couple_profile.dart'
    show DatePrecision, TogetherSince;
import 'package:attune/features/couple_profile/presentation/couple_profile_providers.dart'
    show AboutUsDateSuggestion;
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/link/dating_link.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The localisations outside a widget (the chip's words), English when the
/// app's locale can't be read.
AppLocalizations _loc(Ref ref) {
  try {
    return lookupAppLocalizations(ref.watch(currentLocaleProvider));
  } catch (_) {
    return lookupAppLocalizations(const Locale('en'));
  }
}

/// I-12: About us's AU2 chips for [relationshipId]: "The day you matched:
/// {date}" when the couple came from Dating, else none.
List<AboutUsDateSuggestion> datingAboutUsDateSuggestions(
  Ref ref,
  String relationshipId,
) {
  final account = ref.watch(datingAccountProvider);
  if (account == null) return const [];
  final at =
      ref
          .watch(datingLinkOriginProvider((account, relationshipId)))
          .valueOrNull;
  if (at == null) return const [];
  final local = at.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  return [
    AboutUsDateSuggestion(
      label: _loc(ref).dating_linkMatchedChip(MyDateFormat.toDate(day)),
      since: TogetherSince(day, DatePrecision.day),
    ),
  ];
}

/// About us's "How we met" row: nothing unless the couple kept the card.
class DatingHowWeMetRow extends ConsumerWidget {
  const DatingHowWeMetRow({super.key, required this.relationshipId});

  final String relationshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final account = ref.watch(datingAccountProvider);
    if (account == null) return const SizedBox.shrink();
    final items =
        ref
            .watch(datingHowWeMetProvider((account, relationshipId)))
            .valueOrNull;
    if (items == null) return const SizedBox.shrink();
    void open() => Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => DatingHowWeMetScreen(items: items)),
    );
    return Semantics(
      container: true,
      button: true,
      label: loc.dating_howWeMetRow,
      hint: loc.dating_howWeMetRowHint,
      onTap: open,
      child: ExcludeSemantics(
        child: InkWell(
          key: const ValueKey('dating_how_we_met_row'),
          onTap: open,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      loc.dating_howWeMetRow,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The How we met card: the first messages as both saw them, in order,
/// each with who wrote it. Read only; nothing here moves.
class DatingHowWeMetScreen extends StatelessWidget {
  const DatingHowWeMetScreen({super.key, required this.items});

  final List<DatingHowWeMetItem> items;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return AllowLargeText(
      child: Scaffold(
        appBar: AppBar(title: Text(loc.dating_howWeMetRow)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              Text(
                loc.dating_howWeMetIntro,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Spacing.md),
              for (final item in items)
                Semantics(
                  container: true,
                  label:
                      '${item.mine ? loc.dating_howWeMetYou : loc.dating_howWeMetThem}. ${item.text}',
                  child: ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.sm),
                      child: Align(
                        alignment:
                            item.mine
                                ? AlignmentDirectional.centerEnd
                                : AlignmentDirectional.centerStart,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 320),
                          padding: const EdgeInsets.all(Spacing.sm),
                          decoration: BoxDecoration(
                            color:
                                item.mine
                                    ? theme.colorScheme.primaryContainer
                                    : theme.colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadiusTokens.mdAll,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.mine
                                    ? loc.dating_howWeMetYou
                                    : loc.dating_howWeMetThem,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color:
                                      item.mine
                                          ? theme.colorScheme.onPrimaryContainer
                                          : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: Spacing.xs),
                              Text(
                                item.text,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color:
                                      item.mine
                                          ? theme.colorScheme.onPrimaryContainer
                                          : theme.colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
````

Create `.superpowers/sdd/2026-11-23-spec2-w9/edit_app_T6.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W9 Task 6 (§3.9 steps 4-6; C-4, I-12): the Relationship side.
# ConversationsScreen appends one HomeCard, link_offer, while the server
# reports an offer (nothing else in the file changes: the chat card, the
# Journals and Together cards and every Games entry point stay as they
# are); Spec 1's aboutUsDateSuggestionsProvider is overridden on the client
# by Dating's chip (its own body, one line; Spec 1's couple_profiles
# functions are untouched); About us gains one row, How we met, that shows
# nothing unless the couple kept the card. Formatter-style edits (Spec 1
# and Relationship files, never formatted).
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-23-spec2-w9/anchor.py')['edit']

edit('lib/features/chat/presentation/screens/conversations_screen.dart', [
    ("""import 'package:attune/features/chat/domain/utils/conversation_preview.dart';
""", """import 'package:attune/features/chat/domain/utils/conversation_preview.dart';
import 'package:attune/features/dating/link/link_offer_card.dart';
"""),
    ("""                      cards: const [
                        HomeCard(id: 'journals', label: 'Journals', child: JournalsCard()),
                        HomeCard(id: 'together', label: 'Together', child: TogetherCard()),
                      ],""", """                      cards: [
                        const HomeCard(id: 'journals', label: 'Journals', child: JournalsCard()),
                        const HomeCard(id: 'together', label: 'Together', child: TogetherCard()),
                        // Spec 2 W9 (§3.9 step 6, C-4): Dating's one card, while it has something to say.
                        if (datingLinkOfferShown(ref))
                          const HomeCard(
                            id: datingLinkOfferCardId,
                            label: datingLinkOfferCardLabel,
                            child: DatingLinkOfferCard(),
                          ),
                      ],"""),
], 'T6 Relationship home card')

edit('lib/features/couple_profile/presentation/couple_profile_providers.dart', [
    ("""/// AU2's suggested-date chips (spec §3.8, review I-12): none from Spec 1.
/// Spec 2 W9 overrides this from get_dating_link_origin ("The day you
/// matched: {date}"); a suggestion is never pre-filled.
final aboutUsDateSuggestionsProvider = Provider.autoDispose
    .family<List<AboutUsDateSuggestion>, String>(
      (ref, relationshipId) => const [],
    );""", """/// AU2's suggested-date chips (spec §3.8, review I-12): none from Spec 1.
/// Spec 2 W9 overrides this from get_dating_link_origin ("The day you
/// matched: {date}"); a suggestion is never pre-filled.
final aboutUsDateSuggestionsProvider = Provider.autoDispose
    .family<List<AboutUsDateSuggestion>, String>(
      // Spec 2 W9 (I-12): Dating's chip, for a couple that came from Dating.
      (ref, relationshipId) => datingAboutUsDateSuggestions(ref, relationshipId),
    );"""),
], 'T6 About us chip')

edit('lib/features/couple_profile/presentation/couple_profile_providers.dart', [
    ("""import 'package:attune/features/couple_profile/domain/couple_profile.dart';
""", """import 'package:attune/features/couple_profile/domain/couple_profile.dart';
import 'package:attune/features/dating/link/how_we_met.dart'
    show datingAboutUsDateSuggestions;
"""),
], 'T6 About us chip import')

edit('lib/features/couple_profile/presentation/screens/about_us_screen.dart', [
    ("""import 'package:attune/features/couple_profile/presentation/widgets/changed_by_line.dart';
""", """import 'package:attune/features/couple_profile/presentation/widgets/changed_by_line.dart';
import 'package:attune/features/dating/link/how_we_met.dart' show DatingHowWeMetRow;
"""),
    ("""              onTap: readOnly ? null : () => _ask(context, question),
            ),
          const SizedBox(height: Spacing.md),""", """              onTap: readOnly ? null : () => _ask(context, question),
            ),
          // Spec 2 W9 (§8 W9): How we met, only when the couple kept it.
          if (id != null) DatingHowWeMetRow(relationshipId: id),
          const SizedBox(height: Spacing.md),"""),
], 'T6 About us row')
````

```bash
D=.superpowers/sdd/2026-11-23-spec2-w9
python3 -I $D/edit_app_T6.py
dart format lib/features/dating/link/link_offer_card.dart lib/features/dating/link/how_we_met.dart
```

Expected: `…conversations_screen.dart: 2 edit(s) (T6 Relationship home card)`, `…couple_profile_providers.dart: 1 edit(s) (T6 About us chip)`, `…couple_profile_providers.dart: 1 edit(s) (T6 About us chip import)`, `…about_us_screen.dart: 2 edit(s) (T6 About us row)`; `Formatted 2 files (0 changed) …`.

- [ ] **Step 2: The tests**

Create `test/features/dating/link/relationship_side_test.dart` with exactly:

````dart
// Spec 2 W9 (§3.9 steps 4-6, §7.4; C-4, I-12; R20): the Relationship side
// of a couple that met in Dating. The Relationship home's one Dating card
// (link_offer, appended after Journals and Together only while the server
// reports an offer; it goes after either answer; the chat card and the
// other cards render and keep their order), About us's "The day you
// matched" chip (never pre-filled) and its How we met row and card.
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/screens/conversations_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/widgets/reorderable_home_cards.dart';
import 'package:attune/features/chat/data/home_card_order_repository.dart';
import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/presentation/couple_profile_providers.dart';
import 'package:attune/features/couple_profile/presentation/screens/about_us_screen.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart'
    show coupleProfileEnabledProvider;
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    show togetherChangeSignalProvider;
import 'package:attune/home/home_seams.dart';
import 'package:attune/app/documentations/user_manual/data/documentation_flags.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/domain/services/dating_feature_flags.dart';
import 'package:attune/features/dating/link/dating_link.dart';
import 'package:attune/features/dating/link/how_we_met.dart';
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_couple_profile.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../support/dating_link_fakes.dart';

class _Conversations extends ConversationsNotifier {
  @override
  Future<List<Conversation>> build() async => [
    Conversation(
      id: 'c1',
      relationshipId: 'rel-1',
      partnerId: 'partner-1',
      name: 'Kofi',
      updatedAt: DateTime.utc(2026, 11, 1),
      relationshipStatus: 'active',
      availability: ConversationAvailability.active,
    ),
  ];
}

class _Journals extends JournalEntriesNotifier {
  @override
  Future<List<JournalEntry>> build() async => const [];
}

class _Reminders extends RemindersListNotifier {
  @override
  Future<List<ReminderModel>> build() async => const [];
}

class _Order implements HomeCardOrderRepository {
  _Order(this.saved);
  List<String>? saved;
  @override
  Future<List<String>?> load() async => saved;
  @override
  Future<void> save(List<String> order) async => saved = order;
}

/// R-W9-16: what the app's one Dating flag read says
/// (documentationFlagsProvider).
Override _flag(bool on) => documentationFlagsProvider.overrideWith(
  (ref) async => on ? {DatingFeatureFlags.coupleLink} : <String>{},
);

Future<ProviderContainer> _home(
  WidgetTester t,
  FakeDatingLink fake, {
  List<String>? saved,
  bool flagOn = true,
}) async {
  t.view.physicalSize = const Size(390, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final container = ProviderContainer(
    overrides: [
      conversationsProvider.overrideWith(_Conversations.new),
      journalEntriesProvider.overrideWith(_Journals.new),
      remindersListProvider.overrideWith(_Reminders.new),
      homeCardOrderRepositoryProvider.overrideWithValue(_Order(saved)),
      datingAccountProvider.overrideWithValue('ama'),
      _flag(flagOn),
      ...datingLinkOverrides(fake),
    ],
  );
  addTearDown(container.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: ConversationsScreen(),
            ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return container;
}

List<String> _cardOrder(WidgetTester t) => [
  for (final c
      in t
          .widget<ReorderableHomeCards>(find.byType(ReorderableHomeCards))
          .cards)
    c.id,
];

void main() {
  group('the Relationship home (C-4, R20)', () {
    testWidgets(
      'no offer: Journals and Together only, the chat card above them',
      (t) async {
        final fake = FakeDatingLink();
        await _home(t, fake);
        expect(_cardOrder(t), ['journals', 'together']);
        expect(find.text('Kofi'), findsWidgets, reason: 'the chat card');
        expect(fake.offers, 1);
      },
    );

    testWidgets(
      'R-W9-16: while the app does not know the flag is on, the offer is '
      'never asked and the card is absent',
      (t) async {
        final fake = FakeDatingLink(offerAnswer: DatingPostLinkOffer.delete);
        await _home(t, fake, flagOn: false);
        expect(fake.offers, 0);
        expect(_cardOrder(t), ['journals', 'together']);
        expect(
          find.text('Delete your Dating profile and preferences?'),
          findsNothing,
        );
      },
    );

    testWidgets('R-W9-16: with the flag on, asked once per home load', (
      t,
    ) async {
      final fake = FakeDatingLink(offerAnswer: DatingPostLinkOffer.delete);
      await _home(t, fake);
      await t.pumpAndSettle();
      expect(fake.offers, 1);
      expect(_cardOrder(t), ['journals', 'together', 'link_offer']);
    });

    testWidgets(
      'the 30-day offer is appended last; Keep for now removes it for good',
      (t) async {
        final fake = FakeDatingLink(offerAnswer: DatingPostLinkOffer.delete);
        await _home(t, fake);
        expect(_cardOrder(t), ['journals', 'together', 'link_offer']);
        expect(
          find.text('Delete your Dating profile and preferences?'),
          findsOneWidget,
        );
        expect(find.text('You can set up Dating again later.'), findsOneWidget);
        expect(find.text('Delete my Dating data'), findsOneWidget);
        await t.ensureVisible(find.text('Keep for now'));
        await t.tap(find.text('Keep for now'));
        await t.pumpAndSettle();
        expect(fake.dismissals, [DatingPostLinkOffer.delete]);
        expect(_cardOrder(t), ['journals', 'together']);
        expect(
          find.text('Delete your Dating profile and preferences?'),
          findsNothing,
        );
      },
    );

    testWidgets('a saved order keeps its own; the card joins at the end and '
        'leaves without disturbing it', (t) async {
      final fake = FakeDatingLink(offerAnswer: DatingPostLinkOffer.delete);
      await _home(t, fake, saved: ['together', 'journals']);
      expect(find.byType(ReorderableHomeCards), findsOneWidget);
      expect(resolveHomeCardOrder(['together', 'journals'], _cardOrder(t)), [
        'together',
        'journals',
        'link_offer',
      ]);
      expect(
        resolveHomeCardOrder(
          ['link_offer', 'together', 'journals'],
          ['journals', 'together'],
        ),
        ['together', 'journals'],
      );
    });

    testWidgets('the asker who wasn\'t there: "You decided together." once', (
      t,
    ) async {
      final fake = FakeDatingLink(offerAnswer: DatingPostLinkOffer.linked);
      await _home(t, fake);
      expect(find.text('You decided together.'), findsOneWidget);
      expect(find.text('Your Dating profiles are paused.'), findsOneWidget);
      await t.ensureVisible(find.text('Continue'));
      await t.tap(find.text('Continue'));
      await t.pumpAndSettle();
      expect(fake.dismissals, [DatingPostLinkOffer.linked]);
      expect(find.text('You decided together.'), findsNothing);
    });

    testWidgets('signed out: nothing is asked', (t) async {
      final fake = FakeDatingLink(offerAnswer: DatingPostLinkOffer.delete);
      t.view.physicalSize = const Size(390, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final container = ProviderContainer(
        overrides: [
          conversationsProvider.overrideWith(_Conversations.new),
          journalEntriesProvider.overrideWith(_Journals.new),
          remindersListProvider.overrideWith(_Reminders.new),
          homeCardOrderRepositoryProvider.overrideWithValue(_Order(null)),
          datingAccountProvider.overrideWithValue(null),
          _flag(true),
          ...datingLinkOverrides(fake),
        ],
      );
      addTearDown(container.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder:
                (_, __) => const MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: ConversationsScreen(),
                ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(fake.offers, 0);
      expect(_cardOrder(t), ['journals', 'together']);
    });
  });

  group('About us (I-12)', () {
    test(
      'the chip: "The day you matched: {date}", that day, never pre-filled',
      () async {
        final fake =
            FakeDatingLink()..originAnswer = DateTime(2026, 3, 14, 12).toUtc();
        final container = ProviderContainer(
          overrides: [
            datingAccountProvider.overrideWithValue('ama'),
            _flag(true),
            ...datingLinkOverrides(fake),
          ],
        );
        addTearDown(container.dispose);
        await container.read(documentationFlagsProvider.future);
        final sub = container.listen(
          aboutUsDateSuggestionsProvider('rel-1'),
          (_, __) {},
        );
        addTearDown(sub.close);
        expect(
          sub.read(),
          isEmpty,
          reason: 'nothing before the origin is read',
        );
        await container.read(datingLinkOriginProvider(('ama', 'rel-1')).future);
        final chips = sub.read();
        expect(chips, hasLength(1));
        expect(
          chips.single.label,
          'The day you matched: Saturday, March 14, 2026',
        );
        expect(chips.single.since.date, DateTime(2026, 3, 14));
        expect(fake.origins, ['rel-1']);
      },
    );

    test('no Dating origin, or signed out: no chip', () async {
      final fake = FakeDatingLink();
      final container = ProviderContainer(
        overrides: [
          datingAccountProvider.overrideWithValue('ama'),
          _flag(true),
          ...datingLinkOverrides(fake),
        ],
      );
      addTearDown(container.dispose);
      await container.read(documentationFlagsProvider.future);
      final sub = container.listen(
        aboutUsDateSuggestionsProvider('rel-1'),
        (_, __) {},
      );
      addTearDown(sub.close);
      await container.read(datingLinkOriginProvider(('ama', 'rel-1')).future);
      expect(sub.read(), isEmpty);
      final out = ProviderContainer(
        overrides: [
          datingAccountProvider.overrideWithValue(null),
          _flag(true),
          ...datingLinkOverrides(fake),
        ],
      );
      addTearDown(out.dispose);
      expect(out.read(aboutUsDateSuggestionsProvider('rel-1')), isEmpty);
      expect(fake.origins, ['rel-1']);
    });

    testWidgets('How we met: a row only when the couple kept it, opening the '
        'messages as both saw them', (t) async {
      final fake =
          FakeDatingLink()
            ..howAnswer = [
              DatingHowWeMetItem(
                mine: true,
                text: 'Hi Kofi!',
                at: DateTime.utc(2026, 3, 14, 9),
              ),
              DatingHowWeMetItem(
                mine: false,
                text: 'Call me on •••',
                at: DateTime.utc(2026, 3, 14, 10),
              ),
            ];
      Future<void> pump(FakeDatingLink f) async {
        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(
          ProviderScope(
            overrides: [
              datingAccountProvider.overrideWithValue('ama'),
              _flag(true),
              ...datingLinkOverrides(f),
            ],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(body: DatingHowWeMetRow(relationshipId: 'rel-1')),
            ),
          ),
        );
        await t.pumpAndSettle();
      }

      await pump(FakeDatingLink());
      expect(find.text('How we met'), findsNothing);
      await pump(fake);
      expect(find.text('How we met'), findsOneWidget);
      await t.tap(find.text('How we met'));
      await t.pumpAndSettle();
      expect(
        find.text('Your first messages, as you both saw them.'),
        findsOneWidget,
      );
      expect(find.text('Hi Kofi!'), findsOneWidget);
      expect(find.text('Call me on •••'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Your partner'), findsOneWidget);
    });

    for (final kept in [true, false]) {
      testWidgets(
        'About us shows How we met ${kept ? 'for a couple that kept it' : 'not at all without a card'}',
        (t) async {
          final fake = FakeDatingLink();
          if (kept) {
            fake.howAnswer = [
              DatingHowWeMetItem(
                mine: true,
                text: 'Hi Kofi!',
                at: DateTime.utc(2026, 3, 14, 9),
              ),
            ];
          }
          await pumpFlowScreen(
            t,
            () => AboutUsScreen(
              target: const AboutUsTarget.shared('rel-1'),
              onClose: () {},
              now: DateTime(2026, 11, 20, 10),
            ),
            overrides: [
              coupleProfileEnabledProvider.overrideWithValue(true),
              coupleProfileRpcProvider.overrideWithValue(
                FakeCoupleProfileServer(
                  profiles: {
                    'rel-1': aboutUsJson(
                      togetherSince: '2026-03-14',
                      precision: 'day',
                    ),
                  },
                ).rpc,
              ),
              homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
              togetherChangeSignalProvider.overrideWith(
                (ref, id) => const Stream.empty(),
              ),
              coupleNameProvider.overrideWith((ref, id) async => null),
              datingAccountProvider.overrideWithValue('ama'),
              _flag(true),
              ...datingLinkOverrides(fake),
            ],
            size: const Size(390, 1400),
          );
          expect(find.text('How we met'), kept ? findsOneWidget : findsNothing);
          expect(
            find.text('Together since'),
            findsWidgets,
            reason: 'Spec 1 rows unchanged',
          );
        },
      );
    }
  });

  test('R-W9-16: one Dating read says both flags', () {
    expect(
      DatingFeatureFlags.flagsFrom({'state': 'active', 'couple_link': true}),
      {DatingFeatureFlags.datingModeEnabled, DatingFeatureFlags.coupleLink},
    );
    expect(
      DatingFeatureFlags.flagsFrom({'state': 'feature_unavailable'}),
      isEmpty,
    );
    expect(
      DatingFeatureFlags.flagsFrom({'state': 'paused', 'couple_link': 'yes'}),
      {DatingFeatureFlags.datingModeEnabled},
    );
    expect(DatingFeatureFlags.flagsFrom(null), isEmpty);
  });

  test('R-W9-16: with the flag not known on, About us asks nothing', () async {
    final fake = FakeDatingLink()..originAnswer = DateTime.utc(2026, 3, 14, 12);
    final container = ProviderContainer(
      overrides: [
        datingAccountProvider.overrideWithValue('ama'),
        _flag(false),
        ...datingLinkOverrides(fake),
      ],
    );
    addTearDown(container.dispose);
    await container.read(documentationFlagsProvider.future);
    final sub = container.listen(
      aboutUsDateSuggestionsProvider('rel-1'),
      (_, __) {},
    );
    addTearDown(sub.close);
    await container.read(datingLinkOriginProvider(('ama', 'rel-1')).future);
    await container.read(datingHowWeMetProvider(('ama', 'rel-1')).future);
    expect(sub.read(), isEmpty);
    expect(fake.origins, isEmpty);
    expect(fake.hows, isEmpty);
  });
}
````

```bash
dart format test/features/dating/link/relationship_side_test.dart
flutter test --no-pub test/features/dating/link/relationship_side_test.dart test/features/chat/conversations_screen_test.dart test/features/couple_profile test/app/documentations 2>&1 | tr '\r' '\n' | grep -E '^[0-9:]+ \+[0-9]+.*(All tests passed|Some tests failed)' | tail -1
shasum -c .superpowers/sdd/2026-11-04-spec1-w10-accessibility-docs/w10-1.0.sha | grep -vc ': OK$'
flutter analyze --no-pub lib test 2>&1 | tail -1
```

Expected: `Formatted 1 file (0 changed) …`; `+196: All tests passed!` (Task 6's build of the plan's text; `+212` on the finished tree) (Spec 1's About us and Conversations tests unchanged); `0` (W10's goldens untouched); `571 issues found. …`.

- [ ] **Step 3: The Dart mutants**

Create `.superpowers/sdd/2026-11-23-spec2-w9/mut_T6_dart.py` with exactly:

````python
# Spec 2 W9 Task 6: Dart mutants (dmut.py, in a private copy).
T = ['test/features/dating/link/relationship_side_test.dart']
MUTS = {
    'card_always': ('lib/features/chat/presentation/screens/conversations_screen.dart',
                    """                        if (datingLinkOfferShown(ref))""", """                        if (true)""", T),
    'keep_not_sent': ('lib/features/dating/link/link_offer_card.dart',
                      """    await ref.read(datingLinkGatewayProvider).dismiss(offer);""", """    await Future<void>.value();""", T),
    'offer_signed_out': ('lib/features/dating/link/dating_link.dart',
                         """      if (account == null) return DatingPostLinkOffer.none;
      return ref.read(datingLinkGatewayProvider).offer();""", """      return ref.read(datingLinkGatewayProvider).offer();""", T),
    'row_always': ('lib/features/dating/link/how_we_met.dart',
                   """    if (items == null) return const SizedBox.shrink();""", """    if (items == null) return const Text('How we met');""", T),
    'about_us_row_missing': ('lib/features/couple_profile/presentation/screens/about_us_screen.dart',
                             """          if (id != null) DatingHowWeMetRow(relationshipId: id),
""", "", T),
    'chip_gone': ('lib/features/couple_profile/presentation/couple_profile_providers.dart',
                  """      (ref, relationshipId) => datingAboutUsDateSuggestions(ref, relationshipId),""",
                  """      (ref, relationshipId) => const [],""", T),
}
# R-W9-16 (the controller's): no call while the app doesn't know the flag is on.
L = 'lib/features/dating/link/dating_link.dart'
MUTS.update({
    'offer_ignores_flag': (L, """      if (account == null || !ref.watch(datingCoupleLinkOnProvider)) {
        return DatingPostLinkOffer.none;""", """      if (account == null) {
        return DatingPostLinkOffer.none;""", T),
    'origin_ignores_flag': (L, """      if (key.$1 == null || !ref.watch(datingCoupleLinkOnProvider)) {
        return null;
      }
      return ref.read(datingLinkGatewayProvider).origin(key.$2);""", """      if (key.$1 == null) {
        return null;
      }
      return ref.read(datingLinkGatewayProvider).origin(key.$2);""", T),
    'how_ignores_flag': (L, """      if (key.$1 == null || !ref.watch(datingCoupleLinkOnProvider)) {
        return null;
      }
      return ref.read(datingLinkGatewayProvider).howWeMet(key.$2);""", """      if (key.$1 == null) {
        return null;
      }
      return ref.read(datingLinkGatewayProvider).howWeMet(key.$2);""", T),
    'flags_miss_link': ('lib/features/dating/domain/services/dating_feature_flags.dart',
                        """      if (result['couple_link'] == true) coupleLink,
""", "", T),
})
````

```bash
D=.superpowers/sdd/2026-11-23-spec2-w9
python3 -I $D/dmut.py $D/mut_T6_dart.py | tee $D/mut_T6_dart.txt | tail -1
```

Expected: `10/10 killed` (`offer_ignores_flag`: `Expected: <0>`).

- [ ] **Step 4: Record the tree (do not commit).**

### Task 7: The design spec's notes, the development flag, every W9 mutant again, and the W9b gate (§1.5 pattern, §4.9; Owner checklist)

**Files:**
- Create: `$D/edit_docs_T7.py`
- Modify: `docs/superpowers/specs/2026-10-24-dating-mode-design.md` (seven `amended S2 W9` notes), `supabase/sql/dev_enable_spec2_dating_flags.sql` (`dating_couple_link`, development only)

- [ ] **Step 1: The notes and the development flag**

Create `.superpowers/sdd/2026-11-23-spec2-w9/edit_docs_T7.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 2 W9 Task 7: the design spec says what W9 built where it differs
# (seven amendment notes, the W7/W8 pattern), and the development flag
# script turns dating_couple_link on in development only (never a
# migration).
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-23-spec2-w9/anchor.py')['edit']
S = 'docs/superpowers/specs/2026-10-24-dating-mode-design.md'
edit(S, [
    ("""The request lapses after 14 days with no copy.
""", """The request lapses after 14 days with no copy. *(amended S2 W9: after "Not right now" the asker may ask again only 14 days on; the other side may ask any time; the asker can take an open request back. A request answers from the asker's life only (an Attune relationship, a hold), never the other person's; a chat hidden on the asker's own phone by a trip can't be asked from, and the other side's trip changes nothing in the answer (R-W9-5, R-W9-6, carry 5).)*
"""),
    ("""exactly as both saw it; A-3).
""", """exactly as both saw it; A-3). *(amended S2 W9: the second Yes calls the invite exchange's own `accept_relationship_invite_v2` unchanged, after inserting the pending row `create-relationship-invite` inserts (its columns; a 12-character code no one is shown), so there is one pairing path; the asker's path is set by its own call. The link sends no push (R-W9-1, R-W9-7). A contract proves a link and an invite make the same rows and side effects.)*
"""),
    ("""4. **Both see** (once): "You decided together." with the settle (≤ 600 ms, once) → the Relationship home.
""", """4. **Both see** (once): "You decided together." with the settle (≤ 600 ms, once) → the Relationship home. *(amended S2 W9: the confirmer sees it at once; the asker sees it once wherever they next are: their chat's top card, the link page, or the Relationship home's `link_offer` card, which shows it before the 30-day offer (R-W9-3).)*
"""),
    ("""Nothing else in that file changes; the chat card, the Journals and Together cards and every Games entry point are untouched.
""", """Nothing else in that file changes; the chat card, the Journals and Together cards and every Games entry point are untouched. *(amended S2 W9: the widget lives in `lib/features/dating/link/` (the Dating feature's layout since W3a); "Delete my Dating data" opens Leave Dating (§3.8) behind the Dating lock, and leaving ends the offer (R-W9-8).)*
"""),
    ("""| `dating_export_reads` | `job_id → data_export_jobs ON DELETE CASCADE`, `read_at`; at most 3 rows per job; no content (S-4) |
""", """| `dating_export_reads` | `job_id → data_export_jobs ON DELETE CASCADE`, `read_at`; at most 3 rows per job; no content (S-4) |
| `dating_link_origins` *(amended S2 W9, R-W9-3)* | `relationship_id PK → relationships ON DELETE CASCADE`, `matched_at`, `linked_at`, `low_user_id`, `high_user_id` (→ users ON DELETE SET NULL), each side's `moment_seen_at` and `offer_closed_at`; read only through `get_dating_link_origin` and `get_dating_post_link_offer` (members only); purged with the relationship (the match row it came from is purged 30 days after the link) |
"""),
    ("""`get_dating_post_link_offer()`, `dismiss_dating_post_link_offer()` |
""", """`get_dating_post_link_offer()`, `dismiss_dating_post_link_offer()` *(amended S2 W9: + `get_dating_couple_link(p_match_id, p_show_same_gender)` (the link page's read) and `get_how_we_met(p_relationship_id)`; request and confirm take `p_show_same_gender` as every read that hides (R-T5-1); `dismiss_dating_post_link_offer(p_offer)` names which answer, 'linked' or 'delete'; decline and cancel need no trusted phone (exposure-reducing))* |
"""),
    ("""| `build-data-exports` | change [W9] | one added step in the data phase: calls `dating_export_for_job(job id)` and writes the `dating` part; the existing parts are unchanged (I-13) |
""", """| `build-data-exports` | change [W9] | one added step in the data phase: calls `dating_export_for_job(job id)` and writes the `dating` part; the existing parts are unchanged (I-13) *(amended S2 W9: the step is `dating_part.ts` (`addDatingPart`), writing `dating.json` only when the person has Dating data; its tests run in the frozen-lock CI line)* |
"""),
], 'T7 design spec')

edit('supabase/sql/dev_enable_spec2_dating_flags.sql', [
    ("""    ('dating_traveller_detection', true), -- Spec 2 W8b
""", """    ('dating_traveller_detection', true), -- Spec 2 W8b
    ('dating_couple_link', true), -- Spec 2 W9
"""),
], 'T7 dev flags')
````

```bash
D=.superpowers/sdd/2026-11-23-spec2-w9
python3 -I $D/edit_docs_T7.py
grep -c 'amended S2 W9' docs/superpowers/specs/2026-10-24-dating-mode-design.md
```

Expected: `…dating-mode-design.md: 7 edit(s) (T7 design spec)`, `…dev_enable_spec2_dating_flags.sql: 1 edit(s) (T7 dev flags)`; `7`.

As built (Task 7 rulings T7-1..T7-3): `edit_docs_T7.py` in the tool folder supersedes the text above: its notes say what Tasks 1–6 finally built (their fix rounds), and two notes are added (the link request's foreign keys; the export binding's order and C-1's revoke), so `…dating-mode-design.md: 9 edit(s) (T7 design spec)`, `…dev_enable_spec2_dating_flags.sql: 1 edit(s) (T7 dev flags)`; `9`. Ruling T7-4: the dev script's new line makes `get_dating_home()` carry `couple_link` in `dating_v2_verification_contracts.sql` (which runs the dev script), so that contract turns `dating_couple_link` off again right after it (rolled back with the file).

- [ ] **Step 2: Every W9 mutant set again, on the finished tree**

```bash
D=.superpowers/sdd/2026-11-23-spec2-w9
M=supabase/migrations/20261123100000_dating_v2_couple_link.sql; C=supabase/tests/dating_v2_link_contracts.sql; G=supabase/migrations/20261123100010_dating_v2_couple_link_grants.sql; V=supabase/tests/dating_v2_device_contracts.sql
for s in T1 T2; do echo "$s $(W9_DB=attune_spec3a python3 -I $D/mutate.py $M $C $D/mut_$s.py $D/mut $G | grep -c 'CONTRACT VIOLATED')"; done
echo "T3 $(W9_DB=attune_spec3a python3 -I $D/mutate.py $V $V $D/mut_T3.py $D/mut | grep -c 'CONTRACT VIOLATED')"
echo "T4 $(python3 -I $D/denomut.py $D/mut_T4.py | tail -1)"
for s in T5 T6; do echo "$s $(python3 -I $D/dmut.py $D/mut_${s}_dart.py | tail -1)"; done
```

Expected: `T1 22`, `T2 22`, `T3 10`; `T4 8/8 killed`; `T5 11/11 killed`, `T6 10/10 killed`.

As built (every set the fix rounds added, `gate_muts_T7.sh`, `denomut.py`, `dmut.py`, `race_muts_T7.sh`): SQL `T1 23/23`, `T2 22/22`, `T2b 1/1`, `T2c 6/6`, `T4b 3/3`, `T3 10/10`, `T3b 2/2`, `T3c 9/9`, `W8-T3 31/31`; Deno `T4 8/8 killed`; Dart `T5 11/11`, `T5b 8/8`, `T5c 14/14`, `T5d 4/4`, `T6 10/10`, `T6b 8/8 killed`; races `cancel_toctou` → 64, `ignores_closed` → 65, `no_retry` → 66 (the second Yes answered `busy`: a deadlock in that run), `no_linked_replay` → 67, and 4/4 after each restore.

- [ ] **Step 3: The W9b gate (wait for an idle machine for the race script)**

```bash
D=.superpowers/sdd/2026-11-23-spec2-w9
uptime
bash $D/gate.sh W9b attune_spec3a
```

Expected (the replay's):

```text
SQL 164 PASS, 15 FAIL
SQL-NEW-FAILS: FAIL dating_v2_verification_contracts.sql
LINK all held
DEVICE all held
DENO ok | 285 passed | 0 failed (2s)
DENO-CHECK exit=0
DENO-EXPORTS ok | 26 passed | 0 failed (134ms)
ANALYZE 571 issues found. (ran in 7.1s)
W10SHA 0
W9SHA 0
LATCH lib/home/home_screen.dart: OK
LARGETEXT SCALE 2.0: 0 site(s) to fix, 0 listed apart
GAMES All tests passed!
FLAGS 46 rows, 6 on
LOAD-BEFORE-RACES 2.13 2.88 5.74
RACES 62 PASS, 0 FAIL
FLUTTER +9711 -3: Some tests failed.
FLUTTER-FAILS:
  test/accessibility/w10/healing_journal_large_text_test.dart: journal list and entry, 390 wide, text 1.0
  test/accessibility/w10/healing_journal_large_text_test.dart: journal list and entry, 390 wide, text 1.3
  test/accessibility/w10/healing_journal_large_text_test.dart: journal list and entry, 390 wide, text 2.0
DONE
# Task 7 Ruling T7-4: the one new SQL fail was this task's dev-script line
# (dating_couple_link on adds couple_link to W4's exact home answers);
# dating_v2_verification_contracts.sql turns the couple link off again after
# its \i of the dev script. suite.sh again, 18:42 UTC (W10's launch
# contract in the suite):
SQL 165 PASS, 14 FAIL   (new fails: none; the 14 are the baseline's)
```

- [ ] **Step 4: Record the tree (do not commit).**

---

## Owner checklist (nothing here is done by an implementer)

1. **⚑ Owner questions 1–13** (above): each was built on its default; say which to change.
2. **Deploys.** `supabase db push` (one migration and its twin; the self-revoke means a push that stops between them fails closed), then deploy `build-data-exports` (its `dating_part.ts`), then app builds. `dating_couple_link` stays off in production; its production gate row names the W9 gate.
3. **The W9 production gate (§8 W9):** counsel confirms the export scope (R-W9-9: own data only, own sent messages, report details, no counterpart data, photo metadata without files) and the How we met rule (both consent; masked unless both swapped); the copy, DV and LGBTQ+ reviewers sign §3.9's copy and the Plan copy (owner question 5); the LGBTQ+ reviewer reads owner question 9.
4. **DPIA lines.** `dating_link_origins` (match date, link date, the two members, two once-only marks; purged with the relationship); `couple_how_we_met` (message text both saw, kept only with both consents; purged with the relationship); `dating_export_reads` (job id and time only); the export's own-data part (decrypted own answers delivered only to the person who asked, three reads a job, logged).
5. **Device checks (release builds, F-4):** two phones, two Dating accounts that matched: We met on one, Become a couple on the other; Ask with and without Keep our first messages; Not right now (the asker's "{Name} isn't ready yet."); Take it back; Yes, let's (the settle once; reduce motion fades; the Relationship home on both; About us's chip and How we met); TalkBack/VoiceOver read "What are we agreeing to?" in full before its buttons; text at 200%; offline second Yes; the Dating lock on before `/dating/link/…` from a deep link; the Relationship home's card on day 30 (set the clock or the row) and Keep for now; "Download my data" holds `dating.json` with only your own messages.
6. **The asker's moment (R-W9-3)** is shown at their next open, not pushed (owner question 3).
7. **Metrics:** `dating.couple_link` (links), `dating.couple_link.asked` (asks); the invite counters also count links (owner question 2).
The consolidated list (deploy order, owner questions with their defaults, every review's copy, counsel, LGBTQ+, DV and DPIA items, accepted clashes, device checks) is `.superpowers/sdd/2026-11-23-spec2-w9-couple-link/w9-owner-list.md`.

8. **Carried, not built:** a user-manual topic for Become a couple on Attune (the manual's Dating topics are W3c–W8's; add one with the reviewed copy); photo files in the export (owner question 8).

## Spec coverage (self-review)

| Spec | Where |
|---|---|
| §8 W9: migration 1 `dating_v2_couple_link`; flag `dating_couple_link` | Tasks 1, 2 (the gate row; off) |
| §3.9 step 1: the Safety row once either said We met; "What are we agreeing to?"; Keep our first messages; [Ask {Name}] [Not now] | Task 1 (`request_dating_couple_link`, L2–L3), Task 5 (row, page; carry 6) |
| §3.9 step 2: "{Name} would like to become a couple on Attune." [See what this means] → the sheet → [Yes, let's] [Not right now]; "{Name} isn't ready yet."; lapses after 14 days, no copy | Task 1 (L3–L5; R-W9-5), Task 5 (chat card, page) |
| §3.9 step 3: one transaction; the invite exchange's row transitions (now its own function, R-W9-1); both paused; other chats closed neutrally; both paths; `couple_linked`; first 50 messages masked unless both swapped (A-3) | Task 1 (L6, L7, L9; races Task 3) |
| §3.9 step 4: "You decided together." with the settle → the Relationship home | Task 5 (page, chat card), Task 6 (home card; R-W9-3) |
| §3.9 step 5, I-12: the AU2 chip "The day you matched: {date}" through the client override; `get_dating_link_origin` members only (S-6, mutant 28) | Task 2 (E2), Task 6 (chip; R-W9-14) |
| §3.9 step 6, C-4, R20: the 30-day card, one `HomeCard` (`link_offer`, "Your Dating profile"), only while an offer exists; Keep for now never asks again | Task 2 (E4), Task 6 (order, presence, Keep for now; R-W9-8) |
| The controller's ruling: no offer call while the flag is off | Task 2 (E6, `get_dating_home`'s `couple_link`), Task 5 (`flagsOn`), Task 6 (flag off → never asked; on → once a home load; mutants `offer_ignores_flag`, `origin_ignores_flag`, `how_ignores_flag`, `flags_miss_link`; R-W9-16) |
| §4.3 `dating_couple_link_requests`, `couple_how_we_met`, `dating_export_reads` (+ `dating_link_origins`, R-W9-3) | Tasks 1, 2 (RLS, nobody's grants, the canary) |
| §4.2, §4.4 S-4: `dating_export_for_job` bound to a building job, no user id, three logged reads; no `dating_export_for_user`; the canary's scan | Task 2 (E1, E5; mutants 22, 23) |
| §4.7, I-13: `build-data-exports` adds the `dating` part; other parts unchanged | Task 4 (`dating_part.ts`) |
| §4.10 / R9: `export_relationship` re-created from its live body + the How we met card; `data_export_contracts.sql:229-233` | Task 2 (`edits_T2.py`, `marked_diff`, E3, 1b) |
| §4.8: How-we-met card purged with the relationship | Task 1 (`ON DELETE CASCADE`) |
| §7.1 `dating_v2_link_contracts.sql` (every clause) | Tasks 1, 2 |
| §7.4: link widget tests; the Relationship-home card test | Tasks 5, 6 |
| §7.5 mutants 21, 22, 23, 28 | Tasks 1, 2 |
| §3.15 Couple link (one settle; read in full; offline) | Task 5 |
| §3.14 `/dating/link/:matchId` | Task 5 (route; behind the Dating lock: W8's lock entry test covers it) |
| §6.9 `dating.couple_link` | Task 1 |
| S18 (secretly partnered): no partner-facing signal; asking reveals nothing | Task 1 (L8; R-W9-6) |
| Carries 1–8 | Pre-flight table |
| §1.5 pattern: amendment notes where W9 differs | Task 7 |

## Replay record (2026-11-23)

**Status at handback: the fresh full replay at `cbf7b30b` was stopped during Task 1 (the controller's handback call).** Run so far on a fresh copy (`git archive cbf7b30b`) and a fresh clone of `attune_spec3a`: Task 1 Step 1 (`163 PASS 14 FAIL`, `571 issues`, flutter baseline `+9621 -3`), Step 2 (`3`), Step 3 (`CONTRACT VIOLATED: dating_couple_link is not off`), Step 5 (exit 0), each as Expected. An earlier replay at `fba46cff` ran Tasks 1–4 and the W9a gate end to end: every Expected line matched except the W9a gate's SQL suite, which found four catalogue pins W9 extends (`service_role_grants_test.sql`, and the reflections, never-introduce and photos pins); `edit_tests_T1.py` and `edit_tests_T2.py` now update them (each passes on the build). That gate otherwise read: LINK and DEVICE `all held`, Deno `283`, `deno check` clean, exports `26`, analyze `571`, W10/W9 sha `0`/`0`, latch OK, Games passed, `FLAGS 46 rows, 6 on`, `RACES 61 PASS, 0 FAIL`, flutter `+9118 -3`. Tasks 5–7 and R-W9-16 (the controller's flag gate) were verified in the build only: link and relationship-side tests and the manual flag tests `+64: All tests passed!`; mutants T2 `22`, T5 `11/11`, T6 `10/10` killed. **Still to do: a fresh full replay of Tasks 1–7 at `cbf7b30b`, both gates, the ARB byte check, and the `@@…@@` placeholders (W9a/W9b gate blocks, T2 line count, two test counts).**

**Task 7 (2026-11-23), the finished tree (W9 with W10 present, uncommitted):** every W9 mutant set again (all killed, Task 7 Step 2's As built line), the W9b gate with neither skip switch (Step 3's block: SQL 165/14 after Ruling T7-4, races 62/0 at load 2.13, Deno 285, analyze 571, flutter `+9711 -3` with only the three `healing_journal_large_text` goldens), and the placeholders above filled from the build (the W9a block from Task 4's gate). R-W9-16 now says what was built. Not done here: a fresh `git archive` replay and the ARB byte check.
