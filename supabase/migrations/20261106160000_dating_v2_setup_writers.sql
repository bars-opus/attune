-- Spec 2 W1c, migration 7 (spec §4.9 W1c #1, part 2 of 3: the setup
-- writers D2-D8; §3.2, §2.4, §4.4):
--   save_dating_intention (D2), save_dating_location (D3),
--   save_dating_identity (D5), save_dating_who_to_meet (D6),
--   save_dating_children (D7), save_dating_faith / clear_dating_faith (D8).
-- Every writer except Skip: signed in (else not_authenticated, 42501, like
-- every Dating RPC); the person's setup lock (one step at a time, I-5);
-- dating_require_trusted_device() (reverify_device); then
-- dating_eligibility(me, 'setup') (any failure -> the opaque not_eligible;
-- get_dating_home, W2, says which); then its own validation (invalid, with
-- the field); the special-category writers (D5, D6, D8) need the
-- special_category_profile consent (and D8 special_category_faith) and the
-- field key (unavailable); THEN the idempotency key is claimed
-- (claim_dating_idempotency: a repeat answers ok and writes nothing). Each
-- returns {"ok": true, "next_step": ...} or {"ok": false, "reason": ...}
-- and never raises for a person's answers (each is validated before any
-- write, so no constraint error can echo a row; a malformed idempotency
-- key is 22023, as in every Dating RPC).
-- clear_dating_faith (D8 Skip) is never gated on eligibility or the device
-- (W1 B7 ruling): removing one's own faith answer always works.
-- Locks (I-5), one order everywhere: the setup lock (two-key advisory,
-- hashtext('dating_setup'), hashtext(user)), then for D5 and D6 the
-- country's same-gender lock (hashtext('dating_same_gender'),
-- hashtext(country)) SHARED, then the profile row FOR UPDATE. Task 13's
-- kill switch takes the same-gender lock EXCLUSIVE before any row, so a
-- same-gender answer is never decided against a switch that is running.
-- Where same-gender is off (the Dating country's same_gender_enabled, and
-- the global flag dating_same_gender_matching), D5 and D6 accept only
-- woman/man and the opposite seeking; anything else returns
-- {"ok": false, "reason": "not_available"} WITHOUT raising (a raise can
-- reach the Postgres log), stores nothing and counts nothing (§2.4).
-- Changing the Dating country (at most once per 30 days) clears the
-- encrypted identity and seeking, so D5 and D6 are asked again (§2.4,
-- plan P-28). Counters are server-side (S-2): dating.setup.started,
-- dating.setup.step.d2..d8.
-- Batch 7 (rulings):
--   NULL is never valid: the guard reads IS NOT TRUE / IS DISTINCT FROM,
--   and dating_same_gender_on is a plain true or false.
--   PF-F7: D5's specific term and pronouns go through
--   private.content_filter_verdict after the off-country refusal and the
--   validation (contact_details / unkind; nothing stored or counted);
--   pronouns are letters, '/', space and hyphen.
--   PF-F3: private.dating_clear_faith(user) clears the faith answer and
--   its visibility only (D8 Skip here; Task 12's faith-only withdrawal).
--   Batch-6 carry: dating:field_decrypt_failed and dating:field_key_missing
--   answer unavailable; the step's writes sit in one block that is undone.
--   I-4 (provisional, counsel confirms): marriage history is not Art. 9;
--   D2 saves it (encrypted) without the special-category consent.
-- Batch 8 fix round 1 (W1 B8 ruling, I-2): other countries never hold a
--   country whose same-gender rule excludes the person's profile. D3, D5
--   and D6 take the shared same-gender locks of the Dating country and of
--   every other country (sorted by code, before the profile row), and when
--   the stored profile is not plain (woman or man, nothing more, meeting
--   only the opposite) remove every other country where same-gender is off.
-- W1 final fix (I-1, M-3): dating_lock_setup also takes the shared
--   same-gender locks of the person's countries (sorted, before any row),
--   so every caller follows the kill switch's lock order; an overload
--   takes extra countries (D3's new one, re-created in migration 11).
-- Grants in 20261106160010_dating_v2_setup_writers_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- The person's setup lock (I-5): one setup step at a time per person, so a
-- country change (D3) never interleaves with D5 or D6, and two D3 calls
-- can't both pass the 30-day limit. Held until the transaction ends.
-- W1 final fix (I-1, M-3): then, before any row, the SHARED same-gender
-- locks of the person's Dating country, every other country on their list
-- and [p_also] (D3's new country, other countries' new list), sorted by
-- code (dating_lock_same_gender_all, defined below; resolved at run time).
-- Every Dating writer, lifecycle RPC and trigger path starts here, so a
-- kill switch (the same locks EXCLUSIVE, before any row) and a writer for
-- someone in the switched country serialise instead of deadlocking; the
-- setup lock keeps the country and list stable while they are read.
CREATE OR REPLACE FUNCTION private.dating_lock_setup(p_user uuid, p_also text[])
RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
BEGIN
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('dating_setup'), pg_catalog.hashtext(p_user::text));
  PERFORM private.dating_lock_same_gender_all(
    coalesce(p_also, ARRAY[]::text[])
    || ARRAY(SELECT p.country_code::text FROM public.dating_profiles AS p WHERE p.user_id = p_user)
    || ARRAY(SELECT c::text FROM public.dating_preferences AS d, unnest(d.open_abroad) AS c WHERE d.user_id = p_user));
END;
$fn$;
CREATE OR REPLACE FUNCTION private.dating_lock_setup(p_user uuid)
RETURNS void
LANGUAGE sql
SET search_path = ''
AS $fn$
  SELECT private.dating_lock_setup(p_user, NULL::text[]);
$fn$;

-- A Dating country's same-gender lock, shared (I-5): D5 and D6 hold it
-- while they decide and store; Task 13's apply_same_gender_switch takes it
-- exclusive (for every country on a global flag change) before its rows.
CREATE OR REPLACE FUNCTION private.dating_lock_same_gender(p_country text)
RETURNS void
LANGUAGE sql
SET search_path = ''
AS $fn$
  SELECT pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('dating_same_gender'),
                                                 pg_catalog.hashtext(coalesce(p_country, '')));
