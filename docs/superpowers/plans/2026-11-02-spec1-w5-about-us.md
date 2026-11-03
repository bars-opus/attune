# Spec 1 W5 (About us: the shared couple profile) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a couple one shared, attributed, quiet About us profile: migration 10 (`couple_profiles`, `couple_profile_drafts`, `get_couple_profile`, `update_couple_profile`, the draft RPCs, `adopt_couple_profile_drafts`, `sync_anniversary_reminder`, the together signal, and `accept_relationship_invite_v2`, `set_user_path_internal`, `export_relationship` and `export_bundle` re-created from their live bodies with only W5's lines), and, behind `couple_profile`, AU1-AU6 one question per screen, the About us screen with its "Changed by {name} - {date}" lines, R3's draft card, Settings -> Your relationship -> About us, Together's "Start with" rows (the anniversary as AU6, the single source of the anniversary reminder), the anniversary reminder's "This reminder follows About us" sheet, offline answers queued per account, `MyDateFormat.toMonthYear` / `toYear`, and the manual topic. Never a type, a score or a label: a contract and an architecture test pin that.

**Architecture:** Two halves, five tasks. **Server (Tasks 1-2):** Task 1 is `20261102110000_couple_profiles.sql` and its twin: both tables under RLS, one validating merge (`private.couple_profile_merge`) shared by the profile and the draft, the read/write RPCs with per-field attribution (a first name or "me", never an id), the anniversary reminder kept as one `reminders` row and guarded against client edits (P-6), and the together signal; proven by `couple_profile_contracts.sql` sections A-F with eight mutants. Task 2 is `20261102110100_couple_profiles_links.sql` and its twin: the four existing functions re-created from their live bodies (a body diff proves only W5's lines were added; W4's whole accept hardening stays and `invite_v2_contracts.sql` stays green), the identity contract's I-6 scan narrowed to excuse exactly W5's one statement, and contract sections F (Dating), G (adoption), H, I (export) with five mutants. **Phone (Tasks 3-5):** Task 3 is the data layer (the `couple_profile` flag effective under `flow_couples_v2`, the model, the service, the per-account offline outbox replayed by `OnboardingSyncService`, the sign-out wipe, the date formats, the never-typed architecture test). Task 4 is the copy and AU1-AU6 (`AboutUsQuestionFlow`). Task 5 is the About us screen and every entry point (R3, Settings, Together, the reminder sheet, the route, the manual), then the W5 gate. Every SQL, Dart and Deno block below was run while writing this plan: the SQL on a scratch Postgres 17 restored from `attune_spec3a`'s dump (each migration applied twice; each contract red before and green after; each mutant red with the message quoted; the full contract suite showing no new FAIL against the baseline), the Dart in a scratch copy of the tree (each new test red before its code, green after; goldens generated; the whole suite), the Deno `accept-invite` tests against the re-created accept.

**Tech Stack:** Flutter 3.29.1 (Dart 3.7), Riverpod 2.6, GoRouter, Supabase Postgres 17 (RLS, `SECURITY DEFINER` with `search_path = ''`), Deno 2 (`accept-invite` tests only), psql, Python 3 (edit and check scripts). No new package.

**Spec:** `docs/superpowers/specs/2026-10-24-app-flow-identity-design.md` — §1.3 (Q8), §1.4 (D2, D16, D19, D20), §1.5, §2 (copy, motion, §2.3 accessibility, §2.5 `couple_profile` and its dependencies), §3.8 About us (AU1-AU6, the screen, validation, read-only, errors), R3 and R4, §3.12, §3.14, §4.2 `couple_profiles` and `couple_profile_drafts`, §4.3 W5, §4.4 `couple_profiles_together_signal`, §4.7 #10, §4.8, §5.1-§5.8 rows tagged W5, §7.1 `couple_profile_contracts.sql` and "Never a type or score", §7.3, §7.4 (the I-6 and never-typed mutants), §8 W5 and its gate, §9, §11. Format reference: `docs/superpowers/plans/2026-11-02-spec1-w4-invites.md`.

## Global Constraints

- Work in the main working tree on `main` (`/Users/user/attune`). W1 (360db8d1), W2 (8b3477ad), W3 (c211b262) and W4 (6b8fc7ed) are committed; the owner may have uncommitted edits: never revert, stash, stage, checkout or reformat them. Every edit below is an exact-string replacement; if the text to replace has moved because a later fix changed it, apply the same change to the current text and say so in the task report.
- **NO commits.** No `git add`, `git commit`, `git stash`, `git checkout`, `git reset`, `git rm`. Tasks end with "Run tests", not "Commit".
- Never `dart format` a pre-existing file (the repo predates the 3.7 formatter). Format only the files this plan creates, by path (Task 5, Step 12 lists them).
- **SQL:** contracts run only on the local scratch database `attune_spec3a`, only as `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f <file>`, inside the file's own `BEGIN … ROLLBACK`. Confirm the target first (`psql -X -d attune_spec3a -Atc 'select current_database()'` prints `attune_spec3a`). NEVER `attune_test`. NEVER run `scripts/local_pg_setup.sh` or `scripts/local_pg_grants.sql`; Tasks 1 and 2 **edit** `scripts/local_pg_grants.sql` and never run it.
- **Migrations:** `20261102110000_couple_profiles.sql` + `20261102110010_couple_profiles_grants.sql` (Task 1), `20261102110100_couple_profiles_links.sql` + `20261102110110_couple_profiles_links_grants.sql` (Task 2), later than every migration in the tree (the newest is W4's `20261102100010_accept_invite_v2_grants.sql`). If `ls supabase/migrations | sort | tail -1` shows anything at or after `20261102110000` when Task 1 starts, shift all four to the next free hour, keeping their order, and change every header, `\i` line and command below to match. Each file is one `BEGIN; … COMMIT;`, idempotent (applied twice, `exit=0` both times), `SET LOCAL lock_timeout = '5s'`, every `SECURITY DEFINER` function has `SET search_path = ''` and schema-qualifies every name, server-only objects are revoked inside the migration itself and again in the twin, grants are explicit, nothing reaches `anon`; `authenticated` gets SELECT on both tables (under RLS) and EXECUTE on the four RPCs only; `service_role` gets DML on both new public tables. No `CREATE INDEX CONCURRENTLY`.
- **Re-created functions** (`accept_relationship_invite_v2`, `set_user_path_internal`, `export_relationship`, `export_bundle`) start from their live latest bodies (`20261102100000`, `20261025100300`, `20261024100700`, `20261018120000`; found with `grep -l` and checked identical to `pg_get_functiondef` on the scratch database) and add only W5's lines; Task 2, Step 6 diffs every body. The accept keeps the exact `CREATE OR REPLACE FUNCTION public.accept_relationship_invite_v2(` … `AS $$` text form (the Deno refusal-code test parses the newest migration that defines it) and all of W4's hardening: the inviter-relationship and hold checks, the uniform `invite:invalid`, the acceptor's `account:hold`, both users rows locked lowest id first and then the pending row, the acceptance read once after that lock, both people's other pending invites removed on link, D8. It gains one `PERFORM` and raises nothing new. Every existing `invite_v2_contracts.sql` assertion, its `prosrc` lock-order pins included, stays green.
- **Flags:** W5 adds no flag. `couple_profile` exists (W1c, inserted false, with its W5 production gate row in `private.flag_production_gates`) and needs `flow_couples_v2`, which needs `flow_paths_v2`, which needs `flow_signin_v2` (§2.5); `supabase/sql/dev_enable_spec1_flags.sql` already turns it on in development and is not edited. Every W5 screen and entry point reads `coupleProfileEnabledProvider` (Task 3); the server functions are unflagged (nothing calls them while the flag is off, and the draft adoption is a no-op without drafts).
- **Never touch:** `lib/features/games/**`, `ChatScreen`'s Games entry points, `UniversalBubble` / `ChatTextField` parameters, `lib/features/auth/utility/auth_exports.dart`, every Games route in `app_router.dart` (`test/architecture/games_untouched_test.dart` stays green), `lib/features/opinions/**` (Opinions stays as it is), `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`, every applied migration, `supabase/sql/dev_enable_spec1_flags.sql`, the legacy `OnboardingGate`. Existing SQL contracts are not edited except the one line Task 2 narrows in `identity_foundation_contracts.sql` (P-10). HomeScreen's latch block (from `if (isAuthenticated && !_gateData.isComplete) {` to `_redirectingToOnboarding = false;`) stays byte-identical (Task 1 saves it, every gate diffs it); Task 3 changes only the `_syncService` initializer and one import, outside it.
- **Permanent product constraints:** never a couple "type", score or partner scorecard; no couple report combining both people's insights (About us reads and writes no insight; no AI path reads it: Task 3's architecture test); attribution shows a first name (or "you" / "your partner"), never a raw id (contract section D, the export's `'me'` / `'partner'`); safety notifications go to the at-risk person only (W5 sends no push at all); quick exit works everywhere (the app shell's `QuickExitZone` sits above every route and sheet W5 adds; W5 registers no quick-exit wipe and touches no protective key).
- **Shared phones (D8, D20):** nobody's draft, name or date of birth reaches another account. The draft is per account on the server (`couple_profile_drafts.user_id`, RLS own-row, every RPC keyed on `auth.uid()`); the offline queue is per account on the phone (`attune.flow.<uid>.about_us_outbox`) and wiped at sign-out for every account (`spec1.about_us_outbox`); the profile itself is never cached on the phone. No key or value names Dating.
- **Names:** the couple as a unit is `coupleNameProvider` (the chat name); About us's title is that name, else "About us" (§3.8; P-15); nothing says "both of you". Questions addressed to one partner keep "you two" (D16).
- **Dates** shown to people use `MyDateFormat` only (`toDate`, `toDateShort`, and W5's `toMonthYear`, `toYear`, `toMonth`), a date and its detail joined with `MyDateFormat.join` (`' - '`, D2). "Together since" is never an elapsed counter.
- **Copy:** every new string is an English `aboutUs_*` key appended to `lib/i10n/app_en.arb` by W3's `.superpowers/sdd/2026-10-26-spec1-w3/arb_append.py` and generated with `flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package`; other locales fall back to English. The fragment is written by a script that turns the marker `@@ENDASH@@` into the JSON escape for U+2013 (a backslash, `u2013`), checked with `grep -cP '[^\x00-\x7F]'` (prints `0`) and `grep -c 'u2013'` (prints `3`). Dart sources stay ASCII outside comments (tests build U+2013 and U+00B7 with `String.fromCharCode`).
- **UI:** Material 3 from the app theme and W2's flow widgets (`FlowFrame` wraps `AllowLargeText`; `FlowPrimaryButton`, `FlowSecondaryButton`, `FlowTextLink`, `FlowTextField`, `FlowErrorLine`); every control labelled, targets at least 48 dp, text contrast at least 4.5:1, errors announced and shown with an icon, goldens at 1.0, 1.3, 2.0 and right to left (`expectFlowGoldens`), `androidTapTargetGuideline`, `labeledTapTargetGuideline` and `textContrastGuideline` (`expectFlowGuidelines`) on every new screen. Steps use `SharedAxisStep` (reduce motion: the 150 ms fade); selection is the 150 ms `kSelectionDuration` with a selection haptic; nothing else animates.
- **No deploys.** `supabase db push`, dashboard and store work are the owner's ("Owner deploy checklist"). Don't read `.env*`, credentials or the keychain. No new package; no `flutter pub get`.
- **Regression gate at the end of the server half (Task 2) and of the wave (Task 5):** every SQL contract on `attune_spec3a` shows no new FAIL against the Task 1 baseline and `couple_profile_contracts.sql`, `invite_v2_contracts.sql`, `identity_foundation_contracts.sql`, `data_export_contracts.sql` and `story_export_contracts.sql` are PASS; `deno test --allow-read accept-invite/` passes (Task 2); the full `flutter test` passes; `flutter analyze --no-pub lib test` shows no `error` line that the Task 1 baseline didn't; the Games test passes; no Opinions, Games or `auth_exports.dart` change; the latch is unchanged (Task 5).

## Review Focus

1. **Both partners edit About us at about the same time, or one of them offline.** Expect the last write to win field by field, the line under each field to name whoever wrote it last, and no other field's answer or attribution to move. Tests: Task 1 contract section D (`an edit of one field re-attributed another`, mutant `attribution`), Task 3 `couple_profile_data_test.dart` (`queues per account and target, the last write winning`, `an answer queued while a replay runs is kept`).
2. **A shared phone: Kofi answers About us while his invite waits, signs out, and Ama signs in on the same phone.** Ama must never see or send Kofi's answers. Tests: Task 1 contract section F (`another account read Kofi's draft through the RPC`, `another account selected Kofi's draft row`), Task 3 (`queues per account …` "another account on the phone sees nothing", `wiped at sign-out for every account, never on quick exit`).
3. **The anniversary reminder is edited or deleted from Together's ordinary reminder sheet, or by an older app build.** Expect About us to stay the single source: the server refuses the change (`reminder:follows_about_us`), the app opens "This reminder follows About us" instead of the form, and lead times stay editable. Tests: Task 1 section E (`the app deleted the About us reminder`, `the app moved the About us reminder`, `the couple's lead times were refused`, mutant `guard`), Task 5 `about_us_entry_test.dart` (`the anniversary reminder follows About us; others open as before`).
4. **A paused couple, a couple inside the ending window, one partner sealed, an archived chapter.** Expect reading while the space is readable (with "You can read this until {date}."), never writing, and nothing at all once sealed, archived or past the window. Tests: Task 1 section B (each state by its message, mutant `read_only`), Task 5 `about_us_screen_test.dart` (`read-only: its end date, and no row opens a question`).
5. **Dates at the edges: 30 February, 29 February in a non-leap year, today in UTC+14 (tomorrow in UTC), a month-only date chosen for the anniversary.** Expect real dates only, today never refused, the future refused on both sides, and the anniversary to ask "What day was it?" instead of failing. Tests: Task 1 section C (`2023-02-30`, `2001-02-29`, `current_date + 1` accepted, `+ 2` refused, `anniversary_needs_day`), Task 4 `about_us_flow_test.dart` (`a future date is refused on the phone, and said`, the AU6 day prompt in `AU1-AU6 in order …`).

## Decisions found while verifying the code (read before Task 1)

Each is a verified fact about today's code (HEAD 6b8fc7ed) or the database, with the smallest change that keeps the spec's intent. *Changes spec intent* marks the ones the owner should see.

- **P-1 (two migrations).** Spec §4.7 #10 is one migration. It is built as two, each with its twin, so the server half reviews in two tasks: `20261102110000_couple_profiles` (tables, RPCs, merge, anniversary sync, guard, signal) and `20261102110100_couple_profiles_links` (the four re-created functions). Same objects, same order of dependence.
- **P-2 (the patch and the refusals).** `p_patch` is a JSON object with only the answered question's keys: `together_since` + `together_since_precision` (together), `stage` (+ `stage_words`), `ceremonies`, `living`, `children` (+ `child_age_bands`), `anniversary_source`. Beyond the spec's three codes (`couple_profile:read_only`, `:unknown_key`, `:anniversary_needs_day`, plus `:not_found`), the merge raises `:invalid`, `:future_date`, `:too_many_ceremonies`, `:ceremonies_need_married`, `:bands_need_yes`, and the draft RPCs `:not_relationship`. One function, `private.couple_profile_merge`, validates and normalises for both the profile and the draft.
- **P-3 (future dates).** The server refuses a date after UTC today + 1 day (the earliest time zone's today is UTC tomorrow); the phone refuses anything after its own local today. Neither refuses today.
- **P-4 (what `get_couple_profile` returns).** The spec's values, per-field `changed_by_me` / `changed_by_first_name` / `changed_at` (a field nobody answered has no entry; the first name comes from W4's `private.invite_first_name`, never a phone number) and `read_only`, plus `draft` (false), `read_until` (paused: `paused_at` + 30 days, the automatic end; ended: `ended_at` + 30 days) for "You can read this until {date}.", and `anniversary_reminder_id` (a reminder's id, never a person's) so Together's sheet can tell its reminder. No `suggested_dates` (review I-12).
- **P-5 (the anniversary reminder's time).** §4.3 says "next occurrence at 09:00 in the editor's zone". The repo's reminders store the civil date as midnight UTC and `generate_reminder_notifications` tells **each partner at 09:00 in their own zone** (`20261015100000`). `sync_anniversary_reminder` therefore writes the next occurrence's civil date at midnight UTC, `recurrence 'yearly'`, title "Anniversary", `created_by` the person who chose it; both partners hear at their own 09:00. *Changes spec intent* (owner question 1).
- **P-6 (the reminder follows About us).** A client could edit or delete the About us reminder through the existing `reminders` RLS, leaving About us pointing at a reminder that says something else. A new invoker trigger, `reminders_guard_about_us` (`private.guard_about_us_reminder`), refuses a direct client (`authenticated` / `anon`) delete or change of that row's type, title, date, recurrence, relationship or maker with `reminder:follows_about_us` (definer functions and the service role pass, as W1a's profiles guard does); lead times and the note stay the couple's. The app shows its sheet instead of the form (Task 5). The trigger function reads `couple_profiles`, so it joins the never-typed allow-list. *Changes spec intent* (an object the spec doesn't list; owner question 2).
- **P-7 (dependent answers).** Leaving Married clears the ceremonies, attributed to the person who left it (spec). A ceremony that disappears takes an anniversary on it to `off`, attributed the same way. A change that would leave the anniversary on a date without a day (the date made month-only or cleared) is refused with `couple_profile:anniversary_needs_day`, so nobody silently loses the other partner's reminder.
- **P-8 (adoption at linking).** "The inviter's draft first, the acceptor's fills empty fields": a field is filled from the acceptor's draft only when the inviter's has no value for it (for the anniversary: when the inviter never answered it, "No, thanks" counting as an answer). Each field keeps its owner and that draft's `set_at`. A merged dependent field that no longer holds is dropped, never refused: ceremonies unless the merged stage is Married, an anniversary whose date has no day (then `off`, attributed to nobody). Both drafts go; the reminder is made. No drafts: no profile row.
- **P-9 (drafts and paths).** The draft RPCs need the Relationship path (`couple_profile:not_relationship`). The draft write reads the caller's users row `FOR SHARE` first (users, then the draft: the order `set_user_path_internal` and the accept use), so a switch to Dating can't leave a draft behind. A switch to Just for me keeps the draft (unreadable until Relationship again); a switch to Dating deletes it (I-6). A withdrawal keeps it.
- **P-10 (the identity contract's I-6 scan).** `identity_foundation_contracts.sql` scans the live `set_user_path_internal` for later waves' tables, so W5's spec-required re-creation turns it red (`a W1 function names a later wave's table (I-6): set_user_path_internal(uuid,text)`, verified). Task 2 narrows that one expression to set aside exactly W5's statement (`DELETE FROM public.couple_profile_drafts AS d WHERE d.user_id = p_user;`); any other later-wave name still fails (mutant `identity_extra`). The §7.4 mutant "re-add the delete to the W1 body" can only be caught on the file now, so Task 3's architecture test reads W1's migration body.
- **P-11 (the export's tests).** §8 says `data_export_contracts.sql` is "updated for about_us". The `about_us` section and the three new settings are asserted in `couple_profile_contracts.sql` section I instead (values, `'me'` / `'partner'`, no uuid, the old settings kept), and `data_export_contracts.sql` and `story_export_contracts.sql` stay byte-identical and green.
- **P-12 (the flag on the phone).** `couple_profile` joins the two signed-in flags W3 reads: `SignedInFlowFlags.coupleProfile` (default false, so every existing constructor keeps working), the same one `feature_flags` read, the same cache (a `couple_profile: true` key written only while it is on, so the W3 cache shape and `flow_flags_test.dart` stay unchanged; an absent key reads as off). `coupleProfileEnabledProvider` (in `flow_flags.dart`) is `couple_profile && flowCouplesV2Provider` (§5.3).
- **P-13 (routes).** `/about-us/:relationshipId` (`RouteNames.aboutUs`), with `draft` for the draft (`aboutUsLocation(String?)`); `extra` carries R1's partner first name for the draft's "More about this". Signed-in only; with `couple_profile` off (or unreadable) it goes home, as W4's `/join-invite` does. A row edit, Together's "Add your anniversary" and the reminder sheet push one question (`openAboutUsQuestion`) over the current screen.
- **P-14 (copy the spec doesn't give).** R3's card ("A few easy questions about you two. Skip any of them. {name} sees your answers when they join.", saying plainly that the draft is shared at linking), "More about this" (the footer line, and for a draft "Before {name} joins, your answers are a draft only you can see. When {name} joins, they become your shared About us."), "Not answered yet", "Answer a few questions", "Check the day and month.", "Choose a year.", "Your anniversary reminder needs the full date. Add the day, or turn the reminder off first.", "About us can't be changed right now.", "Saved on this phone. It will be shared when you're back online.", "We couldn't load About us. Check your connection and try again.", the Settings subtitle, AU6's "Ceremony, {year}" for an unlabelled ceremony, the step dots read as "Question 2 of 5", and the manual topic. A refused write otherwise reuses W3's `flow_saveFailed` ("We couldn't save that. Try again.", the spec's words). Owner question 3.
- **P-15 (the title).** §3.8: "title `coupleLabel(name)`, falling back to 'About us'". `coupleLabel` falls back to "Couples"; the screen shows the chat name when there is one and "About us" otherwise, as the spec's fallback says.
- **P-16 (date words).** "Together since" shows a day as `MyDateFormat.toDate` ("Monday, October 14, 2024"), a month as `toMonthYear` ("October 2024"), a year as `toYear`; ceremonies as "Customary, 1999" (`toYear`). W5 also adds `MyDateFormat.toMonth` ("October") for the month pickers, so no screen invents a pattern.
- **P-17 (offline).** An answer the server didn't receive (offline, a timeout, a non-refusal server error) is queued per account and target in `attune.flow.<uid>.about_us_outbox` (the last write wins key by key), shown at once with "Saved on this phone. It will be shared when you're back online.", and replayed (attributed then, as §3.8 says) when About us next opens and on every `OnboardingSyncService.flush` (launch, resume, sign-in: HomeScreen passes `aboutUsOutboxFlushProvider`). A refusal at replay drops the answer (it can't succeed); five failed replays drop it. Sign-out wipes it for every account; quick exit leaves it (it shows nothing, and losing an answer would surprise). Owner question 4.
- **P-18 (Together).** As §3.8 and §5.2 say: the "Start with" rows (shown to a couple whose Together is still empty) gain "About us", and "Add your anniversary" opens AU6 while `couple_profile` is on (the reminder form while it is off). The populated Together screen gains nothing; Settings is the way back in.
- **P-19 (AU6's options).** "No, thanks", "The day you got together" only when AU2 has an answer, and one "{Label} ceremony, {year}" per ceremony. A source without a full date asks "What day was it?" (day, and the month when it isn't known) and saves the completed date and the source in one write.
- **P-20 (one-question edits).** A row on the About us screen, Together's anniversary row and the reminder sheet ask just that question: its button says "Save", there are no step dots and no Skip; Back closes it.
- **P-21 (Settings).** One row, "About us", first in Settings -> Your relationship: the shared profile when linked, paused or in the ending window, the draft while an invite is pending, nothing otherwise.
- **P-22 (fixtures).** The contract uses ids `5c0f0000-0000-0000-0000-0000000000NN` (relationships `…0001NN`) and phones `+15558300NN` (§7.1's `83xx` range), on `auth.users` and `public.users`.

## Owner questions (open; the plan builds the recommendation)

1. **The anniversary reminder reaches each partner at 09:00 in their own zone (P-5), not at 09:00 in the editor's zone.** *Recommendation:* accept; it is how every Together reminder already works, and a partner abroad isn't woken at the editor's 09:00.
2. **The guard on the About us reminder (P-6).** *Recommendation:* accept; without it the reminder and About us can disagree, and the spec makes About us the single source.
3. **The copy the spec doesn't give (P-14), in particular R3's card telling the inviter that the draft is shared at linking.** *Recommendation:* accept as drafted; the Ghanaian cultural reviewer's W5 gate reads the stage options and helper text anyway, and can read these lines in the same pass.
4. **An offline answer stays on the phone through a quick exit (P-17).** *Recommendation:* accept; it is never shown, it belongs to the signed-in account, and sign-out still wipes it.
5. **D2 (from the spec's sign-off): "Changed by Yaw - Tue, 12 Nov".** *Recommendation:* keep; it is the house date standard, built here as specified.

## W1-W4 interfaces this plan consumes (adjust here if a later fix renames one)

- SQL: `public.relationships` (`status`, `paused_at`, `ended_at`, `chat_archived_at`), `public.relationship_seals`, `public.relationship_chat_open(uuid)` / `relationship_chat_open_for(uuid, uuid)` (active, paused, or ended within 30 days; not sealed; not archived), `public.reminders` (`reminder_type` CHECK includes `anniversary`, `recurrence` includes `yearly`, `remind_days_before`, RLS update/delete for active members), `public.reminder_next_on(date, text, date)`, `public.bump_together_signal()` and `public.together_change_signals`, `private.invite_first_name(uuid)` (W4a), `public.users.path`, `public.account_birthdates`, `public.journal_reminder_settings`, `public.export_who(uuid, uuid)`, `public.feature_flags` row `couple_profile` (W1c), `private.spec1_flag_on`, the live bodies named under Global Constraints.
- Edge: `supabase/functions/accept-invite/accept.test.ts` ("every code the newest accept_relationship_invite_v2 raises is mapped, and only those").
- Dart (W1-W4): `SignedInFlowFlags`, `FlowFlagsCache` (`lib/core/flags/signed_in_flow_flags.dart`); `flowFlagsProvider`, `flowFlagsGatewayProvider`, `SupabaseFlowFlagsGateway`, `flowCouplesV2Provider` (`lib/features/onboarding/presentation/providers/flow_flags.dart`); `signInFlowV2Provider`; `homeAuthProvider` (`lib/home/home_seams.dart`); `homeStateProvider(uid)` (`HomeSnapshot.link`, `.linkDetail.relationshipId`, notifier `apply`), `HomeState.fromJson`, `LinkState`; `togetherChangeSignalProvider` (`lib/features/timeline/presentation/providers/timeline_providers.dart`); `coupleNameProvider`; `sharedPreferencesProvider`; `DeviceWipeRegistry`, `DeviceWipeEntry`, `WipeMoment`, `registerDeviceWipes`, `spec1DeviceWipes`, `removePrefsKeys` (`lib/app/device_wipes.dart`); `OnboardingSyncService`, `OnboardingStore`; `FlowFrame`, `FlowPrimaryButton`, `FlowSecondaryButton`, `FlowTextLink`, `FlowTextField`, `FlowErrorLine`, `flowAccent`; `AllowLargeText`; `SharedAxisStep`, `kSelectionDuration`, `reduceMotionOf`; `SpaceRow` (`lib/features/me/presentation/widgets/your_space_section.dart`); `SettingsConfig`, `SettingsItemType`; `activeRelationshipIdProvider`; `InfoRowWidget`; `showReminderSheet`; `RouteNames`; `RelationshipSpaceScreen` (`_partnerName`); `MyDateFormat` (`join`, `toDate`, `toDateShort`); `DocumentationRegistry`; test helpers `pumpFlowScreen`, `expectFlowGoldens`, `expectFlowGuidelines` (`test/helpers/flow_harness.dart`), `FakeHomeAuth`, `testUser`, `snapshotOf` (`home_harness.dart`), `homeJson`, `FakeHomeStateGateway`, `FakeFlowFlagsGateway` (`fake_home_state.dart`), `FakeInvites`, `FakePushAsker`, `pushAskerProvider`, `invitePartnerServiceProvider`, `relationshipLifecycleProvider`.

## File map

**Server (Tasks 1-2)**
- Create `supabase/migrations/20261102110000_couple_profiles.sql`, `…110010_couple_profiles_grants.sql`, `supabase/tests/couple_profile_contracts.sql`; modify `scripts/local_pg_grants.sql` (Task 1).
- Create `supabase/migrations/20261102110100_couple_profiles_links.sql`, `…110110_couple_profiles_links_grants.sql`; modify `supabase/tests/couple_profile_contracts.sql` (sections F-Dating, G, H, I), `supabase/tests/identity_foundation_contracts.sql` (one expression, P-10), `scripts/local_pg_grants.sql` (Task 2).

**Phone (Tasks 3-5)**
- Create `lib/features/couple_profile/domain/couple_profile.dart`, `lib/features/couple_profile/data/{couple_profile_service,about_us_outbox}.dart`, `lib/features/couple_profile/presentation/couple_profile_providers.dart`, `test/helpers/fake_couple_profile.dart`, `test/features/couple_profile/w5/{couple_profile_data_test,about_us_sync_test}.dart`, `test/architecture/couple_profile_never_typed_test.dart`; modify `lib/core/flags/signed_in_flow_flags.dart`, `lib/features/onboarding/presentation/providers/flow_flags.dart`, `lib/core/utils/date_formatter.dart`, `lib/features/onboarding/data/onboarding_sync_service.dart`, `lib/home/home_screen.dart` (outside the latch), `lib/app/device_wipes.dart`, `test/helpers/fake_home_state.dart` (Task 3).
- Create `lib/features/couple_profile/presentation/{about_us_copy.dart,widgets/about_us_choice.dart,screens/about_us_question_flow.dart}`, `test/features/couple_profile/w5/about_us_flow_test.dart` (+ 20 goldens); modify `lib/i10n/app_en.arb` (+ generated) (Task 4).
- Create `lib/features/couple_profile/presentation/{about_us_entry.dart,widgets/about_us_card.dart,widgets/changed_by_line.dart,screens/about_us_screen.dart}`, `lib/app/documentations/user_manual/data/about_us_docs.dart`, `test/features/couple_profile/w5/{about_us_screen_test,about_us_entry_test,relationship_space_about_us_test,about_us_docs_test}.dart` (+ 8 goldens), `test/app/routing/about_us_route_test.dart`; modify `lib/app/routing/app_router.dart`, `lib/features/settings/data/settings_data.dart`, `lib/features/settings/screens/settings_screen.dart`, `lib/features/relationships/presentation/screens/relationship_space_screen.dart`, `lib/features/together/presentation/screens/together_screen.dart`, `lib/features/reminders/presentation/screens/add_edit_reminder_screen.dart`, `lib/app/documentations/user_manual/data/manual_documentation_registry.dart`, `test/features/together/together_screen_test.dart`, `test/app/documentations/documentation_registry_flags_test.dart` (Task 5).

Tests live under `supabase/tests/`, `test/features/couple_profile/w5/`, `test/app/routing/`, `test/architecture/`, `test/helpers/`.

**Not edited:** HomeScreen's latch block, `lib/features/onboarding/presentation/screens/onboarding_gate.dart`, `onboarding_gate_v2.dart`, `lib/features/chat/**`, `lib/features/opinions/**`, `lib/features/games/**`, `auth_exports.dart`, `lib/app/app_shell.dart` and the quick-exit and sign-out files, `supabase/functions/**`, `supabase/sql/dev_enable_spec1_flags.sql`, every applied migration, every existing SQL contract but the one `identity_foundation_contracts.sql` expression, every existing test except the three named above (each extended, nothing removed).

---

### Task 1: Baselines and migration 10, part 1: the profile, the draft, the merge, the anniversary reminder (§4.2, §4.3 W5, §4.4, §7.1, P-1-P-7, P-9, P-22)

**Files:**
- Create: `supabase/migrations/20261102110000_couple_profiles.sql`
- Create: `supabase/migrations/20261102110010_couple_profiles_grants.sql`
- Create: `supabase/tests/couple_profile_contracts.sql`
- Modify: `scripts/local_pg_grants.sql` (one `\i` block after W4a's; never run)

**Interfaces:**
- Consumes: the SQL listed under "W1-W4 interfaces".
- Produces: tables `public.couple_profiles` (PK `relationship_id` -> `relationships` ON DELETE CASCADE; the spec's columns exactly; RLS SELECT `relationship_chat_open(relationship_id)`) and `public.couple_profile_drafts` (PK `user_id` -> `users` ON DELETE CASCADE; RLS SELECT own); `private.couple_profile_merge(p_state jsonb, p_patch jsonb) → jsonb`; `private.couple_profile_change(uuid, uuid, timestamptz) → jsonb`; `private.couple_profile_ceremony_date(jsonb) → date`; `public.get_couple_profile(p_relationship_id uuid) → jsonb` (`{draft, read_only, read_until, together_since, together_since_precision, stage, stage_words, ceremonies, living, children, child_age_bands, anniversary_source, anniversary_reminder_id, changes:{<field>:{changed_by_me, changed_by_first_name?, changed_at}}}`, fields `together_since|stage|ceremonies|living|children|anniversary`); `public.update_couple_profile(p_relationship_id uuid, p_patch jsonb) → jsonb` (same shape); `public.get_my_couple_profile_draft() → jsonb` and `public.update_my_couple_profile_draft(p_patch jsonb) → jsonb` (same shape, `draft: true`, `changes: {}`); `public.adopt_couple_profile_drafts(p_relationship_id uuid, p_inviter uuid, p_acceptor uuid) → void` (no grants; called by Task 2's accept); `public.sync_anniversary_reminder(p_relationship_id uuid) → void` (no grants); triggers `couple_profiles_together_signal` and `reminders_guard_about_us`; refusals `couple_profile:not_found|read_only|not_relationship|unknown_key|invalid|future_date|too_many_ceremonies|ceremonies_need_married|bands_need_yes|anniversary_needs_day` and `reminder:follows_about_us`.

- [ ] **Step 1: Confirm the target, W4 green, and record the baselines**

```bash
cd /Users/user/attune
psql -X -d attune_spec3a -Atc 'select current_database()'
ls supabase/migrations | sort | tail -1
mkdir -p .superpowers/sdd/2026-11-02-spec1-w5
git status --short > .superpowers/sdd/2026-11-02-spec1-w5/git-status-before.txt
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > .superpowers/sdd/2026-11-02-spec1-w5/sql-baseline.txt
grep '^FAIL' .superpowers/sdd/2026-11-02-spec1-w5/sql-baseline.txt
flutter test --no-pub 2>&1 | tr '\r' '\n' | grep -E 'All tests passed!|Some tests failed' | tail -1
flutter analyze --no-pub lib test > .superpowers/sdd/2026-11-02-spec1-w5/analyze-baseline.txt 2>&1
grep -E '^\s*error ' .superpowers/sdd/2026-11-02-spec1-w5/analyze-baseline.txt | sed -E 's/:[0-9]+:[0-9]+//' | sort -u > .superpowers/sdd/2026-11-02-spec1-w5/analyze-errors-baseline.txt
wc -l < .superpowers/sdd/2026-11-02-spec1-w5/analyze-errors-baseline.txt
awk '/if \(isAuthenticated && !_gateData.isComplete\) \{/,/_redirectingToOnboarding = false;/' lib/home/home_screen.dart > .superpowers/sdd/2026-11-02-spec1-w5/latch-before.txt
wc -l < .superpowers/sdd/2026-11-02-spec1-w5/latch-before.txt
(cd supabase/functions && deno test --allow-read accept-invite/ 2>&1 | grep -E 'passed|failed' | tail -1)
psql -X -d attune_spec3a -Atc "select enabled from public.feature_flags where key = 'couple_profile'"
git diff --stat -- lib/features/opinions lib/features/games lib/features/auth/utility/auth_exports.dart | tail -1
```

Expected: `attune_spec3a`; `20261102100010_accept_invite_v2_grants.sql`; the pre-existing FAILs (when this plan was written: the 14 `ai_*` contracts, `couple_map_presence_contracts.sql`, `reminder_delivery_contracts.sql`, `together_events_contracts.sql`; keep whatever you get, every gate compares with it); `All tests passed!`; `0`; a non-zero line count for the latch; `ok | 29 passed | 0 failed`; a row for `couple_profile` (`f` or `t`); no Opinions or Games diff. If the Flutter suite isn't green, stop and report; one known exception: `test/features/planning/planning_recent_test.dart` ("Recent sits above the categories…") fails when run between 00:00 and 01:00 local time (its "an hour ago" becomes "Yesterday"), so rerun that file alone after 01:00 before deciding.

- [ ] **Step 2: Write the failing contract**

Create `supabase/tests/couple_profile_contracts.sql` with exactly:

```sql
-- supabase/tests/couple_profile_contracts.sql
-- Spec 1 W5 (§3.8 About us, §4.2, §4.3 W5, §4.4, §7.1): the shared couple
-- profile and the draft before linking: who may read and write, every
-- validation, attribution per field (a first name, never an id), the
-- together signal, the anniversary reminder's single source and its guard,
-- the draft's life (kept through a withdrawal; W5 part 2 adds the switch
-- to Dating, the adoption at linking and the export), and never a type or
-- a score.
-- One BEGIN ... ROLLBACK.
-- Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/couple_profile_contracts.sql
-- Fixture ids 5c0f0000-0000-0000-0000-0000000000NN (relationships
-- 5c0f0000-0000-0000-0000-0000000001NN); phones +15558300NN (§7.1's 83xx
-- range), set on auth.users and public.users. Every refusal is checked by
-- its message.
BEGIN;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ('5c0f0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

CREATE FUNCTION pg_temp.rel(p_n text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ('5c0f0000-0000-0000-0000-0000000001' || p_n)::uuid;
$$;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', coalesce(p::text, ''), true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

CREATE FUNCTION pg_temp.error_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN NULL;
EXCEPTION WHEN raise_exception OR insufficient_privilege THEN
  RETURN SQLERRM;
END $$;

-- An account on the Relationship path: a verified Auth phone, a users row
-- named [p_name], a date of birth 30 years ago.
CREATE FUNCTION pg_temp.person(p_n text, p_name text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at)
  VALUES (pg_temp.id(p_n), '+155583000' || p_n, now());
  INSERT INTO public.users (id, phone, display_name, path)
  VALUES (pg_temp.id(p_n), '+155583000' || p_n, p_name, 'relationship');
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (pg_temp.id(p_n), (current_date - interval '30 years')::date);
END $$;

-- A relationship [p_rel] between [p_a] and [p_b] in [p_status].
CREATE FUNCTION pg_temp.couple(p_rel text, p_a text, p_b text, p_status text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.relationships (id, user_a, user_b, status, started_at, invite_accepted_at,
                                    paused_at, paused_by, ended_at, ended_by)
  VALUES (pg_temp.rel(p_rel), pg_temp.id(p_a), pg_temp.id(p_b), p_status, current_date, now(),
          CASE WHEN p_status = 'paused' THEN now() - interval '2 days' END,
          CASE WHEN p_status = 'paused' THEN pg_temp.id(p_a) END,
          CASE WHEN p_status = 'ended' THEN now() - interval '3 days' END,
          CASE WHEN p_status = 'ended' THEN pg_temp.id(p_a) END);
END $$;

-- [p_user]'s update of [p_rel] with [p_patch]: the refusal, or NULL.
CREATE FUNCTION pg_temp.update_error(p_user text, p_rel text, p_patch text) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
  v_msg text;
BEGIN
  PERFORM pg_temp.as_user(pg_temp.id(p_user));
  v_msg := pg_temp.error_of(format('SELECT public.update_couple_profile(%L, %L::jsonb)',
                                   pg_temp.rel(p_rel), p_patch));
  RESET ROLE;
  RETURN v_msg;
END $$;

CREATE FUNCTION pg_temp.read_error(p_user text, p_rel text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_msg text;
BEGIN
  PERFORM pg_temp.as_user(pg_temp.id(p_user));
  v_msg := pg_temp.error_of(format('SELECT public.get_couple_profile(%L)', pg_temp.rel(p_rel)));
  RESET ROLE;
  RETURN v_msg;
END $$;

CREATE FUNCTION pg_temp.update_as(p_user text, p_rel text, p_patch jsonb) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  PERFORM pg_temp.as_user(pg_temp.id(p_user));
  v := public.update_couple_profile(pg_temp.rel(p_rel), p_patch);
  RESET ROLE;
  RETURN v;
END $$;

CREATE FUNCTION pg_temp.read_as(p_user text, p_rel text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  PERFORM pg_temp.as_user(pg_temp.id(p_user));
  v := public.get_couple_profile(pg_temp.rel(p_rel));
  RESET ROLE;
  RETURN v;
END $$;

CREATE FUNCTION pg_temp.draft_as(p_user text, p_patch jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  PERFORM pg_temp.as_user(pg_temp.id(p_user));
  v := CASE WHEN p_patch IS NULL THEN public.get_my_couple_profile_draft()
            ELSE public.update_my_couple_profile_draft(p_patch) END;
  RESET ROLE;
  RETURN v;
END $$;

CREATE FUNCTION pg_temp.draft_error(p_user text, p_patch text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_msg text;
BEGIN
  PERFORM pg_temp.as_user(pg_temp.id(p_user));
  v_msg := pg_temp.error_of(CASE WHEN p_patch IS NULL THEN 'SELECT public.get_my_couple_profile_draft()'
                                 ELSE format('SELECT public.update_my_couple_profile_draft(%L::jsonb)', p_patch) END);
  RESET ROLE;
  RETURN v_msg;
END $$;

CREATE FUNCTION pg_temp.signal(p_rel text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce((SELECT s.version FROM public.together_change_signals AS s
                    WHERE s.relationship_id = pg_temp.rel(p_rel)), 0);
$$;

CREATE FUNCTION pg_temp.flag(p_key text, p_on boolean) RETURNS void LANGUAGE sql AS $$
  UPDATE public.feature_flags SET enabled = p_on WHERE key = p_key;
$$;

-- =====================================================================
-- A. Objects, grants, RLS, and never a type or a score (spec §7.1): the
--    exact columns, the only functions that read couple_profiles, no
--    view over it, not in the Realtime publication.
-- =====================================================================
DO $$
DECLARE
  v_cols text;
  v_bad text;
BEGIN
  IF to_regclass('public.couple_profiles') IS NULL OR to_regclass('public.couple_profile_drafts') IS NULL
     OR to_regprocedure('public.get_couple_profile(uuid)') IS NULL
     OR to_regprocedure('public.update_couple_profile(uuid,jsonb)') IS NULL
     OR to_regprocedure('public.get_my_couple_profile_draft()') IS NULL
     OR to_regprocedure('public.update_my_couple_profile_draft(jsonb)') IS NULL
     OR to_regprocedure('public.adopt_couple_profile_drafts(uuid,uuid,uuid)') IS NULL
     OR to_regprocedure('public.sync_anniversary_reminder(uuid)') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W5 objects are missing';
  END IF;

  SELECT string_agg(c.column_name, ',' ORDER BY c.column_name) INTO v_cols
    FROM information_schema.columns AS c
   WHERE c.table_schema = 'public' AND c.table_name = 'couple_profiles';
  IF v_cols IS DISTINCT FROM
     'anniversary_changed_at,anniversary_changed_by,anniversary_reminder_id,anniversary_source,'
     'ceremonies,ceremonies_changed_at,ceremonies_changed_by,child_age_bands,children,'
     'children_changed_at,children_changed_by,living,living_changed_at,living_changed_by,'
     'relationship_id,stage,stage_changed_at,stage_changed_by,stage_words,together_since,'
     'together_since_changed_at,together_since_changed_by,together_since_precision,updated_at' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: couple_profiles has columns beyond the spec (never a type or score): %', v_cols;
  END IF;

  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_bad
    FROM pg_proc AS p
   WHERE p.prosrc ~ '\mcouple_profiles\M'
     AND p.oid NOT IN ('public.get_couple_profile(uuid)'::regprocedure,
                       'public.update_couple_profile(uuid,jsonb)'::regprocedure,
                       'public.adopt_couple_profile_drafts(uuid,uuid,uuid)'::regprocedure,
                       'public.sync_anniversary_reminder(uuid)'::regprocedure,
                       'public.export_relationship(uuid,uuid)'::regprocedure,
                       'private.guard_about_us_reminder()'::regprocedure);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a function outside the allow-list reads couple_profiles (never a type or score): %', v_bad;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_views WHERE definition ~ '\mcouple_profiles\M')
     OR EXISTS (SELECT 1 FROM pg_matviews WHERE definition ~ '\mcouple_profiles\M') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a view selects from couple_profiles';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_publication_tables
              WHERE tablename IN ('couple_profiles', 'couple_profile_drafts')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: About us is in a Realtime publication (the together signal is)';
  END IF;

  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.couple_profiles'::regclass)
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.couple_profile_drafts'::regclass) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: RLS is off on an About us table';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.couple_profiles', 'SELECT')
     OR has_table_privilege('authenticated', 'public.couple_profiles', 'INSERT')
     OR has_table_privilege('authenticated', 'public.couple_profiles', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.couple_profiles', 'DELETE')
     OR has_table_privilege('anon', 'public.couple_profiles', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.couple_profile_drafts', 'SELECT')
     OR has_table_privilege('authenticated', 'public.couple_profile_drafts', 'INSERT')
     OR has_table_privilege('authenticated', 'public.couple_profile_drafts', 'UPDATE')
     OR has_table_privilege('anon', 'public.couple_profile_drafts', 'SELECT')
     OR NOT has_table_privilege('service_role', 'public.couple_profiles', 'INSERT')
     OR NOT has_table_privilege('service_role', 'public.couple_profile_drafts', 'DELETE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: About us table grants are wrong';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.get_couple_profile(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.update_couple_profile(uuid,jsonb)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_my_couple_profile_draft()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.update_my_couple_profile_draft(jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.get_couple_profile(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.update_couple_profile(uuid,jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.update_my_couple_profile_draft(jsonb)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.adopt_couple_profile_drafts(uuid,uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.adopt_couple_profile_drafts(uuid,uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.sync_anniversary_reminder(uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.sync_anniversary_reminder(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.couple_profile_merge(jsonb,jsonb)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.couple_profile_change(uuid,uuid,timestamptz)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.couple_profile_ceremony_date(jsonb)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.guard_about_us_reminder()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: About us function grants are wrong';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'couple_profiles_together_signal'
                    AND tgrelid = 'public.couple_profiles'::regclass)
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'reminders_guard_about_us'
                       AND tgrelid = 'public.reminders'::regclass) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the together signal or the reminder guard trigger is missing';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc AS p
              WHERE p.oid IN ('public.get_couple_profile(uuid)'::regprocedure,
                              'public.update_couple_profile(uuid,jsonb)'::regprocedure,
                              'public.get_my_couple_profile_draft()'::regprocedure,
                              'public.update_my_couple_profile_draft(jsonb)'::regprocedure,
                              'public.adopt_couple_profile_drafts(uuid,uuid,uuid)'::regprocedure,
                              'public.sync_anniversary_reminder(uuid)'::regprocedure)
                AND (NOT p.prosecdef OR p.proconfig IS DISTINCT FROM ARRAY['search_path=""'])) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an About us function is not SECURITY DEFINER with search_path ''''';
  END IF;
END $$;

-- =====================================================================
-- B. Who reads: both members; never an outsider, a sealed side, an
--    archived chapter or one past its window; paused and the window
--    read-only. Fixtures 01-14.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_msg text;
  v_n int;
BEGIN
  PERFORM pg_temp.person('01', 'Yaw Mensah');
  PERFORM pg_temp.person('02', 'Ama Owusu');
  PERFORM pg_temp.person('03', 'Kofi Outsider');
  PERFORM pg_temp.person('04', 'Abena Paused');
  PERFORM pg_temp.person('05', 'Kwame Paused');
  PERFORM pg_temp.person('06', 'Esi Ended');
  PERFORM pg_temp.person('07', 'Kojo Ended');
  PERFORM pg_temp.person('08', 'Adjoa Sealed');
  PERFORM pg_temp.person('09', 'Nana Sealed');
  PERFORM pg_temp.person('10', 'Efua Archived');
  PERFORM pg_temp.person('11', 'Yaa Archived');
  PERFORM pg_temp.person('12', 'Akua Late');
  PERFORM pg_temp.person('13', 'Kwesi Late');
  PERFORM pg_temp.couple('01', '01', '02', 'active');
  PERFORM pg_temp.couple('02', '04', '05', 'paused');
  PERFORM pg_temp.couple('03', '06', '07', 'ended');
  PERFORM pg_temp.couple('04', '08', '09', 'ended');
  INSERT INTO public.relationship_seals (relationship_id, user_id) VALUES (pg_temp.rel('04'), pg_temp.id('08'));
  PERFORM pg_temp.couple('05', '10', '11', 'archived');
  UPDATE public.relationships SET chat_archived_at = now(), chat_archived_reason = 'manual_end',
         ended_at = now() - interval '1 day', ended_by = pg_temp.id('10')
   WHERE id = pg_temp.rel('05');
  PERFORM pg_temp.couple('06', '12', '13', 'ended');
  UPDATE public.relationships SET ended_at = now() - interval '31 days' WHERE id = pg_temp.rel('06');

  v := pg_temp.read_as('01', '01');
  IF (v->>'read_only')::boolean OR v->>'anniversary_source' <> 'off' OR v->'ceremonies' <> '[]'::jsonb
     OR v->'child_age_bands' <> '[]'::jsonb OR v->'changes' <> '{}'::jsonb OR (v->>'draft')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an empty profile reads wrongly: %', v;
  END IF;
  IF v ? 'suggested_dates' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_couple_profile carries suggested_dates (review I-12)';
  END IF;
  IF pg_temp.read_error('02', '01') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the other member cannot read the profile';
  END IF;
  v_msg := pg_temp.read_error('03', '01');
  IF v_msg IS DISTINCT FROM 'couple_profile:not_found' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider read the profile (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.update_error('03', '01', '{"living":"together"}');
  IF v_msg IS DISTINCT FROM 'couple_profile:not_found' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider wrote the profile (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- Paused and inside the ending window: read, never written.
  v := pg_temp.read_as('04', '02');
  IF NOT (v->>'read_only')::boolean OR (v->>'read_until')::timestamptz IS NULL
     OR abs(extract(epoch FROM (v->>'read_until')::timestamptz - (now() + interval '28 days'))) > 60 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused profile is not read-only until the pause ends: %', v;
  END IF;
  v_msg := pg_temp.update_error('05', '02', '{"living":"together"}');
  IF v_msg IS DISTINCT FROM 'couple_profile:read_only' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused profile was written (got %)', coalesce(v_msg, 'no error');
  END IF;
  v := pg_temp.read_as('07', '03');
  IF NOT (v->>'read_only')::boolean
     OR abs(extract(epoch FROM (v->>'read_until')::timestamptz - (now() + interval '27 days'))) > 60 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the ending window is not read-only until its end: %', v;
  END IF;
  v_msg := pg_temp.update_error('06', '03', '{"living":"together"}');
  IF v_msg IS DISTINCT FROM 'couple_profile:read_only' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a profile in the ending window was written (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- Sealed (that side only), archived, past the window: gone.
  v_msg := pg_temp.read_error('08', '04');
  IF v_msg IS DISTINCT FROM 'couple_profile:not_found' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a sealed side read the profile (got %)', coalesce(v_msg, 'no error');
  END IF;
  IF pg_temp.read_error('09', '04') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the unsealed side lost the profile in the window';
  END IF;
  v_msg := pg_temp.read_error('10', '05');
  IF v_msg IS DISTINCT FROM 'couple_profile:not_found' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an archived chapter''s profile was read (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.read_error('12', '06');
  IF v_msg IS DISTINCT FROM 'couple_profile:not_found' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a profile past its window was read (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- RLS on the table itself: members while open, nobody else.
  INSERT INTO public.couple_profiles (relationship_id, living) VALUES (pg_temp.rel('05'), 'together');
  PERFORM pg_temp.as_user(pg_temp.id('03'));
  SELECT count(*) INTO v_n FROM public.couple_profiles WHERE relationship_id IN (pg_temp.rel('01'), pg_temp.rel('05'));
  RESET ROLE;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider selected a couple_profiles row';
  END IF;
  PERFORM pg_temp.as_user(pg_temp.id('10'));
  SELECT count(*) INTO v_n FROM public.couple_profiles WHERE relationship_id = pg_temp.rel('05');
  RESET ROLE;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an archived chapter''s row is selectable';
  END IF;
  PERFORM pg_temp.as_user(pg_temp.id('01'));
  v_msg := pg_temp.error_of(format('UPDATE public.couple_profiles SET stage = ''married'' WHERE relationship_id = %L', pg_temp.rel('01')));
  RESET ROLE;
  IF v_msg IS NULL OR v_msg NOT LIKE 'permission denied%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a member updated couple_profiles directly (got %)', coalesce(v_msg, 'no error');
  END IF;
END $$;

-- =====================================================================
-- C. Every validation (spec §3.8 AU1-AU6, §4.3 W5): each refusal by its
--    message, and the normal forms. Relationship 01 (Yaw 01, Ama 02).
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_msg text;
  r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('{"mood":"great"}', 'couple_profile:unknown_key'),
    ('{"score":5}', 'couple_profile:unknown_key'),
    ('[1,2]', 'couple_profile:invalid'),
    ('{"together_since":"2024-10-14"}', 'couple_profile:invalid'),
    ('{"together_since_precision":"day"}', 'couple_profile:invalid'),
    ('{"together_since":"2024-10-14","together_since_precision":"week"}', 'couple_profile:invalid'),
    ('{"together_since":"14/10/2024","together_since_precision":"day"}', 'couple_profile:invalid'),
    ('{"together_since":"2023-02-30","together_since_precision":"day"}', 'couple_profile:invalid'),
    ('{"together_since":"1899-12-31","together_since_precision":"day"}', 'couple_profile:invalid'),
    ('{"together_since":"2999-01-01","together_since_precision":"year"}', 'couple_profile:future_date'),
    ('{"stage":"situationship"}', 'couple_profile:invalid'),
    ('{"stage":"other","stage_words":"' || repeat('a', 41) || '"}', 'couple_profile:invalid'),
    ('{"living":"elsewhere"}', 'couple_profile:invalid'),
    ('{"children":"three"}', 'couple_profile:invalid'),
    ('{"children":"yes","child_age_bands":["teen"]}', 'couple_profile:invalid'),
    ('{"children":"no","child_age_bands":["2to5"]}', 'couple_profile:invalid'),
    ('{"children":"none","child_age_bands":["2to5"]}', 'couple_profile:bands_need_yes'),
    ('{"child_age_bands":["2to5"]}', 'couple_profile:bands_need_yes'),
    ('{"ceremonies":[{"year":1999}]}', 'couple_profile:ceremonies_need_married'),
    ('{"stage":"engaged","ceremonies":[{"year":1999}]}', 'couple_profile:ceremonies_need_married'),
    ('{"stage":"married","ceremonies":[{"year":1999},{"year":2000},{"year":2001}]}', 'couple_profile:too_many_ceremonies'),
    ('{"stage":"married","ceremonies":[{"year":"1999"}]}', 'couple_profile:invalid'),
    ('{"stage":"married","ceremonies":[{"year":1999,"month":13}]}', 'couple_profile:invalid'),
    ('{"stage":"married","ceremonies":[{"year":1999,"day":4}]}', 'couple_profile:invalid'),
    ('{"stage":"married","ceremonies":[{"year":2001,"month":2,"day":29}]}', 'couple_profile:invalid'),
    ('{"stage":"married","ceremonies":[{"year":1999,"label":"beach"}]}', 'couple_profile:invalid'),
    ('{"stage":"married","ceremonies":[{"year":1999,"guests":200}]}', 'couple_profile:invalid'),
    ('{"stage":"married","ceremonies":[{"year":2999}]}', 'couple_profile:future_date'),
    ('{"anniversary_source":"first_kiss"}', 'couple_profile:invalid'),
    ('{"anniversary_source":"ceremony_1"}', 'couple_profile:invalid'),
    ('{"anniversary_source":"together_since"}', 'couple_profile:anniversary_needs_day'),
    ('{"together_since":"2024-10-01","together_since_precision":"month","anniversary_source":"together_since"}', 'couple_profile:anniversary_needs_day'),
    ('{"stage":"married","ceremonies":[{"year":1999,"month":4}],"anniversary_source":"ceremony_1"}', 'couple_profile:anniversary_needs_day')
  ) AS t(patch, expected) LOOP
    v_msg := pg_temp.update_error('01', '01', r.patch);
    IF v_msg IS DISTINCT FROM r.expected THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % answered % (expected %)', r.patch, coalesce(v_msg, 'no error'), r.expected;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.couple_profiles WHERE relationship_id = pg_temp.rel('01')
                AND (stage IS NOT NULL OR living IS NOT NULL OR together_since IS NOT NULL)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused patch wrote something';
  END IF;

  -- Normal forms: a month is its 1st, a year 1 January; the couple's own
  -- words only with "Something else" (trimmed); bands in order, once.
  v := pg_temp.update_as('01', '01', '{"together_since":"2024-10-19","together_since_precision":"month"}');
  IF v->>'together_since' <> '2024-10-01' OR v->>'together_since_precision' <> 'month' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a month was not kept as its 1st: %', v;
  END IF;
  v := pg_temp.update_as('01', '01', '{"together_since":"2019-06-19","together_since_precision":"year"}');
  IF v->>'together_since' <> '2019-01-01' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a year was not kept as 1 January: %', v;
  END IF;
  v := pg_temp.update_as('01', '01', '{"stage":"other","stage_words":"  Courting, with both families  "}');
  IF v->>'stage_words' <> 'Courting, with both families' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the couple''s own words were not trimmed: %', v;
  END IF;
  v := pg_temp.update_as('01', '01', '{"stage":"engaged"}');
  IF v->'stage_words' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: own words stayed after leaving "Something else": %', v;
  END IF;
  v := pg_temp.update_as('01', '01', '{"stage":"engaged","stage_words":"ignored"}');
  IF v->'stage_words' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: own words were kept without "Something else": %', v;
  END IF;
  v := pg_temp.update_as('01', '01', '{"children":"yes","child_age_bands":["18plus","13to17","18plus"]}');
  IF v->'child_age_bands' <> '["13to17","18plus"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: age bands not ordered once: %', v;
  END IF;
  v := pg_temp.update_as('01', '01', '{"children":"prefer_not_to_say"}');
  IF v->'child_age_bands' <> '[]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: age bands stayed after leaving "Yes": %', v;
  END IF;
  -- Today is never the future (a day of slack for the earliest zone).
  v := pg_temp.update_as('01', '01', jsonb_build_object('together_since', current_date + 1, 'together_since_precision', 'day'));
  IF (v->>'together_since')::date <> current_date + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: tomorrow in UTC (today in UTC+14) was refused: %', v;
  END IF;
  v_msg := pg_temp.update_error('01', '01', jsonb_build_object('together_since', current_date + 2, 'together_since_precision', 'day')::text);
  IF v_msg IS DISTINCT FROM 'couple_profile:future_date' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two days ahead was not a future date (got %)', coalesce(v_msg, 'no error');
  END IF;
  -- Cleared: a date set to null takes its precision with it.
  v := pg_temp.update_as('01', '01', '{"together_since":null}');
  IF v->'together_since' <> 'null'::jsonb OR v->'together_since_precision' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clearing the date kept its precision: %', v;
  END IF;
END $$;

-- =====================================================================
-- D. Attribution per field (a first name, never an id), the together
--    signal, and leaving Married (attributed). Relationship 01.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_signal bigint;
  v_at timestamptz;
BEGIN
  UPDATE public.couple_profiles SET stage = NULL, stage_words = NULL, living = NULL,
         stage_changed_by = NULL, stage_changed_at = NULL, living_changed_by = NULL, living_changed_at = NULL
   WHERE relationship_id = pg_temp.rel('01');
  v_signal := pg_temp.signal('01');
  v := pg_temp.update_as('01', '01', '{"stage":"married","ceremonies":[{"year":1999,"label":"customary"},{"year":2004,"month":8,"day":14,"label":"church"}]}');
  IF pg_temp.signal('01') <= v_signal THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an edit did not bump the together signal';
  END IF;
  PERFORM pg_temp.update_as('02', '01', '{"living":"apart_nearby"}');

  v := pg_temp.read_as('02', '01');
  IF v->'changes'->'stage'->>'changed_by_first_name' IS DISTINCT FROM 'Yaw'
     OR (v->'changes'->'stage'->>'changed_by_me')::boolean
     OR NOT (v->'changes'->'living'->>'changed_by_me')::boolean
     OR v->'changes'->'living' ? 'changed_by_first_name'
     OR v->'changes'->'ceremonies'->>'changed_by_first_name' IS DISTINCT FROM 'Yaw'
     OR (v->'changes'->'living'->>'changed_at')::timestamptz IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: attribution per field reads wrongly for Ama: %', v->'changes';
  END IF;
  v := pg_temp.read_as('01', '01');
  IF NOT (v->'changes'->'stage'->>'changed_by_me')::boolean
     OR v->'changes'->'living'->>'changed_by_first_name' IS DISTINCT FROM 'Ama' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: attribution per field reads wrongly for Yaw: %', v->'changes';
  END IF;
  IF v::text LIKE '%' || pg_temp.id('01') || '%' OR v::text LIKE '%' || pg_temp.id('02') || '%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_couple_profile carries a member id';
  END IF;

  -- A first name, never a phone number written as a name.
  UPDATE public.users SET display_name = '+233 24 000 0000' WHERE id = pg_temp.id('01');
  v := pg_temp.read_as('02', '01');
  IF v->'changes'->'stage' ? 'changed_by_first_name' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a phone number was shown as a name: %', v->'changes'->'stage';
  END IF;
  UPDATE public.users SET display_name = 'Yaw Mensah' WHERE id = pg_temp.id('01');

  -- Changing one field leaves every other field's attribution alone.
  PERFORM pg_temp.update_as('01', '01', '{"children":"none"}');
  IF (SELECT living_changed_by FROM public.couple_profiles WHERE relationship_id = pg_temp.rel('01')) <> pg_temp.id('02')
     OR (SELECT children_changed_by FROM public.couple_profiles WHERE relationship_id = pg_temp.rel('01')) <> pg_temp.id('01') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an edit of one field re-attributed another';
  END IF;

  -- A patch that changes nothing changes no attribution and bumps nothing.
  v_at := (SELECT living_changed_at FROM public.couple_profiles WHERE relationship_id = pg_temp.rel('01'));
  v_signal := pg_temp.signal('01');
  PERFORM pg_temp.update_as('01', '01', '{"living":"apart_nearby"}');
  IF (SELECT living_changed_by FROM public.couple_profiles WHERE relationship_id = pg_temp.rel('01')) <> pg_temp.id('02')
     OR (SELECT living_changed_at FROM public.couple_profiles WHERE relationship_id = pg_temp.rel('01')) <> v_at
     OR pg_temp.signal('01') <> v_signal THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a no-op patch moved the attribution or the signal';
  END IF;

  -- Leaving Married clears the ceremonies, attributed to who left it.
  v := pg_temp.update_as('02', '01', '{"stage":"engaged"}');
  IF v->'ceremonies' <> '[]'::jsonb
     OR NOT (SELECT ceremonies_changed_by = pg_temp.id('02') FROM public.couple_profiles
              WHERE relationship_id = pg_temp.rel('01')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: leaving Married did not clear the ceremonies, attributed: %', v;
  END IF;
END $$;

-- =====================================================================
-- E. The anniversary reminder: one source, created, moved, deleted;
--    and the guard. Relationship 01.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_id uuid;
  v_rem public.reminders%ROWTYPE;
  v_msg text;
  v_other uuid;
BEGIN
  v := pg_temp.update_as('01', '01', '{"together_since":"2016-03-12","together_since_precision":"day","anniversary_source":"together_since"}');
  v_id := (v->>'anniversary_reminder_id')::uuid;
  SELECT * INTO v_rem FROM public.reminders WHERE id = v_id;
  IF v_id IS NULL OR v_rem.reminder_type <> 'anniversary' OR v_rem.title <> 'Anniversary'
     OR v_rem.recurrence <> 'yearly' OR v_rem.created_by <> pg_temp.id('01')
     OR v_rem.relationship_id <> pg_temp.rel('01')
     OR v_rem.remind_at <> (public.reminder_next_on(date '2016-03-12', 'yearly', (now() AT TIME ZONE 'utc')::date)::text
                            || ' 00:00:00+00')::timestamptz THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the anniversary reminder is not the next 12 March, yearly, by Yaw: %', row_to_json(v_rem);
  END IF;
  IF (SELECT count(*) FROM public.reminders WHERE relationship_id = pg_temp.rel('01')) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: more than one reminder for one anniversary';
  END IF;

  -- Moved with its date, the same row.
  PERFORM pg_temp.update_as('02', '01', '{"together_since":"2016-07-02","together_since_precision":"day"}');
  IF (SELECT (remind_at AT TIME ZONE 'utc')::date FROM public.reminders WHERE id = v_id)
     <> public.reminder_next_on(date '2016-07-02', 'yearly', (now() AT TIME ZONE 'utc')::date) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the reminder did not follow the date';
  END IF;
  -- A date without its day while the reminder is on it: refused.
  v_msg := pg_temp.update_error('02', '01', '{"together_since":"2016-07-01","together_since_precision":"month"}');
  IF v_msg IS DISTINCT FROM 'couple_profile:anniversary_needs_day' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the anniversary''s date lost its day (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- The guard (plan P-6): the app can't move or delete it; lead times stay
  -- the couple's; any other reminder is untouched by the guard.
  PERFORM pg_temp.as_user(pg_temp.id('02'));
  v_msg := pg_temp.error_of(format('DELETE FROM public.reminders WHERE id = %L', v_id));
  IF v_msg IS DISTINCT FROM 'reminder:follows_about_us' THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: the app deleted the About us reminder (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.error_of(format('UPDATE public.reminders SET remind_at = now() WHERE id = %L', v_id));
  IF v_msg IS DISTINCT FROM 'reminder:follows_about_us' THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: the app moved the About us reminder (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.error_of(format('UPDATE public.reminders SET remind_days_before = ARRAY[0, 7] WHERE id = %L', v_id));
  IF v_msg IS NOT NULL THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: the couple''s lead times were refused (%)', v_msg;
  END IF;
  INSERT INTO public.reminders (relationship_id, created_by, reminder_type, title, remind_at, recurrence)
  VALUES (pg_temp.rel('01'), pg_temp.id('02'), 'birthday', 'Mum', now() + interval '10 days', 'yearly')
  RETURNING id INTO v_other;
  v_msg := pg_temp.error_of(format('DELETE FROM public.reminders WHERE id = %L', v_other));
  RESET ROLE;
  IF v_msg IS NOT NULL OR EXISTS (SELECT 1 FROM public.reminders WHERE id = v_other) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the guard stopped an ordinary reminder''s delete (%)', v_msg;
  END IF;

  -- A ceremony as the source moves the same reminder; leaving Married
  -- takes it with the ceremonies (anniversary off, attributed).
  PERFORM pg_temp.update_as('01', '01', '{"stage":"married","ceremonies":[{"year":2018,"month":12,"day":1,"label":"civil"}],"anniversary_source":"ceremony_1"}');
  IF (SELECT (remind_at AT TIME ZONE 'utc')::date FROM public.reminders WHERE id = v_id)
     <> public.reminder_next_on(date '2018-12-01', 'yearly', (now() AT TIME ZONE 'utc')::date) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the reminder did not move to the ceremony';
  END IF;
  v := pg_temp.update_as('02', '01', '{"stage":"dating"}');
  IF v->>'anniversary_source' <> 'off' OR v->'anniversary_reminder_id' <> 'null'::jsonb
     OR EXISTS (SELECT 1 FROM public.reminders WHERE id = v_id)
     OR v->'changes'->'anniversary'->>'changed_by_first_name' IS DISTINCT FROM NULL
     OR NOT (v->'changes'->'anniversary'->>'changed_by_me')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: leaving Married left the ceremony''s anniversary: %', v;
  END IF;

  -- On again, then "No, thanks": deleted.
  v := pg_temp.update_as('01', '01', '{"anniversary_source":"together_since"}');
  v_id := (v->>'anniversary_reminder_id')::uuid;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the anniversary did not come back';
  END IF;
  v := pg_temp.update_as('01', '01', '{"anniversary_source":"off"}');
  IF EXISTS (SELECT 1 FROM public.reminders WHERE id = v_id) OR v->'anniversary_reminder_id' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: "No, thanks" left the reminder';
  END IF;
END $$;

-- =====================================================================
-- F. The draft (spec §4.2, §4.3 W5): own, Relationship path only, the
--    same validation; kept through a withdrawal and a switch to Just
--    for me (part 2 adds: gone on a switch to Dating). Fixtures 21-24.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_msg text;
  v_n int;
BEGIN
  PERFORM pg_temp.person('21', 'Kojo Inviter');
  PERFORM pg_temp.person('22', 'Efua Other');
  PERFORM pg_temp.person('23', 'Yaa JustMe');
  UPDATE public.users SET path = 'just_me' WHERE id = pg_temp.id('23');
  INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at)
  VALUES (pg_temp.rel('21'), pg_temp.id('21'), 'pending', 'W5DRF1', now() + interval '7 days');

  v := pg_temp.draft_as('21', NULL);
  IF NOT (v->>'draft')::boolean OR v->>'anniversary_source' <> 'off' OR v->'changes' <> '{}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an empty draft reads wrongly: %', v;
  END IF;
  v := pg_temp.draft_as('21', '{"stage":"engaged","living":"long_distance"}');
  IF v->>'stage' <> 'engaged' OR v->>'living' <> 'long_distance' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the draft did not save: %', v;
  END IF;
  v_msg := pg_temp.draft_error('21', '{"ceremonies":[{"year":1999}]}');
  IF v_msg IS DISTINCT FROM 'couple_profile:ceremonies_need_married' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the draft skipped the profile''s validation (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.draft_error('21', '{"favourite":"x"}');
  IF v_msg IS DISTINCT FROM 'couple_profile:unknown_key' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the draft took an unknown key (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.draft_error('23', '{"stage":"dating"}');
  IF v_msg IS DISTINCT FROM 'couple_profile:not_relationship' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a Just-for-me account wrote a draft (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- The shared-phone rule: nobody reads another account's draft.
  v := pg_temp.draft_as('22', NULL);
  IF v->>'stage' IS NOT NULL OR v->>'living' IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another account read Kojo''s draft through the RPC';
  END IF;
  PERFORM pg_temp.as_user(pg_temp.id('22'));
  SELECT count(*) INTO v_n FROM public.couple_profile_drafts WHERE user_id = pg_temp.id('21');
  RESET ROLE;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another account selected Kojo''s draft row';
  END IF;
  PERFORM pg_temp.as_user(pg_temp.id('21'));
  SELECT count(*) INTO v_n FROM public.couple_profile_drafts WHERE user_id = pg_temp.id('21');
  RESET ROLE;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner cannot select their own draft row';
  END IF;

  -- Kept through a withdrawal (the code goes, the answers stay).
  PERFORM pg_temp.as_user(pg_temp.id('21'));
  PERFORM public.withdraw_my_pending_invites();
  RESET ROLE;
  IF NOT EXISTS (SELECT 1 FROM public.couple_profile_drafts WHERE user_id = pg_temp.id('21') AND stage = 'engaged') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: withdrawing the invite deleted the draft';
  END IF;

  -- A switch to Just for me keeps it (unreadable until Relationship again).
  PERFORM public.set_user_path_internal(pg_temp.id('21'), 'just_me');
  IF NOT EXISTS (SELECT 1 FROM public.couple_profile_drafts WHERE user_id = pg_temp.id('21')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a switch to Just for me deleted the draft';
  END IF;
  v_msg := pg_temp.draft_error('21', NULL);
  IF v_msg IS DISTINCT FROM 'couple_profile:not_relationship' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the draft was readable off the Relationship path (got %)', coalesce(v_msg, 'no error');
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'couple_profile_contracts: all held'; END $$;
ROLLBACK;
```

- [ ] **Step 3: Run it to verify it fails**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/couple_profile_contracts.sql 2>&1 | grep ERROR
```

Expected: `ERROR:  CONTRACT VIOLATED: W5 objects are missing`.

- [ ] **Step 4: Write the migration**

Create `supabase/migrations/20261102110000_couple_profiles.sql` with exactly:

```sql
-- Spec 1 W5, migration 10 part 1 of 2 (spec §4.7 #10; plan P-1):
-- couple_profiles.
--   * public.couple_profiles: the shared About us profile of one
--     relationship (spec §4.2), attributed per field (six pairs), read by
--     both members while relationship_chat_open (active, paused, or ended
--     inside the window; not sealed; not archived). Never a type, a score
--     or a label (permanent constraint; couple_profile_contracts.sql
--     section A pins the columns and every function that reads it).
--   * public.couple_profile_drafts: one inviter's answers before linking,
--     per account (the shared-phone rule: nobody's draft reaches another
--     account), with a set_at per field for the adoption order.
--   * get_couple_profile / update_couple_profile (members), and
--     get_my_couple_profile_draft / update_my_couple_profile_draft (own
--     draft, Relationship path only), all validated by one merge,
--     private.couple_profile_merge.
--   * adopt_couple_profile_drafts (no grants): moves the drafts into the
--     shared profile at linking, the inviter's first, the acceptor's
--     filling what is empty. Its caller, accept_relationship_invite_v2, is
--     re-created in part 2 (20261102110100).
--   * sync_anniversary_reminder (no grants): AU6's single source for
--     Together's anniversary reminder, one reminders row per profile.
--   * private.guard_about_us_reminder: a client can't move or delete that
--     row behind About us's back (plan P-6).
--   * couple_profiles_together_signal: every change bumps both phones
--     through the existing together_change_signals (not in the Realtime
--     publication itself).
-- Grants in 20261102110010_couple_profiles_grants.sql; every server-only
-- object is revoked here as well.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS public.couple_profiles (
  relationship_id uuid PRIMARY KEY REFERENCES public.relationships(id) ON DELETE CASCADE,
  together_since date NULL,
  together_since_precision text NULL
    CHECK (together_since_precision IN ('day', 'month', 'year')),
  stage text NULL CHECK (stage IN ('dating', 'engaged', 'married', 'other')),
  stage_words text NULL CHECK (char_length(stage_words) <= 40),
  ceremonies jsonb NOT NULL DEFAULT '[]'::jsonb,
  living text NULL CHECK (living IN ('together', 'apart_nearby', 'long_distance')),
  children text NULL CHECK (children IN ('none', 'yes', 'expecting', 'prefer_not_to_say')),
  child_age_bands text[] NOT NULL DEFAULT '{}'::text[]
    CHECK (child_age_bands <@ ARRAY['under2', '2to5', '6to12', '13to17', '18plus']::text[]),
  anniversary_source text NOT NULL DEFAULT 'off'
    CHECK (anniversary_source IN ('off', 'together_since', 'ceremony_1', 'ceremony_2')),
  anniversary_reminder_id uuid NULL REFERENCES public.reminders(id) ON DELETE SET NULL,
  together_since_changed_by uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  together_since_changed_at timestamptz NULL,
  stage_changed_by uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  stage_changed_at timestamptz NULL,
  ceremonies_changed_by uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  ceremonies_changed_at timestamptz NULL,
  living_changed_by uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  living_changed_at timestamptz NULL,
  children_changed_by uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  children_changed_at timestamptz NULL,
  anniversary_changed_by uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  anniversary_changed_at timestamptz NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT couple_profiles_since_precision
    CHECK ((together_since IS NULL) = (together_since_precision IS NULL)),
  CONSTRAINT couple_profiles_stage_words CHECK (stage_words IS NULL OR stage = 'other'),
  CONSTRAINT couple_profiles_ceremonies_shape CHECK (
    CASE WHEN jsonb_typeof(ceremonies) = 'array'
         THEN jsonb_array_length(ceremonies) <= 2
              AND (jsonb_array_length(ceremonies) = 0 OR stage = 'married')
         ELSE false END),
  CONSTRAINT couple_profiles_bands_need_yes
    CHECK (cardinality(child_age_bands) = 0 OR children = 'yes')
);
CREATE INDEX IF NOT EXISTS couple_profiles_anniversary_reminder_idx
  ON public.couple_profiles (anniversary_reminder_id)
  WHERE anniversary_reminder_id IS NOT NULL;
ALTER TABLE public.couple_profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS couple_profiles_select_members ON public.couple_profiles;
CREATE POLICY couple_profiles_select_members ON public.couple_profiles
  FOR SELECT TO authenticated
  USING (public.relationship_chat_open(relationship_id));
REVOKE ALL ON public.couple_profiles FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS public.couple_profile_drafts (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  together_since date NULL,
  together_since_precision text NULL
    CHECK (together_since_precision IN ('day', 'month', 'year')),
  stage text NULL CHECK (stage IN ('dating', 'engaged', 'married', 'other')),
  stage_words text NULL CHECK (char_length(stage_words) <= 40),
  ceremonies jsonb NOT NULL DEFAULT '[]'::jsonb,
  living text NULL CHECK (living IN ('together', 'apart_nearby', 'long_distance')),
  children text NULL CHECK (children IN ('none', 'yes', 'expecting', 'prefer_not_to_say')),
  child_age_bands text[] NOT NULL DEFAULT '{}'::text[]
    CHECK (child_age_bands <@ ARRAY['under2', '2to5', '6to12', '13to17', '18plus']::text[]),
  anniversary_source text NOT NULL DEFAULT 'off'
    CHECK (anniversary_source IN ('off', 'together_since', 'ceremony_1', 'ceremony_2')),
  together_since_set_at timestamptz NULL,
  stage_set_at timestamptz NULL,
  ceremonies_set_at timestamptz NULL,
  living_set_at timestamptz NULL,
  children_set_at timestamptz NULL,
  anniversary_set_at timestamptz NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT couple_profile_drafts_since_precision
    CHECK ((together_since IS NULL) = (together_since_precision IS NULL)),
  CONSTRAINT couple_profile_drafts_stage_words CHECK (stage_words IS NULL OR stage = 'other'),
  CONSTRAINT couple_profile_drafts_ceremonies_shape CHECK (
    CASE WHEN jsonb_typeof(ceremonies) = 'array'
         THEN jsonb_array_length(ceremonies) <= 2
              AND (jsonb_array_length(ceremonies) = 0 OR stage = 'married')
         ELSE false END),
  CONSTRAINT couple_profile_drafts_bands_need_yes
    CHECK (cardinality(child_age_bands) = 0 OR children = 'yes')
);
ALTER TABLE public.couple_profile_drafts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS couple_profile_drafts_select_own ON public.couple_profile_drafts;
CREATE POLICY couple_profile_drafts_select_own ON public.couple_profile_drafts
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());
REVOKE ALL ON public.couple_profile_drafts FROM PUBLIC, anon, authenticated;

-- A ceremony's full date, or NULL without a month and a day.
CREATE OR REPLACE FUNCTION private.couple_profile_ceremony_date(p_ceremony jsonb)
RETURNS date
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE
           WHEN p_ceremony IS NULL OR jsonb_typeof(p_ceremony) <> 'object'
                OR p_ceremony->'month' IS NULL OR p_ceremony->'day' IS NULL THEN NULL
           ELSE make_date((p_ceremony->>'year')::int, (p_ceremony->>'month')::int,
                          (p_ceremony->>'day')::int)
         END;
$$;
REVOKE ALL ON FUNCTION private.couple_profile_ceremony_date(jsonb) FROM PUBLIC, anon, authenticated, service_role;

-- One attribution for get_couple_profile: who (me, or a first name, never
-- an id) and when; NULL for a field nobody has answered.
CREATE OR REPLACE FUNCTION private.couple_profile_change(p_me uuid, p_by uuid, p_at timestamptz)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT CASE WHEN p_at IS NULL THEN NULL ELSE jsonb_build_object(
           'changed_by_me', p_by IS NOT DISTINCT FROM p_me,
           'changed_by_first_name',
             CASE WHEN p_by IS DISTINCT FROM p_me AND p_by IS NOT NULL
                  THEN private.invite_first_name(p_by) END,
           'changed_at', p_at) END;
$$;
REVOKE ALL ON FUNCTION private.couple_profile_change(uuid, uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;

-- The one validation (spec §3.8 AU1-AU6, §4.3 W5) for the shared profile
-- and the draft alike: [p_state] (every answer key) with [p_patch] applied,
-- normalised, or a refusal. Keys: together_since + together_since_precision
-- (together), stage (+ stage_words), ceremonies, living, children
-- (+ child_age_bands), anniversary_source. Dates: none before 1900, none
-- in the future (a day of slack for the earliest time zone); a month is
-- kept as its 1st, a year as 1 January. Leaving Married clears the
-- ceremonies; a ceremony that goes takes an anniversary on it with it.
CREATE OR REPLACE FUNCTION private.couple_profile_merge(p_state jsonb, p_patch jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_last_day constant date := (now() AT TIME ZONE 'utc')::date + 1;
  v_bands_all constant text[] := ARRAY['under2', '2to5', '6to12', '13to17', '18plus'];
  v_out jsonb := p_state;
  v_key text;
  v_text text;
  v_date date;
  v_precision text;
  v_stage text;
  v_words text;
  v_list jsonb;
  v_item jsonb;
  v_clean jsonb := '[]'::jsonb;
  v_year int;
  v_month int;
  v_day int;
  v_label text;
  v_children text;
  v_bands text[];
  v_source text;
BEGIN
  IF p_patch IS NULL OR jsonb_typeof(p_patch) <> 'object' THEN
    RAISE EXCEPTION 'couple_profile:invalid';
  END IF;
  FOR v_key IN SELECT jsonb_object_keys(p_patch) LOOP
    IF v_key NOT IN ('together_since', 'together_since_precision', 'stage', 'stage_words',
                     'ceremonies', 'living', 'children', 'child_age_bands', 'anniversary_source') THEN
      RAISE EXCEPTION 'couple_profile:unknown_key';
    END IF;
  END LOOP;

  -- AU2: the date and its precision travel together.
  IF p_patch ? 'together_since' OR p_patch ? 'together_since_precision' THEN
    IF coalesce(jsonb_typeof(p_patch->'together_since'), 'null') = 'null' THEN
      IF coalesce(jsonb_typeof(p_patch->'together_since_precision'), 'null') <> 'null' THEN
        RAISE EXCEPTION 'couple_profile:invalid';
      END IF;
      v_out := v_out || '{"together_since": null, "together_since_precision": null}'::jsonb;
    ELSE
      v_text := p_patch->>'together_since';
      v_precision := p_patch->>'together_since_precision';
      IF jsonb_typeof(p_patch->'together_since') <> 'string'
         OR v_text !~ '^\d{4}-\d{2}-\d{2}$'
         OR v_precision IS NULL OR v_precision NOT IN ('day', 'month', 'year') THEN
        RAISE EXCEPTION 'couple_profile:invalid';
      END IF;
      BEGIN
        v_date := v_text::date;
      EXCEPTION WHEN datetime_field_overflow OR invalid_datetime_format THEN
        RAISE EXCEPTION 'couple_profile:invalid';
      END;
      v_date := CASE v_precision
                  WHEN 'month' THEN date_trunc('month', v_date)::date
                  WHEN 'year' THEN date_trunc('year', v_date)::date
                  ELSE v_date END;
      IF v_date < date '1900-01-01' THEN
        RAISE EXCEPTION 'couple_profile:invalid';
      END IF;
      IF v_date > v_last_day THEN
        RAISE EXCEPTION 'couple_profile:future_date';
      END IF;
      v_out := v_out || jsonb_build_object('together_since', v_date,
                                           'together_since_precision', v_precision);
    END IF;
  END IF;

  -- AU1: the stage, and the couple's own words only for "Something else".
  IF p_patch ? 'stage' OR p_patch ? 'stage_words' THEN
    v_stage := CASE WHEN p_patch ? 'stage' THEN p_patch->>'stage' ELSE v_out->>'stage' END;
    IF v_stage IS NOT NULL AND v_stage NOT IN ('dating', 'engaged', 'married', 'other') THEN
      RAISE EXCEPTION 'couple_profile:invalid';
    END IF;
    v_words := CASE WHEN p_patch ? 'stage_words' THEN p_patch->>'stage_words'
                    ELSE v_out->>'stage_words' END;
    v_words := nullif(btrim(regexp_replace(coalesce(v_words, ''), '[[:cntrl:]]', ' ', 'g')), '');
    IF v_stage IS DISTINCT FROM 'other' THEN
      v_words := NULL;
    END IF;
    IF char_length(v_words) > 40 THEN
      RAISE EXCEPTION 'couple_profile:invalid';
    END IF;
    v_out := v_out || jsonb_build_object('stage', v_stage, 'stage_words', v_words);
    IF v_stage IS DISTINCT FROM 'married' AND NOT p_patch ? 'ceremonies' THEN
      v_out := jsonb_set(v_out, '{ceremonies}', '[]'::jsonb);
    END IF;
  END IF;

  -- AU3: at most two ceremonies, each a year with an optional month, day
  -- and label.
  IF p_patch ? 'ceremonies' THEN
    v_list := p_patch->'ceremonies';
    IF jsonb_typeof(v_list) = 'null' THEN
      v_list := '[]'::jsonb;
    END IF;
    IF jsonb_typeof(v_list) <> 'array' THEN
      RAISE EXCEPTION 'couple_profile:invalid';
    END IF;
    IF jsonb_array_length(v_list) > 2 THEN
      RAISE EXCEPTION 'couple_profile:too_many_ceremonies';
    END IF;
    FOR v_item IN SELECT e.value FROM jsonb_array_elements(v_list) AS e LOOP
      IF jsonb_typeof(v_item) <> 'object'
         OR EXISTS (SELECT 1 FROM jsonb_object_keys(v_item) AS k(name)
                     WHERE k.name NOT IN ('year', 'month', 'day', 'label'))
         OR jsonb_typeof(v_item->'year') IS DISTINCT FROM 'number'
         OR (v_item->>'year') !~ '^\d{4}$'
         OR coalesce(jsonb_typeof(v_item->'month'), 'null') NOT IN ('null', 'number')
         OR coalesce(v_item->>'month', '1') !~ '^\d{1,2}$'
         OR coalesce(jsonb_typeof(v_item->'day'), 'null') NOT IN ('null', 'number')
         OR coalesce(v_item->>'day', '1') !~ '^\d{1,2}$'
         OR coalesce(jsonb_typeof(v_item->'label'), 'null') NOT IN ('null', 'string') THEN
        RAISE EXCEPTION 'couple_profile:invalid';
      END IF;
      v_year := (v_item->>'year')::int;
      v_month := (v_item->>'month')::int;
      v_day := (v_item->>'day')::int;
      v_label := v_item->>'label';
      IF v_year < 1900 OR (v_month IS NOT NULL AND v_month NOT BETWEEN 1 AND 12)
         OR (v_day IS NOT NULL AND v_month IS NULL)
         OR (v_label IS NOT NULL AND v_label NOT IN ('customary', 'church', 'mosque', 'civil', 'other')) THEN
        RAISE EXCEPTION 'couple_profile:invalid';
      END IF;
      BEGIN
        v_date := make_date(v_year, coalesce(v_month, 1), coalesce(v_day, 1));
      EXCEPTION WHEN datetime_field_overflow OR invalid_datetime_format THEN
        RAISE EXCEPTION 'couple_profile:invalid';
      END;
      IF v_date > v_last_day THEN
        RAISE EXCEPTION 'couple_profile:future_date';
      END IF;
      v_clean := v_clean || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
        'year', v_year, 'month', v_month, 'day', v_day, 'label', v_label)));
    END LOOP;
    v_out := jsonb_set(v_out, '{ceremonies}', v_clean);
  END IF;
  IF jsonb_array_length(v_out->'ceremonies') > 0
     AND (v_out->>'stage') IS DISTINCT FROM 'married' THEN
    RAISE EXCEPTION 'couple_profile:ceremonies_need_married';
  END IF;

  -- AU4.
  IF p_patch ? 'living' THEN
    v_text := p_patch->>'living';
    IF v_text IS NOT NULL AND v_text NOT IN ('together', 'apart_nearby', 'long_distance') THEN
      RAISE EXCEPTION 'couple_profile:invalid';
    END IF;
    v_out := v_out || jsonb_build_object('living', v_text);
  END IF;

  -- AU5: age bands only with "Yes"; no names, no counts.
  IF p_patch ? 'children' OR p_patch ? 'child_age_bands' THEN
    v_children := CASE WHEN p_patch ? 'children' THEN p_patch->>'children'
                       ELSE v_out->>'children' END;
    IF v_children IS NOT NULL
       AND v_children NOT IN ('none', 'yes', 'expecting', 'prefer_not_to_say') THEN
      RAISE EXCEPTION 'couple_profile:invalid';
    END IF;
    IF p_patch ? 'child_age_bands' THEN
      v_list := p_patch->'child_age_bands';
      IF jsonb_typeof(v_list) = 'null' THEN
        v_list := '[]'::jsonb;
      END IF;
      IF jsonb_typeof(v_list) <> 'array'
         OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_list) AS e
                     WHERE jsonb_typeof(e.value) <> 'string'
                        OR NOT (e.value #>> '{}') = ANY (v_bands_all)) THEN
        RAISE EXCEPTION 'couple_profile:invalid';
      END IF;
      SELECT coalesce(array_agg(b.band ORDER BY array_position(v_bands_all, b.band)), '{}'::text[])
        INTO v_bands
        FROM (SELECT DISTINCT e.value #>> '{}' AS band FROM jsonb_array_elements(v_list) AS e) AS b;
      IF cardinality(v_bands) > 0 AND v_children IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'couple_profile:bands_need_yes';
      END IF;
    ELSE
      v_bands := ARRAY(SELECT jsonb_array_elements_text(coalesce(v_out->'child_age_bands', '[]'::jsonb)));
    END IF;
    IF v_children IS DISTINCT FROM 'yes' THEN
      v_bands := '{}'::text[];
    END IF;
    v_out := v_out || jsonb_build_object('children', v_children, 'child_age_bands', to_jsonb(v_bands));
  END IF;

  -- AU6: one anniversary source, and it needs a full date.
  IF p_patch ? 'anniversary_source' THEN
    v_source := coalesce(p_patch->>'anniversary_source', 'off');
    IF v_source NOT IN ('off', 'together_since', 'ceremony_1', 'ceremony_2') THEN
      RAISE EXCEPTION 'couple_profile:invalid';
    END IF;
    v_out := jsonb_set(v_out, '{anniversary_source}', to_jsonb(v_source));
  END IF;
  v_source := v_out->>'anniversary_source';
  IF (v_source = 'ceremony_1' AND jsonb_array_length(v_out->'ceremonies') < 1)
     OR (v_source = 'ceremony_2' AND jsonb_array_length(v_out->'ceremonies') < 2) THEN
    IF p_patch ? 'anniversary_source' THEN
      RAISE EXCEPTION 'couple_profile:invalid';
    END IF;
    v_out := jsonb_set(v_out, '{anniversary_source}', '"off"'::jsonb);
    v_source := 'off';
  END IF;
  IF (v_source = 'together_since' AND (v_out->>'together_since_precision') IS DISTINCT FROM 'day')
     OR (v_source = 'ceremony_1' AND private.couple_profile_ceremony_date(v_out->'ceremonies'->0) IS NULL)
     OR (v_source = 'ceremony_2' AND private.couple_profile_ceremony_date(v_out->'ceremonies'->1) IS NULL) THEN
    RAISE EXCEPTION 'couple_profile:anniversary_needs_day';
  END IF;
  RETURN v_out;
END;
$$;
REVOKE ALL ON FUNCTION private.couple_profile_merge(jsonb, jsonb) FROM PUBLIC, anon, authenticated, service_role;

-- The shared profile, for a member while relationship_chat_open (spec
-- §4.3 W5). Values, per-field attribution as a first name or "me" (never
-- an id), read_only unless active, and the window's end for the read-only
-- line. No suggested dates (review I-12).
CREATE OR REPLACE FUNCTION public.get_couple_profile(p_relationship_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid constant uuid := auth.uid();
  v_rel public.relationships%ROWTYPE;
  v public.couple_profiles%ROWTYPE;
BEGIN
  IF v_uid IS NULL OR p_relationship_id IS NULL
     OR NOT public.relationship_chat_open_for(p_relationship_id, v_uid) THEN
    RAISE EXCEPTION 'couple_profile:not_found';
  END IF;
  SELECT * INTO v_rel FROM public.relationships AS r WHERE r.id = p_relationship_id;
  SELECT * INTO v FROM public.couple_profiles AS cp WHERE cp.relationship_id = p_relationship_id;
  RETURN jsonb_build_object(
    'draft', false,
    'read_only', v_rel.status <> 'active',
    'read_until', CASE v_rel.status
                    WHEN 'paused' THEN v_rel.paused_at + interval '30 days'
                    WHEN 'ended' THEN v_rel.ended_at + interval '30 days' END,
    'together_since', v.together_since,
    'together_since_precision', v.together_since_precision,
    'stage', v.stage,
    'stage_words', v.stage_words,
    'ceremonies', coalesce(v.ceremonies, '[]'::jsonb),
    'living', v.living,
    'children', v.children,
    'child_age_bands', to_jsonb(coalesce(v.child_age_bands, '{}'::text[])),
    'anniversary_source', coalesce(v.anniversary_source, 'off'),
    'anniversary_reminder_id', v.anniversary_reminder_id,
    'changes', jsonb_strip_nulls(jsonb_build_object(
      'together_since', private.couple_profile_change(v_uid, v.together_since_changed_by, v.together_since_changed_at),
      'stage', private.couple_profile_change(v_uid, v.stage_changed_by, v.stage_changed_at),
      'ceremonies', private.couple_profile_change(v_uid, v.ceremonies_changed_by, v.ceremonies_changed_at),
      'living', private.couple_profile_change(v_uid, v.living_changed_by, v.living_changed_at),
      'children', private.couple_profile_change(v_uid, v.children_changed_by, v.children_changed_at),
      'anniversary', private.couple_profile_change(v_uid, v.anniversary_changed_by, v.anniversary_changed_at))));
END;
$$;

-- AU6's single source (spec §4.3 W5): 'off' (or a source without a full
-- date) removes the linked reminder; otherwise one yearly "Anniversary"
-- reminders row, on the next occurrence's civil date (midnight UTC, the
-- reminders convention: the generator tells each partner at 09:00 in
-- their own zone; plan P-5), made by whoever chose it. Writes only what
-- changed, so a no-op edit bumps nothing.
CREATE OR REPLACE FUNCTION public.sync_anniversary_reminder(p_relationship_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v public.couple_profiles%ROWTYPE;
  v_date date;
  v_at timestamptz;
  v_id uuid;
BEGIN
  SELECT * INTO v FROM public.couple_profiles AS cp
   WHERE cp.relationship_id = p_relationship_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN;
  END IF;
  v_date := CASE v.anniversary_source
              WHEN 'together_since' THEN
                CASE WHEN v.together_since_precision = 'day' THEN v.together_since END
              WHEN 'ceremony_1' THEN private.couple_profile_ceremony_date(v.ceremonies->0)
              WHEN 'ceremony_2' THEN private.couple_profile_ceremony_date(v.ceremonies->1)
            END;
  IF v_date IS NULL THEN
    IF v.anniversary_reminder_id IS NOT NULL THEN
      DELETE FROM public.reminders AS r WHERE r.id = v.anniversary_reminder_id;
    END IF;
    RETURN;
  END IF;
  v_at := (public.reminder_next_on(v_date, 'yearly', (now() AT TIME ZONE 'utc')::date)::text
           || ' 00:00:00+00')::timestamptz;
  IF v.anniversary_reminder_id IS NOT NULL THEN
    UPDATE public.reminders AS r
       SET remind_at = v_at, title = 'Anniversary', reminder_type = 'anniversary', recurrence = 'yearly'
     WHERE r.id = v.anniversary_reminder_id
       AND (r.remind_at, r.title, r.reminder_type, r.recurrence)
           IS DISTINCT FROM (v_at, 'Anniversary', 'anniversary', 'yearly');
    IF FOUND OR EXISTS (SELECT 1 FROM public.reminders AS r WHERE r.id = v.anniversary_reminder_id) THEN
      RETURN;
    END IF;
  END IF;
  INSERT INTO public.reminders (relationship_id, created_by, reminder_type, title, remind_at, recurrence)
  SELECT p_relationship_id, coalesce(v.anniversary_changed_by, auth.uid(), r.user_a),
         'anniversary', 'Anniversary', v_at, 'yearly'
    FROM public.relationships AS r WHERE r.id = p_relationship_id
  RETURNING id INTO v_id;
  UPDATE public.couple_profiles AS cp SET anniversary_reminder_id = v_id
   WHERE cp.relationship_id = p_relationship_id;
END;
$$;

-- AU1-AU6 written by a member of an active, non-archived relationship
-- (spec §4.3 W5): paused and inside the ending window it is read-only.
-- Each changed field records who and when; leaving Married clears the
-- ceremonies, attributed like any change. Returns the new profile.
CREATE OR REPLACE FUNCTION public.update_couple_profile(p_relationship_id uuid, p_patch jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid constant uuid := auth.uid();
  v_now constant timestamptz := now();
  v_rel public.relationships%ROWTYPE;
  v public.couple_profiles%ROWTYPE;
  v_old jsonb;
  v_new jsonb;
BEGIN
  IF v_uid IS NULL OR p_relationship_id IS NULL
     OR NOT public.relationship_chat_open_for(p_relationship_id, v_uid) THEN
    RAISE EXCEPTION 'couple_profile:not_found';
  END IF;
  SELECT * INTO v_rel FROM public.relationships AS r WHERE r.id = p_relationship_id;
  IF v_rel.status <> 'active' THEN
    RAISE EXCEPTION 'couple_profile:read_only';
  END IF;

  SELECT * INTO v FROM public.couple_profiles AS cp
   WHERE cp.relationship_id = p_relationship_id FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO public.couple_profiles (relationship_id) VALUES (p_relationship_id)
    ON CONFLICT (relationship_id) DO NOTHING;
    SELECT * INTO v FROM public.couple_profiles AS cp
     WHERE cp.relationship_id = p_relationship_id FOR UPDATE;
  END IF;

  v_old := jsonb_build_object(
    'together_since', v.together_since, 'together_since_precision', v.together_since_precision,
    'stage', v.stage, 'stage_words', v.stage_words, 'ceremonies', v.ceremonies,
    'living', v.living, 'children', v.children, 'child_age_bands', to_jsonb(v.child_age_bands),
    'anniversary_source', v.anniversary_source);
  v_new := private.couple_profile_merge(v_old, p_patch);

  IF v_new IS DISTINCT FROM v_old THEN
    UPDATE public.couple_profiles AS cp
       SET together_since = (v_new->>'together_since')::date,
           together_since_precision = v_new->>'together_since_precision',
           stage = v_new->>'stage',
           stage_words = v_new->>'stage_words',
           ceremonies = v_new->'ceremonies',
           living = v_new->>'living',
           children = v_new->>'children',
           child_age_bands = ARRAY(SELECT jsonb_array_elements_text(v_new->'child_age_bands')),
           anniversary_source = v_new->>'anniversary_source',
           together_since_changed_by = CASE WHEN (v_new->'together_since', v_new->'together_since_precision')
                                                 IS DISTINCT FROM (v_old->'together_since', v_old->'together_since_precision')
                                            THEN v_uid ELSE cp.together_since_changed_by END,
           together_since_changed_at = CASE WHEN (v_new->'together_since', v_new->'together_since_precision')
                                                 IS DISTINCT FROM (v_old->'together_since', v_old->'together_since_precision')
                                            THEN v_now ELSE cp.together_since_changed_at END,
           stage_changed_by = CASE WHEN (v_new->'stage', v_new->'stage_words')
                                        IS DISTINCT FROM (v_old->'stage', v_old->'stage_words')
                                   THEN v_uid ELSE cp.stage_changed_by END,
           stage_changed_at = CASE WHEN (v_new->'stage', v_new->'stage_words')
                                        IS DISTINCT FROM (v_old->'stage', v_old->'stage_words')
                                   THEN v_now ELSE cp.stage_changed_at END,
           ceremonies_changed_by = CASE WHEN v_new->'ceremonies' IS DISTINCT FROM v_old->'ceremonies'
                                        THEN v_uid ELSE cp.ceremonies_changed_by END,
           ceremonies_changed_at = CASE WHEN v_new->'ceremonies' IS DISTINCT FROM v_old->'ceremonies'
                                        THEN v_now ELSE cp.ceremonies_changed_at END,
           living_changed_by = CASE WHEN v_new->'living' IS DISTINCT FROM v_old->'living'
                                    THEN v_uid ELSE cp.living_changed_by END,
           living_changed_at = CASE WHEN v_new->'living' IS DISTINCT FROM v_old->'living'
                                    THEN v_now ELSE cp.living_changed_at END,
           children_changed_by = CASE WHEN (v_new->'children', v_new->'child_age_bands')
                                           IS DISTINCT FROM (v_old->'children', v_old->'child_age_bands')
                                      THEN v_uid ELSE cp.children_changed_by END,
           children_changed_at = CASE WHEN (v_new->'children', v_new->'child_age_bands')
                                           IS DISTINCT FROM (v_old->'children', v_old->'child_age_bands')
                                      THEN v_now ELSE cp.children_changed_at END,
           anniversary_changed_by = CASE WHEN v_new->'anniversary_source' IS DISTINCT FROM v_old->'anniversary_source'
                                         THEN v_uid ELSE cp.anniversary_changed_by END,
           anniversary_changed_at = CASE WHEN v_new->'anniversary_source' IS DISTINCT FROM v_old->'anniversary_source'
                                         THEN v_now ELSE cp.anniversary_changed_at END,
           updated_at = v_now
     WHERE cp.relationship_id = p_relationship_id;
  END IF;
  PERFORM public.sync_anniversary_reminder(p_relationship_id);
  RETURN public.get_couple_profile(p_relationship_id);
END;
$$;

-- The caller's own draft (spec §4.3 W5): the same answers as the shared
-- profile, no attribution (only its owner ever sees it), Relationship path
-- only.
CREATE OR REPLACE FUNCTION public.get_my_couple_profile_draft()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid constant uuid := auth.uid();
  v public.couple_profile_drafts%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'couple_profile:not_found';
  END IF;
  IF (SELECT u.path FROM public.users AS u WHERE u.id = v_uid) IS DISTINCT FROM 'relationship' THEN
    RAISE EXCEPTION 'couple_profile:not_relationship';
  END IF;
  SELECT * INTO v FROM public.couple_profile_drafts AS d WHERE d.user_id = v_uid;
  RETURN jsonb_build_object(
    'draft', true,
    'read_only', false,
    'read_until', NULL,
    'together_since', v.together_since,
    'together_since_precision', v.together_since_precision,
    'stage', v.stage,
    'stage_words', v.stage_words,
    'ceremonies', coalesce(v.ceremonies, '[]'::jsonb),
    'living', v.living,
    'children', v.children,
    'child_age_bands', to_jsonb(coalesce(v.child_age_bands, '{}'::text[])),
    'anniversary_source', coalesce(v.anniversary_source, 'off'),
    'anniversary_reminder_id', NULL,
    'changes', '{}'::jsonb);
END;
$$;

-- Writes the caller's draft with the shared profile's validation. The
-- users row is read FOR SHARE first, the order set_user_path_internal and
-- the accept use (users, then the draft), so a switch to Dating can't
-- leave a draft behind.
CREATE OR REPLACE FUNCTION public.update_my_couple_profile_draft(p_patch jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid constant uuid := auth.uid();
  v_now constant timestamptz := now();
  v_path text;
  v public.couple_profile_drafts%ROWTYPE;
  v_old jsonb;
  v_new jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'couple_profile:not_found';
  END IF;
  SELECT u.path INTO v_path FROM public.users AS u WHERE u.id = v_uid FOR SHARE;
  IF v_path IS DISTINCT FROM 'relationship' THEN
    RAISE EXCEPTION 'couple_profile:not_relationship';
  END IF;
  INSERT INTO public.couple_profile_drafts (user_id) VALUES (v_uid)
  ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO v FROM public.couple_profile_drafts AS d WHERE d.user_id = v_uid FOR UPDATE;

  v_old := jsonb_build_object(
    'together_since', v.together_since, 'together_since_precision', v.together_since_precision,
    'stage', v.stage, 'stage_words', v.stage_words, 'ceremonies', v.ceremonies,
    'living', v.living, 'children', v.children, 'child_age_bands', to_jsonb(v.child_age_bands),
    'anniversary_source', v.anniversary_source);
  v_new := private.couple_profile_merge(v_old, p_patch);

  IF v_new IS DISTINCT FROM v_old OR (p_patch ? 'anniversary_source' AND v.anniversary_set_at IS NULL) THEN
    UPDATE public.couple_profile_drafts AS d
       SET together_since = (v_new->>'together_since')::date,
           together_since_precision = v_new->>'together_since_precision',
           stage = v_new->>'stage',
           stage_words = v_new->>'stage_words',
           ceremonies = v_new->'ceremonies',
           living = v_new->>'living',
           children = v_new->>'children',
           child_age_bands = ARRAY(SELECT jsonb_array_elements_text(v_new->'child_age_bands')),
           anniversary_source = v_new->>'anniversary_source',
           together_since_set_at = CASE WHEN (v_new->'together_since', v_new->'together_since_precision')
                                             IS DISTINCT FROM (v_old->'together_since', v_old->'together_since_precision')
                                        THEN v_now ELSE d.together_since_set_at END,
           stage_set_at = CASE WHEN (v_new->'stage', v_new->'stage_words')
                                    IS DISTINCT FROM (v_old->'stage', v_old->'stage_words')
                               THEN v_now ELSE d.stage_set_at END,
           ceremonies_set_at = CASE WHEN v_new->'ceremonies' IS DISTINCT FROM v_old->'ceremonies'
                                    THEN v_now ELSE d.ceremonies_set_at END,
           living_set_at = CASE WHEN v_new->'living' IS DISTINCT FROM v_old->'living'
                                THEN v_now ELSE d.living_set_at END,
           children_set_at = CASE WHEN (v_new->'children', v_new->'child_age_bands')
                                       IS DISTINCT FROM (v_old->'children', v_old->'child_age_bands')
                                  THEN v_now ELSE d.children_set_at END,
           -- "No, thanks" is an answer too (it beats the partner's draft at
           -- linking), so choosing it the first time is recorded.
           anniversary_set_at = CASE WHEN v_new->'anniversary_source' IS DISTINCT FROM v_old->'anniversary_source'
                                          OR (p_patch ? 'anniversary_source' AND d.anniversary_set_at IS NULL)
                                     THEN v_now ELSE d.anniversary_set_at END,
           updated_at = v_now
     WHERE d.user_id = v_uid;
  END IF;
  RETURN public.get_my_couple_profile_draft();
END;
$$;

-- Linking (spec §4.3 W5, §3.8 R4): the inviter's draft first, the
-- acceptor's filling every field the inviter left empty; each field keeps
-- its owner and the time they set it. A merge that would break a rule
-- (ceremonies without Married, an anniversary without a full date) drops
-- the dependent field rather than refusing the link. Both drafts go.
-- Called only by accept_relationship_invite_v2, after both users rows are
-- locked (users, then the drafts, the order of every draft writer).
CREATE OR REPLACE FUNCTION public.adopt_couple_profile_drafts(p_relationship_id uuid, p_inviter uuid, p_acceptor uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  vi public.couple_profile_drafts%ROWTYPE;
  va public.couple_profile_drafts%ROWTYPE;
  v public.couple_profiles%ROWTYPE;
  v_date date;
BEGIN
  PERFORM 1 FROM public.couple_profile_drafts AS d
   WHERE d.user_id IN (p_inviter, p_acceptor) ORDER BY d.user_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN;
  END IF;
  SELECT * INTO vi FROM public.couple_profile_drafts AS d WHERE d.user_id = p_inviter;
  SELECT * INTO va FROM public.couple_profile_drafts AS d WHERE d.user_id = p_acceptor;

  v.relationship_id := p_relationship_id;
  IF vi.together_since IS NOT NULL THEN
    v.together_since := vi.together_since; v.together_since_precision := vi.together_since_precision;
    v.together_since_changed_by := p_inviter; v.together_since_changed_at := vi.together_since_set_at;
  ELSIF va.together_since IS NOT NULL THEN
    v.together_since := va.together_since; v.together_since_precision := va.together_since_precision;
    v.together_since_changed_by := p_acceptor; v.together_since_changed_at := va.together_since_set_at;
  END IF;
  IF vi.stage IS NOT NULL THEN
    v.stage := vi.stage; v.stage_words := vi.stage_words;
    v.stage_changed_by := p_inviter; v.stage_changed_at := vi.stage_set_at;
  ELSIF va.stage IS NOT NULL THEN
    v.stage := va.stage; v.stage_words := va.stage_words;
    v.stage_changed_by := p_acceptor; v.stage_changed_at := va.stage_set_at;
  END IF;
  v.ceremonies := '[]'::jsonb;
  IF v.stage = 'married' THEN
    IF jsonb_array_length(coalesce(vi.ceremonies, '[]'::jsonb)) > 0 AND vi.stage = 'married' THEN
      v.ceremonies := vi.ceremonies;
      v.ceremonies_changed_by := p_inviter; v.ceremonies_changed_at := vi.ceremonies_set_at;
    ELSIF jsonb_array_length(coalesce(va.ceremonies, '[]'::jsonb)) > 0 AND va.stage = 'married' THEN
      v.ceremonies := va.ceremonies;
      v.ceremonies_changed_by := p_acceptor; v.ceremonies_changed_at := va.ceremonies_set_at;
    END IF;
  END IF;
  IF vi.living IS NOT NULL THEN
    v.living := vi.living; v.living_changed_by := p_inviter; v.living_changed_at := vi.living_set_at;
  ELSIF va.living IS NOT NULL THEN
    v.living := va.living; v.living_changed_by := p_acceptor; v.living_changed_at := va.living_set_at;
  END IF;
  v.child_age_bands := '{}'::text[];
  IF vi.children IS NOT NULL THEN
    v.children := vi.children; v.child_age_bands := vi.child_age_bands;
    v.children_changed_by := p_inviter; v.children_changed_at := vi.children_set_at;
  ELSIF va.children IS NOT NULL THEN
    v.children := va.children; v.child_age_bands := va.child_age_bands;
    v.children_changed_by := p_acceptor; v.children_changed_at := va.children_set_at;
  END IF;
  v.anniversary_source := 'off';
  IF vi.anniversary_set_at IS NOT NULL THEN
    v.anniversary_source := vi.anniversary_source;
    v.anniversary_changed_by := p_inviter; v.anniversary_changed_at := vi.anniversary_set_at;
  ELSIF va.anniversary_set_at IS NOT NULL THEN
    v.anniversary_source := va.anniversary_source;
    v.anniversary_changed_by := p_acceptor; v.anniversary_changed_at := va.anniversary_set_at;
  END IF;
  v_date := CASE v.anniversary_source
              WHEN 'together_since' THEN
                CASE WHEN v.together_since_precision = 'day' THEN v.together_since END
              WHEN 'ceremony_1' THEN private.couple_profile_ceremony_date(v.ceremonies->0)
              WHEN 'ceremony_2' THEN private.couple_profile_ceremony_date(v.ceremonies->1)
            END;
  IF v.anniversary_source <> 'off' AND v_date IS NULL THEN
    v.anniversary_source := 'off';
    v.anniversary_changed_by := NULL; v.anniversary_changed_at := NULL;
  END IF;
  v.updated_at := now();

  INSERT INTO public.couple_profiles SELECT (v).*
  ON CONFLICT (relationship_id) DO NOTHING;
  DELETE FROM public.couple_profile_drafts AS d WHERE d.user_id IN (p_inviter, p_acceptor);
  PERFORM public.sync_anniversary_reminder(p_relationship_id);
END;
$$;

-- Plan P-6: the anniversary reminder follows About us. A client (the app
-- or a direct call) can't delete it or change its date, title, type,
-- recurrence, relationship or maker; About us does (definer functions
-- pass). Lead times and the note stay the couple's.
CREATE OR REPLACE FUNCTION private.guard_about_us_reminder()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon')
     OR NOT EXISTS (SELECT 1 FROM public.couple_profiles AS cp
                     WHERE cp.anniversary_reminder_id = OLD.id) THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
  END IF;
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'reminder:follows_about_us';
  END IF;
  IF (NEW.reminder_type, NEW.title, NEW.remind_at, NEW.recurrence, NEW.relationship_id, NEW.created_by)
     IS DISTINCT FROM (OLD.reminder_type, OLD.title, OLD.remind_at, OLD.recurrence, OLD.relationship_id, OLD.created_by) THEN
    RAISE EXCEPTION 'reminder:follows_about_us';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.guard_about_us_reminder() FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS reminders_guard_about_us ON public.reminders;
CREATE TRIGGER reminders_guard_about_us
  BEFORE UPDATE OR DELETE ON public.reminders
  FOR EACH ROW EXECUTE FUNCTION private.guard_about_us_reminder();

DROP TRIGGER IF EXISTS couple_profiles_together_signal ON public.couple_profiles;
CREATE TRIGGER couple_profiles_together_signal
  AFTER INSERT OR UPDATE OR DELETE ON public.couple_profiles
  FOR EACH ROW EXECUTE FUNCTION public.bump_together_signal();

REVOKE ALL ON FUNCTION public.get_couple_profile(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_couple_profile(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_couple_profile_draft() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_my_couple_profile_draft(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.adopt_couple_profile_drafts(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.sync_anniversary_reminder(uuid) FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
```

- [ ] **Step 5: Write the grants twin**

Create `supabase/migrations/20261102110010_couple_profiles_grants.sql` with exactly:

```sql
-- Spec 1 W5: grants for 20261102110000_couple_profiles.sql. The shared
-- profile and the draft are read through their RPCs (and, under RLS,
-- directly: members while relationship_chat_open, the owner for a draft);
-- every write is a definer function. The service role keeps DML on both
-- tables. The merge, the attribution, the ceremony date, the adoption,
-- the anniversary sync and the reminder guard are server-only.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.couple_profiles FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.couple_profile_drafts FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.couple_profiles TO authenticated;
GRANT SELECT ON public.couple_profile_drafts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.couple_profiles TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.couple_profile_drafts TO service_role;
REVOKE ALL ON FUNCTION private.couple_profile_ceremony_date(jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.couple_profile_change(uuid, uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.couple_profile_merge(jsonb, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.guard_about_us_reminder() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.adopt_couple_profile_drafts(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.sync_anniversary_reminder(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_couple_profile(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_couple_profile(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_couple_profile_draft() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_my_couple_profile_draft(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_couple_profile(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_couple_profile(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_couple_profile_draft() TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_my_couple_profile_draft(jsonb) TO authenticated;
COMMIT;
```

- [ ] **Step 6: Apply both twice, then run the contract**

```bash
for i in 1 2; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261102110000_couple_profiles.sql > /dev/null; echo "migration exit=$?"
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261102110010_couple_profiles_grants.sql > /dev/null; echo "grants exit=$?"
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/couple_profile_contracts.sql 2>&1 | tail -1
```

Expected: `migration exit=0` and `grants exit=0` twice, with psql's NOTICE lines on stderr (`… does not exist, skipping` on the first run, `… already exists, skipping` on the second), then `psql:supabase/tests/couple_profile_contracts.sql:703: NOTICE:  couple_profile_contracts: all held`.

- [ ] **Step 7: Mutation checks (each must turn the contract red with the message quoted)**

```bash
M=supabase/migrations/20261102110000_couple_profiles.sql
G=supabase/migrations/20261102110010_couple_profiles_grants.sql
C=supabase/tests/couple_profile_contracts.sql
D=.superpowers/sdd/2026-11-02-spec1-w5
python3 -I - "$M" "$D" <<'EOF'
import pathlib, sys
m = pathlib.Path(sys.argv[1]).read_text()
d = pathlib.Path(sys.argv[2])
muts = {
  'read_only': ("  IF v_rel.status <> 'active' THEN\n    RAISE EXCEPTION 'couple_profile:read_only';\n", "  IF v_rel.status NOT IN ('active', 'paused') THEN\n    RAISE EXCEPTION 'couple_profile:read_only';\n"),
  'bands': ("      IF cardinality(v_bands) > 0 AND v_children IS DISTINCT FROM 'yes' THEN\n        RAISE EXCEPTION 'couple_profile:bands_need_yes';\n      END IF;\n", ""),
  'needs_day': ("    RAISE EXCEPTION 'couple_profile:anniversary_needs_day';\n", "    NULL;\n"),
  'attribution': ("           living_changed_by = CASE WHEN v_new->'living' IS DISTINCT FROM v_old->'living'\n                                    THEN v_uid ELSE cp.living_changed_by END,\n", "           living_changed_by = v_uid,\n"),
  'guard': ("  IF current_user NOT IN ('authenticated', 'anon')\n     OR NOT EXISTS", "  IF true\n     OR NOT EXISTS"),
  'first_name': ("                  THEN private.invite_first_name(p_by) END,\n", "                  THEN p_by::text END,\n"),
}
for name, (a, b) in muts.items():
    assert m.count(a) == 1, name
    (d / f"mut_{name}.sql").write_text(m.replace(a, b))
print('mutants written')
EOF
for m in read_only bands needs_day attribution guard first_name; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $D/mut_$m.sql -f $G > /dev/null 2>&1
  echo "$m: $(psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $C 2>&1 | grep ERROR | sed -E 's/^psql:[^ ]* //' | cut -c1-150)"
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $M -f $G > /dev/null 2>&1
done
# Never a type or score (§7.4 "Add a function that reads couple_profiles into a label"), and a column beyond the spec:
echo "type: $(psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -c 'BEGIN' -c 'ALTER TABLE public.couple_profiles ADD COLUMN couple_type text' -f $C 2>&1 | grep ERROR | sed -E 's/^psql:[^ ]* //' | cut -c1-110)"
echo "label: $(psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -c 'BEGIN' -c "CREATE FUNCTION public.couple_label(p uuid) RETURNS text LANGUAGE sql AS \$\$ SELECT CASE WHEN stage = 'married' THEN 'Traditional' ELSE 'Modern' END FROM public.couple_profiles WHERE relationship_id = p \$\$" -f $C 2>&1 | grep ERROR | sed -E 's/^psql:[^ ]* //' | cut -c1-150)"
psql -X -d attune_spec3a -Atc "select to_regprocedure('public.couple_label(uuid)') is null, (select count(*) from information_schema.columns where table_name = 'couple_profiles' and column_name = 'couple_type')"
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $C 2>&1 | tail -1
rm $D/mut_read_only.sql $D/mut_bands.sql $D/mut_needs_day.sql $D/mut_attribution.sql $D/mut_guard.sql $D/mut_first_name.sql
```

Expected: `mutants written`, then:
- `read_only`: `ERROR:  CONTRACT VIOLATED: a paused profile was written (got no error)`
- `bands`: `ERROR:  CONTRACT VIOLATED: {"children":"none","child_age_bands":["2to5"]} answered no error (expected couple_profile:bands_need_yes)`
- `needs_day`: `ERROR:  CONTRACT VIOLATED: {"anniversary_source":"together_since"} answered no error (expected couple_profile:anniversary_needs_day)`
- `attribution`: `ERROR:  CONTRACT VIOLATED: an edit of one field re-attributed another`
- `guard` (P-6): `ERROR:  CONTRACT VIOLATED: the app deleted the About us reminder (got no error)`
- `first_name` (never a raw id): `ERROR:  CONTRACT VIOLATED: attribution per field reads wrongly for Ama: {"stage": {"changed_at": …` (the id where the first name belongs)
- `type`: `ERROR:  CONTRACT VIOLATED: couple_profiles has columns beyond the spec (never a type or score): …`
- `label` (§7.4): `ERROR:  CONTRACT VIOLATED: a function outside the allow-list reads couple_profiles (never a type or score): couple_label(uuid)`

then `t|0` (the `BEGIN`-wrapped mutants rolled back with the contract) and `NOTICE:  couple_profile_contracts: all held`.

- [ ] **Step 8: Add the twin to the local harness (edit only, never run)**

In `scripts/local_pg_grants.sql`:

Edit 1 of 1. Replace exactly:

```sql
-- Spec 1 W4a: the accept and the eligibility check are the invite edge
-- functions' (service role); the preview is the app's.
\i supabase/migrations/20261102100010_accept_invite_v2_grants.sql
```

with:

```sql
-- Spec 1 W4a: the accept and the eligibility check are the invite edge
-- functions' (service role); the preview is the app's.
\i supabase/migrations/20261102100010_accept_invite_v2_grants.sql

-- Spec 1 W5: About us: the profile and the draft read under RLS and
-- through their RPCs; the adoption, the anniversary sync and the helpers
-- are server-only.
\i supabase/migrations/20261102110010_couple_profiles_grants.sql
```

(`scripts/local_pg_table_privileges.py` reads every migration's table-level GRANT/REVOKE itself; it needs no edit.)

- [ ] **Step 9: Run tests**

```bash
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > .superpowers/sdd/2026-11-02-spec1-w5/sql-after-task1.txt
grep '^FAIL' .superpowers/sdd/2026-11-02-spec1-w5/sql-after-task1.txt | comm -13 <(grep '^FAIL' .superpowers/sdd/2026-11-02-spec1-w5/sql-baseline.txt) -
grep -E 'couple_profile|invite_v2|identity_foundation|data_export|story_export' .superpowers/sdd/2026-11-02-spec1-w5/sql-after-task1.txt
```

Expected: no new FAIL line (`reminder_delivery_contracts.sql` and `together_events_contracts.sql` were FAIL before W5 and stay so; the reminder guard changes neither); `PASS couple_profile_contracts.sql`, `PASS data_export_contracts.sql`, `PASS identity_foundation_contracts.sql`, `PASS invite_v2_contracts.sql`, `PASS story_export_contracts.sql`.

### Task 2: Migration 10, part 2: the accept adopts the drafts, a switch to Dating drops the draft, the export carries About us; the server gate (§4.3 W5 re-created functions, §4.8, §7.1, §7.4, §9 "Export loses the stories order or gains an id", P-1, P-8-P-11)

**Files:**
- Create: `supabase/migrations/20261102110100_couple_profiles_links.sql`
- Create: `supabase/migrations/20261102110110_couple_profiles_links_grants.sql`
- Modify: `supabase/tests/couple_profile_contracts.sql` (sections F-Dating, G, H, I)
- Modify: `supabase/tests/identity_foundation_contracts.sql` (one expression, P-10)
- Modify: `scripts/local_pg_grants.sql` (one `\i` block; never run)

**Interfaces:**
- Consumes: Task 1's `public.adopt_couple_profile_drafts(uuid, uuid, uuid)`, `public.couple_profiles`, `public.couple_profile_drafts`; the live bodies of `accept_relationship_invite_v2` (`20261102100000`), `set_user_path_internal` (`20261025100300`), `export_relationship` (`20261024100700`), `export_bundle` (`20261018120000`).
- Produces: the same four signatures and grants, with: the accept calling `adopt_couple_profile_drafts(v_rel.id, v_rel.user_a, p_acceptor)` once, after `set_user_path_internal(p_acceptor, 'relationship')`; `set_user_path_internal` deleting the person's draft on a change to `dating`; `export_relationship(…)->'about_us'` = `{together_since, together_since_precision, stage, stage_words, ceremonies, living, children, child_age_bands, anniversary_source, changes:[{field, by: 'me'|'partner'|null, at}]}` (or null without a profile); `export_bundle(…)->'personal'->'settings'` gaining `birth_date`, `path`, `journal_reminder: {enabled, iso_weekday, local_time} | null`.

- [ ] **Step 1: Add the failing sections to the contract**

In `supabase/tests/couple_profile_contracts.sql`:

Edit 1 of 4. Replace exactly:

```sql
-- validation, attribution per field (a first name, never an id), the
-- together signal, the anniversary reminder's single source and its guard,
-- the draft's life (kept through a withdrawal; W5 part 2 adds the switch
-- to Dating, the adoption at linking and the export), and never a type or
-- a score.
-- One BEGIN ... ROLLBACK.
-- Run only on attune_spec3a:
```

with:

```sql
-- validation, attribution per field (a first name, never an id), the
-- together signal, the anniversary reminder's single source and its guard,
-- the draft's life (kept through a withdrawal, gone on a switch to Dating,
-- adopted at linking), the export section, and never a type or a score.
-- One BEGIN ... ROLLBACK.
-- Run only on attune_spec3a:
```

Edit 2 of 4. Replace exactly:

```sql
-- =====================================================================
-- F. The draft (spec §4.2, §4.3 W5): own, Relationship path only, the
--    same validation; kept through a withdrawal and a switch to Just
--    for me (part 2 adds: gone on a switch to Dating). Fixtures 21-24.
-- =====================================================================
DO $$
```

with:

```sql
-- =====================================================================
-- F. The draft (spec §4.2, §4.3 W5): own, Relationship path only, the
--    same validation; kept through a withdrawal; gone on a switch to
--    Dating, kept on Just for me. Fixtures 21-24.
-- =====================================================================
DO $$
```

Edit 3 of 4. Replace exactly:

```sql
  END IF;

  -- A switch to Just for me keeps it (unreadable until Relationship again).
  PERFORM public.set_user_path_internal(pg_temp.id('21'), 'just_me');
  IF NOT EXISTS (SELECT 1 FROM public.couple_profile_drafts WHERE user_id = pg_temp.id('21')) THEN
```

with:

```sql
  END IF;

  -- A switch to Just for me keeps it (unreadable until Relationship again);
  -- a switch to Dating deletes it (review I-6).
  PERFORM public.set_user_path_internal(pg_temp.id('21'), 'just_me');
  IF NOT EXISTS (SELECT 1 FROM public.couple_profile_drafts WHERE user_id = pg_temp.id('21')) THEN
```

Edit 4 of 4. Replace exactly:

```sql
    RAISE EXCEPTION 'CONTRACT VIOLATED: the draft was readable off the Relationship path (got %)', coalesce(v_msg, 'no error');
  END IF;
END $$;

```

with:

```sql
    RAISE EXCEPTION 'CONTRACT VIOLATED: the draft was readable off the Relationship path (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM public.set_user_path_internal(pg_temp.id('21'), 'dating');
  IF EXISTS (SELECT 1 FROM public.couple_profile_drafts WHERE user_id = pg_temp.id('21')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a switch to Dating kept the draft (I-6)';
  END IF;
END $$;

-- =====================================================================
-- G. Adoption at linking (spec §3.8 R4): the inviter's draft first, the
--    acceptor's fills what is empty, each field keeps its owner and its
--    time; dependent fields that no longer hold are dropped; both drafts
--    go; the anniversary reminder is made. Fixtures 31-36.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_row public.couple_profiles%ROWTYPE;
  v_set timestamptz;
BEGIN
  PERFORM pg_temp.flag('flow_signin_v2', false);
  PERFORM pg_temp.person('31', 'Yaw Inviter');
  PERFORM pg_temp.person('32', 'Ama Acceptor');
  INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at)
  VALUES (pg_temp.rel('31'), pg_temp.id('31'), 'pending', 'W5ADP1', now() + interval '7 days');
  PERFORM pg_temp.draft_as('31', '{"stage":"engaged","together_since":"2020-02-14","together_since_precision":"day","anniversary_source":"together_since"}');
  v_set := (SELECT stage_set_at FROM public.couple_profile_drafts WHERE user_id = pg_temp.id('31'));
  -- The acceptor's draft: a stage (the inviter's wins), ceremonies (dropped:
  -- the stage is Engaged), where they live and children (filled).
  PERFORM pg_temp.draft_as('32', '{"stage":"married","ceremonies":[{"year":2021}],"living":"together","children":"yes","child_age_bands":["under2"]}');

  v := public.accept_relationship_invite_v2(pg_temp.id('32'), 'W5ADP1');
  SELECT * INTO v_row FROM public.couple_profiles WHERE relationship_id = pg_temp.rel('31');
  IF NOT FOUND OR v_row.stage <> 'engaged' OR v_row.stage_changed_by <> pg_temp.id('31')
     OR v_row.stage_changed_at <> v_set
     OR v_row.together_since <> date '2020-02-14' OR v_row.together_since_changed_by <> pg_temp.id('31')
     OR v_row.living <> 'together' OR v_row.living_changed_by <> pg_temp.id('32')
     OR v_row.children <> 'yes' OR v_row.child_age_bands <> ARRAY['under2']
     OR v_row.children_changed_by <> pg_temp.id('32')
     OR v_row.ceremonies <> '[]'::jsonb OR v_row.ceremonies_changed_by IS NOT NULL
     OR v_row.anniversary_source <> 'together_since' OR v_row.anniversary_changed_by <> pg_temp.id('31') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the drafts were not adopted inviter-first: %', row_to_json(v_row);
  END IF;
  IF EXISTS (SELECT 1 FROM public.couple_profile_drafts WHERE user_id IN (pg_temp.id('31'), pg_temp.id('32'))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a draft survived the adoption';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.reminders AS r
                  WHERE r.id = v_row.anniversary_reminder_id AND r.relationship_id = pg_temp.rel('31')
                    AND r.reminder_type = 'anniversary' AND r.created_by = pg_temp.id('31')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the adopted anniversary made no reminder';
  END IF;

  -- No drafts: no profile row (nothing invented).
  PERFORM pg_temp.person('33', 'Kofi Plain');
  PERFORM pg_temp.person('34', 'Esi Plain');
  INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at)
  VALUES (pg_temp.rel('33'), pg_temp.id('33'), 'pending', 'W5ADP2', now() + interval '7 days');
  PERFORM public.accept_relationship_invite_v2(pg_temp.id('34'), 'W5ADP2');
  IF EXISTS (SELECT 1 FROM public.couple_profiles WHERE relationship_id = pg_temp.rel('33')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a profile was made from no drafts';
  END IF;

  -- The inviter's month-only date wins, so the acceptor's anniversary on
  -- their own full date no longer holds: dropped (off, nobody's), never
  -- moved onto a date without a day; the acceptor's other answers fill in.
  PERFORM pg_temp.person('35', 'Abena Month');
  PERFORM pg_temp.person('36', 'Kwame Day');
  PERFORM pg_temp.draft_as('35', '{"together_since":"2019-05-01","together_since_precision":"month"}');
  PERFORM pg_temp.draft_as('36', '{"together_since":"2019-05-20","together_since_precision":"day","anniversary_source":"together_since","living":"long_distance"}');
  INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at)
  VALUES (pg_temp.rel('35'), pg_temp.id('35'), 'pending', 'W5ADP3', now() + interval '7 days');
  PERFORM public.accept_relationship_invite_v2(pg_temp.id('36'), 'W5ADP3');
  SELECT * INTO v_row FROM public.couple_profiles WHERE relationship_id = pg_temp.rel('35');
  IF v_row.together_since <> date '2019-05-01' OR v_row.together_since_precision <> 'month'
     OR v_row.living <> 'long_distance' OR v_row.living_changed_by <> pg_temp.id('36')
     OR v_row.anniversary_source <> 'off' OR v_row.anniversary_changed_by IS NOT NULL
     OR v_row.anniversary_reminder_id IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a merged anniversary without a full date was kept: %', row_to_json(v_row);
  END IF;
END $$;

-- =====================================================================
-- H. The re-created functions keep their earlier behaviour, with W5's
--    lines in place (the full-body diff is the plan's Task 2 Step 6).
-- =====================================================================
DO $$
DECLARE
  v_src text;
BEGIN
  v_src := (SELECT p.prosrc FROM pg_proc AS p
             WHERE p.oid = 'public.accept_relationship_invite_v2(uuid,text)'::regprocedure);
  IF (SELECT count(*) FROM regexp_matches(v_src, 'adopt_couple_profile_drafts', 'g')) <> 1
     OR position('PERFORM public.adopt_couple_profile_drafts(v_rel.id, v_rel.user_a, p_acceptor);' IN v_src)
        < position('PERFORM public.set_user_path_internal(p_acceptor, ''relationship'');' IN v_src)
     OR position('PERFORM public.set_user_path_internal(p_acceptor, ''relationship'');' IN v_src) = 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the accept does not adopt the drafts once, after the path is set';
  END IF;
  v_src := (SELECT p.prosrc FROM pg_proc AS p
             WHERE p.oid = 'public.set_user_path_internal(uuid,text)'::regprocedure);
  IF position('DELETE FROM public.couple_profile_drafts AS d WHERE d.user_id = p_user;' IN v_src) = 0
     OR position('pause_dating_for_relationship_user' IN v_src) = 0
     OR position('bump_metric_internal(''path_chosen:''' IN v_src) = 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: set_user_path_internal lost a W1 statement or W5''s draft delete';
  END IF;
  v_src := (SELECT p.prosrc FROM pg_proc AS p
             WHERE p.oid = 'public.export_relationship(uuid,uuid)'::regprocedure);
  IF position('export_story_file_name' IN v_src) = 0 OR position('''about_us''' IN v_src) = 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: export_relationship lost the stories order or has no about_us';
  END IF;
END $$;

-- =====================================================================
-- I. The export (spec §4.3 W5): about_us with values and changes as
--    'me' / 'partner', never an id; the person's own birth date, path and
--    journal reminder. Relationship 31 (Yaw 31, Ama 32).
-- =====================================================================
DO $$
DECLARE
  b jsonb;
  a jsonb;
BEGIN
  INSERT INTO public.journal_reminder_settings (user_id, enabled, iso_weekday, local_time)
  VALUES (pg_temp.id('32'), true, 3, time '19:30');
  b := public.export_bundle(pg_temp.id('32'));
  a := b->'relationships'->0->'about_us';
  IF a IS NULL OR a->>'stage' <> 'engaged' OR a->>'living' <> 'together'
     OR NOT (a->'changes' @> '[{"field":"stage","by":"partner"},{"field":"living","by":"me"}]'::jsonb) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the export''s about_us is wrong: %', a;
  END IF;
  IF a::text ~ '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the export''s about_us carries an id: %', a;
  END IF;
  IF (b->'personal'->'settings'->>'birth_date')::date <> (current_date - interval '30 years')::date
     OR b->'personal'->'settings'->>'path' <> 'relationship'
     OR b->'personal'->'settings'->'journal_reminder' <> '{"enabled":true,"iso_weekday":3,"local_time":"19:30:00"}'::jsonb
     OR NOT coalesce(b->'personal'->'settings' ?& ARRAY['timezone', 'seen_receipts', 'devices'], false) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: personal.settings lacks the W5 keys or lost the old ones: %', b->'personal'->'settings';
  END IF;
  -- The other member's export has the same profile, the attribution turned.
  a := public.export_bundle(pg_temp.id('31'))->'relationships'->0->'about_us';
  IF NOT (a->'changes' @> '[{"field":"stage","by":"me"},{"field":"living","by":"partner"}]'::jsonb) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the inviter''s export attributes wrongly: %', a->'changes';
  END IF;
END $$;

```

- [ ] **Step 2: Run it to verify it fails**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/couple_profile_contracts.sql 2>&1 | grep ERROR
```

Expected: `ERROR:  CONTRACT VIOLATED: a switch to Dating kept the draft (I-6)`.

- [ ] **Step 3: Write the migration**

Every function below is its previous migration's text from `CREATE OR REPLACE FUNCTION` to `$$;` with only the lines marked "Spec 1 W5" added (Step 6 proves it). Create `supabase/migrations/20261102110100_couple_profiles_links.sql` with exactly:

```sql
-- Spec 1 W5, migration 10 part 2 of 2 (spec §4.7 #10; plan P-1):
-- couple_profiles_links. Four existing functions re-created from their
-- live bodies (spec §4.3 rule, reviews I-1, I-6), each with only W5's
-- lines added; couple_profile_contracts.sql section H diffs every one
-- against its previous body.
--   * accept_relationship_invite_v2 (from 20261102100000, W4a with all its
--     hardening: the inviter-relationship and hold checks, the uniform
--     invite:invalid, the acceptor's account:hold, both users rows locked
--     lowest id first and then the pending row, the acceptance read once
--     after that lock, both people's other pending invites removed, D8):
--     + one PERFORM adopt_couple_profile_drafts after the path is set.
--   * set_user_path_internal (from 20261025100300): + a change to Dating
--     deletes the person's couple_profile_drafts row (review I-6).
--   * export_relationship (from 20261024100700, the stories order kept):
--     + 'about_us', values and changes, no ids.
--   * export_bundle (from 20261018120000): + personal.settings.birth_date,
--     .path and .journal_reminder.
-- Grants (unchanged) restated in 20261102110110_couple_profiles_links_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.accept_relationship_invite_v2(p_acceptor uuid, p_invite_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_code constant text := upper(regexp_replace(coalesce(p_invite_code, ''), '\s', '', 'g'));
  v_hash text;
  v_done public.relationship_invite_acceptances%ROWTYPE;
  v_rel public.relationships%ROWTYPE;
  v_inviter uuid;
  v_age integer;
  v_waited interval;
BEGIN
  IF p_acceptor IS NULL OR v_code !~ '^[A-Z0-9]{6,12}$' THEN
    RAISE EXCEPTION 'invite:invalid';
  END IF;
  v_hash := encode(extensions.digest(v_code, 'sha256'), 'hex');

  -- Who sent it, read without a lock, so both users rows can be locked
  -- before any relationships row.
  SELECT r.user_a INTO v_inviter FROM public.relationships AS r
   WHERE r.invite_code = v_code AND r.status = 'pending';

  -- Lock order (W1 carry, W4 F-3): the acceptor's and the inviter's users
  -- rows, lowest id first, before any relationships row, as set_my_path
  -- and the withdraw do. No acceptor row: nothing is created (D8).
  PERFORM 1 FROM public.users AS u
   WHERE u.id IN (p_acceptor, v_inviter) ORDER BY u.id FOR UPDATE;
  IF NOT EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = p_acceptor) THEN
    RAISE EXCEPTION 'invite:phone_required';
  END IF;

  -- The pending row, locked: a second accept of the same code waits here
  -- for the first to commit, then finds no pending row.
  SELECT * INTO v_rel FROM public.relationships AS r
   WHERE r.invite_code = v_code AND r.status = 'pending'
   FOR UPDATE;
  -- Read only after that wait, so an acceptance committed meanwhile is
  -- seen: someone else's is invite:already_accepted, one's own a replay.
  SELECT * INTO v_done FROM public.relationship_invite_acceptances AS a
   WHERE a.invite_code_hash = v_hash;
  IF FOUND THEN
    IF v_done.accepted_by IS DISTINCT FROM p_acceptor THEN
      RAISE EXCEPTION 'invite:already_accepted';
    END IF;
    RETURN jsonb_build_object(
      'relationship_id', v_done.relationship_id,
      'status', (SELECT r.status FROM public.relationships AS r WHERE r.id = v_done.relationship_id),
      'idempotent', true,
      'inviter_id', (SELECT r.user_a FROM public.relationships AS r WHERE r.id = v_done.relationship_id));
  END IF;
  IF v_rel.id IS NULL THEN
    RAISE EXCEPTION 'invite:invalid';
  END IF;
  IF v_rel.user_a IS DISTINCT FROM v_inviter THEN
    -- The code changed hands between the read and the lock (a new invite
    -- reusing it): lock that inviter's row too.
    PERFORM 1 FROM public.users AS u WHERE u.id = v_rel.user_a FOR UPDATE;
  END IF;
  IF v_rel.user_a = p_acceptor THEN
    RAISE EXCEPTION 'invite:own';
  END IF;
  IF v_rel.user_b IS NOT NULL THEN
    RAISE EXCEPTION 'invite:invalid';
  END IF;
  IF v_rel.invite_expires_at < now() THEN
    RAISE EXCEPTION 'invite:expired';
  END IF;
  IF EXISTS (SELECT 1 FROM public.relationships AS r
              WHERE p_acceptor IN (r.user_a, r.user_b) AND r.status IN ('active', 'paused')) THEN
    RAISE EXCEPTION 'invite:already_in_relationship';
  END IF;
  IF public.verified_phone(p_acceptor) IS NULL THEN
    RAISE EXCEPTION 'invite:phone_required';
  END IF;
  IF EXISTS (SELECT 1 FROM public.account_holds AS h
              WHERE h.user_id = p_acceptor AND h.resolved_at IS NULL) THEN
    RAISE EXCEPTION 'account:hold';
  END IF;
  IF private.spec1_flag_on('flow_signin_v2') THEN
    v_age := public.account_age(p_acceptor);
    IF v_age IS NULL THEN
      RAISE EXCEPTION 'invite:age_required';
    END IF;
    IF v_age < 18 THEN
      RAISE EXCEPTION 'invite:not_possible';
    END IF;
  END IF;
  -- The inviter's side (rulings I-1, I-3), uniform.
  IF private.invite_inviter_unavailable(v_rel.user_a, v_rel.id) THEN
    RAISE EXCEPTION 'invite:invalid';
  END IF;
  IF private.spec1_flag_on('flow_signin_v2') THEN
    v_age := public.account_age(v_rel.user_a);
    IF v_age IS NULL OR v_age < 18 THEN
      RAISE EXCEPTION 'invite:not_possible';
    END IF;
  END IF;

  -- The acceptor's own invites go first, in this transaction (spec §7.1).
  DELETE FROM public.relationships AS r
   WHERE r.user_a = p_acceptor AND r.status = 'pending' AND r.user_b IS NULL;
  -- And the inviter's other codes (ruling I-1): none can link them again.
  DELETE FROM public.relationships AS r
   WHERE r.user_a = v_rel.user_a AND r.id <> v_rel.id
     AND r.status = 'pending' AND r.user_b IS NULL;

  BEGIN
    UPDATE public.relationships
       SET user_b = p_acceptor,
           status = 'active',
           invite_code = NULL,
           invite_accepted_at = now()
     WHERE id = v_rel.id;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'relationship:already_open' THEN
      RAISE EXCEPTION 'invite:already_in_relationship';
    END IF;
    RAISE;
  END;

  INSERT INTO public.relationship_invite_acceptances
    (invite_code_hash, relationship_id, accepted_by, accepted_at)
  VALUES (v_hash, v_rel.id, p_acceptor, now());

  PERFORM public.set_user_path_internal(p_acceptor, 'relationship');

  -- Spec 1 W5 (§3.8 R4, §4.3 W5): the inviter's About us draft, then the
  -- acceptor's, become the couple's shared profile.
  PERFORM public.adopt_couple_profile_drafts(v_rel.id, v_rel.user_a, p_acceptor);

  -- Server events (internal; spec §4.3 W1b seeds): every accept, and those
  -- within a day and within a week of the invite.
  v_waited := now() - v_rel.created_at;
  PERFORM private.bump_metric_internal('invite_accepted');
  IF v_waited <= interval '24 hours' THEN
    PERFORM private.bump_metric_internal('invite_accepted_24h');
  END IF;
  IF v_waited <= interval '7 days' THEN
    PERFORM private.bump_metric_internal('invite_accepted_7d');
  END IF;

  RETURN jsonb_build_object(
    'relationship_id', v_rel.id,
    'status', 'active',
    'idempotent', false,
    'inviter_id', v_rel.user_a);
END;
$$;

CREATE OR REPLACE FUNCTION public.set_user_path_internal(p_user uuid, p_path text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_old text;
  v_chosen_at timestamptz;
  v_elapsed interval;
BEGIN
  IF p_path IS NULL OR p_path NOT IN ('relationship', 'dating', 'just_me') THEN
    RAISE EXCEPTION 'path:invalid';
  END IF;
  SELECT u.path, u.path_chosen_at INTO v_old, v_chosen_at
    FROM public.users AS u WHERE u.id = p_user FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'path:no_account';
  END IF;
  IF v_old IS NOT DISTINCT FROM p_path THEN RETURN; END IF;

  UPDATE public.users
     SET path_previous = v_old,
         path = p_path,
         path_chosen_at = now()
   WHERE id = p_user;

  -- Spec 1 W5 (review I-6): a change to Dating takes the person's About us
  -- draft with it (spec §4.2).
  IF p_path = 'dating' THEN
    DELETE FROM public.couple_profile_drafts AS d WHERE d.user_id = p_user;
  END IF;

  IF v_old IS NULL THEN
    INSERT INTO public.onboarding_profiles (user_id) VALUES (p_user)
    ON CONFLICT (user_id) DO NOTHING;
    -- Written once, at the first choice, and never re-synced (D14). A status
    -- legacy onboarding already wrote is that one write, so it is kept
    -- (batch 4 review #5).
    INSERT INTO public.profiles AS p (id, relationship_status)
    VALUES (p_user, CASE p_path WHEN 'relationship' THEN 'taken'
                                WHEN 'dating' THEN 'single'
                                ELSE 'figuring_it_out' END)
    ON CONFLICT (id) DO UPDATE
      SET relationship_status = coalesce(p.relationship_status, EXCLUDED.relationship_status);
    PERFORM private.bump_metric_internal('path_chosen:' || p_path);
  ELSE
    v_elapsed := now() - coalesce(v_chosen_at, now());
    IF v_elapsed <= interval '7 days' THEN
      PERFORM private.bump_metric_internal('path_switch_7d:' || v_old || '>' || p_path);
    ELSIF v_elapsed <= interval '30 days' THEN
      PERFORM private.bump_metric_internal('path_switch_30d:' || v_old || '>' || p_path);
    END IF;
  END IF;

  -- The one Dating pause Spec 1 makes (D18).
  IF p_path = 'relationship'
     AND (private.dating_home_summary(p_user) ->> 'enrolled')::boolean THEN
    PERFORM public.pause_dating_for_relationship_user(p_user);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.export_relationship(p_user_id uuid, p_relationship_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_rel public.relationships;
  v_i_am_a boolean;
  v_out jsonb;
  v_start date;
BEGIN
  -- Only a relationship the person is in (re-review M6: callers are the
  -- worker's, but the ids are never trusted).
  SELECT * INTO v_rel FROM public.relationships
  WHERE id = p_relationship_id AND p_user_id IN (user_a, user_b);
  IF NOT FOUND THEN RETURN '{}'::jsonb; END IF;
  v_i_am_a := v_rel.user_a = p_user_id;
  v_start := least(v_rel.created_at::date, coalesce(v_rel.started_at, v_rel.created_at::date));

  v_out := jsonb_build_object(
    'status', v_rel.status,
    'started_on', v_rel.started_at,
    'ended_at', v_rel.ended_at,
    'partner_first_name', (
      SELECT CASE WHEN split_part(btrim(u.display_name), ' ', 1) ~ '^\+?[0-9 ()-]*$' THEN NULL
                  ELSE split_part(btrim(u.display_name), ' ', 1) END
      FROM public.users u
      WHERE u.id = CASE WHEN v_i_am_a THEN v_rel.user_b ELSE v_rel.user_a END),

    -- Chat is paged separately (export_chat_page): a long history must
    -- not be one statement or one in-memory value (plan review I7).
    'chat_messages', (SELECT count(*) FROM public.messages m
                      WHERE m.relationship_id = p_relationship_id AND NOT m.is_system_notice
                        AND coalesce(m.media_type, '') <> 'streak'),

    'places', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'from', public.export_who(p_user_id, pu.user_id), 'at', pu.created_at,
        'label', pu.label, 'note', pu.note, 'city', pu.city, 'country', pu.country,
        -- The partner's exact spots over time would be a location history of
        -- them: their pins keep only the place names (plan review I2).
        'latitude', CASE WHEN pu.user_id = p_user_id THEN pu.latitude END,
        'longitude', CASE WHEN pu.user_id = p_user_id THEN pu.longitude END) ORDER BY pu.created_at)
      FROM public.place_updates pu WHERE pu.relationship_id = p_relationship_id
    ), '[]'::jsonb),

    -- Planning: entries, blocks, items. Templates and deleted rows out;
    -- expenses as a flat per-entry list, no totals (D.2, D6).
    'planning', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'title', e.title, 'status', e.status, 'currency', e.currency,
        'created_by', public.export_who(p_user_id, e.created_by), 'created_at', e.created_at,
        'blocks', coalesce((
          SELECT jsonb_agg(jsonb_build_object(
            'type', b.block_type, 'text', b.plain_text,
            'date_start', b.date_start, 'date_end', b.date_end,
            'photos', CASE WHEN b.block_type = 'photo' THEN (
              SELECT jsonb_agg('media/' || public.export_file_name('planning', x.path))
              FROM jsonb_array_elements_text(coalesce(b.payload->'paths', '[]'::jsonb)) AS x(path)) END,
            'url', CASE WHEN b.block_type = 'link' THEN b.payload->>'url' END,
            'created_by', public.export_who(p_user_id, b.created_by),
            'items', coalesce((
              SELECT jsonb_agg(jsonb_build_object(
                'text', it.text, 'section', it.section, 'done', it.checked_at IS NOT NULL,
                'due', it.due_date, 'amount_minor', it.amount_minor, 'currency', it.currency,
                'paid_by', public.export_who(p_user_id, it.paid_by),
                'assigned_to', public.export_who(p_user_id, it.assigned_to),
                'date_start', it.date_start, 'date_end', it.date_end) ORDER BY it.sort_key)
              FROM public.planning_block_items it
              WHERE it.block_id = b.id AND it.deleted_at IS NULL), '[]'::jsonb)
          ) ORDER BY b.sort_key)
          FROM public.planning_blocks b
          WHERE b.entry_id = e.id AND b.deleted_at IS NULL), '[]'::jsonb)
      ) ORDER BY e.created_at)
      FROM public.planning_entries e
      WHERE e.relationship_id = p_relationship_id AND e.deleted_at IS NULL AND NOT e.is_template
    ), '[]'::jsonb),

    -- Calendar: exactly what the person sees (their private items, shared
    -- items, "Busy" for the partner's busy-only; never the partner's private).
    -- Events the person created or that were shared with them (D.2): never
    -- the partner's private or busy-only items (plan review I3). The whole
    -- relationship, not a window (D.3 #5).
    'calendar', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'kind', t.item_kind, 'id', 'c' || t.rank_id, 'date', t.item_date,
        'starts_at', t.starts_at, 'ends_at', t.ends_at, 'all_day', t.all_day,
        'title', t.title, 'visibility', t.visibility,
        'note', t.note, 'location', t.location,
        'recurring', t.recurring, 'continuation', t.continuation,
        'created_by', public.export_who(p_user_id, t.created_by)) ORDER BY t.item_date)
      FROM (
        SELECT ti.*,
               dense_rank() OVER (ORDER BY ti.item_kind, ti.item_id) AS rank_id,
               CASE WHEN ti.item_kind = 'event' THEN ce.note END AS note,
               CASE WHEN ti.item_kind = 'event' THEN ce.location_name END AS location,
               coalesce(ce.rrule IS NOT NULL OR ce.ritual_id IS NOT NULL, false) AS recurring,
               coalesce(NOT ti.all_day AND ti.starts_at IS NOT NULL
                 AND ti.item_date > (ti.starts_at AT TIME ZONE coalesce(ti.tz, 'UTC'))::date, false) AS continuation
        FROM public.together_items_for(p_user_id, p_relationship_id, v_start, current_date + 365) ti
        LEFT JOIN public.couple_events ce ON ti.item_kind = 'event' AND ce.id = ti.item_id
        WHERE ti.item_kind IN ('event', 'reminder', 'planning_date')
          AND NOT (ti.visibility = 'busy_only' AND ti.created_by IS DISTINCT FROM p_user_id)
      ) t
    ), '[]'::jsonb),

    'reminders', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'type', r.reminder_type, 'title', r.title, 'note', r.note,
        'remind_at', r.remind_at, 'recurrence', r.recurrence) ORDER BY r.remind_at)
      FROM public.reminders r WHERE r.relationship_id = p_relationship_id
    ), '[]'::jsonb),

    -- Spec 1 W5 (§4.3 W5): About us, its values and who changed each one
    -- ('me' or 'partner', never an id) and when.
    'about_us', (
      SELECT jsonb_build_object(
        'together_since', cp.together_since,
        'together_since_precision', cp.together_since_precision,
        'stage', cp.stage, 'stage_words', cp.stage_words,
        'ceremonies', cp.ceremonies, 'living', cp.living,
        'children', cp.children, 'child_age_bands', to_jsonb(cp.child_age_bands),
        'anniversary_source', cp.anniversary_source,
        'changes', coalesce((
          SELECT jsonb_agg(jsonb_build_object(
            'field', c.field, 'by', public.export_who(p_user_id, c.by), 'at', c.at) ORDER BY c.at, c.field)
          FROM (VALUES ('together_since', cp.together_since_changed_by, cp.together_since_changed_at),
                       ('stage', cp.stage_changed_by, cp.stage_changed_at),
                       ('ceremonies', cp.ceremonies_changed_by, cp.ceremonies_changed_at),
                       ('living', cp.living_changed_by, cp.living_changed_at),
                       ('children', cp.children_changed_by, cp.children_changed_at),
                       ('anniversary', cp.anniversary_changed_by, cp.anniversary_changed_at)) AS c(field, by, at)
          WHERE c.at IS NOT NULL), '[]'::jsonb))
      FROM public.couple_profiles cp WHERE cp.relationship_id = p_relationship_id),

    'family', coalesce((
      SELECT jsonb_agg(jsonb_build_object('name', f.name, 'birthday', f.birthday) ORDER BY f.name)
      FROM public.couple_family_members f WHERE f.relationship_id = p_relationship_id
    ), '[]'::jsonb),

    'moments', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'type', t.event_type, 'title', t.title, 'note', t.note, 'on', t.occurred_at,
        'logged_by', public.export_who(p_user_id, t.logged_by),
        -- Spec 7 (B2; review I6): shared through "Share a win".
        'win', CASE WHEN t.is_win THEN true END) ORDER BY t.occurred_at)
      FROM public.timeline_events t
      WHERE t.relationship_id = p_relationship_id AND t.deleted_at IS NULL
        AND (t.visibility = 'shared' OR t.logged_by = p_user_id)
    ), '[]'::jsonb),

    -- The person's own stories only (the partner's are not exportable).
    'my_stories', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'type', s.media_type, 'on', s.occurred_on, 'at', s.created_at,
        'media_file', 'media/' || public.export_story_file_name(s.media_key, s.media_type),
        'place', (SELECT jsonb_build_object('label', sp.label, 'latitude', sp.lat, 'longitude', sp.lng)
                  FROM public.story_places sp WHERE sp.story_item_id = s.id)) ORDER BY s.created_at)
      FROM public.story_items s
      WHERE s.relationship_id = p_relationship_id AND s.author_id = p_user_id AND s.deleted_at IS NULL
    ), '[]'::jsonb),

    -- Shared Pulse history and verdicts (both already saw them); role-free.
    'pulse', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'week_ending', ps.week_ending, 'overall', ps.overall_score,
        'communication', ps.communication, 'connection', ps.connection,
        'conflict_health', ps.conflict_health, 'alignment', ps.alignment,
        'confidence', ps.data_confidence) ORDER BY ps.week_ending)
      FROM public.pulse_scores ps WHERE ps.relationship_id = p_relationship_id
    ), '[]'::jsonb),
    'verdicts', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'period_start', v.period_start, 'period_end', v.period_end,
        'headline', v.headline,
        'strengths', (SELECT jsonb_agg(jsonb_build_object('title', x->>'title', 'body', x->>'body'))
                      FROM jsonb_array_elements(coalesce(v.strengths, '[]'::jsonb)) x),
        'watch_areas', (SELECT jsonb_agg(jsonb_build_object('title', x->>'title', 'body', x->>'body'))
                        FROM jsonb_array_elements(coalesce(v.watch_areas, '[]'::jsonb)) x),
        'one_action', v.one_action, 'disclaimer', v.disclaimer) ORDER BY v.period_start)
      FROM public.verdicts v WHERE v.relationship_id = p_relationship_id AND v.status = 'published'
    ), '[]'::jsonb),

    -- Games: the person's own answers always; the partner's only once the
    -- round revealed them (both answered).
    'game_rounds', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'game', coalesce(gs.game_type, r.game_type, 'love_map'),
        'question', r.question_text_snapshot,
        'at', r.created_at,
        'my_answer', CASE WHEN v_i_am_a THEN r.answer_a ELSE r.answer_b END,
        'partner_answer', CASE WHEN r.both_answered THEN
                            CASE WHEN v_i_am_a THEN r.answer_b ELSE r.answer_a END END) ORDER BY r.created_at)
      FROM public.game_session_rounds r
      LEFT JOIN public.game_sessions gs ON gs.id = r.session_id
      WHERE coalesce(r.relationship_id, gs.relationship_id) = p_relationship_id
        AND (r.answer_a IS NOT NULL OR r.answer_b IS NOT NULL)
    ), '[]'::jsonb),
    'thirty_six_answers', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'question', r.question_text_snapshot,
        'from', public.export_who(p_user_id, a.user_id),
        'answer', a.answer_text, 'at', a.submitted_at) ORDER BY a.submitted_at)
      FROM public.thirty_six_question_answers a
      JOIN public.game_session_rounds r ON r.id = a.round_id
      JOIN public.game_sessions gs ON gs.id = r.session_id
      WHERE gs.relationship_id = p_relationship_id AND NOT coalesce(a.is_removed, false)
        AND (a.user_id = p_user_id OR r.both_answered)
    ), '[]'::jsonb),
    -- The person's own This-or-That picks (plan review M3).
    'this_or_that_picks', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'question', r.question_text_snapshot, 'picked', a.choice, 'at', r.created_at) ORDER BY r.created_at)
      FROM public.this_or_that_round_answers a
      JOIN public.game_session_rounds r ON r.id = a.round_id
      JOIN public.game_sessions gs ON gs.id = r.session_id
      WHERE gs.relationship_id = p_relationship_id AND a.user_id = p_user_id
    ), '[]'::jsonb),
    'love_map_truths', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'about', public.export_who(p_user_id, t.subject_id), 'truth', t.truth_text))
      FROM public.mirror_round_truth t
      JOIN public.game_session_rounds r ON r.id = t.round_id
      LEFT JOIN public.game_sessions gs ON gs.id = r.session_id
      WHERE coalesce(r.relationship_id, gs.relationship_id) = p_relationship_id
        AND (t.subject_id = p_user_id OR r.both_answered)
    ), '[]'::jsonb)
  );
  RETURN v_out;
END;
$$;

CREATE OR REPLACE FUNCTION public.export_bundle(p_user_id uuid, p_relationship_ids uuid[] DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_rels jsonb := '[]'::jsonb;
  v_ids uuid[] := coalesce(p_relationship_ids, public.export_open_relationships(p_user_id));
  v_n int;
BEGIN
  FOR v_n IN 1 .. coalesce(array_length(v_ids, 1), 0) LOOP
    v_rels := v_rels || jsonb_build_array(
      jsonb_build_object('name', 'relationship-' || v_n, 'chat_folder', 'relationship-' || v_n || '/chat')
      || public.export_relationship(p_user_id, v_ids[v_n]));
  END LOOP;

  RETURN jsonb_build_object(
    'format', 'attune-export', 'version', 1, 'generated_at', now(),
    'relationships', v_rels,
    'personal', jsonb_build_object(
      -- Spec 7 (review I6): notes I kept (by ref, under the chapter they
      -- came from), the dates I hid, and a quiet state if one is on.
      'appreciation_jar', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'relationship', 'relationship-' || array_position(v_ids, m.relationship_id),
        'ref', left(md5(m.id::text), 12), 'text', m.content, 'saved_at', j.saved_at) ORDER BY j.saved_at)
        FROM public.appreciation_jar j JOIN public.messages m ON m.id = j.message_id
        WHERE j.user_id = p_user_id AND m.deleted_at IS NULL
          AND array_position(v_ids, m.relationship_id) IS NOT NULL), '[]'::jsonb),
      'hidden_periods', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'starts_on', h.starts_on, 'ends_on', h.ends_on) ORDER BY h.starts_on)
        FROM public.hidden_periods h WHERE h.user_id = p_user_id), '[]'::jsonb),
      'quiet_state', (SELECT jsonb_build_object('kind', q.kind, 'until', q.until)
        FROM public.quiet_states q WHERE q.user_id = p_user_id AND q.until > now()),
      -- Sync audit M-9: my own settings — my time zone, my own seen-receipt
      -- choice per chapter (never the partner's), my signed-in devices.
      'settings', jsonb_build_object(
        'timezone', (SELECT u.timezone FROM public.users u WHERE u.id = p_user_id),
        'seen_receipts', coalesce((SELECT jsonb_agg(jsonb_build_object(
            'relationship', 'relationship-' || array_position(v_ids, sp.relationship_id),
            'seen_on', sp.seen_on) ORDER BY array_position(v_ids, sp.relationship_id))
          FROM public.seen_receipt_prefs sp
          WHERE sp.user_id = p_user_id AND array_position(v_ids, sp.relationship_id) IS NOT NULL), '[]'::jsonb),
        'devices', coalesce((SELECT jsonb_agg(jsonb_build_object(
            'label', d.label, 'platform', d.platform, 'updated_at', d.updated_at) ORDER BY d.updated_at)
          FROM public.session_devices d WHERE d.user_id = p_user_id), '[]'::jsonb),
        -- Spec 1 W5 (§4.3 W5): my date of birth (in my own export only),
        -- the way I use Attune, and my journal reminder.
        'birth_date', (SELECT ab.birth_date FROM public.account_birthdates ab WHERE ab.user_id = p_user_id),
        'path', (SELECT u.path FROM public.users u WHERE u.id = p_user_id),
        'journal_reminder', (SELECT jsonb_build_object(
            'enabled', jr.enabled, 'iso_weekday', jr.iso_weekday, 'local_time', jr.local_time)
          FROM public.journal_reminder_settings jr WHERE jr.user_id = p_user_id)),
      'insights', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'type', i.insight_type, 'text', i.insight_body, 'at', i.created_at) ORDER BY i.created_at)
        FROM public.personal_insights i WHERE i.user_id = p_user_id), '[]'::jsonb),
      -- Content-free by design: no translated text is ever stored.
      'translator_use', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'at', t.used_at, 'need', t.core_need_identified, 'chose_rewrite', t.chose_rewrite) ORDER BY t.used_at)
        FROM public.translator_logs t WHERE t.user_id = p_user_id), '[]'::jsonb),
      'weekly_checkins', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'week_ending', w.week_ending, 'communication', w.communication_rating,
        'connection', w.connection_rating, 'conflict_health', w.conflict_health_rating,
        'alignment', w.alignment_rating) ORDER BY w.week_ending)
        -- safety_rating is never exported (D.2: the safety check never is;
        -- plan review C1).
        FROM public.weekly_checkins w WHERE w.user_id = p_user_id), '[]'::jsonb),
      'journal', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'title', e.title, 'prompt', e.prompt_used, 'created_at', e.created_at,
        'blocks', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'kind', b.kind, 'text', b.plain_text,
          'photo', CASE WHEN b.kind = 'photo' AND b.payload->>'path' IS NOT NULL
                        THEN 'media/' || public.export_file_name('journal', b.payload->>'path') END) ORDER BY b.position)
          FROM public.reflection_journal_blocks b WHERE b.entry_id = e.id), '[]'::jsonb)) ORDER BY e.created_at)
        FROM public.reflection_journal_entries e WHERE e.user_id = p_user_id AND e.deleted_at IS NULL), '[]'::jsonb),
      'healing', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'breakup_at', h.breakup_at, 'reflection_answers', h.reflection_answers,
        'readiness_answers', (SELECT jsonb_agg(ra.answers ORDER BY ra.submitted_at)
                              FROM public.healing_readiness_attempts ra WHERE ra.journey_id = h.id)) ORDER BY h.created_at)
        FROM public.healing_journeys h WHERE h.user_id = p_user_id), '[]'::jsonb),
      'quiz_responses', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'quiz', q.quiz_type, 'answers', q.responses, 'result', q.result_type,
        'result_data', q.result_data, 'at', q.completed_at) ORDER BY q.completed_at)
        FROM public.quiz_responses q WHERE q.user_id = p_user_id), '[]'::jsonb),
      'profile', (SELECT jsonb_build_object(
        'attachment', p.attachment_style, 'love_languages', p.love_languages,
        'communication', p.communication_style, 'conflict', p.conflict_style)
        FROM public.psych_profiles p WHERE p.user_id = p_user_id),
      'profile_history', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'quiz', h.quiz_type, 'result', h.result_type, 'at', h.recorded_at) ORDER BY h.recorded_at)
        FROM public.psych_profile_history h WHERE h.user_id = p_user_id), '[]'::jsonb),
      'onboarding', (SELECT jsonb_build_object('answers', o.attachment_answers, 'anchors', o.anchors)
        FROM public.onboarding_profiles o WHERE o.user_id = p_user_id),
      'my_questions', coalesce((
        SELECT jsonb_agg(x) FROM (
          SELECT jsonb_build_object('game', 'this_or_that', 'question', c.question_text,
                                    'a', c.option_a, 'b', c.option_b) AS x
          FROM public.custom_this_or_that_questions c WHERE c.user_id = p_user_id
          UNION ALL
          SELECT jsonb_build_object('game', 'truth_or_dare', 'type', c.question_type, 'question', c.content)
          FROM public.custom_truth_or_dare_questions c WHERE c.user_id = p_user_id) q), '[]'::jsonb)
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.accept_relationship_invite_v2(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_user_path_internal(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.export_relationship(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.export_bundle(uuid, uuid[]) FROM PUBLIC, anon, authenticated;

COMMIT;
```

- [ ] **Step 4: Write the grants twin**

Create `supabase/migrations/20261102110110_couple_profiles_links_grants.sql` with exactly:

```sql
-- Spec 1 W5: grants for 20261102110100_couple_profiles_links.sql, the
-- four re-created functions' grants exactly as before: the accept and the
-- bundle are the service role's (accept-invite, the export worker); the
-- path writer and one relationship's export are server-only.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.accept_relationship_invite_v2(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.accept_relationship_invite_v2(uuid, text) TO service_role;
REVOKE ALL ON FUNCTION public.set_user_path_internal(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.export_relationship(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.export_bundle(uuid, uuid[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.export_bundle(uuid, uuid[]) TO service_role;
COMMIT;
```

- [ ] **Step 5: Apply both twice, run the contract, and see the identity contract's I-6 scan go red**

```bash
for i in 1 2; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261102110100_couple_profiles_links.sql > /dev/null; echo "migration exit=$?"
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261102110110_couple_profiles_links_grants.sql > /dev/null; echo "grants exit=$?"
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/couple_profile_contracts.sql 2>&1 | tail -1
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql 2>&1 | grep ERROR | sed -E 's/^psql:[^ ]* //'
psql -X -d attune_spec3a -Atc "select p.oid::regprocedure, array_to_string(p.proacl, ',') from pg_proc p where p.oid in ('public.accept_relationship_invite_v2(uuid,text)'::regprocedure, 'public.set_user_path_internal(uuid,text)'::regprocedure, 'public.export_relationship(uuid,uuid)'::regprocedure, 'public.export_bundle(uuid,uuid[])'::regprocedure) order by 1"
```

Expected: `migration exit=0` and `grants exit=0` twice; `NOTICE:  couple_profile_contracts: all held`; then the expected red, P-10: `ERROR:  CONTRACT VIOLATED: a W1 function names a later wave's table (I-6): set_user_path_internal(uuid,text)`; then the four ACLs exactly as before W5: `accept_relationship_invite_v2` and `export_bundle` executable by the owner and `service_role` only, `set_user_path_internal` and `export_relationship` by the owner only (the owner's role name is the database's, e.g. `postgres=X/postgres,service_role=X/postgres`).

- [ ] **Step 6: Prove each re-created body is its live body plus W5's lines only**

```bash
python3 -I - <<'EOF'
import difflib, pathlib, sys
M = pathlib.Path('supabase/migrations')
NEW = (M / '20261102110100_couple_profiles_links.sql').read_text()
def body(sql, head):
    at = sql.rfind('CREATE OR REPLACE FUNCTION ' + head)
    assert at >= 0, head
    return sql[at:sql.index('\n$$;', at) + 4].splitlines()
for prev, head in [
    ('20261102100000_accept_invite_v2.sql', 'public.accept_relationship_invite_v2('),
    ('20261025100300_paths_and_home_state.sql', 'public.set_user_path_internal('),
    ('20261024100700_story_export_order.sql', 'public.export_relationship('),
    ('20261018120000_data_export.sql', 'public.export_bundle('),
]:
    old = body((M / prev).read_text(), head)
    new = body(NEW, head)
    removed = [l for l in difflib.unified_diff(old, new, lineterm='', n=0)
               if l.startswith('-') and not l.startswith('---')]
    added = [l for l in difflib.unified_diff(old, new, lineterm='', n=0)
             if l.startswith('+') and not l.startswith('+++')]
    print(f'{head} from {prev}: {len(removed)} removed, {len(added)} added')
    for l in removed + added:
        print('  ' + l)
EOF
```

Expected exactly:

```text
public.accept_relationship_invite_v2( from 20261102100000_accept_invite_v2.sql: 0 removed, 4 added
  +  -- Spec 1 W5 (§3.8 R4, §4.3 W5): the inviter's About us draft, then the
  +  -- acceptor's, become the couple's shared profile.
  +  PERFORM public.adopt_couple_profile_drafts(v_rel.id, v_rel.user_a, p_acceptor);
  +
public.set_user_path_internal( from 20261025100300_paths_and_home_state.sql: 0 removed, 6 added
  +
  +  -- Spec 1 W5 (review I-6): a change to Dating takes the person's About us
  +  -- draft with it (spec §4.2).
  +  IF p_path = 'dating' THEN
  +    DELETE FROM public.couple_profile_drafts AS d WHERE d.user_id = p_user;
  +  END IF;
public.export_relationship( from 20261024100700_story_export_order.sql: 0 removed, 22 added
  +    -- Spec 1 W5 (§4.3 W5): About us, its values and who changed each one
  +    -- ('me' or 'partner', never an id) and when.
  +    'about_us', (
  +      SELECT jsonb_build_object(
  +        'together_since', cp.together_since,
  +        'together_since_precision', cp.together_since_precision,
  +        'stage', cp.stage, 'stage_words', cp.stage_words,
  +        'ceremonies', cp.ceremonies, 'living', cp.living,
  +        'children', cp.children, 'child_age_bands', to_jsonb(cp.child_age_bands),
  +        'anniversary_source', cp.anniversary_source,
  +        'changes', coalesce((
  +          SELECT jsonb_agg(jsonb_build_object(
  +            'field', c.field, 'by', public.export_who(p_user_id, c.by), 'at', c.at) ORDER BY c.at, c.field)
  +          FROM (VALUES ('together_since', cp.together_since_changed_by, cp.together_since_changed_at),
  +                       ('stage', cp.stage_changed_by, cp.stage_changed_at),
  +                       ('ceremonies', cp.ceremonies_changed_by, cp.ceremonies_changed_at),
  +                       ('living', cp.living_changed_by, cp.living_changed_at),
  +                       ('children', cp.children_changed_by, cp.children_changed_at),
  +                       ('anniversary', cp.anniversary_changed_by, cp.anniversary_changed_at)) AS c(field, by, at)
  +          WHERE c.at IS NOT NULL), '[]'::jsonb))
  +      FROM public.couple_profiles cp WHERE cp.relationship_id = p_relationship_id),
  +
public.export_bundle( from 20261018120000_data_export.sql: 1 removed, 8 added
  -          FROM public.session_devices d WHERE d.user_id = p_user_id), '[]'::jsonb)),
  +          FROM public.session_devices d WHERE d.user_id = p_user_id), '[]'::jsonb),
  +        -- Spec 1 W5 (§4.3 W5): my date of birth (in my own export only),
  +        -- the way I use Attune, and my journal reminder.
  +        'birth_date', (SELECT ab.birth_date FROM public.account_birthdates ab WHERE ab.user_id = p_user_id),
  +        'path', (SELECT u.path FROM public.users u WHERE u.id = p_user_id),
  +        'journal_reminder', (SELECT jsonb_build_object(
  +            'enabled', jr.enabled, 'iso_weekday', jr.iso_weekday, 'local_time', jr.local_time)
  +          FROM public.journal_reminder_settings jr WHERE jr.user_id = p_user_id)),
```

The one removed line is `export_bundle`'s `devices` entry, whose closing `)),` becomes `),` so the three settings can follow it; nothing else is removed anywhere.

- [ ] **Step 7: Narrow the identity contract's I-6 scan to W5's one statement (P-10)**

In `supabase/tests/identity_foundation_contracts.sql`:

Edit 1 of 1. Replace exactly:

```sql
                   'public.get_my_home_state()'::regprocedure,
                   'public.withdraw_my_pending_invites(boolean)'::regprocedure)
     AND p.prosrc ~* '(couple_profiles|couple_profile_drafts|journal_reminder_settings|otp_delivery_intents|invite_preview_attempts|account_activity|fresh_start_challenges|auth_hook_failures|parked_phone_hmac|child_safety_reports)';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a W1 function names a later wave''s table (I-6): %', v_bad;
```

with:

```sql
                   'public.get_my_home_state()'::regprocedure,
                   'public.withdraw_my_pending_invites(boolean)'::regprocedure)
     -- Spec 1 W5 (20261102110100) re-creates set_user_path_internal from
     -- this live body with exactly one statement of its own, the draft
     -- delete on a change to Dating (review I-6): that one statement is
     -- W5's, so it is set aside; any other later-wave name still fails.
     AND regexp_replace(p.prosrc,
           'DELETE FROM public\.couple_profile_drafts AS d WHERE d\.user_id = p_user;', '', 'g')
         ~* '(couple_profiles|couple_profile_drafts|journal_reminder_settings|otp_delivery_intents|invite_preview_attempts|account_activity|fresh_start_challenges|auth_hook_failures|parked_phone_hmac|child_safety_reports)';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a W1 function names a later wave''s table (I-6): %', v_bad;
```

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql > /dev/null 2>&1; echo "identity exit=$?"
```

Expected: `identity exit=0`.

- [ ] **Step 8: Mutation checks (each must turn a contract red with the message quoted)**

```bash
M=supabase/migrations/20261102110000_couple_profiles.sql
G=supabase/migrations/20261102110010_couple_profiles_grants.sql
L=supabase/migrations/20261102110100_couple_profiles_links.sql
LG=supabase/migrations/20261102110110_couple_profiles_links_grants.sql
C=supabase/tests/couple_profile_contracts.sql
I=supabase/tests/identity_foundation_contracts.sql
D=.superpowers/sdd/2026-11-02-spec1-w5
python3 -I - "$M" "$L" "$D" <<'EOF'
import pathlib, sys
m = pathlib.Path(sys.argv[1]).read_text()
l = pathlib.Path(sys.argv[2]).read_text()
d = pathlib.Path(sys.argv[3])
muts = {
  'adopt_order': (m, "  IF vi.stage IS NOT NULL THEN\n    v.stage := vi.stage; v.stage_words := vi.stage_words;\n    v.stage_changed_by := p_inviter; v.stage_changed_at := vi.stage_set_at;\n  ELSIF va.stage IS NOT NULL THEN\n    v.stage := va.stage; v.stage_words := va.stage_words;\n    v.stage_changed_by := p_acceptor; v.stage_changed_at := va.stage_set_at;\n  END IF;\n",
                  "  IF va.stage IS NOT NULL THEN\n    v.stage := va.stage; v.stage_words := va.stage_words;\n    v.stage_changed_by := p_acceptor; v.stage_changed_at := va.stage_set_at;\n  ELSIF vi.stage IS NOT NULL THEN\n    v.stage := vi.stage; v.stage_words := vi.stage_words;\n    v.stage_changed_by := p_inviter; v.stage_changed_at := vi.stage_set_at;\n  END IF;\n"),
  'dating_delete': (l, "  IF p_path = 'dating' THEN\n    DELETE FROM public.couple_profile_drafts AS d WHERE d.user_id = p_user;\n  END IF;\n", ""),
  'adopt_call': (l, "  PERFORM public.adopt_couple_profile_drafts(v_rel.id, v_rel.user_a, p_acceptor);\n", ""),
  'export_id': (l, "'field', c.field, 'by', public.export_who(p_user_id, c.by), 'at', c.at)", "'field', c.field, 'by', c.by, 'at', c.at)"),
  'identity_extra': (l, "  IF p_path = 'dating' THEN\n    DELETE FROM public.couple_profile_drafts AS d WHERE d.user_id = p_user;\n  END IF;\n",
                     "  IF p_path = 'dating' THEN\n    DELETE FROM public.couple_profile_drafts AS d WHERE d.user_id = p_user;\n  END IF;\n  PERFORM 1 FROM public.couple_profile_drafts AS d WHERE d.user_id = p_user;\n"),
}
for name, (src, a, b) in muts.items():
    assert src.count(a) == 1, name
    (d / f"mut_{name}.sql").write_text(src.replace(a, b))
print('mutants written')
EOF
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $D/mut_adopt_order.sql -f $G > /dev/null 2>&1
echo "adopt_order: $(psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $C 2>&1 | grep ERROR | sed -E 's/^psql:[^ ]* //' | cut -c1-110)"
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $M -f $G > /dev/null 2>&1
for m in dating_delete adopt_call export_id; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $D/mut_$m.sql -f $LG > /dev/null 2>&1
  echo "$m: $(psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $C 2>&1 | grep ERROR | sed -E 's/^psql:[^ ]* //' | cut -c1-110)"
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $L -f $LG > /dev/null 2>&1
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $D/mut_identity_extra.sql -f $LG > /dev/null 2>&1
echo "identity_extra: $(psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $I 2>&1 | grep ERROR | sed -E 's/^psql:[^ ]* //' | cut -c1-140)"
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $L -f $LG > /dev/null 2>&1; echo "restored exit=$?"
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $C 2>&1 | tail -1
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $I > /dev/null 2>&1; echo "identity exit=$?"
rm $D/mut_adopt_order.sql $D/mut_dating_delete.sql $D/mut_adopt_call.sql $D/mut_export_id.sql $D/mut_identity_extra.sql
```

Expected: `mutants written`, then:
- `adopt_order` (P-8): `ERROR:  CONTRACT VIOLATED: the drafts were not adopted inviter-first: {"relationship_id":"5c0f0000-…`
- `dating_delete` (§7.4, I-6): `ERROR:  CONTRACT VIOLATED: a switch to Dating kept the draft (I-6)`
- `adopt_call`: `ERROR:  CONTRACT VIOLATED: the drafts were not adopted inviter-first: {"relationship_id":null,…`
- `export_id` (§9, never an id): `ERROR:  CONTRACT VIOLATED: the export's about_us is wrong: {"stage": "engaged", "living": "together", "chan…`
- `identity_extra` (P-10: only W5's one statement is set aside): `ERROR:  CONTRACT VIOLATED: a W1 function names a later wave's table (I-6): set_user_path_internal(uuid,text)`

then `restored exit=0`, `NOTICE:  couple_profile_contracts: all held`, `identity exit=0`.

- [ ] **Step 9: The accept's refusal codes still map (Deno), and W4's contract still holds**

```bash
(cd supabase/functions && deno test --allow-read accept-invite/ 2>&1 | grep -E 'passed|failed' | tail -1)
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/invite_v2_contracts.sql 2>&1 | tail -1
```

Expected: `ok | 29 passed | 0 failed` (`accept.test.ts` now reads the accept from `20261102110100_couple_profiles_links.sql`, the newest file defining it, and finds the same ten codes); `NOTICE:  invite_v2_contracts: all held`.

- [ ] **Step 10: Add the twin to the local harness (edit only, never run)**

In `scripts/local_pg_grants.sql`:

Edit 1 of 1. Replace exactly:

```sql
-- Spec 1 W5: About us: the profile and the draft read under RLS and
-- through their RPCs; the adoption, the anniversary sync and the helpers
-- are server-only.
\i supabase/migrations/20261102110010_couple_profiles_grants.sql
```

with:

```sql
-- Spec 1 W5: About us: the profile and the draft read under RLS and
-- through their RPCs; the adoption, the anniversary sync and the helpers
-- are server-only.
\i supabase/migrations/20261102110010_couple_profiles_grants.sql

-- Spec 1 W5: the four re-created functions keep their grants.
\i supabase/migrations/20261102110110_couple_profiles_links_grants.sql
```

- [ ] **Step 11: Run tests (the server gate)**

```bash
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > .superpowers/sdd/2026-11-02-spec1-w5/sql-after-task2.txt
grep '^FAIL' .superpowers/sdd/2026-11-02-spec1-w5/sql-after-task2.txt | comm -13 <(grep '^FAIL' .superpowers/sdd/2026-11-02-spec1-w5/sql-baseline.txt) -
grep -E 'couple_profile|invite_v2|invite_age|identity_foundation|data_export|story_export|sync_fixes' .superpowers/sdd/2026-11-02-spec1-w5/sql-after-task2.txt
```

Expected: no new FAIL line; `PASS couple_profile_contracts.sql`, `PASS data_export_contracts.sql`, `PASS identity_foundation_contracts.sql`, `PASS invite_age_contracts.sql`, `PASS invite_v2_contracts.sql`, `PASS story_export_contracts.sql`, `PASS sync_fixes_contracts.sql`.

### Task 3: The phone's data layer: the flag, the model, the service, the offline outbox, the wipe, the date formats, never a type (§2.5, §3.14, §4.8, §5.2, §5.3, §5.8, §7.1 never-typed, P-12, P-16, P-17)

**Files:**
- Create: `lib/features/couple_profile/domain/couple_profile.dart`
- Create: `lib/features/couple_profile/data/couple_profile_service.dart`
- Create: `lib/features/couple_profile/data/about_us_outbox.dart`
- Create: `lib/features/couple_profile/presentation/couple_profile_providers.dart`
- Create: `test/helpers/fake_couple_profile.dart`
- Create: `test/features/couple_profile/w5/couple_profile_data_test.dart`
- Create: `test/features/couple_profile/w5/about_us_sync_test.dart`
- Create: `test/architecture/couple_profile_never_typed_test.dart`
- Modify: `lib/core/flags/signed_in_flow_flags.dart`, `lib/features/onboarding/presentation/providers/flow_flags.dart`, `lib/core/utils/date_formatter.dart`, `lib/features/onboarding/data/onboarding_sync_service.dart`, `lib/home/home_screen.dart` (outside the latch), `lib/app/device_wipes.dart`, `test/helpers/fake_home_state.dart`

**Interfaces:**
- Consumes: Task 1-2's RPCs and JSON shape; W3's `flowCouplesV2Provider`, `flowFlagsProvider`, `FlowFlagsCache`; `homeAuthProvider`; `sharedPreferencesProvider`; `togetherChangeSignalProvider`; `DeviceWipeEntry`, `removePrefsKeys`; `OnboardingSyncService`.
- Produces:
  - `coupleProfileEnabledProvider` (`Provider<bool>`, effective) in `flow_flags.dart`; `SignedInFlowFlags.coupleProfile` (`bool`, default false).
  - Domain (`couple_profile.dart`): enums `CoupleStage` (`dating|engaged|married|other`), `DatePrecision` (`day|month|year`), `CeremonyLabel` (`customary|church|mosque|civil|other`), `Living` (`together|apartNearby|longDistance`), `Children` (`none|yes|expecting|preferNotToSay`), `ChildAgeBand` (`under2|twoToFive|sixToTwelve|thirteenToSeventeen|eighteenPlus`), `AnniversarySource` (`off|togetherSince|ceremony1|ceremony2`), `AboutUsField` (`togetherSince|stage|ceremonies|living|children|anniversary`), each with `.wire`; `TogetherSince(DateTime date, DatePrecision precision)` (`hasDay`); `Ceremony({required int year, int? month, int? day, CeremonyLabel? label})` (`fullDate`, `toJson`, `fromJson`); `FieldChange({byMe, byFirstName, at})`; `CoupleProfile` (`isDraft`, `readOnly`, `readUntil`, `togetherSince`, `stage`, `stageWords`, `ceremonies`, `living`, `children`, `childAgeBands`, `anniversarySource`, `anniversaryReminderId`, `changes: Map<AboutUsField, FieldChange>`, `pendingSync`, `isEmpty`, `anniversaryDate`, `fromJson`, `applying(AboutUsPatch)`); `AboutUsPatch(Map<String, Object?> values)` with factories `.stage(CoupleStage?, {String? words})`, `.togetherSince(TogetherSince?)`, `.ceremonies(List<Ceremony>)`, `.living(Living?)`, `.children(Children?, {List<ChildAgeBand> bands})`, `.anniversary(AnniversarySource, {TogetherSince? completedSince, List<Ceremony>? completedCeremonies})`, `merge`; `aboutUsWireDate(DateTime)`; `isFutureCivilDate(DateTime date, DateTime today)`.
  - Data: `AboutUsTarget.shared(String relationshipId)` / `.draft()` (`isDraft`, `wire`, `fromWire`); `AboutUsRefusal` (`notFound|readOnly|notRelationship|futureDate|tooManyCeremonies|ceremoniesNeedMarried|bandsNeedYes|anniversaryNeedsDay|invalid`), `AboutUsRefused(reason)`, `AboutUsOffline`; `typedef CoupleProfileRpc`, `coupleProfileRpcProvider`, `CoupleProfileService(rpc)` (`fetch(target)`, `update(target, patch)`), `coupleProfileServiceProvider`; `AboutUsOutbox(prefs, userId:)` (`keyFor`, `isOutboxKey`, `pending`, `enqueue`, `remove`, `flush(service)`, `maxAttempts = 5`).
  - Providers: `aboutUsOutboxProvider` (`AboutUsOutbox?`), `aboutUsOutboxFlushProvider` (`Future<void> Function()`), `coupleProfileProvider(AboutUsTarget)` (`AsyncNotifier`, notifier `save(AboutUsPatch) → Future<AboutUsSaveOutcome>` = `saved|queued`), `coupleProfileDraftProvider`, `aboutUsDateSuggestionsProvider(String relationshipId)` (`List<AboutUsDateSuggestion>`, `[]` here; Spec 2 W9 overrides it), `AboutUsDateSuggestion({label, since})`.
  - `MyDateFormat.toMonthYear`, `.toYear`, `.toMonth`; `OnboardingSyncService({…, Future<void> Function()? flushAboutUs})`; device wipe `spec1.about_us_outbox` (sign-out only).

- [ ] **Step 1: Write the failing tests and the test server**

`FakeFlowFlagsGateway` learns the third flag. In `test/helpers/fake_home_state.dart`:

Edit 1 of 2. Replace exactly:

```dart

class FakeFlowFlagsGateway implements FlowFlagsGateway {
  FakeFlowFlagsGateway({this.pathsV2 = true, this.couplesV2 = false});

  bool pathsV2;
  bool couplesV2;
  Object? failWith;
  int fetches = 0;
```

with:

```dart

class FakeFlowFlagsGateway implements FlowFlagsGateway {
  FakeFlowFlagsGateway({
    this.pathsV2 = true,
    this.couplesV2 = false,
    this.coupleProfile = false,
  });

  bool pathsV2;
  bool couplesV2;

  /// Spec 1 W5.
  bool coupleProfile;
  Object? failWith;
  int fetches = 0;
```

Edit 2 of 2. Replace exactly:

```dart
    fetches++;
    if (failWith != null) throw failWith!;
    return SignedInFlowFlags(pathsV2: pathsV2, couplesV2: couplesV2);
  }
}
```

with:

```dart
    fetches++;
    if (failWith != null) throw failWith!;
    return SignedInFlowFlags(
      pathsV2: pathsV2,
      couplesV2: couplesV2,
      coupleProfile: coupleProfile,
    );
  }
}
```

Create `test/helpers/fake_couple_profile.dart` with exactly:

```dart
// Spec 1 W5: a scripted About us server for the W5 tests. It keeps one
// profile per target and applies a patch the way update_couple_profile
// does for the keys the tests use (no attribution maths: each changed
// field is marked "by me" now).
import 'dart:async';

import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// get_couple_profile()'s shape (spec §4.3 W5), with every field settable.
Map<String, dynamic> aboutUsJson({
  bool draft = false,
  bool readOnly = false,
  String? readUntil,
  String? togetherSince,
  String? precision,
  String? stage,
  String? stageWords,
  List<Map<String, Object?>> ceremonies = const [],
  String? living,
  String? children,
  List<String> bands = const [],
  String anniversary = 'off',
  String? reminderId,
  Map<String, Object?> changes = const {},
}) => {
  'draft': draft,
  'read_only': readOnly,
  'read_until': readUntil,
  'together_since': togetherSince,
  'together_since_precision': precision,
  'stage': stage,
  'stage_words': stageWords,
  'ceremonies': ceremonies,
  'living': living,
  'children': children,
  'child_age_bands': bands,
  'anniversary_source': anniversary,
  'anniversary_reminder_id': reminderId,
  'changes': changes,
};

class FakeCoupleProfileServer {
  FakeCoupleProfileServer({Map<String, Map<String, dynamic>>? profiles})
    : profiles = profiles ?? {};

  /// By target wire: a relationship id, or `draft`.
  final Map<String, Map<String, dynamic>> profiles;

  /// Every call, in order: (function, params).
  final calls = <(String, Map<String, dynamic>?)>[];

  /// Thrown by the next call, if set (once).
  Object? failNext;

  /// Thrown by every call while set.
  Object? failAlways;

  /// Thrown by every update while set (reads still answer).
  Object? failUpdates;

  /// While set and not completed, every call waits for it.
  Completer<void>? hold;

  int count(String fn) => calls.where((c) => c.$1 == fn).length;

  CoupleProfileRpc get rpc => call;

  Map<String, dynamic> _profile(String wire) =>
      profiles.putIfAbsent(wire, () => aboutUsJson(draft: wire == 'draft'));

  Future<Object?> call(String fn, Map<String, dynamic>? params) async {
    calls.add((fn, params));
    final wait = hold;
    if (wait != null) await wait.future;
    final once = failNext;
    if (once != null) {
      failNext = null;
      throw once;
    }
    if (failAlways != null) throw failAlways!;
    switch (fn) {
      case 'get_couple_profile':
        return Map<String, dynamic>.from(
          _profile(params!['p_relationship_id'] as String),
        );
      case 'get_my_couple_profile_draft':
        return Map<String, dynamic>.from(_profile('draft'));
      case 'update_couple_profile':
      case 'update_my_couple_profile_draft':
        if (failUpdates != null) throw failUpdates!;
        final wire =
            fn == 'update_my_couple_profile_draft'
                ? 'draft'
                : params!['p_relationship_id'] as String;
        final profile = _profile(wire);
        final patch = Map<String, dynamic>.from(params!['p_patch'] as Map);
        final changes = Map<String, Object?>.from(
          profile['changes'] as Map? ?? const {},
        );
        final now = DateTime.now().toUtc().toIso8601String();
        void mark(String field) {
          if (wire != 'draft') {
            changes[field] = {'changed_by_me': true, 'changed_at': now};
          }
        }

        if (patch.containsKey('together_since')) {
          profile['together_since'] = patch['together_since'];
          profile['together_since_precision'] =
              patch['together_since_precision'];
          mark('together_since');
        }
        if (patch.containsKey('stage')) {
          profile['stage'] = patch['stage'];
          profile['stage_words'] = patch['stage_words'];
          if (patch['stage'] != 'married' && !patch.containsKey('ceremonies')) {
            profile['ceremonies'] = <Object?>[];
          }
          mark('stage');
        }
        if (patch.containsKey('ceremonies')) {
          profile['ceremonies'] = patch['ceremonies'];
          mark('ceremonies');
        }
        if (patch.containsKey('living')) {
          profile['living'] = patch['living'];
          mark('living');
        }
        if (patch.containsKey('children')) {
          profile['children'] = patch['children'];
          profile['child_age_bands'] = patch['child_age_bands'] ?? <String>[];
          mark('children');
        }
        if (patch.containsKey('anniversary_source')) {
          profile['anniversary_source'] = patch['anniversary_source'];
          mark('anniversary');
        }
        profile['changes'] = changes;
        return Map<String, dynamic>.from(profile);
      default:
        return null;
    }
  }

  static PostgrestException refusal(String message) =>
      PostgrestException(message: message, code: 'P0001');
}
```

Create `test/features/couple_profile/w5/couple_profile_data_test.dart` with exactly:

```dart
// Spec 1 W5 (§3.8 About us, §3.14, §4.3 W5, §5.3, §5.8): the model reads
// the server's answers (attribution as a first name, never an id), the
// patches are the server's keys, the service puts refusals in the app's
// hands, the offline outbox queues per account and replays, the effective
// flag needs flow_couples_v2, and the outbox is wiped at sign-out only.
import 'dart:async';

import 'package:attune/app/device_wipes.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/auth/sign_up/presentation/sign_up_flags.dart';
import 'package:attune/features/couple_profile/data/about_us_outbox.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/domain/couple_profile.dart';
import 'package:attune/features/couple_profile/presentation/couple_profile_providers.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    show togetherChangeSignalProvider;
import 'package:attune/home/home_seams.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/fake_couple_profile.dart';
import '../../../helpers/fake_home_state.dart';
import '../../../helpers/home_harness.dart';

const _rel = 'rel-w5';

void main() {
  test('MyDateFormat: month name, month and year, year (W5)', () {
    expect(MyDateFormat.toMonth(DateTime(2024, 10, 9)), 'October');
    expect(MyDateFormat.toMonthYear(DateTime(2024, 10, 9)), 'October 2024');
    expect(MyDateFormat.toYear(DateTime(1999, 4, 2)), '1999');
  });

  test('a profile reads every answer and the attribution, never an id', () {
    final profile = CoupleProfile.fromJson(
      aboutUsJson(
        readOnly: true,
        readUntil: '2026-12-01T10:00:00+00:00',
        togetherSince: '2024-10-01',
        precision: 'month',
        stage: 'married',
        ceremonies: [
          {'year': 1999, 'label': 'customary'},
          {'year': 2004, 'month': 8, 'day': 14, 'label': 'church'},
        ],
        living: 'apart_nearby',
        children: 'yes',
        bands: ['13to17', '18plus', 'teen'],
        anniversary: 'ceremony_2',
        reminderId: 'rem-1',
        changes: {
          'stage': {
            'changed_by_me': false,
            'changed_by_first_name': 'Yaw',
            'changed_at': '2026-11-01T09:00:00+00:00',
          },
          'living': {
            'changed_by_me': true,
            'changed_at': '2026-11-02T09:00:00+00:00',
          },
          'children': {'changed_by_me': true},
        },
      ),
    );
    expect(profile.readOnly, isTrue);
    expect(profile.readUntil, DateTime.utc(2026, 12, 1, 10).toLocal());
    expect(
      profile.togetherSince,
      TogetherSince(DateTime(2024, 10), DatePrecision.month),
    );
    expect(profile.stage, CoupleStage.married);
    expect(profile.ceremonies, [
      const Ceremony(year: 1999, label: CeremonyLabel.customary),
      const Ceremony(
        year: 2004,
        month: 8,
        day: 14,
        label: CeremonyLabel.church,
      ),
    ]);
    expect(profile.living, Living.apartNearby);
    expect(profile.children, Children.yes);
    expect(profile.childAgeBands, [
      ChildAgeBand.thirteenToSeventeen,
      ChildAgeBand.eighteenPlus,
    ], reason: 'an unknown band is dropped');
    expect(profile.anniversarySource, AnniversarySource.ceremony2);
    expect(profile.anniversaryDate, DateTime(2004, 8, 14));
    expect(profile.anniversaryReminderId, 'rem-1');
    expect(profile.changes[AboutUsField.stage]!.byFirstName, 'Yaw');
    expect(profile.changes[AboutUsField.stage]!.byMe, isFalse);
    expect(profile.changes[AboutUsField.living]!.byMe, isTrue);
    expect(
      profile.changes.containsKey(AboutUsField.children),
      isFalse,
      reason: 'no time, no line',
    );
    expect(profile.isEmpty, isFalse);
    expect(CoupleProfile.fromJson(aboutUsJson()).isEmpty, isTrue);
  });

  test('patches carry only the answered question\'s server keys', () {
    expect(AboutUsPatch.stage(CoupleStage.other, words: 'Courting').values, {
      'stage': 'other',
      'stage_words': 'Courting',
    });
    expect(AboutUsPatch.stage(CoupleStage.dating, words: 'ignored').values, {
      'stage': 'dating',
      'stage_words': null,
    });
    expect(
      AboutUsPatch.togetherSince(
        TogetherSince(DateTime(2024, 10, 9), DatePrecision.day),
      ).values,
      {'together_since': '2024-10-09', 'together_since_precision': 'day'},
    );
    expect(AboutUsPatch.togetherSince(null).values, {
      'together_since': null,
      'together_since_precision': null,
    });
    expect(
      AboutUsPatch.children(Children.none, bands: [ChildAgeBand.under2]).values,
      {'children': 'none', 'child_age_bands': <String>[]},
      reason: 'bands only with Yes',
    );
    expect(
      AboutUsPatch.anniversary(
        AnniversarySource.togetherSince,
        completedSince: TogetherSince(DateTime(2016, 3, 12), DatePrecision.day),
      ).values,
      {
        'together_since': '2016-03-12',
        'together_since_precision': 'day',
        'anniversary_source': 'together_since',
      },
    );
    final merged = AboutUsPatch.living(
      Living.together,
    ).merge(AboutUsPatch.living(Living.longDistance));
    expect(merged.values, {'living': 'long_distance'}, reason: 'last wins');
  });

  test('an answer queued offline shows the server\'s rules at once', () {
    final married = CoupleProfile.fromJson(
      aboutUsJson(
        stage: 'married',
        ceremonies: [
          {'year': 2010, 'month': 5, 'day': 1},
        ],
        anniversary: 'ceremony_1',
        children: 'yes',
        bands: ['2to5'],
      ),
    );
    final engaged = married.applying(AboutUsPatch.stage(CoupleStage.engaged));
    expect(engaged.ceremonies, isEmpty, reason: 'leaving Married');
    expect(engaged.anniversarySource, AnniversarySource.off);
    expect(engaged.pendingSync, isTrue);
    final noKids = married.applying(AboutUsPatch.children(Children.none));
    expect(noKids.childAgeBands, isEmpty);
    final month = married.applying(
      AboutUsPatch.togetherSince(
        TogetherSince(DateTime(2019, 6, 19), DatePrecision.month),
      ),
    );
    expect(month.togetherSince!.date, DateTime(2019, 6));
  });

  test('a future civil date is refused before it is sent', () {
    final today = DateTime(2026, 11, 2, 23, 59);
    expect(isFutureCivilDate(DateTime(2026, 11, 2), today), isFalse);
    expect(isFutureCivilDate(DateTime(2026, 11, 3), today), isTrue);
  });

  group('the service', () {
    test('calls the shared profile or the draft with its patch', () async {
      final server = FakeCoupleProfileServer();
      final service = CoupleProfileService(server.rpc);
      await service.fetch(const AboutUsTarget.shared(_rel));
      await service.fetch(const AboutUsTarget.draft());
      await service.update(
        const AboutUsTarget.shared(_rel),
        AboutUsPatch.living(Living.together),
      );
      await service.update(
        const AboutUsTarget.draft(),
        AboutUsPatch.living(Living.together),
      );
      expect(server.calls.map((c) => c.$1), [
        'get_couple_profile',
        'get_my_couple_profile_draft',
        'update_couple_profile',
        'update_my_couple_profile_draft',
      ]);
      expect(server.calls[0].$2, {'p_relationship_id': _rel});
      expect(server.calls[2].$2, {
        'p_relationship_id': _rel,
        'p_patch': {'living': 'together'},
      });
      expect(server.calls[3].$2, {
        'p_patch': {'living': 'together'},
      });
    });

    test('every refusal is typed; anything else is offline', () async {
      final server = FakeCoupleProfileServer();
      final service = CoupleProfileService(server.rpc);
      for (final (message, reason) in [
        ('couple_profile:read_only', AboutUsRefusal.readOnly),
        ('couple_profile:not_found', AboutUsRefusal.notFound),
        ('couple_profile:not_relationship', AboutUsRefusal.notRelationship),
        ('couple_profile:future_date', AboutUsRefusal.futureDate),
        (
          'couple_profile:too_many_ceremonies',
          AboutUsRefusal.tooManyCeremonies,
        ),
        (
          'couple_profile:ceremonies_need_married',
          AboutUsRefusal.ceremoniesNeedMarried,
        ),
        ('couple_profile:bands_need_yes', AboutUsRefusal.bandsNeedYes),
        (
          'couple_profile:anniversary_needs_day',
          AboutUsRefusal.anniversaryNeedsDay,
        ),
        ('couple_profile:unknown_key', AboutUsRefusal.invalid),
      ]) {
        server.failNext = FakeCoupleProfileServer.refusal(message);
        await expectLater(
          service.update(
            const AboutUsTarget.shared(_rel),
            AboutUsPatch.living(Living.together),
          ),
          throwsA(
            isA<AboutUsRefused>().having((r) => r.reason, 'reason', reason),
          ),
          reason: message,
        );
      }
      for (final error in [
        FakeCoupleProfileServer.refusal('permission denied'),
        TimeoutException('slow'),
      ]) {
        server.failNext = error;
        await expectLater(
          service.fetch(const AboutUsTarget.draft()),
          throwsA(isA<AboutUsOffline>()),
        );
      }
    });
  });

  group('the outbox', () {
    Future<(AboutUsOutbox, SharedPreferences)> outbox(
      String userId, [
      Map<String, Object> values = const {},
    ]) async {
      SharedPreferences.setMockInitialValues(values);
      final prefs = await SharedPreferences.getInstance();
      return (AboutUsOutbox(prefs, userId: userId), prefs);
    }

    test('queues per account and target, the last write winning', () async {
      final (box, prefs) = await outbox('u-a');
      await box.enqueue(
        const AboutUsTarget.shared(_rel),
        AboutUsPatch.living(Living.together),
      );
      await box.enqueue(
        const AboutUsTarget.shared(_rel),
        AboutUsPatch.living(
          Living.longDistance,
        ).merge(AboutUsPatch.stage(CoupleStage.dating)),
      );
      await box.enqueue(
        const AboutUsTarget.draft(),
        AboutUsPatch.living(Living.apartNearby),
      );
      expect(box.pending(const AboutUsTarget.shared(_rel))!.values, {
        'living': 'long_distance',
        'stage': 'dating',
        'stage_words': null,
      });
      expect(box.pending(const AboutUsTarget.draft())!.values, {
        'living': 'apart_nearby',
      });
      expect(prefs.getKeys(), {'attune.flow.u-a.about_us_outbox'});
      expect(
        AboutUsOutbox(
          prefs,
          userId: 'u-b',
        ).pending(const AboutUsTarget.draft()),
        isNull,
        reason: 'another account on the phone sees nothing',
      );
    });

    test('a replay sends, drops a refusal, keeps what is offline', () async {
      final (box, prefs) = await outbox('u-a');
      final server = FakeCoupleProfileServer();
      final service = CoupleProfileService(server.rpc);
      await box.enqueue(
        const AboutUsTarget.shared(_rel),
        AboutUsPatch.living(Living.together),
      );
      await box.flush(service);
      expect(server.count('update_couple_profile'), 1);
      expect(prefs.getKeys(), isEmpty, reason: 'sent');

      await box.enqueue(
        const AboutUsTarget.shared(_rel),
        AboutUsPatch.living(Living.together),
      );
      server.failNext = FakeCoupleProfileServer.refusal(
        'couple_profile:read_only',
      );
      await box.flush(service);
      expect(prefs.getKeys(), isEmpty, reason: 'a refusal cannot succeed');

      await box.enqueue(
        const AboutUsTarget.draft(),
        AboutUsPatch.living(Living.together),
      );
      server.failUpdates = TimeoutException('offline');
      for (var i = 1; i < AboutUsOutbox.maxAttempts; i++) {
        await box.flush(service);
        expect(
          box.pending(const AboutUsTarget.draft()),
          isNotNull,
          reason: '$i',
        );
      }
      await box.flush(service);
      expect(
        box.pending(const AboutUsTarget.draft()),
        isNull,
        reason: 'dropped after ${AboutUsOutbox.maxAttempts} tries',
      );
    });

    test('an answer queued while a replay runs is kept', () async {
      final (box, _) = await outbox('u-a');
      final server = FakeCoupleProfileServer();
      await box.enqueue(
        const AboutUsTarget.draft(),
        AboutUsPatch.living(Living.together),
      );
      server.hold = Completer<void>();
      final replay = box.flush(CoupleProfileService(server.rpc));
      await Future<void>.delayed(Duration.zero);
      await box.enqueue(
        const AboutUsTarget.draft(),
        AboutUsPatch.living(Living.longDistance),
      );
      server.hold!.complete();
      await replay;
      expect(box.pending(const AboutUsTarget.draft())!.values, {
        'living': 'long_distance',
      });
    });

    test('wiped at sign-out for every account, never on quick exit', () async {
      final registry = DeviceWipeRegistry();
      registerDeviceWipes(registry);
      final entry = spec1DeviceWipes().firstWhere(
        (e) => e.id == 'spec1.about_us_outbox',
      );
      expect(entry.moments, {WipeMoment.signOut});
      expect(entry.keys.join(), isNot(contains('dating')));
      SharedPreferences.setMockInitialValues({
        'attune.flow.u-a.about_us_outbox': '{}',
        'attune.flow.u-b.about_us_outbox': '{}',
        'attune.flow.u-a.partner_first_name': 'Ama',
      });
      await registry.run(WipeMoment.signOut);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where(AboutUsOutbox.isOutboxKey), isEmpty);
    });
  });

  test(
    'the shared profile refetches on a together signal, not on subscribe',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final server = FakeCoupleProfileServer();
      final signals = StreamController<void>.broadcast();
      addTearDown(signals.close);
      final c = ProviderContainer(
        overrides: [
          coupleProfileRpcProvider.overrideWithValue(server.rpc),
          sharedPreferencesProvider.overrideWithValue(prefs),
          homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-a'))),
          togetherChangeSignalProvider.overrideWith(
            (ref, id) => signals.stream,
          ),
        ],
      );
      addTearDown(c.dispose);
      const target = AboutUsTarget.shared(_rel);
      final keep = c.listen(coupleProfileProvider(target), (_, __) {});
      addTearDown(keep.close);
      await c.read(coupleProfileProvider(target).future);
      expect(server.count('get_couple_profile'), 1);
      signals.add(null); // the subscription itself
      await Future<void>.delayed(Duration.zero);
      expect(server.count('get_couple_profile'), 1);
      server.profiles[_rel] = aboutUsJson(living: 'together');
      signals.add(null); // the partner's edit
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(server.count('get_couple_profile'), 2);
      expect(
        c.read(coupleProfileProvider(target)).value!.living,
        Living.together,
      );
    },
  );

  test('couple_profile is effective only with flow_couples_v2', () async {
    for (final (couples, profile, want) in [
      (true, true, true),
      (true, false, false),
      (false, true, false),
    ]) {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          signInFlowV2Provider.overrideWithValue(true),
          flowFlagsGatewayProvider.overrideWithValue(
            FakeFlowFlagsGateway(
              pathsV2: true,
              couplesV2: couples,
              coupleProfile: profile,
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(flowFlagsProvider.future);
      expect(
        c.read(coupleProfileEnabledProvider),
        want,
        reason: '$couples $profile',
      );
    }
    // The cached copy carries it to the next first frame.
    SharedPreferences.setMockInitialValues({
      FlowFlagsCache.key: '{"paths":true,"couples":true,"couple_profile":true}',
    });
    final prefs = await SharedPreferences.getInstance();
    expect(FlowFlagsCache(prefs).read()!.coupleProfile, isTrue);
  });
}
```

Create `test/features/couple_profile/w5/about_us_sync_test.dart` with exactly:

```dart
// Spec 1 W5 (§3.14, §5.2): OnboardingSyncService replays queued About us
// answers after the path, and a failed replay never stops the rest.
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/fake_home_state.dart';

void main() {
  test('a flush replays About us answers; a failure is contained', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = OnboardingStore(prefs, scope: 'user.u-sync');
    var replays = 0;
    final service = OnboardingSyncService(
      homeStateService: HomeStateService(FakeHomeStateGateway()),
      flushAboutUs: () async => replays++,
    );
    await service.flush(store);
    expect(replays, 1);

    final failing = OnboardingSyncService(
      homeStateService: HomeStateService(FakeHomeStateGateway()),
      flushAboutUs: () async => throw StateError('offline'),
    );
    await expectLater(failing.flush(store), completes);
  });
}
```

Create `test/architecture/couple_profile_never_typed_test.dart` with exactly:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Spec 1 W5 (§7.1 "Never a type or score", the permanent constraint: no
/// couple type, score or partner scorecard, no couple report combining
/// both people's insights). About us is plain facts the couple chose to
/// tell. Its model and its tables are read only inside its own feature,
/// never by an AI loader or a prompt builder, so nothing can turn the
/// answers into a label. The SQL side is couple_profile_contracts.sql
/// section A.
void main() {
  /// The About us model, its provider and the server names.
  final aboutUsNames = RegExp(
    r'\b(CoupleProfile|CoupleStage|AboutUsPatch|coupleProfileProvider|coupleProfileDraftProvider)\b'
    r'|couple_profiles|couple_profile_drafts|get_couple_profile|update_couple_profile'
    r'|get_my_couple_profile_draft|update_my_couple_profile_draft',
  );

  List<File> dartFiles(String root) =>
      Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.contains('/generated/'))
          .toList();

  test(
    'the About us model is read only inside lib/features/couple_profile',
    () {
      final outside = [
        for (final f in dartFiles('lib'))
          if (!f.path.startsWith('lib/features/couple_profile/') &&
              aboutUsNames.hasMatch(f.readAsStringSync()))
            f.path,
      ];
      expect(
        outside,
        isEmpty,
        reason:
            'About us is plain facts, never a type or a score: only its own '
            'feature reads the model (others use its entry points).',
      );
    },
  );

  test('no edge function reads About us (no AI loader, no prompt)', () {
    final readers = [
      for (final f
          in Directory(
            'supabase/functions',
          ).listSync(recursive: true).whereType<File>())
        if (RegExp(
          r'couple_profile|about_us|aboutUs',
          caseSensitive: false,
        ).hasMatch(f.readAsStringSync()))
          f.path,
    ];
    expect(readers, isEmpty);
  });

  test('W1\'s set_user_path_internal named no W5 table (review I-6)', () {
    final sql =
        File(
          'supabase/migrations/20261025100300_paths_and_home_state.sql',
        ).readAsStringSync();
    final start = sql.indexOf(
      'CREATE OR REPLACE FUNCTION public.set_user_path_internal(',
    );
    final body = sql.substring(start, sql.indexOf('\n\$\$;', start));
    expect(body, isNot(contains('couple_profile')));
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

```bash
flutter test --no-pub test/features/couple_profile/w5/couple_profile_data_test.dart test/features/couple_profile/w5/about_us_sync_test.dart test/architecture/couple_profile_never_typed_test.dart 2>&1 | tr '\r' '\n' | grep -E "Error: |Some tests failed|All tests passed" | head -6
```

Expected: compile errors naming the missing `package:attune/features/couple_profile/...` files and the unknown named parameters `coupleProfile` and `flushAboutUs`, then `Some tests failed.` (the architecture test alone would pass: there is nothing to find yet).

- [ ] **Step 3: The flag (P-12)**

In `lib/core/flags/signed_in_flow_flags.dart`:

Edit 1 of 5. Replace exactly:

```dart
import 'package:shared_preferences/shared_preferences.dart';

/// The two signed-in Spec 1 flags W3 reads (spec §2.5, §5.3), as stored:
/// `flow_paths_v2` and `flow_couples_v2`. The providers in
/// features/onboarding/presentation/providers/flow_flags.dart turn them
/// into the effective value (the flag and everything it needs). Here, in
```

with:

```dart
import 'package:shared_preferences/shared_preferences.dart';

/// The signed-in Spec 1 flags (spec §2.5, §5.3), as stored:
/// `flow_paths_v2`, `flow_couples_v2` and (W5) `couple_profile`. The providers in
/// features/onboarding/presentation/providers/flow_flags.dart turn them
/// into the effective value (the flag and everything it needs). Here, in
```

Edit 2 of 5. Replace exactly:

```dart
@immutable
class SignedInFlowFlags {
  const SignedInFlowFlags({required this.pathsV2, required this.couplesV2});

  /// What an unreadable flag means: off.
```

with:

```dart
@immutable
class SignedInFlowFlags {
  const SignedInFlowFlags({
    required this.pathsV2,
    required this.couplesV2,
    this.coupleProfile = false,
  });

  /// What an unreadable flag means: off.
```

Edit 3 of 5. Replace exactly:

```dart
  final bool couplesV2;

  @override
  bool operator ==(Object other) =>
      other is SignedInFlowFlags &&
      other.pathsV2 == pathsV2 &&
      other.couplesV2 == couplesV2;

  @override
  int get hashCode => Object.hash(pathsV2, couplesV2);
}

```

with:

```dart
  final bool couplesV2;

  /// Spec 1 W5: About us.
  final bool coupleProfile;

  @override
  bool operator ==(Object other) =>
      other is SignedInFlowFlags &&
      other.pathsV2 == pathsV2 &&
      other.couplesV2 == couplesV2 &&
      other.coupleProfile == coupleProfile;

  @override
  int get hashCode => Object.hash(pathsV2, couplesV2, coupleProfile);
}

```

Edit 4 of 5. Replace exactly:

```dart
        pathsV2: json['paths'] == true,
        couplesV2: json['couples'] == true,
      );
    } catch (_) {
```

with:

```dart
        pathsV2: json['paths'] == true,
        couplesV2: json['couples'] == true,
        coupleProfile: json['couple_profile'] == true,
      );
    } catch (_) {
```

Edit 5 of 5. Replace exactly:

```dart
  Future<void> write(SignedInFlowFlags flags) => _prefs.setString(
    key,
    jsonEncode({'paths': flags.pathsV2, 'couples': flags.couplesV2}),
  );
}
```

with:

```dart
  Future<void> write(SignedInFlowFlags flags) => _prefs.setString(
    key,
    jsonEncode({
      'paths': flags.pathsV2,
      'couples': flags.couplesV2,
      // Spec 1 W5: written only when on, so the W3 shape is unchanged
      // while it is off (an absent key reads as off).
      if (flags.coupleProfile) 'couple_profile': true,
    }),
  );
}
```

In `lib/features/onboarding/presentation/providers/flow_flags.dart`:

Edit 1 of 3. Replace exactly:

```dart
        .from('feature_flags')
        .select('key, enabled')
        .inFilter('key', const ['flow_paths_v2', 'flow_couples_v2'])
        .timeout(timeout);
    bool on(String key) =>
```

with:

```dart
        .from('feature_flags')
        .select('key, enabled')
        .inFilter('key', const [
          'flow_paths_v2',
          'flow_couples_v2',
          'couple_profile',
        ])
        .timeout(timeout);
    bool on(String key) =>
```

Edit 2 of 3. Replace exactly:

```dart
      pathsV2: on('flow_paths_v2'),
      couplesV2: on('flow_couples_v2'),
    );
  }
```

with:

```dart
      pathsV2: on('flow_paths_v2'),
      couplesV2: on('flow_couples_v2'),
      coupleProfile: on('couple_profile'),
    );
  }
```

Edit 3 of 3. Replace exactly:

```dart
});

/// Batch-5 review I-1 (D9): the signed-in flags are known, from an answer
/// this phone has had (this run's, whose cache write SharedPreferences
```

with:

```dart
});

/// couple_profile, effective: the flag and flow_couples_v2 (spec §2.5 A-6,
/// §5.3). Spec 1 W5: About us.
final coupleProfileEnabledProvider = Provider<bool>((ref) {
  if (!ref.watch(flowCouplesV2Provider)) return false;
  return _current(ref).coupleProfile;
});

/// Batch-5 review I-1 (D9): the signed-in flags are known, from an answer
/// this phone has had (this run's, whose cache write SharedPreferences
```

- [ ] **Step 4: The model**

Create `lib/features/couple_profile/domain/couple_profile.dart` with exactly:

```dart
import 'package:flutter/foundation.dart';

/// About us (Spec 1 §3.8 AU1-AU6, §4.2 `couple_profiles`): the couple's
/// shared answers, or one inviter's draft before linking. Plain facts the
/// couple chose to tell, each attributed. Never a type, a score or a label
/// (permanent constraint): nothing here derives anything from the answers,
/// and test/architecture/couple_profile_never_typed_test.dart keeps every
/// reader of this model inside lib/features/couple_profile/.

/// AU1 · Where the two of you are.
enum CoupleStage {
  dating('dating'),
  engaged('engaged'),
  married('married'),
  other('other');

  const CoupleStage(this.wire);

  final String wire;

  static CoupleStage? fromWire(Object? value) {
    for (final stage in values) {
      if (stage.wire == value) return stage;
    }
    return null;
  }
}

/// AU2 · How much of "When did you two get together?" was given.
enum DatePrecision {
  day,
  month,
  year;

  String get wire => name;

  static DatePrecision? fromWire(Object? value) {
    for (final precision in values) {
      if (precision.wire == value) return precision;
    }
    return null;
  }
}

/// AU3 · An optional label for a ceremony.
enum CeremonyLabel {
  customary,
  church,
  mosque,
  civil,
  other;

  String get wire => name;

  static CeremonyLabel? fromWire(Object? value) {
    for (final label in values) {
      if (label.wire == value) return label;
    }
    return null;
  }
}

/// AU4 · Where the two of you live. No option ranks above another.
enum Living {
  together('together'),
  apartNearby('apart_nearby'),
  longDistance('long_distance');

  const Living(this.wire);

  final String wire;

  static Living? fromWire(Object? value) {
    for (final living in values) {
      if (living.wire == value) return living;
    }
    return null;
  }
}

/// AU5 · Children in your life together. No names, counts or "yet".
enum Children {
  none('none'),
  yes('yes'),
  expecting('expecting'),
  preferNotToSay('prefer_not_to_say');

  const Children(this.wire);

  final String wire;

  static Children? fromWire(Object? value) {
    for (final children in values) {
      if (children.wire == value) return children;
    }
    return null;
  }
}

/// AU5 · Their ages, as bands, only with [Children.yes].
enum ChildAgeBand {
  under2('under2'),
  twoToFive('2to5'),
  sixToTwelve('6to12'),
  thirteenToSeventeen('13to17'),
  eighteenPlus('18plus');

  const ChildAgeBand(this.wire);

  final String wire;

  static ChildAgeBand? fromWire(Object? value) {
    for (final band in values) {
      if (band.wire == value) return band;
    }
    return null;
  }
}

/// AU6 · The one source of Together's anniversary reminder.
enum AnniversarySource {
  off('off'),
  togetherSince('together_since'),
  ceremony1('ceremony_1'),
  ceremony2('ceremony_2');

  const AnniversarySource(this.wire);

  final String wire;

  static AnniversarySource fromWire(Object? value) {
    for (final source in values) {
      if (source.wire == value) return source;
    }
    return off;
  }
}

/// The six attributed fields (one "Changed by" line each).
enum AboutUsField {
  togetherSince('together_since'),
  stage('stage'),
  ceremonies('ceremonies'),
  living('living'),
  children('children'),
  anniversary('anniversary');

  const AboutUsField(this.wire);

  final String wire;
}

/// `YYYY-MM-DD` for a civil date (no time, no zone).
String aboutUsWireDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime? _civilDate(Object? value) {
  if (value is! String) return null;
  final parsed = DateTime.tryParse(value);
  return parsed == null
      ? null
      : DateTime(parsed.year, parsed.month, parsed.day);
}

/// True when [date] is after [today] (both civil dates): AU2 and AU3 never
/// take one ("That date is in the future.").
bool isFutureCivilDate(DateTime date, DateTime today) => DateTime(
  date.year,
  date.month,
  date.day,
).isAfter(DateTime(today.year, today.month, today.day));

/// AU2's answer. The server keeps a month as its 1st and a year as 1 January.
@immutable
class TogetherSince {
  const TogetherSince(this.date, this.precision);

  final DateTime date;
  final DatePrecision precision;

  /// A full date, as AU6 needs.
  bool get hasDay => precision == DatePrecision.day;

  @override
  bool operator ==(Object other) =>
      other is TogetherSince &&
      other.precision == precision &&
      aboutUsWireDate(other.date) == aboutUsWireDate(date);

  @override
  int get hashCode => Object.hash(aboutUsWireDate(date), precision);
}

/// AU3's answer: a year, an optional month and day, an optional label.
@immutable
class Ceremony {
  const Ceremony({required this.year, this.month, this.day, this.label});

  final int year;
  final int? month;
  final int? day;
  final CeremonyLabel? label;

  /// A full date, as AU6 needs; null without a month and a day.
  DateTime? get fullDate =>
      month == null || day == null ? null : DateTime(year, month!, day!);

  Map<String, Object?> toJson() => {
    'year': year,
    if (month != null) 'month': month,
    if (day != null) 'day': day,
    if (label != null) 'label': label!.wire,
  };

  static Ceremony? fromJson(Object? json) {
    if (json is! Map) return null;
    final year = json['year'];
    if (year is! int) return null;
    final month = json['month'];
    final day = json['day'];
    return Ceremony(
      year: year,
      month: month is int ? month : null,
      day: day is int ? day : null,
      label: CeremonyLabel.fromWire(json['label']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Ceremony &&
      other.year == year &&
      other.month == month &&
      other.day == day &&
      other.label == label;

  @override
  int get hashCode => Object.hash(year, month, day, label);
}

/// Who last changed a field and when: the server sends a first name or
/// "me", never an account id (spec §4.3 W5).
@immutable
class FieldChange {
  const FieldChange({required this.byMe, this.byFirstName, required this.at});

  final bool byMe;
  final String? byFirstName;
  final DateTime at;

  static FieldChange? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = json['changed_at'];
    final parsed = at is String ? DateTime.tryParse(at) : null;
    if (parsed == null) return null;
    final name = (json['changed_by_first_name'] as String?)?.trim();
    return FieldChange(
      byMe: json['changed_by_me'] == true,
      byFirstName: name == null || name.isEmpty ? null : name,
      at: parsed.toLocal(),
    );
  }
}

/// get_couple_profile() or get_my_couple_profile_draft() (spec §4.3 W5).
@immutable
class CoupleProfile {
  const CoupleProfile({
    this.isDraft = false,
    this.readOnly = false,
    this.readUntil,
    this.togetherSince,
    this.stage,
    this.stageWords,
    this.ceremonies = const [],
    this.living,
    this.children,
    this.childAgeBands = const [],
    this.anniversarySource = AnniversarySource.off,
    this.anniversaryReminderId,
    this.changes = const {},
    this.pendingSync = false,
  });

  static const emptyDraft = CoupleProfile(isDraft: true);

  final bool isDraft;

  /// Paused or inside the ending window: read, never written.
  final bool readOnly;

  /// When a read-only profile goes ("You can read this until {date}.").
  final DateTime? readUntil;
  final TogetherSince? togetherSince;
  final CoupleStage? stage;
  final String? stageWords;
  final List<Ceremony> ceremonies;
  final Living? living;
  final Children? children;
  final List<ChildAgeBand> childAgeBands;
  final AnniversarySource anniversarySource;

  /// The one Together reminder About us keeps (its sheet points back here).
  final String? anniversaryReminderId;
  final Map<AboutUsField, FieldChange> changes;

  /// An answer given offline that hasn't reached the server yet.
  final bool pendingSync;

  /// No question answered yet.
  bool get isEmpty =>
      togetherSince == null &&
      stage == null &&
      ceremonies.isEmpty &&
      living == null &&
      children == null &&
      anniversarySource == AnniversarySource.off;

  /// The date the anniversary reminder follows, when it has a full date.
  DateTime? get anniversaryDate => switch (anniversarySource) {
    AnniversarySource.off => null,
    AnniversarySource.togetherSince =>
      togetherSince != null && togetherSince!.hasDay
          ? togetherSince!.date
          : null,
    AnniversarySource.ceremony1 =>
      ceremonies.isNotEmpty ? ceremonies[0].fullDate : null,
    AnniversarySource.ceremony2 =>
      ceremonies.length > 1 ? ceremonies[1].fullDate : null,
  };

  factory CoupleProfile.fromJson(Map<String, dynamic> json) {
    final since = _civilDate(json['together_since']);
    final precision = DatePrecision.fromWire(json['together_since_precision']);
    final rawCeremonies = json['ceremonies'];
    final rawBands = json['child_age_bands'];
    final rawChanges = json['changes'];
    final readUntil = json['read_until'];
    return CoupleProfile(
      isDraft: json['draft'] == true,
      readOnly: json['read_only'] == true,
      readUntil:
          readUntil is String ? DateTime.tryParse(readUntil)?.toLocal() : null,
      togetherSince:
          since == null || precision == null
              ? null
              : TogetherSince(since, precision),
      stage: CoupleStage.fromWire(json['stage']),
      stageWords: json['stage_words'] as String?,
      ceremonies: [
        if (rawCeremonies is List)
          for (final item in rawCeremonies)
            if (Ceremony.fromJson(item) case final ceremony?) ceremony,
      ],
      living: Living.fromWire(json['living']),
      children: Children.fromWire(json['children']),
      childAgeBands: [
        if (rawBands is List)
          for (final band in rawBands)
            if (ChildAgeBand.fromWire(band) case final known?) known,
      ],
      anniversarySource: AnniversarySource.fromWire(json['anniversary_source']),
      anniversaryReminderId: json['anniversary_reminder_id'] as String?,
      changes: {
        if (rawChanges is Map)
          for (final field in AboutUsField.values)
            if (FieldChange.fromJson(rawChanges[field.wire]) case final c?)
              field: c,
      },
    );
  }

  /// [patch] applied the way update_couple_profile applies it, for an
  /// answer queued offline (spec §3.8: offline edits queue and replay). The
  /// server's answer replaces this once it arrives.
  CoupleProfile applying(AboutUsPatch patch) {
    final v = patch.values;
    var since = togetherSince;
    if (v.containsKey('together_since')) {
      final date = _civilDate(v['together_since']);
      final precision = DatePrecision.fromWire(v['together_since_precision']);
      since =
          date == null || precision == null
              ? null
              : TogetherSince(switch (precision) {
                DatePrecision.day => date,
                DatePrecision.month => DateTime(date.year, date.month),
                DatePrecision.year => DateTime(date.year),
              }, precision);
    }
    var nextStage = stage;
    var words = stageWords;
    if (v.containsKey('stage')) {
      nextStage = CoupleStage.fromWire(v['stage']);
      words =
          nextStage == CoupleStage.other ? v['stage_words'] as String? : null;
    }
    var nextCeremonies = ceremonies;
    if (v.containsKey('ceremonies')) {
      final raw = v['ceremonies'];
      nextCeremonies = [
        if (raw is List)
          for (final item in raw)
            if (Ceremony.fromJson(item) case final ceremony?) ceremony,
      ];
    } else if (nextStage != CoupleStage.married) {
      nextCeremonies = const [];
    }
    var nextChildren = children;
    var bands = childAgeBands;
    if (v.containsKey('children')) {
      nextChildren = Children.fromWire(v['children']);
      final raw = v['child_age_bands'];
      bands =
          nextChildren == Children.yes && raw is List
              ? [
                for (final band in raw)
                  if (ChildAgeBand.fromWire(band) case final known?) known,
              ]
              : const [];
    }
    var source = anniversarySource;
    if (v.containsKey('anniversary_source')) {
      source = AnniversarySource.fromWire(v['anniversary_source']);
    }
    if ((source == AnniversarySource.ceremony1 && nextCeremonies.isEmpty) ||
        (source == AnniversarySource.ceremony2 && nextCeremonies.length < 2)) {
      source = AnniversarySource.off;
    }
    return CoupleProfile(
      isDraft: isDraft,
      readOnly: readOnly,
      readUntil: readUntil,
      togetherSince: since,
      stage: nextStage,
      stageWords: words,
      ceremonies: nextCeremonies,
      living: v.containsKey('living') ? Living.fromWire(v['living']) : living,
      children: nextChildren,
      childAgeBands: bands,
      anniversarySource: source,
      anniversaryReminderId: anniversaryReminderId,
      changes: changes,
      pendingSync: true,
    );
  }
}

/// One answer as update_couple_profile / update_my_couple_profile_draft
/// take it (`p_patch`): only the keys of the question answered.
@immutable
class AboutUsPatch {
  const AboutUsPatch(this.values);

  final Map<String, Object?> values;

  /// AU1. [words] only with [CoupleStage.other] (40 characters).
  factory AboutUsPatch.stage(CoupleStage? stage, {String? words}) =>
      AboutUsPatch({
        'stage': stage?.wire,
        'stage_words': stage == CoupleStage.other ? words : null,
      });

  /// AU2; null clears it.
  factory AboutUsPatch.togetherSince(TogetherSince? since) => AboutUsPatch({
    'together_since': since == null ? null : aboutUsWireDate(since.date),
    'together_since_precision': since?.precision.wire,
  });

  /// AU3: at most two.
  factory AboutUsPatch.ceremonies(List<Ceremony> ceremonies) => AboutUsPatch({
    'ceremonies': [for (final c in ceremonies) c.toJson()],
  });

  /// AU4.
  factory AboutUsPatch.living(Living? living) =>
      AboutUsPatch({'living': living?.wire});

  /// AU5: the bands only with [Children.yes].
  factory AboutUsPatch.children(
    Children? children, {
    List<ChildAgeBand> bands = const [],
  }) => AboutUsPatch({
    'children': children?.wire,
    'child_age_bands':
        children == Children.yes ? [for (final b in bands) b.wire] : <String>[],
  });

  /// AU6, with the full date AU6's "What day was it?" just completed, if
  /// any, in the same write.
  factory AboutUsPatch.anniversary(
    AnniversarySource source, {
    TogetherSince? completedSince,
    List<Ceremony>? completedCeremonies,
  }) => AboutUsPatch({
    if (completedSince != null)
      ...AboutUsPatch.togetherSince(completedSince).values,
    if (completedCeremonies != null)
      ...AboutUsPatch.ceremonies(completedCeremonies).values,
    'anniversary_source': source.wire,
  });

  static AboutUsPatch? fromJson(Object? json) =>
      json is Map ? AboutUsPatch(Map<String, Object?>.from(json)) : null;

  /// [later]'s keys win: the last write wins (spec §3.8).
  AboutUsPatch merge(AboutUsPatch later) =>
      AboutUsPatch({...values, ...later.values});
}
```

- [ ] **Step 5: The service and the outbox**

Create `lib/features/couple_profile/data/couple_profile_service.dart` with exactly:

```dart
import 'dart:async';
import 'dart:io';

import 'package:attune/features/couple_profile/domain/couple_profile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where an About us answer goes: one relationship's shared profile, or
/// this account's own draft before linking (spec §4.2; the draft is per
/// account, so nobody's answers reach another account on a shared phone).
@immutable
class AboutUsTarget {
  const AboutUsTarget.shared(String this.relationshipId);

  const AboutUsTarget.draft() : relationshipId = null;

  final String? relationshipId;

  bool get isDraft => relationshipId == null;

  /// The outbox key part: the relationship id, or `draft`.
  String get wire => relationshipId ?? 'draft';

  static AboutUsTarget fromWire(String wire) =>
      wire == 'draft'
          ? const AboutUsTarget.draft()
          : AboutUsTarget.shared(wire);

  @override
  bool operator ==(Object other) =>
      other is AboutUsTarget && other.relationshipId == relationshipId;

  @override
  int get hashCode => relationshipId.hashCode;
}

/// The server's `couple_profile:*` refusals (spec §4.3 W5), each answered
/// in the app's own words.
enum AboutUsRefusal {
  notFound,
  readOnly,
  notRelationship,
  futureDate,
  tooManyCeremonies,
  ceremoniesNeedMarried,
  bandsNeedYes,
  anniversaryNeedsDay,
  invalid,
}

class AboutUsRefused implements Exception {
  const AboutUsRefused(this.reason);

  final AboutUsRefusal reason;

  static AboutUsRefusal reasonOf(String message) => switch (message) {
    'couple_profile:not_found' => AboutUsRefusal.notFound,
    'couple_profile:read_only' => AboutUsRefusal.readOnly,
    'couple_profile:not_relationship' => AboutUsRefusal.notRelationship,
    'couple_profile:future_date' => AboutUsRefusal.futureDate,
    'couple_profile:too_many_ceremonies' => AboutUsRefusal.tooManyCeremonies,
    'couple_profile:ceremonies_need_married' =>
      AboutUsRefusal.ceremoniesNeedMarried,
    'couple_profile:bands_need_yes' => AboutUsRefusal.bandsNeedYes,
    'couple_profile:anniversary_needs_day' =>
      AboutUsRefusal.anniversaryNeedsDay,
    _ => AboutUsRefusal.invalid,
  };
}

/// No answer from the server (offline, a timeout, a server error): the
/// write is queued and replayed (spec §3.14).
class AboutUsOffline implements Exception {
  const AboutUsOffline();
}

typedef CoupleProfileRpc =
    Future<Object?> Function(String fn, Map<String, dynamic>? params);

final coupleProfileRpcProvider = Provider<CoupleProfileRpc>(
  (ref) => (fn, params) => Supabase.instance.client.rpc(fn, params: params),
);

/// The four About us calls (spec §4.3 W5) behind one seam.
class CoupleProfileService {
  CoupleProfileService(this._rpc);

  final CoupleProfileRpc _rpc;

  static const timeout = Duration(seconds: 15);

  Future<CoupleProfile> fetch(AboutUsTarget target) async => _profile(
    target.isDraft
        ? await _call('get_my_couple_profile_draft', null)
        : await _call('get_couple_profile', {
          'p_relationship_id': target.relationshipId,
        }),
  );

  Future<CoupleProfile> update(
    AboutUsTarget target,
    AboutUsPatch patch,
  ) async => _profile(
    target.isDraft
        ? await _call('update_my_couple_profile_draft', {
          'p_patch': patch.values,
        })
        : await _call('update_couple_profile', {
          'p_relationship_id': target.relationshipId,
          'p_patch': patch.values,
        }),
  );

  CoupleProfile _profile(Object? data) {
    if (data is! Map) throw const AboutUsOffline();
    return CoupleProfile.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Object?> _call(String fn, Map<String, dynamic>? params) async {
    try {
      return await _rpc(fn, params).timeout(timeout);
    } on PostgrestException catch (error) {
      if (error.message.startsWith('couple_profile:')) {
        throw AboutUsRefused(AboutUsRefused.reasonOf(error.message));
      }
      throw const AboutUsOffline();
    } on TimeoutException {
      throw const AboutUsOffline();
    } on IOException {
      throw const AboutUsOffline();
    } on http.ClientException {
      throw const AboutUsOffline();
    } on AuthRetryableFetchException {
      throw const AboutUsOffline();
    }
  }
}

final coupleProfileServiceProvider = Provider<CoupleProfileService>(
  (ref) => CoupleProfileService(ref.watch(coupleProfileRpcProvider)),
);
```

Create `lib/features/couple_profile/data/about_us_outbox.dart` with exactly:

```dart
import 'dart:convert';

import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/domain/couple_profile.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// About us answers given offline, per account and per target, replayed
/// later (spec §3.8 "offline edits queue and replay (last write wins,
/// attributed at replay)", §3.14). One key per account,
/// `attune.flow.<uid>.about_us_outbox`, a JSON map from the target's wire
/// (a relationship id or `draft`) to `{patch, attempts}`. Wiped at sign-out
/// for every account on the phone (device wipe `spec1.about_us_outbox`).
class AboutUsOutbox {
  AboutUsOutbox(this._prefs, {required this.userId});

  final SharedPreferences _prefs;
  final String userId;

  /// A replay that keeps failing for a reason other than a refusal is
  /// dropped after this many tries, so a queue can't grow forever.
  static const maxAttempts = 5;

  static String keyFor(String userId) => 'attune.flow.$userId.about_us_outbox';

  static bool isOutboxKey(String key) =>
      key.startsWith('attune.flow.') && key.endsWith('.about_us_outbox');

  String get _key => keyFor(userId);

  Map<String, Map<String, Object?>> _read() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return {};
      return {
        for (final entry in json.entries)
          if (entry.key is String && entry.value is Map)
            entry.key as String: Map<String, Object?>.from(entry.value as Map),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _write(Map<String, Map<String, Object?>> entries) =>
      entries.isEmpty
          ? _prefs.remove(_key)
          : _prefs.setString(_key, jsonEncode(entries));

  /// What is still owed for [target], or null.
  AboutUsPatch? pending(AboutUsTarget target) =>
      AboutUsPatch.fromJson(_read()[target.wire]?['patch']);

  /// Queues [patch] for [target], on top of anything already queued (its
  /// keys win).
  Future<void> enqueue(AboutUsTarget target, AboutUsPatch patch) async {
    final entries = _read();
    final queued = AboutUsPatch.fromJson(entries[target.wire]?['patch']);
    entries[target.wire] = {
      'patch': (queued?.merge(patch) ?? patch).values,
      'attempts': 0,
    };
    await _write(entries);
  }

  Future<void> remove(AboutUsTarget target) async {
    final entries = _read()..remove(target.wire);
    await _write(entries);
  }

  /// Replays every queued answer. Sent: removed. Refused (the profile
  /// became read-only, a rule it breaks now): dropped, it can't succeed.
  /// Offline: kept, until [maxAttempts]. An answer queued while the replay
  /// ran is kept as it is. Never throws.
  Future<void> flush(CoupleProfileService service) async {
    final sent = _read();
    if (sent.isEmpty) return;
    final outcome = <String, Map<String, Object?>?>{};
    for (final entry in sent.entries) {
      final patch = AboutUsPatch.fromJson(entry.value['patch']);
      if (patch == null) {
        outcome[entry.key] = null;
        continue;
      }
      try {
        await service.update(AboutUsTarget.fromWire(entry.key), patch);
        outcome[entry.key] = null;
      } on AboutUsRefused catch (refused) {
        debugPrint('[about-us] queued answer refused: ${refused.reason.name}');
        outcome[entry.key] = null;
      } catch (_) {
        final attempts = ((entry.value['attempts'] as int?) ?? 0) + 1;
        if (attempts >= maxAttempts) {
          debugPrint('[about-us] queued answer dropped after $attempts tries');
        }
        outcome[entry.key] =
            attempts >= maxAttempts
                ? null
                : {'patch': patch.values, 'attempts': attempts};
      }
    }
    try {
      final latest = _read();
      for (final MapEntry(key: wire, value: result) in outcome.entries) {
        final now = latest[wire];
        if (now == null ||
            jsonEncode(now['patch']) != jsonEncode(sent[wire]?['patch'])) {
          continue;
        }
        if (result == null) {
          latest.remove(wire);
        } else {
          latest[wire] = result;
        }
      }
      await _write(latest);
    } catch (error) {
      debugPrint('[about-us] outbox write failed: ${error.runtimeType}');
    }
  }
}
```

- [ ] **Step 6: The providers**

Create `lib/features/couple_profile/presentation/couple_profile_providers.dart` with exactly:

```dart
import 'dart:async';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/couple_profile/data/about_us_outbox.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/domain/couple_profile.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    show togetherChangeSignalProvider;
import 'package:attune/home/home_seams.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The signed-in account's outbox, or null (signed out, or no
/// SharedPreferences in a bare test host).
final aboutUsOutboxProvider = Provider<AboutUsOutbox?>((ref) {
  final userId = ref.watch(homeAuthProvider).currentUser?.id;
  if (userId == null) return null;
  try {
    return AboutUsOutbox(ref.watch(sharedPreferencesProvider), userId: userId);
  } catch (_) {
    return null;
  }
});

/// Replays the signed-in account's queued About us answers (spec §3.14),
/// for OnboardingSyncService's flush on launch, resume and sign-in.
final aboutUsOutboxFlushProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    final outbox = ref.read(aboutUsOutboxProvider);
    if (outbox == null) return;
    await outbox.flush(ref.read(coupleProfileServiceProvider));
  },
);

/// What a save did (spec §3.8 Errors): saved, or kept on this phone to
/// replay when back online.
enum AboutUsSaveOutcome { saved, queued }

/// One About us target's answers (spec §5.3 `coupleProfileProvider`,
/// `coupleProfileDraftProvider`): fetched on open; the shared profile also
/// refetches on every together signal (either phone's edit, a reminder
/// change). A queued offline answer is shown on top until it is sent.
class CoupleProfileNotifier
    extends AutoDisposeFamilyAsyncNotifier<CoupleProfile, AboutUsTarget> {
  @override
  Future<CoupleProfile> build(AboutUsTarget target) async {
    final id = target.relationshipId;
    if (id != null) {
      ref.listen(togetherChangeSignalProvider(id), (previous, _) {
        // The first event is the subscription itself, not a change.
        if (previous == null || previous.isLoading) return;
        unawaited(_refetch());
      });
    }
    return _load(target);
  }

  Future<CoupleProfile> _load(AboutUsTarget target) async {
    final outbox = ref.read(aboutUsOutboxProvider);
    final service = ref.read(coupleProfileServiceProvider);
    // Something owed for this target: send it first, so the answer read
    // back is the latest (the last write wins, attributed now).
    if (outbox?.pending(target) != null) {
      await outbox!.flush(service);
    }
    final profile = await service.fetch(target);
    final owed = outbox?.pending(target);
    return owed == null ? profile : profile.applying(owed);
  }

  Future<void> _refetch() async {
    try {
      final profile = await _load(arg);
      state = AsyncData(profile);
    } catch (error) {
      debugPrint('[about-us] refetch failed: ${error.runtimeType}');
    }
  }

  /// Saves one answer. Offline: queued on this phone and shown at once;
  /// a refusal is rethrown for the screen to put in words.
  Future<AboutUsSaveOutcome> save(AboutUsPatch patch) async {
    final service = ref.read(coupleProfileServiceProvider);
    try {
      final saved = await service.update(arg, patch);
      state = AsyncData(saved);
      return AboutUsSaveOutcome.saved;
    } on AboutUsOffline {
      final outbox = ref.read(aboutUsOutboxProvider);
      if (outbox == null) rethrow;
      await outbox.enqueue(arg, patch);
      final current = state.valueOrNull;
      if (current != null) state = AsyncData(current.applying(patch));
      return AboutUsSaveOutcome.queued;
    }
  }
}

final coupleProfileProvider = AsyncNotifierProvider.autoDispose
    .family<CoupleProfileNotifier, CoupleProfile, AboutUsTarget>(
      CoupleProfileNotifier.new,
    );

/// The draft before linking (spec §5.3): the same notifier, the draft
/// target.
final coupleProfileDraftProvider = coupleProfileProvider(
  const AboutUsTarget.draft(),
);

/// AU2's suggested-date chips (spec §3.8, review I-12): none from Spec 1.
/// Spec 2 W9 overrides this from get_dating_link_origin ("The day you
/// matched: {date}"); a suggestion is never pre-filled.
final aboutUsDateSuggestionsProvider = Provider.autoDispose
    .family<List<AboutUsDateSuggestion>, String>(
      (ref, relationshipId) => const [],
    );

/// One AU2 chip: its words and the date it fills in when tapped.
@immutable
class AboutUsDateSuggestion {
  const AboutUsDateSuggestion({required this.label, required this.since});

  final String label;
  final TogetherSince since;
}
```

- [ ] **Step 7: The date formats, the replay on sync, the sign-out wipe**

In `lib/core/utils/date_formatter.dart` (P-16):

Edit 1 of 1. Replace exactly:

```dart
  }

  static String toTime(DateTime dateTime) {
    final time = DateFormat('hh:mm a').format(dateTime);
```

with:

```dart
  }

  /// Month and year, e.g. "October 2024" (Spec 1 W5: About us's
  /// "Together since" when only the month is known).
  static String toMonthYear(DateTime dateTime) {
    return DateFormat('MMMM y').format(dateTime);
  }

  /// The month's name alone, e.g. "October" (Spec 1 W5: About us's month
  /// pickers).
  static String toMonth(DateTime dateTime) {
    return DateFormat('MMMM').format(dateTime);
  }

  /// The year alone, e.g. "2024" (Spec 1 W5: a year-only date, a
  /// ceremony's year).
  static String toYear(DateTime dateTime) {
    return DateFormat('y').format(dateTime);
  }

  static String toTime(DateTime dateTime) {
    final time = DateFormat('hh:mm a').format(dateTime);
```

In `lib/features/onboarding/data/onboarding_sync_service.dart` (P-17):

Edit 1 of 2. Replace exactly:

```dart
    HomeStateService? homeStateService,
    Future<void> Function()? onSignUpNotEligible,
  }) : _submissionService = submissionService ?? OnboardingSubmissionService(),
       _accountService = accountService,
       _homeStateService = homeStateService,
       _onSignUpNotEligible = onSignUpNotEligible ?? _blockAndSignOut;

  final OnboardingSubmissionService _submissionService;
  final AccountService? _accountService;
  final HomeStateService? _homeStateService;
  final Future<void> Function() _onSignUpNotEligible;

  /// Flushes [store]'s pending submission, if any. Silent no-op when there is
```

with:

```dart
    HomeStateService? homeStateService,
    Future<void> Function()? onSignUpNotEligible,
    Future<void> Function()? flushAboutUs,
  }) : _submissionService = submissionService ?? OnboardingSubmissionService(),
       _accountService = accountService,
       _homeStateService = homeStateService,
       _onSignUpNotEligible = onSignUpNotEligible ?? _blockAndSignOut,
       _flushAboutUs = flushAboutUs;

  final OnboardingSubmissionService _submissionService;
  final AccountService? _accountService;
  final HomeStateService? _homeStateService;
  final Future<void> Function() _onSignUpNotEligible;

  /// Spec 1 W5 (§3.14): About us answers given offline.
  final Future<void> Function()? _flushAboutUs;

  /// Flushes [store]'s pending submission, if any. Silent no-op when there is
```

Edit 2 of 2. Replace exactly:

```dart
    if (store.pendingSignUp != null) return;
    await _flushPath(store, onPathSynced);

    final pending = store.pendingSubmission;
```

with:

```dart
    if (store.pendingSignUp != null) return;
    await _flushPath(store, onPathSynced);
    // Spec 1 W5: then About us answers queued offline (each its own
    // replay; a failure keeps them for the next launch).
    try {
      await _flushAboutUs?.call();
    } catch (error) {
      debugPrint('[onboarding] about us replay failed: ${error.runtimeType}');
    }

    final pending = store.pendingSubmission;
```

In `lib/home/home_screen.dart` (the `_syncService` initializer and one import; the latch is not touched):

Edit 1 of 2. Replace exactly:

```dart
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_sync_service.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
```

with:

```dart
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/couple_profile/presentation/couple_profile_providers.dart';
import 'package:attune/features/onboarding/data/onboarding_sync_service.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
```

Edit 2 of 2. Replace exactly:

```dart
  late final _syncService = OnboardingSyncService(
    homeStateService: ref.read(homeStateServiceProvider),
  );
  // B3 fix round: the shared seam, so tests can script it.
```

with:

```dart
  late final _syncService = OnboardingSyncService(
    homeStateService: ref.read(homeStateServiceProvider),
    // Spec 1 W5 (§3.14): About us answers queued offline.
    flushAboutUs: ref.read(aboutUsOutboxFlushProvider),
  );
  // B3 fix round: the shared seam, so tests can script it.
```

In `lib/app/device_wipes.dart` (§5.8):

Edit 1 of 2. Replace exactly:

```dart
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/core/platform/install_referrer_keys.dart';
import 'package:attune/features/onboarding/data/ask2_progress_store.dart';
import 'package:attune/features/relationships/data/invite_device_store.dart';
```

with:

```dart
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/core/platform/install_referrer_keys.dart';
import 'package:attune/features/couple_profile/data/about_us_outbox.dart';
import 'package:attune/features/onboarding/data/ask2_progress_store.dart';
import 'package:attune/features/relationships/data/invite_device_store.dart';
```

Edit 2 of 2. Replace exactly:

```dart
    run: () => removePrefsKeys((key) => key == kInstallReferrerCodeKey),
  ),
];
```

with:

```dart
    run: () => removePrefsKeys((key) => key == kInstallReferrerCodeKey),
  ),
  // W5 (§3.8 About us, §3.14): answers queued offline, at sign-out, for
  // every account on the phone (the shared-phone rule: nobody's answers
  // reach the next account).
  DeviceWipeEntry(
    id: 'spec1.about_us_outbox',
    moments: const {WipeMoment.signOut},
    keys: const {'attune.flow.<uid>.about_us_outbox'},
    run: () => removePrefsKeys(AboutUsOutbox.isOutboxKey),
  ),
];
```

- [ ] **Step 8: Run the tests**

```bash
flutter test --no-pub test/features/couple_profile/w5/couple_profile_data_test.dart test/features/couple_profile/w5/about_us_sync_test.dart test/architecture/couple_profile_never_typed_test.dart test/features/onboarding/flow_flags_test.dart test/home/ test/app/device_wipes_test.dart test/core/device/ test/core/utils/date_formatter_test.dart test/features/onboarding/onboarding_pending_sync_test.dart 2>&1 | tr '\r' '\n' | grep -E 'Some tests failed|All tests passed' | tail -1
awk '/if \(isAuthenticated && !_gateData.isComplete\) \{/,/_redirectingToOnboarding = false;/' lib/home/home_screen.dart | diff .superpowers/sdd/2026-11-02-spec1-w5/latch-before.txt - && echo "latch unchanged"
flutter analyze --no-pub lib/features/couple_profile lib/core/flags lib/features/onboarding/presentation/providers/flow_flags.dart lib/core/utils/date_formatter.dart lib/features/onboarding/data/onboarding_sync_service.dart lib/home/home_screen.dart lib/app/device_wipes.dart test/features/couple_profile test/helpers test/architecture 2>&1 | grep -E '^\s*(error|warning) ' | head
```

Expected: `All tests passed!` (the `[device-wipe] spec1.dating_lock: FlutterError` line is the registry logging the Dating lock's secure-store plugin, which the data test doesn't fake; it is expected), `latch unchanged`, no analyzer line.

- [ ] **Step 9: Mutation checks (each must turn a test red)**

```bash
D=.superpowers/sdd/2026-11-02-spec1-w5
cp lib/app/device_wipes.dart $D/device_wipes.orig
python3 -I - <<'EOF'
import pathlib
p = pathlib.Path('lib/app/device_wipes.dart'); s = p.read_text()
a = "    moments: const {WipeMoment.signOut},\n    keys: const {'attune.flow.<uid>.about_us_outbox'},\n"
assert s.count(a) == 1
p.write_text(s.replace(a, "    moments: const {WipeMoment.signOut, WipeMoment.quickExit},\n    keys: const {'attune.flow.<uid>.about_us_outbox'},\n"))
EOF
flutter test --no-pub test/features/couple_profile/w5/couple_profile_data_test.dart 2>&1 | tr '\r' '\n' | grep -E 'Some tests failed|All tests passed' | tail -1
cp $D/device_wipes.orig lib/app/device_wipes.dart && rm $D/device_wipes.orig
cp lib/features/onboarding/presentation/providers/flow_flags.dart $D/flow_flags.orig
python3 -I - <<'EOF'
import pathlib
p = pathlib.Path('lib/features/onboarding/presentation/providers/flow_flags.dart'); s = p.read_text()
a = "final coupleProfileEnabledProvider = Provider<bool>((ref) {\n  if (!ref.watch(flowCouplesV2Provider)) return false;\n"
assert s.count(a) == 1
p.write_text(s.replace(a, "final coupleProfileEnabledProvider = Provider<bool>((ref) {\n"))
EOF
flutter test --no-pub test/features/couple_profile/w5/couple_profile_data_test.dart 2>&1 | tr '\r' '\n' | grep -E 'Some tests failed|All tests passed' | tail -1
cp $D/flow_flags.orig lib/features/onboarding/presentation/providers/flow_flags.dart && rm $D/flow_flags.orig
cp lib/features/together/presentation/together_providers.dart $D/together_providers.orig
printf '\n// A label from CoupleProfile would go here.\n' >> lib/features/together/presentation/together_providers.dart
flutter test --no-pub test/architecture/couple_profile_never_typed_test.dart 2>&1 | tr '\r' '\n' | grep -E 'Some tests failed|All tests passed' | tail -1
cp $D/together_providers.orig lib/features/together/presentation/together_providers.dart && rm $D/together_providers.orig
git diff --stat -- lib/app/device_wipes.dart lib/features/onboarding/presentation/providers/flow_flags.dart lib/features/together/presentation/together_providers.dart | tail -1
```

Expected: `Some tests failed.` three times (`wiped at sign-out for every account, never on quick exit`; `couple_profile is effective only with flow_couples_v2`; `the About us model is read only inside lib/features/couple_profile`), then the diff stat shows only this task's own edits to `device_wipes.dart` and `flow_flags.dart` (`together_providers.dart` is back as it was).

### Task 4: The copy and AU1-AU6, one question per screen (§2.1-§2.3, §3.8 AU1-AU6, validation, errors, §3.14, P-3, P-14, P-19, P-20)

**Files:**
- Modify: `lib/i10n/app_en.arb` (+ `lib/i10n/generated/*` by `flutter gen-l10n`)
- Create: `lib/features/couple_profile/presentation/about_us_copy.dart`
- Create: `lib/features/couple_profile/presentation/widgets/about_us_choice.dart`
- Create: `lib/features/couple_profile/presentation/screens/about_us_question_flow.dart`
- Create: `test/features/couple_profile/w5/about_us_flow_test.dart` (+ `goldens/about_us_au{1,2,3,5,6}.{scale1.0,scale1.3,scale2.0,rtl}.png`)

**Interfaces:**
- Consumes: Task 3's model, `AboutUsTarget`, `AboutUsRefused`, `coupleProfileProvider`, `aboutUsDateSuggestionsProvider`, `MyDateFormat.toMonth|toMonthYear|toYear`; W2's flow widgets; `SharedAxisStep`; `kSelectionDuration`, `reduceMotionOf`, `flowAccent`.
- Produces: `enum AboutUsQuestion { stage, together, married, living, children, anniversary }`; `aboutUsSequence(CoupleStage?) → List<AboutUsQuestion>`; `AboutUsQuestionFlow({required AboutUsTarget target, required VoidCallback onDone, AboutUsQuestion? only, String? partnerName, DateTime Function()? now})`; `AboutUsChoice({label, helper, selected, onTap})`; in `about_us_copy.dart`: `stageText`, `livingText`, `childrenChoiceText`, `childrenText`, `bandText`, `ceremonyLabelText`, `ceremonyText`, `ceremonyAnniversaryText`, `sinceText`, `anniversaryText`, `changedByText(loc, FieldChange, DateTime now)`, `refusalText(loc, AboutUsRefusal)`; the `aboutUs_*` keys below.

- [ ] **Step 1: The copy (the three en dashes are written as JSON escapes by the script)**

```bash
mkdir -p .superpowers/sdd/2026-11-02-spec1-w5
python3 -I - <<'EOF'
import pathlib
text = r'''  "aboutUs_title": "About us",
  "aboutUs_step": "{step} of {total}",
  "@aboutUs_step": {"placeholders": {"step": {"type": "int"}, "total": {"type": "int"}}},
  "aboutUs_stepSemantics": "Question {step} of {total}",
  "@aboutUs_stepSemantics": {"placeholders": {"step": {"type": "int"}, "total": {"type": "int"}}},
  "aboutUs_skip": "Skip",
  "aboutUs_done": "Done",
  "aboutUs_save": "Save",
  "aboutUs_moreAbout": "More about this",
  "aboutUs_moreAboutBody": "Either of you can change these. It's never used to score or type you.",
  "aboutUs_moreAboutDraft": "Before {name} joins, your answers are a draft only you can see. When {name} joins, they become your shared About us.",
  "@aboutUs_moreAboutDraft": {"placeholders": {"name": {"type": "String"}}},
  "aboutUs_moreAboutDraftUnnamed": "Before your partner joins, your answers are a draft only you can see. When they join, they become your shared About us.",
  "aboutUs_stageQuestion": "How would you describe where you two are?",
  "aboutUs_stageDating": "Dating",
  "aboutUs_stageEngaged": "Engaged",
  "aboutUs_stageMarried": "Married",
  "aboutUs_stageOther": "Something else",
  "aboutUs_stageEngagedHelper": "Planning to marry, including after the knocking and before the wedding.",
  "aboutUs_stageMarriedHelper": "Any kind of marriage: customary, religious or civil.",
  "aboutUs_stageWordsLabel": "In your own words",
  "aboutUs_stageWhy": "So what Attune suggests fits you two. Either of you can change this. It's never used to score or type you.",
  "aboutUs_sinceQuestion": "When did you two get together?",
  "aboutUs_sinceHelper": "Use whichever date feels right to you both.",
  "aboutUs_sinceWhy": "So we can remember your anniversary with you, if you'd like.",
  "aboutUs_monthLabel": "Month",
  "aboutUs_yearLabel": "Year",
  "aboutUs_dayLabel": "Day",
  "aboutUs_monthOptional": "Month (optional)",
  "aboutUs_dayOptional": "Day (optional)",
  "aboutUs_notSure": "Not sure",
  "aboutUs_sinceAddDay": "Add the day",
  "aboutUs_sinceNoMonth": "Not sure of the month",
  "aboutUs_sinceSuggestions": "Suggested dates",
  "aboutUs_errorFuture": "That date is in the future.",
  "aboutUs_errorNoSuchDate": "Check the day and month.",
  "aboutUs_errorNeedsYear": "Choose a year.",
  "aboutUs_marryQuestion": "What year did you marry?",
  "aboutUs_ceremonyN": "Ceremony {n}",
  "@aboutUs_ceremonyN": {"placeholders": {"n": {"type": "int"}}},
  "aboutUs_ceremonyLabelGroup": "What kind of ceremony? (optional)",
  "aboutUs_labelCustomary": "Customary",
  "aboutUs_labelChurch": "Church",
  "aboutUs_labelMosque": "Mosque",
  "aboutUs_labelCivil": "Civil",
  "aboutUs_labelOther": "Other",
  "aboutUs_addCeremony": "Had more than one ceremony? Add another",
  "aboutUs_removeCeremony": "Remove this ceremony",
  "aboutUs_livingQuestion": "Where do you two live?",
  "aboutUs_livingTogether": "Together",
  "aboutUs_livingApartNearby": "Apart, nearby",
  "aboutUs_livingLongDistance": "Long distance",
  "aboutUs_livingWhy": "So plans, maps and reminders fit how you live.",
  "aboutUs_childrenQuestion": "Are there children in your life together?",
  "aboutUs_childrenNo": "No",
  "aboutUs_childrenYes": "Yes",
  "aboutUs_childrenExpecting": "We're expecting",
  "aboutUs_childrenPreferNot": "Prefer not to say",
  "aboutUs_childrenAges": "Their ages (optional)",
  "aboutUs_bandUnder2": "Under 2",
  "aboutUs_band2to5": "2@@ENDASH@@5",
  "aboutUs_band6to12": "6@@ENDASH@@12",
  "aboutUs_band13to17": "13@@ENDASH@@17",
  "aboutUs_band18plus": "18+",
  "aboutUs_childrenWhy": "So ideas and reminders suit your family.",
  "aboutUs_anniversaryQuestion": "Remember your anniversary?",
  "aboutUs_anniversaryNo": "No, thanks",
  "aboutUs_anniversaryTogether": "The day you got together",
  "aboutUs_anniversaryCeremony": "{label} ceremony, {year}",
  "@aboutUs_anniversaryCeremony": {"placeholders": {"label": {"type": "String"}, "year": {"type": "String"}}},
  "aboutUs_anniversaryCeremonyPlain": "Ceremony, {year}",
  "@aboutUs_anniversaryCeremonyPlain": {"placeholders": {"year": {"type": "String"}}},
  "aboutUs_anniversaryWhatDay": "What day was it?",
  "aboutUs_rowSince": "Together since",
  "aboutUs_rowStage": "Where you are",
  "aboutUs_rowCeremonies": "Ceremonies",
  "aboutUs_rowLiving": "Where you live",
  "aboutUs_rowChildren": "Children",
  "aboutUs_rowAnniversary": "Anniversary",
  "aboutUs_notAnswered": "Not answered yet",
  "aboutUs_childrenYesBands": "Yes ({bands})",
  "@aboutUs_childrenYesBands": {"placeholders": {"bands": {"type": "String"}}},
  "aboutUs_anniversaryOff": "Off",
  "aboutUs_ceremonyLine": "{label}, {year}",
  "@aboutUs_ceremonyLine": {"placeholders": {"label": {"type": "String"}, "year": {"type": "String"}}},
  "aboutUs_changedBy": "Changed by {name}",
  "@aboutUs_changedBy": {"placeholders": {"name": {"type": "String"}}},
  "aboutUs_changedByYou": "Changed by you",
  "aboutUs_changedByPartner": "Changed by your partner",
  "aboutUs_footer": "Either of you can change these. It's never used to score or type you.",
  "aboutUs_readOnlyUntil": "You can read this until {date}.",
  "@aboutUs_readOnlyUntil": {"placeholders": {"date": {"type": "String"}}},
  "aboutUs_pendingSync": "Saved on this phone. It will be shared when you're back online.",
  "aboutUs_loadFailed": "We couldn't load About us. Check your connection and try again.",
  "aboutUs_answerQuestions": "Answer a few questions",
  "aboutUs_rowEditHint": "Change",
  "aboutUs_errorAnniversaryNeedsDay": "Your anniversary reminder needs the full date. Add the day, or turn the reminder off first.",
  "aboutUs_errorReadOnly": "About us can't be changed right now.",
  "aboutUs_cardTitle": "About us",
  "aboutUs_cardBody": "A few easy questions about you two. Skip any of them. {name} sees your answers when they join.",
  "@aboutUs_cardBody": {"placeholders": {"name": {"type": "String"}}},
  "aboutUs_cardBodyUnnamed": "A few easy questions about you two. Skip any of them. Your partner sees your answers when they join.",
  "aboutUs_settingsSubtitle": "When you got together, where you live and more",
  "aboutUs_reminderFollows": "This reminder follows About us",
  "aboutUs_reminderChange": "Change in About us"'''
text = text.replace('@@ENDASH@@', chr(92) + 'u2013')
pathlib.Path('.superpowers/sdd/2026-11-02-spec1-w5/arb_w5.txt').write_text(text + '\n')
EOF
grep -cP '[^\x00-\x7F]' .superpowers/sdd/2026-11-02-spec1-w5/arb_w5.txt
grep -c 'u2013' .superpowers/sdd/2026-11-02-spec1-w5/arb_w5.txt
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py .superpowers/sdd/2026-11-02-spec1-w5/arb_w5.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package > /dev/null 2>&1; echo "gen exit=$?"
grep -c 'aboutUs_' lib/i10n/generated/app_localizations_en.dart
```

Expected: `0`, `3`, `added 94 keys`, `gen exit=0`, `94`.

- [ ] **Step 2: Write the failing test**

Create `test/features/couple_profile/w5/about_us_flow_test.dart` with exactly:

```dart
// Spec 1 W5 (§3.8 AU1-AU6, §2.2, §2.3, §3.14): one question per screen,
// every one skippable, "2 of 5" (AU3 only when Married), each answer saved
// as it is given, no future dates, the anniversary's missing day asked
// for, refusals in the app's words, offline answers kept on this phone;
// goldens at 1.0, 1.3, 2.0 and right to left; the three guidelines.
import 'dart:async';

import 'package:attune/features/couple_profile/data/about_us_outbox.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/domain/couple_profile.dart';
import 'package:attune/features/couple_profile/presentation/screens/about_us_question_flow.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    show togetherChangeSignalProvider;
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_couple_profile.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';

const _uid = 'u-about';
const _rel = 'rel-about';
final _today = DateTime(2026, 11, 2, 10);

List<Override> _overrides(FakeCoupleProfileServer server) => [
  coupleProfileRpcProvider.overrideWithValue(server.rpc),
  homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
  togetherChangeSignalProvider.overrideWith((ref, id) => const Stream.empty()),
];

Widget _flow(
  AboutUsTarget target, {
  AboutUsQuestion? only,
  VoidCallback? onDone,
  String? partnerName,
}) => AboutUsQuestionFlow(
  target: target,
  only: only,
  partnerName: partnerName,
  now: () => _today,
  onDone: onDone ?? () {},
);

Future<void> _choose(WidgetTester tester, String fieldKey, String item) async {
  await tester.tap(find.byKey(ValueKey(fieldKey)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

Future<void> _continue(WidgetTester tester, [String label = 'Continue']) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Map<String, dynamic>? _lastPatch(FakeCoupleProfileServer server) {
  final updates = server.calls.where((c) => c.$1.startsWith('update_'));
  if (updates.isEmpty) return null;
  return Map<String, dynamic>.from(updates.last.$2!['p_patch'] as Map);
}

void main() {
  testWidgets('AU1-AU6 in order, each saved as given; AU3 only when Married', (
    tester,
  ) async {
    final server = FakeCoupleProfileServer();
    var done = false;
    await pumpFlowScreen(
      tester,
      () => _flow(const AboutUsTarget.draft(), onDone: () => done = true),
      overrides: _overrides(server),
    );
    expect(
      find.text('How would you describe where you two are?'),
      findsOneWidget,
    );
    expect(find.text('1 of 5'), findsOneWidget);
    expect(find.bySemanticsLabel('Question 1 of 5'), findsOneWidget);
    expect(
      find.text('Any kind of marriage: customary, religious or civil.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Married'));
    await tester.pumpAndSettle();
    await _continue(tester);
    expect(_lastPatch(server), {'stage': 'married', 'stage_words': null});
    expect(server.calls.last.$1, 'update_my_couple_profile_draft');

    // AU2, now "2 of 6": Married adds AU3.
    expect(find.text('When did you two get together?'), findsOneWidget);
    expect(find.text('2 of 6'), findsOneWidget);
    await _choose(tester, 'about-us-since-month', 'October');
    await _choose(tester, 'about-us-since-year', '2019');
    await _continue(tester);
    expect(_lastPatch(server), {
      'together_since': '2019-10-01',
      'together_since_precision': 'month',
    });

    // AU3, skipped: nothing saved.
    expect(find.text('What year did you marry?'), findsOneWidget);
    final before = server.calls.length;
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(server.calls.length, before, reason: 'Skip writes nothing');

    // AU4.
    expect(find.text('Where do you two live?'), findsOneWidget);
    await tester.tap(find.text('Apart, nearby'));
    await tester.pumpAndSettle();
    await _continue(tester);
    expect(_lastPatch(server), {'living': 'apart_nearby'});

    // AU5 with an age band.
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(find.text('Their ages (optional)'), findsOneWidget);
    await tester.tap(find.text('18+'));
    await tester.pumpAndSettle();
    await _continue(tester);
    expect(_lastPatch(server), {
      'children': 'yes',
      'child_age_bands': ['18plus'],
    });

    // AU6: the month is known, so only the day is asked for, in the same write.
    expect(find.text('6 of 6'), findsOneWidget);
    await tester.tap(find.text('The day you got together'));
    await tester.pumpAndSettle();
    expect(find.text('What day was it?'), findsOneWidget);
    await _choose(tester, 'about-us-anniversary-day', '14');
    await _continue(tester, 'Done');
    expect(_lastPatch(server), {
      'together_since': '2019-10-14',
      'together_since_precision': 'day',
      'anniversary_source': 'together_since',
    });
    expect(done, isTrue);
  });

  testWidgets('a future date is refused on the phone, and said', (
    tester,
  ) async {
    final server = FakeCoupleProfileServer();
    await pumpFlowScreen(
      tester,
      () => _flow(const AboutUsTarget.draft(), only: AboutUsQuestion.together),
      overrides: _overrides(server),
    );
    expect(find.text('Skip'), findsNothing, reason: 'one question: Save');
    expect(
      find.textContaining(RegExp(r'^\d+ of \d+$')),
      findsNothing,
      reason: 'no step dots',
    );
    await _choose(tester, 'about-us-since-month', 'December');
    await _choose(tester, 'about-us-since-year', '2026');
    await _continue(tester, 'Save');
    expect(find.text('That date is in the future.'), findsOneWidget);
    expect(server.count('update_my_couple_profile_draft'), 0);
  });

  testWidgets('a refusal is the app\'s words; the question stays', (
    tester,
  ) async {
    final server =
        FakeCoupleProfileServer()
          ..failUpdates = FakeCoupleProfileServer.refusal(
            'couple_profile:anniversary_needs_day',
          );
    await pumpFlowScreen(
      tester,
      () =>
          _flow(const AboutUsTarget.shared(_rel), only: AboutUsQuestion.living),
      overrides: _overrides(server),
    );
    await tester.tap(find.text('Together'));
    await tester.pumpAndSettle();
    await _continue(tester, 'Save');
    expect(
      find.text(
        'Your anniversary reminder needs the full date. Add the day, or turn the reminder off first.',
      ),
      findsOneWidget,
    );
    expect(find.text('Where do you two live?'), findsOneWidget);
  });

  testWidgets('offline: kept on this phone for this account, and it moves on', (
    tester,
  ) async {
    final server =
        FakeCoupleProfileServer()..failUpdates = TimeoutException('offline');
    var done = false;
    final harness = await pumpFlowScreen(
      tester,
      () => _flow(
        const AboutUsTarget.shared(_rel),
        only: AboutUsQuestion.living,
        onDone: () => done = true,
      ),
      overrides: _overrides(server),
    );
    await tester.tap(find.text('Long distance'));
    await tester.pumpAndSettle();
    await _continue(tester, 'Save');
    expect(done, isTrue);
    final outbox = AboutUsOutbox(harness.prefs, userId: _uid);
    expect(outbox.pending(const AboutUsTarget.shared(_rel))!.values, {
      'living': 'long_distance',
    });
  });

  testWidgets('"More about this" says the draft is yours until they join', (
    tester,
  ) async {
    await pumpFlowScreen(
      tester,
      () => _flow(const AboutUsTarget.draft(), partnerName: 'Ama'),
      overrides: _overrides(FakeCoupleProfileServer()),
    );
    await tester.ensureVisible(find.text('More about this'));
    await tester.tap(find.text('More about this'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        "Either of you can change these. It's never used to score or type you.",
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Before Ama joins, your answers are a draft only you can see. When Ama joins, they become your shared About us.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the guidelines hold on AU1 and AU5 (chips)', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpFlowScreen(
      tester,
      () => _flow(const AboutUsTarget.draft()),
      overrides: _overrides(FakeCoupleProfileServer()),
    );
    await expectFlowGuidelines(tester);
    await pumpFlowScreen(
      tester,
      () => _flow(const AboutUsTarget.draft(), only: AboutUsQuestion.children),
      overrides: _overrides(
        FakeCoupleProfileServer(
          profiles: {'draft': aboutUsJson(draft: true, children: 'yes')},
        ),
      ),
    );
    await expectFlowGuidelines(tester);
    handle.dispose();
  });

  for (final (name, question, profile) in [
    (
      'about_us_au1',
      AboutUsQuestion.stage,
      aboutUsJson(draft: true, stage: 'other', stageWords: 'Courting'),
    ),
    (
      'about_us_au2',
      AboutUsQuestion.together,
      aboutUsJson(draft: true, togetherSince: '2019-10-14', precision: 'day'),
    ),
    (
      'about_us_au3',
      AboutUsQuestion.married,
      aboutUsJson(
        draft: true,
        stage: 'married',
        ceremonies: [
          {'year': 1999, 'label': 'customary'},
          {'year': 2004, 'month': 8, 'day': 14, 'label': 'church'},
        ],
      ),
    ),
    (
      'about_us_au5',
      AboutUsQuestion.children,
      aboutUsJson(draft: true, children: 'yes', bands: ['13to17', '18plus']),
    ),
    (
      'about_us_au6',
      AboutUsQuestion.anniversary,
      aboutUsJson(
        draft: true,
        stage: 'married',
        togetherSince: '2019-10-01',
        precision: 'month',
        ceremonies: [
          {'year': 1999, 'label': 'customary'},
        ],
      ),
    ),
  ]) {
    testWidgets('goldens: $name', (tester) async {
      await expectFlowGoldens(
        tester,
        name,
        () => _flow(const AboutUsTarget.draft(), only: question),
        overrides: _overrides(
          FakeCoupleProfileServer(profiles: {'draft': profile}),
        ),
      );
    });
  }

  test('the sequence: AU3 only for Married', () {
    expect(aboutUsSequence(null).length, 5);
    expect(aboutUsSequence(null), isNot(contains(AboutUsQuestion.married)));
    expect(aboutUsSequence(CoupleStage.married).length, 6);
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

```bash
flutter test --no-pub test/features/couple_profile/w5/about_us_flow_test.dart 2>&1 | tr '\r' '\n' | grep -E "Error: |Some tests failed" | head -3
```

Expected: a compile error naming `package:attune/features/couple_profile/presentation/screens/about_us_question_flow.dart`, then `Some tests failed.`

- [ ] **Step 4: The words for every answer**

Create `lib/features/couple_profile/presentation/about_us_copy.dart` with exactly:

```dart
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/domain/couple_profile.dart';
import 'package:attune/i10n/generated/app_localizations.dart';

/// About us's words for every answer (Spec 1 §3.8), one place for the
/// question flow and the About us screen. Dates only through MyDateFormat.

String stageText(AppLocalizations loc, CoupleStage stage, {String? words}) =>
    switch (stage) {
      CoupleStage.dating => loc.aboutUs_stageDating,
      CoupleStage.engaged => loc.aboutUs_stageEngaged,
      CoupleStage.married => loc.aboutUs_stageMarried,
      CoupleStage.other =>
        (words == null || words.trim().isEmpty)
            ? loc.aboutUs_stageOther
            : words.trim(),
    };

String livingText(AppLocalizations loc, Living living) => switch (living) {
  Living.together => loc.aboutUs_livingTogether,
  Living.apartNearby => loc.aboutUs_livingApartNearby,
  Living.longDistance => loc.aboutUs_livingLongDistance,
};

String childrenChoiceText(AppLocalizations loc, Children children) =>
    switch (children) {
      Children.none => loc.aboutUs_childrenNo,
      Children.yes => loc.aboutUs_childrenYes,
      Children.expecting => loc.aboutUs_childrenExpecting,
      Children.preferNotToSay => loc.aboutUs_childrenPreferNot,
    };

String bandText(AppLocalizations loc, ChildAgeBand band) => switch (band) {
  ChildAgeBand.under2 => loc.aboutUs_bandUnder2,
  ChildAgeBand.twoToFive => loc.aboutUs_band2to5,
  ChildAgeBand.sixToTwelve => loc.aboutUs_band6to12,
  ChildAgeBand.thirteenToSeventeen => loc.aboutUs_band13to17,
  ChildAgeBand.eighteenPlus => loc.aboutUs_band18plus,
};

/// "Yes (13-17, 18+)", "Yes", "No", "We're expecting", "Prefer not to say".
String childrenText(
  AppLocalizations loc,
  Children children,
  List<ChildAgeBand> bands,
) {
  if (children == Children.yes && bands.isNotEmpty) {
    return loc.aboutUs_childrenYesBands(
      [for (final band in bands) bandText(loc, band)].join(', '),
    );
  }
  return childrenChoiceText(loc, children);
}

String ceremonyLabelText(AppLocalizations loc, CeremonyLabel label) =>
    switch (label) {
      CeremonyLabel.customary => loc.aboutUs_labelCustomary,
      CeremonyLabel.church => loc.aboutUs_labelChurch,
      CeremonyLabel.mosque => loc.aboutUs_labelMosque,
      CeremonyLabel.civil => loc.aboutUs_labelCivil,
      CeremonyLabel.other => loc.aboutUs_labelOther,
    };

/// One ceremony on the About us screen: "Customary, 1999", or the year.
String ceremonyText(AppLocalizations loc, Ceremony ceremony) {
  final year = MyDateFormat.toYear(DateTime(ceremony.year));
  final label = ceremony.label;
  return label == null
      ? year
      : loc.aboutUs_ceremonyLine(ceremonyLabelText(loc, label), year);
}

/// AU6's option for a ceremony: "Customary ceremony, 1999".
String ceremonyAnniversaryText(AppLocalizations loc, Ceremony ceremony) {
  final year = MyDateFormat.toYear(DateTime(ceremony.year));
  final label = ceremony.label;
  return label == null
      ? loc.aboutUs_anniversaryCeremonyPlain(year)
      : loc.aboutUs_anniversaryCeremony(ceremonyLabelText(loc, label), year);
}

/// "Together since": the date as precisely as it was given ("October
/// 2024"), never as time elapsed (§3.8: never an elapsed counter).
String sinceText(TogetherSince since) => switch (since.precision) {
  DatePrecision.day => MyDateFormat.toDate(since.date),
  DatePrecision.month => MyDateFormat.toMonthYear(since.date),
  DatePrecision.year => MyDateFormat.toYear(since.date),
};

String anniversaryText(AppLocalizations loc, CoupleProfile profile) =>
    switch (profile.anniversarySource) {
      AnniversarySource.off => loc.aboutUs_anniversaryOff,
      AnniversarySource.togetherSince => loc.aboutUs_anniversaryTogether,
      AnniversarySource.ceremony1 =>
        profile.ceremonies.isEmpty
            ? loc.aboutUs_anniversaryOff
            : ceremonyAnniversaryText(loc, profile.ceremonies[0]),
      AnniversarySource.ceremony2 =>
        profile.ceremonies.length < 2
            ? loc.aboutUs_anniversaryOff
            : ceremonyAnniversaryText(loc, profile.ceremonies[1]),
    };

/// "Changed by Yaw - Tue, 12 Nov" (D2: MyDateFormat.join, never a middle dot): the
/// short date this year, the full one otherwise.
String changedByText(AppLocalizations loc, FieldChange change, DateTime now) {
  final who =
      change.byMe
          ? loc.aboutUs_changedByYou
          : change.byFirstName == null
          ? loc.aboutUs_changedByPartner
          : loc.aboutUs_changedBy(change.byFirstName!);
  final when =
      change.at.year == now.year
          ? MyDateFormat.toDateShort(change.at)
          : MyDateFormat.toDate(change.at);
  return MyDateFormat.join([who, when]);
}

/// A refused write in the app's words (§3.8 Errors): the specific rule when
/// the screen can fix it, else "We couldn't save that. Try again."
String refusalText(
  AppLocalizations loc,
  AboutUsRefusal reason,
) => switch (reason) {
  AboutUsRefusal.futureDate => loc.aboutUs_errorFuture,
  AboutUsRefusal.anniversaryNeedsDay => loc.aboutUs_errorAnniversaryNeedsDay,
  AboutUsRefusal.readOnly => loc.aboutUs_errorReadOnly,
  _ => loc.flow_saveFailed,
};
```

- [ ] **Step 5: The answer card**

Create `lib/features/couple_profile/presentation/widgets/about_us_choice.dart` with exactly:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One answer to an About us question, as a radio card (Spec 1 §2.2 150 ms
/// selection, §2.3: 48 dp, read as one item with its helper line, the
/// radio state announced).
class AboutUsChoice extends StatelessWidget {
  const AboutUsChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.helper,
  });

  final String label;
  final String? helper;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = flowAccent(context);
    final duration =
        reduceMotionOf(context) ? Duration.zero : kSelectionDuration;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Semantics(
        container: true,
        button: true,
        inMutuallyExclusiveGroup: true,
        checked: selected,
        label: [label, if (helper != null) helper!].join('. '),
        child: ExcludeSemantics(
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () {
                if (!selected) HapticFeedback.selectionClick();
                onTap();
              },
              borderRadius: BorderRadiusTokens.lgAll,
              child: AnimatedContainer(
                duration: duration,
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.smMd,
                ),
                decoration: BoxDecoration(
                  color: selected ? accent.withValues(alpha: 0.08) : null,
                  borderRadius: BorderRadiusTokens.lgAll,
                  border: Border.all(
                    color: selected ? accent : scheme.outlineVariant,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (helper != null) ...[
                            const SizedBox(height: Spacing.xs),
                            Text(
                              helper!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected ? accent : scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: AU1-AU6**

Create `lib/features/couple_profile/presentation/screens/about_us_question_flow.dart` with exactly:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/motion/shared_axis_step.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/domain/couple_profile.dart';
import 'package:attune/features/couple_profile/presentation/about_us_copy.dart';
import 'package:attune/features/couple_profile/presentation/couple_profile_providers.dart';
import 'package:attune/features/couple_profile/presentation/widgets/about_us_choice.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The six About us questions (Spec 1 §3.8 AU1-AU6), in the spec's order.
enum AboutUsQuestion { stage, together, married, living, children, anniversary }

/// The questions to ask: AU3 only when Married.
List<AboutUsQuestion> aboutUsSequence(CoupleStage? stage) => [
  AboutUsQuestion.stage,
  AboutUsQuestion.together,
  if (stage == CoupleStage.married) AboutUsQuestion.married,
  AboutUsQuestion.living,
  AboutUsQuestion.children,
  AboutUsQuestion.anniversary,
];

/// AU1-AU6, one question per screen (Spec 1 §3.8): every one skippable
/// ("Skip", bottom left), step dots ("2 of 5"), a "why" line and "More about
/// this" on each; each answer saved as it is given (offline: queued on this
/// phone, §3.14). With [only], just that question (an edit from the About
/// us screen, or Together's "Add your anniversary"), saved, then [onDone].
class AboutUsQuestionFlow extends ConsumerStatefulWidget {
  const AboutUsQuestionFlow({
    super.key,
    required this.target,
    required this.onDone,
    this.only,
    this.partnerName,
    this.now,
  });

  final AboutUsTarget target;
  final VoidCallback onDone;
  final AboutUsQuestion? only;

  /// Today, for "no future dates" and the year lists (tests pin it).
  final DateTime Function()? now;

  /// The partner's first name, for the draft's "More about this".
  final String? partnerName;

  @override
  ConsumerState<AboutUsQuestionFlow> createState() =>
      _AboutUsQuestionFlowState();
}

class _AboutUsQuestionFlowState extends ConsumerState<AboutUsQuestionFlow> {
  int _index = 0;
  bool _forward = true;
  bool _busy = false;
  String? _error;
  int _errorCount = 0;

  List<AboutUsQuestion> _sequence(CoupleProfile profile) =>
      widget.only != null ? [widget.only!] : aboutUsSequence(profile.stage);

  void _next(CoupleProfile profile) {
    final sequence = _sequence(profile);
    if (_index + 1 >= sequence.length) {
      widget.onDone();
      return;
    }
    setState(() {
      _forward = true;
      _index++;
      _error = null;
    });
  }

  void _back() {
    if (_index == 0) {
      widget.onDone();
      return;
    }
    setState(() {
      _forward = false;
      _index--;
      _error = null;
    });
  }

  Future<void> _submit(AboutUsPatch? patch) async {
    if (_busy) return;
    if (patch == null) {
      final profile =
          ref.read(coupleProfileProvider(widget.target)).valueOrNull;
      if (profile != null) _next(profile);
      return;
    }
    final loc = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      await ref.read(coupleProfileProvider(widget.target).notifier).save(patch);
    } on AboutUsRefused catch (refused) {
      error = refusalText(loc, refused.reason);
    } catch (_) {
      error = loc.flow_saveFailed;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error != null) _errorCount++;
    });
    if (error != null) {
      SemanticsService.announce(error, Directionality.of(context));
      return;
    }
    final profile = ref.read(coupleProfileProvider(widget.target)).valueOrNull;
    if (profile != null) _next(profile);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final async = ref.watch(coupleProfileProvider(widget.target));
    final profile = async.valueOrNull;
    if (profile == null) {
      return FlowFrame(
        title: loc.aboutUs_title,
        onBack: widget.onDone,
        body:
            async.hasError
                ? FlowErrorLine(text: loc.aboutUs_loadFailed, liveRegion: true)
                : LinearProgressIndicator(semanticsLabel: loc.aboutUs_title),
        actions: [
          if (async.hasError)
            FlowPrimaryButton(
              label: loc.flow_tryAgain,
              onPressed:
                  () => ref.invalidate(coupleProfileProvider(widget.target)),
            ),
        ],
      );
    }
    final sequence = _sequence(profile);
    final index = _index.clamp(0, sequence.length - 1);
    final question = sequence[index];
    final step = _StepContext(
      profile: profile,
      stepText: widget.only != null ? null : (index + 1, sequence.length),
      isLast: index == sequence.length - 1,
      single: widget.only != null,
      busy: _busy,
      error: _error,
      errorCount: _errorCount,
      draftPartnerName:
          widget.target.isDraft ? (widget.partnerName ?? '') : null,
      suggestions:
          widget.target.relationshipId == null
              ? const []
              : ref.watch(
                aboutUsDateSuggestionsProvider(widget.target.relationshipId!),
              ),
      onSubmit: _submit,
      onSkip: () => _next(profile),
      onBack: _back,
      today: (widget.now ?? DateTime.now)(),
    );
    return SharedAxisStep(
      stepKey: question,
      forward: _forward,
      child: switch (question) {
        AboutUsQuestion.stage => _StageStep(step: step),
        AboutUsQuestion.together => _TogetherStep(step: step),
        AboutUsQuestion.married => _MarriedStep(step: step),
        AboutUsQuestion.living => _LivingStep(step: step),
        AboutUsQuestion.children => _ChildrenStep(step: step),
        AboutUsQuestion.anniversary => _AnniversaryStep(step: step),
      },
    );
  }
}

/// What every step gets from the flow.
class _StepContext {
  const _StepContext({
    required this.profile,
    required this.stepText,
    required this.isLast,
    required this.single,
    required this.busy,
    required this.error,
    required this.errorCount,
    required this.draftPartnerName,
    required this.suggestions,
    required this.onSubmit,
    required this.onSkip,
    required this.onBack,
    required this.today,
  });

  final CoupleProfile profile;

  /// (step, total) for "2 of 5"; null for a single question.
  final (int, int)? stepText;
  final bool isLast;
  final bool single;
  final bool busy;
  final String? error;
  final int errorCount;

  /// Non-null for a draft: the partner's first name, '' when unknown.
  final String? draftPartnerName;
  final List<AboutUsDateSuggestion> suggestions;
  final Future<void> Function(AboutUsPatch? patch) onSubmit;
  final VoidCallback onSkip;
  final VoidCallback onBack;

  /// Today (the flow's clock).
  final DateTime today;
}

/// One question's screen: the question as the title, the step dots, the
/// answers, the "why" line, "More about this", the error; Continue (Done on
/// the last, Save for a single question), and Skip at the bottom left.
class _StepFrame extends StatelessWidget {
  const _StepFrame({
    required this.step,
    required this.title,
    required this.children,
    required this.onContinue,
    this.hint,
    this.why,
    this.localError,
  });

  final _StepContext step;
  final String title;
  final String? hint;
  final String? why;
  final List<Widget> children;

  /// Null while nothing can be saved yet.
  final VoidCallback? onContinue;

  /// A rule this screen checked itself (a future date, a missing year).
  final String? localError;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final error = localError ?? step.error;
    final counter = step.stepText;
    return FlowFrame(
      title: title,
      hint: hint,
      onBack: step.onBack,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (counter != null) ...[
            Semantics(
              label: loc.aboutUs_stepSemantics(counter.$1, counter.$2),
              child: ExcludeSemantics(
                child: Text(
                  loc.aboutUs_step(counter.$1, counter.$2),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
          ],
          ...children,
          if (error != null) ...[
            const SizedBox(height: Spacing.sm),
            FlowErrorLine(
              key: ValueKey('about-us-error-${step.errorCount}-$error'),
              text: error,
              liveRegion: true,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
          if (why != null) ...[
            const SizedBox(height: Spacing.md),
            Text(
              why!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: Spacing.xs),
          FlowTextLink(
            label: loc.aboutUs_moreAbout,
            alignment: AlignmentDirectional.centerStart,
            onPressed: () => _showMoreAbout(context, step.draftPartnerName),
          ),
        ],
      ),
      actions: [
        FlowPrimaryButton(
          label:
              step.single
                  ? loc.aboutUs_save
                  : step.isLast
                  ? loc.aboutUs_done
                  : loc.flow_continue,
          busy: step.busy,
          onPressed: onContinue,
        ),
        if (!step.single)
          FlowTextLink(
            label: loc.aboutUs_skip,
            alignment: AlignmentDirectional.centerStart,
            onPressed: step.busy ? () {} : step.onSkip,
          ),
      ],
    );
  }
}

Future<void> _showMoreAbout(BuildContext context, String? draftPartnerName) {
  final loc = AppLocalizations.of(context)!;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) {
      final theme = Theme.of(sheet);
      return AllowLargeText(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              0,
              Spacing.lg,
              Spacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    loc.aboutUs_moreAbout,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Text(
                  loc.aboutUs_moreAboutBody,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (draftPartnerName != null) ...[
                  const SizedBox(height: Spacing.sm),
                  Text(
                    draftPartnerName.isEmpty
                        ? loc.aboutUs_moreAboutDraftUnnamed
                        : loc.aboutUs_moreAboutDraft(draftPartnerName),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
                const SizedBox(height: Spacing.lg),
                FlowSecondaryButton(
                  label: loc.flow_close,
                  onPressed: () => Navigator.of(sheet).pop(),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// A labelled dropdown, full width, that grows with the text size.
class _PartDropdown<T> extends StatelessWidget {
  const _PartDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<(T?, String)> items;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final (item, text) in items)
            DropdownMenuItem<T>(value: item, child: Text(text)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

List<(int?, String)> _months({String? none}) => [
  if (none != null) (null, none),
  for (var m = 1; m <= 12; m++) (m, MyDateFormat.toMonth(DateTime(2000, m))),
];

List<(int?, String)> _days({String? none}) => [
  if (none != null) (null, none),
  for (var d = 1; d <= 31; d++) (d, '$d'),
];

List<(int?, String)> _years(DateTime today) => [
  for (var y = today.year; y >= 1900; y--)
    (y, MyDateFormat.toYear(DateTime(y))),
];

/// A real day of that month (no 30 February).
bool _validDay(int year, int month, int day) {
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day;
}

// ---------------------------------------------------------------- AU1

class _StageStep extends StatefulWidget {
  const _StageStep({required this.step});

  final _StepContext step;

  @override
  State<_StageStep> createState() => _StageStepState();
}

class _StageStepState extends State<_StageStep> {
  late CoupleStage? _stage = widget.step.profile.stage;
  late final _words = TextEditingController(
    text: widget.step.profile.stageWords ?? '',
  );

  @override
  void dispose() {
    _words.dispose();
    super.dispose();
  }

  AboutUsPatch? _patch() {
    final words = _stage == CoupleStage.other ? _words.text.trim() : null;
    final before = widget.step.profile;
    final wordsOrNull = words == null || words.isEmpty ? null : words;
    if (_stage == before.stage && wordsOrNull == before.stageWords) return null;
    return AboutUsPatch.stage(_stage, words: wordsOrNull);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return _StepFrame(
      step: widget.step,
      title: loc.aboutUs_stageQuestion,
      why: loc.aboutUs_stageWhy,
      onContinue: _stage == null ? null : () => widget.step.onSubmit(_patch()),
      children: [
        for (final (stage, helper) in [
          (CoupleStage.dating, null),
          (CoupleStage.engaged, loc.aboutUs_stageEngagedHelper),
          (CoupleStage.married, loc.aboutUs_stageMarriedHelper),
          (CoupleStage.other, null),
        ])
          AboutUsChoice(
            label: stageText(loc, stage),
            helper: helper,
            selected: _stage == stage,
            onTap: () => setState(() => _stage = stage),
          ),
        if (_stage == CoupleStage.other)
          FlowTextField(
            controller: _words,
            label: loc.aboutUs_stageWordsLabel,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: [LengthLimitingTextInputFormatter(40)],
            textInputAction: TextInputAction.done,
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- AU2

class _TogetherStep extends StatefulWidget {
  const _TogetherStep({required this.step});

  final _StepContext step;

  @override
  State<_TogetherStep> createState() => _TogetherStepState();
}

class _TogetherStepState extends State<_TogetherStep> {
  int? _year;
  int? _month;
  int? _day;
  bool _withDay = false;
  bool _yearOnly = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    final since = widget.step.profile.togetherSince;
    if (since != null) _fill(since);
  }

  void _fill(TogetherSince since) {
    _year = since.date.year;
    _yearOnly = since.precision == DatePrecision.year;
    _month = _yearOnly ? null : since.date.month;
    _withDay = since.precision == DatePrecision.day;
    _day = _withDay ? since.date.day : null;
  }

  void _continue() {
    final loc = AppLocalizations.of(context)!;
    final year = _year;
    if (year == null) {
      setState(() => _localError = loc.aboutUs_errorNeedsYear);
      return;
    }
    final TogetherSince since;
    if (_yearOnly) {
      since = TogetherSince(DateTime(year), DatePrecision.year);
    } else if (_month == null) {
      since = TogetherSince(DateTime(year), DatePrecision.year);
    } else if (_withDay && _day != null) {
      if (!_validDay(year, _month!, _day!)) {
        setState(() => _localError = loc.aboutUs_errorNoSuchDate);
        return;
      }
      since = TogetherSince(DateTime(year, _month!, _day!), DatePrecision.day);
    } else {
      since = TogetherSince(DateTime(year, _month!), DatePrecision.month);
    }
    if (isFutureCivilDate(since.date, widget.step.today)) {
      setState(() => _localError = loc.aboutUs_errorFuture);
      SemanticsService.announce(
        loc.aboutUs_errorFuture,
        Directionality.of(context),
      );
      return;
    }
    setState(() => _localError = null);
    widget.step.onSubmit(
      since == widget.step.profile.togetherSince
          ? null
          : AboutUsPatch.togetherSince(since),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final today = widget.step.today;
    return _StepFrame(
      step: widget.step,
      title: loc.aboutUs_sinceQuestion,
      hint: loc.aboutUs_sinceHelper,
      why: loc.aboutUs_sinceWhy,
      localError: _localError,
      onContinue: _year == null ? null : _continue,
      children: [
        if (widget.step.suggestions.isNotEmpty) ...[
          Semantics(
            container: true,
            label: loc.aboutUs_sinceSuggestions,
            explicitChildNodes: true,
            child: Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                for (final suggestion in widget.step.suggestions)
                  ActionChip(
                    label: Text(suggestion.label),
                    onPressed: () => setState(() => _fill(suggestion.since)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.md),
        ],
        if (!_yearOnly)
          _PartDropdown<int>(
            key: const ValueKey('about-us-since-month'),
            label: loc.aboutUs_monthLabel,
            value: _month,
            items: _months(),
            onChanged: (m) => setState(() => _month = m),
          ),
        _PartDropdown<int>(
          key: const ValueKey('about-us-since-year'),
          label: loc.aboutUs_yearLabel,
          value: _year,
          items: _years(today),
          onChanged: (y) => setState(() => _year = y),
        ),
        if (!_yearOnly && _withDay)
          _PartDropdown<int>(
            key: const ValueKey('about-us-since-day'),
            label: loc.aboutUs_dayLabel,
            value: _day,
            items: _days(),
            onChanged: (d) => setState(() => _day = d),
          ),
        if (!_yearOnly && !_withDay)
          FlowTextLink(
            label: loc.aboutUs_sinceAddDay,
            alignment: AlignmentDirectional.centerStart,
            onPressed: () => setState(() => _withDay = true),
          ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _yearOnly,
          title: Text(loc.aboutUs_sinceNoMonth),
          onChanged:
              (on) => setState(() {
                _yearOnly = on ?? false;
                if (_yearOnly) {
                  _month = null;
                  _day = null;
                  _withDay = false;
                }
              }),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- AU3

class _CeremonyDraft {
  _CeremonyDraft([Ceremony? from])
    : year = from?.year,
      month = from?.month,
      day = from?.day,
      label = from?.label;

  int? year;
  int? month;
  int? day;
  CeremonyLabel? label;
}

class _MarriedStep extends StatefulWidget {
  const _MarriedStep({required this.step});

  final _StepContext step;

  @override
  State<_MarriedStep> createState() => _MarriedStepState();
}

class _MarriedStepState extends State<_MarriedStep> {
  late final List<_CeremonyDraft> _drafts = [
    for (final c in widget.step.profile.ceremonies) _CeremonyDraft(c),
    if (widget.step.profile.ceremonies.isEmpty) _CeremonyDraft(),
  ];
  String? _localError;

  void _continue() {
    final loc = AppLocalizations.of(context)!;
    final today = widget.step.today;
    final ceremonies = <Ceremony>[];
    for (final d in _drafts) {
      if (d.year == null) {
        setState(() => _localError = loc.aboutUs_errorNeedsYear);
        return;
      }
      final day = d.month == null ? null : d.day;
      if (d.month != null &&
          day != null &&
          !_validDay(d.year!, d.month!, day)) {
        setState(() => _localError = loc.aboutUs_errorNoSuchDate);
        return;
      }
      final date = DateTime(d.year!, d.month ?? 1, day ?? 1);
      if (isFutureCivilDate(date, today)) {
        setState(() => _localError = loc.aboutUs_errorFuture);
        return;
      }
      ceremonies.add(
        Ceremony(year: d.year!, month: d.month, day: day, label: d.label),
      );
    }
    setState(() => _localError = null);
    final before = widget.step.profile.ceremonies;
    final same =
        before.length == ceremonies.length &&
        [
          for (var i = 0; i < before.length; i++) before[i] == ceremonies[i],
        ].every((x) => x);
    widget.step.onSubmit(same ? null : AboutUsPatch.ceremonies(ceremonies));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final today = widget.step.today;
    return _StepFrame(
      step: widget.step,
      title: loc.aboutUs_marryQuestion,
      localError: _localError,
      onContinue: _drafts.every((d) => d.year != null) ? _continue : null,
      children: [
        for (var i = 0; i < _drafts.length; i++) ...[
          if (_drafts.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: Semantics(
                header: true,
                child: Text(
                  loc.aboutUs_ceremonyN(i + 1),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          _PartDropdown<int>(
            key: ValueKey('about-us-ceremony-$i-year'),
            label: loc.aboutUs_yearLabel,
            value: _drafts[i].year,
            items: _years(today),
            onChanged: (y) => setState(() => _drafts[i].year = y),
          ),
          _PartDropdown<int>(
            key: ValueKey('about-us-ceremony-$i-month'),
            label: loc.aboutUs_monthOptional,
            value: _drafts[i].month,
            items: _months(none: loc.aboutUs_notSure),
            onChanged:
                (m) => setState(() {
                  _drafts[i].month = m;
                  if (m == null) _drafts[i].day = null;
                }),
          ),
          if (_drafts[i].month != null)
            _PartDropdown<int>(
              key: ValueKey('about-us-ceremony-$i-day'),
              label: loc.aboutUs_dayOptional,
              value: _drafts[i].day,
              items: _days(none: loc.aboutUs_notSure),
              onChanged: (d) => setState(() => _drafts[i].day = d),
            ),
          Semantics(
            container: true,
            label: loc.aboutUs_ceremonyLabelGroup,
            explicitChildNodes: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Text(
                    loc.aboutUs_ceremonyLabelGroup,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: [
                    for (final label in CeremonyLabel.values)
                      ChoiceChip(
                        label: Text(ceremonyLabelText(loc, label)),
                        selected: _drafts[i].label == label,
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        onSelected:
                            (on) => setState(
                              () => _drafts[i].label = on ? label : null,
                            ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (i == 1)
            FlowTextLink(
              label: loc.aboutUs_removeCeremony,
              alignment: AlignmentDirectional.centerStart,
              onPressed: () => setState(() => _drafts.removeAt(1)),
            ),
          const SizedBox(height: Spacing.md),
        ],
        if (_drafts.length < 2)
          FlowTextLink(
            label: loc.aboutUs_addCeremony,
            alignment: AlignmentDirectional.centerStart,
            onPressed: () => setState(() => _drafts.add(_CeremonyDraft())),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- AU4

class _LivingStep extends StatefulWidget {
  const _LivingStep({required this.step});

  final _StepContext step;

  @override
  State<_LivingStep> createState() => _LivingStepState();
}

class _LivingStepState extends State<_LivingStep> {
  late Living? _living = widget.step.profile.living;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return _StepFrame(
      step: widget.step,
      title: loc.aboutUs_livingQuestion,
      why: loc.aboutUs_livingWhy,
      onContinue:
          _living == null
              ? null
              : () => widget.step.onSubmit(
                _living == widget.step.profile.living
                    ? null
                    : AboutUsPatch.living(_living),
              ),
      children: [
        for (final living in Living.values)
          AboutUsChoice(
            label: livingText(loc, living),
            selected: _living == living,
            onTap: () => setState(() => _living = living),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- AU5

class _ChildrenStep extends StatefulWidget {
  const _ChildrenStep({required this.step});

  final _StepContext step;

  @override
  State<_ChildrenStep> createState() => _ChildrenStepState();
}

class _ChildrenStepState extends State<_ChildrenStep> {
  late Children? _children = widget.step.profile.children;
  late final Set<ChildAgeBand> _bands = {...widget.step.profile.childAgeBands};

  AboutUsPatch? _patch() {
    final bands = [
      for (final band in ChildAgeBand.values)
        if (_children == Children.yes && _bands.contains(band)) band,
    ];
    final before = widget.step.profile;
    if (_children == before.children &&
        listEquals(bands, before.childAgeBands)) {
      return null;
    }
    return AboutUsPatch.children(_children, bands: bands);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return _StepFrame(
      step: widget.step,
      title: loc.aboutUs_childrenQuestion,
      why: loc.aboutUs_childrenWhy,
      onContinue:
          _children == null ? null : () => widget.step.onSubmit(_patch()),
      children: [
        for (final children in Children.values)
          AboutUsChoice(
            label: childrenChoiceText(loc, children),
            selected: _children == children,
            onTap: () => setState(() => _children = children),
          ),
        if (_children == Children.yes)
          Semantics(
            container: true,
            label: loc.aboutUs_childrenAges,
            explicitChildNodes: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: Spacing.xs),
                ExcludeSemantics(
                  child: Text(
                    loc.aboutUs_childrenAges,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: [
                    for (final band in ChildAgeBand.values)
                      FilterChip(
                        label: Text(bandText(loc, band)),
                        selected: _bands.contains(band),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        onSelected:
                            (on) => setState(
                              () => on ? _bands.add(band) : _bands.remove(band),
                            ),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- AU6

class _AnniversaryStep extends StatefulWidget {
  const _AnniversaryStep({required this.step});

  final _StepContext step;

  @override
  State<_AnniversaryStep> createState() => _AnniversaryStepState();
}

class _AnniversaryStepState extends State<_AnniversaryStep> {
  late AnniversarySource? _source =
      widget.step.profile.anniversarySource == AnniversarySource.off &&
              widget.step.profile.changes[AboutUsField.anniversary] == null
          ? null
          : widget.step.profile.anniversarySource;
  int? _month;
  int? _day;
  String? _localError;

  CoupleProfile get _profile => widget.step.profile;

  /// The year and month the chosen source already has, when its day is
  /// missing (AU6 "What day was it?"); null when no day is needed.
  (int year, int? month)? get _missingDay {
    switch (_source) {
      case AnniversarySource.togetherSince:
        final since = _profile.togetherSince;
        if (since == null || since.hasDay) return null;
        return (
          since.date.year,
          since.precision == DatePrecision.month ? since.date.month : null,
        );
      case AnniversarySource.ceremony1 || AnniversarySource.ceremony2:
        final i = _source == AnniversarySource.ceremony1 ? 0 : 1;
        if (_profile.ceremonies.length <= i) return null;
        final c = _profile.ceremonies[i];
        if (c.fullDate != null) return null;
        return (c.year, c.month);
      default:
        return null;
    }
  }

  void _select(AnniversarySource source) => setState(() {
    _source = source;
    _localError = null;
    _month = _missingDay?.$2;
    _day = null;
  });

  void _continue() {
    final loc = AppLocalizations.of(context)!;
    final source = _source;
    if (source == null) return;
    final missing = _missingDay;
    if (missing == null) {
      widget.step.onSubmit(
        source == _profile.anniversarySource &&
                _profile.changes[AboutUsField.anniversary] != null
            ? null
            : AboutUsPatch.anniversary(source),
      );
      return;
    }
    final month = _month;
    final day = _day;
    if (month == null || day == null || !_validDay(missing.$1, month, day)) {
      setState(() => _localError = loc.aboutUs_errorNoSuchDate);
      return;
    }
    final date = DateTime(missing.$1, month, day);
    if (isFutureCivilDate(date, widget.step.today)) {
      setState(() => _localError = loc.aboutUs_errorFuture);
      return;
    }
    setState(() => _localError = null);
    if (source == AnniversarySource.togetherSince) {
      widget.step.onSubmit(
        AboutUsPatch.anniversary(
          source,
          completedSince: TogetherSince(date, DatePrecision.day),
        ),
      );
      return;
    }
    final i = source == AnniversarySource.ceremony1 ? 0 : 1;
    final ceremonies = [..._profile.ceremonies];
    final c = ceremonies[i];
    ceremonies[i] = Ceremony(
      year: c.year,
      month: month,
      day: day,
      label: c.label,
    );
    widget.step.onSubmit(
      AboutUsPatch.anniversary(source, completedCeremonies: ceremonies),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final missing = _missingDay;
    return _StepFrame(
      step: widget.step,
      title: loc.aboutUs_anniversaryQuestion,
      localError: _localError,
      onContinue: _source == null ? null : _continue,
      children: [
        AboutUsChoice(
          label: loc.aboutUs_anniversaryNo,
          selected: _source == AnniversarySource.off,
          onTap: () => _select(AnniversarySource.off),
        ),
        if (_profile.togetherSince != null)
          AboutUsChoice(
            label: loc.aboutUs_anniversaryTogether,
            selected: _source == AnniversarySource.togetherSince,
            onTap: () => _select(AnniversarySource.togetherSince),
          ),
        for (var i = 0; i < _profile.ceremonies.length && i < 2; i++)
          AboutUsChoice(
            label: ceremonyAnniversaryText(loc, _profile.ceremonies[i]),
            selected:
                _source ==
                (i == 0
                    ? AnniversarySource.ceremony1
                    : AnniversarySource.ceremony2),
            onTap:
                () => _select(
                  i == 0
                      ? AnniversarySource.ceremony1
                      : AnniversarySource.ceremony2,
                ),
          ),
        if (missing != null) ...[
          const SizedBox(height: Spacing.sm),
          Semantics(
            header: true,
            child: Text(
              loc.aboutUs_anniversaryWhatDay,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          _PartDropdown<int>(
            key: const ValueKey('about-us-anniversary-month'),
            label: loc.aboutUs_monthLabel,
            value: _month,
            items: _months(),
            onChanged: (m) => setState(() => _month = m),
          ),
          _PartDropdown<int>(
            key: const ValueKey('about-us-anniversary-day'),
            label: loc.aboutUs_dayLabel,
            value: _day,
            items: _days(),
            onChanged: (d) => setState(() => _day = d),
          ),
        ],
      ],
    );
  }
}
```

- [ ] **Step 7: Make the goldens, then run the test**

```bash
flutter test --no-pub --update-goldens test/features/couple_profile/w5/about_us_flow_test.dart 2>&1 | tr '\r' '\n' | grep -E 'Some tests failed|All tests passed' | tail -1
ls test/features/couple_profile/w5/goldens/ | grep -c '^about_us_au'
flutter test --no-pub test/features/couple_profile/w5/about_us_flow_test.dart 2>&1 | tr '\r' '\n' | grep -E 'Some tests failed|All tests passed' | tail -1
flutter analyze --no-pub lib/features/couple_profile test/features/couple_profile 2>&1 | grep -E '^\s*(error|warning) ' | head
```

Expected: `All tests passed!`, `20`, `All tests passed!`, no analyzer line. Open `about_us_au1.scale2.0.png`, `about_us_au3.scale2.0.png` and `about_us_au6.rtl.png` and look: nothing clipped or overlapping at 2.0, the radio marks on the left under right-to-left, the step's actions pinned at the bottom (the test harness draws text as blocks; that is expected).

- [ ] **Step 8: Mutation checks (each must turn the test red)**

```bash
D=.superpowers/sdd/2026-11-02-spec1-w5
F=lib/features/couple_profile/presentation/screens/about_us_question_flow.dart
cp $F $D/flow.orig
python3 -I - <<'EOF'
import pathlib
p = pathlib.Path('lib/features/couple_profile/presentation/screens/about_us_question_flow.dart'); s = p.read_text()
a = "  if (stage == CoupleStage.married) AboutUsQuestion.married,\n"
assert s.count(a) == 1
p.write_text(s.replace(a, "  AboutUsQuestion.married,\n"))
EOF
flutter test --no-pub test/features/couple_profile/w5/about_us_flow_test.dart --plain-name 'AU1-AU6 in order' 2>&1 | tr '\r' '\n' | grep -E 'Some tests failed|All tests passed' | tail -1
cp $D/flow.orig $F
python3 -I - <<'EOF'
import pathlib
p = pathlib.Path('lib/features/couple_profile/presentation/screens/about_us_question_flow.dart'); s = p.read_text()
a = "    if (isFutureCivilDate(since.date, widget.step.today)) {"
assert s.count(a) == 1
p.write_text(s.replace(a, "    if (false) {"))
EOF
flutter test --no-pub test/features/couple_profile/w5/about_us_flow_test.dart --plain-name 'a future date' 2>&1 | tr '\r' '\n' | grep -E 'Some tests failed|All tests passed' | tail -1
cp $D/flow.orig $F && rm $D/flow.orig
flutter test --no-pub test/features/couple_profile/w5/about_us_flow_test.dart 2>&1 | tr '\r' '\n' | grep -E 'Some tests failed|All tests passed' | tail -1
```

Expected: `Some tests failed.` (AU3 asked when not Married: "1 of 5" is "1 of 6"), `Some tests failed.` (a December 2026 date saved on 2 November 2026), then `All tests passed!`.

### Task 5: The About us screen and every way in; the manual; the W5 gate (§3.8 About us screen, R3, §5.1, §5.2 Settings/Together/manual, §5.4, §8 W5, D2, P-4, P-6, P-13, P-15, P-18, P-21)

**Files:**
- Create: `lib/features/couple_profile/presentation/widgets/changed_by_line.dart`
- Create: `lib/features/couple_profile/presentation/screens/about_us_screen.dart`
- Create: `lib/features/couple_profile/presentation/about_us_entry.dart`
- Create: `lib/features/couple_profile/presentation/widgets/about_us_card.dart`
- Create: `lib/app/documentations/user_manual/data/about_us_docs.dart`
- Create: `test/features/couple_profile/w5/about_us_screen_test.dart`, `about_us_entry_test.dart`, `relationship_space_about_us_test.dart`, `about_us_docs_test.dart` (+ `goldens/about_us_screen.*.png`, `goldens/about_us_card.*.png`), `test/app/routing/about_us_route_test.dart`
- Modify: `lib/app/routing/app_router.dart` (the settings block only), `lib/features/settings/data/settings_data.dart`, `lib/features/settings/screens/settings_screen.dart`, `lib/features/relationships/presentation/screens/relationship_space_screen.dart`, `lib/features/together/presentation/screens/together_screen.dart`, `lib/features/reminders/presentation/screens/add_edit_reminder_screen.dart`, `lib/app/documentations/user_manual/data/manual_documentation_registry.dart`, `test/features/together/together_screen_test.dart`, `test/app/documentations/documentation_registry_flags_test.dart`

**Interfaces:**
- Consumes: Tasks 3-4 (`coupleProfileProvider`, `coupleProfileServiceProvider`, `coupleProfileEnabledProvider`, `AboutUsTarget`, `AboutUsQuestionFlow`, `AboutUsQuestion`, the copy helpers); `coupleNameProvider`; `homeAuthProvider`, `homeStateProvider`, `LinkState`; `activeRelationshipIdProvider`; `SpaceRow`; `SettingsConfig`; `InfoRowWidget`; `showReminderSheet`; `RouteNames`.
- Produces: `AboutUsScreen({required AboutUsTarget target, required VoidCallback onClose, String? partnerName, DateTime? now})`; `ChangedByLine({required FieldChange change, DateTime? now})`; `aboutUsLocation(String? relationshipId) → String`; `openAboutUsQuestion(BuildContext, AboutUsTarget, AboutUsQuestion) → Future<void>`; `AboutUsCard({String? partnerName})`; `aboutUsSetting(BuildContext, WidgetRef) → SettingsConfig?`; `showAboutUsReminderLink(BuildContext, {required String reminderId, required String relationshipId, required String reminderType, required String title}) → Future<bool>`; `RouteNames.aboutUs = '/about-us/:relationshipId'` (route name `aboutUs`); `SettingsDataSource.getSettingsSections(…, SettingsConfig? aboutUs)`; manual topic `aboutUs`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/couple_profile/w5/about_us_screen_test.dart` with exactly:

```dart
// Spec 1 W5 (§3.8 About us screen, D2, §2.3): one row per question, the
// answer in words (dates through MyDateFormat, never a count), "Changed by
// {first name or 'you'} - {date}" under each answered row, the couple's
// name as the title (else "About us"), read-only with its end date while
// paused or in the window, a row tap asks that question again; goldens and
// guidelines.
import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/presentation/screens/about_us_screen.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    show togetherChangeSignalProvider;
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_couple_profile.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';

const _rel = 'rel-screen';
final _enDash = String.fromCharCode(0x2013);
final _middleDot = String.fromCharCode(0xB7);
final _now = DateTime(2026, 11, 20, 10);

Map<String, dynamic> _answered({bool readOnly = false}) => aboutUsJson(
  readOnly: readOnly,
  readUntil: readOnly ? '2026-12-01T10:00:00Z' : null,
  togetherSince: '2024-10-01',
  precision: 'month',
  stage: 'married',
  ceremonies: [
    {'year': 1999, 'label': 'customary'},
    {'year': 2004, 'month': 8, 'day': 14},
  ],
  living: 'apart_nearby',
  children: 'yes',
  bands: ['13to17', '18plus'],
  anniversary: 'together_since',
  changes: {
    'together_since': {
      'changed_by_me': false,
      'changed_by_first_name': 'Yaw',
      'changed_at': '2026-11-12T10:00:00Z',
    },
    'stage': {'changed_by_me': true, 'changed_at': '2025-03-04T10:00:00Z'},
    'living': {'changed_by_me': false, 'changed_at': '2026-11-01T10:00:00Z'},
  },
);

List<Override> _overrides(FakeCoupleProfileServer server, {String? name}) => [
  coupleProfileRpcProvider.overrideWithValue(server.rpc),
  homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-screen'))),
  togetherChangeSignalProvider.overrideWith((ref, id) => const Stream.empty()),
  coupleNameProvider.overrideWith((ref, id) async => name),
];

Widget _screen({AboutUsTarget target = const AboutUsTarget.shared(_rel)}) =>
    AboutUsScreen(target: target, onClose: () {}, now: _now);

void main() {
  testWidgets('every answer in words, attributed, never a count', (
    tester,
  ) async {
    await pumpFlowScreen(
      tester,
      _screen,
      overrides: _overrides(
        FakeCoupleProfileServer(profiles: {_rel: _answered()}),
        name: 'The Mensahs',
      ),
      size: const Size(390, 1400),
    );
    expect(find.text('The Mensahs'), findsOneWidget, reason: 'the chat name');
    expect(find.text('October 2024'), findsOneWidget);
    expect(find.text('Married'), findsOneWidget);
    expect(find.text('Customary, 1999\n2004'), findsOneWidget);
    expect(find.text('Apart, nearby'), findsOneWidget);
    expect(find.text('Yes (13${_enDash}17, 18+)'), findsOneWidget);
    expect(find.text('The day you got together'), findsOneWidget);
    // D2: a spaced dash, the short date this year, the full one before.
    expect(find.text('Changed by Yaw - Thu, 12 Nov'), findsOneWidget);
    expect(
      find.text('Changed by you - Tuesday, March 4, 2025'),
      findsOneWidget,
    );
    expect(find.text('Changed by your partner - Sun, 1 Nov'), findsOneWidget);
    expect(find.textContaining(_middleDot), findsNothing);
    expect(
      find.textContaining(RegExp(r'\d+ (years?|months?|days?)')),
      findsNothing,
    );
    expect(
      find.text(
        "Either of you can change these. It's never used to score or type you.",
      ),
      findsOneWidget,
    );
    expect(
      find.text('You can read this until Tuesday, December 1, 2026.'),
      findsNothing,
    );
  });

  testWidgets('without a chat name the title is About us; empty rows say so', (
    tester,
  ) async {
    await pumpFlowScreen(
      tester,
      _screen,
      overrides: _overrides(FakeCoupleProfileServer()),
      size: const Size(390, 1400),
    );
    expect(find.text('About us'), findsOneWidget);
    expect(find.text('Not answered yet'), findsNWidgets(4));
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Answer a few questions'), findsOneWidget);
    expect(find.textContaining('Changed by'), findsNothing);
  });

  testWidgets('read-only: its end date, and no row opens a question', (
    tester,
  ) async {
    await pumpFlowScreen(
      tester,
      _screen,
      overrides: _overrides(
        FakeCoupleProfileServer(profiles: {_rel: _answered(readOnly: true)}),
      ),
      size: const Size(390, 1400),
    );
    expect(find.textContaining('You can read this until'), findsOneWidget);
    await tester.tap(find.text('Apart, nearby'));
    await tester.pumpAndSettle();
    expect(find.text('Where do you two live?'), findsNothing);
  });

  testWidgets('a row asks its question again, and the answer comes back', (
    tester,
  ) async {
    final server = FakeCoupleProfileServer(profiles: {_rel: _answered()});
    await pumpFlowScreen(
      tester,
      _screen,
      overrides: _overrides(server),
      size: const Size(390, 1400),
    );
    await tester.tap(find.text('Apart, nearby'));
    await tester.pumpAndSettle();
    expect(find.text('Where do you two live?'), findsOneWidget);
    await tester.tap(find.text('Long distance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Long distance'), findsOneWidget);
    expect(find.textContaining('Changed by you'), findsWidgets);
  });

  testWidgets('a failed load says so and tries again', (tester) async {
    final server =
        FakeCoupleProfileServer()
          ..failNext = FakeCoupleProfileServer.refusal('boom');
    await pumpFlowScreen(tester, _screen, overrides: _overrides(server));
    expect(
      find.text(
        "We couldn't load About us. Check your connection and try again.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Not answered yet'), findsWidgets);
  });

  testWidgets('the guidelines hold', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpFlowScreen(
      tester,
      _screen,
      overrides: _overrides(
        FakeCoupleProfileServer(profiles: {_rel: _answered()}),
      ),
    );
    await expectFlowGuidelines(tester);
    handle.dispose();
  });

  testWidgets('goldens: about_us_screen', (tester) async {
    await expectFlowGoldens(
      tester,
      'about_us_screen',
      _screen,
      overrides: _overrides(
        FakeCoupleProfileServer(profiles: {_rel: _answered()}),
        name: 'The Mensahs',
      ),
    );
  });
}
```

Create `test/features/couple_profile/w5/about_us_entry_test.dart` with exactly:

```dart
// Spec 1 W5 (§3.8, §5.2): where About us is entered, only with
// couple_profile on: R3's card (the draft, the partner named), Settings ->
// Your relationship (the shared profile after linking, the draft while an
// invite waits, nothing otherwise), and the anniversary reminder's sheet
// ("This reminder follows About us" -> AU6) for that one reminder only.
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/presentation/about_us_entry.dart';
import 'package:attune/features/couple_profile/presentation/widgets/about_us_card.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/settings/models/settings_config.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    show togetherChangeSignalProvider;
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_couple_profile.dart';
import '../../../helpers/fake_home_state.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';

const _uid = 'u-entry';

List<Override> _overrides(
  FakeCoupleProfileServer server, {
  required bool on,
}) => [
  coupleProfileEnabledProvider.overrideWithValue(on),
  coupleProfileRpcProvider.overrideWithValue(server.rpc),
  homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
  togetherChangeSignalProvider.overrideWith((ref, id) => const Stream.empty()),
];

/// Builds Settings' About us row and shows a button that taps it.
class _SettingsProbe extends ConsumerWidget {
  const _SettingsProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SettingsConfig? row = aboutUsSetting(context, ref);
    return Scaffold(
      body: Center(
        child:
            row == null
                ? const Text('no row')
                : TextButton(onPressed: row.onTap, child: Text(row.title)),
      ),
    );
  }
}

class _ReminderProbe extends StatelessWidget {
  const _ReminderProbe(this.reminderId, {this.type = 'anniversary'});

  final String reminderId;
  final String type;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Builder(
      builder:
          (context) => TextButton(
            onPressed: () async {
              final shown = await showAboutUsReminderLink(
                context,
                reminderId: reminderId,
                relationshipId: 'r1',
                reminderType: type,
                title: 'Anniversary',
              );
              if (!shown && context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('the edit form')));
              }
            },
            child: const Text('open reminder'),
          ),
    ),
  );
}

Future<void> _setLink(WidgetTester tester, String link, {String? id}) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(Scaffold).first),
  );
  await container
      .read(homeStateProvider(_uid).notifier)
      .apply(
        HomeState.fromJson(
          homeJson(path: 'relationship', link: link, relationshipId: id),
        ),
      );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'R3\'s card: only with couple_profile, the partner named, the draft',
    (tester) async {
      await pumpFlowScreen(
        tester,
        () => const Scaffold(body: AboutUsCard(partnerName: 'Ama')),
        overrides: _overrides(FakeCoupleProfileServer(), on: false),
      );
      expect(find.text('About us'), findsNothing);

      await pumpFlowScreen(
        tester,
        () => const Scaffold(body: AboutUsCard(partnerName: 'Ama')),
        overrides: _overrides(FakeCoupleProfileServer(), on: true),
      );
      expect(find.text('About us'), findsOneWidget);
      expect(
        find.text(
          'A few easy questions about you two. Skip any of them. Ama sees your answers when they join.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('About us'));
      await tester.pumpAndSettle();
      expect(find.text('at /about-us/draft'), findsOneWidget);
    },
  );

  testWidgets(
    'Settings: shared after linking, the draft while pending, else none',
    (tester) async {
      await pumpFlowScreen(
        tester,
        () => const _SettingsProbe(),
        overrides: _overrides(FakeCoupleProfileServer(), on: true),
      );
      expect(find.text('no row'), findsOneWidget, reason: 'nothing known yet');
      await _setLink(tester, 'none');
      expect(
        find.text('no row'),
        findsOneWidget,
        reason: 'never before an invite',
      );
      await _setLink(tester, 'linked', id: 'r1');
      await tester.tap(find.text('About us'));
      await tester.pumpAndSettle();
      expect(find.text('at /about-us/r1'), findsOneWidget);

      await pumpFlowScreen(
        tester,
        () => const _SettingsProbe(),
        overrides: _overrides(FakeCoupleProfileServer(), on: true),
      );
      await _setLink(tester, 'pending', id: 'r-pending');
      await tester.tap(find.text('About us'));
      await tester.pumpAndSettle();
      expect(find.text('at /about-us/draft'), findsOneWidget);

      await pumpFlowScreen(
        tester,
        () => const _SettingsProbe(),
        overrides: _overrides(FakeCoupleProfileServer(), on: false),
      );
      await _setLink(tester, 'linked', id: 'r1');
      expect(find.text('no row'), findsOneWidget, reason: 'couple_profile off');
    },
  );

  testWidgets(
    'the anniversary reminder follows About us; others open as before',
    (tester) async {
      final server = FakeCoupleProfileServer(
        profiles: {
          'r1': aboutUsJson(
            togetherSince: '2016-03-12',
            precision: 'day',
            anniversary: 'together_since',
            reminderId: 'rem-about-us',
          ),
        },
      );
      await pumpFlowScreen(
        tester,
        () => const _ReminderProbe('rem-about-us'),
        overrides: _overrides(server, on: true),
      );
      await tester.tap(find.text('open reminder'));
      await tester.pumpAndSettle();
      expect(find.text('This reminder follows About us'), findsOneWidget);
      await tester.tap(find.text('Change in About us'));
      await tester.pumpAndSettle();
      expect(find.text('Remember your anniversary?'), findsOneWidget);

      await pumpFlowScreen(
        tester,
        () => const _ReminderProbe('rem-other'),
        overrides: _overrides(server, on: true),
      );
      await tester.tap(find.text('open reminder'));
      await tester.pumpAndSettle();
      expect(find.text('the edit form'), findsOneWidget);

      final calls = server.calls.length;
      await pumpFlowScreen(
        tester,
        () => const _ReminderProbe('rem-about-us', type: 'birthday'),
        overrides: _overrides(server, on: true),
      );
      await tester.tap(find.text('open reminder'));
      await tester.pumpAndSettle();
      expect(find.text('the edit form'), findsOneWidget);
      expect(server.calls.length, calls, reason: 'a birthday asks nothing');

      await pumpFlowScreen(
        tester,
        () => const _ReminderProbe('rem-about-us'),
        overrides: _overrides(server, on: false),
      );
      await tester.tap(find.text('open reminder'));
      await tester.pumpAndSettle();
      expect(find.text('the edit form'), findsOneWidget, reason: 'flag off');
    },
  );

  testWidgets('goldens: about_us_card', (tester) async {
    await expectFlowGoldens(
      tester,
      'about_us_card',
      () => const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(16),
          child: AboutUsCard(partnerName: 'Ama'),
        ),
      ),
      overrides: _overrides(FakeCoupleProfileServer(), on: true),
    );
  });
}
```

Create `test/features/couple_profile/w5/relationship_space_about_us_test.dart` with exactly:

```dart
// Spec 1 W5 (§3.8 R3): the About us card sits in R3's pending state only
// ("never before an invite exists"), names the partner R1 typed on this
// phone, and is absent with couple_profile off.
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/relationships/presentation/relationship_lifecycle_providers.dart';
import 'package:attune/features/relationships/presentation/screens/relationship_space_screen.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/fake_invites.dart';
import '../../../helpers/fake_push_asker.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';

const _uid = 'u-r3-about';

Future<void> _pump(
  WidgetTester tester, {
  required String link,
  required bool aboutUs,
}) async {
  await tester.pumpWidget(const SizedBox());
  await pumpFlowScreen(
    tester,
    () => RelationshipSpaceScreen(
      home: snapshotOf(homeJson(path: 'relationship', link: link)),
    ),
    size: const Size(390, 2600),
    prefsValues: {'attune.flow.$_uid.partner_first_name': 'Ama'},
    overrides: [
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
      homeStateServiceProvider.overrideWithValue(
        HomeStateService(
          FakeHomeStateGateway(state: homeJson(path: 'relationship')),
        ),
      ),
      invitePartnerServiceProvider.overrideWithValue(FakeInvites()),
      relationshipLifecycleProvider.overrideWith((ref) async => null),
      pushAskerProvider.overrideWithValue(FakePushAsker()),
      flowCouplesV2Provider.overrideWithValue(true),
      coupleProfileEnabledProvider.overrideWithValue(aboutUs),
    ],
  );
}

void main() {
  const body =
      'A few easy questions about you two. Skip any of them. Ama sees your answers when they join.';

  testWidgets('pending: the card, the partner named', (tester) async {
    await _pump(tester, link: 'pending', aboutUs: true);
    expect(find.text(body), findsOneWidget);
  });

  testWidgets('never before an invite exists, and never with the flag off', (
    tester,
  ) async {
    await _pump(tester, link: 'none', aboutUs: true);
    expect(find.text(body), findsNothing);
    await _pump(tester, link: 'pending', aboutUs: false);
    expect(find.text(body), findsNothing);
  });
}
```

Create `test/features/couple_profile/w5/about_us_docs_test.dart` with exactly:

```dart
// Spec 1 W5 (§5.2 user manual): the About us topic is listed only while
// flow_signin_v2, flow_paths_v2, flow_couples_v2 and couple_profile are on.
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the About us topic needs all four flags', () {
    DocumentationRegistry.initialize();
    bool listed(Set<String> on) =>
        DocumentationRegistry.visibleModules(on).any((m) => m.id == 'aboutUs');
    const all = {
      'flow_signin_v2',
      'flow_paths_v2',
      'flow_couples_v2',
      'couple_profile',
    };
    expect(DocumentationRegistry.getById('aboutUs'), isNotNull);
    expect(listed(all), isTrue);
    for (final missing in all) {
      expect(listed({...all}..remove(missing)), isFalse, reason: missing);
    }
  });
}
```

Create `test/app/routing/about_us_route_test.dart` with exactly:

```dart
// Spec 1 W5 (§5.4, P-13): createAppRouter's /about-us/:relationshipId is
// for a signed-in account with couple_profile on; `draft` is the draft;
// off (or signed out) a typed or deep /about-us never shows About us.
import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/auth/sign_up/presentation/sign_up_flags.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/presentation/about_us_entry.dart';
import 'package:attune/features/couple_profile/presentation/screens/about_us_screen.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    show togetherChangeSignalProvider;
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_couple_profile.dart';
import '../../helpers/fake_home_state.dart';
import '../../helpers/flow_harness.dart';
import '../../helpers/home_harness.dart';

const _uid = 'u-route-about';

Future<GoRouter> _pump(
  WidgetTester tester, {
  required bool signedIn,
  required bool aboutUs,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final auth = FakeHomeAuth(signedIn ? testUser(_uid) : null);
  addTearDown(auth.changes.close);
  final routing = RoutingNotifier(
    flowV2: true,
    currentUserId: () => signedIn ? _uid : null,
  );
  final router = createAppRouter(routing);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        routingNotifierProvider.overrideWith((ref) => routing),
        publicAppConfigGatewayProvider.overrideWithValue(
          FakePublicConfigGateway(),
        ),
        homeAuthProvider.overrideWithValue(auth),
        // As join_invite_route_test.dart: Home stays a plain shell.
        homeStateServiceProvider.overrideWithValue(
          HomeStateService(
            FakeHomeStateGateway(state: homeJson(path: null, needs: ['path'])),
          ),
        ),
        signInFlowV2Provider.overrideWithValue(true),
        flowPathsV2Provider.overrideWithValue(true),
        flowCouplesV2Provider.overrideWithValue(true),
        coupleProfileEnabledProvider.overrideWithValue(aboutUs),
        coupleProfileRpcProvider.overrideWithValue(
          FakeCoupleProfileServer().rpc,
        ),
        coupleNameProvider.overrideWith((ref, id) async => null),
        togetherChangeSignalProvider.overrideWith(
          (ref, id) => const Stream.empty(),
        ),
      ],
      child: ScreenUtilConfig.builder(
        builder:
            (_) => MaterialApp.router(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            ),
      ),
    ),
  );
  await tester.pump();
  return router;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

String _at(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  test('the locations', () {
    expect(aboutUsLocation('r1'), '/about-us/r1');
    expect(aboutUsLocation(null), '/about-us/draft');
    expect(RouteNames.aboutUs, '/about-us/:relationshipId');
  });

  testWidgets(
    'signed in, couple_profile on: the shared profile and the draft',
    (tester) async {
      final router = await _pump(tester, signedIn: true, aboutUs: true);
      router.go(aboutUsLocation('r1'));
      await _settle(tester);
      expect(_at(router), '/about-us/r1');
      final shared = tester.widget<AboutUsScreen>(find.byType(AboutUsScreen));
      expect(shared.target, const AboutUsTarget.shared('r1'));
      router.go(aboutUsLocation(null), extra: 'Ama');
      await _settle(tester);
      final draft = tester.widget<AboutUsScreen>(find.byType(AboutUsScreen));
      expect(draft.target, const AboutUsTarget.draft());
      expect(draft.partnerName, 'Ama');
    },
  );

  testWidgets('couple_profile off, or signed out: never About us', (
    tester,
  ) async {
    final off = await _pump(tester, signedIn: true, aboutUs: false);
    off.go(aboutUsLocation('r1'));
    await _settle(tester);
    expect(_at(off), isNot(startsWith('/about-us')));
    expect(find.byType(AboutUsScreen), findsNothing);

    await tester.pumpWidget(const SizedBox());
    final out = await _pump(tester, signedIn: false, aboutUs: true);
    out.go(aboutUsLocation('r1'));
    await _settle(tester);
    expect(_at(out), isNot(startsWith('/about-us')));
    expect(find.byType(AboutUsScreen), findsNothing);
  });
}
```

In `test/features/together/together_screen_test.dart` (About us off for every existing test; two new cases):

Edit 1 of 5. Replace exactly:

```dart
import 'package:attune/features/together/presentation/screens/together_screen.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
```

with:

```dart
import 'package:attune/features/together/presentation/screens/together_screen.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
```

Edit 2 of 5. Replace exactly:

```dart
import 'together_widget_sync_test.dart' show FakeWidgetStore;
import 'together_repository_test.dart' show FakeTogetherGateway;

Map<String, dynamic> _row(
```

with:

```dart
import 'together_widget_sync_test.dart' show FakeWidgetStore;
import 'together_repository_test.dart' show FakeTogetherGateway;
import '../../helpers/fake_couple_profile.dart';

Map<String, dynamic> _row(
```

Edit 3 of 5. Replace exactly:

```dart
  bool appreciation = false,
  List<Map<String, dynamic>> wins = const [],
}) async {
  // Never the real lock-screen channel or phone calendar in tests.
```

with:

```dart
  bool appreciation = false,
  List<Map<String, dynamic>> wins = const [],
  bool aboutUs = false,
}) async {
  // Never the real lock-screen channel or phone calendar in tests.
```

Edit 4 of 5. Replace exactly:

```dart
        appreciationEnabledProvider.overrideWith((ref) async => appreciation),
        winsEnabledProvider.overrideWith((ref) async => wins.isNotEmpty),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(home: TogetherScreen(embedded: embedded)),
      ),
    ),
```

with:

```dart
        appreciationEnabledProvider.overrideWith((ref) async => appreciation),
        winsEnabledProvider.overrideWith((ref) async => wins.isNotEmpty),
        // Spec 1 W5: About us is off unless a test turns it on.
        coupleProfileEnabledProvider.overrideWithValue(aboutUs),
        coupleProfileRpcProvider.overrideWithValue(
          FakeCoupleProfileServer().rpc,
        ),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder:
            (_, __) => MaterialApp(
              localizationsDelegates:
                  aboutUs ? AppLocalizations.localizationsDelegates : null,
              supportedLocales:
                  aboutUs
                      ? AppLocalizations.supportedLocales
                      : const [Locale('en', 'US')],
              home: TogetherScreen(embedded: embedded),
            ),
      ),
    ),
```

Edit 5 of 5. Replace exactly:

```dart
    expect(find.text('Add a birthday'), findsOneWidget);
    expect(find.text('Set up a ritual'), findsOneWidget);
  });

```

with:

```dart
    expect(find.text('Add a birthday'), findsOneWidget);
    expect(find.text('Set up a ritual'), findsOneWidget);
  });

  // Spec 1 W5 (§3.8, §5.2): with couple_profile on, "Add your anniversary"
  // is About us's AU6, and About us has its own row; off, as before.
  testWidgets('About us on: the anniversary is AU6, and About us has a row', (
    t,
  ) async {
    await _pump(t, aboutUs: true);
    expect(find.text('About us'), findsOneWidget);
    await t.tap(find.text('Add your anniversary'));
    await t.pumpAndSettle();
    expect(find.text('Remember your anniversary?'), findsOneWidget);
  });

  testWidgets('About us off: Start with is as it was', (t) async {
    await _pump(t);
    expect(find.text('About us'), findsNothing);
    await t.tap(find.text('Add your anniversary'));
    await t.pumpAndSettle();
    expect(find.text('Add reminder'), findsOneWidget);
  });

```

In `test/app/documentations/documentation_registry_flags_test.dart`:

Edit 1 of 1. Replace exactly:

```dart
          'flow_signin_v2',
          'flow_paths_v2',
        }),
      );
```

with:

```dart
          'flow_signin_v2',
          'flow_paths_v2',
          // Spec 1 W5: About us.
          'flow_couples_v2',
          'couple_profile',
        }),
      );
```

- [ ] **Step 2: Run them to verify they fail**

```bash
flutter test --no-pub test/features/couple_profile/w5/about_us_screen_test.dart test/features/couple_profile/w5/about_us_entry_test.dart test/features/couple_profile/w5/relationship_space_about_us_test.dart test/features/couple_profile/w5/about_us_docs_test.dart test/app/routing/about_us_route_test.dart test/features/together/together_screen_test.dart 2>&1 | tr '\r' '\n' | grep -E "Error: |Some tests failed" | head -5
```

Expected: compile errors naming `about_us_screen.dart`, `about_us_entry.dart` and `about_us_card.dart`, then `Some tests failed.`

- [ ] **Step 3: The "Changed by" line and the About us screen**

Create `lib/features/couple_profile/presentation/widgets/changed_by_line.dart` with exactly:

```dart
import 'package:attune/features/couple_profile/domain/couple_profile.dart';
import 'package:attune/features/couple_profile/presentation/about_us_copy.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

/// "Changed by {first name or 'you'} - {date}" under an answered About us
/// row (Spec 1 §3.8, D2). A first name from the server, never an id.
class ChangedByLine extends StatelessWidget {
  const ChangedByLine({super.key, required this.change, this.now});

  final FieldChange change;

  /// Today, for "this year or not" (tests pin it).
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Text(
      changedByText(loc, change, now ?? DateTime.now()),
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
```

Create `lib/features/couple_profile/presentation/screens/about_us_screen.dart` with exactly:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/domain/couple_profile.dart';
import 'package:attune/features/couple_profile/presentation/about_us_copy.dart';
import 'package:attune/features/couple_profile/presentation/couple_profile_providers.dart';
import 'package:attune/features/couple_profile/presentation/screens/about_us_question_flow.dart';
import 'package:attune/features/couple_profile/presentation/widgets/changed_by_line.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The About us screen (Spec 1 §3.8, `/about-us/:relationshipId`, or the
/// draft at `/about-us/draft`): one row per question, the answer, and
/// under each answered row "Changed by {first name or 'you'} - {date}".
/// Tapping a row asks that one question again. Read-only while paused or
/// in the ending window ("You can read this until {date}."). No push, no
/// feed, no history list; "Together since" is a date, never a count.
class AboutUsScreen extends ConsumerWidget {
  const AboutUsScreen({
    super.key,
    required this.target,
    required this.onClose,
    this.partnerName,
    this.now,
  });

  final AboutUsTarget target;
  final VoidCallback onClose;

  /// The partner's first name, for the draft's "More about this".
  final String? partnerName;

  /// Today (tests pin it).
  final DateTime? now;

  Future<void> _ask(
    BuildContext context,
    AboutUsQuestion? only, {
    bool all = false,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder:
          (route) => AboutUsQuestionFlow(
            target: target,
            only: all ? null : only,
            partnerName: partnerName,
            onDone: () => Navigator.of(route).pop(),
          ),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final id = target.relationshipId;
    final coupleName =
        id == null ? null : ref.watch(coupleNameProvider(id)).valueOrNull;
    final title = coupleName ?? loc.aboutUs_title;
    final async = ref.watch(coupleProfileProvider(target));
    final profile = async.valueOrNull;
    if (profile == null) {
      return FlowFrame(
        title: title,
        onBack: onClose,
        body:
            async.hasError
                ? FlowErrorLine(text: loc.aboutUs_loadFailed, liveRegion: true)
                : LinearProgressIndicator(semanticsLabel: loc.aboutUs_title),
        actions: [
          if (async.hasError)
            FlowPrimaryButton(
              label: loc.flow_tryAgain,
              onPressed: () => ref.invalidate(coupleProfileProvider(target)),
            ),
        ],
      );
    }
    final today = now ?? DateTime.now();
    final readOnly = profile.readOnly;
    final rows = <(AboutUsQuestion, AboutUsField, String, String?)>[
      (
        AboutUsQuestion.together,
        AboutUsField.togetherSince,
        loc.aboutUs_rowSince,
        profile.togetherSince == null
            ? null
            : sinceText(profile.togetherSince!),
      ),
      (
        AboutUsQuestion.stage,
        AboutUsField.stage,
        loc.aboutUs_rowStage,
        profile.stage == null
            ? null
            : stageText(loc, profile.stage!, words: profile.stageWords),
      ),
      if (profile.stage == CoupleStage.married || profile.ceremonies.isNotEmpty)
        (
          AboutUsQuestion.married,
          AboutUsField.ceremonies,
          loc.aboutUs_rowCeremonies,
          profile.ceremonies.isEmpty
              ? null
              : [
                for (final c in profile.ceremonies) ceremonyText(loc, c),
              ].join('\n'),
        ),
      (
        AboutUsQuestion.living,
        AboutUsField.living,
        loc.aboutUs_rowLiving,
        profile.living == null ? null : livingText(loc, profile.living!),
      ),
      (
        AboutUsQuestion.children,
        AboutUsField.children,
        loc.aboutUs_rowChildren,
        profile.children == null
            ? null
            : childrenText(loc, profile.children!, profile.childAgeBands),
      ),
      (
        AboutUsQuestion.anniversary,
        AboutUsField.anniversary,
        loc.aboutUs_rowAnniversary,
        anniversaryText(loc, profile),
      ),
    ];
    return FlowFrame(
      title: title,
      onBack: onClose,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (readOnly && profile.readUntil != null) ...[
            Text(
              loc.aboutUs_readOnlyUntil(
                MyDateFormat.toDate(profile.readUntil!),
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: Spacing.md),
          ],
          if (profile.pendingSync) ...[
            Text(
              loc.aboutUs_pendingSync,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.md),
          ],
          for (final (question, field, label, answer) in rows)
            _AboutUsRow(
              label: label,
              value: answer ?? loc.aboutUs_notAnswered,
              change: profile.changes[field],
              now: today,
              onTap: readOnly ? null : () => _ask(context, question),
            ),
          const SizedBox(height: Spacing.md),
          Text(
            loc.aboutUs_footer,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        if (!readOnly && profile.isEmpty)
          FlowPrimaryButton(
            label: loc.aboutUs_answerQuestions,
            onPressed: () => _ask(context, null, all: true),
          ),
      ],
    );
  }
}

class _AboutUsRow extends StatelessWidget {
  const _AboutUsRow({
    required this.label,
    required this.value,
    required this.change,
    required this.now,
    required this.onTap,
  });

  final String label;
  final String value;
  final FieldChange? change;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final changedBy = change == null ? null : changedByText(loc, change!, now);
    return Semantics(
      container: true,
      button: onTap != null,
      label: [label, value, if (changedBy != null) changedBy].join('. '),
      hint: onTap == null ? null : loc.aboutUs_rowEditHint,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          value,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        if (change != null) ...[
                          const SizedBox(height: Spacing.xs),
                          ChangedByLine(change: change!, now: now),
                        ],
                      ],
                    ),
                  ),
                  if (onTap != null)
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
```

- [ ] **Step 4: The ways in**

Create `lib/features/couple_profile/presentation/about_us_entry.dart` with exactly:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/presentation/screens/about_us_question_flow.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/relationships/data/relationship_lifecycle_service.dart';
import 'package:attune/features/settings/models/settings_config.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Where About us is entered (Spec 1 §3.8): R3's card during the wait
/// (the draft; widgets/about_us_card.dart), Together's "Start with" rows
/// and Settings -> Your relationship after linking, and the anniversary
/// reminder's sheet. Never before an invite exists. All behind
/// couple_profile (effective).

/// `/about-us/<relationship id>`, or `/about-us/draft` for the draft.
String aboutUsLocation(String? relationshipId) =>
    '/about-us/${relationshipId ?? 'draft'}';

/// One question, pushed over the current screen (an edit, or Together's
/// "Add your anniversary" as AU6).
Future<void> openAboutUsQuestion(
  BuildContext context,
  AboutUsTarget target,
  AboutUsQuestion question,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder:
        (route) => AboutUsQuestionFlow(
          target: target,
          only: question,
          onDone: () => Navigator.of(route).pop(),
        ),
  ),
);

/// Settings -> Your relationship -> "About us" (§3.8), after linking (the
/// shared space, also read-only while paused or in the ending window), or
/// the draft while an invite is pending.
SettingsConfig? aboutUsSetting(BuildContext context, WidgetRef ref) {
  if (!ref.watch(coupleProfileEnabledProvider)) return null;
  final userId = ref.watch(homeAuthProvider).currentUser?.id;
  if (userId == null) return null;
  final home = ref.watch(homeStateProvider(userId));
  final link = home.link;
  if (link != LinkState.linked &&
      link != LinkState.paused &&
      link != LinkState.endedWindow &&
      link != LinkState.pending) {
    return null;
  }
  final loc = AppLocalizations.of(context)!;
  return SettingsConfig(
    id: 'about_us',
    title: loc.aboutUs_title,
    subtitle: loc.aboutUs_settingsSubtitle,
    icon: Icons.favorite_border_rounded,
    type: SettingsItemType.navigation,
    iconColor: Colors.pink,
    order: 0,
    onTap: () async {
      if (link == LinkState.pending) {
        await context.push(aboutUsLocation(null));
        return;
      }
      final id =
          home.linkDetail.relationshipId ??
          await ref.read(activeRelationshipIdProvider.future);
      if (id != null && context.mounted) {
        await context.push(aboutUsLocation(id));
      }
    },
  );
}

/// Together's anniversary reminder follows About us (§5.2): its sheet says
/// so and offers "Change in About us" (AU6) instead of the edit form.
/// True when [reminderId] is that reminder and the sheet was shown; false
/// for any other reminder, with couple_profile off, or when About us can't
/// be read (the edit form opens, and the server's guard keeps the date).
Future<bool> showAboutUsReminderLink(
  BuildContext context, {
  required String reminderId,
  required String relationshipId,
  required String reminderType,
  required String title,
}) async {
  if (reminderType != 'anniversary') return false;
  final ProviderContainer container;
  try {
    container = ProviderScope.containerOf(context, listen: false);
  } catch (_) {
    return false;
  }
  if (!container.read(coupleProfileEnabledProvider)) return false;
  final target = AboutUsTarget.shared(relationshipId);
  try {
    final profile = await container
        .read(coupleProfileServiceProvider)
        .fetch(target);
    if (profile.anniversaryReminderId != reminderId) return false;
  } catch (_) {
    return false;
  }
  if (!context.mounted) return false;
  final loc = AppLocalizations.of(context)!;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) {
      final theme = Theme.of(sheet);
      return AllowLargeText(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              0,
              Spacing.lg,
              Spacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  loc.aboutUs_reminderFollows,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                FlowPrimaryButton(
                  label: loc.aboutUs_reminderChange,
                  onPressed: () {
                    Navigator.of(sheet).pop();
                    openAboutUsQuestion(
                      context,
                      target,
                      AboutUsQuestion.anniversary,
                    );
                  },
                ),
                const SizedBox(height: Spacing.sm),
                FlowSecondaryButton(
                  label: loc.flow_close,
                  onPressed: () => Navigator.of(sheet).pop(),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return true;
}
```

Create `lib/features/couple_profile/presentation/widgets/about_us_card.dart` (R3's card, §5.1) with exactly:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/couple_profile/presentation/about_us_entry.dart';
import 'package:attune/features/me/presentation/widgets/your_space_section.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// R3's About us card (§3.8 R3), on the pending state only: the draft.
class AboutUsCard extends ConsumerWidget {
  const AboutUsCard({super.key, this.partnerName});

  /// R1's first name for the partner (this phone only), if typed.
  final String? partnerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(coupleProfileEnabledProvider)) {
      return const SizedBox.shrink();
    }
    final loc = AppLocalizations.of(context)!;
    final name = partnerName;
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.md),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          child: SpaceRow(
            title: loc.aboutUs_cardTitle,
            subtitle:
                name == null
                    ? loc.aboutUs_cardBodyUnnamed
                    : loc.aboutUs_cardBody(name),
            icon: Icons.favorite_border_rounded,
            onTap: () => context.push(aboutUsLocation(null), extra: name),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: The route (P-13)**

In `lib/app/routing/app_router.dart` (the constant beside W3c's, the route after `howYouUseAttune`, the flag reader beside `_couplesV2`; no Games route is touched):

Edit 1 of 5. Replace exactly:

```dart
import 'package:attune/features/onboarding/presentation/screens/onboarding_gate_v2.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart'
    show flowCouplesV2Provider;
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:attune/features/opinions/data/models/opinion_model.dart';
```

with:

```dart
import 'package:attune/features/onboarding/presentation/screens/onboarding_gate_v2.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart'
    show coupleProfileEnabledProvider, flowCouplesV2Provider;
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:attune/features/opinions/data/models/opinion_model.dart';
```

Edit 2 of 5. Replace exactly:

```dart
import 'package:attune/features/settings/screens/theme_screen.dart';
import 'package:attune/features/settings/presentation/screens/how_you_use_attune_screen.dart';
import 'package:attune/home/home_location.dart';
import 'package:attune/home/home_screen.dart';
```

with:

```dart
import 'package:attune/features/settings/screens/theme_screen.dart';
import 'package:attune/features/settings/presentation/screens/how_you_use_attune_screen.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/presentation/screens/about_us_screen.dart';
import 'package:attune/home/home_location.dart';
import 'package:attune/home/home_screen.dart';
```

Edit 3 of 5. Replace exactly:

```dart
  /// Spec 1 W3c (§3.12).
  static const String howYouUseAttune = '/settings/how-you-use-attune';
  static const String signedInDevices = '/settings/signed-in-devices';
  static const String dataExport = DataExportScreen.routeName;
```

with:

```dart
  /// Spec 1 W3c (§3.12).
  static const String howYouUseAttune = '/settings/how-you-use-attune';

  /// Spec 1 W5 (§3.8, §5.4): About us; `draft` is this account's draft
  /// before linking (aboutUsLocation builds it).
  static const String aboutUs = '/about-us/:relationshipId';
  static const String signedInDevices = '/settings/signed-in-devices';
  static const String dataExport = DataExportScreen.routeName;
```

Edit 4 of 5. Replace exactly:

```dart
        builder: (context, state) => const HowYouUseAttuneScreen(),
      ),
      GoRoute(
        path: RouteNames.signedInDevices,
```

with:

```dart
        builder: (context, state) => const HowYouUseAttuneScreen(),
      ),
      // Spec 1 W5 (§3.8): About us, signed in and couple_profile on; with
      // it off (or unreadable) a typed or deep /about-us goes home.
      GoRoute(
        path: RouteNames.aboutUs,
        name: 'aboutUs',
        redirect: (context, state) {
          if (!routingNotifier.isSignedIn) return RouteNames.login;
          return _coupleProfile(context) ? null : RouteNames.home;
        },
        builder: (context, state) {
          final id = state.pathParameters['relationshipId'];
          final extra = state.extra;
          return AboutUsScreen(
            target:
                id == null || id == 'draft'
                    ? const AboutUsTarget.draft()
                    : AboutUsTarget.shared(id),
            partnerName: extra is String ? extra : null,
            onClose: () {
              final router = GoRouter.of(context);
              if (router.canPop()) {
                router.pop();
              } else {
                router.go(RouteNames.home);
              }
            },
          );
        },
      ),
      GoRoute(
        path: RouteNames.signedInDevices,
```

Edit 5 of 5. Replace exactly:

```dart
/// flow_couples_v2, effective, from the app's providers; off when they
/// can't be read (final review #6).
bool _couplesV2(BuildContext context) {
  try {
```

with:

```dart
/// flow_couples_v2, effective, from the app's providers; off when they
/// can't be read (final review #6).
/// Spec 1 W5: couple_profile, effective (an unreadable flag is off).
bool _coupleProfile(BuildContext context) {
  try {
    return ProviderScope.containerOf(
      context,
      listen: false,
    ).read(coupleProfileEnabledProvider);
  } catch (_) {
    return false;
  }
}

bool _couplesV2(BuildContext context) {
  try {
```

- [ ] **Step 6: Settings -> Your relationship -> About us (P-21)**

In `lib/features/settings/data/settings_data.dart`:

Edit 1 of 2. Replace exactly:

```dart
    SettingsConfig? journalReminder,
    SettingsConfig? howYouUse,
  }) {
    // Access localization for language prefence
```

with:

```dart
    SettingsConfig? journalReminder,
    SettingsConfig? howYouUse,
    SettingsConfig? aboutUs,
  }) {
    // Access localization for language prefence
```

Edit 2 of 2. Replace exactly:

```dart
        title: 'Your relationship',
        items: [
// Spec 3a (F1 (3)): read-only for both, nothing new shared, no
// notification; either resumes or ends within 30 days.
```

with:

```dart
        title: 'Your relationship',
        items: [
// Spec 1 W5 (§3.8): About us (built by the screen, couple_profile on).
if (aboutUs != null) aboutUs,
// Spec 3a (F1 (3)): read-only for both, nothing new shared, no
// notification; either resumes or ends within 30 days.
```

In `lib/features/settings/screens/settings_screen.dart`:

Edit 1 of 2. Replace exactly:

```dart
import 'package:attune/features/me/presentation/widgets/journal_reminder_row.dart';
import 'package:attune/features/settings/presentation/screens/how_you_use_attune_screen.dart';
import 'package:attune/features/settings/data/chat_feel_preference.dart';
import 'package:attune/features/settings/data/sound_preference.dart';
```

with:

```dart
import 'package:attune/features/me/presentation/widgets/journal_reminder_row.dart';
import 'package:attune/features/settings/presentation/screens/how_you_use_attune_screen.dart';
import 'package:attune/features/couple_profile/presentation/about_us_entry.dart';
import 'package:attune/features/settings/data/chat_feel_preference.dart';
import 'package:attune/features/settings/data/sound_preference.dart';
```

Edit 2 of 2. Replace exactly:

```dart
          currentUserId.isEmpty ? null : journalReminderSetting(context, ref),
      howYouUse: currentUserId.isEmpty ? null : howYouUseSetting(context, ref),
    );

```

with:

```dart
          currentUserId.isEmpty ? null : journalReminderSetting(context, ref),
      howYouUse: currentUserId.isEmpty ? null : howYouUseSetting(context, ref),
      aboutUs: currentUserId.isEmpty ? null : aboutUsSetting(context, ref),
    );

```

- [ ] **Step 7: R3's card, Together's rows, the reminder's sheet (P-6, P-18)**

In `lib/features/relationships/presentation/screens/relationship_space_screen.dart`:

Edit 1 of 2. Replace exactly:

```dart
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/me/presentation/widgets/journal_reminder_row.dart';
import 'package:attune/features/me/presentation/widgets/more_ways_sheet.dart';
```

with:

```dart
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/couple_profile/presentation/widgets/about_us_card.dart';
import 'package:attune/features/me/presentation/widgets/journal_reminder_row.dart';
import 'package:attune/features/me/presentation/widgets/more_ways_sheet.dart';
```

Edit 2 of 2. Replace exactly:

```dart
        const SizedBox(height: Spacing.md),
        _WhileYouWait(),
        const SizedBox(height: Spacing.sm),
        Text(
```

with:

```dart
        const SizedBox(height: Spacing.md),
        _WhileYouWait(),
        // Spec 1 W5 (§3.8 R3): About us, the draft (couple_profile on).
        AboutUsCard(partnerName: _partnerName),
        const SizedBox(height: Spacing.sm),
        Text(
```

In `lib/features/together/presentation/screens/together_screen.dart`:

Edit 1 of 4. Replace exactly:

```dart
import 'package:attune/features/reminders/presentation/screens/family_members_screen.dart';
import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
```

with:

```dart
import 'package:attune/features/reminders/presentation/screens/family_members_screen.dart';
import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/presentation/about_us_entry.dart';
import 'package:attune/features/couple_profile/presentation/screens/about_us_question_flow.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
```

Edit 2 of 4. Replace exactly:

```dart
                                    relationshipId,
                                  ),
                            ),
                          ]
```

with:

```dart
                                    relationshipId,
                                  ),
                              // Spec 1 W5 (§3.8, §5.2): with couple_profile
                              // on, the anniversary is About us's AU6, and
                              // About us has its own row.
                              aboutUs:
                                  ref.watch(coupleProfileEnabledProvider)
                                      ? AboutUsTarget.shared(relationshipId)
                                      : null,
                            ),
                          ]
```

Edit 3 of 4. Replace exactly:

```dart
/// A brand-new couple: three easy ways in.
class _EmptyTogether extends StatelessWidget {
  const _EmptyTogether({required this.onRitual});
  final VoidCallback onRitual;

  @override
```

with:

```dart
/// A brand-new couple: three easy ways in.
class _EmptyTogether extends StatelessWidget {
  const _EmptyTogether({required this.onRitual, this.aboutUs});
  final VoidCallback onRitual;

  /// Spec 1 W5: set while couple_profile is on.
  final AboutUsTarget? aboutUs;

  @override
```

Edit 4 of 4. Replace exactly:

```dart
              showAvatar: false,
              showTrailingArrow: true,
              onTap: () => showReminderSheet(context),
            ),
            InfoRowWidget(
              title: 'Add a birthday',
```

with:

```dart
              showAvatar: false,
              showTrailingArrow: true,
              onTap:
                  aboutUs == null
                      ? () => showReminderSheet(context)
                      : () => openAboutUsQuestion(
                        context,
                        aboutUs!,
                        AboutUsQuestion.anniversary,
                      ),
            ),
            if (aboutUs != null)
              InfoRowWidget(
                title: AppLocalizations.of(context)!.aboutUs_title,
                subtitle: '',
                icon: Icons.people_alt_outlined,
                showAvatar: false,
                showTrailingArrow: true,
                onTap:
                    () => context.push(
                      aboutUsLocation(aboutUs!.relationshipId),
                    ),
              ),
            InfoRowWidget(
              title: 'Add a birthday',
```

In `lib/features/reminders/presentation/screens/add_edit_reminder_screen.dart` (`showReminderSheet` is the one way every surface opens a reminder: Together, the calendar day sheet, the Timeline):

Edit 1 of 2. Replace exactly:

```dart
import 'package:attune/core/providers/run_write.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
```

with:

```dart
import 'package:attune/core/providers/run_write.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/couple_profile/presentation/about_us_entry.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
```

Edit 2 of 2. Replace exactly:

```dart
  DateTime? initialDate,
}) async {
  // The sheet closes with its confirmation; it is shown here, on the
  // screen behind, because the sheet's own messenger closes with it.
```

with:

```dart
  DateTime? initialDate,
}) async {
  // Spec 1 W5 (§5.2): the anniversary reminder About us keeps opens its
  // own sheet ("This reminder follows About us"), not this form.
  if (reminder != null &&
      await showAboutUsReminderLink(
        context,
        reminderId: reminder.id,
        relationshipId: reminder.relationshipId,
        reminderType: reminder.reminderType,
        title: reminder.title,
      )) {
    return;
  }
  if (!context.mounted) return;
  // The sheet closes with its confirmation; it is shown here, on the
  // screen behind, because the sheet's own messenger closes with it.
```

- [ ] **Step 8: The manual topic (§5.2)**

Create `lib/app/documentations/user_manual/data/about_us_docs.dart` with exactly:

```dart
// lib/app/documentations/user_manual/data/about_us_docs.dart
//
// "About us" (Spec 1 §3.8, W5). Listed only while flow_signin_v2,
// flow_paths_v2, flow_couples_v2 and couple_profile are on
// (DocumentationRegistry).

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class AboutUsDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'About us';

  @override
  String get id => 'aboutUs';

  @override
  String getSubtitle(BuildContext context) =>
      'A few shared answers about the two of you';

  @override
  IconData get icon => Icons.favorite_border_rounded;

  @override
  int get order => 3;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'about_us_what',
      title: 'What About us is',
      subtitle: 'Short questions, every one skippable',
      icon: Icons.favorite_border_rounded,
      category: 'About us',
      order: 1,
      contents: [
        ManualContent(
          id: 'about_us_questions',
          title: 'The questions',
          numberPrefix: '1',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'Where the two of you are: dating, engaged, married, or in your own words.',
            'When you got together, as a month and year, a full date, or just the year.',
            'If you are married, the year of your ceremony (up to two).',
            'Where you live, and whether there are children in your life together.',
            'Whether to remember your anniversary.',
          ],
        ),
        ManualContent(
          id: 'about_us_never_scored',
          title: '',
          content:
              'Either of you can change these. It\'s never used to score or type you.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'about_us_where',
      title: 'Where to find it',
      subtitle: 'Before and after your partner joins',
      icon: Icons.place_outlined,
      category: 'About us',
      order: 2,
      contents: [
        ManualContent(
          id: 'about_us_before',
          title: 'While your invite is waiting',
          numberPrefix: '1',
          content:
              'Your answers are a draft only you can see. When your partner joins, they become your shared About us.',
        ),
        ManualContent(
          id: 'about_us_after',
          title: 'Once you are both here',
          numberPrefix: '2',
          content:
              'In Settings, open Your relationship, then About us. Under each answer you can see who changed it last, and when.',
        ),
        ManualContent(
          id: 'about_us_anniversary',
          title: 'Your anniversary',
          numberPrefix: '3',
          content:
              'If you choose a date to remember, Together keeps one yearly reminder for it. Change or turn it off in About us.',
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) => const [
    FAQModel(
      id: 'faq_about_us_told',
      question: 'Does my partner get a notification when I change About us?',
      answer:
          'No. There is no notification and no feed. Your partner sees the change, with your name, the next time they open About us.',
      category: 'About us',
      order: 1,
    ),
  ];
}
```

In `lib/app/documentations/user_manual/data/manual_documentation_registry.dart`:

Edit 1 of 3. Replace exactly:

```dart
import 'package:attune/app/documentations/user_manual/data/hard_moment_docs.dart';
import 'package:attune/app/documentations/user_manual/data/how_you_use_attune_docs.dart';
import 'package:attune/app/documentations/user_manual/data/planning_docs.dart';
import 'package:attune/app/documentations/user_manual/data/privacy_data_docs.dart';
```

with:

```dart
import 'package:attune/app/documentations/user_manual/data/hard_moment_docs.dart';
import 'package:attune/app/documentations/user_manual/data/how_you_use_attune_docs.dart';
import 'package:attune/app/documentations/user_manual/data/about_us_docs.dart';
import 'package:attune/app/documentations/user_manual/data/planning_docs.dart';
import 'package:attune/app/documentations/user_manual/data/privacy_data_docs.dart';
```

Edit 2 of 3. Replace exactly:

```dart
    // Spec 1 W3c: the paths (flow_paths_v2 needs flow_signin_v2).
    'howYouUseAttune': ['flow_signin_v2', 'flow_paths_v2'],
  };

```

with:

```dart
    // Spec 1 W3c: the paths (flow_paths_v2 needs flow_signin_v2).
    'howYouUseAttune': ['flow_signin_v2', 'flow_paths_v2'],
    // Spec 1 W5: About us (couple_profile needs flow_couples_v2, which
    // needs flow_paths_v2, which needs flow_signin_v2).
    'aboutUs': [
      'flow_signin_v2',
      'flow_paths_v2',
      'flow_couples_v2',
      'couple_profile',
    ],
  };

```

Edit 3 of 3. Replace exactly:

```dart
      CoupleMapDocs(),
      HowYouUseAttuneDocs(),
    ]) {
      registerModule(module);
```

with:

```dart
      CoupleMapDocs(),
      HowYouUseAttuneDocs(),
      AboutUsDocs(),
    ]) {
      registerModule(module);
```

- [ ] **Step 9: Make the goldens, then run the tests**

```bash
flutter test --no-pub --update-goldens test/features/couple_profile/w5/about_us_screen_test.dart test/features/couple_profile/w5/about_us_entry_test.dart 2>&1 | tr '\r' '\n' | grep -E 'Some tests failed|All tests passed' | tail -1
ls test/features/couple_profile/w5/goldens/ | grep -cE '^about_us_(screen|card)\.'
flutter test --no-pub test/features/couple_profile/ test/architecture/ test/features/together/together_screen_test.dart test/features/relationships/ test/features/settings/ test/app/documentations/ test/app/routing/ test/features/reminders/ test/features/timeline/ 2>&1 | tr '\r' '\n' | grep -E 'Some tests failed|All tests passed' | tail -1
```

Expected: `All tests passed!`, `8`, `All tests passed!`. Open `about_us_screen.scale2.0.png` and `about_us_screen.rtl.png`: the rows, their "Changed by" lines and the footer readable, nothing clipped.

- [ ] **Step 10: Mutation checks (each must turn a test red)**

```bash
D=.superpowers/sdd/2026-11-02-spec1-w5
T=lib/features/together/presentation/screens/together_screen.dart
C=lib/features/couple_profile/presentation/about_us_copy.dart
cp $T $D/together.orig; cp $C $D/copy.orig
python3 -I - <<'EOF'
import pathlib
p = pathlib.Path('lib/features/together/presentation/screens/together_screen.dart'); s = p.read_text()
a = "              onTap:\n                  aboutUs == null\n                      ? () => showReminderSheet(context)\n"
assert s.count(a) == 1
p.write_text(s.replace(a, "              onTap:\n                  aboutUs != null\n                      ? () => showReminderSheet(context)\n"))
EOF
flutter test --no-pub test/features/together/together_screen_test.dart --plain-name 'About us on' 2>&1 | tr '\r' '\n' | grep -E 'Some tests failed|All tests passed' | tail -1
cp $D/together.orig $T
python3 -I - <<'EOF'
import pathlib
p = pathlib.Path('lib/features/couple_profile/presentation/about_us_copy.dart'); s = p.read_text()
a = "  return MyDateFormat.join([who, when]);\n"
assert s.count(a) == 1
p.write_text(s.replace(a, "  return '$who ' + String.fromCharCode(0xB7) + ' $when';\n"))
EOF
flutter test --no-pub test/features/couple_profile/w5/about_us_screen_test.dart --plain-name 'every answer in words' 2>&1 | tr '\r' '\n' | grep -E 'Some tests failed|All tests passed' | tail -1
cp $D/copy.orig $C && rm $D/together.orig $D/copy.orig
```

Expected: `Some tests failed.` (the anniversary row opened the reminder form with About us on), `Some tests failed.` (D2: a middle dot next to a date), and both files restored.

- [ ] **Step 11: The copy checks**

```bash
grep -rnP '^(?!\s*//).*[^\x00-\x7F]' lib/features/couple_profile lib/app/documentations/user_manual/data/about_us_docs.dart test/features/couple_profile | head
grep -rn "both of you" lib/features/couple_profile lib/app/documentations/user_manual/data/about_us_docs.dart | head
```

Expected: no line from either (non-ASCII only in comments; nothing says "both of you"). The device key `attune.flow.<uid>.about_us_outbox` names no Dating (D20; Task 3's data test checks it).

- [ ] **Step 12: Format the new files only, then the W5 gate**

```bash
dart format lib/features/couple_profile lib/app/documentations/user_manual/data/about_us_docs.dart test/features/couple_profile test/helpers/fake_couple_profile.dart test/architecture/couple_profile_never_typed_test.dart test/app/routing/about_us_route_test.dart
flutter test --no-pub 2>&1 | tr '\r' '\n' | grep -E 'All tests passed!|Some tests failed' | tail -1
flutter analyze --no-pub lib test 2>&1 | grep -E '^\s*error ' | sed -E 's/:[0-9]+:[0-9]+//' | sort -u | comm -13 .superpowers/sdd/2026-11-02-spec1-w5/analyze-errors-baseline.txt -
git diff --stat -- lib/features/opinions lib/features/games lib/features/auth/utility/auth_exports.dart ATTUNE_SOUL.md ATTUNE_THESIS.md supabase/sql/dev_enable_spec1_flags.sql supabase/functions lib/features/onboarding/presentation/screens/onboarding_gate.dart | tail -1
awk '/if \(isAuthenticated && !_gateData.isComplete\) \{/,/_redirectingToOnboarding = false;/' lib/home/home_screen.dart | diff .superpowers/sdd/2026-11-02-spec1-w5/latch-before.txt - && echo "latch unchanged"
flutter test --no-pub test/architecture/games_untouched_test.dart 2>&1 | tr '\r' '\n' | grep -E 'All tests passed!|Some tests failed' | tail -1
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done | grep '^FAIL' | comm -13 <(grep '^FAIL' .superpowers/sdd/2026-11-02-spec1-w5/sql-baseline.txt) -
(cd supabase/functions && deno test --allow-read accept-invite/ 2>&1 | grep -E 'passed|failed' | tail -1)
git status --short > .superpowers/sdd/2026-11-02-spec1-w5/git-status-after.txt
diff .superpowers/sdd/2026-11-02-spec1-w5/git-status-before.txt .superpowers/sdd/2026-11-02-spec1-w5/git-status-after.txt | grep '^>'
```

Expected: the format line lists only the new files (`Formatted N files (k changed)`; never a pre-existing path); `All tests passed!` (if `test/features/chat/chat_upload_progress_cancel_test.dart` or `chat_w1a_final_fixes_test.dart` fails under the full run, run that file alone: both are timing-sensitive under load); no analyzer output; no diff line; `latch unchanged`; `All tests passed!`; no new SQL FAIL; `ok | 29 passed | 0 failed`; the paths this plan touched (report the list: the four migrations, the contract, the identity contract, `scripts/local_pg_grants.sql`, `lib/i10n/*`, the new `lib/features/couple_profile/**` and test files and goldens, and the modified files in the file map). The **W5 gate** itself is not code: **the Ghanaian cultural reviewer confirms the stage options and helper text (engaged, married, ceremonies, labels)**, with the P-14 lines in the same pass; report it as outstanding.

## Owner deploy checklist (the plan never runs any of this)

1. **Order.** W1-W4 are deployed first (their checklists). Deploy both W5 migrations (and their twins) before any W5 build reaches a tester: the app calls the four About us RPCs, and the accept starts adopting drafts as soon as the second migration lands (harmless without drafts). Deploy part 1 before part 2 (`20261102110000` before `20261102110100`: the accept calls `adopt_couple_profile_drafts`). No edge function changes; `accept-invite` needs no redeploy.
2. **Server.** `supabase db push` applies `20261102110000_couple_profiles.sql`, `20261102110010_couple_profiles_grants.sql`, `20261102110100_couple_profiles_links.sql`, `20261102110110_couple_profiles_links_grants.sql`. Afterwards, in the SQL editor:
   - `select has_table_privilege('authenticated', 'public.couple_profiles', 'SELECT'), has_table_privilege('authenticated', 'public.couple_profiles', 'UPDATE'), has_table_privilege('anon', 'public.couple_profiles', 'SELECT');` → `t | f | f`
   - `select has_function_privilege('authenticated', 'public.update_couple_profile(uuid,jsonb)', 'EXECUTE'), has_function_privilege('authenticated', 'public.adopt_couple_profile_drafts(uuid,uuid,uuid)', 'EXECUTE'), has_function_privilege('service_role', 'public.sync_anniversary_reminder(uuid)', 'EXECUTE');` → `t | f | f`
   - `select tablename from pg_publication_tables where tablename like 'couple_profile%';` → no rows (About us is not in Realtime; the together signal is).
   - `select tgname from pg_trigger where tgname in ('couple_profiles_together_signal', 'reminders_guard_about_us');` → both.
   - `select has_function_privilege('service_role', 'public.accept_relationship_invite_v2(uuid,text)', 'EXECUTE'), has_function_privilege('service_role', 'public.export_bundle(uuid,uuid[])', 'EXECUTE');` → `t | t` (unchanged).
   All were checked on the scratch copy of `attune_spec3a`.
3. **Flags.** Nothing to insert: `couple_profile` exists (W1c) and is on in development (W1's dev script, unchanged). On the development project, installing a W5 build shows R3's card, Settings' row, Together's rows and the reminder sheet at once (with `flow_couples_v2` on).
4. **Device checks (development project, both platforms):**
   - Inviter, invite pending: R3 shows the About us card naming the partner typed at R1; answer AU1 Married, AU2 a month and year, AU3 two ceremonies, AU4, AU5 Yes with bands, AU6 a ceremony without a day (it asks "What day was it?"). Skip works on every question; Back returns.
   - The partner accepts the invite: both phones show the same About us (Settings -> Your relationship -> About us), each row "Changed by {first name} - {date}" on the other phone and "Changed by you - {date}" on the answerer's; the anniversary reminder appears once in Together, on the next occurrence, and both partners get it at 09:00 their own time (P-5).
   - Edit a row on one phone: the other phone's open About us updates without a refresh (the together signal), with no push.
   - Together's reminder sheet for the anniversary says "This reminder follows About us"; "Change in About us" opens AU6; a birthday reminder still opens the form.
   - W5 final fix wave (I-2, M-2): on that sheet "Reminder times and note" opens the reminder form with the date, title and type shown but fixed and no Delete; pick "1 week before", Save: both phones hear a week before. With a hand-made yearly anniversary reminder already in Together, AU6 says "You already have an anniversary reminder, so we won't add another."; turning the anniversary on adds none, and the hand-made reminder (title, date, note, memory) is unchanged; turning it off again leaves it as it was. Beside a hand-made one-off, About us adds its own as before. In airplane mode, tapping it shows the offline sheet, and "Reminder times and note" still opens it.
   - Airplane mode: answer a question; it shows with "Saved on this phone…"; back online and reopen the app: the other phone shows it, attributed to the answerer.
   - Shared phone: Kofi answers About us while his invite waits, signs out; Ama signs in on the same phone and sees an empty draft (or none), never Kofi's answers.
   - Pause the shared space: About us reads "You can read this until {date}." and no row opens; resume: editable again. End it: read-only until the window's end, then gone.
   - Switch the inviter to Dating while the invite waits (Settings -> How you use Attune): the draft is gone when they come back to Relationship. Draft answers still queued on the phone from an offline moment go with the switch, so no later replay brings them back (final review M-4).
   - Download my data: `relationship-1` has `about_us` with `"by": "me"` / `"partner"`; `personal.settings` has `birth_date`, `path`, `journal_reminder`.
   - TalkBack and VoiceOver through AU1-AU6 and the About us screen; 200% system text; right to left (Arabic system language): nothing clipped; quick exit (the triple-tap) works on the question flow, the About us screen and the "More about this" sheet.
5. **W5 gate (before `couple_profile` in production):** the Ghanaian cultural reviewer confirms AU1's stage options and helper text (Dating, Engaged with "Planning to marry, including after the knocking and before the wedding.", Married with "Any kind of marriage: customary, religious or civil.", Something else), AU3's ceremony labels (Customary, Church, Mosque, Civil, Other) and, in the same pass, the P-14 lines. Then record the evidence: `select public.record_flag_gate_evidence('couple_profile', '<review reference>');` (service role, SQL editor).
   **P-14 cultural review list (batch 5; the same pass, English source in `lib/i10n/app_en.arb`):**
   - The P-14 lines:
     - R3's card: `aboutUs_cardBody` "A few easy questions about you two. Skip any of them. {name} sees your answers after joining." and `aboutUs_cardBodyUnnamed` "... Your partner sees your answers after joining."
     - "More about this": `aboutUs_moreAboutBody` / `aboutUs_footer` "Either of you can change these. It's never used to score or type you."; `aboutUs_moreAboutDraft` "Before {name} joins, your answers are a draft only you can see. When {name} joins, your answers become your shared About us."; `aboutUs_moreAboutDraftUnnamed` (the same with "your partner").
     - `aboutUs_notAnswered` "Not answered yet", `aboutUs_answerQuestions` "Answer a few questions", `aboutUs_errorNoSuchDate` "Check the day and month.", `aboutUs_errorNeedsYear` "Choose a year.", `aboutUs_errorAnniversaryNeedsDay` "Your anniversary reminder needs the full date. Add the day, or turn the reminder off first.", `aboutUs_errorReadOnly` "About us can't be changed right now.", `aboutUs_pendingSync` "Saved on this phone. It will be shared when you're back online.", `aboutUs_loadFailed` "We couldn't load About us. Check your connection and try again." (also the reminder sheet's and the route's offline state, F-5), `aboutUs_settingsSubtitle` "When you got together, where you live and more", `aboutUs_anniversaryCeremonyPlain` "Ceremony, {year}", `aboutUs_stepSemantics` "Question {step} of {total}", `aboutUs_reminderFollows` "This reminder follows About us", `aboutUs_reminderChange` "Change in About us", and the manual topic (`about_us_docs.dart`).
   - `aboutUs_errorWordsTooLong` "Use 40 characters or fewer." (AU1's own words).
   - The three `aboutUs_reminderStop*` keys: "Your anniversary reminder will stop" / "It follows this ceremony's date. It can follow the day you got together instead." / "Turn it off". Note "It follows this ceremony's date" is generic: it is also shown when leaving Married removes every ceremony (the reviewer may want a variant).
   - The four M-2 rewrites (no "they" for the partner): `aboutUs_moreAboutDraft`, `aboutUs_moreAboutDraftUnnamed`, `aboutUs_cardBody`, `aboutUs_cardBodyUnnamed` (values above).
   - AU2's helper, rewritten by the batch-5 rulings (never "you both"): `aboutUs_sinceHelper` "Use whichever date feels right to {couple}." with the couple's chat name (e.g. "… to The Mensahs."), and `aboutUs_sinceHelperUnnamed` "Use whichever date feels right." when there is no name (every draft, and a couple that hasn't chosen one; ruling M-1).
   - Batch-5 fix round 1: `aboutUs_reminderOffline` "We couldn't check this reminder. Check your connection and try again." (the anniversary reminder's offline sheet), and the manual's two partner lines reworded without "they" ("When your partner joins, your answers become your shared About us."; "Your partner sees the change, with your name, next time your partner opens About us.").
   - W5 final review M-5 (partner- and ceremony-facing copy): `aboutUs_changedByPartner` "Changed by your partner" (a partner whose account is gone), `aboutUs_ceremonyLabelGroup` "What kind of ceremony? (optional)", `aboutUs_removeCeremony` "Remove this ceremony", `aboutUs_sinceSuggestions` "Suggested dates", `aboutUs_monthOptional` / `aboutUs_dayOptional` "Month (optional)" / "Day (optional)", `aboutUs_childrenYesBands` "Yes ({bands})", `aboutUs_done` "Done".
   - W5 final fix wave (I-2, M-2): `aboutUs_reminderTimes` "Reminder times and note" (the anniversary reminder's sheet, online and offline), `aboutUs_reminderLocked` "Its date, title and type follow About us." (the reminder form, locked), `aboutUs_anniversaryHandMade` "You already have an anniversary reminder, so we won't add another." (AU6, beside a yearly anniversary reminder the couple made by hand; ruling "M-2 replaced").
6. **Production switch-on, last:** after W4's switch-on (`flow_couples_v2`) and the gate evidence, `update public.feature_flags set enabled = true where key = 'couple_profile';`.
7. **Owner decisions to confirm** (the plan built the recommendation): P-5 (the anniversary at each partner's 09:00), P-6 (the reminder guard), P-14 (the extra copy, including R3's "sees your answers after joining" (M-2) and AU2's couple-name helper), P-17 (an offline answer survives a quick exit), D2 ("Changed by Yaw - Tue, 12 Nov").

## Spec coverage (self-review)

| Spec item | Where |
|---|---|
| §1.3 Q8 (four fields, customary-marriage helper, up to 2 ceremony years, optional child age bands, one anniversary source, attribution line, no push, no feed) | Tasks 1, 4, 5 |
| §1.4 D2 ("Changed by Yaw - Tue, 12 Nov") | Task 4 `changedByText`, Task 5 screen test, mutant |
| §1.4 D16 (questions say "you two"; the pair named by `coupleNameProvider`) | Task 4 copy; Task 5 title (P-15) |
| §1.4 D19, D20 (wipes; nothing about Dating on the device) | Task 3 (`spec1.about_us_outbox`, sign-out only, no "dating" in the key) |
| §1.5 never touch (Games, Opinions, latch, SOUL/THESIS, relationships grants) | Global Constraints; Task 5 Step 12 |
| §2.1 copy (`aboutUs_` keys, why lines, "More about this", Skip bottom left; dates through MyDateFormat; `toMonthYear`, `toYear`) | Tasks 3, 4 (P-14, P-16) |
| §2.2 motion (shared-axis steps, 150 ms selection, reduce motion) | Task 4 (`SharedAxisStep`, `AboutUsChoice`) |
| §2.3 accessibility (AllowLargeText, goldens 1.0/1.3/2.0/RTL, labels, 48 dp, contrast, announced errors) | Tasks 4, 5 (goldens and guidelines on every new screen) |
| §2.5 `couple_profile` effective under `flow_couples_v2`; off = no About us, "Add your anniversary" opens the reminder sheet | Task 3 (P-12), Task 5 Together tests |
| §3.8 AU1-AU6 (options, helpers, why lines, step dots, every one skippable, easiest first, AU3 only when Married, AU2 chips from `aboutUsDateSuggestionsProvider` returning `[]`, AU6 "What day was it?") | Task 4 (P-19, P-20); Task 3 provider |
| §3.8 offered during the wait (R3 card), after linking (Together "Start with", Settings), never before an invite exists; draft before linking, shared after | Task 5 (P-18, P-21), Tasks 1-2 (drafts, adoption) |
| §3.8 About us screen (title, rows, "Changed by" under each answered row, footer, no push/feed/history, never an elapsed counter) | Task 5 (P-15, P-16) |
| §3.8 validation (no future dates, ceremonies only when Married and cleared on leaving it, at most 2, bands only with Yes) | Task 1 section C/D, Task 4 (P-3, P-7) |
| §3.8 read-only while paused or in the window ("You can read this until…"), gone after archive | Task 1 section B, Task 5 (P-4) |
| §3.8 errors (offline queue and replay, last write wins, attributed at replay; refused write → "We couldn't save that. Try again.") | Tasks 3, 4 (P-17) |
| §3.8 R4 drafts adopted into `couple_profiles` | Task 2 (P-8) |
| §3.14 About-us edits queue and replay through `OnboardingSyncService` | Task 3 |
| §4.2 `couple_profiles`, `couple_profile_drafts` (columns, RLS, grants, not in Realtime) | Task 1, section A |
| §4.3 W5 `get_couple_profile`, `update_couple_profile`, draft RPCs, `adopt_couple_profile_drafts`, `sync_anniversary_reminder` | Tasks 1, 2 (P-2, P-4, P-5, P-8, P-9) |
| §4.3 W5 re-created `accept_relationship_invite_v2` (W4 hardening kept), `set_user_path_internal` (I-6), `export_relationship` (`about_us`, no ids), `export_bundle` (three settings) | Task 2 (body diff, `invite_v2_contracts.sql` and Deno green, section I) |
| §4.4 `couple_profiles_together_signal` | Task 1 (section D signal check) |
| §4.7 #10 `couple_profiles` (+ twin) | Tasks 1, 2 (P-1) |
| §4.8 retention (`couple_profiles` with the relationship; drafts moved on linking, on a switch to Dating, with the account) | Tasks 1, 2 (CASCADEs; section F, G) |
| §5.1 `lib/features/couple_profile/{data/couple_profile_service.dart, domain/couple_profile.dart, presentation/screens/about_us_screen.dart, presentation/screens/about_us_question_flow.dart, presentation/widgets/{about_us_card,changed_by_line}.dart}` | Tasks 3-5 (plus `presentation/about_us_entry.dart` for the other ways in, and `presentation/about_us_copy.dart`, `widgets/about_us_choice.dart`) |
| §5.2 `onboarding_sync_service.dart`, `settings_data.dart`, `together_screen.dart` ("Add your anniversary" → AU6; "About us" row; the reminder's sheet), `date_formatter.dart`, the manual topic in `DocumentationRegistry` with its flags, `app_en.arb`, `feature_flag_refresher.dart` (no change: `flowFlagsProvider` is already refreshed and now carries `couple_profile`) | Tasks 3-5 |
| §5.3 `coupleProfileEnabledProvider`, `coupleProfileProvider(relationshipId)` (+ together signal refetch), `coupleProfileDraftProvider`, `aboutUsDateSuggestionsProvider` | Task 3 |
| §5.4 `/about-us/:relationshipId` | Task 5 (P-13) |
| §5.6 R1 (HomeScreen latch untouched), R9 (export from the latest bodies; both export contracts green) | Tasks 2, 3, 5 |
| §5.8 device wipe registry entry | Task 3 |
| §7.1 `couple_profile_contracts.sql` (member read; outsider, sealed, archived denied; paused and window read-only; every validation; attribution per field; signal bump; draft survives a withdrawal; adoption order; a switch to Dating deletes the draft; anniversary reminder created, moved, deleted; export present and uuid-free; no `suggested_dates`; never a type or score) | Tasks 1, 2 |
| §7.1 "Never a type or score" (exact columns, allow-listed readers, no view; the Dart architecture test) | Task 1 section A, Task 3 architecture test |
| §7.3 About us edit and attribution line; goldens; guidelines | Tasks 4, 5 |
| §7.4 mutants: "Re-add the `couple_profile_drafts` delete to the W1 body" (now a file check, P-10), "Add a function that reads `couple_profiles` into a label" | Task 3 architecture test; Task 1 Step 7 `label` |
| §8 W5 contents, depends on W4a and W3b, tests, gate (cultural reviewer) | Tasks 1-5; checklist 5 |
| §9 "Export loses the stories order or gains an id" | Task 2 (body diff, section I, mutant `export_id`) |
| §11 I-6 (the W1 writer names no W5 table; W5 re-creates it), I-12 (no suggested dates on the server) | Task 2 (P-10), Task 1 section B |
