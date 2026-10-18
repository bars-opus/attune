-- Spec 3a (research 06 §3 F1; 05 Part D): Ending v2 lifecycle.
--   active -> paused -> active (either member); active|paused -> ended
--   (either); paused 30 days -> ended (system); ended -> archived after 30
--   days, when both have sealed, or when either starts a new relationship.
-- No transition queues a push, SMS or email for anyone (F1 (1)).
-- Plan: docs/superpowers/plans/2026-10-18-spec3a-ending-lifecycle.md.

-- ---------------------------------------------------------------------
-- 1. States, reasons, pause columns.
-- ---------------------------------------------------------------------
ALTER TABLE public.relationships DROP CONSTRAINT IF EXISTS relationships_status_check;
ALTER TABLE public.relationships ADD CONSTRAINT relationships_status_check
  CHECK (status IN ('pending', 'active', 'paused', 'ended', 'archived'));

ALTER TABLE public.relationships DROP CONSTRAINT IF EXISTS relationships_chat_archived_reason_check;
ALTER TABLE public.relationships ADD CONSTRAINT relationships_chat_archived_reason_check
  CHECK (chat_archived_reason IS NULL OR chat_archived_reason IN (
    'partner_new_relationship', 'manual_end', 'window_closed', 'both_sealed'
  ));

ALTER TABLE public.relationships
  ADD COLUMN IF NOT EXISTS paused_at timestamptz,
  ADD COLUMN IF NOT EXISTS paused_by uuid REFERENCES public.users(id) ON DELETE SET NULL;

-- R3-7: the old end_relationship archived at once; those rows are archived.
UPDATE public.relationships SET status = 'archived'
WHERE status = 'ended' AND chat_archived_at IS NOT NULL;

-- ---------------------------------------------------------------------
-- 2. Per-person seals; the Healing Stage 2 snapshot.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.relationship_seals (
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  sealed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (relationship_id, user_id)
);
ALTER TABLE public.relationship_seals ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS relationship_seals_self_read ON public.relationship_seals;
CREATE POLICY relationship_seals_self_read ON public.relationship_seals
  FOR SELECT TO authenticated USING (user_id = auth.uid());

-- No FK to relationships: the snapshot outlives the relationship's deletion,
-- so Healing Stage 2 keeps its evidence (D.4 (a)). Owned by the user.
CREATE TABLE IF NOT EXISTS public.healing_ending_snapshots (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  relationship_id uuid NOT NULL,
  pattern_types text[] NOT NULL DEFAULT '{}',
  taken_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, relationship_id)
);
ALTER TABLE public.healing_ending_snapshots ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS healing_ending_snapshots_self_read ON public.healing_ending_snapshots;
CREATE POLICY healing_ending_snapshots_self_read ON public.healing_ending_snapshots
  FOR SELECT TO authenticated USING (user_id = auth.uid());

-- ---------------------------------------------------------------------
-- 3. The one chat read test (R3-4, R3-5): member, not archived, active or
--    paused or within 30 days of ending, and not sealed by the caller.
-- ---------------------------------------------------------------------
-- Evaluated per candidate row by the chat policies (review I7). Postgres
-- cannot inline it (the EXISTS is a sub-select), so it stays SECURITY
-- DEFINER, which skips a second RLS pass over relationships: two primary-key
-- probes per row, after the relationship_id index has narrowed the rows.
CREATE OR REPLACE FUNCTION public.relationship_chat_open_for(p_relationship_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = p_relationship_id
      AND p_user_id IS NOT NULL
      AND p_user_id IN (r.user_a, r.user_b)
      AND r.chat_archived_at IS NULL
      AND (r.status IN ('active', 'paused')
           OR (r.status = 'ended' AND r.ended_at > now() - interval '30 days'))
      AND NOT EXISTS (
        SELECT 1 FROM public.relationship_seals s
        WHERE s.relationship_id = r.id AND s.user_id = p_user_id
      )
  );
$$;

