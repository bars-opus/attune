# Together Phase 2a — Proposals, hand-offs and "Needs you": Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make everything that affects the partner a proposal, never a command:
- "Fri or Sat?" time proposals with up to three options. The partner accepts one or declines with a note, and an unanswered proposal expires quietly after 7 days.
- Asking the partner to take something on, as an owner hand-off they accept or decline.
- A "Needs you" section at the top of the Agenda: proposals and hand-offs waiting on me, Planning date polls I haven't voted on, to-dos nobody has taken due within 7 days, and my own proposals still waiting for a reply.

**Architecture:**
- **Server:** an options table plus SECURITY DEFINER RPCs (`propose_couple_event`, `decide_couple_event`, `propose_owner_handoff`, `decide_owner_handoff`) and one read, `list_together_needs_you`. Pushes go into `scheduled_notifications` from the RPCs themselves, as partner-initiated pushes D9 allows. `list_together_items` now lists confirmed events only, so unanswered proposals don't pose as plans.
- **Client:** domain models, repository methods, a needs provider, the Needs-you section, a decide sheet, and a propose mode and owner row in the event editor.

**Tech Stack:** Supabase Postgres 17, Flutter/Riverpod 2, flutter_test, SQL contracts run on the local PG17 harness (`scratchpad/pg/run.sh`, port 55432) while Docker is down.

**Spec:** `docs/superpowers/specs/2026-10-14-together-hub-design.md`: §3.4 (proposals for partner-affecting actions), §6.1 (proposals, ownership), §4.1 (Needs you), D7, D9. The base is Phases 0, 1a and 1b, all uncommitted on main.

## Global Constraints

- Work directly on `main`. Don't commit unless asked. Re-read files before editing them. `dart format` only touched files, one path at a time, and revert any reflow of the owner's untouched code.
- Migrations start at `20261014120000` and step by 100.
- **Hard rules:**
  - No tallies or counts of who did what. "Needs you" lists items, never "you owe 3".
  - Proposals and hand-offs are the only way to put something on the partner.
  - Pushes in this phase are partner-initiated only: a proposal or hand-off sent to you, or a reply to yours (D9).
- **Copy:** sentence case, plain, never blaming. "No reply yet", never "Kofi hasn't answered". Declines are gentle: "Kofi can't make it".
- **SQL harness:** every new table or column a contract touches must exist in the harness stubs. This plan adds `planning_block_items.assigned_to` and `planning_poll_votes` to `scratchpad/pg/stubs.sql`.

## Rulings (decided while planning)

- **R1:** A proposal can carry one to three options. A single option is an invitation ("Dinner Fri 7pm?").
- **R2:** Proposals cannot repeat (`rrule` must be null). Repeating rituals are proposed by Phase 3's own cron.
- **R3:** Expired proposals are hidden from both partners, which keeps expiry quiet. `decide_couple_event` refuses them with `together:expired`. No cron is needed.
- **R4:** "Unowned" applies to Planning to-dos (`assigned_to IS NULL`, not done, due today to today+7). Applying it to events would flag every dinner. This is where the invisible work lives.
- **R5:** A Planning date poll is waiting on me when it has at least one option and I've voted on none of them. Locking a poll turns it into a date block, so it drops out by itself.
- **R6:** Declining a proposal or hand-off sends one gentle push to the person who asked. D9 allows "a reply to your proposal"; the spec's "silence, not confrontation" rule covers leaving a heads-up event, which is unchanged.
- **R7:** "Today" for unowned to-dos uses the caller's `planning_member_settings` zone, falling back to UTC, which matches the alarm cron.

## Review Focus

1. **Accepting an option** must set the event's times from that option exactly: all-day dates or timed instants with tz. Pinned in Task 1's contract.
2. **A proposal can be decided once,** and only by its recipient, and never after expiry. Pinned in Task 1's contract.
3. **Proposals never appear in the Agenda or Month as plans** until they're accepted. Pinned in Task 1's contract.
4. **A hand-off can only go to the partner,** only on a shared event, and accepting sets the owner to the accepter. Pinned in Task 1's contract.
5. **"Needs you" with more than three items** shows three plus a "More" row, never a count of the other person's misses. Pinned in Task 4's test.

---

### Task 1: Proposals and hand-offs (SQL)

**Files:**
- Create: `supabase/migrations/20261014120000_together_proposals.sql`
- Create: `supabase/tests/together_proposals_contracts.sql`
- Modify: `scratchpad/pg/stubs.sql`, adding `planning_block_items.assigned_to uuid` and the `planning_poll_votes` table (outside the repo; the harness only)
- Modify: `supabase/migrations/20261014110200_list_together_items.sql`. It isn't deployed yet, so it is edited in place and the change is noted in the ledger.

**Interfaces:**
- **Columns** added to `couple_events`: `decision_note text` (≤200), `owner_proposed_to uuid`, `owner_proposed_at timestamptz`.
- **Table** `couple_event_options`: `id`, `event_id`, `position` (1–3), `all_day`, `start_date`, `end_date`, `starts_at`, `ends_at`.
- **RPCs:**
  - `propose_couple_event(p_relationship_id uuid, p_event jsonb, p_options jsonb) RETURNS uuid`, where `p_options` is a JSON array of `{start_date, end_date}` or `{starts_at, ends_at}`;
  - `decide_couple_event(p_event_id uuid, p_option_id uuid, p_accept boolean, p_note text DEFAULT NULL) RETURNS void`;
  - `propose_owner_handoff(p_event_id uuid) RETURNS void`;
  - `decide_owner_handoff(p_event_id uuid, p_accept boolean) RETURNS void`;
  - `list_together_needs_you(p_relationship_id uuid)`, returning a table with these columns:

    `(need_kind text, item_id uuid, title text, due_date date, created_by uuid, detail jsonb)`

    `need_kind` is one of `proposal`, `sent_proposal`, `handoff`, `unowned_todo`, `poll`.
- **Pushes** (metadata `type`): `together_proposal`, `together_proposal_reply`, `together_handoff`, `together_handoff_reply`. Each carries `event_id` and `relationship_id`.
- **New error code:** `together:expired`.

- [ ] **Step 1: Harness stubs.** Append to `scratchpad/pg/stubs.sql`:

```sql
ALTER TABLE public.planning_block_items ADD COLUMN assigned_to uuid;
CREATE TABLE public.planning_poll_votes (item_id uuid NOT NULL, relationship_id uuid NOT NULL,
  user_id uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY (item_id, user_id));
```

- [ ] **Step 2: Write the failing contracts** in `supabase/tests/together_proposals_contracts.sql`:

