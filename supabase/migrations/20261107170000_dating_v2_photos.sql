-- Spec 2 W3c, migration 1 (§4.9 W3c; §3.2 D9; §4.3 dating_profile_photos,
-- dating_photo_moderation_config; §4.4 Photos; §4.10; I-10, R11; plan
-- R-2, R-24, R-25, R-37): photo positions 1-6, captions (the owner's
-- only), csam_state, the five slot reasons, an approval only after a clear
-- inline CSAM scan, the child-label thresholds; the v2 photo RPCs (the
-- setup guard on everything that adds, never on a delete); the CSAM
-- outcome recorder for process-dating-photo; the two storage.objects
-- policies moved onto definer predicates (same names, commands, roles and
-- bucket), so the photo and intent tables lose their client SELECT (twin)
-- and their row policies. No storage.objects trigger (F-1).
-- Grants in 20261107170010_dating_v2_photos_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- 1. The photo table.
ALTER TABLE public.dating_profile_photos ADD COLUMN IF NOT EXISTS caption text;
ALTER TABLE public.dating_profile_photos ADD COLUMN IF NOT EXISTS csam_state text NOT NULL DEFAULT 'pending';
UPDATE public.dating_profile_photos AS f SET rejection_reason = CASE
    WHEN f.rejection_reason IN ('adult_content_detected', 'violent_content_detected', 'racy_content_detected') THEN 'unsafe'
    WHEN f.rejection_reason IN ('face_blurred', 'face_underexposed', 'face_too_small') THEN 'face_unclear'
    WHEN f.rejection_reason = 'image_too_small' THEN 'too_small'
    ELSE 'needs_review' END
 WHERE f.rejection_reason IS NOT NULL
   AND f.rejection_reason NOT IN ('face_unclear', 'too_small', 'contains_child', 'unsafe', 'needs_review');
-- R-24: an approval needs a clear scan; photos approved before (development
-- only) go back to pending and are scanned again.
UPDATE public.dating_profile_photos AS f
   SET moderation_state = 'pending', rejection_reason = NULL, reviewed_at = NULL
 WHERE f.moderation_state IN ('approved', 'needs_review') AND f.csam_state IS DISTINCT FROM 'clear'; -- Spec 2 W3c (fix round 1, M-2): needs_review too
INSERT INTO public.dating_photo_moderation_outbox (photo_id, user_id)
SELECT f.id, f.user_id FROM public.dating_profile_photos AS f WHERE f.moderation_state = 'pending'
ON CONFLICT (photo_id) DO UPDATE
   SET state = 'pending', attempts = 0, last_error_code = NULL, processing_started_at = NULL,
       completed_at = NULL, updated_at = now()
 WHERE public.dating_photo_moderation_outbox.state IN ('done', 'dead_letter');

ALTER TABLE public.dating_profile_photos DROP CONSTRAINT IF EXISTS dating_profile_photos_position_check;
ALTER TABLE public.dating_profile_photos ADD CONSTRAINT dating_profile_photos_position_check CHECK (position BETWEEN 1 AND 6);
ALTER TABLE public.dating_profile_photos DROP CONSTRAINT IF EXISTS dating_profile_photos_caption_check;
ALTER TABLE public.dating_profile_photos ADD CONSTRAINT dating_profile_photos_caption_check
  CHECK (caption IS NULL OR char_length(caption) BETWEEN 1 AND 100);
ALTER TABLE public.dating_profile_photos DROP CONSTRAINT IF EXISTS dating_profile_photos_csam_state_check;
ALTER TABLE public.dating_profile_photos ADD CONSTRAINT dating_profile_photos_csam_state_check
  CHECK (csam_state IN ('pending', 'clear', 'hit', 'error'));
ALTER TABLE public.dating_profile_photos DROP CONSTRAINT IF EXISTS dating_profile_photos_rejection_reason_check;
ALTER TABLE public.dating_profile_photos ADD CONSTRAINT dating_profile_photos_rejection_reason_check
  CHECK (rejection_reason IS NULL OR rejection_reason IN ('face_unclear', 'too_small', 'contains_child', 'unsafe', 'needs_review'));
ALTER TABLE public.dating_profile_photos DROP CONSTRAINT IF EXISTS dating_profile_photos_approved_clear_check;
ALTER TABLE public.dating_profile_photos ADD CONSTRAINT dating_profile_photos_approved_clear_check
  CHECK (moderation_state <> 'approved' OR csam_state = 'clear');
-- Reorder renumbers inside one statement (deferred, then checked at once).
ALTER TABLE public.dating_profile_photos DROP CONSTRAINT IF EXISTS dating_profile_photos_user_id_position_key;
ALTER TABLE public.dating_profile_photos ADD CONSTRAINT dating_profile_photos_user_id_position_key
  UNIQUE (user_id, position) DEFERRABLE INITIALLY IMMEDIATE;
-- Spec 2 W3c (fix round 1, I-3): one photo row per object; the storage predicate and the
-- Spec 2 W3c (fix round 1, I-3) orphan claim read by it (a definer predicate is not inlined).
CREATE UNIQUE INDEX IF NOT EXISTS dating_profile_photos_storage_key_key ON public.dating_profile_photos (storage_key); -- Spec 2 W3c (fix round 1, I-3)
-- Spec 2 W3c (fix round 1, M-7): a CSAM hit is final for every writer (the service role's
-- Spec 2 W3c (fix round 1, M-7) direct table writes included), not only inside the recorder.
CREATE OR REPLACE FUNCTION private.dating_photo_hit_final() -- Spec 2 W3c (fix round 1, M-7)
RETURNS trigger -- Spec 2 W3c (fix round 1, M-7)
LANGUAGE plpgsql -- Spec 2 W3c (fix round 1, M-7)
SECURITY DEFINER -- Spec 2 W3c (fix round 1, M-7)
SET search_path = '' -- Spec 2 W3c (fix round 1, M-7)
AS $$
BEGIN
  RAISE EXCEPTION 'dating:csam_final' USING ERRCODE = 'check_violation'; -- Spec 2 W3c (fix round 1, M-7): no row in the error
END;
$$;
DROP TRIGGER IF EXISTS dating_profile_photos_hit_final ON public.dating_profile_photos; -- Spec 2 W3c (fix round 1, M-7)
CREATE TRIGGER dating_profile_photos_hit_final -- Spec 2 W3c (fix round 1, M-7)
  BEFORE UPDATE OF csam_state ON public.dating_profile_photos -- Spec 2 W3c (fix round 1, M-7)
  FOR EACH ROW WHEN (OLD.csam_state = 'hit' AND NEW.csam_state IS DISTINCT FROM 'hit') -- Spec 2 W3c (fix round 1, M-7)
  EXECUTE FUNCTION private.dating_photo_hit_final(); -- Spec 2 W3c (fix round 1, M-7)

ALTER TABLE public.dating_photo_moderation_config ADD COLUMN IF NOT EXISTS child_label_reject numeric NOT NULL DEFAULT 0.7;
ALTER TABLE public.dating_photo_moderation_config ADD COLUMN IF NOT EXISTS child_label_review numeric NOT NULL DEFAULT 0.5;
ALTER TABLE public.dating_photo_moderation_config DROP CONSTRAINT IF EXISTS dating_photo_moderation_config_child_check;
ALTER TABLE public.dating_photo_moderation_config ADD CONSTRAINT dating_photo_moderation_config_child_check
  CHECK (child_label_review > 0 AND child_label_review < child_label_reject AND child_label_reject <= 1);

-- 2. The v2 RPCs (return types change: dropped and made again).
-- Spec 2 W3c (C; R-47, M-9): the setup guard's locks (the person's setup
-- Spec 2 W3c (C) lock, then the country's same-gender locks) under a photo
-- Spec 2 W3c (C) writer's 2s lock_timeout: a lock timeout, deadlock or
-- Spec 2 W3c (C) serialization failure is retried (3), then dating:busy with
-- Spec 2 W3c (C) the SQLSTATE, never the raw error.
CREATE OR REPLACE FUNCTION private.dating_photo_setup_guard() -- Spec 2 W3c (C)
RETURNS text -- Spec 2 W3c (C)
LANGUAGE plpgsql -- Spec 2 W3c (C)
SECURITY DEFINER -- Spec 2 W3c (C)
SET search_path = '' -- Spec 2 W3c (C)
AS $$
DECLARE
  v_try integer; -- Spec 2 W3c (C)
BEGIN
  FOR v_try IN 1..3 LOOP -- Spec 2 W3c (C)
    BEGIN -- Spec 2 W3c (C)
      RETURN private.dating_setup_guard(); -- Spec 2 W3c (C)
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W3c (C)
      IF v_try = 3 THEN -- Spec 2 W3c (C)
        RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; -- Spec 2 W3c (C)
      END IF; -- Spec 2 W3c (C)
    END; -- Spec 2 W3c (C)
  END LOOP; -- Spec 2 W3c (C)
  RAISE EXCEPTION 'dating:busy' USING ERRCODE = '55P03'; -- Spec 2 W3c (C): never reached; never NULL (eligible)
END;
$$;

