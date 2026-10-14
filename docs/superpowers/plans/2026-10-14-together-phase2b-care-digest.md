# Together Phase 2b — Big-day care loop, daily summary, push budget: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Help partners turn toward each other around the days that matter, without noise:
- **Big days.** Either partner can mark their own event as a big day, such as an interview, exam or appointment. The other partner then sees a care card the evening before ("a word of luck?") and after it ends ("ask how it went"). The card opens chat with a ready draft that they can edit.
- **A morning summary.** One push at 08:00 in each partner's own zone, sent only when something involves them that day. On Sundays it covers the week ahead.
- **A hard budget.** At most one scheduled Together push per person per local day, enforced by the database.
- **Settings.** Each partner can turn off the morning summary, or the big-day nudges for their partner's days.

**Architecture:**
- **Server:**
  - a `together_member_prefs` table that only its owner can read or write, through RPCs;
  - `together_digest_lines()`, which builds the summary from fixed templates, never AI;
  - `together_enqueue_daily()`, which runs every 15 minutes and sends inside the 08:00–10:00 local window, keyed `together_daily:<user>:<local date>` so it can only go out once a day.
- **Client:**
  - care cards are computed from items the Agenda already loads (`togetherCareCards()`), so the big-day flow itself needs no new server call;
  - `ChatScreen` gains an optional `initialDraft`;
  - the event editor gains a "big day" toggle;
  - a settings sheet holds the two prefs.

**Tech Stack:** Supabase Postgres 17 (pg_cron), Flutter/Riverpod 2, flutter_test, SQL contracts on the local PG17 harness.

**Spec:** `docs/superpowers/specs/2026-10-14-together-hub-design.md`: §6.1 (digest), §6.2 (big-day care loop, fixed templates), D9 (push budget), §3.7, §5.3 (`together_member_prefs`). The base is Phases 0–2a, uncommitted on main.

## Global Constraints

- Work directly on `main`. No commits unless asked. Re-read files before editing them. Format only touched files; revert any reflow of the owner's code.
- Migrations start at `20261014130000`.
- **Hard rules:**
  - Care-loop and summary copy are fixed templates, never AI-written (D6).
  - No counts or tallies (§3.1). "A suggestion is waiting for you" is allowed; "you have 3 overdue" is not.
  - Only a partner's **shared** big day triggers care. A busy-only or private event never appears in the other partner's summary.
  - At most one scheduled `together_daily` push per user per local day. User-set alarms (`together_event`, R6 of 1a) and partner-initiated pushes (2a) are outside the budget.
- **Chat is a shared core screen.** The only change there is the additive `initialDraft` parameter, plus the route reading `?draft=`. Nothing else in chat changes.

## Rulings (decided while planning)

- **R1:** The summary goes out at **08:00 local every day**, and on **Sundays** it is the week ahead. This replaces the earlier "Sunday-evening week ahead plus morning today", which would have sent two pushes on Sundays and broken the budget. Cost if wrong: a schedule tweak.
- **R2:** Care cards are **in-app**, shown in Today. Their push is the morning summary line on the partner's big day: "Kofi's big day: Interview at 10:00 — a word of luck?". Sending separate evening-before and after pushes would break the one-per-day budget. Cost if wrong: one extra push type, once the budget is redefined.
- **R3:** Reminder pushes (`reminder_upcoming`, the existing daily pipeline) stay separate for now. The budget invariant covers Together's own scheduled pushes (`together_daily`). Folding reminders in waits for the Phase 1a backfill of reminders into `couple_events`. Cost if wrong: a reminder and a summary can both arrive on the same day.
- **R4:** The summary window is 08:00–10:00 local. A plan added later in the day doesn't trigger an afternoon "Today" push. Cost if wrong: none.
- **R5:** A big day is `kind = 'big_day'`. It can be set only when the event is just for me (`participants = [me]`) and shared. The server already allows that kind; the client offers the toggle only in that case.
- **R6:** Care windows:
  - **before:** from 18:00 the evening before until the start;
  - **after:** from the end (start + 1h if there is no end; 18:00 for all-day events) until 24 hours later.
  - Multi-day continuation rows collapse into one card.

## Review Focus

1. **A busy-only or private event of the partner** never appears in my summary. Pinned in Task 1's contract.
2. **Running the cron twice the same morning, or at 08:05 and 09:50,** sends one push. Pinned in Task 1's contract.
3. **A partner whose summary is off** gets nothing, and one with care nudges off gets no big-day line. Pinned in Task 1's contract.
4. **The before card disappears once the event starts; the after card disappears 24h after it ends.** Pinned in Task 4's tests.
5. **A draft passed to chat** fills the composer instead of a saved draft, and an empty one changes nothing. Pinned in Task 2's test.

---

### Task 1: Prefs, summary and budget (SQL)

**Files:**
- Create: `supabase/migrations/20261014130000_together_daily.sql`
- Create: `supabase/tests/together_daily_contracts.sql`

**Interfaces:**
- `get_together_prefs(p_relationship_id uuid) RETURNS jsonb`, returning `{daily_summary, care_nudges}`. Both default to true when there is no row.
- `set_together_prefs(p_relationship_id uuid, p_daily_summary boolean, p_care_nudges boolean) RETURNS jsonb`.
- `together_digest_lines(p_relationship_id uuid, p_user uuid, p_from date, p_to date, p_tz text, p_care boolean, p_week boolean) RETURNS text[]`.
- `together_enqueue_daily(p_now timestamptz DEFAULT now()) RETURNS int`, run by cron job `together_daily` every 15 minutes.
- Push metadata: `type = 'together_daily'` and `relationship_id`.