```sql
-- Together Phase 2a contracts: proposals, hand-offs, Needs you.
BEGIN;
INSERT INTO auth.users (id) VALUES
  ('7c000000-0000-0000-0000-0000000000a1'), ('7c000000-0000-0000-0000-0000000000b2'),
  ('7c000000-0000-0000-0000-0000000000c3') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7c000000-0000-0000-0000-0000000000a1', '+233280000001', 'Ama'),
  ('7c000000-0000-0000-0000-0000000000b2', '+233280000002', 'Kofi'),
  ('7c000000-0000-0000-0000-0000000000c3', '+233280000003', 'Stranger') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('7d000000-0000-0000-0000-000000000001', '7c000000-0000-0000-0000-0000000000a1',
        '7c000000-0000-0000-0000-0000000000b2', 'active', now(), now()) ON CONFLICT (id) DO NOTHING;
CREATE TEMP TABLE t_ids (name text PRIMARY KEY, id uuid) ON COMMIT DROP;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;

-- 1. Ama proposes Fri or Sat; Kofi gets one push; it isn't a plan yet.
DO $$
DECLARE v_id uuid; v_n int; v_push int;
BEGIN
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000a1');
  v_id := public.propose_couple_event('7d000000-0000-0000-0000-000000000001',
    '{"title":"Dinner at Buka","all_day":false,"tz":"Africa/Accra","participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb,
    '[{"starts_at":"2026-11-06T19:00:00Z","ends_at":"2026-11-06T21:00:00Z"},{"starts_at":"2026-11-07T19:00:00Z","ends_at":"2026-11-07T21:00:00Z"}]'::jsonb);
  INSERT INTO t_ids VALUES ('dinner', v_id);
  SELECT count(*) INTO v_n FROM public.list_together_items('7d000000-0000-0000-0000-000000000001', '2026-11-01', '2026-11-30') WHERE item_id = v_id;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an unanswered proposal is listed as a plan'; END IF;
  SELECT count(*) INTO v_push FROM public.scheduled_notifications
  WHERE user_id = '7c000000-0000-0000-0000-0000000000b2' AND metadata->>'type' = 'together_proposal' AND metadata->>'event_id' = v_id::text;
  IF v_push <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: proposal push count %', v_push; END IF;
  SELECT count(*) INTO v_n FROM public.list_together_needs_you('7d000000-0000-0000-0000-000000000001') WHERE need_kind = 'sent_proposal' AND item_id = v_id;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: sender does not see their waiting proposal'; END IF;
END $$;

-- 2. Only Kofi can decide; Ama can't; accepting option 2 sets Saturday's times and lists it.
DO $$
DECLARE v_msg text; v_opt uuid; v_start timestamptz; v_status text; v_n int; v_reply int;
BEGIN
  SELECT id INTO v_opt FROM public.couple_event_options WHERE event_id = (SELECT id FROM t_ids WHERE name='dinner') AND position = 2;
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000a1');
  BEGIN
    PERFORM public.decide_couple_event((SELECT id FROM t_ids WHERE name='dinner'), v_opt, true);
    RAISE EXCEPTION 'CONTRACT VIOLATED: the proposer decided their own proposal';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:not_found' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.list_together_needs_you('7d000000-0000-0000-0000-000000000001')
  WHERE need_kind = 'proposal' AND jsonb_array_length(detail->'options') = 2;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: recipient does not see the proposal with 2 options'; END IF;
  PERFORM public.decide_couple_event((SELECT id FROM t_ids WHERE name='dinner'), v_opt, true);
  SELECT starts_at, status INTO v_start, v_status FROM public.couple_events WHERE id = (SELECT id FROM t_ids WHERE name='dinner');
  IF v_start <> '2026-11-07T19:00:00Z'::timestamptz OR v_status <> 'confirmed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: accept gave % %', v_start, v_status;
  END IF;
  SELECT count(*) INTO v_n FROM public.list_together_items('7d000000-0000-0000-0000-000000000001', '2026-11-01', '2026-11-30')
  WHERE item_id = (SELECT id FROM t_ids WHERE name='dinner') AND item_date = '2026-11-07';
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: accepted proposal not listed on Saturday'; END IF;
  SELECT count(*) INTO v_reply FROM public.scheduled_notifications
  WHERE user_id = '7c000000-0000-0000-0000-0000000000a1' AND metadata->>'type' = 'together_proposal_reply';
  IF v_reply <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: proposer reply push count %', v_reply; END IF;
  BEGIN
    PERFORM public.decide_couple_event((SELECT id FROM t_ids WHERE name='dinner'), v_opt, true);
    RAISE EXCEPTION 'CONTRACT VIOLATED: decided twice';
  EXCEPTION WHEN raise_exception THEN NULL;
  END;
END $$;

-- 3. Declining with a note cancels it; an expired proposal can't be decided and is hidden.
DO $$
DECLARE v_id uuid; v_opt uuid; v_status text; v_note text; v_msg text; v_n int;
BEGIN
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000a1');
  v_id := public.propose_couple_event('7d000000-0000-0000-0000-000000000001',
    '{"title":"Hike","all_day":true,"participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb,
    '[{"start_date":"2026-11-14"}]'::jsonb);
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000b2');
  PERFORM public.decide_couple_event(v_id, NULL, false, 'Working that day');
  SELECT status, decision_note INTO v_status, v_note FROM public.couple_events WHERE id = v_id;
  IF v_status <> 'cancelled' OR v_note <> 'Working that day' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: decline gave % %', v_status, v_note; END IF;

  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000a1');
  v_id := public.propose_couple_event('7d000000-0000-0000-0000-000000000001',
    '{"title":"Brunch","all_day":true,"participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb,
    '[{"start_date":"2026-11-15"}]'::jsonb);
  UPDATE public.couple_events SET proposal_expires_at = now() - interval '1 minute' WHERE id = v_id;
  SELECT id INTO v_opt FROM public.couple_event_options WHERE event_id = v_id;
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.list_together_needs_you('7d000000-0000-0000-0000-000000000001') WHERE item_id = v_id;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an expired proposal still needs you'; END IF;
  BEGIN
    PERFORM public.decide_couple_event(v_id, v_opt, true);
    RAISE EXCEPTION 'CONTRACT VIOLATED: expired proposal accepted';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:expired' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;
END $$;

-- 4. Proposals must include the partner, be shared, not repeat, and carry 1–3 options.
DO $$
DECLARE v_msg text;
BEGIN
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000a1');
  BEGIN
    PERFORM public.propose_couple_event('7d000000-0000-0000-0000-000000000001',
      '{"title":"Solo","all_day":true,"participant_ids":["7c000000-0000-0000-0000-0000000000a1"]}'::jsonb,
      '[{"start_date":"2026-11-14"}]'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: proposal without the partner accepted';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:invalid_input' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;
  BEGIN
    PERFORM public.propose_couple_event('7d000000-0000-0000-0000-000000000001',
      '{"title":"Too many","all_day":true,"participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb,
      '[{"start_date":"2026-11-14"},{"start_date":"2026-11-15"},{"start_date":"2026-11-16"},{"start_date":"2026-11-17"}]'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: four options accepted';
  EXCEPTION WHEN raise_exception THEN NULL;
  END;
  BEGIN
    PERFORM public.propose_couple_event('7d000000-0000-0000-0000-000000000001',
      '{"title":"Weekly","all_day":true,"rrule":"FREQ=WEEKLY","participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb,
      '[{"start_date":"2026-11-14"}]'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: repeating proposal accepted';
  EXCEPTION WHEN raise_exception THEN NULL;
  END;
END $$;

-- 5. Hand-off: Ama asks Kofi to own a shared event; he accepts and owns it.
DO $$
DECLARE v_id uuid; v_owner uuid; v_n int;
BEGIN
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000a1');
  v_id := public.create_couple_event('7d000000-0000-0000-0000-000000000001',
    '{"title":"Book the plumber","all_day":true,"start_date":"2026-11-10","participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM public.propose_owner_handoff(v_id);
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.list_together_needs_you('7d000000-0000-0000-0000-000000000001') WHERE need_kind = 'handoff' AND item_id = v_id;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: hand-off not waiting on Kofi'; END IF;
  PERFORM public.decide_owner_handoff(v_id, true);
  SELECT owner_id INTO v_owner FROM public.couple_events WHERE id = v_id;
  IF v_owner <> '7c000000-0000-0000-0000-0000000000b2' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: owner after accept %', v_owner; END IF;
END $$;

-- 6. Needs you: unowned to-dos due this week and polls awaiting my vote; no counts.
DO $$
DECLARE v_entry uuid; v_block uuid; v_poll uuid; v_opt uuid; v_n int; v_result text;
BEGIN
  INSERT INTO public.planning_entries (relationship_id, title) VALUES ('7d000000-0000-0000-0000-000000000001', 'Summer') RETURNING id INTO v_entry;
  INSERT INTO public.planning_blocks (entry_id, relationship_id, block_type) VALUES (v_entry, '7d000000-0000-0000-0000-000000000001', 'checklist') RETURNING id INTO v_block;
  INSERT INTO public.planning_block_items (block_id, relationship_id, text, due_date) VALUES
    (v_block, '7d000000-0000-0000-0000-000000000001', 'Book summer camp', current_date + 3),
    (v_block, '7d000000-0000-0000-0000-000000000001', 'Far off', current_date + 30);
  INSERT INTO public.planning_blocks (entry_id, relationship_id, block_type) VALUES (v_entry, '7d000000-0000-0000-0000-000000000001', 'date_poll') RETURNING id INTO v_poll;
  INSERT INTO public.planning_block_items (block_id, relationship_id, text) VALUES (v_poll, '7d000000-0000-0000-0000-000000000001', 'Option') RETURNING id INTO v_opt;

  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.list_together_needs_you('7d000000-0000-0000-0000-000000000001')
  WHERE (need_kind = 'unowned_todo' AND title = 'Book summer camp') OR (need_kind = 'poll' AND detail->>'entry_id' = v_entry::text);
  IF v_n <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: unowned to-do/poll needs %', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.list_together_needs_you('7d000000-0000-0000-0000-000000000001') WHERE title = 'Far off';
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a to-do a month out needs you'; END IF;

  INSERT INTO public.planning_poll_votes (item_id, relationship_id, user_id) VALUES (v_opt, '7d000000-0000-0000-0000-000000000001', '7c000000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.list_together_needs_you('7d000000-0000-0000-0000-000000000001') WHERE need_kind = 'poll';
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a poll I voted on still needs me'; END IF;

  SELECT pg_get_function_result('public.list_together_needs_you(uuid)'::regprocedure) INTO v_result;
  IF v_result ~* '(count|total|tally|score)' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: needs-you returns an aggregate: %', v_result; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

ROLLBACK;
```