-- Spec 2 W3 final (M-7): no photo before Dating's terms: an intent and an
-- Spec 2 W3 final insert need the standing D4 consents activation needs and
-- Spec 2 W3 final a profile (D2 made it), else not_eligible. Deleting never asks.
CREATE OR REPLACE FUNCTION private.dating_photo_allowed(p_user uuid) -- Spec 2 W3 final (M-7)
RETURNS boolean -- Spec 2 W3 final (M-7)
LANGUAGE sql -- Spec 2 W3 final (M-7)
STABLE -- Spec 2 W3 final (M-7)
SECURITY DEFINER -- Spec 2 W3 final (M-7)
SET search_path = '' -- Spec 2 W3 final (M-7)
AS $$ -- Spec 2 W3 final (M-7)
  SELECT p_user IS NOT NULL -- Spec 2 W3 final (M-7)
     AND coalesce(private.dating_consent_granted(p_user, 'dating_terms'), false) -- Spec 2 W3 final (M-7)
     AND coalesce(private.dating_consent_granted(p_user, 'dating_opt_in'), false) -- Spec 2 W3 final (M-7)
     AND coalesce(private.dating_consent_granted(p_user, 'special_category_profile'), false) -- Spec 2 W3 final (M-7)
     AND EXISTS (SELECT 1 FROM public.dating_profiles AS p WHERE p.user_id = p_user); -- Spec 2 W3 final (M-7)
$$; -- Spec 2 W3 final (M-7)

DROP FUNCTION IF EXISTS public.create_dating_photo_upload_intent(text);
CREATE FUNCTION public.create_dating_photo_upload_intent(p_mime_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_ext text;
  v_key text;
  v_id uuid;
  v_expires timestamptz;
  v_try integer;
BEGIN
  v_reason := private.dating_photo_setup_guard(); -- Spec 2 W3c (C): the guard's locks, retried
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  IF private.dating_photo_allowed(v_user) IS NOT TRUE THEN -- Spec 2 W3 final (M-7)
    RETURN jsonb_build_object('ok', false, 'reason', 'not_eligible'); -- Spec 2 W3 final (M-7)
  END IF; -- Spec 2 W3 final (M-7)
  v_ext := CASE p_mime_type WHEN 'image/jpeg' THEN 'jpg' WHEN 'image/png' THEN 'png' WHEN 'image/webp' THEN 'webp' END;
  IF v_ext IS NULL THEN
    RETURN private.dating_invalid('mime');
  END IF;
  -- Spec 2 W3 final (I-4): no count here: Replace and Crop ask for an intent
  -- Spec 2 W3 final with six photos; the insert keeps it to six (positions
  -- Spec 2 W3 final 1-6, one per position, the replaced slot deleted first).
  -- Spec 2 W3 final The 30-a-day intent rate limit below stays.
  BEGIN
    PERFORM public.check_dating_rate_limit('dating_photo_intent', 30, interval '1 day');
  EXCEPTION WHEN invalid_parameter_value THEN
    IF SQLERRM = 'rate_limited' THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'rate_limited');
    END IF;
    RAISE;
  END;
  v_key := 'dating-photos/' || encode(extensions.gen_random_bytes(16), 'hex') || '.' || v_ext;
  -- The shared lock rule (M-9): a bounded retry, then dating:busy.
  FOR v_try IN 1..3 LOOP
    BEGIN
      INSERT INTO public.dating_photo_upload_intents (user_id, storage_key, mime_type, expires_at)
      VALUES (v_user, v_key, p_mime_type, now() + interval '15 minutes')
      RETURNING id, expires_at INTO v_id, v_expires;
      EXIT;
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE;
      END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'intent_id', v_id, 'storage_key', v_key,
                            'bucket', 'dating-profile-photos', 'expires_at', v_expires);
END;
$$;

DROP FUNCTION IF EXISTS public.insert_dating_profile_photo(uuid, smallint);
CREATE FUNCTION public.insert_dating_profile_photo(p_intent_id uuid, p_position smallint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_intent public.dating_photo_upload_intents;
  v_photo uuid;
  v_try integer;
BEGIN
  v_reason := private.dating_photo_setup_guard(); -- Spec 2 W3c (C): the setup lock (and the country's same-gender lock) first, retried
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  IF private.dating_photo_allowed(v_user) IS NOT TRUE THEN -- Spec 2 W3 final (M-7)
    RETURN jsonb_build_object('ok', false, 'reason', 'not_eligible'); -- Spec 2 W3 final (M-7)
  END IF; -- Spec 2 W3 final (M-7)
  IF p_position IS NULL OR p_position NOT BETWEEN 1 AND 6 THEN
    RETURN private.dating_invalid('position');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      SELECT * INTO v_intent FROM public.dating_photo_upload_intents AS i
       WHERE i.id = p_intent_id AND i.user_id = v_user AND i.used_at IS NULL AND i.expires_at > now()
         FOR UPDATE;
      IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'intent_unavailable');
      END IF;
      IF NOT EXISTS (SELECT 1 FROM storage.objects AS o
                      WHERE o.bucket_id = 'dating-profile-photos' AND o.name = v_intent.storage_key) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'object_missing');
      END IF;
      PERFORM 1 FROM public.dating_profiles AS p WHERE p.user_id = v_user FOR UPDATE;
      IF (SELECT count(*) FROM public.dating_profile_photos AS f
           WHERE f.user_id = v_user AND f.position <> p_position) >= 6 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'too_many');
      END IF;
      -- A slot replaced: its photo goes (its trigger queues the object's deletion).
      DELETE FROM public.dating_profile_photos AS f WHERE f.user_id = v_user AND f.position = p_position;
      UPDATE public.dating_photo_upload_intents AS i SET used_at = now() WHERE i.id = p_intent_id;
      INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state, csam_state)
      VALUES (v_user, v_intent.storage_key, p_position, 'pending', 'pending')
      RETURNING id INTO v_photo;
      INSERT INTO public.dating_photo_moderation_outbox (photo_id, user_id) VALUES (v_photo, v_user);
      -- A new photo must match the verification too.
      UPDATE public.dating_profiles AS p SET verification_state = 'needs_review'
       WHERE p.user_id = v_user AND p.verification_state = 'verified';
      EXIT;
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE;
      END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'photo_id', v_photo);
END;
$$;

DROP FUNCTION IF EXISTS public.list_dating_profile_photos();
CREATE FUNCTION public.list_dating_profile_photos()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  -- The owner's own photos; a CSAM hit reads as "unsafe", never named.
  RETURN jsonb_build_object(
    'ok', true,
    'photos', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'id', f.id, 'position', f.position, 'state', f.moderation_state,
               'reason', f.rejection_reason, 'caption', f.caption,
               'storage_key', f.storage_key, 'created_at', f.created_at) ORDER BY f.position)
        FROM public.dating_profile_photos AS f WHERE f.user_id = v_user), '[]'::jsonb),
    'after_mutual', coalesce((SELECT p.photos_after_mutual FROM public.dating_profiles AS p WHERE p.user_id = v_user), false),
    'after_mutual_from', (SELECT u.created_at + interval '30 days' FROM public.users AS u WHERE u.id = v_user));
END;
$$;

