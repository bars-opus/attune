-- Pulse, Timeline, and Weekly Check-in launch tables.
--
-- These four tables are defined canonically in PULSE.md §8 (and pulse_scores /
-- timeline_events in ATTUNE_MASTER_SPEC §4) but were never migrated. The Pulse
-- and Timeline feature code queries them directly (pulse_scores, weekly_checkins,
-- timeline_events), so without this migration those screens fail at runtime with
-- PGRST205 "table not found" — the same class of gap as the earlier public.profiles
-- 404. DDL, RLS, and indexes below are byte-faithful to PULSE.md §8.
--
-- Idempotent: CREATE TABLE IF NOT EXISTS + DROP POLICY IF EXISTS ... CREATE POLICY.

-- ---------------------------------------------------------------------------
-- Tables (PULSE.md §8)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.timeline_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  logged_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  event_type text NOT NULL CHECK (event_type IN (
    'milestone', 'conflict', 'highlight', 'first', 'anniversary'
  )),
  title text NOT NULL CHECK (char_length(title) <= 80),
  note text CHECK (note IS NULL OR char_length(note) <= 300),
  mood_score int CHECK (mood_score IS NULL OR mood_score BETWEEN 1 AND 10),
  occurred_at date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.pulse_scores (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  week_ending date NOT NULL,
  computed_at timestamptz NOT NULL DEFAULT now(),
  overall_score int NOT NULL CHECK (overall_score BETWEEN 0 AND 100),
  communication int NOT NULL CHECK (communication BETWEEN 0 AND 100),
  connection int NOT NULL CHECK (connection BETWEEN 0 AND 100),
  conflict_health int NOT NULL CHECK (conflict_health BETWEEN 0 AND 100),
  alignment int NOT NULL CHECK (alignment BETWEEN 0 AND 100),
  emotional_safety int NOT NULL CHECK (emotional_safety BETWEEN 0 AND 100),
  data_confidence text CHECK (data_confidence IN ('none', 'low', 'medium', 'high')) DEFAULT 'low',
  dimension_confidence jsonb,
  delta_vs_previous jsonb,
  UNIQUE (relationship_id, week_ending)
);

CREATE TABLE IF NOT EXISTS public.weekly_checkins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  week_ending date NOT NULL,
  communication_rating int CHECK (communication_rating IS NULL OR communication_rating BETWEEN 1 AND 10),
  connection_rating int CHECK (connection_rating IS NULL OR connection_rating BETWEEN 1 AND 10),
  conflict_health_rating int CHECK (conflict_health_rating IS NULL OR conflict_health_rating BETWEEN 1 AND 10),
  conflict_health_na boolean NOT NULL DEFAULT false,
  alignment_rating int CHECK (alignment_rating IS NULL OR alignment_rating BETWEEN 1 AND 10),
  safety_rating int CHECK (safety_rating IS NULL OR safety_rating BETWEEN 1 AND 10),
  submitted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, week_ending)
);

CREATE TABLE IF NOT EXISTS public.user_preferences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  pulse_visualisation text CHECK (pulse_visualisation IN ('ring', 'radar', 'number')) DEFAULT 'ring',
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- RLS (PULSE.md §8)
-- ---------------------------------------------------------------------------

ALTER TABLE public.timeline_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pulse_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.weekly_checkins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;

-- Timeline: both partners read (non-deleted); only the logger writes/edits/deletes.
DROP POLICY IF EXISTS timeline_relationship_members ON public.timeline_events;
CREATE POLICY timeline_relationship_members
ON public.timeline_events FOR SELECT TO authenticated
USING (
  deleted_at IS NULL
  AND relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);

DROP POLICY IF EXISTS timeline_insert_members ON public.timeline_events;
CREATE POLICY timeline_insert_members
ON public.timeline_events FOR INSERT TO authenticated
WITH CHECK (
  auth.uid() = logged_by
  AND relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);

DROP POLICY IF EXISTS timeline_update_owner ON public.timeline_events;
CREATE POLICY timeline_update_owner
ON public.timeline_events FOR UPDATE TO authenticated
USING (auth.uid() = logged_by)
WITH CHECK (auth.uid() = logged_by);

DROP POLICY IF EXISTS timeline_delete_owner ON public.timeline_events;
CREATE POLICY timeline_delete_owner
ON public.timeline_events FOR DELETE TO authenticated
USING (auth.uid() = logged_by);

-- Pulse scores: both partners read. Writes are server-side only (the pulse
-- computation job); no client INSERT/UPDATE policy is granted.
DROP POLICY IF EXISTS pulse_scores_relationship_members ON public.pulse_scores;
CREATE POLICY pulse_scores_relationship_members
ON public.pulse_scores FOR SELECT TO authenticated
USING (
  relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);

-- Weekly check-ins: fully private to the submitting user.
DROP POLICY IF EXISTS checkins_private ON public.weekly_checkins;
CREATE POLICY checkins_private
ON public.weekly_checkins FOR ALL TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- User preferences: private to owner.
DROP POLICY IF EXISTS preferences_private ON public.user_preferences;
CREATE POLICY preferences_private
ON public.user_preferences FOR ALL TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Grants. pulse_scores is read-only to clients (server computes it); the others
-- follow their RLS. forum-style least privilege.
-- ---------------------------------------------------------------------------

REVOKE ALL ON public.timeline_events FROM PUBLIC, anon;
REVOKE ALL ON public.pulse_scores FROM PUBLIC, anon;
REVOKE ALL ON public.weekly_checkins FROM PUBLIC, anon;
REVOKE ALL ON public.user_preferences FROM PUBLIC, anon;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.timeline_events TO authenticated;
GRANT SELECT ON public.pulse_scores TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.weekly_checkins TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_preferences TO authenticated;

-- ---------------------------------------------------------------------------
-- updated_at triggers (reuse the existing shared touch function if present;
-- otherwise define a local one).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.touch_pulse_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS touch_timeline_events_updated_at ON public.timeline_events;
CREATE TRIGGER touch_timeline_events_updated_at
BEFORE UPDATE ON public.timeline_events
FOR EACH ROW EXECUTE FUNCTION public.touch_pulse_updated_at();

DROP TRIGGER IF EXISTS touch_user_preferences_updated_at ON public.user_preferences;
CREATE TRIGGER touch_user_preferences_updated_at
BEFORE UPDATE ON public.user_preferences
FOR EACH ROW EXECUTE FUNCTION public.touch_pulse_updated_at();

-- ---------------------------------------------------------------------------
-- Indexes (PULSE.md §8)
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_timeline_relationship_date
  ON public.timeline_events (relationship_id, occurred_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_pulse_relationship_week
  ON public.pulse_scores (relationship_id, week_ending DESC);

CREATE INDEX IF NOT EXISTS idx_checkins_user_week
  ON public.weekly_checkins (user_id, week_ending DESC);
