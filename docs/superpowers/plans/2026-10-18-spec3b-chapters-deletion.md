# Spec 3b: Chapter-scoped data and provable deletion. Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:**
- Nothing from a former relationship ever reaches a later partner.
- After archive, nothing from the archived relationship is readable by either former partner.
- Deleting an account deletes that person's own data and media, provably.
- An archived relationship is hard-deleted 12 months after archive, unless it is on legal hold.

**Architecture:**
- **The read gate.** 3a's `relationship_chat_open(rel)` becomes the read gate for every class-D content path in the audit (`spec3-map.md` §F). It is true only for a member, while the relationship is not archived, inside the 30-day window, and not sealed by the caller.
- **Deletion routines.** Two server routines, both SECURITY DEFINER and service-role only, built on a storage enqueue step:
  - `prepare_account_deletion(user)` runs before `auth.admin.deleteUser`.
  - `purge_relationship(rel)` is run by a daily job for relationships archived at least 12 months ago, and immediately for a relationship whose two members have both deleted their accounts.
  - Storage objects are queued in `media_deletion_queue` before the rows that point at them disappear: by BEFORE DELETE triggers, plus enumeration by path prefix.
- **Canary.** A SQL canary (two former partners and one new partner) proves no cross-chapter row is readable. A delete-then-re-register test proves that nothing resurfaces.

**Spec:** `06-synthesis-roadmap.md`:
- F13 (1) to (3);
- F1 (7) (12-month deletion, legal hold);
- the Spec 3 row (CI canary, delete-then-re-register).

`05` D.2 and D.3 #1 and #2.

**Map:** `.superpowers/sdd/spec3-map.md`, sections F and G, plus the "Spec3b-pre" lines.

## Rulings

- **R3b-1. Closing reads after archive (D.2 "inaccessible to both").** Every class-D table read policy and every class-D read RPC also requires `public.relationship_chat_open(<rel>)`.
  - Exception: the `relationships` row itself. Its clients need it to know the state, and its column-level SELECT already hides who did what.
  - Writes are unchanged; they already need `active`.
- **R3b-2. Personal insights and translator logs are the user's own** (D.2 "retained for the user; deleted with the account").
  - `relationship_id` becomes nullable with `ON DELETE SET NULL`, so the 12-month purge keeps them, unattached.
  - The client already filters both by the active or conversation relationship.
  - The Healing portrait reads only `journey.relationship_id`'s insights.
- **R3b-3. The 12-month purge.**
  - Add `relationships.legal_hold boolean NOT NULL DEFAULT false`. Only `service_role` writes it.
  - The daily cron `purge_archived_relationships` (`'41 3 * * *'`) calls `purge_relationship(rel)` for each relationship matching `status='archived' AND chat_archived_at <= now() - interval '12 months' AND NOT legal_hold`. It also purges any relationship whose `user_a` and `user_b` are both NULL (both accounts deleted), whatever its status.
  - `purge_relationship`:
    - queues every storage object of the relationship (see R3b-5);
    - deletes the `relationships` row, and the 61 cascading tables go with it;
    - keeps the survivors by FK: anonymised `safety_events`, dating exclusions, `healing_journeys`, `healing_ending_snapshots`, and per R3b-2 personal insights and translator logs.
