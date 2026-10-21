# Chat Wave 1a — Delivery, Sync & Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make chat delivery and sync WhatsApp-grade before the two-phone test: a message typed offline always sends itself in order when the connection returns; the server is the source of truth for what each phone shows (ghosts, edits, deletes, reactions, receipts and pins converge on both phones); an incoming message renders in one cheap step; read receipts and presence only fire while the conversation itself is on screen; the local cache can never stop the app from starting.

**Architecture:** The durable outbox becomes a real FIFO engine (`flushOutbox` is the only send path, network failures never consume the attempt cap, one timer always armed at the queue head, a 23505 reconcile that cannot escape) with four flush triggers (realtime re-subscribe, connectivity regained, app resume, open-time recovery) plus an app-level drainer for chats that are closed. Sync gets two new primitives — window reconciliation against each fetched page and an `updated_at` "changes since" cursor backed by a new server column + touch triggers — and the realtime handler is rebuilt as a coalesced batch: catch-up first, touched rows by id, then guarded metadata refreshes; the conversations list stops resubscribing on every bump. Two migrations carry the server side (sync cursor + pins replica identity; per-message counter off the published `relationships` row). Presence/read follow a `RouteAware` + lifecycle signal, draft restore no longer types, and cache init self-heals.

**Tech Stack:** Flutter 3.29 / Dart 3, Riverpod 2.6 (`StateNotifier`, `AsyncNotifier`), drift 2.x SQLite (encrypted blobs), Supabase (PostgREST + Realtime `postgres_changes`, realtime_client 2.7.3), Postgres 17 (plpgsql triggers), go_router 10, connectivity_plus 4, `fake` repository test harness.

**Spec:** `lib/architecture/CHAT_SYSTEM_SPEC.md` (§4 sending/queue, §6 realtime, §16 edge cases), review `docs/reviews/2026-10-18-chat-robustness-review.md` issues #1–#12, evidence `docs/reviews/2026-10-18-chat-review/{01_send,02_receive_sync,03_cache_persistence,V1_client_verify}.md` (root causes RC-1..RC-10, RC-15; RC-16/#35 is plan 3's).

## Global Constraints

- Work on main in the existing working tree (the owner has other uncommitted work; never revert or reformat it). NO COMMITS: replace every "Commit" step with "Checkpoint: run this task's tests and `flutter analyze <touched files>` filtered with `grep -E '^\s*(error|warning) '`; no commit (the owner commits)".
- Never run `dart format` on pre-existing files (repo uses an older formatter; reflowing is a regression). Only new files may be formatted.
- Test-first: every fix starts with a failing test that reproduces the verified failure scenario; watch it fail for the right reason, then fix.
- Flutter tests: `flutter test <path>`; reuse existing harnesses (test/features/chat/support/chat_test_harness.dart, FakeChatRepository, fake cache backends, FakeHaptics). Update old tests only where they encode the wrong behaviour, and say so.
- SQL: new migrations only (never edit an existing migration). Use ONLY your assigned timestamp range (20261019100000–20261019109999). Apply locally with `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/<file>.sql`; contract tests in supabase/tests/<name>_contracts.sql in the existing style (BEGIN … RAISE EXCEPTION 'CONTRACT VIOLATED: …' … ROLLBACK; see supabase/tests/home_card_order_contracts.sql and chat_system_contracts.sql), run with `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/<file>.sql`. Include a mutation check for each key rule (temporarily break the rule in a transaction and show the contract fails). NEVER use the attune_test database. Never touch the live project; deploying migrations/functions is an owner step — list them at the end under "Owner deploy steps".
- Edge functions (Deno/TS): follow existing patterns in supabase/functions; if the function has Deno tests, add tests; otherwise extract pure logic into a testable module with a Deno test (`deno test` if available — check `which deno`; if not available, say so and make the logic testable via SQL or Dart instead). (This plan changes no edge function.)
- Owner-only steps (Xcode capabilities, OneSignal dashboard settings, App Store / Apple developer portal) are listed explicitly as "Owner step" with exact instructions; the plan still makes every file change that can be made in the repo (e.g. entitlements/Info.plist edits).
- Display dates via MyDateFormat; user-facing copy plain and warm; respect reduceMotionOf for animations; haptics via hapticsProvider.
- Don't touch ATTUNE_SOUL.md / ATTUNE_THESIS.md. Don't read .env/credentials/keychain.
- Execution order across plans: 1a → 1b → 2 → 3 → 4, sequential on the same tree. Later plans must not assume line numbers from before earlier plans ran; say which files you share with other plans in a "Shared files" note.
- Design against function/class names, not line numbers: the reviewers' line numbers have drifted; every edit below names the function it changes and shows the whole replacement body.
- Spec §4.2: flush one logical message at a time per relationship in enqueue order; transient failures use bounded exponential backoff with jitter (window caps at 64 s); only authentication, membership, archived relationship, invalid payload and rejected media are permanent.
- Spec §6.1: realtime is an invalidation/delivery mechanism, not guaranteed history — on every reconnect fetch canonical rows after the newest known cursor before declaring the view synchronized. Spec §6.4: read is recorded only while the conversation is visible, foregrounded and rendered.
- Spec §16: "Relationship ends while queued → queue stops; message remains unsent (and the user is told)"; "Drift migration/corruption fails → rebuild read cache from server; preserve recoverable queue".
- Privacy: realtime payloads must never carry message content in a way RLS does not check; `messages` keeps `REPLICA IDENTITY DEFAULT` (contract-tested). Local logs carry ids only (`ChatLog`), never content.

## Shared files (coordinate with plans 1b, 2, 3, 4)

- `lib/features/chat/presentation/state/chat_state.dart` — this plan rewrites the outbox engine, the realtime handler, sync primitives and `ConversationsNotifier`. Plan 3 (chat screen) and plan 2 (media) touch other methods of the same class; they must re-read the file after this plan.
- `lib/features/chat/presentation/screens/chat_screen.dart` — this plan edits `_ChatScreenState` lifecycle (`initState`, `didChangeDependencies`, `dispose`, `didChangeAppLifecycleState`, `_syncViewActive`, `_restoreDraft`) and the `onRetry` gating in the bubble builder. Plan 3 edits the list/composer.
- `lib/features/chat/data/repositories/chat_repository.dart`, `supabase_chat_repository.dart`, `test/features/chat/support/chat_test_harness.dart` — new repository methods and the typed realtime event; plans 2/3 add their own methods beside them.
- `lib/app/routing/app_router.dart` — one `observers:` line. Plan 1b (push) also edits the router/notification wiring.
- `lib/main.dart`, `lib/app/app.dart` — a guard around cache init and one provider warm-up line. Plan 1b touches `main.dart`/OneSignal too.
- `test/features/chat/chat_controller_test.dart`, `inbox_realtime_test.dart` — small assertion updates (named in Task 6).

## Issue → task map

| # | Issue | Task |
|---|---|---|
| 1 | Offline sends never auto-send; offline cold start drops the queue | Task 6 (resync flush), Task 7 (open-time recovery, connectivity, resume, drainer) |
| 2 | Offline send turns Failed after ~15–30 s | Task 5 |
| 3 | Earlier queued message stuck at Queued forever | Task 5 |
| 4 | Stuck on "sending" via the 23505 reconcile | Task 5 |
| 5 | New sends skip the FIFO queue (+ read-only terminal state, M-4; outbox authoritative on restart, M-2) | Task 5 |
| 6 | Server-deleted messages stay as ghosts | Task 4 |
| 7 | Edits/deletes/reactions/receipts beyond the newest 50 never arrive | Task 1 (server cursor + reaction touch), Task 4 (client primitives), Task 6 (handler) |
| 8 | Unpin / un-react don't arrive live | Task 1 (pins `REPLICA IDENTITY FULL`; reactions bump `messages.updated_at` → RLS-checked UPDATE event), Task 6 |
| 9 | ~30 requests per incoming message; new message waits behind metadata; one exception aborts; inbox resubscribe churn; `message_count` echo | Task 2 (counter off `relationships`), Task 3 (narrow `getConversation`), Task 6 |
| 10 | Read/presence while another route covers the chat or the app is backgrounded/locked | Task 8 |
| 11 | Draft restore sends "typing…" | Task 9 |
| 12 | Corrupt/locked cache DB blocks app start | Task 10 |

## Review Focus

1. A send that is in flight when the partner pauses or ends the relationship: the insert fails with `42501`; a person expects "this chat is read-only now", not "you no longer have access", and no dead Retry button. Pinned in Task 5 (`_handleSendFailure` maps `unauthenticated` to `relationshipInactive` when the refreshed conversation is read-only; test "a 42501 against a now read-only chat is explained as read-only").
2. A phone whose clock is an hour ahead of the server: the "changes since" cursor must be built from server timestamps only, never `DateTime.now()`, or every resume would miss an hour of changes. Pinned in Task 4 (test "the sync cursor is the newest server timestamp, not the device clock").
3. Realtime frames arriving while a batch is already running (a burst during a slow fetch): they must be processed by one more batch after the current one, never dropped and never run concurrently. Pinned in Task 6 (test "frames that arrive mid-batch are processed by exactly one follow-up batch").
4. The app resumes while signed out, or with queued rows for a relationship that is no longer in the list: the drainer must do nothing and throw nothing. Pinned in Task 7 (test "the drainer is a no-op when signed out or when the relationship is gone").
5. A crash between the server acknowledging an insert and the outbox row being removed: on restart the canonical row and the outbox row both exist; the person must see one bubble, and the stale outbox row must reconcile through 23505 and disappear. Pinned in Task 5 (test "a canonical row already in the cache wins over its own stale outbox row, which then reconciles").
6. A first-page request that leaves before a send is acknowledged (or before a catch-up merges a partner row): its response predates the new row, and the window reconcile must not read that as a server-side deletion. Pinned in Task 4 (`knownBefore`; test "a row acknowledged while the first page was in flight is not dropped by that page").
7. A bottom sheet, dialog or menu opened over the chat (message actions, emoji picker, delete confirm): the person is still in the chat, so presence must stay and the partner's next message must not push a banner over it. Pinned in Task 8 (`PopupRoute` is not a cover; test "a sheet or dialog over the chat keeps presence and read receipts").

## File Structure

Create:
- `supabase/migrations/20261019100000_chat_sync_cursor.sql` — `messages.updated_at` + backfill + index, client-visible-change touch trigger, reaction→message touch trigger, `message_pins REPLICA IDENTITY FULL`.
- `supabase/migrations/20261019100010_chat_sync_cursor_grants.sql` — column grant for `updated_at`, trigger functions not client-callable.
- `supabase/migrations/20261019100100_chat_message_counters.sql` — `relationship_message_counters` (unpublished), count-on-insert/decrement-on-delete, `enqueue_message_downstream_work` without the `relationships` UPDATE.
- `supabase/migrations/20261019100110_chat_message_counters_grants.sql`.
- `supabase/tests/chat_sync_cursor_contracts.sql`, `supabase/tests/chat_message_counters_contracts.sql`.
- `lib/app/routing/app_route_observer.dart` — the single `RouteObserver` the router installs and `ChatScreen` subscribes to.
- `lib/features/chat/presentation/state/chat_outbox_drainer.dart` — app-level drainer for closed chats.
- Tests: `test/features/chat/chat_realtime_event_test.dart`, `chat_sync_reconcile_test.dart`, `chat_realtime_handler_test.dart`, `chat_outbox_engine_test.dart`, `chat_outbox_triggers_test.dart`, `chat_screen_view_active_test.dart`, `chat_screen_draft_restore_test.dart`, `chat_cache_recovery_test.dart`.

Modify:
- `lib/features/chat/data/repositories/chat_repository.dart` — `ChatRealtimeEvent`/`ChatRealtimeKind`; `watchConversationEvents` typed; `getMessagesByIds`, `getMessagesChangedSince`, `ensureRealtimeConnected`.
- `lib/features/chat/data/repositories/supabase_chat_repository.dart` — the above; `getConversation` becomes one relationship read; channel callbacks map payloads to events.
- `lib/features/chat/presentation/state/chat_state.dart` — `ConversationsNotifier` (no resubscribe on rebuild, coalesced refresh, `refreshQuietly`), `ChatController` (outbox engine, flush triggers, sync primitives, batch handler, read-only terminal state, restore authority).
- `lib/features/chat/presentation/screens/chat_screen.dart` — `RouteAware`, lifecycle, draft restore, retry gating, resume hook.
- `lib/features/chat/data/cache/chat_cache_backend_base.dart`, `chat_cache_backend_io.dart`, `chat_cache_backend_stub.dart`, `chat_cache_service.dart` — `reset()`, guarded init, cache-miss-on-error.
- `lib/app/routing/app_router.dart` (observer), `lib/app/app.dart` (drainer warm-up), `lib/main.dart` (init guard).
- `test/features/chat/support/chat_test_harness.dart` — scripting seams listed in Task 3.

---

### Task 1: Server sync cursor — `messages.updated_at`, touch triggers, pins replica identity (#7, #8 server side)

**Files:**
- Create: `supabase/migrations/20261019100000_chat_sync_cursor.sql`
- Create: `supabase/migrations/20261019100010_chat_sync_cursor_grants.sql`
- Create: `supabase/tests/chat_sync_cursor_contracts.sql`

**Interfaces:**
- Consumes: existing `public.messages`, `public.message_reactions`, `public.message_pins`, `react_to_message(p_relationship_id, p_message_id, p_emoji)`, `remove_reaction(p_message_id)`, `relationship_chat_open(uuid)`.
- Produces: column `public.messages.updated_at timestamptz NOT NULL`, selectable by `authenticated`; index `messages_relationship_updated_idx (relationship_id, updated_at)`; trigger functions `public.messages_touch_updated_at()` (BEFORE UPDATE on messages) and `public.message_reactions_touch_message()` (AFTER INSERT/UPDATE/DELETE on message_reactions); `message_pins` has `relreplident = 'f'`. Task 3's `getMessagesChangedSince` selects `updated_at`.

Design notes (why this shape):
- `updated_at` is bumped only when a column a client can read changes. The safety/analysis workers rewrite `messages` rows too (`message_analysis_done`, `tone_score`, …); without the column diff every phone would refetch a row on which nothing visible changed.
- A reaction add/remove bumps the parent message's `updated_at`. That does two jobs at once: the resume cursor sees reactions, and the resulting `messages` UPDATE realtime frame carries the message id to both phones through the RLS-checked `messages` subscription — so un-react arrives live **without** `REPLICA IDENTITY FULL` on `message_reactions` (which would broadcast un-RLS-checked old rows on DELETE).
- `message_pins` gets `REPLICA IDENTITY FULL`: a pin row is five ids/timestamps and no content, so the only thing FULL adds to the already-broadcast primary key is the `relationship_id` the channel filter needs. Realtime does not apply RLS to DELETE events whatever the identity, so FULL widens exposure by `message_id`, `pinned_by`, `pinned_at` only, to a subscriber who already holds the unguessable relationship uuid. Soft-deleting pins instead would need a new RPC, a column, and changes to every pin reader — more surface for less. `messages` and `message_reactions` stay DEFAULT and the contract test pins that.
- The backfill `UPDATE public.messages SET updated_at = GREATEST(…)` rewrites every existing row, and `messages` is in `supabase_realtime`: each rewritten row is one UPDATE frame to every phone subscribed to that chat at that moment (coalesced client-side into one batch per debounce window by Task 6, but still one `getMessagesByIds` of up to all its ids). Before the two-phone test the live table is small, so this is acceptable; the owner step says to apply it while no chat is open. Skipping the backfill (leaving every old row at the migration timestamp) was rejected: the cursor would then re-read up to 200 rows per chat on every resync until the chat's first new message.
- `authenticated` has no UPDATE grant on `messages` and its INSERT grant does not include `updated_at` (verified on `attune_spec3a`), so a client can neither set nor forge the cursor column; the only writers are server functions and the two triggers.

- [ ] **Step 1: Write the failing contract test**

Create `supabase/tests/chat_sync_cursor_contracts.sql`:

```sql
-- Chat W1a (#7, #8): the sync cursor. messages.updated_at moves only when a
-- client-visible column moves; a reaction add/remove moves it on the parent
-- message; message_pins ships filtered DELETE events (REPLICA IDENTITY FULL)
-- while messages and message_reactions never ship whole old rows.
BEGIN;
INSERT INTO auth.users (id) VALUES
  ('7fea0000-0000-0000-0000-0000000000a1'),
  ('7fea0000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name, mode) VALUES
  ('7fea0000-0000-0000-0000-0000000000a1', '+233200000071', 'Cursor A', 'couples'),
  ('7fea0000-0000-0000-0000-0000000000b2', '+233200000072', 'Cursor B', 'couples')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('7fea0000-0000-0000-0000-0000000000c1',
        '7fea0000-0000-0000-0000-0000000000a1',
        '7fea0000-0000-0000-0000-0000000000b2',
        'active', CURRENT_DATE, now())
ON CONFLICT (id) DO UPDATE SET status = 'active', chat_archived_at = NULL;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;

-- The checks are functions so the mutation checks below can rerun them.
CREATE FUNCTION pg_temp.assert_identities() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF (SELECT relreplident FROM pg_class WHERE oid = 'public.message_pins'::regclass) <> 'f' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: message_pins must be REPLICA IDENTITY FULL (filtered unpin DELETEs are dropped otherwise)';
  END IF;
  IF (SELECT relreplident FROM pg_class WHERE oid = 'public.messages'::regclass) <> 'd' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: messages must stay REPLICA IDENTITY DEFAULT (content must never ride a DELETE frame)';
  END IF;
  IF (SELECT relreplident FROM pg_class WHERE oid = 'public.message_reactions'::regclass) <> 'd' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: message_reactions must stay REPLICA IDENTITY DEFAULT';
  END IF;
END $$;

CREATE FUNCTION pg_temp.assert_reaction_bumps() RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_before timestamptz; v_after timestamptz;
BEGIN
  UPDATE public.messages SET updated_at = now() - interval '1 hour'
   WHERE id = '7fea0000-0000-0000-0000-0000000000d1';
  SELECT updated_at INTO v_before FROM public.messages WHERE id = '7fea0000-0000-0000-0000-0000000000d1';
  SET LOCAL ROLE authenticated;
  PERFORM pg_temp.as_user('7fea0000-0000-0000-0000-0000000000b2');
  PERFORM public.react_to_message('7fea0000-0000-0000-0000-0000000000c1',
                                  '7fea0000-0000-0000-0000-0000000000d1', '❤️');
  RESET ROLE;
  SELECT updated_at INTO v_after FROM public.messages WHERE id = '7fea0000-0000-0000-0000-0000000000d1';
  IF v_after <= v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reaction did not bump the message updated_at (% -> %)', v_before, v_after;
  END IF;
  UPDATE public.messages SET updated_at = now() - interval '1 hour'
   WHERE id = '7fea0000-0000-0000-0000-0000000000d1';
  SET LOCAL ROLE authenticated;
  PERFORM pg_temp.as_user('7fea0000-0000-0000-0000-0000000000b2');
  PERFORM public.remove_reaction('7fea0000-0000-0000-0000-0000000000d1');
  RESET ROLE;
  SELECT updated_at INTO v_after FROM public.messages WHERE id = '7fea0000-0000-0000-0000-0000000000d1';
  IF v_after <> now() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: removing a reaction did not bump the message updated_at';
  END IF;
END $$;

-- Worker-only columns leave the cursor alone; client-visible columns move it.
CREATE FUNCTION pg_temp.assert_visible_change_bumps() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.messages SET updated_at = now() - interval '1 hour'
   WHERE id = '7fea0000-0000-0000-0000-0000000000d1';
  UPDATE public.messages SET message_analysis_done = true, tone_score = 0.5
   WHERE id = '7fea0000-0000-0000-0000-0000000000d1';
  IF (SELECT updated_at FROM public.messages WHERE id = '7fea0000-0000-0000-0000-0000000000d1')
     <> now() - interval '1 hour' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an analysis-only update moved updated_at';
  END IF;
  UPDATE public.messages SET content = 'edited', edited_at = now()
   WHERE id = '7fea0000-0000-0000-0000-0000000000d1';
  IF (SELECT updated_at FROM public.messages WHERE id = '7fea0000-0000-0000-0000-0000000000d1') <> now() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an edit did not move updated_at';
  END IF;
  UPDATE public.messages SET updated_at = now() - interval '1 hour'
   WHERE id = '7fea0000-0000-0000-0000-0000000000d1';
  UPDATE public.messages SET delivered_at = now()
   WHERE id = '7fea0000-0000-0000-0000-0000000000d1';
  IF (SELECT updated_at FROM public.messages WHERE id = '7fea0000-0000-0000-0000-0000000000d1') <> now() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a receipt did not move updated_at';
  END IF;
END $$;

-- 1. A new message carries updated_at, selectable by its members.
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content)
VALUES ('7fea0000-0000-0000-0000-0000000000d1',
        '7fea0000-0000-0000-0000-0000000000c1',
        '7fea0000-0000-0000-0000-0000000000a1',
        '7fea0000-0000-0000-0000-0000000000e1', 'cursor row');
DO $$
BEGIN
  IF (SELECT updated_at FROM public.messages WHERE id = '7fea0000-0000-0000-0000-0000000000d1') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: updated_at missing on a new message';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public'
                 AND indexname = 'messages_relationship_updated_idx') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: messages_relationship_updated_idx missing';
  END IF;
END $$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('7fea0000-0000-0000-0000-0000000000a1');
DO $$
BEGIN
  PERFORM updated_at FROM public.messages WHERE id = '7fea0000-0000-0000-0000-0000000000d1';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated cannot select messages.updated_at';
END $$;
RESET ROLE;

-- 2. Worker-only columns do not move the cursor; visible columns do.
SELECT pg_temp.assert_visible_change_bumps();

-- 3. Reactions bump the parent message (add and remove).
SELECT pg_temp.assert_reaction_bumps();

-- 4. Replica identities.
SELECT pg_temp.assert_identities();

-- Mutation checks: break each rule inside a savepoint and prove the contract notices.
SAVEPOINT mutation_identity;
ALTER TABLE public.message_pins REPLICA IDENTITY DEFAULT;
DO $$
BEGIN
  BEGIN
    PERFORM pg_temp.assert_identities();
    RAISE EXCEPTION 'MUTATION NOT DETECTED: pins identity check passed after breaking it';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'MUTATION NOT DETECTED%' THEN RAISE; END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT mutation_identity;

SAVEPOINT mutation_touch;
DROP TRIGGER message_reactions_touch_message ON public.message_reactions;
DO $$
BEGIN
  BEGIN
    PERFORM pg_temp.assert_reaction_bumps();
    RAISE EXCEPTION 'MUTATION NOT DETECTED: reaction bump check passed without the trigger';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'MUTATION NOT DETECTED%' THEN RAISE; END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT mutation_touch;

SAVEPOINT mutation_visible;
DROP TRIGGER messages_touch_updated_at ON public.messages;
DO $$
BEGIN
  BEGIN
    PERFORM pg_temp.assert_visible_change_bumps();
    RAISE EXCEPTION 'MUTATION NOT DETECTED: visible-change bump check passed without the trigger';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'MUTATION NOT DETECTED%' THEN RAISE; END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT mutation_visible;

RESET ROLE;
ROLLBACK;
```

Reviewer note (2026-10-19): `now()` inside a transaction is the transaction start time, so a row whose transaction *started* earlier but *committed* later than another carries the smaller `updated_at`. The client therefore never trusts a bare "newest timestamp I hold" cursor: Task 4 subtracts a fixed overlap window and Task 3 pages on `(updated_at, id)` keyset, so a late commit inside the window is re-read (idempotent merge) rather than skipped. The trigger itself is right to use `now()`: `clock_timestamp()` would make the three bumps inside one `mark_conversation_read` call differ and gain nothing.

- [ ] **Step 2: Run it to verify it fails for the right reason**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/chat_sync_cursor_contracts.sql`
Expected: `ERROR:  column "updated_at" of relation "messages" does not exist` (the column is missing; the file aborts before any contract line).

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20261019100000_chat_sync_cursor.sql`:

```sql
-- Chat W1a (#7, #8): an incremental sync cursor for messages.
--
-- A phone only ever refetched the newest page, so an edit, deletion,
-- reaction or receipt on an older message never reached the other phone
-- until it fell out of the cache. updated_at lets a client ask for
-- "everything that changed since the newest server timestamp I hold"
-- on every resume and reconnect.
--
-- updated_at moves only when a column a client can SEE moves. The safety
-- and analysis workers rewrite messages rows too; without the diff every
-- phone would refetch rows on which nothing visible changed.
--
-- A reaction add/remove bumps the parent message. Besides feeding the
-- cursor, that emits a messages UPDATE frame through the RLS-checked
-- messages subscription, so un-react arrives live without putting whole
-- message_reactions rows on DELETE frames (REPLICA IDENTITY FULL).

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

UPDATE public.messages
SET updated_at = GREATEST(
  created_at,
  COALESCE(sort_at, created_at),
  COALESCE(edited_at, created_at),
  COALESCE(deleted_at, created_at),
  COALESCE(delivered_at, created_at),
  COALESCE(read_receipt_at, created_at),
  COALESCE(viewed_at, created_at)
)
WHERE updated_at IS DISTINCT FROM GREATEST(
  created_at,
  COALESCE(sort_at, created_at),
  COALESCE(edited_at, created_at),
  COALESCE(deleted_at, created_at),
  COALESCE(delivered_at, created_at),
  COALESCE(read_receipt_at, created_at),
  COALESCE(viewed_at, created_at)
);

CREATE INDEX IF NOT EXISTS messages_relationship_updated_idx
  ON public.messages (relationship_id, updated_at);

CREATE OR REPLACE FUNCTION public.messages_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  -- An explicit bump (the reaction touch below) is kept as given.
  IF NEW.updated_at IS DISTINCT FROM OLD.updated_at THEN
    RETURN NEW;
  END IF;
  IF (NEW.content, NEW.media_url, NEW.media_thumbnail_url, NEW.media_type,
      NEW.media_duration_ms, NEW.media_waveform, NEW.media_width, NEW.media_height,
      NEW.delivered_at, NEW.read_receipt_at, NEW.deleted_at, NEW.edited_at,
      NEW.viewed_at, NEW.streak_views_remaining, NEW.sort_at,
      NEW.reply_to_message_id, NEW.quoted_text, NEW.is_view_once,
      NEW.is_system_notice, NEW.game_session_id, NEW.story_item_id,
      NEW.message_origin, NEW.assistant_payload)
     IS DISTINCT FROM
     (OLD.content, OLD.media_url, OLD.media_thumbnail_url, OLD.media_type,
      OLD.media_duration_ms, OLD.media_waveform, OLD.media_width, OLD.media_height,
      OLD.delivered_at, OLD.read_receipt_at, OLD.deleted_at, OLD.edited_at,
      OLD.viewed_at, OLD.streak_views_remaining, OLD.sort_at,
      OLD.reply_to_message_id, OLD.quoted_text, OLD.is_view_once,
      OLD.is_system_notice, OLD.game_session_id, OLD.story_item_id,
      OLD.message_origin, OLD.assistant_payload) THEN
    NEW.updated_at := now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS messages_touch_updated_at ON public.messages;
CREATE TRIGGER messages_touch_updated_at
  BEFORE UPDATE ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.messages_touch_updated_at();

CREATE OR REPLACE FUNCTION public.message_reactions_touch_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- On a cascade from a deleted message the parent row is already gone and
  -- this matches nothing, which is fine.
  UPDATE public.messages
     SET updated_at = now()
   WHERE id = COALESCE(NEW.message_id, OLD.message_id);
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS message_reactions_touch_message ON public.message_reactions;
CREATE TRIGGER message_reactions_touch_message
  AFTER INSERT OR UPDATE OR DELETE ON public.message_reactions
  FOR EACH ROW EXECUTE FUNCTION public.message_reactions_touch_message();

-- Filtered DELETE events are only delivered when the old row carries the
-- filter column; with the primary key alone an unpin never reached the
-- partner. A pin row is ids and timestamps only.
ALTER TABLE public.message_pins REPLICA IDENTITY FULL;

COMMENT ON COLUMN public.messages.updated_at IS
  'Moves when a client-visible column moves, or when a reaction on this message is added/removed. Chat sync cursor (W1a).';
```

Create `supabase/migrations/20261019100010_chat_sync_cursor_grants.sql`:

```sql
-- Grants for 20261019100000_chat_sync_cursor.
-- messages SELECT is column-scoped for authenticated; the cursor column
-- must be readable or getMessagesChangedSince fails with 42501.
GRANT SELECT (updated_at) ON public.messages TO authenticated;
GRANT SELECT (updated_at) ON public.messages TO service_role;
-- Trigger functions are never client-callable.
REVOKE ALL ON FUNCTION public.messages_touch_updated_at() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.message_reactions_touch_message() FROM PUBLIC, anon, authenticated;
```

- [ ] **Step 4: Apply both migrations and run the contract test**

Run:
```bash
psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261019100000_chat_sync_cursor.sql
psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261019100010_chat_sync_cursor_grants.sql
psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/chat_sync_cursor_contracts.sql
```
Expected: the migrations print `ALTER TABLE`, `UPDATE n`, `CREATE INDEX`, `CREATE FUNCTION`, `CREATE TRIGGER` …; the contract test ends with `ROLLBACK` and no `ERROR` line (the two mutation savepoints raise and are caught inside their DO blocks — nothing is printed for them).

- [ ] **Step 5: Confirm the identity/trigger state once more read-only**

Run: `psql -X -d attune_spec3a -Atc "select relname, relreplident from pg_class where relname in ('messages','message_pins','message_reactions') order by 1;"`
Expected:
```
message_pins|f
message_reactions|d
messages|d
```

- [ ] **Step 6: Checkpoint**

Run this task's contract test again (Step 4 command three) — Expected: no `ERROR`; no `flutter analyze` needed (SQL only); no commit (the owner commits).

---

### Task 2: Per-message counter off the published `relationships` row (#9 server side)

**Files:**
- Create: `supabase/migrations/20261019100100_chat_message_counters.sql`
- Create: `supabase/migrations/20261019100110_chat_message_counters_grants.sql`
- Create: `supabase/tests/chat_message_counters_contracts.sql`

**Interfaces:**
- Consumes: `public.enqueue_message_downstream_work()` (current body dumped from `attune_spec3a` with `pg_get_functiondef`; restated below with one change), `public.relationship_chat_open(uuid)`.
- Produces: table `public.relationship_message_counters(relationship_id uuid PK, message_count bigint, updated_at timestamptz)` — RLS, member SELECT, **not** in `supabase_realtime`; trigger function `public.messages_count_on_delete()`; `public.relationships.message_count` is frozen (commented) and no longer written per insert.

Why: every message insert ran `UPDATE relationships SET message_count = …`, which both channels on both phones subscribe to (`relationships` UPDATE is how pause/end/name changes arrive). Each message therefore produced a second realtime frame per device and a `_refreshConversation` (4–5 requests) per message, and serialised both partners' inserts on one hot row. Nothing in `lib/` or `supabase/functions` reads `relationships.message_count` (re-verified 2026-10-19: the only `message_count` hits in Dart/TS are `chat_import_jobs.parsed_message_count` and `analysis_sessions.message_count`, different tables). Three SQL functions still *write* the column from `count(*)` on rare events — `cancel_chat_imports_on_relationship_change` (trigger on a status/archive change), `revoke_chat_import_request`, `delete_chat_import` (migration 20261018160000) — which is harmless (no reader, no per-message frame) and is left alone so this plan does not restate import functions; the column comment below says "not maintained per insert" rather than "never written". The count moves to an unpublished side table so the behaviour (a per-relationship message count) stays correct while the published row stays quiet.

- [ ] **Step 1: Write the failing contract test**

Create `supabase/tests/chat_message_counters_contracts.sql`:

```sql
-- Chat W1a (#9): a message insert must not touch the published relationships
-- row. The count lives in relationship_message_counters, which stays out of
-- the realtime publication and is readable by the couple only.
BEGIN;
INSERT INTO auth.users (id) VALUES
  ('7fea0000-0000-0000-0000-0000000000a1'),
  ('7fea0000-0000-0000-0000-0000000000b2'),
  ('7fea0000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name, mode) VALUES
  ('7fea0000-0000-0000-0000-0000000000a1', '+233200000071', 'Cursor A', 'couples'),
  ('7fea0000-0000-0000-0000-0000000000b2', '+233200000072', 'Cursor B', 'couples'),
  ('7fea0000-0000-0000-0000-0000000000c3', '+233200000073', 'Outsider C', 'couples')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, message_count)
VALUES ('7fea0000-0000-0000-0000-0000000000c1',
        '7fea0000-0000-0000-0000-0000000000a1',
        '7fea0000-0000-0000-0000-0000000000b2',
        'active', CURRENT_DATE, now(), 41)
ON CONFLICT (id) DO UPDATE SET status = 'active', chat_archived_at = NULL, message_count = 41;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;

CREATE FUNCTION pg_temp.counter() RETURNS bigint LANGUAGE sql AS $$
  SELECT COALESCE((SELECT message_count FROM public.relationship_message_counters
                   WHERE relationship_id = '7fea0000-0000-0000-0000-0000000000c1'), 0) $$;

CREATE FUNCTION pg_temp.assert_unpublished() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication_tables
             WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
               AND tablename = 'relationship_message_counters') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: relationship_message_counters must not be published (that is the echo this table removes)';
  END IF;
END $$;

CREATE FUNCTION pg_temp.assert_delete_decrements() RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_before bigint; v_after bigint;
BEGIN
  INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content)
  VALUES ('7fea0000-0000-0000-0000-0000000000d9',
          '7fea0000-0000-0000-0000-0000000000c1',
          '7fea0000-0000-0000-0000-0000000000a1',
          '7fea0000-0000-0000-0000-0000000000e9', 'to delete');
  v_before := pg_temp.counter();
  DELETE FROM public.messages WHERE id = '7fea0000-0000-0000-0000-0000000000d9';
  v_after := pg_temp.counter();
  IF v_after <> v_before - 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hard delete did not decrement the counter (% -> %)', v_before, v_after;
  END IF;
END $$;

-- 1. Insert: relationships.message_count frozen, counter +1.
DO $$
DECLARE v_counter_before bigint := pg_temp.counter();
BEGIN
  INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content)
  VALUES ('7fea0000-0000-0000-0000-0000000000d2',
          '7fea0000-0000-0000-0000-0000000000c1',
          '7fea0000-0000-0000-0000-0000000000a1',
          '7fea0000-0000-0000-0000-0000000000e2', 'counted');
  IF (SELECT message_count FROM public.relationships WHERE id = '7fea0000-0000-0000-0000-0000000000c1') <> 41 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a message insert still writes relationships.message_count';
  END IF;
  IF pg_temp.counter() <> v_counter_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: counter did not advance on insert (% -> %)', v_counter_before, pg_temp.counter();
  END IF;
END $$;

-- 2. Hard delete decrements.
SELECT pg_temp.assert_delete_decrements();

-- 3. Not published.
SELECT pg_temp.assert_unpublished();

-- 4. Member reads, outsider does not.
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('7fea0000-0000-0000-0000-0000000000a1');
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.relationship_message_counters
                 WHERE relationship_id = '7fea0000-0000-0000-0000-0000000000c1') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a member cannot read the couple''s counter';
  END IF;
END $$;
SELECT pg_temp.as_user('7fea0000-0000-0000-0000-0000000000c3');
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.relationship_message_counters
             WHERE relationship_id = '7fea0000-0000-0000-0000-0000000000c1') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider can read another couple''s counter';
  END IF;
END $$;
RESET ROLE;

-- Mutation checks.
SAVEPOINT mutation_publish;
ALTER PUBLICATION supabase_realtime ADD TABLE public.relationship_message_counters;
DO $$
BEGIN
  BEGIN
    PERFORM pg_temp.assert_unpublished();
    RAISE EXCEPTION 'MUTATION NOT DETECTED: publication check passed after publishing the table';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'MUTATION NOT DETECTED%' THEN RAISE; END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT mutation_publish;

SAVEPOINT mutation_delete;
DROP TRIGGER messages_count_on_delete ON public.messages;
DO $$
BEGIN
  BEGIN
    PERFORM pg_temp.assert_delete_decrements();
    RAISE EXCEPTION 'MUTATION NOT DETECTED: decrement check passed without the trigger';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'MUTATION NOT DETECTED%' THEN RAISE; END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT mutation_delete;

ROLLBACK;
```

- [ ] **Step 2: Run it to verify it fails for the right reason**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/chat_message_counters_contracts.sql`
Expected: `ERROR:  relation "public.relationship_message_counters" does not exist` (raised while creating `pg_temp.counter()`).

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20261019100100_chat_message_counters.sql` (the `enqueue_message_downstream_work` body below is the current one from `attune_spec3a` with exactly one change — the `UPDATE public.relationships SET message_count` statement is replaced by the counter upsert; keep everything else byte-for-byte):

```sql
-- Chat W1a (#9): stop touching the published relationships row per message.
--
-- enqueue_message_downstream_work ran UPDATE relationships SET
-- message_count = message_count + 1 on every insert. Both chat channels on
-- both phones subscribe to relationships UPDATE (that is how a pause, an
-- ending or a renamed chat arrives), so every message produced a second
-- realtime frame per device plus a full header refetch, and both partners'
-- inserts queued on one hot row. The count moves to an unpublished side
-- table; relationships.message_count is frozen at its last value.

CREATE TABLE IF NOT EXISTS public.relationship_message_counters (
  relationship_id uuid PRIMARY KEY REFERENCES public.relationships(id) ON DELETE CASCADE,
  message_count bigint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.relationship_message_counters ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS relationship_message_counters_select ON public.relationship_message_counters;
CREATE POLICY relationship_message_counters_select
  ON public.relationship_message_counters
  FOR SELECT TO authenticated
  USING (public.relationship_chat_open(relationship_id));

-- Seed from the real rows, not the frozen column, so the two agree today.
INSERT INTO public.relationship_message_counters (relationship_id, message_count)
SELECT r.id, (SELECT count(*) FROM public.messages m WHERE m.relationship_id = r.id)
FROM public.relationships r
ON CONFLICT (relationship_id) DO UPDATE
  SET message_count = EXCLUDED.message_count, updated_at = now();

COMMENT ON COLUMN public.relationships.message_count IS
  'Not maintained per insert since 2026-10-19 (chat W1a #9); only the import revoke/delete paths still recompute it. Read relationship_message_counters.';

CREATE OR REPLACE FUNCTION public.messages_count_on_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  UPDATE public.relationship_message_counters
     SET message_count = GREATEST(message_count - 1, 0), updated_at = now()
   WHERE relationship_id = OLD.relationship_id;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS messages_count_on_delete ON public.messages;
CREATE TRIGGER messages_count_on_delete
  AFTER DELETE ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.messages_count_on_delete();

CREATE OR REPLACE FUNCTION public.enqueue_message_downstream_work()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_relationship public.relationships%ROWTYPE;
  v_recipient_id uuid;
  v_notification_outbox_id uuid;
  v_supabase_url text;
  v_service_role_key text;
BEGIN
  SELECT * INTO v_relationship FROM public.relationships WHERE id = NEW.relationship_id;
  IF NOT FOUND THEN RETURN NEW; END IF;
  -- W1a #9: the per-message count lives off the published relationships row.
  INSERT INTO public.relationship_message_counters (relationship_id, message_count)
  VALUES (NEW.relationship_id, 1)
  ON CONFLICT (relationship_id) DO UPDATE
    SET message_count = public.relationship_message_counters.message_count + 1,
        updated_at = now();
  INSERT INTO public.message_safety_outbox (message_id, relationship_id, source_event_key)
  VALUES (NEW.id, NEW.relationship_id, NULL) ON CONFLICT (message_id) DO NOTHING;

  IF NEW.source = 'native' THEN
    v_recipient_id := CASE
      WHEN v_relationship.user_a = NEW.sender_id THEN v_relationship.user_b
      WHEN v_relationship.user_b = NEW.sender_id THEN v_relationship.user_a
      ELSE NULL END;
    IF v_recipient_id IS NOT NULL THEN
      INSERT INTO public.message_notification_outbox (
        message_id, relationship_id, recipient_id, sender_id
      ) VALUES (NEW.id, NEW.relationship_id, v_recipient_id, NEW.sender_id)
      ON CONFLICT (recipient_id, message_id, notification_type) DO NOTHING
      RETURNING id INTO v_notification_outbox_id;
    END IF;
  END IF;

  v_supabase_url := public.app_setting('supabase_url');
  v_service_role_key := public.app_setting('service_role_key');
  IF v_supabase_url IS NOT NULL AND v_service_role_key IS NOT NULL THEN
    BEGIN
      PERFORM net.http_post(
        url := v_supabase_url || '/functions/v1/process-chat-safety-outbox',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_service_role_key,'apikey',v_service_role_key),
        body := jsonb_build_object('message_id', NEW.id));
      IF v_notification_outbox_id IS NOT NULL THEN
        PERFORM net.http_post(
          url := v_supabase_url || '/functions/v1/process-chat-notification-outbox',
          headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_service_role_key,'apikey',v_service_role_key),
          body := jsonb_build_object('outbox_id', v_notification_outbox_id));
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;
  RETURN NEW;
END;
$function$;
```

Before writing, re-dump the live body and diff it against the block above so nothing else drifted:

Run: `psql -X -d attune_spec3a -Atc "select pg_get_functiondef('public.enqueue_message_downstream_work'::regproc);" | grep -n "UPDATE public.relationships SET message_count"`
Expected: one line (the statement being replaced). If the rest of the body differs from the block above, keep the live body and change only that statement.

Create `supabase/migrations/20261019100110_chat_message_counters_grants.sql`:

```sql
-- Grants for 20261019100100_chat_message_counters.
GRANT SELECT ON public.relationship_message_counters TO authenticated;
GRANT SELECT ON public.relationship_message_counters TO service_role;
REVOKE ALL ON FUNCTION public.messages_count_on_delete() FROM PUBLIC, anon, authenticated;
```

- [ ] **Step 4: Apply and run the contract test**

Run:
```bash
psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261019100100_chat_message_counters.sql
psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261019100110_chat_message_counters_grants.sql
psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/chat_message_counters_contracts.sql
```
Expected: migrations apply; the contract test ends in `ROLLBACK` with no `ERROR` line.

- [ ] **Step 5: Re-run the existing chat contracts to prove nothing else moved**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/chat_system_contracts.sql`
Expected: ends in `ROLLBACK`, no `ERROR`.

- [ ] **Step 6: Checkpoint**

Run Task 1's and Task 2's contract tests — Expected: no `ERROR`; no commit (the owner commits).

---

### Task 3: Repository plumbing — typed realtime events, by-id and changes-since reads, narrow `getConversation`, `ensureRealtimeConnected`, harness seams

**Files:**
- Modify: `lib/features/chat/data/repositories/chat_repository.dart` (abstract class + new types at the bottom)
- Modify: `lib/features/chat/data/repositories/supabase_chat_repository.dart` (`getConversation`, `getConversations` helper extraction, `_channelFor` callbacks, `watchConversationEvents`, new methods)
- Modify: `test/features/chat/support/chat_test_harness.dart` (`FakeChatRepository`, `buildChatContainer`)
- Test: `test/features/chat/chat_realtime_event_test.dart`

**Interfaces:**
- Produces (used by Tasks 4–7):
  - `enum ChatRealtimeKind { resync, messageInsert, messageUpdate, messageDelete, relationship, pin, reaction }`
  - `class ChatRealtimeEvent { const ChatRealtimeEvent(this.kind, {this.messageId}); const ChatRealtimeEvent.resync(); final ChatRealtimeKind kind; final String? messageId; static ChatRealtimeEvent? fromPostgresChange({required String table, required String eventType, required Map<String, dynamic> newRecord, required Map<String, dynamic> oldRecord}); }`
  - `Stream<ChatRealtimeEvent> watchConversationEvents(String relationshipId)` (was `Stream<void>`)
  - `Future<List<Message>> getMessagesByIds(String relationshipId, List<String> ids)`
  - `Future<List<Message>> getMessagesChangedSince(String relationshipId, {required DateTime since, int limit = 50})`
  - `Future<void> ensureRealtimeConnected()`
  - `FakeChatRepository` seams: `sendErrorQueue`, `sentContents`, `findMessageError`, `getConversationError`, `getPinnedError`, `getConversationCalls`, `getMessagesCalls`, `getMessagesAfterCalls`, `getPinnedCalls`, `getMessagesByIdsCalls`, `ensureRealtimeConnectedCalls`, `lastChangedSinceArg`, `serverUpdatedAt`, `touch(id)`, `getMessagesResponseGate`, `emitRealtime([event])`; `buildChatContainer(..., Stream<bool>? connectivity)`.

- [ ] **Step 1: Write the failing test for the event mapping**

Create `test/features/chat/chat_realtime_event_test.dart`:

```dart
import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The channel callbacks used to throw the payload away and emit null, so
  // the handler could only refetch everything. The event now says what moved
  // and, where the frame carries one, which message — including a DELETE,
  // whose id lives only in the old record.
  group('ChatRealtimeEvent.fromPostgresChange', () {
    test('a messages INSERT names the new row', () {
      final event = ChatRealtimeEvent.fromPostgresChange(
        table: 'messages',
        eventType: 'insert',
        newRecord: const {'id': 'm1', 'relationship_id': 'rel'},
        oldRecord: const {},
      );
      expect(event?.kind, ChatRealtimeKind.messageInsert);
      expect(event?.messageId, 'm1');
    });

    test('a messages UPDATE names the row', () {
      final event = ChatRealtimeEvent.fromPostgresChange(
        table: 'messages',
        eventType: 'update',
        newRecord: const {'id': 'm2'},
        oldRecord: const {'id': 'm2'},
      );
      expect(event?.kind, ChatRealtimeKind.messageUpdate);
      expect(event?.messageId, 'm2');
    });

    test('a messages DELETE takes the id from the old record', () {
      final event = ChatRealtimeEvent.fromPostgresChange(
        table: 'messages',
        eventType: 'delete',
        newRecord: const {},
        oldRecord: const {'id': 'm3'},
      );
      expect(event?.kind, ChatRealtimeKind.messageDelete);
      expect(event?.messageId, 'm3');
    });

    test('a reaction frame names the message it belongs to, add or remove', () {
      final added = ChatRealtimeEvent.fromPostgresChange(
        table: 'message_reactions',
        eventType: 'insert',
        newRecord: const {'message_id': 'm4', 'user_id': 'u', 'emoji': 'x'},
        oldRecord: const {},
      );
      final removed = ChatRealtimeEvent.fromPostgresChange(
        table: 'message_reactions',
        eventType: 'delete',
        newRecord: const {},
        oldRecord: const {'message_id': 'm4', 'user_id': 'u'},
      );
      expect(added?.kind, ChatRealtimeKind.reaction);
      expect(added?.messageId, 'm4');
      expect(removed?.kind, ChatRealtimeKind.reaction);
      expect(removed?.messageId, 'm4');
    });

    test('pins and relationships map to their kinds; unknown tables to null', () {
      expect(
        ChatRealtimeEvent.fromPostgresChange(
          table: 'message_pins',
          eventType: 'delete',
          newRecord: const {},
          oldRecord: const {'message_id': 'm5', 'relationship_id': 'rel'},
        )?.kind,
        ChatRealtimeKind.pin,
      );
      expect(
        ChatRealtimeEvent.fromPostgresChange(
          table: 'relationships',
          eventType: 'update',
          newRecord: const {'id': 'rel', 'status': 'paused'},
          oldRecord: const {'id': 'rel'},
        )?.kind,
        ChatRealtimeKind.relationship,
      );
      expect(
        ChatRealtimeEvent.fromPostgresChange(
          table: 'something_else',
          eventType: 'update',
          newRecord: const {},
          oldRecord: const {},
        ),
        isNull,
      );
    });

    test('the resync event has no message and is const', () {
      const event = ChatRealtimeEvent.resync();
      expect(event.kind, ChatRealtimeKind.resync);
      expect(event.messageId, isNull);
    });
  });

  test('the Supabase repository builds getConversation from one relationship read, '
      'not from the whole list', () {
    // Source-level: the real repository cannot run without a server. What
    // must hold is that the chat header refresh no longer costs the
    // relationships + users + last message + unread RPC + avatar chain
    // for every conversation the person has.
    final source = File(
      'lib/features/chat/data/repositories/supabase_chat_repository.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<Conversation?> getConversation(');
    final end = source.indexOf('@override', start + 1);
    final body = source.substring(start, end);
    expect(body, isNot(contains('getConversations()')));
    expect(body, contains(".eq('id', relationshipId)"));
    expect(body, isNot(contains('_fetchUnreadCount')));
    expect(body, isNot(contains('_fetchLastMessage')));
  });
}
```

Add `import 'dart:io';` at the top of the file (the source test reads a file).

- [ ] **Step 2: Run it to verify it fails for the right reason**

Run: `flutter test test/features/chat/chat_realtime_event_test.dart`
Expected: compile error `Undefined name 'ChatRealtimeEvent'` / `ChatRealtimeKind`.

- [ ] **Step 3: Add the types and methods to the abstract repository**

In `lib/features/chat/data/repositories/chat_repository.dart`:

Replace the declaration `Stream<void> watchConversationEvents(String relationshipId);` with:

```dart
  /// Everything the per-relationship channel delivers, as typed events: a
  /// message insert/update/delete (with its id), a relationship row change,
  /// a pin or reaction change (with the message id), or a `resync` — emitted
  /// on every successful (re)subscribe, which is the moment the socket may
  /// have missed anything (Spec 6.1).
  Stream<ChatRealtimeEvent> watchConversationEvents(String relationshipId);
```

After `getMessagesAfter(...)`'s declaration add:

```dart
  /// The current server rows for [ids] (hydrated with reactions), in no
  /// particular order. Ids the server no longer returns are hard-deleted or
  /// no longer visible; callers drop them locally.
  Future<List<Message>> getMessagesByIds(String relationshipId, List<String> ids);

  /// Rows whose server `updated_at` is at or after [since], oldest change
  /// first, paged until exhausted (bounded). Edits, deletions, receipts and
  /// reactions all move `updated_at` (migration 20261019100000), so this is
  /// the "what changed while I was away" read used on resume and reconnect.
  Future<List<Message>> getMessagesChangedSince(
    String relationshipId, {
    required DateTime since,
    int limit = 50,
  });

  /// Asks the realtime socket to connect now if it is not. Called when the
  /// device reports connectivity back, so the per-chat channel rejoins in
  /// seconds instead of waiting for the heartbeat to notice. Best-effort.
  Future<void> ensureRealtimeConnected();
```

Append at the end of the file (after `MessageEditHistoryEntry`):

```dart
/// What a realtime frame on the conversation channel was about.
enum ChatRealtimeKind {
  /// The channel (re)subscribed: refetch everything that could have moved.
  resync,
  messageInsert,
  messageUpdate,
  messageDelete,
  relationship,
  pin,
  reaction,
}

/// One realtime frame, reduced to what the controller needs: the kind of
/// change and, when the table has one, the message it concerns. Never the
/// row itself — content must come from an authorized read, not a socket.
class ChatRealtimeEvent {
  const ChatRealtimeEvent(this.kind, {this.messageId});

  const ChatRealtimeEvent.resync() : this(ChatRealtimeKind.resync);

  final ChatRealtimeKind kind;
  final String? messageId;

  /// Maps a postgres_changes frame. Pure, so it is testable without a socket.
  /// [eventType] is the lower-case realtime event name (`insert`, `update`,
  /// `delete`). A DELETE frame only has the old record (primary key under
  /// REPLICA IDENTITY DEFAULT; the whole row under FULL).
  static ChatRealtimeEvent? fromPostgresChange({
    required String table,
    required String eventType,
    required Map<String, dynamic> newRecord,
    required Map<String, dynamic> oldRecord,
  }) {
    String? idFrom(String column) {
      final value = newRecord[column] ?? oldRecord[column];
      return value is String ? value : null;
    }

    switch (table) {
      case 'messages':
        final kind = switch (eventType.toLowerCase()) {
          'insert' => ChatRealtimeKind.messageInsert,
          'delete' => ChatRealtimeKind.messageDelete,
          _ => ChatRealtimeKind.messageUpdate,
        };
        return ChatRealtimeEvent(kind, messageId: idFrom('id'));
      case 'relationships':
        return const ChatRealtimeEvent(ChatRealtimeKind.relationship);
      case 'message_pins':
        return ChatRealtimeEvent(
          ChatRealtimeKind.pin,
          messageId: idFrom('message_id'),
        );
      case 'message_reactions':
        return ChatRealtimeEvent(
          ChatRealtimeKind.reaction,
          messageId: idFrom('message_id'),
        );
    }
    return null;
  }