- [ ] **Step 1: Write the failing contracts**

```sql
-- Together Phase 2b contracts: prefs, morning summary, push budget.
BEGIN;
INSERT INTO auth.users (id) VALUES ('7e100000-0000-0000-0000-0000000000a1'), ('7e100000-0000-0000-0000-0000000000b2') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7e100000-0000-0000-0000-0000000000a1', '+233290000001', 'Ama'),
  ('7e100000-0000-0000-0000-0000000000b2', '+233290000002', 'Kofi') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('7e200000-0000-0000-0000-000000000001', '7e100000-0000-0000-0000-0000000000a1',
        '7e100000-0000-0000-0000-0000000000b2', 'active', now(), now()) ON CONFLICT (id) DO NOTHING;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;

-- Fixtures on Tue 2026-11-10 (UTC zone for both): Ama's dinner with Kofi,
-- Kofi's shared big day, Kofi's busy-only and private events.
DO $$
BEGIN
  PERFORM pg_temp.as_user('7e100000-0000-0000-0000-0000000000a1');
  PERFORM public.create_couple_event('7e200000-0000-0000-0000-000000000001',
    '{"title":"Dinner at Buka","all_day":false,"starts_at":"2026-11-10T19:00:00Z","tz":"UTC","participant_ids":["7e100000-0000-0000-0000-0000000000a1","7e100000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM pg_temp.as_user('7e100000-0000-0000-0000-0000000000b2');
  PERFORM public.create_couple_event('7e200000-0000-0000-0000-000000000001',
    '{"title":"Interview","kind":"big_day","all_day":false,"starts_at":"2026-11-10T10:00:00Z","tz":"UTC","participant_ids":["7e100000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM public.create_couple_event('7e200000-0000-0000-0000-000000000001',
    '{"title":"Therapy","all_day":false,"starts_at":"2026-11-10T15:00:00Z","tz":"UTC","visibility":"busy_only","participant_ids":["7e100000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM public.create_couple_event('7e200000-0000-0000-0000-000000000001',
    '{"title":"Ring shopping","all_day":true,"start_date":"2026-11-10","visibility":"private","participant_ids":["7e100000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 1. Ama's morning summary: her dinner and Kofi's big day; nothing private or busy.
DO $$
DECLARE v_body text; v_title text; v_n int;
BEGIN
  PERFORM public.together_enqueue_daily('2026-11-10T08:05:00Z');
  SELECT metadata->>'title', metadata->>'body' INTO v_title, v_body FROM public.scheduled_notifications
  WHERE source_key = 'together_daily:7e100000-0000-0000-0000-0000000000a1:2026-11-10';
  IF v_title <> 'Today' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: title %', v_title; END IF;
  IF v_body NOT LIKE '%19:00 Dinner at Buka%' OR v_body NOT LIKE '%Kofi''s big day: Interview at 10:00%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: summary body %', v_body;
  END IF;
  IF v_body LIKE '%Therapy%' OR v_body LIKE '%Ring%' OR v_body LIKE '%Busy%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: summary leaks a busy/private event: %', v_body;
  END IF;
  -- once per local day, even across the window
  PERFORM public.together_enqueue_daily('2026-11-10T08:05:00Z');
  PERFORM public.together_enqueue_daily('2026-11-10T09:50:00Z');
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
  WHERE user_id = '7e100000-0000-0000-0000-0000000000a1' AND metadata->>'type' = 'together_daily'
    AND source_key LIKE 'together_daily:%:2026-11-10';
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % summaries in one day', v_n; END IF;
END $$;

-- 2. Outside the window nothing is sent; Kofi's own big day is his plan, not a nudge to himself.
DO $$
DECLARE v_n int; v_body text;
BEGIN
  PERFORM public.together_enqueue_daily('2026-11-11T07:30:00Z');
  PERFORM public.together_enqueue_daily('2026-11-11T11:00:00Z');
  SELECT count(*) INTO v_n FROM public.scheduled_notifications WHERE source_key LIKE 'together_daily:%:2026-11-11';
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: summary outside 08:00-10:00'; END IF;
  SELECT metadata->>'body' INTO v_body FROM public.scheduled_notifications
  WHERE source_key = 'together_daily:7e100000-0000-0000-0000-0000000000b2:2026-11-10';
  IF v_body LIKE '%big day%' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: nudged about own big day: %', v_body; END IF;
END $$;

-- 3. Prefs: owner-only; summary off → nothing; care off → no big-day line.
DO $$
DECLARE v_prefs jsonb; v_n int; v_body text;
BEGIN
  PERFORM pg_temp.as_user('7e100000-0000-0000-0000-0000000000a1');
  v_prefs := public.get_together_prefs('7e200000-0000-0000-0000-000000000001');
  IF v_prefs <> '{"daily_summary": true, "care_nudges": true}'::jsonb THEN RAISE EXCEPTION 'CONTRACT VIOLATED: defaults %', v_prefs; END IF;
  PERFORM public.set_together_prefs('7e200000-0000-0000-0000-000000000001', true, false);
  PERFORM pg_temp.as_user('7e100000-0000-0000-0000-0000000000b2');
  PERFORM public.set_together_prefs('7e200000-0000-0000-0000-000000000001', false, true);
  PERFORM set_config('request.jwt.claims', '', true);

  -- Thursday: another big day for Kofi and a dinner for both
  PERFORM pg_temp.as_user('7e100000-0000-0000-0000-0000000000b2');
  PERFORM public.create_couple_event('7e200000-0000-0000-0000-000000000001',
    '{"title":"Exam","kind":"big_day","all_day":true,"start_date":"2026-11-12","participant_ids":["7e100000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM public.create_couple_event('7e200000-0000-0000-0000-000000000001',
    '{"title":"Cinema","all_day":true,"start_date":"2026-11-12","participant_ids":["7e100000-0000-0000-0000-0000000000a1","7e100000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM public.together_enqueue_daily('2026-11-12T08:05:00Z');
  SELECT count(*) INTO v_n FROM public.scheduled_notifications WHERE source_key = 'together_daily:7e100000-0000-0000-0000-0000000000b2:2026-11-12';
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: summary sent with daily_summary off'; END IF;
  SELECT metadata->>'body' INTO v_body FROM public.scheduled_notifications WHERE source_key = 'together_daily:7e100000-0000-0000-0000-0000000000a1:2026-11-12';
  IF v_body IS NULL OR v_body NOT LIKE '%Cinema%' OR v_body LIKE '%big day%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: care-off summary %', v_body;
  END IF;
END $$;

-- 4. Sunday is the week ahead; nothing at all → no push.
DO $$
DECLARE v_title text; v_body text;
BEGIN
  PERFORM public.together_enqueue_daily('2026-11-08T08:05:00Z');
  SELECT metadata->>'title', metadata->>'body' INTO v_title, v_body FROM public.scheduled_notifications
  WHERE source_key = 'together_daily:7e100000-0000-0000-0000-0000000000a1:2026-11-08';
  IF v_title <> 'Your week together' OR v_body NOT LIKE '%Tue%Dinner at Buka%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: week ahead % / %', v_title, v_body;
  END IF;
  PERFORM public.together_enqueue_daily('2026-12-01T08:05:00Z');
  IF EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE source_key LIKE 'together_daily:%:2026-12-01') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an empty summary was sent';
  END IF;
END $$;

ROLLBACK;
```

