-- Dating Mode photo upload, moderation, and verification pipeline.
-- Extends the existing live dating_profile_photos / dating_profiles tables
-- (see 20260703203000_dating_mode_contract_hardening.sql) rather than
-- replacing them.

-- === 1. Extend dating_profile_photos ===

ALTER TABLE public.dating_profile_photos
  ADD COLUMN IF NOT EXISTS rejection_reason text,
  ADD COLUMN IF NOT EXISTS reviewed_at timestamptz,
  ADD COLUMN IF NOT EXISTS attempts smallint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS storage_bucket text NOT NULL DEFAULT 'dating-profile-photos';

ALTER TABLE public.dating_profile_photos
  DROP CONSTRAINT IF EXISTS dating_profile_photos_moderation_state_check;
ALTER TABLE public.dating_profile_photos
  ADD CONSTRAINT dating_profile_photos_moderation_state_check
  CHECK (moderation_state IN ('pending', 'approved', 'rejected', 'needs_review'));

ALTER TABLE public.dating_profile_photos
  DROP CONSTRAINT IF EXISTS dating_profile_photos_position_check;
ALTER TABLE public.dating_profile_photos
  ADD CONSTRAINT dating_profile_photos_position_check
  CHECK (position BETWEEN 1 AND 4);

-- === 2. Extend dating_profiles with verification state ===

ALTER TABLE public.dating_profiles
  ADD COLUMN IF NOT EXISTS verification_state text NOT NULL DEFAULT 'unverified'
    CHECK (verification_state IN ('unverified', 'pending', 'verified', 'needs_review')),
  ADD COLUMN IF NOT EXISTS verification_method text,
  ADD COLUMN IF NOT EXISTS verified_at timestamptz;

-- === 3. Upload intents (mirrors message_media_upload_intents) ===

CREATE TABLE IF NOT EXISTS public.dating_photo_upload_intents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  storage_key text NOT NULL UNIQUE,
  mime_type text NOT NULL,
  expires_at timestamptz NOT NULL,
  used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dating_photo_upload_intents_lookup
  ON public.dating_photo_upload_intents(user_id, expires_at DESC);

ALTER TABLE public.dating_photo_upload_intents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.dating_photo_upload_intents FROM anon, authenticated;

-- === 4. Moderation outbox (mirrors message_media_processing_outbox) ===

