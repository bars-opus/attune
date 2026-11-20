# Spec 2 W5 (Matching and introductions) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Summary (one paragraph).** W5 is three batches, ten tasks, three migrations (each with its grants twin), one new edge function, and Today on the app. **W5a** (Tasks 1–3) → `20261119100000_dating_v2_matching.sql` (+ `20261119100010_dating_v2_matching_grants.sql`): the v1 trait objects dropped (snapshots, alignment and similarity functions, the v1 generators, the v1 match read, the alignment flag, the weekly cron), introductions reshaped with one row per pair ever, matches carrying their pair, the `introductions_v2` config with its caps CHECK and the production `DEV-` guard, the hard filters rewritten over one person row shared by the single-pair predicate and generation, the cool-off function, freshness, and the functions that named a dropped object re-created (Task 1); the hourly generation tick per country with temp-table decryption, caps, ranking, the band, seeded jitter, reasons, determinism and dead-lettering, and the cron replaced (Task 2); the race case for two ticks, the dev script activating the config, and the W5a gate (Task 3). **W5b** (Tasks 4–7) → `20261119110000_dating_v2_today.sql` (+ `…110010_…_grants.sql`): the card builder, `get_my_dating_today()`, `get_my_dating_introductions()` v2, act v2 with fixed answers, the match-moment marks, the Today notes, `dating_photo_keys_for_viewer`, the digest and its cron, and the race case for simultaneous interest (Task 4); the `dating-photo-urls` edge function (Task 5); the client's Today data, the photo memory and its wipe, the reasons, captions on the card (Task 6); Today, the match moment, Widen, the family question, the quiet note, the section's way in, the manual, and the W5b gate (Task 7). **W5c** (Tasks 8–10) → `20261119120000_dating_v2_signals.sql` (+ `…120010_…_grants.sql`): the moderation queue's table, the dragnet (throttle and filter 15) and the several-accounts-per-phone signal, the fairness job and its cron, and the Other countries read (Task 8); the "Never introduce me" screen (Task 9); the Other countries setting with the cross-border card, the manual, and the W5c gate (Task 10).

**Replayed.** Every task below was replayed in order in a scratch copy of the repo (on a clone of `attune_spec3a`): every "Create … with exactly" block, every edit and splice script, ARB fragment, `gen-l10n`, `dart format` and test command, every mutant set, the race script on an idle scratch database and the Deno CI line. The Expected lines are what that replay printed (Replay record, end of plan).

**Goal:** Build Spec 2's matching and introductions (§5, §3.4, §3.5, §3.12, W5) on the W1–W4 server and app: up to three introductions a day per person, from hard filters that hold both ways and never admit a never-introduce pair (kept rows included), ranked by feasibility and stated values with bounded seeded jitter and fair exposure, deterministic and created once per cohort; Today with honest day states, the card with "Why you two were introduced", the 60-second photo URLs checked on the phone first, Interested / Not for me with undo, the match moment once per side, the neutral daily digest; the never-introduce screen, Other countries with the cross-border card, the behaviour signals to a queue and the weekly fairness check; and Dating still off in production.

**Architecture:** Server first in each batch, then the edge function, then the app. Every re-created SQL function is taken from its LIVE body (`pg_get_functiondef` on `attune_spec3a` after the earlier batches, saved to `$D/before_w5{a,b,c}/`) with only the lines marked `-- Spec 2 W5a` / `W5b` / `W5c` changed (`marked_diff.py` checks); two functions the spec calls rewritten (`dating_pair_passes_hard_filters`, `act_on_dating_introduction` v2) are replaced whole and say so. The hard filters are one implementation: a person row (`private.dating_gen_person`, decrypted only inside a definer function and held only in a transaction's temp table or a variable) and pure functions over two rows, so generation's set and the single-pair predicate can't drift. New functions are `SECURITY DEFINER SET search_path = ''`, pre-validate input and answer `{ok:false, reason}` with a fixed code instead of raising. The edge function holds no state and no database call is open across Storage's signing. The app keeps Today in account-keyed `autoDispose` providers and route-scoped widgets (D8), photos as bytes in a 20-image memory (C-5) emptied by Dating's wipe entry; every Dating screen sits behind the lock gate (`datingRoute()`), and only the Dating-scoped client calls the server (S-7).

**Tech Stack:** Supabase Postgres 17 (RLS, `SECURITY DEFINER`, pg_cron, `extensions.digest`, `pgp_sym_decrypt` through `private.dating_field_decrypt`), psql, Python 3 (build, edit, splice and mutation scripts), Deno 2.8.1 (edge function and tests, frozen lock `.github/deno-w9.lock`), Flutter 3.29.1 / Dart 3.7 / Riverpod 2.6 / go_router, `supabase_flutter`, `http` (all already dependencies). No new package.

**Spec:** `docs/superpowers/specs/2026-10-24-dating-mode-design.md` — §8 W5 (W5a, W5b, W5c, the gate line); §5 (5.1–5.11); §3.0, §3.1 (`active`), §3.4, §3.5, §3.12, §3.13 (digest), §3.14, §3.15 (Today, Match moment, Settings/never-introduce); §2.3 (freshness), §2.4, §2.6, §2.8; §4.1, §4.2, §4.3 (`dating_introductions`, `dating_matches`, `dating_algorithm_configs`, `dating_settings`, `dating_moderation_cases`, `dating_fairness_reports`), §4.4, §4.5, §4.6 (the generation, digest and fairness crons), §4.7 (`dating-photo-urls`), §4.8, §4.9 W5a–W5c, §4.10 (every row tagged W5); §6.9; §7.1 (`dating_v2_matching_contracts.sql`), §7.2 S3, S5, S10, §7.3 (`dating-photo-urls`), §7.4, §7.5 mutants 2, 3, 6, 18, 19, 20, §7.6 (1.6/6.3 concurrency), §7.7 (W5's device checks); §9 R12. `docs/superpowers/specs/2026-10-24-cross-spec-review.md` — S-4, S-5, I-9, W-2. Carries: `.superpowers/sdd/2026-11-19-spec2-w5/carries.md` (all 18, mapped below). Format reference: `docs/superpowers/plans/2026-11-09-spec2-w4-verification.md`.

## Global Constraints

- **Where and how.** Work in the main working tree on `main` (`/Users/user/attune`). HEAD is `a2d22add` (S2 W1–W4 committed). The owner may have uncommitted edits (`supabase/.temp/cli-latest`, `backup-before-planning-p2.sql`): never revert, stash, stage, checkout or reformat them. Every edit to an existing file is an exact replacement made by a script that asserts each anchor occurs once (`anchor.py`); if an anchor moved because a later fix changed it, apply the same change to the current text and say so in the task report.
- **NO commits.** No `git add`, `git commit`, `git stash`, `git checkout`, `git reset`, `git rm` (delete files with `rm`). Where a skill says "commit", instead: **do not commit; record the tree in the report** with `T=$(mktemp -u); GIT_INDEX_FILE=$T git read-tree HEAD && GIT_INDEX_FILE=$T git add -A && GIT_INDEX_FILE=$T git write-tree; rm -f $T` (a private index; the real index is untouched). The controller commits after the wave's final review.
- **Formatting.** Never `dart format` a pre-existing file (the repo uses an older formatter; formatting reflows it). `dart format` only the files a task creates. A later task that edits a file an earlier W5 task created writes its edit in `dart format` style by hand (every edit script below is already in that style) and does not run the formatter on it.
- **SQL target.** Contracts run only on `attune_spec3a`, from the repo root. A file with a top-level `BEGIN;` runs as `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f F`; one without runs wrapped: `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -c 'BEGIN' -f F -c 'ROLLBACK'` (`suite.sh` does both). Migrations and their twins are applied with `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f <file>`. Confirm the target first (`psql -X -d attune_spec3a -Atc 'select current_database()'` prints `attune_spec3a`). **NEVER `attune_test`. NEVER run `scripts/local_pg_setup.sh` or `scripts/local_pg_grants.sql`** — but DO append each new twin's `\i` line to `scripts/local_pg_grants.sql` (`grants_line.py`). Mutants run inside one transaction that the contract's own `ROLLBACK` ends (`mutate.py`, with the grants twin applied after each migration mutant). An `IF a OR b` in a DO block has no evaluation order: every side-effecting call is its own statement first (the replay hit it twice).
- **Migrations.** `20261119100000_dating_v2_matching.sql`, `20261119110000_dating_v2_today.sql`, `20261119120000_dating_v2_signals.sql`, each with its `…10_…_grants.sql` twin, later than every file in `supabase/migrations/` (the newest is `20261109110010_dating_v2_trusted_devices_grants.sql`). If `ls supabase/migrations | sort | tail -1` shows anything at or after `20261119100000` when Task 1 starts, shift all six to the next free hours keeping their order and change every header, `\i` line and command. Each file is one `BEGIN; … COMMIT;`, idempotent at its own task (applied twice, `exit=0` both times), with `SET LOCAL lock_timeout = '5s'`. W5a's migration is not re-applied after W5b's (act's return type changes), so W5a's mutant sets run in Tasks 1–2 only (Ruling R-25). Every new function: `SECURITY DEFINER SET search_path = ''` (the pure ones `IMMUTABLE`), fully-qualified names, `REVOKE ALL … FROM PUBLIC, anon` and `service_role` unless the spec gives it the service role, `GRANT EXECUTE … TO authenticated` only for the client RPCs (`get_my_dating_introductions(integer)` until W5b, `get_my_dating_today()`, `get_my_dating_introductions()`, `act_on_dating_introduction`, `mark_dating_match_moment_seen`, `dismiss_dating_today_note`, `get_dating_abroad_options()`); the service role gets `dating_photo_keys_for_viewer` and DML on the queue and the fairness reports only; every grant is re-asserted in the twin. Re-created functions start from their LIVE body and change only lines marked `-- Spec 2 W5a|W5b|W5c` (`marked_diff.py` checks). Pre-validate input so no raw constraint error echoes input; NULL never counts as eligible, current or safe (`IS NOT TRUE`, `IS DISTINCT FROM`, `coalesce(…, false)`); the device check never answers NULL. Shared lock order: the per-person setup lock (`private.dating_lock_setup`) first, then rows, with a bounded 40P01/55P03/40001 retry (3) then `busy`. Exposure-reducing writes are never gated by the device (adding a never-introduce number, narrowing Other countries); deletion is never blocked. No `CREATE INDEX CONCURRENTLY`; no function names a table a later batch creates.
- **Production stays off.** No Dating flag turns on in production; no migration turns a flag on, activates a config or sets `attune_environment`. `supabase/sql/dev_enable_spec2_dating_flags.sql` turns every Dating flag that exists ON in development (six after W5a drops `dating_alignment_algorithm_v1`) and, from W5a, activates `introductions_v2` with `DEV-` review references (§4.9); in production a trigger refuses to activate a config whose references start `DEV-`.
- **Vendors and data.** No vendor call in any test (Deno tests inject the RPC and the signer; no `--allow-net`). Never read `.env*`, credentials or the keychain. Decrypted answers live only inside a definer function or a transaction's temp table (`ON COMMIT DROP`); `rank_detail` and `reasons` hold no special-category value (V is a count; faith reasons only when both show faith); no payload carries who someone would like to meet, their pools, faith importance, a hidden field, a storage key, a pair key or a user id.
- **Copy.** New strings go into `lib/i10n/app_en.arb` under `dating_` only through `python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py <fragment>`, then `flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package`. Straight apostrophes. Copy names people, never "they" for the partner or another person (the spec's own "They're never told." refers to the listed number's owner and is kept verbatim). Every displayed date or time goes through `MyDateFormat`. Exact spec strings are copied verbatim; strings this plan adds are marked "Plan copy" in their ARB description and listed for the reviewers (Owner checklist). The app never shows a server's text: every answer is a fixed code mapped to ARB copy; reasons are ids mapped to reviewed copy (Fable M3).
- **UI.** Every Dating screen and sheet is under `AllowLargeText`; sheets carry `datingSheetSettings(...)` and `DatingSheetTracker` (W3 final I-1b). Error red is `#C62828` in light (`FlowErrorLine`) and the theme's own colour in dark; errors are icon-plus-text live regions; busy, offline and device answers are calm lines (`DatingCalmLine`, `DatingReverifyLine`). Goldens at 1.0, 1.3, 2.0 and RTL (`expectFlowGoldens`), the three guidelines (`expectFlowGuidelines`), a dark-theme render, the large-text audit at 2.0 (`0 site(s) to fix`). Taps in tests use `tapInReach` (the W10 helper) then pump. Motion: cards cross-fade in and collapse at 200 ms, the moment settles once in at most 600 ms with one light haptic, nothing moves under reduce motion (fades instead). Text fields never let the keyboard learn (`enableSuggestions`, `autocorrect`, `enableIMEPersonalizedLearning` all false; `expectPrivateKeyboard`).
- **D8 shared phones, D20 / C-5.** Every Dating read is keyed to the signed-in account and every screen clears its state on an account change; tests hold the next account's read open and assert no frame shows the last account's state; a held "Not for me" is never sent as the next account. Nothing Dating is written to prefs, files, the image disk cache or secure storage; photos are bytes in `DatingPhotoMemory` (20 at most), cleared on quick exit and sign-out through Dating's entry in Spec 1's device wipe registry. No file or key name says "dating" outside `lib/features/dating/` paths already in use.
- **Every answer settles.** One idempotency key per action (`DatingActionKeys`), settled once the answer is final (`keys.settle`); a busy or failed answer keeps it.
- **Off limits.** In-chat Games (`test/architecture/games_untouched_test.dart` stays green), Opinions, `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`, `lib/home/home_screen.dart` and its latch (byte-identical; `shasum -c .superpowers/sdd/2026-11-07-spec2-w3/latch.sha`), `quick_exit_service.dart`, `auth_provider.dart`, `lib/main.dart`, `lib/app/app.dart`, `set_user_path_internal`, `get_public_app_config()`, `get_dating_home()`, `get_dating_profile_preview()`, every applied migration, every Spec 1 file (the sign-in country list is read, never edited), every edge function but `dating-photo-urls` (new). **No deploys** (`supabase db push`, function deploys, secrets and app builds are the owner's; Owner checklist).
- **Gates, every batch (Tasks 3, 7 and 10).** (1) The wrapped SQL suite on `attune_spec3a`: no new FAIL (baseline **160 PASS / 14 FAIL**; still **160 / 14** after each batch: `dating_alignment_contracts.sql` is replaced by `dating_v2_matching_contracts.sql`, whose sections the later batches extend). (2) Full `flutter test`: no failure beyond the known flakes outside Dating (`chat_controller_test:259`, `chat_screen_list_anchor` D<0, `reflection_journal` at midnight, `planning_recent`, `story_outbox_notices_test` "Discard asks first…"; re-run a failing file alone before calling it a flake); baseline **+8191**; the count moves by the tests each task adds (listed per task). (3) `flutter analyze --no-pub lib test`: **571 issues, 0 new**. (4) `shasum -c .superpowers/sdd/2026-11-04-spec1-w10-accessibility-docs/w10-1.0.sha` and `shasum -c .superpowers/sdd/2026-11-04-spec1-w9/flag_off.sha`: every line `OK`. (5) `scripts/concurrency/dating_kill_switch_races.sh` on an IDLE scratch DB built from `pg_dump -s attune_spec3a` plus the config tables' data (`public.metric_key_prefixes`, `public.feature_flags`, `public.country_safety_config`, `private.dating_calling_codes`, and from W5 `public.dating_algorithm_configs`), dropped after: every case `PASS` (30 after W5a, 31 after W5b and W5c). (6) The Deno CI line (`.github/workflows/tests.yml` job `deno-w9`, frozen lock) passes in full (193 before W5b, 200 after). (7) `test/architecture/games_untouched_test.dart` passes and the latch is `OK`. (8) Each task's named mutants all RED (a `CONTRACT VIOLATED` line, `KILLED`), the RED line quoted in the report; a `COMPILE` or an `anchor missing` is a broken mutant to fix, never a kill.


## Review Focus

Five things a real person will meet that this wave must survive. Each is pinned to tests that fail if it regresses.

1. **A never-introduce pair is ever generated or matched — a kept row included** (a person who restarted Dating on a new phone or left keeping the list, then the listed number's owner joins). Expect: the pair is never introduced by any run, never shown, and acting on an introduction made before the entry ends it with the one answer any unavailable introduction gets ("This isn't available any more."), whether the entry is shown or kept (`kept_at`, never shown again, W4 C-1). Tests: Task 1 contract D (`13 on the never-introduce list`, `13 kept on the list from before (carry 4)`, both orders) and K (W5a act and read; mutant `carry4_kept_ignored`); Task 2 contract G2 (w2's kept list names m2: no w2–m2 introduction; mutant `kept_pair_generated`); Task 4 contract K (v2 act: `introduction_unavailable`, the row `invalidated`, the card gone; mutant `act_unsafe_kept_open`).
2. **Both people tap Interested at the same moment.** Expect: one match, both actions kept, both see the moment once, no error, no deadlock, no push. Tests: Task 4 race `simultaneous mutual interest makes one match` (the first act sleeps holding the row; serialised, 0 deadlocks); contract K (`matched: true` for the second, one active match, no `scheduled_notifications` row; mutant `act_pushes`) and N (the moment once per side; mutants `moment_both_sides`, `moment_any_match`).
3. **An account switch on Today on a shared phone** (a sibling signs in while a "Not for me" is still in its undo window). Expect: nothing of the last account's cards, reasons, photos or moments shows while the next account's Today loads; the held "Not for me" is never sent as the next person; the photo memory is emptied by quick exit and sign-out. Tests: Task 7 widget `D8: a held answer is never sent as the next account; nothing of the last shows` (mutant `d8_keeps_pass`); Task 6 `D8: the next account reads its own Today, nothing of the last` and `at most 20 photos, the oldest out first; Dating's wipe empties them` (mutants `memory_unbounded`, `wipe_forgets_photos`).
4. **A same-gender pair where one country has it off** (a UK woman open to Ghana, a Ghanaian woman; or a non-binary UK person opening Other countries). Expect: no same-gender introduction unless the global flag, both Dating countries and both people's fresh (7-day) contexts allow it; never in Ghana whatever a row says; Other countries never offers a country whose rule refuses the person's answers. Tests: Task 1 contract C (`4 two women, one not allowed`, `4 a non-binary person and a man, not allowed`; mutants `m3_no_same_gender`, `m3_context_ignored`) and E (`Ghana, whatever the rows say (carry 3)`, `a context 8 days old`, `the global flag off`); Task 8 contract U (a not-plain UK profile is offered no same-gender-off country; mutant `abroad_same_gender_ignored`).
5. **Generation runs twice for the same cohort, or concurrently** (a retried cron, two workers). Expect: the second run creates 0 and answers `partition_unavailable`; a rerun after a failure makes the same introductions in the same order (seeded); two concurrent ticks claim one run; a failing run publishes nothing and dead-letters after three tries; the decrypted people never outlive the transaction. Tests: Task 2 contract G3 (`a second run of the cohort`), G4 (`the same seed made different introductions`), G6 (`a failing run published or did not dead-letter`; mutants `second_run_reclaims`, `jitter_unseeded`, `never_dead_letters`, `m6_no_commit_drop`); Task 3 race `two generation ticks claim one run (and no temp table survives)`.


## Pre-flight (read before Task 1)

### Shared files and interfaces between tasks

| File or interface | Tasks | Rule |
|---|---|---|
| `.superpowers/sdd/2026-11-19-spec2-w5/` (`$D`) | 1 creates the tools, baselines and `before_w5a/`; every task adds its scripts and outputs | `suite.sh`, `grants_line.py`, `dmut.py`, `anchor.py`, `marked_diff.py` are W4's, copied unchanged; `mutate.py` is W4's with `W5_DB`; `denomut.py` (Task 5) is W4's |
| `supabase/migrations/20261119100000_dating_v2_matching.sql` | 1 builds it (`build_mig_T1.py`: head, re-created functions, tail); 2 adds `mig_T2_generation.sql` and builds again | the builder includes the generation section when the file exists |
| `…100010_dating_v2_matching_grants.sql` | 1 creates; 2 adds generation's revokes (`edit_tests_T2.py`) | |
| `supabase/tests/dating_v2_matching_contracts.sql` | 1 creates (A–F, K in its W5a form, J, a marker for G–I); 2 splices G–I; 4 replaces K and adds L–P; 8 adds Q–U | helpers `pg_temp.ready(n, opts)`, `dev(n)`, `call(user, device, sql)`, `probe(setup[], sql)`, `hf(a, b)`, `pr(n, opts)`, `man(n, opts)`, `metric(key)`, `activate()`; fixture ids are two decimal digits (the phone uses them) |
| `private.dating_gen_person`, `private.dating_person`, `private.dating_admits`, `private.dating_pair_safe`, `private.dating_pair_new`, `private.dating_person_current` | 1 creates; 2 (generation), 4 (`dating_visible_introductions`, act), 8 (re-creates `dating_person_current` with filter 15) use them | one implementation of §5.2 |
| `private.dating_capacity`, `public.run_dating_generation_tick` | 2 creates; 8 re-creates both from their live bodies (`before_w5c/`) | |
| `act_on_dating_introduction`, `get_my_dating_introductions` | 1 re-creates the v1 forms (marked); 4 replaces act (jsonb answers) and drops the v1 read for `get_my_dating_introductions()` | `dating_mode_contracts.sql` follows (Tasks 1 and 4) |
| `supabase/tests/{dating_mode,dating_v2_identity,country_safety_config,dating_v2_setup,dating_v2_eligibility}_contracts.sql`, `dating_rls_canary.sql` | 1 (v2 introductions, the tick, five flags, freshness, canary W5a), 2 (canary generation + S-4 follows calls), 4 (C1 proof on the v2 read and act, canary W5b, setup G3), 8 (canary W5c) | exact edits; never a loosened check |
| `scripts/concurrency/dating_kill_switch_races.sh` | 1 (v2 introductions), 3 (two ticks), 4 (simultaneous interest) | `dating_generation_runs` joins the delay triggers |
| `supabase/sql/dev_enable_spec2_dating_flags.sql` | 1 | no alignment flag; `introductions_v2` active with `DEV-` refs |
| `scripts/local_pg_grants.sql` | 1, 4, 8 | one `\i` block each (`grants_line.py`) |
| `.github/workflows/tests.yml`, `supabase/config.toml` | 5 | the Deno test and type check; `[functions.dating-photo-urls] verify_jwt = true` |
| `lib/features/dating/today/*` | 6 creates the data, memory, providers and reasons; 7 creates the two screens; 10 edits `today_screen.dart` (the Widen row) | |
| `lib/features/dating/card/dating_card.dart` (W3) | 6 | captions as spoken labels only |
| `lib/features/dating/dating_device_wipes.dart` (W3a) | 6 | one more entry, `spec2.dating_photos` |
| `lib/features/dating/routes/dating_routes.dart` (W3a) | 7 (Today, the moment), 9 (never-introduce), 10 (Other countries) | each route through `datingRoute()` |
| `lib/features/dating/routes/dating_setup_steps.dart` (W3a) | 7 | the `today` return place |
| `lib/features/dating/section/dating_section.dart` (W3a) | 7 | "Open Today" while active |
| `lib/features/dating/settings/dating_settings_screen.dart` (W3c) | 9 (the never-introduce row), 10 (the Other countries row) | |
| `lib/features/dating/data/dating_never_introduce.dart` (W4) | 9 | the two writes |
| `test/features/dating/support/{dating_fakes,dating_shell}.dart` (W3/W4) | 9 (the never-introduce writes), 10 (`FakeAbroad` in the shell) | every earlier shell test still passes |
| `test/architecture/text_scale_routes_test.dart` | 7, 9, 10 | each new route in `_audited` |
| `lib/app/documentations/user_manual/data/dating_mode_docs.dart` | 7, 10 | carry 15 |
| `lib/i10n/app_en.arb` + generated | 6, 7, 9, 10 | `arb_fragment_T{6,7,9,10}.txt` via `arb_append.py`, then gen-l10n |

### Carries → tasks

| # | Carry (`carries.md`) | Where |
|---|---|---|
| 1 | the 72 h cool-off enforced nowhere | Task 1 (`private.dating_cool_off_ends_at(uuid)`; generation's people need it over by their next drop; reads and act see a side only from its drop, which is never earlier: contract D `1 the cool-off past the next drop (carry 1)`, F; mutant `carry1_cool_off_ignored`) |
| 2 | NULL identity or seeking is not introducible | Task 1 (`dating_person` normalises; `dating_admits` is `coalesce(…, false)`: contract C `carry 2 …` both orders; mutant `carry2_null_admits`) |
| 3 | generation still enforces each country's same-gender rule | Task 1 (filter 4 reads the flag, the Dating country and a fresh context: contract E `Ghana, whatever the rows say (carry 3)`) |
| 4 | a never-introduce pair never generated or matched, kept rows included, forever | Tasks 1, 2, 4 (`dating_pair_safe` reads every row, kept or shown: contract D, G2, K; mutants `carry4_kept_ignored`, `kept_pair_generated`, `act_unsafe_kept_open`) |
| 5 | a man–woman match where one member moved country and hasn't re-answered is closed by a switch | Ruling R-26 (W6a) |
| 6 | per-candidate eligibility cost: set-based, bounded | Task 2 (people read once per partition into a temp table, at most `partition_people_max`; at most `scan_limit` candidates scanned per person; pair checks only on admitted candidates) |
| 7 | gate 8 only for the person's own requests (R-17); verification state gates being introduced | Task 1 (`dating_candidate_is_current` keeps eligibility with gate 8 for the caller only, the age gate and readiness (identity verified); contract D `1 the age check revoked (carry 7)`, `1 identity not verified (carry 7)`; K: another phone's act changes nobody's introduction, mutant `r17_act_device_late`); Task 4 (`act_device_late`) |
| 8 | v1 introductions/matches reads must call the device check | Task 1 (the v1 read re-created with the check; the v1 match read dropped, Ruling R-2; contract K `another phone read the introductions (carry 8)`); Task 4 (every new read checks the phone first) |
| 9 | the age re-check keys on photo upload time | Ruling R-27 (W5 adds no photo/decision linkage) |
| 10 | `get_my_dating_verification` untrusted branch reads 1 day; widen to 72 h | Task 1 (re-created, one marked line; contract J; mutant `carry10_one_day`) |
| 11 | parallel starts pass the vendor-session limit (cost only) | Ruling R-27 (deferred, cost only) |
| 12 | `dating-photo-urls` runs the device check before minting; approved/clear only | Tasks 4, 5 (`dating_photo_keys_for_viewer` checks the phone first; contract O; Deno `no install id on the phone…`; mutants `keys_no_device`, `viewable_any`, `no_device_asks_anyway`, `hash_not_passed`) |
| 13 | cards honour `photos_after_mutual`; captions on the card; a derived `viewable` flag | Tasks 4, 6 (`private.dating_photo_viewable`; the card lists no photo while kept for mutual interest; contract L; captions as spoken labels, Ruling R-13; mutants `card_after_mutual_photos`, `caption_unspoken`) |
| 14 | G3 allow-list of photo readers; `dating_photo_keys_for_viewer` | Task 4 (`edit_tests_T4.py` adds the card builder and the keys to setup's G3 list, deliberately) |
| 15 | the manual's W5 passages | Tasks 7 and 10 (`edit_T7_docs.py`, `edit_T10.py`: introductions, matches, never-introduce, other countries) |
| 16 | the never-introduce screen reuses the kept-count line; re-adding indistinguishable; add from any phone, remove gated | Task 9 (`dating_neverIntroduceKept`; "Added." for any answer; the add ungated, remove's `reverify_device` → the re-check line; mutants `never_kept_hidden`, `never_added_differs`) |
| 17 | a country leaves other people's lists when its same-gender rule tightens | Ruling R-29 (done in W1d's switch); Task 8 contract U pins that the read never offers a refused country |
| 18 | a future export must respect `kept_at` | Ruling R-28 (W9) |

### Rulings (the spec wins over this plan; each records its cost if wrong)

- **Ruling R-1:** W5a re-creates the v1 `act_on_dating_introduction` and `get_my_dating_introductions(integer)` from their live bodies, changing only what names a dropped object plus carries 4 and 8, per-side visibility and no "New mutual match" push (§9 R12: the same migration that drops must re-create); W5b replaces act whole (fixed jsonb answers, never a raised refusal) and drops the v1 read for `get_my_dating_introductions()` v2 (§4.9 W5b). Cost if wrong: one extra re-creation.
- **Ruling R-2:** the v1 `get_my_dating_matches(integer)` is dropped in W5a (carry 8): it sent another person's name to any phone and nothing calls it; W6a creates `get_my_dating_matches(boolean)`. The match moment reads the name from Today. Cost if wrong: none in the app.
- **Ruling R-3 (owner-visible):** §2.3's 14-day freshness reads the later of the session context's `checked_at` and the trusted phone's last use (written at most daily by every device-checked call), because nothing writes the context until W8b's `dating-device-check`. A same-gender introduction needs a context checked within 7 days that allows it (§2.3: never while the server can't know where the person is), so **no same-gender introduction is made until W8b** ships. In development, a tester can call `record_dating_session_context`. Cost if wrong: UK same-gender introductions start with W8b.
- **Ruling R-4:** the cool-off is `private.dating_cool_off_ends_at(uuid)` (account creation + the config's `cool_off_hours`, default 72); generation needs it over by the person's next drop (§5.2 1); every read and act shows a side only from its drop, which generation never sets earlier. `get_dating_home()` keeps its own equal computation (not re-created in W5). Cost: two places say 72 h.
- **Ruling R-5:** the hard filters are one implementation over a person row: `dating_admits` (filters 2–10, both directions, pure), `dating_pair_safe` (11–13), `dating_pair_new` (14), `dating_person_current` (1, and 15 from W5c). `dating_pair_passes_hard_filters` and generation call the same functions. Cost: none.
- **Ruling R-6:** one introduction per pair ever (`UNIQUE (pair_key)`); a development database keeps the newest row of a pair (production has none). A match gets its `pair_key` from a `BEFORE INSERT` trigger (the introduction's, else the two members'), so no writer can leave it out. Cost: none.
- **Ruling R-7:** `partition_key` is `text` (`GH`, or `GH:AA` when a country splits by region, §5.5), not `char(2)` as §4.3 says. Cost: one column type.
- **Ruling R-8:** generation's refusals keep W1's order (the generation flag, the exclusion key's fingerprint, a missing key, the field key's fingerprint), then Dating itself and the config, so W1's contracts keep their meaning; every refusal is counted (`dating.generation.skipped`). Cost: none.
- **Ruling R-9:** each pick raises the candidate's exposure for the rest of the run (§5.4 8 says the candidate's); the chooser's capacity falls with the candidate's. The band is the spec's: a cross-border candidate shares no region, so it only reaches a person whose best local candidate is no closer (contract G2 pins it). Cost if wrong: one line.
- **Ruling R-10:** with no reason to cite, a card shows `same_region` only when it is true, `across_borders` across a border, else only the closing line (never a false "same region"). `family_same` is three ids (`family_same_early`, `…_when_serious`, `…_our_decision`) so the app needs no value. Cost: three ids.
- **Ruling R-11 (owner-visible):** the moment's "Say hello" shows only once W6a's chat route exists (`kDatingChatReady`, flipped in W6a); until then it offers "Later". Cost: the moment is a dead end until W6a in development.
- **Ruling R-12 (owner decision):** the card's overflow "More" (Report, Block) arrives with W7a's report sheet; W5b cards carry Interested and Not for me only (Dating is off in production until W7). Alternative: add Block now through the kept `block_dating_introduction` (one more task). Cost if wrong: a development tester can't block from a card until W7a.
- **Ruling R-13:** §3.4 (photos announced with captions) and §4.3 (captions shown only to the owner) agree as: a caption is its photo's spoken label on the other person's card, never printed there. Cost: none.
- **Ruling R-14 (owner-visible):** the dragnet's third input (first messages) comes from W6a's messages; until then `private.dating_first_messages` answers unknown and the rule waits (never fires on a missing input; contract Q stands the input in). The duplicate-opener, money-ask and sexual-pressure signals land with W6b's data, location mismatch with W8b's (a function never names a table a later batch creates). W5c builds the queue, the dragnet with its throttle, and several accounts on one phone. Cost: those four signals start later; Dating is off in production.
- **Ruling R-15:** the signals run once per tick for every active person (not per country), so no signal reads a country; the case writer records the phone's HMAC the case carries (§4.3) and decides nothing.
- **Ruling R-16:** fairness counts people with an active enrolment, their introductions created in the four weeks before the report's week, matched ones for the mutual rate; cohorts region, age band, gender group (non-binary and specific terms together), only at n ≥ 50; the top decile is its own row; reruns overwrite the week's rows; flags go to W7b's console (no automatic change). Cost: none.
- **Ruling R-17:** the queue and the fairness reports are the service role's (W7b's console through its edge function, §4.5) and never a client's; no routing column (S-5).
- **Ruling R-18:** Other countries: `get_dating_abroad_options()` returns eligibility and the open countries the person may join (never one whose same-gender rule refuses their answers); the cross-border card shows on every turn-on (it is the confirmation); turning off never asks and is never refused. D3's disabled row stays (setup comes before verification); settings and Widen offer the screen once eligible. Cost: one tap from D3.
- **Ruling R-19:** the never-introduce add is never device-gated (it reduces exposure) and always says "Added."; remove is the server's check (`reverify_device` → the re-check line); kept rows are counted only (W4 C-1, I-6). Offline, Add waits (§3.15).
- **Ruling R-20:** a profile change that is not a filter input (the family question, the name, what is shown) no longer ends the person's open introductions (`invalidate_dating_on_profile_change` re-created, marked); a preference change still does (all its columns are filter inputs; W1 behaviour). Cost if wrong: a name change would leave a card showing the new name (it reads live).
- **Ruling R-21:** on an account change Today drops a held "Not for me" without sending it; closing the screen sends it (§3.4). Cost: none.
- **Ruling R-22:** Today's body is a column (at most nine cards), so every card is built for screen readers and tests. Cost: none at this size.
- **Ruling R-23:** Today's payload carries the person's own first name (`my_name`) for the moment's own avatar. Cost: one key.
- **Ruling R-24:** with no `dating_push_key` the digest sends nothing, is counted (`dating.digest.push_key_missing`) and never raises (a cron). Cost: none.
- **Ruling R-25:** W5a's migration is not re-applied once W5b's is (act's return type changes), so W5a's mutant sets run in Tasks 1–2 only; W5b's and W5c's run in their tasks and at their gates.
- **Ruling R-26 (owner-visible):** carry 5 (a man–woman match closed by a switch when one member moved country and hasn't re-answered) moves to W6a, which owns closing matches; the side effect closes, never exposes. Cost: in development, such a match closes on a switch.
- **Ruling R-27:** carry 9 is untouched (W5 adds no photo/decision linkage); carry 11 stays deferred (cost only).
- **Ruling R-28:** carry 18 (export respects `kept_at`) is W9's.
- **Ruling R-29:** carry 17 is done (W1d's `apply_same_gender_switch` step 3 prunes other people's lists in sorted lock order); contract U pins the read's side.
- **Ruling R-30:** the canary's S-4 scan follows calls (as it said W5 would): every function that names a decrypting one decrypts; only the export builder (W9) and the switch's publisher (a count, PF-F13) may be the service role's.
- **Ruling R-31:** `dating_photo_keys_for_viewer` mirrors the device check (trusted, or no phone bound yet; a missing hash on a bound account refused); the edge function answers `device_unavailable` when the phone has no install id (W4 I-4).
- **Ruling R-32 (owner-visible):** the Dating section's active card shows "Open Today" (plan copy) rather than the day's cards inside Me (§3.1); Today is its own route. Cost: one tap.
- **Ruling R-33:** the moment opens when Today opens (the Me section reads no Today).
- **Ruling R-34:** Widen's editors return to Today (`today` joins W3's return places).
- **Ruling R-35:** an equivalent mutant is retired with its reason: the never-introduce screen's D8 clear is also done by the lock gate (it rebuilds every Dating page on an account change), so `never_d8_keeps_text` can't fail a test; the screen keeps its own clear (belt and braces).

## Interfaces this plan consumes (read from the current code)

- **Spec 1:** `public.account_age(uuid)`, `public.users (created_at, timezone, path)`, `private.attune_environment()`, `private.assert_development_project()`, `public.app_setting(text)`, `private.bump_metric_internal(text)`, `public.scheduled_notifications` and its quiet-hours guard, `PhoneCountries`, `PhoneCountryPickerSheet` (sign-in's country list, read only), `FlowPrimaryButton`, `FlowSecondaryButton`, `FlowTextLink`, `FlowErrorLine`, `AllowLargeText`, `InfoRowWidget`, `MyDateFormat`, `DeviceWipeRegistry`; test helpers `expectFlowGoldens`, `expectFlowGuidelines`, `pumpFlowScreen`, `tapInReach`, `scripts/large_text_audit.py`.
- **S2 W1–W4 (live):** `public.dating_eligibility(uuid, text)`, `public.dating_candidate_is_current(uuid)`, `public.dating_age_gate_holds(uuid)`, `public.dating_profile_ready(uuid)`, `public.dating_never_introduce_excludes(uuid, uuid)`, `public.dating_former_partner_excluded(uuid, uuid)`, `public.dating_phone_hmac_for_user(uuid)`, `public.dating_pair_key(uuid, uuid)`, `private.dating_field_decrypt(bytea)`, `private.dating_same_gender_on(text)`, `private.dating_first_drop_at(uuid, timestamptz)`, `private.dating_profile_plain(jsonb, jsonb)`, `private.dating_open_countries()`, `private.dating_queue_me_update(uuid, text, text)`, `private.dating_push_source_key(uuid, text, date)`, `private.dating_device_state(uuid, text)`, `private.dating_lock_setup(uuid)`, `public.dating_require_trusted_device()`, `public.check_dating_rate_limit(text, int, interval)`, `public.claim_dating_idempotency(text, text)`, `public.set_dating_open_abroad(text, char(2)[])`, `public.save_dating_family_involvement(text, text)`, `public.add_dating_never_introduce(text, text, text)`, `public.remove_dating_never_introduce(uuid)`, `public.list_dating_never_introduce()`; the tables `dating_trusted_devices`, `dating_session_context`, `dating_never_introduce (kept_at, shown_at)`, `dating_block_hmacs`, `dating_profile_photos (caption, csam_state)`; app: `DatingRpc`, `DatingActionKeys`, `datingWrite`, `DatingWrite`, `DatingCard`, `DatingCardView`, `datingListName`, `datingAccountProvider`, `datingRpcProvider`, `datingSupabaseClientProvider`, `datingOnlineProvider`, `DatingNeverIntroduceGateway`, `datingNeverIntroduceProvider`, `DatingReverifyLine`, `DatingCalmLine`, `DatingSessionMemory`, `datingRoute()`, `DatingPaths`, `DatingMotion`, `datingSheetSettings`, `DatingSheetTracker`, the shell `pumpDatingShell` / `datingShellOverrides`, `FakeNeverIntroduce`, `expectPrivateKeyboard`.

## Interfaces this plan produces (for W6 onward)

- **SQL (W5a):** type `private.dating_gen_person`; `private.dating_intro_config() → (o_version, o_config)`, `private.dating_cool_off_ends_at(uuid)`, `private.dating_last_seen_at(uuid)`, `private.dating_pair_is_man_woman(text, text)`, `private.dating_person(uuid, timestamptz, jsonb)`, `private.dating_person_current(uuid, timestamptz, jsonb)`, `private.dating_admits(gen_person, gen_person, jsonb)`, `private.dating_pair_safe(uuid, uuid, text, text)`, `private.dating_pair_new(uuid, uuid)`, `public.dating_pair_passes_hard_filters(uuid, uuid)` v2; `private.dating_open_chats(uuid, timestamptz)` (W6a re-creates it with messages and "We met"), `private.dating_capacity(uuid, timestamptz, jsonb)`, `private.dating_reasons(gen_person, gen_person) → text[]`, `private.dating_generate_partition(…)`, `public.run_dating_generation_tick(p_now timestamptz DEFAULT now(), p_country text DEFAULT NULL) → {runs:[{partition, cohort, created} | {partition, skipped} | {partition, error}]} | {skipped}`; `dating_introductions (cohort_window, partition_key, visible_from_low, visible_from_high, reasons, rank_detail)`, `dating_matches.pair_key`; config `introductions_v2`. **(W5b):** `dating_matches (low_moment_seen_at, high_moment_seen_at)`, `dating_settings (family_asked_at, quiet_note_at, digest_sent_at)`; `private.dating_photo_viewable(text, text)`, `private.dating_card(viewer, subject, introduction) → jsonb`, `private.dating_visible_introductions(uuid)`; `get_my_dating_today() → {ok, today_state, drop_at, region_name_key, my_name, cards, waiting, moments:[{match_id, display_name}], family_question, quiet_note, data_saver, widen:{min_age, max_age, scope}}`; `get_my_dating_introductions() → {ok, cards}`; `act_on_dating_introduction(p_idempotency_key, p_introduction_id, p_action) → {ok, action, matched} | {ok:false, reason: invalid|reverify_device|not_eligible|introduction_unavailable|rate_limited|busy}`; `mark_dating_match_moment_seen(uuid)`, `dismiss_dating_today_note('family'|'quiet')`; `dating_photo_keys_for_viewer(p_viewer, p_kind 'introduction'|'match', p_id, p_device_hash) → {ok, photos:[{position, key}]} | {ok:false, reason: reverify_device|photos_unavailable}`; `send_dating_digests()`. **(W5c):** `dating_moderation_cases`, `dating_fairness_reports`; `private.dating_open_signal_case(uuid, text, text)`, `private.dating_first_messages(uuid, timestamptz)` (W6a re-creates it), `private.dating_dragnet_holds`, `private.dating_device_accounts_hold`, `private.dating_run_signals(timestamptz, jsonb)`, `private.dating_throttled(uuid)`, `private.dating_generation_removed(uuid, timestamptz, jsonb)` (W7a adds the report steps), `public.dating_fairness_weekly(date)`, `get_dating_abroad_options() → {ok, eligible, countries:[{code, on}]}`.
- **Edge:** `dating-photo-urls` (`verify_jwt = true`): `{kind, id}` → `{ok:true, photos:[{position, url}]}` | `{ok:false, reason: invalid|device_unavailable|reverify_device|photos_unavailable|busy}`; URLs live 60 s.
- **App:** `lib/features/dating/today/{dating_today.dart (DatingToday, DatingTodayState, DatingIntroCard, DatingMoment, DatingActAnswer, DatingPhotoUrl), dating_today_repository.dart (DatingTodayGateway, DatingTodayRepository), dating_today_providers.dart (datingTodayGatewayProvider, datingTodayProvider, datingPhotoFetchProvider, loadDatingPhotos), dating_photo_memory.dart (DatingPhotoMemory), dating_reasons.dart (datingReasonLine, datingReasonLines), today_screen.dart (DatingTodayScreen, showDatingWidenSheet, kDatingCardMotion, kDatingUndo, kDatingUndoScreenReader), match_moment_screen.dart (DatingMatchMomentScreen, kDatingMomentSettle, kDatingChatReady)}`; `lib/features/dating/settings/{never_introduce_screen.dart (DatingNeverIntroduceScreen), dating_abroad.dart (DatingAbroadOptions, DatingAbroadGateway, datingAbroadGatewayProvider, datingAbroadProvider), abroad_screen.dart (DatingAbroadScreen, datingCountryName)}`; `DatingPaths.today`, `.match(id)`, `.stepFromToday(step)`, `.neverIntroduce`, `.abroad`; `DatingCard.captions`; the wipe entry `spec2.dating_photos`.

## File map

**W5a.** Task 1 creates `$D/{suite.sh, grants_line.py, dmut.py, anchor.py, marked_diff.py, mutate.py, before_w5a/, sql-baseline.txt, flutter-baseline.txt, analyze-baseline.txt, mig_T1_head.sql, mig_T1_tail.sql, build_mig_T1.py, edit_tests_T1.py, mut_T1.py}`, `supabase/migrations/20261119100000_dating_v2_matching.sql`, `…100010_…_grants.sql`, `supabase/tests/dating_v2_matching_contracts.sql`; deletes `supabase/tests/dating_alignment_contracts.sql`; modifies `supabase/tests/{dating_v2_identity,country_safety_config,dating_v2_setup,dating_v2_eligibility,dating_mode}_contracts.sql`, `dating_rls_canary.sql`, `scripts/concurrency/dating_kill_switch_races.sh`, `supabase/sql/dev_enable_spec2_dating_flags.sql`, `scripts/local_pg_grants.sql`. Task 2 creates `$D/{mig_T2_generation.sql, contract_T2.sql, splice_T2.py, edit_tests_T2.py, mut_T2.py}`; rebuilds the migration; modifies the contract, the twin, the canary. Task 3 creates `$D/edit_races_T3.py`; modifies the race script.

**W5b.** Task 4 creates `supabase/migrations/20261119110000_dating_v2_today.sql`, `…110010_…_grants.sql`, `$D/{before_w5b/, mig_T4_head.sql, mig_T4_tail.sql, build_mig_T4.py, contract_T4_K.sql, contract_T4.sql, splice_T4.py, edit_tests_T4.py, edit_races_T4.py, mut_T4.py}`; modifies the contract, `dating_mode_contracts.sql`, the canary, `dating_v2_setup_contracts.sql`, the race script, `scripts/local_pg_grants.sql`. Task 5 creates `supabase/functions/dating-photo-urls/{handler,index,handler.test}.ts`, `$D/{denomut.py, edit_ci_T5.py, mut_T5.py}`; modifies `.github/workflows/tests.yml`, `supabase/config.toml`. Task 6 creates `lib/features/dating/today/{dating_today,dating_today_repository,dating_photo_memory,dating_today_providers,dating_reasons}.dart`, `test/features/dating/support/dating_today_fakes.dart`, `test/features/dating/today/dating_today_data_test.dart`, `test/architecture/dating_v1_matching_gone_test.dart`, `$D/{edit_T6.py, arb_fragment_T6.txt, mut_T6.py}`; modifies `dating_card.dart`, `dating_device_wipes.dart`, the ARB; deletes `lib/features/dating/data/models/dating_introduction.dart`. Task 7 creates `lib/features/dating/today/{today_screen,match_moment_screen}.dart`, `test/features/dating/today/today_screen_test.dart` and its goldens, `$D/{edit_T7.py, edit_T7_docs.py, arb_fragment_T7.txt, mut_T7.py}`; modifies `dating_routes.dart`, `dating_setup_steps.dart`, `dating_section.dart`, `text_scale_routes_test.dart`, `dating_routes_test.dart` (its C-1 guard pumps Today with a fake), `dating_mode_docs.dart`, the ARB.

**W5c.** Task 8 creates `supabase/migrations/20261119120000_dating_v2_signals.sql`, `…120010_…_grants.sql`, `$D/{before_w5c/, mig_T8_head.sql, mig_T8_tail.sql, build_mig_T8.py, contract_T8.sql, splice_T8.py, edit_tests_T8.py, mut_T8.py}`; modifies the contract, the canary, `scripts/local_pg_grants.sql`. Task 9 creates `lib/features/dating/settings/never_introduce_screen.dart`, `test/features/dating/settings/never_introduce_test.dart` and its goldens, `$D/{edit_T9.py, arb_fragment_T9.txt, mut_T9.py}`; modifies `dating_never_introduce.dart`, `dating_fakes.dart`, `dating_routes.dart`, `dating_settings_screen.dart`, `text_scale_routes_test.dart`, `dating_settings_rows_test.dart` (W3 checked the row was absent), the four `dating_settings_bottom` goldens (one more row), the ARB. Task 10 creates `lib/features/dating/settings/{dating_abroad,abroad_screen}.dart`, `test/features/dating/settings/abroad_test.dart` and its goldens, `$D/{edit_T10.py, arb_fragment_T10.txt, mut_T10.py}`; modifies `dating_routes.dart`, `dating_settings_screen.dart`, `today_screen.dart`, `dating_shell.dart`, `dating_fakes.dart`, `text_scale_routes_test.dart`, `dating_mode_docs.dart`, the ARB.

**Not edited:** `lib/main.dart`, `lib/app/app.dart`, `lib/home/home_screen.dart`, `quick_exit_service.dart`, `auth_provider.dart`, every Spec 1 file, every applied migration, `scripts/local_pg_setup.sh`, every edge function but `dating-photo-urls`, `get_dating_home()`, `get_dating_profile_preview()`, Games, Opinions, `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`.

---


## Batch W5a — generation

### Task 1: The W5 tool folder, the baselines, migration `dating_v2_matching` (schema, config, hard filters, the re-created functions) and its contract (§4.9 W5a, §4.3, §4.10, §5.1, §5.2, §5.11, §2.3, §2.4, §2.8, §7.1, §7.5 mutants 2, 3, 20; §9 R12; carries 1–4, 7, 8, 10; R-1–R-8, R-25, R-30)

**Files:**
- Create: `$D/{mutate.py, before_w5a/, mig_T1_head.sql, mig_T1_tail.sql, build_mig_T1.py, edit_tests_T1.py, mut_T1.py}` (and `suite.sh`, `grants_line.py`, `dmut.py`, `anchor.py`, `marked_diff.py` copied from W4), `supabase/migrations/20261119100000_dating_v2_matching.sql`, `supabase/migrations/20261119100010_dating_v2_matching_grants.sql`, `supabase/tests/dating_v2_matching_contracts.sql`
- Delete: `supabase/tests/dating_alignment_contracts.sql` (replaced, §4.10)
- Modify: `supabase/tests/{dating_v2_identity,country_safety_config,dating_v2_setup,dating_v2_eligibility,dating_mode}_contracts.sql`, `supabase/tests/dating_rls_canary.sql`, `scripts/concurrency/dating_kill_switch_races.sh`, `supabase/sql/dev_enable_spec2_dating_flags.sql`, `scripts/local_pg_grants.sql`

**Interfaces:**
- Consumes: the live bodies of the nine functions in Step 4 (read from `attune_spec3a`); W1's `dating_never_introduce_excludes`, `dating_former_partner_excluded`, `dating_phone_hmac_for_user`, `dating_field_decrypt`, `dating_same_gender_on`; W2's `dating_eligibility` (gate 8 only for the caller, R-17); W4b's `dating_trusted_devices`, `dating_require_trusted_device()`.
- Produces: every W5a SQL interface under "Interfaces this plan produces" except generation's (Task 2). `dating_pair_passes_hard_filters(a, b)` is true only when filters 1–14 hold both ways now under the active config; `private.dating_admits(a, b, cfg)` is pure and symmetric; the v1 `act_on_dating_introduction` raises `reverify_device` (42501) from another phone before anything changes.

- [ ] **Step 1: Check the target and the free timestamps**

```bash
psql -X -d attune_spec3a -Atc 'select current_database()'
ls supabase/migrations | sort | tail -1
git rev-parse --short HEAD
```

Expected: `attune_spec3a`; `20261109110010_dating_v2_trusted_devices_grants.sql`; `a2d22add` (or a later commit of the owner's: then read `git log --oneline a2d22add..HEAD` and say in the report what changed). If the last migration is at or after `20261119100000`, shift the six W5 timestamps (Global Constraints).

- [ ] **Step 2: The tool folder**

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5; mkdir -p $D/mut
for f in suite.sh grants_line.py dmut.py anchor.py marked_diff.py; do cp .superpowers/sdd/2026-11-09-spec2-w4/$f $D/$f; done
sed -e 's/W4_DB/W5_DB/g' -e 's/Spec 2 W4 mutation runner/Spec 2 W5 mutation runner/' .superpowers/sdd/2026-11-09-spec2-w4/mutate.py > $D/mutate.py
chmod +x $D/suite.sh
grep -c W5_DB $D/mutate.py
```

Expected: `2`.

- [ ] **Step 3: The baselines**

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5
$D/suite.sh attune_spec3a > $D/sql-baseline.txt; echo "$(grep -c '^PASS' $D/sql-baseline.txt) PASS, $(grep -c '^FAIL' $D/sql-baseline.txt) FAIL"
flutter analyze --no-pub lib test > $D/analyze-baseline.txt 2>&1; tail -1 $D/analyze-baseline.txt
flutter test --reporter compact > $D/flutter-baseline.txt 2>&1; tr '\r' '\n' < $D/flutter-baseline.txt | grep -E '^[0-9:]+ \+[0-9]+' | tail -1
shasum -c .superpowers/sdd/2026-11-04-spec1-w10-accessibility-docs/w10-1.0.sha | grep -vc ': OK$'
shasum -c .superpowers/sdd/2026-11-04-spec1-w9/flag_off.sha | grep -vc ': OK$'
shasum -c .superpowers/sdd/2026-11-07-spec2-w3/latch.sha
```

Expected: `160 PASS, 14 FAIL`; `571 issues found. (ran in …)`; a last line with `+8191` and only the known flakes failing (name each in the report); `0`; `0`; `lib/home/home_screen.dart: OK`. The full run takes 12–15 minutes.

- [ ] **Step 4: Save the live bodies the migration re-creates**

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5; mkdir -p $D/before_w5a
for sig in 'public.act_on_dating_introduction(text,uuid,text)' 'public.get_my_dating_introductions(integer)' 'private.dating_exit_internal(uuid,boolean)' 'public.invalidate_dating_for_user(uuid,text)' 'public.expire_dating_introductions()' 'public.get_dating_operational_health()' 'public.dating_candidate_is_current(uuid)' 'private.dating_first_drop_at(uuid,timestamp with time zone)' 'public.get_my_dating_verification()'; do
  psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)" > "$D/before_w5a/$sig.sql"
done
ls $D/before_w5a | wc -l
```

Expected: `9`.

- [ ] **Step 5: Write the failing contract**

Create `supabase/tests/dating_v2_matching_contracts.sql` with exactly (sections A–F, K in its W5a form, J, and the marker Task 2 replaces):

```sql
-- supabase/tests/dating_v2_matching_contracts.sql
-- Spec 2 W5a (§4.3, §4.10, §5.2, §5.3, §5.7, §5.11, §7.1, §7.5 mutants 2,
-- 3, 6, 20; R12; carries 1-4, 7, 8, 10): the v1 trait objects are gone and
-- no function names one (A); the config, its caps CHECK and the production
-- DEV- guard (B); the hard filters 2-10 over person rows: symmetric over a
-- grid, a passing and a failing fixture each, NULL never admitted (C);
-- filters 1 and 11-14 on real people, kept never-introduce rows included,
-- and a stranger's phone never removes anyone (D); same-gender needs the
-- flag, both countries and fresh contexts, never in Ghana (E); the
-- cool-off and the drop time (F); the v1 read and act as W5a leaves them
-- (K); a re-check read back for 72 hours (J). Task 2 adds generation (G-I).
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_matching_contracts.sql
BEGIN;

DO $$
BEGIN
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w5-matching-key', true);
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w5-field-key-0123456789abcdef-0123', true);
END $$;
SELECT private.seed_dating_exclusion_key_fingerprint() AS seeded \gset
SELECT private.seed_dating_field_key_fingerprint() AS seeded_field \gset
INSERT INTO public.feature_flags (key, enabled)
VALUES ('dating_mode_enabled', true), ('dating_candidate_generation', true), ('dating_same_gender_matching', true)
ON CONFLICT (key) DO UPDATE SET enabled = true;
SELECT public.publish_country_config('GH', '{"dating_enabled": true, "open_regions": ["AA", "AH"]}') AS gh \gset
SELECT public.publish_country_config('GB', '{"dating_enabled": true}') AS gb \gset
UPDATE public.dating_algorithm_configs SET state = 'retired', retired_at = now() WHERE state = 'active';

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('5e500000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;
-- The device each person's phone sends (32 hex), and its stored hash.
CREATE FUNCTION pg_temp.dev(p_n text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT md5('w5-device-' || p_n);
$$;
-- A current candidate (§5.2 #1) with every answer in [o] over the defaults.
CREATE FUNCTION pg_temp.ready(p_n text, o jsonb DEFAULT '{}') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_u constant uuid := pg_temp.id(p_n);
  d constant jsonb := '{"identity": "woman", "pools": null, "seeking": ["man"], "country": "GH", "region": "AA",
    "side": null, "scope": "region", "intention": "committed", "timeline": null, "timeline_visible": true,
    "years": 30, "min": 25, "max": 40, "days": 40, "have": false, "want": "yes", "must": false, "excl": false,
    "faith": null, "importance": null, "faith_visible": false, "family": null, "abroad": [], "seen_days": 0,
    "tz": null, "open": null}'::jsonb || o;
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (v_u, '155593000' || p_n, now(), now() - make_interval(days => (d ->> 'days')::int));
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version, timezone)
  VALUES (v_u, '+155593000' || p_n, 'Match ' || p_n, 'dating', now() - make_interval(days => (d ->> 'days')::int),
          now(), '2', d ->> 'tz');
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (v_u, (current_date - make_interval(years => (d ->> 'years')::int) - interval '10 days')::date);
  INSERT INTO public.dating_enrollments (user_id, state, opted_in_at, activated_at) VALUES (v_u, 'active', now(), now());
  INSERT INTO public.dating_profiles (user_id, display_name, profile_state, moderation_state, verification_state,
    country_code, region_code, side_code, intention, marriage_timeline, timeline_visible, not_married_attested_at,
    attestation_version, children_have, children_want, family_involvement, faith_visible)
  VALUES (v_u, 'Match ' || p_n, 'active', 'approved', 'verified', d ->> 'country', d ->> 'region', d ->> 'side',
    d ->> 'intention', d ->> 'timeline', (d ->> 'timeline_visible')::boolean, now(), '2026-10-v1',
    (d ->> 'have')::boolean, d ->> 'want', d ->> 'family', (d ->> 'faith_visible')::boolean);
  INSERT INTO public.dating_preferences (user_id, min_age, max_age, region_scope, open_abroad, want_must_match,
    exclude_parents, intention_open)
  VALUES (v_u, (d ->> 'min')::int, (d ->> 'max')::int, d ->> 'scope',
    ARRAY(SELECT jsonb_array_elements_text(d -> 'abroad'))::char(2)[], (d ->> 'must')::boolean, (d ->> 'excl')::boolean,
    CASE WHEN d -> 'open' = 'null'::jsonb THEN NULL ELSE ARRAY(SELECT jsonb_array_elements_text(d -> 'open')) END);
  INSERT INTO public.dating_profile_sensitive (user_id, identity_enc, seeking_enc, faith_enc)
  VALUES (v_u,
    private.dating_field_encrypt(jsonb_build_object('identity', d ->> 'identity',
      'pools', coalesce(nullif(d -> 'pools', 'null'::jsonb), jsonb_build_array(d ->> 'identity')))),
    private.dating_field_encrypt(jsonb_build_object('seeking', d -> 'seeking')),
    CASE WHEN d ->> 'faith' IS NULL THEN NULL ELSE private.dating_field_encrypt(jsonb_build_object(
      'faith', d ->> 'faith', 'denomination', NULL, 'importance', d ->> 'importance')) END);
  INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer, moderation_state)
  SELECT v_u, n, CASE n WHEN 1 THEN 'perfect_sunday' ELSE 'ask_me_about' END, 'A matching fixture answer ' || n, 'approved'
    FROM generate_series(1, 2) AS n;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state, csam_state)
  SELECT v_u, 'w5/' || v_u || '/' || n || '.jpg', n, 'approved', 'clear' FROM generate_series(1, 2) AS n;
  INSERT INTO public.dating_age_verifications (user_id, age_method, age_result, age_vendor, age_decided_at,
    identity_method, identity_result, identity_vendor, identity_decided_at)
  VALUES (v_u, 'id', 'pass', 'contract', now(), 'liveness_compare', 'pass', 'contract', now());
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT v_u, 'w5-consent-' || p, p, 'granted', 'dating-2.0', clock_timestamp()
    FROM unnest(ARRAY['dating_terms', 'dating_opt_in', 'special_category_profile']) AS p;
  INSERT INTO public.dating_trusted_devices (user_id, device_hash, verified_at, last_seen_at)
  VALUES (v_u, encode(extensions.digest(pg_temp.dev(p_n), 'sha256'), 'hex'), now(),
          now() - make_interval(days => (d ->> 'seen_days')::int));
  RETURN v_u;
END $$;
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
    RAISE EXCEPTION 'w5:probe_undo';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'w5:probe_undo' THEN
      RAISE;
    END IF;
  END;
  RETURN coalesce(v, '<NULL>');
END $$;
-- Both orders of the single-pair predicate, as 'tt', 'ff' or a mix.
CREATE FUNCTION pg_temp.hf(p_a uuid, p_b uuid) RETURNS text LANGUAGE sql AS $$
  SELECT left(public.dating_pair_passes_hard_filters(p_a, p_b)::text, 1) || left(public.dating_pair_passes_hard_filters(p_b, p_a)::text, 1);
$$;
CREATE FUNCTION pg_temp.metric(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce((SELECT sum(c.count) FROM public.metric_counters AS c
                    WHERE c.day = (now() AT TIME ZONE 'utc')::date AND c.key = p_key), 0)::bigint;
$$;
-- A person row for the pure filters (§5.2 2-10): the base, then [o].
CREATE FUNCTION pg_temp.pr(p_n int, o jsonb DEFAULT '{}') RETURNS private.dating_gen_person LANGUAGE sql AS $$
  SELECT jsonb_populate_record(NULL::private.dating_gen_person, jsonb_build_object(
    'user_id', ('5e5f0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid,
    'country', 'GH', 'region', 'AA', 'side', NULL, 'scope', 'region', 'open_abroad', '{}'::text[],
    'age', 30, 'min_age', 25, 'max_age', 40, 'identity', 'woman', 'pools', ARRAY['woman'], 'seeking', ARRAY['man'],
    'intention', 'committed', 'timeline', NULL, 'timeline_visible', true,
    'intention_open', ARRAY['marriage', 'committed', 'companionship', 'not_sure'],
    'children_have', false, 'children_want', 'yes', 'want_must_match', false, 'exclude_parents', false,
    'faith', NULL, 'importance', NULL, 'faith_visible', false, 'family', NULL,
    'same_gender_ok', false, 'abroad_ok', true, 'hmac', md5(p_n::text), 'visible_from', now()) || o);
$$;
CREATE FUNCTION pg_temp.man(p_n int, o jsonb DEFAULT '{}') RETURNS private.dating_gen_person LANGUAGE sql AS $$
  SELECT pg_temp.pr(p_n, '{"identity": "man", "pools": ["man"], "seeking": ["woman"]}'::jsonb || o);
$$;
-- The reviewed config, active for this file (development: DEV- refs pass).
CREATE FUNCTION pg_temp.activate() RETURNS void LANGUAGE sql AS $$
  UPDATE public.dating_algorithm_configs
     SET state = 'active', activated_at = now(), product_review_ref = 'DEV-product', clinical_review_ref = 'DEV-clinical',
         fairness_review_ref = 'DEV-fairness', safety_review_ref = 'DEV-safety'
   WHERE version = 'introductions_v2';
$$;

-- =====================================================================
-- A. (§4.10, R12) The v1 trait objects are gone, no Dating function names
--    one, one introduction per pair ever, a match always carries its pair.
-- =====================================================================
DO $$
DECLARE
  v_got text;
  v_low uuid := pg_temp.id('a1');
  v_high uuid := pg_temp.id('a2');
BEGIN
  IF to_regclass('public.dating_feature_snapshots') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
                 WHERE n.nspname = 'public' AND p.proname IN ('build_dating_feature_snapshot', 'dating_has_historical_consent',
                   'dating_normalize_scalar', 'dating_alignment_score', 'dating_alignment_reasons', 'dating_component_similarity',
                   'dating_set_similarity', 'generate_dating_candidates_for_user', 'run_dating_candidate_generation',
                   'get_my_dating_matches'))
     OR EXISTS (SELECT 1 FROM public.feature_flags WHERE key = 'dating_alignment_algorithm_v1')
     OR EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'dating_introductions'
                  AND column_name IN ('display_band', 'explanation_features', 'low_summary', 'high_summary', 'internal_score',
                                      'snapshot_low_id', 'snapshot_high_id')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a v1 trait object survived W5a';
  END IF;
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY 1) INTO v_got
    FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'private')
     AND p.prosrc ~ '(dating_feature_snapshots|display_band|explanation_features|internal_score|snapshot_(low|high)_id|(low|high)_summary|dating_alignment_|build_dating_feature_snapshot|run_dating_candidate_generation|generate_dating_candidates_for_user|dating_set_similarity|dating_component_similarity|dating_normalize_scalar|dating_has_historical_consent|get_my_dating_matches)';
  IF v_got IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a function still names a dropped object (R12): %', v_got;
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dating-candidate-generation' AND command LIKE '%run_dating_candidate_generation%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the weekly v1 generation cron is still scheduled';
  END IF;
  INSERT INTO auth.users (id) VALUES (v_low), (v_high);
  INSERT INTO public.users (id, display_name) VALUES (v_low, 'A1'), (v_high, 'A2');
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, algorithm_version)
  VALUES (public.dating_pair_key(v_low, v_high), least(v_low, v_high), greatest(v_low, v_high), 'introductions_v2');
  BEGIN
    INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, algorithm_version)
    VALUES (public.dating_pair_key(v_low, v_high), least(v_low, v_high), greatest(v_low, v_high), 'introductions_v3');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pair was introduced twice';
  EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS v_got = CONSTRAINT_NAME;
    IF v_got IS DISTINCT FROM 'dating_introductions_pair_key_key' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the second introduction failed on % (expected the pair_key key)', v_got;
    END IF;
  END;
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(v_low, v_high), greatest(v_low, v_high), 'closed');
  IF (SELECT pair_key FROM public.dating_matches WHERE user_low_id = least(v_low, v_high)) IS DISTINCT FROM public.dating_pair_key(v_low, v_high) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a match was written without its pair';
  END IF;
  DELETE FROM public.dating_matches WHERE user_low_id = least(v_low, v_high);
  DELETE FROM public.dating_introductions WHERE user_low_id = least(v_low, v_high);
END $$;

-- =====================================================================
-- B. (§5.11, §4.3; mutant 20) introductions_v2 is seeded as a draft with
--    its hash; alignment_v1 is retired; daily_new_max can never exceed 3
--    (nor waiting_max 6); the matrix is symmetric; nothing is active until
--    reviewed; in production a DEV- reference can't be activated.
-- =====================================================================
DO $$
DECLARE
  v_cfg jsonb;
  v_got text;
  v_case jsonb;
  a text;
  b text;
BEGIN
  SELECT config INTO v_cfg FROM public.dating_algorithm_configs
   WHERE version = 'introductions_v2' AND config_hash = encode(extensions.digest(config::text, 'sha256'), 'hex');
  IF v_cfg IS NULL OR v_cfg ->> 'daily_new_max' <> '3' OR v_cfg ->> 'waiting_max' <> '6' OR v_cfg ->> 'cool_off_hours' <> '72'
     OR (SELECT state FROM public.dating_algorithm_configs WHERE version = 'alignment_v1') IS DISTINCT FROM 'retired' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the introductions_v2 seed or alignment_v1''s retirement is wrong';
  END IF;
  IF (private.dating_intro_config()).o_version IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a config is active before review';
  END IF;
  FOREACH v_case IN ARRAY ARRAY['{"daily_new_max": 4}', '{"daily_new_max": 5}', '{"daily_new_max": 0}', '{"waiting_max": 7}',
                                '{"daily_new_max": "3x"}']::jsonb[] LOOP
    BEGIN
      INSERT INTO public.dating_algorithm_configs (version, state, config, config_hash)
      VALUES ('w5-caps-' || md5(v_case::text), 'draft', v_cfg || v_case, md5(v_case::text));
      RAISE EXCEPTION 'CONTRACT VIOLATED: a config with % was accepted', v_case;
    EXCEPTION WHEN check_violation THEN
      GET STACKED DIAGNOSTICS v_got = CONSTRAINT_NAME;
      IF v_got IS DISTINCT FROM 'dating_algorithm_configs_caps_check' THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: % was refused by % (expected the caps check)', v_case, v_got;
      END IF;
    END;
  END LOOP;
  FOR a, b IN SELECT k, x FROM jsonb_each(v_cfg -> 'intention_matrix') AS m(k, r), jsonb_array_elements_text(m.r) AS x LOOP
    IF NOT (v_cfg -> 'intention_matrix' -> b) ? a THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the intention matrix admits % with % but not % with %', a, b, b, a;
    END IF;
  END LOOP;
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  BEGIN
    PERFORM pg_temp.activate();
    RAISE EXCEPTION 'CONTRACT VIOLATED: production activated a config with DEV- review references';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM IS DISTINCT FROM 'config:dev_review_ref' THEN RAISE; END IF;
  END;
  PERFORM set_config('app.settings.attune_environment', '', true);
  PERFORM pg_temp.activate();
  IF (private.dating_intro_config()).o_version IS DISTINCT FROM 'introductions_v2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the reviewed config is not the active one';
  END IF;
END $$;

-- =====================================================================
-- C. (§5.2 2-10; mutants 2, 3; carry 2) The pure filters over person
--    rows: admits(x, y) = admits(y, x) over a grid in which every filter
--    differs one way; each filter's passing and failing pair; NULL never.
-- =====================================================================
DO $$
DECLARE
  v_cfg constant jsonb := (private.dating_intro_config()).o_config;
  v_grid private.dating_gen_person[];
  x private.dating_gen_person;
  y private.dating_gen_person;
  v_case record;
BEGIN
  v_grid := ARRAY[
    pg_temp.pr(1), pg_temp.man(2),
    pg_temp.man(3, '{"age": 45}'), pg_temp.man(4, '{"min_age": 32}'),
    pg_temp.pr(5, '{"seeking": ["woman"]}'), pg_temp.man(6, '{"seeking": ["man"]}'),
    pg_temp.pr(7, '{"seeking": ["man", "woman"], "same_gender_ok": true}'),
    pg_temp.pr(8, '{"seeking": ["woman"], "same_gender_ok": true}'),
    pg_temp.pr(9, '{"identity": "non_binary", "pools": ["non_binary", "woman"], "seeking": ["man", "woman", "non_binary"], "same_gender_ok": true}'),
    pg_temp.man(10, '{"region": "AH"}'), pg_temp.man(11, '{"region": "AH", "scope": "country"}'),
    pg_temp.man(12, '{"side": "tema", "scope": "side"}'), pg_temp.pr(13, '{"side": "accra", "scope": "side"}'),
    pg_temp.man(14, '{"country": "GB", "region": "TLI", "open_abroad": ["GH"]}'),
    pg_temp.pr(15, '{"open_abroad": ["GB"]}'), pg_temp.pr(16, '{"open_abroad": ["GB"], "abroad_ok": false}'),
    pg_temp.man(17, '{"intention": "marriage"}'), pg_temp.pr(18, '{"intention": "companionship"}'),
    pg_temp.man(19, '{"intention_open": ["marriage"]}'),
    pg_temp.man(20, '{"want_must_match": true, "children_want": "no"}'), pg_temp.pr(21, '{"children_want": "open"}'),
    pg_temp.man(22, '{"exclude_parents": true}'), pg_temp.pr(23, '{"children_have": true}'),
    pg_temp.man(24, '{"faith": "christian", "importance": "must_share"}'), pg_temp.pr(25, '{"faith": "christian"}'),
    pg_temp.pr(26, '{"faith": "muslim"}'), pg_temp.pr(27, '{"faith": "prefer_not_to_say"}'),
    pg_temp.pr(28, '{"seeking": null}'), pg_temp.man(29, '{"identity": null, "pools": null}')];
  FOREACH x IN ARRAY v_grid LOOP
    FOREACH y IN ARRAY v_grid LOOP
      IF private.dating_admits(x, y, v_cfg) IS DISTINCT FROM private.dating_admits(y, x, v_cfg) THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: the filters are not symmetric for % and % (mutant 2)',
          right(x.user_id::text, 2), right(y.user_id::text, 2);
      END IF;
    END LOOP;
  END LOOP;
  FOR v_case IN SELECT * FROM (VALUES
    ('base pair passes', pg_temp.pr(1), pg_temp.man(2), true),
    ('2 an age outside the range', pg_temp.pr(1), pg_temp.man(3, '{"age": 45}'), false),
    ('3 a seeking set that misses the pools', pg_temp.pr(5, '{"seeking": ["woman"]}'), pg_temp.man(2), false),
    ('4 two women, both allowed', pg_temp.pr(7, '{"seeking": ["woman"], "same_gender_ok": true}'), pg_temp.pr(8, '{"seeking": ["woman"], "same_gender_ok": true}'), true),
    ('4 two women, one not allowed', pg_temp.pr(7, '{"seeking": ["woman"], "same_gender_ok": true}'), pg_temp.pr(8, '{"seeking": ["woman"]}'), false),
    ('4 a non-binary person and a man, both allowed', pg_temp.pr(9, '{"identity": "non_binary", "pools": ["non_binary"], "seeking": ["man"], "same_gender_ok": true}'), pg_temp.man(2, '{"seeking": ["non_binary"], "same_gender_ok": true}'), true),
    ('4 a non-binary person and a man, not allowed', pg_temp.pr(9, '{"identity": "non_binary", "pools": ["non_binary"], "seeking": ["man"], "same_gender_ok": true}'), pg_temp.man(2, '{"seeking": ["non_binary"]}'), false),
    ('5 across borders, both open, both 14 days', pg_temp.pr(15, '{"open_abroad": ["GB"]}'), pg_temp.man(14, '{"country": "GB", "region": "TLI", "open_abroad": ["GH"]}'), true),
    ('5 across borders, one not open', pg_temp.pr(1), pg_temp.man(14, '{"country": "GB", "region": "TLI", "open_abroad": ["GH"]}'), false),
    ('5 across borders, one account under 14 days', pg_temp.pr(16, '{"open_abroad": ["GB"], "abroad_ok": false}'), pg_temp.man(14, '{"country": "GB", "region": "TLI", "open_abroad": ["GH"]}'), false),
    ('6 another region, scope region', pg_temp.pr(1), pg_temp.man(10, '{"region": "AH"}'), false),
    ('6 another region, both scope country', pg_temp.pr(1, '{"scope": "country"}'), pg_temp.man(11, '{"region": "AH", "scope": "country"}'), true),
    ('6 another side, scope side', pg_temp.pr(13, '{"side": "accra", "scope": "side"}'), pg_temp.man(12, '{"side": "tema", "scope": "side"}'), false),
    ('6 another side, scope region', pg_temp.pr(13, '{"side": "accra"}'), pg_temp.man(12, '{"side": "tema"}'), true),
    ('7 marriage and companionship', pg_temp.man(17, '{"intention": "marriage"}'), pg_temp.pr(18, '{"intention": "companionship"}'), false),
    ('7 marriage and committed', pg_temp.man(17, '{"intention": "marriage"}'), pg_temp.pr(1), true),
    ('7 an intention not open to', pg_temp.man(19, '{"intention_open": ["marriage"]}'), pg_temp.pr(1), false),
    ('8 must match, no against yes', pg_temp.man(20, '{"want_must_match": true, "children_want": "no"}'), pg_temp.pr(1), false),
    ('8 must match, no against open', pg_temp.man(20, '{"want_must_match": true, "children_want": "no"}'), pg_temp.pr(21, '{"children_want": "open"}'), true),
    ('9 parents excluded, a parent', pg_temp.man(22, '{"exclude_parents": true}'), pg_temp.pr(23, '{"children_have": true}'), false),
    ('10 must share, the same', pg_temp.man(24, '{"faith": "christian", "importance": "must_share"}'), pg_temp.pr(25, '{"faith": "christian"}'), true),
    ('10 must share, another faith', pg_temp.man(24, '{"faith": "christian", "importance": "must_share"}'), pg_temp.pr(26, '{"faith": "muslim"}'), false),
    ('10 must share, prefer not to say', pg_temp.man(24, '{"faith": "christian", "importance": "must_share"}'), pg_temp.pr(27, '{"faith": "prefer_not_to_say"}'), false),
    ('10 must share, skipped', pg_temp.man(24, '{"faith": "christian", "importance": "must_share"}'), pg_temp.pr(1), false),
    ('carry 2 no who-to-meet', pg_temp.pr(28, '{"seeking": null}'), pg_temp.man(2), false),
    ('carry 2 no identity', pg_temp.pr(1), pg_temp.man(29, '{"identity": null, "pools": null}'), false)) AS t(why, a, b, expected) LOOP
    IF private.dating_admits(v_case.a, v_case.b, v_cfg) IS DISTINCT FROM v_case.expected
       OR private.dating_admits(v_case.b, v_case.a, v_cfg) IS DISTINCT FROM v_case.expected THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: filter fixture "%" admitted %/% (expected %)', v_case.why,
        private.dating_admits(v_case.a, v_case.b, v_cfg),
        private.dating_admits(v_case.b, v_case.a, v_cfg), v_case.expected;
    END IF;
  END LOOP;
END $$;

-- =====================================================================
-- D. (§5.2 1, 11-14; carries 4, 7; R-17) Real people, both orders: a
--    current pair passes; each failing fixture (rolled back) fails both
--    ways: paused, not seen in 14 days, the cool-off past the next drop,
--    hidden by travel, the age check revoked, identity not verified, a
--    path off Dating; a block by id or by phone HMAC; former partners; a
--    never-introduce entry, a kept one too; introduced or matched before.
-- =====================================================================
DO $$
DECLARE
  w constant uuid := pg_temp.ready('11');
  m constant uuid := pg_temp.ready('12', '{"identity": "man", "seeking": ["woman"]}');
  v_probe constant text := format('SELECT pg_temp.hf(%L, %L)', pg_temp.id('11'), pg_temp.id('12'));
  v_case record;
  v text;
BEGIN
  IF pg_temp.hf(w, m) IS DISTINCT FROM 'tt' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a current pair does not pass the hard filters (%)', pg_temp.hf(w, m);
  END IF;
  FOR v_case IN SELECT * FROM (VALUES
    ('1 paused', 'ff', ARRAY[format('UPDATE public.dating_enrollments SET state = ''paused'', pause_reason = ''user'' WHERE user_id = %L', m)]),
    ('1 not seen in 14 days', 'ff', ARRAY[format('UPDATE public.dating_trusted_devices SET last_seen_at = now() - interval ''15 days'' WHERE user_id = %L', m)]),
    ('1 seen through the session context', 'tt', ARRAY[
       format('UPDATE public.dating_trusted_devices SET last_seen_at = now() - interval ''15 days'' WHERE user_id = %L', m),
       format('INSERT INTO public.dating_session_context (user_id, effective_tier, dating_allowed_here, same_gender_allowed_here, away_from_home, ip_resolved) VALUES (%L, 1, true, false, false, true)', m)]),
    ('1 the cool-off past the next drop (carry 1)', 'ff', ARRAY[format('UPDATE public.users SET created_at = now() WHERE id = %L', m)]),
    ('1 hidden by travel', 'ff', ARRAY[format('INSERT INTO public.dating_session_context (user_id, effective_tier, dating_allowed_here, same_gender_allowed_here, away_from_home, ip_resolved) VALUES (%L, 1, false, false, true, true)', m)]),
    ('1 the age check revoked (carry 7)', 'ff', ARRAY[format('UPDATE public.dating_age_verifications SET revoked_at = now(), revoke_reason = ''contract'' WHERE user_id = %L', m)]),
    ('1 identity not verified (carry 7)', 'ff', ARRAY[format('UPDATE public.dating_profiles SET verification_state = ''needs_review'' WHERE user_id = %L', m)]),
    ('1 a path off Dating', 'ff', ARRAY[format('UPDATE public.users SET path = ''just_me'' WHERE id = %L', m)]),
    ('11 a block', 'ff', ARRAY[format('INSERT INTO public.dating_blocks (blocker_user_id, blocked_user_id, pair_key) VALUES (%L, %L, public.dating_pair_key(%L, %L))', m, w, m, w)]),
    ('11 a block by phone HMAC', 'ff', ARRAY[format('INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac) VALUES (public.dating_phone_hmac_for_user(%L), public.dating_phone_hmac_for_user(%L))', w, m)]),
    ('12 former partners', 'ff', ARRAY[format('INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES (%L, %L, ''archived'', now() - interval ''90 days'')', w, m)]),
    ('13 on the never-introduce list', 'ff', ARRAY[format('INSERT INTO public.dating_never_introduce (owner_user_id, phone_hmac, last_two) VALUES (%L, public.dating_phone_hmac_for_user(%L), ''12'')', w, m)]),
    ('13 kept on the list from before (carry 4)', 'ff', ARRAY[format('INSERT INTO public.dating_never_introduce (owner_user_id, phone_hmac, last_two, kept_at) VALUES (%L, public.dating_phone_hmac_for_user(%L), ''12'', now() - interval ''1 day'')', m, w)]),
    ('14 introduced before', 'ff', ARRAY[format('INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version) VALUES (public.dating_pair_key(%L, %L), least(%L::uuid, %L::uuid), greatest(%L::uuid, %L::uuid), ''passed'', ''introductions_v2'')', w, m, w, m, w, m)]),
    ('14 matched before', 'ff', ARRAY[format('INSERT INTO public.dating_matches (user_low_id, user_high_id, state, closed_reason) VALUES (least(%L::uuid, %L::uuid), greatest(%L::uuid, %L::uuid), ''closed'', ''unmatched'')', w, m, w, m)])
  ) AS t(why, expected, setup) LOOP
    v := pg_temp.probe(v_case.setup, v_probe);
    IF v IS DISTINCT FROM v_case.expected THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: hard filter fixture "%" answered % (expected %)', v_case.why, v, v_case.expected;
    END IF;
  END LOOP;
  IF pg_temp.hf(w, m) IS DISTINCT FROM 'tt' THEN
    RAISE EXCEPTION 'fixture: a probe was not undone';
  END IF;
END $$;

-- =====================================================================
-- E. (§2.4, §5.2 4; mutant 3; carry 3) Same-gender needs the global flag,
--    both Dating countries and both people's fresh contexts (7 days), and
--    is never made in Ghana, whatever a row says (generation is the
--    backstop for the writers' refusal).
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('21', '{"country": "GB", "region": "TLI", "seeking": ["woman"]}');
  b constant uuid := pg_temp.ready('22', '{"country": "GB", "region": "TLI", "seeking": ["woman"]}');
  g1 constant uuid := pg_temp.ready('23', '{"seeking": ["woman"]}');
  g2 constant uuid := pg_temp.ready('24', '{"seeking": ["woman"]}');
  v_ctx constant text := 'INSERT INTO public.dating_session_context (user_id, effective_tier, dating_allowed_here, same_gender_allowed_here, away_from_home, ip_resolved, checked_at) VALUES (%L, 3, true, %L, false, true, now() - %L::interval)';
  v_case record;
  v text;
BEGIN
  FOR v_case IN SELECT * FROM (VALUES
    ('both allowed and fresh in the UK', 'tt', a, b, ARRAY[format(v_ctx, a, true, '1 day'), format(v_ctx, b, true, '6 days')]),
    ('no context', 'ff', a, b, ARRAY[format(v_ctx, a, true, '1 day')]),
    ('a context 8 days old', 'ff', a, b, ARRAY[format(v_ctx, a, true, '1 day'), format(v_ctx, b, true, '8 days')]),
    ('not allowed where one is', 'ff', a, b, ARRAY[format(v_ctx, a, true, '1 day'), format(v_ctx, b, false, '1 day')]),
    ('the global flag off', 'ff', a, b, ARRAY[format(v_ctx, a, true, '1 day'), format(v_ctx, b, true, '1 day'),
       'UPDATE public.feature_flags SET enabled = false WHERE key = ''dating_same_gender_matching''']),
    ('Ghana, whatever the rows say (carry 3)', 'ff', g1, g2, ARRAY[format(v_ctx, g1, true, '1 day'), format(v_ctx, g2, true, '1 day')])
  ) AS t(why, expected, x, y, setup) LOOP
    v := pg_temp.probe(v_case.setup, format('SELECT pg_temp.hf(%L, %L)', v_case.x, v_case.y));
    IF v IS DISTINCT FROM v_case.expected THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: same-gender fixture "%" answered % (expected %)', v_case.why, v, v_case.expected;
    END IF;
  END LOOP;
END $$;

-- =====================================================================
-- F. (§2.8, §5.3; carry 1) The cool-off ends 72 hours (the config's
--    hours) after the account was made; the drop is 19:00 in the person's
--    own zone when it is a real zone, else the country's.
-- =====================================================================
DO $$
DECLARE
  u constant uuid := pg_temp.ready('31', '{"days": 1, "tz": "Africa/Lagos"}');
  x constant uuid := pg_temp.ready('32', '{"tz": "Mars/Olympus"}');
  v_made timestamptz;
  v_at constant timestamptz := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + interval '3 hours 17 minutes';
BEGIN
  SELECT created_at INTO v_made FROM public.users WHERE id = u;
  IF private.dating_cool_off_ends_at(u) IS DISTINCT FROM v_made + interval '72 hours'
     OR pg_temp.probe(ARRAY['UPDATE public.dating_algorithm_configs SET config = config || ''{"cool_off_hours": 24}'' WHERE version = ''introductions_v2'''],
                      format('SELECT private.dating_cool_off_ends_at(%L) = %L::timestamptz + interval ''24 hours''', u, v_made)) IS DISTINCT FROM 'true'
     OR private.dating_cool_off_ends_at(pg_temp.id('f9')) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the cool-off does not end at account creation + the config''s hours';
  END IF;
  IF (private.dating_first_drop_at(u, v_at) AT TIME ZONE 'Africa/Lagos')::time IS DISTINCT FROM time '19:00'
     OR (private.dating_first_drop_at(x, v_at) AT TIME ZONE 'Africa/Accra')::time IS DISTINCT FROM time '19:00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the drop is not 19:00 in the person''s own zone (or the country''s for an unknown zone)';
  END IF;
  IF private.dating_person_current(u, v_at, (private.dating_intro_config()).o_config)
     OR NOT private.dating_person_current(u, v_at + interval '3 days', (private.dating_intro_config()).o_config) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a day-old account is a candidate before its cool-off, or not after it (carry 1)';
  END IF;
END $$;

-- =====================================================================
-- K. (§4.10; carries 4, 8; R-17) The v1 read and act as W5a leaves them
--    (W5b replaces both): the caller's own trusted phone first, so another
--    phone reads nothing and changes nobody's introduction; nothing before
--    this side's drop; a kept never-introduce entry ends the pair; mutual
--    interest makes one match and queues no push.
-- =====================================================================
DO $$
DECLARE
  w constant uuid := pg_temp.ready('41');
  m constant uuid := pg_temp.ready('42', '{"identity": "man", "seeking": ["woman"]}');
  k constant uuid := pg_temp.ready('43', '{"identity": "man", "seeking": ["woman"]}');
  v_wm uuid;
  v_wk uuid;
  v text;
  v_pushes bigint := (SELECT count(*) FROM public.scheduled_notifications);
BEGIN
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version,
                                           visible_from_low, visible_from_high)
  VALUES (public.dating_pair_key(w, m), least(w, m), greatest(w, m), 'generated', 'introductions_v2', now() - interval '1 hour', now() - interval '1 hour')
  RETURNING id INTO v_wm;
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version,
                                           visible_from_low, visible_from_high)
  VALUES (public.dating_pair_key(w, k), least(w, k), greatest(w, k), 'generated', 'introductions_v2', now() - interval '1 hour', now() - interval '1 hour')
  RETURNING id INTO v_wk;
  v := pg_temp.call(w, pg_temp.dev('41'), 'SELECT count(*) FROM public.get_my_dating_introductions(20)');
  IF v IS DISTINCT FROM '2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the person''s own phone reads % introductions (expected 2)', v;
  END IF;
  -- Carry 8: another phone (or none) reads nothing.
  IF pg_temp.call(w, pg_temp.dev('99'), 'SELECT count(*) FROM public.get_my_dating_introductions(20)') IS DISTINCT FROM '0'
     OR pg_temp.call(w, NULL, 'SELECT count(*) FROM public.get_my_dating_introductions(20)') IS DISTINCT FROM '0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another phone read the introductions (carry 8)';
  END IF;
  -- R-17: acting from another phone is refused before anything changes.
  v := pg_temp.call(w, pg_temp.dev('99'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('k-stranger'), v_wm));
  IF v NOT LIKE '42501:reverify_device%' OR (SELECT state FROM public.dating_introductions WHERE id = v_wm) <> 'generated' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another phone''s act answered % and left the introduction %', v,
      (SELECT state FROM public.dating_introductions WHERE id = v_wm);
  END IF;
  -- Not before this side's drop.
  UPDATE public.dating_introductions SET visible_from_high = now() + interval '1 hour', visible_from_low = now() + interval '1 hour' WHERE id = v_wk;
  IF pg_temp.call(w, pg_temp.dev('41'), 'SELECT count(*) FROM public.get_my_dating_introductions(20)') IS DISTINCT FROM '1'
     OR pg_temp.call(w, pg_temp.dev('41'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('k-early'), v_wk))
        NOT LIKE '22023:introduction_unavailable%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an introduction was read or answered before this side''s drop';
  END IF;
  -- Carry 4: a kept never-introduce entry ends the pair at the act.
  UPDATE public.dating_introductions SET visible_from_high = now() - interval '1 hour', visible_from_low = now() - interval '1 hour' WHERE id = v_wk;
  INSERT INTO public.dating_never_introduce (owner_user_id, phone_hmac, last_two, kept_at)
  VALUES (k, public.dating_phone_hmac_for_user(w), '41', now());
  v := pg_temp.call(w, pg_temp.dev('41'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('k-kept'), v_wk));
  IF v NOT LIKE '22023:introduction_unavailable%' OR (SELECT state FROM public.dating_introductions WHERE id = v_wk) <> 'generated' THEN
    -- the refusal's UPDATE is rolled back with the raise; the read hides it
    RAISE EXCEPTION 'CONTRACT VIOLATED: a kept never-introduce entry did not stop the act (%)', v;
  END IF;
  IF pg_temp.call(w, pg_temp.dev('41'), 'SELECT count(*) FROM public.get_my_dating_introductions(20)') IS DISTINCT FROM '1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a kept never-introduce pair is still read';
  END IF;
  -- Mutual interest: one match, no push (§3.13).
  PERFORM pg_temp.call(w, pg_temp.dev('41'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('k-w'), v_wm));
  v := pg_temp.call(m, pg_temp.dev('42'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('k-m'), v_wm));
  IF v IS DISTINCT FROM '' AND v IS DISTINCT FROM '<NULL>'
     OR (SELECT count(*) FROM public.dating_matches WHERE introduction_id = v_wm AND state = 'active') <> 1
     OR (SELECT count(*) FROM public.scheduled_notifications) <> v_pushes THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: mutual interest answered %, made % match(es), queued % push(es)', v,
      (SELECT count(*) FROM public.dating_matches WHERE introduction_id = v_wm),
      (SELECT count(*) FROM public.scheduled_notifications) - v_pushes;
  END IF;
END $$;

-- =====================================================================
-- J. (carry 10) A re-check waiting on an untrusted phone is read back for
--    72 hours from its submission, as the sweep keeps it.
-- =====================================================================
DO $$
DECLARE
  u constant uuid := pg_temp.ready('51');
  v jsonb;
BEGIN
  INSERT INTO public.dating_verification_sessions (user_id, kind, step, vendor, state, device_hash, created_at, expires_at, awaiting_since)
  VALUES (u, 'reverify', 'human', 'fake', 'awaiting_review', encode(extensions.digest(pg_temp.dev('59'), 'sha256'), 'hex'),
          now() - interval '50 hours', now() - interval '49 hours', now() - interval '49 hours');
  v := pg_temp.call(u, pg_temp.dev('59'), 'SELECT public.get_my_dating_verification()')::jsonb;
  IF v ->> 'device' IS DISTINCT FROM 'untrusted' OR v #>> '{session,state}' IS DISTINCT FROM 'awaiting_review' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a re-check submitted 49 hours ago is not read back (carry 10): %', v;
  END IF;
END $$;

-- (Task 2: sections G-I)

DO $$ BEGIN RAISE NOTICE 'dating_v2_matching_contracts: all held'; END $$;
ROLLBACK;
```

- [ ] **Step 6: Run it to see it fail**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_matching_contracts.sql 2>&1 | grep -m1 ERROR
```

Expected: `psql:supabase/tests/dating_v2_matching_contracts.sql:…: ERROR:  type "private.dating_gen_person" does not exist` (the first helper that names the person row).

- [ ] **Step 7: Write the migration**

Create `$D/mig_T1_head.sql` with exactly (sections 1–5 and section 6's heading):

```sql
-- supabase/migrations/20261119100000_dating_v2_matching.sql
-- Spec 2 W5a (§4.9 W5a, §4.3, §4.10, §5.1-§5.4, §5.7, §5.11; R12; carries
-- 1-4, 6-8, 10): matching v2. The v1 trait objects go (snapshots, the
-- alignment and similarity functions, the v1 generators, the v1 match read,
-- the flag dating_alignment_algorithm_v1); introductions get their v2
-- columns and one row per pair ever (UNIQUE (pair_key)); matches get
-- pair_key (filled by a trigger, so no insert can leave it out); the
-- introductions_v2 config (§5.11) is seeded as a draft with a CHECK that
-- daily_new_max is 1-3 and waiting_max 1-6, and a production guard refuses
-- to activate a config whose review references start DEV-; the hard filters
-- are rewritten over one person row (private.dating_gen_person), so the
-- single-pair predicate and the generation run (Task 2's section) share
-- one implementation of §5.2; the 72 h cool-off is a function
-- (dating_cool_off_ends_at, carry 1); the functions that named a dropped
-- object are re-created from their live bodies (marked -- Spec 2 W5a).
-- Dating stays off: nothing here turns a flag on or activates a config.
-- Idempotent: applied twice, the second run changes nothing.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- =====================================================================
-- 1. The v1 trait objects (§4.10 Remove [W5]). No client calls any of
--    them (lib/ has no caller; the W5a contract greps). The weekly
--    generation cron goes now; Task 2's section schedules the hourly tick.
-- =====================================================================
DROP FUNCTION IF EXISTS public.generate_dating_candidates_for_user(uuid, text, text, text);
DROP FUNCTION IF EXISTS public.run_dating_candidate_generation(text);
DROP FUNCTION IF EXISTS public.build_dating_feature_snapshot(uuid, text);
DROP FUNCTION IF EXISTS public.dating_has_historical_consent(uuid);
DROP FUNCTION IF EXISTS public.dating_normalize_scalar(numeric, numeric, numeric);
DROP FUNCTION IF EXISTS public.dating_alignment_score(jsonb, jsonb, jsonb);
DROP FUNCTION IF EXISTS public.dating_alignment_reasons(jsonb, jsonb);
DROP FUNCTION IF EXISTS public.dating_component_similarity(numeric, numeric);
DROP FUNCTION IF EXISTS public.dating_set_similarity(jsonb, jsonb);
-- Carry 8 (W4 M-3): the v1 match read sent another person's name to any
-- phone; it has no caller, so it goes (W6a builds get_my_dating_matches(boolean)).
DROP FUNCTION IF EXISTS public.get_my_dating_matches(integer);
DELETE FROM public.feature_flags WHERE key = 'dating_alignment_algorithm_v1';
DELETE FROM private.flag_production_gates WHERE flag_key = 'dating_alignment_algorithm_v1';
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dating-candidate-generation') THEN
    PERFORM cron.unschedule('dating-candidate-generation');
  END IF;
END $$;

-- =====================================================================
-- 2. Introductions v2 (§4.3): no band, no summaries, no score, no
--    snapshots; the cohort, the partition, when each side sees it, the
--    reason ids (<= 3) and the internal rank detail (never returned).
--    One introduction per pair, ever (filter 14).
-- =====================================================================
ALTER TABLE public.dating_introductions
  DROP COLUMN IF EXISTS display_band,
  DROP COLUMN IF EXISTS explanation_features,
  DROP COLUMN IF EXISTS low_summary,
  DROP COLUMN IF EXISTS high_summary,
  DROP COLUMN IF EXISTS internal_score,
  DROP COLUMN IF EXISTS snapshot_low_id,
  DROP COLUMN IF EXISTS snapshot_high_id,
  ADD COLUMN IF NOT EXISTS cohort_window date,
  ADD COLUMN IF NOT EXISTS partition_key text,
  ADD COLUMN IF NOT EXISTS visible_from_low timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS visible_from_high timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS reasons text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS rank_detail jsonb;
DROP TABLE IF EXISTS public.dating_feature_snapshots;
DROP INDEX IF EXISTS public.dating_introductions_pair_algorithm_created_idx;
-- Dating has never been on in production; a development database keeps
-- the newest row of a pair.
DELETE FROM public.dating_introductions AS i
 USING public.dating_introductions AS j
 WHERE i.pair_key = j.pair_key AND (i.created_at, i.id) < (j.created_at, j.id);
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'dating_introductions_pair_key_key') THEN
    ALTER TABLE public.dating_introductions ADD CONSTRAINT dating_introductions_pair_key_key UNIQUE (pair_key);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'dating_introductions_v2_check') THEN
    ALTER TABLE public.dating_introductions ADD CONSTRAINT dating_introductions_v2_check CHECK (
      cardinality(reasons) <= 3 AND array_position(reasons, NULL) IS NULL
      AND (partition_key IS NULL OR partition_key ~ '^[A-Z]{2}(:[A-Z0-9_]{1,16})?$'));
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS dating_intro_high_idx ON public.dating_introductions (user_high_id, created_at DESC);

-- =====================================================================
-- 3. Matches carry their pair (§4.3; fixes §4.10's first latent fault):
--    filled from the introduction or the two members on insert, so no
--    writer can leave it out; a member's deletion keeps it.
-- =====================================================================
ALTER TABLE public.dating_matches ADD COLUMN IF NOT EXISTS pair_key text;
UPDATE public.dating_matches AS m
   SET pair_key = coalesce(
     (SELECT i.pair_key FROM public.dating_introductions AS i WHERE i.id = m.introduction_id),
     CASE WHEN m.user_low_id IS NOT NULL AND m.user_high_id IS NOT NULL
          THEN public.dating_pair_key(m.user_low_id, m.user_high_id) END,
     'gone:' || m.id::text)
 WHERE m.pair_key IS NULL;
CREATE OR REPLACE FUNCTION private.dating_matches_pair_key()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  NEW.pair_key := coalesce(NEW.pair_key,
    (SELECT i.pair_key FROM public.dating_introductions AS i WHERE i.id = NEW.introduction_id),
    CASE WHEN NEW.user_low_id IS NOT NULL AND NEW.user_high_id IS NOT NULL
         THEN public.dating_pair_key(NEW.user_low_id, NEW.user_high_id) END);
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS dating_matches_pair_key ON public.dating_matches;
CREATE TRIGGER dating_matches_pair_key BEFORE INSERT ON public.dating_matches
  FOR EACH ROW EXECUTE FUNCTION private.dating_matches_pair_key();
ALTER TABLE public.dating_matches ALTER COLUMN pair_key SET NOT NULL;
CREATE INDEX IF NOT EXISTS dating_matches_pair_key_idx ON public.dating_matches (pair_key);

-- =====================================================================
-- 4. The introductions_v2 config (§5.11): a draft until reviewed (the W5
--    gate activates it with real references; the dev script with DEV-
--    ones). alignment_v1 is retired. daily_new_max can never exceed 3
--    (Q14; mutant 20) and waiting_max 6. In production a config whose
--    review references start DEV- can't be made active.
-- =====================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'dating_algorithm_configs_caps_check') THEN
    ALTER TABLE public.dating_algorithm_configs ADD CONSTRAINT dating_algorithm_configs_caps_check CHECK (
      (NOT (config ? 'daily_new_max') OR coalesce(config ->> 'daily_new_max' ~ '^[1-3]$', false))
      AND (NOT (config ? 'waiting_max') OR coalesce(config ->> 'waiting_max' ~ '^[1-6]$', false)));
  END IF;
END $$;
UPDATE public.dating_algorithm_configs
   SET state = 'retired', retired_at = coalesce(retired_at, now())
 WHERE version = 'alignment_v1' AND state <> 'retired';
INSERT INTO public.dating_algorithm_configs (version, state, config, config_hash)
SELECT 'introductions_v2', 'draft', c.v, encode(extensions.digest(c.v::text, 'sha256'), 'hex')
  FROM (SELECT '{
    "daily_new_max": 3,
    "waiting_max": 6,
    "open_chat_pause_at": 3,
    "open_chat_active_days": 14,
    "lifetime_days": 7,
    "cool_off_hours": 72,
    "cross_border_min_account_days": 14,
    "photos_after_mutual_min_account_days": 30,
    "context_fresh_days": 14,
    "same_gender_context_fresh_days": 7,
    "rank": {"feasibility_weight": 10, "values_weight": 3, "band_width": 3,
             "exposure_window_days": 7, "jitter": 2.0},
    "intention_matrix": {
      "marriage": ["marriage", "committed"],
      "committed": ["marriage", "committed", "companionship", "not_sure"],
      "companionship": ["committed", "companionship", "not_sure"],
      "not_sure": ["committed", "companionship", "not_sure"]
    },
    "default_ages": {"young_until": 20, "young_plus": 7, "minus": 5, "plus": 5},
    "dragnet": {"min_intros": 15, "window_days": 14, "interested_ratio": 0.9,
                "first_message_ratio": 0.2, "throttled_daily_max": 1},
    "reasons_max": 3,
    "partition_people_max": 5000,
    "scan_limit": 500,
    "max_attempts": 3
  }'::jsonb AS v) AS c
ON CONFLICT (version) DO NOTHING;

CREATE OR REPLACE FUNCTION private.dating_config_review_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.state = 'active' AND private.attune_environment() IS NOT DISTINCT FROM 'production'
     AND (coalesce(NEW.product_review_ref, '') LIKE 'DEV-%' OR coalesce(NEW.clinical_review_ref, '') LIKE 'DEV-%'
          OR coalesce(NEW.fairness_review_ref, '') LIKE 'DEV-%' OR coalesce(NEW.safety_review_ref, '') LIKE 'DEV-%') THEN
    RAISE EXCEPTION 'config:dev_review_ref' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS dating_config_review_guard ON public.dating_algorithm_configs;
CREATE TRIGGER dating_config_review_guard BEFORE INSERT OR UPDATE ON public.dating_algorithm_configs
  FOR EACH ROW EXECUTE FUNCTION private.dating_config_review_guard();

-- The active introductions config, only when its shape is the §5.11 one
-- (else NULL: generation refuses with no_active_config, the filters admit
-- nobody).
CREATE OR REPLACE FUNCTION private.dating_intro_config(OUT o_version text, OUT o_config jsonb)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT c.version, c.config
    FROM public.dating_algorithm_configs AS c
   WHERE c.state = 'active' AND c.version LIKE 'introductions\_v%'
     AND jsonb_typeof(c.config -> 'intention_matrix') = 'object'
     AND jsonb_typeof(c.config -> 'rank') = 'object'
     AND coalesce(c.config ->> 'daily_new_max' ~ '^[1-3]$', false)
     AND coalesce(c.config ->> 'waiting_max' ~ '^[1-6]$', false)
     AND coalesce(c.config ->> 'lifetime_days' ~ '^[0-9]{1,2}$', false)
     AND coalesce(c.config ->> 'cool_off_hours' ~ '^[0-9]{1,3}$', false)
     AND coalesce(c.config ->> 'scan_limit' ~ '^[0-9]{1,4}$', false)
     AND coalesce(c.config ->> 'partition_people_max' ~ '^[0-9]{1,5}$', false)
   ORDER BY c.activated_at DESC NULLS LAST
   LIMIT 1;
$$;

-- =====================================================================
-- 5. The person, the pair and the hard filters (§5.1, §5.2).
-- =====================================================================
-- Carry 1 (W2 final M-5): no introduction is visible before account
-- creation + the cool-off (§2.8, 72 h). NULL for no account: never over.
CREATE OR REPLACE FUNCTION private.dating_cool_off_ends_at(p_user uuid)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT u.created_at + make_interval(hours => coalesce(((private.dating_intro_config()).o_config ->> 'cool_off_hours')::int, 72))
    FROM public.users AS u WHERE u.id = p_user;
$$;

-- §2.3 freshness (Ruling R-3): the last time the person used Dating, the
-- later of the session context check (W8b's device check writes it) and
-- the trusted phone's last use (written at most once a day by every
-- device-checked call, W4b). NULL: never fresh.
CREATE OR REPLACE FUNCTION private.dating_last_seen_at(p_user uuid)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT nullif(greatest(coalesce((SELECT c.checked_at FROM public.dating_session_context AS c WHERE c.user_id = p_user), '-infinity'),
                         coalesce((SELECT max(d.last_seen_at) FROM public.dating_trusted_devices AS d WHERE d.user_id = p_user), '-infinity')),
                '-infinity'::timestamptz);
$$;

-- §2.4: a pair is man-woman when one identity is woman and the other man.
CREATE OR REPLACE FUNCTION private.dating_pair_is_man_woman(p_a text, p_b text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT coalesce((p_a = 'woman' AND p_b = 'man') OR (p_a = 'man' AND p_b = 'woman'), false);
$$;

-- One person as generation sees them (§5.1): decrypted only inside a
-- definer function, held only in a transaction's temp table or a local
-- variable, never stored or returned to anyone.
DO $$
BEGIN
  IF to_regtype('private.dating_gen_person') IS NULL THEN
    CREATE TYPE private.dating_gen_person AS (
      user_id uuid,
      country text,
      region text,
      side text,
      scope text,
      open_abroad text[],
      age integer,
      min_age integer,
      max_age integer,
      identity text,
      pools text[],
      seeking text[],
      intention text,
      timeline text,
      timeline_visible boolean,
      intention_open text[],
      children_have boolean,
      children_want text,
      want_must_match boolean,
      exclude_parents boolean,
      faith text,
      importance text,
      faith_visible boolean,
      family text,
      same_gender_ok boolean,
      abroad_ok boolean,
      hmac text,
      visible_from timestamptz
    );
  END IF;
END $$;

-- The person's row at [p_at] under [p_cfg]; raises dating:field_* on an
-- unreadable answer (callers skip that person).
CREATE OR REPLACE FUNCTION private.dating_person(p_user uuid, p_at timestamptz, p_cfg jsonb)
RETURNS private.dating_gen_person
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v private.dating_gen_person;
  v_p public.dating_profiles;
  v_d public.dating_preferences;
  v_identity jsonb;
  v_seeking jsonb;
  v_faith jsonb;
BEGIN
  SELECT * INTO v_p FROM public.dating_profiles AS p WHERE p.user_id = p_user;
  SELECT * INTO v_d FROM public.dating_preferences AS d WHERE d.user_id = p_user;
  IF v_p.user_id IS NULL OR v_d.user_id IS NULL THEN
    RETURN NULL;
  END IF;
  SELECT private.dating_field_decrypt(s.identity_enc), private.dating_field_decrypt(s.seeking_enc),
         private.dating_field_decrypt(s.faith_enc)
    INTO v_identity, v_seeking, v_faith
    FROM public.dating_profile_sensitive AS s WHERE s.user_id = p_user;
  v.user_id := p_user;
  v.country := v_p.country_code::text;
  v.region := v_p.region_code;
  v.side := v_p.side_code;
  v.scope := v_d.region_scope;
  v.open_abroad := v_d.open_abroad::text[];
  v.age := public.account_age(p_user);
  v.min_age := v_d.min_age;
  v.max_age := v_d.max_age;
  v.identity := v_identity ->> 'identity';
  v.pools := ARRAY(SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(v_identity -> 'pools') = 'array'
                                                          THEN v_identity -> 'pools' END));
  v.seeking := ARRAY(SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(v_seeking -> 'seeking') = 'array'
                                                            THEN v_seeking -> 'seeking' END));
  -- Carry 2 (W1 B7 M-4): no identity or no who-to-meet is never introducible.
  IF v.identity IS NULL OR cardinality(v.pools) = 0 THEN
    v.pools := NULL;
  END IF;
  IF cardinality(v.seeking) = 0 THEN
    v.seeking := NULL;
  END IF;
  v.intention := v_p.intention;
  v.timeline := v_p.marriage_timeline;
  v.timeline_visible := v_p.timeline_visible;
  v.intention_open := coalesce(v_d.intention_open,
    ARRAY(SELECT jsonb_array_elements_text(p_cfg -> 'intention_matrix' -> v_p.intention)));
  v.children_have := v_p.children_have;
  v.children_want := v_p.children_want;
  v.want_must_match := v_d.want_must_match;
  v.exclude_parents := v_d.exclude_parents;
  v.faith := v_faith ->> 'faith';
  v.importance := v_faith ->> 'importance';
  v.faith_visible := v_p.faith_visible;
  v.family := v_p.family_involvement;
  -- §5.2 filter 4: the global flag, the person's Dating country, and a
  -- fresh context that allows it where they are (fail closed: no context,
  -- no same-gender introduction; W8b writes the context).
  v.same_gender_ok := coalesce(private.dating_same_gender_on(v.country), false)
    AND EXISTS (SELECT 1 FROM public.dating_session_context AS c
                 WHERE c.user_id = p_user AND c.same_gender_allowed_here
                   AND c.checked_at >= p_at - make_interval(days => coalesce((p_cfg ->> 'same_gender_context_fresh_days')::int, 7)));
  -- §2.6: an account at least 14 days old may be introduced across borders.
  v.abroad_ok := coalesce((SELECT u.created_at FROM public.users AS u WHERE u.id = p_user)
                          <= p_at - make_interval(days => coalesce((p_cfg ->> 'cross_border_min_account_days')::int, 14)), false);
  v.hmac := public.dating_phone_hmac_for_user(p_user);
  v.visible_from := private.dating_first_drop_at(p_user, p_at);
  RETURN v;
END;
$$;

-- §5.2 filter 1 at [p_at]: a current candidate (eligibility, both checks,
-- an active enrolment, a ready profile, seen in Dating within 14 days:
-- dating_candidate_is_current), not hidden by travel, and the cool-off
-- over by the next drop.
CREATE OR REPLACE FUNCTION private.dating_person_current(p_user uuid, p_at timestamptz, p_cfg jsonb)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(public.dating_candidate_is_current(p_user), false)
    AND NOT EXISTS (SELECT 1 FROM public.dating_session_context AS c
                     WHERE c.user_id = p_user AND c.dating_allowed_here IS FALSE)
    AND coalesce(private.dating_cool_off_ends_at(p_user) <= private.dating_first_drop_at(p_user, p_at), false);
$$;

-- §5.2 filters 2-10, in both directions, over two person rows. Pure: one
-- implementation for the single-pair predicate and for generation's set.
-- Any NULL answer admits nobody (carry 2).
CREATE OR REPLACE FUNCTION private.dating_admits(a private.dating_gen_person, b private.dating_gen_person, p_cfg jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT coalesce(
    a.user_id <> b.user_id
    -- 2. each age within the other's range
    AND b.age BETWEEN a.min_age AND a.max_age
    AND a.age BETWEEN b.min_age AND b.max_age
    -- 3. each seeking set meets the other's pools
    AND a.seeking && b.pools
    AND b.seeking && a.pools
    -- 4. not man-woman: both allowed (flag, country, fresh context)
    AND (private.dating_pair_is_man_woman(a.identity, b.identity) OR (a.same_gender_ok AND b.same_gender_ok))
    -- 5, 6. the same country and inside each one's scope; or across
    -- borders, each open to the other's country, both accounts 14+ days
    AND CASE WHEN a.country = b.country THEN
          (a.scope = 'country' OR b.region = a.region)
          AND (a.scope IS DISTINCT FROM 'side' OR a.side IS NULL OR b.side = a.side)
          AND (b.scope = 'country' OR a.region = b.region)
          AND (b.scope IS DISTINCT FROM 'side' OR b.side IS NULL OR a.side = b.side)
        ELSE b.country = ANY (a.open_abroad) AND a.country = ANY (b.open_abroad) AND a.abroad_ok AND b.abroad_ok
        END
    -- 7. the intention matrix and each one's intentions open to
    AND (p_cfg -> 'intention_matrix' -> a.intention) ? b.intention
    AND b.intention = ANY (a.intention_open)
    AND (p_cfg -> 'intention_matrix' -> b.intention) ? a.intention
    AND a.intention = ANY (b.intention_open)
    -- 8. must match on wanting children: never yes against no
    AND NOT (a.want_must_match AND ((a.children_want = 'yes' AND b.children_want = 'no') OR (a.children_want = 'no' AND b.children_want = 'yes')))
    AND NOT (b.want_must_match AND ((b.children_want = 'yes' AND a.children_want = 'no') OR (b.children_want = 'no' AND a.children_want = 'yes')))
    -- 9. no parents for someone who excludes them
    AND NOT (a.exclude_parents AND b.children_have)
    AND NOT (b.exclude_parents AND a.children_have)
    -- 10. "must share" faith: the other stated the same tradition
    AND (a.importance IS DISTINCT FROM 'must_share' OR (b.faith IS NOT NULL AND b.faith <> 'prefer_not_to_say' AND b.faith = a.faith))
    AND (b.importance IS DISTINCT FROM 'must_share' OR (a.faith IS NOT NULL AND a.faith <> 'prefer_not_to_say' AND a.faith = b.faith)),
    false);
$$;

-- §5.2 filters 11-13, both directions: no block (by id or by phone HMAC),
-- not former partners, and neither number on the other's never-introduce
-- list (kept rows included: they stay enforced forever, carry 4). A
-- missing HMAC is never safe.
CREATE OR REPLACE FUNCTION private.dating_pair_safe(p_a uuid, p_b uuid, p_ha text, p_hb text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT p_ha IS NOT NULL AND p_hb IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.dating_blocks AS b
                     WHERE (b.blocker_user_id = p_a AND b.blocked_user_id = p_b)
                        OR (b.blocker_user_id = p_b AND b.blocked_user_id = p_a))
    AND NOT EXISTS (SELECT 1 FROM public.dating_block_hmacs AS h
                     WHERE (h.blocker_hmac = p_ha AND h.blocked_hmac = p_hb)
                        OR (h.blocker_hmac = p_hb AND h.blocked_hmac = p_ha))
    AND public.dating_former_partner_excluded(p_a, p_b) IS FALSE
    AND public.dating_never_introduce_excludes(p_a, p_b) IS FALSE;
$$;

-- §5.2 filter 14: never introduced before (an earlier match always had an
-- introduction; a match's own pair_key covers one whose introduction went).
CREATE OR REPLACE FUNCTION private.dating_pair_new(p_a uuid, p_b uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT NOT EXISTS (SELECT 1 FROM public.dating_introductions AS i WHERE i.pair_key = public.dating_pair_key(p_a, p_b))
     AND NOT EXISTS (SELECT 1 FROM public.dating_matches AS m WHERE m.pair_key = public.dating_pair_key(p_a, p_b));
$$;

-- §5.2, rewritten (§4.10; fixes the pair_key fault): true only if every
-- filter holds for (a, b) and for (b, a), now, under the active config.
DROP FUNCTION IF EXISTS public.dating_pair_passes_hard_filters(uuid, uuid);
CREATE FUNCTION public.dating_pair_passes_hard_filters(p_a uuid, p_b uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_cfg constant jsonb := (private.dating_intro_config()).o_config;
  v_at constant timestamptz := now();
  v_a private.dating_gen_person;
  v_b private.dating_gen_person;
BEGIN
  IF p_a IS NULL OR p_b IS NULL OR p_a = p_b OR v_cfg IS NULL THEN
    RETURN false;
  END IF;
  -- 1, 15 (W5c adds the moderation removal to the person check).
  IF private.dating_person_current(p_a, v_at, v_cfg) IS NOT TRUE
     OR private.dating_person_current(p_b, v_at, v_cfg) IS NOT TRUE THEN
    RETURN false;
  END IF;
  v_a := private.dating_person(p_a, v_at, v_cfg);
  v_b := private.dating_person(p_b, v_at, v_cfg);
  RETURN coalesce(private.dating_admits(v_a, v_b, v_cfg)
                  AND private.dating_pair_safe(p_a, p_b, v_a.hmac, v_b.hmac)
                  AND private.dating_pair_new(p_a, p_b), false);
EXCEPTION WHEN raise_exception THEN
  -- An unreadable answer or a missing field key admits nobody.
  IF SQLERRM IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
    RETURN false;
  END IF;
  RAISE;
END;
$$;

-- =====================================================================
-- 6. Functions re-created from their LIVE bodies (Spec 2 W5a lines only).
-- =====================================================================
DROP FUNCTION IF EXISTS public.get_my_dating_introductions(integer);
```

Create `$D/mig_T1_tail.sql` with exactly:

```sql

-- =====================================================================
-- 9. Grants (re-asserted by the twin). Every helper is the database's
--    own, the service role included; the v1 introductions read stays the
--    app's until W5b replaces it; the hard-filter predicate is no API
--    role's (as before).
-- =====================================================================
REVOKE ALL ON FUNCTION private.dating_matches_pair_key() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_config_review_guard() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_intro_config() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_cool_off_ends_at(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_last_seen_at(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_pair_is_man_woman(text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_person(uuid, timestamptz, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_person_current(uuid, timestamptz, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_admits(private.dating_gen_person, private.dating_gen_person, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_pair_safe(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_pair_new(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_pair_passes_hard_filters(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_my_dating_introductions(integer) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_dating_introductions(integer) TO authenticated;
COMMIT;
```

Create `$D/build_mig_T1.py` with exactly:

```python
#!/usr/bin/env python3
# Spec 2 W5a: builds supabase/migrations/20261119100000_dating_v2_matching.sql
# from mig_T1_head.sql (the new objects), the functions below re-created
# from their LIVE bodies (saved to before_w5a/ before the migration is
# applied) with only the lines marked "-- Spec 2 W5a" changed, Task 2's
# mig_T2_generation.sql when it exists, and mig_T1_tail.sql (the revokes,
# COMMIT). Every anchor must occur exactly once.
import pathlib
D = pathlib.Path('.superpowers/sdd/2026-11-19-spec2-w5')
OUT = pathlib.Path('supabase/migrations/20261119100000_dating_v2_matching.sql')

def live(sig):
    return (D / 'before_w5a' / f'{sig}.sql').read_text().rstrip('\n')

M = '-- Spec 2 W5a'
FNS = []

# 1. act: no snapshot and no algorithm-version check (both gone); the
#    caller's own phone first, so an untrusted phone changes nothing of
#    anyone's (R-17); per-side visibility; the never-introduce list (kept
#    rows too) and phone-HMAC blocks (carry 4); no "New mutual match" push
#    (§4.10, §3.13). W5b replaces the whole function (v2 answers).
FNS.append(('public.act_on_dating_introduction(text,uuid,text)', [
  ("""  SELECT version INTO v_active_algorithm FROM public.dating_algorithm_configs WHERE state='active';
  IF v_active_algorithm IS NULL THEN RAISE EXCEPTION 'algorithm_unavailable' USING ERRCODE='22023'; END IF;
""",
   f"""  IF public.dating_require_trusted_device() IS NOT TRUE THEN {M} (carry 8): the caller's own phone, before anything
    RAISE EXCEPTION 'reverify_device' USING ERRCODE = '42501'; {M}
  END IF; {M}
"""),
  ("""     OR v_intro.state NOT IN ('generated','presented','interested')
     OR v_intro.algorithm_version<>v_active_algorithm THEN""",
   f"""     OR v_intro.state NOT IN ('generated','presented','interested')
     OR now() < (CASE WHEN v_intro.user_low_id = v_user_id THEN v_intro.visible_from_low ELSE v_intro.visible_from_high END) THEN {M}: not before this side's drop"""),
  ("""     OR NOT EXISTS(SELECT 1 FROM public.dating_feature_snapshots s WHERE s.id=v_intro.snapshot_low_id AND s.invalidated_at IS NULL)
     OR NOT EXISTS(SELECT 1 FROM public.dating_feature_snapshots s WHERE s.id=v_intro.snapshot_high_id AND s.invalidated_at IS NULL) THEN""",
   f"""     OR private.dating_pair_safe(v_intro.user_low_id, v_intro.user_high_id, {M} (carry 4): blocks by HMAC, never-introduce (kept rows too)
          public.dating_phone_hmac_for_user(v_intro.user_low_id), public.dating_phone_hmac_for_user(v_intro.user_high_id)) IS NOT TRUE THEN {M}"""),
  ("""    ON CONFLICT(introduction_id) DO NOTHING RETURNING id INTO v_match_id;
    IF v_match_id IS NOT NULL THEN
      INSERT INTO public.scheduled_notifications(
        user_id,notification_type,scheduled_for,status,metadata,source_key,created_at,updated_at
      ) VALUES
        (v_intro.user_low_id,'immediate',now(),'pending',
         jsonb_build_object('title','New mutual match','body','Open Attune to see your new connection.','type','dating_mutual_match','match_id',v_match_id::text),
         'dating_match:'||v_match_id::text||':'||v_intro.user_low_id::text,now(),now()),
        (v_intro.user_high_id,'immediate',now(),'pending',
         jsonb_build_object('title','New mutual match','body','Open Attune to see your new connection.','type','dating_mutual_match','match_id',v_match_id::text),
         'dating_match:'||v_match_id::text||':'||v_intro.user_high_id::text,now(),now())
      ON CONFLICT(source_key) WHERE source_key IS NOT NULL DO NOTHING;
    END IF;""",
   f"""    ON CONFLICT(introduction_id) DO NOTHING RETURNING id INTO v_match_id;
    {M} (§3.13, §4.10): no push; the match moment shows in Dating (W5b)""")]))

# 2. The v1 introductions read (until W5b's v2 replaces it): no band, no
#    summaries, no snapshots; the caller's own phone (carry 8); this side's
#    drop; the never-introduce list and HMAC blocks (carry 4).
FNS.append(('public.get_my_dating_introductions(integer)', [
  (" RETURNS TABLE(id uuid, display_name text, city_region_code text, relationship_intention text, summary text, display_band text, explanation_features jsonb, state text, expires_at timestamp with time zone, created_at timestamp with time zone, has_acted boolean)",
   " RETURNS TABLE(id uuid, display_name text, state text, expires_at timestamp with time zone, created_at timestamp with time zone, has_acted boolean)"),
  ("""  SELECT di.id,dp.display_name,dp.city_region_code,dp.relationship_intention,
    CASE WHEN di.user_low_id=auth.uid() THEN di.high_summary ELSE di.low_summary END,
    di.display_band,di.explanation_features,
    CASE""",
   f"""  SELECT di.id,dp.display_name, {M}: no region code, intention text, summary, band or features
    CASE"""),
  ("""  WHERE public.dating_flag_enabled('dating_mode_enabled')""",
   f"""  WHERE public.dating_flag_enabled('dating_mode_enabled')
    AND public.dating_require_trusted_device() {M} (carry 8)
    AND now() >= CASE WHEN di.user_low_id=auth.uid() THEN di.visible_from_low ELSE di.visible_from_high END {M}"""),
  ("""    AND EXISTS(SELECT 1 FROM public.dating_feature_snapshots s WHERE s.id=di.snapshot_low_id AND s.invalidated_at IS NULL)
    AND EXISTS(SELECT 1 FROM public.dating_feature_snapshots s WHERE s.id=di.snapshot_high_id AND s.invalidated_at IS NULL)""",
   f"""    AND private.dating_pair_safe(di.user_low_id, di.user_high_id, public.dating_phone_hmac_for_user(di.user_low_id), {M} (carry 4)
                                 public.dating_phone_hmac_for_user(di.user_high_id)) {M}""")]))

# 3. Exit: the snapshots are gone.
FNS.append(('private.dating_exit_internal(uuid,boolean)', [
  ("  DELETE FROM public.dating_feature_snapshots AS f WHERE f.user_id = p_user;\n",
   f"  {M}: the trait snapshots are gone (§4.10)\n")]))

# 4. Invalidation: the snapshots are gone.
FNS.append(('public.invalidate_dating_for_user(uuid,text)', [
  ("""  UPDATE public.dating_feature_snapshots
  SET invalidated_at = COALESCE(invalidated_at, now())
  WHERE user_id = p_user_id
    AND invalidated_at IS NULL;
""",
   f"""  {M}: the trait snapshots are gone (§4.10)
""")]))

# 5. Expiry per side (§5.3, §4.6): a side that hasn't acted when its own
#    seven days end can no longer act, so the pair can't match: it ends.
FNS.append(('public.expire_dating_introductions()', [
  ("""DECLARE v_count bigint;
BEGIN
  UPDATE public.dating_introductions SET state='expired'
  WHERE expires_at<=now() AND state IN ('generated','presented','interested');""",
   f"""DECLARE v_count bigint;
  v_life constant interval := make_interval(days => coalesce(((private.dating_intro_config()).o_config ->> 'lifetime_days')::int, 7)); {M}
BEGIN
  UPDATE public.dating_introductions SET state='expired'
  WHERE state IN ('generated','presented','interested') {M}
    AND (expires_at<=now() {M} (§5.3): the later side's seven days
         OR (low_action IS NULL AND visible_from_low + v_life <= now()) {M}: or a side's own, unanswered
         OR (high_action IS NULL AND visible_from_high + v_life <= now())); {M}""")]))

# 6. Health: today's generation per country, and the generation counters.
FNS.append(('public.get_dating_operational_health()', [
  ("""    'active_algorithm_versions',(SELECT count(*) FROM public.dating_algorithm_configs WHERE state='active'),""",
   f"""    'active_algorithm_versions',(SELECT count(*) FROM public.dating_algorithm_configs WHERE state='active'),
    'introductions_config',(private.dating_intro_config()).o_version, {M} (§5.5): NULL = generation refuses
    'generation_by_country',(SELECT coalesce(jsonb_object_agg(x.partition_key, jsonb_build_object( {M} (§4.4 health v2)
                               'cohort', x.cohort_window, 'state', x.state, 'attempts', x.attempts)), '{{}}'::jsonb) {M}
                             FROM (SELECT DISTINCT ON (r.partition_key) r.partition_key, r.cohort_window, r.state, r.attempts {M}
                                     FROM public.dating_generation_runs AS r WHERE r.created_at >= now() - interval '36 hours' {M}
                                    ORDER BY r.partition_key, r.created_at DESC) AS x), {M}"""),
  ("""                        'dating.deletion.prepare_carry_failed', 'dating.deletion.late_carry_failed']) AS k(key)), -- W1 final fix (M-4)""",
   f"""                        'dating.deletion.prepare_carry_failed', 'dating.deletion.late_carry_failed', -- W1 final fix (M-4); {M}: and
                        'dating.generation.skipped', 'dating.generation.failed', 'dating.generation.unreadable']) AS k(key)), {M}""")]))

# 7. The candidate check: seen in Dating within 14 days (§2.3, §5.2 #1).
FNS.append(('public.dating_candidate_is_current(uuid)', [
  ("""    AND coalesce(public.dating_profile_ready(p_user_id), false); -- Spec 2 W2: NULL-safe""",
   f"""    AND coalesce(public.dating_profile_ready(p_user_id), false) -- Spec 2 W2: NULL-safe; {M}: and
    AND coalesce(private.dating_last_seen_at(p_user_id) >= now() - make_interval(days => {M} (§2.3): fresh, else out of others' days
          coalesce(((private.dating_intro_config()).o_config ->> 'context_fresh_days')::int, 14)), false); {M}""")]))

# 8. The drop time in the person's own zone (§5.3), else the country's.
FNS.append(('private.dating_first_drop_at(uuid,timestamp with time zone)', [
  ("""  v_tz := coalesce(v_tz, 'UTC');""",
   f"""  SELECT u.timezone INTO v_drop_tz FROM public.users AS u WHERE u.id = p_user; {M} (§5.3): users.timezone first
  v_tz := coalesce(CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names AS z WHERE z.name = v_drop_tz) {M}
                        THEN v_drop_tz END, v_tz, 'UTC'); {M}: an unknown zone is never used"""),
  ("""  v_at timestamptz;
BEGIN""",
   f"""  v_at timestamptz;
  v_drop_tz text; {M}
BEGIN""")]))

# 9. Carry 10 (W4 final client M-8): a re-check on an untrusted phone is
#    read back for 72 hours from its submission, as the sweep keeps it.
FNS.append(('public.get_my_dating_verification()', [
  ("""       AND s.created_at > now() - interval '1 day'""",
   f"""       AND coalesce(s.awaiting_since, s.created_at) > now() - interval '72 hours' {M} (carry 10): as the sweep""")]))

parts = []
for sig, pairs in FNS:
    body = live(sig)
    for old, new in pairs:
        n = body.count(old)
        assert n == 1, f'{sig}: anchor occurs {n} times: {old[:60]!r}'
        body = body.replace(old, new)
    parts.append(body + ';\n')
gen = D / 'mig_T2_generation.sql'
OUT.write_text((D / 'mig_T1_head.sql').read_text() + '\n'.join(parts) + '\n'
               + (gen.read_text() if gen.exists() else '') + (D / 'mig_T1_tail.sql').read_text())
print(f'{OUT}: {len(FNS)} functions re-created' + (' + the generation section' if gen.exists() else ''))
```

Create `supabase/migrations/20261119100010_dating_v2_matching_grants.sql` with exactly:

```sql
-- Spec 2 W5a: grants for 20261119100000_dating_v2_matching.sql. The
-- introductions and matches stay no API role's, the service role included
-- (S-5); every new helper is the database's own; the generation tick is
-- cron's (postgres), no API role's, the service role included (it decrypts:
-- §4.2, S-4); the v1 introductions read stays the app's until W5b.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.dating_introductions, public.dating_matches, public.dating_interest_actions
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_matches_pair_key() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_config_review_guard() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_intro_config() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_cool_off_ends_at(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_last_seen_at(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_pair_is_man_woman(text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_person(uuid, timestamptz, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_person_current(uuid, timestamptz, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_admits(private.dating_gen_person, private.dating_gen_person, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_pair_safe(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_pair_new(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_pair_passes_hard_filters(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_my_dating_introductions(integer) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_dating_introductions(integer) TO authenticated;
COMMIT;
```

- [ ] **Step 8: Build and apply**

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5
python3 -I $D/build_mig_T1.py
for f in supabase/migrations/20261119100000_dating_v2_matching.sql supabase/migrations/20261119100010_dating_v2_matching_grants.sql; do
  for run in 1 2; do psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $f > /dev/null 2> $D/apply_err.txt; rc=$?; echo "$(basename $f) run $run exit=$rc"; grep -v NOTICE $D/apply_err.txt || true; done
done
python3 -I $D/marked_diff.py $D/before_w5a attune_spec3a 'Spec 2 W5a'; echo "marked_diff exit=$?"
python3 -I $D/grants_line.py supabase/migrations/20261109110010_dating_v2_trusted_devices_grants.sql 'Spec 2 W5a: matching (twin of 20261119100000)' supabase/migrations/20261119100010_dating_v2_matching_grants.sql
```

Expected: `supabase/migrations/20261119100000_dating_v2_matching.sql: 9 functions re-created`; four `exit=0` lines and nothing else printed for them (the `rc` is read before the echo: W4's form printed `exit=0` whatever happened); nine marked-diff lines each ending `OK` (`public.get_my_dating_introductions(integer)` also shows its `header:` RETURNS TABLE line) and `marked_diff exit=0`; `local_pg_grants.sql: one \i block added`.

- [ ] **Step 9: Run the contract**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_matching_contracts.sql 2>&1 | tail -1
```

Expected: `psql:supabase/tests/dating_v2_matching_contracts.sql:…: NOTICE:  dating_v2_matching_contracts: all held`.

- [ ] **Step 10: The existing contracts, the race script and the dev script meet W5a**

Create `$D/edit_tests_T1.py` with exactly:

```python
# Spec 2 W5a Task 1: the existing contracts, the race script and the dev
# script meet W5a. Introductions lose the v1 columns and the snapshots
# (each fixture inserts the v2 shape, never a loosened check); the v1
# generator and match read are gone (the identity contract calls the tick,
# whose refusals answer as before; dating_mode pins that the v1 match read
# is gone); candidates must have been seen in Dating within 14 days, so
# the fixtures that make current candidates give them a session context;
# the alignment flag and its gate row are gone (5 Dating flags before W5);
# the dev script turns on every Dating flag that exists and activates
# introductions_v2 with DEV- references (§4.9). The canary takes W5a's
# helpers (Task 2 adds generation's).
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anchor import edit

T = 'supabase/tests/'
W = '-- Spec 2 W5a'
INTRO_V2 = """  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version) {W}
  VALUES (public.dating_pair_key(p_a, p_b), least(p_a, p_b), greatest(p_a, p_b), p_state, {alg}) {W}
  RETURNING id INTO v_id;"""

edit(T + 'dating_v2_identity_contracts.sql', [
  ("""-- A pair's introduction ([p_state]), with the two snapshots today's schema
-- needs (dropped in W5a).
CREATE FUNCTION pg_temp.intro(p_a uuid, p_b uuid, p_state text DEFAULT 'presented') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_low uuid;
  v_high uuid;
  v_id uuid;
BEGIN
  INSERT INTO public.dating_feature_snapshots (user_id, algorithm_version)
  VALUES (least(p_a, p_b), 'spec2-w1-contract') RETURNING id INTO v_low;
  INSERT INTO public.dating_feature_snapshots (user_id, algorithm_version)
  VALUES (greatest(p_a, p_b), 'spec2-w1-contract') RETURNING id INTO v_high;
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, display_band, state,
                                           algorithm_version, snapshot_low_id, snapshot_high_id, internal_score)
  VALUES (public.dating_pair_key(p_a, p_b), least(p_a, p_b), greatest(p_a, p_b), 'some_shared_ground', p_state,
          'spec2-w1-contract', v_low, v_high, 0.5)
  RETURNING id INTO v_id;""",
   """-- A pair's introduction ([p_state]), in W5a's shape.
CREATE FUNCTION pg_temp.intro(p_a uuid, p_b uuid, p_state text DEFAULT 'presented') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_id uuid;
BEGIN
""" + INTRO_V2.format(W=W, alg="'spec2-w1-contract'")),
  ("     OR EXISTS (SELECT 1 FROM public.dating_feature_snapshots WHERE user_id = v_a)\n", ""),
], 'identity: v2 introductions')
p = pathlib.Path(T + 'dating_v2_identity_contracts.sql')
s = p.read_text()
assert s.count('public.run_dating_candidate_generation(NULL)') == 7
p.write_text(s.replace('public.run_dating_candidate_generation(NULL)', 'public.run_dating_generation_tick()'))
print('dating_v2_identity_contracts.sql: 7 generation calls now the W5a tick')

edit(T + 'country_safety_config_contracts.sql', [
  ("""DECLARE
  v_low uuid;
  v_high uuid;
  v_id uuid;
BEGIN
  INSERT INTO public.dating_feature_snapshots (user_id, algorithm_version) VALUES (least(p_a, p_b), p_alg) RETURNING id INTO v_low;
  INSERT INTO public.dating_feature_snapshots (user_id, algorithm_version) VALUES (greatest(p_a, p_b), p_alg) RETURNING id INTO v_high;
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, display_band, state,
                                           algorithm_version, snapshot_low_id, snapshot_high_id, internal_score)
  VALUES (public.dating_pair_key(p_a, p_b), least(p_a, p_b), greatest(p_a, p_b), 'some_shared_ground', p_state,
          p_alg, v_low, v_high, 0.5) RETURNING id INTO v_id;""",
   """DECLARE
  v_id uuid;
BEGIN
""" + INTRO_V2.format(W=W, alg='p_alg')),
  ("""  v_i_gen := pg_temp.intro(v_man, v_uk_nb, 'generated', 'w1d-generated');
  v_i_int := pg_temp.intro(v_man, v_uk_nb, 'interested', 'w1d-interested');""",
   f"""  {W} (§5.2 14): one introduction per pair ever, so each state has its own
  {W} not-man-woman pair (a non-binary person, then a man).
  v_i_gen := pg_temp.intro(v_man, v_uk_nb_abroad, 'generated', 'w1d-generated'); {W}
  v_i_int := pg_temp.intro(v_man, v_uk_man, 'interested', 'w1d-interested'); {W}"""),
  ("""                             'dating_profile_photos', 'dating_alignment_algorithm_v1', 'dating_same_gender_matching')) IS DISTINCT FROM 6 THEN""",
   f"""                             'dating_profile_photos', 'dating_same_gender_matching')) IS DISTINCT FROM 5 THEN {W}: the alignment flag is gone"""),
  ("""                     'dating_profile_photos', 'dating_alignment_algorithm_v1', 'dating_same_gender_matching')
         AND enabled) IS DISTINCT FROM 6::bigint""",
   f"""                     'dating_profile_photos', 'dating_same_gender_matching') {W}: the alignment flag is gone
         AND enabled) IS DISTINCT FROM 5::bigint"""),
], 'country config: v2 introductions, five flags')

edit(T + 'dating_v2_setup_contracts.sql', [
  ("""    INSERT INTO public.dating_feature_snapshots (user_id, algorithm_version) VALUES (least(v_x, v_y), 'w1final-m2') RETURNING id INTO v_s_low;
    INSERT INTO public.dating_feature_snapshots (user_id, algorithm_version) VALUES (greatest(v_x, v_y), 'w1final-m2') RETURNING id INTO v_s_high;
    INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, display_band, state, algorithm_version,
                                             snapshot_low_id, snapshot_high_id, internal_score)
    VALUES (public.dating_pair_key(v_x, v_y), least(v_x, v_y), greatest(v_x, v_y), 'some_shared_ground', 'presented', 'w1final-m2',
            v_s_low, v_s_high, 0.5)""",
   f"""    INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version) {W}
    VALUES (public.dating_pair_key(v_x, v_y), least(v_x, v_y), greatest(v_x, v_y), 'presented', 'w1final-m2') {W}"""),
  ("""    INSERT INTO public.dating_feature_snapshots (user_id, algorithm_version) VALUES (least(v_n, v_z2), 'w1final-m2') RETURNING id INTO v_s_low;
    INSERT INTO public.dating_feature_snapshots (user_id, algorithm_version) VALUES (greatest(v_n, v_z2), 'w1final-m2') RETURNING id INTO v_s_high;
    INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, display_band, state, algorithm_version,
                                             snapshot_low_id, snapshot_high_id, internal_score)
    VALUES (public.dating_pair_key(v_n, v_z2), least(v_n, v_z2), greatest(v_n, v_z2), 'some_shared_ground', 'presented', 'w1final-m2',
            v_s_low, v_s_high, 0.5)""",
   f"""    INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version) {W}
    VALUES (public.dating_pair_key(v_n, v_z2), least(v_n, v_z2), greatest(v_n, v_z2), 'presented', 'w1final-m2') {W}"""),
], 'setup: v2 introductions')

edit(T + 'dating_v2_eligibility_contracts.sql', [
  ("""  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_past, 'active');
""",
   f"""  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_past, 'active');
  INSERT INTO public.dating_session_context (user_id, effective_tier, dating_allowed_here, same_gender_allowed_here, {W} (§2.3): seen in Dating
                                             away_from_home, ip_resolved) VALUES (v_past, 1, true, false, false, true); {W}
"""),
], 'eligibility: a candidate seen in Dating')

MODE_V2 = """  INSERT INTO public.dating_introductions (id, pair_key, user_low_id, user_high_id, state, expires_at, algorithm_version) {W}
  VALUES {rows} {W}
  ON CONFLICT (id) DO NOTHING;"""
edit(T + 'dating_mode_contracts.sql', [
  ("""  -- Feature snapshots for A, B, D (valid, not invalidated).
  -- consent_basis / features / source_provenance are all jsonb NOT NULL.
  INSERT INTO public.dating_feature_snapshots(id, user_id, algorithm_version, consent_basis, features, source_provenance)
  VALUES
    (v_snap_a, a, 'test-active-v1', '{"basis":"explicit_opt_in"}', '{}', '{}'),
    (v_snap_b, b, 'test-active-v1', '{"basis":"explicit_opt_in"}', '{}', '{}'),
    (v_snap_d, d, 'test-active-v1', '{"basis":"explicit_opt_in"}', '{}', '{}')
  ON CONFLICT (id) DO NOTHING;

  -- Live introductions: (A,B) and (A,D). user_low/high ordered by uuid text.
  INSERT INTO public.dating_introductions(
    id, pair_key, user_low_id, user_high_id, display_band, explanation_features,
    low_summary, high_summary, state, expires_at,
    algorithm_version, snapshot_low_id, snapshot_high_id, internal_score
  ) VALUES
    (v_intro_ab, public.dating_pair_key(a,b), LEAST(a,b), GREATEST(a,b),
     'some_shared_ground','{}','You share intentional-dating goals.','You share intentional-dating goals.',
     'presented', now() + interval '7 days',
     'test-active-v1',
     CASE WHEN a < b THEN v_snap_a ELSE v_snap_b END,
     CASE WHEN a < b THEN v_snap_b ELSE v_snap_a END,
     0.5),
    (v_intro_ad, public.dating_pair_key(a,d), LEAST(a,d), GREATEST(a,d),
     'some_shared_ground','{}','You share intentional-dating goals.','You share intentional-dating goals.',
     'presented', now() + interval '7 days',
     'test-active-v1',
     CASE WHEN a < d THEN v_snap_a ELSE v_snap_d END,
     CASE WHEN a < d THEN v_snap_d ELSE v_snap_a END,
     0.5)
  ON CONFLICT (id) DO NOTHING;""",
   f"""  -- Spec 2 W5a (§2.3): A, B and D were seen in Dating today.
  INSERT INTO public.dating_session_context (user_id, effective_tier, dating_allowed_here, same_gender_allowed_here, {W}
                                             away_from_home, ip_resolved) {W}
  SELECT u, 1, true, false, false, true FROM (VALUES (a), (b), (d)) AS x(u); {W}

  -- Live introductions: (A,B) and (A,D). user_low/high ordered by uuid text.
""" + MODE_V2.format(W=W, rows="""(v_intro_ab, public.dating_pair_key(a,b), LEAST(a,b), GREATEST(a,b), 'presented', now() + interval '7 days', 'test-active-v1'),
         (v_intro_ad, public.dating_pair_key(a,d), LEAST(a,d), GREATEST(a,d), 'presented', now() + interval '7 days', 'test-active-v1')""")),
  ("  UPDATE public.dating_feature_snapshots SET invalidated_at=NULL WHERE user_id=a;\n", ""),
  ("""  IF pg_get_function_result('public.get_my_dating_matches(integer)'::regprocedure) ~* '(user_id|pair_key)' THEN
    RAISE EXCEPTION 'match payload exposes internal identity';
  END IF;""",
   f"""  IF to_regprocedure('public.get_my_dating_matches(integer)') IS NOT NULL THEN {W} (carry 8): the v1 match read is gone
    RAISE EXCEPTION 'the v1 match read (no device check) survived W5a'; {W}
  END IF;"""),
  ("""  INSERT INTO public.dating_introductions(
    id, pair_key, user_low_id, user_high_id, display_band, explanation_features,
    low_summary, high_summary, state, expires_at,
    algorithm_version, snapshot_low_id, snapshot_high_id, internal_score
  ) VALUES (
    '00000000-0000-0000-0000-000000bd0000', public.dating_pair_key(b,d),
    LEAST(b,d), GREATEST(b,d), 'some_shared_ground','{}','x','x',
    'presented', now() + interval '7 days', 'test-active-v1',
    CASE WHEN b < d THEN v_snap_b ELSE v_snap_d END,
    CASE WHEN b < d THEN v_snap_d ELSE v_snap_b END, 0.5
  ) ON CONFLICT (id) DO NOTHING;""",
   MODE_V2.format(W=W, rows="""('00000000-0000-0000-0000-000000bd0000', public.dating_pair_key(b,d), LEAST(b,d), GREATEST(b,d), 'presented', now() + interval '7 days', 'test-active-v1')""")),
], 'dating_mode: v2 introductions, seen in Dating, the v1 match read gone')

edit('scripts/concurrency/dating_kill_switch_races.sh', [
  ("""DECLARE v_low uuid; v_high uuid; v_id uuid;
BEGIN
  INSERT INTO public.dating_feature_snapshots (user_id, algorithm_version) VALUES (least(p_a, p_b), 'race') RETURNING id INTO v_low;
  INSERT INTO public.dating_feature_snapshots (user_id, algorithm_version) VALUES (greatest(p_a, p_b), 'race') RETURNING id INTO v_high;
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, display_band, state,
                                           algorithm_version, snapshot_low_id, snapshot_high_id, internal_score)
  VALUES (public.dating_pair_key(p_a, p_b), least(p_a, p_b), greatest(p_a, p_b), 'some_shared_ground', 'presented',
          'race', v_low, v_high, 0.5) RETURNING id INTO v_id;""",
   """DECLARE v_id uuid;
BEGIN
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version) -- Spec 2 W5a
  VALUES (public.dating_pair_key(p_a, p_b), least(p_a, p_b), greatest(p_a, p_b), 'presented', 'race') -- Spec 2 W5a
  RETURNING id INTO v_id;"""),
  ("  DELETE FROM public.dating_feature_snapshots WHERE user_id::text LIKE '5e2f%';\n", ""),
], 'races: v2 introductions')

edit('supabase/sql/dev_enable_spec2_dating_flags.sql', [
  ("    ('dating_alignment_algorithm_v1', true),\n", ""),
  ("""  -- Spec 2 W4a (§3.3.5, §4.9): the verification mode, only when none is set""",
   """  -- Spec 2 W5a (§4.9): introductions_v2 active with DEV- review references
  -- Spec 2 W5a (production refuses DEV- references; the owner activates it
  -- Spec 2 W5a there with real ones, the W5 gate). Any other active config retires.
  UPDATE public.dating_algorithm_configs SET state = 'retired', retired_at = now() -- Spec 2 W5a
   WHERE state = 'active' AND version <> 'introductions_v2'; -- Spec 2 W5a
  UPDATE public.dating_algorithm_configs -- Spec 2 W5a
     SET state = 'active', activated_at = coalesce(activated_at, now()), -- Spec 2 W5a
         product_review_ref = coalesce(product_review_ref, 'DEV-product'), clinical_review_ref = coalesce(clinical_review_ref, 'DEV-clinical'), -- Spec 2 W5a
         fairness_review_ref = coalesce(fairness_review_ref, 'DEV-fairness'), safety_review_ref = coalesce(safety_review_ref, 'DEV-safety') -- Spec 2 W5a
   WHERE version = 'introductions_v2' AND state <> 'active'; -- Spec 2 W5a

  -- Spec 2 W4a (§3.3.5, §4.9): the verification mode, only when none is set"""),
], 'dev script: no alignment flag; introductions_v2 active')

edit(T + 'dating_rls_canary.sql', [
  ("""  -- Spec 2 W4b (T3 review M-4): where a verification pause's check stands.
  ('private.dating_check_standing(uuid,text)', '', '');
""",
   """  -- Spec 2 W4b (T3 review M-4): where a verification pause's check stands.
  ('private.dating_check_standing(uuid,text)', '', '');
-- ---------------------------------------------------------------------
-- W5a (migration 1): the v1 trait objects are gone; the person, the pair
-- and the filters are the database's own, the service role included
-- (they decrypt or read who was introduced, S-4, S-5).
DELETE FROM allowed_rel WHERE name = 'dating_feature_snapshots';
DELETE FROM allowed_fn WHERE sig IN ('build_dating_feature_snapshot(uuid,text)', 'dating_alignment_reasons(jsonb,jsonb)',
  'dating_alignment_score(jsonb,jsonb,jsonb)', 'dating_component_similarity(numeric,numeric)', 'dating_set_similarity(jsonb,jsonb)',
  'dating_normalize_scalar(numeric,numeric,numeric)', 'dating_has_historical_consent(uuid)',
  'generate_dating_candidates_for_user(uuid,text,text,text)', 'run_dating_candidate_generation(text)', 'get_my_dating_matches(integer)');
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('private.dating_matches_pair_key()', '', ''),
  ('private.dating_config_review_guard()', '', ''),
  ('private.dating_intro_config()', '', ''),
  ('private.dating_cool_off_ends_at(uuid)', '', ''),
  ('private.dating_last_seen_at(uuid)', '', ''),
  ('private.dating_pair_is_man_woman(text,text)', '', ''),
  ('private.dating_person(uuid,timestamp with time zone,jsonb)', '', ''),
  ('private.dating_person_current(uuid,timestamp with time zone,jsonb)', '', ''),
  ('private.dating_admits(private.dating_gen_person,private.dating_gen_person,jsonb)', '', ''),
  ('private.dating_pair_safe(uuid,uuid,text,text)', '', ''),
  ('private.dating_pair_new(uuid,uuid)', '', '');
UPDATE allowed_fn SET service = '' WHERE sig IN ('dating_pair_passes_hard_filters(uuid,uuid)', 'get_my_dating_introductions(integer)');
"""),
], 'canary: W5a rows')
```

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5
python3 -I $D/edit_tests_T1.py
rm supabase/tests/dating_alignment_contracts.sql
$D/suite.sh attune_spec3a > $D/sql-after-T1.txt; echo "$(grep -c '^PASS' $D/sql-after-T1.txt) PASS, $(grep -c '^FAIL' $D/sql-after-T1.txt) FAIL"
diff <(grep FAIL $D/sql-baseline.txt) <(grep FAIL $D/sql-after-T1.txt)
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -c 'BEGIN' -f supabase/tests/dating_v2_identity_contracts.sql -c 'ROLLBACK' 2>&1 | grep -m1 ERROR
```

Expected: the nine edit lines (`dating_v2_identity_contracts.sql: 2 edit(s) …`, `… 7 generation calls now the W5a tick`, `country_safety_config_contracts.sql: 4 edit(s) …`, `dating_v2_setup_contracts.sql: 2 edit(s) …`, `dating_v2_eligibility_contracts.sql: 1 edit(s) …`, `dating_mode_contracts.sql: 4 edit(s) …`, `dating_kill_switch_races.sh: 2 edit(s) …`, `dev_enable_spec2_dating_flags.sql: 2 edit(s) …`, `dating_rls_canary.sql: 1 edit(s) …`); `159 PASS, 15 FAIL`; the diff shows only `> FAIL dating_v2_identity_contracts.sql`; its error is `function public.run_dating_generation_tick() does not exist` (Task 2 creates the tick; the identity contract's seven generation calls already name it).

- [ ] **Step 11: The mutants (§7.5 2, 3, 20; carries)**

Create `$D/mut_T1.py` with exactly:

```python
# Spec 2 W5a Task 1 mutants (mutate.py): each must make
# dating_v2_matching_contracts.sql fail with a CONTRACT VIOLATED line.
M = '-- Spec 2 W5a'
MUTS = {
  # Mutant 2 (§7.5): one direction of a filter dropped.
  'm2_ages_one_way': ("    AND a.age BETWEEN b.min_age AND b.max_age\n", ""),
  'm2_seeking_one_way': ("    AND b.seeking && a.pools\n", ""),
  'm2_scope_one_way': ("          AND (b.scope = 'country' OR a.region = b.region)\n", ""),
  'm2_side_one_way': ("          AND (b.scope IS DISTINCT FROM 'side' OR b.side IS NULL OR a.side = b.side)\n", ""),
  'm2_abroad_one_way': ("ELSE b.country = ANY (a.open_abroad) AND a.country = ANY (b.open_abroad) AND",
                        "ELSE b.country = ANY (a.open_abroad) AND"),
  'm2_intention_one_way': ("    AND (p_cfg -> 'intention_matrix' -> b.intention) ? a.intention\n    AND a.intention = ANY (b.intention_open)\n", ""),
  'm2_children_one_way': ("    AND NOT (b.want_must_match AND ((b.children_want = 'yes' AND a.children_want = 'no') OR (b.children_want = 'no' AND a.children_want = 'yes')))\n", ""),
  'm2_parents_one_way': ("    AND NOT (b.exclude_parents AND a.children_have)\n", ""),
  'm2_faith_one_way': ("    AND (b.importance IS DISTINCT FROM 'must_share' OR (a.faith IS NOT NULL AND a.faith <> 'prefer_not_to_say' AND a.faith = b.faith)),\n",
                       "    ,\n"),
  # Mutant 3 (§7.5): the same-gender check removed, or its context ignored.
  'm3_no_same_gender': ("    AND (private.dating_pair_is_man_woman(a.identity, b.identity) OR (a.same_gender_ok AND b.same_gender_ok))\n", ""),
  'm3_context_ignored': ("  v.same_gender_ok := coalesce(private.dating_same_gender_on(v.country), false)\n    AND EXISTS",
                         "  v.same_gender_ok := coalesce(private.dating_same_gender_on(v.country), false)\n    OR EXISTS"),
  # Mutant 20 (§7.5): the cap CHECK removed and the config set to 5.
  'm20_cap_check': ('RAW', "ALTER TABLE public.dating_algorithm_configs DROP CONSTRAINT dating_algorithm_configs_caps_check;\n"
                           "UPDATE public.dating_algorithm_configs SET config = config || '{\"daily_new_max\": 5}', "
                           "config_hash = encode(extensions.digest((config || '{\"daily_new_max\": 5}')::text, 'sha256'), 'hex') "
                           "WHERE version = 'introductions_v2';\n"),
  'dev_guard_off': ("  IF NEW.state = 'active' AND private.attune_environment() IS NOT DISTINCT FROM 'production'",
                    "  IF false AND private.attune_environment() IS NOT DISTINCT FROM 'production'"),
  # Carries.
  'carry1_cool_off_ignored': ("    AND NOT EXISTS (SELECT 1 FROM public.dating_session_context AS c\n                     WHERE c.user_id = p_user AND c.dating_allowed_here IS FALSE)\n    AND coalesce(private.dating_cool_off_ends_at(p_user) <= private.dating_first_drop_at(p_user, p_at), false);",
                              "    AND NOT EXISTS (SELECT 1 FROM public.dating_session_context AS c\n                     WHERE c.user_id = p_user AND c.dating_allowed_here IS FALSE);"),
  'traveller_ignored': ("    AND NOT EXISTS (SELECT 1 FROM public.dating_session_context AS c\n                     WHERE c.user_id = p_user AND c.dating_allowed_here IS FALSE)\n", ""),
  'fresh_ignored': (f"    AND coalesce(private.dating_last_seen_at(p_user_id) >= now() - make_interval(days => {M} (§2.3): fresh, else out of others' days\n          coalesce(((private.dating_intro_config()).o_config ->> 'context_fresh_days')::int, 14)), false); {M}",
                    "    ;"),
  'carry2_null_admits': ("    AND (b.importance IS DISTINCT FROM 'must_share' OR (a.faith IS NOT NULL AND a.faith <> 'prefer_not_to_say' AND a.faith = b.faith)),\n    false);",
                         "    AND (b.importance IS DISTINCT FROM 'must_share' OR (a.faith IS NOT NULL AND a.faith <> 'prefer_not_to_say' AND a.faith = b.faith)),\n    true);"),
  'carry4_kept_ignored': ('LIVE', ('public.dating_never_introduce_excludes(uuid,uuid)', [
      ("WHERE n.owner_user_id = p_a AND n.phone_hmac = v_hmac)", "WHERE n.owner_user_id = p_a AND n.phone_hmac = v_hmac AND n.kept_at IS NULL)"),
      ("WHERE n.owner_user_id = p_b AND n.phone_hmac = v_hmac)", "WHERE n.owner_user_id = p_b AND n.phone_hmac = v_hmac AND n.kept_at IS NULL)")])),
  'block_hmac_ignored': ("    AND NOT EXISTS (SELECT 1 FROM public.dating_block_hmacs AS h\n                     WHERE (h.blocker_hmac = p_ha AND h.blocked_hmac = p_hb)\n                        OR (h.blocker_hmac = p_hb AND h.blocked_hmac = p_ha))\n", ""),
  'r17_act_device_late': (f"  IF public.dating_require_trusted_device() IS NOT TRUE THEN {M} (carry 8): the caller's own phone, before anything\n    RAISE EXCEPTION 'reverify_device' USING ERRCODE = '42501'; {M}\n  END IF; {M}\n", ""),
  'act_before_drop': (f"     OR now() < (CASE WHEN v_intro.user_low_id = v_user_id THEN v_intro.visible_from_low ELSE v_intro.visible_from_high END) THEN {M}: not before this side's drop",
                      "     THEN"),
  'carry10_one_day': (f"       AND coalesce(s.awaiting_since, s.created_at) > now() - interval '72 hours' {M} (carry 10): as the sweep",
                      "       AND s.created_at > now() - interval '1 day'"),
  'drop_tz_ignored': (f"  v_tz := coalesce(CASE WHEN EXISTS", f"  v_tz := coalesce(CASE WHEN false AND EXISTS"),
}
```

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5
python3 -I $D/mutate.py supabase/migrations/20261119100000_dating_v2_matching.sql supabase/tests/dating_v2_matching_contracts.sql $D/mut_T1.py $D/mut supabase/migrations/20261119100010_dating_v2_matching_grants.sql > $D/mut_T1.txt 2>&1
grep -c 'CONTRACT VIOLATED' $D/mut_T1.txt; grep -v 'CONTRACT VIOLATED' $D/mut_T1.txt
```

Expected: `23`, and nothing else printed. Among them: `m2_ages_one_way: ERROR:  CONTRACT VIOLATED: the filters are not symmetric for 01 and 03 (mutant 2)`, `m3_no_same_gender: … filter fixture "4 two women, one not allowed" admitted t/t (expected f)`, `m20_cap_check: … the introductions_v2 seed or alignment_v1's retirement is wrong`, `carry4_kept_ignored: … hard filter fixture "13 kept on the list from before (carry 4)" answered tt (expected ff)`, `r17_act_device_late: … another phone's act answered 22023:introduction_unavailable and left the introduction generated`, `carry10_one_day: … a re-check submitted 49 hours ago is not read back (carry 10)`. (The v1 read's own device check is not a separate mutant: the viewer's candidate check already refuses another phone through gate 8, so removing it is equivalent.)

- [ ] **Step 12: Record the tree**

Do not commit; record the tree in the report (`T=$(mktemp -u); GIT_INDEX_FILE=$T git read-tree HEAD && GIT_INDEX_FILE=$T git add -A && GIT_INDEX_FILE=$T git write-tree; rm -f $T`).

### Task 2: Generation: the hourly tick, caps, ranking, reasons, determinism, the cron (§5.3–§5.8, §4.2, §4.6, §6.9, §7.5 mutant 6; carries 4, 6; R-5, R-8, R-9, R-10, R-30)

**Files:**
- Create: `$D/{mig_T2_generation.sql, contract_T2.sql, splice_T2.py, edit_tests_T2.py, mut_T2.py}`
- Modify: `supabase/migrations/20261119100000_dating_v2_matching.sql` (rebuilt with the generation section), `…100010_…_grants.sql`, `supabase/tests/dating_v2_matching_contracts.sql`, `supabase/tests/dating_rls_canary.sql`

**Interfaces:**
- Consumes: Task 1's person row and filters, `private.dating_intro_config()`, `private.dating_cool_off_ends_at`.
- Produces: `public.run_dating_generation_tick(p_now timestamptz DEFAULT now(), p_country text DEFAULT NULL)` (cron's; refuses before any work with `{skipped: flag_disabled|exclusion_key_mismatch|missing_key|field_key_mismatch|no_active_config}`, else `{runs:[…]}`), `private.dating_capacity(uuid, timestamptz, jsonb)` (W5c re-creates it), `private.dating_open_chats(uuid, timestamptz)` (W6a re-creates it), `private.dating_reasons(gen_person, gen_person)`; introductions carry `created_at = p_now`, `rank_detail {f, v, exposure, jitter, seq}`, `visible_from_*` = each side's next drop, `expires_at` = the later + 7 days.

- [ ] **Step 1: Write the failing sections**

Create `$D/contract_T2.sql` with exactly (sections G–I):

```sql
-- =====================================================================
-- G. (§5.3-§5.8; mutant 6; carries 1, 4, 6) Generation. Everyone from the
--    sections above leaves Dating first, so the run sees only G's people.
--    Refusals before any work, each counted; one run: GH's partition and
--    cohort, both sides' drops, the seven days, up to three reasons, the
--    rank detail, a kept never-introduce pair left out, only the best band
--    (§5.4 6); a GB person open to Ghana introduced across the border
--    when both are open; a second run creates 0; the
--    same seed makes the same introductions in the same order; capacity
--    3 a day, 6 waiting, 3 open chats; nobody over 3 in a run; a thin pool
--    yields 0 and is counted; a side's own unanswered seven days end the
--    pair; a run that fails publishes nothing and dead-letters after three
--    tries; every temp table a Dating function makes is dropped at commit.
-- =====================================================================
DO $$
DECLARE
  v_at constant timestamptz := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + interval '3 hours 17 minutes';
  v_cfg constant jsonb := (private.dating_intro_config()).o_config;
  w1 uuid;
  w2 uuid;
  m1 uuid;
  m2 uuid;
  g1 uuid;
  v jsonb;
  v_first jsonb;
  v_again jsonb;
  v_n bigint;
  v_bad text;
  v_empty bigint;
BEGIN
  UPDATE public.dating_enrollments SET state = 'paused', pause_reason = 'user' WHERE state = 'active';
  w1 := pg_temp.ready('61', '{"abroad": ["GB"], "family": "early"}');
  w2 := pg_temp.ready('62', '{"intention": "marriage", "timeline": "few_years"}');
  m1 := pg_temp.ready('63', '{"identity": "man", "seeking": ["woman"], "family": "early"}');
  m2 := pg_temp.ready('64', '{"identity": "man", "seeking": ["woman"], "intention": "marriage", "timeline": "few_years"}');
  g1 := pg_temp.ready('65', '{"identity": "man", "seeking": ["woman"], "country": "GB", "region": "TLI", "abroad": ["GH"]}');
  -- Carry 4: w2's kept list names m2.
  INSERT INTO public.dating_never_introduce (owner_user_id, phone_hmac, last_two, kept_at)
  VALUES (w2, public.dating_phone_hmac_for_user(m2), '64', now() - interval '2 days');

  -- G1. Refusals before any work, each counted.
  IF pg_temp.probe(ARRAY['UPDATE public.feature_flags SET enabled = false WHERE key = ''dating_candidate_generation'''],
       format('SELECT (public.run_dating_generation_tick(%L, ''GH'') ->> ''skipped'') || '':'' || pg_temp.metric(''dating.generation.skipped'')', v_at))
       IS DISTINCT FROM 'flag_disabled:' || (pg_temp.metric('dating.generation.skipped') + 1)
     OR pg_temp.probe(ARRAY['UPDATE public.dating_algorithm_configs SET state = ''retired'', retired_at = now() WHERE version = ''introductions_v2'''],
       format('SELECT public.run_dating_generation_tick(%L, ''GH'') ->> ''skipped''', v_at)) IS DISTINCT FROM 'no_active_config'
     OR pg_temp.probe(ARRAY['SELECT set_config(''app.settings.dating_field_key'', '''', true)'],
       format('SELECT public.run_dating_generation_tick(%L, ''GH'') ->> ''skipped''', v_at)) IS DISTINCT FROM 'missing_key'
     -- Not Ghana's hour: nothing runs.
     OR public.run_dating_generation_tick(v_at + interval '1 hour', 'GH') IS DISTINCT FROM '{"runs": []}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: generation did not refuse (and count) before any work';
  END IF;

  -- G2. One run.
  v_empty := pg_temp.metric('dating.empty_day.gh.aa');
  v := public.run_dating_generation_tick(v_at, 'GH');
  IF v #>> '{runs,0,partition}' IS DISTINCT FROM 'GH' OR (v #>> '{runs,0,created}')::int IS DISTINCT FROM 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the run answered % (expected GH with 3 introductions)', v;
  END IF;
  SELECT string_agg(x.pair_key || ': ' || x.why, '; ') INTO v_bad FROM (
    SELECT i.pair_key, concat_ws(', ',
             CASE WHEN i.partition_key IS DISTINCT FROM 'GH' OR i.cohort_window IS DISTINCT FROM (v_at AT TIME ZONE 'Africa/Accra')::date THEN 'partition/cohort' END,
             CASE WHEN i.visible_from_low IS DISTINCT FROM private.dating_first_drop_at(i.user_low_id, v_at)
                    OR i.visible_from_high IS DISTINCT FROM private.dating_first_drop_at(i.user_high_id, v_at) THEN 'drops' END,
             CASE WHEN i.expires_at IS DISTINCT FROM greatest(i.visible_from_low, i.visible_from_high) + interval '7 days' THEN 'expiry' END,
             CASE WHEN cardinality(i.reasons) > 3 OR i.state <> 'generated' THEN 'shape' END,
             CASE WHEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(i.rank_detail) AS k) IS DISTINCT FROM ARRAY['exposure', 'f', 'jitter', 'seq', 'v'] THEN 'rank detail' END) AS why
      FROM public.dating_introductions AS i WHERE i.created_at = v_at) AS x WHERE x.why <> '';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an introduction is malformed: %', v_bad;
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_introductions WHERE pair_key = public.dating_pair_key(w2, m2))
     -- §5.4 6: g1 (abroad, no shared region) is outside w1's best band.
     OR EXISTS (SELECT 1 FROM public.dating_introductions WHERE pair_key = public.dating_pair_key(w1, g1))
     OR (SELECT reasons FROM public.dating_introductions WHERE pair_key = public.dating_pair_key(w1, m1))
        IS DISTINCT FROM ARRAY['same_intention', 'children_want_yes', 'family_same_early'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a kept never-introduce pair or a pair outside the band was introduced, or w1-m1''s reasons are % (carry 4, §5.4, §5.8)',
      (SELECT reasons FROM public.dating_introductions WHERE pair_key = public.dating_pair_key(w1, m1));
  END IF;

  -- G3. A second run of the cohort creates 0.
  v_n := (SELECT count(*) FROM public.dating_introductions);
  v := public.run_dating_generation_tick(v_at, 'GH');
  IF v #>> '{runs,0,skipped}' IS DISTINCT FROM 'partition_unavailable' OR (SELECT count(*) FROM public.dating_introductions) <> v_n THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second run of the cohort answered % and created %', v, (SELECT count(*) FROM public.dating_introductions) - v_n;
  END IF;

  -- G4. The same seed, the same introductions in the same order (§5.7).
  SELECT jsonb_agg(jsonb_build_array(i.pair_key, i.rank_detail, i.reasons, i.visible_from_low, i.visible_from_high) ORDER BY (i.rank_detail ->> 'seq')::int)
    INTO v_first FROM public.dating_introductions AS i WHERE i.created_at = v_at;
  DELETE FROM public.dating_introductions WHERE created_at = v_at;
  DELETE FROM public.dating_generation_runs WHERE partition_key = 'GH';
  PERFORM public.run_dating_generation_tick(v_at, 'GH');
  SELECT jsonb_agg(jsonb_build_array(i.pair_key, i.rank_detail, i.reasons, i.visible_from_low, i.visible_from_high) ORDER BY (i.rank_detail ->> 'seq')::int)
    INTO v_again FROM public.dating_introductions AS i WHERE i.created_at = v_at;
  IF v_again IS DISTINCT FROM v_first THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the same seed made different introductions: % then %', v_first, v_again;
  END IF;

  -- G5. Capacity: 3 a day, 6 waiting, 3 open chats.
  IF private.dating_capacity(w1, v_at, v_cfg) <> 1 OR private.dating_capacity(m1, v_at, v_cfg) <> 1
     OR pg_temp.probe(ARRAY[format('UPDATE public.dating_introductions SET created_at = %L::timestamptz - interval ''2 days'' WHERE %L IN (user_low_id, user_high_id)', v_at, w1)],
                      format('SELECT private.dating_capacity(%L, %L, %L)', w1, v_at, v_cfg)) IS DISTINCT FROM '3'
     OR pg_temp.probe(ARRAY[format('INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high, created_at, expires_at) SELECT public.dating_pair_key(%L, o), least(%L::uuid, o), greatest(%L::uuid, o), ''generated'', ''introductions_v2'', %L, %L, %L::timestamptz - interval ''2 days'', %L::timestamptz + interval ''5 days'' FROM unnest(ARRAY[pg_temp.id(''11''), pg_temp.id(''21''), pg_temp.id(''22''), pg_temp.id(''23''), pg_temp.id(''24''), pg_temp.id(''31'')]) AS o', m2, m2, m2, v_at, v_at, v_at, v_at),
                           format('UPDATE public.dating_introductions SET created_at = %L::timestamptz - interval ''2 days'' WHERE %L IN (user_low_id, user_high_id) AND created_at = %L', v_at, m2, v_at)],
                      format('SELECT private.dating_capacity(%L, %L, %L)', m2, v_at, v_cfg)) IS DISTINCT FROM '0'
     OR pg_temp.probe(ARRAY[format('INSERT INTO public.dating_matches (user_low_id, user_high_id, state, matched_at) SELECT least(%L::uuid, o), greatest(%L::uuid, o), ''active'', now() FROM unnest(ARRAY[pg_temp.id(''11''), pg_temp.id(''21''), pg_temp.id(''22'')]) AS o', g1, g1)],
                      format('SELECT private.dating_capacity(%L, %L, %L)', g1, v_at + interval '2 days', v_cfg)) IS DISTINCT FROM '0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: capacity is not min(3 - today, 6 - waiting), 0 at 3 open chats';
  END IF;
END $$;

-- G6. Nobody over 3 in a run; a thin pool yields 0 and is counted; a
--     side's own unanswered seven days end the pair; a failing run
--     publishes nothing and dead-letters after three tries; temp tables.
DO $$
DECLARE
  v_at constant timestamptz := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + interval '1 day 3 hours 17 minutes';
  m uuid;
  t uuid;
  w3 uuid;
  g2 uuid;
  v jsonb;
  v_empty bigint;
  v_unreadable bigint;
  v_id uuid;
  v_bad text;
BEGIN
  UPDATE public.dating_enrollments SET state = 'paused', pause_reason = 'user' WHERE state = 'active';
  m := pg_temp.ready('70', '{"identity": "man", "seeking": ["woman"]}');
  PERFORM pg_temp.ready(n::text, '{}') FROM generate_series(71, 75) AS n;
  t := pg_temp.ready('76', '{"min": 60, "max": 70}');
  -- §2.6: a woman in Ashanti open to the UK, a London man open to Ghana.
  w3 := pg_temp.ready('77', '{"region": "AH", "abroad": ["GB"]}');
  g2 := pg_temp.ready('78', '{"identity": "man", "seeking": ["woman"], "country": "GB", "region": "TLI", "abroad": ["GH"]}');
  -- An unreadable answer skips that person only, counted.
  UPDATE public.dating_profile_sensitive SET identity_enc = '\x01c30d0407'::bytea WHERE user_id = pg_temp.id('75');
  v_unreadable := pg_temp.metric('dating.generation.unreadable');
  v_empty := pg_temp.metric('dating.empty_day.gh.aa');
  v := public.run_dating_generation_tick(v_at, 'GH');
  IF pg_temp.metric('dating.generation.unreadable') <> v_unreadable + 1
     OR EXISTS (SELECT 1 FROM public.dating_introductions WHERE pg_temp.id('75') IN (user_low_id, user_high_id)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unreadable answer stopped the run or was introduced uncounted';
  END IF;
  IF (SELECT count(*) FROM public.dating_introductions WHERE m IN (user_low_id, user_high_id) AND created_at = v_at) <> 3
     OR (v #>> '{runs,0,created}')::int <> 4 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one man and five women made % (expected 3: §5.3 daily_new_max; and one across the border)', v;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_introductions WHERE pair_key = public.dating_pair_key(w3, g2) AND partition_key = 'GH'
                    AND reasons = ARRAY['same_intention', 'children_want_yes'])
     OR pg_temp.probe(ARRAY[format('DELETE FROM public.dating_introductions WHERE pair_key = public.dating_pair_key(%L, %L)', w3, g2),
                            format('DELETE FROM public.dating_generation_runs WHERE partition_key = ''GH'' AND cohort_window = %L', (v_at AT TIME ZONE 'Africa/Accra')::date::text),
                            format('UPDATE public.dating_preferences SET open_abroad = ''{}'' WHERE user_id = %L', g2),
                            format('SELECT public.run_dating_generation_tick(%L, ''GH'')', v_at)],
                      format('SELECT count(*) FROM public.dating_introductions WHERE pair_key = public.dating_pair_key(%L, %L)', w3, g2))
        IS DISTINCT FROM '0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the border pair open both ways was not introduced in Ghana''s run, or was when one side is not open (§2.6)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_introductions WHERE t IN (user_low_id, user_high_id))
     OR pg_temp.metric('dating.empty_day.gh.aa') < v_empty + 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a thin pool was filled or not counted (§5.6)';
  END IF;
  -- Per side: an unanswered side's own seven days end the pair; an
  -- answered side waits for the other's.
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high, expires_at)
  VALUES ('w5life:a', least(t, m), greatest(t, m), 'generated', 'introductions_v2', now() - interval '8 days', now() - interval '1 day', now() + interval '6 days')
  RETURNING id INTO v_id;
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, low_action, algorithm_version, visible_from_low, visible_from_high, expires_at)
  VALUES ('w5life:b', least(t, m), greatest(t, m), 'interested', 'interested', 'introductions_v2', now() - interval '8 days', now() - interval '1 day', now() + interval '6 days');
  PERFORM public.expire_dating_introductions();
  IF (SELECT state FROM public.dating_introductions WHERE pair_key = 'w5life:a') <> 'expired'
     OR (SELECT state FROM public.dating_introductions WHERE pair_key = 'w5life:b') <> 'interested' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the seven days are not per side (§5.3)';
  END IF;
  -- A run that fails: nothing published, failed, then dead-lettered.
  IF pg_temp.probe(ARRAY[
       'CREATE OR REPLACE FUNCTION private.dating_reasons(a private.dating_gen_person, b private.dating_gen_person) RETURNS text[] LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION ''w5 stand-in failure''; END $f$',
       format('DELETE FROM public.dating_generation_runs WHERE partition_key = ''GH'' AND cohort_window = %L', (v_at AT TIME ZONE 'Africa/Accra')::date::text),
       format('DELETE FROM public.dating_introductions WHERE created_at = %L', v_at),
       format('SELECT public.run_dating_generation_tick(%L, ''GH'')', v_at),
       format('SELECT public.run_dating_generation_tick(%L, ''GH'')', v_at),
       format('SELECT public.run_dating_generation_tick(%L, ''GH'')', v_at),
       format('SELECT public.run_dating_generation_tick(%L, ''GH'')', v_at)],
     format('SELECT r.last_error_code || '':'' || r.state || '':'' || r.attempts || '':'' || (SELECT count(*) FROM public.dating_introductions WHERE created_at = %L) FROM public.dating_generation_runs AS r WHERE r.partition_key = ''GH'' AND r.cohort_window = %L',
            v_at, (v_at AT TIME ZONE 'Africa/Accra')::date::text)) IS DISTINCT FROM 'P0001:dead_letter:3:0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failing run published or did not dead-letter after three tries';
  END IF;
  -- Mutant 6: every temp table a Dating function makes is dropped at commit.
  SELECT string_agg(p.oid::regprocedure::text, ', ') INTO v_bad
    FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'private') AND p.prosrc ~* 'CREATE\s+TEMP'
     AND (SELECT count(*) FROM regexp_matches(p.prosrc, 'CREATE\s+TEMP(ORARY)?\s+TABLE', 'gi'))
         <> (SELECT count(*) FROM regexp_matches(p.prosrc, 'CREATE\s+TEMP(ORARY)?\s+TABLE[^;]*ON\s+COMMIT\s+DROP', 'gi'))
     AND p.prosrc ~ 'dating_';
  IF v_bad IS NOT NULL OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'dating_generate_partition' AND prosrc ~ 'ON COMMIT DROP') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a temp table of decrypted answers can outlive its transaction (mutant 6): %', v_bad;
  END IF;
END $$;

-- =====================================================================
-- H. (§4.4 health v2) Today's generation per country and the active
--    config, for an operator.
-- I. (§4.6) The hourly cron.
-- =====================================================================
DO $$
DECLARE
  v jsonb := public.get_dating_operational_health();
BEGIN
  IF v #>> '{generation_by_country,GH,state}' IS DISTINCT FROM 'completed' OR v ->> 'introductions_config' IS DISTINCT FROM 'introductions_v2'
     OR NOT (v -> 'safety_counters_7d') ? 'dating.generation.skipped' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health does not show today''s generation: %', v -> 'generation_by_country';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dating-candidate-generation' AND schedule = '17 * * * *'
                  AND command = 'SELECT public.run_dating_generation_tick()') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the hourly generation cron is not scheduled';
  END IF;
END $$;
```

Create `$D/splice_T2.py` with exactly:

```python
# Spec 2 W5a Task 2: generation's sections G-I take the contract's marker.
import pathlib
D = pathlib.Path('.superpowers/sdd/2026-11-19-spec2-w5')
p = pathlib.Path('supabase/tests/dating_v2_matching_contracts.sql')
s = p.read_text()
marker = '-- (Task 2: sections G-I)\n'
assert s.count(marker) == 1, 'marker'
p.write_text(s.replace(marker, (D / 'contract_T2.sql').read_text()))
print(f'{p}: sections G-I in')
```

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5
python3 -I $D/splice_T2.py
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_matching_contracts.sql 2>&1 | grep -m1 ERROR
```

Expected: `supabase/tests/dating_v2_matching_contracts.sql: sections G-I in`; then `… ERROR:  function public.run_dating_generation_tick(timestamp with time zone, unknown) does not exist`.

- [ ] **Step 2: Write generation**

Create `$D/mig_T2_generation.sql` with exactly (sections 7 and 8; the builder puts it before the tail):

```sql

-- =====================================================================
-- 7. Generation v2 (§5.3-§5.8): the hourly tick.
-- =====================================================================
-- §5.3 open_chats: active matches where neither said "We met" and either a
-- message in the last 14 days or under 7 days old. W5 has no messages and
-- no "We met" yet (W6a and W6c re-create this): an active match under 7 days.
CREATE OR REPLACE FUNCTION private.dating_open_chats(p_user uuid, p_at timestamptz)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT count(*)::integer FROM public.dating_matches AS m
   WHERE m.state = 'active' AND p_user IN (m.user_low_id, m.user_high_id)
     AND m.matched_at > p_at - interval '7 days';
$$;

-- §5.3 capacity: 0 at 3 open chats; else min(3 - today, 6 - waiting),
-- floored at 0. today counts the last 20 hours (one run per country a
-- day; a second partition never counts twice); waiting counts cards the
-- person can still answer. (W5c adds the dragnet throttle here.)
CREATE OR REPLACE FUNCTION private.dating_capacity(p_user uuid, p_at timestamptz, p_cfg jsonb)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE
    WHEN private.dating_open_chats(p_user, p_at) >= coalesce((p_cfg ->> 'open_chat_pause_at')::int, 3) THEN 0
    ELSE greatest(0, least(
      (p_cfg ->> 'daily_new_max')::int
        - (SELECT count(*)::int FROM public.dating_introductions AS i
            WHERE p_user IN (i.user_low_id, i.user_high_id)
              AND i.created_at > p_at - interval '20 hours' AND i.created_at <= p_at),
      (p_cfg ->> 'waiting_max')::int
        - (SELECT count(*)::int FROM public.dating_introductions AS i
            WHERE p_user IN (i.user_low_id, i.user_high_id)
              AND i.state IN ('generated', 'presented', 'interested')
              AND i.expires_at > p_at
              AND CASE WHEN i.user_low_id = p_user THEN i.low_action IS NULL
                         AND i.visible_from_low + make_interval(days => (p_cfg ->> 'lifetime_days')::int) > p_at
                       ELSE i.high_action IS NULL
                         AND i.visible_from_high + make_interval(days => (p_cfg ->> 'lifetime_days')::int) > p_at END)))
  END;
$$;

-- §5.8: up to three reason ids, from what both stated and may show, in
-- the spec's order; faith only when both show it; family is shared ground.
-- No reason: same_region, or across_borders; never a field's value.
CREATE OR REPLACE FUNCTION private.dating_reasons(a private.dating_gen_person, b private.dating_gen_person)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  WITH r(n, id) AS (VALUES
    (1, CASE WHEN a.intention = 'marriage' AND b.intention = 'marriage' AND a.timeline = b.timeline
              AND a.timeline_visible AND b.timeline_visible THEN 'same_intention_timeline' END),
    (2, CASE WHEN a.intention = b.intention
              AND NOT (a.intention = 'marriage' AND a.timeline = b.timeline AND a.timeline_visible AND b.timeline_visible)
              THEN 'same_intention' END),
    (3, CASE WHEN a.intention <> b.intention AND a.intention IN ('marriage', 'committed')
              AND b.intention IN ('marriage', 'committed') THEN 'compatible_intention' END),
    (4, CASE WHEN a.children_want = 'yes' AND b.children_want = 'yes' THEN 'children_want_yes'
             WHEN a.children_want = 'no' AND b.children_want = 'no' THEN 'children_want_no' END),
    (5, CASE WHEN a.children_have AND b.children_have THEN 'children_have_both' END),
    (6, CASE WHEN a.faith_visible AND b.faith_visible AND a.faith = b.faith
              AND a.faith NOT IN ('none', 'other', 'prefer_not_to_say') THEN 'same_faith' END),
    (7, CASE WHEN a.faith_visible AND b.faith_visible AND a.importance = 'must_share'
              AND b.importance = 'must_share' THEN 'faith_matters' END),
    (8, CASE WHEN a.family = b.family THEN 'family_same_' || a.family END),
    (9, CASE WHEN a.country = b.country AND a.region = b.region AND a.side IS NOT NULL AND a.side = b.side THEN 'same_side'
             WHEN a.country = b.country AND a.region = b.region THEN 'same_region' END)),
  picked AS (SELECT coalesce(array_agg(r.id ORDER BY r.n) FILTER (WHERE r.id IS NOT NULL), '{}') AS ids FROM r)
  SELECT CASE WHEN cardinality(p.ids) > 0 THEN p.ids[1:3]
              WHEN a.country IS DISTINCT FROM b.country THEN ARRAY['across_borders']
              ELSE '{}'::text[] END
    FROM picked AS p;
$$;

-- A refusal before any work (§5.5): counted for health, never raised.
CREATE OR REPLACE FUNCTION private.dating_generation_skip(p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM private.bump_metric_internal('dating.generation.skipped');
  RETURN jsonb_build_object('skipped', p_reason);
END;
$$;

-- One partition's run (§5.4, §5.5, §5.7): claimed once per (version,
-- cohort, partition); people decrypted into a temp table dropped at commit
-- (§4.2: plaintext never reaches WAL); ordered by recent exposure, then a
-- seeded hash; each takes candidates in the best band, ordered by exposure
-- plus bounded jitter. A failure rolls the partition back (nothing half
-- published) and dead-letters it after max_attempts.
CREATE OR REPLACE FUNCTION private.dating_generate_partition(
  p_country text, p_region text, p_key text, p_window date, p_now timestamptz, p_version text, p_cfg jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_seed constant text := encode(extensions.digest(p_version || p_window::text || p_key, 'sha256'), 'hex');
  v_max constant integer := coalesce((p_cfg ->> 'max_attempts')::int, 3);
  v_people_max constant integer := (p_cfg ->> 'partition_people_max')::int;
  v_scan constant integer := (p_cfg ->> 'scan_limit')::int;
  v_fw constant numeric := coalesce((p_cfg #>> '{rank,feasibility_weight}')::numeric, 10);
  v_vw constant numeric := coalesce((p_cfg #>> '{rank,values_weight}')::numeric, 3);
  v_band constant numeric := coalesce((p_cfg #>> '{rank,band_width}')::numeric, 3);
  v_jit constant numeric := coalesce((p_cfg #>> '{rank,jitter}')::numeric, 2.0);
  v_window constant interval := make_interval(days => coalesce((p_cfg #>> '{rank,exposure_window_days}')::int, 7));
  v_life constant interval := make_interval(days => (p_cfg ->> 'lifetime_days')::int);
  v_run public.dating_generation_runs;
  v_u record;
  v_c record;
  v_cap integer;
  v_id uuid;
  v_seq integer := 0;
  v_state text;
  v_person private.dating_gen_person;
BEGIN
  INSERT INTO public.dating_generation_runs AS r
    (algorithm_version, cohort_window, state, seed, partition_key, attempts, started_at)
  VALUES (p_version, p_window::text, 'processing', v_seed, p_key, 1, now())
  ON CONFLICT (algorithm_version, cohort_window, partition_key) DO UPDATE
    SET state = 'processing', attempts = r.attempts + 1, started_at = now(), last_error_code = NULL
    WHERE r.state IN ('pending', 'failed') AND r.attempts < v_max
  RETURNING * INTO v_run;
  -- No row: completed, being run, or out of attempts. Never ours (§5.7).
  IF v_run.id IS NULL THEN
    RETURN jsonb_build_object('partition', p_key, 'skipped', 'partition_unavailable');
  END IF;

  BEGIN
    DROP TABLE IF EXISTS pg_temp.dating_gen_people;
    CREATE TEMP TABLE dating_gen_people (
      user_id uuid PRIMARY KEY,
      p private.dating_gen_person NOT NULL,
      home boolean NOT NULL,
      exposure integer NOT NULL,
      capacity integer NOT NULL
    ) ON COMMIT DROP;
    -- The partition's own people, then those elsewhere open to it (§5.5).
    FOR v_u IN
      SELECT x.user_id, x.home
        FROM (SELECT p.user_id, true AS home
                FROM public.dating_profiles AS p
                JOIN public.dating_enrollments AS e ON e.user_id = p.user_id AND e.state = 'active'
               WHERE p.country_code::text = p_country AND (p_region IS NULL OR p.region_code = p_region)
               ORDER BY p.user_id LIMIT v_people_max) AS x
      UNION ALL
      SELECT y.user_id, false
        FROM (SELECT d.user_id
                FROM public.dating_preferences AS d
                JOIN public.dating_profiles AS p ON p.user_id = d.user_id
                JOIN public.dating_enrollments AS e ON e.user_id = d.user_id AND e.state = 'active'
               WHERE p_country = ANY (d.open_abroad::text[]) AND p.country_code::text IS DISTINCT FROM p_country
               ORDER BY d.user_id LIMIT v_people_max) AS y
    LOOP
      BEGIN
        CONTINUE WHEN private.dating_person_current(v_u.user_id, p_now, p_cfg) IS NOT TRUE;
        v_person := private.dating_person(v_u.user_id, p_now, p_cfg);
        CONTINUE WHEN v_person IS NULL;
        INSERT INTO pg_temp.dating_gen_people (user_id, p, home, exposure, capacity)
        VALUES (v_u.user_id, v_person, v_u.home,
                (SELECT count(*)::int FROM public.dating_introductions AS i
                  WHERE v_u.user_id IN (i.user_low_id, i.user_high_id)
                    AND i.created_at > p_now - v_window AND i.created_at <= p_now),
                private.dating_capacity(v_u.user_id, p_now, p_cfg));
      EXCEPTION WHEN raise_exception THEN
        IF SQLERRM IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
          PERFORM private.bump_metric_internal('dating.generation.unreadable');
        ELSE
          RAISE;
        END IF;
      END;
    END LOOP;

    -- §5.4 1: fewest introductions in 7 days first, ties by the seed.
    FOR v_u IN
      SELECT g.user_id, g.p FROM pg_temp.dating_gen_people AS g
       WHERE g.home
       ORDER BY g.exposure, md5(v_seed || g.user_id::text), g.user_id
    LOOP
      SELECT g.capacity INTO v_cap FROM pg_temp.dating_gen_people AS g WHERE g.user_id = v_u.user_id;
      CONTINUE WHEN v_cap <= 0;
      FOR v_c IN
        WITH scanned AS MATERIALIZED (
          -- §5.5: at most scan_limit candidates looked at per person.
          SELECT g.user_id, g.p, g.exposure FROM pg_temp.dating_gen_people AS g
           WHERE g.user_id <> v_u.user_id AND g.capacity > 0
             AND (g.p).age BETWEEN (v_u.p).min_age AND (v_u.p).max_age
             AND (v_u.p).age BETWEEN (g.p).min_age AND (g.p).max_age
           ORDER BY g.exposure, md5(v_seed || g.user_id::text), g.user_id
           LIMIT v_scan
        ), admitted AS MATERIALIZED (
          SELECT s.* FROM scanned AS s WHERE private.dating_admits(v_u.p, s.p, p_cfg)
        ), passing AS (
          SELECT a.user_id, a.p, a.exposure,
                 -- §5.4 3: feasibility 0-3
                 (CASE WHEN (v_u.p).intention = (a.p).intention THEN 1 ELSE 0 END
                  + CASE WHEN (v_u.p).children_want = (a.p).children_want AND (a.p).children_want IN ('yes', 'no') THEN 1 ELSE 0 END
                  + CASE WHEN (v_u.p).country = (a.p).country AND (v_u.p).region = (a.p).region
                          AND ((v_u.p).side IS NULL OR (a.p).side IS NULL OR (v_u.p).side = (a.p).side) THEN 1 ELSE 0 END) AS f,
                 -- §5.4 4: stated values 0-4
                 (CASE WHEN (v_u.p).intention = 'marriage' AND (a.p).intention = 'marriage'
                         AND (v_u.p).timeline = (a.p).timeline THEN 1 ELSE 0 END
                  + CASE WHEN (v_u.p).importance = (a.p).importance THEN 1 ELSE 0 END
                  + CASE WHEN (v_u.p).faith = (a.p).faith AND (a.p).faith <> 'prefer_not_to_say' THEN 1 ELSE 0 END
                  + CASE WHEN (v_u.p).family = (a.p).family THEN 1 ELSE 0 END) AS v,
                 -- §5.4 7: (first 3 bytes of md5(seed || U || c)) mod 1000 / 1000 x 2.0
                 ((('x' || substr(md5(v_seed || v_u.user_id::text || a.user_id::text), 1, 6))::bit(24)::int % 1000)::numeric
                   / 1000 * v_jit) AS jitter
            FROM admitted AS a
           WHERE private.dating_pair_safe(v_u.user_id, a.user_id, (v_u.p).hmac, (a.p).hmac)
             AND private.dating_pair_new(v_u.user_id, a.user_id)
        ), banded AS (
          SELECT x.*, v_fw * x.f + v_vw * x.v AS base, max(v_fw * x.f + v_vw * x.v) OVER () AS best FROM passing AS x
        )
        SELECT b.user_id, b.p, b.f, b.v, b.exposure, b.jitter FROM banded AS b
         WHERE b.base >= b.best - v_band
         ORDER BY b.exposure + b.jitter, md5(v_seed || b.user_id::text), b.user_id
      LOOP
        EXIT WHEN v_cap <= 0;
        CONTINUE WHEN (SELECT g.capacity FROM pg_temp.dating_gen_people AS g WHERE g.user_id = v_c.user_id) <= 0;
        -- Both still enrolled at this statement (an exit committed since the
        -- people were read takes them out; R5 race).
        CONTINUE WHEN (SELECT count(*) FROM public.dating_enrollments AS e
                        WHERE e.user_id IN (v_u.user_id, v_c.user_id) AND e.state = 'active') <> 2;
        v_id := NULL;
        INSERT INTO public.dating_introductions AS i
          (pair_key, user_low_id, user_high_id, state, algorithm_version, cohort_window, partition_key,
           visible_from_low, visible_from_high, expires_at, reasons, rank_detail, created_at)
        SELECT public.dating_pair_key(v_u.user_id, v_c.user_id), least(v_u.user_id, v_c.user_id), greatest(v_u.user_id, v_c.user_id),
               'generated', p_version, p_window, p_key,
               CASE WHEN v_u.user_id < v_c.user_id THEN (v_u.p).visible_from ELSE (v_c.p).visible_from END,
               CASE WHEN v_u.user_id < v_c.user_id THEN (v_c.p).visible_from ELSE (v_u.p).visible_from END,
               greatest((v_u.p).visible_from, (v_c.p).visible_from) + v_life,
               private.dating_reasons(v_u.p, v_c.p),
               jsonb_build_object('f', v_c.f, 'v', v_c.v, 'exposure', v_c.exposure, 'jitter', round(v_c.jitter, 3), 'seq', v_seq + 1),
               p_now
        ON CONFLICT (pair_key) DO NOTHING
        RETURNING i.id INTO v_id;
        CONTINUE WHEN v_id IS NULL;
        v_seq := v_seq + 1;
        v_cap := v_cap - 1;
        UPDATE pg_temp.dating_gen_people AS g SET capacity = g.capacity - 1 WHERE g.user_id IN (v_u.user_id, v_c.user_id);
        -- §5.4 8: the candidate's exposure rises for the rest of the run.
        UPDATE pg_temp.dating_gen_people AS g SET exposure = g.exposure + 1 WHERE g.user_id = v_c.user_id;
      END LOOP;
    END LOOP;

    -- §5.6, §6.9: an empty day per person and region; deliveries per country.
    PERFORM private.bump_metric_internal('dating.empty_day.' || lower(p_country) || '.' || lower(coalesce((g.p).region, 'none')))
       FROM pg_temp.dating_gen_people AS g
      WHERE g.home AND NOT EXISTS (SELECT 1 FROM public.dating_introductions AS i
                                    WHERE g.user_id IN (i.user_low_id, i.user_high_id) AND i.created_at = p_now);
    IF v_seq > 0 THEN
      PERFORM private.bump_metric_internal('dating.intros_delivered.' || lower(p_country)) FROM generate_series(1, v_seq);
    END IF;
    UPDATE public.dating_generation_runs SET state = 'completed', completed_at = now() WHERE id = v_run.id;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
    UPDATE public.dating_generation_runs
       SET state = CASE WHEN attempts >= v_max THEN 'dead_letter' ELSE 'failed' END,
           last_error_code = v_state, completed_at = now()
     WHERE id = v_run.id;
    PERFORM private.bump_metric_internal('dating.generation.failed');
    RETURN jsonb_build_object('partition', p_key, 'error', v_state);
  END;
  RETURN jsonb_build_object('partition', p_key, 'cohort', p_window, 'created', v_seq);
END;
$$;

-- The hourly tick (§4.6, §5.5): every country whose generation hour is
-- now's UTC hour, its cohort the country's local date; a country larger
-- than partition_people_max splits by region (GH:AA). Refuses before any
-- work when Dating or generation is off, no reviewed config is active, or
-- a key is missing or replaced.
CREATE OR REPLACE FUNCTION public.run_dating_generation_tick(p_now timestamptz DEFAULT now(), p_country text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_version text;
  v_cfg jsonb;
  v_out jsonb := '[]'::jsonb;
  v_c record;
  v_r record;
  v_window date;
BEGIN
  IF public.dating_flag_enabled('dating_candidate_generation') IS NOT TRUE THEN
    RETURN private.dating_generation_skip('flag_disabled');
  END IF;
  -- The keys next (W1's guard, in its order: a replaced exclusion key is
  -- counted), then Dating itself, then the config.
  IF private.dating_exclusion_key_mismatch() THEN
    PERFORM private.bump_metric_internal('dating.exclusion_key.mismatch');
    RETURN private.dating_generation_skip('exclusion_key_mismatch');
  END IF;
  IF public.app_setting('dating_exclusion_key') IS NULL OR private.dating_field_key_present() IS NOT TRUE THEN
    RETURN private.dating_generation_skip('missing_key');
  END IF;
  IF private.dating_field_key_usable() IS NOT TRUE THEN
    PERFORM private.bump_metric_internal('dating.field_key.mismatch');
    RETURN private.dating_generation_skip('field_key_mismatch');
  END IF;
  IF public.dating_flag_enabled('dating_mode_enabled') IS NOT TRUE THEN
    RETURN private.dating_generation_skip('flag_disabled');
  END IF;
  SELECT c.o_version, c.o_config INTO v_version, v_cfg FROM private.dating_intro_config() AS c;
  IF v_version IS NULL THEN
    RETURN private.dating_generation_skip('no_active_config');
  END IF;
  FOR v_c IN
    SELECT c.country_code::text AS country, c.reference_tz
      FROM public.country_safety_config AS c
     WHERE c.is_current AND c.dating_enabled
       AND c.generation_hour_utc = extract(hour FROM p_now AT TIME ZONE 'UTC')
       AND (p_country IS NULL OR c.country_code::text = p_country)
     ORDER BY c.country_code
  LOOP
    v_window := (p_now AT TIME ZONE v_c.reference_tz)::date;
    IF (SELECT count(*) FROM public.dating_profiles AS p
          JOIN public.dating_enrollments AS e ON e.user_id = p.user_id AND e.state = 'active'
         WHERE p.country_code::text = v_c.country) > (v_cfg ->> 'partition_people_max')::int THEN
      FOR v_r IN
        SELECT DISTINCT p.region_code FROM public.dating_profiles AS p
          JOIN public.dating_enrollments AS e ON e.user_id = p.user_id AND e.state = 'active'
         WHERE p.country_code::text = v_c.country AND p.region_code IS NOT NULL ORDER BY 1
      LOOP
        v_out := v_out || jsonb_build_array(private.dating_generate_partition(
          v_c.country, v_r.region_code, v_c.country || ':' || v_r.region_code, v_window, p_now, v_version, v_cfg));
      END LOOP;
    ELSE
      v_out := v_out || jsonb_build_array(private.dating_generate_partition(
        v_c.country, NULL, v_c.country, v_window, p_now, v_version, v_cfg));
    END IF;
  END LOOP;
  RETURN jsonb_build_object('runs', v_out);
END;
$$;

-- =====================================================================
-- 8. The cron (§4.6): hourly at :17, replacing the weekly v1 job.
-- =====================================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dating-candidate-generation') THEN
    PERFORM cron.unschedule('dating-candidate-generation');
  END IF;
  PERFORM cron.schedule('dating-candidate-generation', '17 * * * *', 'SELECT public.run_dating_generation_tick()');
END $$;
REVOKE ALL ON FUNCTION private.dating_open_chats(uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_capacity(uuid, timestamptz, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_reasons(private.dating_gen_person, private.dating_gen_person) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_generation_skip(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_generate_partition(text, text, text, date, timestamptz, text, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.run_dating_generation_tick(timestamptz, text) FROM PUBLIC, anon, authenticated, service_role;
```

Create `$D/edit_tests_T2.py` with exactly:

```python
# Spec 2 W5a Task 2: the canary takes generation's functions (no API
# role's, the service role included: the tick decrypts, §4.2, S-4) and its
# S-4 scan follows calls: no function the service role can run reaches
# dating_field_decrypt through another, except the export builder (W9) and
# the kill switch's publisher, which returns a count (PF-F13). The grants
# twin re-asserts generation's revokes.
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anchor import edit

edit('supabase/tests/dating_rls_canary.sql', [
  ("""UPDATE allowed_fn SET service = '' WHERE sig IN ('dating_pair_passes_hard_filters(uuid,uuid)', 'get_my_dating_introductions(integer)');
""",
   """UPDATE allowed_fn SET service = '' WHERE sig IN ('dating_pair_passes_hard_filters(uuid,uuid)', 'get_my_dating_introductions(integer)');
-- W5a Task 2: generation is cron's (postgres), no API role's.
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('run_dating_generation_tick(timestamp with time zone,text)', '', ''),
  ('private.dating_open_chats(uuid,timestamp with time zone)', '', ''),
  ('private.dating_capacity(uuid,timestamp with time zone,jsonb)', '', ''),
  ('private.dating_reasons(private.dating_gen_person,private.dating_gen_person)', '', ''),
  ('private.dating_generation_skip(text)', '', ''),
  ('private.dating_generate_partition(text,text,text,date,timestamp with time zone,text,jsonb)', '', '');
"""),
  ("""-- S-4: the only function the service role can execute that decrypts
-- Dating fields is dating_export_for_job (W9); no column stores routing.
-- (PF-F13) publish_country_config, the service role's, decrypts transitively
-- through apply_same_gender_switch and returns no plaintext (a count); this
-- scan reads function text only, so W5 revisits it when generation decrypts.
DO $$
DECLARE
  v_bad text;
BEGIN
  SELECT string_agg(p.oid::regprocedure::text, ', ') INTO v_bad
    FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'private')
     AND p.prosrc LIKE '%dating_field_decrypt%'
     AND p.proname IS DISTINCT FROM 'dating_field_decrypt'
     AND has_function_privilege('service_role', p.oid, 'EXECUTE')
     AND p.proname IS DISTINCT FROM 'dating_export_for_job';""",
   """-- S-4: the only function the service role can execute that decrypts
-- Dating fields is dating_export_for_job (W9); no column stores routing.
-- (PF-F13) publish_country_config, the service role's, decrypts transitively
-- through apply_same_gender_switch and returns no plaintext (a count).
-- Spec 2 W5a: the scan follows calls (generation decrypts through
-- dating_person): every function whose body names a decrypting one decrypts.
DO $$
DECLARE
  v_bad text;
BEGIN
  WITH RECURSIVE dec(oid, name) AS (
    SELECT p.oid, p.proname::text FROM pg_proc AS p WHERE p.proname = 'dating_field_decrypt'
    UNION
    SELECT p.oid, p.proname::text
      FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace, dec
     WHERE n.nspname IN ('public', 'private') AND p.prosrc ~ ('\\m' || dec.name || '\\M'))
  SELECT string_agg(d.oid::regprocedure::text, ', ') INTO v_bad
    FROM dec AS d
   WHERE d.name NOT IN ('dating_field_decrypt', 'dating_export_for_job', 'publish_country_config')
     AND has_function_privilege('service_role', d.oid, 'EXECUTE');"""),
], 'canary: generation rows; S-4 follows calls')

edit('supabase/migrations/20261119100010_dating_v2_matching_grants.sql', [
  ("""GRANT EXECUTE ON FUNCTION public.get_my_dating_introductions(integer) TO authenticated;
COMMIT;""",
   """GRANT EXECUTE ON FUNCTION public.get_my_dating_introductions(integer) TO authenticated;
REVOKE ALL ON FUNCTION private.dating_open_chats(uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_capacity(uuid, timestamptz, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_reasons(private.dating_gen_person, private.dating_gen_person) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_generation_skip(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_generate_partition(text, text, text, date, timestamptz, text, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.run_dating_generation_tick(timestamptz, text) FROM PUBLIC, anon, authenticated, service_role;
COMMIT;"""),
], 'grants twin: generation')
```

- [ ] **Step 3: Build, apply, run**

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5
python3 -I $D/build_mig_T1.py
python3 -I $D/edit_tests_T2.py
for f in supabase/migrations/20261119100000_dating_v2_matching.sql supabase/migrations/20261119100010_dating_v2_matching_grants.sql; do
  for run in 1 2; do psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $f > /dev/null 2> $D/apply_err.txt; rc=$?; echo "$(basename $f) run $run exit=$rc"; grep -v NOTICE $D/apply_err.txt || true; done
done
python3 -I $D/marked_diff.py $D/before_w5a attune_spec3a 'Spec 2 W5a' | grep -c OK
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_matching_contracts.sql 2>&1 | grep -v 'does not exist, skipping' | tail -1
psql -X -d attune_spec3a -Atc "select schedule || ' ' || command from cron.job where jobname = 'dating-candidate-generation'"
$D/suite.sh attune_spec3a > $D/sql-after-T2.txt; echo "$(grep -c '^PASS' $D/sql-after-T2.txt) PASS, $(grep -c '^FAIL' $D/sql-after-T2.txt) FAIL"
diff <(grep FAIL $D/sql-baseline.txt) <(grep FAIL $D/sql-after-T2.txt) && echo same-fails
```

Expected: `… 9 functions re-created + the generation section`; `dating_rls_canary.sql: 2 edit(s) …` and `…_grants.sql: 1 edit(s) …`; four `exit=0`; `9`; `NOTICE:  dating_v2_matching_contracts: all held`; `17 * * * * SELECT public.run_dating_generation_tick()`; `160 PASS, 14 FAIL`; `same-fails`.

- [ ] **Step 4: The mutants (§7.5 6; the rules)**

Create `$D/mut_T2.py` with exactly:

```python
# Spec 2 W5a Task 2 mutants (mutate.py): each must make
# dating_v2_matching_contracts.sql fail with a CONTRACT VIOLATED line.
M = '-- Spec 2 W5a'
MUTS = {
  # Mutant 6 (§7.5): the decrypted people outlive the transaction.
  'm6_no_commit_drop': ("      capacity integer NOT NULL\n    ) ON COMMIT DROP;", "      capacity integer NOT NULL\n    );"),
  'cap_daily_ignored': ("      (p_cfg ->> 'daily_new_max')::int\n        - (SELECT count(*)::int", "      99\n        - (SELECT count(*)::int"),
  'cap_waiting_ignored': ("      (p_cfg ->> 'waiting_max')::int\n        - (SELECT count(*)::int", "      99\n        - (SELECT count(*)::int"),
  'cap_open_chats_ignored': ("    WHEN private.dating_open_chats(p_user, p_at) >= coalesce((p_cfg ->> 'open_chat_pause_at')::int, 3) THEN 0",
                             "    WHEN false THEN 0"),
  'band_ignored': ("         WHERE b.base >= b.best - v_band\n", "         WHERE true\n"),
  'jitter_unseeded': ("((('x' || substr(md5(v_seed || v_u.user_id::text || a.user_id::text), 1, 6))",
                      "((('x' || substr(md5(random()::text || v_u.user_id::text || a.user_id::text), 1, 6))"),
  'second_run_reclaims': ("    WHERE r.state IN ('pending', 'failed') AND r.attempts < v_max",
                          "    WHERE r.state IN ('pending', 'failed', 'completed') AND r.attempts < v_max"),
  'never_dead_letters': ("       SET state = CASE WHEN attempts >= v_max THEN 'dead_letter' ELSE 'failed' END,",
                         "       SET state = 'failed',"),
  'lifetime_one_side': (f"         OR (low_action IS NULL AND visible_from_low + v_life <= now()) {M}: or a side's own, unanswered\n", ""),
  'empty_day_uncounted': ("    PERFORM private.bump_metric_internal('dating.empty_day.' ||", "    PERFORM lower('dating.empty_day.' ||"),
  'flag_ignored': ("  IF public.dating_flag_enabled('dating_candidate_generation') IS NOT TRUE THEN", "  IF false THEN"),
  'hour_ignored': ("       AND c.generation_hour_utc = extract(hour FROM p_now AT TIME ZONE 'UTC')\n", ""),
  'unreadable_stops_run': ("        IF SQLERRM IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN\n          PERFORM private.bump_metric_internal('dating.generation.unreadable');",
                           "        IF false THEN\n          PERFORM private.bump_metric_internal('dating.generation.unreadable');"),
  'kept_pair_generated': ("           WHERE private.dating_pair_safe(v_u.user_id, a.user_id, (v_u.p).hmac, (a.p).hmac)\n             AND private.dating_pair_new(v_u.user_id, a.user_id)",
                          "           WHERE private.dating_pair_new(v_u.user_id, a.user_id)"),
  'abroad_not_loaded': ("               WHERE p_country = ANY (d.open_abroad::text[]) AND p.country_code::text IS DISTINCT FROM p_country",
                        "               WHERE false"),
}
```

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5
python3 -I $D/mutate.py supabase/migrations/20261119100000_dating_v2_matching.sql supabase/tests/dating_v2_matching_contracts.sql $D/mut_T2.py $D/mut supabase/migrations/20261119100010_dating_v2_matching_grants.sql > $D/mut_T2.txt 2>&1
python3 -I $D/mutate.py supabase/migrations/20261119100000_dating_v2_matching.sql supabase/tests/dating_v2_matching_contracts.sql $D/mut_T1.py $D/mut supabase/migrations/20261119100010_dating_v2_matching_grants.sql > $D/mut_T1_after_T2.txt 2>&1
grep -c 'CONTRACT VIOLATED' $D/mut_T2.txt $D/mut_T1_after_T2.txt; cat $D/mut_T2.txt $D/mut_T1_after_T2.txt | grep -v 'CONTRACT VIOLATED'
```

Expected: `…/mut_T2.txt:15` and `…/mut_T1_after_T2.txt:23`, nothing else printed. Among them: `m6_no_commit_drop: … a temp table of decrypted answers can outlive its transaction (mutant 6): private.dating_generate_partition(…)`, `band_ignored: … the run answered {"runs": [{… "created": 4, "partition": "GH"}]} (expected GH with 3 introductions)`, `jitter_unseeded: … the same seed made different introductions`, `second_run_reclaims: … a second run of the cohort answered … and created 1`, `kept_pair_generated: … (expected GH with 3 introductions)`.

- [ ] **Step 5: Record the tree**

Do not commit; record the tree in the report.

### Task 3: The race for two ticks, the dev script, and the W5a gate (§5.5, §7.6 1.6/6.3, §4.9 dev switch-on, §8 W5a)

**Files:**
- Create: `$D/edit_races_T3.py`
- Modify: `scripts/concurrency/dating_kill_switch_races.sh`

**Interfaces:**
- Consumes: Task 2's tick; Task 1's dev-script edit.
- Produces: the race case `two generation ticks claim one run (and no temp table survives)`; `dating_generation_runs` among the race script's delay triggers.

- [ ] **Step 1: The race case**

Create `$D/edit_races_T3.py` with exactly:

```python
# Spec 2 W5a Task 3: the race script's W5a case. Two generation ticks for
# the same cohort at once claim one run: the first holds its claimed run
# row (it sleeps before marking it completed), the second waits on it and
# then finds it taken (partition_unavailable); one run row, one attempt,
# no error, no deadlock. The first session also proves mutant 6 for real:
# after its tick commits (autocommit), the temp table of decrypted people
# is gone from that same session.
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anchor import edit

edit('scripts/concurrency/dating_kill_switch_races.sh', [
  ("""                           'dating_trusted_devices'] LOOP -- Spec 2 W4b (Task 5)""",
   """                           'dating_trusted_devices', -- Spec 2 W4b (Task 5)
                           'dating_generation_runs'] LOOP -- Spec 2 W5a (Task 3)"""),
  ("""$P -c "SELECT race.reset();" > /dev/null 2>&1
exit $fail""",
   """# Spec 2 W5a (Task 3, §5.5, §5.7, §7.6 1.6/6.3; mutant 6): two ticks for
# Ghana's cohort at once. A claims the run and sleeps before marking it
# completed (holding the claimed row); B's claim waits on it, then finds
# the run taken. One run row, one attempt; A's session has no temp table
# left once its tick has committed.
GEN_AT="(date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + interval '3 hours 17 minutes')"
FX_GEN="SELECT race.reset(); ALTER SEQUENCE race.s1 RESTART;
DELETE FROM race.outcome WHERE name LIKE 'tick_%';
DELETE FROM public.dating_generation_runs WHERE partition_key = 'GH';
UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_candidate_generation';
UPDATE public.dating_algorithm_configs SET state = 'retired', retired_at = now() WHERE state = 'active' AND version <> 'introductions_v2';
UPDATE public.dating_algorithm_configs SET state = 'active', activated_at = now(), product_review_ref = 'DEV-race',
       clinical_review_ref = 'DEV-race', fairness_review_ref = 'DEV-race', safety_review_ref = 'DEV-race'
 WHERE version = 'introductions_v2' AND state <> 'active';"
run "two generation ticks claim one run (and no temp table survives)" "$FX_GEN" \\
  "SET race.sleep_dating_generation_runs_update = '2:race.s1';
   INSERT INTO race.outcome VALUES ('tick_a', (SELECT public.run_dating_generation_tick($GEN_AT, 'GH')::text));
   INSERT INTO race.outcome VALUES ('tick_a_temp', coalesce(to_regclass('pg_temp.dating_gen_people')::text, 'gone'));" \\
  "SELECT pg_sleep(0.5);
   INSERT INTO race.outcome VALUES ('tick_b', (SELECT public.run_dating_generation_tick($GEN_AT, 'GH')::text));" \\
  "SELECT CASE WHEN NOT (SELECT is_called FROM race.s1) THEN 'the first tick never reached its run row (no race)'
               WHEN (SELECT count(*) FROM public.dating_generation_runs WHERE partition_key = 'GH') <> 1
                 OR (SELECT attempts FROM public.dating_generation_runs WHERE partition_key = 'GH') <> 1
                 OR (SELECT state FROM public.dating_generation_runs WHERE partition_key = 'GH') <> 'completed'
               THEN 'runs: ' || (SELECT string_agg(state || '/' || attempts, ', ') FROM public.dating_generation_runs WHERE partition_key = 'GH')
               WHEN (SELECT result FROM race.outcome WHERE name = 'tick_b') NOT LIKE '%partition_unavailable%'
               THEN 'the second tick answered ' || (SELECT result FROM race.outcome WHERE name = 'tick_b')
               WHEN (SELECT result FROM race.outcome WHERE name = 'tick_a_temp') <> 'gone'
               THEN 'the decrypted people outlived the tick (mutant 6)'
               ELSE 'ok' END;" serialised

$P -c "SELECT race.reset();" > /dev/null 2>&1
exit $fail"""),
], 'races: two generation ticks')
```

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5
python3 -I $D/edit_races_T3.py
dropdb --if-exists w5race 2>/dev/null; createdb w5race
pg_dump -s attune_spec3a | psql -X -q -d w5race > /dev/null 2>&1
pg_dump -a -t public.metric_key_prefixes -t public.feature_flags -t public.country_safety_config -t private.dating_calling_codes -t public.dating_algorithm_configs attune_spec3a | psql -X -q -d w5race > /dev/null 2>&1
bash scripts/concurrency/dating_kill_switch_races.sh w5race > $D/race_T3.txt 2>&1; grep -c '^PASS' $D/race_T3.txt; grep -v '^PASS' $D/race_T3.txt
dropdb w5race
```

Expected: `scripts/concurrency/dating_kill_switch_races.sh: 2 edit(s) (races: two generation ticks)`; `30`; nothing else; the last PASS line `PASS  two generation ticks claim one run (and no temp table survives) (deadlocks detected and retried: 0)`. Run it on an idle machine (a timing case can flake under load: re-run once before reporting it).

- [ ] **Step 2: The dev script turns everything on in development**

```bash
psql -X -q -At -v ON_ERROR_STOP=1 -d attune_spec3a -c 'BEGIN' -f supabase/sql/dev_enable_spec2_dating_flags.sql \
  -c "SELECT 'active=' || version || ':' || product_review_ref FROM public.dating_algorithm_configs WHERE state = 'active'" \
  -c "SELECT 'flags_on=' || count(*) FROM public.feature_flags WHERE key LIKE 'dating%' AND enabled" -c 'ROLLBACK' 2>&1 | grep -E 'active=|flags_on='
```

Expected: `active=introductions_v2:DEV-product` and `flags_on=6`.

- [ ] **Step 3: The W5a gate**

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5
$D/suite.sh attune_spec3a > $D/sql-W5a.txt; echo "$(grep -c '^PASS' $D/sql-W5a.txt) PASS, $(grep -c '^FAIL' $D/sql-W5a.txt) FAIL"
flutter analyze --no-pub lib test > $D/analyze-W5a.txt 2>&1; tail -1 $D/analyze-W5a.txt
flutter test --reporter compact > $D/flutter-W5a.txt 2>&1; tr '\r' '\n' < $D/flutter-W5a.txt | grep -E '^[0-9:]+ \+[0-9]+' | tail -1
shasum -c .superpowers/sdd/2026-11-04-spec1-w10-accessibility-docs/w10-1.0.sha | grep -vc ': OK$'; shasum -c .superpowers/sdd/2026-11-04-spec1-w9/flag_off.sha | grep -vc ': OK$'
shasum -c .superpowers/sdd/2026-11-07-spec2-w3/latch.sha; flutter test --no-pub test/architecture/games_untouched_test.dart 2>&1 | tr '\r' '\n' | tail -1
(cd supabase/functions && deno test --allow-read --allow-env --lock=../../.github/deno-w9.lock --frozen _shared/unicode_normaliser.test.ts _shared/writer_crisis_check.test.ts _shared/healing_ai_gate.test.ts process-dating-photo/handler.test.ts process-dating-photo/worker.test.ts _shared/google_vision.test.ts analyse-journal-entry/ generate-healing-portrait/ generate-healing-post-mortem/ process-scheduled-notifications/privacy_allowlist.test.ts dating-verification/handler.test.ts _shared/age_assurance/providers.test.ts 2>&1 | grep -E 'passed|failed' | tail -1)
```

Expected: `160 PASS, 14 FAIL`; `571 issues found. (ran in …)`; `+8191` (W5a adds no Dart test) and only the known flakes; `0`; `0`; `lib/home/home_screen.dart: OK`; `All tests passed!`; `ok | 193 passed | 0 failed`. The race script: Step 1's 30. The mutants: Tasks 1–2.

- [ ] **Step 4: Record the tree**

Do not commit; record the tree in the report.


## Batch W5b — Today, the card, the match moment, the digest

### Task 4: Migration `dating_v2_today`: the card, Today, act v2, the moment, the notes, the photo keys, the digest; simultaneous interest (§4.9 W5b, §3.4, §3.5, §3.13, §4.4, §4.7, §5.8, §7.1, §7.5 mutants 18, 19, §7.6; Fable C1, M3, M4, M8; carries 4, 7, 8, 12–14; R-1, R-10, R-13, R-20, R-23, R-24, R-31)

**Files:**
- Create: `supabase/migrations/20261119110000_dating_v2_today.sql`, `supabase/migrations/20261119110010_dating_v2_today_grants.sql`, `$D/{before_w5b/, mig_T4_head.sql, mig_T4_tail.sql, build_mig_T4.py, contract_T4_K.sql, contract_T4.sql, splice_T4.py, edit_tests_T4.py, edit_races_T4.py, mut_T4.py}`
- Modify: `supabase/tests/dating_v2_matching_contracts.sql` (K replaced, L–P added), `supabase/tests/dating_mode_contracts.sql`, `supabase/tests/dating_rls_canary.sql`, `supabase/tests/dating_v2_setup_contracts.sql` (G3), `scripts/concurrency/dating_kill_switch_races.sh`, `scripts/local_pg_grants.sql`

**Interfaces:**
- Consumes: Task 1's person and pair functions, `private.dating_intro_config()`, `private.dating_open_chats`, `private.dating_cool_off_ends_at`; W3a's `private.dating_queue_me_update(uuid, 'digest', 'new')`; W4b's `private.dating_device_state`.
- Produces: the W5b SQL interfaces under "Interfaces this plan produces". The card's keys are exactly `id, display_name, age, region_name_key, side_name_key, intention, marriage_timeline, children_have, children_want, gender, pronouns, faith, marital, prompts, reasons, photos_after_mutual, photos[{id, position, caption}], acted` (the viewer's own action only); Today's `today_state` is one of `cool_off | delivered | before_drop | paused_open_chats | queue_full | empty`.

- [ ] **Step 1: Save the live body the migration re-creates**

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5; mkdir -p $D/before_w5b
psql -X -d attune_spec3a -Atc "select pg_get_functiondef('public.invalidate_dating_on_profile_change()'::regprocedure)" > "$D/before_w5b/public.invalidate_dating_on_profile_change().sql"
ls $D/before_w5b | wc -l
```

Expected: `1`.

- [ ] **Step 2: Write the failing sections**

Create `$D/contract_T4_K.sql` with exactly (section K in its W5b form; it replaces Task 1's):

```sql
-- =====================================================================
-- K. (§3.4, §4.10; carries 4, 8; R-17) Spec 2 W5b: the v2 read and act.
--    The caller's own trusted phone first, so another phone reads nothing
--    and changes nobody's introduction; nothing before this side's drop
--    (the day says when); a kept never-introduce entry ends the pair and
--    the answer is the one any unavailable introduction gets; mutual
--    interest makes one match and queues no push; a replay answers as the
--    first did and there is no rewind; a pass takes the card away.
-- =====================================================================
DO $$
DECLARE
  w constant uuid := pg_temp.ready('41');
  m constant uuid := pg_temp.ready('42', '{"identity": "man", "seeking": ["woman"]}');
  k constant uuid := pg_temp.ready('43', '{"identity": "man", "seeking": ["woman"]}');
  v_wm uuid;
  v_wk uuid;
  v jsonb;
  v_pushes bigint := (SELECT count(*) FROM public.scheduled_notifications);
BEGIN
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high, reasons)
  VALUES (public.dating_pair_key(w, m), least(w, m), greatest(w, m), 'generated', 'introductions_v2', now() - interval '1 hour', now() - interval '1 hour', ARRAY['same_intention'])
  RETURNING id INTO v_wm;
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high)
  VALUES (public.dating_pair_key(w, k), least(w, k), greatest(w, k), 'generated', 'introductions_v2', now() + interval '1 hour', now() + interval '1 hour')
  RETURNING id INTO v_wk;
  v := pg_temp.call(w, pg_temp.dev('41'), 'SELECT public.get_my_dating_today()')::jsonb;
  IF v ->> 'today_state' IS DISTINCT FROM 'delivered' OR jsonb_array_length(v -> 'cards') <> 1
     OR v #>> '{cards,0,id}' IS DISTINCT FROM v_wm::text OR jsonb_array_length(v -> 'waiting') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the person''s own phone reads today as %', v;
  END IF;
  -- Carry 8: another phone (or none) reads nothing.
  IF pg_temp.call(w, pg_temp.dev('99'), 'SELECT public.get_my_dating_today()') IS DISTINCT FROM '{"ok": false, "reason": "reverify_device"}'
     OR pg_temp.call(w, NULL, 'SELECT public.get_my_dating_introductions()') IS DISTINCT FROM '{"ok": false, "reason": "reverify_device"}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another phone read the introductions (carry 8)';
  END IF;
  -- R-17: acting from another phone is refused before anything changes.
  v := pg_temp.call(w, pg_temp.dev('99'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('k-stranger'), v_wm))::jsonb;
  IF v IS DISTINCT FROM '{"ok": false, "reason": "reverify_device"}' OR (SELECT state FROM public.dating_introductions WHERE id = v_wm) <> 'generated' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another phone''s act answered % and left the introduction %', v,
      (SELECT state FROM public.dating_introductions WHERE id = v_wm);
  END IF;
  -- Not before this side's drop: the day says when.
  UPDATE public.dating_introductions SET visible_from_low = now() - interval '1 hour', visible_from_high = now() - interval '1 hour' WHERE id = v_wm;
  IF pg_temp.probe(ARRAY[format('UPDATE public.dating_introductions SET state = ''passed'', low_action = ''passed'', high_action = ''passed'' WHERE id = %L', v_wm)],
                   format('SELECT pg_temp.call(%L, %L, ''SELECT public.get_my_dating_today()'')::jsonb ->> ''today_state''', w, pg_temp.dev('41')))
       IS DISTINCT FROM 'before_drop'
     OR pg_temp.call(w, pg_temp.dev('41'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('k-early'), v_wk))
        IS DISTINCT FROM '{"ok": false, "reason": "introduction_unavailable"}'
     -- H2: one that doesn't exist answers the same.
     OR pg_temp.call(w, pg_temp.dev('41'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('k-absent'), '5e5e0000-0000-4000-8000-0000000000fe'))
        IS DISTINCT FROM '{"ok": false, "reason": "introduction_unavailable"}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an introduction was answered before this side''s drop, or the day did not say it is coming';
  END IF;
  -- Carry 4: a kept never-introduce entry ends the pair at the act, with
  -- the one answer any unavailable introduction gets.
  UPDATE public.dating_introductions SET visible_from_high = now() - interval '1 hour', visible_from_low = now() - interval '1 hour' WHERE id = v_wk;
  INSERT INTO public.dating_never_introduce (owner_user_id, phone_hmac, last_two, kept_at)
  VALUES (k, public.dating_phone_hmac_for_user(w), '41', now());
  v := pg_temp.call(w, pg_temp.dev('41'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('k-kept'), v_wk))::jsonb;
  IF v IS DISTINCT FROM '{"ok": false, "reason": "introduction_unavailable"}' OR (SELECT state FROM public.dating_introductions WHERE id = v_wk) <> 'invalidated'
     OR jsonb_array_length(pg_temp.call(w, pg_temp.dev('41'), 'SELECT public.get_my_dating_introductions()')::jsonb -> 'cards') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a kept never-introduce entry did not end the pair (%; %)', v, (SELECT state FROM public.dating_introductions WHERE id = v_wk);
  END IF;
  -- Mutual interest: one match, no push (§3.13); a replay, no rewind.
  v := pg_temp.call(w, pg_temp.dev('41'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('k-w'), v_wm))::jsonb;
  IF v IS DISTINCT FROM '{"ok": true, "action": "interested", "matched": false}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the first interest answered %', v;
  END IF;
  v := pg_temp.call(m, pg_temp.dev('42'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('k-m'), v_wm))::jsonb;
  IF v IS DISTINCT FROM '{"ok": true, "action": "interested", "matched": true}'
     OR (SELECT count(*) FROM public.dating_matches WHERE introduction_id = v_wm AND state = 'active') <> 1
     OR (SELECT count(*) FROM public.scheduled_notifications) <> v_pushes THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: mutual interest answered %, made % match(es), queued % push(es)', v,
      (SELECT count(*) FROM public.dating_matches WHERE introduction_id = v_wm),
      (SELECT count(*) FROM public.scheduled_notifications) - v_pushes;
  END IF;
  IF pg_temp.call(m, pg_temp.dev('42'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('k-m'), v_wm))
       IS DISTINCT FROM '{"action": "interested", "matched": true, "ok": true}'::jsonb::text
     OR pg_temp.call(w, pg_temp.dev('41'), format('SELECT public.act_on_dating_introduction(%L, %L, ''passed'')', md5('k-w-again'), v_wm))::jsonb
        ->> 'reason' IS DISTINCT FROM 'introduction_unavailable'
     OR (SELECT state || low_action || high_action FROM public.dating_introductions WHERE id = v_wm) <> 'matchedinterestedinterested' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replay answered differently, or a second answer rewound the first';
  END IF;
  -- No rewind on a card still open either: interested, then "Not for me".
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high)
  VALUES (public.dating_pair_key(m, k), least(m, k), greatest(m, k), 'generated', 'introductions_v2', now() - interval '1 hour', now() - interval '1 hour')
  RETURNING id INTO v_wk;
  PERFORM pg_temp.call(m, pg_temp.dev('42'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('k-m-k'), v_wk));
  v := pg_temp.call(m, pg_temp.dev('42'), format('SELECT public.act_on_dating_introduction(%L, %L, ''passed'')', md5('k-m-k2'), v_wk))::jsonb;
  IF v IS DISTINCT FROM '{"ok": true, "action": "interested", "matched": false}' OR (SELECT state FROM public.dating_introductions WHERE id = v_wk) <> 'interested' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: "Not for me" after "Interested" rewound it (%)', v;
  END IF;
END $$;
```

Create `$D/contract_T4.sql` with exactly (sections L–P):

```sql
-- =====================================================================
-- L. (§3.4, §5.8; mutants 18, 19) The card: exactly the allowed keys; who
--    the person would like to meet, their pools, faith importance and any
--    field they hide never; no storage path; captions as photo labels; no
--    photo while the person keeps them for mutual interest. Reasons: faith
--    only when both show it, the timeline only when both show it, at most
--    three in order, across borders when nothing else.
-- =====================================================================
DO $$
DECLARE
  w constant uuid := pg_temp.ready('81', '{"faith": "christian", "importance": "must_share", "faith_visible": false, "family": "early"}');
  m constant uuid := pg_temp.ready('82', '{"identity": "man", "seeking": ["woman"], "faith": "christian", "importance": "must_share", "faith_visible": true}');
  v_id uuid;
  v jsonb;
  v_card jsonb;
  v_bad text;
  v_cfg constant jsonb := (private.dating_intro_config()).o_config;
BEGIN
  UPDATE public.dating_profile_photos SET caption = 'Me at the beach' WHERE user_id = m AND position = 1;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state, csam_state)
  VALUES (m, 'w5/review.jpg', 3, 'needs_review', 'clear');
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high, reasons)
  VALUES (public.dating_pair_key(w, m), least(w, m), greatest(w, m), 'generated', 'introductions_v2', now() - interval '1 hour', now() - interval '1 hour',
          ARRAY['same_intention', 'children_want_yes', 'same_region'])
  RETURNING id INTO v_id;
  v_card := pg_temp.call(w, pg_temp.dev('81'), 'SELECT public.get_my_dating_introductions()')::jsonb #> '{cards,0}';
  SELECT string_agg(k, ', ' ORDER BY k) INTO v_bad FROM jsonb_object_keys(v_card) AS k
   WHERE k NOT IN ('id', 'display_name', 'age', 'region_name_key', 'side_name_key', 'intention', 'marriage_timeline', 'children_have',
                   'children_want', 'gender', 'pronouns', 'faith', 'marital', 'prompts', 'reasons', 'photos_after_mutual', 'photos', 'acted');
  IF v_bad IS NOT NULL OR v_card::text ~* ('(seeking|pools|importance|must_share|storage|w5/|pair_key|user_id|' || w::text || '|' || m::text || ')') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the card carries % or a hidden value (mutant 18): %', v_bad, v_card;
  END IF;
  IF v_card #>> '{faith,faith}' IS DISTINCT FROM 'christian' OR v_card -> 'gender' IS DISTINCT FROM 'null'::jsonb
     OR jsonb_array_length(v_card -> 'photos') <> 2 OR v_card #>> '{photos,0,caption}' IS DISTINCT FROM 'Me at the beach'
     OR v_card -> 'reasons' IS DISTINCT FROM '["same_intention", "children_want_yes", "same_region"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the card does not show what the person chose (faith shown, gender hidden, the two viewable photos, a caption): %', v_card;
  END IF;
  -- m sees w's card: w hides faith.
  v_card := pg_temp.call(m, pg_temp.dev('82'), 'SELECT public.get_my_dating_introductions()')::jsonb #> '{cards,0}';
  IF v_card -> 'faith' IS DISTINCT FROM 'null'::jsonb OR v_card::text ~* 'christian' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hidden faith reached the other person: %', v_card;
  END IF;
  -- A card from two days ago waits (no date on it); the day is empty.
  UPDATE public.dating_introductions SET visible_from_low = now() - interval '2 days', visible_from_high = now() - interval '2 days' WHERE id = v_id;
  v := pg_temp.call(w, pg_temp.dev('81'), 'SELECT public.get_my_dating_today()')::jsonb;
  IF v ->> 'today_state' IS DISTINCT FROM 'empty' OR jsonb_array_length(v -> 'cards') <> 0 OR jsonb_array_length(v -> 'waiting') <> 1
     OR v::text ~ 'visible_from|expires|created' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an older card is not "still waiting", or a date was sent: %', v;
  END IF;
  UPDATE public.dating_profiles SET photos_after_mutual = true WHERE user_id = m;
  v_card := pg_temp.call(w, pg_temp.dev('81'), 'SELECT public.get_my_dating_introductions()')::jsonb #> '{cards,0}';
  IF v_card -> 'photos' IS DISTINCT FROM '[]'::jsonb OR v_card -> 'photos_after_mutual' IS DISTINCT FROM 'true'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: photos kept for mutual interest were listed: %', v_card;
  END IF;
  -- Mutant 19: faith reasons only when both show it.
  IF 'same_faith' = ANY (private.dating_reasons(pg_temp.pr(1, '{"faith": "christian", "faith_visible": false}'), pg_temp.man(2, '{"faith": "christian", "faith_visible": true}')))
     OR 'faith_matters' = ANY (private.dating_reasons(pg_temp.pr(1, '{"faith": "christian", "importance": "must_share", "faith_visible": false}'),
                                                      pg_temp.man(2, '{"faith": "christian", "importance": "must_share", "faith_visible": true}')))
     OR NOT 'same_faith' = ANY (private.dating_reasons(pg_temp.pr(1, '{"faith": "christian", "faith_visible": true, "children_want": "open"}'),
                                                       pg_temp.man(2, '{"faith": "christian", "faith_visible": true, "children_want": "open"}'))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a faith reason was cited while one side hides faith, or not when both show it (mutant 19)';
  END IF;
  IF private.dating_reasons(pg_temp.pr(1, '{"intention": "marriage", "timeline": "few_years", "timeline_visible": false}'),
                            pg_temp.man(2, '{"intention": "marriage", "timeline": "few_years"}')) <> ARRAY['same_intention', 'children_want_yes', 'same_region']
     OR private.dating_reasons(pg_temp.pr(1, '{"intention": "marriage", "timeline": "few_years", "children_have": true, "family": "early"}'),
                               pg_temp.man(2, '{"intention": "marriage", "timeline": "few_years", "children_have": true, "family": "early"}'))
        <> ARRAY['same_intention_timeline', 'children_want_yes', 'children_have_both']
     OR private.dating_reasons(pg_temp.pr(1, '{"intention": "companionship", "children_want": "open"}'),
                               pg_temp.man(2, '{"intention": "not_sure", "children_want": "no", "country": "GB", "region": "TLI"}')) <> ARRAY['across_borders'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the reasons are not the first three that apply in §5.8''s order';
  END IF;
END $$;

-- =====================================================================
-- M. (Fable C1, §4.1, H2) Four accounts on the new reads: an outsider's
--    act, mark and photo keys on someone else's introduction or match
--    answer exactly as for one that doesn't exist; a blocked pair is
--    neither read nor answered.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('83');
  b constant uuid := pg_temp.ready('84', '{"identity": "man", "seeking": ["woman"]}');
  c constant uuid := pg_temp.ready('85', '{"identity": "man", "seeking": ["woman"]}');
  v_ab uuid;
  v_m uuid;
  v_cards jsonb;
  v_answer text;
  v_absent text;
  v_mark text;
  v_mark_absent text;
  v_fake constant uuid := '5e5e0000-0000-4000-8000-0000000000ff';
BEGIN
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high)
  VALUES (public.dating_pair_key(a, b), least(a, b), greatest(a, b), 'generated', 'introductions_v2', now() - interval '1 hour', now() - interval '1 hour')
  RETURNING id INTO v_ab;
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, b), greatest(a, b), 'active') RETURNING id INTO v_m;
  -- Each call its own statement: an IF's operands have no order.
  v_answer := pg_temp.call(c, pg_temp.dev('85'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('c-forged'), v_ab));
  v_absent := pg_temp.call(c, pg_temp.dev('85'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('c-absent'), v_fake));
  v_mark := pg_temp.call(c, pg_temp.dev('85'), format('SELECT public.mark_dating_match_moment_seen(%L)', v_m));
  v_mark_absent := pg_temp.call(c, pg_temp.dev('85'), format('SELECT public.mark_dating_match_moment_seen(%L)', v_fake));
  IF v_answer IS DISTINCT FROM v_absent OR v_mark IS DISTINCT FROM v_mark_absent
     OR public.dating_photo_keys_for_viewer(c, 'introduction', v_ab, encode(extensions.digest(pg_temp.dev('85'), 'sha256'), 'hex'))
       IS DISTINCT FROM public.dating_photo_keys_for_viewer(c, 'introduction', v_fake, encode(extensions.digest(pg_temp.dev('85'), 'sha256'), 'hex'))
     OR public.dating_photo_keys_for_viewer(c, 'match', v_m, encode(extensions.digest(pg_temp.dev('85'), 'sha256'), 'hex'))
       IS DISTINCT FROM public.dating_photo_keys_for_viewer(c, 'match', v_fake, encode(extensions.digest(pg_temp.dev('85'), 'sha256'), 'hex'))
     OR (SELECT low_moment_seen_at IS NOT NULL OR high_moment_seen_at IS NOT NULL FROM public.dating_matches WHERE id = v_m)
     OR EXISTS (SELECT 1 FROM public.dating_interest_actions WHERE actor_user_id = c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider can tell someone else''s introduction or match from none, or changed it (Fable C1)';
  END IF;
  INSERT INTO public.dating_blocks (blocker_user_id, blocked_user_id, pair_key) VALUES (b, a, public.dating_pair_key(a, b));
  -- Each call its own statement: an IF's operands have no order.
  v_cards := pg_temp.call(a, pg_temp.dev('83'), 'SELECT public.get_my_dating_introductions()')::jsonb;
  v_answer := pg_temp.call(a, pg_temp.dev('83'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('a-blocked'), v_ab));
  IF jsonb_array_length(v_cards -> 'cards') <> 0 OR v_answer IS DISTINCT FROM '{"ok": false, "reason": "introduction_unavailable"}'
     OR (SELECT state FROM public.dating_introductions WHERE id = v_ab) <> 'invalidated' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a blocked pair was read or answered';
  END IF;
END $$;

-- =====================================================================
-- N. (§3.4, §3.5, §5.6) The match moment, once per side; the family
--    question once, after the first introduction, and answering it ends
--    nothing; the quiet note after 14 days without one, once.
-- =====================================================================
DO $$
DECLARE
  w constant uuid := pg_temp.ready('86');
  m constant uuid := pg_temp.ready('87', '{"identity": "man", "seeking": ["woman"]}');
  q constant uuid := pg_temp.ready('88');
  v_id uuid;
  v_match uuid;
  v jsonb;
BEGIN
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high)
  VALUES (public.dating_pair_key(w, m), least(w, m), greatest(w, m), 'generated', 'introductions_v2', now() - interval '1 hour', now() - interval '1 hour')
  RETURNING id INTO v_id;
  v := pg_temp.call(w, pg_temp.dev('86'), 'SELECT public.get_my_dating_today()')::jsonb;
  IF (v ->> 'family_question')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the family question is not asked after the first introduction: %', v;
  END IF;
  PERFORM pg_temp.call(w, pg_temp.dev('86'), format('SELECT public.save_dating_family_involvement(%L, ''early'')', md5('fam-w')));
  v := pg_temp.call(w, pg_temp.dev('86'), 'SELECT public.get_my_dating_today()')::jsonb;
  IF (v ->> 'family_question')::boolean OR (SELECT state FROM public.dating_introductions WHERE id = v_id) <> 'generated' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: answering the family question asked it again or ended the introduction (%)', (SELECT state FROM public.dating_introductions WHERE id = v_id);
  END IF;
  PERFORM pg_temp.call(w, pg_temp.dev('86'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('n-w'), v_id));
  PERFORM pg_temp.call(m, pg_temp.dev('87'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('n-m'), v_id));
  SELECT id INTO v_match FROM public.dating_matches WHERE introduction_id = v_id;
  IF pg_temp.call(w, pg_temp.dev('86'), 'SELECT public.get_my_dating_today()')::jsonb -> 'moments'
       IS DISTINCT FROM jsonb_build_array(jsonb_build_object('match_id', v_match, 'display_name', 'Match 87')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the match moment is not offered';
  END IF;
  PERFORM pg_temp.call(w, pg_temp.dev('86'), format('SELECT public.mark_dating_match_moment_seen(%L)', v_match));
  IF jsonb_array_length(pg_temp.call(w, pg_temp.dev('86'), 'SELECT public.get_my_dating_today()')::jsonb -> 'moments') <> 0
     OR jsonb_array_length(pg_temp.call(m, pg_temp.dev('87'), 'SELECT public.get_my_dating_today()')::jsonb -> 'moments') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the moment is not once per side';
  END IF;
  UPDATE public.dating_enrollments SET activated_at = now() - interval '20 days' WHERE user_id = q;
  v := pg_temp.call(q, pg_temp.dev('88'), 'SELECT public.get_my_dating_today()')::jsonb;
  IF (v ->> 'quiet_note')::boolean IS NOT TRUE
     OR pg_temp.call(q, pg_temp.dev('88'), 'SELECT public.dismiss_dating_today_note(''quiet'')') IS DISTINCT FROM '{"ok": true}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the quiet note is not shown after 14 quiet days: %', v;
  END IF;
  v := pg_temp.call(q, pg_temp.dev('88'), 'SELECT public.get_my_dating_today()')::jsonb;
  IF (v ->> 'quiet_note')::boolean
     OR pg_temp.call(q, pg_temp.dev('88'), 'SELECT public.dismiss_dating_today_note(''loud'')') IS DISTINCT FROM '{"ok": false, "reason": "invalid"}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the quiet note is shown again, or an unknown note was taken';
  END IF;
END $$;

-- =====================================================================
-- O. (§4.4, §4.7; carries 12-14) Photo keys for dating-photo-urls: the
--    viewer's phone first; only viewable photos (approved and cleared:
--    never pending, a hit or rejected); never while the other person keeps
--    photos for mutual interest, but theirs once matched; never without
--    the photo flag.
-- =====================================================================
DO $$
DECLARE
  w constant uuid := pg_temp.ready('91');
  m constant uuid := pg_temp.ready('92', '{"identity": "man", "seeking": ["woman"]}');
  v_hash constant text := encode(extensions.digest(pg_temp.dev('91'), 'sha256'), 'hex');
  v_id uuid;
  v_match uuid;
  v jsonb;
BEGIN
  INSERT INTO public.feature_flags (key, enabled) VALUES ('dating_profile_photos', true) ON CONFLICT (key) DO UPDATE SET enabled = true;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state, csam_state)
  VALUES (m, 'w5/hit.jpg', 3, 'rejected', 'hit'), (m, 'w5/pending.jpg', 4, 'pending', 'clear'), (m, 'w5/error.jpg', 5, 'needs_review', 'error');
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high)
  VALUES (public.dating_pair_key(w, m), least(w, m), greatest(w, m), 'generated', 'introductions_v2', now() - interval '1 hour', now() - interval '1 hour')
  RETURNING id INTO v_id;
  v := public.dating_photo_keys_for_viewer(w, 'introduction', v_id, v_hash);
  IF v IS DISTINCT FROM jsonb_build_object('ok', true, 'photos', jsonb_build_array(
         jsonb_build_object('position', 1, 'key', 'w5/' || m || '/1.jpg'), jsonb_build_object('position', 2, 'key', 'w5/' || m || '/2.jpg'))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the photo keys are not exactly the viewable photos: %', v;
  END IF;
  IF public.dating_photo_keys_for_viewer(w, 'introduction', v_id, encode(extensions.digest(pg_temp.dev('99'), 'sha256'), 'hex'))
       IS DISTINCT FROM '{"ok": false, "reason": "reverify_device"}'
     OR public.dating_photo_keys_for_viewer(w, 'introduction', v_id, NULL) IS DISTINCT FROM '{"ok": false, "reason": "reverify_device"}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: photo keys were given to another phone (carry 12)';
  END IF;
  UPDATE public.dating_profiles SET photos_after_mutual = true WHERE user_id = m;
  IF public.dating_photo_keys_for_viewer(w, 'introduction', v_id, v_hash) IS DISTINCT FROM '{"ok": false, "reason": "photos_unavailable"}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: photos kept for mutual interest were keyed before it';
  END IF;
  INSERT INTO public.dating_matches (introduction_id, user_low_id, user_high_id, state) VALUES (v_id, least(w, m), greatest(w, m), 'active') RETURNING id INTO v_match;
  IF jsonb_array_length(public.dating_photo_keys_for_viewer(w, 'match', v_match, v_hash) -> 'photos') <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a match does not see the other''s viewable photos';
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_profile_photos';
  IF public.dating_photo_keys_for_viewer(w, 'match', v_match, v_hash) IS DISTINCT FROM '{"ok": false, "reason": "photos_unavailable"}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: photo keys were given with the photo flag off';
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_profile_photos';
END $$;

-- =====================================================================
-- P. (§3.13) The digest: at the person's drop, only when on, only with
--    something new; the neutral me_update (no "dating", no id); at most
--    one a day.
-- =====================================================================
DO $$
DECLARE
  u constant uuid := pg_temp.ready('93');
  x constant uuid := pg_temp.ready('94', '{"identity": "man", "seeking": ["woman"]}');
  v_off integer;
  v_tz text;
  v_slot time;
  v_local timestamp;
  v_sent integer;
  v_meta jsonb;
BEGIN
  -- A whole-hour zone where the last half-hour slot is between 07:00 and 22:00.
  FOR v_off IN -12..14 LOOP
    v_tz := 'Etc/GMT' || CASE WHEN v_off > 0 THEN '-' || v_off WHEN v_off < 0 THEN '+' || (-v_off) ELSE '' END;
    v_local := now() AT TIME ZONE v_tz;
    v_slot := (date_trunc('hour', v_local) + CASE WHEN extract(minute FROM v_local) >= 30 THEN interval '30 minutes' ELSE interval '0' END)::time;
    EXIT WHEN v_slot BETWEEN time '07:00' AND time '22:00';
  END LOOP;
  UPDATE public.users SET timezone = v_tz WHERE id = u;
  INSERT INTO public.dating_settings (user_id, drop_time, digest_push) VALUES (u, v_slot, true);
  -- x: digest on, but it is night where x is (no drop in the last hour).
  FOR v_off IN -12..14 LOOP
    v_tz := 'Etc/GMT' || CASE WHEN v_off > 0 THEN '-' || v_off WHEN v_off < 0 THEN '+' || (-v_off) ELSE '' END;
    EXIT WHEN extract(hour FROM now() AT TIME ZONE v_tz) BETWEEN 1 AND 5;
  END LOOP;
  UPDATE public.users SET timezone = v_tz WHERE id = x;
  INSERT INTO public.dating_settings (user_id, drop_time, digest_push) VALUES (x, '19:00', true);
  PERFORM set_config('app.settings.dating_push_key', 'spec2-w5-push-key', true);
  IF public.send_dating_digests() <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a digest was sent with nothing new';
  END IF;
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high)
  VALUES (public.dating_pair_key(u, x), least(u, x), greatest(u, x), 'generated', 'introductions_v2', now() - interval '1 minute', now() - interval '1 minute');
  -- No push key: nothing, counted, never a raise (the cron's).
  PERFORM set_config('app.settings.dating_push_key', '', true);
  BEGIN
    v_sent := public.send_dating_digests();
  EXCEPTION WHEN raise_exception THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the digest raised without its push key (%)', SQLERRM;
  END;
  IF v_sent <> 0 OR pg_temp.metric('dating.digest.push_key_missing') < 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the digest without its push key sent or was not counted';
  END IF;
  PERFORM set_config('app.settings.dating_push_key', 'spec2-w5-push-key', true);
  v_sent := public.send_dating_digests();
  SELECT metadata INTO v_meta FROM public.scheduled_notifications
   WHERE user_id = u AND source_key = private.dating_push_source_key(u, 'digest', (now() AT TIME ZONE 'UTC')::date);
  -- (the push queue's quiet-hours guard may mark it deferred: §3.13)
  IF v_sent <> 1 OR v_meta - 'quiet_deferred' IS DISTINCT FROM '{"type": "me_update", "route": "me", "title": "Attune", "body": "You have something new in Attune."}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the digest was not the one neutral push (% sent, %)', v_sent, v_meta;
  END IF;
  IF public.send_dating_digests() <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second digest the same day';
  END IF;
  UPDATE public.dating_settings SET digest_push = false, digest_sent_at = NULL WHERE user_id = u;
  DELETE FROM public.scheduled_notifications WHERE user_id = u;
  IF public.send_dating_digests() <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a digest the person turned off';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dating-digest' AND schedule = '5 * * * *' AND command = 'SELECT public.send_dating_digests()') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the digest cron is not scheduled';
  END IF;
END $$;
```

Create `$D/splice_T4.py` with exactly:

```python
# Spec 2 W5b Task 4: section K becomes the v2 read and act; sections L-P
# go in before the final notice.
import pathlib
D = pathlib.Path('.superpowers/sdd/2026-11-19-spec2-w5')
p = pathlib.Path('supabase/tests/dating_v2_matching_contracts.sql')
s = p.read_text()
sep = '-- =====================================================================\n'
k, j = sep + '-- K. (§4.10; carries 4, 8; R-17)', sep + '-- J. (carry 10)'
end = "DO $$ BEGIN RAISE NOTICE 'dating_v2_matching_contracts: all held'; END $$;"
for a in (k, j, end):
    assert s.count(a) == 1, a[-40:]
s = s[:s.index(k)] + (D / 'contract_T4_K.sql').read_text() + '\n' + s[s.index(j):]
s = s.replace(end, (D / 'contract_T4.sql').read_text() + end)
p.write_text(s)
print(f'{p}: K replaced, L-P in')
```

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5
python3 -I $D/splice_T4.py
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_matching_contracts.sql 2>&1 | grep -v 'skipping' | grep -m1 ERROR
```

Expected: `supabase/tests/dating_v2_matching_contracts.sql: K replaced, L-P in`; then `psql:supabase/tests/dating_v2_matching_contracts.sql:552: ERROR:  invalid input syntax for type json` (K's first read: `pg_temp.call` answers `42883:function public.get_my_dating_today() does not exist`, which is not JSON).

- [ ] **Step 3: Write the migration**

Create `$D/mig_T4_head.sql` with exactly (sections 1–8 and section 9's heading):

```sql
-- supabase/migrations/20261119110000_dating_v2_today.sql
-- Spec 2 W5b (§4.9 W5b, §3.4, §3.5, §3.13, §4.4, §4.7, §5.8; carries 8,
-- 12-14): Today. The card others see (one builder: the person's own
-- answers as they chose to show them, the reason ids, the viewable photos'
-- count and captions, never a storage path, who they'd like to meet or a
-- hidden field); get_my_dating_today() (the day state, today's cards and
-- the ones still waiting, the match moments, the family question and the
-- quiet note); get_my_dating_introductions() v2 (every card the person can
-- answer, for /dating/introduction/:id); act v2 (answers {ok, reason},
-- never raises a refusal; per-side visibility; the caller's own phone
-- first; one match from simultaneous interest; no push); the match moment
-- marks; the Today notes; dating_photo_keys_for_viewer for dating-photo-urls
-- (the phone checked first, only viewable photos, never before mutual
-- interest when the person chose that); send_dating_digests and its cron.
-- An answer that is not a filter (the family question, a name, what is
-- shown) no longer ends the person's open introductions.
-- Dating stays off. Idempotent.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- =====================================================================
-- 1. Columns: each side's match moment (§3.5); the Today notes and the
--    digest's last send (§3.4, §3.13, §5.6).
-- =====================================================================
ALTER TABLE public.dating_matches
  ADD COLUMN IF NOT EXISTS low_moment_seen_at timestamptz,
  ADD COLUMN IF NOT EXISTS high_moment_seen_at timestamptz;
ALTER TABLE public.dating_settings
  ADD COLUMN IF NOT EXISTS family_asked_at timestamptz,
  ADD COLUMN IF NOT EXISTS quiet_note_at timestamptz,
  ADD COLUMN IF NOT EXISTS digest_sent_at timestamptz;

-- =====================================================================
-- 2. The v1 read goes (W5b replaces it; no caller in lib/).
-- =====================================================================
DROP FUNCTION IF EXISTS public.get_my_dating_introductions(integer);

-- =====================================================================
-- 3. The card (§3.4, §5.8; carries 13, 14).
-- =====================================================================
-- A photo others may see: approved and cleared by the inline CSAM scan
-- (never a hit, an error or one waiting), the derived "viewable" rule.
CREATE OR REPLACE FUNCTION private.dating_photo_viewable(p_moderation text, p_csam text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT coalesce(p_moderation = 'approved' AND p_csam = 'clear', false);
$$;

-- [p_subject] as [p_viewer] sees them on introduction [p_intro]. Built
-- from the subject's own rows; decrypts only what the subject chose to
-- show. NULL when the subject has no profile.
CREATE OR REPLACE FUNCTION private.dating_card(p_viewer uuid, p_subject uuid, p_intro public.dating_introductions)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_p public.dating_profiles;
  v_s public.dating_profile_sensitive;
  v_identity jsonb;
  v_faith jsonb;
  v_marital text;
  v_region jsonb;
  v_side jsonb;
  v_photos jsonb;
BEGIN
  SELECT * INTO v_p FROM public.dating_profiles AS p WHERE p.user_id = p_subject;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  SELECT * INTO v_s FROM public.dating_profile_sensitive AS s WHERE s.user_id = p_subject;
  IF v_p.gender_visible THEN
    v_identity := private.dating_field_decrypt(v_s.identity_enc);
  END IF;
  IF v_p.faith_visible THEN
    v_faith := private.dating_field_decrypt(v_s.faith_enc);
  END IF;
  IF v_p.marital_visible THEN
    v_marital := private.dating_field_decrypt(v_s.marital_enc) ->> 'marital';
  END IF;
  SELECT r INTO v_region FROM jsonb_array_elements((public.dating_country_config(v_p.country_code)).region_list) AS r
   WHERE r ->> 'code' = v_p.region_code;
  -- The side is never a field; it is named only by its own reason.
  IF 'same_side' = ANY (p_intro.reasons) THEN
    SELECT x INTO v_side FROM jsonb_array_elements(v_region -> 'sides') AS x WHERE x ->> 'code' = v_p.side_code;
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'position', f.position, 'caption', f.caption) ORDER BY f.position), '[]'::jsonb)
    INTO v_photos
    FROM public.dating_profile_photos AS f
   WHERE f.user_id = p_subject AND private.dating_photo_viewable(f.moderation_state, f.csam_state);
  RETURN jsonb_build_object(
    'id', p_intro.id,
    'display_name', v_p.display_name,
    'age', public.account_age(p_subject),
    'region_name_key', v_region ->> 'name_key',
    'side_name_key', v_side ->> 'name_key',
    'intention', v_p.intention,
    'marriage_timeline', CASE WHEN v_p.intention = 'marriage' AND v_p.timeline_visible THEN v_p.marriage_timeline END,
    'children_have', v_p.children_have,
    'children_want', v_p.children_want,
    'gender', CASE WHEN v_identity IS NULL THEN NULL ELSE jsonb_build_object(
      'identity', v_identity ->> 'identity', 'specific', v_identity ->> 'specific',
      'specific_text', v_identity ->> 'specific_text') END,
    'pronouns', v_identity ->> 'pronouns',
    'faith', CASE WHEN v_faith IS NULL THEN NULL ELSE jsonb_build_object(
      'faith', v_faith ->> 'faith', 'denomination', v_faith ->> 'denomination') END,
    'marital', CASE WHEN v_marital IN ('divorced', 'widowed') THEN v_marital END,
    'prompts', coalesce((SELECT jsonb_agg(jsonb_build_object('prompt_id', q.prompt_id, 'answer', q.answer) ORDER BY q.position)
                           FROM public.dating_prompts AS q
                          WHERE q.user_id = p_subject AND q.moderation_state = 'approved'), '[]'::jsonb),
    'reasons', to_jsonb(p_intro.reasons),
    -- D9: while the subject keeps photos for mutual interest, none (and
    -- the card says they're coming); else the viewable ones, captions as
    -- their spoken labels (§3.4 accessibility).
    'photos_after_mutual', v_p.photos_after_mutual,
    'photos', CASE WHEN v_p.photos_after_mutual THEN '[]'::jsonb ELSE v_photos END,
    'acted', CASE WHEN p_intro.user_low_id = p_viewer THEN p_intro.low_action ELSE p_intro.high_action END);
END;
$$;

-- The introductions [p_viewer] can answer now: their side's drop has
-- come, their own seven days are not over, they haven't passed, the pair
-- is still safe (blocks, former partners, never-introduce: kept rows too)
-- and both are current candidates. Never "they liked you": only the
-- viewer's own action is read.
CREATE OR REPLACE FUNCTION private.dating_visible_introductions(p_viewer uuid)
RETURNS SETOF public.dating_introductions
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT i.*
    FROM public.dating_introductions AS i
   WHERE p_viewer IN (i.user_low_id, i.user_high_id)
     AND i.state IN ('generated', 'presented', 'interested')
     AND i.expires_at > now()
     AND CASE WHEN i.user_low_id = p_viewer
              THEN i.visible_from_low <= now() AND i.low_action IS DISTINCT FROM 'passed'
                   AND i.visible_from_low + make_interval(days => coalesce(((private.dating_intro_config()).o_config ->> 'lifetime_days')::int, 7)) > now()
              ELSE i.visible_from_high <= now() AND i.high_action IS DISTINCT FROM 'passed'
                   AND i.visible_from_high + make_interval(days => coalesce(((private.dating_intro_config()).o_config ->> 'lifetime_days')::int, 7)) > now() END
     AND coalesce(public.dating_candidate_is_current(CASE WHEN i.user_low_id = p_viewer THEN i.user_high_id ELSE i.user_low_id END), false)
     AND coalesce(private.dating_pair_safe(i.user_low_id, i.user_high_id,
                                           public.dating_phone_hmac_for_user(i.user_low_id),
                                           public.dating_phone_hmac_for_user(i.user_high_id)), false);
$$;

-- =====================================================================
-- 4. Today (§3.4, §5.6; carry 8).
-- =====================================================================
CREATE OR REPLACE FUNCTION public.get_my_dating_today()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_cfg jsonb;
  v_p public.dating_profiles;
  v_d public.dating_preferences;
  v_t public.dating_settings;
  v_tz text;
  v_drop timestamptz;
  v_cards jsonb := '[]'::jsonb;
  v_waiting jsonb := '[]'::jsonb;
  v_moments jsonb;
  v_state text;
  v_seen boolean;
  v_i public.dating_introductions;
  v_card jsonb;
  v_region text;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_enrollments AS e WHERE e.user_id = v_user AND e.state = 'active')
     OR public.dating_eligibility(v_user, 'candidate') IS DISTINCT FROM 'eligible' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_eligible');
  END IF;
  v_cfg := (private.dating_intro_config()).o_config;
  SELECT * INTO v_p FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  SELECT * INTO v_d FROM public.dating_preferences AS d WHERE d.user_id = v_user;
  SELECT * INTO v_t FROM public.dating_settings AS t WHERE t.user_id = v_user;
  SELECT r ->> 'name_key' INTO v_region
    FROM jsonb_array_elements((public.dating_country_config(v_p.country_code)).region_list) AS r WHERE r ->> 'code' = v_p.region_code;
  FOR v_i IN SELECT * FROM private.dating_visible_introductions(v_user) AS x
              ORDER BY CASE WHEN x.user_low_id = v_user THEN x.visible_from_low ELSE x.visible_from_high END DESC, x.id LOOP
    v_card := private.dating_card(v_user, CASE WHEN v_i.user_low_id = v_user THEN v_i.user_high_id ELSE v_i.user_low_id END, v_i);
    CONTINUE WHEN v_card IS NULL;
    -- Delivered at the last drop: today; earlier: still waiting (no date
    -- is ever sent: no countdown, Fable M8).
    IF (CASE WHEN v_i.user_low_id = v_user THEN v_i.visible_from_low ELSE v_i.visible_from_high END) > now() - interval '24 hours' THEN
      v_cards := v_cards || jsonb_build_array(v_card);
    ELSE
      v_waiting := v_waiting || jsonb_build_array(v_card);
    END IF;
  END LOOP;

  SELECT coalesce(jsonb_agg(jsonb_build_object('match_id', m.id, 'display_name', p.display_name) ORDER BY m.matched_at), '[]'::jsonb)
    INTO v_moments
    FROM public.dating_matches AS m
    JOIN public.dating_profiles AS p ON p.user_id = CASE WHEN m.user_low_id = v_user THEN m.user_high_id ELSE m.user_low_id END
   WHERE m.state = 'active' AND v_user IN (m.user_low_id, m.user_high_id)
     AND CASE WHEN m.user_low_id = v_user THEN m.low_moment_seen_at ELSE m.high_moment_seen_at END IS NULL;

  v_seen := EXISTS (SELECT 1 FROM public.dating_introductions AS i
                     WHERE v_user IN (i.user_low_id, i.user_high_id)
                       AND CASE WHEN i.user_low_id = v_user THEN i.visible_from_low ELSE i.visible_from_high END <= now());
  -- The person's next drop with an introduction waiting for it.
  SELECT min(CASE WHEN i.user_low_id = v_user THEN i.visible_from_low ELSE i.visible_from_high END) INTO v_drop
    FROM public.dating_introductions AS i
   WHERE v_user IN (i.user_low_id, i.user_high_id) AND i.state IN ('generated', 'presented', 'interested')
     AND CASE WHEN i.user_low_id = v_user THEN i.visible_from_low ELSE i.visible_from_high END > now();
  v_state := CASE
    WHEN coalesce(private.dating_cool_off_ends_at(v_user) > now(), true) THEN 'cool_off'
    WHEN jsonb_array_length(v_cards) > 0 THEN 'delivered'
    WHEN v_drop IS NOT NULL THEN 'before_drop'
    WHEN private.dating_open_chats(v_user, now()) >= coalesce((v_cfg ->> 'open_chat_pause_at')::int, 3) THEN 'paused_open_chats'
    WHEN jsonb_array_length(v_waiting) >= coalesce((v_cfg ->> 'waiting_max')::int, 6) THEN 'queue_full'
    ELSE 'empty' END;

  RETURN jsonb_build_object(
    'ok', true,
    'today_state', v_state,
    'drop_at', CASE WHEN v_state = 'before_drop' THEN v_drop
                    WHEN v_state = 'cool_off' THEN private.dating_first_drop_at(v_user, greatest(now(), private.dating_cool_off_ends_at(v_user))) END,
    'region_name_key', v_region,
    'my_name', v_p.display_name, -- the moment's own first-letter avatar (§3.5)
    'cards', v_cards,
    'waiting', v_waiting,
    'moments', v_moments,
    -- Once, after the first introduction (§3.4); shared ground only.
    'family_question', v_seen AND v_p.family_involvement IS NULL AND v_t.family_asked_at IS NULL,
    -- §5.6: no introduction for 14 days in a row, shown once.
    'quiet_note', v_t.quiet_note_at IS NULL
      AND coalesce((SELECT e.activated_at FROM public.dating_enrollments AS e WHERE e.user_id = v_user) < now() - interval '14 days', false)
      AND NOT EXISTS (SELECT 1 FROM public.dating_introductions AS i
                       WHERE v_user IN (i.user_low_id, i.user_high_id) AND i.created_at > now() - interval '14 days'),
    'data_saver', coalesce(v_t.data_saver, false),
    'widen', jsonb_build_object('min_age', v_d.min_age, 'max_age', v_d.max_age, 'scope', v_d.region_scope));
EXCEPTION WHEN raise_exception THEN
  -- An unreadable answer or a missing field key: never a raw error.
  IF SQLERRM IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  RAISE;
END;
$$;

-- Every card the person can answer now (§4.4 v2; /dating/introduction/:id).
CREATE OR REPLACE FUNCTION public.get_my_dating_introductions()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_cards jsonb := '[]'::jsonb;
  v_i public.dating_introductions;
  v_card jsonb;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  IF public.dating_eligibility(v_user, 'candidate') IS DISTINCT FROM 'eligible' THEN
    RETURN jsonb_build_object('ok', true, 'cards', '[]'::jsonb);
  END IF;
  FOR v_i IN SELECT * FROM private.dating_visible_introductions(v_user) AS x ORDER BY x.created_at DESC, x.id LOOP
    v_card := private.dating_card(v_user, CASE WHEN v_i.user_low_id = v_user THEN v_i.user_high_id ELSE v_i.user_low_id END, v_i);
    IF v_card IS NOT NULL THEN
      v_cards := v_cards || jsonb_build_array(v_card);
    END IF;
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'cards', v_cards);
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  RAISE;
END;
$$;

-- =====================================================================
-- 5. Act v2 (§3.4, §4.10; R-17): fixed answers, never a raised refusal.
--    The caller's own phone first; the caller's setup lock, then the
--    introduction row (the shared order: exit takes the same lock first),
--    with a bounded retry; one uniform answer for an introduction that
--    isn't the caller's, doesn't exist, isn't theirs to see yet or is
--    over (H2). A permanent safety reason (a block, former partners, a
--    never-introduce entry) ends the pair; a counterpart who is away for
--    now (paused, not seen) leaves it as it is. Mutual interest makes one
--    match (the second actor waits on the row) and queues no push.
-- =====================================================================
DROP FUNCTION IF EXISTS public.act_on_dating_introduction(text, uuid, text);
CREATE FUNCTION public.act_on_dating_introduction(p_idempotency_key text, p_introduction_id uuid, p_action text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_i public.dating_introductions;
  v_other text;
  v_mine text;
  v_match uuid;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_action IS NULL OR p_action NOT IN ('interested', 'passed') OR p_introduction_id IS NULL
     OR p_idempotency_key IS NULL OR char_length(p_idempotency_key) NOT BETWEEN 16 AND 128
     OR p_idempotency_key !~ '^[A-Za-z0-9_:.-]+$' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  IF public.dating_eligibility(v_user, 'candidate') IS DISTINCT FROM 'eligible'
     OR NOT EXISTS (SELECT 1 FROM public.dating_enrollments AS e WHERE e.user_id = v_user AND e.state = 'active') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_eligible');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(v_user);
      -- A replay answers as the first did.
      IF EXISTS (SELECT 1 FROM public.dating_rpc_idempotency AS k
                  WHERE k.user_id = v_user AND k.operation = 'act_on_dating_introduction' AND k.idempotency_key = p_idempotency_key) THEN
        SELECT a.action INTO v_mine FROM public.dating_interest_actions AS a
         WHERE a.actor_user_id = v_user AND a.idempotency_key = p_idempotency_key;
        RETURN jsonb_build_object('ok', true, 'action', v_mine,
          'matched', EXISTS (SELECT 1 FROM public.dating_interest_actions AS a
                              JOIN public.dating_matches AS m ON m.introduction_id = a.introduction_id
                             WHERE a.actor_user_id = v_user AND a.idempotency_key = p_idempotency_key));
      END IF;
      SELECT * INTO v_i FROM public.dating_introductions AS i
       WHERE i.id = p_introduction_id AND v_user IN (i.user_low_id, i.user_high_id)
       FOR UPDATE;
      IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM private.dating_visible_introductions(v_user) AS x WHERE x.id = v_i.id) THEN
        -- Gone, not the caller's, not yet theirs to see, over, or a pair
        -- that is no longer safe: one answer. A pair no longer safe ends.
        IF FOUND AND v_i.state IN ('generated', 'presented', 'interested')
           AND private.dating_pair_safe(v_i.user_low_id, v_i.user_high_id,
                 public.dating_phone_hmac_for_user(v_i.user_low_id), public.dating_phone_hmac_for_user(v_i.user_high_id)) IS NOT TRUE THEN
          UPDATE public.dating_introductions SET state = 'invalidated' WHERE id = v_i.id;
        END IF;
        RETURN jsonb_build_object('ok', false, 'reason', 'introduction_unavailable');
      END IF;
      v_mine := CASE WHEN v_i.user_low_id = v_user THEN v_i.low_action ELSE v_i.high_action END;
      IF v_mine IS NOT NULL THEN
        -- No rewind (§3.4): the first answer stands.
        RETURN jsonb_build_object('ok', true, 'action', v_mine, 'matched', v_i.state = 'matched');
      END IF;
      BEGIN
        PERFORM public.check_dating_rate_limit('interest_action', 60, interval '1 day');
      EXCEPTION WHEN invalid_parameter_value THEN
        IF SQLERRM IS DISTINCT FROM 'rate_limited' THEN
          RAISE;
        END IF;
        RETURN jsonb_build_object('ok', false, 'reason', 'rate_limited');
      END;
      PERFORM public.claim_dating_idempotency('act_on_dating_introduction', p_idempotency_key);
      INSERT INTO public.dating_interest_actions (introduction_id, actor_user_id, action, idempotency_key, acted_at)
      VALUES (v_i.id, v_user, p_action, p_idempotency_key, now())
      ON CONFLICT (introduction_id, actor_user_id) DO NOTHING;
      v_other := CASE WHEN v_i.user_low_id = v_user THEN v_i.high_action ELSE v_i.low_action END;
      UPDATE public.dating_introductions AS i
         SET low_action = CASE WHEN i.user_low_id = v_user THEN p_action ELSE i.low_action END,
             high_action = CASE WHEN i.user_high_id = v_user THEN p_action ELSE i.high_action END,
             state = CASE WHEN p_action = 'passed' THEN 'passed'
                          WHEN v_other = 'interested' THEN 'matched' ELSE 'interested' END
       WHERE i.id = v_i.id;
      IF p_action = 'interested' AND v_other = 'interested' THEN
        INSERT INTO public.dating_matches (introduction_id, user_low_id, user_high_id, state, matched_at, created_at)
        VALUES (v_i.id, v_i.user_low_id, v_i.user_high_id, 'active', now(), now())
        ON CONFLICT (introduction_id) DO NOTHING
        RETURNING id INTO v_match;
        IF v_match IS NOT NULL THEN
          PERFORM private.bump_metric_internal('dating.mutual');
        END IF;
      END IF;
      RETURN jsonb_build_object('ok', true, 'action', p_action, 'matched', p_action = 'interested' AND v_other IS NOT DISTINCT FROM 'interested');
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- =====================================================================
-- 6. The match moment and the Today notes (§3.4, §3.5, §5.6). The same
--    answer whoever's match it is (no membership oracle).
-- =====================================================================
CREATE OR REPLACE FUNCTION public.mark_dating_match_moment_seen(p_match_id uuid)
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
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  UPDATE public.dating_matches AS m
     SET low_moment_seen_at = CASE WHEN m.user_low_id = v_user THEN coalesce(m.low_moment_seen_at, now()) ELSE m.low_moment_seen_at END,
         high_moment_seen_at = CASE WHEN m.user_high_id = v_user THEN coalesce(m.high_moment_seen_at, now()) ELSE m.high_moment_seen_at END
   WHERE m.id = p_match_id AND v_user IN (m.user_low_id, m.user_high_id);
  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.dismiss_dating_today_note(p_note text)
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
  IF p_note IS NULL OR p_note NOT IN ('family', 'quiet') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_profiles AS p WHERE p.user_id = v_user) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_eligible');
  END IF;
  INSERT INTO public.dating_settings AS t (user_id, family_asked_at, quiet_note_at)
  VALUES (v_user, CASE WHEN p_note = 'family' THEN now() END, CASE WHEN p_note = 'quiet' THEN now() END)
  ON CONFLICT (user_id) DO UPDATE
    SET family_asked_at = CASE WHEN p_note = 'family' THEN coalesce(t.family_asked_at, now()) ELSE t.family_asked_at END,
        quiet_note_at = CASE WHEN p_note = 'quiet' THEN coalesce(t.quiet_note_at, now()) ELSE t.quiet_note_at END,
        updated_at = now();
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- =====================================================================
-- 7. Photo keys for dating-photo-urls (§4.4, §4.7; carries 12-14), the
--    service role's. The viewer's phone is checked first (the hash the
--    edge function computed from x-attune-device); only viewable photos;
--    for an introduction, only one the viewer can answer now and never
--    while the other person keeps photos for mutual interest; for a
--    match, the other member's while it is active. One answer for every
--    refusal; never a key for anyone else's photo.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.dating_photo_keys_for_viewer(p_viewer uuid, p_kind text, p_id uuid, p_device_hash text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_subject uuid;
  v_keys jsonb;
BEGIN
  IF p_viewer IS NULL OR p_id IS NULL OR p_kind IS NULL OR p_kind NOT IN ('introduction', 'match') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'photos_unavailable');
  END IF;
  IF coalesce(private.dating_device_state(p_viewer, p_device_hash) IN ('trusted', 'unbound'), false) IS NOT TRUE
     OR (p_device_hash IS NULL AND EXISTS (SELECT 1 FROM public.dating_trusted_devices AS d WHERE d.user_id = p_viewer)) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  IF public.dating_flag_enabled('dating_mode_enabled') IS NOT TRUE OR public.dating_flag_enabled('dating_profile_photos') IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'photos_unavailable');
  END IF;
  IF p_kind = 'introduction' THEN
    SELECT CASE WHEN x.user_low_id = p_viewer THEN x.user_high_id ELSE x.user_low_id END INTO v_subject
      FROM private.dating_visible_introductions(p_viewer) AS x
     WHERE x.id = p_id
       AND public.dating_candidate_is_current(p_viewer)
       AND NOT (SELECT p.photos_after_mutual FROM public.dating_profiles AS p
                 WHERE p.user_id = CASE WHEN x.user_low_id = p_viewer THEN x.user_high_id ELSE x.user_low_id END);
  ELSE
    SELECT CASE WHEN m.user_low_id = p_viewer THEN m.user_high_id ELSE m.user_low_id END INTO v_subject
      FROM public.dating_matches AS m
     WHERE m.id = p_id AND m.state = 'active' AND p_viewer IN (m.user_low_id, m.user_high_id)
       AND m.user_low_id IS NOT NULL AND m.user_high_id IS NOT NULL
       AND private.dating_pair_safe(m.user_low_id, m.user_high_id,
             public.dating_phone_hmac_for_user(m.user_low_id), public.dating_phone_hmac_for_user(m.user_high_id));
  END IF;
  IF v_subject IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'photos_unavailable');
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('position', f.position, 'key', f.storage_key) ORDER BY f.position), '[]'::jsonb)
    INTO v_keys
    FROM public.dating_profile_photos AS f
   WHERE f.user_id = v_subject AND private.dating_photo_viewable(f.moderation_state, f.csam_state);
  RETURN jsonb_build_object('ok', true, 'photos', v_keys);
END;
$$;

-- =====================================================================
-- 8. The daily digest (§3.13): at most one a day, at the person's drop
--    time, only if they turned it on, only with new introductions today or
--    a match since the last digest. The neutral me_update push (W3a);
--    quiet hours fold it through the push queue. Hourly at :05.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.send_dating_digests()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  r record;
  v_n integer := 0;
  v_drop timestamptz;
BEGIN
  IF public.dating_flag_enabled('dating_mode_enabled') IS NOT TRUE THEN
    RETURN 0;
  END IF;
  -- No push key, no push (fail closed, counted; the cron never raises).
  IF public.app_setting('dating_push_key') IS NULL THEN
    PERFORM private.bump_metric_internal('dating.digest.push_key_missing');
    RETURN 0;
  END IF;
  FOR r IN
    SELECT t.user_id, t.digest_sent_at
      FROM public.dating_settings AS t
      JOIN public.dating_enrollments AS e ON e.user_id = t.user_id AND e.state = 'active'
     WHERE t.digest_push
     ORDER BY t.user_id
  LOOP
    -- The drop that fell in the last hour, if one did.
    v_drop := private.dating_first_drop_at(r.user_id, now() - interval '1 hour');
    CONTINUE WHEN v_drop > now();
    CONTINUE WHEN r.digest_sent_at IS NOT NULL AND r.digest_sent_at >= v_drop - interval '1 hour';
    CONTINUE WHEN NOT (
      EXISTS (SELECT 1 FROM private.dating_visible_introductions(r.user_id) AS x
               WHERE CASE WHEN x.user_low_id = r.user_id THEN x.visible_from_low ELSE x.visible_from_high END > now() - interval '24 hours')
      OR EXISTS (SELECT 1 FROM public.dating_matches AS m
                  WHERE m.state = 'active' AND r.user_id IN (m.user_low_id, m.user_high_id)
                    AND m.matched_at > coalesce(r.digest_sent_at, '-infinity'::timestamptz)));
    IF private.dating_queue_me_update(r.user_id, 'digest', 'new') THEN
      v_n := v_n + 1;
    END IF;
    UPDATE public.dating_settings SET digest_sent_at = now() WHERE user_id = r.user_id;
  END LOOP;
  RETURN v_n;
END;
$$;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dating-digest') THEN
    PERFORM cron.unschedule('dating-digest');
  END IF;
  PERFORM cron.schedule('dating-digest', '5 * * * *', 'SELECT public.send_dating_digests()');
END $$;

-- =====================================================================
-- 9. Functions re-created from their LIVE bodies (Spec 2 W5b lines only).
-- =====================================================================
```

Create `$D/mig_T4_tail.sql` with exactly:

```sql

-- =====================================================================
-- 10. Grants (re-asserted by the twin). The reads, act and the marks are
--     the app's; the photo keys the service role's (dating-photo-urls);
--     the digest is cron's; the helpers are the database's own.
-- =====================================================================
REVOKE ALL ON FUNCTION private.dating_photo_viewable(text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_card(uuid, uuid, public.dating_introductions) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_visible_introductions(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_my_dating_today() FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.get_my_dating_introductions() FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.act_on_dating_introduction(text, uuid, text) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.mark_dating_match_moment_seen(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.dismiss_dating_today_note(text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_dating_today(), public.get_my_dating_introductions(),
  public.act_on_dating_introduction(text, uuid, text), public.mark_dating_match_moment_seen(uuid),
  public.dismiss_dating_today_note(text) TO authenticated;
REVOKE ALL ON FUNCTION public.dating_photo_keys_for_viewer(uuid, text, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dating_photo_keys_for_viewer(uuid, text, uuid, text) TO service_role;
REVOKE ALL ON FUNCTION public.send_dating_digests() FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
```

Create `$D/build_mig_T4.py` with exactly:

```python
#!/usr/bin/env python3
# Spec 2 W5b: builds supabase/migrations/20261119110000_dating_v2_today.sql
# from mig_T4_head.sql, the functions below re-created from their LIVE
# bodies (saved to before_w5b/) with only the lines marked "-- Spec 2 W5b"
# changed, and mig_T4_tail.sql. Every anchor must occur exactly once.
import pathlib
D = pathlib.Path('.superpowers/sdd/2026-11-19-spec2-w5')
OUT = pathlib.Path('supabase/migrations/20261119110000_dating_v2_today.sql')

def live(sig):
    return (D / 'before_w5b' / f'{sig}.sql').read_text().rstrip('\n')

M = '-- Spec 2 W5b'
FNS = []

# 1. A profile change ends the person's open introductions only when it
#    changes a filter input (§5.2): the family question, a name or what is
#    shown is read live by the card and ends nothing. Preferences are all
#    filter inputs, as before.
FNS.append(('public.invalidate_dating_on_profile_change()', [
  ("""BEGIN
  PERFORM public.invalidate_dating_for_user(NEW.user_id,'profile_or_preference_changed');""",
   f"""BEGIN
  IF TG_TABLE_NAME = 'dating_profiles' THEN {M} (§3.4): not a filter input, nothing ends
    IF (OLD.country_code, OLD.region_code, OLD.side_code, OLD.intention, OLD.children_have, OLD.children_want, {M}
        OLD.profile_state, OLD.moderation_state, OLD.verification_state) {M}
       IS NOT DISTINCT FROM (NEW.country_code, NEW.region_code, NEW.side_code, NEW.intention, NEW.children_have, {M}
        NEW.children_want, NEW.profile_state, NEW.moderation_state, NEW.verification_state) THEN {M}
      RETURN NEW; {M}
    END IF; {M}
  END IF; {M}
  PERFORM public.invalidate_dating_for_user(NEW.user_id,'profile_or_preference_changed');""")]))

parts = []
for sig, pairs in FNS:
    body = live(sig)
    for old, new in pairs:
        n = body.count(old)
        assert n == 1, f'{sig}: anchor occurs {n} times: {old[:60]!r}'
        body = body.replace(old, new)
    parts.append(body + ';\n')
OUT.write_text((D / 'mig_T4_head.sql').read_text() + '\n'.join(parts) + '\n' + (D / 'mig_T4_tail.sql').read_text())
print(f'{OUT}: {len(FNS)} function(s) re-created')
```

Create `supabase/migrations/20261119110010_dating_v2_today_grants.sql` with exactly:

```sql
-- Spec 2 W5b: grants for 20261119110000_dating_v2_today.sql. Today, the
-- introductions read, act and the two marks are the app's (authenticated
-- only); the photo keys are the service role's (dating-photo-urls); the
-- digest is cron's; the helpers are the database's own, the service role
-- included (the card decrypts what the person chose to show, S-4). The
-- introductions and matches stay no API role's (S-5).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.dating_introductions, public.dating_matches, public.dating_interest_actions
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_photo_viewable(text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_card(uuid, uuid, public.dating_introductions) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_visible_introductions(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_my_dating_today() FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.get_my_dating_introductions() FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.act_on_dating_introduction(text, uuid, text) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.mark_dating_match_moment_seen(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.dismiss_dating_today_note(text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_dating_today(), public.get_my_dating_introductions(),
  public.act_on_dating_introduction(text, uuid, text), public.mark_dating_match_moment_seen(uuid),
  public.dismiss_dating_today_note(text) TO authenticated;
REVOKE ALL ON FUNCTION public.dating_photo_keys_for_viewer(uuid, text, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dating_photo_keys_for_viewer(uuid, text, uuid, text) TO service_role;
REVOKE ALL ON FUNCTION public.send_dating_digests() FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
```

- [ ] **Step 4: Build, apply, run**

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5
python3 -I $D/build_mig_T4.py
for f in supabase/migrations/20261119110000_dating_v2_today.sql supabase/migrations/20261119110010_dating_v2_today_grants.sql; do
  for run in 1 2; do psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $f > /dev/null 2> $D/apply_err.txt; rc=$?; echo "$(basename $f) run $run exit=$rc"; grep -v NOTICE $D/apply_err.txt || true; done
done
python3 -I $D/marked_diff.py $D/before_w5b attune_spec3a 'Spec 2 W5b'
python3 -I $D/grants_line.py supabase/migrations/20261119100010_dating_v2_matching_grants.sql 'Spec 2 W5b: Today (twin of 20261119110000)' supabase/migrations/20261119110010_dating_v2_today_grants.sql
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_matching_contracts.sql 2>&1 | grep -v 'skipping' | tail -1
```

Expected: `supabase/migrations/20261119110000_dating_v2_today.sql: 1 function(s) re-created`; four `exit=0`; `public.invalidate_dating_on_profile_change(): 8 added line(s), 0 removed OK`; `local_pg_grants.sql: one \i block added`; `NOTICE:  dating_v2_matching_contracts: all held`.

- [ ] **Step 5: The existing contracts meet Today; the race for simultaneous interest**

Create `$D/edit_tests_T4.py` with exactly:

```python
# Spec 2 W5b Task 4: the existing contracts meet Today. dating_mode's
# four-account proof (Fable C1) moves to the v2 read (get_my_dating_
# introductions() -> cards) and to act's fixed answers (never a raise): a
# forged act and an absent one answer the same; B's card never shows A's
# action; a blocked or former-partner pair is neither read nor answered.
# Act keys are 16+ characters (act v2 pre-validates them). The canary takes
# W5b's functions; setup's G3 allow-list takes the card builder and the
# photo keys, deliberately, with their photos-after-mutual rule.
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anchor import edit

T = 'supabase/tests/'
W = '-- Spec 2 W5b'
AB = "'00000000-0000-0000-0000-000000ab0000'"

edit(T + 'dating_mode_contracts.sql', [
  ("""DO $$ DECLARE v int; BEGIN
  SELECT count(*) INTO v FROM public.get_my_dating_introductions(20);""",
   f"""DO $$ DECLARE v int; BEGIN
  v := jsonb_array_length(public.get_my_dating_introductions() -> 'cards'); {W}: the v2 read"""),
  ("""DO $$ DECLARE v int; v_raised boolean := false; BEGIN
  BEGIN
    PERFORM public.act_on_dating_introduction(
      'forgery-key-c', '00000000-0000-0000-0000-000000ab0000', 'interested');
  EXCEPTION
    -- The RPC signals refusal with USING ERRCODE (e.g. 22023 introduction_unavailable,
    -- 42501 not_authenticated); catch any refusal here. A missing raise fails below.
    WHEN OTHERS THEN v_raised := true;
  END;
  IF NOT v_raised THEN RAISE EXCEPTION 'C: acting on non-member intro unexpectedly succeeded'; END IF;""",
   f"""DO $$ DECLARE v int; v_answer jsonb; BEGIN
  v_answer := public.act_on_dating_introduction('w5b-forgery-key-c0', {AB}, 'interested'); {W}: a fixed answer, never a raise
  IF (v_answer ->> 'ok')::boolean IS NOT FALSE THEN {W}
    RAISE EXCEPTION 'C: acting on a non-member intro answered %', v_answer; {W}
  END IF; {W}"""),
  ("""  s_forged text; m_forged text;   -- C acts on A/B's intro (exists, not a member)
  s_absent text; m_absent text;   -- C acts on a random nonexistent intro id
BEGIN
  BEGIN
    PERFORM public.act_on_dating_introduction('h2-forged','00000000-0000-0000-0000-000000ab0000','interested');
    RAISE EXCEPTION 'H2: forged act did not raise';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s_forged = RETURNED_SQLSTATE; m_forged := SQLERRM;
  END;
  BEGIN
    PERFORM public.act_on_dating_introduction('h2-absent','00000000-0000-0000-0000-0000000ab123','interested');
    RAISE EXCEPTION 'H2: nonexistent act did not raise';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s_absent = RETURNED_SQLSTATE; m_absent := SQLERRM;
  END;
  -- "belongs to someone else" and "does not exist" must be identical responses.
  IF s_forged <> s_absent OR m_forged <> m_absent THEN
    RAISE EXCEPTION 'H2 oracle: non-member (% / %) distinguishable from nonexistent (% / %)',
      s_forged, m_forged, s_absent, m_absent;
  END IF;""",
   f"""  v_forged jsonb; -- C acts on A/B's intro (exists, not a member) {W}
  v_absent jsonb; -- C acts on a random nonexistent intro id {W}
BEGIN
  v_forged := public.act_on_dating_introduction('w5b-h2-forged-key0', {AB}, 'interested'); {W}
  v_absent := public.act_on_dating_introduction('w5b-h2-absent-key0', '00000000-0000-0000-0000-0000000ab123', 'interested'); {W}
  -- "belongs to someone else" and "does not exist" must be identical responses.
  IF v_forged IS DISTINCT FROM v_absent OR (v_forged ->> 'ok')::boolean IS NOT FALSE THEN {W}
    RAISE EXCEPTION 'H2 oracle: non-member % distinguishable from nonexistent %', v_forged, v_absent; {W}
  END IF;"""),
  ("""  PERFORM public.act_on_dating_introduction(
    'a-likes-b', '00000000-0000-0000-0000-000000ab0000', 'interested');""",
   f"""  IF (public.act_on_dating_introduction('w5b-a-likes-b-key0', {AB}, 'interested') ->> 'ok')::boolean IS NOT TRUE THEN {W}
    RAISE EXCEPTION 'A: interest in a live introduction was refused'; {W}
  END IF; {W}"""),
  ("""DO $$ DECLARE v_state text; BEGIN
  SELECT state INTO v_state FROM public.get_my_dating_introductions(20)
  WHERE id = '00000000-0000-0000-0000-000000ab0000';
  IF v_state IS NULL THEN
    RAISE EXCEPTION 'B: (A,B) intro missing from B''s list after A acted';
  END IF;
  -- The viewer-scoped status for a non-acting viewer must be 'open'. Any value
  -- reflecting A''s action ('interested', 'awaiting_response', 'matched') would
  -- be the banned one-sided-interest oracle.
  IF v_state <> 'open' THEN
    RAISE EXCEPTION 'B: double-blind leak — B sees state=% (must be open)', v_state;
  END IF;""",
   f"""DO $$ DECLARE v_card jsonb; BEGIN
  SELECT c INTO v_card FROM jsonb_array_elements(public.get_my_dating_introductions() -> 'cards') AS c {W}
   WHERE c ->> 'id' = '00000000-0000-0000-0000-000000ab0000'; {W}
  IF v_card IS NULL THEN
    RAISE EXCEPTION 'B: (A,B) intro missing from B''s list after A acted';
  END IF;
  -- B's card carries only B's own action (none yet). Anything reflecting
  -- A's (interested, matched) would be the banned one-sided-interest oracle.
  IF v_card -> 'acted' IS DISTINCT FROM 'null'::jsonb OR v_card::text ~ 'interested|matched' THEN {W}
    RAISE EXCEPTION 'B: double-blind leak in B''s card: %', v_card; {W}
  END IF;"""),
  ("""  PERFORM public.act_on_dating_introduction(
    'b-likes-a', '00000000-0000-0000-0000-000000ab0000', 'interested');""",
   f"""  IF public.act_on_dating_introduction('w5b-b-likes-a-key0', {AB}, 'interested') {W}
     IS DISTINCT FROM '{{"ok": true, "action": "interested", "matched": true}}'::jsonb THEN {W}
    RAISE EXCEPTION 'B: the reciprocating interest did not answer matched'; {W}
  END IF; {W}"""),
  ("""DO $$ DECLARE v int; v_raised boolean := false; BEGIN
  BEGIN
    PERFORM public.act_on_dating_introduction(
      'a-acts-blocked-d', '00000000-0000-0000-0000-000000ad0000', 'interested');
  EXCEPTION
    WHEN OTHERS THEN v_raised := true;
  END;
  IF NOT v_raised THEN RAISE EXCEPTION 'A: acting on a blocked pair unexpectedly succeeded'; END IF;""",
   f"""DO $$ DECLARE v int; v_answer jsonb; BEGIN
  v_answer := public.act_on_dating_introduction('w5b-a-acts-blocked-d', '00000000-0000-0000-0000-000000ad0000', 'interested'); {W}
  IF v_answer IS DISTINCT FROM '{{"ok": false, "reason": "introduction_unavailable"}}'::jsonb THEN {W}
    RAISE EXCEPTION 'A: acting on a blocked pair answered %', v_answer; {W}
  END IF; {W}"""),
  ("""  SELECT count(*) INTO v FROM public.get_my_dating_introductions(20)
  WHERE id = '00000000-0000-0000-0000-000000ad0000';
  IF v <> 0 THEN RAISE EXCEPTION 'A: blocked (A,D) pair still visible in list (% rows)', v; END IF;""",
   f"""  SELECT count(*) INTO v FROM jsonb_array_elements(public.get_my_dating_introductions() -> 'cards') AS c {W}
   WHERE c ->> 'id' = '00000000-0000-0000-0000-000000ad0000'; {W}
  IF v <> 0 THEN RAISE EXCEPTION 'A: blocked (A,D) pair still visible in list (% rows)', v; END IF;"""),
  ("""  IF pg_get_function_result('public.get_my_dating_introductions(integer)'::regprocedure) ~* '(user_id|pair_key)' THEN
    RAISE EXCEPTION 'introduction payload exposes internal identity';
  END IF;""",
   f"""  IF to_regprocedure('public.get_my_dating_introductions(integer)') IS NOT NULL THEN {W}: the v1 read is gone
    RAISE EXCEPTION 'the v1 introductions read survived W5b'; {W}
  END IF;"""),
  ("""DO $$ DECLARE v int; v_raised boolean := false; BEGIN
  SELECT count(*) INTO v FROM public.get_my_dating_introductions(20)
  WHERE id = '00000000-0000-0000-0000-000000bd0000';
  IF v <> 0 THEN RAISE EXCEPTION 'C4: former-partner (B,D) intro visible in list (% rows)', v; END IF;
  BEGIN
    PERFORM public.act_on_dating_introduction(
      'b-acts-former-d', '00000000-0000-0000-0000-000000bd0000', 'interested');
  EXCEPTION WHEN OTHERS THEN v_raised := true;
  END;
  IF NOT v_raised THEN RAISE EXCEPTION 'C4: acting on a former-partner intro unexpectedly succeeded'; END IF;""",
   f"""DO $$ DECLARE v int; v_answer jsonb; BEGIN
  SELECT count(*) INTO v FROM jsonb_array_elements(public.get_my_dating_introductions() -> 'cards') AS c {W}
   WHERE c ->> 'id' = '00000000-0000-0000-0000-000000bd0000'; {W}
  IF v <> 0 THEN RAISE EXCEPTION 'C4: former-partner (B,D) intro visible in list (% rows)', v; END IF;
  v_answer := public.act_on_dating_introduction('w5b-b-acts-former-d', '00000000-0000-0000-0000-000000bd0000', 'interested'); {W}
  IF (v_answer ->> 'ok')::boolean IS NOT FALSE THEN {W}
    RAISE EXCEPTION 'C4: acting on a former-partner intro answered %', v_answer; {W}
  END IF; {W}"""),
], 'dating_mode: the C1 proof on the v2 read and act')

edit(T + 'dating_rls_canary.sql', [
  ("""-- W5a Task 2: generation is cron's (postgres), no API role's.
""",
   """-- W5b (migration 2): Today, the v2 read, act and the marks are the app's;
-- the photo keys the service role's; the digest is cron's; the card and
-- the visible-introductions set are the database's own (S-4, S-5).
DELETE FROM allowed_fn WHERE sig = 'get_my_dating_introductions(integer)';
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('get_my_dating_today()', 'authenticated', ''),
  ('get_my_dating_introductions()', 'authenticated', ''),
  ('mark_dating_match_moment_seen(uuid)', 'authenticated', ''),
  ('dismiss_dating_today_note(text)', 'authenticated', ''),
  ('dating_photo_keys_for_viewer(uuid,text,uuid,text)', '', 'service_role'),
  ('send_dating_digests()', '', ''),
  ('private.dating_photo_viewable(text,text)', '', ''),
  ('private.dating_card(uuid,uuid,dating_introductions)', '', ''),
  ('private.dating_visible_introductions(uuid)', '', '');
UPDATE allowed_fn SET service = '' WHERE sig = 'act_on_dating_introduction(text,uuid,text)';
-- W5a Task 2: generation is cron's (postgres), no API role's.
"""),
], 'canary: W5b rows')

edit(T + 'dating_v2_setup_contracts.sql', [
  ("""  -- Spec 2 W4 final (I-1b): whether every approved photo is newer than the
  -- Spec 2 W4 final age pass (a boolean, the database's own).""",
   """  -- Spec 2 W4 final (I-1b): whether every approved photo is newer than the
  -- Spec 2 W4 final age pass (a boolean, the database's own).
  -- Spec 2 W5b: the card others see (the database's own; none while the
  -- Spec 2 W5b person keeps photos for mutual interest, never a key) and the
  -- Spec 2 W5b photo keys for dating-photo-urls (the service role's: the
  -- Spec 2 W5b phone first, never before mutual interest when chosen)."""),
  ("""IF v_got IS DISTINCT FROM 'private.dating_age_recheck_due(uuid):; private.dating_exit_internal(uuid, boolean):;""",
   """IF v_got IS DISTINCT FROM 'private.dating_age_recheck_due(uuid):; private.dating_card(uuid, uuid, dating_introductions):; private.dating_exit_internal(uuid, boolean):;"""),
  ("""public.check_dating_photo_strip(uuid, text, text):service_role; public.claim_dating_orphan_uploads(integer):service_role; public.create_dating_photo_upload_intent(text):authenticated; public.dating_photos_queue_media_before_delete():;""",
   """public.check_dating_photo_strip(uuid, text, text):service_role; public.claim_dating_orphan_uploads(integer):service_role; public.create_dating_photo_upload_intent(text):authenticated; public.dating_photo_keys_for_viewer(uuid, text, uuid, text):service_role; public.dating_photos_queue_media_before_delete():;"""),
], 'setup G3: the card and the photo keys')
```

Create `$D/edit_races_T4.py` with exactly:

```python
# Spec 2 W5b Task 4: simultaneous mutual interest (§7.6 1.6/6.3, §8 W5b
# tests). Both people tap Interested at once: A's act sleeps holding the
# introduction row (its update), B's act waits on that row (after its own
# setup lock), then reads A's answer and makes the match. One match, both
# actions kept, no error, no deadlock.
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anchor import edit

edit('scripts/concurrency/dating_kill_switch_races.sh', [
  ("""$P -c "SELECT race.reset();" > /dev/null 2>&1
exit $fail""",
   """# Spec 2 W5b (Task 4): both interested at once make one match.
FX_MUTUAL="SELECT race.reset(); ALTER SEQUENCE race.s1 RESTART;
SELECT race.stub_complete();
SELECT race.person('07', 'GH', 'AA', 'woman', ARRAY['man']);
SELECT race.person('08', 'GH', 'AA', 'man', ARRAY['woman']);
INSERT INTO public.dating_age_verifications (user_id, age_method, age_result, age_vendor, age_decided_at, identity_method, identity_result, identity_vendor, identity_decided_at)
SELECT u, 'id', 'pass', 'race', now(), 'liveness_compare', 'pass', 'race', now() FROM (VALUES (race.id('07')), (race.id('08'))) AS x(u);
INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high)
VALUES (public.dating_pair_key(race.id('07'), race.id('08')), least(race.id('07'), race.id('08')), greatest(race.id('07'), race.id('08')),
        'generated', 'introductions_v2', now() - interval '1 hour', now() - interval '1 hour');"
MUTUAL_ID="(SELECT id FROM public.dating_introductions WHERE pair_key = public.dating_pair_key(race.id('07'), race.id('08')))"
run "simultaneous mutual interest makes one match" "$FX_MUTUAL" \\
  "SET race.sleep_dating_introductions_update = '2:race.s1';
   SELECT race.call(race.id('07'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', race.key('mutual-a'), $MUTUAL_ID)) ->> 'ok';" \\
  "SELECT pg_sleep(0.5);
   SELECT race.call(race.id('08'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', race.key('mutual-b'), $MUTUAL_ID)) ->> 'matched';" \\
  "SELECT CASE WHEN NOT (SELECT is_called FROM race.s1) THEN 'the first act never reached the row (no race)'
               WHEN (SELECT count(*) FROM public.dating_matches WHERE introduction_id = $MUTUAL_ID AND state = 'active') <> 1
               THEN 'matches: ' || (SELECT count(*) FROM public.dating_matches WHERE introduction_id = $MUTUAL_ID)
               WHEN (SELECT state || '/' || low_action || '/' || high_action FROM public.dating_introductions WHERE id = $MUTUAL_ID)
                    <> 'matched/interested/interested'
               THEN 'introduction: ' || (SELECT state || '/' || coalesce(low_action, '-') || '/' || coalesce(high_action, '-') FROM public.dating_introductions WHERE id = $MUTUAL_ID)
               ELSE 'ok' END;" serialised

$P -c "SELECT race.reset();" > /dev/null 2>&1
exit $fail"""),
], 'races: simultaneous mutual interest')
```

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5
python3 -I $D/edit_tests_T4.py
python3 -I $D/edit_races_T4.py
$D/suite.sh attune_spec3a > $D/sql-after-T4.txt; echo "$(grep -c '^PASS' $D/sql-after-T4.txt) PASS, $(grep -c '^FAIL' $D/sql-after-T4.txt) FAIL"
diff <(grep FAIL $D/sql-baseline.txt) <(grep FAIL $D/sql-after-T4.txt) && echo same-fails
dropdb --if-exists w5race 2>/dev/null; createdb w5race
pg_dump -s attune_spec3a | psql -X -q -d w5race > /dev/null 2>&1
pg_dump -a -t public.metric_key_prefixes -t public.feature_flags -t public.country_safety_config -t private.dating_calling_codes -t public.dating_algorithm_configs attune_spec3a | psql -X -q -d w5race > /dev/null 2>&1
bash scripts/concurrency/dating_kill_switch_races.sh w5race > $D/race_T4.txt 2>&1; grep -c '^PASS' $D/race_T4.txt; grep -v '^PASS' $D/race_T4.txt; tail -1 $D/race_T4.txt
dropdb w5race
```

Expected: `dating_mode_contracts.sql: 10 edit(s) …`, `dating_rls_canary.sql: 1 edit(s) …`, `dating_v2_setup_contracts.sql: 3 edit(s) …`, `dating_kill_switch_races.sh: 1 edit(s) …`; `160 PASS, 14 FAIL`; `same-fails`; `31`; then only `PASS  simultaneous mutual interest makes one match (deadlocks detected and retried: 0)`.

- [ ] **Step 6: The mutants (§7.5 18, 19; the rules)**

Create `$D/mut_T4.py` with exactly:

```python
# Spec 2 W5b Task 4 mutants (mutate.py on 20261119110000_dating_v2_today.sql):
# each must make dating_v2_matching_contracts.sql fail.
M = '-- Spec 2 W5b'
MUTS = {
  # Mutant 18 (§7.5): who the person would like to meet in the card.
  'm18_seeking_in_card': ("    'reasons', to_jsonb(p_intro.reasons),",
                          "    'reasons', to_jsonb(p_intro.reasons),\n    'seeking', private.dating_field_decrypt(v_s.seeking_enc) -> 'seeking',"),
  'm18_hidden_faith_shown': ("  IF v_p.faith_visible THEN\n    v_faith := private.dating_field_decrypt(v_s.faith_enc);",
                             "  IF true THEN\n    v_faith := private.dating_field_decrypt(v_s.faith_enc);"),
  # Mutant 19 (§7.5): same_faith while one side hides faith (W5a's function).
  'm19_same_faith_hidden': ('LIVE', ('private.dating_reasons(private.dating_gen_person,private.dating_gen_person)', [
      ("CASE WHEN a.faith_visible AND b.faith_visible AND a.faith = b.faith", "CASE WHEN a.faith = b.faith")])),
  'card_after_mutual_photos': ("    'photos', CASE WHEN v_p.photos_after_mutual THEN '[]'::jsonb ELSE v_photos END,",
                               "    'photos', v_photos,"),
  'viewable_any': ("  SELECT coalesce(p_moderation = 'approved' AND p_csam = 'clear', false);", "  SELECT true;"),
  'keys_no_device': ("  IF coalesce(private.dating_device_state(p_viewer, p_device_hash) IN ('trusted', 'unbound'), false) IS NOT TRUE\n     OR (p_device_hash IS NULL AND EXISTS (SELECT 1 FROM public.dating_trusted_devices AS d WHERE d.user_id = p_viewer)) THEN",
                     "  IF false THEN"),
  'keys_before_mutual': ("       AND NOT (SELECT p.photos_after_mutual FROM public.dating_profiles AS p\n                 WHERE p.user_id = CASE WHEN x.user_low_id = p_viewer THEN x.user_high_id ELSE x.user_low_id END);",
                         ";"),
  'keys_no_flag': (" OR public.dating_flag_enabled('dating_profile_photos') IS NOT TRUE THEN", " THEN"),
  'act_device_late': ("  IF public.dating_require_trusted_device() IS NOT TRUE THEN\n    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');\n  END IF;\n  IF public.dating_eligibility(v_user, 'candidate') IS DISTINCT FROM 'eligible'\n     OR NOT EXISTS",
                      "  IF public.dating_eligibility(v_user, 'candidate') IS DISTINCT FROM 'eligible'\n     OR NOT EXISTS"),
  'act_rewinds': ("      IF v_mine IS NOT NULL THEN\n        -- No rewind (§3.4): the first answer stands.", "      IF false THEN\n        -- No rewind (§3.4): the first answer stands."),
  'act_absent_differs': ("      IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM private.dating_visible_introductions(v_user) AS x WHERE x.id = v_i.id) THEN",
                         "      IF NOT FOUND THEN\n        RETURN jsonb_build_object('ok', false, 'reason', 'not_found');\n      END IF;\n      IF NOT EXISTS (SELECT 1 FROM private.dating_visible_introductions(v_user) AS x WHERE x.id = v_i.id) THEN"),
  'act_unsafe_kept_open': ("          UPDATE public.dating_introductions SET state = 'invalidated' WHERE id = v_i.id;", "          NULL;"),
  'act_pushes': ("        IF v_match IS NOT NULL THEN\n          PERFORM private.bump_metric_internal('dating.mutual');",
                 "        IF v_match IS NOT NULL THEN\n          INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata) VALUES (v_user, 'immediate', now(), 'pending', '{\"type\": \"me_update\"}');\n          PERFORM private.bump_metric_internal('dating.mutual');"),
  'moment_both_sides': ("     SET low_moment_seen_at = CASE WHEN m.user_low_id = v_user THEN coalesce(m.low_moment_seen_at, now()) ELSE m.low_moment_seen_at END,\n         high_moment_seen_at = CASE WHEN m.user_high_id = v_user THEN coalesce(m.high_moment_seen_at, now()) ELSE m.high_moment_seen_at END",
                        "     SET low_moment_seen_at = now(), high_moment_seen_at = now()"),
  'moment_any_match': ('MULTI', [("   WHERE m.id = p_match_id AND v_user IN (m.user_low_id, m.user_high_id);", "   WHERE m.id = p_match_id;"),
                                  ("     SET low_moment_seen_at = CASE WHEN m.user_low_id = v_user THEN coalesce(m.low_moment_seen_at, now()) ELSE m.low_moment_seen_at END,\n         high_moment_seen_at = CASE WHEN m.user_high_id = v_user THEN coalesce(m.high_moment_seen_at, now()) ELSE m.high_moment_seen_at END",
                                   "     SET low_moment_seen_at = now(), high_moment_seen_at = now()")]),
  'family_invalidates': (f"  IF TG_TABLE_NAME = 'dating_profiles' THEN {M} (§3.4): not a filter input, nothing ends", "  IF false THEN"),
  'read_other_phone': ("  IF public.dating_require_trusted_device() IS NOT TRUE THEN\n    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');\n  END IF;\n  IF NOT EXISTS (SELECT 1 FROM public.dating_enrollments AS e WHERE e.user_id = v_user AND e.state = 'active')",
                       "  IF NOT EXISTS (SELECT 1 FROM public.dating_enrollments AS e WHERE e.user_id = v_user AND e.state = 'active')"),
  'waiting_as_today': ("    IF (CASE WHEN v_i.user_low_id = v_user THEN v_i.visible_from_low ELSE v_i.visible_from_high END) > now() - interval '24 hours' THEN",
                       "    IF true THEN"),
  'digest_ignores_toggle': ("     WHERE t.digest_push\n", "     WHERE true\n"),
  'digest_any_time': ("    CONTINUE WHEN v_drop > now();\n", ""),
  'digest_nothing_new': ("    CONTINUE WHEN NOT (\n", "    CONTINUE WHEN false AND NOT (\n"),
  'digest_no_key_raises': ("  IF public.app_setting('dating_push_key') IS NULL THEN\n    PERFORM private.bump_metric_internal('dating.digest.push_key_missing');\n    RETURN 0;\n  END IF;\n", ""),
}
```

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5
python3 -I $D/mutate.py supabase/migrations/20261119110000_dating_v2_today.sql supabase/tests/dating_v2_matching_contracts.sql $D/mut_T4.py $D/mut supabase/migrations/20261119110010_dating_v2_today_grants.sql > $D/mut_T4.txt 2>&1
grep -c 'CONTRACT VIOLATED' $D/mut_T4.txt; grep -v 'CONTRACT VIOLATED' $D/mut_T4.txt
```

Expected: `22`, nothing else. Among them: `m18_seeking_in_card: … the card carries seeking or a hidden value (mutant 18)`, `m19_same_faith_hidden: … a faith reason was cited while one side hides faith, or not when both show it (mutant 19)`, `act_device_late: … another phone's act answered {"ok": false, "reason": "not_eligible"} and left the introduction generated`, `act_absent_differs: … an introduction was answered before this side's drop, or the day did not say it is coming`, `keys_no_device: … photo keys were given to another phone (carry 12)`, `family_invalidates: … answering the family question asked it again or ended the introduction (invalidated)`, `digest_no_key_raises: … the digest raised without its push key (dating:push_key_missing)`.

- [ ] **Step 7: Record the tree**

Do not commit; record the tree in the report.

### Task 5: The `dating-photo-urls` edge function (§4.7, §7.3, §3.4 payload rules; carries 12–14; R-31)

**Files:**
- Create: `supabase/functions/dating-photo-urls/{handler.ts, index.ts, handler.test.ts}`, `$D/{denomut.py, edit_ci_T5.py, mut_T5.py}`
- Modify: `.github/workflows/tests.yml`, `supabase/config.toml`

**Interfaces:**
- Consumes: Task 4's `dating_photo_keys_for_viewer(p_viewer, p_kind, p_id, p_device_hash)`; `_shared/attune_auth.ts` (`requireUser`, `serviceRoleClient`, `jsonResponse`, `HttpError`), `_shared/error_code.ts`.
- Produces: `handlePhotoUrls(body, {userId, deviceHash}, {rpc, sign}) → {ok:true, photos:[{position, url}]} | {ok:false, reason}`, `deviceHashOf(header)` (equal to `dating-verification`'s), `SIGNED_URL_SECONDS = 60`.

- [ ] **Step 1: Write the failing tests**

Create `supabase/functions/dating-photo-urls/handler.test.ts` with exactly:

```typescript
// Spec 2 W5b (§4.7, §7.3; carries 12-14): dating-photo-urls. A viewer gets
// URLs only for the keys the service function allows, 60 seconds each,
// in position order; the phone's hash is passed on and a phone with no id
// is device_unavailable; refusals are fixed codes, a server error is busy;
// a storage key, a server's text or an error never leaves; nothing is
// logged; the hash matches dating-verification's.
import { deviceHashOf, handlePhotoUrls, type PhotoUrlDeps, SIGNED_URL_SECONDS } from "./handler.ts";
import { deviceHashOf as verificationHash } from "../dating-verification/handler.ts";

function eq(actual: unknown, expected: unknown, why = "") {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${why} expected ${e}, got ${a}`);
}

const ID = "11111111-2222-4333-8444-555555555555";
const HASH = "a".repeat(64);
const CALLER = { userId: "99999999-2222-4333-8444-555555555555", deviceHash: HASH };

interface Seen {
  rpc: Array<[string, Record<string, unknown>]>;
  signed: Array<[string[], number]>;
}

function deps(data: unknown, seen: Seen, opts: { rpcError?: boolean; signThrows?: boolean } = {}): PhotoUrlDeps {
  return {
    rpc: (fn, args) => {
      seen.rpc.push([fn, args]);
      return Promise.resolve(opts.rpcError ? { data: null, error: { code: "XX000", message: "server text" } } : { data, error: null });
    },
    sign: (keys, seconds) => {
      seen.signed.push([keys, seconds]);
      if (opts.signThrows) return Promise.reject(new Error("storage down: key " + keys[0]));
      return Promise.resolve(keys.map((k) => ({ path: k, signedUrl: `https://storage.test/sign/${k.length}?token=t` })));
    },
  };
}

const fresh = (): Seen => ({ rpc: [], signed: [] });

function quietly<T>(f: () => Promise<T>): Promise<T> {
  const original = { log: console.log, error: console.error, warn: console.warn, info: console.info };
  const said: unknown[] = [];
  console.log = console.error = console.warn = console.info = (...a: unknown[]) => said.push(a);
  return f().finally(() => {
    Object.assign(console, original);
    if (said.length > 0) throw new Error("the handler logged: " + JSON.stringify(said));
  });
}

Deno.test("a viewer gets 60-second URLs for exactly the allowed keys, in order; no key leaves", () =>
  quietly(async () => {
    const seen = fresh();
    const answer = await handlePhotoUrls({ kind: "introduction", id: ID }, CALLER, deps({
      ok: true,
      photos: [{ position: 2, key: "dating-photos/b.jpg" }, { position: 1, key: "dating-photos/a.jpg" }],
    }, seen));
    eq(seen.rpc, [["dating_photo_keys_for_viewer", { p_viewer: CALLER.userId, p_kind: "introduction", p_id: ID, p_device_hash: HASH }]]);
    eq(seen.signed, [[["dating-photos/b.jpg", "dating-photos/a.jpg"], 60]]);
    eq(SIGNED_URL_SECONDS, 60);
    if (!answer.ok) throw new Error("refused");
    eq(answer.photos.map((p) => p.position), [1, 2]);
    if (JSON.stringify(answer).includes("dating-photos/")) throw new Error("a storage key left the function");
  }));

Deno.test("a match reads its other member's photos the same way", () =>
  quietly(async () => {
    const seen = fresh();
    const answer = await handlePhotoUrls({ kind: "match", id: ID }, CALLER, deps({ ok: true, photos: [{ position: 1, key: "k1" }] }, seen));
    eq(seen.rpc[0][1].p_kind, "match");
    eq(answer.ok && answer.photos.length, 1);
  }));

Deno.test("no install id on the phone: device_unavailable, the database never asked (W4 I-4)", () =>
  quietly(async () => {
    const seen = fresh();
    eq(await handlePhotoUrls({ kind: "introduction", id: ID }, { ...CALLER, deviceHash: null }, deps({ ok: true, photos: [] }, seen)),
      { ok: false, reason: "device_unavailable" });
    eq(seen.rpc.length, 0);
  }));

Deno.test("refusals are fixed codes; a server error or an unknown answer is busy or unavailable, never its text", () =>
  quietly(async () => {
    eq(await handlePhotoUrls({ kind: "introduction", id: ID }, CALLER, deps({ ok: false, reason: "reverify_device" }, fresh())),
      { ok: false, reason: "reverify_device" });
    eq(await handlePhotoUrls({ kind: "introduction", id: ID }, CALLER, deps({ ok: false, reason: "photos_unavailable" }, fresh())),
      { ok: false, reason: "photos_unavailable" });
    eq(await handlePhotoUrls({ kind: "introduction", id: ID }, CALLER, deps({ ok: false, reason: "a server's own words" }, fresh())),
      { ok: false, reason: "photos_unavailable" });
    eq(await handlePhotoUrls({ kind: "introduction", id: ID }, CALLER, deps(null, fresh(), { rpcError: true })),
      { ok: false, reason: "busy" });
    const seen = fresh();
    eq(await handlePhotoUrls({ kind: "introduction", id: ID }, CALLER, deps({ ok: true, photos: [{ position: 1, key: "k" }] }, seen, { signThrows: true })),
      { ok: false, reason: "busy" });
  }));

Deno.test("no photos to sign: an empty list, Storage never asked", () =>
  quietly(async () => {
    const seen = fresh();
    eq(await handlePhotoUrls({ kind: "introduction", id: ID }, CALLER, deps({ ok: true, photos: [] }, seen)), { ok: true, photos: [] });
    eq(seen.signed.length, 0);
  }));

Deno.test("a malformed request is invalid before any call", () =>
  quietly(async () => {
    for (const body of [null, {}, { kind: "profile", id: ID }, { kind: "introduction", id: "not-a-uuid" }, { kind: "match", id: 7 }]) {
      const seen = fresh();
      eq(await handlePhotoUrls(body, CALLER, deps({ ok: true, photos: [] }, seen)), { ok: false, reason: "invalid" }, JSON.stringify(body));
      eq(seen.rpc.length, 0);
    }
  }));

Deno.test("the device hash is dating-verification's (one phone, one hash)", async () => {
  for (const h of ["0123456789abcdef0123456789abcdef", "nope", null]) {
    eq(await deviceHashOf(h), await verificationHash(h), String(h));
  }
});
```

```bash
cd supabase/functions && NO_COLOR=1 deno test --allow-read --allow-env --lock=../../.github/deno-w9.lock --frozen dating-photo-urls/handler.test.ts 2>&1 | grep -m1 -o "Cannot find module '.*dating-photo-urls/handler.ts'"; cd ../..
```

Expected: `Cannot find module 'file:///…/supabase/functions/dating-photo-urls/handler.ts'` (the type check stops the run).

- [ ] **Step 2: Write the function**

Create `supabase/functions/dating-photo-urls/handler.ts` with exactly:

```typescript
// supabase/functions/dating-photo-urls/handler.ts
// Spec 2 W5b (§3.4, §4.7; carries 12-14): short-lived photo URLs for the
// other person on an introduction or a match. The caller is the signed-in
// person; dating_photo_keys_for_viewer (the service role's) checks their
// phone first, then that the introduction is theirs to see now (or the
// match is active), that the other person hasn't kept photos for mutual
// interest, and lists only viewable photos (approved and cleared by the
// inline CSAM scan). Storage signs those keys for 60 seconds. The answer
// is {ok:true, photos:[{position, url}]} or {ok:false, reason} with a
// fixed code; a storage key, a server's text or an error is never sent and
// nothing is logged. No database call is open across the signing call.
export type RpcResult = { data: unknown; error: unknown };

export interface PhotoUrlDeps {
  rpc(fn: string, args: Record<string, unknown>): PromiseLike<RpcResult>;
  /// Signs [keys] for [seconds]; throws when Storage can't answer.
  sign(keys: string[], seconds: number): Promise<Array<{ path: string | null; signedUrl: string | null }>>;
}

export interface Caller {
  userId: string;
  deviceHash: string | null;
}

export type Answer =
  | { ok: true; photos: Array<{ position: number; url: string }> }
  | { ok: false; reason: string };

/// §3.4: signed URLs live 60 seconds.
export const SIGNED_URL_SECONDS = 60;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const REFUSALS: ReadonlySet<string> = new Set(["reverify_device", "photos_unavailable"]);

/// The x-attune-device header's hash (as dating-verification computes it):
/// sha256 hex of a 32-hex install id; anything else is no device.
export async function deviceHashOf(header: string | null): Promise<string | null> {
  if (header === null || !/^[0-9a-f]{32}$/.test(header)) return null;
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(header)));
  return Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("");
}

export async function handlePhotoUrls(body: unknown, caller: Caller, deps: PhotoUrlDeps): Promise<Answer> {
  const b = (body ?? {}) as Record<string, unknown>;
  const kind = b.kind;
  const id = b.id;
  if ((kind !== "introduction" && kind !== "match") || typeof id !== "string" || !UUID.test(id)) {
    return { ok: false, reason: "invalid" };
  }
  // W4 fix round 1 (I-4): a phone with no install id can't be checked.
  if (caller.deviceHash === null) return { ok: false, reason: "device_unavailable" };
  let res: RpcResult;
  try {
    res = await deps.rpc("dating_photo_keys_for_viewer", {
      p_viewer: caller.userId,
      p_kind: kind,
      p_id: id,
      p_device_hash: caller.deviceHash,
    });
  } catch {
    return { ok: false, reason: "busy" };
  }
  if (res.error) return { ok: false, reason: "busy" };
  const d = res.data as { ok?: unknown; reason?: unknown; photos?: unknown } | null;
  if (d === null || typeof d !== "object") return { ok: false, reason: "busy" };
  if (d.ok !== true) {
    return { ok: false, reason: typeof d.reason === "string" && REFUSALS.has(d.reason) ? d.reason : "photos_unavailable" };
  }
  const listed = Array.isArray(d.photos) ? d.photos : [];
  const keys = new Map<string, number>();
  for (const p of listed) {
    const x = p as { position?: unknown; key?: unknown };
    if (typeof x.key === "string" && typeof x.position === "number") keys.set(x.key, x.position);
  }
  if (keys.size === 0) return { ok: true, photos: [] };
  let signed: Array<{ path: string | null; signedUrl: string | null }>;
  try {
    signed = await deps.sign([...keys.keys()], SIGNED_URL_SECONDS);
  } catch {
    return { ok: false, reason: "busy" };
  }
  const photos: Array<{ position: number; url: string }> = [];
  for (const s of signed) {
    const position = s.path === null ? undefined : keys.get(s.path);
    if (position !== undefined && typeof s.signedUrl === "string" && s.signedUrl.length > 0) {
      photos.push({ position, url: s.signedUrl });
    }
  }
  photos.sort((a, b) => a.position - b.position);
  return { ok: true, photos };
}
```

Create `supabase/functions/dating-photo-urls/index.ts` with exactly:

```typescript
// supabase/functions/dating-photo-urls/index.ts
// Spec 2 W5b (§4.7): the wiring for handler.ts. The caller is the signed-in
// person (their JWT); the keys come from the service function, Storage
// signs them for 60 seconds. The x-attune-device header (sent only by the
// Dating-scoped client) is hashed here and only the hash is passed on.
// Only an error's code is ever logged.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { HttpError, jsonResponse, requireUser, serviceRoleClient } from "../_shared/attune_auth.ts";
import { errorCode } from "../_shared/error_code.ts";
import { deviceHashOf, handlePhotoUrls } from "./handler.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  if (req.method !== "POST") return jsonResponse({ ok: false, reason: "invalid" }, 405);
  try {
    const user = await requireUser(req);
    const supabase = serviceRoleClient();
    const body = await req.json().catch(() => ({}));
    const answer = await handlePhotoUrls(body, {
      userId: user.id,
      deviceHash: await deviceHashOf(req.headers.get("x-attune-device")),
    }, {
      rpc: (fn, args) => supabase.rpc(fn, args),
      sign: async (keys, seconds) => {
        const { data, error } = await supabase.storage.from("dating-profile-photos").createSignedUrls(keys, seconds);
        if (error || !data) throw new Error("storage_unavailable");
        return data.map((d) => ({ path: d.path ?? null, signedUrl: d.signedUrl ?? null }));
      },
    });
    return jsonResponse(answer);
  } catch (error) {
    if (error instanceof HttpError) return jsonResponse({ ok: false, reason: "unauthorized" }, error.status);
    console.error("dating-photo-urls failed:", errorCode(error));
    return jsonResponse({ ok: false, reason: "busy" }, 500);
  }
});
```

Create `$D/edit_ci_T5.py` with exactly:

```python
# Spec 2 W5b Task 5: CI runs the dating-photo-urls tests and type-checks
# its wiring under the frozen lock; the function needs a signed-in caller.
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anchor import edit

edit('.github/workflows/tests.yml', [
  (" dating-verification/handler.test.ts _shared/age_assurance/providers.test.ts\n",
   " dating-verification/handler.test.ts _shared/age_assurance/providers.test.ts dating-photo-urls/handler.test.ts\n"),
  ("        run: deno check --lock=../../.github/deno-w9.lock --frozen dating-verification/index.ts\n",
   "        run: deno check --lock=../../.github/deno-w9.lock --frozen dating-verification/index.ts dating-photo-urls/index.ts\n"),
], 'CI: dating-photo-urls')
edit('supabase/config.toml', [
  ("[functions.dating-verification]\nverify_jwt = true\n",
   "[functions.dating-verification]\nverify_jwt = true\n\n[functions.dating-photo-urls]\nverify_jwt = true\n"),
], 'config: dating-photo-urls needs a JWT')
```

- [ ] **Step 3: Run the tests, CI's line and the type check**

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5
python3 -I $D/edit_ci_T5.py
cd supabase/functions
deno test --allow-read --allow-env --lock=../../.github/deno-w9.lock --frozen dating-photo-urls/handler.test.ts 2>&1 | grep -E 'passed|failed' | tail -1
deno test --allow-read --allow-env --lock=../../.github/deno-w9.lock --frozen _shared/unicode_normaliser.test.ts _shared/writer_crisis_check.test.ts _shared/healing_ai_gate.test.ts process-dating-photo/handler.test.ts process-dating-photo/worker.test.ts _shared/google_vision.test.ts analyse-journal-entry/ generate-healing-portrait/ generate-healing-post-mortem/ process-scheduled-notifications/privacy_allowlist.test.ts dating-verification/handler.test.ts _shared/age_assurance/providers.test.ts dating-photo-urls/handler.test.ts 2>&1 | grep -E 'passed|failed' | tail -1
deno check --lock=../../.github/deno-w9.lock --frozen dating-verification/index.ts dating-photo-urls/index.ts 2>&1 | tail -1
cd ../..
```

Expected: `.github/workflows/tests.yml: 2 edit(s) …`, `supabase/config.toml: 1 edit(s) …`; `ok | 7 passed | 0 failed`; `ok | 200 passed | 0 failed`; nothing from `deno check` (no error; a first, uncached check prints only its `Check …` lines).

- [ ] **Step 4: The mutants**

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5; cp .superpowers/sdd/2026-11-09-spec2-w4/denomut.py $D/denomut.py
```

Create `$D/mut_T5.py` with exactly:

```python
# Spec 2 W5b Task 5: dating-photo-urls Deno mutants (denomut.py).
H = 'supabase/functions/dating-photo-urls/handler.ts'
TESTS = ['dating-photo-urls/handler.test.ts']
MUTS = {
  'url_lives_longer': (H, [("export const SIGNED_URL_SECONDS = 60;", "export const SIGNED_URL_SECONDS = 3600;")]),
  'key_leaves': (H, [("      photos.push({ position, url: s.signedUrl });", "      photos.push({ position, url: s.signedUrl + '#' + s.path });")]),
  'no_device_asks_anyway': (H, [('  if (caller.deviceHash === null) return { ok: false, reason: "device_unavailable" };\n', "")]),
  'hash_not_passed': (H, [("      p_device_hash: caller.deviceHash,", "      p_device_hash: null,")]),
  'server_text_passed': (H, [('    return { ok: false, reason: typeof d.reason === "string" && REFUSALS.has(d.reason) ? d.reason : "photos_unavailable" };',
                              '    return { ok: false, reason: typeof d.reason === "string" ? d.reason : "photos_unavailable" };')]),
  'sign_outage_partial': (H, [('  } catch {\n    return { ok: false, reason: "busy" };\n  }\n  const photos', '  } catch {\n    return { ok: true, photos: [] };\n  }\n  const photos')]),
  'unordered': (H, [("  photos.sort((a, b) => a.position - b.position);\n", "")]),
  'kind_unchecked': (H, [('  if ((kind !== "introduction" && kind !== "match") || typeof id !== "string" || !UUID.test(id)) {',
                          '  if (typeof id !== "string") {')]),
  'logs_error': (H, [('  } catch {\n    return { ok: false, reason: "busy" };\n  }\n  if (res.error)', '  } catch (e) {\n    console.error(e);\n    return { ok: false, reason: "busy" };\n  }\n  if (res.error) console.error(res.error);\n  if (res.error)')]),
}
```

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5; python3 -I $D/denomut.py $D/mut_T5.py 2>&1 | tail -1
```

Expected: `9/9 killed` (e.g. `url_lives_longer: KILLED  a viewer gets 60-second URLs for exactly the allowed keys, in order; no key leaves`, `logs_error: KILLED  refusals are fixed codes; …`).

- [ ] **Step 5: Record the tree**

Do not commit; record the tree in the report.

### Task 6: The app's Today data, the photo memory and its wipe, the reasons, captions on the card (§3.4, §5.8, §6.7, §4.10 the v1 model replaced; D8, C-5; carries 13, 14; R-10, R-13)

**Files:**
- Create: `lib/features/dating/today/{dating_today.dart, dating_today_repository.dart, dating_photo_memory.dart, dating_today_providers.dart, dating_reasons.dart}`, `test/features/dating/support/dating_today_fakes.dart`, `test/features/dating/today/dating_today_data_test.dart`, `test/architecture/dating_v1_matching_gone_test.dart`, `$D/{edit_T6.py, arb_fragment_T6.txt, mut_T6.py}`
- Modify: `lib/features/dating/card/dating_card.dart`, `lib/features/dating/dating_device_wipes.dart`, `lib/i10n/app_en.arb` + generated
- Delete: `lib/features/dating/data/models/dating_introduction.dart` (the v1 band model; nothing imports it)

**Interfaces:**
- Consumes: Task 4's RPC answers; Task 5's `dating-photo-urls`; W3's `DatingCard`, `DatingCardView`, `datingListName`, `datingWrite`, `DatingRpc`, `datingRpcProvider`, `datingSupabaseClientProvider`; Spec 1's `DeviceWipeRegistry`.
- Produces: the app interfaces under "Interfaces this plan produces" for `dating_today*`, `dating_photo_memory`, `dating_reasons`; `DatingCard.captions`; test fakes `FakeDatingToday`, `datingCardJson(id, over)`, `datingTodayJson(over)`, `datingTodayOverrides(fake)`, `datingFetched`, `datingTestPng`.

- [ ] **Step 1: The copy**

Create `$D/arb_fragment_T6.txt` with exactly:

```text
  "dating_cardWhyTitle": "Why you two were introduced",
  "@dating_cardWhyTitle": {"description": "Spec 2 §3.4 the introduction card's reasons heading."},
  "dating_cardChemistry": "Attune can't predict chemistry; meeting is how you find out.",
  "@dating_cardChemistry": {"description": "Spec 2 §3.4, §5.8: always after the reasons."},
  "dating_reasonMarriageSoon": "You both said marriage, in the next year or two.",
  "@dating_reasonMarriageSoon": {"description": "Spec 2 §5.8 same_intention_timeline (within_two_years); the phrase as the card's (§3.4)."},
  "dating_reasonMarriageFew": "You both said marriage, in a few years.",
  "@dating_reasonMarriageFew": {"description": "Spec 2 §5.8 same_intention_timeline (few_years); the phrase as the card's (§3.4)."},
  "dating_reasonMarriageNone": "You both said marriage, with no set time.",
  "@dating_reasonMarriageNone": {"description": "Spec 2 §5.8 same_intention_timeline (no_set_time); the phrase as the card's (§3.4)."},
  "dating_reasonSameMarriage": "You're both looking for marriage.",
  "@dating_reasonSameMarriage": {"description": "Spec 2 §5.8 same_intention (marriage)."},
  "dating_reasonSameCommitted": "You're both looking for a committed relationship.",
  "@dating_reasonSameCommitted": {"description": "Spec 2 §5.8 same_intention (committed)."},
  "dating_reasonSameCompanionship": "You're both looking for companionship, at a comfortable pace.",
  "@dating_reasonSameCompanionship": {"description": "Spec 2 §5.8 same_intention (companionship; the card's phrase, §3.4)."},
  "dating_reasonSameNotSure": "You're both still working out what you're looking for.",
  "@dating_reasonSameNotSure": {"description": "Spec 2 §5.8 same_intention (not_sure). Plan copy: 'looking for not sure yet' doesn't read."},
  "dating_reasonCompatible": "You both want something committed.",
  "@dating_reasonCompatible": {"description": "Spec 2 §5.8 compatible_intention."},
  "dating_reasonChildrenYes": "You both want children.",
  "@dating_reasonChildrenYes": {"description": "Spec 2 §5.8 children_want_yes."},
  "dating_reasonChildrenNo": "Neither of you wants children.",
  "@dating_reasonChildrenNo": {"description": "Spec 2 §5.8 children_want_no."},
  "dating_reasonChildrenHave": "You both have children.",
  "@dating_reasonChildrenHave": {"description": "Spec 2 §5.8 children_have_both."},
  "dating_reasonSameFaith": "You're both {faith}.",
  "@dating_reasonSameFaith": {"description": "Spec 2 §5.8 same_faith (only when both show faith).", "placeholders": {"faith": {"type": "String"}}},
  "dating_reasonFaithMatters": "Faith matters a lot to you both.",
  "@dating_reasonFaithMatters": {"description": "Spec 2 §5.8 faith_matters (only when both show faith)."},
  "dating_reasonFamilyEarly": "You both want family involved early.",
  "@dating_reasonFamilyEarly": {"description": "Spec 2 §5.8 family_same (early)."},
  "dating_reasonFamilyWhenSerious": "You both want family involved once it's serious.",
  "@dating_reasonFamilyWhenSerious": {"description": "Spec 2 §5.8 family_same (when_serious)."},
  "dating_reasonFamilyOwn": "You'd both make the decision yourselves first.",
  "@dating_reasonFamilyOwn": {"description": "Spec 2 §5.8 family_same (our_decision)."},
  "dating_reasonSamePlace": "You're both in {place}.",
  "@dating_reasonSamePlace": {"description": "Spec 2 §5.8 same_side / same_region.", "placeholders": {"place": {"type": "String"}}},
  "dating_reasonAcrossBorders": "You're both open to meeting across borders.",
  "@dating_reasonAcrossBorders": {"description": "Spec 2 §5.8: across borders, when nothing else applies."}
```

```bash
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py .superpowers/sdd/2026-11-19-spec2-w5/arb_fragment_T6.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package > /dev/null; echo gen=$?
```

Expected: `added 20 keys`; `gen=0`.

- [ ] **Step 2: Write the failing tests**

Create `test/features/dating/support/dating_today_fakes.dart` with exactly:

```dart
// Spec 2 W5b: Today faked for widget tests. Every answer is the test's;
// every call is recorded; a read can be held open (D8 tests).
import 'dart:async';
import 'dart:convert';

import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/features/dating/today/dating_today_providers.dart';
import 'package:attune/features/dating/today/dating_today_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A card as the server sends it (§3.4), [over] on top.
Map<String, Object?> datingCardJson(
  String id, [
  Map<String, Object?> over = const {},
]) => {
  'id': id,
  'display_name': 'Kofi',
  'age': 31,
  'region_name_key': 'dating_region_gh_aa',
  'intention': 'committed',
  'children_have': false,
  'children_want': 'yes',
  'prompts': [
    {
      'prompt_id': 'perfect_sunday',
      'answer': 'Church, then jollof with my cousins.',
    },
  ],
  'reasons': ['same_intention', 'children_want_yes', 'same_region'],
  'photos_after_mutual': false,
  'photos': [
    {'id': '$id-p1', 'position': 1, 'caption': 'At the beach in Busua'},
    {'id': '$id-p2', 'position': 2, 'caption': null},
  ],
  'acted': null,
  ...over,
};

Map<String, Object?> datingTodayJson([Map<String, Object?> over = const {}]) =>
    {
      'ok': true,
      'today_state': 'delivered',
      'drop_at': null,
      'region_name_key': 'dating_region_gh_aa',
      'cards': [datingCardJson('i1')],
      'waiting': <Object?>[],
      'moments': <Object?>[],
      'family_question': false,
      'quiet_note': false,
      'data_saver': false,
      'widen': {'min_age': 25, 'max_age': 40, 'scope': 'region'},
      ...over,
    };

class FakeDatingToday implements DatingTodayGateway {
  FakeDatingToday({Map<String, Object?>? today})
    : json = today ?? datingTodayJson();

  Map<String, Object?> json;
  Completer<DatingToday>? hold;
  DatingActAnswer Function(String id, String action) answer =
      (id, action) => DatingActAnswer(ok: true, action: action);
  final acts = <(String key, String id, String action)>[];
  final seen = <String>[];
  final notes = <String>[];
  final families = <String?>[];
  final photoCalls = <(String, String)>[];
  List<DatingPhotoUrl>? urls = const [
    DatingPhotoUrl(1, 'https://s.test/1'),
    DatingPhotoUrl(2, 'https://s.test/2'),
  ];
  int reads = 0;

  @override
  Future<DatingToday> today() async {
    reads++;
    final h = hold;
    if (h != null) return h.future;
    return DatingToday.fromJson(json);
  }

  @override
  Future<DatingActAnswer> act(String key, String id, String action) async {
    acts.add((key, id, action));
    return answer(id, action);
  }

  @override
  Future<void> momentSeen(String matchId) async => seen.add(matchId);

  @override
  Future<DatingWrite> dismissNote(String note) async {
    notes.add(note);
    return const DatingWrite(ok: true);
  }

  @override
  Future<DatingWrite> saveFamily(String key, String? value) async {
    families.add(value);
    return const DatingWrite(ok: true);
  }

  @override
  Future<List<DatingPhotoUrl>?> photoUrls(String kind, String id) async {
    photoCalls.add((kind, id));
    return urls;
  }
}

/// A one-pixel PNG for every photo URL; the URLs fetched are recorded.
final datingFetched = <String>[];
List<Override> datingTodayOverrides(FakeDatingToday fake) => [
  datingTodayGatewayProvider.overrideWithValue(fake),
  datingPhotoFetchProvider.overrideWithValue((url) async {
    datingFetched.add(url);
    return datingTestPng;
  }),
];

/// A valid 1 x 1 PNG.
final datingTestPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);
```

Create `test/features/dating/today/dating_today_data_test.dart` with exactly:

```dart
// Spec 2 W5b (§3.4, §3.5, §5.8; D8, C-5; carries 13, 14): Today's answers
// read fail-closed; the repository sends exactly its RPCs and never a
// server's text; one Today entry per account; the photos in memory only
// (20 at most, emptied by Dating's wipe entry); the reasons are reviewed
// copy from ids only; a caption is its photo's spoken label.
import 'dart:async';
import 'dart:typed_data';

import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/dating/card/dating_card.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/dating_device_wipes.dart';
import 'package:attune/features/dating/today/dating_photo_memory.dart';
import 'package:attune/features/dating/today/dating_reasons.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/features/dating/today/dating_today_providers.dart';
import 'package:attune/features/dating/today/dating_today_repository.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../support/dating_today_fakes.dart';

void main() {
  final loc = AppLocalizationsEn();

  group('the answers, fail closed', () {
    test('anything but an ok object is unavailable, with its reason', () {
      for (final (raw, reason) in [
        (null, 'failed'),
        ('x', 'failed'),
        ({'ok': false, 'reason': 'reverify_device'}, 'reverify_device'),
        ({'ok': false, 'reason': 7}, 'failed'),
        // A refusal's other fields are never read.
        (
          {
            'ok': false,
            'today_state': 'delivered',
            'cards': [datingCardJson('x')],
          },
          'failed',
        ),
      ]) {
        final t = DatingToday.fromJson(raw);
        expect(t.ok, isFalse, reason: '$raw');
        expect(t.reason, reason, reason: '$raw');
        expect(t.cards, isEmpty, reason: '$raw');
      }
    });

    test(
      'every state; an unknown one is unavailable; malformed cards drop',
      () {
        for (final s in DatingTodayState.values) {
          expect(
            DatingToday.fromJson(
              datingTodayJson({'today_state': s.wire}),
            ).state,
            s,
          );
        }
        expect(
          DatingToday.fromJson(datingTodayJson({'today_state': 'party'})).state,
          DatingTodayState.unavailable,
        );
        final t = DatingToday.fromJson(
          datingTodayJson({
            'cards': [
              datingCardJson('a'),
              {'display_name': 'No id'},
              'x',
            ],
            'waiting': [datingCardJson('b')],
            'moments': [
              {'match_id': 'm1', 'display_name': 'Kofi'},
              {'match_id': 2},
            ],
            'family_question': true,
            'quiet_note': 'yes',
            'drop_at': '2026-11-20T19:00:00Z',
          }),
        );
        expect(t.cards.map((c) => c.id), ['a']);
        expect(t.waiting.map((c) => c.id), ['b']);
        expect(t.moments.single.name, 'Kofi');
        expect(t.familyQuestion, isTrue);
        expect(t.quietNote, isFalse);
        expect(t.dropAt, DateTime.utc(2026, 11, 20, 19));
        expect((t.minAge, t.maxAge, t.scope), (25, 40, 'region'));
      },
    );

    test('a card reads the viewer\'s own answer only, captions in order', () {
      final c =
          DatingIntroCard.fromJson(
            datingCardJson('a', {
              'acted': 'interested',
              'photos': [
                {'id': 'p2', 'position': 2, 'caption': 'Second'},
                {'id': 'p1', 'position': 1, 'caption': ''},
              ],
            }),
          )!;
      expect(c.acted, 'interested');
      expect(c.captions, [null, 'Second']);
      expect(c.card.captions, [null, 'Second']);
      expect(
        DatingIntroCard.fromJson(
          datingCardJson('b', {'acted': 'passed'}),
        )!.acted,
        isNull,
      );
      expect('$c', isNot(contains('Kofi')));
    });

    test('act: ok, matched, or a fixed refusal', () {
      expect(
        DatingActAnswer.fromJson({
          'ok': true,
          'action': 'interested',
          'matched': true,
        }).matched,
        isTrue,
      );
      expect(
        DatingActAnswer.fromJson({
          'ok': false,
          'reason': 'introduction_unavailable',
        }).reason,
        'introduction_unavailable',
      );
      expect(DatingActAnswer.fromJson('x').reason, 'failed');
    });
  });

  group('the repository', () {
    test('sends exactly its RPCs; busy and errors are fixed answers', () async {
      final calls = <(String, Map<String, dynamic>?)>[];
      Object? Function(String fn) reply =
          (fn) => {'ok': true, 'today_state': 'empty'};
      final repo = DatingTodayRepository(
        DatingRpc.withCall((fn, p) async {
          calls.add((fn, p));
          return reply(fn);
        }),
        (body) async => {
          'ok': true,
          'photos': [
            {'position': 1, 'url': 'https://s.test/a'},
            {'position': 'x'},
          ],
        },
      );
      expect((await repo.today()).state, DatingTodayState.empty);
      await repo.act('k' * 20, 'i1', 'interested');
      await repo.momentSeen('m1');
      await repo.dismissNote('family');
      await repo.saveFamily('f' * 20, 'early');
      expect(calls.map((c) => c.$1), [
        'get_my_dating_today',
        'act_on_dating_introduction',
        'mark_dating_match_moment_seen',
        'dismiss_dating_today_note',
        'save_dating_family_involvement',
      ]);
      expect(calls[1].$2, {
        'p_idempotency_key': 'k' * 20,
        'p_introduction_id': 'i1',
        'p_action': 'interested',
      });
      expect(calls[4].$2, {'p_idempotency_key': 'f' * 20, 'p_value': 'early'});
      expect((await repo.photoUrls('introduction', 'i1'))!.map((u) => u.url), [
        'https://s.test/a',
      ]);
      reply = (fn) => throw PostgrestException(message: 'dating:busy');
      expect((await repo.today()).reason, 'busy');
      expect((await repo.act('k' * 20, 'i1', 'passed')).reason, 'busy');
      reply =
          (fn) => throw PostgrestException(message: 'a server\'s own words');
      expect((await repo.today()).reason, 'failed');
      expect((await repo.act('k' * 20, 'i1', 'passed')).reason, 'failed');
      await repo.momentSeen('m1'); // never throws
    });

    test('photo URLs: a refusal or an error is null', () async {
      for (final answer in <Object?>[
        {
          'ok': false,
          'reason': 'reverify_device',
          'photos': [
            {'position': 1, 'url': 'https://s.test/x'},
          ],
        },
        'x',
        null,
      ]) {
        final repo = DatingTodayRepository(
          DatingRpc.withCall((fn, p) async => null),
          (body) async => answer,
        );
        expect(await repo.photoUrls('match', 'm1'), isNull, reason: '$answer');
      }
      final throws = DatingTodayRepository(
        DatingRpc.withCall((fn, p) async => null),
        (body) => throw StateError('down'),
      );
      expect(await throws.photoUrls('match', 'm1'), isNull);
    });
  });

  group('D8, memory only', () {
    test(
      'D8: the next account reads its own Today, nothing of the last',
      () async {
        final fake = FakeDatingToday();
        final account = StateProvider<String?>((ref) => 'ama');
        final c = ProviderContainer(
          overrides: [
            datingAccountProvider.overrideWith((ref) => ref.watch(account)),
            datingTodayGatewayProvider.overrideWithValue(fake),
          ],
        );
        addTearDown(c.dispose);
        final sub = c.listen(
          datingTodayProvider(c.read(datingAccountProvider)),
          (_, __) {},
        );
        expect(
          (await c.read(datingTodayProvider('ama').future)).cards,
          hasLength(1),
        );
        fake.hold = Completer<DatingToday>();
        c.read(account.notifier).state = 'kwame';
        final next = c.read(datingTodayProvider('kwame'));
        expect(next.isLoading, isTrue);
        expect(next.valueOrNull, isNull);
        fake.hold!.complete(
          DatingToday.fromJson(datingTodayJson({'cards': <Object?>[]})),
        );
        expect(
          (await c.read(datingTodayProvider('kwame').future)).cards,
          isEmpty,
        );
        sub.close();
      },
    );

    test(
      'at most 20 photos, the oldest out first; Dating\'s wipe empties them',
      () async {
        await DatingPhotoMemory.clear();
        for (var i = 0; i < 25; i++) {
          DatingPhotoMemory.put('k$i', Uint8List.fromList([i]));
        }
        expect(DatingPhotoMemory.length, 20);
        expect(DatingPhotoMemory.get('k4'), isNull);
        expect(DatingPhotoMemory.get('k5'), isNotNull);
        final registry = DeviceWipeRegistry();
        registerDatingDeviceWipes(registry);
        await registry.run(WipeMoment.quickExit);
        expect(DatingPhotoMemory.length, 0);
      },
    );

    test('photos load through memory: each URL fetched once', () async {
      await DatingPhotoMemory.clear();
      final fake = FakeDatingToday();
      final fetched = <String>[];
      Future<Uint8List?> fetch(String url) async {
        fetched.add(url);
        return Uint8List.fromList([1]);
      }

      expect(
        await loadDatingPhotos(fake, fetch, 'introduction', 'i1'),
        hasLength(2),
      );
      expect(
        await loadDatingPhotos(fake, fetch, 'introduction', 'i1'),
        hasLength(2),
      );
      expect(fetched, ['https://s.test/1', 'https://s.test/2']);
      fake.urls = null;
      expect(
        await loadDatingPhotos(fake, fetch, 'introduction', 'i2'),
        isEmpty,
      );
    });
  });

  group('the reasons (§5.8)', () {
    DatingIntroCard card(
      List<String> reasons, [
      Map<String, Object?> over = const {},
    ]) =>
        DatingIntroCard.fromJson(
          datingCardJson('a', {'reasons': reasons, ...over}),
        )!;

    test(
      'each id is its reviewed copy; at most three; unknown ids show nothing',
      () {
        expect(
          datingReasonLines(
            loc,
            card([
              'same_intention',
              'children_want_yes',
              'same_region',
              'compatible_intention',
            ]),
          ),
          [
            loc.dating_reasonSameCommitted,
            loc.dating_reasonChildrenYes,
            loc.dating_reasonSamePlace(loc.dating_region_gh_aa),
          ],
        );
        expect(datingReasonLines(loc, card(['made_up', 'faith_matters'])), [
          loc.dating_reasonFaithMatters,
        ]);
        expect(
          datingReasonLine(
            loc,
            'same_intention_timeline',
            card([], {
              'intention': 'marriage',
              'marriage_timeline': 'few_years',
            }),
          ),
          loc.dating_reasonMarriageFew,
        );
        expect(
          datingReasonLine(
            loc,
            'same_faith',
            card([], {
              'faith': {'faith': 'christian'},
            }),
          ),
          contains('Christian'),
        );
        expect(datingReasonLine(loc, 'same_faith', card([])), isNull);
        expect(datingReasonLine(loc, 'same_side', card([])), isNull);
        for (final (id, line) in [
          ('children_want_no', loc.dating_reasonChildrenNo),
          ('children_have_both', loc.dating_reasonChildrenHave),
          ('family_same_early', loc.dating_reasonFamilyEarly),
          ('family_same_when_serious', loc.dating_reasonFamilyWhenSerious),
          ('family_same_our_decision', loc.dating_reasonFamilyOwn),
          ('across_borders', loc.dating_reasonAcrossBorders),
        ]) {
          expect(datingReasonLine(loc, id, card([])), line, reason: id);
        }
      },
    );
  });

  testWidgets(
    'a caption is its photo\'s spoken label, never printed (carry 13)',
    (t) async {
      final c = DatingIntroCard.fromJson(datingCardJson('a'))!;
      final handle = t.ensureSemantics();
      await t.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: DatingCardView(
                card: c.card,
                photos: [Uint8List(0), Uint8List(0)],
              ),
            ),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('Photo 1 of 2. At the beach in Busua'),
        findsOneWidget,
      );
      await t.drag(find.byType(PageView), const Offset(-400, 0));
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('Photo 2 of 2'), findsOneWidget);
      expect(find.text('At the beach in Busua'), findsNothing);
      handle.dispose();
    },
  );
}
```

Create `test/architecture/dating_v1_matching_gone_test.dart` with exactly:

```dart
// Spec 2 W5 (§4.10 R12; carry 8): the v1 matching objects are gone from the
// app too. No Dart file under lib/ names a dropped server object or reads a
// v1 payload field, so nothing can call what W5a and W5b dropped.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no file under lib/ names a v1 matching object', () {
    final banned = RegExp(
      r'display_band|explanation_features|dating_feature_snapshots|'
      r'get_my_dating_matches|run_dating_candidate_generation|'
      r'generate_dating_candidates_for_user|dating_alignment|'
      r"'get_my_dating_introductions', \{'p_limit'|class DatingIntroduction\b",
    );
    final hits = <String>[];
    for (final f
        in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.contains('/generated/')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (banned.hasMatch(lines[i])) hits.add('${f.path}:${i + 1}');
      }
    }
    expect(hits, isEmpty);
  });
}
```

```bash
flutter test --no-pub test/features/dating/today/dating_today_data_test.dart 2>&1 | tr '\r' '\n' | grep -m1 -o "Error: Error when reading '[^']*'"
flutter test --no-pub test/architecture/dating_v1_matching_gone_test.dart 2>&1 | grep -E -m1 'dating_introduction.dart'
```

Expected: `Error: Error when reading 'lib/features/dating/today/dating_photo_memory.dart'` (the files don't exist yet); then `'lib/features/dating/data/models/dating_introduction.dart:5',` (the v1 model is still there).

- [ ] **Step 3: Write the data layer**

Create `lib/features/dating/today/dating_today.dart` with exactly:

```dart
// Spec 2 W5b (§3.4, §3.5, §5.6): Today as the server sends it. Every field
// is read defensively: an unknown state is unavailable, a malformed card is
// dropped, and nothing here holds a date but when the next introductions
// arrive (no countdown, no expiry: Fable M8). Memory only (D20).
import 'package:attune/features/dating/card/dating_card.dart';

enum DatingTodayState {
  beforeDrop('before_drop'),
  delivered('delivered'),
  empty('empty'),
  queueFull('queue_full'),
  pausedOpenChats('paused_open_chats'),
  coolOff('cool_off'),
  unavailable('unavailable');

  const DatingTodayState(this.wire);

  final String wire;

  static DatingTodayState fromWire(Object? value) => values.firstWhere(
    (s) => s.wire == value,
    orElse: () => DatingTodayState.unavailable,
  );
}

/// One introduction: the card, its reason ids, the photos' spoken labels
/// and the viewer's own answer (never the other person's).
class DatingIntroCard {
  const DatingIntroCard({
    required this.id,
    required this.card,
    this.reasons = const [],
    this.sideNameKey,
    this.captions = const [],
    this.acted,
  });

  final String id;
  final DatingCard card;
  final List<String> reasons;
  final String? sideNameKey;

  /// Each shown photo's caption, in card order (null when none).
  final List<String?> captions;

  /// 'interested' once the viewer said so; null before.
  final String? acted;

  static DatingIntroCard? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String) return null;
    final j = Map<String, dynamic>.from(raw);
    final photos =
        j['photos'] is List
            ? (j['photos'] as List).whereType<Map>().toList()
            : <Map>[];
    photos.sort(
      (a, b) => ((a['position'] as int?) ?? 0).compareTo(
        (b['position'] as int?) ?? 0,
      ),
    );
    return DatingIntroCard(
      id: j['id'] as String,
      card: DatingCard.fromJson(j),
      reasons: [
        if (j['reasons'] is List)
          for (final r in j['reasons'] as List)
            if (r is String) r,
      ],
      sideNameKey: j['side_name_key'] is String ? j['side_name_key'] : null,
      captions: [
        for (final p in photos)
          if (p['id'] is String)
            p['caption'] is String && (p['caption'] as String).isNotEmpty
                ? p['caption'] as String
                : null,
      ],
      acted: j['acted'] == 'interested' ? 'interested' : null,
    );
  }

  DatingIntroCard asInterested() => DatingIntroCard(
    id: id,
    card: card,
    reasons: reasons,
    sideNameKey: sideNameKey,
    captions: captions,
    acted: 'interested',
  );

  /// Never printed: the card is another person's answers.
  @override
  String toString() => 'DatingIntroCard(…)';
}

/// A match the person hasn't seen yet (§3.5).
class DatingMoment {
  const DatingMoment({required this.matchId, required this.name});

  final String matchId;
  final String name;

  @override
  String toString() => 'DatingMoment(…)';
}

/// get_my_dating_today(): `{ok, today_state, …}` or `{ok: false, reason}`.
class DatingToday {
  const DatingToday({
    this.ok = false,
    this.reason,
    this.state = DatingTodayState.unavailable,
    this.dropAt,
    this.regionNameKey,
    this.myName,
    this.cards = const [],
    this.waiting = const [],
    this.moments = const [],
    this.familyQuestion = false,
    this.quietNote = false,
    this.dataSaver = false,
    this.minAge,
    this.maxAge,
    this.scope,
  });

  static const failed = DatingToday(reason: 'failed');
  static const busy = DatingToday(reason: 'busy');

  final bool ok;
  final String? reason;
  final DatingTodayState state;

  /// When the next introductions arrive (before_drop, cool_off).
  final DateTime? dropAt;
  final String? regionNameKey;

  /// The person's own first name (the match moment's own avatar).
  final String? myName;
  final List<DatingIntroCard> cards;
  final List<DatingIntroCard> waiting;
  final List<DatingMoment> moments;
  final bool familyQuestion;
  final bool quietNote;
  final bool dataSaver;
  final int? minAge;
  final int? maxAge;
  final String? scope;

  factory DatingToday.fromJson(Object? raw) {
    if (raw is! Map) return failed;
    if (raw['ok'] != true) {
      final reason = raw['reason'];
      return DatingToday(reason: reason is String ? reason : 'failed');
    }
    List<DatingIntroCard> cards(Object? list) => [
      if (list is List)
        for (final c in list)
          if (DatingIntroCard.fromJson(c) case final card?) card,
    ];
    final widen = raw['widen'] is Map ? raw['widen'] as Map : const {};
    final drop = raw['drop_at'];
    return DatingToday(
      ok: true,
      state: DatingTodayState.fromWire(raw['today_state']),
      dropAt: drop is String ? DateTime.tryParse(drop) : null,
      regionNameKey:
          raw['region_name_key'] is String ? raw['region_name_key'] : null,
      myName: raw['my_name'] is String ? raw['my_name'] : null,
      cards: cards(raw['cards']),
      waiting: cards(raw['waiting']),
      moments: [
        if (raw['moments'] is List)
          for (final m in (raw['moments'] as List).whereType<Map>())
            if (m['match_id'] is String && m['display_name'] is String)
              DatingMoment(
                matchId: m['match_id'] as String,
                name: m['display_name'] as String,
              ),
      ],
      familyQuestion: raw['family_question'] == true,
      quietNote: raw['quiet_note'] == true,
      dataSaver: raw['data_saver'] == true,
      minAge: widen['min_age'] is int ? widen['min_age'] as int : null,
      maxAge: widen['max_age'] is int ? widen['max_age'] as int : null,
      scope: widen['scope'] is String ? widen['scope'] as String : null,
    );
  }

  @override
  String toString() => 'DatingToday(${state.wire})';
}

/// act_on_dating_introduction(): `{ok, action, matched}` or a refusal.
class DatingActAnswer {
  const DatingActAnswer({
    required this.ok,
    this.action,
    this.matched = false,
    this.reason,
  });

  static const busy = DatingActAnswer(ok: false, reason: 'busy');
  static const failed = DatingActAnswer(ok: false, reason: 'failed');

  final bool ok;
  final String? action;
  final bool matched;
  final String? reason;

  factory DatingActAnswer.fromJson(Object? raw) {
    if (raw is! Map) return failed;
    if (raw['ok'] != true) {
      final reason = raw['reason'];
      return DatingActAnswer(
        ok: false,
        reason: reason is String ? reason : 'failed',
      );
    }
    final action = raw['action'];
    return DatingActAnswer(
      ok: true,
      action: action is String ? action : null,
      matched: raw['matched'] == true,
    );
  }
}

/// One signed photo URL (dating-photo-urls): lives 60 seconds.
class DatingPhotoUrl {
  const DatingPhotoUrl(this.position, this.url);

  final int position;
  final String url;
}
```

Create `lib/features/dating/today/dating_today_repository.dart` with exactly:

```dart
// Spec 2 W5b (§3.4, §3.5, §4.4, §4.7): Today's calls. The reads, act and
// the marks go through the Dating RPC client (its device header); the
// photo URLs come from dating-photo-urls through the same Dating-scoped
// client. Every call is bounded; a failure answers failed or busy, never
// the error's text.
import 'dart:async';

import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef DatingPhotoUrlsInvoke =
    Future<Object?> Function(Map<String, Object?> body);

abstract class DatingTodayGateway {
  Future<DatingToday> today();

  /// 'interested' or 'passed' on introduction [id], under [key].
  Future<DatingActAnswer> act(String key, String id, String action);

  /// The match moment was shown on this side (best effort).
  Future<void> momentSeen(String matchId);

  /// 'family' or 'quiet': the Today note is not shown again.
  Future<DatingWrite> dismissNote(String note);

  /// The family question's answer (§3.4); null clears it.
  Future<DatingWrite> saveFamily(String key, String? value);

  /// 60-second URLs for the other person's photos on an introduction or
  /// a match; null when refused, busy or failed (the card shows its slots).
  Future<List<DatingPhotoUrl>?> photoUrls(String kind, String id);
}

class DatingTodayRepository implements DatingTodayGateway {
  DatingTodayRepository(this._rpc, this._invoke);

  /// Through the Dating-scoped client (its edge calls carry the device
  /// header, as its RPCs do).
  factory DatingTodayRepository.of(DatingRpc rpc, SupabaseClient c) =>
      DatingTodayRepository(
        rpc,
        (body) async =>
            (await c.functions.invoke('dating-photo-urls', body: body)).data,
      );

  final DatingRpc _rpc;
  final DatingPhotoUrlsInvoke _invoke;

  static const timeout = Duration(seconds: 30);

  @override
  Future<DatingToday> today() async {
    try {
      return DatingToday.fromJson(await _rpc.call('get_my_dating_today'));
    } on DatingBusy {
      return DatingToday.busy;
    } catch (_) {
      return DatingToday.failed;
    }
  }

  @override
  Future<DatingActAnswer> act(String key, String id, String action) async {
    try {
      return DatingActAnswer.fromJson(
        await _rpc.call('act_on_dating_introduction', {
          'p_idempotency_key': key,
          'p_introduction_id': id,
          'p_action': action,
        }),
      );
    } on DatingBusy {
      return DatingActAnswer.busy;
    } catch (_) {
      return DatingActAnswer.failed;
    }
  }

  @override
  Future<void> momentSeen(String matchId) async {
    try {
      await _rpc.call('mark_dating_match_moment_seen', {'p_match_id': matchId});
    } catch (_) {
      // Shown again next time: never worse than once more.
    }
  }

  @override
  Future<DatingWrite> dismissNote(String note) => datingWrite(
    () => _rpc.call('dismiss_dating_today_note', {'p_note': note}),
  );

  @override
  Future<DatingWrite> saveFamily(String key, String? value) => datingWrite(
    () => _rpc.call('save_dating_family_involvement', {
      'p_idempotency_key': key,
      'p_value': value,
    }),
  );

  @override
  Future<List<DatingPhotoUrl>?> photoUrls(String kind, String id) async {
    try {
      final raw = await _invoke({'kind': kind, 'id': id}).timeout(timeout);
      if (raw is! Map || raw['ok'] != true || raw['photos'] is! List) {
        return null;
      }
      return [
        for (final p in (raw['photos'] as List).whereType<Map>())
          if (p['position'] is int && p['url'] is String)
            DatingPhotoUrl(p['position'] as int, p['url'] as String),
      ];
    } catch (_) {
      return null;
    }
  }
}
```

Create `lib/features/dating/today/dating_photo_memory.dart` with exactly:

```dart
// Spec 2 W5b (§3.4 payload rules, §6.7, C-5): the other person's photos,
// as bytes, in memory only: at most 20 images, the oldest dropped first;
// cleared when Dating is left (Today's route closes), on quick exit and on
// sign-out (Dating's entry in Spec 1's device wipe registry). Never the
// disk, never the image cache's disk, never a URL kept past its use.
import 'dart:typed_data';

abstract final class DatingPhotoMemory {
  static const max = 20;
  // A map literal keeps insertion order: the first key is the oldest.
  static final _bytes = <String, Uint8List>{};

  static Uint8List? get(String key) {
    final b = _bytes.remove(key);
    if (b != null) _bytes[key] = b;
    return b;
  }

  static void put(String key, Uint8List bytes) {
    _bytes.remove(key);
    _bytes[key] = bytes;
    while (_bytes.length > max) {
      _bytes.remove(_bytes.keys.first);
    }
  }

  static int get length => _bytes.length;

  /// Async for Spec 1's wipe registry (it awaits each entry, bounded).
  static Future<void> clear() async => _bytes.clear();
}
```

Create `lib/features/dating/today/dating_today_providers.dart` with exactly:

```dart
// Spec 2 W5b (D8, C-5): Today, one entry per account, memory only; the
// photo bytes are fetched from their 60-second URLs (a seam tests
// replace) into DatingPhotoMemory.
import 'dart:async';
import 'dart:typed_data';

import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_supabase_client.dart';
import 'package:attune/features/dating/today/dating_photo_memory.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/features/dating/today/dating_today_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

final datingTodayGatewayProvider = Provider<DatingTodayGateway>(
  (ref) => DatingTodayRepository.of(
    ref.watch(datingRpcProvider),
    ref.watch(datingSupabaseClientProvider),
  ),
);

/// Today, one entry per account: the next account's entry starts as a
/// plain loading value, never holding the last one's cards (D8).
final datingTodayProvider = FutureProvider.autoDispose
    .family<DatingToday, String?>((ref, account) async {
      if (account == null) return DatingToday.failed;
      return ref.read(datingTodayGatewayProvider).today();
    });

/// One photo's bytes from its signed URL; null when it can't be read.
final datingPhotoFetchProvider = Provider<Future<Uint8List?> Function(String)>(
  (ref) => (url) async {
    try {
      final r = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      return r.statusCode == 200 ? r.bodyBytes : null;
    } catch (_) {
      return null;
    }
  },
);

/// The other person's photos on [kind] [id], in card order, through
/// [DatingPhotoMemory]; an empty list when none can be read.
Future<List<Uint8List>> loadDatingPhotos(
  DatingTodayGateway gateway,
  Future<Uint8List?> Function(String) fetch,
  String kind,
  String id,
) async {
  final urls = await gateway.photoUrls(kind, id);
  if (urls == null) return const [];
  final out = <Uint8List>[];
  for (final u in urls) {
    final key = '$kind:$id:${u.position}';
    final kept = DatingPhotoMemory.get(key);
    final bytes = kept ?? await fetch(u.url);
    if (bytes == null) {
      out.add(Uint8List(0));
      continue;
    }
    if (kept == null) DatingPhotoMemory.put(key, bytes);
    out.add(bytes);
  }
  return out;
}
```

Create `lib/features/dating/today/dating_reasons.dart` with exactly:

```dart
// Spec 2 W5b (§5.8; Fable M3): "Why you two were introduced". The server
// sends reason ids only; each is reviewed copy here, with the closing line
// always after. An id this app doesn't know, or one whose field the card
// doesn't carry, shows nothing (never free text).
import 'package:attune/features/dating/setup/dating_list_names.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/i10n/generated/app_localizations.dart';

String? datingReasonLine(AppLocalizations loc, String id, DatingIntroCard c) =>
    switch (id) {
      'same_intention_timeline' => switch (c.card.timeline) {
        'within_two_years' => loc.dating_reasonMarriageSoon,
        'few_years' => loc.dating_reasonMarriageFew,
        'no_set_time' => loc.dating_reasonMarriageNone,
        _ => null,
      },
      'same_intention' => switch (c.card.intention) {
        'marriage' => loc.dating_reasonSameMarriage,
        'committed' => loc.dating_reasonSameCommitted,
        'companionship' => loc.dating_reasonSameCompanionship,
        'not_sure' => loc.dating_reasonSameNotSure,
        _ => null,
      },
      'compatible_intention' => loc.dating_reasonCompatible,
      'children_want_yes' => loc.dating_reasonChildrenYes,
      'children_want_no' => loc.dating_reasonChildrenNo,
      'children_have_both' => loc.dating_reasonChildrenHave,
      'same_faith' => switch (_name(loc, 'dating_faith_', c.card.faith)) {
        final faith? => loc.dating_reasonSameFaith(faith),
        null => null,
      },
      'faith_matters' => loc.dating_reasonFaithMatters,
      'family_same_early' => loc.dating_reasonFamilyEarly,
      'family_same_when_serious' => loc.dating_reasonFamilyWhenSerious,
      'family_same_our_decision' => loc.dating_reasonFamilyOwn,
      'same_side' => switch (_name(loc, '', c.sideNameKey)) {
        final side? => loc.dating_reasonSamePlace(side),
        null => null,
      },
      'same_region' => switch (_name(loc, '', c.card.regionNameKey)) {
        final region? => loc.dating_reasonSamePlace(region),
        null => null,
      },
      'across_borders' => loc.dating_reasonAcrossBorders,
      _ => null,
    };

String? _name(AppLocalizations loc, String prefix, String? key) =>
    key == null ? null : datingListName(loc, '$prefix$key');

/// The reasons the card shows, in the server's order (at most three).
List<String> datingReasonLines(AppLocalizations loc, DatingIntroCard c) => [
  for (final id in c.reasons.take(3))
    if (datingReasonLine(loc, id, c) case final line?) line,
];
```

Create `$D/edit_T6.py` with exactly:

```python
# Spec 2 W5b Task 6: the W3 card speaks each photo's caption (§3.4
# accessibility; carry 13: a caption is the photo's spoken label on the
# other person's card, never printed there), and Dating's wipe entry also
# empties the photo memory on quick exit and sign-out (§3.4, §6.7).
# Formatter-style edits (the files are not formatted).
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anchor import edit

C = 'lib/features/dating/card/dating_card.dart'
edit(C, [
  ("""    this.photosAfterMutual = false,
    this.photoIds = const [],
  });
""", """    this.photosAfterMutual = false,
    this.photoIds = const [],
    this.captions = const [],
  });
"""),
  ("""  final bool photosAfterMutual;
  final List<String> photoIds;
""", """  final bool photosAfterMutual;
  final List<String> photoIds;

  /// Spec 2 W5b (carry 13): each photo's caption, in [photoIds] order,
  /// read as its label (null: none). Never printed on the card.
  final List<String?> captions;
"""),
  ("""      photoIds: [
        for (final p in photos)
          if (p['id'] is String) p['id'] as String,
      ],
    );
  }
}""", """      photoIds: [
        for (final p in photos)
          if (p['id'] is String) p['id'] as String,
      ],
      captions: [
        for (final p in photos)
          if (p['id'] is String)
            p['caption'] is String && (p['caption'] as String).isNotEmpty
                ? p['caption'] as String
                : null,
      ],
    );
  }
}"""),
  ("""        _Photos(count: card.photoIds.length, photos: photos),""",
   """        _Photos(
          count: card.photoIds.length,
          photos: photos,
          captions: card.captions,
        ),"""),
  ("""class _Photos extends StatefulWidget {
  const _Photos({required this.count, required this.photos});

  final int count;
  final List<Uint8List> photos;
""", """class _Photos extends StatefulWidget {
  const _Photos({
    required this.count,
    required this.photos,
    this.captions = const [],
  });

  final int count;
  final List<Uint8List> photos;
  final List<String?> captions;
"""),
  ("""                  Semantics(
                    image: true,
                    label: loc.dating_cardPhoto(i + 1, widget.count),""",
   """                  Semantics(
                    image: true,
                    label: [
                      loc.dating_cardPhoto(i + 1, widget.count),
                      if (i < widget.captions.length &&
                          widget.captions[i] != null)
                        widget.captions[i]!,
                    ].join('. '),"""),
], 'card: captions as photo labels')

edit('lib/features/dating/dating_device_wipes.dart', [
  ("""import 'package:attune/features/dating/lock/dating_unlock.dart';
""", """import 'package:attune/features/dating/lock/dating_unlock.dart';
import 'package:attune/features/dating/today/dating_photo_memory.dart';
"""),
  ("""      run: DatingSessionMemory.clear,
    ),
  );
}""", """      run: DatingSessionMemory.clear,
    ),
  );
  // Spec 2 W5b (§3.4, §6.7): the other people's photos held in memory.
  (registry ?? DeviceWipeRegistry.instance).register(
    const DeviceWipeEntry(
      id: 'spec2.dating_photos',
      moments: {WipeMoment.signOut, WipeMoment.quickExit},
      run: DatingPhotoMemory.clear,
    ),
  );
}"""),
], 'wipes: the photo memory')
```

- [ ] **Step 4: Apply, format the new files, run**

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5
python3 -I $D/edit_T6.py
rm lib/features/dating/data/models/dating_introduction.dart
dart format lib/features/dating/today/ test/features/dating/today/dating_today_data_test.dart test/features/dating/support/dating_today_fakes.dart test/architecture/dating_v1_matching_gone_test.dart | tail -1
flutter analyze --no-pub lib/features/dating test/features/dating test/architecture 2>&1 | tail -1
flutter test --no-pub test/features/dating/today/dating_today_data_test.dart test/architecture/dating_v1_matching_gone_test.dart 2>&1 | tr '\r' '\n' | grep -E '^[0-9:]+ \+[0-9]+.*(All tests passed|Some tests failed)' | tail -1
```

Expected: `lib/features/dating/card/dating_card.dart: 6 edit(s) …`, `lib/features/dating/dating_device_wipes.dart: 2 edit(s) …`; `Formatted 8 files (0 changed) …`; `No issues found! …`; `+12: All tests passed!` (11 + 1).

- [ ] **Step 5: The mutants**

Create `$D/mut_T6.py` with exactly:

```python
# Spec 2 W5b Task 6: Dart mutants (dmut.py). Each must turn a named test
# red; a COMPILE is a broken mutant, never a kill.
T = 'lib/features/dating/today/'
DATA = ['test/features/dating/today/dating_today_data_test.dart']
MUTS = {
  'photo_refusal_listed': (T + 'dating_today_repository.dart',
      "      if (raw is! Map || raw['ok'] != true || raw['photos'] is! List) {",
      "      if (raw is! Map || raw['photos'] is! List) {", DATA),
  'memory_unbounded': (T + 'dating_photo_memory.dart', "    while (_bytes.length > max) {", "    while (false) {", DATA),
  'wipe_forgets_photos': ('lib/features/dating/dating_device_wipes.dart',
      "      run: DatingPhotoMemory.clear,", "      run: DatingSessionMemory.clear,", DATA),
  'reason_free_text': (T + 'dating_reasons.dart', "      'across_borders' => loc.dating_reasonAcrossBorders,\n      _ => null,",
      "      'across_borders' => loc.dating_reasonAcrossBorders,\n      _ => id,", DATA),
  'acted_any': (T + 'dating_today.dart', "      acted: j['acted'] == 'interested' ? 'interested' : null,",
      "      acted: j['acted'] is String ? j['acted'] as String : null,", DATA),
  'caption_unspoken': ('lib/features/dating/card/dating_card.dart',
      "                      if (i < widget.captions.length &&", "                      if (false &&", DATA),
}
```

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5; python3 -I $D/dmut.py $D/mut_T6.py 2>&1 | tail -1
```

Expected: `6/6 killed` (e.g. `memory_unbounded: KILLED  Expected: <20>`, `wipe_forgets_photos: KILLED  Expected: <0>`, `reason_free_text: KILLED  Expected: ['Faith matters a lot to you both.']`).

- [ ] **Step 6: Record the tree**

Do not commit; record the tree in the report.

### Task 7: Today, the match moment, Widen, the family question, the quiet note, the section's way in, the manual, and the W5b gate (§3.1, §3.4, §3.5, §3.15 Today and Match moment, §5.6, §7.4; D8; carry 15; R-11, R-12, R-21, R-22, R-32–R-34)

**Files:**
- Create: `lib/features/dating/today/{today_screen.dart, match_moment_screen.dart}`, `test/features/dating/today/today_screen_test.dart` and `test/features/dating/today/goldens/{today_delivered,today_empty,match_moment}.{scale1.0,scale1.3,scale2.0,rtl}.png`, `$D/{edit_T7.py, edit_T7_docs.py, arb_fragment_T7.txt, mut_T7.py}`
- Modify: `lib/features/dating/routes/dating_routes.dart`, `lib/features/dating/routes/dating_setup_steps.dart`, `lib/features/dating/section/dating_section.dart`, `test/architecture/text_scale_routes_test.dart`, `test/features/dating/routes/dating_routes_test.dart` (its C-1 guard pumps every Dating route, Today and the moment now among them, so it passes Today's fake), `lib/app/documentations/user_manual/data/dating_mode_docs.dart`, the ARB

**Interfaces:**
- Consumes: Task 6's data layer and fakes; W3's `pumpDatingShell`, `datingShellOverrides`, `DatingCardView`, `datingRoute()`, `datingSheetSettings`, `DatingSheetTracker`; W4's `DatingReverifyLine`.
- Produces: `/dating/today` (`datingToday`) and `/dating/match/:id` (`datingMatch`, `extra: (DatingMoment, String? myName)`); `showDatingWidenSheet(context, today)` (Task 10 adds its third row); `kDatingChatReady` (W6a flips it, Ruling R-11).

- [ ] **Step 1: The copy**

Create `$D/arb_fragment_T7.txt` with exactly:

```text
  "dating_todayTitle": "Today",
  "@dating_todayTitle": {"description": "Spec 2 §3.4 Today's title (/dating/today). Plan copy."},
  "dating_todayBeforeDrop": "Your introductions arrive at {time}.",
  "@dating_todayBeforeDrop": {"description": "Spec 2 §3.4 today_state before_drop.", "placeholders": {"time": {"type": "String"}}},
  "dating_todayEmpty": "No good fit today. Attune is still small in {region}. We'll introduce you when there's a good fit.",
  "@dating_todayEmpty": {"description": "Spec 2 §3.4 today_state empty.", "placeholders": {"region": {"type": "String"}}},
  "dating_todayEmptyNoRegion": "No good fit today. We'll introduce you when there's a good fit.",
  "@dating_todayEmptyNoRegion": {"description": "Spec 2 §3.4 today_state empty when the region's name can't be shown. Plan copy."},
  "dating_todayQueueFull": "You have introductions waiting. New ones arrive after you've looked at these.",
  "@dating_todayQueueFull": {"description": "Spec 2 §3.4 today_state queue_full."},
  "dating_todayPausedChats": "You have 3 conversations going. New introductions start again when one ends or you meet.",
  "@dating_todayPausedChats": {"description": "Spec 2 §3.4 today_state paused_open_chats."},
  "dating_todayWaiting": "Still waiting for you",
  "@dating_todayWaiting": {"description": "Spec 2 §3.4 introductions from earlier days (no dates, no countdown)."},
  "dating_todayWiden": "Widen who I meet",
  "@dating_todayWiden": {"description": "Spec 2 §3.4, §5.6 the Widen sheet's button and title."},
  "dating_widenAges": "Ages: {min}–{max}",
  "@dating_widenAges": {"description": "Spec 2 §3.4 Widen sheet row.", "placeholders": {"min": {"type": "int"}, "max": {"type": "int"}}},
  "dating_widenHowFar": "How far: {scope}",
  "@dating_widenHowFar": {"description": "Spec 2 §3.4 Widen sheet row; scope is My side / My region / Anywhere in {country}.", "placeholders": {"scope": {"type": "String"}}},
  "dating_widenCountry": "Anywhere in my country",
  "@dating_widenCountry": {"description": "Spec 2 §3.4 Widen sheet: the country scope when the country's name isn't on the card. Plan copy."},
  "dating_cardInterested": "Interested",
  "@dating_cardInterested": {"description": "Spec 2 §3.4 the card's filled action."},
  "dating_cardNotForMe": "Not for me",
  "@dating_cardNotForMe": {"description": "Spec 2 §3.4 the card's outlined action."},
  "dating_cardNoted": "Noted. If {name} is interested too, you'll both see it here.",
  "@dating_cardNoted": {"description": "Spec 2 §3.4 after Interested.", "placeholders": {"name": {"type": "String"}}},
  "dating_cardNotForMeDone": "Not for me.",
  "@dating_cardNotForMeDone": {"description": "Spec 2 §3.4 the snackbar after Not for me (its action is Undo)."},
  "dating_cardGone": "This isn't available any more.",
  "@dating_cardGone": {"description": "Spec 2 §3.0, §3.15 an introduction gone meanwhile."},
  "dating_familyQuestion": "One more question, if you like: How involved would you like family to be?",
  "@dating_familyQuestion": {"description": "Spec 2 §3.4 the family question (once, after the first introduction)."},
  "dating_familyEarly": "Involved early",
  "@dating_familyEarly": {"description": "Spec 2 §3.4 family question option."},
  "dating_familyWhenSerious": "Involved once it's serious",
  "@dating_familyWhenSerious": {"description": "Spec 2 §3.4 family question option."},
  "dating_familyOwn": "Our decision first",
  "@dating_familyOwn": {"description": "Spec 2 §3.4 family question option."},
  "dating_familySkip": "Skip",
  "@dating_familySkip": {"description": "Spec 2 §3.4 family question: skip (never asked again)."},
  "dating_quietNote": "It's quiet in {region} right now. Widening your ages or area can help, or you can pause and come back later.",
  "@dating_quietNote": {"description": "Spec 2 §5.6, once after 14 days without introductions.", "placeholders": {"region": {"type": "String"}}},
  "dating_momentTitle": "You and {name} are both interested.",
  "@dating_momentTitle": {"description": "Spec 2 §3.5 the match moment (once per side).", "placeholders": {"name": {"type": "String"}}},
  "dating_momentBody": "There's no rush. Say hello when you're ready.",
  "@dating_momentBody": {"description": "Spec 2 §3.5 the match moment."},
  "dating_momentSayHello": "Say hello",
  "@dating_momentSayHello": {"description": "Spec 2 §3.5 opens the conversation (shown once W6a's chat exists)."},
  "dating_momentLater": "Later",
  "@dating_momentLater": {"description": "Spec 2 §3.5 back to Today."},
  "dating_sectionOpenToday": "Open Today",
  "@dating_sectionOpenToday": {"description": "Spec 2 §3.1 active: the Dating section's way to Today (§3.4). Plan copy."}
```

```bash
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py .superpowers/sdd/2026-11-19-spec2-w5/arb_fragment_T7.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package > /dev/null; echo gen=$?
```

Expected: `added 27 keys` (Undo reuses the existing `dating_undo`); `gen=0`.

- [ ] **Step 2: Write the failing tests**

Create `test/features/dating/today/today_screen_test.dart` with exactly:

```dart
// Spec 2 W5b (§3.1, §3.4, §3.5, §3.15, §5.6, §7.4; D8): Today and the
// match moment. Each day state in its own words (never a date on a card);
// Interested says Noted once; Not for me collapses and holds the answer
// for its undo window (5 s, 20 s with a screen reader), sent when the
// window ends, at the next answer, or when the screen closes, and never as
// the next account; offline the actions wait; refusals are calm or the
// error line; data saver waits for a tap; the family question and the
// quiet note once; Widen opens the editors and comes back; the moment once,
// marked seen, no motion under reduce motion; the section opens Today.
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/dating/today/dating_photo_memory.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/features/dating/today/match_moment_screen.dart';
import 'package:attune/features/dating/today/today_screen.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_shell.dart';
import '../support/dating_today_fakes.dart';

/// tapInReach, then the frames its answer starts.
Future<void> tap(WidgetTester t, Finder finder) async {
  await tapInReach(t, finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  final loc = AppLocalizationsEn();

  setUp(() async {
    datingFetched.clear();
    await DatingPhotoMemory.clear();
  });

  Future<DatingShell> open(
    WidgetTester t,
    FakeDatingToday fake, {
    bool online = true,
    String initial = DatingPaths.today,
  }) => pumpDatingShell(
    t,
    initial: initial,
    online: online,
    overrides: datingTodayOverrides(fake),
  );

  group('the day', () {
    testWidgets('each state in its own words; no date on any card', (t) async {
      final at = DateTime.utc(2026, 11, 20, 19);
      for (final (state, line) in [
        ('before_drop', loc.dating_todayBeforeDrop('19:00')),
        ('empty', loc.dating_todayEmpty(loc.dating_region_gh_aa)),
        ('queue_full', loc.dating_todayQueueFull),
        ('paused_open_chats', loc.dating_todayPausedChats),
      ]) {
        final fake = FakeDatingToday(
          today: datingTodayJson({
            'today_state': state,
            'cards': <Object?>[],
            'drop_at': at.toIso8601String(),
          }),
        );
        await open(t, fake);
        expect(
          find.textContaining(line.split('{').first.substring(0, 20)),
          findsOneWidget,
          reason: state,
        );
      }
      final fake = FakeDatingToday(
        today: datingTodayJson({
          'waiting': [
            datingCardJson('w1', {'display_name': 'Esi'}),
          ],
        }),
      );
      await open(t, fake);
      expect(find.text(loc.dating_todayWaiting), findsOneWidget);
      expect(find.text(loc.dating_cardWhyTitle), findsNWidgets(2));
      expect(find.text(loc.dating_reasonSameCommitted), findsNWidgets(2));
      expect(find.text(loc.dating_cardChemistry), findsNWidgets(2));
      expect(
        find.textContaining(RegExp(r'\b(20|19):00\b|expire|left|ago')),
        findsNothing,
      );
    });

    testWidgets(
      'the refusals: the re-check, calm busy, the error line and Retry; offline',
      (t) async {
        final fake = FakeDatingToday(today: {'ok': false, 'reason': 'busy'});
        await open(t, fake);
        expect(find.text(loc.dating_busy), findsOneWidget);
        fake.json = datingTodayJson();
        await tap(t, find.text(loc.dating_tryAgain));
        expect(find.text(loc.dating_cardInterested), findsOneWidget);
        await open(
          t,
          FakeDatingToday(today: {'ok': false, 'reason': 'reverify_device'}),
        );
        expect(find.text(loc.dating_sectionReverify), findsOneWidget);
        await open(
          t,
          FakeDatingToday(today: {'ok': false, 'reason': 'a server text'}),
        );
        expect(find.text(loc.dating_errorGeneric), findsOneWidget);
        expect(find.textContaining('server text'), findsNothing);
        final offline = FakeDatingToday();
        await open(t, offline, online: false);
        expect(find.text(loc.dating_offline), findsOneWidget);
        await tap(t, find.text(loc.dating_cardInterested));
        expect(offline.acts, isEmpty);
      },
    );
  });

  group('the answers', () {
    testWidgets('Interested: "Noted." once; a double tap sends one answer', (
      t,
    ) async {
      final fake = FakeDatingToday();
      await open(t, fake);
      await tap(t, find.text(loc.dating_cardInterested));
      expect(find.text(loc.dating_cardNoted('Kofi')), findsOneWidget);
      expect(find.text(loc.dating_cardInterested), findsNothing);
      expect(fake.acts.map((a) => a.$3), ['interested']);
      expect(fake.acts.single.$1.length, greaterThanOrEqualTo(16));
    });

    testWidgets(
      'Not for me: the card goes, Undo brings it back and sends nothing',
      (t) async {
        final fake = FakeDatingToday();
        await open(t, fake);
        await tap(t, find.text(loc.dating_cardNotForMe));
        expect(find.text(loc.dating_cardInterested), findsNothing);
        expect(find.text(loc.dating_cardNotForMeDone), findsOneWidget);
        await t.tap(find.text(loc.dating_undo));
        await t.pumpAndSettle();
        expect(find.text(loc.dating_cardInterested), findsOneWidget);
        await t.pump(const Duration(seconds: 30));
        expect(fake.acts, isEmpty);
      },
    );

    testWidgets(
      'the window: 5 s, then sent once; 20 s with a screen reader (§7.4)',
      (t) async {
        final fake = FakeDatingToday();
        await open(t, fake);
        await tap(t, find.text(loc.dating_cardNotForMe));
        await t.pump(const Duration(seconds: 4));
        expect(fake.acts, isEmpty);
        await t.pump(const Duration(seconds: 2));
        expect(fake.acts.map((a) => a.$3), ['passed']);
        await t.pump(const Duration(seconds: 30));
        expect(fake.acts, hasLength(1));

        final reader = FakeDatingToday();
        t.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(accessibleNavigation: true);
        addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
        await open(t, reader);
        await tap(t, find.text(loc.dating_cardNotForMe));
        await t.pump(const Duration(seconds: 19));
        expect(reader.acts, isEmpty);
        await t.pump(const Duration(seconds: 2));
        expect(reader.acts.map((a) => a.$3), ['passed']);
      },
    );

    testWidgets('the next answer, or leaving, sends the held one first', (
      t,
    ) async {
      final fake = FakeDatingToday(
        today: datingTodayJson({
          'cards': [
            datingCardJson('a'),
            datingCardJson('b', {'display_name': 'Yaw'}),
          ],
        }),
      );
      final shell = await open(t, fake);
      await tap(t, find.text(loc.dating_cardNotForMe).first);
      await tap(t, find.text(loc.dating_cardInterested).first);
      expect(fake.acts.map((a) => (a.$2, a.$3)), [
        ('a', 'passed'),
        ('b', 'interested'),
      ]);
      final leave = FakeDatingToday();
      final s2 = await open(t, leave);
      await tap(t, find.text(loc.dating_cardNotForMe));
      s2.router.go('/home');
      await t.pumpAndSettle();
      expect(leave.acts.map((a) => a.$3), ['passed']);
      expect(shell.location, isNotNull);
    });

    testWidgets(
      'D8: a held answer is never sent as the next account; nothing of the last shows',
      (t) async {
        final fake = FakeDatingToday();
        final shell = await open(t, fake);
        await tap(t, find.text(loc.dating_cardNotForMe));
        fake.hold = Completer<DatingToday>();
        shell.container.read(datingTestAccount.notifier).state = 'kwame';
        await t.pump();
        await t.pump(const Duration(seconds: 30));
        expect(fake.acts, isEmpty);
        expect(find.textContaining('Kofi'), findsNothing);
        fake.hold!.complete(
          DatingToday.fromJson(
            datingTodayJson({'cards': <Object?>[], 'today_state': 'empty'}),
          ),
        );
        await t.pumpAndSettle();
        expect(find.textContaining('Kofi'), findsNothing);
      },
    );

    testWidgets(
      'a gone introduction says so calmly; busy is calm; a failure is the error line',
      (t) async {
        for (final (reason, line) in [
          ('introduction_unavailable', loc.dating_cardGone),
          ('busy', loc.dating_busy),
          ('failed', loc.dating_errorGeneric),
        ]) {
          final fake =
              FakeDatingToday()
                ..answer =
                    (id, action) => DatingActAnswer(ok: false, reason: reason);
          await open(t, fake);
          await tap(t, find.text(loc.dating_cardInterested));
          expect(find.text(line), findsOneWidget, reason: reason);
        }
      },
    );
  });

  group('photos, notes, widen', () {
    testWidgets('photos load from their URLs; data saver waits for a tap', (
      t,
    ) async {
      final fake = FakeDatingToday();
      await open(t, fake);
      expect(datingFetched, ['https://s.test/1', 'https://s.test/2']);
      datingFetched.clear();
      await DatingPhotoMemory.clear();
      final saver = FakeDatingToday(
        today: datingTodayJson({
          'data_saver': true,
          'cards': [datingCardJson('s')],
        }),
      );
      await open(t, saver);
      expect(datingFetched, isEmpty);
      await tap(t, find.text(loc.dating_cardShowPhotos));
      expect(saver.photoCalls, [('introduction', 's')]);
      final later = FakeDatingToday(
        today: datingTodayJson({
          'cards': [
            datingCardJson('l', {
              'photos_after_mutual': true,
              'photos': <Object?>[],
            }),
          ],
        }),
      );
      await open(t, later);
      expect(find.text(loc.dating_cardPhotosLater), findsOneWidget);
      expect(later.photoCalls, isEmpty);
    });

    testWidgets('the family question once: an answer or Skip', (t) async {
      final fake = FakeDatingToday(
        today: datingTodayJson({'family_question': true}),
      );
      await open(t, fake);
      await tap(t, find.text(loc.dating_familyEarly));
      expect(fake.families, ['early']);
      expect(find.text(loc.dating_familyQuestion), findsNothing);
      final skip = FakeDatingToday(
        today: datingTodayJson({'family_question': true}),
      );
      await open(t, skip);
      await tap(t, find.text(loc.dating_familySkip));
      expect(skip.notes, ['family']);
      expect(find.text(loc.dating_familyQuestion), findsNothing);
    });

    testWidgets(
      'the quiet note once; Widen opens the editors and comes back to Today',
      (t) async {
        final fake = FakeDatingToday(
          today: datingTodayJson({
            'today_state': 'empty',
            'cards': <Object?>[],
            'quiet_note': true,
          }),
        );
        final shell = await open(t, fake);
        expect(
          find.text(loc.dating_quietNote(loc.dating_region_gh_aa)),
          findsOneWidget,
        );
        await tap(t, find.text(loc.dating_todayWiden));
        expect(fake.notes, ['quiet']);
        expect(find.text(loc.dating_widenAges(25, 40)), findsOneWidget);
        expect(
          find.text(loc.dating_widenHowFar(loc.dating_scopeRegion)),
          findsOneWidget,
        );
        await tap(t, find.text(loc.dating_widenAges(25, 40)));
        await t.pumpAndSettle();
        final step = t.widget<DatingSetupStepRoute>(
          find.byType(DatingSetupStepRoute),
        );
        expect((step.step, step.from), ('meet', 'today'));
        expect(shell.location, isNotNull);
      },
    );
  });

  group('the match moment', () {
    testWidgets('shown once from Today, marked seen; Later goes back', (
      t,
    ) async {
      final fake = FakeDatingToday(
        today: datingTodayJson({
          'my_name': 'Ama',
          'moments': [
            {'match_id': 'm1', 'display_name': 'Kofi'},
          ],
        }),
      );
      final shell = await open(t, fake);
      expect(shell.location, isNotNull);
      expect(find.text(loc.dating_momentTitle('Kofi')), findsOneWidget);
      expect(find.text(loc.dating_momentBody), findsOneWidget);
      expect(find.text(loc.dating_momentSayHello), findsNothing);
      expect(fake.seen, ['m1']);
      await tap(t, find.text(loc.dating_momentLater));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_momentTitle('Kofi')), findsNothing);
      expect(find.text(loc.dating_cardInterested), findsOneWidget);
      expect(fake.seen, ['m1']);
    });

    testWidgets('one settle within 600 ms; none under reduce motion', (
      t,
    ) async {
      expect(kDatingMomentSettle, const Duration(milliseconds: 600));
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final fake = FakeDatingToday(
        today: datingTodayJson({
          'moments': [
            {'match_id': 'm1', 'display_name': 'Kofi'},
          ],
        }),
      );
      await open(t, fake);
      // Under reduce motion the avatars fade; nothing moves them.
      final moving = find.descendant(
        of: find.byKey(const ValueKey('dating_moment_avatars')),
        matching: find.byType(Transform),
      );
      expect(moving, findsNothing);
      t.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await open(
        t,
        FakeDatingToday(
          today: datingTodayJson({
            'moments': [
              {'match_id': 'm2', 'display_name': 'Yaw'},
            ],
          }),
        ),
      );
      expect(moving, findsNWidgets(2));
    });
  });

  testWidgets('the section, active, opens Today (§3.1)', (t) async {
    final h = await pumpFlowScreen(
      t,
      () => const Scaffold(body: SingleChildScrollView(child: DatingSection())),
      overrides: datingShellOverrides(
        home: FakeDatingHomeGateway(
          home: const DatingHome(state: DatingHomeState.active),
        ),
      ),
    );
    await tap(t, find.text(loc.dating_sectionOpenToday));
    await t.pumpAndSettle();
    expect(find.text('at ${DatingPaths.today}'), findsOneWidget);
    expect(h.location, isNotNull);
  });

  group('goldens and accessibility', () {
    testWidgets('Today and the moment: goldens, guidelines, dark', (t) async {
      for (final (name, json) in [
        ('today_delivered', datingTodayJson({'family_question': true})),
        (
          'today_empty',
          datingTodayJson({'today_state': 'empty', 'cards': <Object?>[]}),
        ),
      ]) {
        await expectFlowGoldens(
          t,
          name,
          () => const DatingTodayScreen(),
          overrides: [
            ...datingShellOverrides(),
            ...datingTodayOverrides(FakeDatingToday(today: json)),
          ],
        );
      }
      await expectFlowGoldens(
        t,
        'match_moment',
        () => const DatingMatchMomentScreen(
          matchId: 'm1',
          moment: DatingMoment(matchId: 'm1', name: 'Kofi'),
          myName: 'Ama',
        ),
        overrides: [
          ...datingShellOverrides(),
          ...datingTodayOverrides(FakeDatingToday()),
        ],
      );
      await pumpFlowScreen(
        t,
        () => const DatingTodayScreen(),
        overrides: [
          ...datingShellOverrides(),
          ...datingTodayOverrides(FakeDatingToday()),
        ],
      );
      await expectFlowGuidelines(t);
      await pumpFlowScreen(
        t,
        () => Theme(data: AppTheme.darkTheme, child: const DatingTodayScreen()),
        overrides: [
          ...datingShellOverrides(),
          ...datingTodayOverrides(FakeDatingToday()),
        ],
      );
      expect(t.takeException(), isNull);
    });
  });
}
```

```bash
flutter test --no-pub test/features/dating/today/today_screen_test.dart 2>&1 | tr '\r' '\n' | grep -m1 -o "Error: Error when reading '[^']*'"
```

Expected: `Error: Error when reading 'lib/features/dating/today/match_moment_screen.dart'`.

- [ ] **Step 3: Write the screens and wire them**

Create `lib/features/dating/today/today_screen.dart` with exactly:

```dart
// Spec 2 W5b (§3.4, §3.15 Today, §5.6, §5.8): Today. The day's state in
// the server's words (never a countdown), today's cards and the ones still
// waiting, the family question once and the quiet note once. Interested
// says "Noted."; Not for me collapses the card and offers Undo for 5 s (20 s
// with a screen reader); the answer is sent when that ends, at the next
// answer, or when the screen closes (never as another account: D8). Cards
// cross-fade in at 200 ms and collapse at 200 ms; none of it moves under
// reduce motion. Photos come from 60-second URLs into memory only, on a
// tap with data saver on. Every answer is a fixed code mapped to copy.
import 'dart:async';
import 'dart:typed_data';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/card/dating_card.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/lock/dating_sheets.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/features/dating/setup/dating_list_names.dart';
import 'package:attune/features/dating/today/dating_reasons.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/features/dating/today/dating_today_providers.dart';
import 'package:attune/features/dating/today/dating_today_repository.dart';
import 'package:attune/features/dating/verify/dating_reverify_line.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// §3.15: cards cross-fade in and collapse at 200 ms.
const kDatingCardMotion = Duration(milliseconds: 200);

/// §3.4: the undo window, and at least 20 s with a screen reader (WCAG
/// 2.2.1).
const kDatingUndo = Duration(seconds: 5);
const kDatingUndoScreenReader = Duration(seconds: 20);

class DatingTodayScreen extends ConsumerStatefulWidget {
  const DatingTodayScreen({super.key});

  @override
  ConsumerState<DatingTodayScreen> createState() => _DatingTodayScreenState();
}

class _DatingTodayScreenState extends ConsumerState<DatingTodayScreen> {
  final _keys = DatingActionKeys();
  late final DatingTodayGateway _gateway;
  String? _account;

  /// Cards answered Interested here (the "Noted." line).
  final _noted = <String>{};

  /// Cards collapsed by Not for me (held or sent).
  final _hidden = <String>{};

  /// The Not for me held for its undo window (card id).
  String? _pending;
  Timer? _undo;
  final _answers = <String, DatingActAnswer>{};
  final _photos = <String, List<Uint8List>>{};
  final _loading = <String>{};
  final _tapped = <String>{};
  bool _family = false;
  bool _quiet = false;
  bool _momentOpened = false;

  @override
  void initState() {
    super.initState();
    _gateway = ref.read(datingTodayGatewayProvider);
    _account = ref.read(datingAccountProvider);
    // D8: another account sees nothing of this one's day, and this one's
    // held answer is never sent as the next person.
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (previous == next || !mounted) return;
      _undo?.cancel();
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
      setState(() {
        _account = next;
        _pending = null;
        _noted.clear();
        _hidden.clear();
        _answers.clear();
        _photos.clear();
        _loading.clear();
        _tapped.clear();
        _family = false;
        _quiet = false;
        _momentOpened = false;
      });
    });
  }

  @override
  void dispose() {
    _undo?.cancel();
    // §3.4: closing the screen ends the undo window.
    final id = _pending;
    // (An account change already dropped it: never sent as the next one.)
    if (id != null) {
      unawaited(_gateway.act(_keys.keyFor('pass:$id', _account), id, 'passed'));
    }
    super.dispose();
  }

  bool get _reduce => MediaQuery.of(context).disableAnimations;

  /// Sends the held Not for me now (the window ended, or another answer).
  Future<void> _flush() async {
    final id = _pending;
    if (id == null) return;
    _undo?.cancel();
    _pending = null;
    final account = _account;
    final r = await _gateway.act(
      _keys.keyFor('pass:$id', account),
      id,
      'passed',
    );
    _keys.settle('pass:$id', reason: r.reason);
    if (!mounted || _account != account) return;
    setState(() {
      if (!r.ok && r.reason != 'introduction_unavailable') {
        _hidden.remove(id);
        _answers[id] = r;
      }
    });
  }

  Future<void> _interested(DatingIntroCard c) async {
    await _flush();
    final account = _account;
    final r = await _gateway.act(
      _keys.keyFor('int:${c.id}', account),
      c.id,
      'interested',
    );
    _keys.settle('int:${c.id}', reason: r.reason);
    if (!mounted || _account != account) return;
    setState(() {
      _answers[c.id] = r;
      if (r.ok) _noted.add(c.id);
    });
    if (r.matched) ref.invalidate(datingTodayProvider(account));
  }

  Future<void> _notForMe(DatingIntroCard c) async {
    await _flush();
    if (!mounted) return;
    final loc = AppLocalizations.of(context)!;
    final window =
        MediaQuery.of(context).accessibleNavigation
            ? kDatingUndoScreenReader
            : kDatingUndo;
    setState(() {
      _hidden.add(c.id);
      _pending = c.id;
      _answers.remove(c.id);
    });
    _undo = Timer(window, _flush);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: window,
        content: Text(loc.dating_cardNotForMeDone),
        action: SnackBarAction(
          label: loc.dating_undo,
          onPressed: () {
            if (_pending != c.id) return;
            _undo?.cancel();
            setState(() {
              _pending = null;
              _hidden.remove(c.id);
            });
          },
        ),
      ),
    );
  }

  void _loadPhotos(DatingIntroCard c) {
    if (_photos.containsKey(c.id) || !_loading.add(c.id)) return;
    final account = _account;
    loadDatingPhotos(
      _gateway,
      ref.read(datingPhotoFetchProvider),
      'introduction',
      c.id,
    ).then((bytes) {
      if (!mounted || _account != account) return;
      setState(() {
        _loading.remove(c.id);
        _photos[c.id] = bytes;
      });
    });
  }

  Future<void> _answerFamily(String? value) async {
    final account = _account;
    setState(() => _family = true);
    final w =
        value == null
            ? await _gateway.dismissNote('family')
            : await _gateway.saveFamily(
              _keys.keyFor('family', '$account|$value'),
              value,
            );
    _keys.settle('family', reason: w.reason);
  }

  void _openMoment(DatingToday day) {
    if (_momentOpened || day.moments.isEmpty) return;
    _momentOpened = true;
    final m = day.moments.first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context
          .push(DatingPaths.match(m.matchId), extra: (m, day.myName))
          .whenComplete(() {
            if (mounted) ref.invalidate(datingTodayProvider(_account));
          });
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final account = ref.watch(datingAccountProvider);
    final read = ref.watch(datingTodayProvider(account));
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final day = read.valueOrNull;
    if (day != null && day.ok) _openMoment(day);
    return AllowLargeText(
      child: Scaffold(
        appBar: AppBar(title: Text(loc.dating_todayTitle)),
        body: SafeArea(
          child: switch (read) {
            AsyncData(value: final d) when d.ok => _day(
              context,
              loc,
              d,
              online,
            ),
            AsyncData(value: final d) => ListView(
              padding: const EdgeInsets.all(Spacing.md),
              children: [_refusal(loc, d.reason, online)],
            ),
            AsyncError() => ListView(
              padding: const EdgeInsets.all(Spacing.md),
              children: [_refusal(loc, 'failed', online)],
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }

  Widget _refusal(AppLocalizations loc, String? reason, bool online) {
    final retry = FlowSecondaryButton(
      label: loc.dating_tryAgain,
      onPressed: () => ref.invalidate(datingTodayProvider(_account)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: switch (reason) {
        _ when !online => [DatingCalmLine(loc.dating_offline), retry],
        'reverify_device' => [const DatingReverifyLine()],
        'not_eligible' => [DatingCalmLine(loc.dating_sectionUnavailable)],
        'busy' => [DatingCalmLine(loc.dating_busy), retry],
        _ => [
          FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
          retry,
        ],
      },
    );
  }

  String? _region(AppLocalizations loc, DatingToday d) =>
      d.regionNameKey == null ? null : datingListName(loc, d.regionNameKey!);

  Widget _day(
    BuildContext context,
    AppLocalizations loc,
    DatingToday d,
    bool online,
  ) {
    final theme = Theme.of(context);
    final region = _region(loc, d);
    final at = d.dropAt?.toLocal();
    final line = switch (d.state) {
      DatingTodayState.delivered => null,
      DatingTodayState.beforeDrop when at != null => loc.dating_todayBeforeDrop(
        MyDateFormat.toTime(at),
      ),
      DatingTodayState.coolOff when at != null => loc.dating_sectionFirstDrop(
        MyDateFormat.toDate(at),
        MyDateFormat.toTime(at),
      ),
      DatingTodayState.queueFull => loc.dating_todayQueueFull,
      DatingTodayState.pausedOpenChats => loc.dating_todayPausedChats,
      DatingTodayState.empty =>
        region == null
            ? loc.dating_todayEmptyNoRegion
            : loc.dating_todayEmpty(region),
      _ => null,
    };
    final widen = FlowSecondaryButton(
      label: loc.dating_todayWiden,
      onPressed: online ? () => showDatingWidenSheet(context, d) : null,
    );
    // Every card is built (at most nine): each is in the tree to scroll to.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!online) DatingCalmLine(loc.dating_offline),
          if (line != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.md),
              child: Text(line, style: theme.textTheme.bodyLarge),
            ),
          if (d.state == DatingTodayState.empty && !(d.quietNote && !_quiet))
            widen,
          if (d.quietNote && !_quiet) _quietNote(loc, region, online, d),
          if (d.familyQuestion && !_family) _familyQuestion(loc, online),
          for (final c in d.cards) _tile(loc, c, d, online),
          if (d.waiting.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.md),
              child: Semantics(
                header: true,
                child: Text(
                  loc.dating_todayWaiting,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
            for (final c in d.waiting) _tile(loc, c, d, online),
          ],
        ],
      ),
    );
  }

  Widget _quietNote(
    AppLocalizations loc,
    String? region,
    bool online,
    DatingToday d,
  ) => Card(
    margin: const EdgeInsets.only(bottom: Spacing.md),
    child: Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(loc.dating_quietNote(region ?? loc.dating_widenCountry)),
          const SizedBox(height: Spacing.sm),
          FlowSecondaryButton(
            label: loc.dating_todayWiden,
            onPressed:
                online
                    ? () {
                      setState(() => _quiet = true);
                      unawaited(_gateway.dismissNote('quiet'));
                      showDatingWidenSheet(context, d);
                    }
                    : null,
          ),
          const SizedBox(height: Spacing.sm),
          FlowSecondaryButton(
            label: loc.dating_settingsPause,
            onPressed: () {
              setState(() => _quiet = true);
              unawaited(_gateway.dismissNote('quiet'));
              context.push(DatingPaths.settings);
            },
          ),
        ],
      ),
    ),
  );

  Widget _familyQuestion(AppLocalizations loc, bool online) => Card(
    margin: const EdgeInsets.only(bottom: Spacing.md),
    child: Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(loc.dating_familyQuestion),
          for (final (value, label) in [
            ('early', loc.dating_familyEarly),
            ('when_serious', loc.dating_familyWhenSerious),
            ('our_decision', loc.dating_familyOwn),
          ]) ...[
            const SizedBox(height: Spacing.sm),
            FlowSecondaryButton(
              label: label,
              onPressed: online ? () => _answerFamily(value) : null,
            ),
          ],
          const SizedBox(height: Spacing.sm),
          FlowTextLink(
            label: loc.dating_familySkip,
            alignment: AlignmentDirectional.centerStart,
            onPressed: () => _answerFamily(null),
          ),
        ],
      ),
    ),
  );

  Widget _tile(
    AppLocalizations loc,
    DatingIntroCard c,
    DatingToday d,
    bool online,
  ) {
    final hidePhotos = d.dataSaver && !_tapped.contains(c.id);
    if (!hidePhotos &&
        c.card.photoIds.isNotEmpty &&
        !c.card.photosAfterMutual) {
      _loadPhotos(c);
    }
    final answer = _answers[c.id];
    final noted = _noted.contains(c.id) || c.acted == 'interested';
    final name = c.card.displayName ?? '';
    final tile = DatingCardView(
      card: c.card,
      photos: _photos[c.id] ?? const [],
      photosHidden: hidePhotos,
      onShowPhotos: () => setState(() => _tapped.add(c.id)),
      trailing:
          (part) => switch (part) {
            'intention' => _reasons(loc, c),
            'photos' => Padding(
              padding: const EdgeInsets.only(top: Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (noted)
                    DatingCalmLine(loc.dating_cardNoted(name))
                  else ...[
                    FlowPrimaryButton(
                      label: loc.dating_cardInterested,
                      onPressed: online ? () => _interested(c) : null,
                    ),
                    const SizedBox(height: Spacing.sm),
                    FlowSecondaryButton(
                      label: loc.dating_cardNotForMe,
                      onPressed: online ? () => _notForMe(c) : null,
                    ),
                  ],
                  if (answer != null && !answer.ok) _answerLine(loc, answer),
                ],
              ),
            ),
            _ => null,
          },
    );
    final motion = _reduce ? Duration.zero : kDatingCardMotion;
    return AnimatedSize(
      key: ValueKey('dating_today_card_${c.id}'),
      duration: motion,
      child:
          _hidden.contains(c.id)
              ? const SizedBox(width: double.infinity)
              : TweenAnimationBuilder<double>(
                tween: Tween(begin: _reduce ? 1 : 0, end: 1),
                duration: motion,
                builder:
                    (context, v, child) => Opacity(opacity: v, child: child),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.md),
                  child: tile,
                ),
              ),
    );
  }

  Widget _reasons(AppLocalizations loc, DatingIntroCard c) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(loc.dating_cardWhyTitle, style: theme.textTheme.titleSmall),
          for (final line in datingReasonLines(loc, c))
            Text(line, style: theme.textTheme.bodyMedium),
          Text(loc.dating_cardChemistry, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _answerLine(AppLocalizations loc, DatingActAnswer a) => switch (a
      .reason) {
    'reverify_device' => const DatingReverifyLine(),
    'introduction_unavailable' => DatingCalmLine(loc.dating_cardGone),
    'busy' => DatingCalmLine(loc.dating_busy),
    'rate_limited' => FlowErrorLine(
      text: loc.dating_errorRateLimited,
      liveRegion: true,
    ),
    'not_eligible' => DatingCalmLine(loc.dating_sectionUnavailable),
    _ => FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
  };
}

/// §3.4 "Widen who I meet": each row opens its editor; nothing changes by
/// itself. W5c adds Other countries.
Future<void> showDatingWidenSheet(BuildContext context, DatingToday d) {
  final loc = AppLocalizations.of(context)!;
  final scope = switch (d.scope) {
    'side' => loc.dating_scopeSide,
    'country' => loc.dating_widenCountry,
    _ => loc.dating_scopeRegion,
  };
  return showModalBottomSheet<void>(
    context: context,
    routeSettings: datingSheetSettings('widen'),
    isScrollControlled: true,
    builder:
        (sheet) => DatingSheetTracker(
          child: AllowLargeText(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        loc.dating_todayWiden,
                        style: Theme.of(sheet).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(height: Spacing.sm),
                    if (d.minAge != null && d.maxAge != null)
                      InfoRowWidget(
                        title: loc.dating_widenAges(d.minAge!, d.maxAge!),
                        subtitle: '',
                        icon: Icons.cake_outlined,
                        showAvatar: false,
                        padding: const EdgeInsets.symmetric(
                          vertical: Spacing.xs,
                        ),
                        onTap: () {
                          Navigator.of(sheet).pop();
                          context.push(DatingPaths.stepFromToday('meet'));
                        },
                      ),
                    InfoRowWidget(
                      title: loc.dating_widenHowFar(scope),
                      subtitle: '',
                      icon: Icons.near_me_outlined,
                      showAvatar: false,
                      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                      onTap: () {
                        Navigator.of(sheet).pop();
                        context.push(DatingPaths.stepFromToday('where'));
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
  );
}
```

Create `lib/features/dating/today/match_moment_screen.dart` with exactly:

```dart
// Spec 2 W5b (§3.5, §3.15 Match moment): shown once to each person, the
// next time they open Today. "You and {Name} are both interested." The two
// first-letter avatars settle together once (at most 600 ms, one light
// haptic); with reduce motion they fade in. No counter, no burst, no "It's
// a match". The moment is marked seen when it shows (best effort). "Say
// hello" opens the conversation once W6a's chat exists (Ruling R-11).
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/features/dating/today/dating_today_providers.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// §3.5: the settle, at most 600 ms, once.
const kDatingMomentSettle = Duration(milliseconds: 600);

/// W6a flips this when /dating/chat/:matchId exists (Ruling R-11).
const kDatingChatReady = false;

class DatingMatchMomentScreen extends ConsumerStatefulWidget {
  const DatingMatchMomentScreen({
    super.key,
    required this.matchId,
    this.moment,
    this.myName,
  });

  final String matchId;

  /// From Today (memory only); a link without it reads Today again.
  final DatingMoment? moment;
  final String? myName;

  @override
  ConsumerState<DatingMatchMomentScreen> createState() =>
      _DatingMatchMomentScreenState();
}

class _DatingMatchMomentScreenState
    extends ConsumerState<DatingMatchMomentScreen>
    with SingleTickerProviderStateMixin {
  // Made in initState: a lazy one would be first made in dispose.
  late final AnimationController _settle;
  bool _marked = false;
  bool _played = false;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(vsync: this, duration: kDatingMomentSettle);
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _shown(DatingMoment m) {
    if (!_marked) {
      _marked = true;
      ref.read(datingTodayGatewayProvider).momentSeen(m.matchId);
    }
    if (_played) return;
    _played = true;
    final reduce = MediaQuery.of(context).disableAnimations;
    _settle.duration =
        reduce ? const Duration(milliseconds: 150) : kDatingMomentSettle;
    _settle.forward();
    if (!reduce) HapticFeedback.lightImpact();
  }

  void _later() =>
      context.canPop() ? context.pop() : context.go(DatingPaths.today);

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final account = ref.watch(datingAccountProvider);
    var moment = widget.moment;
    var myName = widget.myName;
    if (moment == null) {
      final day = ref.watch(datingTodayProvider(account)).valueOrNull;
      for (final m in day?.moments ?? const <DatingMoment>[]) {
        if (m.matchId == widget.matchId) moment = m;
      }
      myName ??= day?.myName;
    }
    final m = moment;
    if (m != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => mounted ? _shown(m) : null,
      );
    }
    final theme = Theme.of(context);
    final reduce = MediaQuery.of(context).disableAnimations;
    Widget avatar(String name, double side) => AnimatedBuilder(
      animation: _settle,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_settle.value);
        return reduce
            ? Opacity(opacity: t, child: child)
            : Transform.translate(
              offset: Offset(side * 24 * (1 - t), 0),
              child: child,
            );
      },
      child: CircleAvatar(
        radius: 32,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text(
          name.isEmpty ? '' : name.characters.first.toUpperCase(),
          style: theme.textTheme.headlineSmall?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
    return AllowLargeText(
      child: Scaffold(
        appBar: AppBar(automaticallyImplyLeading: false),
        body: SafeArea(
          child:
              m == null
                  ? Padding(
                    padding: const EdgeInsets.all(Spacing.md),
                    child: FlowSecondaryButton(
                      label: loc.dating_momentLater,
                      onPressed: _later,
                    ),
                  )
                  : SingleChildScrollView(
                    padding: const EdgeInsets.all(Spacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ExcludeSemantics(
                          child: Row(
                            key: const ValueKey('dating_moment_avatars'),
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              avatar(myName ?? '', -1),
                              const SizedBox(width: Spacing.sm),
                              avatar(m.name, 1),
                            ],
                          ),
                        ),
                        const SizedBox(height: Spacing.lg),
                        Semantics(
                          header: true,
                          liveRegion: true,
                          child: Text(
                            loc.dating_momentTitle(m.name),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall,
                          ),
                        ),
                        const SizedBox(height: Spacing.sm),
                        Text(
                          loc.dating_momentBody,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge,
                        ),
                        const SizedBox(height: Spacing.lg),
                        if (kDatingChatReady) ...[
                          FlowPrimaryButton(
                            label: loc.dating_momentSayHello,
                            onPressed: _later,
                          ),
                          const SizedBox(height: Spacing.sm),
                        ],
                        FlowSecondaryButton(
                          label: loc.dating_momentLater,
                          onPressed: _later,
                        ),
                      ],
                    ),
                  ),
        ),
      ),
    );
  }
}
```

Create `$D/edit_T7.py` with exactly:

```python
# Spec 2 W5b Task 7: Today and the match moment on the Dating routes (one
# redirect, the Dating lock gate), a step opened from Today comes back to
# it, Me's Dating section opens Today while active, and the text-scale
# audit lists both routes. Formatter-style edits (the files are W3's and
# Spec 1's, never formatted).
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anchor import edit

edit('lib/features/dating/routes/dating_routes.dart', [
  ("""import 'package:attune/features/dating/settings/dating_settings_screen.dart';
""", """import 'package:attune/features/dating/settings/dating_settings_screen.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/features/dating/today/match_moment_screen.dart';
import 'package:attune/features/dating/today/today_screen.dart';
"""),
  ("""  static const verify = '/dating/verify';

  static String step(String step) => '/dating/setup/$step';
""", """  static const verify = '/dating/verify';

  /// Spec 2 W5b (§3.4, §3.5): Today and one match's moment.
  static const today = '/dating/today';

  static String match(String id) => '/dating/match/$id';

  static String step(String step) => '/dating/setup/$step';

  /// Spec 2 W5b (§3.4): an editor opened from Widen comes back to Today.
  static String stepFromToday(String step) => '/dating/setup/$step?from=today';
"""),
  ("""  // Spec 2 W4b: the check's outcomes are never animated (§3.0).
  datingRoute(
    DatingPaths.verify,
    'datingVerify',
    signedIn,
    (s) => const DatingReverifyRoute(),
    motion: (s) => DatingMotion.none,
  ),
];""", """  // Spec 2 W4b: the check's outcomes are never animated (§3.0).
  datingRoute(
    DatingPaths.verify,
    'datingVerify',
    signedIn,
    (s) => const DatingReverifyRoute(),
    motion: (s) => DatingMotion.none,
  ),
  // Spec 2 W5b (§3.4, §3.15): Today slides in; the moment has its own
  // settle (§3.5), so its page doesn't move.
  datingRoute(
    DatingPaths.today,
    'datingToday',
    signedIn,
    (s) => const DatingTodayScreen(),
    motion: (s) => DatingMotion.sharedAxis,
  ),
  datingRoute(
    '/dating/match/:id',
    'datingMatch',
    signedIn,
    (s) => DatingMatchMomentScreen(
      matchId: s.pathParameters['id'] ?? '',
      moment: switch (s.extra) {
        (final DatingMoment m, _) => m,
        _ => null,
      },
      myName: switch (s.extra) {
        (_, final String name) => name,
        _ => null,
      },
    ),
    motion: (s) => DatingMotion.none,
  ),
];"""),
], 'routes: Today and the moment')

edit('lib/features/dating/routes/dating_setup_steps.dart', [
  ("""const _datingReturnPlaces = {'preview', 'settings', 'ready', 'section'};""",
   """const _datingReturnPlaces = {
  'preview',
  'settings',
  'ready',
  'section',
  // Spec 2 W5b (§3.4): Widen who I meet's editors.
  'today',
};"""),
  ("""  'settings' => DatingPaths.settings,
  'section' => homeLocation(tab: AppTab.me),""",
   """  'settings' => DatingPaths.settings,
  'today' => DatingPaths.today,
  'section' => homeLocation(tab: AppTab.me),"""),
], 'steps: back to Today')

edit('lib/features/dating/section/dating_section.dart', [
  ("""      case DatingHomeState.active:
        return _SectionCard(
          title: loc.flow_slotDatingTitle,
          lines: [loc.dating_sectionActive],
          children: [if (settings != null) settings],
        );""",
   """      case DatingHomeState.active:
        return _SectionCard(
          title: loc.flow_slotDatingTitle,
          lines: [loc.dating_sectionActive],
          children: [
            // Spec 2 W5b (§3.1, §3.4): the day's introductions.
            FlowPrimaryButton(
              label: loc.dating_sectionOpenToday,
              onPressed: () => context.push(DatingPaths.today),
            ),
            if (settings != null) settings,
          ],
        );"""),
], 'section: Open Today')

edit('test/architecture/text_scale_routes_test.dart', [
  ("""  // Spec 2 W4b (§3.3.4): the re-check on a new phone.
  'datingVerify',
""", """  // Spec 2 W4b (§3.3.4): the re-check on a new phone.
  'datingVerify',
  // Spec 2 W5b (§3.4, §3.5): Today and the match moment.
  'datingToday',
  'datingMatch',
"""),
], 'text scale: Today and the moment audited')

edit('test/features/dating/routes/dating_routes_test.dart', [
  ("""import '../support/dating_shell.dart';
""", """import '../support/dating_shell.dart';
import '../support/dating_today_fakes.dart';
"""),
  ("""                : null,
      );
      expect(s.location, location, reason: path);""",
   """                : null,
        // Spec 2 W5b: Today and the moment read their day from a fake.
        overrides: datingTodayOverrides(FakeDatingToday()),
      );
      expect(s.location, location, reason: path);"""),
], 'routes test: the C-1 guard pumps Today with a fake')
```

Create `$D/edit_T7_docs.py` with exactly:

```python
# Spec 2 W5b Task 7 (carry 15; W3 T12 ruling): the manual's introduction
# and match passages say what W5b builds: the reasons from what you both
# said (never a prediction), the undo, seven days to answer with no
# countdown, the moment shown once in Today, photos kept for mutual
# interest, and no push but the optional daily note.
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anchor import edit

edit('lib/app/documentations/user_manual/data/dating_mode_docs.dart', [
  ("""              'Dating introduces you to up to 3 people a day, at a time you choose. Each introduction says why you two were introduced: what you could do together and what you both say you value. There is no swipe deck, no browsing, no counters and no streaks.',""",
   """              'Dating introduces you to up to 3 people a day, in Today, at a time you choose. Each introduction says why you two were introduced, from what you both said you want and may show, and that Attune can\\'t predict chemistry. An introduction waits for you for seven days, with no countdown. If nobody is a good fit, Today says so: Attune never relaxes what you asked for to fill a day, and you can widen who you meet yourself. There is no swipe deck, no browsing, no counters and no streaks. If you turn on the daily note, Attune sends "You have something new in Attune." at your time, only when something is new.',"""),
  ("""              'You answer each introduction with "Interested" or "Not for me". Nobody is told you passed. A match appears only when you\\'re both interested.',""",
   """              'You answer each introduction with "Interested" or "Not for me", and you can undo "Not for me" for a few seconds. Nobody is told you passed or that you\\'re interested. A match appears only when you\\'re both interested: you each see "You and (their name) are both interested" once, the next time you open Today. If someone keeps their photos until you\\'re both interested, you see them once you match.',"""),
], 'manual: introductions and matches as W5b builds them')
```

- [ ] **Step 4: Apply, format, make the goldens, run**

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5
python3 -I $D/edit_T7.py
python3 -I $D/edit_T7_docs.py
dart format lib/features/dating/today/today_screen.dart lib/features/dating/today/match_moment_screen.dart test/features/dating/today/today_screen_test.dart | tail -1
flutter analyze --no-pub lib/features/dating test/features/dating test/architecture 2>&1 | tail -1
flutter test --no-pub test/features/dating/today/today_screen_test.dart --plain-name 'goldens' --update-goldens > /dev/null 2>&1; ls test/features/dating/today/goldens | wc -l
flutter test --no-pub test/features/dating/today test/features/dating/routes test/architecture/text_scale_routes_test.dart test/features/dating/setup/d1_d4_test.dart 2>&1 | tr '\r' '\n' | grep -E '^[0-9:]+ \+[0-9]+.*(All tests passed|Some tests failed)' | tail -1
python3 scripts/large_text_audit.py --scale 2.0 test/features/dating/today 2>&1 | tail -1
```

Expected: `dating_routes.dart: 3 edit(s) …`, `dating_setup_steps.dart: 2 edit(s) …`, `dating_section.dart: 1 edit(s) …`, `text_scale_routes_test.dart: 1 edit(s) …`, `dating_routes_test.dart: 2 edit(s) …`, `dating_mode_docs.dart: 2 edit(s) …`; `Formatted 3 files (0 changed) …`; `No issues found! …`; `12`; a last line ending `All tests passed!`; `SCALE 2.0: 0 site(s) to fix, 0 listed apart, 1 missed tap(s)` (the one is a `PageView` drag in the data test, not a tap).

- [ ] **Step 5: The mutants**

Create `$D/mut_T7.py` with exactly:

```python
# Spec 2 W5b Task 7: Dart mutants (dmut.py).
T = 'lib/features/dating/today/'
UI = ['test/features/dating/today/today_screen_test.dart']
MUTS = {
  'undo_reader_short': (T + 'today_screen.dart', "const kDatingUndoScreenReader = Duration(seconds: 20);",
      "const kDatingUndoScreenReader = Duration(seconds: 5);", UI),
  'leave_drops_pass': (T + 'today_screen.dart', "      unawaited(_gateway.act(_keys.keyFor('pass:$id', _account), id, 'passed'));",
      "      // dropped", UI),
  'd8_keeps_pass': (T + 'today_screen.dart', "        _account = next;\n        _pending = null;", "        _account = next;", UI),
  'saver_ignored': (T + 'today_screen.dart', "    final hidePhotos = d.dataSaver && !_tapped.contains(c.id);",
      "    final hidePhotos = false && !_tapped.contains(c.id);", UI),
  'moment_unmarked': (T + 'match_moment_screen.dart', "      ref.read(datingTodayGatewayProvider).momentSeen(m.matchId);", "      // unmarked", UI),
  'moment_moves_reduced': (T + 'match_moment_screen.dart', "        return reduce\n", "        return false\n", UI),
  'server_text_shown': (T + 'today_screen.dart', "        _ => [\n          FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),",
      "        _ => [\n          FlowErrorLine(text: reason ?? '', liveRegion: true),", UI),
  'section_no_today': ('lib/features/dating/section/dating_section.dart',
      "              onPressed: () => context.push(DatingPaths.today),", "              onPressed: () {},", UI),
  'interest_buttons_stay': (T + 'today_screen.dart', "              if (noted)", "              if (false)", UI),
}
```

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5; python3 -I $D/dmut.py $D/mut_T7.py 2>&1 | tail -1
```

Expected: `9/9 killed` (e.g. `undo_reader_short: KILLED  Expected: empty`, `d8_keeps_pass: KILLED  Expected: empty`, `moment_moves_reduced: KILLED  Expected: no matching candidates`, `section_no_today: KILLED  Expected: exactly one matching candidate`).

- [ ] **Step 6: The W5b gate**

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5
$D/suite.sh attune_spec3a > $D/sql-W5b.txt; echo "$(grep -c '^PASS' $D/sql-W5b.txt) PASS, $(grep -c '^FAIL' $D/sql-W5b.txt) FAIL"
python3 -I $D/mutate.py supabase/migrations/20261119110000_dating_v2_today.sql supabase/tests/dating_v2_matching_contracts.sql $D/mut_T4.py $D/mut supabase/migrations/20261119110010_dating_v2_today_grants.sql 2>&1 | grep -c 'CONTRACT VIOLATED'
flutter analyze --no-pub lib test > $D/analyze-W5b.txt 2>&1; tail -1 $D/analyze-W5b.txt
flutter test --reporter compact > $D/flutter-W5b.txt 2>&1; tr '\r' '\n' < $D/flutter-W5b.txt | grep -E '^[0-9:]+ \+[0-9]+' | tail -1
shasum -c .superpowers/sdd/2026-11-04-spec1-w10-accessibility-docs/w10-1.0.sha | grep -vc ': OK$'; shasum -c .superpowers/sdd/2026-11-04-spec1-w9/flag_off.sha | grep -vc ': OK$'
shasum -c .superpowers/sdd/2026-11-07-spec2-w3/latch.sha; flutter test --no-pub test/architecture/games_untouched_test.dart 2>&1 | tr '\r' '\n' | tail -1
```

Expected: `160 PASS, 14 FAIL`; `22`; `571 issues found. (ran in …)`; `+8218` (+27: Task 6's 12, Task 7's 15) and only the known flakes; `0`; `0`; `lib/home/home_screen.dart: OK`; `All tests passed!`. The race script: Task 4's 31. Deno: Task 5's 200.

- [ ] **Step 7: Record the tree**

Do not commit; record the tree in the report.


## Batch W5c — Never introduce, other countries, signals, fairness

### Task 8: Migration `dating_v2_signals`: the dragnet and its throttle, several accounts on one phone, filter 15, fairness, Other countries' read (§4.9 W5c, §5.9, §5.10, §2.6, §2.8, §3.12, §7.2 S10; carries 17, 18; R-14, R-26–R-30)

**Files:**
- Create: `supabase/migrations/20261119120000_dating_v2_signals.sql`, `supabase/migrations/20261119120010_dating_v2_signals_grants.sql`, `$D/{before_w5c/, mig_T8_head.sql, mig_T8_tail.sql, build_mig_T8.py, contract_T8.sql, splice_T8.py, edit_tests_T8.py, mut_T8.py}`
- Modify: `supabase/tests/dating_v2_matching_contracts.sql` (Q–U added), `supabase/tests/dating_rls_canary.sql`, `scripts/local_pg_grants.sql`

**Interfaces:**
- Consumes: Task 2's tick and `private.dating_capacity`, Task 1's `private.dating_person_current`, W1's `dating_device_accounts`, W4's `dating_device_state`, `private.dating_country_rule`.
- Produces: `public.dating_moderation_cases`, `public.dating_fairness_reports` (service_role only), `private.dating_run_signals(p_now)`, `private.dating_throttled(uuid)`, `public.run_dating_fairness_weekly(p_now)` (cron `dating-fairness-weekly`, Mondays 04:17), `public.get_dating_abroad_options()`; filter 15 in `dating_person_current`; the tick runs the signals first.

- [ ] **Step 1: Save the live bodies the migration re-creates**

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5; mkdir -p $D/before_w5c
for sig in 'private.dating_capacity(uuid,timestamp with time zone,jsonb)' 'private.dating_person_current(uuid,timestamp with time zone,jsonb)' 'public.run_dating_generation_tick(timestamp with time zone,text)'; do
  psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)" > "$D/before_w5c/$sig.sql"
done
ls $D/before_w5c | wc -l
```

Expected: `3`.

- [ ] **Step 2: Write the failing sections**

Create `$D/contract_T8.sql` with exactly (sections Q–U):

```sql
-- =====================================================================
-- Q. (§5.10, §7.2 S10; Ruling R-14) The dragnet: 15 introductions in 14
--    days with "Interested" on 90% or more, and a first message in 20% or
--    fewer of the matches, opens one P2 signal case (never twice) and caps
--    the person at one introduction a day; once today's one is made, they
--    are out of generation (filter 15). Until W6a's messages exist the
--    first-message input is unknown and the rule waits. Under 90%: nothing.
-- =====================================================================
DO $$
DECLARE
  d constant uuid := pg_temp.ready('95', '{"identity": "man", "seeking": ["woman"]}');
  q constant uuid := pg_temp.ready('96', '{"identity": "man", "seeking": ["woman"]}');
  w constant uuid := pg_temp.ready('97');
  v_cfg constant jsonb := (private.dating_intro_config()).o_config;
  v_at constant timestamptz := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + interval '2 days 3 hours 17 minutes';
  v_stub constant text := 'CREATE OR REPLACE FUNCTION private.dating_first_messages(p_user uuid, p_since timestamptz) RETURNS integer LANGUAGE sql AS $f$ SELECT 0 $f$';
  v text;
BEGIN
  UPDATE public.dating_enrollments SET state = 'paused', pause_reason = 'user' WHERE state = 'active' AND user_id NOT IN (d, q, w);
  -- 15 introductions each in the last 14 days, with 15 other people.
  INSERT INTO auth.users (id) SELECT ('5e5d0000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid FROM generate_series(1, 15) AS n;
  INSERT INTO public.users (id, display_name) SELECT ('5e5d0000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'Other' FROM generate_series(1, 15) AS n;
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, low_action, high_action, created_at)
  SELECT 'w5drag:' || x.who || ':' || n, least(x.who, o), greatest(x.who, o), 'interested', 'introductions_v2',
         CASE WHEN x.who < o AND (x.who = d OR n <= 12) THEN 'interested' END,
         CASE WHEN x.who > o AND (x.who = d OR n <= 12) THEN 'interested' END, v_at - make_interval(days => n % 13 + 1)
    FROM (VALUES (d), (q)) AS x(who), generate_series(1, 15) AS n,
         LATERAL (SELECT ('5e5d0000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid AS o) AS other;
  INSERT INTO public.dating_matches (introduction_id, user_low_id, user_high_id, state)
  SELECT i.id, i.user_low_id, i.user_high_id, 'closed' FROM public.dating_introductions AS i
   WHERE i.pair_key IN ('w5drag:' || d || ':1', 'w5drag:' || q || ':1');
  -- W5: the first-message input is unknown, so nothing opens.
  PERFORM private.dating_run_signals(v_at, v_cfg);
  IF EXISTS (SELECT 1 FROM public.dating_moderation_cases WHERE signal_kind = 'dragnet') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the dragnet fired without its first-message input (Ruling R-14)';
  END IF;
  -- The tick runs the signals before any partition (here none: 'ZZ' has
  -- no row); a second run opens no second case.
  v := pg_temp.probe(ARRAY[v_stub,
         format('SELECT public.run_dating_generation_tick(%L, ''ZZ'')', v_at),
         format('SELECT public.run_dating_generation_tick(%L, ''ZZ'')', v_at)],
       format($q$SELECT (SELECT count(*) FROM public.dating_moderation_cases WHERE signal_kind = 'dragnet' AND target_user_id = %L AND kind = 'signal' AND priority = 'P2' AND state = 'open' AND target_phone_hmac = public.dating_phone_hmac_for_user(%L))
                 || ':' || (SELECT count(*) FROM public.dating_moderation_cases WHERE signal_kind = 'dragnet' AND target_user_id = %L)
                 || ':' || private.dating_capacity(%L, %L, %L)
                 || ':' || private.dating_capacity(%L, %L, %L)$q$, d, d, q, d, v_at, v_cfg, w, v_at, v_cfg));
  IF v IS DISTINCT FROM '1:0:1:3' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the dragnet did not open one case and throttle to 1 (or touched someone under 90%%): %', v;
  END IF;
  -- Today's one made: out of generation (filter 15) until a moderator decides.
  v := pg_temp.probe(ARRAY[v_stub,
         format('SELECT private.dating_run_signals(%L, %L)', v_at, v_cfg),
         format('INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, created_at) VALUES (''w5drag:today'', least(%L::uuid, %L::uuid), greatest(%L::uuid, %L::uuid), ''generated'', ''introductions_v2'', %L::timestamptz - interval ''1 hour'')', d, w, d, w, v_at)],
       format('SELECT private.dating_person_current(%L, %L, %L)::text || '':'' || private.dating_person_current(%L, %L, %L)::text', d, v_at, v_cfg, w, v_at, v_cfg));
  IF v IS DISTINCT FROM 'false:true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a throttled person at 0 stayed in generation (filter 15): %', v;
  END IF;
END $$;

-- =====================================================================
-- R. (§5.10, §2.8) Several Dating accounts on one phone: two activations
--    from one trusted phone in 30 days open one case for each account;
--    older than 30 days, none. A case only: nothing else changes.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('14');
  b constant uuid := pg_temp.ready('15', '{"identity": "man", "seeking": ["woman"]}');
  c constant uuid := pg_temp.ready('16');
  c2 constant uuid := pg_temp.ready('13');
  v_shared constant text := encode(extensions.digest('w5-shared-phone', 'sha256'), 'hex');
  v_cfg constant jsonb := (private.dating_intro_config()).o_config;
  v_before bigint := pg_temp.metric('dating.signal.device_accounts');
BEGIN
  INSERT INTO public.dating_trusted_devices (user_id, device_hash, verified_at, last_seen_at)
  VALUES (a, v_shared, now() - interval '3 days', now()), (b, v_shared, now() - interval '1 day', now()),
         (c, encode(extensions.digest('w5-old-phone', 'sha256'), 'hex'), now() - interval '40 days', now()),
         (c2, encode(extensions.digest('w5-old-phone', 'sha256'), 'hex'), now() - interval '35 days', now());
  PERFORM private.dating_run_signals(now(), v_cfg);
  IF (SELECT count(*) FROM public.dating_moderation_cases WHERE signal_kind = 'device_accounts' AND target_user_id IN (a, b)) <> 2
     OR EXISTS (SELECT 1 FROM public.dating_moderation_cases WHERE signal_kind = 'device_accounts' AND target_user_id IN (c, c2))
     OR pg_temp.metric('dating.signal.device_accounts') <> v_before + 2
     OR (SELECT state FROM public.dating_enrollments WHERE user_id = a) <> 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two accounts on one phone did not open one case each (and only that)';
  END IF;
END $$;

-- =====================================================================
-- S. (§2.8, §5.10) No signal reads a country, a region, a network, a phone
--    number or prefix, or a name (the case writer records the phone's
--    HMAC the case carries, §4.3; it decides nothing). No routing column
--    (S-5).
-- =====================================================================
DO $$
DECLARE
  v_bad text;
BEGIN
  SELECT string_agg(p.proname, ', ') INTO v_bad
    FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
   WHERE n.nspname = 'private'
     AND p.proname IN ('dating_dragnet_holds', 'dating_device_accounts_hold', 'dating_run_signals', 'dating_throttled',
                       'dating_generation_removed', 'dating_first_messages')
     AND p.prosrc ~* '(country|region|side_code|network|phone|display_name|calling|prefix)';
  IF v_bad IS NOT NULL OR (SELECT count(*) FROM pg_proc WHERE proname IN ('dating_dragnet_holds', 'dating_device_accounts_hold', 'dating_run_signals')) <> 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a signal reads a country, region, network, phone or name: %', v_bad;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'dating_moderation_cases' AND column_name LIKE '%routing%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the queue stores routing (S-5)';
  END IF;
END $$;

-- =====================================================================
-- T. (§5.9) Fairness: per country and cohort at n >= 50 only (a smaller
--    cohort is left out, never merged); a cohort below 0.8 of the
--    country's introductions per person is flagged; the top 10% holding
--    over 25% of introductions is flagged; aggregates only; idempotent.
-- =====================================================================
CREATE FUNCTION pg_temp.fair_person(p_n int, p_region text, p_identity text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_u constant uuid := ('5e5fa000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid;
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at) VALUES (v_u, '1555940' || lpad(p_n::text, 4, '0'), now(), now() - interval '60 days');
  INSERT INTO public.users (id, phone, display_name, path, created_at) VALUES (v_u, '+1555940' || lpad(p_n::text, 4, '0'), 'Fair ' || p_n, 'dating', now() - interval '60 days');
  INSERT INTO public.account_birthdates (user_id, birth_date) VALUES (v_u, (current_date - interval '30 years 10 days')::date);
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_u, 'active');
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES (v_u, 'Fair', 'GH', p_region);
  INSERT INTO public.dating_profile_sensitive (user_id, identity_enc)
  VALUES (v_u, private.dating_field_encrypt(jsonb_build_object('identity', p_identity, 'pools', jsonb_build_array(p_identity))));
  RETURN v_u;
END $$;
DO $$
DECLARE
  v_week constant date := (date_trunc('week', now()) + interval '7 days')::date;
  v jsonb;
BEGIN
  UPDATE public.dating_enrollments SET state = 'paused', pause_reason = 'user' WHERE state = 'active';
  -- 60 in Greater Accra (two introductions each), 60 in Ashanti (none), 10 in Ahafo.
  PERFORM pg_temp.fair_person(n, CASE WHEN n <= 60 THEN 'AA' WHEN n <= 120 THEN 'AH' ELSE 'AF' END,
                              CASE WHEN n % 2 = 0 THEN 'woman' ELSE 'man' END) FROM generate_series(1, 130) AS n;
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, created_at)
  SELECT 'w5fair:' || n, least(a, b), greatest(a, b), CASE WHEN n % 3 = 0 THEN 'matched' ELSE 'passed' END, 'introductions_v2', now() - interval '2 days'
    FROM generate_series(1, 60) AS n,
         LATERAL (SELECT ('5e5fa000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid AS a,
                         ('5e5fa000-0000-0000-0000-' || lpad((n % 60 + 1)::text, 12, '0'))::uuid AS b) AS x;
  IF public.dating_fairness_weekly(v_week) < 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the fairness job wrote nothing';
  END IF;
  SELECT jsonb_object_agg(cohort_key, jsonb_build_array(active_bucket, introductions_per_active, flagged)) INTO v
    FROM public.dating_fairness_reports WHERE week = v_week AND country_code = 'GH';
  IF v -> 'region:AA' IS DISTINCT FROM '["50–99", 2.0000, false]'::jsonb
     OR v -> 'region:AH' IS DISTINCT FROM '["50–99", 0.0000, true]'::jsonb
     OR v ? 'region:AF' OR v ? 'gender:other'
     OR (v #>> '{age:25_34,2}')::boolean OR (v #>> '{gender:woman,2}')::boolean
     OR (v #>> '{top_decile,2}')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the fairness rows are not the n >= 50 cohorts with their flags: %', v;
  END IF;
  -- The top 10%: 13 people hold nearly every introduction.
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, created_at)
  SELECT 'w5top:' || a || b, ('5e5fa000-0000-0000-0000-' || lpad(a::text, 12, '0'))::uuid,
         ('5e5fa000-0000-0000-0000-' || lpad(b::text, 12, '0'))::uuid, 'passed', 'introductions_v2', now() - interval '2 days'
    FROM generate_series(61, 73) AS a, generate_series(61, 73) AS b WHERE a < b;
  PERFORM public.dating_fairness_weekly(v_week);
  IF (SELECT flagged FROM public.dating_fairness_reports WHERE week = v_week AND country_code = 'GH' AND cohort_key = 'top_decile') IS NOT TRUE
     OR (SELECT count(*) FROM public.dating_fairness_reports WHERE week = v_week AND cohort_key = 'top_decile') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the top decile holding over 25%% was not flagged (or the rerun duplicated rows)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dating-fairness-weekly' AND schedule = '17 4 * * 1') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the fairness cron is not scheduled';
  END IF;
END $$;

-- =====================================================================
-- U. (§2.6, §3.12; carry 17) Other countries: the open countries but the
--    person's own, each on or off; eligible only verified, age checked,
--    14+ days; a country whose same-gender rule refuses the person's
--    answers is never offered; another phone reads nothing.
-- =====================================================================
DO $$
DECLARE
  g constant uuid := pg_temp.ready('17');
  y constant uuid := pg_temp.ready('18', '{"days": 5}');
  nb constant uuid := pg_temp.ready('19', '{"country": "GB", "region": "TLI", "identity": "non_binary", "pools": ["non_binary"], "seeking": ["man", "woman", "non_binary"]}');
  p constant uuid := pg_temp.ready('20', '{"country": "GB", "region": "TLI"}');
  v jsonb;
BEGIN
  v := pg_temp.call(g, pg_temp.dev('17'), 'SELECT public.get_dating_abroad_options()')::jsonb;
  IF v IS DISTINCT FROM '{"ok": true, "eligible": true, "countries": [{"on": false, "code": "GB"}]}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the options are not the other open countries: %', v;
  END IF;
  PERFORM pg_temp.call(g, pg_temp.dev('17'), format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GB'']::char(2)[])', md5('abroad-g')));
  IF pg_temp.call(g, pg_temp.dev('17'), 'SELECT public.get_dating_abroad_options()')::jsonb #> '{countries,0,on}' IS DISTINCT FROM 'true'::jsonb
     OR (pg_temp.call(y, pg_temp.dev('18'), 'SELECT public.get_dating_abroad_options()')::jsonb ->> 'eligible')::boolean
     OR pg_temp.call(nb, pg_temp.dev('19'), 'SELECT public.get_dating_abroad_options()')::jsonb -> 'countries' IS DISTINCT FROM '[]'::jsonb
     OR pg_temp.call(p, pg_temp.dev('20'), 'SELECT public.get_dating_abroad_options()')::jsonb -> 'countries' IS DISTINCT FROM '[{"on": false, "code": "GH"}]'::jsonb
     OR pg_temp.call(g, pg_temp.dev('99'), 'SELECT public.get_dating_abroad_options()') IS DISTINCT FROM '{"ok": false, "reason": "reverify_device"}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Other countries: not on after turning on, eligible under 14 days, a same-gender-off country offered to a not-plain profile, or read from another phone';
  END IF;
END $$;
```

Create `$D/splice_T8.py` with exactly:

```python
# Spec 2 W5c Task 8: sections Q-U go in before the final notice.
import pathlib
D = pathlib.Path('.superpowers/sdd/2026-11-19-spec2-w5')
p = pathlib.Path('supabase/tests/dating_v2_matching_contracts.sql')
s = p.read_text()
end = "DO $$ BEGIN RAISE NOTICE 'dating_v2_matching_contracts: all held'; END $$;"
assert s.count(end) == 1
p.write_text(s.replace(end, (D / 'contract_T8.sql').read_text() + end))
print(f'{p}: Q-U in')
```

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5
python3 -I $D/splice_T8.py
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_matching_contracts.sql 2>&1 | grep -v 'skipping' | grep -m1 ERROR
```

Expected: `supabase/tests/dating_v2_matching_contracts.sql: Q-U in`; then `psql:supabase/tests/dating_v2_matching_contracts.sql:1133: ERROR:  function private.dating_run_signals(timestamp with time zone, jsonb) does not exist`.

- [ ] **Step 3: Write the migration**

Create `$D/mig_T8_head.sql` with exactly:

```sql
-- supabase/migrations/20261119120000_dating_v2_signals.sql
-- Spec 2 W5c (§4.9 W5c, §4.3, §2.6, §2.8, §5.2 15, §5.9, §5.10, §6.9;
-- carry 17): the moderation queue's table (signals only until W7 adds
-- reports and appeals; no routing column, S-5); the behaviour signals whose
-- inputs exist now: the dragnet (with its throttle to one introduction a
-- day until a moderator decides) and several Dating accounts on one phone;
-- each opens one case and nothing else (never a ban, never a partner told).
-- The dragnet's first-message input comes with W6a's messages: until then
-- it reads "unknown" and the rule waits for it (Ruling R-14). Generation
-- runs the signals before its partitions, never introduces anyone the
-- throttle has used up (filter 15) and caps a throttled person at one a
-- day. The weekly fairness job (aggregates only, n >= 50, flags for the
-- safety owner, no automatic re-weighting) and its cron. The countries a
-- person may open to (the Other countries setting), never one whose
-- same-gender rule refuses their answers. No signal reads country, region,
-- network, phone, name or a prefix. Dating stays off. Idempotent.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- =====================================================================
-- 1. The queue (§4.3): signals now; W7a adds reports and appeals, W7b
--    the console. Whether a case needs a routed reviewer is computed when
--    it is read, never stored (S-5). One open signal case per person and
--    kind.
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.dating_moderation_cases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind text NOT NULL CHECK (kind IN ('report', 'photo', 'verification', 'signal', 'appeal', 'csam_hit')),
  priority text NOT NULL DEFAULT 'P2' CHECK (priority IN ('P0', 'P1', 'P2', 'P3')),
  target_user_id uuid REFERENCES public.users (id) ON DELETE SET NULL,
  target_phone_hmac text CHECK (target_phone_hmac IS NULL OR target_phone_hmac ~ '^[0-9a-f]{64}$'),
  report_id uuid,
  match_id uuid REFERENCES public.dating_matches (id) ON DELETE SET NULL,
  signal_kind text CHECK (signal_kind IS NULL OR signal_kind IN
    ('dragnet', 'duplicate_opener', 'money_asks', 'sexual_pressure', 'location_mismatch', 'device_accounts')),
  state text NOT NULL DEFAULT 'open' CHECK (state IN ('open', 'in_review', 'decided', 'closed')),
  assigned_to uuid,
  sla_due_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_at timestamptz,
  outcome text,
  CHECK ((kind = 'signal') = (signal_kind IS NOT NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS dating_moderation_cases_open_signal_idx
  ON public.dating_moderation_cases (target_user_id, signal_kind)
  WHERE kind = 'signal' AND state IN ('open', 'in_review');
CREATE INDEX IF NOT EXISTS dating_moderation_cases_state_idx ON public.dating_moderation_cases (state, priority, created_at);
ALTER TABLE public.dating_moderation_cases ENABLE ROW LEVEL SECURITY;

-- =====================================================================
-- 2. Fairness reports (§4.3, §5.9): aggregates only, rows only at n >= 50.
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.dating_fairness_reports (
  week date NOT NULL,
  country_code char(2) NOT NULL,
  cohort_key text NOT NULL CHECK (cohort_key ~ '^(region:[A-Z0-9_]{1,16}|age:(18_24|25_34|35_44|45_54|55_plus)|gender:(woman|man|other)|top_decile)$'),
  active_bucket text NOT NULL CHECK (active_bucket IN ('50–99', '100–499', '500+')),
  introductions_per_active numeric NOT NULL,
  mutual_rate numeric,
  flagged boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (week, country_code, cohort_key)
);
ALTER TABLE public.dating_fairness_reports ENABLE ROW LEVEL SECURITY;

-- =====================================================================
-- 3. Signals (§5.10, §2.8). Behaviour only: no signal function reads a
--    country, a region, a network, a phone number or prefix, or a name.
-- =====================================================================
-- One open case per person and kind; true when this call opened it.
CREATE OR REPLACE FUNCTION private.dating_open_signal_case(p_user uuid, p_signal text, p_priority text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, target_phone_hmac, signal_kind)
  VALUES ('signal', p_priority, p_user, public.dating_phone_hmac_for_user(p_user), p_signal)
  ON CONFLICT (target_user_id, signal_kind) WHERE kind = 'signal' AND state IN ('open', 'in_review') DO NOTHING
  RETURNING id INTO v_id;
  IF v_id IS NOT NULL THEN
    PERFORM private.bump_metric_internal('dating.signal.' || p_signal);
  END IF;
  RETURN v_id IS NOT NULL;
END;
$$;

-- The first messages the person sent in matches made since [p_since]:
-- W6a's messages answer it; until then unknown (NULL), and a rule that
-- needs it waits (Ruling R-14).
CREATE OR REPLACE FUNCTION private.dating_first_messages(p_user uuid, p_since timestamptz)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT NULL::integer;
$$;

-- §5.10 dragnet: >= 15 introductions in 14 days, "Interested" on >= 90%
-- of them, and a first message in <= 20% of the matches they made. An
-- unknown input never holds.
CREATE OR REPLACE FUNCTION private.dating_dragnet_holds(p_user uuid, p_at timestamptz, p_cfg jsonb)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_since constant timestamptz := p_at - make_interval(days => coalesce((p_cfg #>> '{dragnet,window_days}')::int, 14));
  v_intros integer;
  v_interested integer;
  v_matches integer;
  v_first integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE CASE WHEN i.user_low_id = p_user THEN i.low_action ELSE i.high_action END = 'interested')
    INTO v_intros, v_interested
    FROM public.dating_introductions AS i
   WHERE p_user IN (i.user_low_id, i.user_high_id) AND i.created_at > v_since AND i.created_at <= p_at;
  IF v_intros < coalesce((p_cfg #>> '{dragnet,min_intros}')::int, 15)
     OR v_interested < v_intros * coalesce((p_cfg #>> '{dragnet,interested_ratio}')::numeric, 0.9) THEN
    RETURN false;
  END IF;
  SELECT count(*) INTO v_matches
    FROM public.dating_matches AS m JOIN public.dating_introductions AS i ON i.id = m.introduction_id
   WHERE p_user IN (i.user_low_id, i.user_high_id) AND i.created_at > v_since AND i.created_at <= p_at;
  v_first := private.dating_first_messages(p_user, v_since);
  RETURN coalesce(v_matches > 0
                  AND v_first <= v_matches * coalesce((p_cfg #>> '{dragnet,first_message_ratio}')::numeric, 0.2), false);
END;
$$;

-- §5.10, §2.8: two or more Dating activations from one trusted phone in
-- 30 days (the phone that passed each activation's check).
CREATE OR REPLACE FUNCTION private.dating_device_accounts_hold(p_user uuid, p_at timestamptz)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.dating_trusted_devices AS mine
      JOIN public.dating_trusted_devices AS other
        ON other.device_hash = mine.device_hash AND other.user_id <> mine.user_id
     WHERE mine.user_id = p_user
       AND mine.verified_at > p_at - interval '30 days' AND other.verified_at > p_at - interval '30 days');
$$;

-- Every active person, once per generation tick: open the case a signal
-- calls for. Returns how many cases it opened.
CREATE OR REPLACE FUNCTION private.dating_run_signals(p_at timestamptz, p_cfg jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  r record;
  v_n integer := 0;
BEGIN
  FOR r IN SELECT e.user_id FROM public.dating_enrollments AS e WHERE e.state = 'active' ORDER BY e.user_id LOOP
    IF private.dating_dragnet_holds(r.user_id, p_at, p_cfg) AND private.dating_open_signal_case(r.user_id, 'dragnet', 'P2') THEN
      v_n := v_n + 1;
    END IF;
    IF private.dating_device_accounts_hold(r.user_id, p_at) AND private.dating_open_signal_case(r.user_id, 'device_accounts', 'P2') THEN
      v_n := v_n + 1;
    END IF;
  END LOOP;
  RETURN v_n;
END;
$$;

-- A person under an open dragnet case (until a moderator decides).
CREATE OR REPLACE FUNCTION private.dating_throttled(p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.dating_moderation_cases AS c
                  WHERE c.target_user_id = p_user AND c.kind = 'signal' AND c.signal_kind = 'dragnet'
                    AND c.state IN ('open', 'in_review'));
$$;

-- §5.2 15: removed from generation for now. W5c: the dragnet throttle at
-- 0 (today's one introduction made). W7a adds the P1 and uncorroborated
-- P0 report steps here.
CREATE OR REPLACE FUNCTION private.dating_generation_removed(p_user uuid, p_at timestamptz, p_cfg jsonb)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.dating_throttled(p_user)
     AND (SELECT count(*) FROM public.dating_introductions AS i
           WHERE p_user IN (i.user_low_id, i.user_high_id)
             AND i.created_at > p_at - interval '20 hours' AND i.created_at <= p_at)
         >= coalesce((p_cfg #>> '{dragnet,throttled_daily_max}')::int, 1);
$$;

-- =====================================================================
-- 4. Fairness (§5.9): per country and audited cohort, introductions per
--    active person and the mutual-interest rate over 4 weeks; a cohort
--    only at n >= 50 (smaller ones are left out, never merged); a flag
--    below 0.8 of the country's rate, or when the top 10% receive more
--    than 25% of the introductions. Gender is decrypted inside the job
--    into a temp table dropped at commit; only aggregates leave. Mondays.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.dating_fairness_weekly(p_week date DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_week constant date := coalesce(p_week, date_trunc('week', now())::date);
  v_from constant timestamptz := v_week::timestamptz - interval '28 days';
  v_to constant timestamptz := v_week::timestamptz;
  v_c record;
  v_k record;
  v_rate numeric;
  v_mutual numeric;
  v_n integer;
  v_total bigint;
  v_top bigint;
  v_rows integer := 0;
  v_identity jsonb;
  r record;
BEGIN
  DROP TABLE IF EXISTS pg_temp.dating_fair_people;
  CREATE TEMP TABLE dating_fair_people (
    user_id uuid PRIMARY KEY,
    country text NOT NULL,
    region text,
    age_band text,
    gender_group text,
    intros integer NOT NULL,
    matched integer NOT NULL
  ) ON COMMIT DROP;
  FOR r IN
    SELECT p.user_id, p.country_code::text AS country, p.region_code, s.identity_enc, public.account_age(p.user_id) AS age
      FROM public.dating_profiles AS p
      JOIN public.dating_enrollments AS e ON e.user_id = p.user_id AND e.state = 'active'
      LEFT JOIN public.dating_profile_sensitive AS s ON s.user_id = p.user_id
     WHERE p.country_code IS NOT NULL
  LOOP
    BEGIN
      v_identity := private.dating_field_decrypt(r.identity_enc);
    EXCEPTION WHEN raise_exception THEN
      v_identity := NULL;
    END;
    INSERT INTO pg_temp.dating_fair_people
    VALUES (r.user_id, r.country, r.region_code,
            CASE WHEN r.age < 25 THEN '18_24' WHEN r.age < 35 THEN '25_34' WHEN r.age < 45 THEN '35_44'
                 WHEN r.age < 55 THEN '45_54' WHEN r.age >= 55 THEN '55_plus' END,
            CASE v_identity ->> 'identity' WHEN 'woman' THEN 'woman' WHEN 'man' THEN 'man'
                 WHEN 'non_binary' THEN 'other' END,
            (SELECT count(*) FROM public.dating_introductions AS i
              WHERE r.user_id IN (i.user_low_id, i.user_high_id) AND i.created_at >= v_from AND i.created_at < v_to),
            (SELECT count(*) FROM public.dating_introductions AS i
              WHERE r.user_id IN (i.user_low_id, i.user_high_id) AND i.created_at >= v_from AND i.created_at < v_to
                AND i.state = 'matched'));
  END LOOP;
  FOR v_c IN SELECT f.country, count(*) AS n, sum(f.intros) AS intros, sum(f.matched) AS matched
               FROM pg_temp.dating_fair_people AS f GROUP BY f.country HAVING count(*) >= 50 ORDER BY f.country LOOP
    v_rate := v_c.intros::numeric / v_c.n;
    v_mutual := CASE WHEN v_c.intros > 0 THEN v_c.matched::numeric / v_c.intros END;
    FOR v_k IN
      SELECT x.key, count(*) AS n, sum(x.intros) AS intros, sum(x.matched) AS matched
        FROM (SELECT 'region:' || f.region AS key, f.intros, f.matched FROM pg_temp.dating_fair_people AS f
               WHERE f.country = v_c.country AND f.region IS NOT NULL
              UNION ALL
              SELECT 'age:' || f.age_band, f.intros, f.matched FROM pg_temp.dating_fair_people AS f
               WHERE f.country = v_c.country AND f.age_band IS NOT NULL
              UNION ALL
              SELECT 'gender:' || f.gender_group, f.intros, f.matched FROM pg_temp.dating_fair_people AS f
               WHERE f.country = v_c.country AND f.gender_group IS NOT NULL) AS x
       GROUP BY x.key HAVING count(*) >= 50
    LOOP
      INSERT INTO public.dating_fairness_reports AS fr
        (week, country_code, cohort_key, active_bucket, introductions_per_active, mutual_rate, flagged)
      VALUES (v_week, v_c.country, v_k.key,
              CASE WHEN v_k.n >= 500 THEN '500+' WHEN v_k.n >= 100 THEN '100–499' ELSE '50–99' END,
              round(v_k.intros::numeric / v_k.n, 4),
              CASE WHEN v_k.intros > 0 THEN round(v_k.matched::numeric / v_k.intros, 4) END,
              v_k.intros::numeric / v_k.n < 0.8 * v_rate
                OR (v_mutual IS NOT NULL AND v_k.intros > 0 AND v_k.matched::numeric / v_k.intros < 0.8 * v_mutual))
      ON CONFLICT (week, country_code, cohort_key) DO UPDATE
        SET active_bucket = EXCLUDED.active_bucket, introductions_per_active = EXCLUDED.introductions_per_active,
            mutual_rate = EXCLUDED.mutual_rate, flagged = EXCLUDED.flagged, created_at = now();
      v_rows := v_rows + 1;
    END LOOP;
    -- The top 10% of people by introductions, against the country's total.
    v_total := v_c.intros;
    SELECT coalesce(sum(t.intros), 0) INTO v_top
      FROM (SELECT f.intros FROM pg_temp.dating_fair_people AS f WHERE f.country = v_c.country
             ORDER BY f.intros DESC LIMIT greatest(1, (v_c.n / 10)::int)) AS t;
    INSERT INTO public.dating_fairness_reports AS fr
      (week, country_code, cohort_key, active_bucket, introductions_per_active, mutual_rate, flagged)
    VALUES (v_week, v_c.country, 'top_decile',
            CASE WHEN v_c.n >= 500 THEN '500+' WHEN v_c.n >= 100 THEN '100–499' ELSE '50–99' END,
            CASE WHEN v_total > 0 THEN round(v_top::numeric / v_total, 4) ELSE 0 END, NULL,
            v_total > 0 AND v_top::numeric / v_total > 0.25)
    ON CONFLICT (week, country_code, cohort_key) DO UPDATE
      SET active_bucket = EXCLUDED.active_bucket, introductions_per_active = EXCLUDED.introductions_per_active,
          flagged = EXCLUDED.flagged, created_at = now();
    v_rows := v_rows + 1;
  END LOOP;
  PERFORM private.bump_metric_internal('dating.fairness.flagged')
     FROM public.dating_fairness_reports AS fr WHERE fr.week = v_week AND fr.flagged;
  RETURN v_rows;
END;
$$;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dating-fairness-weekly') THEN
    PERFORM cron.unschedule('dating-fairness-weekly');
  END IF;
  PERFORM cron.schedule('dating-fairness-weekly', '17 4 * * 1', 'SELECT public.dating_fairness_weekly()');
END $$;

-- =====================================================================
-- 5. Other countries (§2.6, §3.12; carry 17): the countries the person
--    may open to, each on or off. Eligible: verified, the age check
--    holding, an account 14+ days old. Never a country whose same-gender
--    rule refuses the person's answers (the writer would refuse it).
-- =====================================================================
CREATE OR REPLACE FUNCTION public.get_dating_abroad_options()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_p public.dating_profiles;
  v_on text[];
  v_plain boolean;
  v_identity jsonb;
  v_seeking jsonb;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  SELECT * INTO v_p FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  IF v_p.user_id IS NULL OR v_p.country_code IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_eligible');
  END IF;
  SELECT d.open_abroad::text[] INTO v_on FROM public.dating_preferences AS d WHERE d.user_id = v_user;
  BEGIN
    SELECT private.dating_field_decrypt(s.identity_enc), private.dating_field_decrypt(s.seeking_enc)
      INTO v_identity, v_seeking FROM public.dating_profile_sensitive AS s WHERE s.user_id = v_user;
    v_plain := coalesce(private.dating_profile_plain(v_identity, v_seeking), false);
  EXCEPTION WHEN raise_exception THEN
    v_plain := false;
  END;
  RETURN jsonb_build_object(
    'ok', true,
    'eligible', v_p.verification_state = 'verified' AND coalesce(public.dating_age_gate_holds(v_user), false)
                AND coalesce((SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) <= now() - interval '14 days', false),
    'countries', coalesce((
      SELECT jsonb_agg(jsonb_build_object('code', c.code, 'on', c.code = ANY (coalesce(v_on, '{}'))) ORDER BY c.code)
        FROM unnest(private.dating_open_countries()) AS c(code)
       WHERE c.code IS DISTINCT FROM v_p.country_code::text
         AND (v_plain OR private.dating_same_gender_on(c.code))), '[]'::jsonb));
END;
$$;

-- =====================================================================
-- 6. Functions re-created from their LIVE bodies (Spec 2 W5c lines only).
-- =====================================================================
```

Create `$D/mig_T8_tail.sql` with exactly:

```sql

-- =====================================================================
-- 7. Grants (re-asserted by the twin). The queue and the reports are the
--    service role's (W7b's console), never a client's; the signals and the
--    fairness job are the database's own (the job decrypts, S-4); the
--    Other countries read is the app's.
-- =====================================================================
REVOKE ALL ON public.dating_moderation_cases, public.dating_fairness_reports FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.dating_moderation_cases, public.dating_fairness_reports TO service_role;
REVOKE ALL ON FUNCTION private.dating_open_signal_case(uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_first_messages(uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_dragnet_holds(uuid, timestamptz, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_device_accounts_hold(uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_run_signals(timestamptz, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_throttled(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_generation_removed(uuid, timestamptz, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_fairness_weekly(date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_dating_abroad_options() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_abroad_options() TO authenticated;
COMMIT;
```

Create `$D/build_mig_T8.py` with exactly:

```python
#!/usr/bin/env python3
# Spec 2 W5c: builds supabase/migrations/20261119120000_dating_v2_signals.sql
# from mig_T8_head.sql, the functions below re-created from their LIVE
# bodies (saved to before_w5c/) with only the lines marked "-- Spec 2 W5c"
# changed, and mig_T8_tail.sql. Every anchor must occur exactly once.
import pathlib
D = pathlib.Path('.superpowers/sdd/2026-11-19-spec2-w5')
OUT = pathlib.Path('supabase/migrations/20261119120000_dating_v2_signals.sql')

def live(sig):
    return (D / 'before_w5c' / f'{sig}.sql').read_text().rstrip('\n')

M = '-- Spec 2 W5c'
FNS = []

# 1. §5.10: a person under an open dragnet case gets at most one a day.
FNS.append(('private.dating_capacity(uuid,timestamp with time zone,jsonb)', [
  ("""      (p_cfg ->> 'daily_new_max')::int
""",
   f"""      CASE WHEN private.dating_throttled(p_user) {M} (§5.10): the dragnet throttle
           THEN least((p_cfg ->> 'daily_new_max')::int, coalesce((p_cfg #>> '{{dragnet,throttled_daily_max}}')::int, 1)) {M}
           ELSE (p_cfg ->> 'daily_new_max')::int END {M}
""")]))

# 2. §5.2 15: removed from generation for now (the throttle at 0; W7a adds
#    the report steps).
FNS.append(('private.dating_person_current(uuid,timestamp with time zone,jsonb)', [
  ("""    AND coalesce(private.dating_cool_off_ends_at(p_user) <= private.dating_first_drop_at(p_user, p_at), false);""",
   f"""    AND coalesce(private.dating_cool_off_ends_at(p_user) <= private.dating_first_drop_at(p_user, p_at), false) {M}: and
    AND NOT coalesce(private.dating_generation_removed(p_user, p_at, p_cfg), false); {M} (§5.2 15)""")]))

# 3. The signals run before the partitions, so this run's throttle holds.
FNS.append(('public.run_dating_generation_tick(timestamp with time zone,text)', [
  ("""  IF v_version IS NULL THEN
    RETURN private.dating_generation_skip('no_active_config');
  END IF;
  FOR v_c IN""",
   f"""  IF v_version IS NULL THEN
    RETURN private.dating_generation_skip('no_active_config');
  END IF;
  PERFORM private.dating_run_signals(p_now, v_cfg); {M} (§5.10): before any partition
  FOR v_c IN""")]))

parts = []
for sig, pairs in FNS:
    body = live(sig)
    for old, new in pairs:
        n = body.count(old)
        assert n == 1, f'{sig}: anchor occurs {n} times: {old[:60]!r}'
        body = body.replace(old, new)
    parts.append(body + ';\n')
OUT.write_text((D / 'mig_T8_head.sql').read_text() + '\n'.join(parts) + '\n' + (D / 'mig_T8_tail.sql').read_text())
print(f'{OUT}: {len(FNS)} functions re-created')
```

Create `supabase/migrations/20261119120010_dating_v2_signals_grants.sql` with exactly:

```sql
-- Spec 2 W5c: grants for 20261119120000_dating_v2_signals.sql. The queue and
-- the fairness reports are the service role's (W7b's console), never a
-- client's; the signal helpers and the fairness job are the database's
-- own (the job decrypts, S-4); the Other countries read is the app's.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.dating_moderation_cases, public.dating_fairness_reports FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.dating_moderation_cases, public.dating_fairness_reports TO service_role;
REVOKE ALL ON FUNCTION private.dating_open_signal_case(uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_first_messages(uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_dragnet_holds(uuid, timestamptz, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_device_accounts_hold(uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_run_signals(timestamptz, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_throttled(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_generation_removed(uuid, timestamptz, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_fairness_weekly(date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_dating_abroad_options() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_abroad_options() TO authenticated;
COMMIT;
```

- [ ] **Step 4: Build, apply, run**

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5
python3 -I $D/build_mig_T8.py
for f in supabase/migrations/20261119120000_dating_v2_signals.sql supabase/migrations/20261119120010_dating_v2_signals_grants.sql; do
  for run in 1 2; do psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $f > /dev/null 2> $D/apply_err.txt; rc=$?; echo "$(basename $f) run $run exit=$rc"; grep -v NOTICE $D/apply_err.txt || true; done
done
python3 -I $D/marked_diff.py $D/before_w5c attune_spec3a 'Spec 2 W5c'
python3 -I $D/grants_line.py supabase/migrations/20261119110010_dating_v2_today_grants.sql 'Spec 2 W5c: signals (twin of 20261119120000)' supabase/migrations/20261119120010_dating_v2_signals_grants.sql
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_matching_contracts.sql 2>&1 | grep -v 'skipping' | tail -1
```

Expected: `supabase/migrations/20261119120000_dating_v2_signals.sql: 3 functions re-created`; four `exit=0`; three `… OK` lines from `marked_diff.py` (`private.dating_capacity(…)`, `private.dating_person_current(…)`, `public.run_dating_generation_tick(…)`); `local_pg_grants.sql: one \i block added`; `NOTICE:  dating_v2_matching_contracts: all held`.

- [ ] **Step 5: The canary; the suite; the races**

Create `$D/edit_tests_T8.py` with exactly:

```python
# Spec 2 W5c Task 8: the canary takes the queue, the fairness reports and
# W5c's functions (the queue and the reports are the service role's, never
# a client's; the Other countries read is the app's; the rest the
# database's own).
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anchor import edit

edit('supabase/tests/dating_rls_canary.sql', [
  ("""-- W5a Task 2: generation is cron's (postgres), no API role's.
""",
   """-- W5c (migration 3): the queue and the fairness reports (the console's,
-- W7b, through the service role; no client); the signals and the fairness
-- job are the database's own; the Other countries read is the app's.
INSERT INTO allowed_rel (name, authenticated, service_dml) VALUES
  ('dating_moderation_cases', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_fairness_reports', '', 'DELETE,INSERT,SELECT,UPDATE');
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('get_dating_abroad_options()', 'authenticated', ''),
  ('dating_fairness_weekly(date)', '', ''),
  ('private.dating_open_signal_case(uuid,text,text)', '', ''),
  ('private.dating_first_messages(uuid,timestamp with time zone)', '', ''),
  ('private.dating_dragnet_holds(uuid,timestamp with time zone,jsonb)', '', ''),
  ('private.dating_device_accounts_hold(uuid,timestamp with time zone)', '', ''),
  ('private.dating_run_signals(timestamp with time zone,jsonb)', '', ''),
  ('private.dating_throttled(uuid)', '', ''),
  ('private.dating_generation_removed(uuid,timestamp with time zone,jsonb)', '', '');
-- W5a Task 2: generation is cron's (postgres), no API role's.
"""),
], 'canary: W5c rows')
```

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5
python3 -I $D/edit_tests_T8.py
$D/suite.sh attune_spec3a > $D/sql-after-T8.txt; echo "$(grep -c '^PASS' $D/sql-after-T8.txt) PASS, $(grep -c '^FAIL' $D/sql-after-T8.txt) FAIL"
diff <(grep FAIL $D/sql-baseline.txt) <(grep FAIL $D/sql-after-T8.txt) && echo same-fails
```

Expected: `supabase/tests/dating_rls_canary.sql: 1 edit(s) (canary: W5c rows)`; `160 PASS, 14 FAIL`; `same-fails`.

- [ ] **Step 6: The mutants**

Create `$D/mut_T8.py` with exactly:

```python
# Spec 2 W5c Task 8 mutants (mutate.py on 20261119120000_dating_v2_signals.sql).
M = '-- Spec 2 W5c'
MUTS = {
  'dragnet_unknown_holds': ("                  AND v_first <= v_matches * coalesce((p_cfg #>> '{dragnet,first_message_ratio}')::numeric, 0.2), false);",
                            "                  AND v_first <= v_matches * coalesce((p_cfg #>> '{dragnet,first_message_ratio}')::numeric, 0.2), true);"),
  'dragnet_ratio_ignored': ("     OR v_interested < v_intros * coalesce((p_cfg #>> '{dragnet,interested_ratio}')::numeric, 0.9) THEN", "     THEN"),
  'throttle_ignored': (f"      CASE WHEN private.dating_throttled(p_user) {M} (§5.10): the dragnet throttle", f"      CASE WHEN false {M} (§5.10): the dragnet throttle"),
  'filter15_ignored': (f"    AND NOT coalesce(private.dating_generation_removed(p_user, p_at, p_cfg), false); {M} (§5.2 15)", "    ;"),
  'tick_skips_signals': (f"  PERFORM private.dating_run_signals(p_now, v_cfg); {M} (§5.10): before any partition\n", ""),
  'device_window_ignored': ("       AND mine.verified_at > p_at - interval '30 days' AND other.verified_at > p_at - interval '30 days');", ");"),
  'signal_reads_country': ("  IF v_intros < coalesce((p_cfg #>> '{dragnet,min_intros}')::int, 15)",
                           "  IF (SELECT p.country_code FROM public.dating_profiles AS p WHERE p.user_id = p_user) IS NULL\n     OR v_intros < coalesce((p_cfg #>> '{dragnet,min_intros}')::int, 15)"),
  'fairness_small_cohort': ("       GROUP BY x.key HAVING count(*) >= 50", "       GROUP BY x.key HAVING count(*) >= 5"),
  'fairness_unflagged': ("              v_k.intros::numeric / v_k.n < 0.8 * v_rate", "              v_k.intros::numeric / v_k.n < 0 * v_rate"),
  'fairness_top_ignored': ("            v_total > 0 AND v_top::numeric / v_total > 0.25)", "            v_total > 0 AND v_top::numeric / v_total > 2.5)"),
  'abroad_same_gender_ignored': ("         AND (v_plain OR private.dating_same_gender_on(c.code))), '[]'::jsonb));", "         ), '[]'::jsonb));"),
  'abroad_young_eligible': ("                AND coalesce((SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) <= now() - interval '14 days', false),", ","),
  'abroad_any_phone': ("  IF public.dating_require_trusted_device() IS NOT TRUE THEN\n    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');\n  END IF;\n  SELECT * INTO v_p FROM public.dating_profiles AS p WHERE p.user_id = v_user;\n  IF v_p.user_id IS NULL OR v_p.country_code IS NULL THEN",
                       "  SELECT * INTO v_p FROM public.dating_profiles AS p WHERE p.user_id = v_user;\n  IF v_p.user_id IS NULL OR v_p.country_code IS NULL THEN"),
}
```

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5
python3 -I $D/mutate.py supabase/migrations/20261119120000_dating_v2_signals.sql supabase/tests/dating_v2_matching_contracts.sql $D/mut_T8.py $D/mut supabase/migrations/20261119120010_dating_v2_signals_grants.sql > $D/mut_T8.txt 2>&1
grep -c 'CONTRACT VIOLATED' $D/mut_T8.txt; grep -v 'CONTRACT VIOLATED' $D/mut_T8.txt
```

Expected: `13`, nothing else. Among them: `dragnet_unknown_holds: … the dragnet fired without its first-message input (Ruling R-14)`, `filter15_ignored: … a throttled person at 0 stayed in generation (filter 15): true:true`, `signal_reads_country: … a signal reads a country, region, network, phone or name: dating_dragnet_holds`, `fairness_small_cohort: … the fairness rows are not the n >= 50 cohorts with their flags: …`, `abroad_same_gender_ignored: … Other countries: not on after turning on, eligible under 14 days, a same-gender-off country offered to a not-plain profile, or read from another phone`.

- [ ] **Step 7: Record the tree**

Do not commit; record the tree in the report.

### Task 9: "Never introduce me to these numbers" (§3.12, §2.8, §6.1; carry 16; R-35; DV sign-off of the copy gates production)

**Files:**
- Create: `lib/features/dating/settings/never_introduce_screen.dart`, `test/features/dating/settings/never_introduce_test.dart`, `test/features/dating/settings/goldens/never_introduce.{scale1.0,scale1.3,scale2.0,rtl}.png`, `$D/{edit_T9.py, arb_fragment_T9.txt, mut_T9.py}`
- Modify: `lib/features/dating/data/dating_never_introduce.dart`, `test/features/dating/support/dating_fakes.dart`, `lib/features/dating/routes/dating_routes.dart`, `lib/features/dating/settings/dating_settings_screen.dart`, `test/architecture/text_scale_routes_test.dart`, `test/features/dating/settings/dating_settings_rows_test.dart` (W3 checked the row was absent), the four `test/features/dating/settings/goldens/dating_settings_bottom.*.png` (the new row is in the bottom of settings), the ARB

**Interfaces:**
- Consumes: W4's `DatingNeverIntroduceGateway.list()`, `datingNeverIntroduceGatewayProvider`, `datingNeverIntroduceProvider`, `DatingReverifyLine`; W1's `add_dating_never_introduce(p_idempotency_key, p_phone_e164, p_label)` and `remove_dating_never_introduce(p_id)`; `DatingActionKeys`; `datingOnlineProvider`.
- Produces: `DatingNeverIntroduceGateway.add(key, phoneE164, label)` and `.remove(id)`; `/dating/never-introduce` (`datingNeverIntroduce`); `DatingNeverIntroduceScreen`.

- [ ] **Step 1: The copy (DV sign-off before production)**

Create `$D/arb_fragment_T9.txt` with exactly:

```text
  "dating_neverTitle": "Never introduce me to these numbers",
  "@dating_neverTitle": {"description": "Spec 2 §3.12 title and the settings row. DV specialist signs the never-introduce copy (W5 gate)."},
  "dating_neverBody": "Add a phone number and Attune will never introduce you to the person who uses it, now or later. They're never told.",
  "@dating_neverBody": {"description": "Spec 2 §3.12. DV specialist sign-off (W5 gate)."},
  "dating_neverCode": "We keep a code made from the number, not the number itself.",
  "@dating_neverCode": {"description": "Spec 2 §3.12. DV specialist sign-off (W5 gate)."},
  "dating_neverNumber": "Phone number",
  "@dating_neverNumber": {"description": "Spec 2 §3.12 the number field's label (after the country code). Plan copy."},
  "dating_neverCountryCode": "Country code {code}",
  "@dating_neverCountryCode": {"description": "Spec 2 §3.12, §3.15 the labelled country-code picker.", "placeholders": {"code": {"type": "String"}}},
  "dating_neverLabel": "A name only you'll see (optional)",
  "@dating_neverLabel": {"description": "Spec 2 §3.12 (20 characters)."},
  "dating_neverAdd": "Add",
  "@dating_neverAdd": {"description": "Spec 2 §3.12 the add button. Plan copy."},
  "dating_neverAdded": "Added.",
  "@dating_neverAdded": {"description": "Spec 2 §3.12: the same answer whatever the number."},
  "dating_neverRow": "{label} · ending {digits}",
  "@dating_neverRow": {"description": "Spec 2 §3.12 a list row.", "placeholders": {"label": {"type": "String"}, "digits": {"type": "String"}}},
  "dating_neverRowNoLabel": "Ending {digits}",
  "@dating_neverRowNoLabel": {"description": "Spec 2 §3.12 a list row with no name. Plan copy.", "placeholders": {"digits": {"type": "String"}}},
  "dating_neverRemove": "Remove",
  "@dating_neverRemove": {"description": "Spec 2 §3.12 a row's action."},
  "dating_neverRemoveLabel": "Remove {row}",
  "@dating_neverRemoveLabel": {"description": "Spec 2 §3.15: the Remove button's spoken label names its row. Plan copy.", "placeholders": {"row": {"type": "String"}}},
  "dating_neverCheckNumber": "Check the number and try again.",
  "@dating_neverCheckNumber": {"description": "Spec 2 W5c: a number the server can't read (never says whether anyone uses it). Plan copy, DV review."},
  "dating_neverCheckLabel": "Use up to 20 letters, with no numbers.",
  "@dating_neverCheckLabel": {"description": "Spec 2 W5c: the name was refused (too long, a number, an invisible mark). Plan copy."},
  "dating_neverLimit": "You can add up to 50 numbers.",
  "@dating_neverLimit": {"description": "Spec 2 §3.12 'Up to 50.' Plan copy."}
```

```bash
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py .superpowers/sdd/2026-11-19-spec2-w5/arb_fragment_T9.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package > /dev/null; echo gen=$?
```

Expected: `added 15 keys`; `gen=0`.

- [ ] **Step 2: Write the failing tests**

Create `test/features/dating/settings/never_introduce_test.dart` with exactly:

```dart
// Spec 2 W5c (§3.12, §3.15; carry 16; D8): Never introduce me. "Added."
// for any number (the add from any phone); the country code and the number
// as E.164; the name optional, at most 20; no field lets the keyboard
// learn; rows read "{label} · ending {digits}" with Remove; a kept entry is
// only counted; a refusal in its own words (the re-check for Remove on
// another phone); offline the add waits; the next account sees nothing.
import 'package:attune/features/dating/data/dating_never_introduce.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/settings/never_introduce_screen.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_private_keyboard.dart';
import '../support/dating_shell.dart';

Future<void> tap(WidgetTester t, Finder finder) async {
  await tapInReach(t, finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

const _list = DatingNeverIntroduceList(
  ok: true,
  items: [
    DatingNeverIntroduceItem(id: 'n1', label: 'Kwame', lastTwo: '42'),
    DatingNeverIntroduceItem(id: 'n2', lastTwo: '07'),
  ],
  keptCount: 2,
);

void main() {
  final loc = AppLocalizationsEn();

  Future<(DatingShell, FakeNeverIntroduce)> open(
    WidgetTester t, {
    bool online = true,
  }) async {
    final fake = FakeNeverIntroduce(_list);
    final shell = await pumpDatingShell(
      t,
      initial: DatingPaths.neverIntroduce,
      online: online,
      overrides: [datingNeverIntroduceGatewayProvider.overrideWithValue(fake)],
    );
    return (shell, fake);
  }

  testWidgets(
    'the copy, the rows, the kept count; no field learns what is typed',
    (t) async {
      await open(t);
      for (final line in [
        loc.dating_neverTitle,
        loc.dating_neverBody,
        loc.dating_neverCode,
      ]) {
        expect(find.text(line), findsOneWidget);
      }
      expect(find.text(loc.dating_neverRow('Kwame', '42')), findsOneWidget);
      expect(find.text(loc.dating_neverRowNoLabel('07')), findsOneWidget);
      expect(find.text(loc.dating_neverIntroduceKept(2)), findsOneWidget);
      expectPrivateKeyboard(t, find.byType(DatingNeverIntroduceScreen));
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('dating_never_label')))
            .maxLength,
        20,
      );
    },
  );

  testWidgets(
    '"Added." for any number, sent as E.164 with the name; fields cleared',
    (t) async {
      final (_, fake) = await open(t);
      await t.enterText(
        find.byKey(const ValueKey('dating_never_number')),
        '024 123 4567',
      );
      await t.enterText(
        find.byKey(const ValueKey('dating_never_label')),
        'Kofi',
      );
      await t.pump();
      await tap(t, find.text(loc.dating_neverAdd));
      expect(fake.adds.single.$2, '+2330241234567');
      expect(fake.adds.single.$3, 'Kofi');
      expect(find.text(loc.dating_neverAdded), findsOneWidget);
      expect(find.text('024 123 4567'), findsNothing);
      fake.answer = const DatingWrite(ok: true);
      await t.enterText(
        find.byKey(const ValueKey('dating_never_number')),
        '0241234567',
      );
      await t.pump();
      await tap(t, find.text(loc.dating_neverAdd));
      expect(find.text(loc.dating_neverAdded), findsOneWidget);
    },
  );

  testWidgets(
    'refusals in their own words; Remove on another phone asks for the check',
    (t) async {
      final (_, fake) = await open(t);
      for (final (w, line) in [
        (
          const DatingWrite(ok: false, reason: 'invalid', field: 'phone'),
          loc.dating_neverCheckNumber,
        ),
        (
          const DatingWrite(ok: false, reason: 'invalid', field: 'label'),
          loc.dating_neverCheckLabel,
        ),
        (
          const DatingWrite(ok: false, reason: 'limit_reached'),
          loc.dating_neverLimit,
        ),
        (const DatingWrite(ok: false, reason: 'busy'), loc.dating_busy),
        (
          const DatingWrite(ok: false, reason: 'failed'),
          loc.dating_errorGeneric,
        ),
      ]) {
        fake.answer = w;
        await t.enterText(
          find.byKey(const ValueKey('dating_never_number')),
          '0241234567',
        );
        await t.pump();
        await tap(t, find.text(loc.dating_neverAdd));
        expect(find.text(line), findsOneWidget, reason: '${w.reason}');
      }
      fake.answer = const DatingWrite(ok: false, reason: 'reverify_device');
      await tap(
        t,
        find.bySemanticsLabel(
          loc.dating_neverRemoveLabel(loc.dating_neverRow('Kwame', '42')),
        ),
      );
      expect(fake.removes, ['n1']);
      expect(find.text(loc.dating_sectionReverify), findsOneWidget);
    },
  );

  testWidgets('offline the add waits; the next account sees nothing typed', (
    t,
  ) async {
    final (shell, fake) = await open(t, online: false);
    await t.enterText(
      find.byKey(const ValueKey('dating_never_number')),
      '0241234567',
    );
    await t.pump();
    await tap(t, find.text(loc.dating_neverAdd));
    expect(fake.adds, isEmpty);
    expect(find.text(loc.dating_offline), findsOneWidget);
    shell.container.read(datingTestAccount.notifier).state = 'kwame';
    await t.pumpAndSettle();
    expect(find.text('0241234567'), findsNothing);
  });

  testWidgets('goldens and guidelines', (t) async {
    await expectFlowGoldens(
      t,
      'never_introduce',
      () => const DatingNeverIntroduceScreen(),
      overrides: [
        ...datingShellOverrides(),
        datingNeverIntroduceGatewayProvider.overrideWithValue(
          FakeNeverIntroduce(_list),
        ),
      ],
    );
    await expectFlowGuidelines(t);
  });
}
```

```bash
flutter test --no-pub test/features/dating/settings/never_introduce_test.dart 2>&1 | tr '\r' '\n' | grep -m1 -o "Error: Error when reading '[^']*'"
```

Expected: `Error: Error when reading 'lib/features/dating/settings/never_introduce_screen.dart'`.

- [ ] **Step 3: Write the screen and wire it**

Create `lib/features/dating/settings/never_introduce_screen.dart` with exactly:

```dart
// Spec 2 W5c (§3.12, §3.15; carry 16; Task 5 C-1 and I-6 rulings): "Never
// introduce me to these numbers". A country code and a number, and a name
// only the person sees; "Added." whatever the number (it can't be used to
// test whether someone uses Attune). The rows show a name and the last two
// digits, each with Remove; entries kept from before are never shown, only
// counted, and only Leave Dating removes them. Adding works from any phone
// (it only reduces exposure); removing is the server's to check. No field
// lets the keyboard learn what is typed; nothing is kept on the phone.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/log_in/presentation/widgets/phone_country_picker_sheet.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_never_introduce.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/lock/dating_sheets.dart';
import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/features/dating/verify/dating_reverify_line.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingNeverIntroduceScreen extends ConsumerStatefulWidget {
  const DatingNeverIntroduceScreen({super.key});

  @override
  ConsumerState<DatingNeverIntroduceScreen> createState() =>
      _DatingNeverIntroduceScreenState();
}

class _DatingNeverIntroduceScreenState
    extends ConsumerState<DatingNeverIntroduceScreen> {
  final _keys = DatingActionKeys();
  final _number = TextEditingController();
  final _label = TextEditingController();
  PhoneCountry _country = PhoneCountries.ghana;
  bool _adding = false;
  DatingWrite? _added;
  DatingWrite? _removed;
  final _removing = <String>{};

  @override
  void initState() {
    super.initState();
    // D8: the next account sees nothing typed or answered for this one.
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (previous == next || !mounted) return;
      _number.clear();
      _label.clear();
      setState(() {
        _adding = false;
        _added = null;
        _removed = null;
        _removing.clear();
      });
    });
  }

  @override
  void dispose() {
    _number.dispose();
    _label.dispose();
    super.dispose();
  }

  String get _e164 =>
      '+${_country.dialCode.replaceAll(RegExp(r'\D'), '')}'
      '${_number.text.replaceAll(RegExp(r'\D'), '')}';

  Future<void> _add() async {
    if (_adding || _number.text.trim().isEmpty) return;
    final account = ref.read(datingAccountProvider);
    final label = _label.text.trim();
    final phone = _e164;
    setState(() {
      _adding = true;
      _added = null;
    });
    final w = await ref
        .read(datingNeverIntroduceGatewayProvider)
        .add(
          _keys.keyFor('add', '$account|$phone|$label'),
          phone,
          label.isEmpty ? null : label,
        );
    _keys.settle('add', reason: w.reason);
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    if (w.ok) {
      _number.clear();
      _label.clear();
      ref.invalidate(datingNeverIntroduceProvider(account));
    }
    setState(() {
      _adding = false;
      _added = w;
    });
  }

  Future<void> _remove(DatingNeverIntroduceItem item) async {
    if (!_removing.add(item.id)) return;
    final account = ref.read(datingAccountProvider);
    setState(() => _removed = null);
    final w = await ref
        .read(datingNeverIntroduceGatewayProvider)
        .remove(item.id);
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    if (w.ok) ref.invalidate(datingNeverIntroduceProvider(account));
    setState(() {
      _removing.remove(item.id);
      _removed = w.ok ? null : w;
    });
  }

  Future<void> _pickCountry() => showModalBottomSheet<void>(
    context: context,
    routeSettings: datingSheetSettings('never-country'),
    isScrollControlled: true,
    builder:
        (sheet) => DatingSheetTracker(
          child: AllowLargeText(
            child: SizedBox(
              height: MediaQuery.of(sheet).size.height * 0.8,
              child: PhoneCountryPickerSheet(
                selectedCountry: _country,
                onCountrySelected: (c) {
                  setState(() => _country = c);
                  Navigator.of(sheet).pop();
                },
              ),
            ),
          ),
        ),
  );

  Widget _answer(AppLocalizations loc, DatingWrite w) => switch (w.reason) {
    null => DatingCalmLine(loc.dating_neverAdded),
    'reverify_device' => const DatingReverifyLine(),
    'busy' => DatingCalmLine(loc.dating_busy),
    'feature_unavailable' ||
    'not_eligible' => DatingCalmLine(loc.dating_sectionUnavailable),
    'rate_limited' => FlowErrorLine(
      text: loc.dating_errorRateLimited,
      liveRegion: true,
    ),
    'limit_reached' => FlowErrorLine(
      text: loc.dating_neverLimit,
      liveRegion: true,
    ),
    'invalid' when w.field == 'label' => FlowErrorLine(
      text: loc.dating_neverCheckLabel,
      liveRegion: true,
    ),
    'invalid' => FlowErrorLine(
      text: loc.dating_neverCheckNumber,
      liveRegion: true,
    ),
    _ => FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
  };

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final account = ref.watch(datingAccountProvider);
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final read = ref.watch(datingNeverIntroduceProvider(account));
    final list = read.valueOrNull;
    // A Dating field never lets the keyboard learn or suggest (W3 M-12).
    InputDecoration field(String label) =>
        InputDecoration(labelText: label, border: const OutlineInputBorder());
    return AllowLargeText(
      child: Scaffold(
        appBar: AppBar(title: Text(loc.dating_neverTitle)),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!online) DatingCalmLine(loc.dating_offline),
                Text(loc.dating_neverBody, style: theme.textTheme.bodyLarge),
                const SizedBox(height: Spacing.sm),
                Text(loc.dating_neverCode, style: theme.textTheme.bodyMedium),
                const SizedBox(height: Spacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      button: true,
                      label: loc.dating_neverCountryCode(_country.dialCode),
                      excludeSemantics: true,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(72, 56),
                        ),
                        onPressed: _pickCountry,
                        child: Text(_country.dialCode),
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('dating_never_number'),
                        controller: _number,
                        keyboardType: TextInputType.phone,
                        enableSuggestions: false,
                        autocorrect: false,
                        enableIMEPersonalizedLearning: false,
                        decoration: field(loc.dating_neverNumber),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.sm),
                TextField(
                  key: const ValueKey('dating_never_label'),
                  controller: _label,
                  maxLength: 20,
                  enableSuggestions: false,
                  autocorrect: false,
                  enableIMEPersonalizedLearning: false,
                  decoration: field(loc.dating_neverLabel),
                ),
                FlowPrimaryButton(
                  label: loc.dating_neverAdd,
                  busy: _adding,
                  onPressed:
                      online && _number.text.trim().isNotEmpty ? _add : null,
                ),
                if (_added case final w?) _answer(loc, w),
                const SizedBox(height: Spacing.md),
                if (list != null && !list.ok)
                  switch (list.reason) {
                    'reverify_device' => const DatingReverifyLine(),
                    'busy' => DatingCalmLine(loc.dating_busy),
                    _ => FlowErrorLine(
                      text: loc.dating_errorGeneric,
                      liveRegion: true,
                    ),
                  },
                for (final item
                    in list?.items ?? const <DatingNeverIntroduceItem>[])
                  _row(loc, item, online),
                if (_removed case final w?) _answer(loc, w),
                if ((list?.keptCount ?? 0) > 0)
                  DatingCalmLine(
                    loc.dating_neverIntroduceKept(list!.keptCount),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(
    AppLocalizations loc,
    DatingNeverIntroduceItem item,
    bool online,
  ) {
    final text =
        item.label == null
            ? loc.dating_neverRowNoLabel(item.lastTwo)
            : loc.dating_neverRow(item.label!, item.lastTwo);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(text)),
          Semantics(
            button: true,
            label: loc.dating_neverRemoveLabel(text),
            excludeSemantics: true,
            child: TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed:
                  online && !_removing.contains(item.id)
                      ? () => _remove(item)
                      : null,
              child: Text(loc.dating_neverRemove),
            ),
          ),
        ],
      ),
    );
  }
}
```

Create `$D/edit_T9.py` with exactly:

```python
# Spec 2 W5c Task 9 (§3.12; carry 16): the "Never introduce me" writes on
# W4's read layer (add: the same "Added." for any number, never device
# gated; remove: device gated by the server), the fake that answers them,
# the route, the settings row, and the text-scale audit. Formatter-style
# edits (the files are W3's and W4's).
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anchor import edit

edit('lib/features/dating/data/dating_never_introduce.dart', [
  ("""abstract class DatingNeverIntroduceGateway {
  Future<DatingNeverIntroduceList> list();
}""", """abstract class DatingNeverIntroduceGateway {
  Future<DatingNeverIntroduceList> list();

  /// Spec 2 W5c (§3.12): `{ok, message: 'added'}` for any number (it can't
  /// be used to test whether someone uses Attune), or a refusal.
  Future<DatingWrite> add(String key, String phoneE164, String? label);

  /// Spec 2 W5c: removes one shown entry (a kept one is never shown).
  Future<DatingWrite> remove(String id);
}"""),
  ("""    } on DatingBusy {
      return const DatingNeverIntroduceList(reason: 'busy');
    }
  }
}""", """    } on DatingBusy {
      return const DatingNeverIntroduceList(reason: 'busy');
    }
  }

  @override
  Future<DatingWrite> add(String key, String phoneE164, String? label) =>
      datingWrite(
        () => _rpc.call('add_dating_never_introduce', {
          'p_idempotency_key': key,
          'p_phone_e164': phoneE164,
          'p_label': label,
        }),
      );

  @override
  Future<DatingWrite> remove(String id) => datingWrite(
    () => _rpc.call('remove_dating_never_introduce', {'p_id': id}),
  );
}"""),
], 'never introduce: the writes')

edit('test/features/dating/support/dating_fakes.dart', [
  ("""  @override
  Future<DatingNeverIntroduceList> list() async {
    reads++;
    return value;
  }
}""", """  @override
  Future<DatingNeverIntroduceList> list() async {
    reads++;
    return value;
  }

  // Spec 2 W5c: the writes, recorded; each answers [answer].
  DatingWrite answer = const DatingWrite(ok: true);
  final adds = <(String, String, String?)>[];
  final removes = <String>[];

  @override
  Future<DatingWrite> add(String key, String phoneE164, String? label) async {
    adds.add((key, phoneE164, label));
    return answer;
  }

  @override
  Future<DatingWrite> remove(String id) async {
    removes.add(id);
    return answer;
  }
}"""),
], 'fake: the writes')

edit('lib/features/dating/routes/dating_routes.dart', [
  ("""  /// Spec 2 W5b (§3.4, §3.5): Today and one match's moment.
  static const today = '/dating/today';
""", """  /// Spec 2 W5b (§3.4, §3.5): Today and one match's moment.
  static const today = '/dating/today';

  /// Spec 2 W5c (§3.12): Never introduce me to these numbers.
  static const neverIntroduce = '/dating/never-introduce';
"""),
  ("""import 'package:attune/features/dating/settings/dating_settings_screen.dart';
""", """import 'package:attune/features/dating/settings/dating_settings_screen.dart';
import 'package:attune/features/dating/settings/never_introduce_screen.dart';
"""),
  ("""    motion: (s) => DatingMotion.none,
  ),
];""", """    motion: (s) => DatingMotion.none,
  ),
  // Spec 2 W5c (§3.12, §3.15): a standard list.
  datingRoute(
    DatingPaths.neverIntroduce,
    'datingNeverIntroduce',
    signedIn,
    (s) => const DatingNeverIntroduceScreen(),
    motion: (s) => DatingMotion.sharedAxis,
  ),
];"""),
], 'routes: never introduce')

edit('lib/features/dating/settings/dating_settings_screen.dart', [
  ("""                if (kept > 0)
                  DatingCalmLine(loc.dating_neverIntroduceKept(kept)),""",
   """                // Spec 2 W5c (§3.12): the list, from any phone (adding
                // reduces exposure; removing asks the server's check).
                if (showRows)
                  row(
                    loc.dating_neverTitle,
                    '',
                    Icons.block_outlined,
                    () => context.push(DatingPaths.neverIntroduce),
                  ),
                if (kept > 0)
                  DatingCalmLine(loc.dating_neverIntroduceKept(kept)),"""),
], 'settings: the never-introduce row')

edit('test/architecture/text_scale_routes_test.dart', [
  ("""  'datingToday',
  'datingMatch',
""", """  'datingToday',
  'datingMatch',
  // Spec 2 W5c (§3.12): the never-introduce list.
  'datingNeverIntroduce',
"""),
], 'text scale: never introduce audited')

edit('test/features/dating/settings/dating_settings_rows_test.dart', [
  ("""      expect(find.textContaining('Never introduce'), findsNothing);""",
   """      // Spec 2 W5c (§3.12): the list's row is in now.
      expect(find.text('Never introduce me to these numbers'), findsOneWidget);"""),
], 'settings rows test: the never-introduce row')
```

- [ ] **Step 4: Apply, format, make the goldens, run**

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5
python3 -I $D/edit_T9.py
dart format lib/features/dating/settings/never_introduce_screen.dart test/features/dating/settings/never_introduce_test.dart | tail -1
flutter analyze --no-pub lib/features/dating test/features/dating test/architecture 2>&1 | tail -1
flutter test --no-pub test/features/dating/settings/never_introduce_test.dart --plain-name 'goldens' --update-goldens > /dev/null 2>&1; ls test/features/dating/settings/goldens | grep -c never_introduce
flutter test --no-pub test/features/dating/settings/dating_t12_fix1_test.dart --plain-name 'M-4' --update-goldens > /dev/null 2>&1
flutter test --no-pub test/features/dating/settings test/features/dating/routes test/architecture/text_scale_routes_test.dart 2>&1 | tr '\r' '\n' | grep -E '^[0-9:]+ \+[0-9]+.*(All tests passed|Some tests failed)' | tail -1
```

Expected: `lib/features/dating/data/dating_never_introduce.dart: 2 edit(s) …`, `dating_fakes.dart: 1 edit(s) …`, `dating_routes.dart: 3 edit(s) …`, `dating_settings_screen.dart: 1 edit(s) …`, `text_scale_routes_test.dart: 1 edit(s) …`, `dating_settings_rows_test.dart: 1 edit(s) …`; `Formatted 2 files (0 changed) …`; `No issues found! …`; `4`; a last line ending `All tests passed!`. Look at `dating_settings_bottom.scale1.0.png` before moving on: the only change is one more row, "Never introduce me to these numbers", under Dating lock's rows.

- [ ] **Step 5: The mutants**

Create `$D/mut_T9.py` with exactly:

```python
# Spec 2 W5c Task 9: Dart mutants (dmut.py). never_d8_keeps_text is retired
# as equivalent (Ruling R-35: the lock gate rebuilds the page per account).
N = 'lib/features/dating/settings/never_introduce_screen.dart'
NT = ['test/features/dating/settings/never_introduce_test.dart']
MUTS = {
  'never_keyboard_learns': (N, "                  maxLength: 20,\n                  enableSuggestions: false,\n                  autocorrect: false,\n                  enableIMEPersonalizedLearning: false,",
                            "                  maxLength: 20,\n                  enableSuggestions: false,\n                  autocorrect: false,", NT),
  'never_added_differs': (N, "    null => DatingCalmLine(loc.dating_neverAdded),", "    null => DatingCalmLine(loc.dating_neverAdded + ' '),", NT),
  'never_offline_adds': (N, "                      online && _number.text.trim().isNotEmpty ? _add : null,", "                      _number.text.trim().isNotEmpty ? _add : null,", NT),
  'never_kept_hidden': (N, "                if ((list?.keptCount ?? 0) > 0)", "                if (false)", NT),
  'never_raw_number': (N, "      '${_number.text.replaceAll(RegExp(r'\\D'), '')}';", "      '${_number.text}';", NT),
}
```

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5; python3 -I $D/dmut.py $D/mut_T9.py 2>&1 | tail -1
```

Expected: `5/5 killed` (`never_keyboard_learns`, `never_added_differs`, `never_offline_adds`, `never_kept_hidden`, `never_raw_number`).

- [ ] **Step 6: Record the tree**

Do not commit; record the tree in the report.

### Task 10: Other countries, Widen's third row, the manual, and the W5 gate (§2.6, §3.12, §3.4 Widen; carry 17; R-29, R-30)

**Files:**
- Create: `lib/features/dating/settings/{dating_abroad.dart, abroad_screen.dart}`, `test/features/dating/settings/abroad_test.dart`, `test/features/dating/settings/goldens/abroad.{scale1.0,scale1.3,scale2.0,rtl}.png`, `$D/{edit_T10.py, arb_fragment_T10.txt, mut_T10.py}`
- Modify: `lib/features/dating/routes/dating_routes.dart`, `lib/features/dating/settings/dating_settings_screen.dart`, `lib/features/dating/today/today_screen.dart` (Widen), `test/features/dating/support/{dating_shell.dart, dating_fakes.dart}`, `test/architecture/text_scale_routes_test.dart`, `lib/app/documentations/user_manual/data/dating_mode_docs.dart`, the ARB

**Interfaces:**
- Consumes: Task 8's `get_dating_abroad_options()`; W3's `set_dating_settings(…, 'abroad', {'other_countries_on': …})` through `DatingSetupGateway`; Task 7's `showDatingWidenSheet`.
- Produces: `DatingAbroadGateway`, `datingAbroadGatewayProvider`, `datingAbroadProvider`, `FakeAbroad`; `/dating/abroad` (`datingAbroad`); the settings row and Widen's row only when eligible.

- [ ] **Step 1: The copy**

Create `$D/arb_fragment_T10.txt` with exactly:

```text
  "dating_abroadTitle": "Other countries",
  "@dating_abroadTitle": {"description": "Spec 2 §3.12 the Other countries setting (also the settings and Widen rows)."},
  "dating_abroadCard": "Scams often start with someone abroad: a soldier, an oil-rig worker, a crypto 'mentor'. Never send money to someone you haven't met. Cross-border introductions are only with verified people whose accounts are at least 14 days old.",
  "@dating_abroadCard": {"description": "Spec 2 §3.12 the cross-border card, shown when a country is turned on."},
  "dating_abroadTurnOn": "Turn on for {country}",
  "@dating_abroadTurnOn": {"description": "Spec 2 §3.12 the cross-border card's button.", "placeholders": {"country": {"type": "String"}}},
  "dating_abroadNotNow": "Not now",
  "@dating_abroadNotNow": {"description": "Spec 2 §3.12 the cross-border card's way out. Plan copy."},
  "dating_abroadNone": "No other country is open to you yet.",
  "@dating_abroadNone": {"description": "Spec 2 §2.6 no open country the person may join (or one whose same-gender rule refuses their answers). Plan copy."}
```

```bash
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py .superpowers/sdd/2026-11-19-spec2-w5/arb_fragment_T10.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package > /dev/null; echo gen=$?
```

Expected: `added 5 keys`; `gen=0`.

- [ ] **Step 2: Write the failing tests**

Create `test/features/dating/settings/abroad_test.dart` with exactly:

```dart
// Spec 2 W5c (§2.6, §3.12, §3.15; carry 17; D8): Other countries. Turning
// a country on shows the cross-border card and writes only on "Turn on";
// "Not now" writes nothing; turning off writes at once, even before the
// person is eligible; not eligible says when; refusals in their own words;
// the settings row and the Widen row appear only once eligible.
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/settings/abroad_screen.dart';
import 'package:attune/features/dating/settings/dating_abroad.dart';
import 'package:attune/features/dating/today/today_screen.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_shell.dart';
import '../support/dating_today_fakes.dart';

Future<void> tap(WidgetTester t, Finder finder) async {
  await tapInReach(t, finder);
  await t.pumpAndSettle();
}

const _eligible = DatingAbroadOptions(
  ok: true,
  eligible: true,
  countries: [('GB', false)],
);

void main() {
  final loc = AppLocalizationsEn();

  Future<FakeAbroad> open(WidgetTester t, DatingAbroadOptions o) async {
    final fake = FakeAbroad(o);
    await pumpDatingShell(
      t,
      initial: DatingPaths.abroad,
      overrides: [datingAbroadGatewayProvider.overrideWithValue(fake)],
    );
    return fake;
  }

  testWidgets(
    'on: the cross-border card first; "Turn on" writes, "Not now" nothing',
    (t) async {
      final fake = await open(t, _eligible);
      expect(find.text(datingCountryName('GB')), findsOneWidget);
      await tap(t, find.byType(Switch));
      expect(find.text(loc.dating_abroadCard), findsOneWidget);
      await tap(t, find.text(loc.dating_abroadNotNow));
      expect(fake.sets, isEmpty);
      await tap(t, find.byType(Switch));
      await tap(t, find.text(loc.dating_abroadTurnOn(datingCountryName('GB'))));
      expect(fake.sets, [
        ['GB'],
      ]);
    },
  );

  testWidgets(
    'off at once, even before eligible; on waits; not eligible says when',
    (t) async {
      final fake = await open(
        t,
        const DatingAbroadOptions(
          ok: true,
          countries: [('GB', true), ('NG', false)],
        ),
      );
      expect(find.text(loc.dating_abroadDisabled), findsOneWidget);
      final switches = t.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches[1].onChanged, isNull);
      await tap(t, find.byType(Switch).first);
      expect(find.text(loc.dating_abroadCard), findsNothing);
      expect(fake.sets, [<String>[]]);
    },
  );

  testWidgets('refusals in their own words', (t) async {
    for (final (reason, line) in [
      ('not_yet', loc.dating_abroadDisabled),
      ('not_available', loc.dating_notAvailableHere),
      ('busy', loc.dating_busy),
      ('failed', loc.dating_errorGeneric),
    ]) {
      final fake = FakeAbroad(_eligible)
        ..answer = DatingWrite(ok: false, reason: reason);
      await pumpDatingShell(
        t,
        initial: DatingPaths.abroad,
        overrides: [datingAbroadGatewayProvider.overrideWithValue(fake)],
      );
      await tap(t, find.byType(Switch));
      await tap(t, find.text(loc.dating_abroadTurnOn(datingCountryName('GB'))));
      expect(find.text(line), findsWidgets, reason: reason);
    }
    await open(t, const DatingAbroadOptions(reason: 'reverify_device'));
    expect(find.text(loc.dating_sectionReverify), findsOneWidget);
  });

  testWidgets('Widen shows Other countries only once eligible', (t) async {
    for (final (o, shown) in [
      (_eligible, findsOneWidget),
      (const DatingAbroadOptions(ok: true), findsNothing),
    ]) {
      final today = FakeDatingToday(
        today: datingTodayJson({'today_state': 'empty', 'cards': <Object?>[]}),
      );
      await pumpDatingShell(
        t,
        initial: DatingPaths.today,
        overrides: [
          ...datingTodayOverrides(today),
          datingAbroadGatewayProvider.overrideWithValue(FakeAbroad(o)),
        ],
      );
      await tap(t, find.text(loc.dating_todayWiden));
      expect(find.text(loc.dating_abroadTitle), shown);
      expect(find.byType(DatingTodayScreen), findsOneWidget);
    }
  });

  testWidgets('goldens and guidelines', (t) async {
    await expectFlowGoldens(
      t,
      'abroad',
      () => const DatingAbroadScreen(),
      overrides: [
        ...datingShellOverrides(),
        datingAbroadGatewayProvider.overrideWithValue(FakeAbroad(_eligible)),
      ],
    );
    await expectFlowGuidelines(t);
  });
}
```

```bash
flutter test --no-pub test/features/dating/settings/abroad_test.dart 2>&1 | tr '\r' '\n' | grep -m1 -o "Error: Error when reading '[^']*'"
```

Expected: `Error: Error when reading 'lib/features/dating/settings/abroad_screen.dart'`.

- [ ] **Step 3: Write the read, the screen, and wire them**

Create `lib/features/dating/settings/dating_abroad.dart` with exactly:

```dart
// Spec 2 W5c (§2.6, §3.12; carry 17): Other countries. The read says which
// open countries the person may open to (never one whose same-gender rule
// refuses their answers) and whether they are eligible yet (verified, the
// age check holding, an account 14 days old); the write sets the list
// (narrowing it is never refused). RPC-only, one entry per account,
// memory only (D8, D20).
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingAbroadOptions {
  const DatingAbroadOptions({
    this.ok = false,
    this.reason,
    this.eligible = false,
    this.countries = const [],
  });

  final bool ok;
  final String? reason;
  final bool eligible;

  /// Each open country's code and whether the person is open to it.
  final List<(String code, bool on)> countries;

  List<String> get on => [
    for (final (code, on) in countries)
      if (on) code,
  ];

  factory DatingAbroadOptions.fromJson(Object? raw) {
    if (raw is! Map) return const DatingAbroadOptions(reason: 'failed');
    if (raw['ok'] != true) {
      final reason = raw['reason'];
      return DatingAbroadOptions(reason: reason is String ? reason : 'failed');
    }
    return DatingAbroadOptions(
      ok: true,
      eligible: raw['eligible'] == true,
      countries: [
        if (raw['countries'] is List)
          for (final c in (raw['countries'] as List).whereType<Map>())
            if (c['code'] is String &&
                RegExp(r'^[A-Z]{2}$').hasMatch(c['code'] as String))
              (c['code'] as String, c['on'] == true),
      ],
    );
  }
}

abstract class DatingAbroadGateway {
  Future<DatingAbroadOptions> read();

  /// The whole list (set_dating_open_abroad).
  Future<DatingWrite> set(String key, List<String> countries);
}

class DatingAbroadRepository implements DatingAbroadGateway {
  DatingAbroadRepository(this._rpc);

  final DatingRpc _rpc;

  @override
  Future<DatingAbroadOptions> read() async {
    try {
      return DatingAbroadOptions.fromJson(
        await _rpc.call('get_dating_abroad_options'),
      );
    } on DatingBusy {
      return const DatingAbroadOptions(reason: 'busy');
    } catch (_) {
      return const DatingAbroadOptions(reason: 'failed');
    }
  }

  @override
  Future<DatingWrite> set(String key, List<String> countries) => datingWrite(
    () => _rpc.call('set_dating_open_abroad', {
      'p_idempotency_key': key,
      'p_countries': countries,
    }),
  );
}

final datingAbroadGatewayProvider = Provider<DatingAbroadGateway>(
  (ref) => DatingAbroadRepository(ref.watch(datingRpcProvider)),
);

/// One entry per account: the next account starts from nothing (D8).
final datingAbroadProvider = FutureProvider.autoDispose
    .family<DatingAbroadOptions, String?>((ref, account) async {
      if (account == null) return const DatingAbroadOptions();
      return ref.read(datingAbroadGatewayProvider).read();
    });
```

Create `lib/features/dating/settings/abroad_screen.dart` with exactly:

```dart
// Spec 2 W5c (§2.6, §3.12, §3.15): Other countries. Each open country the
// person may join, with its switch. Turning one on shows the cross-border
// card first (the scam warning and who is introduced across borders) and
// writes only on "Turn on for {country}"; turning one off writes at once
// (it only narrows who sees the person, never refused). Until the person is
// verified and 14 days in, the switches can only go off. Standard list,
// no motion; every answer is fixed copy.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/lock/dating_sheets.dart';
import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/features/dating/settings/dating_abroad.dart';
import 'package:attune/features/dating/verify/dating_reverify_line.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A country's name for the list (the sign-in country list's).
String datingCountryName(String code) =>
    PhoneCountries.all
        .where((c) => c.isoCode == code)
        .map((c) => c.name)
        .firstOrNull ??
    code;

class DatingAbroadScreen extends ConsumerStatefulWidget {
  const DatingAbroadScreen({super.key});

  @override
  ConsumerState<DatingAbroadScreen> createState() => _DatingAbroadScreenState();
}

class _DatingAbroadScreenState extends ConsumerState<DatingAbroadScreen> {
  final _keys = DatingActionKeys();
  bool _saving = false;
  DatingWrite? _answer;

  @override
  void initState() {
    super.initState();
    // D8: the next account sees nothing of this one's answers.
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (previous == next || !mounted) return;
      setState(() {
        _saving = false;
        _answer = null;
      });
    });
  }

  Future<bool> _card(String code) async {
    final loc = AppLocalizations.of(context)!;
    final name = datingCountryName(code);
    final yes = await showModalBottomSheet<bool>(
      context: context,
      routeSettings: datingSheetSettings('abroad-card'),
      isScrollControlled: true,
      builder:
          (sheet) => DatingSheetTracker(
            child: AllowLargeText(
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        loc.dating_abroadCard,
                        style: Theme.of(sheet).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: Spacing.md),
                      FlowPrimaryButton(
                        label: loc.dating_abroadTurnOn(name),
                        onPressed: () => Navigator.of(sheet).pop(true),
                      ),
                      const SizedBox(height: Spacing.sm),
                      FlowSecondaryButton(
                        label: loc.dating_abroadNotNow,
                        onPressed: () => Navigator.of(sheet).pop(false),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    );
    return yes ?? false;
  }

  Future<void> _toggle(DatingAbroadOptions o, String code, bool on) async {
    if (_saving) return;
    if (on && !await _card(code)) return;
    if (!mounted) return;
    final account = ref.read(datingAccountProvider);
    final list = [...o.on.where((c) => c != code), if (on) code]..sort();
    setState(() {
      _saving = true;
      _answer = null;
    });
    final w = await ref
        .read(datingAbroadGatewayProvider)
        .set(_keys.keyFor('abroad', '$account|$list'), list);
    _keys.settle('abroad', reason: w.reason);
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    ref.invalidate(datingAbroadProvider(account));
    setState(() {
      _saving = false;
      _answer = w.ok ? null : w;
    });
  }

  Widget _line(AppLocalizations loc, String? reason) => switch (reason) {
    'reverify_device' => const DatingReverifyLine(),
    'busy' => DatingCalmLine(loc.dating_busy),
    'not_yet' => DatingCalmLine(loc.dating_abroadDisabled),
    'not_available' => DatingCalmLine(loc.dating_notAvailableHere),
    'not_eligible' => DatingCalmLine(loc.dating_sectionUnavailable),
    _ => FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
  };

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final account = ref.watch(datingAccountProvider);
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final o = ref.watch(datingAbroadProvider(account)).valueOrNull;
    return AllowLargeText(
      child: Scaffold(
        appBar: AppBar(title: Text(loc.dating_abroadTitle)),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!online) DatingCalmLine(loc.dating_offline),
                if (o == null)
                  const Center(child: CircularProgressIndicator())
                else if (!o.ok)
                  _line(loc, o.reason)
                else ...[
                  if (!o.eligible) DatingCalmLine(loc.dating_abroadDisabled),
                  if (o.countries.isEmpty)
                    DatingCalmLine(loc.dating_abroadNone),
                  for (final (code, on) in o.countries)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(datingCountryName(code)),
                      value: on,
                      // Off is always allowed; on needs the person eligible.
                      onChanged:
                          online && !_saving && (on || o.eligible)
                              ? (v) => _toggle(o, code, v)
                              : null,
                    ),
                ],
                if (_answer case final w?) _line(loc, w.reason),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

Create `$D/edit_T10.py` with exactly:

```python
# Spec 2 W5c Task 10 (§2.6, §3.12; carries 15, 16, 17): Other countries on
# the Dating routes, in Dating settings and in Widen who I meet (each only
# once the person is eligible); the shell fakes the read (not eligible, no
# country, unless a test says otherwise); the text-scale audit; and the
# manual's never-introduce and other-countries passages as W5c builds them.
# Formatter-style edits (W3's, W4's and W5b's files).
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anchor import edit

edit('lib/features/dating/routes/dating_routes.dart', [
  ("""  /// Spec 2 W5c (§3.12): Never introduce me to these numbers.
  static const neverIntroduce = '/dating/never-introduce';
""", """  /// Spec 2 W5c (§3.12): Never introduce me to these numbers.
  static const neverIntroduce = '/dating/never-introduce';

  /// Spec 2 W5c (§2.6, §3.12): Other countries.
  static const abroad = '/dating/abroad';
"""),
  ("""import 'package:attune/features/dating/settings/dating_settings_screen.dart';
""", """import 'package:attune/features/dating/settings/abroad_screen.dart';
import 'package:attune/features/dating/settings/dating_settings_screen.dart';
"""),
  ("""    (s) => const DatingNeverIntroduceScreen(),
    motion: (s) => DatingMotion.sharedAxis,
  ),
];""", """    (s) => const DatingNeverIntroduceScreen(),
    motion: (s) => DatingMotion.sharedAxis,
  ),
  datingRoute(
    DatingPaths.abroad,
    'datingAbroad',
    signedIn,
    (s) => const DatingAbroadScreen(),
    motion: (s) => DatingMotion.sharedAxis,
  ),
];"""),
], 'routes: Other countries')

edit('lib/features/dating/settings/dating_settings_screen.dart', [
  ("""import 'package:attune/features/dating/routes/dating_setup_steps.dart'
    show datingStepLocation;""", """import 'package:attune/features/dating/routes/dating_setup_steps.dart'
    show datingStepLocation;
import 'package:attune/features/dating/settings/dating_abroad.dart';"""),
  ("""    final kept = keptRead?.keptCount ?? 0;""", """    final kept = keptRead?.keptCount ?? 0;
    // Spec 2 W5c (§3.12): Other countries, once the person is eligible.
    final abroad =
        showRows
            ? ref.watch(datingAbroadProvider(account)).valueOrNull
            : null;"""),
  ("""                  row(
                    loc.dating_settingsHowFar,
                    '',
                    Icons.near_me_outlined,
                    () => _open('where'),
                  ),""", """                  row(
                    loc.dating_settingsHowFar,
                    '',
                    Icons.near_me_outlined,
                    () => _open('where'),
                  ),
                  if (abroad != null && abroad.ok && abroad.eligible)
                    row(
                      loc.dating_abroadTitle,
                      '',
                      Icons.public,
                      () => context.push(DatingPaths.abroad),
                    ),"""),
], 'settings: Other countries')

edit('lib/features/dating/today/today_screen.dart', [
  ("""import 'package:attune/features/dating/section/dating_calm_line.dart';
""", """import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/features/dating/settings/dating_abroad.dart';
"""),
  ("""                      onTap: () {
                        Navigator.of(sheet).pop();
                        context.push(DatingPaths.stepFromToday('where'));
                      },
                    ),
""", """                      onTap: () {
                        Navigator.of(sheet).pop();
                        context.push(DatingPaths.stepFromToday('where'));
                      },
                    ),
                    // Spec 2 W5c (§2.6, §3.4): only once eligible.
                    Consumer(
                      builder: (context, ref, _) {
                        final account = ref.watch(datingAccountProvider);
                        final o =
                            ref.watch(datingAbroadProvider(account)).valueOrNull;
                        if (o == null || !o.ok || !o.eligible) {
                          return const SizedBox.shrink();
                        }
                        return InfoRowWidget(
                          title: loc.dating_abroadTitle,
                          subtitle: '',
                          icon: Icons.public,
                          showAvatar: false,
                          padding: const EdgeInsets.symmetric(
                            vertical: Spacing.xs,
                          ),
                          onTap: () {
                            Navigator.of(sheet).pop();
                            context.push(DatingPaths.abroad);
                          },
                        );
                      },
                    ),
"""),
], 'widen: Other countries')

edit('test/features/dating/support/dating_shell.dart', [
  ("""import 'package:attune/features/dating/routes/dating_routes.dart';
""", """import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/settings/dating_abroad.dart';
"""),
  ("""        datingNeverIntroduceGatewayProvider.overrideWithValue(
          FakeNeverIntroduce(),
        ),
        ...overrides,""", """        datingNeverIntroduceGatewayProvider.overrideWithValue(
          FakeNeverIntroduce(),
        ),
        // Spec 2 W5c: not eligible for Other countries unless a test says.
        datingAbroadGatewayProvider.overrideWithValue(FakeAbroad()),
        ...overrides,"""),
  ("""  datingNeverIntroduceGatewayProvider.overrideWithValue(FakeNeverIntroduce()),
];

/// The Dating section's overrides""", """  datingNeverIntroduceGatewayProvider.overrideWithValue(FakeNeverIntroduce()),
  datingAbroadGatewayProvider.overrideWithValue(FakeAbroad()),
];

/// The Dating section's overrides"""),
], 'shell: the abroad read faked')

edit('test/features/dating/support/dating_fakes.dart', [
  ("""import 'package:attune/features/dating/data/dating_rpc.dart';
""", """import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/settings/dating_abroad.dart';
"""),
  ("""class FakeNeverIntroduce implements DatingNeverIntroduceGateway {""",
   """/// Spec 2 W5c: Other countries, answered and recorded.
class FakeAbroad implements DatingAbroadGateway {
  FakeAbroad([this.value = const DatingAbroadOptions(ok: true)]);

  DatingAbroadOptions value;
  DatingWrite answer = const DatingWrite(ok: true);
  final sets = <List<String>>[];

  @override
  Future<DatingAbroadOptions> read() async => value;

  @override
  Future<DatingWrite> set(String key, List<String> countries) async {
    sets.add(countries);
    return answer;
  }
}

class FakeNeverIntroduce implements DatingNeverIntroduceGateway {"""),
], 'fakes: Other countries')

edit('test/architecture/text_scale_routes_test.dart', [
  ("""  // Spec 2 W5c (§3.12): the never-introduce list.
  'datingNeverIntroduce',
""", """  // Spec 2 W5c (§3.12): the never-introduce list and Other countries.
  'datingNeverIntroduce',
  'datingAbroad',
"""),
], 'text scale: Other countries audited')

edit('lib/app/documentations/user_manual/data/dating_mode_docs.dart', [
  ("""              'A former Attune partner is never introduced to you, even if either of you later makes a new account.',
          type: ManualContentType.text,
        ),""", """              'A former Attune partner is never introduced to you, even if either of you later makes a new account.',
          type: ManualContentType.text,
        ),
        // Spec 2 W5c (§3.12; carry 15): the list and other countries.
        ManualContent(
          id: 'dating_never_introduce',
          title: 'Never introduce me to these numbers',
          numberPrefix: '3',
          content:
              'In Dating settings you can add up to 50 phone numbers, with a name only you see. Attune will never introduce you to the person who uses one, now or later, and they\\'re never told. Attune keeps a code made from each number, not the number. Adding a number always says "Added.", whoever it belongs to. An introduction already made ends at your next answer; a conversation already going is ended with Block.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_other_countries',
          title: 'Other countries',
          numberPrefix: '4',
          content:
              'Introductions stay in your country unless you choose another one in Dating settings, once you\\'re verified and your account is 14 days old. You\\'re only introduced across a border to verified people whose accounts are at least 14 days old and who chose your country too. Scams often start with someone abroad: never send money to someone you haven\\'t met.',
          type: ManualContentType.text,
        ),"""),
], 'manual: never introduce, other countries')
```

- [ ] **Step 4: Apply, format, make the goldens, run**

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5
python3 -I $D/edit_T10.py
dart format lib/features/dating/settings/dating_abroad.dart lib/features/dating/settings/abroad_screen.dart test/features/dating/settings/abroad_test.dart | tail -1
flutter analyze --no-pub lib/features/dating test/features/dating test/architecture 2>&1 | tail -1
flutter test --no-pub test/features/dating/settings/abroad_test.dart --plain-name 'goldens' --update-goldens > /dev/null 2>&1; ls test/features/dating/settings/goldens | grep -c abroad
flutter test --no-pub test/features/dating test/architecture/text_scale_routes_test.dart 2>&1 | tr '\r' '\n' | grep -E '^[0-9:]+ \+[0-9]+.*(All tests passed|Some tests failed)' | tail -1
python3 scripts/large_text_audit.py --scale 2.0 test/features/dating/today test/features/dating/settings/never_introduce_test.dart test/features/dating/settings/abroad_test.dart 2>&1 | tail -1
```

Expected: `dating_routes.dart: 3 edit(s) …`, `dating_settings_screen.dart: … (settings: Other countries)`, `today_screen.dart: … (widen: Other countries)`, `dating_shell.dart: … (shell: the abroad read faked)`, `dating_fakes.dart: … (fakes: Other countries)`, `text_scale_routes_test.dart: 1 edit(s) …`, `dating_mode_docs.dart: … (manual: never introduce, other countries)`; `Formatted 3 files (0 changed) …`; `No issues found! …`; `4`; `+997: All tests passed!`; `SCALE 2.0: 0 site(s) to fix, 0 listed apart, 1 missed tap(s)` (the one is a `PageView` drag in the data test, not a tap).

- [ ] **Step 5: The mutants**

Create `$D/mut_T10.py` with exactly:

```python
# Spec 2 W5c Task 10: Dart mutants (dmut.py).
A = 'lib/features/dating/settings/abroad_screen.dart'
AT = ['test/features/dating/settings/abroad_test.dart']
MUTS = {
  'abroad_no_card': (A, "    if (on && !await _card(code)) return;", "    if (false && !await _card(code)) return;", AT),
  'abroad_on_before_eligible': (A, "                          online && !_saving && (on || o.eligible)", "                          online && !_saving", AT),
  'widen_abroad_always': ('lib/features/dating/today/today_screen.dart', "                        if (o == null || !o.ok || !o.eligible) {", "                        if (o == null) {", AT),
}
```

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5; python3 -I $D/dmut.py $D/mut_T10.py 2>&1 | tail -1
```

Expected: `3/3 killed` (`abroad_no_card`, `abroad_on_before_eligible`, `widen_abroad_always`).

- [ ] **Step 6: The W5 gate**

```bash
D=.superpowers/sdd/2026-11-19-spec2-w5
$D/suite.sh attune_spec3a > $D/sql-W5.txt; echo "$(grep -c '^PASS' $D/sql-W5.txt) PASS, $(grep -c '^FAIL' $D/sql-W5.txt) FAIL"
diff <(grep FAIL $D/sql-baseline.txt) <(grep FAIL $D/sql-W5.txt) && echo same-fails
for m in T4 T8; do python3 -I $D/mutate.py $( [ $m = T4 ] && echo supabase/migrations/20261119110000_dating_v2_today.sql || echo supabase/migrations/20261119120000_dating_v2_signals.sql ) supabase/tests/dating_v2_matching_contracts.sql $D/mut_$m.py $D/mut $( [ $m = T4 ] && echo supabase/migrations/20261119110010_dating_v2_today_grants.sql || echo supabase/migrations/20261119120010_dating_v2_signals_grants.sql ) 2>&1 | grep -c 'CONTRACT VIOLATED'; done
dropdb --if-exists w5race 2>/dev/null; createdb w5race
pg_dump -s attune_spec3a | psql -X -q -d w5race > /dev/null 2>&1
pg_dump -a -t public.metric_key_prefixes -t public.feature_flags -t public.country_safety_config -t private.dating_calling_codes -t public.dating_algorithm_configs attune_spec3a | psql -X -q -d w5race > /dev/null 2>&1
bash scripts/concurrency/dating_kill_switch_races.sh w5race > $D/race_W5.txt 2>&1; grep -c '^PASS' $D/race_W5.txt; grep -v '^PASS' $D/race_W5.txt
dropdb w5race
cd supabase/functions && deno test --allow-read --allow-env --lock=../../.github/deno-w9.lock --frozen _shared/unicode_normaliser.test.ts _shared/writer_crisis_check.test.ts _shared/healing_ai_gate.test.ts process-dating-photo/handler.test.ts process-dating-photo/worker.test.ts _shared/google_vision.test.ts analyse-journal-entry/ generate-healing-portrait/ generate-healing-post-mortem/ process-scheduled-notifications/privacy_allowlist.test.ts dating-verification/handler.test.ts _shared/age_assurance/providers.test.ts dating-photo-urls/handler.test.ts 2>&1 | grep -E 'passed|failed' | tail -1; cd ../..
psql -X -q -At -v ON_ERROR_STOP=1 -d attune_spec3a -c 'BEGIN' -f supabase/sql/dev_enable_spec2_dating_flags.sql \
  -c "SELECT 'active=' || version || ':' || product_review_ref FROM public.dating_algorithm_configs WHERE state = 'active'" \
  -c "SELECT 'flags_on=' || count(*) FROM public.feature_flags WHERE key LIKE 'dating%' AND enabled" -c 'ROLLBACK' 2>&1 | grep -E 'active=|flags_on='
flutter analyze --no-pub lib test > $D/analyze-W5.txt 2>&1; tail -1 $D/analyze-W5.txt
flutter test --reporter compact > $D/flutter-W5.txt 2>&1; tr '\r' '\n' < $D/flutter-W5.txt | grep -E '^[0-9:]+ \+[0-9]+' | tail -1
shasum -c .superpowers/sdd/2026-11-04-spec1-w10-accessibility-docs/w10-1.0.sha | grep -vc ': OK$'; shasum -c .superpowers/sdd/2026-11-04-spec1-w9/flag_off.sha | grep -vc ': OK$'
shasum -c .superpowers/sdd/2026-11-07-spec2-w3/latch.sha; flutter test --no-pub test/architecture/games_untouched_test.dart 2>&1 | tr '\r' '\n' | tail -1
```

Expected: `160 PASS, 14 FAIL`; `same-fails`; `22`; `13`; `31`; nothing else; `ok | 200 passed | 0 failed`; `active=introductions_v2:DEV-product` and `flags_on=6` (W5b and W5c add no flag); `571 issues found. (ran in …)`; `+8228` (+37 over the baseline: Task 6's 12, Task 7's 15, Task 9's 5, Task 10's 5) and only the known flakes (an earlier run met `chat_upload_progress_cancel_test.dart: … a relationship purge closes the uploader's client` once; it passes alone: treat it as a flake only after that re-run); `0`; `0`; `lib/home/home_screen.dart: OK`; `All tests passed!`.

- [ ] **Step 7: Record the tree**

Do not commit; record the tree in the report.


---

## Owner checklist (nothing here is done by an implementer)

1. **W5's production gate (spec §8 W5; recorded in `private.flag_production_gates` before `dating_candidate_generation` may turn on in production).**
   - `dating_exclusion_key` provisioned in the production vault and `get_dating_operational_health()`'s `exclusion_key_present` green (with `dating_field_key`, already W1's).
   - The DV specialist signs the never-introduce copy (Task 9's keys `dating_never*`: the explainer "Add a phone number and Attune will never introduce you to the person who uses it, now or later. They're never told.", "We keep a code made from the number, not the number itself.", "Added.", the kept-entries line, the remove and re-check lines).
   - `introductions_v2` activated in production with real review references (product, clinical, fairness, safety), none starting `DEV-` (the trigger refuses `DEV-` there; R-12 of §5.11). The config's numbers (`daily_new_max` 3, `waiting_max` 6, the 72-hour cool-off, the 14-day freshness, the band and jitter) are the spec's §5.11 seed; any change is a new version.
   - **Build-time gates (added in the W5 final review; also in the gate row):** generation commits per partition, with a partition run under ~2 s at launch size (the 03:17 tick otherwise holds account deletions, path switches and birth-date fixes past the 8 s API timeout); optimise generation before any partition passes ~1,500 people; rewrite race case 30's overlap check with that rework; the signals and digest steps commit on their own (no lock held across the tick); keep `generation_hour_utc` aligned across countries or add a publish guard; the field-key rotation must not end every open introduction (the sensitive-row trigger compares ciphertext); confirm on the development project that Today, the introductions read and Other countries refresh the trusted phone's `last_seen_at` through PostgREST (and that the older STABLE device-gated reads, led by `get_dating_home`, are fixed or don't need to); `attune_environment` reads `production` in the production vault (the `DEV-` guard depends on it).
2. **§7.7 device checks for W5 (release builds, on the development project with `supabase/sql/dev_enable_spec2_dating_flags.sql` run).**
   - TalkBack and VoiceOver through a full introduction: Today's state line, a card (name, age, region, intention, "Why you two were introduced", each photo announced by its caption), Interested, Not for me with the 20-second screen-reader undo, the match moment read once, Widen and its rows.
   - 200% text and RTL on Today, the card, the moment, Widen, the family question, the quiet note, Never introduce and Other countries.
   - Data use for a day of introductions with and without photos (data saver on: grey cards, photos on tap); correct D1's and D9's figures if off by more than 25%.
   - Quick exit from Today with photos shown: back in the app nothing of Today is shown and no photo is on disk (the photo memory is emptied); the Dating lock, Safety PIN and plain icon unchanged. A second account signed in on the same phone sees nothing of the first's day (D8).
   - Android screenshots and screen recording blocked on Today and the moment; iOS app switcher covered.
   - Real carriers (MTN, Telecel, AirtelTigo, a UK carrier): the digest arrives at the chosen drop time as the neutral "You have something new in Attune." and opens Me; nothing names a person. The moment's light haptic once; nothing moves with reduce motion on.
   - Two phones, two test accounts made mutual by the dev generation: both tap Interested within a second; one match, each sees the moment once.
3. **Deploy (owner only; Dating stays off in production).**
   - `supabase db push` after every earlier undeployed wave (Spec 1 W1–W10, Spec 2 W1–W4), in order: `20261119100000_dating_v2_matching.sql`, `20261119100010_dating_v2_matching_grants.sql`, `20261119110000_dating_v2_today.sql`, `20261119110010_dating_v2_today_grants.sql`, `20261119120000_dating_v2_signals.sql`, `20261119120010_dating_v2_signals_grants.sql`. Before the first: `SELECT count(*) FROM public.dating_introductions` and `… public.dating_matches` on production (W5a keeps the newest row per pair and drops `dating_feature_snapshots`; expect 0 in production).
   - Ship the W5 app build with or after the W5b push (the v1 read `get_my_dating_introductions(integer)` is dropped by W5b; no shipped build calls it — the v1 model is deleted in Task 6).
   - Deploy `dating-photo-urls` (`verify_jwt = true`, `supabase/config.toml`); no new secret (it uses the project's service role and Storage).
   - Secrets checked by name: `dating_exclusion_key`, `dating_field_key`, `dating_push_key` (vault; without the push key the digest sends nothing and counts `dating.digest.push_key_missing`, R-24).
   - Crons after the push: `dating-candidate-generation` hourly at :17 (replaces the v1 weekly job, unscheduled by W5a), `dating-digest` hourly at :05, `dating-fairness-weekly` Mondays 04:17. Alerts on `get_dating_operational_health()`'s `generation_by_country` (a dead-lettered run) and the `dating.generation.failed` and `dating.generation.skipped` counters.
   - Re-run `supabase/sql/dev_enable_spec2_dating_flags.sql` on the development project (it drops the retired alignment flag and activates `introductions_v2` under `DEV-` references).
4. **Plan copy for the reviewers** (each marked "Plan copy" in its ARB description; the full list is Tasks 6, 7, 9 and 10's fragments): Today's day-state lines (cool-off, before the drop, paused for open chats, queue full, empty), the waiting heading, Widen's rows, the family question and quiet note, the reasons' sentences (`dating_reason_*`), the moment's lines and "Later", the section's "Open Today" (R-32), Other countries' card and refusals. The DV reviewer reads the never-introduce lines (gate 1) and the moment; the cultural reviewer the reasons, the family question and the waiting lines; the LGBTQ+ safety reviewer Other countries' card and its refusals.
5. **Owner decisions (one line each).** R-12 asked: Report/Block on the card wait for W7a's report sheet (as written), or Block added now through `block_dating_introduction` (one more task). Visible for a nod (recorded rulings): R-3 (freshness reads the trusted phone's last use until W8b's device check writes the context), R-11 ("Say hello" waits for W6a's chat), R-14 (the dragnet's first-message input waits for W6a; never fires on a missing input), R-26 (carry 5's man–woman match closing moves to W6a), R-32 ("Open Today" on the section rather than cards inside Me).
6. **Still open from W2–W4 (unchanged by W5).**
   - W4: the estimation vendor and Smile ID contracts, Smile's sandbox classes (under-18, MRZ/OCR), the DPIA biometric section and vendor deletion terms (R-22), the AWS region, the UK HEAA documentation, hosted Storage forwarding `x-attune-device` (else signed URLs), Supabase logs and the raw header, the §6.9 metric list; deploy `dating-verification`, delete `verify-dating-profile`, the `dating-verification-sweep` cron and its alert; the W4 app build with or before the W4b push.
   - W3: the cultural, LGBTQ+, Ghana legal and counsel reviews; `dating_push_key`, `GOOGLE_VISION_API_KEY`, `CSAM_MATCHER` and its key; `process-dating-photo` deployed, `upload-dating-photo` deleted; the orphan and stale-job crons and the CSAM alert routes; production GH/GB `dating_enabled = false` checked; the W3 device checks (Android Crop, iOS limited photos, keyboard learning).
   - W2: the clinician's note and the DV reviewer's read of every W2 and W3 string.
7. **Carried to later waves (recorded, not built here):** W6a: the moment's "Say hello" (`kDatingChatReady`), `get_my_dating_matches(boolean)`, the dragnet's first messages (R-14), carry 5 (R-26); W6b: the duplicate-opener, money-ask and sexual-pressure signals; W7a: the card's More (Report, Block) (R-12), the queue's review console; W7b: the fairness flags in the console; W8b: the session context writer that replaces R-3's fallback, the location-mismatch signal; W9: carry 18 (export respects `kept_at`).

---

## Spec coverage (self-review)

| Spec | Where |
|---|---|
| §5.1 inputs, §5.11 the config | Task 1 (A, B: `introductions_v2`, caps CHECK, the `DEV-` guard; mutants `m20_cap_check`, `dev_guard_off`) |
| §5.2 hard filters 1–14, both directions | Task 1 (C–F; mutants `m2_*` both directions, `m3_*`, and the carries) |
| §5.2 filter 15 (the throttle at 0) | Task 8 (Q; `filter15_ignored`) |
| §5.3 ranking, §5.4 band, exposure, jitter | Task 2 (G1, G2, G4; `jitter_unseeded`, `band_ignored`) |
| §5.5 cohorts, one run, dead-letter | Task 2 (G3, G6), Task 3 (race) |
| §5.6 caps and pauses | Task 2 (G5), Task 4 (L day states) |
| §5.7 reasons | Task 2 (H), Task 4 (M; mutant 19), Task 6 (`dating_reasons`) |
| §5.8 the payload | Task 4 (L; mutant 18), Task 5 |
| §5.9 fairness | Task 8 (T) |
| §5.10 signals | Task 8 (Q, R, S; R-14, R-15) |
| §3.4 Today, the card, Widen, family question, undo | Tasks 6, 7, 10 (Widen's third row) |
| §3.5 the match moment | Task 4 (N), Task 7 |
| §3.12 never-introduce, Other countries | Tasks 9, 10, Task 8 (U) |
| §3.13 the digest | Task 4 (P; R-24) |
| §3.14 routes behind the lock | Tasks 7, 9, 10 (`datingRoute`; the C-1 guard) |
| §3.15 rows Today, Match moment, Settings | Tasks 7, 9, 10 (motion, large text, dark, errors, offline) |
| §2.3 freshness, §2.6 same-gender, §2.8 signals and phones | Task 1 (E; R-3), Task 8 (R, S, U) |
| §4.3 tables, §4.4 functions, §4.6 crons | Tasks 1, 2, 4, 8 |
| §4.7 `dating-photo-urls` | Task 5; Task 4 (`dating_photo_keys_for_viewer`) |
| §4.9 W5a–W5c, dev switch-on | Tasks 1, 4, 8; Task 3 Step 2 |
| §4.10 W5 rows | Task 6 (the v1 model deleted; captions), Task 7 (manual), Task 10 (manual) |
| §6.9 metrics | Task 2 (generation counters), Task 4 (digest) |
| §7.1 `dating_v2_matching_contracts.sql` | A–U across Tasks 1, 2, 4, 8 |
| §7.2 S3, S5, S10 | Task 1 (S3: no special category in `rank_detail`), Tasks 6–7 (S5: D8), Task 8 (S10) |
| §7.3 Deno | Task 5 |
| §7.4 widget tests | Tasks 6, 7, 9, 10 |
| §7.5 mutants 2, 3, 6, 18, 19, 20 | Task 1 (`m2_*`, `m3_*`, `m20_cap_check`), Task 2 (`m6_*`), Task 4 (`m18_*`, `m19_*`) |
| §7.6 concurrency | Task 3 (two ticks), Task 4 (simultaneous interest) |
| §7.7 W5 device checks | Owner checklist 2 |
| §8 W5 gate | Owner checklist 1 |
| §9 R12 | Task 1 (the dropped objects' callers re-created; contract J's body scan) |
| Cross-spec S-4, S-5, I-9, W-2 | Task 2 (S-4 transitive scan), Task 8 (S-5 no routing column), Task 4 (I-9: the digest on W3a's `me_update`), the three batches (W-2) |
| Carries 1–18 | the Carries table |
| Review Focus 1–5 | the tests named there |

Placeholder scan: no "TBD"/"TODO"/"fill in" in a step; every step gives its exact file, code, command and expected line. Type consistency checked by name across tasks: `DatingToday` (`ok`, `reason`, `state`, `dropAt`, `regionNameKey`, `myName`, `cards`, `waiting`, `moments`, `familyQuestion`, `quietNote`, `dataSaver`, `minAge`, `maxAge`, `scope`), `DatingIntroCard` (`id`, `card`, `reasons`, `sideNameKey`, `captions`, `acted`), `DatingMoment` (`matchId`, `name`), `DatingActAnswer` (`ok`, `action`, `matched`, `reason`), `DatingPhotoUrl` (`position`, `url`), `DatingTodayGateway` (`today`, `act`, `momentSeen`, `dismissNote`, `saveFamily`, `photoUrls`), `DatingNeverIntroduceGateway` (`list`, `add`, `remove`), `DatingAbroadGateway`. Where a step says an anchor misses, the instruction is to stop and report.

---

## Replay record (2026-11-19)

The plan was built in a scratch copy of the repo at `a2d22add` (plus the owner's two uncommitted files) on a clone of `attune_spec3a`, then replayed from this text: the scratch copy was reset to `a2d22add`, a fresh clone of `attune_spec3a` made, and a script wrote every "Create … with exactly" block and ran every `bash` block in order (Tasks 1–10), with the database name swapped for the clone's. The first build run found three app regressions the plan now fixes: the C-1 guard in `dating_routes_test.dart` pumps every Dating route and needs Today's fake (Task 7), W3's settings-rows test asserted the never-introduce row was absent and the `dating_settings_bottom` goldens gained that row (Task 9), and the match moment made its animation controller lazily inside `dispose` (now made in `initState`). The replay then found only Expected-line and command fixes: Task 4's red line (`invalid input syntax for type json`, the error text `pg_temp.call` returns), `marked_diff`'s count for Task 4 (8 lines), Task 8 Step 1's signature for `dating_person_current` (the replay of Tasks 8–10 was rolled back to Task 7's end and run again from Task 8 on the same clone after that fix), the builder's "3 functions" wording, the Deno and Flutter "see it fail" filters (now `grep -o` on `Cannot find module …` and `Error: Error when reading '…'`; Tasks 9 and 10 printed theirs in the replay, Tasks 5, 6 and 7's were run by hand against a tree without the new file and printed exactly their Expected line), `dropdb`'s notice silenced, Task 10's dating test count (`+997`). After those fixes every Expected line below matched. The replayed tree equals the built tree byte for byte (trailing blank lines aside). The clones and the scratch copy were dropped afterwards; the disk filled once during the first baseline run (an unrelated cache in the scratch copy, removed), which is why Task 3's gate is the baseline's measured `+8191`.

| Check | W5a (after Task 3) | W5b (after Task 7) | W5c (after Task 10) |
|---|---|---|---|
| Migration + twin, applied twice | 4 × `exit=0` | 4 × `exit=0` | 4 × `exit=0` |
| `marked_diff.py` | 9 functions `OK` | 1 function `OK` | 3 functions `OK` |
| SQL suite (wrapped) | 160 PASS / 14 FAIL, no new FAIL | 160 / 14, same fails | 160 / 14, same fails |
| `dating_v2_matching_contracts.sql` | `all held` (A–F, J, K, G–I) | `all held` (+ L–P) | `all held` (+ Q–U) |
| SQL mutants | T1 23 / 23, T2 15 / 15 RED | T4 22 / 22 RED | T8 13 / 13, T4 22 / 22 RED |
| Race script (idle scratch DB) | 30 / 30 PASS | 31 / 31 PASS | 31 / 31 PASS |
| Deno (CI line, frozen lock) | 193 passed, 0 failed | 200 passed, 0 failed | 200 passed, 0 failed |
| Deno mutants | — | T5 9 / 9 killed | — |
| Dart mutants | — | T6 6 / 6, T7 9 / 9 | T9 5 / 5, T10 3 / 3 |
| Dev script | `introductions_v2:DEV-product`, 6 flags on | — | same |
| `flutter analyze --no-pub lib test` | 571, no new issue | 571 | 571 |
| Full `flutter test` | +8191, all passed | +8218, all passed | +8228, all passed |
| Large-text audit at 2.0 | — | 0 sites (1 `PageView` drag, not a tap) | 0 sites (same) |
| W10 / W9 golden shas, latch, Games guard | 0 / 0 / OK / passed | 0 / 0 / OK / passed | 0 / 0 / OK / passed |
