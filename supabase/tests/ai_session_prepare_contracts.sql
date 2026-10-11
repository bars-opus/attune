-- prepare_ai_session: idempotent creation, one-pending-slot enforcement,
-- expired-slot reclamation. Spec §3.2.
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_prepare_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000003';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000002a';
  v_user_b uuid := 'b1000000-0000-0000-0000-00000000002b';
  v_key_1 uuid := gen_random_uuid();
  v_row record;
  v_session_1 uuid;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'prep_a@t.test'), (v_user_b, 'prep_b@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550010001', 'A'), (v_user_b, '+15550010002', 'B')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;

  -- Contract 1: a fresh prepare succeeds and returns created=true.
  SELECT * INTO v_row FROM public.prepare_ai_session(
    v_user_a, v_key_1, v_rel, 'ideas', 'private', NULL, false, NULL
  );
  IF v_row.created IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'EXPLOIT: a fresh prepare did not report created=true';
  END IF;
  v_session_1 := v_row.session_id;

  -- Contract 2: replaying the SAME idempotency key returns the SAME
  -- session_id with created=false, not a second row.
  SELECT * INTO v_row FROM public.prepare_ai_session(
    v_user_a, v_key_1, v_rel, 'ideas', 'private', NULL, false, NULL
  );
  IF v_row.session_id IS DISTINCT FROM v_session_1 OR v_row.created IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'EXPLOIT: replaying the same idempotency key created a second session';
  END IF;

  -- Contract 3: a SECOND private prepare by the SAME creator, with a
  -- DIFFERENT idempotency key, while the first is still preparing,
  -- is rejected (one pending private session per creator).
  --
  -- ASSERTS THE SPECIFIC SQLSTATE, not "any error". The previous form
  -- caught WHEN OTHERS and re-raised only its own EXPLOIT message, so
  -- a prepare that failed for ANY unrelated reason -- a typo in the
  -- argument list, a constraint violation, a NULL-actor refusal --
  -- reported this contract as held. 20260953200200 added ERRCODE
  -- 'AT001' to both slot-limit RAISEs precisely so this can be
  -- discriminated, and Plan C's edge function keys its §10
  -- SESSION_LIMIT_REACHED mapping off the same code.
  BEGIN
    PERFORM public.prepare_ai_session(v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false, NULL);
    RAISE EXCEPTION 'EXPLOIT: a second concurrent private preparing session was allowed for the same creator';
  EXCEPTION
    WHEN SQLSTATE 'AT001' THEN
      -- The message text too: Plan C keeps a text-matching FALLBACK leg
      -- for transports that drop the SQLSTATE, so both must hold.
      IF SQLERRM NOT LIKE '%already pending or active%' THEN
        RAISE EXCEPTION
          'EXPLOIT: the private slot limit raised AT001 but its message changed to "%" -- Plan C''s index.ts keeps a text-matching fallback leg for transports that drop the code; update both together', SQLERRM;
      END IF;
    WHEN OTHERS THEN
      IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
      RAISE EXCEPTION
        'EXPLOIT: the private slot limit was refused with SQLSTATE % ("%") instead of AT001. Without the ERRCODE, Plan C''s prepare branch can only discriminate the limit by regex-matching the exception text, and a reword silently degrades §10''s SESSION_LIMIT_REACHED to a generic UNAVAILABLE.', SQLSTATE, SQLERRM;
  END;

  -- Contract 4: user_b's OWN private session slot is independent of
  -- user_a's -- the limit is per-creator, not per-relationship, for
  -- the private case.
  PERFORM public.prepare_ai_session(v_user_b, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false, NULL);

  -- Contract 5: an expired preparing session is reclaimed -- backdate
  -- the first session's deadline into the past, then prove a new
  -- private prepare by user_a now succeeds.
  UPDATE public.ai_sessions SET preparation_deadline = now() - interval '1 minute'
  WHERE id = v_session_1;
  PERFORM public.prepare_ai_session(v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false, NULL);
  IF (SELECT state FROM public.ai_sessions WHERE id = v_session_1) != 'closed' THEN
    RAISE EXCEPTION 'EXPLOIT: the expired preparing session was not reclaimed (closed) before the new one was allowed';
  END IF;

  RAISE NOTICE 'prepare_ai_session contracts: all held';
