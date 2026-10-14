-- Together Phase 5: a private calendar link per person (spec §6.4, §3.8–3.9;
-- plan R1–R5, R7). Only the token's hash is kept; the feed is read by the
-- calendar-feed edge function with the service role.

CREATE TABLE public.calendar_feed_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz
);
CREATE UNIQUE INDEX calendar_feed_tokens_one_live
  ON public.calendar_feed_tokens (user_id) WHERE revoked_at IS NULL;
ALTER TABLE public.calendar_feed_tokens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.calendar_feed_tokens FROM PUBLIC, anon, authenticated;

-- My active couple, if any.
CREATE FUNCTION public.together_active_relationship(p_user uuid) RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT r.id FROM public.relationships r
  WHERE r.status = 'active' AND r.chat_archived_at IS NULL
    AND (r.user_a = p_user OR r.user_b = p_user)
  ORDER BY r.started_at DESC NULLS LAST
  LIMIT 1
$$;
REVOKE ALL ON FUNCTION public.together_active_relationship(uuid) FROM PUBLIC, anon, authenticated;

-- A new link (shown once); any older one stops working (R3).
CREATE FUNCTION public.create_calendar_feed_token()
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_me uuid := auth.uid(); v_token text;
BEGIN
  IF v_me IS NULL THEN PERFORM public.together_fail('unauthenticated'); END IF;
  IF public.together_active_relationship(v_me) IS NULL THEN PERFORM public.together_fail('not_found'); END IF;
  PERFORM pg_advisory_xact_lock(hashtext('calendar_feed:' || v_me::text));
  UPDATE public.calendar_feed_tokens SET revoked_at = now() WHERE user_id = v_me AND revoked_at IS NULL;
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  INSERT INTO public.calendar_feed_tokens (user_id, token_hash)
  VALUES (v_me, encode(sha256(convert_to(v_token, 'UTF8')), 'hex'));
  RETURN v_token;
END;
$$;

CREATE FUNCTION public.revoke_calendar_feed()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_me uuid := auth.uid();
BEGIN
  IF v_me IS NULL THEN PERFORM public.together_fail('unauthenticated'); END IF;
  UPDATE public.calendar_feed_tokens SET revoked_at = now() WHERE user_id = v_me AND revoked_at IS NULL;
END;
$$;

CREATE FUNCTION public.get_calendar_feed_status()
RETURNS TABLE (is_active boolean, since timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE v_me uuid := auth.uid();
BEGIN
  IF v_me IS NULL THEN PERFORM public.together_fail('unauthenticated'); END IF;
  RETURN QUERY
  SELECT EXISTS (SELECT 1 FROM public.calendar_feed_tokens t WHERE t.user_id = v_me AND t.revoked_at IS NULL),
         (SELECT t.created_at FROM public.calendar_feed_tokens t WHERE t.user_id = v_me AND t.revoked_at IS NULL);
END;
$$;

-- The feed: what this person would see in the app, 30 days back to 180 ahead,
-- one entry per occurrence (R1, R2). NULL when there's nothing to serve (R5).
CREATE FUNCTION public.together_calendar_feed(p_token_hash text, p_today date DEFAULT current_date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user uuid; v_rel uuid;
BEGIN
  SELECT t.user_id INTO v_user FROM public.calendar_feed_tokens t
  WHERE t.token_hash = p_token_hash AND t.revoked_at IS NULL;
  IF v_user IS NULL THEN RETURN NULL; END IF;
  v_rel := public.together_active_relationship(v_user);
  IF v_rel IS NULL THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('items', coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'kind', i.item_kind, 'id', i.item_id, 'date', i.item_date,
      'starts_at', i.starts_at, 'ends_at', i.ends_at, 'all_day', i.all_day,
      'title', i.title, 'note', i.source_ref->>'note', 'location', i.source_ref->>'location_name',
      'recurring', coalesce(ce.rrule IS NOT NULL, false),
      'continuation', coalesce((i.source_ref->>'continuation')::boolean, false))
      ORDER BY i.item_date, i.starts_at NULLS FIRST, i.title)
    FROM public.together_items_for(v_user, v_rel, p_today - 30, p_today + 180) i
    LEFT JOIN public.couple_events ce ON i.item_kind = 'event' AND ce.id = i.item_id
    WHERE i.item_kind IN ('event', 'reminder', 'planning_date')
  ), '[]'::jsonb));
END;
$$;

-- Ending a couple (any path) ends both partners' links (R4, spec §3.8).
CREATE FUNCTION public.together_revoke_feeds_on_end() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF (OLD.status = 'active' AND NEW.status <> 'active')
     OR (OLD.chat_archived_at IS NULL AND NEW.chat_archived_at IS NOT NULL) THEN
    UPDATE public.calendar_feed_tokens SET revoked_at = now()
    WHERE revoked_at IS NULL AND user_id IN (OLD.user_a, OLD.user_b);
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trigger_together_revoke_feeds ON public.relationships;
CREATE TRIGGER trigger_together_revoke_feeds
  AFTER UPDATE OF status, chat_archived_at ON public.relationships
  FOR EACH ROW EXECUTE FUNCTION public.together_revoke_feeds_on_end();

REVOKE ALL ON FUNCTION public.create_calendar_feed_token() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.revoke_calendar_feed() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_calendar_feed_status() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.together_calendar_feed(text, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_calendar_feed_token() TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_calendar_feed() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_calendar_feed_status() TO authenticated;
GRANT EXECUTE ON FUNCTION public.together_calendar_feed(text, date) TO service_role;
