-- supabase/tests/invite_v2_contracts.sql
-- Spec 1 W4a (§4.3 W4a, §4.6, §7.1, D7, D8): the one-transaction accept,
-- the inviter and acceptor age checks, the preview and its rate limit, the
-- attempts' retention. One BEGIN ... ROLLBACK.
-- Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/invite_v2_contracts.sql
-- Fixture ids 4e4a0000-0000-0000-0000-0000000000NN (relationships
-- 4e4a0000-0000-0000-0000-0000000001NN); phones +15558200NN, set on
-- auth.users and public.users. Every refusal is checked by its message.
BEGIN;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ('4e4a0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

CREATE FUNCTION pg_temp.rel(p_n text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ('4e4a0000-0000-0000-0000-0000000001' || p_n)::uuid;
$$;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', coalesce(p::text, ''), true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

CREATE FUNCTION pg_temp.error_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN NULL;
EXCEPTION WHEN raise_exception OR insufficient_privilege THEN
  RETURN SQLERRM;
END $$;

-- An account: a verified Auth phone, a users row named [p_name] (NULL: no
-- users row) and, when [p_age] is set, a date of birth that many years ago.
CREATE FUNCTION pg_temp.person(p_n text, p_name text, p_age int) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at)
  VALUES (pg_temp.id(p_n), '+155582000' || p_n, now());
  IF p_name IS NOT NULL THEN
    INSERT INTO public.users (id, phone, display_name)
    VALUES (pg_temp.id(p_n), '+155582000' || p_n, p_name);
  END IF;
  IF p_age IS NOT NULL THEN
    INSERT INTO public.account_birthdates (user_id, birth_date)
    VALUES (pg_temp.id(p_n), ((now() AT TIME ZONE 'utc')::date - make_interval(years => p_age))::date - 1);
  END IF;
END $$;

-- A pending invite from [p_inviter] with [p_code], made [p_ago] ago.
CREATE FUNCTION pg_temp.invite(p_rel text, p_inviter text, p_code text, p_ago interval) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at, created_at)
  VALUES (pg_temp.rel(p_rel), pg_temp.id(p_inviter), 'pending', p_code,
          now() - p_ago + interval '7 days', now() - p_ago);
END $$;

