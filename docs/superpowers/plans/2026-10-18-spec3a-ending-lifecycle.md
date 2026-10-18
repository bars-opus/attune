# Spec 3a — Ending v2: lifecycle (pause, no-push ending, read-only window, seal, archive) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ending a relationship never notifies the other partner. `paused` becomes a real state. After ending, both people get a 30-day read-only window, each can seal their own side, and archiving happens on schedule.

**Architecture:**
- **Server (one choke point).** All lifecycle transitions live in SECURITY DEFINER RPCs. A single read helper, `relationship_chat_open(rel)`, replaces the `chat_archived_at IS NULL` test on every chat read path, so a per-person seal holds everywhere. A daily cron closes windows. A trigger archives the old chapter when either person starts a new relationship.
- **Client (existing surfaces).** Paused, ended and archived all stay in `OnboardingMode.personal`, and the couples-locked chat screen becomes the lifecycle hub. It offers read-only chat, resume or end, and seal, and shows a one-time warm ending sheet. Nothing new is added to the mode enum.

**Tech Stack:** Supabase Postgres 17 (RLS, SECURITY DEFINER, pg_cron), Deno edge function, Flutter 3.29 / Riverpod 2.6 / go_router 10.

**Spec:** `docs/superpowers/research/2026-10-16-couples-research/06-synthesis-roadmap.md`, row F1 items (1)–(4) and (6) and the Spec 3 row. Also `05-scenarios-strain-risk.md` Part D (D.1 states, D.2 data classes, D.3 rules, D.4 Healing). Code map: `.superpowers/sdd/spec3-map.md`, including section F, the read-access audit.

**Split.** Spec 3 is delivered as three plans:
- **3a (this plan):** lifecycle.
- **3b:** chapter scoping, provable deletion, the 12-month hard delete, closing the class-D read paths after archive, and the two audit security bugs.
- **3c:** export (F1 (5)).

The "Download what we shared" button is added by 3c. 3a leaves a slot for it.

## Rulings in this plan (confirm at review)

- **R3-1. States.** `status` gains `'archived'`. The transitions follow D.1:
  - `active → paused`: either member.
  - `paused → active`: either member (D.1 says "either").
  - `active|paused → ended`: either member.
  - `paused` for 30 days with no decision → `ended`, with `ended_by` NULL (system).
  - `ended → archived`: 30 days after `ended_at`, or once both members have sealed, or immediately when either member's new relationship becomes active.
- **R3-2. No transition sends a push, SMS or email.**
  - The end-relationship edge function's `enqueuePush` is removed.
  - Pending `scheduled_notifications` whose `metadata->>'relationship_id'` is the relationship are set to `cancelled` at pause, end and archive.
  - Rows without that metadata key are personal (self-set alarms) and are kept.
  - No new trigger is added on `scheduled_notifications`: generators already require `status='active'`.
- **R3-3. The read-only window covers chat only, live.** This is chat plus pins, reactions, edit history, streak clips, place updates, chat imports and message media (audit class A).
  - Stories, Planning, Together, games and Pulse stay closed at `ended` (class B, `status='active'`). They become reachable through export (3c).
  - D.2 asks for read-only Planning and stories in the window. Export is how 3a meets that. Cost: no live browsing of plans during the window.
- **R3-4. Seal.** "Seal my side now" is per person, inserted into `relationship_seals`. It ends that person's chat reads immediately; the other's window continues. A second seal archives (`both_sealed`). Sealing cannot be undone.
- **R3-5. Window precision.** `relationship_chat_open` itself tests `ended_at > now() - 30 days`. Access ends on time even when the cron runs late. The cron only flips the status.
- **R3-6. New relationship archives the old chapter.** An AFTER UPDATE trigger on `relationships` fires `pending → active`. It archives every `ended` or `paused` relationship of either new member with reason `partner_new_relationship`; a paused one is ended first, with no push. It is a trigger, not edge-function code, so every activation path is covered.
- **R3-7. Backfill.** Existing rows with `status='ended' AND chat_archived_at IS NOT NULL`, which were archived instantly by the old `end_relationship`, become `status='archived'` with their reason kept.
- **R3-8. Healing Stage 2 snapshot (D.4 (a)).** At `ended`, each non-null member gets a row in `healing_ending_snapshots(user_id, relationship_id, pattern_types text[], taken_at)`.
  - The row holds at most 6 non-safety `patterns.pattern_type` values, the same query `generate-healing-post-mortem` makes today.
  - It is user-owned (FK to users ON DELETE CASCADE) and has **no** FK to `relationships`, so it outlives the relationship's 12-month deletion.
  - The post-mortem function reads the snapshot first and falls back to live patterns.
  - `start_healing_journey` accepts `ended` or `archived`.