-- The caller's form, used by every chat and chapter policy. Spec 3c's export
-- (service role, no auth.uid()) asks relationship_chat_open_for directly.
CREATE OR REPLACE FUNCTION public.relationship_chat_open(p_relationship_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.relationship_chat_open_for(p_relationship_id, auth.uid());
$$;

-- ---------------------------------------------------------------------
-- 4. Internals (no client EXECUTE).
-- ---------------------------------------------------------------------

-- R3-2: nothing queued for the relationship goes out after it stops being
-- active. Personal rows (no relationship in metadata) are left alone.
CREATE OR REPLACE FUNCTION public.relationship_cancel_pending_pushes(p_relationship_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  -- source_key cleared so a resume can enqueue the same occurrence again
  -- (the key's unique index covers every row; review I3). Reminder rows
  -- written before 20261018100300 carry only reminder_id (review I2).
  UPDATE public.scheduled_notifications
  SET status = 'cancelled', source_key = NULL,
      last_error = 'relationship_lifecycle', updated_at = now()
  WHERE status = 'pending'
    AND (
      metadata->>'relationship_id' = p_relationship_id::text
      OR (metadata->>'type' = 'reminder_upcoming'
          AND metadata->>'reminder_id' IN (
            SELECT rm.id::text FROM public.reminders rm
            WHERE rm.relationship_id = p_relationship_id))
    );
  DELETE FROM public.message_notification_outbox
  WHERE relationship_id = p_relationship_id AND state = 'pending';
END;
$$;

-- R3-8: role-free, non-safety pattern types, the same query the post-mortem
-- makes today, one row per member.
CREATE OR REPLACE FUNCTION public.relationship_take_healing_snapshot(p_relationship_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_types text[];
BEGIN
  SELECT coalesce(array_agg(t.pattern_type), '{}') INTO v_types
  FROM (
    SELECT p.pattern_type
    FROM public.patterns p
    WHERE p.relationship_id = p_relationship_id AND p.severity <> 'safety'
    ORDER BY p.last_seen_at DESC
    LIMIT 6
  ) t;
  INSERT INTO public.healing_ending_snapshots (user_id, relationship_id, pattern_types)
  SELECT m.uid, p_relationship_id, v_types
  FROM public.relationships r
  CROSS JOIN LATERAL (VALUES (r.user_a), (r.user_b)) AS m(uid)
  WHERE r.id = p_relationship_id AND m.uid IS NOT NULL
  ON CONFLICT (user_id, relationship_id) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.relationship_archive(p_relationship_id uuid, p_reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  UPDATE public.relationships
  SET status = 'archived',
      chat_archived_at = now(),
      chat_archived_reason = p_reason
  WHERE id = p_relationship_id AND status <> 'archived';
  PERFORM public.relationship_cancel_pending_pushes(p_relationship_id);
END;
$$;

-- The end itself, shared by end_relationship (actor = caller), the 30-day
-- pause expiry and the new-chapter trigger (actor NULL: the system ended it).
-- The caller has already locked and checked the row.
CREATE OR REPLACE FUNCTION public.relationship_end_internal(p_relationship_id uuid, p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  UPDATE public.relationships
  SET status = 'ended',
      ended_at = now(),
      ended_by = p_actor,
      paused_at = NULL,
      paused_by = NULL
  WHERE id = p_relationship_id AND status IN ('active', 'paused');
  IF NOT FOUND THEN
    RETURN;
  END IF;

  PERFORM public.relationship_cancel_pending_pushes(p_relationship_id);
  PERFORM public.relationship_take_healing_snapshot(p_relationship_id);

  -- Recorded in the same transaction as the status change (20260931130000):
  -- an exclusion written only on a best-effort second call could be lost
  -- exactly when it matters. Wrapped so it cannot fail the end itself.
  BEGIN
    PERFORM public.record_dating_former_partner_exclusion(p_relationship_id, true);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'exclusion not recorded for %: %', p_relationship_id, sqlerrm;
  END;
END;
$$;

-- ---------------------------------------------------------------------
-- 5. Client RPCs.
-- ---------------------------------------------------------------------

-- Locks the caller's own relationship row, or raises lifecycle:not_found.
CREATE OR REPLACE FUNCTION public.relationship_lock_mine(p_relationship_id uuid)
RETURNS public.relationships
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_rel public.relationships;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'lifecycle:not_found';
  END IF;
  SELECT * INTO v_rel FROM public.relationships r
  WHERE r.id = p_relationship_id AND auth.uid() IN (r.user_a, r.user_b)
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'lifecycle:not_found';
  END IF;
  RETURN v_rel;
END;
$$;

CREATE OR REPLACE FUNCTION public.pause_relationship(p_relationship_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_rel public.relationships := public.relationship_lock_mine(p_relationship_id);
BEGIN
  IF v_rel.status <> 'active' THEN
    RAISE EXCEPTION 'lifecycle:not_active';
  END IF;
  UPDATE public.relationships
  SET status = 'paused', paused_at = now(), paused_by = auth.uid()
  WHERE id = p_relationship_id;
  PERFORM public.relationship_cancel_pending_pushes(p_relationship_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.resume_relationship(p_relationship_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_rel public.relationships := public.relationship_lock_mine(p_relationship_id);
BEGIN
  -- Past the 30 days the decision has been made (review I12).
  IF v_rel.status <> 'paused' OR v_rel.paused_at <= now() - interval '30 days' THEN
    RAISE EXCEPTION 'lifecycle:not_paused';
  END IF;
  UPDATE public.relationships
  SET status = 'active', paused_at = NULL, paused_by = NULL
  WHERE id = p_relationship_id;
END;
$$;

-- Restated (latest 20260931130000): from active or paused; the chat is NOT
-- archived (the 30-day window, R3-3); no push anywhere (R3-2).
CREATE OR REPLACE FUNCTION public.end_relationship(p_relationship_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_rel public.relationships := public.relationship_lock_mine(p_relationship_id);
BEGIN
  IF v_rel.status NOT IN ('active', 'paused') THEN
    RAISE EXCEPTION 'lifecycle:not_active';
  END IF;
  PERFORM public.relationship_end_internal(p_relationship_id, auth.uid());
END;
$$;

-- R3-4: per person and final. The second seal archives for both.
CREATE OR REPLACE FUNCTION public.seal_my_side(p_relationship_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_rel public.relationships := public.relationship_lock_mine(p_relationship_id);
BEGIN
  IF v_rel.status <> 'ended' THEN
    RAISE EXCEPTION 'lifecycle:not_ended';
  END IF;
  INSERT INTO public.relationship_seals (relationship_id, user_id)
  VALUES (p_relationship_id, auth.uid())
  ON CONFLICT (relationship_id, user_id) DO NOTHING;
  IF NOT EXISTS (
    SELECT 1
    FROM (VALUES (v_rel.user_a), (v_rel.user_b)) AS m(uid)
    WHERE m.uid IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.relationship_seals s
        WHERE s.relationship_id = p_relationship_id AND s.user_id = m.uid
      )
  ) THEN
    PERFORM public.relationship_archive(p_relationship_id, 'both_sealed');
  END IF;
END;
$$;

-- R3-9: the caller's latest non-pending relationship when it is paused,
-- ended or archived; nothing when it is active. Never says whether the
-- other person sealed.
CREATE OR REPLACE FUNCTION public.get_my_relationship_lifecycle()
RETURNS TABLE (
  relationship_id uuid,
  status text,
  partner_first_name text,
  ended_by_me boolean,
  ended_by_partner boolean,
  paused_by_me boolean,
  ended_at timestamptz,
  window_ends_at timestamptz,
  paused_at timestamptz,
  decide_by timestamptz,
  sealed_by_me boolean,
  chat_readable boolean
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  WITH latest AS (
    SELECT r.*
    FROM public.relationships r
    WHERE auth.uid() IS NOT NULL
      AND auth.uid() IN (r.user_a, r.user_b)
      AND r.status <> 'pending'
    ORDER BY r.created_at DESC
    LIMIT 1
  )
  SELECT
    l.id,
    l.status,
    -- A name, never a phone number (an unnamed account's display_name is
    -- its phone): NULL then, and the app says "Your partner".
    CASE WHEN split_part(btrim(p.display_name), ' ', 1) ~ '^\+?[0-9 ()-]*$' THEN NULL
         ELSE split_part(btrim(p.display_name), ' ', 1) END,
    coalesce(l.ended_by = auth.uid(), false),
    coalesce(l.ended_by IS NOT NULL AND l.ended_by <> auth.uid(), false),
    coalesce(l.paused_by = auth.uid(), false),
    l.ended_at,
    l.ended_at + interval '30 days',
    l.paused_at,
    l.paused_at + interval '30 days',
    EXISTS (SELECT 1 FROM public.relationship_seals s
            WHERE s.relationship_id = l.id AND s.user_id = auth.uid()),
    public.relationship_chat_open(l.id)
  FROM latest l
  LEFT JOIN public.users p
    ON p.id = CASE WHEN l.user_a = auth.uid() THEN l.user_b ELSE l.user_a END
  -- An archive older than 30 days is history, not news: no standing line on
  -- the screen about starting fresh (final review IMP-3).
  WHERE l.status IN ('paused', 'ended')
     OR (l.status = 'archived' AND l.chat_archived_at > now() - interval '30 days');
$$;

-- ---------------------------------------------------------------------
-- 6. The clock (F1 (3), (4)).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.close_relationship_windows()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_id uuid;
BEGIN
  FOR v_id IN
    SELECT r.id FROM public.relationships r
    WHERE r.status = 'paused' AND r.paused_at <= now() - interval '30 days'
    FOR UPDATE SKIP LOCKED
  LOOP
    PERFORM public.relationship_end_internal(v_id, NULL);
  END LOOP;
  FOR v_id IN
    SELECT r.id FROM public.relationships r
    WHERE r.status = 'ended' AND r.ended_at <= now() - interval '30 days'
    FOR UPDATE SKIP LOCKED
  LOOP
    PERFORM public.relationship_archive(v_id, 'window_closed');
  END LOOP;
END;
$$;

DO $$
BEGIN
  PERFORM cron.unschedule('close_relationship_windows')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'close_relationship_windows');
END $$;
SELECT cron.schedule(
  'close_relationship_windows', '23 * * * *',   -- hourly: the clock is the copy's promise (review I12)
  $$ SELECT public.close_relationship_windows(); $$
);

-- ---------------------------------------------------------------------
-- 7. A new relationship archives either member's old chapter (R3-6).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.relationship_archive_on_new_chapter()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_old record;
BEGIN
  FOR v_old IN
    SELECT r.id, r.status FROM public.relationships r
    WHERE r.id <> NEW.id
      AND r.status IN ('ended', 'paused')
      AND (r.user_a IN (NEW.user_a, NEW.user_b) OR r.user_b IN (NEW.user_a, NEW.user_b))
    FOR UPDATE
  LOOP
    IF v_old.status = 'paused' THEN
      PERFORM public.relationship_end_internal(v_old.id, NULL);
    END IF;
    PERFORM public.relationship_archive(v_old.id, 'partner_new_relationship');
  END LOOP;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS relationship_archive_on_new_chapter ON public.relationships;
CREATE TRIGGER relationship_archive_on_new_chapter
  AFTER UPDATE OF status ON public.relationships
  FOR EACH ROW
  WHEN (OLD.status = 'pending' AND NEW.status = 'active')
  EXECUTE FUNCTION public.relationship_archive_on_new_chapter();

-- ---------------------------------------------------------------------
-- 8. Healing starts on an archived relationship too (R3-8). Restated from
--    the live definition (20260703193000); only the status test changes.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_or_create_healing_journey(p_relationship_id uuid DEFAULT NULL::uuid, p_breakup_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_breakup_at_source text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_relationship public.relationships%ROWTYPE;
  v_existing uuid;
  v_breakup_at timestamptz;
  v_source text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '28000';
  END IF;

  IF p_relationship_id IS NOT NULL THEN
    SELECT * INTO v_relationship
    FROM public.relationships
    WHERE id = p_relationship_id
      AND status IN ('ended', 'archived')
      AND (user_a = v_user_id OR user_b = v_user_id);

    IF NOT FOUND THEN
      RAISE EXCEPTION 'relationship_not_found' USING ERRCODE = '22023';
    END IF;

    v_breakup_at := v_relationship.ended_at;
    v_source := 'relationship';

    SELECT id INTO v_existing
    FROM public.healing_journeys
    WHERE user_id = v_user_id
      AND relationship_id = p_relationship_id
    LIMIT 1;
  ELSE
    IF p_breakup_at IS NULL OR p_breakup_at_source <> 'user_reported' THEN
      RAISE EXCEPTION 'invalid_breakup_context' USING ERRCODE = '22023';
    END IF;
    v_breakup_at := p_breakup_at;
    v_source := 'user_reported';

    SELECT id INTO v_existing
    FROM public.healing_journeys
    WHERE user_id = v_user_id
      AND relationship_id IS NULL
      AND status IN ('active', 'paused')
    LIMIT 1;
  END IF;

  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  INSERT INTO public.healing_journeys (
    user_id,
    relationship_id,
    breakup_at,
    breakup_at_source,
    status,
    current_stage
  ) VALUES (
    v_user_id,
    p_relationship_id,
    v_breakup_at,
    v_source,
    'active',
    1
  )
  RETURNING id INTO v_existing;

  RETURN v_existing;
END;
$function$

;
