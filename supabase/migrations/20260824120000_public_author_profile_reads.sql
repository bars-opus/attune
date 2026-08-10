-- AnonymousProfileScreen showed an "access denied" error state to guests —
-- not from a client-side gate (the screen has none), but because all three
-- RPCs behind it were authenticated-only: get_author_profile,
-- get_author_opinions, get_author_reposted_opinions.
--
-- Same posture as every prior anon-read grant this milestone: all three are
-- SECURITY DEFINER, none returns user_id (only the HMAC'd author_handle
-- already visible on any card), and every auth.uid() reference degrades
-- safely to NULL for a guest:
--   * get_author_profile: is_mine -> false, is_following -> false. A guest
--     is never "mine" and follows nobody, both correctly.
--   * get_author_opinions / get_author_reposted_opinions: is_mine/
--     my_reaction/is_saved/is_reposted_by_me all go false/null. Moderation
--     filters (removed_at, hidden_pending_review) are enforced inside the
--     function body, not the grant, so they still apply to a guest.
--
-- Reads only. follow_opinion_author / unfollow_opinion_author remain
-- authenticated-only, unaffected by this grant — a guest can now see the
-- Follow button (is_following resolves to false, so it renders "Follow"),
-- but tapping it is still gated client-side with the sign-in snackbar.

GRANT EXECUTE ON FUNCTION public.get_author_profile(text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_author_opinions(text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_author_reposted_opinions(text) TO anon;