- **R3b-4. Account deletion: "deletion is deletion" for the person's own data** (D.3 #1). `prepare_account_deletion(p_user)`, run first by `delete-account`, does the following for every relationship the person belongs to:
  1. If it is `active` or `paused`, end it as that person (`relationship_end_internal(rel, p_user)`). No push; the partner gets the 30-day window over what remains.
  2. Delete that relationship's derived and shared-answer data at once, because it cannot be split by person: game sessions (rounds, answers and Love Map rounds go with them), 36Q journeys and chapter reflections, mirror truth and scores, `patterns`, `pulse_scores`, `verdicts`, `analysis_sessions`, `attachment_compatibility_cache`, `ask2_state`.
  3. Queue the person's own media: the sent messages' media and thumbnails, streak clips and dating photos. Journal and story media are already queued by their triggers when rows cascade.

  Then `auth.admin.deleteUser` cascades the user-keyed rows: the person's messages, stories, journal, quiz and psych data, insights and Healing.

  What stays for the partner until their window closes and the 12-month purge: their own messages, and the relationship's Planning and Together items. These are shared artefacts that "follow the relationship" (D.2).

  The five `NO ACTION` user FKs, which block `deleteUser` today, become `SET NULL`: `game_session_rounds.active_partner_id`, `game_sessions.current_turn_user_id`, `game_sessions.winner_user_id`, `poll_votes.user_id` and `post_polls.created_by`. `poll_votes.user_id` is `CASCADE`, because a vote is the person's own.
- **R3b-5. Storage is queued, never orphaned.** New BEFORE DELETE triggers call `queue_media_deletion`:
  - `messages`: `media_url` and `media_thumbnail_url` in `message-media`;
  - `streak_clips`: `media_url`;
  - `dating_profile_photos`: `storage_key` in `dating-profile-photos`;
  - `relationships`: `chat_avatar_url` and `chat_avatar_thumbnail_url` in `relationship-avatars`.

  `purge_relationship` also queues, by prefix from `storage.objects`:
  - `planning-media` `'<rel>/%'`;
  - `story-media` `'story-media/<rel>/%'`;
  - `relationship-avatars` `'relationship-avatars/<rel>/%'`.

  The story trigger already handles `story-archive/<id>`.
- **R3b-6. Audit security bugs are fixed here.**
  - `get_thirty_six_seen_map` checks membership and opens through `relationship_chat_open`.
  - `analysis_sessions` gets `ENABLE ROW LEVEL SECURITY` with no client policy, plus a client REVOKE, if no `lib/` read exists.
  - `generate-thirty-six-reflection` requires a user JWT and checks that the caller is a member of the journey's relationship, through a user-scoped read of the journey under RLS, before using the service role.
- **R3b-7. The copy says what happens.** The delete-account confirm adds: "Your shared space ends; your messages and photos are removed from it."

## Global Constraints

As in Spec 3a:
- Work on main with no commits.
- Never format pre-existing files.
- Scratch DB `attune_spec3a`.
- New SECURITY DEFINER functions use `SET search_path = ''`, qualified names and `REVOKE … FROM PUBLIC, anon, authenticated`; grant to `service_role` only where an edge function calls them.
- Grants go in a `*_grants.sql` migration, replayed locally.

## Review Focus

1. The canary covers every table with a `relationship_id` the client can SELECT, discovered dynamically rather than from a hand list.
2. `deleteUser` succeeds for someone who has played every game type and voted in a poll. It runs as `DELETE FROM auth.users` in the test.
3. After account deletion, the ex keeps no shared-answer rows that contain the deleted person's answers.
4. The purge never touches a relationship on legal hold, nor an archived one younger than 12 months.
5. Media is queued before its row is deleted, for every bucket.

---

### Task 1: Deletion and purge (SQL)

**Files:**
- `supabase/migrations/20261018110000_chapters_deletion.sql`
- `20261018110100_chapters_deletion_grants.sql`
- `supabase/tests/account_deletion_contracts.sql`
- `supabase/tests/relationship_purge_contracts.sql`

