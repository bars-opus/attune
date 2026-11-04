# Spec 1 W9e (Healing AI pause) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Healing's AI the Journal's W9c treatment (owner approval O2): a `healing_ai_insights` flag (false, with its production gate row: the W9c clinician gate), and the hard-coded `self_disclosure` crisis check run first in `generate-healing-portrait` and `generate-healing-post-mortem` (no provider call and nothing persisted on a match), with W9c's support card on the Healing stage screens.

**Architecture:** Four tasks. **Task 1** records the baselines and adds migration 20 (`20261104140000_healing_ai_insights_flag.sql` + its grants twin: one flag row, false, and its gate row), the dev-script line and `healing_ai_pause_contracts.sql` with seven mutants. **Task 2** makes one crisis check for the Journal and Healing: the pending-review self-harm list moves, unchanged, to `_shared/self_harm_pending.ts` (the journal file re-exports it) and the fold and the check move, unchanged, from `journal_handlers.ts` to `_shared/writer_crisis_check.ts`; the journal's 35 tests stay green and six mutants turn red. **Task 3** moves each Healing function's action into a handler file (`portrait_handler.ts`, `post_mortem_handler.ts`), verbatim except the marked lines, with `_shared/healing_ai_gate.ts` first: the crisis check, then the pause, before the saved answer, the cache and the provider; a match removes the stage's stale AI output (checked, three attempts). Deno spy and order tests, twenty mutants, and the CI job runs them. **Task 4** is the app: the card (W9c's widget) on the post-mortem and portrait screens on `support_offered`, nothing saved, held in an account-scoped in-memory state wiped on sign-out and quick exit; "Need support now?" at the end of the reflection and a manual passage, neither gated; Healing's journey, start-context and readiness reads belong to the signed-in account (D8); widget tests, twelve goldens, seventeen mutants, the spec amendments and the W9e gate. Every SQL, Deno and Dart block below was run while writing this plan: the SQL on a throwaway copy of `attune_spec3a` (migration applied twice, `exit=0` both times; the contract red before with the message quoted and green after; every mutant red; the whole contract suite with no new FAIL: 150 PASS / 14 FAIL, the 14 the same files as before), the Deno tests and every TypeScript mutant, and the Dart in a scratch copy of the tree (every new test red before its code and green after, the goldens looked at, the analyzer clean on every touched file, every Dart mutant red, and the full `flutter test` green: 7036 passed (today's 7016 and the 20 new)).

**Tech Stack:** Flutter 3.29.1 (Dart 3.7), Riverpod 2.6, GoRouter, Supabase Postgres 17, Deno 2.8.1 (CI pins 2.8.1 and `.github/deno-w9.lock`), psql, Python 3 (edit, escape and mutation scripts). No new Dart package, no new Deno import beyond what the lock already holds (checked: the W9e Deno command runs with `--frozen`), no new ARB key.

