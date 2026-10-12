-- Planning P3/P4 deferred minors (M2, M4, M6, M7, M9).
-- Run: psql -q -d attune_planning -f supabase/tests/planning_minors_contracts.sql
\set ON_ERROR_STOP on

BEGIN;
DO $$
DECLARE
  v_rel uuid := '34000000-0000-0000-0000-000000000001';
  v_a uuid := '34000000-0000-0000-0000-0000000000a1';
  v_b uuid := '34000000-0000-0000-0000-0000000000b1';
  v_trips uuid; v_goals uuid;
  v_trip uuid := '34000000-0000-0000-0000-00000000e001';
  v_goal uuid := '34000000-0000-0000-0000-00000000e002';
  v_poll uuid := '34000000-0000-0000-0000-00000000b001';
  v_exp uuid := '34000000-0000-0000-0000-00000000b002';
  v_prog uuid := '34000000-0000-0000-0000-00000000b003';
  v_link uuid := '34000000-0000-0000-0000-00000000b004';
  v_photo uuid := '34000000-0000-0000-0000-00000000b005';
  v_o1 uuid := '34000000-0000-0000-0000-0000000001a1';
  v_o2 uuid := '34000000-0000-0000-0000-0000000001a2';
  v_kept text; v_orphan text; v_fresh text;
  v_v int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_a,'mn_a@t.test'),(v_b,'mn_b@t.test') ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES (v_a,'+13400000001','Ama'),(v_b,'+13400000002','Kofi') ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status) VALUES (v_rel, v_a, v_b, 'active') ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);
  PERFORM public.get_planning_home(v_rel);
  SELECT id INTO v_trips FROM public.planning_categories WHERE relationship_id = v_rel AND seed_key = 'trips';
  SELECT id INTO v_goals FROM public.planning_categories WHERE relationship_id = v_rel AND seed_key = 'goals';
  PERFORM public.create_planning_entry(v_trip, v_trips, 'Bali', false, 'IDR');
  PERFORM public.create_planning_entry(v_goal, v_goals, 'Deposit', false, 'GHS');

  -- M2: an option deleted before the poll was locked can't come back under the Date block.
  PERFORM public.add_planning_block(v_poll, v_trip, 'date_poll', '{}', NULL, NULL, NULL);
  PERFORM public.save_planning_rich_item(v_o1, v_poll, NULL, '{"date_start":"2026-11-20"}', NULL);
  PERFORM public.save_planning_rich_item(v_o2, v_poll, NULL, '{"date_start":"2026-12-04"}', v_o1);
  PERFORM public.vote_planning_poll(v_o1, true);
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_b), true);
  PERFORM public.vote_planning_poll(v_o1, true);
  PERFORM public.delete_planning_block_item(v_o2);
  PERFORM public.lock_planning_poll(v_poll, v_o1);
  BEGIN PERFORM public.restore_planning_block_item(v_o2); RAISE EXCEPTION 'EXPLOIT: a poll option came back under a Date block';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT IN ('planning:not_found', 'planning:invalid_input') THEN RAISE; END IF; END;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);

  -- M7: an expense line or contribution needs a whole-number amount, and a bad one is a planning error.
  PERFORM public.add_planning_block(v_exp, v_trip, 'expenses', '{}', NULL, NULL, NULL);
  BEGIN PERFORM public.save_planning_rich_item(gen_random_uuid(), v_exp, NULL, '{"label":"Taxi"}', NULL);
    RAISE EXCEPTION 'EXPLOIT: an expense without an amount was saved';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  BEGIN PERFORM public.save_planning_rich_item(gen_random_uuid(), v_exp, NULL, '{"label":"Taxi","amount_minor":"12"}', NULL);
    RAISE EXCEPTION 'EXPLOIT: a string amount was saved';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  PERFORM public.add_planning_block(v_prog, v_goal, 'progress', '{"mode":"numeric"}', NULL, NULL, NULL);
  BEGIN PERFORM public.save_planning_rich_item(gen_random_uuid(), v_prog, NULL, '{"label":"Bonus"}', NULL);
    RAISE EXCEPTION 'EXPLOIT: a contribution without an amount was saved';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- M9: the server's preview write does not make the couple's next edit stale.
  PERFORM public.add_planning_block(v_link, v_trip, 'link', '{"url":"https://a.example/"}', NULL, NULL, NULL);
  SELECT version INTO v_v FROM public.planning_blocks WHERE id = v_link;
  PERFORM public.set_planning_link_preview(v_link, 'https://a.example/', '{"status":"ok","title":"A"}');
  PERFORM public.update_planning_block(v_link, v_v, '{"url":"https://a.example/","label":"Ours"}', NULL, NULL);

  -- M6: the money history can't be truncated or rewritten, even by the service role.
  IF has_table_privilege('service_role', 'public.planning_expense_events', 'TRUNCATE')
     OR has_table_privilege('service_role', 'public.planning_expense_events', 'UPDATE')
     OR has_table_privilege('service_role', 'public.planning_expense_events', 'DELETE') THEN
    RAISE EXCEPTION 'EXPLOIT: service_role can rewrite the expense audit';
  END IF;
  BEGIN TRUNCATE public.planning_expense_events; RAISE EXCEPTION 'EXPLOIT: the expense audit was truncated';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%append-only%' THEN RAISE; END IF; END;

  -- M4: uploads nobody references are queued for deletion after a day; referenced or fresh ones stay.
  PERFORM public.add_planning_block(v_photo, v_trip, 'photo', '{}', NULL, NULL, NULL);
  v_kept := v_rel || '/' || v_trip || '/kept.jpg';
  v_orphan := v_rel || '/' || v_trip || '/orphan.jpg';
  v_fresh := v_rel || '/' || v_trip || '/fresh.jpg';
  INSERT INTO storage.objects (bucket_id, name, metadata, created_at) VALUES
    ('planning-media', v_kept, '{"mimetype":"image/jpeg","size":10}', now() - interval '3 days'),
    ('planning-media', v_orphan, '{"mimetype":"image/jpeg","size":10}', now() - interval '3 days'),
    ('planning-media', v_fresh, '{"mimetype":"image/jpeg","size":10}', now());
  PERFORM public.add_planning_photo(v_photo, v_kept);
  PERFORM public.planning_v2_purge();
  IF NOT EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE bucket_id = 'planning-media' AND object_name = v_orphan) THEN
    RAISE EXCEPTION 'EXPLOIT: an abandoned upload was not queued';
  END IF;
  IF EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE bucket_id = 'planning-media' AND object_name IN (v_kept, v_fresh)) THEN
    RAISE EXCEPTION 'EXPLOIT: a used or fresh upload was queued';
  END IF;

  RAISE NOTICE 'PASS';
END $$;
ROLLBACK;
