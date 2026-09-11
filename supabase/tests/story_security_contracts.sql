-- Stories: the security core. Read-only RLS, and no write grants at all.
--
-- Stories carry personal media between exactly two people. A hole here is
-- not "a bad calendar entry" -- it is an author rewriting their own
-- expires_at to keep a story alive forever, an outsider reading a
-- partner's photo, or a leaked viewed_at timestamp that says when someone
-- was last awake and looking at their phone. Every check below is written
-- as an attack that must fail, not a happy path that must pass.

BEGIN;

INSERT INTO auth.users(id) VALUES
  ('00000000-0000-0000-0000-00000000b201'::uuid),
  ('00000000-0000-0000-0000-00000000b202'::uuid),
  ('00000000-0000-0000-0000-00000000b203'::uuid) ON CONFLICT DO NOTHING;

INSERT INTO public.users(id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-00000000b201'::uuid, '+15559990001', 'SI1'),
  ('00000000-0000-0000-0000-00000000b202'::uuid, '+15559990002', 'SI2'),
  ('00000000-0000-0000-0000-00000000b203'::uuid, '+15559990003', 'SI3')
  ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.test_set_stories_auth(p_user_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p_user_id::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_user_id, 'role', 'authenticated')::text, true);
END;
$$;

-- ---------------------------------------------------------------------
-- Grants: authenticated gets SELECT on story_items and NOTHING on
-- story_views. An UPDATE grant would let an author rewrite expires_at,
-- occurred_on or media_key; a DELETE grant would bypass the soft-delete
-- contract and strand the storage object forever.
-- ---------------------------------------------------------------------
RESET ROLE;
DO $$ BEGIN
  IF has_table_privilege('authenticated','public.story_items','UPDATE') THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated can UPDATE story_items';
  END IF;
  IF has_table_privilege('authenticated','public.story_items','DELETE') THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated can DELETE story_items';
  END IF;
  IF has_table_privilege('authenticated','public.story_items','INSERT') THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated can INSERT story_items directly';
  END IF;
  IF NOT has_table_privilege('authenticated','public.story_items','SELECT') THEN
    RAISE EXCEPTION 'authenticated cannot read story_items';
  END IF;
  IF has_table_privilege('authenticated','public.story_views','SELECT') THEN
    RAISE EXCEPTION
      'EXPLOIT: authenticated can read story_views -- viewed_at leaks '
      'a partner''s activity pattern';
  END IF;
  IF has_table_privilege('authenticated','public.story_views','INSERT') THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated can INSERT story_views directly';
  END IF;
  IF has_table_privilege('authenticated','public.story_views','UPDATE') THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated can UPDATE story_views';
  END IF;
  IF has_table_privilege('authenticated','public.story_views','DELETE') THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated can DELETE story_views';
  END IF;
  IF has_table_privilege('anon','public.story_items','SELECT') THEN
    RAISE EXCEPTION 'EXPLOIT: anon can read story_items';
  END IF;
  IF has_table_privilege('anon','public.story_change_signals','SELECT') THEN
    RAISE EXCEPTION 'EXPLOIT: anon can read story_change_signals';
  END IF;
END $$;

DO $$
DECLARE
  v_rel        uuid;    -- active, unarchived: user b201 <-> b202
  v_rel_ended  uuid;    -- same pair, but ended
  v_rel_arch   uuid;    -- same pair, but active with an archived chat
  v_item       uuid;
  v_item_ended uuid;
  v_item_arch  uuid;
  v_deleted    uuid;
  v_count      int;
  v_now        timestamptz := now();
