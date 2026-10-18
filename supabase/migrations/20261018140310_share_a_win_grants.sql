-- Spec 7: grants for 20261018140300.
REVOKE ALL ON public.win_card_dismissals FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.timeline_events_win_guard() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.share_a_win(uuid, text, text, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_win_cards(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.dismiss_win_card(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.share_a_win(uuid, text, text, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_win_cards(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dismiss_win_card(uuid) TO authenticated;
