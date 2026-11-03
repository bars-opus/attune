-- Spec 1 W5, migration 10 part 1 of 2 (spec §4.7 #10; plan P-1):
-- couple_profiles.
--   * public.couple_profiles: the shared About us profile of one
--     relationship (spec §4.2), attributed per field (six pairs), read by
--     both members while relationship_chat_open (active, paused, or ended
--     inside the window; not sealed; not archived). Never a type, a score
--     or a label (permanent constraint; couple_profile_contracts.sql
--     section A pins the columns and every function that reads it).
--   * public.couple_profile_drafts: one inviter's answers before linking,
--     per account (the shared-phone rule: nobody's draft reaches another
--     account), with a set_at per field for the adoption order.
--   * get_couple_profile / update_couple_profile (members), and
--     get_my_couple_profile_draft / update_my_couple_profile_draft (own
--     draft, Relationship path only), all validated by one merge,
--     private.couple_profile_merge.
--   * adopt_couple_profile_drafts (no grants): moves the drafts into the
--     shared profile at linking, the inviter's first, the acceptor's
--     filling what is empty. Its caller, accept_relationship_invite_v2, is
--     re-created in part 2 (20261102110100).
--   * sync_anniversary_reminder (no grants): AU6's single source for
--     Together's anniversary reminder, one reminders row per profile.
--   * private.guard_about_us_reminder: a client can't move or delete that
--     row behind About us's back (plan P-6).
--   * couple_profiles_together_signal: every change bumps both phones
--     through the existing together_change_signals (not in the Realtime
--     publication itself).
-- Grants in 20261102110010_couple_profiles_grants.sql; every server-only
-- object is revoked here as well.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS public.couple_profiles (
  relationship_id uuid PRIMARY KEY REFERENCES public.relationships(id) ON DELETE CASCADE,
  together_since date NULL,
  together_since_precision text NULL
    CHECK (together_since_precision IN ('day', 'month', 'year')),
  stage text NULL CHECK (stage IN ('dating', 'engaged', 'married', 'other')),
  stage_words text NULL CHECK (char_length(stage_words) <= 40),
  ceremonies jsonb NOT NULL DEFAULT '[]'::jsonb,
  living text NULL CHECK (living IN ('together', 'apart_nearby', 'long_distance')),
  children text NULL CHECK (children IN ('none', 'yes', 'expecting', 'prefer_not_to_say')),
  child_age_bands text[] NOT NULL DEFAULT '{}'::text[]
    CHECK (child_age_bands <@ ARRAY['under2', '2to5', '6to12', '13to17', '18plus']::text[]),
  anniversary_source text NOT NULL DEFAULT 'off'
    CHECK (anniversary_source IN ('off', 'together_since', 'ceremony_1', 'ceremony_2')),
  anniversary_reminder_id uuid NULL REFERENCES public.reminders(id) ON DELETE SET NULL,
  together_since_changed_by uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  together_since_changed_at timestamptz NULL,
  stage_changed_by uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  stage_changed_at timestamptz NULL,
  ceremonies_changed_by uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  ceremonies_changed_at timestamptz NULL,
  living_changed_by uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  living_changed_at timestamptz NULL,
  children_changed_by uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  children_changed_at timestamptz NULL,
  anniversary_changed_by uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  anniversary_changed_at timestamptz NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT couple_profiles_since_precision
    CHECK ((together_since IS NULL) = (together_since_precision IS NULL)),
  CONSTRAINT couple_profiles_stage_words CHECK (stage_words IS NULL OR stage = 'other'),
  CONSTRAINT couple_profiles_ceremonies_shape CHECK (
    CASE WHEN jsonb_typeof(ceremonies) = 'array'
         THEN jsonb_array_length(ceremonies) <= 2
              AND (jsonb_array_length(ceremonies) = 0 OR stage = 'married')
         ELSE false END),
  CONSTRAINT couple_profiles_bands_need_yes
    CHECK (cardinality(child_age_bands) = 0 OR children = 'yes')
);
CREATE INDEX IF NOT EXISTS couple_profiles_anniversary_reminder_idx
  ON public.couple_profiles (anniversary_reminder_id)
  WHERE anniversary_reminder_id IS NOT NULL;
ALTER TABLE public.couple_profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS couple_profiles_select_members ON public.couple_profiles;
CREATE POLICY couple_profiles_select_members ON public.couple_profiles
  FOR SELECT TO authenticated
  USING (public.relationship_chat_open(relationship_id));
REVOKE ALL ON public.couple_profiles FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS public.couple_profile_drafts (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  together_since date NULL,
  together_since_precision text NULL
    CHECK (together_since_precision IN ('day', 'month', 'year')),
  stage text NULL CHECK (stage IN ('dating', 'engaged', 'married', 'other')),
  stage_words text NULL CHECK (char_length(stage_words) <= 40),
  ceremonies jsonb NOT NULL DEFAULT '[]'::jsonb,
  living text NULL CHECK (living IN ('together', 'apart_nearby', 'long_distance')),
  children text NULL CHECK (children IN ('none', 'yes', 'expecting', 'prefer_not_to_say')),
  child_age_bands text[] NOT NULL DEFAULT '{}'::text[]
    CHECK (child_age_bands <@ ARRAY['under2', '2to5', '6to12', '13to17', '18plus']::text[]),
  anniversary_source text NOT NULL DEFAULT 'off'
    CHECK (anniversary_source IN ('off', 'together_since', 'ceremony_1', 'ceremony_2')),
  together_since_set_at timestamptz NULL,
  stage_set_at timestamptz NULL,
  ceremonies_set_at timestamptz NULL,
  living_set_at timestamptz NULL,
  children_set_at timestamptz NULL,
  anniversary_set_at timestamptz NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT couple_profile_drafts_since_precision
    CHECK ((together_since IS NULL) = (together_since_precision IS NULL)),
  CONSTRAINT couple_profile_drafts_stage_words CHECK (stage_words IS NULL OR stage = 'other'),
  CONSTRAINT couple_profile_drafts_ceremonies_shape CHECK (
    CASE WHEN jsonb_typeof(ceremonies) = 'array'
         THEN jsonb_array_length(ceremonies) <= 2
              AND (jsonb_array_length(ceremonies) = 0 OR stage = 'married')
         ELSE false END),
  CONSTRAINT couple_profile_drafts_bands_need_yes
    CHECK (cardinality(child_age_bands) = 0 OR children = 'yes')
);
ALTER TABLE public.couple_profile_drafts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS couple_profile_drafts_select_own ON public.couple_profile_drafts;
CREATE POLICY couple_profile_drafts_select_own ON public.couple_profile_drafts
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());
REVOKE ALL ON public.couple_profile_drafts FROM PUBLIC, anon, authenticated;