$fn$;

-- B8 I-2: the shared same-gender locks of a set of countries, in sorted
-- code order (Task 13's global switch takes them exclusive in the same
-- order, so no two callers deadlock). NULLs are skipped.
CREATE OR REPLACE FUNCTION private.dating_lock_same_gender_all(p_countries text[])
RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
DECLARE
  v_c text;
BEGIN
  FOR v_c IN SELECT DISTINCT c COLLATE "C" AS c FROM unnest(p_countries) AS c WHERE c IS NOT NULL ORDER BY 1 LOOP
    PERFORM private.dating_lock_same_gender(v_c);
  END LOOP;
END;
$fn$;

-- B8 I-2: a "plain" profile, the only one any same-gender-off country may
-- see: woman or man, no specific term, no pronouns, no extra pool, meeting
-- only the opposite (exactly what an off-country D5 and D6 accept). NULL
-- or unreadable is not plain (fail closed).
CREATE OR REPLACE FUNCTION private.dating_profile_plain(p_identity jsonb, p_seeking jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT coalesce(p_identity ->> 'identity' IN ('woman', 'man')
                  AND p_identity ->> 'specific' IS NULL AND p_identity ->> 'specific_text' IS NULL
                  AND p_identity ->> 'pronouns' IS NULL
                  AND p_identity -> 'pools' = jsonb_build_array(p_identity ->> 'identity')
                  AND p_seeking -> 'seeking' = jsonb_build_array(CASE p_identity ->> 'identity' WHEN 'woman' THEN 'man' ELSE 'woman' END),
                  false);
$fn$;

-- B8 I-2: removes from a person's other countries every country where
-- same-gender is off; the rest stay. The caller holds those countries'
-- shared same-gender locks (dating_lock_same_gender_all).
CREATE OR REPLACE FUNCTION private.dating_prune_unsafe_abroad(p_user uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  UPDATE public.dating_preferences AS d
     SET open_abroad = ARRAY(SELECT c FROM unnest(d.open_abroad) AS c
                              WHERE private.dating_same_gender_on(c::text) IS TRUE ORDER BY c),
         updated_at = now()
   WHERE d.user_id = p_user
     AND EXISTS (SELECT 1 FROM unnest(d.open_abroad) AS c WHERE private.dating_same_gender_on(c::text) IS NOT TRUE);
END;
$fn$;

-- The checks every setup writer runs first: NULL to go on, else the reason.
CREATE OR REPLACE FUNCTION private.dating_setup_guard()
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  PERFORM private.dating_lock_setup(v_user);
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN 'reverify_device';
  END IF;
  IF public.dating_eligibility(v_user, 'setup') IS DISTINCT FROM 'eligible' THEN
    RETURN 'not_eligible';
  END IF;
  RETURN NULL;
END;
$fn$;

-- The enrolment (profile_draft) and the profile row a step writes into;
-- true when this starts a setup (no profile row before).
CREATE OR REPLACE FUNCTION private.dating_ensure_profile(p_user uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_name text;
BEGIN
  INSERT INTO public.dating_enrollments AS e (user_id, state) VALUES (p_user, 'profile_draft')
  ON CONFLICT (user_id) DO UPDATE SET state = 'profile_draft', exited_at = NULL, updated_at = now()
   WHERE e.state IN ('ineligible', 'eligible_to_opt_in', 'exited');
  INSERT INTO public.dating_profile_sensitive (user_id) VALUES (p_user) ON CONFLICT (user_id) DO NOTHING;
  IF EXISTS (SELECT 1 FROM public.dating_profiles AS p WHERE p.user_id = p_user) THEN
    RETURN false;
  END IF;
  -- I-3: the account name is a default only if the content filter passes
  -- it (contact details, slurs, explicit); else "Me", and D12 asks. Cut to
  -- 30 and trimmed again, so it never ends in a space.
  SELECT btrim(left(btrim(coalesce(u.display_name, '')), 30)) INTO v_name FROM public.users AS u WHERE u.id = p_user;
  IF private.content_filter_verdict(v_name, NULL) IS NOT NULL THEN
    v_name := NULL;
  END IF;
  INSERT INTO public.dating_profiles (user_id, display_name, moderation_state)
  VALUES (p_user, coalesce(nullif(v_name, ''), 'Me'), 'approved')
  ON CONFLICT (user_id) DO NOTHING;
  RETURN FOUND;
END;
$fn$;

-- Same-gender allowed for a Dating country (§2.4): the global flag and
-- the country's switch.
CREATE OR REPLACE FUNCTION private.dating_same_gender_on(p_country text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT coalesce(public.dating_flag_enabled('dating_same_gender_matching'), false)
         AND coalesce((public.dating_country_config(p_country)).same_gender_enabled, false);
$fn$;

-- The default age range for a person of [p_age] (§3.2 D6).
CREATE OR REPLACE FUNCTION private.dating_default_ages(p_age integer)
RETURNS integer[]
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT CASE WHEN p_age IS NULL THEN ARRAY[18, 99]
              WHEN p_age <= 20 THEN ARRAY[18, least(99, p_age + 7)]
              ELSE ARRAY[greatest(18, p_age - 5), least(99, p_age + 5)] END;
$fn$;

CREATE OR REPLACE FUNCTION private.dating_invalid(p_field text)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT jsonb_build_object('ok', false, 'reason', 'invalid', 'field', p_field);
$fn$;

-- The faith answer and what matching derives from it (its visibility),
-- nothing else (PF-F3, owner 2026-11-06): D8 Skip here, Task 12's
-- faith-only consent withdrawal. No setup guard: removing it always works.
CREATE OR REPLACE FUNCTION private.dating_clear_faith(p_user uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  UPDATE public.dating_profile_sensitive AS s SET faith_enc = NULL, updated_at = now()
   WHERE s.user_id = p_user AND s.faith_enc IS NOT NULL;
  UPDATE public.dating_profiles AS p SET faith_visible = false, updated_at = now()
   WHERE p.user_id = p_user AND p.faith_visible;
END;
$fn$;

-- D2: what are you looking for, the attestation, marriage history.
CREATE OR REPLACE FUNCTION public.save_dating_intention(p_idempotency_key text, p_intention text, p_timeline text,
  p_timeline_visible boolean, p_attested boolean, p_marital text, p_marital_visible boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_started boolean;
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  IF p_intention IS NULL OR p_intention NOT IN ('marriage', 'committed', 'companionship', 'not_sure') THEN
    RETURN private.dating_invalid('intention');
  END IF;
  IF (p_intention = 'marriage' AND p_timeline IS NOT NULL
        AND p_timeline NOT IN ('within_two_years', 'few_years', 'no_set_time'))
     OR (p_intention IS DISTINCT FROM 'marriage' AND p_timeline IS NOT NULL) THEN
    RETURN private.dating_invalid('timeline');
  END IF;
  IF p_attested IS NOT TRUE THEN
    RETURN private.dating_invalid('attestation');
  END IF;
  IF p_marital IS NOT NULL AND p_marital NOT IN ('never', 'divorced', 'widowed') THEN
    RETURN private.dating_invalid('marital');
  END IF;
  IF private.dating_field_key_present() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  BEGIN
    IF NOT public.claim_dating_idempotency('save_dating_intention', p_idempotency_key) THEN
      RETURN jsonb_build_object('ok', true, 'next_step', 'where');
    END IF;

    v_started := private.dating_ensure_profile(v_user);
    UPDATE public.dating_profiles AS p
       SET intention = p_intention,
           marriage_timeline = CASE WHEN p_intention = 'marriage' THEN p_timeline END,
           timeline_visible = coalesce(p_timeline_visible, true),
           not_married_attested_at = now(),
           attestation_version = '2026-10-v1',
           marital_visible = coalesce(p_marital_visible, false) AND coalesce(p_marital IN ('divorced', 'widowed'), false),
           updated_at = now()
     WHERE p.user_id = v_user;
    UPDATE public.dating_profile_sensitive AS s
       SET marital_enc = private.dating_field_encrypt(CASE WHEN p_marital IS NULL THEN NULL
                                                          ELSE jsonb_build_object('marital', p_marital) END),
           updated_at = now()
     WHERE s.user_id = v_user;
    IF v_started THEN
      PERFORM private.bump_metric_internal('dating.setup.started');
    END IF;
    PERFORM private.bump_metric_internal('dating.setup.step.d2');
  EXCEPTION WHEN raise_exception THEN
    -- An unreadable value or a missing key (D2): unavailable, and the
    -- block's claim, rows and counters are undone (batch-6 carry).
    IF SQLERRM IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
    END IF;
    RAISE;
  END;
  RETURN jsonb_build_object('ok', true, 'next_step', 'where');
END;
$fn$;

-- D3: where (country, region, side, how far).
CREATE OR REPLACE FUNCTION public.save_dating_location(p_idempotency_key text, p_country text, p_region text,
  p_side text, p_scope text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_country constant text := upper(coalesce(p_country, ''));
  v_config public.country_safety_config;
  v_region jsonb;
  v_old_country text;
  v_changed_at timestamptz;
  v_ages integer[];
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  v_config := public.dating_country_config(v_country);
  IF v_config.country_code IS NULL THEN
    RETURN private.dating_invalid('country');
  END IF;
  IF v_config.dating_enabled IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'country_closed');
  END IF;
  SELECT r INTO v_region FROM jsonb_array_elements(v_config.region_list) AS r WHERE r ->> 'code' = p_region;
  IF v_region IS NULL THEN
    RETURN private.dating_invalid('region');
  END IF;
  IF v_config.open_regions IS NOT NULL AND (p_region = ANY (v_config.open_regions)) IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'region_closed');
  END IF;
  IF p_side IS NOT NULL AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(v_region -> 'sides', '[]'::jsonb)) AS s
                                         WHERE s ->> 'code' = p_side) THEN
    RETURN private.dating_invalid('side');
  END IF;
  IF p_scope IS NULL OR p_scope NOT IN ('side', 'region', 'country') OR (p_scope = 'side' AND p_side IS NULL) THEN
    RETURN private.dating_invalid('scope');
  END IF;
  -- B8 I-2: the other countries' shared same-gender locks (sorted), then the row.
  PERFORM private.dating_lock_same_gender_all(ARRAY(SELECT c::text FROM public.dating_preferences AS d, unnest(d.open_abroad) AS c
                                                     WHERE d.user_id = v_user));
  SELECT p.country_code, p.country_changed_at INTO v_old_country, v_changed_at
    FROM public.dating_profiles AS p WHERE p.user_id = v_user FOR UPDATE;
  IF v_old_country IS NOT NULL AND v_old_country IS DISTINCT FROM v_country
     AND v_changed_at IS NOT NULL AND v_changed_at > now() - interval '30 days' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'country_change_limited');
  END IF;
  IF NOT public.claim_dating_idempotency('save_dating_location', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true, 'next_step', 'privacy');
  END IF;

  IF private.dating_ensure_profile(v_user) THEN
    PERFORM private.bump_metric_internal('dating.setup.started');
  END IF;
  UPDATE public.dating_profiles AS p
     SET country_code = v_country, region_code = p_region, side_code = p_side,
         country_changed_at = CASE WHEN p.country_code IS DISTINCT FROM v_country AND p.country_code IS NOT NULL
                                   THEN now() ELSE p.country_changed_at END,
         updated_at = now()
   WHERE p.user_id = v_user;
  -- A new Dating country: gender and who-to-meet are asked again (§2.4).
  IF v_old_country IS NOT NULL AND v_old_country IS DISTINCT FROM v_country THEN
    UPDATE public.dating_profile_sensitive AS s
       SET identity_enc = NULL, seeking_enc = NULL, updated_at = now()
     WHERE s.user_id = v_user;
    UPDATE public.dating_profiles AS p SET gender_visible = false WHERE p.user_id = v_user;
    UPDATE public.dating_preferences AS d
       SET open_abroad = array_remove(d.open_abroad, v_country::char(2)) WHERE d.user_id = v_user;
    -- B8 I-2: gender and who-to-meet are unknown again (not plain).
    PERFORM private.dating_prune_unsafe_abroad(v_user);
  END IF;
  v_ages := private.dating_default_ages(public.account_age(v_user));
  INSERT INTO public.dating_preferences AS d (user_id, min_age, max_age, region_scope)
  VALUES (v_user, v_ages[1], v_ages[2], p_scope)
  ON CONFLICT (user_id) DO UPDATE SET region_scope = EXCLUDED.region_scope, updated_at = now();
  PERFORM private.bump_metric_internal('dating.setup.step.d3');
  RETURN jsonb_build_object('ok', true, 'next_step', 'privacy');
END;
$fn$;

-- D5: which best describes you.
CREATE OR REPLACE FUNCTION public.save_dating_identity(p_idempotency_key text, p_identity text, p_specific text,
  p_pronouns text, p_extra_pools text[], p_visible boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_country text;
  v_extra constant text[] := coalesce(p_extra_pools, ARRAY[]::text[]);
  v_known constant text[] := ARRAY['trans_woman', 'trans_man', 'genderfluid', 'genderqueer', 'agender', 'intersex'];
  v_old jsonb;
  v_pools text[];
  v_verdict text;
  v_new jsonb;
  v_seeking jsonb;
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  IF private.dating_consent_granted(v_user, 'special_category_profile') IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'consent_required');
  END IF;
  SELECT p.country_code INTO v_country FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  IF v_country IS NULL THEN
    RETURN private.dating_invalid('country');
  END IF;
  -- I-5: the country's same-gender lock (shared), then the profile row.
  -- B8 I-2: with the other countries' locks, all sorted by code.
  PERFORM private.dating_lock_same_gender_all(ARRAY[v_country] || ARRAY(
            SELECT c::text FROM public.dating_preferences AS d, unnest(d.open_abroad) AS c WHERE d.user_id = v_user));
  PERFORM 1 FROM public.dating_profiles AS p WHERE p.user_id = v_user FOR UPDATE;
  -- Off-country (§2.4): only Woman or Man, nothing more; anything else is
  -- not_available, raised by nothing, stored nowhere, counted nowhere.
  IF private.dating_same_gender_on(v_country) IS NOT TRUE
     AND (p_identity IS DISTINCT FROM 'woman' AND p_identity IS DISTINCT FROM 'man'
          OR p_specific IS NOT NULL OR p_pronouns IS NOT NULL OR cardinality(v_extra) > 0) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_available');
  END IF;
  IF p_identity IS NULL OR p_identity NOT IN ('woman', 'man', 'non_binary') THEN
    RETURN private.dating_invalid('identity');
  END IF;
  IF p_specific IS NOT NULL AND NOT (p_specific = ANY (v_known))
     AND NOT coalesce((p_specific COLLATE "pg_c_utf8") ~ '^[[:alpha:]][[:alpha:] -]{0,29}$' AND char_length(btrim(p_specific)) BETWEEN 1 AND 30, false) THEN
    RETURN private.dating_invalid('specific');
  END IF;
  -- PF-F7: letters, '/', space and hyphen only (at least one letter).
  IF p_pronouns IS NOT NULL
     AND (char_length(btrim(p_pronouns)) NOT BETWEEN 1 AND 20
          OR NOT coalesce((btrim(p_pronouns) COLLATE "pg_c_utf8") ~ '^[[:alpha:]/ -]+$', false)
          OR NOT coalesce((p_pronouns COLLATE "pg_c_utf8") ~ '[[:alpha:]]', false)) THEN
    RETURN private.dating_invalid('pronouns');
  END IF;
  IF NOT coalesce(v_extra <@ ARRAY['woman', 'man'], false)
     OR (cardinality(v_extra) > 0 AND p_identity IS DISTINCT FROM 'non_binary') THEN
    RETURN private.dating_invalid('pools');
  END IF;
  -- PF-F7: the free text shown on the card is filtered like the prompts,
  -- after the off-country refusal (§2.4 first) and the validation; a hit
  -- stores, claims and counts nothing.
  v_verdict := private.content_filter_verdict(concat_ws(' ', p_specific, p_pronouns), NULL);
  IF v_verdict IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', CASE WHEN v_verdict = 'contact_info' THEN 'contact_details' ELSE 'unkind' END);
  END IF;
  IF private.dating_field_key_present() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  BEGIN
    IF NOT public.claim_dating_idempotency('save_dating_identity', p_idempotency_key) THEN
      RETURN jsonb_build_object('ok', true, 'next_step', 'meet');
    END IF;

    PERFORM private.dating_ensure_profile(v_user);
    v_pools := CASE p_identity WHEN 'non_binary'
                 THEN ARRAY['non_binary'] || ARRAY(SELECT DISTINCT e FROM unnest(v_extra) AS e ORDER BY e)
                 ELSE ARRAY[p_identity] END;
    SELECT private.dating_field_decrypt(s.identity_enc) INTO v_old
      FROM public.dating_profile_sensitive AS s WHERE s.user_id = v_user;
    v_new := jsonb_build_object(
             'identity', p_identity,
             'specific', CASE WHEN p_specific = ANY (v_known) THEN p_specific END,
             'specific_text', CASE WHEN p_specific IS NOT NULL AND NOT (p_specific = ANY (v_known)) THEN btrim(p_specific) END,
             'pronouns', nullif(btrim(p_pronouns), ''),
             'pools', to_jsonb(v_pools));
    UPDATE public.dating_profile_sensitive AS s
       SET identity_enc = private.dating_field_encrypt(v_new),
           -- A changed identity where same-gender is off: who-to-meet is asked again.
           seeking_enc = CASE WHEN private.dating_same_gender_on(v_country) IS NOT TRUE
                               AND v_old ->> 'identity' IS DISTINCT FROM p_identity THEN NULL
                              ELSE s.seeking_enc END,
           updated_at = now()
     WHERE s.user_id = v_user;
    UPDATE public.dating_profiles AS p SET gender_visible = coalesce(p_visible, false), updated_at = now()
     WHERE p.user_id = v_user;
    -- B8 I-2: not plain now (with who-to-meet as stored): unsafe other countries go.
    SELECT private.dating_field_decrypt(s.seeking_enc) INTO v_seeking
      FROM public.dating_profile_sensitive AS s WHERE s.user_id = v_user;
    IF private.dating_profile_plain(v_new, v_seeking) IS NOT TRUE THEN
      PERFORM private.dating_prune_unsafe_abroad(v_user);
    END IF;
    PERFORM private.bump_metric_internal('dating.setup.step.d5');
  EXCEPTION WHEN raise_exception THEN
    -- An unreadable value or a missing key (D5): unavailable, and the
    -- block's claim, rows and counters are undone (batch-6 carry).
    IF SQLERRM IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
    END IF;
    RAISE;
  END;
  RETURN jsonb_build_object('ok', true, 'next_step', 'meet');
END;
$fn$;

-- D6: who would you like to meet, and their ages.
CREATE OR REPLACE FUNCTION public.save_dating_who_to_meet(p_idempotency_key text, p_seeking text[],
  p_min_age integer, p_max_age integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_country text;
  v_identity jsonb;
  v_seeking text[];
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  IF private.dating_consent_granted(v_user, 'special_category_profile') IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'consent_required');
  END IF;
  IF private.dating_field_key_present() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  SELECT p.country_code INTO v_country FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  -- I-5: the country's same-gender lock (shared), then the profile row.
  -- B8 I-2: with the other countries' locks, all sorted by code.
  IF v_country IS NOT NULL THEN
    PERFORM private.dating_lock_same_gender_all(ARRAY[v_country] || ARRAY(
              SELECT c::text FROM public.dating_preferences AS d, unnest(d.open_abroad) AS c WHERE d.user_id = v_user));
    PERFORM 1 FROM public.dating_profiles AS p WHERE p.user_id = v_user FOR UPDATE;
  END IF;
  BEGIN
    SELECT private.dating_field_decrypt(s.identity_enc) INTO v_identity
      FROM public.dating_profile_sensitive AS s WHERE s.user_id = v_user;
    IF v_country IS NULL OR v_identity IS NULL THEN
      RETURN private.dating_invalid('identity');
    END IF;
    v_seeking := ARRAY(SELECT DISTINCT e FROM unnest(coalesce(p_seeking, ARRAY[]::text[])) AS e ORDER BY e);
    -- Off-country (§2.4): only the opposite of a woman or a man.
    IF private.dating_same_gender_on(v_country) IS NOT TRUE
       AND v_seeking IS DISTINCT FROM (CASE v_identity ->> 'identity' WHEN 'woman' THEN ARRAY['man']
                                                                    WHEN 'man' THEN ARRAY['woman'] END) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'not_available');
    END IF;
    IF v_seeking NOT IN (ARRAY['man'], ARRAY['woman'], ARRAY['man', 'non_binary', 'woman']) THEN
      RETURN private.dating_invalid('seeking');
    END IF;
    IF p_min_age IS NULL OR p_max_age IS NULL OR p_min_age < 18 OR p_max_age > 99 OR p_min_age > p_max_age THEN
      RETURN private.dating_invalid('ages');
    END IF;
    IF NOT public.claim_dating_idempotency('save_dating_who_to_meet', p_idempotency_key) THEN
      RETURN jsonb_build_object('ok', true, 'next_step', 'children');
    END IF;

    UPDATE public.dating_profile_sensitive AS s
       SET seeking_enc = private.dating_field_encrypt(jsonb_build_object('seeking', to_jsonb(v_seeking))),
           updated_at = now()
     WHERE s.user_id = v_user;
    INSERT INTO public.dating_preferences AS d (user_id, min_age, max_age)
    VALUES (v_user, p_min_age, p_max_age)
    ON CONFLICT (user_id) DO UPDATE SET min_age = EXCLUDED.min_age, max_age = EXCLUDED.max_age, updated_at = now();
    -- B8 I-2: not plain now: unsafe other countries go (safe ones stay).
    IF private.dating_profile_plain(v_identity, jsonb_build_object('seeking', to_jsonb(v_seeking))) IS NOT TRUE THEN
      PERFORM private.dating_prune_unsafe_abroad(v_user);
    END IF;
    PERFORM private.bump_metric_internal('dating.setup.step.d6');
  EXCEPTION WHEN raise_exception THEN
    -- An unreadable value or a missing key (D6): unavailable, and the
    -- block's claim, rows and counters are undone (batch-6 carry).
    IF SQLERRM IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
    END IF;
    RAISE;
  END;
  RETURN jsonb_build_object('ok', true, 'next_step', 'children');
END;
$fn$;

-- D7: children (no option to seek parents, §3.2, 10 S22).
CREATE OR REPLACE FUNCTION public.save_dating_children(p_idempotency_key text, p_have boolean, p_want text,
  p_must_match boolean, p_exclude_parents boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_ages integer[];
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  IF p_have IS NULL THEN
    RETURN private.dating_invalid('have');
  END IF;
  IF p_want IS NULL OR p_want NOT IN ('yes', 'no', 'open') THEN
    RETURN private.dating_invalid('want');
  END IF;
  IF NOT public.claim_dating_idempotency('save_dating_children', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true, 'next_step', 'faith');
  END IF;

  IF private.dating_ensure_profile(v_user) THEN
    PERFORM private.bump_metric_internal('dating.setup.started');
  END IF;
  UPDATE public.dating_profiles AS p SET children_have = p_have, children_want = p_want, updated_at = now()
   WHERE p.user_id = v_user;
  v_ages := private.dating_default_ages(public.account_age(v_user));
  INSERT INTO public.dating_preferences AS d (user_id, min_age, max_age, want_must_match, exclude_parents)
  VALUES (v_user, v_ages[1], v_ages[2], coalesce(p_must_match, false), coalesce(p_exclude_parents, false))
  ON CONFLICT (user_id) DO UPDATE
    SET want_must_match = EXCLUDED.want_must_match, exclude_parents = EXCLUDED.exclude_parents, updated_at = now();
  PERFORM private.bump_metric_internal('dating.setup.step.d7');
  RETURN jsonb_build_object('ok', true, 'next_step', 'faith');
END;
$fn$;

-- D8: faith (optional): the country's list, how much sharing it matters.
CREATE OR REPLACE FUNCTION public.save_dating_faith(p_idempotency_key text, p_faith text, p_denomination text,
  p_importance text, p_visible boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_country text;
  v_faith jsonb;
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  IF private.dating_consent_granted(v_user, 'special_category_profile') IS NOT TRUE
     OR private.dating_consent_granted(v_user, 'special_category_faith') IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'consent_required');
  END IF;
  SELECT p.country_code INTO v_country FROM public.dating_profiles AS p WHERE p.user_id = v_user FOR UPDATE;
  SELECT f INTO v_faith FROM jsonb_array_elements((public.dating_country_config(v_country)).faith_list) AS f
   WHERE f ->> 'code' = p_faith;
  IF v_faith IS NULL THEN
    RETURN private.dating_invalid('faith');
  END IF;
  IF p_denomination IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(v_faith -> 'denominations', '[]'::jsonb)) AS d
                      WHERE d ->> 'code' = p_denomination) THEN
    RETURN private.dating_invalid('denomination');
  END IF;
  IF p_importance IS NULL OR p_importance NOT IN ('doesnt_matter', 'nice_to_share', 'must_share') THEN
    RETURN private.dating_invalid('importance');
  END IF;
  IF private.dating_field_key_present() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  BEGIN
    IF NOT public.claim_dating_idempotency('save_dating_faith', p_idempotency_key) THEN
      RETURN jsonb_build_object('ok', true, 'next_step', 'photos');
    END IF;

    IF private.dating_ensure_profile(v_user) THEN
      PERFORM private.bump_metric_internal('dating.setup.started');
    END IF;
    UPDATE public.dating_profile_sensitive AS s
       SET faith_enc = private.dating_field_encrypt(jsonb_build_object(
             'faith', p_faith, 'denomination', p_denomination, 'importance', p_importance)),
           updated_at = now()
     WHERE s.user_id = v_user;
    UPDATE public.dating_profiles AS p SET faith_visible = coalesce(p_visible, false), updated_at = now()
     WHERE p.user_id = v_user;
    PERFORM private.bump_metric_internal('dating.setup.step.d8');
  EXCEPTION WHEN raise_exception THEN
    -- An unreadable value or a missing key (D8): unavailable, and the
    -- block's claim, rows and counters are undone (batch-6 carry).
    IF SQLERRM IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
    END IF;
    RAISE;
  END;
  RETURN jsonb_build_object('ok', true, 'next_step', 'photos');
