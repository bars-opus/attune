-- Couple-chosen chat identity: a relationship-scoped name and photo,
-- editable by either partner, distinct from either person's own profile.
-- See docs/superpowers/specs/2026-08-11-couple-chat-identity-design.md.
--
-- Pipeline shape mirrors the existing chat-media and dating-photo upload
-- pipelines (server-generated storage key, one-time-use upload intents,
-- async processing outbox with worker-claim/stale-lease-recovery) for
-- consistency and operability, per Algorithm Quality Review Checklist
-- v3.1. Deliberately does NOT include dating-photo's face-detection
-- moderation step — a relationship avatar has no dating-style trust/safety
-- requirement for a verifiable human face (see spec's Checklist section).

-- === 1. Identity columns on relationships ===
--
-- No new RLS policy needed for these three columns: "relationship members
-- update limited" (20260606120000_attune_core_schema.sql) already lets
-- either user_a or user_b UPDATE their relationship row.

ALTER TABLE public.relationships
  ADD COLUMN IF NOT EXISTS chat_name text,
  ADD COLUMN IF NOT EXISTS chat_avatar_url text,
  ADD COLUMN IF NOT EXISTS chat_avatar_thumbnail_url text;

-- Checklist 2.1 (input sanitization) backstop at the DB layer: length is
-- also validated client-side before the write, but a constraint means a
-- bypassed/buggy client can never persist an invalid value. Trimmed length
-- 1-30 — empty-after-trim is rejected the same as NULL (unset), not stored
-- as a blank string that would silently win over the partner's real name.
ALTER TABLE public.relationships
  ADD CONSTRAINT relationships_chat_name_length
  CHECK (chat_name IS NULL OR char_length(trim(chat_name)) BETWEEN 1 AND 30);

COMMENT ON COLUMN public.relationships.chat_name IS
  'Couple-chosen display name for this relationship''s chat, e.g. "Japerl34". Null until either partner sets one; conversation display falls back to the partner''s own display_name until then.';
COMMENT ON COLUMN public.relationships.chat_avatar_url IS
  'Couple-chosen full-size avatar for this relationship''s chat. Storage key under relationship-avatars/, set by set_relationship_avatar(). Null until either partner sets one.';
COMMENT ON COLUMN public.relationships.chat_avatar_thumbnail_url IS
  'Async-generated 400px thumbnail of chat_avatar_url, populated by process-relationship-avatar. Null until the background job completes; UI falls back to chat_avatar_url until then.';

-- === 2. Upload intents (mirrors dating_photo_upload_intents) ===

CREATE TABLE IF NOT EXISTS public.relationship_avatar_upload_intents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  requester_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  storage_key text NOT NULL UNIQUE,
  mime_type text NOT NULL,
  expires_at timestamptz NOT NULL,
  used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_relationship_avatar_upload_intents_lookup
  ON public.relationship_avatar_upload_intents(relationship_id, expires_at DESC);

ALTER TABLE public.relationship_avatar_upload_intents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.relationship_avatar_upload_intents FROM anon, authenticated;

-- === 3. Processing outbox (mirrors message_media_processing_outbox) ===
--
-- Thumbnail generation only — see file header on why no moderation state
-- exists here (contrast dating_photo_moderation_outbox's moderation_state).

CREATE TABLE IF NOT EXISTS public.relationship_avatar_processing_outbox (
  relationship_id uuid PRIMARY KEY REFERENCES public.relationships(id) ON DELETE CASCADE,
  storage_key text NOT NULL,
  state text NOT NULL DEFAULT 'pending'
    CHECK (state IN ('pending', 'processing', 'done', 'dead_letter')),
  attempts smallint NOT NULL DEFAULT 0,
  last_error_code text,
  processing_started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_relationship_avatar_processing_outbox_pending
  ON public.relationship_avatar_processing_outbox(state, created_at);

ALTER TABLE public.relationship_avatar_processing_outbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.relationship_avatar_processing_outbox FROM anon, authenticated;

DROP TRIGGER IF EXISTS set_relationship_avatar_processing_outbox_updated_at
  ON public.relationship_avatar_processing_outbox;
CREATE TRIGGER set_relationship_avatar_processing_outbox_updated_at
BEFORE UPDATE ON public.relationship_avatar_processing_outbox
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- === 4. Upload intent RPC (mirrors create_dating_photo_upload_intent /
-- create_chat_media_upload_intent) ===

CREATE OR REPLACE FUNCTION public.create_relationship_avatar_upload_intent(
  p_relationship_id uuid,
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
  v_relationship public.relationships%ROWTYPE;
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

  -- Checklist 1.4: authorization at the resource-access point, not just
  -- entry — only an active relationship's own member may request an
  -- intent for it.
  SELECT * INTO v_relationship
  FROM public.relationships
  WHERE id = p_relationship_id
    AND status = 'active'
    AND (user_a = v_user_id OR user_b = v_user_id);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Relationship not available for chat avatar upload';
  END IF;

  v_extension := CASE p_mime_type
    WHEN 'image/png' THEN 'png'
    WHEN 'image/webp' THEN 'webp'
    ELSE 'jpg'
  END;

  v_storage_key := 'relationship-avatars/' || p_relationship_id || '/' ||
    encode(gen_random_bytes(16), 'hex') || '.' || v_extension;

  INSERT INTO public.relationship_avatar_upload_intents (
    relationship_id, requester_id, storage_key, mime_type, expires_at
  ) VALUES (
    p_relationship_id, v_user_id, v_storage_key, p_mime_type, now() + interval '15 minutes'
  )
  RETURNING relationship_avatar_upload_intents.id,
            relationship_avatar_upload_intents.storage_key,
            relationship_avatar_upload_intents.expires_at
  INTO intent_id, storage_key, expires_at;

  bucket := 'relationship-avatars';
  RETURN NEXT;
END;
$$;

-- === 5. Apply photo RPC (validates intent + uploaded object, writes
-- chat_avatar_url, enqueues thumbnail job) ===
--
-- Checklist 2.18 (idempotency): a single-use intent means retrying this
-- call with the same intent_id after success fails cleanly at the
-- used_at IS NULL check below rather than double-applying.

CREATE OR REPLACE FUNCTION public.set_relationship_avatar(
  p_relationship_id uuid,
  p_intent_id uuid
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
DECLARE
  v_user_id uuid;
  v_intent public.relationship_avatar_upload_intents%ROWTYPE;
  v_object storage.objects%ROWTYPE;
  v_size bigint;
  v_mime text;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.relationships
    WHERE id = p_relationship_id
      AND status = 'active'
      AND (user_a = v_user_id OR user_b = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Relationship not available for chat avatar upload';
  END IF;

  SELECT * INTO v_intent
  FROM public.relationship_avatar_upload_intents
  WHERE id = p_intent_id
    AND relationship_id = p_relationship_id
    AND requester_id = v_user_id
    AND used_at IS NULL
    AND expires_at > now()
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Upload intent is invalid or expired';
  END IF;

  -- Checklist 2.5 (resource limits): the 800KB cap is enforced against the
  -- ACTUAL uploaded object's metadata, not trusted from client input.
  SELECT * INTO v_object FROM storage.objects o
  WHERE o.bucket_id = 'relationship-avatars' AND o.name = v_intent.storage_key;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Uploaded object is missing';
  END IF;
  v_size := COALESCE((v_object.metadata->>'size')::bigint, 0);
  v_mime := COALESCE(v_object.metadata->>'mimetype', v_object.metadata->>'contentType');
  IF v_size <= 0 OR v_size > 819200 OR v_mime IS DISTINCT FROM v_intent.mime_type THEN
    RAISE EXCEPTION 'Uploaded object failed validation';
  END IF;

  UPDATE public.relationship_avatar_upload_intents SET used_at = now() WHERE id = p_intent_id;

  UPDATE public.relationships
  SET chat_avatar_url = v_intent.storage_key,
      chat_avatar_thumbnail_url = NULL
  WHERE id = p_relationship_id;

  INSERT INTO public.relationship_avatar_processing_outbox (relationship_id, storage_key)
  VALUES (p_relationship_id, v_intent.storage_key)
  ON CONFLICT (relationship_id) DO UPDATE
    SET storage_key = EXCLUDED.storage_key,
        state = 'pending', attempts = 0, last_error_code = NULL,
        processing_started_at = NULL, completed_at = NULL, updated_at = now();

  RETURN v_intent.storage_key;
END;
$$;

-- === 6. Set chat name (validated write; DB constraint above is the
-- backstop, this is the primary entry point either partner uses) ===

CREATE OR REPLACE FUNCTION public.set_relationship_chat_name(
  p_relationship_id uuid,
  p_chat_name text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_trimmed text;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  v_trimmed := trim(p_chat_name);
  IF char_length(v_trimmed) < 1 OR char_length(v_trimmed) > 30 THEN
    RAISE EXCEPTION 'Chat name must be between 1 and 30 characters';
  END IF;

  UPDATE public.relationships
  SET chat_name = v_trimmed
  WHERE id = p_relationship_id
    AND status = 'active'
    AND (user_a = v_user_id OR user_b = v_user_id);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Relationship not available';
  END IF;
END;
$$;

-- === 7. Auto-invoke the worker on enqueue (mirrors
-- enqueue_dating_photo_processing / enqueue_chat_media_processing) ===

CREATE OR REPLACE FUNCTION public.enqueue_relationship_avatar_processing()
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
        url := v_supabase_url || '/functions/v1/process-relationship-avatar',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_role_key,
          'apikey', v_service_role_key
        ),
        body := jsonb_build_object('relationship_id', NEW.relationship_id)
      );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_enqueue_relationship_avatar_processing
  ON public.relationship_avatar_processing_outbox;
CREATE TRIGGER trigger_enqueue_relationship_avatar_processing
AFTER INSERT ON public.relationship_avatar_processing_outbox
FOR EACH ROW EXECUTE FUNCTION public.enqueue_relationship_avatar_processing();

-- === 8. Claim jobs (mirrors claim_dating_photo_jobs / claim_chat_media_jobs) ===

CREATE OR REPLACE FUNCTION public.claim_relationship_avatar_jobs(
  p_limit int DEFAULT 20,
  p_relationship_id uuid DEFAULT NULL
)
RETURNS SETOF public.relationship_avatar_processing_outbox
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.relationship_avatar_processing_outbox o
  SET state = 'processing',
      attempts = attempts + 1,
      processing_started_at = now(),
      updated_at = now(),
      last_error_code = NULL
  WHERE o.relationship_id IN (
    SELECT relationship_id FROM public.relationship_avatar_processing_outbox
    WHERE state = 'pending'
      AND (p_relationship_id IS NULL OR relationship_id = p_relationship_id)
    ORDER BY created_at
    FOR UPDATE SKIP LOCKED
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
  )
  RETURNING o.*;
$$;

-- === 9. Stale-lease recovery (mirrors recover_stale_dating_photo_jobs /
-- recover_stale_chat_worker_leases) — same 5-attempt dead-letter
-- threshold, same 5-minute stale-processing window as the existing
-- pipelines (Checklist 3.9: retry bounds copied verbatim, not reinvented) ===

CREATE OR REPLACE FUNCTION public.recover_stale_relationship_avatar_jobs()
RETURNS TABLE(recovered bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count bigint;
BEGIN
  UPDATE public.relationship_avatar_processing_outbox
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

-- === 10. Storage bucket + RLS ===
--
-- 20260813130000_dating_photo_pipeline.sql built its RPCs/tables against a
-- bucket that didn't exist yet and needed a follow-up fix
-- (20260813140000_dating_photo_storage_bucket.sql) once every upload 403'd.
-- Creating the bucket and BOTH policies (insert-by-intent, select-by-
-- membership) in this same migration avoids repeating that gap.

INSERT INTO storage.buckets (id, name, public)
VALUES ('relationship-avatars', 'relationship-avatars', false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS relationship_avatars_insert_by_intent ON storage.objects;
CREATE POLICY relationship_avatars_insert_by_intent
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'relationship-avatars'
  AND EXISTS (
    SELECT 1
    FROM public.relationship_avatar_upload_intents intent
    WHERE intent.storage_key = name
      AND intent.requester_id = auth.uid()
      AND intent.used_at IS NULL
      AND intent.expires_at > now()
  )
);

-- Mirrors message_media_select_relationship_members: relationship members
-- only, checked against whichever of the two URL columns matches.
DROP POLICY IF EXISTS relationship_avatars_select_members ON storage.objects;
CREATE POLICY relationship_avatars_select_members
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'relationship-avatars'
  AND EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE (r.chat_avatar_url = name OR r.chat_avatar_thumbnail_url = name)
      AND auth.uid() IN (r.user_a, r.user_b)
  )
);

-- service_role (process-relationship-avatar worker) bypasses RLS but still
-- needs base table privileges on storage.objects, same lesson as
-- 20260812120000_grant_service_role_core_tables.sql /
-- 20260813140000_dating_photo_storage_bucket.sql.
GRANT SELECT, INSERT ON storage.objects TO service_role;

-- === 11. Grants ===

REVOKE ALL ON FUNCTION public.create_relationship_avatar_upload_intent(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_relationship_avatar(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_relationship_chat_name(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.claim_relationship_avatar_jobs(int, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.recover_stale_relationship_avatar_jobs() FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.create_relationship_avatar_upload_intent(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_relationship_avatar(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_relationship_chat_name(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_relationship_avatar_jobs(int, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.recover_stale_relationship_avatar_jobs() TO service_role;

-- service_role needs direct table access for the worker (same lesson as
-- 20260812120000_grant_service_role_core_tables.sql — RLS is bypassed for
-- service_role, but base table privileges are still checked first):
GRANT SELECT, UPDATE ON public.relationship_avatar_processing_outbox TO service_role;
GRANT SELECT, UPDATE ON public.relationships TO service_role;
