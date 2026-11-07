-- Spec 2 W1d, migration 11 (spec §4.9 W1d #2, the kill switch; §2.2,
-- §2.4; 10 S3; plan P-20, P-37):
--   * apply_same_gender_switch(country) (NULL = every country): under each
--     affected country's EXCLUSIVE same-gender lock (taken first, in
--     COLLATE "C" code order, before any row is read or locked; batch-7
--     carry), for every person whose Dating country no longer allows
--     same-gender introductions (the country's switch or the global flag)
--     the disallowed answers are deleted: a specific term, pronouns and
--     extra pools are stripped from a woman/man identity (re-encrypted as
--     the plain base; batch-11 fix round 1, M-4), any other identity is
--     deleted, and who-to-meet goes unless it is exactly the opposite single
--     set of what remains; gender_visible goes off when the identity
--     changed, and the person is paused with same_gender_switch (an
--     enrolment already paused keeps its first reason). Someone there with
--     no stored identity who is in an open introduction or an active match
--     is paused too (fix round 1, I-3: an unknown pair is never "man-woman").
--     Rows are locked enrolment,
--     then sensitive, then profile (the shared order; batch-10 carry). An
--     unreadable sensitive row is "not plain woman/man": the restrictive
--     path, counted (dating.kill_switch.unreadable), never an abort
--     (batch-6 I-3). Then the switched countries leave every not-plain
--     person's other-countries list (batch-8 I-2c), every open
--     introduction with a member there that is not man-woman is
--     invalidated, and every active match with a member there that is not
--     man-woman is closed ('other', sealed 30 days; owner ruling
--     2026-11-06, PF-F2) (both by the members' answers as they were before
--     the switch, cross-border included; only a pair known to be man-woman
--     is kept: an unreadable or missing identity closes, fix round 1, I-3).
--     Returns the number of people changed, and clears the pending marker of
--     what it switched. Needs a usable field key (raises
--     dating:field_key_missing with no key, dating:field_key_not_ready with
--     a replaced or unseeded one: a key that can't read the answers never
--     wipes them). Never sends anything (no push, no notice to anyone; W3a's
--     note reads pause_reason).
--   * private.dating_kill_switch_pending (fix round 1, I-1): one row per
--     scope (a country, or '*' for the global flag) whose purge failed, set
--     on failure and cleared only by a switch that completes; health lists
--     it until then. A deadlock, a lock timeout or a serialization failure
--     is retried up to three times first (fix round 1, I-2).
--   * country_config_checks re-created from its live body (W1b,
--     20261106140000): Dating opens only under a field key whose stored
--     fingerprint matches (field_key_not_ready; batch-10 carry).
--   * publish_country_config re-created from its live body (W1b,
--     20261106130000 + batch-4 fix round 1): turning same_gender_enabled
--     off now publishes and runs the switch in the same transaction instead
--     of refusing; if the purge can't run the switch is still published, the
--     answer says affected: null with the pending_sqlstate, the country's
--     pending row is set and dating.kill_switch.pending counts it, so the
--     owner re-runs select public.apply_same_gender_switch('<code>');.
--     An exposure-reducing publish (closing, narrowing regions, tightening
--     the tier, same-gender off; nothing widened, no ID document added) is
--     never refused for the production checks or a missing calling code:
--     the checks are still returned (PF-F1, batch-5 M-3).
--   * The global flag: turning dating_same_gender_matching off (or renaming,
--     deleting or truncating its row) runs the switch for every country,
--     through AFTER triggers on public.feature_flags that fire for that one
--     key only and never block the flag change (a failed purge sets the '*'
--     pending row, WARNs and counts; re-run it).
--   * exit_dating_mode re-created from its live body (20261106190000): the
--     hard delete is retried on a deadlock, a lock timeout or a
--     serialization failure (fix round 1, I-2, M-7), so leaving during a
--     switch never fails.
--   * get_dating_operational_health re-created from its live body
--     (20261106190000): the two kill-switch counters and the pending list.
--   * W1 final fix (I-1, M-3): every Dating writer now takes the person's
--     same-gender locks shared, with the setup lock, before any row
--     (private.dating_lock_setup, migration 7), so a same-country switch and
--     a writer serialise. What a cross-border pair can still interleave is
--     retried: invalidate_dating_for_user (re-created from its live body,
--     20260712130000) retries its three statements on a deadlock, a lock
--     timeout or a serialization failure (three attempts, each its own
--     savepoint; the third is dating:busy with the original SQLSTATE), and
--     exit's third failure is dating:busy too (never the raw DETAIL). No
--     loop retries an inner dating:busy, so attempts never multiply (N-M3).
--     save_dating_location (D3) is re-created from its live body (migration
--     7): the new country's lock is taken with the setup lock (old, new and
--     other countries in one sorted pass), and its writes retry the same way.
--     The account-deletion trigger dating_carry_on_auth_user_delete
--     (re-created from migration 3) takes the person's locks before the
--     cascade reaches their rows.
--   * W1 final fix (M-2): moving one's Dating country into a country whose
--     same-gender rule is off gives the kill switch's restrictive treatment
--     to the mover's pairs not known to be man-woman (by the answers held
--     before the move; unreadable or missing is not): active matches close
--     ('other', sealed 30 days), open introductions end, and the mover is
--     paused (same_gender_switch) as the switch would pause them: their
--     answers are not allowed there, or they had no answer and were in a
--     pair. Nobody is told.
--   * W1 final fix (M-7): a later downgrade needs a new tier_review
--     reference (the previous one never covers it).
--   * W1 final fix (M-9, N-I1): save_dating_profile_draft and the v1 photo
--     writers create_dating_photo_upload_intent and
--     insert_dating_profile_photo are revoked from every API role (no Dating
--     upload until W3's writers and W3c's inline CSAM match).
--   * W1 final fix (M-4): health counts a deletion's failed carry at prepare
--     and at the delete, and the deletions refused for a missing key.
-- Grants in 20261106200010_dating_v2_kill_switch_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- Fix round 1, I-1: a purge that failed, as state (not a counter that only
-- grows): set on failure, cleared only by a switch that completes.
CREATE TABLE IF NOT EXISTS private.dating_kill_switch_pending (
  scope text PRIMARY KEY CHECK (scope = '*' OR scope ~ '^[A-Z]{2}$'),
  first_failed_at timestamptz NOT NULL DEFAULT now(),
  last_failed_at timestamptz NOT NULL DEFAULT now(),
  last_sqlstate text NOT NULL CHECK (last_sqlstate ~ '^[0-9A-Z]{5}$'),
  attempts integer NOT NULL DEFAULT 1 CHECK (attempts >= 1)
);
ALTER TABLE private.dating_kill_switch_pending ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.dating_kill_switch_pending FROM PUBLIC, anon, authenticated, service_role;

