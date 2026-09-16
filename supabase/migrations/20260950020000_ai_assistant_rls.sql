-- RLS for the AI Assistant tables. Spec §7.2: drafts/usage/consent events
-- have RLS enabled with NO direct authenticated table grants at all --
-- every legitimate access goes through a SECURITY DEFINER RPC (Tasks 3-7).
-- Planning links are readable by active, unarchived relationship members
-- and writable only by the Task-7 integration RPC.
ALTER TABLE public.ai_assist_drafts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_assistant_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_processing_consent_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_assist_planning_links ENABLE ROW LEVEL SECURITY;

-- Deliberately NO SELECT/INSERT/UPDATE/DELETE policy on
-- ai_assist_drafts, ai_assistant_usage, or ai_processing_consent_events.
-- With RLS enabled and no policy for a command, that command is refused
-- outright for every role except the table owner -- this is the
-- enforcement mechanism for "no direct authenticated table grants at
-- all" (spec §7.2).

CREATE POLICY ai_assist_planning_links_select ON public.ai_assist_planning_links
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = ai_assist_planning_links.relationship_id
        AND r.status = 'active' AND r.chat_archived_at IS NULL
        AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
    )
  );
-- No INSERT/UPDATE/DELETE policy here either -- writable only by
-- create_planning_from_assist_message (Task 7) and delete_message's
-- own cleanup (Task 6), both SECURITY DEFINER.
