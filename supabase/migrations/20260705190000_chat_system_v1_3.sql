-- Chat System v1.3: least-privilege reads, server flags, and gated historical import.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.feature_flags (
  key text PRIMARY KEY,
  enabled boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.feature_flags ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS feature_flags_authenticated_read ON public.feature_flags;
CREATE POLICY feature_flags_authenticated_read
ON public.feature_flags FOR SELECT TO authenticated
USING (true);

REVOKE ALL ON public.feature_flags FROM anon, authenticated;
GRANT SELECT ON public.feature_flags TO authenticated;

INSERT INTO public.feature_flags (key, enabled)
VALUES
  ('chat_image_sharing', false),
  ('chat_translator_entry', false),
  ('chat_expanded_header_drawer', false),
  ('chat_historical_import', false),
  ('chat_voice_messages', false),
  ('chat_reactions', false),
  ('chat_edit_delete', false),
  ('chat_video_sharing', false),
  ('chat_link_previews', false)
ON CONFLICT (key) DO NOTHING;

-- Analysis columns are service-only. Authenticated clients receive only the
-- immutable chat payload and trusted receipt fields used by presentation.
REVOKE SELECT ON public.messages FROM authenticated;
GRANT SELECT (
  id,
  relationship_id,
  sender_id,
  client_message_id,
  content,
  created_at,
  delivered_at,
  read_at,
  media_url,
  media_type
) ON public.messages TO authenticated;

CREATE TABLE IF NOT EXISTS public.chat_import_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  uploader_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  approver_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  source text NOT NULL CHECK (source = 'whatsapp'),
  policy_version text NOT NULL,
  file_fingerprint text NOT NULL,
  parsed_message_count int NOT NULL CHECK (parsed_message_count BETWEEN 1 AND 100000),
  first_message_at timestamptz NOT NULL,
  last_message_at timestamptz NOT NULL,
  state text NOT NULL DEFAULT 'pending_partner_consent' CHECK (state IN (
    'pending_partner_consent', 'approved', 'declined', 'processing',
    'processing_safety', 'completed', 'failed', 'revoked', 'deleted'
  )),
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_at timestamptz,
  CHECK (uploader_id <> approver_id),
  CHECK (first_message_at <= last_message_at)
);

CREATE TABLE IF NOT EXISTS public.chat_import_consents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.chat_import_requests(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  policy_version text NOT NULL,
  action text NOT NULL CHECK (action IN ('granted', 'declined', 'revoked')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.chat_import_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL UNIQUE REFERENCES public.chat_import_requests(id) ON DELETE CASCADE,
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  source text NOT NULL CHECK (source = 'whatsapp'),
  expected_count int NOT NULL CHECK (expected_count > 0),
  imported_count int NOT NULL DEFAULT 0 CHECK (imported_count >= 0),
  state text NOT NULL DEFAULT 'processing' CHECK (state IN (
    'processing', 'processing_safety', 'completed', 'failed', 'revoked', 'deleted'
  )),
  last_source_line int NOT NULL DEFAULT 0,
  error_code text,
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  deleted_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.chat_import_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_hash text NOT NULL,
  event text NOT NULL CHECK (event IN ('completed', 'deleted', 'revoked')),
  occurred_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'native',
  ADD COLUMN IF NOT EXISTS import_job_id uuid REFERENCES public.chat_import_jobs(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS source_line_number int;

ALTER TABLE public.personal_insights
  ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.analysis_sessions
  ADD COLUMN IF NOT EXISTS source_type text NOT NULL DEFAULT 'native',
  ADD COLUMN IF NOT EXISTS source_import_job_ids uuid[] NOT NULL DEFAULT '{}';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'analysis_sessions_source_type_check'
  ) THEN
    ALTER TABLE public.analysis_sessions
      ADD CONSTRAINT analysis_sessions_source_type_check
      CHECK (source_type IN ('native', 'import', 'mixed'));
  END IF;
END
$$;

GRANT SELECT (source) ON public.messages TO authenticated;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'messages_source_check'
  ) THEN
    ALTER TABLE public.messages
      ADD CONSTRAINT messages_source_check
      CHECK (source IN ('native', 'import:whatsapp'));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'messages_import_shape_check'
  ) THEN
    ALTER TABLE public.messages
      ADD CONSTRAINT messages_import_shape_check CHECK (
        (source = 'native' AND import_job_id IS NULL AND source_line_number IS NULL)
        OR
        (source = 'import:whatsapp' AND import_job_id IS NOT NULL AND source_line_number > 0)
      );
  END IF;
