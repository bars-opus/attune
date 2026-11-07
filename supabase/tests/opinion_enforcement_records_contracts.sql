-- supabase/tests/opinion_enforcement_records_contracts.sql
-- Spec 1 W9d (§10 O4, owner approval O4; review I-16; Spec 2 §4.2
-- enforcement_records, §6.3; S2 W1 rulings B3 I-1, B3 I-2, B2 key
-- mismatch, PF-F6; Spec 1 O3): an Opinions strike count or live ban
-- survives account deletion under the phone HMAC stamped when it was
-- placed, never the number held at deletion; nothing ever refuses a
-- deletion or a sign-up; a parked account carries nothing; every path that
-- carries nothing is counted. Batch-1 fix round 1 (B2, C2): the carry is
-- the standing now, capped by the stamp; the backfill stamps a pre-W9d
-- strike only on a number provably unchanged since; the daily purge.
-- Final fix wave (D4): the restore runs from Auth's phone confirmation,
-- on every account path.
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/opinion_enforcement_records_contracts.sql
-- Fixture ids 5f9d0000-0000-0000-0000-0000000000NN; phones 155586040NN on
-- auth.users (Auth's form, no '+'), copied to public.users.
BEGIN;

DO $$
BEGIN
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec1-w9d-contract-exclusion-key', true);
  -- The key is "ready": its fingerprint is the stored one (rolled back).
  DELETE FROM private.dating_key_fingerprints WHERE name = 'dating_exclusion_key';
  IF private.seed_dating_exclusion_key_fingerprint() IS DISTINCT FROM 'ready' THEN
    RAISE EXCEPTION 'CONTRACT SETUP: the contract key could not be made ready';
  END IF;
END $$;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('5f9d0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

-- The HMAC of fixture number 155586040<p_n>, as dating_phone_hmac_for_user computes it.
CREATE FUNCTION pg_temp.h(p_n text) RETURNS text LANGUAGE sql AS $$
  SELECT public.dating_phone_hmac('+155586040' || p_n);
$$;

-- An adult account [p_n] with a profile, phone 155586040<p_n>.
CREATE FUNCTION pg_temp.person(p_n text) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (pg_temp.id(p_n), '155586040' || p_n, now() - interval '400 days', now() - interval '400 days');
  INSERT INTO public.users (id, phone, display_name, created_at, updated_at, eula_accepted_at, eula_version)
  VALUES (pg_temp.id(p_n), '155586040' || p_n, 'W9d person ' || p_n, now() - interval '400 days',
          now() - interval '400 days', now(), '2');
  INSERT INTO public.profiles (id) VALUES (pg_temp.id(p_n));
  RETURN pg_temp.id(p_n);
END $$;

-- One confirmed removal of a new post by [p_user], as the service role
-- (how the SQL editor and edge functions reach it): 'count/banned'.
CREATE FUNCTION pg_temp.strike(p_user uuid) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_id uuid;
  v_r record;
BEGIN
  INSERT INTO public.opinions (user_id, content) VALUES (p_user, 'W9d contract: a post') RETURNING id INTO v_id;
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  SELECT * INTO v_r FROM public.admin_confirm_content_removal('opinion', v_id);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN v_r.violation_count || '/' || (v_r.banned_until IS NOT NULL);
END $$;

-- Makes [p_user]'s strikes look placed [p_days] ago, before W9d: no stamp.
CREATE FUNCTION pg_temp.pre_w9d(p_user uuid, p_days integer) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM private.opinion_enforcement_stamps WHERE user_id = p_user;
  UPDATE public.opinions SET removed_at = now() - make_interval(days => p_days)
   WHERE user_id = p_user AND removed_at IS NOT NULL;
END $$;

-- The full deletion path: prepare twice (delete-account retries), then
-- Auth's delete (the BEFORE DELETE triggers, then the cascade).
CREATE FUNCTION pg_temp.delete_account(p_user uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM public.prepare_account_deletion(p_user);
  PERFORM public.prepare_account_deletion(p_user);
  DELETE FROM auth.users WHERE id = p_user;
END $$;

-- The Opinions records under [p_hmac]: 'count/ban?' per row, by count.
CREATE FUNCTION pg_temp.records(p_hmac text) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce(string_agg(e.confirmed_report_count || '/' || (e.effect_until IS NOT NULL), ' '
                             ORDER BY e.confirmed_report_count), '')
    FROM public.enforcement_records AS e WHERE e.scope = 'opinions' AND e.phone_hmac = p_hmac;
$$;

CREATE FUNCTION pg_temp.metric(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce(sum(count), 0)::bigint FROM public.metric_counters WHERE key = p_key;
$$;

-- =====================================================================
-- A. Grants and shape: the stamps and every helper are no API role's;
--    the two entry points stay the service role's; the trigger is on
--    auth.users; the reserved scope takes the new type.
-- =====================================================================
DO $$
DECLARE
  v_role text;
  v_fn text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF has_table_privilege(v_role, 'private.opinion_enforcement_stamps', 'SELECT')
       OR has_table_privilege(v_role, 'private.opinion_enforcement_stamps', 'INSERT')
       OR has_table_privilege(v_role, 'private.opinion_enforcement_stamps', 'UPDATE')
       OR has_table_privilege(v_role, 'private.opinion_enforcement_stamps', 'DELETE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % can reach the Opinions stamps', v_role;
    END IF;
    FOREACH v_fn IN ARRAY ARRAY['private.opinion_carry_window()',
                                'private.opinion_stamp_enforcement(uuid,integer,timestamptz)',
                                'private.opinion_stamp_backfill()',
                                'private.opinion_deletion_carry(uuid,boolean)',
                                'private.opinion_carry_on_auth_user_delete()',
                                'private.opinion_enforcement_purge()',
                                'private.opinion_restore_on_auth_user()'] LOOP
      IF has_function_privilege(v_role, v_fn, 'EXECUTE') THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: % can execute %', v_role, v_fn;
      END IF;
    END LOOP;
  END LOOP;
  FOREACH v_fn IN ARRAY ARRAY['public.admin_confirm_content_removal(text,uuid)',
                              'public.prepare_account_deletion(uuid)'] LOOP
    IF has_function_privilege('anon', v_fn, 'EXECUTE') OR has_function_privilege('authenticated', v_fn, 'EXECUTE')
       OR NOT has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % must be the service role''s only', v_fn;
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'auth.users'::regclass
                  AND tgname = 'opinions_carry_on_auth_user_delete' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no Opinions carry trigger on auth.users';
  END IF;
  -- Final ruling: the trigger is the only restore path; complete_sign_up
  -- carries none; the trigger's lock waits are bounded.
  IF position('opinion_restore' IN pg_get_functiondef('public.complete_sign_up(text,date,text)'::regprocedure)) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: complete_sign_up still restores';
  END IF;
  IF NOT ('lock_timeout=2s' = ANY (coalesce((SELECT p.proconfig FROM pg_proc AS p
                                             WHERE p.oid = 'private.opinion_restore_on_auth_user()'::regprocedure), '{}'))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the restore trigger''s lock waits are unbounded';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'auth.users'::regclass
                  AND tgname = 'opinions_restore_on_auth_user' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no Opinions restore trigger on auth.users';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'opinion-enforcement-purge' AND schedule = '19 3 * * *'
                  AND command = 'SELECT private.opinion_enforcement_purge()') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no daily opinion-enforcement-purge cron';
  END IF;
  IF private.opinion_carry_window() IS DISTINCT FROM interval '30 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the carry window is %, not the ruled 30 days', private.opinion_carry_window();
  END IF;
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, purge_after)
  VALUES (repeat('a', 64), 'opinions', 'opinions_standing', now() + interval '1 day'),
         (repeat('b', 64), 'dating', 'suspended', now() + interval '1 day');
  DELETE FROM public.enforcement_records WHERE phone_hmac IN (repeat('a', 64), repeat('b', 64));
END $$;

-- =====================================================================
-- B. Stamps at strike time: each confirmed removal stamps the author's
--    number at that moment (and the ban it set); no HMAC means no stamp,
--    counted; a not-ready key stamps anyway, counted; a stamp failure
--    never fails the removal; the backfill stamps what no stamp covers.
-- =====================================================================
DO $$
DECLARE
  v_a uuid := pg_temp.person('01');
  v_b uuid := pg_temp.person('02');
  v_c uuid := pg_temp.person('03');
  v_d uuid := pg_temp.person('04');
  v_got text;
  v_before bigint;
  v_ban timestamptz;
BEGIN
  -- Strikes 1-3: the removal returns exactly what it did before W9d.
  v_got := pg_temp.strike(v_a) || ' ' || pg_temp.strike(v_a) || ' ' || pg_temp.strike(v_a);
  IF v_got IS DISTINCT FROM '1/false 2/false 3/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the removal''s result changed: %', v_got;
  END IF;
  SELECT p.banned_until INTO v_ban FROM public.profiles AS p WHERE p.id = v_a;
  IF (SELECT s.strikes || '/' || (s.ban_until = v_ban) FROM private.opinion_enforcement_stamps AS s
       WHERE s.user_id = v_a AND s.phone_hmac = pg_temp.h('01')) IS DISTINCT FROM '3/true'
     OR (SELECT count(*) FROM private.opinion_enforcement_stamps AS s WHERE s.user_id = v_a) IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: three strikes and the ban were not stamped under the author''s number';
  END IF;

  -- A strike, a number change, a strike: one stamp per number.
  PERFORM pg_temp.strike(v_b);
  UPDATE auth.users SET phone = '15558604099' WHERE id = v_b;
  PERFORM pg_temp.strike(v_b);
  IF (SELECT string_agg(s.strikes::text, ',' ORDER BY s.phone_hmac = pg_temp.h('02') DESC)
        FROM private.opinion_enforcement_stamps AS s WHERE s.user_id = v_b) IS DISTINCT FROM '1,1'
     OR NOT EXISTS (SELECT 1 FROM private.opinion_enforcement_stamps AS s
                     WHERE s.user_id = v_b AND s.phone_hmac = pg_temp.h('99')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a strike was not stamped under the number held when it was placed';
  END IF;

  -- No key: the removal still counts, nothing is stamped, counted.
  v_before := pg_temp.metric('opinions.enforcement.unstamped');
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  v_got := pg_temp.strike(v_c);
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec1-w9d-contract-exclusion-key', true);
  IF v_got IS DISTINCT FROM '1/false'
     OR EXISTS (SELECT 1 FROM private.opinion_enforcement_stamps AS s WHERE s.user_id = v_c)
     OR pg_temp.metric('opinions.enforcement.unstamped') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a strike without the key was lost, stamped or not counted (%)', v_got;
  END IF;

  -- A replaced key (fingerprint not ready): stamped under the live key, counted.
  v_before := pg_temp.metric('opinions.enforcement.key_not_ready');
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec1-w9d-contract-other-key', true);
  PERFORM pg_temp.strike(v_c);
  IF NOT EXISTS (SELECT 1 FROM private.opinion_enforcement_stamps AS s
                  WHERE s.user_id = v_c AND s.phone_hmac = public.dating_phone_hmac('+15558604003'))
     OR pg_temp.metric('opinions.enforcement.key_not_ready') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under a replaced key the strike was not stamped under the live key and counted';
  END IF;
  DELETE FROM private.opinion_enforcement_stamps WHERE user_id = v_c; -- that stamp is under a key the rest of the file doesn't use
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec1-w9d-contract-exclusion-key', true);

  -- A stamp that fails never fails the removal; counted.
  v_before := pg_temp.metric('opinions.enforcement.stamp_failed');
  ALTER TABLE private.opinion_enforcement_stamps ADD CONSTRAINT w9d_contract_refuse CHECK (strikes < 0) NOT VALID;
  v_got := pg_temp.strike(v_d);
  ALTER TABLE private.opinion_enforcement_stamps DROP CONSTRAINT w9d_contract_refuse;
  IF v_got IS DISTINCT FROM '1/false'
     OR pg_temp.metric('opinions.enforcement.stamp_failed') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failing stamp failed the removal or was not counted (%)', v_got;
  END IF;

  -- The backfill: person 03 (2 strikes, none stamped) and 04 (1 strike,
  -- none stamped, plus a live ban set directly) are stamped once.
  UPDATE public.profiles SET banned_until = now() + interval '3 days' WHERE id = v_d;
  IF private.opinion_stamp_backfill() < 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the backfill stamped fewer than the two uncovered accounts';
  END IF;
  IF (SELECT s.strikes FROM private.opinion_enforcement_stamps AS s
       WHERE s.user_id = v_c AND s.phone_hmac = pg_temp.h('03')) IS DISTINCT FROM 2
     OR (SELECT s.strikes || '/' || (s.ban_until > now() + interval '2 days') FROM private.opinion_enforcement_stamps AS s
          WHERE s.user_id = v_d AND s.phone_hmac = pg_temp.h('04')) IS DISTINCT FROM '1/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the backfill did not stamp the uncovered strikes and the live ban';
  END IF;
  IF private.opinion_stamp_backfill() IS DISTINCT FROM 0
     OR (SELECT sum(s.strikes) FROM private.opinion_enforcement_stamps AS s WHERE s.user_id IN (v_a, v_b, v_c, v_d))
        IS DISTINCT FROM 8 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second backfill stamped again';
  END IF;
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  IF private.opinion_stamp_backfill() IS DISTINCT FROM -1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the backfill ran without the key';
  END IF;
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec1-w9d-contract-exclusion-key', true);
END $$;

-- =====================================================================
-- B2. Batch-1 fix round 1. The backfill stamps a pre-W9d strike only when
--     the number provably hasn't changed since the earliest removal (M-1
--     ruling); a parked account is never stamped (M-3); a ban-only backfill
--     stamp, and a stamped ban outlasting later strikes (I-3).
-- =====================================================================
DO $$
DECLARE
  v_m uuid := pg_temp.person('46');
  v_n uuid := pg_temp.person('47');
  v_o uuid := pg_temp.person('48');
  v_q uuid := pg_temp.person('49');
  v_r uuid := pg_temp.person('50');
  v_s uuid := pg_temp.person('41');
  v_t uuid := pg_temp.person('51');
  v_x uuid;
  v_before bigint;
  v_got text;
BEGIN
  -- The reviewer's P3: three pre-W9d strikes and a ban on 46, then the
  -- number moves to a victim's 97 (a confirmed change),
  -- then the backfill, then the deletion. Nothing reaches 97.
  PERFORM pg_temp.strike(v_m); PERFORM pg_temp.strike(v_m); PERFORM pg_temp.strike(v_m);
  PERFORM pg_temp.pre_w9d(v_m, 10);
  UPDATE auth.users SET phone = '15558604097', phone_confirmed_at = now() WHERE id = v_m;
  v_before := pg_temp.metric('opinions.enforcement.backfill_phone_unverified');
  PERFORM private.opinion_stamp_backfill();
  IF EXISTS (SELECT 1 FROM private.opinion_enforcement_stamps WHERE user_id = v_m)
     OR pg_temp.metric('opinions.enforcement.backfill_phone_unverified') < v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the backfill stamped a pre-W9d strike after a number change, or did not count it';
  END IF;
  PERFORM pg_temp.delete_account(v_m);
  IF pg_temp.records(pg_temp.h('97')) IS DISTINCT FROM '' OR pg_temp.records(pg_temp.h('46')) IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pre-W9d strike reached a number the author moved to: % / %',
      pg_temp.records(pg_temp.h('97')), pg_temp.records(pg_temp.h('46'));
  END IF;

  -- Auth confirmed a number after the strike (a phone change confirms it).
  PERFORM pg_temp.strike(v_q);
  PERFORM pg_temp.pre_w9d(v_q, 10);
  UPDATE auth.users SET phone_confirmed_at = now() WHERE id = v_q;
  PERFORM private.opinion_stamp_backfill();
  IF EXISTS (SELECT 1 FROM private.opinion_enforcement_stamps WHERE user_id = v_q) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the backfill stamped a strike placed before the number was last confirmed';
  END IF;

  -- No removal to date the standing (a ban set directly, no strike).
  UPDATE public.profiles SET banned_until = now() + interval '5 days' WHERE id = v_n;
  PERFORM private.opinion_stamp_backfill();
  IF EXISTS (SELECT 1 FROM private.opinion_enforcement_stamps WHERE user_id = v_n) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the backfill stamped a standing it cannot date';
  END IF;

  -- A struck post since hard-deleted: its strike can't be dated.
  PERFORM pg_temp.strike(v_o); PERFORM pg_temp.strike(v_o);
  PERFORM pg_temp.pre_w9d(v_o, 10);
  DELETE FROM public.opinions WHERE id = (SELECT min(o.id::text)::uuid FROM public.opinions AS o WHERE o.user_id = v_o);
  PERFORM private.opinion_stamp_backfill();
  IF EXISTS (SELECT 1 FROM private.opinion_enforcement_stamps WHERE user_id = v_o) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the backfill stamped strikes with a struck post missing';
  END IF;

  -- The number unchanged since the strikes: stamped under it.
  PERFORM pg_temp.strike(v_r); PERFORM pg_temp.strike(v_r);
  PERFORM pg_temp.pre_w9d(v_r, 10);
  PERFORM private.opinion_stamp_backfill();
  IF (SELECT s.strikes FROM private.opinion_enforcement_stamps AS s
       WHERE s.user_id = v_r AND s.phone_hmac = pg_temp.h('50')) IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the backfill did not stamp pre-W9d strikes on an unchanged number';
  END IF;

  -- A ban set directly after a stamped strike: the backfill stamps the ban
  -- alone (1/true); a later strike below 3 keeps it (2/true); a stamp
  -- holding only the ban carries it (0/true).
  PERFORM pg_temp.strike(v_s);
  UPDATE public.profiles SET banned_until = now() + interval '5 days' WHERE id = v_s;
  PERFORM private.opinion_stamp_backfill();
  SELECT s.strikes || '/' || (s.ban_until > now()) INTO v_got FROM private.opinion_enforcement_stamps AS s WHERE s.user_id = v_s;
  IF v_got IS DISTINCT FROM '1/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the backfill did not stamp a live ban no stamp covered: %', v_got;
  END IF;
  PERFORM pg_temp.strike(v_s);
  SELECT s.strikes || '/' || coalesce(s.ban_until > now(), false) INTO v_got FROM private.opinion_enforcement_stamps AS s WHERE s.user_id = v_s;
  IF v_got IS DISTINCT FROM '2/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a strike below 3 dropped the stamped ban: %', v_got;
  END IF;
  UPDATE private.opinion_enforcement_stamps SET strikes = 0 WHERE user_id = v_s;
  PERFORM pg_temp.delete_account(v_s);
  IF pg_temp.records(pg_temp.h('41')) IS DISTINCT FROM '0/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stamp holding only a live ban did not carry it: %', pg_temp.records(pg_temp.h('41'));
  END IF;

  -- W1's reconcile in the same push rewrites public.users for everyone: the
  -- proof doesn't read it (final review M-2), so the strikes are stamped.
  v_x := pg_temp.person('73');
  PERFORM pg_temp.strike(v_x); PERFORM pg_temp.strike(v_x);
  PERFORM pg_temp.pre_w9d(v_x, 10);
  UPDATE public.users SET phone = '+' || phone WHERE id = v_x;
  PERFORM private.opinion_stamp_backfill();
  IF (SELECT s.strikes FROM private.opinion_enforcement_stamps AS s
       WHERE s.user_id = v_x AND s.phone_hmac = pg_temp.h('73')) IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the reconcile''s rewrite of public.users stopped the backfill';
  END IF;

  -- A number change requested after the strike (Auth's phone_change_sent_at,
  -- added here as Auth has it): not stamped.
  ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS phone_change_sent_at timestamptz;
  v_x := pg_temp.person('74');
  PERFORM pg_temp.strike(v_x);
  PERFORM pg_temp.pre_w9d(v_x, 10);
  UPDATE auth.users SET phone_change_sent_at = now() WHERE id = v_x;
  PERFORM private.opinion_stamp_backfill();
  IF EXISTS (SELECT 1 FROM private.opinion_enforcement_stamps WHERE user_id = v_x) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the backfill stamped a strike placed before a requested number change';
  END IF;

  -- Parked: never stamped (M-3), counted.
  PERFORM pg_temp.strike(v_t);
  UPDATE public.users SET phone_released_at = now(), parked_phone_hmac = pg_temp.h('51') WHERE id = v_t;
  v_before := pg_temp.metric('opinions.enforcement.parked_unstamped');
  PERFORM pg_temp.strike(v_t);
  IF (SELECT sum(s.strikes) FROM private.opinion_enforcement_stamps AS s WHERE s.user_id = v_t) IS DISTINCT FROM 1
     OR pg_temp.metric('opinions.enforcement.parked_unstamped') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a strike on a parked account was stamped, or not counted';
  END IF;
END $$;

-- =====================================================================
-- C. Carry at deletion: one record per stamp, under the stamped number;
--    only a live ban or a count above 0; the 30-day window; never the
--    deletion-time number (the phone-change attack); a parked account
--    carries nothing; a strike between prepare and the delete, or a
--    delete without prepare, still carries; nothing ever refuses; each
--    gap is counted once.
-- =====================================================================
DO $$
DECLARE
  v_a uuid := pg_temp.id('01');   -- 3 strikes, live ban, number 01
  v_b uuid := pg_temp.id('02');   -- 1 strike on 02, 1 on 99
  v_c uuid := pg_temp.id('03');   -- 2 strikes stamped by the backfill + 1 unstamped below
  v_e uuid := pg_temp.person('05');
  v_f uuid := pg_temp.person('06');
  v_g uuid := pg_temp.person('07');
  v_i uuid := pg_temp.person('08');
  v_j uuid := pg_temp.person('09');
  v_k uuid := pg_temp.person('10');
  v_l uuid := pg_temp.person('12');
  v_ban timestamptz;
  v_before bigint;
  v_before2 bigint;
BEGIN
  -- The whole path, twice prepared: exactly one record, the ban, 30 days.
  SELECT p.banned_until INTO v_ban FROM public.profiles AS p WHERE p.id = v_a;
  PERFORM pg_temp.delete_account(v_a);
  IF pg_temp.records(pg_temp.h('01')) IS DISTINCT FROM '3/true'
     OR NOT EXISTS (SELECT 1 FROM public.enforcement_records AS e
                     WHERE e.phone_hmac = pg_temp.h('01') AND e.scope = 'opinions'
                       AND e.restriction_type = 'opinions_standing' AND e.category IS NULL
                       AND e.effect_until = v_ban
                       AND e.purge_after BETWEEN now() + interval '29 days' AND now() + interval '31 days') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the strikes and live ban did not carry as one 30-day opinions record: %',
      pg_temp.records(pg_temp.h('01'));
  END IF;
  IF EXISTS (SELECT 1 FROM private.opinion_enforcement_stamps WHERE user_id = v_a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the stamps outlived the account';
  END IF;

  -- One record per number the strikes were placed under.
  PERFORM pg_temp.delete_account(v_b);
  IF pg_temp.records(pg_temp.h('02')) IS DISTINCT FROM '1/false'
     OR pg_temp.records(pg_temp.h('99')) IS DISTINCT FROM '1/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: strikes on two numbers did not carry under each: % / %',
      pg_temp.records(pg_temp.h('02')), pg_temp.records(pg_temp.h('99'));
  END IF;

  -- The phone-change attack (S2 W1 B3 I-1): three strikes and a ban on 05,
  -- then the account moves to a victim's number 98 and deletes.
  PERFORM pg_temp.strike(v_e); PERFORM pg_temp.strike(v_e); PERFORM pg_temp.strike(v_e);
  UPDATE auth.users SET phone = '15558604098' WHERE id = v_e;
  PERFORM pg_temp.delete_account(v_e);
  IF pg_temp.records(pg_temp.h('98')) IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a ban landed on the number the account moved to: %', pg_temp.records(pg_temp.h('98'));
  END IF;
  IF pg_temp.records(pg_temp.h('05')) IS DISTINCT FROM '3/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the ban did not stay with the number it was earned on: %', pg_temp.records(pg_temp.h('05'));
  END IF;

  -- Nothing to carry: count 0 and no ban; a stamped strike the owner has
  -- since pardoned (count 0, ban over); an expired ban on a stamp carries
  -- the count only.
  PERFORM pg_temp.strike(v_j);
  UPDATE public.profiles SET confirmed_violation_count = 0, banned_until = now() - interval '1 day' WHERE id = v_j;
  PERFORM pg_temp.delete_account(v_f);
  PERFORM pg_temp.delete_account(v_j);
  IF pg_temp.records(pg_temp.h('06')) IS DISTINCT FROM '' OR pg_temp.records(pg_temp.h('09')) IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an account with no strike and no live ban carried a record';
  END IF;
  PERFORM pg_temp.strike(v_k); PERFORM pg_temp.strike(v_k); PERFORM pg_temp.strike(v_k);
  UPDATE private.opinion_enforcement_stamps SET ban_until = now() - interval '1 hour' WHERE user_id = v_k;
  UPDATE public.profiles SET banned_until = now() - interval '1 hour' WHERE id = v_k;
  PERFORM pg_temp.delete_account(v_k);
  IF pg_temp.records(pg_temp.h('10')) IS DISTINCT FROM '3/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an expired ban carried, or its count did not: %', pg_temp.records(pg_temp.h('10'));
  END IF;

  -- No key at deletion: the stamps still carry (they need no key); a
  -- strike that was never stamped is counted once, and the deletion ends.
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  PERFORM pg_temp.strike(v_c); -- unstamped
  v_before := pg_temp.metric('opinions.deletion.uncarried');
  PERFORM pg_temp.delete_account(v_c);
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec1-w9d-contract-exclusion-key', true);
  IF EXISTS (SELECT 1 FROM auth.users WHERE id = v_c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deletion without the key did not complete';
  END IF;
  IF pg_temp.records(pg_temp.h('03')) IS DISTINCT FROM '2/false'
     OR pg_temp.metric('opinions.deletion.uncarried') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without the key the stamped strikes did not carry, or the gap was not counted once (%)',
      pg_temp.records(pg_temp.h('03'));
  END IF;

  -- A replaced key at deletion: carried under the stamps, counted, completed.
  PERFORM pg_temp.strike(v_l);
  v_before := pg_temp.metric('opinions.deletion.key_not_ready');
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec1-w9d-contract-other-key', true);
  PERFORM pg_temp.delete_account(v_l);
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec1-w9d-contract-exclusion-key', true);
  IF pg_temp.records(pg_temp.h('12')) IS DISTINCT FROM '1/false'
     OR pg_temp.metric('opinions.deletion.key_not_ready') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under a replaced key the deletion did not carry its stamps and count it (%)',
      pg_temp.records(pg_temp.h('12'));
  END IF;

  -- Parked (Spec 1 O3): nothing carries; counted once.
  v_f := pg_temp.person('13');
  PERFORM pg_temp.strike(v_f);
  UPDATE public.users SET phone_released_at = now(), parked_phone_hmac = pg_temp.h('13') WHERE id = v_f;
  v_before := pg_temp.metric('opinions.deletion.parked_not_carried');
  PERFORM pg_temp.delete_account(v_f);
  IF pg_temp.records(pg_temp.h('13')) IS DISTINCT FROM ''
     OR pg_temp.metric('opinions.deletion.parked_not_carried') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a parked account carried its strikes onto the number, or was not counted';
  END IF;

  -- A strike between prepare and Auth's delete still carries (I-2).
  PERFORM pg_temp.strike(v_g);
  PERFORM public.prepare_account_deletion(v_g);
  PERFORM pg_temp.strike(v_g);
  DELETE FROM auth.users WHERE id = v_g;
  IF pg_temp.records(pg_temp.h('07')) IS DISTINCT FROM '2/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a strike placed after prepare did not carry: %', pg_temp.records(pg_temp.h('07'));
  END IF;

  -- A delete that skips prepare still carries.
  PERFORM pg_temp.strike(v_i);
  DELETE FROM auth.users WHERE id = v_i;
  IF pg_temp.records(pg_temp.h('08')) IS DISTINCT FROM '1/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deletion without prepare did not carry: %', pg_temp.records(pg_temp.h('08'));
  END IF;

  -- A carry that fails never refuses the deletion; counted at both passes.
  v_i := pg_temp.person('14');
  PERFORM pg_temp.strike(v_i);
  v_before := pg_temp.metric('opinions.deletion.prepare_carry_failed');
  v_before2 := pg_temp.metric('opinions.deletion.late_carry_failed');
  ALTER TABLE public.enforcement_records ADD CONSTRAINT w9d_contract_refuse CHECK (scope <> 'opinions') NOT VALID;
  PERFORM pg_temp.delete_account(v_i);
  ALTER TABLE public.enforcement_records DROP CONSTRAINT w9d_contract_refuse;
  IF EXISTS (SELECT 1 FROM auth.users WHERE id = v_i)
     OR pg_temp.metric('opinions.deletion.prepare_carry_failed') IS DISTINCT FROM v_before + 2
     OR pg_temp.metric('opinions.deletion.late_carry_failed') IS DISTINCT FROM v_before2 + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failing carry blocked the deletion or was not counted';
  END IF;

  -- Dating is untouched: an opinions record never closes Dating standing.
  -- (Made while the key is missing, so the restore leaves 01's record.)
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  v_i := pg_temp.person('01');
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec1-w9d-contract-exclusion-key', true);
  IF NOT public.dating_account_in_good_standing(v_i) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an Opinions record closed Dating for the number';
  END IF;
  DELETE FROM auth.users WHERE id = v_i;
END $$;

-- =====================================================================
-- C2. Batch-1 fix round 1: the carry is the standing now, capped by the
--     stamp (I-1); a ban past 30 days sets the purge (I-3); an uncovered
--     live ban is counted (I-3); the 2-year cap; the daily purge (I-2).
-- =====================================================================
DO $$
DECLARE
  v_a uuid := pg_temp.person('43');
  v_b uuid := pg_temp.person('44');
  v_c uuid := pg_temp.person('45');
  v_d uuid := pg_temp.person('52');
  v_e uuid := pg_temp.person('53');
  v_f uuid := pg_temp.person('40');
  v_g uuid := pg_temp.person('42');
  v_h uuid := pg_temp.person('54');
  v_before bigint;
  v_got integer;
BEGIN
  -- The owner pardons down to 1 and lifts the ban: 1, no ban.
  PERFORM pg_temp.strike(v_a); PERFORM pg_temp.strike(v_a); PERFORM pg_temp.strike(v_a);
  UPDATE public.profiles SET confirmed_violation_count = 1, banned_until = NULL WHERE id = v_a;
  PERFORM pg_temp.delete_account(v_a);
  IF pg_temp.records(pg_temp.h('43')) IS DISTINCT FROM '1/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pardon did not lower what was carried: %', pg_temp.records(pg_temp.h('43'));
  END IF;

  -- A full pardon between prepare and the delete removes prepare's record.
  PERFORM pg_temp.strike(v_b); PERFORM pg_temp.strike(v_b); PERFORM pg_temp.strike(v_b);
  PERFORM public.prepare_account_deletion(v_b);
  UPDATE public.profiles SET confirmed_violation_count = 0, banned_until = NULL WHERE id = v_b;
  DELETE FROM auth.users WHERE id = v_b;
  IF pg_temp.records(pg_temp.h('44')) IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pardon after prepare left its record: %', pg_temp.records(pg_temp.h('44'));
  END IF;

  -- A partial pardon between prepare and the delete lowers prepare's record.
  PERFORM pg_temp.strike(v_c); PERFORM pg_temp.strike(v_c); PERFORM pg_temp.strike(v_c);
  PERFORM public.prepare_account_deletion(v_c);
  UPDATE public.profiles SET confirmed_violation_count = 1, banned_until = NULL WHERE id = v_c;
  DELETE FROM auth.users WHERE id = v_c;
  IF pg_temp.records(pg_temp.h('45')) IS DISTINCT FROM '1/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pardon after prepare did not lower its record: %', pg_temp.records(pg_temp.h('45'));
  END IF;

  -- After prepare, the count is pardoned but a ban set directly: the stamp
  -- (a strike, no ban) no longer carries; its record goes.
  PERFORM pg_temp.strike(v_d);
  PERFORM public.prepare_account_deletion(v_d);
  UPDATE public.profiles SET confirmed_violation_count = 0, banned_until = now() + interval '5 days' WHERE id = v_d;
  DELETE FROM auth.users WHERE id = v_d;
  IF pg_temp.records(pg_temp.h('52')) IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stamp that no longer carries kept its record: %', pg_temp.records(pg_temp.h('52'));
  END IF;

  -- Parked between prepare and the delete: prepare's record goes.
  PERFORM pg_temp.strike(v_e);
  PERFORM public.prepare_account_deletion(v_e);
  UPDATE public.users SET phone_released_at = now(), parked_phone_hmac = pg_temp.h('53') WHERE id = v_e;
  DELETE FROM auth.users WHERE id = v_e;
  IF pg_temp.records(pg_temp.h('53')) IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an account parked after prepare kept its record: %', pg_temp.records(pg_temp.h('53'));
  END IF;

  -- A 60-day ban: kept to its end, not 30 days.
  PERFORM pg_temp.strike(v_f); PERFORM pg_temp.strike(v_f); PERFORM pg_temp.strike(v_f);
  UPDATE private.opinion_enforcement_stamps SET ban_until = now() + interval '60 days' WHERE user_id = v_f;
  UPDATE public.profiles SET banned_until = now() + interval '60 days' WHERE id = v_f;
  PERFORM pg_temp.delete_account(v_f);
  IF NOT EXISTS (SELECT 1 FROM public.enforcement_records AS e
                  WHERE e.phone_hmac = pg_temp.h('40') AND e.scope = 'opinions'
                    AND e.purge_after BETWEEN now() + interval '59 days' AND now() + interval '61 days') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 60-day ban was not kept to its end: %', pg_temp.records(pg_temp.h('40'));
  END IF;

  -- A live ban no stamp covers: the count carries, the gap is counted.
  PERFORM pg_temp.strike(v_g);
  UPDATE public.profiles SET banned_until = now() + interval '5 days' WHERE id = v_g;
  v_before := pg_temp.metric('opinions.deletion.uncarried');
  PERFORM pg_temp.delete_account(v_g);
  IF pg_temp.records(pg_temp.h('42')) IS DISTINCT FROM '1/false'
     OR pg_temp.metric('opinions.deletion.uncarried') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an uncovered live ban was carried or not counted: %', pg_temp.records(pg_temp.h('42'));
  END IF;

  -- A 3-year ban: carried, purge capped at 2 years.
  PERFORM pg_temp.strike(v_h); PERFORM pg_temp.strike(v_h); PERFORM pg_temp.strike(v_h);
  UPDATE private.opinion_enforcement_stamps SET ban_until = now() + interval '3 years' WHERE user_id = v_h;
  UPDATE public.profiles SET banned_until = now() + interval '3 years' WHERE id = v_h;
  PERFORM pg_temp.delete_account(v_h);
  IF NOT EXISTS (SELECT 1 FROM public.enforcement_records AS e
                  WHERE e.phone_hmac = pg_temp.h('54') AND e.scope = 'opinions'
                    AND e.purge_after <= now() + interval '2 years') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a ban past 2 years did not carry within the 2-year cap: %', pg_temp.records(pg_temp.h('54'));
  END IF;

  -- A Dating record whose source id is a stamp's: never rewritten.
  v_g := pg_temp.person('55');
  PERFORM pg_temp.strike(v_g);
  INSERT INTO public.enforcement_records (phone_hmac, scope, source_restriction_id, restriction_type, purge_after)
  SELECT repeat('e', 64), 'dating', s.id, 'suspended', now() + interval '1 day'
    FROM private.opinion_enforcement_stamps AS s WHERE s.user_id = v_g;
  PERFORM pg_temp.delete_account(v_g);
  IF (SELECT e.scope || '/' || e.restriction_type || '/' || e.confirmed_report_count || '/' || e.phone_hmac
        FROM public.enforcement_records AS e WHERE e.phone_hmac IN (repeat('e', 64), pg_temp.h('55')))
     IS DISTINCT FROM 'dating/suspended/0/' || repeat('e', 64) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Opinions carry rewrote a Dating record';
  END IF;

  -- A late pass on a record made days earlier keeps the 2-year cap.
  v_g := pg_temp.person('56');
  PERFORM pg_temp.strike(v_g); PERFORM pg_temp.strike(v_g); PERFORM pg_temp.strike(v_g);
  UPDATE private.opinion_enforcement_stamps SET ban_until = now() + interval '3 years' WHERE user_id = v_g;
  UPDATE public.profiles SET banned_until = now() + interval '3 years' WHERE id = v_g;
  PERFORM public.prepare_account_deletion(v_g);
  UPDATE public.enforcement_records SET created_at = now() - interval '2 days', purge_after = now() + interval '30 days'
   WHERE phone_hmac = pg_temp.h('56');
  DELETE FROM auth.users WHERE id = v_g;
  IF (SELECT e.purge_after = e.created_at + interval '2 years' FROM public.enforcement_records AS e
       WHERE e.phone_hmac = pg_temp.h('56')) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the late pass did not extend to the ban within the 2-year cap';
  END IF;

  -- The daily purge: an expired opinions record goes, a live one stays,
  -- Dating's expired one is never touched; counted per row.
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, confirmed_report_count, purge_after, created_at)
  VALUES (repeat('c', 64), 'opinions', 'opinions_standing', 2, now() - interval '1 hour', now() - interval '31 days'),
         (repeat('d', 64), 'dating', 'suspended', 0, now() - interval '1 hour', now() - interval '2 years');
  v_before := pg_temp.metric('opinions.enforcement.purged');
  v_got := private.opinion_enforcement_purge();
  IF v_got IS DISTINCT FROM 1
     OR EXISTS (SELECT 1 FROM public.enforcement_records WHERE phone_hmac = repeat('c', 64))
     OR NOT EXISTS (SELECT 1 FROM public.enforcement_records WHERE phone_hmac = repeat('d', 64))
     OR pg_temp.records(pg_temp.h('40')) IS DISTINCT FROM '3/true'
     OR pg_temp.metric('opinions.enforcement.purged') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge did not remove exactly the expired opinions record (% removed)', v_got;
  END IF;
  IF private.opinion_enforcement_purge() IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second purge removed more';
  END IF;
END $$;

-- =====================================================================
-- D. Restore at sign-up (complete_sign_up, migration 2): the same number
--    within the window gets the count and live ban back, once, at the
--    call that creates the account; the records are taken, so a second
--    round trip never counts twice; past the window, another number, or
--    an account that already existed restores nothing; no key restores
--    nothing (counted); a replaced key restores under the live key
--    (counted); a failing restore never refuses the sign-up.
-- =====================================================================
-- A new account [p_n] on number 155586040<p_phone> completes A1-A5.
CREATE FUNCTION pg_temp.sign_up(p_n text, p_phone text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (pg_temp.id(p_n), '155586040' || p_phone, now(), now());
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', pg_temp.id(p_n)::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', pg_temp.id(p_n), 'role', 'authenticated')::text, true);
  v := public.complete_sign_up('W9d returner', DATE '1990-01-01', '2');
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN v;
END $$;

-- [p_user]'s Opinions standing: 'count/banned'.
CREATE FUNCTION pg_temp.standing(p_user uuid) RETURNS text LANGUAGE sql AS $$
  SELECT p.confirmed_violation_count || '/' || coalesce(p.banned_until > now(), false)
    FROM public.profiles AS p WHERE p.id = p_user;
$$;

DO $$
DECLARE
  v_ban timestamptz := (SELECT e.effect_until FROM public.enforcement_records AS e
                         WHERE e.scope = 'opinions' AND e.phone_hmac = pg_temp.h('01'));
  v_res jsonb;
  v_before bigint;
  v_u uuid;
BEGIN
  -- The same number, the next day: count and ban back, record taken, one
  -- stamp under the number; the sign-up answers exactly as before.
  v_before := pg_temp.metric('opinions.restore.applied');
  v_res := pg_temp.sign_up('21', '01');
  IF v_res IS DISTINCT FROM jsonb_build_object('age', private.age_on_utc_today(DATE '1990-01-01'), 'created', true) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sign-up''s answer changed: %', v_res;
  END IF;
  IF pg_temp.standing(pg_temp.id('21')) IS DISTINCT FROM '3/true'
     OR (SELECT p.banned_until FROM public.profiles AS p WHERE p.id = pg_temp.id('21')) IS DISTINCT FROM v_ban THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the same number did not get its strikes and live ban back: %', pg_temp.standing(pg_temp.id('21'));
  END IF;
  IF pg_temp.records(pg_temp.h('01')) IS DISTINCT FROM ''
     OR (SELECT s.strikes || '/' || (s.ban_until = v_ban) FROM private.opinion_enforcement_stamps AS s
          WHERE s.user_id = pg_temp.id('21') AND s.phone_hmac = pg_temp.h('01')) IS DISTINCT FROM '3/true'
     OR pg_temp.metric('opinions.restore.applied') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the restored record was not taken, re-stamped and counted';
  END IF;

  -- A second call (the account exists): nothing more.
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', pg_temp.id('21'), 'role', 'authenticated')::text, true);
  v_res := public.complete_sign_up('W9d returner', DATE '1990-01-01', '2');
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  IF v_res ->> 'created' IS DISTINCT FROM 'false' OR pg_temp.standing(pg_temp.id('21')) IS DISTINCT FROM '3/true'
     OR pg_temp.metric('opinions.restore.applied') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a repeated sign-up call restored again';
  END IF;

  -- The round trip again: one more strike, delete, sign up: 4, never 7.
  PERFORM pg_temp.strike(pg_temp.id('21'));
  PERFORM pg_temp.delete_account(pg_temp.id('21'));
  PERFORM pg_temp.sign_up('31', '01');
  IF pg_temp.standing(pg_temp.id('31')) IS DISTINCT FROM '4/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second deletion and sign-up did not give back exactly 4 strikes: %',
      pg_temp.standing(pg_temp.id('31'));
  END IF;

  -- Past the window (owner decision W9d-1): nothing back, the record removed.
  UPDATE public.enforcement_records SET purge_after = now() - interval '1 minute'
   WHERE scope = 'opinions' AND phone_hmac = pg_temp.h('10');
  PERFORM pg_temp.sign_up('22', '10');
  IF pg_temp.standing(pg_temp.id('22')) IS DISTINCT FROM '0/false' OR pg_temp.records(pg_temp.h('10')) IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a record past its window restored, or was kept: %', pg_temp.standing(pg_temp.id('22'));
  END IF;

  -- The victim of the phone-change attack signs up on their own number;
  -- a Dating record on it is never taken by the Opinions restore.
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, confirmed_report_count, purge_after)
  VALUES (pg_temp.h('98'), 'dating', 'suspended', 5, now() + interval '1 year');
  PERFORM pg_temp.sign_up('23', '98');
  IF pg_temp.standing(pg_temp.id('23')) IS DISTINCT FROM '0/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the number an attacker moved to inherited their strikes';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.enforcement_records AS e WHERE e.phone_hmac = pg_temp.h('98') AND e.scope = 'dating') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an Opinions restore took a Dating record';
  END IF;

  -- A carried ban that has since ended restores the count only.
  UPDATE public.enforcement_records SET effect_until = now() - interval '1 hour'
   WHERE scope = 'opinions' AND phone_hmac = pg_temp.h('12');
  PERFORM pg_temp.sign_up('27', '12');
  IF pg_temp.standing(pg_temp.id('27')) IS DISTINCT FROM '1/false'
     OR (SELECT p.banned_until FROM public.profiles AS p WHERE p.id = pg_temp.id('27')) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a carried ban that had ended came back: %', pg_temp.standing(pg_temp.id('27'));
  END IF;

  -- No key: nothing restored, counted, the record kept, the sign-up done.
  v_before := pg_temp.metric('opinions.restore.key_missing');
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  v_res := pg_temp.sign_up('24', '02');
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec1-w9d-contract-exclusion-key', true);
  IF v_res ->> 'created' IS DISTINCT FROM 'true' OR pg_temp.standing(pg_temp.id('24')) IS DISTINCT FROM '0/false'
     OR pg_temp.records(pg_temp.h('02')) IS DISTINCT FROM '1/false'
     OR pg_temp.metric('opinions.restore.key_missing') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a sign-up without the key restored, failed, dropped the record or was not counted';
  END IF;

  -- A fingerprint that isn't ready: restored under the live key, counted;
  -- a count-only record leaves the ban empty.
  v_before := pg_temp.metric('opinions.restore.key_not_ready');
  UPDATE private.dating_key_fingerprints SET fingerprint = repeat('c', 64) WHERE name = 'dating_exclusion_key';
  PERFORM pg_temp.sign_up('25', '99');
  DELETE FROM private.dating_key_fingerprints WHERE name = 'dating_exclusion_key';
  PERFORM private.seed_dating_exclusion_key_fingerprint();
  IF pg_temp.standing(pg_temp.id('25')) IS DISTINCT FROM '1/false'
     OR (SELECT p.banned_until FROM public.profiles AS p WHERE p.id = pg_temp.id('25')) IS NOT NULL
     OR pg_temp.metric('opinions.restore.key_not_ready') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under a fingerprint that isn''t ready the count was not restored and counted: %',
      pg_temp.standing(pg_temp.id('25'));
  END IF;

  -- A restore that fails never refuses the sign-up; the record stays.
  v_before := pg_temp.metric('opinions.restore.failed');
  ALTER TABLE public.profiles ADD CONSTRAINT w9d_contract_refuse CHECK (confirmed_violation_count < 1) NOT VALID;
  v_res := pg_temp.sign_up('26', '05');
  ALTER TABLE public.profiles DROP CONSTRAINT w9d_contract_refuse;
  IF v_res ->> 'created' IS DISTINCT FROM 'true' OR pg_temp.standing(pg_temp.id('26')) IS DISTINCT FROM '0/false'
     OR pg_temp.records(pg_temp.h('05')) IS DISTINCT FROM '3/true'
     OR pg_temp.metric('opinions.restore.failed') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failing restore refused the sign-up, took the record or was not counted';
  END IF;

  -- An account that already held the number (made while the key was
  -- missing, its DOB stored) never restores at a later call.
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  v_u := pg_temp.person('08');
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec1-w9d-contract-exclusion-key', true);
  INSERT INTO public.account_birthdates (user_id, birth_date) VALUES (v_u, DATE '1990-01-01');
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u, 'role', 'authenticated')::text, true);
  v_res := public.complete_sign_up('W9d existing', DATE '1990-01-01', '2');
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  IF pg_temp.standing(v_u) IS DISTINCT FROM '0/false' OR pg_temp.records(pg_temp.h('08')) IS DISTINCT FROM '1/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an existing account''s sign-up call took a carried record: %', pg_temp.standing(v_u);
  END IF;

  -- Dating is untouched by a restore.
  IF NOT public.dating_account_in_good_standing(pg_temp.id('31')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a restored Opinions record closed Dating';
  END IF;
END $$;
-- =====================================================================
-- D2. Batch 2 (implementer): a parked account's number restores nothing;
--     an empty restore counts nothing applied; a keyless sign-up counts
--     only key_missing; a record past its window never restores its ban,
--     even if edited to look live; a restore with no profile raises inside
--     its block and the record stays.
-- =====================================================================
DO $$
DECLARE
  v_applied bigint := pg_temp.metric('opinions.restore.applied');
  v_missing bigint;
  v_not_ready bigint;
  v_err text;
BEGIN
  -- Parked (W9d-2): section C's parked account 13 carried nothing, so its
  -- number's next holder starts clean.
  PERFORM pg_temp.sign_up('57', '13');
  IF pg_temp.standing(pg_temp.id('57')) IS DISTINCT FROM '0/false'
     OR pg_temp.metric('opinions.restore.applied') IS DISTINCT FROM v_applied THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a parked account''s number restored, or an empty restore was counted applied';
  END IF;

  -- No key: only key_missing moves.
  v_missing := pg_temp.metric('opinions.restore.key_missing');
  v_not_ready := pg_temp.metric('opinions.restore.key_not_ready');
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  PERFORM pg_temp.sign_up('58', '58');
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec1-w9d-contract-exclusion-key', true);
  IF pg_temp.metric('opinions.restore.key_missing') IS DISTINCT FROM v_missing + 1
     OR pg_temp.metric('opinions.restore.key_not_ready') IS DISTINCT FROM v_not_ready THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a keyless sign-up went past the missing key';
  END IF;

  -- Past its window, a ban edited to look live: nothing back, record gone.
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, confirmed_report_count,
                                          effect_until, purge_after, created_at)
  VALUES (pg_temp.h('59'), 'opinions', 'opinions_standing', 0, now() + interval '3 days',
          now() - interval '1 minute', now() - interval '31 days');
  PERFORM pg_temp.sign_up('59', '59');
  IF pg_temp.standing(pg_temp.id('59')) IS DISTINCT FROM '0/false' OR pg_temp.records(pg_temp.h('59')) IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a record past its window restored a ban: %', pg_temp.standing(pg_temp.id('59'));
  END IF;

  -- No profile yet (an account's first confirmation): the restore makes
  -- the profile row with the standing (final review I-1).
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (pg_temp.id('60'), '15558604060', now(), now());
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, confirmed_report_count, purge_after)
  VALUES (pg_temp.h('60'), 'opinions', 'opinions_standing', 2, now() + interval '20 days');
  PERFORM private.opinion_restore_on_sign_up(pg_temp.id('60'));
  IF pg_temp.standing(pg_temp.id('60')) IS DISTINCT FROM '2/false' OR pg_temp.records(pg_temp.h('60')) IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a restore with no profile did not make it: %', pg_temp.standing(pg_temp.id('60'));
  END IF;
END $$;

-- =====================================================================
-- D3. Batch-2 fix round 1: every restore is logged (no phone, no HMAC) in
--     private.opinion_restores; the owner's private.undo_opinion_restore
--     takes back exactly what was restored, never the account's own
--     strikes, and a second undo changes nothing (I-1); a legacy account
--     whose own standing is higher keeps it (M-1); a restore whose stamp
--     fails stands, counted (M-3); neither the log nor the undo is a
--     client's.
-- =====================================================================
-- Owner's undo, as the SQL editor reaches it.
CREATE FUNCTION pg_temp.undo(p_user uuid) RETURNS boolean LANGUAGE sql AS $$
  SELECT private.undo_opinion_restore(p_user);
$$;

-- A deleted account on number [p_n] that carried [p_strikes] strikes.
CREATE FUNCTION pg_temp.carried(p_n text, p_strikes integer) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v uuid := pg_temp.person(p_n);
BEGIN
  FOR i IN 1..p_strikes LOOP
    PERFORM pg_temp.strike(v);
  END LOOP;
  PERFORM pg_temp.delete_account(v);
END $$;

DO $$
DECLARE
  v_a uuid := pg_temp.id('62');
  v_b uuid := pg_temp.id('64');
  v_c uuid := pg_temp.id('66');
  v_l uuid;
  v_ban timestamptz;
  v_before bigint;
  v_noop bigint;
  v_got text;
BEGIN
  -- Neither the log nor the undo is a client's; the log has no phone or HMAC.
  IF has_table_privilege('anon', 'private.opinion_restores', 'SELECT')
     OR has_table_privilege('authenticated', 'private.opinion_restores', 'SELECT')
     OR has_table_privilege('authenticated', 'private.opinion_restores', 'INSERT')
     OR has_table_privilege('service_role', 'private.opinion_restores', 'SELECT')
     OR has_function_privilege('anon', 'private.undo_opinion_restore(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.undo_opinion_restore(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'private.undo_opinion_restore(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the restore log or the undo is reachable by a client';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'private' AND table_name = 'opinion_restores'
                AND (column_name ~ 'phone|hmac')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the restore log holds a phone or an HMAC';
  END IF;

  -- 3 strikes and a ban carried on 61, restored to 62; it is logged.
  PERFORM pg_temp.carried('61', 3);
  v_ban := (SELECT e.effect_until FROM public.enforcement_records AS e WHERE e.scope = 'opinions' AND e.phone_hmac = pg_temp.h('61'));
  PERFORM pg_temp.sign_up('62', '61');
  SELECT o.restored_count || '/' || (o.restored_ban = v_ban) || '/' || (o.prior_ban IS NULL) || '/'
         || cardinality(o.source_record_ids) || '/' || (o.deleted_at IS NOT NULL) || '/' || (o.stamp_id IS NOT NULL)
    INTO v_got FROM private.opinion_restores AS o WHERE o.user_id = v_a;
  IF v_got IS DISTINCT FROM '3/true/true/1/true/true' OR pg_temp.standing(v_a) IS DISTINCT FROM '3/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the restore was not logged as it happened: %', v_got;
  END IF;

  -- The account earns a strike of its own (the ban extends); the undo
  -- takes back the 3 restored and keeps the earned 1. The extended ban came
  -- from the restored count (1 own strike never bans): it goes (final
  -- review M-1 ruling).
  PERFORM pg_temp.strike(v_a);
  v_before := pg_temp.metric('opinions.restore.undone');
  IF pg_temp.undo(v_a) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the undo did nothing';
  END IF;
  IF pg_temp.standing(v_a) IS DISTINCT FROM '1/false'
     OR (SELECT s.strikes || '/' || (s.ban_until IS NULL) FROM private.opinion_enforcement_stamps AS s
          WHERE s.user_id = v_a AND s.phone_hmac = pg_temp.h('61')) IS DISTINCT FROM '1/true'
     OR pg_temp.metric('opinions.restore.undone') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the undo did not take back exactly the restored part: %', pg_temp.standing(v_a);
  END IF;

  -- A second undo: nothing changes, counted as a no-op.
  v_noop := pg_temp.metric('opinions.restore.undo_noop');
  IF pg_temp.undo(v_a) IS DISTINCT FROM false OR pg_temp.standing(v_a) IS DISTINCT FROM '1/false'
     OR pg_temp.metric('opinions.restore.undone') IS DISTINCT FROM v_before + 1
     OR pg_temp.metric('opinions.restore.undo_noop') IS DISTINCT FROM v_noop + 1
     OR (SELECT o.undone_at IS NOT NULL FROM private.opinion_restores AS o WHERE o.user_id = v_a) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second undo changed something: %', pg_temp.standing(v_a);
  END IF;

  -- A restore with nothing since: the undo gives back a clean account.
  PERFORM pg_temp.carried('63', 3);
  PERFORM pg_temp.sign_up('64', '63');
  PERFORM pg_temp.undo(v_b);
  IF pg_temp.standing(v_b) IS DISTINCT FROM '0/false'
     OR (SELECT s.strikes || '/' || (s.ban_until IS NULL) FROM private.opinion_enforcement_stamps AS s
          WHERE s.user_id = v_b) IS DISTINCT FROM '0/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the undo left restored strikes or the restored ban: %', pg_temp.standing(v_b);
  END IF;

  -- Restored 1 (no ban); the account then earns 3 of its own: the undo
  -- keeps the 3 and the ban they earned.
  PERFORM pg_temp.carried('65', 1);
  PERFORM pg_temp.sign_up('66', '65');
  PERFORM pg_temp.strike(v_c); PERFORM pg_temp.strike(v_c); PERFORM pg_temp.strike(v_c);
  PERFORM pg_temp.undo(v_c);
  IF pg_temp.standing(v_c) IS DISTINCT FROM '3/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the undo took strikes or a ban the account earned itself: %', pg_temp.standing(v_c);
  END IF;

  -- No restore: the undo changes nothing.
  v_noop := pg_temp.metric('opinions.restore.undo_noop');
  IF pg_temp.undo(pg_temp.id('57')) IS DISTINCT FROM false
     OR pg_temp.metric('opinions.restore.undo_noop') IS DISTINCT FROM v_noop + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an undo without a restore did something';
  END IF;

  -- A ban the owner set after the restore stays through the undo.
  PERFORM pg_temp.carried('70', 3);
  PERFORM pg_temp.sign_up('71', '70');
  v_ban := now() + interval '10 days';
  UPDATE public.profiles SET banned_until = v_ban WHERE id = pg_temp.id('71');
  PERFORM pg_temp.undo(pg_temp.id('71'));
  IF pg_temp.standing(pg_temp.id('71')) IS DISTINCT FROM '0/true'
     OR (SELECT p.banned_until FROM public.profiles AS p WHERE p.id = pg_temp.id('71')) IS DISTINCT FROM v_ban THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the undo cleared a ban the restore did not set: %', pg_temp.standing(pg_temp.id('71'));
  END IF;

  -- The log's retention: a row 90 days after its restore goes in the daily
  -- purge; a younger one stays; nothing else is touched.
  UPDATE private.opinion_restores SET restored_at = now() - interval '91 days' WHERE user_id = pg_temp.id('64');
  UPDATE private.opinion_restores SET restored_at = now() - interval '89 days' WHERE user_id = pg_temp.id('66');
  v_before := pg_temp.metric('opinions.restore.log_purged');
  v_noop := (SELECT count(*) FROM public.enforcement_records);
  PERFORM private.opinion_enforcement_purge();
  IF EXISTS (SELECT 1 FROM private.opinion_restores WHERE user_id = pg_temp.id('64'))
     OR NOT EXISTS (SELECT 1 FROM private.opinion_restores WHERE user_id = pg_temp.id('66'))
     OR NOT EXISTS (SELECT 1 FROM private.opinion_restores WHERE user_id = v_a)
     OR pg_temp.metric('opinions.restore.log_purged') IS DISTINCT FROM v_before + 1
     OR (SELECT count(*) FROM public.enforcement_records) IS DISTINCT FROM v_noop
     OR pg_temp.standing(v_b) IS DISTINCT FROM '0/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the daily purge did not remove exactly the restore-log rows past 90 days';
  END IF;

  -- M-1 (the reviewer's probe, now through the trigger): an existing account
  -- with 4 strikes of its own and a longer ban confirms a change onto a
  -- number carrying a 2-count record with a shorter ban: it keeps 4 and its
  -- own ban, takes the record, and logs nothing added.
  v_l := pg_temp.person('67');
  PERFORM pg_temp.strike(v_l); PERFORM pg_temp.strike(v_l); PERFORM pg_temp.strike(v_l); PERFORM pg_temp.strike(v_l);
  v_ban := (SELECT p.banned_until FROM public.profiles AS p WHERE p.id = v_l);
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, confirmed_report_count, effect_until, purge_after)
  VALUES (pg_temp.h('76'), 'opinions', 'opinions_standing', 2, now() + interval '3 days', now() + interval '20 days');
  UPDATE auth.users SET phone = '15558604076', phone_confirmed_at = now() WHERE id = v_l;
  IF pg_temp.standing(v_l) IS DISTINCT FROM '4/true'
     OR (SELECT p.banned_until FROM public.profiles AS p WHERE p.id = v_l) IS DISTINCT FROM v_ban
     OR pg_temp.records(pg_temp.h('76')) IS DISTINCT FROM ''
     OR (SELECT o.restored_count || '/' || (o.restored_ban IS NULL) FROM private.opinion_restores AS o WHERE o.user_id = v_l)
        IS DISTINCT FROM '0/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a legacy account''s own standing was lowered, or the log is wrong: %', pg_temp.standing(v_l);
  END IF;

  -- An existing account with 3 strikes and a ban of its own confirms a
  -- change onto a number carrying a 5-count record with a later ban: the
  -- undo puts back 3 and its own ban.
  v_l := pg_temp.person('69');
  PERFORM pg_temp.strike(v_l); PERFORM pg_temp.strike(v_l); PERFORM pg_temp.strike(v_l);
  v_ban := (SELECT p.banned_until FROM public.profiles AS p WHERE p.id = v_l);
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, confirmed_report_count, effect_until, purge_after)
  VALUES (pg_temp.h('77'), 'opinions', 'opinions_standing', 5, now() + interval '20 days', now() + interval '20 days');
  UPDATE auth.users SET phone = '15558604077', phone_confirmed_at = now() WHERE id = v_l;
  PERFORM pg_temp.undo(v_l);
  IF pg_temp.standing(v_l) IS DISTINCT FROM '3/true'
     OR (SELECT p.banned_until FROM public.profiles AS p WHERE p.id = v_l) IS DISTINCT FROM v_ban THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the undo did not put back the ban the restore replaced: %', pg_temp.standing(v_l);
  END IF;

  -- M-3: the restore's stamp fails; the restore stands, counted.
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, confirmed_report_count, purge_after)
  VALUES (pg_temp.h('68'), 'opinions', 'opinions_standing', 2, now() + interval '20 days');
  v_before := pg_temp.metric('opinions.restore.unstamped');
  ALTER TABLE private.opinion_enforcement_stamps ADD CONSTRAINT w9d_contract_refuse CHECK (strikes < 0) NOT VALID;
  PERFORM pg_temp.sign_up('68', '68');
  ALTER TABLE private.opinion_enforcement_stamps DROP CONSTRAINT w9d_contract_refuse;
  IF pg_temp.standing(pg_temp.id('68')) IS DISTINCT FROM '2/false'
     OR pg_temp.metric('opinions.restore.unstamped') IS DISTINCT FROM v_before + 1
     OR (SELECT o.stamp_id IS NULL FROM private.opinion_restores AS o WHERE o.user_id = pg_temp.id('68')) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a restore whose stamp failed was lost or not counted: %', pg_temp.standing(pg_temp.id('68'));
  END IF;
END $$;

-- =====================================================================
-- D4. Final fix wave (I-1): the restore runs from Auth's phone
--     confirmation, on every account path (v2 or v1, flow_signin_v2 on or
--     off, a crafted client, a confirmed number change), before the account
--     can post; never at a re-confirmation, a fresh-start placeholder or for
--     a parked account; one log row per restore, all undone together.
-- =====================================================================
DO $$
DECLARE
  v_u uuid;
  v_res jsonb;
  v_err text;
  v_before bigint;
BEGIN
  -- Route 1 (the reviewer's): OTP, record_eula_acceptance, set_my_birth_date,
  -- then complete_sign_up (created:false). The standing is back from the OTP.
  PERFORM pg_temp.carried('79', 3);
  v_u := pg_temp.id('80');
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at) VALUES (v_u, '15558604079', now(), now());
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u, 'role', 'authenticated')::text, true);
  PERFORM public.record_eula_acceptance('2');
  PERFORM public.set_my_birth_date(DATE '1990-01-01');
  v_res := public.complete_sign_up('W9d route 1', DATE '1990-01-01', '2');
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  IF v_res ->> 'created' IS DISTINCT FROM 'false' OR pg_temp.standing(v_u) IS DISTINCT FROM '3/true'
     OR pg_temp.records(pg_temp.h('79')) IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: route 1 (eula, birth date, then complete_sign_up) skipped the restore: %', pg_temp.standing(v_u);
  END IF;

  -- Route 2 (the reviewer's): OTP, then create_opinion straight away, with
  -- no users row, profile or DOB: refused by the restored ban.
  PERFORM pg_temp.carried('81', 3);
  v_u := pg_temp.id('82');
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at) VALUES (v_u, '15558604081', now(), now());
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.create_opinion('W9d route 2: posting at once');
  EXCEPTION WHEN OTHERS THEN
    v_err := SQLERRM;
  END;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  IF v_err IS DISTINCT FROM 'posting_banned' OR EXISTS (SELECT 1 FROM public.opinions WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: route 2 posted before the restore (%)', v_err;
  END IF;

  -- flow_signin_v2 off, the v1 app: Auth makes the user at the OTP request
  -- (unconfirmed), confirms it at verify; the EULA gate and the client's
  -- profile upsert follow. complete_sign_up is never called.
  UPDATE public.feature_flags SET enabled = false WHERE key = 'flow_signin_v2';
  PERFORM pg_temp.carried('83', 3);
  v_u := pg_temp.id('84');
  INSERT INTO auth.users (id, phone, created_at) VALUES (v_u, '15558604083', now());
  IF pg_temp.records(pg_temp.h('83')) IS DISTINCT FROM '3/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unconfirmed number took a record';
  END IF;
  UPDATE auth.users SET phone_confirmed_at = now() WHERE id = v_u;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u, 'role', 'authenticated')::text, true);
  PERFORM public.record_eula_acceptance('2');
  INSERT INTO public.profiles (id, username, bio, avatar_url) VALUES (v_u, NULL, NULL, NULL) ON CONFLICT (id) DO NOTHING;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  IF pg_temp.standing(v_u) IS DISTINCT FROM '3/true' OR pg_temp.records(pg_temp.h('83')) IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the v1 sign-up (flow_signin_v2 off) skipped the restore: %', pg_temp.standing(v_u);
  END IF;

  -- A re-confirmation of the same number (a sign-in) restores nothing.
  v_u := pg_temp.person('85');
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, confirmed_report_count, purge_after)
  VALUES (pg_temp.h('85'), 'opinions', 'opinions_standing', 2, now() + interval '20 days');
  UPDATE auth.users SET phone_confirmed_at = now() WHERE id = v_u;
  IF pg_temp.standing(v_u) IS DISTINCT FROM '0/false' OR pg_temp.records(pg_temp.h('85')) IS DISTINCT FROM '2/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a sign-in''s re-confirmation took a record: %', pg_temp.standing(v_u);
  END IF;

  -- Fresh start: Auth rewrites the old account's number to the +999
  -- placeholder (its parked HMAC already written): it restores nothing.
  v_u := pg_temp.person('86');
  UPDATE public.users SET parked_phone_hmac = pg_temp.h('86') WHERE id = v_u;
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, confirmed_report_count, purge_after)
  VALUES (pg_temp.h('86'), 'opinions', 'opinions_standing', 2, now() + interval '20 days');
  UPDATE auth.users SET phone = '999000000000086', phone_confirmed_at = now() WHERE id = v_u;
  IF pg_temp.standing(v_u) IS DISTINCT FROM '0/false' OR pg_temp.records(pg_temp.h('86')) IS DISTINCT FROM '2/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the fresh-start placeholder took the number''s record: %', pg_temp.standing(v_u);
  END IF;

  -- Parked (W9d-2): a parked account restores nothing, counted.
  UPDATE public.users SET phone_released_at = now() WHERE id = v_u;
  v_before := pg_temp.metric('opinions.restore.parked_skipped');
  PERFORM private.opinion_restore_on_sign_up(v_u);
  IF pg_temp.standing(v_u) IS DISTINCT FROM '0/false' OR pg_temp.records(pg_temp.h('86')) IS DISTINCT FROM '2/false'
     OR pg_temp.metric('opinions.restore.parked_skipped') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a parked account restored, or was not counted';
  END IF;

  -- A confirmed change onto a carried number restores again; one log row
  -- each; the undo takes both back.
  PERFORM pg_temp.carried('87', 1);
  PERFORM pg_temp.sign_up('89', '87');
  PERFORM pg_temp.carried('88', 2);
  UPDATE auth.users SET phone = '15558604088', phone_confirmed_at = now() WHERE id = pg_temp.id('89');
  IF pg_temp.standing(pg_temp.id('89')) IS DISTINCT FROM '2/false' OR pg_temp.records(pg_temp.h('88')) IS DISTINCT FROM ''
     OR (SELECT count(*) FROM private.opinion_restores WHERE user_id = pg_temp.id('89')) IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a confirmed change onto a carried number did not restore and log it: %',
      pg_temp.standing(pg_temp.id('89'));
  END IF;
  PERFORM pg_temp.undo(pg_temp.id('89'));
  IF pg_temp.standing(pg_temp.id('89')) IS DISTINCT FROM '0/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the undo did not take back both restores: %', pg_temp.standing(pg_temp.id('89'));
  END IF;

  -- A restore that fails never refuses Auth's write; counted.
  PERFORM pg_temp.carried('90', 3);
  v_before := pg_temp.metric('opinions.restore.failed');
  ALTER TABLE public.profiles ADD CONSTRAINT w9d_contract_refuse CHECK (confirmed_violation_count < 1) NOT VALID;
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at) VALUES (pg_temp.id('91'), '15558604090', now(), now());
  ALTER TABLE public.profiles DROP CONSTRAINT w9d_contract_refuse;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = pg_temp.id('91'))
     OR pg_temp.records(pg_temp.h('90')) IS DISTINCT FROM '3/true'
     OR pg_temp.metric('opinions.restore.failed') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failing restore refused Auth''s write, took the record or was not counted';
  END IF;
END $$;

-- D5. The trigger never blocks Auth: a restore cancelled by a statement
-- timeout (a slow lock or write inside it) is caught and counted, and the
-- phone confirmation completes.
CREATE FUNCTION public.w9d_contract_slow_profile() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_sleep(2);
  RETURN NEW;
END $$;
CREATE TRIGGER w9d_contract_slow BEFORE INSERT ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.w9d_contract_slow_profile();
DO $$ BEGIN PERFORM pg_temp.carried('92', 3); END $$;
SELECT set_config('w9d.failed_before', pg_temp.metric('opinions.restore.failed')::text, true);
SET LOCAL statement_timeout = '300ms';
INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
VALUES (pg_temp.id('93'), '15558604092', now(), now());
SET LOCAL statement_timeout = 0;
DROP TRIGGER w9d_contract_slow ON public.profiles;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = pg_temp.id('93'))
     OR pg_temp.records(pg_temp.h('92')) IS DISTINCT FROM '3/true'
     OR pg_temp.metric('opinions.restore.failed') IS DISTINCT FROM current_setting('w9d.failed_before')::bigint + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a cancelled restore blocked the phone confirmation, took the record or was not counted';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'opinion_enforcement_records_contracts: all held'; END $$;
ROLLBACK;
