-- Cross-spec sync audit (2026-10-18; .superpowers/sdd/2026-10-18-sync-audit.md):
-- where one spec's rules had not reached another's, for functions that
-- already shipped. Grants in 20261018160010.

-- C-2. Spec 3a made a pause reversible; the couple map's purge still treated
-- it as an ending and deleted every story pin. Live presence still goes on
-- any non-active status (it is live location); story pins only at an ending
-- or archive. Restates 20261017100000.
CREATE OR REPLACE FUNCTION public.presence_purge_on_relationship_close()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF (NEW.status IS DISTINCT FROM OLD.status AND NEW.status <> 'active')
     OR (OLD.chat_archived_at IS NULL AND NEW.chat_archived_at IS NOT NULL) THEN
    DELETE FROM public.partner_presence WHERE relationship_id = NEW.id;
  END IF;
  IF (NEW.status IS DISTINCT FROM OLD.status AND NEW.status IN ('ended', 'archived'))
     OR (OLD.chat_archived_at IS NULL AND NEW.chat_archived_at IS NOT NULL) THEN
    DELETE FROM public.story_places WHERE relationship_id = NEW.id;
  END IF;
  RETURN NULL;
END $$;

-- M-7. A pause no longer cancels a WhatsApp import or the partner's consent;
-- an ending or archive still does. Restates 20260705190000.
CREATE OR REPLACE FUNCTION public.cancel_chat_imports_on_relationship_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_job record;
BEGIN
  IF NOT (NEW.status IN ('ended', 'archived') OR NEW.chat_archived_at IS NOT NULL) THEN
    RETURN NEW;
  END IF;
  FOR v_job IN
    SELECT j.id, j.request_id
    FROM public.chat_import_jobs j
    WHERE j.relationship_id = NEW.id
      AND j.state IN ('processing', 'processing_safety', 'failed')
  LOOP
    DELETE FROM public.messages WHERE import_job_id = v_job.id;
    PERFORM public.remove_import_derived_evidence(v_job.id);
    UPDATE public.chat_import_jobs
    SET state = 'revoked', deleted_at = now(), error_code = 'relationship_inactive'
    WHERE id = v_job.id;
    UPDATE public.chat_import_requests SET state = 'revoked'
    WHERE id = v_job.request_id;
  END LOOP;
  UPDATE public.chat_import_requests
  SET state = 'revoked'
  WHERE relationship_id = NEW.id
    AND state IN ('pending_partner_consent', 'approved');
  UPDATE public.relationships r
  SET message_count = (
    SELECT count(*) FROM public.messages m WHERE m.relationship_id = r.id
  )
  WHERE r.id = NEW.id;
  RETURN NEW;
END;
$function$;

