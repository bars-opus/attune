-- Spec 3b final review M-2: the chapter gate's helpers (20261018110200) are
-- called by policies as the caller, so authenticated keeps EXECUTE; anon has
-- no use for them, and game_session_relationship would be an id oracle.
REVOKE ALL ON FUNCTION public.chapter_rpc_open(text, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.game_session_relationship(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.game_round_relationship(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.relationship_active_for_me(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chapter_rpc_open(text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.game_session_relationship(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.game_round_relationship(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.relationship_active_for_me(uuid) TO authenticated;
