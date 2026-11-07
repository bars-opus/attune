-- Spec 2 W1c, migration 8 (spec §4.9 W1c #1, part 3 of 3: the remaining
-- setup writers and the two own-profile readers; §3.2, §3.4, §3.12, §4.4):
--   save_dating_prompts (D10: 2-3 answers, 10-200 characters, Spec 1's
--   pre-post filter private.content_filter_verdict: contact details ->
--   contact_details, slurs or explicit -> unkind), save_dating_display_name
--   (D12: 1-30 characters, no control character, the same filter),
--   save_dating_family_involvement, save_dating_settings (drop time, data
--   saver, digest and chat pushes, show when away), set_dating_open_abroad
--   (verified, the age gate and 14+ days old, open countries other than
--   one's own), set_dating_photos_after_mutual (from account day 30);
--   get_my_dating_profile() (own, decrypted) and get_dating_profile_preview()
--   (exactly what others see: never who you'd like to meet, the side, the
--   DOB or hidden fields; no photo while photos wait for mutual interest).
-- Same order of checks as migration 7 (signed in, the setup lock, device,
-- eligibility, validation, then the idempotency claim). Counters: d10,
-- d12, and dating.setup.started when a step creates the profile (as D2,
-- D3, D7, D8).
-- Batch 8 (rulings):
--   NULL is never valid and every comparison is NULL-safe (IS NOT TRUE /
--   IS DISTINCT FROM / coalesce), so a NULL never passes a check.
--   Writers pre-validate everything a constraint could refuse (types,
--   lengths, codes, array shape), so no raw constraint error can echo a
--   person's input in DETAIL; the only raises are the fixed-message 42501
--   (not_authenticated) and 22023 (a malformed idempotency key).
--   Every free-text field (prompt answers, the name) goes through
--   private.content_filter_verdict with every family, as Task 9.
--   Locks, in Task 9's order: the person's setup lock (in the guard), then
--   the profile row FOR UPDATE where a decision reads it (other
--   countries). No writer here decides same-gender, so none takes the
--   country's same-gender lock.
--   The readers decrypt the caller's own row only; dating:field_decrypt_failed
--   and dating:field_key_missing answer unavailable (batch-6 carry), never
--   a raise. The preview lists no photo (id or path) while photos wait for
--   mutual interest, and never a storage path (§3.4, D9).
-- Batch 8 fix round 1 (W1 B8 rulings and review):
--   I-1: exposure-reducing changes are never gated by the setup guard:
--   closing other countries (a subset of the stored list), pushes and
--   show-when-away off, data saver on, photos after mutual interest on.
--   They keep sign-in, the setup lock, validation, the claim (and day 30
--   for photos), and touch only rows of an existing Dating profile.
--   I-2: other countries never include a country whose same-gender rule
--   excludes the person's profile (not plain -> not_available); locks:
--   setup, then the shared same-gender locks sorted, then the row.
--   M-1: names and answers are trimmed of Unicode white space and refused
--   with invisible or bidi controls; a name needs a letter, an answer a
--   letter or digit. M-2: settings need a Dating profile.
-- W1 final fix (I-1): set_dating_open_abroad passes its new list to the
--   setup lock, which takes every same-gender lock in one sorted pass.
-- Grants in 20261106170010_dating_v2_profile_readers_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- M-1: trims Unicode white space at both ends ([[:space:]] under
-- pg_c_utf8 holds U+00A0 and U+3000, which btrim keeps), and finds the invisible format and bidi controls (zero-width
-- U+200B-U+200F, U+2060-U+2069 isolates, U+202A-U+202E embeddings and
-- overrides, U+FEFF) that no name or answer may hold.
CREATE OR REPLACE FUNCTION private.dating_trim(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT regexp_replace(p_text COLLATE "pg_c_utf8", '^[[:space:]]+|[[:space:]]+$', '', 'g');
$fn$;

CREATE OR REPLACE FUNCTION private.dating_has_invisible(p_text text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT coalesce(p_text ~ '[\u200b-\u200f\u202a-\u202e\u2060-\u2069\ufeff]', true);
$fn$;

-- D10: two required answers, a third optional.
CREATE OR REPLACE FUNCTION public.save_dating_prompts(p_idempotency_key text, p_items jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_item record;
  v_verdict text;
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  -- The shape first (a non-array would make the array functions raise).
  IF jsonb_typeof(p_items) IS DISTINCT FROM 'array' THEN
    RETURN private.dating_invalid('prompts');
  END IF;
  IF jsonb_array_length(p_items) NOT BETWEEN 2 AND 3 THEN
    RETURN private.dating_invalid('prompts');
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_items) AS i
              WHERE coalesce(i ->> 'prompt_id', '') NOT IN ('perfect_sunday', 'feel_at_home', 'friends_say', 'looking_for',
                      'small_thing', 'win_me_over', 'learning_to', 'family_describe', 'place_love', 'ask_me_about'))
     OR (SELECT count(DISTINCT i ->> 'prompt_id') FROM jsonb_array_elements(p_items) AS i)
          IS DISTINCT FROM jsonb_array_length(p_items)::bigint THEN
    RETURN private.dating_invalid('prompts');
  END IF;
  FOR v_item IN SELECT o AS position,
                       CASE WHEN jsonb_typeof(i -> 'answer') = 'string' THEN private.dating_trim(i ->> 'answer') END AS answer
                  FROM jsonb_array_elements(p_items) WITH ORDINALITY AS x(i, o) ORDER BY o LOOP
    IF (char_length(v_item.answer) BETWEEN 10 AND 200) IS NOT TRUE
       OR private.dating_has_invisible(v_item.answer)
       OR NOT coalesce((v_item.answer COLLATE "pg_c_utf8") ~ '[[:alnum:]]', false) THEN
      RETURN private.dating_invalid('answer') || jsonb_build_object('position', v_item.position);
    END IF;
    v_verdict := private.content_filter_verdict(v_item.answer, NULL);
    IF v_verdict IS NOT NULL THEN
      RETURN jsonb_build_object('ok', false,
        'reason', CASE WHEN v_verdict = 'contact_info' THEN 'contact_details' ELSE 'unkind' END,
        'position', v_item.position);
    END IF;
  END LOOP;
  IF NOT public.claim_dating_idempotency('save_dating_prompts', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true, 'next_step', 'verify');
  END IF;

  IF private.dating_ensure_profile(v_user) THEN
    PERFORM private.bump_metric_internal('dating.setup.started');
  END IF;
  DELETE FROM public.dating_prompts AS d WHERE d.user_id = v_user;
  INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer)
  SELECT v_user, o, i ->> 'prompt_id', private.dating_trim(i ->> 'answer')
    FROM jsonb_array_elements(p_items) WITH ORDINALITY AS x(i, o);
  PERFORM private.bump_metric_internal('dating.setup.step.d10');
  RETURN jsonb_build_object('ok', true, 'next_step', 'verify');
END;
$fn$;

-- D12: the first name others see.
CREATE OR REPLACE FUNCTION public.save_dating_display_name(p_idempotency_key text, p_name text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_name constant text := private.dating_trim(p_name);
  v_verdict text;
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  IF (char_length(v_name) BETWEEN 1 AND 30) IS NOT TRUE
     OR coalesce((v_name COLLATE "pg_c_utf8") ~ '[[:cntrl:]]', true)
     OR private.dating_has_invisible(v_name)
     OR NOT coalesce((v_name COLLATE "pg_c_utf8") ~ '[[:alpha:]]', false) THEN
    RETURN private.dating_invalid('name');
  END IF;
  -- Every family (contact details, slurs, explicit), as the default name.
  v_verdict := private.content_filter_verdict(v_name, NULL);
  IF v_verdict IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', CASE WHEN v_verdict = 'contact_info' THEN 'contact_details' ELSE 'unkind' END);
  END IF;
  IF NOT public.claim_dating_idempotency('save_dating_display_name', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true, 'next_step', 'preview');
  END IF;
  IF private.dating_ensure_profile(v_user) THEN
    PERFORM private.bump_metric_internal('dating.setup.started');
  END IF;
  UPDATE public.dating_profiles AS p SET display_name = v_name, updated_at = now() WHERE p.user_id = v_user;
  PERFORM private.bump_metric_internal('dating.setup.step.d12');
  RETURN jsonb_build_object('ok', true, 'next_step', 'preview');
END;
$fn$;

-- The family question (§3.4; shared ground only, never shown as a field).
CREATE OR REPLACE FUNCTION public.save_dating_family_involvement(p_idempotency_key text, p_value text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  -- NULL clears the answer (the question is optional).
  IF p_value IS NOT NULL AND p_value NOT IN ('early', 'when_serious', 'our_decision') THEN
    RETURN private.dating_invalid('family_involvement');
  END IF;
  IF NOT public.claim_dating_idempotency('save_dating_family_involvement', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true);
  END IF;
  IF private.dating_ensure_profile(v_user) THEN
    PERFORM private.bump_metric_internal('dating.setup.started');
  END IF;
  UPDATE public.dating_profiles AS p SET family_involvement = p_value, updated_at = now() WHERE p.user_id = v_user;
  RETURN jsonb_build_object('ok', true);
END;
$fn$;

-- Dating settings (§3.12, D12, D13): any subset of the five keys.
-- B8 I-1 (W1 B8 ruling): a change that only reduces exposure (every key
-- one of digest_push false, chat_push false, show_when_away false,
-- data_saver true) is never gated by the setup guard: signed in, the
-- setup lock, the claim, and only rows that exist for a Dating profile.
CREATE OR REPLACE FUNCTION public.save_dating_settings(p_idempotency_key text, p_values jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_drop time;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  PERFORM private.dating_lock_setup(v_user);
  IF jsonb_typeof(p_values) IS NOT DISTINCT FROM 'object'
     AND NOT EXISTS (SELECT 1 FROM jsonb_each(p_values) AS e
                      WHERE e.key || '=' || e.value::text NOT IN
                            ('digest_push=false', 'chat_push=false', 'show_when_away=false', 'data_saver=true')) THEN
    IF NOT public.claim_dating_idempotency('save_dating_settings', p_idempotency_key) THEN
      RETURN jsonb_build_object('ok', true);
    END IF;
    INSERT INTO public.dating_settings AS s (user_id)
    SELECT v_user WHERE EXISTS (SELECT 1 FROM public.dating_profiles AS p WHERE p.user_id = v_user)
    ON CONFLICT (user_id) DO NOTHING;
    UPDATE public.dating_settings AS s
       SET digest_push = CASE WHEN p_values ? 'digest_push' THEN false ELSE s.digest_push END,
           chat_push = CASE WHEN p_values ? 'chat_push' THEN false ELSE s.chat_push END,
           show_when_away = CASE WHEN p_values ? 'show_when_away' THEN false ELSE s.show_when_away END,
           data_saver = CASE WHEN p_values ? 'data_saver' THEN true ELSE s.data_saver END,
           updated_at = now()
     WHERE s.user_id = v_user;
    RETURN jsonb_build_object('ok', true);
  END IF;

  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  -- The shape first (a non-object would make the object functions raise).
  IF jsonb_typeof(p_values) IS DISTINCT FROM 'object' THEN
    RETURN private.dating_invalid('settings');
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_values) AS k
              WHERE k NOT IN ('drop_time', 'data_saver', 'digest_push', 'chat_push', 'show_when_away'))
     OR EXISTS (SELECT 1 FROM jsonb_each(p_values) AS e
                 WHERE e.key <> 'drop_time' AND jsonb_typeof(e.value) IS DISTINCT FROM 'boolean') THEN
    RETURN private.dating_invalid('settings');
  END IF;
  IF p_values ? 'drop_time' THEN
    IF NOT coalesce((p_values ->> 'drop_time') ~ '^([01][0-9]|2[0-3]):(00|30)$', false) THEN
      RETURN private.dating_invalid('drop_time');
    END IF;
    v_drop := (p_values ->> 'drop_time')::time;
    IF (v_drop BETWEEN '07:00' AND '22:00') IS NOT TRUE THEN
      RETURN private.dating_invalid('drop_time');
    END IF;
  END IF;
  -- M-2: settings belong to a Dating profile (never a row without one).
  IF NOT EXISTS (SELECT 1 FROM public.dating_profiles AS p WHERE p.user_id = v_user) THEN
    RETURN private.dating_invalid('profile');
  END IF;
  IF NOT public.claim_dating_idempotency('save_dating_settings', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true);
  END IF;
  INSERT INTO public.dating_settings AS s (user_id) VALUES (v_user) ON CONFLICT (user_id) DO NOTHING;
  UPDATE public.dating_settings AS s
     SET drop_time = coalesce(v_drop, s.drop_time),
         data_saver = coalesce((p_values ->> 'data_saver')::boolean, s.data_saver),
         digest_push = coalesce((p_values ->> 'digest_push')::boolean, s.digest_push),
         chat_push = coalesce((p_values ->> 'chat_push')::boolean, s.chat_push),
         show_when_away = coalesce((p_values ->> 'show_when_away')::boolean, s.show_when_away),
         updated_at = now()
   WHERE s.user_id = v_user;
  RETURN jsonb_build_object('ok', true);
END;
$fn$;

-- "Other countries" (§2.6, §3.12): only for verified accounts that pass
-- the age gate and are at least 14 days old, only open countries other
-- than one's own, and (B8 I-2) never a country whose same-gender rule
-- excludes the person's profile: a profile that is not plain (woman or
-- man, nothing more, meeting only the opposite; unreadable counts as not
-- plain) is not_available for a same-gender-off country (§2.4: raised by
-- nothing, claimed, stored and counted nowhere).
-- B8 I-1 (W1 B8 ruling): keeping a subset of the stored list (closing some
-- or all) is never gated: signed in, the setup lock, the row lock, the
-- claim; the stored list is only ever narrowed.
CREATE OR REPLACE FUNCTION public.set_dating_open_abroad(p_idempotency_key text, p_countries char(2)[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_own text;
  v_verification text;
  v_list char(2)[];
  v_stored char(2)[];
  v_identity jsonb;
  v_seeking jsonb;
  -- A parameter of type char(2)[] carries no length: each element is
  -- checked as given (never cut to two letters), and none is NULL.
  v_shape constant boolean := p_countries IS NOT NULL AND cardinality(p_countries) <= 10
    AND NOT EXISTS (SELECT 1 FROM unnest(p_countries) AS c WHERE NOT coalesce(upper(c::text) ~ '^[A-Z]{2}$', false));
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  -- W1 final fix (I-1): the new list's same-gender locks are taken with the
  -- setup lock, in one sorted pass before any row (never added out of order).
  PERFORM private.dating_lock_setup(v_user, CASE WHEN v_shape -- W1 final fix (I-1)
    THEN ARRAY(SELECT DISTINCT upper(c::text) FROM unnest(p_countries) AS c) END); -- W1 final fix (I-1)
  IF v_shape THEN
    v_list := ARRAY(SELECT DISTINCT upper(c::text)::char(2) FROM unnest(p_countries) AS c ORDER BY 1);
    -- Read under the setup lock only: a row lock here would come before the
    -- full path's same-gender locks (the shared order is setup, same-gender,
    -- row). The write below only ever narrows the stored list, so a
    -- country removed meanwhile (Task 13's switch) is never put back.
    SELECT d.open_abroad INTO v_stored FROM public.dating_preferences AS d WHERE d.user_id = v_user;
    IF cardinality(v_list) = 0 OR coalesce(v_list <@ v_stored, false) THEN
      PERFORM 1 FROM public.dating_profiles AS p WHERE p.user_id = v_user FOR UPDATE;
      IF NOT public.claim_dating_idempotency('set_dating_open_abroad', p_idempotency_key) THEN
        RETURN jsonb_build_object('ok', true);
      END IF;
      UPDATE public.dating_preferences AS d
         SET open_abroad = ARRAY(SELECT c FROM unnest(d.open_abroad) AS c WHERE c = ANY (v_list) ORDER BY c),
             updated_at = now()
       WHERE d.user_id = v_user AND NOT (d.open_abroad <@ v_list);
      RETURN jsonb_build_object('ok', true);
    END IF;
  END IF;

  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  IF NOT v_shape THEN
    RETURN private.dating_invalid('countries');
  END IF;
  -- B8 I-2: the shared same-gender locks of the Dating country and every
  -- target (sorted), then the profile row; the setup lock keeps the
  -- country stable while it is read for the locks.
  SELECT p.country_code INTO v_own FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  PERFORM private.dating_lock_same_gender_all(ARRAY[v_own] || v_list::text[]);
  SELECT p.country_code, p.verification_state INTO v_own, v_verification
    FROM public.dating_profiles AS p WHERE p.user_id = v_user FOR UPDATE;
  IF v_own IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.dating_preferences AS d WHERE d.user_id = v_user)
     OR EXISTS (SELECT 1 FROM unnest(v_list) AS c
                 WHERE c::text = v_own OR (public.dating_country_config(c::text)).dating_enabled IS NOT TRUE) THEN
    RETURN private.dating_invalid('countries');
  END IF;
  IF v_verification IS DISTINCT FROM 'verified'
     OR public.dating_age_gate_holds(v_user) IS NOT TRUE
     OR coalesce((SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) > now() - interval '14 days', true) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_yet');
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_list) AS c WHERE private.dating_same_gender_on(c::text) IS NOT TRUE) THEN
    BEGIN
      SELECT private.dating_field_decrypt(s.identity_enc), private.dating_field_decrypt(s.seeking_enc)
        INTO v_identity, v_seeking
        FROM public.dating_profile_sensitive AS s WHERE s.user_id = v_user;
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
      END IF;
      RAISE;
    END;
    IF private.dating_profile_plain(v_identity, v_seeking) IS NOT TRUE THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'not_available');
    END IF;
  END IF;
  IF NOT public.claim_dating_idempotency('set_dating_open_abroad', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true);
  END IF;
  UPDATE public.dating_preferences AS d SET open_abroad = v_list, updated_at = now() WHERE d.user_id = v_user;
  RETURN jsonb_build_object('ok', true);