END
$$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_import_job_line
  ON public.messages(import_job_id, source_line_number)
  WHERE import_job_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_chat_import_requests_relationship
  ON public.chat_import_requests(relationship_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_import_consents_request
  ON public.chat_import_consents(request_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_import_jobs_relationship
  ON public.chat_import_jobs(relationship_id, started_at DESC);

ALTER TABLE public.chat_import_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_import_consents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_import_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_import_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS chat_import_requests_members_read ON public.chat_import_requests;
CREATE POLICY chat_import_requests_members_read
ON public.chat_import_requests FOR SELECT TO authenticated
USING (
  auth.uid() IN (uploader_id, approver_id)
  AND EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = relationship_id
      AND r.chat_archived_at IS NULL
      AND auth.uid() IN (r.user_a, r.user_b)
  )
);

DROP POLICY IF EXISTS chat_import_consents_own_read ON public.chat_import_consents;
CREATE POLICY chat_import_consents_own_read
ON public.chat_import_consents FOR SELECT TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS chat_import_jobs_members_read ON public.chat_import_jobs;
CREATE POLICY chat_import_jobs_members_read
ON public.chat_import_jobs FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = relationship_id
      AND r.chat_archived_at IS NULL
      AND auth.uid() IN (r.user_a, r.user_b)
  )
);

REVOKE ALL ON public.chat_import_requests FROM anon, authenticated;
REVOKE ALL ON public.chat_import_consents FROM anon, authenticated;
REVOKE ALL ON public.chat_import_jobs FROM anon, authenticated;
REVOKE ALL ON public.chat_import_audit FROM anon, authenticated;
GRANT SELECT ON public.chat_import_requests TO authenticated;
GRANT SELECT ON public.chat_import_consents TO authenticated;
GRANT SELECT ON public.chat_import_jobs TO authenticated;