- [ ] **Step 3: Run to verify it fails.** Run `scratchpad/pg/run.sh supabase/tests/together_proposals_contracts.sql` (start the cluster first with `pg_ctl -D scratchpad/pg/data -o "-p 55432 -c listen_addresses=127.0.0.1 -c unix_socket_directories=''" start`). Expected: `propose_couple_event does not exist`.

- [ ] **Step 4: Edit `list_together_items`.** In `20261014110200_list_together_items.sql`, change the events branch filter `AND ce.status <> 'cancelled'` to `AND ce.status = 'confirmed'`, and add the comment `-- Proposals are not plans until accepted (Phase 2a R3).` Record this in the ledger as an in-place edit of an undeployed migration.

- [ ] **Step 5: Write the migration** `20261014120000_together_proposals.sql`:

```sql
-- Together Phase 2a: proposals ("Fri or Sat?"), owner hand-offs, and the
-- "Needs you" read. Everything that puts something on the partner is a
-- proposal they answer (spec §3.4). Pushes here are partner-initiated (D9).

ALTER TABLE public.couple_events
  ADD COLUMN decision_note text CHECK (decision_note IS NULL OR char_length(decision_note) <= 200),
  ADD COLUMN owner_proposed_to uuid,
  ADD COLUMN owner_proposed_at timestamptz;

CREATE TABLE public.couple_event_options (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.couple_events(id) ON DELETE CASCADE,
  position smallint NOT NULL CHECK (position BETWEEN 1 AND 3),
  all_day boolean NOT NULL,
  start_date date, end_date date, starts_at timestamptz, ends_at timestamptz,
  UNIQUE (event_id, position),
  CONSTRAINT couple_event_options_when CHECK (
    (all_day AND start_date IS NOT NULL AND starts_at IS NULL AND ends_at IS NULL
       AND (end_date IS NULL OR end_date >= start_date))
    OR (NOT all_day AND starts_at IS NOT NULL AND start_date IS NULL AND end_date IS NULL
       AND (ends_at IS NULL OR ends_at >= starts_at)))
);
ALTER TABLE public.couple_event_options ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.couple_event_options FROM PUBLIC, anon, authenticated;

-- One push to one person, idempotent per key.
CREATE FUNCTION public.together_push(p_user uuid, p_type text, p_title text, p_body text,
  p_event public.couple_events, p_key text) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO public.scheduled_notifications
    (user_id, notification_type, scheduled_for, status, metadata, source_key)
  VALUES (p_user, 'immediate', now(), 'pending',
    jsonb_build_object('type', p_type, 'title', p_title, 'body', left(p_body, 160),
      'event_id', p_event.id, 'relationship_id', p_event.relationship_id), p_key)
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING
$$;
REVOKE ALL ON FUNCTION public.together_push(uuid, text, text, text, public.couple_events, text) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.together_name(p_user uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((SELECT nullif(btrim(display_name), '') FROM public.users WHERE id = p_user), 'Your partner')
$$;
REVOKE ALL ON FUNCTION public.together_name(uuid) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.together_partner(p_relationship_id uuid, p_me uuid) RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN r.user_a = p_me THEN r.user_b ELSE r.user_a END
  FROM public.relationships r WHERE r.id = p_relationship_id
$$;
REVOKE ALL ON FUNCTION public.together_partner(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.propose_couple_event(p_relationship_id uuid, p_event jsonb, p_options jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_actor uuid := public.together_actor(p_relationship_id);
  v_partner uuid := public.together_partner(p_relationship_id, v_actor);
  e public.together_event_input;
  v_first jsonb;
  v_id uuid;
  v_row public.couple_events;
  v_i int := 0;
  v_opt jsonb;
BEGIN
  BEGIN
    e := jsonb_populate_record(NULL::public.together_event_input, p_event);
  EXCEPTION WHEN OTHERS THEN PERFORM public.together_fail('invalid_input');
  END;
  IF v_partner IS NULL OR p_options IS NULL OR jsonb_typeof(p_options) <> 'array'
     OR jsonb_array_length(p_options) NOT BETWEEN 1 AND 3
     OR e.rrule IS NOT NULL OR coalesce(e.visibility, 'shared') <> 'shared'
     OR e.participant_ids IS NULL OR NOT (v_partner = ANY (e.participant_ids)) THEN
    PERFORM public.together_fail('invalid_input');
  END IF;
  v_first := p_options -> 0;
  e.start_date := (v_first->>'start_date')::date;
  e.end_date := (v_first->>'end_date')::date;
  e.starts_at := (v_first->>'starts_at')::timestamptz;
  e.ends_at := (v_first->>'ends_at')::timestamptz;
  PERFORM public.together_validate_input(p_relationship_id, v_actor, e);
  BEGIN
    INSERT INTO public.couple_events (
      relationship_id, created_by, kind, title, note, location_name, all_day,
      start_date, end_date, starts_at, ends_at, tz, participant_ids, owner_id,
      visibility, remind_offsets_min, status, proposed_to, proposal_expires_at)
    VALUES (p_relationship_id, v_actor, coalesce(e.kind, 'event'), btrim(e.title),
      nullif(btrim(e.note), ''), nullif(btrim(e.location_name), ''), e.all_day,
      e.start_date, e.end_date, e.starts_at, e.ends_at, e.tz, e.participant_ids, e.owner_id,
      'shared', coalesce(e.remind_offsets_min, '{}'), 'proposed', v_partner, now() + interval '7 days')
    RETURNING * INTO v_row;
    FOR v_opt IN SELECT * FROM jsonb_array_elements(p_options) LOOP
      v_i := v_i + 1;
      INSERT INTO public.couple_event_options (event_id, position, all_day, start_date, end_date, starts_at, ends_at)
      VALUES (v_row.id, v_i, e.all_day, (v_opt->>'start_date')::date, (v_opt->>'end_date')::date,
              (v_opt->>'starts_at')::timestamptz, (v_opt->>'ends_at')::timestamptz);
    END LOOP;
  EXCEPTION WHEN check_violation OR not_null_violation OR invalid_datetime_format
            OR datetime_field_overflow OR invalid_text_representation THEN
    PERFORM public.together_fail('invalid_input');
  END;
  PERFORM public.together_push(v_partner, 'together_proposal',
    public.together_name(v_actor) || ' suggested a plan', v_row.title, v_row,
    'together_proposal:' || v_row.id);
  RETURN v_row.id;
END;
$$;

CREATE FUNCTION public.decide_couple_event(p_event_id uuid, p_option_id uuid, p_accept boolean, p_note text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row public.couple_events; v_opt public.couple_event_options; v_me uuid := auth.uid();
BEGIN
  SELECT * INTO v_row FROM public.couple_events WHERE id = p_event_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND OR v_row.status <> 'proposed' OR v_row.proposed_to IS DISTINCT FROM v_me THEN
    PERFORM public.together_fail('not_found');
  END IF;
  PERFORM public.together_actor(v_row.relationship_id);
  IF v_row.proposal_expires_at <= now() THEN PERFORM public.together_fail('expired'); END IF;
  IF p_accept THEN
    SELECT * INTO v_opt FROM public.couple_event_options WHERE id = p_option_id AND event_id = v_row.id;
    IF NOT FOUND THEN PERFORM public.together_fail('invalid_input'); END IF;
    UPDATE public.couple_events SET
      start_date = v_opt.start_date, end_date = v_opt.end_date,
      starts_at = v_opt.starts_at, ends_at = v_opt.ends_at,
      status = 'confirmed', decided_at = now()
    WHERE id = v_row.id RETURNING * INTO v_row;
    PERFORM public.together_push(v_row.created_by, 'together_proposal_reply',
      public.together_name(v_me) || ' said yes', v_row.title, v_row, 'together_reply:' || v_row.id);
  ELSE
    IF p_note IS NOT NULL AND char_length(p_note) > 200 THEN PERFORM public.together_fail('invalid_input'); END IF;
    UPDATE public.couple_events SET status = 'cancelled', decided_at = now(),
      decision_note = nullif(btrim(p_note), '')
    WHERE id = v_row.id RETURNING * INTO v_row;
    PERFORM public.together_push(v_row.created_by, 'together_proposal_reply',
      public.together_name(v_me) || ' can''t make it', v_row.title, v_row, 'together_reply:' || v_row.id);
  END IF;
END;
$$;

CREATE FUNCTION public.propose_owner_handoff(p_event_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row public.couple_events := public.together_editable_event(p_event_id);
        v_me uuid := auth.uid(); v_partner uuid;
BEGIN
  v_partner := public.together_partner(v_row.relationship_id, v_me);
  IF v_row.visibility <> 'shared' OR v_partner IS NULL OR v_row.status <> 'confirmed' THEN
    PERFORM public.together_fail('invalid_input');
  END IF;
  UPDATE public.couple_events SET owner_proposed_to = v_partner, owner_proposed_at = now()
  WHERE id = v_row.id RETURNING * INTO v_row;
  PERFORM public.together_push(v_partner, 'together_handoff',
    public.together_name(v_me) || ' asked you to take this on', v_row.title, v_row,
    'together_handoff:' || v_row.id || ':' || extract(epoch FROM v_row.owner_proposed_at)::bigint);
END;
$$;

CREATE FUNCTION public.decide_owner_handoff(p_event_id uuid, p_accept boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row public.couple_events; v_me uuid := auth.uid(); v_asker uuid;
BEGIN
  SELECT * INTO v_row FROM public.couple_events WHERE id = p_event_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND OR v_row.owner_proposed_to IS DISTINCT FROM v_me THEN PERFORM public.together_fail('not_found'); END IF;
  PERFORM public.together_actor(v_row.relationship_id);
  v_asker := public.together_partner(v_row.relationship_id, v_me);
  UPDATE public.couple_events SET
    owner_id = CASE WHEN p_accept THEN v_me ELSE owner_id END,
    owner_proposed_to = NULL, owner_proposed_at = NULL
  WHERE id = v_row.id RETURNING * INTO v_row;
  PERFORM public.together_push(v_asker, 'together_handoff_reply',
    CASE WHEN p_accept THEN public.together_name(v_me) || ' is taking care of it'
         ELSE public.together_name(v_me) || ' can''t take it on' END,
    v_row.title, v_row, 'together_handoff_reply:' || v_row.id || ':' || extract(epoch FROM now())::bigint);
END;
$$;

CREATE FUNCTION public.list_together_needs_you(p_relationship_id uuid)
RETURNS TABLE (need_kind text, item_id uuid, title text, due_date date, created_by uuid, detail jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := public.together_actor(p_relationship_id);
  v_today date := (now() AT TIME ZONE coalesce(
    (SELECT s.timezone FROM public.planning_member_settings s
     WHERE s.relationship_id = p_relationship_id AND s.user_id = v_me), 'UTC'))::date;
BEGIN
  RETURN QUERY
  SELECT CASE WHEN ce.proposed_to = v_me THEN 'proposal' ELSE 'sent_proposal' END,
    ce.id, ce.title, NULL::date, ce.created_by,
    jsonb_build_object(
      'all_day', ce.all_day, 'tz', ce.tz, 'note', ce.note,
      'proposed_to', ce.proposed_to, 'expires_at', ce.proposal_expires_at,
      'options', (SELECT coalesce(jsonb_agg(jsonb_build_object(
          'id', o.id, 'position', o.position, 'start_date', o.start_date, 'end_date', o.end_date,
          'starts_at', o.starts_at, 'ends_at', o.ends_at) ORDER BY o.position), '[]'::jsonb)
        FROM public.couple_event_options o WHERE o.event_id = ce.id))
  FROM public.couple_events ce
  WHERE ce.relationship_id = p_relationship_id AND ce.deleted_at IS NULL
    AND ce.status = 'proposed' AND ce.proposal_expires_at > now()
    AND (ce.proposed_to = v_me OR ce.created_by = v_me)

  UNION ALL
  SELECT 'handoff'::text, ce.id, ce.title, ce.start_date, ce.created_by,
    jsonb_build_object('kind', ce.kind, 'starts_at', ce.starts_at, 'all_day', ce.all_day)
  FROM public.couple_events ce
  WHERE ce.relationship_id = p_relationship_id AND ce.deleted_at IS NULL
    AND ce.owner_proposed_to = v_me

  UNION ALL
  SELECT 'unowned_todo'::text, i.id, coalesce(i.text, ''), i.due_date, NULL::uuid,
    jsonb_build_object('entry_id', e.id, 'entry_title', e.title)
  FROM public.planning_block_items i
  JOIN public.planning_blocks b ON b.id = i.block_id
  JOIN public.planning_entries e ON e.id = b.entry_id
  WHERE i.relationship_id = p_relationship_id AND i.deleted_at IS NULL
    AND i.checked_at IS NULL AND i.assigned_to IS NULL
    AND i.due_date BETWEEN v_today AND v_today + 7
    AND b.deleted_at IS NULL AND b.block_type = 'checklist'
    AND e.deleted_at IS NULL AND NOT e.is_template

  UNION ALL
  SELECT 'poll'::text, b.id, e.title, NULL::date, NULL::uuid,
    jsonb_build_object('entry_id', e.id)
  FROM public.planning_blocks b
  JOIN public.planning_entries e ON e.id = b.entry_id
  WHERE b.relationship_id = p_relationship_id AND b.block_type = 'date_poll'
    AND b.deleted_at IS NULL AND e.deleted_at IS NULL AND NOT e.is_template
    AND EXISTS (SELECT 1 FROM public.planning_block_items i
                WHERE i.block_id = b.id AND i.deleted_at IS NULL)
    AND NOT EXISTS (SELECT 1 FROM public.planning_block_items i
                    JOIN public.planning_poll_votes v ON v.item_id = i.id
                    WHERE i.block_id = b.id AND v.user_id = v_me);
END;
$$;

REVOKE ALL ON FUNCTION public.propose_couple_event(uuid, jsonb, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decide_couple_event(uuid, uuid, boolean, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.propose_owner_handoff(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decide_owner_handoff(uuid, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_together_needs_you(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.propose_couple_event(uuid, jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decide_couple_event(uuid, uuid, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.propose_owner_handoff(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decide_owner_handoff(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_together_needs_you(uuid) TO authenticated;
```