- **R3-9. One lifecycle read for the client.** `get_my_relationship_lifecycle()` returns the caller's latest non-pending relationship when it is `paused`, `ended` or `archived`, and nothing when it is `active`. The fields are:
  - `relationship_id`, `status`, `partner_first_name` (first word of `display_name`);
  - `ended_by_me`, `paused_by_me`;
  - `ended_at`, `window_ends_at`, `paused_at`, `decide_by`;
  - `sealed_by_me`, `chat_readable`.

  It never returns who sealed on the other side, or whether they did.
- **R3-10. Client modes are unchanged.** `resolveModeFromRelationshipStatus` keeps mapping paused, ended and archived to `personal`. `ChatCouplesLockedScreen` hosts the `RelationshipLifecycleCard` and, once per relationship, the warm `RelationshipEndedSheet` for the person who did not end it.
- **R3-11. Device surfaces stop at `paused` and `ended`, not at archive** (F1 (6)).
  - On the ender's phone this already happens in `EndRelationshipAction`.
  - On the other phone, the hub calls `clearTogetherDeviceSurfaces()` once per relationship the first time it sees a non-active lifecycle.
  - Server-side, ICS and calendar, presence, On this day and countdowns are already class B. The revoke and purge triggers fire on leaving `active`.
- **R3-12. Reopen within 90 days (D.1, roadmap D3) is out of scope.** It is a Phase D moonshot.
- **R3-13. Copy says what happens.**
  - Ending tells both people that the chat stays readable for 30 days and is deleted 12 months after it closes. The 12-month job ships in 3b, in the same release.
  - No reason field and no reply affordance.
  - The other partner is named only by first name, and only in the ending sheet.

## Global Constraints

- Work on `main`; no commits unless the owner asks. Never `dart format` pre-existing files (format new files only). Never touch `lib/features/planning/**`, `test/features/planning/**`, `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`.
- Scratch DB `attune_spec3a` (`ATTUNE_TEST_DB=attune_spec3a scripts/local_pg_setup.sh`); never `attune_test`. New grants go in a `*_grants.sql` migration and are replayed in `scripts/local_pg_grants.sql`.
- Every new SECURITY DEFINER function: `SET search_path = ''`, every relation schema-qualified, `REVOKE ALL … FROM PUBLIC, anon`, `GRANT EXECUTE … TO authenticated` (internal helpers: service_role only or none).
- Error codes: `lifecycle:not_found`, `lifecycle:not_active`, `lifecycle:not_paused`, `lifecycle:not_ended`, `lifecycle:sealed`.
- Copy (verbatim):
  - Pause confirm title "Pause your shared space?", message "Chat becomes read-only for both of you and nothing new is shared. Either of you can resume or end it within 30 days. Your partner won't get a notification.", button "Pause".
  - End confirm title "End your shared space?", message "You'll both be able to read your chat for 30 days, then it closes. Closed chats are deleted after 12 months. Your partner won't get a notification; they'll see it the next time they open Attune.", button "End".
  - Paused card: title "Your shared space is paused", body "Chat is read-only. {N} days left to decide." (N ≥ 1; "Less than a day left to decide." at 0), buttons "Read our chat", "Resume", "End".
  - Ended card (window open, not sealed): title "Your shared space has ended", body "You can read your chat until {date}. After that it closes, and 12 months later it is deleted.", buttons "Read our chat", "Seal my side now".
  - Seal confirm title "Seal your side now?", message "Your chat closes for you now. It can't be opened again.", button "Seal".
  - Ending sheet (other partner, once): title "{Name} has ended your shared space.", body "For 30 days you can read what you shared. After {date} it closes, and 12 months later it is deleted.", buttons "Read our chat", "Healing from a breakup?", "Support resources", "Close".
  - Dates via `MyDateFormat.toDate`.
