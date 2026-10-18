-- supabase/tests/quiz_compatibility_retired_contracts.sql
-- Spec 5 (research 06 §3 F9, plan R5-3, review I10): no pairing statement
-- about the couple survives anywhere. The compatibility cache is empty and
-- unwritable, its upsert RPC is gone, and an attachment result can never be
-- shared (it is about the person who took it).
BEGIN;
DO $$
DECLARE v_role text;
BEGIN
  IF to_regprocedure('public.upsert_attachment_compatibility_cache(uuid,text,text,text,text,text,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the pairing upsert RPC still exists';
  END IF;
  FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    IF has_table_privilege(v_role, 'public.attachment_compatibility_cache', 'SELECT')
       OR has_table_privilege(v_role, 'public.attachment_compatibility_cache', 'INSERT')
       OR has_table_privilege(v_role, 'public.attachment_compatibility_cache', 'UPDATE')
       OR has_table_privilege(v_role, 'public.attachment_compatibility_cache', 'DELETE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % can still touch the pairing cache', v_role;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.attachment_compatibility_cache) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pairing rows remain';
  END IF;
  IF EXISTS (SELECT 1 FROM public.quiz_shares WHERE quiz_type = 'attachment') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: attachment shares remain';
  END IF;
END $$;

-- No new attachment share, whoever writes it.
SET LOCAL session_replication_role = replica;
DO $$
BEGIN
  BEGIN
    INSERT INTO public.quiz_shares (sharer_user_id, recipient_user_id, quiz_type, quiz_response_id)
    VALUES (gen_random_uuid(), gen_random_uuid(), 'attachment', gen_random_uuid());
    RAISE EXCEPTION 'CONTRACT VIOLATED: an attachment result was shared';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  -- Other quizzes still share.
  INSERT INTO public.quiz_shares (sharer_user_id, recipient_user_id, quiz_type, quiz_response_id)
  VALUES (gen_random_uuid(), gen_random_uuid(), 'love_language', gen_random_uuid());
END $$;
DO $$ BEGIN RAISE NOTICE 'quiz_compatibility_retired_contracts: all held'; END $$;
ROLLBACK;
