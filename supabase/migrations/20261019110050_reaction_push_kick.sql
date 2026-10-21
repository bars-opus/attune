-- supabase/migrations/20261019110050_reaction_push_kick.sql
--
-- Chat review #14 (07 H-2), 1b Task 5 fix round: a message's outbox row is
-- kicked to process-chat-notification-outbox the moment it is queued
-- (enqueue_message_downstream_work, 20261019100100), but a reaction's row
-- had no kick and waited for the minute cron. This redefines
-- enqueue_reaction_notification (last defined in 20260901140000) with
-- every existing behaviour kept -- the message sender is the recipient, no
-- self-notification, nothing for a deleted message, a re-react collapses
-- onto the one (recipient, message, type) row and resets it to pending --
-- and adds the same per-insert kick: same app_setting lookup, same
-- headers, and a failed kick is swallowed so it never fails the reaction
-- (the cron still sweeps the row). The worker then wakes the sender
-- (process-scheduled-notifications), so Spec 1b's quiet-hours and copy
-- guards still see the push.
--
-- CREATE OR REPLACE keeps the owner, the privileges and the trigger
-- (enqueue_reaction_notification_trigger) as they are; no grants change.
-- Contract: supabase/tests/reaction_push_kick_contracts.sql.

CREATE OR REPLACE FUNCTION public.enqueue_reaction_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_message public.messages%ROWTYPE;
  v_recipient_id uuid;
  v_outbox_id uuid;
  v_supabase_url text;
  v_service_role_key text;
BEGIN
  SELECT * INTO v_message FROM public.messages WHERE id = NEW.message_id;
  IF NOT FOUND OR v_message.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- Notify the MESSAGE'S SENDER (whoever wrote the message being reacted
  -- to), not "the other relationship member" generically -- if you react
  -- to your OWN message, sender_id = NEW.user_id and there is nothing to
  -- notify (self-notification is meaningless and would leak your own
  -- action back to yourself as a push).
  v_recipient_id := v_message.sender_id;
  IF v_recipient_id = NEW.user_id THEN
    RETURN NEW;
  END IF;

  -- Same UNIQUE-conflict shape as enqueue_message_downstream_work's
  -- message_notification_outbox insert: a rapid re-react collapses to one
  -- outbox row via the UPDATE below rather than piling up duplicates,
  -- since (recipient_id, message_id, notification_type) is UNIQUE.
  INSERT INTO public.message_notification_outbox (
    message_id, relationship_id, recipient_id, sender_id,
    notification_type, reaction_emoji, reactor_id
  )
  VALUES (
    NEW.message_id, NEW.relationship_id, v_recipient_id, NEW.user_id,
    'message_reaction', NEW.emoji, NEW.user_id
  )
  ON CONFLICT (recipient_id, message_id, notification_type)
  DO UPDATE SET
    reaction_emoji = EXCLUDED.reaction_emoji,
    reactor_id = EXCLUDED.reactor_id,
    state = 'pending',
    attempts = 0,
    created_at = now()
  RETURNING id INTO v_outbox_id;

  -- Chat review #14: kick the worker now instead of leaving the row to the
  -- minute cron -- the same lookup and request enqueue_message_downstream_
  -- work makes for a message.
  v_supabase_url := public.app_setting('supabase_url');
  v_service_role_key := public.app_setting('service_role_key');
  IF v_outbox_id IS NOT NULL AND v_supabase_url IS NOT NULL AND v_service_role_key IS NOT NULL THEN
    BEGIN
      PERFORM net.http_post(
        url := v_supabase_url || '/functions/v1/process-chat-notification-outbox',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_service_role_key,'apikey',v_service_role_key),
        body := jsonb_build_object('outbox_id', v_outbox_id));
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;

  RETURN NEW;
END;
$function$;
