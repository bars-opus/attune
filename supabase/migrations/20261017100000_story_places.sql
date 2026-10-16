-- Couple map, Phase 2: stories pinned at their exact place (spec 2026-10-16
-- §2 ruling 2, §4.5, §5.2). The author chooses each place at post time;
-- nothing is backfilled; the author can remove one or all; deleting the
-- story or closing the relationship removes them.

CREATE TABLE public.story_places (
  story_item_id   uuid PRIMARY KEY REFERENCES public.story_items(id) ON DELETE CASCADE,
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  author_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  lat             numeric(9,6) NOT NULL CHECK (lat BETWEEN -90 AND 90),
  lng             numeric(9,6) NOT NULL CHECK (lng BETWEEN -180 AND 180),
  label           text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 120),
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX story_places_relationship_idx ON public.story_places (relationship_id, lat, lng);
CREATE INDEX story_places_author_idx ON public.story_places (relationship_id, author_id);

ALTER TABLE public.story_places ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.story_places FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.story_places TO authenticated;
CREATE POLICY story_places_read_members ON public.story_places
  FOR SELECT TO authenticated
  USING (public.story_relationship_is_open(relationship_id, auth.uid()));

-- A client place, or NULLs when anything is off. Malformed input is
-- dropped, never raised: the story must still post.
CREATE OR REPLACE FUNCTION public.story_place_parse(
  p_place jsonb, OUT lat numeric, OUT lng numeric, OUT label text)
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v_lat double precision; v_lng double precision; v_label text;
BEGIN
  IF p_place IS NULL OR jsonb_typeof(p_place) IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_place->'lat') IS DISTINCT FROM 'number'
     OR jsonb_typeof(p_place->'lng') IS DISTINCT FROM 'number'
     OR jsonb_typeof(p_place->'label') IS DISTINCT FROM 'string' THEN
    RETURN;
  END IF;
  v_lat := (p_place->>'lat')::double precision;
  v_lng := (p_place->>'lng')::double precision;
  v_label := btrim(p_place->>'label');
  IF v_lat NOT BETWEEN -90 AND 90 OR v_lng NOT BETWEEN -180 AND 180 OR v_label = '' THEN
    RETURN;
  END IF;
  lat := round(v_lat::numeric, 6);
  lng := round(v_lng::numeric, 6);
  label := left(v_label, 120);
END $$;
REVOKE ALL ON FUNCTION public.story_place_parse(jsonb) FROM PUBLIC, anon, authenticated;

-- The 8-argument finalize becomes the core; the public name gains p_place.
-- Renaming (not copying) keeps the long, reviewed body exactly as it is,
-- and leaves no 8-argument overload for PostgREST to find ambiguous
-- (PGRST203). Older apps' 8-parameter calls resolve to the new function,
-- since p_place defaults to null.
ALTER FUNCTION public.create_story_item(uuid, uuid, uuid, uuid, int, int, int, int)
  RENAME TO create_story_item_core;
