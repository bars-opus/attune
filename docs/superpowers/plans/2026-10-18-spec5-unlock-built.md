# Spec 5: Unlock what is built, safely. Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make the already-built quizzes, the Ask-2 moment, Stories realtime, the couple map, the waiting period and the weekly check-in reachable and safe:
- no pairing or typology statement anywhere (F9);
- quizzes that describe a person, not a type (A2);
- the waiting and day-7 flows the spec promises (A6);
- the Sunday check-in reminder (A7);
- the first accessibility gate (F16, the parts outside Planning);
- the docs reconciled (A10, MASTER_SPEC only).

**Spec:** `06-synthesis-roadmap.md`, rows F9 (:146), F16 (:153), A1–A3, A6, A7 and A10 (:182–191). Also §8.6, §8.7, §8.9 and §8.11. **Map:** `.superpowers/sdd/spec5-map.md`.

## Rulings

- **R5-1. Owner-only files are not touched.** That covers `lib/features/planning/**`, `test/features/planning/**`, `ATTUNE_SOUL.md` and `ATTUNE_THESIS.md`. Therefore:
  - the Planning-block accessibility items (Dynamic Type in the ribbon and blocks; Semantics on 4 block types) go in an owner list;
  - stale SOUL/THESIS lines (compatibility preview, the 48-hour plan) go in the same list;
  - A10 changes MASTER_SPEC only.
- **R5-2. F9 reward.** The Ask-2 reveal becomes:
  - "You're both in";
  - two of the person's **own** anchors reflected back, using prompts 1 and 2: what they admire, and what they hope for more of. The third (past patterns) is personal and not shown on a celebratory screen;
  - "Something for tonight", with one button to a Love map round and one to This or That.

  The partner's anchors are never read (own-row RLS stays).
- **R5-3. Pairing output is removed, not hidden.**
  - Delete `attachment_compatibility_service.dart`, `compatibility_section.dart` and the compatibility providers.
  - Pulse's quiz row subtitle no longer says "how your styles fit together".
  - A migration revokes `upsert_attachment_compatibility_cache` from clients and empties the cache. The table stays for the purge and deletion contracts, and is never written again.
  - An architecture grep test forbids pairing strings in `lib/`.
- **R5-4. Attachment caveat**, fixed text on every attachment result surface: "Written for a general population; if you're autistic or ADHD some items may not fit." Results stay dimensional; the existing spectrum bars remain the primary display.
- **R5-5. "What feels loving to me right now"** replaces the love-language quiz.
  - Five expressions: words, time, help, touch, small gifts. For each, a rating: not really / a little / a lot.
  - An optional context tag: stressed, sad, celebrating, everyday.
  - Multi-select and changeable at any time.
  - No primary/secondary and no "your love language is".
  - Labelled "Based on a popular framework, not a science."
  - Stored as `quiz_responses` `quiz_type='love_language'` with `version=2`; old rows still render through a v1 view.
  - Shared only by the existing explicit quiz share.
  - `generate-verdict` stops reading `love_languages` (§8.7: never a compatibility input).
- **R5-6. Clinical gate.** A new `feature_flags` key, `quiz_clinical_signoff` (default **false**), gates the communication and conflict quizzes' entry tiles and routes ("Coming soon"). Where a shared comparison shows, the copy is "Where you differ", never "growth area".
  - Owner's "flag everything on for testing": the flag is seeded false in the migration and set true by a separate dev-only SQL snippet, `supabase/sql/dev_enable_spec5_flags.sql`, which is never a migration.
- **R5-7. Know yourself.** `KnowYourselfSection` mounts on the profile screen, for the person's own profile only. It shows the four quizzes, with communication and conflict behind R5-6.
- **R5-8. Verdict stays unrouted** (A3). Every user-facing "Verdict" string becomes "Monthly readout". The MASTER_SPEC `[OPEN]` is resolved per Decision 32.
- **R5-9. 48-hour gate** (MASTER_SPEC :2098).
  - Before 48 hours: the waiting step says "We'll suggest a private reflection space if this takes a little while."
  - From 48 hours: the reflection-mode card appears.
  - Journal entries are private by construction (no share mechanism exists), so the "keep private or share" prompt is a plain line: "Your reflections stay private to you."
  - Ruling: no share flow is invented.
