-- Only the games a bare session row can actually start.
--
-- The first allowlist named all ten, which was wrong. game_invite_create
-- inserts a session and nothing else, and four games need more than that
-- before they are playable:
--
--   36_questions  needs journey_id and chapter; without them its own
--                 queries (which filter by journey_id) never see the row,
--                 so the invite is a card that opens a screen starting a
--                 fresh journey and ignoring it.
--   this_or_that  builds rounds and questions in create_this_or_that_session.
--   truth_or_dare needs total_rounds, current_round and a tone; a bare row
--                 reads as "Round 1 of 0".
--   love_map      has no session at all -- §8.4 says it cannot be completed
--                 in one sitting, so there is deliberately no row to invite.
--
-- Removing them here rather than papering over it in the client: an RPC
-- that creates a session no game can open is worse than a refusal, because
-- the refusal is visible and the dead card is not.
--
-- The three games with their own hardened create (Snakes, Word Hunt, Paint
-- Ball) stay listed: they route through their own functions today, and the
-- entry is what lets the generic accept/decline serve their cards.
CREATE OR REPLACE FUNCTION public.game_invite_type_allowed(p_game_type text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_game_type IN (
    'mirror',
    'sliding_scale',
    'scenario',
    'paint_ball',
    'snakes_and_ladders',
    'word_hunt'
  );
$$;

REVOKE ALL ON FUNCTION public.game_invite_type_allowed(text) FROM PUBLIC, anon;
