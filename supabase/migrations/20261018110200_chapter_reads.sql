-- Spec 3b (research 06 §3 F13 (1); 05 D.2, D.3 #2, #4; plan review C2, I2):
-- a relationship's games, answers, Pulse, patterns, timeline, reminders and
-- family are readable only while public.relationship_chat_open(rel) holds
-- (member, not archived, within the 30-day window, not sealed by the
-- caller); nothing is written into it unless it is active. Each policy is the
-- live definition with its member test replaced by the gate (reads) or
-- extended with status = 'active' (writes). FOR ALL policies are split so
-- their read half is gated too.

-- Helpers: which relationship a session, round or journey belongs to.
CREATE OR REPLACE FUNCTION public.game_session_relationship(p_session_id uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT s.relationship_id FROM public.game_sessions s WHERE s.id = p_session_id;
$$;
CREATE OR REPLACE FUNCTION public.game_round_relationship(p_round_id uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT coalesce(r.relationship_id, s.relationship_id)
  FROM public.game_session_rounds r
  LEFT JOIN public.game_sessions s ON s.id = r.session_id
  WHERE r.id = p_round_id;
$$;
-- Member and active: the write test.
CREATE OR REPLACE FUNCTION public.relationship_active_for_me(p_relationship_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = p_relationship_id AND r.status = 'active'
      AND auth.uid() IS NOT NULL AND auth.uid() IN (r.user_a, r.user_b)
  );
$$;

-- ---------------------------------------------------------------------
-- Reads.
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS ask2_state_relationship_read ON public.ask2_state;
CREATE POLICY ask2_state_relationship_read ON public.ask2_state
  FOR SELECT TO authenticated USING (public.relationship_chat_open(relationship_id));

DROP POLICY IF EXISTS compatibility_cache_relationship ON public.attachment_compatibility_cache;
CREATE POLICY compatibility_cache_relationship ON public.attachment_compatibility_cache
  FOR SELECT TO authenticated USING (public.relationship_chat_open(relationship_id));

DROP POLICY IF EXISTS reflections_relationship_members ON public.chapter_reflections;
CREATE POLICY reflections_relationship_members ON public.chapter_reflections
  FOR SELECT USING (EXISTS (
    SELECT 1 FROM public.thirty_six_question_journeys j
    WHERE j.id = chapter_reflections.journey_id AND public.relationship_chat_open(j.relationship_id)
  ));

DROP POLICY IF EXISTS family_members_select_members ON public.couple_family_members;
CREATE POLICY family_members_select_members ON public.couple_family_members
  FOR SELECT TO authenticated USING (public.relationship_chat_open(relationship_id));

DROP POLICY IF EXISTS game_sessions_relationship_members_select ON public.game_sessions;
CREATE POLICY game_sessions_relationship_members_select ON public.game_sessions
  FOR SELECT USING (public.relationship_chat_open(relationship_id));

DROP POLICY IF EXISTS game_rounds_relationship_members_select ON public.game_session_rounds;
CREATE POLICY game_rounds_relationship_members_select ON public.game_session_rounds
  FOR SELECT USING (EXISTS (
    SELECT 1 FROM public.game_sessions s
    WHERE s.id = game_session_rounds.session_id AND s.game_type <> 'paint_ball'
      AND public.relationship_chat_open(s.relationship_id)
  ));

DROP POLICY IF EXISTS mirror_truth_members_read ON public.mirror_round_truth;
CREATE POLICY mirror_truth_members_read ON public.mirror_round_truth
  FOR SELECT USING (
    public.relationship_chat_open(public.game_round_relationship(round_id))
    AND (subject_id = auth.uid()
         OR EXISTS (SELECT 1 FROM public.game_session_rounds r
                    WHERE r.id = mirror_round_truth.round_id AND r.both_answered))
  );

DROP POLICY IF EXISTS paint_ball_penalties_read_members ON public.paint_ball_penalties;
CREATE POLICY paint_ball_penalties_read_members ON public.paint_ball_penalties
  FOR SELECT TO authenticated
  USING (public.relationship_chat_open(public.game_session_relationship(session_id)));

DROP POLICY IF EXISTS patterns_relationship_members ON public.patterns;
CREATE POLICY patterns_relationship_members ON public.patterns
  FOR SELECT TO authenticated USING (public.relationship_chat_open(relationship_id));

DROP POLICY IF EXISTS pulse_scores_relationship_members ON public.pulse_scores;
CREATE POLICY pulse_scores_relationship_members ON public.pulse_scores
  FOR SELECT TO authenticated USING (public.relationship_chat_open(relationship_id));

DROP POLICY IF EXISTS reminders_select_members ON public.reminders;
CREATE POLICY reminders_select_members ON public.reminders
  FOR SELECT TO authenticated USING (public.relationship_chat_open(relationship_id));

DROP POLICY IF EXISTS answers_partner_read ON public.thirty_six_question_answers;
CREATE POLICY answers_partner_read ON public.thirty_six_question_answers
  FOR SELECT USING (
    public.relationship_chat_open(public.game_round_relationship(round_id))
    AND (auth.uid() = user_id
         OR EXISTS (SELECT 1 FROM public.game_session_rounds r
                    WHERE r.id = thirty_six_question_answers.round_id AND r.both_answered = true))
  );

DROP POLICY IF EXISTS journeys_relationship_members ON public.thirty_six_question_journeys;
CREATE POLICY journeys_relationship_members ON public.thirty_six_question_journeys
  FOR SELECT USING (public.relationship_chat_open(relationship_id));

DROP POLICY IF EXISTS seen_questions_relationship_members ON public.thirty_six_questions_seen;
CREATE POLICY seen_questions_relationship_members ON public.thirty_six_questions_seen
  FOR SELECT USING (public.relationship_chat_open(relationship_id));

DROP POLICY IF EXISTS timeline_relationship_members ON public.timeline_events;
CREATE POLICY timeline_relationship_members ON public.timeline_events
  FOR SELECT TO authenticated
  USING (
    deleted_at IS NULL
    AND (visibility = 'shared' OR logged_by = auth.uid())
    AND public.relationship_chat_open(relationship_id)
  );

-- FOR ALL policies, split: a gated read and the original write (now active-only).
DROP POLICY IF EXISTS answers_private_write ON public.thirty_six_question_answers;
CREATE POLICY answers_private_write ON public.thirty_six_question_answers
  FOR INSERT WITH CHECK (auth.uid() = user_id
    AND public.relationship_active_for_me(public.game_round_relationship(round_id)));
CREATE POLICY answers_private_update ON public.thirty_six_question_answers
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id
    AND public.relationship_active_for_me(public.game_round_relationship(round_id)));
CREATE POLICY answers_private_delete ON public.thirty_six_question_answers
  FOR DELETE USING (auth.uid() = user_id
    AND public.relationship_active_for_me(public.game_round_relationship(round_id)));

DROP POLICY IF EXISTS mirror_scores_self_only ON public.mirror_scores;
CREATE POLICY mirror_scores_self_read ON public.mirror_scores
  FOR SELECT USING (user_id = auth.uid()
    AND public.relationship_chat_open(public.game_session_relationship(session_id)));
CREATE POLICY mirror_scores_self_write ON public.mirror_scores
  FOR INSERT WITH CHECK (user_id = auth.uid()
    AND public.relationship_active_for_me(public.game_session_relationship(session_id)));
CREATE POLICY mirror_scores_self_update ON public.mirror_scores
  FOR UPDATE USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid()
    AND public.relationship_active_for_me(public.game_session_relationship(session_id)));
CREATE POLICY mirror_scores_self_delete ON public.mirror_scores
  FOR DELETE USING (user_id = auth.uid()
    AND public.relationship_active_for_me(public.game_session_relationship(session_id)));

DROP POLICY IF EXISTS game_questions_seen_members ON public.game_questions_seen;
CREATE POLICY game_questions_seen_read ON public.game_questions_seen
  FOR SELECT USING (public.relationship_chat_open(relationship_id));
CREATE POLICY game_questions_seen_write ON public.game_questions_seen
  FOR INSERT WITH CHECK (public.relationship_active_for_me(relationship_id));
CREATE POLICY game_questions_seen_update ON public.game_questions_seen
  FOR UPDATE USING (public.relationship_active_for_me(relationship_id))
  WITH CHECK (public.relationship_active_for_me(relationship_id));
CREATE POLICY game_questions_seen_delete ON public.game_questions_seen
  FOR DELETE USING (public.relationship_active_for_me(relationship_id));

DROP POLICY IF EXISTS session_idempotency_members ON public.session_idempotency_keys;
CREATE POLICY session_idempotency_read ON public.session_idempotency_keys
  FOR SELECT USING (public.relationship_chat_open(public.game_session_relationship(session_id)));
CREATE POLICY session_idempotency_write ON public.session_idempotency_keys
  FOR INSERT WITH CHECK (public.relationship_active_for_me(public.game_session_relationship(session_id)));
CREATE POLICY session_idempotency_update ON public.session_idempotency_keys
  FOR UPDATE USING (public.relationship_active_for_me(public.game_session_relationship(session_id)))
  WITH CHECK (public.relationship_active_for_me(public.game_session_relationship(session_id)));
CREATE POLICY session_idempotency_delete ON public.session_idempotency_keys
  FOR DELETE USING (public.relationship_active_for_me(public.game_session_relationship(session_id)));

-- ---------------------------------------------------------------------
-- Writes (I2): membership-only write policies now need an active space.
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS game_sessions_relationship_members_insert ON public.game_sessions;
CREATE POLICY game_sessions_relationship_members_insert ON public.game_sessions
  FOR INSERT WITH CHECK (
    game_type <> ALL (ARRAY['paint_ball', 'snakes_and_ladders', 'word_hunt'])
    AND public.relationship_active_for_me(relationship_id));
DROP POLICY IF EXISTS game_sessions_relationship_members_update ON public.game_sessions;
CREATE POLICY game_sessions_relationship_members_update ON public.game_sessions
  FOR UPDATE
  USING (game_type <> ALL (ARRAY['paint_ball', 'snakes_and_ladders', 'word_hunt'])
    AND public.relationship_active_for_me(relationship_id))
  WITH CHECK (game_type <> ALL (ARRAY['paint_ball', 'snakes_and_ladders', 'word_hunt'])
    AND public.relationship_active_for_me(relationship_id));
DROP POLICY IF EXISTS game_sessions_relationship_members_delete ON public.game_sessions;
CREATE POLICY game_sessions_relationship_members_delete ON public.game_sessions
  FOR DELETE USING (game_type <> ALL (ARRAY['paint_ball', 'snakes_and_ladders', 'word_hunt'])
    AND public.relationship_active_for_me(relationship_id));

DROP POLICY IF EXISTS game_rounds_relationship_members_insert ON public.game_session_rounds;
CREATE POLICY game_rounds_relationship_members_insert ON public.game_session_rounds
  FOR INSERT WITH CHECK (EXISTS (
    SELECT 1 FROM public.game_sessions s
    WHERE s.id = game_session_rounds.session_id
      AND s.game_type <> ALL (ARRAY['paint_ball', 'snakes_and_ladders', 'word_hunt'])
      AND public.relationship_active_for_me(s.relationship_id)));
DROP POLICY IF EXISTS game_rounds_relationship_members_update ON public.game_session_rounds;
CREATE POLICY game_rounds_relationship_members_update ON public.game_session_rounds
  FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM public.game_sessions s
    WHERE s.id = game_session_rounds.session_id
      AND s.game_type <> ALL (ARRAY['paint_ball', 'snakes_and_ladders', 'word_hunt'])
      AND public.relationship_active_for_me(s.relationship_id)))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.game_sessions s
    WHERE s.id = game_session_rounds.session_id
      AND s.game_type <> ALL (ARRAY['paint_ball', 'snakes_and_ladders', 'word_hunt'])
      AND public.relationship_active_for_me(s.relationship_id)));
