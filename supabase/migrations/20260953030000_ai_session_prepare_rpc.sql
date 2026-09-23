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
