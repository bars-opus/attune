-- Stories: delete_story_item, the media_deletion_queue's not_before
-- column, and the hard-delete cascade trigger. Spec §3.3 (security
-- contract) and §4.5 (deletion) are the binding authority; both are
-- short and explain WHY deferring physical deletion is safe.
--
-- media_deletion_queue is a SHARED table already used by chat media
-- (mark_streak_viewed, mark_video_viewed, 20260930120000). Adding a
-- column to it must not change existing behaviour: every row inserted
-- without not_before, and every row already in the queue, must behave
-- exactly as it does today. `not_before timestamptz NOT NULL DEFAULT
-- now()` is chosen specifically because it satisfies that -- an old
-- INSERT (or one from queue_media_deletion, which never mentions this
-- column) gets now() as before, and `not_before <= now()` is true for
-- every pre-existing row from the moment this migration runs.
ALTER TABLE public.media_deletion_queue
  ADD COLUMN IF NOT EXISTS not_before timestamptz NOT NULL DEFAULT now();

-- Task 10 (process-media-deletion-queue) is what actually adds
-- `not_before <= now()` to the drain's pending query; this migration
-- only introduces the column so that function has something to read.
-- Until Task 10 lands, the drain (20260930130000/index.ts, which selects
-- WHERE deleted_at IS NULL with no not_before filter) is unaffected: it
-- keeps draining every unstamped row regardless of not_before, which is
-- the existing behaviour this migration is required not to change.

COMMENT ON COLUMN public.media_deletion_queue.not_before IS
  'Earliest instant the drain may physically delete this object. '
  'Defaults to now() so ordinary enqueues (chat media, story media/'
  'thumbnail keys) are unaffected. Story archive-key re-enqueues from '
  'the downscale worker set this at least 600s out -- the signed-URL '
  'TTL -- so a player mid-playback on a freshly issued URL is not '
  'broken. Task 10 teaches the drain to respect this column.';

