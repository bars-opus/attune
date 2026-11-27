-- Entry gates (2026-11-27 audit, gaps 1 and 10): the invite age and
-- consent checks no longer depend on flow_signin_v2. Each function is its
-- LIVE body (pg_get_functiondef on attune_spec3a; last written by
-- 20261102100000_accept_invite_v2.sql) with only the lines below changed.
--   * public.relationship_invite_eligibility(uuid): the flag-off answer
--     'legacy' is gone (the invite edge functions' ensureUserRow, which it
--     unlocked, is deleted in the same wave). Answers, in order:
--       signup_incomplete  no users row
--       age_required       no date of birth on file
--       not_possible       under 18
--       consent_required   NEW: EULA version 2 or later not accepted
--                          (read as get_my_home_state reads it)
--       ok
--     The edge guard (_shared/sign_up_guard.ts) answers consent_required
--     with its existing 409 signup:incomplete, which the app already
--     resolves by finishing sign-up (the gate's consent step).
--   * public.accept_relationship_invite_v2(uuid, text): both
--     `IF private.spec1_flag_on('flow_signin_v2') THEN` wrappers removed,
--     so the checks always run, and consent added on both sides:
--       acceptor  no DOB -> invite:age_required; under 18 ->
--                 invite:not_possible; EULA < 2 -> invite:consent_required
--                 (NEW code; accept-invite maps it to 409
--                 signup:incomplete, like the eligibility answer)
--       inviter   no DOB, under 18 or EULA < 2 -> invite:not_possible
--                 (uniform, as before: the acceptor is never told why)
--     Everything else (lock order, refusal order before the age checks,
--     holds, deletes, path, About us, metrics, the answer) is unchanged.
-- Grants are kept by CREATE OR REPLACE; 20261127100030 re-asserts them.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.relationship_invite_eligibility(p_user uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_age integer;
  v_eula text;
BEGIN
  IF p_user IS NULL THEN
    RAISE EXCEPTION 'invite:invalid';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = p_user) THEN
    RETURN 'signup_incomplete';
  END IF;
  SELECT u.eula_version INTO v_eula
    FROM public.users AS u
   WHERE u.id = p_user AND u.eula_accepted_at IS NOT NULL;
  v_age := public.account_age(p_user);
  IF v_age IS NULL THEN
    RETURN 'age_required';
  END IF;
  IF v_age < 18 THEN
    RETURN 'not_possible';
  END IF;
  IF coalesce(substring(v_eula FROM '^[0-9]{1,3}$')::integer, 0) < 2 THEN
    RETURN 'consent_required';
  END IF;
  RETURN 'ok';
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_relationship_invite_v2(p_acceptor uuid, p_invite_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_code constant text := upper(regexp_replace(coalesce(p_invite_code, ''), '\s', '', 'g'));
  v_hash text;
  v_done public.relationship_invite_acceptances%ROWTYPE;
  v_rel public.relationships%ROWTYPE;
  v_inviter uuid;
  v_age integer;
  v_waited interval;
BEGIN
  IF p_acceptor IS NULL OR v_code !~ '^[A-Z0-9]{6,12}$' THEN
    RAISE EXCEPTION 'invite:invalid';
  END IF;
  v_hash := encode(extensions.digest(v_code, 'sha256'), 'hex');

  -- Who sent it, read without a lock, so both users rows can be locked
  -- before any relationships row.
  SELECT r.user_a INTO v_inviter FROM public.relationships AS r
   WHERE r.invite_code = v_code AND r.status = 'pending';

  -- Lock order (W1 carry, W4 F-3): the acceptor's and the inviter's users
  -- rows, lowest id first, before any relationships row, as set_my_path
  -- and the withdraw do. No acceptor row: nothing is created (D8).
  PERFORM 1 FROM public.users AS u
   WHERE u.id IN (p_acceptor, v_inviter) ORDER BY u.id FOR UPDATE;
  IF NOT EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = p_acceptor) THEN
    RAISE EXCEPTION 'invite:phone_required';
  END IF;

  -- The pending row, locked: a second accept of the same code waits here
  -- for the first to commit, then finds no pending row.
  SELECT * INTO v_rel FROM public.relationships AS r
   WHERE r.invite_code = v_code AND r.status = 'pending'
   FOR UPDATE;
  -- Read only after that wait, so an acceptance committed meanwhile is
  -- seen: someone else's is invite:already_accepted, one's own a replay.
  SELECT * INTO v_done FROM public.relationship_invite_acceptances AS a
   WHERE a.invite_code_hash = v_hash;
  IF FOUND THEN
    IF v_done.accepted_by IS DISTINCT FROM p_acceptor THEN
      RAISE EXCEPTION 'invite:already_accepted';
    END IF;
    RETURN jsonb_build_object(
      'relationship_id', v_done.relationship_id,
      'status', (SELECT r.status FROM public.relationships AS r WHERE r.id = v_done.relationship_id),
      'idempotent', true,
      'inviter_id', (SELECT r.user_a FROM public.relationships AS r WHERE r.id = v_done.relationship_id));
  END IF;
  IF v_rel.id IS NULL THEN
    RAISE EXCEPTION 'invite:invalid';
  END IF;
  IF v_rel.user_a IS DISTINCT FROM v_inviter THEN
    -- The code changed hands between the read and the lock (a new invite
    -- reusing it): lock that inviter's row too.
    PERFORM 1 FROM public.users AS u WHERE u.id = v_rel.user_a FOR UPDATE;
  END IF;
  IF v_rel.user_a = p_acceptor THEN
    RAISE EXCEPTION 'invite:own';
  END IF;
  IF v_rel.user_b IS NOT NULL THEN
    RAISE EXCEPTION 'invite:invalid';
  END IF;
  IF v_rel.invite_expires_at < now() THEN
    RAISE EXCEPTION 'invite:expired';
  END IF;
  IF EXISTS (SELECT 1 FROM public.relationships AS r
              WHERE p_acceptor IN (r.user_a, r.user_b) AND r.status IN ('active', 'paused')) THEN
    RAISE EXCEPTION 'invite:already_in_relationship';
  END IF;
  IF public.verified_phone(p_acceptor) IS NULL THEN
    RAISE EXCEPTION 'invite:phone_required';
  END IF;
  IF EXISTS (SELECT 1 FROM public.account_holds AS h
              WHERE h.user_id = p_acceptor AND h.resolved_at IS NULL) THEN
    RAISE EXCEPTION 'account:hold';
  END IF;
  -- Entry gates 2026-11-27: always, whatever the sign-in flag says.
  v_age := public.account_age(p_acceptor);
  IF v_age IS NULL THEN
    RAISE EXCEPTION 'invite:age_required';
  END IF;
  IF v_age < 18 THEN
    RAISE EXCEPTION 'invite:not_possible';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users AS u
                  WHERE u.id = p_acceptor AND u.eula_accepted_at IS NOT NULL
                    AND coalesce(substring(u.eula_version FROM '^[0-9]{1,3}$')::integer, 0) >= 2) THEN
    RAISE EXCEPTION 'invite:consent_required';
  END IF;
  -- The inviter's side (rulings I-1, I-3), uniform.
  IF private.invite_inviter_unavailable(v_rel.user_a, v_rel.id) THEN
    RAISE EXCEPTION 'invite:invalid';
  END IF;
  v_age := public.account_age(v_rel.user_a);
  IF v_age IS NULL OR v_age < 18
     OR NOT EXISTS (SELECT 1 FROM public.users AS u
                     WHERE u.id = v_rel.user_a AND u.eula_accepted_at IS NOT NULL
                       AND coalesce(substring(u.eula_version FROM '^[0-9]{1,3}$')::integer, 0) >= 2) THEN
    RAISE EXCEPTION 'invite:not_possible';
  END IF;

  -- The acceptor's own invites go first, in this transaction (spec §7.1).
  DELETE FROM public.relationships AS r
   WHERE r.user_a = p_acceptor AND r.status = 'pending' AND r.user_b IS NULL;
  -- And the inviter's other codes (ruling I-1): none can link them again.
  DELETE FROM public.relationships AS r
   WHERE r.user_a = v_rel.user_a AND r.id <> v_rel.id
     AND r.status = 'pending' AND r.user_b IS NULL;

  BEGIN
    UPDATE public.relationships
       SET user_b = p_acceptor,
           status = 'active',
           invite_code = NULL,
           invite_accepted_at = now()
     WHERE id = v_rel.id;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'relationship:already_open' THEN
      RAISE EXCEPTION 'invite:already_in_relationship';
    END IF;
    RAISE;
  END;

  INSERT INTO public.relationship_invite_acceptances
    (invite_code_hash, relationship_id, accepted_by, accepted_at)
  VALUES (v_hash, v_rel.id, p_acceptor, now());

  PERFORM public.set_user_path_internal(p_acceptor, 'relationship');

  -- Spec 1 W5 (§3.8 R4, §4.3 W5): the inviter's About us draft, then the
  -- acceptor's, become the couple's shared profile.
  PERFORM public.adopt_couple_profile_drafts(v_rel.id, v_rel.user_a, p_acceptor);

  -- Server events (internal; spec §4.3 W1b seeds): every accept, and those
  -- within a day and within a week of the invite.
  v_waited := now() - v_rel.created_at;
  PERFORM private.bump_metric_internal('invite_accepted');
  IF v_waited <= interval '24 hours' THEN
    PERFORM private.bump_metric_internal('invite_accepted_24h');
  END IF;
  IF v_waited <= interval '7 days' THEN
    PERFORM private.bump_metric_internal('invite_accepted_7d');
  END IF;

  RETURN jsonb_build_object(
    'relationship_id', v_rel.id,
    'status', 'active',
    'idempotent', false,
    'inviter_id', v_rel.user_a);
END;
$$;

COMMIT;