-- A ceremony's full date, or NULL without a month and a day.
CREATE OR REPLACE FUNCTION private.couple_profile_ceremony_date(p_ceremony jsonb)
RETURNS date
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE
           WHEN p_ceremony IS NULL OR jsonb_typeof(p_ceremony) <> 'object'
                OR p_ceremony->'month' IS NULL OR p_ceremony->'day' IS NULL THEN NULL
           ELSE make_date((p_ceremony->>'year')::int, (p_ceremony->>'month')::int,
                          (p_ceremony->>'day')::int)
         END;
$$;
REVOKE ALL ON FUNCTION private.couple_profile_ceremony_date(jsonb) FROM PUBLIC, anon, authenticated, service_role;

-- One attribution for get_couple_profile: who (me, or a first name, never
-- an id) and when; NULL for a field nobody has answered.
CREATE OR REPLACE FUNCTION private.couple_profile_change(p_me uuid, p_by uuid, p_at timestamptz)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT CASE WHEN p_at IS NULL THEN NULL ELSE jsonb_build_object(
           'changed_by_me', p_by IS NOT DISTINCT FROM p_me,
           'changed_by_first_name',
             CASE WHEN p_by IS DISTINCT FROM p_me AND p_by IS NOT NULL
                  THEN private.invite_first_name(p_by) END,
           'changed_at', p_at) END;
