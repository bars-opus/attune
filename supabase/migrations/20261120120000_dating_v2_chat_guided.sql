-- supabase/migrations/20261120120000_dating_v2_chat_guided.sql
-- Spec 2 W6c (§4.9 W6c, §3.6 guided conversation, timebox cards, We met,
-- meeting kit, Close kindly, §3.13 check-in, §4.6, §4.8, §5.3, §6.9; R17;
-- carry 9): the guided first conversation (nine reviewed questions in
-- order; an answer is seen once both have answered; either may skip a
-- question for both); "We met" (which also ends the chat's count as an
-- open pre-date chat, §5.3); the day-7 and day-21 cards, once each per
-- side; Close kindly (the reviewed message, then the match closes for
-- both, never to be introduced again); the check-in (one neutral
-- me_checkin push at the time the person chose, not folded by quiet hours:
-- scheduled_notifications_quiet_guard re-created from its live body with
-- me_checkin beside safety_resources, R17); and the daily retention purge
-- (§4.8: closed matches and their messages after the 30-day evidence
-- window unless an open case holds them, resolved introductions' details
-- after 30 days, moderation cases and pair markers at 2 years, the rest
-- per §4.8), each step its own error block counted by SQLSTATE and, from
-- the cron, its own transaction (fix round 1, M-1). No flag changes. Grants:
-- 20261120120010_dating_v2_chat_guided_grants.sql.
-- Final server fix (W6 final server review, 2026-11-21): send checks the
-- match before the flags and needs Dating on (M-1, I-3) and counts a masker
-- failure (I-8); a guided answer not shown yet bumps nobody and is not
-- unread, and the reveal tells both chats (I-7: complete_dating_safety_job
-- and the push's read guard re-created here); in production the chat needs
-- an active safety config and the last one can't be retired under it
-- (I-4); the owner deletes an unlinked reflection (M-4); a cancelled purge
-- step is counted (M-5); the check-in is Dating's (M-12); this migration
-- revokes what it creates (I-2).
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL client_min_messages = warning;

-- ---------------------------------------------------------------------
-- 1. Columns and the guided questions.
-- ---------------------------------------------------------------------
ALTER TABLE public.dating_matches
  ADD COLUMN IF NOT EXISTS low_we_met_at timestamptz,
  ADD COLUMN IF NOT EXISTS high_we_met_at timestamptz,
  ADD COLUMN IF NOT EXISTS low_day7_at timestamptz,
  ADD COLUMN IF NOT EXISTS high_day7_at timestamptz,
  ADD COLUMN IF NOT EXISTS low_day21_at timestamptz,
  ADD COLUMN IF NOT EXISTS high_day21_at timestamptz;

CREATE TABLE IF NOT EXISTS public.dating_guided_skips (
  match_id uuid NOT NULL REFERENCES public.dating_matches (id) ON DELETE CASCADE,
  question_id text NOT NULL CONSTRAINT dating_guided_skips_question_check CHECK (question_id ~ '^[a-z0-9_]{1,40}$'),
  skipped_by_side text NOT NULL CONSTRAINT dating_guided_skips_side_check CHECK (skipped_by_side IN ('low', 'high')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (match_id, question_id)
);
ALTER TABLE public.dating_guided_skips ENABLE ROW LEVEL SECURITY;
-- Task 8 (Ruling G-1): one answer per side per question is the table's rule
-- too. Send checks it first under the match row's lock, so this never raises.
CREATE UNIQUE INDEX IF NOT EXISTS dating_messages_guided_once
  ON public.dating_messages (match_id, question_id, sender_side) WHERE kind = 'guided_answer';
-- Fix round 1 (M-2): the purge's message deletes set events' message_id to
-- NULL through this index, not a scan of a table that never shrinks.
CREATE INDEX IF NOT EXISTS dating_safety_events_message_idx ON public.dating_safety_events (message_id);
-- Fix round 1 (M-3; §4.8, §4.10): a member's private date reflection is
-- kept while they are in Dating (exit and deletion remove it by author),
-- so the purged match leaves it, unlinked.
ALTER TABLE public.dating_date_reflections ALTER COLUMN match_id DROP NOT NULL;
ALTER TABLE public.dating_date_reflections DROP CONSTRAINT IF EXISTS dating_date_reflections_match_id_fkey;
ALTER TABLE public.dating_date_reflections ADD CONSTRAINT dating_date_reflections_match_id_fkey
  FOREIGN KEY (match_id) REFERENCES public.dating_matches (id) ON DELETE SET NULL;

-- §3.6: the reviewed questions, in order (light, middle, deeper). The app
-- holds their words under the same ids.
CREATE OR REPLACE FUNCTION private.dating_guided_questions()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER -- Task 8 (Ruling S-1): every new function
SET search_path = ''
AS $$
  SELECT ARRAY['good_saturday', 'food_every_week', 'looking_forward', 'proud_of', 'laugh_with', 'where_you_grew_up',
               'good_relationship', 'time_with_family', 'before_first_meeting'];
$$;

-- Whether [p_side] has answered [p_question] in [p_match].
CREATE OR REPLACE FUNCTION private.dating_guided_answered(p_match uuid, p_question text, p_side text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.dating_messages AS d
                  WHERE d.match_id = p_match AND d.kind = 'guided_answer' AND d.question_id = p_question
                    AND d.sender_side = p_side);
$$;

-- The guided state as [p_side] sees it: the current question (the first
-- neither skipped nor answered by both; NULL once all are done), whether
-- this side answered it, and how many answers both have shown (the tip
-- follows the first). Never whether the other side answered.
CREATE OR REPLACE FUNCTION private.dating_guided_state(p_match uuid, p_side text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  q text;
  v_current text;
  v_revealed integer := 0;
BEGIN
  FOREACH q IN ARRAY private.dating_guided_questions() LOOP
    IF private.dating_guided_answered(p_match, q, 'low') AND private.dating_guided_answered(p_match, q, 'high') THEN
      v_revealed := v_revealed + 1;
    ELSIF v_current IS NULL AND NOT EXISTS (SELECT 1 FROM public.dating_guided_skips AS s
                                             WHERE s.match_id = p_match AND s.question_id = q) THEN
      v_current := q;
    END IF;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('question_id', v_current,
    'answered', v_current IS NOT NULL AND private.dating_guided_answered(p_match, v_current, p_side),
    'revealed', v_revealed);
END;
$$;

-- A message [p_side] may read: a guided answer of the other side only once
-- this side has answered the same question (§3.6: both appear together).
CREATE OR REPLACE FUNCTION private.dating_message_visible(p_m public.dating_messages, p_side text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT p_m.kind <> 'guided_answer' OR p_m.sender_side = p_side
      OR private.dating_guided_answered(p_m.match_id, p_m.question_id, p_side);
$$;

-- Task 9 fix round 1 (I-2; §3.6 "both answers appear together"): where a
-- message sits in the chat. A guided answer both sides have given sits at
-- the reveal (the later answer's time), so the pair is read together
-- whatever was written between; every other message at its own time.
CREATE OR REPLACE FUNCTION private.dating_message_sort_at(p_m public.dating_messages)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE WHEN p_m.kind = 'guided_answer'
              THEN coalesce((SELECT max(g.created_at) FROM public.dating_messages AS g
                              WHERE g.match_id = p_m.match_id AND g.kind = 'guided_answer'
                                AND g.question_id = p_m.question_id
                             HAVING count(*) = 2), p_m.created_at)
              ELSE p_m.created_at END;
$$;

-- §3.6 the RPC: {ok, question_id, answered, revealed} | {ok:false,
-- reason: invalid | reverify_device | match_unavailable}.
CREATE OR REPLACE FUNCTION public.get_dating_guided_state(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_m public.dating_matches;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_match_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  SELECT * INTO v_m FROM public.dating_matches AS m WHERE m.id = p_match_id AND v_user IN (m.user_low_id, m.user_high_id);
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true)
      || private.dating_guided_state(p_match_id, CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END);
END;
$$;

-- §3.6: either may skip the current question; it is skipped for both.
CREATE OR REPLACE FUNCTION public.skip_dating_guided_question(p_match_id uuid, p_question_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_m public.dating_matches;
  v_side text;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_match_id IS NULL OR p_question_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  SELECT * INTO v_m FROM public.dating_matches AS m
   WHERE m.id = p_match_id AND v_user IN (m.user_low_id, m.user_high_id) FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable');
  END IF;
  -- Task 8 (Ruling L-1): ended as the header shows it (a member gone, or a
  -- block by phone HMAC alone), so the blocker's chat is never told.
  IF v_m.state <> 'active' OR v_m.user_low_id IS NULL OR v_m.user_high_id IS NULL
     OR private.dating_pair_blocked(v_m.user_low_id, v_m.user_high_id) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'closed');
  END IF;
  v_side := CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END;
  IF private.dating_guided_state(p_match_id, v_side) ->> 'question_id' IS DISTINCT FROM p_question_id THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  INSERT INTO public.dating_guided_skips (match_id, question_id, skipped_by_side)
  VALUES (p_match_id, p_question_id, v_side) ON CONFLICT DO NOTHING;
  PERFORM private.dating_bump_chat(CASE WHEN v_side = 'low' THEN v_m.user_high_id ELSE v_m.user_low_id END, p_match_id);
  RETURN pg_catalog.jsonb_build_object('ok', true) || private.dating_guided_state(p_match_id, v_side);
END;
$$;

-- ---------------------------------------------------------------------
-- 2. We met, the timebox cards, Close kindly.
-- ---------------------------------------------------------------------
-- §3.6 "We met": this side's mark (once); counted.
CREATE OR REPLACE FUNCTION public.mark_dating_we_met(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_m public.dating_matches;
  v_side text;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_match_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  SELECT * INTO v_m FROM public.dating_matches AS m
   WHERE m.id = p_match_id AND v_user IN (m.user_low_id, m.user_high_id) FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable');
  END IF;
  -- Task 8 (Ruling L-1): ended as the header shows it (a member gone, or a
  -- block by phone HMAC alone), so the blocker's chat is never told.
  IF v_m.state <> 'active' OR v_m.user_low_id IS NULL OR v_m.user_high_id IS NULL
     OR private.dating_pair_blocked(v_m.user_low_id, v_m.user_high_id) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'closed');
  END IF;
  v_side := CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END;
  IF (CASE WHEN v_side = 'low' THEN v_m.low_we_met_at ELSE v_m.high_we_met_at END) IS NULL THEN
    UPDATE public.dating_matches AS m
       SET low_we_met_at = CASE WHEN v_side = 'low' THEN now() ELSE m.low_we_met_at END,
           high_we_met_at = CASE WHEN v_side = 'high' THEN now() ELSE m.high_we_met_at END
     WHERE m.id = p_match_id;
    PERFORM private.bump_metric_internal('dating.we_met');
    -- Task 8 (Ruling W-1): the other's header changed (we_met.theirs).
    PERFORM private.dating_bump_chat(CASE WHEN v_side = 'low' THEN v_m.user_high_id ELSE v_m.user_low_id END, p_match_id);
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true);
END;
$$;

-- §3.6 the timebox cards, once to each person: 'day7' or 'day21' seen.
CREATE OR REPLACE FUNCTION public.dismiss_dating_timebox(p_match_id uuid, p_card text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_match_id IS NULL OR p_card IS NULL OR p_card NOT IN ('day7', 'day21') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  UPDATE public.dating_matches AS m
     SET low_day7_at = CASE WHEN p_card = 'day7' AND m.user_low_id = v_user THEN coalesce(m.low_day7_at, now()) ELSE m.low_day7_at END,
         high_day7_at = CASE WHEN p_card = 'day7' AND m.user_high_id = v_user THEN coalesce(m.high_day7_at, now()) ELSE m.high_day7_at END,
         low_day21_at = CASE WHEN p_card = 'day21' AND m.user_low_id = v_user THEN coalesce(m.low_day21_at, now()) ELSE m.low_day21_at END,
         high_day21_at = CASE WHEN p_card = 'day21' AND m.user_high_id = v_user THEN coalesce(m.high_day21_at, now()) ELSE m.high_day21_at END
   WHERE m.id = p_match_id AND v_user IN (m.user_low_id, m.user_high_id);
  RETURN pg_catalog.jsonb_build_object('ok', true);
END;
$$;

-- §3.6 Close kindly: the reviewed message, sent as this side's last, then
-- the match closes for both (closed_kindly, sealed for the 30-day
-- evidence window) and the pair is never introduced again. Never gated by
-- the phone (it reduces exposure). {ok} | {ok:false, reason: invalid |
-- match_unavailable | closed | busy}. The lock order of block and exit.
CREATE OR REPLACE FUNCTION public.close_dating_match_kindly(p_idempotency_key text, p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_text constant text := 'Thank you for chatting with me. I don''t think we''re a match, and I wish you well.';
  v_m public.dating_matches;
  v_side text;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_match_id IS NULL OR NOT private.dating_key_ok(p_idempotency_key) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(v_user);
      SELECT * INTO v_m FROM public.dating_matches AS m
       WHERE m.id = p_match_id AND v_user IN (m.user_low_id, m.user_high_id) FOR UPDATE;
      IF NOT FOUND THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable');
      END IF;
      v_side := CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END;
      IF EXISTS (SELECT 1 FROM public.dating_messages AS d
                  WHERE d.match_id = p_match_id AND d.sender_side = v_side AND d.idempotency_key = p_idempotency_key
                    AND d.kind = 'close_kindly') THEN -- fix round 1 (M-8): its own message only
        RETURN pg_catalog.jsonb_build_object('ok', true);
      END IF;
      -- Fix round 1 (M-8): a key another message of this side took.
      IF EXISTS (SELECT 1 FROM public.dating_messages AS d
                  WHERE d.match_id = p_match_id AND d.sender_side = v_side AND d.idempotency_key = p_idempotency_key) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
      END IF;
      -- Task 8 (Ruling L-1): ended as the header shows it; the message is
      -- never written to a pair blocked by phone HMAC alone.
      IF v_m.state <> 'active' OR v_m.user_low_id IS NULL OR v_m.user_high_id IS NULL
         OR private.dating_pair_blocked(v_m.user_low_id, v_m.user_high_id) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'closed');
      END IF;
      PERFORM 1 FROM public.dating_introductions AS i WHERE i.id = v_m.introduction_id FOR UPDATE;
      INSERT INTO public.dating_messages (match_id, sender_side, sender_user_id, kind, body, body_masked, mask_version, idempotency_key)
      VALUES (p_match_id, v_side, v_user, 'close_kindly', v_text, v_text, 1, p_idempotency_key);
      UPDATE public.dating_matches AS m
         SET state = 'closed', closed_reason = 'closed_kindly', closed_at = coalesce(m.closed_at, now()),
             evidence_until = now() + interval '30 days'
       WHERE m.id = p_match_id;
      PERFORM private.dating_mark_pair(v_m.user_low_id, v_m.user_high_id);
      -- Task 8 (Ruling K-1): both members' chats read the end (the closer's
      -- other phone too).
      PERFORM private.dating_bump_chat(v_m.user_low_id, p_match_id);
      PERFORM private.dating_bump_chat(v_m.user_high_id, p_match_id);
      PERFORM private.bump_metric_internal('dating.close_kindly');
      RETURN pg_catalog.jsonb_build_object('ok', true);
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- ---------------------------------------------------------------------
-- 3. The check-in (§3.6 meeting kit, §3.13): one neutral push at the time
--    the person chose (from 5 minutes to 7 days ahead): no place, no
--    match, no name; a new one replaces the last; cancel removes it. Not
--    gated by the phone, never cancelled by quick exit (a safety tool).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.schedule_dating_checkin(p_at timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_at IS NULL OR p_at < now() + interval '5 minutes' OR p_at > now() + interval '7 days' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  -- Final server fix (M-12): Dating's own tool, for someone who has been
  -- in Dating (an enrolment in any state; a person who left keeps it, a
  -- safety tool), never any signed-in account.
  IF NOT EXISTS (SELECT 1 FROM public.dating_enrollments AS e WHERE e.user_id = v_user) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  BEGIN
    PERFORM public.check_dating_rate_limit('dating_checkin', 20, interval '1 day');
  EXCEPTION WHEN invalid_parameter_value THEN
    IF SQLERRM IS DISTINCT FROM 'rate_limited' THEN
      RAISE;
    END IF;
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'rate_limited');
  END;
  -- Task 8 (Ruling C-1): one person's check-ins one at a time, so a new
  -- one always replaces the last (R-46).
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('dating_checkin'), pg_catalog.hashtext(v_user::text));
  UPDATE public.scheduled_notifications AS n SET status = 'cancelled', updated_at = now()
   WHERE n.user_id = v_user AND n.status = 'pending' AND n.metadata ->> 'type' = 'me_checkin';
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata, created_at, updated_at)
  VALUES (v_user, 'immediate', p_at, 'pending',
          pg_catalog.jsonb_build_object('type', 'me_checkin', 'route', 'me_checkin', 'title', 'Attune',
                                        'body', 'A quick check-in from Attune.'),
          now(), now());
  -- Task 10 fix round 1 (I-3): whether a push can reach this person at all.
  RETURN pg_catalog.jsonb_build_object('ok', true, 'at', p_at, 'push', private.dating_has_push_device(v_user));
END;
$$;

-- Task 10 fix round 1 (I-3): an active push device (what the push worker
-- targets, push_tokens.is_active); none means the check-in is skipped.
CREATE OR REPLACE FUNCTION private.dating_has_push_device(p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.push_tokens AS t WHERE t.user_id = p_user AND t.is_active);
$$;

-- Task 10 fix round 1 (I-1): the caller's own pending check-in, or none,
-- so the kit shows the server's state (after quick exit, a restart, a
-- request left in flight, or another phone). A time and whether a push
-- can arrive; never anyone else's.
CREATE OR REPLACE FUNCTION public.get_my_dating_checkin()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'at', (SELECT n.scheduled_for FROM public.scheduled_notifications AS n
            WHERE n.user_id = v_user AND n.status = 'pending' AND n.metadata ->> 'type' = 'me_checkin'
            ORDER BY n.created_at DESC LIMIT 1),
    'push', private.dating_has_push_device(v_user));
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_dating_checkin()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  UPDATE public.scheduled_notifications AS n SET status = 'cancelled', updated_at = now()
   WHERE n.user_id = auth.uid() AND n.status = 'pending' AND n.metadata ->> 'type' = 'me_checkin';
  RETURN pg_catalog.jsonb_build_object('ok', true);
