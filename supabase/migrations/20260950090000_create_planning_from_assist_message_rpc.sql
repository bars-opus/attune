-- Converts a shared Assist message's proposal into a real Planning
-- entity, exactly once per message, under concurrent taps from either
-- partner. Spec §5.4.
--
-- DEVIATION FROM THE BRIEF: the brief's own SQL called
-- create_planning_task(v_new_id, relationship_id, title, NULL, NULL,
-- due_date) and upsert_planning_event(v_new_id, relationship_id, title,
-- NULL, event_date) from memory of Planning's signatures. Both RPCs'
-- REAL committed signatures (20260941040000_planning_item_rpcs.sql,
-- 20260941050000_planning_event_and_note_rpcs.sql) are:
--   create_planning_task(p_id, p_relationship_id, p_title, p_note,
--     p_assigned_to, p_due_date) RETURNS planning_items
--   upsert_planning_event(p_id, p_relationship_id, p_title, p_note,
--     p_event_date) RETURNS planning_events
-- which matches the brief's positional order exactly (title in position
-- 3, note in position 4, due/event date last) once the brief's literal
-- SQL is re-checked against the migration files rather than trusted from
-- memory -- no reordering needed here, but this was verified, not
-- assumed, per the dispatch's explicit instruction.
CREATE OR REPLACE FUNCTION public.create_planning_from_assist_message(
  p_message_id uuid, p_edited_title text, p_edited_date date
) RETURNS TABLE (planning_item_id uuid, planning_event_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_message public.messages;
  v_existing_link public.ai_assist_planning_links;
  v_proposal jsonb;
  v_kind text;
  v_new_item public.planning_items;
  v_new_event public.planning_events;
  v_new_id uuid := gen_random_uuid();
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Lock the message row for the duration of this check-then-act
  -- sequence so two partners' concurrent taps serialize here. NOTE: this
  -- lock target (the messages row) is DISJOINT from the row the
  -- idempotency check below reads (ai_assist_planning_links keyed by
  -- message_id) -- unlike Task 6's share_ai_assist_draft, where the
  -- FOR UPDATE and the idempotency check are the SAME row. That
  -- disjointness is exactly Task 4's bug shape UNLESS something else
  -- closes the gap. It is closed here: ai_assist_planning_links.message_id
  -- is the table's PRIMARY KEY (see migration
  -- 20260950010000_ai_assistant_schema.sql), so the INSERT below that
  -- creates the link is itself a unique-constrained write. Two
  -- concurrent transactions both holding the messages FOR UPDATE lock
  -- serially (the second blocks until the first commits/rolls back,
  -- because both lock the SAME messages row) means the second
  -- transaction's own SELECT of ai_assist_planning_links only runs AFTER
  -- the first has committed its INSERT -- so the second transaction's
  -- re-read always observes the first's link if the first succeeded.
  -- This was empirically confirmed with a real two-psql-process
  -- overlapping-transaction test (see task-7-report.md) rather than
  -- relied on by reasoning alone.
  SELECT * INTO v_message FROM public.messages
  WHERE id = p_message_id AND deleted_at IS NULL FOR UPDATE;
  IF v_message.id IS NULL THEN
    RAISE EXCEPTION 'Message unavailable';
  END IF;
  IF v_message.message_origin IS DISTINCT FROM 'attune_assist' THEN
    RAISE EXCEPTION 'Not an Attune Assist message';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = v_message.relationship_id
      AND r.status = 'active' AND r.chat_archived_at IS NULL
      AND (r.user_a = v_actor OR r.user_b = v_actor)
  ) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  SELECT * INTO v_existing_link FROM public.ai_assist_planning_links
  WHERE message_id = p_message_id;
  IF v_existing_link.message_id IS NOT NULL THEN
    RETURN QUERY SELECT v_existing_link.planning_item_id, v_existing_link.planning_event_id;
    RETURN;
  END IF;

  v_proposal := v_message.assistant_payload -> 'suggested_planning_item';
  IF v_proposal IS NULL OR v_proposal = 'null'::jsonb THEN
    RAISE EXCEPTION 'This message has no Planning proposal';
  END IF;
  v_kind := v_proposal ->> 'kind';

  IF v_kind = 'task' THEN
    -- create_planning_task itself btrim()s the title and raises on an
    -- empty result via its NOT NULL/CHECK constraints on
    -- planning_items.title -- do not re-implement that validation here,
    -- so the constraint is enforced once (spec §5.4, brief step 1
    -- contract 7).
    v_new_item := public.create_planning_task(
      v_new_id, v_message.relationship_id,
      COALESCE(p_edited_title, v_proposal ->> 'title'),
      NULL, NULL, p_edited_date
    );
    INSERT INTO public.ai_assist_planning_links
      (message_id, relationship_id, planning_item_id, created_by)
    VALUES (p_message_id, v_message.relationship_id, v_new_item.id, v_actor);
    RETURN QUERY SELECT v_new_item.id, NULL::uuid;
  ELSIF v_kind = 'event' THEN
    v_new_event := public.upsert_planning_event(
      v_new_id, v_message.relationship_id,
      COALESCE(p_edited_title, v_proposal ->> 'title'),
      NULL, COALESCE(p_edited_date, (v_proposal ->> 'event_date')::date)
    );
    INSERT INTO public.ai_assist_planning_links
      (message_id, relationship_id, planning_event_id, created_by)
    VALUES (p_message_id, v_message.relationship_id, v_new_event.id, v_actor);
    RETURN QUERY SELECT NULL::uuid, v_new_event.id;
  ELSE
    RAISE EXCEPTION 'Unknown proposal kind';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.create_planning_from_assist_message(uuid, text, date)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_planning_from_assist_message(uuid, text, date)
  TO authenticated;
