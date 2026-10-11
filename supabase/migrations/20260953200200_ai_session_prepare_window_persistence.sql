-- Plan C Task 3, ITEM A: the Plan B migration that gives spec §4.3's
-- window toggle an actual substrate, makes the stored source version
-- able to detect an edit, and gives the slot-limit refusal an ERRCODE.
--
-- Spec §4.2 ("Optional shared window: up to six eligible messages AS OF
-- PREPARE TIME... Persist source IDs, versions and snapshot time, not
-- new selections on subsequent turns") and §4.3 ("Window is default
-- off; enabling it in preparing state invalidates approvals and
-- increments revision").
--
-- ======================================================================
-- THIS MIGRATION SUPERSEDES ONE EARLIER MIGRATION.
--
-- It re-defines, by CREATE OR REPLACE:
--
--   * public.prepare_ai_session
--       -- pre-this-file winner: 20260953090000 (Plan B Task 9's
--          "CORRECTION 1, follow-through" block), which won over Task
--          3's original 20260953030000.
--
-- Established by grep over supabase/migrations/, not assumed. The six
-- files naming prepare_ai_session are:
--
--   20260953030000  CREATE OR REPLACE  -- original, SUPERSEDED (its own
--                                         header says so)
--   20260953090000  CREATE OR REPLACE  -- the pre-this-file WINNER
--   20260953090100  comment only ("that function's authoritative ...")
--   20260953100100  comment only (names its expired-slot close path)
--   20260953140000  comment only (a lifecycle table)
--   20260953170000  comment only (notes it returns the INITIAL revision)
--
-- so exactly two files define it and 20260953090000 sorted last. THIS
-- FILE now wins over both. The three defects below are all in
-- 20260953090000's body; per this plan's additive-migrations
-- discipline, that committed file is left byte-for-byte alone.
--
-- It re-defines NOTHING ELSE. In particular it does NOT touch
-- approve_ai_session_context, activate_ai_session,
-- admit_ai_session_generation, end_ai_session,
-- purge_ai_session_content or any of the staging/commit RPCs.
--
-- ======================================================================
-- SIGNATURE CHANGE: this file ADDS a parameter, so it creates a NEW
-- overload rather than replacing the old one in place. The 7-argument
-- form is therefore DROPPED after the 8-argument form is created, so
-- there is exactly one prepare_ai_session and no resolution ambiguity
-- for a PostgREST caller that omits the new argument. Dropping an
-- overload is additive at the migration level (this file is new; no
-- committed file's logic is edited) and safe here because the sole
-- grantee is service_role and the sole caller is Plan C's edge
-- function, updated in the same commit. Verified by grep: no .sql
-- outside supabase/migrations/ and no Dart/lib code calls it.
--
-- ======================================================================
-- DEFECT A1 -- p_include_window IS ACCEPTED AND COMPLETELY IGNORED.
--
-- Verified from the live catalog, not from reading the file:
--
--   SELECT pg_get_function_arguments(oid) ... -> includes
--     "p_include_window boolean"
--   SELECT (length(prosrc) - length(replace(prosrc,'p_include_window','')))/16
--     -> 0
--   SELECT prosrc ~ '''window''' -> false
--
-- The body writes only 'target' source rows. So there was NO durable
-- record of whether a session has a window, and §4.3's "enabling it in
-- preparing state invalidates approvals and increments revision" had
-- nothing to be a property OF.
--
-- THE REPRESENTATION, AND WHY. Both halves, not one:
--
--   (a) ai_session_sources rows with source_role = 'window'. The
--       schema already anticipated exactly this -- 20260953010000's
--       CHECK is `source_role IN ('target','window')` and its own
--       comment reads "'window' (one of the up-to-6 shared-window
--       messages)". Plan B designed for these rows and never wrote
--       them. They are REQUIRED and not optional: spec §4.3's digest
--       binds "source versions", and its revalidation at "activation
--       and every dispatch, commit and share" compares the frozen
--       PER-SOURCE version against the live message. A boolean alone
--       carries neither, so a boolean alone cannot support §4.3.
--
--   (b) ai_sessions.include_window boolean NOT NULL DEFAULT false --
--       added by this migration. This is the TOGGLE'S OWN STATE while
--       the session is `preparing`, which is a DIFFERENT fact from the
--       frozen snapshot in (a). Three cases the source rows cannot
--       distinguish and §4.3 needs distinguished:
--         - window ON but the civil day legitimately holds zero
--           eligible messages -> zero 'window' rows, yet the window IS
--           on. Under (a) alone this is byte-identical to window OFF,
--           so review_context would show "no window" for a session the
--           user switched on, and a later toggle to OFF would
--           correctly NOT invalidate approvals that were taken with it
--           ON.
--         - "default off" (§4.3's words) needs a default to BE off;
--           absence-of-rows is an inference, not a stored default.
--         - the toggle is what §4.3 says invalidates approvals when it
--           changes. Comparing a boolean is a comparison; comparing
--           "did the set of window rows change" conflates a user
--           toggling the window with the day's messages moving
--           underneath it, which is the OTHER §4.3 rule (source
--           revalidation) and has a different remedy.
--
--   This is precisely the "if you conclude a boolean column is needed
--   AS WELL, say so with reasoning and add it -- but do not drop the
--   'window' rows" case. Both are here.
--
-- WHY THE CALLER SUPPLIES THE IDS (p_window_message_ids) AND THIS
-- FUNCTION DOES NOT SELECT THEM.
--
-- The §4.2 selection pipeline -- filter, then limit six, then clip each
-- to 600 scalars, then take the newest entries fitting 2,400 total,
-- clipping the final entry, then order chronologically -- is already
-- implemented, deterministic and tested end to end in TypeScript:
-- supabase/functions/_shared/ai_session_context.ts
-- (selectSharedWindow / selectWindowFromRows), 24 passing tests.
-- Re-implementing it in SQL would create a SECOND selection
-- implementation, and §4.3's whole approval mechanism depends on two
-- separate calls (one per partner) computing the IDENTICAL digest over
-- the IDENTICAL sources. Two implementations that must agree forever is
-- the exact failure mode this plan's Global Constraints forbid. So this
-- migration's job is PERSISTENCE of what the caller selected, not
-- selection.
--
-- The clipped text is NOT taken from the caller either -- see
-- "WHY THE TEXT IS RE-READ" below. The caller supplies only WHICH
-- messages, which it must do because the budget/clipping decision that
-- picks them is the TypeScript module's.
--
-- WHY THE TEXT IS RE-READ FROM public.messages RATHER THAN ACCEPTED.
-- Accepting caller-supplied snippet text would let a caller store any
-- string as an "approved" source and have both partners approve a
-- digest over text that never appeared in the chat. left(m.content,
-- 4000) matches what the 'target' row has always done, so the stored
-- rows remain server-authored. (The edge function's DISPLAY clipping is
-- 600 scalars per §4.2; the stored row keeps the 4,000-scalar column
-- form, same as 'target'. The digest binds the displayed snippets the
-- edge function computes, and the stored row is the revalidation
-- substrate -- which is why the stored row's VERSION is what matters
-- here, defect A2.)
--
-- ======================================================================
-- DEFECT A2 -- source_version CANNOT DETECT AN EDIT.
--
-- Verified from the live catalog:
--
--   substring(prosrc from the INSERT) ->
--     SELECT v_new_session, m.id, m.created_at, left(m.content, 4000), 'target'
--
-- so source_version was m.created_at, and created_at NEVER moves on an
-- edit. Confirmed by catalog query that NO function in public assigns
-- messages.created_at, and edit_message is the only function that
-- UPDATEs messages alongside edited_at. So §4.3's "revalidate ...
-- source existence/version against the frozen snapshot" was blind to
-- edits for the one row that existed.
--
-- FIX: COALESCE(m.edited_at, m.created_at), for BOTH roles. This is
-- byte-identical in intent to what Task 2's live window already uses
-- (ai_session_context.ts: "COALESCE(edited_at, created_at) -- see
-- WindowMessage.sourceVersion for why created_at alone cannot detect an
-- edit"), so the stored row and the live computation now agree. An
-- edit-and-revert moves only the version, which is correct: the text
-- the partner approved was observed at a version that no longer
-- describes the row's history.
--
-- ======================================================================
-- DEFECT A3 -- THE SLOT-LIMIT RAISE CARRIED NO ERRCODE.
--
-- Plan C's prepare branch had to regex-match the exception TEXT
-- ("already pending or active") to map the refusal to §10's
-- SESSION_LIMIT_REACHED; a reword would silently degrade it to
-- UNAVAILABLE. Both slot-limit RAISEs now carry
-- ERRCODE = 'AT001' (a user-defined SQLSTATE in the reserved-for-
-- applications class AT, chosen because no PostgreSQL condition name
-- maps to class AT, so it cannot collide with a built-in error the
-- caller might also see). The MESSAGE TEXT IS UNCHANGED, so the
-- existing executed test keeps passing on the text while the edge
-- function keys off the code.
--
-- ======================================================================
-- LOCK ORDER: UNCHANGED. This function takes exactly one lock, the
-- relationship advisory lock pg_advisory_xact_lock(hashtext(
-- p_relationship_id::text)), in the same position as before -- after
-- the cheap validations, before every read and write. It holds ZERO
-- session row-class FOR UPDATE locks, before and after this migration,
-- so it is not a candidate in the structural sweep for functions
-- holding 2+ session row-classes without the advisory lock (that sweep
-- must keep returning zero rows; re-verified after this change). The
-- new INSERT ... SELECT over public.messages takes no explicit row
-- lock.
--
-- KEY-AS-SESSION-ID CONTRACT: UNCHANGED. v_new_session :=
-- p_idempotency_key, and the replay path still looks the key up as
-- ai_sessions.id and still checks creator_id only (the edge function's
-- detectPrepareKeyConflict supplies the payload half).
-- ======================================================================

-- ---------------------------------------------------------------------
-- A1(b): the toggle's own state. Additive, defaulted to false, which IS
-- spec §4.3's "Window is default off".
-- ---------------------------------------------------------------------
ALTER TABLE public.ai_sessions
  ADD COLUMN IF NOT EXISTS include_window boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.ai_sessions.include_window IS
  'Spec 4.3: the shared recent-window toggle, default off. This is the '
  'SETTING, distinct from the frozen snapshot in ai_session_sources '
  '(source_role = ''window''), which carries the per-source versions the '
  'digest binds and 4.3 revalidates. A session can have include_window '
  'true and zero window source rows (the civil day held no eligible '
  'messages) -- the two facts are not interchangeable. Only Ideas '
  'sessions with visibility = ''shared'' may set it true; enforced by '
  'the CHECK below and by the edge function''s own 4.1 validation.';

-- Only a shared Ideas session can have a window (spec §4.1: "Private
-- and Nearby sessions do not have recent windows"). The edge function
-- already rejects the combination with INVALID_INPUT; this makes the
-- database refuse it too, so a future caller cannot create a session
-- whose context settings contradict the spec.
--
-- NOT VALID is deliberate: every existing row has include_window =
-- false by the DEFAULT above, so the constraint already holds for all
-- of them -- but VALIDATE would take a table scan under an ACCESS
-- EXCLUSIVE-adjacent lock on a live table for a property the default
-- guarantees. Validated immediately below, in the same transaction, on
-- what is a provably all-false column; stated explicitly rather than
-- left as an invisible pending-validation state.
ALTER TABLE public.ai_sessions
  DROP CONSTRAINT IF EXISTS ai_sessions_window_only_shared_ideas;
ALTER TABLE public.ai_sessions
  ADD CONSTRAINT ai_sessions_window_only_shared_ideas
  CHECK (NOT include_window OR (kind = 'ideas' AND visibility = 'shared'))
  NOT VALID;
ALTER TABLE public.ai_sessions
  VALIDATE CONSTRAINT ai_sessions_window_only_shared_ideas;

-- ---------------------------------------------------------------------
-- A1(a) + A2 + A3: the function.
--
-- prepare_ai_session: idempotent, slot-limited session creation.
-- Spec §3.2. Lock order: relationship advisory lock, then no further
-- row lock is needed here (this RPC only ever touches ai_sessions rows
-- it is about to insert, or reclaims one via UPDATE under the same
-- relationship lock, which already serializes against a concurrent
-- prepare for the same relationship).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.prepare_ai_session(
  p_actor_id uuid,
  p_idempotency_key uuid,
  p_relationship_id uuid,
  p_kind text,
  p_visibility text,
  p_target_message_id uuid,
  p_include_window boolean,
  p_window_message_ids uuid[]
) RETURNS TABLE (session_id uuid, revision int, created boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing_session uuid;
  v_new_session uuid;
  v_include_window boolean;
  v_window_ids uuid[];
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

  -- A1: NULL is "off", matching §4.3's "default off". Normalized once
  -- so every use below reads the same value.
  v_include_window := COALESCE(p_include_window, false);
  -- A caller that passes no array is passing an empty window, not a
  -- NULL one. Duplicates are collapsed and NULLs dropped.
  --
  -- MEASURED, not assumed: the DISTINCT is DEFENCE IN DEPTH, not load
  -- bearing. `m.id = ANY(v_window_ids)` joins against public.messages,
  -- whose id is the PRIMARY KEY, so a repeated id matches that row
  -- exactly ONCE and the duplicate never reaches the INSERT -- verified
  -- by query. A mutation replacing this normalization with a bare
  -- COALESCE therefore survives every test, and is recorded as
  -- honestly unreachable rather than having a test tightened around it.
  -- It stays because it is free and because the property it protects
  -- (one row per source, ai_session_sources' primary key) must not
  -- depend on the query shape staying a PK join: a future rewrite to
  -- `unnest(v_window_ids) JOIN messages` would reintroduce the
  -- duplicate, and then the whole prepare aborts on a unique_violation
  -- the caller cannot act on. The NULL filter IS load bearing --
  -- source_message_id is NOT NULL, so a NULL element would abort the
  -- insert.
  v_window_ids := ARRAY(
    SELECT DISTINCT x FROM unnest(COALESCE(p_window_message_ids, ARRAY[]::uuid[])) AS x
    WHERE x IS NOT NULL
  );

  -- §4.1: private and Nearby sessions have no window. Refused here as
  -- well as in the edge function, because the CHECK constraint would
  -- otherwise be the thing that reported it, as a raw 23514.
  IF v_include_window AND NOT (p_kind = 'ideas' AND p_visibility = 'shared') THEN
    RAISE EXCEPTION 'A recent window requires a shared Ideas session';
  END IF;
  -- Window ids without the window switched on would silently persist a
  -- snapshot for a session whose setting says it has none -- the exact
  -- divergence between (a) and (b) this migration exists to prevent.
  IF NOT v_include_window AND cardinality(v_window_ids) > 0 THEN
    RAISE EXCEPTION 'Window messages supplied with p_include_window false';
  END IF;
  -- §4.2: "limits six". The caller's selection module already caps at
  -- WINDOW_ROW_CAP = 6; this refuses a caller that did not.
  IF cardinality(v_window_ids) > 6 THEN
    RAISE EXCEPTION 'At most six window messages';
  END IF;
  -- §4.2 item 3: "excluding the selected target". A target that also
  -- appears in the window would collide on the primary key.
  IF p_target_message_id IS NOT NULL
     AND p_target_message_id = ANY (v_window_ids) THEN
    RAISE EXCEPTION 'The selected target cannot also be a window message';
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
  -- transactionally"). activated_at stays NULL here, which is the
  -- truth -- see 20260953090000's CORRECTION 1 block, whose removal of
  -- the fake stamp Contract 9 asserts and this body preserves.
  UPDATE public.ai_sessions
  SET state = 'closed'
  WHERE creator_id = p_actor_id AND relationship_id = p_relationship_id
    AND state = 'preparing' AND preparation_deadline < now();

  -- A3: both slot-limit refusals now carry an ERRCODE. The MESSAGE TEXT
  -- is unchanged from 20260953090000, so any assertion on the text
  -- still holds; Plan C's prepare branch keys off SQLSTATE 'AT001'
  -- instead, so a future reword cannot silently degrade §10's
  -- SESSION_LIMIT_REACHED mapping to UNAVAILABLE.
  IF p_visibility = 'private' THEN
    IF EXISTS (
      SELECT 1 FROM public.ai_sessions
      WHERE creator_id = p_actor_id AND relationship_id = p_relationship_id
        AND visibility = 'private' AND state IN ('preparing', 'active')
    ) THEN
      RAISE EXCEPTION 'A private session is already pending or active for this creator'
        USING ERRCODE = 'AT001';
    END IF;
  ELSE
    IF EXISTS (
      SELECT 1 FROM public.ai_sessions
      WHERE relationship_id = p_relationship_id
        AND visibility = 'shared' AND state IN ('preparing', 'active')
    ) THEN
      RAISE EXCEPTION 'A shared session is already pending or active for this relationship'
        USING ERRCODE = 'AT001';
    END IF;
  END IF;

  v_new_session := p_idempotency_key;
  INSERT INTO public.ai_sessions (
    id, relationship_id, creator_id, kind, visibility, state,
    revision, context_revision, generation_epoch, attempt_count,
    preparation_deadline, include_window
  ) VALUES (
    v_new_session, p_relationship_id, p_actor_id, p_kind, p_visibility, 'preparing',
    1, 0, 0, 0, now() + interval '5 minutes', v_include_window
  );

  -- A2: source_version is COALESCE(edited_at, created_at) for BOTH
  -- roles. created_at alone never moves on an edit, so the stored row
  -- could not support §4.3's source-version revalidation. This matches
  -- ai_session_context.ts's live window exactly.
  IF p_target_message_id IS NOT NULL THEN
    INSERT INTO public.ai_session_sources (session_id, source_message_id, source_version, approved_clipped_text, source_role)
    SELECT v_new_session, m.id, COALESCE(m.edited_at, m.created_at), left(m.content, 4000), 'target'
    FROM public.messages m
    WHERE m.id = p_target_message_id AND m.deleted_at IS NULL
      AND m.relationship_id = p_relationship_id;
  END IF;

  -- A1(a): the frozen window snapshot. §4.2: "Persist source IDs,
  -- versions and snapshot time, not new selections on subsequent
  -- turns."
  --
  -- Silently skips an id that is not an eligible live message in THIS
  -- relationship -- exactly as the 'target' insert has always done. A
  -- deleted or foreign id yields no row rather than an error, so a
  -- message deleted between the caller's selection query and this call
  -- narrows the window instead of failing the prepare; §4.3's
  -- revalidation at activation is what refuses a session whose sources
  -- moved, and review_context shows the partner what is actually
  -- stored before either of them approves.
  --
  -- The relationship_id predicate is the authorization boundary: it is
  -- what stops a caller aiming p_window_message_ids at another
  -- couple's messages. Without it a SECURITY DEFINER body would happily
  -- clip and store arbitrary chat text.
  IF cardinality(v_window_ids) > 0 THEN
    INSERT INTO public.ai_session_sources (session_id, source_message_id, source_version, approved_clipped_text, source_role)
    SELECT v_new_session, m.id, COALESCE(m.edited_at, m.created_at), left(m.content, 4000), 'window'
    FROM public.messages m
    WHERE m.id = ANY (v_window_ids)
      AND m.deleted_at IS NULL
      AND m.relationship_id = p_relationship_id;
  END IF;

  RETURN QUERY SELECT v_new_session, 1, true;
END;
$$;

REVOKE ALL ON FUNCTION public.prepare_ai_session(uuid, uuid, uuid, text, text, uuid, boolean, uuid[])
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_ai_session(uuid, uuid, uuid, text, text, uuid, boolean, uuid[])
  TO service_role;

-- The 7-argument form is retired now that the 8-argument form exists,
-- so PostgREST cannot resolve a prepare call to a body that ignores
-- p_include_window. Dropped AFTER the new one is created, so there is
-- no window in which no prepare_ai_session exists.
DROP FUNCTION IF EXISTS public.prepare_ai_session(uuid, uuid, uuid, text, text, uuid, boolean);
