# Together Phase 3 — Rituals: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give couples rituals of connection that protect their time without guilt:
- Rituals include date night, a weekly check-in ("State of the Union"), the long-distance weekly call, or a short after-bedtime check-in.
- One partner proposes a ritual and the other accepts it once.
- After that, each week's occurrence appears on both calendars by itself. Either partner can skip a week with no consequence, move one, pause the ritual or end it.
- There are no streaks and no counters (D8).

**Architecture:**
- **Server:** a `couple_rituals` table and SECURITY DEFINER RPCs: `propose_ritual`, `decide_ritual`, `update_ritual`, `set_ritual_status`, `skip_ritual_occurrence` and `list_together_rituals`. A daily cron, `together_ensure_ritual_occurrences`, keeps the next 14 days of occurrences as confirmed `couple_events` with `kind = 'ritual_occurrence'`.
  - A new `ritual_date` column plus a partial unique index makes occurrence creation idempotent.
  - Skipping cancels the occurrence, which keeps it out of the cron.
  - Pausing, ending or retiming deletes future occurrences, so the cron recreates them correctly.
  - Ritual proposals join "Needs you".
- **Client:** a ritual model and templates, repository and provider, a Rituals section on the Agenda, a template picker, editor and manage sheet, and a "Needs you" row for ritual proposals.

**Tech Stack:** Supabase Postgres 17 (pg_cron), Flutter/Riverpod 2, flutter_test, SQL contracts on the local PG17 harness.

**Spec:** `docs/superpowers/specs/2026-10-14-together-hub-design.md`: §6.2 (rituals), D8 (flexible, skip free, no counters), §3.2 (schema test: no counter columns), §5.3 (`couple_rituals`). The base is Phases 0–2b, uncommitted on main.

## Global Constraints

- Work directly on `main`. No commits unless asked. Re-read files before editing them. Format only touched files; revert any reflow of the owner's code.
- Migrations start at `20261014140000`. Edits to earlier undeployed migrations happen in place and are noted in the ledger.
- **Hard rules:**
  - No streak, count, total or score columns on rituals. This is a schema contract.
  - Skipping has no consequence, and no copy mentions missed weeks.
  - Rituals are shared and include both partners.
  - Agreeing to a ritual is a proposal (§3.4).
- **Pushes:**
  - `together_ritual`, when a ritual is proposed to you;
  - `together_ritual_reply`, when your proposal is answered.

  Both are partner-initiated, so they sit outside the D9 budget. Occurrences themselves never push; they appear in the morning summary like any event.

## Rulings (decided while planning)

- **R1:** The ritual is agreed once, and its weekly occurrences are then confirmed automatically. Either partner can skip, move, pause or end. The spec's "each week the app proposes one slot; both confirm" would mean a weekly nag and a weekly push. That contradicts the quiet-by-default rule and adds the mental load Together is meant to remove. Cost if wrong: occurrences could later be created as proposals instead.
- **R2:** Cadence is `weekly` or `fortnightly`, on a fixed weekday and local time, for a fixed duration. Monthly and "first Friday" rules wait until couples ask for them. Cost if wrong: a cadence enum value.
- **R3:** The slot comes from the ritual's preferred weekday and time. Fitting it into both partners' mutual free time waits for the busy overlay in Phase 6. Cost if wrong: none; Phase 6 adds a smarter slot.
- **R4:** Occurrences are kept 14 days ahead. The cron runs daily at 03:15 UTC, and also runs for one ritual as soon as it's accepted or changed.
- **R5:** Editing a single occurrence moves just that week. `update_couple_event` keeps `kind = 'ritual_occurrence'` and `ritual_id`, and the 1a validator is told to accept it.
- **R6:** Templates are client constants with plain names and defaults. The server only stores `template` as a label, so new templates need no migration.

## Review Focus

1. **Skip a week, then let the cron run:** the skipped week stays skipped and isn't recreated. Pinned in Task 1's contract.
2. **Pause, then resume:** future occurrences go away, then come back on the right days. Pinned in Task 1's contract.
3. **Change the time of a ritual:** future occurrences move to the new time, while past and skipped ones are untouched. Pinned in Task 1's contract.
4. **A partner moves one occurrence in the editor:** it stays a ritual occurrence and keeps its link. Pinned in Task 1's contract.
5. **A ritual proposal appears in "Needs you" and accepting it creates the next occurrences straight away.** Pinned in Task 1's contract and Task 4's test.

---

### Task 1: Rituals (SQL)

**Files:**
- Create: `supabase/migrations/20261014140000_together_rituals.sql`
- Modify in place (undeployed): `supabase/migrations/20261014110100_together_event_rpcs.sql`. In `update_couple_event`, keep `kind` for ritual occurrences, and let the validator pass them.
- The new migration also re-creates `list_together_needs_you` with a `ritual_proposal` branch; see Step 3.
- Create: `supabase/tests/together_rituals_contracts.sql`

**Interfaces:**
- `couple_events.ritual_date date`, with a unique index on `(ritual_id, ritual_date) WHERE ritual_id IS NOT NULL AND deleted_at IS NULL`.
- The `couple_rituals` table: `id`, `relationship_id`, `created_by`, `template`, `title`, `cadence`, `weekday` (1–7, ISO), `local_time`, `duration_min`, `tz`, `anchor_date`, `status` (`proposed`, `active`, `paused`, `ended`), `proposed_to`, `created_at`, `updated_at`.
- RPCs:
  - `propose_ritual(p_relationship_id uuid, p_ritual jsonb) RETURNS uuid`. The keys are `template`, `title`, `cadence`, `weekday`, `local_time` (`HH:MM`), `duration_min` and `tz`.
  - `decide_ritual(p_ritual_id uuid, p_accept boolean) RETURNS void`.
  - `update_ritual(p_ritual_id uuid, p_ritual jsonb) RETURNS void`. The creator or the partner can call it while the ritual is active or paused.
  - `set_ritual_status(p_ritual_id uuid, p_status text) RETURNS void`, with `p_status` one of `active`, `paused`, `ended`.
  - `skip_ritual_occurrence(p_event_id uuid) RETURNS void`.
  - `list_together_rituals(p_relationship_id uuid)` returns a table with these columns:

    `(ritual_id uuid, template text, title text, cadence text, weekday int, local_time text, duration_min int, tz text, status text, created_by uuid, proposed_to uuid, next_event_id uuid, next_starts_at timestamptz)`

  - `together_ensure_ritual_occurrences(p_now timestamptz DEFAULT now(), p_ritual_id uuid DEFAULT NULL) RETURNS int`, run daily by cron job `together_rituals`.

- [ ] **Step 1: Write the failing contracts**