- **R5-10. Day-7 pivot** (MASTER_SPEC :2105). After 7 days pending, a card offers:
  - "Keep waiting": renew the invite with `forceNew`;
  - "Use Attune on my own for now": switch to personal mode;
  - "Invite someone else": a new invite, `forceNew`.
- **R5-11. Weekly check-in reminder** (A7).
  - A pure SQL generator, `generate_checkin_reminders(p_now)`, runs hourly (`'5 * * * *'`). It enqueues a `scheduled_notifications` row for each member of an `active` relationship when all of these hold:
    - their local time (`notification_local_zone`) is Sunday 18:00–18:59;
    - they have no check-in for that week;
    - no reminder has gone out for that week (`source_key` `checkin:<user>:<week>`).
  - Quiet hours apply automatically.
  - Copy: title "Weekly check-in", body "A minute to look back on your week." It names nobody.
  - The `send-checkin-reminders` edge function stays unscheduled; ruling: SQL is the scheduler, like the other generators.
- **R5-12. Stories realtime** (A1). `story_change_signals` is added to `supabase_realtime`, with the publication test extended. The couple map flag `couple_map_enabled` is turned on by the dev snippet (R5-6), not by a migration.
- **R5-13. Accessibility** (F16, outside Planning):
  - `BottomSheetHeader`'s action gets a 44×44 minimum tap area. This is a wrapper in the header, not a change to `AppTextButton`'s shared shrink-wrap.
  - The `InfoRowWidget` default subtitle alpha rises to reach 4.5:1 on light and dark surfaces.
  - Together agenda and ritual rows use 2 title lines and 3 subtitle lines when text scale is above 1.3.
  - Game grid tiles use scalable text and a minimum height instead of a fixed aspect ratio when text scale is above 1.3.
  - `stagger.dart` respects reduced motion.
  - A guideline test (tap target, labels, contrast) covers the Together agenda, a ritual card and the game grid.

## Global Constraints

As for Specs 2 and 3: work on main with no commits; format only new files; scratch DB `attune_spec3a`; grants in grants files.

## Review Focus

1. No pairing name, pairing description, "natural strength", "area to watch" or type-about-the-couple sentence is reachable: screen, push, chat card, docs or export.
2. The Ask-2 reveal shows only the person's own anchors, and never the third.
3. The check-in reminder fires once per person per week, at 18:00 local on Sunday, never during quiet hours, and names nobody.
4. Opening the app 47 h vs 49 h after inviting shows the right waiting state; day 7 shows the pivot. Time comes from the invite's created time on the server, not from the device.
5. Old v1 love-language results still display, in the new non-typology form.

---

### Task 1: F9: reward, caveat, pairing removal

- [ ] Tests first:
  - `ask2_reveal_step_test` (own anchors 1–2 shown, not 3; the tonight buttons route);
  - attachment result and partner result caveat tests;
  - `test/architecture/no_pairing_strings_test.dart`, which scans `lib/` for `pairingName`, `pairingDescription`, `natural_strength`, `naturalStrength`, `watchArea`, "attachment pairing", "how your styles fit together" and "compatibility preview";
  - SQL `quiz_compatibility_retired_contracts` (the RPC is not executable by clients; the cache is empty).
- [ ] Implement R5-2, R5-3 and R5-4:
  - migration `20261018130000_retire_attachment_pairing.sql` plus grants;
  - fix the docs strings in `attachment_quiz_docs.dart`.

### Task 2: A2/A3: quizzes and naming

- [ ] Tests first:
  - the v2 love-language model, its scoring and its result screen (no "primary", the framework label, context tags, changeable);
  - v1 rows render through the adapter;
  - the clinical flag hides communication and conflict entries and routes;
  - `KnowYourselfSection` is mounted on the own profile only;
  - no "Verdict" in user-facing strings (grep test over `lib/app/documentations` and `lib/features/verdict/presentation`);
  - a Deno source test that `generate-verdict` does not select `love_languages`.
- [ ] Implement R5-5 to R5-8. Migration `20261018130100_quiz_clinical_flag.sql` seeds the flag false.

### Task 3: A6/A7/A1: waiting, day 7, check-in reminder, Stories realtime

