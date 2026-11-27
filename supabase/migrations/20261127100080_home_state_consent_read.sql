-- Entry gates (2026-11-27) fix round, review M-1: get_my_home_state's
-- 'consent' need reads consent the way private.account_ready and the
-- invite functions do: an accepted time AND a 1-3 digit version >= 2. Until
-- now it read the version only, so an account with a version but no
-- eula_accepted_at would be "complete" to the app's gate and not ready to
-- the server (a loop between the gate and RI-3). Today's writers set both
-- together; this closes the gap for good.
-- public.get_my_home_state() is its LIVE body (pg_get_functiondef on
-- attune_spec3a; last written by 20261103100000_holds_enforced.sql; the
-- drift guard refuses any other body) with one line added to the consent
-- test (`OR v_user.eula_accepted_at IS NULL`) and its comment. search_path
-- was already ''. ACL kept by CREATE OR REPLACE.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- Drift guard: each function must hold exactly the live body this was
-- built from (md5 of prosrc), or already the new one (a re-run).
DO $guard$
DECLARE
  r record;
  v_md5 text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.get_my_home_state()', 'e4d2772d1accfa459303f2866a894f4d', 'bb5b86820069bfb2fca4769299c4385e')
    ) AS t(sig, before_md5, after_md5)
  LOOP
    SELECT pg_catalog.md5(p.prosrc) INTO v_md5
      FROM pg_catalog.pg_proc AS p WHERE p.oid = pg_catalog.to_regprocedure(r.sig);
    IF v_md5 IS NULL THEN
      RAISE EXCEPTION 'entry gates fix round: % is missing', r.sig;
    END IF;
    IF v_md5 NOT IN (r.before_md5, r.after_md5) THEN
      RAISE EXCEPTION 'entry gates fix round: % is not the body this migration was built from (md5 %)', r.sig, v_md5;
    END IF;
  END LOOP;
END $guard$;

CREATE OR REPLACE FUNCTION public.get_my_home_state()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid constant uuid := auth.uid();
  v_user public.users%ROWTYPE;
  v_has_account boolean;
  v_needs text[] := ARRAY[]::text[];
  v_rel public.relationships%ROWTYPE;
  v_state text := 'none';
  v_partner_name text;
  v_tab text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'home:not_signed_in';
  END IF;
  SELECT * INTO v_user FROM public.users AS u WHERE u.id = v_uid;
  v_has_account := FOUND;

  -- The version is a number of at most three digits, read the way
  -- complete_sign_up reads it: anything else counts as not accepted and
  -- never throws (batch 4 fix round 0).
  -- Entry gates 2026-11-27 (fix round, review M-1): consent is read as
  -- private.account_ready reads it, accepted time AND version.
  IF NOT v_has_account
     OR v_user.eula_accepted_at IS NULL
     OR coalesce(substring(v_user.eula_version FROM '^[0-9]{1,3}$')::integer, 0) < 2 THEN
    v_needs := array_append(v_needs, 'consent');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.account_birthdates AS b WHERE b.user_id = v_uid) THEN
    v_needs := array_append(v_needs, 'birth_date');
  END IF;
  -- Read the way complete_sign_up stores it (final review M-1): a name of
  -- invisible or bidi characters only is no name.
  IF NOT v_has_account OR private.normalize_display_name(v_user.display_name) ~ '^\+?[0-9 ()-]*$' THEN
    v_needs := array_append(v_needs, 'name');
  END IF;
  IF v_user.path IS NULL THEN
    v_needs := array_append(v_needs, 'path');
  END IF;

  -- An open (active or paused) relationship ranks first: legacy
  -- accept-invite keeps the acceptor's own pending invite until W4a, and a
  -- linked member must never read as pending (batch 4 review #1).
  SELECT * INTO v_rel FROM public.relationships AS r
   WHERE v_uid IN (r.user_a, r.user_b)
   ORDER BY (r.status IN ('active', 'paused')) DESC, r.created_at DESC, r.id DESC
   LIMIT 1;
  IF FOUND THEN
    v_state := CASE
      WHEN v_rel.status = 'pending' THEN 'pending'
      WHEN v_rel.status = 'active' THEN 'linked'
      WHEN v_rel.status = 'paused' THEN 'paused'
      -- The ending window is the 30 days after the end (spec §3.8 R3,
      -- §3.13), whether or not the chat is still readable: sealing it or
      -- an archive by a new chapter inside those days is still the window
      -- (batch 4 review #7).
      WHEN v_rel.status IN ('ended', 'archived') AND v_rel.ended_at > now() - interval '30 days' THEN 'ended_window'
      ELSE 'after_ending'
    END;
    -- The partner's name only while the space or its ending window is
    -- there, as the lifecycle card shows it; never after the window
    -- (batch 4 review #6). A name, never a phone number (the lifecycle
    -- RPC's guard).
    IF v_state IN ('linked', 'paused', 'ended_window') THEN
      -- Invisible and bidi characters dropped first (final review M-1), so
      -- an override can't spoof it and an invisible-only name reads NULL.
      SELECT CASE WHEN split_part(private.normalize_display_name(p.display_name), ' ', 1) ~ '^\+?[0-9 ()-]*$' THEN NULL
                  ELSE split_part(private.normalize_display_name(p.display_name), ' ', 1) END
        INTO v_partner_name
        FROM public.users AS p
       WHERE p.id = CASE WHEN v_rel.user_a = v_uid THEN v_rel.user_b ELSE v_rel.user_a END;
    END IF;
  END IF;

  -- Chat on the Relationship path. A legacy account that has not chosen a
  -- path yet keeps Chat while its latest relationship is pending, linked or
  -- paused, so the v2 shell never moves a couple onto Me before A6.
  -- A linked or paused member is on Relationship by spec (§3.11, §3.12)
  -- even before a path writer catches up (legacy accept-invite until W4a),
  -- so the tab follows the link (batch 4 review #3).
  v_tab := CASE
    WHEN v_user.path = 'relationship' THEN 'chat'
    WHEN v_state IN ('linked', 'paused') THEN 'chat'
    WHEN v_user.path IS NULL AND v_state IN ('pending', 'linked', 'paused') THEN 'chat'
    ELSE 'me'
  END;

  RETURN jsonb_build_object(
    'has_account', v_has_account,
    'path', v_user.path,
    'tab', v_tab,
    'path_previous', v_user.path_previous,
    'needs', to_jsonb(v_needs),
    'hold', EXISTS (SELECT 1 FROM public.account_holds AS h
                     WHERE h.user_id = v_uid AND h.resolved_at IS NULL),
    -- Spec 1 W6a: which hold, so the phone blocks itself only for an age
    -- hold (age_review first, then safety_review, then recovery_hold).
    'hold_kind', (SELECT h.kind FROM public.account_holds AS h
                   WHERE h.user_id = v_uid AND h.resolved_at IS NULL
                   ORDER BY CASE h.kind WHEN 'age_review' THEN 0 WHEN 'safety_review' THEN 1 ELSE 2 END
                   LIMIT 1),
    'eula_version', v_user.eula_version,
    'dating', private.dating_home_summary(v_uid),
    'link', jsonb_build_object(
      'state', v_state,
      'relationship_id', CASE WHEN v_state = 'none' THEN NULL ELSE v_rel.id END,
      'partner_first_name', v_partner_name,
      'invite_expires_at', CASE WHEN v_state = 'pending' THEN v_rel.invite_expires_at END,
      'window_ends_at', CASE WHEN v_state = 'ended_window' THEN v_rel.ended_at + interval '30 days' END));
END;
$function$;

COMMIT;
