# Together Phase 1a — Couple events and the unified read: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Together its own events (timed or all-day, repeating, with participants, an owner, visibility and reminders) and one read RPC that returns everything for a date range. That range covers events, moments, reminders and Planning dates and to-dos, with visibility enforced on the server. A Dart model, repository and provider sit on top, ready for the Phase 1b screen.

**Architecture:** A new `couple_events` table that the client cannot read directly. All writes go through SECURITY DEFINER RPCs, and all reads go through `list_together_items`. That function expands recurrence on the server (a whitelisted RRULE subset), masks `busy_only` and drops `private` items for the partner, and combines the existing sources without moving them. A 15-minute cron function sends the event reminders a user asked for, through the existing `scheduled_notifications` pipeline. The Dart side mirrors Planning's testable RPC gateway pattern.

**Tech Stack:** Supabase Postgres 17 (plpgsql, pg_cron), Flutter/Riverpod 2, flutter_test, SQL contracts (`scripts/run_sql_contracts.sh`), Deno tests.

**Spec:** `docs/superpowers/specs/2026-10-14-together-hub-design.md` (§3 hard rules, §5 data model, §6.1 Plan together, §8 Phase 1). The base is Phase 0, uncommitted on main: `together_change_signals`, `togetherChangeSignalProvider`, `reminderDateString`.

## Global Constraints

- Work directly on `main`. Do not commit unless the owner asks. Re-read each file before editing it, because the owner edits by hand.
- Format only the files you touch, one at a time (`dart format <file>`). Never format whole folders.
- Migration filenames: `20261014110000` onwards, increasing by 100 per file.
- **Hard rules (spec §3):**
  - Nothing returns per-user counts.
  - No streak or counter columns.
  - Private events are visible only to their creator, everywhere.
  - `busy_only` shows the partner the title "Busy" and no note.
  - Conflict moments never notify the partner (untouched here).
- SQL contracts need Docker. If it is down, write them, record "written, not run (Docker down)", and never claim they passed.
- The full suite has one known pre-existing failure: `planning_home_screen_test.dart: shows visible categories…`.
- **Copy:** sentence case, plain words.

## Rulings (deviations from the spec, decided while planning)

- **R1:** `couple_events` gets no direct SELECT grant, even though spec §5.4 describes a SELECT policy. A direct read would expose a `busy_only` event's real title to the partner, which `list_together_items` masks. RLS is enabled and every privilege is revoked, so reads go only through the RPC. Cost if wrong: none; a policy can be added later.
- **R2:** `couple_event_options` and the proposal RPCs move to Phase 2, where the proposals UI lives. The table would sit unused in 1a. The `status`, `proposed_to` and `proposal_expires_at` columns ship now so Phase 2 needs no event-table migration. Cost if wrong: one migration in Phase 2.
- **R3:** The RRULE subset is `FREQ` plus `INTERVAL`, with `BYDAY` allowed for WEEKLY only. `COUNT` is dropped and "until" lives in the `recurrence_until` column. Repeating events are single-day. Cost if wrong: COUNT can be added later.
- **R4:** Monthly and yearly repeats on a day the target month lacks (the 31st, Feb 29) land on that month's last day. This matches reminders' Feb 29 → Feb 28 rule. Cost if wrong: a CASE change.
- **R5:** Family birthdays reach the read RPC through their `reminders` rows, which `upsert_family_member` already maintains, not by synthesising them from `couple_family_members`. Synthesising would show each birthday twice. Cost if wrong: none.
- **R6:** Event reminders the user sets ("remind me 1 hour before") are alarms the user asked for. They are outside D9's one-scheduled-push budget, which governs app-initiated pushes (digest, care cards, rituals). Their notification type is `together_event`. Cost if wrong: alarms would need folding into the digest in Phase 2.
- **R7:** In 1a an owner can only be yourself or the existing owner. Handing ownership to the partner is a proposal and arrives in Phase 2 (`together:owner_handoff`). Cost if wrong: none.
- **R8:** `TogetherItem` is one immutable class with a `kind` enum, not a sealed hierarchy. Every kind shares one row shape, so subclasses would add nothing. Cost if wrong: a refactor.
- **R9:** A private event's participants can only be its creator. A private event that includes the partner would contradict itself. Cost if wrong: none.

## Review Focus

1. **A weekly 19:00 Europe/London event across the 25 Oct 2026 DST change** must stay at 19:00 local, which moves its UTC time by an hour. Pinned in Task 2's contract.
2. **A "monthly on the 31st" event in a 30-day month and in February** must land on the last day, not vanish. Pinned in Task 2's contract (expansion is server-side only).
3. **The partner's view of a `busy_only` event** must show the title "Busy" and no note; **a `private` event** must not appear at all. Pinned in Task 2's contract.
4. **A range longer than 93 days, or with the end before the start,** must be rejected with `together:range`, not time out. Pinned in Task 2's contract.
5. **An alarm cron run repeated within its window** must not send a second push, and a private event's alarm must go to its creator only. Pinned in Task 3's contract.

---

## File structure

| File | Responsibility |
|---|---|
| `supabase/migrations/20261014110000_couple_events.sql` | Table, constraints, indexes, RLS, triggers (updated_at, Together signal) |
| `supabase/migrations/20261014110100_together_event_rpcs.sql` | Input type, `together_fail`, `together_actor`, validator, create/update/delete/leave |
| `supabase/migrations/20261014110200_list_together_items.sql` | `together_event_dates` (recurrence) and `list_together_items` |
| `supabase/migrations/20261014110300_together_event_alarms.sql` | `together_enqueue_event_alarms` and its cron job |
| `supabase/tests/together_events_contracts.sql` | Contracts for Tasks 1–3 |
| `supabase/functions/process-scheduled-notifications/index.ts` | Allow `event_id` in push data |
| `lib/core/notifications/config/notification_config.dart` | Route a `together_event` tap |
| `lib/features/together/domain/together_item.dart` | `TogetherItem`, its enums and row mapping |
| `lib/features/together/domain/couple_event_draft.dart` | `CoupleEventDraft`, RRULE builder, validation, payload |
| `lib/features/together/data/together_repository.dart` | Gateway, `TogetherException`, repository |
| `lib/features/together/presentation/together_providers.dart` | `togetherRepositoryProvider`, `togetherRangeProvider` |
| `test/features/together/*` | Dart tests |

---

### Task 1: `couple_events` table and write RPCs

**Files:**
- Create: `supabase/migrations/20261014110000_couple_events.sql`
- Create: `supabase/migrations/20261014110100_together_event_rpcs.sql`
- Create: `supabase/tests/together_events_contracts.sql` (sections 1–3)

**Interfaces:**
- Produces:
  - **Table:** `public.couple_events` (columns below).
  - **Type:** `public.together_event_input`.
  - **Write RPCs** (all `SECURITY DEFINER`, granted to authenticated):
    - `create_couple_event(p_relationship_id uuid, p_event jsonb) RETURNS uuid`;
    - `update_couple_event(p_event_id uuid, p_event jsonb) RETURNS void`;
    - `delete_couple_event(p_event_id uuid) RETURNS void`;
    - `leave_couple_event(p_event_id uuid) RETURNS void`.
  - **Errors:** raised as `P0001` with message `together:<code>`. The codes are `unauthenticated`, `not_found`, `invalid_input`, `owner_handoff`, `forbidden`, `range`.
  - **Payload JSON keys:** `kind`, `title`, `note`, `location_name`, `all_day`, `start_date` (`YYYY-MM-DD`), `end_date`, `starts_at` (ISO-8601 UTC), `ends_at`, `tz` (IANA), `rrule`, `recurrence_until` (`YYYY-MM-DD`), `participant_ids` (uuid array), `owner_id`, `visibility`, `remind_offsets_min` (int array), `about_member_id`, `planning_entry_id`.

- [ ] **Step 1: Write contract sections 1–3** in `supabase/tests/together_events_contracts.sql`