- [ ] **Step 2: Run to verify it fails:** `scratchpad/pg/run.sh supabase/tests/together_daily_contracts.sql` → `together_enqueue_daily does not exist`.

- [ ] **Step 3: Write the migration** `20261014130000_together_daily.sql`

```sql
-- Together Phase 2b: per-partner prefs, the morning summary, and the
-- one-scheduled-push-per-day budget (spec D9, plan rulings R1–R4).
-- All copy is fixed templates (D6). Only shared events reach a partner.

CREATE TABLE public.together_member_prefs (
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  daily_summary boolean NOT NULL DEFAULT true,
  care_nudges boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (relationship_id, user_id)
);
ALTER TABLE public.together_member_prefs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.together_member_prefs FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.get_together_prefs(p_relationship_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_me uuid := public.together_actor(p_relationship_id); v_row public.together_member_prefs;
BEGIN
  SELECT * INTO v_row FROM public.together_member_prefs
  WHERE relationship_id = p_relationship_id AND user_id = v_me;
  RETURN jsonb_build_object('daily_summary', coalesce(v_row.daily_summary, true),
                            'care_nudges', coalesce(v_row.care_nudges, true));
END;
$$;

CREATE FUNCTION public.set_together_prefs(p_relationship_id uuid, p_daily_summary boolean, p_care_nudges boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_me uuid := public.together_actor(p_relationship_id);
BEGIN
  IF p_daily_summary IS NULL OR p_care_nudges IS NULL THEN PERFORM public.together_fail('invalid_input'); END IF;
  INSERT INTO public.together_member_prefs (relationship_id, user_id, daily_summary, care_nudges, updated_at)
  VALUES (p_relationship_id, v_me, p_daily_summary, p_care_nudges, now())
  ON CONFLICT (relationship_id, user_id) DO UPDATE
    SET daily_summary = EXCLUDED.daily_summary, care_nudges = EXCLUDED.care_nudges, updated_at = now();
  RETURN jsonb_build_object('daily_summary', p_daily_summary, 'care_nudges', p_care_nudges);
END;
$$;

-- The summary's lines for one person between two dates, in their zone.
-- Theirs: confirmed events they're in that they can see. Their partner's:
-- shared big days only (care on). Today only: a suggestion waiting.
CREATE FUNCTION public.together_digest_lines(
  p_relationship_id uuid, p_user uuid, p_from date, p_to date, p_tz text,
  p_care boolean, p_week boolean
) RETURNS text[] LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH occ AS (
    SELECT ce.*, d.d AS on_day,
      CASE WHEN ce.all_day THEN NULL
           WHEN ce.rrule IS NULL THEN ce.starts_at
           ELSE ((d.d + (ce.starts_at AT TIME ZONE ce.tz)::time) AT TIME ZONE ce.tz) END AS at
    FROM public.couple_events ce
    CROSS JOIN LATERAL public.together_event_dates(ce, p_from, p_to) AS d(d)
    WHERE ce.relationship_id = p_relationship_id AND ce.deleted_at IS NULL
      AND ce.status = 'confirmed'
      -- one line per event: a multi-day one on its first day in range
      AND (ce.rrule IS NOT NULL OR d.d = greatest(p_from,
            CASE WHEN ce.all_day THEN ce.start_date ELSE (ce.starts_at AT TIME ZONE ce.tz)::date END))
  ), lines AS (
    SELECT on_day, at,
      CASE WHEN p_week THEN to_char(on_day, 'Dy') || ': ' ELSE '' END
      || CASE WHEN at IS NULL THEN '' ELSE to_char(at AT TIME ZONE p_tz, 'HH24:MI') || ' ' END
      || title AS line
    FROM occ
    WHERE p_user = ANY (participant_ids) AND (visibility = 'shared' OR created_by = p_user)
    UNION ALL
    SELECT on_day, at,
      CASE WHEN p_week THEN to_char(on_day, 'Dy') || ': ' ELSE '' END
      || public.together_name(created_by) || '''s big day: ' || title
      || CASE WHEN at IS NULL THEN '' ELSE ' at ' || to_char(at AT TIME ZONE p_tz, 'HH24:MI') END
      || ' — a word of luck?'
    FROM occ
    WHERE p_care AND kind = 'big_day' AND visibility = 'shared'
      AND created_by <> p_user AND NOT (p_user = ANY (participant_ids))
    UNION ALL
    SELECT p_from, NULL::timestamptz, 'A suggestion is waiting for you'
    WHERE NOT p_week AND EXISTS (
      SELECT 1 FROM public.couple_events ce
      WHERE ce.relationship_id = p_relationship_id AND ce.deleted_at IS NULL
        AND ce.status = 'proposed' AND ce.proposed_to = p_user AND ce.proposal_expires_at > now())
  )
  SELECT coalesce(array_agg(line ORDER BY on_day, at NULLS FIRST, line), '{}') FROM lines
$$;
REVOKE ALL ON FUNCTION public.together_digest_lines(uuid, uuid, date, date, text, boolean, boolean) FROM PUBLIC, anon, authenticated;

-- Every 15 minutes: each partner whose local time is 08:00–10:00 and who
-- has the summary on gets at most one push for their local day.
CREATE FUNCTION public.together_enqueue_daily(p_now timestamptz DEFAULT now())
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n int;
BEGIN
  INSERT INTO public.scheduled_notifications
    (user_id, notification_type, scheduled_for, status, metadata, source_key)
  SELECT m.user_id, 'immediate', p_now, 'pending',
    jsonb_build_object(
      'type', 'together_daily', 'relationship_id', m.relationship_id,
      'title', CASE WHEN m.week THEN 'Your week together' ELSE 'Today' END,
      'body', left(array_to_string(l.lines[1:3], ' · ')
                   || CASE WHEN cardinality(l.lines) > 3 THEN ' · and more' ELSE '' END, 160)),
    'together_daily:' || m.user_id || ':' || m.local_day
  FROM (
    SELECT r.id AS relationship_id, u AS user_id, z.tz,
           (p_now AT TIME ZONE z.tz)::date AS local_day,
           extract(isodow FROM (p_now AT TIME ZONE z.tz)) = 7 AS week,
           coalesce(p.daily_summary, true) AS summary_on,
           coalesce(p.care_nudges, true) AS care_on
    FROM public.relationships r
    CROSS JOIN LATERAL unnest(ARRAY[r.user_a, r.user_b]) AS u
    CROSS JOIN LATERAL (SELECT coalesce((SELECT s.timezone FROM public.planning_member_settings s
                         WHERE s.relationship_id = r.id AND s.user_id = u), 'UTC') AS tz) z
    LEFT JOIN public.together_member_prefs p ON p.relationship_id = r.id AND p.user_id = u
    WHERE r.status = 'active' AND r.chat_archived_at IS NULL AND u IS NOT NULL
      AND (p_now AT TIME ZONE z.tz)::time >= time '08:00'
      AND (p_now AT TIME ZONE z.tz)::time < time '10:00'
  ) m
  CROSS JOIN LATERAL (
    SELECT public.together_digest_lines(m.relationship_id, m.user_id, m.local_day,
      CASE WHEN m.week THEN m.local_day + 6 ELSE m.local_day END, m.tz, m.care_on, m.week) AS lines
  ) l
  WHERE m.summary_on AND cardinality(l.lines) > 0
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.together_enqueue_daily(timestamptz) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.get_together_prefs(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_together_prefs(uuid, boolean, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_together_prefs(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_together_prefs(uuid, boolean, boolean) TO authenticated;

DO $$
BEGIN
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'together_daily';
END;
$$;
SELECT cron.schedule('together_daily', '*/15 * * * *', $$ SELECT public.together_enqueue_daily(); $$);
```

