-- Internal story helpers are not client-callable.
--
-- Four helpers were granted EXECUTE to `authenticated` as they were
-- written, on the reasoning that a client might one day want to compute
-- the same value. None has a caller anywhere in lib/ or in any other
-- migration, and none needs one: every function that uses them is
-- SECURITY DEFINER and runs as the owner regardless of what the caller
-- may execute.
--
-- The grant is therefore pure surface. `game_invite_error` -- the
-- precedent these were modelled on -- revokes from PUBLIC and anon and
-- grants nothing to authenticated, and that is the shape stories should
-- have had. Re-granting later is one line if a real caller appears.
--
-- story_relationship_is_open deliberately KEEPS its grant: three RLS
-- policies call it (story_items, story_change_signals, and the
-- story-media storage policies), and a policy is evaluated as the
-- querying role.
REVOKE EXECUTE ON FUNCTION public.story_archive_key(uuid)
  FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.story_archive_ttl_seconds()
  FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.story_intent_error(text)
  FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.story_intent_max_bytes(text, text)
  FROM authenticated;