```sql
-- Together Phase 1a contracts (spec 2026-10-14 §3, §5). Self-contained
-- fixtures; every check RAISEs on violation.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('7b000000-0000-0000-0000-0000000000a1'),
  ('7b000000-0000-0000-0000-0000000000b2'),
  ('7b000000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7b000000-0000-0000-0000-0000000000a1', '+233270000001', 'Ama'),
  ('7b000000-0000-0000-0000-0000000000b2', '+233270000002', 'Kofi'),
  ('7b000000-0000-0000-0000-0000000000c3', '+233270000003', 'Stranger')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('7f000000-0000-0000-0000-000000000001',
        '7b000000-0000-0000-0000-0000000000a1',
        '7b000000-0000-0000-0000-0000000000b2', 'active', now(), now())
ON CONFLICT (id) DO NOTHING;

CREATE TEMP TABLE t_ids (name text PRIMARY KEY, id uuid) ON COMMIT DROP;
GRANT ALL ON t_ids TO authenticated;

-- 1. Ama creates a shared timed event, a busy_only one and a private one.
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7b000000-0000-0000-0000-0000000000a1','role','authenticated')::text, true);
  INSERT INTO t_ids VALUES ('shared', public.create_couple_event('7f000000-0000-0000-0000-000000000001',
    '{"title":"Dinner at Buka","all_day":false,"starts_at":"2026-11-06T19:00:00Z","ends_at":"2026-11-06T21:00:00Z","tz":"Africa/Accra","participant_ids":["7b000000-0000-0000-0000-0000000000a1","7b000000-0000-0000-0000-0000000000b2"],"note":"Book a table","remind_offsets_min":[60]}'::jsonb));
  INSERT INTO t_ids VALUES ('busy', public.create_couple_event('7f000000-0000-0000-0000-000000000001',
    '{"title":"Therapy","all_day":false,"starts_at":"2026-11-06T10:00:00Z","tz":"Africa/Accra","participant_ids":["7b000000-0000-0000-0000-0000000000a1"],"visibility":"busy_only","note":"private note"}'::jsonb));
  INSERT INTO t_ids VALUES ('private', public.create_couple_event('7f000000-0000-0000-0000-000000000001',
    '{"title":"Pick up ring","all_day":true,"start_date":"2026-11-07","participant_ids":["7b000000-0000-0000-0000-0000000000a1"],"visibility":"private","remind_offsets_min":[0]}'::jsonb));
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 2. Invalid input is rejected with together:* codes, never a raw error.
DO $$
DECLARE v_msg text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7b000000-0000-0000-0000-0000000000a1','role','authenticated')::text, true);
  -- end before start
  BEGIN
    PERFORM public.create_couple_event('7f000000-0000-0000-0000-000000000001',
      '{"title":"Bad","all_day":true,"start_date":"2026-11-07","end_date":"2026-11-06","participant_ids":["7b000000-0000-0000-0000-0000000000a1"]}'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: end before start accepted';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:invalid_input' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;
  -- a stranger as participant
  BEGIN
    PERFORM public.create_couple_event('7f000000-0000-0000-0000-000000000001',
      '{"title":"Bad","all_day":true,"start_date":"2026-11-07","participant_ids":["7b000000-0000-0000-0000-0000000000c3"]}'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: stranger participant accepted';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:invalid_input' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;
  -- owner set to the partner is a hand-off (Phase 2)
  BEGIN
    PERFORM public.create_couple_event('7f000000-0000-0000-0000-000000000001',
      '{"title":"Plumber","all_day":true,"start_date":"2026-11-07","participant_ids":["7b000000-0000-0000-0000-0000000000a1"],"owner_id":"7b000000-0000-0000-0000-0000000000b2"}'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: owner hand-off accepted directly';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:owner_handoff' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;
  -- BYDAY on a non-weekly rule
  BEGIN
    PERFORM public.create_couple_event('7f000000-0000-0000-0000-000000000001',
      '{"title":"Bad","all_day":true,"start_date":"2026-11-07","rrule":"FREQ=DAILY;BYDAY=MO","participant_ids":["7b000000-0000-0000-0000-0000000000a1"]}'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: BYDAY on DAILY accepted';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:invalid_input' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;
  -- a private event that includes the partner
  BEGIN
    PERFORM public.create_couple_event('7f000000-0000-0000-0000-000000000001',
      '{"title":"Bad","all_day":true,"start_date":"2026-11-07","visibility":"private","participant_ids":["7b000000-0000-0000-0000-0000000000a1","7b000000-0000-0000-0000-0000000000b2"]}'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: private event with partner accepted';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:invalid_input' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 3. Permissions: the partner can edit and leave a shared event, but can't
--    touch busy_only/private ones; a stranger can't create; the table is
--    not readable directly (R1).
DO $$
DECLARE v_msg text; v_n int;
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7b000000-0000-0000-0000-0000000000b2','role','authenticated')::text, true);
  PERFORM public.update_couple_event((SELECT id FROM t_ids WHERE name='shared'),
    '{"title":"Dinner at Buka (8pm)","all_day":false,"starts_at":"2026-11-06T20:00:00Z","tz":"Africa/Accra","participant_ids":["7b000000-0000-0000-0000-0000000000a1","7b000000-0000-0000-0000-0000000000b2"]}'::jsonb);
  BEGIN
    PERFORM public.delete_couple_event((SELECT id FROM t_ids WHERE name='busy'));
    RAISE EXCEPTION 'CONTRACT VIOLATED: partner deleted a busy_only event';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:not_found' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;
  PERFORM public.leave_couple_event((SELECT id FROM t_ids WHERE name='shared'));
  SELECT count(*) INTO v_n FROM public.couple_events
  WHERE id = (SELECT id FROM t_ids WHERE name='shared')
    AND NOT ('7b000000-0000-0000-0000-0000000000b2' = ANY(participant_ids)) AND deleted_at IS NULL;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: leave did not remove the partner only'; END IF;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7b000000-0000-0000-0000-0000000000c3','role','authenticated')::text, true);
  BEGIN
    PERFORM public.create_couple_event('7f000000-0000-0000-0000-000000000001',
      '{"title":"x","all_day":true,"start_date":"2026-11-07","participant_ids":["7b000000-0000-0000-0000-0000000000c3"]}'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: stranger created an event';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:not_found' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7b000000-0000-0000-0000-0000000000a1','role','authenticated')::text, true);
  BEGIN
    PERFORM count(*) FROM public.couple_events;
    RAISE EXCEPTION 'CONTRACT VIOLATED: couple_events readable directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

ROLLBACK;
```

- [ ] **Step 2: Write the table migration** `20261014110000_couple_events.sql`

```sql
-- Together (spec 2026-10-14 §5.1): the couple's own events. Not readable
-- directly (plan ruling R1): writes go through SECURITY DEFINER RPCs and
-- reads through list_together_items, which masks busy_only titles and
-- drops private events for the partner.

CREATE TABLE public.couple_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind text NOT NULL DEFAULT 'event'
    CHECK (kind IN ('event', 'trip', 'big_day', 'ritual_occurrence')),
  title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 120),
  note text CHECK (note IS NULL OR char_length(note) <= 500),
  location_name text CHECK (location_name IS NULL OR char_length(location_name) <= 120),
  all_day boolean NOT NULL,
  start_date date,
  end_date date,
  starts_at timestamptz,
  ends_at timestamptz,
  tz text CHECK (tz IS NULL OR char_length(tz) BETWEEN 1 AND 64),
  rrule text CHECK (rrule IS NULL OR rrule ~
    '^FREQ=(DAILY|WEEKLY|MONTHLY|YEARLY)(;INTERVAL=[1-9][0-9]?)?(;BYDAY=(MO|TU|WE|TH|FR|SA|SU)(,(MO|TU|WE|TH|FR|SA|SU)){0,6})?$'),
  recurrence_until date,
  participant_ids uuid[] NOT NULL CHECK (cardinality(participant_ids) BETWEEN 1 AND 2),
  owner_id uuid,
  visibility text NOT NULL DEFAULT 'shared'
    CHECK (visibility IN ('shared', 'busy_only', 'private')),
  status text NOT NULL DEFAULT 'confirmed'
    CHECK (status IN ('proposed', 'confirmed', 'cancelled')),
  proposed_to uuid,
  proposal_expires_at timestamptz,
  decided_at timestamptz,
  ritual_id uuid,
  planning_entry_id uuid REFERENCES public.planning_entries(id) ON DELETE SET NULL,
  memory_event_id uuid REFERENCES public.timeline_events(id) ON DELETE SET NULL,
  about_member_id uuid REFERENCES public.couple_family_members(id) ON DELETE SET NULL,
  remind_offsets_min int[] NOT NULL DEFAULT '{}' CHECK (
    cardinality(remind_offsets_min) <= 3
    AND 0 <= ALL (remind_offsets_min) AND 10080 >= ALL (remind_offsets_min)),
  legacy_reminder_id uuid UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  CONSTRAINT couple_events_when CHECK (
    (all_day AND start_date IS NOT NULL AND starts_at IS NULL AND ends_at IS NULL
       AND (end_date IS NULL OR end_date >= start_date))
    OR (NOT all_day AND starts_at IS NOT NULL AND tz IS NOT NULL
       AND start_date IS NULL AND end_date IS NULL
       AND (ends_at IS NULL OR ends_at >= starts_at))),
  CONSTRAINT couple_events_repeat_one_day CHECK (rrule IS NULL OR
    (all_day AND (end_date IS NULL OR end_date = start_date))
    OR (NOT all_day AND (ends_at IS NULL OR ends_at - starts_at < interval '24 hours'))),
  CONSTRAINT couple_events_byday_weekly CHECK (
    rrule IS NULL OR position('BYDAY' in rrule) = 0 OR rrule LIKE 'FREQ=WEEKLY%'),
  CONSTRAINT couple_events_until_needs_rule CHECK (recurrence_until IS NULL OR rrule IS NOT NULL),
  CONSTRAINT couple_events_proposal CHECK (
    status <> 'proposed' OR (proposed_to IS NOT NULL AND proposal_expires_at IS NOT NULL))
);

CREATE INDEX idx_couple_events_relationship
  ON public.couple_events (relationship_id) WHERE deleted_at IS NULL;

ALTER TABLE public.couple_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.couple_events FROM PUBLIC, anon, authenticated;

CREATE TRIGGER set_couple_events_updated_at
  BEFORE UPDATE ON public.couple_events
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trigger_together_signal_couple_events ON public.couple_events;
CREATE TRIGGER trigger_together_signal_couple_events
  AFTER INSERT OR UPDATE OR DELETE ON public.couple_events
  FOR EACH ROW EXECUTE FUNCTION public.bump_together_signal();
```

- [ ] **Step 3: Write the RPC migration** `20261014110100_together_event_rpcs.sql`

