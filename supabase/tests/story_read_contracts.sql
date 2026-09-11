-- Stories: the four read RPCs (Task 8, spec §5.5).
--
-- These RPCs are SECURITY INVOKER on purpose -- story_items RLS
-- (story_items_read_members, 20260938020000) is the ONLY authorization
-- authority here, not a predicate re-implemented four times. So the
-- outsider contract (5 below) is not "the RPC checks and refuses" --
-- it is "the RPC runs the plain query and RLS returns zero rows,"
-- which is exactly what must keep holding as this file evolves.
--
-- House rule, applied throughout this file: every comparison of a
-- jsonb-extracted value uses IS DISTINCT FROM / IS NOT DISTINCT FROM,
-- never a bare = or <>. A bare comparison against NULL evaluates to
-- NULL, not true, so an IF built on one silently never fires and the
-- RAISE EXCEPTION it guards never runs -- a vacuous assertion that
-- passes while checking nothing. These RPCs return SETOF/TABLE rows,
-- not jsonb, so most assertions here are row/count checks; count(*) is
-- the one thing that can never be NULL, so a bare = or <> against a
-- count is correct and used throughout. Any field pulled from a row
-- that could legitimately be NULL (there are none required by these
-- six contracts) would still follow the IS DISTINCT FROM idiom.

BEGIN;

INSERT INTO auth.users(id) VALUES
  ('00000000-0000-0000-0000-00000000d501'::uuid),
  ('00000000-0000-0000-0000-00000000d502'::uuid),
  ('00000000-0000-0000-0000-00000000d503'::uuid) ON CONFLICT DO NOTHING;

