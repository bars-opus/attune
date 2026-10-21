-- Chat W1a (#9): stop touching the published relationships row per message.
--
-- enqueue_message_downstream_work ran UPDATE relationships SET
-- message_count = message_count + 1 on every insert. Both chat channels on
-- both phones subscribe to relationships UPDATE (that is how a pause, an
-- ending or a renamed chat arrives), so every message produced a second
-- realtime frame per device plus a full header refetch, and both partners'
-- inserts queued on one hot row. The count moves to an unpublished side
-- table; relationships.message_count is frozen at its last value.
--
-- Explicit transaction: LOCK TABLE needs one, and `supabase db push`
-- (CLI 2.75) runs a file's statements without wrapping them.

BEGIN;

CREATE TABLE IF NOT EXISTS public.relationship_message_counters (
  relationship_id uuid PRIMARY KEY REFERENCES public.relationships(id) ON DELETE CASCADE,
  message_count bigint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.relationship_message_counters ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS relationship_message_counters_select ON public.relationship_message_counters;
CREATE POLICY relationship_message_counters_select
  ON public.relationship_message_counters
  FOR SELECT TO authenticated
  USING (public.relationship_chat_open(relationship_id));

-- Block writers so no message committed between the seed and the function
-- swap below goes uncounted (released at commit).
LOCK TABLE public.messages IN SHARE MODE;

-- Seed from the real rows, not the frozen column, so the two agree today.
INSERT INTO public.relationship_message_counters (relationship_id, message_count)
SELECT r.id, (SELECT count(*) FROM public.messages m WHERE m.relationship_id = r.id)
FROM public.relationships r
ON CONFLICT (relationship_id) DO UPDATE
  SET message_count = EXCLUDED.message_count, updated_at = now();

COMMENT ON COLUMN public.relationships.message_count IS
  'Not maintained per insert since 2026-10-19 (chat W1a #9); only the import revoke/delete paths and cancel_chat_imports_on_relationship_change still recompute it. Read relationship_message_counters.';

CREATE OR REPLACE FUNCTION public.messages_count_on_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  UPDATE public.relationship_message_counters
     SET message_count = GREATEST(message_count - 1, 0), updated_at = now()
   WHERE relationship_id = OLD.relationship_id;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS messages_count_on_delete ON public.messages;
CREATE TRIGGER messages_count_on_delete
  AFTER DELETE ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.messages_count_on_delete();

CREATE OR REPLACE FUNCTION public.enqueue_message_downstream_work()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_relationship public.relationships%ROWTYPE;
  v_recipient_id uuid;
  v_notification_outbox_id uuid;
  v_supabase_url text;
  v_service_role_key text;
BEGIN
  SELECT * INTO v_relationship FROM public.relationships WHERE id = NEW.relationship_id;
  IF NOT FOUND THEN RETURN NEW; END IF;
  -- W1a #9: the per-message count lives off the published relationships row.
  INSERT INTO public.relationship_message_counters (relationship_id, message_count)
  VALUES (NEW.relationship_id, 1)
  ON CONFLICT (relationship_id) DO UPDATE
    SET message_count = public.relationship_message_counters.message_count + 1,
        updated_at = now();
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
$function$;

COMMIT;
