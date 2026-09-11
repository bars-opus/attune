-- Stories: maintenance contracts (Task 9, spec §4.2 and §4.4).
--
-- cleanup_expired_story_media_intents(), claim_story_archival_batch(),
-- complete_story_archival(), and fail_story_archival() (fix round 1)
-- are all service_role-only -- no client ever calls them -- so this
-- file's "attack" framing from the other
-- story test files does not apply the same way. What DOES apply with
-- full force is the CONCURRENCY correctness the brief calls out as the
-- trickiest logic in this plan: a hole here is not a bad row, it's an
-- object silently deleted out from under a live player, or an object
-- leaked forever because nothing ever re-enqueues it.
--
-- House rule, applied throughout this file (same idiom as
-- story_rpc_contracts.sql's header): every comparison of a
-- jsonb-extracted value uses IS DISTINCT FROM / IS NOT DISTINCT FROM,
-- never a bare = or <>. A bare comparison against NULL evaluates to
-- NULL, not true, so an IF built on one silently never fires and the
-- RAISE EXCEPTION it guards never runs -- a vacuous assertion that
-- passes while checking nothing. count(*) is the one exception: it can
-- never be NULL, so a bare = or <> against a count is correct and used
-- throughout.
--
-- Grants: service_role only. This suite runs as the table owner
-- (superuser in the local harness), which already has every privilege,
-- so grant checks here assert the NEGATIVE -- authenticated and anon
-- must NOT be able to execute any of the three -- rather than a
-- positive "service_role can," which the harness cannot meaningfully
-- exercise without actually connecting as that role.
--
-- FIX ROUND 1 (spec §4.4's story_media_processing_outbox table):
-- adds fixtures and contracts for the outbox itself -- an image
-- finalize seeds exactly one row, a video finalize seeds none, five
-- failed attempts dead-letter a row so it is never claimed again, and
-- authenticated/anon have zero table privilege on it (same
-- has_table_privilege idiom story_security_contracts.sql uses for
-- story_views / story_media_upload_intents).

BEGIN;

INSERT INTO auth.users(id) VALUES
  ('00000000-0000-0000-0000-00000000e601'::uuid),
  ('00000000-0000-0000-0000-00000000e602'::uuid) ON CONFLICT DO NOTHING;

INSERT INTO public.users(id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-00000000e601'::uuid, '+15551110001', 'MC1'),
  ('00000000-0000-0000-0000-00000000e602'::uuid, '+15551110002', 'MC2')
  ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------
-- Grants: anon and authenticated must not reach any of the three.
-- ---------------------------------------------------------------------
DO $$ BEGIN
  IF has_function_privilege('anon',
    'public.cleanup_expired_story_media_intents()', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon can execute cleanup_expired_story_media_intents';
  END IF;
  IF has_function_privilege('authenticated',
    'public.cleanup_expired_story_media_intents()', 'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated can execute cleanup_expired_story_media_intents';
  END IF;
  IF NOT has_function_privilege('service_role',
    'public.cleanup_expired_story_media_intents()', 'EXECUTE') THEN
    RAISE EXCEPTION 'service_role cannot execute cleanup_expired_story_media_intents';
  END IF;

  IF has_function_privilege('anon',
    'public.claim_story_archival_batch(int)', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon can execute claim_story_archival_batch';
  END IF;
  IF has_function_privilege('authenticated',
    'public.claim_story_archival_batch(int)', 'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated can execute claim_story_archival_batch';
  END IF;
  IF NOT has_function_privilege('service_role',
    'public.claim_story_archival_batch(int)', 'EXECUTE') THEN
    RAISE EXCEPTION 'service_role cannot execute claim_story_archival_batch';
  END IF;

  IF has_function_privilege('anon',
    'public.complete_story_archival(uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon can execute complete_story_archival';
  END IF;
  IF has_function_privilege('authenticated',
    'public.complete_story_archival(uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated can execute complete_story_archival';
  END IF;
  IF NOT has_function_privilege('service_role',
    'public.complete_story_archival(uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'service_role cannot execute complete_story_archival';
  END IF;

  IF has_function_privilege('anon',
    'public.fail_story_archival(uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon can execute fail_story_archival';
  END IF;
  IF has_function_privilege('authenticated',
    'public.fail_story_archival(uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated can execute fail_story_archival';
  END IF;
  IF NOT has_function_privilege('service_role',
    'public.fail_story_archival(uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'service_role cannot execute fail_story_archival';
  END IF;

  -- =====================================================================
  -- The table itself: authenticated/anon must have ZERO privilege on
  -- story_media_processing_outbox, same has_table_privilege idiom
  -- story_security_contracts.sql uses for story_views /
  -- story_media_upload_intents. This is the exact hole that bit
  -- Task 2 if the table-grants replay (20260938100000) is skipped.
  -- =====================================================================
  IF has_table_privilege('authenticated',
    'public.story_media_processing_outbox', 'SELECT') THEN
    RAISE EXCEPTION
      'EXPLOIT: authenticated can SELECT story_media_processing_outbox';
  END IF;
  IF has_table_privilege('authenticated',
    'public.story_media_processing_outbox', 'INSERT') THEN
    RAISE EXCEPTION
      'EXPLOIT: authenticated can INSERT story_media_processing_outbox';
  END IF;
  IF has_table_privilege('authenticated',
    'public.story_media_processing_outbox', 'UPDATE') THEN
    RAISE EXCEPTION
      'EXPLOIT: authenticated can UPDATE story_media_processing_outbox '
      '-- a client could forge state = ''done'' or dead-letter its own job';
  END IF;
  IF has_table_privilege('authenticated',
    'public.story_media_processing_outbox', 'DELETE') THEN
    RAISE EXCEPTION
      'EXPLOIT: authenticated can DELETE story_media_processing_outbox';
  END IF;
  IF has_table_privilege('anon',
    'public.story_media_processing_outbox', 'SELECT') THEN
    RAISE EXCEPTION
      'EXPLOIT: anon can SELECT story_media_processing_outbox';
  END IF;
END $$;

DO $$
DECLARE
  v_rel uuid;
  v_intent_id uuid;
  v_intent_key text := 'story-media/mc/unused-expired';
  v_used_intent_id uuid;
  v_used_key text := 'story-media/mc/used-finalized';
  v_count int;
  v_queued_at timestamptz;
  v_story_a uuid;
  v_story_b uuid;
  v_story_c uuid;
  v_media_a text := 'story-media/mc/story-a-media';
  v_media_b text := 'story-media/mc/story-b-media';
  v_media_c text := 'story-media/mc/story-c-media';
  v_batch record;
  v_batch_count int;
  v_new_key_a text;
  v_res jsonb;
  v_deleted_row_count int;
  v_outbox_state text;
  v_outbox_available_at timestamptz;
  v_outbox_attempts int;
BEGIN
  RESET ROLE;

  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES ('00000000-0000-0000-0000-00000000e601'::uuid,
          '00000000-0000-0000-0000-00000000e602'::uuid, 'active')
  RETURNING id INTO v_rel;

  -- =================================================================
  -- CONTRACT 1: cleanup enqueues an expired, unused intent's key and
  -- stamps cleanup_queued_at; a SECOND run does not re-arm the key.
  -- =================================================================
  INSERT INTO public.story_media_upload_intents(
    id, relationship_id, requester_id, object_kind, media_type,
    mime_type, storage_key, max_bytes, expires_at
  ) VALUES (
    gen_random_uuid(), v_rel,
    '00000000-0000-0000-0000-00000000e601'::uuid, 'media', 'image',
    'image/jpeg', v_intent_key, 5242880, now() - interval '1 hour'
  ) RETURNING id INTO v_intent_id;

  PERFORM public.cleanup_expired_story_media_intents();

  SELECT cleanup_queued_at INTO v_queued_at
    FROM public.story_media_upload_intents WHERE id = v_intent_id;
  IF v_queued_at IS NULL THEN
    RAISE EXCEPTION
      'cleanup did not stamp cleanup_queued_at on an expired unused intent';
  END IF;

  SELECT count(*) INTO v_count FROM public.media_deletion_queue
   WHERE bucket_id = 'story-media' AND object_name = v_intent_key
     AND deleted_at IS NULL;
  IF v_count <> 1 THEN
    RAISE EXCEPTION
      'cleanup did not enqueue the expired unused intent key (got %)', v_count;
  END IF;

  -- Simulate the drain: mark the queue row deleted, as
  -- process-media-deletion-queue would after physically removing it.
  UPDATE public.media_deletion_queue
     SET deleted_at = now()
   WHERE bucket_id = 'story-media' AND object_name = v_intent_key;

  -- Second run: cleanup_queued_at is already set, so the row no longer
  -- matches the sweep's WHERE clause at all -- it must NOT be re-armed
  -- (re-inserted/re-armed in the queue) a second time.
  PERFORM public.cleanup_expired_story_media_intents();

  SELECT count(*) INTO v_count FROM public.media_deletion_queue
   WHERE bucket_id = 'story-media' AND object_name = v_intent_key
     AND deleted_at IS NULL;
  IF v_count <> 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: a second cleanup run re-armed an already-queued key '
      '(got % un-deleted rows; the stamp exists specifically to prevent this)',
      v_count;
  END IF;

  -- =================================================================
  -- CONTRACT 2: cleanup NEVER touches a used intent's finalized object.
  -- =================================================================
  INSERT INTO public.story_media_upload_intents(
    id, relationship_id, requester_id, object_kind, media_type,
    mime_type, storage_key, max_bytes, expires_at, used_at
  ) VALUES (
    gen_random_uuid(), v_rel,
    '00000000-0000-0000-0000-00000000e601'::uuid, 'media', 'image',
    'image/jpeg', v_used_key, 5242880, now() - interval '1 hour', now()
  ) RETURNING id INTO v_used_intent_id;

  PERFORM public.cleanup_expired_story_media_intents();

  SELECT count(*) INTO v_count FROM public.media_deletion_queue
   WHERE bucket_id = 'story-media' AND object_name = v_used_key;
  IF v_count <> 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: cleanup enqueued a USED intent''s finalized object (got %)',
      v_count;
  END IF;

  -- Age used_at past the 24h prune window and confirm the row is
  -- pruned WITHOUT ever having touched media_deletion_queue.
  UPDATE public.story_media_upload_intents
     SET used_at = now() - interval '25 hours'
   WHERE id = v_used_intent_id;

  PERFORM public.cleanup_expired_story_media_intents();

  SELECT count(*) INTO v_count FROM public.story_media_upload_intents
   WHERE id = v_used_intent_id;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'a used intent 25h past used_at was not pruned';
  END IF;

  SELECT count(*) INTO v_count FROM public.media_deletion_queue
   WHERE bucket_id = 'story-media' AND object_name = v_used_key;
  IF v_count <> 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: pruning a used intent enqueued its finalized object (got %)',
      v_count;
  END IF;

  -- Confirm the unused intent from contract 1 is ALSO pruned 24h after
  -- its cleanup_queued_at stamp (not immediately, and not never).
  SELECT count(*) INTO v_count FROM public.story_media_upload_intents
   WHERE id = v_intent_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION
      'the unused intent was pruned before 24h past its cleanup stamp';
  END IF;

  UPDATE public.story_media_upload_intents
     SET cleanup_queued_at = now() - interval '25 hours'
   WHERE id = v_intent_id;

  PERFORM public.cleanup_expired_story_media_intents();

  SELECT count(*) INTO v_count FROM public.story_media_upload_intents
   WHERE id = v_intent_id;
  IF v_count <> 0 THEN
    RAISE EXCEPTION
      'an unused intent 25h past its cleanup_queued_at stamp was not pruned';
  END IF;

  -- =================================================================
  -- Fixtures for archival contracts: three EXPIRED image stories
  -- (created_at/expires_at satisfy story_expires_in_24h) belonging to
  -- v_rel, not deleted, not yet downscaled.
  -- =================================================================
  INSERT INTO public.story_items(
    id, client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height,
    occurred_on, created_at, expires_at
  ) VALUES (
    gen_random_uuid(), gen_random_uuid(), v_rel,
    '00000000-0000-0000-0000-00000000e601'::uuid, 'image',
    v_media_a, 'story-media/mc/story-a-thumb', 1080, 1920,
    (now() - interval '30 hours')::date,
    now() - interval '30 hours', now() - interval '6 hours'
  ) RETURNING id INTO v_story_a;

  -- =================================================================
  -- FIX ROUND 1, NEW CONTRACT: an image finalize creates exactly one
  -- outbox row with available_at = the story's expires_at; a video
  -- finalize creates none. Fixture inserts bypass create_story_item
  -- (Task 5's own concern), but the AFTER INSERT trigger
  -- (stories_seed_processing_outbox_after_insert) fires on ANY
  -- story_items insert regardless of path -- which is the point: it
  -- is not create_story_item-specific.
  -- =================================================================
  SELECT count(*) INTO v_count FROM public.story_media_processing_outbox
   WHERE story_item_id = v_story_a;
  IF v_count <> 1 THEN
    RAISE EXCEPTION
      'an image story insert did not seed exactly one outbox row (got %)',
      v_count;
  END IF;

  SELECT state, available_at, attempts
    INTO v_outbox_state, v_outbox_available_at, v_outbox_attempts
    FROM public.story_media_processing_outbox
   WHERE story_item_id = v_story_a;
  IF v_outbox_state IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION
      'a freshly seeded outbox row should start pending, got %', v_outbox_state;
  END IF;
  IF v_outbox_available_at IS DISTINCT FROM (
       SELECT expires_at FROM public.story_items WHERE id = v_story_a
     ) THEN
    RAISE EXCEPTION
      'EXPLOIT: outbox available_at (%) does not equal the story''s '
      'expires_at -- spec §4.4 requires available_at = expires_at',
      v_outbox_available_at;
  END IF;
  IF v_outbox_attempts <> 0 THEN
    RAISE EXCEPTION 'a freshly seeded outbox row should have 0 attempts';
  END IF;

  -- Video finalize: NO outbox row at all ("videos get no processing
  -- row", §4.4).
  DECLARE
    v_video_fixture_id uuid;
  BEGIN
    INSERT INTO public.story_items(
      id, client_story_id, relationship_id, author_id, media_type,
      media_key, thumbnail_key, media_width, media_height, duration_ms,
      occurred_on, created_at, expires_at
    ) VALUES (
      gen_random_uuid(), gen_random_uuid(), v_rel,
      '00000000-0000-0000-0000-00000000e601'::uuid, 'video',
      'story-media/mc/video-seed-media', 'story-media/mc/video-seed-thumb',
      1080, 1920, 5000,
      (now() - interval '2 hours')::date,
      now() - interval '2 hours', now() + interval '22 hours'
    ) RETURNING id INTO v_video_fixture_id;

    SELECT count(*) INTO v_count FROM public.story_media_processing_outbox
     WHERE story_item_id = v_video_fixture_id;
    IF v_count <> 0 THEN
      RAISE EXCEPTION
        'EXPLOIT: a video story insert seeded an outbox row (got %) -- '
        'spec §4.4: "videos get no processing row"', v_count;
    END IF;
  END;

  INSERT INTO public.story_items(
    id, client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height,
    occurred_on, created_at, expires_at
  ) VALUES (
    gen_random_uuid(), gen_random_uuid(), v_rel,
    '00000000-0000-0000-0000-00000000e601'::uuid, 'image',
    v_media_b, 'story-media/mc/story-b-thumb', 1080, 1920,
    (now() - interval '30 hours')::date,
    now() - interval '30 hours', now() - interval '6 hours'
  ) RETURNING id INTO v_story_b;

  INSERT INTO public.story_items(
    id, client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height,
    occurred_on, created_at, expires_at
  ) VALUES (
    gen_random_uuid(), gen_random_uuid(), v_rel,
    '00000000-0000-0000-0000-00000000e601'::uuid, 'image',
    v_media_c, 'story-media/mc/story-c-thumb', 1080, 1920,
    (now() - interval '30 hours')::date,
    now() - interval '30 hours', now() - interval '6 hours'
  ) RETURNING id INTO v_story_c;

  -- =================================================================
  -- CONTRACT 3: claim_story_archival_batch leases rows so two
  -- concurrent runs cannot claim the same story.
  --
  -- A single-connection SQL suite cannot literally run two workers at
  -- once (Task 11 adds the real two-connection race per the brief), so
  -- this proves the LEASE PREDICATE instead: claim once (leasing
  -- stories a/b/c into 'processing'), then claim AGAIN in the SAME
  -- transaction while that same lease is still fresh. The second claim
  -- must return ZERO of the rows the first claim already holds -- that
  -- is exactly the condition FOR UPDATE SKIP LOCKED plus the
  -- outbox's own state='processing'/processing_started_at freshness
  -- check is supposed to guarantee, and it is what a second, truly
  -- concurrent worker would also observe.
  -- =================================================================
  SELECT count(*) INTO v_batch_count
    FROM public.claim_story_archival_batch(10) b
   WHERE b.story_id IN (v_story_a, v_story_b, v_story_c);
  IF v_batch_count <> 3 THEN
    RAISE EXCEPTION
      'first claim did not lease all 3 eligible stories (got %)', v_batch_count;
  END IF;

  SELECT state, processing_started_at, attempts
    INTO v_outbox_state, v_outbox_available_at, v_outbox_attempts
    FROM public.story_media_processing_outbox WHERE story_item_id = v_story_a;
  IF v_outbox_state IS DISTINCT FROM 'processing' THEN
    RAISE EXCEPTION
      'claim did not move story_a''s outbox row to processing (got %)',
      v_outbox_state;
  END IF;
  IF v_outbox_available_at IS NULL THEN
    RAISE EXCEPTION 'claim did not stamp processing_started_at on story_a';
  END IF;
  IF v_outbox_attempts <> 1 THEN
    RAISE EXCEPTION
      'claim should increment attempts to 1 on the first claim, got %',
      v_outbox_attempts;
  END IF;

  -- Second claim, same transaction, lease still fresh (well under the
  -- 5-minute timeout): must return NONE of a/b/c.
  SELECT count(*) INTO v_batch_count
    FROM public.claim_story_archival_batch(10) b
   WHERE b.story_id IN (v_story_a, v_story_b, v_story_c);
  IF v_batch_count <> 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: a second claim leased an already-leased story '
      '(got % rows; the lease predicate did not exclude them)',
      v_batch_count;
  END IF;

  -- =================================================================
  -- CONTRACT 4: a stale lease is reclaimable after its timeout.
  -- =================================================================
  UPDATE public.story_media_processing_outbox
     SET processing_started_at = now() - interval '10 minutes'
   WHERE story_item_id = v_story_b;

  SELECT count(*) INTO v_batch_count
    FROM public.claim_story_archival_batch(10) b
   WHERE b.story_id = v_story_b;
  IF v_batch_count <> 1 THEN
    RAISE EXCEPTION
      'a stale (10-minute) lease on story_b was not reclaimed by a new claim '
      '(a crashed worker would park this row forever)';
  END IF;

  SELECT attempts INTO v_outbox_attempts
    FROM public.story_media_processing_outbox WHERE story_item_id = v_story_b;
  IF v_outbox_attempts <> 2 THEN
    RAISE EXCEPTION
      'reclaiming story_b''s stale lease should bring attempts to 2, got %',
      v_outbox_attempts;
  END IF;

  -- story_a's fresh lease (from the first claim above) must still be
  -- untouched by that same reclaim pass.
  SELECT count(*) INTO v_batch_count
    FROM public.claim_story_archival_batch(10) b
   WHERE b.story_id = v_story_a;
  IF v_batch_count <> 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: reclaiming a stale lease also re-leased a still-fresh one';
  END IF;

  -- =================================================================
  -- FIX ROUND 1, NEW CONTRACT: five failed attempts dead-letter the
  -- row and it is no longer claimed. story_b is already at attempts=2,
  -- state='processing' (claimed twice above, in contracts 3 and 4).
  -- attempts only increments on CLAIM, not on fail_story_archival
  -- itself -- fail just records the outcome of an attempt claim
  -- already counted -- so each of the 3 remaining attempts needed to
  -- reach 5 is one claim+fail cycle: fail (below threshold) resets to
  -- 'pending' so the very next claim can pick it straight back up
  -- without waiting out the stale-processing timeout.
  -- =================================================================
  PERFORM public.fail_story_archival(v_story_b, 'TRANSFORM_FAILED'); -- still 2, back to pending
  PERFORM public.claim_story_archival_batch(10);                      -- -> 3, processing
  PERFORM public.fail_story_archival(v_story_b, 'TRANSFORM_FAILED'); -- still 3, back to pending
  PERFORM public.claim_story_archival_batch(10);                      -- -> 4, processing
  PERFORM public.fail_story_archival(v_story_b, 'TRANSFORM_FAILED'); -- still 4, back to pending
  PERFORM public.claim_story_archival_batch(10);                      -- -> 5, processing
  v_res := public.fail_story_archival(v_story_b, 'TRANSFORM_FAILED'); -- still 5, NOW dead_letter

  SELECT state, attempts INTO v_outbox_state, v_outbox_attempts
    FROM public.story_media_processing_outbox WHERE story_item_id = v_story_b;
  IF v_outbox_attempts <> 5 THEN
    RAISE EXCEPTION
      'expected story_b to be at 5 attempts after this sequence, got %',
      v_outbox_attempts;
  END IF;
  IF v_outbox_state IS DISTINCT FROM 'dead_letter' THEN
    RAISE EXCEPTION
      'EXPLOIT: story_b should be dead_letter at 5 attempts, got %',
      v_outbox_state;
  END IF;
  IF (v_res->>'dead_letter') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION
      'fail_story_archival did not report dead_letter=true on the '
      '5th failure: %', v_res;
  END IF;

  -- Age processing_started_at (there is none -- state is dead_letter,
  -- not processing) is irrelevant: dead_letter simply never matches
  -- claim's WHERE clause (state IN ('pending','processing') only,
  -- implicitly -- dead_letter/done are excluded). Prove it directly:
  -- even a generous batch size must never return story_b again.
  SELECT count(*) INTO v_batch_count
    FROM public.claim_story_archival_batch(200) b
   WHERE b.story_id = v_story_b;
  IF v_batch_count <> 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: claim_story_archival_batch returned a dead_letter row '
      '(got % rows for story_b, which has 5 failed attempts)', v_batch_count;
  END IF;

  -- =================================================================
  -- CONTRACT 5: complete_story_archival on a story deleted mid-flight
  -- enqueues the newly produced object rather than orphaning it.
  --
  -- Simulates the worker having already uploaded the new rendition
  -- (the deterministic archive key) BEFORE calling complete_story_
  -- archival -- exactly the ordering §4.4 requires -- and the story
  -- having been deleted by its author in the window between the claim
  -- and this call.
  -- =================================================================
  v_new_key_a := public.story_archive_key(v_story_a);

  UPDATE public.story_items SET deleted_at = now() WHERE id = v_story_a;

  v_res := public.complete_story_archival(v_story_a, v_new_key_a);

  IF (v_res->>'swapped') IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION
      'complete_story_archival on a deleted story should report swapped=false: %',
      v_res;
  END IF;

  -- media_key on the (now-deleted) story must be UNCHANGED -- the swap
  -- must not have happened.
  SELECT count(*) INTO v_count FROM public.story_items
   WHERE id = v_story_a AND media_key = v_media_a;
  IF v_count <> 1 THEN
    RAISE EXCEPTION
      'EXPLOIT: complete_story_archival swapped the key on a deleted story';
  END IF;

  -- The newly produced object (the archive key the worker already
  -- uploaded) must be enqueued rather than orphaned.
  SELECT count(*) INTO v_count FROM public.media_deletion_queue
   WHERE bucket_id = 'story-media' AND object_name = v_new_key_a
     AND deleted_at IS NULL;
  IF v_count <> 1 THEN
    RAISE EXCEPTION
      'EXPLOIT: complete_story_archival on a deleted story left the newly '
      'produced object un-enqueued -- it is now orphaned (got %)', v_count;
  END IF;

  -- =================================================================
  -- CONTRACT 6: a successful swap enqueues the OLD key with
  -- not_before >= now() + 600s AND bumps the change signal.
  -- =================================================================
  SELECT version INTO v_count FROM public.story_change_signals
   WHERE relationship_id = v_rel;
  -- (v_count reused as a scratch int here for the pre-swap version;
  -- NULL is fine -- no signal row may exist yet for v_rel.)

  DECLARE
    v_new_key_c text := public.story_archive_key(v_story_c);
    v_version_before bigint;
    v_version_after bigint;
  BEGIN
    SELECT version INTO v_version_before FROM public.story_change_signals
     WHERE relationship_id = v_rel;

    v_res := public.complete_story_archival(v_story_c, v_new_key_c);

    IF (v_res->>'swapped') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION
        'a clean complete_story_archival call should report swapped=true: %',
        v_res;
    END IF;

    -- media_key swapped to the new archive key.
    SELECT count(*) INTO v_count FROM public.story_items
     WHERE id = v_story_c AND media_key = v_new_key_c AND downscaled_at IS NOT NULL;
    IF v_count <> 1 THEN
      RAISE EXCEPTION
        'complete_story_archival did not swap media_key/stamp downscaled_at on success';
    END IF;

    -- The outbox row is marked done on success.
    SELECT count(*) INTO v_count FROM public.story_media_processing_outbox
     WHERE story_item_id = v_story_c
       AND state = 'done' AND completed_at IS NOT NULL;
    IF v_count <> 1 THEN
      RAISE EXCEPTION
        'complete_story_archival did not mark the outbox row done on success';
    END IF;

    -- The OLD key (v_media_c) is enqueued, delayed >= 600s.
    SELECT count(*) INTO v_count FROM public.media_deletion_queue
     WHERE bucket_id = 'story-media' AND object_name = v_media_c
       AND deleted_at IS NULL
       AND not_before >= now() + interval '599 seconds';
    IF v_count <> 1 THEN
      RAISE EXCEPTION
        'EXPLOIT: the old rendition was not enqueued with a >= 600s delay '
        '-- a player holding a fresh signed URL could break mid-playback';
    END IF;

    -- The change signal was bumped.
    SELECT version INTO v_version_after FROM public.story_change_signals
     WHERE relationship_id = v_rel;
    IF v_version_after IS NULL
       OR (v_version_before IS NOT NULL AND v_version_after <= v_version_before)
    THEN
      RAISE EXCEPTION
        'EXPLOIT: a successful archive swap did not bump story_change_signals '
        '(before=%, after=%) -- a client holding the old key would never '
        'refetch before requesting its next signed URL',
        v_version_before, v_version_after;
    END IF;
  END;

  -- =================================================================
  -- Regression guard on this file's own fixtures: video rows are
  -- marked downscaled_at WITHOUT being leased or swapped (the
  -- images-only reality documented in the migration). Not one of the
  -- six numbered contracts, but load-bearing for the design choice.
  -- =================================================================
  DECLARE
    v_video_id uuid;
  BEGIN
    INSERT INTO public.story_items(
      id, client_story_id, relationship_id, author_id, media_type,
      media_key, thumbnail_key, media_width, media_height, duration_ms,
      occurred_on, created_at, expires_at
    ) VALUES (
      gen_random_uuid(), gen_random_uuid(), v_rel,
      '00000000-0000-0000-0000-00000000e601'::uuid, 'video',
      'story-media/mc/video-media', 'story-media/mc/video-thumb',
      1080, 1920, 5000,
      (now() - interval '30 hours')::date,
      now() - interval '30 hours', now() - interval '6 hours'
    ) RETURNING id INTO v_video_id;

    PERFORM public.claim_story_archival_batch(10);

    SELECT count(*) INTO v_count FROM public.story_items
     WHERE id = v_video_id
       AND downscaled_at IS NOT NULL
       AND media_key = 'story-media/mc/video-media';
    IF v_count <> 1 THEN
      RAISE EXCEPTION
        'a video row was not marked downscaled_at (or was re-keyed) '
        'by claim_story_archival_batch -- images-only archival is broken';
    END IF;

    -- And it never got an outbox row in the first place (proved again
    -- here with claim already having run, to confirm claim itself
    -- never seeds one for video -- only the AFTER INSERT trigger could
    -- have, and it deliberately does not for media_type = 'video').
    SELECT count(*) INTO v_count FROM public.story_media_processing_outbox
     WHERE story_item_id = v_video_id;
    IF v_count <> 0 THEN
      RAISE EXCEPTION
        'EXPLOIT: a video row has an outbox entry (got %)', v_count;
    END IF;
  END;

  RAISE NOTICE 'story_maintenance_contracts (Task 9): all held';
END $$;

ROLLBACK;