END;
$$;

-- ---------------------------------------------------------------------
-- 4. The retention purge (§4.8; carry 9), daily at 02:47 UTC. Each step is
--    one bounded statement in its own error block (counted by SQLSTATE as
--    dating.purge.failed.<step>), so one failing step never stops the
--    others. Fix round 1 (M-1): the cron CALLs run_dating_retention_purge(),
--    which COMMITs after every step, so a step's row locks last only while
--    that step runs: Close kindly, Unmatch, Leave and an account deletion
--    wait at most one step, never the whole purge. purge_dating_retention()
--    runs the same steps in the caller's one transaction (the contract, a
--    manual run) and answers each step's count.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.dating_purge_steps()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT ARRAY['matches', 'introductions', 'pair_markers', 'moderation_cases', 'opener_hashes',
               'safety_events', 'safety_outbox', 'rate_limits', 'block_hmacs', 'enforcement_records',
               'session_context'];
$$;

-- One step, {step: n} or {step: 'failed:<SQLSTATE>'}. Ruling P-1 (carry
-- M-6): a step never waits long on a row another job holds (55P03), and a
-- deadlock with complete_dating_safety_job (40P01) or a lock timeout is
-- retried (3 tries, counted dating.purge.retried), then the step is
-- skipped and counted.
CREATE OR REPLACE FUNCTION private.dating_purge_step(p_step text, p_now timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '5s'
AS $$
DECLARE
  v_n integer;
  v_try integer;
  v_ids uuid[];
BEGIN
  FOR v_try IN 1..3 LOOP
    BEGIN
      CASE p_step
      -- A closed match after its 30-day window, with its messages (cascade),
      -- unless an open case holds it (§4.8 "unless a report holds it"), or
      -- (Ruling P-2, W6b N-4) a safety event about it is still inside the
      -- 7-day evidence window: a deleted recipient is then still counted
      -- once by the match, never once per event. Fix round 1 (M-9): the
      -- rows are locked first, skipping one another job holds (a case being
      -- filed holds it key-share), and the holds are tested again by a new
      -- statement, which sees every case committed before the lock.
      WHEN 'matches' THEN
        SELECT coalesce(pg_catalog.array_agg(y.id), '{}') INTO v_ids
          FROM (SELECT x.id FROM public.dating_matches AS x
                 WHERE x.state <> 'active' AND x.evidence_until < p_now
                 AND NOT EXISTS (SELECT 1 FROM public.dating_moderation_cases AS c
                                  WHERE c.match_id = x.id AND c.state IN ('open', 'in_review'))
                 AND NOT EXISTS (SELECT 1 FROM public.dating_safety_events AS e
                                  WHERE e.match_id = x.id AND e.created_at > p_now - interval '7 days')
                 LIMIT 5000
                   FOR UPDATE OF x SKIP LOCKED) AS y;
        DELETE FROM public.dating_matches AS x
         WHERE x.id = ANY (v_ids)
           AND x.state <> 'active' AND x.evidence_until < p_now
                 AND NOT EXISTS (SELECT 1 FROM public.dating_moderation_cases AS c
                                  WHERE c.match_id = x.id AND c.state IN ('open', 'in_review'))
                 AND NOT EXISTS (SELECT 1 FROM public.dating_safety_events AS e
                                  WHERE e.match_id = x.id AND e.created_at > p_now - interval '7 days');
      -- A resolved introduction keeps only its ids, pair key, state and
      -- dates 30 days on (its interest actions go).
      WHEN 'introductions' THEN
        WITH old AS (
          SELECT i.id FROM public.dating_introductions AS i
           WHERE i.state IN ('passed', 'matched', 'expired', 'invalidated')
             AND greatest(i.expires_at, i.created_at) < p_now - interval '30 days'
             AND (i.low_action IS NOT NULL OR i.high_action IS NOT NULL OR cardinality(i.reasons) > 0 OR i.rank_detail IS NOT NULL
                  OR EXISTS (SELECT 1 FROM public.dating_interest_actions AS a WHERE a.introduction_id = i.id))
           LIMIT 5000
        ), gone AS (
          DELETE FROM public.dating_interest_actions AS a USING old WHERE a.introduction_id = old.id
        )
        UPDATE public.dating_introductions AS i SET low_action = NULL, high_action = NULL, reasons = '{}', rank_detail = NULL
          FROM old WHERE i.id = old.id;
      WHEN 'pair_markers' THEN
        DELETE FROM public.dating_pair_markers AS k WHERE k.purge_after < p_now;
      -- Carry 9: 2 years. Ruling P-3: a case still open or in review stays
      -- (a moderator's queue is never emptied by the clock).
      WHEN 'moderation_cases' THEN
        DELETE FROM public.dating_moderation_cases AS c
         WHERE c.created_at < p_now - interval '2 years' AND c.state NOT IN ('open', 'in_review');
      WHEN 'opener_hashes' THEN
        DELETE FROM public.dating_opener_hashes AS k WHERE k.created_at < p_now - interval '30 days';
      -- Safety events after 90 days keep only their family, tier, rule and
      -- version (nobody, no match, no message). Ruling P-4: the source key
      -- (message id ':' rule) is replaced too, or it would still name the
      -- message, and through it both people.
      WHEN 'safety_events' THEN
        UPDATE public.dating_safety_events AS e
           SET at_risk_user_id = NULL, sender_user_id = NULL, match_id = NULL, message_id = NULL,
               source_event_key = 'anon:' || e.id::text
         WHERE e.created_at < p_now - interval '90 days'
           AND (e.at_risk_user_id IS NOT NULL OR e.sender_user_id IS NOT NULL OR e.match_id IS NOT NULL OR e.message_id IS NOT NULL
                OR e.source_event_key <> 'anon:' || e.id::text);
      WHEN 'safety_outbox' THEN
        DELETE FROM public.dating_message_safety_outbox AS o
         WHERE o.state = 'done' AND o.completed_at < p_now - interval '7 days';
      WHEN 'rate_limits' THEN
        DELETE FROM public.dating_rate_limits AS r WHERE r.window_started_at < p_now - interval '2 days';
      WHEN 'block_hmacs' THEN
        DELETE FROM public.dating_block_hmacs AS h WHERE h.purge_after < p_now;
      WHEN 'enforcement_records' THEN
        DELETE FROM public.enforcement_records AS r WHERE r.scope = 'dating' AND r.purge_after < p_now;
      WHEN 'session_context' THEN
        DELETE FROM public.dating_session_context AS c WHERE c.checked_at < p_now - interval '30 days';
      END CASE;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      RETURN pg_catalog.jsonb_build_object(p_step, v_n);
    EXCEPTION
      WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
        IF v_try < 3 THEN
          PERFORM private.bump_metric_internal('dating.purge.retried');
        ELSE
          PERFORM private.bump_metric_internal('dating.purge.failed.' || p_step);
          RETURN pg_catalog.jsonb_build_object(p_step, 'failed:' || SQLSTATE);
        END IF;
      -- Final server fix (M-5): a statement timeout (or a cancel) skips this
      -- step only, counted like any failure (OTHERS does not catch it).
      WHEN OTHERS OR query_canceled THEN
        PERFORM private.bump_metric_internal('dating.purge.failed.' || p_step);
        RETURN pg_catalog.jsonb_build_object(p_step, 'failed:' || SQLSTATE);
    END;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object(p_step, 'failed:retries');
END;
$$;

-- Every step in the caller's transaction (the contract; a manual run).
CREATE OR REPLACE FUNCTION public.purge_dating_retention(p_now timestamptz DEFAULT now())
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '5s'
AS $$
DECLARE
  v_out jsonb := '{}'::jsonb;
  v_step text;
BEGIN
  FOREACH v_step IN ARRAY private.dating_purge_steps() LOOP
    v_out := v_out || private.dating_purge_step(v_step, p_now);
  END LOOP;
  RETURN v_out;
END;
$$;

-- Fix round 1 (M-1), Ruling P-6: the cron's entry, one transaction per
-- step. PostgreSQL refuses COMMIT in a SECURITY DEFINER procedure or one
-- with a SET clause, so this one runs as its caller (the cron's postgres)
-- with no SET: every name in it is schema-qualified, it calls only the
-- definer step above, and no API role may call it (the twin).
CREATE OR REPLACE PROCEDURE public.run_dating_retention_purge(p_now timestamptz DEFAULT pg_catalog.now())
LANGUAGE plpgsql
AS $$
DECLARE
  v_step text;
BEGIN
  FOREACH v_step IN ARRAY private.dating_purge_steps() LOOP
    PERFORM private.dating_purge_step(v_step, p_now);
    COMMIT;
  END LOOP;
END;
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname = 'cron') THEN
    PERFORM cron.unschedule(j.jobid) FROM cron.job AS j WHERE j.jobname = 'purge-dating-retention';
    PERFORM cron.schedule('purge-dating-retention', '47 2 * * *', $c$CALL public.run_dating_retention_purge()$c$);
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- 5. Functions re-created from their live bodies; only the lines marked
--    "-- Spec 2 W6c" change.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.send_dating_message(p_idempotency_key text, p_match_id uuid, p_body text, p_kind text DEFAULT 'text'::text, p_question_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '2s'
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  v_m public.dating_matches;
  v_side text;
  v_other uuid;
  v_msg public.dating_messages;
  v_masked text;
  v_try integer;
  v_shown boolean; -- Spec 2 W6c (R-45): the other side sees this message now
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_match_id IS NULL OR NOT private.dating_key_ok(p_idempotency_key)
     OR p_kind IS NULL OR p_kind NOT IN ('text', 'guided_answer') -- Spec 2 W6c: text, or a guided answer
     OR (p_kind = 'text') <> (p_question_id IS NULL) -- Spec 2 W6c: a guided answer names its question
     OR p_body IS NULL OR pg_catalog.btrim(p_body) = '' OR pg_catalog.char_length(p_body) > 1000 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF private.dating_body_blank(p_body) THEN -- fix round 1 (M-1): only blank or invisible characters
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      SELECT * INTO v_m FROM public.dating_matches AS m
       WHERE m.id = p_match_id AND v_user IN (m.user_low_id, m.user_high_id)
       FOR NO KEY UPDATE;
      IF NOT FOUND THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable');
      END IF;
      v_side := CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END;
      v_other := CASE WHEN v_side = 'low' THEN v_m.user_high_id ELSE v_m.user_low_id END;
      -- A replay answers as the first did, whatever happened since.
      SELECT * INTO v_msg FROM public.dating_messages AS d
       WHERE d.match_id = p_match_id AND d.sender_side = v_side AND d.idempotency_key = p_idempotency_key;
      IF FOUND THEN
        RETURN pg_catalog.jsonb_build_object('ok', true, 'message',
          private.dating_message_json(v_msg, v_side, v_m.low_swap_at IS NOT NULL AND v_m.high_swap_at IS NOT NULL));
      END IF;
      -- Spec 2 W6c (final server fix, M-1): an ended match answers closed whatever the flags say.
      IF v_m.state <> 'active' OR v_other IS NULL OR public.dating_can_send(p_match_id) IS NOT TRUE THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason',
          CASE WHEN v_m.state = 'active' AND v_other IS NOT NULL AND public.dating_account_in_good_standing(v_user) IS NOT TRUE
               THEN 'restricted' ELSE 'closed' END);
      END IF;
      -- Spec 2 W6c (final server fix, M-1, I-3): then the flags, Dating's and the chat's own.
      IF private.dating_chat_on() IS NOT TRUE THEN -- fix round 1 (I-2): the chat's flag (§4.10)
        -- Fix round 1b: messages are paused (an incident), the match has not ended.
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'unavailable');
      END IF;
      IF p_kind = 'guided_answer' -- Spec 2 W6c: the current question, not answered yet by this side
         AND (private.dating_guided_state(p_match_id, v_side) ->> 'question_id' IS DISTINCT FROM p_question_id -- Spec 2 W6c
              OR private.dating_guided_answered(p_match_id, p_question_id, v_side)) THEN -- Spec 2 W6c
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid'); -- Spec 2 W6c
      END IF; -- Spec 2 W6c
      BEGIN
        PERFORM public.check_dating_rate_limit('dating_message', 500, interval '1 day');
      EXCEPTION WHEN invalid_parameter_value THEN
        IF SQLERRM IS DISTINCT FROM 'rate_limited' THEN
          RAISE;
        END IF;
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'rate_limited');
      END;
      v_masked := private.dating_mask_counted(p_body); -- Spec 2 W6c (final server fix, I-8): a masker failure is counted
      INSERT INTO public.dating_messages (match_id, sender_side, sender_user_id, kind, question_id, body, body_masked,
                                          mask_version, idempotency_key)
      VALUES (p_match_id, v_side, v_user, p_kind, p_question_id, p_body, v_masked, 1, p_idempotency_key) -- Spec 2 W6c
      RETURNING * INTO v_msg;
      UPDATE public.dating_matches AS m
         SET chat_started_at = coalesce(m.chat_started_at, now()),
             low_seen_at = CASE WHEN v_side = 'low' THEN clock_timestamp() ELSE m.low_seen_at END,
             high_seen_at = CASE WHEN v_side = 'high' THEN clock_timestamp() ELSE m.high_seen_at END
       WHERE m.id = p_match_id;
      -- Spec 2 W6c (R-45, Task 8 Ruling H-1): an answer the other can't see
      -- yet tells their chat nothing and sends no push; the one that shows both does.
      v_shown := p_kind = 'text' OR private.dating_guided_answered(p_match_id, p_question_id, CASE WHEN v_side = 'low' THEN 'high' ELSE 'low' END);
      IF v_shown THEN
        PERFORM private.dating_bump_chat(v_other, p_match_id);
        IF p_kind = 'guided_answer' THEN -- Spec 2 W6c (final server fix, I-7): the reveal; this side's other phone
          PERFORM private.dating_bump_chat(v_user, p_match_id); -- Spec 2 W6c: reads again too (a card under the other's answer shows now)
        END IF; -- Spec 2 W6c
      END IF; -- Spec 2 W6c
      INSERT INTO public.dating_message_safety_outbox (message_id) VALUES (v_msg.id); -- Spec 2 W6b (§6.1)
      IF p_kind = 'text' AND NOT EXISTS (SELECT 1 FROM public.dating_opener_hashes AS k -- Spec 2 W6b (§5.10); Spec 2 W6c: the first text message
                      WHERE k.sender_user_id = v_user AND k.match_id = p_match_id) -- Spec 2 W6b
         AND private.dating_opener_hash(p_body) IS NOT NULL THEN -- Spec 2 W6b
        INSERT INTO public.dating_opener_hashes (sender_user_id, match_id, hash) -- Spec 2 W6b
        VALUES (v_user, p_match_id, private.dating_opener_hash(p_body)) ON CONFLICT DO NOTHING; -- Spec 2 W6b
      END IF; -- Spec 2 W6b
      IF v_shown THEN PERFORM private.dating_queue_chat_push(v_other); END IF; -- Spec 2 W6b (§3.13); Spec 2 W6c (R-45)
      IF v_masked IS DISTINCT FROM p_body THEN
        PERFORM private.bump_metric_internal('dating.mask_hit');
      END IF;
      RETURN pg_catalog.jsonb_build_object('ok', true, 'message',
        private.dating_message_json(v_msg, v_side, v_m.low_swap_at IS NOT NULL AND v_m.high_swap_at IS NOT NULL));
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_dating_messages(p_match_id uuid, p_before timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  v_m public.dating_matches;
  v_side text;
  v_both boolean;
  v_limit integer;
  v_rows jsonb;
  v_more boolean;
  v_seen timestamptz;
  v_ids uuid[]; -- Spec 2 W6c (Task 9 fix round 1, I-2)
  v_keys timestamptz[]; -- Spec 2 W6c
  v_edge timestamptz; -- Spec 2 W6c
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_match_id IS NULL OR (p_limit IS NOT NULL AND p_limit NOT BETWEEN 1 AND 100) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  v_limit := coalesce(p_limit, 50);
  SELECT * INTO v_m FROM public.dating_matches AS m
   WHERE m.id = p_match_id AND v_user IN (m.user_low_id, m.user_high_id)
     AND (m.state = 'active' OR m.evidence_until > now());
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'match_unavailable');
  END IF;
  v_side := CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END;
  v_both := v_m.low_swap_at IS NOT NULL AND v_m.high_swap_at IS NOT NULL;
  -- Spec 2 W6c (Task 9 fix round 1, I-2): the candidates are the newest texts by time (a text sits at its own
  -- time) and every guided answer this side can see; each sits at private.dating_message_sort_at.
  SELECT pg_catalog.array_agg(q.id ORDER BY q.k DESC, q.id DESC), pg_catalog.array_agg(q.k ORDER BY q.k DESC, q.id DESC) -- Spec 2 W6c
    INTO v_ids, v_keys -- Spec 2 W6c
    FROM (SELECT d.id, private.dating_message_sort_at(d) AS k FROM public.dating_messages AS d -- Spec 2 W6c
           WHERE d.id IN ((SELECT t.id FROM public.dating_messages AS t -- Spec 2 W6c
                            WHERE t.match_id = p_match_id AND t.kind <> 'guided_answer' -- Spec 2 W6c
                              AND (p_before IS NULL OR t.created_at < p_before) -- Spec 2 W6c
                            ORDER BY t.created_at DESC, t.id DESC LIMIT v_limit + 1) -- Spec 2 W6c
                          UNION -- Spec 2 W6c
                          SELECT g.id FROM public.dating_messages AS g -- Spec 2 W6c
                           WHERE g.match_id = p_match_id AND g.kind = 'guided_answer' -- Spec 2 W6c
                             AND private.dating_message_visible(g, v_side))) AS q -- Spec 2 W6c (§3.6): answers appear together
   WHERE p_before IS NULL OR q.k < p_before; -- Spec 2 W6c
  -- The page: the newest v_limit, and any row tied with the last (a revealed pair is never split). -- Spec 2 W6c
  v_edge := CASE WHEN coalesce(pg_catalog.array_length(v_keys, 1), 0) > v_limit THEN v_keys[v_limit] END; -- Spec 2 W6c
  SELECT coalesce(pg_catalog.jsonb_agg(private.dating_message_json(d, v_side, v_both) -- Spec 2 W6c
                                       || pg_catalog.jsonb_build_object('at', u.k) ORDER BY u.k DESC, u.id DESC), '[]'::jsonb) -- Spec 2 W6c: where it sits
    INTO v_rows -- Spec 2 W6c
    FROM ROWS FROM (pg_catalog.unnest(v_ids), pg_catalog.unnest(v_keys)) AS u(id, k) -- Spec 2 W6c
    JOIN public.dating_messages AS d ON d.id = u.id -- Spec 2 W6c
   WHERE v_edge IS NULL OR u.k >= v_edge; -- Spec 2 W6c
  v_more := v_edge IS NOT NULL AND EXISTS (SELECT 1 FROM public.dating_messages AS d -- Spec 2 W6c
                                            WHERE d.match_id = p_match_id AND d.created_at < v_edge -- Spec 2 W6c
                                              AND private.dating_message_visible(d, v_side) -- Spec 2 W6c
                                              AND private.dating_message_sort_at(d) < v_edge); -- Spec 2 W6c
  -- Fix round 1 (M-7): seen up to the newest incoming message this page
  -- returned, never the clock, so one committed while the page was read
  -- keeps its dot.
  v_seen := (SELECT max((x ->> 'at')::timestamptz) FROM pg_catalog.jsonb_array_elements(v_rows) AS x
              WHERE NOT (x ->> 'mine')::boolean);
  IF p_before IS NULL THEN
    UPDATE public.dating_matches AS m
       SET low_seen_at = CASE WHEN v_side = 'low' THEN v_seen ELSE m.low_seen_at END,
           high_seen_at = CASE WHEN v_side = 'high' THEN v_seen ELSE m.high_seen_at END
     WHERE m.id = p_match_id AND v_seen IS NOT NULL
       AND v_seen > coalesce(CASE WHEN v_side = 'low' THEN m.low_seen_at ELSE m.high_seen_at END, '-infinity');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'chat', private.dating_chat_header(v_m, v_side),
                                       'messages', v_rows, 'more', v_more);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_dating_matches(p_include_ended boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  v_rows jsonb;
  v_ended jsonb;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  SELECT coalesce(pg_catalog.jsonb_agg(c.row ORDER BY c.at DESC, c.id), '[]'::jsonb) INTO v_rows
    FROM (SELECT m.id, coalesce(l.created_at, m.matched_at) AS at,
                 pg_catalog.jsonb_build_object(
                   'match_id', m.id,
                   'display_name', (SELECT p.display_name FROM public.dating_profiles AS p WHERE p.user_id = s.other),
                   'age', public.account_age(s.other),
                   'last', CASE WHEN l.id IS NULL THEN NULL ELSE
                             private.dating_message_json(l, s.side, m.low_swap_at IS NOT NULL AND m.high_swap_at IS NOT NULL) END,
                   'new', EXISTS (SELECT 1 FROM public.dating_messages AS d
                                   WHERE d.match_id = m.id AND d.sender_side <> s.side
                                     AND private.dating_message_visible(d, s.side) -- Spec 2 W6c
                                     AND d.created_at > coalesce(s.seen, '-infinity'))) AS row
            FROM public.dating_matches AS m
           CROSS JOIN LATERAL (SELECT CASE WHEN m.user_low_id = v_user THEN 'low' ELSE 'high' END AS side,
                                      CASE WHEN m.user_low_id = v_user THEN m.user_high_id ELSE m.user_low_id END AS other,
                                      CASE WHEN m.user_low_id = v_user THEN m.low_seen_at ELSE m.high_seen_at END AS seen) AS s
            LEFT JOIN LATERAL (SELECT d.* FROM public.dating_messages AS d WHERE d.match_id = m.id
                                  AND private.dating_message_visible(d, s.side) -- Spec 2 W6c
                                ORDER BY d.created_at DESC, d.id DESC LIMIT 1) AS l ON true
           WHERE v_user IN (m.user_low_id, m.user_high_id) AND m.state = 'active' AND s.other IS NOT NULL
             AND NOT private.dating_pair_blocked(m.user_low_id, m.user_high_id)) AS c; -- fix round 1 (M-5)
  IF coalesce(p_include_ended, false) THEN
    SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
             'match_id', m.id,
             'display_name', (SELECT p.display_name FROM public.dating_profiles AS p
                               WHERE p.user_id = CASE WHEN m.user_low_id = v_user THEN m.user_high_id ELSE m.user_low_id END),
             'ended_at', coalesce(m.closed_at, m.matched_at)) ORDER BY coalesce(m.closed_at, m.matched_at) DESC, m.id), '[]'::jsonb)
      INTO v_ended
      FROM public.dating_matches AS m
     WHERE v_user IN (m.user_low_id, m.user_high_id)
       AND (m.state <> 'active' OR m.user_low_id IS NULL OR m.user_high_id IS NULL)
       AND m.evidence_until > now();
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'conversations', v_rows)
      || CASE WHEN coalesce(p_include_ended, false) THEN pg_catalog.jsonb_build_object('ended', v_ended) ELSE '{}'::jsonb END;
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_chat_header(p_m dating_matches, p_side text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_other constant uuid := CASE WHEN p_side = 'low' THEN p_m.user_high_id ELSE p_m.user_low_id END;
  v_mine constant timestamptz := CASE WHEN p_side = 'low' THEN p_m.low_swap_at ELSE p_m.high_swap_at END;
  v_theirs constant timestamptz := CASE WHEN p_side = 'low' THEN p_m.high_swap_at ELSE p_m.low_swap_at END;
  v_blocked constant boolean := private.dating_pair_blocked(p_m.user_low_id, p_m.user_high_id); -- Spec 2 W6c (fix round 1, M-5)
BEGIN
  RETURN pg_catalog.jsonb_build_object(
    'match_id', p_m.id,
    'display_name', (SELECT p.display_name FROM public.dating_profiles AS p WHERE p.user_id = v_other),
    'age', CASE WHEN v_other IS NULL THEN NULL ELSE public.account_age(v_other) END,
    'state', CASE WHEN p_m.state = 'active' AND v_other IS NOT NULL
                       AND NOT private.dating_pair_blocked(p_m.user_low_id, p_m.user_high_id) THEN 'active' ELSE 'ended' END, -- fix round 1 (M-5)
    'swap', pg_catalog.jsonb_build_object('mine', v_mine IS NOT NULL, 'theirs', v_theirs IS NOT NULL,
                                          'both', v_mine IS NOT NULL AND v_theirs IS NOT NULL,
                                          'from', p_m.matched_at + interval '72 hours'), -- Spec 2 W6c
    'we_met', CASE WHEN v_blocked THEN NULL ELSE pg_catalog.jsonb_build_object( -- Spec 2 W6c (fix round 1, M-5: none for a blocked pair)
      'mine', (CASE WHEN p_side = 'low' THEN p_m.low_we_met_at ELSE p_m.high_we_met_at END) IS NOT NULL, -- Spec 2 W6c
      'theirs', (CASE WHEN p_side = 'low' THEN p_m.high_we_met_at ELSE p_m.low_we_met_at END) IS NOT NULL) END, -- Spec 2 W6c
    'timebox', CASE WHEN p_m.state <> 'active' OR v_other IS NULL OR v_blocked THEN NULL -- Spec 2 W6c (§3.6; fix round 1, M-5)
                    WHEN now() >= p_m.matched_at + interval '21 days' -- Spec 2 W6c
                         AND p_m.low_we_met_at IS NULL AND p_m.high_we_met_at IS NULL -- Spec 2 W6c
                         AND (CASE WHEN p_side = 'low' THEN p_m.low_day21_at ELSE p_m.high_day21_at END) IS NULL THEN 'day21' -- Spec 2 W6c
                    WHEN now() >= p_m.matched_at + interval '7 days' AND now() < p_m.matched_at + interval '21 days' -- Spec 2 W6c
                         AND p_m.low_we_met_at IS NULL AND p_m.high_we_met_at IS NULL -- Spec 2 W6c (fix round 1, M-4)
                         AND (CASE WHEN p_side = 'low' THEN p_m.low_day7_at ELSE p_m.high_day7_at END) IS NULL THEN 'day7' -- Spec 2 W6c
               END); -- Spec 2 W6c
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_open_chats(p_user uuid, p_at timestamp with time zone)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT count(*)::integer FROM public.dating_matches AS m
   WHERE m.state = 'active' AND p_user IN (m.user_low_id, m.user_high_id)
     AND m.low_we_met_at IS NULL AND m.high_we_met_at IS NULL -- Spec 2 W6c (§5.3): neither said We met
     AND (m.matched_at > p_at - interval '7 days' -- Spec 2 W6a (§5.3): or a message in the last 14 days
          OR EXISTS (SELECT 1 FROM public.dating_messages AS d -- Spec 2 W6a
                      WHERE d.match_id = m.id AND d.created_at > p_at - interval '14 days')); -- Spec 2 W6a
$function$;

CREATE OR REPLACE FUNCTION public.get_dating_operational_health()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT jsonb_build_object(
    'dating_enabled',public.dating_flag_enabled('dating_mode_enabled'),
    'candidate_generation_enabled',public.dating_flag_enabled('dating_candidate_generation'),
    'exclusion_key_present',public.app_setting('dating_exclusion_key') IS NOT NULL,
    'relationships_ended_without_exclusion_24h',(
      SELECT count(*) FROM public.relationships r
      WHERE r.status = 'ended'
        AND r.ended_at >= now() - interval '24 hours'
        AND NOT EXISTS (
          SELECT 1 FROM public.dating_former_partner_exclusions e
          WHERE e.relationship_id = r.id
        )
    ),
    'active_algorithm_versions',(SELECT count(*) FROM public.dating_algorithm_configs WHERE state='active'),
    'introductions_config',(private.dating_intro_config()).o_version, -- Spec 2 W5a (§5.5): NULL = generation refuses
    'generation_by_country',(SELECT coalesce(jsonb_object_agg(x.partition_key, jsonb_build_object( -- Spec 2 W5a (§4.4 health v2)
                               'cohort', x.cohort_window, 'state', x.state, 'attempts', x.attempts)), '{}'::jsonb) -- Spec 2 W5a
                             FROM (SELECT DISTINCT ON (r.partition_key) r.partition_key, r.cohort_window, r.state, r.attempts -- Spec 2 W5a
                                     FROM public.dating_generation_runs AS r WHERE r.created_at >= now() - interval '36 hours' -- Spec 2 W5a
                                    ORDER BY r.partition_key, r.created_at DESC) AS x), -- Spec 2 W5a
    'stuck_generation_runs',(SELECT count(*) FROM public.dating_generation_runs WHERE state='processing' AND started_at < now()-interval '30 minutes'),
    'failed_generation_runs_24h',(SELECT count(*) FROM public.dating_generation_runs WHERE state IN ('failed','dead_letter') AND created_at >= now()-interval '24 hours'),
    'expired_open_introductions',(SELECT count(*) FROM public.dating_introductions WHERE state IN ('generated','presented','interested') AND expires_at <= now()),
    'pending_bio_moderation',(SELECT count(*) FROM public.dating_profiles WHERE moderation_state='pending'),
    'pending_photo_moderation',(SELECT count(*) FROM public.dating_profile_photos WHERE moderation_state='pending'),
    'environment',private.attune_environment(), -- Spec 2 W1d
    'field_key_present',private.dating_field_key_present(), -- Spec 2 W1d
    -- Spec 2 W1d (§2.4): nothing can write an RPC's parameters to the log.
    'log_settings_safe',coalesce(current_setting('log_statement', true) IN ('none', 'ddl')
      AND (current_setting('log_min_duration_statement', true) = '-1'
           OR current_setting('log_parameter_max_length', true) = '0')
      AND current_setting('log_parameter_max_length_on_error', true) = '0', false),
    'enabled_countries',to_jsonb(private.dating_open_countries()), -- Spec 2 W1d
    'age_assurance_mode',private.dating_verification_mode(), -- Spec 2 W4a
    'verification_awaiting_review',(SELECT count(*) FROM public.dating_verification_sessions WHERE state='awaiting_review'), -- Spec 2 W4a
    'verification_oldest_waiting_hours',(SELECT floor(extract(epoch FROM now() - min(coalesce(awaiting_since, updated_at))) / 3600)::int -- Spec 2 W4a (fix round 1, M-8)
                                           FROM public.dating_verification_sessions WHERE state='awaiting_review'), -- Spec 2 W4a
    -- Spec 2 W1d (B2 I-5, B5 M-4, B6 M-5): each key set and its stored
    -- Spec 2 W1d fingerprint equal (read only; never the counting mismatch()).
    'exclusion_key_fingerprint_ok',private.dating_exclusion_key_ready(), -- Spec 2 W1d
    'field_key_fingerprint_ok',private.dating_field_key_ready(), -- Spec 2 W1d
    'safety_counters_7d',(SELECT jsonb_object_agg(k.key, coalesce((SELECT sum(c.count) FROM public.metric_counters c -- Spec 2 W1d
                            WHERE c.key = k.key AND c.day >= (now() AT TIME ZONE 'utc')::date - 6), 0)) -- Spec 2 W1d
      FROM unnest(ARRAY['dating.deletion.uncarried', 'dating.exclusion_key.mismatch', 'dating.exclusion_key.unseeded', -- Spec 2 W1d
                        'dating.eligibility.key_not_ready', 'dating.field_key.mismatch', 'dating.field_key.missing', -- Spec 2 W1d
                        'dating.parked_pause.failed', -- Spec 2 W1d (fix round 1, M-5)
                        'dating.path_pause.failed', 'dating.gates.busy', -- Spec 2 W2
                        'dating.gates.failed', 'dating.gentle_wait.undated', -- Spec 2 W2 (Task 3 carry: W2 batch 1 fix round 1, M-4 and M-3)
                        'dating.path_pause.swept', -- Spec 2 W2 (Task 3 fix round 1, I-1)
                        'dating.gentle_wait.seen', 'dating.gentle_wait.account_deleted_7d', -- Spec 2 W2 (migration 3, §6.9)
                        'dating.gentle_wait.clear_busy', 'dating.gentle_wait.seen_skipped', 'dating.home.unreadable_field', -- Spec 2 W2 (migration 3 fix round 1)
                        'dating.kill_switch.pending', 'dating.kill_switch.unreadable', -- Spec 2 W1d (migration 11)
                        'dating.verify.sweep_failed', 'dating.verify.id_review_expired', -- Spec 2 W4a (fix round 1, M-7)
                        'dating.deletion.prepare_carry_failed', 'dating.deletion.late_carry_failed', -- W1 final fix (M-4); -- Spec 2 W5a: and
                        'dating.generation.skipped', 'dating.generation.failed', 'dating.generation.unreadable', -- Spec 2 W5a
                        'dating.generation.busy', -- Spec 2 W5a (Task 2 fix round 2, N-3); -- Spec 2 W5c: and
                        'dating.signal.failed', 'dating.signal.busy', 'dating.fairness.unreadable', -- Spec 2 W5c (fix round 1, I-2, M-1, M-5); -- Spec 2 W5 final: and
                        'dating.digest.push_key_missing', 'dating.digest.failed', -- Spec 2 W5 final (M-5, M-3); Spec 2 W6b: the list goes on
                        'dating.pair_marker.unwritten', 'dating.safety.no_config', 'dating.safety.dead_letter', -- Spec 2 W6b
                        'dating.chat.push_failed', 'dating.chat.push_read', -- Spec 2 W6b (fix round 1, M-11: push_read); Spec 2 W6c: and
                        'dating.purge.retried', -- Spec 2 W6c (Task 8, carry M-6): purge steps retried
                        'dating.mask.failed']) AS k(key)), -- Spec 2 W6c (final server fix, I-8): the masker's fail-closed fallback
    -- Spec 2 W6b (chat spec §10): the chat's safety outbox and its events.
    'chat_safety_outbox',(SELECT jsonb_build_object( -- Spec 2 W6b
                            'pending', count(*) FILTER (WHERE o.state = 'pending'), -- Spec 2 W6b
                            'processing', count(*) FILTER (WHERE o.state = 'processing'), -- Spec 2 W6b
                            'dead_letter', (SELECT count(*) FROM public.dating_message_safety_outbox AS x WHERE x.state = 'dead_letter'), -- Spec 2 W6b (fix round 1, M-10)
                            'oldest_pending_seconds', coalesce(floor(extract(epoch FROM now() - min(o.created_at) FILTER (WHERE o.state = 'pending'))), 0)) -- Spec 2 W6b
                          FROM public.dating_message_safety_outbox AS o WHERE o.state IN ('pending', 'processing')), -- Spec 2 W6b (fix round 1, M-10): done rows never read
    'chat_safety_config_active',(SELECT c.version FROM public.dating_safety_configs AS c WHERE c.state = 'active'), -- Spec 2 W6b
    'chat_safety_events_24h',(SELECT coalesce(jsonb_object_agg(x.family, x.n), '{}'::jsonb) FROM ( -- Spec 2 W6b
                                SELECT e.family, count(*) AS n FROM public.dating_safety_events AS e -- Spec 2 W6b
                                 WHERE e.created_at >= now() - interval '24 hours' GROUP BY e.family) AS x), -- Spec 2 W6b
    -- Spec 2 W6c (§4.8): the retention purge's failed steps, per step, 7 days
    'purge_failed_7d',(SELECT coalesce(jsonb_object_agg(x.step, x.n), '{}'::jsonb) FROM ( -- Spec 2 W6c
                         SELECT substr(c.key, char_length('dating.purge.failed.') + 1) AS step, sum(c.count) AS n -- Spec 2 W6c
                           FROM public.metric_counters AS c -- Spec 2 W6c
                          WHERE left(c.key, char_length('dating.purge.failed.')) = 'dating.purge.failed.' -- Spec 2 W6c
                            AND c.day >= (now() AT TIME ZONE 'utc')::date - 6 -- Spec 2 W6c
                          GROUP BY 1) AS x), -- Spec 2 W6c
    -- Spec 2 W5a (Task 2 fix round 2, N-3): people left out over the bound, per country, 7 days
    'generation_truncated_7d',(SELECT coalesce(jsonb_object_agg(x.country, x.n), '{}'::jsonb) FROM ( -- Spec 2 W5a
                                 SELECT substr(c.key, char_length('dating.generation.truncated.') + 1) AS country, sum(c.count) AS n -- Spec 2 W5a
                                   FROM public.metric_counters AS c -- Spec 2 W5a
                                  WHERE left(c.key, char_length('dating.generation.truncated.')) = 'dating.generation.truncated.' -- Spec 2 W5a
                                    AND c.day >= (now() AT TIME ZONE 'utc')::date - 6 -- Spec 2 W5a
                                  GROUP BY 1) AS x), -- Spec 2 W5a
    -- W1 final fix (M-4): app deletions refused for a missing exclusion key
    -- W1 final fix (delete-account records prepare's message) in 7 days.
    'deletions_refused_key_missing_7d',(SELECT count(*) FROM public.account_deletion_requests AS r -- W1 final fix (M-4)
                                         WHERE r.completed_at IS NULL AND r.requested_at >= now() - interval '7 days' -- W1 final fix (M-4)
                                           AND r.failure_reason LIKE '%deletion:enforcement_key_missing%'), -- W1 final fix (M-4)
    -- Spec 2 W1d (fix round 1, I-1): every purge still pending, until a switch clears it.
    'kill_switch_pending',(SELECT coalesce(jsonb_agg(jsonb_build_object('scope', k.scope, 'since', k.first_failed_at, -- Spec 2 W1d
                             'sqlstate', k.last_sqlstate, 'attempts', k.attempts) ORDER BY k.scope), '[]'::jsonb) -- Spec 2 W1d
                           FROM private.dating_kill_switch_pending k) -- Spec 2 W1d
  );
$function$;

CREATE OR REPLACE FUNCTION public.scheduled_notifications_quiet_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_meta jsonb := coalesce(NEW.metadata, '{}'::jsonb);
  v_type text := v_meta->>'type';
  v_claim boolean := TG_OP = 'UPDATE' AND OLD.status = 'pending' AND NEW.status = 'processing';
  v_neutral_chat constant jsonb := jsonb_build_object(
    'type', 'new_message', 'title', 'New messages in Attune', 'body', 'Open Attune to read them.');
  v_off int;
  v_base timestamptz;
  v_tz text;
  v_release timestamptz;
  v_days int;
  v_key text;
  v_n int;
BEGIN
  -- Inserts and returns to pending are checked; so is the worker's claim
  -- (pending -> processing), so a row reached late in a backlog, or queued
  -- before the recipient's zone was known, is not sent at night.
  IF NOT v_claim AND NEW.status IS DISTINCT FROM 'pending' THEN RETURN NEW; END IF;
  IF NEW.delivery_channel IS DISTINCT FROM 'push' OR v_type IN ('safety_resources', 'me_checkin') THEN -- Spec 2 W6c (R17): a check-in the person timed
    RETURN NEW;
  END IF;
  -- Short-notice plan alarms ("Starting now", "In 1 hour"); the offset is the
  -- 4th key field (together_alarm:<event>:<date>:<offset>:<user>). Day-ahead
  -- heads-ups are still true at 08:00 and wait (D1, review I1).
  v_off := CASE WHEN v_type = 'together_event'
                     AND NEW.source_key ~ '^together_alarm:[^:]+:[^:]+:[0-9]+:'
                THEN split_part(NEW.source_key, ':', 4)::int END;
  IF v_off IS NOT NULL AND v_off <= 120 THEN RETURN NEW; END IF;
  IF public.quiet_hours_game_live(NEW.user_id, v_meta) THEN RETURN NEW; END IF;

  IF TG_OP = 'UPDATE' THEN
    -- A pending row being rewritten to pending is left alone.
    IF NOT v_claim AND OLD.status = 'pending' THEN RETURN NEW; END IF;
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

  IF v_claim THEN
    -- Bounce the claim: the worker skips a row that did not become
    -- 'processing'; it goes out at 08:00 as queued.
    NEW.status := 'pending';
  END IF;
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
  -- A day-ahead alarm says how far the plan is from 08:00, not from the night
  -- it was queued (follow-up M5). The plan starts offset minutes after the
  -- alarm was due.
  IF v_off IS NOT NULL THEN
    v_days := ((v_base + make_interval(mins => v_off)) AT TIME ZONE v_tz)::date
              - (v_release AT TIME ZONE v_tz)::date;
    v_meta := v_meta || jsonb_build_object('body',
      CASE WHEN v_days <= 0 THEN 'Today' WHEN v_days = 1 THEN 'Tomorrow'
           ELSE 'In ' || v_days || ' days' END);
  END IF;

  -- Overnight chat: one neutral push per conversation at 08:00. A retried
  -- push joins it too (follow-up M1). A claim bounced back keeps its row.
  IF v_type IN ('new_message', 'message_reaction') AND NOT v_claim THEN
    v_meta := v_meta || v_neutral_chat;
    IF NEW.source_key IS NOT NULL AND NEW.source_key NOT LIKE 'quiet_chat:%' THEN
      -- The inserter's own key (its idempotency) is kept: no collapse
      -- (follow-up M2).
      NEW.metadata := v_meta;
      RETURN NEW;
    END IF;
    v_key := 'quiet_chat:' || NEW.user_id || ':' || coalesce(v_meta->>'relationship_id', '')
             || ':' || to_char(v_release AT TIME ZONE 'UTC', 'YYYYMMDDHH24MI');
    PERFORM pg_advisory_xact_lock(hashtext(v_key));
    UPDATE public.scheduled_notifications s
       SET metadata = s.metadata || v_neutral_chat || jsonb_build_object(
             'quiet_count', coalesce((s.metadata->>'quiet_count')::int, 1) + 1),
           updated_at = now()
     WHERE s.source_key = v_key AND s.status = 'pending' AND s.id IS DISTINCT FROM NEW.id;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n > 0 THEN
      IF TG_OP = 'INSERT' THEN RETURN NULL; END IF;
      -- A retry joins the overnight push and is itself cancelled.
      NEW.status := 'cancelled';
      NEW.last_error := 'joined_quiet_push';
      NEW.source_key := NULL;
      NEW.metadata := v_meta;
      RETURN NEW;
    END IF;
    IF EXISTS (SELECT 1 FROM public.scheduled_notifications s
               WHERE s.source_key = v_key AND s.id IS DISTINCT FROM NEW.id) THEN
      -- The key's row already left 'pending' (claimed at 08:00, sent,
      -- failed): queue this one on its own. Taking the key would hit the
      -- unique index and dead-letter the chat outbox job (review I4).
      NEW.source_key := NULL;
    ELSE
      NEW.source_key := v_key;
    END IF;
  END IF;

  NEW.metadata := v_meta;
  RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION private.dating_first_messages(p_user uuid, p_since timestamp with time zone, p_at timestamp with time zone)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT count(*)::integer -- Spec 2 W6a (carry 6): the matches the person wrote in
    FROM public.dating_matches AS m JOIN public.dating_introductions AS i ON i.id = m.introduction_id -- Spec 2 W6a
   WHERE p_user IN (i.user_low_id, i.user_high_id) AND i.created_at > p_since -- Spec 2 W6a
     AND i.created_at <= p_at -- Spec 2 W6a (fix round 1, M-8): by the run's time
     AND EXISTS (SELECT 1 FROM public.dating_messages AS d WHERE d.match_id = m.id AND d.sender_user_id = p_user -- Spec 2 W6a
                  AND d.kind IN ('text', 'guided_answer') -- Spec 2 W6c (W6a M-8): Close kindly is not writing in
                  AND d.created_at <= p_at); -- Spec 2 W6a (fix round 1, M-8)
$function$;

CREATE OR REPLACE FUNCTION public.get_my_dating_safety_cards(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  v_country text;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_match_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  SELECT p.country_code INTO v_country FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'cards', coalesce((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
             'id', e.id, 'message_id', e.message_id, 'family', e.family,
             'resource', CASE WHEN e.family IN ('threat_intimidation', 'sextortion')
                              THEN private.dating_card_resource(v_country, e.family) END)
             ORDER BY e.created_at, e.id)
      FROM public.dating_safety_events AS e
     WHERE e.match_id = p_match_id AND e.at_risk_user_id = v_user AND e.tier <= 2 AND e.dismissed_at IS NULL
       AND NOT EXISTS (SELECT 1 FROM public.dating_messages AS d -- Spec 2 W6c (R-45): never under an answer not shown yet
                        WHERE d.id = e.message_id -- Spec 2 W6c
                          AND NOT private.dating_message_visible(d, CASE WHEN d.sender_side = 'low' THEN 'high' ELSE 'low' END)) -- Spec 2 W6c
       AND EXISTS (SELECT 1 FROM public.dating_matches AS m WHERE m.id = e.match_id AND v_user IN (m.user_low_id, m.user_high_id))),
    '[]'::jsonb));
