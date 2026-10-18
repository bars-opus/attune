# Spec 1b — Quiet Hours and Discreet Surfaces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Five quiet-surface floors from the couples research, enforced and tested:
1. **Recipient time zone.** A user-level `users.timezone`, reported by the app on open, sign-in and resume, read through one validating resolver.
2. **Quiet hours (F6 (1)).** Every non-safety push whose send time falls in the recipient's local 22:00–08:00 waits until 08:00 local: deferred, never dropped. Overnight chat pushes collapse into one per conversation at 08:00, and a read before 08:00 cancels it.
3. **No plan titles in push copy (F8 (4)).** Together alarms, proposals, hand-offs, rituals, reminders, countdowns, moments, the date poll and the daily summary stop putting plan titles on the lock screen.
4. **The chat streak counter is deleted (F6 (2))** (function, flag, client fetch), with a gate test so it cannot return. **The Mirror attentiveness flag is removed (F6 (3)).**
5. **Device surfaces show "Next plan" by default (F8 (1)).** The home-screen card, the lock-screen Live Activity and the calendar copy show no titles (and the calendar copy no places) unless the user turns titles on for that surface, on that phone.

**Architecture:**
- **One queue, two guards.** Every push already lands in `public.scheduled_notifications`, except four edge functions that call OneSignal directly; Task 5 moves those onto the queue too. Two BEFORE triggers on that table do all the work, so every present and future inserter is covered:
  - `scheduled_notifications_copy_guard` (INSERT) neutralises fields that hold a plan's title, by push type.
  - `scheduled_notifications_quiet_guard` (INSERT, and any return to `pending`) defers to 08:00 local, collapses overnight chat and neutralises "Today"/"Tomorrow" copy that a deferral would make wrong.
  - Postgres fires BEFORE triggers in name order, and `copy` < `quiet`, so the copy guard runs first.
- **Two generators rewritten**, because their copy weaves a title into a sentence: `together_digest_lines` (the daily summary becomes counts and times) and `planning_v2_notify_poll`.
- **Dart.** A small `UserTimezoneReporter` called from `HomeScreen`'s existing three sync points. Per-surface "Show plan titles" preferences are read by each surface's own publish/sync code, the same way they already re-read their on/off preference.

**Tech Stack:** Postgres 17 (local harness `scripts/local_pg_setup.sh`), Supabase RLS / SECURITY DEFINER / triggers, Deno 2 edge functions, Flutter 3.29 + Riverpod 2 (`flutter_riverpod ^2.4.9`, `FamilyAsyncNotifier`), `shared_preferences`, `flutter_test`.

**Spec:** `docs/superpowers/research/2026-10-16-couples-research/06-synthesis-roadmap.md` §3 rows F6 and F8 ((1) titles and (4) push copy; (2)/(3) icon and sender name are Spec 2), §10 Q11 (Mirror: "Remove"), §11 Spec 1. `lib/architecture/attune/ATTUNE_SOUL.md` §5 P1 (no streaks) and §8. Code maps (read alongside this plan): `.superpowers/sdd/spec1-map-f6.md` and `.superpowers/sdd/spec1-map-f8.md`.

---

## OWNER DECISIONS (2026-10-17) AND RULINGS TO CONFIRM AT PLAN REVIEW

**Decided by the owner ("go with all your 3 recommendations"):**
- **D1. Self-set alarms are not deferred.**
  - Short-notice `together_event` alarms (offset ≤ 120 min: "Starting now", "In 1 hour", "In 2 hours") are exempt from quiet hours, like `safety_resources`. Deferring them to 08:00 would make them false.
  - Day-ahead heads-ups ("In 1 day", "In 2 days", offset ≥ 1440) are not alarms: at 08:00 they are still true, so they wait like everything else. Plan review I1: the offset is the 4th field of the alarm's `source_key`.
  - Accepted residual: alarm offsets are stored on the event (`couple_events.remind_offsets_min`), not per person, and `create_couple_event` makes a shared plan confirmed with no acceptance step. So a partner can set a short alarm on a shared plan that rings the other at night. Both can see and edit the plan; Spec 3 may revisit.
- **D2. Overnight chat pushes collapse into one at 08:00 local**, one per conversation ("New messages in Attune" / "Open Attune to read them."). If the recipient reads the conversation before 08:00, the push is cancelled (Task 3).
- **D3. A user-level time zone column.**
  - `public.users.timezone` is self-only under the existing RLS and set through `set_my_timezone`.
  - Resolution order: that column, then the newest `planning_member_settings.timezone`, then the newest `partner_presence.timezone`.
  - When none is known the result is **unknown (NULL), and nothing is deferred for that user** until their app reports a zone (plan review C1). A UTC guess would hold a UTC-5 user's 19:00 push until 03:00 local.
  - Every source is validated, because clients hold table-level UPDATE on their own `users` row.

**Rulings this plan makes. Confirm or reject at review:**
- **R-C (push copy).** Titles leave push copy as follows:
  - Alarm title → "Your plan" (body keeps "In 1 hour" / "Starting now" / "Today").
  - Reminder title → "Reminder" (body keeps "Today" / "Tomorrow" / "In N days").
  - Proposal, hand-off and ritual bodies, and their replies → "Open Attune to see it."
  - Countdown body → "Open Attune to see it."
  - Moment body → "Open Attune to see it."
  - Date-poll body → "{name} suggested dates".
  - Names stay in push titles ("Ama suggested a plan"), as chat pushes already do. Partner names on lock screens are Spec 2's sender-name audit.
- **R-D (declined-proposal note).** The note a partner types when declining is their own words, like a chat preview. It reaches the lock screen only when the recipient has message previews on (`notification_settings.chat_message_preview_enabled`, default off), and then without the plan's title. Otherwise the body is "Open Attune to see it." Today the note always shows; `together_proposals_contracts.sql` is updated to the new rule.
- **R-E (daily summary).** The 08:00–10:00 "Today" / "Your week together" push becomes counts, times and big-day nudges without titles:
  - "1 plan today at 19:00"
  - "3 plans today, first at 09:30"
  - "2 plans this week, first Tue 19:00"
  - "Kofi's big day at 10:00 — a word of luck?"
  - "A suggestion is waiting for you" (kept).
- **R-F (late time-relative copy).** A reminder or countdown queued after 22:00 (only possible when it is created that late) is deferred to 08:00 like everything else. Its "Today"/"Tomorrow"/"Today's the day" wording would be false on the new day, so it becomes "Open Attune to see it." (countdown title "Your plan": the day itself has passed, so "Coming up" would be false too, per plan review I5). Nothing is dropped.
- **R-G (direct pushes).** `accept-invite`, `end-relationship`, `activate-topics` and `send-notification` stop calling OneSignal and enqueue instead, so quiet hours and the copy guard cover them. `end-relationship` still pushes the partner (Spec 3 "Ending v2" removes that push); it now waits for morning. A Deno source-scan test makes the worker the only OneSignal caller. Deferral widens one gap: a proposal or moment queued at 23:00 for a relationship ended at 01:00 still arrives at 08:00 (with neutral copy). Spec 3 owns cancelling a relationship's pending pushes when it ends (plan review M4).
- **R-H (Mirror wording in the spec).** `ATTUNE_MASTER_SPEC.md` §8 "Mirror Game" line "Score tracked: below 6.5/8 = attentiveness flag" is the only edit to that owner-edited file. Decision 33 already records "Mirror attentiveness flag removed"; this line contradicts it.
- **R-I (calendar places).** With titles off, the calendar copy also omits the place (`location`): a clinic or hotel name outs a plan as surely as its title. The "Show plan titles" switch for the calendar copy covers both.
- **Out of scope, flagged:**
  - The subscribed ICS calendar feed (`together_calendar_feed` / `calendar-feed`) still carries titles, notes and places. It is opt-in ("Show Together in my calendar app") and not one of F8 (1)'s three surfaces. Revisit with Spec 2.
  - Other lock-screen text for Spec 2's sender and copy audit (not plan titles, so F8 (4) is met; plan review M3):
    - the forum topic title in `forum_topic_activated`, `forum_activity` and `forum_quiet`;
    - reply previews in `opinion_*`;
    - the score in `pulse_updated`;
    - the partner's name in `checkin_reminder` and in every Together title.

---

## Global Constraints

