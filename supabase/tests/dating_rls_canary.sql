-- supabase/tests/dating_rls_canary.sql
-- Spec 2 §4.5, §7.1 (S-4, S-5): every Dating relation and function has
-- exactly its allow-listed client grants, so a new Dating table or RPC
-- cannot ship readable or callable by accident. In scope: public
-- relations named dating_*, moderation_* or containing gentle_wait or
-- how_we_met, plus country_safety_config, enforcement_records,
-- couple_how_we_met and law_enforcement_requests, and every public view or
-- materialized view built (at any depth) on one of them; public and private
-- functions whose name contains "dating", "date_reflection", "gentle_wait"
-- or "how_we_met" or starts with "moderation_", plus publish_country_config
-- and apply_same_gender_switch, plus any function whose body names a
-- Dating relation (batch 2 fix round 1, I-3: an RPC that reads Dating data
-- under another name is in scope too).
-- For each relation: anon's and authenticated's table privileges must equal
-- the list exactly, PUBLIC has none, RLS is on, and service_role's
-- SELECT/INSERT/UPDATE/DELETE equal the list (hosted projects also give it
-- TRUNCATE/REFERENCES/TRIGGER by default, which this file ignores).
-- Every in-scope view must be security_invoker.
-- For each function: PUBLIC has no EXECUTE, anon's and authenticated's
-- EXECUTE equal the list, and where a row pins it (service not NULL),
-- service_role's EXECUTE equals it too (I-4: hosted projects grant every
-- new public function to service_role, so a twin that forgets the service
-- role leaves an internal helper, e.g. a number-to-HMAC one, callable with
-- the service key). Every later batch adds its rows here. The API roles
-- have no USAGE on schema private, and no private Dating relation is an
-- API role's.
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_rls_canary.sql
BEGIN;

CREATE TEMP TABLE allowed_rel (
  name text PRIMARY KEY,
  anon text NOT NULL DEFAULT '',
  authenticated text NOT NULL DEFAULT '',
  service_dml text NOT NULL DEFAULT ''
) ON COMMIT DROP;
CREATE TEMP TABLE allowed_fn (
  sig text PRIMARY KEY,
  clients text NOT NULL DEFAULT '',
  service text -- 'service_role' or '' (pinned); NULL: not pinned
) ON COMMIT DROP;

