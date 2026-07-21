-- Forum/Opinions ban enforcement (FORUM.md §8 "Posting bans").
--
-- Every posting RPC already checks profiles.banned_until and rejects if set
-- (private.assert_can_post, create_forum_post — see
-- 20260716140000_forums_opinions_anonymity_hardening.sql), but nothing ever
-- WROTE banned_until: the "three confirmed violations -> 7-day ban" rule had
-- no implementation. The gate existed, the trigger for it did not.
--
-- "Confirmed violation" (FORUM.md §8) means a MODERATOR confirming a
-- report-driven removal — distinct from a user deleting their own content,
-- which already goes through a plain owner-scoped client UPDATE setting
-- removed_at (opinions_owner_update / opinion_comments equivalent /
-- forum_posts equivalent policies). A trigger on "removed_at went from NULL
-- to non-NULL" would misfire on ordinary self-deletes and auto-ban innocent
-- users for deleting their own posts. Since there is no admin UI yet (v1
-- launch defers moderation to direct Supabase dashboard access per FORUM.md
-- §13), the safe, explicit signal is a dedicated SECURITY DEFINER RPC that
-- only the service role may call — usable today from the SQL editor
-- (`select admin_confirm_content_removal(...)`) and ready for a future admin
-- UI to call directly once built.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS confirmed_violation_count int NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION public.admin_confirm_content_removal(
  p_content_type text,  -- 'opinion' | 'comment' | 'forum_post'
  p_content_id uuid
)
RETURNS TABLE (violation_count int, banned_until timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_author_id uuid;
  v_new_count int;
  v_ban_until timestamptz;
BEGIN
  -- Service-role only: requireServiceRole()-style gate. auth.uid() is NULL
  -- for the service-role key (it bypasses PostgREST's user JWT context
  -- entirely), so a NULL check here would let ANY unauthenticated caller in.
  -- The REVOKE below is the actual enforcement; this defends the intent.
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
    -- Already removed, or content_id did not match content_type — nothing
    -- to attribute a violation to. Not an error: idempotent no-op.
    RETURN QUERY SELECT 0, NULL::timestamptz;
    RETURN;
  END IF;

  UPDATE public.profiles
  SET confirmed_violation_count = confirmed_violation_count + 1
  WHERE id = v_author_id
  RETURNING confirmed_violation_count INTO v_new_count;

  IF v_new_count >= 3 THEN
    v_ban_until := now() + interval '7 days';
    UPDATE public.profiles
    SET banned_until = v_ban_until
    WHERE id = v_author_id;
  END IF;

  RETURN QUERY SELECT v_new_count, v_ban_until;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_confirm_content_removal(text, uuid) FROM PUBLIC, anon, authenticated;
-- No GRANT to authenticated: service-role only, matching the auth.role()
-- check above — clients can never call this directly.