```sql
-- Together Phase 3 contracts: rituals.
BEGIN;
INSERT INTO auth.users (id) VALUES ('7f100000-0000-0000-0000-0000000000a1'), ('7f100000-0000-0000-0000-0000000000b2'), ('7f100000-0000-0000-0000-0000000000c3') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7f100000-0000-0000-0000-0000000000a1', '+233300000001', 'Ama'),
  ('7f100000-0000-0000-0000-0000000000b2', '+233300000002', 'Kofi'),
  ('7f100000-0000-0000-0000-0000000000c3', '+233300000003', 'Stranger') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('7f200000-0000-0000-0000-000000000001', '7f100000-0000-0000-0000-0000000000a1',
        '7f100000-0000-0000-0000-0000000000b2', 'active', now(), now()) ON CONFLICT (id) DO NOTHING;
CREATE TEMP TABLE t_ids (name text PRIMARY KEY, id uuid) ON COMMIT DROP;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;
CREATE FUNCTION pg_temp.occ(p_ritual uuid) RETURNS date[] LANGUAGE sql AS $$
  SELECT coalesce(array_agg(ritual_date ORDER BY ritual_date), '{}') FROM public.couple_events
  WHERE ritual_id = p_ritual AND deleted_at IS NULL AND status = 'confirmed' $$;

-- 0. No counters, ever (spec §3.2).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'public' AND table_name = 'couple_rituals'
               AND column_name ~* '(streak|count|total|score|missed|tally)') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: couple_rituals has a counter column';
  END IF;
END $$;

-- 1. Ama proposes a Friday date night; Kofi sees it in Needs you, gets one push, accepts;
--    the next two Fridays appear at 19:00 Accra (UTC).
DO $$
DECLARE v_id uuid; v_n int;
BEGIN
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000a1');
  v_id := public.propose_ritual('7f200000-0000-0000-0000-000000000001',
    '{"template":"date_night","title":"Date night","cadence":"weekly","weekday":5,"local_time":"19:00","duration_min":120,"tz":"Africa/Accra"}'::jsonb);
  INSERT INTO t_ids VALUES ('date', v_id);
  IF EXISTS (SELECT 1 FROM public.couple_events WHERE ritual_id = v_id) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: occurrences before the ritual is agreed';
  END IF;
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
  WHERE user_id = '7f100000-0000-0000-0000-0000000000b2' AND metadata->>'type' = 'together_ritual';
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: ritual proposal pushes %', v_n; END IF;

  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.list_together_needs_you('7f200000-0000-0000-0000-000000000001')
  WHERE need_kind = 'ritual_proposal' AND item_id = v_id;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: ritual proposal not in Needs you'; END IF;
  PERFORM public.decide_ritual(v_id, true);
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

DO $$
DECLARE v_dates date[]; v_start timestamptz;
BEGIN
  PERFORM public.together_ensure_ritual_occurrences('2026-11-02T03:15:00Z');
  v_dates := pg_temp.occ((SELECT id FROM t_ids WHERE name='date'));
  IF NOT (v_dates @> ARRAY['2026-11-06','2026-11-13']::date[]) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: occurrences %', v_dates;
  END IF;
  SELECT starts_at INTO v_start FROM public.couple_events
  WHERE ritual_id = (SELECT id FROM t_ids WHERE name='date') AND ritual_date = '2026-11-06';
  IF v_start <> '2026-11-06T19:00:00Z'::timestamptz THEN RAISE EXCEPTION 'CONTRACT VIOLATED: start %', v_start; END IF;
  -- idempotent
  PERFORM public.together_ensure_ritual_occurrences('2026-11-02T03:15:00Z');
  IF (SELECT count(*) FROM public.couple_events WHERE ritual_id = (SELECT id FROM t_ids WHERE name='date')
      AND ritual_date = '2026-11-06' AND deleted_at IS NULL) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: duplicate occurrence';
  END IF;
END $$;

-- 2. Skipping a week sticks; moving one week keeps it a ritual occurrence.
DO $$
DECLARE v_ev uuid; v_kind text; v_rid uuid;
BEGIN
  SELECT id INTO v_ev FROM public.couple_events WHERE ritual_id = (SELECT id FROM t_ids WHERE name='date') AND ritual_date = '2026-11-06';
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000b2');
  PERFORM public.skip_ritual_occurrence(v_ev);
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM public.together_ensure_ritual_occurrences('2026-11-03T03:15:00Z');
  IF '2026-11-06'::date = ANY (pg_temp.occ((SELECT id FROM t_ids WHERE name='date'))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a skipped week came back';
  END IF;

  SELECT id INTO v_ev FROM public.couple_events WHERE ritual_id = (SELECT id FROM t_ids WHERE name='date') AND ritual_date = '2026-11-13';
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000b2');
  PERFORM public.update_couple_event(v_ev,
    '{"title":"Date night","kind":"event","all_day":false,"starts_at":"2026-11-13T20:00:00Z","ends_at":"2026-11-13T22:00:00Z","tz":"Africa/Accra","participant_ids":["7f100000-0000-0000-0000-0000000000a1","7f100000-0000-0000-0000-0000000000b2"]}'::jsonb);
  SELECT kind, ritual_id INTO v_kind, v_rid FROM public.couple_events WHERE id = v_ev;
  IF v_kind <> 'ritual_occurrence' OR v_rid IS NULL THEN RAISE EXCEPTION 'CONTRACT VIOLATED: moved week became % / %', v_kind, v_rid; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 3. Pause removes future weeks; resume brings them back; retiming moves them.
DO $$
DECLARE v_dates date[]; v_start timestamptz;
BEGIN
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000a1');
  PERFORM public.set_ritual_status((SELECT id FROM t_ids WHERE name='date'), 'paused');
  v_dates := pg_temp.occ((SELECT id FROM t_ids WHERE name='date'));
  IF EXISTS (SELECT 1 FROM unnest(v_dates) d WHERE d >= current_date) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: paused ritual kept future weeks %', v_dates;
  END IF;
  PERFORM public.set_ritual_status((SELECT id FROM t_ids WHERE name='date'), 'active');
  PERFORM public.update_ritual((SELECT id FROM t_ids WHERE name='date'),
    '{"title":"Date night","cadence":"weekly","weekday":6,"local_time":"18:30","duration_min":120,"tz":"Africa/Accra"}'::jsonb);
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM public.together_ensure_ritual_occurrences(now());
  SELECT starts_at INTO v_start FROM public.couple_events
  WHERE ritual_id = (SELECT id FROM t_ids WHERE name='date') AND deleted_at IS NULL AND status = 'confirmed'
    AND ritual_date >= current_date ORDER BY ritual_date LIMIT 1;
  IF v_start IS NULL OR extract(isodow FROM v_start AT TIME ZONE 'Africa/Accra') <> 6
     OR to_char(v_start AT TIME ZONE 'Africa/Accra', 'HH24:MI') <> '18:30' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: retimed occurrence %', v_start;
  END IF;
END $$;

-- 4. Listing, permissions, decline.
DO $$
DECLARE v_n int; v_msg text; v_id uuid; v_status text;
BEGIN
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.list_together_rituals('7f200000-0000-0000-0000-000000000001') WHERE status = 'active' AND next_starts_at IS NOT NULL;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: active ritual with next occurrence not listed'; END IF;
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000c3');
  BEGIN
    PERFORM public.list_together_rituals('7f200000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'CONTRACT VIOLATED: stranger listed rituals';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:not_found' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000b2');
  v_id := public.propose_ritual('7f200000-0000-0000-0000-000000000001',
    '{"template":"state_of_union","title":"State of the Union","cadence":"weekly","weekday":7,"local_time":"18:00","duration_min":60,"tz":"Africa/Accra"}'::jsonb);
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000a1');
  PERFORM public.decide_ritual(v_id, false);
  SELECT status INTO v_status FROM public.couple_rituals WHERE id = v_id;
  IF v_status <> 'ended' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: declined ritual status %', v_status; END IF;
  BEGIN
    PERFORM public.propose_ritual('7f200000-0000-0000-0000-000000000001',
      '{"title":"Bad","cadence":"daily","weekday":5,"local_time":"19:00","duration_min":60,"tz":"Africa/Accra"}'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: daily cadence accepted';
  EXCEPTION WHEN raise_exception THEN NULL;
  END;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

ROLLBACK;
```

- [ ] **Step 2: Run to verify it fails** with the harness: `propose_ritual does not exist`.

- [ ] **Step 3: In-place edits.**
  - In `20261014110100_together_event_rpcs.sql` `update_couple_event`:
    - after `e.visibility := coalesce(e.visibility, v_row.visibility);`, add:

```sql
  -- A ritual occurrence stays one when a week is moved (Phase 3 R5); the
  -- validator only knows client kinds, so it checks this as a plain event.
  IF v_row.kind = 'ritual_occurrence' THEN e.kind := 'event'; END IF;
```

    - change the `kind = CASE …` assignment to:

```sql
      kind = CASE WHEN v_row.kind = 'ritual_occurrence' OR v_row.created_by <> v_actor
                  THEN v_row.kind ELSE coalesce(e.kind, 'event') END,
```

  - Do **not** edit `20261014120000`. Its `list_together_needs_you` would need `couple_rituals`, which doesn't exist yet at that point. Instead, Step 4's migration re-creates `list_together_needs_you` with `CREATE OR REPLACE`. That copy is identical to 120000's definition except for:
    - an added branch (placed before the `handoff` branch):