Before running, check whether Planning's real `planning_blocks` checklist type is spelled `'checklist'`: run `grep -n "'checklist'" supabase/migrations/20261012200000_planning_v2_schema.sql`.

- [ ] **Step 6: Verify.** Run `scratchpad/pg/run.sh supabase/tests/together_events_contracts.sql supabase/tests/together_proposals_contracts.sql supabase/tests/together_phase0_contracts.sql` → all PASS.

---

### Task 2: Dart models and repository

**Files:**
- Create: `lib/features/together/domain/together_need.dart`
- Modify: `lib/features/together/data/together_repository.dart`
- Modify: `lib/features/together/presentation/together_providers.dart`
- Test: `test/features/together/together_need_test.dart`, plus additions to `test/features/together/together_repository_test.dart`

**Interfaces:**
- Produces:
  - `enum TogetherNeedKind { proposal, sentProposal, handoff, unownedTodo, poll }`;
  - `class TogetherOption { id, position, allDay, start (DateTime local), end (DateTime?) }`, with `factory fromJson`;
  - `class TogetherNeed { kind, itemId, title, dueDate?, createdBy?, options, expiresAt?, entryId?, proposedTo? }`, with `factory fromRow`;
  - `class ProposalTime { start, end? }` with `Map<String, dynamic> toJson({required bool allDay})`, producing `start_date`/`end_date` (`YYYY-MM-DD`) or `starts_at`/`ends_at` (UTC ISO);
  - Repository:
    - `proposeEvent(String relationshipId, CoupleEventDraft draft, List<ProposalTime> times)` → `Future<String>`;
    - `decideProposal(String eventId, {String? optionId, required bool accept, String? note})`;
    - `proposeHandoff(String eventId)`;
    - `decideHandoff(String eventId, {required bool accept})`;
    - `listNeeds(String relationshipId)` → `Future<List<TogetherNeed>>`;
  - `togetherNeedsProvider` (`FutureProvider.autoDispose.family<List<TogetherNeed>, String>`), which refetches on the Together and Planning signals.

