-- Spec 1 W4a, migration 9 (spec §4.7 #9): accept_invite_v2.
--   * accept_relationship_invite_v2 (service role, D7): the whole accept in
--     one transaction. Both people's users rows are locked first (lowest
--     id first), then the pending relationship, the order set_my_path and
--     the withdraw use (users, then relationships), so an accept racing a
--     path switch or an invite cancel on either side waits instead of
--     deadlocking, and so do two people who invited each other and accept
--     each other's code at the same instant (the second is told the code
--     is gone). Both withdraw overloads now lock the caller's users row
--     first too (W4 F-3, re-review N-2). A 40P01 (one side aborted, the
--     other completes; never a hang, never corrupt data, the app retries)
--     remains possible against seal_my_side (it locks an ended chapter,
--     then the caller's users row; re-review N-3, deferred) and the
--     theoretical late re-lock of a code reused within milliseconds; any
--     other path that writes relationships rows without taking the users
--     row first would be another. Both people's other pending invites go
--     in the same transaction; the acceptor's path becomes Relationship.
--     It never creates a users row (D8): no row is invite:phone_required.
--     An inviter who is already in an active or paused relationship, or
--     under an open hold, is the uniform invite:invalid (never told
--     apart); an acceptor under an open hold is account:hold.
--   * relationship_invite_eligibility (service role): what
--     create-relationship-invite and accept-invite do before anything else
--     (legacy row creation with flow_signin_v2 off; otherwise an account,
--     a date of birth, 18 or over). Replaces the W2 interim guard's flag
--     read (W4 plan P-2).
--   * preview_relationship_invite (authenticated, RI-3): the inviter's first
--     name for a code the caller holds, 10 per hour and 30 per day.
--   * note_invite_attempt (service role): accept-invite spends the same
--     budget before every accept (one counter, private.take_invite_attempt,
--     serialised per person by an advisory lock), so guessing codes
--     through the accept is capped as the preview is.
--   * withdraw_my_pending_invites(boolean) (W3, R3 "Cancel this invite")
--     and withdraw_my_pending_invites() (W1, Day 7 "Use Attune on my
--     own") take the same order (W4 F-3, re-review N-2): the caller's
--     users row first, then their relationships rows. Signatures,
--     behaviour, grants and search_path unchanged.
--   * Clients no longer insert relationships rows (re-review N-1): INSERT
--     is revoked from authenticated and anon and the "relationship
--     inviter insert" policy is dropped. A direct insert answered a live
--     code's unique-key collision (23505), an oracle outside the attempt
--     budget. Nothing used it: the app never inserts there and
--     create-relationship-invite uses the service role, which keeps its
--     DML.
--   * private.invite_preview_attempts and its own retention cron
--     invite-preview-retention (spec §4.6), deleting attempts older than a
--     day.
-- Grants in 20261102100010_accept_invite_v2_grants.sql; every server-only
-- object is revoked here as well.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS private.invite_preview_attempts (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  attempted_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS invite_preview_attempts_user_at_idx
  ON private.invite_preview_attempts (user_id, attempted_at);
REVOKE ALL ON private.invite_preview_attempts FROM PUBLIC, anon, authenticated, service_role;

-- A display name's first word, never a phone number (the rule
-- get_my_home_state uses for partner_first_name).
CREATE OR REPLACE FUNCTION private.invite_first_name(p_user uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE
           WHEN split_part(private.normalize_display_name(u.display_name), ' ', 1) ~ '^\+?[0-9 ()-]*$' THEN NULL
           ELSE split_part(private.normalize_display_name(u.display_name), ' ', 1)
         END
    FROM public.users AS u
   WHERE u.id = p_user;
$$;
REVOKE ALL ON FUNCTION private.invite_first_name(uuid) FROM PUBLIC, anon, authenticated, service_role;

-- Whether an inviter's code can no longer start anything (rulings I-1,
-- I-3): they are in another active or paused relationship (a paused
-- person cannot start a new chapter), or under an open hold. The accept
-- and the preview both answer it as invalid, never saying which.
CREATE OR REPLACE FUNCTION private.invite_inviter_unavailable(p_inviter uuid, p_invite uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.relationships AS r
                  WHERE r.id <> p_invite AND p_inviter IN (r.user_a, r.user_b)
                    AND r.status IN ('active', 'paused'))
      OR EXISTS (SELECT 1 FROM public.account_holds AS h
                  WHERE h.user_id = p_inviter AND h.resolved_at IS NULL);
$$;
REVOKE ALL ON FUNCTION private.invite_inviter_unavailable(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;

-- One attempt budget for the preview and the accept (spec §6.4, ruling
-- I-3): 10 an hour and 30 a day. Records the attempt and answers true, or
-- records nothing and answers false. The per-person advisory lock makes
-- the count and the insert one step, so parallel calls can't overshoot;
-- it takes no row lock, so the users-then-relationships order is
-- unaffected.
CREATE OR REPLACE FUNCTION private.take_invite_attempt(p_user uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('invite_attempt:' || p_user::text, 0));
  IF (SELECT count(*) FROM private.invite_preview_attempts AS a
       WHERE a.user_id = p_user AND a.attempted_at > now() - interval '1 hour') >= 10
     OR (SELECT count(*) FROM private.invite_preview_attempts AS a
          WHERE a.user_id = p_user AND a.attempted_at > now() - interval '1 day') >= 30 THEN
    RETURN false;
  END IF;
  INSERT INTO private.invite_preview_attempts (user_id) VALUES (p_user);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION private.take_invite_attempt(uuid) FROM PUBLIC, anon, authenticated, service_role;

-- accept-invite calls this in its own request before the accept (a
-- refused accept rolls back, so the accept can't record its own try);
-- false is invite:try_later (429).
CREATE OR REPLACE FUNCTION public.note_invite_attempt(p_user uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_user IS NULL THEN
    RAISE EXCEPTION 'invite:invalid';
  END IF;
  RETURN private.take_invite_attempt(p_user);
END;
$$;
REVOKE ALL ON FUNCTION public.note_invite_attempt(uuid) FROM PUBLIC, anon, authenticated;

-- What both invite functions check first (spec §4.5 W4a). 'legacy': with
-- flow_signin_v2 effectively off, today's missing-row insert runs.
-- Otherwise no row is ever created here (D8): 'signup_incomplete' with no
-- users row, 'age_required' with no date of birth, 'not_possible' under
-- 18, else 'ok'.
CREATE OR REPLACE FUNCTION public.relationship_invite_eligibility(p_user uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_age integer;
BEGIN
  IF p_user IS NULL THEN
    RAISE EXCEPTION 'invite:invalid';
  END IF;
  IF NOT private.spec1_flag_on('flow_signin_v2') THEN
    RETURN 'legacy';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = p_user) THEN
    RETURN 'signup_incomplete';
  END IF;
  v_age := public.account_age(p_user);
  IF v_age IS NULL THEN
    RETURN 'age_required';
  END IF;
  IF v_age < 18 THEN
    RETURN 'not_possible';
  END IF;
  RETURN 'ok';
END;
$$;

-- The accept (spec §4.3 W4a, D7). Codes are case-insensitive, spaces
-- ignored. Refusals: invite:invalid, invite:own, invite:expired,
-- invite:already_accepted, invite:already_in_relationship,
-- invite:phone_required, and with flow_signin_v2 effectively on
-- invite:age_required (acceptor without a date of birth) and
-- invite:not_possible (either side under 18, or an inviter without one;
-- neutral, never says which). Unflagged: account:hold (the acceptor under
-- an open hold) and invite:invalid for an inviter in another active or
-- paused relationship or under an open hold (rulings I-1, I-3; checked
-- after every acceptor check, so no other answer depends on the
-- inviter's state). A replay by the same acceptor answers idempotent.
-- accept-invite spends note_invite_attempt first.
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
  IF private.spec1_flag_on('flow_signin_v2') THEN
    v_age := public.account_age(p_acceptor);
    IF v_age IS NULL THEN
      RAISE EXCEPTION 'invite:age_required';
    END IF;
    IF v_age < 18 THEN
      RAISE EXCEPTION 'invite:not_possible';
    END IF;
  END IF;
  -- The inviter's side (rulings I-1, I-3), uniform.
  IF private.invite_inviter_unavailable(v_rel.user_a, v_rel.id) THEN
    RAISE EXCEPTION 'invite:invalid';
  END IF;
  IF private.spec1_flag_on('flow_signin_v2') THEN
    v_age := public.account_age(v_rel.user_a);
    IF v_age IS NULL OR v_age < 18 THEN
      RAISE EXCEPTION 'invite:not_possible';
    END IF;
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

-- W1's withdraw (Day 7 "Use Attune on my own"), redefined only to lock the
-- caller's users row before its DELETE (re-review N-2): an inviter with
-- two or more codes pressing it while someone accepts one of them now
-- waits instead of aborting. Everything else is W1's text (20261018130600);
-- set_my_path and the boolean overload already hold the row, so the
-- re-lock is a no-op there. CREATE OR REPLACE keeps its grants
-- (authenticated only, re-stated in the twin).
CREATE OR REPLACE FUNCTION public.withdraw_my_pending_invites()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_n int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'invite:not_signed_in'; END IF;
  -- Lock order (W4 N-2): users, then relationships.
  PERFORM 1 FROM public.users AS u WHERE u.id = auth.uid() FOR UPDATE;
  DELETE FROM public.relationships r
  WHERE r.user_a = auth.uid() AND r.status = 'pending' AND r.user_b IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.withdraw_my_pending_invites() FROM PUBLIC, anon;

-- W3's return-to-previous withdraw (R3 "Cancel this invite"), redefined
-- only to lock the caller's users row before the zero-argument withdraw
-- touches any relationships row (W4 F-3), the order the accept and
-- set_my_path use. Everything else is W3's text; CREATE OR REPLACE keeps
-- its grants (authenticated only, re-stated in the twin).
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
  -- Lock order (W4 F-3): users, then relationships. No row (or no
  -- session): nothing to lock; the withdraw below answers as before.
  PERFORM 1 FROM public.users AS u WHERE u.id = v_uid FOR UPDATE;
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
REVOKE ALL ON FUNCTION public.withdraw_my_pending_invites(boolean) FROM PUBLIC, anon;

-- RI-3 (spec §3.8, §4.3 W4a): who sent the code the caller holds. A name
-- only for ok and expired; 10 tries per hour and 30 per day, invalid codes
-- included (no enumeration, §6.4), the same budget as the accept. An
-- inviter who can no longer link (another active or paused relationship,
-- an open hold) reads as invalid, as the accept answers.
CREATE OR REPLACE FUNCTION public.preview_relationship_invite(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid constant uuid := auth.uid();
  v_code constant text := upper(regexp_replace(coalesce(p_code, ''), '\s', '', 'g'));
  v_done public.relationship_invite_acceptances%ROWTYPE;
  v_rel public.relationships%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'invite:not_signed_in';
  END IF;
  IF public.verified_phone(v_uid) IS NULL THEN
    RAISE EXCEPTION 'invite:phone_required';
  END IF;
  IF NOT private.take_invite_attempt(v_uid) THEN
    RAISE EXCEPTION 'invite:try_later';
  END IF;

  IF v_code !~ '^[A-Z0-9]{6,12}$' THEN
    RETURN jsonb_build_object('state', 'invalid', 'inviter_first_name', NULL);
  END IF;

  SELECT * INTO v_done FROM public.relationship_invite_acceptances AS a
   WHERE a.invite_code_hash = encode(extensions.digest(v_code, 'sha256'), 'hex');
  IF FOUND THEN
    RETURN jsonb_build_object(
      'state', CASE WHEN v_done.accepted_by = v_uid THEN 'linked' ELSE 'invalid' END,
      'inviter_first_name', NULL);
  END IF;

  SELECT * INTO v_rel FROM public.relationships AS r
   WHERE r.invite_code = v_code AND r.status = 'pending' AND r.user_b IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('state', 'invalid', 'inviter_first_name', NULL);
  END IF;
  IF v_rel.user_a = v_uid THEN
    RETURN jsonb_build_object('state', 'own', 'inviter_first_name', NULL);
  END IF;
  IF v_rel.invite_expires_at < now() THEN
    RETURN jsonb_build_object('state', 'expired',
                              'inviter_first_name', private.invite_first_name(v_rel.user_a));
  END IF;
  IF private.invite_inviter_unavailable(v_rel.user_a, v_rel.id) THEN
    RETURN jsonb_build_object('state', 'invalid', 'inviter_first_name', NULL);
  END IF;
  RETURN jsonb_build_object('state', 'ok',
                            'inviter_first_name', private.invite_first_name(v_rel.user_a));
END;
$$;

-- Retention (spec §4.6, §4.8): attempts are kept one day.
CREATE OR REPLACE FUNCTION private.purge_invite_preview_attempts()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_n integer;
BEGIN
  DELETE FROM private.invite_preview_attempts AS a
   WHERE a.attempted_at < now() - interval '1 day';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION private.purge_invite_preview_attempts() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.accept_relationship_invite_v2(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.relationship_invite_eligibility(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.preview_relationship_invite(text) FROM PUBLIC, anon;

-- Re-review N-1: relationships rows are made only by the service role
-- (create-relationship-invite) and the definer functions.
DROP POLICY IF EXISTS "relationship inviter insert" ON public.relationships;
REVOKE INSERT ON public.relationships FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'invite-preview-retention';
END;
$$;
SELECT cron.schedule(
  'invite-preview-retention',
  '39 * * * *',
  $$ SELECT private.purge_invite_preview_attempts(); $$
);

COMMIT;