  @override
  String toString() => 'ChatRealtimeEvent(${kind.name}, $messageId)';
}
```

- [ ] **Step 4: Implement them in `SupabaseChatRepository`**

In `lib/features/chat/data/repositories/supabase_chat_repository.dart`:

(a) Change the event controller type. Replace
`final Map<String, StreamController<void>> _eventControllers = {};`
with
`final Map<String, StreamController<ChatRealtimeEvent>> _eventControllers = {};`
and in `_channelFor` replace `() => StreamController<void>.broadcast()` with `() => StreamController<ChatRealtimeEvent>.broadcast()`.

(b) In `_channelFor`, replace each of the four `callback: (_) => events.add(null),` lines with a callback that maps the payload. Add this private helper to the class and use it for all four handlers:

```dart
  /// Reduces a frame to a [ChatRealtimeEvent] and forwards it. Never throws:
  /// a malformed frame must not take the subscription down.
  void _forwardChange(
    StreamController<ChatRealtimeEvent> events,
    PostgresChangePayload payload,
  ) {
    if (events.isClosed) return;
    try {
      final event = ChatRealtimeEvent.fromPostgresChange(
        table: payload.table,
        eventType: payload.eventType.name,
        newRecord: payload.newRecord,
        oldRecord: payload.oldRecord,
      );
      if (event != null) events.add(event);
    } catch (error) {
      ChatLog.e('realtime frame ignored', error);
    }
  }
```

Each of the four handlers becomes `callback: (payload) => _forwardChange(events, payload),`.

In the `.subscribe((status, error) { ... })` callback, replace `if (!events.isClosed) events.add(null);` with `if (!events.isClosed) events.add(const ChatRealtimeEvent.resync());`.

(c) `watchConversationEvents` return type: `Stream<ChatRealtimeEvent> watchConversationEvents(String relationshipId)` (body unchanged).

(d) Replace the whole `getConversation` with one relationship read, and extract the row→Conversation mapping so `getConversations` shares it. Replace the body of `getConversations` from `for (final relationship in relationships) {` to the closing `}` of that loop with:

```dart
    for (final relationship in relationships) {
      final relationshipId = relationship['id'] as String;
      final partnerId = _partnerIdFor(relationship, user.id);
      if (partnerId == null) continue;
      final lastMessage = await _fetchLastMessage(relationshipId, user.id);
      final unreadCount = await _fetchUnreadCount(relationshipId, user.id);
      conversations.add(
        await _conversationFromRow(
          relationship,
          partner: usersById[partnerId],
          partnerId: partnerId,
          lastMessage: lastMessage,
          unreadCount: unreadCount,
        ),
      );
    }
```

Add the helper (keeps every line of the former loop body's mapping, including the avatar comment):

```dart
  static const _relationshipColumns =
      'id,user_a,user_b,status,chat_archived_at,created_at,ended_at,'
      'chat_name,chat_avatar_url,chat_avatar_thumbnail_url';

  Future<Conversation> _conversationFromRow(
    Map<String, dynamic> relationship, {
    required Map<String, dynamic>? partner,
    required String partnerId,
    required Message? lastMessage,
    required int unreadCount,
  }) async {
    final relationshipId = relationship['id'] as String;
    final status = relationship['status'] as String;
    final archivedAt = relationship['chat_archived_at'];
    final availability =
        archivedAt != null
            ? ConversationAvailability.archived
            : (status == 'active'
                ? ConversationAvailability.active
                : ConversationAvailability.readOnly);

    // Couple-chosen identity wins once set (see spec's Read path /
    // display section) — falls back to the partner's own profile until
    // then, exactly matching pre-feature behavior. Prefer the thumbnail
    // once the async job has produced one; the full-size key is still
    // shown in the gap between "photo set" and "thumbnail ready" rather
    // than nothing.
    final chatAvatarKey =
        (relationship['chat_avatar_thumbnail_url'] as String?) ??
        (relationship['chat_avatar_url'] as String?);
    final avatarUrl =
        chatAvatarKey != null
            ? await _createRelationshipAvatarSignedUrl(chatAvatarKey)
            : partner?['avatar_url'] as String?;

    return Conversation(
      id: relationshipId,
      relationshipId: relationshipId,
      partnerId: partnerId,
      name:
          (relationship['chat_name'] as String?) ??
          (partner?['display_name'] as String?) ??
          'Partner',
      // The partner's OWN name, kept separate from the couple's
      // chat_name: a typing indicator or reply preview naming the
      // couple puts their shared name in one person's mouth.
      partnerName: (partner?['display_name'] as String?) ?? 'Partner',
      avatarUrl: avatarUrl,
      lastMessage: lastMessage,
      unreadCount: unreadCount,
      updatedAt: lastMessage?.createdAt ?? DateTime.now(),
      relationshipStatus: status,
      availability: availability,
    );
  }
```

Use `_relationshipColumns` in `getConversations`' `.select(...)` too (same string). Then replace `getConversation`:

```dart
  /// One relationship read plus the partner row. Deliberately NOT the list
  /// fetch filtered to one id: the chat header refresh runs on every
  /// relationship change and used to cost relationships + users + last
  /// message + unread RPC + avatar for every conversation the person has.
  /// The header does not show a preview or an unread count, so neither is
  /// fetched (both are 0/null here; the list keeps its own).
  @override
  Future<Conversation?> getConversation(String relationshipId) async {
    final user = _currentUser;
    final relationship =
        await _supabase
            .from('relationships')
            .select(_relationshipColumns)
            .eq('id', relationshipId)
            .maybeSingle();
    if (relationship == null) return null;
    final partnerId = _partnerIdFor(relationship, user.id);
    if (partnerId == null) return null;
    final usersById = await _loadUsersById([partnerId]);
    return _conversationFromRow(
      relationship,
      partner: usersById[partnerId],
      partnerId: partnerId,
      lastMessage: null,
      unreadCount: 0,
    );
  }
```

Note the behavioural difference and why it is safe: the old path returned `null` for an archived relationship (the list filters `chat_archived_at IS NULL`); the new path returns a Conversation with `availability: archived`. `ChatController._refreshConversation` already purges on either (`updated == null` or `availability == archived`), and `ChatChannelLoader`/`profile_screen` only use the result to open the screen.

(e) Add the new methods next to `getMessagesAfter`:

```dart
  @override
  Future<List<Message>> getMessagesByIds(
    String relationshipId,
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const [];
    final user = _currentUser;
    final rows = await _supabase
        .from('messages')
        .select(_messageColumns)
        .eq('relationship_id', relationshipId)
        .inFilter('id', ids);
    return _hydrateMessages(rows, user.id, resolveMediaUrls: false);
  }

  /// Keyset pages on (updated_at, id): the first page is `updated_at >= since`,
  /// every later page continues strictly after the last row's (updated_at,
  /// id). A bulk receipt (`mark_conversation_read` stamping 200 rows in one
  /// transaction) gives hundreds of rows the SAME updated_at; paging on the
  /// timestamp alone would stall or skip there. The merge dedupes by id.
  /// Capped at [_maxChangedSincePages] pages so a very old cursor never turns
  /// a resume into a history download — the first-page reconcile covers the
  /// rest.
  static const _maxChangedSincePages = 4;

  @override
  Future<List<Message>> getMessagesChangedSince(
    String relationshipId, {
    required DateTime since,
    int limit = 50,
  }) async {
    final user = _currentUser;
    final collected = <Map<String, dynamic>>[];
    // updated_at is selected here and only here (see the note below): the
    // keyset needs it on every row.
    const columns = '$_messageColumns,updated_at';
    final sinceIso = since.toUtc().toIso8601String();
    String? lastUpdatedAt;
    String? lastId;
    for (var page = 0; page < _maxChangedSincePages; page++) {
      final rows =
          lastUpdatedAt == null
              ? await _supabase
                  .from('messages')
                  .select(columns)
                  .eq('relationship_id', relationshipId)
                  .gte('updated_at', sinceIso)
                  .order('updated_at', ascending: true)
                  .order('id', ascending: true)
                  .limit(limit)
              : await _supabase
                  .from('messages')
                  .select(columns)
                  .eq('relationship_id', relationshipId)
                  .or(
                    'updated_at.gt.$lastUpdatedAt,'
                    'and(updated_at.eq.$lastUpdatedAt,id.gt.$lastId)',
                  )
                  .order('updated_at', ascending: true)
                  .order('id', ascending: true)
                  .limit(limit);
      collected.addAll(rows);
      if (rows.length < limit) break;
      lastUpdatedAt = rows.last['updated_at'] as String;
      lastId = rows.last['id'] as String;
    }
    return _hydrateMessages(collected, user.id, resolveMediaUrls: false);
  }

  @override
  Future<void> ensureRealtimeConnected() async {
    try {
      if (!_supabase.realtime.isConnected) {
        await _supabase.realtime.connect();
      }
    } catch (_) {
      // The socket's own reconnect loop keeps trying; this only hurries it.
    }
  }
```

`updated_at` is not in `_messageColumns` on purpose: an app build must keep working against a database where migration 20261019100000 is not yet applied, so only `getMessagesChangedSince` selects the column (as `'$_messageColumns,updated_at'`, which `Message.fromRow` ignores) and its failure is caught and logged by the caller in Task 4/6 (`_guard`). The PostgREST keyset string uses the server's own ISO text for `updated_at` (`rows.last['updated_at']`), never a re-parsed `DateTime`, so microsecond precision is kept and the boundary row is not re-served or skipped.

- [ ] **Step 5: Update `FakeChatRepository` and `buildChatContainer`**

In `test/features/chat/support/chat_test_harness.dart`:

(a) Add the import `import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart';`.

(b) Replace `final _events = StreamController<void>.broadcast();` with `final _events = StreamController<ChatRealtimeEvent>.broadcast();` and replace `void emitRealtime() => _events.add(null);` with:

```dart
  /// Pushes a realtime frame to subscribers. Defaults to the `resync` frame a
  /// (re)subscribe emits, which is what every pre-W1a test meant by "a
  /// realtime event".
  void emitRealtime([ChatRealtimeEvent event = const ChatRealtimeEvent.resync()]) =>
      _events.add(event);
```

and `Stream<void> watchConversationEvents(String relationshipId) => _events.stream;` with `Stream<ChatRealtimeEvent> watchConversationEvents(String relationshipId) => _events.stream;`.

(c) Add the seams right after `SentTextMessageArgs? lastSendArgs;`:

```dart
  // --- Scripting seams for the W1a delivery/sync plan. ---

  /// Errors thrown by successive [sendTextMessage] calls, FIFO, consulted
  /// before [nextSendError]. Lets a test script "fails N times, then works".
  final List<Object> sendErrorQueue = [];

  /// Content of every send the fake server accepted, in acceptance order.
  final List<String> sentContents = [];

  /// One-shot error for [findMessageByClientId]: a lost response while
  /// reconciling a 23505 duplicate.
  Object? findMessageError;

  /// When set, [getConversation] throws it (header metadata unreachable).
  Object? getConversationError;

  /// When set, [getPinnedMessages] throws it.
  Object? getPinnedError;

  int getConversationCalls = 0;
  int getMessagesCalls = 0;
  int getMessagesAfterCalls = 0;
  int getPinnedCalls = 0;
  int getMessagesByIdsCalls = 0;
  int ensureRealtimeConnectedCalls = 0;

  /// The `since` the controller last asked [getMessagesChangedSince] for.
  DateTime? lastChangedSinceArg;

  /// Server-side updated_at per message id (migration 20261019100000).
  /// Seeds default to their created_at; every mutation stamps now().
  final Map<String, DateTime> serverUpdatedAt = {};

  void touch(String id, [DateTime? at]) =>
      serverUpdatedAt[id] = at ?? DateTime.now();
```

(d) In `seedIncoming`, before `return message;` add `serverUpdatedAt[id] = createdAt;`.

(e) In `sendTextMessage`, after the `if (simulateDuplicate) { throw ... }` block add:

```dart
    if (sendErrorQueue.isNotEmpty) {
      throw sendErrorQueue.removeAt(0);
    }
```

and after `serverMessages[id] = message;` (end of the method) add `sentContents.add(content); touch(id);`.

(f) In `findMessageByClientId`, as the first statement:

```dart
    final findError = findMessageError;
    if (findError != null) {
      findMessageError = null;
      throw findError;
    }
```

(g) `getMessages`: first statement `getMessagesCalls++;`. Also add a second gate that holds an ALREADY COMPUTED page (the server answered, the network is slow) — `getMessagesGate` gates before the fake reads `serverMessages`, which cannot model "the response predates a later write". Add the field next to `getMessagesGate`:

```dart
  /// Holds a page the fake has already computed, so a test can make a write
  /// land AFTER the server built the response but BEFORE the client saw it.
  Completer<void>? getMessagesResponseGate;
```

and in `getMessages`, replace the two `return` statements with:

```dart
    final page =
        before == null
            ? all.take(limit).toList()
            : all
                .where((m) => m.sortAt.isBefore(before.sortAt))
                .take(limit)
                .toList();
    final responseGate = getMessagesResponseGate;
    if (responseGate != null) await responseGate.future;
    return page;
```

`getMessagesAfter`: first statement `getMessagesAfterCalls++;`. `getPinnedMessages` becomes:

```dart
  @override
  Future<List<Message>> getPinnedMessages(String relationshipId) async {
    getPinnedCalls++;
    final error = getPinnedError;
    if (error != null) throw error;
    return serverMessages.values
        .where(
          (m) =>
              m.relationshipId == relationshipId &&
              pinnedMessageIds.contains(m.id),
        )
        .toList();
  }
```

`getConversation`: after the gate await add

```dart
    getConversationCalls++;
    final error = getConversationError;
    if (error != null) throw error;
```

(h) `editMessage`, `deleteMessage`, `addReaction`, `removeReaction`: add `touch(messageId);` as the last statement of each.

(i) Add the three new methods (anywhere in the class):

```dart
  @override
  Future<List<Message>> getMessagesByIds(
    String relationshipId,
    List<String> ids,
  ) async {
    getMessagesByIdsCalls++;
    return [
      for (final id in ids)
        if (serverMessages[id] case final m? when m.relationshipId == relationshipId)
          m,
    ];
  }

  @override
  Future<List<Message>> getMessagesChangedSince(
    String relationshipId, {
    required DateTime since,
    int limit = 50,
  }) async {
    lastChangedSinceArg = since;
    final changed =
        serverMessages.values
            .where(
              (m) =>
                  m.relationshipId == relationshipId &&
                  !(serverUpdatedAt[m.id] ?? m.createdAt).isBefore(since),
            )
            .toList()
          ..sort(
            (a, b) => (serverUpdatedAt[a.id] ?? a.createdAt).compareTo(
              serverUpdatedAt[b.id] ?? b.createdAt,
            ),
          );
    return changed;
  }

  @override
  Future<void> ensureRealtimeConnected() async {
    ensureRealtimeConnectedCalls++;
  }
```

(j) `buildChatContainer`: add the parameter `Stream<bool>? connectivity,` after `List<Override> extraOverrides = const [],` and the override (before `...extraOverrides`):

```dart
      // The controller listens for connectivity coming back (W1a #1). Unit
      // tests have no connectivity_plus channel; a test that drives the
      // signal passes its own stream.
      chatConnectivityProvider.overrideWith(
        (ref) => connectivity ?? Stream<bool>.value(true),
      ),
```

- [ ] **Step 6: Run the new test and the whole chat suite**

Run: `flutter test test/features/chat/chat_realtime_event_test.dart`
Expected: `All tests passed!` (7 tests).

Run: `flutter test test/features/chat`
Expected: `All tests passed!` — nothing consumed the old `Stream<void>` except `chat_state.dart`, whose `.listen((_) {...})` still compiles against the typed stream.

- [ ] **Step 7: Checkpoint**

Run: `flutter analyze lib/features/chat/data/repositories/chat_repository.dart lib/features/chat/data/repositories/supabase_chat_repository.dart test/features/chat/support/chat_test_harness.dart test/features/chat/chat_realtime_event_test.dart | grep -E '^\s*(error|warning) '`
Expected: no output. No commit (the owner commits).

---

### Task 4: Sync primitives — window reconcile, refresh-by-id, changes-since cursor (#6, #7 client side)

**Files:**
- Modify: `lib/features/chat/presentation/state/chat_state.dart` (`ChatController.loadMessages`, `loadMoreMessages`, `_catchUpFromCursor`, new `reconcileWindow`, `refreshMessagesByIds`, `syncChangesSinceCursor`, `_onlyLoadedSpan`, `_oldestFetchedCursor`; `_appendOlderMessages` removed)
- Test: `test/features/chat/chat_sync_reconcile_test.dart`

