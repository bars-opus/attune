-- supabase/migrations/20261019110200_push_subscriptions.sql
--
-- Chat review #18 (07 H-3): a push reaches only devices the recipient's own
-- signed-in session registered. The sender targeted the OneSignal alias
-- external_id = user id; anyone with the OneSignal app id (it ships in the
-- binary) and the partner's user id (readable by design) could call
-- OneSignal.login(<that id>) on their own phone and receive every push --
-- an ex, or a controlling partner. OneSignal's remedy, Identity
-- Verification, is not exposed by the Flutter SDK (5.5.1 … 5.7.1:
-- login(externalId) only; loginWithJWT is @Deprecated "not implemented"),
-- so the server stops trusting the alias: push_tokens.token holds the
-- device's OneSignal push subscription id, written only through these RPCs
-- as auth.uid(), and process-scheduled-notifications targets
-- include_subscription_ids from this table.
--
-- A subscription id is a OneSignal-minted UUID known only to the device
-- that owns it. Re-registering it moves it to the caller (the same phone, a
-- new account): the previous account stops receiving on that phone, which
-- is what sign-out must achieve anyway.

COMMENT ON COLUMN public.push_tokens.token IS
  'OneSignal push subscription id of one device (not an APNs/FCM token). Written only by register_push_subscription / unregister_push_subscription (chat review #18).';

-- Whatever is in the table today was written by the old direct-insert path
-- (savePushToken: raw APNs/FCM tokens), never by these RPCs, so none of it
-- is a OneSignal subscription id. Left active it would be handed to
-- OneSignal as include_subscription_ids and fail every push for that
-- person until the invalid-id pruning caught up. Devices re-register on
-- the next app open (OneSignalService._syncSubscription).
UPDATE public.push_tokens SET is_active = false, updated_at = now() WHERE is_active;

CREATE OR REPLACE FUNCTION public.register_push_subscription(p_subscription_id text, p_platform text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'push_subscription:not_signed_in'; END IF;
  IF p_subscription_id IS NULL
     OR p_subscription_id !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
     OR p_platform IS NULL OR p_platform NOT IN ('ios', 'android') THEN
    RAISE EXCEPTION 'push_subscription:invalid';
  END IF;
  INSERT INTO public.push_tokens (user_id, token, platform, is_active, created_at, updated_at)
  VALUES (v_uid, lower(p_subscription_id), p_platform, true, now(), now())
  ON CONFLICT (token) DO UPDATE
    SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform,
        is_active = true, updated_at = now();
  -- A phone keeps one live subscription; reinstalls mint new ids. The
  -- newest ten per person stay active so the table cannot grow unbounded.
  -- The device registering right now is always one of the ten kept: it is
  -- ranked first, so a tie on updated_at (possible inside one transaction,
  -- e.g. the contract test) can neither cap it out nor leave eleven active.
  UPDATE public.push_tokens t SET is_active = false, updated_at = now()
  WHERE t.user_id = v_uid AND t.is_active
    -- Belt-and-braces: the ranking below already keeps this token; this guard
    -- keeps it even if the ORDER BY is ever edited.
    AND t.token <> lower(p_subscription_id)
    AND t.id NOT IN (SELECT k.id FROM public.push_tokens k
                     WHERE k.user_id = v_uid AND k.is_active
                     ORDER BY (k.token = lower(p_subscription_id)) DESC,
                              k.updated_at DESC, k.id
                     LIMIT 10);
END;
$$;

CREATE OR REPLACE FUNCTION public.unregister_push_subscription(p_subscription_id text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  UPDATE public.push_tokens SET is_active = false, updated_at = now()
  WHERE token = lower(p_subscription_id) AND user_id = auth.uid() AND is_active;
$$;