BEGIN
  RESET ROLE;

  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES ('00000000-0000-0000-0000-00000000b201'::uuid,
          '00000000-0000-0000-0000-00000000b202'::uuid, 'active')
  RETURNING id INTO v_rel;

  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES ('00000000-0000-0000-0000-00000000b201'::uuid,
          '00000000-0000-0000-0000-00000000b202'::uuid, 'ended')
  RETURNING id INTO v_rel_ended;

  INSERT INTO public.relationships(user_a, user_b, status, chat_archived_at)
  VALUES ('00000000-0000-0000-0000-00000000b201'::uuid,
          '00000000-0000-0000-0000-00000000b202'::uuid, 'active', v_now)
  RETURNING id INTO v_rel_arch;

  -- A live story in the active, unarchived relationship.
  INSERT INTO public.story_items(
    client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height,
    occurred_on, created_at, expires_at
  ) VALUES (
    gen_random_uuid(), v_rel, '00000000-0000-0000-0000-00000000b201'::uuid,
    'image', 'stories/live-media', 'stories/live-thumb', 1080, 1920,
    v_now::date, v_now, v_now + interval '24 hours'
  ) RETURNING id INTO v_item;

  -- A soft-deleted story in the SAME active relationship.
  INSERT INTO public.story_items(
    client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height,
    occurred_on, created_at, expires_at, deleted_at
  ) VALUES (
    gen_random_uuid(), v_rel, '00000000-0000-0000-0000-00000000b201'::uuid,
    'image', 'stories/deleted-media', 'stories/deleted-thumb', 1080, 1920,
    v_now::date, v_now, v_now + interval '24 hours', v_now
  ) RETURNING id INTO v_deleted;

  -- A story in the ENDED relationship.
  INSERT INTO public.story_items(
    client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height,
    occurred_on, created_at, expires_at
  ) VALUES (
    gen_random_uuid(), v_rel_ended, '00000000-0000-0000-0000-00000000b201'::uuid,
    'image', 'stories/ended-media', 'stories/ended-thumb', 1080, 1920,
    v_now::date, v_now, v_now + interval '24 hours'
  ) RETURNING id INTO v_item_ended;

  -- A story in the active relationship whose CHAT is archived.
  INSERT INTO public.story_items(
    client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height,
    occurred_on, created_at, expires_at
  ) VALUES (
    gen_random_uuid(), v_rel_arch, '00000000-0000-0000-0000-00000000b201'::uuid,
    'image', 'stories/archived-media', 'stories/archived-thumb', 1080, 1920,
    v_now::date, v_now, v_now + interval '24 hours'
  ) RETURNING id INTO v_item_arch;

  INSERT INTO public.story_change_signals(relationship_id)
  VALUES (v_rel) ON CONFLICT DO NOTHING;

  -- =================================================================
  -- SCENARIO 1: an outsider selects a story from a relationship they
  -- are not part of. Must see zero rows.
  -- =================================================================
  PERFORM public.test_set_stories_auth('00000000-0000-0000-0000-00000000b203'::uuid);
  SELECT count(*) INTO v_count FROM public.story_items WHERE id = v_item;
  IF v_count IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: an outsider read a story from a foreign relationship (% rows)',
      v_count;
  END IF;

  -- =================================================================
  -- SCENARIO 2: a member selects a soft-deleted story. Must see zero
  -- rows, even though they are a legitimate member of that relationship.
  -- =================================================================
  PERFORM public.test_set_stories_auth('00000000-0000-0000-0000-00000000b202'::uuid);
  SELECT count(*) INTO v_count FROM public.story_items WHERE id = v_deleted;
  IF v_count IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: a member read a soft-deleted story (% rows)', v_count;
  END IF;

  -- =================================================================
  -- SCENARIO 3: a member of an ENDED relationship selects. Must see
  -- zero rows -- status <> 'active' closes access even for a real
  -- member of a real, once-active relationship.
  -- =================================================================
  PERFORM public.test_set_stories_auth('00000000-0000-0000-0000-00000000b202'::uuid);
  SELECT count(*) INTO v_count FROM public.story_items WHERE id = v_item_ended;
  IF v_count IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: a member of an ended relationship read a story (% rows)',
      v_count;
  END IF;

  -- =================================================================
  -- SCENARIO 4: a member of an ARCHIVED chat selects. Must see zero
  -- rows -- this is the chat-media precedent, not the laxer timeline
  -- one: the relationship is still 'active' but chat_archived_at is set.
  -- =================================================================
  PERFORM public.test_set_stories_auth('00000000-0000-0000-0000-00000000b202'::uuid);
  SELECT count(*) INTO v_count FROM public.story_items WHERE id = v_item_arch;
  IF v_count IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: a member of an archived-chat relationship read a story (% rows)',
      v_count;
  END IF;

  -- =================================================================
  -- SCENARIO 5: a member selects a live story in an active, unarchived
  -- relationship. Must see exactly one row -- both the author and the
  -- non-author partner.
  -- =================================================================
  PERFORM public.test_set_stories_auth('00000000-0000-0000-0000-00000000b201'::uuid);
  SELECT count(*) INTO v_count FROM public.story_items WHERE id = v_item;
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION
      'the author could not read their own live story (% rows)', v_count;
  END IF;

  PERFORM public.test_set_stories_auth('00000000-0000-0000-0000-00000000b202'::uuid);
  SELECT count(*) INTO v_count FROM public.story_items WHERE id = v_item;
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION
      'the non-author partner could not read a live story (% rows)', v_count;
  END IF;

  -- =================================================================
  -- SCENARIO 6: an outsider selects story_change_signals. Must see
  -- zero rows.
  -- =================================================================
  PERFORM public.test_set_stories_auth('00000000-0000-0000-0000-00000000b203'::uuid);
  SELECT count(*) INTO v_count
    FROM public.story_change_signals WHERE relationship_id = v_rel;
  IF v_count IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: an outsider read story_change_signals (% rows)', v_count;
  END IF;

  -- A member DOES see the signal row for their own relationship.
  PERFORM public.test_set_stories_auth('00000000-0000-0000-0000-00000000b201'::uuid);
  SELECT count(*) INTO v_count
    FROM public.story_change_signals WHERE relationship_id = v_rel;
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION
      'a member could not read their own story_change_signals row (% rows)',
      v_count;
  END IF;

  -- =================================================================
  -- story_views has no policy at all: RLS on with no policy denies
  -- everything, even to a real member selecting their own relationship's
  -- rows through the app's authenticated role. This exercises the
  -- table-level REVOKE already checked above, at row level too.
  -- =================================================================
  RESET ROLE;
  INSERT INTO public.story_views(story_item_id, viewer_id)
  VALUES (v_item, '00000000-0000-0000-0000-00000000b202'::uuid)
  ON CONFLICT DO NOTHING;

  PERFORM public.test_set_stories_auth('00000000-0000-0000-0000-00000000b202'::uuid);
  BEGIN
    SELECT count(*) INTO v_count FROM public.story_views
     WHERE story_item_id = v_item;
    RAISE EXCEPTION
      'EXPLOIT: a member read story_views instead of hitting a grant error (% rows)',
      v_count;
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL; -- expected: no SELECT grant at all.
  END;

  RAISE NOTICE 'story security contracts: all held';
END $$;

RESET ROLE;
DROP FUNCTION IF EXISTS public.test_set_stories_auth(uuid);
ROLLBACK;

-- ---------------------------------------------------------------------
-- The bucket must be PRIVATE. A public bucket makes every storage key a
-- permanent unauthenticated URL, which defeats deletion entirely.
-- Runs outside the transaction above: storage.buckets is catalog state
-- created by the migration, not test fixture data to roll back.
-- ---------------------------------------------------------------------
RESET ROLE;
DO $$
DECLARE v_public boolean;
BEGIN
  SELECT public INTO v_public FROM storage.buckets WHERE id = 'story-media';
  IF v_public IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'EXPLOIT: story-media bucket is public or missing';
  END IF;
END $$;