**Interfaces:**
- Consumes: `ChatRepository.getMessagesByIds`, `getMessagesChangedSince` (Task 3); `FakeChatRepository.touch`, `lastChangedSinceArg`, `serverUpdatedAt`.
- Produces (used by Task 6's handler):
  - `@visibleForTesting static List<Message> ChatController.reconcileWindow(List<Message> current, List<Message> fresh, {ChatMessageCursor? before, required bool exhaustive, Set<String>? knownBefore})`
  - `Future<void> ChatController.refreshMessagesByIds(Set<String> ids)`
  - `Future<void> ChatController.syncChangesSinceCursor()`; `static const Duration ChatController.changesSinceOverlap`
  - `static bool ChatController.isOlderThanCursor(Message m, ChatMessageCursor c)`

Design: the server is the source of truth for the span a page covered. A first page covers everything from its oldest row up; an older page covers everything between the paging cursor and its oldest row; a page shorter than the limit covers everything below it too (`exhaustive`). Any canonical (non-`_local_`) row in that span that the page did not return is gone on the server and is dropped — outbox-backed `_local_` rows are never touched, and neither is a canonical row the client did not hold when the page request left (`knownBefore`): a send acknowledged, or a catch-up row merged, while the page was in flight is newer than the server's snapshot and must not be mistaken for a deletion. For changes to rows the page does not cover, two reads: by id (an event named the row) and by `updated_at` cursor (resume/reconnect). Both only *patch rows already loaded* or add rows inside the loaded span — an unknown row older than everything loaded would otherwise appear glued to the bottom of the list with a hole above it; paging back fetches it in order. The `updated_at` cursor is the newest server timestamp the phone holds minus a fixed overlap (`changesSinceOverlap`, 30 s): `now()` is transaction *start* time, so a transaction that started before but committed after the one the phone last saw carries a smaller `updated_at`; the overlap re-reads that window (the merge is idempotent) instead of skipping it. Paging back starts from the oldest row the server confirmed this session (`_oldestFetchedCursor`), not from the oldest cached row, so every cached row below the first page is re-fetched (incoming wins) and reconciled on the way down.

- [ ] **Step 1: Write the failing tests**

Create `test/features/chat/chat_sync_reconcile_test.dart`:

```dart
import 'package:attune/features/chat/config/chat_config.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

class _Booted {
  _Booted(this.controller, this.container, this.conversation);
  final ChatController controller;
  final ProviderContainer container;
  final Conversation conversation;
  ChatState get state => container.read(chatControllerProvider(conversation));
  ChatCacheService get cache => container.read(chatCacheServiceProvider);
}

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';
  final t0 = DateTime(2026, 10, 18, 9);

  Message row(String id, int minutes, {String content = ''}) =>
      Message.fromRow({
        'id': id,
        'relationship_id': relId,
        'sender_id': 'partner',
        'client_message_id': 'c-$id',
        'content': content.isEmpty ? id : content,
        'created_at': t0.add(Duration(minutes: minutes)).toUtc().toIso8601String(),
        'source': 'native',
      }, currentUserId: userId);

  Future<_Booted> boot(
    FakeChatRepository repo, {
    int pageSize = 50,
    ChatCacheService? cache,
  }) async {
    final container = buildChatContainer(
      repository: repo,
      userId: userId,
      cache: cache,
      extraOverrides: [
        chatConfigProvider.overrideWithValue(
          ChatConfig(messagePageSize: pageSize),
        ),
      ],
    );
    addTearDown(container.dispose);
    final convo = activeConversation(relId);
    repo.conversationOverride = convo;
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return _Booted(controller, container, convo);
  }

  void seed(FakeChatRepository repo, int count) {
    for (var i = 1; i <= count; i++) {
      repo.seedIncoming(
        id: 'm-$i',
        relationshipId: relId,
        senderId: 'partner',
        content: 'message $i',
        createdAt: t0.add(Duration(minutes: i)),
      );
    }
  }

  group('reconcileWindow (pure)', () {
    test('drops a canonical row inside the fetched span that the page lacks, '
        'keeps rows below the span and every _local_ row', () {
      final a = row('a', 10), b = row('b', 9), c = row('c', 8), d = row('d', 7);
      final local = Message.optimistic(
        id: '_local_x',
        clientMessageId: 'x',
        relationshipId: relId,
        senderId: userId,
        content: 'mine',
        createdAt: t0.add(const Duration(minutes: 11)),
      );
      final result = ChatController.reconcileWindow(
        [local, a, b, c, d],
        [a, c],
        exhaustive: false,
      );
      expect(result.map((m) => m.id), ['_local_x', 'a', 'c', 'd']);
    });

    test('an exhaustive page (shorter than the limit) owns everything below it too', () {
      final a = row('a', 10), c = row('c', 8), d = row('d', 7);
      final result = ChatController.reconcileWindow(
        [a, c, d],
        [a, c],
        exhaustive: true,
      );
      expect(result.map((m) => m.id), ['a', 'c']);
    });

    test('an empty exhaustive first page clears every canonical row', () {
      final a = row('a', 10), b = row('b', 9);
      final result = ChatController.reconcileWindow(
        [a, b],
        const [],
        exhaustive: true,
      );
      expect(result, isEmpty);
    });

    test('with a paging cursor only the span below the cursor is reconciled', () {
      final a = row('a', 10), b = row('b', 9), c = row('c', 8), d = row('d', 7), e = row('e', 6);
      final result = ChatController.reconcileWindow(
        [a, b, c, d, e],
        [c, e],
        before: ChatMessageCursor(sortAt: b.sortAt, id: b.id),
        exhaustive: false,
      );
      // d sat between c and e and the server did not return it; a and b are
      // above the cursor and none of this page's business.
      expect(result.map((m) => m.id), ['a', 'b', 'c', 'e']);
    });

    test('a row sharing the oldest fetched sortAt but with a lower id is below the span', () {
      final a = row('a', 10);
      final c2 = row('c2', 8);
      final c1 = row('c1', 8); // same minute, lower id: it is on the NEXT page
      final result = ChatController.reconcileWindow(
        [a, c2, c1],
        [a, c2],
        exhaustive: false,
      );
      expect(result.map((m) => m.id), ['a', 'c2', 'c1']);
    });
  });

  group('first page reconcile (#6)', () {
    test('a message deleted on the server disappears from state and cache on the next load', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 3);
      final b = await boot(repo);
      expect(b.state.messages.map((m) => m.id), containsAll(['m-1', 'm-2', 'm-3']));

      repo.serverMessages.remove('m-2');
      await b.controller.loadMessages(silent: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(b.state.messages.map((m) => m.id), ['m-3', 'm-1']);
      final cached = await b.cache.readMessages(userId, relId);
      expect(cached.map((m) => m.id), ['m-3', 'm-1']);
    });

    test('a wiped table clears the history but keeps a queued local message', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 2);
      final b = await boot(repo);
      repo.sendErrorQueue.add(Exception('network down'));
      await b.controller.sendMessage('still mine');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        b.state.messages.firstWhere((m) => m.content == 'still mine').status,
        MessageStatus.queued,
      );

      repo.serverMessages.clear();
      await b.controller.loadMessages(silent: true);

      expect(b.state.messages.map((m) => m.content), ['still mine']);
    });

    test('a row acknowledged while the first page was in flight is not dropped by that page', () async {
      // The page request left before the send was acknowledged, so the
      // response cannot contain the new row. Reconcile may only drop rows the
      // client held BEFORE the request left, never one that arrived while it
      // ran — otherwise a just-sent bubble vanishes until the next catch-up.
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 2);
      final b = await boot(repo);
      final gate = Completer<void>();
      repo.getMessagesResponseGate = gate;
      final page = b.controller.loadMessages(silent: true);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await b.controller.sendMessage('while the page was in flight');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(b.state.messages.first.status, MessageStatus.sent);

      repo.getMessagesResponseGate = null;
      gate.complete();
      await page;

      expect(
        b.state.messages.map((m) => m.content),
        contains('while the page was in flight'),
      );
      expect(b.state.messages.first.id.startsWith('_local_'), isFalse);
    });
  });

  group('older pages (#7a)', () {
    test('loadMoreMessages refreshes rows it already holds from the cache', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 8);
      // A cache from a previous session with a stale copy of an old row.
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final stale = [
        for (var i = 8; i >= 1; i--)
          repo.serverMessages['m-$i']!.copyWith(
            content: i == 2 ? 'stale copy' : 'message $i',
          ),
      ];
      await cache.writeMessages(userId, relId, stale);
      final b = await boot(repo, pageSize: 5, cache: cache);
      expect(b.state.messages.firstWhere((m) => m.id == 'm-2').content, 'stale copy',
          reason: 'row 2 is outside the first page, so it still shows the cache');

      await b.controller.loadMoreMessages();

      expect(b.state.messages.firstWhere((m) => m.id == 'm-2').content, 'message 2');
      expect(b.state.hasMore, isFalse);
    });

    test('loadMoreMessages drops a row in its span that the server no longer has', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 8);
      final cache = ChatCacheService.forTesting(backend: memBackend());
      await cache.writeMessages(userId, relId, [
        for (var i = 8; i >= 1; i--) repo.serverMessages['m-$i']!,
      ]);
      repo.serverMessages.remove('m-2');
      final b = await boot(repo, pageSize: 5, cache: cache);
      expect(b.state.messages.any((m) => m.id == 'm-2'), isTrue);

      await b.controller.loadMoreMessages();

      expect(b.state.messages.any((m) => m.id == 'm-2'), isFalse);
    });
  });

  group('refreshMessagesByIds (#7b)', () {
    test('a reaction on a row outside the newest page is applied in place', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 8);
      final b = await boot(repo, pageSize: 5);
      await b.controller.loadMoreMessages();
      expect(b.state.messages, hasLength(8));

      await repo.addReaction(relationshipId: relId, messageId: 'm-2', emoji: '❤️');
      await b.controller.refreshMessagesByIds({'m-2'});

      final updated = b.state.messages.firstWhere((m) => m.id == 'm-2');
      expect(updated.reactions['❤️'], contains(userId));
      expect(repo.getMessagesByIdsCalls, 1);
    });

    test('an id the server no longer returns is removed locally', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 3);
      final b = await boot(repo);

      repo.serverMessages.remove('m-3');
      await b.controller.refreshMessagesByIds({'m-3'});

      expect(b.state.messages.any((m) => m.id == 'm-3'), isFalse);
      final cached = await b.cache.readMessages(userId, relId);
      expect(cached.any((m) => m.id == 'm-3'), isFalse);
    });
  });

  group('syncChangesSinceCursor (#7c)', () {
    test('edits and deletions made while away land on loaded rows', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 4);
      final b = await boot(repo);

      await repo.editMessage(messageId: 'm-2', newContent: 'edited away');
      await repo.deleteMessage('m-3');
      await b.controller.syncChangesSinceCursor();

      expect(b.state.messages.firstWhere((m) => m.id == 'm-2').content, 'edited away');
      expect(b.state.messages.firstWhere((m) => m.id == 'm-3').isDeleted, isTrue);
    });

    test('the sync cursor is the newest server timestamp minus the overlap, '
        'not the device clock', () async {
      // A phone an hour ahead must not ask for "changes since an hour from
      // now" and miss everything: the cursor comes from the rows it holds.
      // The fixed overlap re-reads late-committing transactions (now() is
      // transaction start time) instead of skipping them.
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 4); // newest row is t0 + 4 min, long before DateTime.now()
      final b = await boot(repo);

      await b.controller.syncChangesSinceCursor();

      expect(
        repo.lastChangedSinceArg,
        t0.add(const Duration(minutes: 4)).subtract(ChatController.changesSinceOverlap),
      );
      expect(ChatController.changesSinceOverlap, const Duration(seconds: 30));
    });

    test('a changed row older than everything loaded is not glued onto the list', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 12);
      final b = await boot(repo, pageSize: 5);
      expect(b.state.messages, hasLength(5));
      expect(b.state.hasMore, isTrue);

      repo.touch('m-1'); // reacted to, far below the loaded window
      await b.controller.syncChangesSinceCursor();

      expect(b.state.messages.any((m) => m.id == 'm-1'), isFalse,
          reason: 'it would render with a hole above it; paging back fetches it in order');
    });

    test('with nothing loaded the cursor sync is a no-op', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);
      await b.controller.syncChangesSinceCursor();
      expect(repo.lastChangedSinceArg, isNull);
    });
  });

  test('_catchUpFromCursor with no canonical row loads the first page instead of '
      'paging the whole history forward', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    seed(repo, 3);
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    final convo = activeConversation(relId);
    repo.conversationOverride = convo;
    repo.getMessagesGate = Completer<void>();
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // State is still empty (first page gated). A realtime frame arrives.
    final before = repo.getMessagesAfterCalls;
    repo.emitRealtime(const ChatRealtimeEvent(ChatRealtimeKind.messageInsert, messageId: 'm-3'));
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(repo.getMessagesAfterCalls, before,
        reason: 'an open-ended forward page would walk the entire history');
    repo.getMessagesGate!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(chatControllerProvider(convo)).messages, hasLength(3));
    expect(repo.getMessagesAfterCalls, before, reason: 'still no forward page');
  });
}
```

Add `import 'dart:async';` at the top (for `Completer`).

- [ ] **Step 2: Run to verify failure for the right reason**

Run: `flutter test test/features/chat/chat_sync_reconcile_test.dart`
Expected: compile errors `The method 'reconcileWindow' isn't defined`, `'refreshMessagesByIds' isn't defined`, `'syncChangesSinceCursor' isn't defined`.

- [ ] **Step 3: Implement the primitives in `ChatController`**

In `lib/features/chat/presentation/state/chat_state.dart`:

(a) Replace the whole `loadMessages` try-block body's state assignment so the page reconciles its window. The method becomes:

```dart
  Future<void> loadMessages({bool silent = false}) async {
    if (state.conversation.availability == ConversationAvailability.archived) {
      return;
    }
    if (!silent) {
      state = state.copyWith(isLoading: true, error: null);
    }
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    try {
      final repository = ref.read(chatRepositoryProvider);
      final pageSize = ref.read(chatConfigProvider).messagePageSize;
      // Only rows held BEFORE the request left may be reconciled away by its
      // response: a send acknowledged or a catch-up row merged while the
      // request was in flight is newer than the server's snapshot.
      final knownBefore = _canonicalIdsHeld();
      final messages = await repository.getMessages(
        relationshipId,
        limit: pageSize,
      );

      if (!mounted) return;
      if (messages.isNotEmpty) {
        // First server-confirmed row of the session; older pages continue
        // from here (see _oldestFetchedCursor).
        _oldestFetchedCursor ??= ChatMessageCursor(
          sortAt: messages.last.sortAt,
          id: messages.last.id,
        );
      }
      // The page is authoritative for the span it covers (#6): a row the
      // server no longer returns inside that span is gone everywhere.
      final merged = reconcileWindow(
        _mergeMessages(messages),
        messages,
        exhaustive: messages.length < pageSize,
        knownBefore: knownBefore,
      );
      state = state.copyWith(
        isLoading: false,
        messages: merged,
        hasMore: messages.length >= pageSize,
        lastSyncedAt: DateTime.now(),
      );
      unawaited(
        ref
            .read(chatCacheServiceProvider)
            .writeMessages(user.id, relationshipId, state.messages),
      );
      unawaited(_discoverAndPrewarmPosters(state.messages));
      _maybeReceiveHaptic();
    } catch (error) {
      final mapped = ChatError.from(error);
      ChatLog.e(
        'load messages failed cat=${mapped.category.name} '
        'id=${mapped.correlationId} rel=${ChatLog.shortId(relationshipId)}',
        mapped.cause,
      );
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        // On a silent (realtime/reconnect) refresh, keep the cached view rather
        // than flashing an error banner over live content.
        error: silent ? state.error : mapped.toUserMessage(),
      );
    }
  }
```

(b) `loadMoreMessages`: incoming rows win over stale copies and the paged span reconciles. Replace the method:

```dart
  /// The oldest row the SERVER has confirmed this session (first page, then
  /// each older page). Paging continues from here, not from the oldest row
  /// in memory: the cache may hold 200 rows the server never re-sent, and
  /// paging from its bottom would skip refreshing every one of them.
  ChatMessageCursor? _oldestFetchedCursor;

  Future<void> loadMoreMessages() async {
    if (state.conversation.availability == ConversationAvailability.archived) {
      return;
    }
    if (state.isLoadingMore || !state.hasMore || state.messages.isEmpty) return;
    state = state.copyWith(isLoadingMore: true);

    try {
      final repository = ref.read(chatRepositoryProvider);
      final pageSize = ref.read(chatConfigProvider).messagePageSize;
      final cursor =
          _oldestFetchedCursor ??
          ChatMessageCursor(
            sortAt: state.messages.last.sortAt,
            id: state.messages.last.id,
          );
      final knownBefore = _canonicalIdsHeld();
      final older = await repository.getMessages(
        relationshipId,
        before: cursor,
        limit: pageSize,
      );

      if (!mounted) return;
      if (older.isNotEmpty) {
        _oldestFetchedCursor = ChatMessageCursor(
          sortAt: older.last.sortAt,
          id: older.last.id,
        );
      }
      // Incoming wins (a cached copy of an old row may predate an edit, a
      // deletion or a reaction) and the span below the cursor is reconciled
      // against what the server actually returned (#7).
      state = state.copyWith(
        isLoadingMore: false,
        messages: reconcileWindow(
          _mergeMessages(older),
          older,
          before: cursor,
          exhaustive: older.length < pageSize,
          knownBefore: knownBefore,
        ),
        hasMore: older.length >= pageSize,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(isLoadingMore: false);
    }
  }

  /// Canonical ids in memory right now — the set a page response may
  /// reconcile against (see [reconcileWindow]'s `knownBefore`).
  Set<String> _canonicalIdsHeld() => {
    for (final m in state.messages)
      if (!m.id.startsWith('_local_')) m.id,
  };
```

Delete `_appendOlderMessages` (no remaining caller).

(c) In `_catchUpFromCursor`, replace the block that builds `cursor` and the `try` with:

```dart
    ChatMessageCursor? cursor;
    for (final message in state.messages) {
      if (message.id.startsWith('_local_')) continue;
      // state.messages is newest-first; the first canonical row is the newest.
      cursor = ChatMessageCursor(sortAt: message.sortAt, id: message.id);
      break;
    }
    if (cursor == null) {
      // Nothing canonical yet: the first page owns this case. An open-ended
      // forward catch-up would page the entire history oldest-first.
      await loadMessages(silent: true);
      return;
    }

    try {
      final repository = ref.read(chatRepositoryProvider);
      final fresh = await repository.getMessagesAfter(
        relationshipId,
        after: cursor,
        limit: ref.read(chatConfigProvider).messagePageSize,
      );
      if (!mounted || fresh.isEmpty) return;
      state = state.copyWith(
        messages: _mergeMessages(fresh),
        lastSyncedAt: DateTime.now(),
      );
      unawaited(
        ref
            .read(chatCacheServiceProvider)
            .writeMessages(user.id, relationshipId, state.messages),
      );
      unawaited(_prewarmPosters(state.messages));
      _maybeReceiveHaptic();
    } catch (_) {
      // Non-fatal; loadMessages() refresh follows.
    }
```

(d) Add the new primitives after `_bySortThenId`:

```dart
  /// Keyset "older than": (sortAt, id) below the cursor, the same order the
  /// server pages on.
  static bool isOlderThanCursor(Message m, ChatMessageCursor c) =>
      m.sortAt.isBefore(c.sortAt) ||
      (m.sortAt.isAtSameMomentAs(c.sortAt) && m.id.compareTo(c.id) < 0);

  /// Makes a fetched page authoritative for the span it covered.
  ///
  /// The cache was only ever merged into, never trimmed, so a row deleted
  /// on the server (a wipe before testing, a revoked import, a cascade)
  /// stayed on every phone until sign-out and new messages rendered under
  /// it (#6). The span is: everything at or above the page's oldest row
  /// (a first page), or everything between [before] and that oldest row
  /// (an older page); a page shorter than the limit is [exhaustive] and
  /// owns everything below it as well. Canonical rows in the span that the
  /// page did not return are dropped. `_local_` rows belong to the outbox
  /// and are never touched here. When [knownBefore] is given (the canonical
  /// ids held when the request LEFT), only those may be dropped: a row that
  /// arrived while the request was in flight — a send acknowledged, a
  /// catch-up merged — postdates the server's snapshot and is kept.
  @visibleForTesting
  static List<Message> reconcileWindow(
    List<Message> current,
    List<Message> fresh, {
    ChatMessageCursor? before,
    required bool exhaustive,
    Set<String>? knownBefore,
  }) {
    final freshIds = <String>{for (final m in fresh) m.id};
    // fresh is newest-first; its last row is the oldest the page covered.
    final floor =
        fresh.isEmpty || exhaustive
            ? null
            : ChatMessageCursor(sortAt: fresh.last.sortAt, id: fresh.last.id);

    bool inSpan(Message m) {
      if (before != null && !isOlderThanCursor(m, before)) return false;
      if (floor == null) return true;
      return !isOlderThanCursor(m, floor);
    }

    return [
      for (final m in current)
        if (m.id.startsWith('_local_') ||
            freshIds.contains(m.id) ||
            (knownBefore != null && !knownBefore.contains(m.id)) ||
            !inSpan(m))
          m,
    ];
  }

  /// Keeps only rows that patch something already loaded or fall inside the
  /// loaded span. An unknown row older than everything loaded would render
  /// glued to the bottom with a hole above it; paging back fetches it in
  /// order. With the whole history loaded there is no hole to make.
  List<Message> _onlyLoadedSpan(List<Message> rows) {
    final known = <String>{for (final m in state.messages) m.id};
    Message? oldest;
    for (final m in state.messages) {
      if (m.id.startsWith('_local_')) continue;
      if (oldest == null ||
          isOlderThanCursor(
            m,
            ChatMessageCursor(sortAt: oldest.sortAt, id: oldest.id),
          )) {
        oldest = m;
      }
    }
    if (oldest == null || !state.hasMore) return rows;
    final floor = ChatMessageCursor(sortAt: oldest.sortAt, id: oldest.id);
    return [
      for (final m in rows)
        if (known.contains(m.id) || !isOlderThanCursor(m, floor)) m,
    ];
  }

  /// Re-reads the named rows from the server and patches them in place,
  /// wherever they sit in history — an edit, a deletion, a reaction or a
  /// receipt on a message outside the newest page used to be invisible
  /// until the row aged out of the cache (#7). Ids the server does not
  /// return are gone and are removed locally.
  Future<void> refreshMessagesByIds(Set<String> ids) async {
    if (ids.isEmpty) return;
    if (state.conversation.availability == ConversationAvailability.archived) {
      return;
    }
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final fresh = await ref
        .read(chatRepositoryProvider)
        .getMessagesByIds(relationshipId, ids.toList());
    if (!mounted) return;
    final returned = <String>{for (final m in fresh) m.id};
    final gone = <String>{
      for (final id in ids)
        if (!returned.contains(id)) id,
    };
    var merged = _mergeMessages(_onlyLoadedSpan(fresh));
    if (gone.isNotEmpty) {
      merged = merged.where((m) => !gone.contains(m.id)).toList();
    }
    state = state.copyWith(messages: merged, lastSyncedAt: DateTime.now());
    unawaited(
      ref
          .read(chatCacheServiceProvider)
          .writeMessages(user.id, relationshipId, state.messages),
    );
  }

  /// How far behind the newest held server timestamp the changes-since read
  /// starts. Postgres `now()` is transaction START time: a transaction that
  /// began before, but committed after, the newest change this phone saw
  /// carries a smaller `updated_at` and a bare cursor would skip it forever.
  /// Re-reading this window is idempotent (merge by id, incoming wins) and
  /// costs at most a page; a miss would cost a lost edit or receipt.
  static const changesSinceOverlap = Duration(seconds: 30);

  /// Pulls every row whose server `updated_at` is at or after the newest
  /// server timestamp this phone holds, less [changesSinceOverlap]. The
  /// cursor is built from server timestamps on loaded rows only — never the
  /// device clock, which may be off by hours — and is at most the true newest
  /// `updated_at`, so an over-fetch is possible (idempotent) but a miss is
  /// not.
  Future<void> syncChangesSinceCursor() async {
    if (state.conversation.availability == ConversationAvailability.archived) {
      return;
    }
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    DateTime? newest;
    for (final m in state.messages) {
      if (m.id.startsWith('_local_')) continue;
      for (final t in <DateTime?>[
        m.createdAt,
        m.sortAt,
        m.editedAt,
        m.deletedAt,
        m.deliveredAt,
        m.readAt,
        m.viewedAt,
      ]) {
        if (t != null && (newest == null || t.isAfter(newest))) newest = t;
      }
    }
    if (newest == null) return; // nothing loaded: the first page is the sync
    final since = newest.subtract(changesSinceOverlap);

    final changed = await ref
        .read(chatRepositoryProvider)
        .getMessagesChangedSince(
          relationshipId,
          since: since,
          limit: ref.read(chatConfigProvider).messagePageSize,
        );
    if (!mounted || changed.isEmpty) return;
    final applicable = _onlyLoadedSpan(changed);
    if (applicable.isEmpty) return;
    state = state.copyWith(
      messages: _mergeMessages(applicable),
      lastSyncedAt: DateTime.now(),
    );
    unawaited(
      ref
          .read(chatCacheServiceProvider)
          .writeMessages(user.id, relationshipId, state.messages),
    );
  }
```

Dart note: `newest` is a local reassigned in a loop, so it is not promoted; `newest.subtract(...)` after the null check needs `newest!` only if the analyzer still sees it as nullable — if so write `final since = newest!.subtract(changesSinceOverlap);`.

- [ ] **Step 4: Run the new tests and the chat suite**

Run: `flutter test test/features/chat/chat_sync_reconcile_test.dart`
Expected: `All tests passed!` (16 tests).

Run: `flutter test test/features/chat`
Expected: `All tests passed!`. If `chat_edge_cases_test.dart` "Reconnect after missed events" fails, it is because the fake's `getMessagesAfter(after: null)` is no longer the path taken — it is not; the controller has a canonical cursor there. Any other failure is a real regression: stop and fix.

- [ ] **Step 5: Checkpoint**

Run: `flutter analyze lib/features/chat/presentation/state/chat_state.dart test/features/chat/chat_sync_reconcile_test.dart | grep -E '^\s*(error|warning) '`
Expected: no output. No commit (the owner commits).

---

### Task 5: Outbox engine — network failures never go red, one timer at the queue head, escape-proof 23505 reconcile, FIFO sends, read-only terminal state, outbox authority on restart (#2, #3, #4, #5)

**Files:**
- Modify: `lib/features/chat/presentation/state/chat_state.dart` (`ChatController`: `sendMessage`, `sendVoiceMessage`, `sendStreakMessage`, `sendVideoMessage`, `sendEphemeralVideoMessage`, `retryMessage`, `flushOutbox`, `_attemptSend`, `_handleSendFailure`, `_refreshConversation`, `_mergeInitialMessages`, `dispose`; new `_enqueueAndFlush`, `_armRetryTimer`, `_settleQueueAfterFlush`, `_reconcileDuplicate`, `_parkForRetry`, `_failQueuedForInactiveRelationship`, `debugSetConversation`)
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (the `onRetry:` argument in the message-list builder)
- Test: `test/features/chat/chat_outbox_engine_test.dart`

**Interfaces:**
- Consumes: `FakeChatRepository.sendErrorQueue`, `sentContents`, `findMessageError`, `simulateDuplicate`/`duplicateClientMessageId` (Task 3), `PendingSend`, `ChatCacheService.putOutbox/readOutbox`.
- Produces: `Future<void> ChatController.flushOutbox({bool force = false})` (`force` ignores backoff — used by every "network is back" trigger); `Future<bool> _attemptSend(PendingSend)` (true = acknowledged by the server); `@visibleForTesting void debugSetConversation(Conversation)`.

Design (the WhatsApp outbox rules this encodes):
1. **Only server rejections count toward the attempt cap.** `offline`, `unavailable`, `rateLimited` keep the clock icon forever at the capped backoff (≤ 64 s); `unknown` still gives up after five tries; `isPermanent` categories fail at once.
2. **One timer, always armed at the queue head.** After every flush and every failure the timer is (re)armed to the earliest due item of the FIFO head, never cancelled in favour of a later deadline. Nothing can sit at "Queued" with no timer.
3. **Strict FIFO for anything waiting for the network.** Every send enters the outbox first and leaves through `flushOutbox`; a flush stops at the first item that is not yet due or that just failed, so a later message never overtakes an earlier one. Media that is still being prepared or is mid-upload (in flight) does not hold texts up — the WhatsApp behaviour — because order among *waiting* items is what the two phones compare.
4. **A 23505 reconcile can never escape.** `_reconcileDuplicate` owns its own network calls and funnels any failure to `_handleSendFailure`; a last-resort guard around the whole attempt parks the row for retry rather than leaving it at `sending`.
5. **A read-only relationship ends the queue honestly.** Items are marked `failedPermanent(relationshipInactive)`, bubbles turn to failed (removable) under the chat's existing read-only banner; Retry is hidden when the chat cannot send. (`ChatState.copyWith` clears `error` on every state write by design, so the explanation lives in the bubble state and the read-only banner, not in a transient error line.)
6. **On restart the outbox is authoritative** for every `_local_` row; a cached optimistic snapshot never overrides it, and a cached `_local_` row with no outbox entry is dropped.

- [ ] **Step 1: Write the failing tests**

Create `test/features/chat/chat_outbox_engine_test.dart`:

```dart
import 'dart:io';

import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/chat_test_harness.dart';

class _Booted {
  _Booted(this.controller, this.container, this.conversation, this.cache);
  final ChatController controller;
  final ProviderContainer container;
  final Conversation conversation;
  final ChatCacheService cache;
  ChatState get state => container.read(chatControllerProvider(conversation));
  Future<List<PendingSend>> outbox() =>
      cache.readOutbox('user-a', relationshipId: 'rel-1');
}

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';

  Future<_Booted> boot(
    FakeChatRepository repo, {
    ChatCacheService? cache,
    Conversation? conversation,
  }) async {
    final effectiveCache =
        cache ?? ChatCacheService.forTesting(backend: memBackend());
    final container = buildChatContainer(
      repository: repo,
      userId: userId,
      cache: effectiveCache,
    );
    addTearDown(container.dispose);
    final convo = conversation ?? activeConversation(relId);
    repo.conversationOverride = convo;
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return _Booted(controller, container, convo, effectiveCache);
  }

  PendingSend pendingText(
    String clientMessageId,
    String text, {
    required DateTime createdAt,
    DateTime? nextAttemptAt,
    int attempts = 0,
    PendingSendState state = PendingSendState.queued,
  }) => PendingSend(
    clientMessageId: clientMessageId,
    relationshipId: relId,
    senderId: userId,
    text: text,
    createdAt: createdAt,
    attempts: attempts,
    nextAttemptAt: nextAttemptAt,
    state: state,
  );

  group('#2 failure policy', () {
    test('seven consecutive offline failures keep the message queued, never failed', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      for (var i = 0; i < 7; i++) {
        repo.sendErrorQueue.add(const SocketException('no route to host'));
      }
      final b = await boot(repo);

      await b.controller.sendMessage('on my way');
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(b.state.messages.single.status, MessageStatus.queued,
            reason: 'offline attempt ${i + 1} must not consume the cap');
        await b.controller.flushOutbox(force: true);
      }
      expect(repo.sendCallCount, 7);
      final row = (await b.outbox()).single;
      expect(row.state, PendingSendState.queued);
      expect(row.nextAttemptAt, isNotNull);

      await b.controller.flushOutbox(force: true); // the network is back
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(b.state.messages.single.status, MessageStatus.sent);
      expect(await b.outbox(), isEmpty);
    });

    test('a server-side unknown error still gives up after five attempts', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      for (var i = 0; i < 5; i++) {
        repo.sendErrorQueue.add(StateError('something odd'));
      }
      final b = await boot(repo);

      await b.controller.sendMessage('x');
      for (var i = 0; i < 4; i++) {
        await b.controller.flushOutbox(force: true);
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(repo.sendCallCount, 5);
      expect(b.state.messages.single.status, MessageStatus.failed);
      expect((await b.outbox()).single.state, PendingSendState.failedPermanent);
    });

    test('a 42501 against a now read-only chat is explained as read-only', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      repo.sendDelay = const Duration(milliseconds: 80);
      repo.nextSendError = const PostgrestException(
        message: 'new row violates row-level security policy',
        code: '42501',
      );
      final b = await boot(repo);

      final send = b.controller.sendMessage('racing the pause');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // The partner paused while the insert was in flight.
      b.controller.debugSetConversation(readOnlyConversation(relId));
      await send;

      expect(b.state.messages.single.status, MessageStatus.failed);
      expect(b.state.error, 'This relationship chat is read-only.');
      expect((await b.outbox()).single.lastErrorCategory, 'relationshipInactive');
    });
  });

  group('#3 one timer at the queue head', () {
    test('an earlier item with a later deadline is waited for, then both go in order', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final now = DateTime.now();
      await cache.putOutbox(userId, pendingText('a', 'A',
          createdAt: now.subtract(const Duration(seconds: 10)),
          attempts: 2,
          nextAttemptAt: now.add(const Duration(milliseconds: 350))));
      await cache.putOutbox(userId, pendingText('b', 'B',
          createdAt: now.subtract(const Duration(seconds: 5)),
          attempts: 1,
          nextAttemptAt: now.add(const Duration(milliseconds: 100))));

      final b = await boot(repo, cache: cache);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(repo.sendCallCount, 0, reason: 'B must not overtake A');

      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(repo.sentContents, ['A', 'B']);
      expect(await b.outbox(), isEmpty);
      expect(b.state.messages.map((m) => m.status), everyElement(MessageStatus.sent));
    });

    test('a failure re-arms the timer and the item is retried without any user action', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      repo.sendErrorQueue.add(const SocketException('blip'));
      final b = await boot(repo);

      await b.controller.sendMessage('retry me');
      expect(b.state.messages.single.status, MessageStatus.queued);

      // First backoff window is 1-2 s (1 << 1 seconds, equal jitter).
      await Future<void>.delayed(const Duration(milliseconds: 2300));
      expect(b.state.messages.single.status, MessageStatus.sent);
      expect(repo.sendCallCount, 2);
    });
  });

  group('#4 the 23505 reconcile cannot escape', () {
    test('a lost response during reconcile leaves a queued, retryable row — not a stuck clock', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      repo.simulateDuplicate = true;
      repo.findMessageError = const SocketException('timed out');
      final b = await boot(repo);

      await b.controller.sendMessage('dup'); // must complete without throwing
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final bubble = b.state.messages.single;
      expect(bubble.status, MessageStatus.queued);
      expect(b.state.isSending, isFalse);
      final row = (await b.outbox()).single;
      expect(row.state, PendingSendState.queued);
      expect(row.nextAttemptAt, isNotNull);

      // The network returns: the duplicate reconciles to the canonical row.
      repo.duplicateClientMessageId = bubble.clientMessageId;
      await b.controller.flushOutbox(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(b.state.messages.single.status, MessageStatus.sent);
      expect(b.state.messages.single.id.startsWith('_local_'), isFalse);
      expect(await b.outbox(), isEmpty);
    });

    test('a canonical row already in the cache wins over its own stale outbox row, which then reconciles', () async {
      // Crash between the server ack and removeOutbox: both exist on restart.
      final repo = FakeChatRepository(currentUserId: userId);
      final canonical = repo.seedIncoming(
        id: 'srv-1',
        relationshipId: relId,
        senderId: userId,
        content: 'acked before the crash',
        createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      final cache = ChatCacheService.forTesting(backend: memBackend());
      await cache.writeMessages(userId, relId, [canonical]);
      await cache.putOutbox(userId, pendingText(
        canonical.clientMessageId, 'acked before the crash',
        createdAt: canonical.createdAt,
        state: PendingSendState.sending,
      ));
      repo.simulateDuplicate = true;
      repo.duplicateClientMessageId = canonical.clientMessageId;

      final b = await boot(repo, cache: cache);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(b.state.messages, hasLength(1));
      expect(b.state.messages.single.id, 'srv-1');
      expect(await b.outbox(), isEmpty, reason: 'the stale row reconciled via 23505');
    });
  });

  group('#5 FIFO', () {
    test('a message typed while an earlier one waits for the network goes out after it', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      repo.sendErrorQueue.add(const SocketException('offline'));
      final b = await boot(repo);

      await b.controller.sendMessage('A');
      await b.controller.sendMessage('B');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(repo.sendCallCount, 1, reason: 'B waits behind A');
      expect(b.state.messages.map((m) => m.status), everyElement(MessageStatus.queued));

      await b.controller.flushOutbox(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(repo.sentContents, ['A', 'B']);
    });

    test('tapping retry sends the queue in order, not the tapped message first', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      repo.sendErrorQueue.add(const SocketException('offline'));
      final b = await boot(repo);
      await b.controller.sendMessage('A');
      await b.controller.sendMessage('B');
      final bBubble = b.state.messages.firstWhere((m) => m.content == 'B');

      await b.controller.retryMessage(bBubble);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(repo.sentContents, ['A', 'B']);
    });
  });

  group('read-only terminal state (Spec 16: relationship ends while queued)', () {
    test('queued messages become failed with a plain explanation and no Retry', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      repo.sendErrorQueue.add(const SocketException('offline'));
      final b = await boot(repo);
      await b.controller.sendMessage('never sent');
      expect(b.state.messages.single.status, MessageStatus.queued);

      repo.conversationOverride = readOnlyConversation(relId);
      repo.emitRealtime();
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(b.state.conversation.canSend, isFalse);
      expect(b.state.messages.single.status, MessageStatus.failed);
      final row = (await b.outbox()).single;
      expect(row.state, PendingSendState.failedPermanent);
      expect(row.lastErrorCategory, 'relationshipInactive');
    });

    test('a queue restored into a read-only chat is failed on open, and can be removed', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final cache = ChatCacheService.forTesting(backend: memBackend());
      await cache.putOutbox(userId, pendingText('q', 'from last night',
          createdAt: DateTime.now().subtract(const Duration(hours: 9))));

      final b = await boot(repo, cache: cache, conversation: readOnlyConversation(relId));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(repo.sendCallCount, 0);
      expect(b.state.messages.single.status, MessageStatus.failed);
      await b.controller.removeFailedMessage(b.state.messages.single);
      expect(b.state.messages, isEmpty);
      expect(await b.outbox(), isEmpty);
    });
  });

  group('restart: the outbox decides (M-2)', () {
    test('a cached "sending" snapshot of a message the outbox knows failed restores as failed', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final createdAt = DateTime.now().subtract(const Duration(minutes: 3));
      final snapshot = Message.optimistic(
        id: '_local_f',
        clientMessageId: 'f',
        relationshipId: relId,
        senderId: userId,
        content: 'failed one',
        createdAt: createdAt,
      ).copyWith(status: MessageStatus.sending);
      final orphan = Message.optimistic(
        id: '_local_o',
        clientMessageId: 'o',
        relationshipId: relId,
        senderId: userId,
        content: 'orphan',
        createdAt: createdAt,
      );
      await cache.writeMessages(userId, relId, [snapshot, orphan]);
      await cache.putOutbox(userId, pendingText('f', 'failed one',
          createdAt: createdAt,
          attempts: 5,
          state: PendingSendState.failedPermanent));

      final b = await boot(repo, cache: cache);

      expect(b.state.messages.map((m) => m.content), ['failed one'],
          reason: 'the orphan has no outbox row: it was sent or removed');
      expect(b.state.messages.single.status, MessageStatus.failed);
    });
  });
}
```

- [ ] **Step 2: Run to verify failure for the right reason**

Run: `flutter test test/features/chat/chat_outbox_engine_test.dart`
Expected: compile errors `No named parameter with the name 'force'` and `The method 'debugSetConversation' isn't defined`. (With stubs for those two, the behavioural failures are: offline test → `Expected: MessageStatus.queued Actual: MessageStatus.failed` on attempt 5; head-timer test → `sendCallCount` 1 at 120 ms (B overtook A); 23505 test → the `sendMessage` future completes with `SocketException`; FIFO test → `sendCallCount` 2.)

- [ ] **Step 3: Implement the engine**

All edits in `lib/features/chat/presentation/state/chat_state.dart`, class `ChatController`.

(a) Fields — next to `Timer? _retryTimer;` add:

```dart
  /// The deadline [_retryTimer] is armed for, so a later failure never
  /// replaces an earlier deadline (that is how an item got stranded, #3).
  DateTime? _retryDeadline;
  bool _forceRequestedWhileBusy = false;
```

(b) Every direct send goes through the queue. In `sendMessage`, `sendVoiceMessage`, `sendStreakMessage`, `sendVideoMessage` and `sendEphemeralVideoMessage` replace the final `await _attemptSend(pending);` with `await _enqueueAndFlush(user.id, pending);` and add the helper:

```dart
  /// Every send enters the durable queue first and leaves through
  /// [flushOutbox], so a message typed while an earlier one is still waiting
  /// for the network goes out after it (Spec 4.2 enqueue order) instead of
  /// overtaking it and showing the two phones different orders (#5). The
  /// optimistic bubble is already on screen; this is the disk + network leg.
  Future<void> _enqueueAndFlush(String userId, PendingSend pending) async {
    try {
      await ref.read(chatCacheServiceProvider).putOutbox(userId, pending);
    } catch (error) {
      ChatLog.e('outbox write failed; sending without durability', error);
      await _attemptSend(pending);
      return;
    }
    await flushOutbox();
  }
```

`sendImageMessage` and `sendVideoMessageFromTrim` already `putOutbox` then `_prepareAndAttemptSend`; leave them (preparation is local work and runs outside the queue order by design — see Design 3). In `_prepareAndAttemptSend` keep `await _attemptSend(prepared);`.

(c) `retryMessage` — replace the final branch so a manual retry re-queues and flushes in order:

```dart
    final queued = pending.copyWith(
      state: PendingSendState.queued,
      nextAttemptAt: null,
      lastErrorCategory: null,
    );
    if (queued.requiresPreparation) {
      _updateOptimisticMessage(
        queued.clientMessageId,
        (entry) => entry.copyWith(
          status: MessageStatus.sending,
          isPreparing: queued.mediaType == 'video',
          compressProgress: queued.mediaType == 'video' ? 0 : null,
        ),
      );
      await _prepareAndAttemptSend(queued);
    } else {
      // Back into the queue, then the whole queue in order: a tap on the
      // second of two waiting messages must not send it before the first.
      await ref.read(chatCacheServiceProvider).putOutbox(user.id, queued);
      await flushOutbox(force: true);
    }
```

(d) Replace `flushOutbox` entirely:

```dart
  /// Sends what is waiting, oldest first (Spec 4.2).
  ///
  /// Stops at the first item that is not yet due or that just failed, so
  /// nothing behind it can overtake it; items whose media is still being
  /// prepared or is mid-upload are skipped (texts do not wait on an upload,
  /// as in WhatsApp — order among items *waiting for the network* is what
  /// the two phones compare). [force] ignores backoff deadlines: used by
  /// every "the network is back" trigger (resubscribe, connectivity,
  /// resume, manual retry). After every pass the retry timer is armed for
  /// the queue head, so no item can ever wait without a timer (#3).
  Future<void> flushOutbox({bool force = false}) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    if (!state.conversation.canSend) {
      // Spec 16: the queue stops, and the person is told (M-4).
      await _failQueuedForInactiveRelationship(user.id);
      return;
    }

    // Serialize flushing: init, the retry timer, realtime, connectivity and
    // manual retries can all call flushOutbox. One in-flight flush per
    // controller; a request made meanwhile runs once more afterwards.
    if (_isFlushing) {
      _flushRequestedWhileBusy = true;
      if (force) _forceRequestedWhileBusy = true;
      return;
    }
    _isFlushing = true;
    try {
      final queue = await ref
          .read(chatCacheServiceProvider)
          .readOutbox(user.id, relationshipId: relationshipId);
      final now = DateTime.now();

      for (final item in queue) {
        if (item.state == PendingSendState.failedPermanent) continue;
        // A concurrent single-message send or a preparation may already own
        // this item; it does not block the ones behind it.
        if (_inFlightClientIds.contains(item.clientMessageId) ||
            _preparingClientIds.contains(item.clientMessageId)) {
          continue;
        }
        final due = item.nextAttemptAt;
        if (!force && due != null && due.isAfter(now)) break;

        final bool acknowledged;
        if (item.requiresPreparation) {
          await _prepareAndAttemptSend(item);
          acknowledged = !(await _stillPending(user.id, item.clientMessageId));
        } else {
          acknowledged = await _attemptSend(item);
        }
        if (!acknowledged) {
          // A transient failure ends the pass: the next item must not go
          // out before this one, and the timer below brings the pass back.
          // A permanent failure steps aside — it will never send, so it
          // must not hold the queue.
          if (await _stillPending(user.id, item.clientMessageId)) break;
        }
      }
    } catch (error) {
      ChatLog.e(
        'outbox flush failed rel=${ChatLog.shortId(relationshipId)}',
        error,
      );
    } finally {
      _isFlushing = false;
      await _settleQueueAfterFlush(user.id);
      // If a flush was requested while we were busy, run once more so a newly
      // enqueued item isn't stranded until the next trigger.
      if (_flushRequestedWhileBusy) {
        final again = _forceRequestedWhileBusy;
        _flushRequestedWhileBusy = false;
        _forceRequestedWhileBusy = false;
        unawaited(flushOutbox(force: again));
      }
    }
  }

  Future<bool> _stillPending(String userId, String clientMessageId) async {
    final queue = await ref
        .read(chatCacheServiceProvider)
        .readOutbox(userId, relationshipId: relationshipId);
    return queue.any(
      (item) =>
          item.clientMessageId == clientMessageId &&
          item.state != PendingSendState.failedPermanent,
    );
  }

  /// Arms the retry timer for [due] unless an earlier deadline is already
  /// armed. The old code cancelled and re-armed for the latest failure only,
  /// which stranded an earlier item whose own deadline was further out.
  void _armRetryTimer(DateTime due) {
    if (!mounted) return;
    final current = _retryDeadline;
    if (_retryTimer?.isActive == true && current != null && !due.isBefore(current)) {
      return;
    }
    _retryTimer?.cancel();
    _retryDeadline = due;
    // Never re-arm for "now": a pass that could not attempt the head (an
    // exception before the send, a cache read that failed) must not spin.
    // The floor sits well under the smallest backoff window (1 s).
    const floor = Duration(milliseconds: 500);
    final delay = due.difference(DateTime.now());
    _retryTimer = Timer(delay < floor ? floor : delay, () {
      _retryDeadline = null;
      unawaited(flushOutbox());
    });
  }

  /// After a pass: arm the timer for the FIFO head and make every bubble
  /// that is still waiting say so.
  ///
  /// The head is the first item that is neither permanently failed nor in
  /// flight; nothing behind it can go before it, so its deadline is the
  /// queue's deadline. A waiting item with no deadline of its own (it was
  /// enqueued behind a blocked head) goes on the head's deadline, or on the
  /// next trigger. Its bubble flips from the optimistic "sending" to
  /// "queued" so the clock is honest while it waits.
  Future<void> _settleQueueAfterFlush(String userId) async {
    try {
      final queue = await ref
          .read(chatCacheServiceProvider)
          .readOutbox(userId, relationshipId: relationshipId);
      DateTime? headDue;
      final waiting = <String>{};
      for (final item in queue) {
        if (item.state == PendingSendState.failedPermanent) continue;
        if (_inFlightClientIds.contains(item.clientMessageId) ||
            _preparingClientIds.contains(item.clientMessageId)) {
          continue;
        }
        waiting.add(item.clientMessageId);
        final due = item.nextAttemptAt;
        if (headDue == null && due != null) headDue = due;
      }
      if (headDue != null) _armRetryTimer(headDue);
      if (!mounted || waiting.isEmpty) return;
      final needsFlip = state.messages.any(
        (m) =>
            waiting.contains(m.clientMessageId) &&
            m.id.startsWith('_local_') &&
            m.status == MessageStatus.sending,
      );
      if (!needsFlip) return;
      state = state.copyWith(
        error: state.error,
        messages:
            state.messages
                .map(
                  (m) =>
                      waiting.contains(m.clientMessageId) &&
                              m.id.startsWith('_local_') &&
                              m.status == MessageStatus.sending
                          ? m.copyWith(status: MessageStatus.queued)
                          : m,
                )
                .toList(),
      );
    } catch (error) {
      ChatLog.e('outbox settle failed', error);
    }
  }
```

(e) Replace `_attemptSend` entirely (the body up to the insert is unchanged; what changes is the return type, the catch structure and the reconcile):

```dart
  /// One attempt at delivering [pending]. Returns true when the server has
  /// the row (fresh insert or 23505 reconcile); false when the attempt
  /// failed and [_handleSendFailure] has recorded it. Never throws.
  Future<bool> _attemptSend(PendingSend pending) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return false;

    // Guard against the same logical message being sent twice concurrently
    // (e.g. a manual retry racing a flush). The DB unique constraint is the
    // hard backstop; this avoids the wasted attempt entirely.
    if (!_inFlightClientIds.add(pending.clientMessageId)) return false;

    var durablePending = pending;
    try {
      try {
        await ref
            .read(chatCacheServiceProvider)
            .putOutbox(
              user.id,
              pending.copyWith(state: PendingSendState.sending),
            );

        final repository = ref.read(chatRepositoryProvider);
        String? mediaKey = durablePending.uploadedMediaKey;
        String? mediaThumbnailKey = durablePending.uploadedThumbnailKey;
        // Every type that carries a file. A type missing here uploads
        // nothing, leaves mediaKey null, and its insert then fails
        // messages_payload_present with no content either — which is
        // exactly how streaks broke.
        final isMediaSend =
            (pending.mediaType == 'image' ||
                pending.mediaType == 'audio' ||
                pending.mediaType == 'video' ||
                pending.mediaType == 'streak') &&
            pending.localMediaPath != null &&
            pending.mediaMimeType != null;
        if (isMediaSend && mediaKey == null) {
          final intent = await repository.createMediaUploadIntent(
            relationshipId: pending.relationshipId,
            mimeType: pending.mediaMimeType!,
            mediaType: pending.mediaType!,
          );
          await repository.uploadChatMedia(
            intent: intent,
            localPath: pending.localMediaPath!,
            mimeType: pending.mediaMimeType!,
          );
          mediaKey = intent.storageKey;
          durablePending = durablePending.copyWith(uploadedMediaKey: mediaKey);
          // The expensive upload is now durable independently of the message
          // insert. If that later write or the process fails, recovery reuses
          // this key instead of creating an orphan and uploading again.
          await ref
              .read(chatCacheServiceProvider)
              .putOutbox(user.id, durablePending);
        }

        // Video-only: a second intent/upload for the thumbnail, through the
        // ordinary image path (media_type: 'image'). Non-fatal on its own
        // failure — a successfully-uploaded 25MB video must not be lost
        // over a missing 40KB poster (see design spec's error table). A
        // failure here is caught locally so it doesn't abort the whole
        // send via the outer try/catch.
        if (pending.mediaType == 'video' &&
            pending.localThumbnailPath != null &&
            pending.thumbnailMimeType != null &&
            mediaThumbnailKey == null) {
          try {
            final thumbIntent = await repository.createMediaUploadIntent(
              relationshipId: pending.relationshipId,
              mimeType: pending.thumbnailMimeType!,
              mediaType: 'image',
            );
            await repository.uploadChatMedia(
              intent: thumbIntent,
              localPath: pending.localThumbnailPath!,
              mimeType: pending.thumbnailMimeType!,
            );
            mediaThumbnailKey = thumbIntent.storageKey;
            durablePending = durablePending.copyWith(
              uploadedThumbnailKey: mediaThumbnailKey,
            );
            await ref
                .read(chatCacheServiceProvider)
                .putOutbox(user.id, durablePending);
            ChatLog.d(
              '[CHAT] video poster uploaded '
              'key=${ChatLog.shortId(thumbIntent.storageKey)}',
            );
          } catch (error) {
            // Non-fatal for the SEND, but fatal for the POSTER: with no
            // thumbnail key the row has nothing for the bubble to resolve,
            // so the video renders as a blank tile forever, on every device
            // and across every reinstall.
            //
            // Deliberately uses ChatLog.diagnostic rather than ChatLog.e:
            // this failure is a server-side rejection (feature flag, MIME
            // allowlist, RLS) whose *reason* is the entire diagnostic value,
            // and e() shapes it away to a length. Shipping it shaped is what
            // made this bug survive three rounds of client-side fixes.
            ChatLog.diagnostic('video thumbnail upload failed', error);
          }
        }
        final canonical = await repository.sendTextMessage(
          relationshipId: pending.relationshipId,
          senderId: pending.senderId,
          clientMessageId: pending.clientMessageId,
          content: pending.text,
          mediaKey: mediaKey,
          mediaType: pending.mediaType,
          mediaDurationMs: pending.mediaDurationMs,
          waveform: pending.waveform,
          mediaThumbnailKey: mediaThumbnailKey,
          mediaWidth: pending.mediaWidth,
          mediaHeight: pending.mediaHeight,
          isViewOnce: pending.isViewOnce,
          streakViewsRemaining: pending.streakViewsRemaining,
          replyToMessageId: pending.replyToMessageId,
          quotedText: pending.quotedText,
        );

        // A streak's clip row hangs off the message that just landed, using
        // the storage key already resolved for the upload. Additive: every
        // other media type skips this entirely.
        await _attachStreakClipIfNeeded(durablePending, canonical, mediaKey);

        await _acknowledge(user.id, durablePending, canonical);
        ChatLog.d(
          '[CHAT] send ok rel=${ChatLog.shortId(relationshipId)} '
          'cid=${ChatLog.shortId(pending.clientMessageId)}',
        );
        return true;
      } on PostgrestException catch (error) {
        if (error.code == '23505') {
          // Duplicate insert committed nothing (Spec 3.1): the row is
          // already on the server. The reconcile makes its own network
          // calls, so it owns its own failure handling (#4).
          return await _reconcileDuplicate(user.id, durablePending, error);
        }
        await _handleSendFailure(user.id, durablePending, ChatError.from(error));
        return false;
      } catch (error) {
        await _handleSendFailure(user.id, durablePending, ChatError.from(error));
        return false;
      }
    } catch (error) {
      // Last line of defence (a failure inside the failure handler itself):
      // nothing may leave a bubble on the clock with no retry armed.
      ChatLog.e(
        'send attempt escaped cid=${ChatLog.shortId(pending.clientMessageId)}',
        error,
      );
      await _parkForRetry(user.id, durablePending);
      return false;
    } finally {
      _inFlightClientIds.remove(pending.clientMessageId);
    }
  }

  /// The success path shared by a fresh insert and a 23505 reconcile:
  /// outbox row gone, optimistic bubble swapped for the canonical row,
  /// cache written, staged media promoted.
  Future<void> _acknowledge(
    String userId,
    PendingSend durablePending,
    Message canonical,
  ) async {
    await ref
        .read(chatCacheServiceProvider)
        .removeOutbox(
          userId,
          durablePending.relationshipId,
          durablePending.clientMessageId,
        );

    if (!mounted) return;
    // Acknowledge immediately while the canonical row still points at the
    // exact local bytes the optimistic row was painting. Cache promotion
    // and staging cleanup happen after this state transition, so neither
    // disk I/O nor a missing signed URL can produce a blank acknowledgement
    // frame or keep the busy overlay spinning after the server replied.
    final resolved = _canonicalWithLocalHandoff(durablePending, canonical);
    state = state.copyWith(
      isSending: false,
      error: null,
      messages: _replaceOptimistic(resolved),
    );
    // Persisted here, not only on the next sync. loadMessages and
    // refreshMessages were the only writers, so a just-sent message lived
    // in memory alone: popping the screen dropped it, the warm-cache
    // restore on return did not have it, and it reappeared seconds later
    // when the server fetch landed.
    final canonicalCacheWrite = ref
        .read(chatCacheServiceProvider)
        .writeMessages(userId, durablePending.relationshipId, state.messages);
    // Enqueue the canonical snapshot first, then promote local bytes. The
    // settlement pass persists its stable cache paths before deleting the
    // staging files, so a process restart cannot restore a dead path.
    unawaited(
      _settleAcknowledgedMedia(
        userId,
        durablePending,
        canonical,
        after: canonicalCacheWrite,
      ),
    );
  }

  /// Handles a 23505: fetch the canonical row and treat the violation as
  /// success-with-fetch. Every network call in here is its own failure
  /// domain — a throw inside a `catch` clause is not caught by sibling
  /// clauses, and that is exactly how a bubble froze at "sending" while the
  /// partner already had the message (#4). Returns true when acknowledged.
  Future<bool> _reconcileDuplicate(
    String userId,
    PendingSend durablePending,
    PostgrestException duplicate,
  ) async {
    final Message? canonical;
    try {
      canonical = await ref
          .read(chatRepositoryProvider)
          .findMessageByClientId(
            senderId: durablePending.senderId,
            clientMessageId: durablePending.clientMessageId,
          );
    } catch (error) {
      await _handleSendFailure(userId, durablePending, ChatError.from(error));
      return false;
    }
    if (canonical == null) {
      // The server says duplicate but will not show us the row (not yet
      // visible). Treat as transient; the next attempt reconciles.
      await _handleSendFailure(
        userId,
        durablePending,
        ChatError.from(duplicate),
      );
      return false;
    }
    try {
      await _attachStreakClipIfNeeded(
        durablePending,
        canonical,
        durablePending.uploadedMediaKey,
      );
    } catch (attachError) {
      // The message exists but its streak clip still does not. Keep the
      // outbox entry so the next retry can finish that second write.
      await _handleSendFailure(
        userId,
        durablePending,
        ChatError.from(attachError),
      );
      return false;
    }
    await _acknowledge(userId, durablePending, canonical);
    return true;
  }

  /// When even the failure handler failed (cache unavailable, for instance):
  /// the bubble goes back to the clock and a short timer brings the queue
  /// back, so the message is never stuck at "sending".
  Future<void> _parkForRetry(String userId, PendingSend pending) async {
    final due = DateTime.now().add(const Duration(seconds: 5));
    try {
      await ref
          .read(chatCacheServiceProvider)
          .putOutbox(
            userId,
            pending.copyWith(
              state: PendingSendState.queued,
              nextAttemptAt: due,
            ),
          );
    } catch (_) {
      // The in-memory bubble and the timer below still carry the retry.
    }
    if (!mounted) return;
    state = state.copyWith(
      isSending: false,
      messages:
          state.messages
              .map(
                (message) =>
                    message.clientMessageId == pending.clientMessageId
                        ? message.copyWith(status: MessageStatus.queued)
                        : message,
              )
              .toList(),
    );
    _armRetryTimer(due);
  }
```

(f) `_handleSendFailure` — replace the permanence rule, guard the cache write, arm (not replace) the timer, and map a 42501 against a read-only chat. The method becomes:

```dart
  Future<void> _handleSendFailure(
    String userId,
    PendingSend pending,
    ChatError failure,
  ) async {
    var error = failure;
    // An RLS insert denial while the relationship has gone read-only is a
    // pause/ending, not lost access: say so, and do not offer Retry.
    if (error.category == ChatErrorCategory.unauthenticated &&
        !state.conversation.canSend) {
      error = ChatError(
        ChatErrorCategory.relationshipInactive,
        correlationId: error.correlationId,
        cause: error.cause,
      );
    }
    final attempts = pending.attempts + 1;
    // Only a server-side failure of unknown shape can exhaust the automatic
    // attempts. A network-class failure (offline, unavailable, rate-limited)
    // never turns a message red on its own: it keeps the clock, at the
    // capped backoff, until the connection returns (#2).
    final countsTowardCap = error.category == ChatErrorCategory.unknown;
    final permanent =
        error.isPermanent ||
        (countsTowardCap && attempts >= _maxAutomaticSendAttempts);

    ChatLog.e(
      'send failed cat=${error.category.name} id=${error.correlationId} '
      'attempt=$attempts permanent=$permanent '
      'cid=${ChatLog.shortId(pending.clientMessageId)}',
      error.cause,
    );

    // ChatLog.e shapes the cause to a length so message bodies cannot leak,
    // which leaves an infrastructure failure — an RLS denial, a CHECK
    // violation, a disabled feature flag, a storage rejection — logged as
    // `<len=34>` and indistinguishable from any other error. The user sees
    // a banner and the console says nothing usable.
    //
    // These two carry no user text: PostgrestException and StorageException
    // describe the REQUEST (keys, constraints, policies), so they are safe
    // to print intact and are usually the entire diagnostic value.
    final cause = error.cause;
    if (cause is PostgrestException || cause is StorageException) {
      ChatLog.diagnostic(
        'send failed cid=${ChatLog.shortId(pending.clientMessageId)} '
        'media=${pending.mediaType ?? 'text'}',
        cause,
      );
    }

    // Bounded exponential backoff with equal jitter (Spec 4.2, 7.2): half the
    // window is fixed, half is randomized so many clients flushing after an
    // outage do not retry in lockstep. Window caps at 2^6 = 64s.
    final windowSeconds = 1 << attempts.clamp(1, 6);
    final backoffMillis =
        (windowSeconds * 500) + _backoffJitter.nextInt(windowSeconds * 500 + 1);

    final updatedPending = pending.copyWith(
      attempts: attempts,
      lastErrorCategory: error.queueCode,
      nextAttemptAt:
          permanent
              ? null
              : DateTime.now().add(Duration(milliseconds: backoffMillis)),
      state:
          permanent
              ? PendingSendState.failedPermanent
              : PendingSendState.queued,
    );

    try {
      await ref.read(chatCacheServiceProvider).putOutbox(userId, updatedPending);
    } catch (cacheError) {
      ChatLog.e('outbox write failed after a send failure', cacheError);
    }

    if (!permanent && updatedPending.nextAttemptAt != null) {
      _armRetryTimer(updatedPending.nextAttemptAt!);
    }

    if (!mounted) return;
    state = state.copyWith(
      isSending: false,
      error: error.toUserMessage(),
      messages:
          state.messages
              .map(
                (message) =>
                    message.clientMessageId == pending.clientMessageId
                        ? message.copyWith(
                          status:
                              permanent
                                  ? MessageStatus.failed
                                  : MessageStatus.queued,
                        )
                        : message,
              )
              .toList(),
    );
  }
```

(g) Read-only terminal state. Add:

```dart
  /// Spec 16 "relationship ends while queued": the queue stops and the
  /// person is told. The server insert policy requires status = 'active',
  /// so these rows can never send; left as they were they came back as
  /// clock bubbles on every restart with no way to remove them (M-4).
  Future<void> _failQueuedForInactiveRelationship(String userId) async {
    final List<PendingSend> queue;
    try {
      queue = await ref
          .read(chatCacheServiceProvider)
          .readOutbox(userId, relationshipId: relationshipId);
    } catch (_) {
      return;
    }
    final stuck =
        queue.where((p) => p.state != PendingSendState.failedPermanent).toList();
    if (stuck.isEmpty) return;
    for (final item in stuck) {
      try {
        await ref
            .read(chatCacheServiceProvider)
            .putOutbox(
              userId,
              item.copyWith(
                state: PendingSendState.failedPermanent,
                nextAttemptAt: null,
                lastErrorCategory: ChatErrorCategory.relationshipInactive.name,
              ),
            );
      } catch (error) {
        ChatLog.e('outbox write failed while closing the queue', error);
      }
    }
    _retryTimer?.cancel();
    _retryDeadline = null;
    if (!mounted) return;
    final ids = {for (final p in stuck) p.clientMessageId};
    state = state.copyWith(
      isSending: false,
      error:
          stuck.length == 1
              ? "Your unsent message can't be delivered — this chat is "
                  'read-only now. You can remove it.'
              : "Your ${stuck.length} unsent messages can't be delivered — "
                  'this chat is read-only now. You can remove them.',
      messages:
          state.messages
              .map(
                (message) =>
                    ids.contains(message.clientMessageId)
                        ? message.copyWith(
                          status: MessageStatus.failed,
                          isPreparing: false,
                        )
                        : message,
              )
              .toList(),
    );
  }
```

In `_refreshConversation`, after `state = state.copyWith(conversation: updated);` and before the archived check add:

```dart
    if (!updated.canSend &&
        updated.availability != ConversationAvailability.archived) {
      final user = ref.read(currentUserProvider);
      if (user != null) await _failQueuedForInactiveRelationship(user.id);
    }
```

(h) `_mergeInitialMessages` — replace:

```dart
  /// The outbox is authoritative for anything still local. A cached
  /// `_local_` row is a snapshot of a bubble at some earlier sync: it may say
  /// "sending" for a message the queue knows has failed (restored that way,
  /// it offered neither retry nor remove), or belong to a message the queue
  /// no longer has at all (sent, then superseded; or removed). A canonical
  /// cached row wins over a restored pending row with the same client id:
  /// the server already has it, and the stale outbox row reconciles through
  /// 23505 on the next flush.
  List<Message> _mergeInitialMessages(
    List<Message> cached,
    List<Message> restoredPending,
  ) {
    final byClientMessageId = <String, Message>{};
    for (final message in cached) {
      if (message.id.startsWith('_local_')) continue;
      byClientMessageId[message.clientMessageId] = message;
    }
    for (final message in restoredPending) {
      byClientMessageId.putIfAbsent(message.clientMessageId, () => message);
    }
    return byClientMessageId.values.toList()..sort(_bySortThenId);
  }
```

(i) Test seam and dispose. Next to `debugSetMessages` add:

```dart
  /// Test-only: the conversation as a refresh would set it, without a
  /// network round-trip (e.g. to race a send against a pause).
  @visibleForTesting
  void debugSetConversation(Conversation conversation) {
    state = state.copyWith(conversation: conversation);
  }
```

In `dispose()`, after `_retryTimer?.cancel();` add `_retryDeadline = null;`.

(j) `chat_screen.dart` — in the message-list builder the bubble's `onRetry:` argument reads `message.isFailed ? () => … retryMessage(message) : null`. Change the condition to `message.isFailed && state.conversation.canSend` (Retry on a read-only chat can only fail again; Remove stays).

- [ ] **Step 4: Run the new tests and the chat suite**

Run: `flutter test test/features/chat/chat_outbox_engine_test.dart`
Expected: `All tests passed!` (12 tests; the backoff test takes ~2.5 s).

Run: `flutter test test/features/chat`
Expected: `All tests passed!`. Known interactions: `chat_controller_test.dart` "transient failure keeps message queued" and "retry after a transient failure sends exactly one canonical row" still pass (`Exception('network down')` maps to `offline`, which is now never permanent — the same outcome they assert). `chat_edge_cases_test.dart` "Commit succeeds, response lost" still sees one row.

- [ ] **Step 5: Checkpoint**

Run: `flutter analyze lib/features/chat/presentation/state/chat_state.dart lib/features/chat/presentation/screens/chat_screen.dart test/features/chat/chat_outbox_engine_test.dart | grep -E '^\s*(error|warning) '`
Expected: no output. No commit (the owner commits).

---

### Task 6: Realtime handler as a coalesced, guarded batch; conversations list without resubscribe churn (#8, #9, resync flush for #1)

**Files:**
- Modify: `lib/features/chat/presentation/state/chat_state.dart` (`ConversationsNotifier` whole class; `ChatController._subscribeToRealtime`, new `_onRealtimeEvent`, `_processRealtimeBatch`, `_guard`, `_refreshConversationSafely`; `markAsRead`; `_attemptSend` success path's bump)
- Modify: `test/features/chat/chat_controller_test.dart` (one test's assertion), `test/features/chat/inbox_realtime_test.dart` (two waits)
- Test: `test/features/chat/chat_realtime_handler_test.dart`

**Interfaces:**
- Consumes: `ChatRealtimeEvent`/`ChatRealtimeKind` (Task 3), `refreshMessagesByIds`, `syncChangesSinceCursor` (Task 4), `flushOutbox({bool force})` (Task 5).
- Produces: `Future<void> ConversationsNotifier.refreshQuietly()`; `ChatController` no longer bumps `conversationsRefreshProvider` from the realtime handler, after a send, or after a read.

Design: one batch per debounce window. Order inside the batch is the order a person feels it — the new bubble first (`_catchUpFromCursor`), then rows that events named (`refreshMessagesByIds`), then on a resync the cursor sync and the authoritative first page, then header/pins/delivered, each inside `_guard` so one failure logs and the rest still runs. Frames that arrive while a batch runs are processed by exactly one follow-up batch. The handler no longer bumps `conversationsRefreshProvider`: that bump rebuilt `ConversationsNotifier`, whose `ref.onDispose` inside `_subscribeToInbox` ran on every rebuild and tore down/rejoined the inbox channel (one `subscribed` → one more list fetch) and re-ran this very controller's header refresh. The inbox stream already refreshes the list on every message; the one case with no event — a read while receipts are off — calls `refreshQuietly()`.

- [ ] **Step 1: Write the failing handler tests**

Create `test/features/chat/chat_realtime_handler_test.dart`:

```dart
import 'dart:async';

import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

class _Booted {
  _Booted(this.controller, this.container, this.conversation);
  final ChatController controller;
  final ProviderContainer container;
  final Conversation conversation;
  ChatState get state => container.read(chatControllerProvider(conversation));
}

Conversation _convo(String id, {int unread = 0}) => Conversation(
  id: id,
  relationshipId: id,
  partnerId: 'partner',
  name: 'Partner',
  updatedAt: DateTime.now(),
  relationshipStatus: 'active',
  availability: ConversationAvailability.active,
  unreadCount: unread,
);

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';

  Future<_Booted> boot(FakeChatRepository repo) async {
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    final convo = activeConversation(relId);
    repo.conversationOverride = convo;
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return _Booted(controller, container, convo);
  }

  void partnerSends(FakeChatRepository repo, String id, String content) {
    repo.seedIncoming(
      id: id,
      relationshipId: relId,
      senderId: 'partner',
      content: content,
      createdAt: DateTime.now(),
    );
  }

  group('per-chat handler', () {
    test('a new message renders even when the header refresh throws', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);
      repo.getConversationError = Exception('metadata unreachable');

      partnerSends(repo, 'inc-1', 'are you there?');
      repo.emitRealtime(
        const ChatRealtimeEvent(ChatRealtimeKind.messageInsert, messageId: 'inc-1'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(b.state.messages.map((m) => m.id), contains('inc-1'));
    });

    test('an insert frame costs one forward fetch and no header or list work', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      partnerSends(repo, 'inc-0', 'earlier');
      final b = await boot(repo);
      final conversationCalls = repo.getConversationCalls;
      final pageCalls = repo.getMessagesCalls;
      final forwardCalls = repo.getMessagesAfterCalls;
      final bumps = b.container.read(conversationsRefreshProvider);

      partnerSends(repo, 'inc-1', 'new');
      repo.emitRealtime(
        const ChatRealtimeEvent(ChatRealtimeKind.messageInsert, messageId: 'inc-1'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(b.state.messages.first.id, 'inc-1');
      expect(repo.getMessagesAfterCalls, forwardCalls + 1);
      expect(repo.getMessagesCalls, pageCalls, reason: 'no first-page refetch for an insert');
      expect(repo.getConversationCalls, conversationCalls, reason: 'no header refetch for an insert');
      expect(b.container.read(conversationsRefreshProvider), bumps,
          reason: 'the handler must not rebuild the conversations list');
    });

    test('frames inside one debounce window are processed as one batch', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      partnerSends(repo, 'inc-0', 'earlier');
      final b = await boot(repo);
      final forwardCalls = repo.getMessagesAfterCalls;

      for (var i = 1; i <= 5; i++) {
        partnerSends(repo, 'inc-$i', 'burst $i');
        repo.emitRealtime(
          ChatRealtimeEvent(ChatRealtimeKind.messageInsert, messageId: 'inc-$i'),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(b.state.messages.where((m) => m.content.startsWith('burst')), hasLength(5));
      expect(repo.getMessagesAfterCalls, forwardCalls + 1);
    });

    test('an update frame refreshes exactly the named row, wherever it is', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      partnerSends(repo, 'inc-1', 'original');
      final b = await boot(repo);

      await repo.editMessage(messageId: 'inc-1', newContent: 'edited');
      repo.emitRealtime(
        const ChatRealtimeEvent(ChatRealtimeKind.messageUpdate, messageId: 'inc-1'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(b.state.messages.single.content, 'edited');
      expect(repo.getMessagesByIdsCalls, 1);
    });

    test('a reaction frame (add or remove) refreshes the message it names (#8)', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      partnerSends(repo, 'inc-1', 'react to me');
      final b = await boot(repo);

      await repo.addReaction(relationshipId: relId, messageId: 'inc-1', emoji: '❤️');
      repo.emitRealtime(
        const ChatRealtimeEvent(ChatRealtimeKind.reaction, messageId: 'inc-1'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(b.state.messages.single.reactions['❤️'], contains(userId));

      await repo.removeReaction('inc-1');
      repo.emitRealtime(
        const ChatRealtimeEvent(ChatRealtimeKind.reaction, messageId: 'inc-1'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(b.state.messages.single.reactions, isEmpty);
    });

    test('a pin frame refreshes the pinned banner (#8 unpin arrives live)', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      partnerSends(repo, 'inc-1', 'pin me');
      final b = await boot(repo);
      repo.pinnedMessageIds.add('inc-1');
      repo.emitRealtime(const ChatRealtimeEvent(ChatRealtimeKind.pin, messageId: 'inc-1'));
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(b.state.pinnedMessages.map((m) => m.id), ['inc-1']);

      repo.pinnedMessageIds.remove('inc-1');
      repo.emitRealtime(const ChatRealtimeEvent(ChatRealtimeKind.pin, messageId: 'inc-1'));
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(b.state.pinnedMessages, isEmpty);
    });

    test('a resync frame refreshes page, header and pins, and flushes the outbox (#1)', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      partnerSends(repo, 'inc-0', 'earlier');
      final b = await boot(repo);
      repo.sendErrorQueue.add(Exception('network down'));
      await b.controller.sendMessage('typed offline');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        b.state.messages.firstWhere((m) => m.content == 'typed offline').status.name,
        'queued',
      );
      final conversationCalls = repo.getConversationCalls;
      final pageCalls = repo.getMessagesCalls;
      final pinCalls = repo.getPinnedCalls;

      repo.emitRealtime();
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(repo.getConversationCalls, conversationCalls + 1);
      expect(repo.getMessagesCalls, pageCalls + 1);
      expect(repo.getPinnedCalls, pinCalls + 1);
      expect(
        b.state.messages.firstWhere((m) => m.content == 'typed offline').status.name,
        'sent',
        reason: 'a (re)subscribe is the moment the network is back',
      );
    });

    test('one failing step does not skip the others', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);
      repo.getPinnedError = Exception('pins down');
      partnerSends(repo, 'inc-1', 'undelivered');
      final deliveredBefore = repo.markDeliveredCalls.length;

      repo.emitRealtime();
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(b.state.messages.map((m) => m.id), contains('inc-1'));
      expect(repo.markDeliveredCalls.length, greaterThan(deliveredBefore));
    });

    test('frames that arrive mid-batch are processed by exactly one follow-up batch', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      partnerSends(repo, 'inc-0', 'earlier');
      final b = await boot(repo);
      final forwardCalls = repo.getMessagesAfterCalls;

      // Hold the resync batch at its first-page step so frames can land
      // while it is genuinely running.
      final gate = Completer<void>();
      repo.getMessagesGate = gate;
      repo.emitRealtime();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(repo.getMessagesAfterCalls, forwardCalls + 1, reason: 'the batch is running');

      for (var i = 1; i <= 3; i++) {
        partnerSends(repo, 'inc-$i', 'late $i');
        repo.emitRealtime(
          ChatRealtimeEvent(ChatRealtimeKind.messageInsert, messageId: 'inc-$i'),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(repo.getMessagesAfterCalls, forwardCalls + 1,
          reason: 'nothing may run concurrently with the open batch');

      repo.getMessagesGate = null;
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(b.state.messages.where((m) => m.content.startsWith('late')), hasLength(3));
      expect(repo.getMessagesAfterCalls, forwardCalls + 2,
          reason: 'one follow-up batch for the three frames, not three');
    });
  });

  group('conversations list', () {
    test('bumping conversationsRefreshProvider rebuilds the list without resubscribing the inbox', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      repo.conversations = [_convo('rel-1')];
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      await container.read(conversationsProvider.future);
      final subscriptions = repo.inboxSubscriptions.length;

      for (var i = 0; i < 3; i++) {
        container.read(conversationsRefreshProvider.notifier).state++;
        await container.read(conversationsProvider.future);
      }

      expect(repo.inboxSubscriptions.length, subscriptions,
          reason: 'each rebuild used to tear down and rejoin the inbox channel');
    });

    test('a burst of inbox events is one refetch', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      repo.conversations = [_convo('rel-1')];
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      await container.read(conversationsProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final calls = repo.getConversationsCalls;

      repo.conversations = [_convo('rel-1', unread: 5)];
      for (var i = 0; i < 5; i++) {
        repo.inboxEvents.add(null);
      }
      await Future<void>.delayed(const Duration(milliseconds: 450));

      expect(repo.getConversationsCalls, calls + 1);
      expect(container.read(conversationsProvider).value?.single.unreadCount, 5);
    });

    test('refreshQuietly refetches in place without a loading state', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      repo.conversations = [_convo('rel-1', unread: 2)];
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      await container.read(conversationsProvider.future);
      final states = <bool>[];
      container.listen(conversationsProvider, (_, next) => states.add(next.isLoading));

      repo.conversations = [_convo('rel-1', unread: 0)];
      await container.read(conversationsProvider.notifier).refreshQuietly();

      expect(states.contains(true), isFalse);
      expect(container.read(conversationsProvider).value?.single.unreadCount, 0);
    });
  });
}
```

- [ ] **Step 2: Run to verify failure for the right reason**

Run: `flutter test test/features/chat/chat_realtime_handler_test.dart`
Expected: compile error `The method 'refreshQuietly' isn't defined for the type 'ConversationsNotifier'`. (After adding only that method as a stub, the behavioural tests fail on counts: e.g. "an insert frame costs…" fails with `Expected: <N> Actual: <N+1>` for `getConversationCalls`, and "bumping … without resubscribing" fails with `inboxSubscriptions.length` 4 instead of 1.)

- [ ] **Step 3: Rewrite `ConversationsNotifier`**

Replace the whole `ConversationsNotifier` class in `chat_state.dart` with:

```dart
class ConversationsNotifier extends AsyncNotifier<List<Conversation>> {
  static bool _servedCache = false;

  /// Realtime refreshes landing inside this window are one refetch. A
  /// message and its receipt/worker UPDATE frames arrive within tens of
  /// milliseconds of each other; each used to be a full list fetch.
  static const _refreshCoalesce = Duration(milliseconds: 300);

  StreamSubscription<void>? _inboxSubscription;
  List<String>? _subscribedIds;
  String? _subscribedUserId;
  Timer? _refreshDebounce;
  bool _refreshInFlight = false;
  bool _refreshAgain = false;

  /// ref.onDispose fires on every rebuild AND on real disposal, and the
  /// notifier object survives rebuilds — which is why the subscription must
  /// not be torn down in onDispose. This flag tells the two apart after the
  /// fact: a rebuild sets it true again at the top of build(); a disposal
  /// leaves it false, so a late inbox frame or debounce tick drops the
  /// subscription instead of writing state into a dead notifier.
  bool _isBuilt = false;

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Reports delivery for conversations the device now holds.
  ///
  /// The notification worker used to stamp delivered_at when it QUEUED a
  /// push, which claimed delivery for a phone that might be switched off.
  /// The honest signal is this: the recipient's own device has the rows.
  ///
  /// Driven off unreadCount because that is what the list already knows --
  /// an unread partner message the device is holding is exactly a message
  /// that has been delivered but not read.
  void _markDeliveredForFetched(
    ChatRepository repository,
    List<Conversation> conversations,
  ) {
    for (final conversation in conversations) {
      if (conversation.unreadCount > 0) {
        unawaited(
          repository.markRelationshipDelivered(conversation.relationshipId),
        );
      }
    }
  }

  @override
  Future<List<Conversation>> build() async {
    _isBuilt = true;
    ref.onDispose(() {
      _isBuilt = false;
      _refreshDebounce?.cancel();
    });
    ref.watch(conversationsRefreshProvider);
    final repository = ref.watch(chatRepositoryProvider);
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      _dropInbox();
      return const [];
    }
    // The inbox subscription outlives rebuilds on purpose: a bump of
    // conversationsRefreshProvider (identity edit, pull-to-refresh) must not
    // tear down and rejoin the websocket channel. It is dropped only when the
    // signed-in user changes.
    if (_subscribedUserId != null && _subscribedUserId != user.id) {
      _dropInbox();
    }

    final cache = ref.read(chatCacheServiceProvider);

    if (!_servedCache) {
      _servedCache = true;
      final cached = await cache.readConversations(user.id);
      if (cached.isNotEmpty) {
        // Subscribed from the CACHED ids too: this path returns before the
        // network fetch, and without this a cold start that painted from
        // cache would leave the list unsubscribed until the next rebuild.
        _subscribeToInbox(repository, cache, user.id, cached);
        unawaited(_refreshInBackground(repository, cache, user.id));
        return cached;
      }
    }

    try {
      final conversations = await repository.getConversations();
      unawaited(cache.writeConversations(user.id, conversations));
      _subscribeToInbox(repository, cache, user.id, conversations);
      _markDeliveredForFetched(repository, conversations);
      return conversations;
    } catch (_) {
      return await cache.readConversations(user.id);
    }
  }

  void _dropInbox() {
    _inboxSubscription?.cancel();
    _inboxSubscription = null;
    _subscribedIds = null;
    _subscribedUserId = null;
    _refreshDebounce?.cancel();
  }

  /// Keeps the conversation list live.
  ///
  /// The list was fetched once at build and never again: a message
  /// arriving while the user sat on the conversations screen changed
  /// neither the preview nor the unread badge until they pulled to
  /// refresh or restarted the app. The chat screen had its own
  /// subscription; the list had none.
  ///
  /// Refreshes in place rather than invalidating: invalidate() would
  /// rebuild through AsyncLoading and flash the list away under the user
  /// for something as ordinary as a message arriving.
  void _subscribeToInbox(
    ChatRepository repository,
    ChatCacheService cache,
    String userId,
    List<Conversation> conversations,
  ) {
    final ids = conversations.map((c) => c.relationshipId).toList()..sort();
    if (ids.isEmpty) return;

    // Re-subscribed only when the SET of relationships changes. Without
    // this the subscription would tear itself down and rebuild on every
    // event it delivered -- each refresh calls back into here -- churning
    // a websocket channel for every message that arrives.
    if (_subscribedUserId == userId &&
        _subscribedIds != null &&
        _listEquals(_subscribedIds!, ids)) {
      return;
    }

    _inboxSubscription?.cancel();
    _subscribedIds = ids;
    _subscribedUserId = userId;

    _inboxSubscription = repository
        .watchInboxEvents(ids)
        .listen((_) => _scheduleRefresh(repository, cache, userId));
  }

  void _scheduleRefresh(
    ChatRepository repository,
    ChatCacheService cache,
    String userId,
  ) {
    if (!_isBuilt) {
      // The provider was disposed for good (container gone): let the
      // subscription go now rather than on a user change that never comes.
      _dropInbox();
      return;
    }
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(_refreshCoalesce, () {
      unawaited(_refreshInBackground(repository, cache, userId));
    });
  }

  /// Refetches the list in place: no AsyncLoading flash, no rebuild, no
  /// inbox resubscribe. The chat controller calls this after a read while
  /// receipts are off -- the one change that fires no messages event
  /// (Spec 1a) -- instead of bumping conversationsRefreshProvider.
  Future<void> refreshQuietly() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    await _refreshInBackground(
      ref.read(chatRepositoryProvider),
      ref.read(chatCacheServiceProvider),
      user.id,
    );
  }

  /// Fetches behind an already-painted cached list. Never surfaces an
  /// AsyncLoading (that would flash the cache away) and swallows failure —
  /// the user keeps reading the cached list until a later refresh succeeds.
  /// Serialized: a refresh requested while one runs re-runs once after it.
  Future<void> _refreshInBackground(
    ChatRepository repository,
    ChatCacheService cache,
    String userId,
  ) async {
    if (!_isBuilt) return;
    if (_refreshInFlight) {
      _refreshAgain = true;
      return;
    }
    _refreshInFlight = true;
    try {
      final conversations = await repository.getConversations();
      if (!_isBuilt) return;
      state = AsyncData(conversations);
      unawaited(cache.writeConversations(userId, conversations));
      _markDeliveredForFetched(repository, conversations);
      // A new relationship (or a first fetch behind the cache) means new
      // ids to filter on, and the subscription is per relationship.
      _subscribeToInbox(repository, cache, userId, conversations);
    } catch (error) {
      ChatLog.e('conversations background refresh failed', error);
    } finally {
      _refreshInFlight = false;
      if (_refreshAgain) {
        _refreshAgain = false;
        unawaited(_refreshInBackground(repository, cache, userId));
      }
    }
  }
}
```

- [ ] **Step 4: Rebuild the per-chat handler**

In `ChatController`, add these fields next to `_refreshDebounce`:

```dart
  // Realtime frames are coalesced: everything inside one debounce window is
  // one batch, run new-rows-first with every metadata step guarded (#9).
  bool _pendingResync = false;
  bool _pendingRelationship = false;
  bool _pendingPins = false;
  final Set<String> _touchedMessageIds = <String>{};
  bool _batchInFlight = false;
  bool _batchRequested = false;
```

Replace `_subscribeToRealtime` with:

```dart
  void _subscribeToRealtime() {
    final repository = ref.read(chatRepositoryProvider);
    ChatLog.d(
      '[CHAT] realtime subscribe rel=${ChatLog.shortId(relationshipId)}',
    );
    _realtimeSubscription = repository
        .watchConversationEvents(relationshipId)
        .listen(_onRealtimeEvent);
  }

  void _onRealtimeEvent(ChatRealtimeEvent event) {
    switch (event.kind) {
      case ChatRealtimeKind.resync:
        _pendingResync = true;
      case ChatRealtimeKind.relationship:
        _pendingRelationship = true;
      case ChatRealtimeKind.pin:
        _pendingPins = true;
      case ChatRealtimeKind.messageInsert:
        // The forward catch-up restores inserts by cursor; nothing to remember.
        break;
      case ChatRealtimeKind.messageUpdate:
      case ChatRealtimeKind.messageDelete:
      case ChatRealtimeKind.reaction:
        final id = event.messageId;
        if (id == null) {
          _pendingResync = true;
        } else {
          _touchedMessageIds.add(id);
        }
    }
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(
      ref.read(chatConfigProvider).realtimeRefreshDebounce,
      () => unawaited(_processRealtimeBatch()),
    );
  }

  /// One pass over everything the last debounce window announced, in the
  /// order a person feels it: the new bubble first, then the rows events
  /// named, then (after a reconnect) the cursor sync and the authoritative
  /// first page, then header, pins and delivery marks — each guarded so a
  /// failure in one cannot drop the rest. Frames that land while this runs
  /// get exactly one follow-up pass.
  Future<void> _processRealtimeBatch() async {
    if (_batchInFlight) {
      _batchRequested = true;
      return;
    }
    _batchInFlight = true;
    try {
      final resync = _pendingResync;
      final relationship = _pendingRelationship;
      final pins = _pendingPins;
      final touched = Set<String>.of(_touchedMessageIds);
      _pendingResync = false;
      _pendingRelationship = false;
      _pendingPins = false;
      _touchedMessageIds.clear();

      await _guard('catch-up', _catchUpFromCursor);
      if (touched.isNotEmpty) {
        await _guard('touched rows', () => refreshMessagesByIds(touched));
      }
      if (resync) {
        await _guard('changes since cursor', syncChangesSinceCursor);
        await _guard('first page', () => loadMessages(silent: true));
      }
      if (resync || relationship) {
        await _guard('conversation', _refreshConversation);
      }
      if (resync || pins) {
        await _guard('pins', _refreshPinnedMessages);
      }
      await _guard('delivered', _markPartnerMessagesDelivered);
      // If the user is actively viewing this conversation, newly arrived
      // partner messages are seen immediately (Spec 6.4).
      if (_isViewActive) markAsReadDebounced();
      // A successful (re)subscribe is the best "the network is back" signal
      // there is: send what waited (#1).
      if (resync) unawaited(flushOutbox(force: true));
    } finally {
      _batchInFlight = false;
      if (_batchRequested) {
        _batchRequested = false;
        unawaited(_processRealtimeBatch());
      }
    }
  }

  Future<void> _guard(String step, Future<void> Function() run) async {
    try {
      await run();
    } catch (error) {
      if (!mounted) return;
      ChatLog.e(
        'realtime $step failed rel=${ChatLog.shortId(relationshipId)}',
        error,
      );
    }
  }
```

Remove the `conversationsRefreshProvider` bump from `_attemptSend`'s success path (the line `ref.read(conversationsRefreshProvider.notifier).state++;` after the `send ok` log — the inbox channel delivers the sender's own INSERT and refreshes the list). In `markAsRead`, replace `ref.read(conversationsRefreshProvider.notifier).state++;` and its comment with:

```dart
      // While receipts are off the read changes no messages row, so no
      // realtime event refreshes the conversations list; refresh it in place
      // (no rebuild, no inbox resubscribe) or the unread badge stays stale
      // (Spec 1a).
      unawaited(ref.read(conversationsProvider.notifier).refreshQuietly());
```

Keep the constructor's `ref.listen(conversationsRefreshProvider, …)` (identity edits still arrive that way) and the pull-to-refresh bump in `conversations_screen.dart`.

- [ ] **Step 5: Update the two old tests that encoded the bump and the un-debounced refresh**

In `test/features/chat/chat_controller_test.dart`, the test `'a read refreshes the conversations list, so the unread badge clears even when receipts are off and no messages event fires (Spec 1a)'` asserted the counter bump. The behaviour it protects (the list refetches after a read) is now delivered by `refreshQuietly()`. Replace its body with:

```dart
      final repo = FakeChatRepository(currentUserId: userId);
      repo.seedIncoming(
        id: 'inc-1',
        relationshipId: relId,
        senderId: 'partner',
        content: 'hi from partner',
        createdAt: DateTime.now(),
      );
      final b = await boot(repo);
      await b.container.read(conversationsProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final before = repo.getConversationsCalls;

      b.controller.setViewActive(true);
      await Future<void>.delayed(const Duration(milliseconds: 550));
      expect(repo.markReadCalls, hasLength(1));
      expect(repo.getConversationsCalls, greaterThan(before));

      // Nothing new to mark: no call, no extra list refresh.
      final after = repo.getConversationsCalls;
      await b.controller.markAsRead();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(repo.getConversationsCalls, after);
```

In `test/features/chat/inbox_realtime_test.dart`, the tests `'an inbox event refreshes the unread count in place'` and `'a refresh does not flash the list away'` wait 20 ms after `repo.inboxEvents.add(null)`; refreshes are now coalesced over 300 ms, so change both waits to `const Duration(milliseconds: 400)`. The test `'the subscription is not rebuilt on every event'` stays as is.

- [ ] **Step 6: Run the new tests, the two updated files and the whole chat suite**

Run: `flutter test test/features/chat/chat_realtime_handler_test.dart test/features/chat/chat_controller_test.dart test/features/chat/inbox_realtime_test.dart`
Expected: `All tests passed!`.

Run: `flutter test test/features/chat`
Expected: `All tests passed!`. `reconnect_cascade_test.dart`, `receive_sound_test.dart`, `receive_haptic_test.dart`, `first_of_day_shimmer_test.dart`, `chat_instant_feel_test.dart` use `emitRealtime()` (resync) and still see a first-page refresh.

- [ ] **Step 7: Checkpoint**

Run: `flutter analyze lib/features/chat/presentation/state/chat_state.dart test/features/chat/chat_realtime_handler_test.dart test/features/chat/chat_controller_test.dart test/features/chat/inbox_realtime_test.dart | grep -E '^\s*(error|warning) '`
Expected: no output. No commit (the owner commits).

---

### Task 7: Flush triggers — open-time recovery, connectivity regained, app resume, and a drainer for closed chats (#1)

**Files:**
- Modify: `lib/features/chat/presentation/state/chat_state.dart` (`ChatController` constructor, `_init`; new `_refreshConversationSafely`, `_onConnectivityRegained`, `onAppResumed`)
- Create: `lib/features/chat/presentation/state/chat_outbox_drainer.dart`
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (`didChangeAppLifecycleState`)
- Modify: `lib/app/app.dart` (`_AppState.initState`)
- Test: `test/features/chat/chat_outbox_triggers_test.dart`

**Interfaces:**
- Consumes: `flushOutbox({force})` (Task 5), `_onRealtimeEvent`/`ChatRealtimeEvent.resync()` (Tasks 3, 6), `ChatRepository.ensureRealtimeConnected` (Task 3), `chatConnectivityProvider` (`StreamProvider<bool>`, `chat_experience_providers.dart`), `buildChatContainer(connectivity:)` (Task 3).
- Produces: `void ChatController.onAppResumed()`; `chatOutboxDrainerProvider` (`Provider<ChatOutboxDrainer>`) with `Future<void> ChatOutboxDrainer.drain()`.

Design: the outbox had one trigger (`_init`) and it died offline before reaching the flush. Now: (1) `_init` cannot abort before the flush — cache reads and the header refresh are best-effort; (2) a (re)subscribe flushes (Task 6); (3) the device reporting connectivity back nudges the socket and runs a resync batch (catch-up, changes-since, first page, flush with `force`) without waiting ~25–45 s for the heartbeat; (4) app resume does the same from the screen; (5) with no chat open, `ChatOutboxDrainer` wakes each relationship that has queued rows on resume/connectivity, flushes it, and lets its controller fall back onto the normal keep-alive eviction.

- [ ] **Step 1: Write the failing tests**

Create `test/features/chat/chat_outbox_triggers_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart';
import 'package:attune/features/chat/presentation/state/chat_outbox_drainer.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

class _Booted {
  _Booted(this.controller, this.container, this.conversation, this.cache);
  final ChatController controller;
  final ProviderContainer container;
  final Conversation conversation;
  final ChatCacheService cache;
  ChatState get state => container.read(chatControllerProvider(conversation));
  Future<List<PendingSend>> outbox() =>
      cache.readOutbox('user-a', relationshipId: 'rel-1');
}

void main() {
  // The drainer listens to app lifecycle, which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'user-a';
  const relId = 'rel-1';

  PendingSend queuedText(String id, String text, {String relationshipId = relId}) =>
      PendingSend(
        clientMessageId: id,
        relationshipId: relationshipId,
        senderId: userId,
        text: text,
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

  Future<_Booted> boot(
    FakeChatRepository repo, {
    ChatCacheService? cache,
    Stream<bool>? connectivity,
  }) async {
    final effectiveCache =
        cache ?? ChatCacheService.forTesting(backend: memBackend());
    final container = buildChatContainer(
      repository: repo,
      userId: userId,
      cache: effectiveCache,
      connectivity: connectivity,
    );
    addTearDown(container.dispose);
    final convo = activeConversation(relId);
    repo.conversationOverride = convo;
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return _Booted(controller, container, convo, effectiveCache);
  }

  test('opening a chat offline still restores and attempts the previous session\'s queue, '
      'and the first resubscribe sends it (#1)', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final cache = ChatCacheService.forTesting(backend: memBackend());
    await cache.putOutbox(userId, queuedText('q1', 'typed in the tunnel'));
    repo.getConversationError = const SocketException('offline');
    repo.sendErrorQueue.add(const SocketException('offline'));

    final b = await boot(repo, cache: cache);

    expect(b.state.messages.single.status, MessageStatus.queued);
    expect(repo.sendCallCount, 1,
        reason: 'the open-time flush must run although the header refresh threw');
    expect(b.state.isLoading, isFalse);

    repo.getConversationError = null;
    repo.emitRealtime(); // the channel (re)subscribed: the network is back
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(b.state.messages.single.status, MessageStatus.sent);
    expect(await b.outbox(), isEmpty);
  });

  test('connectivity coming back nudges the socket, resyncs and flushes at once', () async {
    final connectivity = StreamController<bool>.broadcast();
    addTearDown(connectivity.close);
    final repo = FakeChatRepository(currentUserId: userId);
    repo.sendErrorQueue.add(const SocketException('offline'));
    final b = await boot(repo, connectivity: connectivity.stream);

    await b.controller.sendMessage('waiting');
    expect(b.state.messages.single.status, MessageStatus.queued);
    repo.seedIncoming(
      id: 'inc-1',
      relationshipId: relId,
      senderId: 'partner',
      content: 'sent while you were out of range',
      createdAt: DateTime.now(),
    );

    connectivity.add(false);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    connectivity.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(repo.ensureRealtimeConnectedCalls, 1);
    expect(b.state.messages.map((m) => m.id), contains('inc-1'));
    expect(
      b.state.messages.firstWhere((m) => m.content == 'waiting').status,
      MessageStatus.sent,
    );
  });

  test('coming back to the foreground flushes and resyncs', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    repo.sendErrorQueue.add(const SocketException('offline'));
    final b = await boot(repo);
    await b.controller.sendMessage('waiting');
    expect(b.state.messages.single.status, MessageStatus.queued);

    b.controller.onAppResumed();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(b.state.messages.single.status, MessageStatus.sent);
  });

  group('drainer (chat not open)', () {
    test('sends queued messages for a relationship whose chat is closed', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      repo.conversations = [activeConversation(relId)];
      repo.conversationOverride = activeConversation(relId);
      final cache = ChatCacheService.forTesting(backend: memBackend());
      await cache.putOutbox(userId, queuedText('q1', 'from the car'));
      await cache.putOutbox(userId, queuedText('q2', 'and this one'));
      final container = buildChatContainer(
        repository: repo,
        userId: userId,
        cache: cache,
      );
      addTearDown(container.dispose);

      await container.read(chatOutboxDrainerProvider).drain();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(repo.sentContents, ['from the car', 'and this one']);
      expect(await cache.readOutbox(userId), isEmpty);
    });

    test('is a no-op when signed out or when the relationship is gone', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final cache = ChatCacheService.forTesting(backend: memBackend());
      await cache.putOutbox(userId, queuedText('q1', 'orphaned', relationshipId: 'rel-gone'));

      // Signed out.
      final signedOut = ProviderContainer(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          chatCacheServiceProvider.overrideWithValue(cache),
          currentUserProvider.overrideWithValue(null),
          chatConnectivityProvider.overrideWith((ref) => Stream<bool>.value(true)),
        ],
      );
      addTearDown(signedOut.dispose);
      await signedOut.read(chatOutboxDrainerProvider).drain();
      expect(repo.sendCallCount, 0);

      // Signed in, but the queued relationship is not in the list.
      repo.conversations = [activeConversation(relId)];
      final container = buildChatContainer(
        repository: repo,
        userId: userId,
        cache: cache,
      );
      addTearDown(container.dispose);
      await container.read(chatOutboxDrainerProvider).drain();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(repo.sendCallCount, 0);
    });
  });
}
```

- [ ] **Step 2: Run to verify failure for the right reason**

Run: `flutter test test/features/chat/chat_outbox_triggers_test.dart`
Expected: compile errors `Target of URI doesn't exist: '.../chat_outbox_drainer.dart'` and `The method 'onAppResumed' isn't defined`. (With stubs: the first test fails at `expect(repo.sendCallCount, 1)` with `Actual: <0>` — `_init` died on the header refresh before the flush; the connectivity test fails at `ensureRealtimeConnectedCalls` `Actual: <0>`.)

- [ ] **Step 3: Make `_init` unable to abort before the flush, and add the triggers**

In `ChatController`:

(a) Replace `_init` with:

```dart
  Future<void> _init() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    // Local reads are best-effort: a cache that cannot be read is a cold
    // start, never a chat that stays on a spinner (#12).
    var cached = const <Message>[];
    var restoredPending = const <Message>[];
    try {
      cached = await ref
          .read(chatCacheServiceProvider)
          .readMessages(user.id, relationshipId);
      if (!mounted) return;
      restoredPending = await _restorePendingMessages(user.id);
    } catch (error) {
      ChatLog.e('chat cache read failed; starting cold', error);
    }
    if (!mounted) return;
    final restoredMessages = _mergeInitialMessages(cached, restoredPending);
    final hasWarmCache = restoredMessages.isNotEmpty;
    if (hasWarmCache && mounted) {
      // Publish the local snapshot before optional poster work. Persisted
      // dimensions reserve each tile's geometry, so hydration cannot shift
      // the message list after first paint.
      state = state.copyWith(isLoading: false, messages: restoredMessages);
      unawaited(_discoverAndPrewarmPosters(restoredMessages));
    }

    // Subscribe before fetching to close the query-to-subscribe race. Header
    // metadata and messages are independent reads, so a slow avatar/name
    // refresh must not hold a cold message list blank — and an offline one
    // must not stop anything below from running (#1).
    _subscribeToRealtime();
    final conversationRefresh = _refreshConversationSafely();
    // With a warm cache the user already sees their history, so refresh
    // silently — no loading spinner and no "Syncing" banner flash. Only a
    // cold open (empty cache) shows the initial loading state.
    await loadMessages(silent: hasWarmCache);
    await conversationRefresh;
    if (!mounted) return;
    // Seed the baseline after the first load so initial history (warm cache
    // or cold fetch) never triggers the receive haptic; only messages that
    // arrive after this point can be "new" (Task 10).
    _lastPartnerMessageId =
        state.messages
            .where((m) => !m.isMine && !m.id.startsWith('_local_'))
            .fold<Message?>(
              null,
              (best, m) =>
                  best == null || m.createdAt.isAfter(best.createdAt)
                      ? m
                      : best,
            )
            ?.id;
    _hasSeededPartnerBaseline = true;
    await _refreshPinnedMessages();
    if (!mounted) return;
    await _refreshStarredMessageIds();
    if (!mounted) return;
    await _guard('delivered', _markPartnerMessagesDelivered);
    if (!mounted) return;
    // Read is only recorded once the screen reports the conversation is
    // visible and foregrounded (Spec 6.4); do not mark read here.
    // The open-time flush: whatever the last session left queued goes now
    // (or, offline, gets its timer and waits for the next trigger).
    unawaited(flushOutbox());
  }

  /// [_refreshConversation] for callers that must keep going when the
  /// header read fails (open, resume, reconnect). Returns normally after
  /// logging; the next trigger retries.
  Future<void> _refreshConversationSafely() async {
    try {
      await _refreshConversation();
    } catch (error) {
      if (!mounted) return;
      ChatLog.e(
        'conversation refresh failed rel=${ChatLog.shortId(relationshipId)}',
        error,
      );
    }
  }
```

(b) In the constructor, after the `conversationsRefreshProvider` listener and before `_init();` add:

```dart
    // The device saying "network is back" is seconds earlier than the socket
    // noticing (heartbeat 25 s + backoff). Treat it like a resubscribe:
    // catch up, sync changes, refresh the page, and send what waited (#1).
    ref.listen<AsyncValue<bool>>(chatConnectivityProvider, (previous, next) {
      if (previous?.valueOrNull == false && next.valueOrNull == true) {
        _onConnectivityRegained();
      }
    });
```

(c) Add the two methods next to `setViewActive`:

```dart
  void _onConnectivityRegained() {
    unawaited(_repository.ensureRealtimeConnected());
    _onRealtimeEvent(const ChatRealtimeEvent.resync());
  }

  /// The screen reports the app coming back to the foreground. supabase_flutter
  /// rejoins channels on resume too (which emits a resync), but that waits on
  /// the socket; this runs the same batch immediately.
  void onAppResumed() => _onConnectivityRegained();
```

Add the import `import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart';` to `chat_state.dart`.

(d) In `chat_screen.dart`, `didChangeAppLifecycleState` becomes:

```dart
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    _syncViewActive();
    if (_isForeground) {
      ref
          .read(chatControllerProvider(widget.conversation).notifier)
          .onAppResumed();
    }
  }
```

- [ ] **Step 4: Add the drainer**

Create `lib/features/chat/presentation/state/chat_outbox_drainer.dart`:

```dart
import 'dart:async';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sends what is still queued for chats that are not open.
///
/// A message typed in a tunnel, with the chat then closed, used to wait
/// until that chat was reopened: the only flushers lived in the chat's own
/// controller. On app resume and on connectivity returning this reads the
/// whole outbox, wakes the controller of every relationship that has
/// waiting rows, flushes it, and releases it so it is evicted on the usual
/// keep-alive. Warmed once from App.initState.
final chatOutboxDrainerProvider = Provider<ChatOutboxDrainer>((ref) {
  final drainer = ChatOutboxDrainer(ref);
  ref.onDispose(drainer.dispose);
  return drainer;
});

class ChatOutboxDrainer {
  ChatOutboxDrainer(this._ref) {
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(drain()));
    _ref.listen<AsyncValue<bool>>(chatConnectivityProvider, (previous, next) {
      if (previous?.valueOrNull == false && next.valueOrNull == true) {
        unawaited(drain());
      }
    });
  }

  final Ref _ref;
  AppLifecycleListener? _lifecycle;
  bool _draining = false;

  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      final user = _ref.read(currentUserProvider);
      if (user == null) return;
      final queue = await _ref.read(chatCacheServiceProvider).readOutbox(user.id);
      final relationshipIds = <String>{
        for (final item in queue)
          if (item.state != PendingSendState.failedPermanent) item.relationshipId,
      };
      if (relationshipIds.isEmpty) return;

      List<Conversation> conversations;
      try {
        conversations = await _ref.read(conversationsProvider.future);
      } catch (_) {
        conversations = await _ref
            .read(chatCacheServiceProvider)
            .readConversations(user.id);
      }
      for (final conversation in conversations) {
        if (!relationshipIds.contains(conversation.relationshipId)) continue;
        // Listening (not just reading) keeps the autoDispose controller
        // alive for the flush; closing the subscription afterwards starts
        // its normal keep-alive eviction.
        final subscription = _ref.listen<ChatState>(
          chatControllerProvider(conversation),
          (_, __) {},
        );
        try {
          await _ref
              .read(chatControllerProvider(conversation).notifier)
              .flushOutbox(force: true);
        } catch (error) {
          ChatLog.e(
            'outbox drain failed rel=${ChatLog.shortId(conversation.relationshipId)}',
            error,
          );
        } finally {
          subscription.close();
        }
      }
    } catch (error) {
      ChatLog.e('outbox drain failed', error);
    } finally {
      _draining = false;
    }
  }

  void dispose() {
    _lifecycle?.dispose();
    _lifecycle = null;
  }
}
```

In `lib/app/app.dart`, `_AppState.initState`, after the OneSignal microtask add:

```dart
    // Sends what was typed offline for chats that are not open, on resume and
    // when connectivity returns (chat W1a #1).
    Future.microtask(() {
      if (!mounted) return;
      ref.read(chatOutboxDrainerProvider);
    });
```

with the import `import 'package:attune/features/chat/presentation/state/chat_outbox_drainer.dart';`.

- [ ] **Step 5: Run the new tests and the chat suite**

Run: `flutter test test/features/chat/chat_outbox_triggers_test.dart`
Expected: `All tests passed!` (5 tests).

Run: `flutter test test/features/chat`
Expected: `All tests passed!`.

- [ ] **Step 6: Checkpoint**

Run: `flutter analyze lib/features/chat/presentation/state/chat_state.dart lib/features/chat/presentation/state/chat_outbox_drainer.dart lib/features/chat/presentation/screens/chat_screen.dart lib/app/app.dart test/features/chat/chat_outbox_triggers_test.dart | grep -E '^\s*(error|warning) '`
Expected: no output. `dart format lib/features/chat/presentation/state/chat_outbox_drainer.dart` is allowed (new file only). No commit (the owner commits).

---

### Task 8: View-active follows the route and the lifecycle — no read receipts or presence while a game, viewer or sheet covers the chat, or while the app is backgrounded/locked (#10)

**Files:**
- Create: `lib/app/routing/app_route_observer.dart`
- Modify: `lib/app/routing/app_router.dart` (`createAppRouter`: one `observers:` line)
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (`_ChatScreenState` mixins, `didChangeDependencies`, `dispose`, `didPushNext`, `didPopNext`, `_syncViewActive`)
- Test: `test/features/chat/chat_screen_view_active_test.dart`

**Interfaces:**
- Produces: `class AppRouteObserver extends RouteObserver<ModalRoute<void>>` with `Route<dynamic>? lastPushedRoute`, and `final AppRouteObserver appRouteObserver` (app-wide; any screen may subscribe).
- Consumes: `ChatController.setViewActive(bool)`, `onAppResumed()` (Task 7).

Design: `State.deactivate` fires only when the element leaves the tree; a route pushed on top keeps the chat mounted, so `_isViewActive` stayed true through every game, the media viewer, message info and the streak camera — read receipts were written and presence kept the push suppressed for a chat nobody was looking at. All routes live on the root navigator (no `ShellRoute` in `app_router.dart`), so one `RouteObserver` on `GoRouter.observers` sees every push over the chat. `RouteAware.didPushNext` → inactive, `didPopNext` → re-evaluate. **Popups are not covers**: a message-actions sheet, an emoji picker, a confirm dialog or a menu is a `PopupRoute` that leaves the chat on screen with the person in it; treating it as a cover would drop presence (so the partner's next message pushes a notification banner over the chat the person is looking at, and "Active in this chat" flickers on every long-press) and stop read receipts mid-conversation. `RouteAware.didPushNext` is not told which route was pushed, so the observer records the last pushed route and the screen ignores the signal when it is a `PopupRoute`. Lifecycle: anything but `resumed` (including `inactive`, which iOS sends on screen lock) is background. The presence heartbeat already follows `_isViewActive` inside the controller, so it stops with it. `deactivate()` stays as the backstop for a pop.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/chat/chat_screen_view_active_test.dart`:

```dart
import 'dart:async';

import 'package:attune/app/routing/app_route_observer.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';

  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    FakeChatRepository repo,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = buildChatContainer(repository: repo, userId: userId);
    final convo = activeConversation(relId);
    repo.conversationOverride = convo;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(
            navigatorObservers: [appRouteObserver],
            home: ChatScreen(conversation: convo),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  Future<void> tearDownChat(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  }

  /// Drives the lifecycle the way the engine does (the public channel), so
  /// WidgetsBindingObserver.didChangeAppLifecycleState fires on the screen.
  Future<void> setLifecycle(WidgetTester tester, String state) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage(state),
      (_) {},
    );
  }

  testWidgets('a route pushed over the chat ends presence and stops read receipts '
      'until it pops', (tester) async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = await pumpChat(tester, repo);
    expect(repo.presenceCalls.last, relId, reason: 'the chat is on screen');

    final navigator = Navigator.of(tester.element(find.byType(ChatScreen)));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Center(child: Text('Love Map'))),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.presenceCalls.last, isNull, reason: 'a game covers the chat');

    // The partner writes while the game is open.
    repo.seedIncoming(
      id: 'inc-1',
      relationshipId: relId,
      senderId: 'partner',
      content: 'are you there?',
      createdAt: DateTime.now(),
    );
    repo.emitRealtime();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 700));
    expect(repo.markReadCalls, isEmpty,
        reason: 'nobody saw it: it must not be marked read');

    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.presenceCalls.last, relId, reason: 'back on the chat');
    await tester.pump(const Duration(milliseconds: 700));
    expect(repo.markReadCalls, isNotEmpty, reason: 'now it has been seen');

    await tearDownChat(tester, container);
  });

  testWidgets('leaving the foreground (inactive, as on screen lock) ends presence; '
      'resuming restores it', (tester) async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = await pumpChat(tester, repo);
    expect(repo.presenceCalls.last, relId);

    await setLifecycle(tester, 'AppLifecycleState.inactive');
    await tester.pump(const Duration(milliseconds: 50));
    expect(repo.presenceCalls.last, isNull);

    await setLifecycle(tester, 'AppLifecycleState.paused');
    await tester.pump(const Duration(milliseconds: 50));
    expect(repo.presenceCalls.last, isNull);

    await setLifecycle(tester, 'AppLifecycleState.resumed');
    await tester.pump(const Duration(milliseconds: 50));
    expect(repo.presenceCalls.last, relId);

    await tearDownChat(tester, container);
  });

  testWidgets('a sheet or dialog over the chat keeps presence and read receipts: '
      'the person is still in the chat', (tester) async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = await pumpChat(tester, repo);
    expect(repo.presenceCalls.last, relId);
    final presenceCallsBefore = repo.presenceCalls.length;

    final chatContext = tester.element(find.byType(ChatScreen));
    unawaited(
      showModalBottomSheet<void>(
        context: chatContext,
        builder:
            (_) => const SizedBox(height: 200, child: Text('Message actions')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.presenceCalls.length, presenceCallsBefore,
        reason: 'a popup route must not clear presence');

    repo.seedIncoming(
      id: 'inc-1',
      relationshipId: relId,
      senderId: 'partner',
      content: 'still here?',
      createdAt: DateTime.now(),
    );
    repo.emitRealtime();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 700));
    expect(repo.markReadCalls, isNotEmpty,
        reason: 'the chat is still what the person is looking at');

    Navigator.of(chatContext).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.presenceCalls.last, relId);

    await tearDownChat(tester, container);
  });
}
```

- [ ] **Step 2: Run to verify failure for the right reason**

Run: `flutter test test/features/chat/chat_screen_view_active_test.dart`
Expected: compile error `Target of URI doesn't exist: 'package:attune/app/routing/app_route_observer.dart'`. (With the observer file alone, the first test fails at `expect(repo.presenceCalls.last, isNull)` with `Actual: 'rel-1'` — the push did not clear the view; the third test passes before the change and must still pass after it — it is the regression guard for the popup rule.)

- [ ] **Step 3: Add the observer and subscribe the chat screen**

Create `lib/app/routing/app_route_observer.dart`:

```dart
import 'package:flutter/widgets.dart';

/// The one navigator observer the app installs (see createAppRouter).
///
/// Screens that must know when another route is pushed over them — the
/// chat, whose read receipts and presence may only run while it is the
/// screen the person is looking at — subscribe with [RouteAware].
/// `State.deactivate` does not fire for a push (the covered route stays
/// mounted), which is why the chat used to mark messages read during a game.
class AppRouteObserver extends RouteObserver<ModalRoute<void>> {
  /// The route most recently pushed anywhere on this navigator. Read inside
  /// [RouteAware.didPushNext], which says THAT something was pushed over the
  /// subscriber but not what: a page covers the chat; a sheet, dialog or
  /// menu ([PopupRoute]) leaves it on screen with the person still in it.
  Route<dynamic>? lastPushedRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushedRoute = route;
    super.didPush(route, previousRoute);
  }
}

final AppRouteObserver appRouteObserver = AppRouteObserver();
```

In `lib/app/routing/app_router.dart`, add the import `import 'package:attune/app/routing/app_route_observer.dart';` and, in `createAppRouter`, directly after `navigatorKey: appNavigatorKey,` add `observers: [appRouteObserver],`.

In `lib/features/chat/presentation/screens/chat_screen.dart`:

(a) Import `package:attune/app/routing/app_route_observer.dart`.

(b) Change the class header to `class _ChatScreenState extends ConsumerState<ChatScreen> with WidgetsBindingObserver, RouteAware {` and add the fields next to `bool _isForeground = true;`:

```dart
  /// True while another route (a game, a viewer, a sheet) sits on top of this
  /// one. Set by RouteAware; State.deactivate does not fire for a push.
  bool _coveredByRoute = false;
  ModalRoute<Object?>? _observedRoute;
```

(c) Add after `initState`:

```dart
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && !identical(route, _observedRoute)) {
      if (_observedRoute != null) appRouteObserver.unsubscribe(this);
      _observedRoute = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    // A sheet, dialog or menu (PopupRoute) leaves the chat visible and the
    // person in it: presence and read receipts carry on. Anything else — a
    // game, a viewer, settings, a camera — covers it.
    if (appRouteObserver.lastPushedRoute is PopupRoute) return;
    _coveredByRoute = true;
    _syncViewActive();
  }

  @override
  void didPopNext() {
    _coveredByRoute = false;
    _syncViewActive();
    // ModalRoute.isCurrent can lag the pop by a frame; settle once more.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncViewActive());
  }
```

(d) In `dispose()`, before `WidgetsBinding.instance.removeObserver(this);` add `appRouteObserver.unsubscribe(this);`.

(e) Replace `_syncViewActive`:

```dart
  /// Reports current view visibility to the controller. The conversation is
  /// "active" for read purposes only while nothing but a popup (sheet,
  /// dialog, menu) sits over this route — a page pushed on top covers it —
  /// and the app is foregrounded (resumed — inactive/paused/hidden all count
  /// as away, which covers the lock screen).
  void _syncViewActive() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    final isCurrentRoute =
        !_coveredByRoute &&
        (route == null ||
            route.isCurrent ||
            // Not current only because a popup is open on top of it.
            appRouteObserver.lastPushedRoute is PopupRoute);
    ref
        .read(chatControllerProvider(widget.conversation).notifier)
        .setViewActive(_isForeground && isCurrentRoute);
  }
```

(f) Update the `deactivate()` doc comment's last paragraph to: `// deactivate() rather than dispose(): ref is still usable here. It fires on a pop; a push over this route is handled by RouteAware (didPushNext), which deactivate() does not see.` Leave the call as is.

`_openPulse`/`_openInsights` keep their manual `_syncViewActive()` calls (harmless; the observer now covers them).

- [ ] **Step 4: Run the test and the chat widget tests**

Run: `flutter test test/features/chat/chat_screen_view_active_test.dart`
Expected: `All tests passed!` (3 tests).

Run: `flutter test test/features/chat`
Expected: `All tests passed!`.

- [ ] **Step 5: Checkpoint**

Run: `flutter analyze lib/app/routing/app_route_observer.dart lib/app/routing/app_router.dart lib/features/chat/presentation/screens/chat_screen.dart test/features/chat/chat_screen_view_active_test.dart | grep -E '^\s*(error|warning) '`
Expected: no output. `dart format lib/app/routing/app_route_observer.dart` is allowed (new file). No commit (the owner commits).

---

### Task 9: Restoring a saved draft must not say "typing…" (#11)

**Files:**
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (`_restoreDraft`)
- Test: `test/features/chat/chat_screen_draft_restore_test.dart`

**Interfaces:**
- Consumes: `FakeChatRepository.sentTyping` (records every `sendTyping` call), `ChatCacheService.writeDraft`.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/chat/chat_screen_draft_restore_test.dart`:

```dart
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    FakeChatRepository repo, {
    required String savedDraft,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = buildChatContainer(repository: repo, userId: 'user-a');
    await container
        .read(chatCacheServiceProvider)
        .writeDraft('user-a', 'rel-1', savedDraft);
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(home: ChatScreen(conversation: convo)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  Future<void> tearDownChat(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  }

  testWidgets('restoring a saved draft fills the composer without telling the partner '
      'I am typing', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final container = await pumpChat(tester, repo, savedDraft: 'hey, about tonight');

    expect(find.text('hey, about tonight'), findsOneWidget);
    expect(repo.sentTyping, isEmpty,
        reason: 'a restore is not typing; the partner must not see "typing…"');

    // Actually typing still does.
    await tester.enterText(find.byType(TextField).first, 'hey, about tonight!');
    await tester.pump(const Duration(milliseconds: 50));
    expect(repo.sentTyping.where((t) => t.typing), isNotEmpty);

    await tearDownChat(tester, container);
  });
}
```

- [ ] **Step 2: Run to verify failure for the right reason**

Run: `flutter test test/features/chat/chat_screen_draft_restore_test.dart`
Expected: FAIL at `expect(repo.sentTyping, isEmpty)` with `Actual: [(typing: true)]`.

- [ ] **Step 3: Restore without the draft listener**

In `_restoreDraft` (chat_screen.dart), replace the plain-draft tail

```dart
    if (draft.isEmpty) return;
    _controller.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
```

with

```dart
    if (draft.isEmpty) return;
    // Restoring is not typing. Set the text without the draft listener,
    // exactly like the initialDraft branch above: no typing broadcast to the
    // partner, and the identical draft is not re-encrypted and re-written.
    _controller.removeListener(_onDraftChanged);
    _controller.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
    _controller.addListener(_onDraftChanged);
```

- [ ] **Step 4: Run the test and the existing draft tests**

Run: `flutter test test/features/chat/chat_screen_draft_restore_test.dart test/features/chat/chat_screen_initial_draft_test.dart`
Expected: `All tests passed!`.

- [ ] **Step 5: Checkpoint**

Run: `flutter analyze lib/features/chat/presentation/screens/chat_screen.dart test/features/chat/chat_screen_draft_restore_test.dart | grep -E '^\s*(error|warning) '`
Expected: no output. No commit (the owner commits).

---

### Task 10: The local cache can never stop the app from starting (#12)

**Files:**
- Modify: `lib/features/chat/data/cache/chat_cache_backend_base.dart` (add `reset()`)
- Modify: `lib/features/chat/data/cache/chat_cache_backend_io.dart` (`reset()`; `init` closes a stale handle)
- Modify: `lib/features/chat/data/cache/chat_cache_backend_stub.dart` (`reset()`)
- Modify: `lib/features/chat/data/cache/chat_cache_service.dart` (`init` with recovery, guarded reads/writes, memory fallback)
- Modify: `lib/main.dart` (guarded, bounded `chatCache.init()`)
- Test: `test/features/chat/chat_cache_recovery_test.dart`

**Interfaces:**
- Produces: `Future<void> ChatCacheBackend.reset()` (close and delete the store; the next `init()` recreates it); `ChatCacheService.init()` never throws; every `read*` returns an empty result on a backend error and every write/remove swallows and logs one; `bool ChatCacheService.isDegraded` (true when running on the in-memory fallback).
- Consumes: `chat_cache_backend_stub.dart`'s `createBackend()` as the in-memory fallback (importable on every platform — it has no platform deps).

Design (Spec 16 "Drift migration/corruption fails → rebuild read cache from server; preserve recoverable queue"): open → on failure delete `attune_chat_cache.sqlite{,-wal,-shm,-journal}` and open once more → on failure run this session on an in-memory backend. The keystore read gets the same 3 s bound `main.dart` already applies to the safety lock. A runtime SQLite error is a cache miss, never an exception into a controller. `main()` bounds the whole init so a hung open cannot hold the splash.

- [ ] **Step 1: Write the failing tests**

Create `test/features/chat/chat_cache_recovery_test.dart`:

```dart
import 'package:attune/features/chat/data/cache/chat_cache_backend_base.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// A backend that fails to open a scripted number of times, can be reset,
/// and can be told to throw on reads — the three ways SQLite fails in the
/// field (corrupt file, locked WAL, disk I/O).
class _FlakyBackend implements ChatCacheBackend {
  _FlakyBackend({this.initFailuresLeft = 0});

  final ChatCacheBackend inner = memBackend();
  int initFailuresLeft;
  int resetCalls = 0;
  bool throwOnReads = false;
  bool throwOnWrites = false;

  @override
  Future<void> init() async {
    if (initFailuresLeft > 0) {
      initFailuresLeft--;
      throw StateError('SQLITE_CORRUPT: database disk image is malformed');
    }
    await inner.init();
  }

  @override
  Future<void> reset() async {
    resetCalls++;
    await inner.clearAll();
  }

  Future<T> _read<T>(Future<T> Function() run) {
    if (throwOnReads) throw StateError('SQLITE_IOERR: disk I/O error');
    return run();
  }

  Future<void> _write(Future<void> Function() run) {
    if (throwOnWrites) throw StateError('SQLITE_FULL: database or disk is full');
    return run();
  }

  @override
  Future<String?> readMessages(String userId, String relationshipId) =>
      _read(() => inner.readMessages(userId, relationshipId));
  @override
  Future<void> writeMessages(String userId, String relationshipId, String payload) =>
      _write(() => inner.writeMessages(userId, relationshipId, payload));
  @override
  Future<void> deleteMessages(String userId, String relationshipId) =>
      _write(() => inner.deleteMessages(userId, relationshipId));
  @override
  Future<String?> readConversations(String userId) =>
      _read(() => inner.readConversations(userId));
  @override
  Future<void> writeConversations(String userId, String payload) =>
      _write(() => inner.writeConversations(userId, payload));
  @override
  Future<List<String>> readOutbox(String userId, {String? relationshipId}) =>
      _read(() => inner.readOutbox(userId, relationshipId: relationshipId));
  @override
  Future<void> putOutbox(String userId, String relationshipId, String clientMessageId,
          String payload, int createdAtMillis) =>
      _write(() => inner.putOutbox(userId, relationshipId, clientMessageId, payload, createdAtMillis));
  @override
  Future<void> removeOutbox(String userId, String relationshipId, String clientMessageId) =>
      _write(() => inner.removeOutbox(userId, relationshipId, clientMessageId));
  @override
  Future<List<({String relationshipId, String clientMessageId})>> oldestOutbox(
          String userId, int limit) =>
      _read(() => inner.oldestOutbox(userId, limit));
  @override
  Future<void> purgeOutboxForRelationship(String userId, String relationshipId) =>
      _write(() => inner.purgeOutboxForRelationship(userId, relationshipId));
  @override
  Future<String?> readDraft(String userId, String relationshipId) =>
      _read(() => inner.readDraft(userId, relationshipId));
  @override
  Future<void> writeDraft(String userId, String relationshipId, String draft) =>
      _write(() => inner.writeDraft(userId, relationshipId, draft));
  @override
  Future<void> clearDraft(String userId, String relationshipId) =>
      _write(() => inner.clearDraft(userId, relationshipId));
  @override
  Future<void> clearAll() => _write(inner.clearAll);
}

void main() {
  PendingSend pending(String id) => PendingSend(
    clientMessageId: id,
    relationshipId: 'rel-1',
    senderId: 'user-a',
    text: 'queued',
    createdAt: DateTime.now(),
  );

  test('a corrupt database is rebuilt once and the cache then works', () async {
    final backend = _FlakyBackend(initFailuresLeft: 1);
    final cache = ChatCacheService.forTesting(backend: backend);

    await cache.init(); // must not throw

    expect(backend.resetCalls, 1);
    expect(cache.isDegraded, isFalse);
    await cache.putOutbox('user-a', pending('q1'));
    expect((await cache.readOutbox('user-a')).single.clientMessageId, 'q1');
  });

  test('a database that cannot be rebuilt falls back to memory for the session', () async {
    final backend = _FlakyBackend(initFailuresLeft: 5);
    final cache = ChatCacheService.forTesting(backend: backend);

    await cache.init(); // must not throw

    expect(backend.resetCalls, 1);
    expect(cache.isDegraded, isTrue);
    await cache.putOutbox('user-a', pending('q1'));
    expect((await cache.readOutbox('user-a')).single.clientMessageId, 'q1',
        reason: 'the queue still works within the session');
  });

  test('a runtime read or write failure is a cache miss, not an exception', () async {
    final backend = _FlakyBackend();
    final cache = ChatCacheService.forTesting(backend: backend);
    await cache.init();
    await cache.putOutbox('user-a', pending('q1'));

    backend.throwOnReads = true;
    expect(await cache.readMessages('user-a', 'rel-1'), isEmpty);
    expect(await cache.readConversations('user-a'), isEmpty);
    expect(await cache.readOutbox('user-a'), isEmpty);
    expect(await cache.readDraft('user-a', 'rel-1'), '');

    backend.throwOnReads = false;
    backend.throwOnWrites = true;
    await cache.writeDraft('user-a', 'rel-1', 'x'); // must not throw
    await cache.writeMessages('user-a', 'rel-1', const []);
    await cache.removeOutbox('user-a', 'rel-1', 'q1');
    await cache.clearAll();
  });

  test('a chat opened over a broken cache still loads from the server', () async {
    final backend = _FlakyBackend()..throwOnReads = true;
    final cache = ChatCacheService.forTesting(backend: backend);
    await cache.init();
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'inc-1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'from the server',
      createdAt: DateTime.now(),
    );
    final container = buildChatContainer(repository: repo, userId: 'user-a', cache: cache);
    addTearDown(container.dispose);
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;

    container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = container.read(chatControllerProvider(convo));
    expect(state.isLoading, isFalse);
    expect(state.messages.map((m) => m.id), ['inc-1']);
  });

  test('main() cannot be held by cache init', () {
    // Source-level: main is not unit-testable. The init call must be
    // bounded and guarded so a hung keystore or a locked file never holds
    // the splash (Spec 16).
    final source = File('lib/main.dart').readAsStringSync();
    final at = source.indexOf('chatCache.init()');
    final around = source.substring(at - 80, at + 160);
    expect(around, contains('.timeout('));
    expect(around, contains('catch'));
  });
}
```

Add `import 'dart:io';` at the top.

- [ ] **Step 2: Run to verify failure for the right reason**

Run: `flutter test test/features/chat/chat_cache_recovery_test.dart`
Expected: compile errors — `The method doesn't override an inherited method` on `_FlakyBackend.reset()` (the interface has no `reset` yet) and `The getter 'isDegraded' isn't defined for the type 'ChatCacheService'`. (With both stubbed, "a corrupt database is rebuilt once" fails because `init()` throws `Bad state: SQLITE_CORRUPT…`.)

- [ ] **Step 3: Add `reset()` to the backends**

`chat_cache_backend_base.dart` — add to the abstract class, after `init()`:

```dart
  /// Closes and deletes the store so the next [init] starts from nothing.
  /// Used once when [init] fails (corrupt or locked file). The outbox is
  /// lost with it — it was unreadable anyway — and the read cache rebuilds
  /// from the server.
  Future<void> reset();
```

`chat_cache_backend_io.dart` — add to `_DriftChatCacheBackend`:

```dart
  static const _fileName = 'attune_chat_cache.sqlite';

  @override
  Future<void> reset() async {
    try {
      await _db?.close();
    } catch (_) {
      // A handle that will not close is exactly the case we are recovering
      // from; the files go regardless.
    }
    _db = null;
    final directory = await getApplicationSupportDirectory();
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final file = File(p.join(directory.path, '$_fileName$suffix'));
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Best-effort; init() will report if the directory is unusable.
      }
    }
  }
