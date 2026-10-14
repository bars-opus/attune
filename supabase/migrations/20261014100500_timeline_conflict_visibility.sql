-- Together Phase 4: a conflict moment can be kept private (spec §6.3, §3.5;
-- plan R1, R7). Only conflicts can be private; the default is shared.
ALTER TABLE public.timeline_events
  ADD COLUMN visibility text NOT NULL DEFAULT 'shared'
    CHECK (visibility IN ('shared', 'private')),
  ADD CONSTRAINT timeline_events_private_conflicts_only
    CHECK (visibility = 'shared' OR event_type = 'conflict');

-- Both partners read shared, non-deleted moments; a private one only its logger.
DROP POLICY IF EXISTS timeline_relationship_members ON public.timeline_events;
CREATE POLICY timeline_relationship_members
ON public.timeline_events FOR SELECT TO authenticated
USING (
  deleted_at IS NULL
  AND (visibility = 'shared' OR logged_by = auth.uid())
  AND relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);
