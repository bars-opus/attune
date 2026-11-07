-- Spec 2 W1a, migration 1 (spec §4.9 W1a #1, §4.1, §6.3, §7.1; I-11):
-- every Dating phone HMAC comes from auth.users, never public.users.
--   * dating_phone_canonical(text): '+' || digits (NULL when there are none),
--     the exact form consume_fresh_start hashes (S1 W6a, I-11). It normalises
--     a number that is already E.164 (Auth's); it does not validate one, so
--     a caller that takes a typed number checks ^\+[1-9][0-9]{7,14}$ first
--     (W1d's add_dating_never_introduce).
--   * dating_phone_hmac_for_user(uuid): auth.users.phone, canonical, through
--     the existing dating_phone_hmac(text); for a parked account (Spec 1's
--     users.phone_released_at set, or Auth already on the +999 placeholder)
--     Spec 1's users.parked_phone_hmac, or NULL. Never the +999 HMAC.
--   * record_dating_former_partner_exclusion, dating_former_partner_excluded
--     and backfill_dating_former_partner_exclusions re-created from their
--     live bodies (20260931130000, 20260712160000) with only the lines marked
--     "Spec 2 W1a": the recorder and the predicate read the helper; the
--     recorder also skips a relationship whose user_a is gone (a NULL
--     user_id would fail its NOT NULL); the backfill covers 'archived' too;
--     and the predicate also holds while both accounts still have their
--     ended or archived Attune relationship, so a later number change can't
--     undo the exclusion (plan P-4); that check runs first and decides
--     without a key. The predicate also matches rows in their pre-W1a stored
--     form (the HMAC of Auth's number as digits, which public.users.phone mirrored),
--     read from auth.users and never for a parked account, so a row this
--     migration can't rebuild keeps working.
--   * private.dating_recompute_former_partner_exclusions(): rebuilds, from
--     auth.users, every row of an ended or archived relationship whose two
--     members both still have an HMAC, and keeps every other row as stored
--     (an ex-partner who deleted their account and comes back on the same
--     number is still excluded, §7.1). It runs here; without
--     dating_exclusion_key it changes nothing and a NOTICE says to run the
--     backfill after setting it.
--   * The relationship guard trigger now calls the null-safe
--     sync_dating_pause_on_relationship() (pending, active and paused);
--     handle_relationship_dating_guard() is dropped.
-- Nothing here is granted to a client, and the helpers, the predicate and
-- the recompute not to the service role either. Grants in
-- 20261106100010_dating_v2_phone_hmac_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- Normalises an E.164 number ('+' || digits); not a validator (see the header).
CREATE OR REPLACE FUNCTION public.dating_phone_canonical(p_phone text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT CASE WHEN d.digits = '' THEN NULL ELSE '+' || d.digits END
    FROM (SELECT pg_catalog.regexp_replace(coalesce(p_phone, ''), '\D', '', 'g') AS digits) AS d;
$fn$;

CREATE OR REPLACE FUNCTION public.dating_phone_hmac_for_user(p_user uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_released timestamptz;
  v_parked text;
  v_phone text;
BEGIN
  IF p_user IS NULL THEN
    RETURN NULL;
  END IF;
  SELECT u.phone_released_at, u.parked_phone_hmac INTO v_released, v_parked
    FROM public.users AS u WHERE u.id = p_user;
  SELECT a.phone INTO v_phone FROM auth.users AS a WHERE a.id = p_user;
  -- A parked account (I-11): the real number's HMAC, written by
  -- consume_fresh_start before the park, or NULL when the key was missing
  -- then. Never the HMAC of Spec 1's +999 placeholder, even in the moment
  -- between Auth's rewrite and mark_fresh_start_parked.
  IF v_released IS NOT NULL OR coalesce(v_phone, '') ~ '^\+?999[0-9]{12}$' THEN
    RETURN v_parked;
  END IF;
  RETURN public.dating_phone_hmac(public.dating_phone_canonical(v_phone));
END;
$fn$;

CREATE OR REPLACE FUNCTION public.record_dating_former_partner_exclusion(p_relationship_id uuid, p_internal boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rel public.relationships%ROWTYPE;
  v_hmac_a text;  v_hmac_b text;
BEGIN
  IF NOT p_internal
     AND auth.role() IS NOT NULL
     AND auth.role() = 'authenticated' THEN
    RAISE EXCEPTION 'exclusion_write_is_backend_only' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_rel FROM public.relationships WHERE id = p_relationship_id;
  IF NOT FOUND OR v_rel.user_a IS NULL OR v_rel.user_b IS NULL THEN RETURN; END IF; -- Spec 2 W1a
  v_hmac_a := public.dating_phone_hmac_for_user(v_rel.user_a); -- Spec 2 W1a: auth.users
  v_hmac_b := public.dating_phone_hmac_for_user(v_rel.user_b); -- Spec 2 W1a: auth.users

  -- Protect A from B (store B's phone-HMAC against A) and vice-versa.
  IF v_hmac_b IS NOT NULL THEN
    INSERT INTO public.dating_former_partner_exclusions(user_id, excluded_phone_hmac, relationship_id)
    VALUES (v_rel.user_a, v_hmac_b, p_relationship_id)
    ON CONFLICT (user_id, excluded_phone_hmac) DO NOTHING;
  END IF;
  IF v_hmac_a IS NOT NULL THEN
    INSERT INTO public.dating_former_partner_exclusions(user_id, excluded_phone_hmac, relationship_id)
    VALUES (v_rel.user_b, v_hmac_a, p_relationship_id)
    ON CONFLICT (user_id, excluded_phone_hmac) DO NOTHING;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.dating_former_partner_excluded(p_user_a uuid, p_user_b uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_hmac_a text;  v_hmac_b text;
  v_leg_a text;  v_leg_b text; -- Spec 2 W1a: the pre-W1a stored form
BEGIN
  IF EXISTS ( -- Spec 2 W1a: while both accounts exist, their ended Attune relationship itself
      SELECT 1 FROM public.relationships r
      WHERE r.status IN ('ended', 'archived')
        AND ((r.user_a = p_user_a AND r.user_b = p_user_b) OR (r.user_a = p_user_b AND r.user_b = p_user_a))) THEN
    RETURN true; -- Spec 2 W1a
  END IF; -- Spec 2 W1a
  v_hmac_a := public.dating_phone_hmac_for_user(p_user_a); -- Spec 2 W1a: auth.users
  v_hmac_b := public.dating_phone_hmac_for_user(p_user_b); -- Spec 2 W1a: auth.users

  -- A is protected from B's phone, OR B is protected from A's phone.
  IF (v_hmac_b IS NOT NULL AND EXISTS ( -- Spec 2 W1a
       SELECT 1 FROM public.dating_former_partner_exclusions e
       WHERE e.user_id = p_user_a AND e.excluded_phone_hmac = v_hmac_b))
    OR
    (v_hmac_a IS NOT NULL AND EXISTS (
       SELECT 1 FROM public.dating_former_partner_exclusions e
       WHERE e.user_id = p_user_b AND e.excluded_phone_hmac = v_hmac_a)) THEN -- Spec 2 W1a
    RETURN true; -- Spec 2 W1a
  END IF; -- Spec 2 W1a

  -- Spec 2 W1a: rows written before W1a hash Auth's raw number (the
  -- public.users mirror, digits only, no '+'). Read from auth.users, never
  -- public.users, as digits whatever the formatting, and never for a parked
  -- account (released, or Auth already on the +999 placeholder).
  v_leg_a := (SELECT public.dating_phone_hmac(nullif(pg_catalog.regexp_replace(a.phone, '\D', '', 'g'), '')) -- Spec 2 W1a
               FROM auth.users a LEFT JOIN public.users u ON u.id = a.id -- Spec 2 W1a
               WHERE a.id = p_user_a AND u.phone_released_at IS NULL -- Spec 2 W1a
                 AND coalesce(a.phone, '') !~ '^\+?999[0-9]{12}$'); -- Spec 2 W1a
  v_leg_b := (SELECT public.dating_phone_hmac(nullif(pg_catalog.regexp_replace(a.phone, '\D', '', 'g'), '')) -- Spec 2 W1a
               FROM auth.users a LEFT JOIN public.users u ON u.id = a.id -- Spec 2 W1a
               WHERE a.id = p_user_b AND u.phone_released_at IS NULL -- Spec 2 W1a
                 AND coalesce(a.phone, '') !~ '^\+?999[0-9]{12}$'); -- Spec 2 W1a
  RETURN -- Spec 2 W1a
    (v_leg_b IS NOT NULL AND EXISTS ( -- Spec 2 W1a
       SELECT 1 FROM public.dating_former_partner_exclusions e -- Spec 2 W1a
       WHERE e.user_id = p_user_a AND e.excluded_phone_hmac = v_leg_b)) -- Spec 2 W1a
    OR -- Spec 2 W1a
    (v_leg_a IS NOT NULL AND EXISTS ( -- Spec 2 W1a
       SELECT 1 FROM public.dating_former_partner_exclusions e -- Spec 2 W1a
       WHERE e.user_id = p_user_b AND e.excluded_phone_hmac = v_leg_a)); -- Spec 2 W1a
END;
$function$;

CREATE OR REPLACE FUNCTION public.backfill_dating_former_partner_exclusions()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rel record;
  v_done int := 0;
BEGIN
  IF public.app_setting('dating_exclusion_key') IS NULL THEN
    RAISE EXCEPTION 'dating_exclusion_key is not set; store it in Vault first';
  END IF;

  FOR v_rel IN
    SELECT id FROM public.relationships
    WHERE status IN ('ended', 'archived') AND user_b IS NOT NULL -- Spec 2 W1a: archived too
  LOOP
    PERFORM public.record_dating_former_partner_exclusion(v_rel.id, true);
    v_done := v_done + 1;
  END LOOP;

  RETURN v_done;
END;
$function$;

-- Recompute the exclusions from auth.users (the old rows were keyed by
-- public.users.phone). Only rows the backfill rebuilds are deleted: both
-- members of their ended or archived relationship still have an HMAC. Any
-- other row (a member deleted their account or is parked without an HMAC,
-- or the relationship is gone) is kept as stored, and the predicate reads
-- that form too. -1 (and a NOTICE) without the key; otherwise the
-- backfill's count.
CREATE OR REPLACE FUNCTION private.dating_recompute_former_partner_exclusions()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  IF public.app_setting('dating_exclusion_key') IS NULL THEN
    RAISE NOTICE 'dating_v2_phone_hmac: dating_exclusion_key is not set, so exclusions were not recomputed; run select public.backfill_dating_former_partner_exclusions(); after setting it';
    RETURN -1;
  END IF;
  DELETE FROM public.dating_former_partner_exclusions AS e
   USING public.relationships AS r
   WHERE e.relationship_id = r.id AND r.status IN ('ended', 'archived')
     AND public.dating_phone_hmac_for_user(r.user_a) IS NOT NULL
     AND public.dating_phone_hmac_for_user(r.user_b) IS NOT NULL;
  RETURN public.backfill_dating_former_partner_exclusions();
END;
$fn$;
REVOKE ALL ON FUNCTION private.dating_recompute_former_partner_exclusions() FROM PUBLIC, anon, authenticated, service_role;

DO $do$
BEGIN
  PERFORM private.dating_recompute_former_partner_exclusions();
END
$do$;

-- The guard trigger calls the null-safe function (it covers paused too).
CREATE OR REPLACE TRIGGER relationship_dating_guard
  AFTER INSERT OR UPDATE OF status, user_b ON public.relationships
  FOR EACH ROW EXECUTE FUNCTION public.sync_dating_pause_on_relationship();
DROP FUNCTION IF EXISTS public.handle_relationship_dating_guard();

REVOKE ALL ON FUNCTION public.dating_phone_canonical(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_phone_hmac_for_user(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_former_partner_excluded(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.record_dating_former_partner_exclusion(uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.backfill_dating_former_partner_exclusions() FROM PUBLIC, anon, authenticated;

COMMIT;
