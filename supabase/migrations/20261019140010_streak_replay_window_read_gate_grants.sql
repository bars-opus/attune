-- Grants for 20261019140000: clients read clips only through the gated RPC;
-- the destroy step runs only inside it (and mark_streak_viewed inlines its
-- own copy).
REVOKE ALL ON FUNCTION public.expire_streak_clips(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.streak_clips_for_viewing(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.streak_clips_for_viewing(uuid) TO authenticated;
