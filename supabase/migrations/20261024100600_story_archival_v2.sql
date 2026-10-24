-- supabase/migrations/20261024100600_story_archival_v2.sql
--
-- Stories Wave 5 (review 04 #7, #9, #14):
--   * claim_story_archival_batch returns each image's width and height, so
--     the worker resizes by the LONG edge (portrait stories never reached the
--     1600 px target). It closes, and never claims, a job whose story is
--     soft-deleted or already considered.
--   * fail_story_archival acts only on a job that is being processed: a
--     failure that lands after delete_story_item closed the job no longer
--     reopens it into a spurious dead letter.
--   * skip_story_archival: an image already within 1600 px is considered and
--     left alone (no re-encode, no swap, nothing deleted).
--   * The video close-out UPDATE gets a partial index; the worker runs every
--     5 minutes, and only while something is due (it was 20 images an hour).
--   * complete_story_archival keeps its body and the old key's 600 s delay
--     (ruling 5), with one guard: a late second complete for a story that is
--     already swapped (a lease that ran out while the first worker was still
--     finishing; both use the same archive key) no longer queues the LIVE
--     rendition for deletion. It now pins search_path too.
-- All four functions pin search_path to ''. claim's RETURNS TABLE changes,
-- so DROP + CREATE; one transaction.
BEGIN;

-- The index below takes a brief write lock on story_items: give up rather
-- than queue behind a long transaction.
SET LOCAL lock_timeout = '5s';

DROP FUNCTION IF EXISTS public.claim_story_archival_batch(int);

CREATE FUNCTION public.claim_story_archival_batch(p_limit int)
RETURNS TABLE (
  story_id     uuid,
  media_key    text,
  media_width  int,
  media_height int
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_limit int := LEAST(GREATEST(COALESCE(p_limit, 25), 1), 200);
BEGIN
  -- Video: considered and left alone (no transcoding runtime, §4.4).
  UPDATE public.story_items si
     SET downscaled_at = now()
   WHERE si.media_type = 'video'
     AND si.deleted_at IS NULL
     AND si.downscaled_at IS NULL
     AND si.expires_at <= now();

  -- 04 #14: a job whose story is gone, or already considered, is closed.
  UPDATE public.story_media_processing_outbox o
     SET state = 'done',
         completed_at = now(),
         updated_at = now(),
         last_error_code = CASE WHEN si.deleted_at IS NOT NULL THEN 'story_deleted' ELSE o.last_error_code END
    FROM public.story_items si
   WHERE si.id = o.story_item_id
     AND o.state IN ('pending', 'processing')
     AND (si.deleted_at IS NOT NULL OR si.downscaled_at IS NOT NULL);

  RETURN QUERY
  UPDATE public.story_media_processing_outbox o
     SET state                 = 'processing',
         attempts              = o.attempts + 1,
         processing_started_at = now(),
         updated_at            = now()
    FROM public.story_items si
   WHERE si.id = o.story_item_id
     AND o.story_item_id IN (
           SELECT j.story_item_id
             FROM public.story_media_processing_outbox j
             JOIN public.story_items s2 ON s2.id = j.story_item_id
            WHERE j.available_at <= now()
              AND s2.deleted_at IS NULL
              AND s2.downscaled_at IS NULL
              AND (
                    j.state = 'pending'
                    OR (
                         j.state = 'processing'
                         AND j.processing_started_at
                             <= now() - public.story_archival_lease_timeout()
                       )
                  )
            ORDER BY j.available_at, j.created_at
            LIMIT v_limit
              FOR UPDATE OF j SKIP LOCKED
         )
  RETURNING o.story_item_id, o.source_key, si.media_width, si.media_height;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_story_archival_batch(int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_story_archival_batch(int) TO service_role;

CREATE OR REPLACE FUNCTION public.fail_story_archival(
  p_story_id uuid,
  p_error_code text
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_attempts int;
  v_dead_lettered boolean := false;
BEGIN
  IF p_story_id IS NULL THEN
    RETURN jsonb_build_object('error', true, 'code', 'INVALID_INPUT');
  END IF;

  UPDATE public.story_media_processing_outbox o
     SET last_error_code = left(p_error_code, 120),
         state = CASE
                   WHEN o.attempts >= public.story_archival_max_attempts() THEN 'dead_letter'
                   ELSE 'pending'
                 END,
         updated_at = now()
   WHERE o.story_item_id = p_story_id
     AND o.state = 'processing'
  RETURNING o.attempts, (o.state = 'dead_letter') INTO v_attempts, v_dead_lettered;

  IF v_attempts IS NULL THEN
    -- No job being processed: deleted mid-flight (closed by
    -- delete_story_item), cascaded away, or never existed. A zero-row finish
    -- is cancellation, not worker failure (§4.4).
    RETURN jsonb_build_object('error', false, 'found', false);
  END IF;

  RETURN jsonb_build_object(
    'error', false, 'found', true,
    'attempts', v_attempts, 'dead_letter', v_dead_lettered
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fail_story_archival(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fail_story_archival(uuid, text) TO service_role;

CREATE OR REPLACE FUNCTION public.skip_story_archival(p_story_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_skipped boolean;
BEGIN
  IF p_story_id IS NULL THEN
    RETURN jsonb_build_object('error', true, 'code', 'INVALID_INPUT');
  END IF;
  PERFORM 1 FROM public.story_items si WHERE si.id = p_story_id FOR UPDATE;
  UPDATE public.story_items si
     SET downscaled_at = now()
   WHERE si.id = p_story_id
     AND si.deleted_at IS NULL
     AND si.downscaled_at IS NULL;
  v_skipped := FOUND;
  IF v_skipped THEN
    UPDATE public.story_media_processing_outbox o
       SET state = 'done', completed_at = now(), updated_at = now(), last_error_code = 'already_small'
     WHERE o.story_item_id = p_story_id
       AND o.state IN ('pending', 'processing');
  END IF;
  RETURN jsonb_build_object('error', false, 'skipped', v_skipped);
END;
$$;

REVOKE ALL ON FUNCTION public.skip_story_archival(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.skip_story_archival(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.complete_story_archival(
  p_story_id uuid,
  p_new_key text
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_old_key text;
  v_deleted_at timestamptz;
  v_relationship_id uuid;
  v_swapped boolean := false;
BEGIN
  IF p_story_id IS NULL OR p_new_key IS NULL OR p_new_key = '' THEN
    RETURN jsonb_build_object('error', true, 'code', 'INVALID_INPUT');
  END IF;

  PERFORM 1 FROM public.story_items si WHERE si.id = p_story_id FOR UPDATE;

  SELECT si.media_key, si.deleted_at, si.relationship_id
    INTO v_old_key, v_deleted_at, v_relationship_id
    FROM public.story_items si
   WHERE si.id = p_story_id;

  UPDATE public.story_items si
     SET media_key     = p_new_key,
         downscaled_at = now()
   WHERE si.id = p_story_id
     AND si.deleted_at IS NULL
     AND si.downscaled_at IS NULL;

  v_swapped := FOUND;

  IF NOT v_swapped THEN
    -- Deleted mid-flight, or another worker already won this row: the
    -- object this call uploaded is not referenced, so it goes (no delay:
    -- no signed URL was ever minted for it). Unless the row is LIVE and
    -- already points at it: then it is the rendition the earlier call
    -- swapped in. A deleted row's key is queued even then: this call's
    -- upsert may have re-created an object the drain had already removed,
    -- and a deleted row's key is unreadable to clients, so no delay.
    IF v_old_key IS DISTINCT FROM p_new_key OR v_deleted_at IS NOT NULL THEN
      PERFORM public.queue_story_media_deletion('story-media', p_new_key);
    END IF;

    RETURN jsonb_build_object(
      'error', false, 'swapped', false, 'story_id', p_story_id
    );
  END IF;

  -- The OLD rendition goes after the signed-URL TTL (§4.4), and the change
  -- signal makes a client holding the old key refetch (§5.5).
  PERFORM public.queue_story_media_deletion(
    'story-media',
    v_old_key,
    now() + make_interval(secs => public.story_archive_ttl_seconds())
  );

  IF v_relationship_id IS NOT NULL THEN
    PERFORM public.bump_story_signal(v_relationship_id);
  END IF;

  UPDATE public.story_media_processing_outbox o
     SET state = 'done',
         completed_at = now(),
         updated_at = now()
   WHERE o.story_item_id = p_story_id;

  RETURN jsonb_build_object(
    'error', false, 'swapped', true, 'story_id', p_story_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.complete_story_archival(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_story_archival(uuid, text) TO service_role;

CREATE INDEX IF NOT EXISTS idx_story_items_video_closeout
  ON public.story_items (expires_at)
  WHERE media_type = 'video' AND downscaled_at IS NULL AND deleted_at IS NULL;

-- The cron's stale-lease check (pending is covered by idx_story_media_jobs_claim).
-- done rows are never pruned, so an idle tick must not scan the outbox.
CREATE INDEX IF NOT EXISTS idx_story_media_jobs_processing
  ON public.story_media_processing_outbox (processing_started_at)
  WHERE state = 'processing';

DO $$
BEGIN
  PERFORM cron.unschedule('invoke-story-archival');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

-- Every 5 minutes, only while a job or a video close-out is due, through the
-- vault-backed helper (20260931120000), like build-data-exports.
SELECT cron.schedule(
  'invoke-story-archival',
  '*/5 * * * *',
  $cron$
  SELECT public.invoke_edge_function('process-story-archival')
   WHERE EXISTS (
           SELECT 1 FROM public.story_media_processing_outbox o
            WHERE o.state = 'pending' AND o.available_at <= now())
      OR EXISTS (
           SELECT 1 FROM public.story_media_processing_outbox o
            WHERE o.state = 'processing'
              AND o.processing_started_at <= now() - public.story_archival_lease_timeout())
      OR EXISTS (
           SELECT 1 FROM public.story_items si
            WHERE si.media_type = 'video' AND si.deleted_at IS NULL
              AND si.downscaled_at IS NULL AND si.expires_at <= now());
  $cron$
);

COMMIT;