```sql
  UNION ALL
  SELECT 'ritual_proposal'::text, cr.id, cr.title, NULL::date, cr.created_by,
    jsonb_build_object('template', cr.template, 'cadence', cr.cadence, 'weekday', cr.weekday,
                       'local_time', to_char(cr.local_time, 'HH24:MI'), 'duration_min', cr.duration_min,
                       'tz', cr.tz)
  FROM public.couple_rituals cr
  WHERE cr.relationship_id = p_relationship_id AND cr.status = 'proposed' AND cr.proposed_to = v_me
```

    - the ORDER BY array `ARRAY['proposal','ritual_proposal','handoff','poll','unowned_todo','sent_proposal']`.

- [ ] **Step 4: Write the migration** `20261014140000_together_rituals.sql`

```sql
-- Together Phase 3: rituals of connection (spec §6.2, D8; plan R1–R6).
-- Agreed once; weekly occurrences appear by themselves; skipping is free;
-- no counters of any kind.

ALTER TABLE public.couple_events ADD COLUMN ritual_date date;
CREATE UNIQUE INDEX couple_events_ritual_week
  ON public.couple_events (ritual_id, ritual_date)
  WHERE ritual_id IS NOT NULL AND deleted_at IS NULL;

CREATE TABLE public.couple_rituals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  template text NOT NULL DEFAULT 'custom' CHECK (char_length(template) BETWEEN 1 AND 40),
  title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 80),
  cadence text NOT NULL CHECK (cadence IN ('weekly', 'fortnightly')),
  weekday smallint NOT NULL CHECK (weekday BETWEEN 1 AND 7),
  local_time time NOT NULL,
  duration_min int NOT NULL CHECK (duration_min BETWEEN 10 AND 480),
  tz text NOT NULL CHECK (char_length(tz) BETWEEN 1 AND 64),
  anchor_date date NOT NULL DEFAULT current_date,
  status text NOT NULL DEFAULT 'proposed' CHECK (status IN ('proposed', 'active', 'paused', 'ended')),
  proposed_to uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_couple_rituals_relationship ON public.couple_rituals (relationship_id) WHERE status <> 'ended';
ALTER TABLE public.couple_rituals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.couple_rituals FROM PUBLIC, anon, authenticated;
CREATE TRIGGER set_couple_rituals_updated_at BEFORE UPDATE ON public.couple_rituals
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS trigger_together_signal_rituals ON public.couple_rituals;
CREATE TRIGGER trigger_together_signal_rituals AFTER INSERT OR UPDATE OR DELETE ON public.couple_rituals
  FOR EACH ROW EXECUTE FUNCTION public.bump_together_signal();

-- Validated ritual fields from JSON (invalid input → together:invalid_input).
CREATE FUNCTION public.together_ritual_fields(p jsonb,
  OUT o_title text, OUT o_template text, OUT o_cadence text, OUT o_weekday smallint,
  OUT o_time time, OUT o_duration int, OUT o_tz text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  BEGIN
    o_title := btrim(p->>'title');
    o_template := coalesce(nullif(btrim(p->>'template'), ''), 'custom');
    o_cadence := p->>'cadence';
    o_weekday := (p->>'weekday')::smallint;
    o_time := (p->>'local_time')::time;
    o_duration := (p->>'duration_min')::int;
    o_tz := p->>'tz';
  EXCEPTION WHEN OTHERS THEN PERFORM public.together_fail('invalid_input');
  END;
  IF o_title IS NULL OR o_title = '' OR char_length(o_title) > 80
     OR o_cadence IS NULL OR o_cadence NOT IN ('weekly', 'fortnightly')
     OR o_weekday IS NULL OR o_weekday NOT BETWEEN 1 AND 7
     OR o_time IS NULL OR o_duration IS NULL OR o_duration NOT BETWEEN 10 AND 480
     OR o_tz IS NULL OR NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = o_tz) THEN
    PERFORM public.together_fail('invalid_input');
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.together_ritual_fields(jsonb) FROM PUBLIC, anon, authenticated;

-- Keep the next 14 days of a ritual's weeks as confirmed shared events.
CREATE FUNCTION public.together_ensure_ritual_occurrences(p_now timestamptz DEFAULT now(), p_ritual_id uuid DEFAULT NULL)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n int;
BEGIN
  INSERT INTO public.couple_events (
    relationship_id, created_by, kind, title, all_day, starts_at, ends_at, tz,
    participant_ids, visibility, status, ritual_id, ritual_date)
  SELECT cr.relationship_id, cr.created_by, 'ritual_occurrence', cr.title, false,
    (d.d + cr.local_time) AT TIME ZONE cr.tz,
    ((d.d + cr.local_time) AT TIME ZONE cr.tz) + make_interval(mins => cr.duration_min),
    cr.tz, array_remove(ARRAY[r.user_a, r.user_b], NULL), 'shared', 'confirmed', cr.id, d.d
  FROM public.couple_rituals cr
  JOIN public.relationships r ON r.id = cr.relationship_id AND r.status = 'active' AND r.chat_archived_at IS NULL
  CROSS JOIN LATERAL generate_series(
    greatest((p_now AT TIME ZONE cr.tz)::date, cr.anchor_date),
    (p_now AT TIME ZONE cr.tz)::date + 13, interval '1 day') AS d(d)
  WHERE cr.status = 'active' AND (p_ritual_id IS NULL OR cr.id = p_ritual_id)
    AND extract(isodow FROM d.d)::int = cr.weekday
    AND (cr.cadence = 'weekly'
         OR ((d.d::date - (cr.anchor_date - (extract(isodow FROM cr.anchor_date)::int - 1))) / 7) % 2 = 0)
    -- not in the past: a week whose start already went by isn't created
    AND (d.d + cr.local_time) AT TIME ZONE cr.tz > p_now
  ON CONFLICT (ritual_id, ritual_date) WHERE ritual_id IS NOT NULL AND deleted_at IS NULL DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.together_ensure_ritual_occurrences(timestamptz, uuid) FROM PUBLIC, anon, authenticated;

-- Future weeks (not skipped ones) go away, so the next ensure lays them out afresh.
CREATE FUNCTION public.together_clear_future_weeks(p_ritual_id uuid) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.couple_events SET deleted_at = now()
  WHERE ritual_id = p_ritual_id AND deleted_at IS NULL AND status = 'confirmed' AND starts_at > now()
$$;
REVOKE ALL ON FUNCTION public.together_clear_future_weeks(uuid) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.together_ritual_row(p_ritual_id uuid) RETURNS public.couple_rituals
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v public.couple_rituals;
BEGIN
  SELECT * INTO v FROM public.couple_rituals WHERE id = p_ritual_id;
  IF NOT FOUND THEN PERFORM public.together_fail('not_found'); END IF;
  PERFORM public.together_actor(v.relationship_id);
  RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.together_ritual_row(uuid) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.propose_ritual(p_relationship_id uuid, p_ritual jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := public.together_actor(p_relationship_id);
  v_partner uuid := public.together_partner(p_relationship_id, v_me);
  f record;
  v public.couple_rituals;
BEGIN
  IF v_partner IS NULL THEN PERFORM public.together_fail('invalid_input'); END IF;
  SELECT * INTO f FROM public.together_ritual_fields(p_ritual);
  INSERT INTO public.couple_rituals (relationship_id, created_by, template, title, cadence, weekday,
    local_time, duration_min, tz, status, proposed_to)
  VALUES (p_relationship_id, v_me, f.o_template, f.o_title, f.o_cadence, f.o_weekday,
    f.o_time, f.o_duration, f.o_tz, 'proposed', v_partner)
  RETURNING * INTO v;
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata, source_key)
  VALUES (v_partner, 'immediate', now(), 'pending',
    jsonb_build_object('type', 'together_ritual', 'relationship_id', p_relationship_id,
      'title', public.together_name(v_me) || ' suggested a ritual', 'body', v.title),
    'together_ritual:' || v.id)
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING;
  RETURN v.id;
END;
$$;

CREATE FUNCTION public.decide_ritual(p_ritual_id uuid, p_accept boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v public.couple_rituals; v_me uuid := auth.uid();
BEGIN
  SELECT * INTO v FROM public.couple_rituals WHERE id = p_ritual_id FOR UPDATE;
  IF NOT FOUND OR v.status <> 'proposed' OR v.proposed_to IS DISTINCT FROM v_me THEN
    PERFORM public.together_fail('not_found');
  END IF;
  PERFORM public.together_actor(v.relationship_id);
  UPDATE public.couple_rituals
  SET status = CASE WHEN p_accept THEN 'active' ELSE 'ended' END,
      proposed_to = NULL, anchor_date = current_date
  WHERE id = v.id;
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata, source_key)
  VALUES (v.created_by, 'immediate', now(), 'pending',
    jsonb_build_object('type', 'together_ritual_reply', 'relationship_id', v.relationship_id,
      'title', CASE WHEN p_accept THEN public.together_name(v_me) || ' is in'
                    ELSE public.together_name(v_me) || ' would rather not, for now' END,
      'body', v.title),
    'together_ritual_reply:' || v.id)
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING;
  IF p_accept THEN PERFORM public.together_ensure_ritual_occurrences(now(), v.id); END IF;
END;
$$;

CREATE FUNCTION public.update_ritual(p_ritual_id uuid, p_ritual jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v public.couple_rituals := public.together_ritual_row(p_ritual_id); f record;
BEGIN
  IF v.status NOT IN ('active', 'paused') THEN PERFORM public.together_fail('not_found'); END IF;
  SELECT * INTO f FROM public.together_ritual_fields(p_ritual || jsonb_build_object('template', v.template));
  UPDATE public.couple_rituals SET title = f.o_title, cadence = f.o_cadence, weekday = f.o_weekday,
    local_time = f.o_time, duration_min = f.o_duration, tz = f.o_tz, anchor_date = current_date
  WHERE id = v.id;
  PERFORM public.together_clear_future_weeks(v.id);
  PERFORM public.together_ensure_ritual_occurrences(now(), v.id);
END;
$$;

CREATE FUNCTION public.set_ritual_status(p_ritual_id uuid, p_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v public.couple_rituals := public.together_ritual_row(p_ritual_id);
BEGIN
  IF p_status NOT IN ('active', 'paused', 'ended') OR v.status IN ('proposed', 'ended') THEN
    PERFORM public.together_fail('invalid_input');
  END IF;
  UPDATE public.couple_rituals SET status = p_status WHERE id = v.id;
  IF p_status = 'active' THEN
    PERFORM public.together_ensure_ritual_occurrences(now(), v.id);
  ELSE
    PERFORM public.together_clear_future_weeks(v.id);
  END IF;
END;
$$;

CREATE FUNCTION public.skip_ritual_occurrence(p_event_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v public.couple_events;
BEGIN
  SELECT * INTO v FROM public.couple_events WHERE id = p_event_id AND deleted_at IS NULL;
  IF NOT FOUND OR v.kind <> 'ritual_occurrence' OR v.status <> 'confirmed' THEN
    PERFORM public.together_fail('not_found');
  END IF;
  PERFORM public.together_actor(v.relationship_id);
  UPDATE public.couple_events SET status = 'cancelled' WHERE id = v.id;
END;
$$;

CREATE FUNCTION public.list_together_rituals(p_relationship_id uuid)
RETURNS TABLE (ritual_id uuid, template text, title text, cadence text, weekday int,
  local_time text, duration_min int, tz text, status text, created_by uuid,
  proposed_to uuid, next_event_id uuid, next_starts_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.together_actor(p_relationship_id);
  RETURN QUERY
  SELECT cr.id, cr.template, cr.title, cr.cadence, cr.weekday::int,
    to_char(cr.local_time, 'HH24:MI'), cr.duration_min, cr.tz, cr.status, cr.created_by, cr.proposed_to,
    n.id, n.starts_at
  FROM public.couple_rituals cr
  LEFT JOIN LATERAL (
    SELECT ce.id, ce.starts_at FROM public.couple_events ce
    WHERE ce.ritual_id = cr.id AND ce.deleted_at IS NULL AND ce.status = 'confirmed'
      AND coalesce(ce.ends_at, ce.starts_at) > now()
    ORDER BY ce.starts_at LIMIT 1
  ) n ON true
  WHERE cr.relationship_id = p_relationship_id AND cr.status <> 'ended'
  ORDER BY (cr.status = 'proposed') DESC, n.starts_at NULLS LAST, cr.created_at;
END;
$$;

REVOKE ALL ON FUNCTION public.propose_ritual(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decide_ritual(uuid, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_ritual(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_ritual_status(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.skip_ritual_occurrence(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_together_rituals(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.propose_ritual(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decide_ritual(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_ritual(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_ritual_status(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.skip_ritual_occurrence(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_together_rituals(uuid) TO authenticated;

DO $$
BEGIN
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'together_rituals';
END;
$$;
SELECT cron.schedule('together_rituals', '15 3 * * *', $$ SELECT public.together_ensure_ritual_occurrences(); $$);
```