- [ ] **Step 1: Write the failing tests**

`test/features/together/together_need_test.dart`:

```dart
import 'package:attune/features/together/domain/together_need.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a proposal row carries its options in local time', () {
    final n = TogetherNeed.fromRow({
      'need_kind': 'proposal', 'item_id': 'e1', 'title': 'Dinner', 'due_date': null,
      'created_by': 'ama',
      'detail': {
        'all_day': false, 'tz': 'Africa/Accra', 'proposed_to': 'kofi',
        'expires_at': '2026-11-09T10:00:00+00:00',
        'options': [
          {'id': 'o1', 'position': 1, 'start_date': null, 'end_date': null,
           'starts_at': '2026-11-06T19:00:00+00:00', 'ends_at': '2026-11-06T21:00:00+00:00'},
          {'id': 'o2', 'position': 2, 'start_date': null, 'end_date': null,
           'starts_at': '2026-11-07T19:00:00+00:00', 'ends_at': null},
        ],
      },
    });
    expect(n.kind, TogetherNeedKind.proposal);
    expect(n.options.map((o) => o.id), ['o1', 'o2']);
    expect(n.options.first.start, DateTime.utc(2026, 11, 6, 19).toLocal());
    expect(n.options.last.end, isNull);
    expect(n.expiresAt, DateTime.utc(2026, 11, 9, 10).toLocal());
  });

  test('to-dos and polls point at their plan', () {
    final todo = TogetherNeed.fromRow({
      'need_kind': 'unowned_todo', 'item_id': 'i1', 'title': 'Book camp', 'due_date': '2026-11-05',
      'created_by': null, 'detail': {'entry_id': 'p1', 'entry_title': 'Summer'},
    });
    expect(todo.kind, TogetherNeedKind.unownedTodo);
    expect(todo.dueDate, DateTime(2026, 11, 5));
    expect(todo.entryId, 'p1');
    expect(TogetherNeed.fromRow({'need_kind': 'poll', 'item_id': 'b1', 'title': 'Lisbon', 'due_date': null,
      'created_by': null, 'detail': {'entry_id': 'p2'}}).kind, TogetherNeedKind.poll);
  });

  test('ProposalTime serialises like the server expects', () {
    expect(ProposalTime(start: DateTime(2026, 11, 14), end: DateTime(2026, 11, 15)).toJson(allDay: true),
        {'start_date': '2026-11-14', 'end_date': '2026-11-15'});
    expect(ProposalTime(start: DateTime(2026, 11, 6, 19)).toJson(allDay: false),
        {'starts_at': DateTime(2026, 11, 6, 19).toUtc().toIso8601String()});
  });
}
```

Append to `together_repository_test.dart`:

```dart
  test('proposals, decisions and hand-offs call their RPCs', () async {
    final g = FakeTogetherGateway({
      'propose_couple_event': (_) => 'ev-9',
      'decide_couple_event': (_) => null,
      'propose_owner_handoff': (_) => null,
      'decide_owner_handoff': (_) => null,
      'list_together_needs_you': (_) => [
        {'need_kind': 'handoff', 'item_id': 'e1', 'title': 'Plumber', 'due_date': '2026-11-10',
         'created_by': 'ama', 'detail': {'kind': 'event'}},
      ],
    });
    final repo = TogetherRepository(g);
    final draft = CoupleEventDraft(title: 'Dinner', allDay: false, start: DateTime(2026, 11, 6, 19),
        timezone: 'UTC', participantIds: const ['ama', 'kofi']);
    expect(await repo.proposeEvent('r1', draft, [ProposalTime(start: DateTime(2026, 11, 6, 19))]), 'ev-9');
    expect((g.calls.last.$2['p_options'] as List).single, contains('starts_at'));
    await repo.decideProposal('ev-9', optionId: 'o1', accept: true);
    expect(g.calls.last.$2, {'p_event_id': 'ev-9', 'p_option_id': 'o1', 'p_accept': true, 'p_note': null});
    await repo.proposeHandoff('e1');
    await repo.decideHandoff('e1', accept: false);
    expect(g.calls.last.$2, {'p_event_id': 'e1', 'p_accept': false});
    expect((await repo.listNeeds('r1')).single.kind, TogetherNeedKind.handoff);
  });
```

Add `import 'package:attune/features/together/domain/together_need.dart';` to that file.

- [ ] **Step 2: Run them to verify they fail.**

- [ ] **Step 3: Implement**

`lib/features/together/domain/together_need.dart`:

```dart
/// Something on Together waiting on me (or my proposal waiting on my
/// partner), from `list_together_needs_you`.
library;

enum TogetherNeedKind { proposal, sentProposal, handoff, unownedTodo, poll }

const _kinds = {
  'proposal': TogetherNeedKind.proposal,
  'sent_proposal': TogetherNeedKind.sentProposal,
  'handoff': TogetherNeedKind.handoff,
  'unowned_todo': TogetherNeedKind.unownedTodo,
  'poll': TogetherNeedKind.poll,
};

DateTime? _local(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

DateTime? _day(Object? v) {
  if (v == null) return null;
  final p = DateTime.parse(v as String);
  return DateTime(p.year, p.month, p.day);
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// One time a proposal offers.
class TogetherOption {
  const TogetherOption({
    required this.id,
    required this.position,
    required this.allDay,
    required this.start,
    this.end,
  });

  factory TogetherOption.fromJson(Map<String, dynamic> j, {required bool allDay}) =>
      TogetherOption(
        id: j['id'] as String,
        position: (j['position'] as num).toInt(),
        allDay: allDay,
        start: allDay ? _day(j['start_date'])! : _local(j['starts_at'])!,
        end: allDay ? _day(j['end_date']) : _local(j['ends_at']),
      );

  final String id;
  final int position;
  final bool allDay;
  final DateTime start;
  final DateTime? end;
}

/// A time to offer when proposing.
class ProposalTime {
  const ProposalTime({required this.start, this.end});
  final DateTime start;
  final DateTime? end;

  Map<String, dynamic> toJson({required bool allDay}) => allDay
      ? {'start_date': _ymd(start), if (end != null) 'end_date': _ymd(end!)}
      : {
          'starts_at': start.toUtc().toIso8601String(),
          if (end != null) 'ends_at': end!.toUtc().toIso8601String(),
        };
}

class TogetherNeed {
  const TogetherNeed({
    required this.kind,
    required this.itemId,
    required this.title,
    this.dueDate,
    this.createdBy,
    this.options = const [],
    this.expiresAt,
    this.entryId,
    this.proposedTo,
    this.allDay = false,
  });

  factory TogetherNeed.fromRow(Map<String, dynamic> r) {
    final d = Map<String, dynamic>.from(r['detail'] as Map? ?? const {});
    final allDay = d['all_day'] as bool? ?? false;
    return TogetherNeed(
      kind: _kinds[r['need_kind']] ?? TogetherNeedKind.poll,
      itemId: r['item_id'] as String,
      title: r['title'] as String? ?? '',
      dueDate: _day(r['due_date']),
      createdBy: r['created_by'] as String?,
      options: [
        for (final o in (d['options'] as List? ?? const []))
          TogetherOption.fromJson(Map<String, dynamic>.from(o as Map), allDay: allDay),
      ],
      expiresAt: _local(d['expires_at']),
      entryId: d['entry_id'] as String?,
      proposedTo: d['proposed_to'] as String?,
      allDay: allDay,
    );
  }

  final TogetherNeedKind kind;
  final String itemId;
  final String title;
  final DateTime? dueDate;
  final String? createdBy;
  final List<TogetherOption> options;
  final DateTime? expiresAt;
  final String? entryId;
  final String? proposedTo;
  final bool allDay;
}
```

In `together_repository.dart`, add `import '../domain/together_need.dart';` and these methods:

