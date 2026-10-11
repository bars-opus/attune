-- Task 10: authorized read RPCs. Spec §7.2.
--
-- Both functions are STABLE (read-only) but still SECURITY DEFINER,
-- because ai_session_turns and ai_session_staging have RLS enabled with
-- ZERO policies and no table grant to `authenticated` at all (see
-- 20260953010100 / 20260953020100). There is no row-level fallback for
-- these functions to wrap: they ARE the entire read path for session
-- content, not a convenience layer over a SELECT policy.
--
-- Neither function takes a lock. Both are STABLE and mutate nothing, so
-- they add no entry to this plan's fixed lock order (relationship
-- advisory lock -> requester quota advisory lock -> ai_sessions row
-- lock -> request row lock). A read that took the relationship lock
-- would serialize every read behind every write for no correctness
-- gain: a read is a single consistent snapshot either way, and the
-- worst a concurrent end_ai_session can do is make a read return rows
-- that were legitimately readable by that same actor microseconds
-- earlier -- the identical, already-accepted shape of Ruling 1 on
-- share_ai_session_turn's TOCTOU (Task 9 fix round 1).
--
-- DELIBERATE SILENCE, NOT AN OVERSIGHT: every unauthorized outcome
-- below is `RETURN` (zero rows), never RAISE. A distinguishable error
-- would make these RPCs an existence oracle -- "session not found"
-- versus "not authorized" tells a caller whether a private session
-- exists on a relationship they are a member of, which is exactly the
-- disclosure spec §3.1's TARGET_UNAVAILABLE precedent exists to
-- prevent. The partner's zero and a stranger's zero must be
-- byte-identical, and Task 10's contract test asserts precisely that.
-- The ONE exception is the p_actor_id NULL check, which is a caller
-- bug rather than an authorization outcome; it still returns silently
-- here rather than raising, because a NULL actor can never match any
-- authorization branch below and raising would only add a second
-- distinguishable response shape to a function whose whole security
-- property is having exactly one.

