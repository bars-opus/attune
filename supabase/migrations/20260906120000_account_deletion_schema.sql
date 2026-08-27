-- Schema prerequisites for GDPR account deletion (§10).
--
-- The spec requires: "User can delete account and all data at any time",
-- "Couple's shared data (patterns, pulse) anonymised on one partner's
-- deletion", and "Safety events: anonymised after 12 months, never fully
-- deleted (legal protection)".
--
-- Deleting a user cascades from auth.users -> public.users -> 40 dependent
-- tables, which handles the user's OWN data correctly. Three defects sit in
-- the path of the shared/legal-hold data, all fixed here.

-- ---------------------------------------------------------------------------
-- 1. relationships.ended_by blocks deletion outright.
--
-- It references users(id) with NO ON DELETE clause, so it defaults to
-- NO ACTION. Any user who has ever ended a relationship cannot be deleted:
-- the DELETE raises a foreign-key violation. This is not a data-shape
-- preference — it makes the GDPR path fail closed for a real subset of
-- users.
--
-- SET NULL rather than CASCADE: ended_by is an audit annotation on a
-- relationship that belongs to BOTH partners. Cascading would delete the
-- surviving partner's relationship record because the other person pressed
-- "end" months earlier.
-- ---------------------------------------------------------------------------
ALTER TABLE public.relationships
  DROP CONSTRAINT IF EXISTS relationships_ended_by_fkey;

ALTER TABLE public.relationships
  ADD CONSTRAINT relationships_ended_by_fkey
  FOREIGN KEY (ended_by) REFERENCES public.users(id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------------
-- 2. Deletion is asymmetric between the two partners.
--
--   user_a uuid NOT NULL ... ON DELETE CASCADE
--   user_b uuid          ... ON DELETE SET NULL
--
-- So if user_a deletes their account the whole relationships row is
-- removed, and patterns / pulse_scores / verdicts (all
-- `relationship_id ... ON DELETE CASCADE`) go with it — destroying the
-- SURVIVING partner's history. If user_b deletes instead, the row survives
-- and that same shared data is preserved. Whose data survives should not
-- depend on which column a couple happened to be written into.
--
-- The spec is explicit that shared data is ANONYMISED, not destroyed, so
-- user_a becomes SET NULL to match user_b. Dropping NOT NULL is required
-- for SET NULL to be legal.
--
-- A relationship with both user columns NULL is the fully-anonymised end
-- state: no longer reachable by any user (every RLS policy on these tables
-- joins through user_a/user_b), while the derived analysis rows it
-- parents remain for aggregate/statistical use, exactly as
-- "Analysis results: retained indefinitely (anonymised)" requires.
-- ---------------------------------------------------------------------------
ALTER TABLE public.relationships
  ALTER COLUMN user_a DROP NOT NULL;

ALTER TABLE public.relationships
  DROP CONSTRAINT IF EXISTS relationships_user_a_fkey;

ALTER TABLE public.relationships
  ADD CONSTRAINT relationships_user_a_fkey
  FOREIGN KEY (user_a) REFERENCES public.users(id) ON DELETE SET NULL;

-- 2b. Symmetric NULL guard for the dating-pause trigger.
--
-- handle_relationship_dating_guard() guards user_b with an explicit
-- `IF NEW.user_b IS NOT NULL` but passes NEW.user_a straight through — safe
-- only because user_a was NOT NULL, a guarantee section 2 just removed. The
-- callee's `WHERE user_id = p_user_id` makes a NULL a harmless no-op, and
-- the trigger only fires for pending/active rows (an anonymised
-- relationship is neither), so this is defence in depth rather than a live
-- bug. Restoring the symmetry keeps the invariant local and readable
-- instead of resting on two unrelated facts elsewhere.
CREATE OR REPLACE FUNCTION public.sync_dating_pause_on_relationship()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IN ('pending', 'active') THEN
    IF NEW.user_a IS NOT NULL THEN
      PERFORM public.pause_dating_for_relationship_user(NEW.user_a);
    END IF;
    IF NEW.user_b IS NOT NULL THEN
      PERFORM public.pause_dating_for_relationship_user(NEW.user_b);
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- CREATE OR REPLACE resets privileges to the default (EXECUTE to PUBLIC),
-- so the original migration's REVOKE must be reapplied here or this
-- becomes a privilege regression rather than a null guard.
REVOKE ALL ON FUNCTION public.handle_relationship_dating_guard() FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- 3. safety_events cannot satisfy its own anonymisation invariant.
--
-- Its CHECK is:
--   (anonymised_at IS NULL     AND at_risk_user_id IS NOT NULL)
--   OR (anonymised_at IS NOT NULL AND at_risk_user_id IS NULL
--                                 AND relationship_id IS NULL)
--
-- Both FKs are ON DELETE SET NULL, so deleting a user NULLs
-- at_risk_user_id while anonymised_at stays NULL and relationship_id stays
-- populated — which satisfies NEITHER branch, and the DELETE fails with a
-- check violation. The legal-hold table is therefore the one table that
-- makes account deletion impossible.
--
-- A BEFORE trigger on users stamps the row through the valid transition in
-- one step, so the eventual FK SET NULL lands on an already-consistent row.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.anonymise_safety_events_for_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Clears BOTH identifying columns and stamps anonymised_at together, so
  -- the row moves directly from the first branch of the CHECK to the
  -- second and is never momentarily invalid.
  --
  -- Deliberately an UPDATE, never a DELETE: "never fully deleted (legal
  -- protection)". The event's tier, family, and timestamps survive for
  -- safeguarding review; only the link to a person is destroyed.
  UPDATE public.safety_events
     SET at_risk_user_id = NULL,
         relationship_id = NULL,
         anonymised_at   = COALESCE(anonymised_at, now())
   WHERE at_risk_user_id = OLD.id;

  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS anonymise_safety_events_before_user_delete
  ON public.users;

CREATE TRIGGER anonymise_safety_events_before_user_delete
  BEFORE DELETE ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.anonymise_safety_events_for_user();

-- ---------------------------------------------------------------------------
-- 4. Deletion request audit trail.
--
-- relationships.deletion_scheduled_at has existed since the core schema but
-- was never written by anything. GDPR allows fulfilment within 30 days and
-- requires the controller to evidence the request, so record it rather than
-- relying on the absence of a row as proof.
--
-- No user_id FK: the row must outlive the user it refers to (an FK would
-- cascade the evidence away with the account). user_ref is a bare uuid.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.account_deletion_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_ref uuid NOT NULL,
  email_ref text,
  requested_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  failure_reason text
);

CREATE INDEX IF NOT EXISTS account_deletion_requests_user_ref_idx
  ON public.account_deletion_requests (user_ref);

ALTER TABLE public.account_deletion_requests ENABLE ROW LEVEL SECURITY;

-- No policy is created: this is service-role-only audit evidence. With RLS
-- enabled and no policy, anon/authenticated read nothing, while the service
-- role (which bypasses RLS) can still write it.
REVOKE ALL ON public.account_deletion_requests FROM anon, authenticated;
