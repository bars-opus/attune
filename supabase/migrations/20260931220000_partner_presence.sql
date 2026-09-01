-- "Active in this chat", shown to the partner.
--
-- chat_presence has existed since July but was deliberately one-way: its
-- header says presence "is never exposed to the other partner", and the
-- RLS policy lets a user read only their own row. That was the right
-- default, and this does not relax it -- the policy is untouched.
--
-- What changes is a single narrow question, answered by a SECURITY
-- DEFINER function: is the OTHER member of a relationship I belong to
-- looking at this conversation right now? It returns a boolean and
-- nothing else. No timestamp, no last-seen, no "online elsewhere".
--
-- The product reasoning matters as much as the mechanism. A general
-- online indicator in a couples app answers "are they on their phone and
-- not replying to me" -- a question that starts arguments and that the
-- app should not help anyone ask. Scoped to this conversation it answers
-- something kinder and true: they are here with you now. It is also the
-- only thing chat_presence actually measures.

CREATE OR REPLACE FUNCTION public.partner_is_active_in_chat(
  p_relationship_id uuid,
  p_window_seconds int DEFAULT 45
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_partner uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN false;
  END IF;

  -- Membership is verified before anything is read: without this, any
  -- authenticated user could probe any relationship id and learn whether
  -- someone is at their phone. Returns false rather than raising, so a
  -- caller cannot distinguish "not a member" from "not active" and use
  -- the difference to test whether a relationship exists.
  SELECT CASE
           WHEN r.user_a = v_user_id THEN r.user_b
           WHEN r.user_b = v_user_id THEN r.user_a
         END
  INTO v_partner
  FROM public.relationships r
  WHERE r.id = p_relationship_id
    AND r.chat_archived_at IS NULL
    AND (r.user_a = v_user_id OR r.user_b = v_user_id);

  IF v_partner IS NULL THEN
    RETURN false;
  END IF;

  -- Bounded so a caller cannot pass a huge window and turn a live
  -- indicator into "was here at some point today", which is last-seen by
  -- another name.
  p_window_seconds := least(greatest(coalesce(p_window_seconds, 45), 15), 120);

  RETURN EXISTS (
    SELECT 1 FROM public.chat_presence cp
    WHERE cp.user_id = v_partner
      AND cp.active_relationship_id = p_relationship_id
      AND cp.updated_at > now() - make_interval(secs => p_window_seconds)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.partner_is_active_in_chat(uuid, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.partner_is_active_in_chat(uuid, int)
  TO authenticated;

COMMENT ON FUNCTION public.partner_is_active_in_chat(uuid, int) IS
  'True when the caller''s partner is viewing this conversation within the '
  'freshness window. Returns a boolean only -- never a timestamp -- and '
  'false for a relationship the caller does not belong to.';