- [ ] **Step 4: Verify.** Run `run.sh` against all four Together contract files → PASS.

---

### Task 2: Chat opens with a draft

**Files:**
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (constructor and `_restoreDraft`)
- Modify: `lib/app/routing/app_router.dart` (the `chatScreen` route reads `?draft=`)
- Test: `test/features/chat/chat_screen_initial_draft_test.dart`

- [ ] **Step 1: Write the failing test.** Copy `pumpChat` and `tearDownChat` from `test/features/chat/chat_screen_initial_jump_test.dart` (lines 14–62), replacing the `initialJumpToMessageId` parameter with `String? initialDraft`, which is passed as `initialDraft:`.

```dart
  testWidgets('a draft passed in fills the composer', (tester) async {
    final repo = FakeChatRepository();
    final container = await pumpChat(tester, repo, initialDraft: 'How did the interview go?');
    expect(find.text('How did the interview go?'), findsOneWidget);
    await tearDownChat(tester, container);
  });

  testWidgets('no draft leaves the composer alone', (tester) async {
    final repo = FakeChatRepository();
    final container = await pumpChat(tester, repo);
    expect(find.text('How did the interview go?'), findsNothing);
    await tearDownChat(tester, container);
  });

  test('the chat route passes ?draft= through', () {
    final src = File('lib/app/routing/app_router.dart').readAsStringSync();
    final at = src.indexOf("name: 'chatScreen'");
    expect(src.substring(at, src.indexOf('GoRoute(', at)), contains("queryParameters['draft']"));
  });
```

