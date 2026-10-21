-- The app recognises a stale media upload (its 15-minute intent ran out
-- before the insert) by the insert trigger's refusal text, and re-uploads
-- under a fresh intent instead of failing the send for good
-- (ChatError.staleMediaUploadRefusals, lib/features/chat/utils/chat_error.dart).
-- The trigger raises a bare P0001, so the text is the contract: rewording
-- one of these silently turns that recovery back into a permanent failure.
-- Change both sides together.
BEGIN;
DO $$
DECLARE
  v_src text;
  v_text text;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc
  WHERE proname = 'validate_message_media_before_insert'
    AND pronamespace = 'public'::regnamespace;
  IF v_src IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: validate_message_media_before_insert not found';
  END IF;
  FOREACH v_text IN ARRAY ARRAY[
    'Chat media upload intent is invalid or expired',
    'Chat media object is missing',
    'Chat media thumbnail upload intent is invalid or expired',
    'Chat media thumbnail object is missing'
  ] LOOP
    IF position(format('RAISE EXCEPTION %L', v_text) IN v_src) = 0 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: trigger no longer raises "%"; update ChatError.staleMediaUploadRefusals with it', v_text;
    END IF;
  END LOOP;

  -- The expiry the app's recovery exists for is still enforced.
  IF position('expires_at > now()' IN v_src) = 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: trigger no longer checks intent expiry';
  END IF;
END $$;
ROLLBACK;