```sql
-- Together write RPCs (spec §3.4, §5.4). Errors are P0001 'together:<code>'.

CREATE TYPE public.together_event_input AS (
  kind text, title text, note text, location_name text, all_day boolean,
  start_date date, end_date date, starts_at timestamptz, ends_at timestamptz,
  tz text, rrule text, recurrence_until date, participant_ids uuid[],
  owner_id uuid, visibility text, remind_offsets_min int[],
  about_member_id uuid, planning_entry_id uuid
);

CREATE FUNCTION public.together_fail(p_code text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'together:' || p_code;
END;
$$;
REVOKE ALL ON FUNCTION public.together_fail(text) FROM PUBLIC, anon, authenticated;

-- The caller, who must be a member of this active relationship.
CREATE FUNCTION public.together_actor(p_relationship_id uuid) RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN PERFORM public.together_fail('unauthenticated'); END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = p_relationship_id AND r.status = 'active' AND r.chat_archived_at IS NULL
      AND (r.user_a = v_uid OR r.user_b = v_uid)
  ) THEN
    PERFORM public.together_fail('not_found');
  END IF;
  RETURN v_uid;
END;
$$;
REVOKE ALL ON FUNCTION public.together_actor(uuid) FROM PUBLIC, anon, authenticated;

-- Checks what the table's CHECKs can't: people, references, zones.
CREATE FUNCTION public.together_validate_input(
  p_relationship_id uuid, p_actor uuid, e public.together_event_input,
  p_existing_owner uuid DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_members uuid[];
BEGIN
  SELECT array_remove(ARRAY[r.user_a, r.user_b], NULL) INTO v_members
  FROM public.relationships r WHERE r.id = p_relationship_id;

  IF e.title IS NULL OR btrim(e.title) = ''
     OR coalesce(e.kind, 'event') NOT IN ('event', 'trip', 'big_day')
     OR e.all_day IS NULL
     OR e.participant_ids IS NULL OR cardinality(e.participant_ids) = 0
     OR NOT (e.participant_ids <@ v_members)
     OR cardinality(ARRAY(SELECT DISTINCT unnest(e.participant_ids))) <> cardinality(e.participant_ids)
     OR (e.tz IS NOT NULL AND NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = e.tz))
     OR (coalesce(e.visibility, 'shared') = 'private' AND e.participant_ids <> ARRAY[p_actor])
     OR (e.about_member_id IS NOT NULL AND NOT EXISTS (
          SELECT 1 FROM public.couple_family_members f
          WHERE f.id = e.about_member_id AND f.relationship_id = p_relationship_id))
     OR (e.planning_entry_id IS NOT NULL AND NOT EXISTS (
          SELECT 1 FROM public.planning_entries pe
          WHERE pe.id = e.planning_entry_id AND pe.relationship_id = p_relationship_id
            AND pe.deleted_at IS NULL))
  THEN
    PERFORM public.together_fail('invalid_input');
  END IF;

  IF e.owner_id IS NOT NULL AND e.owner_id <> p_actor
     AND e.owner_id IS DISTINCT FROM p_existing_owner THEN
    IF e.owner_id = ANY (v_members) THEN
      PERFORM public.together_fail('owner_handoff');
    END IF;
    PERFORM public.together_fail('invalid_input');
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.together_validate_input(uuid, uuid, public.together_event_input, uuid)
  FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.create_couple_event(p_relationship_id uuid, p_event jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_actor uuid := public.together_actor(p_relationship_id);
  e public.together_event_input;
  v_id uuid;
BEGIN
  BEGIN
    e := jsonb_populate_record(NULL::public.together_event_input, p_event);
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.together_fail('invalid_input');
  END;
  PERFORM public.together_validate_input(p_relationship_id, v_actor, e);
  BEGIN
    INSERT INTO public.couple_events (
      relationship_id, created_by, kind, title, note, location_name, all_day,
      start_date, end_date, starts_at, ends_at, tz, rrule, recurrence_until,
      participant_ids, owner_id, visibility, remind_offsets_min,
      about_member_id, planning_entry_id)
    VALUES (
      p_relationship_id, v_actor, coalesce(e.kind, 'event'), btrim(e.title),
      nullif(btrim(e.note), ''), nullif(btrim(e.location_name), ''), e.all_day,
      e.start_date, e.end_date, e.starts_at, e.ends_at, e.tz, e.rrule, e.recurrence_until,
      e.participant_ids, e.owner_id, coalesce(e.visibility, 'shared'),
      coalesce(e.remind_offsets_min, '{}'), e.about_member_id, e.planning_entry_id)
    RETURNING id INTO v_id;
  EXCEPTION WHEN check_violation OR not_null_violation THEN
    PERFORM public.together_fail('invalid_input');
  END;
  RETURN v_id;
END;
$$;

-- The row the caller may change: shared events by either partner,
-- busy_only/private ones by their creator only (others: not_found).
CREATE FUNCTION public.together_editable_event(p_event_id uuid)
RETURNS public.couple_events
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row public.couple_events; v_actor uuid;
BEGIN
  SELECT * INTO v_row FROM public.couple_events WHERE id = p_event_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.together_fail('not_found'); END IF;
  v_actor := public.together_actor(v_row.relationship_id);
  IF v_row.visibility <> 'shared' AND v_row.created_by <> v_actor THEN
    PERFORM public.together_fail('not_found');
  END IF;
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.together_editable_event(uuid) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.update_couple_event(p_event_id uuid, p_event jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_row public.couple_events := public.together_editable_event(p_event_id);
  v_actor uuid := auth.uid();
  e public.together_event_input;
BEGIN
  BEGIN
    e := jsonb_populate_record(NULL::public.together_event_input, p_event);
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.together_fail('invalid_input');
  END;
  PERFORM public.together_validate_input(v_row.relationship_id, v_actor, e, v_row.owner_id);
  IF v_row.created_by <> v_actor AND coalesce(e.visibility, 'shared') <> v_row.visibility THEN
    PERFORM public.together_fail('forbidden');
  END IF;
  BEGIN
    UPDATE public.couple_events SET
      kind = coalesce(e.kind, 'event'), title = btrim(e.title),
      note = nullif(btrim(e.note), ''), location_name = nullif(btrim(e.location_name), ''),
      all_day = e.all_day, start_date = e.start_date, end_date = e.end_date,
      starts_at = e.starts_at, ends_at = e.ends_at, tz = e.tz,
      rrule = e.rrule, recurrence_until = e.recurrence_until,
      participant_ids = e.participant_ids, owner_id = e.owner_id,
      visibility = coalesce(e.visibility, 'shared'),
      remind_offsets_min = coalesce(e.remind_offsets_min, '{}'),
      about_member_id = e.about_member_id, planning_entry_id = e.planning_entry_id
    WHERE id = v_row.id;
  EXCEPTION WHEN check_violation OR not_null_violation THEN
    PERFORM public.together_fail('invalid_input');
  END;
END;
$$;

CREATE FUNCTION public.delete_couple_event(p_event_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row public.couple_events := public.together_editable_event(p_event_id);
BEGIN
  UPDATE public.couple_events SET deleted_at = now() WHERE id = v_row.id;
END;
$$;

-- Step out of an event someone else put you in (spec §3.4): silent, and
-- the event goes away when nobody is left in it.
CREATE FUNCTION public.leave_couple_event(p_event_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row public.couple_events := public.together_editable_event(p_event_id);
        v_actor uuid := auth.uid();
BEGIN
  IF NOT (v_actor = ANY (v_row.participant_ids)) THEN
    PERFORM public.together_fail('not_found');
  END IF;
  IF cardinality(v_row.participant_ids) = 1 THEN
    UPDATE public.couple_events SET deleted_at = now() WHERE id = v_row.id;
  ELSE
    UPDATE public.couple_events
    SET participant_ids = array_remove(participant_ids, v_actor),
        owner_id = CASE WHEN owner_id = v_actor THEN NULL ELSE owner_id END
    WHERE id = v_row.id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.create_couple_event(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_couple_event(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_couple_event(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.leave_couple_event(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_couple_event(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_couple_event(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_couple_event(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.leave_couple_event(uuid) TO authenticated;
```

Note: section 1 of the contract inserts `"tz":"Africa/Accra"` events with `ends_at`. If `pg_timezone_names` lookups are slow in CI that's fine.

- [ ] **Step 4: Verify.** With Docker up: `scripts/run_sql_contracts.sh together_events` → passes. Otherwise ledger "written, not run". Also run `grep -c "together:" supabase/migrations/20261014110100_together_event_rpcs.sql` as a sanity check (>10).

---

### Task 2: `list_together_items` with server-side recurrence

**Files:**
- Create: `supabase/migrations/20261014110200_list_together_items.sql`
- Modify: `supabase/tests/together_events_contracts.sql` (sections 4–6, inserted before `ROLLBACK;`)

**Interfaces:**
- Consumes: `couple_events`, `together_actor`, `together_fail` (Task 1).
- Produces:
  - `public.together_event_dates(e public.couple_events, p_start date, p_end date) RETURNS SETOF date`, the occurrence days in the event's own zone;
  - `public.list_together_items(p_relationship_id uuid, p_start date, p_end date)`, which returns a table with these columns:

    `(item_kind text, item_id uuid, item_date date, starts_at timestamptz, ends_at timestamptz, all_day boolean, tz text, title text, participant_ids uuid[], owner_id uuid, created_by uuid, visibility text, status text, source_ref jsonb)`

  - `item_kind` is one of `event`, `moment`, `reminder`, `planning_date`, `planning_item`.

- [ ] **Step 1: Write contract sections 4–6** (before `ROLLBACK;`)

