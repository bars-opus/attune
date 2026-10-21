-- supabase/migrations/20261019110220_deactivate_other_push_subscriptions.sql
-- Chat review #18 (fix I2): "Sign out other devices" (Spec 2, account
-- sessions) revokes the other sessions' refresh tokens, but a revoked phone
-- only notices on its next token refresh (up to ~1 h) and keeps receiving
-- this person's pushes until then. The app calls this right after the
-- revoke: every other device of the caller stops at once; the phone that
-- asked (p_keep_subscription_id; NULL when it has no push subscription)
-- keeps receiving. Runs as auth.uid(); push_tokens stays closed to clients.
CREATE OR REPLACE FUNCTION public.deactivate_other_push_subscriptions(p_keep_subscription_id text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_session uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'push_subscription:not_signed_in'; END IF;
  -- Only a live session may stop the others: a phone that was itself
  -- signed out elsewhere still holds a valid access token for up to ~1 h
  -- and must not silence the owner's phones (fix round 2). Fail-closed
  -- without session_id, as register below and register_my_device do.
  BEGIN
    v_session := nullif(auth.jwt()->>'session_id', '')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    v_session := NULL;
  END;
  IF v_session IS NULL OR NOT EXISTS (
       SELECT 1 FROM auth.sessions s
       WHERE s.id = v_session AND s.user_id = v_uid
         AND (s.not_after IS NULL OR s.not_after > now())) THEN
    RAISE EXCEPTION 'push_subscription:session_revoked';
  END IF;
  IF p_keep_subscription_id IS NOT NULL
     AND p_keep_subscription_id !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
    RAISE EXCEPTION 'push_subscription:invalid';
  END IF;
  UPDATE public.push_tokens SET is_active = false, updated_at = now()
  WHERE user_id = v_uid AND is_active
    AND token IS DISTINCT FROM lower(p_keep_subscription_id);
END;
$$;

-- Fix round 1 addendum: a phone signed out from another device keeps a
-- valid access token until it expires (up to ~1 h). Without this check,
-- reopening the app in that window re-registered its device and undid the
-- deactivation above. register now also requires the token's session to
-- still exist in auth.sessions (Supabase deletes a revoked session's row)
-- and not to have run out (not_after). Fail-closed when the token has no
-- session_id: every access token GoTrue issues for a user session carries
-- it, and register_my_device (Spec 2) already refuses without it.
-- Everything else is exactly 20261019110200's: auth.uid() scoping,
-- validation, the device moving to whoever registers it, the cap of ten.
CREATE OR REPLACE FUNCTION public.register_push_subscription(p_subscription_id text, p_platform text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_session uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'push_subscription:not_signed_in'; END IF;
  BEGIN
    v_session := nullif(auth.jwt()->>'session_id', '')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    v_session := NULL;
  END;
  IF v_session IS NULL OR NOT EXISTS (
       SELECT 1 FROM auth.sessions s
       WHERE s.id = v_session AND s.user_id = v_uid
         AND (s.not_after IS NULL OR s.not_after > now())) THEN
    RAISE EXCEPTION 'push_subscription:session_revoked';
  END IF;
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