END;
$fn$;

-- "Show my photos only after we're both interested" (D9): from account day
-- 30. B8 I-1 (W1 B8 ruling): turning it on reduces exposure, so it is
-- never gated by the setup guard (signed in, the setup lock, day 30, the
-- claim, an existing profile only); turning it off is the full step.
CREATE OR REPLACE FUNCTION public.set_dating_photos_after_mutual(p_idempotency_key text, p_on boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  PERFORM private.dating_lock_setup(v_user);
  IF p_on IS TRUE THEN
    IF coalesce((SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) > now() - interval '30 days', true) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'not_yet');
    END IF;
    IF NOT public.claim_dating_idempotency('set_dating_photos_after_mutual', p_idempotency_key) THEN
      RETURN jsonb_build_object('ok', true);
    END IF;
    UPDATE public.dating_profiles AS p SET photos_after_mutual = true, updated_at = now()
     WHERE p.user_id = v_user AND NOT p.photos_after_mutual;
    RETURN jsonb_build_object('ok', true);
  END IF;

  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  IF p_on IS NULL THEN
    RETURN private.dating_invalid('on');
  END IF;
  IF NOT public.claim_dating_idempotency('set_dating_photos_after_mutual', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true);
  END IF;
  IF private.dating_ensure_profile(v_user) THEN
    PERFORM private.bump_metric_internal('dating.setup.started');
  END IF;
  UPDATE public.dating_profiles AS p SET photos_after_mutual = false, updated_at = now() WHERE p.user_id = v_user;
  RETURN jsonb_build_object('ok', true);
