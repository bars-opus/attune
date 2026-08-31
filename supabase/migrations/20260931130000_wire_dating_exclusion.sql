-- Dating former-partner exclusion was built but never connected.
--
-- record_dating_former_partner_exclusion() has existed since July with no
-- caller anywhere: not end_relationship, not the end-relationship Edge
-- Function, not a trigger. The only thing that has ever invoked it is a
-- contract test. Separately, the phone-HMAC it stores comes from
-- dating_phone_hmac(), which read a key from app.settings.* -- a
-- mechanism that cannot be set on a managed project (see
-- 20260931120000). So the feature had two independent faults: nothing
-- called it, and had anything called it, it would have hashed to NULL
-- and inserted nothing.
--
-- The promise being kept here is a privacy one: when a couple ends a
-- relationship, neither should be surfaced to the other in dating.
--
-- The hook goes on end_relationship rather than the Edge Function so it
-- covers every path that ends a relationship, including any future one.

-- ---------------------------------------------------------------------
-- 1. Let the recorder run inside an authenticated transaction.
-- ---------------------------------------------------------------------

-- The original refuses an authenticated caller outright, to keep clients
-- from writing exclusions directly. But end_relationship runs as the
-- user who is ending it, so calling it from there would trip that guard
-- and raise 42501 -- breaking the end-relationship flow entirely.
--
-- The guard is preserved for DIRECT calls, which is what it was for. The
-- new p_internal argument is how end_relationship (itself SECURITY
-- DEFINER, and reached only after it has verified the caller belongs to
-- the relationship) says the check has already been done. A client
-- calling the RPC cannot set it: EXECUTE is still service_role only.
-- The single-argument signature is dropped rather than left in place:
-- CREATE OR REPLACE cannot add a defaulted parameter to an existing
-- function, so the two would coexist as overloads and every existing
-- one-argument call site -- including the dating contract test -- would
-- fail with "is not unique".
DROP FUNCTION IF EXISTS public.record_dating_former_partner_exclusion(uuid);

CREATE OR REPLACE FUNCTION public.record_dating_former_partner_exclusion(
  p_relationship_id uuid,
  p_internal boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rel public.relationships%ROWTYPE;
  v_phone_a text; v_phone_b text;
  v_hmac_a text;  v_hmac_b text;
BEGIN
  IF NOT p_internal
     AND auth.role() IS NOT NULL
     AND auth.role() = 'authenticated' THEN
    RAISE EXCEPTION 'exclusion_write_is_backend_only' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_rel FROM public.relationships WHERE id = p_relationship_id;
  IF NOT FOUND OR v_rel.user_b IS NULL THEN RETURN; END IF;

  SELECT phone INTO v_phone_a FROM public.users WHERE id = v_rel.user_a;
  SELECT phone INTO v_phone_b FROM public.users WHERE id = v_rel.user_b;
  v_hmac_a := public.dating_phone_hmac(v_phone_a);
  v_hmac_b := public.dating_phone_hmac(v_phone_b);

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
$$;

REVOKE ALL ON FUNCTION public.record_dating_former_partner_exclusion(uuid, boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_dating_former_partner_exclusion(uuid, boolean)
  TO service_role;

-- ---------------------------------------------------------------------
-- 2. Call it when a relationship ends.
-- ---------------------------------------------------------------------

-- Body preserved from the live definition; the exclusion call is the
-- only addition.
CREATE OR REPLACE FUNCTION public.end_relationship(p_relationship_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_relationship public.relationships%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_relationship
  FROM public.relationships
  WHERE id = p_relationship_id
    AND status = 'active'
    AND (user_a = v_user_id OR user_b = v_user_id)
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Relationship not found or not active';
  END IF;

  UPDATE public.relationships
  SET status = 'ended',
      ended_at = now(),
      ended_by = v_user_id,
      chat_archived_at = now(),
      chat_archived_reason = 'manual_end'
  WHERE id = p_relationship_id;

  -- Recorded in the same transaction as the status change: an exclusion
  -- written only on a best-effort second call could be lost exactly when
  -- it matters, leaving a just-ended partner visible in dating.
  --
  -- Wrapped so it cannot fail the end itself. If the exclusion cannot be
  -- written -- an unset dating_exclusion_key, a party with no phone --
  -- ending the relationship must still succeed; the alternative is a
  -- user unable to leave a relationship because of a dating feature.
  BEGIN
    PERFORM public.record_dating_former_partner_exclusion(
      p_relationship_id, true
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'exclusion not recorded for %: %', p_relationship_id, sqlerrm;
  END;
END;
$$;

-- ---------------------------------------------------------------------
-- 3. Backfill the relationships that already ended.
-- ---------------------------------------------------------------------

-- Every relationship ended before this migration recorded no exclusion,
-- so those former partners are still mutually visible in dating. This
-- replays the recorder over them.
--
-- Idempotent: the inserts are ON CONFLICT DO NOTHING, so re-running is
-- harmless. Rows whose parties have no phone, or that predate the
-- dating_exclusion_key being stored in Vault, simply insert nothing --
-- which is why this migration must be applied AFTER the secret exists.
DO $$
DECLARE
  v_rel record;
  v_done int := 0;
BEGIN
  IF public.app_setting('dating_exclusion_key') IS NULL THEN
    RAISE WARNING
      'dating_exclusion_key is not set; skipping backfill. '
      'Store it with vault.create_secret(), then run: '
      'SELECT public.backfill_dating_former_partner_exclusions();';
    RETURN;
  END IF;

  FOR v_rel IN
    SELECT id FROM public.relationships
    WHERE status = 'ended' AND user_b IS NOT NULL
  LOOP
    PERFORM public.record_dating_former_partner_exclusion(v_rel.id, true);
    v_done := v_done + 1;
  END LOOP;

  RAISE NOTICE 'backfilled exclusions for % ended relationships', v_done;
END $$;

-- Kept as a callable function so the backfill can be run by hand after
-- the secret is stored, without editing an applied migration.
CREATE OR REPLACE FUNCTION public.backfill_dating_former_partner_exclusions()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rel record;
  v_done int := 0;
BEGIN
  IF public.app_setting('dating_exclusion_key') IS NULL THEN
    RAISE EXCEPTION 'dating_exclusion_key is not set; store it in Vault first';
  END IF;

  FOR v_rel IN
    SELECT id FROM public.relationships
    WHERE status = 'ended' AND user_b IS NOT NULL
  LOOP
    PERFORM public.record_dating_former_partner_exclusion(v_rel.id, true);
    v_done := v_done + 1;
  END LOOP;

  RETURN v_done;
END;
$$;

REVOKE ALL ON FUNCTION public.backfill_dating_former_partner_exclusions()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.backfill_dating_former_partner_exclusions()
  TO service_role;
