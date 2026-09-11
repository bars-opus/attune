-- Stories private tables: revoked, and kept revoked.
--
-- Separated from the schema/RLS/storage migrations for one reason: this
-- file is replayed by scripts/local_pg_grants.sql AFTER the harness
-- applies its blanket "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL
-- TABLES IN SCHEMA public TO authenticated", exactly as
-- 20260930190000_game_table_grants.sql and
-- 20260936150000_word_hunt_table_grants.sql already are. Without that
-- replay the harness hands every client write access to story_items
-- (rewrite expires_at/occurred_on/media_key at will, per spec §3.3) and
-- full read/write to story_views (leaking the exact viewed_at timestamp
-- that says when a partner was last awake and looking at their phone,
-- per §3.4) and to story_media_upload_intents (mint or steal upload
-- slots into someone else's relationship), regardless of what the RLS
-- policies say -- Postgres checks the table privilege FIRST and the
-- policy second.
--
-- Which is not a hypothetical here either: story_security_contracts.sql
-- failed on a from-scratch rebuild with
--
--   EXPLOIT: authenticated can UPDATE story_items
--
-- because 20260938020000_stories_rls.sql's REVOKE ran during migration
-- application, and scripts/local_pg_grants.sql's blanket GRANT then ran
-- straight over it afterward. Production does not have this hazard --
-- Supabase grants at CREATE time and a later REVOKE stands -- but a
-- future migration applying a blanket grant would, and this file (plus
-- its \i line in local_pg_grants.sql) is what stands in its way, the
-- same way it already does for games and Word Hunt.
--
-- story_items and story_change_signals keep exactly the client SELECT
-- their RLS policies (in 20260938020000) expect to gate; story_views,
-- story_media_upload_intents and story_media_processing_outbox
-- (Task 9 fix round 1, 20260938090000) get NO grant at all -- all three
-- have zero policies, by design, so the table privilege is their ONLY
-- gate, same as Word Hunt's three tables.
--
-- story_media_processing_outbox specifically: spec §4.4 says "The
-- table and its claim/finish/recovery RPCs are service-role only."
-- Without this REVOKE the harness's blanket grant would hand
-- authenticated direct read/write on attempts/state/last_error_code --
-- a client could dead-letter its own story's archival job, or forge
-- a 'done' state and defeat the swap entirely -- regardless of the
-- fact that no policy exists, for exactly the reason story_items
-- itself failed this same way on a from-scratch rebuild (see above).
REVOKE ALL ON public.story_items                    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.story_views                     FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.story_change_signals            FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.story_media_upload_intents      FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.story_media_processing_outbox   FROM PUBLIC, anon, authenticated;

GRANT SELECT ON public.story_items          TO authenticated;
GRANT SELECT ON public.story_change_signals TO authenticated;
-- story_views, story_media_upload_intents, story_media_processing_outbox:
-- no grant. Every writer/reader of any of them is a SECURITY DEFINER
-- function running as owner (create_story_upload_intent,
-- create_story_item, the maintenance RPCs in 20260938090000) or the
-- storage policies' own EXISTS subquery, never a direct client query.
