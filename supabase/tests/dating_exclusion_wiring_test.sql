-- Ending a relationship must record the former-partner exclusion.
--
-- record_dating_former_partner_exclusion() existed from July with NO
-- caller: not end_relationship, not the end-relationship Edge Function,
-- not a trigger. The only thing that ever invoked it was a contract test
-- calling it directly, which is why the gap survived -- the test proved
-- the recorder works, never that anything runs it.
--
-- These tests exercise the path a real breakup takes: end_relationship
-- as the authenticated user, then assert the exclusion rows exist.

BEGIN;

-- The recorder hashes phones through dating_phone_hmac, which reads the
-- key via app_setting(). Seeded in Vault so the local run has one.
SELECT vault.create_secret('test-exclusion-key-wiring', 'dating_exclusion_key');

-- Defined here rather than reused: the equivalents live inside
-- dating_mode_contracts.sql, and each test file runs in its own psql
-- session. Clearing the JWT claims matters as much as RESET ROLE --
-- auth.role() reads the claims, so a stale one keeps the backend-only
-- guard rejecting calls that should now be allowed.
CREATE OR REPLACE FUNCTION pg_temp.set_auth(p_user_id uuid)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p_user_id::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_user_id, 'role', 'authenticated')::text, true);
END;
$fn$;

CREATE OR REPLACE FUNCTION pg_temp.clear_auth()
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  RESET ROLE;
END;
$fn$;


DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-0000000e0a01';
  b uuid := '00000000-0000-0000-0000-0000000e0b02';
  v_rel uuid;
  v int;
BEGIN
  INSERT INTO auth.users(id) VALUES (a), (b) ON CONFLICT DO NOTHING;
  INSERT INTO public.users(id, phone, display_name)
  VALUES (a, '+15550000001', 'A'), (b, '+15550000002', 'B')
  ON CONFLICT (id) DO UPDATE SET phone = EXCLUDED.phone;

  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES (a, b, 'active') RETURNING id INTO v_rel;

  -- The real path: the user ending it is authenticated, which is exactly
  -- the case the recorder's backend-only guard rejects. If end_relationship
  -- called it without the internal flag this would raise 42501 and the
  -- breakup itself would fail.
  PERFORM pg_temp.set_auth(a);
  PERFORM public.end_relationship(v_rel);
  PERFORM pg_temp.clear_auth();

  IF (SELECT status FROM public.relationships WHERE id = v_rel) <> 'ended' THEN
    RAISE EXCEPTION 'relationship did not end';
  END IF;

  -- Symmetric: each party is protected from the other.
  SELECT count(*) INTO v FROM public.dating_former_partner_exclusions
  WHERE relationship_id = v_rel;
  IF v <> 2 THEN
    RAISE EXCEPTION 'expected 2 exclusion rows after ending, got %', v;
  END IF;
END $$;

-- A client must still not be able to write exclusions directly. The
-- p_internal flag is how end_relationship says the check already
-- happened; it must not become a way around the guard.
--
-- Asserted on the DEFAULT rather than by calling as `authenticated`:
-- EXECUTE is revoked from that role, so such a call is refused on
-- privilege whatever the flag says, and the test would pass even if the
-- default flipped to true. This checks the thing that would actually
-- change -- an omitted argument must mean "not internal", so the
-- backend-only guard still applies to any caller that reaches the body.
DO $$
DECLARE
  v_default boolean;
BEGIN
  SELECT p.proargdefaults IS NOT NULL
         AND pg_get_expr(p.proargdefaults, 0) LIKE '%false%'
  INTO v_default
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'record_dating_former_partner_exclusion';

  IF NOT COALESCE(v_default, false) THEN
    RAISE EXCEPTION
      'p_internal must default to false, or omitting it silently '
      'bypasses the backend-only guard';
  END IF;
END $$;