```dart
  Future<String> proposeEvent(
    String relationshipId,
    CoupleEventDraft draft,
    List<ProposalTime> times,
  ) async =>
      await _call('propose_couple_event', {
        'p_relationship_id': relationshipId,
        'p_event': draft.toPayload(),
        'p_options': [for (final t in times) t.toJson(allDay: draft.allDay)],
      }) as String;

  Future<void> decideProposal(String eventId, {String? optionId, required bool accept, String? note}) =>
      _call('decide_couple_event', {
        'p_event_id': eventId,
        'p_option_id': optionId,
        'p_accept': accept,
        'p_note': note,
      });

  Future<void> proposeHandoff(String eventId) =>
      _call('propose_owner_handoff', {'p_event_id': eventId});

  Future<void> decideHandoff(String eventId, {required bool accept}) =>
      _call('decide_owner_handoff', {'p_event_id': eventId, 'p_accept': accept});

  Future<List<TogetherNeed>> listNeeds(String relationshipId) async {
    final rows = await _call('list_together_needs_you', {'p_relationship_id': relationshipId}) as List;
    return [for (final r in rows) TogetherNeed.fromRow(Map<String, dynamic>.from(r as Map))];
  }
```

In `together_providers.dart`, add `import '../domain/together_need.dart';` and:

```dart
/// What's waiting on me (and my proposals waiting on my partner).
final togetherNeedsProvider = FutureProvider.autoDispose
    .family<List<TogetherNeed>, String>((ref, relationshipId) {
      ref.listen(togetherChangeSignalProvider(relationshipId), (_, __) => ref.invalidateSelf());
      ref.listen(planningChangeSignalProvider(relationshipId), (_, __) => ref.invalidateSelf());
      return ref.watch(togetherRepositoryProvider).listNeeds(relationshipId);
    });
```

- [ ] **Step 4: Run tests**: `flutter test test/features/together/` → pass.

---

### Task 3: The decide sheet and the hand-off sheet

**Files:**
- Create: `lib/features/together/presentation/widgets/together_need_sheets.dart`
- Test: `test/features/together/together_need_sheets_test.dart`

**Interfaces:**
- Produces:
  - `Future<void> showProposalSheet(BuildContext context, TogetherNeed need)`. The recipient picks a time to accept, or declines with an optional note.
  - `Future<void> showSentProposalSheet(BuildContext context, TogetherNeed need)`. The sender sees "No reply yet" and can withdraw, which calls `deleteEvent`.
  - `Future<void> showHandoffSheet(BuildContext context, TogetherNeed need)`. Take it on, or not now.
  - Each pops with a message that the host shows, and invalidates `togetherNeedsProvider` and `togetherRangeProvider`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart' as quiz;
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/domain/together_need.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/together_need_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'together_repository_test.dart' show FakeTogetherGateway;

final _proposal = TogetherNeed.fromRow({
  'need_kind': 'proposal', 'item_id': 'e1', 'title': 'Dinner at Buka', 'due_date': null, 'created_by': 'kofi',
  'detail': {'all_day': true, 'proposed_to': 'ama', 'expires_at': '2026-11-09T10:00:00+00:00', 'options': [
    {'id': 'o1', 'position': 1, 'start_date': '2026-11-06', 'end_date': null, 'starts_at': null, 'ends_at': null},
    {'id': 'o2', 'position': 2, 'start_date': '2026-11-07', 'end_date': null, 'starts_at': null, 'ends_at': null},
  ]},
});

Future<FakeTogetherGateway> _host(WidgetTester t, Future<void> Function(BuildContext) open) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final g = FakeTogetherGateway({
    'decide_couple_event': (_) => null,
    'decide_owner_handoff': (_) => null,
    'delete_couple_event': (_) => null,
  });
  await t.pumpWidget(ProviderScope(
    overrides: [
      togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
      quiz.partnerNameProvider.overrideWith((ref) async => 'Kofi'),
    ],
    child: ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(home: Scaffold(body: Builder(
        builder: (c) => TextButton(onPressed: () => open(c), child: const Text('open')),
      ))),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return g;
}

void main() {
  testWidgets('accepting needs a chosen time, then confirms it', (t) async {
    final g = await _host(t, (c) => showProposalSheet(c, _proposal));
    expect(find.text('Kofi suggested'), findsOneWidget);
    await t.tap(find.text('Accept'));
    await t.pumpAndSettle();
    expect(g.calls, isEmpty, reason: 'nothing chosen yet');
    await t.tap(find.textContaining('Sat'));
    await t.tap(find.text('Accept'));
    await t.pumpAndSettle();
    expect(g.calls.single.$2, {'p_event_id': 'e1', 'p_option_id': 'o2', 'p_accept': true, 'p_note': null});
    expect(find.text('Added to Together.'), findsOneWidget);
  });

  testWidgets("can't make any: declines with an optional note", (t) async {
    final g = await _host(t, (c) => showProposalSheet(c, _proposal));
    await t.enterText(find.byType(TextField), 'Working late');
    await t.tap(find.text("Can't make these"));
    await t.pumpAndSettle();
    expect(g.calls.single.$2, {'p_event_id': 'e1', 'p_option_id': null, 'p_accept': false, 'p_note': 'Working late'});
  });

  testWidgets('a hand-off can be taken on', (t) async {
    final handoff = TogetherNeed.fromRow({'need_kind': 'handoff', 'item_id': 'e2', 'title': 'Book the plumber',
      'due_date': '2026-11-10', 'created_by': 'kofi', 'detail': {'kind': 'event'}});
    final g = await _host(t, (c) => showHandoffSheet(c, handoff));
    expect(find.text('Book the plumber'), findsOneWidget);
    await t.tap(find.text("I'll take it"));
    await t.pumpAndSettle();
    expect(g.calls.single.$2, {'p_event_id': 'e2', 'p_accept': true});
  });

  testWidgets('my own proposal says no reply yet and can be withdrawn', (t) async {
    final sent = TogetherNeed.fromRow({'need_kind': 'sent_proposal', 'item_id': 'e3', 'title': 'Hike',
      'due_date': null, 'created_by': 'ama', 'detail': {'all_day': true, 'proposed_to': 'kofi',
      'expires_at': '2026-11-09T10:00:00+00:00', 'options': []}});
    final g = await _host(t, (c) => showSentProposalSheet(c, sent));
    expect(find.text('No reply yet'), findsOneWidget);
    await t.tap(find.text('Withdraw'));
    await t.pumpAndSettle();
    expect(g.calls.single.$1, 'delete_couple_event');
  });
}
```

- [ ] **Step 2: Run it to verify it fails.**

- [ ] **Step 3: Implement** `together_need_sheets.dart`:

```dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz_providers;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/together_repository.dart';
import '../../domain/together_need.dart';
import '../together_providers.dart';

String togetherOptionLabel(TogetherOption o) {
  if (o.allDay) {
    final s = DateFormat.MMMEd().format(o.start);
    return o.end == null || o.end == o.start ? s : '$s – ${DateFormat.MMMEd().format(o.end!)}';
  }
  final s = DateFormat.MMMEd().add_jm().format(o.start);
  return o.end == null ? s : '$s – ${DateFormat.jm().format(o.end!)}';
}

Future<void> _sheet(BuildContext context, Widget child) async {
  final message = await BottomSheetUtils.showDocumentationBottomSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.neutral,
    widget: child,
  );
  if (message != null && context.mounted) context.showSuccessSnackbar(message);
}

Future<void> showProposalSheet(BuildContext context, TogetherNeed need) =>
    _sheet(context, _ProposalSheet(need: need));

Future<void> showSentProposalSheet(BuildContext context, TogetherNeed need) =>
    _sheet(context, _SentProposalSheet(need: need));

Future<void> showHandoffSheet(BuildContext context, TogetherNeed need) =>
    _sheet(context, _HandoffSheet(need: need));

/// Runs a decision, refreshes Together, and closes with [done].
Future<void> _decide(BuildContext context, WidgetRef ref, Future<void> Function(TogetherRepository) action,
    String done) async {
  try {
    await action(ref.read(togetherRepositoryProvider));
    ref.invalidate(togetherNeedsProvider);
    ref.invalidate(togetherRangeProvider);
    if (context.mounted) Navigator.of(context).pop(done);
  } on TogetherException catch (e) {
    if (!context.mounted) return;
    context.showErrorSnackbar(e.code == 'expired'
        ? 'This suggestion has expired.'
        : 'Could not do that. Please try again.');
  } catch (_) {
    if (context.mounted) context.showErrorSnackbar('Could not do that. Please try again.');
  }
}

