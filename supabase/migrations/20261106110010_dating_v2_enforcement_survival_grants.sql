-- Spec 2 W1a: grants for 20261106110000_dating_v2_enforcement_survival.sql,
-- and every Dating table's client grants re-asserted (spec §4.1, §4.5):
-- clients reach Dating through definer RPCs only; until W3a the app still
-- SELECTs its own rows from the four 20260811120000 tables and the two the
-- photo upload and Storage policies read (the owner-read policies keep
-- those reads to the person's own rows). S-5: introductions, interest
-- actions and matches are revoked from service_role too (no edge function
-- reads them; every reader is a definer function). The two new tables are
-- the service role's (the console, W7) and nobody else's. Every Dating
-- function is revoked from service_role too (hosted projects grant it every
-- new public function) and granted back only to the edge and job entry
-- points; dating_phone_hmac is not one (I-4).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.dating_account_restrictions, public.dating_age_verifications,
  public.dating_algorithm_configs, public.dating_blocks, public.dating_consent_events,
  public.dating_date_reflections, public.dating_enrollments, public.dating_feature_snapshots,
  public.dating_former_partner_exclusions, public.dating_generation_runs,
  public.dating_interest_actions, public.dating_introductions, public.dating_matches,
  public.dating_photo_moderation_config, public.dating_photo_moderation_outbox,
  public.dating_photo_upload_intents, public.dating_preferences, public.dating_profile_photos,
  public.dating_profiles, public.dating_rate_limits, public.dating_reports,
  public.dating_rpc_idempotency
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.dating_enrollments, public.dating_consent_events, public.dating_profiles,
  public.dating_preferences, public.dating_profile_photos, public.dating_photo_upload_intents
  TO authenticated;
REVOKE ALL ON public.dating_introductions, public.dating_interest_actions, public.dating_matches
  FROM service_role;
REVOKE ALL ON public.enforcement_records, public.dating_block_hmacs FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.enforcement_records, public.dating_block_hmacs TO service_role;
REVOKE ALL ON FUNCTION public.block_dating_user(text, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_account_in_good_standing(uuid) FROM PUBLIC, anon, authenticated, service_role;
-- Every Dating function's client EXECUTE, re-asserted (hosted projects
-- grant new public functions to anon and authenticated by default; the
-- canary checks the result): no PUBLIC, no anon; authenticated only on the
-- client RPCs; the service role keeps its edge-function entry points.
REVOKE ALL ON FUNCTION
  public.act_on_dating_introduction(text, uuid, text),
  public.activate_dating_profile(text),
  public.backfill_dating_former_partner_exclusions(),
  public.begin_dating_enrollment(text, text),
  public.block_dating_introduction(text, uuid),
  public.block_dating_match(text, uuid),
  public.block_dating_user(text, uuid),
  public.build_dating_feature_snapshot(uuid, text),
  public.bump_dating_enrollment_version(),
  public.bump_dating_profile_version(),
  public.check_dating_rate_limit(text, integer, interval),
  public.claim_dating_idempotency(text, text),
  public.claim_dating_photo_jobs(integer, uuid),
  public.create_dating_photo_upload_intent(text),
  public.dating_account_in_good_standing(uuid),
  public.dating_age_gate_holds(uuid),
  public.dating_alignment_reasons(jsonb, jsonb),
  public.dating_alignment_score(jsonb, jsonb, jsonb),
  public.dating_candidate_is_current(uuid),
  public.dating_component_similarity(numeric, numeric),
  public.dating_flag_enabled(text),
  public.dating_former_partner_excluded(uuid, uuid),
  public.dating_has_historical_consent(uuid),
  public.dating_has_relationship(uuid),
  public.dating_healing_gates_hold(uuid),
  public.dating_normalize_scalar(numeric, numeric, numeric),
  public.dating_pair_key(uuid, uuid),
  public.dating_pair_passes_hard_filters(uuid, uuid),
  public.dating_phone_canonical(text),
  public.dating_phone_hmac(text),
  public.dating_phone_hmac_for_user(uuid),
  public.dating_photos_queue_media_before_delete(),
  public.dating_profile_ready(uuid),
  public.dating_set_similarity(jsonb, jsonb),
  public.delete_dating_profile_photo(uuid),
  public.delete_private_date_reflection(text, uuid),
  public.enforce_dating_age_verification_change(),
  public.enforce_dating_lifecycle_gates(),
  public.enforce_dating_restriction_change(),
  public.enqueue_dating_photo_processing(),
  public.expire_dating_introductions(),
  public.generate_dating_candidates_for_user(uuid, text, text, text),
  public.get_dating_eligibility(),
  public.get_dating_operational_health(),
  public.get_my_dating_introductions(integer),
  public.get_my_dating_matches(integer),
  public.insert_dating_profile_photo(uuid, smallint),
  public.invalidate_dating_for_user(uuid, text),
  public.invalidate_dating_on_photo_change(),
  public.invalidate_dating_on_profile_change(),
  public.list_dating_profile_photos(),
  public.pause_dating_for_relationship_user(uuid),
  public.pause_dating_mode(text),
  public.record_dating_consent(text, text, text, text, jsonb),
  public.record_dating_date_reflection(text, uuid, text, text),
  public.record_dating_former_partner_exclusion(uuid, boolean),
  public.recover_stale_dating_photo_jobs(),
  public.report_dating_introduction(text, uuid, text, text),
  public.report_dating_match(text, uuid, text, text),
  public.resolve_dating_introduction_target(uuid),
  public.resolve_dating_match_target(uuid),
  public.resolve_dating_verification_review(uuid, text),
  public.revoke_dating_age_verification(uuid),
  public.run_dating_candidate_generation(text),
  public.save_dating_profile_draft(text, text, text, text, text, integer, integer),
  public.save_private_date_reflection(text, uuid, text, text),
  public.submit_dating_report(text, uuid, text, text),
  public.sync_dating_pause_on_relationship(),
  public.unmatch_dating_match(text, uuid),
  public.verify_dating_age(uuid, date, text, uuid, timestamp with time zone),
  private.dating_home_summary(uuid),
  private.dating_open_countries(),
  private.dating_exclusion_key_mismatch(),
  private.dating_matches_close_on_member_delete()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON private.dating_key_fingerprints FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION
  public.act_on_dating_introduction(text, uuid, text),
  public.activate_dating_profile(text),
  public.begin_dating_enrollment(text, text),
  public.block_dating_introduction(text, uuid),
  public.block_dating_match(text, uuid),
  public.delete_dating_profile_photo(uuid),
  public.delete_private_date_reflection(text, uuid),
  public.get_dating_eligibility(),
  public.get_my_dating_introductions(integer),
  public.get_my_dating_matches(integer),
  public.list_dating_profile_photos(),
  public.pause_dating_mode(text),
  public.record_dating_consent(text, text, text, text, jsonb),
  public.report_dating_introduction(text, uuid, text, text),
  public.report_dating_match(text, uuid, text, text),
  public.save_private_date_reflection(text, uuid, text, text),
  public.unmatch_dating_match(text, uuid)
  TO authenticated;
-- W1 final fix (I-2): exit_dating_mode(text) and delete_dating_profile(text)
-- are dropped by migration 10 (20261106190000), so this twin re-asserts
-- them only where they still exist (a replay after migration 10, such as
-- scripts/local_pg_grants.sql, skips them; on a first apply they exist and
-- get exactly the grants above: no API role but authenticated).
-- W1 final fix (M-9): save_dating_profile_draft is no longer in the list
-- above (revoked from every API role; migration 11 says so again), nor are
-- the v1 photo writers create_dating_photo_upload_intent and
-- insert_dating_profile_photo (N-I1: they check nothing, and the bucket has
-- no CSAM scan until W3c's inline match; W3 re-creates and re-grants them).
DO $$
DECLARE
  v_sig text;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY['public.exit_dating_mode(text)', 'public.delete_dating_profile(text)'] LOOP
    IF to_regprocedure(v_sig) IS NOT NULL THEN
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role', v_sig);
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_sig);
    END IF;
  END LOOP;
END $$;
GRANT EXECUTE ON FUNCTION
  public.backfill_dating_former_partner_exclusions(),
  public.build_dating_feature_snapshot(uuid, text),
  public.claim_dating_photo_jobs(integer, uuid),
  public.get_dating_operational_health(),
  public.record_dating_former_partner_exclusion(uuid, boolean),
  public.recover_stale_dating_photo_jobs(),
  public.resolve_dating_verification_review(uuid, text),
  public.revoke_dating_age_verification(uuid),
  public.run_dating_candidate_generation(text),
  public.verify_dating_age(uuid, date, text, uuid, timestamp with time zone)
  TO service_role;
COMMIT;