END;
$fn$;

-- The person's own Dating profile, decrypted (setup resume, settings).
-- Only the caller's own rows (auth.uid()) are ever read.
CREATE OR REPLACE FUNCTION public.get_my_dating_profile()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_p public.dating_profiles;
  v_s public.dating_profile_sensitive;
  v_d public.dating_preferences;
  v_t public.dating_settings;
  v_identity jsonb;
  v_seeking jsonb;
  v_faith jsonb;
  v_marital jsonb;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  SELECT * INTO v_p FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'profile', NULL);
  END IF;
  SELECT * INTO v_s FROM public.dating_profile_sensitive AS s WHERE s.user_id = v_user;
  -- Redundant with the handler below (decrypt raises field_key_missing,
  -- mapped to unavailable); kept only to avoid decrypting (review M-4).
  IF num_nonnulls(v_s.identity_enc, v_s.seeking_enc, v_s.faith_enc, v_s.marital_enc) > 0
     AND private.dating_field_key_present() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  BEGIN
    v_identity := private.dating_field_decrypt(v_s.identity_enc);
    v_seeking := private.dating_field_decrypt(v_s.seeking_enc);
    v_faith := private.dating_field_decrypt(v_s.faith_enc);
    v_marital := private.dating_field_decrypt(v_s.marital_enc);
  EXCEPTION WHEN raise_exception THEN
    -- An unreadable value or a key lost after the check (batch-6 carry).
    IF SQLERRM IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
    END IF;
    RAISE;
  END;
  SELECT * INTO v_d FROM public.dating_preferences AS d WHERE d.user_id = v_user;
  SELECT * INTO v_t FROM public.dating_settings AS t WHERE t.user_id = v_user;
  RETURN jsonb_build_object('ok', true, 'profile', jsonb_build_object(
    'display_name', v_p.display_name,
    'country_code', v_p.country_code, 'region_code', v_p.region_code, 'side_code', v_p.side_code,
    'intention', v_p.intention, 'marriage_timeline', v_p.marriage_timeline, 'timeline_visible', v_p.timeline_visible,
    'attested', v_p.not_married_attested_at IS NOT NULL,
    'children_have', v_p.children_have, 'children_want', v_p.children_want,
    'family_involvement', v_p.family_involvement,
    'gender_visible', v_p.gender_visible, 'faith_visible', v_p.faith_visible, 'marital_visible', v_p.marital_visible,
    'photos_after_mutual', v_p.photos_after_mutual,
    'identity', v_identity,
    'seeking', v_seeking -> 'seeking',
    'faith', v_faith,
    'marital', v_marital ->> 'marital',
    'preferences', CASE WHEN v_d.user_id IS NULL THEN NULL ELSE jsonb_build_object(
      'min_age', v_d.min_age, 'max_age', v_d.max_age, 'region_scope', v_d.region_scope,
      'open_abroad', to_jsonb(v_d.open_abroad), 'want_must_match', v_d.want_must_match,
      'exclude_parents', v_d.exclude_parents) END,
    'settings', jsonb_build_object(
      'drop_time', to_char(coalesce(v_t.drop_time, '19:00'::time), 'HH24:MI'),
      'data_saver', coalesce(v_t.data_saver, false), 'digest_push', coalesce(v_t.digest_push, false),
      'chat_push', coalesce(v_t.chat_push, true), 'show_when_away', coalesce(v_t.show_when_away, false)),
    'prompts', coalesce((SELECT jsonb_agg(jsonb_build_object('position', q.position, 'prompt_id', q.prompt_id,
                                                             'answer', q.answer) ORDER BY q.position)
                           FROM public.dating_prompts AS q
                          WHERE q.user_id = v_user AND q.moderation_state = 'approved'), '[]'::jsonb)));
