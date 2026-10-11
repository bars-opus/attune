-- Plan C Task 5, ITEM A1 (user Ruling 17): the `include_window` TOGGLE.
--
-- Spec §4.3: "Window is default off; ENABLING IT IN PREPARING STATE
-- INVALIDATES APPROVALS AND INCREMENTS REVISION."
--
-- Plan C Task 3's 20260953200200 built the substrate -- the
-- ai_sessions.include_window column and the source_role = 'window' rows
-- -- and recorded (Ruling 17) that the behaviour above had no UPDATE
-- path at all. prepare_ai_session can only SET the window at creation;
-- nothing could change it afterwards, so §4.3's sentence described a
-- transition no code could perform. This migration is that transition.
--
-- ======================================================================
-- THIS MIGRATION SUPERSEDES NOTHING. Established by grep over
-- supabase/, lib/ and docs/, not assumed:
--
--   grep -rn 'set_ai_session_include_window' supabase/ lib/ docs/
--     -> 0 files before this one
--
-- public.set_ai_session_include_window is a NEW function. This file
-- re-defines NO existing function: not prepare_ai_session, not
-- approve_ai_session_context, not activate_ai_session, not
-- admit_ai_session_generation, not end_ai_session, not either read RPC.
-- It adds no column and no constraint.
--
-- CONSEQUENCE FOR THE SUPERSESSION CONTRACT:
-- supabase/tests/ai_session_read_authorization_contracts.sql Contract 9
-- asserts live bodies against supersession reverts and reports "12
-- superseded definitions". That count is UNCHANGED by this file,
-- because this file creates nothing that was previously defined
-- elsewhere. No marker in Contract 9 needed updating, and none was.
--
-- ======================================================================
-- WHAT "INVALIDATES APPROVALS" MEANS HERE, AND WHY IT IS TWO THINGS.
--
-- Clearing approvals must make a stale approval UNUSABLE, not merely
-- ABSENT -- a DELETE alone would be undone by any client that still
-- holds the old (revision, digest) pair and re-submits it, because
-- approve_ai_session_context's ON CONFLICT DO NOTHING would happily
-- re-insert the identical row and activate_ai_session would then accept
-- it. So this function does BOTH, and the revision bump is the
-- load-bearing half:
--
--   1. ai_sessions.revision = revision + 1.
--      approve_ai_session_context matches `state = 'preparing' AND
--      revision = p_revision`, and activate_ai_session matches
--      `v_session.revision != p_revision -> RAISE 'Revision mismatch'`
--      and then COUNTS approvals `WHERE revision = p_revision`. So
--      after a bump, a client replaying the OLD revision is refused by
--      approve (no row at that revision in that state) and refused by
--      activate (revision mismatch), while a client submitting the NEW
--      revision has no approvals at it yet -> APPROVAL_REQUIRED. Both
--      doors are closed by the same integer.
--
--   2. DELETE FROM ai_session_approvals WHERE session_id = ...
--      Not strictly required for correctness given (1) -- rows at the
--      old revision can never be counted again, since nothing ever
--      sets ai_sessions.revision backwards (every writer is `+ 1`;
--      verified by grep: no `SET revision = ` assignment in the schema
--      decreases it). It is done anyway for two reasons that are not
--      hygiene: the stale rows carry the DIGEST of a context snapshot
--      the user has just changed, i.e. content-describing material for
--      a snapshot that no longer exists, and §4.3's own word is
--      "invalidates", which a reader checking this table should be able
--      to see rather than infer from an integer two tables away.
--
-- ======================================================================
-- THE `active`-STATE DECISION, which the brief asked to be decided and
-- justified rather than assumed.
--
-- CALLED ON AN ACTIVE SESSION, THIS FUNCTION REFUSES -- it raises
-- 'Session is not preparing', and changes nothing.
--
-- It does NOT silently no-op, and it does NOT toggle. Three reasons,
-- in the order they bind:
--
--   (a) §4.3 scopes the behaviour to the preparing state by its own
--       words ("enabling it IN PREPARING STATE"), and §4.2 is the
--       reason: "Persist source IDs, versions and snapshot time, NOT
--       NEW SELECTIONS ON SUBSEQUENT TURNS." An active session's
--       context is FROZEN -- context_revision was set at activation and
--       every dispatch revalidates against those exact rows (Ruling
--       13). Rewriting the 'window' rows of an active session would
--       substitute new messages into a snapshot both partners already
--       approved, which is precisely what §4.2 forbids and what §4.3's
--       edit/tombstone rule treats as grounds to TERMINATE the session.
--
--   (b) A no-op would be worse than a refusal, and this is the real
--       choice being made. A client that believes it switched the
--       window on would get HTTP 200 and then generate turns over a
--       context without it -- the partner's chat text silently absent
--       from, or silently present in, a session the user thinks they
--       configured. A loud refusal tells the client to end the session
--       and prepare a new one, which is the only correct remedy given
--       (a). The same reasoning the edge function already applies to a
--       location on an Ideas session ("a client that believes it sent a
--       location must not be told it worked").
--
--   (c) The refusal is NOT an information leak, because it comes AFTER
--       authorization. The membership gate runs first, so a non-member
--       and an unknown session both get 'Session unavailable' -- §3.1's
--       indistinguishable response -- and only an authorized member of
--       a real session can ever observe the state-specific message.
--       The edge function maps it to UNAVAILABLE anyway.
--
-- The toggle is also deliberately IDEMPOTENT on a no-change call: a
-- caller asking to enable a window that is already enabled gets a
-- successful return with changed = false, and NOTHING is bumped or
-- cleared. §4.3 ties the invalidation to a CHANGE, and a client
-- re-sending its current state (a double-tap, a retry) must not
-- destroy approvals the partner already gave. This is the one case
-- where a no-op is right, because the caller's belief about the
-- resulting state is correct.
--
-- ======================================================================
-- WHY THE CALLER SUPPLIES THE MESSAGE IDS AND THE TEXT IS RE-READ.
--
-- Identical to 20260953200200's reasoning, and deliberately the same
-- shape so the two write paths cannot diverge:
--
--   * SELECTION STAYS IN TYPESCRIPT. The §4.2 pipeline (filter, limit
--     six, clip each to 600 scalars, take the newest fitting 2,400
--     total, order chronologically) is implemented, deterministic and
--     tested in supabase/functions/_shared/ai_session_context.ts
--     (selectSharedWindow). Re-implementing it in SQL would create a
--     SECOND selection implementation, and §4.3's approval mechanism
--     depends on two separate calls computing the IDENTICAL digest over
--     the IDENTICAL sources. This function PERSISTS what the caller
--     selected; it does not select.
--
--   * THE TEXT IS NEVER ACCEPTED FROM THE CALLER. This is SECURITY
--     DEFINER, so a caller-supplied snippet would let any caller store
--     an arbitrary string as an "approved" source and have both
--     partners approve a digest over text that never appeared in the
--     chat. The rows are written by `INSERT ... SELECT left(m.content,
--     4000) FROM public.messages m WHERE ... AND m.relationship_id =
--     v_session.relationship_id`, byte-for-byte the form
--     prepare_ai_session uses, and THE relationship_id PREDICATE IS THE
--     AUTHORIZATION BOUNDARY -- it is what stops a caller aiming
--     p_window_message_ids at another couple's messages.
--
--   * source_version is COALESCE(m.edited_at, m.created_at), matching
--     20260953200200's defect-A2 fix for both roles. created_at alone
--     never moves on an edit, so a row stored any other way could not
--     support §4.3's source-version revalidation, and would disagree
--     with ai_session_context.ts's live window.
--
-- 'target' SOURCE ROWS ARE NOT TOUCHED. The DELETE below is scoped
-- `AND source_role = 'window'`. The target was chosen at prepare time
-- and is not part of the window (§4.2 item 3 EXCLUDES it from the
-- window), so a window toggle must not disturb it. A toggle that
-- dropped the target would silently change what the user selected.
--
-- ======================================================================
-- LOCK ORDER: A PREFIX, WHICH THE BRIEF PERMITS.
--
-- The plan's fixed order is
--   relationship advisory lock
--     -> quota advisory lock (inside reserve_ai_assistant_quota)
--     -> session row FOR UPDATE
--     -> request row.
--
-- This function takes elements 1 and 3, in that order, and NOTHING
-- else:
--   LOCK 1  pg_advisory_xact_lock(hashtext(v_relationship_id::text))
--   LOCK 2  SELECT ... FROM public.ai_sessions ... FOR UPDATE
--
-- It reserves no quota (so it never reaches the quota advisory lock)
-- and it touches no ai_session_requests row (a preparing session has
-- none -- admit_ai_session_generation refuses `state != 'active'`, so
-- no request can exist for a session in the only state this function
-- operates on). Taking a strict prefix in order cannot participate in a
-- cycle with a function taking the full order.
--
-- THE STRUCTURAL SWEEP STILL RETURNS ZERO. That sweep (see
-- supabase/tests/ai_session_nearby_staging_contracts.sql's Contract on
-- discard's lock order) enumerates functions locking or writing two or
-- more of the three session row-classes -- ai_sessions,
-- ai_session_requests, ai_session_staging -- WITHOUT the relationship
-- advisory lock. This function touches exactly ONE of those three
-- (ai_sessions) and takes the advisory lock anyway, so it is not a
-- candidate on either leg. ai_session_sources and ai_session_approvals
-- are not row-classes in that sweep, and both are written here only
-- under both locks above.
--
-- The advisory lock is NOT optional even though the session row lock
-- alone would serialize two concurrent toggles: it is what serializes
-- this function against prepare_ai_session (which takes the
-- relationship advisory lock and can CLOSE this actor's expired
-- preparing sessions) and against end_ai_session (advisory lock ->
-- session row -> request rows). A toggle that skipped element 1 would
-- be the same partial-order defect 20260953150000 fixed for discard.
--
-- ======================================================================
-- NO RAW PENDING INSTRUCTION, CONTEXT OR LOCATION IS WRITTEN. This
-- function writes exactly two things: ai_sessions.include_window /
-- revision, and ai_session_sources rows whose text is re-read
-- server-side from public.messages -- the same durable chat content
-- prepare_ai_session already clips there. No new column, no instruction,
-- no coordinate.
-- ======================================================================
CREATE OR REPLACE FUNCTION public.set_ai_session_include_window(
  p_actor_id uuid,
  p_session_id uuid,
  p_include_window boolean,
  p_window_message_ids uuid[]
) RETURNS TABLE (changed boolean, revision int, include_window boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_relationship_id uuid;
  v_session public.ai_sessions;
  v_include_window boolean;
  v_window_ids uuid[];
  v_target_message_id uuid;
  v_new_revision int;
BEGIN
  -- THE LITERAL FIRST STATEMENT. Global Constraint / Ruling 14: every
  -- SECURITY DEFINER function in this plan validates its actor
  -- parameter non-NULL before it resolves a relationship, takes a lock
  -- or touches a row. The message matches every other RPC in the plan.
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Normalized BEFORE any work, so every use below reads one value.
  -- NULL is "off", matching §4.3's "default off" and
  -- prepare_ai_session's own COALESCE.
  v_include_window := COALESCE(p_include_window, false);
  -- A caller passing no array is passing an EMPTY window, not a NULL
  -- one. Duplicates collapsed, NULLs dropped -- the NULL filter is load
  -- bearing (source_message_id is NOT NULL, so a NULL element would
  -- abort the INSERT); the DISTINCT is defence in depth for the same
  -- measured reason 20260953200200 records (the join is on messages'
  -- primary key, so a repeat already matches once).
  v_window_ids := ARRAY(
    SELECT DISTINCT x
    FROM unnest(COALESCE(p_window_message_ids, ARRAY[]::uuid[])) AS x
    WHERE x IS NOT NULL
  );

  -- Cheap shape refusals, before the locks. §4.2's "limits six", and
  -- the contradiction prepare_ai_session refuses by the same words.
  IF cardinality(v_window_ids) > 6 THEN
    RAISE EXCEPTION 'At most six window messages';
  END IF;
  IF NOT v_include_window AND cardinality(v_window_ids) > 0 THEN
    RAISE EXCEPTION 'Window messages supplied with p_include_window false';
  END IF;

  -- Lock-target lookup ONLY -- unlocked, decides nothing but which rows
  -- to lock. Same shape 20260953120000 gave the completion RPCs and
  -- 20260953150000 gave discard: the advisory lock needs the
  -- relationship id, and the relationship id is only reachable through
  -- the session row.
  SELECT s.relationship_id INTO v_relationship_id
  FROM public.ai_sessions s WHERE s.id = p_session_id;
  IF v_relationship_id IS NULL THEN
    -- §3.1: an unknown session and a foreign one are the SAME response.
    RAISE EXCEPTION 'Session unavailable';
  END IF;

  -- LOCK 1: the relationship advisory lock. Element 1 of the fixed
  -- order; see the header on why a prefix is still a total order and
  -- why skipping this would not be.
  PERFORM pg_advisory_xact_lock(hashtext(v_relationship_id::text));

  -- LOCK 2: the session row, re-read AUTHORITATIVELY under both locks.
  -- Everything decided below comes from THIS read, not the pre-read: a
  -- session that was closed, activated or reclaimed while this
  -- transaction waited for the locks must be judged in its new state.
  SELECT * INTO v_session FROM public.ai_sessions
  WHERE id = p_session_id FOR UPDATE;
  IF v_session.id IS NULL THEN
    RAISE EXCEPTION 'Session unavailable';
  END IF;

  -- AUTHORIZATION BEFORE STATE, deliberately, and in this order for the
  -- reason checkEligibility documents at the edge: reversing them would
  -- tell a non-member "that session is already active", confirming a
  -- session exists on a relationship they are not in. A non-member and
  -- an unknown id get the identical 'Session unavailable'.
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = v_session.relationship_id
      AND r.status = 'active' AND r.chat_archived_at IS NULL
      AND (r.user_a = p_actor_id OR r.user_b = p_actor_id)
  ) THEN
    RAISE EXCEPTION 'Session unavailable';
  END IF;

  -- §4.3 scopes this transition to the preparing state, and §4.2
  -- forbids new selections on an activated session's frozen snapshot.
  -- See the header's `active`-state decision: a REFUSAL, not a no-op.
  IF v_session.state != 'preparing' THEN
    RAISE EXCEPTION 'Session is not preparing';
  END IF;
  -- §5.1: "Server read-time expiry is authoritative even before
  -- cleanup." A session past its preparation deadline is not
  -- configurable.
  IF v_session.preparation_deadline <= now() THEN
    RAISE EXCEPTION 'Session unavailable';
  END IF;

  -- §4.1: only a shared Ideas session has a recent window. Refused here
  -- as well as at the edge, because the
  -- ai_sessions_window_only_shared_ideas CHECK would otherwise be the
  -- thing reporting it, as a raw 23514 the caller cannot act on.
  IF v_include_window
     AND NOT (v_session.kind = 'ideas' AND v_session.visibility = 'shared') THEN
    RAISE EXCEPTION 'A recent window requires a shared Ideas session';
  END IF;

  -- IDEMPOTENT NO-CHANGE CALL. §4.3 ties invalidation to a CHANGE; a
  -- client re-sending the state the session already has (a double-tap,
  -- a retry) must not destroy an approval its partner already gave.
  --
  -- "No change" means the SETTING is unchanged AND, when the window is
  -- on, the requested id set matches what is already stored. The second
  -- half matters: re-enabling an already-on window with a DIFFERENT
  -- selection is a real context change and must invalidate, even though
  -- the boolean did not move.
  IF v_session.include_window = v_include_window
     AND (
       NOT v_include_window
       OR v_window_ids = ARRAY(
            SELECT src.source_message_id
            FROM public.ai_session_sources src
            WHERE src.session_id = p_session_id
              AND src.source_role = 'window'
            ORDER BY src.source_message_id
          )
     ) THEN
    RETURN QUERY SELECT false, v_session.revision, v_session.include_window;
    RETURN;
  END IF;

  -- §4.2 item 3: "excluding the selected target". A target that also
  -- appeared in the window would collide on ai_session_sources' primary
  -- key. The target is read from the STORED row, not from the caller --
  -- it was frozen at prepare time and this function must not be able to
  -- change it.
  SELECT src.source_message_id INTO v_target_message_id
  FROM public.ai_session_sources src
  WHERE src.session_id = p_session_id AND src.source_role = 'target';
  IF v_target_message_id IS NOT NULL
     AND v_target_message_id = ANY (v_window_ids) THEN
    RAISE EXCEPTION 'The selected target cannot also be a window message';
  END IF;

  -- ---- THE TRANSITION, all of it under both locks ------------------

  -- Rewrite the 'window' rows. DELETE-then-INSERT rather than a merge:
  -- the new selection is authoritative and a row no longer selected
  -- must not survive. SCOPED TO source_role = 'window' -- the 'target'
  -- row is not part of the window and is not touched.
  DELETE FROM public.ai_session_sources
  WHERE session_id = p_session_id AND source_role = 'window';

  IF v_include_window AND cardinality(v_window_ids) > 0 THEN
    -- Text and version RE-READ SERVER-SIDE, never accepted from the
    -- caller, under the relationship_id predicate that is the
    -- authorization boundary. Byte-identical in form to
    -- prepare_ai_session's own 'window' insert, deliberately.
    --
    -- Silently skips an id that is not an eligible live message in THIS
    -- relationship -- exactly as prepare does. A deleted or foreign id
    -- narrows the window instead of failing the toggle; §4.3's
    -- revalidation at activation is what refuses a session whose
    -- sources moved, and review_context shows both partners what is
    -- actually stored before either approves.
    INSERT INTO public.ai_session_sources (
      session_id, source_message_id, source_version,
      approved_clipped_text, source_role
    )
    SELECT p_session_id, m.id, COALESCE(m.edited_at, m.created_at),
           left(m.content, 4000), 'window'
    FROM public.messages m
    WHERE m.id = ANY (v_window_ids)
      AND m.deleted_at IS NULL
      AND m.relationship_id = v_session.relationship_id;
  END IF;

  -- INVALIDATE THE APPROVALS -- both halves. See the header: the
  -- revision bump is what makes a stale approval UNUSABLE (approve
  -- matches on revision, activate matches on revision and counts
  -- approvals at it), and the DELETE is what makes it ABSENT so the
  -- digest of a snapshot that no longer exists is not left lying in the
  -- table.
  DELETE FROM public.ai_session_approvals WHERE session_id = p_session_id;

  UPDATE public.ai_sessions
  SET include_window = v_include_window,
      revision = public.ai_sessions.revision + 1
  WHERE id = p_session_id
  RETURNING public.ai_sessions.revision INTO v_new_revision;

  -- The new revision is DISCLOSED so the caller can re-review and
  -- re-approve against it without a second round trip, the same way
  -- 20260953170000 made commit/publish disclose session_revision
  -- (Ruling 1's sanctioned polling mechanism). Disclosing it is safe:
  -- the caller is an authorized member of a preparing session it just
  -- reconfigured, and the integer describes a change the caller itself
  -- caused.
  RETURN QUERY SELECT true, v_new_revision, v_include_window;
END;
$$;

REVOKE ALL ON FUNCTION public.set_ai_session_include_window(uuid, uuid, boolean, uuid[])
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_ai_session_include_window(uuid, uuid, boolean, uuid[])
  TO service_role;

COMMENT ON FUNCTION public.set_ai_session_include_window(uuid, uuid, boolean, uuid[]) IS
  'Spec 4.3''s window toggle: flips ai_sessions.include_window, rewrites the '
  'source_role = ''window'' rows from caller-chosen message ids whose text and '
  'version are RE-READ from public.messages under a relationship_id predicate '
  '(never accepted from the caller -- this is SECURITY DEFINER), deletes every '
  'ai_session_approvals row and increments ai_sessions.revision so a stale '
  'approval is UNUSABLE and not merely absent. PREPARING STATE ONLY: an active '
  'session RAISES ''Session is not preparing'' rather than no-opping, because '
  'spec 4.2 forbids new selections against a frozen snapshot and a silent no-op '
  'would let a client generate over a context it believes it configured. A '
  'no-change call (same setting, same id set) is idempotent and invalidates '
  'nothing. Selection itself stays in ai_session_context.ts''s selectSharedWindow '
  '-- two selection implementations that must agree forever is what 4.3''s '
  'two-partner digest equality cannot survive. Lock order: relationship advisory '
  'lock, then the session row FOR UPDATE -- a strict prefix of the plan''s fixed '
  'order, holding exactly one of the three session row-classes.';
