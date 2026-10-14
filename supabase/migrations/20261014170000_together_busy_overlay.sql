-- Together Phase 6: lend only *when* you're busy, opt-in per person (spec
-- §3.3, D5, §6.4; plan R1–R5). Times only, rounded to 30 minutes, 14 days.

ALTER TABLE public.together_member_prefs
  ADD COLUMN overlay text NOT NULL DEFAULT 'off'
    CHECK (overlay IN ('off', 'free_windows', 'strips'));

CREATE TABLE public.couple_busy_blocks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  uploaded_at timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at),
  CHECK (extract(epoch FROM starts_at)::bigint % 1800 = 0 AND extract(epoch FROM ends_at)::bigint % 1800 = 0)
);
CREATE INDEX idx_couple_busy_blocks_rel ON public.couple_busy_blocks (relationship_id, starts_at);
ALTER TABLE public.couple_busy_blocks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.couple_busy_blocks FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.together_overlay_level(p_relationship_id uuid, p_user uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((SELECT p.overlay FROM public.together_member_prefs p
                   WHERE p.relationship_id = p_relationship_id AND p.user_id = p_user), 'off')
$$;
CREATE FUNCTION public.together_member_tz(p_relationship_id uuid, p_user uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((SELECT s.timezone FROM public.planning_member_settings s
                   WHERE s.relationship_id = p_relationship_id AND s.user_id = p_user), 'UTC')
$$;
REVOKE ALL ON FUNCTION public.together_overlay_level(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.together_member_tz(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.get_together_overlay(p_relationship_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_me uuid := public.together_actor(p_relationship_id);
BEGIN
  RETURN jsonb_build_object('level', public.together_overlay_level(p_relationship_id, v_me));
END;
$$;

-- Turning it off deletes my busy times in the same call; the partner is told nothing.
CREATE FUNCTION public.set_together_overlay(p_relationship_id uuid, p_level text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_me uuid := public.together_actor(p_relationship_id);
BEGIN
  IF p_level IS NULL OR p_level NOT IN ('off', 'free_windows', 'strips') THEN
    PERFORM public.together_fail('invalid_input');
  END IF;
  INSERT INTO public.together_member_prefs (relationship_id, user_id, overlay, updated_at)
  VALUES (p_relationship_id, v_me, p_level, now())
  ON CONFLICT (relationship_id, user_id) DO UPDATE SET overlay = EXCLUDED.overlay, updated_at = now();
  IF p_level = 'off' THEN
    DELETE FROM public.couple_busy_blocks WHERE relationship_id = p_relationship_id AND user_id = v_me;
  END IF;
  RETURN jsonb_build_object('level', p_level);
END;
$$;

-- Replace someone's busy times as of p_now: rounded outward to 30 minutes,
-- clipped to p_now..p_now+14 days, anything outside dropped. Internal.
CREATE FUNCTION public.together_store_busy_blocks(p_relationship_id uuid, p_user uuid, p_blocks jsonb, p_now timestamptz)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n int;
BEGIN
  -- Every element must be an object with both times: greatest()/least() skip
  -- NULLs, so a missing time would otherwise become a 14-day busy block.
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_blocks) b
             WHERE jsonb_typeof(b) <> 'object' OR NOT (b ? 'starts_at') OR NOT (b ? 'ends_at')
                OR jsonb_typeof(b->'starts_at') <> 'string' OR jsonb_typeof(b->'ends_at') <> 'string') THEN
    PERFORM public.together_fail('invalid_input');
  END IF;
  DELETE FROM public.couple_busy_blocks WHERE relationship_id = p_relationship_id AND user_id = p_user;
  BEGIN
    INSERT INTO public.couple_busy_blocks (relationship_id, user_id, starts_at, ends_at)
    SELECT p_relationship_id, p_user, s, e
    FROM (
      SELECT to_timestamp(floor(extract(epoch FROM greatest((b->>'starts_at')::timestamptz, p_now)) / 1800) * 1800) AS s,
             to_timestamp(ceil(extract(epoch FROM least((b->>'ends_at')::timestamptz, p_now + interval '14 days')) / 1800) * 1800) AS e
      FROM jsonb_array_elements(p_blocks) b
    ) r
    WHERE e > s;
  EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow OR invalid_text_representation THEN
    PERFORM public.together_fail('invalid_input');
  END;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.together_store_busy_blocks(uuid, uuid, jsonb, timestamptz) FROM PUBLIC, anon, authenticated;

-- My busy times for the next 14 days, replacing what was there (only while on).
CREATE FUNCTION public.replace_my_busy_blocks(p_relationship_id uuid, p_blocks jsonb)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_me uuid := public.together_actor(p_relationship_id);
BEGIN
  IF public.together_overlay_level(p_relationship_id, v_me) = 'off'
     OR p_blocks IS NULL OR jsonb_typeof(p_blocks) <> 'array' OR jsonb_array_length(p_blocks) > 300 THEN
    PERFORM public.together_fail('invalid_input');
  END IF;
  RETURN public.together_store_busy_blocks(p_relationship_id, v_me, p_blocks, now());
END;
$$;

-- When we're both free (R1–R3): 30-minute slots on the UTC grid over 14 days,
-- inside both partners' waking hours, clear of both partners' busy blocks and
-- of every Together event I can see; runs of ≥ 60 minutes. Empty unless both opted in.
CREATE FUNCTION public.list_together_free_windows(p_relationship_id uuid, p_now timestamptz DEFAULT now())
RETURNS TABLE (starts_at timestamptz, ends_at timestamptz, partner_from text, partner_to text, partner_differs boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE
  v_me uuid := public.together_actor(p_relationship_id);
  v_partner uuid := public.together_partner(p_relationship_id, v_me);
  v_tz_me text; v_tz_p text;
  v_from timestamptz := to_timestamp(ceil(extract(epoch FROM p_now) / 1800) * 1800);
BEGIN
  IF v_partner IS NULL
     OR public.together_overlay_level(p_relationship_id, v_me) = 'off'
     OR public.together_overlay_level(p_relationship_id, v_partner) = 'off' THEN
    RETURN;
  END IF;
  v_tz_me := public.together_member_tz(p_relationship_id, v_me);
  v_tz_p := public.together_member_tz(p_relationship_id, v_partner);
  RETURN QUERY
  WITH busy_events AS (
    SELECT CASE WHEN i.all_day THEN NULL ELSE i.starts_at END AS s,
           CASE WHEN i.all_day THEN NULL ELSE coalesce(i.ends_at, i.starts_at + interval '1 hour') END AS e,
           CASE WHEN i.all_day THEN i.item_date END AS d
    FROM public.together_items_for(v_me, p_relationship_id,
           (v_from AT TIME ZONE 'UTC')::date - 1, (v_from AT TIME ZONE 'UTC')::date + 15) i
    WHERE i.item_kind = 'event' AND (NOT i.all_day OR i.source_ref->>'kind' = 'trip')
  ), slots AS (
    SELECT g AS s, g + interval '30 minutes' AS e
    FROM generate_series(v_from, v_from + interval '14 days' - interval '30 minutes', interval '30 minutes') g
  ), free AS (
    SELECT sl.s, sl.e FROM slots sl
    WHERE (sl.s AT TIME ZONE v_tz_me)::time BETWEEN time '08:00' AND time '21:30'
      AND (sl.s AT TIME ZONE v_tz_p)::time BETWEEN time '08:00' AND time '21:30'
      AND NOT EXISTS (SELECT 1 FROM public.couple_busy_blocks b
                      WHERE b.relationship_id = p_relationship_id AND b.user_id IN (v_me, v_partner)
                        AND b.starts_at < sl.e AND b.ends_at > sl.s)
      AND NOT EXISTS (SELECT 1 FROM busy_events x
                      WHERE (x.s IS NOT NULL AND x.s < sl.e AND x.e > sl.s)
                         OR (x.d IS NOT NULL AND x.d IN ((sl.s AT TIME ZONE v_tz_me)::date,
                                                         (sl.s AT TIME ZONE v_tz_p)::date)))
  ), runs AS (
    SELECT f.s, f.e, f.s - (row_number() OVER (ORDER BY f.s)) * interval '30 minutes' AS grp FROM free f
  ), windows AS (
    SELECT min(r.s) AS ws, max(r.e) AS we FROM runs r GROUP BY r.grp
    HAVING max(r.e) - min(r.s) >= interval '60 minutes'
  )
  SELECT w.ws, w.we,
         to_char(w.ws AT TIME ZONE v_tz_p, 'HH24:MI'), to_char(w.we AT TIME ZONE v_tz_p, 'HH24:MI'),
         to_char(w.ws AT TIME ZONE v_tz_p, 'HH24:MI') <> to_char(w.ws AT TIME ZONE v_tz_me, 'HH24:MI')
  FROM windows w ORDER BY w.ws;
END;
$$;

-- Busy strips (D5): mine always; my partner's only at their 'strips' level,
-- and only while I'm opted in too (same rules for both).
CREATE FUNCTION public.list_together_busy_strips(p_relationship_id uuid, p_now timestamptz DEFAULT now())
RETURNS TABLE (is_mine boolean, starts_at timestamptz, ends_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE
  v_me uuid := public.together_actor(p_relationship_id);
  v_partner uuid := public.together_partner(p_relationship_id, v_me);
BEGIN
  IF public.together_overlay_level(p_relationship_id, v_me) = 'off' THEN RETURN; END IF;
  RETURN QUERY
  SELECT b.user_id = v_me, b.starts_at, b.ends_at
  FROM public.couple_busy_blocks b
  WHERE b.relationship_id = p_relationship_id AND b.ends_at > p_now
    AND (b.user_id = v_me
         OR (b.user_id = v_partner AND public.together_overlay_level(p_relationship_id, v_partner) = 'strips'))
  ORDER BY b.starts_at;
END;
$$;

CREATE FUNCTION public.together_purge_busy_blocks() RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  DELETE FROM public.couple_busy_blocks WHERE ends_at < now()
$$;
REVOKE ALL ON FUNCTION public.together_purge_busy_blocks() FROM PUBLIC, anon, authenticated;
SELECT cron.schedule('together_busy_purge', '45 3 * * *', $$ SELECT public.together_purge_busy_blocks(); $$);

-- Ending a couple (any path) purges its busy times (spec §3.8).
CREATE FUNCTION public.together_purge_busy_on_end() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF (OLD.status = 'active' AND NEW.status <> 'active')
     OR (OLD.chat_archived_at IS NULL AND NEW.chat_archived_at IS NOT NULL) THEN
    DELETE FROM public.couple_busy_blocks WHERE relationship_id = OLD.id;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trigger_together_purge_busy ON public.relationships;
CREATE TRIGGER trigger_together_purge_busy
  AFTER UPDATE OF status, chat_archived_at ON public.relationships
  FOR EACH ROW EXECUTE FUNCTION public.together_purge_busy_on_end();

REVOKE ALL ON FUNCTION public.get_together_overlay(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_together_overlay(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.replace_my_busy_blocks(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_together_free_windows(uuid, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_together_busy_strips(uuid, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_together_overlay(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_together_overlay(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.replace_my_busy_blocks(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_together_free_windows(uuid, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_together_busy_strips(uuid, timestamptz) TO authenticated;