After that, append the full `CREATE OR REPLACE FUNCTION public.list_together_needs_you(...)`. Copy it verbatim from the current 120000 definition, add the `ritual_proposal` branch from Step 3, and use the new ORDER BY. Keep its REVOKE and GRANT lines.

- [ ] **Step 5: Verify.** Run all five Together contract files on the harness → PASS.

---

### Task 2: Ritual model, templates, repository, provider

**Files:**
- Create: `lib/features/together/domain/together_ritual.dart`
- Modify: `together_repository.dart`, `together_providers.dart`, `together_need.dart` (new need kind)
- Test: `test/features/together/together_ritual_test.dart`, plus additions to `together_repository_test.dart`

**Interfaces:**
- `enum RitualCadence { weekly, fortnightly }`
- `enum RitualStatus { proposed, active, paused }`
- `class TogetherRitual`, with fields `{id, template, title, cadence, weekday (1–7), localTime (TimeOfDay-like: hour, minute), durationMin, tz, status, createdBy, proposedTo, nextEventId, nextStartsAt (local DateTime?)}`, plus `fromRow` and `String get when`. For example, `when` is "Fridays at 19:00" or "Every other Sunday at 18:00".
- `class RitualTemplate { id, title, blurb, cadence, weekday, hour, minute, durationMin, icon }` and `const ritualTemplates`, which holds:
  - `date_night`: "Date night", "Time for just the two of you", weekly, Fri 19:00, 120 min.
  - `state_of_union`: "State of the Union", "An hour to check in on how you're both doing", weekly, Sun 18:00, 60 min.
  - `weekly_call`: "Weekly call", "A longer call when you're apart", weekly, Sun 19:00, 60 min.
  - `bedtime_check_in`: "After-bedtime check-in", "Twenty minutes once the kids are down", weekly, Wed 21:00, 20 min.
  - `custom`: "Something of our own", "Name it and choose a time", weekly, Sat 10:00, 60 min.
- `TogetherNeedKind.ritualProposal`, with `TogetherNeed.ritual` carrying the detail fields.
- Repository:
  - `listRituals(String relationshipId)`;
  - `proposeRitual(String relationshipId, RitualDraft draft)` → `Future<String>`;
  - `decideRitual(String ritualId, {required bool accept})`;
  - `updateRitual(String ritualId, RitualDraft draft)`;
  - `setRitualStatus(String ritualId, String status)`;
  - `skipRitualOccurrence(String eventId)`.
- `class RitualDraft { template, title, cadence, weekday, hour, minute, durationMin, tz }`, with `toPayload()`.
- `togetherRitualsProvider` (`FutureProvider.autoDispose.family<List<TogetherRitual>, String>`), which refetches on the Together signal.

- [ ] **Step 1: Failing tests**