END;
$function$;

CREATE OR REPLACE FUNCTION public.complete_dating_safety_job(p_message_id uuid, p_version text, p_hits jsonb, p_error text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_d public.dating_messages;
  v_m public.dating_matches;
  v_to uuid;
  v_from uuid;
  v_attempts smallint;
  h jsonb;
  v_family text;
  v_tier integer;
  v_events integer := 0;
  v_hash text;
  v_cfg jsonb;
  v_fin boolean := false;
  v_sex boolean := false;
BEGIN
  IF p_message_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  SELECT o.attempts INTO v_attempts FROM public.dating_message_safety_outbox AS o
   WHERE o.message_id = p_message_id AND o.state = 'processing' FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_claimed');
  END IF;
  IF p_error IS NOT NULL THEN
    UPDATE public.dating_message_safety_outbox AS o
       SET state = CASE WHEN v_attempts >= 5 THEN 'dead_letter' ELSE 'pending' END,
           last_error_code = CASE WHEN p_error ~ '^[a-z0-9_]{1,40}$' THEN p_error ELSE 'worker_error' END,
           processing_started_at = NULL
     WHERE o.message_id = p_message_id;
    IF v_attempts >= 5 THEN
      PERFORM private.bump_metric_internal('dating.safety.dead_letter');
    END IF;
    RETURN pg_catalog.jsonb_build_object('ok', true, 'state', CASE WHEN v_attempts >= 5 THEN 'dead_letter' ELSE 'pending' END);
  END IF;
  -- Its own IF first: an OR has no order, and the elements of a non-array raise.
  IF jsonb_typeof(coalesce(p_hits, '[]'::jsonb)) <> 'array' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  -- A version names a stored config, and each hit's tier is its family's
  -- tier there (a hit can't skip its case); a hit with no family is invalid
  -- (NULL NOT IN is NULL: coalesced), never a raise that holds the message.
  IF p_version IS NOT NULL THEN
    SELECT c.config INTO v_cfg FROM public.dating_safety_configs AS c WHERE c.version = p_version;
    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
    END IF;
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(p_hits, '[]'::jsonb)) AS x
              WHERE jsonb_typeof(x) <> 'object' OR coalesce(x ->> 'family', '') NOT IN ('sexual_pressure', 'harassment_abuse',
                      'contact_migration_pressure', 'meet_private_pressure', 'threat_intimidation', 'financial_request',
                      'sextortion', 'child_access', 'age_signal', 'identity_inconsistency')
                 OR coalesce(x ->> 'tier', '') NOT IN ('1', '2', '3')
                 OR (x ->> 'tier') IS DISTINCT FROM (v_cfg #>> ARRAY['families', x ->> 'family', 'tier'])
                 -- Fix round 1 (M-5): the rule is its family and one of that
                 -- version's terms, never free text (no message words).
                 OR NOT EXISTS (
                      SELECT 1 FROM jsonb_array_elements_text(
                               CASE WHEN jsonb_typeof(v_cfg #> ARRAY['families', x ->> 'family', 'terms']) = 'array'
                                    THEN v_cfg #> ARRAY['families', x ->> 'family', 'terms'] ELSE '[]'::jsonb END
                               || CASE WHEN jsonb_typeof(v_cfg #> ARRAY['families', x ->> 'family', 'new_match_terms']) = 'array'
                                       THEN v_cfg #> ARRAY['families', x ->> 'family', 'new_match_terms'] ELSE '[]'::jsonb END) AS t(term)
                       WHERE (x ->> 'family') || ':' || t.term = x ->> 'rule_id')
                 OR coalesce(pg_catalog.char_length(x ->> 'rule_id'), 0) NOT BETWEEN 1 AND 120)
     OR (p_version IS NULL AND jsonb_array_length(coalesce(p_hits, '[]'::jsonb)) > 0) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  SELECT * INTO v_d FROM public.dating_messages AS d WHERE d.id = p_message_id;
  SELECT * INTO v_m FROM public.dating_matches AS m WHERE m.id = v_d.match_id;
  v_from := v_d.sender_user_id;
  v_to := CASE WHEN v_d.sender_side = 'low' THEN v_m.user_high_id ELSE v_m.user_low_id END;
  IF p_version IS NULL THEN
    PERFORM private.bump_metric_internal('dating.safety.no_config');
  END IF;
  FOR h IN SELECT x FROM jsonb_array_elements(coalesce(p_hits, '[]'::jsonb)) AS x LOOP
    v_family := h ->> 'family';
    v_tier := (h ->> 'tier')::integer;
    -- Fix round 1 (M-7): a recipient deleted meanwhile (v_to NULL) still
    -- leaves the evidence and the case about the sender; no card.
    INSERT INTO public.dating_safety_events (match_id, message_id, at_risk_user_id, sender_user_id, rule_id, family, tier,
                                             config_version, source_event_key)
    VALUES (v_d.match_id, p_message_id, v_to, v_from, h ->> 'rule_id', v_family, v_tier, p_version,
            p_message_id::text || ':' || (h ->> 'rule_id'))
    ON CONFLICT (source_event_key) DO NOTHING;
    IF FOUND THEN
      v_events := v_events + 1;
      v_fin := v_fin OR v_family = 'financial_request';
      v_sex := v_sex OR v_family = 'sexual_pressure';
      IF v_tier <= 2 AND v_to IS NOT NULL THEN
        PERFORM private.bump_metric_internal('dating.card.' || v_family);
        -- Task 7 fix round 1: the recipient's open chat reads again and
        -- shows the card (the sender's chat learns nothing).
        -- Spec 2 W6c (final server fix, I-7): only once the recipient can see the message: a guided
        -- Spec 2 W6c answer not shown yet has no card to show (the reveal tells both chats).
        IF private.dating_message_visible(v_d, CASE WHEN v_d.sender_side = 'low' THEN 'high' ELSE 'low' END) THEN -- Spec 2 W6c
          PERFORM private.dating_bump_chat(v_to, v_d.match_id); -- Spec 2 W6c
        END IF; -- Spec 2 W6c
      END IF;
      IF v_tier >= 2 AND v_from IS NOT NULL THEN
        PERFORM private.dating_open_chat_case(v_from, v_d.match_id, 'chat_' || v_family,
          CASE WHEN v_family = 'identity_inconsistency' THEN 'P2' ELSE 'P1' END);
      END IF;
    END IF;
  END LOOP;
  -- §5.10 (carry 8): the sender's repeated patterns, each a signal case.
  -- Fix round 1 (I-1): each pattern is checked only when this completion
  -- added its evidence (the opener: the side's first message), so the case
  -- names the match that holds it; evidence a moderator's decision
  -- postdates never counts again (W5c's dating_signal_cleared, per item):
  -- a decision sticks, and only fresh evidence opens a new case. A deleted
  -- recipient still counts once (by match, else by event; M-7).
  IF v_from IS NOT NULL THEN
    IF v_fin AND (SELECT count(DISTINCT coalesce(e.at_risk_user_id::text, 'm:' || e.match_id::text, 'e:' || e.id::text))
                    FROM public.dating_safety_events AS e
                   WHERE e.sender_user_id = v_from AND e.family = 'financial_request' AND e.created_at > now() - interval '7 days'
                     AND NOT private.dating_signal_cleared(v_from, 'money_asks', e.created_at)) >= 2 THEN
      PERFORM private.dating_open_chat_case(v_from, v_d.match_id, 'money_asks', 'P1');
    END IF;
    IF v_sex AND (SELECT count(DISTINCT coalesce(e.at_risk_user_id::text, 'm:' || e.match_id::text, 'e:' || e.id::text))
                    FROM public.dating_safety_events AS e
                   WHERE e.sender_user_id = v_from AND e.family = 'sexual_pressure' AND e.created_at > now() - interval '7 days'
                     AND NOT private.dating_signal_cleared(v_from, 'sexual_pressure', e.created_at)) >= 2 THEN
      PERFORM private.dating_open_chat_case(v_from, v_d.match_id, 'sexual_pressure', 'P2');
    END IF;
    -- Fix round 2 (N-1): the side's first text message (send keeps that
    -- one's opener), whatever guided answers came before it.
    IF v_d.kind = 'text' AND NOT EXISTS (SELECT 1 FROM public.dating_messages AS d2
                    WHERE d2.match_id = v_d.match_id AND d2.sender_side = v_d.sender_side AND d2.kind = 'text'
                      AND (d2.created_at, d2.id) < (v_d.created_at, v_d.id)) THEN
      SELECT k.hash INTO v_hash FROM public.dating_opener_hashes AS k WHERE k.sender_user_id = v_from AND k.match_id = v_d.match_id;
      IF v_hash IS NOT NULL
         AND (SELECT count(DISTINCT k.match_id) FROM public.dating_opener_hashes AS k
               WHERE k.sender_user_id = v_from AND k.hash = v_hash AND k.created_at > now() - interval '7 days'
                 AND NOT private.dating_signal_cleared(v_from, 'duplicate_opener', k.created_at)) >= 3 THEN
        PERFORM private.dating_open_chat_case(v_from, v_d.match_id, 'duplicate_opener', 'P2');
      END IF;
    END IF;
  END IF;
  UPDATE public.dating_message_safety_outbox AS o
     SET state = 'done', completed_at = clock_timestamp(), processing_started_at = NULL, last_error_code = NULL
   WHERE o.message_id = p_message_id;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'state', 'done', 'events', v_events);
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_chat_push_read_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_q bigint;
BEGIN
  -- The trigger's WHEN already limits this to a claim of a me_update push.
  IF NEW.source_key IS NULL OR NEW.created_at IS NULL THEN
    RETURN NEW;
  END IF;
  -- A message push's key: its own quarter hour's (chat:<q>), or (final
  -- server fix, I-6) a trailing push's, keyed by the quarter hour it is due
  -- in, which is the one it was queued in or the next (chat:<q>:t).
  v_q := pg_catalog.floor(extract(epoch FROM NEW.created_at) / 900)::bigint;
  IF NEW.source_key IS DISTINCT FROM private.dating_push_source_key(NEW.user_id, 'chat:' || v_q::text,
       (NEW.created_at AT TIME ZONE 'UTC')::date)
     AND NEW.source_key IS DISTINCT FROM private.dating_push_source_key(NEW.user_id, 'chat:' || v_q::text || ':t',
       (pg_catalog.to_timestamp(v_q * 900) AT TIME ZONE 'UTC')::date)
     AND NEW.source_key IS DISTINCT FROM private.dating_push_source_key(NEW.user_id, 'chat:' || (v_q + 1)::text || ':t',
       (pg_catalog.to_timestamp((v_q + 1) * 900) AT TIME ZONE 'UTC')::date) THEN
    RETURN NEW;
  END IF;
  -- Fix round 2 (N-3): one indexed lookup per side (no scan of matches).
  IF NOT EXISTS (SELECT 1 FROM public.dating_matches AS m
                  WHERE m.user_low_id = NEW.user_id AND m.state = 'active'
                    AND EXISTS (SELECT 1 FROM public.dating_messages AS d
                                 WHERE d.match_id = m.id AND d.sender_side = 'high'
                                   AND private.dating_message_visible(d, 'low') -- Spec 2 W6c (final server fix, I-7): a hidden answer is not unread
                                   AND d.created_at > coalesce(m.low_seen_at, '-infinity'::timestamptz)))
     AND NOT EXISTS (SELECT 1 FROM public.dating_matches AS m
                      WHERE m.user_high_id = NEW.user_id AND m.state = 'active'
                        AND EXISTS (SELECT 1 FROM public.dating_messages AS d
                                     WHERE d.match_id = m.id AND d.sender_side = 'low'
                                       AND private.dating_message_visible(d, 'high') -- Spec 2 W6c (final server fix, I-7)
                                       AND d.created_at > coalesce(m.high_seen_at, '-infinity'::timestamptz))) THEN
    NEW.status := 'skipped';
    NEW.last_error := 'dating_chat_read';
    PERFORM private.bump_metric_internal('dating.chat.push_read');
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_private_date_reflection(p_idempotency_key text, p_match_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT public.claim_dating_idempotency('delete_private_date_reflection', p_idempotency_key) THEN
    RETURN;
  END IF;

  DELETE FROM public.dating_date_reflections
  WHERE match_id IS NOT DISTINCT FROM p_match_id -- Spec 2 W6c (final server fix, M-4): an unlinked one (its match purged) too
    AND author_user_id = auth.uid();
END;
$function$;

-- ---------------------------------------------------------------------
-- Task 10 fix round 1 (I-4): Get help opens S1's support directory, which
-- exists only under support_resources_v2. In production Dating chat can't
-- be on while it is off (turn the chat off first). The gate rows say so.
-- Development is free. Fix round 2 (N-1): judged on each statement's end
-- state, after the statement (inserts, updates and deletes alike), so a
-- bulk switch-off or a two-flag statement passes in any row order. Only a
-- statement that touched one of the two rows is judged (another flag's
-- write never waits on this pair).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.guard_dating_chat_needs_directory()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_touched boolean;
BEGIN
  -- Each event's own transition tables (one trigger per event).
  IF TG_OP = 'INSERT' THEN
    v_touched := EXISTS (SELECT 1 FROM new_rows AS n WHERE n.key IN ('dating_match_messaging', 'support_resources_v2'));
  ELSIF TG_OP = 'DELETE' THEN
    v_touched := EXISTS (SELECT 1 FROM old_rows AS o WHERE o.key IN ('dating_match_messaging', 'support_resources_v2'));
  ELSE
    v_touched := EXISTS (SELECT 1 FROM new_rows AS n WHERE n.key IN ('dating_match_messaging', 'support_resources_v2'))
              OR EXISTS (SELECT 1 FROM old_rows AS o WHERE o.key IN ('dating_match_messaging', 'support_resources_v2'));
  END IF;
  IF v_touched
     AND coalesce((SELECT f.enabled FROM public.feature_flags AS f WHERE f.key = 'dating_match_messaging'), false)
     AND NOT coalesce((SELECT f.enabled FROM public.feature_flags AS f WHERE f.key = 'support_resources_v2'), false)
     AND private.attune_environment() = 'production' THEN
    RAISE EXCEPTION 'flag:dating_chat_needs_support_resources_v2: turn Dating chat (dating_match_messaging) off first, or turn support_resources_v2 on in the same statement'
      USING HINT = 'Get help opens the support_resources_v2 directory.';
  END IF;
  -- Final server fix (I-4): nor without an active chat safety config (with
  -- none the worker completes every message unscanned, for good). Only a
  -- statement that leaves the chat on is judged: any switch-off passes.
  IF v_touched
     AND coalesce((SELECT f.enabled FROM public.feature_flags AS f WHERE f.key = 'dating_match_messaging'), false)
     AND NOT EXISTS (SELECT 1 FROM public.dating_safety_configs AS c WHERE c.state = 'active')
     AND private.attune_environment() = 'production' THEN
    RAISE EXCEPTION 'flag:dating_chat_needs_safety_config: activate a dating_safety_configs version (with its reviewers'' reference) before turning Dating chat (dating_match_messaging) on'
      USING HINT = 'With no active config no message is scanned, and a scanned message is never scanned again.';
  END IF;
  RETURN coalesce(NEW, OLD);
END;
$$;

-- Final server fix (I-4): the other side of the rule. In production the
-- last active chat safety config can't be retired or deleted while Dating
-- chat is on. Judged on the transaction's end state (a deferred constraint
-- trigger): the one-active index makes a version swap in one statement
-- depend on row order, so a swap is two statements (retire, then
-- activate) and passes at commit; the chat turned off in the same
-- transaction (the emergency switch-off) passes too.
CREATE OR REPLACE FUNCTION private.guard_dating_chat_keeps_config()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF coalesce((SELECT f.enabled FROM public.feature_flags AS f WHERE f.key = 'dating_match_messaging'), false)
     AND NOT EXISTS (SELECT 1 FROM public.dating_safety_configs AS c WHERE c.state = 'active')
     AND private.attune_environment() = 'production' THEN
    RAISE EXCEPTION 'config:dating_chat_needs_active_config: turn Dating chat (dating_match_messaging) off first, or activate another version in the same transaction'
      USING ERRCODE = '23514', HINT = 'With no active config no message is scanned.';
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS dating_safety_configs_chat_keeps_active ON public.dating_safety_configs;
CREATE CONSTRAINT TRIGGER dating_safety_configs_chat_keeps_active
  AFTER UPDATE OR DELETE ON public.dating_safety_configs
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION private.guard_dating_chat_keeps_config();

DROP TRIGGER IF EXISTS feature_flags_dating_chat_needs_directory ON public.feature_flags;
DROP TRIGGER IF EXISTS feature_flags_dating_chat_needs_directory_ins ON public.feature_flags;
DROP TRIGGER IF EXISTS feature_flags_dating_chat_needs_directory_upd ON public.feature_flags;
DROP TRIGGER IF EXISTS feature_flags_dating_chat_needs_directory_del ON public.feature_flags;
CREATE TRIGGER feature_flags_dating_chat_needs_directory_ins
  AFTER INSERT ON public.feature_flags
  REFERENCING NEW TABLE AS new_rows
  FOR EACH STATEMENT EXECUTE FUNCTION private.guard_dating_chat_needs_directory();
CREATE TRIGGER feature_flags_dating_chat_needs_directory_upd
  AFTER UPDATE ON public.feature_flags
  REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
  FOR EACH STATEMENT EXECUTE FUNCTION private.guard_dating_chat_needs_directory();
CREATE TRIGGER feature_flags_dating_chat_needs_directory_del
  AFTER DELETE ON public.feature_flags
  REFERENCING OLD TABLE AS old_rows
  FOR EACH STATEMENT EXECUTE FUNCTION private.guard_dating_chat_needs_directory();

UPDATE private.flag_production_gates
   SET gate = 'Spec 2 W6 gate: DATING_CHAT_SAFETY_SPEC v2 section 12 checked by the safety owner, DV and cultural sign-offs; support_resources_v2 on in production first (Get help opens its directory; a trigger refuses the chat flag without it); an active dating_safety_configs version with the reviewers'' reference first (final server fix I-4: a trigger refuses the chat flag without one, and refuses retiring the last active one while the chat is on); Report (W7a) built'
 WHERE flag_key = 'dating_match_messaging' AND review_ref IS NULL;
-- Fix round 2: the directory's own row names who needs it.
UPDATE private.flag_production_gates
   SET gate = gate || '; Spec 2 W6: Dating chat (dating_match_messaging) needs this on in production, so turn the chat off before turning this off'
 WHERE flag_key = 'support_resources_v2' AND review_ref IS NULL AND gate NOT LIKE '%dating_match_messaging%';

-- ---------------------------------------------------------------------
-- 6. Final server fix (I-2): a split push fails closed. Every object this
--    migration creates is revoked here, in its own transaction, from
--    PUBLIC, anon, authenticated and the service role; its twin
--    (20261120120010) then grants the app its RPCs. Re-created functions
--    keep their grants.
-- ---------------------------------------------------------------------
REVOKE ALL ON TABLE public.dating_guided_skips FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  private.dating_guided_questions(), private.dating_guided_answered(uuid, text, text), private.dating_guided_state(uuid, text),
  private.dating_message_visible(public.dating_messages, text), private.dating_message_sort_at(public.dating_messages),
  public.get_dating_guided_state(uuid), public.skip_dating_guided_question(uuid, text), public.mark_dating_we_met(uuid),
  public.dismiss_dating_timebox(uuid, text), public.close_dating_match_kindly(text, uuid),
  public.schedule_dating_checkin(timestamptz), private.dating_has_push_device(uuid), public.get_my_dating_checkin(),
  public.cancel_dating_checkin(), private.dating_purge_steps(), private.dating_purge_step(text, timestamptz),
  public.purge_dating_retention(timestamptz), private.guard_dating_chat_needs_directory(),
  private.guard_dating_chat_keeps_config()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON PROCEDURE public.run_dating_retention_purge(timestamptz) FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