-- Records a failed purge for [p_scope] (a country code, or NULL for every
-- country), counted; never raises.
CREATE OR REPLACE FUNCTION private.dating_kill_switch_mark(p_scope text, p_sqlstate text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  PERFORM private.bump_metric_internal('dating.kill_switch.pending');
  INSERT INTO private.dating_kill_switch_pending AS k (scope, last_sqlstate)
  VALUES (coalesce(p_scope, '*'), CASE WHEN p_sqlstate ~ '^[0-9A-Z]{5}$' THEN p_sqlstate ELSE 'XX000' END)
  ON CONFLICT (scope) DO UPDATE SET last_failed_at = now(), last_sqlstate = EXCLUDED.last_sqlstate,
                                    attempts = k.attempts + 1;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'dating_kill_switch_mark:%', SQLSTATE;
END;
$fn$;

-- One sensitive value, decrypted; an unreadable one is reported, never
-- raised (batch-6 I-3). Any other error still raises.
CREATE OR REPLACE FUNCTION private.dating_switch_read(p_cipher bytea, OUT o_value jsonb, OUT o_unreadable boolean)
LANGUAGE plpgsql
VOLATILE
SET search_path = ''
AS $fn$
BEGIN
  o_unreadable := false;
  o_value := private.dating_field_decrypt(p_cipher);
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
    o_value := NULL;
    o_unreadable := true;
  ELSE
    RAISE;
  END IF;
END;
$fn$;

-- A member's identity as it was before the switch (p_before: user id ->
-- identity, for the people in the switched countries), else as stored;
-- 'unreadable' when it can't be read; NULL when there is no answer (neither
-- is ever man-woman: fix round 1, I-3).
CREATE OR REPLACE FUNCTION private.dating_switch_identity(p_user uuid, p_before jsonb)
RETURNS text
LANGUAGE sql
VOLATILE
SET search_path = ''
AS $fn$
  SELECT CASE WHEN p_before ? p_user::text THEN p_before ->> p_user::text
              ELSE (SELECT CASE WHEN d.o_unreadable THEN 'unreadable' ELSE d.o_value ->> 'identity' END
                      FROM public.dating_profile_sensitive AS s
                     CROSS JOIN LATERAL private.dating_switch_read(s.identity_enc) AS d
                     WHERE s.user_id = p_user) END;
$fn$;

