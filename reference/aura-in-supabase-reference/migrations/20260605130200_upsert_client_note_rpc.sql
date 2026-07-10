-- Phase 12 — upsert_client_note RPC
--
-- Authz FIRST: caller must own the target shop. Defence-in-depth
-- exactly-one-of identity check (the table CHECK enforces the same).
-- Empty body is allowed (soft-clear sentinel); only > 2000 chars raises.
-- HINT codes match the Phase 11 hardening template (RESEARCH §12).

CREATE OR REPLACE FUNCTION public.upsert_client_note(
  p_shop_id          UUID,
  p_user_id          UUID,
  p_guest_profile_id UUID,
  p_body             TEXT
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $function$
DECLARE
  v_owns_shop BOOLEAN;
  v_note_id   UUID;
BEGIN
  -- Authz FIRST.
  SELECT EXISTS (
    SELECT 1 FROM public.shops
    WHERE id = p_shop_id AND user_id = auth.uid()
  ) INTO v_owns_shop;
  IF NOT v_owns_shop THEN
    RAISE EXCEPTION 'not_found'
      USING ERRCODE = '42501', HINT = 'NOT_SHOP_OWNER';
  END IF;

  -- Defence-in-depth: exactly one of user_id / guest_profile_id.
  IF (p_user_id IS NULL) = (p_guest_profile_id IS NULL) THEN
    RAISE EXCEPTION 'invalid_identity'
      USING ERRCODE = '22023', HINT = 'EXACTLY_ONE_OF_USER_OR_GUEST';
  END IF;

  IF p_body IS NULL THEN
    RAISE EXCEPTION 'invalid_input'
      USING ERRCODE = '22023', HINT = 'BODY_NULL_NOT_ALLOWED';
  END IF;

  IF char_length(p_body) > 2000 THEN
    RAISE EXCEPTION 'invalid_input'
      USING ERRCODE = '22023', HINT = 'NOTE_TOO_LONG';
  END IF;

  INSERT INTO public.client_notes (
    shop_id, user_id, guest_profile_id, body,
    updated_at, updated_by_user_id
  ) VALUES (
    p_shop_id, p_user_id, p_guest_profile_id, p_body,
    now(), auth.uid()
  )
  ON CONFLICT (shop_id, COALESCE(user_id::text, guest_profile_id::text))
  DO UPDATE SET
    body = EXCLUDED.body,
    updated_at = now(),
    updated_by_user_id = auth.uid()
  RETURNING id INTO v_note_id;

  RETURN v_note_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.upsert_client_note(UUID, UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_client_note(UUID, UUID, UUID, TEXT) TO authenticated;
COMMENT ON FUNCTION public.upsert_client_note(UUID, UUID, UUID, TEXT) IS
  'Upsert a per-shop / per-client sticky note. SECURITY DEFINER with shops.user_id=auth.uid() gate. Defence-in-depth exactly-one-of identity check. O(1) by unique index lookup. Phase 12.';