```sql
-- 4. Recurrence: weekly across DST, monthly on the 31st, yearly Feb 29.
DO $$
DECLARE v_id uuid; v_dates date[]; v_utc timestamptz[];
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7b000000-0000-0000-0000-0000000000a1','role','authenticated')::text, true);

  v_id := public.create_couple_event('7f000000-0000-0000-0000-000000000001',
    '{"title":"Date night","all_day":false,"starts_at":"2026-10-16T18:00:00Z","ends_at":"2026-10-16T20:00:00Z","tz":"Europe/London","rrule":"FREQ=WEEKLY;BYDAY=FR","participant_ids":["7b000000-0000-0000-0000-0000000000a1","7b000000-0000-0000-0000-0000000000b2"]}'::jsonb);
  SELECT array_agg(item_date ORDER BY item_date), array_agg(starts_at ORDER BY item_date)
  INTO v_dates, v_utc
  FROM public.list_together_items('7f000000-0000-0000-0000-000000000001', '2026-10-15', '2026-11-01')
  WHERE item_id = v_id;
  IF v_dates <> ARRAY['2026-10-16','2026-10-23','2026-10-30']::date[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: weekly dates %', v_dates;
  END IF;
  -- 19:00 London is 18:00Z in BST and 19:00Z after the 25 Oct change.
  IF v_utc[1] <> '2026-10-16T18:00:00Z'::timestamptz OR v_utc[3] <> '2026-10-30T19:00:00Z'::timestamptz THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: DST not kept local %', v_utc;
  END IF;

  v_id := public.create_couple_event('7f000000-0000-0000-0000-000000000001',
    '{"title":"Rent","all_day":true,"start_date":"2026-08-31","rrule":"FREQ=MONTHLY","participant_ids":["7b000000-0000-0000-0000-0000000000a1"]}'::jsonb);
  SELECT array_agg(item_date ORDER BY item_date) INTO v_dates
  FROM public.list_together_items('7f000000-0000-0000-0000-000000000001', '2026-09-01', '2026-11-30')
  WHERE item_id = v_id;
  IF v_dates <> ARRAY['2026-09-30','2026-10-31','2026-11-30']::date[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: monthly 31st %', v_dates;
  END IF;

  v_id := public.create_couple_event('7f000000-0000-0000-0000-000000000001',
    '{"title":"Leap day","all_day":true,"start_date":"2024-02-29","rrule":"FREQ=YEARLY","participant_ids":["7b000000-0000-0000-0000-0000000000a1"]}'::jsonb);
  SELECT array_agg(item_date) INTO v_dates
  FROM public.list_together_items('7f000000-0000-0000-0000-000000000001', '2027-02-01', '2027-03-15')
  WHERE item_id = v_id;
  IF v_dates <> ARRAY['2027-02-28']::date[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Feb 29 in a non-leap year %', v_dates;
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 5. What the partner sees: busy_only masked, private absent, and the
--    union carries moments, reminders and Planning too.
DO $$
DECLARE v_title text; v_ref jsonb; v_n int;
BEGIN
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
  VALUES ('7f000000-0000-0000-0000-000000000001', '7b000000-0000-0000-0000-0000000000a1', 'highlight', 'Beach', '2026-11-05');
  INSERT INTO public.reminders (relationship_id, created_by, reminder_type, title, remind_at, recurrence)
  VALUES ('7f000000-0000-0000-0000-000000000001', '7b000000-0000-0000-0000-0000000000a1', 'birthday', 'Ama''s birthday', '2020-11-04', 'yearly');

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7b000000-0000-0000-0000-0000000000b2','role','authenticated')::text, true);
  SELECT title, source_ref INTO v_title, v_ref
  FROM public.list_together_items('7f000000-0000-0000-0000-000000000001', '2026-11-01', '2026-11-30')
  WHERE item_id = (SELECT id FROM t_ids WHERE name='busy');
  IF v_title <> 'Busy' OR v_ref ? 'note' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: busy_only leaks to the partner (% %)', v_title, v_ref;
  END IF;
  SELECT count(*) INTO v_n
  FROM public.list_together_items('7f000000-0000-0000-0000-000000000001', '2026-11-01', '2026-11-30')
  WHERE item_id = (SELECT id FROM t_ids WHERE name='private');
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: private event visible to the partner'; END IF;
  SELECT count(*) INTO v_n
  FROM public.list_together_items('7f000000-0000-0000-0000-000000000001', '2026-11-01', '2026-11-30')
  WHERE (item_kind = 'moment' AND item_date = '2026-11-05')
     OR (item_kind = 'reminder' AND item_date = '2026-11-04');
  IF v_n <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: moment/reminder missing from the union (%)', v_n; END IF;

  -- The creator sees her own private event and the busy one's real title.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7b000000-0000-0000-0000-0000000000a1','role','authenticated')::text, true);
  SELECT count(*) INTO v_n
  FROM public.list_together_items('7f000000-0000-0000-0000-000000000001', '2026-11-01', '2026-11-30')
  WHERE item_id IN ((SELECT id FROM t_ids WHERE name='private'), (SELECT id FROM t_ids WHERE name='busy'))
    AND title IN ('Pick up ring', 'Therapy');
  IF v_n <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: creator cannot see own events (%)', v_n; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 6. Range limits, membership, and no scorecard columns (spec §3.1).
DO $$
DECLARE v_msg text; v_result text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7b000000-0000-0000-0000-0000000000a1','role','authenticated')::text, true);
  BEGIN
    PERFORM count(*) FROM public.list_together_items('7f000000-0000-0000-0000-000000000001', '2026-01-01', '2026-06-01');
    RAISE EXCEPTION 'CONTRACT VIOLATED: >93-day range accepted';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:range' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;
  BEGIN
    PERFORM count(*) FROM public.list_together_items('7f000000-0000-0000-0000-000000000001', '2026-06-01', '2026-05-01');
    RAISE EXCEPTION 'CONTRACT VIOLATED: reversed range accepted';
  EXCEPTION WHEN raise_exception THEN NULL;
  END;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7b000000-0000-0000-0000-0000000000c3','role','authenticated')::text, true);
  BEGIN
    PERFORM count(*) FROM public.list_together_items('7f000000-0000-0000-0000-000000000001', '2026-11-01', '2026-11-30');
    RAISE EXCEPTION 'CONTRACT VIOLATED: stranger read the couple''s items';
  EXCEPTION WHEN raise_exception THEN NULL;
  END;
  PERFORM set_config('request.jwt.claims', '', true);

  SELECT pg_get_function_result('public.list_together_items(uuid, date, date)'::regprocedure) INTO v_result;
  IF v_result ~* '(count|total|tally|score)' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: list_together_items returns an aggregate column: %', v_result;
  END IF;
END $$;
```

- [ ] **Step 2: Write the migration** `20261014110200_list_together_items.sql`