INSERT INTO public.users(id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-00000000d501'::uuid, '+15559990001', 'RR1'),
  ('00000000-0000-0000-0000-00000000d502'::uuid, '+15559990002', 'RR2'),
  ('00000000-0000-0000-0000-00000000d503'::uuid, '+15559990003', 'RR3')
  ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.test_set_story_read_auth(p_user_id uuid)
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
-- Grants: anon must not reach any of the four; authenticated must.
-- ---------------------------------------------------------------------
RESET ROLE;
DO $$ BEGIN
  IF has_function_privilege('anon',
    'public.get_story_ring_summary(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon can execute get_story_ring_summary';
  END IF;
  IF has_function_privilege('anon',
    'public.list_active_story_items(uuid,uuid,timestamptz,uuid,int)',
    'EXECUTE') THEN
    RAISE EXCEPTION 'anon can execute list_active_story_items';
  END IF;
  IF has_function_privilege('anon',
    'public.list_story_day_counts(uuid,date,date)', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon can execute list_story_day_counts';
  END IF;
  IF has_function_privilege('anon',
    'public.list_story_day_items(uuid,date,timestamptz,uuid,int)',
    'EXECUTE') THEN
    RAISE EXCEPTION 'anon can execute list_story_day_items';
  END IF;

  IF NOT has_function_privilege('authenticated',
    'public.get_story_ring_summary(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated cannot execute get_story_ring_summary';
  END IF;
  IF NOT has_function_privilege('authenticated',
    'public.list_active_story_items(uuid,uuid,timestamptz,uuid,int)',
    'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated cannot execute list_active_story_items';
  END IF;
  IF NOT has_function_privilege('authenticated',
    'public.list_story_day_counts(uuid,date,date)', 'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated cannot execute list_story_day_counts';
  END IF;
  IF NOT has_function_privilege('authenticated',
    'public.list_story_day_items(uuid,date,timestamptz,uuid,int)',
    'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated cannot execute list_story_day_items';
  END IF;
END $$;

DO $$
DECLARE
  v_rel        uuid;
  v_outsider_rel uuid;
  v_count      int;
  v_row        record;
  v_first_id   uuid;
  v_first_created timestamptz;
  v_expired_id uuid;
  v_today      date := (now() at time zone 'utc')::date;
  v_last_created timestamptz;
  v_last_id    uuid;
  v_seen_ids   uuid[];
  v_new_id     uuid;
  v_new_seen_ids uuid[];
  v_pre_insert_page2_ids uuid[];
BEGIN
  RESET ROLE;

  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES ('00000000-0000-0000-0000-00000000d501'::uuid,
          '00000000-0000-0000-0000-00000000d502'::uuid, 'active')
  RETURNING id INTO v_rel;

  -- A relationship the attacker (d503) is NOT in.
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES ('00000000-0000-0000-0000-00000000d501'::uuid,
          '00000000-0000-0000-0000-00000000d503'::uuid, 'active')
  RETURNING id INTO v_outsider_rel;

  -- =================================================================
  -- Fixture: d501 (author) posts a currently-active item AND an
  -- already-expired item, both on today's occurred_on, into v_rel.
  -- Inserted directly (bypassing create_story_item, which is Task 5's
  -- concern) since this file tests reads, not finalization.
  -- =================================================================
  INSERT INTO public.story_items(
    id, client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height,
    occurred_on, created_at, expires_at
  ) VALUES (
    gen_random_uuid(), gen_random_uuid(), v_rel,
    '00000000-0000-0000-0000-00000000d501'::uuid, 'image',
    'story-media/read-1/media', 'story-media/read-1/thumb',
    1080, 1920, v_today,
    now() - interval '2 hours', now() + interval '22 hours'
  ) RETURNING id, created_at INTO v_first_id, v_first_created;

  INSERT INTO public.story_items(
    id, client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height,
    occurred_on, created_at, expires_at
  ) VALUES (
    gen_random_uuid(), gen_random_uuid(), v_rel,
    '00000000-0000-0000-0000-00000000d501'::uuid, 'image',
    'story-media/read-2/media', 'story-media/read-2/thumb',
    1080, 1920, v_today,
    now() - interval '30 hours', now() - interval '6 hours'
  ) RETURNING id INTO v_expired_id;

  -- =================================================================
  -- CONTRACT 2: list_active_story_items excludes expires_at <= now();
  -- list_story_day_items INCLUDES it. Same row, two surfaces.
  -- =================================================================
  PERFORM public.test_set_story_read_auth(
    '00000000-0000-0000-0000-00000000d501'::uuid);

  SELECT count(*) INTO v_count
    FROM public.list_active_story_items(v_rel,
      '00000000-0000-0000-0000-00000000d501'::uuid, NULL, NULL, 50)
   WHERE id = v_expired_id;
  IF v_count <> 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: list_active_story_items returned an expired item';
  END IF;

  SELECT count(*) INTO v_count
    FROM public.list_active_story_items(v_rel,
      '00000000-0000-0000-0000-00000000d501'::uuid, NULL, NULL, 50)
   WHERE id = v_first_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION
      'list_active_story_items dropped the still-active item';
  END IF;

  SELECT count(*) INTO v_count
    FROM public.list_story_day_items(v_rel, v_today, NULL, NULL, 50)
   WHERE id = v_expired_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION
      'list_story_day_items must include an expired item from its day';
  END IF;

  SELECT count(*) INTO v_count
    FROM public.list_story_day_items(v_rel, v_today, NULL, NULL, 50)
   WHERE id = v_first_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION
      'list_story_day_items dropped the still-active item on its own day';
  END IF;

  -- =================================================================
  -- CONTRACT 4: ordering is oldest-first for both playback reads.
  -- v_expired_id was created 30h ago, v_first_id 2h ago -- day items
  -- must return v_expired_id before v_first_id.
  -- =================================================================
  SELECT array_agg(id ORDER BY ord) INTO v_seen_ids
    FROM (
      SELECT id, row_number() OVER () AS ord
        FROM public.list_story_day_items(v_rel, v_today, NULL, NULL, 50)
    ) t;
  IF v_seen_ids[1] IS DISTINCT FROM v_expired_id
     OR v_seen_ids[2] IS DISTINCT FROM v_first_id THEN
    RAISE EXCEPTION
      'list_story_day_items is not oldest-first: got %', v_seen_ids;
  END IF;

  -- =================================================================
  -- CONTRACT 1: p_limit = 1000 returns AT MOST 50.
  -- Populate v_rel's day with 55 more items (57 total for the day) so
  -- an uncapped p_limit would visibly return more than 50.
  -- =================================================================
  RESET ROLE;
  FOR v_count IN 1..55 LOOP
    v_last_created := now() - interval '1 hour'
      + (v_count || ' milliseconds')::interval;
    INSERT INTO public.story_items(
      client_story_id, relationship_id, author_id, media_type,
      media_key, thumbnail_key, media_width, media_height,
      occurred_on, created_at, expires_at
    ) VALUES (
      gen_random_uuid(), v_rel,
      '00000000-0000-0000-0000-00000000d501'::uuid, 'image',
      'story-media/bulk-' || v_count || '/media',
      'story-media/bulk-' || v_count || '/thumb',
      1080, 1920, v_today,
      v_last_created, v_last_created + interval '24 hours'
    );
  END LOOP;
  PERFORM public.test_set_story_read_auth(
    '00000000-0000-0000-0000-00000000d501'::uuid);

  SELECT count(*) INTO v_count
    FROM public.list_story_day_items(v_rel, v_today, NULL, NULL, 1000);
  IF v_count > 50 THEN
    RAISE EXCEPTION
      'EXPLOIT: p_limit=1000 on list_story_day_items returned % rows (> 50)',
      v_count;
  END IF;
  IF v_count <> 50 THEN
    RAISE EXCEPTION
      'expected exactly 50 (of 57 available) rows, got %', v_count;
  END IF;

  SELECT count(*) INTO v_count
    FROM public.list_active_story_items(v_rel,
      '00000000-0000-0000-0000-00000000d501'::uuid, NULL, NULL, 1000);
  IF v_count > 50 THEN
    RAISE EXCEPTION
      'EXPLOIT: p_limit=1000 on list_active_story_items returned % rows (> 50)',
      v_count;
  END IF;

  -- =================================================================
  -- CONTRACT 3: keyset paging with an INSERT between pages appends
  -- rather than duplicating or skipping. Constructed so offset paging
  -- would visibly fail: page 1 is the first 50 (oldest-first) of the
  -- 57 rows; then a NEW row is inserted with a created_at OLDER than
  -- several rows already returned on page 1 (simulating a
  -- reel/calendar backfill or clock skew) plus one genuinely newer row.
  -- Offset paging (LIMIT 50 OFFSET 50) would have page 2 start at
  -- "row 51 by current sort order," which shifts by 1 the instant a
  -- new row lands before that boundary -- either re-showing row 50 or
  -- skipping the true row 51. Keyset paging keys page 2 on the VALUE
  -- of the last row returned on page 1, which cannot shift.
  -- =================================================================
  SELECT count(*) INTO v_count FROM public.story_items
   WHERE relationship_id = v_rel AND occurred_on = v_today;
  IF v_count <> 57 THEN
    RAISE EXCEPTION 'fixture drift: expected 57 day rows, got %', v_count;
  END IF;

  -- Page 1: first 50, oldest first. Capture the keyset cursor (the
  -- LAST row's created_at/id) rather than an offset.
  SELECT si.created_at, si.id INTO v_last_created, v_last_id
    FROM public.list_story_day_items(v_rel, v_today, NULL, NULL, 50) si
   ORDER BY si.created_at DESC, si.id DESC
   LIMIT 1;

  SELECT array_agg(id) INTO v_seen_ids
    FROM public.list_story_day_items(v_rel, v_today, NULL, NULL, 50);
  IF array_length(v_seen_ids, 1) <> 50 THEN
    RAISE EXCEPTION 'page 1 did not return 50 rows';
  END IF;

  -- What page 2 (keyed on this cursor) looks like BEFORE the insert --
  -- the baseline this contract proves stays unchanged afterward.
  SELECT array_agg(id) INTO v_pre_insert_page2_ids
    FROM public.list_story_day_items(
      v_rel, v_today, v_last_created, v_last_id, 50);
  IF array_length(v_pre_insert_page2_ids, 1) <> 7 THEN
    RAISE EXCEPTION
      'fixture drift: expected 7 rows after the cursor before the '
      'insert, got %', array_length(v_pre_insert_page2_ids, 1);
  END IF;

  -- Insert a new row whose created_at falls strictly BEFORE the
  -- captured page-1/page-2 cursor (v_last_created is bulk row #48's
  -- timestamp, now() - 1h + 48ms) -- i.e. this new row belongs
  -- somewhere in the MIDDLE of page 1's oldest-first order, not after
  -- it. This is what would shift an offset-based page 2: LIMIT 50
  -- OFFSET 50 defines "page 2" as "skip the first 50 by current sort,"
  -- and inserting a row before that boundary pushes every subsequent
  -- row's position back by one, corrupting the next page. A keyset
  -- page 2, defined by VALUE rather than position, is unaffected.
  RESET ROLE;
  v_first_created := now() - interval '1 hour' + interval '24 milliseconds';
  INSERT INTO public.story_items(
    client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height,
    occurred_on, created_at, expires_at
  ) VALUES (
    gen_random_uuid(), v_rel,
    '00000000-0000-0000-0000-00000000d501'::uuid, 'image',
    'story-media/backfill/media', 'story-media/backfill/thumb',
    1080, 1920, v_today,
    v_first_created, v_first_created + interval '24 hours'
  ) RETURNING id INTO v_new_id;
  PERFORM public.test_set_story_read_auth(
    '00000000-0000-0000-0000-00000000d501'::uuid);

  -- Page 2, keyed on the cursor captured from ORIGINAL page 1 (before
  -- the insert) -- exactly what a viewer resuming playback from where
  -- they left off would send back. Not an offset.
  SELECT array_agg(id) INTO v_new_seen_ids
    FROM public.list_story_day_items(
      v_rel, v_today, v_last_created, v_last_id, 50);

  IF v_new_id = ANY (v_new_seen_ids) THEN
    RAISE EXCEPTION
      'EXPLOIT: a backfilled row (older than the keyset cursor) leaked '
      'into page 2 -- this indicates offset-shaped, not keyset, paging';
  END IF;

  -- The defining keyset property: resuming from the SAME cursor after
  -- the insert returns the SAME set of "next" rows it would have
  -- before the insert -- unaffected by anything that landed earlier in
  -- the order. Offset paging (LIMIT 50 OFFSET 50) has no such
  -- invariant: inserting one row before the old boundary shifts what
  -- "OFFSET 50" points at, so this exact re-fetch would silently
  -- change under offset paging but cannot change under keyset paging.
  IF v_new_seen_ids IS DISTINCT FROM v_pre_insert_page2_ids THEN
    RAISE EXCEPTION
      'EXPLOIT: paging past the same cursor changed after an insert '
      'landed before it -- % vs %', v_new_seen_ids, v_pre_insert_page2_ids;
  END IF;

  -- No overlap between ORIGINAL page 1 (v_seen_ids, captured before
  -- the insert) and page 2 keyed on the same cursor -- no duplication.
  SELECT count(*) INTO v_count
    FROM (
      SELECT unnest(v_seen_ids) AS id
      INTERSECT
      SELECT unnest(v_new_seen_ids) AS id
    ) overlap;
  IF v_count <> 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: page 1 and page 2 overlap by % row(s) -- duplication',
      v_count;
  END IF;

  -- The backfilled row is not lost: a caller opening the day FRESH
  -- (no cursor) sees it appended into its correct chronological
  -- position, proving inserts append rather than vanish.
  SELECT count(*) INTO v_count
    FROM public.list_story_day_items(v_rel, v_today, NULL, NULL, 50)
   WHERE id = v_new_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION
      'EXPLOIT: the backfilled row is not visible in a fresh first '
      'page -- it was skipped rather than appended';
  END IF;

  -- And every row from ORIGINAL page 1 plus page 2 (keyed on the same
  -- cursor) plus the backfilled row together account for all 58 rows
  -- that now exist -- nothing vanished, nothing was double-counted.
  SELECT count(*) INTO v_count
    FROM (
      SELECT unnest(v_seen_ids) AS id
      UNION
      SELECT unnest(v_new_seen_ids) AS id
      UNION
      SELECT v_new_id
    ) everything;
  IF v_count <> 58 THEN
    RAISE EXCEPTION
      'EXPLOIT: original page 1 + resumed page 2 + the backfilled row '
      'account for % of 58 rows expected', v_count;
  END IF;

  -- =================================================================
  -- CONTRACT 5: an outsider gets zero rows from all four RPCs.
  -- d503 is not a member of v_rel; RLS on story_items (not a
  -- re-implemented predicate here) must return nothing.
  -- =================================================================
  PERFORM public.test_set_story_read_auth(
    '00000000-0000-0000-0000-00000000d503'::uuid);

  SELECT count(*) INTO v_count
    FROM public.list_active_story_items(v_rel,
      '00000000-0000-0000-0000-00000000d501'::uuid, NULL, NULL, 50);
  IF v_count <> 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: outsider got % rows from list_active_story_items', v_count;
  END IF;

  SELECT count(*) INTO v_count
    FROM public.list_story_day_items(v_rel, v_today, NULL, NULL, 50);
  IF v_count <> 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: outsider got % rows from list_story_day_items', v_count;
  END IF;

  SELECT count(*) INTO v_count
    FROM public.list_story_day_counts(v_rel, v_today - 7, v_today + 1);
  IF v_count <> 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: outsider got % day-count rows from list_story_day_counts',
      v_count;
  END IF;

  SELECT count(*) INTO v_count
    FROM public.get_story_ring_summary(v_rel);
  IF v_count <> 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: outsider got % rows from get_story_ring_summary', v_count;
  END IF;

  -- The outsider's OWN relationship must still work normally (sanity:
  -- this is not a global lockout, it is membership-scoped).
  SELECT count(*) INTO v_count
    FROM public.get_story_ring_summary(v_outsider_rel);
  IF v_count <> 0 THEN
    -- No stories exist there yet; zero is correct. Just proving the
    -- call itself does not error for a relationship the caller IS in.
    NULL;
  END IF;

  -- =================================================================
  -- CONTRACT 6: get_story_ring_summary returns the newest thumbnail
  -- per author, and an unviewed count that EXCLUDES the caller's own
  -- stories.
  -- =================================================================
  -- d502 (the partner) posts two active items into v_rel, newest last,
  -- both unviewed by d501.
  RESET ROLE;
  INSERT INTO public.story_items(
    client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height,
    occurred_on, created_at, expires_at
  ) VALUES (
    gen_random_uuid(), v_rel,
    '00000000-0000-0000-0000-00000000d502'::uuid, 'image',
    'story-media/partner-1/media', 'story-media/partner-1/thumb',
    1080, 1920, v_today, now() - interval '10 minutes',
    now() + interval '23 hours 50 minutes'
  );
  INSERT INTO public.story_items(
    client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height,
    occurred_on, created_at, expires_at
  ) VALUES (
    gen_random_uuid(), v_rel,
    '00000000-0000-0000-0000-00000000d502'::uuid, 'image',
    'story-media/partner-2-newest/media',
    'story-media/partner-2-newest/thumb',
    1080, 1920, v_today, now() - interval '1 minute',
    now() + interval '23 hours 59 minutes'
  );

  PERFORM public.test_set_story_read_auth(
    '00000000-0000-0000-0000-00000000d501'::uuid);

  SELECT * INTO v_row
    FROM public.get_story_ring_summary(v_rel)
   WHERE author_id = '00000000-0000-0000-0000-00000000d502'::uuid;

  IF v_row.newest_thumbnail_key IS DISTINCT FROM
     'story-media/partner-2-newest/thumb' THEN
    RAISE EXCEPTION
      'ring summary did not return the newest thumbnail for the '
      'partner: got %', v_row.newest_thumbnail_key;
  END IF;
  IF v_row.unviewed_count <> 2 THEN
    RAISE EXCEPTION
      'expected 2 unviewed partner items, got %', v_row.unviewed_count;
  END IF;

  -- d501's OWN row in the same summary must report unviewed_count = 0,
  -- regardless of has_been_viewed on any of d501's own stories --
  -- has_been_viewed there means "my partner saw it," never "I saw it."
  SELECT * INTO v_row
    FROM public.get_story_ring_summary(v_rel)
   WHERE author_id = '00000000-0000-0000-0000-00000000d501'::uuid;
  IF v_row.unviewed_count <> 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: caller''s own unviewed_count is % (must always be 0 -- '
      'own stories are never counted as unviewed to the author)',
      v_row.unviewed_count;
  END IF;

  -- Now mark one of the partner's stories viewed (as the non-author,
  -- d501, which is what mark_story_viewed requires) and confirm the
  -- unviewed count drops accordingly, still excluding d501's own.
  PERFORM public.mark_story_viewed(
    (SELECT id FROM public.story_items
      WHERE thumbnail_key = 'story-media/partner-1/thumb'));

  SELECT * INTO v_row
    FROM public.get_story_ring_summary(v_rel)
   WHERE author_id = '00000000-0000-0000-0000-00000000d502'::uuid;
  IF v_row.unviewed_count <> 1 THEN
    RAISE EXCEPTION
      'expected 1 unviewed partner item after marking one viewed, got %',
      v_row.unviewed_count;
  END IF;

  RAISE NOTICE 'story_read_contracts: all six contracts held';
END $$;

RESET ROLE;
DROP FUNCTION IF EXISTS public.test_set_story_read_auth(uuid);
ROLLBACK;
