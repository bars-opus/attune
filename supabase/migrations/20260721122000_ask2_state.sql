-- supabase/migrations/20260721122000_ask2_state.sql
-- Tracks each couple's progress through the Ask-2 lifecycle (decision 29).
-- One row per relationship, created lazily by the eligibility sweep.
CREATE TABLE IF NOT EXISTS public.ask2_state (
  relationship_id uuid PRIMARY KEY REFERENCES public.relationships(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'eligible', 'prompted', 'reminded', 'completed', 'skipped')),
  eligible_at timestamptz,
  first_positive_message_id uuid REFERENCES public.messages(id),
  prompted_at timestamptz,
  reminded_at timestamptz,
  completed_at timestamptz,
  skipped_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.ask2_state ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.ask2_state FROM PUBLIC, anon;

-- Both relationship members can read their own Ask-2 state (Ask2Flow, Task 5,
-- needs this to know whether to show intro/resume/already-completed UI).
-- Writes go through the service role only (the sweep, and Ask2Flow's
-- completion/skip RPC in Task 5) — no direct client INSERT/UPDATE grant.
CREATE POLICY ask2_state_relationship_read
ON public.ask2_state FOR SELECT TO authenticated
USING (
  relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);

GRANT SELECT ON public.ask2_state TO authenticated;

-- Client-facing completion RPC. Ask2Flow (Task 5) calls this instead of
-- UPDATE-ing ask2_state directly — there is no client UPDATE grant on the
-- table above, matching the same read-only-to-clients /
-- SECURITY-DEFINER-RPC-writes pattern already used by
-- attachment_compatibility_cache (see 20260717130000_attachment_compatibility_cache.sql).
-- Verifies the caller is a member of the relationship before writing, and
-- only transitions FROM 'prompted'/'reminded' (the only states a real
-- completion can follow) so a stray call can't fabricate history.
CREATE OR REPLACE FUNCTION public.complete_ask2(
  p_relationship_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.relationships
    WHERE id = p_relationship_id
      AND (user_a = auth.uid() OR user_b = auth.uid())
  ) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  UPDATE public.ask2_state
  SET status = 'completed',
      completed_at = now(),
      updated_at = now()
  WHERE relationship_id = p_relationship_id
    AND status IN ('prompted', 'reminded');
END;
$$;

REVOKE ALL ON FUNCTION public.complete_ask2(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_ask2(uuid) TO authenticated;