```

and in `init()` replace `final file = File(p.join(directory.path, 'attune_chat_cache.sqlite'));` with `final file = File(p.join(directory.path, _fileName));`.

`chat_cache_backend_stub.dart` — add to `_MemoryChatCacheBackend`:

```dart
  @override
  Future<void> reset() async {
    _messages.clear();
    _conversations.clear();
    _outbox.clear();
    _drafts.clear();
  }
```

- [ ] **Step 4: Make the service self-healing and non-throwing**

In `chat_cache_service.dart`:

(a) Add `import 'package:attune/features/chat/data/cache/chat_cache_backend_stub.dart' as memory;` and change `final ChatCacheBackend _backend;` to `ChatCacheBackend _backend;`. Add the field and getter:

```dart
  bool _degraded = false;

  /// True when this session runs on the in-memory fallback because the
  /// on-disk store could not be opened or rebuilt. Nothing persists across
  /// restarts until the next launch opens the disk store again.
  bool get isDegraded => _degraded;
```

(b) Replace `init()`:

```dart
  /// Never throws and never hangs the caller for long (Spec 16: a broken
  /// local database is rebuilt; failing that, the app runs without it).
  Future<void> init() async {
    await _openBackendWithRecovery();
    // Fail-closed on privacy: if key setup fails we operate without a cache
    // rather than persisting plaintext content to disk (Spec 4.4). Bounded:
    // a hung keystore (seen on some Samsung phones) must not hold startup.
    try {
      _cipher ??= await ChatCacheCipher.create().timeout(
        const Duration(seconds: 3),
      );
    } catch (_) {
      _cipher = null;
    }
  }

  Future<void> _openBackendWithRecovery() async {
    try {
      await _backend.init();
      return;
    } catch (error) {
      debugPrint('[chat-cache] open failed (${error.runtimeType}); rebuilding');
    }
    try {
      await _backend.reset();
      await _backend.init();
      return;
    } catch (error) {
      debugPrint(
        '[chat-cache] rebuild failed (${error.runtimeType}); '
        'running without a disk cache this session',
      );
    }
    _degraded = true;
    _backend = memory.createBackend();
    await _backend.init();
  }

  /// A backend failure at runtime is a cache miss, never an exception into
  /// a controller: the server is the source of truth.
  Future<T> _guardRead<T>(String what, Future<T> Function() run, T fallback) async {
    try {
      return await run();
    } catch (error) {
      debugPrint('[chat-cache] $what read failed (${error.runtimeType})');
      return fallback;
    }
  }

  Future<void> _guardWrite(String what, Future<void> Function() run) async {
    try {
      await run();
    } catch (error) {
      debugPrint('[chat-cache] $what write failed (${error.runtimeType})');
    }
  }