class _ProposalSheet extends ConsumerStatefulWidget {
  const _ProposalSheet({required this.need});
  final TogetherNeed need;
  @override
  ConsumerState<_ProposalSheet> createState() => _ProposalSheetState();
}

class _ProposalSheetState extends ConsumerState<_ProposalSheet> {
  String? _chosen;
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(TogetherRepository) action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    await _decide(context, ref, action, done);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final partner = ref.watch(quiz_providers.partnerNameProvider).valueOrNull ?? 'Your partner';
    final need = widget.need;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        children: [
          BottomSheetHeader(
            title: '$partner suggested',
            actionLabel: 'Accept',
            onPressed: _busy
                ? null
                : () {
                    final id = _chosen;
                    if (id == null) {
                      context.showErrorSnackbar('Pick a time first');
                      return;
                    }
                    _run((r) => r.decideProposal(need.itemId, optionId: id, accept: true), 'Added to Together.');
                  },
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
            child: Text(need.title, style: Theme.of(context).textTheme.titleMedium),
          ),
          Gap(Spacing.sm),
          for (final o in need.options)
            RadioListTile<String>(
              value: o.id,
              groupValue: _chosen,
              title: Text(togetherOptionLabel(o)),
              onChanged: (v) => setState(() => _chosen = v),
            ),
          AppDivider(),
          AppTextFormField(controller: _note, label: 'Add a note (optional)', maxLength: 200),
          InfoRowWidget(
            title: "Can't make these",
            subtitle: '',
            icon: Icons.event_busy_outlined,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
            onTap: _busy
                ? null
                : () => _run(
                      (r) => r.decideProposal(need.itemId,
                          accept: false, note: _note.text.trim().isEmpty ? null : _note.text.trim()),
                      'Sent.',
                    ),
          ),
          Gap(Spacing.xl),
        ],
      ),
    );
  }
}

class _SentProposalSheet extends ConsumerWidget {
  const _SentProposalSheet({required this.need});
  final TogetherNeed need;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(quiz_providers.partnerNameProvider).valueOrNull ?? 'your partner';
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        children: [
          BottomSheetHeader(title: need.title),
          InfoRowWidget(
            title: 'No reply yet',
            subtitle: 'Waiting for $partner',
            icon: Icons.hourglass_empty_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
          ),
          AppDivider(),
          InfoRowWidget(
            title: 'Withdraw',
            subtitle: '',
            icon: Icons.undo_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
            onTap: () => _decide(context, ref, (r) => r.deleteEvent(need.itemId), 'Withdrawn.'),
          ),
          Gap(Spacing.xl),
        ],
      ),
    );
  }
}

class _HandoffSheet extends ConsumerWidget {
  const _HandoffSheet({required this.need});
  final TogetherNeed need;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(quiz_providers.partnerNameProvider).valueOrNull ?? 'Your partner';
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        children: [
          BottomSheetHeader(title: '$partner asked you to take this on'),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
            child: Text(need.title, style: Theme.of(context).textTheme.titleMedium),
          ),
          Gap(Spacing.md),
          AppDivider(),
          InfoRowWidget(
            title: "I'll take it",
            subtitle: '',
            icon: Icons.check_circle_outline_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
            onTap: () => _decide(context, ref, (r) => r.decideHandoff(need.itemId, accept: true), "It's yours."),
          ),
          AppDivider(),
          InfoRowWidget(
            title: 'Not now',
            subtitle: '',
            icon: Icons.close_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
            onTap: () => _decide(context, ref, (r) => r.decideHandoff(need.itemId, accept: false), 'Sent.'),
          ),
          Gap(Spacing.xl),
        ],
      ),
    );
  }
}
```

If `RadioListTile`'s `groupValue`/`onChanged` show a deprecation info on this Flutter version (3.29), that's acceptable; keep it consistent with the codebase.

- [ ] **Step 4: Run tests**: `flutter test test/features/together/together_need_sheets_test.dart` → pass.

---

### Task 4: "Needs you" on the Agenda

**Files:**
- Modify: `lib/features/together/presentation/screens/together_screen.dart`
- Test: additions to `test/features/together/together_screen_test.dart`

- [ ] **Step 1: Write the failing tests.** In `together_screen_test.dart`, extend the fake gateway in `_pump` with a `'list_together_needs_you': (_) => needs` handler, where `needs` is a new named parameter defaulting to `const []`. Then append:

```dart
  testWidgets('needs you sits on top and opens the right sheet', (t) async {
    await _pump(t, upcoming: [_row('rent', '2026-11-02', title: 'Rent')], needs: [
      {'need_kind': 'proposal', 'item_id': 'e1', 'title': 'Dinner at Buka', 'due_date': null, 'created_by': 'kofi',
       'detail': {'all_day': true, 'proposed_to': 'ama', 'expires_at': '2026-11-09T10:00:00+00:00', 'options': [
         {'id': 'o1', 'position': 1, 'start_date': '2026-11-06', 'end_date': null, 'starts_at': null, 'ends_at': null}]}},
    ]);
    expect(find.text('Needs you'), findsOneWidget);
    expect(find.text('Dinner at Buka'), findsOneWidget);
    await t.tap(find.text('Dinner at Buka'));
    await t.pumpAndSettle();
    expect(find.text('Kofi suggested'), findsOneWidget);
  });

  testWidgets('needs you shows three and a More row, never a count of misses', (t) async {
    Map<String, dynamic> todo(int i) => {'need_kind': 'unowned_todo', 'item_id': 't$i', 'title': 'Task $i',
      'due_date': '2026-11-0${i + 2}', 'created_by': null, 'detail': {'entry_id': 'p1'}};
    await _pump(t, needs: [for (var i = 1; i <= 5; i++) todo(i)]);
    expect(find.text('Task 1'), findsOneWidget);
    expect(find.text('Task 3'), findsOneWidget);
    expect(find.text('Task 4'), findsNothing);
    expect(find.text('More'), findsOneWidget);
  });

  testWidgets('with nothing waiting, there is no Needs you section', (t) async {
    await _pump(t, upcoming: [_row('rent', '2026-11-02', title: 'Rent')]);
    expect(find.text('Needs you'), findsNothing);
  });
```

Also `_pump`'s empty-state test now needs needs `[]`, which is the default.

- [ ] **Step 2: Run them to verify they fail.**

- [ ] **Step 3: Implement.** In `together_screen.dart`:
  - Import `together_need.dart` and `together_need_sheets.dart`.
  - Inside `_agenda`, watch `togetherNeedsProvider(relationshipId)`: `final needs = ref.watch(togetherNeedsProvider(relationshipId)).valueOrNull ?? const <TogetherNeed>[];`.
  - Treat the agenda as empty only when `agenda.isEmpty && needs.isEmpty`.
  - Insert this as the first child of the non-empty list, before Today:

```dart
                  if (needs.isNotEmpty)
                    TogetherSection(
                      title: 'Needs you',
                      children: [
                        for (var i = 0; i < needs.length && i < 3; i++)
                          _needRow(needs[i], relationshipId, partnerName,
                              last: needs.length <= 3 && i == needs.length - 1),
                        if (needs.length > 3)
                          InfoRowWidget(
                            title: 'More',
                            subtitle: '',
                            icon: Icons.expand_more_rounded,
                            showAvatar: false,
                            showDivider: false,
                            showTrailingArrow: true,
                            onTap: () => _showAllNeeds(needs, relationshipId, partnerName),
                          ),
                      ],
                    ),
