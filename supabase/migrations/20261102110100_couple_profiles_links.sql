-- Spec 1 W5, migration 10 part 2 of 2 (spec §4.7 #10; plan P-1):
-- couple_profiles_links. Four existing functions re-created from their
-- live bodies (spec §4.3 rule, reviews I-1, I-6), each with only W5's
-- lines added; couple_profile_contracts.sql section H diffs every one
-- against its previous body.
--   * accept_relationship_invite_v2 (from 20261102100000, W4a with all its
--     hardening: the inviter-relationship and hold checks, the uniform
--     invite:invalid, the acceptor's account:hold, both users rows locked
--     lowest id first and then the pending row, the acceptance read once
--     after that lock, both people's other pending invites removed, D8):
--     + one PERFORM adopt_couple_profile_drafts after the path is set.
--   * set_user_path_internal (from 20261025100300): + a change to Dating
--     deletes the person's couple_profile_drafts row (review I-6).
--   * export_relationship (from 20261024100700, the stories order kept):
--     + 'about_us', values and changes, no ids.
--   * export_bundle (from 20261018120000): + personal.settings.birth_date,
--     .path and .journal_reminder.
-- Grants (unchanged) restated in 20261102110110_couple_profiles_links_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.accept_relationship_invite_v2(p_acceptor uuid, p_invite_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_code constant text := upper(regexp_replace(coalesce(p_invite_code, ''), '\s', '', 'g'));
  v_hash text;
  v_done public.relationship_invite_acceptances%ROWTYPE;
  v_rel public.relationships%ROWTYPE;
  v_inviter uuid;
  v_age integer;
  v_waited interval;
BEGIN
  IF p_acceptor IS NULL OR v_code !~ '^[A-Z0-9]{6,12}$' THEN
    RAISE EXCEPTION 'invite:invalid';
  END IF;
  v_hash := encode(extensions.digest(v_code, 'sha256'), 'hex');

  -- Who sent it, read without a lock, so both users rows can be locked
  -- before any relationships row.
  SELECT r.user_a INTO v_inviter FROM public.relationships AS r
   WHERE r.invite_code = v_code AND r.status = 'pending';

  -- Lock order (W1 carry, W4 F-3): the acceptor's and the inviter's users
  -- rows, lowest id first, before any relationships row, as set_my_path
  -- and the withdraw do. No acceptor row: nothing is created (D8).
  PERFORM 1 FROM public.users AS u
   WHERE u.id IN (p_acceptor, v_inviter) ORDER BY u.id FOR UPDATE;
  IF NOT EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = p_acceptor) THEN
    RAISE EXCEPTION 'invite:phone_required';
  END IF;

  -- The pending row, locked: a second accept of the same code waits here
  -- for the first to commit, then finds no pending row.
  SELECT * INTO v_rel FROM public.relationships AS r
   WHERE r.invite_code = v_code AND r.status = 'pending'
   FOR UPDATE;
  -- Read only after that wait, so an acceptance committed meanwhile is
  -- seen: someone else's is invite:already_accepted, one's own a replay.
  SELECT * INTO v_done FROM public.relationship_invite_acceptances AS a
   WHERE a.invite_code_hash = v_hash;
  IF FOUND THEN
    IF v_done.accepted_by IS DISTINCT FROM p_acceptor THEN
      RAISE EXCEPTION 'invite:already_accepted';
    END IF;
    RETURN jsonb_build_object(
      'relationship_id', v_done.relationship_id,
      'status', (SELECT r.status FROM public.relationships AS r WHERE r.id = v_done.relationship_id),
      'idempotent', true,
      'inviter_id', (SELECT r.user_a FROM public.relationships AS r WHERE r.id = v_done.relationship_id));
  END IF;
  IF v_rel.id IS NULL THEN
    RAISE EXCEPTION 'invite:invalid';
  END IF;
  IF v_rel.user_a IS DISTINCT FROM v_inviter THEN
    -- The code changed hands between the read and the lock (a new invite
    -- reusing it): lock that inviter's row too.
    PERFORM 1 FROM public.users AS u WHERE u.id = v_rel.user_a FOR UPDATE;
  END IF;
  IF v_rel.user_a = p_acceptor THEN
    RAISE EXCEPTION 'invite:own';
  END IF;
  IF v_rel.user_b IS NOT NULL THEN
    RAISE EXCEPTION 'invite:invalid';
  END IF;
  IF v_rel.invite_expires_at < now() THEN
    RAISE EXCEPTION 'invite:expired';
  END IF;
  IF EXISTS (SELECT 1 FROM public.relationships AS r
              WHERE p_acceptor IN (r.user_a, r.user_b) AND r.status IN ('active', 'paused')) THEN
    RAISE EXCEPTION 'invite:already_in_relationship';
  END IF;
  IF public.verified_phone(p_acceptor) IS NULL THEN
    RAISE EXCEPTION 'invite:phone_required';
  END IF;
  IF EXISTS (SELECT 1 FROM public.account_holds AS h
              WHERE h.user_id = p_acceptor AND h.resolved_at IS NULL) THEN
    RAISE EXCEPTION 'account:hold';
  END IF;
  IF private.spec1_flag_on('flow_signin_v2') THEN
    v_age := public.account_age(p_acceptor);
    IF v_age IS NULL THEN
      RAISE EXCEPTION 'invite:age_required';
    END IF;
    IF v_age < 18 THEN
      RAISE EXCEPTION 'invite:not_possible';
    END IF;
  END IF;
  -- The inviter's side (rulings I-1, I-3), uniform.
  IF private.invite_inviter_unavailable(v_rel.user_a, v_rel.id) THEN
    RAISE EXCEPTION 'invite:invalid';
  END IF;
  IF private.spec1_flag_on('flow_signin_v2') THEN
    v_age := public.account_age(v_rel.user_a);
    IF v_age IS NULL OR v_age < 18 THEN
      RAISE EXCEPTION 'invite:not_possible';
    END IF;
  END IF;

  -- The acceptor's own invites go first, in this transaction (spec §7.1).
  DELETE FROM public.relationships AS r
   WHERE r.user_a = p_acceptor AND r.status = 'pending' AND r.user_b IS NULL;
  -- And the inviter's other codes (ruling I-1): none can link them again.
  DELETE FROM public.relationships AS r
   WHERE r.user_a = v_rel.user_a AND r.id <> v_rel.id
     AND r.status = 'pending' AND r.user_b IS NULL;

  BEGIN
    UPDATE public.relationships
       SET user_b = p_acceptor,
           status = 'active',
           invite_code = NULL,
           invite_accepted_at = now()
     WHERE id = v_rel.id;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'relationship:already_open' THEN
      RAISE EXCEPTION 'invite:already_in_relationship';
    END IF;
    RAISE;
  END;

  INSERT INTO public.relationship_invite_acceptances
    (invite_code_hash, relationship_id, accepted_by, accepted_at)
  VALUES (v_hash, v_rel.id, p_acceptor, now());

  PERFORM public.set_user_path_internal(p_acceptor, 'relationship');

  -- Spec 1 W5 (§3.8 R4, §4.3 W5): the inviter's About us draft, then the
  -- acceptor's, become the couple's shared profile.
  PERFORM public.adopt_couple_profile_drafts(v_rel.id, v_rel.user_a, p_acceptor);

  -- Server events (internal; spec §4.3 W1b seeds): every accept, and those
  -- within a day and within a week of the invite.
  v_waited := now() - v_rel.created_at;
  PERFORM private.bump_metric_internal('invite_accepted');
  IF v_waited <= interval '24 hours' THEN
    PERFORM private.bump_metric_internal('invite_accepted_24h');
  END IF;
  IF v_waited <= interval '7 days' THEN
    PERFORM private.bump_metric_internal('invite_accepted_7d');
  END IF;

  RETURN jsonb_build_object(
    'relationship_id', v_rel.id,
    'status', 'active',
    'idempotent', false,
    'inviter_id', v_rel.user_a);
END;
$$;

CREATE OR REPLACE FUNCTION public.set_user_path_internal(p_user uuid, p_path text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_old text;
  v_chosen_at timestamptz;
  v_elapsed interval;
BEGIN
  IF p_path IS NULL OR p_path NOT IN ('relationship', 'dating', 'just_me') THEN
    RAISE EXCEPTION 'path:invalid';
  END IF;
  SELECT u.path, u.path_chosen_at INTO v_old, v_chosen_at
    FROM public.users AS u WHERE u.id = p_user FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'path:no_account';
  END IF;
  IF v_old IS NOT DISTINCT FROM p_path THEN RETURN; END IF;

  UPDATE public.users
     SET path_previous = v_old,
         path = p_path,
         path_chosen_at = now()
   WHERE id = p_user;

  -- Spec 1 W5 (review I-6): a change to Dating takes the person's About us
  -- draft with it (spec §4.2).
  IF p_path = 'dating' THEN
    DELETE FROM public.couple_profile_drafts AS d WHERE d.user_id = p_user;
  END IF;

  IF v_old IS NULL THEN
    INSERT INTO public.onboarding_profiles (user_id) VALUES (p_user)
    ON CONFLICT (user_id) DO NOTHING;
    -- Written once, at the first choice, and never re-synced (D14). A status
    -- legacy onboarding already wrote is that one write, so it is kept
    -- (batch 4 review #5).
    INSERT INTO public.profiles AS p (id, relationship_status)
    VALUES (p_user, CASE p_path WHEN 'relationship' THEN 'taken'
                                WHEN 'dating' THEN 'single'
                                ELSE 'figuring_it_out' END)
    ON CONFLICT (id) DO UPDATE
      SET relationship_status = coalesce(p.relationship_status, EXCLUDED.relationship_status);
    PERFORM private.bump_metric_internal('path_chosen:' || p_path);
  ELSE
    v_elapsed := now() - coalesce(v_chosen_at, now());
    IF v_elapsed <= interval '7 days' THEN
      PERFORM private.bump_metric_internal('path_switch_7d:' || v_old || '>' || p_path);
    ELSIF v_elapsed <= interval '30 days' THEN
      PERFORM private.bump_metric_internal('path_switch_30d:' || v_old || '>' || p_path);
    END IF;
  END IF;

  -- The one Dating pause Spec 1 makes (D18).
  IF p_path = 'relationship'
     AND (private.dating_home_summary(p_user) ->> 'enrolled')::boolean THEN
    PERFORM public.pause_dating_for_relationship_user(p_user);
  END IF;
END;
$$;

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

    -- Spec 1 W5 (§4.3 W5): About us, its values and who changed each one
    -- ('me' or 'partner', never an id) and when.
    'about_us', (
      SELECT jsonb_build_object(
        'together_since', cp.together_since,
        'together_since_precision', cp.together_since_precision,
        'stage', cp.stage, 'stage_words', cp.stage_words,
        'ceremonies', cp.ceremonies, 'living', cp.living,
        'children', cp.children, 'child_age_bands', to_jsonb(cp.child_age_bands),
        'anniversary_source', cp.anniversary_source,
        'changes', coalesce((
          SELECT jsonb_agg(jsonb_build_object(
            'field', c.field, 'by', public.export_who(p_user_id, c.by), 'at', c.at) ORDER BY c.at, c.field)
          FROM (VALUES ('together_since', cp.together_since_changed_by, cp.together_since_changed_at),
                       ('stage', cp.stage_changed_by, cp.stage_changed_at),
                       ('ceremonies', cp.ceremonies_changed_by, cp.ceremonies_changed_at),
                       ('living', cp.living_changed_by, cp.living_changed_at),
                       ('children', cp.children_changed_by, cp.children_changed_at),
                       ('anniversary', cp.anniversary_changed_by, cp.anniversary_changed_at)) AS c(field, by, at)
          WHERE c.at IS NOT NULL), '[]'::jsonb))
      FROM public.couple_profiles cp WHERE cp.relationship_id = p_relationship_id),

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
          FROM public.session_devices d WHERE d.user_id = p_user_id), '[]'::jsonb),
        -- Spec 1 W5 (§4.3 W5): my date of birth (in my own export only),
        -- the way I use Attune, and my journal reminder.
        'birth_date', (SELECT ab.birth_date FROM public.account_birthdates ab WHERE ab.user_id = p_user_id),
        'path', (SELECT u.path FROM public.users u WHERE u.id = p_user_id),
        'journal_reminder', (SELECT jsonb_build_object(
            'enabled', jr.enabled, 'iso_weekday', jr.iso_weekday, 'local_time', jr.local_time)
          FROM public.journal_reminder_settings jr WHERE jr.user_id = p_user_id)),
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

REVOKE ALL ON FUNCTION public.accept_relationship_invite_v2(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_user_path_internal(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.export_relationship(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.export_bundle(uuid, uuid[]) FROM PUBLIC, anon, authenticated;

COMMIT;
