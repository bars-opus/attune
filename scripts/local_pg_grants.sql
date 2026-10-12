-- Applied AFTER all migrations, reproducing the privileges Supabase
-- applies platform-side.
--
-- service_role is deliberately NOT blanket-granted here any more.
--
-- It used to be, and that hid a real production fault for the project's
-- entire life: 103 public tables had no service_role grant at all,
-- because Supabase grants privileges when a table is created through its
-- API and a table created by a migration gets only whatever default
-- privileges happen to exist. Every Edge Function worker read empty
-- queues through PostgREST -- a missing SELECT returns NO ROWS rather
-- than an error -- while this harness showed every table reachable.
--
-- 20260931140000 now grants service_role explicitly and sets default
-- privileges for tables added later. Leaving service_role out of the
-- blanket below is what makes that migration load-bearing here: if it is
-- ever dropped or a table escapes it, the contract tests fail locally
-- instead of the queue silently draining nothing in production.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public
  TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public
  TO authenticated, anon;
-- Then re-apply the table REVOKEs migrations make deliberately.
--
-- Same hazard as the function note below, one level up: the blanket grant
-- above runs AFTER migrations, so it silently re-grants write access to
-- tables a migration explicitly revoked. In production Supabase applies
-- its grant at CREATE time and never again, so a later REVOKE stands —
-- here it was being undone, and games_contracts' "clients cannot write the
-- question catalogue" assertion failed against a schema that was correct.
--
-- Sourced from the migration itself rather than duplicated by hand, so
-- the two cannot drift.
\i supabase/migrations/20260930190000_game_table_grants.sql

-- Same replay for Word Hunt's three private tables, which have no RLS
-- policy at all: the table privilege is their only gate, so the blanket
-- grant above would open the puzzle and both players' attempts.
\i supabase/migrations/20260936150000_word_hunt_table_grants.sql

-- Same replay for Stories. story_items and story_change_signals have
-- RLS policies, but Postgres checks the table privilege first -- the
-- blanket grant above would still hand authenticated UPDATE/DELETE on
-- story_items (rewrite expires_at, occurred_on, media_key -- all
-- server-owned, per spec §3.3) despite the policy only ever having
-- covered SELECT. story_views and story_media_upload_intents have NO
-- policy at all by design, so for them the table privilege is the only
-- gate that exists, exactly like Word Hunt's tables above.
\i supabase/migrations/20260938100000_stories_table_grants.sql

-- And the messages column allowlist for story replies. messages is a
-- shared core table: the blanket grant above hands authenticated
-- table-level INSERT, which silently overrides the column allowlist
-- 20260939020000 sets. Replaying it keeps local behaviour identical to
-- production, where the REVOKE stands. Without this replay the harness
-- cannot catch a column dropped from the allowlist -- which is exactly
-- how the media_*/is_view_once/streak_views_remaining loss reached review.
\i supabase/migrations/20260939020000_story_reply_grants.sql

-- Same replay for Planning's change signal (the v1 Planning tables it
-- used to share a grants file with are dropped): without it the blanket
-- GRANT above would hand authenticated write access to a table that must
-- stay SELECT-only.
\i supabase/migrations/20261012200710_planning_change_signals_grants.sql

-- Same replay for the AI Assistant tables: the blanket GRANT above would
-- otherwise silently hand authenticated direct write access to
-- ai_assist_drafts/ai_assistant_usage/ai_processing_consent_events (which
-- must have NO authenticated grant at all) and direct write access to
-- ai_assist_planning_links (SELECT-only for authenticated) -- masking
-- exactly the kind of security bug this replay pattern exists to catch.
\i supabase/migrations/20260950030000_ai_assistant_table_grants.sql

-- Same replay for the AI Sessions tables: the blanket GRANT above would
-- otherwise silently hand authenticated direct access to ai_sessions,
-- ai_session_approvals, and ai_session_sources (which must have NO
-- authenticated grant at all) -- all access goes through SECURITY DEFINER
-- RPCs built in later tasks. Task 1's contract test enforces this.
\i supabase/migrations/20260953010100_ai_sessions_table_grants.sql

-- Same replay for the AI Session requests, turns, staging, and publications
-- tables: the blanket GRANT above would otherwise silently hand authenticated
-- direct access to all four tables (which must have NO authenticated grant at
-- all) -- all access goes through SECURITY DEFINER RPCs built in later tasks.
-- Task 2's contract test enforces this.
\i supabase/migrations/20260953020100_ai_session_requests_turns_staging_publications_table_grants.sql

-- Same replay for feature_flags, the rollout table. 20260705190000 shipped
-- `REVOKE ALL ... FROM anon, authenticated` + `GRANT SELECT TO authenticated`
-- when it created the table, but the blanket grant above was re-granting
-- INSERT/UPDATE/DELETE to authenticated locally -- measured as
-- `authenticated=arwd` in relacl -- so the harness could not catch a client
-- write privilege on the table that carries every capability kill switch.
-- Replaying it makes local behaviour match production, where the migration's
-- REVOKE stands. 20260953200100 re-asserts the pair for exactly this replay;
-- see its header for the measurement and why RLS alone was holding.
\i supabase/migrations/20260953200100_feature_flags_table_grants.sql

-- Deliberately NOT granting EXECUTE on all functions.
--
-- Supabase's default is EXECUTE for PUBLIC on new functions, and the
-- migrations then REVOKE it from the SECURITY DEFINER RPCs that must not be
-- callable by clients. A blanket GRANT here would re-grant exactly those and
-- silently defeat every function-privilege contract -- dating_mode_contracts
-- asserts, for instance, that `authenticated` cannot execute
-- block_dating_user(text,uuid), which a blanket grant would make false.
--
-- So function privileges are left exactly as the migrations leave them.

-- Planning v2 (P1): no client privileges on any v2 table; every read and
-- write is a SECURITY DEFINER RPC. Without this the blanket grant above
-- would hand authenticated full DML on them locally.
\i supabase/migrations/20261012200010_planning_v2_table_grants.sql

-- Planning v2 (P1): starter-template definitions are server-only.
\i supabase/migrations/20261012200210_planning_v2_starter_template_grants.sql