DROP FUNCTION IF EXISTS public.delete_dating_profile_photo(uuid);
CREATE FUNCTION public.delete_dating_profile_photo(p_photo_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '1s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  -- Exposure-reducing: never gated, idempotent.
  FOR v_try IN 1..3 LOOP
    BEGIN
      DELETE FROM public.dating_profile_photos AS f WHERE f.id = p_photo_id AND f.user_id = v_user;
      RETURN jsonb_build_object('ok', true);
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure OR query_canceled THEN
      NULL;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

CREATE OR REPLACE FUNCTION public.reorder_dating_photos(p_idempotency_key text, p_order uuid[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_mine uuid[];
  v_try integer;
BEGIN
  v_reason := private.dating_photo_setup_guard(); -- Spec 2 W3c (C): the guard's locks, retried
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  v_mine := ARRAY(SELECT f.id FROM public.dating_profile_photos AS f WHERE f.user_id = v_user ORDER BY f.id);
  IF p_order IS NULL OR cardinality(p_order) IS DISTINCT FROM cardinality(v_mine)
     OR array_position(p_order, NULL) IS NOT NULL
     OR ARRAY(SELECT x FROM unnest(p_order) AS x ORDER BY x) IS DISTINCT FROM v_mine THEN
    RETURN private.dating_invalid('order');
  END IF;
  IF NOT public.claim_dating_idempotency('reorder_dating_photos', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true);
  END IF;
  -- The shared lock rule (M-9): a bounded retry, then dating:busy.
  FOR v_try IN 1..3 LOOP
    BEGIN
      SET CONSTRAINTS public.dating_profile_photos_user_id_position_key DEFERRED;
      UPDATE public.dating_profile_photos AS f SET position = o.n
        FROM unnest(p_order) WITH ORDINALITY AS o(id, n)
       WHERE f.id = o.id AND f.user_id = v_user;
      SET CONSTRAINTS public.dating_profile_photos_user_id_position_key IMMEDIATE;
      EXIT;
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE;
      END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- A caption is shown only to its owner (§4.3; 09 P12): no filter but
-- length and invisible characters; blank clears.
CREATE OR REPLACE FUNCTION public.set_dating_photo_caption(p_photo_id uuid, p_caption text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '1s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_text text;
  v_try integer; -- Spec 2 W3c (C)
  v_found boolean; -- Spec 2 W3c (C)
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  IF char_length(p_caption) > 400 THEN
    RETURN private.dating_invalid('caption');
  END IF;
  v_text := nullif(private.dating_trim(coalesce(p_caption, '')), '');
  IF v_text IS NOT NULL AND (char_length(v_text) > 100 OR coalesce(private.dating_has_invisible(v_text), true)) THEN
    RETURN private.dating_invalid('caption');
  END IF;
  -- Spec 2 W3c (C): a row wait (the worker's own write) is retried (3), then dating:busy.
  FOR v_try IN 1..3 LOOP -- Spec 2 W3c (C)
    BEGIN -- Spec 2 W3c (C)
      UPDATE public.dating_profile_photos AS f SET caption = v_text WHERE f.id = p_photo_id AND f.user_id = v_user;
      v_found := FOUND; -- Spec 2 W3c (C)
      EXIT; -- Spec 2 W3c (C)
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W3c (C)
      IF v_try = 3 THEN -- Spec 2 W3c (C)
        RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; -- Spec 2 W3c (C)
      END IF; -- Spec 2 W3c (C)
    END; -- Spec 2 W3c (C)
  END LOOP; -- Spec 2 W3c (C)
  IF v_found IS NOT TRUE THEN -- Spec 2 W3c (C)
    RETURN private.dating_invalid('photo');
  END IF;
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- 3. process-dating-photo's CSAM outcome (I-10, R-25). A hit is final.
CREATE OR REPLACE FUNCTION public.record_dating_photo_csam(p_photo_id uuid, p_outcome text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s' -- Spec 2 W3c (C)
AS $$
DECLARE
  v_user uuid;
  v_try integer; -- Spec 2 W3c (C)
  v_found boolean; -- Spec 2 W3c (fix round 1, M-4)
  v_prev text; -- Spec 2 W3c (Task 9 fix round 1, M-5)
BEGIN
  IF p_outcome IS NULL OR p_outcome NOT IN ('clear', 'hit', 'error') THEN
    RETURN private.dating_invalid('outcome');
  END IF;
  -- Spec 2 W3c (C): the shared lock order, as exit and the setup writers:
  -- Spec 2 W3c (C) the person's setup lock (then the country's same-gender
  -- Spec 2 W3c (C) locks) before the photo row, so a hit's hold (which
  -- Spec 2 W3c (C) suspends the enrolment) never meets exit in a lock
  -- Spec 2 W3c (C) cycle; a bounded retry, then dating:busy (the job retries).
  SELECT f.user_id INTO v_user FROM public.dating_profile_photos AS f WHERE f.id = p_photo_id; -- Spec 2 W3c (C)
  IF NOT FOUND THEN -- Spec 2 W3c (C)
    RETURN jsonb_build_object('ok', false, 'reason', 'gone'); -- Spec 2 W3c (C)
  END IF; -- Spec 2 W3c (C)
  FOR v_try IN 1..3 LOOP -- Spec 2 W3c (C)
    BEGIN -- Spec 2 W3c (C)
      PERFORM private.dating_lock_setup(v_user); -- Spec 2 W3c (C)
      SELECT f.user_id, f.csam_state INTO v_user, v_prev FROM public.dating_profile_photos AS f WHERE f.id = p_photo_id FOR UPDATE; -- Spec 2 W3c (fix round 1, M-4): retried too; (Task 9 fix round 1, M-5): the state before
      v_found := FOUND; -- Spec 2 W3c (fix round 1, M-4)
      EXIT; -- Spec 2 W3c (C)
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W3c (C)
      IF v_try = 3 THEN -- Spec 2 W3c (C)
        RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; -- Spec 2 W3c (C)
      END IF; -- Spec 2 W3c (C)
    END; -- Spec 2 W3c (C)
  END LOOP; -- Spec 2 W3c (C)
  IF v_found IS NOT TRUE THEN -- Spec 2 W3c (fix round 1, M-4)
-- Spec 2 W3c (fix round 1, I-1): a hit answered 'gone' (the row deleted mid-scan) places no
-- Spec 2 W3c (fix round 1, I-1) Dating hold here: Task 9's worker records it (carry).
    RETURN jsonb_build_object('ok', false, 'reason', 'gone');
  END IF;
  IF p_outcome = 'hit' THEN
    UPDATE public.dating_profile_photos AS f
       SET csam_state = 'hit', moderation_state = 'rejected', rejection_reason = 'unsafe', reviewed_at = now()
     WHERE f.id = p_photo_id;
    IF NOT EXISTS (SELECT 1 FROM public.dating_account_restrictions AS r
                    WHERE r.user_id = v_user AND r.restriction_type = 'moderation_hold' AND r.lifted_at IS NULL
                      AND (r.ends_at IS NULL OR r.ends_at > now())) THEN
      -- W7a stamps category 'csam' and source 'csam_hash' (R-25).
      INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_user, 'moderation_hold');
    END IF;
    IF v_prev IS DISTINCT FROM 'hit' THEN -- Spec 2 W3c (Task 9 fix round 1, M-5): a redelivered hit is not counted again
      BEGIN -- Spec 2 W3c (Task 9 fix round 1, M-5)
        PERFORM private.bump_metric_internal('dating.photo.csam_hit'); -- Spec 2 W3c (Task 9 fix round 1, M-5)
      EXCEPTION WHEN OTHERS THEN -- Spec 2 W3c (Task 9 fix round 1, M-5)
        NULL; -- Spec 2 W3c (Task 9 fix round 1, M-5)
      END; -- Spec 2 W3c (Task 9 fix round 1, M-5)
    END IF; -- Spec 2 W3c (Task 9 fix round 1, M-5)
  ELSE
    UPDATE public.dating_profile_photos AS f SET csam_state = p_outcome
     WHERE f.id = p_photo_id AND f.csam_state IS DISTINCT FROM 'hit'
       AND NOT (p_outcome = 'error' AND f.csam_state = 'clear'); -- Spec 2 W3c (fix round 1, I-2): an error never undoes a clear scan
  END IF;
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- Spec 2 W3c (Task 9, B; R-25): a hit whose photo row is gone (deleted mid-scan) answers
-- Spec 2 W3c (Task 9, B) 'gone' above and holds nothing; process-dating-photo, which read
-- Spec 2 W3c (Task 9, B) the owner before the scan, places the same Dating hold here: one
-- Spec 2 W3c (Task 9, B) live moderation_hold (W7a stamps category and source), the person's
-- Spec 2 W3c (Task 9, B) setup lock first (exit's order: the hold suspends the enrolment,
-- Spec 2 W3c (Task 9, B) which exit locks first), a bounded retry, then dating:busy (the worker
-- Spec 2 W3c (Task 9, B) retries). An account that is itself gone answers 'gone'.
CREATE OR REPLACE FUNCTION public.record_dating_csam_hold(p_user uuid) -- Spec 2 W3c (Task 9, B)
RETURNS jsonb -- Spec 2 W3c (Task 9, B)
LANGUAGE plpgsql -- Spec 2 W3c (Task 9, B)
SECURITY DEFINER -- Spec 2 W3c (Task 9, B)
SET search_path = '' -- Spec 2 W3c (Task 9, B)
SET lock_timeout = '2s' -- Spec 2 W3c (Task 9, B)
AS $$
DECLARE -- Spec 2 W3c (Task 9, B)
  v_try integer; -- Spec 2 W3c (Task 9, B)
  v_new boolean := false; -- Spec 2 W3c (Task 9 fix round 1, M-5)
BEGIN -- Spec 2 W3c (Task 9, B)
  IF p_user IS NULL THEN -- Spec 2 W3c (Task 9, B)
    RETURN private.dating_invalid('user'); -- Spec 2 W3c (Task 9, B)
  END IF; -- Spec 2 W3c (Task 9, B)
  IF NOT EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = p_user) THEN -- Spec 2 W3c (Task 9, B)
    RETURN jsonb_build_object('ok', false, 'reason', 'gone'); -- Spec 2 W3c (Task 9, B)
  END IF; -- Spec 2 W3c (Task 9, B)
  FOR v_try IN 1..3 LOOP -- Spec 2 W3c (Task 9, B)
    BEGIN -- Spec 2 W3c (Task 9, B)
      v_new := false; -- Spec 2 W3c (Task 9 fix round 1, M-5): a rolled-back try placed nothing
      PERFORM private.dating_lock_setup(p_user); -- Spec 2 W3c (Task 9, B)
      IF NOT EXISTS (SELECT 1 FROM public.dating_account_restrictions AS r -- Spec 2 W3c (Task 9, B)
                      WHERE r.user_id = p_user AND r.restriction_type = 'moderation_hold' AND r.lifted_at IS NULL -- Spec 2 W3c (Task 9, B)
                        AND (r.ends_at IS NULL OR r.ends_at > now())) THEN -- Spec 2 W3c (Task 9, B)
        INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (p_user, 'moderation_hold'); -- Spec 2 W3c (Task 9, B)
        v_new := true; -- Spec 2 W3c (Task 9 fix round 1, M-5)
      END IF; -- Spec 2 W3c (Task 9, B)
      EXIT; -- Spec 2 W3c (Task 9, B)
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W3c (Task 9, B)
      IF v_try = 3 THEN -- Spec 2 W3c (Task 9, B)
        RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; -- Spec 2 W3c (Task 9, B)
      END IF; -- Spec 2 W3c (Task 9, B)
    WHEN foreign_key_violation THEN -- Spec 2 W3c (Task 9, B)
      RETURN jsonb_build_object('ok', false, 'reason', 'gone'); -- Spec 2 W3c (Task 9, B)
    END; -- Spec 2 W3c (Task 9, B)
  END LOOP; -- Spec 2 W3c (Task 9, B)
  IF v_new THEN -- Spec 2 W3c (Task 9 fix round 1, M-5): only the hold this call placed is counted
    BEGIN -- Spec 2 W3c (Task 9, B)
      PERFORM private.bump_metric_internal('dating.photo.csam_hit'); -- Spec 2 W3c (Task 9, B)
    EXCEPTION WHEN OTHERS THEN -- Spec 2 W3c (Task 9, B)
      NULL; -- Spec 2 W3c (Task 9, B)
    END; -- Spec 2 W3c (Task 9, B)
  END IF; -- Spec 2 W3c (Task 9 fix round 1, M-5)
  RETURN jsonb_build_object('ok', true); -- Spec 2 W3c (Task 9, B)
END; -- Spec 2 W3c (Task 9, B)
$$;

-- 4. The storage policies' predicates (R-2): definer reads of the person's
--    own rows, so the tables need no client SELECT.
CREATE OR REPLACE FUNCTION public.dating_storage_intent_open(p_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.dating_photo_upload_intents AS i
                  WHERE i.storage_key = p_name AND i.user_id = auth.uid()
                    AND i.used_at IS NULL AND i.expires_at > now());
$$;

CREATE OR REPLACE FUNCTION public.dating_storage_owns(p_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.dating_profile_photos AS f
                  WHERE f.storage_key = p_name AND f.user_id = auth.uid()
                    AND f.csam_state IS DISTINCT FROM 'hit' -- Spec 2 W3c (fix round 1, M-8): a match is never served, the owner included
                    AND NOT EXISTS (SELECT 1 FROM private.media_scan_queue AS q -- Spec 2 W3c (fix round 1, M-8): nor a quarantined object
                                     WHERE q.bucket = 'dating-profile-photos' AND q.object_name = p_name AND q.status = 'match'));
$$;

DROP POLICY IF EXISTS dating_profile_photos_insert_by_intent ON storage.objects;
CREATE POLICY dating_profile_photos_insert_by_intent ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'dating-profile-photos' AND public.dating_storage_intent_open(name));
DROP POLICY IF EXISTS dating_profile_photos_select_owner ON storage.objects;
CREATE POLICY dating_profile_photos_select_owner ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'dating-profile-photos' AND public.dating_storage_owns(name));

