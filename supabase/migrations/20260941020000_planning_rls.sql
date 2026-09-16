-- RLS for Planning. Spec §4.1: clients get SELECT only, and there is
-- deliberately NO read-after-archive exception (unlike Stories) --
-- Planning becomes neither readable nor writable once the relationship
-- is no longer active and unarchived.
ALTER TABLE public.planning_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.planning_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.planning_event_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.planning_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.planning_change_signals ENABLE ROW LEVEL SECURITY;

CREATE POLICY planning_items_select ON public.planning_items
  FOR SELECT
  USING (
    deleted_at IS NULL
    AND EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = planning_items.relationship_id
        AND r.status = 'active' AND r.chat_archived_at IS NULL
        AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
    )
  );

CREATE POLICY planning_events_select ON public.planning_events
  FOR SELECT
  USING (
    deleted_at IS NULL
    AND EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = planning_events.relationship_id
        AND r.status = 'active' AND r.chat_archived_at IS NULL
        AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
    )
  );

-- The link table has no deleted_at of its own -- a link is either
-- present or it isn't. Membership alone gates its visibility; the read
-- RPCs (Task 4) additionally join against the live content tables.
CREATE POLICY planning_event_tasks_select ON public.planning_event_tasks
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = planning_event_tasks.relationship_id
        AND r.status = 'active' AND r.chat_archived_at IS NULL
        AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
    )
  );

CREATE POLICY planning_notes_select ON public.planning_notes
  FOR SELECT
  USING (
    deleted_at IS NULL
    AND EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = planning_notes.relationship_id
        AND r.status = 'active' AND r.chat_archived_at IS NULL
        AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
    )
  );

-- No deleted_at clause here -- the signal table has no soft deletion.
CREATE POLICY planning_change_signals_select ON public.planning_change_signals
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = planning_change_signals.relationship_id
        AND r.status = 'active' AND r.chat_archived_at IS NULL
        AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
    )
  );

-- Deliberately NO INSERT/UPDATE/DELETE policy on any of the five
-- tables. With RLS enabled and no policy for a command, that command is
-- refused outright for every role except the table owner -- this is
-- the enforcement mechanism for "clients get SELECT only" (spec §4.1),
-- matching story_items' own "no INSERT/UPDATE/DELETE policy at all"
-- shape exactly.
