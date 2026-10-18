-- supabase/tests/relationship_purge_contracts.sql
-- Spec 3b (research 06 §3 F1 (7)): an archived relationship is hard-deleted
-- 12 months after archive, unless on legal hold; its storage is queued first;
-- the person's own insights survive, unattached; a relationship whose two
-- members both deleted their accounts goes at once.
BEGIN;

INSERT INTO auth.users (id)
SELECT ('9e100000-0000-0000-0000-0000000000' || lpad(i::text, 2, '0'))::uuid
FROM generate_series(1, 6) i ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name)
SELECT ('9e100000-0000-0000-0000-0000000000' || lpad(i::text, 2, '0'))::uuid,
       '+2335994' || lpad(i::text, 5, '0'), 'Purge ' || i
FROM generate_series(1, 6) i ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.u(i int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('9e100000-0000-0000-0000-0000000000' || lpad(i::text, 2, '0'))::uuid $$;
CREATE FUNCTION pg_temp.r(i int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('9e200000-0000-0000-0000-0000000000' || lpad(i::text, 2, '0'))::uuid $$;

-- r1 archived 13 months ago (purged); r2 11 months ago (kept); r3 13 months
-- ago on legal hold (kept); r4 both accounts deleted (purged, any status).
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at, ended_at)
VALUES
  (pg_temp.r(1), pg_temp.u(1), pg_temp.u(2), 'ended', CURRENT_DATE, now() - interval '3 years', now(), now() - interval '14 months'),
  (pg_temp.r(2), pg_temp.u(3), pg_temp.u(4), 'ended', CURRENT_DATE, now() - interval '3 years', now(), now() - interval '12 months'),
  (pg_temp.r(3), pg_temp.u(5), pg_temp.u(6), 'ended', CURRENT_DATE, now() - interval '3 years', now(), now() - interval '14 months'),
  (pg_temp.r(4), NULL, NULL, 'ended', CURRENT_DATE, now() - interval '1 year', now(), now() - interval '5 days');
UPDATE public.relationships SET status = 'archived', chat_archived_reason = 'window_closed',
  chat_archived_at = CASE id WHEN pg_temp.r(2) THEN now() - interval '11 months' ELSE now() - interval '13 months' END,
  chat_avatar_url = CASE id WHEN pg_temp.r(1) THEN 'relationship-avatars/' || pg_temp.r(1) || '/a.jpg' END
WHERE id IN (pg_temp.r(1), pg_temp.r(2), pg_temp.r(3));
UPDATE public.relationships SET legal_hold = true WHERE id = pg_temp.r(3);

SET LOCAL session_replication_role = replica;
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, media_url, media_type)
VALUES ('9e300000-0000-0000-0000-000000000001', pg_temp.r(1), pg_temp.u(1), gen_random_uuid(), 'old', 'chat-media/9e-old.jpg', 'image'),
       ('9e300000-0000-0000-0000-000000000002', pg_temp.r(2), pg_temp.u(3), gen_random_uuid(), 'kept', NULL, NULL),
       ('9e300000-0000-0000-0000-000000000003', pg_temp.r(3), pg_temp.u(5), gen_random_uuid(), 'held', NULL, NULL);
INSERT INTO public.personal_insights (user_id, relationship_id, insight_type, insight_body)
VALUES (pg_temp.u(1), pg_temp.r(1), 'pattern', 'mine to keep');
INSERT INTO public.weekly_checkins (user_id, relationship_id, week_ending) VALUES (pg_temp.u(1), pg_temp.r(1), CURRENT_DATE - 400);
INSERT INTO public.pulse_private_scores (user_id, relationship_id, week_ending, emotional_safety) VALUES (pg_temp.u(1), pg_temp.r(1), CURRENT_DATE - 400, 50);
INSERT INTO public.message_media_upload_intents (relationship_id, requester_id, storage_key, media_type, mime_type, expires_at)
VALUES (pg_temp.r(1), pg_temp.u(1), 'chat-media/9e-intent.jpg', 'image', 'image/jpeg', now());
INSERT INTO storage.objects (bucket_id, name) VALUES
  ('planning-media', pg_temp.r(1) || '/entry/photo.jpg'),
  ('story-media', 'story-media/' || pg_temp.r(1) || '/' || pg_temp.u(1) || '/x-photo'),
  ('relationship-avatars', 'relationship-avatars/' || pg_temp.r(1) || '/a.jpg'),
  ('planning-media', pg_temp.r(2) || '/entry/kept.jpg');
