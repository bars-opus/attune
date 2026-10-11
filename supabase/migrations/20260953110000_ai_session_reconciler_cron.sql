-- Task 11: the every-minute reconciler/purger, its cron registration,
-- the WRITE leg of the consent gate, and two defence-in-depth
-- invariants routed here from Tasks 6/9/10's reviews.
-- Spec §8.2.3, §7.2, §5.4, §7.3, §3.2.
--
-- ======================================================================
-- THIS MIGRATION SUPERSEDES PART OF ONE EARLIER MIGRATION.
--
-- It re-defines, by CREATE OR REPLACE:
--
--   * public.publish_ai_session_nearby_result -- originally
--     20260953080000 (Task 8), to add the membership + consent gate it
--     never had (routed item 1, from Task 10's Ruling 8).
--
-- It does NOT re-define public.end_ai_session. That function's
-- authoritative definition remains 20260953090100 (Task 9 fix round 1)
-- and is deliberately left byte-identical -- see "WHY end_ai_session IS
-- NOT WIDENED" below, which is this migration's largest single
-- deviation from its own brief.
--
-- Per this plan's additive-migrations discipline (established by Task
-- 6's fix round 20260953060100 and followed by 20260953090100 and
-- 20260953100100), no earlier migration's logic is edited in place.
-- Later migrations win; the earlier files stay as the record of what
-- shipped when.
-- ======================================================================
--
--
-- ======================================================================
-- WHY end_ai_session IS NOT WIDENED TO ACCEPT A NULL ACTOR
-- (deviation from this task's brief, Steps 3 and 5 -- verified wrong
-- before deviating, not assumed wrong)
-- ======================================================================
--
-- The brief instructs this migration to CREATE OR REPLACE
-- end_ai_session with a body that accepts p_actor_id IS NULL when the
-- session is already past its own expiry, so the purger can call it
-- with a NULL actor. Three independent facts make that body unusable
-- as written:
--
--   1. IT WOULD RE-OPEN A CRITICAL BUG. The brief's replacement body
--      is derived from Task 9's ORIGINAL end_ai_session
--      (20260953090000). It predates Task 9's fix round and contains
--      NONE of it: no pg_advisory_xact_lock, no ai_session_requests
--      cancellation, no release_ai_assistant_quota_reservation loop,
--      no `revision` bump. Applying it would revert review finding F1
--      (Critical) -- the partner-weaponizable quota-stranding DoS where
--      a never-dispatched reservation sits at outcome='reserved'
--      forever, counted against the actor's 20-per-24h rolling window
--      and unreachable by reconcile_ai_session_leases (which scans only
--      state IN ('reserved','started'), never 'cancelled'). Measured at
--      review time as x20 -> rate_limited, retry_after=86394. It would
--      also drop the relationship advisory lock, which this plan's
--      Global Constraints fix as the FIRST lock in a non-negotiable
--      order, and revert F6 (the revision bump that makes the purge
--      observable to a revision-polling client).
--
--   2. IT WOULD VIOLATE A GLOBAL CONSTRAINT HEAD-ON. "Every new
--      SECURITY DEFINER function uses SET search_path = public and
--      validates its actor parameter non-NULL as its first statement."
--      end_ai_session's `IF p_actor_id IS NULL THEN RAISE EXCEPTION
--      'Not authenticated'` is that first statement today. The brief
--      replaces it with a conditional bypass.
--
--   3. IT WOULD BREAK A COMMITTED CONTRACT. Task 9's Contract 4
--      (supabase/tests/ai_session_end_share_contracts.sql) asserts the
--      SPECIFIC 'Not authenticated' raise for a NULL actor on
--      end_ai_session. The brief's own Step 5 predicts that file still
--      passes unchanged; it would not. The brief's prediction rests on
--      "the NULL-actor path only activates when v_is_system_purge is
--      true, which none of Task 9's own scenarios trigger" -- but
--      Contract 4 passes an ALREADY-CLOSED session, for which
--      v_is_system_purge is false, so the brief's body raises
--      'Not authenticated' only because of the `state = 'closed'`
--      early RETURN that fires first. The contract would then be
--      asserting a raise that never happens. Either way the committed
--      assertion and the brief's body cannot both be right.
--
-- THE CREATOR-AS-ACTOR ALTERNATIVE WAS ALSO MEASURED, AND IT FAILS.
-- The obvious way to keep end_ai_session untouched is to have the
-- purger pass the session's own creator_id as the actor. It is wrong,
-- and provably so: relationships.user_a/user_b are NULLABLE with
-- ON DELETE SET NULL, so a creator can be removed from the
-- relationship. Probed live against this schema -- creator removed
-- (user_a = NULL), session expired an hour ago:
--
--   end_ai_session(creator_id, session) -> FAILED:
--     'Not a member of this shared session''s relationship'
--   session state afterwards -> still 'active'
--
-- That is the worst possible failure mode: the purger would
-- PERMANENTLY fail to delete exactly the sessions whose content most
-- needs deleting (relationship dissolved, member removed), and would
-- do so silently, forever, every minute. The brief's instinct that the
-- system path must not be subject to actor authorization is CORRECT;
-- only its implementation is wrong.
--
-- WHAT THIS MIGRATION DOES INSTEAD. It factors the closure itself into
-- purge_ai_session_content(p_session_id) -- an actor-free primitive
-- that takes no actor parameter at all, so there is no actor to
-- validate and no authorization to bypass. end_ai_session stays
-- byte-identical and remains the ONLY authorized, user-facing way to
-- end a session; the purger is the only other caller and reaches the
-- primitive directly. This satisfies the brief's actual requirement
-- ("reusing that function's synchronous content deletion rather than
-- duplicating it") through a shared primitive rather than through a
-- NULL-actor hole in a user-facing RPC, keeps all three facts above
-- intact, and leaves Task 9's ten contracts and Contract 9's
-- supersession marker untouched (end_ai_session's live body still
-- contains its release_ai_assistant_quota_reservation call, because
-- that function is not edited).
--
-- The cost of the shared primitive is that the closure logic now lives
-- in purge_ai_session_content while end_ai_session keeps its own copy
-- of the same four DELETEs and the same release loop. That duplication
-- is deliberate and bounded: collapsing end_ai_session into a
-- delegating wrapper would change a function that 20+ passing mutants
-- and ten committed contracts are pinned to, on the last task of the
-- plan, for no behavioural gain. A contract below asserts the two
-- paths stay semantically equivalent (the primitive purges all four
-- session-scoped tables and releases 'reserved'-only quota, exactly as
-- end_ai_session does), so the duplication cannot silently diverge.
-- ======================================================================


-- ----------------------------------------------------------------------
-- purge_ai_session_content -- the actor-free closure primitive.
--
-- Closes one session and deletes its primary content in ONE
-- transaction, with no actor parameter and therefore no authorization
-- step. Returns true if it closed the session, false if there was
-- nothing to do (unknown session, or already closed) -- so the caller
-- can count real work without a second query.
--
-- This is NOT a client-reachable surface: no GRANT below reaches anon
-- or authenticated, and service_role gets EXECUTE only because the
-- cron job and Plan C's edge function both run as service_role. Every
-- user-initiated close still goes through end_ai_session, which
-- authorizes the actor first.
--
-- LOCK ORDER (Global Constraints / spec §6.2) is the SAME order
-- end_ai_session and reconcile_ai_session_leases already use, and is
-- NOT varied:
--
--   1. relationship advisory lock  pg_advisory_xact_lock(hashtext(rel))
--   2. session row lock            SELECT ... FOR UPDATE on ai_sessions
--   3. request row locks           SELECT ... FOR UPDATE on
--                                  ai_session_requests
--
-- There is no requester-quota advisory lock in this path, which is
-- correct and not an omission: that lock lives INSIDE
-- reserve_ai_assistant_quota (the admission path), and
-- release_ai_assistant_quota_reservation -- the only quota function
-- this path calls -- takes no advisory lock at all. So this function
-- acquires a strict PREFIX of the documented order (1, 2, 3 with the
-- optional 2nd element absent), never a different order, which is
-- exactly what end_ai_session does. Proven by contract rather than by
-- reading: a contract below asserts the live body's lock statements
-- appear in this order, and the existing
-- ai_session_end_admit_concurrent_test.sh already proves the
-- relationship-lock-first discipline is deadlock-free against a racing
-- admission.
CREATE OR REPLACE FUNCTION public.purge_ai_session_content(
  p_session_id uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.ai_sessions;
  v_relationship_id uuid;
  v_row record;
BEGIN
  -- No actor parameter exists to validate. p_session_id is validated
  -- instead, as this function's first statement: a NULL session id is
  -- rejected rather than silently matching nothing, so a caller bug
  -- cannot look like a successful no-op purge.
  IF p_session_id IS NULL THEN
    RAISE EXCEPTION 'purge_ai_session_content requires a session id';
  END IF;

  SELECT s.relationship_id INTO v_relationship_id
  FROM public.ai_sessions s WHERE s.id = p_session_id;
  IF v_relationship_id IS NULL THEN
    RETURN false; -- unknown session: idempotent no-op
  END IF;

  -- LOCK 1: the relationship advisory lock, first and always.
  PERFORM pg_advisory_xact_lock(hashtext(v_relationship_id::text));

  -- LOCK 2: the session row, re-read authoritatively under both locks.
  -- The re-read is load-bearing, not defensive dressing: between the
  -- purger's scan and this lock, a racing end_ai_session or a racing
  -- admission may have changed the state, and the scan's snapshot must
  -- not be trusted. This is the same under-lock re-check
  -- end_ai_session performs.
  SELECT * INTO v_session FROM public.ai_sessions
  WHERE id = p_session_id FOR UPDATE;
  IF v_session.id IS NULL THEN
    RETURN false;
  END IF;
  IF v_session.state = 'closed' THEN
    RETURN false; -- already closed: idempotent no-op, nothing purged
  END IF;

  -- Fence any in-flight worker, and advance `revision` so the purge is
  -- observable to a revision-polling client -- identical to
  -- end_ai_session (Task 9 F6). activated_at is left untouched (NULL
  -- for a session that never activated, which Task 9's loosened 3-way
  -- CHECK permits for state='closed'). No client-readable "who ended
  -- it" column exists to set, and none is added (Global Constraints /
  -- spec §5.4) -- a system purge is recorded exactly as a user close
  -- is, which is part of why no such column may exist.
  UPDATE public.ai_sessions
  SET state = 'closed',
      generation_epoch = generation_epoch + 1,
      revision = revision + 1
  WHERE id = p_session_id;

  -- LOCK 3: every outstanding request, resolved before its row leaves
  -- the states the reconciler scans. This mirrors end_ai_session's own
  -- F1 fix exactly, including the two details that make it correct:
  --
  --   * 'reserved' -> never dispatched, so
  --     ai_assistant_usage.provider_started_at IS NULL and the
  --     reservation is genuinely unconsumed. Release it exactly once.
  --   * 'started'/'staged' -> claim_ai_session_dispatch already set the
  --     write-once provider marker (20260953060100), so the quota is
  --     LEGITIMATELY consumed and stays charged. These are excluded
  --     rather than passed to the release RPC, which would RAISE
  --     ('Cannot release a reservation whose provider call has
  --     started') and abort the whole purge transaction.
  --
  -- v_row.actor_id, never a caller-supplied actor: the charged actor is
  -- whoever admitted the generation.
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
      PERFORM public.release_ai_assistant_quota_reservation(v_row.actor_id, v_row.id);
    END IF;
  END LOOP;

  -- Synchronous purge, SAME transaction (spec §5.4, Global
  -- Constraints). ai_session_publications is deliberately NOT purged:
  -- its consumed_marker must outlive the session (Task 2's table
  -- comment), and the chat messages it points at are ordinary messages
  -- that outlive the session by design.
  DELETE FROM public.ai_session_turns WHERE session_id = p_session_id;
  DELETE FROM public.ai_session_sources WHERE session_id = p_session_id;
  DELETE FROM public.ai_session_approvals WHERE session_id = p_session_id;
  DELETE FROM public.ai_session_staging WHERE session_id = p_session_id;

  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.purge_ai_session_content(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_ai_session_content(uuid)
  TO service_role;


-- ----------------------------------------------------------------------
-- purge_expired_ai_sessions -- the every-minute expiry purger.
-- Spec §8.2.3: "scheduled expiry purger runs every minute with an
-- operational target of deletion within five minutes after logical
-- expiry. Existing hourly 24-hour draft purge does not satisfy this."
--
-- THIS IS A BACKSTOP, NOT THE PRIMARY DELETION PATH (Global
-- Constraints). Every session-scoped table's primary content is
-- deleted in the SAME transaction that closes the session, by
-- end_ai_session. This job exists for the sessions nothing ever closes:
--
--   * an 'active' session past expires_at whose relationship simply
--     never generates again, so no admission, no completion and no End
--     ever runs; and
--   * a 'preparing' session past preparation_deadline that Task 3's
--     reclaim-on-prepare never catches, because that reclaim fires only
--     when the SAME creator prepares another session on the SAME
--     relationship -- a pair that never prepares again leaves the row
--     and its approved source clippings behind indefinitely.
--
-- Nothing here restructures closure to depend on this job.
--
-- EACH SESSION IS PURGED IN ITS OWN CALL, under its own relationship
-- lock, and a failure on one is logged and skipped rather than
-- aborting the batch. The reasoning is operational: this runs
-- unattended every minute, and one wedged session must not be able to
-- stop every other session on the platform from ever being purged. The
-- per-session EXCEPTION block is therefore deliberate, and it is
-- NARROW -- it re-raises nothing but does record a WARNING naming the
-- session and SQLERRM, so a systematic failure is visible in the cron
-- log rather than silent. Note the subtlety this depends on: a plpgsql
-- EXCEPTION block wraps its body in a subtransaction, so a failed
-- session's partial work is rolled back to the start of ITS OWN
-- iteration and cannot leave a half-purged session behind.
--
-- The scan is bounded by p_limit (default 500) so a backlog drains
-- over several minutes instead of one unbounded transaction holding
-- locks for an unpredictable time. At one run per minute, 500/minute
-- clears any realistic backlog well inside the five-minute target.
CREATE OR REPLACE FUNCTION public.purge_expired_ai_sessions(
  p_limit int DEFAULT 500
) RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row record;
  v_count int := 0;
BEGIN
  FOR v_row IN
    SELECT id FROM public.ai_sessions
    WHERE (state = 'active'
             AND expires_at IS NOT NULL
             AND expires_at < now())
       OR (state = 'preparing'
             AND preparation_deadline < now())
    -- Oldest first, so a backlog drains in expiry order and the worst
    -- purge lag shrinks monotonically rather than starving old rows.
    -- COALESCE because the two arms populate different columns.
    ORDER BY COALESCE(expires_at, preparation_deadline)
    LIMIT p_limit
  LOOP
    BEGIN
      IF public.purge_ai_session_content(v_row.id) THEN
        v_count := v_count + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING
        'purge_expired_ai_sessions: session % could not be purged (%) -- skipped, will retry next run',
        v_row.id, SQLERRM;
    END;
  END LOOP;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.purge_expired_ai_sessions(int)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_expired_ai_sessions(int)
  TO service_role;


-- ----------------------------------------------------------------------
-- ROUTED ITEM 3: the quota-residue sweep.
--
-- Nothing enforced, at the DB level, that no ai_assistant_usage row
-- sits at outcome='reserved' AND provider_started_at IS NULL while its
-- ai_session_requests row is in a TERMINAL state ('committed',
-- 'failed', 'cancelled'). That is precisely the shape of the F1
-- quota-stranding leak Task 9 fixed in code: the usage row counts
-- against the actor's rolling window forever (the window excludes only
-- outcome IN ('rejected','cancelled')) while no reconciler path can
-- ever reach it (reconcile_ai_session_leases scans only
-- state IN ('reserved','started')).
--
-- WHY A SWEEP AND NOT A CHECK OR A TRIGGER -- the choice this item
-- asked to be justified:
--
--   * A CHECK constraint is IMPOSSIBLE here, not merely awkward. The
--     invariant spans two tables (ai_session_requests.state and
--     ai_assistant_usage.outcome/provider_started_at) and Postgres
--     CHECK constraints cannot reference another row, let alone
--     another table. There is not even a foreign key between them:
--     ai_assistant_usage is Plan A's ledger, shared with the 'assist'
--     and 'understand' modes, and keyed only on request_id with no FK
--     to ai_session_requests. Verified against the live schema.
--
--   * A TRIGGER would be enforcement rather than detection, which
--     sounds stronger and is worse here. The invariant is transiently
--     and LEGITIMATELY false inside a correct transaction:
--     end_ai_session sets state='cancelled' on the request BEFORE
--     calling release_ai_assistant_quota_reservation, so a row-level
--     AFTER trigger on ai_session_requests would fire while the
--     release is still one statement away and would abort the correct
--     path. Making it a CONSTRAINT TRIGGER deferred to commit would
--     avoid that, at the cost of aborting the user's End at COMMIT
--     time -- turning a quota-accounting residue into a failed user
--     action, and doing so in the one code path (closure) whose whole
--     purpose is to delete content. Failing a purge to protect an
--     accounting row is the wrong trade.
--
--   * A RECONCILER SWEEP fits what the reconciler already is: a
--     once-a-minute scanner that resolves exactly this class of
--     residue, and it can RESOLVE the row rather than merely refusing
--     it. It also covers residue from paths that no trigger on
--     ai_session_requests would ever see -- a request row DELETEd by
--     the ai_sessions ON DELETE CASCADE, for instance, leaves its
--     usage row behind with no request row left to trigger on. The
--     sweep catches that; a trigger structurally cannot.
--
-- The sweep RESOLVES by calling the same release RPC end_ai_session
-- and reconcile_ai_session_leases use, so there is exactly one way a
-- reservation is ever released in this system. Its guard
-- (provider_started_at IS NULL AND outcome='reserved') is what makes
-- this safe: a row whose provider call started is never touched, and a
-- second call is a no-op.
--
-- It also deliberately sweeps ORPHANED usage rows -- 'session'-mode
-- reservations with no ai_session_requests row at all, which the
-- cascade leaves behind. Scoped to mode='session' throughout so Plan
-- A's 'assist'/'understand' ledger rows, which have no
-- ai_session_requests row BY DESIGN, are never touched.
CREATE OR REPLACE FUNCTION public.reconcile_ai_session_quota_residue()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row record;
  v_count int := 0;
BEGIN
  FOR v_row IN
    SELECT u.request_id, u.user_id
    FROM public.ai_assistant_usage u
    LEFT JOIN public.ai_session_requests r ON r.id = u.request_id
    WHERE u.mode = 'session'
      AND u.outcome = 'reserved'
      AND u.provider_started_at IS NULL
      -- Either the request reached a terminal state without its
      -- reservation being resolved, or the request row is gone
      -- entirely (ai_sessions ON DELETE CASCADE) and nothing can ever
      -- resolve it.
      AND (r.id IS NULL OR r.state IN ('committed', 'failed', 'cancelled'))
    FOR UPDATE OF u
  LOOP
    BEGIN
      PERFORM public.release_ai_assistant_quota_reservation(
        v_row.user_id, v_row.request_id);
      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING
        'reconcile_ai_session_quota_residue: request % could not be released (%) -- skipped',
        v_row.request_id, SQLERRM;
    END;
  END LOOP;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.reconcile_ai_session_quota_residue()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_ai_session_quota_residue()
  TO service_role;


-- ----------------------------------------------------------------------
-- ROUTED ITEM 4: tie ai_session_approvals.member_id to the session's
-- relationship.
--
-- Nothing tied an approval row's member to the session's relationship,
-- which is why Gate 1's actor predicate in read_ai_session_turns was
-- the ONLY thing stopping a non-member holding a forged approval row at
-- the current context_revision from reading a full shared transcript
-- (Task 10's F2). The shipped read RPC does deny it, and Task 10's
-- Contract 5d now proves that; this makes the forged row impossible to
-- create in the first place, so the read gate and the write constraint
-- are independent defences.
--
-- IMPLEMENTED AS A TRIGGER, NOT AS A CHECK INSIDE
-- approve_ai_session_context. Deliberate, for two reasons:
--
--   1. approve_ai_session_context ALREADY performs this check. Read at
--      20260953040000: it requires the actor to be a current member of
--      an active, un-archived relationship before inserting, and the
--      inserted member_id IS that actor. So adding a check inside it
--      would be a second copy of a check that already passes, and
--      would protect nothing -- a forged row does not arrive through
--      that RPC. The gap is a DIRECT INSERT, which only
--      service_role/superuser can reach (no table grants, RLS on, zero
--      policies -- asserted by the 56-combination enumeration), i.e.
--      Plan C's edge function, a migration, or an operator.
--
--   2. It therefore does NOT touch Task 4's RPC at all. The routed item
--      offered "a trigger OR a check inside approve_ai_session_context"
--      and noted the latter touches a Task 4 RPC; the trigger is
--      strictly additive, re-defines no committed function, and
--      catches every write path including the ones the RPC does not
--      mediate.
--
-- The constraint enforced is MEMBERSHIP OF THE RELATIONSHIP, not
-- membership of an ACTIVE relationship. That distinction is
-- load-bearing: an approval is a historical fact about who approved a
-- context snapshot, and a relationship that later ends or is archived
-- must not retroactively invalidate rows already written, nor break
-- end_ai_session's purge. Liveness remains the read RPCs' Gate 1,
-- which Task 10 proved denies an ex-member even while holding a valid
-- current-revision approval. This trigger adds the one fact Gate 1
-- cannot infer: that the member was EVER party to this session's
-- relationship.
CREATE OR REPLACE FUNCTION public.assert_ai_session_approval_membership()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_relationship_id uuid;
BEGIN
  SELECT s.relationship_id INTO v_relationship_id
  FROM public.ai_sessions s WHERE s.id = NEW.session_id;
  -- No session row: the FK on session_id will reject this insert
  -- anyway. Returning NEW keeps the FK's own error message as the one
  -- the caller sees, rather than masking it with a less specific one.
  IF v_relationship_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = v_relationship_id
      AND (r.user_a = NEW.member_id OR r.user_b = NEW.member_id)
  ) THEN
    RAISE EXCEPTION
      'ai_session_approvals.member_id % is not a member of session %''s relationship %',
      NEW.member_id, NEW.session_id, v_relationship_id;
  END IF;

  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.assert_ai_session_approval_membership()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_ai_session_approvals_membership
  ON public.ai_session_approvals;
CREATE TRIGGER trg_ai_session_approvals_membership
  BEFORE INSERT OR UPDATE OF member_id, session_id
  ON public.ai_session_approvals
  FOR EACH ROW
  EXECUTE FUNCTION public.assert_ai_session_approval_membership();


-- ----------------------------------------------------------------------
-- ROUTED ITEM 1: the WRITE leg of the consent gate.
--
-- publish_ai_session_nearby_result had the same missing membership +
-- consent gate that read_ai_session_staging had (Task 10's F1), on the
-- WRITE side -- and the write leg is strictly worse than the read leg
-- it mirrors. The read leak made a staged Nearby result READABLE for up
-- to two minutes after a partner withdrew AI-processing consent; this
-- one COMMITS that content into the session's permanent transcript,
-- where it survives the withdrawal indefinitely. 20260953100100 closed
-- the read side and left this open.
--
-- Three gates are added, in the order they fire, AFTER the existing
-- requester/ownership checks so the asymmetry is unchanged:
--
--   1. active membership -- the actor is a current member of the
--      session's relationship, which must itself be active and
--      un-archived.
--   2. current consent   -- BOTH partners have a 'granted' consent
--      event at the CURRENT policy version.
--
-- The predicate shape is the BYTE-IDENTICAL shape
-- read_ai_session_turns and read_ai_session_staging already use --
-- same predicates, same `ORDER BY e.created_at DESC, e.id DESC LIMIT
-- 1`, same `COALESCE(a,false) AND COALESCE(b,false)` -- which matches
-- canonical get_ai_processing_consent_status and the covering index
-- idx_ai_processing_consent_current (relationship_id, user_id,
-- policy_version, created_at DESC, id DESC). A new shape here would be
-- a latent divergence; reusing the existing one is the point. Consent
-- cannot be read through Plan A's get_ai_processing_consent_status:
-- that function derives its actor from auth.uid() and RAISEs
-- 'Not authenticated' when it is NULL, and service_role -- this RPC's
-- only grantee -- carries no JWT.
--
-- IT DOES NOT LIFT VERBATIM, and the difference is not cosmetic: the
-- read RPCs resolve relationship_id from the staging row's session_id,
-- whereas this function has only v_request.session_id. The
-- `SELECT se.relationship_id FROM public.ai_sessions se` lookup is
-- therefore added first; without it the gates would compare against a
-- NULL relationship and deny every publish.
--
-- THE FAILURE MODE IS A RAISE, CHOSEN DELIBERATELY. The read RPCs are
-- SILENT by design (`RETURN`, zero rows) so a partner's result and a
-- stranger's are indistinguishable and neither RPC is an existence
-- oracle. That property does not transfer to a write: this function
-- RAISEs on every other rejection, and its success signature is
-- `(committed boolean, user_ordinal int, attune_ordinal int)`. A
-- verbatim `RETURN;` would return ZERO ROWS -- which the caller reads
-- as neither success nor failure, and which a caller that does
-- `SELECT committed FROM ...` would see as a NULL committed flag on a
-- publish that silently wrote nothing. Reporting success while
-- committing nothing is worse than either alternative. There is also
-- no oracle to protect: reaching these gates at all requires already
-- having passed `v_staging.requester_id = p_actor_id`, so the caller
-- demonstrably owns the row and learns nothing new from the raise. The
-- contract asserts the SPECIFIC exception, not a zero count.
--
-- The staging row is left in place on rejection rather than discarded.
-- A withdrawal that is later re-granted inside the staging row's
-- ~2-minute window should let the publish succeed, and
-- discard_ai_session_nearby_staging already exists for the explicit
-- discard. The row expires on its own regardless, and
-- read_ai_session_staging will not show it while consent is withdrawn
-- (20260953100100).
CREATE OR REPLACE FUNCTION public.publish_ai_session_nearby_result(
  p_actor_id uuid, p_request_id uuid
) RETURNS TABLE (committed boolean, user_ordinal int, attune_ordinal int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.ai_session_requests;
  v_staging public.ai_session_staging;
  v_user_ord smallint;
  v_attune_ord smallint;
  v_relationship_id uuid;
  v_user_a uuid;
  v_user_b uuid;
  v_version text := public.ai_current_consent_policy_version();
  v_a_granted boolean;
  v_b_granted boolean;
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_request FROM public.ai_session_requests WHERE id = p_request_id FOR UPDATE;
  IF v_request.id IS NULL THEN
    RAISE EXCEPTION 'Request not found';
  END IF;

  v_user_ord := (v_request.attempt_n * 2) - 1;
  v_attune_ord := v_request.attempt_n * 2;

  -- Idempotent replay of an already-committed publish, answered BEFORE
  -- the consent gate on purpose. The content is already in the
  -- transcript; re-reporting the ordinals of a write that already
  -- happened discloses nothing new and commits nothing, whereas
  -- raising here would make a retry after a withdrawal look like a
  -- failed publish and could drive a caller to publish again.
  IF v_request.state = 'committed' THEN
    RETURN QUERY SELECT true, v_user_ord::int, v_attune_ord::int;
    RETURN;
  END IF;

  SELECT * INTO v_staging FROM public.ai_session_staging
  WHERE request_id = p_request_id;
  IF v_staging.request_id IS NULL THEN
    RAISE EXCEPTION 'No staged result for this request';
  END IF;
  IF v_staging.requester_id != p_actor_id THEN
    RAISE EXCEPTION 'Only the requester may publish a staged Nearby result';
  END IF;
  IF v_staging.expires_at <= now() THEN
    RAISE EXCEPTION 'Staged result has expired';
  END IF;

  -- ---- ROUTED ITEM 1 STARTS HERE ----------------------------------
  -- The relationship lookup the read RPCs get for free and this
  -- function does not: it resolves only session_id.
  SELECT se.relationship_id INTO v_relationship_id
  FROM public.ai_sessions se WHERE se.id = v_request.session_id;
  IF v_relationship_id IS NULL THEN
    RAISE EXCEPTION 'Session unavailable';
  END IF;

  -- Gate: active membership in a live, un-archived relationship.
  SELECT r.user_a, r.user_b INTO v_user_a, v_user_b
  FROM public.relationships r
  WHERE r.id = v_relationship_id
    AND r.status = 'active' AND r.chat_archived_at IS NULL
    AND (r.user_a = p_actor_id OR r.user_b = p_actor_id);
  IF v_user_a IS NULL THEN
    RAISE EXCEPTION 'Not a current member of this relationship';
  END IF;

  -- Gate: current consent from BOTH partners at the current policy
  -- version. An event at an older version never counts as granted,
  -- which is what makes a version bump require two fresh grants.
  SELECT (e.action = 'granted') INTO v_a_granted
  FROM public.ai_processing_consent_events e
  WHERE e.relationship_id = v_relationship_id AND e.user_id = v_user_a
    AND e.policy_version = v_version
  ORDER BY e.created_at DESC, e.id DESC LIMIT 1;

  SELECT (e.action = 'granted') INTO v_b_granted
  FROM public.ai_processing_consent_events e
  WHERE e.relationship_id = v_relationship_id AND e.user_id = v_user_b
    AND e.policy_version = v_version
  ORDER BY e.created_at DESC, e.id DESC LIMIT 1;

  IF NOT (COALESCE(v_a_granted, false) AND COALESCE(v_b_granted, false)) THEN
    RAISE EXCEPTION 'AI processing consent is not current for this relationship';
  END IF;
  -- ---- ROUTED ITEM 1 ENDS HERE ------------------------------------

  INSERT INTO public.ai_session_turns (session_id, request_id, ordinal, role, author_id, kind, payload)
  VALUES
    (v_request.session_id, p_request_id, v_user_ord, 'user', v_request.actor_id, 'nearby_result',
     jsonb_build_object('instruction', 'nearby')),
    (v_request.session_id, p_request_id, v_attune_ord, 'attune', NULL, 'nearby_result',
     jsonb_build_object('reply_text', v_staging.reply_text, 'sources', v_staging.sources));

  DELETE FROM public.ai_session_staging WHERE request_id = p_request_id;
  UPDATE public.ai_session_requests SET state = 'committed' WHERE id = p_request_id;
  UPDATE public.ai_sessions SET revision = revision + 1 WHERE id = v_request.session_id;
  PERFORM public.mark_ai_assistant_usage_outcome(v_request.actor_id, p_request_id, 'succeeded', 2::smallint);

  RETURN QUERY SELECT true, v_user_ord::int, v_attune_ord::int;
END;
$$;
REVOKE ALL ON FUNCTION public.publish_ai_session_nearby_result(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.publish_ai_session_nearby_result(uuid, uuid)
  TO service_role;


-- ----------------------------------------------------------------------
-- CRON REGISTRATION -- every minute, matching the
-- process-chat-safety-outbox / process-scheduled-notifications
-- precedent in 20260907120000_register_scheduled_jobs.sql.
--
-- NOT the hourly cadence Plan A's ai_assist_drafts purge uses
-- (20260950100000): spec §8.2.3 sets Sessions' own purge-lag target at
-- five minutes after logical expiry, which an hourly job cannot meet
-- by an order of magnitude.
--
-- Three jobs rather than two. The brief specifies purge-ai-sessions and
-- reconcile-ai-session-leases; reconcile-ai-session-quota-residue is
-- added for routed item 3, on the same cadence because it resolves the
-- residue the other two can create and there is no reason for it to lag
-- behind them.
--
-- Each is unscheduled first: cron.schedule RAISEs on an existing
-- jobname, so re-applying this migration must be safe. Named
-- explicitly rather than truncating cron.job, so the 16 jobs
-- 20260907120000 registers and the unrelated 'analyse-session-sweep' /
-- 'expire_paint_ball' are left untouched.
--
-- These call Postgres functions directly rather than an edge function,
-- so they need no HTTP hop and no service-role key -- the same pattern
-- as generate-reminder-notifications and the dating reapers. That
-- matters for a Global Constraint: no SQL transaction may span a
-- provider HTTP call, and none of these three makes one. Each is a
-- no-op over an empty scan.
DO $$
DECLARE
  v_job text;
BEGIN
  FOREACH v_job IN ARRAY ARRAY[
    'purge-ai-sessions',
    'reconcile-ai-session-leases',
    'reconcile-ai-session-quota-residue'
  ]
  LOOP
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = v_job;
  END LOOP;
END;
$$;

SELECT cron.schedule(
  'purge-ai-sessions',
  '* * * * *',
  $$ SELECT public.purge_expired_ai_sessions(); $$
);

SELECT cron.schedule(
  'reconcile-ai-session-leases',
  '* * * * *',
  $$ SELECT public.reconcile_ai_session_leases(); $$
);

SELECT cron.schedule(
  'reconcile-ai-session-quota-residue',
  '* * * * *',
  $$ SELECT public.reconcile_ai_session_quota_residue(); $$
);


-- ======================================================================
-- MIGRATION PROVENANCE -- see 20260953090100's block for the full
-- table. After this file:
--
--   public.publish_ai_session_nearby_result
--     Task 8   20260953080000  (original)
--     Task 11  20260953110000  (THIS FILE) <-- WINS
--       Adds the membership + consent gate it never had (routed item 1
--       / Task 10's Ruling 8). The superseded body never reads
--       ai_processing_consent_events at all, which makes that table the
--       sharpest possible supersession marker. Asserted by
--       ai_session_purge_contracts.sql.
--
--   public.end_ai_session
--     UNCHANGED -- 20260953090100 (Task 9 fix round 1) still WINS. This
--     file does NOT re-define it, deliberately; see "WHY
--     end_ai_session IS NOT WIDENED" at the top.
--
--   public.purge_ai_session_content            NEW, this file
--   public.purge_expired_ai_sessions           NEW, this file
--   public.reconcile_ai_session_quota_residue  NEW, this file
--   public.assert_ai_session_approval_membership  NEW, this file
--
-- A future change to any function above must be made in a NEW
-- migration that sorts after the winning file, not in the original.
-- ======================================================================
