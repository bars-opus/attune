-- Spec 3 (forum removal) W2, migration 3 of 4: cancel every forum push still
-- waiting to go out. The existing cancel idiom
-- (20261018140400_put_away_gently.sql): status 'cancelled', the source key
-- released, last_error naming why. 'processing' rows are left to finish: the
-- dispatcher's own status update requires status = 'processing'. W3 deletes
-- these rows. One statement, so atomic without its own BEGIN/COMMIT;
-- idempotent (a second run matches nothing).
UPDATE public.scheduled_notifications
SET status = 'cancelled', source_key = NULL, last_error = 'forum_retired', updated_at = now()
WHERE status = 'pending'
  AND metadata->>'type' IN ('forum_topic_activated', 'forum_activity', 'forum_quiet');
