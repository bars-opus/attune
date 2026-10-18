-- Spec 3b: grants for 20261018110000. Deletion and purge run only as the
-- service role (delete-account) or the cron owner; legal hold is the
-- service role's alone.
REVOKE ALL ON FUNCTION public.prepare_account_deletion(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_account_deletion(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.purge_relationship(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.purge_archived_relationships() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.relationship_queue_storage(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.messages_queue_media_before_delete() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.streak_clips_queue_media_before_delete() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dating_photos_queue_media_before_delete() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.relationships_queue_media_before_delete() FROM PUBLIC, anon, authenticated;
-- relationships has no client UPDATE since 20261017110000; legal_hold is
-- listed so a later broad grant cannot reopen it silently.
REVOKE UPDATE (legal_hold) ON public.relationships FROM authenticated, anon;