END $$;


-- =====================================================================
-- ITEM A CONTRACTS (migration 20260953200200). Spec §4.2 (persist
-- source IDs and versions), §4.3 (window default off), §4.1 (private
-- and Nearby sessions have no window).
--
-- WHY A SEPARATE BLOCK: the contracts above all pass p_include_window
-- = false and NULL window ids, so NONE of them could tell the
-- pre-20260953200200 body -- which accepted p_include_window and
-- discarded it, writing only 'target' rows with source_version =
-- m.created_at -- from the current one. Each assertion below names the
-- specific row, role and timestamp expected.
--
-- FIXTURE IDS: a distinct b1000000-...-0000000000d* block, swept
-- against every other supabase/tests/*.sql and every supabase/
-- functions test before use (users.phone is UNIQUE and these inserts
-- are deliberately NOT `ON CONFLICT DO NOTHING` for the relationship
-- or the messages, so a collision fails loudly instead of silently
-- reusing another suite's row).
-- =====================================================================
DO $$
DECLARE
  v_rel      uuid := 'b1000000-0000-0000-0000-0000000000d3';
  v_user_a   uuid := 'b1000000-0000-0000-0000-0000000000da';
  v_user_b   uuid := 'b1000000-0000-0000-0000-0000000000db';
  v_target   uuid := 'b1000000-0000-0000-0000-0000000000f0';
  v_win_1    uuid := 'b1000000-0000-0000-0000-0000000000f1';
  v_win_2    uuid := 'b1000000-0000-0000-0000-0000000000f2';
  v_sess_on  uuid := 'b1000000-0000-0000-0000-0000000000e1';
  v_sess_off uuid := 'b1000000-0000-0000-0000-0000000000e2';
  v_sess_ed  uuid := 'b1000000-0000-0000-0000-0000000000e3';
  v_count    int;
  v_flag     boolean;
  v_version  timestamptz;
  v_created  timestamptz;
  v_edited   timestamptz;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'prep_win_a@t.test'), (v_user_b, 'prep_win_b@t.test');
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550010301', 'WA'), (v_user_b, '+15550010302', 'WB');
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active');
  INSERT INTO public.messages
    (id, relationship_id, sender_id, client_message_id, content, source, created_at)
  VALUES
    (v_target, v_rel, v_user_a, gen_random_uuid(), 'the target message', 'native', now() - interval '9 minutes'),
    (v_win_1,  v_rel, v_user_a, gen_random_uuid(), 'window line one',    'native', now() - interval '8 minutes'),
    (v_win_2,  v_rel, v_user_b, gen_random_uuid(), 'window line two',    'native', now() - interval '7 minutes');

  -- ---- A1, the ON case: p_include_window = true persists the SETTING
  -- and one 'window' row per supplied id.
  PERFORM public.prepare_ai_session(
    v_user_a, v_sess_on, v_rel, 'ideas', 'shared', v_target, true,
    ARRAY[v_win_1, v_win_2]::uuid[]);

  SELECT include_window INTO v_flag FROM public.ai_sessions WHERE id = v_sess_on;
  IF v_flag IS DISTINCT FROM true THEN
    RAISE EXCEPTION
      'EXPLOIT: p_include_window = true was not persisted (ai_sessions.include_window = %). That is the pre-20260953200200 defect exactly: the parameter was accepted and discarded, so spec §4.3''s "Window is default off; enabling it in preparing state invalidates approvals" had no substrate to be a property of.', COALESCE(v_flag::text, 'NULL');
  END IF;

  SELECT count(*) INTO v_count FROM public.ai_session_sources
   WHERE session_id = v_sess_on AND source_role = 'window';
  IF v_count != 2 THEN
    RAISE EXCEPTION
      'EXPLOIT: prepare_ai_session persisted % window source rows for two supplied ids, expected exactly 2. The ai_session_sources CHECK has allowed source_role = ''window'' since 20260953010000 and NO function ever wrote one; 20260953200200 is what does.', v_count;
  END IF;
  -- The SPECIFIC ids, not just the count: a body that wrote two rows
  -- for the wrong messages (the two newest in the relationship, say,
  -- re-selected in SQL instead of persisting what the caller approved)
  -- satisfies the count alone.
  IF NOT EXISTS (
    SELECT 1 FROM public.ai_session_sources
     WHERE session_id = v_sess_on AND source_role = 'window' AND source_message_id = v_win_1
  ) OR NOT EXISTS (
    SELECT 1 FROM public.ai_session_sources
     WHERE session_id = v_sess_on AND source_role = 'window' AND source_message_id = v_win_2
  ) THEN
    RAISE EXCEPTION
      'EXPLOIT: the persisted window rows are not the two messages the caller supplied. Selection is the edge function''s (§4.2''s deterministic pipeline in ai_session_context.ts); this RPC''s job is to persist exactly what was approved, not to re-select.';
  END IF;
  -- And the target is still its own single row.
  SELECT count(*) INTO v_count FROM public.ai_session_sources
   WHERE session_id = v_sess_on AND source_role = 'target';
  IF v_count != 1 THEN
    RAISE EXCEPTION 'EXPLOIT: expected exactly one ''target'' source row, found %', v_count;
  END IF;

  -- ---- A1, the OFF case. A shared session already holds the shared
  -- slot for this relationship, so the OFF case is private.
  PERFORM public.prepare_ai_session(
    v_user_a, v_sess_off, v_rel, 'ideas', 'private', v_target, false, NULL);
  SELECT include_window INTO v_flag FROM public.ai_sessions WHERE id = v_sess_off;
  IF v_flag IS DISTINCT FROM false THEN
    RAISE EXCEPTION
      'EXPLOIT: p_include_window = false did not store as false (got %). §4.3''s "default off" needs a default to BE off; absence-of-rows is an inference, not a stored default.', COALESCE(v_flag::text, 'NULL');
  END IF;
  SELECT count(*) INTO v_count FROM public.ai_session_sources
   WHERE session_id = v_sess_off AND source_role = 'window';
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: p_include_window = false still persisted % window source rows', v_count;
  END IF;
  -- ANTI-VACUITY: the OFF session must still have its target row, or
  -- "zero window rows" would also be satisfied by a prepare that
  -- persisted nothing at all.
  SELECT count(*) INTO v_count FROM public.ai_session_sources
   WHERE session_id = v_sess_off AND source_role = 'target';
  IF v_count != 1 THEN
    RAISE EXCEPTION
      'EXPLOIT: the window-off session has % target rows, expected 1 -- the zero-window assertion above is vacuous if this prepare persisted nothing', v_count;
  END IF;

  -- ---- A1, the refusals. Window ids without the flag, and a window on
  -- a session kind that §4.1 says cannot have one, must both be
  -- refused rather than silently stored.
  BEGIN
    PERFORM public.prepare_ai_session(
      v_user_b, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, true,
      ARRAY[v_win_1]::uuid[]);
    RAISE EXCEPTION
      'EXPLOIT: a PRIVATE session was allowed a recent window. §4.1: "Private and Nearby sessions do not have recent windows."';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE '%requires a shared Ideas session%' THEN
      RAISE EXCEPTION
        'EXPLOIT: a private session with a window was refused, but with the wrong error ("%") -- so the refusal is coming from somewhere other than the §4.1 rule and would stop covering it if that other thing changed', SQLERRM;
    END IF;
  END;
  --
  -- RUN ON A RELATIONSHIP WITH NO LIVE SHARED SESSION. v_rel already
  -- holds one (v_sess_on), so a shared prepare there is refused by the
  -- SLOT LIMIT before this guard is ever reached -- which means the
  -- assertion would "catch" a deleted guard for entirely the wrong
  -- reason, and would also pass if the guard were MOVED below the slot
  -- limit. Measured: dropping the guard on v_rel reported
  -- 'A shared session is already pending or active'. A fresh
  -- relationship makes the guard the only thing that can refuse.
  DECLARE
    v_rel_g  uuid := 'b1000000-0000-0000-0000-0000000000d6';
    v_user_g uuid := 'b1000000-0000-0000-0000-0000000000de';
    v_msg_g  uuid := 'b1000000-0000-0000-0000-0000000000fb';
  BEGIN
    INSERT INTO auth.users (id, email) VALUES (v_user_g, 'prep_win_g@t.test');
    INSERT INTO public.users (id, phone, display_name)
      VALUES (v_user_g, '+15550010305', 'WG');
    INSERT INTO public.relationships (id, user_a, user_b, status)
      VALUES (v_rel_g, v_user_g, v_user_a, 'active');
    INSERT INTO public.messages
      (id, relationship_id, sender_id, client_message_id, content, source, created_at)
    VALUES (v_msg_g, v_rel_g, v_user_g, gen_random_uuid(),
            'a line in the guard relationship', 'native', now() - interval '4 minutes');
    BEGIN
      PERFORM public.prepare_ai_session(
        v_user_g, gen_random_uuid(), v_rel_g, 'ideas', 'shared', NULL, false,
        ARRAY[v_msg_g]::uuid[]);
      RAISE EXCEPTION
        'EXPLOIT: window message ids were accepted with p_include_window = false -- a frozen snapshot would be persisted for a session whose stored setting says it has no window, which is the exact divergence between the setting and the snapshot that 20260953200200 exists to prevent';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
      IF SQLERRM NOT LIKE '%p_include_window false%' THEN
        RAISE EXCEPTION
          'EXPLOIT: window-ids-without-the-flag was refused, but by "%" rather than by its own guard. On a relationship with no live shared session nothing else should be able to refuse it, so this means the guard is gone and something unrelated caught the call -- or the guard has moved below the slot limit, where it no longer runs first.', SQLERRM;
      END IF;
    END;
  END;
  -- The CHECK constraint is the database's own backstop, independent of
  -- the RPC's guard above. Asserted directly, because a future change
  -- to the RPC body must not be the only thing standing between a
  -- private session and a window setting.
  BEGIN
    UPDATE public.ai_sessions SET include_window = true WHERE id = v_sess_off;
    RAISE EXCEPTION
      'EXPLOIT: ai_sessions_window_only_shared_ideas does not exist or does not bite -- a direct UPDATE set include_window = true on a PRIVATE session';
  EXCEPTION WHEN check_violation THEN
    NULL; -- correct
  WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    RAISE EXCEPTION
      'EXPLOIT: the private-session include_window UPDATE failed with SQLSTATE % ("%") rather than a check_violation', SQLSTATE, SQLERRM;
  END;

  -- ---- A DUPLICATE id in p_window_message_ids yields ONE row.
  --
  -- NOTE ON MUTATION M13, recorded honestly: replacing the RPC's
  -- DISTINCT normalization with a bare COALESCE SURVIVES this test, and
  -- that is correct rather than a weak assertion. `m.id = ANY(array)`
  -- joins against public.messages, whose id is the PRIMARY KEY, so a
  -- repeated id matches that row exactly once and the duplicate never
  -- reaches the INSERT -- measured. The DISTINCT is defence in depth
  -- against a future rewrite of the query shape (see the migration's
  -- own note). This test asserts the OBSERVABLE property -- one row per
  -- supplied source, and no whole-request abort -- which is what a
  -- caller depends on and which holds under either implementation.
  DECLARE
    v_rel_d  uuid := 'b1000000-0000-0000-0000-0000000000d8';
    v_user_d uuid := 'b1000000-0000-0000-0000-0000000000e9';
    v_msg_d  uuid := 'b1000000-0000-0000-0000-0000000000fd';
    v_sess_d uuid := 'b1000000-0000-0000-0000-0000000000e5';
    v_n      int;
  BEGIN
    INSERT INTO auth.users (id, email) VALUES (v_user_d, 'prep_win_d@t.test');
    INSERT INTO public.users (id, phone, display_name)
      VALUES (v_user_d, '+15550010307', 'WD');
    INSERT INTO public.relationships (id, user_a, user_b, status)
      VALUES (v_rel_d, v_user_d, v_user_a, 'active');
    INSERT INTO public.messages
      (id, relationship_id, sender_id, client_message_id, content, source, created_at)
    VALUES (v_msg_d, v_rel_d, v_user_d, gen_random_uuid(),
            'a duplicated window id', 'native', now() - interval '4 minutes');
    BEGIN
      PERFORM public.prepare_ai_session(
        v_user_d, v_sess_d, v_rel_d, 'ideas', 'shared', NULL, true,
        ARRAY[v_msg_d, v_msg_d]::uuid[]);
    EXCEPTION WHEN unique_violation THEN
      RAISE EXCEPTION
        'EXPLOIT: a duplicated id in p_window_message_ids aborted the entire prepare with a unique_violation. ai_session_sources'' primary key is (session_id, source_message_id), so the RPC must collapse duplicates -- the caller''s selection module cannot be the only thing preventing a whole-request failure from a repeated id.';
    END;
    SELECT count(*) INTO v_n FROM public.ai_session_sources
     WHERE session_id = v_sess_d AND source_role = 'window';
    IF v_n != 1 THEN
      RAISE EXCEPTION
        'EXPLOIT: a duplicated window id produced % window rows, expected exactly 1', v_n;
    END IF;
  END;

  -- ---- M14: the §4.2 six-message cap. "limits six" is a spec budget,
  -- not a convenience: the window contributes to the 2,400-scalar
  -- budget and ultimately to §4.2's 12,700-scalar total, and a caller
  -- that is not the edge function (or an edge function whose selection
  -- regressed) must not be able to freeze a larger snapshot. Mutation
  -- M14 -- deleting the cap -- survived every other assertion.
  DECLARE
    v_rel_c  uuid := 'b1000000-0000-0000-0000-0000000000d9';
    v_user_c2 uuid := 'b1000000-0000-0000-0000-0000000000ea';
    v_ids    uuid[] := ARRAY[]::uuid[];
    v_id     uuid;
  BEGIN
    INSERT INTO auth.users (id, email) VALUES (v_user_c2, 'prep_win_cap@t.test');
    INSERT INTO public.users (id, phone, display_name)
      VALUES (v_user_c2, '+15550010308', 'WCap');
    INSERT INTO public.relationships (id, user_a, user_b, status)
      VALUES (v_rel_c, v_user_c2, v_user_a, 'active');
    FOR i IN 1..7 LOOP
      v_id := gen_random_uuid();
      v_ids := v_ids || v_id;
      INSERT INTO public.messages
        (id, relationship_id, sender_id, client_message_id, content, source, created_at)
      VALUES (v_id, v_rel_c, v_user_c2, gen_random_uuid(),
              'cap line ' || i, 'native', now() - (i || ' minutes')::interval);
    END LOOP;
    BEGIN
      PERFORM public.prepare_ai_session(
        v_user_c2, gen_random_uuid(), v_rel_c, 'ideas', 'shared', NULL, true, v_ids);
      RAISE EXCEPTION
        'EXPLOIT: SEVEN window message ids were accepted. §4.2 "limits six", and the window''s contribution to the 2,400-scalar and 12,700-scalar budgets depends on that cap holding in the function that PERSISTS the snapshot, not only in the caller that selected it.';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
      IF SQLERRM NOT LIKE '%At most six window messages%' THEN
        RAISE EXCEPTION
          'EXPLOIT: seven window ids were refused by "%" rather than by the six-message cap', SQLERRM;
      END IF;
    END;
    -- ANTI-VACUITY: SIX must be accepted, or the refusal above could be
    -- a cap of zero, one or five and this test would not notice.
    PERFORM public.prepare_ai_session(
      v_user_c2, gen_random_uuid(), v_rel_c, 'ideas', 'shared', NULL, true,
      v_ids[1:6]);
  END;

  -- ---- M15: the column's DEFAULT must be FALSE. §4.3's words are
  -- "Window is default off", and the default is what makes that true
  -- for any row written by a path other than this RPC -- including
  -- every row that existed before 20260953200200. Mutation M15 --
  -- DEFAULT true -- survived every other assertion, because every row
  -- these tests create goes through the RPC, which sets the value
  -- explicitly.
  IF (SELECT column_default FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'ai_sessions'
         AND column_name = 'include_window') IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION
      'EXPLOIT: ai_sessions.include_window''s DEFAULT is % and not false. §4.3: "Window is default off" -- a row inserted by any path that does not name the column must come out window-off, and that is also what made 20260953200200''s CHECK validate against every pre-existing row without a scan-time failure.',
      COALESCE((SELECT column_default FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'ai_sessions'
                   AND column_name = 'include_window'), 'NULL');
  END IF;
  IF (SELECT is_nullable FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'ai_sessions'
         AND column_name = 'include_window') != 'NO' THEN
    RAISE EXCEPTION
      'EXPLOIT: ai_sessions.include_window is NULLABLE. A NULL window setting is a third state between on and off, and §4.3''s invalidation-on-toggle is a comparison -- NULL compares to neither.';
  END IF;

  -- ---- §4.2 item 3, the target/window overlap. Mutation M11 --
  -- deleting this guard -- SURVIVED every other assertion in this file
  -- and in Contract 9, which is why this leg exists. The overlap is not
  -- merely redundant: ai_session_sources' primary key is (session_id,
  -- source_message_id), so a target that also appears in the window
  -- collides and aborts the WHOLE prepare with a raw 23505 the caller
  -- cannot act on. The guard turns that into a named refusal.
  --
  -- Run on its own relationship, for the same reason the guard above
  -- is: v_rel's shared slot is occupied, so a shared prepare there
  -- would be refused by the slot limit before the guard ran.
  DECLARE
    v_rel_o  uuid := 'b1000000-0000-0000-0000-0000000000d7';
    v_user_o uuid := 'b1000000-0000-0000-0000-0000000000df';
    v_msg_o  uuid := 'b1000000-0000-0000-0000-0000000000fc';
    v_dupes  int;
  BEGIN
    INSERT INTO auth.users (id, email) VALUES (v_user_o, 'prep_win_o@t.test');
    INSERT INTO public.users (id, phone, display_name)
      VALUES (v_user_o, '+15550010306', 'WO');
    INSERT INTO public.relationships (id, user_a, user_b, status)
      VALUES (v_rel_o, v_user_o, v_user_a, 'active');
    INSERT INTO public.messages
      (id, relationship_id, sender_id, client_message_id, content, source, created_at)
    VALUES (v_msg_o, v_rel_o, v_user_o, gen_random_uuid(),
            'both target and window', 'native', now() - interval '4 minutes');
    BEGIN
      PERFORM public.prepare_ai_session(
        v_user_o, gen_random_uuid(), v_rel_o, 'ideas', 'shared', v_msg_o, true,
        ARRAY[v_msg_o]::uuid[]);
      RAISE EXCEPTION
        'EXPLOIT: the selected target was accepted as a window message too. §4.2 item 3 excludes the target from the window, and ai_session_sources'' primary key (session_id, source_message_id) makes the overlap a primary-key collision that aborts the entire prepare.';
    EXCEPTION
      WHEN unique_violation THEN
        RAISE EXCEPTION
          'EXPLOIT: the target/window overlap guard is gone, so the overlap reached the INSERT and aborted the whole prepare with a raw unique_violation (SQLSTATE 23505) instead of a named refusal. That is the failure mode the guard exists to prevent -- the caller gets an opaque constraint name rather than "the selected target cannot also be a window message".';
      WHEN OTHERS THEN
        IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
        IF SQLERRM NOT LIKE '%target cannot also be a window message%' THEN
          RAISE EXCEPTION
            'EXPLOIT: the target/window overlap was refused by "%" rather than by its own guard', SQLERRM;
        END IF;
    END;
  END;

  -- ---- A2: source_version is COALESCE(edited_at, created_at), so an
  -- EDIT moves it. Before 20260953200200 the stored version was
  -- m.created_at, and created_at never moves on an edit -- confirmed by
  -- catalog query that no function in public assigns
  -- messages.created_at -- so §4.3's "revalidate ... source
  -- existence/version against the frozen snapshot" was blind to edits
  -- for the stored rows, while ai_session_context.ts's live window
  -- already used the COALESCE form. The two disagreed.
  UPDATE public.messages
     SET content = content || ' (edited)', edited_at = now()
   WHERE id IN (v_target, v_win_1);

  PERFORM public.prepare_ai_session(
    v_user_b, v_sess_ed, v_rel, 'ideas', 'private', v_target, false, NULL);

  SELECT s.source_version, m.created_at, m.edited_at
    INTO v_version, v_created, v_edited
    FROM public.ai_session_sources s
    JOIN public.messages m ON m.id = s.source_message_id
   WHERE s.session_id = v_sess_ed AND s.source_role = 'target';
  IF v_edited IS NULL THEN
    RAISE EXCEPTION 'SETUP FAILED: the target message was not actually edited, so the assertions below are vacuous';
  END IF;
  IF v_created = v_edited THEN
    RAISE EXCEPTION 'SETUP FAILED: created_at and edited_at coincide, so neither assertion below discriminates';
  END IF;
  IF v_version IS DISTINCT FROM v_edited THEN
    RAISE EXCEPTION
      'EXPLOIT: the stored target source_version is % but the message''s edited_at is %. source_version must be COALESCE(edited_at, created_at) or §4.3''s source-version revalidation cannot detect an edit -- a partner approves a digest computed over pre-edit text while the stored version says nothing changed.', v_version, v_edited;
  END IF;
  IF v_version = v_created THEN
    RAISE EXCEPTION
      'EXPLOIT: the stored target source_version equals created_at, which never moves on an edit. That is 20260953090000''s superseded expression (SELECT ..., m.created_at, ...).';
  END IF;

  -- The SAME property for a 'window' row, not just the target. Both
  -- roles must agree or the two revalidate differently -- which is why
  -- this leg exists separately rather than trusting the target's.
  UPDATE public.ai_sessions SET state = 'closed' WHERE id = v_sess_on;
  PERFORM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'shared', NULL, true,
    ARRAY[v_win_1]::uuid[]);
  SELECT s.source_version, m.created_at, m.edited_at
    INTO v_version, v_created, v_edited
    FROM public.ai_session_sources s
    JOIN public.messages m ON m.id = s.source_message_id
   WHERE s.source_role = 'window' AND s.source_message_id = v_win_1
     AND s.session_id != v_sess_on;
  IF v_version IS DISTINCT FROM v_edited OR v_version = v_created THEN
    RAISE EXCEPTION
      'EXPLOIT: a ''window'' row''s source_version is % (created_at %, edited_at %) -- window rows must use the SAME COALESCE(edited_at, created_at) expression as the target row, or the two stored roles revalidate differently under §4.3.', v_version, v_created, v_edited;
  END IF;

  -- ---- The authorization boundary on the new parameter. A window id
  -- from ANOTHER relationship must not be clipped and stored: this
  -- function is SECURITY DEFINER, so without the relationship_id
  -- predicate on the INSERT ... SELECT it would happily persist
  -- arbitrary chat text as an "approved source".
  DECLARE
    v_rel_other uuid := 'b1000000-0000-0000-0000-0000000000d4';
    v_user_c    uuid := 'b1000000-0000-0000-0000-0000000000dc';
    v_msg_other uuid := 'b1000000-0000-0000-0000-0000000000fa';
    v_sess_x    uuid := 'b1000000-0000-0000-0000-0000000000e4';
  BEGIN
    INSERT INTO auth.users (id, email) VALUES (v_user_c, 'prep_win_c@t.test');
    INSERT INTO public.users (id, phone, display_name)
      VALUES (v_user_c, '+15550010303', 'WC');
    INSERT INTO public.relationships (id, user_a, user_b, status)
      VALUES (v_rel_other, v_user_c, v_user_a, 'active');
    INSERT INTO public.messages
      (id, relationship_id, sender_id, client_message_id, content, source, created_at)
    VALUES
      (v_msg_other, v_rel_other, v_user_c, gen_random_uuid(),
       'ANOTHER COUPLE PRIVATE TEXT', 'native', now() - interval '3 minutes');

    UPDATE public.ai_sessions SET state = 'closed'
     WHERE relationship_id = v_rel AND visibility = 'shared' AND state = 'preparing';
    PERFORM public.prepare_ai_session(
      v_user_a, v_sess_x, v_rel, 'ideas', 'shared', NULL, true,
      ARRAY[v_win_2, v_msg_other]::uuid[]);

    IF EXISTS (
      SELECT 1 FROM public.ai_session_sources
       WHERE session_id = v_sess_x AND source_message_id = v_msg_other
    ) THEN
      RAISE EXCEPTION
        'EXPLOIT: prepare_ai_session persisted a window source row for a message in a DIFFERENT relationship. p_window_message_ids is caller-supplied and this function is SECURITY DEFINER, so the relationship_id predicate on the window INSERT ... SELECT is the authorization boundary; without it a member of one couple can freeze another couple''s chat text into an approved snapshot.';
    END IF;
    -- ANTI-VACUITY: the legitimate id in the SAME call must still have
    -- been stored, or "the foreign id was not stored" is satisfied by a
    -- body that stored nothing.
    IF NOT EXISTS (
      SELECT 1 FROM public.ai_session_sources
       WHERE session_id = v_sess_x AND source_message_id = v_win_2
         AND source_role = 'window'
    ) THEN
      RAISE EXCEPTION
        'EXPLOIT: the in-relationship window id in the same call was ALSO dropped -- the foreign-id assertion above proves nothing if the whole insert was skipped';
    END IF;
  END;

  -- ---- A3, the SHARED limit's SQLSTATE too, not just the private
  -- one. Mutation M6 -- dropping ERRCODE from the shared RAISE alone --
  -- SURVIVED the private-only assertion in the first block above, and
  -- the shared limit is the one two partners can collide on, so it is
  -- the more reachable of the two. Caught here as well as by the
  -- occurrence-count leg in Contract 9.
  DECLARE
    v_rel_s  uuid := 'b1000000-0000-0000-0000-0000000000d5';
    v_user_s uuid := 'b1000000-0000-0000-0000-0000000000dd';
  BEGIN
    INSERT INTO auth.users (id, email) VALUES (v_user_s, 'prep_win_s@t.test');
    INSERT INTO public.users (id, phone, display_name)
      VALUES (v_user_s, '+15550010304', 'WS');
    INSERT INTO public.relationships (id, user_a, user_b, status)
      VALUES (v_rel_s, v_user_s, v_user_a, 'active');
    PERFORM public.prepare_ai_session(
      v_user_s, gen_random_uuid(), v_rel_s, 'ideas', 'shared', NULL, false, NULL);
    BEGIN
      -- The PARTNER's attempt, so this is the cross-member collision
      -- rather than the creator's own.
      PERFORM public.prepare_ai_session(
        v_user_a, gen_random_uuid(), v_rel_s, 'ideas', 'shared', NULL, false, NULL);
      RAISE EXCEPTION
        'EXPLOIT: a second concurrent SHARED preparing session was allowed for the same relationship';
    EXCEPTION
      WHEN SQLSTATE 'AT001' THEN
        IF SQLERRM NOT LIKE '%already pending or active%' THEN
          RAISE EXCEPTION
            'EXPLOIT: the shared slot limit raised AT001 but its message changed to "%"', SQLERRM;
        END IF;
      WHEN OTHERS THEN
        IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
        RAISE EXCEPTION
          'EXPLOIT: the SHARED slot limit was refused with SQLSTATE % ("%") instead of AT001. Dropping the ERRCODE from the shared RAISE alone survives an assertion that only exercises the private limit (measured, mutation M6), and the shared limit is the one two partners can collide on.', SQLSTATE, SQLERRM;
    END;
  END;

  RAISE NOTICE 'prepare_ai_session Item A contracts: window persistence, edit-detecting source_version, the shared-Ideas-only CHECK and the cross-relationship boundary all hold';
END $$;