CREATE OR REPLACE FUNCTION public.apply_same_gender_switch(p_country text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_code constant text := upper(btrim(p_country));
  v_codes text[];
  v_off text[];
  v_c text;
  r record;
  v_identity_enc bytea;
  v_seeking_enc bytea;
  v_read record;
  v_identity jsonb;
  v_seeking jsonb;
  v_unreadable boolean;
  v_bad_identity boolean;
  v_bad_seeking boolean;
  v_base text;
  v_strip boolean;
  v_kept_base text;
  v_open_pair boolean;
  v_before jsonb;
  v_count integer := 0;
BEGIN
  IF p_country IS NOT NULL
     AND (coalesce(v_code ~ '^[A-Z]{2}$', false) IS NOT TRUE OR private.dating_iso_country(v_code) IS NULL) THEN
    RAISE EXCEPTION 'dating:invalid_country';
  END IF;
  -- A missing or replaced key would make every answer unreadable, and the
  -- restrictive path would then wipe them all.
  IF private.dating_field_key_usable() IS NOT TRUE THEN
    IF private.dating_field_key_present() THEN -- fix round 1, M-6: present but replaced or unseeded
      RAISE EXCEPTION 'dating:field_key_not_ready';
    END IF;
    RAISE EXCEPTION 'dating:field_key_missing';
  END IF;

  -- 1. The exclusive same-gender lock of every affected country, before any
  --    row (setup writers hold it shared while they decide; batch-7 I-5).
  --    Every country: all that are configured or named by a profile or an
  --    other-countries list, in COLLATE "C" order (dating_lock_same_gender_all's).
  v_codes := CASE WHEN p_country IS NOT NULL THEN ARRAY[v_code]
                  ELSE ARRAY(SELECT DISTINCT x.c COLLATE "C"
                               FROM (SELECT c.country_code::text AS c FROM public.country_safety_config AS c
                                     UNION SELECT p.country_code::text FROM public.dating_profiles AS p
                                     UNION SELECT a::text FROM public.dating_preferences AS d, unnest(d.open_abroad) AS a) AS x
                              WHERE x.c IS NOT NULL
                              ORDER BY 1) END;
  FOREACH v_c IN ARRAY v_codes LOOP
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('dating_same_gender'), pg_catalog.hashtext(v_c));
  END LOOP;
  -- Read after the locks: the countries that now refuse same-gender.
  v_off := ARRAY(SELECT c FROM unnest(v_codes) AS c WHERE private.dating_same_gender_on(c) IS NOT TRUE ORDER BY 1);
  IF cardinality(v_off) = 0 THEN
    DELETE FROM private.dating_kill_switch_pending AS k WHERE p_country IS NULL OR k.scope = v_code;
    RETURN 0;
  END IF;

  -- The identities as they were, for the introduction and match passes
  -- (a woman whose pronouns are deleted below is still in a man-woman pair).
  SELECT coalesce(jsonb_object_agg(s.user_id::text, CASE WHEN d.o_unreadable THEN to_jsonb('unreadable'::text)
                                                         ELSE d.o_value -> 'identity' END), '{}'::jsonb)
    INTO v_before
    FROM public.dating_profiles AS p
    JOIN public.dating_profile_sensitive AS s ON s.user_id = p.user_id
   CROSS JOIN LATERAL private.dating_switch_read(s.identity_enc) AS d
   WHERE p.country_code::text = ANY (v_off);

  -- 2. The people there: enrolment, then sensitive, then profile.
  FOR r IN
    SELECT p.user_id
      FROM public.dating_profiles AS p
     WHERE p.country_code::text = ANY (v_off)
     ORDER BY p.user_id
  LOOP
    PERFORM 1 FROM public.dating_enrollments AS e WHERE e.user_id = r.user_id FOR UPDATE;
    SELECT s.identity_enc, s.seeking_enc INTO v_identity_enc, v_seeking_enc
      FROM public.dating_profile_sensitive AS s WHERE s.user_id = r.user_id FOR UPDATE;
    CONTINUE WHEN NOT FOUND;
    v_read := private.dating_switch_read(v_identity_enc);
    v_identity := v_read.o_value;
    v_unreadable := v_read.o_unreadable;
    v_read := private.dating_switch_read(v_seeking_enc);
    v_seeking := v_read.o_value;
    v_unreadable := v_unreadable OR v_read.o_unreadable;
    v_base := CASE WHEN v_unreadable THEN NULL ELSE v_identity ->> 'identity' END;
    v_bad_identity := v_unreadable OR (v_identity IS NOT NULL
      AND (coalesce(v_base, '') NOT IN ('woman', 'man')
           OR v_identity ->> 'specific' IS NOT NULL OR v_identity ->> 'specific_text' IS NOT NULL
           OR v_identity ->> 'pronouns' IS NOT NULL
           OR v_identity -> 'pools' IS DISTINCT FROM jsonb_build_array(v_base)));
    -- M-4: a woman/man identity loses only its disallowed parts.
    v_strip := v_bad_identity AND coalesce(v_base IN ('woman', 'man'), false);
    v_kept_base := CASE WHEN v_bad_identity AND NOT v_strip THEN NULL ELSE v_base END;
    v_bad_seeking := v_unreadable OR (v_seeking IS NOT NULL
      AND (v_kept_base IS NULL
           OR v_seeking -> 'seeking' IS DISTINCT FROM
              jsonb_build_array(CASE v_kept_base WHEN 'woman' THEN 'man' ELSE 'woman' END)));
    -- I-3: no stored identity in an open pair is never "man-woman".
    v_open_pair := v_identity IS NULL AND NOT v_unreadable
      AND (EXISTS (SELECT 1 FROM public.dating_matches AS m
                    WHERE m.state = 'active' AND r.user_id IN (m.user_low_id, m.user_high_id))
           OR EXISTS (SELECT 1 FROM public.dating_introductions AS i
                       WHERE i.state IN ('generated', 'presented', 'interested')
                         AND r.user_id IN (i.user_low_id, i.user_high_id)));
    CONTINUE WHEN NOT (v_bad_identity OR v_bad_seeking OR v_open_pair);
    IF v_unreadable THEN
      PERFORM private.bump_metric_internal('dating.kill_switch.unreadable');
    END IF;
    UPDATE public.dating_profile_sensitive AS s
       SET identity_enc = CASE WHEN NOT v_bad_identity THEN s.identity_enc
                               WHEN v_strip THEN private.dating_field_encrypt(jsonb_build_object(
                                 'identity', v_base, 'specific', NULL, 'specific_text', NULL, 'pronouns', NULL,
                                 'pools', jsonb_build_array(v_base)))
                               ELSE NULL END,
           seeking_enc = CASE WHEN v_bad_seeking THEN NULL ELSE s.seeking_enc END,
           updated_at = now()
     WHERE s.user_id = r.user_id;
    UPDATE public.dating_profiles AS p
       SET gender_visible = CASE WHEN v_bad_identity THEN false ELSE p.gender_visible END,
           profile_state = CASE WHEN p.profile_state = 'active' THEN 'paused' ELSE p.profile_state END,
           updated_at = now()
     WHERE p.user_id = r.user_id;
    UPDATE public.dating_enrollments AS e
       SET state = 'paused', pause_reason = 'same_gender_switch', paused_at = coalesce(e.paused_at, now()),
           updated_at = now()
     WHERE e.user_id = r.user_id AND e.state IN ('active', 'profile_draft');
    v_count := v_count + 1;
  END LOOP;

  -- 3. The switched countries leave every not-plain person's other-countries
  --    list (batch-8 I-2c; the locks are held). Unreadable is not plain.
  FOR r IN
    SELECT d.user_id
      FROM public.dating_preferences AS d
     WHERE d.open_abroad::text[] && v_off
     ORDER BY d.user_id
  LOOP
    v_identity_enc := NULL;
    v_seeking_enc := NULL;
    SELECT s.identity_enc, s.seeking_enc INTO v_identity_enc, v_seeking_enc
      FROM public.dating_profile_sensitive AS s WHERE s.user_id = r.user_id;
    v_read := private.dating_switch_read(v_identity_enc);
    v_identity := v_read.o_value;
    v_unreadable := v_read.o_unreadable;
    v_read := private.dating_switch_read(v_seeking_enc);
    v_seeking := v_read.o_value;
    v_unreadable := v_unreadable OR v_read.o_unreadable;
    IF v_unreadable THEN -- (never someone step 2 handled: it deleted what it couldn't read)
      PERFORM private.bump_metric_internal('dating.kill_switch.unreadable');
    END IF;
    IF v_unreadable OR private.dating_profile_plain(v_identity, v_seeking) IS NOT TRUE THEN
      PERFORM private.dating_prune_unsafe_abroad(r.user_id);
    END IF;
  END LOOP;

  -- 4. Every open introduction touching a switched country that isn't
  --    known to be man-woman (an unreadable or missing identity is not).
  UPDATE public.dating_introductions AS i
     SET state = 'invalidated'
   WHERE i.state IN ('generated', 'presented', 'interested')
     AND EXISTS (SELECT 1 FROM public.dating_profiles AS p
                  WHERE p.user_id IN (i.user_low_id, i.user_high_id)
                    AND p.country_code::text = ANY (v_off))
     AND NOT EXISTS (SELECT 1 FROM (SELECT private.dating_switch_identity(i.user_low_id, v_before) AS a,
                                           private.dating_switch_identity(i.user_high_id, v_before) AS b) AS g
                      WHERE ARRAY[g.a, g.b] IN (ARRAY['woman', 'man'], ARRAY['man', 'woman']));

  -- 5. Owner ruling 2026-11-06 (PF-F2): every active match touching a
  --    switched country that isn't man-woman closes, neutrally ('other'),
  --    sealed for the 30-day evidence window. Nobody is told.
  UPDATE public.dating_matches AS m
     SET state = 'closed', closed_reason = 'other', closed_at = coalesce(m.closed_at, now()),
         evidence_until = now() + interval '30 days'
   WHERE m.state = 'active'
     AND EXISTS (SELECT 1 FROM public.dating_profiles AS p
                  WHERE p.user_id IN (m.user_low_id, m.user_high_id)
                    AND p.country_code::text = ANY (v_off))
     AND NOT EXISTS (SELECT 1 FROM (SELECT private.dating_switch_identity(m.user_low_id, v_before) AS a,
                                           private.dating_switch_identity(m.user_high_id, v_before) AS b) AS g
                      WHERE ARRAY[g.a, g.b] IN (ARRAY['woman', 'man'], ARRAY['man', 'woman']));
  -- I-1: what was switched is no longer pending.
  DELETE FROM private.dating_kill_switch_pending AS k WHERE p_country IS NULL OR k.scope = v_code;
  RETURN v_count;
END;
$fn$;

CREATE OR REPLACE FUNCTION private.country_config_checks(p_row public.country_safety_config)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE
  v_checks text[] := ARRAY[]::text[];
  v_sg jsonb := p_row.legal_checklist -> 'same_gender_reconsideration';
BEGIN
  IF coalesce(p_row.dating_enabled, true) THEN
    IF coalesce(p_row.legal_checklist, '{}'::jsonb) = '{}'::jsonb
       -- I-3: every country needs the baseline references, whatever else
       -- its checklist holds.
       OR NOT (coalesce(p_row.legal_checklist, '{}'::jsonb)
               ?& ARRAY['dpia', 'pen_test', 'safety_owner_and_moderator', 'reviewer_signoffs'])
       OR EXISTS (SELECT 1 FROM jsonb_each(p_row.legal_checklist) AS e
                   WHERE e.key <> 'same_gender_reconsideration'
                     AND (jsonb_typeof(e.value) <> 'string' OR btrim(e.value #>> '{}') = '')) THEN
      v_checks := array_append(v_checks, 'evidence_missing');
    END IF;
    IF p_row.resources_verified_at IS NULL OR p_row.resources_verified_at < now() - interval '90 days' THEN
      v_checks := array_append(v_checks, 'resources_not_verified');
    END IF;
    -- Spec 2 W1b (batch-2 carry, I-5): Dating opens only under a set key
    -- Spec 2 W1b whose stored fingerprint matches it (no key, no stored
    -- Spec 2 W1b fingerprint or a rotated key: not ready).
    IF private.dating_exclusion_key_ready() IS NOT TRUE THEN -- Spec 2 W1b
      v_checks := array_append(v_checks, 'exclusion_key_not_ready'); -- Spec 2 W1b
    END IF; -- Spec 2 W1b
    -- Spec 2 W1d (batch-10 carry): and under a field key whose stored
    -- Spec 2 W1d fingerprint matches it (none, unseeded or replaced: not ready).
    IF private.dating_field_key_ready() IS NOT TRUE THEN -- Spec 2 W1d
      v_checks := array_append(v_checks, 'field_key_not_ready'); -- Spec 2 W1d
    END IF; -- Spec 2 W1d
  END IF;
  IF coalesce(p_row.same_gender_enabled, true) AND coalesce(p_row.tier, 1) IN (1, 2)
     AND (jsonb_typeof(v_sg) IS DISTINCT FROM 'object'
          OR EXISTS (SELECT 1 FROM unnest(ARRAY['legal_opinion', 'lgbtq_consultation', 'tier1_protections']) AS k(key)
                      WHERE jsonb_typeof(v_sg -> k.key) IS DISTINCT FROM 'string'
                         OR btrim(v_sg ->> k.key) = '')) THEN
    v_checks := array_append(v_checks, 'same_gender_reconsideration_missing');
  END IF;
  RETURN v_checks;
END;
$function$;

CREATE OR REPLACE FUNCTION public.publish_country_config(p_country text, p_values jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_code constant text := upper(coalesce(p_country, ''));
  v_allowed constant text[] := ARRAY['tier', 'dating_enabled', 'open_regions', 'same_gender_enabled',
    'region_list', 'faith_list', 'id_documents', 'generation_hour_utc', 'reference_tz',
    'resources_verified_at', 'legal_checklist', 'source_url', 'reviewed_at', 'reviewed_by', 'published_by'];
  v_old public.country_safety_config;
  v_new public.country_safety_config;
  v_codes text[];
  v_checks text[];
  v_check_row public.country_safety_config; -- I-2
  v_switch boolean; -- Spec 2 W1d
  v_affected integer; -- Spec 2 W1d
  v_closing boolean; -- Spec 2 W1d (PF-F1, batch-5 M-3)
  v_open_old text[]; -- Spec 2 W1d
  v_open_new text[]; -- Spec 2 W1d
  v_try integer; -- Spec 2 W1d (fix round 1, I-2)
  v_failed text; -- Spec 2 W1d (fix round 1, I-1)
BEGIN
  IF v_code !~ '^[A-Z]{2}$' OR private.dating_iso_country(v_code) IS NULL THEN -- I-1
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_country');
  END IF;
  IF jsonb_typeof(p_values) IS DISTINCT FROM 'object' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_values');
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_values) AS k WHERE k <> ALL (v_allowed)) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:unknown_key');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('country_safety_config:' || v_code, 0));
  SELECT * INTO v_old FROM public.country_safety_config AS c
   WHERE c.country_code = v_code AND c.is_current FOR UPDATE;
  IF NOT FOUND THEN
    v_old := public.dating_country_config(v_code);
  END IF;

  BEGIN
    v_new := jsonb_populate_record(v_old, p_values - 'open_regions');
    IF p_values ? 'open_regions' THEN
      v_new.open_regions := CASE WHEN jsonb_typeof(p_values -> 'open_regions') = 'null' THEN NULL
                                 ELSE ARRAY(SELECT DISTINCT e FROM jsonb_array_elements_text(p_values -> 'open_regions') AS e
                                             ORDER BY e) END; -- M-2: deduplicated
    END IF;
  EXCEPTION WHEN data_exception OR invalid_text_representation OR datatype_mismatch THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_values');
  END;
  v_new.country_code := v_code;
  v_new.version := v_old.version + 1;
  v_new.is_current := true;
  v_new.published_at := now();
  v_new.published_by := coalesce(nullif(btrim(p_values ->> 'published_by'), ''), 'service_role');
  -- M-3: a country first published as Tier 1/2 starts same-gender off.
  IF v_old.version = 0 AND v_new.tier IN (1, 2) AND NOT p_values ? 'same_gender_enabled' THEN
    v_new.same_gender_enabled := false;
  END IF;

  IF v_new.tier IS NULL OR v_new.tier NOT BETWEEN 1 AND 3
     OR v_new.dating_enabled IS NULL OR v_new.same_gender_enabled IS NULL
     OR v_new.generation_hour_utc IS NULL OR v_new.generation_hour_utc NOT BETWEEN 0 AND 23
     OR v_new.resources_verified_at > now() + interval '1 day' THEN -- M-1
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_values');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names AS z WHERE z.name = v_new.reference_tz) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_tz');
  END IF;
  IF jsonb_typeof(v_new.region_list) IS DISTINCT FROM 'array'
     OR jsonb_typeof(v_new.faith_list) IS DISTINCT FROM 'array'
     OR jsonb_typeof(v_new.id_documents) IS DISTINCT FROM 'array'
     OR jsonb_typeof(v_new.legal_checklist) IS DISTINCT FROM 'object'
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_new.region_list) AS r
                 WHERE jsonb_typeof(r) <> 'object' OR coalesce(r ->> 'code', '') !~ '^[A-Z0-9]{2,3}$') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_lists');
  END IF;
  -- I-3: the checklist only grows (a dropped key is a dropped obligation).
  IF NOT (v_new.legal_checklist ?& ARRAY(SELECT jsonb_object_keys(v_old.legal_checklist))) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:checklist_keys_removed');
  END IF;
  v_codes := ARRAY(SELECT r ->> 'code' FROM jsonb_array_elements(v_new.region_list) AS r);
  IF cardinality(v_codes) <> (SELECT count(DISTINCT c) FROM unnest(v_codes) AS c)
     OR (v_new.open_regions IS NOT NULL AND NOT v_new.open_regions <@ v_codes)
     OR (v_new.dating_enabled AND cardinality(v_new.open_regions) = 0) THEN -- M-2: open in no region
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_regions');
  END IF;
  -- Spec 2 W1d (PF-F1, batch-5 M-3): an exposure-reducing publish (closing,
  -- Spec 2 W1d narrowing the open regions, tightening the tier, same-gender
  -- Spec 2 W1d off) widens nothing and adds no ID document; a safety
  -- Spec 2 W1d change is never refused for unrelated lapsed evidence.
  v_open_old := CASE WHEN v_old.dating_enabled IS TRUE -- Spec 2 W1d
                     THEN coalesce(v_old.open_regions, ARRAY(SELECT r ->> 'code' FROM jsonb_array_elements(v_old.region_list) AS r)) -- Spec 2 W1d
                     ELSE ARRAY[]::text[] END; -- Spec 2 W1d
  v_open_new := CASE WHEN v_new.dating_enabled THEN coalesce(v_new.open_regions, v_codes) ELSE ARRAY[]::text[] END; -- Spec 2 W1d
  v_closing := v_old.version >= 1 -- Spec 2 W1d
    AND coalesce(v_open_new <@ v_open_old, false) -- Spec 2 W1d: no region newly open
    AND NOT (v_new.dating_enabled AND v_old.dating_enabled IS NOT TRUE) -- Spec 2 W1d
    AND v_new.tier <= v_old.tier -- Spec 2 W1d: 1 is the strictest
    AND NOT (v_new.same_gender_enabled AND v_old.same_gender_enabled IS NOT TRUE) -- Spec 2 W1d
    AND coalesce(v_old.id_documents @> v_new.id_documents, false) -- Spec 2 W1d: no ID document added (fix round 1, M-8)
    AND ((v_old.dating_enabled IS TRUE AND NOT v_new.dating_enabled) -- Spec 2 W1d: and something is reduced
         OR NOT coalesce(v_open_old <@ v_open_new, false) -- Spec 2 W1d
         OR v_new.tier < v_old.tier -- Spec 2 W1d
         OR NOT coalesce(v_new.id_documents @> v_old.id_documents, false) -- Spec 2 W1d: an ID document removed (fix round 1, M-8)
         OR (v_old.same_gender_enabled IS TRUE AND NOT v_new.same_gender_enabled)); -- Spec 2 W1d
  v_closing := coalesce(v_closing, false); -- Spec 2 W1d
  -- M-4: a country that restricts anything needs its calling code, or the
  -- phone fallback can't see it.
  IF (v_new.tier IN (1, 2) OR NOT v_new.same_gender_enabled)
     AND NOT EXISTS (SELECT 1 FROM private.dating_calling_codes AS k WHERE k.country_code = v_code)
     AND NOT v_closing THEN -- Spec 2 W1d: a reduction is still published (reported below)
    RETURN jsonb_build_object('ok', false, 'reason', 'config:no_calling_code');
  END IF;

  -- Same-gender off: the kill switch runs in this transaction (§2.4).
  -- (Not for a country with no row yet: nobody can have it as their Dating country. M-3)
  v_switch := v_old.version >= 1 AND v_old.same_gender_enabled AND NOT v_new.same_gender_enabled; -- Spec 2 W1d

  -- I-2: the reconsideration is checked at the stricter of the old and new
  -- tiers, and a downgrade needs its own review reference.
  v_check_row := v_new;
  v_check_row.tier := least(v_old.tier, v_new.tier);
  v_checks := private.country_config_checks(v_check_row);
  IF v_old.version >= 1 AND v_new.tier > v_old.tier
     AND (jsonb_typeof(v_new.legal_checklist -> 'tier_review') IS DISTINCT FROM 'string'
          OR btrim(v_new.legal_checklist ->> 'tier_review') = ''
          OR v_new.legal_checklist -> 'tier_review' IS NOT DISTINCT FROM v_old.legal_checklist -> 'tier_review') THEN -- W1 final fix (M-7): each downgrade its own review
    v_checks := array_append(v_checks, 'tier_review_missing');
  END IF;
  IF (v_new.tier IN (1, 2) OR NOT v_new.same_gender_enabled) -- Spec 2 W1d
     AND NOT EXISTS (SELECT 1 FROM private.dating_calling_codes AS k WHERE k.country_code = v_code) THEN -- Spec 2 W1d
    v_checks := array_append(v_checks, 'no_calling_code'); -- Spec 2 W1d: only a reduction gets here
  END IF; -- Spec 2 W1d
  IF cardinality(v_checks) > 0 AND private.attune_environment() = 'production'
     AND NOT v_closing THEN -- Spec 2 W1d (PF-F1): the checks are still returned
    RETURN jsonb_build_object('ok', false, 'reason', 'config:production_checks_failed',
                              'checks', to_jsonb(v_checks));
  END IF;

  UPDATE public.country_safety_config AS c SET is_current = false
   WHERE c.country_code = v_code AND c.is_current;
  INSERT INTO public.country_safety_config SELECT v_new.*;
  IF v_switch THEN -- Spec 2 W1d
    -- Spec 2 W1d: the switch is published even if the purge can't run; a
    -- Spec 2 W1d deadlock or lock timeout is retried (fix round 1, I-2), and a
    -- Spec 2 W1d purge that still fails is left pending, visibly (I-1).
    FOR v_try IN 1..3 LOOP -- Spec 2 W1d
      BEGIN -- Spec 2 W1d
        v_affected := public.apply_same_gender_switch(v_code); -- Spec 2 W1d
        v_failed := NULL; -- Spec 2 W1d
        EXIT; -- Spec 2 W1d
      EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W1d
        v_failed := SQLSTATE; -- Spec 2 W1d: its locks are released; the other side finishes; try again
        EXIT WHEN SQLERRM = 'dating:busy'; -- W1 final fix (N-M3): an inner retry already ran
      WHEN OTHERS THEN -- Spec 2 W1d
        v_failed := SQLSTATE; -- Spec 2 W1d
        EXIT; -- Spec 2 W1d
      END; -- Spec 2 W1d
    END LOOP; -- Spec 2 W1d
    IF v_failed IS NOT NULL THEN -- Spec 2 W1d
      v_affected := NULL; -- Spec 2 W1d
      PERFORM private.dating_kill_switch_mark(v_code, v_failed); -- Spec 2 W1d
      RAISE WARNING 'publish_country_config:kill_switch_pending:%; re-run select public.apply_same_gender_switch(''%'');', v_failed, v_code; -- Spec 2 W1d
    END IF; -- Spec 2 W1d
  END IF; -- Spec 2 W1d
  RETURN jsonb_build_object('ok', true, 'country', v_code, 'version', v_new.version,
                            'dating_enabled', v_new.dating_enabled,
                            'same_gender_enabled', v_new.same_gender_enabled,
                            'environment', private.attune_environment(),
                            'checks', to_jsonb(v_checks))
         || CASE WHEN v_switch THEN jsonb_build_object('switched', true, 'affected', v_affected) -- Spec 2 W1d
                 ELSE '{}'::jsonb END -- Spec 2 W1d
         || CASE WHEN v_failed IS NOT NULL THEN jsonb_build_object('pending_sqlstate', v_failed) -- Spec 2 W1d (I-1)
                 ELSE '{}'::jsonb END; -- Spec 2 W1d
END;
$function$;

-- The global flag off is the kill switch everywhere (§2.4). It never
-- blocks the flag change.
CREATE OR REPLACE FUNCTION private.dating_same_gender_flag_off()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_try integer;
  v_failed text;
BEGIN
  -- A deadlock or lock timeout is retried (fix round 1, I-2); a purge that
  -- still fails is left pending, visibly ('*'; I-1).
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM public.apply_same_gender_switch(NULL);
      v_failed := NULL;
      EXIT;
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      v_failed := SQLSTATE;
      EXIT WHEN SQLERRM = 'dating:busy'; -- W1 final fix (N-M3): an inner retry already ran
    WHEN OTHERS THEN
      v_failed := SQLSTATE;
      EXIT;
    END;
  END LOOP;
  IF v_failed IS NOT NULL THEN
    PERFORM private.dating_kill_switch_mark(NULL, v_failed);
    RAISE WARNING 'dating_same_gender_flag_off:%; re-run select public.apply_same_gender_switch(NULL);', v_failed;
  END IF;
  RETURN NULL;
END;
$fn$;
DROP TRIGGER IF EXISTS dating_same_gender_flag_off ON public.feature_flags;
CREATE TRIGGER dating_same_gender_flag_off
  AFTER UPDATE ON public.feature_flags
  FOR EACH ROW
  WHEN (OLD.key = 'dating_same_gender_matching' AND OLD.enabled
        AND NOT (NEW.key = 'dating_same_gender_matching' AND NEW.enabled))
  EXECUTE FUNCTION private.dating_same_gender_flag_off();
-- A missing flag reads off (dating_flag_enabled), so deleting it is the switch too.
DROP TRIGGER IF EXISTS dating_same_gender_flag_deleted ON public.feature_flags;
CREATE TRIGGER dating_same_gender_flag_deleted
  AFTER DELETE ON public.feature_flags
  FOR EACH ROW
  WHEN (OLD.key = 'dating_same_gender_matching' AND OLD.enabled)
  EXECUTE FUNCTION private.dating_same_gender_flag_off();
-- Fix round 1, M-2: a TRUNCATE fires no row trigger, and leaves the flag missing (off).
DROP TRIGGER IF EXISTS dating_same_gender_flag_truncated ON public.feature_flags;
CREATE TRIGGER dating_same_gender_flag_truncated
  AFTER TRUNCATE ON public.feature_flags
  FOR EACH STATEMENT
  EXECUTE FUNCTION private.dating_same_gender_flag_off();

-- W1 final fix (I-1): re-created from its live body (20260712130000) with
-- only the marked lines: its three statements are retried on a lock
-- conflict, so a settings or lifecycle writer whose introductions a
-- cross-border switch is ending (the one interleaving the shared lock order
-- can't serialise) waits for the switch instead of failing.
CREATE OR REPLACE FUNCTION public.invalidate_dating_for_user(p_user_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE -- W1 final fix (I-1)
  v_try integer; -- W1 final fix (I-1)
BEGIN
  FOR v_try IN 1..3 LOOP -- W1 final fix (I-1)
  BEGIN -- W1 final fix (I-1)
  UPDATE public.dating_feature_snapshots
  SET invalidated_at = COALESCE(invalidated_at, now())
  WHERE user_id = p_user_id
    AND invalidated_at IS NULL;

  UPDATE public.dating_introductions
  SET state = 'invalidated'
  WHERE (user_low_id = p_user_id OR user_high_id = p_user_id)
    AND state IN ('generated', 'presented', 'interested');

  -- Close existing active matches ONLY for reasons that are genuinely an exit
  -- from Dating: leaving (exit), terms/opt-in withdrawal (dating_consent_withdrawn
  -- — this ALSO sets profile_state='exited', so it must close matches too, per
  -- re-review DATING-H5a; note Spec §3.3/:113 "matches remain on withdrawal"
  -- governs HISTORICAL-DATA consent only, not terms/opt-in), suspension
  -- (account_restricted), and profile deletion. Pause, HISTORICAL-consent
  -- withdrawal, profile edits, and scheduled revalidation deliberately PRESERVE
  -- matches (Spec §14 :612 pause; :113 historical-consent).
  IF p_reason IN (
    'exit', 'dating_consent_withdrawn', 'account_restricted', 'profile_deleted'
  ) THEN
    UPDATE public.dating_matches
    SET state = 'closed',
        closed_at = COALESCE(closed_at, now())
    WHERE (user_low_id = p_user_id OR user_high_id = p_user_id)
      AND state = 'active';
  END IF;
  EXIT; -- W1 final fix (I-1)
  EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- W1 final fix (I-1)
    IF v_try = 3 OR SQLERRM = 'dating:busy' THEN RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; END IF; -- W1 final fix (N-M3): an inner retry already ran: no nesting -- W1 final fix (I-1)
  END; -- W1 final fix (I-1)
  END LOOP; -- W1 final fix (I-1)
END;
$function$;

-- W1 final fix (I-1, M-2): D3 re-created from its live body (migration 7)
-- with only the marked lines.
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
  v_try integer; -- W1 final fix (I-1)
  v_identity_enc bytea; -- W1 final fix (M-2)
  v_seeking_enc bytea; -- W1 final fix (M-2)
  v_read record; -- W1 final fix (M-2)
  v_identity jsonb; -- W1 final fix (M-2)
  v_seeking jsonb; -- W1 final fix (M-2)
  v_unreadable boolean; -- W1 final fix (M-2)
  v_base text; -- W1 final fix (M-2)
  v_before jsonb; -- W1 final fix (M-2)
  v_rows integer; -- W1 final fix (M-2)
  v_restrict boolean; -- W1 final fix (M-2)
BEGIN
  -- W1 final fix (I-1): the new country's same-gender lock is taken with the
  -- W1 final fix setup lock (old, new and other countries in one sorted pass).
  IF v_user IS NOT NULL AND v_country ~ '^[A-Z]{2}$' THEN -- W1 final fix (I-1)
    PERFORM private.dating_lock_setup(v_user, ARRAY[v_country]); -- W1 final fix (I-1)
  END IF; -- W1 final fix (I-1)
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

  FOR v_try IN 1..3 LOOP -- W1 final fix (I-1): a lock conflict is retried (each attempt its own savepoint)
  BEGIN -- W1 final fix (I-1)
  v_restrict := false; -- W1 final fix (M-2)
  IF private.dating_ensure_profile(v_user) THEN
    PERFORM private.bump_metric_internal('dating.setup.started');
  END IF;
  -- W1 final fix (M-2): moving into a country whose same-gender rule is off
  -- W1 final fix gives her pairs the kill switch's treatment, judged by the
  -- W1 final fix answers she held before the move (unreadable or missing is
  -- W1 final fix never man-woman): active matches close ('other', sealed for
  -- W1 final fix the 30-day evidence window), open introductions end, and
  -- W1 final fix she is paused (same_gender_switch) as the switch would pause
  -- W1 final fix her. Nobody is told.
  IF v_old_country IS NOT NULL AND v_old_country IS DISTINCT FROM v_country -- W1 final fix (M-2)
     AND private.dating_same_gender_on(v_country) IS NOT TRUE THEN -- W1 final fix (M-2)
    SELECT s.identity_enc, s.seeking_enc INTO v_identity_enc, v_seeking_enc -- W1 final fix (M-2)
      FROM public.dating_profile_sensitive AS s WHERE s.user_id = v_user FOR UPDATE; -- W1 final fix (M-2)
    v_read := private.dating_switch_read(v_identity_enc); -- W1 final fix (M-2)
    v_identity := v_read.o_value; -- W1 final fix (M-2)
    v_unreadable := v_read.o_unreadable; -- W1 final fix (M-2)
    v_read := private.dating_switch_read(v_seeking_enc); -- W1 final fix (M-2)
    v_seeking := v_read.o_value; -- W1 final fix (M-2)
    v_unreadable := v_unreadable OR v_read.o_unreadable; -- W1 final fix (M-2)
    v_base := CASE WHEN v_unreadable THEN 'unreadable' ELSE v_identity ->> 'identity' END; -- W1 final fix (M-2)
    v_before := jsonb_build_object(v_user::text, v_base); -- W1 final fix (M-2): hers as it was (NULL: no answer)
    UPDATE public.dating_matches AS m -- W1 final fix (M-2)
       SET state = 'closed', closed_reason = 'other', closed_at = coalesce(m.closed_at, now()), -- W1 final fix (M-2)
           evidence_until = now() + interval '30 days' -- W1 final fix (M-2)
     WHERE m.state = 'active' AND v_user IN (m.user_low_id, m.user_high_id) -- W1 final fix (M-2)
       AND NOT EXISTS (SELECT 1 FROM (SELECT private.dating_switch_identity(m.user_low_id, v_before) AS a, -- W1 final fix (M-2)
                                             private.dating_switch_identity(m.user_high_id, v_before) AS b) AS g -- W1 final fix (M-2)
                        WHERE ARRAY[g.a, g.b] IN (ARRAY['woman', 'man'], ARRAY['man', 'woman'])); -- W1 final fix (M-2)
    GET DIAGNOSTICS v_rows = ROW_COUNT; -- W1 final fix (M-2)
    v_restrict := v_rows > 0; -- W1 final fix (M-2): a pair ended (for the pause rule below)
    UPDATE public.dating_introductions AS i SET state = 'invalidated' -- W1 final fix (M-2)
     WHERE i.state IN ('generated', 'presented', 'interested') AND v_user IN (i.user_low_id, i.user_high_id) -- W1 final fix (M-2)
       AND NOT EXISTS (SELECT 1 FROM (SELECT private.dating_switch_identity(i.user_low_id, v_before) AS a, -- W1 final fix (M-2)
                                             private.dating_switch_identity(i.user_high_id, v_before) AS b) AS g -- W1 final fix (M-2)
                        WHERE ARRAY[g.a, g.b] IN (ARRAY['woman', 'man'], ARRAY['man', 'woman'])); -- W1 final fix (M-2)
    GET DIAGNOSTICS v_rows = ROW_COUNT; -- W1 final fix (M-2)
    -- W1 final fix (M-2): paused as the switch pauses: her answers aren't
    -- W1 final fix allowed there (an identity other than plain woman/man, a
    -- W1 final fix who-to-meet other than exactly the opposite, or unreadable),
    -- W1 final fix or she had no identity and was in a pair (never man-woman).
    -- W1 final fix A plain mover's ended pairs don't pause her (nor the switch).
    v_restrict := (v_identity IS NULL AND NOT v_unreadable AND (v_restrict OR v_rows > 0)) OR v_unreadable -- W1 final fix (M-2)
      OR (v_identity IS NOT NULL AND NOT coalesce(v_base IN ('woman', 'man') -- W1 final fix (M-2)
            AND v_identity ->> 'specific' IS NULL AND v_identity ->> 'specific_text' IS NULL -- W1 final fix (M-2)
            AND v_identity ->> 'pronouns' IS NULL AND v_identity -> 'pools' = jsonb_build_array(v_base), false)) -- W1 final fix (M-2)
      OR (v_seeking IS NOT NULL AND NOT coalesce(v_base IN ('woman', 'man') -- W1 final fix (M-2)
            AND v_seeking -> 'seeking' = jsonb_build_array(CASE v_base WHEN 'woman' THEN 'man' ELSE 'woman' END), false)); -- W1 final fix (M-2)
    IF v_restrict THEN -- W1 final fix (M-2): an enrolment already paused keeps its first reason
      UPDATE public.dating_enrollments AS e -- W1 final fix (M-2)
         SET state = 'paused', pause_reason = 'same_gender_switch', paused_at = coalesce(e.paused_at, now()), -- W1 final fix (M-2)
             updated_at = now() -- W1 final fix (M-2)
       WHERE e.user_id = v_user AND e.state IN ('active', 'profile_draft'); -- W1 final fix (M-2)
    END IF; -- W1 final fix (M-2)
  END IF; -- W1 final fix (M-2)
  UPDATE public.dating_profiles AS p
     SET country_code = v_country, region_code = p_region, side_code = p_side,
         country_changed_at = CASE WHEN p.country_code IS DISTINCT FROM v_country AND p.country_code IS NOT NULL
                                   THEN now() ELSE p.country_changed_at END,
         profile_state = CASE WHEN v_restrict AND p.profile_state = 'active' THEN 'paused' ELSE p.profile_state END, -- W1 final fix (M-2)
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
  EXIT; -- W1 final fix (I-1)
  EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- W1 final fix (I-1)
    IF v_try = 3 OR SQLERRM = 'dating:busy' THEN RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; END IF; -- W1 final fix (N-M3): an inner retry already ran: no nesting -- W1 final fix (I-1)
  END; -- W1 final fix (I-1)
  END LOOP; -- W1 final fix (I-1)
  RETURN jsonb_build_object('ok', true, 'next_step', 'privacy');
END;
$fn$;

-- W1 final fix (I-1): re-created from its live body (migration 3) with
-- only the marked lines: the person's locks (setup, then same-gender,
-- shared) before the cascade reaches their Dating rows, so an account
-- deletion waits for a running switch instead of deadlocking with it.
CREATE OR REPLACE FUNCTION private.dating_carry_on_auth_user_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  BEGIN -- W1 final fix (I-1)
    PERFORM private.dating_lock_setup(OLD.id); -- W1 final fix (I-1)
  EXCEPTION WHEN OTHERS THEN -- W1 final fix (I-1): never blocks the deletion
    RAISE WARNING 'dating_carry_on_auth_user_delete:lock:%', SQLSTATE; -- W1 final fix (I-1)
  END; -- W1 final fix (I-1)
  BEGIN
    IF private.dating_deletion_carry(OLD.id, true) > 0 THEN
      PERFORM private.bump_metric_internal('dating.deletion.late_carry');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    PERFORM private.bump_metric_internal('dating.deletion.late_carry_failed');
  END;
  RETURN OLD;
END;
$function$;

CREATE OR REPLACE FUNCTION public.exit_dating_mode(p_idempotency_key text, p_keep_never_introduce boolean DEFAULT false)
 RETURNS dating_enrollments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_enrollment public.dating_enrollments%ROWTYPE;
  v_try integer; -- Spec 2 W1d (batch-11 fix round 1, I-2)
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  -- No device check: leaving deletes the person's own data (W1 B8 ruling).
  PERFORM private.dating_lock_setup(v_user_id); -- the shared lock order (setup first)
  IF NOT public.claim_dating_idempotency('exit_dating_mode', p_idempotency_key) THEN
    SELECT * INTO v_enrollment FROM public.dating_enrollments AS e WHERE e.user_id = v_user_id;
    RETURN v_enrollment;
  END IF;
  -- The hard delete also writes "when you left": every standing consent
  -- withdrawn, on the server's clock (fix round 1, I-1).
  -- Spec 2 W1d (batch-11 fix round 1, I-2, M-7): a deadlock with a kill
  -- Spec 2 W1d switch (or a lock timeout) is retried, so leaving never fails
  -- Spec 2 W1d on it; the aborted attempt released its row locks.
  FOR v_try IN 1..3 LOOP -- Spec 2 W1d
    BEGIN -- Spec 2 W1d
      PERFORM private.dating_exit_internal(v_user_id, coalesce(p_keep_never_introduce, false));
      EXIT; -- Spec 2 W1d
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W1d
      IF v_try = 3 OR SQLERRM = 'dating:busy' THEN -- Spec 2 W1d (W1 final fix N-M3: an inner retry already ran)
        RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; -- W1 final fix (I-1): the SQLSTATE, never the raw DETAIL
      END IF; -- Spec 2 W1d
    END; -- Spec 2 W1d
  END LOOP; -- Spec 2 W1d
  SELECT * INTO v_enrollment FROM public.dating_enrollments AS e WHERE e.user_id = v_user_id;
  RETURN v_enrollment;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_dating_operational_health()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT jsonb_build_object(
    'dating_enabled',public.dating_flag_enabled('dating_mode_enabled'),
    'candidate_generation_enabled',public.dating_flag_enabled('dating_candidate_generation'),
    'exclusion_key_present',public.app_setting('dating_exclusion_key') IS NOT NULL,
    'relationships_ended_without_exclusion_24h',(
      SELECT count(*) FROM public.relationships r
      WHERE r.status = 'ended'
        AND r.ended_at >= now() - interval '24 hours'
        AND NOT EXISTS (
          SELECT 1 FROM public.dating_former_partner_exclusions e
          WHERE e.relationship_id = r.id
        )
    ),
    'active_algorithm_versions',(SELECT count(*) FROM public.dating_algorithm_configs WHERE state='active'),
    'stuck_generation_runs',(SELECT count(*) FROM public.dating_generation_runs WHERE state='processing' AND started_at < now()-interval '30 minutes'),
    'failed_generation_runs_24h',(SELECT count(*) FROM public.dating_generation_runs WHERE state IN ('failed','dead_letter') AND created_at >= now()-interval '24 hours'),
    'expired_open_introductions',(SELECT count(*) FROM public.dating_introductions WHERE state IN ('generated','presented','interested') AND expires_at <= now()),
    'pending_bio_moderation',(SELECT count(*) FROM public.dating_profiles WHERE moderation_state='pending'),
    'pending_photo_moderation',(SELECT count(*) FROM public.dating_profile_photos WHERE moderation_state='pending'),
    'environment',private.attune_environment(), -- Spec 2 W1d
    'field_key_present',private.dating_field_key_present(), -- Spec 2 W1d
    -- Spec 2 W1d (§2.4): nothing can write an RPC's parameters to the log.
    'log_settings_safe',coalesce(current_setting('log_statement', true) IN ('none', 'ddl')
      AND (current_setting('log_min_duration_statement', true) = '-1'
           OR current_setting('log_parameter_max_length', true) = '0')
      AND current_setting('log_parameter_max_length_on_error', true) = '0', false),
    'enabled_countries',to_jsonb(private.dating_open_countries()), -- Spec 2 W1d
    -- Spec 2 W1d (B2 I-5, B5 M-4, B6 M-5): each key set and its stored
    -- Spec 2 W1d fingerprint equal (read only; never the counting mismatch()).
    'exclusion_key_fingerprint_ok',private.dating_exclusion_key_ready(), -- Spec 2 W1d
    'field_key_fingerprint_ok',private.dating_field_key_ready(), -- Spec 2 W1d
    'safety_counters_7d',(SELECT jsonb_object_agg(k.key, coalesce((SELECT sum(c.count) FROM public.metric_counters c -- Spec 2 W1d
                            WHERE c.key = k.key AND c.day >= (now() AT TIME ZONE 'utc')::date - 6), 0)) -- Spec 2 W1d
      FROM unnest(ARRAY['dating.deletion.uncarried', 'dating.exclusion_key.mismatch', 'dating.exclusion_key.unseeded', -- Spec 2 W1d
                        'dating.eligibility.key_not_ready', 'dating.field_key.mismatch', 'dating.field_key.missing', -- Spec 2 W1d
                        'dating.parked_pause.failed', -- Spec 2 W1d (fix round 1, M-5)
                        'dating.kill_switch.pending', 'dating.kill_switch.unreadable', -- Spec 2 W1d (migration 11)
                        'dating.deletion.prepare_carry_failed', 'dating.deletion.late_carry_failed']) AS k(key)), -- W1 final fix (M-4)
    -- W1 final fix (M-4): app deletions refused for a missing exclusion key
    -- W1 final fix (delete-account records prepare's message) in 7 days.
    'deletions_refused_key_missing_7d',(SELECT count(*) FROM public.account_deletion_requests AS r -- W1 final fix (M-4)
                                         WHERE r.completed_at IS NULL AND r.requested_at >= now() - interval '7 days' -- W1 final fix (M-4)
                                           AND r.failure_reason LIKE '%deletion:enforcement_key_missing%'), -- W1 final fix (M-4)
    -- Spec 2 W1d (fix round 1, I-1): every purge still pending, until a switch clears it.
    'kill_switch_pending',(SELECT coalesce(jsonb_agg(jsonb_build_object('scope', k.scope, 'since', k.first_failed_at, -- Spec 2 W1d
                             'sqlstate', k.last_sqlstate, 'attempts', k.attempts) ORDER BY k.scope), '[]'::jsonb) -- Spec 2 W1d
                           FROM private.dating_kill_switch_pending k) -- Spec 2 W1d
  );
$function$;

REVOKE ALL ON FUNCTION public.apply_same_gender_switch(text), private.dating_same_gender_flag_off(),
  private.dating_switch_read(bytea), private.dating_switch_identity(uuid, jsonb),
  private.country_config_checks(public.country_safety_config), private.dating_kill_switch_mark(text, text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE private.dating_kill_switch_pending FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.publish_country_config(text, jsonb), public.get_dating_operational_health()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.publish_country_config(text, jsonb), public.get_dating_operational_health() TO service_role;
REVOKE ALL ON FUNCTION public.exit_dating_mode(text, boolean) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.exit_dating_mode(text, boolean) TO authenticated;
-- W1 final fix: the re-created functions keep their grants (re-asserted).
REVOKE ALL ON FUNCTION public.invalidate_dating_for_user(uuid, text), private.dating_carry_on_auth_user_delete()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.save_dating_location(text, text, text, text, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.save_dating_location(text, text, text, text, text) TO authenticated;
-- W1 final fix (M-9): the v1 draft writer bypasses every v2 check (no flag,
-- eligibility or filter; it reopens an exited or paused enrolment and makes
-- the "Dating profile" never-introduce accepts): no API role runs it. W3b
-- drops it; its v1 columns stay (P-22).
REVOKE ALL ON FUNCTION public.save_dating_profile_draft(text, text, text, text, text, integer, integer)
  FROM PUBLIC, anon, authenticated, service_role;
-- W1 final fix (N-I1, M-9 scope): the v1 photo-upload path checks no flag,
-- eligibility, standing or rate limit, and its bucket has no CSAM scan until
-- W3c's inline match, so no API role starts an upload (without an intent
-- the bucket's INSERT policy admits nothing). W3 re-creates both with the
-- v2 checks and the inline match; deleting one's own photo stays.
REVOKE ALL ON FUNCTION public.create_dating_photo_upload_intent(text), public.insert_dating_profile_photo(uuid, smallint)
  FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
