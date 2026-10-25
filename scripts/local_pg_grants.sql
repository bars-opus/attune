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

-- Planning P3: the expense audit and the link-preview cache are server-only.
\i supabase/migrations/20261012200810_planning_rich_blocks_grants.sql

-- Planning P4: votes, member settings and the gallery are server-only.
\i supabase/migrations/20261012200910_planning_couple_blocks_grants.sql

-- Spec 1a (Task 1): relationships are read/insert only for clients; every
-- write is an RPC or the service role. Replayed so the blanket grant above
-- cannot hand UPDATE back locally.
\i supabase/migrations/20261017110000_relationships_write_lockdown_grants.sql

-- Spec 1a (Task 2): the seen-receipts votes are RPC-only.
\i supabase/migrations/20261017120100_seen_receipts_table_grants.sql

-- Spec 1a (Task 3): messages SELECT allowlist (no read_at, no analysis
-- columns), no UPDATE/DELETE; message_reads RPC-only. Must come after the
-- story-reply replay above, which only touches INSERT.
\i supabase/migrations/20261017130100_messages_column_grants.sql

-- Spec 1a (final review I2): the read watermark table is server-only.
\i supabase/migrations/20261017130300_read_marks_grants.sql

-- Spec 1a (Task 4): story_items SELECT allowlist (no has_been_viewed, no
-- seen_shown). After the stories replay above, which grants the whole table.
\i supabase/migrations/20261017140100_story_items_column_grants.sql

-- Stories Wave 5 (05 #8): story_places is SELECT-only for clients. Replayed
-- after the blanket grant above, which would otherwise hand authenticated
-- INSERT/UPDATE/DELETE and anon SELECT, and turn story_places_contracts red.
\i supabase/migrations/20261024100000_story_places_grants.sql

-- Spec 1a (Task 7): private Pulse scores are SELECT-only for their author;
-- the recompute limit table is server-only.
\i supabase/migrations/20261017150100_pulse_privacy_table_grants.sql

-- Spec 2 (Task 1): session_devices is RPC-only.
\i supabase/migrations/20261017200100_session_devices_grants.sql

-- Spec 3a (Task 1): lifecycle RPCs, seals and Healing snapshots.
\i supabase/migrations/20261018100100_relationship_lifecycle_grants.sql

-- Spec 3b (Task 1): deletion and purge are service-role only.
\i supabase/migrations/20261018110100_chapters_deletion_grants.sql

-- Security lockdown (Spec 3b review C3, I4): analysis_sessions, tag tables, 36Q/import functions.
\i supabase/migrations/20261017195000_security_lockdown.sql

-- Spec 3b final review M-2: chapter gate helpers.
\i supabase/migrations/20261018110300_chapter_reads_grants.sql

-- Spec 3c (Task 1): export jobs and functions.

-- Spec 3c (Task 1): export jobs and functions.
\i supabase/migrations/20261018120100_data_export_grants.sql

-- Spec 5 (Task 1): the pairing cache is closed to clients.
\i supabase/migrations/20261018130100_retire_attachment_pairing_grants.sql

-- Spec 5 (Task 2): what feels loving is saved through its RPC.
\i supabase/migrations/20261018130310_save_loving_now_grants.sql

-- Spec 5 (Task 3): the invite clock and withdraw.
\i supabase/migrations/20261018130610_invite_age_grants.sql

-- Spec 7 (Task 1): quiet states.
\i supabase/migrations/20261018140010_quiet_states_grants.sql

-- Spec 7 (Task 2): hidden periods.
\i supabase/migrations/20261018140110_quiet_effects_grants.sql

-- Spec 7 (Task 3): appreciation notes and the jar.
\i supabase/migrations/20261018140210_appreciation_grants.sql

-- Spec 7 (Task 4): Share a win.
\i supabase/migrations/20261018140310_share_a_win_grants.sql

-- Spec 7 (Task 5): put a plan away gently.
\i supabase/migrations/20261018140410_put_away_gently_grants.sql

-- Spec 8 (Task 1): the private safety check.
\i supabase/migrations/20261018150010_safety_self_check_grants.sql

-- Spec 8 (Task 4): Take a pause.
\i supabase/migrations/20261018150110_pause_messages_grants.sql

-- Spec 8 (Task 5): AI gates and the provider-call ledger.
\i supabase/migrations/20261018150310_ai_gates_grants.sql

-- Spec 8 (Task 3): the translator's daily limit.
\i supabase/migrations/20261018150210_translator_limit_grants.sql

-- Cross-spec sync audit fixes.
\i supabase/migrations/20261018160010_sync_fixes_grants.sql

-- Per-plan "new from your partner" seen marks.
\i supabase/migrations/20261018170010_planning_entry_seen_grants.sql

-- Chat review #7/#8: sync cursor column grant (messages.updated_at).
\i supabase/migrations/20261019100010_chat_sync_cursor_grants.sql

-- Chat review #9: per-message counter table, read-only to members.
\i supabase/migrations/20261019100110_chat_message_counters_grants.sql

-- Chat review #18: push subscriptions are written through RPCs only.
\i supabase/migrations/20261019110210_push_subscriptions_grants.sql

-- Chat review #18 (fix I2): "sign out other devices" stops their pushes.
\i supabase/migrations/20261019110225_deactivate_other_push_subscriptions_grants.sql

-- Chat review #19: system notices are server-only; the screenshot notice RPC.
\i supabase/migrations/20261019110310_system_notice_server_only_grants.sql

-- Plan 1b final review I1: an offline sign-out's owed push release (anon).
\i supabase/migrations/20261019110335_release_push_subscription_grants.sql

-- Chat review: push-once-per-job RPC grants.
\i supabase/migrations/20261019120115_chat_push_once_per_job_grants.sql

-- Chat W4 (#40/M-8): streak replay window read gate.
\i supabase/migrations/20261019140010_streak_replay_window_read_gate_grants.sql

-- Chat W4 Task 5b: view-once streak hardening (spend ledger is server-only).
\i supabase/migrations/20261019140110_streak_view_once_hardening_grants.sql

-- Spec 1 W1a: users column grants (no client INSERT; UPDATE of name, avatar
-- and time zone only) and migration 1's function grants.
\i supabase/migrations/20261025100010_identity_users_lockdown_grants.sql

-- Spec 1 W1b: metric tables and the report are closed to clients.
\i supabase/migrations/20261025100110_metric_counters_grants.sql

-- Spec 1 W1b: birth dates and holds are server-only; the sign-up RPCs.
\i supabase/migrations/20261025100210_account_birthdates_and_holds_grants.sql

-- Spec 1 W1b: the path writer and both seams are server-only; the home RPCs.
\i supabase/migrations/20261025100310_paths_and_home_state_grants.sql

-- Spec 1 W1c: the environment helpers and the flag gate are server-only;
-- get_public_app_config is the one anon read.
\i supabase/migrations/20261025100410_spec1_flags_and_public_config_grants.sql

-- Spec 1 W1c: identity health and the unfinished sign-up list, service role only.
\i supabase/migrations/20261025100510_identity_health_grants.sql