**How we work**
- Work directly on `main`. **No commits or pushes**: each task ends with a ledger line in `$WS/progress.md` instead of a commit.
- Write each test first and watch it fail before writing code. For SQL, "fail" means the contract file errors on the scratch database built **without** the task's migration (or with the mutant prepended — `$WS/mutant.sh`).
- **Never `dart format` a pre-existing file or directory.** Format only files this plan creates.
- **Snapshot-diff every shared file.** Before editing one, `cp <file> "$WS/snapshots/<flattened-name>"`. After editing, `diff -u "$WS/snapshots/<flattened-name>" <file>` and check it shows only the intended lines. Do not rely on `git diff`: `lib/features/planning/**`, the three architecture docs and the Spec 1a work all carry uncommitted edits.
- Analyzer gate: `flutter analyze <files> 2>&1 | grep -E "^\s*(error|warning) "` prints nothing (the leading anchor matters). A warning on a line the task did not touch is pre-existing: confirm it against the snapshot and note it in the ledger.
- SQL contracts:
  - They are plain-SQL `DO` blocks that assert the **specific** error (`EXCEPTION WHEN insufficient_privilege`, or `GET STACKED DIAGNOSTICS` + exact message text), never `WHEN OTHERS`.
  - Run them on the local Postgres 17 harness, scratch DB **`attune_spec1b`**. Rebuild with `ATTUNE_TEST_DB=attune_spec1b scripts/local_pg_setup.sh --no-tests`, then run `psql -q -d attune_spec1b -v ON_ERROR_STOP=1 -f supabase/tests/<file>.sql`.
  - **Never use `attune_test` or `attune_spec1a`** (other sessions' DBs).
  - A green run prints only `NOTICE` lines.
- Every `REVOKE` lives in its own `*_grants.sql` migration **and** gets an `\i` line appended to `scripts/local_pg_grants.sql`: the harness blanket-grants every **table** after migrations, so an inline table revoke is silently undone locally. Function `REVOKE`/`GRANT` statements are not affected and stay in the behaviour migration.
- Migration timestamps follow the latest existing one (`20261017150100_pulse_privacy_table_grants.sql`). This plan uses `20261017160000` … `20261017190100`, in task order.
- Deno: `deno test --allow-read --allow-env --allow-net <dir>` (several `index.ts` files call `serve()` at import).
- **Never log message content, plan titles or a time zone** in any new function.
- Fixture hygiene: new SQL fixtures use the uuid prefixes `8b`…`8f` and phones `+233598…` listed in each task. Both were confirmed unused on 2026-10-17. `users.phone` is UNIQUE, and `ON CONFLICT DO NOTHING` hides a collision.
- **Known pre-existing failures (do not fix, do not count as regressions):**
  - 8 contract files fail on the harness before this plan: `couple_map_presence`, `reminder_delivery`, `settings_accessor_test`, `story_places`, `together_ai`, `together_events`, `together_occurrence`, `together_proposals`. They are local grant-replay gaps or phone collisions; see the Spec 1a ledger.
  - `together_proposals_contracts.sql` fails at its line 9 (phone collision) on a reused DB. On a fresh DB it fails at line 174 (`null value in column "id" of relation "planning_entries"`), so its decline-note block never runs; ruling R-D is pinned by `push_copy_contracts.sql` instead.
  - `test/features/planning/planning_recent_test.dart` "Recent sits above the categories" fails between local midnight and about 05:00 (it is time-of-day dependent).
  - `deno test supabase/functions/_shared` (the directory) fails type-checking before this plan (`TS2353 … 'utcOffsetMinutes' does not exist in type 'ApprovalDigestInput'`). Run this plan's `_shared` tests by file name.
  - Record the Task 0 baseline and compare final runs to it line for line.
- Shared files touched. Each is a surgical edit; flag the regression risk in the ledger:
  - SQL and scripts: `scripts/local_pg_grants.sql`, `supabase/tests/chat_system_contracts.sql`, `supabase/tests/together_daily_contracts.sql`, `supabase/tests/planning_couple_blocks_contracts.sql`, `supabase/tests/together_phase0_contracts.sql`, `supabase/tests/together_proposals_contracts.sql`.
  - Edge functions: `supabase/functions/{accept-invite,end-relationship,activate-topics,send-notification}/index.ts`.
  - Home and chat: `lib/home/home_screen.dart`, `lib/features/chat/domain/services/chat_feature_flags.dart`, `lib/features/chat/data/repositories/chat_repository.dart`, `lib/features/chat/data/repositories/supabase_chat_repository.dart`, `lib/features/chat/presentation/providers/chat_experience_providers.dart`, `test/features/chat/support/chat_test_harness.dart`.
  - Mirror: `lib/features/games/mirror/**` (scoring, judge screen comment), `test/features/games/mirror_scoring_test.dart`, `test/features/games/mirror_judge_screen_test.dart`.
  - Together: `lib/features/together/**` (widget, live, mirror domain and data, providers, settings sheet, screen), and `test/features/together/{together_widget_sync,together_live_activity,together_calendar_mirror,together_mirror}_test.dart`.
  - Docs: `lib/app/documentations/user_manual/data/chat_docs.dart`, and `lib/architecture/attune/ATTUNE_MASTER_SPEC.md` (one line, ruling R-H).
  - **Do not touch** `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`, `lib/features/planning/**` or `test/features/planning/**`, which hold the owner's uncommitted edits.

**Rules (copied from the spec)**
- F6 (1): "Notification engine defers (never drops) any non-safety push falling in the recipient's local 22:00–08:00; covers date-poll, forum and reminder budgets that currently bypass it."
- F6 (2): "`chat_streaks` flag, migration-side computation and client fetch removed; a grep gate in CI forbids `streak` in chat providers."
- F6 (3): "Mirror flag removed" (owner Q11: "Remove").
- F8 (1): "Widget, Live Activity and calendar mirror show 'Next plan' + time, never the title, unless the user opts into titles per surface."
- F8 (4): "Push copy audit: no event titles that could out an intimate plan."
- SOUL §5 P1: no streaks, no badges, no leaderboards; skips have no consequence.

**Copy (verbatim)**
- Quiet chat collapse: title "New messages in Attune", body "Open Attune to read them."
- Neutral body (every neutralised push): "Open Attune to see it."
- Alarm title: "Your plan". Reminder title: "Reminder". Deferred countdown title: "Your plan".
- Date poll body: "{name} suggested dates" (`{name}` = display name, else "Your partner").
- Daily summary lines (ruling R-E):
  - Day: "{n} plan(s) today", "… at HH:MM", or "…, first at HH:MM".
  - Week: "{n} plan(s) this week: Dy HH:MM" or "…, first Dy HH:MM".
  - Big day: "{name}'s big day at HH:MM — a word of luck?" (in the week summary, prefixed "Dy: ").
  - "A suggestion is waiting for you".
- Device surfaces: "Next plan" (card and lock screen), "Reminder" (card, for a reminder), "Free" (card, unchanged), "Plan" (calendar copy).
- Settings, home-screen card subtitle: "Off unless you turn it on. Shows “Next plan” and the time — no names, and no titles unless you turn them on. Anyone who sees your phone can see it; quick exit clears it."
- Settings, lock-screen subtitle: "Off unless you turn it on. A plan you’re both in shows as “Next plan” with its time and a countdown from 4 hours before — no names, and no titles unless you turn them on. Anyone who sees your phone can see it; quick exit clears it."
- Settings, calendar copy subtitle: "Off unless you turn it on. Adds a calendar called “Plans” with the next 60 days of plans you’re in, each as “Plan” with its time — never names or notes, and no titles or places unless you turn them on. If your phone keeps calendars in iCloud it may show on your other devices. Turning it off or quick exit deletes it."
- Settings sub-row (shown only while its surface is on):
  - Title: "Show plan titles".
  - Subtitle (card and lock screen): "Shows what each plan is called. Anyone who sees your phone can read it."
  - Subtitle (calendar copy): "Copies each plan’s title and place. Anyone who sees your calendar can read them."
- Chat FAQ (`faq_chat_quiet_hours`):
  - Question: "Why do some notifications arrive at 8 in the morning?"
  - Answer: "Attune holds notifications between 10 pm and 8 am in your time zone and sends them at 8 am instead — nothing is lost. Messages that arrive overnight become one notification per conversation, and none at all if you read them first. Safety resources, alarms set for shortly before a plan, and moves in a game you're playing right now are never held."

**Constants**

| Name | Where | Value |
|---|---|---|
| Quiet window | `quiet_hours_release_at` | `[22:00, 08:00)` recipient local; release at 08:00 local |
| Exempt push types | `scheduled_notifications_quiet_guard` | `safety_resources`; `together_event` whose alarm offset (4th `source_key` field) is ≤ 120 min |
| Collapse key | quiet guard | `'quiet_chat:' || user_id || ':' || relationship_id || ':' || to_char(release AT TIME ZONE 'UTC','YYYYMMDDHH24MI')` |
| Time-zone fallback | `notification_recipient_tz` | `users.timezone` → newest `planning_member_settings` → newest `partner_presence` → NULL (unknown: no deferral); each checked with `presence_tz_ok` |
| Reporter prefs key | `UserTimezoneReporter.prefsKey(userId)` | `user_timezone_reported:<userId>` |
| Titles prefs keys | data layer | `together_widget_titles`, `together_live_titles`, `together_mirror_titles` (default off) |

## Review Focus

1. **A retry or a stale-lease reset at night.** The worker puts a failed push back to `pending` with its old `scheduled_for`; at 23:00 it would go out immediately. The quiet guard fires on any return to `pending`. Pinned in Task 2 (`quiet_hours_contracts.sql` block 4, with a night zone chosen against the real clock).
2. **Overnight messages read before 08:00.** The 08:00 "New messages" push must not arrive for a conversation already read. Pinned in Task 3 (`quiet_chat_read_contracts.sql` block 2). Known gap (plan review M5): a night with only a reaction may give the opening client nothing new to mark, so `mark_conversation_read` may not run and the push still comes. That is accepted.
3. **A traveller.** The zone must follow the phone on resume, not stay cached for the process. Pinned in Task 1 (`user_timezone_reporter_test.dart` "a changed zone is reported again"; production reads `FlutterTimezone` directly on every report, never `TimezoneUtils`' process cache).
4. **The DST morning.** On the night clocks spring forward, the release must still be 08:00 local (not 07:00 or 09:00). Pinned in Task 2 (block 0, America/New_York 2026-03-08).
5. **A reminder created at 23:00 for "today".** It must not vanish and must not say "Today" on the wrong day. Pinned in Task 2 (block 6) and ruling R-F.
6. **A declined proposal with a personal note, recipient's previews off.** The note must not reach the lock screen. Pinned in Task 4 (`push_copy_contracts.sql` block 2).
7. **Turning "Show plan titles" on or off while the surface is showing.** What is on the card, lock screen and calendar must change straight away, not at the next agenda load. Pinned in Task 8: the data layer by `together_surface_titles_test.dart` "turning titles on replaces the calendar entries", and the screen listener by `together_screen_test.dart` "turning plan titles on re-sends the card straight away". The lock-screen and calendar listeners mirror that one and are covered by device check 4 in Task 9.


## Owner follow-up (2026-10-17, after the final review)

The owner asked for the I2 recommendation and all nine minors. Done test-first; each is in the ledger.
- **Game pushes:** a push about a game session skips quiet hours only while the game is live: the recipient was in the app in the last 15 minutes (`chat_presence`), or the session had a move in the last 15 minutes (`quiet_hours_game_live`). Invites to a partner who may be asleep still wait.
- **M1:** a chat push retried into the night joins the overnight push, or becomes it. Every overnight chat push is neutral.
- **M2:** an inserter's own `source_key` on a chat push is kept.
- **M3:** the calendar copy deduplicates by plan id + fingerprint.
- **M4:** text fixed.
- **M5:** a deferred day-ahead alarm says "Today" / "Tomorrow" / "In N days" measured from 08:00.
- **M6:** the alarm-offset parse is CASE-guarded.
- **M7:** the guard re-checks the worker's claim and bounces it back to `pending` at night; the worker skips a bounced claim.
- **M8:** alarms, the daily summary, countdowns and reminders all use `notification_local_zone` (reported zone → Planning → UTC), in `20261017180100`.
- **M9:** cosmetic.

## Plan review (Fable, 2026-10-17)

Report: `.superpowers/sdd/2026-10-17-spec1b-quiet-surfaces-plan-review.md`. Applied:
- **C1:** unknown zone → NULL, no deferral; Task 1 block 5, Task 2 block 7, a UTC-guess mutant, and hand-off order with the app first.
- **I1:** D1 narrowed to short-notice alarms; Task 2 block 2.
- **I2:** Spec 1a hard dependency; preflight in `170100`, hand-off item 2.
- **I3:** the reporter reads `FlutterTimezone` directly, plus a test.
- **I4:** a collapse-key clash queues a keyless neutral push; Task 2 block 5.
- **I5:** deferred countdown title "Your plan".
- **Minors:**
  - M1: the index;
  - M2: worker throughput in the hand-off;
  - M3: other lock-screen text flagged for Spec 2;
  - M4: stale pushes after an ending assigned to Spec 3;
  - M5: the reaction-only gap noted;
  - M6: `'cancelled'` status;
  - M7: corrected sentence;
  - M9: the `RETURN NULL` note;
  - M10: auth-listener note;
  - M11: kill switches.
- **Not applied:** M8 (a surface's titles switch survives turning the surface off and on). Ruling: the switch is shown again the moment the surface is back on, and resetting it would silently undo a choice the user made; the cost if wrong is titles reappearing when a surface is re-enabled.

## Plan verification (dry run, 2026-10-17, before review)

Every code block was extracted and run outside the repo (scratch DB `attune_spec1b_dry`, scratch copies of `supabase/functions` and the Flutter tree). Nothing in the repo changed.
- **Contracts.**
  - The 5 new contract files fail on a pre-plan DB (`attune_spec1a`) and pass after the 6 migrations.
  - The 4 edited contracts (`together_daily`, `planning_couple_blocks`, `together_phase0`, `chat_system`) fail before and pass after.
  - Neighbours stay green: `together_rituals`, `reminder_lead_time`, `games`, `snakes_and_ladders`, the Spec 1a read and seen contracts, `love_map`.
  - All 7 mutants are killed.
  - **Re-run after the review fixes:** a fresh dry DB, all contracts and neighbours green, 8 mutants killed (including the UTC-guess mutant), and the `170100` preflight refuses to apply without Spec 1a. Reporter: 6 tests and `test/home` green, analyzer clean.
- **Deno.** Queue + transport gate: 5 passed. Worker: 1 passed. `deno check` is clean on the 4 edited functions.
- **Flutter.** The Tasks 1, 6, 7 and 8 edits compile and pass: chat, home, games/mirror and Together suites, plus the full suite (every failure was a test reading files the copy left out).
- **Fixes the dry run forced, folded in above:**
  - the unused `chat_state.dart` import (Task 6);
  - the calendar fixture that reset the store (Task 8);
  - `together_screen_test.dart`'s 11 surface tests and the new Review Focus 7 test (Task 8);
  - the `_shared` Deno type-check and the `together_proposals` fresh-DB failure, both pre-existing (Global Constraints).
8. **A user with no zone anywhere** (an old app build, forum-only or dating users, nobody who opened Planning). Nothing may move: no 03:00 releases. Pinned in Task 1 (`user_timezone_contracts.sql` block 5: the resolver returns NULL) and Task 2 (`quiet_hours_contracts.sql` block 7).

---

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/20261017160000_user_timezone.sql` (new) | `users.timezone`, `set_my_timezone`, `notification_recipient_tz` |
| `supabase/migrations/20261017170000_quiet_hours.sql` (new) | `quiet_hours_release_at`, `scheduled_notifications_quiet_guard` + trigger |
| `supabase/migrations/20261017170100_quiet_chat_read_skip.sql` (new) | `mark_conversation_read` cancels the conversation's pending chat pushes |
| `supabase/migrations/20261017180000_push_copy.sql` (new) | `scheduled_notifications_copy_guard` + trigger; `together_digest_lines`; `planning_v2_notify_poll` |
| `supabase/migrations/20261017190000_drop_chat_streak_counter.sql` (new) | Drop `chat_conversation_streak`; delete flag |
| `supabase/migrations/20261017190100_mirror_flag_removed.sql` (new) | `finalise_mirror_scores` without `flagged`; drop the column |
| `supabase/tests/user_timezone_contracts.sql`, `quiet_hours_contracts.sql`, `quiet_chat_read_contracts.sql`, `push_copy_contracts.sql`, `mirror_flag_contracts.sql` (new) | Contracts |
| `supabase/tests/{chat_system,together_daily,planning_couple_blocks,together_phase0,together_proposals}_contracts.sql` (shared) | Updated assertions |
| `supabase/functions/_shared/push_queue.ts` + `push_queue.test.ts` + `push_transport.test.ts` (new) | `enqueuePush`; transport gate |
| `supabase/functions/{accept-invite,end-relationship,activate-topics,send-notification}/index.ts` (shared) | Enqueue instead of send |
| `lib/core/services/user_timezone_reporter.dart` (new) + `test/core/services/user_timezone_reporter_test.dart`, `test/home/home_screen_timezone_wiring_test.dart` (new) | Zone reporting |
| `lib/home/home_screen.dart` (shared) | Three `_reportTimezone()` calls |
| chat Dart files (shared) + `test/features/chat/no_streak_counter_gate_test.dart` (new); delete `test/features/chat/streak_test.dart` | Counter removal |
| `lib/features/games/mirror/domain/services/mirror_scoring.dart` (shared) + tests | Flag removal |
| `lib/features/together/**` (shared) + `test/features/together/together_surface_titles_test.dart` (new) | Titles off by default |
| `lib/app/documentations/user_manual/data/chat_docs.dart` (shared) | Quiet-hours FAQ |

---

### Task 0: Workspace, baseline and scratch database

**Files:**
- Create: `.superpowers/sdd/2026-10-17-spec1b-quiet-surfaces/progress.md` (the ledger)
- Create: `.superpowers/sdd/2026-10-17-spec1b-quiet-surfaces/mutant.sh`

- [ ] **Step 1: Create the workspace and the ledger**

```bash
export WS=/Users/user/attune/.superpowers/sdd/2026-10-17-spec1b-quiet-surfaces
mkdir -p "$WS/snapshots"
cat > "$WS/progress.md" <<'LEDGER'
# SDD ledger — plan: docs/superpowers/plans/2026-10-17-spec1b-quiet-surfaces.md

Spec 1b — Quiet hours and discreet surfaces. Branch: main (no commits). Scratch DB: attune_spec1b.
Owner decisions (2026-10-17): D1 alarms not deferred; D2 overnight chat collapses at 08:00; D3 users.timezone.

## Baseline
LEDGER
```

- [ ] **Step 2: Write the mutant runner**

The contract files begin with `BEGIN;` and end with `ROLLBACK;`. The runner prepends a mutation inside the same transaction, so nothing persists. A green run against a mutant means the test is vacuous.

```bash
cat > "$WS/mutant.sh" <<'SH'
#!/usr/bin/env bash
# usage: mutant.sh "<sql to prepend>" supabase/tests/<file>.sql
set -u
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"
cd /Users/user/attune
out=$({ echo "BEGIN;"; echo "$1"; awk '!d && /^BEGIN;$/ {d=1; next} {print}' "$2"; } \
  | psql -q -d "${ATTUNE_TEST_DB:-attune_spec1b}" -v ON_ERROR_STOP=1 2>&1)
echo "$out" | grep -E "ERROR|VIOLATED|EXPLOIT" | head -3
if echo "$out" | grep -qE "CONTRACT VIOLATED|EXPLOIT"; then
  echo "MUTANT KILLED"
else
  echo "MUTANT NOT KILLED (vacuous or broken mutation)"; exit 1
fi
SH
chmod +x "$WS/mutant.sh"
```

- [ ] **Step 3: Measure the baselines**

```bash
cd /Users/user/attune
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"
grep -rln -- "+233598" supabase/tests; for p in 8b100000- 8c100000- 8d100000- 8e100000- 8f100000-; do grep -rl -- "$p" supabase/tests; done; echo "fixtures checked"
flutter test > "$WS/baseline-flutter.txt" 2>&1; tr '\r' '\n' < "$WS/baseline-flutter.txt" | grep -E "All tests|Some tests" | tail -1
for d in process-scheduled-notifications compute-pulse; do deno test --allow-read --allow-env --allow-net supabase/functions/$d 2>&1 | grep -E "passed|failed" | tail -1; done
ATTUNE_TEST_DB=attune_spec1b scripts/local_pg_setup.sh > "$WS/baseline-sql.txt" 2>&1; grep -cE "^\s+PASS" "$WS/baseline-sql.txt"; grep -E "^\s+FAIL" -A1 "$WS/baseline-sql.txt"
```
Expected:
- The grep finds nothing; the only output is `fixtures checked`.
- Flutter shows the full pass count, with at most the one time-of-day failure.
- Deno: `process-scheduled-notifications` 1 passed and `compute-pulse` 76 passed.
- SQL: the 8 known FAIL files only, and no migration `FAILED:`.

Write all the numbers into the ledger's Baseline block.

- [ ] **Step 4: Ledger**

Append `Task 0: complete (baseline flutter N/1 tod, deno psn 1 + compute-pulse 76, sql PASS M / FAIL 8 known)`.

---

### Task 1: Recipient time zone — column, setter, resolver, reporter

**Files:**
- Create: `supabase/migrations/20261017160000_user_timezone.sql`
- Create: `supabase/tests/user_timezone_contracts.sql`
- Create: `lib/core/services/user_timezone_reporter.dart`
- Create: `test/core/services/user_timezone_reporter_test.dart`
- Create: `test/home/home_screen_timezone_wiring_test.dart`
- Modify: `lib/home/home_screen.dart` (import; `_reportTimezone()`; three call sites)

**Interfaces:**
- Produces (SQL):
  - `public.users.timezone text NULL` (length 1..64).
  - `public.set_my_timezone(p_timezone text) RETURNS void`. SECURITY DEFINER. Raises `timezone:invalid_input` when `presence_tz_ok` is false. EXECUTE for `authenticated` only.
  - `public.notification_recipient_tz(p_user uuid) RETURNS text`. SECURITY DEFINER, no client EXECUTE. Returns a zone that `presence_tz_ok` accepts, or **NULL** when none is known.
  - `planning_member_settings_user_idx` on `(user_id, updated_at DESC)`.
- Produces (Dart): `class UserTimezoneReporter { UserTimezoneReporter({required Future<String> Function() deviceTimezone, required Future<void> Function(String) send}); static String prefsKey(String userId); Future<void> report(String? userId); }` and `final userTimezoneReporterProvider = Provider<UserTimezoneReporter>`.
- Consumes: `public.presence_tz_ok(text)` (`20261016100000_presence_v2.sql:151`), and `FlutterTimezone.getLocalTimezone()` directly. Not `TimezoneUtils`: it caches for the process and returns `'UTC'` on failure (plan review I3).

- [ ] **Step 1: Write the failing contract**

```sql
-- supabase/tests/user_timezone_contracts.sql
-- Recipient time zone (Spec 1b Task 1): users.timezone is self-only and
-- set through a validating RPC; notification_recipient_tz returns a valid
-- zone from the user's own report, then Planning/Together's, then the
-- couple map's, else NULL (unknown -- never a guess). Every check RAISEs.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('8b100000-0000-0000-0000-0000000000a1'),
  ('8b100000-0000-0000-0000-0000000000b2'),
  ('8b100000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('8b100000-0000-0000-0000-0000000000a1', '+233598100001', 'Zone A'),
  ('8b100000-0000-0000-0000-0000000000b2', '+233598100002', 'Zone B'),
  ('8b100000-0000-0000-0000-0000000000c3', '+233598100003', 'Zone C')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at) VALUES
  ('8b200000-0000-0000-0000-000000000001', '8b100000-0000-0000-0000-0000000000a1',
   '8b100000-0000-0000-0000-0000000000b2', 'active', CURRENT_DATE, now())
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- 1. The column exists; the app may call the setter; nobody but the server
--    reaches the resolver.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'timezone') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: users.timezone does not exist';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.set_my_timezone(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the app cannot report its zone';
  END IF;
  IF has_function_privilege('anon', 'public.set_my_timezone(text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.notification_recipient_tz(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.notification_recipient_tz(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the setter or the resolver is open to the wrong role';
  END IF;
END $$;

-- 2. The app reports a zone; the resolver uses it.
DO $$
DECLARE v text;
BEGIN
  PERFORM pg_temp.as_user('8b100000-0000-0000-0000-0000000000a1');
  PERFORM public.set_my_timezone('Africa/Accra');
  RESET ROLE;
  SELECT timezone INTO v FROM public.users WHERE id = '8b100000-0000-0000-0000-0000000000a1';
  IF v IS DISTINCT FROM 'Africa/Accra' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: set_my_timezone stored %', v;
  END IF;
  IF public.notification_recipient_tz('8b100000-0000-0000-0000-0000000000a1') <> 'Africa/Accra' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the resolver ignored the user''s own zone';
  END IF;
END $$;

-- 3. Abbreviations, offsets, legacy names, blanks, NULL and made-up zones
--    are refused, and the stored zone is unchanged.
DO $$
DECLARE v_zone text; v_msg text;
BEGIN
  FOREACH v_zone IN ARRAY ARRAY['BST', 'UTC+3', 'Japan', '', 'Mars/Olympus'] LOOP
    PERFORM pg_temp.as_user('8b100000-0000-0000-0000-0000000000a1');
    BEGIN
      PERFORM public.set_my_timezone(v_zone);
      RAISE EXCEPTION 'CONTRACT VIOLATED: "%" accepted as a zone', v_zone;
    EXCEPTION WHEN raise_exception THEN
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      IF v_msg <> 'timezone:invalid_input' THEN RAISE; END IF;
    END;
    RESET ROLE;
  END LOOP;
  PERFORM pg_temp.as_user('8b100000-0000-0000-0000-0000000000a1');
  BEGIN
    PERFORM public.set_my_timezone(NULL);
    RAISE EXCEPTION 'CONTRACT VIOLATED: NULL accepted as a zone';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'timezone:invalid_input' THEN RAISE; END IF;
  END;
  RESET ROLE;
  IF (SELECT timezone FROM public.users WHERE id = '8b100000-0000-0000-0000-0000000000a1') <> 'Africa/Accra' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused zone changed the stored one';
  END IF;
END $$;

-- 4. A zone is coarse location: the partner can never read it.
DO $$
DECLARE v int;
BEGIN
  PERFORM pg_temp.as_user('8b100000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v FROM public.users
   WHERE id = '8b100000-0000-0000-0000-0000000000a1' AND timezone IS NOT NULL;
  RESET ROLE;
  IF v <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the partner can read my time zone'; END IF;
END $$;

-- 5. Fallbacks, each validated: Planning's zone, then the couple map's,
--    else unknown (NULL, never a UTC guess); a garbage value anywhere is
--    skipped.
DO $$
BEGIN
  -- B never reported; Planning stored a zone.
  INSERT INTO public.planning_member_settings (relationship_id, user_id, timezone)
  VALUES ('8b200000-0000-0000-0000-000000000001', '8b100000-0000-0000-0000-0000000000b2', 'Europe/London');
  IF public.notification_recipient_tz('8b100000-0000-0000-0000-0000000000b2') <> 'Europe/London' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Planning''s zone was not used';
  END IF;
  -- Planning's row turns to garbage; the couple map knows better.
  UPDATE public.planning_member_settings SET timezone = 'Mars/Olympus'
   WHERE user_id = '8b100000-0000-0000-0000-0000000000b2';
  INSERT INTO public.partner_presence (user_id, relationship_id, timezone)
  VALUES ('8b100000-0000-0000-0000-0000000000b2', '8b200000-0000-0000-0000-000000000001', 'Asia/Tokyo');
  IF public.notification_recipient_tz('8b100000-0000-0000-0000-0000000000b2') <> 'Asia/Tokyo' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a garbage Planning zone was used, or the map''s was skipped';
  END IF;
  -- C has nothing anywhere: unknown, not a guess.
  IF public.notification_recipient_tz('8b100000-0000-0000-0000-0000000000c3') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no zone resolved to a guess (%), not NULL',
      public.notification_recipient_tz('8b100000-0000-0000-0000-0000000000c3');
  END IF;
  -- A client can write users.timezone directly (table-level UPDATE on its own
  -- row); garbage there is skipped too.
  UPDATE public.users SET timezone = 'Nope/Zone' WHERE id = '8b100000-0000-0000-0000-0000000000c3';
  IF public.notification_recipient_tz('8b100000-0000-0000-0000-0000000000c3') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a garbage users.timezone was trusted';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'user_timezone_contracts: all held'; END $$;
ROLLBACK;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `ATTUNE_TEST_DB=attune_spec1b scripts/local_pg_setup.sh --no-tests 2>&1 | grep -E "FAILED|applied"; psql -q -d attune_spec1b -v ON_ERROR_STOP=1 -f supabase/tests/user_timezone_contracts.sql 2>&1 | grep -m1 ERROR`
Expected: `ERROR:  CONTRACT VIOLATED: users.timezone does not exist`.

- [ ] **Step 3: Write the migration**

```sql
-- supabase/migrations/20261017160000_user_timezone.sql
--
-- The recipient's time zone, for quiet hours (Spec 1b; owner decision
-- 2026-10-17: a user-level column the app reports on open).
--
-- users is self-only under RLS, so the partner never reads it (a zone is
-- coarse location). Clients hold table-level UPDATE on their own users row,
-- so a client could write anything here: set_my_timezone is the app's path,
-- and every reader validates with presence_tz_ok and falls back.
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS timezone text
  CHECK (timezone IS NULL OR char_length(timezone) BETWEEN 1 AND 64);

CREATE OR REPLACE FUNCTION public.set_my_timezone(p_timezone text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.presence_tz_ok(p_timezone) THEN
    RAISE EXCEPTION 'timezone:invalid_input';
  END IF;
  UPDATE public.users SET timezone = p_timezone
   WHERE id = auth.uid() AND timezone IS DISTINCT FROM p_timezone;
END $$;
REVOKE ALL ON FUNCTION public.set_my_timezone(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_my_timezone(text) TO authenticated;

-- Where a push's recipient is: their own report, then the zone Planning or
-- Together last stored for them, then the couple map's. NULL means unknown:
-- callers must not guess (a UTC guess holds a UTC-5 user's 19:00 push until
-- 03:00 local).
CREATE OR REPLACE FUNCTION public.notification_recipient_tz(p_user uuid)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v text;
BEGIN
  SELECT u.timezone INTO v FROM public.users u WHERE u.id = p_user;
  IF public.presence_tz_ok(v) THEN RETURN v; END IF;
  FOR v IN SELECT s.timezone FROM public.planning_member_settings s
            WHERE s.user_id = p_user ORDER BY s.updated_at DESC LIMIT 3 LOOP
    IF public.presence_tz_ok(v) THEN RETURN v; END IF;
  END LOOP;
  FOR v IN SELECT p.timezone FROM public.partner_presence p
            WHERE p.user_id = p_user AND p.timezone IS NOT NULL
            ORDER BY p.updated_at DESC NULLS LAST LIMIT 3 LOOP
    IF public.presence_tz_ok(v) THEN RETURN v; END IF;
  END LOOP;
  RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION public.notification_recipient_tz(uuid) FROM PUBLIC, anon, authenticated;

-- The resolver runs on every queued push (Spec 1b quiet guard); its Planning
-- lookup is by user, which the (relationship_id, user_id) key cannot serve.
CREATE INDEX IF NOT EXISTS planning_member_settings_user_idx
  ON public.planning_member_settings (user_id, updated_at DESC);
```

- [ ] **Step 4: Rebuild, run, mutate**

```bash
ATTUNE_TEST_DB=attune_spec1b scripts/local_pg_setup.sh --no-tests 2>&1 | grep -E "FAILED|applied"
psql -q -d attune_spec1b -v ON_ERROR_STOP=1 -f supabase/tests/user_timezone_contracts.sql 2>&1 | grep -E "ERROR|held"
"$WS/mutant.sh" "CREATE OR REPLACE FUNCTION public.notification_recipient_tz(p_user uuid) RETURNS text LANGUAGE sql STABLE AS \$\$ SELECT coalesce((SELECT timezone FROM public.users WHERE id = p_user), 'UTC') \$\$;" supabase/tests/user_timezone_contracts.sql
```
Expected: `failed 0`; `NOTICE:  user_timezone_contracts: all held`; the mutant (which trusts `users.timezone` unvalidated and has no fallbacks) prints `CONTRACT VIOLATED: Planning's zone was not used` and `MUTANT KILLED`.

Then the UTC-guess mutant:
```bash
"$WS/mutant.sh" "$(sed -n '/CREATE OR REPLACE FUNCTION public.notification_recipient_tz/,/^END \$\$;/p' supabase/migrations/20261017160000_user_timezone.sql | sed 's/RETURN NULL;/RETURN '"'"'UTC'"'"';/')" supabase/tests/user_timezone_contracts.sql
```
Expected: `CONTRACT VIOLATED: no zone resolved to a guess (UTC), not NULL` and `MUTANT KILLED`.

If the `partner_presence` INSERT in block 5 is refused by a constraint or trigger the map did not show, add the minimum extra columns it needs and record a ruling. Do not drop the presence fallback case.

- [ ] **Step 5: Write the failing Dart tests**

```dart
// test/core/services/user_timezone_reporter_test.dart
import 'package:attune/core/services/user_timezone_reporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late List<String> sent;
  late String zone;
  late bool failSend;
  late UserTimezoneReporter reporter;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sent = [];
    zone = 'Africa/Accra';
    failSend = false;
    reporter = UserTimezoneReporter(
      deviceTimezone: () async => zone,
      send: (z) async {
        if (failSend) throw Exception('offline');
        sent.add(z);
      },
    );
  });

  test('reports once per zone per user', () async {
    await reporter.report('u1');
    await reporter.report('u1');
    expect(sent, ['Africa/Accra']);
  });

  test('a changed zone is reported again (a traveller, on resume)', () async {
    await reporter.report('u1');
    zone = 'Europe/London';
    await reporter.report('u1');
    expect(sent, ['Africa/Accra', 'Europe/London']);
  });

  test('another user on the same phone reports for themselves', () async {
    await reporter.report('u1');
    await reporter.report('u2');
    expect(sent, ['Africa/Accra', 'Africa/Accra']);
  });

  test('signed out or no zone: nothing is sent', () async {
    await reporter.report(null);
    zone = '';
    await reporter.report('u1');
    expect(sent, isEmpty);
  });

  test('a device read that throws sends nothing', () async {
    final broken = UserTimezoneReporter(
      deviceTimezone: () async => throw StateError('channel'),
      send: (z) async => sent.add(z),
    );
    await broken.report('u1');
    expect(sent, isEmpty);
  });

  test('a failed send never throws and is retried next time', () async {
    failSend = true;
    await reporter.report('u1');
    expect(sent, isEmpty);
    failSend = false;
    await reporter.report('u1');
    expect(sent, ['Africa/Accra']);
  });
}
```

```dart
// test/home/home_screen_timezone_wiring_test.dart
// Spec 1b: quiet hours follow the phone's zone, reported at the three
// moments HomeScreen already re-syncs (first frame, sign-in, resume). A
// source scan, the repo's pattern for wiring that a widget test cannot
// reach without the whole auth stack (see together_routes_test.dart).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HomeScreen reports the time zone at first frame, sign-in and resume', () {
    final src = File('lib/home/home_screen.dart').readAsStringSync();
    expect(src, contains("import 'package:attune/core/services/user_timezone_reporter.dart';"));
    expect(src, contains('void _reportTimezone()'));
    expect(RegExp(r'_reportTimezone\(\);').allMatches(src).length, 3);
    final resume = src.substring(src.indexOf('void didChangeAppLifecycleState'));
    expect(resume.substring(0, resume.indexOf('\n  }')), contains('_reportTimezone();'));
  });
}
```

Run: `flutter test test/core/services/user_timezone_reporter_test.dart test/home/home_screen_timezone_wiring_test.dart`
Expected: both fail. The reporter test fails to compile (missing file); the wiring test fails on the import expectation.

- [ ] **Step 6: Write the reporter**

```dart
// lib/core/services/user_timezone_reporter.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tells the server which time zone this phone is in, so quiet hours
/// (22:00–08:00) are the user's own nights (Spec 1b). Called on app open,
/// sign-in and resume; sends only when the zone changed since this user's
/// last report on this phone. Never throws: a missed report only means the
/// server keeps the last zone it knew, or falls back.
class UserTimezoneReporter {
  UserTimezoneReporter({
    required Future<String> Function() deviceTimezone,
    required Future<void> Function(String timezone) send,
  }) : _deviceTimezone = deviceTimezone,
       _send = send;

  final Future<String> Function() _deviceTimezone;
  final Future<void> Function(String timezone) _send;

  static String prefsKey(String userId) => 'user_timezone_reported:$userId';

  Future<void> report(String? userId) async {
    if (userId == null) return;
    try {
      final zone = await _deviceTimezone();
      if (zone.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(prefsKey(userId)) == zone) return;
      await _send(zone);
      await prefs.setString(prefsKey(userId), zone);
    } catch (_) {
      // Retried on the next open or resume.
    }
  }
}

final userTimezoneReporterProvider = Provider<UserTimezoneReporter>((ref) {
  return UserTimezoneReporter(
    // Read the platform directly on every report: TimezoneUtils caches the
    // zone for the whole process (a traveller's new zone must be seen on
    // resume), returns 'UTC' on any failure (which would overwrite a good
    // zone) and an abbreviation on web. '' means "unknown, send nothing".
    deviceTimezone: () async {
      if (kIsWeb) return '';
      try {
        return await FlutterTimezone.getLocalTimezone();
      } catch (_) {
        return '';
      }
    },
    send: (zone) async {
      await Supabase.instance.client.rpc(
        'set_my_timezone',
        params: {'p_timezone': zone},
      );
    },
  );
});
```

- [ ] **Step 7: Wire HomeScreen**

Snapshot: `cp lib/home/home_screen.dart "$WS/snapshots/home_screen.dart"`.

Add the import after `import 'package:attune/core/providers/shared_prefs_provider.dart';`:
```dart
import 'package:attune/core/services/user_timezone_reporter.dart';
```
In the auth listener, change
```dart
      _syncRelationshipMode();
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncRelationshipMode(),
    );
```
to
```dart
      _syncRelationshipMode();
      _reportTimezone();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncRelationshipMode();
      _reportTimezone();
    });
```
Change
```dart
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncRelationshipMode();
  }
```
to
```dart
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncRelationshipMode();
      _reportTimezone();
    }
  }

  // Quiet hours follow the phone's zone (Spec 1b). The reporter sends only
  // a changed zone and never throws.
  void _reportTimezone() {
    unawaited(
      ref
          .read(userTimezoneReporterProvider)
          .report(_authService.currentUser?.id),
    );
  }
```
(`dart:async` is already imported, line 1, and `HomeScreen` is a `ConsumerStatefulWidget`, so `ref` is available.) The auth-listener call sits after the listener's early `if (userId == _scopeUserId) return;`, so token refreshes do not report; only a real sign-in does. Resume is covered by the lifecycle hook (plan review M10).

- [ ] **Step 8: Run the Dart tests, diff, analyze**

```bash
flutter test test/core/services/user_timezone_reporter_test.dart test/home/home_screen_timezone_wiring_test.dart test/home
diff -u "$WS/snapshots/home_screen.dart" lib/home/home_screen.dart
dart format lib/core/services/user_timezone_reporter.dart test/core/services/user_timezone_reporter_test.dart test/home/home_screen_timezone_wiring_test.dart
flutter analyze lib/core/services/user_timezone_reporter.dart lib/home/home_screen.dart test/core/services/user_timezone_reporter_test.dart test/home/home_screen_timezone_wiring_test.dart 2>&1 | grep -E "^\s*(error|warning) "
```
Expected:
- All tests pass, including the existing `test/home` tests. If one pumps `HomeScreen`, the reporter's `Supabase.instance` and platform-channel failures are caught inside `report`.
- The diff shows only the lines above.
- The analyzer grep prints nothing.

- [ ] **Step 9: Ledger**

Append `Task 1: complete (user_timezone_contracts green; 2 mutants KILLED; reporter 6 tests + wiring scan green). Regression risk: HomeScreen gains one unawaited call at three existing sync points.`

---
### Task 2: Quiet hours — defer to 08:00 local, exempt safety and alarms, collapse overnight chat

**Files:**
- Create: `supabase/migrations/20261017170000_quiet_hours.sql`
- Create: `supabase/tests/quiet_hours_contracts.sql`

**Interfaces:**
- Consumes: `notification_recipient_tz(uuid)` (Task 1).
- Produces:
  - `public.quiet_hours_release_at(p_at timestamptz, p_tz text) RETURNS timestamptz`: `p_at` itself outside the window, else the next 08:00 local. The guard never calls it with a NULL zone.
  - Trigger `scheduled_notifications_quiet_guard` (BEFORE INSERT OR UPDATE OF status). A deferred row gets `metadata.quiet_deferred = true`.
  - Overnight chat rows carry `source_key = 'quiet_chat:<user>:<relationship>:<release YYYYMMDDHH24MI UTC>'` and `metadata.quiet_count` (≥ 2 once collapsed). A collapsed insert returns no row (the BEFORE trigger returns NULL).

- [ ] **Step 1: Write the failing contract**

```sql
-- supabase/tests/quiet_hours_contracts.sql
-- Engine-level quiet hours (Spec 1b Task 2; research 06 §3 F6 (1)): a push
-- whose send time is in the recipient's local 22:00–08:00 waits for 08:00
-- local, deferred never dropped; safety resources and plan alarms never
-- wait; a retry at night waits too; overnight chat collapses to one push per
-- conversation; "Today"/"Tomorrow" copy deferred across midnight goes
-- neutral. Every check RAISEs.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('8c100000-0000-0000-0000-0000000000a1'),
  ('8c100000-0000-0000-0000-0000000000b2'),
  ('8c100000-0000-0000-0000-0000000000c3'),
  ('8c100000-0000-0000-0000-0000000000d4'),
  ('8c100000-0000-0000-0000-0000000000e5')
ON CONFLICT (id) DO NOTHING;
-- A: Accra (UTC+0, no DST). B: New York. C and D: zones picked below so the
-- REAL clock is 23:xx (C) or 12:xx (D) local -- the retry path defers from
-- now(), which a contract cannot pin.
INSERT INTO public.users (id, phone, display_name, timezone) VALUES
  ('8c100000-0000-0000-0000-0000000000a1', '+233598200001', 'Quiet A', 'Africa/Accra'),
  ('8c100000-0000-0000-0000-0000000000b2', '+233598200002', 'Quiet B', 'America/New_York'),
  ('8c100000-0000-0000-0000-0000000000c3', '+233598200003', 'Quiet C', NULL),
  ('8c100000-0000-0000-0000-0000000000d4', '+233598200004', 'Quiet D', NULL),
  ('8c100000-0000-0000-0000-0000000000e5', '+233598200005', 'Quiet E', NULL)
ON CONFLICT (id) DO NOTHING;

-- An Etc/GMT zone in which the real now() is p_hour:xx local
-- (Etc/GMT-N is UTC+N; the range -11..+12 exists in tzdata).
CREATE FUNCTION pg_temp.zone_at(p_hour int) RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN n = 0 THEN 'Etc/GMT'
              WHEN n > 0 THEN 'Etc/GMT-' || n
              ELSE 'Etc/GMT+' || (-n) END
  FROM (SELECT CASE WHEN m > 12 THEN m - 24 ELSE m END AS n
        FROM (SELECT (((p_hour - extract(hour FROM now() AT TIME ZONE 'UTC')::int) % 24) + 24) % 24 AS m) a) b $$;
UPDATE public.users SET timezone = pg_temp.zone_at(23) WHERE id = '8c100000-0000-0000-0000-0000000000c3';
UPDATE public.users SET timezone = pg_temp.zone_at(12) WHERE id = '8c100000-0000-0000-0000-0000000000d4';

-- Queue one push as the server does; returns its id (NULL when collapsed).
CREATE FUNCTION pg_temp.push(p_user uuid, p_type text, p_at timestamptz,
  p_extra jsonb DEFAULT '{}'::jsonb, p_key text DEFAULT NULL, p_status text DEFAULT 'pending')
RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata, source_key)
  VALUES (p_user, 'immediate', p_at, p_status,
          jsonb_build_object('type', p_type, 'title', 'T', 'body', 'B',
                             'relationship_id', '8c200000-0000-0000-0000-000000000001') || p_extra,
          p_key)
  RETURNING id $$;
CREATE FUNCTION pg_temp.at(p_id uuid) RETURNS timestamptz LANGUAGE sql AS $$
  SELECT scheduled_for FROM public.scheduled_notifications WHERE id = p_id $$;

-- 0. The window, including its edges and a DST morning.
DO $$
BEGIN
  IF public.quiet_hours_release_at('2026-11-10 23:30+00', 'Africa/Accra') <> '2026-11-11 08:00+00'
     OR public.quiet_hours_release_at('2026-11-10 22:00+00', 'Africa/Accra') <> '2026-11-11 08:00+00'
     OR public.quiet_hours_release_at('2026-11-10 03:00+00', 'Africa/Accra') <> '2026-11-10 08:00+00'
     OR public.quiet_hours_release_at('2026-11-10 07:59+00', 'Africa/Accra') <> '2026-11-10 08:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a night send time is not released at 08:00 local';
  END IF;
  IF public.quiet_hours_release_at('2026-11-10 08:00+00', 'Africa/Accra') <> '2026-11-10 08:00+00'
     OR public.quiet_hours_release_at('2026-11-10 21:59+00', 'Africa/Accra') <> '2026-11-10 21:59+00'
     OR public.quiet_hours_release_at('2026-11-10 12:00+00', 'Africa/Accra') <> '2026-11-10 12:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a daytime send time moved';
  END IF;
  -- 22:30 EST on 10 Nov is 03:30Z on the 11th; 08:00 EST is 13:00Z.
  IF public.quiet_hours_release_at('2026-11-11 03:30+00', 'America/New_York') <> '2026-11-11 13:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the recipient''s own zone is not used';
  END IF;
  -- Spring forward (8 Mar 2026, 02:00 EST -> 03:00 EDT): 01:30 EST is
  -- 06:30Z; 08:00 EDT is 12:00Z.
  IF public.quiet_hours_release_at('2026-03-08 06:30+00', 'America/New_York') <> '2026-03-08 12:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the DST morning is not released at 08:00 local';
  END IF;
END $$;

-- 1. Every inserter is covered: a night push waits, a day push does not.
DO $$
DECLARE v_night uuid; v_day uuid;
BEGIN
  v_night := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'moment_logged', '2026-11-10 23:30+00');
  v_day := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'moment_logged', '2026-11-10 12:00+00');
  IF pg_temp.at(v_night) <> '2026-11-11 08:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 23:30 push was not deferred (%)', pg_temp.at(v_night);
  END IF;
  IF (SELECT metadata->>'quiet_deferred' FROM public.scheduled_notifications WHERE id = v_night) IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deferred push is not marked';
  END IF;
  IF pg_temp.at(v_day) <> '2026-11-10 12:00+00'
     OR (SELECT metadata ? 'quiet_deferred' FROM public.scheduled_notifications WHERE id = v_day) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a daytime push was touched';
  END IF;
  IF (SELECT status FROM public.scheduled_notifications WHERE id = v_night) <> 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deferred push is not pending (dropped?)';
  END IF;
END $$;

-- 2. Safety resources and short-notice plan alarms never wait (owner
--    decision D1); a day-ahead heads-up is still true at 08:00 and waits.
DO $$
DECLARE v_safe uuid; v_alarm uuid; v_far uuid;
BEGIN
  v_safe := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'safety_resources', '2026-11-10 23:30+00');
  v_alarm := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'together_event', '2026-11-10 23:30+00',
    '{}'::jsonb, 'together_alarm:8c-ev:2026-11-10:60:8c100000-0000-0000-0000-0000000000a1');
  v_far := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'together_event', '2026-11-10 23:30+00',
    '{}'::jsonb, 'together_alarm:8c-ev:2026-11-11:1440:8c100000-0000-0000-0000-0000000000a1');
  IF pg_temp.at(v_safe) <> '2026-11-10 23:30+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a safety push was held until morning';
  END IF;
  IF pg_temp.at(v_alarm) <> '2026-11-10 23:30+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a plan alarm was held until morning';
  END IF;
  IF pg_temp.at(v_far) <> '2026-11-11 08:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a day-ahead heads-up rang at night (%)', pg_temp.at(v_far);
  END IF;
END $$;

-- 3. The recipient's own zone decides.
DO $$
DECLARE v uuid;
BEGIN
  v := pg_temp.push('8c100000-0000-0000-0000-0000000000b2', 'moment_logged', '2026-11-11 03:30+00');
  IF pg_temp.at(v) <> '2026-11-11 13:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: New York 22:30 released at % (want 13:00Z)', pg_temp.at(v);
  END IF;
END $$;

-- 4. A retry or a stale-lease reset at night waits too; by day it doesn't.
DO $$
DECLARE v_c uuid; v_d uuid; v_tz text; v_before timestamptz := now() - interval '1 minute';
BEGIN
  v_c := pg_temp.push('8c100000-0000-0000-0000-0000000000c3', 'moment_logged', v_before, '{}'::jsonb, NULL, 'processing');
  v_d := pg_temp.push('8c100000-0000-0000-0000-0000000000d4', 'moment_logged', v_before, '{}'::jsonb, NULL, 'processing');
  IF pg_temp.at(v_c) <> v_before THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a processing row was moved on insert'; END IF;
  UPDATE public.scheduled_notifications SET status = 'pending', retry_count = 1 WHERE id IN (v_c, v_d);
  SELECT timezone INTO v_tz FROM public.users WHERE id = '8c100000-0000-0000-0000-0000000000c3';
  IF pg_temp.at(v_c) <= now() OR (pg_temp.at(v_c) AT TIME ZONE v_tz)::time <> time '08:00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a retry at 23:xx local goes out at % (zone %)', pg_temp.at(v_c), v_tz;
  END IF;
  IF pg_temp.at(v_d) <> v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a daytime retry was delayed';
  END IF;
  -- The worker's claim and finish (other statuses) pass straight through.
  UPDATE public.scheduled_notifications SET status = 'processing' WHERE id = v_d;
  UPDATE public.scheduled_notifications SET status = 'sent' WHERE id = v_d;
  IF pg_temp.at(v_d) <> v_before THEN RAISE EXCEPTION 'CONTRACT VIOLATED: claim/finish moved a row'; END IF;
END $$;

-- 5. Overnight chat: one push per conversation, sent at 08:00 (owner
--    decision D2). By day, nothing collapses.
DO $$
DECLARE v1 uuid; v2 uuid; v3 uuid; v_other uuid; v_n int; v_m jsonb;
BEGIN
  v1 := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'new_message', '2026-11-10 23:10+00');
  v2 := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'new_message', '2026-11-10 23:20+00');
  v3 := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'message_reaction', '2026-11-11 02:40+00');
  v_other := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'new_message', '2026-11-10 23:30+00',
                          '{"relationship_id":"8c200000-0000-0000-0000-000000000099"}'::jsonb);
  IF v1 IS NULL OR v2 IS NOT NULL OR v3 IS NOT NULL OR v_other IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: overnight chat did not collapse per conversation (% % % %)', v1, v2, v3, v_other;
  END IF;
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
   WHERE user_id = '8c100000-0000-0000-0000-0000000000a1' AND status = 'pending'
     AND metadata->>'type' IN ('new_message', 'message_reaction')
     AND metadata->>'relationship_id' = '8c200000-0000-0000-0000-000000000001';
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % overnight chat pushes for one conversation', v_n; END IF;
  SELECT metadata INTO v_m FROM public.scheduled_notifications WHERE id = v1;
  IF v_m->>'title' <> 'New messages in Attune' OR v_m->>'body' <> 'Open Attune to read them.'
     OR (v_m->>'quiet_count')::int <> 3 OR pg_temp.at(v1) <> '2026-11-11 08:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the collapsed push is wrong: % at %', v_m, pg_temp.at(v1);
  END IF;
  -- The collapse row is claimed at 08:00 while a late night message is
  -- still being queued: no duplicate-key error, a second neutral push.
  UPDATE public.scheduled_notifications SET status = 'processing' WHERE id = v1;
  v2 := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'new_message', '2026-11-11 07:59+00',
                     '{"body":"a preview"}'::jsonb);
  IF v2 IS NULL OR (SELECT source_key FROM public.scheduled_notifications WHERE id = v2) IS NOT NULL
     OR (SELECT metadata->>'body' FROM public.scheduled_notifications WHERE id = v2) <> 'Open Attune to read them.'
     OR pg_temp.at(v2) <> '2026-11-11 08:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a message after the collapse row was claimed was mishandled';
  END IF;
  -- By day each message is its own push.
  v1 := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'new_message', '2026-11-11 12:05+00');
  v2 := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'new_message', '2026-11-11 12:06+00');
  IF v1 IS NULL OR v2 IS NULL THEN RAISE EXCEPTION 'CONTRACT VIOLATED: daytime chat collapsed'; END IF;
END $$;

-- 6. "Today"/"Tomorrow" deferred across local midnight go neutral; within
--    the same local date they stand. Nothing is dropped.
DO $$
DECLARE v_late uuid; v_early uuid; v_cd uuid; v_m jsonb;
BEGIN
  v_late := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'reminder_upcoming', '2026-11-10 23:30+00',
                         '{"body":"Tomorrow"}'::jsonb);
  v_early := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'reminder_upcoming', '2026-11-10 03:00+00',
                          '{"body":"Tomorrow"}'::jsonb);
  v_cd := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'planning_entry', '2026-11-10 23:30+00',
                       '{"title":"Today''s the day","body":"B"}'::jsonb,
                       'planning_countdown:8c-test:8c100000-0000-0000-0000-0000000000a1:2026-11-10');
  IF (SELECT metadata->>'body' FROM public.scheduled_notifications WHERE id = v_late) <> 'Open Attune to see it.' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: "Tomorrow" arrives a day late unchanged';
  END IF;
  IF (SELECT metadata->>'body' FROM public.scheduled_notifications WHERE id = v_early) <> 'Tomorrow' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a same-day deferral changed correct copy';
  END IF;
  SELECT metadata INTO v_m FROM public.scheduled_notifications WHERE id = v_cd;
  IF v_m->>'title' <> 'Your plan' OR v_m->>'body' <> 'Open Attune to see it.' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deferred countdown still says today: %', v_m;
  END IF;
END $$;

-- 7. A user whose zone is unknown is never deferred: no guess, no 03:00
--    release (review C1).
DO $$
DECLARE v uuid;
BEGIN
  v := pg_temp.push('8c100000-0000-0000-0000-0000000000e5', 'moment_logged', '2026-11-10 23:30+00');
  IF pg_temp.at(v) <> '2026-11-10 23:30+00'
     OR (SELECT metadata ? 'quiet_deferred' FROM public.scheduled_notifications WHERE id = v) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a push for a user with no known zone was moved (to %)', pg_temp.at(v);
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'quiet_hours_contracts: all held'; END $$;
ROLLBACK;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `psql -q -d attune_spec1b -v ON_ERROR_STOP=1 -f supabase/tests/quiet_hours_contracts.sql 2>&1 | grep -m1 ERROR`
Expected: `ERROR:  function public.quiet_hours_release_at(unknown, unknown) does not exist`. That is the red state for a missing function; it is not a CONTRACT line, and the mutants in Step 5 provide the CONTRACT red evidence.

- [ ] **Step 3: Write the migration**

```sql
-- supabase/migrations/20261017170000_quiet_hours.sql
--
-- Engine-level quiet hours (Spec 1b; research 06 §3 F6 (1)). A queued push
-- whose send time falls in the recipient's local 22:00–08:00 moves to 08:00
-- local: deferred, never dropped. Exempt: safety resources (never wait) and
-- short-notice Together alarms (offset <= 120 min; at 08:00 "Starting now"
-- would be false -- owner decision D1, 2026-10-17). Overnight chat
-- collapses into one push per conversation at 08:00 (owner decision D2).
--
-- One BEFORE trigger covers every inserter -- SQL functions, triggers, edge
-- functions -- and every return to 'pending' (the worker's retry, the
-- stale-lease reset), so a retry at 23:00 waits too. Rows the worker claims
-- or finishes (other statuses) pass straight through. A user whose zone is
-- unknown is never deferred (no guessing).
--
-- A collapsed chat insert returns NULL from this trigger: the INSERT
-- succeeds with 0 rows, so `INSERT … RETURNING id INTO v` yields NULL and
-- GET DIAGNOSTICS ROW_COUNT is 0. Today's chat inserters (the outbox,
-- enqueuePush) do not read the row back; a future one must expect this.

CREATE OR REPLACE FUNCTION public.quiet_hours_release_at(p_at timestamptz, p_tz text)
RETURNS timestamptz LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT CASE
    WHEN (p_at AT TIME ZONE p_tz)::time >= time '22:00'
      THEN (((p_at AT TIME ZONE p_tz)::date + 1) + time '08:00') AT TIME ZONE p_tz
    WHEN (p_at AT TIME ZONE p_tz)::time < time '08:00'
      THEN ((p_at AT TIME ZONE p_tz)::date + time '08:00') AT TIME ZONE p_tz
    ELSE p_at
  END
$$;
REVOKE ALL ON FUNCTION public.quiet_hours_release_at(timestamptz, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.scheduled_notifications_quiet_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_meta jsonb := coalesce(NEW.metadata, '{}'::jsonb);
  v_type text := v_meta->>'type';
  v_base timestamptz;
  v_tz text;
  v_release timestamptz;
  v_key text;
  v_n int;
BEGIN
  IF NEW.status IS DISTINCT FROM 'pending'
     OR NEW.delivery_channel IS DISTINCT FROM 'push'
     OR v_type = 'safety_resources'
     -- Short-notice plan alarms ("Starting now", "In 1 hour"); the offset is
     -- the 4th key field (together_alarm:<event>:<date>:<offset>:<user>).
     -- Day-ahead heads-ups are still true at 08:00 and wait (review I1).
     OR (v_type = 'together_event'
         AND NEW.source_key ~ '^together_alarm:[^:]+:[^:]+:[0-9]+:'
         AND split_part(NEW.source_key, ':', 4)::int <= 120) THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' THEN
    -- Only a return to pending; an UPDATE of a row that was already pending
    -- (say, a status rewrite to the same value) is left alone.
    IF OLD.status = 'pending' THEN RETURN NEW; END IF;
    v_base := greatest(NEW.scheduled_for, now());
  ELSE
    v_base := coalesce(NEW.scheduled_for, now());
  END IF;

  v_tz := public.notification_recipient_tz(NEW.user_id);
  -- Unknown zone: no guess, no deferral (review C1). The user keeps today's
  -- behaviour until their app reports a zone.
  IF v_tz IS NULL THEN RETURN NEW; END IF;
  v_release := public.quiet_hours_release_at(v_base, v_tz);
  IF v_release <= v_base THEN RETURN NEW; END IF;

  NEW.scheduled_for := v_release;
  v_meta := v_meta || jsonb_build_object('quiet_deferred', true);

  -- "Today" / "Tomorrow" / "Today's the day" are false on the next local day.
  IF (v_release AT TIME ZONE v_tz)::date <> (v_base AT TIME ZONE v_tz)::date THEN
    IF v_type = 'reminder_upcoming' THEN
      v_meta := v_meta || jsonb_build_object('body', 'Open Attune to see it.');
    ELSIF v_type = 'planning_entry' AND NEW.source_key LIKE 'planning_countdown:%' THEN
      v_meta := v_meta || jsonb_build_object('title', 'Your plan', 'body', 'Open Attune to see it.');
    END IF;
  END IF;

  -- Overnight chat: one push per conversation at 08:00.
  IF TG_OP = 'INSERT' AND v_type IN ('new_message', 'message_reaction') THEN
    v_key := 'quiet_chat:' || NEW.user_id || ':' || coalesce(v_meta->>'relationship_id', '')
             || ':' || to_char(v_release AT TIME ZONE 'UTC', 'YYYYMMDDHH24MI');
    PERFORM pg_advisory_xact_lock(hashtext(v_key));
    UPDATE public.scheduled_notifications s
       SET metadata = s.metadata || jsonb_build_object(
             'type', 'new_message',
             'title', 'New messages in Attune',
             'body', 'Open Attune to read them.',
             'quiet_count', coalesce((s.metadata->>'quiet_count')::int, 1) + 1),
           updated_at = now()
     WHERE s.source_key = v_key AND s.status = 'pending';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n > 0 THEN RETURN NULL; END IF;
    IF EXISTS (SELECT 1 FROM public.scheduled_notifications s WHERE s.source_key = v_key) THEN
      -- The key's row already left 'pending' (claimed at 08:00, sent,
      -- failed): queue this one on its own, with the collapse copy so no
      -- preview rides along. Taking the key would hit the unique index and
      -- dead-letter the chat outbox job (review I4).
      NEW.source_key := NULL;
      v_meta := v_meta || jsonb_build_object(
        'type', 'new_message',
        'title', 'New messages in Attune',
        'body', 'Open Attune to read them.');
    ELSE
      NEW.source_key := v_key;
    END IF;
  END IF;

  NEW.metadata := v_meta;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.scheduled_notifications_quiet_guard() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS scheduled_notifications_quiet_guard ON public.scheduled_notifications;
CREATE TRIGGER scheduled_notifications_quiet_guard
  BEFORE INSERT OR UPDATE OF status ON public.scheduled_notifications
  FOR EACH ROW EXECUTE FUNCTION public.scheduled_notifications_quiet_guard();
```

- [ ] **Step 4: Rebuild and run**

```bash
ATTUNE_TEST_DB=attune_spec1b scripts/local_pg_setup.sh --no-tests 2>&1 | grep -E "FAILED|applied"
psql -q -d attune_spec1b -v ON_ERROR_STOP=1 -f supabase/tests/quiet_hours_contracts.sql 2>&1 | grep -E "ERROR|held"
for f in together_daily_contracts together_rituals_contracts together_phase0_contracts planning_couple_blocks_contracts reminder_lead_time_contracts games_contracts snakes_and_ladders_test chat_system_contracts; do psql -q -d attune_spec1b -v ON_ERROR_STOP=1 -f supabase/tests/$f.sql >/dev/null 2>"$WS/err.txt" && echo "PASS $f" || { echo "FAIL $f"; grep -m2 ERROR "$WS/err.txt"; }; done
```
Expected:
- `failed 0`.
- `NOTICE:  quiet_hours_contracts: all held`.
- Every neighbour `PASS`. They count rows and read copy, never `scheduled_for`, so a deferral cannot break them. If one fails, it is a real interaction: debug it, do not loosen it.

- [ ] **Step 5: Mutation-test**

```bash
"$WS/mutant.sh" "CREATE OR REPLACE FUNCTION public.quiet_hours_release_at(p_at timestamptz, p_tz text) RETURNS timestamptz LANGUAGE sql STABLE AS \$\$ SELECT p_at \$\$;" supabase/tests/quiet_hours_contracts.sql
"$WS/mutant.sh" "DROP TRIGGER scheduled_notifications_quiet_guard ON public.scheduled_notifications; CREATE TRIGGER scheduled_notifications_quiet_guard BEFORE INSERT ON public.scheduled_notifications FOR EACH ROW EXECUTE FUNCTION public.scheduled_notifications_quiet_guard();" supabase/tests/quiet_hours_contracts.sql
```
Expected:
- The first mutant prints `CONTRACT VIOLATED: a night send time is not released at 08:00 local`.
- The second (no UPDATE path) prints `CONTRACT VIOLATED: a retry at 23:xx local goes out at …`.
- Both print `MUTANT KILLED`.

- [ ] **Step 6: Ledger**

Append `Task 2: complete (quiet_hours_contracts green; 2 mutants KILLED; neighbours green). Regression risk: every push insert now runs the resolver (users PK, planning_member_settings_user_idx, partner_presence PK prefix) — a few index reads per insert.`

---

### Task 3: A read cancels the conversation's pending chat pushes

**Files:**
- Create: `supabase/migrations/20261017170100_quiet_chat_read_skip.sql`
- Create: `supabase/tests/quiet_chat_read_contracts.sql`

**Interfaces:**
- Consumes: `mark_conversation_read(uuid)` as last defined in `20261017130200_read_marks_watermark.sql` (Spec 1a), and the collapse key from Task 2.
- Produces: `mark_conversation_read` additionally sets the caller's own `pending` `new_message` / `message_reaction` rows for that relationship to `status = 'cancelled'` (the queue's word for a user-caused cancellation, as in `cancel_booking_notifications`), `source_key = NULL`, `last_error = 'read_before_send'`. Clearing `source_key` lets a later overnight message start a fresh collapse.

- [ ] **Step 1: Write the failing contract**

```sql
-- supabase/tests/quiet_chat_read_contracts.sql
-- A read before 08:00 cancels the overnight chat push (Spec 1b Task 3,
-- owner decision D2): mark_conversation_read cancels the reader's own pending
-- chat pushes for that conversation -- no one else's, no other
-- conversation's, no other kind -- and a later overnight message starts a
-- new one. Every check RAISEs.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('8d100000-0000-0000-0000-0000000000a1'),
  ('8d100000-0000-0000-0000-0000000000b2'),
  ('8d100000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name, timezone) VALUES
  ('8d100000-0000-0000-0000-0000000000a1', '+233598300001', 'Read A', 'Africa/Accra'),
  ('8d100000-0000-0000-0000-0000000000b2', '+233598300002', 'Read B', 'Africa/Accra'),
  ('8d100000-0000-0000-0000-0000000000c3', '+233598300003', 'Read C', 'Africa/Accra')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at) VALUES
  ('8d200000-0000-0000-0000-000000000001', '8d100000-0000-0000-0000-0000000000a1',
   '8d100000-0000-0000-0000-0000000000b2', 'active', CURRENT_DATE, now(), '2026-11-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;
CREATE FUNCTION pg_temp.push(p_user uuid, p_type text, p_at timestamptz, p_rel text)
RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata)
  VALUES (p_user, 'immediate', p_at, 'pending',
          jsonb_build_object('type', p_type, 'title', 'T', 'body', 'B', 'relationship_id', p_rel))
  RETURNING id $$;
CREATE FUNCTION pg_temp.status(p_id uuid) RETURNS text LANGUAGE sql AS $$
  SELECT status FROM public.scheduled_notifications WHERE id = p_id $$;

CREATE TEMP TABLE t_ids (name text PRIMARY KEY, id uuid) ON COMMIT DROP;

-- 1. Fixtures: A's overnight push for this conversation (collapsed key), A's
--    daytime push for it still pending, A's push for another conversation,
--    A's moment push, and B's own chat push.
DO $$
BEGIN
  INSERT INTO t_ids VALUES
    ('night', pg_temp.push('8d100000-0000-0000-0000-0000000000a1', 'new_message', '2026-11-10 23:10+00', '8d200000-0000-0000-0000-000000000001')),
    ('day',   pg_temp.push('8d100000-0000-0000-0000-0000000000a1', 'message_reaction', '2026-11-10 12:00+00', '8d200000-0000-0000-0000-000000000001')),
    ('other', pg_temp.push('8d100000-0000-0000-0000-0000000000a1', 'new_message', '2026-11-10 23:15+00', '8d200000-0000-0000-0000-000000000099')),
    ('moment', pg_temp.push('8d100000-0000-0000-0000-0000000000a1', 'moment_logged', '2026-11-10 23:20+00', '8d200000-0000-0000-0000-000000000001')),
    ('theirs', pg_temp.push('8d100000-0000-0000-0000-0000000000b2', 'new_message', '2026-11-10 23:25+00', '8d200000-0000-0000-0000-000000000001'));
  IF (SELECT source_key FROM public.scheduled_notifications WHERE id = (SELECT id FROM t_ids WHERE name = 'night')) NOT LIKE 'quiet_chat:%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: fixture -- the overnight push is not a collapse row (Task 2 missing?)';
  END IF;
END $$;

-- 2. A reads the conversation: both of A's pushes for it are cancelled,
--    nothing else is.
DO $$
DECLARE v_key text;
BEGIN
  PERFORM pg_temp.as_user('8d100000-0000-0000-0000-0000000000a1');
  PERFORM count(*) FROM public.mark_conversation_read('8d200000-0000-0000-0000-000000000001');
  RESET ROLE;
  IF pg_temp.status((SELECT id FROM t_ids WHERE name = 'night')) <> 'cancelled'
     OR pg_temp.status((SELECT id FROM t_ids WHERE name = 'day')) <> 'cancelled' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a push for a conversation already read is still pending';
  END IF;
  SELECT source_key INTO v_key FROM public.scheduled_notifications WHERE id = (SELECT id FROM t_ids WHERE name = 'night');
  IF v_key IS NOT NULL THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a cancelled collapse row keeps its key'; END IF;
  IF pg_temp.status((SELECT id FROM t_ids WHERE name = 'other')) <> 'pending'
     OR pg_temp.status((SELECT id FROM t_ids WHERE name = 'moment')) <> 'pending'
     OR pg_temp.status((SELECT id FROM t_ids WHERE name = 'theirs')) <> 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a read cancelled a push it does not cover';
  END IF;
END $$;

-- 3. A later overnight message starts a fresh collapse (no key clash).
DO $$
DECLARE v uuid;
BEGIN
  v := pg_temp.push('8d100000-0000-0000-0000-0000000000a1', 'new_message', '2026-11-10 23:50+00', '8d200000-0000-0000-0000-000000000001');
  IF v IS NULL OR pg_temp.status(v) <> 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a message after the read was not queued';
  END IF;
  INSERT INTO t_ids VALUES ('again', v);
END $$;

-- 4. An outsider's call cancels nothing.
DO $$
BEGIN
  PERFORM pg_temp.as_user('8d100000-0000-0000-0000-0000000000c3');
  PERFORM count(*) FROM public.mark_conversation_read('8d200000-0000-0000-0000-000000000001');
  RESET ROLE;
  IF pg_temp.status((SELECT id FROM t_ids WHERE name = 'again')) <> 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider cancelled a member''s push';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'quiet_chat_read_contracts: all held'; END $$;
ROLLBACK;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `psql -q -d attune_spec1b -v ON_ERROR_STOP=1 -f supabase/tests/quiet_chat_read_contracts.sql 2>&1 | grep -m1 ERROR`
Expected: `ERROR:  CONTRACT VIOLATED: a push for a conversation already read is still pending`.

- [ ] **Step 3: Write the migration**

The whole function is restated from `20261017130200_read_marks_watermark.sql`. The only changes are the dependency guard at the top of the file and the `UPDATE public.scheduled_notifications` block after the membership check.

```sql
-- supabase/migrations/20261017170100_quiet_chat_read_skip.sql
--
-- A read cancels the conversation's pending chat pushes (Spec 1b; owner
-- decision D2): the 08:00 "New messages" push must not arrive for a
-- conversation already read at 07:30. scheduled_notifications is not
-- published, so this is as silent as the read itself. The key is cleared so
-- a later overnight message starts a fresh collapse. Otherwise identical to
-- 20261017130200_read_marks_watermark.sql.
--
-- Hard dependency: Spec 1a (20261017120000..130200). Pushed alone, this
-- would stop db push half-way with quiet hours live and no cancel-on-read.
DO $$
BEGIN
  IF to_regclass('public.message_read_marks') IS NULL
     OR to_regprocedure('public.seen_receipts_effective(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Spec 1b 20261017170100 requires Spec 1a (20261017120000..130200)';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.mark_conversation_read(p_relationship_id uuid)
RETURNS TABLE (
  id uuid,
  delivered_at timestamptz,
  read_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_on boolean;
  v_floor timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM public.relationships r
    WHERE r.id = p_relationship_id
      AND r.chat_archived_at IS NULL
      AND (r.user_a = v_uid OR r.user_b = v_uid)
  ) THEN
    RETURN;
  END IF;

  -- Spec 1b: pushes about this conversation that have not gone out are moot.
  UPDATE public.scheduled_notifications s
     SET status = 'cancelled', source_key = NULL,
         last_error = 'read_before_send', updated_at = now()
   WHERE s.user_id = v_uid
     AND s.status = 'pending'
     AND s.metadata->>'type' IN ('new_message', 'message_reaction')
     AND s.metadata->>'relationship_id' = p_relationship_id::text;

  v_on := public.seen_receipts_effective(p_relationship_id);
  SELECT w.read_through - interval '10 minutes' INTO v_floor
  FROM public.message_read_marks w
  WHERE w.relationship_id = p_relationship_id AND w.reader_id = v_uid;
  v_floor := COALESCE(v_floor, '-infinity'::timestamptz);

  RETURN QUERY
  WITH marked (mid, rat) AS (
    -- The private marker. Never touches messages.
    INSERT INTO public.message_reads (message_id, reader_id)
    SELECT m.id, v_uid
    FROM public.messages m
    WHERE m.relationship_id = p_relationship_id
      AND m.created_at > v_floor
      AND m.sender_id <> v_uid
      AND m.read_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM public.message_reads x WHERE x.message_id = m.id)
    ON CONFLICT (message_id) DO NOTHING
    RETURNING message_reads.message_id, message_reads.read_at
  ),
  ticked (tid) AS (
    -- The sender-visible tick, only while on. With v_on false this UPDATE
    -- matches no row, so nothing is written and nothing streams.
    UPDATE public.messages m
    SET read_receipt_at = now(),
        delivered_at = COALESCE(m.delivered_at, now())
    FROM marked
    WHERE v_on AND m.id = marked.mid
    RETURNING m.id
  ),
  moved AS (
    -- Forward only; nothing marked, nothing written.
    INSERT INTO public.message_read_marks (relationship_id, reader_id, read_through)
    SELECT p_relationship_id, v_uid, max(m.created_at)
    FROM marked
    JOIN public.messages m ON m.id = marked.mid
    HAVING count(*) > 0
    ON CONFLICT (relationship_id, reader_id) DO UPDATE
      SET read_through = GREATEST(message_read_marks.read_through, EXCLUDED.read_through)
    RETURNING 1
  )
  SELECT marked.mid, m.delivered_at, marked.rat
  FROM marked
  JOIN public.messages m ON m.id = marked.mid
  LEFT JOIN ticked ON ticked.tid = marked.mid;
END;
$$;
```

Before writing, diff the restated body against the live one: `sed -n '/CREATE OR REPLACE FUNCTION public.mark_conversation_read/,/^\$\$;/p' supabase/migrations/20261017130200_read_marks_watermark.sql > "$WS/mcr-old.sql"`. Then extract the same range from the new file and `diff` the two. The only difference must be the added UPDATE block and its comment.

- [ ] **Step 4: Rebuild, run, neighbours, mutant**

```bash
ATTUNE_TEST_DB=attune_spec1b scripts/local_pg_setup.sh --no-tests 2>&1 | grep -E "FAILED|applied"
for f in quiet_chat_read_contracts read_watermark_contracts read_receipt_contracts chat_system_contracts chat_import_contracts seen_receipts_contracts quiet_hours_contracts; do psql -q -d attune_spec1b -v ON_ERROR_STOP=1 -f supabase/tests/$f.sql >/dev/null 2>"$WS/err.txt" && echo "PASS $f" || { echo "FAIL $f"; grep -m2 ERROR "$WS/err.txt"; }; done
"$WS/mutant.sh" "$(sed -n '/CREATE OR REPLACE FUNCTION public.mark_conversation_read/,/^\$\$;/p' supabase/migrations/20261017130200_read_marks_watermark.sql)" supabase/tests/quiet_chat_read_contracts.sql
```
Expected:
- All seven files `PASS`.
- The mutant (the Spec 1a function, which never cancels pushes) prints `CONTRACT VIOLATED: a push for a conversation already read is still pending` and `MUTANT KILLED`.

- [ ] **Step 5: Ledger**

Append `Task 3: complete (quiet_chat_read_contracts green; Spec 1a read contracts green; mutant KILLED). Regression risk: mark_conversation_read now writes scheduled_notifications (unpublished) — reads stay silent.`

---
### Task 4: Push copy without plan titles — copy guard, daily summary, date poll

**Files:**
- Create: `supabase/migrations/20261017180000_push_copy.sql`
- Create: `supabase/tests/push_copy_contracts.sql`
- Modify (assertions only): `supabase/tests/together_daily_contracts.sql`, `supabase/tests/planning_couple_blocks_contracts.sql`, `supabase/tests/together_phase0_contracts.sql`, `supabase/tests/together_proposals_contracts.sql`

**Interfaces:**
- Produces:
  - Trigger `scheduled_notifications_copy_guard` (BEFORE INSERT). It fires before the quiet guard, because `copy` < `quiet` in name order.
  - Field rules, by `metadata.type`:

    | type | field | becomes |
    |---|---|---|
    | `together_event` | title | "Your plan" |
    | `reminder_upcoming` | title | "Reminder" |
    | `together_proposal`, `together_handoff`, `together_handoff_reply` | body | "Open Attune to see it." |
    | `together_proposal_reply` | body | the decline note, when present and the recipient's `notification_settings.chat_message_preview_enabled` is true; otherwise "Open Attune to see it." |
    | `together_ritual`, `together_ritual_reply`, `moment_logged` | body | "Open Attune to see it." |
    | `planning_entry` with `source_key LIKE 'planning_countdown:%'` | body | "Open Attune to see it." |

  - `together_digest_lines(...)`: same signature; title-free lines (ruling R-E).
  - `planning_v2_notify_poll(...)`: same signature; body "{name} suggested dates".
- Consumes: `couple_events.title` (the decline-note prefix is `left(title, 60) || ': '`, `20261014120000_together_proposals.sql:137-140`).

- [ ] **Step 1: Write the failing contract**

```sql
-- supabase/tests/push_copy_contracts.sql
-- Push copy carries no plan titles (Spec 1b Task 4; research 06 §3 F8 (4)).
-- Each Together, reminder and moment generator runs on a plan whose title
-- holds the marker "Zq"; no queued push may contain it. A declined
-- proposal's note reaches the asker only when they show message previews.
-- Every check RAISEs.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('8e100000-0000-0000-0000-0000000000a1'),
  ('8e100000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('8e100000-0000-0000-0000-0000000000a1', '+233598400001', 'Ama'),
  ('8e100000-0000-0000-0000-0000000000b2', '+233598400002', 'Kofi')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('8e200000-0000-0000-0000-000000000001', '8e100000-0000-0000-0000-0000000000a1',
        '8e100000-0000-0000-0000-0000000000b2', 'active', now(), now())
ON CONFLICT (id) DO NOTHING;
CREATE TEMP TABLE t_ids (name text PRIMARY KEY, id uuid) ON COMMIT DROP;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;
CREATE FUNCTION pg_temp.meta_for_event(p_user uuid, p_type text, p_event uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT metadata FROM public.scheduled_notifications
  WHERE user_id = p_user AND metadata->>'type' = p_type AND metadata->>'event_id' = p_event::text $$;
CREATE FUNCTION pg_temp.meta_of_type(p_user uuid, p_type text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT metadata FROM public.scheduled_notifications
  WHERE user_id = p_user AND metadata->>'type' = p_type $$;

-- 1. An alarm on a plan: "Your plan · In 1 hour".
DO $$
DECLARE v_id uuid; v_m jsonb;
BEGIN
  PERFORM pg_temp.as_user('8e100000-0000-0000-0000-0000000000a1');
  v_id := public.create_couple_event('8e200000-0000-0000-0000-000000000001',
    '{"title":"Zq clinic visit","all_day":false,"starts_at":"2026-11-20T19:00:00Z","tz":"UTC","remind_offsets_min":[60],"participant_ids":["8e100000-0000-0000-0000-0000000000a1","8e100000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM public.together_enqueue_event_alarms('2026-11-20T18:05:00Z');
  v_m := pg_temp.meta_for_event('8e100000-0000-0000-0000-0000000000b2', 'together_event', v_id);
  IF v_m IS NULL THEN RAISE EXCEPTION 'CONTRACT VIOLATED: fixture -- no alarm was queued'; END IF;
  IF v_m->>'title' <> 'Your plan' OR v_m->>'body' <> 'In 1 hour' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: alarm copy %', v_m;
  END IF;
END $$;

-- 2. A proposal, then a decline with a note while the asker's previews are
--    off: neither the title nor the note reaches the lock screen.
DO $$
DECLARE v_id uuid; v_m jsonb;
BEGIN
  PERFORM pg_temp.as_user('8e100000-0000-0000-0000-0000000000a1');
  v_id := public.propose_couple_event('8e200000-0000-0000-0000-000000000001',
    '{"title":"Zq weekend away","all_day":true,"participant_ids":["8e100000-0000-0000-0000-0000000000a1","8e100000-0000-0000-0000-0000000000b2"]}'::jsonb,
    '[{"start_date":"2026-11-28"}]'::jsonb);
  v_m := pg_temp.meta_for_event('8e100000-0000-0000-0000-0000000000b2', 'together_proposal', v_id);
  IF v_m->>'body' <> 'Open Attune to see it.' OR v_m->>'title' <> 'Ama suggested a plan' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: proposal copy %', v_m;
  END IF;
  PERFORM pg_temp.as_user('8e100000-0000-0000-0000-0000000000b2');
  PERFORM public.decide_couple_event(v_id, NULL, false, 'Zq not that weekend');
  v_m := pg_temp.meta_for_event('8e100000-0000-0000-0000-0000000000a1', 'together_proposal_reply', v_id);
  IF v_m->>'body' <> 'Open Attune to see it.' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a decline note reached a lock screen with previews off: %', v_m;
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 3. With previews on, the note arrives -- without the plan's title.
DO $$
DECLARE v_id uuid; v_m jsonb;
BEGIN
  INSERT INTO public.notification_settings (user_id, chat_message_preview_enabled)
  VALUES ('8e100000-0000-0000-0000-0000000000a1', true)
  ON CONFLICT (user_id) DO UPDATE SET chat_message_preview_enabled = true;
  PERFORM pg_temp.as_user('8e100000-0000-0000-0000-0000000000a1');
  v_id := public.propose_couple_event('8e200000-0000-0000-0000-000000000001',
    '{"title":"Zq second try","all_day":true,"participant_ids":["8e100000-0000-0000-0000-0000000000a1","8e100000-0000-0000-0000-0000000000b2"]}'::jsonb,
    '[{"start_date":"2026-12-05"}]'::jsonb);
  PERFORM pg_temp.as_user('8e100000-0000-0000-0000-0000000000b2');
  PERFORM public.decide_couple_event(v_id, NULL, false, 'Sunday instead?');
  v_m := pg_temp.meta_for_event('8e100000-0000-0000-0000-0000000000a1', 'together_proposal_reply', v_id);
  IF v_m->>'body' <> 'Sunday instead?' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with previews on the note should arrive alone: %', v_m;
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 4. A hand-off, and a ritual proposed and accepted.
DO $$
DECLARE v_ev uuid; v_rit uuid; v_m jsonb;
BEGIN
  PERFORM pg_temp.as_user('8e100000-0000-0000-0000-0000000000a1');
  v_ev := public.create_couple_event('8e200000-0000-0000-0000-000000000001',
    '{"title":"Zq dentist","all_day":true,"start_date":"2026-11-12","participant_ids":["8e100000-0000-0000-0000-0000000000a1","8e100000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM public.propose_owner_handoff(v_ev);
  v_rit := public.propose_ritual('8e200000-0000-0000-0000-000000000001',
    '{"template":"date_night","title":"Zq ritual","cadence":"weekly","weekday":5,"local_time":"19:00","duration_min":120,"tz":"Africa/Accra"}'::jsonb);
  PERFORM pg_temp.as_user('8e100000-0000-0000-0000-0000000000b2');
  PERFORM public.decide_ritual(v_rit, true);
  PERFORM set_config('request.jwt.claims', '', true);
  v_m := pg_temp.meta_for_event('8e100000-0000-0000-0000-0000000000b2', 'together_handoff', v_ev);
  IF v_m->>'body' <> 'Open Attune to see it.' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: hand-off copy %', v_m; END IF;
  v_m := pg_temp.meta_of_type('8e100000-0000-0000-0000-0000000000b2', 'together_ritual');
  IF v_m->>'body' <> 'Open Attune to see it.' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: ritual copy %', v_m; END IF;
  v_m := pg_temp.meta_of_type('8e100000-0000-0000-0000-0000000000a1', 'together_ritual_reply');
  IF v_m->>'body' <> 'Open Attune to see it.' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: ritual reply copy %', v_m; END IF;
END $$;

-- 5. A reminder ("Reminder · Today") and a moment ("Ama added a moment").
DO $$
DECLARE v_m jsonb;
BEGIN
  INSERT INTO public.reminders (id, relationship_id, created_by, reminder_type, title, remind_at, recurrence)
  VALUES ('8e500000-0000-0000-0000-000000000001', '8e200000-0000-0000-0000-000000000001',
          '8e100000-0000-0000-0000-0000000000a1', 'birthday', 'Zq birthday', '2020-11-21', 'yearly');
  PERFORM public.generate_reminder_notifications('2026-11-21T09:05:00Z');
  SELECT metadata INTO v_m FROM public.scheduled_notifications
   WHERE user_id = '8e100000-0000-0000-0000-0000000000a1' AND metadata->>'reminder_id' = '8e500000-0000-0000-0000-000000000001';
  IF v_m IS NULL OR v_m->>'title' <> 'Reminder' OR v_m->>'body' <> 'Today' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: reminder copy %', v_m;
  END IF;
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
  VALUES ('8e200000-0000-0000-0000-000000000001', '8e100000-0000-0000-0000-0000000000a1', 'highlight', 'Zq beach', current_date);
  v_m := pg_temp.meta_of_type('8e100000-0000-0000-0000-0000000000b2', 'moment_logged');
  IF v_m->>'title' <> 'Ama added a moment' OR v_m->>'body' <> 'Open Attune to see it.' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: moment copy %', v_m;
  END IF;
END $$;

-- 6. A countdown row is neutralised; a poll row (whose generator writes no
--    title) and a game push are untouched.
DO $$
DECLARE v_m jsonb;
BEGIN
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata, source_key) VALUES
    ('8e100000-0000-0000-0000-0000000000a1', 'immediate', '2026-11-19 12:00+00', 'pending',
     '{"type":"planning_entry","title":"Today''s the day","body":"Zq trip"}'::jsonb,
     'planning_countdown:8e-test:8e100000-0000-0000-0000-0000000000a1:2026-11-19'),
    ('8e100000-0000-0000-0000-0000000000a1', 'immediate', '2026-11-19 12:00+00', 'pending',
     '{"type":"planning_entry","title":"New dates to vote on","body":"Kofi suggested dates"}'::jsonb,
     'planning_poll:8e-test:8e100000-0000-0000-0000-0000000000a1:2026111912'),
    ('8e100000-0000-0000-0000-0000000000a1', 'immediate', '2026-11-19 12:00+00', 'pending',
     '{"type":"game_invite","title":"Kofi invited you","body":"Mirror — your turn to play."}'::jsonb, NULL);
  SELECT metadata INTO v_m FROM public.scheduled_notifications WHERE source_key LIKE 'planning_countdown:8e-test:%';
  IF v_m->>'title' <> 'Today''s the day' OR v_m->>'body' <> 'Open Attune to see it.' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: countdown copy %', v_m;
  END IF;
  IF (SELECT metadata->>'body' FROM public.scheduled_notifications WHERE source_key LIKE 'planning_poll:8e-test:%') <> 'Kofi suggested dates'
     OR NOT EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE metadata->>'body' = 'Mirror — your turn to play.') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the guard rewrote a push it does not cover';
  END IF;
END $$;

-- 7. The sweep: no queued push anywhere carries a "Zq" title.
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
   WHERE user_id IN ('8e100000-0000-0000-0000-0000000000a1', '8e100000-0000-0000-0000-0000000000b2')
     AND metadata::text LIKE '%Zq%';
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % queued pushes carry a plan title', v_n; END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'push_copy_contracts: all held'; END $$;
ROLLBACK;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `psql -q -d attune_spec1b -v ON_ERROR_STOP=1 -f supabase/tests/push_copy_contracts.sql 2>&1 | grep -m1 ERROR`
Expected: `ERROR:  CONTRACT VIOLATED: alarm copy {…"title": "Zq clinic visit"…}`.

If an RPC rejects a fixture payload (`together:invalid_input`), compare the fixture with the existing contract that calls the same RPC (`together_daily_contracts.sql` for `create_couple_event`, `together_proposals_contracts.sql` for `propose_couple_event`, `together_rituals_contracts.sql` for `propose_ritual`). Fix the fixture only, and record the ruling.

- [ ] **Step 3: Update the four existing contracts to the new copy (they go red)**

Snapshot all four first: `for f in together_daily_contracts planning_couple_blocks_contracts together_phase0_contracts together_proposals_contracts; do cp supabase/tests/$f.sql "$WS/snapshots/$f.sql"; done`.

(a) `together_daily_contracts.sql`.

Block 1: replace
```sql
  IF v_body NOT LIKE '%19:00 Dinner at Buka%' OR v_body NOT LIKE '%Kofi''s big day: Interview at 10:00%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: summary body %', v_body;
  END IF;
```
with
```sql
  -- Spec 1b (ruling R-E): counts, times and nudges -- never titles.
  IF v_body IS DISTINCT FROM '1 plan today at 19:00 · Kofi''s big day at 10:00 — a word of luck?' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: summary body %', v_body;
  END IF;
```
Block 3: replace
```sql
  IF v_body IS NULL OR v_body NOT LIKE '%Cinema%' OR v_body LIKE '%big day%' THEN
```
with
```sql
  IF v_body IS DISTINCT FROM '1 plan today' THEN
```
Block 4: replace
```sql
  IF v_title <> 'Your week together' OR v_body NOT LIKE '%Tue%Dinner at Buka%' THEN
```
with
```sql
  IF v_title <> 'Your week together' OR v_body IS DISTINCT FROM '2 plans this week, first Tue 19:00' THEN
```
Block 5: replace
```sql
  IF v_tue LIKE '%Call%' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: London Tuesday shows a Wednesday 02:00 call: %', v_tue; END IF;
  IF v_wed IS NULL OR v_wed NOT LIKE '%02:00 Call%' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: London Wednesday summary %', v_wed; END IF;
```
with
```sql
  IF v_tue IS NOT NULL THEN RAISE EXCEPTION 'CONTRACT VIOLATED: London Tuesday shows a Wednesday 02:00 call: %', v_tue; END IF;
  IF v_wed IS DISTINCT FROM '1 plan today at 02:00' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: London Wednesday summary %', v_wed; END IF;
```
and, directly before the file's closing `ROLLBACK;`, add:
```sql
-- 6. Spec 1b: no summary anywhere carries a plan title.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.scheduled_notifications
             WHERE metadata->>'type' = 'together_daily'
               AND metadata->>'body' ~ '(Dinner|Interview|Therapy|Ring|Exam|Cinema|Call|Viva)') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a daily summary carries a plan title';
  END IF;
END $$;
```
(b) `planning_couple_blocks_contracts.sql`: replace `OR v_r ->> 'body' <> 'Ama suggested dates for Bali' THEN` with `OR v_r ->> 'body' <> 'Ama suggested dates' THEN`. Directly after the countdown assertion `IF v_n <> 1 OR v_i <> 1 THEN RAISE EXCEPTION 'EXPLOIT: countdown pushes wrong later (Ama %, Kofi %)', v_n, v_i; END IF;`, add:
```sql
  -- Spec 1b: a countdown push never carries the plan's title.
  IF EXISTS (SELECT 1 FROM public.scheduled_notifications
             WHERE source_key LIKE 'planning_countdown:' || v_cd || ':%' AND metadata::text LIKE '%Bali%') THEN
    RAISE EXCEPTION 'EXPLOIT: countdown push carries the plan title';
  END IF;
```
(c) `together_phase0_contracts.sql`: replace `    AND metadata->>'body' = 'Beach day';` with `    AND metadata->>'body' = 'Open Attune to see it.';`.

(d) `together_proposals_contracts.sql` (pre-existing failure: fixture phone collision; updated so it states the new rule). Directly before `  PERFORM public.decide_couple_event(v_id, NULL, false, 'Sunday instead?');`, add:
```sql
  -- Spec 1b (ruling R-D): the note reaches the asker only with previews on.
  INSERT INTO public.notification_settings (user_id, chat_message_preview_enabled)
  VALUES ('7c000000-0000-0000-0000-0000000000a1', true)
  ON CONFLICT (user_id) DO UPDATE SET chat_message_preview_enabled = true;
```
and replace `  IF v_body NOT LIKE '%Sunday instead?%' THEN` with `  IF v_body IS DISTINCT FROM 'Sunday instead?' THEN`.

Run:
```bash
for f in together_daily_contracts planning_couple_blocks_contracts together_phase0_contracts; do psql -q -d attune_spec1b -v ON_ERROR_STOP=1 -f supabase/tests/$f.sql >/dev/null 2>"$WS/err.txt" && echo "PASS $f" || { echo "FAIL $f"; grep -m1 ERROR "$WS/err.txt"; }; done
```
Expected: all three FAIL on their updated assertions: `summary body 19:00 Dinner at Buka · …`, `poll push wrong`, and `expected 1 partner push, got 0`.

- [ ] **Step 4: Write the migration**

```sql
-- supabase/migrations/20261017180000_push_copy.sql
--
-- Push copy carries no plan titles (Spec 1b; research 06 §3 F8 (4): "no
-- event titles that could out an intimate plan"). A lock screen is read by
-- whoever holds the phone.
--
-- (1) A copy guard on the queue rewrites the fields that ARE a plan's title,
--     by push type, for every present and future inserter. It runs before
--     scheduled_notifications_quiet_guard (BEFORE triggers fire in name
--     order). Names stay in titles ("Ama suggested a plan"); body copy is
--     neutral.
-- (2) A declined proposal's note is the partner's own words, like a chat
--     preview: it reaches the lock screen only when the recipient shows
--     message previews (chat_message_preview_enabled, default off), and
--     then without the plan's title.
-- (3) The daily summary and the date poll wove a title into a sentence;
--     both generators are restated without it.

CREATE OR REPLACE FUNCTION public.scheduled_notifications_copy_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_meta jsonb := coalesce(NEW.metadata, '{}'::jsonb);
  v_type text := v_meta->>'type';
  v_neutral constant text := 'Open Attune to see it.';
  v_title text;
  v_prefix text;
  v_note text;
  v_preview boolean;
BEGIN
  IF v_type = 'together_event' THEN
    v_meta := v_meta || jsonb_build_object('title', 'Your plan');
  ELSIF v_type = 'reminder_upcoming' THEN
    v_meta := v_meta || jsonb_build_object('title', 'Reminder');
  ELSIF v_type IN ('together_proposal', 'together_handoff', 'together_handoff_reply') THEN
    v_meta := v_meta || jsonb_build_object('body', v_neutral);
  ELSIF v_type = 'together_proposal_reply' THEN
    -- The body is the title, or (a decline with a note) left(title, 60),
    -- ': ' and the note (decide_couple_event).
    IF v_meta ? 'event_id' THEN
      SELECT ce.title INTO v_title FROM public.couple_events ce
       WHERE ce.id = (v_meta->>'event_id')::uuid;
      v_prefix := left(v_title, 60) || ': ';
      IF v_title IS NOT NULL
         AND left(v_meta->>'body', char_length(v_prefix)) = v_prefix THEN
        v_note := nullif(btrim(substr(v_meta->>'body', char_length(v_prefix) + 1)), '');
      END IF;
    END IF;
    SELECT ns.chat_message_preview_enabled INTO v_preview
      FROM public.notification_settings ns WHERE ns.user_id = NEW.user_id;
    v_meta := v_meta || jsonb_build_object('body',
      CASE WHEN v_note IS NOT NULL AND coalesce(v_preview, false) THEN v_note ELSE v_neutral END);
  ELSIF v_type IN ('together_ritual', 'together_ritual_reply', 'moment_logged') THEN
    v_meta := v_meta || jsonb_build_object('body', v_neutral);
  ELSIF v_type = 'planning_entry' AND NEW.source_key LIKE 'planning_countdown:%' THEN
    v_meta := v_meta || jsonb_build_object('body', v_neutral);
  END IF;
  NEW.metadata := v_meta;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.scheduled_notifications_copy_guard() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS scheduled_notifications_copy_guard ON public.scheduled_notifications;
CREATE TRIGGER scheduled_notifications_copy_guard
  BEFORE INSERT ON public.scheduled_notifications
  FOR EACH ROW EXECUTE FUNCTION public.scheduled_notifications_copy_guard();

-- The daily summary (20261014130000): the same candidates, placement and
-- visibility rules, said without titles. One summary line ("2 plans today,
-- first at 19:00" / "3 plans this week, first Tue 19:00"), then the
-- partner's big days ("Kofi's big day at 10:00 — a word of luck?"), then the
-- waiting suggestion. together_enqueue_daily still joins the first three.
CREATE OR REPLACE FUNCTION public.together_digest_lines(
  p_relationship_id uuid, p_user uuid, p_from date, p_to date, p_tz text,
  p_care boolean, p_week boolean
) RETURNS text[] LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH cand AS (
    SELECT ce.*, d.d AS ev_day,
      CASE WHEN ce.all_day THEN NULL
           WHEN ce.rrule IS NULL THEN ce.starts_at
           ELSE ((d.d + (ce.starts_at AT TIME ZONE ce.tz)::time) AT TIME ZONE ce.tz) END AS at
    FROM public.couple_events ce
    CROSS JOIN LATERAL public.together_event_dates(ce, p_from - 1, p_to + 1) AS d(d)
    WHERE ce.relationship_id = p_relationship_id AND ce.deleted_at IS NULL
      AND ce.status = 'confirmed'
      AND (ce.rrule IS NOT NULL
           OR (ce.all_day AND d.d = greatest(p_from, ce.start_date))
           OR (NOT ce.all_day AND d.d = (ce.starts_at AT TIME ZONE ce.tz)::date))
  ), occ AS (
    SELECT cand.*,
      CASE WHEN at IS NULL THEN ev_day ELSE (at AT TIME ZONE p_tz)::date END AS on_day
    FROM cand
  ), placed AS (
    SELECT * FROM occ WHERE on_day BETWEEN p_from AND p_to
  ), mine AS (
    SELECT on_day, at FROM placed
    WHERE p_user = ANY (participant_ids) AND (visibility = 'shared' OR created_by = p_user)
  ), summary AS (
    SELECT p_from AS on_day, NULL::timestamptz AS at, 0 AS ord,
      s.n || CASE WHEN s.n = 1 THEN ' plan' ELSE ' plans' END
          || CASE WHEN p_week THEN ' this week' ELSE ' today' END
          || CASE
               WHEN p_week THEN CASE WHEN s.n = 1 THEN ': ' ELSE ', first ' END
                    || to_char(s.f_day, 'Dy')
                    || coalesce(' ' || to_char(s.f_at AT TIME ZONE p_tz, 'HH24:MI'), '')
               WHEN s.f_at IS NULL THEN ''
               ELSE CASE WHEN s.n = 1 THEN ' at ' ELSE ', first at ' END
                    || to_char(s.f_at AT TIME ZONE p_tz, 'HH24:MI')
             END AS line
    FROM (SELECT count(*) AS n,
                 (array_agg(on_day ORDER BY on_day, at NULLS FIRST))[1] AS f_day,
                 (array_agg(at ORDER BY on_day, at NULLS FIRST))[1] AS f_at
          FROM mine) s
    WHERE s.n > 0
  ), big AS (
    SELECT on_day, at, 1 AS ord,
      CASE WHEN p_week THEN to_char(on_day, 'Dy') || ': ' ELSE '' END
      || public.together_name(created_by) || '''s big day'
      || CASE WHEN at IS NULL THEN '' ELSE ' at ' || to_char(at AT TIME ZONE p_tz, 'HH24:MI') END
      || ' — a word of luck?' AS line
    FROM placed
    WHERE p_care AND kind = 'big_day' AND visibility = 'shared'
      AND created_by <> p_user AND NOT (p_user = ANY (participant_ids))
  ), sugg AS (
    SELECT p_from AS on_day, NULL::timestamptz AS at, 2 AS ord, 'A suggestion is waiting for you'::text AS line
    WHERE NOT p_week AND EXISTS (
      SELECT 1 FROM public.couple_events ce
      WHERE ce.relationship_id = p_relationship_id AND ce.deleted_at IS NULL
        AND ce.status = 'proposed' AND ce.proposed_to = p_user AND ce.proposal_expires_at > now())
  ), lines AS (
    SELECT on_day, at, ord, line FROM summary
    UNION ALL SELECT on_day, at, ord, line FROM big
    UNION ALL SELECT on_day, at, ord, line FROM sugg
  )
  SELECT coalesce(array_agg(line ORDER BY ord, on_day, at NULLS FIRST, line), '{}') FROM lines
$$;
REVOKE ALL ON FUNCTION public.together_digest_lines(uuid, uuid, date, date, text, boolean, boolean) FROM PUBLIC, anon, authenticated;

-- The date poll (20261012200900): "Ama suggested dates", not "… for Bali".
CREATE OR REPLACE FUNCTION public.planning_v2_notify_poll(p_block public.planning_blocks, p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_entry public.planning_entries; v_partner uuid; v_name text;
BEGIN
  SELECT * INTO v_entry FROM public.planning_entries WHERE id = p_block.entry_id;
  IF v_entry.is_template OR p_actor IS NULL THEN RETURN; END IF;
  SELECT CASE WHEN r.user_a = p_actor THEN r.user_b ELSE r.user_a END INTO v_partner
  FROM public.relationships r WHERE r.id = p_block.relationship_id;
  SELECT coalesce(nullif(btrim(display_name), ''), 'Your partner') INTO v_name FROM public.users WHERE id = p_actor;
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata, source_key)
  VALUES (v_partner, 'immediate', now(), 'pending',
          jsonb_build_object('type', 'planning_entry', 'relationship_id', p_block.relationship_id,
            'entry_id', p_block.entry_id, 'title', 'New dates to vote on',
            'body', left(coalesce(v_name, 'Your partner') || ' suggested dates', 160)),
          'planning_poll:' || p_block.id || ':' || v_partner || ':'
            || to_char(date_trunc('hour', clock_timestamp() AT TIME ZONE 'UTC'), 'YYYYMMDDHH24'))
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_notify_poll(public.planning_blocks, uuid) FROM PUBLIC, anon, authenticated;
```

Before writing, diff the two restated functions against their originals:
- `together_digest_lines`: from `20261014130000_together_daily.sql:43-91`. The `cand`/`occ`/`placed` CTEs and the visibility predicates must be identical; only `lines` changes shape.
- `planning_v2_notify_poll`: from `20261012200900_planning_couple_blocks.sql:406-424`. Only the `'body'` expression changes.

- [ ] **Step 5: Rebuild and run**

```bash
ATTUNE_TEST_DB=attune_spec1b scripts/local_pg_setup.sh --no-tests 2>&1 | grep -E "FAILED|applied"
for f in push_copy_contracts together_daily_contracts planning_couple_blocks_contracts together_phase0_contracts together_rituals_contracts reminder_lead_time_contracts quiet_hours_contracts quiet_chat_read_contracts games_contracts snakes_and_ladders_test; do psql -q -d attune_spec1b -v ON_ERROR_STOP=1 -f supabase/tests/$f.sql >/dev/null 2>"$WS/err.txt" && echo "PASS $f" || { echo "FAIL $f"; grep -m2 ERROR "$WS/err.txt"; }; done
for f in together_daily_contracts planning_couple_blocks_contracts together_phase0_contracts together_proposals_contracts; do echo "== $f"; diff -u "$WS/snapshots/$f.sql" supabase/tests/$f.sql | grep -E '^[-+][^-+]'; done
```
Expected: every file `PASS`, and each diff shows only the Step 3 lines.

- [ ] **Step 6: Mutation-test**

```bash
"$WS/mutant.sh" "DROP TRIGGER scheduled_notifications_copy_guard ON public.scheduled_notifications;" supabase/tests/push_copy_contracts.sql
"$WS/mutant.sh" "CREATE OR REPLACE FUNCTION public.scheduled_notifications_copy_guard() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN IF NEW.metadata->>'type' = 'together_proposal_reply' THEN RETURN NEW; END IF; NEW.metadata := NEW.metadata || CASE WHEN NEW.metadata->>'type' = 'together_event' THEN '{\"title\":\"Your plan\"}'::jsonb WHEN NEW.metadata->>'type' = 'reminder_upcoming' THEN '{\"title\":\"Reminder\"}'::jsonb WHEN NEW.metadata->>'type' IN ('together_proposal','together_handoff','together_handoff_reply','together_ritual','together_ritual_reply','moment_logged') OR NEW.source_key LIKE 'planning_countdown:%' THEN '{\"body\":\"Open Attune to see it.\"}'::jsonb ELSE '{}'::jsonb END; RETURN NEW; END \$\$;" supabase/tests/push_copy_contracts.sql
```
Expected:
- The first mutant prints `CONTRACT VIOLATED: alarm copy …`.
- The second (replies untouched) prints `CONTRACT VIOLATED: a decline note reached a lock screen with previews off`.
- Both print `MUTANT KILLED`.

- [ ] **Step 7: Ledger**

Append `Task 4: complete (push_copy_contracts green; daily/planning/phase0 updated and green; proposals updated (pre-existing collision); 2 mutants KILLED). Regression risk: the daily summary's wording changes for every couple (ruling R-E); decline notes need previews on (R-D).`

---
### Task 5: Every push goes through the queue

**Files:**
- Create: `supabase/functions/_shared/push_queue.ts`
- Create: `supabase/functions/_shared/push_queue.test.ts`
- Create: `supabase/functions/_shared/push_transport.test.ts`
- Modify: `supabase/functions/accept-invite/index.ts`, `supabase/functions/end-relationship/index.ts`, `supabase/functions/activate-topics/index.ts`, `supabase/functions/send-notification/index.ts`

**Interfaces:**
- Produces: `enqueuePush(supabase, { userId, type, title, body, data?, sourceKey? }): Promise<void>`.
  - Inserts one `pending`, `immediate` row into `scheduled_notifications` with `metadata = { ...data, type, title, body }` (the explicit fields win).
  - A unique-violation (`23505`) on a given `sourceKey` is "already queued" and returns. Any other error throws `enqueue_push_failed:<code>`.
- Consumes: the worker's `privacySafeData` allowlist (`process-scheduled-notifications/index.ts:80-107`) already carries `relationship_id`, `topic_id`, `journey_id`, `session_id`, `chapter`. Tap routing reads `data.type` only (`lib/core/notifications/config/notification_config.dart`), so the dropped `screen` keys are not needed.

- [ ] **Step 1: Write the failing Deno tests**

```ts
// supabase/functions/_shared/push_queue.test.ts
import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { enqueuePush } from "./push_queue.ts";

function fakeClient(error: { code?: string } | null = null) {
  const rows: Record<string, unknown>[] = [];
  return {
    rows,
    from(table: string) {
      return {
        insert(row: Record<string, unknown>) {
          rows.push({ table, ...row });
          return Promise.resolve({ error });
        },
      };
    },
  };
}

const push = { userId: "u1", type: "invite_accepted", title: "T", body: "B" };

Deno.test("enqueuePush queues one pending, immediate push; explicit fields win over data", async () => {
  const c = fakeClient();
  await enqueuePush(c, { ...push, data: { relationship_id: "r1", type: "spoof", title: "spoof" }, sourceKey: "k1" });
  assertEquals(c.rows.length, 1);
  const row = c.rows[0];
  assertEquals(row.table, "scheduled_notifications");
  assertEquals(row.user_id, "u1");
  assertEquals(row.status, "pending");
  assertEquals(row.notification_type, "immediate");
  assertEquals(row.source_key, "k1");
  assertEquals(row.metadata, { relationship_id: "r1", type: "invite_accepted", title: "T", body: "B" });
});

Deno.test("enqueuePush without a key leaves source_key null", async () => {
  const c = fakeClient();
  await enqueuePush(c, push);
  assertEquals(c.rows[0].source_key, null);
});

Deno.test("a duplicate key means already queued: no throw", async () => {
  await enqueuePush(fakeClient({ code: "23505" }), { ...push, sourceKey: "k1" });
});

Deno.test("a duplicate without a key, or any other error, throws", async () => {
  await assertRejects(() => enqueuePush(fakeClient({ code: "23505" }), push), Error, "enqueue_push_failed:23505");
  await assertRejects(() => enqueuePush(fakeClient({ code: "42501" }), { ...push, sourceKey: "k1" }), Error, "enqueue_push_failed:42501");
});
```

```ts
// supabase/functions/_shared/push_transport.test.ts
// Spec 1b: the worker (process-scheduled-notifications) is the only OneSignal
// caller, so quiet hours and the no-titles copy guard -- both triggers on
// scheduled_notifications -- cover every push. A function that wants to
// notify someone calls enqueuePush.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

const root = new URL("../", import.meta.url);

async function* sources(dir: URL): AsyncGenerator<URL> {
  for await (const e of Deno.readDir(dir)) {
    if (e.isDirectory) {
      yield* sources(new URL(`${e.name}/`, dir));
    } else if (e.name.endsWith(".ts") && !e.name.endsWith(".test.ts")) {
      yield new URL(e.name, dir);
    }
  }
}

Deno.test("only the worker sends pushes; nothing else reaches OneSignal", async () => {
  const offenders: string[] = [];
  for await (const file of sources(root)) {
    const rel = file.pathname.slice(root.pathname.length);
    if (rel === "_shared/onesignal_push.ts") continue;
    const src = await Deno.readTextFile(file);
    if (src.includes("api.onesignal.com")) offenders.push(`${rel}: calls the OneSignal API`);
    if (src.includes("sendOneSignalPush") && rel !== "process-scheduled-notifications/index.ts") {
      offenders.push(`${rel}: sendOneSignalPush`);
    }
  }
  assertEquals(offenders, []);
});
```

Run: `deno test --allow-read supabase/functions/_shared/push_queue.test.ts supabase/functions/_shared/push_transport.test.ts`
Expected: `push_queue.test.ts` fails to load (`push_queue.ts` missing). `push_transport.test.ts` fails, listing the four offenders: `accept-invite/index.ts`, `activate-topics/index.ts`, `end-relationship/index.ts` and `send-notification/index.ts`.

- [ ] **Step 2: Write `push_queue.ts`**

```ts
// supabase/functions/_shared/push_queue.ts
//
// Every push goes through public.scheduled_notifications (Spec 1b): the
// queue's triggers apply quiet hours and the no-titles copy rules, and the
// worker (process-scheduled-notifications) is the only OneSignal caller. A
// function that wants to notify someone enqueues; it never sends.

export type QueuedPush = {
  userId: string;
  type: string;
  title: string;
  body: string;
  /** Extra metadata (deep-link ids). type/title/body above always win. */
  data?: Record<string, unknown>;
  /** Idempotency: a second enqueue with the same key is a no-op. */
  sourceKey?: string;
};

// deno-lint-ignore no-explicit-any
type Client = { from: (table: string) => any };

export async function enqueuePush(supabase: Client, push: QueuedPush): Promise<void> {
  const now = new Date().toISOString();
  const { error } = await supabase.from("scheduled_notifications").insert({
    user_id: push.userId,
    notification_type: "immediate",
    scheduled_for: now,
    status: "pending",
    metadata: { ...(push.data ?? {}), type: push.type, title: push.title, body: push.body },
    source_key: push.sourceKey ?? null,
    created_at: now,
    updated_at: now,
  });
  if (!error) return;
  if (push.sourceKey && error.code === "23505") return;
  throw new Error(`enqueue_push_failed:${error.code ?? "unknown"}`);
}
```

- [ ] **Step 3: Switch the four functions to the queue**

Snapshot each: `for f in accept-invite end-relationship activate-topics send-notification; do cp supabase/functions/$f/index.ts "$WS/snapshots/$f-index.ts"; done`.

`accept-invite/index.ts`: replace the import `import { sendOneSignalPush } from "../_shared/onesignal_push.ts";` with `import { enqueuePush } from "../_shared/push_queue.ts";`, and replace
```ts
      await sendOneSignalPush({
        userId: relationship.user_a,
        title: "Your partner joined Attune",
        body: "You can start chatting now.",
        data: {
          type: "invite_accepted",
          screen: "chat",
          relationship_id: updated.id,
        },
      });
```
with
```ts
      // Spec 1b: queued, so quiet hours apply; the worker sends it.
      await enqueuePush(supabase, {
        userId: relationship.user_a,
        type: "invite_accepted",
        title: "Your partner joined Attune",
        body: "You can start chatting now.",
        data: { relationship_id: updated.id },
        sourceKey: `invite_accepted:${updated.id}`,
      });
```

`end-relationship/index.ts`: same import swap, and replace
```ts
        await sendOneSignalPush({
          userId: otherPartnerId,
          title: "Your relationship has ended",
          body: "Reach out if you have questions, or take some time — we're here when you're ready.",
          data: { type: "relationship_ended", screen: "home" },
        });
```
with
```ts
        // Spec 1b: queued, so quiet hours apply. (Spec 3, "Ending v2",
        // removes this push altogether.)
        await enqueuePush(supabase, {
          userId: otherPartnerId,
          type: "relationship_ended",
          title: "Your relationship has ended",
          body: "Reach out if you have questions, or take some time — we're here when you're ready.",
          sourceKey: `relationship_ended:${relationshipId}:${otherPartnerId}`,
        });
```

`activate-topics/index.ts`: same import swap, and replace
```ts
      await sendOneSignalPush({
        userId,
        title: "Your topic is live",
        body: `'${shortTitle}' is now a debate. You're ${side} →`,
        data: { type: "forum_topic_activated", topic_id: topicId },
        idempotencyKey: `forum-topic-activated-${topicId}-${userId}`,
      });
```
with
```ts
      // Spec 1b: queued, so quiet hours apply (this cron runs every hour).
      await enqueuePush(supabase, {
        userId,
        type: "forum_topic_activated",
        title: "Your topic is live",
        body: `'${shortTitle}' is now a debate. You're ${side} →`,
        data: { topic_id: topicId },
        sourceKey: `forum-topic-activated-${topicId}-${userId}`,
      });
```

`send-notification/index.ts`:
- Replace `import { sendOneSignalPush } from "../_shared/onesignal_push.ts";` with `import { enqueuePush } from "../_shared/push_queue.ts";`.
- Replace `import { requireServiceRole } from "../_shared/attune_auth.ts";` with `import { requireServiceRole, serviceRoleClient } from "../_shared/attune_auth.ts";`.
- Replace
```ts
    await sendOneSignalPush({
      userId,
      title: titleText,
      body: bodyText,
      data: notificationData,
    });
```
with
```ts
    // Spec 1b: queued like every push; quiet hours and the copy guard apply
    // (the guard neutralises a moment_logged title in the body).
    const { type: dataType, ...data } = notificationData as Record<string, unknown>;
    await enqueuePush(serviceRoleClient(), {
      userId,
      type: String(dataType ?? type),
      title: titleText,
      body: bodyText,
      data,
    });
```

- [ ] **Step 4: Run, check, diff**

```bash
deno test --allow-read supabase/functions/_shared/push_queue.test.ts supabase/functions/_shared/push_transport.test.ts
deno test --allow-read --allow-env --allow-net supabase/functions/process-scheduled-notifications
deno check supabase/functions/accept-invite/index.ts supabase/functions/end-relationship/index.ts supabase/functions/activate-topics/index.ts supabase/functions/send-notification/index.ts supabase/functions/_shared/push_queue.ts
for f in accept-invite end-relationship activate-topics send-notification; do echo "== $f"; diff -u "$WS/snapshots/$f-index.ts" supabase/functions/$f/index.ts | grep -E '^[-+][^-+]'; done
```
Expected:
- 5 passed (4 queue, 1 transport); the worker's existing allowlist test is still 1 passed.
- `deno check` is clean.
- Each diff shows only the swap.
- If `deno check` reports that `supabase` is not in scope at a call site, pass the client that function already builds (`serviceRoleClient()`), and record a ruling.

- [ ] **Step 5: Ledger**

Append `Task 5: complete (push_queue 4 + transport gate 1 green; worker test green; deno check clean). Regression risk: these four pushes now arrive via the 1-minute worker cron (≤ 1 min later) and wait out quiet hours; end-relationship's partner push waits for morning (ruling R-G).`

---

### Task 6: Delete the chat streak counter

**Files:**
- Create: `supabase/migrations/20261017190000_drop_chat_streak_counter.sql`
- Create: `test/features/chat/no_streak_counter_gate_test.dart`
- Delete: `test/features/chat/streak_test.dart`
- Modify: `supabase/tests/chat_system_contracts.sql` (the streak block becomes an absence check)
- Modify: `lib/features/chat/domain/services/chat_feature_flags.dart` (lines 13, 26), `lib/features/chat/data/repositories/chat_repository.dart` (the `fetchStreak` declaration), `lib/features/chat/data/repositories/supabase_chat_repository.dart` (the `fetchStreak` override), `lib/features/chat/presentation/providers/chat_experience_providers.dart` (flag check + fetch; `ChatHeaderSnapshot.streak`), `test/features/chat/support/chat_test_harness.dart` (`streakValue`, `fetchStreak`)

**Interfaces:**
- Removes: `public.chat_conversation_streak(uuid, int)`, `feature_flags` row `chat_streaks`, `ChatFeatureFlags.streaks`, `ChatRepository.fetchStreak`, `ChatHeaderSnapshot.streak`.
- **Does not touch the streak CAMERA**: `streak_clips`, `mark_streak_viewed`, `messages.streak_views_remaining`, `streak_repository.dart`, `streak_*` screens and widgets, `streakReplayPreferenceProvider`, `chat_state.dart`'s `sendStreakMessage` (`spec1-map-f6.md` §3.2).

- [ ] **Step 1: Write the failing gate test**

```dart
// test/features/chat/no_streak_counter_gate_test.dart
// Spec 1b (research 06 §3 F6 (2); SOUL §5 P1, no streaks): the chat streak
// counter is gone and must not come back. Chat providers never mention a
// streak, and nothing in lib/ calls the counter or reads its flag. The
// streak CAMERA lives in presentation/state, data/streak_repository.dart and
// the settings feature -- outside this gate on purpose.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> _dart(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  test('chat providers never mention a streak', () {
    final hits = <String>[];
    for (final f in _dart('lib/features/chat/presentation/providers')) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (RegExp('streak', caseSensitive: false).hasMatch(lines[i])) {
          hits.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(hits, isEmpty);
  });

  test('nothing in lib/ calls the counter or reads its flag', () {
    final hits = [
      for (final f in _dart('lib'))
        if (RegExp(r'chat_conversation_streak|chat_streaks|fetchStreak')
            .hasMatch(f.readAsStringSync()))
          f.path,
    ];
    expect(hits, isEmpty);
  });
}
```

Run: `flutter test test/features/chat/no_streak_counter_gate_test.dart`
Expected: both tests FAIL. The first lists `chat_experience_providers.dart:54…`; the second lists `chat_feature_flags.dart`, `chat_repository.dart`, `supabase_chat_repository.dart` and `chat_experience_providers.dart`.

- [ ] **Step 2: Make the SQL contract assert absence (red)**

Snapshot: `cp supabase/tests/chat_system_contracts.sql "$WS/snapshots/chat_system_contracts.sql"`.

Replace the whole block from the line `-- Conversation streak: both members on two consecutive days -> streak 2` through the end of the `-- Outsider gets streak 0` DO block (the line `END $$;` after `outsider expected streak 0`) with:
```sql
-- Spec 1b: the chat streak counter is gone -- no function, no flag (SOUL §5
-- P1). The streak camera (streak_clips, mark_streak_viewed) is unrelated.
DO $$
BEGIN
  IF to_regprocedure('public.chat_conversation_streak(uuid,integer)') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: chat_conversation_streak still exists';
  END IF;
  IF EXISTS (SELECT 1 FROM public.feature_flags WHERE key = 'chat_streaks') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the chat_streaks flag still exists';
  END IF;
END $$;
```
Run: `psql -q -d attune_spec1b -v ON_ERROR_STOP=1 -f supabase/tests/chat_system_contracts.sql 2>&1 | grep -m1 ERROR`
Expected: `ERROR:  CONTRACT VIOLATED: chat_conversation_streak still exists`.

The removed block inserted four fixture messages ('a today', 'a yest', 'b today', 'b yest') used only by the streak checks (`spec1-map-f6.md` §3.1). If a later block in the file fails once they are gone, that block depended on them: record a ruling and restore exactly the INSERT it needs.

- [ ] **Step 3: Write the migration**

```sql
-- supabase/migrations/20261017190000_drop_chat_streak_counter.sql
--
-- The chat streak counter goes (Spec 1b; research 06 §3 F6 (2); SOUL §5 P1:
-- no streaks, under any name). Its flag was on in production and the client
-- fetched the count on every chat open (nothing displayed it). The streak
-- CAMERA (streak_clips, mark_streak_viewed, streak_views_remaining) is a
-- different feature and stays.
DROP FUNCTION IF EXISTS public.chat_conversation_streak(uuid, int);
DELETE FROM public.feature_flags WHERE key = 'chat_streaks';
```

- [ ] **Step 4: Remove the client counter**

Snapshot the five Dart files first (`chat_feature_flags.dart`, `chat_repository.dart`, `supabase_chat_repository.dart`, `chat_experience_providers.dart`, `chat_test_harness.dart`) into `$WS/snapshots/`.

- `chat_feature_flags.dart`: delete `  static const String streaks = 'chat_streaks';` and `    streaks: false,`.
- `chat_repository.dart`: delete
```dart
  /// Current conversation streak (consecutive local days both partners
  /// messaged). 0 on error or when there is no streak.
  Future<int> fetchStreak(String relationshipId);

```
- `supabase_chat_repository.dart`: delete the whole override, from `  @override` / `  Future<int> fetchStreak(String relationshipId) async {` through its closing `  }` and the blank line after it.
- `chat_experience_providers.dart`: in `chatHeaderSnapshotProvider`, replace
```dart
      final snapshot = await ref
          .read(chatContextRepositoryProvider)
          .loadHeaderSnapshot(userId: user.id, relationshipId: relationshipId);

      final streaksEnabled = await ChatFeatureFlags.isEnabled(
        ref.watch(supabaseClientProvider),
        ChatFeatureFlags.streaks,
      );
      if (!streaksEnabled) return snapshot;

      final streak = await ref
          .read(chatRepositoryProvider)
          .fetchStreak(relationshipId);
      return ChatHeaderSnapshot(
        pulse: snapshot.pulse,
        latestUnreadInsight: snapshot.latestUnreadInsight,
        nextReminder: snapshot.nextReminder,
        streak: streak,
      );
    });
```
with
```dart
      return ref
          .read(chatContextRepositoryProvider)
          .loadHeaderSnapshot(userId: user.id, relationshipId: relationshipId);
    });
```
  and in `ChatHeaderSnapshot` delete `  final int streak;` and `    this.streak = 0,`. Delete the now-unused import `import 'package:attune/features/chat/presentation/state/chat_state.dart';`; its only use here was `chatRepositoryProvider` for the fetch (dry run 2026-10-17: `unused_import` otherwise). Keep the `chat_feature_flags.dart` import: the file still uses `ChatFeatureFlags` for three other flags (lines 19-35).
- `chat_test_harness.dart`: delete
```dart
  /// Value returned by [fetchStreak].
  int streakValue = 0;

```
  and
```dart
  @override
  Future<int> fetchStreak(String relationshipId) async => streakValue;

```
- Delete the file `test/features/chat/streak_test.dart` (it tests only `fetchStreak`).

- [ ] **Step 5: Run everything for the task**

```bash
ATTUNE_TEST_DB=attune_spec1b scripts/local_pg_setup.sh --no-tests 2>&1 | grep -E "FAILED|applied"
psql -q -d attune_spec1b -v ON_ERROR_STOP=1 -f supabase/tests/chat_system_contracts.sql 2>&1 | grep -E "ERROR" ; echo "chat_system rc=$?"
grep -rln "chat_conversation_streak" supabase/functions lib test
flutter test test/features/chat > "$WS/t6-chat.txt" 2>&1; tr '\r' '\n' < "$WS/t6-chat.txt" | grep -E "All tests|Some tests" | tail -1
for f in chat_feature_flags.dart chat_repository.dart supabase_chat_repository.dart chat_experience_providers.dart chat_test_harness.dart; do echo "== $f"; diff -u "$WS/snapshots/$f" "$(find lib test -name $f | head -1)" | grep -E '^[-+][^-+]'; done
dart format test/features/chat/no_streak_counter_gate_test.dart
flutter analyze lib/features/chat/domain/services/chat_feature_flags.dart lib/features/chat/data/repositories/chat_repository.dart lib/features/chat/data/repositories/supabase_chat_repository.dart lib/features/chat/presentation/providers/chat_experience_providers.dart test/features/chat/support/chat_test_harness.dart test/features/chat/no_streak_counter_gate_test.dart 2>&1 | grep -E "^\s*(error|warning) "
```
Expected:
- `failed 0`.
- `chat_system_contracts` prints no `ERROR`.
- The `grep` finds nothing.
- The chat suite shows `All tests passed!`: the baseline count minus `streak_test.dart`'s 2, plus the gate's 2.
- The diffs show only the removals.
- The analyzer grep prints nothing. It is run on the touched files only, because `lib/features/chat/presentation/screens/chat_couples_locked_screen.dart` has pre-existing warnings.

- [ ] **Step 6: Ledger**

Append `Task 6: complete (gate test RED→GREEN; chat_system absence block RED→GREEN; chat suite green; streak camera untouched). Regression risk: chatHeaderSnapshotProvider no longer reads a flag — one fewer network call per chat open.`

---
### Task 7: Remove the Mirror attentiveness flag

**Files:**
- Create: `supabase/migrations/20261017190100_mirror_flag_removed.sql`
- Create: `supabase/tests/mirror_flag_contracts.sql`
- Modify: `lib/features/games/mirror/domain/services/mirror_scoring.dart`, `test/features/games/mirror_scoring_test.dart`, `lib/features/games/mirror/presentation/screens/mirror_judge_screen.dart` (comment), `test/features/games/mirror_judge_screen_test.dart` (comment), `lib/architecture/attune/ATTUNE_MASTER_SPEC.md` (one line, ruling R-H)

**Interfaces:**
- Removes: `mirror_scores.flagged`, `kAttentivenessFlagThreshold`, `isAttentivenessFlagged`.
- Keeps: `finalise_mirror_scores(uuid)` (same signature, same grants, same score), `mirrorScore`, the self-only `mirror_scores` RLS, and the end-screen score.

- [ ] **Step 1: Write the failing contract**

```sql
-- supabase/tests/mirror_flag_contracts.sql
-- The Mirror attentiveness flag is gone (Spec 1b Task 7; research 06 §3 F6
-- (3); owner Q11 "Remove"): no stored judgement about how well someone
-- reads their partner. The score stays, self-only. Every check RAISEs.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('8f100000-0000-0000-0000-0000000000a1'),
  ('8f100000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('8f100000-0000-0000-0000-0000000000a1', '+233598500001', 'Mirror A'),
  ('8f100000-0000-0000-0000-0000000000b2', '+233598500002', 'Mirror B')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at) VALUES
  ('8f200000-0000-0000-0000-000000000001', '8f100000-0000-0000-0000-0000000000a1',
   '8f100000-0000-0000-0000-0000000000b2', 'active', CURRENT_DATE, now())
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- 1. No flag column, and nothing writes one.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'public' AND table_name = 'mirror_scores' AND column_name = 'flagged') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: mirror_scores.flagged still exists';
  END IF;
  IF (SELECT prosrc FROM pg_proc WHERE proname = 'finalise_mirror_scores') LIKE '%flagged%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: finalise_mirror_scores still computes a flag';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.finalise_mirror_scores(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.finalise_mirror_scores(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: finalise_mirror_scores grants changed';
  END IF;
END $$;

-- 2. The score still works and stays self-only. Four rounds: A is the
--    subject of 1-2 (B guesses: 1 right), B of 3-4 (A guesses: 2 right).
DO $$
DECLARE v_n int; v_score int;
BEGIN
  INSERT INTO public.game_sessions (id, relationship_id, initiator_id, game_type, status)
  VALUES ('8f300000-0000-0000-0000-000000000001', '8f200000-0000-0000-0000-000000000001',
          '8f100000-0000-0000-0000-0000000000a1', 'mirror', 'active');
  INSERT INTO public.game_session_rounds (id, session_id, round_number) VALUES
    ('8f400000-0000-0000-0000-000000000001', '8f300000-0000-0000-0000-000000000001', 1),
    ('8f400000-0000-0000-0000-000000000002', '8f300000-0000-0000-0000-000000000001', 2),
    ('8f400000-0000-0000-0000-000000000003', '8f300000-0000-0000-0000-000000000001', 3),
    ('8f400000-0000-0000-0000-000000000004', '8f300000-0000-0000-0000-000000000001', 4);
  INSERT INTO public.mirror_round_truth (round_id, subject_id, truth_text, was_correct) VALUES
    ('8f400000-0000-0000-0000-000000000001', '8f100000-0000-0000-0000-0000000000a1', 'tired', true),
    ('8f400000-0000-0000-0000-000000000002', '8f100000-0000-0000-0000-0000000000a1', 'hopeful', false),
    ('8f400000-0000-0000-0000-000000000003', '8f100000-0000-0000-0000-0000000000b2', 'calm', true),
    ('8f400000-0000-0000-0000-000000000004', '8f100000-0000-0000-0000-0000000000b2', 'busy', true);
  PERFORM pg_temp.as_user('8f100000-0000-0000-0000-0000000000a1');
  PERFORM public.finalise_mirror_scores('8f300000-0000-0000-0000-000000000001');
  SELECT count(*), max(score) INTO v_n, v_score FROM public.mirror_scores
   WHERE session_id = '8f300000-0000-0000-0000-000000000001';
  RESET ROLE;
  IF v_n <> 1 OR v_score <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: A sees % score rows (max %), want only their own 2', v_n, v_score;
  END IF;
  IF (SELECT score FROM public.mirror_scores
      WHERE session_id = '8f300000-0000-0000-0000-000000000001'
        AND user_id = '8f100000-0000-0000-0000-0000000000b2') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: B''s score was not written';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'mirror_flag_contracts: all held'; END $$;
ROLLBACK;
```

Run: `psql -q -d attune_spec1b -v ON_ERROR_STOP=1 -f supabase/tests/mirror_flag_contracts.sql 2>&1 | grep -m1 ERROR`
Expected: `ERROR:  CONTRACT VIOLATED: mirror_scores.flagged still exists`.

If a `game_sessions` / `game_session_rounds` / `mirror_round_truth` insert in block 2 is refused by a constraint or trigger not visible in `information_schema`, add only the column it names and record a ruling. The score assertion must stay.

- [ ] **Step 2: Write the migration**

The function is restated from `20260912120000_gate_mirror_truth_read.sql:81-145`, minus the flag expression and the `flagged` column.

```sql
-- supabase/migrations/20261017190100_mirror_flag_removed.sql
--
-- The Mirror "attentiveness flag" goes (Spec 1b; research 06 §3 F6 (3);
-- owner Q11 "Remove"; ATTUNE_MASTER_SPEC decision 33). It stored a judgement
-- ("flagged") about how well someone reads their partner -- never shown,
-- but a label the product must not keep. The score stays: self-only, shown
-- to its owner at the end of the game.
CREATE OR REPLACE FUNCTION public.finalise_mirror_scores(
  p_session_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_a uuid;
  v_user_b uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT rel.user_a, rel.user_b
    INTO v_user_a, v_user_b
  FROM public.game_sessions s
  JOIN public.relationships rel ON rel.id = s.relationship_id
  WHERE s.id = p_session_id
    AND s.game_type = 'mirror'
    AND (rel.user_a = v_user_id OR rel.user_b = v_user_id);

  IF v_user_a IS NULL THEN
    RAISE EXCEPTION 'Session not found';
  END IF;

  -- One row per guesser. A round's guesser is whichever partner is NOT
  -- its subject, so the score counts the rounds where that person read
  -- their partner correctly.
  INSERT INTO public.mirror_scores (session_id, user_id, score)
  SELECT
    p_session_id,
    guesser.id,
    count(*) FILTER (WHERE t.was_correct)::int
  FROM public.mirror_round_truth t
  JOIN public.game_session_rounds r ON r.id = t.round_id
  CROSS JOIN LATERAL (
    SELECT CASE WHEN t.subject_id = v_user_a THEN v_user_b
                ELSE v_user_a END AS id
  ) AS guesser
  WHERE r.session_id = p_session_id
    AND t.was_correct IS NOT NULL
  GROUP BY guesser.id
  ON CONFLICT (session_id, user_id) DO UPDATE
    SET score = EXCLUDED.score;
END;
$$;

REVOKE ALL ON FUNCTION public.finalise_mirror_scores(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalise_mirror_scores(uuid) TO authenticated;

ALTER TABLE public.mirror_scores DROP COLUMN IF EXISTS flagged;
```

Before writing, diff the restated body against `20260912120000_gate_mirror_truth_read.sql:81-145`. Only the INSERT column list, the flag expression with its comment, and the `ON CONFLICT … SET` list may differ.

- [ ] **Step 3: Rebuild, run, neighbours, mutant**

```bash
ATTUNE_TEST_DB=attune_spec1b scripts/local_pg_setup.sh --no-tests 2>&1 | grep -E "FAILED|applied"
for f in mirror_flag_contracts love_map_contracts games_contracts; do psql -q -d attune_spec1b -v ON_ERROR_STOP=1 -f supabase/tests/$f.sql >/dev/null 2>"$WS/err.txt" && echo "PASS $f" || { echo "FAIL $f"; grep -m2 ERROR "$WS/err.txt"; }; done
"$WS/mutant.sh" "ALTER TABLE public.mirror_scores ADD COLUMN flagged boolean NOT NULL DEFAULT false;" supabase/tests/mirror_flag_contracts.sql
```
Expected: all `PASS`; the mutant prints `CONTRACT VIOLATED: mirror_scores.flagged still exists` and `MUTANT KILLED`.

- [ ] **Step 4: Remove the Dart duplicate (test first)**

Snapshot `mirror_scoring.dart`, `mirror_scoring_test.dart`, `mirror_judge_screen.dart`, `mirror_judge_screen_test.dart` and `ATTUNE_MASTER_SPEC.md` into `$WS/snapshots/`.

In `test/features/games/mirror_scoring_test.dart`, replace the whole `group('isAttentivenessFlagged', () { … });` with:
```dart
  test('the score is a count, never a flag (Spec 1b: no attentiveness '
      'judgement is computed or stored)', () {
    final src = File(
      'lib/features/games/mirror/domain/services/mirror_scoring.dart',
    ).readAsStringSync();
    expect(src.contains('isAttentivenessFlagged'), isFalse);
    expect(src.contains('kAttentivenessFlagThreshold'), isFalse);
  });
```
and add `import 'dart:io';` as the file's first import.
Run: `flutter test test/features/games/mirror_scoring_test.dart` → FAIL (both symbols present).

In `mirror_scoring.dart`, replace the header and flag code:
- Delete `/// §8.4: "Score tracked: below 6.5/8 = attentiveness flag".` and `const double kAttentivenessFlagThreshold = 6.5;` together with the blank line after them.
- Delete the whole `isAttentivenessFlagged` doc comment and function (from `/// Whether this score raises the §8.4 attentiveness flag.` to its closing `}`).
- Change the first doc line to `/// Mirror Game scoring (ATTUNE_MASTER_SPEC.md §8.4). No attentiveness flag (Spec 1b).`

In `mirror_judge_screen.dart`, change the comment lines
```dart
              // Both options are OutlinedButton, deliberately matching
              // widget types. This measurement feeds the §8.4
              // attentiveness flag directly: a FilledButton on "Yes"
              // visually nudges the subject toward the affirmative in
              // the very judgement that determines the score.
```
to
```dart
              // Both options are OutlinedButton, deliberately matching
              // widget types: a FilledButton on "Yes" visually nudges the
              // subject toward the affirmative in the very judgement that
              // determines the score.
```
In `mirror_judge_screen_test.dart`, change `    // in the exact measurement the §8.4 attentiveness flag reads. Both` to `    // in the exact judgement the score is made of. Both`.

In `ATTUNE_MASTER_SPEC.md` (ruling R-H), change the single line `- Score tracked: below 6.5/8 = attentiveness flag` to `- Score shown only to the person who guessed; no attentiveness flag is computed or stored (decision 33)`.

Run:
```bash
flutter test test/features/games/mirror_scoring_test.dart test/features/games/mirror_judge_screen_test.dart test/features/games
for f in mirror_scoring.dart mirror_scoring_test.dart mirror_judge_screen.dart mirror_judge_screen_test.dart ATTUNE_MASTER_SPEC.md; do echo "== $f"; diff -u "$WS/snapshots/$f" "$(find lib test -name $f | head -1)" | grep -E '^[-+][^-+]'; done
flutter analyze lib/features/games/mirror test/features/games/mirror_scoring_test.dart test/features/games/mirror_judge_screen_test.dart 2>&1 | grep -E "^\s*(error|warning) "
```
Expected: all pass; the diffs show only those lines; the analyzer grep prints nothing.

- [ ] **Step 5: Ledger**

Append `Task 7: complete (mirror_flag_contracts RED→GREEN, love_map + games green; mutant KILLED; Dart flag removed RED→GREEN; MASTER_SPEC one line (R-H)).`

---

### Task 8: Device surfaces show "Next plan" unless titles are turned on

**Files:**
- Modify: `lib/features/together/domain/together_widget.dart`, `lib/features/together/domain/together_live.dart`, `lib/features/together/domain/together_mirror.dart`
- Modify: `lib/features/together/data/together_widget_sync.dart`, `lib/features/together/data/together_live_activity.dart`, `lib/features/together/data/together_calendar_mirror.dart`
- Modify: `lib/features/together/presentation/together_providers.dart`, `lib/features/together/presentation/widgets/together_settings_sheet.dart`, `lib/features/together/presentation/screens/together_screen.dart`
- Create: `test/features/together/together_surface_titles_test.dart`
- Modify (fixtures that assumed titles): `test/features/together/together_widget_sync_test.dart`, `test/features/together/together_live_activity_test.dart`, `test/features/together/together_calendar_mirror_test.dart`, `test/features/together/together_mirror_test.dart`, `test/features/together/together_screen_test.dart` (plus one new screen test)

**Interfaces:**
- Domain:
  - `WidgetLine` gains `final String neutralTitle` (named, default `widgetNeutralTitle`).
  - Constants: `const widgetNeutralTitle = 'Next plan'`, `const widgetNeutralReminderTitle = 'Reminder'`.
  - `List<WidgetLine> widgetLinesForCard(List<WidgetLine> lines, {required bool showTitles})`.
  - `const liveNeutralTitle = 'Next plan'`; `LivePlan livePlanForLockScreen(LivePlan plan, {required bool showTitles})`.
  - `const mirrorNeutralTitle = 'Plan'`; `mirrorEventsFor({…, bool showTitles = false})`. With titles off: title `mirrorNeutralTitle`, `location: null`.
- Data: `const widgetTitlesKey = 'together_widget_titles'`, `const liveTitlesKey = 'together_live_titles'`, `const mirrorTitlesKey = 'together_mirror_titles'`. Each publish/show/sync re-reads its key from storage, default false.
- Providers: `class TogetherSurfaceTitles extends FamilyAsyncNotifier<bool, String>` with `set(bool)`, and `final togetherSurfaceTitlesProvider = AsyncNotifierProvider.family<TogetherSurfaceTitles, bool, String>(TogetherSurfaceTitles.new)` keyed by the prefs key.
- Native code is unchanged: the payload schema is the same, only the strings differ (`spec1-map-f8.md` "Key facts").

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/together/together_surface_titles_test.dart
// Spec 1b (research 06 §3 F8 (1)): the home-screen card, the lock-screen
// plan and the calendar copy show "Next plan" (calendar: "Plan", no place)
// unless this phone turned titles on for that surface. Off by default.
import 'package:attune/features/together/data/together_calendar_mirror.dart';
import 'package:attune/features/together/data/together_live_activity.dart';
import 'package:attune/features/together/data/together_widget_sync.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/together/domain/together_live.dart';
import 'package:attune/features/together/domain/together_mirror.dart';
import 'package:attune/features/together/domain/together_overlay.dart';
import 'package:attune/features/together/domain/together_widget.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'together_calendar_mirror_test.dart' show FakeMirrorCalendar;
import 'together_live_activity_test.dart' show FakeLiveStore;
import 'together_widget_sync_test.dart' show FakeWidgetStore;

final _now = DateTime(2026, 11, 2, 9);

TogetherItem _item(
  String title, {
  TogetherItemKind kind = TogetherItemKind.event,
  Map<String, dynamic> ref = const {},
}) => TogetherItem(
  kind: kind,
  id: title,
  date: DateTime(2026, 11, 3),
  startsAt: DateTime(2026, 11, 3, 19),
  allDay: false,
  title: title,
  participantIds: const ['ama', 'kofi'],
  createdBy: 'ama',
  sourceRef: ref,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the card lines know their neutral words: plan, reminder, free', () {
    final lines = togetherWidgetLines(
      items: [
        _item('Clinic'),
        _item('Pick up pills', kind: TogetherItemKind.reminder),
      ],
      windows: [
        FreeWindow(
          start: DateTime(2026, 11, 2, 18),
          end: DateTime(2026, 11, 2, 20),
          partnerFrom: '18:00',
          partnerTo: '20:00',
          partnerDiffers: false,
        ),
      ],
      me: 'ama',
      now: _now,
    );
    expect(
      widgetLinesForCard(lines, showTitles: false).map((l) => l.title),
      containsAll(['Free', widgetNeutralTitle, widgetNeutralReminderTitle]),
    );
    expect(
      widgetLinesForCard(lines, showTitles: true).map((l) => l.title),
      containsAll(['Free', 'Clinic', 'Pick up pills']),
    );
  });

  test('the card publishes "Next plan" unless titles are on', () async {
    final store = FakeWidgetStore();
    TogetherWidgetSync.store = store;
    const line = WidgetLine(title: 'Clinic', label: 'Tue 7:00 PM', startMs: 1, endMs: 2);
    SharedPreferences.setMockInitialValues({'together_widget_enabled': true});
    await TogetherWidgetSync.publishIfEnabled([line]);
    expect(store.saved.last, contains('Next plan'));
    expect(store.saved.last, isNot(contains('Clinic')));
    SharedPreferences.setMockInitialValues({
      'together_widget_enabled': true,
      'together_widget_titles': true,
    });
    await TogetherWidgetSync.publishIfEnabled([line]);
    expect(store.saved.last, contains('Clinic'));
  });

  test('the lock screen shows "Next plan" unless titles are on', () async {
    final store = FakeLiveStore();
    TogetherLiveActivity.store = store;
    final plan = LivePlan(
      title: 'Clinic',
      start: DateTime(2026, 11, 2, 19),
      end: DateTime(2026, 11, 2, 20),
    );
    SharedPreferences.setMockInitialValues({'together_live_enabled': true});
    await TogetherLiveActivity.showIfEnabled(plan);
    expect(store.shown.last.title, liveNeutralTitle);
    expect(store.shown.last.start, plan.start);
    SharedPreferences.setMockInitialValues({
      'together_live_enabled': true,
      'together_live_titles': true,
    });
    await TogetherLiveActivity.showIfEnabled(plan);
    expect(store.shown.last, plan);
  });

  test('the calendar copy is "Plan" with no place unless titles are on', () {
    final items = [_item('Clinic', ref: {'location_name': 'Ridge Hospital'})];
    final off = mirrorEventsFor(items: items, me: 'ama');
    expect(off.single.title, mirrorNeutralTitle);
    expect(off.single.location, isNull);
    final on = mirrorEventsFor(items: items, me: 'ama', showTitles: true);
    expect(on.single.title, 'Clinic');
    expect(on.single.location, 'Ridge Hospital');
  });

  test('turning titles on replaces the calendar entries', () async {
    final cal = FakeMirrorCalendar();
    TogetherMirror.calendar = cal;
    final items = [_item('Clinic')];
    SharedPreferences.setMockInitialValues({'together_mirror_enabled': true});
    await TogetherMirror.syncIfEnabled((from, to) async => items, 'ama', _now);
    expect(cal.entries('Plans').map((e) => e.title), [mirrorNeutralTitle]);
    // Set on the same store: resetting the mock would also forget the
    // calendar's id and make a second "Plans" calendar.
    await (await SharedPreferences.getInstance()).setBool(
      mirrorTitlesKey,
      true,
    );
    await TogetherMirror.syncIfEnabled((from, to) async => items, 'ama', _now);
    expect(cal.entries('Plans').map((e) => e.title), ['Clinic']);
  });

  test('each surface\'s titles switch is off by default and remembered', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    for (final key in [widgetTitlesKey, liveTitlesKey, mirrorTitlesKey]) {
      expect(await c.read(togetherSurfaceTitlesProvider(key).future), isFalse);
    }
    await c.read(togetherSurfaceTitlesProvider(widgetTitlesKey).notifier).set(true);
    expect(await c.read(togetherSurfaceTitlesProvider(widgetTitlesKey).future), isTrue);
    expect((await SharedPreferences.getInstance()).getBool(widgetTitlesKey), isTrue);
    expect(await c.read(togetherSurfaceTitlesProvider(liveTitlesKey).future), isFalse);
  });
}
```

Run: `flutter test test/features/together/together_surface_titles_test.dart`
Expected: compile failure (`widgetLinesForCard`, `widgetNeutralTitle`, `liveNeutralTitle`, `mirrorNeutralTitle`, `togetherSurfaceTitlesProvider`, `widgetTitlesKey` … not defined).

- [ ] **Step 2: Domain**

Snapshot every file listed under **Modify** into `$WS/snapshots/` first.

`together_widget.dart`:
- Add `this.neutralTitle = widgetNeutralTitle,` to the `WidgetLine` constructor.
- Add the field:
```dart
  /// What the card shows unless this phone turned plan titles on (Spec 1b).
  final String neutralTitle;