Add `import 'dart:io';`. If `FakeChatRepository()` needs arguments, mirror `chat_screen_initial_jump_test.dart`'s construction.

- [ ] **Step 2: Run it to verify it fails** (no `initialDraft` parameter).

- [ ] **Step 3: Implement.**
  - In `ChatScreen`, add an optional `this.initialDraft` with the field `final String? initialDraft;` and this doc comment:

```dart
  /// Text to start the composer with (e.g. Together's "How did it go?"),
  /// used instead of a saved draft. Null or empty: the saved draft as usual.
```

  - In `_restoreDraft`, at the top after the user check:

```dart
    final given = widget.initialDraft;
    if (given != null && given.isNotEmpty) {
      _controller.value = TextEditingValue(
        text: given,
        selection: TextSelection.collapsed(offset: given.length),
      );
      return;
    }
```

  - In the router's `chatScreen` builder, add `initialDraft: state.uri.queryParameters['draft'],`.

- [ ] **Step 4: Run** `flutter test test/features/chat/` → pass.

---

### Task 3: Marking a big day in the editor

**Files:**
- Modify: `lib/features/together/presentation/widgets/couple_event_sheet.dart`
- Test: append to `test/features/together/couple_event_sheet_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
  testWidgets('a shared event just for me can be marked a big day', (t) async {
    final g = await _open(t);
    await t.enterText(find.byType(TextField).first, 'Interview');
    await t.tap(find.text('Me').first);
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: find.widgetWithText(InfoRowWidget, 'A big day for me'), matching: find.byType(Switch)));
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    final payload = g.calls.firstWhere((c) => c.$1 == 'create_couple_event').$2['p_event'] as Map;
    expect(payload['kind'], 'big_day');
    expect(payload['participant_ids'], ['ama']);
  });

  testWidgets('the big-day toggle only shows for a shared event just for me', (t) async {
    await _open(t);
    expect(find.text('A big day for me'), findsNothing, reason: 'Who is Both by default');
  });
```

- [ ] **Step 2: Run it to verify it fails.**

- [ ] **Step 3: Implement.** Right after the "Who it's for" segmented control and its propose block, add:

```dart
            if (shared && _who == _Who.me && !_proposing) ...[
              AppDivider(),
              InfoRowWidget(
                title: 'A big day for me',
                subtitle: '$partnerName will be reminded to wish you luck',
                icon: Icons.star_outline_rounded,
                showAvatar: false,
                showDivider: false,
                isToggleItem: true,
                toggleValue: _kind == 'big_day',
                onToggleChanged: (v) => setState(() => _kind = v ? 'big_day' : 'event'),
              ),
            ],
```

In `_save`, before building the draft, add `if (_kind == 'big_day' && !(shared && _who == _Who.me)) _kind = 'event';`. This means a big day can't silently survive switching to Both or to private. `shared` here is `_visibility == TogetherVisibility.shared`.

- [ ] **Step 4: Run** `flutter test test/features/together/couple_event_sheet_test.dart` → pass.

---

### Task 4: Care cards in Today

**Files:**
- Create: `lib/features/together/domain/together_care.dart`
- Modify: `lib/features/together/domain/together_agenda.dart` (`TogetherAgenda.careCards` and the `me` parameter)
- Modify: `lib/features/together/presentation/together_providers.dart` (pass `me`)
- Modify: `lib/features/together/presentation/screens/together_screen.dart` (render the cards and their action)
- Test: `test/features/together/together_care_test.dart`, plus additions to `together_screen_test.dart`

**Interfaces:**
- Produces:
  - `enum CarePhase { before, after }`;
  - `class CareCard { final TogetherItem item; final CarePhase phase; }`;
  - `List<CareCard> togetherCareCards(List<TogetherItem> items, {required String? me, required DateTime now})`;
  - `String careDraft(CareCard c)`, the fixed copy;
  - `TogetherAgenda.careCards`.

- [ ] **Step 1: Write the failing tests**

`test/features/together/together_care_test.dart`:

```dart
import 'package:attune/features/together/domain/together_care.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:flutter_test/flutter_test.dart';

TogetherItem _big({String createdBy = 'kofi', TogetherVisibility visibility = TogetherVisibility.shared,
    DateTime? start, DateTime? end, bool allDay = false, String kind = 'big_day', bool continuation = false}) =>
  TogetherItem(
    kind: TogetherItemKind.event, id: 'b1',
    date: DateTime(2026, 11, 10), startsAt: allDay ? null : (start ?? DateTime(2026, 11, 10, 10)),
    endsAt: allDay ? null : end, allDay: allDay, title: 'Interview',
    participantIds: [createdBy], createdBy: createdBy, visibility: visibility,
    sourceRef: {'kind': kind, if (continuation) 'continuation': true},
  );

void main() {
  test('the evening before brings a word-of-luck card, until it starts', () {
    expect(togetherCareCards([_big()], me: 'ama', now: DateTime(2026, 11, 9, 17, 59)), isEmpty);
    expect(togetherCareCards([_big()], me: 'ama', now: DateTime(2026, 11, 9, 18)).single.phase, CarePhase.before);
    expect(togetherCareCards([_big()], me: 'ama', now: DateTime(2026, 11, 10, 9, 59)).single.phase, CarePhase.before);
    expect(togetherCareCards([_big()], me: 'ama', now: DateTime(2026, 11, 10, 10, 30)), isEmpty);
  });

  test('after it ends, ask how it went for a day', () {
    final item = _big(end: DateTime(2026, 11, 10, 11));
    expect(togetherCareCards([item], me: 'ama', now: DateTime(2026, 11, 10, 11)).single.phase, CarePhase.after);
    expect(togetherCareCards([item], me: 'ama', now: DateTime(2026, 11, 11, 10, 59)).single.phase, CarePhase.after);
    expect(togetherCareCards([item], me: 'ama', now: DateTime(2026, 11, 11, 11, 1)), isEmpty);
  });

  test('no end: an hour after it starts; all-day: from 18:00', () {
    expect(togetherCareCards([_big()], me: 'ama', now: DateTime(2026, 11, 10, 11)).single.phase, CarePhase.after);
    expect(togetherCareCards([_big(allDay: true)], me: 'ama', now: DateTime(2026, 11, 10, 18)).single.phase, CarePhase.after);
    expect(togetherCareCards([_big(allDay: true)], me: 'ama', now: DateTime(2026, 11, 10, 12)), isEmpty);
  });

  test("only my partner's shared big days, once each", () {
    final now = DateTime(2026, 11, 9, 20);
    expect(togetherCareCards([_big(createdBy: 'ama')], me: 'ama', now: now), isEmpty);
    expect(togetherCareCards([_big(visibility: TogetherVisibility.busyOnly)], me: 'ama', now: now), isEmpty);
    expect(togetherCareCards([_big(kind: 'event')], me: 'ama', now: now), isEmpty);
    expect(togetherCareCards([_big(), _big(continuation: true)], me: 'ama', now: now), hasLength(1));
  });

  test('drafts are fixed, warm and editable', () {
    final before = togetherCareCards([_big()], me: 'ama', now: DateTime(2026, 11, 9, 20)).single;
    expect(careDraft(before), 'Good luck with Interview. You’ve got this!');
    final after = togetherCareCards([_big()], me: 'ama', now: DateTime(2026, 11, 10, 12)).single;
    expect(careDraft(after), 'How did Interview go?');
  });
}
```

Append to `together_screen_test.dart`:

```dart
  testWidgets("my partner's big day shows a care card in Today", (t) async {
    final row = _row('b1', '2026-11-02', title: 'Interview', startsAt: '2026-11-02T15:00:00Z');
    row['participant_ids'] = ['kofi'];
    row['created_by'] = 'kofi';
    row['source_ref'] = {'kind': 'big_day'};
    await _pump(t, upcoming: [row]);
    expect(find.text("Kofi's big day: Interview"), findsOneWidget);
    expect(find.text('Send a word of luck'), findsOneWidget);
  });
```

The test clock is 2026-11-02 09:00 local, and the event is at 15:00 UTC; for TZ-independent tests, check the local start is after 09:00. If the machine zone makes 15:00Z earlier than 09:00 local, use `'2026-11-02T23:00:00Z'`.

- [ ] **Step 2: Run them to verify they fail.**

- [ ] **Step 3: Implement**

`lib/features/together/domain/together_care.dart`:

```dart
import 'together_item.dart';

/// A care card's moment: before a partner's big day, or after it.
enum CarePhase { before, after }

class CareCard {
  const CareCard({required this.item, required this.phase});
  final TogetherItem item;
  final CarePhase phase;
}

/// My partner's shared big days that deserve a word now (plan 2b R6):
/// from 18:00 the evening before until it starts, and from its end
/// (start + 1h, or 18:00 for all-day) for 24 hours.
List<CareCard> togetherCareCards(
  List<TogetherItem> items, {
  required String? me,
  required DateTime now,
}) {
  final seen = <String>{};
  final cards = <CareCard>[];
  for (final i in items) {
    if (i.kind != TogetherItemKind.event ||
        i.sourceRef['kind'] != 'big_day' ||
        i.visibility != TogetherVisibility.shared ||
        i.createdBy == null ||
        i.createdBy == me ||
        i.sourceRef['continuation'] == true ||
        !seen.add(i.id)) {
      continue;
    }
    final day = i.date;
    final start = i.startsAt ?? DateTime(day.year, day.month, day.day, 9);
    final end = i.endsAt ??
        (i.allDay || i.startsAt == null
            ? DateTime(day.year, day.month, day.day, 18)
            : start.add(const Duration(hours: 1)));
    final eveningBefore = DateTime(day.year, day.month, day.day - 1, 18);
    if (!now.isBefore(eveningBefore) && now.isBefore(start) && !(i.allDay && !now.isBefore(DateTime(day.year, day.month, day.day)))) {
      cards.add(CareCard(item: i, phase: CarePhase.before));
    } else if (!now.isBefore(end) && now.isBefore(end.add(const Duration(hours: 24)))) {
      cards.add(CareCard(item: i, phase: CarePhase.after));
    }
  }
  return cards;
}

/// The message chat opens with: fixed, warm, and the partner can edit it.
String careDraft(CareCard c) => c.phase == CarePhase.before
    ? 'Good luck with ${c.item.title}. You’ve got this!'
    : 'How did ${c.item.title} go?';
```

