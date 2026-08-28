BEGIN;


INSERT INTO auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
  ('71000000-0000-0000-0000-0000000000a1','authenticated','authenticated','+233200000001','x',now(),'{}','{}',now(),now()),
  ('71000000-0000-0000-0000-0000000000b2','authenticated','authenticated','+233200000002','x',now(),'{}','{}',now(),now()),
  ('71000000-0000-0000-0000-0000000000c3','authenticated','authenticated','+233200000003','x',now(),'{}','{}',now(),now()),
  ('71000000-0000-0000-0000-0000000000d4','authenticated','authenticated','+233200000004','x',now(),'{}','{}',now(),now())
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.users(id, phone,display_name,mode) VALUES
  ('71000000-0000-0000-0000-0000000000a1','+233200000005','Import A','couples'),
  ('71000000-0000-0000-0000-0000000000b2','+233200000006','Import B','couples'),
  ('71000000-0000-0000-0000-0000000000c3','+233200000007','Import C','couples'),
  ('71000000-0000-0000-0000-0000000000d4','+233200000008','Import D','couples')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.relationships(id,user_a,user_b,status,started_at,created_at) VALUES
  ('72000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-0000000000a1','71000000-0000-0000-0000-0000000000b2','active',current_date,now()),
  ('72000000-0000-0000-0000-000000000002','71000000-0000-0000-0000-0000000000c3','71000000-0000-0000-0000-0000000000d4','active',current_date,now())
ON CONFLICT (id) DO UPDATE SET status = 'active', chat_archived_at = NULL;

UPDATE public.feature_flags SET enabled = true WHERE key = 'chat_historical_import';

CREATE OR REPLACE FUNCTION public.test_set_chat_import_auth(p_user_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  -- request.jwt.claims (JSON), not the legacy singular
  -- request.jwt.claim.sub: auth.uid() parses the former, so setting only
  -- the latter left every call unauthenticated and this whole file could
  -- never reach the contracts it means to test.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_user_id::text, 'role', 'authenticated')::text,
    true);
  EXECUTE 'SET LOCAL ROLE authenticated';
END;
$$;

SELECT public.test_set_chat_import_auth('71000000-0000-0000-0000-0000000000a1');
CREATE TEMP TABLE import_test_state(request_id uuid, job_id uuid);

INSERT INTO import_test_state(request_id)
SELECT public.create_chat_import_request(
  '72000000-0000-0000-0000-000000000001',
  'chat-import-1.0',
  repeat('a', 64),
  2,
  now() - interval '2 days',
  now()
);

-- The uploader cannot provide the approver's independent signature.
DO $$
DECLARE v_succeeded boolean := false;
BEGIN
  BEGIN
    PERFORM public.respond_to_chat_import_request(
      (SELECT request_id FROM import_test_state), 'granted', 'chat-import-1.0'
    );
    v_succeeded := true;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  IF v_succeeded THEN RAISE EXCEPTION 'uploader approved own import'; END IF;
END
$$;

-- Both accounts in the unrelated relationship see no request.
SELECT public.test_set_chat_import_auth('71000000-0000-0000-0000-0000000000c3');
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.chat_import_requests) THEN
    RAISE EXCEPTION 'unrelated account C read import request';
  END IF;
END
$$;

SELECT public.test_set_chat_import_auth('71000000-0000-0000-0000-0000000000d4');
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.chat_import_requests) THEN
    RAISE EXCEPTION 'unrelated account D read import request';
  END IF;
END
$$;

SELECT public.test_set_chat_import_auth('71000000-0000-0000-0000-0000000000b2');
SELECT public.respond_to_chat_import_request(
  (SELECT request_id FROM import_test_state), 'granted', 'chat-import-1.0'
);

-- An unrelated user cannot ingest even after the real couple approved.
SELECT public.test_set_chat_import_auth('71000000-0000-0000-0000-0000000000c3');
DO $$
DECLARE v_succeeded boolean := false;
BEGIN
  BEGIN
    PERFORM * FROM public.ingest_chat_import_batch(
      (SELECT request_id FROM import_test_state), '[]'::jsonb, true
    );
    v_succeeded := true;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  IF v_succeeded THEN RAISE EXCEPTION 'unrelated account ingested import'; END IF;
END
$$;

SELECT public.test_set_chat_import_auth('71000000-0000-0000-0000-0000000000a1');
WITH result AS (
  SELECT * FROM public.ingest_chat_import_batch(
    (SELECT request_id FROM import_test_state),
    jsonb_build_array(
      jsonb_build_object('line',1,'sender_id','71000000-0000-0000-0000-0000000000a1','created_at',now()-interval '2 days','content','Earlier message'),
      jsonb_build_object('line',2,'sender_id','71000000-0000-0000-0000-0000000000b2','created_at',now()-interval '1 day','content','Earlier reply')
    ),
    true
  )
)
UPDATE import_test_state s SET job_id = result.job_id FROM result;

-- message_safety_outbox has RLS enabled with no policies: no client role may
-- read it (chat_system_contracts asserts exactly that denial). Verifying the
-- import enqueued Safety therefore has to run as the owning role, not as
-- `authenticated`, or the rows are invisible and the check fails for the
-- wrong reason.
RESET ROLE;
DO $$
DECLARE v_job uuid := (SELECT job_id FROM import_test_state);
BEGIN
  IF (SELECT count(*) FROM public.messages WHERE import_job_id = v_job) <> 2 THEN
    RAISE EXCEPTION 'expected two imported messages';
  END IF;
  IF (SELECT count(*) FROM public.message_safety_outbox o JOIN public.messages m ON m.id=o.message_id WHERE m.import_job_id=v_job) <> 2 THEN
    RAISE EXCEPTION 'import did not enqueue Safety for every message';
  END IF;
  IF EXISTS (SELECT 1 FROM public.message_notification_outbox o JOIN public.messages m ON m.id=o.message_id WHERE m.import_job_id=v_job) THEN
    RAISE EXCEPTION 'import created forbidden new-message push work';
  END IF;
END
$$;

SELECT public.test_set_chat_import_auth('71000000-0000-0000-0000-0000000000d4');
DO $$
DECLARE v_succeeded boolean := false;
BEGIN
  BEGIN
    PERFORM public.delete_chat_import((SELECT job_id FROM import_test_state), false);
    v_succeeded := true;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  IF v_succeeded THEN RAISE EXCEPTION 'unrelated account deleted import'; END IF;
END
$$;

SELECT public.test_set_chat_import_auth('71000000-0000-0000-0000-0000000000b2');
SELECT public.delete_chat_import((SELECT job_id FROM import_test_state), false);
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.messages WHERE import_job_id = (SELECT job_id FROM import_test_state)) THEN
    RAISE EXCEPTION 'partner deletion left imported messages';
  END IF;
END
$$;

ROLLBACK;