-- M-3. Only ordinary messages count toward Ask-2: no pause, note, notice
-- or deleted row. Restates 20260721121000.
CREATE OR REPLACE FUNCTION public.ask2_eligibility(p_relationship_id uuid)
 RETURNS TABLE(eligible boolean, first_positive_message_id uuid, first_positive_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rel public.relationships%ROWTYPE;
  v_user_a_count int;
  v_user_b_count int;
  v_day_count int;
  v_first_positive_id uuid;
  v_first_positive_at timestamptz;
BEGIN
  SELECT * INTO v_rel FROM public.relationships WHERE id = p_relationship_id;

  IF NOT FOUND OR v_rel.user_b IS NULL OR v_rel.status <> 'active' THEN
    RETURN QUERY SELECT false, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;

  SELECT count(*) INTO v_user_a_count
  FROM public.messages
  WHERE relationship_id = p_relationship_id AND sender_id = v_rel.user_a
    AND media_type IS NULL AND NOT is_system_notice AND deleted_at IS NULL;

  SELECT count(*) INTO v_user_b_count
  FROM public.messages
  WHERE relationship_id = p_relationship_id AND sender_id = v_rel.user_b
    AND media_type IS NULL AND NOT is_system_notice AND deleted_at IS NULL;

  IF v_user_a_count < 30 OR v_user_b_count < 30 THEN
    RETURN QUERY SELECT false, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;

  -- Distinct UTC days on which both wrote (a coarse, timezone-agnostic
  -- proxy; see 20260721121000).
  SELECT count(*) INTO v_day_count
  FROM (
    SELECT (created_at::date) AS day
    FROM public.messages
    WHERE relationship_id = p_relationship_id
      AND media_type IS NULL AND NOT is_system_notice AND deleted_at IS NULL
    GROUP BY 1
    HAVING bool_or(sender_id = v_rel.user_a) AND bool_or(sender_id = v_rel.user_b)
  ) qualifying_days;

  IF v_day_count < 3 THEN
    RETURN QUERY SELECT false, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;

  SELECT id, created_at INTO v_first_positive_id, v_first_positive_at
  FROM public.messages
  WHERE relationship_id = p_relationship_id AND sentiment = 'positive'
    AND media_type IS NULL AND NOT is_system_notice AND deleted_at IS NULL
  ORDER BY created_at ASC
  LIMIT 1;

  IF v_first_positive_id IS NULL THEN
    RETURN QUERY SELECT false, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;

  RETURN QUERY SELECT true, v_first_positive_id, v_first_positive_at;
END;
$function$;

-- I-8. Nobody already in an active relationship joins another (an active
-- person could hold two). A paused one is left to Spec 3a's Decision 19
-- (a new chapter ends and archives it, relationship_archive_on_new_chapter);
-- accept-invite and create-relationship-invite refuse a paused person,
-- since the app's accept path asks for no confirmation.
CREATE OR REPLACE FUNCTION public.relationship_one_open_chapter_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF OLD.status = 'pending' AND NEW.status = 'active' AND EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id <> NEW.id
      AND r.status = 'active'
      AND (r.user_a IN (NEW.user_a, NEW.user_b) OR r.user_b IN (NEW.user_a, NEW.user_b))
  ) THEN
    RAISE EXCEPTION 'relationship:already_open';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS relationship_one_open_chapter_guard ON public.relationships;
CREATE TRIGGER relationship_one_open_chapter_guard
  BEFORE UPDATE OF status ON public.relationships
  FOR EACH ROW EXECUTE FUNCTION public.relationship_one_open_chapter_guard();

-- M-8. Low-sensitivity rows the new specs left without an end: finished
-- export jobs a month after they expired, the per-day translator counter
-- after a week, a lapsed private check a month after it lapsed, device
-- labels of sessions that no longer exist, and private Pulse scores whose
-- relationship is gone. (Healing snapshots stay: the healing journey reads
-- them after the relationship is purged.)
CREATE OR REPLACE FUNCTION public.purge_stale_personal_rows()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  DELETE FROM public.data_export_jobs
  WHERE status IN ('ready', 'failed')
    AND coalesce(expires_at, requested_at) < now() - interval '30 days';
  DELETE FROM public.translator_daily_use WHERE day < current_date - 7;
  DELETE FROM public.safety_self_checks
  WHERE until < now() - interval '30 days'
    AND (positive_until IS NULL OR positive_until < now() - interval '30 days');
  DELETE FROM public.session_devices d
  WHERE d.updated_at < now() - interval '30 days'
    AND NOT EXISTS (SELECT 1 FROM auth.sessions s WHERE s.id = d.session_id);
  DELETE FROM public.pulse_private_scores p
  WHERE p.relationship_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.relationships r WHERE r.id = p.relationship_id);
END $$;

DO $$
BEGIN
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'purge-stale-personal-rows';
END;
$$;
SELECT cron.schedule(
  'purge-stale-personal-rows',
  '27 4 * * *',
  $$ SELECT public.purge_stale_personal_rows(); $$
);