-- ---------------------------------------------------------------------
-- queue_story_media_deletion: the re-arming enqueue helper.
--
-- The existing public.queue_media_deletion (20260930120000) uses
-- ON CONFLICT (bucket_id, object_name) DO NOTHING. That is wrong for
-- stories' re-arm requirement (brief contract 4, spec §4.5's last two
-- paragraphs): deleting an already-completed queue entry a second time,
-- or a delete racing the archival worker's own enqueue of the same
-- deterministic key, must REVIVE the row rather than leave it
-- deleted_at-stamped forever. So this is a SEPARATE internal helper
-- (not a change to queue_media_deletion's contract, which chat still
-- depends on exactly as-is) that:
--
--   1. inserts with ON CONFLICT (bucket_id, object_name) DO UPDATE,
--      setting deleted_at = NULL (re-arms), refreshing requested_at
--      (spec §4.5's "refreshes requested_at"), and keeping the
--      EARLIER of the two not_before values ("keeps the earlier
--      not_before") -- so a re-arm can only pull the eligible time
--      forward, never push it back out.
--
-- This is what closes the delete/worker race spec §4.5 describes:
-- deletion enqueues the not-yet-created archive key; the drain runs and
-- stamps that no-op complete (the key never existed, so the Storage
-- API's remove() no-ops successfully); later the downscale worker
-- uploads the rendition and must re-enqueue the SAME key so it is ever
-- cleaned up when the story is later (or already) deleted. Without
-- re-arming, that second enqueue would hit DO NOTHING against an
-- already-deleted_at row and the object would leak forever.
--
-- SECURITY DEFINER, called only from other SECURITY DEFINER functions
-- (delete_story_item here; Task 9's downscale worker later), so it is
-- never granted to authenticated -- same posture as
-- queue_media_deletion itself.
CREATE OR REPLACE FUNCTION public.queue_story_media_deletion(
  p_bucket_id text,
  p_object_name text,
  p_not_before timestamptz DEFAULT now()
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_object_name IS NULL OR p_object_name = '' THEN
    RETURN;
  END IF;

  INSERT INTO public.media_deletion_queue
    (bucket_id, object_name, requested_at, not_before)
  VALUES
    (p_bucket_id, p_object_name, now(), COALESCE(p_not_before, now()))
  ON CONFLICT (bucket_id, object_name) DO UPDATE
    SET deleted_at   = NULL,
        requested_at = now(),
        not_before   = LEAST(
          public.media_deletion_queue.not_before,
          COALESCE(EXCLUDED.not_before, now())
        );
END;
$$;

REVOKE ALL ON FUNCTION public.queue_story_media_deletion(text, text, timestamptz)
  FROM PUBLIC, anon, authenticated;
-- Not granted to service_role either: every current and planned caller
-- (delete_story_item, the story_items cascade trigger below, Task 9's
-- downscale worker) is itself a SECURITY DEFINER function running as
-- the table owner, exactly like queue_media_deletion's own posture.

-- ---------------------------------------------------------------------
-- The deterministic archive key.
--
-- Task 9's archival worker (spec §4.4) writes a downscaled rendition to
-- a key derived from the story alone, so both the worker and this
-- deletion path can compute the SAME key independently without either
-- reading it off the other. Defined here, once, as a SQL function so
-- Task 9 calls the identical derivation rather than re-implementing it:
--
--   story-archive/<story_item_id>.jpg
--
-- (spec §4.5: "the deterministic story-archive/<story-id>.jpg key").
-- JPEG because §4.4 fixes the downscaled rendition format for both the
-- image and video-frame-grab paths at 400px/JPEG/quality 75 for
-- thumbnails and 1600px/quality 80 for the archived image rendition --
-- there is exactly one archive object per story regardless of
-- media_type, always a JPEG.
CREATE OR REPLACE FUNCTION public.story_archive_key(p_story_item_id uuid)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 'story-archive/' || p_story_item_id::text || '.jpg';
$$;

REVOKE ALL ON FUNCTION public.story_archive_key(uuid) FROM PUBLIC, anon;
-- Granted to authenticated too: it is a pure, harmless derivation (no
-- table access, IMMUTABLE, takes only a uuid the caller already knows)
-- and Task 9's worker or future client code may reasonably want to
-- compute the same key without a definer escalation. Matches
-- story_intent_error/story_intent_max_bytes' "small pure helper, granted
-- broadly" precedent from Task 4 rather than bump_story_signal's
-- "mutates shared state, kept narrow" one -- this function mutates
-- nothing.
GRANT EXECUTE ON FUNCTION public.story_archive_key(uuid) TO authenticated;

-- The archive rendition is a live object THIS TTL after it is minted
-- into a signed URL a player may be holding -- see the queue_story_
-- media_deletion call below and process-chat-media's own
-- _signedUrlTtl precedent (§4.1, §4.4). Named so both the RPC below and
-- Task 9's worker use the identical bound rather than two copies of the
-- literal 600.
CREATE OR REPLACE FUNCTION public.story_archive_ttl_seconds()
RETURNS int
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 600;
$$;

REVOKE ALL ON FUNCTION public.story_archive_ttl_seconds() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.story_archive_ttl_seconds() TO authenticated;

-- ---------------------------------------------------------------------
-- delete_story_item(p_story_item_id uuid) RETURNS jsonb
--
-- Spec §3.3 / §4.5. Row-locks the story, verifies AUTHORSHIP (not
-- membership -- §3.3's whole point: an author never loses the right to
-- remove their own retained media, even from an ENDED relationship, so
-- this deliberately does NOT call story_relationship_is_open), stamps
-- deleted_at, and enqueues THREE keys -- media, thumbnail, and the
-- deterministic archive key -- in the SAME transaction, so a tombstone
-- can never exist without its cleanup work.
--
-- Idempotent (brief contract 4, spec §4.5): calling this twice returns
-- success both times and RE-ARMS an already-completed queue entry
-- (deleted_at set back to NULL) via queue_story_media_deletion's
-- ON CONFLICT DO UPDATE, rather than silently doing nothing on the
-- second call or inserting a duplicate row against the queue's
-- UNIQUE (bucket_id, object_name).
--
-- The archive key's queue entry alone carries not_before >=
-- now() + 600s (story_archive_ttl_seconds()) -- the signed-URL TTL
-- (§4.1/§4.4): deleting the rendition a live player just got a fresh
-- URL for would break playback mid-stream. media_key and
-- thumbnail_key do NOT need the delay: by the time delete_story_item
-- runs, deleted_at is about to be stamped in this same transaction, so
-- the storage SELECT policy (which requires deleted_at IS NULL) starts
-- refusing new reads of those two keys immediately -- the same bounded
-- window §4.5 already accepts for any already-issued URL. The archive
-- key is different only because Task 9's worker may have handed out a
-- signed URL to that key moments before this call, with no story-row
-- gate in between (the archive object's storage policy, once Task 9
-- adds one, cannot re-check deleted_at after the URL is already signed
-- any more than the media/thumbnail case can) -- enqueueing it is safe
-- even when the object does not exist yet (a nonexistent-key Storage
-- delete is a no-op), and the delay is what closes the delete/worker
-- race described in §4.5's last two paragraphs.
--
-- Same house error shape as the rest of this feature
-- (story_intent_error) would normally apply, but per spec §3.3 "Missing,
-- not a member, ended relationship, and deleted all return the same
-- unavailable result" is about READ/membership paths; delete's own
-- authorship check has exactly one refusal condition (not the author),
-- so it reuses story_intent_error('UNAVAILABLE') for that single
-- failure mode too -- "missing" and "someone else's story" are
-- indistinguishable to the caller either way, never an existence
-- oracle for a story_item_id the caller does not own.
CREATE OR REPLACE FUNCTION public.delete_story_item(
  p_story_item_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user  uuid := auth.uid();
  v_story public.story_items%ROWTYPE;
  v_not_before timestamptz;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.story_intent_error('UNAUTHORIZED');
  END IF;

  IF p_story_item_id IS NULL THEN
    RETURN public.story_intent_error('INVALID_INPUT');
  END IF;

  -- Row-lock so a concurrent delete/view/finalize cannot interleave
  -- with the authorship check and the stamp below.
  SELECT * INTO v_story
    FROM public.story_items
   WHERE id = p_story_item_id
   FOR UPDATE;

  -- AUTHORSHIP, not membership. Deliberately no
  -- story_relationship_is_open call anywhere in this function: per
  -- §3.3, deletion does not require the relationship still be active.
  -- "Missing" and "someone else's story" fall through the same branch
  -- to the same result -- never an existence oracle.
  IF v_story.id IS NULL
     OR v_story.author_id IS DISTINCT FROM v_user
  THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;

  -- Idempotent stamp: only move deleted_at forward on the FIRST
  -- delete. A second call must not re-stamp (would report a later
  -- deleted_at than the true first deletion) but must still fall
  -- through to re-arm the queue below and return success either way.
  UPDATE public.story_items
     SET deleted_at = now()
   WHERE id = p_story_item_id
     AND deleted_at IS NULL;

  -- Enqueue THREE keys in this SAME transaction -- media, thumbnail,
  -- and the deterministic archive key -- so the tombstone above can
  -- never commit without its cleanup work. Re-arming (ON CONFLICT DO
  -- UPDATE inside queue_story_media_deletion) makes this safe to call
  -- again on an already-deleted story: brief contract 4.
  PERFORM public.queue_story_media_deletion('story-media', v_story.media_key);
  PERFORM public.queue_story_media_deletion('story-media', v_story.thumbnail_key);

  -- Archive key: safe to enqueue even when it does not exist yet
  -- (closes the delete/worker race, §4.5) -- but delayed by at least
  -- the signed-URL TTL, because this is the one key a player may have
  -- just been handed a fresh URL for.
  v_not_before := now() + make_interval(secs => public.story_archive_ttl_seconds());
  PERFORM public.queue_story_media_deletion(
    'story-media',
    public.story_archive_key(p_story_item_id),
    v_not_before
  );

  PERFORM public.bump_story_signal(v_story.relationship_id);

  RETURN jsonb_build_object('error', false, 'deleted', true);
END;
$$;

REVOKE ALL ON FUNCTION public.delete_story_item(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_story_item(uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- Hard-delete cascade trigger.
--
-- ON DELETE CASCADE on story_items.relationship_id (20260938010000)
-- removes every story row when a relationship is hard-deleted, but a
-- cascade never calls delete_story_item -- it is a row removal, not an
-- RPC invocation. Without this trigger, a hard-deleted relationship's
-- story media/thumbnails/archive renditions would leak in the bucket
-- forever with no row left to enqueue them from.
--
-- BEFORE DELETE on story_items itself (not a trigger on relationships)
-- so this fires for every row-level cause of a story_items row
-- disappearing via cascade -- relationship deletion, account deletion
-- (auth.users -> relationships.user_a/user_b -> ... eventually cascades
-- here too), or privileged maintenance -- without needing a separate
-- trigger per upstream table, per spec §4.5's closing paragraph.
--
-- Deliberately does NOT skip rows that are already deleted_at-stamped:
-- a soft-deleted story that gets hard-deleted still needs its keys
-- re-armed exactly like delete_story_item's own idempotent path, for
-- the identical race (§4.5's re-arming upsert plus the unique
-- (bucket_id, object_name) constraint "make this safe beside the
-- soft-delete path and an in-flight worker").
--
-- SECURITY DEFINER is irrelevant for a trigger function (it runs as
-- whatever role performs the DELETE, but the queue helper it calls is
-- itself SECURITY DEFINER, so privilege is not the gate here); what
-- matters is that this only ever fires server-side, since no client
-- role has DELETE on story_items or relationships in the first place.
CREATE OR REPLACE FUNCTION public.stories_enqueue_media_on_hard_delete()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  PERFORM public.queue_story_media_deletion('story-media', OLD.media_key);
  PERFORM public.queue_story_media_deletion('story-media', OLD.thumbnail_key);
  PERFORM public.queue_story_media_deletion(
    'story-media',
    public.story_archive_key(OLD.id),
    now() + make_interval(secs => public.story_archive_ttl_seconds())
  );
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS stories_enqueue_media_before_hard_delete
  ON public.story_items;
CREATE TRIGGER stories_enqueue_media_before_hard_delete
  BEFORE DELETE ON public.story_items
  FOR EACH ROW
  EXECUTE FUNCTION public.stories_enqueue_media_on_hard_delete();
