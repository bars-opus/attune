-- Spec 1 W1b, migration 4 of 6 (spec §4.7 #4): paths_and_home_state.
--   * private.spec1_flag_on: the effective Spec 1 flag (§2.5 dependencies);
--     a missing row is off. W1c inserts the rows.
--   * private.dating_home_summary: {enabled, enrolled}, the seam Spec 2 W1b
--     re-creates; no client reads a Dating table for this (I-4, A-10).
--   * set_user_path_internal: the single path writer. It pauses Dating only
--     on a change to relationship (D18); any other change away from Dating
--     is paused by Spec 2 W2's users.path trigger. It names no table a later
--     wave creates (I-6): W5 re-creates it from this live body.
--   * set_my_path, get_my_home_state, and withdraw_my_pending_invites with a
--     return-to-previous-path variant.
--   * onboarding_profiles.mode is dropped: no SQL reader, no fixture; the
--     legacy client stops writing it in the same release.
-- Grants in 20261025100310_paths_and_home_state_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

ALTER TABLE public.onboarding_profiles DROP COLUMN IF EXISTS mode;

CREATE OR REPLACE FUNCTION private.spec1_flag_on(p_key text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_on boolean;
  v_needs text;
BEGIN
  SELECT f.enabled INTO v_on FROM public.feature_flags AS f WHERE f.key = p_key;
  IF NOT coalesce(v_on, false) THEN
    RETURN false;
  END IF;
  v_needs := CASE p_key
               WHEN 'flow_paths_v2' THEN 'flow_signin_v2'
               WHEN 'flow_couples_v2' THEN 'flow_paths_v2'
               WHEN 'couple_profile' THEN 'flow_couples_v2'
             END;
  RETURN v_needs IS NULL OR private.spec1_flag_on(v_needs);
END;
$$;

CREATE OR REPLACE FUNCTION private.dating_home_summary(p_user uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'enabled', public.dating_flag_enabled('dating_mode_enabled'),
    'enrolled', EXISTS (
      SELECT 1 FROM public.dating_enrollments AS e
       WHERE e.user_id = p_user
         AND e.state IN ('profile_draft', 'active', 'paused', 'suspended')));
$$;

CREATE OR REPLACE FUNCTION public.set_user_path_internal(p_user uuid, p_path text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_old text;
  v_chosen_at timestamptz;
  v_elapsed interval;
BEGIN
  IF p_path IS NULL OR p_path NOT IN ('relationship', 'dating', 'just_me') THEN
    RAISE EXCEPTION 'path:invalid';
  END IF;
  SELECT u.path, u.path_chosen_at INTO v_old, v_chosen_at
    FROM public.users AS u WHERE u.id = p_user FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'path:no_account';
  END IF;
  IF v_old IS NOT DISTINCT FROM p_path THEN RETURN; END IF;

  UPDATE public.users
     SET path_previous = v_old,
         path = p_path,
         path_chosen_at = now()
   WHERE id = p_user;

  IF v_old IS NULL THEN
    INSERT INTO public.onboarding_profiles (user_id) VALUES (p_user)
    ON CONFLICT (user_id) DO NOTHING;
    -- Written once, at the first choice, and never re-synced (D14). A status
    -- legacy onboarding already wrote is that one write, so it is kept
    -- (batch 4 review #5).
    INSERT INTO public.profiles AS p (id, relationship_status)
    VALUES (p_user, CASE p_path WHEN 'relationship' THEN 'taken'
                                WHEN 'dating' THEN 'single'
                                ELSE 'figuring_it_out' END)
    ON CONFLICT (id) DO UPDATE
      SET relationship_status = coalesce(p.relationship_status, EXCLUDED.relationship_status);
    PERFORM private.bump_metric_internal('path_chosen:' || p_path);
  ELSE
    v_elapsed := now() - coalesce(v_chosen_at, now());
    IF v_elapsed <= interval '7 days' THEN
      PERFORM private.bump_metric_internal('path_switch_7d:' || v_old || '>' || p_path);
    ELSIF v_elapsed <= interval '30 days' THEN
      PERFORM private.bump_metric_internal('path_switch_30d:' || v_old || '>' || p_path);
    END IF;
  END IF;

  -- The one Dating pause Spec 1 makes (D18).
  IF p_path = 'relationship'
     AND (private.dating_home_summary(p_user) ->> 'enrolled')::boolean THEN
    PERFORM public.pause_dating_for_relationship_user(p_user);
  END IF;
END;
$$;

-- The home's one read (spec §3.11, §3.15, §5.3).
CREATE OR REPLACE FUNCTION public.get_my_home_state()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
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
  IF NOT v_has_account
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
    'eula_version', v_user.eula_version,
    'dating', private.dating_home_summary(v_uid),
    'link', jsonb_build_object(
      'state', v_state,
      'relationship_id', CASE WHEN v_state = 'none' THEN NULL ELSE v_rel.id END,
      'partner_first_name', v_partner_name,
      'invite_expires_at', CASE WHEN v_state = 'pending' THEN v_rel.invite_expires_at END,
      'window_ends_at', CASE WHEN v_state = 'ended_window' THEN v_rel.ended_at + interval '30 days' END));
END;
$$;

-- The return-to-previous variant (spec §4.3 W1b). The zero-argument
-- withdraw_my_pending_invites() stays exactly as it is: the app calls it,
-- invite_age_contracts.sql names it, and scripts/local_pg_grants.sql replays
-- its grants. This overload has no default, so a call without arguments
-- still resolves to the original.
CREATE OR REPLACE FUNCTION public.withdraw_my_pending_invites(p_return_to_previous_path boolean)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid constant uuid := auth.uid();
  v_n integer;
  v_path text;
  v_previous text;
BEGIN
  v_n := public.withdraw_my_pending_invites();
  IF p_return_to_previous_path AND v_n > 0 THEN
    SELECT u.path, u.path_previous INTO v_path, v_previous
      FROM public.users AS u WHERE u.id = v_uid;
    -- Never off Relationship while a relationship is open (spec §3.12): the
    -- stale invite still goes, the path stays (batch 4 review #2).
    IF v_path = 'relationship' AND v_previous IS NOT NULL AND v_previous <> 'relationship'
       AND NOT EXISTS (SELECT 1 FROM public.relationships AS r
                        WHERE v_uid IN (r.user_a, r.user_b) AND r.status IN ('active', 'paused')) THEN
      PERFORM public.set_user_path_internal(v_uid, v_previous);
    END IF;
  END IF;
  RETURN v_n;
END;
$$;

-- A6 and Settings -> How you use Attune (spec §3.7, §3.12).
CREATE OR REPLACE FUNCTION public.set_my_path(p_path text, p_confirmed boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid constant uuid := auth.uid();
  v_current text;
  v_eula text;
  v_age integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'path:not_signed_in';
  END IF;
  IF p_path IS NULL OR p_path NOT IN ('relationship', 'dating', 'just_me') THEN
    RAISE EXCEPTION 'path:invalid';
  END IF;
  -- Locked before the checks, so a concurrent accept or a second device
  -- is serialised with them (batch 4 review #4).
  SELECT u.path, u.eula_version INTO v_current, v_eula
    FROM public.users AS u WHERE u.id = v_uid FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'path:needs_signup';
  END IF;
  v_age := public.account_age(v_uid);
  IF v_age IS NULL OR v_age < 18 THEN
    RAISE EXCEPTION 'path:needs_signup';
  END IF;
  -- EULA 2 or later, read as get_my_home_state reads it (fix round 0).
  IF private.spec1_flag_on('flow_signin_v2')
     AND coalesce(substring(v_eula FROM '^[0-9]{1,3}$')::integer, 0) < 2 THEN
    RAISE EXCEPTION 'path:needs_signup';
  END IF;

  IF p_path <> 'relationship' THEN
    IF EXISTS (SELECT 1 FROM public.relationships AS r
                WHERE v_uid IN (r.user_a, r.user_b) AND r.status IN ('active', 'paused')) THEN
      RAISE EXCEPTION 'path:relationship_open';
    END IF;
    IF EXISTS (SELECT 1 FROM public.relationships AS r
                WHERE r.user_a = v_uid AND r.status = 'pending' AND r.user_b IS NULL) THEN
      IF NOT p_confirmed THEN
        RAISE EXCEPTION 'path:confirm_withdraw';
      END IF;
      PERFORM public.withdraw_my_pending_invites();
    END IF;
  ELSIF v_current IS DISTINCT FROM 'relationship'
        AND (private.dating_home_summary(v_uid) ->> 'enrolled')::boolean
        AND NOT p_confirmed THEN
    RAISE EXCEPTION 'path:confirm_pause_dating';
  END IF;

  PERFORM public.set_user_path_internal(v_uid, p_path);
  RETURN public.get_my_home_state();
END;
$$;

-- Revoked here as well as in the twin (controller ruling after batch 3; the
-- verified_phone precedent): the hosted default privileges grant EXECUTE on
-- a new function to anon and authenticated, and a failed or late twin push
-- must not let a client write any account's path, read any account's Dating
-- summary or probe the flags.
REVOKE ALL ON FUNCTION private.spec1_flag_on(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.dating_home_summary(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_user_path_internal(uuid, text) FROM PUBLIC, anon, authenticated;

COMMIT;