```dart
import 'package:attune/features/together/domain/together_ritual.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a ritual row maps and reads naturally', () {
    final r = TogetherRitual.fromRow({
      'ritual_id': 'r1', 'template': 'date_night', 'title': 'Date night', 'cadence': 'weekly',
      'weekday': 5, 'local_time': '19:00', 'duration_min': 120, 'tz': 'Africa/Accra',
      'status': 'active', 'created_by': 'ama', 'proposed_to': null,
      'next_event_id': 'e1', 'next_starts_at': '2026-11-06T19:00:00+00:00',
    });
    expect(r.status, RitualStatus.active);
    expect(r.when, 'Fridays at 19:00');
    expect(r.nextStartsAt, DateTime.utc(2026, 11, 6, 19).toLocal());
    final f = TogetherRitual.fromRow({...{
      'ritual_id': 'r2', 'template': 'state_of_union', 'title': 'SOTU', 'cadence': 'fortnightly',
      'weekday': 7, 'local_time': '18:00', 'duration_min': 60, 'tz': 'UTC', 'status': 'paused',
      'created_by': 'kofi', 'proposed_to': null, 'next_event_id': null, 'next_starts_at': null}});
    expect(f.when, 'Every other Sunday at 18:00');
    expect(f.status, RitualStatus.paused);
  });

  test('templates cover each couple type, with plain names', () {
    expect(ritualTemplates.map((t) => t.id),
        containsAll(['date_night', 'state_of_union', 'weekly_call', 'bedtime_check_in', 'custom']));
    final d = ritualTemplates.firstWhere((t) => t.id == 'date_night');
    expect([d.weekday, d.hour, d.durationMin], [DateTime.friday, 19, 120]);
  });

  test('a draft sends what the server checks', () {
    const draft = RitualDraft(template: 'date_night', title: 'Date night', cadence: RitualCadence.weekly,
        weekday: 5, hour: 19, minute: 0, durationMin: 120, tz: 'Africa/Accra');
    expect(draft.toPayload(), {
      'template': 'date_night', 'title': 'Date night', 'cadence': 'weekly', 'weekday': 5,
      'local_time': '19:00', 'duration_min': 120, 'tz': 'Africa/Accra',
    });
  });
}
```

Append to `together_repository_test.dart`:

```dart
  test('ritual calls', () async {
    final g = FakeTogetherGateway({
      'list_together_rituals': (_) => const [],
      'propose_ritual': (_) => 'rit-1',
      'decide_ritual': (_) => null,
      'update_ritual': (_) => null,
      'set_ritual_status': (_) => null,
      'skip_ritual_occurrence': (_) => null,
    });
    final repo = TogetherRepository(g);
    const draft = RitualDraft(template: 'custom', title: 'Walk', cadence: RitualCadence.fortnightly,
        weekday: 6, hour: 10, minute: 30, durationMin: 60, tz: 'UTC');
    expect(await repo.proposeRitual('r1', draft), 'rit-1');
    await repo.decideRitual('rit-1', accept: true);
    expect(g.calls.last.$2, {'p_ritual_id': 'rit-1', 'p_accept': true});
    await repo.setRitualStatus('rit-1', 'paused');
    expect(g.calls.last.$2, {'p_ritual_id': 'rit-1', 'p_status': 'paused'});
    await repo.skipRitualOccurrence('e1');
    expect(g.calls.last.$2, {'p_event_id': 'e1'});
    expect(await repo.listRituals('r1'), isEmpty);
  });
```

Add `import 'package:attune/features/together/domain/together_ritual.dart';`.

- [ ] **Step 2: Run them to verify they fail.**

- [ ] **Step 3: Implement** `together_ritual.dart`:

```dart
import 'package:flutter/material.dart' show IconData, Icons;

enum RitualCadence { weekly, fortnightly }

enum RitualStatus { proposed, active, paused }

const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String _hm(int h, int m) => '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

/// A ritual of connection the couple agreed on (Phase 3). No counters:
/// only what it is, when, and the next time.
class TogetherRitual {
  const TogetherRitual({
    required this.id,
    required this.template,
    required this.title,
    required this.cadence,
    required this.weekday,
    required this.hour,
    required this.minute,
    required this.durationMin,
    required this.tz,
    required this.status,
    this.createdBy,
    this.proposedTo,
    this.nextEventId,
    this.nextStartsAt,
  });

  factory TogetherRitual.fromRow(Map<String, dynamic> r) {
    final parts = (r['local_time'] as String? ?? '00:00').split(':');
    return TogetherRitual(
      id: r['ritual_id'] as String,
      template: r['template'] as String? ?? 'custom',
      title: r['title'] as String? ?? '',
      cadence: r['cadence'] == 'fortnightly' ? RitualCadence.fortnightly : RitualCadence.weekly,
      weekday: (r['weekday'] as num).toInt(),
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
      durationMin: (r['duration_min'] as num).toInt(),
      tz: r['tz'] as String? ?? 'UTC',
      status: switch (r['status']) {
        'proposed' => RitualStatus.proposed,
        'paused' => RitualStatus.paused,
        _ => RitualStatus.active,
      },
      createdBy: r['created_by'] as String?,
      proposedTo: r['proposed_to'] as String?,
      nextEventId: r['next_event_id'] as String?,
      nextStartsAt: r['next_starts_at'] == null
          ? null
          : DateTime.parse(r['next_starts_at'] as String).toLocal(),
    );
  }

  final String id;
  final String template;
  final String title;
  final RitualCadence cadence;
  final int weekday;
  final int hour;
  final int minute;
  final int durationMin;
  final String tz;
  final RitualStatus status;
  final String? createdBy;
  final String? proposedTo;
  final String? nextEventId;
  final DateTime? nextStartsAt;

  /// "Fridays at 19:00" / "Every other Sunday at 18:00" (in its own zone).
  String get when => cadence == RitualCadence.weekly
      ? '${_days[weekday - 1]}s at ${_hm(hour, minute)}'
      : 'Every other ${_days[weekday - 1]} at ${_hm(hour, minute)}';
}

/// A starting point for a ritual (plan R6): a plain name, why, and defaults.
class RitualTemplate {
  const RitualTemplate({
    required this.id,
    required this.title,
    required this.blurb,
    required this.weekday,
    required this.hour,
    required this.durationMin,
    required this.icon,
    this.minute = 0,
    this.cadence = RitualCadence.weekly,
  });
  final String id;
  final String title;
  final String blurb;
  final RitualCadence cadence;
  final int weekday;
  final int hour;
  final int minute;
  final int durationMin;
  final IconData icon;
}

const ritualTemplates = [
  RitualTemplate(id: 'date_night', title: 'Date night', blurb: 'Time for just the two of you',
      weekday: DateTime.friday, hour: 19, durationMin: 120, icon: Icons.local_bar_outlined),
  RitualTemplate(id: 'state_of_union', title: 'State of the Union',
      blurb: "An hour to check in on how you're both doing",
      weekday: DateTime.sunday, hour: 18, durationMin: 60, icon: Icons.forum_outlined),
  RitualTemplate(id: 'weekly_call', title: 'Weekly call', blurb: "A longer call when you're apart",
      weekday: DateTime.sunday, hour: 19, durationMin: 60, icon: Icons.call_outlined),
  RitualTemplate(id: 'bedtime_check_in', title: 'After-bedtime check-in',
      blurb: 'Twenty minutes once the kids are down',
      weekday: DateTime.wednesday, hour: 21, durationMin: 20, icon: Icons.nightlight_outlined),
  RitualTemplate(id: 'custom', title: 'Something of our own', blurb: 'Name it and choose a time',
      weekday: DateTime.saturday, hour: 10, durationMin: 60, icon: Icons.favorite_border_rounded),
];

/// What the ritual editor collects.
class RitualDraft {
  const RitualDraft({
    required this.template,
    required this.title,
    required this.cadence,
    required this.weekday,
    required this.hour,
    required this.minute,
    required this.durationMin,
    required this.tz,
  });
  final String template;
  final String title;
  final RitualCadence cadence;
  final int weekday;
  final int hour;
  final int minute;
  final int durationMin;
  final String tz;

  Map<String, dynamic> toPayload() => {
    'template': template,
    'title': title.trim(),
    'cadence': cadence.name,
    'weekday': weekday,
    'local_time': _hm(hour, minute),
    'duration_min': durationMin,
    'tz': tz,
  };
}
```

