-- Phase 12 — enqueue_booking_reminder helper
--
-- Single channel-branching writer for scheduled_notifications.
-- Used by:
--   * The AFTER INSERT trigger on bookings → 24h + 2h reminders
--   * cancel_and_followup helper → review_request, recovery_checkin
--   * enqueue_rebook_nudges() (Wave 3) → rebook_nudge
--
-- Channel routing (RESEARCH §17):
--   * Registered user (bookings.user_id NOT NULL)   → 'push'
--   * Guest booking   (bookings.guest_profile_id)   → 'whatsapp'
--                                                     uses denormalized
--                                                     guest_phone /
--                                                     guest_name first,
--                                                     falls back to
--                                                     guest_profiles
--                                                     JOIN.
--
-- WhatsApp template names are derived as `<notification_type>_v1`
-- (rebook_nudge_v1, review_request_v1, recovery_checkin_v1).
-- The existing 6h WhatsAppTemplateNotFoundError retry covers the Meta
-- approval window — Phase 12 does not need a gating flag.
--
-- NOT GRANTed to authenticated. Called only from triggers / SECURITY
-- DEFINER RPCs.

CREATE OR REPLACE FUNCTION public.enqueue_booking_reminder(
  p_booking_id    UUID,
  p_type          notification_type,
  p_scheduled_for TIMESTAMPTZ
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $function$
DECLARE
  v_booking     public.bookings%ROWTYPE;
  v_shop_name   TEXT;
  v_client_name TEXT;
  v_phone       TEXT;
  v_template    TEXT;
  v_channel     TEXT;
  v_notif_id    UUID;
  v_title       TEXT;
  v_body        TEXT;
BEGIN
  SELECT * INTO v_booking FROM public.bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN RETURN NULL; END IF;

  SELECT sh.shop_name INTO v_shop_name FROM public.shops sh WHERE sh.id = v_booking.shop_id;

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
    v_template := p_type::text || '_v1';
  END IF;

  -- Per-category copy (RESEARCH §10).
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
      'We noticed your last appointment at ' || v_shop_name || ' didn''t happen. Book a new time whenever works for you.'
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
    CASE WHEN v_channel = 'whatsapp'
         THEN jsonb_build_object('1', v_client_name, '2', v_shop_name)
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
  'Channel-branching writer for scheduled_notifications. Single source of metadata + whatsapp_params for the five Phase 12 categories. SECURITY DEFINER; not exposed to clients. O(1). Phase 12.';