SET LOCAL session_replication_role = origin;

SELECT public.purge_archived_relationships();

DO $$
DECLARE v record;
BEGIN
  IF EXISTS (SELECT 1 FROM public.relationships WHERE id IN (pg_temp.r(1), pg_temp.r(4))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a relationship due for deletion survived';
  END IF;
  IF EXISTS (SELECT 1 FROM public.messages WHERE id = '9e300000-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purged chat''s message survived';
  END IF;
  IF (SELECT count(*) FROM public.relationships WHERE id IN (pg_temp.r(2), pg_temp.r(3))) <> 2
     OR NOT EXISTS (SELECT 1 FROM public.messages WHERE id = '9e300000-0000-0000-0000-000000000002')
     OR NOT EXISTS (SELECT 1 FROM public.messages WHERE id = '9e300000-0000-0000-0000-000000000003') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an 11-month or legal-hold relationship was deleted';
  END IF;
  FOR v IN SELECT * FROM (VALUES
    ('message-media', 'chat-media/9e-old.jpg'),
    ('message-media', 'chat-media/9e-intent.jpg'),
    ('planning-media', pg_temp.r(1) || '/entry/photo.jpg'),
    ('story-media', 'story-media/' || pg_temp.r(1) || '/' || pg_temp.u(1) || '/x-photo'),
    ('relationship-avatars', 'relationship-avatars/' || pg_temp.r(1) || '/a.jpg')) t(b, n)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE bucket_id = v.b AND object_name = v.n) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % / % was not queued', v.b, v.n;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE object_name = pg_temp.r(2) || '/entry/kept.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a kept relationship''s photo was queued';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.personal_insights
                 WHERE user_id = pg_temp.u(1) AND insight_body = 'mine to keep' AND relationship_id IS NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the person''s own insight did not survive, unattached';
  END IF;
  -- The person's own check-ins and private score are theirs (D.2 "Private"):
  -- kept, unattached (final review I-3).
  IF NOT EXISTS (SELECT 1 FROM public.weekly_checkins WHERE user_id = pg_temp.u(1) AND relationship_id IS NULL)
     OR NOT EXISTS (SELECT 1 FROM public.pulse_private_scores WHERE user_id = pg_temp.u(1) AND relationship_id IS NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge deleted the person''s own check-ins or private score';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purge_archived_relationships') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge is not scheduled';
  END IF;
  IF has_function_privilege('authenticated', 'public.purge_archived_relationships()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.purge_relationship(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client can purge';
  END IF;
  IF has_column_privilege('authenticated', 'public.relationships', 'legal_hold', 'UPDATE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client can set legal hold';
  END IF;
END $$;

-- Final review I-1: an inviter cannot make a space immune to the purge.
DO $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(1), 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', pg_temp.u(1)::text, true);
  BEGIN
    INSERT INTO public.relationships (user_a, status, invite_code, invite_expires_at, legal_hold)
    VALUES (pg_temp.u(1), 'pending', 'HOLD-ME', now() + interval '1 day', true);
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: an inviter created a relationship on legal hold';
  EXCEPTION WHEN insufficient_privilege THEN
    RESET ROLE;
  END;
END $$;

DO $$ BEGIN RAISE NOTICE 'relationship_purge_contracts: all held'; END $$;
ROLLBACK;
