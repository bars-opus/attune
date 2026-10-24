-- supabase/migrations/20261024100700_story_export_order.sql
--
-- Stories Wave 5 (review 04 #1, #12; 07b V8/G8):
--   * The media walk sorted by bucket name, so story-media came after
--     journal, message and planning media, behind a 12-part cap. Stories are
--     the one class with no copy on the phone, and after an ending export is
--     their only way out. They now come first: the walk is ordered by
--     (export_media_rank(bucket), bucket, name). The rank is a function of the
--     bucket, so the job's (bucket, name) cursor still marks a unique place.
--   * Story videos and photos under 24 hours had no extension (keys end in
--     -media). Their names now come from media_type: .mp4 or .jpg, in
--     data.json and in the ZIP alike.
--   * A job already part-way through the media walk in the old order would
--     skip every story under the new one. Such jobs are replaced by a fresh
--     job (the old one fails 'restarted' and its parts are dropped); jobs not
--     yet in the media walk are re-labelled. data_export_jobs.media_order
--     records which walk a job uses, which keeps this idempotent.
-- One transaction, so no job is claimed between the new order and the restart.
BEGIN;

-- The ALTER TABLE below takes an ACCESS EXCLUSIVE lock on data_export_jobs:
-- give up rather than queue new export requests and claims behind an
-- in-flight build. On a timeout the whole file rolls back; re-run the push.
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.export_media_rank(p_bucket text)
RETURNS int LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT CASE WHEN p_bucket = 'story-media' THEN 0 ELSE 1 END;
$$;

CREATE OR REPLACE FUNCTION public.export_story_file_name(p_media_key text, p_media_type text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT 'my_stories/' || left(md5(p_media_key), 16)
         || CASE WHEN p_media_type = 'video' THEN '.mp4' ELSE '.jpg' END;
$$;

REVOKE ALL ON FUNCTION public.export_media_rank(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.export_story_file_name(text, text) FROM PUBLIC, anon, authenticated;

ALTER TABLE public.data_export_jobs ADD COLUMN IF NOT EXISTS media_order smallint NOT NULL DEFAULT 1;
ALTER TABLE public.data_export_jobs ALTER COLUMN media_order SET DEFAULT 2;

-- export_relationship restated from 20261018120000 with one change: a story's
-- media_file comes from export_story_file_name, so data.json and the ZIP agree.
CREATE OR REPLACE FUNCTION public.export_relationship(p_user_id uuid, p_relationship_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_rel public.relationships;
  v_i_am_a boolean;
  v_out jsonb;
  v_start date;
BEGIN
  -- Only a relationship the person is in (re-review M6: callers are the
  -- worker's, but the ids are never trusted).
  SELECT * INTO v_rel FROM public.relationships
  WHERE id = p_relationship_id AND p_user_id IN (user_a, user_b);
  IF NOT FOUND THEN RETURN '{}'::jsonb; END IF;
  v_i_am_a := v_rel.user_a = p_user_id;
  v_start := least(v_rel.created_at::date, coalesce(v_rel.started_at, v_rel.created_at::date));

  v_out := jsonb_build_object(
    'status', v_rel.status,
    'started_on', v_rel.started_at,
    'ended_at', v_rel.ended_at,
    'partner_first_name', (
      SELECT CASE WHEN split_part(btrim(u.display_name), ' ', 1) ~ '^\+?[0-9 ()-]*$' THEN NULL
                  ELSE split_part(btrim(u.display_name), ' ', 1) END
      FROM public.users u
      WHERE u.id = CASE WHEN v_i_am_a THEN v_rel.user_b ELSE v_rel.user_a END),

    -- Chat is paged separately (export_chat_page): a long history must
    -- not be one statement or one in-memory value (plan review I7).
    'chat_messages', (SELECT count(*) FROM public.messages m
                      WHERE m.relationship_id = p_relationship_id AND NOT m.is_system_notice
                        AND coalesce(m.media_type, '') <> 'streak'),

    'places', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'from', public.export_who(p_user_id, pu.user_id), 'at', pu.created_at,
        'label', pu.label, 'note', pu.note, 'city', pu.city, 'country', pu.country,
        -- The partner's exact spots over time would be a location history of
        -- them: their pins keep only the place names (plan review I2).
        'latitude', CASE WHEN pu.user_id = p_user_id THEN pu.latitude END,
        'longitude', CASE WHEN pu.user_id = p_user_id THEN pu.longitude END) ORDER BY pu.created_at)
      FROM public.place_updates pu WHERE pu.relationship_id = p_relationship_id
    ), '[]'::jsonb),

    -- Planning: entries, blocks, items. Templates and deleted rows out;
    -- expenses as a flat per-entry list, no totals (D.2, D6).
    'planning', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'title', e.title, 'status', e.status, 'currency', e.currency,
        'created_by', public.export_who(p_user_id, e.created_by), 'created_at', e.created_at,
        'blocks', coalesce((
          SELECT jsonb_agg(jsonb_build_object(
            'type', b.block_type, 'text', b.plain_text,
            'date_start', b.date_start, 'date_end', b.date_end,
            'photos', CASE WHEN b.block_type = 'photo' THEN (
              SELECT jsonb_agg('media/' || public.export_file_name('planning', x.path))
              FROM jsonb_array_elements_text(coalesce(b.payload->'paths', '[]'::jsonb)) AS x(path)) END,
            'url', CASE WHEN b.block_type = 'link' THEN b.payload->>'url' END,
            'created_by', public.export_who(p_user_id, b.created_by),
            'items', coalesce((
              SELECT jsonb_agg(jsonb_build_object(
                'text', it.text, 'section', it.section, 'done', it.checked_at IS NOT NULL,
                'due', it.due_date, 'amount_minor', it.amount_minor, 'currency', it.currency,
                'paid_by', public.export_who(p_user_id, it.paid_by),
                'assigned_to', public.export_who(p_user_id, it.assigned_to),
                'date_start', it.date_start, 'date_end', it.date_end) ORDER BY it.sort_key)
              FROM public.planning_block_items it
              WHERE it.block_id = b.id AND it.deleted_at IS NULL), '[]'::jsonb)
          ) ORDER BY b.sort_key)
          FROM public.planning_blocks b
          WHERE b.entry_id = e.id AND b.deleted_at IS NULL), '[]'::jsonb)
      ) ORDER BY e.created_at)
      FROM public.planning_entries e
      WHERE e.relationship_id = p_relationship_id AND e.deleted_at IS NULL AND NOT e.is_template
    ), '[]'::jsonb),

    -- Calendar: exactly what the person sees (their private items, shared
    -- items, "Busy" for the partner's busy-only; never the partner's private).
    -- Events the person created or that were shared with them (D.2): never
    -- the partner's private or busy-only items (plan review I3). The whole
    -- relationship, not a window (D.3 #5).
    'calendar', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'kind', t.item_kind, 'id', 'c' || t.rank_id, 'date', t.item_date,
        'starts_at', t.starts_at, 'ends_at', t.ends_at, 'all_day', t.all_day,
        'title', t.title, 'visibility', t.visibility,
        'note', t.note, 'location', t.location,
        'recurring', t.recurring, 'continuation', t.continuation,
        'created_by', public.export_who(p_user_id, t.created_by)) ORDER BY t.item_date)
      FROM (
        SELECT ti.*,
               dense_rank() OVER (ORDER BY ti.item_kind, ti.item_id) AS rank_id,
               CASE WHEN ti.item_kind = 'event' THEN ce.note END AS note,
               CASE WHEN ti.item_kind = 'event' THEN ce.location_name END AS location,
               coalesce(ce.rrule IS NOT NULL OR ce.ritual_id IS NOT NULL, false) AS recurring,
               coalesce(NOT ti.all_day AND ti.starts_at IS NOT NULL
                 AND ti.item_date > (ti.starts_at AT TIME ZONE coalesce(ti.tz, 'UTC'))::date, false) AS continuation
        FROM public.together_items_for(p_user_id, p_relationship_id, v_start, current_date + 365) ti
        LEFT JOIN public.couple_events ce ON ti.item_kind = 'event' AND ce.id = ti.item_id
        WHERE ti.item_kind IN ('event', 'reminder', 'planning_date')
          AND NOT (ti.visibility = 'busy_only' AND ti.created_by IS DISTINCT FROM p_user_id)
      ) t
    ), '[]'::jsonb),

    'reminders', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'type', r.reminder_type, 'title', r.title, 'note', r.note,
        'remind_at', r.remind_at, 'recurrence', r.recurrence) ORDER BY r.remind_at)
      FROM public.reminders r WHERE r.relationship_id = p_relationship_id
    ), '[]'::jsonb),

    'family', coalesce((
      SELECT jsonb_agg(jsonb_build_object('name', f.name, 'birthday', f.birthday) ORDER BY f.name)
      FROM public.couple_family_members f WHERE f.relationship_id = p_relationship_id
    ), '[]'::jsonb),

    'moments', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'type', t.event_type, 'title', t.title, 'note', t.note, 'on', t.occurred_at,
        'logged_by', public.export_who(p_user_id, t.logged_by),
        -- Spec 7 (B2; review I6): shared through "Share a win".
        'win', CASE WHEN t.is_win THEN true END) ORDER BY t.occurred_at)
      FROM public.timeline_events t
      WHERE t.relationship_id = p_relationship_id AND t.deleted_at IS NULL
        AND (t.visibility = 'shared' OR t.logged_by = p_user_id)
    ), '[]'::jsonb),

    -- The person's own stories only (the partner's are not exportable).
    'my_stories', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'type', s.media_type, 'on', s.occurred_on, 'at', s.created_at,
        'media_file', 'media/' || public.export_story_file_name(s.media_key, s.media_type),
        'place', (SELECT jsonb_build_object('label', sp.label, 'latitude', sp.lat, 'longitude', sp.lng)
                  FROM public.story_places sp WHERE sp.story_item_id = s.id)) ORDER BY s.created_at)
      FROM public.story_items s
      WHERE s.relationship_id = p_relationship_id AND s.author_id = p_user_id AND s.deleted_at IS NULL
    ), '[]'::jsonb),

    -- Shared Pulse history and verdicts (both already saw them); role-free.
    'pulse', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'week_ending', ps.week_ending, 'overall', ps.overall_score,
        'communication', ps.communication, 'connection', ps.connection,
        'conflict_health', ps.conflict_health, 'alignment', ps.alignment,
        'confidence', ps.data_confidence) ORDER BY ps.week_ending)
      FROM public.pulse_scores ps WHERE ps.relationship_id = p_relationship_id
    ), '[]'::jsonb),
    'verdicts', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'period_start', v.period_start, 'period_end', v.period_end,
        'headline', v.headline,
        'strengths', (SELECT jsonb_agg(jsonb_build_object('title', x->>'title', 'body', x->>'body'))
                      FROM jsonb_array_elements(coalesce(v.strengths, '[]'::jsonb)) x),
        'watch_areas', (SELECT jsonb_agg(jsonb_build_object('title', x->>'title', 'body', x->>'body'))
                        FROM jsonb_array_elements(coalesce(v.watch_areas, '[]'::jsonb)) x),
        'one_action', v.one_action, 'disclaimer', v.disclaimer) ORDER BY v.period_start)
      FROM public.verdicts v WHERE v.relationship_id = p_relationship_id AND v.status = 'published'
    ), '[]'::jsonb),

    -- Games: the person's own answers always; the partner's only once the
    -- round revealed them (both answered).
    'game_rounds', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'game', coalesce(gs.game_type, r.game_type, 'love_map'),
        'question', r.question_text_snapshot,
        'at', r.created_at,
        'my_answer', CASE WHEN v_i_am_a THEN r.answer_a ELSE r.answer_b END,
        'partner_answer', CASE WHEN r.both_answered THEN
                            CASE WHEN v_i_am_a THEN r.answer_b ELSE r.answer_a END END) ORDER BY r.created_at)
      FROM public.game_session_rounds r
      LEFT JOIN public.game_sessions gs ON gs.id = r.session_id
      WHERE coalesce(r.relationship_id, gs.relationship_id) = p_relationship_id
        AND (r.answer_a IS NOT NULL OR r.answer_b IS NOT NULL)
    ), '[]'::jsonb),
    'thirty_six_answers', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'question', r.question_text_snapshot,
        'from', public.export_who(p_user_id, a.user_id),
        'answer', a.answer_text, 'at', a.submitted_at) ORDER BY a.submitted_at)
      FROM public.thirty_six_question_answers a
      JOIN public.game_session_rounds r ON r.id = a.round_id
      JOIN public.game_sessions gs ON gs.id = r.session_id
      WHERE gs.relationship_id = p_relationship_id AND NOT coalesce(a.is_removed, false)
        AND (a.user_id = p_user_id OR r.both_answered)
    ), '[]'::jsonb),
    -- The person's own This-or-That picks (plan review M3).
    'this_or_that_picks', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'question', r.question_text_snapshot, 'picked', a.choice, 'at', r.created_at) ORDER BY r.created_at)
      FROM public.this_or_that_round_answers a
      JOIN public.game_session_rounds r ON r.id = a.round_id
      JOIN public.game_sessions gs ON gs.id = r.session_id
      WHERE gs.relationship_id = p_relationship_id AND a.user_id = p_user_id
    ), '[]'::jsonb),
    'love_map_truths', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'about', public.export_who(p_user_id, t.subject_id), 'truth', t.truth_text))
      FROM public.mirror_round_truth t
      JOIN public.game_session_rounds r ON r.id = t.round_id
      LEFT JOIN public.game_sessions gs ON gs.id = r.session_id
      WHERE coalesce(r.relationship_id, gs.relationship_id) = p_relationship_id
        AND (t.subject_id = p_user_id OR r.both_answered)
    ), '[]'::jsonb)
  );
  RETURN v_out;