$$;
REVOKE ALL ON FUNCTION private.couple_profile_change(uuid, uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;

-- The one validation (spec §3.8 AU1-AU6, §4.3 W5) for the shared profile
-- and the draft alike: [p_state] (every answer key) with [p_patch] applied,
-- normalised, or a refusal. Keys: together_since + together_since_precision
-- (together), stage (+ stage_words), ceremonies, living, children
-- (+ child_age_bands), anniversary_source. Dates: none before 1900, none
-- in the future (a day of slack for the earliest time zone); a month is
-- kept as its 1st, a year as 1 January. Leaving Married clears the
-- ceremonies; a ceremony that goes takes an anniversary on it with it.
CREATE OR REPLACE FUNCTION private.couple_profile_merge(p_state jsonb, p_patch jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_last_day constant date := (now() AT TIME ZONE 'utc')::date + 1;
  v_bands_all constant text[] := ARRAY['under2', '2to5', '6to12', '13to17', '18plus'];
  v_out jsonb := p_state;
  v_key text;
  v_text text;
  v_date date;
  v_precision text;
  v_stage text;
  v_words text;
  v_list jsonb;
  v_item jsonb;
  v_clean jsonb := '[]'::jsonb;
  v_year int;
  v_month int;
  v_day int;
  v_label text;
  v_children text;
  v_bands text[];
  v_source text;
BEGIN
  IF p_patch IS NULL OR jsonb_typeof(p_patch) <> 'object' THEN
    RAISE EXCEPTION 'couple_profile:invalid';
  END IF;
  FOR v_key IN SELECT jsonb_object_keys(p_patch) LOOP
    IF v_key NOT IN ('together_since', 'together_since_precision', 'stage', 'stage_words',
                     'ceremonies', 'living', 'children', 'child_age_bands', 'anniversary_source') THEN
      RAISE EXCEPTION 'couple_profile:unknown_key';
    END IF;
  END LOOP;

  -- AU2: the date and its precision travel together.
  IF p_patch ? 'together_since' OR p_patch ? 'together_since_precision' THEN
    IF coalesce(jsonb_typeof(p_patch->'together_since'), 'null') = 'null' THEN
      IF coalesce(jsonb_typeof(p_patch->'together_since_precision'), 'null') <> 'null' THEN
        RAISE EXCEPTION 'couple_profile:invalid';
      END IF;
      v_out := v_out || '{"together_since": null, "together_since_precision": null}'::jsonb;
    ELSE
      v_text := p_patch->>'together_since';
      v_precision := p_patch->>'together_since_precision';
      IF jsonb_typeof(p_patch->'together_since') <> 'string'
         OR v_text !~ '^\d{4}-\d{2}-\d{2}$'
         OR v_precision IS NULL OR v_precision NOT IN ('day', 'month', 'year') THEN
        RAISE EXCEPTION 'couple_profile:invalid';
      END IF;
      BEGIN
        v_date := v_text::date;
      EXCEPTION WHEN datetime_field_overflow OR invalid_datetime_format THEN
        RAISE EXCEPTION 'couple_profile:invalid';
      END;
      v_date := CASE v_precision
                  WHEN 'month' THEN date_trunc('month', v_date)::date
                  WHEN 'year' THEN date_trunc('year', v_date)::date
                  ELSE v_date END;
      IF v_date < date '1900-01-01' THEN
        RAISE EXCEPTION 'couple_profile:invalid';
      END IF;
      IF v_date > v_last_day THEN
        RAISE EXCEPTION 'couple_profile:future_date';
      END IF;
      v_out := v_out || jsonb_build_object('together_since', v_date,
                                           'together_since_precision', v_precision);
    END IF;
  END IF;

  -- AU1: the stage, and the couple's own words only for "Something else".
  IF p_patch ? 'stage' OR p_patch ? 'stage_words' THEN
    -- The couple's own words are a string or nothing, never a number, a
    -- list or an object stored as its JSON text (batch 1 review Minor 3).
    IF coalesce(jsonb_typeof(p_patch->'stage_words'), 'null') NOT IN ('string', 'null') THEN
      RAISE EXCEPTION 'couple_profile:invalid';
    END IF;
    v_stage := CASE WHEN p_patch ? 'stage' THEN p_patch->>'stage' ELSE v_out->>'stage' END;
    IF v_stage IS NOT NULL AND v_stage NOT IN ('dating', 'engaged', 'married', 'other') THEN
      RAISE EXCEPTION 'couple_profile:invalid';
    END IF;
    v_words := CASE WHEN p_patch ? 'stage_words' THEN p_patch->>'stage_words'
                    ELSE v_out->>'stage_words' END;
    v_words := nullif(btrim(regexp_replace(coalesce(v_words, ''), '[[:cntrl:]]', ' ', 'g')), '');
    IF v_stage IS DISTINCT FROM 'other' THEN
      v_words := NULL;
    END IF;
    IF char_length(v_words) > 40 THEN
      RAISE EXCEPTION 'couple_profile:invalid';
    END IF;
    v_out := v_out || jsonb_build_object('stage', v_stage, 'stage_words', v_words);
    IF v_stage IS DISTINCT FROM 'married' AND NOT p_patch ? 'ceremonies' THEN
      v_out := jsonb_set(v_out, '{ceremonies}', '[]'::jsonb);
    END IF;
  END IF;

  -- AU3: at most two ceremonies, each a year with an optional month, day
  -- and label.
  IF p_patch ? 'ceremonies' THEN
    v_list := p_patch->'ceremonies';
    IF jsonb_typeof(v_list) = 'null' THEN
      v_list := '[]'::jsonb;
    END IF;
    IF jsonb_typeof(v_list) <> 'array' THEN
      RAISE EXCEPTION 'couple_profile:invalid';
    END IF;
    IF jsonb_array_length(v_list) > 2 THEN
      RAISE EXCEPTION 'couple_profile:too_many_ceremonies';
    END IF;
    FOR v_item IN SELECT e.value FROM jsonb_array_elements(v_list) AS e LOOP
      IF jsonb_typeof(v_item) <> 'object'
         OR EXISTS (SELECT 1 FROM jsonb_object_keys(v_item) AS k(name)
                     WHERE k.name NOT IN ('year', 'month', 'day', 'label'))
         OR jsonb_typeof(v_item->'year') IS DISTINCT FROM 'number'
         OR (v_item->>'year') !~ '^\d{4}$'
         OR coalesce(jsonb_typeof(v_item->'month'), 'null') NOT IN ('null', 'number')
         OR coalesce(v_item->>'month', '1') !~ '^\d{1,2}$'
         OR coalesce(jsonb_typeof(v_item->'day'), 'null') NOT IN ('null', 'number')
         OR coalesce(v_item->>'day', '1') !~ '^\d{1,2}$'
         OR coalesce(jsonb_typeof(v_item->'label'), 'null') NOT IN ('null', 'string') THEN
        RAISE EXCEPTION 'couple_profile:invalid';
      END IF;
      v_year := (v_item->>'year')::int;
      v_month := (v_item->>'month')::int;
      v_day := (v_item->>'day')::int;
      v_label := v_item->>'label';
      IF v_year < 1900 OR (v_month IS NOT NULL AND v_month NOT BETWEEN 1 AND 12)
         OR (v_day IS NOT NULL AND v_month IS NULL)
         OR (v_label IS NOT NULL AND v_label NOT IN ('customary', 'church', 'mosque', 'civil', 'other')) THEN
        RAISE EXCEPTION 'couple_profile:invalid';
      END IF;
      BEGIN
        v_date := make_date(v_year, coalesce(v_month, 1), coalesce(v_day, 1));
      EXCEPTION WHEN datetime_field_overflow OR invalid_datetime_format THEN
        RAISE EXCEPTION 'couple_profile:invalid';
      END;
      IF v_date > v_last_day THEN
        RAISE EXCEPTION 'couple_profile:future_date';
      END IF;
      v_clean := v_clean || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
        'year', v_year, 'month', v_month, 'day', v_day, 'label', v_label)));
    END LOOP;
    v_out := jsonb_set(v_out, '{ceremonies}', v_clean);
  END IF;
  IF jsonb_array_length(v_out->'ceremonies') > 0
     AND (v_out->>'stage') IS DISTINCT FROM 'married' THEN
    RAISE EXCEPTION 'couple_profile:ceremonies_need_married';
  END IF;

  -- AU4.
  IF p_patch ? 'living' THEN
    v_text := p_patch->>'living';
    IF v_text IS NOT NULL AND v_text NOT IN ('together', 'apart_nearby', 'long_distance') THEN
      RAISE EXCEPTION 'couple_profile:invalid';
    END IF;
    v_out := v_out || jsonb_build_object('living', v_text);
  END IF;

  -- AU5: age bands only with "Yes"; no names, no counts.
  IF p_patch ? 'children' OR p_patch ? 'child_age_bands' THEN
    v_children := CASE WHEN p_patch ? 'children' THEN p_patch->>'children'
                       ELSE v_out->>'children' END;
    IF v_children IS NOT NULL
       AND v_children NOT IN ('none', 'yes', 'expecting', 'prefer_not_to_say') THEN
      RAISE EXCEPTION 'couple_profile:invalid';
    END IF;
    IF p_patch ? 'child_age_bands' THEN
      v_list := p_patch->'child_age_bands';
      IF jsonb_typeof(v_list) = 'null' THEN
        v_list := '[]'::jsonb;
      END IF;
      IF jsonb_typeof(v_list) <> 'array'
         OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_list) AS e
                     WHERE jsonb_typeof(e.value) <> 'string'
                        OR NOT (e.value #>> '{}') = ANY (v_bands_all)) THEN
        RAISE EXCEPTION 'couple_profile:invalid';
      END IF;
      SELECT coalesce(array_agg(b.band ORDER BY array_position(v_bands_all, b.band)), '{}'::text[])
        INTO v_bands
        FROM (SELECT DISTINCT e.value #>> '{}' AS band FROM jsonb_array_elements(v_list) AS e) AS b;
      IF cardinality(v_bands) > 0 AND v_children IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'couple_profile:bands_need_yes';
      END IF;
    ELSE
      v_bands := ARRAY(SELECT jsonb_array_elements_text(coalesce(v_out->'child_age_bands', '[]'::jsonb)));
    END IF;
    IF v_children IS DISTINCT FROM 'yes' THEN
      v_bands := '{}'::text[];
    END IF;
    v_out := v_out || jsonb_build_object('children', v_children, 'child_age_bands', to_jsonb(v_bands));
  END IF;

  -- AU6: one anniversary source, and it needs a full date.
  IF p_patch ? 'anniversary_source' THEN
    v_source := coalesce(p_patch->>'anniversary_source', 'off');
    IF v_source NOT IN ('off', 'together_since', 'ceremony_1', 'ceremony_2') THEN
      RAISE EXCEPTION 'couple_profile:invalid';
    END IF;
    v_out := jsonb_set(v_out, '{anniversary_source}', to_jsonb(v_source));
  END IF;
  v_source := v_out->>'anniversary_source';
  IF (v_source = 'ceremony_1' AND jsonb_array_length(v_out->'ceremonies') < 1)
     OR (v_source = 'ceremony_2' AND jsonb_array_length(v_out->'ceremonies') < 2) THEN
    IF p_patch ? 'anniversary_source' THEN
      RAISE EXCEPTION 'couple_profile:invalid';
    END IF;
    v_out := jsonb_set(v_out, '{anniversary_source}', '"off"'::jsonb);
    v_source := 'off';
  END IF;
  IF (v_source = 'together_since' AND (v_out->>'together_since_precision') IS DISTINCT FROM 'day')
     OR (v_source = 'ceremony_1' AND private.couple_profile_ceremony_date(v_out->'ceremonies'->0) IS NULL)
     OR (v_source = 'ceremony_2' AND private.couple_profile_ceremony_date(v_out->'ceremonies'->1) IS NULL) THEN
    RAISE EXCEPTION 'couple_profile:anniversary_needs_day';
  END IF;
  RETURN v_out;
END;
$$;
REVOKE ALL ON FUNCTION private.couple_profile_merge(jsonb, jsonb) FROM PUBLIC, anon, authenticated, service_role;

-- The shared profile, for a member while relationship_chat_open (spec
-- §4.3 W5). Values, per-field attribution as a first name or "me" (never
-- an id), read_only unless active, and the window's end for the read-only
-- line. No suggested dates (review I-12).
CREATE OR REPLACE FUNCTION public.get_couple_profile(p_relationship_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid constant uuid := auth.uid();
  v_rel public.relationships%ROWTYPE;
  v public.couple_profiles%ROWTYPE;
BEGIN
  IF v_uid IS NULL OR p_relationship_id IS NULL
     OR NOT public.relationship_chat_open_for(p_relationship_id, v_uid) THEN
    RAISE EXCEPTION 'couple_profile:not_found';
  END IF;
  SELECT * INTO v_rel FROM public.relationships AS r WHERE r.id = p_relationship_id;
  SELECT * INTO v FROM public.couple_profiles AS cp WHERE cp.relationship_id = p_relationship_id;
  RETURN jsonb_build_object(
    'draft', false,
    'read_only', v_rel.status <> 'active',
    'read_until', CASE v_rel.status
                    WHEN 'paused' THEN v_rel.paused_at + interval '30 days'
                    WHEN 'ended' THEN v_rel.ended_at + interval '30 days' END,
    'together_since', v.together_since,
    'together_since_precision', v.together_since_precision,
    'stage', v.stage,
    'stage_words', v.stage_words,
    'ceremonies', coalesce(v.ceremonies, '[]'::jsonb),
    'living', v.living,
    'children', v.children,
    'child_age_bands', to_jsonb(coalesce(v.child_age_bands, '{}'::text[])),
    'anniversary_source', coalesce(v.anniversary_source, 'off'),
    'anniversary_reminder_id', v.anniversary_reminder_id,
    'changes', jsonb_strip_nulls(jsonb_build_object(
      'together_since', private.couple_profile_change(v_uid, v.together_since_changed_by, v.together_since_changed_at),
      'stage', private.couple_profile_change(v_uid, v.stage_changed_by, v.stage_changed_at),
      'ceremonies', private.couple_profile_change(v_uid, v.ceremonies_changed_by, v.ceremonies_changed_at),
      'living', private.couple_profile_change(v_uid, v.living_changed_by, v.living_changed_at),
      'children', private.couple_profile_change(v_uid, v.children_changed_by, v.children_changed_at),
      'anniversary', private.couple_profile_change(v_uid, v.anniversary_changed_by, v.anniversary_changed_at))));
END;
$$;

-- AU6's single source (spec §4.3 W5): 'off' (or a source without a full
-- date) removes the linked reminder; otherwise one yearly "Anniversary"
-- reminders row, on the next occurrence's civil date (midnight UTC, the
-- reminders convention: the generator tells each partner at 09:00 in
-- their own zone; plan P-5), made by whoever chose it. Writes only what
-- changed, so a no-op edit bumps nothing. W5 final review M-1: a
-- 29 February anniversary is kept on a leap year's 29 February (the
-- generator takes the stored month and day), so it is the 28th only in
-- other years. M-2 (ruling "M-2 replaced"): About us never adopts,
-- renames, unlinks or deletes a reminder someone made by hand. While the
-- relationship has a hand-made yearly anniversary-type reminder, it makes
-- none of its own (one anniversary reminder, the couple's); "off" deletes
-- only its own linked one.
CREATE OR REPLACE FUNCTION public.sync_anniversary_reminder(p_relationship_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v public.couple_profiles%ROWTYPE;
  v_date date;
  v_on date;
  v_at timestamptz;
  v_id uuid;
BEGIN
  SELECT * INTO v FROM public.couple_profiles AS cp
   WHERE cp.relationship_id = p_relationship_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN;
  END IF;
  v_date := CASE v.anniversary_source
              WHEN 'together_since' THEN
                CASE WHEN v.together_since_precision = 'day' THEN v.together_since END
              WHEN 'ceremony_1' THEN private.couple_profile_ceremony_date(v.ceremonies->0)
              WHEN 'ceremony_2' THEN private.couple_profile_ceremony_date(v.ceremonies->1)
            END;
  IF v_date IS NULL THEN
    IF v.anniversary_reminder_id IS NOT NULL THEN
      DELETE FROM public.reminders AS r WHERE r.id = v.anniversary_reminder_id;
    END IF;
    RETURN;
  END IF;
  v_on := public.reminder_next_on(v_date, 'yearly', (now() AT TIME ZONE 'utc')::date);
  IF extract(month FROM v_date) = 2 AND extract(day FROM v_date) = 29 THEN
    WHILE extract(day FROM v_on) <> 29 LOOP
      v_on := public.reminder_day_in_year(v_date, extract(year FROM v_on)::int + 1);
    END LOOP;
  END IF;
  v_at := (v_on::text || ' 00:00:00+00')::timestamptz;
  IF v.anniversary_reminder_id IS NOT NULL THEN
    UPDATE public.reminders AS r
       SET remind_at = v_at, title = 'Anniversary', reminder_type = 'anniversary', recurrence = 'yearly'
     WHERE r.id = v.anniversary_reminder_id
       AND (r.remind_at, r.title, r.reminder_type, r.recurrence)
           IS DISTINCT FROM (v_at, 'Anniversary', 'anniversary', 'yearly');
    IF FOUND OR EXISTS (SELECT 1 FROM public.reminders AS r WHERE r.id = v.anniversary_reminder_id) THEN
      RETURN;
    END IF;
  END IF;
  IF EXISTS (SELECT 1 FROM public.reminders AS r
              WHERE r.relationship_id = p_relationship_id
                AND r.reminder_type = 'anniversary' AND r.recurrence = 'yearly') THEN
    RETURN;
  END IF;
  INSERT INTO public.reminders (relationship_id, created_by, reminder_type, title, remind_at, recurrence)
  SELECT p_relationship_id, coalesce(v.anniversary_changed_by, auth.uid(), r.user_a),
         'anniversary', 'Anniversary', v_at, 'yearly'
    FROM public.relationships AS r WHERE r.id = p_relationship_id
  RETURNING id INTO v_id;
  UPDATE public.couple_profiles AS cp SET anniversary_reminder_id = v_id
   WHERE cp.relationship_id = p_relationship_id;
END;
$$;

-- AU1-AU6 written by a member of an active, non-archived relationship
-- (spec §4.3 W5): paused and inside the ending window it is read-only.
-- Each changed field records who and when; leaving Married clears the
-- ceremonies, attributed like any change. Returns the new profile.
CREATE OR REPLACE FUNCTION public.update_couple_profile(p_relationship_id uuid, p_patch jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid constant uuid := auth.uid();
  v_now constant timestamptz := now();
  v_rel public.relationships%ROWTYPE;
  v public.couple_profiles%ROWTYPE;
  v_old jsonb;
  v_new jsonb;
BEGIN
  IF v_uid IS NULL OR p_relationship_id IS NULL
     OR NOT public.relationship_chat_open_for(p_relationship_id, v_uid) THEN
    RAISE EXCEPTION 'couple_profile:not_found';
  END IF;
  SELECT * INTO v_rel FROM public.relationships AS r WHERE r.id = p_relationship_id;
  IF v_rel.status <> 'active' THEN
    RAISE EXCEPTION 'couple_profile:read_only';
  END IF;

  SELECT * INTO v FROM public.couple_profiles AS cp
   WHERE cp.relationship_id = p_relationship_id FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO public.couple_profiles (relationship_id) VALUES (p_relationship_id)
    ON CONFLICT (relationship_id) DO NOTHING;
    SELECT * INTO v FROM public.couple_profiles AS cp
     WHERE cp.relationship_id = p_relationship_id FOR UPDATE;
  END IF;

  v_old := jsonb_build_object(
    'together_since', v.together_since, 'together_since_precision', v.together_since_precision,
    'stage', v.stage, 'stage_words', v.stage_words, 'ceremonies', v.ceremonies,
    'living', v.living, 'children', v.children, 'child_age_bands', to_jsonb(v.child_age_bands),
    'anniversary_source', v.anniversary_source);
  v_new := private.couple_profile_merge(v_old, p_patch);

  IF v_new IS DISTINCT FROM v_old THEN
    UPDATE public.couple_profiles AS cp
       SET together_since = (v_new->>'together_since')::date,
           together_since_precision = v_new->>'together_since_precision',
           stage = v_new->>'stage',
           stage_words = v_new->>'stage_words',
           ceremonies = v_new->'ceremonies',
           living = v_new->>'living',
           children = v_new->>'children',
           child_age_bands = ARRAY(SELECT jsonb_array_elements_text(v_new->'child_age_bands')),
           anniversary_source = v_new->>'anniversary_source',
           together_since_changed_by = CASE WHEN (v_new->'together_since', v_new->'together_since_precision')
                                                 IS DISTINCT FROM (v_old->'together_since', v_old->'together_since_precision')
                                            THEN v_uid ELSE cp.together_since_changed_by END,
           together_since_changed_at = CASE WHEN (v_new->'together_since', v_new->'together_since_precision')
                                                 IS DISTINCT FROM (v_old->'together_since', v_old->'together_since_precision')
                                            THEN v_now ELSE cp.together_since_changed_at END,
           stage_changed_by = CASE WHEN (v_new->'stage', v_new->'stage_words')
                                        IS DISTINCT FROM (v_old->'stage', v_old->'stage_words')
                                   THEN v_uid ELSE cp.stage_changed_by END,
           stage_changed_at = CASE WHEN (v_new->'stage', v_new->'stage_words')
                                        IS DISTINCT FROM (v_old->'stage', v_old->'stage_words')
                                   THEN v_now ELSE cp.stage_changed_at END,
           ceremonies_changed_by = CASE WHEN v_new->'ceremonies' IS DISTINCT FROM v_old->'ceremonies'
                                        THEN v_uid ELSE cp.ceremonies_changed_by END,
           ceremonies_changed_at = CASE WHEN v_new->'ceremonies' IS DISTINCT FROM v_old->'ceremonies'
                                        THEN v_now ELSE cp.ceremonies_changed_at END,
           living_changed_by = CASE WHEN v_new->'living' IS DISTINCT FROM v_old->'living'
                                    THEN v_uid ELSE cp.living_changed_by END,
           living_changed_at = CASE WHEN v_new->'living' IS DISTINCT FROM v_old->'living'
                                    THEN v_now ELSE cp.living_changed_at END,
           children_changed_by = CASE WHEN (v_new->'children', v_new->'child_age_bands')
                                           IS DISTINCT FROM (v_old->'children', v_old->'child_age_bands')
                                      THEN v_uid ELSE cp.children_changed_by END,
           children_changed_at = CASE WHEN (v_new->'children', v_new->'child_age_bands')
                                           IS DISTINCT FROM (v_old->'children', v_old->'child_age_bands')
                                      THEN v_now ELSE cp.children_changed_at END,
           anniversary_changed_by = CASE WHEN v_new->'anniversary_source' IS DISTINCT FROM v_old->'anniversary_source'
                                         THEN v_uid ELSE cp.anniversary_changed_by END,
           anniversary_changed_at = CASE WHEN v_new->'anniversary_source' IS DISTINCT FROM v_old->'anniversary_source'
                                         THEN v_now ELSE cp.anniversary_changed_at END,
           updated_at = v_now
     WHERE cp.relationship_id = p_relationship_id;
  END IF;
  PERFORM public.sync_anniversary_reminder(p_relationship_id);
  RETURN public.get_couple_profile(p_relationship_id);
END;
$$;

-- The caller's own draft (spec §4.3 W5): the same answers as the shared
-- profile, no attribution (only its owner ever sees it), Relationship path
-- only, and never while the caller is in an active or paused relationship
-- (review F-2).
CREATE OR REPLACE FUNCTION public.get_my_couple_profile_draft()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid constant uuid := auth.uid();
  v public.couple_profile_drafts%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'couple_profile:not_found';
  END IF;
  IF (SELECT u.path FROM public.users AS u WHERE u.id = v_uid) IS DISTINCT FROM 'relationship' THEN
    RAISE EXCEPTION 'couple_profile:not_relationship';
  END IF;
  -- Review F-2: a linked person has no draft. An answer queued before
  -- linking and replayed after it is refused (the phone drops a refusal),
  -- so no stale draft waits for a later link.
  IF EXISTS (SELECT 1 FROM public.relationships AS r
              WHERE (r.user_a = v_uid OR r.user_b = v_uid)
                AND r.status IN ('active', 'paused')) THEN
    RAISE EXCEPTION 'couple_profile:not_found';
  END IF;
  SELECT * INTO v FROM public.couple_profile_drafts AS d WHERE d.user_id = v_uid;
  RETURN jsonb_build_object(
    'draft', true,
    'read_only', false,
    'read_until', NULL,
    'together_since', v.together_since,
    'together_since_precision', v.together_since_precision,
    'stage', v.stage,
    'stage_words', v.stage_words,
    'ceremonies', coalesce(v.ceremonies, '[]'::jsonb),
    'living', v.living,
    'children', v.children,
    'child_age_bands', to_jsonb(coalesce(v.child_age_bands, '{}'::text[])),
    'anniversary_source', coalesce(v.anniversary_source, 'off'),
    'anniversary_reminder_id', NULL,
    'changes', '{}'::jsonb);
END;
$$;

-- Writes the caller's draft with the shared profile's validation. The
-- users row is read FOR SHARE first, the order set_user_path_internal and
-- the accept use (users, then the draft), so a switch to Dating can't
-- leave a draft behind. The relationship check (review F-2) runs after
-- that lock, so an accept that held it is seen committed.
CREATE OR REPLACE FUNCTION public.update_my_couple_profile_draft(p_patch jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid constant uuid := auth.uid();
  v_now constant timestamptz := now();
  v_path text;
  v public.couple_profile_drafts%ROWTYPE;
  v_old jsonb;
  v_new jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'couple_profile:not_found';
  END IF;
  SELECT u.path INTO v_path FROM public.users AS u WHERE u.id = v_uid FOR SHARE;
  IF v_path IS DISTINCT FROM 'relationship' THEN
    RAISE EXCEPTION 'couple_profile:not_relationship';
  END IF;
  -- Review F-2: a linked person has no draft. An answer queued before
  -- linking and replayed after it is refused (the phone drops a refusal),
  -- so no stale draft waits for a later link.
  IF EXISTS (SELECT 1 FROM public.relationships AS r
              WHERE (r.user_a = v_uid OR r.user_b = v_uid)
                AND r.status IN ('active', 'paused')) THEN
    RAISE EXCEPTION 'couple_profile:not_found';
  END IF;
  INSERT INTO public.couple_profile_drafts (user_id) VALUES (v_uid)
  ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO v FROM public.couple_profile_drafts AS d WHERE d.user_id = v_uid FOR UPDATE;

  v_old := jsonb_build_object(
    'together_since', v.together_since, 'together_since_precision', v.together_since_precision,
    'stage', v.stage, 'stage_words', v.stage_words, 'ceremonies', v.ceremonies,
    'living', v.living, 'children', v.children, 'child_age_bands', to_jsonb(v.child_age_bands),
    'anniversary_source', v.anniversary_source);
  v_new := private.couple_profile_merge(v_old, p_patch);

  IF v_new IS DISTINCT FROM v_old OR (p_patch ? 'anniversary_source' AND v.anniversary_set_at IS NULL) THEN
    UPDATE public.couple_profile_drafts AS d
       SET together_since = (v_new->>'together_since')::date,
           together_since_precision = v_new->>'together_since_precision',
           stage = v_new->>'stage',
           stage_words = v_new->>'stage_words',
           ceremonies = v_new->'ceremonies',
           living = v_new->>'living',
           children = v_new->>'children',
           child_age_bands = ARRAY(SELECT jsonb_array_elements_text(v_new->'child_age_bands')),
           anniversary_source = v_new->>'anniversary_source',
           together_since_set_at = CASE WHEN (v_new->'together_since', v_new->'together_since_precision')
                                             IS DISTINCT FROM (v_old->'together_since', v_old->'together_since_precision')
                                        THEN v_now ELSE d.together_since_set_at END,
           stage_set_at = CASE WHEN (v_new->'stage', v_new->'stage_words')
                                    IS DISTINCT FROM (v_old->'stage', v_old->'stage_words')
                               THEN v_now ELSE d.stage_set_at END,
           ceremonies_set_at = CASE WHEN v_new->'ceremonies' IS DISTINCT FROM v_old->'ceremonies'
                                    THEN v_now ELSE d.ceremonies_set_at END,
           living_set_at = CASE WHEN v_new->'living' IS DISTINCT FROM v_old->'living'
                                THEN v_now ELSE d.living_set_at END,
           children_set_at = CASE WHEN (v_new->'children', v_new->'child_age_bands')
                                       IS DISTINCT FROM (v_old->'children', v_old->'child_age_bands')
                                  THEN v_now ELSE d.children_set_at END,
           -- "No, thanks" is an answer too (it beats the partner's draft at
           -- linking), so choosing it the first time is recorded.
           anniversary_set_at = CASE WHEN v_new->'anniversary_source' IS DISTINCT FROM v_old->'anniversary_source'
                                          OR (p_patch ? 'anniversary_source' AND d.anniversary_set_at IS NULL)
                                     THEN v_now ELSE d.anniversary_set_at END,
           updated_at = v_now
     WHERE d.user_id = v_uid;
  END IF;
  RETURN public.get_my_couple_profile_draft();
END;
$$;

-- Linking (spec §4.3 W5, §3.8 R4): the inviter's draft first, the
-- acceptor's filling every field the inviter left empty; each field keeps
-- its owner and the time they set it. A merge that would break a rule
-- (ceremonies without Married, an anniversary without a full date) drops
-- the dependent field rather than refusing the link. Both drafts go.
-- Called only by accept_relationship_invite_v2, after both users rows are
-- locked (users, then the drafts, the order of every draft writer).
CREATE OR REPLACE FUNCTION public.adopt_couple_profile_drafts(p_relationship_id uuid, p_inviter uuid, p_acceptor uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  vi public.couple_profile_drafts%ROWTYPE;
  va public.couple_profile_drafts%ROWTYPE;
  v public.couple_profiles%ROWTYPE;
  v_date date;
BEGIN
  PERFORM 1 FROM public.couple_profile_drafts AS d
   WHERE d.user_id IN (p_inviter, p_acceptor) ORDER BY d.user_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN;
  END IF;
  SELECT * INTO vi FROM public.couple_profile_drafts AS d WHERE d.user_id = p_inviter;
  SELECT * INTO va FROM public.couple_profile_drafts AS d WHERE d.user_id = p_acceptor;

  v.relationship_id := p_relationship_id;
  IF vi.together_since IS NOT NULL THEN
    v.together_since := vi.together_since; v.together_since_precision := vi.together_since_precision;
    v.together_since_changed_by := p_inviter; v.together_since_changed_at := vi.together_since_set_at;
  ELSIF va.together_since IS NOT NULL THEN
    v.together_since := va.together_since; v.together_since_precision := va.together_since_precision;
    v.together_since_changed_by := p_acceptor; v.together_since_changed_at := va.together_since_set_at;
  END IF;
  IF vi.stage IS NOT NULL THEN
    v.stage := vi.stage; v.stage_words := vi.stage_words;
    v.stage_changed_by := p_inviter; v.stage_changed_at := vi.stage_set_at;
  ELSIF va.stage IS NOT NULL THEN
    v.stage := va.stage; v.stage_words := va.stage_words;
    v.stage_changed_by := p_acceptor; v.stage_changed_at := va.stage_set_at;
  END IF;
  v.ceremonies := '[]'::jsonb;
  IF v.stage = 'married' THEN
    IF jsonb_array_length(coalesce(vi.ceremonies, '[]'::jsonb)) > 0 AND vi.stage = 'married' THEN
      v.ceremonies := vi.ceremonies;
      v.ceremonies_changed_by := p_inviter; v.ceremonies_changed_at := vi.ceremonies_set_at;
    ELSIF jsonb_array_length(coalesce(va.ceremonies, '[]'::jsonb)) > 0 AND va.stage = 'married' THEN
      v.ceremonies := va.ceremonies;
      v.ceremonies_changed_by := p_acceptor; v.ceremonies_changed_at := va.ceremonies_set_at;
    END IF;
  END IF;
  IF vi.living IS NOT NULL THEN
    v.living := vi.living; v.living_changed_by := p_inviter; v.living_changed_at := vi.living_set_at;
  ELSIF va.living IS NOT NULL THEN
    v.living := va.living; v.living_changed_by := p_acceptor; v.living_changed_at := va.living_set_at;
  END IF;
  v.child_age_bands := '{}'::text[];
  IF vi.children IS NOT NULL THEN
    v.children := vi.children; v.child_age_bands := vi.child_age_bands;
    v.children_changed_by := p_inviter; v.children_changed_at := vi.children_set_at;
  ELSIF va.children IS NOT NULL THEN
    v.children := va.children; v.child_age_bands := va.child_age_bands;
    v.children_changed_by := p_acceptor; v.children_changed_at := va.children_set_at;
  END IF;
  v.anniversary_source := 'off';
  IF vi.anniversary_set_at IS NOT NULL THEN
    v.anniversary_source := vi.anniversary_source;
    v.anniversary_changed_by := p_inviter; v.anniversary_changed_at := vi.anniversary_set_at;
  ELSIF va.anniversary_set_at IS NOT NULL THEN
    v.anniversary_source := va.anniversary_source;
    v.anniversary_changed_by := p_acceptor; v.anniversary_changed_at := va.anniversary_set_at;
  END IF;
  v_date := CASE v.anniversary_source
              WHEN 'together_since' THEN
                CASE WHEN v.together_since_precision = 'day' THEN v.together_since END
              WHEN 'ceremony_1' THEN private.couple_profile_ceremony_date(v.ceremonies->0)
              WHEN 'ceremony_2' THEN private.couple_profile_ceremony_date(v.ceremonies->1)
            END;
  IF v.anniversary_source <> 'off' AND v_date IS NULL THEN
    v.anniversary_source := 'off';
    v.anniversary_changed_by := NULL; v.anniversary_changed_at := NULL;
  END IF;
  v.updated_at := now();

  INSERT INTO public.couple_profiles SELECT (v).*
  ON CONFLICT (relationship_id) DO NOTHING;
  DELETE FROM public.couple_profile_drafts AS d WHERE d.user_id IN (p_inviter, p_acceptor);
  PERFORM public.sync_anniversary_reminder(p_relationship_id);
END;
$$;

-- Plan P-6: the anniversary reminder follows About us. A client (the app
-- or a direct call) can't delete it or change its date, title, type,
-- recurrence, relationship or maker; About us does (definer functions
-- pass). Lead times and the note stay the couple's.
CREATE OR REPLACE FUNCTION private.guard_about_us_reminder()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon')
     OR NOT EXISTS (SELECT 1 FROM public.couple_profiles AS cp
                     WHERE cp.anniversary_reminder_id = OLD.id) THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
  END IF;
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'reminder:follows_about_us';
  END IF;
  IF (NEW.reminder_type, NEW.title, NEW.remind_at, NEW.recurrence, NEW.relationship_id, NEW.created_by)
     IS DISTINCT FROM (OLD.reminder_type, OLD.title, OLD.remind_at, OLD.recurrence, OLD.relationship_id, OLD.created_by) THEN
    RAISE EXCEPTION 'reminder:follows_about_us';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.guard_about_us_reminder() FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS reminders_guard_about_us ON public.reminders;
CREATE TRIGGER reminders_guard_about_us
  BEFORE UPDATE OR DELETE ON public.reminders
  FOR EACH ROW EXECUTE FUNCTION private.guard_about_us_reminder();

DROP TRIGGER IF EXISTS couple_profiles_together_signal ON public.couple_profiles;
CREATE TRIGGER couple_profiles_together_signal
  AFTER INSERT OR UPDATE OR DELETE ON public.couple_profiles
  FOR EACH ROW EXECUTE FUNCTION public.bump_together_signal();

REVOKE ALL ON FUNCTION public.get_couple_profile(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_couple_profile(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_couple_profile_draft() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_my_couple_profile_draft(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.adopt_couple_profile_drafts(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.sync_anniversary_reminder(uuid) FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