DROP POLICY IF EXISTS game_rounds_relationship_members_delete ON public.game_session_rounds;
CREATE POLICY game_rounds_relationship_members_delete ON public.game_session_rounds
  FOR DELETE USING (EXISTS (
    SELECT 1 FROM public.game_sessions s
    WHERE s.id = game_session_rounds.session_id
      AND s.game_type <> ALL (ARRAY['paint_ball', 'snakes_and_ladders', 'word_hunt'])
      AND public.relationship_active_for_me(s.relationship_id)));

DROP POLICY IF EXISTS reflections_update_relationship_members ON public.chapter_reflections;
CREATE POLICY reflections_update_relationship_members ON public.chapter_reflections
  FOR UPDATE
  USING (EXISTS (SELECT 1 FROM public.thirty_six_question_journeys j
                 WHERE j.id = chapter_reflections.journey_id AND public.relationship_active_for_me(j.relationship_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM public.thirty_six_question_journeys j
                 WHERE j.id = chapter_reflections.journey_id AND public.relationship_active_for_me(j.relationship_id)));

DROP POLICY IF EXISTS journeys_insert ON public.thirty_six_question_journeys;
CREATE POLICY journeys_insert ON public.thirty_six_question_journeys
  FOR INSERT WITH CHECK (public.relationship_active_for_me(relationship_id));
DROP POLICY IF EXISTS journeys_update_members ON public.thirty_six_question_journeys;
CREATE POLICY journeys_update_members ON public.thirty_six_question_journeys
  FOR UPDATE USING (public.relationship_active_for_me(relationship_id))
  WITH CHECK (public.relationship_active_for_me(relationship_id));

DROP POLICY IF EXISTS mirror_truth_subject_write ON public.mirror_round_truth;
CREATE POLICY mirror_truth_subject_write ON public.mirror_round_truth
  FOR INSERT WITH CHECK (subject_id = auth.uid()
    AND public.relationship_active_for_me(public.game_round_relationship(round_id)));

DROP POLICY IF EXISTS family_members_update_members ON public.couple_family_members;
CREATE POLICY family_members_update_members ON public.couple_family_members
  FOR UPDATE TO authenticated USING (public.relationship_active_for_me(relationship_id));
DROP POLICY IF EXISTS family_members_delete_members ON public.couple_family_members;
CREATE POLICY family_members_delete_members ON public.couple_family_members
  FOR DELETE TO authenticated USING (public.relationship_active_for_me(relationship_id));

DROP POLICY IF EXISTS reminders_update_members ON public.reminders;
CREATE POLICY reminders_update_members ON public.reminders
  FOR UPDATE TO authenticated USING (public.relationship_active_for_me(relationship_id));
DROP POLICY IF EXISTS reminders_delete_members ON public.reminders;
CREATE POLICY reminders_delete_members ON public.reminders
  FOR DELETE TO authenticated USING (public.relationship_active_for_me(relationship_id));

DROP POLICY IF EXISTS timeline_update_owner ON public.timeline_events;
CREATE POLICY timeline_update_owner ON public.timeline_events
  FOR UPDATE TO authenticated
  USING (auth.uid() = logged_by AND public.relationship_active_for_me(relationship_id))
  WITH CHECK (auth.uid() = logged_by);
DROP POLICY IF EXISTS timeline_delete_owner ON public.timeline_events;
CREATE POLICY timeline_delete_owner ON public.timeline_events
  FOR DELETE TO authenticated
  USING (auth.uid() = logged_by AND public.relationship_active_for_me(relationship_id));

-- ---------------------------------------------------------------------
-- I2: the game write RPCs are SECURITY DEFINER and bypass the policies.
-- One guard per game table refuses a write a client caused unless the
-- relationship is active. Exempt: the service role (expiry jobs) and
-- writes made by other triggers (the end-of-relationship game abandon).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.game_write_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_rel uuid;
BEGIN
  IF pg_trigger_depth() > 1 OR coalesce(auth.role(), '') = 'service_role' OR auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;
  v_rel := CASE TG_TABLE_NAME
    WHEN 'game_sessions' THEN (to_jsonb(NEW)->>'relationship_id')::uuid
    WHEN 'game_session_rounds' THEN coalesce(
      (to_jsonb(NEW)->>'relationship_id')::uuid,
      public.game_session_relationship((to_jsonb(NEW)->>'session_id')::uuid))
    WHEN 'thirty_six_question_answers' THEN public.game_round_relationship((to_jsonb(NEW)->>'round_id')::uuid)
    WHEN 'this_or_that_round_answers' THEN public.game_round_relationship((to_jsonb(NEW)->>'round_id')::uuid)
    WHEN 'mirror_round_truth' THEN public.game_round_relationship((to_jsonb(NEW)->>'round_id')::uuid)
    ELSE public.game_session_relationship((to_jsonb(NEW)->>'session_id')::uuid)
  END;
  IF v_rel IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.relationships r WHERE r.id = v_rel AND r.status = 'active'
  ) THEN
    RAISE EXCEPTION 'lifecycle:not_active';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.game_write_guard() FROM PUBLIC, anon, authenticated;