DROP POLICY IF EXISTS dating_profile_photos_select_own ON public.dating_profile_photos;
DROP POLICY IF EXISTS dating_photo_upload_intents_select_own ON public.dating_photo_upload_intents;

-- 5. Orphan uploads (I-14): an object uploaded under an intent that then
--    expired unused (no photo row) is scanned like a photo, CSAM first, by
--    process-dating-photo. Clear: deleted here. A match: recorded through
--    Spec 1's inline path, which quarantines a copy and deletes the
--    original (and keeps it when the copy failed: it is then the only
--    evidence). Nothing is deleted unscanned: a claim deletes nothing, and
--    a scan that can't answer releases the claim for a retry.
ALTER TABLE public.dating_photo_upload_intents ADD COLUMN IF NOT EXISTS orphan_claimed_at timestamptz;
ALTER TABLE public.dating_photo_upload_intents ADD COLUMN IF NOT EXISTS orphan_state text;
ALTER TABLE public.dating_photo_upload_intents ADD COLUMN IF NOT EXISTS orphan_attempts integer NOT NULL DEFAULT 0; -- Spec 2 W3c (fix round 1, M-10)
ALTER TABLE public.dating_photo_upload_intents DROP CONSTRAINT IF EXISTS dating_photo_upload_intents_orphan_state_check;
ALTER TABLE public.dating_photo_upload_intents ADD CONSTRAINT dating_photo_upload_intents_orphan_state_check
  CHECK (orphan_state IS NULL OR orphan_state IN ('swept', 'csam', 'stuck')); -- Spec 2 W3c (fix round 1, M-10): stuck
CREATE INDEX IF NOT EXISTS dating_photo_upload_intents_orphan_idx ON public.dating_photo_upload_intents (expires_at) -- Spec 2 W3c (fix round 1, I-3)
  WHERE used_at IS NULL AND orphan_state IS NULL; -- Spec 2 W3c (fix round 1, I-3): the sweep's candidates

