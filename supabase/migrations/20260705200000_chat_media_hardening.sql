CREATE TABLE IF NOT EXISTS public.message_media_processing_outbox (
  message_id uuid PRIMARY KEY REFERENCES public.messages(id) ON DELETE CASCADE,
  storage_key text NOT NULL,
  state text NOT NULL DEFAULT 'pending'
    CHECK (state IN ('pending', 'processing', 'done', 'dead_letter')),
  attempts int NOT NULL DEFAULT 0,
  processing_started_at timestamptz,
  completed_at timestamptz,
  last_error_code text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_message_media_processing_pending
  ON public.message_media_processing_outbox(state, created_at);

ALTER TABLE public.message_media_processing_outbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.message_media_processing_outbox FROM anon, authenticated;
GRANT SELECT (media_thumbnail_url) ON public.messages TO authenticated;

CREATE OR REPLACE FUNCTION public.validate_message_media_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
DECLARE
  v_intent public.message_media_upload_intents%ROWTYPE;
  v_object storage.objects%ROWTYPE;
  v_size bigint;
  v_mime text;
BEGIN
  IF NEW.media_url IS NULL THEN RETURN NEW; END IF;
  IF NEW.media_type IS DISTINCT FROM 'image' THEN
    RAISE EXCEPTION 'Unsupported chat media type';
  END IF;

  SELECT * INTO v_intent
  FROM public.message_media_upload_intents intent
  WHERE intent.storage_key = NEW.media_url
    AND intent.relationship_id = NEW.relationship_id
    AND intent.requester_id = NEW.sender_id
    AND intent.media_type = NEW.media_type
    AND intent.used_at IS NULL
    AND intent.expires_at > now()
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Chat media upload intent is invalid or expired'; END IF;

  SELECT * INTO v_object FROM storage.objects o
  WHERE o.bucket_id = 'message-media' AND o.name = NEW.media_url;
  IF NOT FOUND THEN RAISE EXCEPTION 'Chat media object is missing'; END IF;
  v_size := COALESCE((v_object.metadata->>'size')::bigint, 0);
  v_mime := COALESCE(v_object.metadata->>'mimetype', v_object.metadata->>'contentType');
  IF v_size <= 0 OR v_size > 819200 OR v_mime IS DISTINCT FROM v_intent.mime_type THEN
    RAISE EXCEPTION 'Chat media object failed validation';
  END IF;

  UPDATE public.message_media_upload_intents SET used_at = now() WHERE id = v_intent.id;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.enqueue_chat_media_processing()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_supabase_url text;
  v_service_role_key text;
BEGIN
  IF NEW.media_url IS NULL OR NEW.media_type <> 'image' THEN RETURN NEW; END IF;
  INSERT INTO public.message_media_processing_outbox(message_id, storage_key)
  VALUES (NEW.id, NEW.media_url) ON CONFLICT (message_id) DO NOTHING;
  v_supabase_url := current_setting('app.settings.supabase_url', true);
  v_service_role_key := current_setting('app.settings.service_role_key', true);
  IF v_supabase_url IS NOT NULL AND v_service_role_key IS NOT NULL THEN
    BEGIN
      PERFORM net.http_post(
        url := v_supabase_url || '/functions/v1/process-chat-media',
        headers := jsonb_build_object(
          'Content-Type','application/json',
          'Authorization','Bearer '||v_service_role_key,
          'apikey',v_service_role_key
        ),
        body := jsonb_build_object('message_id', NEW.id)
      );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enqueue_chat_media_processing ON public.messages;
CREATE TRIGGER enqueue_chat_media_processing
AFTER INSERT ON public.messages
FOR EACH ROW
WHEN (NEW.media_url IS NOT NULL AND NEW.media_type = 'image')
EXECUTE FUNCTION public.enqueue_chat_media_processing();

DROP POLICY IF EXISTS message_media_select_relationship_members ON storage.objects;
CREATE POLICY message_media_select_relationship_members
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'message-media'
  AND EXISTS (
    SELECT 1 FROM public.messages m
    JOIN public.relationships r ON r.id = m.relationship_id
    WHERE (m.media_url = name OR m.media_thumbnail_url = name)
      AND r.chat_archived_at IS NULL
      AND auth.uid() IN (r.user_a, r.user_b)
  )
);