- No feature flag: this replaces unsafe behaviour (the ending push) and is a safety floor item.

## Review Focus

1. A sealed member reads nothing through any class-A path: table, RPC, storage or realtime. Realtime uses the same RLS.
2. Day 30: access ends by the clock (R3-5) even if the cron hasn't run, and both people lose access at the same moment.
3. Ending from `paused` works, and the 30-day pause expiry ends with `ended_by` NULL. No copy says "{Name} ended" when the system did.
4. The new-relationship trigger never archives the relationship that just became active, and never touches other people's relationships.
5. Existing contracts that assert the old end-time archive are updated, not deleted: `chat_system_contracts`, `relationships_lockdown_contracts`, `dating_exclusion_wiring_test`, `story_places` and presence purge.

---

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/20261018100000_relationship_lifecycle_v2.sql` | Status and reason CHECKs, pause columns, backfill, `relationship_seals`, `healing_ending_snapshots`, helpers, RPCs, cron, new-relationship trigger, `start_healing_journey` restated |
| `supabase/migrations/20261018100100_relationship_lifecycle_grants.sql` | Grants (replayed locally) |
| `supabase/migrations/20261018100200_chat_reads_respect_seal.sql` | Restates class-A chat read policies, the message-media storage policy and the chat read RPCs on `relationship_chat_open` |
| `supabase/tests/relationship_lifecycle_contracts.sql` | Lifecycle contracts and mutants |
| `supabase/functions/end-relationship/index.ts` (+ `no_push.test.ts`) | No push; accepts paused |
| `supabase/functions/generate-healing-post-mortem/index.ts` | Snapshot first |
| `lib/features/relationships/domain/relationship_lifecycle.dart` | `RelationshipLifecycle` model plus pure copy helpers |
| `lib/features/relationships/data/relationship_lifecycle_service.dart` | + `pause`, `resume`, `seal`, `fetchLifecycle` |
| `lib/features/relationships/presentation/relationship_lifecycle_providers.dart` | `relationshipLifecycleProvider` |
| `lib/features/relationships/presentation/widgets/relationship_lifecycle_card.dart` | The hub card |
| `lib/features/relationships/presentation/widgets/relationship_ended_sheet.dart` | One-time warm sheet |
| `lib/features/relationships/presentation/widgets/pause_relationship_action.dart` | Pause confirm |
| `end_relationship_action.dart`, `chat_couples_locked_screen.dart`, `settings_data.dart`, `healing_repository.dart`, `relationship_mode_sync.dart` (test only) | Wiring |

---

### Task 0: Workspace and baseline

- [ ] Create the ledger and snapshots dir at `.superpowers/sdd/2026-10-18-spec3a-ending-lifecycle/`. Run `ATTUNE_TEST_DB=attune_spec3a scripts/local_pg_setup.sh > $WS/baseline-sql.txt` and record PASS/FAIL counts and the FAIL set. Copy `mutant.sh` from the Spec 2 workspace, retargeted to `attune_spec3a`. Flutter baseline: 3638.
- [ ] Find every contract that asserts the old end-time behaviour. Search `supabase/tests` for `end_relationship(`, `chat_archived_at` and `status = 'ended'`. List them in the ledger: each is updated in Task 1 step 6.

### Task 1: Lifecycle on the server (F1 (1), (3), (4); D.4 (a))

**Interfaces — Produces (SQL):**
- `relationship_chat_open(p_relationship_id uuid) RETURNS boolean`. STABLE SECURITY DEFINER. Uses `auth.uid()`.
- `pause_relationship(uuid)`, `resume_relationship(uuid)`, `end_relationship(uuid)` (restated) and `seal_my_side(uuid)`. All return `void`.
- `get_my_relationship_lifecycle()`. Returns `TABLE(relationship_id uuid, status text, partner_first_name text, ended_by_me boolean, paused_by_me boolean, ended_at timestamptz, window_ends_at timestamptz, paused_at timestamptz, decide_by timestamptz, sealed_by_me boolean, chat_readable boolean)`, 0 or 1 rows.
- Internal, no client EXECUTE:
  - `relationship_archive(uuid, text)`;
  - `relationship_cancel_pending_pushes(uuid)`;
  - `relationship_take_healing_snapshot(uuid)`;
  - `close_relationship_windows()`, scheduled daily `'23 2 * * *'` as `close_relationship_windows`.

- [ ] **Step 1: Write the contracts first.** File `supabase/tests/relationship_lifecycle_contracts.sql`, one transaction, fixtures in the `9b…` uuid range. It covers:
  1. **End enqueues nothing for the other member.** The other member's counts in `scheduled_notifications`, `in_app_notifications` and `message_notification_outbox` are unchanged. A pre-seeded pending row with `metadata.relationship_id` becomes `cancelled`.
  2. **After end:** `status='ended'`, `chat_archived_at IS NULL`, `ended_by` = caller. Both members SELECT the seeded message. INSERT into `messages` is refused for both.
  3. **Pause:**
     - by a member → `paused`, `paused_by` set; reads OK; writes refused;
     - pause by a non-member → `lifecycle:not_found`;
     - resume → `active` with the pause fields NULL;
     - end from `paused` → `ended`.
  4. **Seal:**
     - after A seals, A reads 0 messages, 0 pins and 0 reactions; `count_unread_messages` returns 0 for A; the message-media `storage.objects` SELECT is denied for A;
     - B still reads everything;
     - B seals → `archived`, reason `both_sealed`;
     - sealing an active relationship → `lifecycle:not_ended`;
     - a second seal by A is a no-op.
  5. **Window:**
     - with `ended_at = now() - 31 days` and the cron not yet run, `relationship_chat_open` is false for both;
     - `close_relationship_windows()` → `archived`, `window_closed`;
     - paused with `paused_at = now() - 31 days` → `ended`, `ended_by IS NULL`.
  6. **New relationship:**
     - A's ended relationship with B, plus A's new relationship with C going `pending → active` → the old one becomes `archived` / `partner_new_relationship`, and the A–C one stays `active`;
     - a third party's ended relationship is untouched;
     - A's paused relationship is ended and archived.
  7. **Healing:**
     - after end, each member has a `healing_ending_snapshots` row whose `pattern_types` excludes `severity='safety'` and holds at most 6 values;
     - `start_healing_journey(rel)` succeeds on `archived`.
  8. **Lifecycle read:**
     - B, after A ends: `ended_by_me=false`, `partner_first_name` = A's first word, `window_ends_at = ended_at + 30d`, `chat_readable=true`;
     - an active relationship → 0 rows;
     - A outsider → 0 rows.
  9. **Backfill:** a fixture inserted as `ended` with `chat_archived_at` set, then the backfill statement (copied from the migration) → `archived`.
  10. **Grants:** `anon` cannot execute any new RPC; `authenticated` cannot execute the internal helpers.
- [ ] **Step 2:** Run the contracts on `attune_spec3a`. Expected: FAIL at the first missing function.
- [ ] **Step 3: Write the migration** (key SQL below; write it in full).
```sql
ALTER TABLE public.relationships DROP CONSTRAINT IF EXISTS relationships_status_check;
ALTER TABLE public.relationships ADD CONSTRAINT relationships_status_check
  CHECK (status IN ('pending','active','paused','ended','archived'));
ALTER TABLE public.relationships DROP CONSTRAINT IF EXISTS relationships_chat_archived_reason_check;
ALTER TABLE public.relationships ADD CONSTRAINT relationships_chat_archived_reason_check
  CHECK (chat_archived_reason IS NULL OR chat_archived_reason IN
    ('partner_new_relationship','manual_end','window_closed','both_sealed'));
ALTER TABLE public.relationships
  ADD COLUMN IF NOT EXISTS paused_at timestamptz,
  ADD COLUMN IF NOT EXISTS paused_by uuid REFERENCES public.users(id) ON DELETE SET NULL;

UPDATE public.relationships SET status = 'archived'
WHERE status = 'ended' AND chat_archived_at IS NOT NULL;   -- R3-7

CREATE TABLE IF NOT EXISTS public.relationship_seals (
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  sealed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (relationship_id, user_id)
);
ALTER TABLE public.relationship_seals ENABLE ROW LEVEL SECURITY;
CREATE POLICY relationship_seals_self_read ON public.relationship_seals
  FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE TABLE IF NOT EXISTS public.healing_ending_snapshots (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  relationship_id uuid NOT NULL,           -- no FK: outlives the relationship (R3-8)
  pattern_types text[] NOT NULL DEFAULT '{}',
  taken_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, relationship_id)
);
ALTER TABLE public.healing_ending_snapshots ENABLE ROW LEVEL SECURITY;
CREATE POLICY healing_ending_snapshots_self_read ON public.healing_ending_snapshots
  FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.relationship_chat_open(p_relationship_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = p_relationship_id
      AND auth.uid() IN (r.user_a, r.user_b)
      AND r.chat_archived_at IS NULL
      AND (r.status IN ('active','paused')
           OR (r.status = 'ended' AND r.ended_at > now() - interval '30 days'))
      AND NOT EXISTS (SELECT 1 FROM public.relationship_seals s
                      WHERE s.relationship_id = r.id AND s.user_id = auth.uid())
  );