Repository methods, importing `together_ritual.dart`:

```dart
  Future<List<TogetherRitual>> listRituals(String relationshipId) async {
    final rows = await _call('list_together_rituals', {'p_relationship_id': relationshipId}) as List;
    return [for (final r in rows) TogetherRitual.fromRow(Map<String, dynamic>.from(r as Map))];
  }

  Future<String> proposeRitual(String relationshipId, RitualDraft draft) async =>
      await _call('propose_ritual', {
        'p_relationship_id': relationshipId,
        'p_ritual': draft.toPayload(),
      }) as String;

  Future<void> decideRitual(String ritualId, {required bool accept}) =>
      _call('decide_ritual', {'p_ritual_id': ritualId, 'p_accept': accept});

  Future<void> updateRitual(String ritualId, RitualDraft draft) =>
      _call('update_ritual', {'p_ritual_id': ritualId, 'p_ritual': draft.toPayload()});

  Future<void> setRitualStatus(String ritualId, String status) =>
      _call('set_ritual_status', {'p_ritual_id': ritualId, 'p_status': status});

  Future<void> skipRitualOccurrence(String eventId) =>
      _call('skip_ritual_occurrence', {'p_event_id': eventId});
```

Provider:

```dart
final togetherRitualsProvider = FutureProvider.autoDispose
    .family<List<TogetherRitual>, String>((ref, relationshipId) {
      ref.listen(togetherChangeSignalProvider(relationshipId), (_, __) => ref.invalidateSelf());
      return ref.watch(togetherRepositoryProvider).listRituals(relationshipId);
    });
```

In `together_need.dart`, add `ritualProposal` to the enum (after `proposal`) and `'ritual_proposal': TogetherNeedKind.ritualProposal` to `_kinds`. Then add a `final Map<String, dynamic> detail;` field to `TogetherNeed`, filled from the row's `detail` in `fromRow`, with a default of `const {}` in the constructor, so the ritual sheet can read cadence, weekday and time.

- [ ] **Step 4: Run** `flutter test test/features/together/` → pass.

---

### Task 3: Ritual sheets

**Files:**
- Create: `lib/features/together/presentation/widgets/ritual_sheets.dart`
- Test: `test/features/together/ritual_sheets_test.dart`

**Interfaces:**
- `Future<void> showRitualTemplatesSheet(BuildContext context, String relationshipId)`. It lists the templates; choosing one opens the editor.
- `Future<void> showRitualEditor(BuildContext context, String relationshipId, {RitualTemplate? template, TogetherRitual? ritual})`. A new ritual is proposed; an existing one is updated. The editor has a title field, a cadence segmented control (Every week / Every other week), weekday chips, a time row and a length row (20 min, 45 min, 1 hour, 2 hours).
- `Future<void> showRitualSheet(BuildContext context, String relationshipId, TogetherRitual ritual)`, the manage sheet. It offers "Skip {next date}" when there is a next occurrence, Change time (which opens the editor), Pause or Resume, and End, which asks first.
- `Future<void> showRitualProposalSheet(BuildContext context, TogetherNeed need)`. It reads "{partner} suggested a ritual", then the title and when, with "We're in" and "Not now".

All of them pop with a message, invalidate `togetherRitualsProvider`, `togetherRangeProvider` and `togetherNeedsProvider`, and use the app sheet with a neutral background.

- [ ] **Step 1: Failing tests**

```dart
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart' as quiz;
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/domain/together_need.dart';
import 'package:attune/features/together/domain/together_ritual.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/ritual_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'together_repository_test.dart' show FakeTogetherGateway;

final _ritual = TogetherRitual.fromRow({
  'ritual_id': 'rit-1', 'template': 'date_night', 'title': 'Date night', 'cadence': 'weekly',
  'weekday': 5, 'local_time': '19:00', 'duration_min': 120, 'tz': 'UTC', 'status': 'active',
  'created_by': 'ama', 'proposed_to': null, 'next_event_id': 'e9',
  'next_starts_at': '2026-11-06T19:00:00+00:00',
});

Future<FakeTogetherGateway> _host(WidgetTester t, Future<void> Function(BuildContext) open) async {
  t.view.physicalSize = const Size(1170, 4200);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final g = FakeTogetherGateway({
    'propose_ritual': (_) => 'rit-2',
    'update_ritual': (_) => null,
    'set_ritual_status': (_) => null,
    'skip_ritual_occurrence': (_) => null,
    'decide_ritual': (_) => null,
  });
  await t.pumpWidget(ProviderScope(
    overrides: [
      togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
      togetherDeviceTimezoneProvider.overrideWith((ref) async => 'Africa/Accra'),
      quiz.partnerNameProvider.overrideWith((ref) async => 'Kofi'),
    ],
    child: ScreenUtilInit(designSize: const Size(375, 812), builder: (_, __) => MaterialApp(
      home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => open(c), child: const Text('open')))),
    )),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return g;
}

void main() {
  testWidgets('picking Date night proposes it to my partner with its defaults', (t) async {
    final g = await _host(t, (c) => showRitualTemplatesSheet(c, 'r1'));
    expect(find.text('State of the Union'), findsOneWidget);
    await t.tap(find.text('Date night'));
    await t.pumpAndSettle();
    expect(find.text('Suggest to Kofi'), findsOneWidget);
    await t.tap(find.text('Suggest to Kofi'));
    await t.pumpAndSettle();
    final p = g.calls.single.$2['p_ritual'] as Map;
    expect([p['template'], p['cadence'], p['weekday'], p['local_time'], p['duration_min'], p['tz']],
        ['date_night', 'weekly', 5, '19:00', 120, 'Africa/Accra']);
    expect(find.text('Sent to Kofi.'), findsOneWidget);
  });

  testWidgets('skipping a week is one tap, with no guilt', (t) async {
    final g = await _host(t, (c) => showRitualSheet(c, 'r1', _ritual));
    await t.tap(find.textContaining('Skip'));
    await t.pumpAndSettle();
    expect(g.calls.single.$2, {'p_event_id': 'e9'});
    expect(find.text('Skipped this week.'), findsOneWidget);
  });

  testWidgets('pausing and ending; ending asks first', (t) async {
    final g = await _host(t, (c) => showRitualSheet(c, 'r1', _ritual));
    await t.tap(find.text('Pause'));
    await t.pumpAndSettle();
    expect(g.calls.last.$2, {'p_ritual_id': 'rit-1', 'p_status': 'paused'});
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.text('End this ritual'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'End it'));
    await t.pumpAndSettle();
    expect(g.calls.last.$2, {'p_ritual_id': 'rit-1', 'p_status': 'ended'});
  });

  testWidgets("a partner's ritual suggestion can be accepted", (t) async {
    final need = TogetherNeed.fromRow({'need_kind': 'ritual_proposal', 'item_id': 'rit-3', 'title': 'Weekly call',
      'due_date': null, 'created_by': 'kofi', 'detail': {'template': 'weekly_call', 'cadence': 'weekly',
      'weekday': 7, 'local_time': '19:00', 'duration_min': 60, 'tz': 'Europe/London'}});
    final g = await _host(t, (c) => showRitualProposalSheet(c, need));
    expect(find.text('Kofi suggested a ritual'), findsOneWidget);
    expect(find.text('Sundays at 19:00'), findsOneWidget);
    await t.tap(find.text("We're in"));
    await t.pumpAndSettle();
    expect(g.calls.single.$2, {'p_ritual_id': 'rit-3', 'p_accept': true});
  });
}
```

- [ ] **Step 2: Run it to verify it fails.**

- [ ] **Step 3: Implement** `ritual_sheets.dart`:

```dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz_providers;
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/together_need.dart';
import '../../domain/together_ritual.dart';
import '../together_providers.dart';

const _lengths = {20: '20 min', 45: '45 min', 60: '1 hour', 120: '2 hours'};
const _short = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

Future<void> _sheet(BuildContext context, Widget child) async {
  final message = await BottomSheetUtils.showDocumentationBottomSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.neutral,
    widget: child,
  );
  if (message != null && context.mounted) context.showSuccessSnackbar(message);
}

void _refresh(WidgetRef ref) {
  ref.invalidate(togetherRitualsProvider);
  ref.invalidate(togetherRangeProvider);
  ref.invalidate(togetherNeedsProvider);
}

Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action, String done) async {
  try {
    await action();
    _refresh(ref);
    if (context.mounted) Navigator.of(context).pop(done);
  } catch (_) {
    if (context.mounted) context.showErrorSnackbar('Could not do that. Please try again.');
  }
}

Future<void> showRitualTemplatesSheet(BuildContext context, String relationshipId) =>
    _sheet(context, _TemplatesSheet(relationshipId: relationshipId));

Future<void> showRitualEditor(BuildContext context, String relationshipId,
        {RitualTemplate? template, TogetherRitual? ritual}) =>
    _sheet(context, _RitualEditor(relationshipId: relationshipId, template: template, ritual: ritual));

Future<void> showRitualSheet(BuildContext context, String relationshipId, TogetherRitual ritual) =>
    _sheet(context, _RitualSheet(relationshipId: relationshipId, ritual: ritual));

Future<void> showRitualProposalSheet(BuildContext context, TogetherNeed need) =>
    _sheet(context, _RitualProposalSheet(need: need));

class _TemplatesSheet extends StatelessWidget {
  const _TemplatesSheet({required this.relationshipId});
  final String relationshipId;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: ListView(
      children: [
        const BottomSheetHeader(title: 'A ritual for the two of you'),
        for (var i = 0; i < ritualTemplates.length; i++) ...[
          InfoRowWidget(
            title: ritualTemplates[i].title,
            subtitle: ritualTemplates[i].blurb,
            icon: ritualTemplates[i].icon,
            showAvatar: false,
            showDivider: false,
            showTrailingArrow: true,
            onTap: () {
              final navigator = Navigator.of(context);
              final host = navigator.context;
              navigator.pop();
              showRitualEditor(host, relationshipId, template: ritualTemplates[i]);
            },
          ),
          if (i < ritualTemplates.length - 1) AppDivider(),
        ],
        Gap(Spacing.xl),
      ],
    ),
  );
}

class _RitualEditor extends ConsumerStatefulWidget {
  const _RitualEditor({required this.relationshipId, this.template, this.ritual});
  final String relationshipId;
  final RitualTemplate? template;
  final TogetherRitual? ritual;
  @override
  ConsumerState<_RitualEditor> createState() => _RitualEditorState();
}

class _RitualEditorState extends ConsumerState<_RitualEditor> {
  late final TextEditingController _title;
  late RitualCadence _cadence;
  late int _weekday;
  late int _hour;
  late int _minute;
  late int _length;
  late String _templateId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final r = widget.ritual;
    final t = widget.template ?? ritualTemplates.last;
    _title = TextEditingController(text: r?.title ?? (t.id == 'custom' ? '' : t.title));
    _cadence = r?.cadence ?? t.cadence;
    _weekday = r?.weekday ?? t.weekday;
    _hour = r?.hour ?? t.hour;
    _minute = r?.minute ?? t.minute;
    _length = r?.durationMin ?? t.durationMin;
    _templateId = r?.template ?? t.id;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save(String partner) async {
    if (_busy) return;
    if (_title.text.trim().isEmpty) {
      context.showErrorSnackbar('Give it a name');
      return;
    }
    setState(() => _busy = true);
    final tz = widget.ritual?.tz ?? await ref.read(togetherDeviceTimezoneProvider.future);
    final draft = RitualDraft(template: _templateId, title: _title.text, cadence: _cadence,
        weekday: _weekday, hour: _hour, minute: _minute, durationMin: _length, tz: tz);
    final repo = ref.read(togetherRepositoryProvider);
    if (!mounted) return;
    await _run(context, ref, () async {
      if (widget.ritual == null) {
        await repo.proposeRitual(widget.relationshipId, draft);
      } else {
        await repo.updateRitual(widget.ritual!.id, draft);
      }
    }, widget.ritual == null ? 'Sent to $partner.' : 'Saved.');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final partner = ref.watch(quiz_providers.partnerNameProvider).valueOrNull ?? 'your partner';
    final time = DateFormat.jm().format(DateTime(2000, 1, 1, _hour, _minute));
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ListView(
          children: [
            BottomSheetHeader(
              title: widget.ritual == null ? 'New ritual' : 'Change ritual',
              actionLabel: widget.ritual == null ? 'Suggest to $partner' : 'Save',
              onPressed: _busy ? null : () => _save(partner),
            ),
            AppTextFormField(controller: _title, label: 'Name', textCapitalization: TextCapitalization.sentences),
            Padding(
              padding: Spacing.allMd,
              child: SegmentedButton<RitualCadence>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: RitualCadence.weekly, label: Text('Every week')),
                  ButtonSegment(value: RitualCadence.fortnightly, label: Text('Every other week')),
                ],
                selected: {_cadence},
                onSelectionChanged: (s) => setState(() => _cadence = s.first),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
              child: Wrap(
                spacing: Spacing.xs,
                children: [
                  for (var d = 1; d <= 7; d++)
                    ChoiceChip(
                      label: Text(_short[d - 1]),
                      selected: _weekday == d,
                      onSelected: (_) => setState(() => _weekday = d),
                    ),
                ],
              ),
            ),
            Gap(Spacing.sm),
            AppDivider(),
            InfoRowWidget(
              title: time,
              subtitle: 'Time',
              icon: Icons.schedule_rounded,
              showAvatar: false,
              showDivider: false,
              disableTrailing: true,
              onTap: () => showCupertinoDateTimeSheet(
                context: context,
                mode: CupertinoDatePickerMode.time,
                initialDateTime: DateTime(2000, 1, 1, _hour, _minute),
                sheetHeight: 350.h,
                onChanged: (v) => setState(() {
                  _hour = v.hour;
                  _minute = v.minute;
                }),
              ),
            ),
            AppDivider(),
            Padding(
              padding: Spacing.allMd,
              child: Wrap(
                spacing: Spacing.xs,
                children: [
                  for (final e in _lengths.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: _length == e.key,
                      onSelected: (_) => setState(() => _length = e.key),
                    ),
                ],
              ),
            ),
            Gap(Spacing.xl),
          ],
        ),
      ),
    );
  }
}

class _RitualSheet extends ConsumerWidget {
  const _RitualSheet({required this.relationshipId, required this.ritual});
  final String relationshipId;
  final TogetherRitual ritual;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(togetherRepositoryProvider);
    final next = ritual.nextStartsAt;
    final paused = ritual.status == RitualStatus.paused;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        children: [
          BottomSheetHeader(title: ritual.title),
          InfoRowWidget(
            title: ritual.when,
            subtitle: paused ? 'Paused' : (next == null ? '' : 'Next: ${DateFormat.MMMEd().format(next)}'),
            icon: Icons.event_repeat_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
          ),
          if (!paused && ritual.nextEventId != null) ...[
            AppDivider(),
            InfoRowWidget(
              title: 'Skip ${DateFormat.MMMEd().format(next!)}',
              subtitle: 'No problem — it’ll be back the week after',
              icon: Icons.redo_rounded,
              showAvatar: false,
              showDivider: false,
              disableTrailing: true,
              onTap: () => _run(context, ref, () => repo.skipRitualOccurrence(ritual.nextEventId!), 'Skipped this week.'),
            ),
          ],
          AppDivider(),
          InfoRowWidget(
            title: 'Change time',
            subtitle: '',
            icon: Icons.schedule_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
            onTap: () {
              final navigator = Navigator.of(context);
              final host = navigator.context;
              navigator.pop();
              showRitualEditor(host, relationshipId, ritual: ritual);
            },
          ),
          AppDivider(),
          InfoRowWidget(
            title: paused ? 'Resume' : 'Pause',
            subtitle: '',
            icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
            onTap: () => _run(context, ref,
                () => repo.setRitualStatus(ritual.id, paused ? 'active' : 'paused'),
                paused ? 'Back on.' : 'Paused.'),
          ),
          AppDivider(),
          InfoRowWidget(
            title: 'End this ritual',
            subtitle: '',
            icon: Icons.close_rounded,
            iconColor: Theme.of(context).colorScheme.error,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('End this ritual?'),
                  content: const Text('Its future weeks come off both calendars.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Keep it')),
                    TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('End it')),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                await _run(context, ref, () => repo.setRitualStatus(ritual.id, 'ended'), 'Ended.');
              }
            },
          ),
          Gap(Spacing.xl),
        ],
      ),
    );
  }
}

class _RitualProposalSheet extends ConsumerWidget {
  const _RitualProposalSheet({required this.need});
  final TogetherNeed need;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(quiz_providers.partnerNameProvider).valueOrNull ?? 'Your partner';
    final d = need.detail;
    final ritual = TogetherRitual.fromRow({
      'ritual_id': need.itemId, 'template': d['template'], 'title': need.title,
      'cadence': d['cadence'], 'weekday': d['weekday'], 'local_time': d['local_time'],
      'duration_min': d['duration_min'], 'tz': d['tz'], 'status': 'proposed',
    });
    final repo = ref.read(togetherRepositoryProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        children: [
          BottomSheetHeader(title: '$partner suggested a ritual'),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
            child: Text(need.title, style: Theme.of(context).textTheme.titleMedium),
          ),
          InfoRowWidget(
            title: ritual.when,
            subtitle: _lengths[ritual.durationMin] ?? '${ritual.durationMin} min',
            icon: Icons.event_repeat_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
          ),
          AppDivider(),
          InfoRowWidget(
            title: "We're in",
            subtitle: 'It goes on both calendars every week',
            icon: Icons.check_circle_outline_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
            onTap: () => _run(context, ref, () => repo.decideRitual(need.itemId, accept: true), 'On your calendars.'),
          ),
          AppDivider(),
          InfoRowWidget(
            title: 'Not now',
            subtitle: '',
            icon: Icons.close_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
            onTap: () => _run(context, ref, () => repo.decideRitual(need.itemId, accept: false), 'Sent.'),
          ),
          Gap(Spacing.xl),
        ],
      ),
    );
  }
}
```

