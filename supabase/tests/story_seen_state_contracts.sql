-- supabase/tests/story_seen_state_contracts.sql
-- Story seen-state under "Show when we've seen things" (Spec 1a Task 4).
-- The viewer always sees their own state; the author sees a view only while
-- the setting is on AND the view happened while it was on; a view while off
-- bumps no author-visible signal. Every check RAISEs on violation.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('5d100000-0000-0000-0000-0000000000a1'),
  ('5d100000-0000-0000-0000-0000000000b2'),
  ('5d100000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('5d100000-0000-0000-0000-0000000000a1', '+233599400001', 'Story A'),
  ('5d100000-0000-0000-0000-0000000000b2', '+233599400002', 'Story B'),
  ('5d100000-0000-0000-0000-0000000000c3', '+233599400003', 'Story C')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at) VALUES
  ('5d200000-0000-0000-0000-000000000001', '5d100000-0000-0000-0000-0000000000a1',
   '5d100000-0000-0000-0000-0000000000b2', 'active', CURRENT_DATE, now(), '2026-11-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING;
-- Three stories by A, inserted as the owner (the finalize RPC is covered by
-- story_rpc_contracts; this file is about reads).
INSERT INTO public.story_items (id, client_story_id, relationship_id, author_id, media_type,
  media_key, thumbnail_key, media_width, media_height, occurred_on, created_at, expires_at)
SELECT s.id, s.id, '5d200000-0000-0000-0000-000000000001', '5d100000-0000-0000-0000-0000000000a1', 'image',
  'story-media/5d/' || s.n || '/media', 'story-media/5d/' || s.n || '/thumb', 1080, 1920,
  CURRENT_DATE, now() - interval '1 minute' + (s.n || ' second')::interval,
  now() - interval '1 minute' + (s.n || ' second')::interval + interval '24 hours'
FROM (VALUES ('5d300000-0000-0000-0000-000000000001'::uuid, 1),
             ('5d300000-0000-0000-0000-000000000002'::uuid, 2),
             ('5d300000-0000-0000-0000-000000000003'::uuid, 3)) AS s(id, n)
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;
-- has_been_viewed as the CURRENT caller sees it through the reel RPC.
CREATE FUNCTION pg_temp.reel_seen(p_story uuid) RETURNS boolean LANGUAGE sql AS $$
  SELECT has_been_viewed FROM public.list_active_story_items(
    '5d200000-0000-0000-0000-000000000001', '5d100000-0000-0000-0000-0000000000a1')
  WHERE id = p_story $$;
CREATE FUNCTION pg_temp.day_seen(p_story uuid) RETURNS boolean LANGUAGE sql AS $$
  SELECT has_been_viewed FROM public.list_story_day_items(
    '5d200000-0000-0000-0000-000000000001', CURRENT_DATE)
  WHERE id = p_story $$;
CREATE FUNCTION pg_temp.signal() RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce((SELECT version FROM public.story_change_signals
                   WHERE relationship_id = '5d200000-0000-0000-0000-000000000001'), 0) $$;

-- 1. Grants: the two seen columns are never client-selectable; the rest are.
DO $$
DECLARE v int;
BEGIN
  IF has_table_privilege('authenticated', 'public.story_items', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated holds table-level SELECT on story_items';
  END IF;
  IF NOT has_any_column_privilege('authenticated', 'public.story_items', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated cannot read story_items at all';
  END IF;
  IF has_column_privilege('authenticated', 'public.story_items', 'has_been_viewed', 'SELECT')
     OR has_column_privilege('authenticated', 'public.story_items', 'seen_shown', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a seen column is client-selectable';
  END IF;
  IF NOT has_column_privilege('authenticated', 'public.story_items', 'media_key', 'SELECT')
     OR NOT has_column_privilege('authenticated', 'public.story_items', 'thumbnail_key', 'SELECT')
     OR NOT has_column_privilege('authenticated', 'public.story_items', 'occurred_on', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a needed story_items column is not selectable';
  END IF;
  PERFORM pg_temp.as_user('5d100000-0000-0000-0000-0000000000a1');
  BEGIN
    SELECT count(*) INTO v FROM public.story_items WHERE has_been_viewed;
    RAISE EXCEPTION 'CONTRACT VIOLATED: the author selected has_been_viewed directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  SELECT count(*) INTO v FROM public.story_items WHERE relationship_id = '5d200000-0000-0000-0000-000000000001';
  IF v <> 3 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the allowlisted read returned % rows', v; END IF;
  RESET ROLE;
END $$;

-- 2. Off (no prefs rows): the partner's view is recorded for the partner,
--    hidden from the author, and bumps no signal.
DO $$
DECLARE v_before bigint; v jsonb; v_row public.story_items%ROWTYPE; v_ring record;
BEGIN
  v_before := pg_temp.signal();
  PERFORM pg_temp.as_user('5d100000-0000-0000-0000-0000000000b2');
  v := public.mark_story_viewed('5d300000-0000-0000-0000-000000000001');
  IF (v->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'setup: the partner''s view was refused: %', v;
  END IF;
  IF pg_temp.reel_seen('5d300000-0000-0000-0000-000000000001') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the viewer does not see their own view';
  END IF;
  SELECT * INTO v_ring FROM public.get_story_ring_summary('5d200000-0000-0000-0000-000000000001')
   WHERE author_id = '5d100000-0000-0000-0000-0000000000a1';
  IF v_ring.unviewed_count <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: viewer ring expected 2 unviewed, got %', v_ring.unviewed_count;
  END IF;

  PERFORM pg_temp.as_user('5d100000-0000-0000-0000-0000000000a1');
  IF pg_temp.reel_seen('5d300000-0000-0000-0000-000000000001') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the author learned of a view while receipts were off (reel)';
  END IF;
  IF pg_temp.day_seen('5d300000-0000-0000-0000-000000000001') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the author learned of a view while receipts were off (day)';
  END IF;
  RESET ROLE;
  IF pg_temp.signal() <> v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a view while off bumped story_change_signals';
  END IF;
  SELECT * INTO v_row FROM public.story_items WHERE id = '5d300000-0000-0000-0000-000000000001';
  IF v_row.has_been_viewed IS DISTINCT FROM true OR v_row.seen_shown IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: stored state wrong after an off view (% / %)', v_row.has_been_viewed, v_row.seen_shown;
  END IF;
END $$;

-- 3. On (both): a NEW view shows to the author and bumps the signal once; the
--    earlier off-view stays hidden.
DO $$
DECLARE v_before bigint; v jsonb;
BEGIN
  PERFORM pg_temp.as_user('5d100000-0000-0000-0000-0000000000a1');
  PERFORM public.set_seen_receipts('5d200000-0000-0000-0000-000000000001', true);
  PERFORM pg_temp.as_user('5d100000-0000-0000-0000-0000000000b2');
  PERFORM public.set_seen_receipts('5d200000-0000-0000-0000-000000000001', true);
  RESET ROLE;
  v_before := pg_temp.signal();
  PERFORM pg_temp.as_user('5d100000-0000-0000-0000-0000000000b2');
  v := public.mark_story_viewed('5d300000-0000-0000-0000-000000000002');
  IF (v->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'setup: the partner''s second view was refused: %', v;
  END IF;
  PERFORM pg_temp.as_user('5d100000-0000-0000-0000-0000000000a1');
  IF pg_temp.reel_seen('5d300000-0000-0000-0000-000000000002') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the author does not see a view made while on';
  END IF;
  IF pg_temp.day_seen('5d300000-0000-0000-0000-000000000002') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the day list hides a view made while on';
  END IF;
  IF pg_temp.reel_seen('5d300000-0000-0000-0000-000000000001') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: turning receipts on revealed a view made while off';
  END IF;
  RESET ROLE;
  IF pg_temp.signal() <> v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a view while on did not bump the signal exactly once';
  END IF;
END $$;

-- 4. Off again by one partner: hidden again at once; a further view is hidden
--    for good; on again shows only views made while on.
DO $$
DECLARE v_before bigint; v jsonb;
BEGIN
  PERFORM pg_temp.as_user('5d100000-0000-0000-0000-0000000000a1');
  PERFORM public.set_seen_receipts('5d200000-0000-0000-0000-000000000001', false);
  IF pg_temp.reel_seen('5d300000-0000-0000-0000-000000000002') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one partner turning off did not hide seen-state';
  END IF;
  RESET ROLE;
  v_before := pg_temp.signal();
  PERFORM pg_temp.as_user('5d100000-0000-0000-0000-0000000000b2');
  v := public.mark_story_viewed('5d300000-0000-0000-0000-000000000003');
  RESET ROLE;
  IF pg_temp.signal() <> v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a view after turning off bumped the signal';
  END IF;
  PERFORM pg_temp.as_user('5d100000-0000-0000-0000-0000000000a1');
  PERFORM public.set_seen_receipts('5d200000-0000-0000-0000-000000000001', true);
  IF pg_temp.reel_seen('5d300000-0000-0000-0000-000000000002') IS DISTINCT FROM true
     OR pg_temp.reel_seen('5d300000-0000-0000-0000-000000000003') IS DISTINCT FROM false
     OR pg_temp.reel_seen('5d300000-0000-0000-0000-000000000001') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after re-enabling, only views made while on may show';
  END IF;
  -- The viewer's own view of their state never changed through any of this.
  PERFORM pg_temp.as_user('5d100000-0000-0000-0000-0000000000b2');
  IF pg_temp.reel_seen('5d300000-0000-0000-0000-000000000001') IS DISTINCT FROM true
     OR pg_temp.reel_seen('5d300000-0000-0000-0000-000000000003') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the viewer lost their own seen state';
  END IF;
  -- seen_shown itself is never returned as true to anyone.
  IF EXISTS (SELECT 1 FROM public.list_active_story_items(
               '5d200000-0000-0000-0000-000000000001', '5d100000-0000-0000-0000-0000000000a1')
             WHERE seen_shown) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: seen_shown leaked through the list RPC';
  END IF;
  RESET ROLE;
END $$;

-- 5. Outsiders get nothing from the definer RPCs.
DO $$
DECLARE v int;
BEGIN
  PERFORM pg_temp.as_user('5d100000-0000-0000-0000-0000000000c3');
  SELECT count(*) INTO v FROM public.list_active_story_items(
    '5d200000-0000-0000-0000-000000000001', '5d100000-0000-0000-0000-0000000000a1');
  IF v <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider listed % reel items', v; END IF;
  SELECT count(*) INTO v FROM public.list_story_day_items('5d200000-0000-0000-0000-000000000001', CURRENT_DATE);
  IF v <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider listed % day items', v; END IF;
  SELECT count(*) INTO v FROM public.get_story_ring_summary('5d200000-0000-0000-0000-000000000001');
  IF v <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider got % ring rows', v; END IF;
  RESET ROLE;
  RAISE NOTICE 'story_seen_state_contracts: all held';
END $$;

ROLLBACK;