CREATE OR REPLACE FUNCTION public.create_chat_import_request(
  p_relationship_id uuid,
  p_policy_version text,
  p_file_fingerprint text,
  p_message_count int,
  p_first_message_at timestamptz,
  p_last_message_at timestamptz
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_relationship public.relationships%ROWTYPE;
  v_request_id uuid;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF COALESCE((SELECT enabled FROM public.feature_flags WHERE key = 'chat_historical_import'), false) = false THEN
    RAISE EXCEPTION 'Historical import unavailable';
  END IF;
  IF p_policy_version IS NULL OR btrim(p_policy_version) = ''
     OR p_file_fingerprint !~ '^[a-f0-9]{64}$'
     OR p_message_count NOT BETWEEN 1 AND 100000
     OR p_first_message_at > p_last_message_at THEN
    RAISE EXCEPTION 'Invalid import request';
  END IF;

  SELECT * INTO v_relationship
  FROM public.relationships
  WHERE id = p_relationship_id
    AND status = 'active'
    AND chat_archived_at IS NULL
    AND user_a IS NOT NULL AND user_b IS NOT NULL
    AND v_user_id IN (user_a, user_b)
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Relationship unavailable'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.chat_import_requests r
    WHERE r.relationship_id = p_relationship_id
      AND r.uploader_id = v_user_id
      AND r.state IN ('pending_partner_consent', 'approved', 'processing', 'processing_safety')
  ) THEN
    RAISE EXCEPTION 'An import request is already active';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.chat_import_requests r
    WHERE r.relationship_id = p_relationship_id
      AND r.uploader_id = v_user_id
      AND r.state = 'declined'
      AND r.decided_at > now() - interval '7 days'
  ) THEN
    RAISE EXCEPTION 'Import request cooldown active';
  END IF;

  INSERT INTO public.chat_import_requests (
    relationship_id, uploader_id, approver_id, source, policy_version,
    file_fingerprint, parsed_message_count, first_message_at, last_message_at
  ) VALUES (
    p_relationship_id,
    v_user_id,
    CASE WHEN v_relationship.user_a = v_user_id THEN v_relationship.user_b ELSE v_relationship.user_a END,
    'whatsapp', p_policy_version, p_file_fingerprint, p_message_count,
    p_first_message_at, p_last_message_at
  ) RETURNING id INTO v_request_id;

  INSERT INTO public.chat_import_consents (request_id, user_id, policy_version, action)
  VALUES (v_request_id, v_user_id, p_policy_version, 'granted');
  RETURN v_request_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.respond_to_chat_import_request(
  p_request_id uuid,
  p_action text,
  p_policy_version text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_request public.chat_import_requests%ROWTYPE;
BEGIN
  IF p_action NOT IN ('granted', 'declined') THEN RAISE EXCEPTION 'Invalid action'; END IF;
  SELECT * INTO v_request FROM public.chat_import_requests
  WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND OR v_user_id IS NULL OR v_request.approver_id <> v_user_id
     OR v_request.state <> 'pending_partner_consent'
     OR v_request.policy_version <> p_policy_version THEN
    RAISE EXCEPTION 'Import request unavailable';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = v_request.relationship_id AND r.status = 'active'
      AND r.chat_archived_at IS NULL AND v_user_id IN (r.user_a, r.user_b)
  ) THEN RAISE EXCEPTION 'Relationship unavailable'; END IF;

  INSERT INTO public.chat_import_consents (request_id, user_id, policy_version, action)
  VALUES (p_request_id, v_user_id, p_policy_version, p_action);
  UPDATE public.chat_import_requests
  SET state = CASE WHEN p_action = 'granted' THEN 'approved' ELSE 'declined' END,
      decided_at = now()
  WHERE id = p_request_id;
  RETURN CASE WHEN p_action = 'granted' THEN 'approved' ELSE 'declined' END;
END;
$$;

