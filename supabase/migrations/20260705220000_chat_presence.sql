-- Chat presence: lets the new-message notification worker suppress a push when
-- the recipient is already actively viewing that conversation (Spec 9.2:
-- "Do not send if ... the recipient is already actively viewing that
-- conversation"). Presence is a coarse, self-reported, short-lived heartbeat —
-- it carries no message content and is never exposed to the other partner.

CREATE TABLE IF NOT EXISTS public.chat_presence (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  -- The relationship the user is actively viewing, or NULL when not in any
  -- conversation / backgrounded.
  active_relationship_id uuid REFERENCES public.relationships(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chat_presence_active
  ON public.chat_presence (active_relationship_id, updated_at DESC);

ALTER TABLE public.chat_presence ENABLE ROW LEVEL SECURITY;

-- A user may read only their own presence row; nobody reads a partner's
-- presence directly. Suppression decisions run in the trusted worker.
DROP POLICY IF EXISTS chat_presence_self_read ON public.chat_presence;
CREATE POLICY chat_presence_self_read
ON public.chat_presence FOR SELECT TO authenticated
USING (user_id = auth.uid());

REVOKE ALL ON public.chat_presence FROM anon, authenticated;
GRANT SELECT ON public.chat_presence TO authenticated;

-- Presence is written only through this RPC, which pins it to the caller and
-- verifies current, non-archived membership before recording a viewing state.
CREATE OR REPLACE FUNCTION public.set_chat_presence(p_relationship_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_active uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- NULL clears presence (backgrounded / left the conversation).
  IF p_relationship_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = p_relationship_id
        AND r.chat_archived_at IS NULL
        AND (r.user_a = v_user_id OR r.user_b = v_user_id)
    ) THEN
      -- Not a current member; record no active conversation rather than error
      -- (avoids leaking whether the relationship exists).
      v_active := NULL;
    ELSE
      v_active := p_relationship_id;
    END IF;
  ELSE
    v_active := NULL;
  END IF;

  INSERT INTO public.chat_presence (user_id, active_relationship_id, updated_at)
  VALUES (v_user_id, v_active, now())
  ON CONFLICT (user_id) DO UPDATE
    SET active_relationship_id = EXCLUDED.active_relationship_id,
        updated_at = now();
END;
$$;

REVOKE ALL ON FUNCTION public.set_chat_presence(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_chat_presence(uuid) TO authenticated;

-- Trusted-only helper the notification worker uses to decide suppression. Runs
-- as the service role; returns true when the recipient has a fresh heartbeat
-- (<= p_window_seconds) for this exact relationship.
CREATE OR REPLACE FUNCTION public.is_actively_viewing(
  p_user_id uuid,
  p_relationship_id uuid,
  p_window_seconds int DEFAULT 30
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.chat_presence cp
    WHERE cp.user_id = p_user_id
      AND cp.active_relationship_id = p_relationship_id
      AND cp.updated_at > now() - make_interval(secs => p_window_seconds)
  );
$$;

REVOKE ALL ON FUNCTION public.is_actively_viewing(uuid, uuid, int) FROM PUBLIC, anon, authenticated;