- [ ] **Step 1: Contracts first.**
  - **`account_deletion_contracts`.** User D has a phone, active relationship R with partner P, and a past archived relationship R0 with Q. D holds:
    - messages with media in R;
    - a streak clip;
    - a dating photo;
    - a journal entry;
    - personal insights in R and R0;
    - quiz responses;
    - a 36Q journey with answers;
    - a Love Map round in R;
    - a game with `active_partner_id`, `current_turn_user_id` and `winner_user_id` set to D;
    - a poll vote and a poll;
    - patterns and pulse for R.

    The test calls `prepare_account_deletion(D)` and then `DELETE FROM auth.users WHERE id = D`. That DELETE must not fail. Then it asserts:
    - R is `ended`, with `ended_by` NULL (D is gone) and `ended_at` set;
    - no game, journey, round, answer, pattern, pulse or verdict rows remain for R or R0;
    - D's messages are gone and P's remain;
    - `media_deletion_queue` holds D's message media and thumbnail, the clip and the dating photo;
    - no row in any table references D (dynamic over every FK column to `users` / `auth.users`);
    - re-register: a new auth user with D's phone reads zero rows from every personal table and sees no relationship;
    - P's dating exclusion row still holds D's phone HMAC, as intended.
  - **`relationship_purge_contracts`:**
    - R1 archived 13 months ago → after `purge_archived_relationships()` the relationship and its messages are gone. Its storage objects (planning and avatar by prefix, and message media) are queued. `personal_insights` rows survive with a NULL relationship.
    - R2 archived 11 months ago → untouched.
    - R3 archived 13 months ago with `legal_hold` → untouched.
    - R4 with both users NULL → purged.
    - The cron is scheduled.
    - Internal functions are not executable by clients.
- [ ] **Step 2:** Run both contracts. Expected: FAIL.
- [ ] **Step 3:** Write the migration as in R3b-2 to R3b-5:
  - FK changes;
  - `legal_hold`;
  - the four media triggers;
  - `relationship_queue_storage(rel)`;
  - `purge_relationship(rel)`;
  - `purge_archived_relationships()` with its cron;
  - `prepare_account_deletion(uuid)`.

  Then the grants. Grant `prepare_account_deletion` EXECUTE to `service_role` only.
- [ ] **Step 4:** Run the contracts (GREEN), the full SQL suite (fail set = baseline), and these mutants:
  - (a) the purge skips the legal-hold test;
  - (b) the messages media trigger is dropped;
  - (c) `prepare_account_deletion` skips the game delete.

### Task 2: Reads close at archive, the canary, the security bugs (SQL)

**Files:** `20261018110200_chapter_reads.sql` and `supabase/tests/chapter_canary_contracts.sql`.

- [ ] **Step 1: Write the canary.** Setup:
  - A and B share R1, which is ended and then archived through the 3a path (new chapter).
  - A and C share R2, active.
  - Representative R1 rows are seeded: a game session and rounds, 36Q answers, a Love Map round, mirror truth, pulse, patterns, a timeline event, a reminder, a family member, `ask2_state` and the compatibility cache.

  Checks:
  - **Dynamic loop:** for every public table with a `relationship_id` column on which `authenticated` holds any SELECT privilege, count rows `WHERE relationship_id = R1` as C, as A and as B. Each must be 0, except for `relationships` itself, `personal_insights`, `translator_logs` and `healing_ending_snapshots` (own rows only, by design).
  - The class-D RPCs called with R1 ids return nothing or raise not-found for A, B and C. These are `get_revealed_round`, `session_game_round_state`, `this_or_that_round_state`, `get_paint_ball_session_state`, `get_snakes_session_state`, `get_word_hunt_state`, `get_paint_ball_history` and `get_thirty_six_seen_map`.
  - Within R1's window (before the archive), A and B can read and C cannot.
  - `analysis_sessions` has RLS on.
- [ ] **Step 2:** Run it. Expected: FAIL.
- [ ] **Step 3:** Migration: restate every class-D policy in `spec3-map.md` §F verbatim, adding `AND public.relationship_chat_open(<rel>)`. For the RPCs, add a first-statement guard that raises the function's existing not-found error, or returns empty, when the relationship isn't open. Also:
  - fix `get_thirty_six_seen_map`;
  - enable RLS on `analysis_sessions` and revoke client grants on it;
  - check `lib/` for reads with `grep -rn "analysis_sessions" lib`.
