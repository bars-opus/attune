-- Dating flag defense-in-depth (Fable review DATING-H1).
--
-- Two gaps:
--   1. `feature_flags` was client-readable with USING (true), so any authenticated
--      user could enumerate the rollout plan — including `dating_mode_enabled`
--      before launch — and the client-side gate was advisory/spoofable.
--   2. The content-writing reflection RPC skipped `dating_flag_enabled`, so a
--      modified client with an active match row could WRITE dating content while
--      Dating was flagged off.
--
-- Chat also reads `feature_flags` client-side (chat_feature_flags.dart) and MUST
-- keep working, so we do NOT revoke the grant wholesale. Instead we narrow the
-- RLS policy to hide `dating_%` keys from clients: chat keeps its `chat_*` reads,
-- the dating rollout row is no longer exposed, and the dating client derives
-- availability from `get_dating_eligibility()` (which already returns a
-- 'feature_unavailable' reason) rather than the raw table.

-- ---------------------------------------------------------------------------
-- 1. Hide dating rollout flags from clients (chat_* stay readable).
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS feature_flags_authenticated_read ON public.feature_flags;
CREATE POLICY feature_flags_authenticated_read
ON public.feature_flags FOR SELECT TO authenticated
USING (key NOT LIKE 'dating\_%');

-- ---------------------------------------------------------------------------
-- 2. Gate the content-writing reflection RPC on the dating flag. Because
--    record_dating_date_reflection delegates to save_private_date_reflection,
--    guarding this one function covers BOTH reflection write paths without
--    duplicating logic. Body is the v1.2 body verbatim plus one guard line.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.save_private_date_reflection(
  p_idempotency_key text,p_match_id uuid,p_response text,p_note text
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  -- DATING-H1: server is the sole authority; refuse content writes when the
  -- feature is off, even for a user who still holds an active match row.
  IF NOT public.dating_flag_enabled('dating_mode_enabled') THEN
    RAISE EXCEPTION 'dating_unavailable' USING ERRCODE='22023';
  END IF;
  IF p_response NOT IN ('meet_again','unsure','rather_not') THEN
    RAISE EXCEPTION 'invalid_reflection_response' USING ERRCODE='22023';
  END IF;
  IF length(COALESCE(p_note,'')) > 500 THEN
    RAISE EXCEPTION 'reflection_note_too_long' USING ERRCODE='22023';
  END IF;
  PERFORM public.check_dating_rate_limit('save_reflection',20,interval '1 day');
  IF NOT EXISTS (
    SELECT 1 FROM public.dating_matches dm WHERE dm.id=p_match_id
      AND dm.state='active' AND v_user_id IN (dm.user_low_id,dm.user_high_id)
  ) THEN RAISE EXCEPTION 'match_not_found' USING ERRCODE='22023'; END IF;
  IF NOT public.claim_dating_idempotency('save_private_date_reflection',p_idempotency_key) THEN RETURN; END IF;
  INSERT INTO public.dating_date_reflections(match_id,author_user_id,response,note,idempotency_key,created_at,updated_at)
  VALUES(p_match_id,v_user_id,p_response,NULLIF(trim(COALESCE(p_note,'')),''),p_idempotency_key,now(),now())
  ON CONFLICT(match_id,author_user_id) DO UPDATE SET
    response=EXCLUDED.response,note=EXCLUDED.note,idempotency_key=EXCLUDED.idempotency_key,updated_at=now();
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. DATING-H3(b): validate the client-authored idempotency key server-side
--    (length + charset) so a malicious client cannot pre-claim griefing keys or
--    inject oversized/weird values. The claim already runs AFTER auth/membership/
--    validity in each RPC (H3(a) satisfied); this bounds the key space. Body is
--    the current version verbatim plus the format guard.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_dating_idempotency(
  p_operation text,
  p_idempotency_key text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  IF p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
    RAISE EXCEPTION 'idempotency_key_required' USING ERRCODE = '22023';
  END IF;

  -- DATING-H3(b): bound the client key space. Keys are dedup tokens, not secrets,
  -- but a bounded charset/length stops oversized payloads and pre-claim griefing.
  IF char_length(p_idempotency_key) NOT BETWEEN 8 AND 200
     OR p_idempotency_key !~ '^[A-Za-z0-9_:.-]+$' THEN
    RAISE EXCEPTION 'idempotency_key_invalid' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.dating_rpc_idempotency (
    user_id,
    operation,
    idempotency_key
  )
  VALUES (
    v_user_id,
    p_operation,
    p_idempotency_key
  )
  ON CONFLICT DO NOTHING;

  RETURN FOUND;
END;
$$;
