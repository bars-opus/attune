-- Phase 13 — patch enqueue_booking_reminder for recovery code.
--
-- CREATE OR REPLACE the Phase 12 helper with FIVE surgical edits:
--   1. Declare new local `v_recovery_code TEXT`.
--   2. Before the v_template/v_body construction, conditionally call
--      generate_recovery_code() when p_type = 'recovery_checkin'.
--   3. The v_template CASE switches recovery_checkin's WhatsApp
--      template from _v1 → _v2 (3rd variable for the code).
--   4. whatsapp_params adds the {{3}} code variable when present.
--   5. The push body for recovery_checkin gets a "Use code X" suffix
--      when a code was generated.
--
-- Everything else — channel branching, the other four categories'
-- copy, the INSERT shape, the REVOKE/COMMENT trio — is byte-for-byte
-- unchanged. Phase 12 callers are unaffected because all five
-- categories still receive their original message shape; only
-- recovery_checkin changes.
--
-- The recovery code is OPTIONAL: when the shop has no active
-- loyalty rule, generate_recovery_code returns NULL and the message
-- falls back to the original Phase 12 text-only copy. No discount.

CREATE OR REPLACE FUNCTION public.enqueue_booking_reminder(
  p_booking_id    UUID,
  p_type          notification_type,
  p_scheduled_for TIMESTAMPTZ
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $function$
DECLARE
  v_booking       public.bookings%ROWTYPE;
  v_shop_name     TEXT;
  v_client_name   TEXT;
  v_phone         TEXT;
  v_template      TEXT;
  v_channel       TEXT;
  v_notif_id      UUID;
  v_title         TEXT;
  v_body          TEXT;
  v_recovery_code TEXT;  -- Phase 13 addition.
BEGIN
  SELECT * INTO v_booking FROM public.bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN RETURN NULL; END IF;

  SELECT sh.shop_name INTO v_shop_name FROM public.shops sh WHERE sh.id = v_booking.shop_id;

  -- Phase 13: generate the recovery code BEFORE composing the message.
  -- Returns NULL when the shop has no active loyalty rule, in which
  -- case the recovery_checkin message stays text-only.
  IF p_type = 'recovery_checkin' THEN
    v_recovery_code := public.generate_recovery_code(
      v_booking.shop_id, v_booking.user_id, v_booking.guest_profile_id
    );
  END IF;

  -- Channel branch: user_id → push, guest_profile_id → WhatsApp.
  IF v_booking.user_id IS NOT NULL THEN
    v_channel  := 'push';
    v_template := NULL;
  ELSE
    v_channel := 'whatsapp';
    v_phone   := COALESCE(v_booking.guest_phone,
                          (SELECT gp.phone FROM public.guest_profiles gp
                            WHERE gp.id = v_booking.guest_profile_id));
    v_client_name := COALESCE(v_booking.guest_name,
                              (SELECT gp.name FROM public.guest_profiles gp
                                WHERE gp.id = v_booking.guest_profile_id),
                              'there');
    -- Phase 13: recovery_checkin uses the 3-variable _v2 template ONLY
    -- when a recovery code was successfully generated. If the shop has
    -- no active loyalty rule (v_recovery_code IS NULL), fall back to
    -- the 2-variable _v1 template so Meta doesn't reject the dispatch
    -- for a missing {{3}} variable.
    v_template := CASE
      WHEN p_type = 'recovery_checkin' AND v_recovery_code IS NOT NULL
        THEN 'recovery_checkin_v2'
      ELSE p_type::text || '_v1'
    END;
  END IF;

  -- Per-category copy.
  v_title := CASE p_type
    WHEN 'booking_reminder_24h' THEN 'Appointment tomorrow'
    WHEN 'booking_reminder_2h'  THEN 'Appointment in 2 hours'
    WHEN 'rebook_nudge'         THEN 'Time for your next visit?'
    WHEN 'review_request'       THEN 'How was your visit?'
    WHEN 'recovery_checkin'     THEN 'We''d love to see you again'
    ELSE NULL
  END;

  v_body := CASE p_type
    WHEN 'booking_reminder_24h' THEN
      'Your appointment at ' || v_shop_name || ' is tomorrow.'
    WHEN 'booking_reminder_2h'  THEN
      'Your appointment at ' || v_shop_name || ' starts in 2 hours.'
    WHEN 'rebook_nudge'         THEN
      'It''s been a while since your last visit to ' || v_shop_name || '. Book again whenever you''re ready.'
    WHEN 'review_request'       THEN
      'Thanks for visiting ' || v_shop_name || '. Tap to leave a rating — takes 5 seconds.'
    WHEN 'recovery_checkin'     THEN
      -- Phase 13: append the code if generation succeeded.
      'We noticed your last appointment at ' || v_shop_name || ' didn''t happen. ' ||
      CASE WHEN v_recovery_code IS NOT NULL
           THEN 'Use code ' || v_recovery_code || ' for a discount on your next booking.'
           ELSE 'Book a new time whenever works for you.'
      END
    ELSE NULL
  END;

  INSERT INTO public.scheduled_notifications (
    user_id, guest_profile_id, booking_id, shop_id,
    notification_type, scheduled_for, delivery_channel,
    whatsapp_template, whatsapp_params, status, metadata
  ) VALUES (
    v_booking.user_id,
    v_booking.guest_profile_id,
    p_booking_id,
    v_booking.shop_id,
    p_type,
    p_scheduled_for,
    v_channel,
    v_template,
    -- Phase 13: WhatsApp params include {{3}} code when present.
    CASE WHEN v_channel = 'whatsapp'
         THEN CASE
           WHEN p_type = 'recovery_checkin' AND v_recovery_code IS NOT NULL
             THEN jsonb_build_object('1', v_client_name, '2', v_shop_name, '3', v_recovery_code)
           ELSE jsonb_build_object('1', v_client_name, '2', v_shop_name)
         END
         ELSE NULL END,
    'pending',
    CASE WHEN v_channel = 'whatsapp'
         THEN jsonb_build_object('phone', v_phone, 'booking_id', p_booking_id, 'shop_name', v_shop_name)
         ELSE jsonb_build_object('title', v_title, 'body', v_body, 'booking_id', p_booking_id, 'shop_name', v_shop_name)
    END
  )
  RETURNING id INTO v_notif_id;

  RETURN v_notif_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.enqueue_booking_reminder(UUID, notification_type, TIMESTAMPTZ) FROM PUBLIC;
-- Intentionally NOT GRANTed to authenticated. Called only from triggers
-- and SECURITY DEFINER RPCs.

COMMENT ON FUNCTION public.enqueue_booking_reminder(UUID, notification_type, TIMESTAMPTZ) IS
  'Channel-branching writer for scheduled_notifications. Single source of metadata + whatsapp_params for the five categories. SECURITY DEFINER; not exposed to clients. Phase 13: recovery_checkin now generates and embeds a discount code via generate_recovery_code (NULL-safe — no code when shop has no active loyalty rule). O(1).';