The `when` text uses 24-hour time to match the summary. The editor shows the locale time. The template sheet's header is "A ritual for the two of you".

- [ ] **Step 4: Run** `flutter test test/features/together/ritual_sheets_test.dart` → pass.

---

### Task 4: Rituals on the Agenda

**Files:**
- Modify: `lib/features/together/presentation/screens/together_screen.dart`
- Modify: `lib/features/together/presentation/widgets/together_item_row.dart` (an icon for `ritual_occurrence`)
- Test: additions to `together_screen_test.dart`

**Behaviour:**
- A **Rituals** section sits after This week and before Coming up.
  - It holds one row per ritual: the title, with the subtitle "Next: Fri 6 Nov · 19:00", "Waiting for Kofi" (proposed by me) or "Paused".
  - Tapping a row opens `showRitualSheet`; a ritual still in proposal opens nothing.
  - A final row, "Add a ritual", opens `showRitualTemplatesSheet`.
  - With no rituals, the section shows only "Add a ritual", with the subtitle "Date night, a weekly check-in…".
- **"Needs you"** gets `ritualProposal` rows ("{partner} suggested a ritual"), which open `showRitualProposalSheet`.
- **The empty state's third row** becomes "Set up a ritual", which opens the templates sheet, in place of "Plan something together". The FAB still plans things.
- **`TogetherItemRow`:** `sourceRef['kind'] == 'ritual_occurrence'` shows `Icons.event_repeat_rounded`.
- **Tapping a ritual occurrence** opens the event editor, so a partner can move just that week.

- [ ] **Step 1: Failing tests.** Extend `_pump` with a `rituals` parameter and a `'list_together_rituals': (_) => rituals` handler. Then append:

```dart
  testWidgets('rituals sit on the Agenda with their next time, and one can be added', (t) async {
    await _pump(t, upcoming: [_row('rent', '2026-11-02', title: 'Rent')], rituals: [
      {'ritual_id': 'rit-1', 'template': 'date_night', 'title': 'Date night', 'cadence': 'weekly',
       'weekday': 5, 'local_time': '19:00', 'duration_min': 120, 'tz': 'UTC', 'status': 'active',
       'created_by': 'ama', 'proposed_to': null, 'next_event_id': 'e9', 'next_starts_at': '2026-11-06T19:00:00+00:00'},
    ]);
    await t.scrollUntilVisible(find.text('Add a ritual'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Rituals'), findsOneWidget);
    expect(find.text('Date night'), findsOneWidget);
    await t.tap(find.text('Add a ritual'));
    await t.pumpAndSettle();
    expect(find.text('A ritual for the two of you'), findsOneWidget);
  });

  testWidgets('a ritual suggestion waits in Needs you', (t) async {
    await _pump(t, needs: [
      {'need_kind': 'ritual_proposal', 'item_id': 'rit-3', 'title': 'Weekly call', 'due_date': null,
       'created_by': 'kofi', 'detail': {'template': 'weekly_call', 'cadence': 'weekly', 'weekday': 7,
       'local_time': '19:00', 'duration_min': 60, 'tz': 'UTC'}},
    ]);
    expect(find.text('Weekly call'), findsOneWidget);
    await t.tap(find.text('Weekly call'));
    await t.pumpAndSettle();
    expect(find.text('Kofi suggested a ritual'), findsOneWidget);
  });
```

Also update the existing "a new couple sees three ways to start" test: expect `'Set up a ritual'` instead of `'Plan something together'`.

- [ ] **Step 2: Run them to verify they fail.**

- [ ] **Step 3: Implement.**
  - In `_agenda`, watch `togetherRitualsProvider(relationshipId)` with a `const []` fallback.
  - Count the agenda as empty only when the agenda, `needs` and `rituals` are all empty.
  - Insert the Rituals section. For rows, use `InfoRowWidget` with `Icons.event_repeat_rounded` and the subtitle built from the ritual state. For a timed next occurrence use `'Next: ${DateFormat.MMMEd().format(next)} · ${DateFormat.jm().format(next)}'`. For a proposed ritual created by me use `'Waiting for $partnerName'`; for a paused one, `'Paused'`.
  - In `_needRow`, add the `ritualProposal` case: icon `Icons.event_repeat_rounded`, subtitle `'$partnerName suggested a ritual'`. In `_openNeed`, add the case that calls `showRitualProposalSheet`.
  - In `_EmptyTogether`, rename the third row to 'Set up a ritual' with `Icons.event_repeat_rounded`. Its `onTap` comes from a new constructor callback, `onRitual`.
  - In `together_item_row.dart` `_icon`, inside the event branch's kind switch, add `'ritual_occurrence' => Icons.event_repeat_rounded,`.
  - Imports: `together_ritual.dart` and `ritual_sheets.dart`.

- [ ] **Step 4: Run** `flutter test test/features/together/` → pass.

---

### Task 5: Push taps, close-out

- [ ] **Push routes.** Add `together_ritual` and `together_ritual_reply` to the `notification_config.dart` fall-through group, and extend the route test's type list (RED, then GREEN).
- [ ] **Overrides.** `planning_test_app.dart`'s `_EmptyTogetherGateway` already returns `[]` for any call, so the rituals list is empty and nothing changes. Check that the Conversations and Planning tests still pass.
- [ ] **Spec.** Add "### 8.6 Phase 3 rulings" (R1–R6).
- [ ] **Full verification:**
  - `flutter test` (no failures);
  - analyzer clean for `lib/features/together` and `lib/core/notifications`;
  - all five Together contract files on the harness;
  - golden previews of the Agenda with rituals, the template sheet and the manage sheet, inspected and then deleted.
- [ ] **Report the deploys:** migrations through `20261014140000`, and cron `together_rituals`.