CREATE OR REPLACE FUNCTION public.ingest_chat_import_batch(
  p_request_id uuid,
  p_messages jsonb,
  p_is_final_batch boolean DEFAULT false
)
RETURNS TABLE(job_id uuid, imported_count int, state text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_request public.chat_import_requests%ROWTYPE;
  v_job public.chat_import_jobs%ROWTYPE;
  v_item jsonb;
  v_line int;
  v_sender uuid;
  v_created_at timestamptz;
  v_content text;
  v_client_id uuid;
BEGIN
  IF jsonb_typeof(p_messages) <> 'array' OR jsonb_array_length(p_messages) > 500 THEN
    RAISE EXCEPTION 'Invalid import batch';
  END IF;
  SELECT * INTO v_request FROM public.chat_import_requests
  WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND OR v_user_id IS NULL OR v_request.uploader_id <> v_user_id
     OR v_request.state NOT IN ('approved', 'processing', 'failed') THEN
    RAISE EXCEPTION 'Import request unavailable';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = v_request.relationship_id AND r.status = 'active'
      AND r.chat_archived_at IS NULL
      AND v_user_id IN (r.user_a, r.user_b)
  ) OR NOT EXISTS (
    SELECT 1 FROM public.chat_import_consents c
    WHERE c.request_id = p_request_id AND c.user_id = v_request.uploader_id
      AND c.action = 'granted'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.chat_import_consents c
    WHERE c.request_id = p_request_id AND c.user_id = v_request.approver_id
      AND c.action = 'granted'
  ) OR EXISTS (
    SELECT 1 FROM public.chat_import_consents c
    WHERE c.request_id = p_request_id AND c.action = 'revoked'
  ) THEN RAISE EXCEPTION 'Import consent unavailable'; END IF;

  INSERT INTO public.chat_import_jobs (
    request_id, relationship_id, source, expected_count
  ) VALUES (
    p_request_id, v_request.relationship_id, 'whatsapp', v_request.parsed_message_count
  ) ON CONFLICT (request_id) DO NOTHING;
  SELECT * INTO v_job FROM public.chat_import_jobs
  WHERE request_id = p_request_id FOR UPDATE;
  IF v_job.state NOT IN ('processing', 'failed') THEN
    RAISE EXCEPTION 'Import job unavailable';
  END IF;
  UPDATE public.chat_import_requests SET state = 'processing' WHERE id = p_request_id;
  UPDATE public.chat_import_jobs SET state = 'processing', error_code = NULL WHERE id = v_job.id;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_messages)
  LOOP
    v_line := (v_item->>'line')::int;
    v_sender := (v_item->>'sender_id')::uuid;
    v_created_at := (v_item->>'created_at')::timestamptz;
    v_content := v_item->>'content';
    IF v_line <= 0 OR v_sender NOT IN (v_request.uploader_id, v_request.approver_id)
       OR v_created_at < v_request.first_message_at
       OR v_created_at > v_request.last_message_at
       OR btrim(COALESCE(v_content, '')) = ''
       OR char_length(v_content) > 10000 THEN
      RAISE EXCEPTION 'Invalid imported message';
    END IF;
    v_client_id := (
      substr(md5(v_job.id::text || ':' || v_line::text), 1, 8) || '-' ||
      substr(md5(v_job.id::text || ':' || v_line::text), 9, 4) || '-' ||
      '5' || substr(md5(v_job.id::text || ':' || v_line::text), 14, 3) || '-' ||
      '8' || substr(md5(v_job.id::text || ':' || v_line::text), 18, 3) || '-' ||
      substr(md5(v_job.id::text || ':' || v_line::text), 21, 12)
    )::uuid;

    INSERT INTO public.messages (
      relationship_id, sender_id, client_message_id, content, created_at,
      delivered_at, read_at, source, import_job_id, source_line_number
    ) VALUES (
      v_request.relationship_id, v_sender, v_client_id, v_content, v_created_at,
      v_created_at, v_created_at, 'import:whatsapp', v_job.id, v_line
    ) ON CONFLICT (import_job_id, source_line_number) WHERE import_job_id IS NOT NULL
      DO NOTHING;
  END LOOP;

  UPDATE public.chat_import_jobs j
  SET imported_count = (SELECT count(*) FROM public.messages m WHERE m.import_job_id = j.id),
      last_source_line = GREATEST(
        j.last_source_line,
        COALESCE((SELECT max(m.source_line_number) FROM public.messages m WHERE m.import_job_id = j.id), 0)
      ),
      state = CASE WHEN p_is_final_batch THEN 'processing_safety' ELSE 'processing' END
  WHERE j.id = v_job.id
  RETURNING * INTO v_job;

  IF p_is_final_batch AND v_job.imported_count <> v_job.expected_count THEN
    UPDATE public.chat_import_jobs SET state = 'failed', error_code = 'count_mismatch' WHERE id = v_job.id;
    UPDATE public.chat_import_requests SET state = 'failed' WHERE id = p_request_id;
    v_job.state := 'failed';
  ELSIF p_is_final_batch THEN
    UPDATE public.chat_import_requests SET state = 'processing_safety' WHERE id = p_request_id;
    IF NOT EXISTS (
      SELECT 1 FROM public.messages m
      WHERE m.import_job_id = v_job.id
        AND m.safety_processed_at IS NULL AND m.safety_error_at IS NULL
    ) THEN
      UPDATE public.chat_import_jobs
      SET state = 'completed', completed_at = now(), error_code = NULL
      WHERE id = v_job.id;
      UPDATE public.chat_import_requests SET state = 'completed'
      WHERE id = p_request_id;
      INSERT INTO public.chat_import_audit (relationship_hash, event)
      VALUES (encode(digest(v_job.relationship_id::text, 'sha256'), 'hex'), 'completed');
      v_job.state := 'completed';
    END IF;
  END IF;

  job_id := v_job.id;
  imported_count := v_job.imported_count;
  state := v_job.state;
  RETURN NEXT;