```sql
-- Together's single read (spec §5.5). Recurrence is expanded here so the
-- app, alarms and (later) the ICS feed agree. RRULE subset per plan
-- ruling R3; month-end clamping per R4. Dates are in the event's zone.

CREATE FUNCTION public.together_last_day(d date) RETURNS int
LANGUAGE sql IMMUTABLE AS $$
  SELECT extract(day FROM (date_trunc('month', d) + interval '1 month - 1 day'))::int
$$;

CREATE FUNCTION public.together_event_dates(e public.couple_events, p_start date, p_end date)
RETURNS SETOF date LANGUAGE sql STABLE AS $$
  WITH a AS (
    SELECT
      CASE WHEN e.all_day THEN e.start_date
           ELSE (e.starts_at AT TIME ZONE e.tz)::date END AS anchor,
      CASE WHEN e.all_day THEN coalesce(e.end_date, e.start_date)
           ELSE (coalesce(e.ends_at, e.starts_at) AT TIME ZONE e.tz)::date END AS last_day,
      substring(e.rrule FROM 'FREQ=([A-Z]+)') AS freq,
      coalesce(substring(e.rrule FROM 'INTERVAL=([0-9]+)')::int, 1) AS step,
      string_to_array(substring(e.rrule FROM 'BYDAY=([A-Z,]+)'), ',') AS bydays
  )
  SELECT d::date
  FROM a, generate_series(
    greatest(p_start, a.anchor),
    least(p_end, CASE WHEN e.rrule IS NULL THEN a.last_day
                      ELSE coalesce(e.recurrence_until, p_end) END),
    interval '1 day') AS d
  WHERE e.rrule IS NULL
     OR (a.freq = 'DAILY' AND (d::date - a.anchor) % a.step = 0)
     OR (a.freq = 'WEEKLY'
         AND (ARRAY['MO','TU','WE','TH','FR','SA','SU'])[extract(isodow FROM d)::int]
             = ANY (coalesce(a.bydays,
                ARRAY[(ARRAY['MO','TU','WE','TH','FR','SA','SU'])[extract(isodow FROM a.anchor)::int]]))
         AND (((d::date - (extract(isodow FROM d)::int - 1))
               - (a.anchor - (extract(isodow FROM a.anchor)::int - 1))) / 7) % a.step = 0)
     OR (a.freq = 'MONTHLY'
         AND ((extract(year FROM d)::int * 12 + extract(month FROM d)::int)
              - (extract(year FROM a.anchor)::int * 12 + extract(month FROM a.anchor)::int)) % a.step = 0
         AND extract(day FROM d)::int
             = least(extract(day FROM a.anchor)::int, public.together_last_day(d::date)))
     OR (a.freq = 'YEARLY'
         AND (extract(year FROM d)::int - extract(year FROM a.anchor)::int) % a.step = 0
         AND extract(month FROM d) = extract(month FROM a.anchor)
         AND extract(day FROM d)::int
             = least(extract(day FROM a.anchor)::int, public.together_last_day(d::date)))
$$;
REVOKE ALL ON FUNCTION public.together_event_dates(public.couple_events, date, date) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.list_together_items(p_relationship_id uuid, p_start date, p_end date)
RETURNS TABLE (
  item_kind text, item_id uuid, item_date date, starts_at timestamptz, ends_at timestamptz,
  all_day boolean, tz text, title text, participant_ids uuid[], owner_id uuid,
  created_by uuid, visibility text, status text, source_ref jsonb
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_actor uuid := public.together_actor(p_relationship_id);
  v_members uuid[];
BEGIN
  IF p_start IS NULL OR p_end IS NULL OR p_end < p_start OR p_end - p_start > 93 THEN
    PERFORM public.together_fail('range');
  END IF;
  SELECT array_remove(ARRAY[r.user_a, r.user_b], NULL) INTO v_members
  FROM public.relationships r WHERE r.id = p_relationship_id;

  RETURN QUERY
  -- 1. Couple events, one row per day they fall on.
  SELECT 'event'::text, ce.id, occ.d,
    CASE WHEN ce.all_day THEN NULL
         WHEN ce.rrule IS NULL THEN ce.starts_at
         ELSE ((occ.d + (ce.starts_at AT TIME ZONE ce.tz)::time) AT TIME ZONE ce.tz) END,
    CASE WHEN ce.all_day OR ce.ends_at IS NULL THEN NULL
         WHEN ce.rrule IS NULL THEN ce.ends_at
         ELSE ((occ.d + (ce.starts_at AT TIME ZONE ce.tz)::time) AT TIME ZONE ce.tz)
              + (ce.ends_at - ce.starts_at) END,
    ce.all_day, ce.tz,
    CASE WHEN ce.visibility = 'busy_only' AND ce.created_by <> v_actor THEN 'Busy' ELSE ce.title END,
    ce.participant_ids, ce.owner_id, ce.created_by, ce.visibility, ce.status,
    CASE WHEN ce.visibility = 'busy_only' AND ce.created_by <> v_actor
      THEN jsonb_build_object('kind', ce.kind)
      ELSE jsonb_build_object(
        'kind', ce.kind, 'note', ce.note, 'location_name', ce.location_name,
        'start_date', ce.start_date, 'end_date', ce.end_date,
        'event_starts_at', ce.starts_at, 'event_ends_at', ce.ends_at,
        'rrule', ce.rrule, 'recurrence_until', ce.recurrence_until,
        'remind_offsets_min', to_jsonb(ce.remind_offsets_min),
        'about_member_id', ce.about_member_id, 'planning_entry_id', ce.planning_entry_id)
    END
  FROM public.couple_events ce
  CROSS JOIN LATERAL public.together_event_dates(ce, p_start, p_end) AS occ(d)
  WHERE ce.relationship_id = p_relationship_id AND ce.deleted_at IS NULL
    AND ce.status <> 'cancelled'
    AND (ce.visibility <> 'private' OR ce.created_by = v_actor)

  UNION ALL
  -- 2. Moments.
  SELECT 'moment'::text, te.id, te.occurred_at, NULL::timestamptz, NULL::timestamptz,
    true, NULL::text, te.title, ARRAY[te.logged_by], NULL::uuid, te.logged_by,
    'shared'::text, 'confirmed'::text,
    jsonb_build_object('event_type', te.event_type, 'mood_score', te.mood_score, 'note', te.note)
  FROM public.timeline_events te
  WHERE te.relationship_id = p_relationship_id AND te.deleted_at IS NULL
    AND te.occurred_at BETWEEN p_start AND p_end

  UNION ALL
  -- 3. Reminders (family birthdays included, plan ruling R5).
  SELECT DISTINCT 'reminder'::text, r.id, x.day, NULL::timestamptz, NULL::timestamptz,
    true, NULL::text, r.title, v_members, NULL::uuid, r.created_by,
    'shared'::text, 'confirmed'::text,
    jsonb_build_object('reminder_type', r.reminder_type, 'recurrence', r.recurrence,
      'family_member_id', r.family_member_id,
      'linked_timeline_event_id', r.linked_timeline_event_id, 'note', r.note)
  FROM public.reminders r
  CROSS JOIN LATERAL (SELECT (r.remind_at AT TIME ZONE 'UTC')::date AS on_day) rd
  CROSS JOIN LATERAL (
    SELECT CASE WHEN r.recurrence = 'yearly' THEN
             make_date(y, extract(month FROM rd.on_day)::int,
               least(extract(day FROM rd.on_day)::int,
                     public.together_last_day(make_date(y, extract(month FROM rd.on_day)::int, 1))))
           ELSE rd.on_day END AS day
    FROM generate_series(extract(year FROM p_start)::int, extract(year FROM p_end)::int) AS y
  ) x
  WHERE r.relationship_id = p_relationship_id
    AND x.day BETWEEN p_start AND p_end

  UNION ALL
  -- 4. Planning date blocks, one row per day (as list_planning_calendar_entries).
  SELECT 'planning_date'::text, e.id, d::date, NULL::timestamptz, NULL::timestamptz,
    true, NULL::text, e.title, v_members, NULL::uuid, NULL::uuid,
    'shared'::text, 'confirmed'::text,
    jsonb_build_object('entry_id', e.id)
  FROM public.planning_blocks b
  JOIN public.planning_entries e ON e.id = b.entry_id
  CROSS JOIN LATERAL generate_series(
    greatest(b.date_start, p_start), least(coalesce(b.date_end, b.date_start), p_end), interval '1 day') d
  WHERE b.relationship_id = p_relationship_id AND b.block_type = 'date' AND b.deleted_at IS NULL
    AND b.date_start IS NOT NULL AND b.date_start <= p_end
    AND coalesce(b.date_end, b.date_start) >= p_start
    AND e.deleted_at IS NULL AND NOT e.is_template

  UNION ALL
  -- 5. Planning to-dos with a due date.
  SELECT 'planning_item'::text, i.id, i.due_date, NULL::timestamptz, NULL::timestamptz,
    true, NULL::text, i.text, v_members, NULL::uuid, NULL::uuid,
    'shared'::text, 'confirmed'::text,
    jsonb_build_object('entry_id', e.id, 'is_complete', i.checked_at IS NOT NULL)
  FROM public.planning_block_items i
  JOIN public.planning_blocks b ON b.id = i.block_id
  JOIN public.planning_entries e ON e.id = b.entry_id
  WHERE i.relationship_id = p_relationship_id AND i.deleted_at IS NULL
    AND i.due_date BETWEEN p_start AND p_end
    AND b.deleted_at IS NULL AND e.deleted_at IS NULL AND NOT e.is_template;
END;
$$;
REVOKE ALL ON FUNCTION public.list_together_items(uuid, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_together_items(uuid, date, date) TO authenticated;
```

Before writing, confirm the Planning column names used in sections 4 and 5 against `20261012200700_planning_replace_v1.sql:123-160`: `planning_blocks.relationship_id`, `date_start`, `date_end`, `block_type`, `entry_id`; `planning_block_items.relationship_id`, `due_date`, `checked_at`, `text`, `block_id`; `planning_entries.is_template`. If one differs, use the real name and ledger it.

- [ ] **Step 3: Verify.** With Docker up, `scripts/run_sql_contracts.sh together_events` passes. Otherwise ledger "written, not run".

---

### Task 3: Event reminders (alarms)

**Files:**
- Create: `supabase/migrations/20261014110300_together_event_alarms.sql`
- Modify: `supabase/tests/together_events_contracts.sql` (section 7)
- Modify: `supabase/functions/process-scheduled-notifications/index.ts` (`privacySafeData` allowlist)
- Create: `supabase/functions/process-scheduled-notifications/together_event_data.test.ts`
- Modify: `lib/core/notifications/config/notification_config.dart`
- Create: `test/core/notifications/together_event_route_test.dart`

**Interfaces:**
- Consumes: `together_event_dates` (Task 2).
- Produces:
  - `public.together_enqueue_event_alarms(p_now timestamptz DEFAULT now()) RETURNS int`;
  - cron job `together_event_alarms` running every 15 minutes;
  - push data `{type: 'together_event', relationship_id, event_id}`.

- [ ] **Step 1: Write contract section 7** (before `ROLLBACK;`)

```sql
-- 7. Alarms: a shared event's 60-minute alarm reaches both participants
--    once; a private event's goes to its creator only (R6, spec §3.6).
DO $$
DECLARE v_n int; v_again int; v_private_partner int;
BEGIN
  -- The shared event now starts 2026-11-06 20:00Z with Ama only (Kofi left
  -- in section 3), so add Kofi back via a fresh event for a clean check.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7b000000-0000-0000-0000-0000000000a1','role','authenticated')::text, true);
  INSERT INTO t_ids VALUES ('alarm', public.create_couple_event('7f000000-0000-0000-0000-000000000001',
    '{"title":"Flight","all_day":false,"starts_at":"2026-11-10T09:00:00Z","tz":"UTC","participant_ids":["7b000000-0000-0000-0000-0000000000a1","7b000000-0000-0000-0000-0000000000b2"],"remind_offsets_min":[60]}'::jsonb));
  PERFORM set_config('request.jwt.claims', '', true);

  PERFORM public.together_enqueue_event_alarms('2026-11-10T08:05:00Z');
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
  WHERE source_key LIKE 'together_alarm:' || (SELECT id FROM t_ids WHERE name='alarm') || ':%'
    AND metadata->>'type' = 'together_event';
  IF v_n <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: expected 2 alarm pushes, got %', v_n; END IF;

  PERFORM public.together_enqueue_event_alarms('2026-11-10T08:15:00Z');
  SELECT count(*) INTO v_again FROM public.scheduled_notifications
  WHERE source_key LIKE 'together_alarm:' || (SELECT id FROM t_ids WHERE name='alarm') || ':%';
  IF v_again <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: alarm sent twice (%)', v_again; END IF;

  -- private all-day event on 2026-11-07, offset 0 → 08:00 creator-local (UTC here).
  PERFORM public.together_enqueue_event_alarms('2026-11-07T08:05:00Z');
  SELECT count(*) INTO v_private_partner FROM public.scheduled_notifications
  WHERE source_key LIKE 'together_alarm:' || (SELECT id FROM t_ids WHERE name='private') || ':%'
    AND user_id = '7b000000-0000-0000-0000-0000000000b2';
  IF v_private_partner <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: private alarm reached the partner'; END IF;
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
  WHERE source_key LIKE 'together_alarm:' || (SELECT id FROM t_ids WHERE name='private') || ':%'
    AND user_id = '7b000000-0000-0000-0000-0000000000a1';
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: private alarm missing for its creator (%)', v_n; END IF;
END $$;
```

- [ ] **Step 2: Write the migration** `20261014110300_together_event_alarms.sql`