```
- Before `DateTime _day(`, add:
```dart
/// The card's words for a plan when titles are off (Spec 1b; research 06 §3
/// F8 (1)): a glance at a locked or borrowed phone says when, never what.
const widgetNeutralTitle = 'Next plan';
const widgetNeutralReminderTitle = 'Reminder';

/// What actually goes to the card: titles only where this phone opted in.
List<WidgetLine> widgetLinesForCard(
  List<WidgetLine> lines, {
  required bool showTitles,
}) => [
  for (final l in lines)
    showTitles
        ? l
        : WidgetLine(
          title: l.neutralTitle,
          label: l.label,
          startMs: l.startMs,
          endMs: l.endMs,
          neutralTitle: l.neutralTitle,
        ),
];
```
- In `togetherWidgetLines`, give the plan line `neutralTitle: i.kind == TogetherItemKind.reminder ? widgetNeutralReminderTitle : widgetNeutralTitle,` and the free-window line `neutralTitle: 'Free',`.

`together_live.dart`: change the library doc's second line to `/// as a countdown. "Next plan" unless titles are on (Spec 1b); no names (R2).`, and append:
```dart
/// The lock screen's words for a plan when titles are off (Spec 1b).
const liveNeutralTitle = 'Next plan';

/// What actually goes to the lock screen: the title only if this phone
/// opted in.
LivePlan livePlanForLockScreen(LivePlan plan, {required bool showTitles}) =>
    showTitles
        ? plan
        : LivePlan(title: liveNeutralTitle, start: plan.start, end: plan.end);
```

`together_mirror.dart`:
- Add `bool showTitles = false,` to `mirrorEventsFor`'s named parameters.
- In the `MirrorEvent(...)` it builds, change `title: title,` to `title: showTitles ? title : mirrorNeutralTitle,` and `location: i.sourceRef['location_name'] as String?,` to `location: showTitles ? i.sourceRef['location_name'] as String? : null,`.
- Above `mirrorEventsFor`, add:
```dart
/// The calendar copy's word for a plan when titles are off (Spec 1b). A
/// place outs a plan as surely as its title, so it goes with it (R-I).
const mirrorNeutralTitle = 'Plan';
```
Two plans at the same time then share a fingerprint, so `mirrorEventsFor` deduplicates by plan id + fingerprint (follow-up M3): the calendar shows two "Plan" entries and a second sync changes nothing.

- [ ] **Step 3: Data layer**

`together_widget_sync.dart`: next to `const enabledKey = 'together_widget_enabled';`, add
```dart
/// Whether the card may show plan titles on this phone (Spec 1b). Off by
/// default; read from storage at every publish, like [enabledKey].
const widgetTitlesKey = 'together_widget_titles';
```
and change the body of `publishIfEnabled` to
```dart
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(enabledKey) ?? false)) return;
      await publish(
        widgetLinesForCard(
          lines,
          showTitles: prefs.getBool(widgetTitlesKey) ?? false,
        ),
      );
    } catch (_) {}
```

`together_live_activity.dart`: next to `const liveEnabledKey = 'together_live_enabled';`, add
```dart
/// Whether the lock-screen plan may show its title on this phone (Spec 1b).
const liveTitlesKey = 'together_live_titles';
```
and in `showIfEnabled` change `await store.show(plan);` to
```dart
        await store.show(
          livePlanForLockScreen(
            plan,
            showTitles: prefs.getBool(liveTitlesKey) ?? false,
          ),
        );
```

`together_calendar_mirror.dart`: next to `const mirrorEnabledKey = 'together_mirror_enabled';`, add
```dart
/// Whether the calendar copy may carry plan titles and places on this phone
/// (Spec 1b). A change replaces every entry (titles are in the fingerprint).
const mirrorTitlesKey = 'together_mirror_titles';
```
and in `syncIfEnabled` change `for (final e in mirrorEventsFor(items: await load(from, to), me: me))` to
```dart
        for (final e in mirrorEventsFor(
          items: await load(from, to),
          me: me,
          showTitles: prefs.getBool(mirrorTitlesKey) ?? false,
        ))
```

- [ ] **Step 4: Provider, settings rows, screen listeners**

`together_providers.dart`: after `togetherMirrorEnabledProvider`, add
```dart
/// Whether one device surface may show plan titles on this phone (Spec 1b),
/// keyed by that surface's prefs key ([widgetTitlesKey], [liveTitlesKey],
/// [mirrorTitlesKey]). Off by default. Each surface re-reads the stored value
/// itself when it publishes, so this only drives the switch.
class TogetherSurfaceTitles extends FamilyAsyncNotifier<bool, String> {
  @override
  Future<bool> build(String key) async =>
      (await SharedPreferences.getInstance()).getBool(key) ?? false;

  Future<void> set(bool on) async {
    await (await SharedPreferences.getInstance()).setBool(arg, on);
    state = AsyncData(on);
  }
}

final togetherSurfaceTitlesProvider =
    AsyncNotifierProvider.family<TogetherSurfaceTitles, bool, String>(
      TogetherSurfaceTitles.new,
    );
```

`together_settings_sheet.dart`:
- Add imports `import '../../data/together_calendar_mirror.dart' show mirrorTitlesKey;`, `import '../../data/together_live_activity.dart' show liveTitlesKey;` and `import '../../data/together_widget_sync.dart' show widgetTitlesKey;`.
- Replace the three subtitles with the verbatim copy from Global Constraints.
- Directly after each surface's `InfoRowWidget(...)` (inside its `if (… != null) ...[` list), add `if (widgetOn == true) _titlesRow(widgetTitlesKey, _titlesOnPhone),` (and the same with `liveOn` / `liveTitlesKey` / `_titlesOnPhone`, and `mirrorOn` / `mirrorTitlesKey` / `_titlesInCalendar`).
- Add to the State class:
```dart
  static const _titlesOnPhone =
      'Shows what each plan is called. Anyone who sees your phone can read it.';
  static const _titlesInCalendar =
      'Copies each plan’s title and place. Anyone who sees your calendar can read them.';

  // Spec 1b: a surface shows "Next plan" unless this phone turns titles on.
  Widget _titlesRow(String key, String subtitle) {
    final on = ref.watch(togetherSurfaceTitlesProvider(key)).valueOrNull;
    if (on == null) return const SizedBox.shrink();
    return InfoRowWidget(
      key: ValueKey('together_titles_$key'),
      title: 'Show plan titles',
      subtitle: subtitle,
      icon: Icons.title_outlined,
      showAvatar: false,
      showDivider: false,
      isToggleItem: true,
      toggleValue: on,
      onToggleChanged:
          (v) => ref.read(togetherSurfaceTitlesProvider(key).notifier).set(v),
    );
  }
```

`together_screen.dart`: directly after the existing `ref.listen<AsyncValue<bool>>(togetherWidgetEnabledProvider, …);` block in `_agenda`, add:
```dart
    // Spec 1b: turning plan titles on or off re-sends what the card and the
    // lock screen show, from what the hub already has.
    ref.listen<AsyncValue<bool>>(
      togetherSurfaceTitlesProvider(widgetTitlesKey),
      (prev, next) {
        if (prev?.valueOrNull != null &&
            next.valueOrNull != prev?.valueOrNull) {
          _publishWidget(
            ref.read(togetherAgendaProvider(relationshipId)).valueOrNull,
            windows,
            me,
            now,
          );
        }
      },
    );
    ref.listen<AsyncValue<bool>>(
      togetherSurfaceTitlesProvider(liveTitlesKey),
      (prev, next) {
        if (prev?.valueOrNull != null &&
            next.valueOrNull != prev?.valueOrNull) {
          _publishLive(
            ref.read(togetherAgendaProvider(relationshipId)).valueOrNull,
            me,
            now,
          );
        }
      },
    );
```
and directly after the `ref.listen<AsyncValue<bool>>(togetherMirrorEnabledProvider, …);` block, add:
```dart
    // Spec 1b: titles on or off replaces every calendar entry.
    ref.listen<AsyncValue<bool>>(
      togetherSurfaceTitlesProvider(mirrorTitlesKey),
      (prev, next) {
        if (relationshipId != null &&
            prev?.valueOrNull != null &&
            next.valueOrNull != prev?.valueOrNull) {
          _syncMirror(relationshipId);
        }
      },
    );
```
(The screen already imports the three data files and `together_providers.dart`.)

- [ ] **Step 5: Bring the four existing tests to the new default**

These tests assumed titles were always shown. Each keeps its own behaviour under test and now states the titles opt-in explicitly:
- `together_widget_sync_test.dart` ("publishing checks the stored opt-in itself"): change `SharedPreferences.setMockInitialValues({'together_widget_enabled': true});` to `SharedPreferences.setMockInitialValues({'together_widget_enabled': true, 'together_widget_titles': true});`.
- `together_live_activity_test.dart` ("shows or ends only when this phone opted in"): change `SharedPreferences.setMockInitialValues({'together_live_enabled': true});` (the first one in that test) to `SharedPreferences.setMockInitialValues({'together_live_enabled': true, 'together_live_titles': true});`.
- `together_calendar_mirror_test.dart` `setUp`: change `SharedPreferences.setMockInitialValues({'together_mirror_enabled': true});` to `SharedPreferences.setMockInitialValues({'together_mirror_enabled': true, 'together_mirror_titles': true});`.
- `together_mirror_test.dart`: add `showTitles: true,` to the two `mirrorEventsFor(` calls written `final out = mirrorEventsFor(\n      me: 'ama',` (in "copies shared, confirmed plans I am in: titles, times and places" and "a three-day trip is one all-day entry"). The `me: null` call needs nothing.
- `together_screen_test.dart`: its 11 `SharedPreferences.setMockInitialValues({…})` calls all belong to surface tests that assert titled output (dry run 2026-10-17: 7 of them fail under the new default).
  - Before `void main() {`, add:
```dart
// Spec 1b: these tests exercise the screen's wiring with plan titles on;
// the titles-off default is pinned in together_surface_titles_test.dart.
const _titlesOn = <String, Object>{
  'together_widget_titles': true,
  'together_live_titles': true,
  'together_mirror_titles': true,
};
```
  - Replace every `SharedPreferences.setMockInitialValues({` in the file with `SharedPreferences.setMockInitialValues({..._titlesOn, `.
  - Directly before `  testWidgets('with the card off (the default), nothing is written', (t) async {`, add the Review Focus 7 test (red until the Step 4 listeners exist):
```dart
  testWidgets('turning plan titles on re-sends the card straight away '
      '(Spec 1b)', (t) async {
    SharedPreferences.setMockInitialValues({'together_widget_enabled': true});
    final store = FakeWidgetStore();
    TogetherWidgetSync.store = store;
    await _pump(
      t,
      upcoming: [
        _row(
          'd',
          '2026-11-03',
          startsAt: '2026-11-03T19:00:00Z',
          title: 'Dinner',
        ),
      ],
    );
    await t.pumpAndSettle();
    expect(store.saved.where((s) => s != null).last, contains('Next plan'));
    expect(store.saved.where((s) => s != null).last, isNot(contains('Dinner')));
    final container = ProviderScope.containerOf(
      t.element(find.byType(TogetherScreen)),
    );
    await container
        .read(togetherSurfaceTitlesProvider(widgetTitlesKey).notifier)
        .set(true);
    await t.pumpAndSettle();
    expect(store.saved.where((s) => s != null).last, contains('Dinner'));
  });

```
    (This new test sets its own map without `_titlesOn`, because it starts with titles off.)

- [ ] **Step 6: Run, diff, format, analyze**

```bash
flutter test test/features/together > "$WS/t8.txt" 2>&1; tr '\r' '\n' < "$WS/t8.txt" | grep -E "All tests|Some tests" | tail -1; tr '\r' '\n' < "$WS/t8.txt" | grep "\[E\]" | sort -u | head
for f in together_widget.dart together_live.dart together_mirror.dart together_widget_sync.dart together_live_activity.dart together_calendar_mirror.dart together_providers.dart together_settings_sheet.dart together_screen.dart together_widget_sync_test.dart together_live_activity_test.dart together_calendar_mirror_test.dart together_mirror_test.dart together_screen_test.dart; do echo "== $f"; diff -u "$WS/snapshots/$f" "$(find lib/features/together test/features/together -name $f | head -1)" | grep -E '^[-+][^-+]'; done
dart format test/features/together/together_surface_titles_test.dart
flutter analyze lib/features/together test/features/together 2>&1 | grep -E "^\s*(error|warning) "
```
Expected:
- `All tests passed!`. The settings tests still find "no names" exactly once: the card's new subtitle keeps it, and the calendar copy's says "never names".
- Each diff shows only the lines above.
- The analyzer grep prints nothing new.

- [ ] **Step 7: Ledger**

Append `Task 8: complete (together_surface_titles_test RED→GREEN; Together suite green; native unchanged). Regression risk: anyone who turned a surface on before this ships now sees "Next plan" until they turn titles on (intended, F8 (1)).`

---
### Task 9: Docs, full suite, privacy greps, owner hand-off, final review

**Files:**
- Modify: `lib/app/documentations/user_manual/data/chat_docs.dart` (one FAQ)
- Modify: the ledger `$WS/progress.md`

- [ ] **Step 1: The quiet-hours FAQ**

Snapshot `chat_docs.dart`. After the `faq_chat_reflections` `FAQModel(...)` (the last one, `order: 8`), add:
```dart
      FAQModel(
        id: 'faq_chat_quiet_hours',
        question: 'Why do some notifications arrive at 8 in the morning?',
        answer:
            'Attune holds notifications between 10 pm and 8 am in your time zone and sends them at 8 am instead — nothing is lost. Messages that arrive overnight become one notification per conversation, and none at all if you read them first. Safety resources, alarms set for shortly before a plan, and moves in a game you're playing right now are never held.',
        category: 'Chat',
        order: 9,
      ),
```
Run: `flutter analyze lib/app/documentations/user_manual/data/chat_docs.dart 2>&1 | grep -E "^\s*(error|warning) "; flutter test test/app/documentations`. Expected: nothing from the analyzer; all pass. Diff against the snapshot.

- [ ] **Step 2: Run everything**

```bash
cd /Users/user/attune
flutter test > "$WS/full.txt" 2>&1; tr '\r' '\n' < "$WS/full.txt" | grep -E "All tests|Some tests" | tail -1; tr '\r' '\n' < "$WS/full.txt" | grep "\[E\]" | sed 's/.*attune\/test/test/' | sort -u
deno test --allow-read supabase/functions/_shared/push_queue.test.ts supabase/functions/_shared/push_transport.test.ts 2>&1 | grep -E "passed|failed" | tail -1
for d in process-scheduled-notifications compute-pulse generate-verdict; do echo "== $d"; deno test --allow-read --allow-env --allow-net supabase/functions/$d 2>&1 | grep -E "passed|failed" | tail -1; done
ATTUNE_TEST_DB=attune_spec1b scripts/local_pg_setup.sh > "$WS/final-sql.txt" 2>&1; grep -cE "^\s+PASS" "$WS/final-sql.txt"
diff <(grep -E "^\s+FAIL" -A1 "$WS/baseline-sql.txt") <(grep -E "^\s+FAIL" -A1 "$WS/final-sql.txt") && echo "SQL failures identical to baseline"
grep -c "FAILED:" "$WS/final-sql.txt"
```
Expected:
- Flutter: the baseline count + this plan's new tests − `streak_test.dart`'s 2. Only the known time-of-day test may fail, and only when run between midnight and about 05:00.
- Deno: 5 passed for the two new `_shared` files; the three directories are green.
- SQL: PASS = baseline + 5 new files; failures identical to baseline; `0` migrations `FAILED:`.

Record all numbers in the ledger.

- [ ] **Step 3: Privacy greps**

```bash
grep -rn "sendOneSignalPush" supabase/functions --include='*.ts' | grep -v "_shared/onesignal_push.ts\|process-scheduled-notifications/index.ts\|\.test\.ts"
grep -rniE "streak" lib/features/chat/presentation/providers
grep -rnE "console\.(log|error)\(.*(timezone|title)" supabase/functions/_shared/push_queue.ts supabase/functions/{accept-invite,end-relationship,activate-topics,send-notification}/index.ts
grep -rn "debugPrint\|print(" lib/core/services/user_timezone_reporter.dart
```
Expected: all four print nothing.

- [ ] **Step 4: Checklist v3.1 evidence map (into the ledger)**

| Item | Evidence |
|---|---|
| 1.4 Authorization | `set_my_timezone` updates only `auth.uid()`'s row; the resolver and guards are not client-callable (contract Task 1 §1); `mark_conversation_read` cancels only the caller's own pushes, and an outsider cancels nothing (Task 3 §2, §4) |
| 1.6 Concurrency | Overnight collapse under `pg_advisory_xact_lock(hashtext(key))` plus the unique `source_key`; the collapse UPDATE does not refire the status trigger (it does not set `status`) |
| 1.11 Privacy impact | A zone is coarse location, so `users` is self-only (Task 1 §4); no plan titles in push copy (Task 4 sweep); device surfaces neutral by default, and the calendar copy drops places (Task 8) |
| 2.1 Input validation | `set_my_timezone` refuses abbreviations, offsets, legacy names, blanks, NULL and unknown zones (Task 1 §3); the resolver re-validates every stored zone (§5) |
| 2.18 Idempotency | `enqueuePush` source keys (23505 → already queued); the collapse key; `set_my_timezone` no-op on the same zone; the reporter skips an unchanged zone |
| 3.x Never drop | Deferred rows stay `pending` (Task 2 §1); late time-relative copy is neutralised, not removed (§6); a collapse-key clash queues a second push rather than failing (§5); the only cancellation is a chat push for a conversation already read (Task 3, owner decision D2) |
| 4.4 No sensitive logs | Step 3 greps |
| 6.x Tests first | Every task's RED run is recorded; mutants per task (T1 2, T2 2, T3 1, T4 2, T7 1) |
| 8.1 Flags/rollout | No feature flag. Migration-gated: quiet hours and copy apply from `db push`; titles off is a client default (per phone). Kill switches: `DISABLE TRIGGER` on either guard (reversible with `ENABLE`); quiet hours reach a user only once their zone is known. |

- [ ] **Step 5: Owner hand-off (into the ledger, and tell the owner)**

1. **Ship the app build first:** the time-zone reporter, the streak fetch removed, and the titles-off surfaces. Until a user's app reports a zone, quiet hours simply don't apply to them (unknown zone, no deferral), so shipping in this order means more people get quiet hours from day one. Older builds are safe: the `chat_streaks` flag row is gone, so `ChatFeatureFlags.isEnabled` returns false and no old client calls the dropped function.
2. `supabase db push` applies six migrations: `20261017160000`, `170000`, `170100`, `180000`, `190000`, `190100`. **Hard dependency:** `170100` requires Spec 1a's `20261017120000`–`130200`. Push both specs in one `db push`, or 1a first; never 1b alone (`170100` refuses to apply without them).
3. Redeploy `accept-invite`, `end-relationship`, `activate-topics` and `send-notification` (they now enqueue). Either order relative to `db push` is safe. `process-scheduled-notifications` is unchanged.
4. Remote checks (record in the ledger):
   - After an app open, `select timezone from public.users where id = '<test user>'` shows the phone's IANA zone.
   - At 23:00 local on a test phone, send a message from the partner: no push arrives; at 08:00 one "New messages in Attune" arrives. Repeat, but read the chat at 07:30: no 08:00 push.
   - Set a plan alarm for 23:30: it rings at 23:30.
   - Lock-screen copy for a proposal, a reminder and the daily summary shows no plan titles.
   - The Together card, Live Activity and calendar copy show "Next plan" / "Plan". Turn "Show plan titles" on for each: the titles appear without leaving the screen (Review Focus 7).
   - `select key from feature_flags where key = 'chat_streaks'` returns nothing.
   - A week after release: `select count(*) filter (where timezone is null), count(*) from public.users;` shows how many users quiet hours do not yet reach.
5. Emergency rollback, no migration needed (plan review M11):
   - `ALTER TABLE public.scheduled_notifications DISABLE TRIGGER scheduled_notifications_quiet_guard;` (and `… scheduled_notifications_copy_guard;`).
   - Reverse each with `ENABLE TRIGGER`.
6. Watch first: the worker claims at most 50 rows a minute (`process-scheduled-notifications/index.ts:13-19`), and every deferred row for a zone becomes due at 08:00 together. At around 3,000 overnight rows in one zone, the last goes out about an hour late. Raise the batch, or loop while full, when overnight queue depth gets near that (plan review M2).
7. Spec 2 (quick exit, Safety PIN, account security, neutral icon and sender-name audit) is next; the ICS feed's titles go with it.

- [ ] **Step 6: Final review**

Build the review package: snapshot diffs for every shared file, plus the full text of every new file. Dispatch the final Fable review with:
- this plan;
- the spec rows F6 and F8;
- this plan's Review Focus, verbatim;
- the owner decisions and rulings box;
- the ledger's `Ruling:` lines.

Do one fix pass; each fix must be proved by a test that failed first. Append `Task 9: complete` with the final numbers.

---

## Self-review (done while writing)

**Spec coverage**

| Requirement | Task |
|---|---|
| F6 (1) defer, never drop, any non-safety push in recipient-local 22:00–08:00 | 2 (guard on insert and on return to pending), 5 (the direct callers join the queue) |
| F6 (1) covers date-poll, forum and reminder budgets that bypass it | 2: all three insert into the queue (poll `planning_v2_notify_poll`, forum `queue_forum_activity_notifications` / `notify_quiet_topic`, reminders `generate_reminder_notifications`); the guard is on the table |
| Recipient's local zone | 1 (column, setter, resolver, reporter) |
| Owner D1 alarms not deferred | 2 (exempt list; contract §2) |
| Owner D2 overnight chat collapse at 08:00 | 2 (collapse; §5), 3 (cancel on read) |
| Owner D3 user-level zone column | 1 |
| F6 (2) counter, flag, client fetch removed; gate | 6 (migration, Dart, SQL absence block, `no_streak_counter_gate_test`) |
| F6 (3) Mirror flag removed | 7 |
| F8 (1) widget / Live / mirror "Next plan" by default, titles per surface | 8 |
| F8 (4) no event titles in push copy | 4 (guard, summary, poll; sweep) |

**Type and name consistency**
- `notification_recipient_tz(uuid)`: Task 1 produces it; Task 2 consumes it.
- `quiet_chat:` key: Task 2 produces it; Task 3 asserts it and clears it.
- `'Open Attune to see it.'` is identical in Tasks 2, 4 and the contracts.
- `widgetTitlesKey` / `liveTitlesKey` / `mirrorTitlesKey` and `togetherSurfaceTitlesProvider` are spelled the same in the data layer, providers, sheet, screen and tests.
- `enqueuePush` has the same shape in Task 5's helper, its tests and the four call sites.

**Placeholders:** none. Every migration, contract, Dart and TS file carries its full text, and every step has a command and an expected result. Three steps give a bounded "if the fixture is refused, add only the named column and record a ruling" fallback for tables whose triggers the read-only maps could not see (`partner_presence`, the Mirror game tables, the Together RPC payloads).

**Recorded design decisions (for the reviewer)**
- The quiet guard is a table trigger, not worker logic. It covers every inserter and every return to `pending` with one rule. The worker is unchanged (and stays the only OneSignal caller).
- The copy guard rewrites only fields that are a plan's title, by push type. Composite sentences (summary, poll) are fixed in their generators. Names stay in titles.
- Deferral uses the recipient's zone at insert or retry time. A zone change after a row is deferred does not move it again: the row goes out at the 08:00 that was computed.
- Cancel-on-read covers any pending chat push for that conversation, not only deferred ones. A push still in the 1-minute queue for a conversation just read is moot too.
- Timed Together generators still read `planning_member_settings` for their own windows (countdown ≥ 08:00, reminders ≥ 09:00, summary 08:00–10:00). Switching them to `notification_recipient_tz` is a follow-up, not this plan.
