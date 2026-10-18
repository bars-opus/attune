-- Security lockdown (Spec 3b plan review C3, I4; 2026-10-18). Idempotent.
-- To close the exposure before the next release, paste this file into the
-- SQL editor and run it; do NOT record it with `migration repair`. The
-- next `supabase db push` runs it again, harmlessly, in order. Numbered
-- right after the last deployed migration (20261017190100).
--
-- analysis_sessions had RLS off and anon SELECT: anyone with the public anon
-- key could read every couple's conflict-session analysis (pursuer,
-- escalation score, suggested insight). Nothing in the app reads it; the
-- analysis pipeline uses the service role.
ALTER TABLE public.analysis_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.analysis_sessions FROM anon, authenticated;

-- Tag tables: public reads stay; writes go through the SECURITY DEFINER
-- attach_*_tags RPCs only.
REVOKE INSERT, UPDATE, DELETE ON public.forum_topic_tags, public.opinion_tags, public.tags
  FROM anon, authenticated;

-- PostgreSQL's default PUBLIC execute on SECURITY DEFINER functions.
REVOKE ALL ON FUNCTION public.get_thirty_six_seen_map(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mark_thirty_six_questions_seen(uuid, uuid[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mark_thirty_six_round_complete(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.complete_thirty_six_chapter(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.replace_thirty_six_question(uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_thirty_six_seen_map(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_thirty_six_questions_seen(uuid, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_thirty_six_round_complete(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_thirty_six_chapter(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.replace_thirty_six_question(uuid, uuid, text) TO authenticated;
-- Deletes personal insights and patterns by import job with no caller check:
-- internal to the import cancel/rollback paths only.
REVOKE ALL ON FUNCTION public.remove_import_derived_evidence(uuid) FROM PUBLIC, anon, authenticated;