$$;
```
  - `relationship_cancel_pending_pushes(rel)`:
    - `UPDATE public.scheduled_notifications SET status = 'cancelled' WHERE status = 'pending' AND metadata->>'relationship_id' = rel::text`;
    - also `DELETE FROM public.message_notification_outbox WHERE relationship_id = rel` if that table has the column. Check in the dry run; otherwise rely on the worker's active check.
  - `relationship_take_healing_snapshot(rel)`:
    - inserts one row per non-null member, `ON CONFLICT DO NOTHING`;
    - `pattern_types` = `array(SELECT pattern_type FROM public.patterns WHERE relationship_id = rel AND severity <> 'safety' ORDER BY created_at DESC LIMIT 6)`. Check that the column names exist in the dry run.
  - `end_relationship(rel)`:
    - select `FOR UPDATE` where the caller is a member and `status IN ('active','paused')`, else `lifecycle:not_active`;
    - `UPDATE … SET status='ended', ended_at=now(), ended_by=v_user, paused_at=NULL, paused_by=NULL`. `chat_archived_*` is **not** set;
    - then cancel pushes and take the snapshot;
    - keep the dating-exclusion block verbatim, wrapped as today.

    The internal `relationship_end_internal(rel, actor uuid)` does the work, so the cron and the trigger reuse it with `actor` NULL.
  - `pause_relationship(rel)`: the caller is a member and `status='active'`, else `lifecycle:not_found` (not a member) or `lifecycle:not_active`. Sets `paused` and the pause fields, then cancels pushes.
  - `resume_relationship(rel)`: `status='paused'`, else `lifecycle:not_paused`. Sets `active` and clears the pause fields.
  - `seal_my_side(rel)`:
    - the caller is a member and `status='ended'`, else `lifecycle:not_ended`;
    - insert into `relationship_seals`, `ON CONFLICT DO NOTHING`;
    - if every non-null member has a seal → `relationship_archive(rel, 'both_sealed')`.
  - `relationship_archive(rel, reason)`: `UPDATE … SET status='archived', chat_archived_at=now(), chat_archived_reason=reason WHERE id=rel AND status <> 'archived'`, then cancels pushes.
  - `close_relationship_windows()`:
    - `ended AND ended_at <= now() - 30 days` → archive `window_closed`;
    - `paused AND paused_at <= now() - 30 days` → `relationship_end_internal(rel, NULL)`.
  - `relationship_archive_on_new_chapter()`:
    - an AFTER UPDATE OF status trigger, `WHEN (OLD.status = 'pending' AND NEW.status = 'active')`;
    - for each relationship `r` with `r.id <> NEW.id`, `r.status IN ('ended','paused')` and a member in `{NEW.user_a, NEW.user_b}`: if paused, run `relationship_end_internal(r.id, NULL)`; then `relationship_archive(r.id, 'partner_new_relationship')`.
  - `get_my_relationship_lifecycle()`: as R3-9. The latest row by `created_at` with `status <> 'pending'`; return nothing if it is `active`. `partner_first_name` = `split_part(btrim(u.display_name), ' ', 1)`.
  - `start_healing_journey`: restate the latest definition verbatim (`20260703193000_healing_mode_v1_1.sql`). Change only `AND status = 'ended'` to `AND status IN ('ended','archived')`.
  - `SELECT cron.schedule('close_relationship_windows', '23 2 * * *', $$ SELECT public.close_relationship_windows(); $$);`
- [ ] **Step 4:** The grants migration plus the local replay:
  - `REVOKE ALL … FROM PUBLIC, anon` on every new function;
  - `GRANT EXECUTE` to `authenticated` on the 5 client RPCs and `relationship_chat_open`;
  - the internal helpers get no grant;
  - `REVOKE ALL ON relationship_seals, healing_ending_snapshots FROM anon, authenticated; GRANT SELECT … TO authenticated`.
- [ ] **Step 5:** Write `20261018100200_chat_reads_respect_seal.sql`. For each class-A **read** path in `spec3-map.md` §F, restate the latest definition verbatim. The only change is replacing `r.chat_archived_at IS NULL` plus its member test with `public.relationship_chat_open(<rel id expr>)`.
  - **Policies (9):** messages, message_pins, message_reactions, message_edit_history, streak_clips, place_updates, chat_import_jobs, chat_import_requests, and storage `message_media_select_relationship_members`.
  - **RPCs (3):** `count_unread_messages`, `chat_conversation_streak` and `partner_is_active_in_chat`.
  - **Writes stay as they are** (they need `active`): mark_* delivered/read, set_chat_presence.
- [ ] **Step 6:** Update the old-behaviour contracts listed in Task 0 to the new semantics. End leaves the archive NULL; archive comes via `relationship_archive`. Keep each file's intent and give every edit a one-line comment naming Spec 3a.
- [ ] **Step 7:** Run the contracts (GREEN) plus the full SQL suite. The fail set must be identical to the baseline. Mutants (each must FAIL the contracts):
  - (a) drop the seal clause from `relationship_chat_open`;
  - (b) drop the 30-day clause;
  - (c) `end_relationship` setting `chat_archived_at = now()`;
  - (d) the trigger without `r.id <> NEW.id`.

### Task 2: The end-relationship function sends nothing (F1 (1))

- [ ] **Step 1:** Write `supabase/functions/end-relationship/no_push.test.ts`, a source test like `claim_recheck.test.ts`. The file must not import `push_queue` or call `enqueuePush`/`sendPush`, and its pre-check must accept `paused`. Run `deno test`. Expected: FAIL.
- [ ] **Step 2:** In the function, change the pre-fetch to `.in("status", ["active","paused"])`. Remove the partner lookup used only for the push, remove the push block and the import, and keep the response. Run again. Expected: PASS.
- [ ] **Step 3:** In `generate-healing-post-mortem/index.ts`, read `healing_ending_snapshots` (user-scoped admin query on `user_id` + `relationship_id`) first and fall back to live `patterns`. Write a Deno test of the pure selection helper `pickPatternEvidence(snapshot, live)`.

### Task 3: Client lifecycle data

**Interfaces — Produces:**
- `class RelationshipLifecycle { relationshipId, status (enum LifecycleStatus {paused, ended, archived}), partnerFirstName, endedByMe, pausedByMe, endedAt?, windowEndsAt?, pausedAt?, decideBy?, sealedByMe, chatReadable; factory fromRow; int daysLeft(DateTime now) }`.
- `RelationshipLifecycleService`: `pause(String id)`, `resume(String id)`, `seal(String id)` and `Future<RelationshipLifecycle?> fetchLifecycle()`, through an injectable `rpc` (same shape as `SessionsRpc`).
- `relationshipLifecycleProvider` (`FutureProvider.autoDispose<RelationshipLifecycle?>`).

- [ ] **Step 1: Tests first.** File `test/features/relationships/relationship_lifecycle_test.dart` covers:
  - `fromRow`, including null partner and null dates;
  - `daysLeft`: 30 days → 30; 23 hours → 0; past → 0;
  - each service method calls its RPC with `{'p_relationship_id': id}`;
  - `fetchLifecycle` returns null on 0 rows;
  - a `lifecycle:not_active` error maps to `RelationshipLifecycleException` with the message "This shared space has already changed. Pull to refresh."
- [ ] **Step 2:** Implement. `healing_repository.dart:55`: `.eq('status','ended')` → `.inFilter('status', ['ended','archived'])`. Add a test case to `relationship_mode_sync_test.dart` asserting that `archived` → personal.

### Task 4: The hub, the ending sheet, pause, copy (F1 (2), (3), (6))

- [ ] **Step 1: Widget tests first.** File `test/features/relationships/relationship_lifecycle_card_test.dart`, with a fake service and a provider override. It checks:
  - **Paused:** copy with N days, Resume calls `resume` then invalidates, End opens the end confirm.
  - **Ended and readable:** copy with `MyDateFormat.toDate(windowEndsAt)`. "Read our chat" pushes `chatChannel` with the `Conversation` from `chatRepository.getConversations()` whose id matches. "Seal my side now" asks first; "Seal" calls `seal`.
  - **Sealed or archived:** the card renders nothing.
  - **Device surfaces:** the first sight of any non-active lifecycle calls the injected `clearSurfaces` exactly once per relationship id (prefs key `lifecycle_surfaces_cleared:<id>`).
  - **`RelationshipEndedSheet`:** shows "{Name} has ended your shared space." once (prefs `relationship_ended_seen:<id>`). It is not shown when `endedByMe` or when `endedBy` is the system (`partnerFirstName` is shown only when `endedByMe == false` and the row's `ended_by` is the partner; add `endedByPartner` to the model, computed server-side as `ended_by IS NOT NULL AND ended_by <> auth.uid()`). The buttons route to `chatChannel`, `RouteNames.healingJourney` and `RouteNames.safetyResources`. There is no text field.
  - **Pause action:** the confirm copy is verbatim; confirm calls `pause`, then `clearTogetherDeviceSurfaces` and `relationshipModeResyncSignal.value++`.
  - **End action:** the new copy is verbatim.
- [ ] **Step 2:** Implement the widgets. In `ChatCouplesLockedScreen`, snapshot the file first; it has 738 lines. Insert `const RelationshipLifecycleCard()` as the first child of the body column, and schedule the ending sheet post-frame from `initState`. Touch nothing else in that file.
- [ ] **Step 3:** In `settings_data.dart` (snapshot first), add `pause_relationship` before `endRelationship` in the danger section, with a unique order. It is shown only where `endRelationship` is shown (same condition). Update the `EndRelationshipAction` copy, and keep its post-end flow.
- [ ] **Step 4:** Run `test/features/relationships test/features/chat test/features/settings test/home test/features/onboarding`, then analyze the touched files.

### Task 5: Docs, full runs, review

- [ ] **Step 1:** Update the user manual's relationship/ending section (find it with `grep -rn "End relationship\|archived" lib/app/documentations`):
  - no notification;
  - 30-day read window;
  - seal;
  - pause;
  - 12-month deletion.

  Write the copy test first, as `safety_docs_copy_test.dart` does.
- [ ] **Step 2:** Full `flutter test`, full SQL suite (fail set = baseline), analyzer on touched files, Deno tests for the two functions.
- [ ] **Step 3:** Hand-off in the ledger:
  - `supabase db push` (3 migrations);
  - `supabase functions deploy end-relationship generate-healing-post-mortem`;
  - device checks:
    - end from one phone; the other phone gets no push, and on open sees the sheet once, then the card;
    - read-only chat works;
    - seal hides the chat on that phone only;
    - pause, then resume from the other phone;
    - Together widget and Live Activity cleared on both phones.
- [ ] **Step 4:** Final Fable review of the whole change against this plan, F1 and D.1–D.4. One fix pass, every fix test-first. Ledger it.

---

## Plan review amendments (Fable, 2026-10-18) — BINDING, applied during execution

Review: `.superpowers/sdd/2026-10-18-spec3a-plan-review.md` (3 Critical, 12 Important, 14 Minor). Each item below overrides the task text above.

- **C1.** The app calls `rpc('end_relationship')` directly, as the caller. The edge function stays for older app versions. It now forwards the caller's JWT to an anon-key client, so `ended_by` is the human. Contract: an end with no claims → `lifecycle:not_found`.
- **C2.** Writes that only tested `chat_archived_at` now need `status='active'`, restated in `20261018100300_lifecycle_hardening.sql`:
  - pin delete, reaction delete, place update insert/delete, streak clip insert;
  - `mark_delivered`, `mark_relationship_delivered`, `set_chat_presence`;
  - `mark_conversation_read`, which accepts active or paused.

  New file `relationship_lifecycle_hardening_contracts.sql`.
- **C3.** `RelationshipLifecycleWatcher` lives in the app shell, inside the PIN gate and never on the decoy. It owns the one-time device-surface clear and the ending sheet, so both run on whatever tab the app opens. The card no longer does either.
- **I1.** `relationships` SELECT is column-level: `ended_by`, `paused_by` and `chat_archived_reason` are hidden from clients and realtime.
- **I2 / I3.**
  - The reminder generator is active-only and writes `relationship_id` into metadata.
  - The cancel step also matches `reminder_upcoming` rows by `reminder_id`.
  - Cancelled rows get `source_key = NULL`.
- **I4.** Timeline inserts are active-only.
- **I5.** Dating counts `paused` as a relationship (`dating_has_relationship` and both dating guards). Healing readiness is unchanged, pending the owner.
- **I6.** Calendar feeds are revoked only at `ended` or `archived`. The pause copy gains "Any game in progress ends."
- **I7.** The `streak_clips` read is correlated. `relationship_chat_open` cannot be inlined (its EXISTS is a sub-select). It stays SECURITY DEFINER: an index scan plus a per-row filter. Staging EXPLAIN ANALYZE is part of the hand-off.
- **I8.** Card variants:
  - ended and `chatReadable`: the open copy;
  - ended and not readable: "Your chat has closed. It is deleted 12 months from now.";
  - sealed or archived: "Your shared space has ended."

  The closed variants have no buttons.
- **I9.** Names: `get_or_create_healing_journey`; `patterns.last_seen_at`; `ended_by_partner` is in R3-9.
- **I10.** While paused, the locked screen hides "Invite your partner" and Dating.
- **I11.** An unknown partner reads "Your partner". A system ending or a deleted ender shows the card only, never the sheet.
- **I12.** The cron runs hourly. `resume_relationship` refuses once 30 days have passed.
- **Minors.**
  - M2: the outbox has `relationship_id`.
  - M6: the End subtitle changed.
  - M7: release gate. Do not push 3a to production before 3b's 12-month deletion job ships.
  - M8: ending from paused is done through the card's End button; the Settings entries require an active space.
  - M9: deferred (a sealed chat opened from a stray deep link shows empty).
  - M14: quick exit comes from the root shell.