DO $$
DECLARE v_t text;
BEGIN
  FOREACH v_t IN ARRAY ARRAY['game_sessions', 'game_session_rounds', 'thirty_six_question_answers',
    'this_or_that_round_answers', 'mirror_round_truth', 'mirror_scores', 'paint_ball_penalties',
    'word_hunt_attempts', 'word_hunt_puzzles']
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS aa_game_write_guard ON public.%I', v_t);
    EXECUTE format('CREATE TRIGGER aa_game_write_guard BEFORE INSERT OR UPDATE ON public.%I '
                   'FOR EACH ROW EXECUTE FUNCTION public.game_write_guard()', v_t);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- Class-D read RPCs (SECURITY DEFINER, member-only): each is wrapped by a
-- same-signature function that first asks relationship_chat_open. The
-- original is kept as <name>__ungated, callable by no client. Not
-- re-runnable on a database that already has the wrappers (migrations run
-- once). Volatility: scalar wrappers are VOLATILE (they call set_config),
-- set-returning ones STABLE; harmless with POST rpc() calls, which the app
-- uses throughout.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.chapter_rpc_open(p_kind text, p_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.relationship_chat_open(CASE p_kind
    WHEN 'session' THEN public.game_session_relationship(p_id)
    WHEN 'round' THEN public.game_round_relationship(p_id)
    ELSE p_id END);
$$;

DO $$
DECLARE
  v record;
  v_args text;
  v_call text;
  v_ret text;
  v_body text;
BEGIN
  FOR v IN
    SELECT p.oid, p.proname, p.proretset, x.kind
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
    JOIN (VALUES
      ('get_revealed_round', 'round'), ('session_game_round_state', 'session'),
      ('this_or_that_round_state', 'session'), ('get_paint_ball_session_state', 'session'),
      ('get_snakes_session_state', 'session'), ('get_word_hunt_state', 'session'),
      ('get_paint_ball_history', 'relationship'), ('get_active_paint_ball_session', 'relationship'),
      ('get_thirty_six_seen_map', 'relationship')
    ) AS x(name, kind) ON x.name = p.proname
  LOOP
    v_args := pg_get_function_arguments(v.oid);
    v_ret := pg_get_function_result(v.oid);
    SELECT string_agg(quote_ident(a), ', ' ORDER BY i) INTO v_call
    FROM unnest((SELECT proargnames FROM pg_proc WHERE oid = v.oid)) WITH ORDINALITY AS t(a, i)
    WHERE i <= (SELECT pronargs FROM pg_proc WHERE oid = v.oid);
    EXECUTE format('ALTER FUNCTION public.%I(%s) RENAME TO %I',
      v.proname, pg_get_function_identity_arguments(v.oid), v.proname || '__ungated');
    EXECUTE format('REVOKE ALL ON FUNCTION public.%I(%s) FROM PUBLIC, anon, authenticated',
      v.proname || '__ungated', pg_get_function_identity_arguments(v.oid));
    -- A closed chapter answers exactly what the function tells someone who
    -- was never a member: an empty set, or the function's own refusal (it
    -- is called once as a nobody, then the caller is restored).
    v_body := CASE WHEN v.proretset
      THEN format($b$
        -- Signed out or the service role: the function decides as before.
        IF auth.uid() IS NOT NULL AND NOT public.chapter_rpc_open(%1$L, %2$I) THEN
          RETURN;
        END IF;
        RETURN QUERY SELECT * FROM public.%3$I(%4$s);$b$,
        v.kind, (SELECT proargnames[1] FROM pg_proc WHERE oid = v.oid), v.proname || '__ungated', v_call)
      ELSE format($b$
        -- Signed out: the function's own UNAUTHORIZED answer stands.
        IF auth.uid() IS NOT NULL AND NOT public.chapter_rpc_open(%1$L, %2$I) THEN
          v_sub := current_setting('request.jwt.claim.sub', true);
          v_claims := current_setting('request.jwt.claims', true);
          PERFORM set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', true);
          PERFORM set_config('request.jwt.claims',
            '{"sub":"00000000-0000-0000-0000-000000000000","role":"authenticated"}', true);
          BEGIN
            v_out := public.%3$I(%4$s);
          EXCEPTION WHEN OTHERS THEN
            PERFORM set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
            PERFORM set_config('request.jwt.claims', coalesce(v_claims, ''), true);
            RAISE;
          END;
          PERFORM set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
          PERFORM set_config('request.jwt.claims', coalesce(v_claims, ''), true);
          RETURN v_out;
        END IF;
        RETURN public.%3$I(%4$s);$b$,
        v.kind, (SELECT proargnames[1] FROM pg_proc WHERE oid = v.oid), v.proname || '__ungated', v_call)
      END;
    EXECUTE format($f$
      CREATE FUNCTION public.%1$I(%2$s) RETURNS %3$s
      LANGUAGE plpgsql %5$s SECURITY DEFINER SET search_path = '' AS $w$
      DECLARE
        v_sub text;
        v_claims text;
        %6$s
      BEGIN
        -- Spec 3b: a closed chapter is answered as if never a member.
        %4$s
      END;
      $w$ $f$,
      v.proname, v_args, v_ret, v_body,
      CASE WHEN v.proretset THEN 'STABLE' ELSE 'VOLATILE' END,
      CASE WHEN v.proretset THEN '' ELSE 'v_out ' || v_ret || ';' END);
    EXECUTE format('REVOKE ALL ON FUNCTION public.%I(%s) FROM PUBLIC, anon',
      v.proname, pg_get_function_identity_arguments(v.oid));
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO authenticated',
      v.proname, pg_get_function_identity_arguments(v.oid));
  END LOOP;
END $$;
