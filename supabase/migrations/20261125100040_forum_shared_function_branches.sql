-- Spec 3 (forum removal) W3, migration 5 of 6: the shared functions lose
-- their forum branches (Spec 3 §6.3 step 5, §3.9; V8, V11; R15-R17). Each is
-- its LIVE body (pg_get_functiondef on attune_spec3a at 9bac1bdb; migration
-- 1 refuses to run unless the database holds exactly that body, md5 of
-- prosrc) with only the lines below changed; review is a pure diff against
-- the source named. Opinions limits, bans, strikes, stamps and the two
-- moderation notices Spec 1 W9b restored are unchanged.
--   * private.assert_can_post(uuid, text) (live: 20260716140000): removed,
--     verbatim:
--         ELSIF p_kind = 'topic' THEN
--           -- 3 submissions per 7 days.
--           SELECT count(*) INTO v_count
--           FROM public.forum_topics
--           WHERE submitted_by = p_user_id AND created_at > now() - interval '7 days';
--           IF v_count >= 3 THEN RAISE EXCEPTION 'daily_limit' USING ERRCODE = '53400'; END IF;
--         -- forum_post per-forum limits are enforced in create_forum_post (needs topic_id).
--     and search_path 'public', 'private' becomes '' (every relation was
--     already qualified). 'topic' now meets only the ban gate.
--   * public.admin_confirm_content_removal(text, uuid) (live: 20261107100000):
--     removed, verbatim:
--         ELSIF p_content_type = 'forum_post' THEN
--           UPDATE public.forum_posts SET removed_at = now()
--           WHERE id = p_content_id AND removed_at IS NULL
--           RETURNING user_id INTO v_author_id;
--     so 'forum_post' raises invalid_content_type (22023) like any unknown
--     type. Spec 1 W9b's notices and W9d's stamp are untouched.
--   * private.opinion_stamp_backfill() (Spec 1 W9d, live: 20261107100000;
--     added after Spec 3 was written, found by migration 1's inventory):
--     removed, verbatim:
--                     UNION ALL
--                     SELECT f.removed_at FROM public.forum_posts AS f WHERE f.user_id = r.id AND f.removed_at IS NOT NULL
--     With no forum post left the branch reads nothing. Removed forum posts
--     no longer count, from v_removed as well as from the earliest date: an
--     account whose strikes include forum-post removals now fails
--     v_removed >= strikes and is skipped as unverified (fails closed: "not
--     shown"). W9d's own apply-time backfill, run with the keys set before
--     this wave, stamps such accounts while forum_posts still exists (owner
--     checklist).
-- ACLs re-asserted as they are: assert_can_post and the backfill are the
-- database's own (the backfill is owner-run; dating_rls_canary.sql pins no
-- service_role); admin_confirm_content_removal is the service role's.
-- private.enqueue_forum_notification is not touched (every Opinions caller
-- uses named arguments; p_forum_post_id stays in its signature).
-- Idempotent: CREATE OR REPLACE.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION private.assert_can_post(p_user_id uuid, p_kind text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE
  v_banned_until timestamptz;
  v_count int;
  v_last timestamptz;
BEGIN
  -- Ban gate: banned users may read but not post.
  SELECT banned_until INTO v_banned_until FROM public.profiles WHERE id = p_user_id;
  IF v_banned_until IS NOT NULL AND v_banned_until > now() THEN
    RAISE EXCEPTION 'posting_banned' USING ERRCODE = '42501';
  END IF;

  IF p_kind = 'opinion' THEN
    -- 5 per 24h, 60s cooldown.
    SELECT count(*), max(created_at) INTO v_count, v_last
    FROM public.opinions
    WHERE user_id = p_user_id AND created_at > now() - interval '24 hours';
    IF v_count >= 5 THEN RAISE EXCEPTION 'daily_limit' USING ERRCODE = '53400'; END IF;
    IF v_last IS NOT NULL AND v_last > now() - interval '60 seconds' THEN
      RAISE EXCEPTION 'cooldown' USING ERRCODE = '53400';
    END IF;

  ELSIF p_kind = 'comment' THEN
    -- 20 per 24h.
    SELECT count(*) INTO v_count
    FROM public.opinion_comments
    WHERE user_id = p_user_id AND created_at > now() - interval '24 hours';
    IF v_count >= 20 THEN RAISE EXCEPTION 'daily_limit' USING ERRCODE = '53400'; END IF;
  END IF;
  -- Spec 3 W3: any other kind (the retired 'topic' among them) has no limit
  -- beyond the ban gate above.
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_confirm_content_removal(p_content_type text, p_content_id uuid)
 RETURNS TABLE(violation_count integer, banned_until timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE
  v_author_id uuid;
  v_new_count int;
  v_ban_until timestamptz;
  v_prev_ban timestamptz; -- Spec 1 W9b
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  IF p_content_type = 'opinion' THEN
    UPDATE public.opinions SET removed_at = now()
    WHERE id = p_content_id AND removed_at IS NULL
    RETURNING user_id INTO v_author_id;
  ELSIF p_content_type = 'comment' THEN
    UPDATE public.opinion_comments SET removed_at = now()
    WHERE id = p_content_id AND removed_at IS NULL
    RETURNING user_id INTO v_author_id;
  ELSE
    -- Spec 3 W3: 'forum_post' is refused here too; its table is gone.
    RAISE EXCEPTION 'invalid_content_type' USING ERRCODE = '22023';
  END IF;

  IF v_author_id IS NULL THEN
    RETURN QUERY SELECT 0, NULL::timestamptz;
    RETURN;
  END IF;

  UPDATE public.profiles
  SET confirmed_violation_count = confirmed_violation_count + 1
  WHERE id = v_author_id
  RETURNING confirmed_violation_count INTO v_new_count;

  -- Spec 1 W9b (D17): the removal notice, to the author only.
  PERFORM private.enqueue_forum_notification(
    p_user_id    => v_author_id,
    p_title      => 'Post removed',
    p_body       => 'One of your posts was removed for breaking the Opinions guidelines.',
    p_type       => 'forum_content_removed',
    p_opinion_id => CASE WHEN p_content_type = 'opinion' THEN p_content_id END,
    p_comment_id => CASE WHEN p_content_type = 'comment' THEN p_content_id END
  );

  IF v_new_count >= 3 THEN
    -- Never move the ban backward: a moderator confirming several
    -- violations in one sitting extends the ban past whichever is later
    -- (now, or an existing future banned_until), and never re-shortens or
    -- re-applies a ban that already ran its course before this confirmation.
    SELECT GREATEST(COALESCE(p.banned_until, now()), now()) + interval '7 days', p.banned_until -- Spec 1 W9b: OPN-BAN-42702
    INTO v_ban_until, v_prev_ban
    FROM public.profiles AS p WHERE p.id = v_author_id;

    UPDATE public.profiles
    SET banned_until = v_ban_until
    WHERE id = v_author_id;

    -- Spec 1 W9b (D17): the ban notice, new or extended.
    PERFORM private.enqueue_forum_notification(
      p_user_id => v_author_id,
      p_title   => 'Posting paused',
      p_body    => CASE WHEN v_prev_ban > now()
                        THEN 'Your pause on posting in Opinions has been extended.'
                        ELSE 'You can''t post in Opinions for 7 days.' END,
      p_type    => 'forum_posting_banned'
    );
  END IF;

  -- Spec 1 W9d (O4; S2 W1 B3 I-1): this strike, and the ban it set, are
  -- Spec 1 W9d stamped with the number the author holds now; never raises.
  IF v_new_count IS NOT NULL THEN -- Spec 1 W9d
    PERFORM private.opinion_stamp_enforcement(v_author_id, 1, v_ban_until); -- Spec 1 W9d
  END IF; -- Spec 1 W9d
  RETURN QUERY SELECT v_new_count, v_ban_until;
END;
$function$;

CREATE OR REPLACE FUNCTION private.opinion_stamp_backfill()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
-- Owner-run (owner checklist): strikes and live bans no stamp covers, under
-- the number each account holds now, only when that number provably hasn't
-- changed since the account's earliest removed post (M-1 ruling). -1 while
-- the key is missing.
DECLARE
  r record;
  v_n integer := 0;
  v_first timestamptz;
  v_removed integer;
BEGIN
  IF public.dating_phone_hmac('attune:dating_exclusion_key:fingerprint:v1') IS NULL THEN
    RAISE NOTICE 'dating_exclusion_key is not set: no Opinions strike stamped';
    RETURN -1;
  END IF;
  FOR r IN
    SELECT p.id, p.confirmed_violation_count AS strikes,
           CASE WHEN p.banned_until > now() THEN p.banned_until END AS ban,
           coalesce((SELECT sum(s.strikes) FROM private.opinion_enforcement_stamps AS s
                      WHERE s.user_id = p.id), 0)::integer AS stamped,
           (SELECT max(s.ban_until) FROM private.opinion_enforcement_stamps AS s
             WHERE s.user_id = p.id) AS stamped_ban,
           (SELECT a.phone_confirmed_at FROM auth.users AS a WHERE a.id = p.id) AS confirmed_at,
           (SELECT (to_jsonb(a) ->> 'phone_change_sent_at')::timestamptz FROM auth.users AS a
             WHERE a.id = p.id) AS change_sent_at
      FROM public.profiles AS p
     WHERE p.confirmed_violation_count > 0 OR p.banned_until > now()
  LOOP
    IF r.strikes > r.stamped OR (r.ban IS NOT NULL AND (r.stamped_ban IS NULL OR r.stamped_ban < r.ban)) THEN
      SELECT min(x.removed_at), count(*)::integer INTO v_first, v_removed
        FROM (SELECT o.removed_at FROM public.opinions AS o WHERE o.user_id = r.id AND o.removed_at IS NOT NULL
              UNION ALL
              SELECT c.removed_at FROM public.opinion_comments AS c WHERE c.user_id = r.id AND c.removed_at IS NOT NULL) AS x; -- Spec 3 W3: forum posts are gone
      -- The number held now provably held since the earliest removal, or
      -- nothing is stamped (a NULL anywhere is "not shown").
      IF NOT coalesce(v_removed >= r.strikes
                      AND r.confirmed_at <= v_first
                      AND (r.change_sent_at IS NULL OR r.change_sent_at <= v_first), false) THEN
        PERFORM private.bump_metric_internal('opinions.enforcement.backfill_phone_unverified');
        CONTINUE;
      END IF;
      IF private.opinion_stamp_enforcement(r.id, greatest(r.strikes - r.stamped, 0), r.ban) THEN
        v_n := v_n + 1;
      END IF;
    END IF;
  END LOOP;
  RETURN v_n;
END;
$function$;

REVOKE ALL ON FUNCTION private.assert_can_post(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_confirm_content_removal(text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_confirm_content_removal(text, uuid) TO service_role;
REVOKE ALL ON FUNCTION private.opinion_stamp_backfill() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
