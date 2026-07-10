BEGIN;

DO $$
BEGIN
  INSERT INTO auth.users (
    id,aud,role,email,encrypted_password,email_confirmed_at,
    raw_app_meta_data,raw_user_meta_data,created_at,updated_at
  ) VALUES
    ('00000000-0000-0000-0000-00000000da01','authenticated','authenticated','dating-a@example.com','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-00000000db02','authenticated','authenticated','dating-b@example.com','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-00000000dc03','authenticated','authenticated','dating-c@example.com','x',now(),'{}','{}',now(),now())
  ON CONFLICT(id) DO NOTHING;

  INSERT INTO public.users(id,email,display_name,mode) VALUES
    ('00000000-0000-0000-0000-00000000da01','dating-a@example.com','Dating A','solo'),
    ('00000000-0000-0000-0000-00000000db02','dating-b@example.com','Dating B','solo'),
    ('00000000-0000-0000-0000-00000000dc03','dating-c@example.com','Dating C','solo')
  ON CONFLICT(id) DO UPDATE SET email=EXCLUDED.email,display_name=EXCLUDED.display_name;

  INSERT INTO public.dating_enrollments(user_id,state) VALUES
    ('00000000-0000-0000-0000-00000000da01','profile_draft'),
    ('00000000-0000-0000-0000-00000000db02','profile_draft')
  ON CONFLICT(user_id) DO UPDATE SET state=EXCLUDED.state;

  INSERT INTO public.dating_profiles(user_id,display_name,city_region_code,relationship_intention,bio,profile_state,moderation_state)
  VALUES
    ('00000000-0000-0000-0000-00000000da01','Dating A','Accra','Intentional dating',NULL,'draft','approved'),
    ('00000000-0000-0000-0000-00000000db02','Dating B','Kumasi','Intentional dating',NULL,'draft','approved')
  ON CONFLICT(user_id) DO UPDATE SET display_name=EXCLUDED.display_name;
END
$$;

CREATE OR REPLACE FUNCTION public.test_set_dating_auth(p_user_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',p_user_id::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claims',json_build_object('sub',p_user_id,'role','authenticated')::text,true);
END;
$$;

SELECT public.test_set_dating_auth('00000000-0000-0000-0000-00000000da01');
DO $$ DECLARE v_count int; BEGIN
  SELECT count(*) INTO v_count FROM public.dating_profiles;
  IF v_count<>1 THEN RAISE EXCEPTION 'profile owner expected 1 row, got %',v_count; END IF;
  SELECT count(*) INTO v_count FROM public.dating_enrollments;
  IF v_count<>1 THEN RAISE EXCEPTION 'enrollment owner expected 1 row, got %',v_count; END IF;
END $$;

SELECT public.test_set_dating_auth('00000000-0000-0000-0000-00000000dc03');
DO $$ DECLARE v_count int; BEGIN
  SELECT count(*) INTO v_count FROM public.dating_profiles;
  IF v_count<>0 THEN RAISE EXCEPTION 'outsider read % dating profiles',v_count; END IF;
  SELECT count(*) INTO v_count FROM public.dating_enrollments;
  IF v_count<>0 THEN RAISE EXCEPTION 'outsider read % dating enrollments',v_count; END IF;
END $$;

RESET ROLE;
DO $$
BEGIN
  IF COALESCE((SELECT enabled FROM public.feature_flags WHERE key='dating_mode_enabled'),false) THEN
    RAISE EXCEPTION 'dating_mode_enabled must default false';
  END IF;
  IF has_function_privilege('authenticated','public.block_dating_user(text,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'authenticated can execute raw-target block RPC';
  END IF;
  IF has_function_privilege('authenticated','public.submit_dating_report(text,uuid,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'authenticated can execute raw-target report RPC';
  END IF;
  IF has_function_privilege('authenticated','public.get_dating_operational_health()','EXECUTE') THEN
    RAISE EXCEPTION 'authenticated can read backend operational health';
  END IF;
  IF pg_get_function_result('public.get_my_dating_introductions(integer)'::regprocedure) ~* '(user_id|pair_key)' THEN
    RAISE EXCEPTION 'introduction payload exposes internal identity';
  END IF;
  IF pg_get_function_result('public.get_my_dating_matches(integer)'::regprocedure) ~* '(user_id|pair_key)' THEN
    RAISE EXCEPTION 'match payload exposes internal identity';
  END IF;
  BEGIN
    INSERT INTO public.dating_algorithm_configs(version,state,config,config_hash,activated_at)
    VALUES('unreviewed-test','active','{}','unreviewed-test',now());
    RAISE EXCEPTION 'unreviewed active algorithm unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END
$$;

ROLLBACK;
