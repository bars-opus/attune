-- Dating photo pipeline (20260813130000_dating_photo_pipeline.sql) built the
-- upload-intent flow, moderation outbox, and verification RPCs against a
-- 'dating-profile-photos' storage bucket that was never actually created —
-- no bucket row, no storage.objects RLS policies. Without these, the
-- client's direct .storage.from(bucket).upload(...) call 403s for every
-- user, so no photo can ever be uploaded. Mirrors the chat media bucket
-- pattern (20260705133000_chat_media_month2.sql).

INSERT INTO storage.buckets (id, name, public)
VALUES ('dating-profile-photos', 'dating-profile-photos', false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS dating_profile_photos_insert_by_intent ON storage.objects;
CREATE POLICY dating_profile_photos_insert_by_intent
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'dating-profile-photos'
  AND EXISTS (
    SELECT 1
    FROM public.dating_photo_upload_intents intent
    WHERE intent.storage_key = name
      AND intent.user_id = auth.uid()
      AND intent.used_at IS NULL
      AND intent.expires_at > now()
  )
);

DROP POLICY IF EXISTS dating_profile_photos_select_owner ON storage.objects;
CREATE POLICY dating_profile_photos_select_owner
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'dating-profile-photos'
  AND EXISTS (
    SELECT 1
    FROM public.dating_profile_photos p
    WHERE p.storage_key = name
      AND p.user_id = auth.uid()
  )
);

-- service_role (process-dating-photo, verify-dating-profile) bypasses RLS
-- but still needs base table privileges on storage.objects, same lesson as
-- 20260812120000_grant_service_role_core_tables.sql.
GRANT SELECT ON storage.objects TO service_role;

-- Design spec §4 step 4 / §8 (docs/superpowers/specs/2026-08-02-dating-photo-
-- verification-design.md:53,130): verification is a hard eligibility filter —
-- an unverified or needs_review profile must be excluded from candidate
-- generation entirely, not merely unranked. dating_profile_ready() is the
-- single shared eligibility check behind dating_candidate_is_current(),
-- which both get_my_dating_introductions() queries already call for both
-- parties in a pairing — so gating it here propagates the requirement to
-- every discoverability path without duplicating the filter at each call
-- site. Deliberately NOT added to get_dating_eligibility() (the user's own
-- "can I opt in to Dating Mode" check) or get_my_dating_matches() (an
-- already-matched pair should not be retroactively hidden from each other
-- merely because one party's verification lapsed after matching) — the
-- spec gates discoverability to others, not existing matches or opt-in.
CREATE OR REPLACE FUNCTION public.dating_profile_ready(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.dating_profiles dp
    JOIN public.dating_preferences pref ON pref.user_id = dp.user_id
    WHERE dp.user_id = p_user_id
      AND dp.profile_state = 'active'
      AND dp.moderation_state = 'approved'
      AND dp.verification_state = 'verified'
      AND jsonb_array_length(pref.gender_preferences) > 0
      AND jsonb_array_length(pref.region_preferences) > 0
      AND jsonb_array_length(pref.intention_preferences) > 0
  );
$$;
