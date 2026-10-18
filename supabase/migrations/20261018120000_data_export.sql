-- Spec 3c (research 06 §3 F1 (5); 05 D.2 Export column, D.3 #5, #6):
-- "Download what's yours". export_bundle(user) is the single source of
-- truth for what a download contains; export_media_manifest(user) lists the
-- storage objects that go with it. A relationship's data is included only
-- while that person can still read it (relationship_chat_open_for);
-- personal classes always. Never: AI judgement, role attribution, safety
-- data, translator originals (none are stored), partner ids.
-- Plan: docs/superpowers/plans/2026-10-18-spec3c-export.md.

-- 'me' / 'partner' instead of a user id.
CREATE OR REPLACE FUNCTION public.export_who(p_me uuid, p_id uuid)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT CASE WHEN p_id IS NULL THEN NULL WHEN p_id = p_me THEN 'me' ELSE 'partner' END;
$$;

-- A ZIP-relative file name with no id in it: a short hash of the object
-- name, its extension kept (plan review I1).
CREATE OR REPLACE FUNCTION public.export_file_name(p_folder text, p_object text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT p_folder || '/' || left(md5(p_object), 16)
         || coalesce('.' || nullif(substring(p_object from '\.([A-Za-z0-9]+)$'), ''), '');
$$;

-- One relationship's shared data, as the person can see it.
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
        'media_file', 'media/' || public.export_file_name('my_stories', s.media_key),
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

-- The relationships a download covers, in order: those the person can still
-- read. A job snapshots this list at its first claim, so every part of one
-- download numbers the same chapters the same way (final review I1).
CREATE OR REPLACE FUNCTION public.export_open_relationships(p_user_id uuid)
RETURNS uuid[] LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT coalesce(array_agg(r.id ORDER BY r.created_at), '{}')
  FROM public.relationships r
  WHERE p_user_id IN (r.user_a, r.user_b) AND public.relationship_chat_open_for(r.id, p_user_id);
$$;

CREATE OR REPLACE FUNCTION public.export_bundle(p_user_id uuid, p_relationship_ids uuid[] DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_rels jsonb := '[]'::jsonb;
  v_ids uuid[] := coalesce(p_relationship_ids, public.export_open_relationships(p_user_id));
  v_n int;
BEGIN
  FOR v_n IN 1 .. coalesce(array_length(v_ids, 1), 0) LOOP
    v_rels := v_rels || jsonb_build_array(
      jsonb_build_object('name', 'relationship-' || v_n, 'chat_folder', 'relationship-' || v_n || '/chat')
      || public.export_relationship(p_user_id, v_ids[v_n]));
  END LOOP;

  RETURN jsonb_build_object(
    'format', 'attune-export', 'version', 1, 'generated_at', now(),
    'relationships', v_rels,
    'personal', jsonb_build_object(
      -- Spec 7 (review I6): notes I kept (by ref, under the chapter they
      -- came from), the dates I hid, and a quiet state if one is on.
      'appreciation_jar', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'relationship', 'relationship-' || array_position(v_ids, m.relationship_id),
        'ref', left(md5(m.id::text), 12), 'text', m.content, 'saved_at', j.saved_at) ORDER BY j.saved_at)
        FROM public.appreciation_jar j JOIN public.messages m ON m.id = j.message_id
        WHERE j.user_id = p_user_id AND m.deleted_at IS NULL
          AND array_position(v_ids, m.relationship_id) IS NOT NULL), '[]'::jsonb),
      'hidden_periods', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'starts_on', h.starts_on, 'ends_on', h.ends_on) ORDER BY h.starts_on)
        FROM public.hidden_periods h WHERE h.user_id = p_user_id), '[]'::jsonb),
      'quiet_state', (SELECT jsonb_build_object('kind', q.kind, 'until', q.until)
        FROM public.quiet_states q WHERE q.user_id = p_user_id AND q.until > now()),
      -- Sync audit M-9: my own settings — my time zone, my own seen-receipt
      -- choice per chapter (never the partner's), my signed-in devices.
      'settings', jsonb_build_object(
        'timezone', (SELECT u.timezone FROM public.users u WHERE u.id = p_user_id),
        'seen_receipts', coalesce((SELECT jsonb_agg(jsonb_build_object(
            'relationship', 'relationship-' || array_position(v_ids, sp.relationship_id),
            'seen_on', sp.seen_on) ORDER BY array_position(v_ids, sp.relationship_id))
          FROM public.seen_receipt_prefs sp
          WHERE sp.user_id = p_user_id AND array_position(v_ids, sp.relationship_id) IS NOT NULL), '[]'::jsonb),
        'devices', coalesce((SELECT jsonb_agg(jsonb_build_object(
            'label', d.label, 'platform', d.platform, 'updated_at', d.updated_at) ORDER BY d.updated_at)
          FROM public.session_devices d WHERE d.user_id = p_user_id), '[]'::jsonb)),
      'insights', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'type', i.insight_type, 'text', i.insight_body, 'at', i.created_at) ORDER BY i.created_at)
        FROM public.personal_insights i WHERE i.user_id = p_user_id), '[]'::jsonb),
      -- Content-free by design: no translated text is ever stored.
      'translator_use', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'at', t.used_at, 'need', t.core_need_identified, 'chose_rewrite', t.chose_rewrite) ORDER BY t.used_at)
        FROM public.translator_logs t WHERE t.user_id = p_user_id), '[]'::jsonb),
      'weekly_checkins', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'week_ending', w.week_ending, 'communication', w.communication_rating,
        'connection', w.connection_rating, 'conflict_health', w.conflict_health_rating,
        'alignment', w.alignment_rating) ORDER BY w.week_ending)
        -- safety_rating is never exported (D.2: the safety check never is;
        -- plan review C1).
        FROM public.weekly_checkins w WHERE w.user_id = p_user_id), '[]'::jsonb),
      'journal', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'title', e.title, 'prompt', e.prompt_used, 'created_at', e.created_at,
        'blocks', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'kind', b.kind, 'text', b.plain_text,
          'photo', CASE WHEN b.kind = 'photo' AND b.payload->>'path' IS NOT NULL
                        THEN 'media/' || public.export_file_name('journal', b.payload->>'path') END) ORDER BY b.position)
          FROM public.reflection_journal_blocks b WHERE b.entry_id = e.id), '[]'::jsonb)) ORDER BY e.created_at)
        FROM public.reflection_journal_entries e WHERE e.user_id = p_user_id AND e.deleted_at IS NULL), '[]'::jsonb),
      'healing', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'breakup_at', h.breakup_at, 'reflection_answers', h.reflection_answers,
        'readiness_answers', (SELECT jsonb_agg(ra.answers ORDER BY ra.submitted_at)
                              FROM public.healing_readiness_attempts ra WHERE ra.journey_id = h.id)) ORDER BY h.created_at)
        FROM public.healing_journeys h WHERE h.user_id = p_user_id), '[]'::jsonb),
      'quiz_responses', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'quiz', q.quiz_type, 'answers', q.responses, 'result', q.result_type,
        'result_data', q.result_data, 'at', q.completed_at) ORDER BY q.completed_at)
        FROM public.quiz_responses q WHERE q.user_id = p_user_id), '[]'::jsonb),
      'profile', (SELECT jsonb_build_object(
        'attachment', p.attachment_style, 'love_languages', p.love_languages,
        'communication', p.communication_style, 'conflict', p.conflict_style)
        FROM public.psych_profiles p WHERE p.user_id = p_user_id),
      'profile_history', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'quiz', h.quiz_type, 'result', h.result_type, 'at', h.recorded_at) ORDER BY h.recorded_at)
        FROM public.psych_profile_history h WHERE h.user_id = p_user_id), '[]'::jsonb),
      'onboarding', (SELECT jsonb_build_object('answers', o.attachment_answers, 'anchors', o.anchors)
        FROM public.onboarding_profiles o WHERE o.user_id = p_user_id),
      'my_questions', coalesce((
        SELECT jsonb_agg(x) FROM (
          SELECT jsonb_build_object('game', 'this_or_that', 'question', c.question_text,
                                    'a', c.option_a, 'b', c.option_b) AS x
          FROM public.custom_this_or_that_questions c WHERE c.user_id = p_user_id
          UNION ALL
          SELECT jsonb_build_object('game', 'truth_or_dare', 'type', c.question_type, 'question', c.content)
          FROM public.custom_truth_or_dare_questions c WHERE c.user_id = p_user_id) q), '[]'::jsonb)
    )
  );