```

(c) Wrap every backend call:
- `readMessages`: `final raw = _decrypt(await _guardRead('messages', () => _backend.readMessages(userId, relationshipId), null));`
- `writeMessages`: `await _guardWrite('messages', () => _backend.writeMessages(userId, relationshipId, payload));`
- `readConversations`: `final raw = _decrypt(await _guardRead('conversations', () => _backend.readConversations(userId), null));`
- `writeConversations`: `await _guardWrite('conversations', () => _backend.writeConversations(userId, payload));`
- `readOutbox`: `final rows = await _guardRead('outbox', () => _backend.readOutbox(userId, relationshipId: relationshipId), const <String>[]);`
- `putOutbox`: wrap the `_backend.putOutbox(...)` call in `_guardWrite('outbox', () => ...)`; wrap the overflow trim (`oldestOutbox` + `removeOutbox` loop) in one `_guardWrite('outbox trim', () async { ... })`.
- `removeOutbox`: `await _guardWrite('outbox', () => _backend.removeOutbox(userId, relationshipId, clientMessageId));`
- `purgeRelationship`: wrap the three calls in one `_guardWrite('purge', () async { ... })`.
- `readDraft`: `return _decrypt(await _guardRead('draft', () => _backend.readDraft(userId, relationshipId), null)) ?? '';`
- `writeDraft` and `clearDraft`: `_guardWrite('draft', …)` around the backend calls.
- `clearAll`: `await _guardWrite('clear', _backend.clearAll);`

(d) `lib/main.dart` — replace

```dart
  final chatCache = ChatCacheService();
  await chatCache.init();
