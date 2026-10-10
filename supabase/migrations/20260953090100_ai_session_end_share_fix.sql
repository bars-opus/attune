-- Fix round 1 for Task 9 (end_ai_session / share_ai_session_turn).
-- Spec §5.4, §7.3, §8.1, §8.2.2.
--
-- ======================================================================
-- THIS MIGRATION SUPERSEDES PARTS OF TWO EARLIER MIGRATIONS.
--
-- It re-defines, by CREATE OR REPLACE:
--
--   * public.end_ai_session        -- originally 20260953090000 (Task 9)
--   * public.share_ai_session_turn -- originally 20260953090000 (Task 9)
--
-- and it re-states the grant on share_ai_session_turn. It does NOT
-- re-define public.prepare_ai_session; that function's authoritative
-- definition remains the one in 20260953090000 (Task 9), which itself
-- superseded Task 3's original in 20260953030000. See the "MIGRATION
-- PROVENANCE" note at the bottom of this file.
--
-- Per this plan's additive-migrations discipline (established by Task
-- 6's fix round, 20260953060100), no earlier migration's logic is
-- edited in place. Later migrations win; the earlier files are kept as
-- the historical record of what shipped when.
-- ======================================================================
--
-- Review findings addressed here:
--
--   F1 (Critical) -- end_ai_session stranded the global quota
--     reservation. It moved an outstanding ai_session_requests row to
--     state='cancelled' but never released the matching
--     ai_assistant_usage reservation. Two independent facts made that a
--     permanent leak rather than a cosmetic one:
--
--       (a) reserve_ai_assistant_quota's rolling-window COUNT excludes
--           only outcome IN ('rejected','cancelled'); an
--           ai_assistant_usage row left at outcome='reserved' therefore
--           counts against the actor's 20-per-24h limit forever.
--       (b) reconcile_ai_session_leases -- the ONE path that would have
--           released it -- scans only
--           `state IN ('reserved','started') AND lease_deadline < now()`.
--           A 'cancelled' request is invisible to it.
--
--     Measured effect before this fix: either partner of a shared
--     session could call end_ai_session repeatedly between a creator's
--     admission and its dispatch, burning the CREATOR's entire 24h AI
--     quota with zero provider calls (reviewer measured x20 ->
--     rate_limited, retry_after=86394). That is a partner-weaponizable
--     denial of service, not just an accounting error.
--
--     Fix: resolve the two cases distinctly, exactly as
--     reconcile_ai_session_leases's own 'reserved' branch already does:
--
--       * state = 'reserved'  -> NEVER dispatched. No provider call was
--         made and claim_ai_session_dispatch never ran, so
--         ai_assistant_usage.provider_started_at IS NULL. The
--         reservation is genuinely unconsumed and MUST be released,
--         via Plan A's release_ai_assistant_quota_reservation(actor,
--         request_id). That RPC's own WHERE clause
--         (outcome='reserved' AND provider_started_at IS NULL) is the
--         enforcement, and it is idempotent on a second call.
--
--       * state IN ('started','staged') -> a provider call IS in flight
--         or already returned. claim_ai_session_dispatch set the real,
--         write-once ai_assistant_usage.provider_started_at marker (see
--         20260953060100), so this reservation has LEGITIMATELY consumed
--         quota and must stay charged. release_ai_assistant_quota_
--         reservation would RAISE on it ('Cannot release a reservation
--         whose provider call has started'), which is precisely why
--         these rows are excluded from the release loop rather than
--         passed to it and swallowed. 'staged' is reachable only via
--         claim_ai_session_dispatch (20260953080000's
--         stage_ai_session_nearby_result moves 'started' -> 'staged'),
--         so it carries the marker for the same reason 'started' does.
--
--     Note the actor released is v_row.actor_id -- the request's OWN
--     actor (whoever admitted the generation), NOT p_actor_id. The
--     whole point of F1 is that the ENDER may be the partner while the
--     charged actor is the creator; releasing against p_actor_id would
--     raise 'Reservation not found for this actor' and leave the real
--     leak in place. This is also why the loop reads actor_id off each
--     row instead of assuming one actor per session.
--
--   F2 (Critical) -- share_ai_session_turn was granted to
--     `authenticated` while taking its actor as a PARAMETER and then
--     overwriting request.jwt.claims with it. Any logged-in user could
--     call it through PostgREST with a victim's user id, read a private
--     session's Attune answer out of the returned public.messages row,
--     and post a chat message into someone else's relationship under
--     the victim's sender_id. Plan A's share_ai_assist_draft is safe
--     with an `authenticated` grant only because it takes NO actor
--     parameter and derives auth.uid() internally; Task 9 copied the
--     grant without the property that justified it.
--
--     Fix: the grant moves to service_role, matching every other RPC in
--     this plan. This is not a locally-invented choice -- Plan C's edge
--     function already calls this RPC through its SERVICE-ROLE client
--     (`service.rpc("share_ai_session_turn", { p_actor_id:
--     userScoped.user.id, ... })`, Plan C's `case "share_answer"`), and
--     Plan B's own Task 10 Step 5 explicitly prescribes this exact
--     change ("recommend granting it to service_role too and having
--     Plan C's edge function derive p_actor_id from requireUser(req),
--     rather than leaving it as the one `authenticated`-callable
--     exception in this entire plan"). As committed the grant was in
--     fact BROKEN for the intended caller as well as exploitable by the
--     unintended one: service_role had no EXECUTE privilege at all.
--
--     The alternative -- keep `authenticated` and reject
--     `p_actor_id IS DISTINCT FROM auth.uid()` -- was rejected
--     deliberately: it would make the RPC uncallable by the actual
--     caller, since a service-role connection carries no JWT and
--     auth.uid() is NULL there. The two options are mutually exclusive,
--     and Plan C settles which caller is real.
--
--     The JWT-claim dance INSIDE the function is kept unchanged and is
--     still required: share_ai_assist_draft reads auth.uid() itself, so
--     delegating to it from a service-role connection with no ambient
--     claim would fail 'Not authenticated' on every share. With the
--     grant now service_role-only, the claim is set to an actor this
--     function has ALREADY authorized against the session, under a
--     privilege the client cannot reach -- which is the configuration
--     the comment in 20260953090000 described but the grant contradicted.
--
--   F6 (Minor) -- end_ai_session bumped generation_epoch but not
--     revision, while deleting the entire transcript. `revision` is
--     ai_sessions' optimistic-concurrency / content token (Task 1's own
--     column comment: "Advances on admission/completion/publication...
--     Optimistic concurrency token for generate's expected_revision"),
--     and commit_ai_session_ideas_turn / publish_ai_session_nearby_result
--     both bump it on every content change. A revision-polling client
--     therefore saw an unchanged revision across the single largest
--     content change a session can undergo.
--
--     Checked before changing it: the ONLY reader of ai_sessions.revision
--     is admit_ai_session_generation's `revision != p_expected_revision
--     -> CONTEXT_CHANGED` check (twice: pre-lock and under the row
--     lock), plus approve/activate's `revision = p_revision` guards
--     which apply only to a 'preparing' session. Every one of those
--     readers is gated on a state this function is leaving behind --
--     admit raises UNAVAILABLE on `state != 'active'` BEFORE it ever
--     compares revisions, and approve/activate match
--     `state = 'preparing'`. So bumping revision on close cannot change
--     any authorization or admission outcome; it only makes the purge
--     observable. Semantics support it.
--
--   F7 (Minor) -- 20260953090000's `ALTER TABLE ... DROP CONSTRAINT
--     ai_sessions_check` had no IF EXISTS, so re-applying that migration
--     to an already-migrated database aborted. Repaired defensively
--     below without editing that file: the constraint is dropped IF
--     EXISTS (a no-op on a database that already ran 20260953090000)
--     and the named replacement is re-asserted only if missing. This
--     makes the pair idempotent from here on regardless of which order
--     a rebuild applies them in.

-- ----------------------------------------------------------------------
-- F7: make the Correction-1 constraint swap idempotent.
--
-- On a fresh rebuild 20260953090000 has already dropped the anonymous
-- `ai_sessions_check` and added `ai_sessions_activated_at_state_check`,
-- so both statements below are no-ops. On a database where
-- 20260953090000 is re-applied (or on any future re-run of this file),
-- they are what keeps it from aborting.
ALTER TABLE public.ai_sessions DROP CONSTRAINT IF EXISTS ai_sessions_check;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.ai_sessions'::regclass
      AND conname = 'ai_sessions_activated_at_state_check'
  ) THEN
    ALTER TABLE public.ai_sessions ADD CONSTRAINT ai_sessions_activated_at_state_check
      CHECK (
        (state = 'preparing' AND activated_at IS NULL)
        OR (state = 'active' AND activated_at IS NOT NULL)
        OR (state = 'closed')
      );
  END IF;
END $$;

-- ----------------------------------------------------------------------
-- F1 + F6: end_ai_session, now releasing the quota reservation of every
-- never-dispatched request it cancels, and advancing `revision` so the
-- purge is observable.
--
-- LOCK ORDER (Global Constraints / spec §6.2) is UNCHANGED from
-- 20260953090000 and must stay that way: relationship advisory lock,
-- THEN the session row lock, THEN the request rows. The new release
-- loop takes the request rows FOR UPDATE last, which is exactly the
-- documented order (relationship -> session row -> request row) and the
-- same order reconcile_ai_session_leases uses. No new lock class is
-- introduced: release_ai_assistant_quota_reservation touches
-- ai_assistant_usage only, which no other lock in this chain covers,
-- and it is called while already holding this session's relationship
-- lock -- the same nesting admit_ai_session_generation establishes when
-- it calls reserve_ai_assistant_quota under that same lock.
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
  v_row record;
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT s.relationship_id INTO v_relationship_id
  FROM public.ai_sessions s WHERE s.id = p_session_id;
  IF v_relationship_id IS NULL THEN
    RETURN; -- unknown session: idempotent no-op, same as "already closed"
  END IF;

  -- LOCK 1: the relationship advisory lock.
  PERFORM pg_advisory_xact_lock(hashtext(v_relationship_id::text));

  -- LOCK 2: the session row, re-read authoritatively under both locks.
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
    -- session (spec §5.4), read from relationships rather than from
    -- who approved.
    IF NOT EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = v_session.relationship_id
        AND (r.user_a = p_actor_id OR r.user_b = p_actor_id)
    ) THEN
      RAISE EXCEPTION 'Not a member of this shared session''s relationship';
    END IF;
  END IF;

  -- Fence any in-flight worker, and advance `revision` so a
  -- revision-polling client can observe the purge (F6). No
  -- client-readable ending-actor column exists to set, and none is
  -- added (Global Constraints / spec §5.4). activated_at is left
  -- untouched -- NULL for a session that never activated.
  UPDATE public.ai_sessions
  SET state = 'closed',
      generation_epoch = generation_epoch + 1,
      revision = revision + 1
  WHERE id = p_session_id;

  -- LOCK 3: every outstanding request for this session, locked in one
  -- pass so its quota can be resolved before the row leaves the states
  -- the reconciler scans. This loop IS the F1 fix.
  FOR v_row IN
    SELECT id, actor_id, state FROM public.ai_session_requests
    WHERE session_id = p_session_id
      AND state IN ('reserved', 'started', 'staged')
    FOR UPDATE
  LOOP
    UPDATE public.ai_session_requests
    SET state = 'cancelled', terminal_code = 'session_ended'
    WHERE id = v_row.id;

    IF v_row.state = 'reserved' THEN
      -- Never dispatched: claim_ai_session_dispatch never ran, so
      -- ai_assistant_usage.provider_started_at IS NULL and no provider
      -- call was ever made. Release the reservation exactly once, the
      -- same way reconcile_ai_session_leases's own 'reserved' branch
      -- does (spec §7.3: "A terminal failure proven to have no
      -- provider-start marker may release global quota once"). Without
      -- this, the row sits at outcome='reserved' forever -- counted
      -- against the actor's rolling window and unreachable by the
      -- reconciler, which scans only 'reserved'/'started' requests.
      --
      -- v_row.actor_id, NOT p_actor_id: the ender may be the partner
      -- while the charged actor is the creator.
      PERFORM public.release_ai_assistant_quota_reservation(v_row.actor_id, v_row.id);
    END IF;
    -- 'started' / 'staged': claim_ai_session_dispatch already set the
    -- write-once ai_assistant_usage.provider_started_at marker
    -- (20260953060100), so a provider call is in flight or has already
    -- returned and the quota is LEGITIMATELY consumed. It stays
    -- charged, and is deliberately not passed to the release RPC --
    -- which would RAISE 'Cannot release a reservation whose provider
    -- call has started' rather than silently no-op.
  END LOOP;

  -- Synchronous purge, SAME transaction (spec §5.4) -- not a later job.
  -- ai_session_publications is deliberately NOT purged: its
  -- consumed_marker must survive the session lifetime (Task 2's table
  -- comment), and the chat messages it points at are ordinary messages
  -- that outlive the session by design.
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

-- ----------------------------------------------------------------------
-- F2: share_ai_session_turn's body is unchanged; only its GRANT moves.
--
-- Re-stated in full here (rather than patched with a bare GRANT) so
-- this file is the single authoritative definition of the function and
-- its privileges together -- the privilege WAS the defect, and splitting
-- them across files is how the committed version came to describe a
-- configuration it did not have.
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
  -- 'redirect' cannot be posted at all (spec §8.1), and 'nearby_result'
  -- has its own requester-only publish path.
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

  -- share_ai_assist_draft derives its actor from auth.uid() directly
  -- (Plan A's client-callable RPC, predating this plan's explicit-
  -- p_actor_id convention) and enforces requester_id = that actor. The
  -- claim is set to the actor THIS function has already authorized
  -- against the session, so the delegation sees the same actor the
  -- authorization used. set_config(..., true) is transaction-local and
  -- the prior value is restored on both the success and the exception
  -- path, so no impersonation claim leaks into the caller's
  -- transaction. With the grant now service_role-only (see this file's
  -- F2 note), a client cannot reach this code to supply an actor it is
  -- not.
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
-- F2: service_role-only, like every other RPC in this plan. Plan C's
-- edge function is the caller and already invokes this through its
-- service-role client with p_actor_id from requireUser(req); Plan B's
-- Task 10 Step 5 prescribes exactly this grant. The `authenticated`
-- grant 20260953090000 shipped was both exploitable (actor
-- impersonation from any logged-in client) and wrong for the real
-- caller (service_role had no EXECUTE at all).
REVOKE ALL ON FUNCTION public.share_ai_session_turn(uuid, uuid, int)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.share_ai_session_turn(uuid, uuid, int)
  TO service_role;

-- ======================================================================
-- MIGRATION PROVENANCE (F4) -- where each function in this feature is
-- authoritatively defined, as of this migration:
--
--   public.prepare_ai_session
--     Task 3    20260953030000_ai_session_prepare_rpc.sql   (original)
--     Task 9    20260953090000_ai_session_end_share_rpcs.sql  <-- WINS
--       Task 9's "CORRECTION 1" re-defined it to drop the FAKE
--       `activated_at = now()` its expired-slot reclaim UPDATE needed
--       only to satisfy Task 1's original 2-way CHECK. Task 9 loosened
--       that CHECK to the honest 3-way form in the same migration, so
--       the fabricated timestamp became both unnecessary and untrue.
--       Reviewed and accepted: the only reader of activated_at anywhere
--       is admit_ai_session_generation's expires_at computation, which
--       runs only after asserting state = 'active' -- a state the 3-way
--       constraint still guarantees carries a non-NULL activated_at.
--       The behaviour is NOT reverted here. Editing Task 3's committed
--       file in place would violate this plan's additive-migrations
--       discipline; the supersession is made legible instead, by this
--       note plus a pointer comment appended to Task 3's own file.
--
--   public.end_ai_session
--     Task 9    20260953090000_ai_session_end_share_rpcs.sql  (original)
--     fix r1    20260953090100_ai_session_end_share_fix.sql   <-- WINS
--
--   public.share_ai_session_turn
--     Task 9    20260953090000_ai_session_end_share_rpcs.sql  (original)
--     fix r1    20260953090100_ai_session_end_share_fix.sql   <-- WINS
--       (grant changed from `authenticated` to `service_role`)
--
--   public.claim_ai_session_dispatch / public.reconcile_ai_session_leases
--     Task 6    20260953060000_ai_session_dispatch_claim_rpc.sql
--     fix r1    20260953060100_ai_session_dispatch_claim_marker_fix.sql <-- WINS
--
-- A future change to any function above must be made in a NEW migration
-- that sorts after the winning file, not in the original.
-- ======================================================================