CREATE OR REPLACE FUNCTION public.claim_chat_media_jobs(
  p_limit int DEFAULT 20,
  p_message_id uuid DEFAULT NULL
)
RETURNS SETOF public.message_media_processing_outbox
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.message_media_processing_outbox o
  SET state = 'processing',
      attempts = attempts + 1,
      processing_started_at = now(),
      updated_at = now(),
      last_error_code = NULL
  WHERE o.message_id IN (
    SELECT message_id FROM public.message_media_processing_outbox
    WHERE state = 'pending'
      AND (p_message_id IS NULL OR message_id = p_message_id)
    ORDER BY created_at
    FOR UPDATE SKIP LOCKED
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
  )
  RETURNING o.*;
$$;

CREATE OR REPLACE FUNCTION public.recover_stale_chat_worker_leases()
RETURNS TABLE(worker text, recovered bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count bigint;
BEGIN
  UPDATE public.message_safety_outbox
  SET state = CASE WHEN attempts >= 5 THEN 'dead_letter' ELSE 'pending' END,
      processing_started_at = NULL,
      last_error_code = 'stale_lease',
      completed_at = CASE WHEN attempts >= 5 THEN now() ELSE NULL END
  WHERE state = 'processing' AND processing_started_at < now() - interval '5 minutes';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  worker := 'safety'; recovered := v_count; RETURN NEXT;

  UPDATE public.message_notification_outbox
  SET state = CASE WHEN attempts >= 5 THEN 'dead_letter' ELSE 'pending' END,
      processing_started_at = NULL,
      last_error_code = 'stale_lease',
      completed_at = CASE WHEN attempts >= 5 THEN now() ELSE NULL END
  WHERE state = 'processing' AND processing_started_at < now() - interval '5 minutes';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  worker := 'notification'; recovered := v_count; RETURN NEXT;

  UPDATE public.message_media_processing_outbox
  SET state = CASE WHEN attempts >= 5 THEN 'dead_letter' ELSE 'pending' END,
      processing_started_at = NULL,
      last_error_code = 'stale_lease',
      completed_at = CASE WHEN attempts >= 5 THEN now() ELSE NULL END,
      updated_at = now()
  WHERE state = 'processing' AND processing_started_at < now() - interval '5 minutes';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  worker := 'media'; recovered := v_count; RETURN NEXT;

  UPDATE public.scheduled_notifications
  SET status = CASE WHEN retry_count >= 5 THEN 'failed' ELSE 'pending' END,
      retry_count = retry_count + 1,
      last_error = 'stale_lease',
      updated_at = now()
  WHERE status = 'processing' AND updated_at < now() - interval '5 minutes';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  worker := 'scheduled_notification'; recovered := v_count; RETURN NEXT;
END;
$$;

CREATE OR REPLACE VIEW public.chat_worker_health
WITH (security_invoker = false)
AS
SELECT 'safety'::text AS worker, state,
       count(*)::bigint AS job_count,
       min(created_at) AS oldest_job_at
FROM public.message_safety_outbox GROUP BY state
UNION ALL
SELECT 'notification', state, count(*)::bigint, min(created_at)
FROM public.message_notification_outbox GROUP BY state
UNION ALL
SELECT 'media', state, count(*)::bigint, min(created_at)
FROM public.message_media_processing_outbox GROUP BY state;

CREATE OR REPLACE FUNCTION public.cleanup_expired_chat_media_intents()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
DECLARE
  v_count int;
BEGIN
  WITH expired AS (
    DELETE FROM storage.objects o
    USING public.message_media_upload_intents i
    WHERE o.bucket_id = 'message-media'
      AND o.name = i.storage_key
      AND i.used_at IS NULL
      AND i.expires_at < now()
    RETURNING o.id
  ) SELECT count(*) INTO v_count FROM expired;
  DELETE FROM public.message_media_upload_intents
  WHERE used_at IS NULL AND expires_at < now() - interval '24 hours';
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_chat_media_jobs(int,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cleanup_expired_chat_media_intents() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.recover_stale_chat_worker_leases() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.chat_worker_health FROM PUBLIC, anon, authenticated;