CREATE FUNCTION pg_temp.accept_error(p_n text, p_code text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  RETURN pg_temp.error_of(format(
    'SELECT public.accept_relationship_invite_v2(%L, %L)', pg_temp.id(p_n), p_code));
END $$;

CREATE FUNCTION pg_temp.metric(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce((SELECT c.count FROM public.metric_counters AS c
                    WHERE c.day = (now() AT TIME ZONE 'utc')::date AND c.key = p_key), 0);
$$;

CREATE FUNCTION pg_temp.flag(p_key text, p_on boolean) RETURNS void LANGUAGE sql AS $$
  UPDATE public.feature_flags SET enabled = p_on WHERE key = p_key;
$$;

-- =====================================================================
-- A. Objects, grants, the cron, the lock order.
-- =====================================================================
DO $$
DECLARE
  v_src text;
  v_lock int;
  v_pending int;
BEGIN
  IF to_regprocedure('public.accept_relationship_invite_v2(uuid,text)') IS NULL
     OR to_regprocedure('public.preview_relationship_invite(text)') IS NULL
     OR to_regprocedure('public.relationship_invite_eligibility(uuid)') IS NULL
     OR to_regprocedure('private.purge_invite_preview_attempts()') IS NULL
     OR to_regclass('private.invite_preview_attempts') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W4a objects are missing (accept_relationship_invite_v2, preview_relationship_invite, relationship_invite_eligibility, invite_preview_attempts)';
  END IF;
  -- Fix round 1 (review #3, ruling I-3): the accept's attempts share the
  -- preview's budget through note_invite_attempt (accept-invite calls it
  -- first); private.take_invite_attempt is the one counter both use.
  IF to_regprocedure('public.note_invite_attempt(uuid)') IS NULL
     OR to_regprocedure('private.take_invite_attempt(uuid)') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the shared invite attempt budget is missing (note_invite_attempt, take_invite_attempt)';
  END IF;
  IF has_function_privilege('authenticated', 'public.note_invite_attempt(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.note_invite_attempt(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.note_invite_attempt(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.take_invite_attempt(uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'private.take_invite_attempt(uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'private.invite_first_name(uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'private.purge_invite_preview_attempts()', 'EXECUTE')
     OR has_table_privilege('service_role', 'private.invite_preview_attempts', 'INSERT')
     OR has_table_privilege('service_role', 'private.invite_preview_attempts', 'DELETE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the attempt budget grants are wrong';
  END IF;
  IF has_function_privilege('authenticated', 'public.accept_relationship_invite_v2(uuid,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.accept_relationship_invite_v2(uuid,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.accept_relationship_invite_v2(uuid,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.relationship_invite_eligibility(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.relationship_invite_eligibility(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.relationship_invite_eligibility(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.preview_relationship_invite(text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.preview_relationship_invite(text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.purge_invite_preview_attempts()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.invite_first_name(uuid)', 'EXECUTE')
     OR has_table_privilege('authenticated', 'private.invite_preview_attempts', 'SELECT')
     OR has_table_privilege('authenticated', 'private.invite_preview_attempts', 'INSERT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W4a grants are wrong';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job
                  WHERE jobname = 'invite-preview-retention' AND schedule = '39 * * * *') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: invite-preview-retention is not scheduled at 39 * * * *';
  END IF;
  -- W1 carry: the users rows (the acceptor's and the inviter's, lowest id
  -- first) are locked before any relationships row, the order set_my_path
  -- and the withdraw use; nothing is row-locked before them.
  v_src := (SELECT p.prosrc FROM pg_proc AS p
             WHERE p.oid = 'public.accept_relationship_invite_v2(uuid,text)'::regprocedure);
  v_lock := position('WHERE u.id IN (p_acceptor, v_inviter) ORDER BY u.id FOR UPDATE' IN v_src);
  v_pending := position('SELECT * INTO v_rel FROM public.relationships AS r' IN v_src);
  IF v_lock = 0 OR v_pending = 0 OR v_lock > v_pending
     OR position('FOR UPDATE' IN substr(v_src, 1, v_lock - 1)) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the accept does not lock the users row before relationships';
  END IF;
  -- Review Focus 1 (fix round 1, review #4): the pending row is locked,
  -- so a second accept of the same code waits ...
  IF position('FOR UPDATE' IN split_part(substr(v_src, v_pending), ';', 1)) = 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the accept does not lock the pending invite row';
  END IF;
  -- ... and the acceptance is read only after that wait, so the loser of
  -- the race reads the winner's committed acceptance: invite:already_accepted.
  IF position('FROM public.relationship_invite_acceptances' IN substr(v_src, 1, v_pending)) > 0
     OR position('FROM public.relationship_invite_acceptances AS a' IN substr(v_src, v_pending)) = 0
     OR position('invite:already_accepted' IN substr(v_src, v_pending)) = 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the accept does not re-read the acceptance after waiting for the pending row';
  END IF;
  -- Minor 5: the budget's count and insert are serialised per person.
  v_src := (SELECT p.prosrc FROM pg_proc AS p
             WHERE p.oid = 'private.take_invite_attempt(uuid)'::regprocedure);
  IF position('pg_advisory_xact_lock' IN v_src) = 0
     OR position('pg_advisory_xact_lock' IN v_src) > position('count(*)' IN v_src) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the attempt count is not taken under a per-person advisory lock';
  END IF;
  -- W4 F-3: R3's "Cancel this invite" (the boolean overload) takes the
  -- same order, the caller's users row before the zero-argument withdraw
  -- locks any relationships row, so a cancel on one device and an accept
  -- on another wait for each other instead of deadlocking.
  v_src := (SELECT p.prosrc FROM pg_proc AS p
             WHERE p.oid = 'public.withdraw_my_pending_invites(boolean)'::regprocedure);
  IF position('WHERE u.id = v_uid FOR UPDATE' IN v_src) = 0
     OR position('v_n := public.withdraw_my_pending_invites();' IN v_src) = 0
     OR position('WHERE u.id = v_uid FOR UPDATE' IN v_src)
        > position('v_n := public.withdraw_my_pending_invites();' IN v_src) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: withdraw_my_pending_invites(boolean) does not lock the users row before relationships';
  END IF;
  -- The overload keeps its W3 shape: SECURITY DEFINER, search_path '',
  -- the app's grant and nothing for anon; the zero-argument one is W1's.
  IF NOT EXISTS (SELECT 1 FROM pg_proc AS p
                  WHERE p.oid = 'public.withdraw_my_pending_invites(boolean)'::regprocedure
                    AND p.prosecdef AND p.proconfig = ARRAY['search_path=""'])
     OR NOT has_function_privilege('authenticated', 'public.withdraw_my_pending_invites(boolean)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.withdraw_my_pending_invites(boolean)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: withdraw_my_pending_invites lost its W1/W3 shape';
  END IF;
  -- Fix round 2 (re-review N-2): the zero-argument withdraw ("Use Attune on
  -- my own", Day 7) also locks the caller's users row before its DELETE,
  -- so it queues behind an accept that removes an inviter's other codes.
  -- Same signature, SECURITY DEFINER, search_path '', the app's grant.
  v_src := (SELECT p.prosrc FROM pg_proc AS p
             WHERE p.oid = 'public.withdraw_my_pending_invites()'::regprocedure);
  IF NOT EXISTS (SELECT 1 FROM pg_proc AS p
                  WHERE p.oid = 'public.withdraw_my_pending_invites()'::regprocedure
                    AND p.prosecdef AND p.proconfig = ARRAY['search_path=""']
                    AND p.prorettype = 'integer'::regtype)
     OR NOT has_function_privilege('authenticated', 'public.withdraw_my_pending_invites()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.withdraw_my_pending_invites()', 'EXECUTE')
     OR position('WHERE u.id = auth.uid() FOR UPDATE' IN v_src) = 0
     OR position('DELETE FROM public.relationships' IN v_src) = 0
     OR position('WHERE u.id = auth.uid() FOR UPDATE' IN v_src)
        > position('DELETE FROM public.relationships' IN v_src) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: withdraw_my_pending_invites() does not lock the users row before relationships';
  END IF;
  -- Fix round 2 (re-review N-1): no client inserts relationships rows. A
  -- direct insert was an oracle for live codes (23505 on the unique code)
  -- outside the attempt budget; create-relationship-invite uses the
  -- service role.
  IF has_table_privilege('authenticated', 'public.relationships', 'INSERT')
     OR has_table_privilege('anon', 'public.relationships', 'INSERT')
     OR EXISTS (SELECT 1 FROM pg_policy AS pol
                 WHERE pol.polrelid = 'public.relationships'::regclass AND pol.polcmd IN ('a', '*'))
     OR NOT has_table_privilege('service_role', 'public.relationships', 'INSERT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clients can still insert relationships rows (or the service role cannot)';
  END IF;
END $$;

-- =====================================================================
-- B. Refusals, flow_signin_v2 off and on. Fixtures 01-19.
-- =====================================================================
DO $$
DECLARE
  v_msg text;
BEGIN
  PERFORM pg_temp.flag('flow_signin_v2', false);
  PERFORM pg_temp.person('01', 'Yaw Mensah', 30);     -- inviter
  PERFORM pg_temp.person('02', 'Ama Owusu', 29);      -- acceptor
  PERFORM pg_temp.person('03', NULL, NULL);           -- no users row
  PERFORM pg_temp.person('04', 'Kofi Boateng', 31);   -- in an active relationship
  PERFORM pg_temp.person('05', 'Esi Ofori', 28);      -- Kofi's partner
  PERFORM pg_temp.person('06', 'Abena Paused', 27);   -- in a paused relationship
  PERFORM pg_temp.person('07', 'Kwame Paused', 27);
  PERFORM pg_temp.person('08', 'Adjoa NoPhone', 25);  -- phone not verified
  UPDATE auth.users SET phone_confirmed_at = NULL WHERE id = pg_temp.id('08');
  PERFORM pg_temp.invite('01', '01', 'K7P2QM', interval '1 hour');
  PERFORM pg_temp.invite('02', '01', 'OLD7XY', interval '8 days');
  INSERT INTO public.relationships (id, user_a, user_b, status, started_at, invite_accepted_at)
  VALUES (pg_temp.rel('03'), pg_temp.id('04'), pg_temp.id('05'), 'active', current_date, now()),
         (pg_temp.rel('04'), pg_temp.id('06'), pg_temp.id('07'), 'paused', current_date, now());

  -- N-1: a signed-in user's direct insert, one row of it someone's live
  -- code, is refused for privilege (42501), never answered with the
  -- unique-code collision (23505) that told live codes apart.
  PERFORM pg_temp.as_user(pg_temp.id('02'));
  BEGIN
    INSERT INTO public.relationships (user_a, status, invite_code, invite_expires_at)
    VALUES (pg_temp.id('02'), 'pending', 'GUESS2', now() + interval '7 days'),
           (pg_temp.id('02'), 'pending', 'K7P2QM', now() + interval '7 days');
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: a signed-in user inserted relationships rows';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
    WHEN unique_violation THEN
      RESET ROLE;
      RAISE EXCEPTION 'CONTRACT VIOLATED: a direct insert told a live code apart (23505)';
  END;
  IF (SELECT count(*) FROM public.relationships WHERE user_a = pg_temp.id('02')) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused direct insert left a row';
  END IF;

  v_msg := pg_temp.accept_error('02', 'NOSUCH');
  IF v_msg IS DISTINCT FROM 'invite:invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown code (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.accept_error('02', 'K7');
  IF v_msg IS DISTINCT FROM 'invite:invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a malformed code (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.accept_error('01', 'K7P2QM');
  IF v_msg IS DISTINCT FROM 'invite:own' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: own invite (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.accept_error('02', 'OLD7XY');
  IF v_msg IS DISTINCT FROM 'invite:expired' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an expired invite (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.accept_error('04', 'K7P2QM');
  IF v_msg IS DISTINCT FROM 'invite:already_in_relationship' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an active member accepted (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.accept_error('06', 'K7P2QM');
  IF v_msg IS DISTINCT FROM 'invite:already_in_relationship' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused member accepted (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.accept_error('08', 'K7P2QM');
  IF v_msg IS DISTINCT FROM 'invite:phone_required' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unverified phone accepted (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- D8: no users row is never a new users row.
  v_msg := pg_temp.accept_error('03', 'K7P2QM');
  IF v_msg IS DISTINCT FROM 'invite:phone_required' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an account with no users row (got %)', coalesce(v_msg, 'no error');
  END IF;
  IF EXISTS (SELECT 1 FROM public.users WHERE id = pg_temp.id('03')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the accept created a users row (D8)';
  END IF;
  IF (SELECT status FROM public.relationships WHERE id = pg_temp.rel('01')) <> 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused accept changed the invite';
  END IF;
END $$;

-- Ages, with flow_signin_v2 on (fixtures 11-16).
DO $$
DECLARE
  v_msg text;
BEGIN
  PERFORM pg_temp.flag('flow_signin_v2', true);
  PERFORM pg_temp.person('11', 'Akua NoDob', NULL);    -- acceptor, no DOB
  PERFORM pg_temp.person('12', 'Yaa Minor', 17);       -- acceptor, 17
  PERFORM pg_temp.person('13', 'Kojo NoDob', NULL);    -- inviter, no DOB
  PERFORM pg_temp.person('14', 'Efua Minor', 17);      -- inviter, 17
  PERFORM pg_temp.person('15', 'Nana Adult', 40);      -- acceptor, adult
  PERFORM pg_temp.invite('13', '13', 'NODOB2', interval '1 hour');
  PERFORM pg_temp.invite('14', '14', 'MINOR2', interval '1 hour');

  v_msg := pg_temp.accept_error('11', 'K7P2QM');
  IF v_msg IS DISTINCT FROM 'invite:age_required' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an acceptor without a DOB (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.accept_error('12', 'K7P2QM');
  IF v_msg IS DISTINCT FROM 'invite:not_possible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 17-year-old acceptor (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.accept_error('15', 'NODOB2');
  IF v_msg IS DISTINCT FROM 'invite:not_possible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an inviter without a DOB (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.accept_error('15', 'MINOR2');
  IF v_msg IS DISTINCT FROM 'invite:not_possible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 17-year-old inviter (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- The eligibility both edge functions check first.
  IF public.relationship_invite_eligibility(pg_temp.id('15')) <> 'ok'
     OR public.relationship_invite_eligibility(pg_temp.id('13')) <> 'age_required'
     OR public.relationship_invite_eligibility(pg_temp.id('14')) <> 'not_possible'
     OR public.relationship_invite_eligibility(pg_temp.id('03')) <> 'signup_incomplete' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: relationship_invite_eligibility with the flag on';
  END IF;
  PERFORM pg_temp.flag('flow_signin_v2', false);
  IF public.relationship_invite_eligibility(pg_temp.id('03')) <> 'legacy'
     OR public.relationship_invite_eligibility(pg_temp.id('14')) <> 'legacy' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: relationship_invite_eligibility with the flag off is not legacy';
  END IF;
  -- With the flag off, no age check: a person without a DOB still links.
  v_msg := pg_temp.accept_error('11', 'NODOB2');
  IF v_msg IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the flag-off accept checked ages (%)', v_msg;
  END IF;
END $$;

-- =====================================================================
-- C. The accept: the acceptor's own invites go in the same transaction,
--    the path is set, the acceptance is kept, a replay is idempotent,
--    someone else's replay is refused, the code is case- and
--    space-insensitive, metrics move. Fixtures 21-23.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_again jsonb;
  v_msg text;
  v_before bigint := pg_temp.metric('invite_accepted');
  v_before_24h bigint := pg_temp.metric('invite_accepted_24h');
  v_before_7d bigint := pg_temp.metric('invite_accepted_7d');
BEGIN
  PERFORM pg_temp.flag('flow_signin_v2', true);
  PERFORM pg_temp.person('21', 'Yaw Inviter', 33);
  PERFORM pg_temp.person('22', 'Ama Acceptor', 32);
  PERFORM pg_temp.person('23', 'Kofi Late', 35);
  UPDATE public.users SET path = 'just_me' WHERE id = pg_temp.id('22');
  PERFORM pg_temp.invite('21', '21', 'HAPPY2', interval '2 hours');
  -- The acceptor's own invites, live and expired: both must go.
  PERFORM pg_temp.invite('22', '22', 'MINE22', interval '1 hour');
  PERFORM pg_temp.invite('23', '22', 'MINE33', interval '9 days');

  v := public.accept_relationship_invite_v2(pg_temp.id('22'), ' happy2 ');
  IF v->>'relationship_id' <> pg_temp.rel('21')::text OR v->>'status' <> 'active'
     OR (v->>'idempotent')::boolean OR v->>'inviter_id' <> pg_temp.id('21')::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the accept answered %', v;
  END IF;
  IF EXISTS (SELECT 1 FROM public.relationships
              WHERE user_a = pg_temp.id('22') AND status = 'pending') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the acceptor''s own pending invites survived the accept';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.relationships
                  WHERE id = pg_temp.rel('21') AND status = 'active' AND user_b = pg_temp.id('22')
                    AND invite_code IS NULL AND invite_accepted_at IS NOT NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the relationship is not active with the acceptor';
  END IF;
  IF (SELECT path FROM public.users WHERE id = pg_temp.id('22')) IS DISTINCT FROM 'relationship'
     OR (SELECT path_previous FROM public.users WHERE id = pg_temp.id('22')) IS DISTINCT FROM 'just_me' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the acceptor''s path is not Relationship (previous just_me)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.relationship_invite_acceptances
                  WHERE relationship_id = pg_temp.rel('21') AND accepted_by = pg_temp.id('22')
                    AND invite_code_hash = encode(extensions.digest('HAPPY2', 'sha256'), 'hex')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no acceptance row with the code''s SHA-256';
  END IF;
  IF pg_temp.metric('invite_accepted') <> v_before + 1
     OR pg_temp.metric('invite_accepted_24h') <> v_before_24h + 1
     OR pg_temp.metric('invite_accepted_7d') <> v_before_7d + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the accept metrics did not move once each';
  END IF;

  v_again := public.accept_relationship_invite_v2(pg_temp.id('22'), 'HAPPY2');
  IF NOT (v_again->>'idempotent')::boolean OR v_again->>'relationship_id' <> pg_temp.rel('21')::text
     OR v_again->>'status' <> 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replay was not idempotent: %', v_again;
  END IF;
  IF pg_temp.metric('invite_accepted') <> v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replay counted a second accept';
  END IF;
  v_msg := pg_temp.accept_error('23', 'HAPPY2');
  IF v_msg IS DISTINCT FROM 'invite:already_accepted' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: someone else reused an accepted code (got %)', coalesce(v_msg, 'no error');
  END IF;
END $$;

-- =====================================================================
-- D. A failure after the update rolls everything back. Fixtures 31-32.
-- =====================================================================
CREATE FUNCTION pg_temp.fail_acceptance() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'forced failure';
END $$;

DO $$
DECLARE
  v_msg text;
BEGIN
  PERFORM pg_temp.person('31', 'Yaw Rollback', 30);
  PERFORM pg_temp.person('32', 'Ama Rollback', 30);
  UPDATE public.users SET path = 'just_me' WHERE id = pg_temp.id('32');
  PERFORM pg_temp.invite('31', '31', 'ROLL22', interval '1 hour');
  PERFORM pg_temp.invite('32', '32', 'KEEP22', interval '1 hour');
  CREATE TRIGGER w4_fail_acceptance BEFORE INSERT ON public.relationship_invite_acceptances
    FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_acceptance();
  BEGIN
    PERFORM public.accept_relationship_invite_v2(pg_temp.id('32'), 'ROLL22');
    v_msg := NULL;
  EXCEPTION WHEN raise_exception THEN
    v_msg := SQLERRM;
  END;
  DROP TRIGGER w4_fail_acceptance ON public.relationship_invite_acceptances;
  IF v_msg IS DISTINCT FROM 'forced failure' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the forced failure did not surface (got %)', coalesce(v_msg, 'no error');
  END IF;
  IF (SELECT status FROM public.relationships WHERE id = pg_temp.rel('31')) <> 'pending'
     OR (SELECT user_b FROM public.relationships WHERE id = pg_temp.rel('31')) IS NOT NULL
     OR NOT EXISTS (SELECT 1 FROM public.relationships WHERE id = pg_temp.rel('32') AND status = 'pending')
     OR (SELECT path FROM public.users WHERE id = pg_temp.id('32')) IS DISTINCT FROM 'just_me' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed accept left part of its work behind';
  END IF;
END $$;

-- =====================================================================
-- E. An inviter already linked to someone else (a legacy state) is the
--    uniform invite:invalid (ruling I-1: the inviter's status is never
--    told). The database guard stays the race backstop, its refusal the
--    acceptor's message: simulated by a trigger that raises it, as the
--    guard would for a link committed while this accept waited.
--    Fixtures 41-45.
-- =====================================================================
CREATE FUNCTION pg_temp.fake_open_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'relationship:already_open';
END $$;

DO $$
DECLARE
  v_msg text;
BEGIN
  PERFORM pg_temp.person('41', 'Yaw Linked', 30);
  PERFORM pg_temp.person('42', 'Esi Partner', 30);
  PERFORM pg_temp.person('43', 'Ama Late', 30);
  PERFORM pg_temp.invite('41', '41', 'STALE2', interval '1 hour');
  INSERT INTO public.relationships (id, user_a, user_b, status, started_at, invite_accepted_at)
  VALUES (pg_temp.rel('42'), pg_temp.id('41'), pg_temp.id('42'), 'active', current_date, now());
  v_msg := pg_temp.accept_error('43', 'STALE2');
  IF v_msg IS DISTINCT FROM 'invite:invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an active inviter''s second code is not invite:invalid (got %)', coalesce(v_msg, 'no error');
  END IF;
  IF (SELECT status FROM public.relationships WHERE id = pg_temp.rel('41')) <> 'pending'
     OR (SELECT status FROM public.relationships WHERE id = pg_temp.rel('42')) <> 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused accept of an active inviter''s code changed a relationship';
  END IF;

  PERFORM pg_temp.person('44', 'Kojo Raced', 30);
  PERFORM pg_temp.person('45', 'Abena Raced', 30);
  PERFORM pg_temp.invite('45', '44', 'RACE22', interval '1 hour');
  CREATE TRIGGER w4_fake_open_guard BEFORE UPDATE ON public.relationships
    FOR EACH ROW EXECUTE FUNCTION pg_temp.fake_open_guard();
  v_msg := pg_temp.accept_error('45', 'RACE22');
  DROP TRIGGER w4_fake_open_guard ON public.relationships;
  IF v_msg IS DISTINCT FROM 'invite:already_in_relationship' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: relationship:already_open is not mapped (got %)', coalesce(v_msg, 'no error');
  END IF;
END $$;

-- =====================================================================
-- F. The preview (RI-3): states, the name only for ok and expired, never
--    a phone as a name, the rate limit. Fixtures 51-56.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_msg text;
BEGIN
  PERFORM pg_temp.person('51', 'Yaw Preview', 30);
  PERFORM pg_temp.person('52', 'Ama Viewer', 30);
  PERFORM pg_temp.person('53', '+233 24 000 0000', 30);
  PERFORM pg_temp.person('54', 'Kofi Limited', 30);
  PERFORM pg_temp.person('55', 'Esi Daily', 30);
  PERFORM pg_temp.invite('51', '51', 'PEEK22', interval '1 hour');
  PERFORM pg_temp.invite('52', '51', 'PEEK33', interval '8 days');
  PERFORM pg_temp.invite('53', '53', 'PHONE2', interval '1 hour');

  PERFORM pg_temp.as_user(pg_temp.id('52'));
  v := public.preview_relationship_invite('peek22');
  IF v <> '{"state": "ok", "inviter_first_name": "Yaw"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: preview ok read %', v;
  END IF;
  v := public.preview_relationship_invite('PEEK33');
  IF v <> '{"state": "expired", "inviter_first_name": "Yaw"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: preview expired read %', v;
  END IF;
  v := public.preview_relationship_invite('NOSUCH');
  IF v <> '{"state": "invalid", "inviter_first_name": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: preview invalid read %', v;
  END IF;
  v := public.preview_relationship_invite('PHONE2');
  IF v <> '{"state": "ok", "inviter_first_name": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a phone number was given as a name: %', v;
  END IF;
  v := public.preview_relationship_invite('HAPPY2');
  IF v <> '{"state": "invalid", "inviter_first_name": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: someone else''s accepted code read %', v;
  END IF;
  RESET ROLE;

  PERFORM pg_temp.as_user(pg_temp.id('51'));
  v := public.preview_relationship_invite('PEEK22');
  RESET ROLE;
  IF v <> '{"state": "own", "inviter_first_name": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: preview own read %', v;
  END IF;

  PERFORM pg_temp.as_user(pg_temp.id('22'));
  v := public.preview_relationship_invite('HAPPY2');
  RESET ROLE;
  IF v <> '{"state": "linked", "inviter_first_name": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: preview of my accepted code read %', v;
  END IF;

  -- 10 per hour: the 11th is refused and records nothing.
  PERFORM pg_temp.as_user(pg_temp.id('54'));
  FOR i IN 1..10 LOOP
    PERFORM public.preview_relationship_invite('NOSUCH');
  END LOOP;
  v_msg := pg_temp.error_of('SELECT public.preview_relationship_invite(''PEEK22'')');
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'invite:try_later' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 11th preview in an hour (got %)', coalesce(v_msg, 'no error');
  END IF;
  IF (SELECT count(*) FROM private.invite_preview_attempts WHERE user_id = pg_temp.id('54')) <> 10 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused preview was recorded';
  END IF;

  -- 30 per day: 29 earlier today, then one more, then refused.
  INSERT INTO private.invite_preview_attempts (user_id, attempted_at)
  SELECT pg_temp.id('55'), now() - interval '3 hours' FROM generate_series(1, 29);
  PERFORM pg_temp.as_user(pg_temp.id('55'));
  PERFORM public.preview_relationship_invite('NOSUCH');
  v_msg := pg_temp.error_of('SELECT public.preview_relationship_invite(''NOSUCH'')');
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'invite:try_later' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 31st preview in a day (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- No verified phone: refused, and nothing is recorded (review #6).
  PERFORM pg_temp.person('57', 'Adjoa Unverified', 30);
  UPDATE auth.users SET phone_confirmed_at = NULL WHERE id = pg_temp.id('57');
  PERFORM pg_temp.as_user(pg_temp.id('57'));
  v_msg := pg_temp.error_of('SELECT public.preview_relationship_invite(''PEEK22'')');
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'invite:phone_required' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a preview without a verified phone (got %)', coalesce(v_msg, 'no error');
  END IF;
  IF EXISTS (SELECT 1 FROM private.invite_preview_attempts WHERE user_id = pg_temp.id('57')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a preview without a verified phone was recorded';
  END IF;

  -- Signed out: nothing.
  PERFORM pg_temp.as_user(NULL);
  v_msg := pg_temp.error_of('SELECT public.preview_relationship_invite(''PEEK22'')');
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'invite:not_signed_in' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a preview without a session (got %)', coalesce(v_msg, 'no error');
  END IF;
END $$;

-- =====================================================================
-- G. Retention: only attempts older than a day go.
-- =====================================================================
DO $$
BEGIN
  PERFORM pg_temp.person('56', 'Kojo Old', 30);
  INSERT INTO private.invite_preview_attempts (user_id, attempted_at)
  VALUES (pg_temp.id('56'), now() - interval '25 hours'),
         (pg_temp.id('56'), now() - interval '23 hours');
END $$;
DO $$
DECLARE
  v_young bigint;
BEGIN
  SELECT count(*) INTO v_young FROM private.invite_preview_attempts
   WHERE attempted_at >= now() - interval '1 day';
  PERFORM private.purge_invite_preview_attempts();
  IF EXISTS (SELECT 1 FROM private.invite_preview_attempts WHERE attempted_at < now() - interval '1 day') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an attempt older than a day survived the purge';
  END IF;
  IF (SELECT count(*) FROM private.invite_preview_attempts) <> v_young THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge deleted attempts younger than a day';
  END IF;
END $$;

-- =====================================================================
-- H. The inviter's side and holds (fix round 1, review #1 and #2,
--    rulings I-1 and I-3), unflagged: flow_signin_v2 off. Fixtures 61-69.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_msg text;
BEGIN
  PERFORM pg_temp.flag('flow_signin_v2', false);
  -- The review's probe: a paused inviter's second live code.
  PERFORM pg_temp.person('61', 'Yaw Paused', 30);
  PERFORM pg_temp.person('62', 'Esi Paused', 30);
  PERFORM pg_temp.person('63', 'Ama Stranger', 30);
  INSERT INTO public.relationships (id, user_a, user_b, status, started_at, invite_accepted_at, paused_at)
  VALUES (pg_temp.rel('61'), pg_temp.id('61'), pg_temp.id('62'), 'paused', current_date, now(), now());
  PERFORM pg_temp.invite('62', '61', 'PAUSE2', interval '1 hour');
  v_msg := pg_temp.accept_error('63', 'PAUSE2');
  IF v_msg IS DISTINCT FROM 'invite:invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused inviter''s second code linked or was not invite:invalid (got %)', coalesce(v_msg, 'no error');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.relationships
                  WHERE id = pg_temp.rel('61') AND status = 'paused' AND chat_archived_at IS NULL)
     OR (SELECT status FROM public.relationships WHERE id = pg_temp.rel('62')) <> 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused accept touched the paused inviter''s relationship';
  END IF;
  PERFORM pg_temp.as_user(pg_temp.id('63'));
  v := public.preview_relationship_invite('PAUSE2');
  RESET ROLE;
  IF v <> '{"state": "invalid", "inviter_first_name": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the preview of a paused inviter''s code read %', v;
  END IF;

  -- An open hold on the inviter: the same uniform invite:invalid.
  PERFORM pg_temp.person('64', 'Kofi Held', 30);
  PERFORM pg_temp.person('65', 'Akua Joiner', 30);
  PERFORM public.place_account_hold(pg_temp.id('64'), 'age_review');
  PERFORM pg_temp.invite('64', '64', 'HOLD22', interval '1 hour');
  v_msg := pg_temp.accept_error('65', 'HOLD22');
  IF v_msg IS DISTINCT FROM 'invite:invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a held inviter''s code (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM pg_temp.as_user(pg_temp.id('65'));
  v := public.preview_relationship_invite('HOLD22');
  RESET ROLE;
  IF v <> '{"state": "invalid", "inviter_first_name": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the preview of a held inviter''s code read %', v;
  END IF;
  -- A resolved hold is no hold.
  UPDATE public.account_holds SET resolved_at = now(), resolved_by = 'contract'
   WHERE user_id = pg_temp.id('64');
  v_msg := pg_temp.accept_error('65', 'HOLD22');
  IF v_msg IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a resolved hold still refused (%)', v_msg;
  END IF;

  -- An open hold on the acceptor: account:hold, their own state.
  PERFORM pg_temp.person('66', 'Efua Held', 30);
  PERFORM pg_temp.person('67', 'Kwame Inviter', 30);
  PERFORM public.place_account_hold(pg_temp.id('66'), 'safety_review');
  PERFORM pg_temp.invite('66', '67', 'HOLD33', interval '1 hour');
  v_msg := pg_temp.accept_error('66', 'HOLD33');
  IF v_msg IS DISTINCT FROM 'account:hold' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a held acceptor (got %)', coalesce(v_msg, 'no error');
  END IF;
  IF (SELECT status FROM public.relationships WHERE id = pg_temp.rel('66')) <> 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a held acceptor''s refusal changed the invite';
  END IF;

  -- On link, both people's other pending invites go.
  PERFORM pg_temp.person('68', 'Yaa Twocodes', 30);
  PERFORM pg_temp.person('69', 'Nana Joiner', 30);
  PERFORM pg_temp.invite('67', '68', 'BOTH22', interval '1 hour');
  PERFORM pg_temp.invite('68', '68', 'BOTH33', interval '2 hours');
  PERFORM pg_temp.invite('69', '69', 'BOTH44', interval '1 hour');
  v := public.accept_relationship_invite_v2(pg_temp.id('69'), 'BOTH22');
  IF v->>'relationship_id' <> pg_temp.rel('67')::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the two-code accept answered %', v;
  END IF;
  IF EXISTS (SELECT 1 FROM public.relationships
              WHERE user_a IN (pg_temp.id('68'), pg_temp.id('69')) AND status = 'pending') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pending invite of the inviter or the acceptor survived the link';
  END IF;
  PERFORM pg_temp.flag('flow_signin_v2', true);
END $$;

-- =====================================================================
-- I. One attempt budget for the preview and the accept (ruling I-3):
--    10 an hour and 30 a day across both. Fixtures 71-73.
-- =====================================================================
DO $$
DECLARE
  v_msg text;
BEGIN
  PERFORM pg_temp.person('71', 'Kojo Previewer', 30);
  PERFORM pg_temp.person('72', 'Esi Guesser', 30);
  PERFORM pg_temp.person('73', 'Ama Daily', 30);
  -- 10 previews spend the accept's hour.
  PERFORM pg_temp.as_user(pg_temp.id('71'));
  FOR i IN 1..10 LOOP
    PERFORM public.preview_relationship_invite('NOSUCH');
  END LOOP;
  RESET ROLE;
  IF public.note_invite_attempt(pg_temp.id('71')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an accept attempt was allowed after 10 previews in an hour';
  END IF;
  -- 10 accept attempts spend the preview's hour.
  FOR i IN 1..10 LOOP
    IF NOT public.note_invite_attempt(pg_temp.id('72')) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: accept attempt % of 10 was refused', i;
    END IF;
  END LOOP;
  IF public.note_invite_attempt(pg_temp.id('72')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 11th accept attempt in an hour was allowed';
  END IF;
  PERFORM pg_temp.as_user(pg_temp.id('72'));
  v_msg := pg_temp.error_of('SELECT public.preview_relationship_invite(''PEEK22'')');
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'invite:try_later' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a preview after 10 accept attempts (got %)', coalesce(v_msg, 'no error');
  END IF;
  IF (SELECT count(*) FROM private.invite_preview_attempts WHERE user_id = pg_temp.id('72')) <> 10 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused attempt was recorded';
  END IF;
  -- 30 a day.
  INSERT INTO private.invite_preview_attempts (user_id, attempted_at)
  SELECT pg_temp.id('73'), now() - interval '3 hours' FROM generate_series(1, 30);
  IF public.note_invite_attempt(pg_temp.id('73')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 31st accept attempt in a day was allowed';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'invite_v2_contracts: all held'; END $$;
ROLLBACK;