END;
$fn$;

-- D12: exactly what others will see on the introduction card (§3.4):
-- name, age (never the DOB), region (never the side), intention (with the
-- timeline only if shown), children, prompts, approved photo slots (none
-- while photos wait for mutual interest, D9; never a storage path), and
-- gender, pronouns, faith and "Divorced" / "Widowed" only if shown.
CREATE OR REPLACE FUNCTION public.get_dating_profile_preview()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_p public.dating_profiles;
  v_s public.dating_profile_sensitive;
  v_identity jsonb;
  v_faith jsonb;
  v_marital text;
  v_region jsonb;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  SELECT * INTO v_p FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'card', NULL);
  END IF;
  SELECT * INTO v_s FROM public.dating_profile_sensitive AS s WHERE s.user_id = v_user;
  IF (v_p.gender_visible OR v_p.faith_visible OR v_p.marital_visible) AND private.dating_field_key_present() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  BEGIN
    IF v_p.gender_visible THEN
      v_identity := private.dating_field_decrypt(v_s.identity_enc);
    END IF;
    IF v_p.faith_visible THEN
      v_faith := private.dating_field_decrypt(v_s.faith_enc);
    END IF;
    IF v_p.marital_visible THEN
      v_marital := private.dating_field_decrypt(v_s.marital_enc) ->> 'marital';
    END IF;
  EXCEPTION WHEN raise_exception THEN
    -- An unreadable value or a key lost after the check (batch-6 carry).
    IF SQLERRM IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
    END IF;
    RAISE;
  END;
  SELECT r INTO v_region FROM jsonb_array_elements((public.dating_country_config(v_p.country_code)).region_list) AS r
   WHERE r ->> 'code' = v_p.region_code;
  RETURN jsonb_build_object('ok', true, 'card', jsonb_build_object(
    'display_name', v_p.display_name,
    'age', public.account_age(v_user),
    'region_code', v_p.region_code,
    'region_name_key', v_region ->> 'name_key',
    'intention', v_p.intention,
    'marriage_timeline', CASE WHEN v_p.intention = 'marriage' AND v_p.timeline_visible THEN v_p.marriage_timeline END,
    'children_have', v_p.children_have,
    'children_want', v_p.children_want,
    'gender', CASE WHEN v_identity IS NULL THEN NULL ELSE jsonb_build_object(
      'identity', v_identity ->> 'identity', 'specific', v_identity ->> 'specific',
      'specific_text', v_identity ->> 'specific_text') END,
    'pronouns', v_identity ->> 'pronouns',
    'faith', CASE WHEN v_faith IS NULL THEN NULL ELSE jsonb_build_object(
      'faith', v_faith ->> 'faith', 'denomination', v_faith ->> 'denomination') END,
    'marital', CASE WHEN v_marital IN ('divorced', 'widowed') THEN v_marital END,
    'prompts', coalesce((SELECT jsonb_agg(jsonb_build_object('prompt_id', q.prompt_id, 'answer', q.answer)
                                          ORDER BY q.position)
                           FROM public.dating_prompts AS q
                          WHERE q.user_id = v_user AND q.moderation_state = 'approved'), '[]'::jsonb),
    -- D9: while photos wait for mutual interest, others see none (and so
    -- does the preview); the card says they are coming.
    'photos_after_mutual', v_p.photos_after_mutual,
    'photos', CASE WHEN v_p.photos_after_mutual THEN '[]'::jsonb ELSE
      coalesce((SELECT jsonb_agg(jsonb_build_object('id', f.id, 'position', f.position) ORDER BY f.position)
                  FROM public.dating_profile_photos AS f
                 WHERE f.user_id = v_user AND f.moderation_state = 'approved'), '[]'::jsonb) END));
END;
$fn$;

REVOKE ALL ON FUNCTION
  public.save_dating_prompts(text, jsonb), public.save_dating_display_name(text, text),
  public.save_dating_family_involvement(text, text), public.save_dating_settings(text, jsonb),
  public.set_dating_open_abroad(text, char(2)[]), public.set_dating_photos_after_mutual(text, boolean),
  public.get_my_dating_profile(), public.get_dating_profile_preview()
  FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION private.dating_trim(text), private.dating_has_invisible(text)
  FROM PUBLIC, anon, authenticated, service_role;
-- The writers are the signed-in app's only, and the two readers decrypt:
-- no one but the person (S-4; hosted projects grant new functions to the
-- service role by default; batch-2 carry).
GRANT EXECUTE ON FUNCTION
  public.save_dating_prompts(text, jsonb), public.save_dating_display_name(text, text),
  public.save_dating_family_involvement(text, text), public.save_dating_settings(text, jsonb),
  public.set_dating_open_abroad(text, char(2)[]), public.set_dating_photos_after_mutual(text, boolean),
  public.get_my_dating_profile(), public.get_dating_profile_preview()
  TO authenticated;

COMMIT;
