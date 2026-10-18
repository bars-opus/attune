-- Per-plan "new from your partner" (2026-10-18). A plan is new to someone
-- when their partner made its latest change after they last opened it;
-- opening it (get_planning_entry) marks it seen. The plan rows in Recent and
-- in a category (planning_v2_entry_summary) carry has_new, and the category
-- dot (get_planning_home) now means "a plan in here is new to you" — so
-- opening the one changed plan clears both. A plan put away never lights the
-- category dot (it is put away quietly). planning_category_seen stays, and
-- mark_planning_category_seen still answers older apps, but neither decides
-- a dot any more. Grants in 20261018170010.

CREATE TABLE public.planning_entry_seen (
  entry_id        uuid NOT NULL,
  relationship_id uuid NOT NULL,
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  seen_at         timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (entry_id, user_id),
  CONSTRAINT planning_entry_seen_same_relationship
    FOREIGN KEY (entry_id, relationship_id)
    REFERENCES public.planning_entries(id, relationship_id) ON DELETE CASCADE
);
ALTER TABLE public.planning_entry_seen ENABLE ROW LEVEL SECURITY;

-- No dots at deploy: whoever had opened a category has seen its plans up to
-- then, exactly as the old category dot counted them.
INSERT INTO public.planning_entry_seen (entry_id, relationship_id, user_id, seen_at)
SELECT e.id, e.relationship_id, s.user_id, s.seen_at
FROM public.planning_category_seen s
JOIN public.planning_entries e
  ON e.category_id = s.category_id AND NOT e.is_template AND e.deleted_at IS NULL
ON CONFLICT (entry_id, user_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.planning_v2_entry_summary(p_entry_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'id', e.id, 'title', e.title, 'status', e.status, 'last_activity_at', e.last_activity_at,
    'pinned', e.pinned_at IS NOT NULL,
    'date_start', d.date_start, 'date_end', d.date_end,
    'checklist_done', coalesce(cl.done, 0), 'checklist_total', coalesce(cl.total, 0),
    -- New to the caller: their partner changed it after they last opened it.
    'has_new', coalesce(e.last_activity_by <> auth.uid()
                        AND e.last_activity_at > coalesce(sn.seen_at, '-infinity'::timestamptz), false))
  FROM public.planning_entries e
  LEFT JOIN public.planning_entry_seen sn ON sn.entry_id = e.id AND sn.user_id = auth.uid()
  LEFT JOIN LATERAL (
    SELECT b.date_start, b.date_end FROM public.planning_blocks b
    WHERE b.entry_id = e.id AND b.deleted_at IS NULL AND b.block_type = 'date' AND b.date_start IS NOT NULL
    ORDER BY b.sort_key, b.id LIMIT 1) d ON true
  LEFT JOIN LATERAL (
    SELECT count(*) FILTER (WHERE i.checked_at IS NOT NULL) AS done, count(*) AS total
    FROM public.planning_block_items i JOIN public.planning_blocks b ON b.id = i.block_id
    WHERE b.entry_id = e.id AND b.block_type = 'checklist' AND b.deleted_at IS NULL AND i.deleted_at IS NULL) cl ON true
  WHERE e.id = p_entry_id;
$$;

-- Opening a plan marks it seen for the caller.
CREATE OR REPLACE FUNCTION public.get_planning_entry(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rel      uuid;
  v_template boolean;
  v_actor    uuid;
BEGIN
  SELECT relationship_id, is_template INTO v_rel, v_template
  FROM public.planning_entries WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_actor := public.planning_v2_actor(v_rel);
  IF NOT v_template THEN
    INSERT INTO public.planning_entry_seen (entry_id, relationship_id, user_id, seen_at)
    VALUES (p_id, v_rel, v_actor, clock_timestamp())
    ON CONFLICT (entry_id, user_id) DO UPDATE SET seen_at = EXCLUDED.seen_at;
  END IF;
  RETURN public.planning_v2_entry_detail(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_planning_home(p_relationship_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_actor  uuid := public.planning_v2_actor(p_relationship_id);
  v_result jsonb;
BEGIN
  PERFORM public.planning_v2_ensure_starters(p_relationship_id);
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'seed_key', c.seed_key, 'name', c.name, 'icon', c.icon,
           'color', c.color, 'sort_key', c.sort_key, 'hidden', c.hidden_at IS NOT NULL,
           'template_entry_id', t.id,
           'entry_count', coalesce(e.cnt, 0),
           'has_new', coalesce(e.any_new, false)
         ) ORDER BY c.sort_key, c.id), '[]'::jsonb)
    INTO v_result
  FROM public.planning_categories c
  LEFT JOIN public.planning_entries t
         ON t.category_id = c.id AND t.is_template AND t.deleted_at IS NULL
  LEFT JOIN LATERAL (
    SELECT count(*) AS cnt,
           -- A plan in here is new to the caller; put-away plans stay quiet.
           bool_or(x.status <> 'archived'
                   AND x.last_activity_by <> v_actor
                   AND x.last_activity_at > coalesce(sn.seen_at, '-infinity'::timestamptz)) AS any_new
    FROM public.planning_entries x
    LEFT JOIN public.planning_entry_seen sn ON sn.entry_id = x.id AND sn.user_id = v_actor
    WHERE x.category_id = c.id AND NOT x.is_template AND x.deleted_at IS NULL
  ) e ON true
  WHERE c.relationship_id = p_relationship_id AND c.deleted_at IS NULL
    AND (c.seed_key IS DISTINCT FROM 'everyday' OR coalesce(e.cnt, 0) > 0);
  RETURN jsonb_build_object('categories', v_result);
END;
$$;
