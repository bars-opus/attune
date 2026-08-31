-- Scheduled jobs and enqueue triggers read their Supabase URL and service
-- role key from app.settings.*, which is set with ALTER DATABASE. On a
-- managed project the SQL editor connects as `postgres`, which is not the
-- database owner, so ALTER DATABASE (and ALTER ROLE) fail with 42501 and
-- the settings were never set.
--
-- The result: every one of the 21 cron jobs has failed on every run since
-- it was registered, and the four enqueue triggers -- which read the
-- settings with the two-argument current_setting and skip silently when
-- they are NULL -- have been no-ops. Nothing surfaced this, because the
-- cron failures land in cron.job_run_details, which nothing reads, and
-- the triggers were written to fail quietly by design.
--
-- Vault IS writable as `postgres`, so the secrets move there. The reader
-- below prefers Vault and falls back to the old GUC, which keeps local
-- development working (where ALTER DATABASE does succeed) and means this
-- migration does not have to be reverted if the GUC ever becomes
-- available.
--
-- Prerequisite, run once by hand:
--   select vault.create_secret('https://<ref>.supabase.co', 'supabase_url');
--   select vault.create_secret('<service-role-key>', 'service_role_key');

CREATE OR REPLACE FUNCTION public.app_setting(p_name text)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, vault
AS $$
DECLARE
  v_value text;
BEGIN
  -- Vault first: it is the only one of the two that can be written on a
  -- managed project.
  SELECT decrypted_secret INTO v_value
  FROM vault.decrypted_secrets
  WHERE name = p_name
  LIMIT 1;

  IF v_value IS NOT NULL AND v_value <> '' THEN
    RETURN v_value;
  END IF;

  -- Falls back to the GUC so a local database with ALTER DATABASE set
  -- keeps working unchanged.
  RETURN nullif(current_setting('app.settings.' || p_name, true), '');
EXCEPTION WHEN OTHERS THEN
  -- A missing vault extension or an unreadable secret must not take down
  -- a user-facing INSERT through the enqueue triggers. Callers already
  -- treat NULL as "not configured" and skip their HTTP post.
  RETURN nullif(current_setting('app.settings.' || p_name, true), '');
END;
$$;

REVOKE ALL ON FUNCTION public.app_setting(text) FROM PUBLIC;

COMMENT ON FUNCTION public.app_setting(text) IS
  'Reads a deployment setting (supabase_url, service_role_key) from Vault, '
  'falling back to the app.settings.* GUC. Returns NULL when unset.';

-- ---------------------------------------------------------------------
-- The shared edge-function invoker used by 16 of the cron jobs.
-- ---------------------------------------------------------------------

-- Unchanged except for where the two values come from. Raising when they
-- are missing rather than posting to 'null/functions/v1/...' turns a
-- silent no-op into a row in cron.job_run_details that names the cause.
CREATE OR REPLACE FUNCTION public.invoke_edge_function(p_function text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_url text := public.app_setting('supabase_url');
  v_key text := public.app_setting('service_role_key');
BEGIN
  IF v_url IS NULL OR v_key IS NULL THEN
    RAISE EXCEPTION
      'invoke_edge_function(%): supabase_url/service_role_key not configured; '
      'store them with vault.create_secret()', p_function;
  END IF;

  PERFORM net.http_post(
    url := v_url || '/functions/v1/' || p_function,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key,
      'apikey', v_key
    ),
    body := '{}'::jsonb
  );
END;
$$;

REVOKE ALL ON FUNCTION public.invoke_edge_function(text) FROM PUBLIC;

-- ---------------------------------------------------------------------
-- The three cron jobs that inline their own net.http_post.
-- ---------------------------------------------------------------------

-- Re-registered through the shared invoker rather than rewritten in
-- place: the inline copies were already drifting from each other, which
-- is what invoke_edge_function was extracted to stop.
SELECT cron.unschedule('analyse-session-sweep')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'analyse-session-sweep');

SELECT cron.schedule(
  'analyse-session-sweep',
  '7,37 * * * *',
  $$SELECT public.invoke_edge_function('analyse-session')$$
);

SELECT cron.unschedule('drain-truth-answer-safety')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'drain-truth-answer-safety');

SELECT cron.schedule(
  'drain-truth-answer-safety',
  '*/2 * * * *',
  $$SELECT public.invoke_edge_function('process-truth-answer-safety')$$
);

SELECT cron.unschedule('drain-media-deletion-queue')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'drain-media-deletion-queue');

SELECT cron.schedule(
  'drain-media-deletion-queue',
  '*/10 * * * *',
  $$SELECT public.invoke_edge_function('process-media-deletion-queue')$$
);

-- ---------------------------------------------------------------------
-- The four enqueue triggers.
-- ---------------------------------------------------------------------

-- These read the settings with the two-argument current_setting and skip
-- their HTTP post when it returns NULL, so they have been silently
-- enqueueing rows without ever waking the worker that drains them. Each
-- body below is its current definition unchanged apart from the two
-- settings reads; the NULL-check and the EXCEPTION block stay exactly as
-- they were, so a missing secret still cannot break a user-facing INSERT.

-- Body preserved verbatim from 20260705190000_chat_system_v1_3.sql; only the two settings
-- reads are redirected to the Vault-backed accessor.
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

  v_supabase_url := public.app_setting('supabase_url');
  v_service_role_key := public.app_setting('service_role_key');
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

-- Body preserved verbatim from 20260705200000_chat_media_hardening.sql; only the two settings
-- reads are redirected to the Vault-backed accessor.
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
  v_supabase_url := public.app_setting('supabase_url');
  v_service_role_key := public.app_setting('service_role_key');
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

-- Body preserved verbatim from 20260826130000_relationship_chat_identity.sql; only the two settings
-- reads are redirected to the Vault-backed accessor.
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
  v_supabase_url := public.app_setting('supabase_url');
  v_service_role_key := public.app_setting('service_role_key');
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

-- Body preserved verbatim from 20260813130000_dating_photo_pipeline.sql; only the two settings
-- reads are redirected to the Vault-backed accessor.
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
  v_supabase_url := public.app_setting('supabase_url');
  v_service_role_key := public.app_setting('service_role_key');
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

-- ---------------------------------------------------------------------
-- Dating contact exclusion.
-- ---------------------------------------------------------------------

-- Found by the settings contract test rather than by the audit above:
-- this reads a THIRD secret, dating_exclusion_key, through the same dead
-- mechanism. It hashes a phone number so a user is never shown someone
-- from their contacts; with the key unset it returns NULL, and the
-- exclusion it exists to enforce has therefore never applied.
--
-- Store the key alongside the other two:
--   select vault.create_secret('<random-32-byte-hex>', 'dating_exclusion_key');
--
-- Body preserved verbatim from 20260712160000_dating_former_partner_exclusion.sql; only the settings read changes. It
-- still returns NULL when unconfigured rather than raising, which is
-- correct here: this runs inline on profile writes, and the caller
-- already treats NULL as "no exclusion hash available".
CREATE OR REPLACE FUNCTION public.dating_phone_hmac(p_phone text)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_key text := public.app_setting('dating_exclusion_key');
  v_phone text := NULLIF(trim(COALESCE(p_phone, '')), '');
BEGIN
  IF v_phone IS NULL OR v_key IS NULL OR length(v_key) = 0 THEN
    RETURN NULL;
  END IF;
  -- Bare hmac(): pgcrypto is installed into public here (matches the codebase's
  -- unqualified digest() calls), and search_path is pinned to public.
  RETURN encode(hmac(v_phone, v_key, 'sha256'), 'hex');
END;
$$;