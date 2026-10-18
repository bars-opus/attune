-- Spec 3a: grants for the lifecycle (20261018100000). Clients call the five
-- RPCs and the read helper; the internals run only inside them.
REVOKE ALL ON FUNCTION public.relationship_chat_open(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.relationship_chat_open_for(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.pause_relationship(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.resume_relationship(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.end_relationship(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.seal_my_side(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_relationship_lifecycle() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.relationship_chat_open(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pause_relationship(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resume_relationship(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.end_relationship(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.seal_my_side(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_relationship_lifecycle() TO authenticated;

REVOKE ALL ON FUNCTION public.relationship_cancel_pending_pushes(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.relationship_take_healing_snapshot(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.relationship_archive(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.relationship_end_internal(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.relationship_lock_mine(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.close_relationship_windows() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.relationship_archive_on_new_chapter() FROM PUBLIC, anon, authenticated;

REVOKE ALL ON public.relationship_seals FROM anon, authenticated;
REVOKE ALL ON public.healing_ending_snapshots FROM anon, authenticated;
GRANT SELECT ON public.relationship_seals TO authenticated;
GRANT SELECT ON public.healing_ending_snapshots TO authenticated;

-- I1. Who ended it, who paused, and why it was archived (for instance "the
-- other person started a new relationship") are not the ex's to read, by
-- query or by realtime. The lifecycle RPC (SECURITY DEFINER) still reads
-- them and shares only what R3-9 allows.
REVOKE SELECT ON public.relationships FROM authenticated, anon;
GRANT SELECT (
  id, user_a, user_b, invite_code, invite_expires_at, invite_accepted_at,
  status, started_at, created_at, ended_at, deletion_scheduled_at,
  total_sessions, message_count, games_completed, last_overall_pulse,
  chat_archived_at, chat_name, chat_avatar_url, chat_avatar_thumbnail_url,
  paused_at
) ON public.relationships TO authenticated;
