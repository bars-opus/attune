CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE public.relationships
  ADD COLUMN IF NOT EXISTS chat_archived_at timestamptz,
  ADD COLUMN IF NOT EXISTS chat_archived_reason text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'relationships_chat_archived_reason_check'
  ) THEN
    ALTER TABLE public.relationships
      ADD CONSTRAINT relationships_chat_archived_reason_check
      CHECK (
        chat_archived_reason IS NULL OR chat_archived_reason IN (
          'partner_new_relationship',
          'manual_end'
        )
      );
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS public.analysis_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  started_at timestamptz NOT NULL,
  ended_at timestamptz NOT NULL,
  message_count int NOT NULL DEFAULT 0,
  trigger_type text NOT NULL DEFAULT 'inactivity'
    CHECK (trigger_type IN ('inactivity', 'topic_shift', 'manual')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  client_message_id uuid,
  content text,
  created_at timestamptz NOT NULL DEFAULT now(),
  delivered_at timestamptz,
  read_at timestamptz,
  media_url text,
  media_thumbnail_url text,
  media_type text CHECK (media_type IN ('image', 'video')),
  message_analysis_done boolean NOT NULL DEFAULT false,
  message_analysis_skipped boolean NOT NULL DEFAULT false,
  included_in_session_id uuid REFERENCES public.analysis_sessions(id) ON DELETE SET NULL,
  tone_score float,
  nvc_violations jsonb,
  bid_type text CHECK (bid_type IN ('toward', 'away', 'against'))
);

UPDATE public.messages
SET client_message_id = gen_random_uuid()
WHERE client_message_id IS NULL;

ALTER TABLE public.messages
  ALTER COLUMN client_message_id SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'messages_sender_client_id_unique'
  ) THEN
    ALTER TABLE public.messages
      ADD CONSTRAINT messages_sender_client_id_unique
      UNIQUE (sender_id, client_message_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'messages_payload_present'
  ) THEN
    ALTER TABLE public.messages
      ADD CONSTRAINT messages_payload_present
      CHECK (
        (content IS NOT NULL AND char_length(btrim(content)) > 0)
        OR media_url IS NOT NULL
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'messages_content_length'
  ) THEN
    ALTER TABLE public.messages
      ADD CONSTRAINT messages_content_length
      CHECK (content IS NULL OR char_length(content) <= 10000);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'messages_receipt_order'
  ) THEN
    ALTER TABLE public.messages
      ADD CONSTRAINT messages_receipt_order
      CHECK (read_at IS NULL OR delivered_at IS NOT NULL);
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_messages_relationship_created
  ON public.messages (relationship_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_messages_sender_client_id
  ON public.messages (sender_id, client_message_id);

CREATE TABLE IF NOT EXISTS public.message_safety_outbox (
  message_id uuid PRIMARY KEY REFERENCES public.messages(id) ON DELETE CASCADE,
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  source_event_key text NOT NULL UNIQUE,
  state text NOT NULL DEFAULT 'pending'
    CHECK (state IN ('pending', 'processing', 'done', 'dead_letter')),
  attempts int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  last_error_code text
);

CREATE TABLE IF NOT EXISTS public.message_notification_outbox (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  recipient_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  notification_type text NOT NULL DEFAULT 'new_message'
    CHECK (notification_type IN ('new_message')),
  state text NOT NULL DEFAULT 'pending'
    CHECK (state IN ('pending', 'processing', 'done', 'dead_letter')),
  attempts int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  last_error_code text,
  UNIQUE (recipient_id, message_id, notification_type)
);

CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS touch_message_safety_outbox_updated_at ON public.message_safety_outbox;
CREATE TRIGGER touch_message_safety_outbox_updated_at
BEFORE UPDATE ON public.message_safety_outbox
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

DROP TRIGGER IF EXISTS touch_message_notification_outbox_updated_at ON public.message_notification_outbox;
CREATE TRIGGER touch_message_notification_outbox_updated_at
BEFORE UPDATE ON public.message_notification_outbox
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

CREATE OR REPLACE FUNCTION public.enqueue_message_downstream_work()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_relationship public.relationships%ROWTYPE;
  v_recipient_id uuid;
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
    encode(
      digest(NEW.relationship_id::text || ':' || NEW.id::text, 'sha256'),
      'hex'
    )
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
    ON CONFLICT (recipient_id, message_id, notification_type) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS messages_enqueue_downstream_work ON public.messages;
CREATE TRIGGER messages_enqueue_downstream_work
AFTER INSERT ON public.messages
FOR EACH ROW EXECUTE FUNCTION public.enqueue_message_downstream_work();

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_safety_outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_notification_outbox ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS messages_select_members ON public.messages;
CREATE POLICY messages_select_members
ON public.messages FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.relationships r
    WHERE r.id = messages.relationship_id
      AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
      AND r.chat_archived_at IS NULL
  )
);

DROP POLICY IF EXISTS messages_insert_sender_active ON public.messages;
CREATE POLICY messages_insert_sender_active
ON public.messages FOR INSERT TO authenticated
WITH CHECK (
  sender_id = auth.uid()
  AND EXISTS (
    SELECT 1
    FROM public.relationships r
    WHERE r.id = messages.relationship_id
      AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
      AND r.status = 'active'
      AND r.chat_archived_at IS NULL
  )
);

REVOKE ALL ON public.message_safety_outbox FROM anon, authenticated;
REVOKE ALL ON public.message_notification_outbox FROM anon, authenticated;

REVOKE INSERT ON public.messages FROM authenticated;
GRANT INSERT (
  relationship_id,
  sender_id,
  client_message_id,
  content,
  media_url,
  media_type
) ON public.messages TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_delivered(p_message_ids uuid[])
RETURNS TABLE (
  id uuid,
  delivered_at timestamptz,
  read_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  RETURN QUERY
  WITH candidate_messages AS (
    SELECT m.id
    FROM public.messages m
    JOIN public.relationships r
      ON r.id = m.relationship_id
    WHERE m.id = ANY(p_message_ids)
      AND m.sender_id <> auth.uid()
      AND r.chat_archived_at IS NULL
      AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
    LIMIT 200
  ),
  updated AS (
    UPDATE public.messages m
    SET delivered_at = COALESCE(m.delivered_at, now())
    FROM candidate_messages c
    WHERE m.id = c.id
    RETURNING m.id, m.delivered_at, m.read_at
  )
  SELECT updated.id, updated.delivered_at, updated.read_at
  FROM updated;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_conversation_read(p_relationship_id uuid)
RETURNS TABLE (
  id uuid,
  delivered_at timestamptz,
  read_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  RETURN QUERY
  WITH membership AS (
    SELECT 1
    FROM public.relationships r
    WHERE r.id = p_relationship_id
      AND r.chat_archived_at IS NULL
      AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
  ),
  updated AS (
    UPDATE public.messages m
    SET delivered_at = COALESCE(m.delivered_at, now()),
        read_at = COALESCE(m.read_at, now())
    WHERE EXISTS (SELECT 1 FROM membership)
      AND m.relationship_id = p_relationship_id
      AND m.sender_id <> auth.uid()
      AND m.read_at IS NULL
    RETURNING m.id, m.delivered_at, m.read_at
  )
  SELECT updated.id, updated.delivered_at, updated.read_at
  FROM updated;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_delivered(uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_delivered(uuid[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.mark_delivered(uuid[]) TO authenticated;

REVOKE ALL ON FUNCTION public.mark_conversation_read(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_conversation_read(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.mark_conversation_read(uuid) TO authenticated;
