-- Spec 1 W9b, migration 18 (spec §4.7 #18; D17; Spec 3 V8 and §10 F-1):
-- the two Opinions moderation notices restored, and OPN-BAN-42702 fixed.
-- public.admin_confirm_content_removal is re-created from its LIVE body
-- (20260802120000:205-267, checked identical to pg_get_functiondef on
-- attune_spec3a while writing the plan), keeping the service-role gate,
-- the three content-type branches (Spec 3 W3 removes forum_post later from
-- this body), the idempotent no-op, the strike count and the never-shorten
-- ban extension, with only:
--   * SET search_path = '' (every name was already schema-qualified);
--   * OPN-BAN-42702: the ban-extension SELECT qualifies the column
--     (public.profiles AS p ... p.banned_until). RETURNS TABLE
--     (violation_count int, banned_until timestamptz) declares an OUT
--     variable named banned_until, so the bare column raised 42702 at the
--     third confirmed removal and no ban was ever set. The same SELECT now
--     also reads the ban as it was (v_prev_ban), for the notice's wording;
--   * the two notices the 20260802 rewrite dropped, through the kept
--     private.enqueue_forum_notification, to the author only:
--     forum_content_removed after a removal that found an author (with
--     p_opinion_id or p_comment_id), and forum_posting_banned when the ban
--     starts ("You can't post in Opinions for 7 days.") or moves ("Your
--     pause on posting in Opinions has been extended."). Nothing is queued
--     when the content was already removed. Taps land on home
--     (notification_config.dart, unchanged).
-- Not gated: it restores live behaviour lost in 20260802 (spec §8 W9b). The
-- return shape is unchanged. Release note: the first real 7-day bans
-- follow this fix (spec §9).
-- Grants in 20261104120010_opinion_moderation_notices_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

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
  ELSIF p_content_type = 'forum_post' THEN
    UPDATE public.forum_posts SET removed_at = now()
    WHERE id = p_content_id AND removed_at IS NULL
    RETURNING user_id INTO v_author_id;
  ELSE
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

  RETURN QUERY SELECT v_new_count, v_ban_until;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_confirm_content_removal(text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_confirm_content_removal(text, uuid) TO service_role;

COMMIT;