-- ---------------------------------------------------------------------
-- W1a: the Dating tables of today, and the two survival tables.
-- (service_dml lists SELECT, INSERT, UPDATE, DELETE held by service_role.)
-- ---------------------------------------------------------------------
INSERT INTO allowed_rel (name, authenticated, service_dml) VALUES
  ('dating_account_restrictions', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_age_verifications', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_algorithm_configs', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_block_hmacs', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_blocks', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_consent_events', 'SELECT', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_date_reflections', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_enrollments', 'SELECT', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_feature_snapshots', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_former_partner_exclusions', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_generation_runs', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_interest_actions', '', ''),
  ('dating_introductions', '', ''),
  ('dating_matches', '', ''),
  ('dating_photo_moderation_config', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_photo_moderation_outbox', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_photo_upload_intents', 'SELECT', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_preferences', 'SELECT', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_profile_photos', 'SELECT', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_profiles', 'SELECT', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_rate_limits', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_reports', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_rpc_idempotency', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('enforcement_records', '', 'DELETE,INSERT,SELECT,UPDATE');

INSERT INTO allowed_fn (sig, clients) VALUES
  ('act_on_dating_introduction(text,uuid,text)', 'authenticated'),
  ('activate_dating_profile(text)', 'authenticated'),
  ('backfill_dating_former_partner_exclusions()', ''),
  ('begin_dating_enrollment(text,text)', 'authenticated'),
  ('block_dating_introduction(text,uuid)', 'authenticated'),
  ('block_dating_match(text,uuid)', 'authenticated'),
  ('block_dating_user(text,uuid)', ''),
  ('build_dating_feature_snapshot(uuid,text)', ''),
  ('bump_dating_enrollment_version()', ''),
  ('bump_dating_profile_version()', ''),
  ('check_dating_rate_limit(text,integer,interval)', ''),
  ('claim_dating_idempotency(text,text)', ''),
  ('claim_dating_photo_jobs(integer,uuid)', ''),
  ('create_dating_photo_upload_intent(text)', ''), -- W1 final fix (N-I1): no client uploads until W3c's inline CSAM match
  ('dating_account_in_good_standing(uuid)', ''),
  ('dating_age_gate_holds(uuid)', ''),
  ('dating_alignment_reasons(jsonb,jsonb)', ''),
  ('dating_alignment_score(jsonb,jsonb,jsonb)', ''),
  ('dating_candidate_is_current(uuid)', ''),
  ('dating_component_similarity(numeric,numeric)', ''),
  ('dating_flag_enabled(text)', ''),
  ('dating_former_partner_excluded(uuid,uuid)', ''),
  ('dating_has_historical_consent(uuid)', ''),
  ('dating_has_relationship(uuid)', ''),
  ('dating_healing_gates_hold(uuid)', ''),
  ('dating_normalize_scalar(numeric,numeric,numeric)', ''),
  ('dating_pair_key(uuid,uuid)', ''),
  ('dating_pair_passes_hard_filters(uuid,uuid)', ''),
  ('dating_phone_canonical(text)', ''),
  ('dating_phone_hmac(text)', ''),
  ('dating_phone_hmac_for_user(uuid)', ''),
  ('dating_photos_queue_media_before_delete()', ''),
  ('dating_profile_ready(uuid)', ''),
  ('dating_set_similarity(jsonb,jsonb)', ''),
  ('delete_dating_profile_photo(uuid)', 'authenticated'),
  ('delete_private_date_reflection(text,uuid)', 'authenticated'),
  ('enforce_dating_age_verification_change()', ''),
  ('enforce_dating_lifecycle_gates()', ''),
  ('enforce_dating_restriction_change()', ''),
  ('enqueue_dating_photo_processing()', ''),
  ('expire_dating_introductions()', ''),
  ('generate_dating_candidates_for_user(uuid,text,text,text)', ''),
  ('get_dating_eligibility()', 'authenticated'),
  ('get_dating_operational_health()', ''),
  ('get_my_dating_introductions(integer)', 'authenticated'),
  ('get_my_dating_matches(integer)', 'authenticated'),
  ('insert_dating_profile_photo(uuid,smallint)', ''), -- W1 final fix (N-I1)
  ('invalidate_dating_for_user(uuid,text)', ''),
  ('invalidate_dating_on_photo_change()', ''),
  ('invalidate_dating_on_profile_change()', ''),
  ('list_dating_profile_photos()', 'authenticated'),
  ('pause_dating_for_relationship_user(uuid)', ''),
  ('pause_dating_mode(text)', 'authenticated'),
  ('private.dating_home_summary(uuid)', ''),
  ('private.dating_exclusion_key_mismatch()', ''),
  ('private.dating_matches_close_on_member_delete()', ''),
  ('private.dating_open_countries()', ''),
  ('private.dating_recompute_former_partner_exclusions()', ''),
  ('record_dating_consent(text,text,text,text,jsonb)', 'authenticated'),
  ('record_dating_date_reflection(text,uuid,text,text)', ''),
  ('record_dating_former_partner_exclusion(uuid,boolean)', ''),
  ('recover_stale_dating_photo_jobs()', ''),
  ('report_dating_introduction(text,uuid,text,text)', 'authenticated'),
  ('report_dating_match(text,uuid,text,text)', 'authenticated'),
  ('resolve_dating_introduction_target(uuid)', ''),
  ('resolve_dating_match_target(uuid)', ''),
  ('resolve_dating_verification_review(uuid,text)', ''),
  ('revoke_dating_age_verification(uuid)', ''),
  ('run_dating_candidate_generation(text)', ''),
  ('save_dating_profile_draft(text,text,text,text,text,integer,integer)', ''), -- W1 final fix (M-9): the v1 draft writer bypasses v2; no API role
  ('save_private_date_reflection(text,uuid,text,text)', 'authenticated'),
  ('submit_dating_report(text,uuid,text,text)', ''),
  ('sync_dating_pause_on_relationship()', ''),
  ('unmatch_dating_match(text,uuid)', 'authenticated'),
  ('verify_dating_age(uuid,date,text,uuid,timestamp with time zone)', '');

-- I-4: every W1a function's service-role EXECUTE, pinned. Only the edge and
-- job entry points keep it; dating_phone_hmac does not (a service key must
-- not test guessed numbers against the survivors' HMACs).
UPDATE allowed_fn SET service = CASE WHEN sig IN (
  'backfill_dating_former_partner_exclusions()',
  'build_dating_feature_snapshot(uuid,text)',
  'claim_dating_photo_jobs(integer,uuid)',
  'get_dating_operational_health()',
  'record_dating_former_partner_exclusion(uuid,boolean)',
  'recover_stale_dating_photo_jobs()',
  'resolve_dating_verification_review(uuid,text)',
  'revoke_dating_age_verification(uuid)',
  'run_dating_candidate_generation(text)',
  'verify_dating_age(uuid,date,text,uuid,timestamp with time zone)') THEN 'service_role' ELSE '' END;

-- I-3: functions outside the Dating names whose body names a Dating
-- relation (Spec 1's). service NULL where Spec 1's own migrations leave the
-- service role's EXECUTE to the hosted default (not this canary's to pin).
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('consume_fresh_start(text,text)', '', 'service_role'),
  ('get_my_home_state()', 'authenticated', NULL),
  ('get_public_app_config()', 'anon,authenticated', NULL),
  ('prepare_account_deletion(uuid)', '', 'service_role'),
  ('private.birth_date_correction_open(uuid)', '', ''),
  ('set_my_path(text,boolean)', 'authenticated', NULL),
  ('set_user_path_internal(uuid,text)', '', NULL);

-- Spec 2 W1a Task 4 (batch-3 fix round 1, I-1/I-2): the deletion carry-over's
-- private helpers and triggers are no API role's, the service role included.
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('private.dating_carry_on_auth_user_delete()', '', ''),
  ('private.dating_deletion_carry(uuid,boolean)', '', ''),
  ('private.dating_stamp_restriction_hmacs()', '', ''),
  ('private.dating_stamp_restriction_on_insert()', '', ''),
  ('private.dating_restriction_user_immutable()', '', ''); -- W1 final fix (M-8)

-- Spec 1 W9d (O4): the Opinions carry-over's helpers name enforcement_records
-- and the Dating HMAC helpers; no API role's, the service role included.
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('private.opinion_carry_on_auth_user_delete()', '', ''),
  ('private.opinion_carry_window()', '', ''),
  ('private.opinion_deletion_carry(uuid,boolean)', '', ''),
  ('private.opinion_enforcement_purge()', '', ''),
  ('private.opinion_stamp_backfill()', '', ''),
  ('private.opinion_stamp_enforcement(uuid,integer,timestamp with time zone)', '', '');
-- Spec 1 W9d (O4): the sign-up restore helper, the same.
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('private.opinion_restore_on_sign_up(uuid)', '', '');

-- ---------------------------------------------------------------------
-- W1b (migration 4): the country model and the session context.
-- service pinned (batch-2 carry): only the two service entry points keep
-- the service role's EXECUTE; the helpers and the trigger are no API
-- role's. country_safety_config_immutable() names no Dating relation, so
-- the scan doesn't reach it; its row and contract G2 pin it anyway.
-- ---------------------------------------------------------------------
INSERT INTO allowed_rel (name, authenticated, service_dml) VALUES
  ('country_safety_config', '', 'SELECT'), -- fix round 1, C-1: the service role only reads it
  ('dating_notify_requests', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_session_context', '', 'DELETE,INSERT,SELECT,UPDATE');
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('dating_country_config(text)', '', ''),
  ('dating_effective_context(text,text,text,text)', '', ''),
  ('get_dating_availability()', 'anon,authenticated', ''),
  ('private.country_config_checks(country_safety_config)', '', ''),
  ('private.country_safety_config_has_current()', '', ''),
  ('private.country_safety_config_immutable()', '', ''),
  ('private.dating_iso_country(text)', '', ''),
  ('private.dating_phone_country(text)', '', ''),
  ('publish_country_config(text,jsonb)', '', 'service_role'),
  ('record_dating_session_context(uuid,text,text)', '', 'service_role');
-- ---------------------------------------------------------------------
-- W1b (migration 5): eligibility. service pinned (batch-2 carry): the
-- gates are the database's own, no API role's, the service role included.
-- ---------------------------------------------------------------------
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('dating_eligibility(uuid,text)', '', '');
-- Fix round 1 (I-1, M-4): the key-readiness predicate and the owner-only
-- seeder are no API role's, the service role included.
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('private.dating_exclusion_key_ready()', '', ''),
  ('private.seed_dating_exclusion_key_fingerprint()', '', '');
-- ---------------------------------------------------------------------
-- W1c (migration 6): the encrypted answers (no API role, the service role
-- included), prompts, settings, the key and consent helpers. service
-- pinned '' (batch-2 carry): the twin revokes the service role on each.
-- ---------------------------------------------------------------------
INSERT INTO allowed_rel (name, authenticated, service_dml) VALUES
  ('dating_profile_sensitive', '', ''),
  ('dating_prompts', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_settings', '', 'DELETE,INSERT,SELECT,UPDATE');
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('dating_require_trusted_device()', '', ''),
  ('private.dating_consent_granted(uuid,text)', '', ''),
  ('private.dating_field_decrypt(bytea)', '', ''),
  ('private.dating_field_encrypt(jsonb)', '', ''),
  ('private.dating_field_key_present()', '', '');
-- Batch-6 fix round 1 (I-2): the display-name trigger function is no API role's.
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('private.dating_profiles_display_name_guard()', '', '');
-- ---------------------------------------------------------------------
-- W1c (migration 7): the D2-D8 writers (the app's) and their helpers.
-- service pinned '' (batch-2 carry): the twin revokes the service role on
-- every writer and helper; private.dating_clear_faith is PF-F3's.
-- ---------------------------------------------------------------------
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('clear_dating_faith(text)', 'authenticated', ''),
  ('private.dating_clear_faith(uuid)', '', ''),
  ('private.dating_lock_same_gender(text)', '', ''), -- fix round 1, I-5
  ('private.dating_lock_setup(uuid)', '', ''), -- fix round 1, I-5
  ('private.dating_lock_setup(uuid,text[])', '', ''), -- W1 final fix (I-1): + the person's same-gender locks
  ('private.dating_default_ages(integer)', '', ''),
  ('private.dating_ensure_profile(uuid)', '', ''),
  ('private.dating_invalid(text)', '', ''),
  ('private.dating_same_gender_on(text)', '', ''),
  ('private.dating_setup_guard()', '', ''),
  ('save_dating_children(text,boolean,text,boolean,boolean)', 'authenticated', ''),
  ('save_dating_faith(text,text,text,text,boolean)', 'authenticated', ''),
  ('save_dating_identity(text,text,text,text,text[],boolean)', 'authenticated', ''),
  ('save_dating_intention(text,text,text,boolean,boolean,text,boolean)', 'authenticated', ''),
  ('save_dating_location(text,text,text,text,text)', 'authenticated', ''),
  ('save_dating_who_to_meet(text,text[],integer,integer)', 'authenticated', '');
-- ---------------------------------------------------------------------
-- W1c (migration 8): the remaining writers and the own-profile readers.
-- service pinned '' (batch-2 carry): the twin revokes the service role on
-- every writer and on both readers (S-4).
-- ---------------------------------------------------------------------
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('get_dating_profile_preview()', 'authenticated', ''),
  ('get_my_dating_profile()', 'authenticated', ''),
  ('save_dating_display_name(text,text)', 'authenticated', ''),
  ('save_dating_family_involvement(text,text)', 'authenticated', ''),
  ('save_dating_prompts(text,jsonb)', 'authenticated', ''),
  ('save_dating_settings(text,jsonb)', 'authenticated', ''),
  ('set_dating_open_abroad(text,character[])', 'authenticated', ''),
  ('set_dating_photos_after_mutual(text,boolean)', 'authenticated', ''),
  -- Batch 8 fix round 1: I-2's sorted locks, "plain" and the prune
  -- (migration 7), M-1's text helpers (migration 8): the database's own.
  ('private.dating_has_invisible(text)', '', ''),
  ('private.dating_lock_same_gender_all(text[])', '', ''),
  ('private.dating_profile_plain(jsonb,jsonb)', '', ''),
  ('private.dating_prune_unsafe_abroad(uuid)', '', ''),
  ('private.dating_trim(text)', '', '');
-- ---------------------------------------------------------------------
-- W1d (migration 9): never introduce. service pinned '' (batch-2 carry):
-- the twin revokes the service role on all five functions; the list is no
-- API role's table, the service role's included (batch-9 fix round 1, M-5).
-- ---------------------------------------------------------------------
INSERT INTO allowed_rel (name, authenticated, service_dml) VALUES
  ('dating_never_introduce', '', '');
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('add_dating_never_introduce(text,text,text)', 'authenticated', ''),
  ('private.dating_typed_phone_e164(text)', '', ''),
  ('dating_never_introduce_excludes(uuid,uuid)', '', ''),
  ('list_dating_never_introduce()', 'authenticated', ''),
  ('remove_dating_never_introduce(uuid)', 'authenticated', '');
-- ---------------------------------------------------------------------
-- W1d (migration 10): the lifecycle (exit_dating_mode(text) and
-- delete_dating_profile(text) are gone; their W1a rows are removed) and the
-- field key's fingerprint (batch-6 M-5). service pinned '' (batch-2
-- carry): the twin revokes the service role on every one.
-- ---------------------------------------------------------------------
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('dating_on_account_parked()', '', ''),
  ('dating_profile_complete(uuid)', '', ''),
  ('exit_dating_mode(text,boolean)', 'authenticated', ''),
  ('private.dating_exit_internal(uuid,boolean)', '', ''),
  ('private.dating_field_key_fingerprint()', '', ''),
  ('private.dating_field_key_ready()', '', ''),
  ('private.dating_field_key_usable()', '', ''),
  ('private.seed_dating_field_key_fingerprint()', '', ''),
  ('resume_dating_mode(text)', 'authenticated', '');
-- ---------------------------------------------------------------------
-- W1d (migration 11): the kill switch, its two helpers and its flag
-- trigger are the database's own; service pinned '' (batch-2 carry: the
-- twin revokes the service role on every one). publish_country_config's
-- row ('service_role') and country_config_checks' ('') are already here.
-- ---------------------------------------------------------------------
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('apply_same_gender_switch(text)', '', ''),
  ('private.dating_same_gender_flag_off()', '', ''),
  ('private.dating_kill_switch_mark(text,text)', '', ''), -- batch-11 fix round 1, I-1
  ('private.dating_switch_identity(uuid,jsonb)', '', ''),
  ('private.dating_switch_read(bytea)', '', '');
-- ---------------------------------------------------------------------
-- Checks (every batch adds its rows above this line).
-- ---------------------------------------------------------------------
CREATE FUNCTION pg_temp.table_privs(p_rel oid, p_role text, p_dml_only boolean) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce(string_agg(x.priv, ',' ORDER BY x.priv), '')
    FROM (SELECT DISTINCT a.privilege_type AS priv
            FROM pg_class AS c, aclexplode(c.relacl) AS a
           WHERE c.oid = p_rel
             AND a.grantee = CASE WHEN p_role = 'PUBLIC' THEN 0 ELSE p_role::regrole::oid END
             AND (NOT p_dml_only OR a.privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE'))) AS x;
$$;

DO $$
DECLARE
  r record;
  v_bad text := '';
  v_allowed allowed_rel%ROWTYPE;
  v_clients text;
  v_service text;
BEGIN
  FOR r IN
    WITH RECURSIVE named AS (
      SELECT c.oid
        FROM pg_class AS c JOIN pg_namespace AS n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public' AND c.relkind IN ('r', 'v', 'm', 'p')
         AND (c.relname ~ '^(dating_|moderation_)' OR c.relname ~ '(gentle_wait|how_we_met)'
              OR c.relname IN ('country_safety_config', 'enforcement_records',
                               'couple_how_we_met', 'law_enforcement_requests'))
    ), scoped AS (
      SELECT oid FROM named
      UNION
      SELECT rw.ev_class
        FROM scoped AS s
        JOIN pg_depend AS d ON d.refclassid = 'pg_class'::regclass AND d.refobjid = s.oid
                           AND d.classid = 'pg_rewrite'::regclass
        JOIN pg_rewrite AS rw ON rw.oid = d.objid
       WHERE rw.ev_class IS DISTINCT FROM s.oid
    )
    SELECT c.oid, c.relname::text AS name, c.relkind, c.relrowsecurity,
           coalesce((SELECT o.option_value FROM pg_options_to_table(c.reloptions) AS o
                      WHERE o.option_name = 'security_invoker'), 'false') IN ('true', 'on', '1') AS invoker
      FROM pg_class AS c JOIN pg_namespace AS n ON n.oid = c.relnamespace
     WHERE c.oid IN (SELECT oid FROM scoped) AND n.nspname = 'public'
     ORDER BY c.relname
  LOOP
    SELECT * INTO v_allowed FROM allowed_rel WHERE name = r.name;
    IF NOT FOUND THEN
      v_bad := v_bad || format(E'\n  %s: not in the canary''s allow-list', r.name);
      CONTINUE;
    END IF;
    IF r.relkind IN ('r', 'p') AND NOT r.relrowsecurity THEN
      v_bad := v_bad || format(E'\n  %s: RLS is off', r.name);
    END IF;
    IF r.relkind = 'v' AND NOT r.invoker THEN
      v_bad := v_bad || format(E'\n  %s: view is not security_invoker', r.name);
    END IF;
    IF pg_temp.table_privs(r.oid, 'PUBLIC', false) IS DISTINCT FROM '' THEN
      v_bad := v_bad || format(E'\n  %s: PUBLIC has %s', r.name, pg_temp.table_privs(r.oid, 'PUBLIC', false));
    END IF;
    IF pg_temp.table_privs(r.oid, 'anon', false) IS DISTINCT FROM v_allowed.anon THEN
      v_bad := v_bad || format(E'\n  %s: anon has [%s], allowed [%s]', r.name, pg_temp.table_privs(r.oid, 'anon', false), v_allowed.anon);
    END IF;
    IF pg_temp.table_privs(r.oid, 'authenticated', false) IS DISTINCT FROM v_allowed.authenticated THEN
      v_bad := v_bad || format(E'\n  %s: authenticated has [%s], allowed [%s]', r.name,
                               pg_temp.table_privs(r.oid, 'authenticated', false), v_allowed.authenticated);
    END IF;
    IF pg_temp.table_privs(r.oid, 'service_role', true) IS DISTINCT FROM v_allowed.service_dml THEN
      v_bad := v_bad || format(E'\n  %s: service_role has [%s], allowed [%s]', r.name,
                               pg_temp.table_privs(r.oid, 'service_role', true), v_allowed.service_dml);
    END IF;
    -- Batch-6 fix round 1 (I-1): no column of a Dating relation carries its
    -- own grant (relacl above misses column ACLs; none is allowed).
    IF EXISTS (SELECT 1 FROM pg_attribute AS a
                WHERE a.attrelid = r.oid AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL) THEN
      v_bad := v_bad || format(E'\n  %s: a column has its own grant (%s)', r.name,
        (SELECT string_agg(a.attname || '=' || a.attacl::text, ', ' ORDER BY a.attnum) FROM pg_attribute AS a
          WHERE a.attrelid = r.oid AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL));
    END IF;
  END LOOP;

  FOR r IN
    SELECT p.oid,
           CASE WHEN n.nspname = 'public' THEN '' ELSE n.nspname || '.' END
             || p.proname || '(' || pg_catalog.oidvectortypes(p.proargtypes) || ')' AS sig
      FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
     WHERE n.nspname IN ('public', 'private')
       AND (p.proname ~ '(dating|date_reflection|gentle_wait|how_we_met)' OR p.proname ~ '^moderation_'
            OR p.proname IN ('publish_country_config', 'apply_same_gender_switch')
            -- W1 final fix (M-5 p2, p3): a BEGIN ATOMIC body (prosrc is empty
            -- there) is read too, and a Dating bucket named by its id
            -- ('dating-profile-photos') is in scope like a Dating relation.
            OR (coalesce(p.prosrc, '') || ' ' || coalesce(pg_get_function_sqlbody(p.oid), ''))
               ~ '\m(dating_[a-z_]+|dating-[a-z-]+|enforcement_records|country_safety_config|couple_how_we_met|law_enforcement_requests)\M')
  LOOP
    r.sig := replace(r.sig, ', ', ',');
    SELECT a.clients, a.service INTO v_clients, v_service FROM allowed_fn AS a WHERE a.sig = r.sig;
    IF NOT FOUND THEN
      v_bad := v_bad || format(E'\n  %s: not in the canary''s allow-list', r.sig);
      CONTINUE;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc AS p2, aclexplode(coalesce(p2.proacl, acldefault('f', p2.proowner))) AS a
                WHERE p2.oid = r.oid AND a.grantee = 0 AND a.privilege_type = 'EXECUTE') THEN
      v_bad := v_bad || format(E'\n  %s: PUBLIC can execute it', r.sig);
    END IF;
    IF concat_ws(',', CASE WHEN has_function_privilege('anon', r.oid, 'EXECUTE') THEN 'anon' END,
                      CASE WHEN has_function_privilege('authenticated', r.oid, 'EXECUTE') THEN 'authenticated' END)
       IS DISTINCT FROM v_clients THEN
      v_bad := v_bad || format(E'\n  %s: clients [%s], allowed [%s]', r.sig,
        concat_ws(',', CASE WHEN has_function_privilege('anon', r.oid, 'EXECUTE') THEN 'anon' END,
                       CASE WHEN has_function_privilege('authenticated', r.oid, 'EXECUTE') THEN 'authenticated' END),
        v_clients);
    END IF;
    IF v_service IS NOT NULL
       AND (CASE WHEN has_function_privilege('service_role', r.oid, 'EXECUTE') THEN 'service_role' ELSE '' END)
           IS DISTINCT FROM v_service THEN
      v_bad := v_bad || format(E'\n  %s: service_role [%s], allowed [%s]', r.sig,
        CASE WHEN has_function_privilege('service_role', r.oid, 'EXECUTE') THEN 'service_role' ELSE '' END, v_service);
    END IF;
  END LOOP;

  -- The API roles never reach schema private, and no private Dating
  -- relation is an API role's.
  IF has_schema_privilege('anon', 'private', 'USAGE') OR has_schema_privilege('authenticated', 'private', 'USAGE') THEN
    v_bad := v_bad || E'\n  schema private: an API role has USAGE';
  END IF;
  FOR r IN
    SELECT c.oid, c.relname::text AS name
      FROM pg_class AS c JOIN pg_namespace AS n ON n.oid = c.relnamespace
     WHERE n.nspname = 'private' AND c.relkind IN ('r', 'v', 'm', 'p') AND c.relname ~ 'dating'
     ORDER BY c.relname
  LOOP
    IF concat(pg_temp.table_privs(r.oid, 'PUBLIC', false), pg_temp.table_privs(r.oid, 'anon', false),
              pg_temp.table_privs(r.oid, 'authenticated', false), pg_temp.table_privs(r.oid, 'service_role', false))
       IS DISTINCT FROM '' THEN
      v_bad := v_bad || format(E'\n  private.%s: an API role has a privilege', r.name);
    END IF;
  END LOOP;

  IF v_bad IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Dating grants differ from the allow-list:%', v_bad;
  END IF;
END $$;

-- S-5: the derived special-category tables are unreadable by every API
-- role, the service role included.
DO $$
DECLARE
  v_t text;
BEGIN
  FOREACH v_t IN ARRAY ARRAY['dating_profile_sensitive', 'dating_messages', 'dating_introductions',
                             'dating_interest_actions', 'dating_matches', 'dating_couple_link_requests'] LOOP
    CONTINUE WHEN to_regclass('public.' || v_t) IS NULL;
    IF has_table_privilege('anon', 'public.' || v_t, 'SELECT')
       OR has_table_privilege('authenticated', 'public.' || v_t, 'SELECT')
       OR has_table_privilege('service_role', 'public.' || v_t, 'SELECT') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: public.% is readable by an API role (S-5)', v_t;
    END IF;
  END LOOP;
END $$;

-- S-4: the only function the service role can execute that decrypts
-- Dating fields is dating_export_for_job (W9); no column stores routing.
-- (PF-F13) publish_country_config, the service role's, decrypts transitively
-- through apply_same_gender_switch and returns no plaintext (a count); this
-- scan reads function text only, so W5 revisits it when generation decrypts.
DO $$
DECLARE
  v_bad text;
BEGIN
  SELECT string_agg(p.oid::regprocedure::text, ', ') INTO v_bad
    FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'private')
     AND p.prosrc LIKE '%dating_field_decrypt%'
     AND p.proname IS DISTINCT FROM 'dating_field_decrypt'
     AND has_function_privilege('service_role', p.oid, 'EXECUTE')
     AND p.proname IS DISTINCT FROM 'dating_export_for_job';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the service role can decrypt Dating fields through %', v_bad;
  END IF;
  IF to_regprocedure('private.dating_field_decrypt(bytea)') IS NOT NULL
     AND has_function_privilege('service_role', 'private.dating_field_decrypt(bytea)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the service role can call dating_field_decrypt';
  END IF;
  SELECT string_agg(c.table_name || '.' || c.column_name, ', ') INTO v_bad
    FROM information_schema.columns AS c
   WHERE c.table_schema = 'public' AND c.column_name LIKE '%routing%'
     AND NOT (c.table_name = 'dating_moderators' AND c.column_name = 'sensitive_routing_allowed');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a column stores routing (S-5): %', v_bad;
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'dating_rls_canary: all held'; END $$;
ROLLBACK;