The all-day clause means an all-day big day has its before card until its own day begins, and its after card from 18:00 that day.

In `together_agenda.dart`:
- add the field `final List<CareCard> careCards;` (default `const []` in the constructor);
- include `careCards.isEmpty` in `isEmpty`;
- give `togetherAgenda` an optional `String? me` parameter;
- compute `careCards: togetherCareCards([...upcoming, ...past], me: me, now: now)`;
- import `together_care.dart`.

In `togetherAgendaProvider`, pass `me: ref.watch(togetherMeProvider)`.

In `together_screen.dart`, at the top of the Today section's children (before the rows or the "Nothing planned today." text), insert:

```dart
                                for (final c in agenda.careCards)
                                  InfoRowWidget(
                                    padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.xs),
                                    icon: Icons.favorite_rounded,
                                    iconColor: Theme.of(context).colorScheme.primary,
                                    backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                                    title: c.phase == CarePhase.before
                                        ? "$partnerName's big day: ${c.item.title}"
                                        : 'How did ${c.item.title} go?',
                                    subtitle: c.phase == CarePhase.before
                                        ? 'Send a word of luck'
                                        : 'Ask $partnerName how it went',
                                    titleMaxLines: 1,
                                    subTitleMaxLines: 1,
                                    showDivider: true,
                                    disableTrailing: true,
                                    onTap: () => _openChatWith(careDraft(c)),
                                  ),
```

Make Today's empty text show only when `agenda.today.isEmpty && agenda.careCards.isEmpty`. Add to the state:

```dart
  /// Opens our chat with [draft] ready to send (or edit).
  Future<void> _openChatWith(String draft) async {
    final conversations = await ref.read(conversationsProvider.future);
    if (!mounted) return;
    if (conversations.isEmpty) {
      context.showErrorSnackbar('Chat isn’t available right now.');
      return;
    }
    context.pushNamed('chatScreen', extra: conversations.first,
        queryParameters: {'draft': draft});
  }
```

Import `package:attune/features/chat/presentation/state/chat_state.dart' show conversationsProvider;` and `../../domain/together_care.dart`.

- [ ] **Step 4: Run** `flutter test test/features/together/` → pass.

---

### Task 5: Settings sheet

**Files:**
- Create: `lib/features/together/domain/together_prefs.dart`
- Modify: `together_repository.dart`, `together_providers.dart`
- Create: `lib/features/together/presentation/widgets/together_settings_sheet.dart`
- Modify: `together_screen.dart` (a tune icon beside the Agenda/Month toggle)
- Test: `test/features/together/together_settings_test.dart`

**Interfaces:**
- `class TogetherPrefs { final bool dailySummary; final bool careNudges; }`, with `fromJson` and `copyWith`;
- repository `getPrefs(String relationshipId)` → `Future<TogetherPrefs>`;
- repository `setPrefs(String relationshipId, TogetherPrefs prefs)` → `Future<TogetherPrefs>`;
- `togetherPrefsProvider` (`FutureProvider.autoDispose.family<TogetherPrefs, String>`);
- `Future<void> showTogetherSettingsSheet(BuildContext context, String relationshipId)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart' as quiz;
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/together_settings_sheet.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'together_repository_test.dart' show FakeTogetherGateway;

void main() {
  testWidgets('turning off the morning summary saves straight away', (t) async {
    final g = FakeTogetherGateway({
      'get_together_prefs': (_) => {'daily_summary': true, 'care_nudges': true},
      'set_together_prefs': (p) => {'daily_summary': p['p_daily_summary'], 'care_nudges': p['p_care_nudges']},
    });
    await t.pumpWidget(ProviderScope(
      overrides: [
        togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
        quiz.partnerNameProvider.overrideWith((ref) async => 'Kofi'),
      ],
      child: ScreenUtilInit(designSize: const Size(375, 812), builder: (_, __) => MaterialApp(
        home: Scaffold(body: Builder(builder: (c) => TextButton(
          onPressed: () => showTogetherSettingsSheet(c, 'r1'), child: const Text('open')))),
      )),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Morning summary'), findsOneWidget);
    expect(find.text("Kofi's big days"), findsOneWidget);
    await t.tap(find.descendant(of: find.widgetWithText(InfoRowWidget, 'Morning summary'), matching: find.byType(Switch)));
    await t.pumpAndSettle();
    final call = g.calls.lastWhere((c) => c.$1 == 'set_together_prefs');
    expect(call.$2, {'p_relationship_id': 'r1', 'p_daily_summary': false, 'p_care_nudges': true});
  });
}
```