END;
$$;

CREATE OR REPLACE FUNCTION public.export_media_manifest(
  p_user_id uuid, p_relationship_ids uuid[] DEFAULT NULL,
  p_after_bucket text DEFAULT NULL, p_after_name text DEFAULT NULL, p_limit integer DEFAULT NULL
)
RETURNS TABLE (bucket text, object_name text, zip_path text, size_bytes bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  WITH rels AS (
    SELECT r.id
    FROM unnest(coalesce(p_relationship_ids, public.export_open_relationships(p_user_id))) AS x(id)
    JOIN public.relationships r ON r.id = x.id AND p_user_id IN (r.user_a, r.user_b)
  ),
  wanted (bucket, object_name, zip_path) AS (
    SELECT 'message-media', m.media_url, 'media/' || public.export_file_name('chat', m.media_url)
    FROM public.messages m JOIN rels ON rels.id = m.relationship_id
    WHERE m.media_url IS NOT NULL AND m.deleted_at IS NULL AND NOT m.is_view_once
      AND m.media_type IN ('image', 'audio', 'video')
    UNION ALL
    SELECT 'story-media', s.media_key, 'media/' || public.export_story_file_name(s.media_key, s.media_type)
    FROM public.story_items s JOIN rels ON rels.id = s.relationship_id
    WHERE s.author_id = p_user_id AND s.deleted_at IS NULL AND s.media_key IS NOT NULL
    UNION ALL
    SELECT 'planning-media', x.path, 'media/' || public.export_file_name('planning', x.path)
    FROM public.planning_blocks b
    JOIN rels ON rels.id = b.relationship_id
    JOIN public.planning_entries e ON e.id = b.entry_id AND e.deleted_at IS NULL AND NOT e.is_template
    CROSS JOIN LATERAL jsonb_array_elements_text(coalesce(b.payload->'paths', '[]'::jsonb)) AS x(path)
    WHERE b.block_type = 'photo' AND b.deleted_at IS NULL
    UNION ALL
    SELECT 'journal-media', b.payload->>'path', 'media/' || public.export_file_name('journal', b.payload->>'path')
    FROM public.reflection_journal_blocks b
    JOIN public.reflection_journal_entries e ON e.id = b.entry_id AND e.deleted_at IS NULL
    WHERE b.user_id = p_user_id AND b.kind = 'photo' AND b.payload->>'path' IS NOT NULL
  )
  -- Stories first (Wave 5); sizes from storage, so the worker can plan the
  -- download before fetching.
  SELECT d.bucket, d.object_name, d.zip_path, d.size_bytes FROM (
    SELECT DISTINCT ON (w.bucket, w.object_name) w.bucket, w.object_name, w.zip_path,
           nullif(o.metadata->>'size', '')::bigint AS size_bytes
    FROM wanted w
    LEFT JOIN storage.objects o ON o.bucket_id = w.bucket AND o.name = w.object_name
    WHERE p_after_bucket IS NULL
       OR (public.export_media_rank(w.bucket), w.bucket, w.object_name)
          > (public.export_media_rank(p_after_bucket), p_after_bucket, p_after_name)
    ORDER BY w.bucket, w.object_name
  ) d
  ORDER BY public.export_media_rank(d.bucket), d.bucket, d.object_name
  LIMIT p_limit;
$$;

-- export_next_allowed restated from 20261018120000: a job this migration
-- failed as 'restarted' was the system's doing, so it counts neither for the
-- hour's pause nor toward three a day (review M3).
CREATE OR REPLACE FUNCTION public.export_next_allowed(p_user_id uuid)
RETURNS timestamptz LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT nullif(greatest(
    coalesce((SELECT max(j.requested_at) + interval '24 hours' FROM public.data_export_jobs j
              WHERE j.user_id = p_user_id AND j.status = 'ready'), '-infinity'),
    coalesce((SELECT max(j.requested_at) + interval '1 hour' FROM public.data_export_jobs j
              WHERE j.user_id = p_user_id AND j.status = 'failed'
                AND j.error IS DISTINCT FROM 'restarted'), '-infinity'),
    -- Three in the last day: allowed again when the oldest of the newest
    -- three is a day old (re-review M1).
    coalesce((SELECT j.requested_at + interval '24 hours' FROM public.data_export_jobs j
              WHERE j.user_id = p_user_id AND j.requested_at > now() - interval '24 hours'
                AND NOT (j.status = 'failed' AND j.error IS NOT DISTINCT FROM 'restarted')
              ORDER BY j.requested_at DESC OFFSET 2 LIMIT 1), '-infinity')
  ), '-infinity'::timestamptz);
$$;

REVOKE ALL ON FUNCTION public.export_next_allowed(uuid) FROM PUBLIC, anon, authenticated;

-- In-flight jobs built in the old order start again; a job not yet started
-- takes the new walk.
CREATE OR REPLACE FUNCTION public.export_restart_old_order_jobs()
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v record;
  v_n int := 0;
BEGIN
  FOR v IN
    SELECT j.id, j.user_id
      FROM public.data_export_jobs j
     WHERE j.media_order = 1
       AND j.status IN ('queued', 'building')
       -- Every job but one not yet started: past the data part, data.json
       -- named story files without extensions; building now, a live worker
       -- run may hold an old-order data.json or media list (review M1).
       AND NOT (j.status = 'queued' AND j.phase = 'data')
     ORDER BY j.requested_at
       FOR UPDATE
  LOOP
    UPDATE public.data_export_jobs SET status = 'failed', error = 'restarted' WHERE id = v.id;
    PERFORM public.export_drop_files(v.id);
    -- relationship_ids NULL: the first claim takes a fresh snapshot, so a
    -- chapter whose window closed meanwhile is not exported (review M5).
    INSERT INTO public.data_export_jobs (user_id, relationship_ids, media_order)
    VALUES (v.user_id, NULL, 2);
    v_n := v_n + 1;
  END LOOP;
  UPDATE public.data_export_jobs j SET media_order = 2
   WHERE j.media_order = 1 AND j.status IN ('queued', 'building');
  RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION public.export_restart_old_order_jobs() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.export_restart_old_order_jobs() TO service_role;

SELECT public.export_restart_old_order_jobs();

COMMIT;
