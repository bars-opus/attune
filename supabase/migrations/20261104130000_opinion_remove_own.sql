-- Spec 1 W9b, migration 19 (spec §4.7 #19; OPN-DELETE-RLS): removing your
-- own opinion or comment.
-- Today the app deletes with a direct UPDATE ... SET removed_at, which needs
-- SELECT on the row, so Postgres checks the new row against the SELECT
-- policies opinions_public_read / opinion_comments_public_read
-- (removed_at IS NULL ...) and refuses it ("new row violates row-level
-- security policy"). No policy is loosened: two owner-checked definer RPCs
-- do the removal instead, and the app calls them.
--   * remove_my_opinion(p_opinion_id): sets removed_at on the caller's own
--     live opinion. Someone else's, a missing or an already-removed one
--     changes nothing and raises nothing (today's client contract: a
--     non-owner delete is a no-op).
--   * remove_my_comment(p_comment_id): the same for a comment, and lowers
--     the parent opinion's comment_count by one (never below 0) only when
--     this call removed a live comment, so a repeat never decrements twice.
--     The app stops calling decrement_opinion_comment_count for a delete.
-- Neither is gated by the posting ban or opinions_safety_v1: removing your
-- own words is never a posting act. Not flagged (spec §8 W9b).
-- Grants in 20261104130010_opinion_remove_own_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.remove_my_opinion(p_opinion_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  UPDATE public.opinions AS o
     SET removed_at = pg_catalog.now()
   WHERE o.id = p_opinion_id
     AND o.user_id = auth.uid()
     AND o.removed_at IS NULL;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.remove_my_comment(p_comment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_opinion uuid;
BEGIN
  UPDATE public.opinion_comments AS c
     SET removed_at = pg_catalog.now()
   WHERE c.id = p_comment_id
     AND c.user_id = auth.uid()
     AND c.removed_at IS NULL
  RETURNING c.opinion_id INTO v_opinion;

  -- Only when this call removed a live comment: a repeat never decrements.
  IF v_opinion IS NOT NULL THEN
    UPDATE public.opinions AS o
       SET comment_count = GREATEST(COALESCE(o.comment_count, 0) - 1, 0)
     WHERE o.id = v_opinion;
  END IF;
END;
$fn$;

REVOKE ALL ON FUNCTION public.remove_my_opinion(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.remove_my_comment(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_my_opinion(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_my_comment(uuid) TO authenticated;

COMMIT;
