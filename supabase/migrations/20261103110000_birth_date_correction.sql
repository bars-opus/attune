-- Spec 1 W6b, migration 12 (spec §4.7 #12): birth_date_correction.
--   * private.birth_date_correction_open(p_user): the one rule for "Fix a
--     mistake" (§3.15, §4.3 W6b): a declared date of birth, never
--     self-corrected, declared under 7 days ago, no Dating enrollment
--     in 'active', and no open account hold of any kind (review B6 I-1: a
--     self-confessed minor can't rewrite the date the hold rests on;
--     support corrects through 'support_corrected'). Spec 2 re-creates it
--     from its live body if Dating's state moves elsewhere (plan P-21).
--   * correct_my_birth_date(p_birth_date) -> jsonb (authenticated): once;
--     outside the rule birth_date:correction_closed. The same date again
--     changes and spends nothing; while a hold is open it is closed too,
--     except an under-18 date, which is always not_eligible, never ok
--     (review B7 I-1: a lost answer retried). Under 18 -> an age_review hold and
--     {status:'not_eligible'} WITHOUT raising, so the hold and the date
--     commit (set_my_birth_date's pattern). The date is never returned.
--   * get_my_birth_date_status() -> jsonb (authenticated): {age,
--     can_correct, correct_until} for Settings -> Date of birth; never the
--     date itself (plan P-22).
-- Grants in 20261103110010_birth_date_correction_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION private.birth_date_correction_open(p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.account_birthdates AS b
                  WHERE b.user_id = p_user
                    AND b.self_corrections = 0
                    AND b.declared_at > now() - interval '7 days')
     AND NOT EXISTS (SELECT 1 FROM public.dating_enrollments AS e
                      WHERE e.user_id = p_user AND e.state = 'active')
     AND NOT EXISTS (SELECT 1 FROM public.account_holds AS h
                      WHERE h.user_id = p_user AND h.resolved_at IS NULL);
$$;

CREATE OR REPLACE FUNCTION public.correct_my_birth_date(p_birth_date date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid constant uuid := auth.uid();
  v_stored date;
  v_age integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'birth_date:not_signed_in';
  END IF;
  IF p_birth_date IS NULL OR p_birth_date < DATE '1900-01-01'
     OR p_birth_date > (now() AT TIME ZONE 'utc')::date THEN
    RAISE EXCEPTION 'birth_date:invalid';
  END IF;
  -- The users row first, then the date (the order the path writer and the
  -- accept use), so a correction and a Dating activation serialise.
  PERFORM 1 FROM public.users AS u WHERE u.id = v_uid FOR UPDATE;
  SELECT b.birth_date INTO v_stored
    FROM public.account_birthdates AS b WHERE b.user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'birth_date:not_set';
  END IF;
  -- Review B7 I-1: the holds before the same-date answer, and an under-18
  -- date is never 'ok'. A retry whose not_eligible answer was lost (the
  -- date stored, the hold open) is told not_eligible again; anything else
  -- while a hold is open is closed (B6 I-1), the same date included.
  IF EXISTS (SELECT 1 FROM public.account_holds AS h
              WHERE h.user_id = v_uid AND h.resolved_at IS NULL) THEN
    IF v_stored = p_birth_date AND private.age_on_utc_today(v_stored) < 18 THEN
      RETURN jsonb_build_object('status', 'not_eligible');
    END IF;
    RAISE EXCEPTION 'birth_date:correction_closed';
  END IF;
  IF v_stored = p_birth_date THEN
    v_age := private.age_on_utc_today(v_stored);
    IF v_age < 18 THEN
      -- Under 18 with no open hold (never expected: support corrects the
      -- date before resolving): hold the account again.
      PERFORM public.place_account_hold(v_uid, 'age_review', 'self_corrected_birth_date');
      RETURN jsonb_build_object('status', 'not_eligible');
    END IF;
    RETURN jsonb_build_object('status', 'ok', 'age', v_age, 'changed', false);
  END IF;
  IF NOT private.birth_date_correction_open(v_uid) THEN
    RAISE EXCEPTION 'birth_date:correction_closed';
  END IF;

  UPDATE public.account_birthdates AS b
     SET birth_date = p_birth_date,
         self_corrections = b.self_corrections + 1,
         corrected_at = now()
   WHERE b.user_id = v_uid;

  v_age := private.age_on_utc_today(p_birth_date);
  IF v_age < 18 THEN
    PERFORM public.place_account_hold(v_uid, 'age_review', 'self_corrected_birth_date');
    RETURN jsonb_build_object('status', 'not_eligible');
  END IF;
  RETURN jsonb_build_object('status', 'ok', 'age', v_age, 'changed', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_birth_date_status()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(
    (SELECT jsonb_build_object(
              'age', private.age_on_utc_today(b.birth_date),
              'can_correct', private.birth_date_correction_open(b.user_id),
              'correct_until', CASE WHEN private.birth_date_correction_open(b.user_id)
                                    THEN b.declared_at + interval '7 days' END)
       FROM public.account_birthdates AS b
      WHERE b.user_id = auth.uid()),
    jsonb_build_object('age', NULL, 'can_correct', false, 'correct_until', NULL));
$$;

REVOKE ALL ON FUNCTION private.birth_date_correction_open(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.correct_my_birth_date(date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_birth_date_status() FROM PUBLIC, anon;

COMMIT;
