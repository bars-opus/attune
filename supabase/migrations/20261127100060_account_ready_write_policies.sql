-- Entry gates (2026-11-27 audit, gap 2): user-content writes need a
-- complete account (private.account_ready: users row, 18+ date of birth,
-- EULA >= 2, no open hold). Before this, a session verified by OTP but
-- refused at A5 (under 18) or never finished could post Opinions and write
-- couple/personal content straight through the API.
--
-- How: one RESTRICTIVE policy per table and command, TO authenticated,
-- WITH CHECK (public.my_account_ready()). Restrictive policies are ANDed
-- with the table's existing permissive ones, so every existing policy
-- stays byte-for-byte as it is (no expression re-typed), the gate holds
-- for any permissive write policy added later, and the gate is one name
-- to find (account_ready_insert / account_ready_update). UPDATE uses
-- USING (true): which rows a caller may target is still the permissive
-- policy's; only the written row must come from a complete account.
-- SELECT and DELETE are untouched (reads never change; a person may still
-- delete their own rows). The service role bypasses RLS (edge functions,
-- crons), and SECURITY DEFINER RPCs run as the table owner, so neither is
-- affected by the policies.
--
-- Tables gated (INSERT and UPDATE each unless noted), with the permissive
-- policy each one now narrows:
--   Opinions
--     opinions               opinions_authenticated_insert, opinions_owner_update
--     opinion_comments       opinion_comments_owner_insert, opinion_comments_owner_update
--     opinion_reactions      opinion_reactions_owner_write (ALL)
--     opinion_reposts        opinion_reposts_owner (ALL)
--     opinion_follows        opinion_follows_owner (ALL)
--     comment_likes          comment_likes_owner (ALL)
--     forum_reports          forum_reports_insert_own (INSERT only; Opinions'
--                            report table, kept by Spec 3 W3)
--   Couple / personal content
--     reminders              reminders_insert_members, reminders_update_members
--     weekly_checkins        checkins_private (ALL)
--     quiz_shares            "quiz shares owner insert", "quiz shares owner update"
--     timeline_events        timeline_insert_members, timeline_update_owner
--     place_updates          place_updates_author_write (INSERT only; no
--                            UPDATE policy exists)
--     couple_family_members  family_members_insert_members, family_members_update_members
--
-- Deliberately NOT gated (and why):
--   users, profiles, onboarding_profiles, account_birthdates: the sign-up
--     path writes them for an account that is not complete yet (and the
--     first three's writers are complete_sign_up / set_my_birth_date /
--     onboarding, by design before readiness).
--   notification_settings, user_preferences, in_app_notifications,
--     translator_logs, opinion_saves, opinion_hides, opinion_mutes,
--     tag_follows: private settings and safety tools nobody else sees.
--   messages, message_* , stories and chat tables: the core chat path;
--     left for an owner decision (see server-gates-report.md).
--   Games tables (game_*, mirror_*, thirty_six_*, chapter_reflections,
--     custom_*_questions, session_idempotency_keys, streak_clips): Games
--     is out of scope for this wave.
--
-- Opinions' own write RPCs are SECURITY DEFINER, so the policies above do
-- not reach them. private.assert_can_post(uuid, text), the shared posting
-- gate create_opinion (and so create_opinion_with_poll /
-- create_opinion_with_quote) and create_opinion_comment call first, is
-- re-created from its LIVE body (20261125100040) with one check added
-- right after the ban gate: not account_ready -> 'account_not_ready'
-- (42501), before the limits. A banned person keeps reading
-- posting_banned first. Nothing else in it changes.
BEGIN;
SET LOCAL lock_timeout = '5s';

DO $$
DECLARE
  t text;
  v_insert constant text[] := ARRAY[
    'opinions', 'opinion_comments', 'opinion_reactions', 'opinion_reposts',
    'opinion_follows', 'comment_likes', 'forum_reports',
    'reminders', 'weekly_checkins', 'quiz_shares', 'timeline_events',
    'place_updates', 'couple_family_members'];
  v_update constant text[] := ARRAY[
    'opinions', 'opinion_comments', 'opinion_reactions', 'opinion_reposts',
    'opinion_follows', 'comment_likes',
    'reminders', 'weekly_checkins', 'quiz_shares', 'timeline_events',
    'couple_family_members'];
BEGIN
  FOREACH t IN ARRAY v_insert LOOP
    EXECUTE format('DROP POLICY IF EXISTS account_ready_insert ON public.%I', t);
    EXECUTE format(
      'CREATE POLICY account_ready_insert ON public.%I AS RESTRICTIVE FOR INSERT TO authenticated '
      'WITH CHECK (public.my_account_ready())', t);
  END LOOP;
  FOREACH t IN ARRAY v_update LOOP
    EXECUTE format('DROP POLICY IF EXISTS account_ready_update ON public.%I', t);
    EXECUTE format(
      'CREATE POLICY account_ready_update ON public.%I AS RESTRICTIVE FOR UPDATE TO authenticated '
      'USING (true) WITH CHECK (public.my_account_ready())', t);
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION private.assert_can_post(p_user_id uuid, p_kind text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
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

  -- Entry gates 2026-11-27: only a complete account posts (users row,
  -- 18+ date of birth, EULA >= 2, no open hold). After the ban gate, so a
  -- banned person still reads posting_banned.
  IF NOT private.account_ready(p_user_id) THEN
    RAISE EXCEPTION 'account_not_ready' USING ERRCODE = '42501';
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
$$;

-- assert_can_post keeps its ACL (the database's own): re-asserted.
REVOKE ALL ON FUNCTION private.assert_can_post(uuid, text) FROM PUBLIC, anon, authenticated;

COMMIT;
