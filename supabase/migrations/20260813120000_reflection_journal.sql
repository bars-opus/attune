-- Reflection Journal v1
-- Private, always-available, user-owned journal with AI-assisted (Gemini)
-- NVC-informed analysis. No relationship_id anywhere — this is explicitly
-- user-scoped only, unlike timeline_events/pulse_scores.

CREATE TABLE IF NOT EXISTS public.reflection_journal_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  content text NOT NULL CHECK (char_length(content) > 0),
  prompt_used text,
  tone text CHECK (tone IN ('reflective', 'charged', 'settled', 'searching', 'hopeful', 'heavy')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);

CREATE INDEX IF NOT EXISTS reflection_journal_entries_user_created_idx
  ON public.reflection_journal_entries(user_id, created_at DESC)
  WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS public.reflection_journal_analysis (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_id uuid NOT NULL REFERENCES public.reflection_journal_entries(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'completed', 'insufficient_evidence', 'failed')),
  tone text CHECK (tone IN ('reflective', 'charged', 'settled', 'searching', 'hopeful', 'heavy')),
  observation text,
  confidence text CHECK (confidence IN ('high', 'medium', 'low', 'none')),
  input_hash text NOT NULL,
  prompt_version text NOT NULL,
  model_provider text NOT NULL,
  model_name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (entry_id, input_hash)
);

CREATE INDEX IF NOT EXISTS reflection_journal_analysis_user_status_idx
  ON public.reflection_journal_analysis(user_id, status, created_at DESC);

DROP TRIGGER IF EXISTS set_reflection_journal_entries_updated_at ON public.reflection_journal_entries;
CREATE TRIGGER set_reflection_journal_entries_updated_at
BEFORE UPDATE ON public.reflection_journal_entries
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_reflection_journal_analysis_updated_at ON public.reflection_journal_analysis;
CREATE TRIGGER set_reflection_journal_analysis_updated_at
BEFORE UPDATE ON public.reflection_journal_analysis
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.reflection_journal_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reflection_journal_analysis ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.reflection_journal_entries FROM anon;
REVOKE ALL ON public.reflection_journal_analysis FROM anon;

GRANT SELECT ON public.reflection_journal_entries TO authenticated;
GRANT SELECT ON public.reflection_journal_analysis TO authenticated;

-- RLS is bypassed for service_role, but base table privileges are still
-- checked before RLS regardless of role (see
-- 20260812120000_grant_service_role_core_tables.sql for the earlier fix of
-- this exact bug class). The analyse-journal-entry edge function's
-- adminClient does direct .from(...) reads/writes on both tables.
GRANT SELECT, UPDATE ON public.reflection_journal_entries TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.reflection_journal_analysis TO service_role;

DROP POLICY IF EXISTS "journal entries owner read" ON public.reflection_journal_entries;
CREATE POLICY "journal entries owner read"
ON public.reflection_journal_entries FOR SELECT
USING (user_id = auth.uid());

DROP POLICY IF EXISTS "journal analysis owner read" ON public.reflection_journal_analysis;
CREATE POLICY "journal analysis owner read"
ON public.reflection_journal_analysis FOR SELECT
USING (user_id = auth.uid());

-- Writes go through SECURITY DEFINER RPCs only (mirrors healing_journeys),
-- so the client never inserts/updates these tables directly.

CREATE OR REPLACE FUNCTION public.create_journal_entry(
  p_content text,
  p_prompt_used text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_entry_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '28000';
  END IF;
  IF p_content IS NULL OR char_length(trim(p_content)) = 0 THEN
    RAISE EXCEPTION 'content_required' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.reflection_journal_entries (user_id, content, prompt_used)
  VALUES (v_user_id, p_content, p_prompt_used)
  RETURNING id INTO v_entry_id;

  RETURN v_entry_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_journal_entry(
  p_entry_id uuid,
  p_content text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '28000';
  END IF;
  IF p_content IS NULL OR char_length(trim(p_content)) = 0 THEN
    RAISE EXCEPTION 'content_required' USING ERRCODE = '22023';
  END IF;

  UPDATE public.reflection_journal_entries
  SET content = p_content,
      tone = NULL
  WHERE id = p_entry_id
    AND user_id = v_user_id
    AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'entry_not_found' USING ERRCODE = '22023';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_journal_entry(
  p_entry_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '28000';
  END IF;

  UPDATE public.reflection_journal_entries
  SET deleted_at = now()
  WHERE id = p_entry_id
    AND user_id = v_user_id
    AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'entry_not_found' USING ERRCODE = '22023';
  END IF;
END;
$$;

-- Service-role only: called from the analyse-journal-entry edge function
-- with the service key, never from the Flutter client.
CREATE OR REPLACE FUNCTION public.upsert_journal_analysis(
  p_entry_id uuid,
  p_user_id uuid,
  p_status text,
  p_tone text,
  p_observation text,
  p_confidence text,
  p_input_hash text,
  p_prompt_version text,
  p_model_provider text,
  p_model_name text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF p_status NOT IN ('pending', 'completed', 'insufficient_evidence', 'failed') THEN
    RAISE EXCEPTION 'invalid_status' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.reflection_journal_analysis (
    entry_id, user_id, status, tone, observation, confidence,
    input_hash, prompt_version, model_provider, model_name
  ) VALUES (
    p_entry_id, p_user_id, p_status, p_tone, p_observation, p_confidence,
    p_input_hash, p_prompt_version, p_model_provider, p_model_name
  )
  ON CONFLICT (entry_id, input_hash) DO UPDATE
  SET status = EXCLUDED.status,
      tone = EXCLUDED.tone,
      observation = EXCLUDED.observation,
      confidence = EXCLUDED.confidence
  RETURNING id INTO v_id;

  UPDATE public.reflection_journal_entries
  SET tone = COALESCE(p_tone, tone)
  WHERE id = p_entry_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_journal_entry(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_journal_entry(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_journal_entry(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.upsert_journal_analysis(uuid, uuid, text, text, text, text, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_journal_entry(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_journal_entry(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_journal_entry(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_journal_analysis(uuid, uuid, text, text, text, text, text, text, text, text) TO service_role;