EXCEPTION WHEN OTHERS THEN
  IF v_job.id IS NOT NULL THEN
    UPDATE public.chat_import_jobs SET state = 'failed', error_code = 'batch_rejected' WHERE id = v_job.id;
    UPDATE public.chat_import_requests SET state = 'failed' WHERE id = p_request_id;
    job_id := v_job.id;
    imported_count := v_job.imported_count;
    state := 'failed';
    RETURN NEXT;
    RETURN;
  END IF;
  RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_import_derived_evidence(p_job_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.personal_insights
  WHERE metadata->>'source_type' = 'import'
    AND (
      metadata->>'import_job_id' = p_job_id::text
      OR metadata->'import_job_ids' ? p_job_id::text
    );
  UPDATE public.personal_insights
  SET metadata = jsonb_set(metadata, '{needs_recompute}', 'true'::jsonb, true)
  WHERE metadata->>'source_type' = 'mixed'
    AND metadata->'import_job_ids' ? p_job_id::text;

  DELETE FROM public.patterns
  WHERE metadata->>'source_type' = 'import'
    AND metadata->'import_job_ids' ? p_job_id::text;
  UPDATE public.patterns
  SET metadata = jsonb_set(metadata, '{needs_recompute}', 'true'::jsonb, true)
  WHERE metadata->>'source_type' = 'mixed'
    AND metadata->'import_job_ids' ? p_job_id::text;

  DELETE FROM public.analysis_sessions
  WHERE source_type = 'import' AND p_job_id = ANY(source_import_job_ids);
  UPDATE public.analysis_sessions
  SET escalation_score = NULL,
      pattern_memory_done = false,
      source_type = 'native',
      source_import_job_ids = array_remove(source_import_job_ids, p_job_id)
  WHERE source_type = 'mixed' AND p_job_id = ANY(source_import_job_ids);
END;
$$;

CREATE OR REPLACE FUNCTION public.revoke_chat_import_request(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_request public.chat_import_requests%ROWTYPE;
  v_job_id uuid;
BEGIN
  SELECT * INTO v_request FROM public.chat_import_requests
  WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND OR v_user_id IS NULL
     OR v_user_id NOT IN (v_request.uploader_id, v_request.approver_id)
     OR v_request.state IN ('declined', 'completed', 'deleted', 'revoked') THEN
    RAISE EXCEPTION 'Import request unavailable';
  END IF;
  INSERT INTO public.chat_import_consents (request_id, user_id, policy_version, action)
  VALUES (v_request.id, v_user_id, v_request.policy_version, 'revoked');
  SELECT id INTO v_job_id FROM public.chat_import_jobs WHERE request_id = p_request_id;
  IF v_job_id IS NULL THEN
    UPDATE public.chat_import_requests SET state = 'revoked' WHERE id = p_request_id;
    INSERT INTO public.chat_import_audit (relationship_hash, event)
    VALUES (encode(digest(v_request.relationship_id::text, 'sha256'), 'hex'), 'revoked');
  ELSE
    DELETE FROM public.messages WHERE import_job_id = v_job_id;
    PERFORM public.remove_import_derived_evidence(v_job_id);
    UPDATE public.chat_import_jobs
    SET state = 'revoked', deleted_at = now(), error_code = NULL
    WHERE id = v_job_id;
    UPDATE public.chat_import_requests SET state = 'revoked'
    WHERE id = p_request_id;
    INSERT INTO public.chat_import_audit (relationship_hash, event)
    VALUES (encode(digest(v_request.relationship_id::text, 'sha256'), 'hex'), 'revoked');
    UPDATE public.relationships r
    SET message_count = (
      SELECT count(*) FROM public.messages m WHERE m.relationship_id = r.id
    )
    WHERE r.id = v_request.relationship_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.finalize_chat_import_after_safety()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job public.chat_import_jobs%ROWTYPE;
BEGIN
  IF NEW.import_job_id IS NULL OR
     (NEW.safety_processed_at IS NULL AND NEW.safety_error_at IS NULL) THEN
    RETURN NEW;
  END IF;
  SELECT * INTO v_job FROM public.chat_import_jobs WHERE id = NEW.import_job_id FOR UPDATE;
  IF NOT FOUND OR v_job.state <> 'processing_safety' THEN RETURN NEW; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.messages m
    WHERE m.import_job_id = v_job.id
      AND m.safety_processed_at IS NULL AND m.safety_error_at IS NULL
  ) AND v_job.imported_count = v_job.expected_count THEN
    UPDATE public.chat_import_jobs
    SET state = 'completed', completed_at = now(), error_code = NULL
    WHERE id = v_job.id;
    UPDATE public.chat_import_requests SET state = 'completed'
    WHERE id = v_job.request_id;
    INSERT INTO public.chat_import_audit (relationship_hash, event)
    VALUES (encode(digest(v_job.relationship_id::text, 'sha256'), 'hex'), 'completed');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS finalize_chat_import_after_safety ON public.messages;
CREATE TRIGGER finalize_chat_import_after_safety
AFTER UPDATE OF safety_processed_at, safety_error_at ON public.messages
FOR EACH ROW EXECUTE FUNCTION public.finalize_chat_import_after_safety();

CREATE OR REPLACE FUNCTION public.delete_chat_import(p_job_id uuid, p_revoke boolean DEFAULT false)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_job public.chat_import_jobs%ROWTYPE;
  v_request public.chat_import_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_job FROM public.chat_import_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Import unavailable'; END IF;
  SELECT * INTO v_request FROM public.chat_import_requests WHERE id = v_job.request_id;
  IF v_user_id IS NULL OR v_user_id NOT IN (v_request.uploader_id, v_request.approver_id) THEN
    RAISE EXCEPTION 'Import unavailable';
  END IF;
  IF p_revoke THEN
    INSERT INTO public.chat_import_consents (
      request_id, user_id, policy_version, action
    ) VALUES (v_request.id, v_user_id, v_request.policy_version, 'revoked');
  END IF;
  DELETE FROM public.messages WHERE import_job_id = v_job.id;
  PERFORM public.remove_import_derived_evidence(v_job.id);
  UPDATE public.chat_import_jobs
  SET state = CASE WHEN p_revoke THEN 'revoked' ELSE 'deleted' END,
      deleted_at = now(), error_code = NULL
  WHERE id = v_job.id;
  UPDATE public.chat_import_requests
  SET state = CASE WHEN p_revoke THEN 'revoked' ELSE 'deleted' END
  WHERE id = v_request.id;
  INSERT INTO public.chat_import_audit (relationship_hash, event)
  VALUES (
    encode(digest(v_job.relationship_id::text, 'sha256'), 'hex'),
    CASE WHEN p_revoke THEN 'revoked' ELSE 'deleted' END
  );
  UPDATE public.relationships r
  SET message_count = (
    SELECT count(*) FROM public.messages m WHERE m.relationship_id = r.id
  )
  WHERE r.id = v_job.relationship_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_chat_imports_on_relationship_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job record;
BEGIN
  IF NEW.status = 'active' AND NEW.chat_archived_at IS NULL THEN RETURN NEW; END IF;
  FOR v_job IN
    SELECT j.id, j.request_id
    FROM public.chat_import_jobs j
    WHERE j.relationship_id = NEW.id
      AND j.state IN ('processing', 'processing_safety', 'failed')
  LOOP
    DELETE FROM public.messages WHERE import_job_id = v_job.id;
    PERFORM public.remove_import_derived_evidence(v_job.id);
    UPDATE public.chat_import_jobs
    SET state = 'revoked', deleted_at = now(), error_code = 'relationship_inactive'
    WHERE id = v_job.id;
    UPDATE public.chat_import_requests SET state = 'revoked'
    WHERE id = v_job.request_id;
  END LOOP;
  UPDATE public.chat_import_requests
  SET state = 'revoked'
  WHERE relationship_id = NEW.id
    AND state IN ('pending_partner_consent', 'approved');
  UPDATE public.relationships r
  SET message_count = (
    SELECT count(*) FROM public.messages m WHERE m.relationship_id = r.id
  )
  WHERE r.id = NEW.id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS cancel_chat_imports_on_relationship_change ON public.relationships;
CREATE TRIGGER cancel_chat_imports_on_relationship_change
AFTER UPDATE OF status, chat_archived_at ON public.relationships
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status OR OLD.chat_archived_at IS DISTINCT FROM NEW.chat_archived_at)
EXECUTE FUNCTION public.cancel_chat_imports_on_relationship_change();

