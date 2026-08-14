-- Message reactions: either partner may react to any message (including
-- their own) with one emoji at a time. Reacting again overwrites via
-- react_to_message's upsert — one row per (message, user), never two.
--
-- relationship_id is denormalized onto this table (not derivable-only via
-- a join through messages) for the same reason message_pins carries it
-- (20260831120000_message_actions.sql:142-143): it lets the realtime
-- channel filter Postgres changes on relationship_id directly, matching
-- the existing message_pins subscription in
-- SupabaseChatRepository._channelFor (supabase_chat_repository.dart:492).

CREATE TABLE IF NOT EXISTS public.message_reactions (
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  emoji text NOT NULL,
  reacted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_message_reactions_relationship
  ON public.message_reactions (relationship_id);

-- The PRIMARY KEY (message_id, user_id) already serves lookups by
-- message_id alone (it's the leading column), so no extra index is
-- needed there — matching message_stars' single index, not message_pins'
-- two (message_pins' PK leads with relationship_id, message_reactions'
-- leads with message_id).

ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS message_reactions_select ON public.message_reactions;
-- Visible to BOTH relationship members (unlike message_stars, which is
-- owner-only) — you need to see your partner's reaction, not just your
-- own. Archived-chat guard matches message_pins_select exactly.
CREATE POLICY message_reactions_select ON public.message_reactions
  FOR SELECT TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = message_reactions.relationship_id
        AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
        AND r.chat_archived_at IS NULL
    )
  );

DROP POLICY IF EXISTS message_reactions_delete ON public.message_reactions;
-- Only your OWN reaction may be removed (unlike message_pins, where
-- either partner may unpin) — matches message_stars_owner's "yours only"
-- shape for DELETE.
CREATE POLICY message_reactions_delete ON public.message_reactions
  FOR DELETE TO authenticated USING (user_id = auth.uid());

-- SELECT/DELETE only, no direct INSERT/UPDATE grant — reacting always
-- goes through react_to_message so the relationship-active and
-- message-not-deleted business rules are enforced server-side (same
-- rationale as message_pins' INSERT-only-via-RPC comment,
-- 20260831120000_message_actions.sql:187-188). Direct DELETE is safe to
-- grant broadly since the RLS policy above already restricts it to your
-- own row.
REVOKE ALL ON public.message_reactions FROM PUBLIC, anon, authenticated;
GRANT SELECT, DELETE ON public.message_reactions TO authenticated;

CREATE OR REPLACE FUNCTION public.react_to_message(
  p_relationship_id uuid,
  p_message_id uuid,
  p_emoji text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  IF p_emoji IS NULL OR char_length(p_emoji) = 0 OR char_length(p_emoji) > 16 THEN
    RAISE EXCEPTION 'invalid_emoji' USING ERRCODE = '22023';
  END IF;

  -- Same "active, not archived" condition pin_message enforces
  -- (20260831120000_message_actions.sql:363-376): reacting is a write
  -- into a live conversation.
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = p_relationship_id
      AND (r.user_a = v_uid OR r.user_b = v_uid)
      AND r.status = 'active'
      AND r.chat_archived_at IS NULL
  ) THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = '42501';
  END IF;

  -- Message must exist, belong to this relationship, and not be
  -- tombstoned — matches pin_message's message check exactly
  -- (20260831120000_message_actions.sql:381-388).
  IF NOT EXISTS (
    SELECT 1 FROM public.messages m
    WHERE m.id = p_message_id
      AND m.relationship_id = p_relationship_id
      AND m.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'not_reactable' USING ERRCODE = '42501';
  END IF;

  -- Upsert: one row per (message_id, user_id) — reacting again overwrites
  -- the emoji rather than erroring or adding a second row.
  INSERT INTO public.message_reactions (message_id, relationship_id, user_id, emoji)
  VALUES (p_message_id, p_relationship_id, v_uid, p_emoji)
  ON CONFLICT (message_id, user_id)
  DO UPDATE SET emoji = EXCLUDED.emoji, reacted_at = now();
END;
$$;

REVOKE ALL ON FUNCTION public.react_to_message(uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.react_to_message(uuid, uuid, text) TO authenticated;

-- remove_reaction is a thin RPC (not a direct DELETE from the client)
-- purely for symmetry/simplicity with react_to_message's call shape in
-- the repository — the RLS DELETE policy above already makes a direct
-- delete equally safe, but going through one RPC per mutation keeps the
-- repository's two methods structurally identical to
-- starMessage/unstarMessage's own pair.
CREATE OR REPLACE FUNCTION public.remove_reaction(p_message_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.message_reactions
  WHERE message_id = p_message_id AND user_id = v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.remove_reaction(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_reaction(uuid) TO authenticated;