```sql
-- Event alarms the user asked for (plan ruling R6; outside D9's budget).
-- Every 15 minutes: an alarm fires in the first run at or after
-- (start − offset), within a 20-minute window; idempotent per event,
-- day, offset and recipient. All-day events count from 08:00 in the
-- recipient's zone (planning_member_settings, else UTC). Shared events
-- alarm their participants; busy_only/private ones only their creator.

CREATE FUNCTION public.together_enqueue_event_alarms(p_now timestamptz DEFAULT now())
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n int;
BEGIN
  INSERT INTO public.scheduled_notifications
    (user_id, notification_type, scheduled_for, status, metadata, source_key)
  SELECT m.user_id, 'immediate', p_now, 'pending',
    jsonb_build_object(
      'type', 'together_event',
      'relationship_id', ce.relationship_id,
      'event_id', ce.id,
      'title', left(ce.title, 120),
      'body', CASE
        WHEN o.off = 0 AND ce.all_day THEN 'Today'
        WHEN o.off = 0 THEN 'Starting now'
        WHEN o.off % 1440 = 0 THEN 'In ' || (o.off / 1440) || CASE WHEN o.off = 1440 THEN ' day' ELSE ' days' END
        WHEN o.off % 60 = 0 THEN 'In ' || (o.off / 60) || CASE WHEN o.off = 60 THEN ' hour' ELSE ' hours' END
        ELSE 'In ' || o.off || ' minutes' END),
    'together_alarm:' || ce.id || ':' || occ.d || ':' || o.off || ':' || m.user_id
  FROM public.couple_events ce
  JOIN public.relationships r
    ON r.id = ce.relationship_id AND r.status = 'active' AND r.chat_archived_at IS NULL
  CROSS JOIN LATERAL unnest(ce.remind_offsets_min) AS o(off)
  CROSS JOIN LATERAL (
    SELECT u AS user_id,
           coalesce((SELECT s.timezone FROM public.planning_member_settings s
                     WHERE s.relationship_id = r.id AND s.user_id = u), 'UTC') AS tz
    FROM unnest(CASE WHEN ce.visibility = 'shared' THEN ce.participant_ids
                     ELSE ARRAY[ce.created_by] END) AS u
    WHERE u = r.user_a OR u = r.user_b
  ) m
  CROSS JOIN LATERAL public.together_event_dates(
    ce, (p_now AT TIME ZONE m.tz)::date - 1, (p_now AT TIME ZONE m.tz)::date + 8) AS occ(d)
  CROSS JOIN LATERAL (
    SELECT CASE
      WHEN ce.all_day THEN (occ.d + time '08:00') AT TIME ZONE m.tz
      WHEN ce.rrule IS NULL THEN ce.starts_at
      ELSE (occ.d + (ce.starts_at AT TIME ZONE ce.tz)::time) AT TIME ZONE ce.tz
    END AS ref
  ) t
  WHERE ce.deleted_at IS NULL AND ce.status = 'confirmed'
    AND cardinality(ce.remind_offsets_min) > 0
    -- one alarm per occurrence: a multi-day event alarms on its first day only
    AND (ce.rrule IS NOT NULL OR occ.d = CASE WHEN ce.all_day THEN ce.start_date
                                              ELSE (ce.starts_at AT TIME ZONE ce.tz)::date END)
    AND p_now >= t.ref - make_interval(mins => o.off)
    AND p_now < t.ref - make_interval(mins => o.off) + interval '20 minutes'
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.together_enqueue_event_alarms(timestamptz) FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'together_event_alarms';
END;
$$;
SELECT cron.schedule('together_event_alarms', '*/15 * * * *',
  $$ SELECT public.together_enqueue_event_alarms(); $$);
```

- [ ] **Step 3: Write the failing push-data and route tests**

`supabase/functions/process-scheduled-notifications/together_event_data.test.ts`:

```ts
// A Together event alarm must carry its event id to the app (deep link),
// through the privacy allowlist like reminder_id and entry_id do.
import { assertStringIncludes } from "https://deno.land/std@0.208.0/assert/mod.ts";

Deno.test("push data may carry event_id", async () => {
  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const allow = source.slice(source.indexOf("function privacySafeData"));
  assertStringIncludes(allow.slice(0, allow.indexOf("];")), '"event_id"');
});
```

`test/core/notifications/together_event_route_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A Together event alarm opens the calendar (Phase 1b retargets it to
/// /together), never the generic home fallback.
void main() {
  test("a 'together_event' tap is routed, not left to the default", () {
    final source =
        File('lib/core/notifications/config/notification_config.dart').readAsStringSync();
    final at = source.indexOf("case 'together_event':");
    expect(at, isNot(-1));
    expect(source.substring(at, source.indexOf('return;', at)), contains('RouteNames.timeline'));
  });
}
```

Run both. The Deno test fails on the missing `"event_id"`; the Dart test fails on `indexOf == -1`.

- [ ] **Step 4: Implement.**
  - In `process-scheduled-notifications/index.ts` `privacySafeData`, after `"entry_id",`, add:

```ts
    // Together event alarm deep link (Together spec §6.1).
    "event_id",
```

  - In `notification_config.dart`, next to the `moment_logged` case, add:

```dart
        case 'together_event':
          GoRouter.of(context).go(RouteNames.timeline);
          return;
```

- [ ] **Step 5: Verify.**
  - `deno test --allow-read supabase/functions/process-scheduled-notifications/together_event_data.test.ts` → pass.
  - `flutter test test/core/notifications/` → pass.
  - SQL contracts with Docker up; otherwise ledger "not run".

---

### Task 4: `TogetherItem` and `CoupleEventDraft` (Dart domain)

**Files:**
- Create: `lib/features/together/domain/together_item.dart`
- Create: `lib/features/together/domain/couple_event_draft.dart`
- Test: `test/features/together/together_item_test.dart`, `test/features/together/couple_event_draft_test.dart`

**Interfaces:**
- Produces:
  - `enum TogetherItemKind { event, moment, reminder, planningDate, planningItem }`
  - `enum TogetherVisibility { shared, busyOnly, private }`, with `String get wire` returning `'shared' | 'busy_only' | 'private'`
  - `enum TogetherWho { me, partner, us }`
  - `class TogetherItem`, with fields `kind, id, date, startsAt, endsAt, allDay, tz, title, participantIds, ownerId, createdBy, visibility, status, sourceRef`, plus:
    - `factory TogetherItem.fromRow(Map<String, dynamic>)`;
    - `DateTime get day`, the local calendar day to group under;
    - `TogetherWho whoFor(String myId)`.
  - `enum TogetherRepeat { none, daily, weekly, monthly, yearly }`
  - `class CoupleEventDraft`, with:
    - `String? get rrule`;
    - `String? validate()`, which returns copy or null;
    - `Map<String, dynamic> toPayload()`.

- [ ] **Step 1: Write the failing tests**

`test/features/together/together_item_test.dart`:

```dart
import 'package:attune/features/together/domain/together_item.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row({
  String kind = 'event',
  bool allDay = false,
  String? startsAt = '2026-11-06T19:00:00+00:00',
  List<String> participants = const ['ama', 'kofi'],
  String visibility = 'shared',
}) => {
  'item_kind': kind,
  'item_id': 'i1',
  'item_date': '2026-11-06',
  'starts_at': startsAt,
  'ends_at': null,
  'all_day': allDay,
  'tz': allDay ? null : 'Africa/Accra',
  'title': 'Dinner',
  'participant_ids': participants,
  'owner_id': 'ama',
  'created_by': 'ama',
  'visibility': visibility,
  'status': 'confirmed',
  'source_ref': {'note': 'Book a table'},
};

void main() {
  test('maps a timed event row; times come back in local time', () {
    final item = TogetherItem.fromRow(_row());
    expect(item.kind, TogetherItemKind.event);
    expect(item.startsAt, DateTime.utc(2026, 11, 6, 19).toLocal());
    expect(item.startsAt!.isUtc, isFalse);
    expect(item.visibility, TogetherVisibility.shared);
    expect(item.sourceRef['note'], 'Book a table');
  });

  test('an all-day row groups under its calendar date', () {
    final item = TogetherItem.fromRow(_row(allDay: true, startsAt: null));
    expect(item.day, DateTime(2026, 11, 6));
  });

  test('a timed row groups under the local day it starts', () {
    final item = TogetherItem.fromRow(_row());
    final local = item.startsAt!;
    expect(item.day, DateTime(local.year, local.month, local.day));
  });

  test('kinds and visibility map from the wire', () {
    expect(TogetherItem.fromRow(_row(kind: 'planning_item')).kind, TogetherItemKind.planningItem);
    expect(TogetherItem.fromRow(_row(kind: 'planning_date')).kind, TogetherItemKind.planningDate);
    expect(TogetherItem.fromRow(_row(visibility: 'busy_only')).visibility, TogetherVisibility.busyOnly);
  });

  test('who it is for, from my point of view', () {
    expect(TogetherItem.fromRow(_row()).whoFor('ama'), TogetherWho.us);
    expect(TogetherItem.fromRow(_row(participants: ['ama'])).whoFor('ama'), TogetherWho.me);
    expect(TogetherItem.fromRow(_row(participants: ['kofi'])).whoFor('ama'), TogetherWho.partner);
  });
}
```

`test/features/together/couple_event_draft_test.dart`:

```dart
import 'package:attune/features/together/domain/couple_event_draft.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:flutter_test/flutter_test.dart';

CoupleEventDraft _draft({
  String title = 'Date night',
  bool allDay = false,
  DateTime? start,
  DateTime? end,
  TogetherRepeat repeat = TogetherRepeat.none,
  int interval = 1,
  Set<int> weekdays = const {},
  List<String> participants = const ['ama', 'kofi'],
}) => CoupleEventDraft(
  title: title,
  allDay: allDay,
  start: start ?? DateTime(2026, 10, 16, 19),
  end: end,
  timezone: 'Europe/London',
  repeat: repeat,
  interval: interval,
  weekdays: weekdays,
  participantIds: participants,
);

void main() {
  test('rrule follows the server whitelist', () {
    expect(_draft().rrule, isNull);
    expect(_draft(repeat: TogetherRepeat.daily, interval: 2).rrule, 'FREQ=DAILY;INTERVAL=2');
    expect(
      _draft(repeat: TogetherRepeat.weekly, weekdays: {DateTime.friday, DateTime.monday}).rrule,
      'FREQ=WEEKLY;BYDAY=MO,FR',
    );
    expect(_draft(repeat: TogetherRepeat.monthly).rrule, 'FREQ=MONTHLY');
    expect(_draft(repeat: TogetherRepeat.yearly).rrule, 'FREQ=YEARLY');
  });

  test('timed payload sends UTC instants and the zone', () {
    final p = _draft(end: DateTime(2026, 10, 16, 21)).toPayload();
    expect(p['all_day'], false);
    expect(p['starts_at'], DateTime(2026, 10, 16, 19).toUtc().toIso8601String());
    expect(p['ends_at'], DateTime(2026, 10, 16, 21).toUtc().toIso8601String());
    expect(p['tz'], 'Europe/London');
    expect(p.containsKey('start_date'), isFalse);
  });

  test('all-day payload sends plain dates and no zone', () {
    final p = _draft(allDay: true, start: DateTime(2026, 11, 7), end: DateTime(2026, 11, 9)).toPayload();
    expect(p['start_date'], '2026-11-07');
    expect(p['end_date'], '2026-11-09');
    expect(p.containsKey('starts_at'), isFalse);
    expect(p['tz'], isNull);
  });

  test('validation speaks plainly', () {
    expect(_draft().validate(), isNull);
    expect(_draft(title: '  ').validate(), 'Give it a title');
    expect(_draft(title: 'x' * 121).validate(), 'Keep the title under 120 characters');
    expect(_draft(end: DateTime(2026, 10, 16, 18)).validate(), "It can't end before it starts");
    expect(_draft(participants: const []).validate(), "Choose who it's for");
    expect(
      _draft(allDay: true, start: DateTime(2026, 11, 7), end: DateTime(2026, 11, 8), repeat: TogetherRepeat.weekly).validate(),
      'Repeating events last one day',
    );
  });
}
```

- [ ] **Step 2: Run them to verify they fail**: `flutter test test/features/together/` → files not found / undefined names.

- [ ] **Step 3: Implement**

`lib/features/together/domain/together_item.dart`:

```dart
/// One thing on the couple's calendar, from `list_together_items`:
/// a Together event, a moment, a reminder, or a Planning date or to-do.
/// One shape for every kind (plan ruling R8).
library;

enum TogetherItemKind { event, moment, reminder, planningDate, planningItem }

enum TogetherVisibility {
  shared('shared'),
  busyOnly('busy_only'),
  private('private');

  const TogetherVisibility(this.wire);
  final String wire;

  static TogetherVisibility fromWire(String? s) =>
      values.firstWhere((v) => v.wire == s, orElse: () => shared);
}

/// Whose an item is, seen from one partner: theirs, the other's, or both.
enum TogetherWho { me, partner, us }

const _kinds = {
  'event': TogetherItemKind.event,
  'moment': TogetherItemKind.moment,
  'reminder': TogetherItemKind.reminder,
  'planning_date': TogetherItemKind.planningDate,
  'planning_item': TogetherItemKind.planningItem,
};

class TogetherItem {
  const TogetherItem({
    required this.kind,
    required this.id,
    required this.date,
    this.startsAt,
    this.endsAt,
    required this.allDay,
    this.tz,
    required this.title,
    required this.participantIds,
    this.ownerId,
    this.createdBy,
    this.visibility = TogetherVisibility.shared,
    this.status = 'confirmed',
    this.sourceRef = const {},
  });

  factory TogetherItem.fromRow(Map<String, dynamic> r) {
    DateTime? local(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();
    final day = DateTime.parse(r['item_date'] as String);
    return TogetherItem(
      kind: _kinds[r['item_kind']] ?? TogetherItemKind.event,
      id: r['item_id'] as String,
      date: DateTime(day.year, day.month, day.day),
      startsAt: local(r['starts_at']),
      endsAt: local(r['ends_at']),
      allDay: r['all_day'] as bool? ?? true,
      tz: r['tz'] as String?,
      title: r['title'] as String,
      participantIds: [for (final p in (r['participant_ids'] as List? ?? const [])) p as String],
      ownerId: r['owner_id'] as String?,
      createdBy: r['created_by'] as String?,
      visibility: TogetherVisibility.fromWire(r['visibility'] as String?),
      status: r['status'] as String? ?? 'confirmed',
      sourceRef: Map<String, dynamic>.from(r['source_ref'] as Map? ?? const {}),
    );
  }

  final TogetherItemKind kind;
  final String id;

  /// The calendar date the server placed it on (the event's own zone).
  final DateTime date;

  /// Local times; null for all-day items.
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool allDay;
  final String? tz;
  final String title;
  final List<String> participantIds;
  final String? ownerId;
  final String? createdBy;
  final TogetherVisibility visibility;
  final String status;
  final Map<String, dynamic> sourceRef;

  /// The local day to list it under: a timed item where it starts for the
  /// viewer, an all-day one on its calendar date.
  DateTime get day {
    final s = startsAt;
    if (allDay || s == null) return date;
    return DateTime(s.year, s.month, s.day);
  }

  TogetherWho whoFor(String myId) {
    final mine = participantIds.contains(myId);
    if (mine && participantIds.length > 1) return TogetherWho.us;
    return mine ? TogetherWho.me : TogetherWho.partner;
  }
}
```

`lib/features/together/domain/couple_event_draft.dart`:

```dart
import 'together_item.dart';

enum TogetherRepeat { none, daily, weekly, monthly, yearly }

const _weekdayCodes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// What the event editor collects, before it is saved. [start] and [end]
/// are local times (timed) or calendar dates (all-day); [timezone] is the
/// device's IANA zone, so a weekly 19:00 stays 19:00 across DST.
class CoupleEventDraft {
  const CoupleEventDraft({
    required this.title,
    required this.allDay,
    required this.start,
    this.end,
    this.timezone,
    this.note,
    this.locationName,
    this.kind = 'event',
    this.repeat = TogetherRepeat.none,
    this.interval = 1,
    this.weekdays = const {},
    this.repeatUntil,
    required this.participantIds,
    this.ownerId,
    this.visibility = TogetherVisibility.shared,
    this.remindOffsetsMin = const [],
  });

  final String title;
  final bool allDay;
  final DateTime start;
  final DateTime? end;
  final String? timezone;
  final String? note;
  final String? locationName;
  final String kind;
  final TogetherRepeat repeat;
  final int interval;

  /// `DateTime.monday` … `DateTime.sunday`; weekly only.
  final Set<int> weekdays;
  final DateTime? repeatUntil;
  final List<String> participantIds;
  final String? ownerId;
  final TogetherVisibility visibility;
  final List<int> remindOffsetsMin;

  /// The server's RRULE subset (plan ruling R3).
  String? get rrule {
    if (repeat == TogetherRepeat.none) return null;
    final parts = ['FREQ=${repeat.name.toUpperCase()}'];
    if (interval > 1) parts.add('INTERVAL=$interval');
    if (repeat == TogetherRepeat.weekly && weekdays.isNotEmpty) {
      final days = weekdays.toList()..sort();
      parts.add('BYDAY=${days.map((d) => _weekdayCodes[d - 1]).join(',')}');
    }
    return parts.join(';');
  }

  bool get _spansDays {
    final e = end;
    if (e == null) return false;
    return allDay
        ? DateTime(e.year, e.month, e.day).isAfter(DateTime(start.year, start.month, start.day))
        : e.difference(start) >= const Duration(hours: 24);
  }

  /// Plain-language problem with the draft, or null when it can be saved.
  String? validate() {
    final t = title.trim();
    if (t.isEmpty) return 'Give it a title';
    if (t.length > 120) return 'Keep the title under 120 characters';
    final e = end;
    if (e != null && e.isBefore(start)) return "It can't end before it starts";
    if (participantIds.isEmpty) return "Choose who it's for";
    if (repeat != TogetherRepeat.none && _spansDays) return 'Repeating events last one day';
    return null;
  }

  Map<String, dynamic> toPayload() => {
    'kind': kind,
    'title': title.trim(),
    'note': note,
    'location_name': locationName,
    'all_day': allDay,
    if (allDay) 'start_date': _ymd(start),
    if (allDay && end != null) 'end_date': _ymd(end!),
    if (!allDay) 'starts_at': start.toUtc().toIso8601String(),
    if (!allDay && end != null) 'ends_at': end!.toUtc().toIso8601String(),
    'tz': allDay ? null : timezone,
    'rrule': rrule,
    'recurrence_until': repeatUntil == null ? null : _ymd(repeatUntil!),
    'participant_ids': participantIds,
    'owner_id': ownerId,
    'visibility': visibility.wire,
    'remind_offsets_min': remindOffsetsMin,
  };
}
```

- [ ] **Step 4: Run tests**: `flutter test test/features/together/` → pass.

---

### Task 5: Repository and range provider

**Files:**
- Create: `lib/features/together/data/together_repository.dart`
- Create: `lib/features/together/presentation/together_providers.dart`
- Test: `test/features/together/together_repository_test.dart`, `test/features/together/together_range_provider_test.dart`

