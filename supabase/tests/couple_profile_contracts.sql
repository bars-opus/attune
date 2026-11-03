-- supabase/tests/couple_profile_contracts.sql
-- Spec 1 W5 (§3.8 About us, §4.2, §4.3 W5, §4.4, §7.1): the shared couple
-- profile and the draft before linking: who may read and write, every
-- validation, attribution per field (a first name, never an id), the
-- together signal, the anniversary reminder's single source and its guard,
-- the draft's life (kept through a withdrawal, gone on a switch to Dating,
-- adopted at linking), the export section, and never a type or a score.
-- One BEGIN ... ROLLBACK.
-- Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/couple_profile_contracts.sql
-- Fixture ids 5c0f0000-0000-0000-0000-0000000000NN (relationships
-- 5c0f0000-0000-0000-0000-0000000001NN); phones +15558300NN (§7.1's 83xx
-- range), set on auth.users and public.users. Every refusal is checked by
-- its message.
BEGIN;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ('5c0f0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

CREATE FUNCTION pg_temp.rel(p_n text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ('5c0f0000-0000-0000-0000-0000000001' || p_n)::uuid;
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

-- An account on the Relationship path: a verified Auth phone, a users row
-- named [p_name], a date of birth 30 years ago.
CREATE FUNCTION pg_temp.person(p_n text, p_name text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at)
  VALUES (pg_temp.id(p_n), '+155583000' || p_n, now());
  INSERT INTO public.users (id, phone, display_name, path)
  VALUES (pg_temp.id(p_n), '+155583000' || p_n, p_name, 'relationship');
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (pg_temp.id(p_n), (current_date - interval '30 years')::date);
END $$;

-- A relationship [p_rel] between [p_a] and [p_b] in [p_status].
CREATE FUNCTION pg_temp.couple(p_rel text, p_a text, p_b text, p_status text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.relationships (id, user_a, user_b, status, started_at, invite_accepted_at,
                                    paused_at, paused_by, ended_at, ended_by)
  VALUES (pg_temp.rel(p_rel), pg_temp.id(p_a), pg_temp.id(p_b), p_status, current_date, now(),
          CASE WHEN p_status = 'paused' THEN now() - interval '2 days' END,
          CASE WHEN p_status = 'paused' THEN pg_temp.id(p_a) END,
          CASE WHEN p_status = 'ended' THEN now() - interval '3 days' END,
          CASE WHEN p_status = 'ended' THEN pg_temp.id(p_a) END);
END $$;

-- [p_user]'s update of [p_rel] with [p_patch]: the refusal, or NULL.
CREATE FUNCTION pg_temp.update_error(p_user text, p_rel text, p_patch text) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
  v_msg text;
BEGIN
  PERFORM pg_temp.as_user(pg_temp.id(p_user));
  v_msg := pg_temp.error_of(format('SELECT public.update_couple_profile(%L, %L::jsonb)',
                                   pg_temp.rel(p_rel), p_patch));
  RESET ROLE;
  RETURN v_msg;
END $$;

CREATE FUNCTION pg_temp.read_error(p_user text, p_rel text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_msg text;
BEGIN
  PERFORM pg_temp.as_user(pg_temp.id(p_user));
  v_msg := pg_temp.error_of(format('SELECT public.get_couple_profile(%L)', pg_temp.rel(p_rel)));
  RESET ROLE;
  RETURN v_msg;
END $$;

CREATE FUNCTION pg_temp.update_as(p_user text, p_rel text, p_patch jsonb) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  PERFORM pg_temp.as_user(pg_temp.id(p_user));
  v := public.update_couple_profile(pg_temp.rel(p_rel), p_patch);
  RESET ROLE;
  RETURN v;
END $$;

CREATE FUNCTION pg_temp.read_as(p_user text, p_rel text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  PERFORM pg_temp.as_user(pg_temp.id(p_user));
  v := public.get_couple_profile(pg_temp.rel(p_rel));
  RESET ROLE;
  RETURN v;
END $$;

CREATE FUNCTION pg_temp.draft_as(p_user text, p_patch jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  PERFORM pg_temp.as_user(pg_temp.id(p_user));
  v := CASE WHEN p_patch IS NULL THEN public.get_my_couple_profile_draft()
            ELSE public.update_my_couple_profile_draft(p_patch) END;
  RESET ROLE;
  RETURN v;
END $$;

CREATE FUNCTION pg_temp.draft_error(p_user text, p_patch text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_msg text;
BEGIN
  PERFORM pg_temp.as_user(pg_temp.id(p_user));
  v_msg := pg_temp.error_of(CASE WHEN p_patch IS NULL THEN 'SELECT public.get_my_couple_profile_draft()'
                                 ELSE format('SELECT public.update_my_couple_profile_draft(%L::jsonb)', p_patch) END);
  RESET ROLE;
  RETURN v_msg;
END $$;

CREATE FUNCTION pg_temp.signal(p_rel text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce((SELECT s.version FROM public.together_change_signals AS s
                    WHERE s.relationship_id = pg_temp.rel(p_rel)), 0);
$$;

CREATE FUNCTION pg_temp.flag(p_key text, p_on boolean) RETURNS void LANGUAGE sql AS $$
  UPDATE public.feature_flags SET enabled = p_on WHERE key = p_key;
$$;

-- =====================================================================
-- A. Objects, grants, RLS, and never a type or a score (spec §7.1): the
--    exact columns, the only functions that read couple_profiles, no
--    view over it, not in the Realtime publication.
-- =====================================================================
DO $$
DECLARE
  v_cols text;
  v_bad text;
BEGIN
  IF to_regclass('public.couple_profiles') IS NULL OR to_regclass('public.couple_profile_drafts') IS NULL
     OR to_regprocedure('public.get_couple_profile(uuid)') IS NULL
     OR to_regprocedure('public.update_couple_profile(uuid,jsonb)') IS NULL
     OR to_regprocedure('public.get_my_couple_profile_draft()') IS NULL
     OR to_regprocedure('public.update_my_couple_profile_draft(jsonb)') IS NULL
     OR to_regprocedure('public.adopt_couple_profile_drafts(uuid,uuid,uuid)') IS NULL
     OR to_regprocedure('public.sync_anniversary_reminder(uuid)') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W5 objects are missing';
  END IF;

  SELECT string_agg(c.column_name, ',' ORDER BY c.column_name) INTO v_cols
    FROM information_schema.columns AS c
   WHERE c.table_schema = 'public' AND c.table_name = 'couple_profiles';
  IF v_cols IS DISTINCT FROM
     'anniversary_changed_at,anniversary_changed_by,anniversary_reminder_id,anniversary_source,'
     'ceremonies,ceremonies_changed_at,ceremonies_changed_by,child_age_bands,children,'
     'children_changed_at,children_changed_by,living,living_changed_at,living_changed_by,'
     'relationship_id,stage,stage_changed_at,stage_changed_by,stage_words,together_since,'
     'together_since_changed_at,together_since_changed_by,together_since_precision,updated_at' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: couple_profiles has columns beyond the spec (never a type or score): %', v_cols;
  END IF;

  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_bad
    FROM pg_proc AS p
   WHERE p.prosrc ~ '\mcouple_profiles\M'
     AND p.oid NOT IN ('public.get_couple_profile(uuid)'::regprocedure,
                       'public.update_couple_profile(uuid,jsonb)'::regprocedure,
                       'public.adopt_couple_profile_drafts(uuid,uuid,uuid)'::regprocedure,
                       'public.sync_anniversary_reminder(uuid)'::regprocedure,
                       'public.export_relationship(uuid,uuid)'::regprocedure,
                       'private.guard_about_us_reminder()'::regprocedure);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a function outside the allow-list reads couple_profiles (never a type or score): %', v_bad;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_views WHERE definition ~ '\mcouple_profiles\M')
     OR EXISTS (SELECT 1 FROM pg_matviews WHERE definition ~ '\mcouple_profiles\M') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a view selects from couple_profiles';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_publication_tables
              WHERE tablename IN ('couple_profiles', 'couple_profile_drafts')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: About us is in a Realtime publication (the together signal is)';
  END IF;

  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.couple_profiles'::regclass)
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.couple_profile_drafts'::regclass) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: RLS is off on an About us table';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.couple_profiles', 'SELECT')
     OR has_table_privilege('authenticated', 'public.couple_profiles', 'INSERT')
     OR has_table_privilege('authenticated', 'public.couple_profiles', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.couple_profiles', 'DELETE')
     OR has_table_privilege('anon', 'public.couple_profiles', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.couple_profile_drafts', 'SELECT')
     OR has_table_privilege('authenticated', 'public.couple_profile_drafts', 'INSERT')
     OR has_table_privilege('authenticated', 'public.couple_profile_drafts', 'UPDATE')
     OR has_table_privilege('anon', 'public.couple_profile_drafts', 'SELECT')
     OR NOT has_table_privilege('service_role', 'public.couple_profiles', 'INSERT')
     OR NOT has_table_privilege('service_role', 'public.couple_profile_drafts', 'DELETE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: About us table grants are wrong';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.get_couple_profile(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.update_couple_profile(uuid,jsonb)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_my_couple_profile_draft()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.update_my_couple_profile_draft(jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.get_couple_profile(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.update_couple_profile(uuid,jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.update_my_couple_profile_draft(jsonb)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.adopt_couple_profile_drafts(uuid,uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.adopt_couple_profile_drafts(uuid,uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.sync_anniversary_reminder(uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.sync_anniversary_reminder(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.couple_profile_merge(jsonb,jsonb)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.couple_profile_change(uuid,uuid,timestamptz)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.couple_profile_ceremony_date(jsonb)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.guard_about_us_reminder()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: About us function grants are wrong';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'couple_profiles_together_signal'
                    AND tgrelid = 'public.couple_profiles'::regclass)
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'reminders_guard_about_us'
                       AND tgrelid = 'public.reminders'::regclass) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the together signal or the reminder guard trigger is missing';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc AS p
              WHERE p.oid IN ('public.get_couple_profile(uuid)'::regprocedure,
                              'public.update_couple_profile(uuid,jsonb)'::regprocedure,
                              'public.get_my_couple_profile_draft()'::regprocedure,
                              'public.update_my_couple_profile_draft(jsonb)'::regprocedure,
                              'public.adopt_couple_profile_drafts(uuid,uuid,uuid)'::regprocedure,
                              'public.sync_anniversary_reminder(uuid)'::regprocedure)
                AND (NOT p.prosecdef OR p.proconfig IS DISTINCT FROM ARRAY['search_path=""'])) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an About us function is not SECURITY DEFINER with search_path ''''';
  END IF;
END $$;

-- =====================================================================
-- B. Who reads: both members; never an outsider, a sealed side, an
--    archived chapter or one past its window; paused and the window
--    read-only. Fixtures 01-14.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_msg text;
  v_n int;
BEGIN
  PERFORM pg_temp.person('01', 'Yaw Mensah');
  PERFORM pg_temp.person('02', 'Ama Owusu');
  PERFORM pg_temp.person('03', 'Kofi Outsider');
  PERFORM pg_temp.person('04', 'Abena Paused');
  PERFORM pg_temp.person('05', 'Kwame Paused');
  PERFORM pg_temp.person('06', 'Esi Ended');
  PERFORM pg_temp.person('07', 'Kojo Ended');
  PERFORM pg_temp.person('08', 'Adjoa Sealed');
  PERFORM pg_temp.person('09', 'Nana Sealed');
  PERFORM pg_temp.person('10', 'Efua Archived');
  PERFORM pg_temp.person('11', 'Yaa Archived');
  PERFORM pg_temp.person('12', 'Akua Late');
  PERFORM pg_temp.person('13', 'Kwesi Late');
  PERFORM pg_temp.couple('01', '01', '02', 'active');
  PERFORM pg_temp.couple('02', '04', '05', 'paused');
  PERFORM pg_temp.couple('03', '06', '07', 'ended');
  PERFORM pg_temp.couple('04', '08', '09', 'ended');
  INSERT INTO public.relationship_seals (relationship_id, user_id) VALUES (pg_temp.rel('04'), pg_temp.id('08'));
  PERFORM pg_temp.couple('05', '10', '11', 'archived');
  UPDATE public.relationships SET chat_archived_at = now(), chat_archived_reason = 'manual_end',
         ended_at = now() - interval '1 day', ended_by = pg_temp.id('10')
   WHERE id = pg_temp.rel('05');
  PERFORM pg_temp.couple('06', '12', '13', 'ended');
  UPDATE public.relationships SET ended_at = now() - interval '31 days' WHERE id = pg_temp.rel('06');

  v := pg_temp.read_as('01', '01');
  IF (v->>'read_only')::boolean OR v->>'anniversary_source' <> 'off' OR v->'ceremonies' <> '[]'::jsonb
     OR v->'child_age_bands' <> '[]'::jsonb OR v->'changes' <> '{}'::jsonb OR (v->>'draft')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an empty profile reads wrongly: %', v;
  END IF;
  IF v ? 'suggested_dates' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_couple_profile carries suggested_dates (review I-12)';
  END IF;
  IF pg_temp.read_error('02', '01') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the other member cannot read the profile';
  END IF;
  v_msg := pg_temp.read_error('03', '01');
  IF v_msg IS DISTINCT FROM 'couple_profile:not_found' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider read the profile (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.update_error('03', '01', '{"living":"together"}');
  IF v_msg IS DISTINCT FROM 'couple_profile:not_found' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider wrote the profile (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- Paused and inside the ending window: read, never written.
  v := pg_temp.read_as('04', '02');
  IF NOT (v->>'read_only')::boolean OR (v->>'read_until')::timestamptz IS NULL
     OR abs(extract(epoch FROM (v->>'read_until')::timestamptz - (now() + interval '28 days'))) > 60 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused profile is not read-only until the pause ends: %', v;
  END IF;
  v_msg := pg_temp.update_error('05', '02', '{"living":"together"}');
  IF v_msg IS DISTINCT FROM 'couple_profile:read_only' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused profile was written (got %)', coalesce(v_msg, 'no error');
  END IF;
  v := pg_temp.read_as('07', '03');
  IF NOT (v->>'read_only')::boolean
     OR abs(extract(epoch FROM (v->>'read_until')::timestamptz - (now() + interval '27 days'))) > 60 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the ending window is not read-only until its end: %', v;
  END IF;
  v_msg := pg_temp.update_error('06', '03', '{"living":"together"}');
  IF v_msg IS DISTINCT FROM 'couple_profile:read_only' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a profile in the ending window was written (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- Sealed (that side only), archived, past the window: gone.
  v_msg := pg_temp.read_error('08', '04');
  IF v_msg IS DISTINCT FROM 'couple_profile:not_found' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a sealed side read the profile (got %)', coalesce(v_msg, 'no error');
  END IF;
  IF pg_temp.read_error('09', '04') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the unsealed side lost the profile in the window';
  END IF;
  v_msg := pg_temp.read_error('10', '05');
  IF v_msg IS DISTINCT FROM 'couple_profile:not_found' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an archived chapter''s profile was read (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.read_error('12', '06');
  IF v_msg IS DISTINCT FROM 'couple_profile:not_found' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a profile past its window was read (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- RLS on the table itself: members while open, nobody else.
  INSERT INTO public.couple_profiles (relationship_id, living) VALUES (pg_temp.rel('05'), 'together');
  PERFORM pg_temp.as_user(pg_temp.id('03'));
  SELECT count(*) INTO v_n FROM public.couple_profiles WHERE relationship_id IN (pg_temp.rel('01'), pg_temp.rel('05'));
  RESET ROLE;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider selected a couple_profiles row';
  END IF;
  PERFORM pg_temp.as_user(pg_temp.id('10'));
  SELECT count(*) INTO v_n FROM public.couple_profiles WHERE relationship_id = pg_temp.rel('05');
  RESET ROLE;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an archived chapter''s row is selectable';
  END IF;
  PERFORM pg_temp.as_user(pg_temp.id('01'));
  v_msg := pg_temp.error_of(format('UPDATE public.couple_profiles SET stage = ''married'' WHERE relationship_id = %L', pg_temp.rel('01')));
  RESET ROLE;
  IF v_msg IS NULL OR v_msg NOT LIKE 'permission denied%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a member updated couple_profiles directly (got %)', coalesce(v_msg, 'no error');
  END IF;
END $$;

-- =====================================================================
-- C. Every validation (spec §3.8 AU1-AU6, §4.3 W5): each refusal by its
--    message, and the normal forms. Relationship 01 (Yaw 01, Ama 02).
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_msg text;
  r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('{"mood":"great"}', 'couple_profile:unknown_key'),
    ('{"score":5}', 'couple_profile:unknown_key'),
    ('[1,2]', 'couple_profile:invalid'),
    ('{"together_since":"2024-10-14"}', 'couple_profile:invalid'),
    ('{"together_since_precision":"day"}', 'couple_profile:invalid'),
    ('{"together_since":"2024-10-14","together_since_precision":"week"}', 'couple_profile:invalid'),
    ('{"together_since":"14/10/2024","together_since_precision":"day"}', 'couple_profile:invalid'),
    ('{"together_since":"2023-02-30","together_since_precision":"day"}', 'couple_profile:invalid'),
    ('{"together_since":"1899-12-31","together_since_precision":"day"}', 'couple_profile:invalid'),
    ('{"together_since":"2999-01-01","together_since_precision":"year"}', 'couple_profile:future_date'),
    ('{"stage":"situationship"}', 'couple_profile:invalid'),
    ('{"stage":"other","stage_words":"' || repeat('a', 41) || '"}', 'couple_profile:invalid'),
    -- The couple's own words are a string or nothing (batch 1 review Minor 3).
    ('{"stage":"other","stage_words":5}', 'couple_profile:invalid'),
    ('{"stage":"other","stage_words":["Courting"]}', 'couple_profile:invalid'),
    ('{"stage":"other","stage_words":{"w":"Courting"}}', 'couple_profile:invalid'),
    ('{"stage":"other","stage_words":true}', 'couple_profile:invalid'),
    ('{"living":"elsewhere"}', 'couple_profile:invalid'),
    ('{"children":"three"}', 'couple_profile:invalid'),
    ('{"children":"yes","child_age_bands":["teen"]}', 'couple_profile:invalid'),
    ('{"children":"no","child_age_bands":["2to5"]}', 'couple_profile:invalid'),
    ('{"children":"none","child_age_bands":["2to5"]}', 'couple_profile:bands_need_yes'),
    ('{"child_age_bands":["2to5"]}', 'couple_profile:bands_need_yes'),
    ('{"ceremonies":[{"year":1999}]}', 'couple_profile:ceremonies_need_married'),
    ('{"stage":"engaged","ceremonies":[{"year":1999}]}', 'couple_profile:ceremonies_need_married'),
    ('{"stage":"married","ceremonies":[{"year":1999},{"year":2000},{"year":2001}]}', 'couple_profile:too_many_ceremonies'),
    ('{"stage":"married","ceremonies":[{"year":"1999"}]}', 'couple_profile:invalid'),
    ('{"stage":"married","ceremonies":[{"year":1999,"month":13}]}', 'couple_profile:invalid'),
    ('{"stage":"married","ceremonies":[{"year":1999,"day":4}]}', 'couple_profile:invalid'),
    ('{"stage":"married","ceremonies":[{"year":2001,"month":2,"day":29}]}', 'couple_profile:invalid'),
    ('{"stage":"married","ceremonies":[{"year":1999,"label":"beach"}]}', 'couple_profile:invalid'),
    ('{"stage":"married","ceremonies":[{"year":1999,"guests":200}]}', 'couple_profile:invalid'),
    ('{"stage":"married","ceremonies":[{"year":2999}]}', 'couple_profile:future_date'),
    ('{"anniversary_source":"first_kiss"}', 'couple_profile:invalid'),
    ('{"anniversary_source":"ceremony_1"}', 'couple_profile:invalid'),
    ('{"anniversary_source":"together_since"}', 'couple_profile:anniversary_needs_day'),
    ('{"together_since":"2024-10-01","together_since_precision":"month","anniversary_source":"together_since"}', 'couple_profile:anniversary_needs_day'),
    ('{"stage":"married","ceremonies":[{"year":1999,"month":4}],"anniversary_source":"ceremony_1"}', 'couple_profile:anniversary_needs_day')
  ) AS t(patch, expected) LOOP
    v_msg := pg_temp.update_error('01', '01', r.patch);
    IF v_msg IS DISTINCT FROM r.expected THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % answered % (expected %)', r.patch, coalesce(v_msg, 'no error'), r.expected;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.couple_profiles WHERE relationship_id = pg_temp.rel('01')
                AND (stage IS NOT NULL OR living IS NOT NULL OR together_since IS NOT NULL)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused patch wrote something';
  END IF;

  -- Normal forms: a month is its 1st, a year 1 January; the couple's own
  -- words only with "Something else" (trimmed); bands in order, once.
  v := pg_temp.update_as('01', '01', '{"together_since":"2024-10-19","together_since_precision":"month"}');
  IF v->>'together_since' <> '2024-10-01' OR v->>'together_since_precision' <> 'month' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a month was not kept as its 1st: %', v;
  END IF;
  v := pg_temp.update_as('01', '01', '{"together_since":"2019-06-19","together_since_precision":"year"}');
  IF v->>'together_since' <> '2019-01-01' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a year was not kept as 1 January: %', v;
  END IF;
  v := pg_temp.update_as('01', '01', '{"stage":"other","stage_words":"  Courting, with both families  "}');
  IF v->>'stage_words' <> 'Courting, with both families' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the couple''s own words were not trimmed: %', v;
  END IF;
  v := pg_temp.update_as('01', '01', '{"stage":"engaged"}');
  IF v->'stage_words' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: own words stayed after leaving "Something else": %', v;
  END IF;
  v := pg_temp.update_as('01', '01', '{"stage":"engaged","stage_words":"ignored"}');
  IF v->'stage_words' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: own words were kept without "Something else": %', v;
  END IF;
  v := pg_temp.update_as('01', '01', '{"children":"yes","child_age_bands":["18plus","13to17","18plus"]}');
  IF v->'child_age_bands' <> '["13to17","18plus"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: age bands not ordered once: %', v;
  END IF;
  v := pg_temp.update_as('01', '01', '{"children":"prefer_not_to_say"}');
  IF v->'child_age_bands' <> '[]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: age bands stayed after leaving "Yes": %', v;
  END IF;
  -- Today is never the future (a day of slack for the earliest zone).
  v := pg_temp.update_as('01', '01', jsonb_build_object('together_since', current_date + 1, 'together_since_precision', 'day'));
  IF (v->>'together_since')::date <> current_date + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: tomorrow in UTC (today in UTC+14) was refused: %', v;
  END IF;
  v_msg := pg_temp.update_error('01', '01', jsonb_build_object('together_since', current_date + 2, 'together_since_precision', 'day')::text);
  IF v_msg IS DISTINCT FROM 'couple_profile:future_date' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two days ahead was not a future date (got %)', coalesce(v_msg, 'no error');
  END IF;
  -- Cleared: a date set to null takes its precision with it.
  v := pg_temp.update_as('01', '01', '{"together_since":null}');
  IF v->'together_since' <> 'null'::jsonb OR v->'together_since_precision' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clearing the date kept its precision: %', v;
  END IF;
END $$;

-- =====================================================================
-- D. Attribution per field (a first name, never an id), the together
--    signal, and leaving Married (attributed). Relationship 01.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_signal bigint;
  v_at timestamptz;
BEGIN
  UPDATE public.couple_profiles SET stage = NULL, stage_words = NULL, living = NULL,
         stage_changed_by = NULL, stage_changed_at = NULL, living_changed_by = NULL, living_changed_at = NULL
   WHERE relationship_id = pg_temp.rel('01');
  v_signal := pg_temp.signal('01');
  v := pg_temp.update_as('01', '01', '{"stage":"married","ceremonies":[{"year":1999,"label":"customary"},{"year":2004,"month":8,"day":14,"label":"church"}]}');
  IF pg_temp.signal('01') <= v_signal THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an edit did not bump the together signal';
  END IF;
  PERFORM pg_temp.update_as('02', '01', '{"living":"apart_nearby"}');

  v := pg_temp.read_as('02', '01');
  IF v->'changes'->'stage'->>'changed_by_first_name' IS DISTINCT FROM 'Yaw'
     OR (v->'changes'->'stage'->>'changed_by_me')::boolean
     OR NOT (v->'changes'->'living'->>'changed_by_me')::boolean
     OR v->'changes'->'living' ? 'changed_by_first_name'
     OR v->'changes'->'ceremonies'->>'changed_by_first_name' IS DISTINCT FROM 'Yaw'
     OR (v->'changes'->'living'->>'changed_at')::timestamptz IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: attribution per field reads wrongly for Ama: %', v->'changes';
  END IF;
  v := pg_temp.read_as('01', '01');
  IF NOT (v->'changes'->'stage'->>'changed_by_me')::boolean
     OR v->'changes'->'living'->>'changed_by_first_name' IS DISTINCT FROM 'Ama' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: attribution per field reads wrongly for Yaw: %', v->'changes';
  END IF;
  IF v::text LIKE '%' || pg_temp.id('01') || '%' OR v::text LIKE '%' || pg_temp.id('02') || '%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_couple_profile carries a member id';
  END IF;

  -- A first name, never a phone number written as a name.
  UPDATE public.users SET display_name = '+233 24 000 0000' WHERE id = pg_temp.id('01');
  v := pg_temp.read_as('02', '01');
  IF v->'changes'->'stage' ? 'changed_by_first_name' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a phone number was shown as a name: %', v->'changes'->'stage';
  END IF;
  UPDATE public.users SET display_name = 'Yaw Mensah' WHERE id = pg_temp.id('01');

  -- Changing one field leaves every other field's attribution alone.
  PERFORM pg_temp.update_as('01', '01', '{"children":"none"}');
  IF (SELECT living_changed_by FROM public.couple_profiles WHERE relationship_id = pg_temp.rel('01')) <> pg_temp.id('02')
     OR (SELECT children_changed_by FROM public.couple_profiles WHERE relationship_id = pg_temp.rel('01')) <> pg_temp.id('01') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an edit of one field re-attributed another';
  END IF;

  -- A patch that changes nothing changes no attribution and bumps nothing.
  v_at := (SELECT living_changed_at FROM public.couple_profiles WHERE relationship_id = pg_temp.rel('01'));
  v_signal := pg_temp.signal('01');
  PERFORM pg_temp.update_as('01', '01', '{"living":"apart_nearby"}');
  IF (SELECT living_changed_by FROM public.couple_profiles WHERE relationship_id = pg_temp.rel('01')) <> pg_temp.id('02')
     OR (SELECT living_changed_at FROM public.couple_profiles WHERE relationship_id = pg_temp.rel('01')) <> v_at
     OR pg_temp.signal('01') <> v_signal THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a no-op patch moved the attribution or the signal';
  END IF;

  -- Leaving Married clears the ceremonies, attributed to who left it.
  v := pg_temp.update_as('02', '01', '{"stage":"engaged"}');
  IF v->'ceremonies' <> '[]'::jsonb
     OR NOT (SELECT ceremonies_changed_by = pg_temp.id('02') FROM public.couple_profiles
              WHERE relationship_id = pg_temp.rel('01')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: leaving Married did not clear the ceremonies, attributed: %', v;
  END IF;
END $$;

-- =====================================================================
-- E. The anniversary reminder: one source, created, moved, deleted;
--    and the guard. Relationship 01.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_id uuid;
  v_rem public.reminders%ROWTYPE;
  v_msg text;
  v_other uuid;
  r record;
BEGIN
  v := pg_temp.update_as('01', '01', '{"together_since":"2016-03-12","together_since_precision":"day","anniversary_source":"together_since"}');
  v_id := (v->>'anniversary_reminder_id')::uuid;
  SELECT * INTO v_rem FROM public.reminders WHERE id = v_id;
  IF v_id IS NULL OR v_rem.reminder_type <> 'anniversary' OR v_rem.title <> 'Anniversary'
     OR v_rem.recurrence <> 'yearly' OR v_rem.created_by <> pg_temp.id('01')
     OR v_rem.relationship_id <> pg_temp.rel('01')
     OR v_rem.remind_at <> (public.reminder_next_on(date '2016-03-12', 'yearly', (now() AT TIME ZONE 'utc')::date)::text
                            || ' 00:00:00+00')::timestamptz THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the anniversary reminder is not the next 12 March, yearly, by Yaw: %', row_to_json(v_rem);
  END IF;
  IF (SELECT count(*) FROM public.reminders WHERE relationship_id = pg_temp.rel('01')) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: more than one reminder for one anniversary';
  END IF;

  -- Moved with its date, the same row.
  PERFORM pg_temp.update_as('02', '01', '{"together_since":"2016-07-02","together_since_precision":"day"}');
  IF (SELECT (remind_at AT TIME ZONE 'utc')::date FROM public.reminders WHERE id = v_id)
     <> public.reminder_next_on(date '2016-07-02', 'yearly', (now() AT TIME ZONE 'utc')::date) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the reminder did not follow the date';
  END IF;
  -- A date without its day while the reminder is on it: refused.
  v_msg := pg_temp.update_error('02', '01', '{"together_since":"2016-07-01","together_since_precision":"month"}');
  IF v_msg IS DISTINCT FROM 'couple_profile:anniversary_needs_day' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the anniversary''s date lost its day (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- The guard (plan P-6): the app can't move or delete it; lead times stay
  -- the couple's; any other reminder is untouched by the guard.
  PERFORM pg_temp.as_user(pg_temp.id('02'));
  v_msg := pg_temp.error_of(format('DELETE FROM public.reminders WHERE id = %L', v_id));
  IF v_msg IS DISTINCT FROM 'reminder:follows_about_us' THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: the app deleted the About us reminder (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.error_of(format('UPDATE public.reminders SET remind_at = now() WHERE id = %L', v_id));
  IF v_msg IS DISTINCT FROM 'reminder:follows_about_us' THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: the app moved the About us reminder (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.error_of(format('UPDATE public.reminders SET remind_days_before = ARRAY[0, 7] WHERE id = %L', v_id));
  IF v_msg IS NOT NULL THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: the couple''s lead times were refused (%)', v_msg;
  END IF;
  -- Every other field the reminder takes from About us is guarded too: an
  -- older build's ordinary reminder sheet renames it or changes its type
  -- (batch 1 review Minor 2). The note stays the couple's.
  FOR r IN SELECT * FROM (VALUES
    ('title', '''Ours'''),
    ('reminder_type', '''custom'''),
    ('recurrence', '''none'''),
    ('created_by', quote_literal(pg_temp.id('02')))
  ) AS t(col, val) LOOP
    v_msg := pg_temp.error_of(format('UPDATE public.reminders SET %I = %s WHERE id = %L', r.col, r.val, v_id));
    IF v_msg IS DISTINCT FROM 'reminder:follows_about_us' THEN
      RESET ROLE;
      RAISE EXCEPTION 'CONTRACT VIOLATED: the app changed the About us reminder''s % (got %)', r.col, coalesce(v_msg, 'no error');
    END IF;
  END LOOP;
  v_msg := pg_temp.error_of(format('UPDATE public.reminders SET note = ''x'' WHERE id = %L', v_id));
  IF v_msg IS NOT NULL THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: the couple''s note on the About us reminder was refused (%)', v_msg;
  END IF;
  INSERT INTO public.reminders (relationship_id, created_by, reminder_type, title, remind_at, recurrence)
  VALUES (pg_temp.rel('01'), pg_temp.id('02'), 'birthday', 'Mum', now() + interval '10 days', 'yearly')
  RETURNING id INTO v_other;
  v_msg := pg_temp.error_of(format('DELETE FROM public.reminders WHERE id = %L', v_other));
  RESET ROLE;
  IF v_msg IS NOT NULL OR EXISTS (SELECT 1 FROM public.reminders WHERE id = v_other) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the guard stopped an ordinary reminder''s delete (%)', v_msg;
  END IF;

  -- A ceremony as the source moves the same reminder; leaving Married
  -- takes it with the ceremonies (anniversary off, attributed).
  PERFORM pg_temp.update_as('01', '01', '{"stage":"married","ceremonies":[{"year":2018,"month":12,"day":1,"label":"civil"}],"anniversary_source":"ceremony_1"}');
  IF (SELECT (remind_at AT TIME ZONE 'utc')::date FROM public.reminders WHERE id = v_id)
     <> public.reminder_next_on(date '2018-12-01', 'yearly', (now() AT TIME ZONE 'utc')::date) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the reminder did not move to the ceremony';
  END IF;
  v := pg_temp.update_as('02', '01', '{"stage":"dating"}');
  IF v->>'anniversary_source' <> 'off' OR v->'anniversary_reminder_id' <> 'null'::jsonb
     OR EXISTS (SELECT 1 FROM public.reminders WHERE id = v_id)
     OR v->'changes'->'anniversary'->>'changed_by_first_name' IS DISTINCT FROM NULL
     OR NOT (v->'changes'->'anniversary'->>'changed_by_me')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: leaving Married left the ceremony''s anniversary: %', v;
  END IF;

  -- On again, then "No, thanks": deleted.
  v := pg_temp.update_as('01', '01', '{"anniversary_source":"together_since"}');
  v_id := (v->>'anniversary_reminder_id')::uuid;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the anniversary did not come back';
  END IF;
  v := pg_temp.update_as('01', '01', '{"anniversary_source":"off"}');
  IF EXISTS (SELECT 1 FROM public.reminders WHERE id = v_id) OR v->'anniversary_reminder_id' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: "No, thanks" left the reminder';
  END IF;
END $$;

-- =====================================================================
-- F. The draft (spec §4.2, §4.3 W5): own, Relationship path only, the
--    same validation; kept through a withdrawal; gone on a switch to
--    Dating, kept on Just for me. Fixtures 21-24.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_msg text;
  v_n int;
BEGIN
  PERFORM pg_temp.person('21', 'Kojo Inviter');
  PERFORM pg_temp.person('22', 'Efua Other');
  PERFORM pg_temp.person('23', 'Yaa JustMe');
  UPDATE public.users SET path = 'just_me' WHERE id = pg_temp.id('23');
  INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at)
  VALUES (pg_temp.rel('21'), pg_temp.id('21'), 'pending', 'W5DRF1', now() + interval '7 days');

  v := pg_temp.draft_as('21', NULL);
  IF NOT (v->>'draft')::boolean OR v->>'anniversary_source' <> 'off' OR v->'changes' <> '{}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an empty draft reads wrongly: %', v;
  END IF;
  v := pg_temp.draft_as('21', '{"stage":"engaged","living":"long_distance"}');
  IF v->>'stage' <> 'engaged' OR v->>'living' <> 'long_distance' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the draft did not save: %', v;
  END IF;
  v_msg := pg_temp.draft_error('21', '{"ceremonies":[{"year":1999}]}');
  IF v_msg IS DISTINCT FROM 'couple_profile:ceremonies_need_married' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the draft skipped the profile''s validation (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.draft_error('21', '{"favourite":"x"}');
  IF v_msg IS DISTINCT FROM 'couple_profile:unknown_key' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the draft took an unknown key (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.draft_error('23', '{"stage":"dating"}');
  IF v_msg IS DISTINCT FROM 'couple_profile:not_relationship' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a Just-for-me account wrote a draft (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- Review F-2: nobody in an active or paused relationship has a draft (an
  -- answer queued before linking and replayed after it is refused, never
  -- kept for a later link); an ended one may start again. Section B's
  -- fixtures: Yaw 01 (active), Abena 04 and Kwame 05 (paused), Kojo 07
  -- (ended, inside the window).
  FOR v_msg IN SELECT unnest(ARRAY[pg_temp.draft_error('01', NULL),
                                   pg_temp.draft_error('01', '{"living":"together"}'),
                                   pg_temp.draft_error('04', NULL),
                                   pg_temp.draft_error('05', '{"stage":"dating"}')]) LOOP
    IF v_msg IS DISTINCT FROM 'couple_profile:not_found' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a linked account used a draft (F-2) (got %)', coalesce(v_msg, 'no error');
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.couple_profile_drafts
              WHERE user_id IN (pg_temp.id('01'), pg_temp.id('04'), pg_temp.id('05'))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a linked account''s draft row was written (F-2)';
  END IF;
  v_msg := pg_temp.draft_error('07', NULL);
  IF v_msg IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ended relationship blocked a new draft (F-2 is active or paused only) (got %)', v_msg;
  END IF;

  -- The shared-phone rule: nobody reads another account's draft.
  v := pg_temp.draft_as('22', NULL);
  IF v->>'stage' IS NOT NULL OR v->>'living' IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another account read Kojo''s draft through the RPC';
  END IF;
  PERFORM pg_temp.as_user(pg_temp.id('22'));
  SELECT count(*) INTO v_n FROM public.couple_profile_drafts WHERE user_id = pg_temp.id('21');
  RESET ROLE;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another account selected Kojo''s draft row';
  END IF;
  PERFORM pg_temp.as_user(pg_temp.id('21'));
  SELECT count(*) INTO v_n FROM public.couple_profile_drafts WHERE user_id = pg_temp.id('21');
  RESET ROLE;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner cannot select their own draft row';
  END IF;

  -- Kept through a withdrawal (the code goes, the answers stay).
  PERFORM pg_temp.as_user(pg_temp.id('21'));
  PERFORM public.withdraw_my_pending_invites();
  RESET ROLE;
  IF NOT EXISTS (SELECT 1 FROM public.couple_profile_drafts WHERE user_id = pg_temp.id('21') AND stage = 'engaged') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: withdrawing the invite deleted the draft';
  END IF;

  -- A switch to Just for me keeps it (unreadable until Relationship again);
  -- a switch to Dating deletes it (review I-6).
  PERFORM public.set_user_path_internal(pg_temp.id('21'), 'just_me');
  IF NOT EXISTS (SELECT 1 FROM public.couple_profile_drafts WHERE user_id = pg_temp.id('21')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a switch to Just for me deleted the draft';
  END IF;
  v_msg := pg_temp.draft_error('21', NULL);
  IF v_msg IS DISTINCT FROM 'couple_profile:not_relationship' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the draft was readable off the Relationship path (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM public.set_user_path_internal(pg_temp.id('21'), 'dating');
  IF EXISTS (SELECT 1 FROM public.couple_profile_drafts WHERE user_id = pg_temp.id('21')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a switch to Dating kept the draft (I-6)';
  END IF;
END $$;

-- =====================================================================
-- G. Adoption at linking (spec §3.8 R4): the inviter's draft first, the
--    acceptor's fills what is empty, each field keeps its owner and its
--    time; dependent fields that no longer hold are dropped; both drafts
--    go; the anniversary reminder is made. Fixtures 31-36.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_row public.couple_profiles%ROWTYPE;
  v_set timestamptz;
  v_since_set timestamptz;
  v_living_set timestamptz;
  v_children_set timestamptz;
  v_ann_set timestamptz;
  v_msg text;
BEGIN
  PERFORM pg_temp.flag('flow_signin_v2', false);
  PERFORM pg_temp.person('31', 'Yaw Inviter');
  PERFORM pg_temp.person('32', 'Ama Acceptor');
  INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at)
  VALUES (pg_temp.rel('31'), pg_temp.id('31'), 'pending', 'W5ADP1', now() + interval '7 days');
  PERFORM pg_temp.draft_as('31', '{"stage":"engaged","together_since":"2020-02-14","together_since_precision":"day","anniversary_source":"together_since"}');
  v_set := (SELECT stage_set_at FROM public.couple_profile_drafts WHERE user_id = pg_temp.id('31'));
  -- The acceptor's draft: a stage (the inviter's wins), ceremonies (dropped:
  -- the stage is Engaged), where they live and children (filled).
  PERFORM pg_temp.draft_as('32', '{"stage":"married","ceremonies":[{"year":2021}],"living":"together","children":"yes","child_age_bands":["under2"]}');
  -- Each field keeps its owner's time (batch 1 review Info 7). One
  -- transaction has one now(), so the drafts' times are set apart first.
  UPDATE public.couple_profile_drafts
     SET together_since_set_at = now() - interval '6 days', stage_set_at = now() - interval '5 days',
         anniversary_set_at = now() - interval '4 days'
   WHERE user_id = pg_temp.id('31');
  UPDATE public.couple_profile_drafts
     SET stage_set_at = now() - interval '9 days', ceremonies_set_at = now() - interval '9 days',
         living_set_at = now() - interval '3 days', children_set_at = now() - interval '2 days'
   WHERE user_id = pg_temp.id('32');
  v_set := (SELECT stage_set_at FROM public.couple_profile_drafts WHERE user_id = pg_temp.id('31'));
  v_since_set := (SELECT together_since_set_at FROM public.couple_profile_drafts WHERE user_id = pg_temp.id('31'));
  v_ann_set := (SELECT anniversary_set_at FROM public.couple_profile_drafts WHERE user_id = pg_temp.id('31'));
  SELECT living_set_at, children_set_at INTO v_living_set, v_children_set
    FROM public.couple_profile_drafts WHERE user_id = pg_temp.id('32');

  v := public.accept_relationship_invite_v2(pg_temp.id('32'), 'W5ADP1');
  SELECT * INTO v_row FROM public.couple_profiles WHERE relationship_id = pg_temp.rel('31');
  IF NOT FOUND OR v_row.stage IS DISTINCT FROM 'engaged' OR v_row.stage_changed_by IS DISTINCT FROM pg_temp.id('31')
     OR v_row.stage_changed_at IS DISTINCT FROM v_set
     OR v_row.together_since IS DISTINCT FROM date '2020-02-14' OR v_row.together_since_changed_by IS DISTINCT FROM pg_temp.id('31')
     OR v_row.living IS DISTINCT FROM 'together' OR v_row.living_changed_by IS DISTINCT FROM pg_temp.id('32')
     OR v_row.children IS DISTINCT FROM 'yes' OR v_row.child_age_bands IS DISTINCT FROM ARRAY['under2']
     OR v_row.children_changed_by IS DISTINCT FROM pg_temp.id('32')
     OR v_row.ceremonies IS DISTINCT FROM '[]'::jsonb OR v_row.ceremonies_changed_by IS NOT NULL
     OR v_row.anniversary_source IS DISTINCT FROM 'together_since' OR v_row.anniversary_changed_by IS DISTINCT FROM pg_temp.id('31') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the drafts were not adopted inviter-first: %', row_to_json(v_row);
  END IF;
  IF v_row.together_since_changed_at IS DISTINCT FROM now() - interval '6 days'
     OR v_row.living_changed_at IS DISTINCT FROM now() - interval '3 days'
     OR v_row.children_changed_at IS DISTINCT FROM now() - interval '2 days'
     OR v_row.anniversary_changed_at IS DISTINCT FROM now() - interval '4 days'
     OR v_since_set IS DISTINCT FROM now() - interval '6 days' OR v_living_set IS DISTINCT FROM now() - interval '3 days'
     OR v_children_set IS DISTINCT FROM now() - interval '2 days' OR v_ann_set IS DISTINCT FROM now() - interval '4 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an adopted field lost its owner''s time: %', row_to_json(v_row);
  END IF;
  IF EXISTS (SELECT 1 FROM public.couple_profile_drafts WHERE user_id IN (pg_temp.id('31'), pg_temp.id('32'))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a draft survived the adoption';
  END IF;
  -- Review F-2: an answer queued before linking and replayed after it is
  -- refused, and leaves no draft for a later link to adopt.
  v_msg := pg_temp.draft_error('32', '{"living":"together"}');
  IF v_msg IS DISTINCT FROM 'couple_profile:not_found' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a draft answer replayed after linking was taken (F-2) (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.draft_error('31', '{"living":"together"}');
  IF v_msg IS DISTINCT FROM 'couple_profile:not_found' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the inviter''s draft answer replayed after linking was taken (F-2) (got %)', coalesce(v_msg, 'no error');
  END IF;
  IF EXISTS (SELECT 1 FROM public.couple_profile_drafts WHERE user_id IN (pg_temp.id('31'), pg_temp.id('32'))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replayed draft answer left a draft row after linking (F-2)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.reminders AS r
                  WHERE r.id = v_row.anniversary_reminder_id AND r.relationship_id = pg_temp.rel('31')
                    AND r.reminder_type = 'anniversary' AND r.created_by = pg_temp.id('31')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the adopted anniversary made no reminder';
  END IF;

  -- No drafts: no profile row (nothing invented).
  PERFORM pg_temp.person('33', 'Kofi Plain');
  PERFORM pg_temp.person('34', 'Esi Plain');
  INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at)
  VALUES (pg_temp.rel('33'), pg_temp.id('33'), 'pending', 'W5ADP2', now() + interval '7 days');
  PERFORM public.accept_relationship_invite_v2(pg_temp.id('34'), 'W5ADP2');
  IF EXISTS (SELECT 1 FROM public.couple_profiles WHERE relationship_id = pg_temp.rel('33')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a profile was made from no drafts';
  END IF;

  -- The inviter's month-only date wins, so the acceptor's anniversary on
  -- their own full date no longer holds: dropped (off, nobody's), never
  -- moved onto a date without a day; the acceptor's other answers fill in.
  PERFORM pg_temp.person('35', 'Abena Month');
  PERFORM pg_temp.person('36', 'Kwame Day');
  PERFORM pg_temp.draft_as('35', '{"together_since":"2019-05-01","together_since_precision":"month"}');
  PERFORM pg_temp.draft_as('36', '{"together_since":"2019-05-20","together_since_precision":"day","anniversary_source":"together_since","living":"long_distance"}');
  INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at)
  VALUES (pg_temp.rel('35'), pg_temp.id('35'), 'pending', 'W5ADP3', now() + interval '7 days');
  PERFORM public.accept_relationship_invite_v2(pg_temp.id('36'), 'W5ADP3');
  SELECT * INTO v_row FROM public.couple_profiles WHERE relationship_id = pg_temp.rel('35');
  IF NOT FOUND OR v_row.together_since IS DISTINCT FROM date '2019-05-01' OR v_row.together_since_precision IS DISTINCT FROM 'month'
     OR v_row.together_since_changed_by IS DISTINCT FROM pg_temp.id('35')
     OR v_row.living IS DISTINCT FROM 'long_distance' OR v_row.living_changed_by IS DISTINCT FROM pg_temp.id('36')
     OR v_row.anniversary_source IS DISTINCT FROM 'off' OR v_row.anniversary_changed_by IS NOT NULL
     OR v_row.anniversary_reminder_id IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a merged anniversary without a full date was kept: %', row_to_json(v_row);
  END IF;

  -- Both answered everything: every field is the inviter's (batch 1
  -- review: the acceptor-first order fails on any field, not only stage).
  PERFORM pg_temp.person('37', 'Akua Full');
  PERFORM pg_temp.person('38', 'Kojo Full');
  PERFORM pg_temp.draft_as('37', '{"together_since":"2018-03-03","together_since_precision":"day","stage":"married","ceremonies":[{"year":2019,"month":6,"day":1}],"living":"together","children":"none","anniversary_source":"ceremony_1"}');
  PERFORM pg_temp.draft_as('38', '{"together_since":"2017-05-05","together_since_precision":"day","stage":"engaged","living":"long_distance","children":"yes","child_age_bands":["6to12"],"anniversary_source":"together_since"}');
  INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at)
  VALUES (pg_temp.rel('37'), pg_temp.id('37'), 'pending', 'W5ADP4', now() + interval '7 days');
  PERFORM public.accept_relationship_invite_v2(pg_temp.id('38'), 'W5ADP4');
  SELECT * INTO v_row FROM public.couple_profiles WHERE relationship_id = pg_temp.rel('37');
  IF NOT FOUND OR v_row.together_since IS DISTINCT FROM date '2018-03-03' OR v_row.together_since_changed_by IS DISTINCT FROM pg_temp.id('37')
     OR v_row.stage IS DISTINCT FROM 'married' OR v_row.stage_changed_by IS DISTINCT FROM pg_temp.id('37')
     OR v_row.ceremonies IS DISTINCT FROM '[{"year":2019,"month":6,"day":1}]'::jsonb
     OR v_row.ceremonies_changed_by IS DISTINCT FROM pg_temp.id('37')
     OR v_row.living IS DISTINCT FROM 'together' OR v_row.living_changed_by IS DISTINCT FROM pg_temp.id('37')
     OR v_row.children IS DISTINCT FROM 'none' OR v_row.child_age_bands IS DISTINCT FROM '{}'::text[]
     OR v_row.children_changed_by IS DISTINCT FROM pg_temp.id('37')
     OR v_row.anniversary_source IS DISTINCT FROM 'ceremony_1' OR v_row.anniversary_changed_by IS DISTINCT FROM pg_temp.id('37')
     OR v_row.anniversary_reminder_id IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a field both answered was not the inviter''s: %', row_to_json(v_row);
  END IF;
  IF EXISTS (SELECT 1 FROM public.couple_profile_drafts WHERE user_id IN (pg_temp.id('37'), pg_temp.id('38'))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a draft survived the adoption (37, 38)';
  END IF;
END $$;

-- =====================================================================
-- H. The re-created functions keep their earlier behaviour, with W5's
--    lines in place (the full-body diff is the plan's Task 2 Step 6).
-- =====================================================================
DO $$
DECLARE
  v_src text;
BEGIN
  v_src := (SELECT p.prosrc FROM pg_proc AS p
             WHERE p.oid = 'public.accept_relationship_invite_v2(uuid,text)'::regprocedure);
  IF (SELECT count(*) FROM regexp_matches(v_src, 'adopt_couple_profile_drafts', 'g')) <> 1
     OR position('PERFORM public.adopt_couple_profile_drafts(v_rel.id, v_rel.user_a, p_acceptor);' IN v_src)
        < position('PERFORM public.set_user_path_internal(p_acceptor, ''relationship'');' IN v_src)
     OR position('PERFORM public.set_user_path_internal(p_acceptor, ''relationship'');' IN v_src) = 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the accept does not adopt the drafts once, after the path is set';
  END IF;
  v_src := (SELECT p.prosrc FROM pg_proc AS p
             WHERE p.oid = 'public.set_user_path_internal(uuid,text)'::regprocedure);
  IF position('DELETE FROM public.couple_profile_drafts AS d WHERE d.user_id = p_user;' IN v_src) = 0
     OR position('pause_dating_for_relationship_user' IN v_src) = 0
     OR position('bump_metric_internal(''path_chosen:''' IN v_src) = 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: set_user_path_internal lost a W1 statement or W5''s draft delete';
  END IF;
  v_src := (SELECT p.prosrc FROM pg_proc AS p
             WHERE p.oid = 'public.export_relationship(uuid,uuid)'::regprocedure);
  IF position('export_story_file_name' IN v_src) = 0 OR position('''about_us''' IN v_src) = 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: export_relationship lost the stories order or has no about_us';
  END IF;
END $$;

-- =====================================================================
-- I. The export (spec §4.3 W5): about_us with values and changes as
--    'me' / 'partner', never an id; the person's own birth date, path and
--    journal reminder. Relationship 31 (Yaw 31, Ama 32).
-- =====================================================================
DO $$
DECLARE
  b jsonb;
  a jsonb;
BEGIN
  INSERT INTO public.journal_reminder_settings (user_id, enabled, iso_weekday, local_time)
  VALUES (pg_temp.id('32'), true, 3, time '19:30');
  b := public.export_bundle(pg_temp.id('32'));
  a := b->'relationships'->0->'about_us';
  IF a IS NULL OR a->>'stage' IS DISTINCT FROM 'engaged' OR a->>'living' IS DISTINCT FROM 'together'
     OR NOT coalesce(a->'changes' @> '[{"field":"stage","by":"partner"},{"field":"living","by":"me"}]'::jsonb, false)
     OR (SELECT array_agg(k ORDER BY k COLLATE "C") FROM jsonb_object_keys(a) AS k)
        IS DISTINCT FROM ARRAY['anniversary_source', 'ceremonies', 'changes', 'child_age_bands', 'children',
                               'living', 'stage', 'stage_words', 'together_since', 'together_since_precision']
                         ::text[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the export''s about_us is wrong: %', a;
  END IF;
  IF a::text ~ '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the export''s about_us carries an id: %', a;
  END IF;
  IF (b->'personal'->'settings'->>'birth_date')::date IS DISTINCT FROM (current_date - interval '30 years')::date
     OR b->'personal'->'settings'->>'path' IS DISTINCT FROM 'relationship'
     OR b->'personal'->'settings'->'journal_reminder' IS DISTINCT FROM '{"enabled":true,"iso_weekday":3,"local_time":"19:30:00"}'::jsonb
     OR NOT coalesce(b->'personal'->'settings' ?& ARRAY['timezone', 'seen_receipts', 'devices'], false) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: personal.settings lacks the W5 keys or lost the old ones: %', b->'personal'->'settings';
  END IF;
  -- The other member's export has the same profile, the attribution turned.
  a := public.export_bundle(pg_temp.id('31'))->'relationships'->0->'about_us';
  IF NOT coalesce(a->'changes' @> '[{"field":"stage","by":"me"},{"field":"living","by":"partner"}]'::jsonb, false) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the inviter''s export attributes wrongly: %', a->'changes';
  END IF;
  -- No profile: about_us is there, and null; no journal reminder: null.
  b := public.export_bundle(pg_temp.id('34'));
  IF NOT coalesce(b->'relationships'->0 ? 'about_us', false)
     OR b->'relationships'->0->'about_us' IS DISTINCT FROM 'null'::jsonb
     OR NOT coalesce(b->'personal'->'settings' ? 'journal_reminder', false)
     OR b->'personal'->'settings'->'journal_reminder' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an export without a profile or a journal reminder reads wrongly: %', b->'relationships'->0->'about_us';
  END IF;
END $$;

-- =====================================================================
-- J. W5 final review: About us never adopts, renames, unlinks or deletes
--    a hand-made reminder (M-2, ruling "M-2 replaced"): with a hand-made
--    yearly anniversary-type reminder it makes none of its own, and "No,
--    thanks" touches only its own; a hand-made one-off doesn't count. A
--    29 February anniversary is the 29th in leap years and the 28th only
--    in others (M-1). The guard lets lead times and the note through
--    together (I-2's locked form). Fixtures 41-44 (relationships 41, 43).
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_own uuid;
  v_once uuid;
  v_mine uuid;
  v_memory uuid;
  v_before jsonb;
  v_memory_before jsonb;
  v_once_before jsonb;
  v_msg text;
  v_stored date;
BEGIN
  PERFORM pg_temp.person('41', 'Kofi');
  PERFORM pg_temp.person('42', 'Ama');
  PERFORM pg_temp.person('43', 'Esi');
  PERFORM pg_temp.person('44', 'Yaw');
  PERFORM pg_temp.couple('41', '41', '42', 'active');
  PERFORM pg_temp.couple('43', '43', '44', 'active');

  -- Ama made her own yearly anniversary reminder, a week's notice and a
  -- note, with its memory.
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
  VALUES (pg_temp.rel('41'), pg_temp.id('42'), 'anniversary', 'Our day', date '2015-06-12')
  RETURNING id INTO v_memory;
  INSERT INTO public.reminders (relationship_id, created_by, reminder_type, title, note, remind_at,
                                recurrence, remind_days_before, linked_timeline_event_id)
  VALUES (pg_temp.rel('41'), pg_temp.id('42'), 'anniversary', 'Our day', 'Book the jollof place',
          timestamptz '2015-06-12 00:00:00+00', 'yearly', ARRAY[0, 7], v_memory)
  RETURNING id INTO v_own;
  SELECT to_jsonb(r) INTO v_before FROM public.reminders AS r WHERE r.id = v_own;
  SELECT to_jsonb(e) INTO v_memory_before FROM public.timeline_events AS e WHERE e.id = v_memory;

  v := pg_temp.update_as('41', '41', '{"together_since":"2015-06-12","together_since_precision":"day","anniversary_source":"together_since"}');
  IF v->>'anniversary_source' <> 'together_since' OR v->'anniversary_reminder_id' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: About us took or added a reminder beside the couple''s own: %', v;
  END IF;
  IF (SELECT count(*) FROM public.reminders WHERE relationship_id = pg_temp.rel('41')) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: About us added a second anniversary reminder';
  END IF;
  IF (SELECT to_jsonb(r) FROM public.reminders AS r WHERE r.id = v_own) IS DISTINCT FROM v_before
     OR (SELECT to_jsonb(e) FROM public.timeline_events AS e WHERE e.id = v_memory) IS DISTINCT FROM v_memory_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: About us changed the couple''s own reminder or its memory: %',
      (SELECT to_jsonb(r) FROM public.reminders AS r WHERE r.id = v_own);
  END IF;
  -- A later edit (the date moves) still leaves it alone.
  PERFORM pg_temp.update_as('42', '41', '{"together_since":"2015-06-13","together_since_precision":"day"}');
  -- "No, thanks" touches only About us's own: the couple's stays as it was.
  v := pg_temp.update_as('42', '41', '{"anniversary_source":"off"}');
  IF (SELECT to_jsonb(r) FROM public.reminders AS r WHERE r.id = v_own) IS DISTINCT FROM v_before
     OR (SELECT count(*) FROM public.reminders WHERE relationship_id = pg_temp.rel('41')) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: "No, thanks" touched the couple''s own reminder';
  END IF;
  -- Not About us's: the app may edit or delete it as before.
  PERFORM pg_temp.as_user(pg_temp.id('42'));
  v_msg := pg_temp.error_of(format('UPDATE public.reminders SET title = %L WHERE id = %L', 'Ours', v_own));
  RESET ROLE;
  IF v_msg IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the guard stopped the couple''s own reminder (%)', v_msg;
  END IF;

  -- A hand-made one-off anniversary reminder doesn't count: About us makes
  -- its own, and the one-off stays as it was (relationship 43; another
  -- couple's yearly reminder never counts either).
  INSERT INTO public.reminders (relationship_id, created_by, reminder_type, title, remind_at, recurrence)
  VALUES (pg_temp.rel('43'), pg_temp.id('43'), 'anniversary', 'Dinner booked',
          date_trunc('day', now() AT TIME ZONE 'utc') AT TIME ZONE 'utc' + interval '20 days', 'none')
  RETURNING id INTO v_once;
  SELECT to_jsonb(r) INTO v_once_before FROM public.reminders AS r WHERE r.id = v_once;
  v := pg_temp.update_as('43', '43', '{"together_since":"2019-01-05","together_since_precision":"day","anniversary_source":"together_since"}');
  v_mine := (v->>'anniversary_reminder_id')::uuid;
  IF v_mine IS NULL OR v_mine = v_once
     OR (SELECT (title, recurrence) FROM public.reminders WHERE id = v_mine)
        IS DISTINCT FROM ('Anniversary'::text, 'yearly'::text)
     OR (SELECT to_jsonb(r) FROM public.reminders AS r WHERE r.id = v_once) IS DISTINCT FROM v_once_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: beside a one-off, About us did not make its own: %', v;
  END IF;
  -- I-2: the locked form's one update, lead times and note together.
  PERFORM pg_temp.as_user(pg_temp.id('44'));
  v_msg := pg_temp.error_of(format(
    'UPDATE public.reminders SET remind_days_before = ARRAY[1, 7], note = %L WHERE id = %L',
    'Flowers', v_mine));
  RESET ROLE;
  IF v_msg IS NOT NULL
     OR (SELECT (remind_days_before, note) FROM public.reminders WHERE id = v_mine)
        IS DISTINCT FROM (ARRAY[1, 7], 'Flowers'::text) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the locked form''s lead times and note were refused (%)', v_msg;
  END IF;
  v := pg_temp.update_as('44', '43', '{"anniversary_source":"off"}');
  IF EXISTS (SELECT 1 FROM public.reminders WHERE id = v_mine)
     OR (SELECT to_jsonb(r) FROM public.reminders AS r WHERE r.id = v_once) IS DISTINCT FROM v_once_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: "No, thanks" kept its own or touched the one-off';
  END IF;

  -- M-1: 29 February.
  v := pg_temp.update_as('43', '43', '{"together_since":"2000-02-29","together_since_precision":"day","anniversary_source":"together_since"}');
  SELECT (remind_at AT TIME ZONE 'utc')::date INTO v_stored
    FROM public.reminders WHERE id = (v->>'anniversary_reminder_id')::uuid;
  IF v_stored IS NULL
     OR public.reminder_next_on(v_stored, 'yearly', date '2028-01-10') <> date '2028-02-29'
     OR public.reminder_next_on(v_stored, 'yearly', date '2027-01-10') <> date '2027-02-28'
     OR public.reminder_next_on(v_stored, 'yearly', date '2032-02-29') <> date '2032-02-29'
     OR public.reminder_next_on(v_stored, 'yearly', date '2029-03-01') <> date '2030-02-28'
     OR public.reminder_next_on(v_stored, 'yearly', (now() AT TIME ZONE 'utc')::date)
        <> public.reminder_next_on(date '2000-02-29', 'yearly', (now() AT TIME ZONE 'utc')::date) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 29 February anniversary drifts (stored %)', v_stored;
  END IF;
  -- A ceremony on 29 February, the same.
  v := pg_temp.update_as('44', '43', '{"stage":"married","ceremonies":[{"year":2004,"month":2,"day":29}],"anniversary_source":"ceremony_1"}');
  SELECT (remind_at AT TIME ZONE 'utc')::date INTO v_stored
    FROM public.reminders WHERE id = (v->>'anniversary_reminder_id')::uuid;
  IF public.reminder_next_on(v_stored, 'yearly', date '2028-01-10') <> date '2028-02-29'
     OR public.reminder_next_on(v_stored, 'yearly', date '2031-01-10') <> date '2031-02-28' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 29 February ceremony drifts (stored %)', v_stored;
  END IF;
  -- Any other date is still stored as its next occurrence.
  v := pg_temp.update_as('44', '43', '{"ceremonies":[{"year":2004,"month":3,"day":1}]}');
  SELECT (remind_at AT TIME ZONE 'utc')::date INTO v_stored
    FROM public.reminders WHERE id = (v->>'anniversary_reminder_id')::uuid;
  IF v_stored <> public.reminder_next_on(date '2004-03-01', 'yearly', (now() AT TIME ZONE 'utc')::date) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ordinary date is no longer its next occurrence (stored %)', v_stored;
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'couple_profile_contracts: all held'; END $$;
ROLLBACK;