**Spec:** `docs/superpowers/specs/2026-10-24-app-flow-identity-design.md`: §8 W9e (line ~1246: contents, depends on W9c, tests, gate), the owner approval O2 (§10 line ~1317 and the approval line ~1383: "Healing's AI insight gets the same pause, with the `self_disclosure` crisis check running first ... behind `healing_ai_insights`, under the same clinician gate"), §2.5 (flags, the production flag gate, `journal_ai_insights` as the model), §4.5 `analyse-journal-entry` (W9c's pattern as built, including batch-7 R-2: the check runs before the pause), §5.8 (the device wipe registry), §6.6, §7.2, §7.4, §2.2 (support surfaces never animate), §2.3 (accessibility), D8 (shared phones), D12. Format and pattern reference: `docs/superpowers/plans/2026-11-04-spec1-w9-opinions-safety.md` Tasks 9-10 and its ledger `.superpowers/sdd/2026-11-04-spec1-w9-opinions-safety/progress.md` (the W9 B7 and B8 rulings, carried below).

## Global Constraints

- Work in the main working tree on `main` (`/Users/user/attune`). W1-W9 are committed (HEAD `a1ccd91d`); the owner may have uncommitted edits (`supabase/.temp/cli-latest`, `backup-before-planning-p2.sql` at the time of writing): never revert, stash, stage, checkout or reformat them. Every edit to an existing file is an exact-string replacement made by a script that asserts each anchor occurs once; if an anchor has moved, apply the same change to the current text and say so in the task report.
- **NO commits.** No `git add`, `git commit`, `git stash`, `git checkout`, `git reset`, `git rm`. Tasks end with "Run tests", not "Commit".
- Never `dart format` a pre-existing file (the repo predates the 3.7 formatter). The Dart files this plan creates are given already formatted; each task's format step names exactly those paths (it changes nothing).
- **SQL:** only on `attune_spec3a`, only as `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f <file>`, **from the repo root** (the contract reads the dev script with `\set ... \`cat ...\``). Confirm the target first (`psql -X -d attune_spec3a -Atc 'select current_database()'` prints `attune_spec3a`). NEVER `attune_test`. NEVER run `scripts/local_pg_setup.sh`, `scripts/local_pg_grants.sql` or `scripts/local_pg_bootstrap.sql`. No DDL except by applying this plan's migration files; the mutants run inside one transaction each and are rolled back.
- **Migrations:** `20261104140000_healing_ai_insights_flag.sql` and `20261104140010_healing_ai_insights_flag_grants.sql` (spec §4.7 #20). They are later than every migration in the tree (the newest is W9's `20261104130010_opinion_remove_own_grants.sql`); if `ls supabase/migrations | sort | tail -1` shows anything at or after `20261104140000` when Task 1 starts, shift both to the next free hour and change every command below to match. Each file is one `BEGIN; ... COMMIT;`, `SET LOCAL lock_timeout = '5s'`, idempotent (applied twice, `exit=0` both times), grants explicit, nothing reaches `anon`. No new object, no new function, no trigger.
- **Flags are inserted false.** `healing_ai_insights` is inserted false by migration 20 with its gate row (gate row first, so it is gated from the moment it exists). Only `supabase/sql/dev_enable_spec1_flags.sql` (development only, `assert_development_project()` first) turns it on; it gains one line. `private_safety_check` (Spec 8) and `journal_ai_insights` are read, never written.
- **Nothing depends on an LLM.** The check is the hard-coded `self_disclosure` corpus (`_shared/ai_session_safety.ts`'s `self_harm` tier through `detectSelfDisclosure`) plus the pending-review list, run on the server before the pause, the saved answer, the cache and any provider call. The provider is injected and spied on in every test.
- **The W9 B7/B8 rulings, carried (each has a test and a mutant):**
  - *Detector first, before the pause* (B7 R-2): the crisis check runs before the `healing_ai_insights` pause and before any provider call, cache read, saved answer or persist; a match while paused still answers `support_offered` and removes stale output; no match while paused answers `paused` with nothing read or written.
  - *Fail closed* (B7): a `private_safety_check` read that throws, a detector that throws, or a reflection that cannot be read (not an object, nested past 8 levels, a value whose text throws) is a match; a `healing_ai_insights` read that throws or answers anything but `false` is paused. A journey the caller cannot load answers today's 404 and reaches nothing (the journal as built: "an unreadable entry ... answers its error and never reaches a provider").
  - *Delete stale AI output* (B7 P-23, I-1): on a match, every `healing_generation_jobs` row of that journey's stage (journey, caller, stage; every hash) is deleted and, when the loaded journey holds that stage's saved AI text, the text is set to null; `{error}` is checked and the delete tried at most 3 times; support is offered either way. The answer is exactly `{status:'support_offered'}`, which tells the app to hide any AI text it holds for the journey and stage it asked about.
  - *Fold typographic quotes and hyphens first* (B7 I-2, final N-1): the shared check folds apostrophes and quotes, checks invisible characters both removed and as spaces, and reads hyphens as spaces.
  - *Reuse the pending phrases* (B7 I-5, final I-2): the 52 phrases and 4 patterns of `journal_self_harm_pending.ts` move to `_shared/self_harm_pending.ts` unchanged and the journal file re-exports them; Healing imports the same object (a test asserts identity). **Never edit** `_shared/ai_session_safety.ts`, `_shared/self_disclosure.ts` or `_shared/chat_safety.ts` (the reviewed corpus, live in AI Sessions and ai-assist).
  - *Scope reads to the caller* (B7 I-3): the journey is read through the caller's client (RLS); every service-role read and write is limited to the caller's rows (`user_id`), including the cache read the functions already had.
  - *Shared phones* (B8 I-1, N-1): the card state is held in memory only, belongs to the signed-in account, starts again on an account change, and goes on sign-out and quick exit (`spec1.healing_support_memory`); an answer that lands after the account changed is dropped; Healing's journey, start context and readiness reads are re-read when the account changes and never show a journey read for another account. The tests hold the next account's read open and assert frame by frame; they never `pumpAndSettle` past that window.
  - *Support always reachable* (B8 I-4): the card, "Need support now?" and the manual passage do not read `healing_ai_insights`; the client never reads it at all (the server decides). Tests: `"Need support now?" ends the reflection, always ...`, `the manual passage needs no flag (W9 B8 I-4)`; mutants `no_reflection_link`, `no_manual_passage`.
  - *Mutant per fail-closed branch*: every branch above has a named mutant in its task.
- **Never touch:** `lib/features/games/**`, every Games route in `app_router.dart` (`test/architecture/games_untouched_test.dart` stays green), `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`, `lib/home/home_screen.dart` (its latch block, from `if (isAuthenticated && !_gateData.isComplete) {` to `_redirectingToOnboarding = false;`, stays byte-identical: Task 1 saves its hash, Task 4 compares), **anything under `lib/features/opinions/**` and `test/features/opinions/**`** (Opinions stays untouched: Healing gets its own link widget rather than a new `SupportLinkSource` value), every applied migration, every existing SQL contract (the new one is its own file), `_shared/ai_session_safety.ts`, `_shared/self_disclosure.ts`, `_shared/chat_safety.ts`, `analyse-journal-entry/index.ts`, `journal_pause.ts`, `lib/core/metrics/metric_counter.dart`, `lib/app/routing/app_router.dart`, `lib/app/app_shell.dart`.
- **Copy:** W9e adds no ARB key: the card is W9c's (`journal_supportCardBody`, `journal_supportSeeSupport`, `journal_supportNotNow`, the words the clinician signs) and the link is W9b's `support_needSupportNow`. If a later change needs a key, append it with W3's `.superpowers/sdd/2026-10-26-spec1-w3/arb_append.py` and generate with `flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package` (never W2 P-9's perl fix). The manual passage is a plain string like every manual entry, ASCII only. No partner is named (never "they" for the partner, never "both of you"); W9e shows no date (any later one goes through `MyDateFormat`).
- **Escapes:** files that need a non-ASCII character (`writer_crisis_check.test.ts` and the two handler tests) hold it as a `\uXXXX` escape, written by script: after creating each, run `$D/ascii_escapes.py` on it and check `grep -cP '[^\x00-\x7F]' <file>` prints `0`. An editor or tool may turn an escape into the character (this happened while writing this plan); the script turns it back. `writer_crisis_check.ts` itself is cut from `journal_handlers.ts` by script, so its escapes are the journal's bytes.
- **UI:** Material 3 from the app theme. The card is W9c's widget (`AllowLargeText`, a live region, 48 dp buttons, `onSurface` on `surfaceContainerLow`); the link is wrapped in `AllowLargeText` with a 48 dp target and `onSurface` text. Contrast at least 4.5:1 checked by `textContrastGuideline` (`expectFlowGuidelines`); nothing here uses the app's light `error`/`onError` pair (3.68:1). Labelled controls (`labeledTapTargetGuideline`), RTL, goldens at 1.0, 1.3, 2.0 and right to left (`expectFlowGoldens`). Nothing on the card animates (§2.2: it is a plain widget placed in the stage's body; no switcher, fade or slide above it, test-pinned); the card scrolls at large text so its buttons stay reachable.
- **No deploys.** `supabase db push`, function deploys, flag switches, the backfill and every gate are the owner's ("Owner deploy checklist"). Don't read `.env*`, credentials or the keychain. No `flutter pub get`.
- **Working folder** for baselines and scripts: `D=.superpowers/sdd/2026-11-04-spec1-w9e` (git-ignored); set `D` in every shell, at the repo root. Every script below is saved there first, exactly as given.
- **Regression gate (Task 4, last step):** every SQL contract on `attune_spec3a` shows no new FAIL against Task 1's baseline and `healing_ai_pause_contracts.sql`, `identity_foundation_contracts.sql`, the four `opinion_*` contracts and `account_deletion_contracts.sql` are PASS; the W9e Deno command passes with `--frozen`; the full `flutter test` passes with Task 1's count plus 20; `flutter analyze --no-pub lib test` shows no `error` line Task 1's baseline didn't; the Games test passes; the latch is unchanged; `git status --short lib/features/opinions test/features/opinions lib/features/games ATTUNE_SOUL.md ATTUNE_THESIS.md` prints nothing.

## Review Focus

1. **The answer arrives after the person left the stage screen** (they backed out while it was generating). Expect no error, nothing saved, and the card waiting when they come back this run. Test: Task 4 `Review Focus 1: an answer after the screen closed raises nothing, and the card waits for the next visit`; mutant `set_state_after_close`.
2. **Large text (2.0) on a phone: the card is taller than the space left on the stage.** Expect the card to scroll inside the stage and "See support" to stay reachable. Test: Task 4 `Review Focus 2: at 2.0 the card scrolls and See support stays reachable`; mutant `card_not_scrollable`.
3. **Crisis words split across two answers** ("Some nights I want to" / "kill myself"). Expect support (fail safe: the answers are read as one text, so the split is not a way past the check). Test: Task 3 `Review Focus 3: crisis words split across two answers are a match (fail safe)`.
4. **A reflection typed on a phone keyboard with a typographic apostrophe** ("I don't want to be here anymore" with U+2019). Expect support through the real handler, not only in the shared check's unit test. Test: Task 3 `Review Focus 4: a phone keyboard's typographic apostrophe still matches` (both functions); mutant `no_typography_fold` (Task 2).
5. **Healing's AI paused in production (the state until the clinician gate).** Expect the person to finish the stage as today (no card unless the check matched, "Continue" offered), and nothing read from the cache or sent to a provider. Tests: Task 3 `no match while paused: paused, before the saved ...` (both functions); Task 4 `paused keeps today's path ...` (asserts "Continue" is offered).

## Decisions found while verifying the code (read before Task 1)

Each is a verified fact about today's code (HEAD `a1ccd91d`) or the runtime, with the smallest change that keeps the spec's intent. *Changes spec intent* marks the ones the owner should see.

- **P-1 (timestamps).** Migration 20 is `20261104140000` + `…140010`; W9's newest is `20261104130010`.
- **P-2 (the flag).** `healing_ai_insights` is read by the two functions only, the way `analyse-journal-entry` reads `journal_ai_insights` (`featureFlagEnabled(adminClient, ...)`, off on any error): not through `private.spec1_flag_on` (it depends on no other flag), not in `get_public_app_config()`, and the app never reads it (the server decides; support never waits for it). Its gate row: `'W9e gate (the W9c clinician gate): the clinician and the suicide-prevention reviewer sign the Healing support card and the self-harm corpus'`. The identity contract's flag checks count `IN (...)` lists and `>= 10` gate rows, so a twelfth flag leaves it green (checked).
- **P-3 (what is checked).** Every string anywhere in the journey's `reflection_answers` (the person's words; the only free text either function sends to a provider), joined with newlines. `insights` and `patterns` are system-written labels and are not checked. `save_healing_reflection` already refuses anything but a JSON object, so "unreadable" only fails closed on rows nothing should write.
- **P-4 (the order).** Caller's journey read (RLS) → crisis check → pause → the saved answer (`*_status = 'completed'`) → evidence → cache (now also `.eq("user_id", ...)`) → insufficient-evidence row → provider. The pause sits before the saved answer, so a paused function returns nothing AI-written at all.
- **P-5 (a match removes the stage's stale AI output).** The stage's `healing_generation_jobs` rows (any hash; a job written before W9e for these words would otherwise be served by the cache) are deleted, and when the loaded journey holds that stage's saved AI text (`portrait_text`, `portrait_prompt`; or `post_mortem_observation`, `post_mortem_confidence`, `post_mortem_reflection_prompt`) it is set to null, scoped to `id` and `user_id`. The status, the completed time and the person's own `portrait_reflection` stay, so their progress is unchanged; the app shows such a stage as having no AI text (P-9). No write happens when there is nothing to clear (the journey's `updated_at` is not touched for nothing). *Changes spec intent* (as W9 P-23 did: "nothing persisted" also removes an old AI note).
- **P-6 (no count).** W9c counts `support_card_shown:journal`; W9e adds no metric key. A new server prefix or client key changes W1b's exact seed counts (26 client keys, 10 prefixes), which `identity_foundation_contracts.sql` and `test/core/metrics/metric_counter_test.dart` pin and W9e does not edit, and the counted link enum lives in the Opinions folder. Healing's "See support" and "Need support now?" open Support uncounted (a test asserts no metric). Owner question 3.
- **P-7 (`paused` on the phone).** Today any answer but `completed` records the stage as `insufficient_evidence` and says "There is not enough information for a grounded reflection yet." / "No portrait available yet." W9e keeps that path for `paused` (no new copy, the same thing builds already in people's hands do). Consequence: someone who reaches the stage while production is paused moves on and does not get that stage's AI later. *Changes spec intent* (the spec says nothing about Healing's paused state). Owner question 1.
- **P-8 (`support_offered` on the phone).** Nothing is saved (no `complete_healing_generated_stage` call); the stage's AI text the screen holds is dropped; the card shows in the stage's body, inside a scroll view; "Skip" and "Generate" stay (the person decides whether to move on; generating again re-checks). The state (`offered`, `hidden`) is `healingSupportProvider`: in memory, this account only, emptied on an account change, sign-out and quick exit. "Not now" puts the card away and keeps the AI text hidden; a later `completed` answer for that stage shows the fresh text. The card is W9c's widget with a new optional `onSeeSupport` (the journal's default, counted, is unchanged).
- **P-9 (a completed stage with no AI text).** Shown as "There is not enough information..." / "No portrait available yet." with "Continue" (today a completed post-mortem with no text fell through to "Ready for a grounded reflection..." with a "Continue" button). Reached after P-5 or the backfill.
- **P-10 (where the link goes).** "Need support now?" ends the Healing reflection (stage 1, where the person writes about the breakup), in its `ListView` (nothing above it moves). The manual passage "When a reflection sounds very hard" joins "What stays private" in `healing_docs.dart`. Neither has a flag. Healing's link widget mirrors W9b's `NeedSupportLink` (whose file is under `lib/features/opinions/`, untouched).
- **P-11 (D8 for Healing's reads).** `healingJourneyProvider`, `healingStartContextProvider` and `latestReadinessAttemptProvider` watch `healingAccountProvider` (the signed-in id), and `healingJourneyProvider` drops a journey whose `user_id` is not that account (a read answering for the previous session). `hasActiveSoloHealingJourneyProvider` is left as it is: it is a bool read at tap time by Conversations and the Me home (no content shown), and making it watch the auth stream makes `test/features/chat/chat_couples_locked_screen_healing_entry_test.dart` (which pumps without Supabase) fail. Known gap, carried. *Overruled in batch 3 (owner ruling): `hasActiveSoloHealingJourneyProvider` is scoped to the account too, and so are `startHealingJourneyProvider` (partners share the ended relationship, so its cached start could answer for the other) and Healing's `currentUserIdProvider`; the chat test that pumps without Supabase names its account with an override.*
- **P-12 (the split).** Each `index.ts` keeps `serve`, the clients, auth and the body parse; the action and its helpers move verbatim into `portrait_handler.ts` / `post_mortem_handler.ts` (only lines marked `Spec 1 W9e` change, checked by `verbatim_check.py`), with the provider and both flags injected (`HealingDeps`) so the tests spy on them. `chapter_scope.test.ts` (Spec 3b) reads the moved evidence in `portrait_handler.ts` (one line). The moved code keeps its 22 existing `deno lint` findings (`any`, an unused constant), exactly as today's `index.ts` has them.
- **P-13 (old builds).** A build from before W9e that gets `paused` or `support_offered` takes its not-completed path (records `insufficient_evidence`, "No portrait available yet."): no card. Release note (owner checklist 1).
- **P-14 (production changes at deploy).** Today Healing's AI runs in production with no flag. Once migration 20 is pushed and the two functions deploy, it answers `paused` until the clinician gate; the crisis check, the card, the link and the passage reach production at once, before the gate.
- **P-15 (new files the spec doesn't list).** `_shared/writer_crisis_check.ts`, `_shared/self_harm_pending.ts`, `_shared/healing_ai_gate.ts`, the two handler files, `_shared/test_support/{fake_supabase,healing_fakes}.ts`, `lib/features/healing/presentation/providers/healing_support_providers.dart`, `lib/features/healing/presentation/widgets/healing_support.dart`, the tests and their helpers. Task 4 amends the spec (§2.5, §4.5, §4.7, §5.1, §5.2, §5.8, §7.1, §7.2, §7.4, §8 W9e), each tagged *(amended W9e)*.

## Owner questions (open; the plan builds the recommendation)

1. **Healing while paused (P-7).** *Recommendation:* keep today's path (stage recorded `insufficient_evidence`, today's words), because it keeps journeys moving with no new copy before the clinician has read it; accept that people who pass a stage while paused don't get its AI later.
2. **Clearing a completed stage's saved AI text on a match, and the one-off backfill (P-5).** *Recommendation:* yes to both: a portrait or reflection written from words that now read as a crisis should not stay on the person's screen; run the backfill (checklist 3) after deploy and before the switch-on.
3. **Counting Healing's offers and link opens (P-6).** *Recommendation:* not in W9e; add `support_card_shown:healing` and `support_link_opened:healing` with the W1b seed tests in a later wave if the owner wants the numbers.
4. ~~**`hasActiveSoloHealingJourneyProvider` stays unscoped (P-11).**~~ *Resolved (owner ruling, batch 3): scoped to the account; nothing left to decide.*

## W1-W9 interfaces this plan consumes

- SQL: `public.feature_flags (key, enabled)` (SELECT for `authenticated` only, 20260953200100), `private.flag_production_gates (flag_key, gate, review_ref, recorded_by, recorded_at)` and its trigger `feature_flags_production_gate` (raises `flag:gate_evidence_required`), `public.production_flag_violations()`, `public.record_flag_gate_evidence(text, text)`, `private.attune_environment()` (forced in a transaction with `set_config('app.settings.attune_environment', 'production', true)`), `private.assert_development_project()`, `public.healing_journeys` (owner SELECT by RLS; `reflection_answers jsonb` object; the saved AI columns in P-5), `public.healing_generation_jobs (journey_id, user_id, stage IN ('post_mortem','portrait'), status, input_hash, output_*)` (client-revoked).
- Edge: `_shared/self_disclosure.ts` (`detectSelfDisclosure(text, {victimisation})`), `_shared/feature_flag.ts` (`featureFlagEnabled`, `DRAFT_SAFETY_CONTENT_FLAG = "private_safety_check"`), `_shared/gemini_json.ts` (`callGeminiJson(params) -> Promise<Record<string, unknown> | null>`), `_shared/chat_safety.ts` (`normalizeForTokenPhrase`), `analyse-journal-entry/journal_handlers.ts` (`foldTypography`, `disclosed`, `JournalDeps`), `analyse-journal-entry/journal_self_harm_pending.ts` (`JOURNAL_SELF_HARM_PENDING`, `matchesPendingSelfHarm`), `generate-healing-post-mortem/pattern_evidence.ts`.
- Dart: `JournalSupportCard({onNotNow})` (W9c), `openSupportNow` / `SupportLinkSource.journal` (W9b, read only), `currentUserProvider` (`auth_provider.dart`), `healingRepositoryProvider`, `supabaseClientProvider` (`healing_providers.dart`), `HealingRepository`, `HealingGenerationService`, `HealingJourney.fromJson`, `DeviceWipeRegistry`, `DeviceWipeEntry`, `WipeMoment`, `registerDeviceWipes`, `RouteNames.safetyResources`, `AllowLargeText`, `Spacing`, `AppLocalizations.support_needSupportNow`; test helpers `pumpFlowScreen`, `expectFlowGoldens`, `expectFlowGuidelines`, `FlowHarness.metrics` / `router` (`test/helpers/flow_harness.dart`).

## File map

- **Task 1.** Create `supabase/migrations/20261104140000_healing_ai_insights_flag.sql`, `supabase/migrations/20261104140010_healing_ai_insights_flag_grants.sql`, `supabase/tests/healing_ai_pause_contracts.sql`. Modify `supabase/sql/dev_enable_spec1_flags.sql` (one line).
- **Task 2.** Create (by script) `supabase/functions/_shared/self_harm_pending.ts`, `supabase/functions/_shared/writer_crisis_check.ts`; create `supabase/functions/_shared/writer_crisis_check.test.ts`. Modify (by script) `supabase/functions/analyse-journal-entry/journal_handlers.ts`, `supabase/functions/analyse-journal-entry/journal_self_harm_pending.ts` (now a re-export).
- **Task 3.** Create `supabase/functions/_shared/healing_ai_gate.ts`, `_shared/healing_ai_gate.test.ts`, `_shared/test_support/fake_supabase.ts`, `_shared/test_support/healing_fakes.ts`, `generate-healing-portrait/portrait_handler.test.ts`, `generate-healing-post-mortem/post_mortem_handler.test.ts`; create (by script) `generate-healing-portrait/portrait_handler.ts`, `generate-healing-post-mortem/post_mortem_handler.ts`. Modify (by script) both `index.ts`, `generate-healing-portrait/chapter_scope.test.ts` (one line), `.github/workflows/tests.yml` (the Deno job's name and command).
- **Task 4.** Create `lib/features/healing/presentation/providers/healing_support_providers.dart`, `lib/features/healing/presentation/widgets/healing_support.dart`, `test/features/healing/w9e/support/healing_fakes.dart`, `test/features/healing/w9e/healing_support_test.dart` (+ 12 goldens), `test/features/healing/w9e/healing_account_test.dart`. Modify (by script) `lib/features/healing/presentation/providers/healing_providers.dart`, `lib/features/healing/presentation/screens/{healing_post_mortem_screen,healing_portrait_screen,healing_reflection_screen}.dart`, `lib/features/reflection_journal/presentation/widgets/journal_support_card.dart`, `lib/app/device_wipes.dart`, `lib/app/documentations/user_manual/data/healing_docs.dart`, `docs/superpowers/specs/2026-10-24-app-flow-identity-design.md` (amendments).

**Not edited:** everything in "Never touch", `lib/features/healing/services/healing_generation_service.dart`, `lib/features/healing/data/**`, `healing_journey_screen.dart`, `healing_pattern_awareness_screen.dart`, `healing_readiness_screen.dart`, `lib/i10n/**`, `lib/app/feature_flag_refresher.dart`, `scripts/local_pg_grants.sql` (no new object), every existing test except the one line in `chapter_scope.test.ts`.

---

### Task 1: Baselines; migration 20, the flag and its gate (spec §2.5, §4.7 #20, §8 W9e; P-1, P-2)

**Files:**
- Create: `supabase/migrations/20261104140000_healing_ai_insights_flag.sql`
- Create: `supabase/migrations/20261104140010_healing_ai_insights_flag_grants.sql`
- Create: `supabase/tests/healing_ai_pause_contracts.sql`
- Modify: `supabase/sql/dev_enable_spec1_flags.sql` (one line after `('journal_ai_insights', true),`)
- Scratch: `$D/ascii_escapes.py`, `$D/mutants_t1.py`, the baselines

**Interfaces:**
- Consumes: the W1c flag gate (`private.flag_production_gates`, the `feature_flags` trigger, `production_flag_violations()`), `private.assert_development_project()`.
- Produces: the row `public.feature_flags ('healing_ai_insights', false)` and its gate row. Task 3's `HEALING_AI_FLAG = "healing_ai_insights"` reads it.

- [ ] **Step 1: Record the baselines**

```bash
D=.superpowers/sdd/2026-11-04-spec1-w9e; mkdir -p $D
git status --short > $D/status-before.txt; cat $D/status-before.txt
ls supabase/migrations | sort | tail -1
psql -X -d attune_spec3a -Atc 'select current_database()'
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $f"; else echo "FAIL $f"; fi
done > $D/sql-baseline.txt
echo "PASS $(grep -c ^PASS $D/sql-baseline.txt) FAIL $(grep -c ^FAIL $D/sql-baseline.txt)"
(cd supabase/functions && NO_COLOR=1 deno test --allow-read --allow-env --lock=../../.github/deno-w9.lock --frozen _shared/unicode_normaliser.test.ts analyse-journal-entry/ generate-healing-portrait/ generate-healing-post-mortem/ 2>&1 | grep -E '^(ok|FAILED) \|')
(cd supabase/functions && NO_COLOR=1 deno test --allow-read --allow-env _shared/self_disclosure.test.ts _shared/assistant_input.test.ts 2>&1 | grep -E '^(ok|FAILED) \|')
flutter analyze --no-pub lib test 2>&1 | grep -E '^\s*error ' > $D/analyze-baseline.txt; wc -l < $D/analyze-baseline.txt
sed -n '/if (isAuthenticated && !_gateData.isComplete) {/,/_redirectingToOnboarding = false;/p' lib/home/home_screen.dart | shasum > $D/latch.sha; cat $D/latch.sha
flutter test --no-pub 2>&1 | tail -1 | tee $D/flutter-baseline.txt
```

Expected: the status lists only the owner's two entries; `20261104130010_opinion_remove_own_grants.sql`; `attune_spec3a`; about `PASS 149 FAIL 14` (the 14 FAILs are pre-existing AI-session, quota, Together and couple-map contracts, state-dependent; whatever the file says is the baseline); `ok | 47 passed | 0 failed`; `ok | 10 passed | 0 failed`; the analyzer line count (the baseline, whatever it is); `8fe95dbcc4e4e825401daaf612409114e5bed421  -`; `All tests passed!` with the count (`+7016` at the time of writing) that Task 4 compares against.

- [ ] **Step 2: Save the escape script** (used by Tasks 2 and 3)

Create `$D/ascii_escapes.py` with exactly:

```python
# Rewrites every non-ASCII character in the given files as a \uXXXX escape
# (the backslash is chr(92), so no tool can turn it back into the character).
import pathlib, sys
B = chr(92)
for name in sys.argv[1:]:
    p = pathlib.Path(name)
    t = p.read_text()
    out = []
    for ch in t:
        cp = ord(ch)
        if cp < 128:
            out.append(ch)
        elif cp <= 0xFFFF:
            out.append(B + "u%04X" % cp)
        else:
            cp -= 0x10000
            out.append(B + "u%04X" % (0xD800 + (cp >> 10)) + B + "u%04X" % (0xDC00 + (cp & 0x3FF)))
    p.write_text("".join(out))
    print(name, sum(1 for ch in t if ord(ch) > 127), "escaped")
```

- [ ] **Step 3: Write the failing contract**

Create `supabase/tests/healing_ai_pause_contracts.sql` with exactly:

```sql
-- Spec 1 W9e (spec 2.5, 7.1, 8 W9e; owner approval O2): healing_ai_insights
-- exists and is off; production refuses to switch it on without the W9c
-- clinician gate's evidence and lists it if it is on; clients read it and
-- never write it; the development script turns it on.
-- Run from the repo root (section E reads the dev script):
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/healing_ai_pause_contracts.sql
\set dev_script `cat supabase/sql/dev_enable_spec1_flags.sql`
BEGIN;

CREATE FUNCTION pg_temp.error_of(p_sql text) RETURNS text
LANGUAGE plpgsql AS $fn$
BEGIN
  EXECUTE p_sql;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RETURN SQLERRM;
END;
$fn$;

SELECT set_config('w9e.dev_script', :'dev_script', true) AS dev_script_loaded \g /dev/null

DO $$
DECLARE
  v_msg text;
BEGIN
  -- A. The flag row exists, off.
  IF NOT EXISTS (SELECT 1 FROM public.feature_flags
                  WHERE key = 'healing_ai_insights' AND enabled = false) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: healing_ai_insights is missing or on';
  END IF;

  -- B. Its production gate row: the W9c clinician gate, no evidence yet.
  IF NOT EXISTS (SELECT 1 FROM private.flag_production_gates
                  WHERE flag_key = 'healing_ai_insights'
                    AND gate LIKE 'W9e gate (the W9c clinician gate):%'
                    AND review_ref IS NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: healing_ai_insights has no clinician gate row';
  END IF;

  -- C. Production refuses it without evidence; on in development is
  -- listed the moment the project reads production.
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  v_msg := pg_temp.error_of($q$UPDATE public.feature_flags SET enabled = true WHERE key = 'healing_ai_insights'$q$);
  IF v_msg IS DISTINCT FROM 'flag:gate_evidence_required' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: healing_ai_insights went on in production without evidence (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM set_config('app.settings.attune_environment', '', true);
  UPDATE public.feature_flags SET enabled = true WHERE key = 'healing_ai_insights';
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  IF NOT EXISTS (SELECT 1 FROM public.production_flag_violations() AS v WHERE v = 'healing_ai_insights') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production_flag_violations missed healing_ai_insights';
  END IF;
  PERFORM set_config('app.settings.attune_environment', '', true);
  UPDATE public.feature_flags SET enabled = false WHERE key = 'healing_ai_insights';

  -- D. Clients read flags and never write them; the gate table is the owner's.
  IF NOT has_table_privilege('authenticated', 'public.feature_flags', 'SELECT')
     OR has_table_privilege('authenticated', 'public.feature_flags', 'INSERT, UPDATE, DELETE, TRUNCATE')
     OR has_table_privilege('anon', 'public.feature_flags', 'SELECT, INSERT, UPDATE, DELETE')
     OR has_table_privilege('authenticated', 'private.flag_production_gates', 'SELECT, INSERT, UPDATE, DELETE')
     OR has_table_privilege('anon', 'private.flag_production_gates', 'SELECT, INSERT, UPDATE, DELETE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the flag tables'' grants are wrong';
  END IF;

  -- E. The development script turns it on with the other Spec 1 flags.
  IF position($t$('healing_ai_insights', true)$t$ IN current_setting('w9e.dev_script')) = 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dev_enable_spec1_flags.sql does not turn healing_ai_insights on';
  END IF;

  RAISE NOTICE 'healing_ai_pause_contracts: PASS';
END $$;

ROLLBACK;
```

- [ ] **Step 4: Run it to see it fail**

Run: `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/healing_ai_pause_contracts.sql; echo "exit=$?"`
Expected: `ERROR:  CONTRACT VIOLATED: healing_ai_insights is missing or on` and `exit=3`.

- [ ] **Step 5: Write migration 20 and its twin**

Create `supabase/migrations/20261104140000_healing_ai_insights_flag.sql` with exactly:

```sql
-- Spec 1 W9e, migration 20 (spec 2.5, 4.7 #20, 8 W9e; owner approval O2):
-- healing_ai_insights, Healing's AI pause. One flag row, inserted false
-- (migrations never turn a flag on), read by generate-healing-portrait and
-- generate-healing-post-mortem (_shared/healing_ai_gate.ts): off means no
-- provider call for either stage and status 'paused', unless the crisis
-- check matches first: 'support_offered'. Its production gate row is the
-- same clinician gate as W9c. The gate row goes in first, so the flag is
-- gated from the moment it exists. No new object.
-- Grants in 20261104140010_healing_ai_insights_flag_grants.sql.
BEGIN;
-- public.feature_flags carries the production gate trigger: fail fast
-- rather than queue every flag read and write behind it.
SET LOCAL lock_timeout = '5s';

INSERT INTO private.flag_production_gates (flag_key, gate) VALUES
  ('healing_ai_insights', 'W9e gate (the W9c clinician gate): the clinician and the suicide-prevention reviewer sign the Healing support card and the self-harm corpus')
ON CONFLICT (flag_key) DO NOTHING;

INSERT INTO public.feature_flags (key, enabled) VALUES
  ('healing_ai_insights', false)
ON CONFLICT (key) DO NOTHING;
COMMIT;
```

Create `supabase/migrations/20261104140010_healing_ai_insights_flag_grants.sql` with exactly:

```sql
-- Spec 1 W9e: grants for 20261104140000_healing_ai_insights_flag.sql. No new
-- object: the flag row and its gate row live in tables whose grants are
-- re-asserted here exactly as they stand (20260953200100,
-- 20261025100410): clients read flags and never write them; nobody but the
-- owner reaches the gate table.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.feature_flags FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.feature_flags TO authenticated;
REVOKE ALL ON private.flag_production_gates FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
```

- [ ] **Step 6: The dev script turns it on (development only)**

```bash
python3 -I - supabase/sql/dev_enable_spec1_flags.sql <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); t = p.read_text()
old = "    ('journal_ai_insights', true),\n"
assert t.count(old) == 1 and "healing_ai_insights" not in t
p.write_text(t.replace(old, old + "    ('healing_ai_insights', true),\n"))
print("dev script: ok")
PY
```

- [ ] **Step 7: Apply twice, then the contract passes**

```bash
for i in 1 2; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261104140000_healing_ai_insights_flag.sql; echo "migration $i exit=$?"
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261104140010_healing_ai_insights_flag_grants.sql; echo "twin $i exit=$?"
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/healing_ai_pause_contracts.sql; echo "exit=$?"
psql -X -d attune_spec3a -Atc "select key, enabled from public.feature_flags where key = 'healing_ai_insights'"
```

Expected: four `exit=0`; `NOTICE:  healing_ai_pause_contracts: PASS` and `exit=0`; `healing_ai_insights|f` (the dev script is never run here).

- [ ] **Step 8: Mutation checks (each must fail the contract; all rolled back)**

Create `$D/mutants_t1.py` with exactly:

```python
# Spec 1 W9e Task 1 mutants. Each runs in ONE transaction on the target
# database and is rolled back: the flag and gate rows are deleted, the
# mutated migration and twin are applied (their BEGIN/COMMIT stripped),
# then the contract body runs. Each must fail with CONTRACT VIOLATED.
# Run from the repo root: python3 -I <this> <database>
import pathlib, subprocess, sys, tempfile
DB = sys.argv[1]
MIG = pathlib.Path("supabase/migrations/20261104140000_healing_ai_insights_flag.sql").read_text()
TWIN = pathlib.Path("supabase/migrations/20261104140010_healing_ai_insights_flag_grants.sql").read_text()
CONTRACT = pathlib.Path("supabase/tests/healing_ai_pause_contracts.sql").read_text()
DEV = pathlib.Path("supabase/sql/dev_enable_spec1_flags.sql").read_text()

def inner(sql, start, end):
    a = sql.index(start) + len(start)
    return sql[a:sql.rindex(end)]

def run(mig, twin, dev):
    with tempfile.TemporaryDirectory() as d:
        devf = pathlib.Path(d) / "dev.sql"
        devf.write_text(dev)
        body = inner(CONTRACT, "\nBEGIN;\n", "\nROLLBACK;\n")
        sql = (
            f"\\set dev_script `cat {devf}`\n"
            "BEGIN;\n"
            "DELETE FROM public.feature_flags WHERE key = 'healing_ai_insights';\n"
            "DELETE FROM private.flag_production_gates WHERE flag_key = 'healing_ai_insights';\n"
            + inner(mig, "\nBEGIN;\n", "\nCOMMIT;\n") + "\n"
            + inner(twin, "\nBEGIN;\n", "\nCOMMIT;\n") + "\n"
            + body + "\nROLLBACK;\n"
        )
        f = pathlib.Path(d) / "m.sql"
        f.write_text(sql)
        r = subprocess.run(["psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-d", DB, "-f", str(f)],
                           capture_output=True, text=True)
        out = (r.stdout + r.stderr)
        line = next((l for l in out.splitlines() if "CONTRACT VIOLATED" in l or "PASS" in l or "ERROR" in l), out.strip()[-120:])
        return line.split("NOTICE:  ")[-1].split("ERROR:  ")[-1]

def mut(text, a, b):
    assert text.count(a) == 1, a
    return text.replace(a, b)

print("unmutated:", run(MIG, TWIN, DEV))
M = {
    "flag_inserted_on": (mut(MIG, "  ('healing_ai_insights', false)\n", "  ('healing_ai_insights', true)\n"), TWIN, DEV),
    "no_flag_row": (mut(MIG, "INSERT INTO public.feature_flags (key, enabled) VALUES\n  ('healing_ai_insights', false)\nON CONFLICT (key) DO NOTHING;\n", ""), TWIN, DEV),
    "no_gate_row": (mut(MIG, MIG[MIG.index("INSERT INTO private.flag_production_gates"):MIG.index("INSERT INTO public.feature_flags")], ""), TWIN, DEV),
    "wrong_gate": (mut(MIG, "'W9e gate (the W9c clinician gate):", "'W9e gate:"), TWIN, DEV),
    "client_writes_flags": (MIG, mut(TWIN, "GRANT SELECT ON public.feature_flags TO authenticated;\n", "GRANT SELECT, UPDATE ON public.feature_flags TO authenticated;\n"), DEV),
    "anon_reads_gates": (MIG, mut(TWIN, "REVOKE ALL ON private.flag_production_gates FROM PUBLIC, anon, authenticated, service_role;\n", "GRANT USAGE ON SCHEMA private TO anon;\nGRANT SELECT ON private.flag_production_gates TO anon;\n"), DEV),
    "dev_script_misses_it": (MIG, TWIN, mut(DEV, "    ('healing_ai_insights', true),\n", "")),
}
for name, args in M.items():
    print(name + ":", run(*args))
```

Run: `python3 -I $D/mutants_t1.py attune_spec3a`
Expected:
```
unmutated: healing_ai_pause_contracts: PASS
flag_inserted_on: CONTRACT VIOLATED: healing_ai_insights is missing or on
no_flag_row: CONTRACT VIOLATED: healing_ai_insights is missing or on
no_gate_row: CONTRACT VIOLATED: healing_ai_insights has no clinician gate row
wrong_gate: CONTRACT VIOLATED: healing_ai_insights has no clinician gate row
client_writes_flags: CONTRACT VIOLATED: the flag tables' grants are wrong
anon_reads_gates: CONTRACT VIOLATED: the flag tables' grants are wrong
dev_script_misses_it: CONTRACT VIOLATED: dev_enable_spec1_flags.sql does not turn healing_ai_insights on
```

- [ ] **Step 9: Run tests**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/healing_ai_pause_contracts.sql; echo "exit=$?"
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql >/dev/null 2>&1; echo "identity exit=$?"
psql -X -d attune_spec3a -Atc "select has_schema_privilege('anon', 'private', 'USAGE'), (select enabled from public.feature_flags where key = 'healing_ai_insights')"
git status --short
```

Expected: `exit=0`; `identity exit=0`; `f|f` (the mutants left nothing behind); the status adds exactly the two migrations, the contract and ` M supabase/sql/dev_enable_spec1_flags.sql`.

### Task 2: One crisis check for the Journal and Healing (spec §4.5; W9 B7 I-2, I-5, final I-2, N-1; P-15)

**Files:**
- Create (by `$D/w9e_share_check.py`): `supabase/functions/_shared/self_harm_pending.ts`, `supabase/functions/_shared/writer_crisis_check.ts`
- Create: `supabase/functions/_shared/writer_crisis_check.test.ts`
- Modify (by the same script): `supabase/functions/analyse-journal-entry/journal_handlers.ts` (the fold and the check replaced by the shared ones; `foldTypography` re-exported), `supabase/functions/analyse-journal-entry/journal_self_harm_pending.ts` (now a re-export)

**Interfaces:**
- Consumes: `detectSelfDisclosure`, `normalizeForTokenPhrase` (unchanged files).
- Produces: `writerTextDiscloses(text: string, victimisation: boolean | null): boolean` (true for a match and for any doubt: `victimisation` null, a detector that throws) and `foldTypography(text: string): string` in `_shared/writer_crisis_check.ts`; `JOURNAL_SELF_HARM_PENDING` and `matchesPendingSelfHarm(text: string): boolean` in `_shared/self_harm_pending.ts` (also re-exported, as the same objects, from `analyse-journal-entry/journal_self_harm_pending.ts`). Task 3's gate calls `writerTextDiscloses`.

- [ ] **Step 1: Write the failing test**

Create `supabase/functions/_shared/writer_crisis_check.test.ts` with exactly the text below, then turn any non-ASCII character back into its escape:

```ts
// Spec 1 W9e: the writer-facing crisis check, shared by the Journal (W9c)
// and Healing (W9e). Deterministic; any doubt is a match.
import { assert, assertEquals, assertStrictEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { foldTypography, writerTextDiscloses } from "./writer_crisis_check.ts";
import { JOURNAL_SELF_HARM_PENDING, matchesPendingSelfHarm } from "./self_harm_pending.ts";
import * as journalList from "../analyse-journal-entry/journal_self_harm_pending.ts";

const ORDINARY = "We walked by the lagoon and I thought about what I would do differently next time.";
const THROWS = { toString(): string { throw new Error("unreadable"); } } as unknown as string;

Deno.test("the reviewed corpus and the pending list match, whatever private_safety_check says", () => {
  for (const victimisation of [true, false]) {
    for (const text of ["I want to kill myself", "Some days I want to die", "I took all of my pills", "nobody would even miss me"]) {
      assert(writerTextDiscloses(text, victimisation), `${text} (victimisation ${victimisation})`);
    }
  }
});

Deno.test("the [DRAFT] victimisation list only with private_safety_check on", () => {
  assert(writerTextDiscloses("he hit me last night", true));
  assertEquals(writerTextDiscloses("he hit me last night", false), false);
});

Deno.test("ordinary words do not match", () => {
  assertEquals(writerTextDiscloses(ORDINARY, true), false);
  assertEquals(writerTextDiscloses("", true), false);
});

Deno.test("typographic apostrophes and quotes are folded first", () => {
  assert(writerTextDiscloses("I don\u2019t want to exist", false));
  assert(writerTextDiscloses("\u201CI want to die\u201D", false));
  assertEquals(foldTypography("don\u2019t \u201Chi\u201D"), "don't \"hi\"");
});

Deno.test("hyphens read as spaces, invisible characters neither split nor join a phrase", () => {
  assert(writerTextDiscloses("thinking about an over-dose", false));
  assert(writerTextDiscloses("thinking about an over\u2011dose", false));
  assert(writerTextDiscloses("I want to kill\u200Bmyself", false));
  assert(writerTextDiscloses("I want to ki\u00ADll myself", false));
});

Deno.test("fail safe: an unknown flag or a detector that throws is a match", () => {
  assert(writerTextDiscloses(ORDINARY, null));
  assert(writerTextDiscloses(THROWS, false));
});

Deno.test("one pending list for the Journal and Healing, never a copy", () => {
  assertStrictEquals(journalList.JOURNAL_SELF_HARM_PENDING, JOURNAL_SELF_HARM_PENDING);
  assertStrictEquals(journalList.matchesPendingSelfHarm, matchesPendingSelfHarm);
  assertEquals(JOURNAL_SELF_HARM_PENDING.config_version, "journal_self_harm_pending-0.3.0");
  assertEquals(JOURNAL_SELF_HARM_PENDING.review_status, "PENDING CLINICIAN REVIEW (W9c gate)");
  assertEquals(JOURNAL_SELF_HARM_PENDING.phrases.length, 52);
  assertEquals(JOURNAL_SELF_HARM_PENDING.patterns.length, 4);
});
```

```bash
python3 -I $D/ascii_escapes.py supabase/functions/_shared/writer_crisis_check.test.ts
grep -cP '[^\x00-\x7F]' supabase/functions/_shared/writer_crisis_check.test.ts
grep -c 'u200B' supabase/functions/_shared/writer_crisis_check.test.ts
```

Expected: `0`, then `1` (the zero-width space in "kill", U+200B, "myself" is an escape, not an invisible character).

- [ ] **Step 2: Run it to make sure it fails**

Run: `(cd supabase/functions && NO_COLOR=1 deno test --allow-read --allow-env _shared/writer_crisis_check.test.ts 2>&1 | grep -E 'TS2307|error:' | head -3)`
Expected: `TS2307 [ERROR]: Cannot find module '.../_shared/writer_crisis_check.ts'.` and `error: Type checking failed.`

- [ ] **Step 3: Move the list, the fold and the check to `_shared`**

Create `$D/w9e_share_check.py` with exactly:

```python
# Spec 1 W9e, Task 2: one crisis check for the Journal and Healing.
#   1. the pending-review list moves, verbatim, to _shared/self_harm_pending.ts
#      (the old file re-exports it);
#   2. the fold and the check move, verbatim, from journal_handlers.ts to
#      _shared/writer_crisis_check.ts;
#   3. journal_handlers.ts calls the shared check (and re-exports the fold
#      its tests import).
# Run from the repo root: python3 -I <this> supabase/functions
import pathlib, sys

root = pathlib.Path(sys.argv[1])
old_list = root / "analyse-journal-entry" / "journal_self_harm_pending.ts"
new_list = root / "_shared" / "self_harm_pending.ts"
check = root / "_shared" / "writer_crisis_check.ts"
handlers = root / "analyse-journal-entry" / "journal_handlers.ts"
for p in (new_list, check):
    assert not p.exists(), f"{p} exists already: stop and report"

# 1. The pending list.
src = old_list.read_text()
IMPORT = 'import { normalizeForTokenPhrase } from "../_shared/chat_safety.ts";\n'
assert src.count(IMPORT) == 1
head, body = src.split(IMPORT, 1)
assert head.startswith("// supabase/functions/analyse-journal-entry/journal_self_harm_pending.ts\n")
assert "PENDING CLINICIAN REVIEW (W9c gate)" in body
keep_from = head.index("// Phrases are in normalizeForTokenPhrase's form")
new_list.write_text(
    "// supabase/functions/_shared/self_harm_pending.ts\n"
    "//\n"
    "// Spec 1 W9 fix round 1 (batch-7-review.md I-5): self-harm phrasings that\n"
    "// the reviewed sessions corpus (_shared/ai_session_safety.ts, reused by\n"
    "// _shared/self_disclosure.ts) does not catch. Those two files are never\n"
    "// touched (global constraints) and are live in AI Sessions and ai-assist,\n"
    "// so the writer-facing crisis check (_shared/writer_crisis_check.ts) runs\n"
    "// this list next to them instead: the Journal (W9c) and Healing (W9e).\n"
    "// Spec 1 W9e moved it here from analyse-journal-entry/\n"
    "// journal_self_harm_pending.ts, unchanged (its name and config_version\n"
    "// are the list the clinician signs); that file now re-exports it.\n"
    "//\n"
    "// PENDING CLINICIAN REVIEW: a W9c gate item, and W9e's (the same gate).\n"
    "// The suicide-prevention reviewer rules on every phrase before\n"
    "// journal_ai_insights or healing_ai_insights goes on in production, and\n"
    "// the reviewed ones move into the shared corpus (carry to Spec 8).\n"
    "// It runs always, like the reviewed self-harm list: a false positive only\n"
    "// shows a support card, a miss sends crisis words to a provider.\n"
    "//\n"
    + head[keep_from:]
    + 'import { normalizeForTokenPhrase } from "./chat_safety.ts";\n'
    + body
)
old_list.write_text(
    "// supabase/functions/analyse-journal-entry/journal_self_harm_pending.ts\n"
    "//\n"
    "// Spec 1 W9e: the pending-review self-harm list moved, unchanged, to\n"
    "// _shared/self_harm_pending.ts, so the Journal and Healing share one list\n"
    "// (never a copy). Re-exported here so every journal import still works.\n"
    'export { JOURNAL_SELF_HARM_PENDING, matchesPendingSelfHarm } from "../_shared/self_harm_pending.ts";\n'
)
assert new_list.read_text().split('from "./chat_safety.ts";\n', 1)[1] == body

# 2. The fold and the check, from journal_handlers.ts.
t = handlers.read_text()
START = "// Review I-2: typographic apostrophes (iOS smart punctuation, pasted text)\n"
FOLD_END = "function pendingSelfHarm(text: string): boolean {\n"
END = "// deno-lint-ignore no-explicit-any\nasync function removeOldReflection("
for a in (START, FOLD_END, END):
    assert t.count(a) == 1, a
fold = t[t.index(START):t.index(FOLD_END)]
assert "export function foldTypography(text: string): string {" in fold
check.write_text(
    "// supabase/functions/_shared/writer_crisis_check.ts\n"
    "//\n"
    "// Spec 1 W9c and W9e (spec 4.5; D12; owner approval O2): the writer-facing\n"
    "// crisis check, one implementation for the Journal (analyse-journal-entry)\n"
    "// and Healing (generate-healing-portrait, generate-healing-post-mortem).\n"
    "// Deterministic: no provider, no model. Self-harm (the reviewed sessions\n"
    "// corpus, through detectSelfDisclosure) and the pending-review list\n"
    "// (self_harm_pending.ts) always run; the [DRAFT] victimisation list only\n"
    "// when the caller passes private_safety_check on (review A-4). The fold\n"
    "// and the check moved here from analyse-journal-entry/journal_handlers.ts\n"
    "// in W9e, unchanged. Hyphens read as spaces: normalizeForTokenPhrase keeps\n"
    "// only letters, digits, apostrophes and spaces, and the pending matcher\n"
    "// folds every dash first (W9 final re-review N-1).\n"
    'import { detectSelfDisclosure } from "./self_disclosure.ts";\n'
    'import { matchesPendingSelfHarm } from "./self_harm_pending.ts";\n'
    "\n"
    + fold
    + "/// True for a match, and for anything that stops the check from running:\n"
    "/// [victimisation] null (the private_safety_check read threw, so it is\n"
    "/// unknown) or a detector that throws. The writer is offered support and\n"
    "/// nothing reaches a provider (fail safe).\n"
    "export function writerTextDiscloses(text: string, victimisation: boolean | null): boolean {\n"
    "  if (victimisation === null) return true;\n"
    "  try {\n"
    "    const folded = foldTypography(text);\n"
    '    for (const t of [folded.replace(INVISIBLE, ""), folded.replace(INVISIBLE, " ")]) {\n'
    "      if (detectSelfDisclosure(t, { victimisation }) !== null) return true;\n"
    "      if (matchesPendingSelfHarm(t)) return true;\n"
    "    }\n"
    "    return false;\n"
    "  } catch {\n"
    "    return true;\n"
    "  }\n"
    "}\n"
)

# 3. The journal calls it.
def once(old, new):
    global t
    assert t.count(old) == 1, old
    t = t.replace(old, new)

once('import { detectSelfDisclosure } from "../_shared/self_disclosure.ts";\n', "")
once('import { matchesPendingSelfHarm } from "./journal_self_harm_pending.ts";\n',
     "// Spec 1 W9e: the fold and the check are shared with Healing.\n"
     'import { foldTypography, writerTextDiscloses } from "../_shared/writer_crisis_check.ts";\n'
     "export { foldTypography };\n")
t = t[:t.index(START)] + (
    "/// True for a match, and for anything that stops the check from running\n"
    "/// (an unknown flag, a detector that throws, an entry whose text cannot be\n"
    "/// read): the writer is offered support and nothing reaches the provider.\n"
    "/// Spec 1 W9e: the check itself is _shared/writer_crisis_check.ts.\n"
    "function disclosed(entry: EntryText, victimisation: boolean | null): boolean {\n"
    "  try {\n"
    '    return writerTextDiscloses(`${entry.title ?? ""}\\n${entry.content ?? ""}`, victimisation);\n'
    "  } catch {\n"
    "    return true;\n"
    "  }\n"
    "}\n"
    "\n"
) + t[t.index(END):]
handlers.write_text(t)
print("shared check: ok")
```

Run: `python3 -I $D/w9e_share_check.py supabase/functions`
Expected: `shared check: ok`.

- [ ] **Step 4: Run the tests**

```bash
(cd supabase/functions && NO_COLOR=1 deno test --allow-read --allow-env --lock=../../.github/deno-w9.lock --frozen _shared/unicode_normaliser.test.ts _shared/writer_crisis_check.test.ts analyse-journal-entry/ 2>&1 | grep -E '^(ok|FAILED) \|')
(cd supabase/functions && NO_COLOR=1 deno check analyse-journal-entry/index.ts 2>&1 | tail -1)
```

Expected: `ok | 49 passed | 0 failed` (the journal's 35 and the normaliser's unchanged, 7 new); `Check analyse-journal-entry/index.ts`.

- [ ] **Step 5: Nothing moved by accident; the reviewed corpus untouched**

```bash
diff <(git show HEAD:supabase/functions/analyse-journal-entry/journal_handlers.ts | sed -n '/^const APOSTROPHES/,/^const INVISIBLE/p') <(sed -n '/^const APOSTROPHES/,/^const INVISIBLE/p' supabase/functions/_shared/writer_crisis_check.ts) && echo fold-verbatim
diff <(git show HEAD:supabase/functions/analyse-journal-entry/journal_self_harm_pending.ts | sed -n '/^export const JOURNAL_SELF_HARM_PENDING/,$p') <(sed -n '/^export const JOURNAL_SELF_HARM_PENDING/,$p' supabase/functions/_shared/self_harm_pending.ts) && echo list-verbatim
git diff --quiet -- supabase/functions/_shared/ai_session_safety.ts supabase/functions/_shared/self_disclosure.ts supabase/functions/_shared/chat_safety.ts supabase/functions/analyse-journal-entry/index.ts supabase/functions/analyse-journal-entry/journal_pause.ts && echo corpus-untouched
git diff --stat -- supabase/functions/analyse-journal-entry/journal_handlers.ts
grep -cP '[^\x00-\x7F]' supabase/functions/_shared/writer_crisis_check.ts supabase/functions/_shared/self_harm_pending.ts
```

Expected: `fold-verbatim`, `list-verbatim`, `corpus-untouched`; `1 file changed, 7 insertions(+), 29 deletions(-)` (the fold and the check leave; the shared import, the re-export and `disclosed`, now one call inside its own `try`, stay); `0` for both files.

- [ ] **Step 6: Mutation checks (each must turn a test red)**

Create `$D/mutants_t2.py` with exactly:

```python
# Spec 1 W9e Task 2 mutants: each must turn a test red. Run from
# supabase/functions.
import os, pathlib, subprocess
CMD = ["deno", "test", "--allow-read", "--allow-env", "--lock=../../.github/deno-w9.lock", "--frozen",
       "_shared/writer_crisis_check.test.ts", "analyse-journal-entry/"]
p = pathlib.Path("_shared/writer_crisis_check.ts")
orig = p.read_text()
muts = {
    "unknown_flag_open": ("  if (victimisation === null) return true;\n", "  if (victimisation === null) victimisation = false;\n"),
    "detector_throw_open": ("    return false;\n  } catch {\n    return true;\n  }\n", "    return false;\n  } catch {\n    return false;\n  }\n"),
    "no_typography_fold": ("    const folded = foldTypography(text);\n", "    const folded = text;\n"),
    "no_pending_list": ("      if (matchesPendingSelfHarm(t)) return true;\n", ""),
    "no_reviewed_corpus": ("      if (detectSelfDisclosure(t, { victimisation }) !== null) return true;\n", ""),
    "victimisation_always": ("detectSelfDisclosure(t, { victimisation })", "detectSelfDisclosure(t, { victimisation: true })"),
}
try:
    for name, (a, b) in muts.items():
        assert orig.count(a) == 1, name
        p.write_text(orig.replace(a, b))
        r = subprocess.run(CMD, capture_output=True, text=True, env={**os.environ, "NO_COLOR": "1"})
        print(name, [l for l in r.stdout.splitlines() if l.startswith(("ok |", "FAILED |"))])
finally:
    p.write_text(orig)
r = subprocess.run(CMD, capture_output=True, text=True, env={**os.environ, "NO_COLOR": "1"})
print("restored", [l for l in r.stdout.splitlines() if l.startswith(("ok |", "FAILED |"))])
```

Run: `(cd supabase/functions && python3 -I ../../$D/mutants_t2.py)`
Expected:
```
unknown_flag_open ['FAILED | 40 passed | 2 failed (...)']
detector_throw_open ['FAILED | 41 passed | 1 failed (...)']
no_typography_fold ['FAILED | 39 passed | 3 failed (...)']
no_pending_list ['FAILED | 36 passed | 6 failed (...)']
no_reviewed_corpus ['FAILED | 28 passed | 14 failed (...)']
victimisation_always ['FAILED | 39 passed | 3 failed (...)']
restored ['ok | 42 passed | 0 failed (...)']
```
(The journal's own tests catch every mutant but `detector_throw_open`, which only the shared test sees: the journal's `disclosed` keeps its own `try`.)

- [ ] **Step 7: Run tests**

```bash
(cd supabase/functions && NO_COLOR=1 deno test --allow-read --allow-env _shared/self_disclosure.test.ts _shared/assistant_input.test.ts 2>&1 | grep -E '^(ok|FAILED) \|')
(cd supabase/functions && NO_COLOR=1 deno lint _shared/writer_crisis_check.ts _shared/self_harm_pending.ts _shared/writer_crisis_check.test.ts analyse-journal-entry/journal_self_harm_pending.ts 2>&1 | grep -E 'Found|Checked')
flutter test --no-pub test/architecture/permanent_constraints_test.dart 2>&1 | tail -1
```

Expected: `ok | 10 passed | 0 failed`; only `Checked 4 files` (no `Found ... problems` line); `All tests passed!`.

### Task 3: The two Healing functions: the gate first (spec §8 W9e, O2; W9 B7 rulings; P-3-P-5, P-12)

**Files:**
- Create: `supabase/functions/_shared/healing_ai_gate.ts`
- Create: `supabase/functions/_shared/test_support/fake_supabase.ts`, `supabase/functions/_shared/test_support/healing_fakes.ts`
- Create: `supabase/functions/_shared/healing_ai_gate.test.ts`, `supabase/functions/generate-healing-portrait/portrait_handler.test.ts`, `supabase/functions/generate-healing-post-mortem/post_mortem_handler.test.ts`
- Create (by `$D/split_healing.py`): `generate-healing-portrait/portrait_handler.ts`, `generate-healing-post-mortem/post_mortem_handler.ts`
- Modify (by the same script): both `index.ts` (now `serve`, the clients, auth, the body parse and the injected deps), `generate-healing-portrait/chapter_scope.test.ts` (reads `portrait_handler.ts`)
- Modify: `.github/workflows/tests.yml` (the `deno-w9` job's name and command)

**Interfaces:**
- Consumes: `writerTextDiscloses` (Task 2), `featureFlagEnabled`, `DRAFT_SAFETY_CONTENT_FLAG`, `callGeminiJson`, the row from Task 1.
- Produces: `HEALING_AI_FLAG`, `PAUSED_BODY`, `SUPPORT_OFFERED_BODY`, `DELETE_ATTEMPTS = 3`, `MAX_ANSWER_DEPTH = 8`, `type HealingStage = "portrait" | "post_mortem"`, `type HealingModel`, `interface HealingDeps { model; aiPaused; victimisationOn }`, `reflectionTextOf(answers: unknown): string | null`, `healingGate(adminClient, userId, journey, stage, deps): Promise<Record<string, string> | null>` in `_shared/healing_ai_gate.ts`; `handlePortrait(userClient, adminClient, user: {id}, journey_id, deps)` and `handlePostMortem(...)` (same shape), each `Promise<Response>`. The app sees two new statuses from either function: `{status:'paused'}` and `{status:'support_offered'}` (Task 4).

- [ ] **Step 1: Write the test support and the failing tests**

Create `supabase/functions/_shared/test_support/fake_supabase.ts` with exactly:

```ts
// TEST-ONLY. A supabase-js-shaped fake for handler tests (Spec 1 W9e):
// every chain is recorded (table, operation, filters, payload) and
// [answer] decides what a finished chain resolves to. It never reaches a
// network or a database.

export type FakeCall = {
  table: string;
  op: "" | "select" | "delete" | "update" | "upsert" | "insert";
  filters: Array<[string, string, unknown]>;
  payload?: unknown;
};

export type FakeAnswer = { data: unknown; error: unknown };

export function fakeClient(answer: (call: FakeCall) => FakeAnswer | Promise<FakeAnswer> = () => ({ data: null, error: null })) {
  const calls: FakeCall[] = [];
  const rpcs: Array<{ fn: string; params: Record<string, unknown> }> = [];
  function chain(call: FakeCall) {
    const done = () => Promise.resolve(answer(call));
    const filter = (kind: string) => (col: string, v?: unknown) => {
      call.filters.push([kind, col, v]);
      return c;
    };
    const c: Record<string, unknown> = {
      select(_cols?: string) {
        if (call.op === "") call.op = "select";
        return c;
      },
      delete() {
        call.op = "delete";
        return c;
      },
      update(payload: unknown) {
        call.op = "update";
        call.payload = payload;
        return c;
      },
      upsert(payload: unknown, _opts?: unknown) {
        call.op = "upsert";
        call.payload = payload;
        return c;
      },
      insert(payload: unknown) {
        call.op = "insert";
        call.payload = payload;
        return c;
      },
      eq: filter("eq"),
      neq: filter("neq"),
      is: filter("is"),
      in: filter("in"),
      order: filter("order"),
      limit: (n: number) => {
        call.filters.push(["limit", "", n]);
        return c;
      },
      single: done,
      maybeSingle: done,
      then(resolve: (v: unknown) => unknown, reject: (e: unknown) => unknown) {
        return done().then(resolve, reject);
      },
    };
    return c;
  }
  return {
    calls,
    rpcs,
    client: {
      from(table: string) {
        const call: FakeCall = { table, op: "", filters: [] };
        calls.push(call);
        return chain(call);
      },
      rpc(fn: string, params: Record<string, unknown>) {
        rpcs.push({ fn, params });
        return Promise.resolve({ data: null, error: null });
      },
    },
  };
}
```

Create `supabase/functions/_shared/test_support/healing_fakes.ts` with exactly:

```ts
// TEST-ONLY (Spec 1 W9e): journeys, reflections and spied dependencies for
// the two Healing handlers' tests.
import type { HealingDeps } from "../healing_ai_gate.ts";
import { fakeClient } from "./fake_supabase.ts";

export const CRISIS = { answer1: "Some nights I want to kill myself", answer2: "", answer3: "" };
export const VICTIM = { answer1: "he hit me last night and I don't know what to do", answer2: "", answer3: "" };
export const ORDINARY = {
  answer1: "I go quiet instead of saying what I actually need.",
  answer2: "I mistook intensity for closeness.",
  answer3: "Speaking up earlier instead of waiting until I am resentful.",
};

export function journey(over: Record<string, unknown> = {}) {
  return {
    id: "j1",
    user_id: "u1",
    relationship_id: null,
    reflection_answers: ORDINARY,
    post_mortem_status: "not_started",
    post_mortem_observation: null,
    post_mortem_confidence: null,
    post_mortem_reflection_prompt: null,
    portrait_status: "not_started",
    portrait_text: null,
    portrait_prompt: null,
    portrait_reflection: null,
    ...over,
  };
}

/// The caller's own client (RLS): it answers the journey, a profile, and
/// nothing else.
export function userWith(row: unknown, error: unknown = null) {
  return fakeClient((call) => {
    if (call.table === "healing_journeys") return { data: error ? null : row, error };
    if (call.table === "psych_profiles") {
      return { data: { attachment_style: { primary: "secure" } }, error: null };
    }
    return { data: [], error: null };
  });
}

export function spyDeps(opts: {
  paused?: boolean;
  pausedThrows?: boolean;
  victimisation?: boolean;
  victimisationThrows?: boolean;
  reply?: Record<string, unknown> | null;
} = {}) {
  const prompts: string[] = [];
  const deps: HealingDeps = {
    model: (params) => {
      prompts.push(params.userPrompt);
      return Promise.resolve(
        opts.reply === undefined
          ? { portrait: "You notice how you show up.", observation: "A pattern may have surfaced.", reflection_prompt: "What feels familiar?" }
          : opts.reply,
      );
    },
    aiPaused: () => opts.pausedThrows ? Promise.reject(new Error("flag read failed")) : Promise.resolve(opts.paused ?? false),
    victimisationOn: () =>
      opts.victimisationThrows ? Promise.reject(new Error("flag read failed")) : Promise.resolve(opts.victimisation ?? false),
  };
  return { deps, prompts };
}

/// A value whose text cannot be read: reading it throws.
export const THROWS = { toString(): string { throw new Error("unreadable"); } } as unknown as string;

/// reflection_answers nested [depth] levels deep, with ordinary words.
export function nested(depth: number): Record<string, unknown> {
  let value: unknown = "ordinary words";
  for (let i = 0; i < depth; i++) value = { inner: value };
  return value as Record<string, unknown>;
}
```

Create `supabase/functions/_shared/healing_ai_gate.test.ts` with exactly:

```ts
// Spec 1 W9e: the Healing gate. The crisis check runs first; any doubt is
// a match (support, never the provider) or, for the AI flag, paused.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { DELETE_ATTEMPTS, HEALING_AI_FLAG, healingGate, MAX_ANSWER_DEPTH, reflectionTextOf } from "./healing_ai_gate.ts";
import { fakeClient } from "./test_support/fake_supabase.ts";
import { CRISIS, journey, nested, ORDINARY, spyDeps, THROWS } from "./test_support/healing_fakes.ts";

Deno.test("the flag is healing_ai_insights", () => {
  assertEquals(HEALING_AI_FLAG, "healing_ai_insights");
});

Deno.test("reflectionTextOf reads every string, and nothing it cannot read", () => {
  assertEquals(reflectionTextOf(null), "");
  assertEquals(reflectionTextOf(undefined), "");
  assertEquals(reflectionTextOf({}), "");
  assertEquals(reflectionTextOf({ a: "one", b: 2, c: null, d: { e: ["two", true] } }), "one\ntwo");
  assertEquals(reflectionTextOf(nested(MAX_ANSWER_DEPTH)), "ordinary words");
  assertEquals(reflectionTextOf(nested(MAX_ANSWER_DEPTH + 1)), null);
  assertEquals(reflectionTextOf(["a list"]), null);
  assertEquals(reflectionTextOf("a string"), null);
  assertEquals(reflectionTextOf(7), null);
  assertEquals(reflectionTextOf({ a: THROWS }), null);
});

Deno.test("a crisis anywhere in the answers, even nested, is a match", async () => {
  for (const answers of [CRISIS, { a: { b: [CRISIS.answer1] } }]) {
    const admin = fakeClient();
    const body = await healingGate(admin.client, "u1", journey({ reflection_answers: answers }), "portrait", spyDeps().deps);
    assertEquals(body, { status: "support_offered" });
  }
});

Deno.test("Review Focus 3: crisis words split across two answers are a match (fail safe)", async () => {
  const split = { answer1: "Some nights I want to", answer2: "kill myself", answer3: "" };
  const body = await healingGate(fakeClient().client, "u1", journey({ reflection_answers: split }), "portrait", spyDeps().deps);
  assertEquals(body, { status: "support_offered" });
});

Deno.test("fail safe: unreadable answers, or a private_safety_check read that throws, offer support", async () => {
  for (const answers of [["a list"], "a string", nested(MAX_ANSWER_DEPTH + 1)]) {
    const body = await healingGate(fakeClient().client, "u1", journey({ reflection_answers: answers }), "portrait", spyDeps().deps);
    assertEquals(body, { status: "support_offered" }, JSON.stringify(answers));
  }
  const body = await healingGate(fakeClient().client, "u1", journey(), "portrait", spyDeps({ victimisationThrows: true }).deps);
  assertEquals(body, { status: "support_offered" });
});

Deno.test("fail safe: a healing_ai_insights read that throws is paused", async () => {
  const admin = fakeClient();
  const body = await healingGate(admin.client, "u1", journey(), "portrait", spyDeps({ pausedThrows: true }).deps);
  assertEquals(body, { status: "paused" });
  assertEquals(admin.calls.length, 0);
});

Deno.test("no match and not paused: go on (null), with nothing read or written", async () => {
  const admin = fakeClient();
  assertEquals(await healingGate(admin.client, "u1", journey({ reflection_answers: ORDINARY }), "portrait", spyDeps().deps), null);
  assertEquals(admin.calls.length, 0);
});

Deno.test("the stale-output delete answers {error}: retried, bounded, and support is still offered", async () => {
  const always = fakeClient((call) => (call.op === "delete" ? { data: null, error: { message: "down" } } : { data: null, error: null }));
  const body = await healingGate(always.client, "u1", journey({ reflection_answers: CRISIS }), "post_mortem", spyDeps().deps);
  assertEquals(body, { status: "support_offered" });
  assertEquals(always.calls.filter((c) => c.op === "delete").length, DELETE_ATTEMPTS);

  let failures = 1;
  const once = fakeClient((call) =>
    call.op === "delete" && failures-- > 0 ? { data: null, error: { message: "down" } } : { data: null, error: null }
  );
  await healingGate(once.client, "u1", journey({ reflection_answers: CRISIS }), "post_mortem", spyDeps().deps);
  assertEquals(once.calls.filter((c) => c.op === "delete").length, 2);

  const throwing = fakeClient((call) => {
    if (call.op === "delete") throw new Error("network");
    return { data: null, error: null };
  });
  assertEquals(
    await healingGate(throwing.client, "u1", journey({ reflection_answers: CRISIS }), "post_mortem", spyDeps().deps),
    { status: "support_offered" },
  );
});
```

Create `supabase/functions/generate-healing-portrait/portrait_handler.test.ts` with exactly:

```ts
// Spec 1 W9e (owner approval O2; spec 8 W9e): the portrait's crisis check
// runs first, W9c's pattern. With a spy on the provider: a crisis
// reflection never reaches it, or the cache, or the saved portrait,
// whatever either flag says; nothing about the match is stored and the
// stage's earlier AI output is removed; with no match, healing_ai_insights
// off answers paused before anything is read; otherwise as before.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handlePortrait } from "./portrait_handler.ts";
import { fakeClient } from "../_shared/test_support/fake_supabase.ts";
import { CRISIS, journey, ORDINARY, spyDeps, userWith, VICTIM } from "../_shared/test_support/healing_fakes.ts";

const U = { id: "u1" };

Deno.test("a crisis reflection never reaches the provider or the cache, and stores nothing", async () => {
  for (const paused of [false, true]) {
    for (const victimisation of [false, true]) {
      const user = userWith(journey({ reflection_answers: CRISIS }));
      const admin = fakeClient();
      const spy = spyDeps({ paused, victimisation });
      const res = await handlePortrait(user.client, admin.client, U, "j1", spy.deps);
      assertEquals(await res.json(), { status: "support_offered" });
      assertEquals(spy.prompts.length, 0, "the provider was called");
      // First: nothing but the caller's journey was read.
      assertEquals(user.calls.map((c) => c.table), ["healing_journeys"]);
      // Only the stage's cached jobs are removed (no saved text to clear).
      assertEquals(admin.calls.map((c) => [c.table, c.op]), [["healing_generation_jobs", "delete"]]);
      assertEquals(admin.calls[0].filters, [["eq", "journey_id", "j1"], ["eq", "user_id", "u1"], ["eq", "stage", "portrait"]]);
      assertEquals(admin.rpcs.length, 0);
    }
  }
});

Deno.test("the check runs before the saved portrait: it is cleared, never returned", async () => {
  const saved = journey({
    reflection_answers: CRISIS,
    portrait_status: "completed",
    portrait_text: "An older portrait.",
    portrait_prompt: "An older prompt.",
    portrait_reflection: "My own words.",
  });
  const admin = fakeClient();
  const spy = spyDeps();
  const res = await handlePortrait(userWith(saved).client, admin.client, U, "j1", spy.deps);
  const text = await res.text();
  assertEquals(JSON.parse(text), { status: "support_offered" });
  assert(!text.includes("older"));
  assertEquals(admin.calls.map((c) => [c.table, c.op]), [["healing_generation_jobs", "delete"], ["healing_journeys", "update"]]);
  // The AI text only: the person's own words, the status and the time stay.
  assertEquals(admin.calls[1].payload, { portrait_text: null, portrait_prompt: null });
  assertEquals(admin.calls[1].filters, [["eq", "id", "j1"], ["eq", "user_id", "u1"]]);
  assertEquals(spy.prompts.length, 0);
});

Deno.test("no match while paused: paused, before the saved portrait, the cache or the provider", async () => {
  for (const opts of [{ paused: true }, { pausedThrows: true }]) {
    const user = userWith(journey({ portrait_status: "completed", portrait_text: "Saved.", portrait_prompt: "P" }));
    const admin = fakeClient();
    const spy = spyDeps(opts);
    const res = await handlePortrait(user.client, admin.client, U, "j1", spy.deps);
    assertEquals(await res.json(), { status: "paused" });
    assertEquals(admin.calls.length, 0, "the cache was read or written");
    assertEquals(user.calls.map((c) => c.table), ["healing_journeys"]);
    assertEquals(spy.prompts.length, 0);
  }
});

Deno.test("an ordinary reflection, not paused: the caller's own cache, then the provider, as before", async () => {
  const admin = fakeClient();
  const spy = spyDeps();
  const res = await handlePortrait(userWith(journey({ reflection_answers: ORDINARY })).client, admin.client, U, "j1", spy.deps);
  assertEquals((await res.json()).status, "completed");
  assertEquals(admin.calls.map((c) => [c.table, c.op]), [["healing_generation_jobs", "select"], ["healing_generation_jobs", "upsert"]]);
  assertEquals(admin.calls[0].filters.slice(0, 3), [["eq", "user_id", "u1"], ["eq", "journey_id", "j1"], ["eq", "stage", "portrait"]]);
  assertEquals(spy.prompts.length, 1);
  assert(spy.prompts[0].includes("I mistook intensity for closeness."));
});

Deno.test("the [DRAFT] victimisation list runs only with private_safety_check on", async () => {
  const on = spyDeps({ victimisation: true });
  const resOn = await handlePortrait(userWith(journey({ reflection_answers: VICTIM })).client, fakeClient().client, U, "j1", on.deps);
  assertEquals((await resOn.json()).status, "support_offered");
  assertEquals(on.prompts.length, 0);

  const off = spyDeps({ victimisation: false });
  const resOff = await handlePortrait(userWith(journey({ reflection_answers: VICTIM })).client, fakeClient().client, U, "j1", off.deps);
  assertEquals((await resOff.json()).status, "completed");
  assertEquals(off.prompts.length, 1);
});

Deno.test("Review Focus 4: a phone keyboard's typographic apostrophe still matches", async () => {
  const spy = spyDeps();
  const answers = { answer1: "I don\u2019t want to be here anymore", answer2: "", answer3: "" };
  const res = await handlePortrait(userWith(journey({ reflection_answers: answers })).client, fakeClient().client, U, "j1", spy.deps);
  assertEquals(await res.json(), { status: "support_offered" });
  assertEquals(spy.prompts.length, 0);
});

Deno.test("fail safe: an unreadable reflection or a flag read that throws never reaches the provider", async () => {
  for (const [row, opts] of [
    [journey({ reflection_answers: ["a list"] }), {}],
    [journey(), { victimisationThrows: true }],
  ] as const) {
    const spy = spyDeps(opts);
    const res = await handlePortrait(userWith(row).client, fakeClient().client, U, "j1", spy.deps);
    assertEquals(await res.json(), { status: "support_offered" });
    assertEquals(spy.prompts.length, 0);
  }
});

Deno.test("a journey the caller cannot read answers 404, with nothing else read", async () => {
  const admin = fakeClient();
  const spy = spyDeps();
  const res = await handlePortrait(userWith(null, { message: "no rows" }).client, admin.client, U, "j1", spy.deps);
  assertEquals(res.status, 404);
  assertEquals(admin.calls.length, 0);
  assertEquals(spy.prompts.length, 0);
});

Deno.test("index.ts wires the live provider, the pause flag and the draft-list flag", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assert(src.includes("model: callGeminiJson,"));
  assert(src.includes("aiPaused: async () => !(await featureFlagEnabled(adminClient, HEALING_AI_FLAG)),"));
  assert(src.includes("victimisationOn: () => featureFlagEnabled(adminClient, DRAFT_SAFETY_CONTENT_FLAG),"));
  assert(src.includes("return await handlePortrait(userClient, adminClient, user, journey_id, deps);"));
  assert(!src.includes("generate("), "no provider call left in index.ts");
});
```

Create `supabase/functions/generate-healing-post-mortem/post_mortem_handler.test.ts` with exactly:

```ts
// Spec 1 W9e (owner approval O2; spec 8 W9e): the post-mortem's crisis check
// runs first, W9c's pattern. With a spy on the provider: a crisis
// reflection never reaches it, or the cache, or the saved reflection,
// whatever either flag says; nothing about the match is stored and the
// stage's earlier AI output is removed; with no match, healing_ai_insights
// off answers paused before anything is read; otherwise as before.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handlePostMortem } from "./post_mortem_handler.ts";
import { fakeClient } from "../_shared/test_support/fake_supabase.ts";
import { CRISIS, journey, ORDINARY, spyDeps, userWith, VICTIM } from "../_shared/test_support/healing_fakes.ts";

const U = { id: "u1" };

Deno.test("a crisis reflection never reaches the provider or the cache, and stores nothing", async () => {
  for (const paused of [false, true]) {
    for (const victimisation of [false, true]) {
      const user = userWith(journey({ reflection_answers: CRISIS }));
      const admin = fakeClient();
      const spy = spyDeps({ paused, victimisation });
      const res = await handlePostMortem(user.client, admin.client, U, "j1", spy.deps);
      assertEquals(await res.json(), { status: "support_offered" });
      assertEquals(spy.prompts.length, 0, "the provider was called");
      // First: nothing but the caller's journey was read.
      assertEquals(user.calls.map((c) => c.table), ["healing_journeys"]);
      // Only the stage's cached jobs are removed (no saved text to clear).
      assertEquals(admin.calls.map((c) => [c.table, c.op]), [["healing_generation_jobs", "delete"]]);
      assertEquals(admin.calls[0].filters, [["eq", "journey_id", "j1"], ["eq", "user_id", "u1"], ["eq", "stage", "post_mortem"]]);
      assertEquals(admin.rpcs.length, 0);
    }
  }
});

Deno.test("the check runs before the saved reflection: it is cleared, never returned", async () => {
  const saved = journey({
    reflection_answers: CRISIS,
    post_mortem_status: "completed",
    post_mortem_observation: "An older observation.",
    post_mortem_confidence: "low",
    post_mortem_reflection_prompt: "An older prompt.",
  });
  const admin = fakeClient();
  const spy = spyDeps();
  const res = await handlePostMortem(userWith(saved).client, admin.client, U, "j1", spy.deps);
  const text = await res.text();
  assertEquals(JSON.parse(text), { status: "support_offered" });
  assert(!text.includes("older"));
  assertEquals(admin.calls.map((c) => [c.table, c.op]), [["healing_generation_jobs", "delete"], ["healing_journeys", "update"]]);
  // The AI text only: the status and the time stay.
  assertEquals(admin.calls[1].payload, {
    post_mortem_observation: null,
    post_mortem_confidence: null,
    post_mortem_reflection_prompt: null,
  });
  assertEquals(admin.calls[1].filters, [["eq", "id", "j1"], ["eq", "user_id", "u1"]]);
  assertEquals(spy.prompts.length, 0);
});

Deno.test("no match while paused: paused, before the saved reflection, the cache or the provider", async () => {
  for (const opts of [{ paused: true }, { pausedThrows: true }]) {
    const user = userWith(journey({ post_mortem_status: "completed", post_mortem_observation: "Saved.", post_mortem_confidence: "low" }));
    const admin = fakeClient();
    const spy = spyDeps(opts);
    const res = await handlePostMortem(user.client, admin.client, U, "j1", spy.deps);
    assertEquals(await res.json(), { status: "paused" });
    assertEquals(admin.calls.length, 0, "the cache was read or written");
    assertEquals(user.calls.map((c) => c.table), ["healing_journeys"]);
    assertEquals(spy.prompts.length, 0);
  }
});

Deno.test("an ordinary reflection, not paused: the caller's own cache, then the provider, as before", async () => {
  const admin = fakeClient();
  const spy = spyDeps();
  const res = await handlePostMortem(userWith(journey({ reflection_answers: ORDINARY })).client, admin.client, U, "j1", spy.deps);
  assertEquals((await res.json()).status, "completed");
  assertEquals(admin.calls.map((c) => [c.table, c.op]), [["healing_generation_jobs", "select"], ["healing_generation_jobs", "upsert"]]);
  assertEquals(admin.calls[0].filters.slice(0, 3), [["eq", "user_id", "u1"], ["eq", "journey_id", "j1"], ["eq", "stage", "post_mortem"]]);
  assertEquals(spy.prompts.length, 1);
  assert(spy.prompts[0].includes("I mistook intensity for closeness."));
});

Deno.test("the [DRAFT] victimisation list runs only with private_safety_check on", async () => {
  const on = spyDeps({ victimisation: true });
  const resOn = await handlePostMortem(userWith(journey({ reflection_answers: VICTIM })).client, fakeClient().client, U, "j1", on.deps);
  assertEquals((await resOn.json()).status, "support_offered");
  assertEquals(on.prompts.length, 0);

  const off = spyDeps({ victimisation: false });
  const resOff = await handlePostMortem(userWith(journey({ reflection_answers: VICTIM })).client, fakeClient().client, U, "j1", off.deps);
  assertEquals((await resOff.json()).status, "completed");
  assertEquals(off.prompts.length, 1);
});

Deno.test("Review Focus 4: a phone keyboard's typographic apostrophe still matches", async () => {
  const spy = spyDeps();
  const answers = { answer1: "I don\u2019t want to be here anymore", answer2: "", answer3: "" };
  const res = await handlePostMortem(userWith(journey({ reflection_answers: answers })).client, fakeClient().client, U, "j1", spy.deps);
  assertEquals(await res.json(), { status: "support_offered" });
  assertEquals(spy.prompts.length, 0);
});

Deno.test("fail safe: an unreadable reflection or a flag read that throws never reaches the provider", async () => {
  for (const [row, opts] of [
    [journey({ reflection_answers: ["a list"] }), {}],
    [journey(), { victimisationThrows: true }],
  ] as const) {
    const spy = spyDeps(opts);
    const res = await handlePostMortem(userWith(row).client, fakeClient().client, U, "j1", spy.deps);
    assertEquals(await res.json(), { status: "support_offered" });
    assertEquals(spy.prompts.length, 0);
  }
});

Deno.test("a journey the caller cannot read answers 404, with nothing else read", async () => {
  const admin = fakeClient();
  const spy = spyDeps();
  const res = await handlePostMortem(userWith(null, { message: "no rows" }).client, admin.client, U, "j1", spy.deps);
  assertEquals(res.status, 404);
  assertEquals(admin.calls.length, 0);
  assertEquals(spy.prompts.length, 0);
});

Deno.test("index.ts wires the live provider, the pause flag and the draft-list flag", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assert(src.includes("model: callGeminiJson,"));
  assert(src.includes("aiPaused: async () => !(await featureFlagEnabled(adminClient, HEALING_AI_FLAG)),"));
  assert(src.includes("victimisationOn: () => featureFlagEnabled(adminClient, DRAFT_SAFETY_CONTENT_FLAG),"));
  assert(src.includes("return await handlePostMortem(userClient, adminClient, user, journey_id, deps);"));
  assert(!src.includes("generate("), "no provider call left in index.ts");
});
```

Then:

```bash
python3 -I $D/ascii_escapes.py supabase/functions/generate-healing-portrait/portrait_handler.test.ts supabase/functions/generate-healing-post-mortem/post_mortem_handler.test.ts
grep -cP '[^\x00-\x7F]' supabase/functions/_shared/test_support/*.ts supabase/functions/_shared/healing_ai_gate.test.ts supabase/functions/generate-healing-*/*_handler.test.ts
```

Expected: every count `0`.

- [ ] **Step 2: Run them to make sure they fail**

Run: `(cd supabase/functions && NO_COLOR=1 deno test --allow-read --allow-env _shared/healing_ai_gate.test.ts generate-healing-portrait/ generate-healing-post-mortem/ 2>&1 | grep -E 'TS2307' | head -3)`
Expected: `TS2307 [ERROR]: Cannot find module '.../_shared/healing_ai_gate.ts'.` (and the same for `portrait_handler.ts` / `post_mortem_handler.ts`).

- [ ] **Step 3: Write the gate**

Create `supabase/functions/_shared/healing_ai_gate.ts` with exactly:

```ts
// supabase/functions/_shared/healing_ai_gate.ts
//
// Spec 1 W9e (owner approval O2; spec 8 W9e): Healing's AI pause, with the
// writer-facing crisis check first, W9c's pattern. generate-healing-portrait
// and generate-healing-post-mortem send a person's breakup reflections to a
// provider; before anything else, after loading the caller's own journey:
//   1. the crisis check (writerTextDiscloses) on every string in the
//      journey's reflection_answers. A match, an unreadable reflection, a
//      private_safety_check read that throws or a detector that throws
//      answers {status: 'support_offered'}: no provider call, no cache
//      read, nothing about the match stored, and the stage's earlier AI
//      output removed (the cached jobs and, when the journey holds it, the
//      saved text), so none is shown beside these words;
//   2. only then the pause: healing_ai_insights off, unreadable or missing
//      answers {status: 'paused'} before any cache read or provider call.
// Support never waits for the AI flag (W9 batch-7 ruling R-2). Nothing here
// depends on a model.
import { writerTextDiscloses } from "./writer_crisis_check.ts";

export const HEALING_AI_FLAG = "healing_ai_insights";

export const PAUSED_BODY = { status: "paused" } as const;

/// The whole answer to a match (W9c's body). The app hides any AI output it
/// holds for the journey and stage it asked about, and shows the card.
export const SUPPORT_OFFERED_BODY = { status: "support_offered" } as const;

/// The stale-output delete: supabase-js answers {error} rather than
/// throwing, so the answer is checked and the delete tried at most this
/// many times; support is offered either way (W9 batch-7 review I-1).
export const DELETE_ATTEMPTS = 3;

/// Deepest nesting read in reflection_answers; anything deeper is
/// unreadable, and unreadable is treated as a match.
export const MAX_ANSWER_DEPTH = 8;

export type HealingStage = "portrait" | "post_mortem";

export type HealingModel = (params: {
  promptId: string;
  systemPrompt: string;
  userPrompt: string;
  maxOutputTokens: number;
  attribution: { fn: string; userId: string };
}) => Promise<Record<string, unknown> | null>;

export interface HealingDeps {
  /// callGeminiJson in production.
  model: HealingModel;
  /// healing_ai_insights off (any doubt is paused).
  aiPaused: () => Promise<boolean>;
  /// private_safety_check, read the way ai-assist reads it (off on doubt).
  victimisationOn: () => Promise<boolean>;
}

/// The journey's saved AI text for each stage: cleared on a match. The
/// person's own words (portrait_reflection), the status and the completed
/// time are kept, so the journey's progress is unchanged.
const SAVED_OUTPUT: Record<HealingStage, string[]> = {
  portrait: ["portrait_text", "portrait_prompt"],
  post_mortem: ["post_mortem_observation", "post_mortem_confidence", "post_mortem_reflection_prompt"],
};

/// Every string in reflection_answers, joined; "" for none; null when it
/// cannot be read (not an object, or nested past MAX_ANSWER_DEPTH).
export function reflectionTextOf(answers: unknown): string | null {
  if (answers === null || answers === undefined) return "";
  if (typeof answers !== "object" || Array.isArray(answers)) return null;
  const parts: string[] = [];
  const walk = (value: unknown, depth: number): boolean => {
    if (typeof value === "string") {
      parts.push(value);
      return true;
    }
    if (value === null || typeof value === "number" || typeof value === "boolean") return true;
    if (typeof value !== "object" || depth >= MAX_ANSWER_DEPTH) return false;
    const items = Array.isArray(value) ? value : Object.values(value as Record<string, unknown>);
    return items.every((item) => walk(item, depth + 1));
  };
  return walk(answers, 0) ? parts.join("\n") : null;
}

/// private_safety_check, or null when the read threw (unknown: a match).
async function readVictimisation(deps: HealingDeps): Promise<boolean | null> {
  try {
    return (await deps.victimisationOn()) === true;
  } catch {
    return null;
  }
}

/// healing_ai_insights off, or unreadable.
async function aiPaused(deps: HealingDeps): Promise<boolean> {
  try {
    return (await deps.aiPaused()) !== false;
  } catch {
    return true;
  }
}

// deno-lint-ignore no-explicit-any
async function removeStaleOutput(adminClient: any, userId: string, journey: any, stage: HealingStage) {
  const columns = SAVED_OUTPUT[stage];
  const saved = columns.some((c) => journey?.[c] !== null && journey?.[c] !== undefined);
  for (let attempt = 0; attempt < DELETE_ATTEMPTS; attempt++) {
    try {
      // Every cached job for the stage, whatever text it was written for.
      const jobs = await adminClient
        .from("healing_generation_jobs")
        .delete()
        .eq("journey_id", journey.id)
        .eq("user_id", userId)
        .eq("stage", stage);
      if (jobs.error) continue;
      if (saved) {
        const row = await adminClient
          .from("healing_journeys")
          .update(Object.fromEntries(columns.map((c) => [c, null])))
          .eq("id", journey.id)
          .eq("user_id", userId);
        if (row.error) continue;
      }
      return;
    } catch {
      // Tried again, then support anyway.
    }
  }
}

/// The W9e gate: the body to answer at once (support_offered or paused),
/// or null to go on as before. [journey] is the caller's own row, read
/// through the caller's client (RLS).
export async function healingGate(
  // deno-lint-ignore no-explicit-any
  adminClient: any,
  userId: string,
  // deno-lint-ignore no-explicit-any
  journey: any,
  stage: HealingStage,
  deps: HealingDeps,
): Promise<Record<string, string> | null> {
  const victimisation = await readVictimisation(deps);
  const text = reflectionTextOf(journey?.reflection_answers);
  if (text === null || writerTextDiscloses(text, victimisation)) {
    await removeStaleOutput(adminClient, userId, journey, stage);
    return { ...SUPPORT_OFFERED_BODY };
  }
  if (await aiPaused(deps)) {
    return { ...PAUSED_BODY };
  }
  return null;
}
```

- [ ] **Step 4: Move each action into its handler, the gate first**

Create `$D/split_healing.py` with exactly:

```python
# Spec 1 W9e, Task 3: builds <fn>/<handler>.ts and the new <fn>/index.ts
# from today's index.ts. Everything is moved verbatim except the lines
# marked "Spec 1 W9e". Also points chapter_scope.test.ts at the moved
# evidence. Run from the repo root: python3 -I <this> supabase/functions
import pathlib, sys

root = pathlib.Path(sys.argv[1])  # supabase/functions
SPECS = {
    "generate-healing-portrait": dict(
        handler="portrait_handler.ts", fn="handlePortrait", stage="portrait",
        about="the portrait", cache_stage='.eq("stage", "portrait")',
    ),
    "generate-healing-post-mortem": dict(
        handler="post_mortem_handler.ts", fn="handlePostMortem", stage="post_mortem",
        about="the post-mortem reflection", cache_stage='.eq("stage", "post_mortem")',
    ),
}

def once(text, old, new):
    assert text.count(old) == 1, (old, text.count(old))
    return text.replace(old, new)

for folder, s in SPECS.items():
    assert not (root / folder / s["handler"]).exists(), f"{folder}/{s['handler']} exists already: stop and report"
    src = (root / folder / "index.ts").read_text()
    head, rest = src.split("serve(async (req) => {\n", 1)
    body, helpers = rest.split("\n});\n", 1)
    # The action: from the body parse's journey_id check to the completed answer.
    start = body.index('    if (!journey_id) {\n')
    end = body.index('  } catch (error) {\n')
    action = body[start:end]
    # Unindent the action by two spaces (it leaves the serve try block).
    action = "\n".join(l[2:] if l.startswith("  ") else l for l in action.split("\n"))
    action = once(action,
        '  const journey = journeyRes.data;\n',
        '  const journey = journeyRes.data;\n'
        '  // Spec 1 W9e: the crisis check, then the healing_ai_insights pause,\n'
        '  // before the saved answer, the cache and any provider call.\n'
        f'  const gate = await healingGate(adminClient, user.id, journey, "{s["stage"]}", deps);\n'
        '  if (gate) {\n'
        '    return json(gate);\n'
        '  }\n')
    action = once(action,
        '  if (journeyRes.error) {\n',
        '  // Spec 1 W9e: a journey that is not there never reaches the gate.\n  if (journeyRes.error || !journeyRes.data) {\n')
    action = once(action,
        '    .from("healing_generation_jobs")\n    .select("*")\n',
        '    .from("healing_generation_jobs")\n    .select("*")\n'
        '    .eq("user_id", user.id) // Spec 1 W9e: the caller\'s own rows only\n')
    action = once(action,
        'await maybeGenerateWithGemini(evidence, buildPrompt(evidence), user.id)',
        'await maybeGenerateWithGemini(deps.model, evidence, buildPrompt(evidence), user.id)')
    action = once(action,
        '  let output = await maybeGenerateWithGemini(deps.model',
        '  // Spec 1 W9e: the provider is injected (HealingDeps.model).\n  let output = await maybeGenerateWithGemini(deps.model')
    helpers = once(helpers,
        'async function maybeGenerateWithGemini(evidence: any, prompt: string, userId: string) {',
        'async function maybeGenerateWithGemini(model: HealingModel, evidence: any, prompt: string, userId: string) {')
    helpers = once(helpers, '  const parsed = await callGeminiJson({', '  // Spec 1 W9e: callGeminiJson, injected (HealingDeps.model).\n  const parsed = await model({')
    helpers = once(helpers, '\nfunction json(body: unknown, status = 200) {', '\nexport function json(body: unknown, status = 200) {')
    # Constants: everything in head after the imports.
    lines = head.split("\n")
    imports = [l for l in lines if l.startswith("import ")]
    others = "\n".join(l for l in lines if not l.startswith("import "))
    others = once(others, "const corsHeaders = {", "export const corsHeaders = {")
    keep_imports = [l for l in imports if "deno.land/std@0.177.0/http" not in l and "supabase-js" not in l and "callGeminiJson" not in l]
    handler = (
        f"// supabase/functions/{folder}/{s['handler']}\n"
        "//\n"
        f"// {s['about'][0].upper() + s['about'][1:]}, moved out of index.ts unchanged except for Spec 1\n"
        "// W9e (owner approval O2; spec 8 W9e), on the lines marked so: after the\n"
        "// caller's own journey is read, healingGate runs first (the crisis check,\n"
        "// then the healing_ai_insights pause; _shared/healing_ai_gate.ts), before\n"
        "// the saved answer, the cache and any provider call; the cache read is\n"
        "// limited to the caller's own rows; the provider is injected\n"
        f"// (HealingDeps.model) so {s['handler'].replace('.ts', '.test.ts')} can spy on it.\n"
        'import { type HealingDeps, healingGate, type HealingModel } from "../_shared/healing_ai_gate.ts";\n'
        + "".join(l + "\n" for l in keep_imports)
        + "\n" + others.lstrip("\n")
        + f"export async function {s['fn']}(\n"
        "  // deno-lint-ignore no-explicit-any\n"
        "  userClient: any,\n"
        "  // deno-lint-ignore no-explicit-any\n"
        "  adminClient: any,\n"
        "  user: { id: string },\n"
        "  journey_id: string,\n"
        "  deps: HealingDeps,\n"
        "): Promise<Response> {\n"
        + action.rstrip("\n") + "\n}\n"
        + helpers
    )
    new_index = (
        'import { serve } from "https://deno.land/std@0.177.0/http/server.ts";\n'
        'import { createClient } from "https://esm.sh/@supabase/supabase-js@2";\n'
        'import { callGeminiJson } from "../_shared/gemini_json.ts";\n'
        'import { DRAFT_SAFETY_CONTENT_FLAG, featureFlagEnabled } from "../_shared/feature_flag.ts";\n'
        'import { HEALING_AI_FLAG, type HealingDeps } from "../_shared/healing_ai_gate.ts";\n'
        f'import {{ corsHeaders, {s["fn"]}, json }} from "./{s["handler"]}";\n'
        "\n"
        "serve(async (req) => {\n"
        + body[:start]
        + "    // Spec 1 W9e: the provider, the healing_ai_insights pause and the\n"
          "    // draft-list flag, injected so the handler's tests can spy on them.\n"
          "    // featureFlagEnabled answers off on any error: off is paused, and\n"
          "    // the [DRAFT] victimisation list stays off (review A-4).\n"
          "    const deps: HealingDeps = {\n"
          "      model: callGeminiJson,\n"
          "      aiPaused: async () => !(await featureFlagEnabled(adminClient, HEALING_AI_FLAG)),\n"
          "      victimisationOn: () => featureFlagEnabled(adminClient, DRAFT_SAFETY_CONTENT_FLAG),\n"
          "    };\n"
          f"    return await {s['fn']}(userClient, adminClient, user, journey_id, deps);\n"
        + body[end:]
        + "\n});\n"
    )
    (root / folder / s["handler"]).write_text(handler)
    (root / folder / "index.ts").write_text(new_index)
    print(folder, "ok")

chapter = root / "generate-healing-portrait" / "chapter_scope.test.ts"
ct = chapter.read_text()
old = 'const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));\n'
assert ct.count(old) == 1
chapter.write_text(ct.replace(old,
    "// Spec 1 W9e: the evidence moved, unchanged, into portrait_handler.ts.\n"
    'const src = await Deno.readTextFile(new URL("./portrait_handler.ts", import.meta.url));\n'))
print("chapter_scope.test.ts ok")
```

Run: `python3 -I $D/split_healing.py supabase/functions`
Expected: `generate-healing-portrait ok`, `generate-healing-post-mortem ok`, `chapter_scope.test.ts ok`. The new `generate-healing-portrait/index.ts` reads exactly as below (the post-mortem's is the same with `handlePostMortem` and `./post_mortem_handler.ts`):

```ts
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callGeminiJson } from "../_shared/gemini_json.ts";
import { DRAFT_SAFETY_CONTENT_FLAG, featureFlagEnabled } from "../_shared/feature_flag.ts";
import { HEALING_AI_FLAG, type HealingDeps } from "../_shared/healing_ai_gate.ts";
import { corsHeaders, handlePortrait, json } from "./portrait_handler.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "missing_authorization" }, 401);
    }

    const userClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const adminClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();
    if (userError || !user) {
      return json({ error: "authentication_required" }, 401);
    }

    const { journey_id } = await req.json();
    // Spec 1 W9e: the provider, the healing_ai_insights pause and the
    // draft-list flag, injected so the handler's tests can spy on them.
    // featureFlagEnabled answers off on any error: off is paused, and
    // the [DRAFT] victimisation list stays off (review A-4).
    const deps: HealingDeps = {
      model: callGeminiJson,
      aiPaused: async () => !(await featureFlagEnabled(adminClient, HEALING_AI_FLAG)),
      victimisationOn: () => featureFlagEnabled(adminClient, DRAFT_SAFETY_CONTENT_FLAG),
    };
    return await handlePortrait(userClient, adminClient, user, journey_id, deps);
  } catch (error) {
    return json(
      { error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});
```

- [ ] **Step 5: Run the tests and type-check**

```bash
(cd supabase/functions && NO_COLOR=1 deno test --allow-read --allow-env --lock=../../.github/deno-w9.lock --frozen _shared/unicode_normaliser.test.ts _shared/writer_crisis_check.test.ts _shared/healing_ai_gate.test.ts analyse-journal-entry/ generate-healing-portrait/ generate-healing-post-mortem/ 2>&1 | grep -E '^(ok|FAILED) \|')
(cd supabase/functions && NO_COLOR=1 deno check generate-healing-portrait/index.ts generate-healing-post-mortem/index.ts 2>&1 | tail -2)
(cd supabase/functions && NO_COLOR=1 deno lint _shared/healing_ai_gate.ts _shared/healing_ai_gate.test.ts _shared/test_support/fake_supabase.ts _shared/test_support/healing_fakes.ts generate-healing-portrait/portrait_handler.test.ts generate-healing-post-mortem/post_mortem_handler.test.ts 2>&1 | grep -E 'Found|Checked')
```

Expected: `ok | 80 passed | 0 failed` (49 from Task 2, the 5 existing Healing tests, 26 new); `Check generate-healing-portrait/index.ts`, `Check generate-healing-post-mortem/index.ts`; only `Checked 6 files` (no `Found ... problems` line).

- [ ] **Step 6: Nothing of the old behaviour moved by accident**

Create `$D/verbatim_check.py` with exactly:

```python
# Spec 1 W9e, Task 3: what moved out of each index.ts is unchanged. Prints
# every line of the new handler and index that today's index.ts does not
# have (they must all be Spec 1 W9e's), then "moved-verbatim <fn>" when
# every line of today's index.ts is still in the handler or the new index,
# in the same order within each file. Run from the repo root.
import pathlib, subprocess, sys
for folder, handler in [("generate-healing-portrait", "portrait_handler.ts"),
                        ("generate-healing-post-mortem", "post_mortem_handler.ts")]:
    before = subprocess.run(["git", "show", f"HEAD:supabase/functions/{folder}/index.ts"],
                            capture_output=True, text=True, check=True).stdout.split("\n")
    h = pathlib.Path(f"supabase/functions/{folder}/{handler}").read_text().split("\n")
    i = pathlib.Path(f"supabase/functions/{folder}/index.ts").read_text().split("\n")
    old = set(l.strip() for l in before)
    extra = [l.strip() for l in h + i if l.strip() and l.strip() not in old]
    print(f"--- {folder}: {len(extra)} new lines")
    for l in extra:
        print("   ", l)
    # Every old line (but the import lines index.ts no longer needs and the
    # serve wrapper's 2-space indent) survives somewhere, in order.
    new_stripped = [l.strip() for l in h + i]
    missing = [l.strip() for l in before if l.strip() and l.strip() not in new_stripped]
    print(f"    missing from the move: {missing}")
```

Run: `python3 -I $D/verbatim_check.py`
Expected, for each function: `46 new lines`, every one a header comment line, the handler signature, a line carrying `Spec 1 W9e`, the gate block (`const gate = ...`, `if (gate) {`, `return json(gate);`), the injected-deps block in `index.ts`, the three new imports, `export const corsHeaders = {`, `export function json(...)`, and the four replaced lines in their new form; and `missing from the move:` exactly the six lines W9e replaced: `const corsHeaders = {`, `if (journeyRes.error) {`, the old `let output = await maybeGenerateWithGemini(evidence, ...)`, the old `async function maybeGenerateWithGemini(evidence: any, ...)`, `const parsed = await callGeminiJson({`, `function json(body: unknown, status = 200) {`.

- [ ] **Step 7: Mutation checks (each must turn a test red)**

Create `$D/mutants_t3.py` with exactly:

```python
# Spec 1 W9e Task 3 mutants: each must turn a test red. Run from
# supabase/functions.
import os, pathlib, subprocess
CMD = ["deno", "test", "--allow-read", "--allow-env", "--lock=../../.github/deno-w9.lock", "--frozen",
       "_shared/healing_ai_gate.test.ts", "generate-healing-portrait/", "generate-healing-post-mortem/"]
GATE = "_shared/healing_ai_gate.ts"
PORTRAIT = "generate-healing-portrait/portrait_handler.ts"
POST = "generate-healing-post-mortem/post_mortem_handler.ts"
P_INDEX = "generate-healing-portrait/index.ts"
CHECK = """  const victimisation = await readVictimisation(deps);
  const text = reflectionTextOf(journey?.reflection_answers);
  if (text === null || writerTextDiscloses(text, victimisation)) {
    await removeStaleOutput(adminClient, userId, journey, stage);
    return { ...SUPPORT_OFFERED_BODY };
  }
"""
PAUSE = """  if (await aiPaused(deps)) {
    return { ...PAUSED_BODY };
  }
"""
def gate_line(stage):
    return f"""  const gate = await healingGate(adminClient, user.id, journey, "{stage}", deps);
  if (gate) {{
    return json(gate);
  }}
"""
SAVED_P = '  if (journey.portrait_status === "completed" && journey.portrait_text) {\n'
SAVED_M = '  if (journey.post_mortem_status === "completed" && journey.post_mortem_observation) {\n'
CACHE_HIT = "  if (existing.data) {\n"
MUTANTS = {
    "victim_throw_open": [(GATE, "  } catch {\n    return null;\n  }\n", "  } catch {\n    return false;\n  }\n")],
    "list_answers_readable": [(GATE, '  if (typeof answers !== "object" || Array.isArray(answers)) return null;\n',
                               '  if (typeof answers !== "object" || Array.isArray(answers)) return "";\n')],
    "no_depth_cap": [(GATE, "depth >= MAX_ANSWER_DEPTH", "depth >= 1000")],
    "pause_throw_open": [(GATE, "  } catch {\n    return true;\n  }\n", "  } catch {\n    return false;\n  }\n")],
    "pause_first": [(GATE, CHECK + PAUSE, PAUSE + CHECK)],
    "no_stale_delete": [(GATE, """      const jobs = await adminClient
        .from("healing_generation_jobs")
        .delete()
        .eq("journey_id", journey.id)
        .eq("user_id", userId)
        .eq("stage", stage);
      if (jobs.error) continue;
""", "      const jobs = { error: null };\n")],
    "delete_error_unchecked": [(GATE, "      if (jobs.error) continue;\n", "")],
    "delete_unbounded_once": [(GATE, "for (let attempt = 0; attempt < DELETE_ATTEMPTS; attempt++)", "for (let attempt = 0; attempt < 1; attempt++)")],
    "delete_unscoped": [(GATE, '        .eq("journey_id", journey.id)\n        .eq("user_id", userId)\n        .eq("stage", stage);\n',
                         '        .eq("journey_id", journey.id)\n        .eq("stage", stage);\n')],
    "saved_text_kept": [(GATE, "      if (saved) {\n", "      if (false) {\n")],
    "portrait_no_gate": [(PORTRAIT, gate_line("portrait"), "")],
    "portrait_gate_after_saved": [(PORTRAIT, gate_line("portrait") + SAVED_P, SAVED_P), (PORTRAIT, '\n  const evidence = await buildPortraitEvidence(', '\n' + gate_line("portrait") + '  const evidence = await buildPortraitEvidence(')],
    "portrait_gate_after_cache": [(PORTRAIT, gate_line("portrait"), ""), (PORTRAIT, CACHE_HIT, gate_line("portrait") + CACHE_HIT)],
    "portrait_cache_unscoped": [(PORTRAIT, '    .eq("user_id", user.id) // Spec 1 W9e: the caller\'s own rows only\n', "")],
    "post_no_gate": [(POST, gate_line("post_mortem"), "")],
    "post_gate_after_saved": [(POST, gate_line("post_mortem") + SAVED_M, SAVED_M), (POST, '\n  const evidence = await buildPostMortemEvidence(', '\n' + gate_line("post_mortem") + '  const evidence = await buildPostMortemEvidence(')],
    "post_gate_after_cache": [(POST, gate_line("post_mortem"), ""), (POST, CACHE_HIT, gate_line("post_mortem") + CACHE_HIT)],
    "post_cache_unscoped": [(POST, '    .eq("user_id", user.id) // Spec 1 W9e: the caller\'s own rows only\n', "")],
    "post_wrong_stage": [(POST, gate_line("post_mortem"), gate_line("portrait"))],
    "index_pause_unwired": [(P_INDEX, "aiPaused: async () => !(await featureFlagEnabled(adminClient, HEALING_AI_FLAG)),", "aiPaused: async () => false,")],
}
def run():
    r = subprocess.run(CMD, capture_output=True, text=True, env={**os.environ, "NO_COLOR": "1"})
    return [l for l in r.stdout.splitlines() if l.startswith(("ok |", "FAILED |"))] or ["no result: " + (r.stderr.strip().splitlines() or ["?"])[-1]]
originals = {f: pathlib.Path(f).read_text() for f in (GATE, PORTRAIT, POST, P_INDEX)}
try:
    for name, edits in MUTANTS.items():
        texts = dict(originals)
        for f, a, b in edits:
            assert texts[f].count(a) == 1, (name, a)
            texts[f] = texts[f].replace(a, b)
        for f, t in texts.items():
            pathlib.Path(f).write_text(t)
        print(name, run())
        for f, t in originals.items():
            pathlib.Path(f).write_text(t)
finally:
    for f, t in originals.items():
        pathlib.Path(f).write_text(t)
print("restored", run())
```

Run: `(cd supabase/functions && python3 -I ../../$D/mutants_t3.py)`
Expected (each `FAILED`):
```
victim_throw_open ['FAILED | 28 passed | 3 failed (...)']
list_answers_readable ['FAILED | 27 passed | 4 failed (...)']
no_depth_cap ['FAILED | 29 passed | 2 failed (...)']
pause_throw_open ['FAILED | 28 passed | 3 failed (...)']
pause_first ['FAILED | 29 passed | 2 failed (...)']
no_stale_delete ['FAILED | 26 passed | 5 failed (...)']
delete_error_unchecked ['FAILED | 30 passed | 1 failed (...)']
delete_unbounded_once ['FAILED | 30 passed | 1 failed (...)']
delete_unscoped ['FAILED | 29 passed | 2 failed (...)']
saved_text_kept ['FAILED | 29 passed | 2 failed (...)']
portrait_no_gate ['FAILED | 25 passed | 6 failed (...)']
portrait_gate_after_saved ['FAILED | 29 passed | 2 failed (...)']
portrait_gate_after_cache ['FAILED | 28 passed | 3 failed (...)']
portrait_cache_unscoped ['FAILED | 30 passed | 1 failed (...)']
post_no_gate ['FAILED | 25 passed | 6 failed (...)']
post_gate_after_saved ['FAILED | 29 passed | 2 failed (...)']
post_gate_after_cache ['FAILED | 28 passed | 3 failed (...)']
post_cache_unscoped ['FAILED | 30 passed | 1 failed (...)']
post_wrong_stage ['FAILED | 29 passed | 2 failed (...)']
index_pause_unwired ['FAILED | 30 passed | 1 failed (...)']
restored ['ok | 31 passed | 0 failed (...)']
```

- [ ] **Step 8: CI runs the W9e Deno tests**

```bash
python3 -I - .github/workflows/tests.yml <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); t = p.read_text()
pairs = [
    ("    name: Deno tests (W9 normaliser + journal check)\n",
     "    name: Deno tests (W9 normaliser + journal check, W9e Healing check)\n"),
    ("--frozen _shared/unicode_normaliser.test.ts analyse-journal-entry/\n",
     "--frozen _shared/unicode_normaliser.test.ts _shared/writer_crisis_check.test.ts _shared/healing_ai_gate.test.ts analyse-journal-entry/ generate-healing-portrait/ generate-healing-post-mortem/\n"),
]
for old, new in pairs:
    assert t.count(old) == 1, old
    t = t.replace(old, new)
p.write_text(t)
print("ci: ok")
PY
grep -n "deno test" .github/workflows/tests.yml
(cd supabase/functions && NO_COLOR=1 deno test --allow-read --allow-env --lock=../../.github/deno-w9.lock --frozen _shared/unicode_normaliser.test.ts _shared/writer_crisis_check.test.ts _shared/healing_ai_gate.test.ts analyse-journal-entry/ generate-healing-portrait/ generate-healing-post-mortem/ 2>&1 | grep -E '^(ok|FAILED) \|')
git diff --quiet .github/deno-w9.lock && echo lock-unchanged
```

Expected: `ci: ok`; the job's one `deno test` line with the six paths; `ok | 80 passed | 0 failed` (the same command CI runs, `--frozen`: no new remote module); `lock-unchanged`.

- [ ] **Step 9: Run tests**

```bash
(cd supabase/functions && NO_COLOR=1 deno test --allow-read --allow-env _shared/self_disclosure.test.ts _shared/assistant_input.test.ts 2>&1 | grep -E '^(ok|FAILED) \|')
grep -rn "callGeminiJson(" supabase/functions/generate-healing-portrait supabase/functions/generate-healing-post-mortem
```

Expected: `ok | 10 passed | 0 failed`; no line (the provider is only ever called through `deps.model`).

### Task 4: The Healing screens' card, the link, D8, and the W9e gate (spec §8 W9e, §2.2, §2.3, §5.8, §6.6, D8; W9 B8 rulings; P-6-P-11)

**Files:**
- Create: `lib/features/healing/presentation/providers/healing_support_providers.dart`
- Create: `lib/features/healing/presentation/widgets/healing_support.dart`
- Create: `test/features/healing/w9e/support/healing_fakes.dart`, `test/features/healing/w9e/healing_support_test.dart` (+ 12 goldens in `test/features/healing/w9e/goldens/`), `test/features/healing/w9e/healing_account_test.dart`
- Modify (by `$D/w9e_client_edits.py`): `lib/features/healing/presentation/providers/healing_providers.dart`, `lib/features/healing/presentation/screens/healing_post_mortem_screen.dart`, `.../healing_portrait_screen.dart`, `.../healing_reflection_screen.dart`, `lib/features/reflection_journal/presentation/widgets/journal_support_card.dart`, `lib/app/device_wipes.dart`, `lib/app/documentations/user_manual/data/healing_docs.dart`
- Modify (by `$D/spec_amend.py`): `docs/superpowers/specs/2026-10-24-app-flow-identity-design.md`

**Interfaces:**
- Consumes: the two statuses from Task 3; `JournalSupportCard`, `currentUserProvider`, `DeviceWipeEntry`, `RouteNames.safetyResources`.
- Produces: `healingAccountProvider` (`Provider<String?>`), `healingGenerationServiceProvider` (`Provider<HealingGenerationService>`) in `healing_providers.dart`; `enum HealingAiStage { postMortem, portrait }`, `typedef HealingSupportKey = ({String journeyId, HealingAiStage stage})`, `HealingSupportState { Set<HealingSupportKey> offered, hidden }`, `HealingSupport` (`offer`, `notNow`, `completed`, `account`), `healingSupportProvider`, `HealingSupportMemory` (`track`, `clear`) in `healing_support_providers.dart`; `openHealingSupport(BuildContext)`, `HealingSupportCard({required onNotNow})`, `HealingNeedSupportLink()` in `healing_support.dart`; `JournalSupportCard({required onNotNow, VoidCallback? onSeeSupport})`; the device-wipe entry `spec1.healing_support_memory`.

- [ ] **Step 1: Write the test support and the failing tests**

Create `test/features/healing/w9e/support/healing_fakes.dart` with exactly:

```dart
// Spec 1 W9e test support: a journey, the Healing functions and the
// repository, without Supabase.
import 'dart:async';

import 'package:attune/features/healing/data/models/healing_journey.dart';
import 'package:attune/features/healing/data/repositories/healing_repository.dart';
import 'package:attune/features/healing/services/healing_generation_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

const supportCardText =
    "If things feel heavy right now, you don't have to carry it alone. Support is here if you want it.";

User testUser(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-11-04T00:00:00Z',
);

HealingJourney testJourney({
  String id = 'j1',
  String userId = 'ama',
  int stage = 2,
  String postMortemStatus = 'not_started',
  String? postMortemObservation,
  String portraitStatus = 'not_started',
  String? portraitText,
}) => HealingJourney.fromJson({
  'id': id,
  'user_id': userId,
  'relationship_id': null,
  'breakup_at': '2026-10-01T00:00:00Z',
  'breakup_at_source': 'user_reported',
  'status': 'active',
  'current_stage': stage,
  'reflection_answers': <String, dynamic>{},
  'reflection_completed_at': '2026-10-02T00:00:00Z',
  'post_mortem_status': postMortemStatus,
  'post_mortem_observation': postMortemObservation,
  'post_mortem_confidence': postMortemObservation == null ? null : 'low',
  'post_mortem_reflection_prompt': null,
  'portrait_status': portraitStatus,
  'portrait_text': portraitText,
  'portrait_prompt': null,
  'created_at': '2026-10-02T00:00:00Z',
  'updated_at': '2026-10-02T00:00:00Z',
});

/// The two functions: each call takes the next answer; [gate], when set,
/// holds every answer until it completes.
class FakeHealingGeneration implements HealingGenerationService {
  FakeHealingGeneration(this.answers);

  final List<Map<String, dynamic>?> answers;
  final calls = <String>[];
  Completer<void>? gate;

  Future<Map<String, dynamic>?> _next(String what) async {
    calls.add(what);
    await gate?.future;
    return answers.isEmpty ? null : answers.removeAt(0);
  }

  @override
  Future<Map<String, dynamic>?> generatePostMortem({
    required String journeyId,
  }) => _next('post_mortem:$journeyId');

  @override
  Future<Map<String, dynamic>?> generatePortrait({required String journeyId}) =>
      _next('portrait:$journeyId');
}

/// Records what a stage screen saves; [latest] answers each account's
/// journey, and [hold] keeps the next account's read open.
class FakeHealingRepository implements HealingRepository {
  final saved = <String>[];
  final latest = <String, HealingJourney?>{};
  String account = 'ama';
  Completer<void>? hold;

  @override
  Future<void> completePostMortem({
    required String journeyId,
    required String status,
    String? observation,
    String? confidence,
    String? reflectionPrompt,
  }) async => saved.add('post_mortem:$status');

  @override
  Future<void> completePortrait({
    required String journeyId,
    required String status,
    String? portraitText,
    String? portraitReflection,
    String? reflectionPrompt,
  }) async => saved.add('portrait:$status');

  @override
  Future<HealingJourney?> getLatestJourney() async {
    final who = account;
    if (who != 'ama') await hold?.future;
    return latest[who];
  }

  @override
  Future<Map<String, dynamic>?> getStartableRelationship() async => null;

  @override
  Future<Map<String, dynamic>?> getLatestReadinessAttempt(
    String journeyId,
  ) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
```

Create `test/features/healing/w9e/healing_support_test.dart` with exactly:

```dart
// Spec 1 W9e (spec 8 W9e, 6.6, 2.2, 2.3; owner approval O2): when Healing's
// crisis check answers support_offered, the stage shows W9c's card instead
// of any AI text and saves nothing; "See support" opens Support; "Not now"
// puts the card away and the AI text stays hidden this run. paused keeps
// today's path. The state is this account's, in memory only: gone on an
// account change, sign-out and quick exit (D8). "Need support now?" is at
// the end of the reflection, whatever the flags say.
//   flutter test --update-goldens test/features/healing/w9e/healing_support_test.dart
import 'dart:async';

import 'package:attune/app/device_wipes.dart';
import 'package:attune/app/documentations/user_manual/data/documentation_flags.dart';
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/healing/data/models/healing_journey.dart';
import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:attune/features/healing/presentation/providers/healing_support_providers.dart';
import 'package:attune/features/healing/presentation/screens/healing_portrait_screen.dart';
import 'package:attune/features/healing/presentation/screens/healing_post_mortem_screen.dart';
import 'package:attune/features/healing/presentation/screens/healing_reflection_screen.dart';
import 'package:attune/features/healing/presentation/widgets/healing_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/flow_harness.dart';
import 'support/healing_fakes.dart';

const _offered = {'status': 'support_offered'};
const _paused = {'status': 'paused'};
const _ready = 'Ready for a grounded reflection on the relationship dynamic?';
const _notEnough =
    'There is not enough information for a grounded reflection yet.';

final _signedIn = StateProvider<String?>((ref) => 'ama');

List<Override> _overrides(
  FakeHealingGeneration gen,
  FakeHealingRepository repo, [
  List<Override> more = const [],
]) => [
  healingGenerationServiceProvider.overrideWithValue(gen),
  healingRepositoryProvider.overrideWithValue(repo),
  healingAccountProvider.overrideWith((ref) => ref.watch(_signedIn)),
  ...more,
];

ProviderContainer _container(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(Scaffold).first));

/// The support state seeded with [key] already offered and hidden.
class _Seeded extends HealingSupport {
  _Seeded(this.key);

  final HealingSupportKey key;

  @override
  HealingSupportState build() {
    super.build();
    return HealingSupportState(offered: {key}, hidden: {key});
  }
}

Widget Function() _postMortem(HealingJourney j) =>
    () => HealingPostMortemScreen(journey: j);

void main() {
  testWidgets(
    'post-mortem: support_offered shows the card, saves nothing, shows no AI text',
    (t) async {
      final gen = FakeHealingGeneration([_offered, _offered]);
      final repo = FakeHealingRepository();
      await pumpFlowScreen(
        t,
        _postMortem(testJourney()),
        overrides: _overrides(gen, repo),
      );
      expect(find.text(_ready), findsOneWidget);
      await t.tap(find.text('Generate reflection'));
      await t.pumpAndSettle();
      expect(gen.calls, ['post_mortem:j1']);
      expect(find.text(supportCardText), findsOneWidget);
      expect(find.text('One pattern that surfaced:'), findsNothing);
      expect(repo.saved, isEmpty); // nothing saved about the match

      await t.tap(find.text('Not now'));
      await t.pumpAndSettle();
      expect(find.text(supportCardText), findsNothing);
      expect(find.text(_ready), findsOneWidget);
      expect(_container(t).read(healingSupportProvider).hidden, {
        (journeyId: 'j1', stage: HealingAiStage.postMortem),
      });

      await t.tap(find.text('Generate reflection'));
      await t.pumpAndSettle();
      expect(find.text(supportCardText), findsOneWidget); // the check again
      expect(repo.saved, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.contains('support')), isEmpty);
    },
  );

  testWidgets('portrait: support_offered shows the card, saves nothing', (
    t,
  ) async {
    final gen = FakeHealingGeneration([_offered]);
    final repo = FakeHealingRepository();
    await pumpFlowScreen(
      t,
      () => HealingPortraitScreen(journey: testJourney(stage: 4)),
      overrides: _overrides(gen, repo),
    );
    await t.tap(find.text('Generate portrait'));
    await t.pumpAndSettle();
    expect(gen.calls, ['portrait:j1']);
    expect(find.text(supportCardText), findsOneWidget);
    expect(find.text('How you show up in relationships:'), findsNothing);
    expect(repo.saved, isEmpty);
  });

  testWidgets('See support opens Support, uncounted', (t) async {
    final h = await pumpFlowScreen(
      t,
      _postMortem(testJourney()),
      overrides: _overrides(
        FakeHealingGeneration([_offered]),
        FakeHealingRepository(),
      ),
    );
    await t.tap(find.text('Generate reflection'));
    await t.pumpAndSettle();
    await t.tap(find.text('See support'));
    await t.pumpAndSettle();
    expect(find.text('at /safety-resources'), findsOneWidget);
    expect(h.metrics, isEmpty);
  });

  testWidgets(
    'paused keeps today\'s path: insufficient_evidence, today\'s words',
    (t) async {
      final repo = FakeHealingRepository();
      await pumpFlowScreen(
        t,
        _postMortem(testJourney()),
        overrides: _overrides(FakeHealingGeneration([_paused]), repo),
      );
      await t.tap(find.text('Generate reflection'));
      await t.pumpAndSettle();
      expect(repo.saved, ['post_mortem:insufficient_evidence']);
      expect(find.text(_notEnough), findsOneWidget);
      // Review Focus 5: the person can still finish the stage.
      expect(find.text('Continue \u2192'), findsOneWidget);
      expect(find.text(supportCardText), findsNothing);
    },
  );

  testWidgets(
    'a later completed answer is shown: written for the words as they are now',
    (t) async {
      final repo = FakeHealingRepository();
      await pumpFlowScreen(
        t,
        _postMortem(testJourney()),
        overrides: _overrides(
          FakeHealingGeneration([
            _offered,
            {
              'status': 'completed',
              'observation': 'A fresh observation.',
              'confidence': 'low',
              'reflection_prompt': null,
            },
          ]),
          repo,
        ),
      );
      await t.tap(find.text('Generate reflection'));
      await t.pumpAndSettle();
      await t.tap(find.text('Not now'));
      await t.pumpAndSettle();
      await t.tap(find.text('Generate reflection'));
      await t.pumpAndSettle();
      expect(find.text('A fresh observation.'), findsOneWidget);
      expect(repo.saved, ['post_mortem:completed']);
      expect(_container(t).read(healingSupportProvider).hidden, isEmpty);
    },
  );

  testWidgets(
    'reopened this run: saved AI text the check matched stays hidden, the card shows',
    (t) async {
      const key = (journeyId: 'j1', stage: HealingAiStage.postMortem);
      await pumpFlowScreen(
        t,
        _postMortem(
          testJourney(
            postMortemStatus: 'completed',
            postMortemObservation: 'An older observation.',
          ),
        ),
        overrides: _overrides(
          FakeHealingGeneration([]),
          FakeHealingRepository(),
          [healingSupportProvider.overrideWith(() => _Seeded(key))],
        ),
      );
      expect(find.text('An older observation.'), findsNothing);
      expect(find.text(supportCardText), findsOneWidget);
      await t.tap(find.text('Not now'));
      await t.pumpAndSettle();
      expect(find.text('An older observation.'), findsNothing);
      expect(find.text(_notEnough), findsOneWidget);
      expect(find.text('Continue \u2192'), findsOneWidget);
    },
  );

  testWidgets(
    'a completed stage whose AI text was removed shows as having none',
    (t) async {
      await pumpFlowScreen(
        t,
        _postMortem(testJourney(postMortemStatus: 'completed')),
        overrides: _overrides(
          FakeHealingGeneration([]),
          FakeHealingRepository(),
        ),
      );
      expect(find.text(_notEnough), findsOneWidget);
      expect(find.text(_ready), findsNothing);
      expect(find.text('Continue \u2192'), findsOneWidget);
    },
  );

  testWidgets(
    'D8: an answer that lands after the account changed is dropped, and the '
    'next account starts with no support state',
    (t) async {
      final gen = FakeHealingGeneration([_offered])..gate = Completer<void>();
      await pumpFlowScreen(
        t,
        _postMortem(testJourney()),
        overrides: _overrides(gen, FakeHealingRepository()),
      );
      await t.tap(find.text('Generate reflection'));
      await t.pump();
      final c = _container(t);
      c.read(_signedIn.notifier).state = 'kofi';
      await t.pump();
      gen.gate!.complete();
      await t.pump();
      await t.pump();
      expect(c.read(healingSupportProvider).offered, isEmpty);
      expect(c.read(healingSupportProvider).hidden, isEmpty);
      expect(find.text(supportCardText), findsNothing);
    },
  );

  testWidgets('D8: an account change empties the support state', (t) async {
    await pumpFlowScreen(
      t,
      _postMortem(testJourney()),
      overrides: _overrides(
        FakeHealingGeneration([_offered]),
        FakeHealingRepository(),
      ),
    );
    await t.tap(find.text('Generate reflection'));
    await t.pumpAndSettle();
    expect(find.text(supportCardText), findsOneWidget);
    _container(t).read(_signedIn.notifier).state = 'kofi';
    await t.pump();
    expect(_container(t).read(healingSupportProvider).offered, isEmpty);
    expect(find.text(supportCardText), findsNothing);
  });

  testWidgets('sign-out and quick exit empty the support state', (t) async {
    await pumpFlowScreen(
      t,
      _postMortem(testJourney()),
      overrides: _overrides(
        FakeHealingGeneration([_offered]),
        FakeHealingRepository(),
      ),
    );
    await t.tap(find.text('Generate reflection'));
    await t.pumpAndSettle();
    final registry = DeviceWipeRegistry();
    registerDeviceWipes(registry);
    final entry = registry.entries.firstWhere(
      (e) => e.id == 'spec1.healing_support_memory',
    );
    expect(entry.moments, {WipeMoment.signOut, WipeMoment.quickExit});
    expect(entry.keys, isEmpty);
    expect(entry.protective, isFalse);
    expect(_container(t).read(healingSupportProvider).offered, isNotEmpty);
    await entry.run();
    await t.pump();
    expect(_container(t).read(healingSupportProvider).offered, isEmpty);
    expect(_container(t).read(healingSupportProvider).hidden, isEmpty);
    expect(find.text(supportCardText), findsNothing);
  });

  testWidgets('the card is a plain widget: nothing on it animates (spec 2.2)', (
    t,
  ) async {
    await pumpFlowScreen(
      t,
      _postMortem(testJourney()),
      overrides: _overrides(
        FakeHealingGeneration([_offered]),
        FakeHealingRepository(),
      ),
    );
    await t.tap(find.text('Generate reflection'));
    await t.pump(); // one frame: the card is there at once
    await t.pump();
    expect(find.text(supportCardText), findsOneWidget);
    for (final type in [
      FadeTransition,
      SlideTransition,
      ScaleTransition,
      AnimatedSwitcher,
      AnimatedOpacity,
    ]) {
      expect(
        find.ancestor(
          of: find.text(supportCardText),
          matching: find.byType(type),
        ),
        findsNothing,
        reason: '$type above the card',
      );
    }
  });

  testWidgets(
    '"Need support now?" ends the reflection, always; opens Support',
    (t) async {
      final h = await pumpFlowScreen(
        t,
        () => HealingReflectionScreen(journey: testJourney(stage: 1)),
        overrides: _overrides(
          FakeHealingGeneration([]),
          FakeHealingRepository(),
        ),
      );
      await t.scrollUntilVisible(
        find.text('Need support now?'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.ensureVisible(find.text('Need support now?'));
      await t.pumpAndSettle();
      await t.tap(find.text('Need support now?'));
      await t.pumpAndSettle();
      expect(find.text('at /safety-resources'), findsOneWidget);
      expect(h.metrics, isEmpty);
    },
  );

  testWidgets('the manual passage needs no flag (W9 B8 I-4)', (t) async {
    DocumentationRegistry.initialize();
    late BuildContext context;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          documentationFlagsProvider.overrideWith((ref) async => <String>{}),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (c, ref, _) {
              ref.watch(documentationFlagsProvider);
              context = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final module = DocumentationRegistry.getById('healing')!;
    final ids = [
      for (final s in module.getSections(context))
        for (final c in s.contents) c.id,
    ];
    expect(ids, contains('healing_support_first'));
  });

  testWidgets('the card and the link meet the guidelines and let large text '
      'through', (t) async {
    Widget pieces() => Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            HealingSupportCard(onNotNow: () {}),
            const HealingNeedSupportLink(),
          ],
        ),
      ),
    );
    await pumpFlowScreen(t, pieces);
    await expectFlowGuidelines(t);
    await pumpFlowScreen(t, pieces, textScale: 2.0);
    expect(
      MediaQuery.of(t.element(find.text(supportCardText))).textScaler.scale(10),
      20,
    );
    expect(
      MediaQuery.of(
        t.element(find.text('Need support now?')),
      ).textScaler.scale(10),
      20,
    );
    await expectFlowGuidelines(t);
  });

  testWidgets(
    'Review Focus 1: an answer after the screen closed raises nothing, and '
    'the card waits for the next visit',
    (t) async {
      final gen = FakeHealingGeneration([_offered])..gate = Completer<void>();
      final h = await pumpFlowScreen(
        t,
        _postMortem(testJourney()),
        overrides: _overrides(gen, FakeHealingRepository()),
      );
      await t.tap(find.text('Generate reflection'));
      await t.pump();
      final c = _container(t);
      h.router.go('/elsewhere'); // the person left the stage
      await t.pumpAndSettle();
      expect(find.byType(HealingPostMortemScreen), findsNothing);
      gen.gate!.complete();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(c.read(healingSupportProvider).offered, {
        (journeyId: 'j1', stage: HealingAiStage.postMortem),
      });
      h.router.go('/test'); // back to the stage, this run
      await t.pumpAndSettle();
      expect(find.text(supportCardText), findsOneWidget);
    },
  );

  testWidgets(
    'Review Focus 2: at 2.0 the card scrolls and See support stays reachable',
    (t) async {
      await pumpFlowScreen(
        t,
        _postMortem(testJourney()),
        textScale: 2.0,
        overrides: _overrides(
          FakeHealingGeneration([_offered]),
          FakeHealingRepository(),
        ),
      );
      await t.tap(find.text('Generate reflection'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('See support'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('See support'));
      await t.pumpAndSettle();
      expect(find.text('at /safety-resources'), findsOneWidget);
    },
  );

  testWidgets('goldens: the card on both stages, and the link', (t) async {
    Future<void> generate(WidgetTester t, String label) async {
      await t.tap(find.text(label));
      await t.pumpAndSettle();
    }

    await expectFlowGoldens(
      t,
      'healing_post_mortem_support',
      _postMortem(testJourney()),
      overrides: _overrides(
        FakeHealingGeneration(List.filled(4, _offered, growable: true)),
        FakeHealingRepository(),
      ),
      before: (t) => generate(t, 'Generate reflection'),
    );
    await expectFlowGoldens(
      t,
      'healing_portrait_support',
      () => HealingPortraitScreen(journey: testJourney(stage: 4)),
      overrides: _overrides(
        FakeHealingGeneration(List.filled(4, _offered, growable: true)),
        FakeHealingRepository(),
      ),
      before: (t) => generate(t, 'Generate portrait'),
    );
    await expectFlowGoldens(
      t,
      'healing_reflection_support_link',
      () => HealingReflectionScreen(journey: testJourney(stage: 1)),
      overrides: _overrides(FakeHealingGeneration([]), FakeHealingRepository()),
      before: (t) async {
        await t.scrollUntilVisible(
          find.text('Need support now?'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
      },
    );
  });
}
```

Create `test/features/healing/w9e/healing_account_test.dart` with exactly:

```dart
// Spec 1 W9e (D8, shared phones): Healing's journey, start context and
// readiness answers belong to the signed-in account. When another account
// signs in on the same phone, the Healing screen never shows the last
// account's journey: not while the next account's read is out, not after
// it fails, and not when a read answers for another account.
import 'dart:async';

import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:attune/features/healing/presentation/screens/healing_journey_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import 'support/healing_fakes.dart';

final _signedIn = StateProvider<String?>((ref) => 'ama');

ProviderContainer _container(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(Scaffold).first));

Future<FakeHealingRepository> _pumpAma(WidgetTester t) async {
  final repo =
      FakeHealingRepository()
        ..latest['ama'] = testJourney(userId: 'ama', stage: 2)
        ..latest['kofi'] = testJourney(id: 'j2', userId: 'kofi', stage: 4);
  await pumpFlowScreen(
    t,
    () => const HealingJourneyScreen(),
    // The stage row is wider than a phone in the test font (Ahem), which
    // is not what this test is about.
    size: const Size(900, 1200),
    overrides: [
      healingRepositoryProvider.overrideWithValue(repo),
      healingAccountProvider.overrideWith((ref) => ref.watch(_signedIn)),
    ],
  );
  expect(find.text('Stage 2 of 5'), findsOneWidget);
  return repo;
}

void main() {
  testWidgets(
    'the next account never sees the last one\'s journey while its read is out',
    (t) async {
      final repo = await _pumpAma(t);
      repo
        ..account = 'kofi'
        ..hold = Completer<void>();
      _container(t).read(_signedIn.notifier).state = 'kofi';
      // Frame by frame while Kofi's read is out: never Ama's journey.
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
        expect(find.text('Stage 2 of 5'), findsNothing, reason: 'frame $i');
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      }
      repo.hold!.complete();
      await t.pumpAndSettle();
      expect(find.text('Stage 4 of 5'), findsOneWidget);
      expect(find.text('Stage 2 of 5'), findsNothing);
    },
  );

  testWidgets('the next account\'s read fails: an error, never the last '
      'account\'s journey', (t) async {
    final repo = await _pumpAma(t);
    final hold = Completer<void>();
    repo
      ..account = 'kofi'
      ..hold = hold;
    _container(t).read(_signedIn.notifier).state = 'kofi';
    await t.pump();
    hold.completeError(Exception('offline'));
    await t.pump();
    await t.pump();
    expect(find.text('Stage 2 of 5'), findsNothing);
    expect(find.textContaining('offline'), findsOneWidget);
  });

  testWidgets('a read that answers for another account is never shown', (
    t,
  ) async {
    final repo = await _pumpAma(t);
    // The phone's session still answers for Ama after Kofi signed in.
    repo.latest['kofi'] = testJourney(userId: 'ama', stage: 2);
    repo.account = 'kofi';
    _container(t).read(_signedIn.notifier).state = 'kofi';
    await t.pumpAndSettle();
    expect(find.text('Stage 2 of 5'), findsNothing);
    expect(
      find.textContaining('a healing journey is available'),
      findsOneWidget,
    );
  });
}
```

- [ ] **Step 2: Run them to make sure they fail**

Run: `flutter test --no-pub test/features/healing/w9e/ 2>&1 | grep -E "Error: |Some tests failed" | head -4`
Expected: compile errors, among them `Error: Error when reading 'lib/features/healing/presentation/providers/healing_support_providers.dart': No such file or directory`, `Error: Error when reading 'lib/features/healing/presentation/widgets/healing_support.dart': No such file or directory` and `Error: Undefined name 'healingAccountProvider'.`, then `Some tests failed.`

- [ ] **Step 3: Write the support state and the widgets**

Create `lib/features/healing/presentation/providers/healing_support_providers.dart` with exactly:

```dart
import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The two Healing stages whose AI the crisis check guards (Spec 1 W9e).
enum HealingAiStage { postMortem, portrait }

/// One journey's stage, as the support state holds it.
typedef HealingSupportKey = ({String journeyId, HealingAiStage stage});

/// What the crisis check's `support_offered` answers mean for this run and
/// this account (Spec 1 W9e, W9c's pattern): [offered] shows the card for
/// that journey's stage; [hidden] keeps any AI text the phone holds for it
/// off the screen, also after "Not now", until a later `completed` answer
/// for that stage. Never stored on the phone, never sent anywhere.
@immutable
class HealingSupportState {
  const HealingSupportState({this.offered = const {}, this.hidden = const {}});

  final Set<HealingSupportKey> offered;
  final Set<HealingSupportKey> hidden;
}

/// Held in memory only (Spec 1, spec 6.6): emptied when the signed-in account
/// changes (D8, shared phones), and on sign-out and quick exit through the
/// device-wipe registry (`spec1.healing_support_memory`; on iOS quick exit
/// leaves the process alive behind the neutral screen).
class HealingSupport extends Notifier<HealingSupportState> {
  /// The account this state belongs to.
  String? account;

  @override
  HealingSupportState build() {
    account = ref.watch(healingAccountProvider);
    HealingSupportMemory.track(
      this,
      ref,
      () => state = const HealingSupportState(),
    );
    return const HealingSupportState();
  }

  /// `support_offered` for [key]: the card, and its AI text hidden.
  void offer(HealingSupportKey key) =>
      state = HealingSupportState(
        offered: {...state.offered, key},
        hidden: {...state.hidden, key},
      );

  /// "Not now": the card goes; the AI text stays hidden.
  void notNow(HealingSupportKey key) =>
      state = HealingSupportState(
        offered: {...state.offered}..remove(key),
        hidden: state.hidden,
      );

  /// A later `completed` answer for [key]: written for the words as they
  /// are now, so it may be shown.
  void completed(HealingSupportKey key) =>
      state = HealingSupportState(
        offered: {...state.offered}..remove(key),
        hidden: {...state.hidden}..remove(key),
      );
}

final healingSupportProvider =
    NotifierProvider<HealingSupport, HealingSupportState>(HealingSupport.new);

/// Healing's in-memory support state, emptied on sign-out and quick exit
/// (lib/app/device_wipes.dart). Mirrors the journal's JournalSupportMemory.
abstract final class HealingSupportMemory {
  static final _clears = <Object, void Function()>{};

  /// [owner]'s [clear], until [ref] is disposed or rebuilt.
  static void track(Object owner, Ref ref, void Function() clear) {
    _clears[owner] = clear;
    ref.onDispose(() => _clears.remove(owner));
  }

  static Future<void> clear() async {
    for (final clear in List.of(_clears.values)) {
      try {
        clear();
      } catch (_) {
        // A notifier being torn down has nothing left to clear.
      }
    }
  }
}
```

Create `lib/features/healing/presentation/widgets/healing_support.dart` with exactly:

```dart
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/reflection_journal/presentation/widgets/journal_support_card.dart'
    show JournalSupportCard;
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Opens Support (W7a's screen and route; with support_resources_v2 off,
/// today's Safety resources screen). Spec 1 W9e: Healing's opens are not
/// counted (plan P-6). Nothing about it is stored on the phone.
void openHealingSupport(BuildContext context) =>
    context.push(RouteNames.safetyResources);

/// The writer's card on a Healing stage (Spec 1 W9e): W9c's card, the same
/// words the clinician signs, shown instead of the AI text when the crisis
/// check answers `support_offered`. Never animated (spec 2.2); large text let
/// through.
class HealingSupportCard extends StatelessWidget {
  const HealingSupportCard({super.key, required this.onNotNow});

  final VoidCallback onNotNow;

  @override
  Widget build(BuildContext context) => JournalSupportCard(
    onNotNow: onNotNow,
    onSeeSupport: () => openHealingSupport(context),
  );
}

/// "Need support now?" at the end of the Healing reflection (Spec 1 W9e):
/// always there, whatever healing_ai_insights says. Looks like W9b's link.
class HealingNeedSupportLink extends StatelessWidget {
  const HealingNeedSupportLink({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return AllowLargeText(
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            foregroundColor: scheme.onSurface,
            padding: Spacing.horizontalSm,
          ),
          onPressed: () => openHealingSupport(context),
          icon: const Icon(Icons.support_outlined, size: 20),
          label: Text(loc.support_needSupportNow),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Edit the existing files**

Create `$D/w9e_client_edits.py` with exactly:

```python
# Spec 1 W9e, Task 4: exact-string edits to existing Dart files. Each anchor
# must occur once; the script stops at the first that does not.
import pathlib, sys

def edit(path, pairs):
    p = pathlib.Path(path)
    t = p.read_text()
    for old, new in pairs:
        assert t.count(old) == 1, (path, old[:70], t.count(old))
        t = t.replace(old, new)
    p.write_text(t)
    print("edited", path)

# 1. Providers: the account (D8), the generation service seam.
edit("lib/features/healing/presentation/providers/healing_providers.dart", [
    ("import 'package:attune/features/healing/data/models/healing_journey.dart';\n",
     "import 'package:attune/features/auth/providers/auth_provider.dart'\n"
     "    show currentUserProvider;\n"
     "import 'package:attune/features/healing/data/models/healing_journey.dart';\n"),
    ("import 'package:attune/features/healing/data/repositories/healing_repository.dart';\n",
     "import 'package:attune/features/healing/data/repositories/healing_repository.dart';\n"
     "import 'package:attune/features/healing/services/healing_generation_service.dart';\n"),
    ("final healingJourneyProvider = FutureProvider<HealingJourney?>((ref) async {\n"
     "  final repository = ref.read(healingRepositoryProvider);\n"
     "  return repository.getLatestJourney();\n"
     "});\n",
     "/// Spec 1 W9e (D8, shared phones): the signed-in account's id (null signed\n"
     "/// out). Healing's journey, its start context and its readiness answers\n"
     "/// are this account's only: they are read again when it changes.\n"
     "final healingAccountProvider = Provider<String?>(\n"
     "  (ref) => ref.watch(currentUserProvider.select((u) => u?.id)),\n"
     ");\n"
     "\n"
     "/// Spec 1 W9e: the two Healing AI functions, behind a provider so the\n"
     "/// stage screens can be tested without Supabase.\n"
     "final healingGenerationServiceProvider = Provider<HealingGenerationService>(\n"
     "  (ref) => HealingGenerationService(supabase: ref.read(supabaseClientProvider)),\n"
     ");\n"
     "\n"
     "final healingJourneyProvider = FutureProvider<HealingJourney?>((ref) async {\n"
     "  final account = ref.watch(healingAccountProvider); // Spec 1 W9e (D8)\n"
     "  final repository = ref.read(healingRepositoryProvider);\n"
     "  final journey = await repository.getLatestJourney();\n"
     "  // Spec 1 W9e (D8): never a journey read for another account.\n"
     "  return journey != null && journey.userId == account ? journey : null;\n"
     "});\n"),
    ("final healingStartContextProvider = FutureProvider<HealingStartContext?>((\n"
     "  ref,\n"
     ") async {\n",
     "final healingStartContextProvider = FutureProvider<HealingStartContext?>((\n"
     "  ref,\n"
     ") async {\n"
     "  ref.watch(healingAccountProvider); // Spec 1 W9e (D8)\n"),
    ("      ref,\n"
     "      journeyId,\n"
     "    ) async {\n"
     "      return ref\n"
     "          .read(healingRepositoryProvider)\n"
     "          .getLatestReadinessAttempt(journeyId);\n",
     "      ref,\n"
     "      journeyId,\n"
     "    ) async {\n"
     "      ref.watch(healingAccountProvider); // Spec 1 W9e (D8)\n"
     "      return ref\n"
     "          .read(healingRepositoryProvider)\n"
     "          .getLatestReadinessAttempt(journeyId);\n"),
])

# 2. W9c's card: Healing opens Support itself (the journal's default stays).
edit("lib/features/reflection_journal/presentation/widgets/journal_support_card.dart", [
    ("  const JournalSupportCard({super.key, required this.onNotNow});\n\n"
     "  final VoidCallback onNotNow;\n",
     "  const JournalSupportCard({\n"
     "    super.key,\n"
     "    required this.onNotNow,\n"
     "    this.onSeeSupport,\n"
     "  });\n\n"
     "  final VoidCallback onNotNow;\n\n"
     "  /// Spec 1 W9e: Healing opens Support itself; by default the journal's\n"
     "  /// link, counted as support_link_opened:journal.\n"
     "  final VoidCallback? onSeeSupport;\n"),
    ("                    onPressed:\n"
     "                        () => openSupportNow(\n"
     "                          context,\n"
     "                          ref,\n"
     "                          SupportLinkSource.journal,\n"
     "                        ),\n",
     "                    onPressed:\n"
     "                        onSeeSupport ??\n"
     "                        () => openSupportNow(\n"
     "                          context,\n"
     "                          ref,\n"
     "                          SupportLinkSource.journal,\n"
     "                        ),\n"),
])

# 3. The device-wipe entry.
edit("lib/app/device_wipes.dart", [
    ("import 'package:attune/features/onboarding/data/ask2_progress_store.dart';\n",
     "import 'package:attune/features/healing/presentation/providers/healing_support_providers.dart'\n"
     "    show HealingSupportMemory;\n"
     "import 'package:attune/features/onboarding/data/ask2_progress_store.dart';\n"),
    ("    run: JournalSupportMemory.clear,\n  ),\n];\n",
     "    run: JournalSupportMemory.clear,\n  ),\n"
     "  // W9e (D8): Healing's support card state, held in memory only (the\n"
     "  // offers and the hidden AI text), at sign-out and on quick exit (iOS\n"
     "  // keeps the process alive behind the neutral screen). No device key.\n"
     "  DeviceWipeEntry(\n"
     "    id: 'spec1.healing_support_memory',\n"
     "    moments: const {WipeMoment.signOut, WipeMoment.quickExit},\n"
     "    run: HealingSupportMemory.clear,\n"
     "  ),\n];\n"),
])

# 4. The two stage screens.
for path, stage, field, fields_null, gen, svc, status_field, text_field in [
    ("lib/features/healing/presentation/screens/healing_post_mortem_screen.dart", "postMortem", "_observation",
     "          _observation = null;\n          _confidence = null;\n          _reflectionPrompt = null;\n",
     "_generatePostMortem", "generatePostMortem", "postMortemStatus", "postMortemObservation"),
    ("lib/features/healing/presentation/screens/healing_portrait_screen.dart", "portrait", "_portrait",
     "          _portrait = null;\n          _reflectionPrompt = null;\n",
     "_generatePortrait", "generatePortrait", "portraitStatus", "portraitText"),
]:
    p = pathlib.Path(path)
    t = p.read_text()
    pairs = [
        ("import 'package:attune/features/healing/services/healing_generation_service.dart';\n", ""),
        ("import '../providers/healing_providers.dart';\n",
         "import '../providers/healing_providers.dart';\n"
         "import '../providers/healing_support_providers.dart';\n"
         "import '../widgets/healing_support.dart';\n"),
        (f"  void _checkExistingStatus() {{\n    if (widget.journey.{status_field} == 'completed') {{\n",
         f"  /// Spec 1 W9e: this journey's stage in the support state.\n"
         f"  late final HealingSupportKey _supportKey = (\n"
         f"    journeyId: widget.journey.id,\n"
         f"    stage: HealingAiStage.{stage},\n"
         f"  );\n\n"
         f"  void _checkExistingStatus() {{\n"
         f"    // Spec 1 W9e: AI text the crisis check matched this run is never\n"
         f"    // shown, and a completed stage whose AI text was removed shows as\n"
         f"    // having none.\n"
         f"    final hidden = ref.read(healingSupportProvider).hidden.contains(\n"
         f"      _supportKey,\n"
         f"    );\n"
         f"    final saved = widget.journey.{text_field};\n"
         f"    if (widget.journey.{status_field} == 'completed' &&\n"
         f"        !hidden &&\n"
         f"        saved != null &&\n"
         f"        saved.trim().isNotEmpty) {{\n"),
        (f"    }} else if (widget.journey.{status_field} == 'skipped' ||\n",
         f"    }} else if (widget.journey.{status_field} == 'completed' ||\n"
         f"        widget.journey.{status_field} == 'skipped' ||\n"),
        (f"      final service = HealingGenerationService(\n"
         f"        supabase: ref.read(supabaseClientProvider),\n"
         f"      );\n",
         f"      final service = ref.read(healingGenerationServiceProvider);\n"),
        (f"      if (result != null && result['status'] == 'completed') {{\n",
         f"      // Spec 1 W9e: the crisis check matched. Nothing is saved; any AI\n"
         f"      // text held for this stage is hidden and the card shows instead.\n"
         f"      // An answer that lands after the account changed is dropped (D8).\n"
         f"      if (result != null && result['status'] == 'support_offered') {{\n"
         f"        if (support.account != account) return;\n"
         f"        support.offer(_supportKey);\n"
         + ("        _stopAnticipation();\n" if stage == "postMortem" else "")
         + f"        if (!mounted) return;\n"
         f"        setState(() {{\n"
         + fields_null +
         f"          _isGenerating = false;\n"
         f"        }});\n"
         f"        return;\n"
         f"      }}\n"
         f"      if (result != null && result['status'] == 'completed') {{\n"
         f"        support.completed(_supportKey); // Spec 1 W9e\n"),
    ]
    if stage == "postMortem":
        pairs.append(("    _startAnticipation();\n\n    try {\n",
                      "    _startAnticipation();\n"
                      "    // Spec 1 W9e: taken now; the answer may land after the screen or\n"
                      "    // the account is gone.\n"
                      "    final support = ref.read(healingSupportProvider.notifier);\n"
                      "    final account = ref.read(healingAccountProvider);\n\n"
                      "    try {\n"))
        pairs.append(("            if (_isGenerating) ...[\n",
                      "            if (_isGenerating) ...[\n"))
        pairs.append(("            ] else if (_isComplete && _observation != null) ...[\n",
                      "            ] else if (supportOffered) ...[\n"
                      "              // Spec 1 W9e: the card instead of the AI text.\n"
                      "              Gap(Spacing.md.h),\n"
                      "              Expanded(\n"
                      "                child: SingleChildScrollView(\n"
                      "                  child: HealingSupportCard(\n"
                      "                    onNotNow:\n"
                      "                        () => ref\n"
                      "                            .read(healingSupportProvider.notifier)\n"
                      "                            .notNow(_supportKey),\n"
                      "                  ),\n"
                      "                ),\n"
                      "              ),\n"
                      "            ] else if (_isComplete && _observation != null) ...[\n"))
    else:
        pairs.append(("    setState(() => _isGenerating = true);\n\n    try {\n      final service",
                      "    setState(() => _isGenerating = true);\n"
                      "    // Spec 1 W9e: taken now; the answer may land after the screen or\n"
                      "    // the account is gone.\n"
                      "    final support = ref.read(healingSupportProvider.notifier);\n"
                      "    final account = ref.read(healingAccountProvider);\n\n"
                      "    try {\n      final service"))
        pairs.append(("            ] else if (_isComplete && _portrait != null) ...[\n              Gap(Spacing.xl.h),\n",
                      "            ] else if (supportOffered) ...[\n"
                      "              // Spec 1 W9e: the card instead of the AI text.\n"
                      "              Gap(Spacing.md.h),\n"
                      "              Expanded(\n"
                      "                child: SingleChildScrollView(\n"
                      "                  child: HealingSupportCard(\n"
                      "                    onNotNow:\n"
                      "                        () => ref\n"
                      "                            .read(healingSupportProvider.notifier)\n"
                      "                            .notNow(_supportKey),\n"
                      "                  ),\n"
                      "                ),\n"
                      "              ),\n"
                      "            ] else if (_isComplete && _portrait != null) ...[\n              Gap(Spacing.xl.h),\n"))
    pairs.append(("    final textTheme = Theme.of(context).textTheme;\n\n    return Scaffold(\n",
                  "    final textTheme = Theme.of(context).textTheme;\n"
                  "    // Spec 1 W9e: the crisis check's card for this stage, this run.\n"
                  "    final supportOffered = ref.watch(\n"
                  "      healingSupportProvider.select((s) => s.offered.contains(_supportKey)),\n"
                  "    );\n\n"
                  "    return Scaffold(\n"))
    pairs = [(a, b) for a, b in pairs if a != b]
    for old, new in pairs:
        assert t.count(old) == 1, (path, old[:80], t.count(old))
        t = t.replace(old, new)
    p.write_text(t)
    print("edited", path)

# 5. The reflection screen's link.
edit("lib/features/healing/presentation/screens/healing_reflection_screen.dart", [
    ("import '../providers/healing_providers.dart';\n",
     "import '../providers/healing_providers.dart';\n"
     "import '../widgets/healing_support.dart';\n"),
    ("              );\n            }),\n          ],\n        ),\n        bottomNavigationBar: SafeArea(\n",
     "              );\n            }),\n"
     "            // Spec 1 W9e: always here, whatever healing_ai_insights says.\n"
     "            Gap(Spacing.md.h),\n"
     "            const HealingNeedSupportLink(),\n"
     "          ],\n        ),\n        bottomNavigationBar: SafeArea(\n"),
])

# 6. The manual passage (no flag, like the check itself).
edit("lib/app/documentations/user_manual/data/healing_docs.dart", [
    ("              'Safety resources and the quick-exit gesture remain available on every screen throughout Healing Mode, exactly like everywhere else in the app.',\n"
     "          type: ManualContentType.important,\n"
     "        ),\n",
     "              'Safety resources and the quick-exit gesture remain available on every screen throughout Healing Mode, exactly like everywhere else in the app.',\n"
     "          type: ManualContentType.important,\n"
     "        ),\n"
     "        // Spec 1 W9e: for everyone, like the check itself (it runs whatever\n"
     "        // healing_ai_insights says).\n"
     "        ManualContent(\n"
     "          id: 'healing_support_first',\n"
     "          title: 'When a reflection sounds very hard',\n"
     "          content:\n"
     "              \"If what you write in your reflection sounds like you may be going through something very hard, Attune doesn't write a relationship reflection or a portrait from it. It shows you a way to reach support instead. Only you see it, and nothing about it is kept. \\\"Need support now?\\\" is always at the end of your reflection.\",\n"
     "          numberPrefix: '2',\n"
     "          type: ManualContentType.text,\n"
     "        ),\n"),
])
```

Run: `python3 -I $D/w9e_client_edits.py`
Expected: seven `edited ...` lines (providers, the journal card, device wipes, the post-mortem, portrait and reflection screens, the manual).

- [ ] **Step 5: Format the new files only, and analyze the touched ones**

```bash
dart format lib/features/healing/presentation/providers/healing_support_providers.dart lib/features/healing/presentation/widgets/healing_support.dart test/features/healing/w9e/support/healing_fakes.dart test/features/healing/w9e/healing_support_test.dart test/features/healing/w9e/healing_account_test.dart
flutter analyze --no-pub lib/features/healing lib/app/device_wipes.dart lib/features/reflection_journal/presentation/widgets/journal_support_card.dart lib/app/documentations/user_manual/data/healing_docs.dart test/features/healing/w9e 2>&1 | grep -E "^\s*(error|warning) " | grep -vE "healing_journey_screen.dart|healing_self_report_sheet.dart"
```

Expected: `Formatted 5 files (0 changed)`; no line (the two warnings left out are today's, in `healing_journey_screen.dart` and `healing_self_report_sheet.dart`, which W9e does not edit; the folder's infos are today's too).

- [ ] **Step 6: Run the tests, write the goldens and look at them**

```bash
flutter test --no-pub --update-goldens test/features/healing/w9e/healing_support_test.dart 2>&1 | tail -1
ls test/features/healing/w9e/goldens/
flutter test --no-pub test/features/healing/w9e/ 2>&1 | tail -1
```

Expected: `+17: All tests passed!`; twelve files: `healing_post_mortem_support`, `healing_portrait_support` and `healing_reflection_support_link`, each `.scale1.0.png`, `.scale1.3.png`, `.scale2.0.png`, `.rtl.png`; `+20: All tests passed!`. Open the twelve: the stage label and title, then the card (W9c's words, "Not now" and "See support" at the end, mirrored in `rtl`); at 2.0 the card fills the stage and continues below the fold (scrollable) above the unchanged "Skip" / "Generate" buttons; the reflection golden shows "Need support now?" with its icon under the last question card, above the bottom buttons.

- [ ] **Step 7: Mutation checks (each must turn a test red)**

Create `$D/mutants_t4.py` with exactly:

```python
# Spec 1 W9e Task 4 mutants: each must turn a W9e widget test red. Run from
# the repo root; name mutants as arguments to run only those. Every file is
# restored afterwards.
import pathlib, re, subprocess, sys
TESTS = ["test/features/healing/w9e/healing_support_test.dart", "test/features/healing/w9e/healing_account_test.dart"]
PROV = "lib/features/healing/presentation/providers/healing_providers.dart"
SUP = "lib/features/healing/presentation/providers/healing_support_providers.dart"
WIDG = "lib/features/healing/presentation/widgets/healing_support.dart"
PM = "lib/features/healing/presentation/screens/healing_post_mortem_screen.dart"
PT = "lib/features/healing/presentation/screens/healing_portrait_screen.dart"
REF = "lib/features/healing/presentation/screens/healing_reflection_screen.dart"
WIPES = "lib/app/device_wipes.dart"
MANUAL = "lib/app/documentations/user_manual/data/healing_docs.dart"

def support_branch(path):
    t = pathlib.Path(path).read_text()
    a = t.index("      if (result != null && result['status'] == 'support_offered') {\n")
    b = t.index("      if (result != null && result['status'] == 'completed') {\n")
    return t[a:b]

MUTANTS = {
    "journey_read_not_watched": [(PROV, "  final account = ref.watch(healingAccountProvider); // Spec 1 W9e (D8)\n",
                                  "  final account = ref.read(healingAccountProvider); // Spec 1 W9e (D8)\n")],
    "no_account_tag_check": [(PROV, "  return journey != null && journey.userId == account ? journey : null;\n", "  return journey;\n")],
    "late_answer_lands": [(PM, "        if (support.account != account) return;\n", "")],
    "support_not_account_scoped": [(SUP, "    account = ref.watch(healingAccountProvider);\n", "    account = ref.read(healingAccountProvider);\n")],
    "no_wipe_entry": [(WIPES, "    id: 'spec1.healing_support_memory',\n", "    id: 'spec1.healing_support_memory_gone',\n")],
    "wipe_not_tracked": [(SUP, "    HealingSupportMemory.track(\n", "    if (false) HealingSupportMemory.track(\n")],
    "post_mortem_saves_on_match": [(PM, support_branch(PM), "")],
    "portrait_saves_on_match": [(PT, support_branch(PT), "")],
    "hidden_text_shown_on_reopen": [(PM, "        !hidden &&\n", "")],
    "not_now_unhides": [(SUP, "        offered: {...state.offered}..remove(key),\n        hidden: state.hidden,\n",
                         "        offered: {...state.offered}..remove(key),\n        hidden: {...state.hidden}..remove(key),\n")],
    "completed_keeps_hidden": [(PM, "        support.completed(_supportKey); // Spec 1 W9e\n", "")],
    "removed_text_reads_as_new": [(PM, "    } else if (widget.journey.postMortemStatus == 'completed' ||\n", "    } else if (")],
    "no_reflection_link": [(REF, "            const HealingNeedSupportLink(),\n", "")],
    "card_counts_as_journal": [(WIDG, "    onSeeSupport: () => openHealingSupport(context),\n", "")],
    "set_state_after_close": [(PM, "        support.offer(_supportKey);\n        _stopAnticipation();\n        if (!mounted) return;\n",
                               "        support.offer(_supportKey);\n        _stopAnticipation();\n")],
    "no_manual_passage": [(MANUAL, "          id: 'healing_support_first',\n", "          id: 'healing_support_first_gone',\n")],
    "card_not_scrollable": [(PM, "              Expanded(\n                child: SingleChildScrollView(\n                  child: HealingSupportCard(",
                             "              Expanded(\n                child: SizedBox(\n                  child: HealingSupportCard(")],
}

def run():
    r = subprocess.run(["flutter", "test", "--no-pub", *TESTS], capture_output=True, text=True)
    m = re.findall(r"\+(\d+)(?: -(\d+))?:", r.stdout)
    p, f = (m[-1] if m else ("?", "?"))
    return f"+{p} -{f or 0} " + ("FAILED" if r.returncode else "passed")

ONLY = set(sys.argv[1:])
if ONLY:
    MUTANTS = {k: v for k, v in MUTANTS.items() if k in ONLY}
originals = {f: pathlib.Path(f).read_text() for f in (PROV, SUP, WIDG, PM, PT, REF, WIPES, MANUAL)}
try:
    for name, edits in MUTANTS.items():
        texts = dict(originals)
        for f, a, b in edits:
            assert texts[f].count(a) == 1, (name, a[:60])
            texts[f] = texts[f].replace(a, b)
        for f, t in texts.items():
            pathlib.Path(f).write_text(t)
        print(name, run(), flush=True)
        for f, t in originals.items():
            pathlib.Path(f).write_text(t)
finally:
    for f, t in originals.items():
        pathlib.Path(f).write_text(t)
print("restored", run())
```

Run: `python3 -I $D/mutants_t4.py`
Expected (each `FAILED`; the counts are passed / failed of the 20 W9e tests):
```
journey_read_not_watched +17 -3 FAILED
no_account_tag_check +19 -1 FAILED
late_answer_lands +19 -1 FAILED
support_not_account_scoped +18 -2 FAILED
no_wipe_entry +19 -1 FAILED
wipe_not_tracked +19 -1 FAILED
post_mortem_saves_on_match +11 -9 FAILED
portrait_saves_on_match +18 -2 FAILED
hidden_text_shown_on_reopen +19 -1 FAILED
not_now_unhides +19 -1 FAILED
completed_keeps_hidden +19 -1 FAILED
removed_text_reads_as_new +18 -2 FAILED
no_reflection_link +18 -2 FAILED
card_counts_as_journal +19 -1 FAILED
set_state_after_close +19 -1 FAILED
no_manual_passage +19 -1 FAILED
card_not_scrollable +18 -2 FAILED
restored +20 -0 passed
```

- [ ] **Step 8: The neighbours of every edited file stay green**

```bash
flutter test --no-pub test/features/reflection_journal/ test/features/healing/ test/features/chat/chat_couples_locked_screen_healing_entry_test.dart test/features/safety/w7/support_hooks_test.dart test/features/couple_profile/w5/couple_profile_data_test.dart test/core/device/ test/app/documentations/ test/core/metrics/metric_counter_test.dart 2>&1 | tail -1
```

Expected: `+188: All tests passed!` (W9c's card tests use `JournalSupportCard` without `onSeeSupport`, so the journal's counted link is unchanged).

- [ ] **Step 9: Amend the spec**

Create `$D/spec_amend.py` with exactly:

```python
# Spec 1 W9e: the spec amendments (tagged "amended W9e"). Each anchor is the
# start of exactly one line; the new line goes right after it, or the
# replacement is made inside it. Run from the repo root.
import pathlib
p = pathlib.Path("docs/superpowers/specs/2026-10-24-app-flow-identity-design.md")
lines = p.read_text().split("\n")

def after(prefix, new):
    hits = [i for i, l in enumerate(lines) if l.startswith(prefix)]
    assert len(hits) == 1, (prefix, len(hits))
    assert new not in lines, ("already applied", new[:60])
    lines.insert(hits[0] + 1, new)

def inside(prefix, old, new):
    hits = [i for i, l in enumerate(lines) if l.startswith(prefix)]
    assert len(hits) == 1, (prefix, len(hits))
    assert lines[hits[0]].count(old) == 1, old
    lines[hits[0]] = lines[hits[0]].replace(old, new)

# 2.5: the flag row.
after("| `journal_ai_insights` | W1c (created), W9c (may switch on) |",
      "| `healing_ai_insights` | W9e | `generate-healing-portrait`, `generate-healing-post-mortem` | no provider call for either stage; status `paused`, **unless the crisis check matches first: `support_offered`** *(amended W9e)* | W9e gate (the W9c clinician gate) |")
# 4.5: the journal's pending list moved; the two Healing functions.
inside("| `analyse-journal-entry` | W1c, W9c | changed |",
       "**Pending corpus:** `analyse-journal-entry/journal_self_harm_pending.ts`,",
       "**Pending corpus:** `_shared/self_harm_pending.ts` (moved there unchanged in W9e and re-exported from `analyse-journal-entry/journal_self_harm_pending.ts`; the fold and the check are `_shared/writer_crisis_check.ts`, shared with Healing *(amended W9e)*),")
after("| `analyse-journal-entry` | W1c, W9c | changed |",
      "| `generate-healing-portrait`, `generate-healing-post-mortem` | W9e | changed | After the caller's own journey is read (RLS), `_shared/healing_ai_gate.ts` runs **first**: `writerTextDiscloses` (the Journal's check: the reviewed corpus and the pending list always, the `[DRAFT]` victimisation list only with `private_safety_check`) on every string in `reflection_answers`. A match, an unreadable reflection, a flag read that throws or a detector that throws answers `{status:'support_offered'}`: no provider call, no saved answer returned, no cache read, nothing about the match stored; the stage's `healing_generation_jobs` rows are deleted and, when the journey holds it, the stage's saved AI text is set to null (status, completed time and the person's own words kept; `{error}` checked, 3 attempts). **Then** `healing_ai_insights` off, unreadable or missing answers `{status:'paused'}` before the saved answer, the cache or any provider. Otherwise as before, with the cache read limited to the caller's own rows. Nothing is counted (no metric key is added). *(amended W9e)* |")
# 4.7: migration 20.
after("| 19 | `opinion_remove_own` | W9b |",
      "| 20 | `healing_ai_insights_flag` | W9e | the `healing_ai_insights` flag row (false) and its production gate row; no new object *(amended W9e)* |")
# 5.1: new files.
after("| `supabase/functions/analyse-journal-entry/journal_handlers.ts`, `journal_self_harm_pending.ts` | W9c |",
      "| `supabase/functions/_shared/writer_crisis_check.ts`, `_shared/self_harm_pending.ts`, `_shared/healing_ai_gate.ts`, `generate-healing-portrait/portrait_handler.ts`, `generate-healing-post-mortem/post_mortem_handler.ts` (+ tests, `_shared/test_support/{fake_supabase,healing_fakes}.ts`) | W9e | the shared writer check and pending list (moved, unchanged); Healing's gate; the two handlers, moved from `index.ts` with the gate first *(amended W9e)* |")
after("| `supabase/functions/analyse-journal-entry/journal_handlers.ts`, `journal_self_harm_pending.ts` | W9c |",
      "| `lib/features/healing/presentation/providers/healing_support_providers.dart`, `lib/features/healing/presentation/widgets/healing_support.dart` | W9e | Healing's account-scoped, in-memory support state (offers, hidden AI text); the card (W9c's) and \"Need support now?\" *(amended W9e)* |")
# 5.2: changed files.
after("| `test/features/reflection_journal/support/journal_test_app.dart` | W9c |",
      "| `lib/features/healing/presentation/providers/healing_providers.dart`, `lib/features/healing/presentation/screens/{healing_post_mortem_screen,healing_portrait_screen,healing_reflection_screen}.dart`, `lib/features/reflection_journal/presentation/widgets/journal_support_card.dart`, `lib/app/device_wipes.dart`, `lib/app/documentations/user_manual/data/healing_docs.dart` | W9e | the account (D8) and the service seam; the card on `support_offered`, nothing saved; the reflection's link; `onSeeSupport` (the journal's default unchanged); `spec1.healing_support_memory`; the passage \"When a reflection sounds very hard\" (no flag) *(amended W9e)* |")
after("| `test/features/reflection_journal/support/journal_test_app.dart` | W9c |",
      "| `supabase/functions/generate-healing-portrait/index.ts`, `generate-healing-post-mortem/index.ts`, `generate-healing-portrait/chapter_scope.test.ts`, `analyse-journal-entry/{journal_handlers,journal_self_harm_pending}.ts`, `supabase/sql/dev_enable_spec1_flags.sql`, `.github/workflows/tests.yml` | W9e | `serve` and the injected deps only; the test reads the moved evidence; the journal calls the shared check; the re-export; the dev line; the CI job runs the W9e Deno tests *(amended W9e)* |")
# 5.8: the wipe entry.
after("| `spec1.journal_support_memory` | W9c |",
      "| `spec1.healing_support_memory` | W9e | sign-out, quick exit | no key: Healing's in-memory support state (offers, hidden AI text) *(amended W9e)* |")
# 7.1, 7.2, 7.4.
after("| `opinion_remove_own_contracts.sql` | W9b |",
      "| `healing_ai_pause_contracts.sql` | W9e | `healing_ai_insights` present and off; its clinician gate row; production refuses it without evidence and lists it when on; clients read flags and never write them; the dev script turns it on *(amended W9e)* |")
after("- `analyse-journal-entry`: with a spy on `callGeminiJson`",
      "- `generate-healing-portrait`, `generate-healing-post-mortem`, `_shared/healing_ai_gate.test.ts`, `_shared/writer_crisis_check.test.ts` (W9e): with a spy on the provider, a crisis reflection never reaches it, the cache or the saved answer, whatever either flag says; no match while paused answers `paused` with nothing read; the stale-output delete is scoped, checked and retried; unreadable answers and a throwing flag read or detector are a match; the victimisation list only with `private_safety_check`; one pending list for the Journal and Healing *(amended W9e)*.")
after("| Remove the `self_disclosure` call or move it after the cache read | Deno spy test |",
      "| Remove Healing's crisis check, move it after the saved answer or the cache, or put the pause first | Healing Deno spy and order tests (W9e) *(amended W9e)* |")
# 8 W9e: as built.
after("- Gate: the same clinician gate as W9c; `healing_ai_insights` may be switched on in production only after it.",
      "- **As built** *(amended W9e)*: migration 20 (`20261104140000` + twin); the check and the pending list are shared with the Journal (`_shared/writer_crisis_check.ts`, `_shared/self_harm_pending.ts`, moved unchanged); on a match the stage's cached jobs and saved AI text go (plan P-5); `paused` keeps the stage's existing client path (recorded `insufficient_evidence`, today's words; plan P-7); the card shows on the post-mortem and portrait screens, held in memory for the signed-in account (`spec1.healing_support_memory`); \"Need support now?\" ends the reflection and the manual passage \"When a reflection sounds very hard\" needs no flag; Healing's journey, start context and readiness reads belong to the signed-in account (D8); nothing is counted. The card, the link and the passage reach production with the function deploy and the build, before this gate; the gate governs only `healing_ai_insights`.")
p.write_text("\n".join(lines))
print("spec amended")
```

Run: `python3 -I $D/spec_amend.py && grep -c "amended W9e" docs/superpowers/specs/2026-10-24-app-flow-identity-design.md`
Expected: `spec amended`, `13`.

- [ ] **Step 10: The W9e gate (regression)**

```bash
D=.superpowers/sdd/2026-11-04-spec1-w9e
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $f"; else echo "FAIL $f"; fi
done > $D/sql-after.txt
echo "PASS $(grep -c ^PASS $D/sql-after.txt) FAIL $(grep -c ^FAIL $D/sql-after.txt)"
comm -13 <(grep ^FAIL $D/sql-baseline.txt) <(grep ^FAIL $D/sql-after.txt)
grep -E "healing_ai_pause|identity_foundation|opinion_|account_deletion" $D/sql-after.txt
(cd supabase/functions && NO_COLOR=1 deno test --allow-read --allow-env --lock=../../.github/deno-w9.lock --frozen _shared/unicode_normaliser.test.ts _shared/writer_crisis_check.test.ts _shared/healing_ai_gate.test.ts analyse-journal-entry/ generate-healing-portrait/ generate-healing-post-mortem/ 2>&1 | grep -E '^(ok|FAILED) \|')
flutter test --no-pub 2>&1 | tail -1; cat $D/flutter-baseline.txt
flutter analyze --no-pub lib test 2>&1 | grep -E '^\s*error ' | diff $D/analyze-baseline.txt - && echo no-new-analyzer-errors
flutter test --no-pub test/architecture/games_untouched_test.dart 2>&1 | tail -1
sed -n '/if (isAuthenticated && !_gateData.isComplete) {/,/_redirectingToOnboarding = false;/p' lib/home/home_screen.dart | shasum | diff - $D/latch.sha && echo latch-unchanged
git status --short lib/features/opinions test/features/opinions lib/features/games ATTUNE_SOUL.md ATTUNE_THESIS.md lib/i10n lib/home
git status --short
```

Expected: one more PASS than the baseline (`healing_ai_pause_contracts.sql`) and the same FAILs; no line from `comm` (no new FAIL); `PASS` for `healing_ai_pause_contracts.sql`, `identity_foundation_contracts.sql`, the four `opinion_*` contracts and `account_deletion_contracts.sql`; `ok | 80 passed | 0 failed`; `All tests passed!` with the baseline count plus 20; `no-new-analyzer-errors`; `All tests passed!`; `latch-unchanged`; no line from the scoped status; the full status lists exactly the owner's two entries plus the files in this plan's file map (and the twelve goldens).

## Owner deploy checklist (the plan never runs any of this)

1. **Order and release note.** W9 is deployed first (its checklist). Then: `supabase db push` (migration 20: `20261104140000`, `…140010`); deploy `generate-healing-portrait`, `generate-healing-post-mortem` **and `analyse-journal-entry`** (it now imports the shared check and the moved list: deploy it with the other two so the three run the same check); ship the Task 4 build. On the development project re-run `supabase/sql/dev_enable_spec1_flags.sql` (it now also turns `healing_ai_insights` on).
   - **What changes at once (P-14).** Healing's AI stops in production (`healing_ai_insights` is off) until item 2: the post-mortem and portrait stages answer `paused` and record "not enough information" (P-7). The crisis check, the card, "Need support now?" at the end of the reflection and the manual passage are live at once, whatever the flag says.
   - **Old builds (P-13).** A build from before W9e shows "No portrait available yet" / "There is not enough information..." for both new answers and no card. Ship the build with the deploy, or say so in the release note.
2. **The W9e gate, the same as W9c's: the clinician before `healing_ai_insights` goes on in production.**
   - **The words.** The couples clinician and the suicide-prevention reviewer confirm the W9c card's words for Healing ("If things feel heavy right now, you don't have to carry it alone. Support is here if you want it.", "See support", "Not now"), sign the manual passage "When a reflection sounds very hard" and confirm that the reviewed self-harm corpus and the pending list (52 phrases, 4 patterns, now `supabase/functions/_shared/self_harm_pending.ts`, `journal_self_harm_pending-0.3.0`) also guard Healing. **Timing: before item 1's deploy.** The card, "Need support now?" and the passage ship live with the deploy while `healing_ai_insights` is still off, so their words reach people before this gate: the clinician signs them before the deploy (going out unsigned is only by the owner's explicit, recorded acceptance, as for W9c). The gate below then governs only the switch-on.
   - **Breakup-specific phrasings (new for Healing).** The clinician rules whether phrasings that are common after a breakup belong in the pending list (for example "I can't live without him", "I can't live without her", "there's no point without them", "I don't want to wake up"); none is added by this plan. A false positive only shows the card.
   - **Then**, in production: `select public.record_flag_gate_evidence('healing_ai_insights', '<ref>');` and switch it on.
3. **One-off backfill (owner question 2), after item 1's deploy and before the switch-on.** AI text written before W9e for a reflection that matches today stays on the person's screen (P-5 clears it only when the function is called again, which the app does not do for a completed stage). Save the script below as `supabase/functions/_operator/healing_w9e_backfill.ts` (never committed; delete it afterwards) and run it from the repo root in the owner's own shell, with the project's URL and service-role key exported (never written to a file in the repo): first `deno run --allow-env --allow-net --allow-read supabase/functions/_operator/healing_w9e_backfill.ts` (dry run: "journeys read: N; matching today: M"), then the same with `--apply` ("cleared: M; failed: 0"; re-run to retry a failure). Run it on development first and check one known crisis journey: `select count(*) from public.healing_generation_jobs where journey_id = '<that journey>';` → `0`, and its `portrait_text` and `post_mortem_observation` are null. (Checked while writing: `deno check` and `deno lint` pass.)

   ```ts
// One-off W9e backfill; operator only, never committed (delete it after).
// Removes Healing's AI output from every journey whose reflection the W9e
// check matches today, with the functions' own pieces: the same text
// (reflectionTextOf), the same check (writerTextDiscloses: fold, both
// invisible-character passes, the reviewed corpus and the pending list,
// victimisation only with private_safety_check on), the same deletes
// (every cached job for the journey and caller; the saved AI text of both
// stages). Prints counts only, never text or ids.
//   deno run --allow-env --allow-net --allow-read supabase/functions/_operator/healing_w9e_backfill.ts [--apply]
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { DRAFT_SAFETY_CONTENT_FLAG, featureFlagEnabled } from "../_shared/feature_flag.ts";
import { reflectionTextOf } from "../_shared/healing_ai_gate.ts";
import { writerTextDiscloses } from "../_shared/writer_crisis_check.ts";

const apply = Deno.args.includes("--apply");
const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const victimisation = await featureFlagEnabled(admin, DRAFT_SAFETY_CONTENT_FLAG);

const SAVED = {
  post_mortem_observation: null,
  post_mortem_confidence: null,
  post_mortem_reflection_prompt: null,
  portrait_text: null,
  portrait_prompt: null,
};

let read = 0, matched = 0, cleared = 0, failed = 0;
const PAGE = 500;
for (let from = 0;; from += PAGE) {
  const { data, error } = await admin
    .from("healing_journeys")
    .select("id, user_id, reflection_answers")
    .order("id")
    .range(from, from + PAGE - 1);
  if (error) throw new Error("journeys_unreadable");
  if (!data || data.length === 0) break;
  for (const j of data) {
    read++;
    const text = reflectionTextOf(j.reflection_answers);
    if (text !== null && !writerTextDiscloses(text, victimisation)) continue;
    matched++;
    if (!apply) continue;
    const jobs = await admin.from("healing_generation_jobs").delete().eq("journey_id", j.id).eq("user_id", j.user_id);
    const row = await admin.from("healing_journeys").update(SAVED).eq("id", j.id).eq("user_id", j.user_id);
    if (jobs.error || row.error) failed++;
    else cleared++;
  }
  if (data.length < PAGE) break;
}
console.log(
  apply
    ? `journeys read: ${read}; matching today: ${matched}; cleared: ${cleared}; failed: ${failed}`
    : `journeys read: ${read}; matching today: ${matched} (dry run; --apply clears them)`,
);
   ```

4. **Device checks on development (flag on).** Write a crisis phrase in the Healing reflection (stage 1), complete it, then on stage 2 tap "Generate reflection": the card, no reflection; `select post_mortem_status from public.healing_journeys where id = '<journey>';` is still `not_started` and `select count(*) from public.healing_generation_jobs where journey_id = '<journey>';` is `0`. "Not now" puts it away; "Generate reflection" again brings it back; "See support" opens Support. Leave the stage while it is generating and come back: the card is there. Large text at the largest system size: the card scrolls and "See support" is reachable. Right-to-left: the card mirrors. "Need support now?" at the end of the reflection opens Support with the flag off too. With `healing_ai_insights` off and an ordinary reflection: "There is not enough information for a grounded reflection yet." and "Continue". **Shared phone:** sign out and in as another account on the same phone, also on a slow network: never the first account's journey or card on Healing, also while the second account's first read is out or after it fails. Quick exit (iOS included) then return: no card. **Screen readers:** TalkBack reads the card when it arrives (live region); with VoiceOver, check it is noticed (VoiceOver ignores `liveRegion`; if it is not, announce `journal_supportCardBody` once when an offer is added: a developer change, as W9 M-7).
   - **Batch-3 carries (shared phone and overlap).** Two accounts that share an ended relationship on one phone: the second account's "Start journey" starts its own journey (not the first account's), and Conversations / Me "Healing" opens the sheet or the journey by the second account's answer, also while that answer is slow. Start "Generate reflection", go back while it runs, come in again and generate again with a crisis reflection: the card stays even when the first request's answer lands later, and no reflection appears or is saved.
5. **Owner decisions to confirm:** questions 1-3 above (4 is resolved).
6. **Carried:** the Spec 8 carry now moves the reviewed pending phrases from one file (`_shared/self_harm_pending.ts`) into the shared corpus for the Journal and Healing together.
7. **Deferred minors (ledger "Final: minor"; none blocks the deploy).**
   - **B2 M-1.** The post-mortem's service-role `patterns` read is scoped by the caller's own journey's `relationship_id` only (the table has no `user_id`): no cross-account path, but for old endings it skips Spec 3b's chapter gate (Spec 3a D.4(a)). Add a membership check before the live fallback, or record the acceptance beside the read.
   - **B2 M-2.** A generation that passed the gate is not re-checked before it saves its job or answers: a crisis reflection saved while it is out can sit beside its AI text until the next call. Batch 3 closes the app side for a newer `support_offered` (an older answer is never shown or saved); a server re-check after the provider returns is still open.
   - **B2 M-3.** The saved-text blanking is decided from the journey read before the gate; text saved in between is not cleared. Make the update conditional in SQL.
   - **B2 M-4, M-5.** Two Deno test gaps: `saved` with only the prompt column set, and the post-mortem's snapshot-first read order (two probe mutants survive).
   - **B2 note (spec gap).** `portrait_reflection` and reflection edits made after a stage completed are not re-checked; the backfill (item 3) covers what exists at deploy.
   - **No Healing metrics** (owner question 3): `support_card_shown:healing` / `support_link_opened:healing` wait for a wave that also updates W1b's seed tests.
   - **VoiceOver** ignores `liveRegion` (item 4): if the card is not announced, announce `journal_supportCardBody` once per new offer (as W9 M-7).
   - **Final M-1 (pre-existing).** Leaving a stage while it generates loses a `completed` or `paused` answer (`setState`/`ref` after the screen closes). Not made worse by W9e; fix with a `mounted` guard and a provider-held result.
   - **Final M-2, M-3.** The account check reads a field that can go stale when no screen listens (same pattern as the Journal, no visible effect); a support answer landing after quick exit brings the card back for the same account.

## Spec coverage (self-review)

| Spec item | Where |
|---|---|
| §8 W9e: `healing_ai_insights` flag row (false) | Task 1 (migration 20; contract A; mutants `flag_inserted_on`, `no_flag_row`) |
| §8 W9e: its §2.5 row and production gate row | Task 1 (gate row; contract B, C; mutants `no_gate_row`, `wrong_gate`); Task 4 Step 9 (§2.5 row) |
| §8 W9e: `detectSelfDisclosure` first in both functions, W9c's pattern | Tasks 2-3 (`writerTextDiscloses` is the journal's check; `healingGate` first; order mutants `pause_first`, `*_gate_after_saved`, `*_gate_after_cache`, `*_no_gate`) |
| §8 W9e: no provider call and nothing persisted on a match | Task 3 (spy tests; no upsert, no RPC; P-5 removes stale output; mutants `no_stale_delete`, `delete_*`, `saved_text_kept`) |
| §8 W9e: the Healing screens' support card | Task 4 (card on both stages; nothing saved; mutants `*_saves_on_match`) |
| §8 W9e tests: Deno spy and order tests for both functions; widget tests | Task 3 (26 Deno tests), Task 4 (20 widget tests, 12 goldens) |
| §8 W9e gate: the same clinician gate as W9c | Task 1 (gate row text); owner checklist 2 |
| O2: off in production, a production gate row, checked before any provider call, `self_disclosure` first, the same writer card, the same clinician gate | Tasks 1-4; P-2, P-4 |
| §2.2 (no animation), §2.3 (large text, contrast, labels, 48 dp, RTL, goldens) | Task 4 (`the card is a plain widget...`, guidelines at 1.0 and 2.0, goldens at four variants; Review Focus 2) |
| §5.8 / D8 (shared phones) | Task 4 (`spec1.healing_support_memory`; account tests held frame by frame; mutants `support_not_account_scoped`, `late_answer_lands`, `journey_read_not_watched`, `no_account_tag_check`, `no_wipe_entry`, `wipe_not_tracked`) |
| W9 B7/B8 rulings (detector first, fail closed, stale delete, fold, shared pending list, caller scope, D8, ungated support, mutants) | Global Constraints; Tasks 2-4 |
| §7.1, §7.2, §7.4 | Task 1 contract; Tasks 2-3 Deno tests; mutants in every task; Task 4 Step 9 amendments |

Placeholder scan: no "TBD", "TODO", "later" (as an instruction) or "similar to"; every code step has its full text or a script that writes it from today's file with asserted anchors; `<ref>`, `<journey>` and `<that journey>` in the owner checklist are values only the owner has. Type consistency: `HEALING_AI_FLAG`, `HealingDeps` (`model`, `aiPaused`, `victimisationOn`), `HealingModel`, `HealingStage`, `healingGate`, `reflectionTextOf`, `writerTextDiscloses`, `foldTypography`, `matchesPendingSelfHarm`, `JOURNAL_SELF_HARM_PENDING`, `handlePortrait`, `handlePostMortem`, `healingAccountProvider`, `healingGenerationServiceProvider`, `HealingAiStage`, `HealingSupportKey`, `HealingSupportState`, `HealingSupport` (`offer`, `notNow`, `completed`), `healingSupportProvider`, `HealingSupportMemory`, `HealingSupportCard`, `HealingNeedSupportLink`, `openHealingSupport`, `JournalSupportCard.onSeeSupport` are used as defined (each file was compiled, type-checked or run while writing this plan).
