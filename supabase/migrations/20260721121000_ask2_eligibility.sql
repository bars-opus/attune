-- supabase/migrations/20260721121000_ask2_eligibility.sql
-- Service-role-only eligibility check for Ask-2 (ATTUNE_MASTER_SPEC.md
-- decision 29): both partners active on 3+ distinct local days, each has
-- sent >= 30 messages, and at least one message has positive sentiment.
--
-- Unlike chat_conversation_streak (SECURITY DEFINER keyed off auth.uid(),
-- callable by any authenticated user for their own relationship), this
-- function takes an explicit relationship_id and is NOT auth.uid()-scoped —
-- it must be callable by the cron sweep (Task 3) for arbitrary relationships,
-- not just "the caller's own." REVOKE/GRANT below restricts it to the
-- service role only, same pattern as other service-only functions in this
-- codebase would use (there is no "authenticated" grant here, deliberately).
CREATE OR REPLACE FUNCTION public.ask2_eligibility(
  p_relationship_id uuid
)
RETURNS TABLE (
  eligible boolean,
  first_positive_message_id uuid,
  first_positive_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rel public.relationships%ROWTYPE;
  v_user_a_count int;
  v_user_b_count int;
  v_day_count int;
  v_first_positive_id uuid;
  v_first_positive_at timestamptz;
BEGIN
  SELECT * INTO v_rel FROM public.relationships WHERE id = p_relationship_id;

  IF NOT FOUND OR v_rel.user_b IS NULL OR v_rel.status <> 'active' THEN
    RETURN QUERY SELECT false, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;

  SELECT count(*) INTO v_user_a_count
  FROM public.messages
  WHERE relationship_id = p_relationship_id AND sender_id = v_rel.user_a;

  SELECT count(*) INTO v_user_b_count
  FROM public.messages
  WHERE relationship_id = p_relationship_id AND sender_id = v_rel.user_b;

  IF v_user_a_count < 30 OR v_user_b_count < 30 THEN
    RETURN QUERY SELECT false, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;

  -- Distinct local days (UTC bucketing — matches chat_conversation_streak's
  -- pattern of using a caller-supplied UTC offset for local-day bucketing,
  -- but the sweep is not tied to a single user's timezone, so UTC calendar
  -- days are used here as a deliberately simpler, timezone-agnostic proxy.
  -- "3+ distinct days" is a coarse threshold; exact local-midnight precision
  -- does not materially change the trigger's behaviour).
  SELECT count(*) INTO v_day_count
  FROM (
    SELECT (created_at::date) AS day
    FROM public.messages
    WHERE relationship_id = p_relationship_id
    GROUP BY 1
    HAVING bool_or(sender_id = v_rel.user_a) AND bool_or(sender_id = v_rel.user_b)
  ) qualifying_days;

  IF v_day_count < 3 THEN
    RETURN QUERY SELECT false, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;

  SELECT id, created_at INTO v_first_positive_id, v_first_positive_at
  FROM public.messages
  WHERE relationship_id = p_relationship_id AND sentiment = 'positive'
  ORDER BY created_at ASC
  LIMIT 1;

  IF v_first_positive_id IS NULL THEN
    RETURN QUERY SELECT false, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;

  RETURN QUERY SELECT true, v_first_positive_id, v_first_positive_at;
END;
$$;

REVOKE ALL ON FUNCTION public.ask2_eligibility(uuid) FROM PUBLIC, anon, authenticated;
-- No GRANT to authenticated: this function is service-role-only, called by
-- the evaluate-ask2-eligibility edge function's service-role client, which
-- authenticates via the service_role JWT (bypasses PostgREST's role grants
-- entirely) — the REVOKE above is defence in depth against a client ever
-- calling it directly.