- [ ] **Step 4:** Run GREEN, the full suite, and the game contracts in particular (live games are unaffected). Mutant: drop the guard from one game policy.

### Task 3: Edge functions

- [ ] **`delete-account`:** call `rpc('prepare_account_deletion', {p_user_id})` with the service role before `deleteUser`. If it fails, record `failure_reason` and stop: the account is not deleted half-way. Deno source test: the RPC call comes before `deleteUser`.
- [ ] **`generate-thirty-six-reflection`:** require a user (`requireUser`) and read the journey through a user-scoped client, so RLS proves membership. Return 404 when it isn't found. Deno source test.
- [ ] **`generate-healing-portrait`:** personal insights `.eq("relationship_id", journey.relationship_id)` when the journey has one; none otherwise. Pure helper plus a Deno test.

### Task 4: Client copy and docs

- [ ] The delete-account confirm copy (R3b-7), test-first. The manual FAQ "What happens to my data if I delete my account?" and the 12-month archive deletion, test-first.

### Task 5: Full runs, hand-off, review

- [ ] Full `flutter test` and SQL suite, plus the Deno tests.
- [ ] Hand-off:
  - push the migrations, together with 3a. 3b lifts 3a's release gate;
  - deploy `delete-account`, `generate-thirty-six-reflection` and `generate-healing-portrait`;
  - staging: delete a test account that played games and voted in polls → no error, and its media appears in the queue and drains.
- [ ] Final Fable review, then one fix pass.

---

## Plan review amendments (Fable, 2026-10-18): BINDING, applied during execution

Review: `.superpowers/sdd/2026-10-18-spec3b-plan-review.md`. It found 3 Critical, 6 Important and 9 Minor issues.

- **C1.** `poll_votes.user_id` and `post_polls.created_by` are NOT NULL, so they use `ON DELETE CASCADE`. This replaces the plan's SET NULL.
- **C2.** The canary's table set is discovered: tables with `relationship_id`, plus every table with an FK chain to sessions, rounds or journeys.
  - A required-table guard means a schema change can't silently shrink that set.
  - A static check proves every SELECT and ALL policy in the set is gated. Own-row policies (`user_id = auth.uid()`) are allowed.
  - The FOR ALL policies are split, and their self branches are gated.
- **C3 / I4: live exposure.** New migration `20261017230000_security_lockdown.sql`, timestamped before 3a so it can be applied on its own:
  - `analysis_sessions` gets RLS on and a client revoke; it was readable with the anon key;
  - client writes to the tag tables are revoked;
  - six 36Q and import functions lose their default PUBLIC and anon execute;
  - `remove_import_derived_evidence` is revoked from authenticated too.
- **I1.** `prepare_account_deletion` keeps `pulse_scores`, `verdicts` and `patterns`, which are role-free and exportable by the partner. It deletes games, journeys, `analysis_sessions`, the compatibility cache, `ask2_state` and the seen tables. The partner's own game answers go with the shared sessions (D.3 #1 over D.2). The delete-account e-mail and confirm copy are corrected.
- **I2.** Game write policies require `active`. A BEFORE INSERT/UPDATE guard trigger on each game table covers the SECURITY DEFINER write RPCs. The service role and nested triggers are exempt.
- **I3.** `generate-thirty-six-reflection` takes a user JWT, reads the journey as the caller and returns 409 unless the space is active.
- **I5.** Upload intents are queued for deletion. The deletion contract also asserts:
  - safety events are anonymised;
  - the partner's dating exclusion survives;
  - no column without an FK still names the deleted person.
- **I6.** `prepare_account_deletion` is idempotent. A failed `deleteUser` leaves the person's shared spaces ended; a retry is safe, and the failure is recorded in `failure_reason`.
- **Read RPCs.** Each is wrapped generically: the original becomes `<name>__ungated`, and the wrapper answers a closed chapter exactly as the function answers someone who was never a member.