- [ ] Tests first:
  - waiting-step states at 47 h and 49 h, and the day-7 pivot with its three actions (fake invite service);
  - SQL `checkin_reminder_contracts`:
    - Sunday 18:30 local enqueues once;
    - a second run in the same hour adds nothing;
    - 17:59 enqueues nothing, and nor does Monday;
    - someone who already checked in is skipped;
    - a paused relationship is skipped;
    - the copy names nobody;
    - a night-zone recipient is deferred by the quiet guard;
  - `realtime_publication_test` includes `story_change_signals`.
- [ ] Implement R5-9 to R5-12:
  - `get_my_invite_age()`, or extend the waiting step's existing invite read with `created_at`, so time comes from the server;
  - migrations `20261018130200_checkin_reminders.sql` and `20261018130300_story_signals_realtime.sql`;
  - the dev snippet.

### Task 4: F16 and A10

- [ ] Tests first: a guideline test for agenda rows, ritual rows and game tiles at text scale 2.0 (no overflow, at least 44 dp targets, labels); a header tap-target test; a contrast test for the `InfoRowWidget` subtitle.
- [ ] Implement R5-13. MASTER_SPEC edits:
  - mark Gemini as the provider where the spec names Claude for runtime AI;
  - resolve the `[OPEN]` on verdict language;
  - rename §8.5 "Insights & Verdict" to "Insights & Monthly readout";
  - replace the stale "compatibility preview" lines with the F9 reward;
  - note 48-hour and day-7 as implemented.
- [ ] Owner list in the ledger: Planning accessibility items and SOUL/THESIS stale lines (R5-1).

### Task 5: Runs, review

- [ ] Full Flutter, SQL and Deno runs. Final Fable review. One fix pass.

---

## Plan review amendments (Fable, 2026-10-18): BINDING

Review: `.superpowers/sdd/2026-10-18-spec5-plan-review.md`. It found 6 Critical, 11 Important and 9 Minor issues.

- **C1.** Love-language v2 is marked by `result_data.instrument_version = 2`, the conflict quiz's existing key. `version` stays the retake counter. One adapter reads both shapes, from `quiz_responses` and from `psych_profiles.love_languages`.
- **C2.** Day 7, "Use Attune on my own for now": a new RPC, `withdraw_my_pending_invites()`, deletes the caller's own never-accepted pending rows. With no pending row, the existing mode sync resolves to personal mode.
- **C3.** Invite age comes from `get_my_invite_age()`, which returns `now() − min(created_at)` over the caller's pending rows, expired ones included. A re-mint therefore never resets the clock.
- **C4.** "Keep waiting" is a plain `createInvite()`: it returns the live invite or mints one. It is not `forceNew`.
- **C5.** Check-in reminder:
  - it is skipped when the person has a check-in submitted in the last 6 days;
  - its `source_key` uses the local Sunday date;
  - fixtures cover America/Chicago and Pacific/Honolulu;
  - people with an unknown zone are skipped (I9).
- **C6.** The pairing grep test scans `lib/**/*.dart` only, with word-bounded patterns. Also delete `attachment_compatibility.dart` and the "See how your styles compare" share copy.
- **I1.** The clinical flag is read through the `ChatFeatureFlags` shape. The communication and conflict routes stay registered, and their builders show "Coming soon" while the flag is off.
- **I2/I3.**
  - The partner love-language screen and the share push copy lose their typology.
  - F9 (3) says the attachment result is self-facing, so the partner's view of an attachment share is retired, along with the share action for attachment (ruled).
- **I4.** A Continue button stays before 48 h. The 48-hour card and the day-7 pivot also appear on `ChatCouplesLockedScreen`.
- **I5.** The header action's tap area is 44 dp without growing the header (padding is rebalanced). This is asserted in a header test.
- **I6.** A new `OpacityTokens.secondaryText = 0.64`, used only in the `InfoRowWidget` subtitle.
- **I7.** `stagger.dart` already respects reduced motion; this is a test only.
- **I8.** `send-notification`'s `checkin_reminder` copy names nobody. The generator's metadata carries `type: 'checkin_reminder'` so the tap routes correctly.
- **I10.** The retire migration also revokes client INSERT, UPDATE and DELETE (authenticated) and SELECT (anon) on the cache table.
- **I11.** The Verdict grep matches string literals in the docs data files and the verdict presentation layer.