REVOKE ALL ON FUNCTION public.create_story_item_core(uuid, uuid, uuid, uuid, int, int, int, int)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_story_item(
  p_relationship_id     uuid,
  p_client_story_id     uuid,
  p_media_intent_id     uuid,
  p_thumbnail_intent_id uuid,
  p_media_width         int,
  p_media_height        int,
  p_duration_ms         int,
  p_utc_offset_minutes  int,
  p_place               jsonb DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, storage AS $$
DECLARE v_res jsonb; v_place record;
BEGIN
  v_res := public.create_story_item_core(
    p_relationship_id, p_client_story_id, p_media_intent_id, p_thumbnail_intent_id,
    p_media_width, p_media_height, p_duration_ms, p_utc_offset_minutes);
  -- A place only on a FRESH insert: a replay never adds one (no backfill).
  IF p_place IS NULL
     OR (v_res->>'error') IS NOT DISTINCT FROM 'true'
     OR (v_res->>'existing')::boolean IS DISTINCT FROM false THEN
    RETURN v_res;
  END IF;
  -- Behind the couple map flag: turning it off stops new places (rollback).
  IF NOT EXISTS (SELECT 1 FROM public.feature_flags WHERE key = 'couple_map_enabled' AND enabled) THEN
    RETURN v_res;
  END IF;
  SELECT * INTO v_place FROM public.story_place_parse(p_place);
  IF v_place.lat IS NULL THEN
    RETURN v_res;
  END IF;
  BEGIN
    INSERT INTO public.story_places (story_item_id, relationship_id, author_id, lat, lng, label)
    VALUES ((v_res->>'story_id')::uuid, p_relationship_id, auth.uid(),
            v_place.lat, v_place.lng, v_place.label);
  EXCEPTION WHEN others THEN
    NULL; -- never fatal to the story
  END;
  RETURN v_res;
END $$;
REVOKE ALL ON FUNCTION public.create_story_item(uuid, uuid, uuid, uuid, int, int, int, int, jsonb)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_story_item(uuid, uuid, uuid, uuid, int, int, int, int, jsonb)
  TO authenticated;

-- Deleting a story (soft delete) removes its place for good.
CREATE OR REPLACE FUNCTION public.story_places_drop_on_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
    DELETE FROM public.story_places WHERE story_item_id = NEW.id;
  END IF;
  RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION public.story_places_drop_on_delete() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS story_places_drop_on_delete ON public.story_items;
CREATE TRIGGER story_places_drop_on_delete
  AFTER UPDATE OF deleted_at ON public.story_items
  FOR EACH ROW EXECUTE FUNCTION public.story_places_drop_on_delete();

-- The author removes one place. A non-author's call removes nothing and
-- says nothing (no existence oracle). Idempotent.
CREATE OR REPLACE FUNCTION public.clear_story_place(p_story_item_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rel uuid;
BEGIN
  IF auth.uid() IS NULL THEN PERFORM public.presence_fail('not_found'); END IF;
  DELETE FROM public.story_places
   WHERE story_item_id = p_story_item_id AND author_id = auth.uid()
  RETURNING relationship_id INTO v_rel;
  IF v_rel IS NOT NULL THEN PERFORM public.bump_story_signal(v_rel); END IF;
END $$;

-- The author removes every place they pinned in this couple; returns how many.
CREATE OR REPLACE FUNCTION public.clear_my_story_places(p_relationship_id uuid)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n int;
BEGIN
  IF auth.uid() IS NULL THEN PERFORM public.presence_fail('not_found'); END IF;
  DELETE FROM public.story_places
   WHERE relationship_id = p_relationship_id AND author_id = auth.uid();
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n > 0 THEN PERFORM public.bump_story_signal(p_relationship_id); END IF;
  RETURN v_n;
END $$;

-- Places in a box, newest first, at most 500. SECURITY INVOKER: RLS on
-- story_places and story_items (deleted_at, open relationship) applies.
CREATE OR REPLACE FUNCTION public.list_story_places(
  p_relationship_id uuid, p_author_id uuid,
  p_min_lat numeric, p_min_lng numeric, p_max_lat numeric, p_max_lng numeric,
  p_limit int DEFAULT 500)
RETURNS TABLE (
  story_item_id uuid, author_id uuid, lat numeric, lng numeric, label text, placed_at timestamptz,
  client_story_id uuid, media_type text, media_key text, thumbnail_key text,
  media_width int, media_height int, duration_ms int, occurred_on date,
  created_at timestamptz, expires_at timestamptz)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $$
  SELECT sp.story_item_id, sp.author_id, sp.lat, sp.lng, sp.label, sp.created_at,
         si.client_story_id, si.media_type, si.media_key, si.thumbnail_key,
         si.media_width, si.media_height, si.duration_ms, si.occurred_on,
         si.created_at, si.expires_at
    FROM public.story_places sp
    JOIN public.story_items si ON si.id = sp.story_item_id
   WHERE p_min_lat IS NOT NULL AND p_min_lng IS NOT NULL
     AND p_max_lat IS NOT NULL AND p_max_lng IS NOT NULL
     AND sp.relationship_id = p_relationship_id
     AND (p_author_id IS NULL OR sp.author_id = p_author_id)
     AND sp.lat BETWEEN p_min_lat AND p_max_lat
     AND sp.lng BETWEEN p_min_lng AND p_max_lng
   ORDER BY si.created_at DESC, si.id DESC
   LIMIT LEAST(GREATEST(COALESCE(p_limit, 500), 1), 500)
$$;

REVOKE ALL ON FUNCTION public.clear_story_place(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.clear_my_story_places(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_story_places(uuid, uuid, numeric, numeric, numeric, numeric, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.clear_story_place(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.clear_my_story_places(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_story_places(uuid, uuid, numeric, numeric, numeric, numeric, int) TO authenticated;

-- Closing the relationship purges presence (Phase 0) and story places.
CREATE OR REPLACE FUNCTION public.presence_purge_on_relationship_close()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF (NEW.status IS DISTINCT FROM OLD.status AND NEW.status <> 'active')
     OR (OLD.chat_archived_at IS NULL AND NEW.chat_archived_at IS NOT NULL) THEN
    DELETE FROM public.partner_presence WHERE relationship_id = NEW.id;
    DELETE FROM public.story_places WHERE relationship_id = NEW.id;
  END IF;
  RETURN NULL;
END $$;

NOTIFY pgrst, 'reload schema';