END;
$$;


-- One page of one relationship's chat, after a cursor (keyset paging: each
-- page is an index range, never a renumbering of the whole chat; final
-- review I2). Messages carry a short opaque ref, and a reply points at the
-- ref it answers -- never an id. No AI columns, no assistant payload, no
-- view-once text or media, no streaks, no system notices; a deleted message
-- is a tombstone (final review I7: a view-once message keeps no text, and
-- a reply quoting one keeps no quote).
CREATE OR REPLACE FUNCTION public.export_chat_page(
  p_user_id uuid, p_relationship_id uuid, p_after_at timestamptz, p_after_id uuid, p_limit integer
)
RETURNS TABLE (rows jsonb, last_at timestamptz, last_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  WITH page AS (
    SELECT m.* FROM public.messages m
    WHERE m.relationship_id = p_relationship_id
      AND p_user_id IN (SELECT unnest(ARRAY[r.user_a, r.user_b]) FROM public.relationships r WHERE r.id = p_relationship_id)
      AND NOT m.is_system_notice
      AND coalesce(m.media_type, '') <> 'streak'
      AND (p_after_at IS NULL OR (m.created_at, m.id) > (p_after_at, p_after_id))
    ORDER BY m.created_at, m.id
    LIMIT least(greatest(p_limit, 1), 5000)
  )
  SELECT
    coalesce(jsonb_agg(jsonb_build_object(
      'ref', left(md5(p.id::text), 12),
      'from', public.export_who(p_user_id, p.sender_id),
      'at', p.created_at,
      'text', CASE WHEN p.deleted_at IS NULL AND NOT p.is_view_once THEN p.content END,
      -- A quote only while the quoted message still exists and is not
      -- view-once (re-review M7).
      'quoted', CASE WHEN p.deleted_at IS NULL AND q.id IS NOT NULL AND NOT q.is_view_once THEN p.quoted_text END,
      'reply_to', CASE WHEN p.reply_to_message_id IS NOT NULL THEN left(md5(p.reply_to_message_id::text), 12) END,
      'media', CASE WHEN p.deleted_at IS NULL AND NOT p.is_view_once
                     AND p.media_type IN ('image', 'audio', 'video') THEN p.media_type END,
      'media_file', CASE WHEN p.deleted_at IS NULL AND NOT p.is_view_once AND p.media_url IS NOT NULL
                     AND p.media_type IN ('image', 'audio', 'video')
                     THEN 'media/' || public.export_file_name('chat', p.media_url) END,
      'view_once', CASE WHEN p.is_view_once THEN true END,
      'edited_at', p.edited_at,
      'deleted', CASE WHEN p.deleted_at IS NOT NULL THEN true END,
      'source', p.source,
      'from_attune_assist', CASE WHEN p.message_origin = 'attune_assist' THEN true END,
      -- Spec 7 (B1; review I6): an "I noticed…" note; Spec 8 (sync audit
      -- M-2): a pause and its fixed reply.
      'kind', CASE p.media_type WHEN 'appreciation' THEN 'i_noticed'
                                WHEN 'pause' THEN 'pause'
                                WHEN 'pause_reply' THEN 'pause_reply' END
    ) ORDER BY p.created_at, p.id), '[]'::jsonb),
    max(p.created_at),
    (array_agg(p.id ORDER BY p.created_at DESC, p.id DESC))[1]
  FROM page p
  LEFT JOIN public.messages q ON q.id = p.reply_to_message_id;
$$;

-- The storage objects that go with the bundle, and where they go in the ZIP.
-- Walked with a (bucket, object_name) cursor, not an offset, so a photo
-- added or deleted during the build never shifts the list (re-review M5).
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
    SELECT 'story-media', s.media_key, 'media/' || public.export_file_name('my_stories', s.media_key)
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
  -- Sizes from storage, so the worker can plan the download before fetching.
  SELECT d.* FROM (
    SELECT DISTINCT ON (w.bucket, w.object_name) w.bucket, w.object_name, w.zip_path,
           nullif(o.metadata->>'size', '')::bigint AS size_bytes
    FROM wanted w
    LEFT JOIN storage.objects o ON o.bucket_id = w.bucket AND o.name = w.object_name
    WHERE p_after_bucket IS NULL OR (w.bucket, w.object_name) > (p_after_bucket, p_after_name)
    ORDER BY w.bucket, w.object_name
  ) d
  ORDER BY d.bucket, d.object_name
  LIMIT p_limit;
$$;

-- ---------------------------------------------------------------------
-- Jobs, built in parts (final review C1): an edge function has about two
-- seconds of CPU, so one run builds one bounded part -- the data files, a
-- slice of chat, or about 40 MB of media -- and the next run carries on from
-- the recorded progress. Every part's file is queued for deletion BEFORE it
-- is uploaded (final review C2), so no archive can ever be orphaned.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.data_export_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'building', 'ready', 'failed')),
  requested_at timestamptz NOT NULL DEFAULT now(),
  claimed_at timestamptz,
  attempts int NOT NULL DEFAULT 0,
  ready_at timestamptz,
  expires_at timestamptz,
  storage_keys text[] NOT NULL DEFAULT '{}',
  error text,
  -- Progress between parts.
  relationship_ids uuid[],
  phase text NOT NULL DEFAULT 'data' CHECK (phase IN ('data', 'chat', 'media', 'done')),
  rel_index int NOT NULL DEFAULT 1,
  chat_after_at timestamptz,
  chat_after_id uuid,
  chat_page int NOT NULL DEFAULT 0,
  media_after_bucket text,
  media_after_name text,
  -- Errors on the current part; three and the job fails (re-review I2).
  part_failures int NOT NULL DEFAULT 0,
  left_out jsonb NOT NULL DEFAULT '[]'::jsonb
);
CREATE INDEX IF NOT EXISTS data_export_jobs_user_idx ON public.data_export_jobs (user_id, requested_at DESC);
CREATE INDEX IF NOT EXISTS data_export_jobs_queue_idx ON public.data_export_jobs (requested_at) WHERE status IN ('queued', 'building');
ALTER TABLE public.data_export_jobs ENABLE ROW LEVEL SECURITY;

