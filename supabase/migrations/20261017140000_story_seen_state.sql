-- supabase/migrations/20261017140000_story_seen_state.sql
--
-- Story seen-state under "Show when we've seen things" (Spec 1a Task 4;
-- research 06 §3 F4 (1)).
--
-- story_items.has_been_viewed did two jobs (the viewer's own "new/seen" ring
-- and the author's "my partner saw it"), and the list RPCs were SECURITY
-- INVOKER returning si.*, so the author read it on their own rows. The
-- first view also bumped story_change_signals, which the author's client
-- subscribes to -- the moment of the view leaked even with the column hidden.
--
-- Now:
--   * has_been_viewed stays the viewer's state. A new seen_shown is the
--     author-facing boolean, set on the first view ONLY while the couple's
--     setting is on. Neither column is client-selectable (20261017140100);
--     the list RPCs become SECURITY DEFINER, inline the former RLS predicate,
--     and return has_been_viewed = (effective AND seen_shown) on the caller's
--     own items, has_been_viewed as stored on the partner's, and seen_shown
--     = false always.
--   * mark_story_viewed bumps the signal only while on. The viewer's own
--     client refreshes its ring locally after a view (story_reel_screen).
ALTER TABLE public.story_items ADD COLUMN IF NOT EXISTS seen_shown boolean NOT NULL DEFAULT false;

-- Couples that keep today's behaviour keep today's seen marks.
UPDATE public.story_items si
   SET seen_shown = true
 WHERE si.has_been_viewed
   AND NOT si.seen_shown
   AND public.seen_receipts_effective(si.relationship_id);

CREATE OR REPLACE FUNCTION public.list_active_story_items(
  p_relationship_id   uuid,
  p_author_id         uuid,
  p_after_created_at  timestamptz DEFAULT NULL,
  p_after_id          uuid DEFAULT NULL,
  p_limit             int DEFAULT 50
)
RETURNS SETOF public.story_items
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (jsonb_populate_record(si, jsonb_build_object(
            'has_been_viewed',
              CASE WHEN si.author_id = auth.uid() THEN (s.v_on AND si.seen_shown)
                   ELSE si.has_been_viewed END,
            'seen_shown', false))).*
    FROM public.story_items si
   CROSS JOIN (SELECT public.seen_receipts_effective(p_relationship_id) AS v_on) s
   WHERE si.relationship_id = p_relationship_id
     AND si.author_id = p_author_id
     AND si.deleted_at IS NULL
     AND public.story_relationship_is_open(si.relationship_id, auth.uid())
     AND si.expires_at > now()
     AND (
       p_after_created_at IS NULL
       OR (si.created_at, si.id) > (p_after_created_at, p_after_id)
     )
   ORDER BY si.created_at ASC, si.id ASC
   LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 50)
$$;

CREATE OR REPLACE FUNCTION public.list_story_day_items(
  p_relationship_id   uuid,
  p_occurred_on       date,
  p_after_created_at  timestamptz DEFAULT NULL,
  p_after_id          uuid DEFAULT NULL,
  p_limit             int DEFAULT 50
)
RETURNS SETOF public.story_items
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (jsonb_populate_record(si, jsonb_build_object(
            'has_been_viewed',
              CASE WHEN si.author_id = auth.uid() THEN (s.v_on AND si.seen_shown)
                   ELSE si.has_been_viewed END,
            'seen_shown', false))).*
    FROM public.story_items si
   CROSS JOIN (SELECT public.seen_receipts_effective(p_relationship_id) AS v_on) s
   WHERE si.relationship_id = p_relationship_id
     AND si.occurred_on = p_occurred_on
     AND si.deleted_at IS NULL
     AND public.story_relationship_is_open(si.relationship_id, auth.uid())
     AND (
       p_after_created_at IS NULL
       OR (si.created_at, si.id) > (p_after_created_at, p_after_id)
     )
   ORDER BY si.created_at ASC, si.id ASC
   LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 50)
$$;

-- Viewer-side only (unviewed_count already excludes the caller's own items),
-- but it reads has_been_viewed, which the client role can no longer select.
CREATE OR REPLACE FUNCTION public.get_story_ring_summary(
  p_relationship_id uuid
)
RETURNS TABLE (
  author_id             uuid,
  active_count          bigint,
  unviewed_count        bigint,
  newest_thumbnail_key  text,
  newest_created_at     timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    si.author_id,
    count(*) AS active_count,
    count(*) FILTER (
      WHERE si.author_id <> auth.uid() AND NOT si.has_been_viewed
    ) AS unviewed_count,
    (array_agg(si.thumbnail_key ORDER BY si.created_at DESC))[1]
      AS newest_thumbnail_key,
    max(si.created_at) AS newest_created_at
  FROM public.story_items si
 WHERE si.relationship_id = p_relationship_id
   AND si.deleted_at IS NULL
   AND public.story_relationship_is_open(p_relationship_id, auth.uid())
   AND si.expires_at > now()
 GROUP BY si.author_id
$$;

CREATE OR REPLACE FUNCTION public.mark_story_viewed(
  p_story_item_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user  uuid := auth.uid();
  v_story public.story_items%ROWTYPE;
  v_inserted boolean;
  v_on boolean;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.story_intent_error('UNAUTHORIZED');
  END IF;

  IF p_story_item_id IS NULL THEN
    RETURN public.story_intent_error('INVALID_INPUT');
  END IF;

  SELECT * INTO v_story
    FROM public.story_items
   WHERE id = p_story_item_id
   FOR UPDATE;

  IF v_story.id IS NULL
     OR v_story.deleted_at IS NOT NULL
     OR v_story.author_id IS NOT DISTINCT FROM v_user
     OR v_story.expires_at <= now()
     OR NOT public.story_relationship_is_open(v_story.relationship_id, v_user)
  THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;

  INSERT INTO public.story_views (story_item_id, viewer_id)
  VALUES (p_story_item_id, v_user)
  ON CONFLICT (story_item_id, viewer_id) DO NOTHING;
  v_inserted := FOUND;

  IF v_inserted THEN
    v_on := public.seen_receipts_effective(v_story.relationship_id);
    -- The viewer's own state always; the author-facing mark only while on.
    UPDATE public.story_items
       SET has_been_viewed = true,
           seen_shown = seen_shown OR v_on
     WHERE id = p_story_item_id;
    -- The author's client listens to this signal, so while off a view must
    -- not move it (Spec 1a; spec1-map-f4 §0.4).
    IF v_on THEN
      PERFORM public.bump_story_signal(v_story.relationship_id);
    END IF;
  END IF;

  RETURN jsonb_build_object('error', false, 'viewed', true);
END;
$$;
