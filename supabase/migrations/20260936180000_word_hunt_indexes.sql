-- Word Hunt query plans.
--
-- EXPLAIN on the two hot paths, not assumed:
--
--   Seq Scan on game_sessions
--     Filter: status = ANY('{invited,active}') AND game_type = 'word_hunt'
--
-- Cheap today over a near-empty table and wrong at any real size. Both
-- the lobby's active-session lookup and the hourly expiry sweep run this
-- shape, and the sweep runs it for every couple at once.
--
-- Partial and composite, matching idx_paint_ball_sessions_relationship:
-- the leading relationship_id serves the lobby, and the WHERE clause
-- keeps the index to just this game's rows so it costs nothing to the
-- other seven game types sharing the table.
CREATE INDEX IF NOT EXISTS idx_word_hunt_sessions_relationship
  ON public.game_sessions(relationship_id, game_type, status)
  WHERE game_type = 'word_hunt';

-- The sweep scans by status without a relationship, so it needs its own.
-- created_at is included because both expiry predicates compare against
-- it, letting the index answer the whole WHERE clause.
CREATE INDEX IF NOT EXISTS idx_word_hunt_sessions_open
  ON public.game_sessions(status, created_at)
  WHERE game_type = 'word_hunt' AND status IN ('invited', 'active');

-- Attempts are read by session for every state call, and swept by
-- started_at. The primary key (session_id, user_id) already serves the
-- first; idx_word_hunt_attempts_open in the schema migration serves the
-- second. Nothing more is needed and an unused index is not free.
