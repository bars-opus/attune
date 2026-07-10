CREATE EXTENSION IF NOT EXISTS pg_net;

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS safety_processed_at timestamptz,
  ADD COLUMN IF NOT EXISTS safety_error_at timestamptz,
  ADD COLUMN IF NOT EXISTS safety_error_code text;

ALTER TABLE public.message_safety_outbox
  ALTER COLUMN source_event_key DROP NOT NULL;

ALTER TABLE public.message_safety_outbox
  ADD COLUMN IF NOT EXISTS processing_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS completed_at timestamptz;

ALTER TABLE public.message_notification_outbox
  ADD COLUMN IF NOT EXISTS processing_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS completed_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_message_safety_outbox_state_created
  ON public.message_safety_outbox (state, created_at);

CREATE INDEX IF NOT EXISTS idx_message_notification_outbox_state_created
  ON public.message_notification_outbox (state, created_at);

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'notification_settings'
  ) AND NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'notification_settings'
      AND column_name = 'chat_message_preview_enabled'
  ) THEN
    ALTER TABLE public.notification_settings
      ADD COLUMN chat_message_preview_enabled boolean NOT NULL DEFAULT false;
  END IF;
END
$$;

UPDATE public.message_safety_outbox
SET source_event_key = NULL
WHERE source_event_key IS NOT NULL;

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
  SELECT *
  INTO v_relationship
  FROM public.relationships
  WHERE id = NEW.relationship_id;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  UPDATE public.relationships
  SET message_count = COALESCE(message_count, 0) + 1
  WHERE id = NEW.relationship_id;

  INSERT INTO public.message_safety_outbox (
    message_id,
    relationship_id,
    source_event_key
  )
  VALUES (
    NEW.id,
    NEW.relationship_id,
    NULL
  )
  ON CONFLICT (message_id) DO NOTHING;

  v_recipient_id := CASE
    WHEN v_relationship.user_a = NEW.sender_id THEN v_relationship.user_b
    WHEN v_relationship.user_b = NEW.sender_id THEN v_relationship.user_a
    ELSE NULL
  END;

  IF v_recipient_id IS NOT NULL THEN
    INSERT INTO public.message_notification_outbox (
      message_id,
      relationship_id,
      recipient_id,
      sender_id
    )
    VALUES (
      NEW.id,
      NEW.relationship_id,
      v_recipient_id,
      NEW.sender_id
    )
    ON CONFLICT (recipient_id, message_id, notification_type) DO NOTHING
    RETURNING id INTO v_notification_outbox_id;
  END IF;

  v_supabase_url := current_setting('app.settings.supabase_url', true);
  v_service_role_key := current_setting('app.settings.service_role_key', true);

  IF v_supabase_url IS NOT NULL AND v_service_role_key IS NOT NULL THEN
    BEGIN
      PERFORM net.http_post(
        url := v_supabase_url || '/functions/v1/process-chat-safety-outbox',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_role_key,
          'apikey', v_service_role_key
        ),
        body := jsonb_build_object('message_id', NEW.id)
      );

      IF v_notification_outbox_id IS NOT NULL THEN
        PERFORM net.http_post(
          url := v_supabase_url || '/functions/v1/process-chat-notification-outbox',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_service_role_key,
            'apikey', v_service_role_key
          ),
          body := jsonb_build_object('outbox_id', v_notification_outbox_id)
        );
      END IF;
    EXCEPTION
      WHEN OTHERS THEN
        NULL;
    END;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.enqueue_safety_resource_notification(
  p_safety_event_id uuid,
  p_user_id uuid,
  p_title text,
  p_body text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_push_enabled boolean := true;
  v_recent_sent boolean := false;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'notification_settings'
  ) THEN
    SELECT COALESCE(ns.push_enabled, true)
    INTO v_push_enabled
    FROM public.notification_settings ns
    WHERE ns.user_id = p_user_id;
  END IF;

  IF COALESCE(v_push_enabled, true) = false THEN
    UPDATE public.safety_events
    SET notification_status = 'suppressed'
    WHERE id = p_safety_event_id;
    RETURN 'suppressed';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.safety_events se
    WHERE se.at_risk_user_id = p_user_id
      AND se.notification_status = 'sent'
      AND se.created_at >= now() - interval '24 hours'
  )
  INTO v_recent_sent;

  IF v_recent_sent THEN
    UPDATE public.safety_events
    SET notification_status = 'suppressed'
    WHERE id = p_safety_event_id;
    RETURN 'suppressed';
  END IF;

  INSERT INTO public.scheduled_notifications (
    user_id,
    notification_type,
    scheduled_for,
    status,
    metadata,
    created_at,
    updated_at
  )
  VALUES (
    p_user_id,
    'immediate',
    now(),
    'pending',
    jsonb_build_object(
      'title', p_title,
      'body', p_body,
      'type', 'safety_resources'
    ),
    now(),
    now()
  );

  UPDATE public.safety_events
  SET notification_status = 'sent'
  WHERE id = p_safety_event_id;

  RETURN 'sent';
EXCEPTION
  WHEN OTHERS THEN
    UPDATE public.safety_events
    SET notification_status = 'failed'
    WHERE id = p_safety_event_id;
    RETURN 'failed';
END;
$$;
