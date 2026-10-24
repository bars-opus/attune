-- supabase/migrations/20261024100000_story_places_grants.sql
--
-- Stories Wave 5 (review 05 #8, 06 #26): story_places' table privileges in
-- their own file, so scripts/local_pg_grants.sql can replay them after its
-- blanket grant, as it already does for 20260938100000_stories_table_grants
-- and 20260939020000_story_reply_grants. The statements are the ones
-- 20261017100000_story_places.sql:19-20 made; production is unchanged.
-- Idempotent.
REVOKE ALL ON public.story_places FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.story_places TO authenticated;