```

Add to the state class:

```dart
  Widget _needRow(TogetherNeed n, String relationshipId, String partnerName, {bool last = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, subtitle) = switch (n.kind) {
      TogetherNeedKind.proposal => (Icons.how_to_vote_outlined, '$partnerName suggested · pick a time'),
      TogetherNeedKind.sentProposal => (Icons.hourglass_empty_rounded, 'No reply yet'),
      TogetherNeedKind.handoff => (Icons.front_hand_outlined, '$partnerName asked you to take this on'),
      TogetherNeedKind.unownedTodo => (
          Icons.check_box_outline_blank_rounded,
          n.dueDate == null ? 'Nobody has this yet' : 'Nobody has this yet · due ${DateFormat.MMMEd().format(n.dueDate!)}',
        ),
      TogetherNeedKind.poll => (Icons.date_range_outlined, 'Pick the dates that work for you'),
    };
    return InfoRowWidget(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.xs),
      icon: icon,
      iconColor: colorScheme.primary,
      backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
      title: n.title.isEmpty ? 'Untitled' : n.title,
      subtitle: subtitle,
      titleMaxLines: 1,
      subTitleMaxLines: 1,
      showDivider: !last,
      disableTrailing: true,
      onTap: () => _openNeed(n, relationshipId),
    );
  }

  void _openNeed(TogetherNeed n, String relationshipId) {
    switch (n.kind) {
      case TogetherNeedKind.proposal:
        showProposalSheet(context, n);
      case TogetherNeedKind.sentProposal:
        showSentProposalSheet(context, n);
      case TogetherNeedKind.handoff:
        showHandoffSheet(context, n);
      case TogetherNeedKind.unownedTodo:
      case TogetherNeedKind.poll:
        final entryId = n.entryId;
        if (entryId == null) return;
        Navigator.of(context).push(planningRoute(
          PlanningEntryScreen(relationshipId: relationshipId, entryId: entryId),
        ));
    }
  }

  void _showAllNeeds(List<TogetherNeed> needs, String relationshipId, String partnerName) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (var i = 0; i < needs.length; i++)
              _needRow(needs[i], relationshipId, partnerName, last: i == needs.length - 1),
          ],
        ),
      ),
    );
  }
```

Use `_needRow`'s own `context` (the screen's) for navigation. Rows inside the modal also open sheets from the screen context, which is intended.

- [ ] **Step 4: Run tests**: `flutter test test/features/together/` → pass.

---

### Task 5: Propose mode and "Who's holding it" in the editor

**Files:**
- Modify: `lib/features/together/presentation/widgets/couple_event_sheet.dart`
- Test: additions to `test/features/together/couple_event_sheet_test.dart`

**Behaviour:**
- **New shared events with the partner included** show a toggle, "Ask {partner} to pick". When it's on:
  - a list of up to three times appears, with "Add another time"; the first time is the editor's start and end;
  - Save calls `proposeEvent` and closes with "Sent to {partner}.";
  - Repeats is disabled.
- **Who's holding it** has three choices: Nobody, Me, {partner}.
  - Choosing {partner} doesn't set `owner_id`. After a successful create or update, the editor calls `proposeHandoff`.
  - Me and Nobody save directly. For an existing event whose owner is the partner, the choice shows {partner} and saving keeps their ownership.

- [ ] **Step 1: Write the failing tests** (append):

```dart
  testWidgets('asking my partner to pick sends a proposal with the chosen times', (t) async {
    final g = await _open(t);
    g.handlers['propose_couple_event'] = (_) => 'ev-p';
    await t.enterText(find.byType(TextField).first, 'Dinner');
    await t.scrollUntilVisible(find.text('Ask Kofi to pick'), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Ask Kofi to pick'));
    await t.pumpAndSettle();
    await t.tap(find.text('Add another time'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    final call = g.calls.firstWhere((c) => c.$1 == 'propose_couple_event');
    expect((call.$2['p_options'] as List), hasLength(2));
    expect(find.text('Sent to Kofi.'), findsOneWidget);
  });

  testWidgets('asking my partner to hold it saves, then asks them', (t) async {
    final g = await _open(t);
    await t.enterText(find.byType(TextField).first, 'Book the plumber');
    await t.scrollUntilVisible(find.text("Who's holding it"), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.descendant(of: find.byKey(const Key('owner-picker')), matching: find.text('Kofi')));
    await t.pumpAndSettle();
    g.handlers['propose_owner_handoff'] = (_) => null;
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(g.calls.map((c) => c.$1), containsAllInOrder(['create_couple_event', 'propose_owner_handoff']));
    final payload = g.calls.firstWhere((c) => c.$1 == 'create_couple_event').$2['p_event'] as Map;
    expect(payload['owner_id'], isNull, reason: 'the partner is asked, never assigned');
  });
```

The owner `SegmentedButton` carries `Key('owner-picker')`; the test taps the partner's label inside it.

- [ ] **Step 2: Run them to verify they fail.**

- [ ] **Step 3: Implement.** In `_CoupleEventSheetState`:
  - **State:** add `bool _propose = false;`, `List<({DateTime start, DateTime? end})> _times = [];` and `String _holder = 'nobody';` (one of `'nobody' | 'me' | 'partner'`).
  - **`initState`, edit path:** after `_ownerId = d.ownerId;`, set `_holder = d.ownerId == null ? 'nobody' : (d.ownerId == ref.read(togetherMeProvider) ? 'me' : 'partner');`.
  - **Build:**
    - After the Who segmented control (shared and new events only), add a toggle row titled `'Ask $partnerName to pick'`, shown only when `widget.item == null && shared && _who != _Who.me`. Turning it on seeds `_times = [(start: _start, end: _end)]`.
    - When `_propose` is on, list each time as an `InfoRowWidget` that opens the picker for that time; reuse `_pick`'s pattern with an index. Add an "Add another time" row while `_times.length < 3`; it appends the last time plus one day. Disable the Repeats row.
    - After the visibility control, add a `labelLarge` label "Who's holding it" and a `SegmentedButton<String>(key: const Key('owner-picker'), …)` with Nobody / Me / partnerName, shown only when shared.
  - **`_save`:**
    - Build `ownerId` from `_holder`: `'me'` gives `me`; `'partner'` gives `widget.item?.ownerId` when the partner already owns it, otherwise `null`; `'nobody'` gives `null`.
    - When `_propose` is on, call `repo.proposeEvent(widget.relationshipId, draft, [for (final t in _times) ProposalTime(start: t.start, end: t.end)])` and pop `'Sent to $partnerName.'`.
    - Otherwise create or update as now, keeping the new id from `createEvent`. Then, if `_holder == 'partner'` and the partner isn't already the owner, call `repo.proposeHandoff(id)`.
    - Always `ref.invalidate(togetherNeedsProvider)` as well as `togetherRangeProvider`.
  - **Imports:** `together_need.dart`.

- [ ] **Step 4: Run tests**: `flutter test test/features/together/` → pass.

---

### Task 6: Push taps, close-out

**Files:**
- Modify: `lib/core/notifications/config/notification_config.dart`
- Modify: `test/core/notifications/together_event_route_test.dart`

- [ ] **Step 1: Failing test.** Extend `together_event_route_test.dart` so each of `together_proposal`, `together_proposal_reply`, `together_handoff` and `together_handoff_reply` routes to `RouteNames.together`:

```dart
  for (final type in ['together_proposal', 'together_proposal_reply', 'together_handoff', 'together_handoff_reply']) {
    test("a '$type' tap opens Together", () {
      final source = File('lib/core/notifications/config/notification_config.dart').readAsStringSync();
      final at = source.indexOf("case '$type':");
      expect(at, isNot(-1), reason: type);
      expect(source.substring(at, source.indexOf('return;', at)), contains('RouteNames.together'));
    });
  }
```

- [ ] **Step 2: Implement.** Change `case 'together_event':` to fall through from the new cases:

```dart
        case 'together_event':
        case 'together_proposal':
        case 'together_proposal_reply':
        case 'together_handoff':
        case 'together_handoff_reply':
          GoRouter.of(context).go(RouteNames.together);
          return;
```

The source test finds each case's text, then the next `return;`, which is shared, so all four pass.

- [ ] **Step 3: Spec.** Add "### 8.4 Phase 2a rulings" (R1–R7) under spec §8.
- [ ] **Step 4: Full verification.**
  - `flutter test` → no failures.
  - `flutter analyze lib/features/together lib/core/notifications` → clean.
  - `scratchpad/pg/run.sh supabase/tests/together_phase0_contracts.sql supabase/tests/together_events_contracts.sql supabase/tests/together_proposals_contracts.sql` → all PASS.
  - Golden preview of the Agenda with Needs you, and of the proposal sheet; inspect them, then delete the preview test.
- [ ] **Step 5: Report** the deploy steps: `supabase db push` now includes `20261014120000`, and `20261014110200` has changed.
