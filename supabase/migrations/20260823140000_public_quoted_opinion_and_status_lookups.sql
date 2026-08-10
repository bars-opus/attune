-- get_quoted_opinion was still authenticated-only. This is the RPC behind
-- QuotedOpinionPreview (the original embedded inside a quote card) — unlike
-- the tag lookups, its failure path is user-visible and actively wrong: a
-- 403 for a guest renders "This opinion is no longer available", the exact
-- copy reserved for a moderated/deleted original (§8.11 "Removed original").
-- A guest reading a quote card was being told the original was gone when it
-- was not — the read was simply refused.
--
-- is_following_author: followStatusProvider (OpinionCard's Follow button,
-- rendered for guests per the "show everything, gate the tap" pass) reads
-- this. It degrades to valueOrNull ?? false on a 403, so nothing crashed —
-- the button just always rendered "not following", which is moot for a
-- guest today but was quietly wrong regardless.
--
-- is_opinion_reposted / is_opinion_saved: no Dart caller today (the feed
-- RPCs already return is_reposted_by_me / is_saved inline), same as the
-- singular tag lookups closed in 20260823130000 — granted now to close the
-- same landmine rather than fix a live bug.
--
-- All four: SECURITY DEFINER, auth.uid() degrades safely to NULL/false for a
-- guest, no user_id ever returned to the client.

GRANT EXECUTE ON FUNCTION public.get_quoted_opinion(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.is_following_author(text) TO anon;
GRANT EXECUTE ON FUNCTION public.is_opinion_reposted(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.is_opinion_saved(uuid) TO anon;