-- Imported rows use the same Safety/analysis outbox but never create a new-message push.
CREATE OR REPLACE FUNCTION public.enqueue_message_downstream_work()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_relationship public.relationships%ROWTYPE;
  v_recipient_id uuid;
  v_notification_outbox_id uuid;
  v_supabase_url text;
  v_service_role_key text;
BEGIN
  SELECT * INTO v_relationship FROM public.relationships WHERE id = NEW.relationship_id;
  IF NOT FOUND THEN RETURN NEW; END IF;
  UPDATE public.relationships SET message_count = COALESCE(message_count, 0) + 1
  WHERE id = NEW.relationship_id;
  INSERT INTO public.message_safety_outbox (message_id, relationship_id, source_event_key)
  VALUES (NEW.id, NEW.relationship_id, NULL) ON CONFLICT (message_id) DO NOTHING;

  IF NEW.source = 'native' THEN
    v_recipient_id := CASE
      WHEN v_relationship.user_a = NEW.sender_id THEN v_relationship.user_b
      WHEN v_relationship.user_b = NEW.sender_id THEN v_relationship.user_a
      ELSE NULL END;
    IF v_recipient_id IS NOT NULL THEN
      INSERT INTO public.message_notification_outbox (
        message_id, relationship_id, recipient_id, sender_id
      ) VALUES (NEW.id, NEW.relationship_id, v_recipient_id, NEW.sender_id)
      ON CONFLICT (recipient_id, message_id, notification_type) DO NOTHING
      RETURNING id INTO v_notification_outbox_id;
    END IF;
  END IF;

  v_supabase_url := current_setting('app.settings.supabase_url', true);
  v_service_role_key := current_setting('app.settings.service_role_key', true);
  IF v_supabase_url IS NOT NULL AND v_service_role_key IS NOT NULL THEN
    BEGIN
      PERFORM net.http_post(
        url := v_supabase_url || '/functions/v1/process-chat-safety-outbox',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_service_role_key,'apikey',v_service_role_key),
        body := jsonb_build_object('message_id', NEW.id));
      IF v_notification_outbox_id IS NOT NULL THEN
        PERFORM net.http_post(
          url := v_supabase_url || '/functions/v1/process-chat-notification-outbox',
          headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_service_role_key,'apikey',v_service_role_key),
          body := jsonb_build_object('outbox_id', v_notification_outbox_id));
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.create_chat_import_request(uuid,text,text,int,timestamptz,timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_chat_import_request(uuid,text,text,int,timestamptz,timestamptz) TO authenticated;
REVOKE ALL ON FUNCTION public.respond_to_chat_import_request(uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.respond_to_chat_import_request(uuid,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.ingest_chat_import_batch(uuid,jsonb,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ingest_chat_import_batch(uuid,jsonb,boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.delete_chat_import(uuid,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_chat_import(uuid,boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.revoke_chat_import_request(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revoke_chat_import_request(uuid) TO authenticated;