-- And the guard itself still fires when the body is reached without the
-- flag. service_role holds EXECUTE, so this exercises the check rather
-- than the grant.
DO $$
DECLARE
  v_refused boolean := false;
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  BEGIN
    PERFORM public.record_dating_former_partner_exclusion(gen_random_uuid());
  EXCEPTION WHEN OTHERS THEN
    v_refused := true;
  END;
  PERFORM pg_temp.clear_auth();

  IF NOT v_refused THEN
    RAISE EXCEPTION 'the backend-only guard did not fire';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- Operational health surfaces the exclusion key (checklist 4.9).
--
-- An unset key makes end_relationship record no exclusion and raise only a
-- WARNING, leaving former partners mutually matchable with nothing to show
-- it. Health must report both the key's presence and the relationships that
-- already ended without an exclusion row.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_health jsonb;
BEGIN
  v_health := public.get_dating_operational_health();

  IF NOT (v_health ? 'exclusion_key_present') THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: health does not report exclusion_key_present';
  END IF;
  IF (v_health->>'exclusion_key_present')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: the key is set but health reports it absent';
  END IF;
  IF NOT (v_health ? 'relationships_ended_without_exclusion_24h') THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: health omits relationships_ended_without_exclusion_24h';
  END IF;
  -- Every relationship ended so far in this test ran WITH the key set, so
  -- the recorder ran and the gap count must be zero. A non-zero value means
  -- an exclusion failed silently on a path the earlier assertions missed.
  IF (v_health->>'relationships_ended_without_exclusion_24h')::int <> 0 THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: % ended relationship(s) recorded no exclusion',
      v_health->>'relationships_ended_without_exclusion_24h';
  END IF;
END $$;

-- Ending must survive a failure to record. A user has to be able to
-- leave a relationship even when the dating key is missing; the
-- alternative is being trapped by a feature they may not even use.
DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-0000000e0a03';
  b uuid := '00000000-0000-0000-0000-0000000e0b04';
  v_rel uuid;
BEGIN
  DELETE FROM vault.decrypted_secrets WHERE name = 'dating_exclusion_key';

  INSERT INTO auth.users(id) VALUES (a), (b) ON CONFLICT DO NOTHING;
  INSERT INTO public.users(id, phone, display_name)
  VALUES (a, '+15550000003', 'C'), (b, '+15550000004', 'D')
  ON CONFLICT (id) DO UPDATE SET phone = EXCLUDED.phone;
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES (a, b, 'active') RETURNING id INTO v_rel;

  PERFORM pg_temp.set_auth(a);
  PERFORM public.end_relationship(v_rel);
  PERFORM pg_temp.clear_auth();

  IF (SELECT status FROM public.relationships WHERE id = v_rel) <> 'ended' THEN
    RAISE EXCEPTION 'an unset dating key blocked ending a relationship';
  END IF;

  -- The silent failure just happened: this relationship ended and recorded
  -- no exclusion, so the two former partners stay mutually matchable. That
  -- is precisely what health must surface -- a counter that cannot count
  -- past zero would report the system healthy while the damage accrues.
  IF EXISTS (SELECT 1 FROM public.dating_former_partner_exclusions
             WHERE relationship_id = v_rel) THEN
    RAISE EXCEPTION
      'an exclusion was recorded without a key -- test premise is wrong';
  END IF;
  IF (public.get_dating_operational_health()
       ->>'relationships_ended_without_exclusion_24h')::int < 1 THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: health missed a relationship that ended with no exclusion';
  END IF;
  IF (public.get_dating_operational_health()
       ->>'exclusion_key_present')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: health reports a key that is not set';
  END IF;
END $$;

-- The backfill refuses to run silently against a missing key: a run that
-- reports success while inserting nothing is how the original fault
-- stayed hidden for two months.
DO $$
DECLARE
  v_raised boolean := false;
BEGIN
  BEGIN
    PERFORM public.backfill_dating_former_partner_exclusions();
  EXCEPTION WHEN OTHERS THEN
    v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION 'backfill should refuse to run without the key';
  END IF;
END $$;

ROLLBACK;
