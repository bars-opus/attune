-- Together (spec 2026-10-14 §5.1): the couple's own events. Not readable
-- directly (plan ruling R1): writes go through SECURITY DEFINER RPCs and
-- reads through list_together_items, which masks busy_only titles and
-- drops private events for the partner.

CREATE TABLE public.couple_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind text NOT NULL DEFAULT 'event'
    CHECK (kind IN ('event', 'trip', 'big_day', 'ritual_occurrence')),
  title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 120),
  note text CHECK (note IS NULL OR char_length(note) <= 500),
  location_name text CHECK (location_name IS NULL OR char_length(location_name) <= 120),
  all_day boolean NOT NULL,
  start_date date,
  end_date date,
  starts_at timestamptz,
  ends_at timestamptz,
  tz text CHECK (tz IS NULL OR char_length(tz) BETWEEN 1 AND 64),
  rrule text CHECK (rrule IS NULL OR rrule ~
    '^FREQ=(DAILY|WEEKLY|MONTHLY|YEARLY)(;INTERVAL=[1-9][0-9]?)?(;BYDAY=(MO|TU|WE|TH|FR|SA|SU)(,(MO|TU|WE|TH|FR|SA|SU)){0,6})?$'),
  recurrence_until date,
  participant_ids uuid[] NOT NULL CHECK (cardinality(participant_ids) BETWEEN 1 AND 2),
  owner_id uuid,
  visibility text NOT NULL DEFAULT 'shared'
    CHECK (visibility IN ('shared', 'busy_only', 'private')),
  status text NOT NULL DEFAULT 'confirmed'
    CHECK (status IN ('proposed', 'confirmed', 'cancelled')),
  proposed_to uuid,
  proposal_expires_at timestamptz,
  decided_at timestamptz,
  ritual_id uuid,
  planning_entry_id uuid REFERENCES public.planning_entries(id) ON DELETE SET NULL,
  about_member_id uuid REFERENCES public.couple_family_members(id) ON DELETE SET NULL,
  remind_offsets_min int[] NOT NULL DEFAULT '{}' CHECK (
    cardinality(remind_offsets_min) <= 3
    AND 0 <= ALL (remind_offsets_min) AND 10080 >= ALL (remind_offsets_min)),
  legacy_reminder_id uuid UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  CONSTRAINT couple_events_when CHECK (
    (all_day AND start_date IS NOT NULL AND starts_at IS NULL AND ends_at IS NULL
       AND (end_date IS NULL OR end_date >= start_date))
    OR (NOT all_day AND starts_at IS NOT NULL AND tz IS NOT NULL
       AND start_date IS NULL AND end_date IS NULL
       AND (ends_at IS NULL OR ends_at >= starts_at))),
  CONSTRAINT couple_events_repeat_one_day CHECK (rrule IS NULL OR
    (all_day AND (end_date IS NULL OR end_date = start_date))
    OR (NOT all_day AND (ends_at IS NULL OR ends_at - starts_at < interval '24 hours'))),
  CONSTRAINT couple_events_byday_weekly CHECK (
    rrule IS NULL OR position('BYDAY' in rrule) = 0 OR rrule LIKE 'FREQ=WEEKLY%'),
  CONSTRAINT couple_events_until_needs_rule CHECK (recurrence_until IS NULL OR rrule IS NOT NULL),
  CONSTRAINT couple_events_proposal CHECK (
    status <> 'proposed' OR (proposed_to IS NOT NULL AND proposal_expires_at IS NOT NULL))
);

CREATE INDEX idx_couple_events_relationship
  ON public.couple_events (relationship_id) WHERE deleted_at IS NULL;

ALTER TABLE public.couple_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.couple_events FROM PUBLIC, anon, authenticated;

CREATE TRIGGER set_couple_events_updated_at
  BEFORE UPDATE ON public.couple_events
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trigger_together_signal_couple_events ON public.couple_events;
CREATE TRIGGER trigger_together_signal_couple_events
  AFTER INSERT OR UPDATE OR DELETE ON public.couple_events
  FOR EACH ROW EXECUTE FUNCTION public.bump_together_signal();
