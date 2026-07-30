-- Adds get_my_author_handle, so the client can navigate to its own
-- AnonymousProfileScreen (needed for a "My Profile" entry point in
-- OpinionsTab, now that Reposts/Bookmarks moved onto the profile screen as
-- tabs rather than living as standalone routes off the feed's AppBar).
--
-- opinion_author_handle(uuid) is deliberately NOT granted to authenticated
-- (see its own comment in 20260716140000_forums_opinions_anonymity_hardening.sql:
-- "clients never compute handles themselves... keeps the mapping
-- one-directional"). This function does not weaken that: it takes NO
-- parameter, so it can only ever compute the CALLER's own handle via
-- auth.uid() -- there is no way to pass another user's id through it. A
-- client still cannot resolve anyone else's handle; it can only learn its
-- own, the one piece of the mapping it is already entitled to (it already
-- knows its own posts carry this handle, from every feed row where
-- is_mine = true).

CREATE OR REPLACE FUNCTION public.get_my_author_handle()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT public.opinion_author_handle(auth.uid())
  WHERE auth.uid() IS NOT NULL;
$$;
REVOKE ALL ON FUNCTION public.get_my_author_handle() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_author_handle() TO authenticated;
