-- Entry gates (2026-11-27) fix round, owner ruling: un-reacting must
-- always work. 20261127100070 gated the four decrement counter RPCs with
-- the rest; a held or not-ready account could delete its own reaction row
-- (deletes are never gated) but its decrement was refused, leaving the
-- public count one too high. Each function below is its LIVE body (as
-- 20261127100070 left it; the drift guard refuses any other body) with
-- only the account_ready gate block removed (a comment says why).
-- search_path stays ''. The increments stay gated.
--   * public.decrement_opinion_like_count(uuid)
--   * public.decrement_opinion_dislike_count(uuid)
--   * public.decrement_opinion_comment_count(uuid)
--   * public.decrement_comment_like_count(uuid)
-- supabase/tests/entry_gates_contracts.sql section G now allowlists them
-- as "undo of your own action". Known, separate follow-up (not fixed
-- here): the counter RPCs trust the caller, so any complete account can
-- move any opinion's counts without having reacted.
-- ACLs kept by CREATE OR REPLACE; no grant changes.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- Drift guard: each function must hold exactly the body this was built
-- from (md5 of prosrc), or already the new one (a re-run).
DO $guard$
DECLARE
  r record;
  v_md5 text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.decrement_opinion_like_count(uuid)', 'a9847abfcc36b21786aee3457092c6d0', 'e094093a3fd5005ad62ae385c9c86a46'),
      ('public.decrement_opinion_dislike_count(uuid)', 'fbeb96c31652b19af1185f38d0e1f978', '541bbd29b2ac144c76d08d701eeb01c5'),
      ('public.decrement_opinion_comment_count(uuid)', '20bc60ea78a3029e14b4e745f97e928a', '01976c382bce1d88be636e49625806b2'),
      ('public.decrement_comment_like_count(uuid)', 'e03810a42d1c29717db8b584290edf1c', 'bf9bdcc47b745f772b5e656997d3cb19')
    ) AS t(sig, before_md5, after_md5)
  LOOP
    SELECT pg_catalog.md5(p.prosrc) INTO v_md5
      FROM pg_catalog.pg_proc AS p WHERE p.oid = pg_catalog.to_regprocedure(r.sig);
    IF v_md5 IS NULL THEN
      RAISE EXCEPTION 'entry gates decrements: % is missing', r.sig;
    END IF;
    IF v_md5 NOT IN (r.before_md5, r.after_md5) THEN
      RAISE EXCEPTION 'entry gates decrements: % is not the body this migration was built from (md5 %)', r.sig, v_md5;
    END IF;
  END LOOP;
END $guard$;

CREATE OR REPLACE FUNCTION public.decrement_opinion_like_count(p_opinion_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_like_count int;
  v_dislike_count int;
BEGIN
  -- Entry gates 2026-11-27 (owner ruling): an undo of the caller's own
  -- reaction, so it is never gated (un-reacting must always work).
  UPDATE public.opinions
  SET like_count = GREATEST(COALESCE(like_count, 0) - 1, 0)
  WHERE id = p_opinion_id
  RETURNING like_count, dislike_count INTO v_like_count, v_dislike_count;

  PERFORM realtime.send(
    jsonb_build_object(
      'opinion_id', p_opinion_id,
      'like_count', v_like_count,
      'dislike_count', v_dislike_count
    ),
    'counts',
    'opinion-counts:' || p_opinion_id,
    false
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.decrement_opinion_dislike_count(p_opinion_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_like_count int;
  v_dislike_count int;
BEGIN
  -- Entry gates 2026-11-27 (owner ruling): an undo of the caller's own
  -- reaction, so it is never gated (un-reacting must always work).
  UPDATE public.opinions
  SET dislike_count = GREATEST(COALESCE(dislike_count, 0) - 1, 0)
  WHERE id = p_opinion_id
  RETURNING like_count, dislike_count INTO v_like_count, v_dislike_count;

  PERFORM realtime.send(
    jsonb_build_object(
      'opinion_id', p_opinion_id,
      'like_count', v_like_count,
      'dislike_count', v_dislike_count
    ),
    'counts',
    'opinion-counts:' || p_opinion_id,
    false
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.decrement_opinion_comment_count(p_opinion_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  -- Entry gates 2026-11-27 (owner ruling): an undo of the caller's own
  -- reaction, so it is never gated (un-reacting must always work).
  UPDATE public.opinions
  SET comment_count = GREATEST(COALESCE(comment_count, 0) - 1, 0)
  WHERE id = p_opinion_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.decrement_comment_like_count(p_comment_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  -- Entry gates 2026-11-27 (owner ruling): an undo of the caller's own
  -- reaction, so it is never gated (un-reacting must always work).
  UPDATE public.opinion_comments
  SET like_count = GREATEST(COALESCE(like_count, 0) - 1, 0)
  WHERE id = p_comment_id;
END;
$function$;

COMMIT;
