-- get_dating_operational_health reports flags, stuck runs and moderation
-- backlogs, but says nothing about dating_exclusion_key.
--
-- That key is the one dependency whose absence fails SILENTLY in a
-- direction that matters. record_dating_former_partner_exclusion is
-- wrapped in an EXCEPTION handler inside end_relationship (deliberately --
-- a dating feature must never stop someone leaving a relationship), so an
-- unset key means every relationship that ends records NO exclusion and
-- raises only a WARNING into the Postgres log. The former partners stay
-- mutually matchable, and nothing surfaces it.
--
-- Checklist 4.9: every failure mode needs an alert. Two fields:
--
--   exclusion_key_present  -- false is a hard blocker on the
--                             dating_candidate_generation flag
--   relationships_ended_without_exclusion_24h
--                          -- the damage already done: relationships that
--                             ended with no exclusion row for either party
--
-- The second is what catches a key that goes missing AFTER launch, when
-- the first would read true at deploy time and drift later.
CREATE OR REPLACE FUNCTION public.get_dating_operational_health()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
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
    'pending_photo_moderation',(SELECT count(*) FROM public.dating_profile_photos WHERE moderation_state='pending')
  );
$$;

-- Unchanged from 20260705210000: backend-only. Restated because CREATE OR
-- REPLACE keeps existing grants and this must never drift to authenticated.
REVOKE ALL ON FUNCTION public.get_dating_operational_health() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_dating_operational_health() TO service_role;