**Interfaces:**
- Consumes:
  - `TogetherItem`, `CoupleEventDraft` (Task 4);
  - the Task 1/2 RPC names;
  - `togetherChangeSignalProvider` (Phase 0, `timeline_providers.dart`);
  - `planningChangeSignalProvider` (`planning_providers.dart`).
- Produces:
  - `abstract class TogetherRpcGateway` with `Future<dynamic> rpc(String fn, {Map<String, dynamic>? params})`;
  - `SupabaseTogetherRpcGateway`;
  - `class TogetherException implements Exception`, holding `final String code`;
  - `TogetherRepository`:
    - `listItems(String relationshipId, {required DateTime start, required DateTime end})` → `Future<List<TogetherItem>>`;
    - `createEvent(String relationshipId, CoupleEventDraft draft)` → `Future<String>`;
    - `updateEvent(String eventId, CoupleEventDraft draft)`;
    - `deleteEvent(String eventId)`;
    - `leaveEvent(String eventId)`;
  - `togetherRepositoryProvider`;
  - `typedef TogetherRangeArgs = ({String relationshipId, DateTime start, DateTime end})`;
  - `togetherRangeProvider` (`FutureProvider.autoDispose.family<List<TogetherItem>, TogetherRangeArgs>`).

- [ ] **Step 1: Write the failing tests**

`test/features/together/together_repository_test.dart`:

```dart
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/domain/couple_event_draft.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeTogetherGateway implements TogetherRpcGateway {
  FakeTogetherGateway(this.handlers);
  final Map<String, dynamic Function(Map<String, dynamic>)> handlers;
  final List<(String, Map<String, dynamic>)> calls = [];

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) async {
    calls.add((function, params ?? const {}));
    final h = handlers[function];
    if (h == null) throw StateError('no handler for $function');
    return h(params ?? const {});
  }
}

void main() {
  test('listItems sends the range as plain dates and maps rows', () async {
    final g = FakeTogetherGateway({
      'list_together_items': (_) => [
        {
          'item_kind': 'moment', 'item_id': 'm1', 'item_date': '2026-11-05',
          'starts_at': null, 'ends_at': null, 'all_day': true, 'tz': null,
          'title': 'Beach', 'participant_ids': ['ama'], 'owner_id': null,
          'created_by': 'ama', 'visibility': 'shared', 'status': 'confirmed',
          'source_ref': {'event_type': 'highlight'},
        },
      ],
    });
    final items = await TogetherRepository(g).listItems(
      'rel-1', start: DateTime(2026, 11, 1), end: DateTime(2026, 11, 30, 23));
    expect(g.calls.single.$2, {
      'p_relationship_id': 'rel-1', 'p_start': '2026-11-01', 'p_end': '2026-11-30',
    });
    expect(items.single.kind, TogetherItemKind.moment);
  });

  test('createEvent sends the draft payload and returns the new id', () async {
    final g = FakeTogetherGateway({'create_couple_event': (_) => 'ev-1'});
    final draft = CoupleEventDraft(
      title: 'Dinner', allDay: true, start: DateTime(2026, 11, 7),
      participantIds: const ['ama'],
    );
    expect(await TogetherRepository(g).createEvent('rel-1', draft), 'ev-1');
    expect(g.calls.single.$2['p_relationship_id'], 'rel-1');
    expect(g.calls.single.$2['p_event'], draft.toPayload());
  });

  test('server refusals become TogetherException codes', () async {
    final g = FakeTogetherGateway({
      'delete_couple_event': (_) => throw const PostgrestException(message: 'together:not_found'),
    });
    await expectLater(
      TogetherRepository(g).deleteEvent('ev-1'),
      throwsA(isA<TogetherException>().having((e) => e.code, 'code', 'not_found')),
    );
  });
}
```

`test/features/together/together_range_provider_test.dart`:

```dart
import 'dart:async';

import 'package:attune/features/planning/presentation/planning_providers.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'together_repository_test.dart' show FakeTogetherGateway;

void main() {
  test('a Together or Planning signal refetches the range', () async {
    var fetches = 0;
    final g = FakeTogetherGateway({'list_together_items': (_) { fetches++; return const []; }});
    final together = StreamController<void>.broadcast();
    final planning = StreamController<void>.broadcast();
    addTearDown(together.close);
    addTearDown(planning.close);
    final c = ProviderContainer(overrides: [
      togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
      togetherChangeSignalProvider.overrideWith((ref, id) => together.stream),
      planningChangeSignalProvider.overrideWith((ref, id) => planning.stream),
    ]);
    addTearDown(c.dispose);
    final args = (relationshipId: 'rel-1', start: DateTime(2026, 11, 1), end: DateTime(2026, 11, 30));
    c.listen(togetherRangeProvider(args), (_, __) {});
    await c.read(togetherRangeProvider(args).future);
    expect(fetches, 1);

    together.add(null);
    await Future<void>.delayed(Duration.zero);
    await c.read(togetherRangeProvider(args).future);
    expect(fetches, 2);

    planning.add(null);
    await Future<void>.delayed(Duration.zero);
    await c.read(togetherRangeProvider(args).future);
    expect(fetches, 3);
  });
}
```

- [ ] **Step 2: Run them to verify they fail** (undefined names).

- [ ] **Step 3: Implement**

`lib/features/together/data/together_repository.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/couple_event_draft.dart';
import '../domain/together_item.dart';

/// The RPC seam, so tests run the real repository without Supabase
/// (the same pattern as PlanningRpcGateway).
abstract class TogetherRpcGateway {
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params});
}

class SupabaseTogetherRpcGateway implements TogetherRpcGateway {
  const SupabaseTogetherRpcGateway(this._supabase);
  final SupabaseClient _supabase;

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) =>
      _supabase.rpc(function, params: params);
}

/// A server refusal: `not_found`, `invalid_input`, `owner_handoff`,
/// `forbidden`, `range`, `unauthenticated`.
class TogetherException implements Exception {
  const TogetherException(this.code);
  final String code;

  @override
  String toString() => 'TogetherException($code)';
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class TogetherRepository {
  const TogetherRepository(this._gateway);
  final TogetherRpcGateway _gateway;

  Future<dynamic> _call(String fn, Map<String, dynamic> params) async {
    try {
      return await _gateway.rpc(fn, params: params);
    } on PostgrestException catch (e) {
      final m = RegExp(r'together:([a-z_]+)').firstMatch(e.message);
      if (m != null) throw TogetherException(m.group(1)!);
      rethrow;
    }
  }

  Future<List<TogetherItem>> listItems(
    String relationshipId, {
    required DateTime start,
    required DateTime end,
  }) async {
    final rows = await _call('list_together_items', {
      'p_relationship_id': relationshipId,
      'p_start': _ymd(start),
      'p_end': _ymd(end),
    }) as List;
    return [for (final r in rows) TogetherItem.fromRow(Map<String, dynamic>.from(r as Map))];
  }

  Future<String> createEvent(String relationshipId, CoupleEventDraft draft) async =>
      await _call('create_couple_event', {
        'p_relationship_id': relationshipId,
        'p_event': draft.toPayload(),
      }) as String;

  Future<void> updateEvent(String eventId, CoupleEventDraft draft) =>
      _call('update_couple_event', {'p_event_id': eventId, 'p_event': draft.toPayload()});

  Future<void> deleteEvent(String eventId) =>
      _call('delete_couple_event', {'p_event_id': eventId});

  Future<void> leaveEvent(String eventId) =>
      _call('leave_couple_event', {'p_event_id': eventId});
}
```

`lib/features/together/presentation/together_providers.dart`:

```dart
import 'package:attune/features/planning/presentation/planning_providers.dart'
    show planningChangeSignalProvider;
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    show togetherChangeSignalProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/together_repository.dart';
import '../domain/together_item.dart';

final togetherRepositoryProvider = Provider<TogetherRepository>(
  (ref) => TogetherRepository(SupabaseTogetherRpcGateway(Supabase.instance.client)),
);

typedef TogetherRangeArgs = ({String relationshipId, DateTime start, DateTime end});

/// Everything on the couple's calendar between two dates (≤ 93 days).
/// Refetches on any Together change (events, moments, reminders) and any
/// Planning change, since Planning dates and to-dos are in it too.
final togetherRangeProvider = FutureProvider.autoDispose
    .family<List<TogetherItem>, TogetherRangeArgs>((ref, a) {
      ref.listen(togetherChangeSignalProvider(a.relationshipId), (_, __) => ref.invalidateSelf());
      ref.listen(planningChangeSignalProvider(a.relationshipId), (_, __) => ref.invalidateSelf());
      return ref
          .watch(togetherRepositoryProvider)
          .listItems(a.relationshipId, start: a.start, end: a.end);
    });
```

- [ ] **Step 4: Run tests**: `flutter test test/features/together/` → pass. Run `flutter analyze lib/features/together` → no issues.

---

### Task 6: Close out

- [ ] **Step 1: Spec.** Add a "Phase 1a rulings" note under spec §8. List R1–R9 in one line each. Also amend D9 to say: "User-set event alarms (`together_event`) are requested by the user and sit outside this budget."
- [ ] **Step 2:** Run the full suite with `flutter test`. Expected: only the known planning failure.
- [ ] **Step 3:** Run `flutter analyze lib/features/together lib/core/notifications` → no errors or warnings.
- [ ] **Step 4:** Run the Deno tests: `deno test --allow-read supabase/functions/process-scheduled-notifications/ supabase/functions/generate-verdict/`.
- [ ] **Step 5:** If Docker is up, run `scripts/run_sql_contracts.sh together` (Phase 0 and 1a contracts). Otherwise report them as not run.
- [ ] **Step 6:** Report the deploy steps:
  - `supabase db push` for migrations `20261014110000`–`110300`;
  - deploy `process-scheduled-notifications`;
  - check `cron.job` lists `together_event_alarms`.