-- ---------------------------------------------------------------------
-- read_ai_session_turns -- authorized content read.
--
-- Gates, all four required (spec §7.2: "Content reads require active
-- membership, current consent, unexpired active state and creator
-- (private) or accepted participant (shared)"):
--
--   1. active membership  -- the actor is a current member of the
--      session's relationship, which must itself be active and
--      un-archived. The brief's sample SQL omitted this gate; its own
--      interface description requires it, and so does the spec clause
--      the brief quotes. Without it, a user whose relationship has
--      since ended or been archived keeps reading session content.
--   2. current consent    -- BOTH partners have a 'granted' consent
--      event at the CURRENT policy version. Also omitted from the
--      brief's sample SQL, also required by its interface text. This
--      is the gate that makes a withdrawal effective immediately on
--      reads, not merely on new generations.
--   3. unexpired active state -- state = 'active' and (expires_at IS
--      NULL OR expires_at > now()).
--   4. creator (private) or accepted participant (shared) -- for a
--      shared session, "accepted" means holding an ai_session_approvals
--      row at the session's CURRENT context_revision, so a partner who
--      approved an older snapshot does not inherit access to a
--      re-approved one.
--
-- Consent is computed inline rather than by calling Plan A's
-- get_ai_processing_consent_status(relationship_id). That function
-- derives its actor from auth.uid() and RAISEs 'Not authenticated' when
-- it is NULL -- and a service_role connection (the only caller this
-- function is granted to) carries no JWT, so auth.uid() is NULL there.
-- Calling it would turn every read into an unconditional exception. The
-- inline form below is the same "latest event at the current policy
-- version, per user, both must be 'granted'" rule that function
-- implements, keyed on the session's two relationship members instead
-- of on auth.uid().
CREATE OR REPLACE FUNCTION public.read_ai_session_turns(
  p_actor_id uuid, p_session_id uuid
) RETURNS SETOF public.ai_session_turns
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_session public.ai_sessions;
  v_user_a uuid;
  v_user_b uuid;
  v_version text := public.ai_current_consent_policy_version();
  v_a_granted boolean;
  v_b_granted boolean;
  v_authorized boolean := false;
BEGIN
  IF p_actor_id IS NULL THEN
    RETURN;
  END IF;

  SELECT * INTO v_session FROM public.ai_sessions WHERE id = p_session_id;
  IF v_session.id IS NULL THEN
    RETURN;
  END IF;

  -- Gate 3: unexpired active state.
  IF v_session.state != 'active' THEN
    RETURN;
  END IF;
  IF v_session.expires_at IS NOT NULL AND v_session.expires_at <= now() THEN
    RETURN;
  END IF;

  -- Gate 1: active membership in a live, un-archived relationship.
  SELECT r.user_a, r.user_b INTO v_user_a, v_user_b
  FROM public.relationships r
  WHERE r.id = v_session.relationship_id
    AND r.status = 'active' AND r.chat_archived_at IS NULL
    AND (r.user_a = p_actor_id OR r.user_b = p_actor_id);
  IF v_user_a IS NULL THEN
    RETURN;
  END IF;

  -- Gate 2: current consent from BOTH partners at the current policy
  -- version. An event at an older version never counts as granted,
  -- which is what makes a version bump require two fresh grants.
  SELECT (e.action = 'granted') INTO v_a_granted
  FROM public.ai_processing_consent_events e
  WHERE e.relationship_id = v_session.relationship_id AND e.user_id = v_user_a
    AND e.policy_version = v_version
  ORDER BY e.created_at DESC, e.id DESC LIMIT 1;

  SELECT (e.action = 'granted') INTO v_b_granted
  FROM public.ai_processing_consent_events e
  WHERE e.relationship_id = v_session.relationship_id AND e.user_id = v_user_b
    AND e.policy_version = v_version
  ORDER BY e.created_at DESC, e.id DESC LIMIT 1;

  IF NOT (COALESCE(v_a_granted, false) AND COALESCE(v_b_granted, false)) THEN
    RETURN;
  END IF;

  -- Gate 4: creator (private) or accepted participant (shared).
  IF v_session.visibility = 'private' THEN
    v_authorized := (v_session.creator_id = p_actor_id);
  ELSE
    v_authorized := EXISTS (
      SELECT 1 FROM public.ai_session_approvals a
      WHERE a.session_id = p_session_id
        AND a.member_id = p_actor_id
        AND a.revision = v_session.context_revision
    );
  END IF;

  IF NOT v_authorized THEN
    RETURN;
  END IF;

  RETURN QUERY SELECT * FROM public.ai_session_turns
  WHERE session_id = p_session_id
  ORDER BY ordinal;
END;
$$;
REVOKE ALL ON FUNCTION public.read_ai_session_turns(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.read_ai_session_turns(uuid, uuid)
  TO service_role;

-- ---------------------------------------------------------------------
-- read_ai_session_staging -- the author-checking RPC for own staged
-- Nearby (spec §7.2: "Own staged Nearby is accessible only through an
-- author-checking RPC, never a shared SELECT policy").
--
-- Deliberately NARROWER than read_ai_session_turns, and that asymmetry
-- is the point. Staging is requester-private by construction: the
-- partner of a SHARED session must not read it even though they can
-- read that session's turns. So the only authorization this needs is
-- requester_id = p_actor_id -- there is no visibility branch, no
-- approvals lookup, and no partner path at all. The session-level gates
-- would be redundant here (staging rows are purged in the same
-- transaction that closes the session, per the Global Constraint, and
-- expires_at already caps them at min(now+2min, session expiry)), but
-- expires_at is still checked so an unpurged residue row cannot be read
-- after its own lifetime, independent of Task 11's backstop reconciler.
CREATE OR REPLACE FUNCTION public.read_ai_session_staging(
  p_actor_id uuid, p_request_id uuid
) RETURNS SETOF public.ai_session_staging
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
  IF p_actor_id IS NULL THEN
    RETURN;
  END IF;
  RETURN QUERY SELECT * FROM public.ai_session_staging
  WHERE request_id = p_request_id AND requester_id = p_actor_id
    AND expires_at > now();
END;
$$;
REVOKE ALL ON FUNCTION public.read_ai_session_staging(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.read_ai_session_staging(uuid, uuid)
  TO service_role;

-- ======================================================================
-- MIGRATION PROVENANCE -- see 20260953090100's own block for the full
-- table. This file introduces two NEW functions and supersedes nothing.
-- The functions it defines are authoritative here:
--
--   public.read_ai_session_turns    Task 10  20260953100000  (original)
--   public.read_ai_session_staging  Task 10  20260953100000  (original)
--
-- Task 10 additionally adds the SUPERSESSION-ORDERING contract the
-- Task 9 re-review flagged as missing (deferred note 2): nothing
-- previously stopped a future out-of-order re-apply of a superseded
-- migration from silently reverting the winning definition. The
-- contract lives in supabase/tests/ai_session_read_authorization_contracts.sql
-- and asserts the LIVE body (pg_get_functiondef) of each superseded
-- function carries the marker only its WINNING definition has.
-- ======================================================================