END;
$fn$;

-- D8 "Skip", or removing a faith answer later: nothing stays. Never gated
-- on eligibility or the device (W1 B7 ruling): removing one's own
-- sensitive data always works; a stolen device can do no more than Skip.
CREATE OR REPLACE FUNCTION public.clear_dating_faith(p_idempotency_key text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  PERFORM private.dating_lock_setup(v_user);
  IF NOT public.claim_dating_idempotency('clear_dating_faith', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true, 'next_step', 'photos');
  END IF;
  PERFORM private.dating_clear_faith(v_user);
  RETURN jsonb_build_object('ok', true, 'next_step', 'photos');
END;
$fn$;

REVOKE ALL ON FUNCTION private.dating_setup_guard(), private.dating_ensure_profile(uuid),
  private.dating_same_gender_on(text), private.dating_default_ages(integer), private.dating_invalid(text),
  private.dating_clear_faith(uuid), private.dating_lock_setup(uuid), private.dating_lock_same_gender(text),
  private.dating_lock_same_gender_all(text[]), private.dating_profile_plain(jsonb, jsonb),
  private.dating_prune_unsafe_abroad(uuid), private.dating_lock_setup(uuid, text[])
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  public.save_dating_intention(text, text, text, boolean, boolean, text, boolean),
  public.save_dating_location(text, text, text, text, text),
  public.save_dating_identity(text, text, text, text, text[], boolean),
  public.save_dating_who_to_meet(text, text[], integer, integer),
  public.save_dating_children(text, boolean, text, boolean, boolean),
  public.save_dating_faith(text, text, text, text, boolean),
  public.clear_dating_faith(text)
  FROM PUBLIC, anon, service_role;
-- The writers are the signed-in app's only: the service role runs none
-- (S-4: hosted projects grant new functions to the service role by
-- default; the two that decrypt, D5 and D6, above all; batch-2 carry).
GRANT EXECUTE ON FUNCTION
  public.save_dating_intention(text, text, text, boolean, boolean, text, boolean),
  public.save_dating_location(text, text, text, text, text),
  public.save_dating_identity(text, text, text, text, text[], boolean),
  public.save_dating_who_to_meet(text, text[], integer, integer),
  public.save_dating_children(text, boolean, text, boolean, boolean),
  public.save_dating_faith(text, text, text, text, boolean),
  public.clear_dating_faith(text)
  TO authenticated;

COMMIT;
