-- supabase/migrations/20261019110330_release_push_subscription.sql
--
-- Plan 1b final review I1: a phone signed out offline cannot call
-- unregister_push_subscription (it needs the session that just ended), so
-- its push_tokens row stays active and the previous account's pushes can
-- still reach it once it is back online with the app closed. The app keeps
-- the subscription id as an "owed release" and sends it here on the next
-- start (signed in or not) and when the network returns.
--
-- Trust model: the same as register's (Task 6): a OneSignal subscription id
-- is a device-minted UUID that never leaves the phone, so holding it is
-- proof of possession. This adds only "whoever holds the id can silence
-- that device". It deactivates exactly that row, never moves it, returns
-- nothing (an unknown id looks the same as a known one) and is idempotent.
CREATE OR REPLACE FUNCTION public.release_push_subscription(p_subscription_id text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF p_subscription_id IS NULL
     OR p_subscription_id !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
    RAISE EXCEPTION 'push_subscription:invalid';
  END IF;
  UPDATE public.push_tokens SET is_active = false, updated_at = now()
  WHERE token = lower(p_subscription_id) AND is_active;
END;
$$;
