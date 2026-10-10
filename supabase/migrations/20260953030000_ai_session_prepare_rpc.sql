-- ======================================================================
-- SUPERSEDED: a LATER migration re-defines prepare_ai_session.
--
-- The authoritative definition of public.prepare_ai_session is in
--   supabase/migrations/20260953090000_ai_session_end_share_rpcs.sql
-- (Task 9, "CORRECTION 1"), which CREATE OR REPLACEs it to remove the
-- fake `activated_at = now()` that the expired-slot reclaim UPDATE
-- below needed only to satisfy Task 1's original 2-way CHECK on
-- ai_sessions. Task 9 loosened that CHECK to the honest 3-way form, so
-- the fabricated timestamp became unnecessary -- and untrue, since the
-- reclaimed session provably never activated. Task 9's reviewer
-- verified the safety argument: the only reader of
-- ai_sessions.activated_at anywhere is admit_ai_session_generation's
-- expires_at computation, which runs only after asserting
-- state = 'active', a state the 3-way constraint still guarantees
-- carries a non-NULL activated_at.
--
-- DO NOT edit the function body below expecting the change to take
-- effect: on any rebuild, migrations apply in filename order and
-- 20260953090000 runs last, silently overriding whatever is here.
-- A change to prepare_ai_session belongs in a NEW migration sorting
-- after 20260953090100 (this plan's additive-migrations discipline,
-- established by Task 6's fix round). See the MIGRATION PROVENANCE
-- block at the end of 20260953090100_ai_session_end_share_fix.sql for
-- the full map of which file wins for each function in this feature.
--
-- This file is left byte-identical in its SQL as the historical record
-- of what Task 3 shipped; only this comment was added (fix round 1 for
-- Task 9, review finding F4).
-- ======================================================================
-- prepare_ai_session: idempotent, slot-limited session creation.
-- Spec §3.2. Lock order: relationship advisory lock, then no further
-- row lock is needed here (this RPC only ever touches ai_sessions rows
-- it is about to insert, or reclaims one via UPDATE under the same
-- relationship lock, which already serializes against a concurrent
-- prepare for the same relationship).
CREATE OR REPLACE FUNCTION public.prepare_ai_session(
  p_actor_id uuid,
  p_idempotency_key uuid,
  p_relationship_id uuid,
  p_kind text,
  p_visibility text,
  p_target_message_id uuid,
  p_include_window boolean
) RETURNS TABLE (session_id uuid, revision int, created boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing_session uuid;
  v_new_session uuid;
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_kind NOT IN ('ideas', 'nearby') THEN
    RAISE EXCEPTION 'Invalid kind';
  END IF;
  IF p_visibility NOT IN ('private', 'shared') THEN
    RAISE EXCEPTION 'Invalid visibility';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = p_relationship_id AND r.status = 'active' AND r.chat_archived_at IS NULL
      AND (r.user_a = p_actor_id OR r.user_b = p_actor_id)
  ) THEN
    RAISE EXCEPTION 'Relationship unavailable';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_relationship_id::text));

  -- Idempotent replay: an idempotency key is scoped to (actor, key) --
  -- storing it would need its own column; simplest correct approach
  -- for this task is to key it into the operation_fingerprint-style
  -- lookup via a dedicated lookup table. To keep this RPC self-contained
  -- without a new table, reuse ai_sessions.id itself as the idempotency
  -- key when the caller supplies one that already resolves to an
  -- existing row for this actor -- i.e. the CALLER is responsible for
  -- reusing the same p_idempotency_key value as a candidate session_id
  -- on retry. This mirrors share_ai_assist_draft's own "the id IS the
  -- idempotency key" pattern (Plan A's ai_assist_drafts.id).
  SELECT id INTO v_existing_session FROM public.ai_sessions WHERE id = p_idempotency_key;
  IF v_existing_session IS NOT NULL THEN
    IF (SELECT creator_id FROM public.ai_sessions WHERE id = v_existing_session) != p_actor_id THEN
      RAISE EXCEPTION 'Idempotency key already used by a different actor';
    END IF;
    RETURN QUERY SELECT v_existing_session, s.revision, false
    FROM public.ai_sessions s WHERE s.id = v_existing_session;
    RETURN;
  END IF;

  -- Reclaim any of THIS actor's own expired preparing sessions before
  -- checking the slot limit (spec §3.2: "reclaim expired slots
  -- transactionally"). ai_sessions' own CHECK constraint requires
  -- activated_at IS NOT NULL whenever state != 'preparing', so the
  -- reclaim must stamp activated_at here too -- it is not a real
  -- activation, just the timestamp that satisfies the invariant for a
  -- session that is being closed without ever having been admitted.
  UPDATE public.ai_sessions
  SET state = 'closed', activated_at = now()
  WHERE creator_id = p_actor_id AND relationship_id = p_relationship_id
    AND state = 'preparing' AND preparation_deadline < now();

  IF p_visibility = 'private' THEN
    IF EXISTS (
      SELECT 1 FROM public.ai_sessions
      WHERE creator_id = p_actor_id AND relationship_id = p_relationship_id
        AND visibility = 'private' AND state IN ('preparing', 'active')
    ) THEN
      RAISE EXCEPTION 'A private session is already pending or active for this creator';
    END IF;
  ELSE
    IF EXISTS (
      SELECT 1 FROM public.ai_sessions
      WHERE relationship_id = p_relationship_id
        AND visibility = 'shared' AND state IN ('preparing', 'active')
    ) THEN
      RAISE EXCEPTION 'A shared session is already pending or active for this relationship';
    END IF;
  END IF;

  v_new_session := p_idempotency_key;
  INSERT INTO public.ai_sessions (
    id, relationship_id, creator_id, kind, visibility, state,
    revision, context_revision, generation_epoch, attempt_count,
    preparation_deadline
  ) VALUES (
    v_new_session, p_relationship_id, p_actor_id, p_kind, p_visibility, 'preparing',
    1, 0, 0, 0, now() + interval '5 minutes'
  );

  IF p_target_message_id IS NOT NULL THEN
    INSERT INTO public.ai_session_sources (session_id, source_message_id, source_version, approved_clipped_text, source_role)
    SELECT v_new_session, m.id, m.created_at, left(m.content, 4000), 'target'
    FROM public.messages m
    WHERE m.id = p_target_message_id AND m.deleted_at IS NULL
      AND m.relationship_id = p_relationship_id;
  END IF;

  RETURN QUERY SELECT v_new_session, 1, true;
END;
$$;
REVOKE ALL ON FUNCTION public.prepare_ai_session(uuid, uuid, uuid, text, text, uuid, boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_ai_session(uuid, uuid, uuid, text, text, uuid, boolean)
  TO service_role;
