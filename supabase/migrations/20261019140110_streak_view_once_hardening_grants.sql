-- Grants for 20261019140100.
--
-- The spend ledger is server-only: no client privilege at all (RLS is on
-- with no policies as well, for the platform's default table grants).
REVOKE ALL ON TABLE public.streak_view_spends FROM PUBLIC, anon, authenticated;

-- Both spend forms are client RPCs (the 1-arg one for older clients).
REVOKE ALL ON FUNCTION public.mark_streak_viewed(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_streak_viewed(uuid, uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.mark_streak_viewed(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_streak_viewed(uuid) TO authenticated;

-- The recipient-window helper is called from the message-media storage
-- policy and the streak_clips read policy, which run as the caller.
REVOKE ALL ON FUNCTION public.streak_replay_open(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.streak_replay_open(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.streak_recipient_may_sign(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.streak_recipient_may_sign(uuid) TO authenticated;

-- The sweep runs from pg_cron only; the destroy step stays internal.
REVOKE ALL ON FUNCTION public.sweep_abandoned_streaks() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.expire_streak_clips(uuid) FROM PUBLIC, anon, authenticated;

-- Restated (CREATE OR REPLACE keeps it, this pins it).
REVOKE ALL ON FUNCTION public.streak_clips_for_viewing(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.streak_clips_for_viewing(uuid) TO authenticated;