- [ ] **Step 2: Run it to verify it fails.**

- [ ] **Step 3: Implement**

`together_prefs.dart`:

```dart
/// What Together may send me (plan 2b): the morning summary, and nudges
/// around my partner's big days.
class TogetherPrefs {
  const TogetherPrefs({this.dailySummary = true, this.careNudges = true});

  factory TogetherPrefs.fromJson(Map<String, dynamic> j) => TogetherPrefs(
    dailySummary: j['daily_summary'] as bool? ?? true,
    careNudges: j['care_nudges'] as bool? ?? true,
  );

  final bool dailySummary;
  final bool careNudges;

  TogetherPrefs copyWith({bool? dailySummary, bool? careNudges}) => TogetherPrefs(
    dailySummary: dailySummary ?? this.dailySummary,
    careNudges: careNudges ?? this.careNudges,
  );
}
```

Repository (import `together_prefs.dart`):

```dart
  Future<TogetherPrefs> getPrefs(String relationshipId) async => TogetherPrefs.fromJson(
    Map<String, dynamic>.from(
      await _call('get_together_prefs', {'p_relationship_id': relationshipId}) as Map,
    ),
  );

  Future<TogetherPrefs> setPrefs(String relationshipId, TogetherPrefs prefs) async =>
      TogetherPrefs.fromJson(Map<String, dynamic>.from(await _call('set_together_prefs', {
        'p_relationship_id': relationshipId,
        'p_daily_summary': prefs.dailySummary,
        'p_care_nudges': prefs.careNudges,
      }) as Map));
```

Provider:

```dart
final togetherPrefsProvider = FutureProvider.autoDispose.family<TogetherPrefs, String>(
  (ref, relationshipId) => ref.watch(togetherRepositoryProvider).getPrefs(relationshipId),
);
```

`together_settings_sheet.dart`:

```dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz_providers;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/together_prefs.dart';
import '../together_providers.dart';

/// What Together may send me. Each switch saves straight away.
Future<void> showTogetherSettingsSheet(BuildContext context, String relationshipId) =>
    BottomSheetUtils.showDocumentationBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.neutral,
      widget: _TogetherSettingsSheet(relationshipId: relationshipId),
    );

class _TogetherSettingsSheet extends ConsumerWidget {
  const _TogetherSettingsSheet({required this.relationshipId});
  final String relationshipId;

  Future<void> _save(BuildContext context, WidgetRef ref, TogetherPrefs next) async {
    try {
      await ref.read(togetherRepositoryProvider).setPrefs(relationshipId, next);
      ref.invalidate(togetherPrefsProvider(relationshipId));
    } catch (_) {
      if (context.mounted) context.showErrorSnackbar('Could not save that. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(quiz_providers.partnerNameProvider).valueOrNull ?? 'Your partner';
    final prefs = ref.watch(togetherPrefsProvider(relationshipId)).valueOrNull ?? const TogetherPrefs();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        children: [
          const BottomSheetHeader(title: 'Together settings'),
          InfoRowWidget(
            title: 'Morning summary',
            subtitle: 'One note at 8am when something involves you. Sundays: your week.',
            icon: Icons.wb_twilight_rounded,
            showAvatar: false,
            showDivider: false,
            isToggleItem: true,
            toggleValue: prefs.dailySummary,
            onToggleChanged: (v) => _save(context, ref, prefs.copyWith(dailySummary: v)),
          ),
          AppDivider(),
          InfoRowWidget(
            title: "$partner's big days",
            subtitle: 'A reminder to wish them luck and ask how it went',
            icon: Icons.favorite_border_rounded,
            showAvatar: false,
            showDivider: false,
            isToggleItem: true,
            toggleValue: prefs.careNudges,
            onToggleChanged: (v) => _save(context, ref, prefs.copyWith(careNudges: v)),
          ),
          Gap(Spacing.xl),
        ],
      ),
    );
  }
}
```

In `together_screen.dart`, wrap the toggle `SegmentedButton` in a `Row(children: [Expanded(child: SegmentedButton…), IconButton(tooltip: 'Together settings', icon: const Icon(Icons.tune_rounded), onPressed: relationshipId == null ? null : () => showTogetherSettingsSheet(context, relationshipId))])`. The `toggle` is built before `relationshipId` is known, so pass it in or build the `IconButton` where `relationshipId` is non-null.

- [ ] **Step 4: Run** `flutter test test/features/together/` → pass.

---

### Task 6: Push tap, close-out

- [ ] Add `case 'together_daily':` to the fall-through group in `notification_config.dart`. Extend `together_event_route_test.dart`'s type list with `'together_daily'` (RED first, then GREEN).
- [ ] Add "### 8.5 Phase 2b rulings" (R1–R6) to the spec. Amend the D9 text: "the morning summary (08:00 local; Sundays the week ahead) is the one scheduled push; care cards are in-app and appear as a line in that summary".
- [ ] **Full verification:**
  - `flutter test` (no failures);
  - `flutter analyze lib/features/together lib/features/chat/presentation/screens/chat_screen.dart lib/app/routing/app_router.dart lib/core/notifications`;
  - all Together contracts on the harness;
  - a golden preview of Today with a care card and of the settings sheet, then delete the preview.
- [ ] **Report the deploys:** migrations through `20261014130000`; cron `together_daily` appears in `cron.job`.