CREATE OR REPLACE FUNCTION public.claim_dating_orphan_uploads(p_limit integer)
RETURNS TABLE (intent_id uuid, user_id uuid, storage_key text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 THEN
    RAISE EXCEPTION 'dating:invalid_limit' USING ERRCODE = '22023';
  END IF;
  -- Expired 15 minutes ago, never used, its object there, no photo row;
  -- a claim older than 10 minutes (a worker that died) is claimed again.
  RETURN QUERY
  WITH picked AS (
    SELECT i.id FROM public.dating_photo_upload_intents AS i
     WHERE i.used_at IS NULL AND i.orphan_state IS NULL
       AND i.expires_at < now() - interval '15 minutes'
       AND (i.orphan_claimed_at IS NULL OR i.orphan_claimed_at < now() - interval '10 minutes')
       AND EXISTS (SELECT 1 FROM storage.objects AS o
                    WHERE o.bucket_id = 'dating-profile-photos' AND o.name = i.storage_key)
       AND NOT EXISTS (SELECT 1 FROM public.dating_profile_photos AS f WHERE f.storage_key = i.storage_key)
     ORDER BY i.expires_at
     LIMIT p_limit
       FOR UPDATE OF i SKIP LOCKED)
  UPDATE public.dating_photo_upload_intents AS i SET orphan_claimed_at = now()
    FROM picked WHERE i.id = picked.id
  RETURNING i.id, i.user_id, i.storage_key;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_dating_orphan_scan(p_intent_id uuid, p_outcome text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s' -- Spec 2 W3c (fix round 1, I-1)
AS $$
DECLARE
  v_intent public.dating_photo_upload_intents;
  v_user uuid; -- Spec 2 W3c (fix round 1, I-1)
  v_try integer; -- Spec 2 W3c (fix round 1, I-1)
  v_found boolean; -- Spec 2 W3c (fix round 1, I-1)
  v_stuck boolean; -- Spec 2 W3c (fix round 1, M-10)
BEGIN
  IF p_outcome IS NULL OR p_outcome NOT IN ('clear', 'hit', 'error') THEN
    RETURN private.dating_invalid('outcome');
  END IF;
-- Spec 2 W3c (fix round 1, I-1): a match places the Dating hold, so it takes the person's
-- Spec 2 W3c (fix round 1, I-1) setup lock (then the country's) before the intent row, as exit
-- Spec 2 W3c (fix round 1, I-1) does (the hold suspends the enrolment, which exit locks first);
-- Spec 2 W3c (fix round 1, I-1) every lock a bounded retry, then dating:busy (the sweep retries).
  SELECT i.user_id INTO v_user FROM public.dating_photo_upload_intents AS i WHERE i.id = p_intent_id; -- Spec 2 W3c (fix round 1, I-1): unlocked
  FOR v_try IN 1..3 LOOP -- Spec 2 W3c (fix round 1, I-1)
    BEGIN -- Spec 2 W3c (fix round 1, I-1)
      IF p_outcome = 'hit' AND v_user IS NOT NULL THEN -- Spec 2 W3c (fix round 1, I-1)
        PERFORM private.dating_lock_setup(v_user); -- Spec 2 W3c (fix round 1, I-1)
      END IF; -- Spec 2 W3c (fix round 1, I-1)
      SELECT * INTO v_intent FROM public.dating_photo_upload_intents AS i WHERE i.id = p_intent_id FOR UPDATE; -- Spec 2 W3c (fix round 1, I-1): retried
      v_found := FOUND; -- Spec 2 W3c (fix round 1, I-1)
      EXIT; -- Spec 2 W3c (fix round 1, I-1)
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W3c (fix round 1, I-1)
      IF v_try = 3 THEN -- Spec 2 W3c (fix round 1, I-1)
        RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; -- Spec 2 W3c (fix round 1, I-1)
      END IF; -- Spec 2 W3c (fix round 1, I-1)
    END; -- Spec 2 W3c (fix round 1, I-1)
  END LOOP; -- Spec 2 W3c (fix round 1, I-1)
  IF v_found IS NOT TRUE OR v_intent.orphan_claimed_at IS NULL OR v_intent.orphan_state IS NOT NULL -- Spec 2 W3c (fix round 1, I-1)
     OR v_intent.used_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_claimed');
  END IF;
  IF p_outcome = 'error' THEN
    -- The matcher couldn't answer: nothing is deleted; the next sweep retries.
    UPDATE public.dating_photo_upload_intents AS i SET orphan_claimed_at = NULL WHERE i.id = p_intent_id;
-- Spec 2 W3c (fix round 1, M-10): five failed scans cap the retries: the object is kept
-- Spec 2 W3c (fix round 1, M-10) (never deleted unscanned), flagged stuck (never claimed
-- Spec 2 W3c (fix round 1, M-10) again) and counted for an operator.
    UPDATE public.dating_photo_upload_intents AS i -- Spec 2 W3c (fix round 1, M-10)
       SET orphan_attempts = i.orphan_attempts + 1, -- Spec 2 W3c (fix round 1, M-10)
           orphan_state = CASE WHEN i.orphan_attempts + 1 >= 5 THEN 'stuck' END -- Spec 2 W3c (fix round 1, M-10)
     WHERE i.id = p_intent_id -- Spec 2 W3c (fix round 1, M-10)
     RETURNING i.orphan_state IS NOT DISTINCT FROM 'stuck' INTO v_stuck; -- Spec 2 W3c (fix round 1, M-10)
    IF v_stuck THEN -- Spec 2 W3c (fix round 1, M-10)
      BEGIN -- Spec 2 W3c (fix round 1, M-10)
        PERFORM private.bump_metric_internal('dating.photo.orphan_scan_stuck'); -- Spec 2 W3c (fix round 1, M-10)
      EXCEPTION WHEN OTHERS THEN -- Spec 2 W3c (fix round 1, M-10)
        NULL; -- Spec 2 W3c (fix round 1, M-10)
      END; -- Spec 2 W3c (fix round 1, M-10)
    END IF; -- Spec 2 W3c (fix round 1, M-10)
  ELSIF p_outcome = 'clear' THEN
    -- Scanned clear: the object goes.
    PERFORM public.queue_media_deletion('dating-profile-photos', v_intent.storage_key);
    UPDATE public.dating_photo_upload_intents AS i SET orphan_state = 'swept' WHERE i.id = p_intent_id;
  ELSE
    -- A match: Spec 1's inline record (already made) owns the object's fate;
    -- nothing here deletes evidence.
    UPDATE public.dating_photo_upload_intents AS i SET orphan_state = 'csam' WHERE i.id = p_intent_id;
-- Spec 2 W3c (fix round 1, I-1): one live Dating moderation_hold, as a photo match (R-25),
-- Spec 2 W3c (fix round 1, I-1) stamped by phone, so it survives deleting the account.
    IF NOT EXISTS (SELECT 1 FROM public.dating_account_restrictions AS r -- Spec 2 W3c (fix round 1, I-1)
                    WHERE r.user_id = v_intent.user_id AND r.restriction_type = 'moderation_hold' AND r.lifted_at IS NULL -- Spec 2 W3c (fix round 1, I-1)
                      AND (r.ends_at IS NULL OR r.ends_at > now())) THEN -- Spec 2 W3c (fix round 1, I-1)
      INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_intent.user_id, 'moderation_hold'); -- Spec 2 W3c (fix round 1, I-1)
    END IF; -- Spec 2 W3c (fix round 1, I-1)
  END IF;
  BEGIN
    PERFORM private.bump_metric_internal(CASE p_outcome WHEN 'hit' THEN 'dating.photo.orphan_csam'
                                                        WHEN 'clear' THEN 'dating.photo.orphan_swept'
                                                        ELSE 'dating.photo.orphan_scan_error' END);
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- The sweep runs with process-dating-photo's own invocation (no photo id).
-- Spec 2 W3 final (I-1): guarded as the other Dating crons (unscheduled by
-- Spec 2 W3 final name, then scheduled), with the recovery every 5 minutes.
DO $unschedule$ -- Spec 2 W3 final (I-1)
BEGIN -- Spec 2 W3 final (I-1)
  PERFORM cron.unschedule(j.jobid) FROM cron.job AS j -- Spec 2 W3 final (I-1)
   WHERE j.jobname IN ('sweep-dating-photo-orphans', 'recover-stale-dating-photo-jobs'); -- Spec 2 W3 final (I-1)
END $unschedule$; -- Spec 2 W3 final (I-1)
SELECT cron.schedule('sweep-dating-photo-orphans', '*/15 * * * *',
  $cron$SELECT public.invoke_edge_function('process-dating-photo')$cron$);
SELECT cron.schedule('recover-stale-dating-photo-jobs', '*/5 * * * *', -- Spec 2 W3 final (I-1)
  $cron$SELECT public.recover_stale_dating_photo_jobs()$cron$); -- Spec 2 W3 final (I-1)

-- 5b. Spec 2 W3 final (I-1, I-2): the photo outbox's liveness. W3c made it
--     this bucket's only CSAM scan, so a job is never stranded: the
--     recovery (scheduled below, every 5 minutes) takes back a job whose
--     worker died and re-queues a photo dead-lettered unscanned; the claim
--     never overflows a job's attempts (a matcher that can't answer is
--     requeued, never dead-lettered, process-dating-photo). Re-created from
--     their live bodies (pg_get_functiondef on attune_spec3a); only the
--     marked lines change; grants are kept (CREATE OR REPLACE).
CREATE OR REPLACE FUNCTION public.recover_stale_dating_photo_jobs()
 RETURNS TABLE(recovered bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO '' -- Spec 2 W3 final (I-1): every name below is qualified
AS $function$
DECLARE
  v_count bigint;
  v_rescan bigint; -- Spec 2 W3 final (I-2)
BEGIN
  -- Spec 2 W3 final (I-1): a job a worker claimed and never finished (it
  -- Spec 2 W3 final died: the wall clock, memory, a failed finish) goes back
  -- Spec 2 W3 final to pending after its 10-minute lease, whatever its
  -- Spec 2 W3 final attempts: it may have seen a match, so the worker decides;
  -- Spec 2 W3 final never dead-lettered, nothing deleted. A row another
  -- Spec 2 W3 final session holds is skipped for the next run.
  UPDATE public.dating_photo_moderation_outbox
  SET state = 'pending', -- Spec 2 W3 final (I-1): never dead_letter
      processing_started_at = NULL,
      last_error_code = 'stale_lease',
      completed_at = NULL, -- Spec 2 W3 final (I-1)
      updated_at = now()
  WHERE photo_id IN (SELECT s.photo_id FROM public.dating_photo_moderation_outbox AS s -- Spec 2 W3 final (I-1)
                      WHERE s.state = 'processing' AND s.processing_started_at < now() - interval '10 minutes' -- Spec 2 W3 final (I-1): the lease
                        FOR UPDATE SKIP LOCKED); -- Spec 2 W3 final (I-1)
  GET DIAGNOSTICS v_count = ROW_COUNT;
  -- Spec 2 W3 final (I-2): a photo dead-lettered before its CSAM scan
  -- Spec 2 W3 final answered (needs_review with csam_state pending or error:
  -- Spec 2 W3 final no person may approve it) by an older worker goes back to
  -- Spec 2 W3 final the queue, to be scanned again. A clear one stays for a
  -- Spec 2 W3 final person; a hit is final.
  WITH dead AS ( -- Spec 2 W3 final (I-2)
    SELECT f.id FROM public.dating_profile_photos AS f -- Spec 2 W3 final (I-2)
      JOIN public.dating_photo_moderation_outbox AS o ON o.photo_id = f.id -- Spec 2 W3 final (I-2)
     WHERE o.state = 'dead_letter' AND f.moderation_state = 'needs_review' -- Spec 2 W3 final (I-2)
       AND f.csam_state IN ('pending', 'error') -- Spec 2 W3 final (I-2)
       FOR UPDATE OF f, o SKIP LOCKED -- Spec 2 W3 final (I-2)
  ), photos AS ( -- Spec 2 W3 final (I-2)
    UPDATE public.dating_profile_photos AS f -- Spec 2 W3 final (I-2)
       SET moderation_state = 'pending', rejection_reason = NULL, reviewed_at = NULL -- Spec 2 W3 final (I-2)
      FROM dead WHERE f.id = dead.id -- Spec 2 W3 final (I-2)
    RETURNING f.id -- Spec 2 W3 final (I-2)
  ) -- Spec 2 W3 final (I-2)
  UPDATE public.dating_photo_moderation_outbox AS o -- Spec 2 W3 final (I-2)
     SET state = 'pending', attempts = 0, last_error_code = 'rescan', processing_started_at = NULL, -- Spec 2 W3 final (I-2)
         completed_at = NULL, updated_at = now() -- Spec 2 W3 final (I-2)
    FROM photos WHERE o.photo_id = photos.id; -- Spec 2 W3 final (I-2)
  GET DIAGNOSTICS v_rescan = ROW_COUNT; -- Spec 2 W3 final (I-2)
  recovered := v_count + v_rescan; -- Spec 2 W3 final (I-2)
  RETURN NEXT;
END;
$function$;

CREATE OR REPLACE FUNCTION public.claim_dating_photo_jobs(p_limit integer DEFAULT 20, p_photo_id uuid DEFAULT NULL::uuid)
 RETURNS SETOF public.dating_photo_moderation_outbox -- Spec 2 W3 final (I-2): qualified
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO '' -- Spec 2 W3 final (I-2): every name below is qualified
AS $function$
  UPDATE public.dating_photo_moderation_outbox o
  SET state = 'processing',
      attempts = LEAST(attempts, 32766) + 1, -- Spec 2 W3 final (I-2): a job requeued forever never overflows the smallint
      processing_started_at = now(),
      updated_at = now(),
      last_error_code = NULL
  WHERE o.photo_id IN (
    SELECT photo_id FROM public.dating_photo_moderation_outbox
    WHERE state = 'pending'
      AND (p_photo_id IS NULL OR photo_id = p_photo_id)
    ORDER BY created_at
    FOR UPDATE SKIP LOCKED
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
  )
  RETURNING o.*;
$function$;

-- 5c. Spec 2 W3 final (M-3): the bucket takes only what the preparer sends
--     (1600 px, 1.5 MB JPEG): at most 2 MB, JPEG, PNG or WebP (the intent's
--     types), as the other media buckets; guarded, as they are, on the
--     storage schema having the columns.
CREATE OR REPLACE FUNCTION private.dating_photo_bucket_limits() -- Spec 2 W3 final (M-3)
RETURNS void -- Spec 2 W3 final (M-3)
LANGUAGE plpgsql -- Spec 2 W3 final (M-3)
SECURITY DEFINER -- Spec 2 W3 final (M-3)
SET search_path = '' -- Spec 2 W3 final (M-3)
AS $$ -- Spec 2 W3 final (M-3)
BEGIN -- Spec 2 W3 final (M-3)
  IF EXISTS (SELECT 1 FROM information_schema.columns AS c -- Spec 2 W3 final (M-3)
              WHERE c.table_schema = 'storage' AND c.table_name = 'buckets' AND c.column_name = 'file_size_limit') -- Spec 2 W3 final (M-3)
     AND EXISTS (SELECT 1 FROM information_schema.columns AS c -- Spec 2 W3 final (M-3)
                  WHERE c.table_schema = 'storage' AND c.table_name = 'buckets' AND c.column_name = 'allowed_mime_types') THEN -- Spec 2 W3 final (M-3)
    EXECUTE $q$UPDATE storage.buckets SET file_size_limit = 2097152, allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp'] WHERE id = 'dating-profile-photos'$q$; -- Spec 2 W3 final (M-3)
  END IF; -- Spec 2 W3 final (M-3)
END; -- Spec 2 W3 final (M-3)
$$; -- Spec 2 W3 final (M-3)
SELECT private.dating_photo_bucket_limits(); -- Spec 2 W3 final (M-3)

-- 5d. Spec 2 W3 final (M-5): the metadata strip re-uploads a clear photo's
--     object. Before it, process-dating-photo checks here, under the photo
--     row's lock, that the row is there with its key and a clear scan
--     (else nothing is uploaded); after it, that the row is still there. A
--     row gone by then (an owner delete, an exit, an account deletion; the
--     deletion drain may already have run) re-arms the object's deletion,
--     unless a CSAM match names the object (Spec 1's evidence is kept).
--     The service role's alone; one short statement each (no lock is held
--     across the upload).
CREATE OR REPLACE FUNCTION public.check_dating_photo_strip(p_photo_id uuid, p_storage_key text, p_phase text) -- Spec 2 W3 final (M-5)
RETURNS jsonb -- Spec 2 W3 final (M-5)
LANGUAGE plpgsql -- Spec 2 W3 final (M-5)
SECURITY DEFINER -- Spec 2 W3 final (M-5)
SET search_path = '' -- Spec 2 W3 final (M-5)
SET lock_timeout = '2s' -- Spec 2 W3 final (M-5)
AS $$ -- Spec 2 W3 final (M-5)
DECLARE -- Spec 2 W3 final (M-5)
  v_csam text; -- Spec 2 W3 final (M-5)
  v_found boolean := false; -- Spec 2 W3 final (M-5)
  v_try integer; -- Spec 2 W3 final (M-5)
BEGIN -- Spec 2 W3 final (M-5)
  IF p_phase IS NULL OR p_phase NOT IN ('before', 'after') THEN -- Spec 2 W3 final (M-5)
    RETURN private.dating_invalid('phase'); -- Spec 2 W3 final (M-5)
  END IF; -- Spec 2 W3 final (M-5)
  IF p_photo_id IS NULL OR p_storage_key IS NULL OR p_storage_key !~ '^dating-photos/[0-9a-f]{32}[.](jpg|png|webp)$' THEN -- Spec 2 W3 final (M-5)
    RETURN jsonb_build_object('ok', false, 'reason', 'gone'); -- Spec 2 W3 final (M-5)
  END IF; -- Spec 2 W3 final (M-5)
  FOR v_try IN 1..3 LOOP -- Spec 2 W3 final (M-5)
    BEGIN -- Spec 2 W3 final (M-5)
      SELECT f.csam_state INTO v_csam FROM public.dating_profile_photos AS f -- Spec 2 W3 final (M-5)
       WHERE f.id = p_photo_id AND f.storage_key = p_storage_key FOR UPDATE; -- Spec 2 W3 final (M-5)
      v_found := FOUND; -- Spec 2 W3 final (M-5)
      EXIT; -- Spec 2 W3 final (M-5)
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W3 final (M-5)
      IF v_try = 3 THEN -- Spec 2 W3 final (M-5)
        RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; -- Spec 2 W3 final (M-5)
      END IF; -- Spec 2 W3 final (M-5)
    END; -- Spec 2 W3 final (M-5)
  END LOOP; -- Spec 2 W3 final (M-5)
  IF v_found AND (p_phase = 'after' OR v_csam = 'clear') THEN -- Spec 2 W3 final (M-5)
    RETURN jsonb_build_object('ok', true); -- Spec 2 W3 final (M-5)
  END IF; -- Spec 2 W3 final (M-5)
  IF p_phase = 'after' AND NOT v_found -- Spec 2 W3 final (M-5)
     AND NOT EXISTS (SELECT 1 FROM public.dating_profile_photos AS f WHERE f.storage_key = p_storage_key) -- Spec 2 W3 final (M-5)
     AND NOT EXISTS (SELECT 1 FROM public.safety_escalations AS e -- Spec 2 W3 final (M-5)
                      WHERE e.kind = 'csam_match' AND e.bucket = 'dating-profile-photos' -- Spec 2 W3 final (M-5)
                        AND e.object_name = p_storage_key AND e.status <> 'closed') -- Spec 2 W3 final (M-5)
     AND NOT EXISTS (SELECT 1 FROM private.media_scan_queue AS q -- Spec 2 W3 final (M-5)
                      WHERE q.bucket = 'dating-profile-photos' AND q.object_name = p_storage_key AND q.status = 'match') THEN -- Spec 2 W3 final (M-5)
    INSERT INTO public.media_deletion_queue AS q (bucket_id, object_name) -- Spec 2 W3 final (M-5)
    VALUES ('dating-profile-photos', p_storage_key) -- Spec 2 W3 final (M-5)
    ON CONFLICT (bucket_id, object_name) DO UPDATE SET deleted_at = NULL, not_before = now(), requested_at = now(); -- Spec 2 W3 final (M-5)
    PERFORM private.bump_metric_internal('dating.photo.strip_after_delete'); -- Spec 2 W3 final (M-5)
  END IF; -- Spec 2 W3 final (M-5)
  RETURN jsonb_build_object('ok', false, 'reason', 'gone'); -- Spec 2 W3 final (M-5)
END; -- Spec 2 W3 final (M-5)
$$; -- Spec 2 W3 final (M-5)

-- 6. Spec 2 W3c (M-11; Task 3 review; R-43): has_data also counts the
--    person's photos and upload intents (profile or not), so Leave,
--    which deletes both, stays reachable. Re-created from its live body
--    (pg_get_functiondef on attune_spec3a); grants unchanged (revoked
--    below and in the twin).
CREATE OR REPLACE FUNCTION private.dating_has_data(p_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT p_user IS NOT NULL AND (
         EXISTS (SELECT 1 FROM public.dating_enrollments AS e WHERE e.user_id = p_user -- Spec 2 W3 final (M-4)
                    AND e.state IS DISTINCT FROM 'exited') -- Spec 2 W3 final (M-4): a kept 'exited' enrolment alone is nothing to leave
      OR EXISTS (SELECT 1 FROM public.dating_never_introduce AS x WHERE x.owner_user_id = p_user) -- Spec 2 W3 final (M-4): kept by choice; a second Leave deletes it
      OR EXISTS (SELECT 1 FROM public.dating_profiles AS p WHERE p.user_id = p_user)
      OR EXISTS (SELECT 1 FROM public.dating_gentle_wait_reflections AS r WHERE r.user_id = p_user)
      OR EXISTS (SELECT 1 FROM public.dating_notify_requests AS n WHERE n.user_id = p_user) -- Spec 2 W3c (M-11): no longer the last
      OR EXISTS (SELECT 1 FROM public.dating_profile_photos AS f WHERE f.user_id = p_user) -- Spec 2 W3c (M-11)
      OR EXISTS (SELECT 1 FROM public.dating_photo_upload_intents AS i WHERE i.user_id = p_user)); -- Spec 2 W3c (M-11)
$function$;

-- 7. Spec 2 W3c (Task 9 fix round 1, I-1; controller ruling): a CSAM hit's
--    object is never queued for deletion by a Dating path. The person's own
--    delete (the row trigger), exit (its upload intents name the same
--    objects) and account deletion (its own queue lines; the cascade runs
--    the trigger) still delete every row, so deletion is never blocked;
--    the object is left to Spec 1's record. Re-created from their live
--    bodies (pg_get_functiondef on attune_spec3a); only the marked lines
--    change; grants are kept (CREATE OR REPLACE).
CREATE OR REPLACE FUNCTION public.dating_photos_queue_media_before_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  -- Spec 2 W3c (Task 9 fix round 1, I-1): a CSAM hit's object is Spec 1's evidence: the row
  -- Spec 2 W3c (Task 9 fix round 1, I-1) goes, the object waits for Spec 1's record, which
  -- Spec 2 W3c (Task 9 fix round 1, I-1) queues it when quarantined and holds it otherwise.
  IF OLD.csam_state IS DISTINCT FROM 'hit' THEN -- Spec 2 W3c (Task 9 fix round 1, I-1)
    PERFORM public.queue_media_deletion('dating-profile-photos', OLD.storage_key); -- Spec 2 W3c (Task 9 fix round 1, I-1)
  ELSIF NOT EXISTS (SELECT 1 FROM public.safety_escalations AS e -- Spec 2 W3c (Task 9 fix round 2, I-4)
                     WHERE e.kind = 'csam_match' AND e.bucket = 'dating-profile-photos' -- Spec 2 W3c (Task 9 fix round 2, I-4)
                       AND e.object_name = OLD.storage_key AND e.status <> 'closed') THEN -- Spec 2 W3c (Task 9 fix round 2, I-4)
    -- Spec 2 W3c (Task 9 fix round 2, I-4): a hit no open escalation names (Spec 1's record
    -- Spec 2 W3c (Task 9 fix round 2, I-4) never landed): recorded unquarantined now, so a person
    -- Spec 2 W3c (Task 9 fix round 2, I-4) is told and the original is held as the evidence. The
    -- Spec 2 W3c (Task 9 fix round 2, I-4) account cascade included (escalations name no row), and
    -- Spec 2 W3c (Task 9 fix round 2, I-4) a failure never blocks the delete: it is counted.
    BEGIN -- Spec 2 W3c (Task 9 fix round 2, I-4)
      PERFORM public.record_inline_csam_match('dating-profile-photos', OLD.storage_key, OLD.user_id, -- Spec 2 W3c (Task 9 fix round 2, I-4)
                                             'dating_unrecorded', NULL, false, NULL); -- Spec 2 W3c (Task 9 fix round 2, I-4)
    EXCEPTION WHEN OTHERS THEN -- Spec 2 W3c (Task 9 fix round 2, I-4)
      PERFORM private.bump_metric_internal('dating.photo.csam_unrecorded'); -- Spec 2 W3c (Task 9 fix round 2, I-4)
    END; -- Spec 2 W3c (Task 9 fix round 2, I-4)
  END IF; -- Spec 2 W3c (Task 9 fix round 1, I-1)
  RETURN OLD;
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_exit_internal(p_user uuid, p_keep_never_introduce boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_found boolean;
  v_exited_at timestamptz;
BEGIN
  IF p_user IS NULL THEN
    RETURN;
  END IF;
  -- The row order: the enrolment before the profile (as activation, the
  -- pauses and the parked trigger).
  SELECT e.exited_at INTO v_exited_at FROM public.dating_enrollments AS e WHERE e.user_id = p_user FOR UPDATE;
  v_found := FOUND;
  -- Uploads never attached go with their storage objects; photo rows queue
  -- their own objects (dating_photos_queue_media_before_delete). Both go
  -- through queue_media_deletion, so the CSAM evidence guard holds back an
  -- object under an open, unquarantined match.
  PERFORM public.queue_media_deletion('dating-profile-photos', i.storage_key)
     FROM public.dating_photo_upload_intents AS i WHERE i.user_id = p_user -- Spec 2 W3c (Task 9 fix round 1, I-1): an intent names its photo's object
      AND NOT EXISTS (SELECT 1 FROM public.dating_profile_photos AS f -- Spec 2 W3c (Task 9 fix round 1, I-1)
                       WHERE f.storage_key = i.storage_key AND f.csam_state = 'hit'); -- Spec 2 W3c (Task 9 fix round 1, I-1): not a hit's
  DELETE FROM public.dating_photo_upload_intents AS i WHERE i.user_id = p_user;
  DELETE FROM public.dating_profile_photos AS f WHERE f.user_id = p_user;
  DELETE FROM public.dating_prompts AS q WHERE q.user_id = p_user;
  DELETE FROM public.dating_settings AS t WHERE t.user_id = p_user;
  DELETE FROM public.dating_profile_sensitive AS s WHERE s.user_id = p_user;
  DELETE FROM public.dating_preferences AS d WHERE d.user_id = p_user;
  DELETE FROM public.dating_profiles AS p WHERE p.user_id = p_user;
  DELETE FROM public.dating_date_reflections AS r WHERE r.author_user_id = p_user;
  DELETE FROM public.dating_session_context AS c WHERE c.user_id = p_user;
  DELETE FROM public.dating_notify_requests AS n WHERE n.user_id = p_user;
  IF to_regclass('public.dating_gentle_wait_reflections') IS NOT NULL THEN -- W2's table
    EXECUTE 'DELETE FROM public.dating_gentle_wait_reflections WHERE user_id = $1' USING p_user;
  END IF;
  IF NOT coalesce(p_keep_never_introduce, false) THEN
    DELETE FROM public.dating_never_introduce AS n WHERE n.owner_user_id = p_user;
  END IF;
  -- Conversations close for both and stay sealed for the evidence window.
  UPDATE public.dating_matches AS m
     SET state = 'closed', closed_reason = 'exit', closed_at = coalesce(m.closed_at, now()),
         evidence_until = now() + interval '30 days'
   WHERE p_user IN (m.user_low_id, m.user_high_id) AND m.state = 'active';
  -- Introductions go (their interest actions cascade; a match keeps its row).
  DELETE FROM public.dating_introductions AS i WHERE p_user IN (i.user_low_id, i.user_high_id);
  DELETE FROM public.dating_feature_snapshots AS f WHERE f.user_id = p_user;
  -- "When you left" (§3.8; fix round 1, I-1): every consent whose latest
  -- event is a grant is withdrawn now, on the server's clock, so coming back
  -- needs D4 again. Kept with the consents (Q17 exception 3). A second exit
  -- finds nothing standing and writes nothing (M-2).
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT p_user, 'exit:' || l.purpose || ':' || replace(gen_random_uuid()::text, '-', ''), l.purpose, 'withdrawn',
         l.policy_version, clock_timestamp()
    FROM (SELECT DISTINCT ON (c.purpose) c.purpose, c.action, c.policy_version
            FROM public.dating_consent_events AS c
           WHERE c.user_id = p_user
           ORDER BY c.purpose, c.occurred_at DESC, c.created_at DESC, (c.action = 'withdrawn') DESC) AS l
   WHERE l.action = 'granted';
  -- A suspension stays (only the data goes); a second exit keeps the first
  -- "when you left" (M-2).
  UPDATE public.dating_enrollments AS e
     SET state = CASE WHEN e.state = 'suspended' THEN 'suspended' ELSE 'exited' END,
         exited_at = coalesce(e.exited_at, now()), paused_at = NULL, pause_reason = NULL, updated_at = now()
   WHERE e.user_id = p_user;
  IF v_found AND v_exited_at IS NULL THEN
    PERFORM private.bump_metric_internal('dating.exit');
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.prepare_account_deletion(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_rel record;
  v_key_set boolean; -- Spec 2 W1a (PF-F6)
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'deletion:no_user';
  END IF;

  -- Spec 2 W1a (§6.3, R5): Dating carry-over, before anything is deleted.
  -- A missing key with a live restriction refuses (retried once the key is
  -- in Vault, PF-F6). The carry (records under each restriction's stamped
  -- HMAC, block pairs, report HMACs) runs; a failure there is counted and
  -- never refuses (W1 final fix, M-4). The auth.users trigger runs it again
  -- at the delete.
  v_key_set := public.dating_phone_hmac('attune:dating_exclusion_key:fingerprint:v1') IS NOT NULL;
  IF NOT v_key_set AND EXISTS (
       SELECT 1 FROM public.dating_account_restrictions AS dar
        WHERE dar.user_id = p_user_id AND dar.lifted_at IS NULL
          AND (dar.ends_at IS NULL OR dar.ends_at > now())) THEN
    RAISE EXCEPTION 'deletion:enforcement_key_missing';
  END IF;
  -- Spec 2 W1 final fix (M-4, PF-F6): only the missing key refuses; any
  -- Spec 2 W1 final fix other carry failure is counted and the deletion goes
  -- Spec 2 W1 final fix on (the auth.users trigger carries again at the
  -- Spec 2 W1 final fix delete, counting late_carry_failed if that fails too).
  BEGIN -- Spec 2 W1 final fix (M-4)
    PERFORM private.dating_deletion_carry(p_user_id, false);
  EXCEPTION WHEN OTHERS THEN -- Spec 2 W1 final fix (M-4)
    RAISE WARNING 'dating_deletion:carry:%', SQLSTATE; -- Spec 2 W1 final fix (M-4)
    PERFORM private.bump_metric_internal('dating.deletion.prepare_carry_failed'); -- Spec 2 W1 final fix (M-4)
  END; -- Spec 2 W1 final fix (M-4)
  -- Spec 1 W9d (O4): the Opinions strike count and live ban carry under
  -- Spec 1 W9d the HMACs stamped when they were placed. Never refuses
  -- Spec 1 W9d (PF-F6); the auth.users trigger carries again at the delete.
  BEGIN -- Spec 1 W9d
    PERFORM private.opinion_deletion_carry(p_user_id, false); -- Spec 1 W9d
  EXCEPTION WHEN OTHERS THEN -- Spec 1 W9d
    RAISE WARNING 'opinion_deletion:carry:%', SQLSTATE; -- Spec 1 W9d
    PERFORM private.bump_metric_internal('opinions.deletion.prepare_carry_failed'); -- Spec 1 W9d
  END; -- Spec 1 W9d
  -- 3. Matches close (account_deleted) and stay sealed for 30 days; the
  --    cascade sets their member ids to NULL (and its trigger seals any
  --    match this step missed, so a failure here warns and counts).
  BEGIN
    UPDATE public.dating_matches AS m
       SET state = CASE WHEN m.state = 'active' THEN 'closed' ELSE m.state END,
           closed_reason = CASE WHEN m.state = 'active' THEN 'account_deleted' ELSE m.closed_reason END,
           closed_at = coalesce(m.closed_at, now()),
           evidence_until = CASE WHEN m.state = 'active' OR m.evidence_until IS NULL
                                 THEN now() + interval '30 days' ELSE m.evidence_until END
     WHERE p_user_id IN (m.user_low_id, m.user_high_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'dating_deletion:matches:%', SQLSTATE;
    PERFORM private.bump_metric_internal('dating.deletion.step_failed.matches');
  END;
  -- 5. The cascade removes everything else (profile, photos via the media
  --    queue below, introductions, the never-introduce list, ...).

  FOR v_rel IN
    SELECT r.id, r.status FROM public.relationships r
    WHERE p_user_id IN (r.user_a, r.user_b)
    FOR UPDATE
  LOOP
    IF v_rel.status IN ('active', 'paused') THEN
      PERFORM public.relationship_end_internal(v_rel.id, p_user_id);
    ELSIF v_rel.status = 'pending' THEN
      DELETE FROM public.relationships WHERE id = v_rel.id;
      CONTINUE;
    END IF;

    -- What carries the person's answers or profile and cannot be split by
    -- person: games (positional answer_a/answer_b; rounds, per-user answers,
    -- Love map rounds and mirror truth go with them), 36-question journeys
    -- (AI text about the pair), the analysis sessions' role attribution, the
    -- profile-derived compatibility card. The partner's own game answers go
    -- with the shared sessions (D.3 #1 over D.2; review I1). Pulse,
    -- verdicts and patterns stay: role-free, both already saw them, the
    -- partner may export them in the window; the 12-month purge removes them.
    DELETE FROM public.game_sessions WHERE relationship_id = v_rel.id;
    DELETE FROM public.game_session_rounds WHERE relationship_id = v_rel.id;
    DELETE FROM public.thirty_six_question_journeys WHERE relationship_id = v_rel.id;
    DELETE FROM public.thirty_six_questions_seen WHERE relationship_id = v_rel.id;
    DELETE FROM public.game_questions_seen WHERE relationship_id = v_rel.id;
    DELETE FROM public.analysis_sessions WHERE relationship_id = v_rel.id;
    DELETE FROM public.attachment_compatibility_cache WHERE relationship_id = v_rel.id;
    DELETE FROM public.ask2_state WHERE relationship_id = v_rel.id;
  END LOOP;

  -- The person's own media. Their messages, clips and dating photos go in
  -- the cascade; queue now so nothing depends on trigger order there.
  PERFORM public.queue_media_deletion('message-media', m.media_url),
          public.queue_media_deletion('message-media', m.media_thumbnail_url)
  FROM public.messages m WHERE m.sender_id = p_user_id;
  PERFORM public.queue_media_deletion('message-media', c.media_url)
  FROM public.streak_clips c JOIN public.messages m ON m.id = c.message_id
  WHERE m.sender_id = p_user_id;
  PERFORM public.queue_media_deletion('dating-profile-photos', p.storage_key)
  FROM public.dating_profile_photos p WHERE p.user_id = p_user_id -- Spec 2 W3c (Task 9 fix round 1, I-1)
    AND p.csam_state IS DISTINCT FROM 'hit'; -- Spec 2 W3c (Task 9 fix round 1, I-1): a hit's object is Spec 1's
  -- Uploads never attached to anything: no row names them (review I5).
  PERFORM public.queue_media_deletion('message-media', i.storage_key)
  FROM public.message_media_upload_intents i WHERE i.requester_id = p_user_id;
  PERFORM public.queue_media_deletion('dating-profile-photos', i.storage_key)
  FROM public.dating_photo_upload_intents i WHERE i.user_id = p_user_id -- Spec 2 W3c (Task 9 fix round 1, I-1)
    AND NOT EXISTS (SELECT 1 FROM public.dating_profile_photos AS f -- Spec 2 W3c (Task 9 fix round 1, I-1)
                     WHERE f.storage_key = i.storage_key AND f.csam_state = 'hit'); -- Spec 2 W3c (Task 9 fix round 1, I-1)
  PERFORM public.queue_media_deletion('story-media', i.storage_key)
  FROM public.story_media_upload_intents i WHERE i.requester_id = p_user_id;
  PERFORM public.queue_media_deletion('relationship-avatars', i.storage_key)
  FROM public.relationship_avatar_upload_intents i WHERE i.requester_id = p_user_id;
  -- Their downloads (Spec 3c; data_export_jobs is created in 20261018120000,
  -- resolved when this runs): every part of every job goes now, then the jobs.
  IF to_regclass('public.data_export_jobs') IS NOT NULL THEN
    EXECUTE $q$
      UPDATE public.media_deletion_queue q SET not_before = now(), deleted_at = NULL
      FROM public.data_export_jobs j
      WHERE j.user_id = $1 AND q.bucket_id = 'data-exports' AND q.object_name LIKE j.id::text || '/%'
    $q$ USING p_user_id;
    EXECUTE 'DELETE FROM public.data_export_jobs WHERE user_id = $1' USING p_user_id;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.record_dating_photo_csam(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_dating_csam_hold(uuid) FROM PUBLIC, anon, authenticated; -- Spec 2 W3c (Task 9, B)
-- Spec 2 W3c: the other server-only objects too (the twin repeats it).
REVOKE ALL ON FUNCTION public.claim_dating_orphan_uploads(integer) FROM PUBLIC, anon, authenticated; -- Spec 2 W3c
REVOKE ALL ON FUNCTION public.record_dating_orphan_scan(uuid, text) FROM PUBLIC, anon, authenticated; -- Spec 2 W3c
REVOKE ALL ON FUNCTION private.dating_photo_setup_guard() FROM PUBLIC, anon, authenticated, service_role; -- Spec 2 W3c (C)
REVOKE ALL ON FUNCTION private.dating_has_data(uuid) FROM PUBLIC, anon, authenticated, service_role; -- Spec 2 W3c (M-11)
REVOKE ALL ON FUNCTION private.dating_photo_hit_final() FROM PUBLIC, anon, authenticated, service_role; -- Spec 2 W3c (fix round 1, M-7)
REVOKE ALL ON FUNCTION private.dating_photo_allowed(uuid) FROM PUBLIC, anon, authenticated, service_role; -- Spec 2 W3 final (M-7)
REVOKE ALL ON FUNCTION private.dating_photo_bucket_limits() FROM PUBLIC, anon, authenticated, service_role; -- Spec 2 W3 final (M-3)
REVOKE ALL ON FUNCTION public.check_dating_photo_strip(uuid, text, text) FROM PUBLIC, anon, authenticated; -- Spec 2 W3 final (M-5)

COMMIT;