-- When the person may ask for the next one (final review I4).
CREATE OR REPLACE FUNCTION public.export_next_allowed(p_user_id uuid)
RETURNS timestamptz LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT nullif(greatest(
    coalesce((SELECT max(j.requested_at) + interval '24 hours' FROM public.data_export_jobs j
              WHERE j.user_id = p_user_id AND j.status = 'ready'), '-infinity'),
    coalesce((SELECT max(j.requested_at) + interval '1 hour' FROM public.data_export_jobs j
              WHERE j.user_id = p_user_id AND j.status = 'failed'), '-infinity'),
    -- Three in the last day: allowed again when the oldest of the newest
    -- three is a day old (re-review M1).
    coalesce((SELECT j.requested_at + interval '24 hours' FROM public.data_export_jobs j
              WHERE j.user_id = p_user_id AND j.requested_at > now() - interval '24 hours'
              ORDER BY j.requested_at DESC OFFSET 2 LIMIT 1), '-infinity')
  ), '-infinity'::timestamptz);
$$;

-- A job not done within 6 hours has failed (re-review I5: a stalled cron
-- must never leave "Getting it ready" up for days, nor outlive the day's
-- grace on its parts). NULL: everyone's (the worker); else one person's.
CREATE OR REPLACE FUNCTION public.export_expire_stale(p_user_id uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_failed record;
BEGIN
  FOR v_failed IN
    UPDATE public.data_export_jobs j
    SET status = 'failed', error = 'expired'
    WHERE j.status IN ('queued', 'building') AND j.requested_at < now() - interval '6 hours'
      AND (p_user_id IS NULL OR j.user_id = p_user_id)
    RETURNING j.id
  LOOP
    PERFORM public.export_drop_files(v_failed.id);
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.request_my_export()
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
  v_next timestamptz;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'export:not_signed_in'; END IF;
  PERFORM pg_advisory_xact_lock(hashtext('data_export:' || v_uid::text));
  PERFORM public.export_expire_stale(v_uid);
  IF EXISTS (SELECT 1 FROM public.data_export_jobs
             WHERE user_id = v_uid AND status IN ('queued', 'building')) THEN
    RAISE EXCEPTION 'export:in_progress';
  END IF;
  -- One ready download a day; an hour's pause after a failure; at most
  -- three requests in a day (plan review I6).
  v_next := public.export_next_allowed(v_uid);
  IF v_next IS NOT NULL AND v_next > now() THEN
    RAISE EXCEPTION 'export:too_soon';
  END IF;
  INSERT INTO public.data_export_jobs (user_id) VALUES (v_uid) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- The latest job, and -- while it is not itself ready -- the last download
-- that still is, which get-export-url keeps serving (re-review M8).
CREATE OR REPLACE FUNCTION public.get_my_export()
RETURNS TABLE (id uuid, status text, requested_at timestamptz, ready_at timestamptz,
               expires_at timestamptz, next_allowed_at timestamptz, parts int,
               earlier_parts int, earlier_expires_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT j.id,
         CASE WHEN j.status = 'ready' AND j.expires_at <= now() THEN 'expired'
              WHEN j.status IN ('queued', 'building') AND j.requested_at < now() - interval '6 hours' THEN 'failed'
              ELSE j.status END,
         j.requested_at, j.ready_at, j.expires_at,
         public.export_next_allowed(auth.uid()),
         CASE WHEN j.status = 'ready' THEN cardinality(j.storage_keys) END,
         CASE WHEN j.status <> 'ready' THEN cardinality(e.storage_keys) END,
         CASE WHEN j.status <> 'ready' THEN e.expires_at END
  FROM public.data_export_jobs j
  LEFT JOIN LATERAL (
    SELECT k.storage_keys, k.expires_at FROM public.data_export_jobs k
    WHERE k.user_id = j.user_id AND k.status = 'ready' AND k.expires_at > now()
    ORDER BY k.requested_at DESC LIMIT 1
  ) e ON true
  WHERE j.user_id = auth.uid()
  ORDER BY j.requested_at DESC
  LIMIT 1;
$$;

-- The worker's: the oldest queued job (new, or between parts), or one a
-- crashed worker left building for 15 minutes; three crashes in a row, and
-- it fails; a job older than 6 hours fails (re-review I5). The first claim
-- snapshots the relationships it covers.
CREATE OR REPLACE FUNCTION public.claim_data_export()
RETURNS SETOF public.data_export_jobs LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_failed record;
BEGIN
  PERFORM public.export_expire_stale(NULL);
  FOR v_failed IN
    UPDATE public.data_export_jobs j
    SET status = 'failed', error = 'too many attempts'
    WHERE j.status = 'building' AND j.claimed_at < now() - interval '15 minutes' AND j.attempts >= 3
    RETURNING j.id
  LOOP
    PERFORM public.export_drop_files(v_failed.id);
  END LOOP;
  RETURN QUERY
  UPDATE public.data_export_jobs j
  SET status = 'building', claimed_at = now(),
      attempts = CASE WHEN j.status = 'building' THEN j.attempts + 1 ELSE 1 END,
      relationship_ids = coalesce(j.relationship_ids, public.export_open_relationships(j.user_id))
  WHERE j.id = (
    SELECT k.id FROM public.data_export_jobs k
    WHERE k.status = 'queued' OR (k.status = 'building' AND k.claimed_at < now() - interval '15 minutes')
    ORDER BY k.requested_at
    FOR UPDATE SKIP LOCKED
    LIMIT 1)
  RETURNING j.*;
END;
$$;

-- The next part's file name, queued for deletion before anything is stored
-- under it (final review C2). A day's grace until the download is ready.
CREATE OR REPLACE FUNCTION public.export_begin_part(p_job_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_key text;
BEGIN
  SELECT p_job_id::text || '/attune-export-' || (cardinality(j.storage_keys) + 1) || '.zip' INTO v_key
  FROM public.data_export_jobs j WHERE j.id = p_job_id AND j.status = 'building';
  IF v_key IS NULL THEN RAISE EXCEPTION 'export:not_building'; END IF;
  INSERT INTO public.media_deletion_queue (bucket_id, object_name, not_before)
  VALUES ('data-exports', v_key, now() + interval '1 day')
  ON CONFLICT (bucket_id, object_name) DO UPDATE SET not_before = EXCLUDED.not_before, deleted_at = NULL;
  RETURN v_key;
END;
$$;

-- A part is stored: record it and the progress. p_done finishes the job
-- (ready for 7 days); otherwise it goes back to the queue for the next part.
-- p_key NULL: the run had nothing to store, only progress (re-review I3).
-- A job that vanished meanwhile (account deleted) has its file dropped now.
CREATE OR REPLACE FUNCTION public.export_finish_part(
  p_job_id uuid, p_key text, p_phase text, p_rel_index int,
  p_chat_after_at timestamptz, p_chat_after_id uuid, p_chat_page int,
  p_media_after_bucket text, p_media_after_name text, p_left_out jsonb, p_done boolean
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_expires timestamptz := now() + interval '7 days';
BEGIN
  UPDATE public.data_export_jobs j
  SET storage_keys = CASE WHEN p_key IS NULL THEN j.storage_keys ELSE j.storage_keys || p_key END,
      phase = CASE WHEN p_done THEN 'done' ELSE p_phase END,
      rel_index = p_rel_index, chat_after_at = p_chat_after_at, chat_after_id = p_chat_after_id,
      chat_page = p_chat_page, media_after_bucket = p_media_after_bucket, media_after_name = p_media_after_name,
      left_out = j.left_out || coalesce(p_left_out, '[]'::jsonb),
      status = CASE WHEN p_done THEN 'ready' ELSE 'queued' END,
      ready_at = CASE WHEN p_done THEN now() END,
      expires_at = CASE WHEN p_done THEN v_expires END,
      attempts = 0, part_failures = 0, error = NULL
  WHERE j.id = p_job_id AND j.status = 'building';
  IF NOT FOUND THEN
    IF p_key IS NULL THEN RETURN; END IF;
    UPDATE public.media_deletion_queue SET not_before = now(), deleted_at = NULL
    WHERE bucket_id = 'data-exports' AND object_name = p_key;
    RETURN;
  END IF;
  IF p_done THEN
    UPDATE public.media_deletion_queue q SET not_before = v_expires
    FROM public.data_export_jobs j
    WHERE j.id = p_job_id AND q.bucket_id = 'data-exports' AND q.object_name = ANY (j.storage_keys);
  END IF;
END;
$$;

-- Every file of a job goes now (a failure, too many attempts, a deletion).
CREATE OR REPLACE FUNCTION public.export_drop_files(p_job_id uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  UPDATE public.media_deletion_queue SET not_before = now(), deleted_at = NULL
  WHERE bucket_id = 'data-exports' AND object_name LIKE p_job_id::text || '/%';
$$;

-- Files go only when this call failed the job: a part whose finish already
-- committed (its response lost) keeps them (re-review I1).
CREATE OR REPLACE FUNCTION public.fail_data_export(p_job_id uuid, p_error text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  UPDATE public.data_export_jobs
  SET status = 'failed', error = left(coalesce(p_error, 'unknown'), 300)
  WHERE id = p_job_id AND status = 'building';
  IF FOUND THEN
    PERFORM public.export_drop_files(p_job_id);
  END IF;
END;
$$;

-- A part that threw: back to the queue with its progress and finished parts
-- kept; the third error on the same part fails the job (re-review I2).
-- Returns the job's status afterwards (NULL: it was not building).
CREATE OR REPLACE FUNCTION public.export_retry_part(p_job_id uuid, p_error text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_status text;
BEGIN
  UPDATE public.data_export_jobs
  SET part_failures = part_failures + 1,
      status = CASE WHEN part_failures + 1 >= 3 THEN 'failed' ELSE 'queued' END,
      error = left(coalesce(p_error, 'unknown'), 300)
  WHERE id = p_job_id AND status = 'building'
  RETURNING status INTO v_status;
  IF v_status = 'failed' THEN
    PERFORM public.export_drop_files(p_job_id);
  END IF;
  RETURN v_status;
END;
$$;

-- ---------------------------------------------------------------------
-- The bucket: private, no client policy at all. Files are named
-- <job_id>/attune-export-N.zip (no person id in the path) and reached only
-- through the short signed links get-export-url mints. Parts stay under
-- 50 MB (40 MB of media plus data), within Storage's default object limit.
-- ---------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public) VALUES ('data-exports', 'data-exports', false)
ON CONFLICT (id) DO UPDATE SET public = false;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'storage' AND table_name = 'buckets' AND column_name = 'file_size_limit') THEN
    UPDATE storage.buckets SET file_size_limit = 52428800, allowed_mime_types = ARRAY['application/zip']
    WHERE id = 'data-exports';
  END IF;
END $$;
DROP POLICY IF EXISTS data_exports_owner_read ON storage.objects;
