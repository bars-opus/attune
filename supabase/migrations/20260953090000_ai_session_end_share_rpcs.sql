-- end_ai_session (either-partner-ends, synchronous content purge, no
-- actor recorded) and share_ai_session_turn (adapts the existing Plan A
-- draft/share pipeline to a session-turn source). Spec §5.4, §8.1.
--
-- ======================================================================
-- SUPERSEDED IN PART: a LATER migration re-defines both RPCs below.
--
-- The authoritative definitions of public.end_ai_session and
-- public.share_ai_session_turn, and the GRANT on the latter, are in
--   supabase/migrations/20260953090100_ai_session_end_share_fix.sql
-- (fix round 1), which addressed two Critical review findings:
--
--   F1 -- end_ai_session below cancels an outstanding
--     ai_session_requests row without releasing the matching
--     ai_assistant_usage reservation, so a never-dispatched request's
--     quota was charged forever and no reconciler path could release it.
--     Either partner could burn the creator's whole 24h AI quota with
--     zero provider calls.
--   F2 -- share_ai_session_turn below is granted to `authenticated`
--     while taking its actor as a PARAMETER, which let any logged-in
--     user impersonate another. The grant moved to service_role,
--     matching Plan C's actual caller and Plan B's Task 10 Step 5.
--
-- DO NOT edit either function body below expecting the change to take
-- effect: migrations apply in filename order and 20260953090100 runs
-- after this file, silently overriding whatever is here. A change
-- belongs in a NEW migration sorting after it. See the MIGRATION
-- PROVENANCE block at the end of 20260953090100 for the full map of
-- which file wins for each function in this feature.
--
-- NOTE on "CORRECTION 1" below: this file's re-definition of
-- public.prepare_ai_session (Task 3's function) is NOT superseded and is
-- still authoritative. It is retained deliberately -- reviewed and
-- accepted on the merits -- and Task 3's own migration file carries a
-- pointer comment saying so.
-- ======================================================================

-- ---------------------------------------------------------------------
-- CORRECTION 1: loosen ai_sessions' activated_at invariant to the
-- honest 3-way form.
--
-- Task 1 shipped an anonymous table-level CHECK (Postgres named it
-- `ai_sessions_check`) of the form:
--
--     (state = 'preparing' AND activated_at IS NULL)
--     OR (state != 'preparing' AND activated_at IS NOT NULL)
--
-- That reads as a 2-way invariant but silently constrains THREE states.
-- It forces `closed` to carry an activated_at, which is false for every
-- session that closes without ever having been activated -- a genuinely
-- reachable state in at least two places:
--
--   * Task 3's prepare_ai_session reclaiming an expired `preparing`
--     session to `closed`. It works around the constraint today by
--     stamping a FAKE `activated_at = now()` on a session that was
--     never activated. Task 3's own reviewer called that "acceptable
--     but not clean" and recommended fixing the constraint at the
--     source instead, which is what this block does.
--
--   * end_ai_session below, which may legitimately be called on a
--     session still in `preparing` -- e.g. either partner ending a
--     shared session before the partner ever approved it. Its UPDATE
--     sets state and generation_epoch only, and would otherwise hit
--     exactly the same violation.
--
-- The replacement states the invariant honestly: `preparing` must have
-- no activation timestamp, `active` must have one, and `closed`
-- constrains neither way -- a closed session either genuinely activated
-- (and keeps the real timestamp set at activation) or never did (and
-- keeps NULL). Both are truthful terminal states, and the column stops
-- being a place where a fabricated timestamp has to be written to
-- satisfy a mis-stated rule.
--
-- This is an additive migration that ALTERs an already-shipped
-- constraint, not an edit to Task 1's committed migration file. The
-- replacement is given an explicit name so a future migration never has
-- to guess at a Postgres-assigned one again.
-- Fix round 1 (review finding F7): `IF EXISTS` added. Without it,
-- re-applying this migration to a database that already ran it aborts
-- with `constraint "ai_sessions_check" ... does not exist` -- which is
-- exactly what broke the reviewer's first mutation-testing harness, and
-- what a forward-only migration has no business doing. This is the one
-- in-place edit this fix round makes to an already-committed migration,
-- and it is deliberately confined to re-apply safety: no SQL logic, no
-- constraint definition and no behaviour changes, and the resulting
-- schema is byte-for-byte what this file already produced on a fresh
-- run. An additive migration cannot repair this particular defect,
-- because the defect IS this file aborting before a later migration
-- could run. The companion migration
-- 20260953090100_ai_session_end_share_fix.sql re-asserts the same
-- constraint defensively for the same reason.
ALTER TABLE public.ai_sessions DROP CONSTRAINT IF EXISTS ai_sessions_check;
ALTER TABLE public.ai_sessions DROP CONSTRAINT IF EXISTS ai_sessions_activated_at_state_check;
ALTER TABLE public.ai_sessions ADD CONSTRAINT ai_sessions_activated_at_state_check
  CHECK (
    (state = 'preparing' AND activated_at IS NULL)
    OR (state = 'active' AND activated_at IS NOT NULL)
    OR (state = 'closed')
  );

-- ---------------------------------------------------------------------
-- end_ai_session
--
-- LOCK ORDER (Global Constraints / spec §6.2): relationship advisory
-- lock, THEN the session row lock. This RPC takes
-- pg_advisory_xact_lock(hashtext(relationship_id)) BEFORE its
-- SELECT ... FOR UPDATE, matching admit_ai_session_generation's own
-- documented order exactly (LOCK 1 relationship advisory, LOCK 3
-- session row). This ordering is load-bearing, not defensive style:
-- admit's PRE-checks deliberately read the session row UNLOCKED,
-- justified in its own header by "every mutator of this session (End,
-- source edit, membership change, activation) takes that same
-- relationship lock first per the Global Constraints". End is named in
-- that list. Taking only the row lock here -- as a naive reading of
-- "lock the row you are about to update" produces -- would make this
-- function precisely the non-conforming writer admit's post-lock RAISE
-- fences against, and would let an end land between admit's pre-check
-- and its row lock. Proven by
-- supabase/tests/ai_session_end_admit_concurrent_test.sh.
--
-- The relationship id is resolved with an unlocked read first, purely
-- to know WHICH lock to take (same pattern as admit). A session's
-- relationship_id is immutable, so that read cannot go stale.
CREATE OR REPLACE FUNCTION public.end_ai_session(
  p_actor_id uuid, p_session_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.ai_sessions;
  v_relationship_id uuid;
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT s.relationship_id INTO v_relationship_id
  FROM public.ai_sessions s WHERE s.id = p_session_id;
  IF v_relationship_id IS NULL THEN
    RETURN; -- unknown session: idempotent no-op, same as "already closed"
  END IF;

  -- LOCK 1: the relationship advisory lock (see the header).
  PERFORM pg_advisory_xact_lock(hashtext(v_relationship_id::text));

  -- LOCK 2: the session row itself, re-read authoritatively under both
  -- locks -- a concurrent end for the same session serializes here.
  SELECT * INTO v_session FROM public.ai_sessions
  WHERE id = p_session_id FOR UPDATE;
  IF v_session.id IS NULL THEN
    RETURN;
  END IF;
  IF v_session.state = 'closed' THEN
    RETURN; -- idempotent no-op
  END IF;

  IF v_session.visibility = 'private' THEN
    IF v_session.creator_id != p_actor_id THEN
      RAISE EXCEPTION 'Only the creator may end a private session';
    END IF;
  ELSE
    -- Either CURRENT member of the relationship may end a shared
    -- session (spec §5.4). Membership is read from relationships, not
    -- from who approved, so a partner who never approved can still end
    -- a session opened against them -- which is the whole point of
    -- "either partner ends".
    IF NOT EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = v_session.relationship_id
        AND (r.user_a = p_actor_id OR r.user_b = p_actor_id)
    ) THEN
      RAISE EXCEPTION 'Not a member of this shared session''s relationship';
    END IF;
  END IF;

  -- Fence any in-flight worker FIRST, in the same statement set: an
  -- outstanding request's generation_epoch was captured at admission,
  -- so bumping the session's epoch invalidates every lease that has
  -- not yet committed (spec §6.2's "Completion transaction fences on
  -- ... epoch"). No client-readable ending-actor column exists to set,
  -- and none is added (Global Constraints / spec §5.4): ending is
  -- recorded ONLY as the state transition.
  --
  -- activated_at is deliberately left exactly as it is -- NULL for a
  -- session that never activated, the real timestamp for one that did.
  -- The loosened constraint at the top of this file is what makes that
  -- honest rather than requiring a fabricated value.
  UPDATE public.ai_sessions
  SET state = 'closed', generation_epoch = generation_epoch + 1
  WHERE id = p_session_id;

  -- Any request still outstanding for this session is now unreachable:
  -- its worker token can no longer commit (the epoch moved, and the
  -- session is closed), so mark it terminal rather than leaving a row
  -- that reads as perpetually in-flight. Done BEFORE the content purge
  -- so the turns/staging deletes below cannot be mistaken for the thing
  -- that resolved it.
  UPDATE public.ai_session_requests
  SET state = 'cancelled', terminal_code = 'session_ended'
  WHERE session_id = p_session_id AND state IN ('reserved', 'started', 'staged');

  -- Synchronous purge, SAME transaction (spec §5.4) -- not a later job.
  -- ai_session_publications is deliberately NOT purged: its
  -- consumed_marker must survive the session lifetime (Task 2's own
  -- table comment), and the shared chat messages it points at are
  -- ordinary messages that outlive the session by design.
  DELETE FROM public.ai_session_turns WHERE session_id = p_session_id;
  DELETE FROM public.ai_session_sources WHERE session_id = p_session_id;
  DELETE FROM public.ai_session_approvals WHERE session_id = p_session_id;
  DELETE FROM public.ai_session_staging WHERE session_id = p_session_id;
END;
$$;
REVOKE ALL ON FUNCTION public.end_ai_session(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.end_ai_session(uuid, uuid)
  TO service_role;

-- ---------------------------------------------------------------------
-- share_ai_session_turn: validates the turn, then reuses Plan A's
-- insert_ai_assist_draft + share_ai_assist_draft exactly as the
-- existing long-press flow does -- NOT a reimplementation of message
-- insertion (spec §8.1: "Adapt the existing draft/share integration
-- explicitly to session-answer origin").
--
-- target_message_id is NULL here (a session answer has no single
-- "target message" the way a long-press Assist call does); the existing
-- share_ai_assist_draft already treats a NULL target_message_id as "no
-- target eligibility recheck needed" -- its `IF v_draft.target_message_id
-- IS NOT NULL THEN` guard skips the target-existence check entirely.
--
-- THE JWT CLAIM DANCE, and why it is required rather than incidental:
-- share_ai_assist_draft derives its actor from auth.uid() directly --
-- it is Plan A's CLIENT-callable RPC and predates this plan's
-- explicit-p_actor_id convention. It then enforces
-- `v_draft.requester_id IS DISTINCT FROM v_actor -> 'Draft unavailable'`.
-- So delegating to it without setting request.jwt.claims would mean
-- either (a) an edge function calling as service_role, with no JWT at
-- all, gets auth.uid() = NULL and every share fails with "Not
-- authenticated", or worse (b) p_actor_id is silently ignored in favour
-- of whatever ambient claim happens to be set -- a real
-- confused-deputy bug, since this function has ALREADY authorized
-- p_actor_id against the session above. Setting the claim to the
-- actor this function authorized is what makes p_actor_id actually
-- mean something across the delegation boundary.
--
-- set_config(..., true) is TRANSACTION-local, and the prior value is
-- captured and restored on both the success and the exception path, so
-- this never leaks an impersonation claim into the rest of the caller's
-- transaction. Asserted by Contract 5 in
-- supabase/tests/ai_session_end_share_contracts.sql.
CREATE OR REPLACE FUNCTION public.share_ai_session_turn(
  p_actor_id uuid, p_session_id uuid, p_ordinal int
) RETURNS public.messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.ai_sessions;
  v_turn public.ai_session_turns;
  v_draft_id uuid;
  v_message public.messages;
  v_prior_claims text;
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_session FROM public.ai_sessions WHERE id = p_session_id;
  IF v_session.id IS NULL OR v_session.state != 'active' THEN
    RAISE EXCEPTION 'Session unavailable';
  END IF;

  IF v_session.visibility = 'private' THEN
    IF v_session.creator_id != p_actor_id THEN
      RAISE EXCEPTION 'Only the creator may share from a private session';
    END IF;
  ELSE
    IF NOT EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = v_session.relationship_id
        AND (r.user_a = p_actor_id OR r.user_b = p_actor_id)
    ) THEN
      RAISE EXCEPTION 'Not a member of this shared session''s relationship';
    END IF;
  END IF;

  SELECT * INTO v_turn FROM public.ai_session_turns
  WHERE session_id = p_session_id AND ordinal = p_ordinal;
  IF v_turn.session_id IS NULL THEN
    RAISE EXCEPTION 'Turn not found';
  END IF;
  IF v_turn.role != 'attune' THEN
    RAISE EXCEPTION 'Only an Attune-authored turn may be shared';
  END IF;
  -- Allow-list, not a deny-list: only 'ideas_answer' is postable here.
  -- 'redirect' cannot be posted at all (spec §8.1: "Redirects cannot be
  -- posted"), and 'nearby_result' has its own requester-only publish
  -- path -- a generic share RPC that let ANY member post a Nearby card
  -- would contradict "only the originating requester may post a Nearby
  -- card even after it was published in a shared session".
  IF v_turn.kind != 'ideas_answer' THEN
    RAISE EXCEPTION 'This turn kind cannot be posted to chat: %', v_turn.kind;
  END IF;

  v_draft_id := gen_random_uuid();
  PERFORM public.insert_ai_assist_draft(
    v_draft_id, v_session.relationship_id, p_actor_id, NULL,
    v_turn.payload->>'reply_text',
    jsonb_build_object(
      'schema_version', 1,
      'suggested_planning_item', v_turn.payload->'suggested_planning_item',
      'sources', COALESCE(v_turn.payload->'sources', '[]'::jsonb)
    )
  );

  v_prior_claims := current_setting('request.jwt.claims', true);
  BEGIN
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', p_actor_id::text)::text, true);
    v_message := public.share_ai_assist_draft(v_draft_id);
    PERFORM set_config('request.jwt.claims', COALESCE(v_prior_claims, ''), true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claims', COALESCE(v_prior_claims, ''), true);
    RAISE;
  END;

  INSERT INTO public.ai_session_publications (session_id, request_id, message_id, consumed_marker)
  VALUES (p_session_id, v_turn.request_id, v_message.id, true)
  ON CONFLICT (session_id, request_id) DO NOTHING;

  RETURN v_message;
END;
$$;
-- NOTE ON THIS GRANT: unlike every other RPC in this plan,
-- share_ai_session_turn is granted to `authenticated`, not
-- `service_role`, matching Plan A's share_ai_assist_draft precedent
-- (client-callable through PostgREST). Whether Plan C's edge function
-- should instead be the caller -- which would move this grant to
-- service_role -- is an open design question the brief explicitly
-- leaves for a later task to resolve rather than silently pick a side
-- of here.
REVOKE ALL ON FUNCTION public.share_ai_session_turn(uuid, uuid, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.share_ai_session_turn(uuid, uuid, int)
  TO authenticated;

-- ---------------------------------------------------------------------
-- CORRECTION 1, follow-through: redefine prepare_ai_session WITHOUT the
-- fake activated_at stamp its reclaim path needed under the OLD
-- constraint. This is an additive CREATE OR REPLACE in this task's own
-- migration -- Task 3's committed migration file is untouched. The
-- function body below is byte-identical to Task 3's except for the
-- reclaim UPDATE and its comment.
--
-- Safety of removing the stamp: the ONLY reader of
-- ai_sessions.activated_at anywhere in the codebase is
-- admit_ai_session_generation's expires_at computation
-- (activated_at + interval '60 minutes'), and it reads that value only
-- after asserting state = 'active' -- a state the new constraint still
-- guarantees carries a non-NULL activated_at. No test asserts an
-- activated_at value on a closed-without-activating row. Verified by a
-- full-tree grep of migrations, lib/ and supabase/tests/.
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
  -- transactionally").
  --
  -- CORRECTION 1 follow-through: this UPDATE previously also stamped a
  -- FAKE `activated_at = now()` on a session that was never activated,
  -- purely to satisfy Task 1's original CHECK ("activated_at IS NOT
  -- NULL whenever state != 'preparing'"). Task 3's own reviewer called
  -- that "acceptable but not clean" and recommended fixing the
  -- constraint at the source instead. The loosened 3-way constraint
  -- earlier in this same migration does exactly that, so the fake
  -- timestamp is no longer required -- and is now removed, because
  -- leaving it would keep writing a fabricated activation time onto
  -- sessions that provably never activated. activated_at stays NULL
  -- here, which is the truth.
  UPDATE public.ai_sessions
  SET state = 'closed'
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
