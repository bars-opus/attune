-- supabase/migrations/20261119115000_dating_v2_block.sql
-- Spec 2 W5b Task 7b (§3.4 the card's "More": "Block"; §3.6 Block; §4.10
-- block_dating_introduction "Keep, wrapper"; owner 2026-11-19: Block on the
-- card now, Report in W7a, plan Ruling R-12 superseded; Ruling R-36).
-- block_dating_introduction re-created from its live body (the rate limit,
-- then block_dating_user on the introduction's other person) in act v2's
-- form: a fixed jsonb answer ({ok: true} | {ok: false, reason: invalid |
-- introduction_unavailable | rate_limited | busy}), never a raised refusal;
-- one answer for an introduction that is not the caller's or does not
-- exist; one block per idempotency key (a replay answers as the first
-- did); the caller's setup lock first, then the introduction row, each
-- wait 2 s, a bounded retry (3), then busy; search_path ''.
-- Ruling R-36: a block only reduces exposure, so neither the phone nor
-- eligibility gates it; the caller must be one of the introduction's two
-- people. block_dating_user (unchanged) writes the pair by id and by phone
-- HMAC (what private.dating_pair_safe reads, so the pair is never
-- introducible again, a new account on the same number included), ends
-- the pair's open introductions for both people (invalidated) and closes an
-- active match (blocked). Nobody is told and nothing is queued. The answer
-- type changes (void to jsonb), so the function is dropped and created; the
-- twin re-asserts its grant. Dating stays off. Idempotent.
BEGIN;
SET LOCAL lock_timeout = '5s';

DROP FUNCTION IF EXISTS public.block_dating_introduction(text, uuid);
CREATE FUNCTION public.block_dating_introduction(p_idempotency_key text, p_introduction_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
-- act v2's wait (Task 4 fix round 1, M-6): each lock wait gives up in 2 s,
-- so the 55P03 arm retries and the third ends 'busy', never a raw timeout.
SET lock_timeout = '2s'
AS $$
DECLARE -- Spec 2 W5b-7b
  v_user constant uuid := auth.uid(); -- Spec 2 W5b-7b
  v_other uuid; -- Spec 2 W5b-7b
  v_try integer; -- Spec 2 W5b-7b
BEGIN
  IF v_user IS NULL THEN -- Spec 2 W5b-7b: as act v2 (no API role reaches here without one)
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; -- Spec 2 W5b-7b
  END IF; -- Spec 2 W5b-7b
  IF p_introduction_id IS NULL OR p_idempotency_key IS NULL -- Spec 2 W5b-7b: act v2's key rule
     OR char_length(p_idempotency_key) NOT BETWEEN 16 AND 128 -- Spec 2 W5b-7b
     OR p_idempotency_key !~ '^[A-Za-z0-9_:.-]+$' THEN -- Spec 2 W5b-7b
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid'); -- Spec 2 W5b-7b
  END IF; -- Spec 2 W5b-7b
  -- Spec 2 W5b-7b (Ruling R-36): no phone check and no eligibility check:
  -- Spec 2 W5b-7b a block only reduces exposure (as the never-introduce add,
  -- Spec 2 W5b-7b W1 B8), and an introduction's id reaches the app only
  -- Spec 2 W5b-7b through the phone-checked reads.
  FOR v_try IN 1..3 LOOP -- Spec 2 W5b-7b
    BEGIN -- Spec 2 W5b-7b
      PERFORM private.dating_lock_setup(v_user); -- Spec 2 W5b-7b: the shared order, the setup lock first
      -- Spec 2 W5b-7b: a replay answers as the first did (only a block claims its key).
      IF EXISTS (SELECT 1 FROM public.dating_rpc_idempotency AS k -- Spec 2 W5b-7b
                  WHERE k.user_id = v_user AND k.operation = 'block_dating_introduction' -- Spec 2 W5b-7b
                    AND k.idempotency_key = p_idempotency_key) THEN -- Spec 2 W5b-7b
        RETURN jsonb_build_object('ok', true); -- Spec 2 W5b-7b
      END IF; -- Spec 2 W5b-7b
      -- Spec 2 W5b-7b (live: resolve_dating_introduction_target, which raised):
      -- Spec 2 W5b-7b the caller's own introduction, in any state, then its row;
      -- Spec 2 W5b-7b one answer for one that is not theirs or does not exist,
      -- Spec 2 W5b-7b whatever the other person did (H2).
      -- Spec 2 W5 final (M-4): exit's row order on a matched pair, the match
      -- Spec 2 W5 final then the introduction: the pair read without a lock,
      -- Spec 2 W5 final its live match locked first, then the row below (read
      -- Spec 2 W5 final again under its lock), so a block and the other's leave
      -- Spec 2 W5 final queue on the match and never deadlock.
      SELECT CASE WHEN i.user_low_id = v_user THEN i.user_high_id ELSE i.user_low_id END INTO v_other -- Spec 2 W5 final (M-4)
        FROM public.dating_introductions AS i -- Spec 2 W5 final (M-4)
       WHERE i.id = p_introduction_id AND v_user IN (i.user_low_id, i.user_high_id); -- Spec 2 W5 final (M-4)
      IF FOUND THEN -- Spec 2 W5 final (M-4)
        PERFORM 1 FROM public.dating_matches AS m -- Spec 2 W5 final (M-4)
         WHERE m.user_low_id = least(v_user, v_other) AND m.user_high_id = greatest(v_user, v_other) -- Spec 2 W5 final (M-4)
           AND m.state = 'active' -- Spec 2 W5 final (M-4)
         ORDER BY m.id FOR UPDATE; -- Spec 2 W5 final (M-4)
      END IF; -- Spec 2 W5 final (M-4)
      SELECT CASE WHEN i.user_low_id = v_user THEN i.user_high_id ELSE i.user_low_id END INTO v_other -- Spec 2 W5b-7b
        FROM public.dating_introductions AS i -- Spec 2 W5b-7b
       WHERE i.id = p_introduction_id AND v_user IN (i.user_low_id, i.user_high_id) -- Spec 2 W5b-7b
       FOR UPDATE; -- Spec 2 W5b-7b
      IF NOT FOUND THEN -- Spec 2 W5b-7b
        RETURN jsonb_build_object('ok', false, 'reason', 'introduction_unavailable'); -- Spec 2 W5b-7b
      END IF; -- Spec 2 W5b-7b
      BEGIN -- Spec 2 W5b-7b (live: the same limit, raised)
        PERFORM public.check_dating_rate_limit('block', 20, interval '1 day'); -- Spec 2 W5b-7b
      EXCEPTION WHEN invalid_parameter_value THEN -- Spec 2 W5b-7b
        IF SQLERRM IS DISTINCT FROM 'rate_limited' THEN -- Spec 2 W5b-7b
          RAISE; -- Spec 2 W5b-7b
        END IF; -- Spec 2 W5b-7b
        RETURN jsonb_build_object('ok', false, 'reason', 'rate_limited'); -- Spec 2 W5b-7b
      END; -- Spec 2 W5b-7b
      PERFORM public.claim_dating_idempotency('block_dating_introduction', p_idempotency_key); -- Spec 2 W5b-7b
      PERFORM public.block_dating_user(p_idempotency_key, v_other); -- Spec 2 W5b-7b (live: the same call)
      PERFORM private.bump_metric_internal('dating.block'); -- Spec 2 W5b-7b (§6.9 metrics)
      RETURN jsonb_build_object('ok', true); -- Spec 2 W5b-7b
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W5b-7b
      IF v_try = 3 THEN -- Spec 2 W5b-7b
        RETURN jsonb_build_object('ok', false, 'reason', 'busy'); -- Spec 2 W5b-7b
      END IF; -- Spec 2 W5b-7b
    END; -- Spec 2 W5b-7b
  END LOOP; -- Spec 2 W5b-7b
  RETURN jsonb_build_object('ok', false, 'reason', 'busy'); -- Spec 2 W5b-7b
END;
$$;

-- Grants (re-asserted by the twin): the app's, never anon's or the
-- service role's (it acts as auth.uid()).
REVOKE ALL ON FUNCTION public.block_dating_introduction(text, uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.block_dating_introduction(text, uuid) TO authenticated;
COMMIT;
