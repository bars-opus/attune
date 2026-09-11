-- Stories: a soft-deleted image story must not dead-letter its own
-- archival job. FINAL WHOLE-BRANCH REVIEW, finding I1 (Important).
--
-- THE BUG: claim_story_archival_batch (20260938090000, around line
-- 349) selects purely from story_media_processing_outbox -- it never
-- joins story_items and never checks deleted_at. delete_story_item
-- (20260938070000) stamps deleted_at and enqueues media_key for
-- physical deletion with not_before = now(), but leaves the outbox
-- row completely untouched: that file contains zero references to
-- story_media_processing_outbox.
--
-- THE SEQUENCE, for an ordinary user action:
--   1. Author posts an image story -> outbox row 'pending',
--      available_at = expires_at (+24h).
--   2. Author deletes it an hour later -> deleted_at stamped,
--      media_key enqueued with not_before = now() (undelayed).
--   3. The deletion drain physically removes the source object.
--   4. 23h later available_at passes; claim_story_archival_batch
--      picks the row up regardless of the story being deleted.
--   5. The worker tries to download source_key -- gone -- throws;
--      fail_story_archival runs -> attempts=1, state back to 'pending'.
--   6. Repeats hourly until attempts=5 -> state='dead_letter'.
--
-- CONSEQUENCE: every image story deleted before its 24h mark produces
-- a dead-lettered job plus five wasted Storage round-trips. Spec §4.4
-- names dead_letter + last_error_code as the operational alert
-- surface, so the alert channel fills with noise from ordinary
-- deletions and is useless for detecting real failures from day one.
-- Not data loss -- an observability bug that makes this branch's own
-- alerting worthless.
--
-- THE FIX (specified, not the rejected alternative): have
-- delete_story_item mark the outbox row terminal (state='done',
-- completed_at=now()) in the SAME transaction as the tombstone --
-- that transaction already owns the fact, and it matches the
-- "tombstone and its cleanup work commit together" contract the
-- delete RPC was built around. Deliberately NOT a deleted_at check
-- added to claim_story_archival_batch's WHERE clause instead: that
-- alternative was considered and rejected because it leaves the
-- outbox row stuck at state='pending' forever with no terminal state
-- -- an eternally-pending row that never claims and never resolves is
-- its own (quieter, but permanent) mess, not a fix.
--
-- WHY A NEW MIGRATION rather than editing 20260938070000: this
-- branch's convention throughout has been that fixes land as new
-- migrations layered on top of the shipped file -- 20260938100000,
-- 20260938110000, 20260938120000, and 20260938130000 all did exactly
-- this rather than rewriting an already-shipped migration in place.
-- CREATE OR REPLACE is used here, as it was in all four of those, to
-- redefine delete_story_item's body with the fix applied. The body
-- below is copied verbatim from 20260938070000 with exactly one
-- statement added -- the outbox UPDATE -- placed AFTER the existing
-- three queue_story_media_deletion enqueues and BEFORE
-- bump_story_signal, matching the reviewer's specified placement.
-- Nothing else is reordered.
--
-- THE HARD-DELETE PATH NEEDS NOTHING: story_media_processing_outbox's
-- story_item_id column is declared
-- `REFERENCES public.story_items(id) ON DELETE CASCADE` (20260938090000).
-- A hard-deleted story_items row (the cascade trigger
-- stories_enqueue_media_on_hard_delete already re-arms its storage
-- keys) is removed by Postgres's own FK cascade, which takes the
-- outbox row with it automatically -- there is no dead-letter risk on
-- that path because there is no outbox row left to claim at all.
-- Verified by inspection of the CREATE TABLE in 20260938090000; no
-- change needed here.
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

  -- FIX (I1): terminate this story's outbox row in the SAME
  -- transaction as the tombstone above, so a soft-deleted image story
  -- can never again be claimed by claim_story_archival_batch. state
  -- = 'done' (not a new state) is deliberate: 'done' already means
  -- "never claim this again" to claim_story_archival_batch's WHERE
  -- clause (state IN ('pending','processing') only) and to
  -- complete_story_archival's own successful-swap terminal state --
  -- reusing it means no other function needs to learn a new state
  -- value. Unconditional (no WHERE state <> 'done' guard) and safe to
  -- run on every call including re-deletes and stories with no outbox
  -- row at all (a video story, or a race with an already-completed
  -- archive swap): the UPDATE simply matches zero rows in those cases,
  -- exactly like queue_story_media_deletion's own no-op-when-absent
  -- posture. completed_at is set here as well as state, matching
  -- complete_story_archival's own successful-terminal shape, so a
  -- reader cannot see state='done' with completed_at still NULL from
  -- either path.
  UPDATE public.story_media_processing_outbox
     SET state = 'done',
         completed_at = now(),
         updated_at = now()
   WHERE story_item_id = p_story_item_id;

  PERFORM public.bump_story_signal(v_story.relationship_id);

  RETURN jsonb_build_object('error', false, 'deleted', true);
END;
$$;

REVOKE ALL ON FUNCTION public.delete_story_item(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_story_item(uuid) TO authenticated;

-- ===========================================================================
-- M2 (Minor, optional) -- storage SELECT policy asymmetry.
--
-- 20260938030000's INSERT policy (story_media_insert_by_intent) checks
-- both `used_at IS NULL` AND `expires_at > now()` on the owning
-- intent. The SELECT policy's second branch (the "verify my own
-- upload landed" branch, story_media_select_authorized) checks only
-- `used_at IS NULL`, omitting the expiry check the INSERT policy
-- directly above it enforces. Net effect: an uploader can keep
-- reading its own orphaned, never-finalized object for as long as the
-- intent row survives -- up to the hourly cleanup sweep prunes it,
-- per §4.2 -- rather than being cut off the instant the intent
-- expires. Own object, own upload, no cross-user exposure; this is a
-- symmetry fix, not a hole being closed for anyone but the uploader
-- themselves reading slightly longer than intended.
--
-- Fixed for symmetry with the INSERT policy directly above it, in
-- this same migration, by DROP + CREATE (Postgres has no
-- CREATE OR REPLACE POLICY) of story_media_select_authorized with the
-- identical `expires_at > now()` clause added to its second EXISTS
-- branch. The first branch (live story, open relationship) is
-- untouched.
-- ===========================================================================
DROP POLICY IF EXISTS story_media_select_authorized ON storage.objects;
CREATE POLICY story_media_select_authorized
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'story-media'
  AND (
    EXISTS (
      SELECT 1
      FROM public.story_items si
      WHERE (si.media_key = name OR si.thumbnail_key = name)
        AND si.deleted_at IS NULL
        AND public.story_relationship_is_open(si.relationship_id, auth.uid())
    )
    OR EXISTS (
      SELECT 1
      FROM public.story_media_upload_intents intent
      WHERE intent.storage_key = name
        AND intent.requester_id = auth.uid()
        AND intent.used_at IS NULL
        AND intent.expires_at > now()
    )
  )
);
