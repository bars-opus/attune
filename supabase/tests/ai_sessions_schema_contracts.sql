-- Static Sessions tables: shape and RLS-absence contracts. Spec §7.1, §7.2.
-- Run: psql -q -d attune_test -f supabase/tests/ai_sessions_schema_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'a6000000-0000-0000-0000-000000000aca';
  v_user_a uuid := 'a6000000-0000-0000-0000-00000000000a';
  v_user_b uuid := 'a6000000-0000-0000-0000-00000000000b';
  v_session uuid := gen_random_uuid();
BEGIN
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;

  -- Contract 1: the table accepts a well-formed preparing-state row
  -- via direct insert (proving column shape/defaults) -- this fixture
  -- setup runs as the migration owner, not authenticated; Contract 2
  -- proves authenticated has no access at all.
  INSERT INTO public.ai_sessions (
    id, relationship_id, creator_id, kind, visibility, state,
    revision, context_revision, generation_epoch, attempt_count,
    preparation_deadline
  ) VALUES (
    v_session, v_rel, v_user_a, 'ideas', 'private', 'preparing',
    1, 0, 0, 0, now() + interval '5 minutes'
  );

  -- Contract 2: authenticated has NO grant on any of the three tables
  -- in this migration, in either direction.
  IF EXISTS (
    SELECT 1 FROM information_schema.table_privileges
    WHERE table_name IN ('ai_sessions', 'ai_session_approvals', 'ai_session_sources')
      AND grantee = 'authenticated'
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated has a direct table grant on a Sessions table';
  END IF;

  -- Contract 3: RLS is enabled on all three (enabled but policy-less is
  -- what makes "no grant" airtight even against a future accidental
  -- GRANT -- RLS still blocks it with no matching policy).
  IF (SELECT count(*) FROM pg_tables
      WHERE schemaname = 'public'
        AND tablename IN ('ai_sessions', 'ai_session_approvals', 'ai_session_sources')
        AND rowsecurity = true) != 3 THEN
    RAISE EXCEPTION 'EXPLOIT: not all three Sessions tables have RLS enabled';
  END IF;

  -- Contract 4: kind and visibility are immutable in shape (CHECK
  -- constraints reject invalid values) -- this is schema-level
  -- enforcement, not just application-code discipline.
  BEGIN
    INSERT INTO public.ai_sessions (
      id, relationship_id, creator_id, kind, visibility, state,
      revision, context_revision, generation_epoch, attempt_count,
      preparation_deadline
    ) VALUES (
      gen_random_uuid(), v_rel, v_user_a, 'nonsense_kind', 'private', 'preparing',
      1, 0, 0, 0, now() + interval '5 minutes'
    );
    RAISE EXCEPTION 'EXPLOIT: an invalid kind value was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 5: attempt_count is bounded 0..10 at the schema level.
  BEGIN
    UPDATE public.ai_sessions SET attempt_count = 11 WHERE id = v_session;
    RAISE EXCEPTION 'EXPLOIT: attempt_count accepted a value above 10';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  RAISE NOTICE 'ai_sessions static schema contracts: all held';
END $$;