CREATE TABLE IF NOT EXISTS public.dating_photo_moderation_outbox (
  photo_id uuid PRIMARY KEY REFERENCES public.dating_profile_photos(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  state text NOT NULL DEFAULT 'pending'
    CHECK (state IN ('pending', 'processing', 'done', 'dead_letter')),
  attempts smallint NOT NULL DEFAULT 0,
  last_error_code text,
  processing_started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dating_photo_moderation_outbox_pending
  ON public.dating_photo_moderation_outbox(state, created_at);

ALTER TABLE public.dating_photo_moderation_outbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.dating_photo_moderation_outbox FROM anon, authenticated;

DROP TRIGGER IF EXISTS set_dating_photo_moderation_outbox_updated_at
  ON public.dating_photo_moderation_outbox;
CREATE TRIGGER set_dating_photo_moderation_outbox_updated_at
BEFORE UPDATE ON public.dating_photo_moderation_outbox
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- === 5. Moderation thresholds (server-side config, not hardcoded) ===

CREATE TABLE IF NOT EXISTS public.dating_photo_moderation_config (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  min_dimension_px int NOT NULL DEFAULT 600,
  min_face_confidence numeric NOT NULL DEFAULT 0.7,
  min_face_area_ratio numeric NOT NULL DEFAULT 0.06,
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.dating_photo_moderation_config (id)
VALUES (true)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.dating_photo_moderation_config ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.dating_photo_moderation_config FROM anon, authenticated;

-- === 6. Upload intent RPC (mirrors create_chat_media_upload_intent) ===

CREATE OR REPLACE FUNCTION public.create_dating_photo_upload_intent(
  p_mime_type text
)
RETURNS TABLE (
  intent_id uuid,
  storage_key text,
  expires_at timestamptz,
  bucket text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_extension text;
  v_storage_key text;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_mime_type NOT IN ('image/jpeg', 'image/png', 'image/webp') THEN
    RAISE EXCEPTION 'Unsupported image type';
  END IF;

  v_extension := CASE p_mime_type
    WHEN 'image/png' THEN 'png'
    WHEN 'image/webp' THEN 'webp'
    ELSE 'jpg'
  END;

  v_storage_key := 'dating-photos/' || encode(gen_random_bytes(16), 'hex') || '.' || v_extension;

  INSERT INTO public.dating_photo_upload_intents (
    user_id, storage_key, mime_type, expires_at
  ) VALUES (
    v_user_id, v_storage_key, p_mime_type, now() + interval '15 minutes'
  )
  RETURNING dating_photo_upload_intents.id, dating_photo_upload_intents.storage_key,
            dating_photo_upload_intents.expires_at
  INTO intent_id, storage_key, expires_at;

  bucket := 'dating-profile-photos';
  RETURN NEXT;
END;
$$;

-- === 7. Insert photo row (validates intent, enforces max 4, enqueues job) ===

CREATE OR REPLACE FUNCTION public.insert_dating_profile_photo(
  p_intent_id uuid,
  p_position smallint
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
DECLARE
  v_user_id uuid;
  v_intent public.dating_photo_upload_intents%ROWTYPE;
  v_object storage.objects%ROWTYPE;
  v_photo_count int;
  v_photo_id uuid;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_position NOT BETWEEN 1 AND 4 THEN
    RAISE EXCEPTION 'Invalid photo position';
  END IF;

  SELECT * INTO v_intent
  FROM public.dating_photo_upload_intents
  WHERE id = p_intent_id
    AND user_id = v_user_id
    AND used_at IS NULL
    AND expires_at > now()
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Upload intent is invalid or expired';
  END IF;

  SELECT * INTO v_object FROM storage.objects o
  WHERE o.bucket_id = 'dating-profile-photos' AND o.name = v_intent.storage_key;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Uploaded object is missing';
  END IF;

  SELECT count(*) INTO v_photo_count
  FROM public.dating_profile_photos
  WHERE user_id = v_user_id;
  IF v_photo_count >= 4 THEN
    RAISE EXCEPTION 'Maximum of 4 photos already reached';
  END IF;

  UPDATE public.dating_photo_upload_intents SET used_at = now() WHERE id = p_intent_id;

  INSERT INTO public.dating_profile_photos (
    user_id, storage_key, position, moderation_state
  ) VALUES (
    v_user_id, v_intent.storage_key, p_position, 'pending'
  )
  ON CONFLICT (user_id, position) DO UPDATE
    SET storage_key = EXCLUDED.storage_key,
        moderation_state = 'pending',
        rejection_reason = NULL,
        reviewed_at = NULL,
        attempts = 0
  RETURNING id INTO v_photo_id;

  INSERT INTO public.dating_photo_moderation_outbox (photo_id, user_id)
  VALUES (v_photo_id, v_user_id)
  ON CONFLICT (photo_id) DO UPDATE
    SET state = 'pending', attempts = 0, last_error_code = NULL,
        processing_started_at = NULL, completed_at = NULL, updated_at = now();

  -- Replacing an existing approved photo invalidates prior verification,
  -- per spec §4 step 5: a new photo must also match the verification selfie.
  UPDATE public.dating_profiles
  SET verification_state = 'needs_review'
  WHERE user_id = v_user_id AND verification_state = 'verified';

  RETURN v_photo_id;
END;
$$;

-- === 8. Delete photo row ===

CREATE OR REPLACE FUNCTION public.delete_dating_profile_photo(
  p_photo_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  DELETE FROM public.dating_profile_photos
  WHERE id = p_photo_id AND user_id = v_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Photo not found';
  END IF;
END;
$$;

-- === 9. List own photos ===

CREATE OR REPLACE FUNCTION public.list_dating_profile_photos()
RETURNS TABLE (
  id uuid,
  "position" smallint,
  moderation_state text,
  rejection_reason text,
  storage_key text,
  created_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id, p.position, p.moderation_state, p.rejection_reason, p.storage_key, p.created_at
  FROM public.dating_profile_photos p
  WHERE p.user_id = auth.uid()
  ORDER BY p.position;
$$;

-- === 9b. Auto-invoke the worker on enqueue (mirrors
-- enqueue_chat_media_processing exactly — without this, jobs sit in
-- 'pending' forever with nothing to claim them) ===

CREATE OR REPLACE FUNCTION public.enqueue_dating_photo_processing()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_supabase_url text;
  v_service_role_key text;
BEGIN
  v_supabase_url := current_setting('app.settings.supabase_url', true);
  v_service_role_key := current_setting('app.settings.service_role_key', true);
  IF v_supabase_url IS NOT NULL AND v_service_role_key IS NOT NULL THEN
    BEGIN
      PERFORM net.http_post(
        url := v_supabase_url || '/functions/v1/process-dating-photo',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_role_key,
          'apikey', v_service_role_key
        ),
        body := jsonb_build_object('photo_id', NEW.photo_id)
      );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_enqueue_dating_photo_processing
  ON public.dating_photo_moderation_outbox;
CREATE TRIGGER trigger_enqueue_dating_photo_processing
AFTER INSERT ON public.dating_photo_moderation_outbox
FOR EACH ROW EXECUTE FUNCTION public.enqueue_dating_photo_processing();

-- Fallback for when the HTTP call above fails (network blip, function cold
-- start) — mirrors this repo's recover_stale_chat_worker_leases pattern
-- being paired with a periodic sweep. recover_stale_dating_photo_jobs
-- (defined below in §12) only recovers jobs already claimed and stuck in
-- 'processing'; it does NOT pick up jobs that never got an HTTP call in the
-- first place. A separate periodic invocation of process-dating-photo
-- itself (which claims any 'pending' job, not just stale 'processing' ones)
-- is required as an operator-configured cron — same open item already
-- flagged in the manual verification checklist at the end of this plan.

-- === 10. Verification review resolution (service-role only; no admin UI yet,
-- but the resolution path must exist per spec §4) ===

CREATE OR REPLACE FUNCTION public.resolve_dating_verification_review(
  p_user_id uuid,
  p_outcome text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_outcome NOT IN ('verified', 'unverified') THEN
    RAISE EXCEPTION 'Invalid outcome';
  END IF;

  UPDATE public.dating_profiles
  SET verification_state = p_outcome,
      verified_at = CASE WHEN p_outcome = 'verified' THEN now() ELSE NULL END
  WHERE user_id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile not found';
  END IF;
END;
$$;

-- === 11. Claim jobs (mirrors claim_chat_media_jobs exactly) ===

CREATE OR REPLACE FUNCTION public.claim_dating_photo_jobs(
  p_limit int DEFAULT 20,
  p_photo_id uuid DEFAULT NULL
)
RETURNS SETOF public.dating_photo_moderation_outbox
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.dating_photo_moderation_outbox o
  SET state = 'processing',
      attempts = attempts + 1,
      processing_started_at = now(),
      updated_at = now(),
      last_error_code = NULL
  WHERE o.photo_id IN (
    SELECT photo_id FROM public.dating_photo_moderation_outbox
    WHERE state = 'pending'
      AND (p_photo_id IS NULL OR photo_id = p_photo_id)
    ORDER BY created_at
    FOR UPDATE SKIP LOCKED
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
  )
  RETURNING o.*;
$$;

-- === 12. Stale-lease recovery (mirrors recover_stale_chat_worker_leases) ===

CREATE OR REPLACE FUNCTION public.recover_stale_dating_photo_jobs()
RETURNS TABLE(recovered bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count bigint;
BEGIN
  UPDATE public.dating_photo_moderation_outbox
  SET state = CASE WHEN attempts >= 5 THEN 'dead_letter' ELSE 'pending' END,
      processing_started_at = NULL,
      last_error_code = 'stale_lease',
      completed_at = CASE WHEN attempts >= 5 THEN now() ELSE NULL END,
      updated_at = now()
  WHERE state = 'processing' AND processing_started_at < now() - interval '5 minutes';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  recovered := v_count;
  RETURN NEXT;
END;
$$;

-- === 13. Grants ===

REVOKE ALL ON FUNCTION public.create_dating_photo_upload_intent(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.insert_dating_profile_photo(uuid, smallint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_dating_profile_photo(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_dating_profile_photos() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.resolve_dating_verification_review(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_dating_photo_jobs(int, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.recover_stale_dating_photo_jobs() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_dating_photo_upload_intent(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.insert_dating_profile_photo(uuid, smallint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_dating_profile_photo(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_dating_profile_photos() TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_dating_verification_review(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_dating_photo_jobs(int, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.recover_stale_dating_photo_jobs() TO service_role;

-- service_role needs direct table access for the worker (same lesson as
-- 20260812120000_grant_service_role_core_tables.sql — RLS is bypassed for
-- service_role, but base table privileges are still checked first):
GRANT SELECT, UPDATE ON public.dating_profile_photos TO service_role;
GRANT SELECT ON public.dating_photo_moderation_config TO service_role;
GRANT SELECT, UPDATE ON public.dating_profiles TO service_role;
