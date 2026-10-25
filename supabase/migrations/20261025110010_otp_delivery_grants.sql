-- Spec 1 W2c: grants for 20261025110000_otp_delivery.sql. The two decisions
-- and the hook's delivery check and mark are the edge functions' (service
-- role); everything else is server-only.
BEGIN;
REVOKE ALL ON private.otp_delivery_intents, private.otp_intent_attempts, private.otp_intent_refusals,
              private.otp_send_events, private.otp_routes, private.otp_destination_rules,
              private.otp_hook_deliveries
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE private.otp_send_events_id_seq FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.otp_refusal(text, interval) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.otp_routes_for(text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.otp_purge() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.otp_record_intent(text, text, text, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.otp_take_send_decision(text, text, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.otp_hook_delivery_sent(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.otp_mark_hook_delivery_sent(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.otp_record_intent(text, text, text, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.otp_take_send_decision(text, text, text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.otp_hook_delivery_sent(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.otp_mark_hook_delivery_sent(text) TO service_role;
COMMIT;
