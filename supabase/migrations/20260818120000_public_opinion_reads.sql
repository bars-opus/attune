-- Let signed-out visitors read the real Discover feed and open comment
-- threads, instead of being shown a hardcoded local preview.
--
-- Previously these RPCs were granted to `authenticated` only, so the app had
-- to fake a feed for guests (DiscoverFeedScreen._buildAnonymousPreviewSliver)
-- from three hardcoded strings. That preview is being removed, so the real
-- functions must be callable by `anon`.
--
-- Why this does not weaken the anonymity guarantees of
-- 20260716140000_forums_opinions_anonymity_hardening:
--
--   * All three functions are SECURITY DEFINER and return only
--     public.opinion_author_handle(user_id) — the HMAC'd, non-reversible
--     handle. user_id is never in the result set, for any caller. FORUM.md §3
--     ("user_id is NEVER exposed in any API response") still holds.
--   * Every auth.uid() reference inside them degrades safely to NULL for an
--     anon caller: is_mine/liked_by_me become false, my_reaction/is_saved/
--     is_reposted_by_me become null, and the mute/hide NOT EXISTS filters
--     simply match nothing. A guest sees an unpersonalised feed, not an
--     unfiltered one.
--   * Moderation filters are inside the function body, not the grant:
--     removed_at IS NULL and hidden_pending_review = false still apply, so
--     reported/removed content stays hidden from guests too.
--
-- Reads only. Every mutation (create/edit/react/save/repost/follow/report)
-- remains authenticated-only and is untouched here — a guest can read the
-- conversation but cannot join it.

-- Discover feed. Only the current 3-arg (tag-filtered) overload is granted;
-- the older 2-arg signature is superseded and deliberately left
-- authenticated-only.
GRANT EXECUTE ON FUNCTION public.get_discover_opinions(int, int, text[]) TO anon;

-- Comment threads, so a guest can open an opinion and read the replies.
GRANT EXECUTE ON FUNCTION public.get_opinion_comments(uuid) TO anon;

-- The feed renders tag filter chips above the list; without this the chip row
-- errors for guests even though the feed itself loads.
GRANT EXECUTE ON FUNCTION public.get_all_tags() TO anon;