```

with

```dart
  final chatCache = ChatCacheService();
  // init() recovers from a corrupt or locked store itself and bounds the
  // keystore read; this outer bound is the last line: a cache can never
  // hold the first frame (Spec 16).
  try {
    await chatCache.init().timeout(const Duration(seconds: 8));
  } catch (error) {
    debugPrint('[startup] chat cache unavailable: ${error.runtimeType}');
  }
```

- [ ] **Step 5: Run the new tests and the chat suite**

Run: `flutter test test/features/chat/chat_cache_recovery_test.dart`
Expected: `All tests passed!` (5 tests).

Run: `flutter test test/features/chat`
Expected: `All tests passed!` (`chat_cache_cipher_test.dart`, `send_persists_to_cache_test.dart`, `streak_outbox_test.dart` unchanged in behaviour).

- [ ] **Step 6: Checkpoint**

Run: `flutter analyze lib/features/chat/data/cache lib/main.dart test/features/chat/chat_cache_recovery_test.dart | grep -E '^\s*(error|warning) '`
Expected: no output. No commit (the owner commits).

---

## Final verification (after Task 10)

- [ ] Run the whole chat suite and the two SQL contract tests once more:

```bash
flutter test test/features/chat
psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/chat_sync_cursor_contracts.sql
psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/chat_message_counters_contracts.sql
psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/chat_system_contracts.sql
flutter analyze lib/features/chat lib/app/routing lib/app/app.dart lib/main.dart test/features/chat | grep -E '^\s*(error|warning) '
```
Expected: `All tests passed!`; three `ROLLBACK`s with no `ERROR`; no analyzer output.

## Rulings (issues in scope that need no further change)

- **#9 "message_count UPDATE echoes"** — fixed server-side in Task 2; no client-side payload diffing is added because once the migration is live the frame no longer exists, and before it the frame is coalesced into the same batch (Task 6) and costs one narrow `getConversation` (Task 3).
- **#8 for reactions** — handled without `REPLICA IDENTITY FULL` on `message_reactions`: Task 1's touch trigger turns every reaction add/remove into an RLS-checked `messages` UPDATE frame carrying the message id, which Task 6 refreshes by id. `REPLICA IDENTITY FULL` is applied to `message_pins` only (Task 1, with the exposure reasoning).
- **01 M-2 / 01 M-4 / 02 M-4 / 02 L-1 (part)** — folded into Task 5 (restart authority, read-only terminal state) and Task 7 (connectivity resync); 02 L-1 is folded into Task 4 (`_catchUpFromCursor` with no cursor loads the first page).
- **Out of this plan's numbered scope, deliberately not changed:** #35 over-10k paste (plan 3); 03 M-4 keystore read failure disabling persistence for the session (not in #1–#12 — the cipher timeout in Task 10 bounds the hang but does not regenerate a corrupt key); 02 L-6 typing on background; 02 M-2/#36 delivered-from-push (plan 1b/3); the "Remove" affordance on *queued* bubbles (RC-3's UI half) is unnecessary once the head timer exists — a queued bubble always has a timer or a pending trigger, and a read-only chat flips it to failed with Remove.

## Owner deploy steps

1. Apply the four migrations to the live project in this order (after this plan's tasks are merged, before shipping the app build that contains Task 4 — `getMessagesChangedSince` logs and skips until `updated_at` exists, everything else is independent). Apply the first one while no chat is open on either test phone: its backfill rewrites every `messages` row once, and each rewritten row is a realtime UPDATE frame to any phone subscribed to that chat at that moment.
   - `supabase/migrations/20261019100000_chat_sync_cursor.sql`
   - `supabase/migrations/20261019100010_chat_sync_cursor_grants.sql`
   - `supabase/migrations/20261019100100_chat_message_counters.sql`
   - `supabase/migrations/20261019100110_chat_message_counters_grants.sql`
   (`supabase db push`, or `psql` against the live database in that order.)
2. Verify on the live database: `select relname, relreplident from pg_class where relname in ('messages','message_pins','message_reactions');` → `messages|d`, `message_pins|f`, `message_reactions|d`; and `select tablename from pg_publication_tables where pubname='supabase_realtime' and tablename='relationship_message_counters';` → no rows.
3. No edge function, Xcode, OneSignal or App Store step in this plan.
4. Two-phone check after deploy (manual): airplane mode → send two texts → close the chat → leave airplane mode with the app in the background → both arrive in order on the partner's phone without reopening the chat; partner reacts to and then un-reacts a week-old photo → both changes show on the other phone within a second; owner deletes a message row in the dashboard → it disappears from both phones on their next open or resume.
