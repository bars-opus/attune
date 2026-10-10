-- Task 5, item 6: the recorded Minors that are a line of SQL each.
--
-- Two changes, both additive:
--   RULING 14  discard_ai_session_nearby_staging gains an EXPLICIT
--              NULL-actor guard as its literal first statement.
--   N5         the consumed_marker survival claim is corrected to what
--              the spec actually requires and the schema actually does.
--
-- Nothing here touches a lock, a lock order, a return shape or a grant.

-- ======================================================================
-- RULING 14: the explicit NULL-actor guard on
-- discard_ai_session_nearby_staging.
--
-- THE GLOBAL CONSTRAINT: "Every SECURITY DEFINER function uses SET
-- search_path = public AND validates its actor parameter non-NULL as
-- its FIRST statement." discard was the one function in the plan
-- satisfying that INDIRECTLY rather than by construction, and Task 1's
-- fix round 1 correctly declined to change it (turning a silent path
-- into a raising one is a behaviour decision, not a lock-order fix).
-- This is that decision, taken on its own.
--
-- WHAT WAS MEASURED BEFORE THE CHANGE. Two distinct paths, both
-- reproduced on a fresh database:
--
--   (a) NULL actor, staging row EXISTS -> RAISES 'Not authenticated',
--       indirectly, from mark_ai_assistant_usage_outcome at the very
--       end of the function. (`v_actor != p_actor_id` is NULL when
--       p_actor_id is NULL, so the requester check falls THROUGH rather
--       than denying -- the staging row is DELETEd and the request row
--       UPDATEd before anything objects. plpgsql's subtransaction
--       rollback undoes both, so the net effect is correct today, but
--       the function performs two writes it had no authority to perform
--       and is saved only by the rollback.)
--
--   (b) NULL actor, NO staging row -> returns SILENTLY. The
--       lock-target lookup finds nothing first and takes the idempotent
--       no-op RETURN, so a NULL actor is never noticed at all.
--
-- THE MESSAGE DOES NOT CHANGE for path (a): it is 'Not authenticated',
-- the same string, now raised directly and as the first statement
-- instead of incidentally after two writes. That is the whole point --
-- the constraint exists so authorization precedes side effects rather
-- than being rolled back after them.
--
-- PATH (b) DOES CHANGE, from a silent return to 'Not authenticated',
-- and that is recorded deliberately rather than engineered around:
--
--   * It is strictly a CALLER BUG, not an authorization outcome. A NULL
--     actor is a service_role caller that failed to resolve its user;
--     there is no actor for whom a silent answer could be the right
--     one.
--   * It discloses NOTHING. The information this function's silence
--     protects is whether a staging row exists, and the new guard fires
--     BEFORE that is looked at -- a NULL actor now gets the identical
--     error whether the row exists or not, which is MORE uniform than
--     before, not less. (This is the opposite of the read RPCs, where
--     silence IS the security property and the actor check must stay a
--     silent RETURN -- see 20260953180000's note on why the shared
--     consent helper never raises.)
--   * No contract asserts the silent-NULL path; verified by grep across
--     supabase/tests before changing it.
--
-- EVERYTHING ELSE IS BYTE-IDENTICAL to 20260953150000, which is Task
-- 1's fix-round lock-order fix. The three locks, their order, their
-- keys, the authoritative re-read under them, the idempotent no-op
-- RETURNs, the requester check, the DELETE/UPDATE pair and the
-- 'succeeded' outcome are untouched. The FOR UPDATE count stays at
-- exactly 2, which the structural contract in
-- ai_session_nearby_staging_contracts.sql asserts.
-- ======================================================================
CREATE OR REPLACE FUNCTION public.discard_ai_session_nearby_staging(
  p_actor_id uuid, p_request_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid;
  v_session_id uuid;
  v_relationship_id uuid;
BEGIN
  -- RULING 14: THE FIRST STATEMENT. Global Constraint: every SECURITY
  -- DEFINER function in this plan validates its actor parameter
  -- non-NULL as its first statement. Before this guard existed, a NULL
  -- actor reached the staging DELETE and the request UPDATE and was
  -- refused only afterwards, by mark_ai_assistant_usage_outcome, with
  -- this same message -- correct by rollback rather than by
  -- construction. The message is unchanged on purpose.
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Lock-target lookup ONLY -- unlocked, and it decides nothing except
  -- which rows to lock and whether there is anything to do at all. The
  -- authorization comparison is NOT made here: it is made on the
  -- re-read under the locks below. This is the same shape
  -- 20260953120000 gave the three completion RPCs, and the same reason
  -- -- the advisory lock needs the relationship id, and the
  -- relationship id is only reachable through the row being discarded.
  --
  -- ai_session_staging.session_id REFERENCES ai_sessions(id) NOT NULL
  -- (20260953020000), so this join is total for any staging row that
  -- exists; a LEFT JOIN would be dead code.
  SELECT st.session_id, se.relationship_id
  INTO v_session_id, v_relationship_id
  FROM public.ai_session_staging st
  JOIN public.ai_sessions se ON se.id = st.session_id
  WHERE st.request_id = p_request_id;

  IF v_session_id IS NULL THEN
    RETURN; -- already discarded/published/expired -- idempotent no-op
  END IF;

  -- LOCK 1: the relationship advisory lock. Task 1 fix round 1's fix.
  -- Without it, this function serialized against nothing -- publish
  -- takes this lock first and discard took no advisory lock at all, so
  -- the two still formed a cycle over the staging and request rows
  -- (14/15 deadlocks at a 1 ms window). Keyed on the RELATIONSHIP, as
  -- every other function in this chain is: a per-session or per-request
  -- key would serialize against none of them and the deadlock would
  -- return.
  PERFORM pg_advisory_xact_lock(hashtext(v_relationship_id::text));

  -- LOCK 2: the session row, before the request row. discard does not
  -- otherwise touch ai_sessions -- it neither updates it nor INSERTs
  -- into a child table, so it takes no implicit FK lock on the parent
  -- either. The lock is taken anyway, and explicitly, so that this
  -- function occupies the documented order at the SAME points as
  -- end_ai_session, purge_ai_session_content and the three completion
  -- RPCs. A participant that skips an element of a lock order is how
  -- the order stops being a total order, which is precisely the defect
  -- 20260953150000 fixed one level up. (Plan Ruling 16: redundant in
  -- isolation, kept on purpose, and the structural contract fails if
  -- someone "optimizes" it away.)
  PERFORM 1 FROM public.ai_sessions WHERE id = v_session_id FOR UPDATE;

  -- LOCK 3: the request row. This is the row publish holds across its
  -- gates while waiting for the staging row, and the row the old body
  -- took SECOND (after the staging DELETE) -- the inversion. Taking it
  -- here, under the advisory lock and after the session row, is what
  -- closes the cycle.
  PERFORM 1 FROM public.ai_session_requests WHERE id = p_request_id FOR UPDATE;

  -- The staging row, re-read AUTHORITATIVELY under all three locks.
  -- Everything this function acts on comes from here, not from the
  -- pre-read: the idempotent-no-op test (a row that vanished while this
  -- transaction waited for the locks is indistinguishable from one that
  -- was never there, and takes the same silent RETURN) and the
  -- requester authorization.
  SELECT requester_id INTO v_actor
  FROM public.ai_session_staging WHERE request_id = p_request_id;
  IF v_actor IS NULL THEN
    RETURN; -- already discarded/published/expired -- idempotent no-op
  END IF;
  IF v_actor != p_actor_id THEN
    RAISE EXCEPTION 'Only the requester may discard their own staged result';
  END IF;

  DELETE FROM public.ai_session_staging WHERE request_id = p_request_id;
  -- Terminal, counted, no partner pair (spec §8.2.2) -- NOT a quota
  -- release. provider_started_at is already set for this request (it
  -- reached 'staged' only via claim_ai_session_dispatch), so this
  -- outcome must remain a counted terminal state, never 'cancelled'/
  -- 'rejected'.
  UPDATE public.ai_session_requests SET state = 'cancelled' WHERE id = p_request_id;
  PERFORM public.mark_ai_assistant_usage_outcome(p_actor_id, p_request_id, 'succeeded', 2::smallint);
END;
$$;
REVOKE ALL ON FUNCTION public.discard_ai_session_nearby_staging(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.discard_ai_session_nearby_staging(uuid, uuid)
  TO service_role;


-- ======================================================================
-- N5: the consumed_marker survival claim, corrected.
--
-- THE FINDING. ai_session_publications.consumed_marker survives the
-- PURGE correctly -- purge_ai_session_content deliberately does not
-- delete from this table, and the contract asserts it. But
-- `session_id` is `REFERENCES ai_sessions(id) ON DELETE CASCADE` and
-- `ai_sessions.relationship_id` is in turn `ON DELETE CASCADE` to
-- relationships, so DELETING A RELATIONSHIP removes the marker --
-- while three derived comments in the plan claim it "must outlive the
-- session" without qualification.
--
-- THE DECISION: FIX THE COMMENTS, NOT THE CASCADE. The spec clause the
-- original comment quotes (§7.1) is specific:
--
--   "Keep a content-free consumed marker through the SESSION LIFETIME
--    even if the message is deleted; message FK may become NULL but
--    must not cascade away the consumed marker."
--
-- Every word of that is satisfied by the schema as built. The clause
-- scopes survival to the SESSION LIFETIME and names exactly ONE FK it
-- forbids cascading -- `message_id`, which is correctly `ON DELETE SET
-- NULL`. It says nothing about the relationship, and relationship
-- deletion is not inside any session's lifetime.
--
-- Cascading away on relationship deletion is also the behaviour the
-- rest of the system requires, so "fixing" the cascade would be a
-- defect in three separate ways:
--
--   1. DELETION IS A PRIVACY GUARANTEE. Deleting a relationship means
--      the couple's shared history is gone. A surviving publications
--      row is a per-request record that a given relationship once sent
--      AI-generated content into its chat -- content-free, but still a
--      durable fact about a relationship the users asked to be
--      forgotten. Retaining it would be the more defensible choice only
--      if something needed it, and nothing does.
--   2. IT WOULD BE UNREACHABLE ANYWAY. Both of this table's other FKs
--      cascade from the same deletion (`request_id` -> ai_session_
--      requests -> ai_sessions), and `session_id`/`request_id` are its
--      PRIMARY KEY. Keeping the row would mean making those columns
--      nullable and dropping the PK -- a schema redesign to retain a
--      boolean nobody can look up.
--   3. THE MARKER'S PURPOSE IS SESSION-SCOPED. It exists so a client
--      can render "already added to chat" for a request within its
--      session, which is why the spec scopes it to the session
--      lifetime. After the relationship is gone there is no client, no
--      chat and no session to render it for.
--
-- So the schema is right and the prose was over-stated. The correction
-- is recorded as real COMMENTs on the table and the column -- not as a
-- migration comment that the next reader has to go find -- so that
-- `\d+ ai_session_publications` tells the truth to whoever looks next.
-- The three over-stated comments in 20260953020000, 20260953090000 /
-- 20260953090100 and 20260953110000 are superseded by these, which the
-- catalog serves.
-- ======================================================================
COMMENT ON TABLE public.ai_session_publications IS
  'Service-only mapping from an AI session request to the ordinary chat message its result was published into. Rows survive the session CONTENT PURGE deliberately: purge_ai_session_content and end_ai_session delete turns, sources, approvals and staging but NOT this table, so consumed_marker outlives the session itself (spec §7.1). Rows DO cascade away when the SESSION ROW or the RELATIONSHIP is deleted (session_id and request_id are both ON DELETE CASCADE and together form the PK). That is correct and intended: spec §7.1 scopes the marker to the session lifetime and forbids exactly one cascade -- message_id, which is ON DELETE SET NULL -- and relationship deletion is a privacy guarantee that must not leave a durable record that a deleted relationship once used AI generation.';

COMMENT ON COLUMN public.ai_session_publications.consumed_marker IS
  'Content-free marker that this request''s result was published into chat, so a client can render "already added" without re-reading the result. Survives message deletion (message_id is ON DELETE SET NULL) and survives the session content purge (this table is deliberately excluded from it). Does NOT survive deletion of the session row or the relationship -- see the table comment; that is per spec §7.1, which scopes the marker to the session lifetime.';
